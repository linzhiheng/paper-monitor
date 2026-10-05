# ==================================================
# initial_setup_layer.R — First-run configuration status
# ==================================================

initial_setup_status <- function(
    llm_cfg = read_json_config(file.path(CONFIG_DIR, "llm_config.json"), default = NULL),
    feeds = load_feeds_config(),
    profile = read_json_config(file.path(CONFIG_DIR, "research_profile.json"), default = NULL),
    output_cfg = read_json_config(file.path(CONFIG_DIR, "output_config.json"), default = NULL)
) {

  profile_check <- if (is.null(profile)) list(valid = FALSE, message = "not created") else validate_profile_draft(profile)
  output_folder <- output_cfg$output_folder %||% ""

  list(
    list(
      id = "llm", label = "LLM provider", complete = llm_config_is_configured(llm_cfg),
      detail = if (llm_config_is_configured(llm_cfg)) paste(llm_provider(llm_provider_from_config(llm_cfg))$label, "—", llm_cfg$model) else "not configured"
    ),
    list(
      id = "feeds", label = "RSS feeds", complete = nrow(feeds) > 0 && any(feeds$enabled),
      detail = if (nrow(feeds) > 0 && any(feeds$enabled)) sprintf("%d enabled", sum(feeds$enabled)) else "add and enable at least one"
    ),
    list(
      id = "profile", label = "Research profile", complete = isTRUE(profile_check$valid),
      detail = if (isTRUE(profile_check$valid)) "saved and valid" else profile_check$message %||% "not created"
    ),
    list(
      id = "output", label = "Output folder", complete = nzchar(output_folder) && dir.exists(output_folder),
      detail = if (nzchar(output_folder) && dir.exists(output_folder)) output_folder else "set an existing folder"
    )
  )
}

initial_setup_complete <- function(status = initial_setup_status()) {
  all(vapply(status, `[[`, logical(1), "complete"))
}

initial_setup_next_incomplete <- function(status = initial_setup_status()) {
  pending <- which(!vapply(status, `[[`, logical(1), "complete"))
  if (length(pending) == 0L) NA_integer_ else pending[[1]]
}

initial_setup_labels <- function(status = initial_setup_status()) {
  vapply(status, function(step) {
    sprintf("[%s] %s — %s", if (isTRUE(step$complete)) "x" else " ", step$label, step$detail)
  }, character(1))
}
