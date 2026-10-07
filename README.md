# Paper Monitor

Paper Monitor is a repeatable pipline for keeping up with new research. Each
run fetches the latest entries available from your selected journal RSS feeds,
skips papers it has already analyzed whether or not they were recommended, and
uses an AI model to evaluate the remaining papers against your research
profile. It then writes a Markdown report containing the papers that meet your
recommendation threshold.

Run it whenever you want an update, or schedule it to run every day for an
automatic daily report of newly discovered papers relevant to your research.

You do not need to install R or work with Docker commands. Download the package
for your computer and use the included launcher script to open its menu, run a
monitoring cycle, or uninstall Paper Monitor.

## What you need

- A Mac with Apple Silicon, or a Windows 11 x64 computer
- Docker Desktop, or OrbStack on a Mac
- An API key for an online AI service such as OpenAI, Anthropic, or DeepSeek;
  or a local Ollama model, which does not need an API key
- Internet access for checking journal feeds

A ChatGPT, Claude, or other website/app subscription cannot be used in place
of an API key. API access is a separate service and may be billed separately
by the provider.

## Download and unpack

Download the package for your computer from the
[latest release](https://github.com/linzhiheng/paper-monitor/releases/latest):

- Mac: `PaperMonitor-...-macos-arm64.zip`
- Windows: `PaperMonitor-...-windows-amd64.zip`

Extract the ZIP, then keep all files in the extracted folder together. Start
Docker Desktop or OrbStack before using Paper Monitor.

## Open Paper Monitor

Open Terminal on a Mac or PowerShell on Windows in the extracted folder. Then
run the menu command for your computer.

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
the interactive menu. On the first launch, the guided setup asks you to choose
an AI service and enter its API key, add journals, describe your research
interests, and confirm where results should be saved. Local Ollama is the only
built-in option that does not need an API key. Use `/app/output` as the output
folder.

## Journal feeds are included

You do not need to find RSS addresses yourself. Paper Monitor includes a
searchable library of 50 journal feeds from:

- AGU
- EGU
- *Philosophical Transactions of the Royal Society A*
- Selected Springer Earth-science journals

Choose one or more journals during initial setup. You can search the library or
add another RSS address manually if the journal you want is not included.

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

Your reading lists appear in the `output` folder. Each paper includes its
relevance score, matched topics, citation details, a short summary, and an
explanation of why it may interest you.

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

The generated Markdown files work in Obsidian and ordinary Markdown readers.

![Example Paper Monitor output shown in Obsidian](release/assets/output-example.png)

## Change your settings

Run the `menu` command again. You can add or remove journals, change the AI
service, update your research interests, or change output settings.

Your settings, reading history, and generated files are stored in the
`config`, `data`, and `output` folders inside the extracted package.

## Uninstall

Use the included launcher instead of entering Docker commands yourself.

Mac:

```bash
./paper-monitor-macos-arm64.sh uninstall
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd uninstall
```

The launcher removes the installed Paper Monitor image. By default, it keeps
your settings, history, and reading lists so that you can use them again. It
only deletes those files after you explicitly request a full cleanup and type
`DELETE` when asked.

For more help, see the
[full installation and usage guide](release/INSTALL_AND_USAGE.md).

## For developers

The main program is `Paper_Monitor.R`. To build the container from source and
run one cycle:

```bash
docker compose build
docker compose up --no-build rss-paper
```

To open the interactive menu from a source checkout:

```bash
docker compose run --rm -it rss-paper Rscript Paper_Monitor.R
```

Release packages are built with `scripts/release/build.sh` from a matching Git
version tag.
