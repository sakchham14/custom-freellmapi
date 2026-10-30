#!/usr/bin/env bash
# Install the dependencies freellmapi-cc-setup needs.
#
# Idempotent: already-installed packages are skipped. The required set matches
# the upstream FreeLLMAPI Docker guide (Docker, Docker Compose, OpenSSL) plus
# the tools the wrapper scripts themselves call (jq, node, curl, git, npm).
#
# Platform handling:
#   macOS  -> Homebrew (installs Docker Desktop if missing)
#   Linux  -> apt (the distro package manager)
#   WSL    -> apt (the Linux distro inside WSL)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

OS="$(detect_os)"

# Map a package to its name on each platform. Bash 3.2 (stock macOS /bin/bash,
# and WSL's bash on a fresh install) has no associative arrays, so this is a
# function + case, not a map lookup.
brew_name() { case "$1" in docker) echo docker ;; openssl) echo openssl ;; jq) echo jq ;; node) echo node ;; curl) echo curl ;; git) echo git ;; npm) echo npm ;; *) echo "$1" ;; esac; }
apt_name()  { case "$1" in docker) echo docker.io ;; openssl) echo openssl ;; jq) echo jq ;; node) echo nodejs ;; curl) echo curl ;; git) echo git ;; npm) echo npm ;; *) echo "$1" ;; esac; }

missing=()
for pkg in docker openssl jq node curl git npm; do
  if command -v "$pkg" >/dev/null 2>&1; then
    ok "$pkg: $(command -v "$pkg")"
  else
    warn "$pkg: not found"
    missing+=("$pkg")
  fi
done

if [ "${#missing[@]}" -eq 0 ]; then
  ok "All dependencies present"
  exit 0
fi

log "Installing missing dependencies: ${missing[*]}"

case "$OS" in
  macos)
    if ! command -v brew >/dev/null 2>&1; then
      err "Homebrew not found. Install it first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      exit 1
    fi
    # Docker Desktop is the only Docker on macOS; `brew install docker`
    # is the desktop formula. If the CLI is missing but the app exists, the
    # CLI still needs linking.
    if ! command -v docker >/dev/null 2>&1; then
      if [ -d "/Applications/Docker.app" ]; then
        warn "Docker Desktop installed but CLI not on PATH — open Docker Desktop once to finish setup"
      else
        log "Installing Docker Desktop via Homebrew..."
        brew install --cask docker
      fi
    fi
    for pkg in "${missing[@]}"; do
      [ "$pkg" = "docker" ] && continue   # handled above
      pkg_name="$(brew_name "$pkg")"
      log "brew install $pkg_name"
      brew install "$pkg_name" || warn "brew install $pkg_name failed (continuing)"
    done
    ;;

  linux|*)
    # Linux and WSL both use apt. WSL's distro is Ubuntu, so apt works.
    if ! command -v apt-get >/dev/null 2>&1; then
      err "apt-get not found — this distro isn't supported by this installer"
      exit 1
    fi
    sudo apt-get update -qq
    # nodejs package name differs: Debian/Ubuntu call it nodejs, the CLI is `node`.
    install_args=()
    for pkg in "${missing[@]}"; do
      install_args+=("$(apt_name "$pkg")")
    done
    log "apt-get install ${install_args[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${install_args[@]}"

    # The nodejs package installs the binary as nodejs; symlink to node if needed.
    if ! command -v node >/dev/null 2>&1 && command -v nodejs >/dev/null 2>&1; then
      sudo ln -sf "$(command -v nodejs)" /usr/local/bin/node
      ok "symlinked nodejs -> node"
    fi
    ;;
esac

# --- Verify -----------------------------------------------------------------
fail=0
for pkg in docker openssl jq node curl git npm; do
  if command -v "$pkg" >/dev/null 2>&1; then
    ok "$pkg: $(command -v "$pkg")"
  else
    err "$pkg: STILL MISSING after install"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  err "Some dependencies could not be installed. Install them manually and re-run."
  exit 1
fi

# docker compose is a subcommand of the docker CLI, not a separate binary.
if ! docker compose version >/dev/null 2>&1; then
  err "docker compose not available — install Docker Desktop / docker engine with compose plugin"
  exit 1
fi
ok "docker compose: $(docker compose version)"

ok "All dependencies installed"