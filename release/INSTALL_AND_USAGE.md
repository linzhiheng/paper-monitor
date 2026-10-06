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

## 2. Extract the package

macOS: double-click the ZIP in Finder, or run:

```bash
unzip your-package.zip
```

Windows: right-click the ZIP and choose **Extract All…**

Open the extracted package folder and keep its contents together. Always run
the commands below from inside that folder, not from the ZIP itself.

The folder contains:

- `paper-monitor-macos-arm64.sh`, or `paper-monitor-windows-amd64.cmd` with
  `paper-monitor-windows-amd64.ps1` — the launcher for your platform
- `images/` — the container image archive for your platform (the combined
  package contains both)
- `compose.yaml`, `.env.example` — Docker configuration
- `resources/` — the built-in journal RSS library
- `config/`, `data/`, `output/` — your settings, history, and results
- `reports/` — software bill of materials and vulnerability reports
- `README.md`, `INSTALL_AND_USAGE.md` — the quick-start and this full guide
- `SHA256SUMS`, `LICENSE`

## 3. Install and complete first-time setup

Start Docker Desktop or OrbStack, open a terminal in the extracted package
folder, and run the setup command. The launcher automatically loads the
included container image the first time, so you do not need a registry
account or a separate `docker load` command. The first launch may take a
minute.

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
2. **RSS feeds** — choose one or more journals from the built-in searchable
   library. Nothing is enabled until you select it.
3. **Researcher profile** — you can either let the LLM draft it through a
   short interview, or write it by hand.
4. **Output settings** — set the output folder to exactly `/app/output`.
   This maps to the `output/` folder inside the package on your computer.

When everything is configured, press `q` at the main menu to leave. Each
step is saved to `config/` when you confirm it.

### Choosing RSS feeds

The RSS step opens the built-in library automatically when no feed is
configured. It contains 50 verified feeds: 24 AGU journals, 20 EGU
journals, *Philosophical Transactions of the Royal Society A*, and five
selected Springer earth-science journals.

- Type a journal number to select or deselect it. You can select several
  journals before saving.
- Press `s` to search by journal or publisher, and `n` or `p` to move
  between result pages.
- Press `a` to add all selected journals. Already configured journals are
  marked `[added]` and will not be duplicated.
- Once at least one feed is enabled, press `d` on the RSS Feeds page to
  continue to the next setup step. You do not need to finish building your
  full journal list first.
- Press `m` to enter an RSS URL manually if the journal you want is not in
  the library. The assistant will test it, suggest a parser and preview the
  articles before saving.

You can return to **Manage RSS feeds** later to add, test, disable, or delete
feeds.

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

### Moving the folders elsewhere

The three folders are bind-mounted into the container at `/app/config`,
`/app/data`, and `/app/output` (see `compose.yaml`). Two ways to relocate
them:

- **Digests only** — in Output settings, change the output folder. It must
  remain a container path; `/app/output` is the default.
- **Any or all folders** — edit the left-hand side of the `volumes:`
  entries in `compose.yaml` to absolute paths on your computer. The
  right-hand container paths must stay as they are. For example, to write
  digests straight into an Obsidian vault (macOS):

  ```yaml
  volumes:
    - ./config:/app/config
    - ./data:/app/data
    - /Users/<you>/Documents/ObsidianVault/PaperDigests:/app/output
  ```

Notes:

- Create the target folders before running.
- A package update brings a fresh `compose.yaml`, so re-apply your edits
  after upgrading.
- Absolute paths no longer travel with the package folder; relative paths
  (starting with `./`) always stay inside it.

## 6. Changing settings later

Run the setup command again at any time. It opens the same menu, where you
can search the RSS library or manage existing feeds, edit the research
profile, change LLM or output settings, and review or prune the
recommendation history.

**Time zone** — each day's digest file is named with the container's date.
To change the zone, copy `.env.example` to `.env` and edit the `TZ` value
(default `Asia/Tokyo`).

**Logs** — if you want to see what a run did:

```bash
docker compose logs rss-paper
```

## 7. Optional: verify the downloaded ZIP

This check is optional. Compare the accompanying `.sha256` value with the
result of `shasum -a 256 your-package.zip` on macOS or
`Get-FileHash .\your-package.zip -Algorithm SHA256` in Windows PowerShell.
If the values differ, request a fresh copy.

## 8. Troubleshooting

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

## 9. Removing Paper Monitor

Run the uninstall command from the extracted package folder.

macOS:

```bash
./paper-monitor-macos-arm64.sh uninstall
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd uninstall
```

The command stops and removes Paper Monitor's Docker Compose resources and
deletes the loaded `paper-monitor:v0.1.0` image. The offline image archive
and launcher remain in the package folder, so running `setup` later can
install it again.

At the data prompt:

- Press Enter or answer `y` to keep `config/`, `data/`, and `output/`. This
  is the default and preserves settings, API credentials, recommendation
  history, and generated digests for a later reinstall.
- Answer `n` to request a complete cleanup. The launcher then requires you
  to type `DELETE` exactly before it permanently removes those three
  folders. Any other answer cancels the data cleanup.

Only the three folders next to the launcher are eligible for deletion.
Folders you mapped to other host locations by editing `compose.yaml` are not
removed automatically.

The launcher does not delete the extracted package folder itself. If you no
longer need its offline image archive or launchers, delete that folder after
uninstalling. If you chose to keep your data, copy `config/`, `data/`, and
`output/` somewhere safe before deleting the package folder.
