#!/usr/bin/env node

/**
 * Sty Credit Icon Generator
 *
 * Generates ONE unified credit/coin icon for the entire app.
 * This icon replaces the inconsistent SVG StyIcon + coin-reward.png.
 *
 * Pipeline:
 *   1. Generate via KIE AI API (nano-banana-pro)
 *   2. Remove background via Sty AI API
 *   3. Convert to WebP via ffmpeg (lightweight)
 *   4. Output multiple sizes: @1x (24px), @2x (48px), @3x (72px), hero (160px)
 *
 * Usage:
 *   node tools/generate-sty-icon.mjs
 */

import { writeFile, readFile } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";
import { loadEnv } from "./lib/env.mjs";
import { createTask, pollUntilDone, downloadFile, log } from "./lib/kie-client.mjs";
import { removeBackground } from "./lib/bg-remove.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_DIR = join(__dirname, "..", "styai-mobile", "src", "assets", "images", "credits");

// ─── ffmpeg helpers ─────────────────────────────────────────
function hasFFmpeg() {
  try { execSync("which ffmpeg", { stdio: "pipe" }); return true; } catch { return false; }
}

function ffmpegResize(input, output, size) {
  execSync(`ffmpeg -y -i "${input}" -vf "scale=${size}:${size}:flags=lanczos" "${output}"`, { stdio: "pipe" });
  log(`  [resized] ${output} (${size}x${size})`);
}

function ffmpegToWebP(input, output) {
  try {
    execSync(`ffmpeg -y -i "${input}" -c:v libwebp -quality 90 -lossless 0 "${output}"`, { stdio: "pipe" });
    log(`  [webp] ${output}`);
  } catch {
    log(`  [skip] WebP not available, keeping PNG: ${input}`);
  }
}

// ─── Main ───────────────────────────────────────────────────
async function main() {
  await loadEnv();

  if (!process.env.KIE_AI_API_KEY) {
    console.error("Error: KIE_AI_API_KEY not found. Check .env");
    process.exit(1);
  }

  const useFFmpeg = hasFFmpeg();
  if (!useFFmpeg) {
    log("[warn] ffmpeg not found — skipping resize and WebP conversion");
    log("[warn] Install with: brew install ffmpeg");
  }

  console.log("\n========================================");
  console.log("  Sty Credit Icon Generator");
  console.log("  One icon to rule them all");
  console.log("========================================\n");

  // ─── Phase 1: Generate high-res icon ──────────────────────
  const prompt = [
    "A single flat coin icon on a solid pure white #FFFFFF background, centered, no shadows on background.",
    "The coin is a perfect circle, viewed straight-on (flat, no tilt, no perspective).",
    "Coin color: vibrant rose-pink gradient from #EC4899 to #DB2777, smooth metallic finish.",
    "On the coin face: a bold clean letter S in white, centered, modern sans-serif font, slightly embossed.",
    "The coin has a thin clean rim, slightly lighter rose-pink #F87198.",
    "One subtle diagonal highlight across the coin for a polished metallic look.",
    "NO particles, NO sparkles, NO glow, NO halo, NO floating elements around the coin.",
    "NO shadows on the background. The coin edges must be crisp and clean against the white background.",
    "Solid pure white background only. Clean, minimal, flat icon style.",
    "High quality digital illustration, app icon style, crisp vector-like rendering.",
    "No text besides the S. No watermarks, no people, no extra elements.",
  ].join(" ");

  log("--- Phase 1: Generating high-res coin icon ---\n");
  log("  [submit] sty-coin  (1:1 2K)");

  const taskId = await createTask({
    model: "nano-banana-pro",
    input: {
      prompt,
      aspect_ratio: "1:1",
      resolution: "2K",
      output_format: "png",
    },
  });

  log(`  [queued] sty-coin  taskId=${taskId}`);
  log("\n--- Phase 2: Polling ---\n");

  const resultUrl = await pollUntilDone(taskId, "sty-coin");

  // ─── Phase 3: Download ────────────────────────────────────
  log("\n--- Phase 3: Downloading ---\n");
  const rawPath = join(OUTPUT_DIR, "sty-coin-raw.png");
  await downloadFile(resultUrl, rawPath);

  // ─── Phase 4: Remove background ──────────────────────────
  log("\n--- Phase 4: Removing background ---\n");
  const noBgPath = join(OUTPUT_DIR, "sty-coin.png");
  try {
    await removeBackground(rawPath, noBgPath);
  } catch (err) {
    log(`  [warn] Background removal failed: ${err.message}`);
    log("  [fallback] Using raw image as sty-coin.png");
    await writeFile(noBgPath, await readFile(rawPath));
  }

  // ─── Phase 5: Generate sizes + WebP via ffmpeg ────────────
  if (useFFmpeg) {
    log("\n--- Phase 5: Generating sizes + WebP ---\n");

    ffmpegResize(noBgPath, join(OUTPUT_DIR, "sty-coin-hero.png"), 160);
    ffmpegResize(noBgPath, join(OUTPUT_DIR, "sty-coin@3x.png"), 72);
    ffmpegResize(noBgPath, join(OUTPUT_DIR, "sty-coin@2x.png"), 48);

    // WebP versions for lightweight loading
    ffmpegToWebP(join(OUTPUT_DIR, "sty-coin-hero.png"), join(OUTPUT_DIR, "sty-coin-hero.webp"));
    ffmpegToWebP(join(OUTPUT_DIR, "sty-coin@3x.png"), join(OUTPUT_DIR, "sty-coin@3x.webp"));
  }

  console.log("\n========================================");
  console.log("  All done!");
  console.log("========================================");
  console.log(`\nGenerated in ${OUTPUT_DIR}:`);
  console.log("  - sty-coin.png        (full-res, transparent bg)");
  if (useFFmpeg) {
    console.log("  - sty-coin@2x.png     (48px)");
    console.log("  - sty-coin@3x.png     (72px)");
    console.log("  - sty-coin-hero.png   (160px, for hero section)");
    console.log("  - sty-coin-hero.webp  (160px, lightweight)");
    console.log("  - sty-coin@3x.webp    (72px, lightweight)");
  }
  console.log("");
}

main().catch((err) => {
  console.error(`\nFatal: ${err.message}`);
  process.exit(1);
});
