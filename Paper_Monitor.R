# ==================================================
# Paper_Monitor.R — Interactive command-line tool for the paper monitoring pipeline
# Run with: Rscript Paper_Monitor.R
# ==================================================

script_arg  <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- sub("^--file=", "", script_arg)
if (!file.exists(script_path)) {
  # Some launchers (e.g. macOS Shortcuts "Run Shell Script") mangle spaces in
  # file paths into the literal sequence "~+~" before invoking Rscript.
  unmangled_path <- gsub("~\\+~", " ", script_path, fixed = FALSE)
  if (file.exists(unmangled_path)) script_path <- unmangled_path
}
setwd(dirname(normalizePath(script_path)))

# --------------------------------------------------
# Stdin primitive (needed below for the package-install prompt, before the
# rest of the menu primitives are defined further down)
# --------------------------------------------------
# menu()/readline() require interactive()==TRUE, which is FALSE under plain
# Rscript. Reading the stdin connection directly works regardless.

.stdin_con <- file("stdin", "r")

read_stdin_line <- function() {
  line <- readLines(con = .stdin_con, n = 1)
  if (length(line) == 0) {
    # EOF on stdin (e.g. piped input exhausted) — no more input is ever
    # coming, so exit rather than spin forever re-reading EOF.
    cat("\nEnd of input, exiting.\n")
    quit(save = "no", status = 0)
  }
  trimws(line)
}

# --------------------------------------------------
# Required package check
# --------------------------------------------------

REQUIRED_PACKAGES <- c("xml2", "dplyr", "purrr", "httr2", "jsonlite", "tibble", "stringr")

missing_packages <- REQUIRED_PACKAGES[!vapply(REQUIRED_PACKAGES, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("Missing required R package(s):", paste(missing_packages, collapse = ", "), "\n")
  cat("Install now? [y/N]: ")
  ans <- tolower(read_stdin_line())
  if (!ans %in% c("y", "yes")) {
    cat("Cannot continue without required packages. Exiting.\n")
    quit(save = "no", status = 1)
  }
  install.packages(missing_packages)
  still_missing <- missing_packages[!vapply(missing_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still_missing) > 0) {
    cat("Failed to install: ", paste(still_missing, collapse = ", "), ". Exiting.\n")
    quit(save = "no", status = 1)
  }
}

suppressPackageStartupMessages({
  library(xml2)
  library(dplyr)
  library(purrr)
  library(httr2)
  library(jsonlite)
  library(tibble)
  library(stringr)
})

source("R/config_layer.R")
source("R/rss_layer.R")
source("R/prompt_layer.R")
source("R/llm_layer.R")
source("R/cli_ui_layer.R")
source("R/llm_provider_layer.R")
source("R/profile_interview_layer.R")
source("R/initial_setup_layer.R")
source("R/scoring_layer.R")
source("R/output_layer.R")
source("R/pipeline_layer.R")

# --------------------------------------------------
# Startup LLM connection check
# --------------------------------------------------

check_llm_status_on_startup <- function(is_run_mode) {
  cfg <- read_json_config(file.path(CONFIG_DIR, "llm_config.json"), default = NULL)

  if (is.null(cfg) || !nzchar(cfg$backend %||% "")) {
    cat("LLM backend: not configured.\n")
    if (is_run_mode) {
      stop("LLM connection is not configured. Run `Rscript Paper_Monitor.R` to set up the LLM backend.")
    }
    return(invisible(NULL))
  }

  cat("Checking LLM connection (backend:", cfg$backend, ")...\n")
  res <- test_llm_connection(cfg)
  if (isTRUE(res$success)) {
    cat("LLM connection OK:", res$message, "\n")
  } else {
    cat("LLM connection FAILED:", res$message, "\n")
    if (is_run_mode) {
      stop("LLM connection failed. Run `Rscript Paper_Monitor.R` to set up the LLM backend.")
    }
  }
}

# --------------------------------------------------
# Menu primitives
# --------------------------------------------------

prompt_text <- function(label, default = "") {
  cat(sprintf("%s [%s]: ", label, default))
  ans <- read_stdin_line()
  if (!nzchar(ans)) default else ans
}

prompt_yes_no <- function(label, default = FALSE) {
  d <- if (default) "Y/n" else "y/N"
  cat(sprintf("%s [%s]: ", label, d))
  ans <- tolower(read_stdin_line())
  if (!nzchar(ans)) return(default)
  ans %in% c("y", "yes")
}

# --------------------------------------------------
# Run pipeline now
# --------------------------------------------------

action_run_pipeline <- function(fail_on_error = FALSE) {
  res <- tryCatch(
    run_daily_papers_from_config(
      progress_cb = function(message, detail = NULL, value = NULL) cat(">>", message, "\n")
    ),
    error = function(e) {
      cat("Pipeline error:", conditionMessage(e), "\n")
      if (isTRUE(fail_on_error)) stop(e)
      NULL
    }
  )
  invisible(res)
}

# --------------------------------------------------
# RSS feeds submenu
# --------------------------------------------------

feed_item_labels <- function(feeds, status) {
  if (nrow(feeds) == 0) return(character())
  feeds$parser_type <- ifelse(is_specialized_parser(feeds$parser), "specialized", "fallback")
  if (nrow(status) > 0) {
    feeds <- dplyr::left_join(
      feeds,
      dplyr::select(status, journal, success, item_count, message, timestamp),
      by = "journal"
    )
  }
  vapply(seq_len(nrow(feeds)), function(i) {
    last_message <- if ("message" %in% names(feeds)) feeds$message[[i]] else NA_character_
    if (is.na(last_message) || !nzchar(last_message)) last_message <- "(never run)"
    sprintf(
      "[%s] %-45s parser=%-11s last=%s",
      if (isTRUE(feeds$enabled[i])) "x" else " ",
      feeds$journal[i],
      feeds$parser_type[i],
      last_message
    )
  }, character(1))
}

RSS_LIBRARY_PAGE_SIZE <- 10L

rss_library_item_labels <- function(library, selected_ids, feeds) {
  configured <- rss_library_is_configured(library, feeds)
  vapply(seq_len(nrow(library)), function(i) {
    marker <- if (configured[i]) "[added]" else if (library$library_id[i] %in% selected_ids) "[x]" else "[ ]"
    sprintf("%-7s %-14s %s", marker, library$publisher[i], library$journal[i])
  }, character(1))
}

action_add_feeds_from_library <- function(feeds) {
  library <- tryCatch(load_rss_library(), error = function(e) e)
  if (inherits(library, "error")) {
    cat("RSS library could not be loaded:", conditionMessage(library), "\n")
    return(invisible(NULL))
  }
  if (nrow(library) == 0) {
    cat("RSS library is empty. You can still add a feed manually.\n")
    return(invisible(NULL))
  }

  query <- ""
  page <- 1L
  selected_ids <- integer()

  repeat {
    matches <- search_rss_library(library, query)
    page_count <- max(1L, ceiling(nrow(matches) / RSS_LIBRARY_PAGE_SIZE))
    page <- min(max(1L, page), page_count)
    first <- (page - 1L) * RSS_LIBRARY_PAGE_SIZE + 1L
    last <- min(nrow(matches), page * RSS_LIBRARY_PAGE_SIZE)
    page_rows <- if (nrow(matches) == 0) matches else matches[first:last, , drop = FALSE]

    commands <- c(
      s = "Search",
      if (length(selected_ids) > 0) c(a = sprintf("Add selected (%d)", length(selected_ids))) else character(),
      if (page < page_count) c(n = "Next page") else character(),
      if (page > 1L) c(p = "Previous page") else character(),
      m = "Add RSS URL manually",
      b = "Back"
    )
    info <- c(
      sprintf("Search: %s", if (nzchar(query)) query else "(all journals)"),
      sprintf("Selected: %d  Page: %d/%d  Matches: %d", length(selected_ids), page, page_count, nrow(matches)),
      "Select a number to toggle it. [added] entries are already configured."
    )
    if (nrow(matches) == 0) info <- c(info, "No journals match this search.")

    nav <- prompt_cli_page(
      "RSS Library",
      rss_library_item_labels(page_rows, selected_ids, feeds),
      commands,
      info
    )

    if (identical(nav$kind, "select")) {
      selected <- page_rows[nav$value, , drop = FALSE]
      if (rss_library_is_configured(selected, feeds)) {
        cat("This journal is already in your feeds.\n")
      } else if (selected$library_id %in% selected_ids) {
        selected_ids <- setdiff(selected_ids, selected$library_id)
      } else {
        selected_ids <- c(selected_ids, selected$library_id)
      }
      next
    }
    if (identical(nav$value, "s")) {
      query <- prompt_text("Search journals or publishers")
      page <- 1L
    } else if (identical(nav$value, "n")) {
      page <- page + 1L
    } else if (identical(nav$value, "p")) {
      page <- page - 1L
    } else if (identical(nav$value, "a")) {
      selected <- dplyr::filter(library, library_id %in% selected_ids)
      result <- add_rss_library_feeds(feeds, selected)
      if (result$added > 0) save_feeds_config(result$feeds)
      cat(sprintf("Added %d RSS feed%s.\n", result$added, if (result$added == 1L) "" else "s"))
      if (result$skipped > 0) cat(sprintf("Skipped %d already-configured feed%s.\n", result$skipped, if (result$skipped == 1L) "" else "s"))
      return(invisible(result$feeds))
    } else if (identical(nav$value, "m")) {
      action_add_feed(feeds)
      return(invisible(load_feeds_config()))
    } else {
      return(invisible(feeds))
    }
  }
}

action_manage_feeds <- function(exit_commands = c(b = "Back"), setup_mode = FALSE) {
  library_offered <- FALSE
  repeat {
    feeds  <- load_feeds_config()
    status <- read_feed_status()
    has_enabled_feed <- nrow(feeds) > 0 && any(feeds$enabled)

    if (isTRUE(setup_mode) && !library_offered && !has_enabled_feed) {
      library_offered <- TRUE
      action_add_feeds_from_library(feeds)
      next
    }

    info <- if (nrow(feeds) == 0) {
      "Choose journals from the RSS library or add an RSS URL manually."
    } else if (isTRUE(setup_mode) && has_enabled_feed) {
      "At least one feed is enabled. Choose Continue setup when ready."
    } else {
      character()
    }
    commands <- c(
      a = "Add from library",
      m = "Add RSS URL manually",
      if (isTRUE(setup_mode) && has_enabled_feed) c(d = "Continue setup") else character(),
      exit_commands
    )
    nav <- prompt_cli_page("RSS Feeds", feed_item_labels(feeds, status), commands, info)
    if (identical(nav$value, "d")) return(invisible("d"))
    if (identical(nav$value, "a")) { action_add_feeds_from_library(feeds); next }
    if (identical(nav$value, "m")) { action_add_feed(feeds); next }
    if (nav$value %in% names(exit_commands)) return(invisible(nav$value))
    action_feed_detail(feeds, nav$value)
  }
}

action_feed_detail <- function(feeds, row) {
  feed <- feeds[row, ]
  info <- c(
    paste("Journal:", feed$journal), paste("RSS URL:", feed$rss_url),
    paste("Parser:", feed$parser), paste("Enabled:", isTRUE(feed$enabled))
  )
  repeat {
    nav <- prompt_cli_page("RSS Feed Detail", character(), c(e = "Toggle enabled", t = "Test", d = "Delete", b = "Back"), info)
    if (identical(nav$value, "b")) return(invisible(NULL))
    if (identical(nav$value, "e")) {
      feeds$enabled[row] <- !isTRUE(feeds$enabled[row]); save_feeds_config(feeds); cat("Updated.\n"); return(invisible(NULL))
    }
    if (identical(nav$value, "d")) {
      if (prompt_yes_no(sprintf("Delete '%s'?", feed$journal))) {
        save_feeds_config(feeds[-row, ]); cat("Deleted.\n")
      }
      return(invisible(NULL))
    }
    res <- tryCatch(
      test_fetch_feed(feed$journal, feed$rss_url, feed$parser, feed$parser_arg),
      error = function(e) list(data = NULL, status = list(message = conditionMessage(e)))
    )
    prompt_cli_page(
      "RSS Feed Test", character(), c(b = "Back"),
      c(paste("Status:", res$status$message), rss_preview_lines(res$data))
    )
  }
}

# --------------------------------------------------
# Add a new RSS feed
# --------------------------------------------------

rss_preview_lines <- function(data) {
  if (is.null(data) || nrow(data) == 0) return("Preview: no articles parsed.")
  c("Preview:", capture.output(print(data)))
}

action_add_feed <- function(feeds) {
  rss_url <- ""
  while (!nzchar(rss_url)) {
    rss_url <- prompt_text("RSS URL")
    if (!nzchar(rss_url)) cat("RSS URL is required.\n")
  }

  probe <- tryCatch(probe_rss_url(rss_url), error = function(e) NULL)
  if (is.null(probe)) {
    cat("Could not fetch or parse this RSS URL. Nothing was saved.\n")
    return(invisible(NULL))
  }

  journal <- probe$suggested_journal
  parser <- probe$recommended_parser

  repeat {
    attempt <- probe$attempts[[parser]]
    preview <- attempt$data
    if (!is.null(preview) && "journal" %in% names(preview)) preview$journal <- journal

    parser_labels <- vapply(names(probe$attempts), function(name) {
      candidate <- probe$attempts[[name]]
      sprintf("%s — score %.1f; %s", name, candidate$quality, candidate$status$message)
    }, character(1))
    commands <- c(
      if (isTRUE(attempt$status$success)) c(s = "Confirm and save") else character(),
      e = "Edit journal name", p = "Choose another parser", c = "Discard"
    )
    action <- prompt_cli_page(
      "Add RSS Feed", character(), commands,
      c(
        paste("Suggested journal name:", journal),
        paste("Recommended parser:", probe$recommended_parser),
        paste("Selected parser:", parser),
        paste("Status:", attempt$status$message),
        rss_preview_lines(preview)
      )
    )
    if (identical(action$value, "s")) {
      new_row <- tibble::tibble(
        journal = journal, rss_url = rss_url, parser = parser,
        parser_arg = NA_character_, enabled = TRUE
      )
      feeds <- dplyr::bind_rows(feeds, new_row)
      save_feeds_config(feeds)
      cat("Saved.\n")
      return(invisible(NULL))
    } else if (identical(action$value, "e")) {
      journal <- prompt_text("Journal name", journal)
      if (!nzchar(journal)) journal <- probe$suggested_journal
      next
    } else if (identical(action$value, "p")) {
      parser_nav <- prompt_cli_page("RSS Parser", parser_labels, c(b = "Back"), "Choose a parser without downloading the feed again.")
      if (!identical(parser_nav$value, "b")) parser <- names(probe$attempts)[parser_nav$value]
      next
    } else {
      cat("Not saved.\n")
      return(invisible(NULL))
    }
  }
}

# --------------------------------------------------
# LLM provider settings
# --------------------------------------------------

# Per-provider remembered settings (model/api_key/base_url/url), kept
# separately from llm_config.json so a switch does not leak another
# provider's defaults into the new configuration.
LLM_BACKENDS_FILE <- file.path(CONFIG_DIR, "llm_backends.json")

read_llm_backends <- function() read_json_config(LLM_BACKENDS_FILE, default = list())

save_llm_backend <- function(key, fields) {
  backends <- read_llm_backends()
  backends[[key]] <- fields
  write_json_config(backends, LLM_BACKENDS_FILE)
}

llm_config_summary <- function(cfg) {
  provider_id <- llm_provider_from_config(cfg)
  provider_label <- if (is.null(provider_id)) "Unknown" else llm_provider(provider_id)$label
  c(paste("Provider:", provider_label), paste("Model:", cfg$model %||% ""),
    if (isTRUE(cfg$use_batch)) "Mode: Batch API" else character())
}

prompt_llm_model <- function(provider, default_model = "") {
  if (isTRUE(provider$model_input_only)) {
    model <- ""
    while (!nzchar(model)) {
      model <- prompt_text("Ollama model name", default_model)
      if (!nzchar(model)) cat("A model name is required.\n")
    }
    return(model)
  }
  items <- provider$models
  commands <- c(c = "Custom model name", b = "Back")
  nav <- prompt_cli_page("Select Model", items, commands, paste("Provider:", provider$label))
  if (identical(nav$value, "b")) return(NULL)
  if (identical(nav$value, "c")) {
    model <- ""
    while (!nzchar(model)) {
      model <- prompt_text("Custom model name", default_model)
      if (!nzchar(model)) cat("A model name is required.\n")
    }
    return(model)
  }
  items[[nav$value]]
}

prompt_llm_provider_config <- function(current_cfg = NULL, exit_commands = c(b = "Back")) {
  exit_key <- names(exit_commands)[[1]]
  repeat {
    provider_nav <- prompt_cli_page("LLM Provider", llm_provider_labels(), exit_commands)
    if (identical(provider_nav$value, exit_key)) return(NULL)
    provider_id <- llm_provider_ids()[provider_nav$value]
    provider <- llm_provider(provider_id)
    remembered <- read_llm_backends()[[provider_id]] %||% list()
    if (identical(provider_id, llm_provider_from_config(current_cfg))) remembered <- modifyList(remembered, current_cfg)

    model <- prompt_llm_model(provider, remembered$model %||% "")
    if (is.null(model)) next
    api_key <- if (isTRUE(provider$requires_api_key)) prompt_text("API Key", remembered$api_key %||% "") else ""
    use_batch <- if (identical(provider_id, "anthropic")) {
      prompt_yes_no("Use Batch API?", isTRUE(remembered$use_batch))
    } else FALSE
    custom_base_url <- if (identical(provider_id, "custom_openai_compatible")) {
      prompt_text("Base URL", remembered$base_url %||% "")
    } else ""
    ollama_url <- if (identical(provider_id, "ollama")) remembered$url %||% OLLAMA_DEFAULT_URL else OLLAMA_DEFAULT_URL
    max_tokens <- suppressWarnings(as.integer(remembered$max_tokens %||% 1024L))
    if (is.na(max_tokens) || max_tokens < 1L) max_tokens <- 1024L

    return(new_llm_provider_config(provider_id, model, api_key, max_tokens, custom_base_url, ollama_url, use_batch))
  }
}

edit_ollama_endpoint <- function(cfg) {
  endpoint <- prompt_text("Ollama endpoint URL", cfg$url %||% OLLAMA_DEFAULT_URL)
  if (nzchar(endpoint)) cfg$url <- endpoint
  cfg
}

save_llm_config <- function(cfg) {
  provider_id <- llm_provider_from_config(cfg)
  write_json_config(cfg, file.path(CONFIG_DIR, "llm_config.json"))
  save_llm_backend(provider_id %||% normalize_backend(cfg$backend), cfg)
  cat("Saved to config/llm_config.json\n")
  invisible(cfg)
}

review_llm_provider_config <- function(cfg, exit_commands = c(b = "Back")) {
  repeat {
    commands <- c(t = "Test connection", s = "Save without testing", if (identical(llm_provider_from_config(cfg), "ollama")) c(a = "Advanced endpoint") else character(), c = "Discard")
    action <- prompt_cli_page("Review LLM Settings", character(), commands, llm_config_summary(cfg))
    if (identical(action$value, "a")) { cfg <- edit_ollama_endpoint(cfg); next }
    if (identical(action$value, "c")) return(FALSE)
    if (identical(action$value, "s")) { save_llm_config(cfg); return(TRUE) }
    res <- test_llm_connection(cfg)
    cat(if (res$success) "OK: " else "FAILED: ", res$message, "\n", sep = "")
    if (isTRUE(res$success)) {
      save_llm_config(cfg)
      return(TRUE)
    }
    retry <- prompt_cli_page("LLM Connection Failed", character(), c(e = "Edit configuration", s = "Save and test later", c = "Discard"), "The settings were not changed yet.")
    if (identical(retry$value, "s")) { save_llm_config(cfg); return(TRUE) }
    if (identical(retry$value, "c")) return(FALSE)
    return(review_llm_provider_config(prompt_llm_provider_config(cfg, exit_commands) %||% cfg, exit_commands))
  }
}

action_llm_settings <- function(setup_mode = FALSE) {
  exit_commands <- if (setup_mode) c(c = "Cancel initial setup") else c(b = "Back")
  cfg <- read_json_config(file.path(CONFIG_DIR, "llm_config.json"), default = NULL)
  if (!is.null(cfg) && llm_config_is_configured(cfg)) {
    existing <- prompt_cli_page("LLM Settings", character(), c(k = "Keep existing settings", r = "Reconfigure", t = "Test connection", exit_commands), llm_config_summary(cfg))
    if (identical(existing$value, names(exit_commands)[[1]]) || identical(existing$value, "k")) return(invisible(NULL))
    if (identical(existing$value, "t")) {
      res <- test_llm_connection(cfg)
      cat(if (res$success) "OK: " else "FAILED: ", res$message, "\n", sep = "")
      return(invisible(res))
    }
  }
  new_cfg <- prompt_llm_provider_config(cfg, exit_commands)
  if (is.null(new_cfg)) return(invisible(NULL))
  review_llm_provider_config(new_cfg, exit_commands)
  invisible(NULL)
}

# --------------------------------------------------
# Output settings submenu
# --------------------------------------------------

action_output_settings <- function(exit_commands = c(b = "Back")) {
  exit_key <- names(exit_commands)[[1]]
  cfg <- read_json_config(file.path(CONFIG_DIR, "output_config.json"), default = list(
    output_folder = "", filename_pattern = "Daily_Papers_%s.md", max_papers = 25, recommendation_threshold = 50
  ))
  cfg <- list(
    output_folder = cfg$output_folder %||% "",
    filename_pattern = cfg$filename_pattern %||% "Daily_Papers_%s.md",
    max_papers = cfg$max_papers %||% 25,
    recommendation_threshold = cfg$recommendation_threshold %||% 50
  )

  save_cfg <- function() {
    write_json_config(cfg, file.path(CONFIG_DIR, "output_config.json"))
    cat("Saved to config/output_config.json\n")
  }

  repeat {
    fields <- c(
      sprintf("Output folder: %s", cfg$output_folder),
      sprintf("Filename pattern: %s", cfg$filename_pattern),
      sprintf("Max papers per run: %s", cfg$max_papers),
      sprintf("Recommendation threshold: %s", cfg$recommendation_threshold)
    )
    nav <- prompt_cli_page("Output Settings", fields, exit_commands)
    if (identical(nav$value, exit_key)) return(invisible(NULL))
    field <- nav$value

    if (field == 1) {
      folder <- prompt_text("Output folder", cfg$output_folder)
      if (!dir.exists(folder)) {
        if (prompt_yes_no(sprintf("'%s' doesn't exist. Create it?", folder), default = TRUE)) {
          dir.create(folder, recursive = TRUE)
          cfg$output_folder <- folder
          save_cfg()
        } else {
          cat("Not saved (folder doesn't exist).\n")
        }
      } else {
        cfg$output_folder <- folder
        save_cfg()
      }
    } else if (field == 2) {
      current_prefix <- sub("%s\\.md$", "", cfg$filename_pattern)
      new_prefix <- prompt_text("Filename prefix (before %s.md)", current_prefix)
      cfg$filename_pattern <- paste0(new_prefix, "%s.md")
      save_cfg()
    } else if (field == 3) {
      max_papers <- suppressWarnings(as.integer(prompt_text("Max papers per run", as.character(cfg$max_papers))))
      if (is.na(max_papers)) max_papers <- 25L
      cfg$max_papers <- max_papers
      save_cfg()
    } else if (field == 4) {
      recommendation_threshold <- suppressWarnings(as.integer(prompt_text("Recommendation threshold (score)", as.character(cfg$recommendation_threshold))))
      if (is.na(recommendation_threshold)) recommendation_threshold <- 50L
      cfg$recommendation_threshold <- recommendation_threshold
      save_cfg()
    }
  }
}

# --------------------------------------------------
# Recommendations history submenu
# --------------------------------------------------

RECOMMENDATIONS_FILE <- recommendations_file_path()

read_recommendations <- function() {
  if (!file.exists(RECOMMENDATIONS_FILE)) return(data.frame())
  read.csv(RECOMMENDATIONS_FILE, stringsAsFactors = FALSE)
}

print_recommendations_page <- function(recs, start, end) {
  vapply(start:end, function(i) {
    sprintf(
      "[%-20s] score=%-3s %-60s (%s)",
      recs$category[i], recs$score[i],
      substr(recs$title[i], 1, 60), recs$processed_date[i]
    )
  }, character(1))
}

action_browse_recommendations <- function(recs) {
  page_size <- 10
  page <- 1
  total_pages <- ceiling(nrow(recs) / page_size)

  repeat {
    start <- (page - 1) * page_size + 1
    end <- min(page * page_size, nrow(recs))
    commands <- c(if (page < total_pages) c(n = "Next") else character(),
                  if (page > 1) c(p = "Previous") else character(), b = "Back")
    nav <- prompt_cli_page("Recommendations", print_recommendations_page(recs, start, end), commands,
                           sprintf("Page %d/%d (records %d-%d of %d)", page, total_pages, start, end, nrow(recs)))
    if (identical(nav$value, "b")) return(invisible(NULL))
    if (identical(nav$value, "n")) { page <- page + 1; next }
    if (identical(nav$value, "p")) { page <- page - 1; next }
    row <- start + nav$value - 1L
    r <- recs[row, ]
    info <- sprintf(
      "Title: %s\nAuthors: %s\nJournal: %s\nDate: %s\nScore: %s  Category: %s\nMatched topics: %s\nReason: %s\nDOI: %s\nProcessed: %s",
      r$title, r$authors, r$journal, r$pubdate, r$score, r$category,
      r$matched_topics, r$reason, r$doi, r$processed_date
    )
    prompt_cli_page("Recommendation Detail", character(), c(b = "Back"), info)
  }
}

action_manage_recommendations <- function() {
  repeat {
    recs <- read_recommendations()
    info <- character()
    if (nrow(recs) == 0) {
      info <- "No recommendations recorded yet."
    } else {
      info <- c(sprintf("Total: %d", nrow(recs)), "By category:", capture.output(print(table(recs$category))),
                "By processed date:", capture.output(print(table(recs$processed_date))))
    }
    commands <- if (nrow(recs) == 0) c(b = "Back") else c(v = "Browse", d = "Delete all", c = "Delete by category", e = "Delete by date", b = "Back")
    nav <- prompt_cli_page("Recommendation History", character(), commands, info)
    if (identical(nav$value, "b")) return(invisible(NULL))
    if (identical(nav$value, "v")) {
      action_browse_recommendations(recs)
    } else if (identical(nav$value, "d")) {
      if (prompt_yes_no(sprintf("Delete all %d recommendations? This cannot be undone.", nrow(recs)))) {
        file.remove(RECOMMENDATIONS_FILE)
        cat("Cleared.\n")
      }
    } else if (identical(nav$value, "c")) {
      cats <- sort(unique(recs$category))
      category_nav <- prompt_cli_page("Delete Recommendation Category", cats, c(b = "Back"))
      if (identical(category_nav$value, "b")) next
      cat_name <- cats[category_nav$value]
      n <- sum(recs$category == cat_name)
      if (prompt_yes_no(sprintf("Delete %d recommendations in category '%s'?", n, cat_name))) {
        recs <- recs[recs$category != cat_name, ]
        write.csv(recs, RECOMMENDATIONS_FILE, row.names = FALSE)
        cat("Deleted.\n")
      }
    } else if (identical(nav$value, "e")) {
      dates <- c("Today", "Yesterday", "Specific date (yyyy-mm-dd)")
      date_nav <- prompt_cli_page("Delete by Processed Date", dates, c(b = "Back"))
      if (identical(date_nav$value, "b")) next
      target_date <- if (date_nav$value == 1) {
        as.character(Sys.Date())
      } else if (date_nav$value == 2) {
        as.character(Sys.Date() - 1)
      } else if (date_nav$value == 3) {
        d <- prompt_text("Date (yyyy-mm-dd)", as.character(Sys.Date()))
        parsed <- tryCatch(as.Date(d, format = "%Y-%m-%d"), error = function(e) NA)
        if (is.na(parsed) || !grepl("^\\d{4}-\\d{2}-\\d{2}$", d)) {
          cat("Invalid date format. Expected yyyy-mm-dd.\n")
          NA
        } else {
          as.character(parsed)
        }
      }
      if (!is.na(target_date)) {
        n <- sum(recs$processed_date == target_date)
        if (n == 0) {
          cat("No recommendations processed on", target_date, "\n")
        } else if (prompt_yes_no(sprintf("Delete %d recommendations processed on %s?", n, target_date))) {
          recs <- recs[recs$processed_date != target_date, ]
          write.csv(recs, RECOMMENDATIONS_FILE, row.names = FALSE)
          cat("Deleted.\n")
        }
      }
    }
  }
}

# --------------------------------------------------
# Researcher profile submenu
# --------------------------------------------------

print_profile_summary <- function(profile) {
  cat(sprintf("Summary: %s\n", profile$researcher_summary %||% "(none)"))
  ci <- profile$core_interests
  if (!is.null(ci) && length(ci) > 0) {
    cat("Core interests:\n")
    for (item in ci) cat(sprintf("  - %s (%.2f)\n", item$topic %||% "?", item$weight %||% 0))
  }
  for (field in c("secondary_interests", "emerging_interests", "preferred_methods",
                  "preferred_domains", "regional_interests", "frequent_keywords")) {
    cat(sprintf("%s: %d items\n", field, length(profile[[field]] %||% list())))
  }
}

call_profile_interview_step <- function(state, config, force_summary = FALSE) {
  for (attempt in 1:2) {
    response <- tryCatch(
      call_llm(build_profile_interview_prompt(state, force_summary = force_summary), config, simplify = FALSE),
      error = function(e) NULL
    )
    checked <- validate_profile_interview_response(response, force_summary = force_summary)
    if (isTRUE(checked$valid)) return(checked$data)
    cat("Interview response failed:", checked$message %||% "LLM call failed.", "\n")
    if (attempt == 1) cat("Retrying the same interview step once...\n")
  }
  NULL
}

call_profile_draft <- function(state, summary, config) {
  draft_config <- config
  configured_tokens <- suppressWarnings(as.integer(draft_config$max_tokens %||% 0L))
  if (is.na(configured_tokens)) configured_tokens <- 0L
  draft_config$max_tokens <- max(configured_tokens, 4096L)

  for (attempt in 1:2) {
    draft <- tryCatch(
      call_llm(build_profile_draft_prompt(state, summary), draft_config, simplify = FALSE),
      error = function(e) NULL
    )
    checked <- validate_profile_draft(draft)
    if (isTRUE(checked$valid)) return(draft)
    cat("Profile draft failed:", checked$message %||% "LLM call failed.", "\n")
    if (attempt == 1) cat("Retrying profile generation once...\n")
  }
  NULL
}

prompt_profile_interview_answer <- function(options, info, can_revise = FALSE) {
  repeat {
    commands <- c(f = "Finish and summarize", if (can_revise) c(r = "Revise previous answer") else character(), c = "Discard")
    cat(paste(cli_page_lines("Profile Interview", options,
                             commands, info), collapse = "\n"), "\n")
    cat(sprintf("Your answer [1-%d or free text]: ", length(options)))
    answer <- read_stdin_line()
    nav <- cli_parse_navigation(answer, length(options), commands)
    if (identical(nav$kind, "select")) return(list(status = "answer", answer = options[[nav$value]]))
    if (identical(nav$value, "f")) return(list(status = "finish", answer = NULL))
    if (identical(nav$value, "r")) return(list(status = "revise", answer = NULL))
    if (identical(nav$value, "c")) return(list(status = "cancel", answer = NULL))
    resolved <- resolve_profile_interview_answer(answer, options)
    if (identical(resolved$status, "other")) {
      other_answer <- prompt_text("Other answer", "")
      if (nzchar(other_answer)) return(list(status = "answer", answer = other_answer))
      cat("Please enter an answer.\n")
      next
    }
    if (identical(resolved$status, "invalid")) {
      cat("Enter an option number, another answer, /finish, or /cancel.\n")
      next
    }
    return(resolved)
  }
}

action_draft_profile <- function() {
  llm_cfg <- read_json_config(file.path(CONFIG_DIR, "llm_config.json"), default = NULL)
  if (is.null(llm_cfg) || !nzchar(llm_cfg$backend %||% "")) {
    cat("\nNo LLM backend is configured. Set one up under 'LLM settings' before starting the guided profile interview.\n")
    return(invisible(NULL))
  }

  draft_cfg <- llm_cfg
  draft_cfg$backend <- normalize_backend(llm_cfg$backend)
  language_nav <- prompt_cli_page("Interview Language", PROFILE_INTERVIEW_LANGUAGES, c(b = "Back"),
                                  "Select the language for LLM interview questions and summaries.")
  if (identical(language_nav$value, "b")) return(invisible(NULL))
  state <- new_profile_interview_state(load_feeds_config(), PROFILE_INTERVIEW_LANGUAGES[[language_nav$value]])
  summary <- NULL
  pending_step <- NULL

  repeat {
    if (is.null(summary)) {
      if (!is.null(pending_step)) {
        step <- pending_step
        pending_step <- NULL
      } else {
        force_summary <- profile_interview_force_summary(state)
        step <- call_profile_interview_step(state, draft_cfg, force_summary = force_summary)
      }
      if (is.null(step)) {
        cat("Interview ended without saving a profile.\n")
        return(invisible(NULL))
      }

      if (identical(step$action, "ask")) {
        question_number <- profile_interview_question_count(state) + 1L
        question_info <- c(
          sprintf("Question %d", question_number),
          paste("Current inference:", step$current_inference), "", paste("Question:", step$question)
        )
        response <- prompt_profile_interview_answer(
          step$options, question_info,
          can_revise = profile_interview_question_count(state) > 0L
        )
        if (identical(response$status, "cancel")) {
          cat("Interview discarded. Existing profile was not changed.\n")
          return(invisible(NULL))
        }
        if (identical(response$status, "revise")) {
          revised <- profile_interview_revise_previous_answer(state)
          state <- revised$state
          pending_step <- revised$step
          next
        }
        if (identical(response$status, "finish")) {
          summary_step <- call_profile_interview_step(state, draft_cfg, force_summary = TRUE)
          if (is.null(summary_step)) {
            cat("Interview ended without saving a profile.\n")
            return(invisible(NULL))
          }
          summary <- summary_step$summary
          next
        }
        state <- profile_interview_add_answer(state, step$current_inference, step$question, step$options, response$answer)
        next
      }

      summary <- step$summary
    }

    review <- prompt_cli_page("Profile Understanding", character(), c(g = "Generate profile draft", e = "Add correction or detail", c = "Discard"), summary)
    if (identical(review$value, "c")) {
      cat("Interview discarded. Existing profile was not changed.\n")
      return(invisible(NULL))
    }
    if (identical(review$value, "e")) {
      revision <- prompt_text("Correction or additional detail", "")
      if (!nzchar(revision)) {
        cat("No correction entered.\n")
        next
      }
      state <- profile_interview_add_summary_revision(state, revision)
      summary_step <- call_profile_interview_step(state, draft_cfg, force_summary = TRUE)
      if (is.null(summary_step)) {
        cat("Interview ended without saving a profile.\n")
        return(invisible(NULL))
      }
      summary <- summary_step$summary
      next
    }

    cat("Generating profile draft...\n")
    draft <- call_profile_draft(state, summary, draft_cfg)
    if (is.null(draft)) {
      cat("Interview ended without saving a profile.\n")
      return(invisible(NULL))
    }

    draft_info <- c(capture.output(print_profile_summary(draft)), "", "Raw JSON:",
                    as.character(jsonlite::toJSON(draft, auto_unbox = TRUE, pretty = TRUE)))
    draft_nav <- prompt_cli_page("Review Profile Draft", character(), c(s = "Save", e = "Return to summary and add detail", c = "Discard"), draft_info)
    if (identical(draft_nav$value, "s")) {
      write_json_config(draft, file.path(CONFIG_DIR, "research_profile.json"))
      cat("Saved to config/research_profile.json\n")
      return(invisible(NULL))
    } else if (identical(draft_nav$value, "e")) {
      revision <- prompt_text("Correction or additional detail", "")
      if (nzchar(revision)) {
        state <- profile_interview_add_summary_revision(state, revision)
        summary_step <- call_profile_interview_step(state, draft_cfg, force_summary = TRUE)
        if (is.null(summary_step)) {
          cat("Interview ended without saving a profile.\n")
          return(invisible(NULL))
        }
        summary <- summary_step$summary
      }
      next
    } else {
      cat("Interview discarded. Existing profile was not changed.\n")
      return(invisible(NULL))
    }
  }
}

empty_profile_template <- function() {
  fields <- setNames(rep(list(list()), length(PROFILE_FIELDS)), PROFILE_FIELDS)
  fields$weak_negative_note <- ""
  fields$researcher_summary <- ""
  fields
}

profile_field_summary <- function(profile, field) {
  val <- profile[[field]]
  if (field %in% PROFILE_STRING_FIELDS) {
    if (is.null(val) || !nzchar(val)) "(empty)" else substr(val, 1, 50)
  } else {
    sprintf("%d items", length(val %||% list()))
  }
}

edit_string_list <- function(items, label) {
  items <- as.list(items)
  repeat {
    nav <- prompt_cli_page(label, unlist(items, use.names = FALSE), c(a = "Add", b = "Back"), sprintf("%d items", length(items)))
    if (identical(nav$value, "a")) {
      new_item <- prompt_text("New item", "")
      if (nzchar(new_item)) items <- c(items, new_item)
    } else if (identical(nav$value, "b")) {
      return(items)
    } else {
      item <- items[[nav$value]]
      detail <- prompt_cli_page(paste(label, "Item"), character(), c(d = "Delete", b = "Back"), item)
      if (identical(detail$value, "d")) { items <- items[-nav$value]; cat("Deleted.\n") }
    }
  }
}

edit_core_interests <- function(items) {
  repeat {
    total <- sum(vapply(items, function(x) x$weight %||% 0, numeric(1)))
    labels <- vapply(items, function(x) sprintf("%s (%.2f)", x$topic, x$weight), character(1))
    nav <- prompt_cli_page("Core Interests", labels, c(a = "Add", b = "Back"), sprintf("%d topics; weights sum to %.2f", length(items), total))
    if (identical(nav$value, "a")) {
      topic <- prompt_text("Topic name", "")
      if (nzchar(topic)) {
        weight <- suppressWarnings(as.numeric(prompt_text("Weight (0-1)", "0.1")))
        if (is.na(weight)) weight <- 0.1
        items <- c(items, list(list(topic = topic, weight = weight)))
      }
    } else if (identical(nav$value, "b")) {
      return(items)
    } else {
      row <- nav$value
      detail <- prompt_cli_page("Core Interest Detail", character(), c(e = "Edit weight", d = "Delete", b = "Back"), labels[[row]])
      if (identical(detail$value, "e")) {
        weight <- suppressWarnings(as.numeric(prompt_text("New weight", as.character(items[[row]]$weight))))
        if (!is.na(weight)) items[[row]]$weight <- weight
      } else if (identical(detail$value, "d")) {
        items <- items[-row]; cat("Deleted.\n")
      }
    }
  }
}

edit_topic_aliases <- function(dict) {
  repeat {
    topics <- names(dict)
    labels <- vapply(topics, function(topic) sprintf("%s (%d aliases)", topic, length(dict[[topic]])), character(1))
    nav <- prompt_cli_page("Topic Aliases", labels, c(a = "Add", b = "Back"))
    if (identical(nav$value, "a")) {
      topic <- prompt_text("Topic name (should match a core_interests topic)", "")
      if (nzchar(topic)) dict[[topic]] <- list()
    } else if (identical(nav$value, "b")) {
      return(dict)
    } else {
      topic <- topics[[nav$value]]
      detail <- prompt_cli_page("Topic Alias Detail", character(), c(e = "Edit aliases", d = "Delete topic", b = "Back"), topic)
      if (identical(detail$value, "e")) dict[[topic]] <- edit_string_list(dict[[topic]] %||% list(), paste("Aliases for", topic))
      else if (identical(detail$value, "d")) { dict[[topic]] <- NULL; cat("Deleted.\n") }
    }
  }
}

edit_profile_field <- function(profile, field) {
  if (field %in% PROFILE_STRING_FIELDS) {
    profile[[field]] <- prompt_text(field, profile[[field]] %||% "")
  } else if (field == "core_interests") {
    profile$core_interests <- edit_core_interests(profile$core_interests %||% list())
  } else if (field == "topic_aliases") {
    profile$topic_aliases <- edit_topic_aliases(profile$topic_aliases %||% list())
  } else {
    profile[[field]] <- edit_string_list(profile[[field]] %||% list(), field)
  }
  profile
}

action_manual_edit_profile <- function(profile) {
  repeat {
    labels <- sprintf("%-22s %s", PROFILE_FIELDS,
                       vapply(PROFILE_FIELDS, function(f) profile_field_summary(profile, f), character(1)))
    nav <- prompt_cli_page("Manual Researcher Profile", labels, c(s = "Save", c = "Discard"))
    if (identical(nav$value, "s")) {
      write_json_config(profile, file.path(CONFIG_DIR, "research_profile.json"))
      cat("Saved to config/research_profile.json\n")
      return(invisible(NULL))
    }
    if (identical(nav$value, "c")) { cat("Discarded.\n"); return(invisible(NULL)) }
    field <- PROFILE_FIELDS[nav$value]
    profile <- edit_profile_field(profile, field)
  }
}

action_research_profile <- function(exit_commands = c(b = "Back")) {
  exit_key <- names(exit_commands)[[1]]
  repeat {
    profile <- read_json_config(file.path(CONFIG_DIR, "research_profile.json"), default = NULL)
    info <- if (is.null(profile)) "No profile configured yet." else capture.output(print_profile_summary(profile))
    commands <- c(if (!is.null(profile)) c(v = "View raw JSON") else character(), g = "Draft with LLM", e = if (is.null(profile)) "Create manually" else "Edit manually", exit_commands)
    nav <- prompt_cli_page("Researcher Profile", character(), commands, info)
    if (identical(nav$value, exit_key)) return(invisible(NULL))
    if (identical(nav$value, "v")) {
      prompt_cli_page("Researcher Profile JSON", character(), c(b = "Back"), as.character(jsonlite::toJSON(profile, auto_unbox = TRUE, pretty = TRUE)))
    } else if (identical(nav$value, "g")) {
      action_draft_profile()
    } else {
      action_manual_edit_profile(profile %||% empty_profile_template())
    }
  }
}

# --------------------------------------------------
# First-run setup helper
# --------------------------------------------------

action_initial_setup <- function() {
  repeat {
    status <- initial_setup_status()
    complete <- initial_setup_complete(status)
    if (complete) {
      nav <- prompt_cli_page("Initial Setup", initial_setup_labels(status), c(b = "Back"),
                             "All required settings are ready. Select a step to review or change it.")
      if (identical(nav$value, "b")) return(invisible(TRUE))
      step_index <- nav$value
    } else {
      step_index <- initial_setup_next_incomplete(status)
      cat(sprintf("\nInitial Setup: continuing with %s.\n", status[[step_index]]$label))
    }

    before_complete <- status[[step_index]]$complete
    step_result <- NULL
    if (step_index == 1L) action_llm_settings(setup_mode = TRUE)
    else if (step_index == 2L) step_result <- action_manage_feeds(
      exit_commands = c(c = "Cancel initial setup"), setup_mode = TRUE
    )
    else if (step_index == 3L) action_research_profile(exit_commands = c(c = "Cancel initial setup"))
    else if (step_index == 4L) action_output_settings(exit_commands = c(c = "Cancel initial setup"))

    if (step_index == 2L && identical(step_result, "c")) return(invisible(FALSE))

    after_status <- initial_setup_status()
    if (!isTRUE(after_status[[step_index]]$complete) && identical(before_complete, after_status[[step_index]]$complete)) {
      return(invisible(FALSE))
    }
  }
}

# --------------------------------------------------
# Settings submenu and main loop
# --------------------------------------------------

action_settings <- function() {
  repeat {
    nav <- prompt_cli_page("Settings", c(
      "Researcher profile", "LLM settings", "Output settings"
    ), c(b = "Back"))
    if (identical(nav$value, "b")) return(invisible(NULL))
    if (nav$value == 1L) action_research_profile()
    else if (nav$value == 2L) action_llm_settings()
    else if (nav$value == 3L) action_output_settings()
  }
}

main <- function() {
  repeat {
    nav <- prompt_cli_page("Paper Monitor", c(
      "Run pipeline now", "Manage RSS feeds", "Manage recommendations", "Settings"
    ), c(i = "Initial setup", q = "Quit"))
    if (identical(nav$value, "q")) { cat("Bye.\n"); return(invisible(NULL)) }
    if (nav$value == 1) action_run_pipeline()
    else if (nav$value == 2) action_manage_feeds()
    else if (nav$value == 3) action_manage_recommendations()
    else if (nav$value == 4) action_settings()
    else if (identical(nav$value, "i")) action_initial_setup()
  }
}

# --run skips the interactive menu entirely and just runs the pipeline once
# (e.g. for cron/scheduled invocations), then exits.
is_run_mode <- "--run" %in% commandArgs(trailingOnly = TRUE)
check_llm_status_on_startup(is_run_mode)

if (is_run_mode) {
  action_run_pipeline(fail_on_error = TRUE)
} else {
  if (!initial_setup_complete()) action_initial_setup()
  main()
}
