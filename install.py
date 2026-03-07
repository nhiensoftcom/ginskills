#!/usr/bin/env python3
"""
Claude Code Skills & Agents Installer

Interactive terminal installer that copies skills and agents into a project's
.claude/ directory following the Anthropic skill standard.

Skills  -> <target>/.claude/skills/<name>/SKILL.md
Agents  -> <target>/.claude/agents/<name>.md

Usage:
    python install.py                  # interactive, defaults to parent dir
    python install.py /path/to/project # specify target directly
"""

import os
import sys
import shutil
from pathlib import Path

# ── ANSI Colors ────────────────────────────────────────────────────────────────

BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
CYAN = "\033[36m"


def enable_ansi():
    if sys.platform == "win32":
        os.system("")  # enables VT100 on Windows 10+


# ── Raw Key Reading (cross-platform) ──────────────────────────────────────────

UP, DOWN, SPACE, ENTER, KEY_A, KEY_Q, OTHER = range(7)


def _read_key_msvcrt():
    import msvcrt

    ch = msvcrt.getwch()
    if ch in ("\x00", "\xe0"):
        ch2 = msvcrt.getwch()
        if ch2 == "H":
            return UP
        if ch2 == "P":
            return DOWN
        return OTHER
    if ch == "\r":
        return ENTER
    if ch == " ":
        return SPACE
    if ch.lower() == "a":
        return KEY_A
    if ch.lower() == "q":
        return KEY_Q
    if ch == "\x03":
        raise KeyboardInterrupt
    return OTHER


def _read_key_termios():
    import termios
    import tty

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
        if ch == "\x1b":
            sys.stdin.read(1)  # '['
            ch3 = sys.stdin.read(1)
            if ch3 == "A":
                return UP
            if ch3 == "B":
                return DOWN
            return OTHER
        if ch in ("\r", "\n"):
            return ENTER
        if ch == " ":
            return SPACE
        if ch.lower() == "a":
            return KEY_A
        if ch.lower() == "q":
            return KEY_Q
        if ch == "\x03":
            raise KeyboardInterrupt
        return OTHER
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def _get_read_key_fn():
    """Return a raw key reader, or None if unavailable."""
    if not sys.stdin.isatty():
        return None
    try:
        import msvcrt  # noqa: F401

        return _read_key_msvcrt
    except ImportError:
        pass
    try:
        import termios  # noqa: F401
        import tty  # noqa: F401

        return _read_key_termios
    except ImportError:
        pass
    return None


# ── Interactive Multi-Select ───────────────────────────────────────────────────


def _render_checklist(title, items, selected, cursor):
    """Build the lines for the checklist UI."""
    lines = []
    lines.append(f"  {BOLD}{CYAN}{title}{RESET}")
    lines.append(
        f"  {DIM}  Up/Down: move   Space: toggle   A: all/none   Enter: confirm{RESET}"
    )
    lines.append("")
    for i, item in enumerate(items):
        mark = f"{GREEN}*{RESET}" if selected[i] else " "
        arrow = f"{CYAN}>{RESET}" if i == cursor else " "
        name = f"{BOLD}{item}{RESET}" if i == cursor else item
        lines.append(f"   {arrow} [{mark}] {name}")
    lines.append("")
    count = sum(selected)
    lines.append(f"  {DIM}{count}/{len(items)} selected{RESET}")
    return lines


def _write_lines(lines):
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.flush()


def _clear_and_rewrite(prev_count, lines):
    # Move up to start of previous block, clear everything below
    sys.stdout.write(f"\033[{prev_count}A\r\033[J")
    _write_lines(lines)
    return len(lines)


def interactive_select(title, items, read_key_fn):
    """Multi-select with arrow keys. Returns list of selected indices."""
    if not items:
        return []

    selected = [True] * len(items)
    cursor = 0
    total = len(items)

    lines = _render_checklist(title, items, selected, cursor)
    _write_lines(lines)
    line_count = len(lines)

    while True:
        key = read_key_fn()

        if key == UP:
            cursor = (cursor - 1) % total
        elif key == DOWN:
            cursor = (cursor + 1) % total
        elif key == SPACE:
            selected[cursor] = not selected[cursor]
        elif key == KEY_A:
            toggle = not all(selected)
            selected = [toggle] * total
        elif key == ENTER:
            # Final render
            lines = _render_checklist(title, items, selected, cursor)
            _clear_and_rewrite(line_count, lines)
            return [i for i in range(total) if selected[i]]
        else:
            continue

        lines = _render_checklist(title, items, selected, cursor)
        line_count = _clear_and_rewrite(line_count, lines)


# ── Fallback Selector (plain numbered input) ──────────────────────────────────


def fallback_select(title, items):
    """Numbered input fallback when raw terminal is unavailable."""
    if not items:
        return []

    print(f"\n  {BOLD}{CYAN}{title}{RESET}")
    for i, item in enumerate(items):
        print(f"    {BOLD}{i + 1}.{RESET} {item}")

    print(f"\n  {DIM}Enter numbers (e.g. 1,3,5 or 1-5), 'all', or 'none' [default: all]{RESET}")
    choice = input(f"  {BLUE}>{RESET} ").strip().lower()

    if choice == "none":
        return []
    if choice in ("", "all"):
        return list(range(len(items)))

    indices = set()
    for part in choice.split(","):
        part = part.strip()
        if "-" in part:
            try:
                a, b = part.split("-", 1)
                for n in range(int(a), int(b) + 1):
                    if 1 <= n <= len(items):
                        indices.add(n - 1)
            except ValueError:
                pass
        else:
            try:
                n = int(part)
                if 1 <= n <= len(items):
                    indices.add(n - 1)
            except ValueError:
                pass

    return sorted(indices)


# ── Discovery ─────────────────────────────────────────────────────────────────


def discover_skills(skills_dir):
    """Find skill directories that contain SKILL.md (Anthropic standard)."""
    if not skills_dir.exists():
        return []
    return sorted(
        d.name for d in skills_dir.iterdir() if d.is_dir() and (d / "SKILL.md").exists()
    )


def discover_agents(agents_dir):
    """Find agent markdown files."""
    if not agents_dir.exists():
        return []
    return sorted(f.name for f in agents_dir.iterdir() if f.is_file() and f.suffix == ".md")


# ── Install ───────────────────────────────────────────────────────────────────


def install_skill(src_dir, dest_dir):
    """Copy a skill directory (overwrites if exists)."""
    if dest_dir.exists():
        shutil.rmtree(dest_dir)
    shutil.copytree(src_dir, dest_dir)


def install_agent(src_file, dest_file):
    """Copy an agent .md file."""
    dest_file.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_file, dest_file)


# ── Main ──────────────────────────────────────────────────────────────────────


def main():
    enable_ansi()

    script_dir = Path(__file__).resolve().parent
    default_target = script_dir.parent  # parent of ginstudio-skills repo
    skills_src = script_dir / "skills"
    agents_src = script_dir / "agents"

    # Discover
    skills = discover_skills(skills_src)
    agents = discover_agents(agents_src)

    # Determine selection mode
    read_key_fn = _get_read_key_fn()

    def select(title, items):
        if read_key_fn:
            try:
                return interactive_select(title, items, read_key_fn)
            except Exception:
                pass  # fall through to fallback
        return fallback_select(title, items)

    # ── Header ──
    print(
        f"""
{BOLD}{'=' * 56}
     Claude Code Skills & Agents Installer
{'=' * 56}{RESET}
"""
    )

    # ── Target Directory ──
    print(f"  Default target: {CYAN}{default_target}{RESET}")

    if len(sys.argv) > 1:
        target = Path(sys.argv[1]).resolve()
        print(f"  Using argument: {CYAN}{target}{RESET}")
    else:
        target_input = input(f"  Enter target path [{CYAN}Enter{RESET} for default]: ").strip()
        target = Path(target_input).resolve() if target_input else default_target

    if not target.exists():
        print(f"\n  {RED}Error: path does not exist: {target}{RESET}")
        sys.exit(1)

    claude_dir = target / ".claude"
    print(f"\n  Will install to: {GREEN}{claude_dir}{RESET}\n")

    # ── Select Skills ──
    if skills:
        skill_indices = select("Select Skills", skills)
        selected_skills = [skills[i] for i in skill_indices]
    else:
        print(f"  {YELLOW}No skills found in {skills_src}{RESET}")
        selected_skills = []

    # ── Select Agents ──
    if agents:
        agent_display = [a.replace(".md", "") for a in agents]
        agent_indices = select("Select Agents", agent_display)
        selected_agents = [agents[i] for i in agent_indices]
    else:
        print(f"  {YELLOW}No agents found in {agents_src}{RESET}")
        selected_agents = []

    # ── Nothing selected ──
    if not selected_skills and not selected_agents:
        print(f"\n  {YELLOW}Nothing selected. Exiting.{RESET}")
        sys.exit(0)

    # ── Summary ──
    print(
        f"""
{BOLD}{'─' * 56}
  Installation Summary
{'─' * 56}{RESET}

  Target: {CYAN}{claude_dir}{RESET}

  {BOLD}Skills ({len(selected_skills)}):{RESET}"""
    )
    if selected_skills:
        for s in selected_skills:
            print(f"    {GREEN}*{RESET} {s}")
    else:
        print(f"    {DIM}(none){RESET}")

    print(f"\n  {BOLD}Agents ({len(selected_agents)}):{RESET}")
    if selected_agents:
        for a in selected_agents:
            print(f"    {GREEN}*{RESET} {a.replace('.md', '')}")
    else:
        print(f"    {DIM}(none){RESET}")

    # ── Confirm ──
    confirm = input(f"\n  Proceed? [Y/n]: ").strip().lower()
    if confirm == "n":
        print(f"\n  {RED}Cancelled.{RESET}")
        sys.exit(0)

    # ── Install ──
    print()
    installed = 0

    if selected_skills:
        dest_skills = claude_dir / "skills"
        dest_skills.mkdir(parents=True, exist_ok=True)
        for skill in selected_skills:
            install_skill(skills_src / skill, dest_skills / skill)
            installed += 1
            print(f"  {GREEN}*{RESET} Skill installed: {BOLD}{skill}{RESET}")

    if selected_agents:
        dest_agents = claude_dir / "agents"
        dest_agents.mkdir(parents=True, exist_ok=True)
        for agent in selected_agents:
            install_agent(agents_src / agent, dest_agents / agent)
            installed += 1
            name = agent.replace(".md", "")
            print(f"  {GREEN}*{RESET} Agent installed: {BOLD}{name}{RESET}")

    # ── Done ──
    print(
        f"""
{BOLD}{GREEN}  Installation complete! ({installed} items installed){RESET}

  Skills -> {claude_dir / 'skills'}
  Agents -> {claude_dir / 'agents'}

  {DIM}Restart Claude Code to pick up new skills and agents.{RESET}
"""
    )


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n  {RED}Interrupted.{RESET}")
        sys.exit(1)
