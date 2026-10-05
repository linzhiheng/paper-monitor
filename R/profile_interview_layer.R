# ==================================================
# profile_interview_layer.R — Guided Research Profile Interview
# ==================================================

PROFILE_INTERVIEW_SOFT_LIMIT <- 8L
PROFILE_INTERVIEW_HARD_LIMIT <- 15L
PROFILE_INTERVIEW_LANGUAGES <- c("English", "中文", "日本語")

PROFILE_FIELDS <- c(
  "core_interests", "secondary_interests", "emerging_interests", "preferred_methods",
  "preferred_domains", "topic_aliases", "regional_interests", "positive_signals",
  "frequent_keywords", "frequent_authors", "frequent_venues", "weak_negative_interests",
  "weak_negative_keywords", "weak_negative_note", "researcher_summary"
)
PROFILE_STRING_FIELDS <- c("weak_negative_note", "researcher_summary")

PROFILE_SCHEMA_SPEC <- "
Return a JSON object with exactly these fields:
- core_interests: array of {topic: string, weight: number}, weights summing to 1.0, most important first
- secondary_interests: array of strings
- emerging_interests: array of strings
- preferred_methods: array of strings
- preferred_domains: array of strings
- topic_aliases: object mapping each core_interests topic to an array of alias/synonym strings useful for matching paper text
- regional_interests: array of strings
- positive_signals: array of strings
- frequent_keywords: array of strings
- frequent_authors: array of strings
- frequent_venues: array of strings
- weak_negative_interests: array of strings
- weak_negative_keywords: array of strings
- weak_negative_note: string
- researcher_summary: string (2-4 sentence summary of the researcher's focus)
"

.is_nonempty_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(value))
}

profile_interview_rss_sources <- function(feeds) {
  if (is.null(feeds) || nrow(feeds) == 0 || !"enabled" %in% names(feeds)) return(list())
  enabled <- feeds[!is.na(feeds$enabled) & feeds$enabled, , drop = FALSE]
  if (nrow(enabled) == 0) return(list())

  lapply(seq_len(nrow(enabled)), function(i) {
    list(
      journal = as.character(enabled$journal[i]),
      rss_url = as.character(enabled$rss_url[i])
    )
  })
}

new_profile_interview_state <- function(feeds, language = "English") {
  if (!language %in% PROFILE_INTERVIEW_LANGUAGES) stop("Unsupported interview language.")
  list(
    rss_sources = profile_interview_rss_sources(feeds),
    answers = list(),
    summary_revisions = character(),
    language = language
  )
}

profile_interview_question_count <- function(state) length(state$answers %||% list())

profile_interview_force_summary <- function(state) {
  profile_interview_question_count(state) >= PROFILE_INTERVIEW_HARD_LIMIT
}

profile_interview_add_answer <- function(state, inference, question, options, answer) {
  if (profile_interview_force_summary(state)) stop("The interview question limit has been reached.")
  state$answers[[length(state$answers) + 1L]] <- list(
    inference = inference,
    question  = question,
    options   = as.character(options),
    answer    = answer
  )
  state
}

profile_interview_revise_previous_answer <- function(state) {
  answer_count <- profile_interview_question_count(state)
  if (answer_count == 0) return(list(state = state, step = NULL))

  previous <- state$answers[[answer_count]]
  state$answers <- if (answer_count == 1L) list() else state$answers[seq_len(answer_count - 1L)]
  list(
    state = state,
    step = list(
      action = "ask",
      current_inference = previous$inference,
      question = previous$question,
      options = as.character(previous$options)
    )
  )
}

profile_interview_add_summary_revision <- function(state, revision) {
  state$summary_revisions <- c(state$summary_revisions, revision)
  state
}

.profile_interview_context <- function(state) {
  rss_json <- if (length(state$rss_sources) == 0) {
    "No enabled RSS sources are configured. Start the interview from zero."
  } else {
    jsonlite::toJSON(state$rss_sources, auto_unbox = TRUE, pretty = TRUE)
  }

  answers_json <- if (length(state$answers) == 0) {
    "No interview answers have been collected yet."
  } else {
    jsonlite::toJSON(state$answers, auto_unbox = TRUE, pretty = TRUE)
  }

  revisions_json <- if (length(state$summary_revisions) == 0) {
    "No corrections to a previous summary."
  } else {
    jsonlite::toJSON(as.list(state$summary_revisions), auto_unbox = TRUE, pretty = TRUE)
  }

  paste0(
    "Enabled RSS source metadata (journal names and URLs only):\n", rss_json,
    "\n\nInterview history:\n", answers_json,
    "\n\nUser corrections to previous summaries:\n", revisions_json
  )
}

build_profile_interview_prompt <- function(state, force_summary = FALSE) {
  question_count <- profile_interview_question_count(state)
  convergence_note <- if (question_count < 5L) {
    "Ask only questions that materially improve the profile; do not collect every possible detail."
  } else if (question_count < 7L) {
    "You are entering questions 6-7. Ask only about information that would materially change the profile; otherwise summarize."
  } else if (question_count == 7L) {
    "You are about to ask question 8. Make it the final question only if it resolves a material gap; otherwise summarize now."
  } else if (question_count < 12L) {
    "At least 8 questions have been answered. Strongly prefer summarize. Ask only if a material gap prevents a useful profile."
  } else {
    "At least 12 questions have been answered. Do not ask another question unless an absolutely essential fact is still missing; otherwise summarize immediately."
  }
  hard_limit_note <- if (force_summary) {
    "The CLI requires a summary now. You MUST summarize; do not ask another question."
  } else {
    "The CLI has a 15-question safety ceiling. It is not a target; summarize as soon as the profile is useful."
  }

  paste0(
    "You are conducting a one-question-at-a-time interview to build a research profile used to score English-language academic papers.\n\n",
    "Treat RSS metadata only as a tentative clue. If sources are present, first state a concise candidate disciplinary scope in current_inference and ask the user to confirm or correct it. Do not treat RSS metadata as proof of their interests. If no sources are present, begin from zero.\n\n",
    "The interview language is ", state$language %||% "English", ". Write every current inference, question, recommended option, and summary in that language, regardless of the language used in RSS metadata or the user's answers. Give a current inference that the user can correct; do not prescribe their preferences. Ask exactly one focused question at a time. Decide yourself whether more information is needed.\n\n",
    convergence_note, "\n", hard_limit_note, "\n\n",
    "Return ONLY valid JSON with exactly one of these shapes:\n",
    "{\"action\":\"ask\",\"current_inference\":\"...\",\"question\":\"...\",\"options\":[\"...\",\"...\"]}\n",
    "{\"action\":\"summarize\",\"summary\":\"...\"}\n\n",
    "An ask response MUST provide 2 to 4 short, mutually exclusive candidate answers in options. They are recommendations the user can correct, not prescriptions. Do not include an 'other' option: the CLI supplies it.\n",
    "Use action summarize when the profile is sufficiently understood, when the user provided corrections to a previous summary, or when forced to summarize.\n\n",
    .profile_interview_context(state)
  )
}

validate_profile_interview_response <- function(response, force_summary = FALSE) {
  fail <- function(message) list(valid = FALSE, message = message, data = NULL)
  if (!is.list(response) || !.is_nonempty_string(response$action)) {
    return(fail("Response must contain a non-empty action."))
  }

  action <- response$action
  if (force_summary && !identical(action, "summarize")) {
    return(fail("The CLI requires a summarize response."))
  }

  if (identical(action, "ask")) {
    required <- c("action", "current_inference", "question", "options")
    if (!setequal(names(response), required)) return(fail("Ask response has unexpected or missing fields."))
    if (!.is_nonempty_string(response$current_inference) || !.is_nonempty_string(response$question)) {
      return(fail("Ask response must contain a current inference and one non-empty question."))
    }
    options <- response$options
    if ((!is.list(options) && !is.character(options)) || length(options) < 2L || length(options) > 4L ||
        !all(vapply(options, .is_nonempty_string, logical(1))) || anyDuplicated(options)) {
      return(fail("Ask response must contain 2-4 unique, non-empty options."))
    }
    response$options <- as.character(unlist(options, use.names = FALSE))
    return(list(valid = TRUE, message = NULL, data = response[required]))
  }

  if (identical(action, "summarize")) {
    required <- c("action", "summary")
    if (!setequal(names(response), required)) return(fail("Summary response has unexpected or missing fields."))
    if (!.is_nonempty_string(response$summary)) return(fail("Summary response must contain non-empty text."))
    return(list(valid = TRUE, message = NULL, data = response[required]))
  }

  fail("Response action must be ask or summarize.")
}

resolve_profile_interview_answer <- function(input, options) {
  value <- trimws(input %||% "")
  command <- tolower(value)
  if (identical(command, "/cancel")) return(list(status = "cancel", answer = NULL))
  if (identical(command, "/finish")) return(list(status = "finish", answer = NULL))
  if (identical(command, "other")) return(list(status = "other", answer = NULL))
  if (!nzchar(value)) return(list(status = "invalid", answer = NULL))

  option_number <- suppressWarnings(as.integer(value))
  if (!is.na(option_number)) {
    if (option_number >= 1L && option_number <= length(options)) {
      return(list(status = "answer", answer = options[[option_number]]))
    }
    return(list(status = "invalid", answer = NULL))
  }
  list(status = "answer", answer = value)
}

build_profile_draft_prompt <- function(state, summary) {
  paste0(
    "Create a structured academic research profile from the confirmed interview summary and the interview evidence below. ",
    "Use English scientific terms for all topics, aliases, keywords, methods, domains, regions, authors, and venues even if the interview was in another language. ",
    "Do not invent a preference that is unsupported by the interview. Return ONLY valid JSON. No markdown or explanation.\n\n",
    "Confirmed research-profile summary:\n", summary, "\n\n",
    .profile_interview_context(state), "\n\n",
    PROFILE_SCHEMA_SPEC
  )
}

validate_profile_draft <- function(profile, weight_tolerance = 0.01) {
  fail <- function(message) list(valid = FALSE, message = message)
  if (!is.list(profile) || anyDuplicated(names(profile)) || !setequal(names(profile), PROFILE_FIELDS)) {
    return(fail("Profile must contain exactly the required 15 fields."))
  }

  for (field in PROFILE_STRING_FIELDS) {
    if (!.is_nonempty_string(profile[[field]])) {
      return(fail(sprintf("Profile field '%s' must be a non-empty string.", field)))
    }
  }

  list_fields <- setdiff(PROFILE_FIELDS, PROFILE_STRING_FIELDS)
  for (field in list_fields) {
    if (!is.list(profile[[field]])) {
      return(fail(sprintf("Profile field '%s' must be an array or object.", field)))
    }
  }

  core <- profile$core_interests
  if (length(core) == 0) return(fail("Profile must include at least one core interest."))
  topics <- character(length(core))
  weights <- numeric(length(core))
  for (i in seq_along(core)) {
    item <- core[[i]]
    if (!is.list(item) || !.is_nonempty_string(item$topic) ||
        length(item$weight) != 1L || !is.numeric(item$weight) ||
        !is.finite(item$weight) || item$weight < 0) {
      return(fail("Each core interest needs a non-empty topic and non-negative numeric weight."))
    }
    topics[i] <- item$topic
    weights[i] <- item$weight
  }
  if (anyDuplicated(topics)) return(fail("Core-interest topics must be unique."))
  if (abs(sum(weights) - 1) > weight_tolerance) {
    return(fail("Core-interest weights must sum to 1.0."))
  }

  aliases <- profile$topic_aliases
  if (anyDuplicated(names(aliases)) || !setequal(names(aliases), topics)) {
    return(fail("Topic-alias keys must match the core-interest topics."))
  }
  if (any(!vapply(aliases, is.list, logical(1)))) {
    return(fail("Each topic-alias value must be an array."))
  }

  list(valid = TRUE, message = NULL)
}
