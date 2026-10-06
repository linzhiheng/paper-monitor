source("R/llm_layer.R")
source("R/profile_interview_layer.R")

expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}

expect_false <- function(value, message) expect_true(!isTRUE(value), message)

feeds <- data.frame(
  journal = c("Journal A", "Journal B"),
  rss_url = c("https://example.com/a", "https://example.com/b"),
  enabled = c(TRUE, FALSE),
  stringsAsFactors = FALSE
)
state <- new_profile_interview_state(feeds, "中文")
expect_true(length(state$rss_sources) == 1L, "Only enabled RSS sources should be included.")
expect_true(grepl("Journal A", build_profile_interview_prompt(state), fixed = TRUE), "RSS context should be present.")
expect_true(grepl("The interview language is 中文", build_profile_interview_prompt(state), fixed = TRUE), "Selected interview language should be included in the prompt.")
expect_true(tryCatch({ new_profile_interview_state(feeds, "French"); FALSE }, error = function(e) TRUE), "Unsupported interview language should fail.")

empty_state <- new_profile_interview_state(feeds[0, ])
expect_true(grepl("Start the interview from zero", build_profile_interview_prompt(empty_state), fixed = TRUE), "Empty RSS context should use zero-start wording.")
disabled_state <- new_profile_interview_state(transform(feeds, enabled = FALSE))
expect_true(length(disabled_state$rss_sources) == 0L, "Disabled RSS sources should not be included.")

ask <- list(
  action = "ask", current_inference = "A likely focus is seismology.", question = "Is that correct?",
  options = list("Earthquake seismology", "Tsunami science")
)
expect_true(validate_profile_interview_response(ask)$valid, "A valid ask response should pass.")
expect_false(validate_profile_interview_response(list(action = "ask", question = "Missing inference"))$valid, "Incomplete ask response should fail.")
expect_false(validate_profile_interview_response(list(action = "ask", current_inference = "x", question = "y", options = list("Only one")))$valid, "Ask response with too few options should fail.")
expect_false(validate_profile_interview_response(list(action = "ask", current_inference = "x", question = "y", options = list("A", "A")))$valid, "Ask response with duplicate options should fail.")
expect_true(validate_profile_interview_response(list(action = "summarize", summary = "A profile summary."), force_summary = TRUE)$valid, "Forced summary should accept a summary.")
expect_false(validate_profile_interview_response(ask, force_summary = TRUE)$valid, "Forced summary should reject another question.")

options <- c("Option one", "Option two", "Option three")
expect_true(identical(resolve_profile_interview_answer("2", options)$answer, "Option two"), "A numbered answer should map to its option.")
expect_true(identical(resolve_profile_interview_answer("other", options)$status, "other"), "Other should request free text.")
expect_true(identical(resolve_profile_interview_answer("A custom answer", options)$answer, "A custom answer"), "Free text should be retained.")
expect_true(identical(resolve_profile_interview_answer("4", options)$status, "invalid"), "An out-of-range option should be invalid.")
expect_true(identical(resolve_profile_interview_answer("/finish", options)$status, "finish"), "Finish command should be recognized.")

for (i in seq_len(5L)) {
  state <- profile_interview_add_answer(state, "Inference", "Question", c("Option A", "Option B"), paste("Answer", i))
}
expect_true(grepl("questions 6-7", build_profile_interview_prompt(state), fixed = TRUE), "Question 6-7 convergence guidance should be included.")
for (i in 6:7) {
  state <- profile_interview_add_answer(state, "Inference", "Question", c("Option A", "Option B"), paste("Answer", i))
}
expect_true(grepl("question 8", build_profile_interview_prompt(state), fixed = TRUE), "Question 8 convergence guidance should be included.")
state <- profile_interview_add_answer(state, "Inference", "Question", c("Option A", "Option B"), "Answer 8")
expect_true(grepl("Strongly prefer summarize", build_profile_interview_prompt(state), fixed = TRUE), "Post-question-8 convergence guidance should be included.")
for (i in 9:PROFILE_INTERVIEW_HARD_LIMIT) {
  state <- profile_interview_add_answer(state, "Inference", "Question", c("Option A", "Option B"), paste("Answer", i))
}
expect_true(profile_interview_question_count(state) == PROFILE_INTERVIEW_HARD_LIMIT, "Question count should reach the hard limit.")
expect_true(profile_interview_force_summary(state), "Hard limit should force a summary.")
expect_true(grepl("MUST summarize", build_profile_interview_prompt(state, force_summary = TRUE), fixed = TRUE), "Forced prompt should require summary.")
expect_true(grepl("At least 12 questions", build_profile_interview_prompt(state), fixed = TRUE), "Late-stage convergence guidance should be included.")

state <- profile_interview_add_summary_revision(state, "Please include tsunami forecasting.")
expect_true(grepl("tsunami forecasting", build_profile_interview_prompt(state, force_summary = TRUE), fixed = TRUE), "Summary revision should be present in context.")

revision_state <- new_profile_interview_state(feeds)
revision_state <- profile_interview_add_answer(revision_state, "Inference 1", "Question 1", c("A", "B"), "A")
revision_state <- profile_interview_add_answer(revision_state, "Inference 2", "Question 2", c("C", "D"), "D")
revised <- profile_interview_revise_previous_answer(revision_state)
expect_true(profile_interview_question_count(revised$state) == 1L, "Revising should remove only the latest answer.")
expect_true(identical(revised$step$question, "Question 2"), "Revising should restore the latest question.")
expect_true(identical(revised$step$options, c("C", "D")), "Revising should restore the original options.")
expect_true(is.null(profile_interview_revise_previous_answer(new_profile_interview_state(feeds))$step), "The first question should not have a previous answer to revise.")

valid_profile <- list(
  core_interests = list(list(topic = "Tsunami Science", weight = 0.6), list(topic = "Seismology", weight = 0.4)),
  secondary_interests = list(), emerging_interests = list(), preferred_methods = list(), preferred_domains = list(),
  topic_aliases = list("Tsunami Science" = list("tsunami"), Seismology = list("earthquake")),
  regional_interests = list(), positive_signals = list(), frequent_keywords = list(), frequent_authors = list(),
  frequent_venues = list(), weak_negative_interests = list(), weak_negative_keywords = list(),
  weak_negative_note = "No additional exclusions.", researcher_summary = "A researcher focused on tsunamis and earthquakes."
)
expect_true(validate_profile_draft(valid_profile)$valid, "A valid profile should pass.")
invalid_weights <- valid_profile
invalid_weights$core_interests[[2]]$weight <- 0.2
expect_false(validate_profile_draft(invalid_weights)$valid, "Weights that do not sum to one should fail.")
invalid_aliases <- valid_profile
invalid_aliases$topic_aliases <- list("Other Topic" = list("other"))
expect_false(validate_profile_draft(invalid_aliases)$valid, "Alias keys that do not match core topics should fail.")

cat("profile_interview_tests: PASS\n")
