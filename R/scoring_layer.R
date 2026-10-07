# ==================================================
# scoring_layer.R — Results Processing and Scoring Layer
# ==================================================

suppressPackageStartupMessages({
  library(dplyr)
})

# --------------------------------------------------
# History management
# --------------------------------------------------

load_history <- function(history_file) {
  if (file.exists(history_file)) {
    read.csv(history_file, stringsAsFactors = FALSE)
  } else {
    data.frame(doi = character(), stringsAsFactors = FALSE)
  }
}

deduplicate_papers <- function(papers, history) {
  papers |> filter(!(doi %in% history$doi))
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
  updated <- dplyr::bind_rows(history, results_df)
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

.process_sequential <- function(new_papers, json_file, config, model_size) {

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

    results[[length(results) + 1]] <- .paper_result_row(new_papers[i, , drop = FALSE], ai)
  }

  if (length(results)) dplyr::bind_rows(results) else .empty_paper_results()
}

# --------------------------------------------------
# Batch processing (Claude Batch API)
# --------------------------------------------------

.process_batch <- function(new_papers, json_file, config, model_size) {

  profile <- if (is.character(json_file)) load_research_profile(json_file) else json_file

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
  cat("Batch ID:", batch$id, "\n")

  poll_interval <- config$poll_interval %||% 30L
  poll_claude_batch(batch$id, config, poll_interval = poll_interval)

  cat("Collecting results...\n")
  results_raw <- collect_claude_batch(batch$id, config)

  results <- list()
  for (i in seq_len(nrow(new_papers))) {
    custom_id <- sprintf("paper-%04d", i)
    ai        <- results_raw[[custom_id]]
    if (is.null(ai)) next
    checked <- validate_and_finalize_paper_result(ai, profile)
    if (!checked$valid) {
      warning("Skipping ", custom_id, ": ", checked$message, call. = FALSE)
      next
    }
    results[[length(results) + 1]] <- .paper_result_row(new_papers[i, , drop = FALSE], checked$data)
  }

  if (length(results)) dplyr::bind_rows(results) else .empty_paper_results()
}

# --------------------------------------------------
# Unified dispatcher
# --------------------------------------------------

process_papers_with_llm <- function(new_papers, json_file, config, model_size) {
  backend <- config$backend %||% "ollama"

  if (backend == "claude_batch") {
    .process_batch(new_papers, json_file, config, model_size)
  } else {
    .process_sequential(new_papers, json_file, config, model_size)
  }
}
