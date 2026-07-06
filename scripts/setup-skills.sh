#!/bin/bash
# Installs skill prerequisites to /data on first run.
# Idempotent — safe to call on every container start.
# All tools land on the Railway volume (/data) and persist across redeploys.
set -e

# ── Patch incompatible config fields (don't regenerate, just fix) ──
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-.clawdbot}"
CONFIG_PATH="/data/$CONFIG_DIR/openclaw.json"
if [ -f "$CONFIG_PATH" ]; then
    CONFIG_PATH="$CONFIG_PATH" node << 'PATCH_EOF'
const fs = require('fs');
const configPath = process.env.CONFIG_PATH;
try {
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  let changed = false;

  if (config.models !== undefined) {
    console.log('[setup] Removing invalid top-level models field...');
    delete config.models;
    changed = true;
  }

  if (!config.gateway) config.gateway = {};
  if (!config.gateway.controlUi) config.gateway.controlUi = {};
  const origins = config.gateway.controlUi.allowedOrigins;
  if (!Array.isArray(origins) || !origins.includes('*')) {
    console.log('[setup] Setting allowedOrigins to ["*"]...');
    config.gateway.controlUi.allowedOrigins = ['*'];
    changed = true;
  }

  if (changed) {
    const backupPath = configPath + '.bak.' + Date.now();
    fs.writeFileSync(backupPath, JSON.stringify(config, null, 2), 'utf8');
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2), 'utf8');
    console.log('[setup] Config patched and saved to volume.');
  } else {
    console.log('[setup] Config already valid.');
  }
} catch (e) {
  console.error('[setup] Config patch failed:', e.message);
}
PATCH_EOF
fi

# ── First-boot: generate config if missing ──────────────────────────────────
if [ ! -f "$CONFIG_PATH" ]; then
  echo "[setup] First boot: generating config from template..."

  mkdir -p "/data/$CONFIG_DIR/agents/main/agent"

  CONFIG_PATH="$CONFIG_PATH" GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:?Gateway token required}" \
    ANTHROPIC_KEY="${ANTHROPIC_API_KEY:?Anthropic API key required}" \
    GOOGLE_KEY="${GOOGLE_API_KEY:?Google API key required}" \
    node << 'INIT_EOF'
const fs = require('fs');
const path = require('path');
const configPath = process.env.CONFIG_PATH;
const gatewayToken = process.env.GATEWAY_TOKEN;
const anthropicKey = process.env.ANTHROPIC_KEY;
const googleKey = process.env.GOOGLE_KEY;

const config = {
  agents: {
    defaults: {
      workspace: path.dirname(configPath) + '/workspace',
      models: {
        'anthropic/claude-opus-4-7': {},
        'anthropic/claude-opus-4-5': {},
        'google/gemini-2.5-flash': {},
        'google/gemini-2.0-flash': {}
      },
      model: { primary: 'google/gemini-2.5-flash' }
    }
  },
  gateway: {
    mode: 'local',
    port: 18789,
    bind: 'loopback',
    controlUi: {
      allowInsecureAuth: true,
      allowedOrigins: ['*']
    },
    nodes: {
      denyCommands: [
        'camera.snap', 'camera.clip', 'screen.record',
        'contacts.add', 'calendar.add', 'reminders.add',
        'sms.send', 'sms.search'
      ]
    },
    auth: {
      mode: 'token',
      token: gatewayToken
    }
  },
  session: { dmScope: 'per-channel-peer' },
  tools: {
    profile: 'coding',
    exec: {
      host: 'gateway',
      security: 'full',
      ask: 'off',
      timeoutSec: 1800
    },
    web: {
      search: {
        provider: 'firecrawl',
        enabled: true
      }
    }
  },
  auth: {
    profiles: {
      'anthropic:default': {
        provider: 'anthropic',
        mode: 'api_key'
      }
    }
  },
  channels: {
    whatsapp: {
      selfChatMode: true,
      dmPolicy: 'allowlist',
      allowFrom: ['+420734740997'],
      enabled: true
    }
  },
  plugins: {
    entries: {
      bonjour: { enabled: false },
      firecrawl: {
        enabled: true,
        config: {
          webSearch: {
            apiKey: process.env.FIRECRAWL_API_KEY || ''
          }
        }
      },
      anthropic: { enabled: true },
      google: { enabled: true },
      'openclaw-mem0': {
        enabled: true,
        config: {
          mode: 'platform',
          apiKey: process.env.MEM0_API_KEY || '',
          userId: 'default-user'
        }
      }
    }
  },
  skills: {
    install: { nodeManager: 'npm' },
    entries: {
      goplaces: { apiKey: process.env.GOOGLE_PLACES_API_KEY || '' },
      '1password': { enabled: false },
      'apple-reminders': { enabled: false },
      'apple-notes': { enabled: false },
      oracle: { enabled: false }
    }
  },
  hooks: {
    internal: {
      enabled: true,
      entries: {
        'session-memory': { enabled: true }
      }
    }
  }
};

const authProfiles = {
  version: 1,
  profiles: {
    'anthropic:default': {
      type: 'api_key',
      provider: 'anthropic',
      key: anthropicKey
    },
    'google:default': {
      type: 'api_key',
      provider: 'google',
      key: googleKey
    }
  }
};

try {
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2), 'utf8');

  const authDir = path.join(path.dirname(configPath), 'agents/main/agent');
  fs.mkdirSync(authDir, { recursive: true });
  fs.writeFileSync(path.join(authDir, 'auth-profiles.json'), JSON.stringify(authProfiles, null, 2), 'utf8');

  console.log('[setup] Config generated and saved to volume.');
} catch (e) {
  console.error('[setup] Config generation failed:', e.message);
  process.exit(1);
}
INIT_EOF
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