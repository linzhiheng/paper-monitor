source("R/config_layer.R")
source("R/llm_layer.R")
source("R/profile_interview_layer.R")
source("R/prompt_layer.R")
source("R/rss_layer.R")
source("R/scoring_layer.R")
source("R/backlog_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_false <- function(value, message) expect_true(!isTRUE(value), message)

# --- History normalization (all-ignored CSV has no numeric score column) ---
normalized_file <- tempfile(fileext = ".csv")
writeLines(c(
  "doi,title,journal,score,category,processed_date,reason",
  "10.1/a,Paper A,J,NA,ignored,2026-10-30,Initial backlog skip",
  "10.1/b,Paper B,J,NA,ignored,2026-10-30,Initial backlog skip"
), normalized_file)
normalized <- load_history(normalized_file)
expect_true(is.numeric(normalized$score), "History score must be numeric even when every value is NA.")
expect_true(all(is.na(normalized$score)), "Ignored rows must keep an empty score.")
expect_true(all(normalized$category == "ignored"), "Ignored rows must keep their category.")

# --- Deduplication by DOI and by title+journal fallback ---
history <- data.frame(
  doi = c("10.1/a", NA_character_),
  title = c("Paper A", "Same title"),
  journal = c("J", "J"),
  stringsAsFactors = FALSE
)
papers <- data.frame(
  doi = c("10.1/a", NA_character_, NA_character_, "10.1/c", NA_character_),
  title = c("Paper A", "Same title", "Same title", "Paper C", "Different title"),
  journal = c("J", "J", "K", "J", "J"),
  stringsAsFactors = FALSE
)
kept <- deduplicate_papers(papers, history)
expect_true(identical(kept$title, c("Same title", "Paper C", "Different title")),
            "DOI matches and title+journal matches should both be removed.")
expect_true(identical(kept$journal, c("K", "J", "J")),
            "A matching title in a different journal must not be removed.")

missing_keys <- data.frame(
  doi = NA_character_, title = NA_character_, journal = "J", stringsAsFactors = FALSE
)
expect_true(nrow(deduplicate_papers(missing_keys, history)) == 1L,
            "Papers without DOI or title cannot be deduplicated and must be kept.")

# --- Ignored rows carry the agreed fields and provenance ---
ignored_papers <- data.frame(
  doi = c("10.1/x", "10.1/y"),
  title = c("Ignored X", "Ignored Y"),
  authors = c("A, B", "C"),
  abstract = c("Abstract X", "Abstract Y"),
  journal = c("J", "J"),
  pubdate = as.Date(c("2026-01-01", "2026-01-02")),
  stringsAsFactors = FALSE
)
profile <- list(
  must_read_scope = "focused",
  must_read_focus = list(primary_focus = "Tsunami forecasting")
)
reason <- "Ignored during first-run backlog setup."
ignored_row <- .ignored_paper_row(ignored_papers[1, , drop = FALSE], profile, reason)
expect_true(is.na(ignored_row$score), "Ignored rows must not have a score.")
expect_true(identical(ignored_row$category, "ignored"), "Ignored rows must use the ignored category.")
expect_true(identical(ignored_row$reason, reason), "Ignored rows must preserve the reason.")
expect_true(identical(ignored_row$must_read_scope, "focused"), "Ignored rows must preserve the must-read scope.")
expect_true(identical(ignored_row$must_read_primary_focus, "Tsunami forecasting"),
            "Ignored rows must preserve the active primary focus.")
expect_true(is.na(ignored_row$must_read_focus_match), "Ignored rows must not claim a focus match.")

# --- Writing ignored rows appends to history and survives a reload ---
history_file <- tempfile(fileext = ".csv")
history <- data.frame(doi = character(), stringsAsFactors = FALSE)
record_ignored_papers(ignored_papers, history, history_file, profile, reason)
reloaded <- load_history(history_file)
expect_true(nrow(reloaded) == 2L, "Both ignored papers should be recorded.")
expect_true(all(is.na(reloaded$score)), "Reloaded ignored rows must have no score.")
expect_true(all(reloaded$category == "ignored"), "Reloaded ignored rows must keep the ignored category.")
expect_true(all(reloaded$processed_date == as.character(Sys.Date())), "Ignored rows must be dated today.")

# --- A legacy history is backed up before the must-read columns are added ---
legacy_dir <- tempfile("paper-monitor-legacy-")
dir.create(legacy_dir)
legacy_file <- file.path(legacy_dir, "recommendations.csv")
write.csv(data.frame(
  doi = "10.1/legacy", title = "Legacy", authors = "A", abstract = "B", journal = "J",
  pubdate = "2026-01-01", score = 80, category = "recommended",
  matched_topics = "topic", reason = "reason", tldr = "tldr",
  processed_date = "2026-10-29", stringsAsFactors = FALSE
), legacy_file, row.names = FALSE)
legacy_history <- load_history(legacy_file)
record_ignored_papers(ignored_papers[1, , drop = FALSE], legacy_history, legacy_file, profile, reason)
expect_true(file.exists(file.path(legacy_dir, "recommendations.pre-must-read-scope.csv")),
            "A legacy history must be backed up before ignored rows add must-read columns.")
legacy_reloaded <- load_history(legacy_file)
expect_true(nrow(legacy_reloaded) == 2L, "The legacy row and the ignored row must both remain.")
expect_true(legacy_reloaded$score[legacy_reloaded$doi == "10.1/legacy"] == 80,
            "Existing scored rows must keep their score.")

# --- Backlog scan reuses one fetch and excludes history / title noise ---
profile <- list(
  core_interests = list(list(topic = "Tsunami Science", weight = 0.6), list(topic = "Seismology", weight = 0.4)),
  secondary_interests = list(), emerging_interests = list(), preferred_methods = list(), preferred_domains = list(),
  topic_aliases = list("Tsunami Science" = list("tsunami"), Seismology = list("earthquake")),
  regional_interests = list(), positive_signals = list(), frequent_keywords = list(), frequent_authors = list(),
  frequent_venues = list(), weak_negative_interests = list(), weak_negative_keywords = list(),
  weak_negative_note = "No additional exclusions.",
  researcher_summary = "A researcher focused on tsunamis and earthquakes."
)

scan_papers <- data.frame(
  title = c("New paper A", "New paper B", "Correction: ignore me", "Old paper"),
  abstract = c("Abstract A", "Abstract B", "", "Abstract old"),
  authors = c("A", "B", "", "D"),
  journal = c("J1", "J1", "J1", "J2"),
  doi = c("10.1/new-a", "10.1/new-b", "10.1/correction", "10.1/old"),
  pubdate = as.Date(c("2026-10-01", "2026-09-01", "2026-10-02", "2026-08-01")),
  stringsAsFactors = FALSE
)
scan_history_file <- tempfile(fileext = ".csv")
write.csv(data.frame(
  doi = "10.1/old", title = "Old paper", journal = "J2",
  stringsAsFactors = FALSE
), scan_history_file, row.names = FALSE)
get_papers <- function(feeds = NULL) scan_papers
feed_status <- data.frame(
  journal = c("J1", "J2"), success = c(TRUE, FALSE), message = c("ok", "timeout"),
  stringsAsFactors = FALSE
)
scan <- scan_backlog(history_file = scan_history_file, feed_status = feed_status)
expect_true(scan$fetched_count == 3L, "Correction-prefixed titles must be filtered before counting.")
expect_true(scan$history_count == 1L, "The scan should read the existing history.")
expect_true(scan$new_count == 2L, "Only papers absent from history should remain.")
expect_true(nrow(scan$failed_feeds) == 1L, "Failed feeds should be reported separately.")

# --- Recency split keeps the newest N and ignores the rest ---
split_papers <- data.frame(
  title = c("Newest", "Middle", "Oldest", "Unknown date"),
  pubdate = as.Date(c("2026-10-01", "2026-09-01", "2026-08-01", NA)),
  stringsAsFactors = FALSE
)
split <- split_backlog_by_recency(split_papers, 2)
expect_true(identical(split$selected$title, c("Newest", "Middle")), "The newest N papers should be selected.")
expect_true(identical(split$ignored$title, c("Oldest", "Unknown date")), "The remainder should be ignored in date order.")
expect_true(nrow(split_backlog_by_recency(split_papers, 0)$selected) == 0L, "N=0 should select nothing.")
expect_true(nrow(split_backlog_by_recency(split_papers, 10)$ignored) == 0L, "N above the count should ignore nothing.")

# --- Estimates are local and use the configured max_papers ---
estimate <- estimate_backlog(
  scan$papers, profile, list(backend = "openai_compatible"),
  list(max_papers = 25), output_mode = "top_n", top_n = 1
)
expect_true(estimate$count == 2L, "The estimate should use the scanned paper count.")
expect_true(estimate$input_tokens > 0 && estimate$output_tokens > 0, "Token estimates should be positive.")
expect_true(estimate$output_blocks == 1L, "Top-N output should estimate at most N blocks.")
expect_true(estimate$drain$simple_days == 1L, "Two papers at 25 per run should take one day.")
expect_true(is.finite(estimate$drain$daily_inflow), "The date span should produce a daily inflow estimate.")

zero_capacity <- estimate_backlog(
  scan$papers, profile, list(backend = "ollama"),
  list(max_papers = 0), output_mode = "full"
)
expect_true(!zero_capacity$drain$can_clear, "A non-positive max_papers must not report a clearable backlog.")

# --- Decision file round-trip ---
decision_path <- tempfile(fileext = ".json")
expect_true(backlog_decision_pending(decision_path), "A missing decision file is pending.")
save_backlog_decision(new_backlog_decision("skip_all", backlog_count = 2L), decision_path)
decision <- load_backlog_decision(decision_path)
expect_true(identical(decision$mode, "skip_all"), "The decision mode should round-trip.")
expect_true(decision$backlog_count == 2L, "The backlog count should round-trip.")
expect_false(backlog_decision_pending(decision_path), "A saved decision is no longer pending.")
expect_true(grepl("all skipped", backlog_decision_label(decision), fixed = TRUE),
            "The decision label should describe the skip choice.")

deferred_path <- tempfile(fileext = ".json")
save_backlog_decision(new_backlog_decision("deferred"), deferred_path)
expect_true(grepl("deferred", backlog_decision_label(load_backlog_decision(deferred_path)), fixed = TRUE),
            "The deferred decision should be labeled.")
expect_true(grepl("no new papers", backlog_decision_label(new_backlog_decision("skip_all", backlog_count = 0L)), fixed = TRUE),
            "A zero-paper skip should be labeled as no new papers.")

detailed_decision <- new_backlog_decision(
  "process_now", scope = "recent_n", recent_n = 10L, output = "top_n", top_n = 5L
)
detailed_label <- backlog_decision_label(detailed_decision)
expect_true(grepl("recent 10", detailed_label, fixed = TRUE) &&
              grepl("top 5", detailed_label, fixed = TRUE),
            "The decision label should show the recent and top-N counts.")

# --- Formatting helpers ---
expect_true(identical(format_backlog_tokens(1500000), "1.5M"), "Token formatting should use M for millions.")
expect_true(identical(format_backlog_bytes(2048), "2 KB"), "Byte formatting should use KB.")
expect_true(identical(format_backlog_seconds(90), "2 min"), "Duration formatting should use minutes.")

cat("backlog_core_tests: PASS\n")
