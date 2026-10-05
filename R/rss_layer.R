# ==================================================
# rss_layer.R — RSS Data Fetching Layer
# ==================================================

suppressPackageStartupMessages({
  library(xml2)
  library(dplyr)
  library(purrr)
  library(tibble)
  library(stringr)
})

# --------------------------------------------------
# Shared XML helper (replaces get_field() in each parser)
# --------------------------------------------------

get_xml_field <- function(item, field) {
  nodes <- xml_children(item)
  idx   <- which(xml_name(nodes) == field)
  if (length(idx) == 0) return(NA_character_)
  xml_text(nodes[[idx[1]]])
}

resolve_rss_document <- function(rss_url = NULL, rss = NULL) {
  if (!is.null(rss)) return(rss)
  if (is.null(rss_url) || !nzchar(rss_url)) stop("An RSS URL or XML document is required.")
  read_xml(rss_url)
}

# --------------------------------------------------
# AGU / Wiley parser
# --------------------------------------------------

extract_rss_agu <- function(rss_url = NULL, rss = NULL) {

  rss   <- resolve_rss_document(rss_url, rss)
  items <- xml_find_all(rss, "//item")

  parse_item <- function(item) {
    nodes  <- xml_children(item)
    fields <- tibble(
      field = xml_name(nodes),
      value = xml_text(nodes)
    )
    get <- function(name, n = 1) {
      x <- fields$value[fields$field == name]
      if (length(x) < n) return(NA_character_)
      str_squish(x[n])
    }
    tibble(
      title    = get("title"),
      abstract = clean_agu_abstract(get("encoded")),
      authors  = get("creator"),
      journal  = get("publicationName"),
      doi      = get("doi"),
      url      = get("url"),
      pubdate  = get("coverDate")
    )
  }

  bind_rows(map(items, possibly(parse_item, otherwise = NULL)))
}

clean_agu_abstract <- function(x) {
  if (is.na(x) || !nzchar(x)) return(NA_character_)
  txt <- tryCatch(
    xml2::xml_text(xml2::read_html(paste0("<div>", x, "</div>"))),
    error = function(e) x
  )
  txt <- str_squish(txt)
  sub("^Abstract:?\\s*", "", txt, ignore.case = TRUE)
}

# --------------------------------------------------
# Springer parser
# --------------------------------------------------

extract_rss_springer <- function(rss_url = NULL, journal_name, rss = NULL) {

  rss   <- resolve_rss_document(rss_url, rss)
  items <- xml_find_all(rss, "//item")

  parse_item <- function(item) {
    abstract <- get_xml_field(item, "description")
    if (identical(abstract, "")) abstract <- NA_character_
    # <guid> is a full URL (https://link.springer.com/10.xxxx/... or https://doi.org/...)
    # Strip the prefix to recover the bare DOI, matching the other parsers' format
    raw_guid <- get_xml_field(item, "guid")
    doi <- sub("^https?://(link\\.springer\\.com|doi\\.org)/", "", raw_guid, perl = TRUE)
    tibble(
      title    = get_xml_field(item, "title"),
      abstract = abstract,
      authors  = NA_character_,
      journal  = journal_name,
      doi      = doi,
      url      = get_xml_field(item, "link"),
      pubdate  = get_xml_field(item, "pubDate")
    )
  }

  bind_rows(map(items, possibly(parse_item, otherwise = NULL)))
}

# --------------------------------------------------
# EGU / Copernicus parser
# --------------------------------------------------

extract_rss_egu <- function(rss_url = NULL, journal_name, rss = NULL) {

  rss   <- resolve_rss_document(rss_url, rss)
  items <- xml_find_all(rss, "//item")

  parse_item <- function(item) {
    info <- parse_egu_description(get_xml_field(item, "description"))
    tibble(
      title    = get_xml_field(item, "title"),
      abstract = info$abstract,
      authors  = info$authors,
      journal  = journal_name,
      doi      = sub("^https?://doi\\.org/", "", get_xml_field(item, "guid"), perl = TRUE),
      url      = get_xml_field(item, "link"),
      pubdate  = get_xml_field(item, "pubDate")
    )
  }

  bind_rows(map(items, possibly(parse_item, otherwise = NULL)))
}

parse_egu_description <- function(desc) {
  desc  <- gsub("\r", "", desc)
  desc  <- gsub("\n", " ", desc)
  desc  <- gsub("<br\\s*/?>", "\n", desc)
  lines <- trimws(unlist(strsplit(desc, "\n")))
  lines <- lines[nzchar(lines)]
  list(
    authors  = if (length(lines) >= 2) lines[2] else NA_character_,
    citation = if (length(lines) >= 3) lines[3] else NA_character_,
    abstract = if (length(lines) >= 4) paste(lines[4:length(lines)], collapse = " ")
               else NA_character_
  )
}

# --------------------------------------------------
# Royal Society parser
# --------------------------------------------------

extract_rss_royalsociety <- function(rss_url = NULL, journal_name, rss = NULL) {

  rss   <- resolve_rss_document(rss_url, rss)
  items <- xml_find_all(rss, "//item")

  parse_item <- function(item) {
    tibble(
      title    = get_xml_field(item, "title"),
      abstract = extract_royalsociety_abstract(get_xml_field(item, "description")),
      authors  = NA_character_,
      journal  = journal_name,
      doi      = get_xml_field(item, "doi"),
      url      = get_xml_field(item, "link"),
      pubdate  = get_xml_field(item, "pubDate")
    )
  }

  bind_rows(map(items, possibly(parse_item, otherwise = NULL)))
}

extract_royalsociety_abstract <- function(desc) {
  desc <- gsub("<[^>]+>", " ", desc)
  desc <- gsub("\\s+", " ", desc)
  desc <- trimws(desc)
  sub("^Abstract\\s*", "", desc)
}

# --------------------------------------------------
# Generic fallback parser (standard RSS fields only)
# --------------------------------------------------
# Used for feeds that don't match one of the specialized parsers above.
# DOI and authors aren't part of standard RSS, so they're left NA here;
# a dedicated parser is still required to populate them for a given feed.

extract_rss_generic <- function(rss_url = NULL, journal_name, rss = NULL) {

  rss   <- resolve_rss_document(rss_url, rss)
  items <- xml_find_all(rss, "//item")

  parse_item <- function(item) {
    desc <- get_xml_field(item, "description")
    abstract <- if (is.na(desc)) NA_character_ else trimws(gsub("\\s+", " ", gsub("<[^>]+>", " ", desc)))
    tibble(
      title    = get_xml_field(item, "title"),
      abstract = abstract,
      authors  = NA_character_,
      journal  = journal_name,
      doi      = NA_character_,
      url      = get_xml_field(item, "link"),
      pubdate  = get_xml_field(item, "pubDate")
    )
  }

  bind_rows(map(items, possibly(parse_item, otherwise = NULL)))
}

# --------------------------------------------------
# Text cleaning helpers
# --------------------------------------------------

clean_rss_text <- function(x) {
  x <- decode_unicode_tags(x)
  x <- enc2utf8(x)
  # Zero-width space/joiner/non-joiner (U+200B-U+200D) and BOM (U+FEFF).
  # Written as \u escapes (pure ASCII in the source file) instead of literal
  # Unicode characters, so the regex pattern parses correctly regardless of
  # the locale R is invoked under (e.g. Apple Shortcuts uses a non-UTF-8
  # locale, which corrupted literal multibyte chars in the source file).
  x <- gsub("[\u200B-\u200D\uFEFF]", "", x, perl = TRUE)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

decode_unicode_tags <- function(x) {
  if (is.null(x)) return(NA_character_)
  x <- as.character(x)
  # str_replace_all passes all matches in x as one vector and requires the
  # replacement to be a same-length vector; intToUtf8() defaults to
  # multiple = FALSE (collapsing into a single string), so it must be set
  # explicitly here to return one decoded character per match.
  stringr::str_replace_all(x, "<U\\+([0-9A-Fa-f]+)>", function(m) {
    code <- stringr::str_match(m, "<U\\+([0-9A-Fa-f]+)>")[, 2]
    intToUtf8(strtoi(code, 16L), multiple = TRUE)
  })
}

remove_redundant_text_before_math <- function(x) {
  pattern <- "([^[:space:]]+)\\s+\\$([^$]+)\\$"
  m       <- gregexpr(pattern, x, perl = TRUE)
  regmatches(x, m) <- lapply(regmatches(x, m), function(matches) {
    vapply(matches, function(s) {
      parts     <- regmatches(s, regexec(pattern, s, perl = TRUE))[[1]]
      text_part <- toupper(gsub("[^A-Z0-9]", "", parts[2]))
      math_part <- toupper(gsub("[^A-Z0-9]", "", parts[3]))
      if (nchar(text_part) > 0 && identical(text_part, math_part)) {
        paste0("$", parts[3], "$")
      } else {
        s
      }
    }, character(1))
  })
  x
}

clean_paper_fields <- function(df) {
  df |>
    dplyr::mutate(
      dplyr::across(c("title", "abstract", "authors", "journal"), clean_rss_text)
    ) |>
    dplyr::mutate(
      dplyr::across(where(is.character), ~ ifelse(trimws(.x) == "", NA_character_, .x))
    ) |>
    dplyr::mutate(
      dplyr::across(c("title", "abstract"), remove_redundant_text_before_math)
    )
}

normalize_pubdate <- function(x) {
  x   <- trimws(as.character(x))
  out <- rep(as.Date(NA), length(x))

  idx <- grepl("^\\d{4}-\\d{2}-\\d{2}$", x)
  if (any(idx)) out[idx] <- as.Date(x[idx])

  idx <- grepl("^[A-Za-z]{3},", x) & is.na(out)
  if (any(idx)) out[idx] <- as.Date(strptime(x[idx], "%a, %d %b %Y %H:%M:%S %z"))

  idx <- grepl("GMT$", x) & is.na(out)
  if (any(idx)) out[idx] <- as.Date(strptime(sub(" GMT$", "", x[idx]), "%a, %d %b %Y %H:%M:%S"))

  out
}

# --------------------------------------------------
# Feed configuration (feeds.json) and feed health status (feed_status.json)
# --------------------------------------------------
# Depends on read_json_config()/write_json_config() from R/config_layer.R
# and %||% from R/llm_layer.R — both just need to be sourced at some point
# before these functions are actually called, not before they're defined.

FEEDS_CONFIG_PATH <- file.path(CONFIG_DIR, "feeds.json")
FEED_STATUS_PATH  <- file.path(CONFIG_DIR, "feed_status.json")

SPECIALIZED_PARSERS <- c("AGU", "Springer", "EGU", "RoyalSociety")

is_specialized_parser <- function(parser) parser %in% SPECIALIZED_PARSERS

empty_feeds_tibble <- function() {
  tibble(
    journal    = character(),
    rss_url    = character(),
    parser     = character(),
    parser_arg = character(),
    enabled    = logical()
  )
}

load_feeds_config <- function(path = FEEDS_CONFIG_PATH) {
  raw <- read_json_config(path, default = list())
  if (length(raw) == 0) return(empty_feeds_tibble())

  tibble(
    journal    = map_chr(raw, ~ .x$journal %||% NA_character_),
    rss_url    = map_chr(raw, ~ .x$rss_url %||% NA_character_),
    parser     = map_chr(raw, ~ .x$parser %||% NA_character_),
    parser_arg = map_chr(raw, ~ .x$parser_arg %||% NA_character_),
    enabled    = map_lgl(raw, ~ isTRUE(.x$enabled))
  )
}

save_feeds_config <- function(feeds, path = FEEDS_CONFIG_PATH) {
  records <- lapply(seq_len(nrow(feeds)), function(i) as.list(feeds[i, ]))
  write_json_config(records, path)
  invisible(feeds)
}

read_feed_status <- function(path = FEED_STATUS_PATH) {
  raw <- read_json_config(path, default = list())
  if (length(raw) == 0) {
    return(tibble(
      journal     = character(),
      parser_type = character(),
      success     = logical(),
      item_count  = integer(),
      message     = character(),
      timestamp   = character()
    ))
  }

  tibble(
    journal     = map_chr(raw, ~ .x$journal %||% NA_character_),
    parser_type = map_chr(raw, ~ .x$parser_type %||% NA_character_),
    success     = vapply(raw, function(x) if (is.null(x$success)) NA else isTRUE(x$success), logical(1)),
    item_count  = vapply(raw, function(x) if (is.null(x$item_count)) NA_integer_ else as.integer(x$item_count), integer(1)),
    message     = map_chr(raw, ~ .x$message %||% NA_character_),
    timestamp   = map_chr(raw, ~ .x$timestamp %||% NA_character_)
  )
}

write_feed_status <- function(status_list, path = FEED_STATUS_PATH) {
  write_json_config(status_list, path)
  invisible(status_list)
}

# --------------------------------------------------
# Single-feed fetch (shared by get_papers() and the RSS-tab test-fetch preview)
# --------------------------------------------------

rss_feed_title <- function(rss) {
  nodes <- xml_find_all(rss, "/*[local-name()='rss']/*[local-name()='channel']/*[local-name()='title'] | /*[local-name()='feed']/*[local-name()='title']")
  if (length(nodes) == 0) return(NA_character_)
  title <- str_squish(xml_text(nodes[[1]]))
  if (nzchar(title)) title else NA_character_
}

parse_rss_document <- function(rss, parser, journal_name) {
  if (parser == "AGU") {
    extract_rss_agu(rss = rss)
  } else if (parser == "Springer") {
    extract_rss_springer(journal_name = journal_name, rss = rss)
  } else if (parser == "EGU") {
    extract_rss_egu(journal_name = journal_name, rss = rss)
  } else if (parser == "RoyalSociety") {
    extract_rss_royalsociety(journal_name = journal_name, rss = rss)
  } else {
    extract_rss_generic(journal_name = journal_name, rss = rss)
  }
}

rss_fetch_result <- function(data, error, journal, parser) {

  item_count <- if (is.null(data)) 0L else nrow(data)
  success    <- is.null(error) && item_count > 0
  message    <- if (!is.null(error)) {
    error
  } else if (item_count == 0) {
    "RSS returned 0 items"
  } else {
    sprintf("OK (%d items)", item_count)
  }

  list(
    data = data,
    status = list(
      journal     = journal,
      parser_type = if (is_specialized_parser(parser)) "specialized" else "fallback",
      success     = success,
      item_count  = item_count,
      message     = message,
      timestamp   = as.character(Sys.time())
    )
  )
}

rss_parse_quality <- function(data) {
  if (is.null(data) || nrow(data) == 0) return(-Inf)
  fields <- c(title = 5, url = 4, pubdate = 3, abstract = 2, doi = 2, authors = 1)
  present <- vapply(names(fields), function(field) {
    if (!field %in% names(data)) return(0)
    mean(!is.na(data[[field]]) & nzchar(trimws(as.character(data[[field]]))))
  }, numeric(1))
  min(nrow(data), 10L) + sum(present * fields)
}

probe_rss_document <- function(rss, preview_n = 5L) {
  suggested_journal <- rss_feed_title(rss)
  if (is.na(suggested_journal) || !nzchar(suggested_journal)) suggested_journal <- "Untitled RSS feed"
  parsers <- c(SPECIALIZED_PARSERS, "Generic")
  attempts <- lapply(parsers, function(parser) {
    fetched <- tryCatch(
      list(data = parse_rss_document(rss, parser, suggested_journal), error = NULL),
      error = function(e) list(data = NULL, error = conditionMessage(e))
    )
    result <- rss_fetch_result(fetched$data, fetched$error, suggested_journal, parser)
    result$quality <- rss_parse_quality(result$data)
    result$data <- if (is.null(result$data)) NULL else get_papers_sample(result$data, n = preview_n)
    result
  })
  names(attempts) <- parsers
  scores <- vapply(attempts, `[[`, numeric(1), "quality")
  best_parsers <- names(attempts)[scores == max(scores)]
  recommended_parser <- if ("Generic" %in% best_parsers) "Generic" else best_parsers[[1]]
  list(
    rss = rss,
    suggested_journal = suggested_journal,
    recommended_parser = recommended_parser,
    attempts = attempts
  )
}

probe_rss_url <- function(rss_url, preview_n = 5L) {
  rss <- read_xml(rss_url)
  probe_rss_document(rss, preview_n = preview_n)
}

fetch_one_feed <- function(journal, rss_url, parser, parser_arg) {
  journal_name <- if (is.null(parser_arg) || is.na(parser_arg)) journal else parser_arg

  fetched <- tryCatch(
    {
      rss <- read_xml(rss_url)
      list(data = parse_rss_document(rss, parser, journal_name), error = NULL)
    },
    error = function(e) list(data = NULL, error = conditionMessage(e))
  )

  rss_fetch_result(fetched$data, fetched$error, journal, parser)
}

# Preview a single feed without writing to feed_status.json — health status
# is only persisted from real get_papers() runs, not ad-hoc previews.
test_fetch_feed <- function(journal, rss_url, parser, parser_arg, n = 5) {
  fetched <- fetch_one_feed(journal, rss_url, parser, parser_arg)
  list(
    data   = if (is.null(fetched$data)) NULL else get_papers_sample(fetched$data, n = n),
    status = fetched$status
  )
}

# --------------------------------------------------
# Main fetch function
# --------------------------------------------------

get_papers <- function(feeds = NULL) {

  if (is.null(feeds)) feeds <- load_feeds_config()

  papers_list  <- list()
  status_list  <- list()

  for (i in seq_len(nrow(feeds))) {
    journal    <- feeds$journal[i]
    rss_url    <- feeds$rss_url[i]
    parser     <- feeds$parser[i]
    parser_arg <- feeds$parser_arg[i]

    if (!isTRUE(feeds$enabled[i])) {
      status_list[[length(status_list) + 1]] <- list(
        journal     = journal,
        parser_type = if (is_specialized_parser(parser)) "specialized" else "fallback",
        success     = NA,
        item_count  = NA_integer_,
        message     = "Skipped (disabled)",
        timestamp   = as.character(Sys.time())
      )
      next
    }

    fetched <- fetch_one_feed(journal, rss_url, parser, parser_arg)
    status_list[[length(status_list) + 1]] <- fetched$status

    if (!isTRUE(fetched$status$success)) {
      warning(sprintf("\n%s: %s\nRSS: %s", journal, fetched$status$message, rss_url), call. = FALSE)
      next
    }

    papers_list[[length(papers_list) + 1]] <- fetched$data
  }

  write_feed_status(status_list)

  if (length(papers_list) == 0) {
    return(tibble(
      title = character(), abstract = character(), authors = character(),
      journal = character(), doi = character(), url = character(),
      pubdate = as.Date(character())
    ))
  }

  papers <- bind_rows(papers_list) |>
    clean_paper_fields() |>
    mutate(pubdate = normalize_pubdate(pubdate)) |>
    mutate(
      completeness_score =
        (!is.na(title)) + (!is.na(abstract)) +
        (!is.na(authors)) + (!is.na(pubdate))
    )

  papers_with_doi    <- papers |> filter(!is.na(doi)) |>
    arrange(desc(completeness_score)) |> distinct(doi, .keep_all = TRUE)
  papers_without_doi <- papers |> filter(is.na(doi))

  bind_rows(papers_with_doi, papers_without_doi) |>
    select(title, abstract, authors, journal, doi, url, pubdate)
}

# --------------------------------------------------
# Utilities
# --------------------------------------------------

filter_rss_title_prefix <- function(data,
                                    prefixes = c("Correction:", "Issue Information")) {
  stopifnot(is.data.frame(data))
  prefixes_norm <- tolower(trimws(prefixes))
  title_norm    <- tolower(trimws(data$title))
  is_bad <- vapply(title_norm, function(x) {
    !is.na(x) && any(startsWith(x, prefixes_norm))
  }, logical(1))
  dplyr::filter(data, !is_bad)
}

get_papers_sample <- function(df, n = 5) {
  dplyr::slice_head(df, n = n)
}
