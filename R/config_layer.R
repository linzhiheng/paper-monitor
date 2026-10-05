# ==================================================
# config_layer.R — Generic JSON Config Read/Write Helpers
# ==================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

CONFIG_DIR <- "config"
DATA_DIR <- "data"

recommendations_file_path <- function() {
  if (!dir.exists(DATA_DIR)) dir.create(DATA_DIR, recursive = TRUE, showWarnings = FALSE)
  file.path(DATA_DIR, "recommendations.csv")
}

read_json_config <- function(path, default = list()) {
  if (!file.exists(path)) return(default)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

write_json_config <- function(config, path) {
  jsonlite::write_json(config, path, auto_unbox = TRUE, pretty = TRUE)
  invisible(config)
}
