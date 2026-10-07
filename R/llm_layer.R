# ==================================================
# llm_layer.R — LLM Calling Layer
# Backends: Ollama / Claude (direct) / Claude Batch API
# ==================================================

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

OLLAMA_DEFAULT_URL <- "http://localhost:11434/api/generate"

# Within JSON string literals (tracked via unescaped-quote toggling), raw
# control characters are illegal — models sometimes emit a literal newline
# inside a "reason"/"abstract" value instead of an escaped \n, which breaks
# the parser well before the actual end of the response.
escape_control_chars_in_strings <- function(text) {
  chars <- strsplit(text, "")[[1]]
  if (length(chars) == 0) return(text)
  in_string <- FALSE
  escaped   <- FALSE
  for (i in seq_along(chars)) {
    ch <- chars[i]
    if (in_string) {
      if (escaped) {
        escaped <- FALSE
      } else if (ch == "\\") {
        escaped <- TRUE
      } else if (ch == '"') {
        in_string <- FALSE
      } else if (ch == "\n") {
        chars[i] <- "\\n"
      } else if (ch == "\r") {
        chars[i] <- "\\r"
      } else if (ch == "\t") {
        chars[i] <- "\\t"
      }
    } else if (ch == '"') {
      in_string <- TRUE
    }
  }
  paste0(chars, collapse = "")
}

# Models are told to return raw JSON, but don't always comply. This strips a
# leading/trailing markdown code fence, trims everything outside the first
# {/[ through the last }/] if stray prose remains, normalizes "smart" quotes
# to plain ASCII ones, drops trailing commas before a closing bracket, and
# escapes raw control characters found inside string literals — all common
# ways models produce JSON that looks right but fails strict parsing.
clean_llm_json_text <- function(text) {
  text <- trimws(text)
  text <- sub("^```[a-zA-Z]*\\s*", "", text)
  text <- sub("```\\s*$", "", text)
  text <- trimws(text)

  start <- regexpr("[{[]", text)[1]
  end   <- max(gregexpr("[]}]", text)[[1]])
  if (start > 0 && end >= start) text <- substr(text, start, end)

  text <- gsub("[“”]", '"', text)
  text <- gsub("[‘’]", "'", text)
  text <- escape_control_chars_in_strings(text)
  text <- gsub(",([ \\t\\n\\r]*[}\\]])", "\\1", text, perl = TRUE)

  text
}

# Models also quote terms inside JSON string values with bare " characters
# (e.g. "question":"围绕"地震/海啸"，…") or with typographic “ ” quotes that
# clean_llm_json_text() rewrites into bare ASCII quotes. Both turn otherwise
# valid JSON into invalid JSON. This escapes every quote that cannot be a
# structural closing, so it is a no-op for well-formed JSON.
escape_inner_json_quotes <- function(text) {
  chars <- strsplit(text, "")[[1]]
  if (length(chars) == 0L) return(text)
  out <- character(length(chars))
  in_string <- FALSE
  escaped <- FALSE
  for (i in seq_along(chars)) {
    ch <- chars[i]
    if (escaped) {
      out[i] <- ch
      escaped <- FALSE
      next
    }
    if (identical(ch, "\\")) {
      out[i] <- ch
      escaped <- TRUE
      next
    }
    if (!identical(ch, "\"")) {
      out[i] <- ch
      next
    }
    if (!in_string) {
      in_string <- TRUE
      out[i] <- ch
      next
    }
    rest <- if (i < length(chars)) chars[(i + 1L):length(chars)] else character(0)
    rest <- rest[!rest %in% c(" ", "\t", "\n", "\r")]
    following <- if (length(rest) > 0L) rest[1] else ""
    if (!nzchar(following) || following %in% c(":", ",", "}", "]")) {
      in_string <- FALSE
      out[i] <- ch
    } else {
      out[i] <- "\\\""
    }
  }
  paste0(out, collapse = "")
}

# Parsing escalates from lossless to lossy and keeps the first candidate that
# parses: the raw text with inner quotes escaped (typographic quotes survive),
# then the historical clean path, then the clean path with inner quotes
# escaped. The historical path alone is lossy: rewriting “ ” into " inside a
# string value invalidates JSON that was previously valid.
parse_llm_json_text <- function(text, simplify = TRUE, label = "LLM") {
  if (!is.character(text) || !nzchar(trimws(text))) {
    message(label, " JSON parse failed: no content")
    return(NULL)
  }
  attempts <- list(
    raw = escape_inner_json_quotes(text),
    cleaned = clean_llm_json_text(text),
    cleaned_escaped = escape_inner_json_quotes(clean_llm_json_text(text))
  )
  last_error <- "unknown parse error"
  for (name in names(attempts)) {
    attempted <- attempts[[name]]
    parsed <- tryCatch(
      fromJSON(attempted, simplifyVector = simplify),
      error = function(e) {
        last_error <<- conditionMessage(e)
        NULL
      }
    )
    if (!is.null(parsed)) {
      if (!identical(attempted, text)) message(label, " JSON repaired before parsing.")
      return(parsed)
    }
  }
  message(label, " JSON parse failed: ", last_error)
  NULL
}

# --------------------------------------------------
# Ollama backend
# --------------------------------------------------

call_ollama <- function(prompt, config, simplify = TRUE) {
  url   <- config$url %||% OLLAMA_DEFAULT_URL
  model <- config$model

  resp <- request(url) |>
    req_body_json(list(
      model  = model,
      prompt = prompt,
      stream = FALSE,
      format = "json"
    )) |>
    req_perform()

  result <- resp_body_json(resp)

  parse_llm_json_text(result$response, simplify = simplify, label = "Ollama")
}

# --------------------------------------------------
# Claude direct backend (raw HTTP, no official R SDK)
# --------------------------------------------------

.claude_base_req <- function(api_key) {
  request("https://api.anthropic.com") |>
    req_headers(
      "x-api-key"         = api_key,
      "anthropic-version" = "2023-06-01",
      "content-type"      = "application/json"
    )
}

call_claude <- function(prompt, config, simplify = TRUE) {
  api_key   <- config$api_key
  model     <- config$model %||% "claude-haiku-4-5"
  max_tokens <- config$max_tokens %||% 1024L

  resp <- .claude_base_req(api_key) |>
    req_url_path("/v1/messages") |>
    req_body_json(list(
      model      = model,
      max_tokens = max_tokens,
      messages   = list(list(role = "user", content = prompt))
    )) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) != 200L) {
    message("Claude API error ", resp_status(resp), ": ", resp_body_string(resp))
    return(NULL)
  }

  body <- resp_body_json(resp)
  text <- body$content[[1]]$text

  parse_llm_json_text(text, simplify = simplify, label = "Claude")
}

# --------------------------------------------------
# DeepSeek backend (OpenAI-compatible chat API, raw HTTP)
# --------------------------------------------------

.deepseek_base_req <- function(api_key) {
  request("https://api.deepseek.com") |>
    req_headers(
      "Authorization" = paste("Bearer", api_key),
      "content-type"  = "application/json"
    )
}

call_deepseek <- function(prompt, config, simplify = TRUE) {
  api_key   <- config$api_key
  model     <- config$model %||% "deepseek-chat"
  max_tokens <- config$max_tokens %||% 1024L

  resp <- .deepseek_base_req(api_key) |>
    req_url_path("/chat/completions") |>
    req_body_json(list(
      model           = model,
      max_tokens      = max_tokens,
      messages        = list(list(role = "user", content = prompt)),
      response_format = list(type = "json_object")
    )) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) != 200L) {
    message("DeepSeek API error ", resp_status(resp), ": ", resp_body_string(resp))
    return(NULL)
  }

  body <- resp_body_json(resp)
  text <- body$choices[[1]]$message$content

  parse_llm_json_text(text, simplify = simplify, label = "DeepSeek")
}

# --------------------------------------------------
# Generic OpenAI-compatible backend (raw HTTP, user-supplied base_url)
# --------------------------------------------------

call_openai_compatible <- function(prompt, config, simplify = TRUE) {
  base_url  <- config$base_url
  api_key   <- config$api_key
  model     <- config$model
  max_tokens <- config$max_tokens %||% 1024L

  url <- paste0(sub("/+$", "", base_url), "/chat/completions")

  resp <- request(url) |>
    req_headers(
      "Authorization" = paste("Bearer", api_key),
      "content-type"  = "application/json"
    ) |>
    req_body_json(list(
      model      = model,
      max_tokens = max_tokens,
      messages   = list(list(role = "user", content = prompt))
    )) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) != 200L) {
    message("OpenAI-compatible API error ", resp_status(resp), ": ", resp_body_string(resp))
    return(NULL)
  }

  body <- resp_body_json(resp)
  text <- body$choices[[1]]$message$content

  parse_llm_json_text(text, simplify = simplify, label = "OpenAI-compatible")
}

# --------------------------------------------------
# Claude Batch API — submit
# --------------------------------------------------

submit_claude_batch <- function(requests, config) {
  api_key   <- config$api_key
  model     <- config$model %||% "claude-haiku-4-5"
  max_tokens <- config$max_tokens %||% 1024L

  batch_requests <- lapply(seq_along(requests), function(i) {
    list(
      custom_id = requests[[i]]$custom_id,
      params = list(
        model      = model,
        max_tokens = max_tokens,
        messages   = list(list(role = "user", content = requests[[i]]$prompt))
      )
    )
  })

  resp <- .claude_base_req(api_key) |>
    req_url_path("/v1/messages/batches") |>
    req_body_json(list(requests = batch_requests)) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) != 200L) {
    stop("Batch submit failed (", resp_status(resp), "): ", resp_body_string(resp))
  }

  resp_body_json(resp)
}

# --------------------------------------------------
# Claude Batch API — poll until ended
# --------------------------------------------------

poll_claude_batch <- function(batch_id, config, poll_interval = 30L) {
  api_key <- config$api_key

  repeat {
    resp <- .claude_base_req(api_key) |>
      req_url_path(paste0("/v1/messages/batches/", batch_id)) |>
      req_error(is_error = function(resp) FALSE) |>
      req_perform()

    if (resp_status(resp) != 200L) {
      stop("Batch poll failed (", resp_status(resp), "): ", resp_body_string(resp))
    }

    status <- resp_body_json(resp)

    counts <- status$request_counts
    cat(sprintf(
      "  Batch %s — processing: %d  succeeded: %d  errored: %d\n",
      batch_id,
      counts$processing %||% 0L,
      counts$succeeded  %||% 0L,
      counts$errored    %||% 0L
    ))

    if (identical(status$processing_status, "ended")) return(status)

    Sys.sleep(poll_interval)
  }
}

# --------------------------------------------------
# Claude Batch API — collect results (JSONL)
# --------------------------------------------------

collect_claude_batch <- function(batch_id, config) {
  api_key <- config$api_key

  resp <- .claude_base_req(api_key) |>
    req_url_path(paste0("/v1/messages/batches/", batch_id, "/results")) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) != 200L) {
    stop("Batch results failed (", resp_status(resp), "): ", resp_body_string(resp))
  }

  raw_lines <- strsplit(resp_body_string(resp), "\n", fixed = TRUE)[[1]]
  raw_lines <- raw_lines[nzchar(trimws(raw_lines))]

  results <- list()
  for (line in raw_lines) {
    item <- tryCatch(fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(item)) next

    custom_id <- item$custom_id
    result    <- item$result

    if (!identical(result$type, "succeeded")) {
      results[[custom_id]] <- NULL
      next
    }

    text <- result$message$content[[1]]$text
    parsed <- tryCatch(fromJSON(text), error = function(e) NULL)
    results[[custom_id]] <- parsed
  }

  results
}

# --------------------------------------------------
# Unified entry point
# --------------------------------------------------

call_llm <- function(prompt, config, simplify = TRUE) {
  backend <- config$backend %||% "ollama"

  switch(
    backend,
    ollama            = call_ollama(prompt, config, simplify),
    claude            = call_claude(prompt, config, simplify),
    deepseek          = call_deepseek(prompt, config, simplify),
    openai_compatible = call_openai_compatible(prompt, config, simplify),
    claude_batch      = stop("Use process_papers_with_llm() for batch backend."),
    stop("Unknown backend: ", backend)
  )
}

# --------------------------------------------------
# Test connection — minimal round trip per backend, no JSON-shape
# requirements on the response (unlike call_llm, which expects the
# paper-scoring JSON schema).
# --------------------------------------------------

test_llm_connection <- function(config) {
  backend <- config$backend %||% "ollama"

  tryCatch({
    switch(
      backend,
      ollama = {
        url <- config$url %||% OLLAMA_DEFAULT_URL
        resp <- request(url) |>
          req_body_json(list(model = config$model, prompt = "ping", stream = FALSE)) |>
          req_error(is_error = function(resp) FALSE) |>
          req_perform()
        if (resp_status(resp) == 200L) {
          list(success = TRUE, message = "Connected to Ollama.")
        } else {
          list(success = FALSE, message = paste0("Ollama error ", resp_status(resp), ": ", resp_body_string(resp)))
        }
      },
      claude = ,
      claude_batch = {
        resp <- .claude_base_req(config$api_key) |>
          req_url_path("/v1/messages") |>
          req_body_json(list(
            model      = config$model %||% "claude-haiku-4-5",
            max_tokens = 16L,
            messages   = list(list(role = "user", content = "ping"))
          )) |>
          req_error(is_error = function(resp) FALSE) |>
          req_perform()
        if (resp_status(resp) == 200L) {
          list(success = TRUE, message = "Connected to Claude.")
        } else {
          list(success = FALSE, message = paste0("Claude error ", resp_status(resp), ": ", resp_body_string(resp)))
        }
      },
      openai_compatible = {
        url <- paste0(sub("/+$", "", config$base_url), "/chat/completions")
        resp <- request(url) |>
          req_headers(
            "Authorization" = paste("Bearer", config$api_key),
            "content-type"  = "application/json"
          ) |>
          req_body_json(list(
            model      = config$model,
            max_tokens = 16L,
            messages   = list(list(role = "user", content = "ping"))
          )) |>
          req_error(is_error = function(resp) FALSE) |>
          req_perform()
        if (resp_status(resp) == 200L) {
          list(success = TRUE, message = "Connected to OpenAI-compatible API.")
        } else {
          list(success = FALSE, message = paste0("API error ", resp_status(resp), ": ", resp_body_string(resp)))
        }
      },
      list(success = FALSE, message = paste("Unknown backend:", backend))
    )
  }, error = function(e) list(success = FALSE, message = conditionMessage(e)))
}
