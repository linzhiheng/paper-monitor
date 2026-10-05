# Paper Monitor v0.1.0 — Installation and Usage Guide

Paper Monitor watches RSS feeds from geophysics journals, scores each new
paper for relevance to your research profile using an LLM, and writes a
Markdown digest you can read in Obsidian or any text editor.

This is a private package: it installs entirely offline from the supplied
image files, with no registry account needed. One command runs one
monitoring cycle. Nothing leaves your computer except requests to the RSS
feeds and to the LLM service you configure.

## 1. What you need

- macOS on Apple Silicon, or Windows 11 x64.
- Docker Desktop (or OrbStack on macOS), configured to run **Linux
  containers**. Docker Compose v2 comes with it.
- A few GB of free disk space: a platform package is about 0.6 GB and the
  combined package about 1.1 GB, and Docker needs more room for the loaded
  container image.
- Internet access while the program runs, if you use a cloud LLM. If you
  use a local Ollama model, only RSS fetching needs the internet.

## 2. Verify and unpack the package

You should have received two files through a trusted channel: the ZIP and
its `.sha256` checksum file. The checksum file is named the same as the ZIP.

**Step 1 — Check the ZIP before using it.**

macOS:

```bash
shasum -a 256 your-package.zip
```

Windows PowerShell:

```powershell
Get-FileHash .\your-package.zip -Algorithm SHA256
```

Compare the result with the hash in the `.sha256` file. If they do not
match, stop and ask for a fresh copy.

**Step 2 — Unpack.**

macOS: double-click the ZIP in Finder, or run:

```bash
unzip your-package.zip
```

Windows: right-click the ZIP and choose **Extract All…**

You now have a folder named after the package. Keep the folder intact and
always run the commands from inside it, not from the ZIP itself.

The folder contains:

- `paper-monitor-macos-arm64.sh`, or `paper-monitor-windows-amd64.cmd` with
  `paper-monitor-windows-amd64.ps1` — the launcher for your platform
- `images/` — the container image archive for your platform (the combined
  package contains both)
- `compose.yaml`, `.env.example` — Docker configuration
- `config/`, `data/`, `output/` — your settings, history, and results
- `reports/` — software bill of materials and vulnerability reports
- `README.md`, `INSTALL_AND_USAGE.md` — the quick-start and this full guide
- `SHA256SUMS`, `LICENSE`

Optional extra check on macOS: run `shasum -a 256 -c SHA256SUMS` from
inside the package folder to verify every packaged file against the
manifest.

## 3. First-time setup

Open a terminal in the package folder and run the setup command. The first
launch loads the container image and may take a minute.

macOS:

```bash
chmod +x paper-monitor-macos-arm64.sh
./paper-monitor-macos-arm64.sh setup
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd setup
```

On Windows, use the `.cmd` wrapper: it runs the PowerShell launcher with a
temporary execution-policy bypass, so you do not have to change any system
settings.

The setup is a menu-driven assistant. It will ask you for:

1. **LLM settings** — pick a provider (Anthropic, OpenAI, DeepSeek, Ollama,
   or a custom OpenAI-compatible service), choose a model, and enter your
   API key where required. The assistant tests the connection before saving.
2. **RSS feeds** — the package starts with none, so add at least one
   journal feed. The assistant can detect the right parser for you.
3. **Researcher profile** — you can either let the LLM draft it through a
   short interview, or write it by hand.
4. **Output settings** — set the output folder to exactly `/app/output`.
   This maps to the `output/` folder inside the package on your computer.

When everything is configured, press `q` at the main menu to leave. Each
step is saved to `config/` when you confirm it.

Nothing needs to be prepared by hand: the package already contains the
`config/`, `data/`, and `output/` folders, the launcher recreates them
automatically if they are ever missing, and the setup assistant writes all
settings files into `config/` for you.

Two notes:

- Your API key is stored in plain text in `config/llm_config.json`, on this
  computer only. Keep that file private and never share it.
- If you use Ollama running on this same computer, set its endpoint in the
  advanced settings to `http://host.docker.internal:11434/api/generate`, not
  `localhost`.

## 4. Run a monitoring cycle

macOS:

```bash
./paper-monitor-macos-arm64.sh run
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd run
```

Each run fetches the latest items from your enabled feeds, skips papers that
were already scored before, asks your LLM to score the new ones, and writes
`output/Daily_Papers_<date>.md`. The command prints progress as it works and
exits by itself when the cycle is finished.

If no LLM is configured, the run stops immediately with an error. Run setup
first in that case.

## 5. Where your files and settings live

Inside the package folder:

- `config/` — your settings, including `llm_config.json` (which holds your
  API key), `feeds.json`, `research_profile.json`, `output_config.json`, and
  `template.md`
- `data/recommendations.csv` — the history of every paper ever scored
- `output/` — the generated Markdown digests

To back up everything you care about, copy `config/`, `data/`, and
`output/`. To move to another computer, copy those folders into a fresh
package on that machine.

## 6. Changing settings later

Run the setup command again at any time. It opens the same menu, where you
can manage RSS feeds, edit the research profile, change LLM or output
settings, and review or prune the recommendation history.

**Time zone** — each day's digest file is named with the container's date.
To change the zone, copy `.env.example` to `.env` and edit the `TZ` value
(default `Asia/Tokyo`).

**Logs** — if you want to see what a run did:

```bash
docker compose logs rss-paper
```

## 7. Troubleshooting

- **"Docker is installed but its daemon is not running"** — start Docker
  Desktop and run the command again.
- **"This package requires Docker Linux containers"** — on Windows, switch
  Docker Desktop to Linux containers (it is usually the default).
- **"This is the macOS ARM64 package; Docker reports architecture …"** —
  you are running a launcher that does not match your computer. Download
  the package for your platform and run its launcher.
- **"Image 'paper-monitor:v0.1.0' is 'arm64', not 'amd64'"** (or the
  reverse) — an image built for another platform is already loaded on this
  Docker host. Remove it with `docker image rm paper-monitor:v0.1.0` and run
  the launcher again.
- **PowerShell refuses to run the `.ps1` directly** — use the `.cmd`
  wrapper, which bypasses this automatically. If you prefer calling the
  PowerShell script directly, allow scripts for the current window only:

  ```powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  ```

  Then run the launcher again.
- **Ollama not reachable from the container** — make sure the endpoint is
  `http://host.docker.internal:11434/api/generate` and Ollama is running on
  the host.
- **On macOS with OrbStack** — do not run the program from an OrbStack
  `orb-wormhole-temp-*` terminal; use your normal terminal and the packaged
  launcher.

## 8. Removing Paper Monitor

- Delete the package folder. Your digests in `output/` and history in
  `data/` are inside it, so keep copies first if you want them.
- Optional: remove the container image with
  `docker image rm paper-monitor:v0.1.0`.
