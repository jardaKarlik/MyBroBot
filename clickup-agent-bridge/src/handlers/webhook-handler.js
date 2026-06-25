import crypto from "node:crypto";
import config from "../config.js";
import * as clickup from "../services/clickup-service.js";
import * as openclaw from "../services/openclaw-service.js";

// Track in-flight tasks to prevent duplicate processing
const processingTasks = new Set();

/**
 * Handle an incoming ClickUp webhook event.
 *
 * Flow:
 * 1. Validate signature (if secret configured)
 * 2. Filter for taskStatusUpdated events where after.status === "for agent"
 * 3. Fetch full task details from ClickUp
 * 4. Update status to "in progress" and post a pickup comment
 * 5. Send task description to OpenClaw agent
 * 6. Post agent response as comment and update status to "review"
 * 7. On error: post error comment and set status to "failed"
 *
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 */
export async function handleWebhook(req, res) {
  const payload = req.body;

  // 1. Validate webhook signature if secret is configured
  if (config.clickup.webhookSecret) {
    const signature = req.headers["x-signature"];
    if (!verifySignature(JSON.stringify(payload), signature)) {
      console.warn("[Webhook] Invalid signature, rejecting request");
      return res.status(401).json({ error: "Invalid signature" });
    }
  }

  // 2. Filter for status update events
  const event = payload.event;
  if (event !== "taskStatusUpdated") {
    console.log(`[Webhook] Ignoring event: ${event}`);
    return res.status(200).json({ ok: true, skipped: true });
  }

  const taskId = payload.task_id;
  const historyItems = payload.history_items || [];

  // Find the status change in history_items
  const statusChange = historyItems.find((item) => item.field === "status");
  if (!statusChange) {
    console.log(`[Webhook] No status change found in history_items`);
    return res.status(200).json({ ok: true, skipped: true });
  }

  const afterRaw = statusChange.after;
  const beforeRaw = statusChange.before;
  const afterStatus = (typeof afterRaw === "object" ? afterRaw?.status : afterRaw)?.toLowerCase();
  const beforeStatus = (typeof beforeRaw === "object" ? beforeRaw?.status : beforeRaw)?.toLowerCase();

  console.log(
    `[Webhook] Task ${taskId}: status changed "${beforeStatus}" → "${afterStatus}"`
  );

  // Only trigger on our configured trigger status
  if (afterStatus !== config.statuses.trigger) {
    console.log(
      `[Webhook] Status "${afterStatus}" is not trigger "${config.statuses.trigger}", skipping`
    );
    return res.status(200).json({ ok: true, skipped: true });
  }

  // Prevent duplicate processing
  if (processingTasks.has(taskId)) {
    console.warn(`[Webhook] Task ${taskId} is already being processed`);
    return res.status(200).json({ ok: true, duplicate: true });
  }

  // Respond immediately — ClickUp expects a fast response
  res.status(200).json({ ok: true, processing: true });

  // Process the task asynchronously
  processTask(taskId).catch((err) => {
    console.error(`[Webhook] Unhandled error processing task ${taskId}:`, err);
  });
}

/**
 * Process a single task: fetch details, send to agent, report back.
 * @param {string} taskId
 */
async function processTask(taskId) {
  processingTasks.add(taskId);
  const startTime = Date.now();

  try {
    // 3. Fetch full task details
    console.log(`[Process] Fetching task ${taskId} details...`);
    const task = await clickup.getTask(taskId);
    const taskName = task.name || "Untitled Task";
    const taskDescription =
      task.description || task.text_content || task.markdown_content || "";

    if (!taskDescription.trim()) {
      throw new Error(
        "Task has no description. Please add a prompt/description to the task."
      );
    }

    console.log(`[Process] Task: "${taskName}"`);
    console.log(`[Process] Description length: ${taskDescription.length} chars`);

    // 4. Update status to "in progress" and post pickup comment
    await clickup.updateTaskStatus(taskId, config.statuses.inProgress);
    await clickup.addComment(
      taskId,
      `🤖 **Agent picked up this task**\n\n` +
        `Processing your request...\n` +
        `Agent: \`${config.openclaw.agentId}\`\n` +
        `Started: ${new Date().toISOString()}`
    );

    // 5. Send to OpenClaw agent
    console.log(`[Process] Sending to OpenClaw agent...`);
    const agentResponse = await openclaw.runAgent(taskDescription, {
      taskId,
      taskName,
    });

    // 6. Post response and update status to "review"
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

    // Truncate response if too long for a single comment (ClickUp limit ~50k chars)
    const maxCommentLength = 45000;
    let responseText = agentResponse;
    let wasTruncated = false;

    if (responseText.length > maxCommentLength) {
      responseText = responseText.substring(0, maxCommentLength);
      wasTruncated = true;
    }

    const commentBody =
      `🤖 **Agent Response** (${elapsed}s)\n\n` +
      `---\n\n` +
      responseText +
      (wasTruncated
        ? `\n\n---\n⚠️ *Response was truncated (${agentResponse.length} chars total). Full response may require multiple parts.*`
        : "") +
      `\n\n---\n` +
      `✅ Ready for review.`;

    await clickup.addComment(taskId, commentBody);
    
    try {
      await clickup.updateTaskStatus(taskId, config.statuses.review);
      console.log(
        `[Process] ✅ Task ${taskId} completed in ${elapsed}s, status → "${config.statuses.review}"`
      );
    } catch (statusError) {
      console.warn(`[Process] Failed to update status to "${config.statuses.review}":`, statusError.message);
      await clickup.addComment(
        taskId,
        `⚠️ **Notice**: Could not update task status to **"${config.statuses.review}"** (it might not be enabled in this ClickUp List's settings).`
      );
    }
  } catch (error) {
    // 7. On error: post error comment and set status to "failed"
    console.error(`[Process] ❌ Task ${taskId} failed:`, error.message);

    try {
      await clickup.addComment(
        taskId,
        `❌ **Agent Error**\n\n` +
          `The agent encountered an error while processing this task:\n\n` +
          `\`\`\`\n${error.message}\n\`\`\`\n\n` +
          `You can retry by setting the status back to **"${config.statuses.trigger}"**.`
      );
      try {
        await clickup.updateTaskStatus(taskId, config.statuses.failed);
      } catch (statusError) {
        console.warn(`[Process] Failed to update status to "${config.statuses.failed}":`, statusError.message);
        await clickup.addComment(
          taskId,
          `⚠️ **Notice**: Could not update task status to **"${config.statuses.failed}"** (it might not be enabled in this ClickUp List's settings).`
        );
      }
    } catch (reportError) {
      console.error(
        `[Process] Failed to report error to ClickUp:`,
        reportError.message
      );
    }
  } finally {
    processingTasks.delete(taskId);
  }
}

/**
 * Verify the HMAC signature of a webhook payload.
 * @param {string} body - Raw request body
 * @param {string} signature - The x-signature header value
 * @returns {boolean}
 */
function verifySignature(body, signature) {
  if (!signature || !config.clickup.webhookSecret) return false;

  const expected = crypto
    .createHmac("sha256", config.clickup.webhookSecret)
    .update(body)
    .digest("hex");

  return crypto.timingSafeEqual(
    Buffer.from(signature, "hex"),
    Buffer.from(expected, "hex")
  );
}
