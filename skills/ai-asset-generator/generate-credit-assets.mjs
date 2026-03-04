#!/usr/bin/env node

/**
 * Credit Feature Asset Generator
 *
 * Generates hero illustrations for the Earn Credits screen
 * using the KIE AI API (nano-banana-pro).
 *
 * Assets:
 *   1. earn-hero.png   - Main hero background for the earn credits screen
 *   2. coin-reward.png - Sty coin/reward illustration (transparent bg)
 *   3. streak-fire.png - Daily streak fire illustration (transparent bg)
 *
 * Brand palette:
 *   Rose #EC4899 primary, #FFF1F3 → #FFE4E9 → #FECDD6 → #FDA4B8 gradient
 *   Task colors: Blue #3B82F6, Green #22C55E, Purple #8B5CF6, Amber #F59E0B
 *
 * Usage:
 *   node tools/generate-credit-assets.mjs
 */

import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { loadEnv } from "./lib/env.mjs";
import { createTask, pollUntilDone, downloadFile, log } from "./lib/kie-client.mjs";
import { removeBackground } from "./lib/bg-remove.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_DIR = join(__dirname, "..", "styai-mobile", "src", "assets", "images", "credits");

// ─── Asset Definitions ──────────────────────────────────────
const IMAGE_ASSETS = [
  {
    name: "earn-hero",
    filename: "earn-hero.png",
    aspect_ratio: "16:9",
    resolution: "2K",
    removeBg: false,
    prompt: [
      "Abstract soft blurred background banner for a mobile app card header.",
      "Smooth dreamy gradient from blush pink (#FFF1F3) on left to rose (#FECDD6) center to mauve pink (#FDA4B8) on right.",
      "Scattered soft bokeh circles in light rose and white, gentle and out of focus.",
      "A few tiny sparkle dots in rose-gold tones, very subtle and sparse.",
      "Soft diagonal light streak from top-left, warm and diffused.",
      "The overall feel is premium, feminine, airy, like a luxury fashion brand background.",
      "No objects, no coins, no icons, no shapes in focus. Just an abstract atmospheric background.",
      "Very clean and minimal, suitable for overlaying text and icons on top.",
      "Ultra smooth gradients, no harsh edges, dreamlike soft-focus photography style.",
      "No text, no typography, no logos, no people, no watermarks, no UI elements.",
    ].join(" "),
  },
  {
    name: "coin-reward",
    filename: "coin-reward.png",
    aspect_ratio: "1:1",
    resolution: "1K",
    removeBg: true,
    prompt: [
      "Premium 3D render of a single stylish reward coin, centered on pure white background.",
      "The coin is polished rose-gold (#EC4899) with luxurious metallic sheen and soft reflections.",
      "On the coin face: a clean minimalist 5-pointed star, embossed with soft beveled edges.",
      "The coin has a refined thin rim with subtle ridge detailing, like a luxury medallion.",
      "Slight 15-degree tilt showing the coin's thickness and 3D depth.",
      "Warm ambient glow radiating behind: rose-pink (#FDA4B8) halo with soft falloff.",
      "4-5 tiny sparkle particles floating around the coin in blush and champagne gold.",
      "One small light streak crossing the coin surface for premium shine effect.",
      "Clean white background, professional studio three-point lighting, razor sharp focus.",
      "Photorealistic 3D render, luxury product photography, fashion accessory aesthetic.",
      "No text, no typography, no logos, no people, no watermarks.",
    ].join(" "),
  },
  {
    name: "streak-fire",
    filename: "streak-fire.png",
    aspect_ratio: "1:1",
    resolution: "1K",
    removeBg: true,
    prompt: [
      "Premium 3D render of a stylized flame icon, centered on pure white background.",
      "The flame is elegant and fashion-forward, made of gradient from rose (#EC4899)",
      "at base to coral (#F87198) mid to warm pink (#FDA4B8) at tip.",
      "Smooth glossy surface with a gentle metallic sheen, like a luxury enamel brooch.",
      "The flame shape is clean, stylized, and slightly abstract — not realistic fire.",
      "Two inner flicker shapes inside the flame in lighter rose tones for depth.",
      "Subtle warm glow at the base, blush (#FFE4E9) ambient light spreading outward.",
      "3-4 tiny sparkle particles in rose and gold tones floating near the tip.",
      "Clean white background, professional studio lighting, ultra sharp focus.",
      "Photorealistic 3D render, luxury product photography style.",
      "No text, no typography, no logos, no people, no watermarks.",
      "Fashion-forward, premium gamification aesthetic, celebratory feel.",
    ].join(" "),
  },
];

// ─── Main ───────────────────────────────────────────────────
async function main() {
  await loadEnv();

  if (!process.env.KIE_AI_API_KEY) {
    console.error("Error: KIE_AI_API_KEY not found. Check .env");
    process.exit(1);
  }

  console.log("\n========================================");
  console.log("  Credit Feature Asset Generator");
  console.log("  Brand: Rose #EC4899 | Sty AI");
  console.log("========================================\n");

  // Phase 1: Submit all tasks
  log("--- Phase 1: Submitting image tasks ---\n");

  const jobs = await Promise.all(
    IMAGE_ASSETS.map(async (asset) => {
      log(`  [submit] ${asset.name}  (${asset.aspect_ratio} ${asset.resolution})`);
      const taskId = await createTask({
        model: "nano-banana-pro",
        input: {
          prompt: asset.prompt,
          aspect_ratio: asset.aspect_ratio,
          resolution: asset.resolution,
          output_format: "png",
        },
      });
      log(`  [queued] ${asset.name}  taskId=${taskId}`);
      return { ...asset, taskId };
    })
  );

  // Phase 2: Poll all tasks
  log(`\n--- Phase 2: Polling ${jobs.length} image tasks ---\n`);

  const results = await Promise.all(
    jobs.map(async (job) => {
      const url = await pollUntilDone(job.taskId, job.name);
      return { ...job, resultUrl: url };
    })
  );

  // Phase 3: Download images
  log("\n--- Phase 3: Downloading images ---\n");

  for (const r of results) {
    const dest = join(OUTPUT_DIR, r.filename);
    await downloadFile(r.resultUrl, dest);
  }

  // Phase 4: Remove backgrounds where needed
  const bgRemoveJobs = results.filter((r) => r.removeBg);
  if (bgRemoveJobs.length > 0) {
    log("\n--- Phase 4: Removing backgrounds ---\n");
    for (const r of bgRemoveJobs) {
      const src = join(OUTPUT_DIR, r.filename);
      const noBgName = r.filename.replace(".png", "-nobg.png");
      const dest = join(OUTPUT_DIR, noBgName);
      try {
        await removeBackground(src, dest);
      } catch (err) {
        log(`  [warn] Background removal failed for ${r.name}: ${err.message}`);
        log(`  [skip] Keeping original ${r.filename}`);
      }
    }
  }

  console.log("\n========================================");
  console.log("  All done!");
  console.log("========================================");
  console.log(`\nGenerated assets in ${OUTPUT_DIR}:`);
  for (const r of results) {
    console.log(`  - ${r.filename}  (${r.name})`);
    if (r.removeBg) {
      console.log(`  - ${r.filename.replace(".png", "-nobg.png")}  (${r.name} no bg)`);
    }
  }
  console.log("");
}

main().catch((err) => {
  console.error(`\nFatal: ${err.message}`);
  process.exit(1);
});
