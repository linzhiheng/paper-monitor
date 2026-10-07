# Paper Monitor v0.1.3

__PACKAGE_DESCRIPTION__

Paper Monitor is a repeatable workflow for keeping up with new research. Each
run fetches the latest entries available from your selected journal RSS feeds,
skips papers it has already analyzed whether or not they were recommended, and
uses an AI model to evaluate the remaining papers against your research
profile. It then writes a Markdown report containing the papers that meet your
recommendation threshold.

Run it whenever you want an update, or schedule it to run every day for an
automatic daily report of newly discovered papers relevant to your research.

Use the launcher included in this folder to open the interactive menu, run a
monitoring cycle, or uninstall Paper Monitor. You do not need to install R,
enter Docker commands, or download a container image separately.

## Before you start

You need:

- Docker Desktop, or OrbStack on a Mac
- An API key for an online AI service such as OpenAI, Anthropic, or DeepSeek;
  or a local Ollama model, which does not need an API key
- Internet access for checking journal feeds

A ChatGPT, Claude, or other website/app subscription cannot be used in place
of an API key. API access is a separate service and may be billed separately
by the provider.

## Open Paper Monitor

1. Extract the ZIP.
2. Start Docker Desktop or OrbStack.
3. Open Terminal or PowerShell in this folder.
4. Run the menu command for your computer.

Mac:

```bash
chmod +x paper-monitor-macos-arm64.sh
./paper-monitor-macos-arm64.sh menu
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd menu
```

The launcher installs the included Paper Monitor image automatically and opens
the interactive menu. On the first launch, the guided setup asks you to:

1. Choose an AI service and enter its API key. Local Ollama does not need a
   key.
2. Choose journals from the built-in RSS library.
3. Describe your research interests.
4. Confirm the output folder. Use `/app/output`.

Your API key is saved in `config/llm_config.json` on this computer. Keep this
file private.

## Journal feeds are included

You do not need to find RSS addresses yourself. Paper Monitor includes a
searchable library of 50 journal feeds from AGU, EGU, *Philosophical
Transactions of the Royal Society A*, and selected Springer Earth-science
journals.

Choose one or more journals, then press `a` to add them. After at least one
feed has been added, press `d` to continue. You can also press `s` to search
the library or `m` to add an RSS address manually.

## Run Paper Monitor

Each run checks the latest RSS entries against your analysis history. It sends
only papers that have not already been analyzed to your AI service, up to the
configured maximum, and scores them against your research profile. Papers that
meet your recommendation threshold are included in a new report.

Mac:

```bash
./paper-monitor-macos-arm64.sh run
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd run
```

The launcher closes when the report is ready. The result is saved in the
`output` folder.

## Run automatically

Complete the initial setup and test the `run` command once before scheduling
it. Always schedule `run`; `menu` waits for keyboard input. On a Mac, create a
shortcut with the **Run Shell Script** action, enter the following command with
the full path to your launcher, then add a **Time of Day** automation:

```bash
"/full/path/to/paper-monitor-macos-arm64.sh" run
```

On Windows, open **Task Scheduler** and create a basic task with your preferred
schedule. Choose **Start a program**, then use:

- Program/script: `C:\Windows\System32\cmd.exe`
- Add arguments: `/d /c ""C:\full\path\paper-monitor-windows-amd64.cmd" run"`
- Start in: the extracted Paper Monitor folder

The computer must be awake, and Docker Desktop or OrbStack must already be
running. If you use a local Ollama model, Ollama must also be running. With a
daily schedule, Paper Monitor repeats the workflow each day and produces a new
report; when nothing new qualifies, the report says so instead of repeating
previous recommendations.

## Example output

Each paper includes its relevance score, matched topics, citation details, a
short summary, and an explanation of why it may interest you. The Markdown
files work in Obsidian and ordinary Markdown readers.

![Example Paper Monitor output shown in Obsidian](assets/output-example.png)

## Change your settings

Run the `menu` command again. You can add or remove journals, change the AI
service, update your research interests, or change output settings.

Your files stay in these folders:

- `config` — settings, including your API key
- `data` — reading history
- `output` — generated Markdown reports

Back up these three folders before replacing or deleting the package.

## Uninstall

Mac:

```bash
./paper-monitor-macos-arm64.sh uninstall
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd uninstall
```

The launcher removes the installed Paper Monitor image. Press Enter when asked
if you want to keep your settings, history, and reports. A full cleanup
only happens if you request it and then type `DELETE`.

The extracted package folder is not deleted automatically.

For more help and troubleshooting, see `INSTALL_AND_USAGE.md`.
