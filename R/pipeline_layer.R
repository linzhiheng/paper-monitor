# ==================================================
# pipeline_layer.R — Daily Pipeline Orchestration
# ==================================================

.process_papers_with_checkpoint <- function(new_papers, profile, llm_config, model_size,
                                            history, history_file,
                                            checkpoint_every = NULL,
                                            batch_checkpoint_file = NULL) {
  pending <- list()
  updated_history <- history
  received_results <- 0L

  record <- function(row) {
    received_results <<- received_results + 1L
    pending[[length(pending) + 1L]] <<- row
    if (!is.null(checkpoint_every) && checkpoint_every > 0L &&
        length(pending) >= checkpoint_every) {
      updated_history <<- update_history(
        updated_history, dplyr::bind_rows(pending), history_file
      )
      pending <<- list()
    }
  }

  results_df <- process_papers_with_llm(
    new_papers, profile, llm_config, model_size,
    on_result = record, batch_checkpoint_file = batch_checkpoint_file
  )

  if (length(pending) > 0L) {
    updated_history <- update_history(
      updated_history, dplyr::bind_rows(pending), history_file
    )
  } else if (received_results == 0L && nrow(results_df) > 0L) {
    # Backend returned rows without reporting them incrementally.
    updated_history <- update_history(updated_history, results_df, history_file)
  }

  list(results = results_df, history = updated_history)
}

run_paper_set <- function(
    papers_filtered,
    history_file,
    profile,
    llm_config,
    model_size,
    recommendation_threshold,
    max_papers,
    md_file,
    output_max = NULL,
    header_extra = character(),
    count_label = "Recommended papers",
    digest_title = "Daily Paper Digest",
    checkpoint_every = NULL,
    batch_checkpoint_file = NULL,
    progress_cb = NULL,
    start_time = NULL
) {
  if (is.null(start_time)) start_time <- Sys.time()

  step <- function(message, detail = NULL, value = NULL) {
    if (!is.null(progress_cb)) progress_cb(message, detail, value)
  }

  step("Deduplicating against history", value = 0.3)
  history <- load_history(history_file)
  new_papers <- deduplicate_papers(papers_filtered, history)
  if (!is.infinite(max_papers)) {
    new_papers <- get_papers_sample(new_papers, n = max_papers)
  }

  cat(
    "RSS papers:",     nrow(papers_filtered), "\n",
    "History records:", nrow(history), "\n",
    "Papers to process:", nrow(new_papers), "\n"
  )

  if (nrow(new_papers) == 0) {
    lines <- c(
      paste0("## ", digest_title),
      "",
      sprintf("Generated: %s", Sys.Date()),
      as.character(header_extra),
      "",
      "No new papers found today."
    )
    write_daily_note(lines, md_file)
    cat("No new papers.\nDigest written.\n")
    step("No new papers — digest written", value = 1)
    return(invisible(list(
      results = .empty_paper_results(),
      new_papers = new_papers,
      history = history
    )))
  }

  step(sprintf("Scoring %d papers with LLM", nrow(new_papers)), value = 0.5)
  scored <- .process_papers_with_checkpoint(
    new_papers, profile, llm_config, model_size, history, history_file,
    checkpoint_every = checkpoint_every,
    batch_checkpoint_file = batch_checkpoint_file
  )

  step("History saved", value = 0.8)
  step("Writing digest", value = 0.9)
  lines <- build_digest_lines(
    scored$results, recommendation_threshold,
    max_output = output_max,
    header_extra = header_extra,
    count_label = count_label
  )
  write_daily_note(lines, md_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  cat("Finished.\nRuntime:", elapsed, "seconds\n")
  step("Finished", value = 1)

  invisible(list(
    results = scored$results,
    new_papers = new_papers,
    history = scored$history
  ))
}

run_daily_papers <- function(
    json_file,
    history_file,
    llm_config,
    model_size,
    recommendation_threshold,
    max_papers,
    md_file,
    progress_cb = NULL
) {
  start_time <- Sys.time()

  step <- function(message, detail = NULL, value = NULL) {
    if (!is.null(progress_cb)) progress_cb(message, detail, value)
  }

  # Validate before any RSS/network work so scheduled runs fail safely.
  profile <- tryCatch(load_research_profile(json_file), error = function(e) {
    stop("Researcher Profile is invalid. Open Settings > Researcher profile to repair it. ", conditionMessage(e), call. = FALSE)
  })

  # RSS layer
  step("Fetching RSS feeds", value = 0.1)
  papers_raw      <- get_papers()
  papers_filtered <- filter_rss_title_prefix(papers_raw)

  result <- run_paper_set(
    papers_filtered = papers_filtered,
    history_file = history_file,
    profile = profile,
    llm_config = llm_config,
    model_size = model_size,
    recommendation_threshold = recommendation_threshold,
    max_papers = max_papers,
    md_file = md_file,
    progress_cb = progress_cb,
    start_time = start_time
  )

  invisible(result$results)
}

# --------------------------------------------------
# Build config from llm_config.json / output_config.json and run.
# Shared by the interactive CLI's "Run pipeline now" action.
# --------------------------------------------------

run_daily_papers_from_config <- function(progress_cb = NULL) {
  llm_config    <- read_json_config(file.path(CONFIG_DIR, "llm_config.json"), default = NULL)
  output_config <- read_json_config(file.path(CONFIG_DIR, "output_config.json"), default = NULL)

  if (is.null(llm_config) || !nzchar(llm_config$backend %||% "")) {
    stop("No LLM backend configured — set one up in the LLM settings menu first.")
  }
  if (is.null(output_config) || !nzchar(output_config$output_folder %||% "")) {
    stop("No output folder configured — set one up in the output settings menu first.")
  }

  filename <- sprintf(output_config$filename_pattern %||% "Daily_Papers_%s.md", Sys.Date())
  md_file  <- file.path(output_config$output_folder, filename)

  run_daily_papers(
    json_file                = file.path(CONFIG_DIR, "research_profile.json"),
    history_file             = recommendations_file_path(),
    llm_config                = llm_config,
    model_size                = "large",
    recommendation_threshold = output_config$recommendation_threshold %||% 50,
    max_papers                = output_config$max_papers %||% 25,
    md_file                    = md_file,
    progress_cb                = progress_cb
  )
}
