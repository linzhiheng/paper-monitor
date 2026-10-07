source("R/config_layer.R")
source("R/profile_interview_layer.R")
source("R/prompt_layer.R")
source("R/scoring_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)

legacy_profile <- list(
  core_interests = list(list(topic = "Tsunami Science", weight = 1)),
  secondary_interests = list(), emerging_interests = list(), preferred_methods = list(), preferred_domains = list(),
  topic_aliases = list("Tsunami Science" = list("tsunami")), regional_interests = list(), positive_signals = list(),
  frequent_keywords = list(), frequent_authors = list(), frequent_venues = list(), weak_negative_interests = list(),
  weak_negative_keywords = list(), weak_negative_note = "No exclusions.", researcher_summary = "Tsunami science."
)
broad <- normalize_research_profile(legacy_profile)
focused <- broad
focused$must_read_scope <- "focused"
focused$must_read_focus <- list(
  primary_focus = "Direct tsunami source inference", supporting_signals = list("comparable observations"),
  primary_focus_only = FALSE, must_read_definition = "The title and abstract directly evaluate tsunami source inference."
)

base_result <- list(score = 95.5, category = "wrong", matched_topics = list("tsunami source"), reason = "Strong long-term relevance.", tldr = "The study estimates a tsunami source.")
false_result <- c(base_result, list(must_read_focus_match = FALSE, must_read_focus_reason = "The required observation is absent."))
checked <- validate_and_finalize_paper_result(false_result, focused)
expect_true(checked$valid && identical(checked$data$score, 89) && identical(checked$data$category, "recommended"), "A focused non-match should be capped at 89 and recategorized.")

true_result <- c(base_result, list(must_read_focus_match = TRUE, must_read_focus_reason = "Directly tests the focus."))
true_result$score <- 74.5
checked <- validate_and_finalize_paper_result(true_result, focused)
expect_true(checked$data$score == 74.5 && checked$data$category == "potentially_relevant", "A true match must not increase the score.")

warnings <- character()
unconfirmed <- validate_and_finalize_paper_result(base_result, focused, function(x) warnings <<- c(warnings, x))
expect_true(unconfirmed$valid && unconfirmed$data$score == 89 && is.na(unconfirmed$data$must_read_focus_match) && length(warnings) == 1L, "Missing focused fields should fail closed without discarding a valid common result.")

expect_true(derive_recommendation_category(89.9) == "recommended" && derive_recommendation_category(90) == "must_read" && derive_recommendation_category(39.9) == "low_relevance", "Decimal score boundaries should have no gaps.")
bad <- base_result; bad$score <- Inf
expect_true(!validate_and_finalize_paper_result(bad, broad)$valid, "Non-finite common scores should fail validation.")
bad <- base_result; bad$reason <- ""
expect_true(!validate_and_finalize_paper_result(bad, broad)$valid, "Empty common reasons should fail validation.")

broad_prompt <- build_paper_prompt(broad, "small", "Title", "Abstract")
focused_prompt <- build_paper_prompt(focused, "small", "Title", "Abstract")
expect_true(!grepl("must_read_focus_match", broad_prompt, fixed = TRUE), "Research-direction prompts should preserve the old response contract.")
expect_true(grepl("must_read_focus_match", focused_prompt, fixed = TRUE) && grepl("Do not raise the general relevance score", focused_prompt, fixed = TRUE), "Focused prompts should request an independent direct-match judgment.")

paper <- data.frame(doi = "10.1/test", title = "Title", authors = "A", abstract = "Abstract", journal = "J", pubdate = as.Date("2026-01-01"), stringsAsFactors = FALSE)
provider_result <- c(base_result, list(must_read_focus_match = FALSE, must_read_focus_reason = "Missing focus evidence."))
call_llm <- function(...) provider_result
sequential <- .process_sequential(paper, focused, list(backend = "claude"), "small")
submit_claude_batch <- function(...) list(id = "batch-test")
poll_claude_batch <- function(...) invisible(NULL)
collect_claude_batch <- function(...) list("paper-0001" = provider_result)
batch <- .process_batch(paper, focused, list(backend = "claude_batch", poll_interval = 0), "small")
expect_true(identical(names(sequential), names(batch)) && identical(sequential$score, batch$score) && identical(sequential$category, batch$category), "Sequential and Batch paths should finalize to the same result schema and score/category.")

history_dir <- tempfile("history-"); dir.create(history_dir)
history_file <- file.path(history_dir, "recommendations.csv")
old_history <- data.frame(doi = "old", score = 50, stringsAsFactors = FALSE)
write.csv(old_history, history_file, row.names = FALSE)
new_row <- data.frame(doi = "new", score = 80, must_read_scope = "research_direction", must_read_primary_focus = "", must_read_focus_match = NA, must_read_focus_reason = "", stringsAsFactors = FALSE)
update_history(old_history, new_row, history_file)
backup <- file.path(dirname(history_file), "recommendations.pre-must-read-scope.csv")
expect_true(file.exists(backup), "The first history schema expansion should create a sibling backup.")
before <- file.info(backup)$mtime
update_history(read.csv(history_file), new_row, history_file)
expect_true(identical(file.info(backup)$mtime, before), "The history backup must not be overwritten.")

cat("must_read_scoring_tests: PASS\n")
