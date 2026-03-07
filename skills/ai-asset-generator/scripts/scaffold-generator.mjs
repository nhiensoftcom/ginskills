#!/usr/bin/env node

/**
 * Asset Generator Scaffold
 *
 * Creates a new generation script from a template with the proper
 * project structure, imports, and pipeline phases.
 *
 * Usage:
 *   node scripts/scaffold-generator.mjs <name> [--assets <count>]
 *
 * Example:
 *   node scripts/scaffold-generator.mjs onboarding --assets 3
 *   → Creates generate-onboarding-assets.mjs
 */

import { writeFile, access } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");

const name = process.argv[2];
const assetCount = parseInt(process.argv.find((a, i) => process.argv[i - 1] === "--assets") || "2");

if (!name) {
  console.log(`
  Usage: node scripts/scaffold-generator.mjs <name> [--assets <count>]

  Examples:
    node scripts/scaffold-generator.mjs onboarding --assets 3
    node scripts/scaffold-generator.mjs referral-icon --assets 1

  This creates a new generate-<name>-assets.mjs file with:
    - Proper imports from lib/
    - Asset definition array
    - 4-phase pipeline (submit → poll → download → bg-remove)
    - Brand color placeholders
  `);
  process.exit(0);
}

const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
const filename = `generate-${slug}-assets.mjs`;
const filepath = join(ROOT, filename);

// Check if file already exists
try {
  await access(filepath);
  console.error(`  [error] ${filename} already exists. Pick a different name or delete it first.`);
  process.exit(1);
} catch {
  // File doesn't exist — good
}

// Generate asset placeholders
const assets = Array.from({ length: assetCount }, (_, i) => {
  const num = i + 1;
  return `  {
    name: "asset-${num}",
    filename: "asset-${num}.png",
    aspect_ratio: "${i === 0 ? "16:9" : "1:1"}",
    resolution: "${i === 0 ? "2K" : "1K"}",
    removeBg: ${i > 0},
    prompt: [
      // TODO: Write a detailed prompt for asset ${num}
      // Tips:
      //   - Include specific hex colors: "rose-gold (#EC4899)"
      //   - Describe composition: "centered on pure white background"
      //   - Specify render style: "Photorealistic 3D render"
      //   - Always end with exclusions:
      "No text, no typography, no logos, no people, no watermarks.",
    ].join(" "),
  }`;
}).join(",\n");

const template = `#!/usr/bin/env node

/**
 * ${name.charAt(0).toUpperCase() + name.slice(1)} Asset Generator
 *
 * Generates assets for the ${name} feature using KIE AI API.
 *
 * Brand palette:
 *   TODO: Fill in brand colors
 *   Primary: #EC4899 (Rose)
 *   Gradient: #FFF1F3 → #FFE4E9 → #FECDD6 → #FDA4B8
 *
 * Assets:
 * ${Array.from({ length: assetCount }, (_, i) => `*   ${i + 1}. asset-${i + 1}.png — TODO: describe`).join("\n ")}
 *
 * Usage:
 *   node ${filename}
 */

import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { loadEnv } from "./lib/env.mjs";
import { createTask, pollUntilDone, downloadFile, log, outputDir } from "./lib/kie-client.mjs";
import { removeBackground } from "./lib/bg-remove.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Default: ai-asset-generator/output/${slug}/
// Override: OUTPUT_DIR=/other/path node ${filename}
const OUTPUT_DIR = process.env.OUTPUT_DIR || outputDir("${slug}");

// ─── Asset Definitions ──────────────────────────────────────
const IMAGE_ASSETS = [
${assets}
];

// ─── Main ───────────────────────────────────────────────────
async function main() {
  await loadEnv();

  if (!process.env.KIE_AI_API_KEY) {
    console.error("Error: KIE_AI_API_KEY not found. Check .env");
    process.exit(1);
  }

  console.log("\\n========================================");
  console.log("  ${name.charAt(0).toUpperCase() + name.slice(1)} Asset Generator");
  console.log("========================================\\n");

  // Phase 1: Submit all tasks in parallel
  log("--- Phase 1: Submitting image tasks ---\\n");

  const jobs = await Promise.all(
    IMAGE_ASSETS.map(async (asset) => {
      log(\`  [submit] \${asset.name}  (\${asset.aspect_ratio} \${asset.resolution})\`);
      const taskId = await createTask({
        model: "nano-banana-pro",
        input: {
          prompt: asset.prompt,
          aspect_ratio: asset.aspect_ratio,
          resolution: asset.resolution,
          output_format: "png",
        },
      });
      log(\`  [queued] \${asset.name}  taskId=\${taskId}\`);
      return { ...asset, taskId };
    })
  );

  // Phase 2: Poll all tasks in parallel
  log(\`\\n--- Phase 2: Polling \${jobs.length} image tasks ---\\n\`);

  const results = await Promise.all(
    jobs.map(async (job) => {
      const url = await pollUntilDone(job.taskId, job.name);
      return { ...job, resultUrl: url };
    })
  );

  // Phase 3: Download images
  log("\\n--- Phase 3: Downloading images ---\\n");

  for (const r of results) {
    const dest = join(OUTPUT_DIR, r.filename);
    await downloadFile(r.resultUrl, dest);
  }

  // Phase 4: Remove backgrounds where needed
  const bgRemoveJobs = results.filter((r) => r.removeBg);
  if (bgRemoveJobs.length > 0) {
    log("\\n--- Phase 4: Removing backgrounds ---\\n");
    for (const r of bgRemoveJobs) {
      const src = join(OUTPUT_DIR, r.filename);
      const noBgName = r.filename.replace(".png", "-nobg.png");
      const dest = join(OUTPUT_DIR, noBgName);
      try {
        await removeBackground(src, dest);
      } catch (err) {
        log(\`  [warn] Background removal failed for \${r.name}: \${err.message}\`);
        log(\`  [skip] Keeping original \${r.filename}\`);
      }
    }
  }

  console.log("\\n========================================");
  console.log("  All done!");
  console.log("========================================");
  console.log(\`\\nGenerated assets in \${OUTPUT_DIR}:\`);
  for (const r of results) {
    console.log(\`  - \${r.filename}  (\${r.name})\`);
    if (r.removeBg) {
      console.log(\`  - \${r.filename.replace(".png", "-nobg.png")}  (\${r.name} no bg)\`);
    }
  }
  console.log("");
}

main().catch((err) => {
  console.error(\`\\nFatal: \${err.message}\`);
  process.exit(1);
});
`;

await writeFile(filepath, template);
console.log(`  [created] ${filename}`);
console.log(`  [info]    ${assetCount} asset placeholder(s) ready`);
console.log(`  [next]    Edit the prompts and OUTPUT_DIR, then run: node ${filename}`);
