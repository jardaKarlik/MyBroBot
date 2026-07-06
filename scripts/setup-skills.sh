#!/bin/bash
# Installs skill prerequisites to /data on first run.
# Idempotent — safe to call on every container start.
# All tools land on the Railway volume (/data) and persist across redeploys.
set -e

# ── Detect incompatible config and remove for regeneration ──
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-.clawdbot}"
if [ -f "/data/$CONFIG_DIR/openclaw.json" ]; then
    if node -e "
const fs = require('fs');
try {
  const c = JSON.parse(fs.readFileSync('/data/$CONFIG_DIR/openclaw.json', 'utf8'));
  const hasModels = c.models !== undefined;
  const origins = c.gateway?.controlUi?.allowedOrigins;
  const originsValid = Array.isArray(origins) && origins.includes('*');
  if (hasModels) { console.log('has-invalid-models'); process.exit(0); }
  if (!originsValid) { console.log('has-restrictive-origins'); process.exit(0); }
  process.exit(1);
} catch (e) { process.exit(1); }
" 2>/dev/null; then
        echo "[setup] Incompatible config detected (invalid models or restrictive CORS), regenerating..."
        cp "/data/$CONFIG_DIR/openclaw.json" "/data/$CONFIG_DIR/openclaw.json.bak.$(date +%s)" 2>/dev/null || true
        rm -f "/data/$CONFIG_DIR/openclaw.json"
    fi
fi

mkdir -p /data/bin /data/uv

# ── helpers ──────────────────────────────────────────────────────────────────

install_gh_bin() {
  local repo="$1" version="$2" binary="$3" archive="$4" dest="${5:-/data/bin}"
  if command -v "$binary" &>/dev/null || [ -f "$dest/$binary" ]; then
    echo "[setup] $binary already installed, skipping"; return
  fi
  local ARCH; ARCH=$(dpkg --print-architecture)
  local url; url=$(echo "$archive" | sed "s/VERSION/$version/g; s/ARCH/$ARCH/g")
  echo "[setup] Installing $binary ($version)..."
  curl -fsSL "https://github.com/$repo/releases/download/$version/$url" | tar -xz -C /tmp
  find /tmp -type f -name "$binary" -exec cp {} "$dest/$binary" \; -exec chmod +x "$dest/$binary" \;
  rm -rf /tmp/*/"$binary" 2>/dev/null || true
}

install_npm_global() {
  local pkg="$1" allow_scripts="$2"
  if command -v "$pkg" &>/dev/null; then echo "[setup] $pkg already installed, skipping"; return; fi
  echo "[setup] Installing $pkg via npm..."
  if [ -n "$allow_scripts" ]; then
    npm install -g --allow-scripts="$allow_scripts" "$pkg"
  else
    npm install -g "$pkg"
  fi
}

# Map dpkg arch to Google's tarball arch naming
gcloud_arch() {
  local a; a=$(dpkg --print-architecture)
  case "$a" in
    amd64)  echo "x86_64" ;;
    arm64)  echo "arm64"  ;;
    *)      echo "$a"     ;;
  esac
}

# ── existing tools ───────────────────────────────────────────────────────────

if ! command -v uv &>/dev/null; then
  echo "[setup] Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/data/uv sh
fi

install_gh_bin "openclaw/gogcli" "v0.19.0" "gog" "gogcli_0.19.0_linux_ARCH.tar.gz"
install_npm_global "clawhub"
install_npm_global "mcporter"

# ── common project tools (all projects) ──────────────────────────────────────

# gh — GitHub CLI
install_gh_bin "cli/cli" "v2.89.0" "gh" "gh_2.89.0_linux_ARCH.tar.gz"

# railway — Railway CLI (npm, needs allow-scripts for postinstall)
install_npm_global "@railway/cli" "@railway/cli"

# composio — Composio agentic tooling platform
install_npm_global "composio"

# skillfish — Skillfish CLI (ClawHub ecosystem)
install_npm_global "skillfish"

# Note: Firecrawl is an OpenClaw web search provider (tools.web.search).
# It's configured via the OpenClaw config + FIRECRAWL_API_KEY env var.
# No standalone CLI binary needed.

# gcloud — Google Cloud CLI (large, installs to /data/google-cloud-sdk)
if ! command -v gcloud &>/dev/null && [ ! -f /data/bin/gcloud ]; then
  echo "[setup] Installing gcloud CLI..."
  ARCH=$(gcloud_arch)
  curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-${ARCH}.tar.gz" \
    | tar -xz -C /data
  # Install alpha/beta components and set up
  /data/google-cloud-sdk/install.sh --quiet --additional-components alpha beta --install-python false --path-update false --command-completion false --usage-reporting false 2>/dev/null || true
  ln -sf /data/google-cloud-sdk/bin/gcloud /data/bin/gcloud
  ln -sf /data/google-cloud-sdk/bin/gsutil /data/bin/gsutil
  ln -sf /data/google-cloud-sdk/bin/bq /data/bin/bq
  echo "[setup] gcloud CLI installed to /data/google-cloud-sdk"
fi

echo "[setup] All prerequisites ready."