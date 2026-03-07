#!/usr/bin/env node

/**
 * Check upstream ui-ux-pro-max skill for updates before publishing.
 *
 * Compares the local skill data against the latest commit on the upstream repo:
 * https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
 *
 * Warns (non-blocking) if the upstream has newer commits than the local copy.
 */

import { execSync } from "child_process"
import { readFileSync, existsSync } from "fs"
import { join, dirname } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, "..")
const SKILL_DIR = join(ROOT, "skills", "ui-ux-pro-max")
const UPSTREAM_REPO = "nextlevelbuilder/ui-ux-pro-max-skill"
const UPSTREAM_URL = `https://api.github.com/repos/${UPSTREAM_REPO}/commits?per_page=1`

// Local timestamp file to track last sync
const SYNC_FILE = join(SKILL_DIR, ".last-upstream-sync")

async function getUpstreamLatestCommit() {
  const res = await fetch(UPSTREAM_URL, {
    headers: { "User-Agent": "ginskill-init" },
  })
  if (!res.ok) {
    throw new Error(`GitHub API returned ${res.status}: ${res.statusText}`)
  }
  const [commit] = await res.json()
  return {
    sha: commit.sha.slice(0, 7),
    date: commit.commit.committer.date,
    message: commit.commit.message.split("\n")[0],
  }
}

function getLocalSyncDate() {
  if (!existsSync(SYNC_FILE)) return null
  try {
    const content = readFileSync(SYNC_FILE, "utf-8").trim()
    return content || null
  } catch {
    return null
  }
}

async function main() {
  console.log("\n🔍 Checking upstream ui-ux-pro-max skill for updates...")

  try {
    const upstream = await getUpstreamLatestCommit()
    const localSync = getLocalSyncDate()

    const upstreamDate = new Date(upstream.date)
    const localDate = localSync ? new Date(localSync) : null

    if (localDate && upstreamDate <= localDate) {
      console.log(`  ✅ ui-ux-pro-max is up to date (upstream: ${upstream.sha} — ${upstream.message})`)
    } else {
      console.log(`  ⚠️  Upstream ui-ux-pro-max has updates!`)
      console.log(`     Latest commit: ${upstream.sha} — ${upstream.message}`)
      console.log(`     Commit date:   ${upstream.date}`)
      if (localSync) {
        console.log(`     Last synced:   ${localSync}`)
      } else {
        console.log(`     Last synced:   never`)
      }
      console.log(`     Repo: https://github.com/${UPSTREAM_REPO}`)
      console.log(`     Run: git -C skills/ui-ux-pro-max pull  (if tracking upstream)`)
      console.log()
      // Non-blocking warning — don't exit(1) to avoid blocking publish
    }
  } catch (err) {
    // Network errors should not block publishing
    console.log(`  ⚠️  Could not check upstream: ${err.message}`)
    console.log(`     Skipping upstream check (publish will continue).`)
  }

  console.log()
}

main()
