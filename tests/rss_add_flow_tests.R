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
library_page_size_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "RSS_LIBRARY_PAGE_SIZE <-")
}, logical(1)))]]
library_labels_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "rss_library_item_labels <-")
}, logical(1)))]]
add_library_feeds_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "action_add_feeds_from_library <-")
}, logical(1)))]]
feed_labels_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "feed_item_labels <-")
}, logical(1)))]]
manage_feeds_expression <- paper_expressions[[which(vapply(paper_expressions, function(x) {
  startsWith(paste(deparse(x), collapse = ""), "action_manage_feeds <-")
}, logical(1)))]]
eval(preview_lines_expression, envir = globalenv())
eval(feed_detail_expression, envir = globalenv())
eval(add_feed_expression, envir = globalenv())
eval(library_page_size_expression, envir = globalenv())
eval(library_labels_expression, envir = globalenv())
eval(add_library_feeds_expression, envir = globalenv())
eval(feed_labels_expression, envir = globalenv())
eval(manage_feeds_expression, envir = globalenv())

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

rss_library <- load_rss_library()
expect_true(nrow(rss_library) == 50L, "The built-in RSS library should contain 50 journals.")
publisher_counts <- table(rss_library$publisher)
expect_true(
  identical(as.integer(publisher_counts[c("AGU", "EGU", "Royal Society", "Springer")]), c(24L, 20L, 1L, 5L)),
  "The RSS library should contain the approved publisher counts."
)
expect_true(nrow(search_rss_library(rss_library, "SPRINGER")) == 5L, "Library search should be case-insensitive and match publishers.")
expect_true(nrow(search_rss_library(rss_library, "solid earth")) == 2L, "Library search should match journal names.")

selected_library_feeds <- rss_library[c(1L, 25L), , drop = FALSE]
add_result <- add_rss_library_feeds(empty_feeds_tibble(), selected_library_feeds)
expect_true(add_result$added == 2L && add_result$skipped == 0L, "Selected library feeds should be added and enabled.")
expect_true(nrow(add_result$feeds) == 2L && all(add_result$feeds$enabled), "Library additions should produce enabled runtime feeds.")
duplicate_result <- add_rss_library_feeds(add_result$feeds, selected_library_feeds)
expect_true(duplicate_result$added == 0L && duplicate_result$skipped == 2L, "Already-configured feeds should be skipped.")
same_journal <- selected_library_feeds[1L, , drop = FALSE]
same_journal$rss_url <- "https://example.org/a-different-url"
expect_true(rss_library_is_configured(same_journal, add_result$feeds), "A matching journal name should prevent duplicate configuration.")

library_fixture <- rss_library[1:3, , drop = FALSE]
load_rss_library <- function(...) library_fixture
saved_feeds <- NULL
page_calls <- list()
responses <- list(
  list(kind = "select", value = 1L),
  list(kind = "select", value = 2L),
  list(kind = "command", value = "a")
)
action_add_feed <- function(...) stop("The manual add flow should not run during library selection.")
action_add_feeds_from_library(empty_feeds_tibble())
expect_true(nrow(saved_feeds) == 2L, "Multi-selecting library entries should save both feeds together.")
expect_true(all(saved_feeds$journal == library_fixture$journal[1:2]), "The selected library journals should be saved.")
expect_true(any(grepl("Add selected (2)", page_calls[[3]]$commands, fixed = TRUE)), "The library should expose the selected-feed count.")
expect_true(any(grepl("Add RSS URL manually", page_calls[[1]]$commands, fixed = TRUE)), "The RSS library should retain a manual URL option.")

managed_feeds <- empty_feeds_tibble()
library_open_count <- 0L
load_feeds_config <- function(...) managed_feeds
read_feed_status <- function(...) tibble::tibble(
  journal = character(), parser_type = character(), success = logical(),
  item_count = integer(), message = character(), timestamp = character()
)
page_calls <- list()
responses <- list(list(kind = "command", value = "d"))
action_add_feeds_from_library <- function(feeds) {
  library_open_count <<- library_open_count + 1L
  managed_feeds <<- add_rss_library_feeds(feeds, library_fixture[1L, , drop = FALSE])$feeds
  invisible(managed_feeds)
}
setup_result <- action_manage_feeds(exit_commands = c(c = "Cancel initial setup"), setup_mode = TRUE)
expect_true(library_open_count == 1L, "Initial RSS setup should automatically open the library when no feed is enabled.")
expect_true(identical(setup_result, "d"), "Initial RSS setup should continue after the user selects Continue setup.")
expect_true("d" %in% names(page_calls[[1]]$commands), "Continue setup should be available once an enabled feed exists.")
expect_true("m" %in% names(page_calls[[1]]$commands), "Manual RSS entry should remain available in setup mode.")
expect_true(any(grepl("(never run)", page_calls[[1]]$items, fixed = TRUE)), "A feed without status history should show a clean never-run label.")

managed_feeds <- empty_feeds_tibble()
library_open_count <- 0L
page_calls <- list()
responses <- list(list(kind = "command", value = "c"))
action_add_feeds_from_library <- function(feeds) {
  library_open_count <<- library_open_count + 1L
  invisible(feeds)
}
cancel_result <- action_manage_feeds(exit_commands = c(c = "Cancel initial setup"), setup_mode = TRUE)
expect_true(library_open_count == 1L, "The empty setup should offer the library only once before showing the feed page.")
expect_true(identical(cancel_result, "c"), "The RSS page should return its initial-setup cancellation command.")
expect_true(!"d" %in% names(page_calls[[1]]$commands), "Continue setup should stay hidden until an enabled feed exists.")

managed_feeds <- add_result$feeds[1L, , drop = FALSE]
page_calls <- list()
responses <- list(list(kind = "command", value = "b"))
action_add_feeds_from_library <- function(...) stop("Normal feed management should not auto-open the library.")
normal_result <- action_manage_feeds()
expect_true(identical(normal_result, "b"), "Normal feed management should retain its Back action.")
expect_true(!"d" %in% names(page_calls[[1]]$commands), "Continue setup should not appear outside initial setup.")
expect_true(all(c("a", "m", "b") %in% names(page_calls[[1]]$commands)), "Feed management should expose library, manual, and Back actions.")

cat("rss_add_flow_tests: PASS\n")
