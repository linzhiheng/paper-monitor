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
  updated <- dplyr::bind_rows(history, results_df)
  write.csv(updated, history_file, row.names = FALSE)
  invisible(updated)
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

  prompt <- build_paper_prompt(
    profile_or_file = json_file,
    model_size      = model_size,
    title           = title,
    abstract        = abstract
  )

  if (print_prompt) {
    cat("\n========== Prompt ==========\n", prompt,
        "\n============================\n")
  }

  parsed <- call_llm(prompt, config)

  if (verbose && !is.null(parsed)) {
    cat(sprintf(
      "  score=%s  category=%s  topics=%s\n",
      parsed$score %||% "?",
      parsed$category %||% "?",
      paste(unlist(parsed$matched_topics), collapse = "; ")
    ))
  }

  parsed
}

# --------------------------------------------------
# Sequential processing (Ollama / Claude direct)
# --------------------------------------------------

.process_sequential <- function(new_papers, json_file, config, model_size) {

  results <- list()

  for (i in seq_len(nrow(new_papers))) {
    cat("Processing:", i, "/", nrow(new_papers), "\n")

    attempt <- function() {
      tryCatch(
        evaluate_paper(
          json_file  = json_file,
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

    results[[length(results) + 1]] <- data.frame(
      doi            = new_papers$doi[i],
      title          = new_papers$title[i],
      authors        = new_papers$authors[i],
      abstract       = new_papers$abstract[i],
      journal        = new_papers$journal[i],
      pubdate        = as.character(new_papers$pubdate[i]),
      score          = ai$score %||% 0L,
      category       = ai$category %||% "",
      matched_topics = paste(unlist(ai$matched_topics), collapse = "; "),
      reason         = ai$reason %||% "",
      tldr           = ai$tldr %||% "",
      processed_date = as.character(Sys.Date()),
      stringsAsFactors = FALSE
    )
  }

  dplyr::bind_rows(results)
}

# --------------------------------------------------
# Batch processing (Claude Batch API)
# --------------------------------------------------

.process_batch <- function(new_papers, json_file, config, model_size) {

  cat("Building batch prompts...\n")

  requests <- lapply(seq_len(nrow(new_papers)), function(i) {
    list(
      custom_id = sprintf("paper-%04d", i),
      prompt    = build_paper_prompt(
        profile_or_file = json_file,
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

    results[[length(results) + 1]] <- data.frame(
      doi            = new_papers$doi[i],
      title          = new_papers$title[i],
      authors        = new_papers$authors[i],
      abstract       = new_papers$abstract[i],
      journal        = new_papers$journal[i],
      pubdate        = as.character(new_papers$pubdate[i]),
      score          = ai$score %||% 0L,
      category       = ai$category %||% "",
      matched_topics = paste(unlist(ai$matched_topics), collapse = "; "),
      reason         = ai$reason %||% "",
      tldr           = ai$tldr %||% "",
      processed_date = as.character(Sys.Date()),
      stringsAsFactors = FALSE
    )
  }

  dplyr::bind_rows(results)
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
