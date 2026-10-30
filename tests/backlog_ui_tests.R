source("R/config_layer.R")
source("R/llm_layer.R")
source("R/scoring_layer.R")
source("R/backlog_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_false <- function(value, message) expect_true(!isTRUE(value), message)

paper_expressions <- parse("Paper_Monitor.R")
extract_expression <- function(prefix) {
  idx <- which(vapply(paper_expressions, function(x) {
    startsWith(paste(deparse(x), collapse = ""), prefix)
  }, logical(1)))
  if (length(idx) != 1L) stop("Expected exactly one expression for ", prefix, call. = FALSE)
  paper_expressions[[idx]]
}
eval(extract_expression(".action_backlog_exit_deferred <-"), envir = globalenv())
eval(extract_expression("action_backlog_setup <-"), envir = globalenv())
eval(extract_expression("action_initial_setup <-"), envir = globalenv())

output_dir <- tempfile("paper-monitor-backlog-ui-")
dir.create(output_dir)
profile_fixture <- list(must_read_scope = "research_direction", must_read_focus = NULL)
scan_papers <- data.frame(
  doi = paste0("10.1/", 1:5),
  title = paste("Paper", 1:5),
  authors = "A", abstract = "Abstract", journal = "J",
  pubdate = as.Date(c("2026-10-05", "2026-10-04", "2026-10-03", "2026-10-02", "2026-10-01")),
  stringsAsFactors = FALSE
)
scan_fixture <- list(
  papers = scan_papers, fetched_count = 5L, history_count = 0L, new_count = 5L,
  failed_feeds = data.frame()
)
estimate_fixture <- list(
  count = 5L, input_tokens = 5000, output_tokens = 1500, sampled_prompts = 5L,
  min_seconds = 25, max_seconds = 75, time_note = "",
  output_blocks = 5L, output_bytes = 10000,
  drain = list(backlog = 5L, simple_days = 1L, net_days = 1L, daily_inflow = 0.5, can_clear = TRUE)
)

page_queue <- list()
text_queue <- list()
yes_queue <- list()
saved <- NULL
run_record <- NULL
ignored_count <- NULL
forced <- NULL

prompt_cli_page <- function(...) {
  value <- page_queue[[1]]
  page_queue <<- page_queue[-1]
  list(kind = "select", value = value)
}
prompt_text <- function(label, default = "") {
  value <- text_queue[[1]]
  text_queue <<- text_queue[-1]
  value
}
prompt_yes_no <- function(label, default = FALSE) {
  value <- yes_queue[[1]]
  yes_queue <<- yes_queue[-1]
  value
}
read_json_config <- function(path, default = list()) {
  if (grepl("llm_config", path, fixed = TRUE)) return(list(backend = "openai_compatible"))
  if (grepl("output_config", path, fixed = TRUE)) {
    return(list(output_folder = output_dir, max_papers = 25L, recommendation_threshold = 50L))
  }
  default
}
load_research_profile <- function(...) profile_fixture
scan_backlog <- function(...) scan_fixture
estimate_backlog <- function(...) estimate_fixture
backlog_decision_pending <- function(...) TRUE
backlog_decision_status_label <- function(...) "not decided"
load_backlog_decision <- function(...) NULL
save_backlog_decision <- function(decision, path = BACKLOG_DECISION_FILE) {
  saved <<- decision
  invisible(decision)
}
load_history <- function(...) data.frame(doi = character(), stringsAsFactors = FALSE)
recommendations_file_path <- function() tempfile(fileext = ".csv")
record_ignored_papers <- function(papers, history, history_file, profile, reason) {
  ignored_count <<- nrow(papers)
  invisible(history)
}
run_backlog_papers <- function(papers, ignored_papers, profile, llm_config, output_config,
                               output_mode, top_n) {
  run_record <<- list(
    papers = papers, ignored_papers = ignored_papers, output_mode = output_mode, top_n = top_n
  )
  list(digest_file = "Backlog_test.md")
}

run_flow <- function(pages, texts = list(), yes = list()) {
  page_queue <<- pages
  text_queue <<- texts
  yes_queue <<- yes
  saved <<- NULL
  run_record <<- NULL
  ignored_count <<- NULL
  action_backlog_setup()
  list(saved = saved, run = run_record, ignored = ignored_count)
}

# --- Pure display helpers ---
summary_lines <- backlog_summary_lines(scan_fixture, estimate_fixture, list(max_papers = 25L))
expect_true(any(grepl("New papers: 5", summary_lines, fixed = TRUE)), "Summary should show the backlog count.")
expect_true(any(grepl("Daily drain at 25 per run", summary_lines, fixed = TRUE)), "Summary should show max_papers.")
confirm_lines <- backlog_confirm_lines(5L, 0L, "top_n", 3L, estimate_fixture)
expect_true(any(grepl("The 3 highest-scoring papers", confirm_lines, fixed = TRUE)),
            "Top-N confirmation should state the score-based selection.")
drain_lines <- backlog_drain_info_lines(scan_fixture, estimate_fixture, list(max_papers = 25L))
expect_true(any(grepl("Estimated completion", drain_lines, fixed = TRUE)), "Drain page should show the ETA.")
drain_lines_no_estimate <- backlog_drain_info_lines(scan_fixture, NULL, list(max_papers = 25L))
expect_true(any(grepl("Estimated completion", drain_lines_no_estimate, fixed = TRUE)),
            "Drain page should still work when token estimation is unavailable.")
skip_lines <- backlog_skip_info_lines(scan_fixture)
expect_true(any(grepl("record 5 papers as ignored", skip_lines, fixed = TRUE)),
            "Skip page should state the ignored count.")
expect_true(identical(format_backlog_seconds(90), "2 min"), "Duration formatting should still work.")

base_name <- file.path(output_dir, sprintf("Backlog_%s.md", Sys.Date()))
writeLines("existing", base_name)
expect_false(identical(backlog_digest_path(output_dir), base_name),
             "An existing backlog digest must not be overwritten.")
writeLines("not json", file.path(output_dir, "bad-decision.json"))
expect_true(identical(backlog_decision_status_label(file.path(output_dir, "bad-decision.json")), "not decided"),
            "A malformed decision file should be treated as not decided.")

# --- Decision flows ---
deferred <- run_flow(list("c"))
expect_true(identical(deferred$saved$mode, "deferred"), "Cancel should save a deferred decision.")

drain <- run_flow(list(2), yes = list(TRUE))
expect_true(identical(drain$saved$mode, "daily_drain"), "Drain should save the daily-drain decision.")
expect_true(is.null(drain$run), "Drain must not score papers immediately.")

skip <- run_flow(list(3), yes = list(TRUE))
expect_true(identical(skip$saved$mode, "skip_all"), "Skip should save the skip-all decision.")
expect_true(identical(skip$ignored, 5L), "Skip should record every scanned paper as ignored.")

all_now <- run_flow(list(1, 1, 1), yes = list(TRUE))
expect_true(identical(all_now$saved$mode, "process_now"), "Process now should save the process decision.")
expect_true(nrow(all_now$run$papers) == 5L, "Process-all should score every scanned paper.")
expect_true(nrow(all_now$run$ignored_papers) == 0L, "Process-all should ignore nothing.")
expect_true(identical(all_now$run$output_mode, "full"), "Process-all should honor the full output choice.")

recent_top <- run_flow(list(1, 2, 3), texts = list("2", "3"), yes = list(TRUE))
expect_true(nrow(recent_top$run$papers) == 2L, "Recent-N should score only the newest N papers.")
expect_true(nrow(recent_top$run$ignored_papers) == 3L, "Recent-N should ignore the remainder.")
expect_true(identical(recent_top$saved$scope, "recent_n") && recent_top$saved$recent_n == 2L,
            "Recent-N should persist the scope and count.")
expect_true(identical(recent_top$run$output_mode, "top_n") && recent_top$run$top_n == 2L,
            "Top-N should be clamped to the selected paper count.")

# --- Force mode can be declined without overwriting the decision ---
backlog_decision_pending <- function(...) FALSE
load_backlog_decision <- function(...) list(mode = "daily_drain", decided_at = "2026-10-30 10:00:00")
prompt_yes_no <- function(label, default = FALSE) FALSE
saved <- NULL
action_backlog_setup(force = TRUE)
expect_true(is.null(saved), "Declining a forced re-run must keep the existing decision.")

# --- Scan retry paths ---
prompt_yes_no <- function(label, default = FALSE) {
  value <- yes_queue[[1]]
  yes_queue <<- yes_queue[-1]
  value
}
zero_scan <- scan_fixture
zero_scan$papers <- scan_papers[0, , drop = FALSE]
zero_scan$new_count <- 0L
zero_scan$failed_feeds <- data.frame(journal = "J", success = FALSE, stringsAsFactors = FALSE)
scan_backlog <- function(...) zero_scan
backlog_decision_pending <- function(...) TRUE
page_queue <- list()
yes_queue <- list(TRUE, FALSE)
saved <- NULL
action_backlog_setup()
expect_true(identical(saved$mode, "skip_all") && saved$backlog_count == 0L,
            "A zero-paper scan with failed feeds should retry, then save a zero skip when declined.")

scan_calls <- 0L
scan_backlog <- function(...) {
  scan_calls <<- scan_calls + 1L
  if (scan_calls == 1L) stop("simulated scan failure")
  scan_fixture
}
page_queue <- list("c")
yes_queue <- list(TRUE)
saved <- NULL
action_backlog_setup()
expect_true(scan_calls == 2L && identical(saved$mode, "deferred"),
            "A failed scan should retry and then honor the defer choice.")
scan_backlog <- function(...) scan_fixture

# --- Initial setup integration: automatic prompt and the k command ---
status_complete <- lapply(1:4, function(i) list(
  id = c("llm", "feeds", "profile", "output")[[i]], label = "step", complete = TRUE
))
initial_setup_status <- function() status_complete
initial_setup_complete <- function(status) TRUE
initial_setup_labels <- function(status) character()

backlog_calls <- 0L
backlog_decision_pending <- function(...) backlog_calls == 0L
action_backlog_setup <- function(force = FALSE) {
  backlog_calls <<- backlog_calls + 1L
  TRUE
}
backlog_decision_status_label <- function(...) "deferred"
prompt_cli_page <- function(...) list(kind = "command", value = "b")
expect_true(action_initial_setup(), "Completed setup should return after the backlog prompt.")
expect_true(backlog_calls == 1L, "Completed setup should open the backlog step once when undecided.")

forced <- NULL
backlog_decision_pending <- function(...) FALSE
action_backlog_setup <- function(force = FALSE) {
  forced <<- force
  FALSE
}
answers <- list("k", "b")
prompt_cli_page <- function(...) {
  value <- answers[[1]]
  answers <<- answers[-1]
  list(kind = "command", value = value)
}
expect_true(action_initial_setup(), "The backlog review command should return to the completed page.")
expect_true(isTRUE(forced), "The initial-setup page should offer a forced backlog review.")

cat("backlog_ui_tests: PASS\n")
