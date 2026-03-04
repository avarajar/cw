# CW — Claude Workspace Manager

**Multi-project workspace orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).**

CW manages multiple Claude Code sessions across projects, accounts, and tasks — with isolated worktrees, persistent context, and automatic integration with Linear, Notion, and GitHub.

<!-- TODO: Add GIF demo here -->
<!-- ![CW Demo](docs/assets/demo.gif) -->

---

## Why CW?

If you work with Claude Code across multiple projects and accounts, you know the pain:

- Switching `CLAUDE_CONFIG_DIR` for every project
- Claude forgetting what you were doing when you come back
- Branch conflicts when working on features while reviewing PRs
- Manually copying ticket descriptions into context

CW fixes all of that with one command:

```bash
cw work my-app https://linear.app/team/issue/PROJ-123/fix-auth-flow
```

Claude launches with the right account, fetches the ticket from Linear, creates a worktree on the correct branch, and starts working with full context.

## Quick Start

```bash
# Install
git clone https://github.com/avarajar/cw.git && cd cw && ./install.sh

# Setup
cw init
cw account add work              # creates a Claude account profile
cw project register ~/code/my-app --account work

# Work
cw work my-app fix-auth          # launches Claude right here
```

## Core Commands

### `cw work <project> <task>`

Start or resume a feature/bug. CW creates an isolated worktree, tracks the session, and launches Claude in your current terminal.

```bash
cw work my-app fix-auth                                  # branch name
cw work my-app https://linear.app/team/issue/PROJ-123    # Linear URL
cw work my-app https://github.com/org/repo/issues/42     # GitHub issue
cw work my-app https://notion.so/team/Auth-Redesign      # Notion page

cw work my-app fix-auth             # resume (--continue)
cw work my-app fix-auth --done      # close + cleanup
```

When you pass a URL, Claude uses the relevant MCP (Linear, GitHub, Notion) to fetch issue details, find the branch name, create the worktree, and populate `TASK_NOTES.md` with context — all automatically.

### `cw review <project> <PR>`

Review a PR in an isolated worktree.

```bash
cw review my-app 123
cw review my-app https://github.com/org/repo/pull/123
cw review my-app 123 --done
```

### `cw open <project>`

Quick-open Claude in a project. No worktree, no session tracking.

```bash
cw open my-app
```

### `cw spaces`

List all active tasks and reviews across projects.

### `cw dashboard`

Full workspace overview: accounts, projects, active spaces.

## Multi-Account Support

Each project is linked to a Claude account. CW auto-routes.

```bash
cw account add work
cw account add personal

cw project register ~/code/company-app --account work
cw project register ~/code/side-project --account personal

cw work company-app feat-x     # uses "work" account
cw work side-project feat-y    # uses "personal" account
```

## How It Works

### Worktree Isolation

Each task gets its own [git worktree](https://git-scm.com/docs/git-worktree) — no `checkout` conflicts, no stashing.

```
my-app/
├── src/                    # main branch (untouched)
├── .tasks/
│   ├── fix-auth/           # worktree → fix-auth branch
│   └── PROJ-123/           # worktree → branch from Linear
└── .reviews/
    └── pr-123/             # worktree → PR branch
```

### Session Persistence

Notes and metadata live outside git in `~/.cw/sessions/`:

```
~/.cw/sessions/my-app/
├── task-fix-auth/
│   ├── session.json        # metadata, status, opens count
│   ├── TASK_NOTES.md       # persistent context (symlinked into worktree)
│   └── init_prompt.txt     # initial Claude prompt
└── review-pr-123/
    ├── session.json
    └── REVIEW_NOTES.md
```

`TASK_NOTES.md` is symlinked into the worktree so Claude can read it, but it never touches git. When you resume, Claude uses `--continue`. If the conversation is lost, the notes file preserves context.

### URL → Context Flow

```
cw work my-app https://linear.app/.../PROJ-123
  ↓
Parse URL → detect Linear → extract PROJ-123
  ↓
Launch Claude with init prompt:
  "Fetch PROJ-123 from Linear MCP, get the branch,
   create worktree, fill TASK_NOTES.md"
  ↓
Claude handles everything interactively
```

## Installation

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git 2.15+
- Python 3.6+
- Bash 4+ or Zsh

### Install

```bash
git clone https://github.com/avarajar/cw.git
cd cw
./install.sh
```

### Setup

```bash
cw init
cw account add work
cw launch work                 # authenticate: /login

cw project register ~/code/my-app --account work
cw dashboard                   # verify
```

### Shell Integration

The installer adds to your `.zshrc` / `.bashrc`:

```bash
source ~/.cw/cw-shell-integration.sh
```

This gives you tab completion for commands, projects, and active tasks, plus aliases: `cww` (work), `cwpr` (review), `cwsp` (spaces).

## Team Setup

CW is the shared tool. Everything personal stays local.

**Shared (this repo):** `cw`, `install.sh`, `cw-shell-integration.sh`, templates, docs.

**Personal (each member):** `~/.cw/accounts/`, `~/.cw/projects.json`, `~/.cw/sessions/`.

Each team member clones the repo, runs `install.sh`, then registers their own projects with their own accounts. Project paths don't need to match.

## File Structure

```
~/.cw/
├── bin/cw                          # main script
├── cw-shell-integration.sh         # completions + aliases
├── accounts/
│   ├── work/                       # Claude config dir
│   └── personal/
├── sessions/
│   └── <project>/
│       └── task-<n>/
│           ├── session.json
│           └── TASK_NOTES.md
├── templates/
│   └── CLAUDE.template.md
└── projects.json                   # registered projects
```

## All Commands

| Command | Description |
|---------|------------|
| `cw work <project> <task\|URL>` | Work on feature/bug (worktree + session) |
| `cw work <project> <task> --done` | Close task, archive session |
| `cw review <project> <PR\|URL>` | Review PR (worktree + session) |
| `cw review <project> <PR> --done` | Close review |
| `cw open <project>` | Quick open Claude in project |
| `cw spaces` | Show all active spaces |
| `cw dashboard` | Full workspace overview |
| `cw account add <n>` | Add Claude account |
| `cw account list` | List accounts |
| `cw project register <path>` | Register project |
| `cw project list` | List projects |
| `cw project setup-mcps <n>` | Configure MCP integrations |
| `cw help` | Full help |

## License

MIT
