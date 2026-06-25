import config from "../config.js";

/**
 * Send a prompt to the OpenClaw agent and return the response.
 *
 * Uses the OpenResponses-compatible POST /v1/responses endpoint.
 *
 * @param {string} prompt - The task description / prompt to send to the agent
 * @param {Object} [metadata] - Optional metadata (task_id, task_name, etc.)
 * @returns {Promise<string>} The agent's text response
 */
export async function runAgent(prompt, metadata = {}) {
  const url = `${config.openclaw.url}/v1/responses`;

  // Build the request body per OpenResponses spec
  const requestBody = {
    model: config.openclaw.agentId,
    input: prompt,
  };

  // Attach metadata as instructions context if provided
  if (metadata.taskId || metadata.taskName) {
    requestBody.instructions = [
      `Task ID: ${metadata.taskId || "unknown"}`,
      `Task Name: ${metadata.taskName || "unknown"}`,
      `Source: ClickUp Agent Bridge`,
      `Please process this task and provide a complete response.`,
    ].join("\n");
  }

  console.log(
    `[OpenClaw] Sending prompt to agent "${config.openclaw.agentId}"...`
  );
  console.log(
    `[OpenClaw] Prompt preview: ${prompt.substring(0, 200)}${prompt.length > 200 ? "..." : ""}`
  );

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.openclaw.apiToken}`,
    },
    body: JSON.stringify(requestBody),
    // Allow longer timeout for agent processing (5 minutes)
    signal: AbortSignal.timeout(5 * 60 * 1000),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(
      `OpenClaw API error [${response.status}]: ${errorBody}`
    );
  }

  const data = await response.json();

  // Extract the text response from the OpenResponses format
  // The response format has an "output" array with message items
  let agentResponse = "";

  if (data.output && Array.isArray(data.output)) {
    // OpenResponses format: output is an array of content items
    for (const item of data.output) {
      if (item.type === "message" && item.content) {
        for (const content of item.content) {
          if (content.type === "output_text" || content.type === "text") {
            agentResponse += content.text + "\n";
          }
        }
      }
    }
  } else if (data.output_text) {
    // Simplified format
    agentResponse = data.output_text;
  } else if (typeof data.output === "string") {
    agentResponse = data.output;
  } else if (data.choices && data.choices[0]) {
    // OpenAI-compatible fallback
    agentResponse =
      data.choices[0].message?.content || data.choices[0].text || "";
  } else {
    // Last resort: stringify the whole response
    agentResponse = JSON.stringify(data, null, 2);
  }

  console.log(
    `[OpenClaw] Received response (${agentResponse.length} chars)`
  );
  return agentResponse.trim();
}

/**
 * Health check for the OpenClaw instance.
 * @returns {Promise<boolean>} true if reachable
 */
export async function healthCheck() {
  try {
    const response = await fetch(`${config.openclaw.url}/health`, {
      headers: {
        Authorization: `Bearer ${config.openclaw.apiToken}`,
      },
      signal: AbortSignal.timeout(10_000),
    });
    // Any status less than 500 (including 200, 401, 404) means the server is reachable and running
    return response.status < 500;
  } catch {
    return false;
  }
}
