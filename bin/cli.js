#!/usr/bin/env node

import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { existsSync, readdirSync, statSync, mkdirSync, copyFileSync, rmSync, readFileSync, writeFileSync } from 'fs';
import { homedir } from 'os';
import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import prompts from 'prompts';

const __dirname  = dirname(fileURLToPath(import.meta.url));
const PACKAGE_DIR = join(__dirname, '..');
const SRC_SKILLS  = join(PACKAGE_DIR, 'skills');
const SRC_AGENTS  = join(PACKAGE_DIR, 'agents');
const PKG         = JSON.parse(readFileSync(join(PACKAGE_DIR, 'package.json'), 'utf-8'));

// ─── Skills that require environment variables ───────────────────────────────
const SKILL_ENV_VARS = {
  'ai-asset-generator': [
    { key: 'KIE_AI_API_KEY', desc: 'KIE AI API key for image/video generation', url: 'https://kie.ai' },
    { key: 'STY_AI_API_KEY', desc: 'Sty AI API key for background removal', url: 'https://api.styai.app' },
  ],
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function getDirs(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).filter(f => statSync(join(dir, f)).isDirectory());
}

function getMdFiles(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter(f => f.endsWith('.md') && statSync(join(dir, f)).isFile())
    .map(f => f.replace('.md', ''));
}

function unique(arr) {
  return [...new Set(arr)];
}

function copyDir(src, dest) {
  mkdirSync(dest, { recursive: true });
  for (const entry of readdirSync(src)) {
    const s = join(src, entry), d = join(dest, entry);
    statSync(s).isDirectory() ? copyDir(s, d) : copyFileSync(s, d);
  }
}

function resolveTarget(targetArg, isGlobal) {
  if (isGlobal)  return join(homedir(), '.claude');
  if (targetArg) return join(targetArg, '.claude');
  return join(process.cwd(), '.claude');
}

function getAvailable() {
  const skills = getDirs(SRC_SKILLS);
  const agents = unique([...getDirs(SRC_AGENTS), ...getMdFiles(SRC_AGENTS)]);
  return { skills, agents };
}

function getInstalled(claudeDir) {
  const skills = getDirs(join(claudeDir, 'skills'))
    .filter(s => getDirs(SRC_SKILLS).includes(s));           // only ours
  const agentDir = join(claudeDir, 'agents');
  const available = getAvailable().agents;
  const agents = unique([
    ...getDirs(agentDir),
    ...getMdFiles(agentDir),
  ]).filter(a => available.includes(a));
  return { skills, agents };
}

// ─── Logger ───────────────────────────────────────────────────────────────────

const log = {
  title:   msg => console.log('\n' + chalk.bold.cyan(msg) + '\n'),
  info:    msg => console.log(chalk.blue('  info  ') + msg),
  success: msg => console.log(chalk.green('  ✓  ') + msg),
  warn:    msg => console.log(chalk.yellow('  warn  ') + msg),
  error:   msg => console.log(chalk.red('  error ') + msg),
  dim:     msg => console.log(chalk.dim('  ' + msg)),
};

const onCancel = () => { log.warn('Cancelled.'); process.exit(0); };

// ─── Core Install ─────────────────────────────────────────────────────────────

async function runInstall({ target, skills, agents, verb = 'Installed' }) {
  const destSkills = join(target, 'skills');
  const destAgents = join(target, 'agents');

  if (skills.length === 0 && agents.length === 0) {
    log.warn('Nothing selected.');
    return;
  }

  const spinner = ora({ text: 'Working...', color: 'cyan' }).start();
  let count = 0;

  for (const skill of skills) {
    spinner.text = `${verb.replace('d','ing')} skill ${chalk.cyan(skill)}...`;
    copyDir(join(SRC_SKILLS, skill), join(destSkills, skill));
    count++;
  }

  for (const agent of agents) {
    spinner.text = `${verb.replace('d','ing')} agent ${chalk.cyan(agent)}...`;
    const srcDir  = join(SRC_AGENTS, agent);
    const srcFile = join(SRC_AGENTS, `${agent}.md`);
    mkdirSync(destAgents, { recursive: true });
    if (existsSync(srcDir) && statSync(srcDir).isDirectory()) {
      copyDir(srcDir, join(destAgents, agent));
    } else if (existsSync(srcFile)) {
      copyFileSync(srcFile, join(destAgents, `${agent}.md`));
    }
    count++;
  }

  spinner.succeed(chalk.bold.green(`${verb}! ${count} item(s)`));
  console.log();
  log.info(`Target: ${chalk.cyan(target)}`);

  // Check if any installed skills need env vars
  const neededVars = [];
  for (const skill of skills) {
    if (SKILL_ENV_VARS[skill]) {
      neededVars.push(...SKILL_ENV_VARS[skill].map(v => ({ ...v, skill })));
    }
  }

  if (neededVars.length > 0) {
    const envExamplePath = join(target, '.env.example');
    const envPath = join(target, '.env');

    // Build .env.example content
    const lines = ['# Environment variables required by installed skills', ''];
    const grouped = {};
    for (const v of neededVars) {
      if (!grouped[v.skill]) grouped[v.skill] = [];
      grouped[v.skill].push(v);
    }
    for (const [skill, vars] of Object.entries(grouped)) {
      lines.push(`# ─── ${skill} ───`);
      for (const v of vars) {
        lines.push(`# ${v.desc}`);
        lines.push(`# Get from: ${v.url}`);
        lines.push(`${v.key}=`);
        lines.push('');
      }
    }

    // Write .env.example (always overwrite with latest)
    writeFileSync(envExamplePath, lines.join('\n'));

    // Create .env from .env.example if it doesn't exist yet
    if (!existsSync(envPath)) {
      copyFileSync(envExamplePath, envPath);
    }

    console.log();
    console.log(chalk.bold.yellow('  ⚠  Environment variables required:'));
    console.log();
    for (const v of neededVars) {
      console.log(`    ${chalk.yellow(v.key)}`);
      console.log(`    ${chalk.dim(v.desc)} — ${chalk.cyan(v.url)}`);
      console.log();
    }
    console.log(`  ${chalk.dim('Fill in your keys in:')} ${chalk.cyan(envPath)}`);
  }

  console.log();
  log.dim('Restart Claude Code (or run /agents) to pick up changes.');
  console.log();
}

// ─── Multiselect helper ───────────────────────────────────────────────────────

async function multiSelect(message, choices) {
  const { selected } = await prompts({
    type: 'multiselect',
    name: 'selected',
    message,
    choices,
    hint: 'Space to toggle · A to toggle all · Enter to confirm',
    instructions: false,
    min: 0,
  }, { onCancel });
  return selected ?? [];
}

async function confirmPrompt(message) {
  const { ok } = await prompts({ type: 'confirm', name: 'ok', message, initial: true }, { onCancel });
  return ok;
}

// ─── COMMAND: install ─────────────────────────────────────────────────────────

async function cmdInstall(options, targetArg) {
  log.title('GinStudio — Install Skills & Agents');

  const target  = resolveTarget(options.target || targetArg, options.global);
  const { skills: allSkills, agents: allAgents } = getAvailable();

  // Non-interactive shortcut flags
  if (options.all || options.skills || options.agents) {
    const skills = options.all ? allSkills
      : options.skills ? options.skills.split(',').map(s => s.trim()).filter(s => allSkills.includes(s))
      : allSkills;
    const agents = options.all ? allAgents
      : options.agents ? options.agents.split(',').map(s => s.trim()).filter(s => allAgents.includes(s))
      : allAgents;

    log.info(`Target: ${chalk.cyan(target)}`);
    log.info(`Skills (${skills.length}): ${chalk.green(skills.join(', ') || 'none')}`);
    log.info(`Agents (${agents.length}): ${chalk.cyan(agents.join(', ') || 'none')}`);
    console.log();
    return runInstall({ target, skills, agents });
  }

  // Full TUI
  log.info(`Target: ${chalk.cyan(target)}\n`);

  const installed = getInstalled(target);

  const skills = await multiSelect('Select skills to install:', allSkills.map(s => ({
    title: s,
    value: s,
    selected: installed.skills.includes(s) || !existsSync(target),
  })));

  console.log();

  const agents = await multiSelect('Select agents to install:', allAgents.map(a => ({
    title: a,
    value: a,
    selected: installed.agents.includes(a) || !existsSync(target),
  })));

  console.log();
  console.log(chalk.bold('  Summary'));
  console.log(`    ${chalk.green('Skills')} (${skills.length}): ${skills.join(', ') || chalk.dim('none')}`);
  console.log(`    ${chalk.cyan('Agents')} (${agents.length}): ${agents.join(', ') || chalk.dim('none')}`);
  console.log(`    Target: ${target}`);
  console.log();

  if (!await confirmPrompt('Install?')) { log.warn('Cancelled.'); return; }
  console.log();

  return runInstall({ target, skills, agents });
}

// ─── COMMAND: upgrade ─────────────────────────────────────────────────────────

async function cmdUpgrade(options, targetArg) {
  log.title('GinStudio — Upgrade Skills & Agents');

  const target = resolveTarget(options.target || targetArg, options.global);
  const installed = getInstalled(target);
  const total = installed.skills.length + installed.agents.length;

  if (total === 0) {
    log.warn(`Nothing from GinStudio is installed in ${chalk.cyan(target)}.`);
    log.dim(`Run ${chalk.white('gin-skills')} to install first.`);
    console.log();
    return;
  }

  log.info(`Target: ${chalk.cyan(target)}`);
  log.info(`Current package: ${chalk.cyan(`v${PKG.version}`)}\n`);

  // Non-interactive: --all or --skills/--agents flags
  if (options.all || options.skills || options.agents) {
    const skills = options.all ? installed.skills
      : options.skills ? options.skills.split(',').map(s => s.trim()).filter(s => installed.skills.includes(s))
      : [];
    const agents = options.all ? installed.agents
      : options.agents ? options.agents.split(',').map(s => s.trim()).filter(s => installed.agents.includes(s))
      : [];

    if (skills.length === 0 && agents.length === 0) {
      log.warn('No matching installed items found.');
      return;
    }

    log.info(`Skills (${skills.length}): ${chalk.green(skills.join(', ') || 'none')}`);
    log.info(`Agents (${agents.length}): ${chalk.cyan(agents.join(', ') || 'none')}`);
    console.log();
    return runInstall({ target, skills, agents, verb: 'Upgraded' });
  }

  const skills = await multiSelect('Select skills to upgrade:', installed.skills.map(s => ({
    title: s, value: s, selected: true,
  })));

  console.log();

  const agents = await multiSelect('Select agents to upgrade:', installed.agents.map(a => ({
    title: a, value: a, selected: true,
  })));

  console.log();

  if (!await confirmPrompt(`Re-install ${skills.length + agents.length} item(s) from v${PKG.version}?`)) {
    log.warn('Cancelled.');
    return;
  }
  console.log();

  return runInstall({ target, skills, agents, verb: 'Upgraded' });
}

// ─── COMMAND: uninstall ───────────────────────────────────────────────────────

async function cmdUninstall(options, targetArg) {
  log.title('GinStudio — Uninstall Skills & Agents');

  const target = resolveTarget(options.target || targetArg, options.global);
  const installed = getInstalled(target);
  const total = installed.skills.length + installed.agents.length;

  if (total === 0) {
    log.warn(`Nothing from GinStudio is installed in ${chalk.cyan(target)}.`);
    console.log();
    return;
  }

  log.info(`Target: ${chalk.cyan(target)}\n`);

  const skills = await multiSelect('Select skills to uninstall:', installed.skills.map(s => ({
    title: s, value: s, selected: false,
  })));

  console.log();

  const agents = await multiSelect('Select agents to uninstall:', installed.agents.map(a => ({
    title: a, value: a, selected: false,
  })));

  console.log();

  const count = skills.length + agents.length;
  if (count === 0) { log.warn('Nothing selected.'); return; }

  console.log(chalk.bold('  Will remove:'));
  skills.forEach(s => console.log(`    ${chalk.red('✕')} skill  ${s}`));
  agents.forEach(a => console.log(`    ${chalk.red('✕')} agent  ${a}`));
  console.log();

  if (!await confirmPrompt(chalk.red(`Permanently remove ${count} item(s)?`))) {
    log.warn('Cancelled.');
    return;
  }

  const spinner = ora({ text: 'Removing...', color: 'red' }).start();

  for (const skill of skills) {
    const dir = join(target, 'skills', skill);
    if (existsSync(dir)) rmSync(dir, { recursive: true, force: true });
  }
  for (const agent of agents) {
    const dir  = join(target, 'agents', agent);
    const file = join(target, 'agents', `${agent}.md`);
    if (existsSync(dir))  rmSync(dir,  { recursive: true, force: true });
    if (existsSync(file)) rmSync(file, { force: true });
  }

  spinner.succeed(chalk.bold.red(`Removed ${count} item(s)`));
  console.log();
  log.dim('Restart Claude Code to pick up changes.');
  console.log();
}

// ─── COMMAND: status ──────────────────────────────────────────────────────────

function cmdStatus(options, targetArg) {
  log.title('GinStudio — Status');

  const target = resolveTarget(options.target || targetArg, options.global);
  const { skills: allSkills, agents: allAgents } = getAvailable();
  const installed = getInstalled(target);

  log.info(`Package:  ${chalk.cyan(`gin-skills v${PKG.version}`)}`);
  log.info(`Target:   ${chalk.cyan(target)}`);
  console.log();

  console.log(chalk.bold('  Skills:'));
  for (const s of allSkills) {
    const isInstalled = installed.skills.includes(s);
    const icon  = isInstalled ? chalk.green('✓') : chalk.dim('○');
    const label = isInstalled ? chalk.white(s)   : chalk.dim(s);
    const badge = isInstalled ? chalk.green('installed') : chalk.dim('not installed');
    console.log(`    ${icon}  ${label.padEnd(28)} ${badge}`);
  }

  console.log();
  console.log(chalk.bold('  Agents:'));
  for (const a of allAgents) {
    const isInstalled = installed.agents.includes(a);
    const icon  = isInstalled ? chalk.green('✓') : chalk.dim('○');
    const label = isInstalled ? chalk.cyan(a)    : chalk.dim(a);
    const badge = isInstalled ? chalk.green('installed') : chalk.dim('not installed');
    console.log(`    ${icon}  ${label.padEnd(28)} ${badge}`);
  }

  console.log();
  const si = installed.skills.length, ai = installed.agents.length;
  log.info(`${si} skill(s) · ${ai} agent(s) installed out of ${allSkills.length} skills · ${allAgents.length} agents available`);
  console.log();
}

// ─── COMMAND: versions ────────────────────────────────────────────────────────

async function cmdVersions() {
  log.title('GinStudio — Available Versions');

  const spinner = ora({ text: 'Fetching from npm registry...', color: 'cyan' }).start();

  try {
    const res  = await fetch(`https://registry.npmjs.org/${PKG.name}`);
    if (!res.ok) throw new Error(`Registry returned ${res.status}`);
    const data = await res.json();

    const versions = Object.keys(data.versions || {}).reverse();
    const latest   = data['dist-tags']?.latest;
    const times    = data.time || {};

    spinner.succeed(`Found ${versions.length} version(s)\n`);

    console.log(chalk.bold('  Available versions:\n'));
    for (const v of versions.slice(0, 20)) {
      const isLatest = v === latest;
      const date     = times[v] ? new Date(times[v]).toLocaleDateString() : '';
      const isCurrent = v === PKG.version;
      const tag      = isLatest ? chalk.green('[latest]') : '';
      const cur      = isCurrent ? chalk.blue('[current]') : '';
      const vStr     = isLatest ? chalk.bold.green(`v${v}`) : chalk.white(`v${v}`);
      console.log(`    ${vStr}  ${chalk.dim(date)}  ${tag} ${cur}`);
    }
    if (versions.length > 20) log.dim(`... and ${versions.length - 20} more`);

    console.log();
    log.dim(`Run ${chalk.white('npx gin-skills@latest')} to get the newest version.`);
    console.log();

  } catch (err) {
    spinner.fail('Could not fetch versions from npm registry.');
    log.error(err.message);
    log.dim(`Current installed version: ${chalk.cyan(`v${PKG.version}`)}`);
    console.log();
  }
}

// ─── COMMAND: list ────────────────────────────────────────────────────────────

function cmdList() {
  log.title('GinStudio — Available Skills & Agents');
  const { skills, agents } = getAvailable();

  console.log(chalk.bold('  Skills:'));
  skills.forEach(s => console.log(`    ${chalk.green('✦')} ${s}`));
  console.log();
  console.log(chalk.bold('  Agents:'));
  agents.forEach(a => console.log(`    ${chalk.cyan('✦')} ${a}`));
  console.log();
}

// ─── CLI wiring ───────────────────────────────────────────────────────────────

const program = new Command();

program
  .name('gin-skills')
  .description('Install GinStudio skills & agents for Claude Code')
  .version(PKG.version);

// Shared options factory
function addTargetOptions(cmd) {
  return cmd
    .option('-g, --global',        'Target ~/.claude/ (available in all projects)')
    .option('-t, --target <path>', 'Custom target project path')
    .argument('[target]',          'Target project path (positional)');
}

// Default: install
addTargetOptions(
  program
    .option('-a, --all',           'Install all without prompts')
    .option('--skills <list>',     'Install specific skills (comma-separated names)')
    .option('--agents <list>',     'Install specific agents (comma-separated names)')
)
.action((targetArg, opts) => cmdInstall(opts, targetArg));

// Merge parent opts (handles case where Commander consumes -t/-g at parent level)
function mergeOpts(opts) {
  return { ...program.opts(), ...opts };
}

// upgrade
addTargetOptions(
  program.command('upgrade')
    .description('Upgrade installed skills & agents to the bundled version')
    .option('-a, --all', 'Upgrade all without prompts')
    .option('--skills <list>', 'Upgrade specific skills only (comma-separated names)')
    .option('--agents <list>', 'Upgrade specific agents only (comma-separated names)')
)
.action((targetArg, opts) => cmdUpgrade(mergeOpts(opts), targetArg));

// uninstall
addTargetOptions(
  program.command('uninstall').alias('remove')
    .description('Remove installed skills & agents')
)
.action((targetArg, opts) => cmdUninstall(mergeOpts(opts), targetArg));

// status
addTargetOptions(
  program.command('status').alias('info')
    .description('Show installed vs available skills & agents')
)
.action((targetArg, opts) => cmdStatus(mergeOpts(opts), targetArg));

// versions
program.command('versions').alias('ver')
  .description('List all published npm versions')
  .action(() => cmdVersions());

// list
program.command('list').alias('ls')
  .description('List all available skills & agents in this package')
  .action(() => cmdList());

program.parse();
