# freellmapi-cc-setup

One-command bootstrap for **FreeLLMAPI + nginx + Claude Code**.

This is a thin wrapper around the upstream FreeLLMAPI Docker image. It adds an
nginx reverse proxy, optional HTTP Basic Auth, optional Watchtower self-updater,
and a one-shot Claude Code configuration that points at the gateway — so you get
a working local LLM proxy with token-saving compression and response caching
already turned on.

## What it does

| Step | What happens |
|---|---|
| 1. Install | Pulls `ghcr.io/tashfeenahmed/freellmapi:latest`, generates an encryption key + `.env`, starts the container |
| 2. nginx | Renders `nginx.conf` from the template (optional Basic Auth), starts the proxy on host port **80** → freellmapi:3001 |
| 3. Claude Code | Reads the unified API key straight from the FreeLLMAPI settings table and writes `~/.claude/settings.json` — `ANTHROPIC_BASE_URL=http://localhost:80/v1`, `ANTHROPIC_AUTH_TOKEN=<key>`, auto-compact + gateway model discovery on |
| 4. Gateway config | Reapplies compression (`aggressive`, auto-trigger at 32k tokens) + response cache after every start — the upstream image resets these on pull |

## Quick start

```bash
git clone https://github.com/sakchham14/custom-freellmapi.git
cd custom-freellmapi
./scripts/run.sh --quick
```

That's it. Run `claude` and it routes through the proxy automatically.

### On Windows: double-click `run.bat` instead

Windows doesn't know how to open a `.sh` file, so double-clicking `run.sh` in
File Explorer spawns a bash that exits immediately — the window opens and
closes before you can read anything. Use the Windows entry point instead:

```
double-click:  scripts\run.bat
from cmd:      scripts\run.bat --quick
from PowerShell: scripts\run.bat --quick
```

`run.bat` finds a working bash (WSL, Git Bash, or Cygwin), runs the real
script, and **keeps the window open on failure** so the error stays visible.

### Platform notes

The scripts are bash and call `docker compose`, so they need a bash environment
with Docker Desktop running. **WSL2 is the recommended path on Windows.**

- **macOS** — `./scripts/run.sh --quick` works as-is. Homebrew Docker Desktop is the common install.
- **Linux** — same command; make sure your user is in the `docker` group or use `sudo`.
- **Windows 11** — see the dedicated section below. Native Git Bash also works
  if Docker Desktop is on and `docker compose` resolves, but WSL2 is cleaner.

## Full options

```bash
./scripts/run.sh                          # interactive: prompts for every option
./scripts/run.sh --quick                  # all defaults, no prompts
./scripts/run.sh --quick --no-memory      # skip the shared-memory MCP server
./scripts/run.sh --quick --local-only     # skip Claude login AND server-side memory
./scripts/run.sh --enable-nginx-auth      # also enable nginx basic auth
./scripts/run.sh --skip-nginx             # skip nginx (proxy runs directly on port 3001)
./scripts/run.sh --skip-claude            # don't write Claude Code settings
./scripts/run.sh --watchtower             # also start the Watchtower self-updater
```

Defaults: port **3001**, bind **127.0.0.1**, shared-memory **on**, nginx auth **off**.

## Local-only mode

Use the gateway directly — no Claude login, no server-side memory. This is the
option if you want the FreeLLMAPI proxy without wiring up Claude Code or the
shared-memory MCP server.

```bash
./scripts/run.sh --quick --local-only
```

This is equivalent to `--skip-claude --no-memory` in one flag. It still installs
FreeLLMAPI and starts nginx; it just skips writing `~/.claude/settings.json`
and the memory MCP server.

### Use the gateway from any client

The proxy is at `http://localhost:80/v1`. Point any OpenAI-compatible client at
it — Claude Code, VS Code, curl, or a script:

```bash
# Claude Code (no settings file written, set the URL in your shell)
export ANTHROPIC_BASE_URL=http://localhost:80/v1
export ANTHROPIC_AUTH_TOKEN=local
claude

# curl
curl http://localhost:80/v1/models \
  -H "Authorization: Bearer local"
```

The gateway accepts **any** API key — it routes by model name, not by
credential, so `local` works everywhere.

## Setting up on Windows 11 (with Docker Desktop)

Recommended path: **WSL2**. The scripts are bash and expect a Unix home
directory, so running them directly under cmd/PowerShell breaks. WSL2 gives
you a real bash shell, `docker compose`, and a normal `$HOME` — everything the
scripts were written for.

### 1. Install prerequisites

- **Windows 11** with the Windows Subsystem for Linux enabled.
- **Docker Desktop** (latest) — install from docker.com, sign in, and leave it
  running. Enable **WSL2 backend** in Settings → General → Use the WSL2 based
  engine.
- **WSL2** — open PowerShell as Administrator and run:

```powershell
wsl --install
```

Then pick a distro (Ubuntu is the default and works fine) and finish the
setup. Open the Ubuntu terminal, set a username and password when prompted.

### 2. Install Docker CLI inside WSL

Docker Desktop exposes its daemon to WSL automatically, but the `docker`
command itself needs to be available in the WSL shell:

```bash
# Ubuntu
sudo apt update && sudo apt install -y docker.io docker-compose-v2
```

Verify:

```bash
docker --version
docker compose version
docker run hello-world
```

If `docker run hello-world` fails with a connection error, open Docker
Desktop → Settings → General and make sure **"Expose the Docker daemon on
localhost"** (or the equivalent WSL integration) is enabled.

### 3. Clone and run

```bash
git clone https://github.com/sakchham14/custom-freellmapi.git
cd custom-freellmapi
./scripts/run.sh --quick
```

That runs the full bootstrap: installs FreeLLMAPI, starts nginx on port 80,
and writes `~/.claude/settings.json` so `claude` routes through the proxy.

### 4. Run Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude
```

Claude Code will read `~/.claude/settings.json` and send traffic through
`http://localhost:80/v1` → nginx → freellmapi.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `docker: command not found` in WSL | Reopen the Ubuntu terminal; Docker Desktop's WSL integration may need a shell restart. Otherwise `sudo apt install docker.io` |
| `dial tcp 127.0.0.1:3001: connect: connection refused` | Docker Desktop isn't running — start it and wait for the whale icon |
| `nginx did not come up in time` | Check `docker compose logs nginx`; the freellmapi container must be healthy first |
| `Could not resolve unified API key` | freellmapi container isn't up or the DB path differs — check `docker compose logs freellmapi` |
| Proxy works but Claude Code says `connection refused` | Make sure Docker Desktop's port 80 is not blocked by Windows Defender Firewall |
| `claude` command not found | Install it: `npm install -g @anthropic-ai/claude-code` |

#### WSL opens and crashes on Windows 11

WSL crashing on launch is usually one of four things. Run each in an
**elevated PowerShell** (`Shift+Ctrl+right-click Start → Windows Terminal (Admin)`):

**1. WSL isn't initialized yet.** A fresh install needs a first-run step:

```powershell
wsl --set-default-version 2
wsl --set-default-directory \\wsl$\localhost\Ubuntu
wsl
```

The last command opens Ubuntu and asks for a username/password — set both,
then close it.

**2. The WSL2 kernel is out of date.** Windows 11 22H2 or earlier needs the
kernel update package:

```powershell
wsl --update
```

Restart after it finishes. If `wsl --update` fails, download the kernel MSI
from https://github.com/microsoft/wsl2-kernel/releases.

**3. The Linux distro is broken or in a bad state.** WSL keeps a tar backup of
each distro. Reset and reinstall:

```powershell
wsl --list --verbose
wsl --unregister Ubuntu
wsl --install --distribution Ubuntu
```

**4. Required Windows features are missing.** WSL2 needs Hyper-V and the
Windows Subsystem for Linux optional feature. Enable them and reboot:

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
wsl --set-default-version 2
```

Then reboot the machine. If you're on Windows 11 Home (no Hyper-V), WSL2
falls back to a lightweight VM — that still works, but make sure
**Virtualization is enabled in BIOS** (often called Intel VT-x / AMD-V).

If WSL opens but immediately exits with an error, run `wsl --status` in
PowerShell — it usually tells you which of the above is the problem.

## Setting up Claude Code (CLI)

If you ran the full bootstrap (no `--local-only`), Claude Code is already
configured — just run `claude`.

### Manual setup

If you skipped Claude Code during setup, or want to point an existing install at
the gateway:

```bash
npm install -g @anthropic-ai/claude-code
```

Then set the environment variables in your shell profile (`~/.zshrc`,
`~/.bashrc`, or the WSL equivalent):

```bash
export ANTHROPIC_BASE_URL=http://localhost:80/v1
export ANTHROPIC_AUTH_TOKEN=local
export ANTHROPIC_MODEL=auto
```

`ANTHROPIC_AUTH_TOKEN=local` works because the gateway routes by model name, not
by credential. Reload your shell and run `claude`.

### Using the gateway without Claude Code

Any OpenAI-compatible client works. The gateway is at `http://localhost:80/v1`:

```bash
# List models available through the gateway
curl http://localhost:80/v1/models -H "Authorization: Bearer local"

# A chat completion
curl http://localhost:80/v1/chat/completions \
  -H "Authorization: Bearer local" \
  -H "Content-Type: application/json" \
  -d '{"model":"auto","messages":[{"role":"user","content":"hello"}]}'
```

## Setting up VS Code

The gateway is an OpenAI-compatible endpoint, so the [GitHub Copilot
extension](https://marketplace.visualstudio.com/items?itemName=github.copilot)
or any extension that lets you set a custom base URL works. Two common paths:

### Option A: GitHub Copilot (with a Copilot subscription)

Install the Copilot extension, sign in, and it routes through GitHub's own
infrastructure — it will **not** use your local gateway. Use this if you want
Copilot's models.

### Option B: Custom OpenAI-compatible provider

If your extension supports a custom base URL (e.g. the **Continue** /
**Claude Code** extension, or **OpenAI** extension with a custom endpoint),
point it at the gateway:

| Setting | Value |
|---|---|
| Base URL | `http://localhost:80/v1` |
| API Key | `local` |
| Model | `auto` (gateway picks a free model) |

```bash
# If the extension reads from your environment:
export OPENAI_BASE_URL=http://localhost:80/v1
export OPENAI_API_KEY=local
```

### Option C: Claude Code extension

Install the [Claude Code VS Code extension](https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code), then set the same environment variables as the CLI section above:

```bash
export ANTHROPIC_BASE_URL=http://localhost:80/v1
export ANTHROPIC_AUTH_TOKEN=local
```

## Re-applying gateway config

The upstream image resets compression and cache settings on every pull. To
restore them after an update:

```bash
./scripts/reapply-gateway-config.sh
```

## Repository layout

| File | Purpose |
|---|---|
| `scripts/run.sh` | Entrypoint — parses options, runs the four setup steps |
| `scripts/install-freellmapi.sh` | Installs FreeLLMAPI via `docker compose`, generates `.env` + encryption key |
| `scripts/setup-nginx.sh` | Renders `nginx.conf` from the template (optional HTTP Basic Auth), starts the stack |
| `scripts/setup-claude.sh` | Reads the unified API key from the FreeLLMAPI DB and writes `~/.claude/settings.json` |
| `scripts/reapply-gateway-config.sh` | Restores compression + response-cache after any image update |
| `lib/common.sh` | Shared helpers: logging, `compose()` / `compose_exec()`, `wait_http()`, `require_cmd()`, `detect_os()` |
| `compose/docker-compose.yml` | freellmapi + nginx + optional watchtower |
| `nginx/nginx.conf.template` | Template rendered into `nginx.conf` at setup time |
| `nginx/nginx.conf` | Rendered reverse-proxy config (generated, not edited by hand) |
| `templates/settings.json` | Claude Code settings with shared-memory MCP + hooks |
| `templates/settings-no-memory.json` | Same, without the shared-memory MCP server |

## Security

- `.env`, `.encryption-key`, `nginx/.htpasswd`, and `~/.claude/settings.json` are **gitignored** — never committed.
- The unified API key is read from the FreeLLMAPI settings table at runtime. It
  is stored in plaintext there (that's how upstream ships it), but it never
  touches this repo.
- nginx Basic Auth, when enabled, generates a random password and prints it to
  the terminal. Save it somewhere safe — it is not stored anywhere else.

## Requirements

- Docker / Docker Desktop
- `openssl`, `jq`, `node`, `curl` (all checked at startup)
- A GitHub account if you want to fork, otherwise `git clone` is enough

## License

This wrapper is provided as-is. Add a `LICENSE` file to the repo root if you
want to govern usage of your fork.