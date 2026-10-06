source("R/config_layer.R")
source("R/llm_layer.R")
source("R/llm_provider_layer.R")
source("R/profile_interview_layer.R")
source("R/initial_setup_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_false <- function(value, message) expect_true(!isTRUE(value), message)

valid_profile <- list(
  core_interests = list(list(topic = "Tsunami Science", weight = 0.6), list(topic = "Seismology", weight = 0.4)),
  secondary_interests = list(), emerging_interests = list(), preferred_methods = list(), preferred_domains = list(),
  topic_aliases = list("Tsunami Science" = list("tsunami"), Seismology = list("earthquake")),
  regional_interests = list(), positive_signals = list(), frequent_keywords = list(), frequent_authors = list(),
  frequent_venues = list(), weak_negative_interests = list(), weak_negative_keywords = list(),
  weak_negative_note = "No additional exclusions.", researcher_summary = "A researcher focused on tsunamis and earthquakes."
)
feeds <- data.frame(journal = "Journal A", rss_url = "https://example.com/rss", parser = "Generic", parser_arg = NA_character_, enabled = TRUE)
output_dir <- tempfile("paper-monitor-output-")
dir.create(output_dir)

complete_status <- initial_setup_status(
  llm_cfg = new_llm_provider_config("ollama", "llama3.2"), feeds = feeds,
  profile = valid_profile, output_cfg = list(output_folder = output_dir)
)
expect_true(initial_setup_complete(complete_status), "All four configured steps should be complete.")
expect_true(all(grepl("\\[x\\]", initial_setup_labels(complete_status))), "Completed steps should have a visible marker.")
expect_true(is.na(initial_setup_next_incomplete(complete_status)), "Completed setup should not have a next step.")

missing_feed_status <- initial_setup_status(
  llm_cfg = new_llm_provider_config("ollama", "llama3.2"), feeds = feeds[0, ],
  profile = valid_profile, output_cfg = list(output_folder = output_dir)
)
expect_false(initial_setup_complete(missing_feed_status), "Missing feeds should keep setup incomplete.")
expect_true(identical(missing_feed_status[[2]]$id, "feeds") && !missing_feed_status[[2]]$complete, "Feed status should identify the missing requirement.")
expect_true(identical(initial_setup_next_incomplete(missing_feed_status), 2L), "Setup should skip completed steps and continue with the first missing step.")

paper_expressions <- parse("Paper_Monitor.R")
initial_setup_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "action_initial_setup <-")
}, logical(1)))]]
eval(initial_setup_expression, envir = globalenv())

run_initial_setup_step_test <- function(step_index) {
  state <- new.env(parent = emptyenv())
  state$finished <- FALSE
  make_status <- function(finished) lapply(seq_len(4L), function(i) list(
    id = c("llm", "feeds", "profile", "output")[[i]],
    label = c("LLM provider", "RSS feeds", "Research profile", "Output folder")[[i]],
    complete = finished || i != step_index
  ))
  initial_setup_status <<- function() make_status(state$finished)
  initial_setup_complete <<- function(status) all(vapply(status, `[[`, logical(1), "complete"))
  initial_setup_next_incomplete <<- function(status) which(!vapply(status, `[[`, logical(1), "complete"))[[1]]
  initial_setup_labels <<- function(status) character()
  prompt_cli_page <<- function(...) list(value = "b")
  expected_cancel <- c(c = "Cancel initial setup")
  action_llm_settings <<- function(setup_mode = FALSE) {
    expect_true(step_index == 1L && setup_mode, "LLM setup should receive setup mode.")
    state$finished <- TRUE
  }
  action_manage_feeds <<- function(exit_commands = c(b = "Back")) {
    expect_true(step_index == 2L && identical(exit_commands, expected_cancel), "RSS setup should receive the cancel command vector.")
    state$finished <- TRUE
  }
  action_research_profile <<- function(exit_commands = c(b = "Back")) {
    expect_true(step_index == 3L && identical(exit_commands, expected_cancel), "Profile setup should receive the cancel command vector.")
    state$finished <- TRUE
  }
  action_output_settings <<- function(exit_commands = c(b = "Back")) {
    expect_true(step_index == 4L && identical(exit_commands, expected_cancel), "Output setup should receive the cancel command vector.")
    state$finished <- TRUE
  }
  action_initial_setup()
}

for (step_index in seq_len(4L)) run_initial_setup_step_test(step_index)

cat("initial_setup_tests: PASS\n")
