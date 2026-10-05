# ==================================================
# llm_provider_layer.R — Built-in LLM provider catalog and config helpers
# ==================================================

LLM_PROVIDER_CATALOG <- list(
  anthropic = list(
    label = "Anthropic",
    backend = "claude",
    base_url = "https://api.anthropic.com",
    models = c("claude-fable-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"),
    requires_api_key = TRUE
  ),
  openai = list(
    label = "OpenAI",
    backend = "openai_compatible",
    base_url = "https://api.openai.com/v1",
    models = c("gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"),
    requires_api_key = TRUE
  ),
  deepseek = list(
    label = "DeepSeek",
    backend = "openai_compatible",
    base_url = "https://api.deepseek.com",
    models = c("deepseek-v4-pro", "deepseek-v4-flash"),
    requires_api_key = TRUE
  ),
  ollama = list(
    label = "Ollama (local)",
    backend = "ollama",
    base_url = "",
    models = character(),
    requires_api_key = FALSE,
    model_input_only = TRUE
  ),
  custom_openai_compatible = list(
    label = "Custom OpenAI-compatible",
    backend = "openai_compatible",
    base_url = "",
    models = character(),
    requires_api_key = TRUE
  )
)

llm_provider_ids <- function() names(LLM_PROVIDER_CATALOG)

llm_provider <- function(provider_id) {
  provider <- LLM_PROVIDER_CATALOG[[provider_id]]
  if (is.null(provider)) stop("Unknown LLM provider: ", provider_id)
  provider
}

llm_provider_labels <- function() {
  vapply(LLM_PROVIDER_CATALOG, `[[`, character(1), "label")
}

normalize_backend <- function(backend) if (identical(backend, "claude_batch")) "claude" else backend

llm_provider_from_config <- function(config) {
  if (is.null(config)) return(NULL)
  explicit <- config$provider %||% ""
  if (explicit %in% llm_provider_ids()) return(explicit)

  backend <- normalize_backend(config$backend %||% "")
  if (identical(backend, "ollama")) return("ollama")
  if (identical(backend, "claude")) return("anthropic")
  if (!identical(backend, "openai_compatible")) return(NULL)

  base_url <- sub("/+$", "", config$base_url %||% "")
  if (identical(base_url, "https://api.openai.com/v1")) return("openai")
  if (identical(base_url, "https://api.deepseek.com")) return("deepseek")
  "custom_openai_compatible"
}

new_llm_provider_config <- function(provider_id, model, api_key = "", max_tokens = 1024L,
                                    custom_base_url = "", ollama_url = OLLAMA_DEFAULT_URL,
                                    use_batch = FALSE) {
  provider <- llm_provider(provider_id)
  base_url <- if (identical(provider_id, "custom_openai_compatible")) custom_base_url else provider$base_url
  list(
    provider = provider_id,
    backend = if (identical(provider_id, "anthropic") && isTRUE(use_batch)) "claude_batch" else provider$backend,
    model = model,
    api_key = api_key,
    base_url = base_url,
    url = if (identical(provider_id, "ollama")) ollama_url else "",
    use_batch = isTRUE(use_batch),
    max_tokens = as.integer(max_tokens)
  )
}

llm_config_is_configured <- function(config) {
  if (is.null(config) || !nzchar(config$backend %||% "") || !nzchar(config$model %||% "")) return(FALSE)
  provider_id <- llm_provider_from_config(config)
  if (is.null(provider_id)) return(FALSE)
  provider <- llm_provider(provider_id)
  if (isTRUE(provider$requires_api_key) && !nzchar(config$api_key %||% "")) return(FALSE)
  if (identical(provider_id, "custom_openai_compatible") && !nzchar(config$base_url %||% "")) return(FALSE)
  TRUE
}
