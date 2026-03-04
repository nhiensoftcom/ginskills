#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const readline = require("readline");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const sourceSkillsDir = path.join(__dirname, "skills");
const sourceAgentsDir = path.join(__dirname, "agents");

function getDirectories(srcPath) {
  if (!fs.existsSync(srcPath)) return [];
  return fs
    .readdirSync(srcPath)
    .filter((file) => fs.statSync(path.join(srcPath, file)).isDirectory());
}

function copyDirectorySync(src, dest) {
  if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
  fs.readdirSync(src).forEach((file) => {
    const srcFile = path.join(src, file);
    const destFile = path.join(dest, file);
    if (fs.statSync(srcFile).isDirectory()) {
      copyDirectorySync(srcFile, destFile);
    } else {
      fs.copyFileSync(srcFile, destFile);
    }
  });
}

const skills = getDirectories(sourceSkillsDir);
const agents = getDirectories(sourceAgentsDir);

console.log("====================================================");
console.log("🤖 Claude Code Skills & Agents Installer");
console.log("====================================================\n");

rl.question(
  "Enter the target project path (default: current directory):\n> ",
  (targetPathInput) => {
    const targetProject = targetPathInput.trim() || process.cwd();
    const targetClaudeDir = path.join(targetProject, ".claude");

    console.log(`\n📁 Target directory: ${targetClaudeDir}\n`);

    console.log("--- Available Skills ---");
    skills.forEach((skill, index) => console.log(`  ${index + 1}. ${skill}`));

    rl.question(
      `\nEnter the numbers of the skills to install (comma-separated), 'all', or 'none' (default: all):\n> `,
      (skillsInput) => {
        let selectedSkills = [];
        const sInput = skillsInput.trim().toLowerCase();

        if (sInput === "none") {
          selectedSkills = [];
        } else if (sInput === "" || sInput === "all") {
          selectedSkills = skills;
        } else {
          const indices = sInput
            .split(",")
            .map((n) => parseInt(n.trim()) - 1)
            .filter((n) => !isNaN(n) && n >= 0 && n < skills.length);
          selectedSkills = indices.map((i) => skills[i]);
        }

        console.log("\n--- Available Agents ---");
        if (agents.length === 0) {
          console.log("  No agents found in this repository.");
        } else {
          agents.forEach((agent, index) =>
            console.log(`  ${index + 1}. ${agent}`),
          );
        }

        rl.question(
          `\nEnter the numbers of the agents to install (comma-separated), 'all', or 'none' (default: all):\n> `,
          (agentsInput) => {
            let selectedAgents = [];
            const aInput = agentsInput.trim().toLowerCase();

            if (aInput === "none" || agents.length === 0) {
              selectedAgents = [];
            } else if (aInput === "" || aInput === "all") {
              selectedAgents = agents;
            } else {
              const indices = aInput
                .split(",")
                .map((n) => parseInt(n.trim()) - 1)
                .filter((n) => !isNaN(n) && n >= 0 && n < agents.length);
              selectedAgents = indices.map((i) => agents[i]);
            }

            console.log(
              "\n====================================================",
            );
            console.log("📋 Installation Summary");
            console.log("====================================================");
            console.log(`Target Path: ${targetClaudeDir}`);
            console.log(
              `Skills (${selectedSkills.length}):\n  ${selectedSkills.length ? selectedSkills.join("\n  ") : "None"}`,
            );
            console.log(
              `Agents (${selectedAgents.length}):\n  ${selectedAgents.length ? selectedAgents.join("\n  ") : "None"}`,
            );

            rl.question(
              "\nProceed with installation? (Y/n):\n> ",
              (confirm) => {
                if (confirm.trim().toLowerCase() === "n") {
                  console.log("\n❌ Installation cancelled.");
                  rl.close();
                  return;
                }

                console.log("\nInstalling...");

                if (selectedSkills.length > 0) {
                  const destSkillsDir = path.join(targetClaudeDir, "skills");
                  if (!fs.existsSync(destSkillsDir))
                    fs.mkdirSync(destSkillsDir, { recursive: true });

                  selectedSkills.forEach((skill) => {
                    copyDirectorySync(
                      path.join(sourceSkillsDir, skill),
                      path.join(destSkillsDir, skill),
                    );
                  });
                }

                if (selectedAgents.length > 0) {
                  const destAgentsDir = path.join(targetClaudeDir, "agents");
                  if (!fs.existsSync(destAgentsDir))
                    fs.mkdirSync(destAgentsDir, { recursive: true });

                  selectedAgents.forEach((agent) => {
                    copyDirectorySync(
                      path.join(sourceAgentsDir, agent),
                      path.join(destAgentsDir, agent),
                    );
                  });
                }

                console.log(
                  "\n✅ Installation complete! The skills and agents are ready to use in Claude Code.",
                );
                rl.close();
              },
            );
          },
        );
      },
    );
  },
);
