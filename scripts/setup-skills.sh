#!/bin/bash
# Installs skill prerequisites to /data on first run.
# Idempotent — safe to call on every container start.
# Add new tools here; they persist on the Railway volume across redeploys.
set -e

mkdir -p /data/bin /data/uv

# mcporter — npm global install, lands in /data/npm/bin via NPM_CONFIG_PREFIX
if ! command -v mcporter &>/dev/null; then
  echo "[skills-setup] Installing mcporter..."
  npm install -g mcporter
fi

# uv — Python tool runner, installed to /data/uv
if ! command -v uv &>/dev/null; then
  echo "[skills-setup] Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/data/uv sh
fi

# gogcli — Google Workspace CLI binary, installed to /data/bin
if ! command -v gog &>/dev/null; then
  echo "[skills-setup] Installing gogcli..."
  ARCH=$(dpkg --print-architecture)
  curl -fsSL "https://github.com/openclaw/gogcli/releases/download/v0.19.0/gogcli_0.19.0_linux_${ARCH}.tar.gz" \
    | tar -xz -C /data/bin gog
fi

# clawhub CLI — registry auth, skill/plugin search, publish, sync
if ! command -v clawhub &>/dev/null; then
  echo "[skills-setup] Installing clawhub..."
  npm install -g clawhub
fi

echo "[skills-setup] Skill prerequisites ready."
