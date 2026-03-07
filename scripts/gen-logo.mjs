#!/usr/bin/env node

/**
 * GinStudio Skills Logo Generator
 *
 * Generates a logo icon for the landing page.
 * Output: landing/logo.png
 */

import { join, dirname } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, "..")
const LIB = join(ROOT, "skills", "ai-asset-generator", "lib")

const { loadEnv } = await import(join(LIB, "env.mjs"))
const { createTask, pollUntilDone, downloadFile, log, outputDir } = await import(join(LIB, "kie-client.mjs"))

const OUTPUT_DIR = process.env.OUTPUT_DIR || outputDir("logo")

const ASSETS = [
  {
    name: "logo",
    filename: "logo.png",
    aspect_ratio: "1:1",
    resolution: "1K",
    prompt: [
      "A modern, minimal logo icon for a developer tool called 'GinStudio Skills'.",
      "The icon is the letter 'G' stylized inside a rounded square with 20% corner radius.",
      "The 'G' is bold, geometric, clean sans-serif style, white color (#FFFFFF).",
      "The rounded square background is a smooth gradient from emerald green (#16A34A) to teal (#0D9488).",
      "The design is flat, minimal, no shadows, no 3D effects, no textures.",
      "Pure vector-like appearance, centered composition, on a transparent or pure white background.",
      "Professional, modern, Silicon Valley tech startup aesthetic.",
      "No text other than the letter G, no additional elements, no decorations.",
      "Style: flat vector logo, app icon, minimal, clean.",
    ].join(" "),
  },
]

async function main() {
  await loadEnv()
  if (!process.env.KIE_AI_API_KEY) {
    console.error("Error: KIE_AI_API_KEY not found.")
    process.exit(1)
  }

  for (const asset of ASSETS) {
    log(`Generating ${asset.name}...`)
    const taskId = await createTask({
      model: "nano-banana-pro",
      input: {
        prompt: asset.prompt,
        aspect_ratio: asset.aspect_ratio,
        resolution: asset.resolution,
        output_format: "png",
      },
    })

    const url = await pollUntilDone(taskId, asset.name)
    await downloadFile(url, join(OUTPUT_DIR, asset.filename))
    log(`Saved ${asset.filename}`)
  }
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`)
  process.exit(1)
})
