import express from "express";
import config, { validateConfig } from "./config.js";
import { handleWebhook } from "./handlers/webhook-handler.js";
import * as clickupService from "./services/clickup-service.js";
import * as openclawService from "./services/openclaw-service.js";

// ── Validate configuration ─────────────────────────────────────────
try {
  validateConfig();
} catch (err) {
  console.error(`\n❌ Configuration Error:\n${err.message}\n`);
  process.exit(1);
}

// ── Create Express app ──────────────────────────────────────────────
const app = express();

// Parse JSON bodies (needed for webhook payloads)
// Store raw body for signature verification
app.use(
  express.json({
    verify: (req, _res, buf) => {
      req.rawBody = buf.toString();
    },
  })
);

// ── Routes ──────────────────────────────────────────────────────────

// Health check
app.get("/health", async (_req, res) => {
  const openclawHealthy = await openclawService.healthCheck();
  res.json({
    status: "ok",
    service: "clickup-agent-bridge",
    timestamp: new Date().toISOString(),
    openclaw: {
      url: config.openclaw.url,
      reachable: openclawHealthy,
      agent: config.openclaw.agentId,
    },
    statuses: config.statuses,
  });
});

// ClickUp webhook receiver
app.post("/webhook/clickup", handleWebhook);

// Catch-all for unknown routes
app.use((_req, res) => {
  res.status(404).json({
    error: "Not found",
    hint: "Webhook endpoint is POST /webhook/clickup",
  });
});

// Global error handler
app.use((err, _req, res, _next) => {
  console.error("[Server] Unhandled error:", err);
  res.status(500).json({ error: "Internal server error" });
});

// ── Start server ────────────────────────────────────────────────────
app.listen(config.port, async () => {
  console.log(`
╔══════════════════════════════════════════════════════╗
║         ClickUp ↔ OpenClaw Agent Bridge              ║
╠══════════════════════════════════════════════════════╣
║  Server:    http://localhost:${String(config.port).padEnd(25)}║
║  Webhook:   POST /webhook/clickup                    ║
║  Health:    GET  /health                             ║
╠══════════════════════════════════════════════════════╣
║  OpenClaw:  ${config.openclaw.url.padEnd(40)}║
║  Agent:     ${config.openclaw.agentId.padEnd(40)}║
╠══════════════════════════════════════════════════════╣
║  Trigger:   status → "${config.statuses.trigger}"${" ".repeat(Math.max(0, 30 - config.statuses.trigger.length))}║
║  Progress:  status → "${config.statuses.inProgress}"${" ".repeat(Math.max(0, 30 - config.statuses.inProgress.length))}║
║  Review:    status → "${config.statuses.review}"${" ".repeat(Math.max(0, 30 - config.statuses.review.length))}║
║  Failed:    status → "${config.statuses.failed}"${" ".repeat(Math.max(0, 30 - config.statuses.failed.length))}║
╚══════════════════════════════════════════════════════╝
  `);

  // Auto-register webhook if configured
  if (config.webhook.autoRegister && config.clickup.workspaceId) {
    try {
      console.log("[Startup] Auto-registering webhook...");
      const result = await clickupService.createWebhook(
        config.clickup.workspaceId,
        config.webhook.callbackUrl,
        ["taskStatusUpdated"],
        config.clickup.webhookSecret || undefined
      );
      console.log(`[Startup] ✅ Webhook registered: ${result.id}`);
    } catch (err) {
      console.warn(`[Startup] ⚠️ Failed to register webhook: ${err.message}`);
      console.warn(
        "[Startup] You may need to register the webhook manually."
      );
    }
  }

  // Check OpenClaw connectivity
  const openclawOk = await openclawService.healthCheck();
  if (openclawOk) {
    console.log("[Startup] ✅ OpenClaw Gateway is reachable");
  } else {
    console.warn(
      `[Startup] ⚠️ OpenClaw Gateway at ${config.openclaw.url} is not reachable`
    );
    console.warn(
      "[Startup] The bridge will still start, but tasks may fail until OpenClaw is available."
    );
  }
});
