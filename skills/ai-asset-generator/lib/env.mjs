/**
 * Shared .env loader for ai-asset-generator scripts.
 *
 * Search order:
 *   1. Project root (skills/)         — the single source of truth for all env vars
 *   2. ai-asset-generator/ dir        — legacy fallback
 *   3. Monorepo root (skills/../../)  — fallback for monorepo setups
 *
 * Files checked: .env, .env.local (values from earlier files win).
 */

import { readFile } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const GENERATOR_DIR = join(__dirname, "..");
const PROJECT_ROOT = join(__dirname, "..", "..", "..");    // skills/
const MONOREPO_ROOT = join(__dirname, "..", "..", "..", ".."); // one above skills/

export async function loadEnv() {
  const searchPaths = [PROJECT_ROOT, GENERATOR_DIR, MONOREPO_ROOT];
  const envFiles = [".env", ".env.local"];

  for (const dir of searchPaths) {
    for (const envFile of envFiles) {
      try {
        const raw = await readFile(join(dir, envFile), "utf8");
        let loaded = 0;
        for (const line of raw.split("\n")) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith("#")) continue;
          const eq = trimmed.indexOf("=");
          if (eq === -1) continue;
          const key = trimmed.slice(0, eq).trim();
          const val = trimmed.slice(eq + 1).trim();
          if (!process.env[key]) {
            process.env[key] = val;
            loaded++;
          }
        }
        if (loaded > 0) console.log(`  [env] Loaded ${loaded} vars from ${dir}/${envFile}`);
      } catch {
        // File doesn't exist, continue
      }
    }
  }
}
