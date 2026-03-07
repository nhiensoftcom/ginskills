---
name: ai-asset-generator
description: |
  **AI Asset Generator**: Generate production-ready images, icons, videos, and visual assets using KIE AI and background removal APIs. Handles text-to-image, image-to-image, image-to-video, background removal, and multi-size icon generation.
  - MANDATORY TRIGGERS: generate asset, generate image, create icon, generate illustration, create hero image, generate banner, app icon, brand assets, AI image, generate visual, asset pipeline, remove background, generate video, KIE AI, create artwork, generate graphics, app assets, mobile assets, feature illustration
  - Use this skill whenever the user wants to create, generate, or produce any visual asset for their project. Also trigger when discussing image generation pipelines, brand asset creation, or background removal workflows, even if the user just says "make me an image" or "I need graphics for this feature".
---

# AI Asset Generator

Generate production-ready visual assets using the KIE AI image/video generation API and background removal APIs. This skill knows the API patterns, prompt engineering techniques, and output pipelines for asset generation.

## How It Works

The asset generation pipeline follows these phases:

1. **Define** — Describe what assets are needed (dimensions, style, brand colors)
2. **Generate** — Submit tasks to KIE AI API (`nano-banana-pro` model for images, `bytedance/v1-pro-image-to-video` for video)
3. **Post-process** — Background removal, resizing, format conversion (WebP)
4. **Deliver** — Save to the appropriate project directory

All scripts and libraries are in `skills/ai-asset-generator/`. The shared client library handles API communication, polling, and downloads.

## Quick Start

To generate assets, you need:
1. A `KIE_AI_API_KEY` in the project root `.env` file (see `.env.example`)
2. Node.js 18+ (uses native `fetch`)

Scaffold a new generator:
```bash
cd skills/ai-asset-generator
node scripts/scaffold-generator.mjs <name> --assets 3
```

Output is saved to `ai-asset-generator/output/<name>/` by default.
Override with `OUTPUT_DIR=/target/path node generate-<name>-assets.mjs`.

## Brand Guidelines

Define your project's brand guidelines before generating assets. Example structure:

### Primary Brand
- Primary Color: `#EC4899` (specify your brand's primary hex)
- Gradient: Define your brand gradient stops
- Accent colors for highlight/sparkle effects
- Aesthetic keywords: e.g., "Premium, minimalist, clean"

### Secondary Brand / Sub-products
- Define separate color palettes for sub-products if applicable
- Keep consistent aesthetic language across products

### Common Accent Colors
- Blue `#3B82F6`, Green `#22C55E`, Purple `#8B5CF6`, Amber `#F59E0B`

## API Reference

Read the full API docs in the `docs/` directory when you need exact parameter details:

- `docs/gen-image.md` — KIE AI image generation (text-to-image, image-to-image)
- `docs/genvideo.md` — KIE AI video generation (image-to-video via ByteDance model)
- `docs/remove-background.md` — Background removal API

### Image Generation (KIE AI)

**Endpoint:** `POST https://api.kie.ai/api/v1/jobs/createTask`

Key parameters:
- `model`: `"nano-banana-pro"` (primary image model)
- `input.prompt`: Detailed description (max 20,000 chars). Be very specific about colors using hex codes, composition, lighting, and what to exclude.
- `input.aspect_ratio`: `1:1`, `2:3`, `3:2`, `3:4`, `4:3`, `4:5`, `5:4`, `9:16`, `16:9`, `21:9`, `auto`
- `input.resolution`: `1K`, `2K`, `4K`
- `input.output_format`: `png` or `jpg`
- `input.image_input`: Array of up to 8 image URLs for image-to-image transforms

**Polling:** `GET https://api.kie.ai/api/v1/jobs/recordInfo?taskId=<id>`
- States: `waiting` → `queuing` → `generating` → `success` | `fail`
- Use exponential backoff: start at 5s, multiply by 1.5, cap at 30s
- Timeout: 300s for images, 600s for video

### Video Generation (ByteDance via KIE AI)

Same endpoint, different model:
- `model`: `"bytedance/v1-pro-image-to-video"`
- `input.image_url`: Source image URL (required)
- `input.prompt`: Motion/camera description
- `input.resolution`: `480p`, `720p`, `1080p`
- `input.duration`: `"5"` or `"10"` (seconds)
- `input.camera_fixed`: `true`/`false`

### Background Removal

Configure your background removal endpoint in the `lib/bg-remove.mjs` library. Common options:
- Self-hosted or third-party background removal API
- Multipart form: `file` (image blob), `cropToForeground` (`true`/`false`), `outputFormat` (`png`)
- Auth: API key header
- Returns: Processed image (base64 or binary)

## Writing Generation Scripts

When creating a new asset generator script, follow the established pattern:

### Script Structure

```javascript
#!/usr/bin/env node

/**
 * [Feature Name] Asset Generator
 *
 * Purpose: [what it generates]
 * Brand: [relevant brand colors]
 *
 * Assets:
 *   1. [filename] - [description]
 *   2. [filename] - [description]
 */

import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { loadEnv } from "./lib/env.mjs";
import { createTask, pollUntilDone, downloadFile, log } from "./lib/kie-client.mjs";
import { removeBackground } from "./lib/bg-remove.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_DIR = join(__dirname, "<target-output-directory>");

// Define assets as a declarative array
const IMAGE_ASSETS = [
  {
    name: "asset-name",
    filename: "asset-name.png",
    aspect_ratio: "16:9",  // or 1:1, 9:16, etc.
    resolution: "2K",       // 1K, 2K, or 4K
    removeBg: false,        // true to run background removal after
    prompt: [
      // Break prompt into logical lines for readability
      "Main subject description with specific hex colors.",
      "Composition and layout details.",
      "Lighting and atmosphere.",
      "Style reference (photorealistic, 3D render, illustration, etc.).",
      "Exclusions: No text, no typography, no logos, no people, no watermarks.",
    ].join(" "),
  },
];

async function main() {
  await loadEnv();
  if (!process.env.KIE_AI_API_KEY) {
    console.error("Error: KIE_AI_API_KEY not found. Check .env");
    process.exit(1);
  }

  // Phase 1: Submit all tasks in parallel
  const jobs = await Promise.all(
    IMAGE_ASSETS.map(async (asset) => {
      const taskId = await createTask({
        model: "nano-banana-pro",
        input: {
          prompt: asset.prompt,
          aspect_ratio: asset.aspect_ratio,
          resolution: asset.resolution,
          output_format: "png",
        },
      });
      return { ...asset, taskId };
    })
  );

  // Phase 2: Poll all tasks in parallel
  const results = await Promise.all(
    jobs.map(async (job) => {
      const url = await pollUntilDone(job.taskId, job.name);
      return { ...job, resultUrl: url };
    })
  );

  // Phase 3: Download
  for (const r of results) {
    await downloadFile(r.resultUrl, join(OUTPUT_DIR, r.filename));
  }

  // Phase 4: Background removal (where needed)
  for (const r of results.filter(r => r.removeBg)) {
    try {
      const src = join(OUTPUT_DIR, r.filename);
      const dest = join(OUTPUT_DIR, r.filename.replace(".png", "-nobg.png"));
      await removeBackground(src, dest);
    } catch (err) {
      log(`  [warn] BG removal failed for ${r.name}: ${err.message}`);
    }
  }
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`);
  process.exit(1);
});
```

### Prompt Engineering Tips

The KIE AI model responds well to these patterns:

1. **Be explicit about colors** — Always include hex codes: "rose-gold (#EC4899)" not just "pink"
2. **Specify what to exclude** — Always end with: "No text, no typography, no logos, no people, no watermarks."
3. **Use photography/cinema terminology** — "three-point lighting", "soft bokeh", "shallow depth of field", "studio lighting"
4. **State the render style** — "Photorealistic 3D render", "flat illustration", "watercolor style"
5. **Describe composition** — "centered on pure white background", "left-aligned with negative space on right"
6. **Keep prompts focused** — One clear concept per asset. Multi-concept prompts produce confused results.

### Multi-Size Icon Pipeline

For app icons that need multiple sizes, add resize steps after generation:

1. Generate one high-res master image (1K, 1:1)
2. Remove background (optional)
3. Resize using `ffmpeg`:
   ```bash
   ffmpeg -i input.png -vf scale=48:48 -y output@2x.png
   ffmpeg -i input.png -vf scale=48:48 -y output@2x.webp
   ```

## Shared Libraries

All in `lib/`:

| File | Exports | Purpose |
|------|---------|---------|
| `kie-client.mjs` | `createTask`, `queryTask`, `pollUntilDone`, `downloadFile`, `outputDir`, `sleep`, `log` | KIE AI API client with exponential backoff polling and default output dir |
| `bg-remove.mjs` | `removeBackground(inputPath, outputPath)` | Background removal API client |
| `env.mjs` | `loadEnv()` | Loads `.env` and `.env.local` from project root |

## Output

Default output: `skills/ai-asset-generator/output/<name>/`

```
output/
  ├── logo/          ← outputDir("logo")
  ├── onboarding/    ← outputDir("onboarding")
  └── ...
```

Override per-run: `OUTPUT_DIR=/path/to/target node generate-xxx.mjs`

The `output/` directory is gitignored. Copy generated assets to your project as needed.
