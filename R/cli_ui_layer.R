# ==================================================
# cli_ui_layer.R — Shared terminal page rendering and navigation parsing
# ==================================================

CLI_RULE_WIDTH <- 72L

cli_rule <- function(width = CLI_RULE_WIDTH) strrep("─", width)

cli_title_rule <- function(title, width = CLI_RULE_WIDTH) {
  prefix <- paste0("─ ", title, " ")
  paste0(prefix, strrep("─", max(1L, width - nchar(prefix, type = "width"))))
}

cli_command_labels <- function(commands) {
  if (length(commands) == 0) return(character())
  if (is.null(names(commands)) || any(!nzchar(names(commands)))) {
    stop("CLI commands must be a named character vector.")
  }
  sprintf("[%s] %s", names(commands), unname(commands))
}

cli_page_lines <- function(title, items = character(), commands = character(), info = character()) {
  items <- as.character(items)
  info <- as.character(info)
  selection <- if (length(items) > 0) sprintf("[1-%d] Select Number", length(items)) else character()
  footer <- paste(c(selection, cli_command_labels(commands)), collapse = " ")
  c(
    paste0("\n", cli_title_rule(title)),
    info,
    if (length(items) > 0) sprintf("%d. %s", seq_along(items), items) else character(),
    cli_rule(),
    footer
  )
}

cli_parse_navigation <- function(input, item_count = 0L, commands = character()) {
  value <- tolower(trimws(input %||% ""))
  number <- suppressWarnings(as.integer(value))
  if (!is.na(number) && number >= 1L && number <= item_count) {
    return(list(kind = "select", value = number))
  }
  if (value %in% names(commands)) return(list(kind = "command", value = value))
  list(kind = "invalid", value = value)
}

prompt_cli_page <- function(title, items = character(), commands = character(), info = character()) {
  repeat {
    cat(paste(cli_page_lines(title, items, commands, info), collapse = "\n"), "\n")
    cat("Command: ")
    parsed <- cli_parse_navigation(read_stdin_line(), length(items), commands)
    if (!identical(parsed$kind, "invalid")) return(parsed)
    cat("Invalid command.\n")
  }
}
