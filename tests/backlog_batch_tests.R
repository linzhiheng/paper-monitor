source("R/config_layer.R")
source("R/llm_layer.R")
source("R/profile_interview_layer.R")
source("R/prompt_layer.R")
source("R/scoring_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_false <- function(value, message) expect_true(!isTRUE(value), message)

legacy_profile <- list(
  core_interests = list(list(topic = "Tsunami Science", weight = 1)),
  secondary_interests = list(), emerging_interests = list(), preferred_methods = list(), preferred_domains = list(),
  topic_aliases = list("Tsunami Science" = list("tsunami")), regional_interests = list(), positive_signals = list(),
  frequent_keywords = list(), frequent_authors = list(), frequent_venues = list(), weak_negative_interests = list(),
  weak_negative_keywords = list(), weak_negative_note = "No exclusions.", researcher_summary = "Tsunami science."
)
profile <- normalize_research_profile(legacy_profile)
papers <- data.frame(
  doi = c("10.1/a", "10.1/b"),
  title = c("Paper A", "Paper B"),
  authors = c("A", "B"),
  abstract = c("Abstract A", "Abstract B"),
  journal = c("J", "J"),
  pubdate = as.Date(c("2026-01-01", "2026-01-02")),
  stringsAsFactors = FALSE
)
custom_ids <- c("paper-0001", "paper-0002")
result_a <- list(score = 95, matched_topics = list("tsunami"), reason = "Strong match.", tldr = "Summary A.")
result_b <- list(score = 80, matched_topics = list("earthquake"), reason = "Good match.", tldr = "Summary B.")

# --- State round-trip ---
state_path <- tempfile(fileext = ".json")
.save_batch_state("batch-roundtrip", papers, custom_ids, state_path)
state <- .load_batch_state(state_path)
expect_true(identical(state$batch_id, "batch-roundtrip"), "The batch id should round-trip.")
expect_true(nrow(state$papers) == 2L, "The paper manifest should round-trip.")
expect_true(identical(state$custom_ids, custom_ids), "The custom ids should round-trip.")
expect_true(identical(state$papers$doi, papers$doi), "Paper DOIs should round-trip.")

one_path <- tempfile(fileext = ".json")
.save_batch_state("batch-one", papers[1, , drop = FALSE], "paper-0001", one_path)
one <- .load_batch_state(one_path)
expect_true(nrow(one$papers) == 1L && identical(one$custom_ids, "paper-0001"),
            "A one-paper batch state should round-trip.")

# --- Batch interruption keeps the state; resume does not resubmit ---
submit_calls <- 0L
poll_calls <- 0L
collect_calls <- 0L
poll_fail_first <- TRUE
submit_claude_batch <- function(requests, config) {
  submit_calls <<- submit_calls + 1L
  list(id = "batch-resume-test")
}
poll_claude_batch <- function(batch_id, config, poll_interval = 30L) {
  poll_calls <<- poll_calls + 1L
  if (poll_fail_first) {
    poll_fail_first <<- FALSE
    stop("simulated interruption")
  }
  invisible(NULL)
}
collect_claude_batch <- function(batch_id, config) {
  collect_calls <<- collect_calls + 1L
  list("paper-0001" = result_a, "paper-0002" = result_b)
}

interrupted_path <- tempfile(fileext = ".json")
interrupted <- tryCatch(
  .process_batch(
    papers, profile, list(backend = "claude_batch", poll_interval = 0), "large",
    checkpoint_file = interrupted_path
  ),
  error = identity
)
expect_true(inherits(interrupted, "error"), "The simulated batch interruption should propagate.")
expect_true(file.exists(interrupted_path), "The batch state must survive an interruption.")
expect_true(submit_calls == 1L, "The first attempt should submit exactly one batch.")

seen <- 0L
resumed <- .process_batch(
  papers, profile, list(backend = "claude_batch", poll_interval = 0), "large",
  on_result = function(row) seen <<- seen + 1L,
  checkpoint_file = interrupted_path
)
expect_true(submit_calls == 1L, "Resuming must not submit a second batch.")
expect_true(collect_calls == 1L, "Resuming should collect once.")
expect_true(nrow(resumed) == 2L, "Resuming should finalize both papers.")
expect_true(seen == 2L, "The result callback should see every finalized paper.")
expect_false(file.exists(interrupted_path), "A collected batch state should be removed.")

# --- Resume filters papers that are already in the current set ---
filtered_path <- tempfile(fileext = ".json")
.save_batch_state("batch-filter-test", papers, custom_ids, filtered_path)
poll_fail_first <- FALSE
filtered <- .process_batch(
  papers[2, , drop = FALSE], profile,
  list(backend = "claude_batch", poll_interval = 0), "large",
  checkpoint_file = filtered_path
)
expect_true(nrow(filtered) == 1L, "Only papers still in the current set should be finalized.")
expect_true(identical(filtered$doi, "10.1/b"), "The remaining paper should be the one in the current set.")
expect_false(file.exists(filtered_path), "The filtered batch state should be removed after collection.")
expect_true(identical(
  .batch_paper_is_current(papers, papers),
  c(TRUE, TRUE)
), "Identical paper sets should match on resume.")
expect_true(identical(
  .batch_paper_is_current(papers, papers[2, , drop = FALSE]),
  c(FALSE, TRUE)
), "A smaller current set should match only its own papers.")

# --- Malformed state fails before a new submission ---
bad_path <- tempfile(fileext = ".json")
writeLines("not json", bad_path)
submit_before <- submit_calls
bad <- tryCatch(
  .process_batch(
    papers, profile, list(backend = "claude_batch", poll_interval = 0), "large",
    checkpoint_file = bad_path
  ),
  error = identity
)
expect_true(inherits(bad, "error"), "A malformed batch state should stop the run.")
expect_true(submit_calls == submit_before, "A malformed state must not trigger a new submission.")

cat("backlog_batch_tests: PASS\n")
