# Paper Monitor v0.1.3 — Installation and Usage

Paper Monitor is a repeatable workflow for keeping up with new research. Each
run fetches the latest entries available from your selected journal RSS feeds,
skips papers it has already analyzed whether or not they were recommended, and
uses an AI model to evaluate the remaining papers against your research
profile. It then writes a Markdown report containing the papers that meet your
recommendation threshold.

Run it whenever you want an update, or schedule it to run every day for an
automatic daily report of newly discovered papers relevant to your research.

The package already contains the Paper Monitor software. Use the launcher
script in this folder to open its menu, change settings, run a monitoring
cycle, or uninstall it.

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
- `output` — your generated Markdown reports
- `README.md` and `INSTALL_AND_USAGE.md` — help documents

The other files support the launcher and should not be moved or renamed.

## 3. Open Paper Monitor

Start Docker Desktop or OrbStack first. Then open Terminal on a Mac or
PowerShell on Windows in the extracted folder.

Run the menu command for your computer.

Mac:

```bash
chmod +x paper-monitor-macos-arm64.sh
./paper-monitor-macos-arm64.sh menu
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd menu
```

Use the Windows `.cmd` launcher shown above. You do not need to change the
PowerShell execution policy.

Opening the menu for the first time may take a minute because the launcher
installs the included Paper Monitor image. It does this automatically; you do
not need a Docker account or a separate installation command.

On the first launch, the setup guide asks for four things:

1. **AI service** — choose a provider and model, then enter its API key. Paper
   Monitor tests the connection before saving it. Local Ollama does not need a
   key.
2. **Journals** — choose one or more journals from the included RSS library.
3. **Research interests** — answer a short AI-guided interview or enter the
   information yourself.
4. **Output folder** — use `/app/output`. Your reports will then appear
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

You can return to the journal list later by running `menu` again.

## 5. Run Paper Monitor

Run one monitoring cycle whenever you want a new report.

Mac:

```bash
./paper-monitor-macos-arm64.sh run
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd run
```

Paper Monitor checks the latest entries from the selected RSS feeds against its
analysis history. It sends only papers that have not already been analyzed to
your AI service, up to the configured maximum, and scores them against your
research profile. Papers that meet your recommendation threshold are included
in a file named `Daily_Papers_<date>.md` in the `output` folder. If no new paper
qualifies, the report says so instead of repeating a previous recommendation.
The launcher closes when the report is ready.

During profile setup, choose whether `must_read` follows your overall research
direction or only a narrower current focus. In focused mode, general relevance
still controls recommendations; only the highest-priority `must_read` label
requires a direct focus match. Use **Settings > Researcher profile > Update
must-read scope/focus** to change this later without rebuilding the long-term
profile. Existing profiles are accepted without a manual migration.

### Run automatically

First finish the initial setup and run the `run` command manually once. This
confirms that Docker and your AI service are ready before you add a schedule.
Always schedule `run`; `menu` waits for keyboard input.

#### Mac: Shortcuts

1. Open **Shortcuts** and create a new shortcut.
2. Add the **Run Shell Script** action.
3. Enter the command below, replacing the example with the full path to the
   launcher in your extracted Paper Monitor folder:

   ```bash
   "/full/path/to/paper-monitor-macos-arm64.sh" run
   ```

4. Click **Edit > Automation**, add a **Time of Day** trigger, and choose when
   it should run.
5. To run without confirmation, open the shortcut's information, choose
   **Privacy**, and enable **Allow Running When Locked** if that option is
   available.

#### Windows: Task Scheduler

1. Open **Task Scheduler** and choose **Create Basic Task**.
2. Choose a schedule, such as **Daily**, and set the time.
3. Choose **Start a program**.
4. Enter these values, replacing the example paths with the location of your
   extracted Paper Monitor folder:

   - Program/script: `C:\Windows\System32\cmd.exe`
   - Add arguments: `/d /c ""C:\full\path\paper-monitor-windows-amd64.cmd" run"`
   - Start in: `C:\full\path`

5. Save the task. In Task Scheduler, right-click it and choose **Run** once to
   test it.

For either method, the computer must be awake and Docker Desktop or OrbStack
must already be running. If you use a local Ollama model, Ollama must also be
running. Keeping the scheduled task in your signed-in user session is the most
reliable choice for Docker Desktop.

With a daily schedule, Paper Monitor repeats the full workflow each day and
produces a new report of newly discovered papers relevant to your research.

## 6. Example output

The result is a Markdown file that works in Obsidian and ordinary Markdown
readers. It includes the paper title, journal, authors, link, relevance score,
matched topics, short summary, and reason for the recommendation.
Focused reports also explain the direct focus relationship separately from
overall research relevance. New history rows retain the scope and focus used at
evaluation time; the first expansion of an older history file creates a sibling
backup named `recommendations.pre-must-read-scope.csv`.

![Example Paper Monitor output shown in Obsidian](assets/output-example.png)

## 7. Change settings later

Run the menu command again at any time:

Mac:

```bash
./paper-monitor-macos-arm64.sh menu
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd menu
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
- `output` — generated Markdown reports

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

- Press Enter or answer `y` to keep your settings, history, and reports.
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
Then run `menu` again.

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
