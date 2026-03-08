#!/usr/bin/env node

// Auto-generate the "Available Skills" and "Available Agents" sections in README.md
// AND update the landing page (landing/index.html) with the same data.
//
// Usage: node scripts/gen-readme.mjs
// Runs automatically on: npm version (prepublishOnly)

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from "fs"
import { join, dirname } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, "..")

// ─── Color rotation for skill cards ───
const SKILL_COLORS = [
  "var(--cyan)",
  "var(--green)",
  "var(--rose)",
  "var(--purple)",
  "var(--amber)",
  "var(--blue)",
]

// ─── Color + icon config for agent cards ───
const AGENT_STYLES = [
  { color: "var(--green)", bg: "var(--green-glow)" },
  { color: "var(--cyan)", bg: "var(--cyan-dim)" },
  { color: "var(--purple)", bg: "var(--purple-dim)" },
  { color: "var(--amber)", bg: "var(--amber-dim)" },
  { color: "var(--rose)", bg: "var(--rose-dim)" },
  { color: "var(--blue)", bg: "var(--blue-dim)" },
]

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/)
  if (!match) return null

  const raw = match[1]
  const result = {}

  // Simple YAML parser for name + description (handles multiline `|` syntax)
  let currentKey = null
  let multilineValue = []

  for (const line of raw.split("\n")) {
    const keyMatch = line.match(/^(\w[\w-]*):\s*(.*)$/)
    if (keyMatch) {
      // Save previous multiline key
      if (currentKey && multilineValue.length) {
        result[currentKey] = multilineValue.join("\n").trim()
        multilineValue = []
      }

      const [, key, value] = keyMatch
      if (value === "|" || value === ">") {
        currentKey = key
        multilineValue = []
      } else {
        result[key] = value.replace(/^["']|["']$/g, "")
        currentKey = null
      }
    } else if (currentKey && (line.startsWith("  ") || line.startsWith("\t"))) {
      multilineValue.push(line.trim())
    }
  }

  // Flush last multiline key
  if (currentKey && multilineValue.length) {
    result[currentKey] = multilineValue.join("\n").trim()
  }

  return result
}

function getShortDescription(description) {
  if (!description) return ""
  // Take the first line, strip markdown bold markers
  const firstLine = description.split("\n")[0].replace(/\*\*/g, "").trim()
  // Remove "MANDATORY TRIGGERS" and trigger lists
  const cleaned = firstLine.replace(/\s*-\s*MANDATORY TRIGGERS:.*/, "").trim()
  // Strip trailing colon/dash artifacts
  let result = cleaned.replace(/[:\-—]+\s*$/, "").trim()
  // Truncate to first sentence if too long (keep under ~120 chars for table readability)
  // Use ". " (period+space) or end-of-string period to avoid cutting at "Next.js", "v5.0", etc.
  if (result.length > 120) {
    const firstSentence = result.match(/^.+?\.\s/)
    if (firstSentence) result = firstSentence[0].trim()
  }
  // Final hard truncate if still too long
  if (result.length > 150) result = result.slice(0, 147) + "..."
  return result
}

function collectSkills() {
  const skillsDir = join(ROOT, "skills")
  const skills = []

  for (const entry of readdirSync(skillsDir)) {
    const skillDir = join(skillsDir, entry)
    if (!statSync(skillDir).isDirectory()) continue

    const skillFile = join(skillDir, "SKILL.md")
    try {
      const content = readFileSync(skillFile, "utf-8")
      const fm = parseFrontmatter(content)
      if (fm?.name) {
        skills.push({
          name: fm.name,
          description: getShortDescription(fm.description),
        })
      }
    } catch {
      // Skip if SKILL.md doesn't exist
    }
  }

  return skills.sort((a, b) => a.name.localeCompare(b.name))
}

function collectAgents() {
  const agentsDir = join(ROOT, "agents")
  const agents = []

  for (const entry of readdirSync(agentsDir)) {
    const fullPath = join(agentsDir, entry)
    let content

    if (statSync(fullPath).isDirectory()) {
      // Directory agent — look for agent.md or first .md file
      const agentFile = join(fullPath, "agent.md")
      try {
        content = readFileSync(agentFile, "utf-8")
      } catch {
        const mdFiles = readdirSync(fullPath).filter((f) => f.endsWith(".md"))
        if (mdFiles.length) content = readFileSync(join(fullPath, mdFiles[0]), "utf-8")
      }
    } else if (entry.endsWith(".md")) {
      content = readFileSync(fullPath, "utf-8")
    }

    if (content) {
      const fm = parseFrontmatter(content)
      if (fm?.name) {
        agents.push({
          name: fm.name,
          description: getShortDescription(fm.description),
        })
      }
    }
  }

  return agents.sort((a, b) => a.name.localeCompare(b.name))
}

function generateSkillsTable(items) {
  const rows = items.map(
    (item) => `| \`${item.name}\` | \`--skills ${item.name}\` | ${item.description} |`,
  )
  return rows.join("\n")
}

function generateAgentsTable(items) {
  const rows = items.map(
    (item) => `| \`${item.name}\` | \`--agents ${item.name}\` | ${item.description} |`,
  )
  return rows.join("\n")
}

// ─── README update ───
function updateReadme(skills, agents) {
  const readmePath = join(ROOT, "README.md")
  let readme = readFileSync(readmePath, "utf-8")

  // Replace "## Available Skills" section
  const skillsTable = `## Available Skills\n\n| Skill | Install | Description |\n|-------|---------|-------------|\n${generateSkillsTable(skills)}`
  readme = readme.replace(
    /## Available Skills\n[\s\S]*?(?=\n## )/,
    skillsTable + "\n\n",
  )

  // Replace "## Available Agents" section
  const agentsTable = `## Available Agents\n\n| Agent | Install | Description |\n|-------|---------|-------------|\n${generateAgentsTable(agents)}`
  readme = readme.replace(
    /## Available Agents\n[\s\S]*?(?=\n## )/,
    agentsTable + "\n\n",
  )

  writeFileSync(readmePath, readme)
}

// ─── Landing page update ───
function updateLanding(skills, agents) {
  const landingPath = join(ROOT, "landing", "index.html")
  if (!existsSync(landingPath)) {
    console.log("  [skip] landing/index.html not found")
    return
  }

  let html = readFileSync(landingPath, "utf-8")
  const sc = skills.length
  const ac = agents.length

  // Read package.json for version
  const pkg = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf-8"))
  const ver = pkg.version
  const verShort = ver.replace(/\.\d+$/, "") // e.g. "2.5.5" → "2.5"

  // Helper: replace content between markers
  function replaceMarker(src, marker, replacement) {
    const re = new RegExp(
      `(<!-- AUTO:${marker} -->)[\\s\\S]*?(<!-- /AUTO:${marker} -->)`,
      "g",
    )
    return src.replace(re, `$1${replacement}$2`)
  }
  function replaceJsMarker(src, marker, replacement) {
    const re = new RegExp(
      `(/\\* AUTO:${marker} \\*/)[\\s\\S]*?(/\\* /AUTO:${marker} \\*/)`,
      "g",
    )
    return src.replace(re, `$1\n${replacement}\n    $2`)
  }

  // 1. Badge: "v2.5 — 14 Skills · 6 Agents"
  html = replaceMarker(html, "BADGE", `v${verShort} &mdash; ${sc} Skills &middot; ${ac} Agents`)

  // 2. Stats bar
  const statsHtml = `
      <div class="stats-bar fade-up">
        <div class="stat"><span class="stat-number">${sc}</span><span class="stat-label">Skills</span></div>
        <div class="stat"><span class="stat-number">${ac}</span><span class="stat-label">Agents</span></div>
        <div class="stat"><span class="stat-number">1</span><span class="stat-label">Command</span></div>
        <div class="stat"><span class="stat-number">MIT</span><span class="stat-label">License</span></div>
      </div>
      `
  html = replaceMarker(html, "STATS", statsHtml)

  // 3. Section heading counts
  html = replaceMarker(html, "SKILL_COUNT", String(sc))
  html = replaceMarker(html, "AGENT_COUNT", String(ac))

  // 4. Meta description counts
  html = replaceMarker(html, "META_COUNTS", `${sc} skills, ${ac} agents`)

  // 5. CTA counts
  html = replaceMarker(html, "CTA_COUNTS", `${sc} skills. ${ac} agents.`)

  // Helper: escape for JS single-quoted string literal
  function escJs(str) {
    return str.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
  }

  // 6. Skills JS data array
  const skillsJs = `    const SKILLS = [\n${skills
    .map((s, i) => {
      const color = SKILL_COLORS[i % SKILL_COLORS.length]
      return `      { name: '${escJs(s.name)}', desc: '${escJs(s.description)}', color: '${color}' },`
    })
    .join("\n")}\n    ];`
  html = replaceJsMarker(html, "SKILLS_DATA", skillsJs)

  // 7. Agents JS data array
  const agentsJs = `    const AGENTS = [\n${agents
    .map((a, i) => {
      const style = AGENT_STYLES[i % AGENT_STYLES.length]
      const icon = escJs(a.name.charAt(0).toUpperCase())
      return `      { name: '${escJs(a.name)}', icon: '${icon}', color: '${style.color}', bg: '${style.bg}', desc: '${escJs(a.description)}' },`
    })
    .join("\n")}\n    ];`
  html = replaceJsMarker(html, "AGENTS_DATA", agentsJs)

  // 8. Footer version
  html = html.replace(
    /(<div class="footer-brand">)GinStudio Skills[^<]*(<\/div>)/,
    `$1GinStudio Skills v${ver}$2`,
  )

  // 9. Terminal animation version line
  html = html.replace(
    /(GinStudio Skills v)[\d.]+/,
    `$1${ver}`,
  )

  // 10. Badge (hero subtitle)
  html = html.replace(
    /<!-- AUTO:BADGE -->.*?<!-- \/AUTO:BADGE -->/,
    `<!-- AUTO:BADGE -->v${ver} &mdash; ${skills.length} Skills &middot; ${agents.length} Agents<!-- /AUTO:BADGE -->`,
  )

  writeFileSync(landingPath, html)
}

// ─── Run ───
const skills = collectSkills()
const agents = collectAgents()

console.log(`Found ${skills.length} skills:`)
skills.forEach((s) => console.log(`  - ${s.name}: ${s.description}`))
console.log(`\nFound ${agents.length} agents:`)
agents.forEach((a) => console.log(`  - ${a.name}: ${a.description}`))

updateReadme(skills, agents)
console.log(`\nREADME.md updated with ${skills.length} skills and ${agents.length} agents.`)

updateLanding(skills, agents)
console.log(`landing/index.html updated with ${skills.length} skills and ${agents.length} agents.`)
