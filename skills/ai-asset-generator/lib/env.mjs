/**
 * Shared .env loader for ai-asset-generator scripts.
 * Looks for .env in ai-asset-generator/ first, then workspace root.
 */

import { readFile } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const GENERATOR_DIR = join(__dirname, "..");
const ROOT = join(__dirname, "..", "..", "..", "..");

export async function loadEnv() {
  // Look in ai-asset-generator/ first, then workspace root as fallback
  const searchPaths = [GENERATOR_DIR, ROOT];
  const envFiles = [".env", ".env.local"];

  for (const dir of searchPaths) {
    for (const envFile of envFiles) {
      try {
        const raw = await readFile(join(dir, envFile), "utf8");
        for (const line of raw.split("\n")) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith("#")) continue;
          const eq = trimmed.indexOf("=");
          if (eq === -1) continue;
          const key = trimmed.slice(0, eq).trim();
          const val = trimmed.slice(eq + 1).trim();
          if (!process.env[key]) process.env[key] = val;
        }
        console.log(`  [env] Loaded ${envFile}`);
      } catch {
        // File may not exist, continue
      }
    }
  }
}
