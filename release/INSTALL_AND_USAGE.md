# Paper Monitor v0.1.1 — Installation and Usage

Paper Monitor finds new journal articles and creates a reading list based on
your research interests. Each paper has a short summary, a relevance score,
and a reason why it may be useful to you.

The package already contains the Paper Monitor software. Use the launcher
script in this folder to install it, change settings, run it, or uninstall it.

## 1. Before you start

You need:

- A Mac with Apple Silicon, or a Windows 11 x64 computer
- Docker Desktop, or OrbStack on a Mac
- A few gigabytes of free disk space
- Internet access for checking journal feeds
- An API key if you want to use an online AI service

### About AI accounts and API keys

Online services such as OpenAI, Anthropic, and DeepSeek require an API key. A
ChatGPT, Claude, or other website/app subscription cannot be used in place of
an API key. API access is a separate service and may be billed separately by
the provider.

If you already run Ollama on this computer, you can use a local model instead.
Local Ollama does not need an API key.

## 2. Extract the package

Mac: double-click the ZIP in Finder.

Windows: right-click the ZIP and choose **Extract All**.

Open the extracted folder. Keep everything in this folder together. Do not
run the launcher from inside the ZIP.

The main items in the folder are:

- `paper-monitor-macos-arm64.sh` or `paper-monitor-windows-amd64.cmd` — the
  launcher for your computer
- `config` — your settings
- `data` — your reading history
- `output` — your generated reading lists
- `README.md` and `INSTALL_AND_USAGE.md` — help documents

The other files support the launcher and should not be moved or renamed.

## 3. Set up Paper Monitor

Start Docker Desktop or OrbStack first. Then open Terminal on a Mac or
PowerShell on Windows in the extracted folder.

Run the setup command for your computer.

Mac:

```bash
chmod +x paper-monitor-macos-arm64.sh
./paper-monitor-macos-arm64.sh setup
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd setup
```

Use the Windows `.cmd` launcher shown above. You do not need to change the
PowerShell execution policy.

The first setup may take a minute because the launcher installs the included
Paper Monitor image. It does this automatically; you do not need a Docker
account or a separate installation command.

The setup guide asks for four things:

1. **AI service** — choose a provider and model, then enter its API key. The
   setup tests the connection before saving it. Local Ollama does not need a
   key.
2. **Journals** — choose one or more journals from the included RSS library.
3. **Research interests** — answer a short AI-guided interview or enter the
   information yourself.
4. **Output folder** — use `/app/output`. Your reading lists will then appear
   in the `output` folder next to the launcher.

Your API key is saved as plain text in `config/llm_config.json` on this
computer. Keep that file private and do not share it.

## 4. Choose journal feeds

You do not need to search the web for RSS addresses. Paper Monitor includes a
searchable library of 50 journal feeds:

- 24 AGU journals
- 20 EGU journals
- *Philosophical Transactions of the Royal Society A*
- Five selected Springer Earth-science journals

In the journal list:

- Type a journal number to select or deselect it.
- Press `s` to search by journal name or publisher.
- Press `n` or `p` to move between pages.
- Press `a` to add all selected journals.
- After at least one feed has been added, press `d` to continue setup.
- Press `m` if you want to enter an RSS address that is not in the library.

You can return to the journal list later by running `setup` again.

## 5. Run Paper Monitor

Run one monitoring cycle whenever you want a new reading list.

Mac:

```bash
./paper-monitor-macos-arm64.sh run
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd run
```

Paper Monitor checks the selected journals, skips papers it has seen before,
and asks your AI service to score the new papers. It then saves a file named
`Daily_Papers_<date>.md` in the `output` folder. The launcher closes when the
reading list is ready.

## 6. Example output

The result is a Markdown file that works in Obsidian and ordinary Markdown
readers. It includes the paper title, journal, authors, link, relevance score,
matched topics, short summary, and reason for the recommendation.

![Example Paper Monitor output shown in Obsidian](assets/output-example.png)

## 7. Change settings later

Run the setup command again at any time:

Mac:

```bash
./paper-monitor-macos-arm64.sh setup
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd setup
```

You can add or remove journals, change the AI service, update your research
interests, change output settings, or review your recommendation history.

If you use Ollama on the same computer, use this address in its advanced
settings:

```text
http://host.docker.internal:11434/api/generate
```

Do not use `localhost`; inside Paper Monitor, that name refers to the
container itself.

## 8. Back up or move your information

Your information is stored in three folders next to the launcher:

- `config` — settings and your API key
- `data` — previously processed papers
- `output` — generated reading lists

Copy these folders to make a backup. To move Paper Monitor to another
computer, extract a fresh package there and copy these folders into it.

## 9. Uninstall Paper Monitor

Use the launcher from the extracted package folder.

Mac:

```bash
./paper-monitor-macos-arm64.sh uninstall
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd uninstall
```

The launcher stops Paper Monitor and removes its installed image. It keeps
`config`, `data`, and `output` by default.

When asked whether to keep your information:

- Press Enter or answer `y` to keep your settings, history, and reading lists.
- Answer `n` to request a full cleanup. You must then type `DELETE` exactly
  before the three folders are permanently removed.

The launcher does not delete the extracted package folder. If you kept your
information, copy the three folders somewhere safe before deleting that
folder yourself.

## 10. Troubleshooting

### Docker is not running

Start Docker Desktop or OrbStack, wait until it is ready, and run the launcher
again.

### Windows says Linux containers are required

Open Docker Desktop and switch it to Linux containers, then run the launcher
again.

### The AI connection test fails

Check that you entered an API key, not a ChatGPT or Claude subscription login.
Confirm that the key is active and that its API account has available credit.
Then run `setup` again.

### Ollama cannot be reached

Make sure Ollama is running. In Paper Monitor's advanced settings, use
`http://host.docker.internal:11434/api/generate` as the address.

### PowerShell refuses to run the `.ps1` file

Run `paper-monitor-windows-amd64.cmd` instead. The `.cmd` launcher handles the
required PowerShell setting automatically.

### OrbStack opens a temporary terminal

Do not run Paper Monitor from an `orb-wormhole-temp-*` terminal. Open your
normal Terminal app, go to the extracted package folder, and run the Mac
launcher there.

## 11. Optional download check

Each downloadable ZIP has a matching `.sha256` file. Checking it is optional.
If you want to verify the download, compare the ZIP's SHA-256 value with that
file. If the values differ, download the package again.
