# ==================================================
# backlog_layer.R — First-run backlog scan, estimates, and decision state
# ==================================================

BACKLOG_DECISION_FILE <- file.path(CONFIG_DIR, "backlog_setup.json")
BACKLOG_BATCH_STATE_FILE <- file.path(CONFIG_DIR, "backlog_batch.json")
BACKLOG_DECISION_VERSION <- 1L
BACKLOG_RECENT_N_DEFAULT <- 50L
BACKLOG_TOP_N_DEFAULT <- 25L

BACKLOG_IGNORE_REASON <- "Ignored during first-run backlog setup (not scored)."
BACKLOG_IGNORE_RECENT_REASON <- "Older than the most recent N papers selected during first-run backlog setup (not scored)."

# --------------------------------------------------
# Decision state
# --------------------------------------------------

load_backlog_decision <- function(path = BACKLOG_DECISION_FILE) {
  read_json_config(path, default = NULL)
}

backlog_decision_pending <- function(path = BACKLOG_DECISION_FILE) {
  is.null(tryCatch(load_backlog_decision(path), error = function(e) NULL))
}

backlog_decision_status_label <- function(path = BACKLOG_DECISION_FILE) {
  decision <- tryCatch(load_backlog_decision(path), error = function(e) NULL)
  if (is.null(decision)) "not decided" else backlog_decision_label(decision)
}

save_backlog_decision <- function(decision, path = BACKLOG_DECISION_FILE) {
  if (is.null(decision$version)) decision$version <- BACKLOG_DECISION_VERSION
  if (is.null(decision$decided_at)) decision$decided_at <- as.character(Sys.time())
  write_json_config(decision, path)
  invisible(decision)
}

new_backlog_decision <- function(mode, scope = NULL, recent_n = NULL, output = NULL,
                                 top_n = NULL, backlog_count = 0L,
                                 processed_count = 0L, ignored_count = 0L) {
  list(
    version = BACKLOG_DECISION_VERSION,
    decided_at = as.character(Sys.time()),
    mode = mode,
    scope = scope,
    recent_n = recent_n,
    output = output,
    top_n = top_n,
    backlog_count = as.integer(backlog_count),
    processed_count = as.integer(processed_count),
    ignored_count = as.integer(ignored_count)
  )
}

backlog_decision_label <- function(decision) {
  if (is.null(decision)) return("not decided")
  mode <- decision$mode
  if (is.null(mode) || length(mode) == 0L || is.na(mode)) mode <- "unknown"
  label <- switch(
    mode,
    process_now = {
      scope <- decision$scope
      if (is.null(scope) || length(scope) == 0L || is.na(scope)) scope <- "all"
      if (identical(scope, "recent_n")) {
        recent_n <- decision$recent_n
        scope <- if (is.null(recent_n) || length(recent_n) == 0L || is.na(recent_n)) {
          "recent N"
        } else {
          sprintf("recent %s", recent_n)
        }
      }
      output <- decision$output
      if (is.null(output) || length(output) == 0L || is.na(output)) output <- "full"
      if (identical(output, "top_n")) {
        top_n <- decision$top_n
        output <- if (is.null(top_n) || length(top_n) == 0L || is.na(top_n)) {
          "top N"
        } else {
          sprintf("top %s", top_n)
        }
      }
      sprintf("processed now (%s, %s output)", scope, output)
    },
    daily_drain = "drain daily via max_papers",
    skip_all = {
      count <- decision$backlog_count
      if (!is.null(count) && length(count) > 0L && !is.na(count) && as.integer(count) == 0L) {
        "no new papers"
      } else {
        "all skipped from today"
      }
    },
    deferred = "deferred",
    mode
  )
  decided_at <- decision$decided_at
  if (is.null(decided_at) || length(decided_at) == 0L || is.na(decided_at)) decided_at <- "unknown time"
  sprintf("%s — %s", label, decided_at)
}

# --------------------------------------------------
# Scan
# --------------------------------------------------

# Fetches all enabled feeds once and returns the papers that would be treated
# as new by a normal run. The caller can reuse `papers` for immediate scoring
# instead of fetching the feeds a second time.
scan_backlog <- function(feeds = NULL, history_file = recommendations_file_path(),
                         feed_status = NULL) {
  papers_raw <- get_papers(feeds)
  papers_filtered <- filter_rss_title_prefix(papers_raw)
  history <- load_history(history_file)
  new_papers <- deduplicate_papers(papers_filtered, history)

  if (is.null(feed_status)) feed_status <- read_feed_status()
  failed_feeds <- if (nrow(feed_status) > 0L && "success" %in% names(feed_status)) {
    feed_status[!is.na(feed_status$success) & !feed_status$success, , drop = FALSE]
  } else {
    feed_status[0, , drop = FALSE]
  }

  list(
    papers = new_papers,
    fetched_count = nrow(papers_filtered),
    history_count = nrow(history),
    new_count = nrow(new_papers),
    failed_feeds = failed_feeds
  )
}

# Newest-first selection. Papers with an unparseable date sort last.
split_backlog_by_recency <- function(papers, n) {
  if (nrow(papers) == 0L) return(list(selected = papers, ignored = papers))
  n <- suppressWarnings(as.integer(n))
  if (is.na(n)) n <- 0L
  n <- max(0L, min(n, nrow(papers)))
  dates <- as.Date(papers$pubdate)
  ord <- order(dates, decreasing = TRUE, na.last = TRUE)
  selected_idx <- if (n == 0L) integer(0) else ord[seq_len(n)]
  ignored_idx <- if (n >= nrow(papers)) integer(0) else ord[(n + 1L):nrow(papers)]
  list(
    selected = papers[selected_idx, , drop = FALSE],
    ignored = papers[ignored_idx, , drop = FALSE]
  )
}

# --------------------------------------------------
# Estimates (local only — no LLM calls)
# --------------------------------------------------

.backlog_paper_chars <- function(papers, field) {
  values <- papers[[field]]
  values <- ifelse(is.na(values), "", as.character(values))
  nchar(values, type = "chars")
}

.estimate_backlog_tokens <- function(papers, profile, model_size = "large", sample_size = 20L) {
  count <- nrow(papers)
  if (count == 0L) return(list(input_tokens = 0, output_tokens = 0, sampled = 0L))

  sample_n <- min(as.integer(sample_size), count)
  prompts <- vapply(seq_len(sample_n), function(i) {
    build_paper_prompt(profile, model_size, papers$title[i], papers$abstract[i])
  }, character(1))
  average_chars <- mean(nchar(prompts, type = "chars"))
  list(
    input_tokens = ceiling(average_chars / 4 * count),
    output_tokens = 300L * count,
    sampled = sample_n
  )
}

.estimate_backlog_time <- function(count, llm_config) {
  backend <- llm_config$backend
  if (is.null(backend) || length(backend) == 0L || is.na(backend) || !nzchar(backend)) {
    backend <- "ollama"
  }
  if (identical(backend, "claude_batch")) {
    return(list(
      min_seconds = if (count == 0L) 0 else 300,
      max_seconds = if (count == 0L) 0 else 86400,
      note = "Batch API can take minutes to 24 hours; keep the terminal open."
    ))
  }
  if (identical(backend, "ollama")) {
    return(list(
      min_seconds = 15 * count,
      max_seconds = 60 * count,
      note = "Local Ollama speed depends on hardware."
    ))
  }
  list(
    min_seconds = 5 * count,
    max_seconds = 15 * count,
    note = "Cloud API latency varies."
  )
}

.estimate_backlog_output_size <- function(papers, output_mode, top_n) {
  count <- nrow(papers)
  if (count == 0L) return(list(blocks = 0L, bytes = 0))

  sample_n <- min(10L, count)
  overhead <- 800
  average_chars <- mean(
    .backlog_paper_chars(papers[seq_len(sample_n), , drop = FALSE], "title") +
      .backlog_paper_chars(papers[seq_len(sample_n), , drop = FALSE], "abstract") +
      overhead
  )
  blocks <- if (identical(output_mode, "top_n")) min(as.integer(top_n), count) else count
  list(blocks = blocks, bytes = ceiling(average_chars * blocks))
}

.estimate_backlog_drain <- function(papers, max_papers) {
  count <- nrow(papers)
  if (count == 0L) {
    return(list(backlog = 0L, simple_days = 0L, net_days = 0L,
                daily_inflow = NA_real_, can_clear = TRUE))
  }
  max_papers <- suppressWarnings(as.integer(max_papers))
  if (is.na(max_papers) || max_papers <= 0L) {
    return(list(backlog = count, simple_days = NA_integer_, net_days = NA_integer_,
                daily_inflow = NA_real_, can_clear = FALSE))
  }

  simple_days <- ceiling(count / max_papers)
  dates <- as.Date(papers$pubdate)
  valid_dates <- dates[!is.na(dates)]
  daily_inflow <- NA_real_
  if (length(valid_dates) >= 2L) {
    span_days <- as.numeric(max(valid_dates) - min(valid_dates)) + 1
    if (is.finite(span_days) && span_days > 0) daily_inflow <- count / span_days
  }

  net_per_day <- max_papers - if (is.na(daily_inflow)) 0 else daily_inflow
  net_days <- if (is.na(daily_inflow)) simple_days else if (net_per_day > 0) ceiling(count / net_per_day) else NA_integer_
  list(
    backlog = count,
    simple_days = simple_days,
    net_days = net_days,
    daily_inflow = daily_inflow,
    can_clear = !is.na(net_days)
  )
}

estimate_backlog <- function(papers, profile, llm_config, output_config,
                             output_mode = "full", top_n = 25L) {
  max_papers <- output_config$max_papers
  if (is.null(max_papers) || length(max_papers) == 0L || is.na(max_papers)) max_papers <- 25L

  tokens <- .estimate_backlog_tokens(papers, profile)
  timing <- .estimate_backlog_time(nrow(papers), llm_config)
  size <- .estimate_backlog_output_size(papers, output_mode, top_n)
  drain <- .estimate_backlog_drain(papers, max_papers)

  list(
    count = nrow(papers),
    input_tokens = tokens$input_tokens,
    output_tokens = tokens$output_tokens,
    sampled_prompts = tokens$sampled,
    min_seconds = timing$min_seconds,
    max_seconds = timing$max_seconds,
    time_note = timing$note,
    output_blocks = size$blocks,
    output_bytes = size$bytes,
    drain = drain
  )
}

# --------------------------------------------------
# Display helpers
# --------------------------------------------------

format_backlog_tokens <- function(tokens) {
  if (is.null(tokens) || length(tokens) == 0L || is.na(tokens)) return("unknown")
  if (tokens < 1000) return(as.character(as.integer(tokens)))
  if (tokens < 1e6) return(sprintf("%.0fk", tokens / 1000))
  sprintf("%.1fM", tokens / 1e6)
}

format_backlog_seconds <- function(seconds) {
  if (is.null(seconds) || length(seconds) == 0L || is.na(seconds)) return("unknown")
  if (seconds < 60) return(sprintf("%d sec", round(seconds)))
  if (seconds < 3600) return(sprintf("%d min", round(seconds / 60)))
  sprintf("%.1f hr", seconds / 3600)
}

format_backlog_bytes <- function(bytes) {
  if (is.null(bytes) || length(bytes) == 0L || is.na(bytes)) return("unknown")
  if (bytes < 1024) return(sprintf("%d B", as.integer(bytes)))
  if (bytes < 1024^2) return(sprintf("%.0f KB", bytes / 1024))
  sprintf("%.1f MB", bytes / 1024^2)
}

backlog_time_range <- function(min_seconds, max_seconds) {
  if (is.na(min_seconds) || is.na(max_seconds)) return("unknown")
  if (identical(as.numeric(min_seconds), as.numeric(max_seconds))) {
    return(format_backlog_seconds(min_seconds))
  }
  paste(format_backlog_seconds(min_seconds), "-", format_backlog_seconds(max_seconds))
}

.backlog_max_papers <- function(output_config) {
  max_papers <- output_config$max_papers
  if (is.null(max_papers) || length(max_papers) == 0L || is.na(max_papers)) return(25L)
  as.integer(max_papers)
}

backlog_new_items <- function() {
  c("Process the backlog now", "Drain it through daily runs", "Skip all current backlog")
}

backlog_scope_items <- function(recent_n = BACKLOG_RECENT_N_DEFAULT) {
  c("All new papers", sprintf("Most recent %d papers", as.integer(recent_n)))
}

backlog_output_items <- function(top_n = BACKLOG_TOP_N_DEFAULT) {
  c(
    "Full digest (recommendation threshold)",
    "Must-read only (score >= 90)",
    sprintf("Top %d by score", as.integer(top_n))
  )
}

backlog_drain_text <- function(drain, max_papers) {
  if (is.na(drain$simple_days)) {
    return("cannot estimate — max_papers must be greater than 0")
  }
  if (drain$backlog == 0L) return("nothing to drain")
  if (!drain$can_clear) {
    return(sprintf(
      "the backlog will not shrink at the current inflow; without new papers it would take at least %d days",
      drain$simple_days
    ))
  }
  if (is.finite(drain$daily_inflow)) {
    return(sprintf(
      "at least %d days; about %d days at the current inflow (~%.1f papers/day), assuming one run per day",
      drain$simple_days, drain$net_days, drain$daily_inflow
    ))
  }
  sprintf("at least %d days, assuming one run per day", drain$simple_days)
}

backlog_summary_lines <- function(scan, estimate, output_config) {
  max_papers <- .backlog_max_papers(output_config)
  lines <- c(sprintf("New papers: %d", scan$new_count))
  if (nrow(scan$failed_feeds) > 0L) {
    lines <- c(lines, sprintf("Feeds with errors: %d (the count may be incomplete)", nrow(scan$failed_feeds)))
  }
  if (!is.null(estimate)) {
    lines <- c(
      lines,
      sprintf(
        "Estimated full processing: ~%s input tokens, %s",
        format_backlog_tokens(estimate$input_tokens),
        backlog_time_range(estimate$min_seconds, estimate$max_seconds)
      ),
      sprintf("Daily drain at %d per run: %s", max_papers, backlog_drain_text(estimate$drain, max_papers))
    )
    if (!is.null(estimate$time_note) && nzchar(estimate$time_note)) {
      lines <- c(lines, estimate$time_note)
    }
  }
  lines
}

backlog_output_description <- function(output_mode, top_n) {
  switch(
    output_mode,
    full = "full digest (recommendation threshold)",
    must_read = "must-read only (score >= 90)",
    top_n = sprintf("top %d by score", as.integer(top_n)),
    output_mode
  )
}

backlog_confirm_lines <- function(selected_count, ignored_count, output_mode, top_n, estimate) {
  output_line <- if (identical(output_mode, "must_read")) {
    "Only papers scoring 90 or above will be written; the actual count is unknown until scoring."
  } else if (identical(output_mode, "top_n")) {
    sprintf("The %d highest-scoring papers will be written.", min(as.integer(top_n), selected_count))
  } else {
    "All papers at or above the recommendation threshold will be written."
  }
  c(
    sprintf("Papers to score: %d", selected_count),
    if (ignored_count > 0L) sprintf("Papers to ignore: %d", ignored_count),
    sprintf("Output: %s", backlog_output_description(output_mode, top_n)),
    sprintf("Estimated input: ~%s tokens", format_backlog_tokens(estimate$input_tokens)),
    sprintf("Estimated output: ~%s tokens", format_backlog_tokens(estimate$output_tokens)),
    sprintf("Estimated time: %s", backlog_time_range(estimate$min_seconds, estimate$max_seconds)),
    if (!is.null(estimate$time_note) && nzchar(estimate$time_note)) estimate$time_note,
    output_line,
    sprintf("Maximum output size: ~%s", format_backlog_bytes(estimate$output_bytes)),
    "A separate Backlog_<date>.md file will be written; the daily digest is not overwritten."
  )
}

backlog_drain_info_lines <- function(scan, estimate, output_config) {
  max_papers <- .backlog_max_papers(output_config)
  drain <- if (is.null(estimate)) {
    .estimate_backlog_drain(scan$papers, max_papers)
  } else {
    estimate$drain
  }
  c(
    sprintf("Backlog: %d papers", scan$new_count),
    sprintf("Current max_papers: %d", max_papers),
    sprintf("Estimated completion: %s", backlog_drain_text(drain, max_papers)),
    "No papers are recorded now; each daily run will score up to max_papers new papers.",
    "Risk: feeds usually keep only recent items, so older backlog papers may roll out before their turn.",
    "Risk: processing follows your feed configuration order, not a cross-journal date order."
  )
}

backlog_skip_info_lines <- function(scan) {
  c(
    sprintf("This will record %d papers as ignored (no score).", scan$new_count),
    "They will not be scored later.",
    "You can undo this by deleting the 'ignored' category in Manage recommendations.",
    "Papers that appear after this scan are not affected."
  )
}

backlog_digest_path <- function(output_folder, date = Sys.Date()) {
  base <- file.path(output_folder, sprintf("Backlog_%s.md", date))
  if (!file.exists(base)) return(base)
  stamp <- format(Sys.time(), "%H%M%S")
  candidate <- file.path(output_folder, sprintf("Backlog_%s_%s.md", date, stamp))
  if (!file.exists(candidate)) return(candidate)
  counter <- 1L
  repeat {
    candidate <- file.path(output_folder, sprintf("Backlog_%s_%s_%d.md", date, stamp, counter))
    if (!file.exists(candidate)) return(candidate)
    counter <- counter + 1L
  }
}

# --------------------------------------------------
# Process-now execution
# --------------------------------------------------

run_backlog_papers <- function(papers, ignored_papers, profile, llm_config, output_config,
                               output_mode = c("full", "must_read", "top_n"),
                               top_n = NULL,
                               checkpoint_every = 10L,
                               progress_cb = NULL) {
  output_mode <- match.arg(output_mode)
  if (nrow(papers) == 0L) stop("No papers selected for backlog processing.", call. = FALSE)

  output_folder <- output_config$output_folder
  if (is.null(output_folder) || length(output_folder) == 0L ||
      is.na(output_folder) || !nzchar(output_folder)) {
    stop("Output folder is not configured.", call. = FALSE)
  }
  if (!dir.exists(output_folder)) {
    stop("Output folder does not exist: ", output_folder, call. = FALSE)
  }
  probe_file <- tempfile(tmpdir = output_folder)
  writable <- tryCatch({
    created <- suppressWarnings(file.create(probe_file))
    if (isTRUE(created)) unlink(probe_file)
    isTRUE(created)
  }, error = function(e) FALSE)
  if (!writable) {
    stop("Output folder is not writable: ", output_folder, call. = FALSE)
  }

  digest_file <- backlog_digest_path(output_folder)
  threshold <- output_config$recommendation_threshold
  if (is.null(threshold) || length(threshold) == 0L || is.na(threshold)) threshold <- 50

  output_max <- NULL
  count_label <- "Recommended papers"
  output_threshold <- threshold
  if (identical(output_mode, "must_read")) {
    output_threshold <- 90
    count_label <- "Must-read papers"
  } else if (identical(output_mode, "top_n")) {
    output_max <- suppressWarnings(as.integer(top_n))
    if (is.na(output_max) || output_max <= 0L) {
      stop("top_n must be a positive integer.", call. = FALSE)
    }
    output_threshold <- -Inf
    count_label <- "Papers included"
  }

  history <- load_history(recommendations_file_path())
  if (nrow(ignored_papers) > 0L) {
    ignored_papers <- deduplicate_papers(ignored_papers, history)
    record_ignored_papers(
      ignored_papers, history, recommendations_file_path(), profile,
      BACKLOG_IGNORE_RECENT_REASON
    )
  }

  header_extra <- c(
    "Source: First-run backlog",
    sprintf("Selection: %s", backlog_output_description(output_mode, top_n)),
    if (nrow(ignored_papers) > 0L) sprintf("Ignored (not scored): %d", nrow(ignored_papers))
  )

  result <- run_paper_set(
    papers_filtered = papers,
    history_file = recommendations_file_path(),
    profile = profile,
    llm_config = llm_config,
    model_size = "large",
    recommendation_threshold = output_threshold,
    max_papers = Inf,
    md_file = digest_file,
    output_max = output_max,
    header_extra = header_extra,
    count_label = count_label,
    digest_title = "First-run Backlog Digest",
    checkpoint_every = checkpoint_every,
    batch_checkpoint_file = if (identical(llm_config$backend, "claude_batch")) {
      BACKLOG_BATCH_STATE_FILE
    } else {
      NULL
    },
    progress_cb = progress_cb
  )

  list(
    digest_file = digest_file,
    results = result$results,
    processed_count = nrow(result$results),
    selected_count = nrow(result$new_papers),
    ignored_count = nrow(ignored_papers)
  )
}
