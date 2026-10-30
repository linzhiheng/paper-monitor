# ==================================================
# scoring_layer.R — Results Processing and Scoring Layer
# ==================================================

suppressPackageStartupMessages({
  library(dplyr)
})

# --------------------------------------------------
# History management
# --------------------------------------------------

.normalize_history_text <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  tolower(trimws(gsub("\\s+", " ", x)))
}

.dedup_doi_key <- function(doi) {
  key <- .normalize_history_text(doi)
  ifelse(nzchar(key), paste0("doi:", key), NA_character_)
}

.dedup_title_journal_key <- function(title, journal) {
  title <- .normalize_history_text(title)
  journal <- .normalize_history_text(journal)
  ifelse(nzchar(title), paste0("title:", title, "|journal:", journal), NA_character_)
}

normalize_history_data <- function(history) {
  if (!is.data.frame(history) || ncol(history) == 0L) return(history)
  if ("doi" %in% names(history)) history$doi <- as.character(history$doi)
  if ("score" %in% names(history)) history$score <- suppressWarnings(as.numeric(history$score))
  if ("must_read_focus_match" %in% names(history)) {
    history$must_read_focus_match <- as.logical(history$must_read_focus_match)
  }
  history
}

load_history <- function(history_file) {
  if (!file.exists(history_file)) {
    return(data.frame(doi = character(), stringsAsFactors = FALSE))
  }
  normalize_history_data(read.csv(history_file, stringsAsFactors = FALSE))
}

# Papers are treated as already seen when either their DOI or their
# title+journal pair matches a history row. The fallback is needed for feeds
# that omit DOIs and for deliberately ignored papers recorded without a score.
deduplicate_papers <- function(papers, history) {
  if (nrow(papers) == 0L) return(papers)

  history_doi_keys <- if ("doi" %in% names(history)) .dedup_doi_key(history$doi) else character()
  history_title_keys <- if (all(c("title", "journal") %in% names(history))) {
    .dedup_title_journal_key(history$title, history$journal)
  } else {
    character()
  }

  paper_doi_keys <- if ("doi" %in% names(papers)) {
    .dedup_doi_key(papers$doi)
  } else {
    rep(NA_character_, nrow(papers))
  }
  paper_title_keys <- if (all(c("title", "journal") %in% names(papers))) {
    .dedup_title_journal_key(papers$title, papers$journal)
  } else {
    rep(NA_character_, nrow(papers))
  }

  duplicate <- (!is.na(paper_doi_keys) & paper_doi_keys %in% history_doi_keys) |
    (!is.na(paper_title_keys) & paper_title_keys %in% history_title_keys)
  papers[!duplicate, , drop = FALSE]
}

.ignored_paper_row <- function(paper, profile, reason) {
  scope <- profile$must_read_scope
  if (is.null(scope) || length(scope) == 0L || is.na(scope)) scope <- NA_character_
  focus <- ""
  if (identical(scope, "focused")) {
    focus <- profile$must_read_focus$primary_focus
    if (is.null(focus) || length(focus) == 0L || is.na(focus)) focus <- ""
  }
  data.frame(
    doi = paper$doi, title = paper$title, authors = paper$authors, abstract = paper$abstract,
    journal = paper$journal, pubdate = as.character(paper$pubdate), score = NA_real_,
    category = "ignored", matched_topics = "", reason = reason, tldr = "",
    processed_date = as.character(Sys.Date()), must_read_scope = scope,
    must_read_primary_focus = focus, must_read_focus_match = NA,
    must_read_focus_reason = "", stringsAsFactors = FALSE
  )
}

record_ignored_papers <- function(papers, history, history_file, profile, reason) {
  if (nrow(papers) == 0L) return(invisible(history))
  rows <- dplyr::bind_rows(lapply(seq_len(nrow(papers)), function(i) {
    .ignored_paper_row(papers[i, , drop = FALSE], profile, reason)
  }))
  update_history(history, rows, history_file)
}

update_history <- function(history, results_df, history_file) {
  history_fields <- c("must_read_scope", "must_read_primary_focus", "must_read_focus_match", "must_read_focus_reason")
  if (file.exists(history_file) && any(!history_fields %in% names(history)) &&
      any(history_fields %in% names(results_df))) {
    backup <- file.path(dirname(history_file), "recommendations.pre-must-read-scope.csv")
    if (!file.exists(backup) && !file.copy(history_file, backup, overwrite = FALSE)) {
      stop("Could not create the recommendation-history backup: ", backup)
    }
  }
  updated <- normalize_history_data(dplyr::bind_rows(history, results_df))
  write.csv(updated, history_file, row.names = FALSE)
  invisible(updated)
}

derive_recommendation_category <- function(score) {
  if (score >= 90) "must_read" else if (score >= 75) "recommended" else if (score >= 60) "potentially_relevant" else if (score >= 40) "peripheral" else "low_relevance"
}

validate_and_finalize_paper_result <- function(result, profile, warning_cb = warning) {
  fail <- function(message) list(valid = FALSE, message = message, data = NULL)
  if (!is.list(result)) return(fail("Paper response must be a JSON object."))
  score <- result$score
  if (!is.numeric(score) || length(score) != 1L || is.na(score) || !is.finite(score) || score < 0 || score > 100) {
    return(fail("score must be one finite number from 0 through 100."))
  }
  topics <- result$matched_topics
  if (!is.list(topics) && !is.character(topics)) return(fail("matched_topics must be a string array."))
  if (length(topics) && !all(vapply(as.list(topics), function(x) is.character(x) && length(x) == 1L && !is.na(x), logical(1)))) {
    return(fail("matched_topics must be a string array."))
  }
  topics <- as.character(unlist(topics, use.names = FALSE))
  if (any(is.na(topics))) return(fail("matched_topics must be a string array."))
  if (!.is_nonempty_string(result$reason) || !.is_nonempty_string(result$tldr)) {
    return(fail("reason and tldr must be non-empty strings."))
  }

  scope <- profile$must_read_scope
  focus_match <- NA
  focus_reason <- ""
  if (identical(scope, "focused")) {
    valid_match <- is.logical(result$must_read_focus_match) && length(result$must_read_focus_match) == 1L && !is.na(result$must_read_focus_match)
    valid_reason <- .is_nonempty_string(result$must_read_focus_reason)
    if (!valid_match || !valid_reason) {
      warning_cb("Focused result did not contain a valid focus assessment; treating the match as unconfirmed.")
      focus_match <- NA
      focus_reason <- "The model did not provide a valid focus assessment; match not confirmed."
      score <- min(score, 89)
    } else {
      focus_match <- result$must_read_focus_match
      focus_reason <- trimws(result$must_read_focus_reason)
      if (!isTRUE(focus_match)) score <- min(score, 89)
    }
  }
  finalized <- list(
    score = as.numeric(score), category = derive_recommendation_category(score),
    matched_topics = topics, reason = trimws(result$reason), tldr = trimws(result$tldr),
    must_read_scope = scope,
    must_read_primary_focus = if (identical(scope, "focused")) profile$must_read_focus$primary_focus else "",
    must_read_focus_match = focus_match, must_read_focus_reason = focus_reason
  )
  list(valid = TRUE, message = NULL, data = finalized)
}

.paper_result_row <- function(paper, ai) {
  data.frame(
    doi = paper$doi, title = paper$title, authors = paper$authors, abstract = paper$abstract,
    journal = paper$journal, pubdate = as.character(paper$pubdate), score = ai$score,
    category = ai$category, matched_topics = paste(ai$matched_topics, collapse = "; "),
    reason = ai$reason, tldr = ai$tldr, processed_date = as.character(Sys.Date()),
    must_read_scope = ai$must_read_scope, must_read_primary_focus = ai$must_read_primary_focus,
    must_read_focus_match = ai$must_read_focus_match, must_read_focus_reason = ai$must_read_focus_reason,
    stringsAsFactors = FALSE
  )
}

.empty_paper_results <- function() {
  data.frame(
    doi = character(), title = character(), authors = character(), abstract = character(), journal = character(),
    pubdate = character(), score = numeric(), category = character(), matched_topics = character(), reason = character(),
    tldr = character(), processed_date = character(), must_read_scope = character(), must_read_primary_focus = character(),
    must_read_focus_match = logical(), must_read_focus_reason = character(), stringsAsFactors = FALSE
  )
}

# --------------------------------------------------
# Single paper evaluation
# --------------------------------------------------

evaluate_paper <- function(
    json_file,
    model_size,
    title,
    abstract,
    config,
    verbose    = TRUE,
    print_prompt = FALSE
) {

  profile <- if (is.character(json_file)) load_research_profile(json_file) else json_file
  prompt <- build_paper_prompt(
    profile_or_file = profile,
    model_size      = model_size,
    title           = title,
    abstract        = abstract
  )

  if (print_prompt) {
    cat("\n========== Prompt ==========\n", prompt,
        "\n============================\n")
  }

  parsed <- call_llm(prompt, config)

  if (is.null(parsed)) return(NULL)
  checked <- validate_and_finalize_paper_result(parsed, profile)
  if (!checked$valid) {
    message("Invalid paper evaluation: ", checked$message)
    return(NULL)
  }
  finalized <- checked$data
  if (verbose) {
    cat(sprintf("  score=%s  category=%s  topics=%s\n", finalized$score, finalized$category,
                paste(finalized$matched_topics, collapse = "; ")))
  }
  finalized
}

# --------------------------------------------------
# Sequential processing (Ollama / Claude direct)
# --------------------------------------------------

.process_sequential <- function(new_papers, json_file, config, model_size, on_result = NULL) {

  profile <- if (is.character(json_file)) load_research_profile(json_file) else json_file
  results <- list()

  for (i in seq_len(nrow(new_papers))) {
    cat("Processing:", i, "/", nrow(new_papers), "\n")

    attempt <- function() {
      tryCatch(
        evaluate_paper(
          json_file  = profile,
          model_size = model_size,
          title      = new_papers$title[i],
          abstract   = new_papers$abstract[i],
          config     = config
        ),
        error = function(e) {
          message("Error on paper ", i, ": ", e$message)
          NULL
        }
      )
    }

    ai <- attempt()

    if (is.null(ai)) {
      message("Retrying paper ", i, " in 15 seconds...")
      Sys.sleep(15)
      ai <- attempt()
    }

    if (is.null(ai)) {
      message("Paper ", i, " failed twice — skipping.")
      next
    }

    row <- .paper_result_row(new_papers[i, , drop = FALSE], ai)
    results[[length(results) + 1]] <- row
    if (!is.null(on_result)) on_result(row)
  }

  if (length(results)) dplyr::bind_rows(results) else .empty_paper_results()
}

# --------------------------------------------------
# Batch checkpoint state
# --------------------------------------------------

BACKLOG_BATCH_STATE_VERSION <- 1L

.save_batch_state <- function(batch_id, papers, custom_ids, path) {
  records <- lapply(seq_len(nrow(papers)), function(i) {
    list(
      doi = papers$doi[i] %||% NA_character_,
      title = papers$title[i] %||% NA_character_,
      authors = papers$authors[i] %||% NA_character_,
      abstract = papers$abstract[i] %||% NA_character_,
      journal = papers$journal[i] %||% NA_character_,
      pubdate = as.character(papers$pubdate[i])
    )
  })
  write_json_config(list(
    version = BACKLOG_BATCH_STATE_VERSION,
    created_at = as.character(Sys.time()),
    batch_id = batch_id,
    papers = records,
    custom_ids = as.list(unname(custom_ids))
  ), path)
  invisible(path)
}

.load_batch_state <- function(path) {
  if (!file.exists(path)) return(NULL)
  state <- tryCatch(
    read_json_config(path, default = NULL),
    error = function(e) {
      stop(
        "Batch state file is unreadable: ", path,
        ". Delete it only if you are sure the batch cannot be collected.",
        call. = FALSE
      )
    }
  )
  if (is.null(state) || is.null(state$batch_id) || !nzchar(state$batch_id)) {
    stop("Batch state file is missing its batch id: ", path, call. = FALSE)
  }
  if (is.null(state$papers) || length(state$papers) == 0L) {
    stop("Batch state file has no paper manifest: ", path, call. = FALSE)
  }

  papers <- dplyr::bind_rows(lapply(state$papers, function(p) {
    data.frame(
      doi = p$doi %||% NA_character_,
      title = p$title %||% NA_character_,
      authors = p$authors %||% NA_character_,
      abstract = p$abstract %||% NA_character_,
      journal = p$journal %||% NA_character_,
      pubdate = p$pubdate %||% NA_character_,
      stringsAsFactors = FALSE
    )
  }))
  custom_ids <- as.character(unlist(state$custom_ids, use.names = FALSE))
  if (length(custom_ids) != nrow(papers)) {
    stop("Batch state file has mismatched papers and custom ids: ", path, call. = FALSE)
  }
  list(batch_id = state$batch_id, papers = papers, custom_ids = custom_ids)
}

.batch_paper_is_current <- function(state_papers, current_papers) {
  state_doi <- .dedup_doi_key(state_papers$doi)
  state_title <- .dedup_title_journal_key(state_papers$title, state_papers$journal)
  current_doi <- .dedup_doi_key(current_papers$doi)
  current_title <- .dedup_title_journal_key(current_papers$title, current_papers$journal)
  matched <- (!is.na(state_doi) & state_doi %in% current_doi) |
    (!is.na(state_title) & state_title %in% current_title)
  unmatched <- is.na(state_doi) & is.na(state_title)
  matched | unmatched
}

# --------------------------------------------------
# Batch processing (Claude Batch API)
# --------------------------------------------------

.process_batch <- function(new_papers, json_file, config, model_size, on_result = NULL,
                           checkpoint_file = NULL) {

  profile <- if (is.character(json_file)) load_research_profile(json_file) else json_file
  state <- if (!is.null(checkpoint_file)) .load_batch_state(checkpoint_file) else NULL

  if (!is.null(state)) {
    cat("Resuming batch", state$batch_id, "...\n")
    batch_id <- state$batch_id
    papers_for_batch <- state$papers
    custom_ids <- state$custom_ids
  } else {
    cat("Building batch prompts...\n")

    requests <- lapply(seq_len(nrow(new_papers)), function(i) {
      list(
        custom_id = sprintf("paper-%04d", i),
        prompt    = build_paper_prompt(
          profile_or_file = profile,
          model_size      = model_size,
          title           = new_papers$title[i],
          abstract        = new_papers$abstract[i]
        )
      )
    })

    cat("Submitting batch (", length(requests), "papers)...\n")
    batch  <- submit_claude_batch(requests, config)
    batch_id <- batch$id
    papers_for_batch <- new_papers
    custom_ids <- sprintf("paper-%04d", seq_len(nrow(new_papers)))

    if (!is.null(checkpoint_file)) {
      .save_batch_state(batch_id, papers_for_batch, custom_ids, checkpoint_file)
    }
  }

  cat("Batch ID:", batch_id, "\n")

  poll_interval <- config$poll_interval %||% 30L
  poll_claude_batch(batch_id, config, poll_interval = poll_interval)

  cat("Collecting results...\n")
  results_raw <- collect_claude_batch(batch_id, config)

  keep <- rep(TRUE, nrow(papers_for_batch))
  if (!is.null(state)) {
    keep <- .batch_paper_is_current(papers_for_batch, new_papers)
  }

  results <- list()
  for (i in seq_len(nrow(papers_for_batch))) {
    if (!keep[i]) next
    custom_id <- custom_ids[i]
    ai        <- results_raw[[custom_id]]
    if (is.null(ai)) next
    checked <- validate_and_finalize_paper_result(ai, profile)
    if (!checked$valid) {
      warning("Skipping ", custom_id, ": ", checked$message, call. = FALSE)
      next
    }
    row <- .paper_result_row(papers_for_batch[i, , drop = FALSE], checked$data)
    results[[length(results) + 1]] <- row
    if (!is.null(on_result)) on_result(row)
  }

  if (!is.null(checkpoint_file) && file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
  }

  if (length(results)) dplyr::bind_rows(results) else .empty_paper_results()
}

# --------------------------------------------------
# Unified dispatcher
# --------------------------------------------------

process_papers_with_llm <- function(new_papers, json_file, config, model_size, on_result = NULL,
                                    batch_checkpoint_file = NULL) {
  backend <- config$backend %||% "ollama"

  if (backend == "claude_batch") {
    .process_batch(
      new_papers, json_file, config, model_size,
      on_result = on_result, checkpoint_file = batch_checkpoint_file
    )
  } else {
    .process_sequential(new_papers, json_file, config, model_size, on_result = on_result)
  }
}
