# Paper Monitor v0.1.1

__PACKAGE_DESCRIPTION__

Paper Monitor helps you keep up with new research papers. It checks journal
feeds, asks an AI model which papers match your interests, and creates a daily
Markdown reading list.

Use the launcher included in this folder to set up, run, or uninstall Paper
Monitor. You do not need to install R, enter Docker commands, or download a
container image separately.

## Before you start

You need:

- Docker Desktop, or OrbStack on a Mac
- An API key for an online AI service such as OpenAI, Anthropic, or DeepSeek;
  or a local Ollama model, which does not need an API key
- Internet access for checking journal feeds

A ChatGPT, Claude, or other website/app subscription cannot be used in place
of an API key. API access is a separate service and may be billed separately
by the provider.

## Set up Paper Monitor

1. Extract the ZIP.
2. Start Docker Desktop or OrbStack.
3. Open Terminal or PowerShell in this folder.
4. Run the setup command for your computer.

Mac:

```bash
chmod +x paper-monitor-macos-arm64.sh
./paper-monitor-macos-arm64.sh setup
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd setup
```

The launcher installs the included Paper Monitor image automatically. The
guided setup asks you to:

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

Run one monitoring cycle whenever you want a new reading list.

Mac:

```bash
./paper-monitor-macos-arm64.sh run
```

Windows:

```powershell
.\paper-monitor-windows-amd64.cmd run
```

The launcher checks for new papers and closes when the reading list is ready.
The result is saved in the `output` folder.

## Example output

Each paper includes its relevance score, matched topics, citation details, a
short summary, and an explanation of why it may interest you. The Markdown
files work in Obsidian and ordinary Markdown readers.

![Example Paper Monitor output shown in Obsidian](assets/output-example.png)

## Change your settings

Run the `setup` command again. You can add or remove journals, change the AI
service, update your research interests, or change output settings.

Your files stay in these folders:

- `config` — settings, including your API key
- `data` — reading history
- `output` — generated reading lists

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
if you want to keep your settings, history, and reading lists. A full cleanup
only happens if you request it and then type `DELETE`.

The extracted package folder is not deleted automatically.

For more help and troubleshooting, see `INSTALL_AND_USAGE.md`.
