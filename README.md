# Paper Monitor

Daily academic-paper monitoring pipeline. It fetches configured RSS feeds, filters and scores papers with the configured LLM, then writes a Markdown digest.

## Docker

The Docker service is a batch job: each run performs one recommendation cycle and exits. Scheduling stays outside the image.

### Build

```bash
docker compose build
```

### First-time configuration

The container mounts `config/`, `data/`, and `output/` from the project directory. API keys remain in `config/llm_config.json`; they are not passed through environment variables or copied into the image.

If configuration files are not yet present, open the existing interactive setup:

```bash
docker compose run --rm -it rss-paper Rscript Paper_Monitor.R
```

In **Output settings**, set the output folder to `/app/output`. Configure RSS feeds in the same CLI, or edit `config/feeds.json` directly. The researcher profile is stored in `config/research_profile.json`.

Optionally copy `.env.example` to `.env` to choose a container timezone. It contains no credentials.

### Run once

```bash
docker compose up --no-build rss-paper
```

The generated Markdown is written to `./output/`; recommendation history is retained at `./data/recommendations.csv`; feed health status is retained at `./config/feed_status.json`.

### Schedule with host cron

For example, run every day at 07:00 (replace `/path/to/project`):

```cron
0 7 * * * cd /path/to/project && docker compose up --no-build rss-paper
```

Do not use `restart: always`: failed runs should be visible and handled by your host scheduling/monitoring policy rather than retried invisibly.

### Logs and lifecycle

```bash
docker compose logs rss-paper
docker compose down
```

`docker compose up -d` is valid but starts only one batch run; the service exits when that run completes. It is not a long-running scheduler.

### Update after code changes

```bash
docker compose build
docker compose up --no-build rss-paper
```

## Private offline release

The maintained release target is a single offline ZIP for macOS Apple Silicon
and Windows 11 x64 Docker Desktop. Build it only from the exact local Git tag
matching `DESCRIPTION`'s version:

```bash
scripts/release/build.sh
```

The build creates `dist/PaperMonitor-v<version>-offline.zip` and a separate
`.sha256` file. It builds both Linux architectures, runs the R test suite and
configuration smoke tests, checks the Docker Desktop Ollama host route,
generates SPDX SBOMs, and blocks the release on unapproved HIGH or CRITICAL
vulnerabilities.

The packaged user documentation is `release/README.md` (quick start, copied
in as the package's `README.md`) and `release/INSTALL_AND_USAGE.md` (full
installation and usage guide). The package also includes the platform
launchers, with a Windows `.cmd` wrapper so recipients do not have to change
the PowerShell execution policy. Version strings inside both release
documents are literal; update them together with `DESCRIPTION` when
preparing a new version. Do not include user configuration or API-key files
when sharing the package.
