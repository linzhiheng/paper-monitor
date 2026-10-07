# ==================================================
# profile_interview_layer.R — Guided Research Profile Interview
# ==================================================

PROFILE_INTERVIEW_SOFT_LIMIT <- 8L
PROFILE_INTERVIEW_HARD_LIMIT <- 15L
FOCUSED_INTERVIEW_SOFT_LIMIT <- 6L
FOCUSED_INTERVIEW_HARD_LIMIT <- 8L
PROFILE_INTERVIEW_MAX_TOKENS <- 200000L
PROFILE_INTERVIEW_LANGUAGES <- c("English", "中文", "日本語")

LEGACY_PROFILE_FIELDS <- c(
  "core_interests", "secondary_interests", "emerging_interests", "preferred_methods",
  "preferred_domains", "topic_aliases", "regional_interests", "positive_signals",
  "frequent_keywords", "frequent_authors", "frequent_venues", "weak_negative_interests",
  "weak_negative_keywords", "weak_negative_note", "researcher_summary"
)
PROFILE_FIELDS <- c(LEGACY_PROFILE_FIELDS, "must_read_scope", "must_read_focus")
PROFILE_STRING_FIELDS <- c("weak_negative_note", "researcher_summary")
MUST_READ_FOCUS_FIELDS <- c(
  "primary_focus", "supporting_signals", "primary_focus_only", "must_read_definition"
)

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
- must_read_scope: research_direction or focused
- must_read_focus: null for research_direction, otherwise an object with exactly primary_focus,
  supporting_signals, primary_focus_only, and must_read_definition
"

.is_nonempty_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(value))
}

.has_exact_fields <- function(value, fields) {
  is.list(value) && !is.null(names(value)) && !anyDuplicated(names(value)) &&
    setequal(names(value), fields)
}

.valid_question_purpose <- function(value) {
  if (!.is_nonempty_string(value) || grepl("[\r\n]", value)) return(FALSE)
  words <- strsplit(trimws(value), "[[:space:]]+")[[1]]
  length(words) <= 25L
}

validate_must_read_focus <- function(focus) {
  fail <- function(message) list(valid = FALSE, message = message)
  if (!.has_exact_fields(focus, MUST_READ_FOCUS_FIELDS)) {
    return(fail("Must-read focus must contain exactly the four required fields."))
  }
  if (!.is_nonempty_string(focus$primary_focus) ||
      !.is_nonempty_string(focus$must_read_definition)) {
    return(fail("Must-read focus and definition must be non-empty strings."))
  }
  if (!is.logical(focus$primary_focus_only) || length(focus$primary_focus_only) != 1L ||
      is.na(focus$primary_focus_only)) {
    return(fail("must_read_focus.primary_focus_only must be one boolean."))
  }
  signals <- focus$supporting_signals
  if (!is.list(signals) && !is.character(signals)) {
    return(fail("must_read_focus.supporting_signals must be an array."))
  }
  if (length(signals) && !all(vapply(as.list(signals), function(x) is.character(x) && length(x) == 1L && !is.na(x), logical(1)))) {
    return(fail("Must-read supporting signals must be strings."))
  }
  signals <- trimws(as.character(unlist(signals, use.names = FALSE)))
  if (any(!nzchar(signals)) || anyDuplicated(signals)) {
    return(fail("Must-read supporting signals must be unique non-empty strings."))
  }
  if (isTRUE(focus$primary_focus_only) && length(signals) != 0L) {
    return(fail("A primary-focus-only profile cannot contain supporting signals."))
  }
  if (!isTRUE(focus$primary_focus_only) && length(signals) == 0L) {
    return(fail("A focused profile needs supporting signals unless primary-focus-only is true."))
  }
  list(valid = TRUE, message = NULL)
}

normalize_research_profile <- function(profile) {
  if (!is.list(profile) || is.null(names(profile)) || anyDuplicated(names(profile))) return(profile)
  has_scope <- "must_read_scope" %in% names(profile)
  has_focus <- "must_read_focus" %in% names(profile)
  if (!has_scope && !has_focus && setequal(names(profile), LEGACY_PROFILE_FIELDS)) {
    profile$must_read_scope <- "research_direction"
    profile["must_read_focus"] <- list(NULL)
  }
  profile
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
    phase = "long_term",
    rss_sources = profile_interview_rss_sources(feeds),
    answers = list(), # legacy alias retained for callers/tests
    long_term_answers = list(),
    long_term_supplements = character(),
    long_term_summary = NULL,
    summary_revisions = character(),
    language = language,
    must_read_scope = NULL,
    scope_free_text = NULL,
    focused_answers = list(),
    focus_proposal = NULL
  )
}

profile_interview_question_count <- function(state) {
  length(state$long_term_answers %||% state$answers %||% list())
}

focused_interview_question_count <- function(state) length(state$focused_answers %||% list())

profile_interview_force_summary <- function(state) {
  profile_interview_question_count(state) >= PROFILE_INTERVIEW_HARD_LIMIT
}

profile_interview_add_answer <- function(state, inference, question, options, answer) {
  if (profile_interview_force_summary(state)) stop("The interview question limit has been reached.")
  record <- list(
    question_purpose = "Clarifies which papers belong in the general recommendation scope.",
    selection_mode = "single",
    current_inference = inference,
    inference = inference, question = question,
    options = as.character(options), answer = answer
  )
  state$long_term_answers[[length(state$long_term_answers) + 1L]] <- record
  state$answers <- state$long_term_answers
  state
}

profile_interview_add_structured_answer <- function(state, phase, step, answer) {
  record <- list(
    question_purpose = step$question_purpose,
    selection_mode = step$selection_mode,
    current_inference = step$current_inference,
    question = step$question,
    options = as.character(step$options),
    answer = answer
  )
  field <- if (identical(phase, "long_term")) "long_term_answers" else if (identical(phase, "focused")) "focused_answers" else stop("Unknown interview phase.")
  limit <- if (identical(phase, "long_term")) PROFILE_INTERVIEW_HARD_LIMIT else FOCUSED_INTERVIEW_HARD_LIMIT
  if (length(state[[field]]) >= limit) stop("The interview question limit has been reached.")
  state[[field]][[length(state[[field]]) + 1L]] <- record
  if (identical(phase, "long_term")) state$answers <- state$long_term_answers
  state
}

profile_interview_revise_previous_answer <- function(state) {
  answer_count <- profile_interview_question_count(state)
  if (answer_count == 0) return(list(state = state, step = NULL))

  answers <- state$long_term_answers %||% state$answers
  previous <- answers[[answer_count]]
  state$long_term_answers <- if (answer_count == 1L) list() else answers[seq_len(answer_count - 1L)]
  state$answers <- state$long_term_answers
  list(
    state = state,
    step = list(
      action = "ask",
      question_purpose = previous$question_purpose %||% "Clarifies the general recommendation scope.",
      selection_mode = previous$selection_mode %||% "single",
      current_inference = previous$current_inference %||% previous$inference,
      question = previous$question,
      options = as.character(previous$options)
    )
  )
}

profile_interview_revise_phase_answer <- function(state, phase) {
  field <- if (identical(phase, "long_term")) "long_term_answers" else "focused_answers"
  answers <- state[[field]] %||% list()
  if (!length(answers)) return(list(state = state, step = NULL))
  previous <- answers[[length(answers)]]
  state[[field]] <- if (length(answers) == 1L) list() else answers[-length(answers)]
  if (identical(phase, "long_term")) state$answers <- state$long_term_answers
  list(state = state, step = c(list(action = "ask"), previous[c("question_purpose", "selection_mode", "current_inference", "question", "options")]))
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

  opening_rule <- if (question_count == 0L && length(state$rss_sources %||% list()) > 0L) {
    "For the opening question, derive 2-4 tentative peer keywords from the enabled RSS sources as options. The user may combine or replace them."
  } else if (question_count == 0L) {
    "The opening question asks for one or more free-text keywords and MUST return an empty options list. Put 1-2 examples in the question text."
  } else {
    "From the second question onward, keep the inference, question, and options at one level as peers of the same granularity."
  }
  supplements <- if (length(state$long_term_supplements %||% character())) {
    paste0("Additional directions named by the user:\n", paste(state$long_term_supplements, collapse = "\n"), "\n\n")
  } else ""
  paste0(
    "You are conducting phase 1 of a one-question-at-a-time academic-paper filtering interview.\n\n",
    "Treat RSS metadata only as a tentative clue, never proof. Enabled RSS metadata:\n",
    jsonlite::toJSON(state$rss_sources %||% list(), auto_unbox = TRUE, pretty = TRUE), "\n\n",
    "The interview language is ", state$language %||% "English", ". Write every user-facing field in that language.\n\n",
    "Use this subject funnel: (1) the user's target-area keywords, (2) sub-directions/problem classes/aspects, (3) concrete topics/systems/phenomena/objects. Descend exactly one level only when the current level names concrete items and has no unresolved branch. Stop at level 3. Do not descend into methods, algorithms, model families, tools, theoretical guarantees, or datasets. Treat every selected keyword as active. If an answer is vague or meta, ask for concrete content at the same level. Select the question with greatest information gain first, then write its purpose.\n\n",
    opening_rule, "\n\n",
    "Each ask response includes question_purpose: one sentence of at most 25 words explaining how the answer improves general recommendation filtering. Never mention scores or numeric thresholds. Use multiple when options can all be true and single only for exclusive alternatives. Do not add Other. Avoid identity, affiliation, project names, collaborators, funding, confidential data, and unpublished results.\n\n",
    convergence_note, "\n", hard_limit_note, "\n\n",
    "Before summarizing, verify that the profile names the target research area, at least 2-3 concrete topics/systems/phenomena/problem areas, and at least two items that could appear in a title or abstract. Readiness overrides the count preference until the hard ceiling.\n\n",
    "Return ONLY valid JSON with exactly one of these shapes:\n",
    "{\"action\":\"ask\",\"question_purpose\":\"...\",\"selection_mode\":\"single|multiple\",\"current_inference\":\"...\",\"question\":\"...\",\"options\":[\"...\",\"...\"]}\n",
    "{\"action\":\"summarize\",\"summary\":\"...\"}\n\n",
    supplements, .profile_interview_context(state)
  )
}

validate_profile_interview_response <- function(response, force_summary = FALSE, allow_no_options = FALSE) {
  fail <- function(message) list(valid = FALSE, message = message, data = NULL)
  if (!is.list(response) || !.is_nonempty_string(response$action)) {
    return(fail("Response must contain a non-empty action."))
  }

  action <- response$action
  if (force_summary && !identical(action, "summarize")) {
    return(fail("The CLI requires a summarize response."))
  }

  if (identical(action, "ask")) {
    required <- c("action", "question_purpose", "selection_mode", "current_inference", "question", "options")
    if (!.has_exact_fields(response, required)) return(fail("Ask response has unexpected or missing fields."))
    if (!.valid_question_purpose(response$question_purpose) || !response$selection_mode %in% c("single", "multiple") ||
        !.is_nonempty_string(response$current_inference) || !.is_nonempty_string(response$question)) {
      return(fail("Ask response must contain a purpose, selection mode, inference, and one question."))
    }
    options <- response$options
    min_options <- if (isTRUE(allow_no_options)) 0L else 2L
    if ((!is.list(options) && !is.character(options)) || length(options) < min_options || length(options) > 4L) {
      return(fail("Ask response options are out of range."))
    }
    response$options <- trimws(as.character(unlist(options, use.names = FALSE)))
    if (any(!nzchar(response$options)) || anyDuplicated(response$options)) return(fail("Options must be unique non-empty strings."))
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

resolve_profile_interview_answer <- function(input, options, selection_mode = "single") {
  value <- trimws(input %||% "")
  command <- tolower(value)
  if (identical(command, "/cancel")) return(list(status = "cancel", answer = NULL))
  if (identical(command, "/finish")) return(list(status = "finish", answer = NULL))
  if (!nzchar(value)) return(list(status = "invalid", answer = NULL))
  if (!length(options)) return(list(status = "answer", answer = list(selected_options = list(), free_text = value)))
  normalized <- gsub("(?i)(?<=\\d)\\s*(?:and|和|と|、|，|\\+|&)\\s*(?=\\d)", ",", value, perl = TRUE)
  normalized <- gsub("(?<=\\d)\\s+(?=\\d)", ",", normalized, perl = TRUE)
  match <- regexpr("^[0-9]+(?:\\s*,\\s*[0-9]+)*", normalized, perl = TRUE)
  if (match[[1]] != 1L) return(list(status = "answer", answer = list(selected_options = list(), free_text = value)))
  prefix <- regmatches(normalized, match)
  indices <- as.integer(strsplit(gsub("[[:space:]]", "", prefix), ",", fixed = TRUE)[[1]])
  if (any(is.na(indices)) || any(indices < 1L) || any(indices > length(options)) || anyDuplicated(indices)) {
    return(list(status = "invalid", answer = NULL, reason = "bad_number"))
  }
  if (identical(selection_mode, "single") && length(indices) != 1L) {
    return(list(status = "invalid", answer = NULL, reason = "single_multiple"))
  }
  remainder <- substring(normalized, attr(match, "match.length") + 1L)
  remainder <- trimws(sub("^[,，+;；:：-]+", "", trimws(remainder), perl = TRUE))
  list(status = "answer", answer = list(selected_options = as.list(options[indices]), free_text = remainder))
}

profile_advance_after_summary <- function(state) {
  state$phase <- if (profile_interview_question_count(state) >= PROFILE_INTERVIEW_HARD_LIMIT) "scope" else "extend"
  state
}

profile_apply_extension <- function(state, input) {
  value <- trimws(input %||% "")
  if (!nzchar(value)) {
    state$phase <- "scope"
  } else {
    state$long_term_supplements <- c(state$long_term_supplements, value)
    state$phase <- "long_term"
  }
  state
}

build_scope_classifier_prompt <- function(state, answer) {
  paste0(
    "The long-term profile already determines general relevance. Classify whether must_read means ",
    "strong matches to the overall direction (research_direction) or only direct matches to a narrower current question, object, method, or goal (focused).\n\n",
    "Long-term summary:\n", state$long_term_summary, "\n\nUser answer:\n", answer,
    "\n\nReturn ONLY {\"scope\":\"research_direction|focused|unclear\",\"interpretation\":\"...\"}. Write interpretation in ", state$language, "."
  )
}

validate_scope_classifier_response <- function(response) {
  fail <- function(message) list(valid = FALSE, message = message, data = NULL)
  if (!.has_exact_fields(response, c("scope", "interpretation"))) return(fail("Scope response fields are invalid."))
  if (!response$scope %in% c("research_direction", "focused", "unclear") || !.is_nonempty_string(response$interpretation)) {
    return(fail("Scope or interpretation is invalid."))
  }
  list(valid = TRUE, message = NULL, data = response[c("scope", "interpretation")])
}

build_focused_interview_prompt <- function(state, force_proposal = FALSE, saved_profile = NULL) {
  count <- focused_interview_question_count(state)
  convergence <- if (count < 3L) "Narrow the primary focus before proposing." else if (count < FOCUSED_INTERVIEW_SOFT_LIMIT) "Ask only about ambiguity that changes direct-match decisions; otherwise propose." else "Strongly prefer proposing the focus now."
  limit <- if (force_proposal || count >= FOCUSED_INTERVIEW_HARD_LIMIT) "You MUST return propose_focus now." else "The hard ceiling is 8 answered focused questions."
  evidence <- c(
    if (.is_nonempty_string(state$scope_free_text)) paste0("Free-text scope evidence: ", state$scope_free_text) else NULL,
    if (!is.null(state$focus_proposal)) paste0("Existing focus: ", jsonlite::toJSON(state$focus_proposal, auto_unbox = TRUE)) else NULL
  )
  long_context <- if (!is.null(saved_profile)) {
    paste0(saved_profile$researcher_summary %||% "", "\n", jsonlite::toJSON(saved_profile[LEGACY_PROFILE_FIELDS], auto_unbox = TRUE))
  } else state$long_term_summary
  paste0(
    "You are conducting the focused must-read phase of an academic-paper filtering interview. General relevance remains governed by the long-term profile. Define one current focus for direct-match decisions.\n\n",
    "Interview language: ", state$language, ". Use concrete hypotheses grounded in the profile. Progress through primary focus, useful supporting signals or explicit primary-focus-only mode, then a title-and-abstract-testable definition.\n\n",
    "Long-term profile:\n", long_context, "\n\n", paste(evidence, collapse = "\n"), "\n\n",
    "Each ask includes a question_purpose of one sentence and at most 25 words explaining how it improves must-read filtering, without scores or thresholds. Use multiple for compatible signals and single only for exclusive choices. Avoid identity or confidential details.\n\n",
    convergence, " ", limit, "\n\nFocused history:\n",
    jsonlite::toJSON(state$focused_answers %||% list(), auto_unbox = TRUE, pretty = TRUE), "\n\n",
    "Return ONLY one exact JSON shape:\n",
    "{\"action\":\"ask\",\"question_purpose\":\"...\",\"selection_mode\":\"single|multiple\",\"current_inference\":\"...\",\"question\":\"...\",\"options\":[\"...\",\"...\"]}\n",
    "{\"action\":\"propose_focus\",\"primary_focus\":\"...\",\"supporting_signals\":[\"...\"],\"primary_focus_only\":false,\"must_read_definition\":\"...\"}"
  )
}

validate_focused_interview_response <- function(response, force_proposal = FALSE) {
  fail <- function(message) list(valid = FALSE, message = message, data = NULL)
  if (!is.list(response) || !.is_nonempty_string(response$action)) return(fail("Response requires an action."))
  if (force_proposal && !identical(response$action, "propose_focus")) return(fail("A focus proposal is required now."))
  if (identical(response$action, "ask")) return(validate_profile_interview_response(response))
  if (!identical(response$action, "propose_focus")) return(fail("Action must be ask or propose_focus."))
  proposal <- response[setdiff(names(response), "action")]
  checked <- validate_must_read_focus(proposal)
  if (!checked$valid || !.has_exact_fields(response, c("action", MUST_READ_FOCUS_FIELDS))) return(fail(checked$message %||% "Focus proposal fields are invalid."))
  proposal$supporting_signals <- trimws(as.character(unlist(proposal$supporting_signals, use.names = FALSE)))
  list(valid = TRUE, message = NULL, data = c(list(action = "propose_focus"), proposal))
}

normalize_profile_interview_llm_config <- function(config) {
  if (!is.list(config) || !.is_nonempty_string(config$model)) stop("LLM configuration is missing a model.")
  normalized <- config
  if (identical(normalized$backend, "claude_batch")) normalized$backend <- "claude"
  if (!normalized$backend %in% c("ollama", "claude", "deepseek", "openai_compatible")) stop("Unsupported interview backend: ", normalized$backend %||% "(missing)")
  tokens <- suppressWarnings(as.integer(normalized$max_tokens %||% PROFILE_INTERVIEW_MAX_TOKENS))
  if (is.na(tokens)) tokens <- PROFILE_INTERVIEW_MAX_TOKENS
  normalized$max_tokens <- min(max(tokens, 4096L), PROFILE_INTERVIEW_MAX_TOKENS)
  normalized
}

build_profile_draft_prompt <- function(state, summary) {
  paste0(
    "Create a structured academic research profile from the confirmed interview summary and the interview evidence below. ",
    "Use English scientific terms for all topics, aliases, keywords, methods, domains, regions, authors, and venues even if the interview was in another language. ",
    "Generalize identifying or confidential details when that preserves filtering intent. Do not invent unsupported preferences. Translate the profile and focus scientific fields into English. Return ONLY valid JSON. No markdown or explanation.\n\n",
    "Confirmed research-profile summary:\n", summary, "\n\n",
    "Confirmed must-read scope: ", state$must_read_scope, "\n",
    "Confirmed focus proposal: ", if (is.null(state$focus_proposal)) "null" else jsonlite::toJSON(state$focus_proposal[setdiff(names(state$focus_proposal), "action")], auto_unbox = TRUE), "\n\n",
    .profile_interview_context(state), "\n\n",
    PROFILE_SCHEMA_SPEC
  )
}

validate_profile_draft <- function(profile, weight_tolerance = 0.01) {
  fail <- function(message) list(valid = FALSE, message = message)
  profile <- normalize_research_profile(profile)
  if (!.has_exact_fields(profile, PROFILE_FIELDS)) {
    return(fail("Profile must contain exactly the required 17 fields (or all 15 legacy fields)."))
  }

  for (field in PROFILE_STRING_FIELDS) {
    if (!.is_nonempty_string(profile[[field]])) {
      return(fail(sprintf("Profile field '%s' must be a non-empty string.", field)))
    }
  }

  list_fields <- setdiff(LEGACY_PROFILE_FIELDS, PROFILE_STRING_FIELDS)
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

  if (!.is_nonempty_string(profile$must_read_scope) || !profile$must_read_scope %in% c("research_direction", "focused")) {
    return(fail("must_read_scope must be research_direction or focused."))
  }
  if (identical(profile$must_read_scope, "research_direction") && !is.null(profile$must_read_focus)) {
    return(fail("Research-direction scope requires a null must_read_focus."))
  }
  if (identical(profile$must_read_scope, "focused")) {
    focus_check <- validate_must_read_focus(profile$must_read_focus)
    if (!focus_check$valid) return(focus_check)
  }

  list(valid = TRUE, message = NULL, profile = profile)
}
