/**
 * Shared background removal via Sty AI API.
 */

import { writeFile, readFile } from "fs/promises";
import { log } from "./kie-client.mjs";

export async function removeBackground(inputPath, outputPath) {
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
      "X-API-Key": "REDACTED_STY_AI_API_KEY",
    },
    body: formData,
  });

  const json = await res.json();
  if (!json.sucess && !json.success) {
    throw new Error("Background removal failed");
  }

  const buffer = Buffer.from(json.buffer, "base64");
  await writeFile(outputPath, buffer);
  log(`  [bg-removed] ${outputPath}`);
}
