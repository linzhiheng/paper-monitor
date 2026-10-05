# Paper Monitor v0.1.0 offline package

__PACKAGE_DESCRIPTION__

This package runs one paper-monitoring cycle at a time. It does not contain
your API key, RSS feeds, research profile, recommendation history, or output.

For step-by-step installation and usage instructions, see
`INSTALL_AND_USAGE.md` in this package.

## Before you start

- macOS: Apple Silicon, Docker Desktop or OrbStack, configured for Linux
  containers.
- Windows: Windows 11 x64, Docker Desktop, configured for Linux containers.
- Internet access is needed when the application fetches RSS feeds or calls a
  cloud LLM. Loading the supplied image itself is offline.

The outer `.sha256` file (named the same as the ZIP) verifies the ZIP. On
macOS, run `shasum -a 256 your-package.zip`; on Windows, run
`Get-FileHash .\your-package.zip -Algorithm SHA256`, using your downloaded
file's name. Compare the result with the checksum in the `.sha256` file.

## First-time setup

macOS:

```bash
chmod +x paper-monitor-macos-arm64.sh
./paper-monitor-macos-arm64.sh setup
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd setup
```

The `.cmd` wrapper runs the PowerShell launcher with a temporary
execution-policy bypass, so no system setting has to be changed. Calling
`paper-monitor-windows-amd64.ps1` directly from PowerShell also works.

Follow the CLI steps to configure an LLM, RSS feeds, research profile, and
output. In Output settings, set the folder to `/app/output`.

Your API key remains in `config/llm_config.json` on this computer. Do not
share that file. To use local Ollama from this container, use the advanced
endpoint setting `http://host.docker.internal:11434/api/generate`, not
`localhost`.

## Run one cycle

```bash
./paper-monitor-macos-arm64.sh run
```

```powershell
.\paper-monitor-windows-amd64.cmd run
```

Generated Markdown appears in `output/`; history is in
`data/recommendations.csv`. To change the timezone, copy `.env.example` to
`.env` and edit `TZ` before running. Logs are available with
`docker compose logs rss-paper`.

Do not run the program in an OrbStack `orb-wormhole-temp-*` terminal. Use the
platform script or `docker compose` from this package directory.
