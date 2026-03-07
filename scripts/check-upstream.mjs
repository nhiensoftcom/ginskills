#!/usr/bin/env node

/**
 * Check & sync upstream ui-ux-pro-max skill before publishing.
 *
 * Compares the local skill data against the latest release/commit on:
 * https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
 *
 * If upstream has updates:
 *   - Automatically pulls latest into skills/ui-ux-pro-max (if git remote is set)
 *   - Or warns with instructions to update manually
 *
 * Saves the last sync timestamp so subsequent runs skip if already up to date.
 */

import { execSync } from "child_process"
import { readFileSync, writeFileSync, existsSync } from "fs"
import { join, dirname } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, "..")
const SKILL_DIR = join(ROOT, "skills", "ui-ux-pro-max")
const UPSTREAM_REPO = "nextlevelbuilder/ui-ux-pro-max-skill"
const UPSTREAM_API = `https://api.github.com/repos/${UPSTREAM_REPO}`

const SYNC_FILE = join(SKILL_DIR, ".last-upstream-sync")

async function getUpstreamLatest() {
  // Try releases first, fall back to commits
  let tag = null
  try {
    const relRes = await fetch(`${UPSTREAM_API}/releases/latest`, {
      headers: { "User-Agent": "ginskill-init" },
    })
    if (relRes.ok) {
      const rel = await relRes.json()
      tag = rel.tag_name
    }
  } catch {}

  const res = await fetch(`${UPSTREAM_API}/commits?per_page=1`, {
    headers: { "User-Agent": "ginskill-init" },
  })
  if (!res.ok) {
    throw new Error(`GitHub API returned ${res.status}: ${res.statusText}`)
  }
  const [commit] = await res.json()
  return {
    sha: commit.sha.slice(0, 7),
    fullSha: commit.sha,
    date: commit.commit.committer.date,
    message: commit.commit.message.split("\n")[0],
    tag,
  }
}

function getLocalSyncInfo() {
  if (!existsSync(SYNC_FILE)) return null
  try {
    const content = readFileSync(SYNC_FILE, "utf-8").trim()
    const [date, sha] = content.split("\n")
    return { date: date || null, sha: sha || null }
  } catch {
    return null
  }
}

function saveSync(date, sha) {
  writeFileSync(SYNC_FILE, `${date}\n${sha}\n`)
}

function hasGitRemote() {
  try {
    const remote = execSync("git remote -v", { cwd: SKILL_DIR, encoding: "utf-8" })
    return remote.includes("ui-ux-pro-max-skill")
  } catch {
    return false
  }
}

function pullLatest() {
  try {
    const result = execSync("git pull origin main --ff-only", {
      cwd: SKILL_DIR,
      encoding: "utf-8",
      timeout: 30000,
    })
    return { success: true, output: result.trim() }
  } catch (err) {
    return { success: false, output: err.message }
  }
}

async function main() {
  console.log("\n  Checking upstream ui-ux-pro-max skill for updates...")

  try {
    const upstream = await getUpstreamLatest()
    const local = getLocalSyncInfo()

    const upstreamDate = new Date(upstream.date)
    const localDate = local?.date ? new Date(local.date) : null

    // Already up to date
    if (local?.sha === upstream.fullSha) {
      console.log(`  [ok] ui-ux-pro-max is up to date (${upstream.sha} — ${upstream.message})`)
      if (upstream.tag) console.log(`       Latest release: ${upstream.tag}`)
      console.log()
      return
    }

    if (localDate && upstreamDate <= localDate) {
      console.log(`  [ok] ui-ux-pro-max is up to date (${upstream.sha} — ${upstream.message})`)
      console.log()
      return
    }

    // Upstream has updates
    console.log(`  [!!] Upstream ui-ux-pro-max has updates!`)
    console.log(`       Latest commit: ${upstream.sha} — ${upstream.message}`)
    console.log(`       Commit date:   ${upstream.date}`)
    if (upstream.tag) console.log(`       Latest release: ${upstream.tag}`)
    if (local?.date) {
      console.log(`       Last synced:   ${local.date}`)
    } else {
      console.log(`       Last synced:   never`)
    }

    // Try auto-sync
    if (hasGitRemote()) {
      console.log(`\n       Auto-syncing from upstream...`)
      const result = pullLatest()
      if (result.success) {
        console.log(`       [ok] Synced successfully: ${result.output}`)
        saveSync(upstream.date, upstream.fullSha)
      } else {
        console.log(`       [warn] Auto-sync failed: ${result.output}`)
        console.log(`       Please manually update: cd skills/ui-ux-pro-max && git pull`)
      }
    } else {
      console.log(`\n       To update manually:`)
      console.log(`         cd skills/ui-ux-pro-max`)
      console.log(`         git remote add origin https://github.com/${UPSTREAM_REPO}.git`)
      console.log(`         git pull origin main`)
      console.log(`       Or download from: https://github.com/${UPSTREAM_REPO}/releases`)
    }
    console.log()
  } catch (err) {
    // Network errors should not block publishing
    console.log(`  [warn] Could not check upstream: ${err.message}`)
    console.log(`         Skipping upstream check (publish will continue).`)
    console.log()
  }
}

main()
