# Paper Monitor

Paper Monitor helps you keep up with new research papers. It checks journal
feeds, asks an AI model which papers match your interests, and creates a daily
Markdown reading list.

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

Each run checks for new papers and creates one reading list. Run the launcher
again whenever you want a new list.

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
