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
./scripts/run.sh --enable-nginx-auth      # also enable nginx basic auth
./scripts/run.sh --skip-nginx             # skip nginx (proxy runs directly on port 3001)
./scripts/run.sh --skip-claude            # don't write Claude Code settings
./scripts/run.sh --watchtower             # also start the Watchtower self-updater
```

Defaults: port **3001**, bind **127.0.0.1**, shared-memory **on**, nginx auth **off**.

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