expect_true <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

read_text <- function(path) {
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

launcher_root <- Sys.getenv("PAPER_MONITOR_LAUNCHER_ROOT", unset = "release")
launcher_path <- function(name) file.path(launcher_root, name)

description <- readLines("DESCRIPTION", warn = FALSE, encoding = "UTF-8")
version_line <- description[startsWith(description, "Version:")]
version <- trimws(sub("^Version:", "", version_line))
expect_true(identical(version, "0.2.0"), "DESCRIPTION should declare version 0.2.0.")

mac_launcher_path <- launcher_path("paper-monitor-macos-arm64.sh")
mac_launcher <- read_text(mac_launcher_path)
windows_cmd <- read_text(launcher_path("paper-monitor-windows-amd64.cmd"))
windows_ps1 <- read_text(launcher_path("paper-monitor-windows-amd64.ps1"))

expect_true(
  grepl("{menu|run|uninstall}", mac_launcher, fixed = TRUE),
  "The macOS launcher usage should expose menu, run, and uninstall."
)
expect_true(
  grepl('[[ "$mode" == "menu" || "$mode" == "run" || "$mode" == "uninstall" ]]', mac_launcher, fixed = TRUE),
  "The macOS launcher should accept exactly menu, run, and uninstall."
)
expect_true(
  grepl('if [[ "$mode" == "menu" ]]', mac_launcher, fixed = TRUE),
  "The macOS menu command should select the interactive entry point."
)
expect_true(
  grepl("{menu^|run^|uninstall}", windows_cmd, fixed = TRUE),
  "The Windows command wrapper usage should expose menu, run, and uninstall."
)
expect_true(
  grepl('[ValidateSet("menu", "run", "uninstall")]', windows_ps1, fixed = TRUE),
  "The Windows launcher should accept exactly menu, run, and uninstall."
)
expect_true(
  grepl('if ($Mode -eq "menu")', windows_ps1, fixed = TRUE),
  "The Windows menu command should select the interactive entry point."
)

for (launcher in c(mac_launcher, windows_ps1)) {
  expect_true(
    grepl("paper-monitor:v0.2.0", launcher, fixed = TRUE),
    "Each platform launcher should use the v0.2.0 image tag."
  )
  expect_true(
    grepl("paper-monitor-v0.2.0-linux-", launcher, fixed = TRUE),
    "Each platform launcher should load a v0.2.0 image archive."
  )
}

setup_result <- suppressWarnings(system2(
  "bash",
  c(mac_launcher_path, "setup"),
  stdout = TRUE,
  stderr = TRUE
))
expect_true(
  identical(attr(setup_result, "status"), 64L),
  "The removed setup command should be rejected with usage status 64."
)
expect_true(
  any(grepl("{menu|run|uninstall}", setup_result, fixed = TRUE)),
  "Rejecting setup should show the new launcher usage."
)

cat("launcher_contract_tests: PASS\n")
