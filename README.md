<p align="center">
  <h1 align="center">CW</h1>
  <p align="center">
    <strong>Claude Workspace Manager</strong>
    <br />
    Multi-project orchestrator for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a>
  </p>
  <p align="center">
    <a href="#quick-start">Quick Start</a> &middot;
    <a href="#how-it-works">How It Works</a> &middot;
    <a href="docs/commands.md">Commands</a> &middot;
    <a href="docs/architecture.md">Architecture</a>
  </p>
</p>

---

One command. Right account. Isolated worktree. Full context.

```bash
cw work my-app https://linear.app/team/issue/PROJ-123/fix-auth-flow
```

CW launches Claude with the correct account, fetches the ticket from Linear, creates a worktree, and starts working — all automatically.

---

## The Problem

Working with Claude Code across multiple projects means:

- Juggling `CLAUDE_CONFIG_DIR` for every project
- Losing context when conversations expire
- Branch conflicts when reviewing PRs while coding
- Copy-pasting ticket descriptions into Claude manually

## The Solution

```
cw work my-app PROJ-123        →  worktree + Linear context + right account
cw review my-app 42            →  isolated PR review with auto-start
cw work my-app PROJ-123        →  resume exactly where you left off
cw work my-app PROJ-123 --done →  cleanup worktree, archive session
```

## Quick Start

```bash
# Install
git clone https://github.com/avarajar/cw.git && cd cw && ./install.sh

# Setup
cw init
cw account add work
cw launch work                    # authenticate with /login
cw project register ~/code/my-app --account work

# Go
cw work my-app fix-auth
```

## Core Commands

### Work

```bash
cw work my-app fix-auth                                # branch name
cw work my-app PROJ-123                                # ticket ID
cw work my-app https://linear.app/team/issue/PROJ-123  # Linear URL
cw work my-app https://github.com/org/repo/issues/42   # GitHub issue
cw work my-app https://notion.so/team/Auth-Redesign    # Notion page

cw work my-app fix-auth                                # resume
cw work my-app fix-auth --done                         # close + cleanup
```

Creates an isolated worktree, tracks the session, fetches context from URLs via MCP, and launches Claude.

### Review

```bash
cw review my-app 123                                   # by PR number
cw review my-app https://github.com/org/repo/pull/123  # by URL
cw review my-app 123                                   # re-review (checks resolved changes)
cw review my-app 123 --done                            # close
```

First review runs your project's review skill automatically. Follow-up reviews check if requested changes were addressed.

### Quick Access

```bash
cw open my-app          # open Claude in project (no worktree)
cw spaces               # list all active tasks and reviews
cw dashboard            # full workspace overview
```

### Arcade (Live Dashboard)

```bash
cw arcade --setup       # install activity hooks (once)
cw arcade               # launch live dashboard in browser
```

Real-time visual dashboard that shows all your Claude Code sessions, tool usage, and agent activity across accounts. Uses Server-Sent Events to stream activity as it happens — no polling.

The `--setup` command installs Claude Code hooks in all your accounts. New accounts created with `cw account add` auto-inherit the hooks.

## Multi-Account Routing

Each project maps to a Claude account. CW handles the rest.

```bash
cw account add work
cw account add personal

cw project register ~/code/company-app  --account work
cw project register ~/code/side-project --account personal

cw work company-app feat-x      # → work account
cw work side-project feat-y     # → personal account
```

## How It Works

### Worktree Isolation

Every task and review gets its own [git worktree](https://git-scm.com/docs/git-worktree). No checkout conflicts, no stashing.

```
my-app/
├── src/                       # main branch (untouched)
├── .tasks/
│   ├── fix-auth/              # worktree → fix-auth branch
│   └── PROJ-123/              # worktree → branch from Linear
└── .reviews/
    └── pr-123/                # worktree → PR branch
```

### Session Persistence

Context survives conversation loss. Notes and metadata live in `~/.cw/sessions/`, symlinked into worktrees:

```
~/.cw/sessions/my-app/
├── task-fix-auth/
│   ├── session.json           # metadata, status, opens count
│   ├── TASK_NOTES.md          # persistent context → symlinked into worktree
│   └── init_prompt.txt        # initial Claude prompt
└── review-pr-123/
    ├── session.json
    └── REVIEW_NOTES.md
```

When you resume, Claude uses `--continue`. If the conversation is lost, the notes file preserves context.

### URL → Context

```
cw work my-app https://linear.app/.../PROJ-123
  → Parse URL, detect Linear, extract PROJ-123
  → Launch Claude with init prompt
  → Claude fetches issue via MCP, creates worktree, fills TASK_NOTES.md
```

Works with **Linear**, **GitHub**, and **Notion** URLs.

### Review Skills

CW finds the best review skill for each project:

| Priority | Location |
|----------|----------|
| 1 | `.claude/skills/{code-review,review-pr,review}/SKILL.md` (project) |
| 2 | `~/.claude/skills/{code-review,code-reviewer}/SKILL.md` (global) |
| 3 | `~/.cw/commands/review-pr.md` (CW fallback) |
| 4 | Built-in default |

## Installation

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git 2.15+
- Python 3.6+
- Bash 4+ or Zsh

### Setup

```bash
git clone https://github.com/avarajar/cw.git
cd cw
./install.sh
```

The installer adds shell integration to `.zshrc` / `.bashrc` with tab completion and aliases.

## Configuration

### `~/.cw/config.yaml`

```yaml
default_account: work
skip_permissions: false     # set true to skip Claude permission prompts

tools:
  tracker: linear
  docs: notion
  chat: slack
  repo: github
```

### Permission Skipping

```bash
# Per-command
cw --skip-permissions work my-app fix-auth

# Permanent (config.yaml)
skip_permissions: true

# Per-session (env)
CW_CLAUDE_FLAGS="--dangerously-skip-permissions" cw work my-app fix-auth
```

### MCP Integrations

```bash
cw project setup-mcps my-app    # interactive setup for GitHub, Linear, Notion, Slack
```

Installs MCPs directly on the project's account. Shows status of already-installed MCPs.

## Shell Aliases

After installation, these aliases are available:

| Alias | Command |
|-------|---------|
| `cww` | `cw work` |
| `cwpr` | `cw review` |
| `cwsp` | `cw spaces` |
| `cwd` | `cw dashboard` |
| `cws` | `cw status` |
| `cwl` | `cw project list` |
| `cwo` | Fuzzy project opener (requires `fzf`) |
| `cc` | `cw launch` |

## Team Setup

CW is shared. Personal data stays local.

| Shared (this repo) | Personal (`~/.cw/`) |
|---------------------|---------------------|
| `cw`, `install.sh` | `accounts/` |
| `cw-shell-integration.sh` | `projects.json` |
| `templates/`, `docs/` | `sessions/` |

Each member clones the repo, runs `install.sh`, registers their own projects. Paths don't need to match.

## Integrations

### GSD — Get Shit Done

[GSD](https://github.com/gsd-build/get-shit-done) is a meta-prompting workflow for Claude Code. It installs slash commands and context files (`PROJECT.md`, `ROADMAP.md`, `STATE.md`) that guide Claude through Discuss → Plan → Execute → Verify phases.

```bash
cw gsd:init [path]   # initialize GSD in a worktree (default: current directory)
cw gsd:sync          # initialize GSD in all active worktrees that don't have it yet
```

Requires Node.js / npx.

### claude-code-best-practice — Agents & Hooks

[claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) provides ready-made agents and hooks with audio notifications for Claude Code events.

Bundled in this repo and installed automatically by `install.sh`:

| Asset | Location | Purpose |
|-------|----------|---------|
| `agents/presentation-curator.md` | `~/.cw/agents/` | Proactive slide/presentation agent |
| `agents/weather-agent.md` | `~/.cw/agents/` | Dubai weather fetcher via wttr.in |
| `hooks/scripts/hooks.py` | `~/.cw/hooks/` | Hook handler with audio notifications |
| `hooks/config/hooks-config.json` | `~/.cw/hooks/` | Hook event configuration |
| `hooks/sounds/` | `~/.cw/hooks/` | Sound effects for Claude Code events |

---

## All Commands

| Command | Description |
|---------|-------------|
| `cw work <project> <task\|URL>` | Work on feature/bug |
| `cw work <project> <task> --done` | Close task, cleanup |
| `cw review <project> <PR\|URL>` | Review PR |
| `cw review <project> <PR> --done` | Close review |
| `cw open <project>` | Quick open (no worktree) |
| `cw spaces` | Active spaces |
| `cw dashboard` | Full overview |
| `cw arcade` | Live activity dashboard |
| `cw arcade --setup` | Install activity hooks |
| `cw account add\|list\|remove` | Manage accounts |
| `cw project register\|list\|info` | Manage projects |
| `cw project setup-mcps <name>` | Configure MCPs |
| `cw project setup-agents <name>` | Install agents |
| `cw gsd:init [path]` | Initialize GSD workflow in a worktree |
| `cw gsd:sync` | Initialize GSD in all active worktrees |
| `cw --skip-permissions <cmd>` | Skip permission prompts |
| `cw version` | Show version |
| `cw help` | Full help |

## License

MIT
