# ClickUp → OpenClaw Agent Bridge

Bridge service that connects ClickUp task management with an OpenClaw AI agent.

## How It Works

1. You create a task in ClickUp with a prompt/description
2. You set the task status to **"FOR AGENT"**
3. The bridge receives a webhook from ClickUp
4. It sends the task description to your OpenClaw agent
5. The agent's response is posted back as a ClickUp comment
6. Task status is updated to **"REVIEW"** for your inspection

## Setup

### 1. Install Dependencies
```bash
npm install
```

### 2. Configure Environment
```bash
cp .env.example .env
# Edit .env with your actual values
```

### 3. Run Locally
```bash
npm run dev
```

### 4. Expose for Webhooks (Local Development)
Use [ngrok](https://ngrok.com/) to expose your local server:
```bash
ngrok http 3000
```
Then register the ngrok URL as your webhook endpoint in ClickUp.

### 5. Register ClickUp Webhook
The bridge auto-registers a webhook on startup if `AUTO_REGISTER_WEBHOOK=true` is set.
Or register manually via the ClickUp API.

## Status Flow
```
TO DO → FOR AGENT → IN PROGRESS → REVIEW → DONE
                                         ↘ FAILED
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | No | Server port (default: 3000) |
| `CLICKUP_API_TOKEN` | Yes | ClickUp Personal API Token |
| `CLICKUP_WEBHOOK_SECRET` | No | Secret for HMAC signature validation |
| `OPENCLAW_URL` | Yes | OpenClaw Gateway URL |
| `OPENCLAW_API_TOKEN` | Yes | OpenClaw Bearer token |
| `OPENCLAW_AGENT_ID` | No | Agent ID (default: openclaw/default) |
| `STATUS_TRIGGER` | No | Trigger status (default: "for agent") |
| `STATUS_IN_PROGRESS` | No | In-progress status (default: "in progress") |
| `STATUS_REVIEW` | No | Review status (default: "review") |
| `STATUS_FAILED` | No | Failed status (default: "failed") |

## Deployment (Railway)

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app)

1. Push this repo to GitHub
2. Connect to Railway
3. Set environment variables in Railway dashboard
4. Railway will auto-deploy on push
