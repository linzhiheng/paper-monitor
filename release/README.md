# Paper Monitor v0.1.1 offline package

__PACKAGE_DESCRIPTION__

Paper Monitor fetches papers from RSS feeds, scores them with your chosen
LLM, and writes a Markdown digest. This package runs one monitoring cycle at
a time and installs from the included Docker image without a registry
download.

For more detail and troubleshooting, see `INSTALL_AND_USAGE.md`.

## Requirements

- macOS on Apple Silicon with Docker Desktop or OrbStack, or Windows 11 x64
  with Docker Desktop
- Docker configured to use Linux containers
- Internet access while fetching RSS feeds or using a cloud LLM

## Install and configure

1. Extract the ZIP in Finder or Windows Explorer.
2. Open a terminal in the extracted package folder.
3. Make sure Docker Desktop or OrbStack is running.
4. Start the setup command for your platform.

macOS:

```bash
chmod +x paper-monitor-macos-arm64.sh
./paper-monitor-macos-arm64.sh setup
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd setup
```

The first setup command automatically loads the included Docker image; no
registry login or separate image installation is needed. On Windows, the
`.cmd` launcher also avoids changing the system PowerShell execution policy.

Follow the CLI prompts to configure:

1. An LLM provider and model
2. At least one RSS feed from the built-in library
3. Your research profile
4. The output folder, which should be `/app/output`

The RSS step opens a searchable library of 50 verified journal feeds from
AGU, EGU, the Royal Society, and Springer. Select journal numbers to toggle
one or more choices, then press `a` to add them. After the first feed is
enabled, press `d` to continue setup. Press `s` to search, `n`/`p` to move
between pages, or `m` to enter an RSS URL manually when a journal is not in
the library.

Your API key is stored in plain text at `config/llm_config.json` on this
computer. Keep that file private. For local Ollama, use
`http://host.docker.internal:11434/api/generate` as the advanced endpoint,
not `localhost`.

## Run Paper Monitor

Run one monitoring cycle whenever you want:

macOS:

```bash
./paper-monitor-macos-arm64.sh run
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd run
```

The command exits when the cycle finishes. Generated Markdown appears in
`output/`, and recommendation history is saved in
`data/recommendations.csv`. Run the setup command again whenever you want to
change settings.

Settings, history, and output stay in `config/`, `data/`, and `output/` next
to this README. Back up those three folders before replacing or deleting the
package.

## Uninstall

The uninstall command stops Paper Monitor and removes its loaded Docker
image. It keeps `config/`, `data/`, and `output/` by default.

macOS:

```bash
./paper-monitor-macos-arm64.sh uninstall
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd uninstall
```

Press Enter at the data prompt to keep your settings, history, and output.
For a complete data cleanup, answer `n` and then type `DELETE` when asked.
The downloaded package folder is not deleted automatically.

## Optional integrity check

If you want to verify the download before extracting it, compare the ZIP's
SHA-256 value with the accompanying `.sha256` file. Commands are listed in
`INSTALL_AND_USAGE.md`.

Do not run the program in an OrbStack `orb-wormhole-temp-*` terminal. Use
your normal terminal from the extracted package folder.
