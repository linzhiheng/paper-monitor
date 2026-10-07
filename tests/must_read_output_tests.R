source("R/config_layer.R")
source("R/output_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)

expect_true(compose_report_reason("research_direction", NA, "", "Overall.") == "Overall.", "Broad-mode output should be unchanged.")
expect_true(grepl("Focus: Direct match — Direct evidence. Overall relevance: Overall.", compose_report_reason("focused", TRUE, "Direct evidence.", "Overall."), fixed = TRUE), "Direct matches should include both explanations.")
expect_true(grepl("Not a direct match", compose_report_reason("focused", FALSE, "Missing evidence.", "Overall."), fixed = TRUE), "False matches should be labeled.")
expect_true(grepl("Match not confirmed", compose_report_reason("focused", NA, "Invalid assessment.", "Overall."), fixed = TRUE), "Unconfirmed matches should be labeled.")

rows <- data.frame(
  doi = c("10.1/a", "10.1/b"), title = c("Included", "Filtered"), score = c(80, 49), category = c("recommended", "peripheral"),
  matched_topics = c("topic", "topic"), journal = c("J", "J"), authors = c("A, B", "C"), pubdate = c("2026-01-01", "2026-01-01"),
  reason = c("Overall.", "Low."), tldr = c("Summary.", "Summary."), abstract = c("Abstract.", "Abstract."),
  must_read_scope = c("focused", "focused"), must_read_focus_match = c(FALSE, TRUE), must_read_focus_reason = c("Missing evidence.", "Direct."),
  stringsAsFactors = FALSE
)
old_template <- PAPER_TEMPLATE_FILE
PAPER_TEMPLATE_FILE <- tempfile(fileext = ".md")
writeLines(c("{title}", "{reason}"), PAPER_TEMPLATE_FILE)
lines <- build_digest_lines(rows, 50)
expect_true(any(grepl("Included", lines, fixed = TRUE)) && !any(grepl("Filtered", lines, fixed = TRUE)), "Threshold filtering should still apply with a custom template.")
expect_true(any(grepl("Focus: Not a direct match", lines, fixed = TRUE)), "Custom templates should receive the composed reason.")
PAPER_TEMPLATE_FILE <- old_template

cat("must_read_output_tests: PASS\n")
