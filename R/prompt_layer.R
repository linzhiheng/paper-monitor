# ==================================================
# prompt_layer.R — Prompt Building Layer
# ==================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

# --------------------------------------------------
# A: Loading and rendering are kept separate
# --------------------------------------------------

load_research_profile <- function(json_file) {
  profile <- normalize_research_profile(fromJSON(json_file, simplifyVector = FALSE))
  checked <- validate_profile_draft(profile)
  if (!isTRUE(checked$valid)) stop("Invalid research profile: ", checked$message)
  checked$profile
}

# --------------------------------------------------
# B: Field renderers
#
# Each field name maps to a renderer function (value, model_size) -> string.
# Adding a plain-list field only requires adding its name to
# .default_prompt_sections, or to the `sections` argument passed at call
# time — no rendering logic needs to change. Only fields with non-trivial
# structure (core_interests, topic_aliases) need a dedicated renderer
# registered here.
# --------------------------------------------------

# Display labels for each field (small differs from medium/large, handled separately)
# Uses list(), not c(): a list returns NULL for an unmatched [[field_name]]
# lookup, while an atomic vector errors with "subscript out of bounds" -
# unsafe once "custom" sections can name arbitrary fields not listed here.
.field_labels <- list(
  researcher_summary      = "Researcher Summary",
  core_interests          = "Core Interests",
  secondary_interests     = "Secondary Interests",
  emerging_interests      = "Emerging Interests",
  preferred_methods       = "Preferred Methods",
  preferred_domains       = "Preferred Domains",
  frequent_keywords       = "Keywords",
  regional_interests      = "Regional Interests",
  positive_signals        = "Positive Signals",
  frequent_authors        = "Frequent Authors",
  frequent_venues         = "Frequent Venues",
  topic_aliases           = "Topic Aliases",
  weak_negative_interests = "Generally Lower Priority Fields",
  weak_negative_keywords  = "Generally Lower Priority Keywords",
  weak_negative_note      = "Important Note"
)

# Renderers for fields with special structure; all other fields fall back to .render_default()
.field_renderers <- list(

  researcher_summary = function(value, model_size) {
    if (model_size == "small") return(value)
    paste0("Researcher Summary:\n", value)
  },

  core_interests = function(value, model_size) {
    topics  <- vapply(value, function(x) x$topic,  character(1))
    weights <- vapply(value, function(x) x$weight, numeric(1))
    if (model_size == "small") {
      return(paste0("Core Topics: ", paste(topics, collapse = ", ")))
    }
    weight_fmt <- if (model_size == "large") "weight %.2f" else "%.2f"
    lines <- sprintf(paste0("- %s (", weight_fmt, ")"), topics, weights)
    paste0("Core Interests:\n", paste(lines, collapse = "\n"))
  },

  topic_aliases = function(value, model_size) {
    alias_lines <- vapply(names(value), function(topic) {
      paste0(topic, ": ", paste(unlist(value[[topic]]), collapse = ", "))
    }, character(1))
    paste0("Topic Aliases:\n", paste(alias_lines, collapse = "\n"))
  },

  weak_negative_note = function(value, model_size) {
    paste0("Important Note:\n", value)
  }
)

# Some fields use different labels under small size (also list(), see reasoning above)
.small_labels <- list(
  frequent_keywords      = "Important Keywords",
  weak_negative_keywords = "Generally Lower Priority Topics"
)

.render_default <- function(field_name, value, model_size) {
  text <- paste(unlist(value), collapse = ", ")
  if (model_size == "small") {
    label <- .small_labels[[field_name]] %||% .field_labels[[field_name]] %||% field_name
    return(paste0(label, ": ", text))
  }
  label <- .field_labels[[field_name]] %||% field_name
  paste0(label, ":\n", text)
}

.render_field <- function(field_name, value, model_size) {
  if (is.null(value)) return(NULL)
  renderer <- .field_renderers[[field_name]]
  if (!is.null(renderer)) renderer(value, model_size)
  else .render_default(field_name, value, model_size)
}

# --------------------------------------------------
# Main function: accepts either a profile list or a JSON file path
# --------------------------------------------------

# Default field list per model_size — the formal interface contract of
# build_research_profile_prompt(). Profile data sources no longer need
# to define their own prompt_sections.
.default_prompt_sections <- list(
  small  = c("researcher_summary", "core_interests", "frequent_keywords",
             "regional_interests", "weak_negative_keywords"),
  medium = c("researcher_summary", "core_interests", "secondary_interests",
             "preferred_methods", "preferred_domains", "frequent_keywords",
             "regional_interests", "positive_signals",
             "weak_negative_interests", "weak_negative_keywords"),
  large  = c("researcher_summary", "core_interests", "secondary_interests",
             "emerging_interests", "preferred_methods", "preferred_domains",
             "frequent_keywords", "regional_interests", "positive_signals",
             "frequent_authors", "frequent_venues", "topic_aliases",
             "weak_negative_interests", "weak_negative_keywords",
             "weak_negative_note")
)

# Renders the research-profile section of the prompt for a given model_size.
# model_size = "custom" requires an explicit `sections` field-name vector.
# If some requested fields are absent from the profile, renders the rest and
# warns; if ALL requested fields are absent, stops with an error.
build_research_profile_prompt <- function(profile_or_file,
                                          model_size = c("small", "medium", "large", "custom"),
                                          sections = NULL) {
  model_size <- match.arg(model_size)

  if (model_size == "custom") {
    if (is.null(sections)) {
      stop("model_size = \"custom\" requires a non-NULL 'sections' argument ",
           "(a character vector of field names to render).")
    }
  } else {
    sections <- .default_prompt_sections[[model_size]]
  }

  profile <- if (is.character(profile_or_file)) {
    load_research_profile(profile_or_file)
  } else {
    normalized <- normalize_research_profile(profile_or_file)
    checked <- validate_profile_draft(normalized)
    if (!isTRUE(checked$valid)) stop("Invalid research profile: ", checked$message)
    checked$profile
  }

  parts <- c("Research Profile")
  missing_fields <- character(0)
  for (field_name in sections) {
    rendered <- .render_field(field_name, profile[[field_name]], model_size)
    if (is.null(rendered)) {
      missing_fields <- c(missing_fields, field_name)
    } else {
      parts <- c(parts, rendered)
    }
  }

  if (length(missing_fields) == length(sections)) {
    stop("None of the requested fields (", paste(sections, collapse = ", "),
         ") were found in the profile for model_size = \"", model_size, "\".")
  }
  if (length(missing_fields) > 0) {
    warning("Missing fields for model_size = \"", model_size, "\": ",
            paste(missing_fields, collapse = ", "),
            ". Prompt generated using only the available fields.")
  }

  paste(parts, collapse = "\n\n")
}

# --------------------------------------------------
# Paper evaluation prompt (backward compatible: accepts a file path or a profile list)
# --------------------------------------------------

# Builds the full paper-evaluation prompt; forwards model_size/sections to
# build_research_profile_prompt().
build_paper_prompt <- function(profile_or_file, model_size, title, abstract, sections = NULL) {

  profile <- if (is.character(profile_or_file)) load_research_profile(profile_or_file) else {
    checked <- validate_profile_draft(normalize_research_profile(profile_or_file))
    if (!isTRUE(checked$valid)) stop("Invalid research profile: ", checked$message)
    checked$profile
  }

  profile_prompt <- build_research_profile_prompt(profile,
                                                    model_size = model_size,
                                                    sections = sections)

  focused <- identical(profile$must_read_scope, "focused")
  focus_prompt <- if (focused) paste0(
    "\n\nMust-read focus (evaluate independently from general relevance):\n",
    "Primary focus: ", profile$must_read_focus$primary_focus, "\n",
    "Supporting signals: ", paste(unlist(profile$must_read_focus$supporting_signals), collapse = "; "), "\n",
    "Primary-focus-only: ", profile$must_read_focus$primary_focus_only, "\n",
    "Definition: ", profile$must_read_focus$must_read_definition, "\n",
    "Return must_read_focus_match as one boolean and must_read_focus_reason as a non-empty explanation. A direct match is necessary, not sufficient, for must_read. Do not raise the general relevance score because of focus matching. If the abstract is absent or too weak to establish specificity, return false and say evidence is insufficient."
  ) else ""
  response_fields <- if (focused) {
    ' "tldr": "",\n "must_read_focus_match": false,\n "must_read_focus_reason": ""\n'
  } else ' "tldr": ""\n'

  paste0(
    profile_prompt,
    focus_prompt,

    "\n\n",
    "Task: Evaluate an academic paper for relevance.\n\n",

    "Title:\n", title,
    "\n\n",

    "Abstract:\n", abstract,
    "\n\n",

    "Scoring Rules:\n",
    "- Score range: 0-100\n",
    "- Prioritize core interests above all other criteria\n",
    "- Consider research topic, scientific objective, methods, study region, and application domain\n",
    "- Multiple matching signals should increase confidence and score\n",
    "- Weak-negative topics should only reduce scores when they are not clearly connected to earthquakes, tsunamis, subduction zones, monitoring, hazard assessment, marine geophysics, electromagnetic observations, or magnetotellurics\n",
    "- Generic geoscience papers without clear relevance should receive moderate or low scores\n\n",

    "Score bands:\n",
    "- 90-100: must_read (direct match to core interests, methods, or study regions)\n",
    "- 75-89: recommended (strong relevance to research interests)\n",
    "- 60-74: potentially_relevant (partial relevance, useful background, or related methods)\n",
    "- 40-59: peripheral (general geoscience with limited relevance)\n",
    "- 0-39: low_relevance (mostly unrelated)\n\n",

    "High-scoring signals:\n",
    "- Tsunami forecasting, tsunami hazards, tsunami source studies\n",
    "- Earthquake source processes, rupture, faulting, seismic monitoring\n",
    "- Magnetotellurics, conductivity structure, resistivity imaging\n",
    "- Electromagnetic observations and marine EM studies\n",
    "- Ocean-bottom observations (OBS)\n",
    "- Subduction zones, megathrusts, slow slip events (SSE)\n",
    "- Hazard assessment, disaster mitigation, early warning systems\n",
    "- Geophysical inversion, source inversion, data assimilation\n",
    "- Nankai Trough, Japan Trench, Ryukyu Trench, Kuril Trench, Sagami Trough\n\n",

    "Matched topics rules:\n",
    "- Extract 1-5 specific technical topics\n",
    "- Prefer scientific concepts, methods, or target phenomena\n",
    "- Avoid generic terms such as 'geophysics', 'earth science', or 'monitoring'\n",
    "- Examples: tsunami forecasting, magnetotelluric inversion, slow slip event, ocean-bottom seismometer, conductivity structure\n\n",

    "Reason rules:\n",
    "- Explain briefly why the paper matches or does not match the research profile\n",
    "- Mention specific matched topics when possible\n",
    "- Keep reason concise (3-5 sentences)\n\n",

    "TL;DR rules:\n",
    "- Summarize the abstract itself (not the relevance judgment) in 1-2 sentences\n",
    "- Focus on what the paper actually did and found\n\n",

    "Return ONLY valid JSON. No explanation. No markdown.\n\n",

    "{\n",
    " \"score\": 0,\n",
    " \"category\": \"\",\n",
    " \"matched_topics\": [],\n",
    " \"reason\": \"\",\n",
    response_fields,
    "}\n"
  )
}
