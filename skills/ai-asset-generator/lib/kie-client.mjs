/**
 * Shared KIE AI API client.
 *
 * Provides: createTask, queryTask, pollUntilDone, downloadFile
 * All scripts use the same API base and auth pattern.
 */

import { writeFile, mkdir } from "fs/promises";
import { existsSync } from "fs";
import { dirname } from "path";

// ─── Helpers ────────────────────────────────────────────────
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const log = (msg) => console.log(msg);

// ─── API Client ─────────────────────────────────────────────
const API = "https://api.kie.ai/api/v1/jobs";

function headers() {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${process.env.KIE_AI_API_KEY}`,
  };
}

export async function createTask(payload) {
  const res = await fetch(`${API}/createTask`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify(payload),
  });
  const json = await res.json();
  if (json.code !== 200) {
    throw new Error(`createTask failed (${json.code}): ${json.message}`);
  }
  return json.data.taskId;
}

export async function queryTask(taskId) {
  const res = await fetch(`${API}/recordInfo?taskId=${taskId}`, {
    headers: { Authorization: `Bearer ${process.env.KIE_AI_API_KEY}` },
  });
  const json = await res.json();
  if (json.code !== 200) {
    throw new Error(`queryTask failed (${json.code}): ${json.message}`);
  }
  return json.data;
}

/**
 * Poll a task until it reaches success/fail.
 * Uses increasing delay: 5s → 8s → 12s → … capped at 30s.
 */
export async function pollUntilDone(taskId, label, timeoutMs = 300_000) {
  const t0 = Date.now();
  let delay = 5_000;

  while (Date.now() - t0 < timeoutMs) {
    const task = await queryTask(taskId);

    if (task.state === "success") {
      const urls = JSON.parse(task.resultJson).resultUrls;
      log(`  [done] ${label}`);
      return urls[0];
    }

    if (task.state === "fail") {
      throw new Error(`${label} failed: ${task.failMsg || "unknown"}`);
    }

    const elapsed = Math.round((Date.now() - t0) / 1000);
    log(`  [${task.state}] ${label}  (${elapsed}s, next poll in ${Math.round(delay / 1000)}s)`);
    await sleep(delay);
    delay = Math.min(Math.round(delay * 1.5), 30_000);
  }

  throw new Error(`${label} timed out after ${timeoutMs / 1000}s`);
}

export async function downloadFile(url, dest) {
  const dir = dirname(dest);
  if (!existsSync(dir)) await mkdir(dir, { recursive: true });
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download failed: ${res.status} ${url}`);
  const buf = Buffer.from(await res.arrayBuffer());
  await writeFile(dest, buf);
  log(`  [saved] ${dest}`);
}
