import dotenv from "dotenv";
dotenv.config();

const config = {
  port: parseInt(process.env.PORT || "3000", 10),

  clickup: {
    apiToken: process.env.CLICKUP_API_TOKEN,
    webhookSecret: process.env.CLICKUP_WEBHOOK_SECRET || null,
    workspaceId: process.env.CLICKUP_WORKSPACE_ID || null,
    listId: process.env.CLICKUP_LIST_ID || null,
  },

  openclaw: {
    url: process.env.OPENCLAW_URL,
    apiToken: process.env.OPENCLAW_API_TOKEN,
    agentId: process.env.OPENCLAW_AGENT_ID || "openclaw/default",
  },

  statuses: {
    trigger: (process.env.STATUS_TRIGGER || "for agent").toLowerCase(),
    inProgress: (process.env.STATUS_IN_PROGRESS || "in progress").toLowerCase(),
    review: (process.env.STATUS_REVIEW || "review").toLowerCase(),
    failed: (process.env.STATUS_FAILED || "failed").toLowerCase(),
  },

  webhook: {
    autoRegister: process.env.AUTO_REGISTER_WEBHOOK === "true",
    callbackUrl: process.env.WEBHOOK_CALLBACK_URL || null,
  },
};

/**
 * Validate that all required configuration is present.
 * Throws on missing required values.
 */
export function validateConfig() {
  const missing = [];

  if (!config.clickup.apiToken) {
    missing.push("CLICKUP_API_TOKEN");
  }
  if (!config.openclaw.url) {
    missing.push("OPENCLAW_URL");
  }
  if (!config.openclaw.apiToken) {
    missing.push("OPENCLAW_API_TOKEN");
  }

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(", ")}\n` +
        `Copy .env.example to .env and fill in the values.`
    );
  }

  if (config.webhook.autoRegister) {
    if (!config.webhook.callbackUrl) {
      missing.push("WEBHOOK_CALLBACK_URL");
    }
    if (!config.clickup.workspaceId) {
      missing.push("CLICKUP_WORKSPACE_ID");
    }
    if (missing.length > 0) {
      throw new Error(
        `Auto-register webhook requires: ${missing.join(", ")}`
      );
    }
  }
}

export default config;
