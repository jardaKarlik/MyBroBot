import config from "../config.js";

const CLICKUP_API_BASE = "https://api.clickup.com/api/v2";

/**
 * Make an authenticated request to the ClickUp API.
 */
async function clickupFetch(path, options = {}) {
  const url = `${CLICKUP_API_BASE}${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      Authorization: config.clickup.apiToken,
      "Content-Type": "application/json",
      ...options.headers,
    },
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(
      `ClickUp API error [${response.status}] ${path}: ${errorBody}`
    );
  }

  return response.json();
}

/**
 * Get full task details including description.
 * @param {string} taskId - The ClickUp task ID
 * @returns {Promise<Object>} Task object with name, description, status, etc.
 */
export async function getTask(taskId) {
  return clickupFetch(`/task/${taskId}`);
}

/**
 * Update the status of a task.
 * @param {string} taskId - The ClickUp task ID
 * @param {string} status - The new status string
 */
export async function updateTaskStatus(taskId, status) {
  return clickupFetch(`/task/${taskId}`, {
    method: "PUT",
    body: JSON.stringify({ status }),
  });
}

/**
 * Add a comment to a task.
 * @param {string} taskId - The ClickUp task ID
 * @param {string} commentText - The comment body (supports markdown)
 * @param {boolean} [notifyAll=false] - Whether to notify all assignees
 */
export async function addComment(taskId, commentText, notifyAll = false) {
  return clickupFetch(`/task/${taskId}/comment`, {
    method: "POST",
    body: JSON.stringify({
      comment_text: commentText,
      notify_all: notifyAll,
    }),
  });
}

/**
 * Create a webhook for a workspace.
 * @param {string} workspaceId - The workspace ID
 * @param {string} endpoint - The callback URL
 * @param {string[]} events - Array of event names to subscribe to
 * @param {string} [secret] - Optional HMAC secret
 */
export async function createWebhook(workspaceId, endpoint, events, secret) {
  const body = { endpoint, events };
  if (secret) body.secret = secret;

  return clickupFetch(`/team/${workspaceId}/webhook`, {
    method: "POST",
    body: JSON.stringify(body),
  });
}

/**
 * List all webhooks for a workspace.
 * @param {string} workspaceId - The workspace ID
 */
export async function listWebhooks(workspaceId) {
  return clickupFetch(`/team/${workspaceId}/webhook`);
}

/**
 * Get the accessible workspaces.
 */
export async function getWorkspaces() {
  return clickupFetch("/team");
}

/**
 * Get lists in a space (for discovering list IDs).
 * @param {string} spaceId - The space ID
 */
export async function getListsInSpace(spaceId) {
  return clickupFetch(`/space/${spaceId}/list`);
}
