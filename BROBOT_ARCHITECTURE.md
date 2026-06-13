# Brobot (OpenClaw on Railway) — Build & Architecture Reference

## Build Chain
Dockerfile (multi-stage) → Railway deploy → Container (EU West)

### Dockerfile
| Stage | Base | What |
|---|---|---|
| `openclaw-build` | `node:22-bookworm` | Clones OpenClaw v2026.3.8, pnpm build |
| Runtime | `node:22-bookworm` | Copies build + wrapper server.js |

### Runtime
- **OS**: Debian 12 (bookworm) x86_64
- **User**: `root` (no USER directive)
- **PID 1**: `tini` (zombie reaper)
- **Node**: 22.22.3
- **OpenClaw**: v2026.3.8 stable

### Entrypoint
```bash
tini -- /bin/sh -c "/app/scripts/setup-skills.sh && exec node src/server.js"
```

## Filesystem Layout

### Docker Image (read-only)
```
/openclaw/                  ← Built OpenClaw source
/openclaw/dist/entry.js     ← OpenClaw CLI entry
/app/
  ├── src/server.js          ← Wrapper Express server
  ├── src/setup-app.js       ← /setup UI frontend
  ├── scripts/setup-skills.sh
  └── package.json
/usr/local/bin/openclaw      ← Alias: node /openclaw/dist/entry.js "$@"
```

### Railway Volume (`/data` — 5GB persistent)
```
/data/
  ├── .clawdbot/              ← OPENCLAW_STATE_DIR
  │   ├── openclaw.json        ← Main config (editable via /setup)
  │   ├── openclaw.json.bak-*  ← Auto backups
  │   ├── gateway.token
  │   ├── credentials/
  │   ├── cache/
  │   ├── canvas/
  │   └── agents/main/
  │       ├── agent/auth-profiles.json
  │       └── sessions/
  ├── workspace/              ← OPENCLAW_WORKSPACE_DIR
  │   ├── AGENTS.md, SOUL.md, USER.md, IDENTITY.md, TOOLS.md, HEARTBEAT.md
  │   ├── memory/             ← Daily logs
  │   └── skills/             ← Installed skills
  ├── bin/                    ← Binary tools (gogcli)
  ├── uv/                     ← Python tool runner
  ├── npm/bin/                ← npm globals (clawhub, mcporter)
  ├── pnpm/                   ← pnpm home
  └── pnpm-store/             ← pnpm cache
```

## Environment Variables

### Set in Dockerfile
```bash
NPM_CONFIG_PREFIX=/data/npm
NPM_CONFIG_CACHE=/data/npm-cache
PNPM_HOME=/data/pnpm
PNPM_STORE_DIR=/data/pnpm-store
PATH="/data/bin:/data/uv:/data/npm/bin:/data/pnpm:${PATH}"
```

### Set via Railway Variables
| Variable | Value | Purpose |
|---|---|---|
| `OPENCLAW_CONFIG_DIR` | `/data/.clawdbot` | Config location |
| `OPENCLAW_STATE_DIR` | `/data/.clawdbot` | Runtime state |
| `OPENCLAW_WORKSPACE_DIR` | `/data/workspace` | Agent workspace |
| `OPENCLAW_GATEWAY_TOKEN` | `fcc22e2c5...` | Gateway auth |
| `SETUP_PASSWORD` | `Klobasa23!` | /setup UI auth |
| `FIRECRAWL_API_KEY` | `fc-2bb78d...` | Web search provider |

### Railway Auto-Injected
`PORT`, `RAILWAY_SERVICE_NAME`, `RAILWAY_PUBLIC_DOMAIN`, `RAILWAY_PRIVATE_DOMAIN`,
`RAILWAY_ENVIRONMENT_NAME`, `RAILWAY_VOLUME_ID`, `RAILWAY_VOLUME_NAME`,
`RAILWAY_VOLUME_MOUNT_PATH`, `RAILWAY_PROJECT_ID`, etc.

## ⚠️ Critical PATH Issue
Dockerfile sets `PATH="/data/bin:/data/uv:/data/npm/bin:/data/pnpm:..."` but OpenClaw's
**`exec` tool runs via `sh -lc` (login shell)**, which **resets PATH** to Debian defaults
(`/usr/local/bin:/usr/bin:/bin`).

**Fix**: We added `tools.exec.pathPrepend` in config:
```json
"exec": {
  "pathPrepend": ["/data/bin", "/data/npm/bin", "/data/pnpm", "/data/uv"]
}
```
This ensures volume binaries are always findable by the agent.

## Services & Ports
```
Browser → https://...up.railway.app:443
       ↓ (Railway routes PORT)
Wrapper (server.js) → :${PORT} (default 3000)
  ├── /setup/*              → Setup UI (Basic auth via SETUP_PASSWORD)
  ├── /setup/healthz        → Railway health probes
  ├── /healthz              → Public health (no auth)
  ├── /setup/api/config/raw → Config editor (GET/POST full JSON)
  ├── /setup/api/console/run→ Limited CLI (allowlisted commands)
  ├── /setup/import         → Restore tar.gz backup into /data
  ├── /setup/export         → Download /data as tar.gz
  └── /*                    → Proxy → OpenClaw Gateway :18789 (HTTP+WS)
```

## Startup Flow
```
Container start → tini → setup-skills.sh → node src/server.js
                                               ↓
                                         Resolve STATE_DIR, WORKSPACE_DIR
                                         Start Express on $PORT
                                         Sync gateway token to config
                                         Start gateway child process:
                                           node entry.js gateway run
                                           --bind loopback --port 18789
                                           --auth token --token <token>
```

## Pre-installed Tools (by setup-skills.sh)
| Tool | Location | How |
|---|---|---|
| `clawhub` | `/data/npm/bin/` | npm -g install |
| `mcporter` | `/data/npm/bin/` | npm -g install |
| `uv` | `/data/uv/` | astral.sh installer |
| `gog` (gogcli) | `/data/bin/` | GitHub release binary |

## OpenClaw Config (current active)
| Key | Value |
|---|---|
| `agents.defaults.model.primary` | `google/gemini-3.5-flash` |
| `agents.defaults.workspace` | `/data/workspace` |
| `tools.exec.host` | `gateway` |
| `tools.exec.security` | `full` |
| `tools.exec.ask` | `off` |
| `tools.exec.pathPrepend` | `["/data/bin","/data/npm/bin","/data/pnpm","/data/uv"]` |
| `tools.web.search.provider` | `firecrawl` |
| `tools.profile` | `coding` |

## Key Restrictions
- No channels configured (webchat-only)
- No sandbox — exec runs directly on gateway
- No paired node — no phone/device commands
- Memory search disabled (no embedding provider)