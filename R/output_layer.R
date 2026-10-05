# ==================================================
# output_layer.R — Markdown Output Layer
# ==================================================

suppressPackageStartupMessages({
  library(dplyr)
})

# --------------------------------------------------
# Author formatting
# --------------------------------------------------

format_authors <- function(authors) {
  if (is.na(authors) || authors == "") return("")
  parts <- trimws(strsplit(authors, ",")[[1]])
  parts <- parts[nchar(parts) > 0]
  if (length(parts) == 0) return("")
  if (length(parts) == 1) return(parts[1])
  paste0(parts[1], " et al.")
}

# --------------------------------------------------
# Per-paper Markdown block — template-driven
# --------------------------------------------------

PAPER_TEMPLATE_FILE <- file.path(CONFIG_DIR, "template.md")

# Fallback used when template.md is absent, and the literal content that
# template.md ships with — keeps these in one place so the two can't drift.
DEFAULT_PAPER_TEMPLATE_LINES <- c(
  "## *{title}",
  "",
  "**Score:** {score} - {category}",
  "**Matched Topics:** {matched_topics}",
  "",
  "**Journal:** {journal}",
  "**Authors:** {authors}",
  "**Date:** {date}",
  "**Link:** {link}",
  "",
  "> [!Reason]",
  "> {reason}",
  "",
  "> [!TL;DR]",
  "> {tldr}",
  "",
  "> [!Abstract]",
  "> **{title}**",
  "> {abstract}",
  "",
  "> [!Reader Review]",
  "> Paper_id:: {doi}",
  "> Decision:: `INPUT[inlineSelect(option(Skip/Irrelevant), option(Skim), option(Read), option(Save/Important)):Paper_{paper_number}]`",
  "",
  "---",
  ""
)

read_paper_template <- function() {
  if (file.exists(PAPER_TEMPLATE_FILE)) return(readLines(PAPER_TEMPLATE_FILE, warn = FALSE))
  DEFAULT_PAPER_TEMPLATE_LINES
}

render_paper_block <- function(tmpl_lines, paper) {
  chr <- function(x) if (is.na(x)) "NA" else as.character(x)
  values <- list(
    title          = chr(paper$title),
    score          = chr(paper$score),
    category       = chr(paper$category),
    matched_topics = chr(paper$matched_topics),
    journal        = chr(paper$journal),
    authors        = format_authors(paper$authors),
    date           = chr(paper$pubdate),
    link           = paste0("https://doi.org/", paper$doi),
    reason         = chr(paper$reason),
    tldr           = chr(paper$tldr),
    abstract       = chr(paper$abstract),
    doi            = chr(paper$doi),
    paper_number   = chr(paper$paper_number)
  )
  lines <- tmpl_lines
  for (key in names(values)) {
    lines <- gsub(paste0("{", key, "}"), values[[key]], lines, fixed = TRUE)
  }
  lines
}

# Warns (without blocking generation) if template.md references a
# placeholder we don't know how to fill — e.g. a typo like {abstrct}.
warn_unknown_placeholders <- function(rendered_lines) {
  found <- unique(unlist(regmatches(rendered_lines, gregexpr("\\{[a-z_]+\\}", rendered_lines))))
  if (length(found) > 0) {
    cat("Warning: unrecognized placeholder(s) in template.md:", paste(found, collapse = ", "), "\n")
  }
}

# --------------------------------------------------
# Markdown digest builder
# --------------------------------------------------

build_digest_lines <- function(results_df, threshold) {

  digest <- results_df |>
    filter(score >= threshold) |>
    arrange(desc(score))

  lines <- c(
    "---",
    sprintf("Generated: %s", Sys.Date()),
    sprintf("Papers analyzed: %d", nrow(results_df)),
    sprintf("Recommended papers: %d", nrow(digest)),
    "",
    "---",
    ""
  )

  if (nrow(digest) == 0) {
    return(c(lines, "No papers exceeded the recommendation threshold."))
  }

  tmpl <- read_paper_template()
  for (i in seq_len(nrow(digest))) {
    paper <- list(
      doi = digest$doi[i], title = digest$title[i], score = digest$score[i],
      category = digest$category[i], matched_topics = digest$matched_topics[i],
      journal = digest$journal[i], authors = digest$authors[i],
      pubdate = digest$pubdate[i], reason = digest$reason[i],
      tldr = digest$tldr[i],
      abstract = digest$abstract[i], paper_number = i
    )
    rendered <- render_paper_block(tmpl, paper)
    if (i == 1) warn_unknown_placeholders(rendered)
    lines <- c(lines, rendered)
  }

  lines
}

# --------------------------------------------------
# Write to file
# --------------------------------------------------

write_daily_note <- function(lines, md_file) {
  writeLines(lines, md_file, useBytes = TRUE)
}
