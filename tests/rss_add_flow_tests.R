source("R/config_layer.R")
source("R/llm_layer.R")
source("R/rss_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)

paper_expressions <- parse("Paper_Monitor.R")
preview_lines_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "rss_preview_lines <-")
}, logical(1)))]]
feed_detail_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "action_feed_detail <-")
}, logical(1)))]]
add_feed_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "action_add_feed <-")
}, logical(1)))]]
eval(preview_lines_expression, envir = globalenv())
eval(feed_detail_expression, envir = globalenv())
eval(add_feed_expression, envir = globalenv())

sample_data <- tibble::tibble(
  title = "Example paper", abstract = "Example abstract", authors = NA_character_, journal = "Detected Journal",
  doi = NA_character_, url = "https://example.org/paper", pubdate = "Mon, 01 Jan 2024 00:00:00 GMT"
)
make_attempt <- function(score) list(
  data = sample_data,
  status = list(success = TRUE, message = "OK (1 items)"),
  quality = score
)
make_probe <- function() list(
  suggested_journal = "Detected Journal", recommended_parser = "Generic",
  attempts = list(AGU = make_attempt(10), Springer = make_attempt(12), EGU = make_attempt(13), RoyalSociety = make_attempt(12), Generic = make_attempt(14))
)

responses <- list()
text_answers <- character()
saved_feeds <- NULL
probe_calls <- 0L
page_calls <- list()
prompt_text <- function(label, default = "") {
  answer <- text_answers[[1]]
  text_answers <<- text_answers[-1]
  answer
}
prompt_cli_page <- function(title, items = character(), commands = character(), info = character()) {
  page_calls[[length(page_calls) + 1L]] <<- list(title = title, items = items, commands = commands, info = info)
  response <- responses[[1]]
  responses <<- responses[-1]
  response
}
probe_rss_url <- function(...) {
  probe_calls <<- probe_calls + 1L
  make_probe()
}
save_feeds_config <- function(feeds, path = FEEDS_CONFIG_PATH) {
  saved_feeds <<- feeds
  invisible(feeds)
}

responses <- list(list(value = "p"), list(value = 2L), list(value = "e"), list(value = "s"))
text_answers <- c("https://example.org/rss", "Confirmed Journal")
action_add_feed(empty_feeds_tibble())
expect_true(probe_calls == 1L, "Changing parser or journal name should reuse the one downloaded feed document.")
expect_true(nrow(saved_feeds) == 1L, "Confirming should save one feed.")
expect_true(identical(saved_feeds$journal[[1]], "Confirmed Journal"), "The edited journal name should be saved.")
expect_true(identical(saved_feeds$parser[[1]], "Springer"), "The manually selected parser should be saved.")
expect_true(is.na(saved_feeds$parser_arg[[1]]), "The new flow should not require a parser override.")
expect_true(identical(page_calls[[1]]$title, "Add RSS Feed"), "The confirmation view should use the standard Add RSS Feed page.")
expect_true(any(page_calls[[1]]$info == "Preview:"), "The parsed articles should appear inside the standard page information area.")
expect_true(any(grepl("Example paper", page_calls[[1]]$info, fixed = TRUE)), "The standard page should include the parsed article preview.")

saved_feeds <- NULL
probe_calls <- 0L
page_calls <- list()
responses <- list(list(value = "c"))
text_answers <- "https://example.org/rss"
action_add_feed(empty_feeds_tibble())
expect_true(is.null(saved_feeds), "Discarding should not save a feed.")
expect_true(probe_calls == 1L, "Discarding still performs only the initial URL probe.")

page_calls <- list()
responses <- list(list(value = "t"), list(value = "b"), list(value = "b"))
test_fetch_feed <- function(...) list(data = sample_data, status = list(message = "OK (1 items)"))
action_feed_detail(tibble::tibble(
  journal = "Detected Journal", rss_url = "https://example.org/rss", parser = "Generic",
  parser_arg = NA_character_, enabled = TRUE
), 1L)
expect_true(identical(page_calls[[2]]$title, "RSS Feed Test"), "Testing a feed should use its own standard result page.")
expect_true(any(page_calls[[2]]$info == "Preview:"), "The test result page should include a preview section.")
expect_true(any(grepl("Example paper", page_calls[[2]]$info, fixed = TRUE)), "The test result page should include parsed articles.")

cat("rss_add_flow_tests: PASS\n")
