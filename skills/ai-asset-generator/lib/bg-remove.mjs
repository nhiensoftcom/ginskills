/**
 * Shared background removal via Sty AI API.
 */

import { writeFile, readFile } from "fs/promises";
import { resolve, dirname, join } from "path";
import { fileURLToPath } from "url";
import { log } from "./kie-client.mjs";

const __lib = dirname(fileURLToPath(import.meta.url));
const OUTPUT_BASE = resolve(join(__lib, "..", "output"));

function assertSafePath(p, base) {
  const resolved = resolve(p);
  if (!resolved.startsWith(base)) {
    throw new Error(`Path traversal blocked: ${p} escapes ${base}`);
  }
  return resolved;
}

export async function removeBackground(inputPath, outputPath) {
  const safeOutput = assertSafePath(outputPath, OUTPUT_BASE);

  const apiKey = process.env.STY_AI_API_KEY;
  if (!apiKey) {
    throw new Error("STY_AI_API_KEY environment variable is not set");
  }

  const fileBuffer = await readFile(inputPath);
  const blob = new Blob([fileBuffer], { type: "image/png" });

  const formData = new FormData();
  formData.append("file", blob, "image.png");
  formData.append("cropToForeground", "true");
  formData.append("outputFormat", "png");

  const res = await fetch("https://api.styai.app/api/v1/media/remove-background", {
    method: "POST",
    headers: {
      accept: "application/json",
      "X-API-Key": apiKey,
    },
    body: formData,
  });

  const json = await res.json();
  if (!json.sucess && !json.success) {
    throw new Error("Background removal failed");
  }

  const buffer = Buffer.from(json.buffer, "base64");
  await writeFile(safeOutput, buffer);
  log(`  [bg-removed] ${safeOutput}`);
}
