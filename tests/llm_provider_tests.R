source("R/llm_layer.R")
source("R/llm_provider_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_false <- function(value, message) expect_true(!isTRUE(value), message)

expect_true(identical(
  llm_provider_ids(),
  c("anthropic", "openai", "deepseek", "ollama", "custom_openai_compatible")
), "The provider catalog should contain the approved providers in display order.")
expect_true(identical(llm_provider_from_config(list(backend = "claude", model = "x")), "anthropic"), "Legacy Claude config should infer Anthropic.")
expect_true(identical(llm_provider_from_config(list(backend = "openai_compatible", base_url = "https://api.deepseek.com/")), "deepseek"), "Known DeepSeek URLs should infer DeepSeek.")
expect_true(identical(llm_provider_from_config(list(backend = "openai_compatible", base_url = "https://example.org/v1")), "custom_openai_compatible"), "Unknown compatible URLs should infer Custom.")
expect_true(identical(llm_provider("openai")$models, c("gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna")), "OpenAI should offer the current GPT-5.6 family.")
expect_true(identical(llm_provider("deepseek")$models, c("deepseek-v4-pro", "deepseek-v4-flash")), "DeepSeek should offer only current V4 models.")
expect_true(isTRUE(llm_provider("ollama")$model_input_only), "Ollama should request a model name directly.")

openai_cfg <- new_llm_provider_config("openai", "gpt-4o", api_key = "key")
expect_true(identical(openai_cfg$backend, "openai_compatible"), "OpenAI should use the compatible backend.")
expect_true(identical(openai_cfg$base_url, "https://api.openai.com/v1"), "OpenAI should have a fixed Base URL.")
expect_true(llm_config_is_configured(openai_cfg), "A complete cloud config should be configured.")
expect_true(identical(new_llm_provider_config("anthropic", "claude-haiku-4-5", api_key = "key", use_batch = TRUE)$backend, "claude_batch"), "Anthropic Batch API should remain available.")
expect_false(llm_config_is_configured(new_llm_provider_config("deepseek", "deepseek-chat")), "Cloud providers require an API key.")
expect_true(llm_config_is_configured(new_llm_provider_config("ollama", "llama3.2")), "Ollama does not require an API key.")
expect_false(llm_config_is_configured(new_llm_provider_config("custom_openai_compatible", "model", api_key = "key")), "Custom compatible providers require a Base URL.")

smart_quote_json <- '{"question":"围绕“地震/海啸”，你更关注什么？","options":[]}'
expect_true(identical(parse_llm_json_text(smart_quote_json, simplify = FALSE)$question,
                      "围绕“地震/海啸”，你更关注什么？"),
            "Valid JSON with typographic quotes should parse without losing them.")
bare_quote_json <- '{"question":"围绕"地震/海啸"，你更关注什么？","options":[]}'
expect_true(identical(parse_llm_json_text(bare_quote_json, simplify = FALSE, label = "Test")$question,
                      "围绕\"地震/海啸\"，你更关注什么？"),
            "Unescaped quotes inside a string value should be repaired.")
healthy_json <- '{"action":"summarize","summary":"ok"}'
expect_true(identical(escape_inner_json_quotes(healthy_json), healthy_json),
            "The inner-quote repair should be a no-op for well-formed JSON.")
expect_true(identical(parse_llm_json_text(healthy_json, simplify = FALSE)$summary, "ok"),
            "Well-formed JSON should parse unchanged.")

cat("llm_provider_tests: PASS\n")
