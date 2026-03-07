#!/usr/bin/env node

// Auto-generate the "Available Skills" and "Available Agents" sections in README.md
// by reading frontmatter from each skill's SKILL.md and each agent's .md file.
//
// Usage: node scripts/gen-readme.mjs

import { readFileSync, writeFileSync, readdirSync, statSync } from "fs"
import { join, dirname } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, "..")

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

function generateTable(items) {
  const rows = items.map((item) => `| \`${item.name}\` | ${item.description} |`)
  return rows.join("\n")
}

function updateReadme(skills, agents) {
  const readmePath = join(ROOT, "README.md")
  let readme = readFileSync(readmePath, "utf-8")

  // Replace "## Available Skills" section
  const skillsTable = `## Available Skills\n\n| Skill | Description |\n|-------|-------------|\n${generateTable(skills)}`
  readme = readme.replace(
    /## Available Skills\n[\s\S]*?(?=\n## )/,
    skillsTable + "\n\n",
  )

  // Replace "## Available Agents" section
  const agentsTable = `## Available Agents\n\n| Agent | Description |\n|-------|-------------|\n${generateTable(agents)}`
  readme = readme.replace(
    /## Available Agents\n[\s\S]*?(?=\n## )/,
    agentsTable + "\n\n",
  )

  writeFileSync(readmePath, readme)
  return { skillCount: skills.length, agentCount: agents.length }
}

// Run
const skills = collectSkills()
const agents = collectAgents()

console.log(`Found ${skills.length} skills:`)
skills.forEach((s) => console.log(`  - ${s.name}: ${s.description}`))
console.log(`\nFound ${agents.length} agents:`)
agents.forEach((a) => console.log(`  - ${a.name}: ${a.description}`))

const { skillCount, agentCount } = updateReadme(skills, agents)
console.log(`\nREADME.md updated with ${skillCount} skills and ${agentCount} agents.`)
