#!/bin/bash
set -euo pipefail

# Use the Railway volume if OPENCLAW_STATE_DIR is set, otherwise default
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${OPENCLAW_STATE_DIR:-/home/node/.openclaw}}"
PORT="${PORT:-18789}"

# Clean up corrupt config on startup (to recover from config errors)
if [ -f "$CONFIG_DIR/openclaw.json" ]; then
    if ! grep -q '"brave"\|"perplexity"\|"grok"\|"gemini"\|"kimi"' "$CONFIG_DIR/openclaw.json" 2>/dev/null || \
       grep -q 'web.search.provider.*openrouter' "$CONFIG_DIR/openclaw.json" 2>/dev/null; then
        echo "[openclaw-init] Invalid or corrupted config detected; removing for regeneration..."
        rm -f "$CONFIG_DIR/openclaw.json"
    fi
fi

# ── First-boot initialization ──────────────────────────────────────────────
if [ ! -f "$CONFIG_DIR/openclaw.json" ]; then
    echo "[openclaw-init] First boot — initializing config..."

    : "${OPENCLAW_GATEWAY_TOKEN:?ERROR: OPENCLAW_GATEWAY_TOKEN env var must be set}"
    : "${ANTHROPIC_API_KEY:?ERROR: ANTHROPIC_API_KEY env var must be set}"
    : "${GOOGLE_API_KEY:?ERROR: GOOGLE_API_KEY env var must be set}"

    # Use workspace dir from env or default to volume path
    WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$CONFIG_DIR/workspace}"

    mkdir -p \
        "$CONFIG_DIR/agents/main/agent" \
        "$WORKSPACE_DIR" \
        "/home/node/.config/openclaw"

    # ── Main config ──────────────────────────────────────────────────────
    cat > "$CONFIG_DIR/openclaw.json" <<EOF
{
  "agents": {
    "defaults": {
      "workspace": "${WORKSPACE_DIR}",
      "models": {
        "anthropic/claude-opus-4-7": {},
        "anthropic/claude-opus-4-5": {},
        "google/gemini-2.5-flash": {},
        "google/gemini-2.0-flash": {}
      },
      "model": {
        "primary": "google/gemini-2.5-flash"
      }
    }
  },
  "gateway": {
    "mode": "local",
    "port": ${PORT},
    "bind": "lan",
    "controlUi": {
      "allowInsecureAuth": true,
      "allowedOrigins": ["*"]
    },
    "nodes": {
      "denyCommands": [
        "camera.snap", "camera.clip", "screen.record",
        "contacts.add", "calendar.add", "reminders.add",
        "sms.send", "sms.search"
      ]
    },
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    }
  },
  "session": {
    "dmScope": "per-channel-peer"
  },
  "tools": {
    "profile": "coding",
    "exec": {
      "host": "gateway",
      "security": "full",
      "ask": "off",
      "timeoutSec": 1800
    },
    "web": {
      "search": {
        "provider": "firecrawl",
        "enabled": true
      }
    }
  },
  "auth": {
    "profiles": {
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key"
      }
    }
  },
  "channels": {
    "whatsapp": {
      "selfChatMode": true,
      "dmPolicy": "allowlist",
      "allowFrom": ["+420734740997"],
      "enabled": true
    }
  },
  "plugins": {
    "entries": {
      "bonjour": { "enabled": false },
      "firecrawl": {
        "enabled": true,
        "config": {
          "webSearch": {
            "apiKey": "${FIRECRAWL_API_KEY:-}"
          }
        }
      },
      "anthropic": { "enabled": true },
      "google": { "enabled": true },
      "openclaw-mem0": {
        "enabled": true,
        "config": {
          "mode": "platform",
          "apiKey": "${MEM0_API_KEY:-}",
          "userId": "default-user"
        }
      }
    }
  },
  "skills": {
    "install": { "nodeManager": "npm" },
    "entries": {
      "goplaces": { "apiKey": "${GOOGLE_PLACES_API_KEY:-}" },
      "1password": { "enabled": false },
      "apple-reminders": { "enabled": false },
      "apple-notes": { "enabled": false },
      "oracle": { "enabled": false }
    }
  },
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "session-memory": { "enabled": true }
      }
    }
  },
  "models": {
    "mode": "replace",
    "providers": {}
  }
}
EOF

    # ── Provider API keys ──────────────────────────────────────────────────
    cat > "$CONFIG_DIR/agents/main/agent/auth-profiles.json" <<EOF
{
  "version": 1,
  "profiles": {
    "anthropic:default": {
      "type": "api_key",
      "provider": "anthropic",
      "key": "${ANTHROPIC_API_KEY}"
    },
    "google:default": {
      "type": "api_key",
      "provider": "google",
      "key": "${GOOGLE_API_KEY}"
    }
  }
}
EOF

    # ── Seed workspace (no-clobber: never overwrite agent's own edits) ────
    cp -rn /app/seed/workspace/. "$WORKSPACE_DIR/"

    echo "[openclaw-init] Done. Config and workspace ready."
fi

# ── WhatsApp needs re-auth on a new host (QR scan via dashboard) ──────────
# Credentials are host-bound; skip copying stale baileys state.

# ── Start gateway ──────────────────────────────────────────────────────────
echo "[openclaw-start] Launching gateway on port $PORT..."
exec node /app/openclaw.mjs gateway --port "$PORT"
