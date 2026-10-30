source("R/config_layer.R")
source("R/llm_layer.R")
source("R/profile_interview_layer.R")
source("R/prompt_layer.R")
source("R/rss_layer.R")
source("R/scoring_layer.R")
source("R/output_layer.R")
source("R/pipeline_layer.R")
source("R/backlog_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_false <- function(value, message) expect_true(!isTRUE(value), message)

profile_fixture <- list(must_read_scope = "research_direction", must_read_focus = NULL)
papers <- data.frame(
  doi = paste0("10.1/", 1:5),
  title = paste("Paper", 1:5),
  authors = "A", abstract = "Abstract", journal = "J",
  pubdate = as.Date("2026-01-01") + 0:4,
  stringsAsFactors = FALSE
)
fake_scores <- c(95, 80, 70, 40, 30)

make_result <- function(paper, score) {
  .paper_result_row(paper, list(
    score = score,
    category = derive_recommendation_category(score),
    matched_topics = c("topic"),
    reason = "Reason.",
    tldr = "TLDR.",
    must_read_scope = "research_direction",
    must_read_primary_focus = "",
    must_read_focus_match = NA,
    must_read_focus_reason = ""
  ))
}

normal_llm <- function(new_papers, profile, llm_config, model_size, on_result = NULL,
                       batch_checkpoint_file = NULL) {
  rows <- lapply(seq_len(nrow(new_papers)), function(i) {
    row <- make_result(new_papers[i, , drop = FALSE], fake_scores[i])
    if (!is.null(on_result)) on_result(row)
    row
  })
  dplyr::bind_rows(rows)
}
process_papers_with_llm <- normal_llm

update_calls <- 0L
update_history <- function(history, results_df, history_file) {
  update_calls <<- update_calls + 1L
  updated <- dplyr::bind_rows(history, results_df)
  write.csv(updated, history_file, row.names = FALSE)
  invisible(updated)
}

old_template <- PAPER_TEMPLATE_FILE
PAPER_TEMPLATE_FILE <- tempfile(fileext = ".md")
writeLines(c("{title}", "{score}", "{reason}"), PAPER_TEMPLATE_FILE)

# --- Full output, all papers, checkpointed history ---
history_file <- tempfile(fileext = ".csv")
md_file <- tempfile(fileext = ".md")
update_calls <- 0L
result <- run_paper_set(
  papers_filtered = papers, history_file = history_file, profile = profile_fixture,
  llm_config = list(backend = "openai_compatible"), model_size = "large",
  recommendation_threshold = 50, max_papers = Inf, md_file = md_file, checkpoint_every = 2
)
expect_true(nrow(result$results) == 5L, "Backlog mode should score every paper when max_papers is infinite.")
expect_true(update_calls == 3L, "Checkpointing should write after 2, 4, and the final paper.")
expect_true(nrow(read.csv(history_file)) == 5L, "Every scored paper should reach history.")
digest <- readLines(md_file)
expect_true(any(grepl("Paper 1", digest, fixed = TRUE)) && any(grepl("Paper 3", digest, fixed = TRUE)),
            "Papers above the threshold should be written.")
expect_false(any(grepl("Paper 4", digest, fixed = TRUE)), "Papers below the threshold should be filtered out.")
expect_true(any(grepl("Papers analyzed: 5", digest, fixed = TRUE)) &&
              any(grepl("Recommended papers: 3", digest, fixed = TRUE)),
            "The digest header should report the analyzed and included counts.")

# --- Daily max_papers is still honored and writes history once ---
history_file_daily <- tempfile(fileext = ".csv")
md_file_daily <- tempfile(fileext = ".md")
update_calls <- 0L
limited <- run_paper_set(
  papers_filtered = papers, history_file = history_file_daily, profile = profile_fixture,
  llm_config = list(backend = "openai_compatible"), model_size = "large",
  recommendation_threshold = 50, max_papers = 2, md_file = md_file_daily
)
expect_true(nrow(limited$results) == 2L, "A finite max_papers must still cap the paper set.")
expect_true(update_calls == 1L, "Without checkpointing, history should be written once.")
expect_true(nrow(read.csv(history_file_daily)) == 2L, "Only the selected papers should reach history.")

# --- Top-N output, custom header, and count label ---
md_file_top <- tempfile(fileext = ".md")
topped <- run_paper_set(
  papers_filtered = papers, history_file = tempfile(fileext = ".csv"), profile = profile_fixture,
  llm_config = list(backend = "openai_compatible"), model_size = "large",
  recommendation_threshold = 50, max_papers = Inf, md_file = md_file_top,
  output_max = 2, header_extra = "Source: First-run backlog",
  count_label = "Papers included"
)
top_digest <- readLines(md_file_top)
expect_true(any(grepl("Source: First-run backlog", top_digest, fixed = TRUE)),
            "The backlog source should appear in the digest header.")
expect_true(any(grepl("Papers included: 2", top_digest, fixed = TRUE)),
            "The custom count label should be used.")
expect_true(any(grepl("Paper 1", top_digest, fixed = TRUE)) &&
              any(grepl("Paper 2", top_digest, fixed = TRUE)) &&
              !any(grepl("Paper 3", top_digest, fixed = TRUE)),
            "Top-N should keep only the highest-scoring papers.")

# --- Interruption resumes from the last checkpoint without duplicates ---
history_file_resume <- tempfile(fileext = ".csv")
md_file_resume <- tempfile(fileext = ".md")
interrupted_llm <- function(new_papers, profile, llm_config, model_size, on_result = NULL,
                            batch_checkpoint_file = NULL) {
  for (i in seq_len(min(3L, nrow(new_papers)))) {
    row <- make_result(new_papers[i, , drop = FALSE], fake_scores[i])
    if (!is.null(on_result)) on_result(row)
    if (i == 3L) stop("simulated interruption")
  }
}
process_papers_with_llm <- interrupted_llm
interrupted <- tryCatch(
  run_paper_set(
    papers_filtered = papers, history_file = history_file_resume, profile = profile_fixture,
    llm_config = list(backend = "openai_compatible"), model_size = "large",
    recommendation_threshold = 50, max_papers = Inf, md_file = md_file_resume, checkpoint_every = 2
  ),
  error = identity
)
expect_true(inherits(interrupted, "error"), "The simulated interruption should propagate.")
expect_true(nrow(read.csv(history_file_resume)) == 2L,
            "Checkpointed papers should survive an interruption.")

process_papers_with_llm <- normal_llm
resumed <- run_paper_set(
  papers_filtered = papers, history_file = history_file_resume, profile = profile_fixture,
  llm_config = list(backend = "openai_compatible"), model_size = "large",
  recommendation_threshold = 50, max_papers = Inf, md_file = md_file_resume, checkpoint_every = 2
)
resumed_history <- read.csv(history_file_resume)
expect_true(nrow(resumed_history) == 5L, "Resuming should add the remaining papers.")
expect_true(length(unique(resumed_history$doi)) == 5L, "Resuming must not duplicate already-scored papers.")
expect_true(nrow(resumed$new_papers) == 3L, "The resumed run should only process the remaining papers.")

# --- run_backlog_papers records ignored rows and writes a separate digest ---
backlog_history <- tempfile(fileext = ".csv")
recommendations_file_path <- function() backlog_history
out_dir <- tempfile("paper-monitor-backlog-out-")
dir.create(out_dir)
output_config <- list(output_folder = out_dir, recommendation_threshold = 50, max_papers = 25)
process_papers_with_llm <- normal_llm

selected <- papers[1:3, , drop = FALSE]
ignored <- papers[4:5, , drop = FALSE]
backlog <- run_backlog_papers(
  selected, ignored, profile_fixture,
  list(backend = "openai_compatible"), output_config,
  output_mode = "full", checkpoint_every = 2
)
expect_true(file.exists(backlog$digest_file), "The backlog digest should be written.")
expect_true(startsWith(basename(backlog$digest_file), "Backlog_"),
            "The backlog digest must use its own file name.")
expect_true(backlog$processed_count == 3L && backlog$ignored_count == 2L,
            "The result should report scored and ignored counts.")
backlog_history_data <- read.csv(backlog_history)
expect_true(nrow(backlog_history_data) == 5L, "Ignored and scored papers should all be in history.")
ignored_rows <- backlog_history_data[backlog_history_data$category == "ignored", , drop = FALSE]
expect_true(nrow(ignored_rows) == 2L && all(is.na(ignored_rows$score)),
            "Ignored rows must have no score.")
backlog_digest <- readLines(backlog$digest_file)
expect_true(any(grepl("Source: First-run backlog", backlog_digest, fixed = TRUE)),
            "The backlog digest should identify its source.")
expect_true(any(grepl("Ignored (not scored): 2", backlog_digest, fixed = TRUE)),
            "The backlog digest should report ignored papers.")

missing_folder <- tryCatch(
  run_backlog_papers(
    selected, ignored, profile_fixture,
    list(backend = "openai_compatible"),
    list(output_folder = file.path(out_dir, "missing"), recommendation_threshold = 50),
    output_mode = "full"
  ),
  error = identity
)
expect_true(inherits(missing_folder, "error"),
            "A missing output folder must stop before any scoring.")

# --- Top-N ignores the recommendation threshold ---
out_dir_top <- tempfile("paper-monitor-backlog-top-")
dir.create(out_dir_top)
backlog_history_top <- tempfile(fileext = ".csv")
recommendations_file_path <- function() backlog_history_top
top_backlog <- run_backlog_papers(
  selected, ignored, profile_fixture,
  list(backend = "openai_compatible"),
  list(output_folder = out_dir_top, recommendation_threshold = 50, max_papers = 25),
  output_mode = "top_n", top_n = 2, checkpoint_every = 2
)
top_backlog_digest <- readLines(top_backlog$digest_file)
expect_true(any(grepl("Papers included: 2", top_backlog_digest, fixed = TRUE)),
            "Top-N should include exactly N papers.")
expect_true(any(grepl("Selection: top 2 by score", top_backlog_digest, fixed = TRUE)),
            "Top-N should describe the score-based selection.")
expect_true(any(grepl("Paper 1", top_backlog_digest, fixed = TRUE)) &&
              any(grepl("Paper 2", top_backlog_digest, fixed = TRUE)) &&
              !any(grepl("Paper 3", top_backlog_digest, fixed = TRUE)),
            "Top-N should keep the highest scores, even below the usual threshold.")

# --- Must-read output uses the 90-point boundary ---
out_dir_must <- tempfile("paper-monitor-backlog-must-")
dir.create(out_dir_must)
backlog_history_must <- tempfile(fileext = ".csv")
recommendations_file_path <- function() backlog_history_must
must_backlog <- run_backlog_papers(
  selected, ignored, profile_fixture,
  list(backend = "openai_compatible"),
  list(output_folder = out_dir_must, recommendation_threshold = 50, max_papers = 25),
  output_mode = "must_read", checkpoint_every = 2
)
must_digest <- readLines(must_backlog$digest_file)
expect_true(any(grepl("Must-read papers: 1", must_digest, fixed = TRUE)),
            "Must-read output should include only score >= 90.")
expect_true(any(grepl("Paper 1", must_digest, fixed = TRUE)) &&
              !any(grepl("Paper 2", must_digest, fixed = TRUE)),
            "Papers below 90 must not appear in must-read output.")

# --- Daily wrapper keeps its behavior after the refactor ---
daily_history <- tempfile(fileext = ".csv")
daily_md <- tempfile(fileext = ".md")
get_papers <- function(...) papers[1:3, , drop = FALSE]
load_research_profile <- function(...) profile_fixture
process_papers_with_llm <- normal_llm
daily_result <- run_daily_papers(
  json_file = "unused", history_file = daily_history,
  llm_config = list(backend = "openai_compatible"), model_size = "large",
  recommendation_threshold = 50, max_papers = 2, md_file = daily_md
)
expect_true(nrow(daily_result) == 2L, "The daily wrapper should still honor max_papers.")
expect_true(nrow(read.csv(daily_history)) == 2L, "The daily wrapper should still write history.")
daily_digest <- readLines(daily_md)
expect_false(any(grepl("Source: First-run backlog", daily_digest, fixed = TRUE)),
             "The daily digest must not inherit the backlog header.")

PAPER_TEMPLATE_FILE <- old_template

cat("backlog_pipeline_tests: PASS\n")
