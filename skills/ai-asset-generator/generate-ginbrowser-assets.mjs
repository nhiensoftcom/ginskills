#!/usr/bin/env node

/**
 * GinBrowser Asset Generator
 *
 * Generates hero images, feature illustrations, and hero background video
 * using the KIE AI API (nano-banana-pro for images, bytedance for video).
 *
 * Usage:
 *   node tools/generate-ginbrowser-assets.mjs              # generate all
 *   node tools/generate-ginbrowser-assets.mjs --images     # images only
 *   node tools/generate-ginbrowser-assets.mjs --video <url> # video only
 */

import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { loadEnv } from "./lib/env.mjs";
import { createTask, pollUntilDone, downloadFile, log } from "./lib/kie-client.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const OUTPUT_DIR = join(ROOT, "public", "images");

// ─── Prompt Engineering ─────────────────────────────────────
const IMAGE_ASSETS = [
  {
    name: "hero-bg",
    filename: "hero-bg.png",
    aspect_ratio: "16:9",
    resolution: "2K",
    prompt: [
      "Cinematic ultra-wide establishing shot of a dark digital fortress environment.",
      "Pure black void (#0A0E1A) as the base.",
      "In the center, a massive translucent shield construct made of hexagonal grid panels",
      "glowing with soft emerald (#10B981) and cyan (#06B6D4) light,",
      "surrounded by orbiting data streams and encrypted packet visualizations.",
      "Thousands of tiny luminous particles form fingerprint-like patterns",
      "that dissolve into digital noise and scatter outward.",
      "Multiple browser window silhouettes float in the background,",
      "each with slightly different configurations, representing multiple identities.",
      "Soft volumetric emerald light radiates from behind the central shield.",
      "Center has ample dark negative space for UI overlay.",
      "Ultra high quality photorealistic 3D render with volumetric lighting and depth of field.",
      "Absolutely no text, no typography, no logos, no people, no UI elements, no watermarks.",
      "Dark moody atmosphere, premium cybersecurity aesthetic.",
    ].join(" "),
  },
  {
    name: "feature-fingerprint",
    filename: "feature-fingerprint.png",
    aspect_ratio: "1:1",
    resolution: "1K",
    prompt: [
      "Abstract premium technology illustration on a pure black background.",
      "A large translucent holographic fingerprint floating in dark space,",
      "constructed from glowing emerald (#10B981) digital circuit traces",
      "and fine data-stream lines with tiny pulsing encrypted nodes.",
      "The fingerprint gradually dissolves into scattered pixels and noise",
      "on the right side, symbolizing digital fingerprint masking.",
      "Tiny shield icons and lock symbols orbit around the fingerprint.",
      "Clean minimal composition with generous dark breathing room.",
      "Emerald and cyan accent lighting on pure black.",
      "Ultra high quality 3D render. Photorealistic volumetric light.",
      "No text, no typography, no logos, no people, no watermarks.",
      "Premium cybersecurity illustration style.",
    ].join(" "),
  },
  {
    name: "feature-profiles",
    filename: "feature-profiles.png",
    aspect_ratio: "1:1",
    resolution: "1K",
    prompt: [
      "Abstract premium technology illustration on a pure black background.",
      "Multiple floating translucent browser window shapes arranged in a fan formation,",
      "each glowing with different subtle color tints - emerald, cyan, blue, teal.",
      "Each browser window has a unique abstract avatar silhouette inside it.",
      "Thin luminous connection threads link the windows to a central hub node.",
      "The windows have frosted glass appearance with soft inner glow.",
      "Tiny data particles flow between the windows and the central node.",
      "Clean minimal composition with generous negative space.",
      "Emerald and teal accent colors on pure black.",
      "Ultra high quality 3D render. Photorealistic volumetric light.",
      "No text, no typography, no logos, no people, no watermarks.",
      "Premium multi-identity management illustration style.",
    ].join(" "),
  },
  {
    name: "feature-stealth",
    filename: "feature-stealth.png",
    aspect_ratio: "1:1",
    resolution: "1K",
    prompt: [
      "Abstract premium technology illustration on a pure black background.",
      "A crystalline transparent eye shape floating in dark space,",
      "constructed from hundreds of tiny emerald (#10B981) and cyan data points.",
      "The eye is crossed out by an elegant glowing slash line,",
      "symbolizing undetectable browsing and anti-tracking.",
      "Around the eye, scattered detection radar waves dissolve into noise.",
      "Faint grid lines recede into the background suggesting the web.",
      "Small shield fragments and pixel dust float around the composition.",
      "Clean minimal composition with generous negative space.",
      "Emerald and cyan accent colors on pure black.",
      "Ultra high quality 3D render. Photorealistic volumetric light.",
      "No text, no typography, no logos, no people, no watermarks.",
      "Premium anti-detection stealth illustration style.",
    ].join(" "),
  },
];

const VIDEO_PROMPT = [
  "Extremely slow, hypnotic forward camera drift through the scene.",
  "The hexagonal shield panels pulse gently with soft emerald bioluminescent light in slow waves.",
  "Fingerprint particle patterns continuously dissolve and reform in mesmerizing cycles.",
  "Translucent encrypted data streams shimmer and slowly orbit the central shield.",
  "Microscopic particles drift past the lens creating dreamy bokeh.",
  "Volumetric fog shifts almost imperceptibly in the background.",
  "Ultra smooth, meditative cinematic motion.",
  "No sudden movements, no flashes, no camera shake.",
  "Premium atmospheric cybersecurity ambience.",
].join(" ");

// ─── Main ───────────────────────────────────────────────────
async function generateImages() {
  log("\n--- Phase 1: Submitting image tasks ---\n");

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

  log(`\n--- Phase 2: Polling ${jobs.length} image tasks ---\n`);

  const results = await Promise.all(
    jobs.map(async (job) => {
      const url = await pollUntilDone(job.taskId, job.name);
      return { ...job, resultUrl: url };
    })
  );

  log("\n--- Phase 3: Downloading images ---\n");

  for (const r of results) {
    await downloadFile(r.resultUrl, join(OUTPUT_DIR, r.filename));
  }

  return results;
}

async function generateVideo(heroImageUrl) {
  log("\n--- Phase 4: Submitting video task ---\n");

  log(`  [submit] hero-bg-video  (720p 5s)`);
  log(`  [source] ${heroImageUrl}`);

  const taskId = await createTask({
    model: "bytedance/v1-pro-image-to-video",
    input: {
      prompt: VIDEO_PROMPT,
      image_url: heroImageUrl,
      resolution: "720p",
      duration: "5",
      camera_fixed: false,
      seed: -1,
      enable_safety_checker: true,
    },
  });

  log(`  [queued] hero-bg-video  taskId=${taskId}`);
  log("\n--- Phase 5: Polling video task (may take several minutes) ---\n");

  const videoUrl = await pollUntilDone(taskId, "hero-bg-video", 600_000);

  log("\n--- Phase 6: Downloading video ---\n");
  await downloadFile(videoUrl, join(OUTPUT_DIR, "hero-bg.mp4"));
}

async function main() {
  await loadEnv();

  if (!process.env.KIE_AI_API_KEY) {
    console.error("Error: KIE_AI_API_KEY not found. Check .env or .env.local");
    process.exit(1);
  }

  const args = process.argv.slice(2);
  const imagesOnly = args.includes("--images");
  const videoOnly = args.includes("--video");

  console.log("\n========================================");
  console.log("  GinBrowser Asset Generator");
  console.log("========================================");

  if (videoOnly) {
    const urlArg = args.find((a) => a.startsWith("http"));
    if (!urlArg) {
      console.error("Video-only mode requires a hero image URL argument.");
      console.error("Usage: node tools/generate-ginbrowser-assets.mjs --video <hero-image-url>");
      process.exit(1);
    }
    await generateVideo(urlArg);
  } else {
    const results = await generateImages();

    if (!imagesOnly) {
      const heroResult = results.find((r) => r.name === "hero-bg");
      if (heroResult?.resultUrl) {
        await generateVideo(heroResult.resultUrl);
      } else {
        log("\n  [skip] Video generation: hero-bg image not available");
      }
    }
  }

  console.log("\n========================================");
  console.log("  All done!");
  console.log("========================================");
  console.log("\nGenerated assets in public/images/:");
  console.log("  - hero-bg.png             (hero background)");
  console.log("  - hero-bg.mp4             (hero video)");
  console.log("  - feature-fingerprint.png (fingerprint masking)");
  console.log("  - feature-profiles.png    (multi-profile management)");
  console.log("  - feature-stealth.png     (stealth/anti-detection)");
  console.log("");
}

main().catch((err) => {
  console.error(`\nFatal: ${err.message}`);
  process.exit(1);
});
