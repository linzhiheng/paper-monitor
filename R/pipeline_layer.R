# ==================================================
# pipeline_layer.R — Daily Pipeline Orchestration
# ==================================================

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

  # Deduplication
  step("Deduplicating against history", value = 0.3)
  history    <- load_history(history_file)
  new_papers <- deduplicate_papers(papers_filtered, history)
  new_papers <- get_papers_sample(new_papers, n = max_papers)

  cat(
    "RSS papers:",     nrow(papers_filtered), "\n",
    "History records:", nrow(history), "\n",
    "Papers to process:", nrow(new_papers), "\n"
  )

  if (nrow(new_papers) == 0) {
    lines <- c(
      "## Daily Paper Digest",
      "",
      sprintf("Generated: %s", Sys.Date()),
      "",
      "No new papers found today."
    )
    write_daily_note(lines, md_file)
    cat("No new papers.\nDigest written.\n")
    step("No new papers — digest written", value = 1)
    return(invisible(NULL))
  }

  # Scoring layer
  step(sprintf("Scoring %d papers with LLM", nrow(new_papers)), value = 0.5)
  results_df <- process_papers_with_llm(new_papers, profile, llm_config, model_size)

  # Persist history
  step("Updating history", value = 0.8)
  update_history(history, results_df, history_file)

  # Output layer
  step("Writing digest", value = 0.9)
  lines <- build_digest_lines(results_df, recommendation_threshold)
  write_daily_note(lines, md_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  cat("Finished.\nRuntime:", elapsed, "seconds\n")
  step("Finished", value = 1)

  invisible(results_df)
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
