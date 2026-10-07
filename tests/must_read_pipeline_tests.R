source("R/config_layer.R")
source("R/profile_interview_layer.R")
source("R/prompt_layer.R")
source("R/pipeline_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)

profile_file <- tempfile(fileext = ".json")
jsonlite::write_json(list(core_interests = list()), profile_file, auto_unbox = TRUE)
rss_called <- FALSE
get_papers <- function(...) { rss_called <<- TRUE; stop("RSS must not be called") }

error <- tryCatch({
  run_daily_papers(
    json_file = profile_file, history_file = tempfile(fileext = ".csv"), llm_config = list(),
    model_size = "large", recommendation_threshold = 50, max_papers = 1,
    md_file = tempfile(fileext = ".md")
  )
  NULL
}, error = identity)
expect_true(inherits(error, "error") && grepl("Researcher Profile", conditionMessage(error), fixed = TRUE), "Invalid profiles should produce actionable settings guidance.")
expect_true(!rss_called, "Profile validation must happen before RSS fetching.")

cat("must_read_pipeline_tests: PASS\n")
