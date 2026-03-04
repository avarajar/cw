# CW — Claude Workspace Manager

**Multi-project workspace orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with iTerm2 native integration.**

CW manages multiple Claude Code sessions across projects, accounts, and tasks — with isolated worktrees, persistent context, and automatic integration with Linear, Notion, and GitHub.

<!-- TODO: Add GIF demo here -->
<!-- ![CW Demo](docs/assets/demo.gif) -->

---

## Why CW?

If you work with Claude Code across multiple projects and accounts, you know the pain:

- **Account juggling** — switching `CLAUDE_CONFIG_DIR` for each project
- **Context loss** — Claude forgets what you were doing when you come back
- **Branch conflicts** — working on features while reviewing PRs in the same repo
- **Tab chaos** — 20 terminal tabs with no idea which is which

CW solves all of this:

| Problem | CW Solution |
|---------|------------|
| Multiple accounts | Auto-routes projects to the right Claude account |
| Context loss | Persistent `TASK_NOTES.md` / `REVIEW_NOTES.md` survives across sessions |
| Branch conflicts | Git worktrees isolate each task and PR review |
| Tab chaos | iTerm2 colored tabs with badges per project |
| Task setup | Paste a Linear/Notion/GitHub URL and Claude fetches context + creates the right branch |

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/avarajar/cw/main/install.sh | bash

# Initialize
cw init

# Add your Claude account(s)
cw account add work
cw account add personal   # optional

# Register a project
cw project register ~/code/my-app --account work

# Start working
cw work my-app fix-auth
```

## Core Commands

### `cw work <project> <task>`

Start or resume work on a feature/bug with an isolated worktree.

```bash
# With a task name (creates branch from main)
cw work my-app fix-auth

# With a Linear URL (fetches branch + context from Linear)
cw work my-app https://linear.app/team/issue/PROJ-123/fix-auth-flow

# With a Notion URL
cw work my-app https://notion.so/team/Auth-Redesign-abc123

# With a GitHub issue URL
cw work my-app https://github.com/org/repo/issues/42

# Resume (auto-detects existing session)
cw work my-app fix-auth

# Close when done (removes worktree, archives session)
cw work my-app fix-auth --done
```

**What happens:**

1. Detects source URL → extracts task ID (e.g., `PROJ-123`)
2. Opens Claude in the project with an init prompt
3. Claude uses the relevant MCP (Linear/GitHub/Notion) to fetch the issue details and branch name
4. Claude creates the git worktree at `.tasks/<task>/`
5. Claude fills `TASK_NOTES.md` with the issue context
6. You start working with full context

### `cw review <project> <PR>`

Review a PR with an isolated worktree.

```bash
# By PR number
cw review my-app 123

# By GitHub URL
cw review my-app https://github.com/org/repo/pull/123

# Resume
cw review my-app 123

# Close
cw review my-app 123 --done
```

### `cw open <project>`

Quick-open Claude in a project without worktrees or session tracking. For quick questions or exploration.

```bash
cw open my-app
```

### `cw spaces`

See all active tasks and reviews across all projects.

```bash
cw spaces
```

### `cw dashboard`

Full workspace overview: accounts, projects, active spaces.

```bash
cw dashboard
```

## Multi-Account Support

CW supports multiple Claude accounts. Each project is linked to an account, and CW automatically uses the right one.

```bash
# Add accounts
cw account add work
cw account add personal

# Register projects with specific accounts
cw project register ~/code/company-app --account work
cw project register ~/code/side-project --account personal

# CW auto-routes
cw work company-app feat-x    # → uses "work" account
cw work side-project feat-y   # → uses "personal" account
```

## How It Works

### Worktree Isolation

Each task gets its own git worktree — a physical copy of the repo at a specific branch. No `git checkout` conflicts, no stashing.

```
my-app/
├── src/                    # main branch (untouched)
├── .tasks/
│   ├── fix-auth/           # worktree: branch fix-auth
│   └── PROJ-123/           # worktree: branch from Linear
└── .reviews/
    └── pr-123/             # worktree: PR branch
```

### Session Persistence

Each space has metadata and notes stored outside of git:

```
~/.cw/sessions/<project>/
├── task-fix-auth/
│   ├── session.json        # metadata: account, branch, status, opens count
│   ├── TASK_NOTES.md       # persistent context (symlinked into worktree)
│   └── init_prompt.txt     # initial Claude prompt
└── review-pr-123/
    ├── session.json
    └── REVIEW_NOTES.md
```

Notes are **symlinked** into the worktree so Claude can read them, but they never touch git.

When you resume (`cw work my-app fix-auth` a second time):
- Claude starts with `--continue` to resume the conversation
- If the session is lost, Claude reads `TASK_NOTES.md` for context

### iTerm2 Integration

CW uses iTerm2 natively (no tmux):
- **Colored tabs** — each mode has a distinct color
- **Badges** — project/task name visible in the tab background
- **Auto-layout** — Claude tab + Shell tab per workspace

## Installation

### Requirements

- macOS with [iTerm2](https://iterm2.com/)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- Git 2.15+ (for worktree support)
- Python 3.6+ (for JSON processing)
- Bash 4+ or Zsh

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/avarajar/cw/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/avarajar/cw.git
cd cw
./install.sh
```

### Setup

```bash
# Initialize CW
cw init

# Add a Claude account
cw account add work
# → Follow prompts to authenticate: claude /login

# Register your projects
cw project register ~/code/my-app --account work --type fullstack
cw project register ~/code/api --account work --type api

# Verify
cw dashboard
```

### Shell Integration

The installer adds this to your `.zshrc` / `.bashrc`:

```bash
source ~/.cw/cw-shell-integration.sh
```

This gives you:
- `cw` in your PATH
- Tab completion for all commands, projects, and active tasks
- Aliases: `cww` (work), `cwpr` (review), `cwsp` (spaces)

## Configuration

### Project Types

```bash
cw project register <path> --type <type> --account <account>
```

Types: `fullstack`, `api`, `knowledge`, `infra`, `agents`

### CLAUDE.md Template

CW includes a template for project-level Claude instructions:

```bash
cp ~/.cw/templates/CLAUDE.template.md ~/code/my-app/CLAUDE.md
```

Key sections: Stack, Development commands, Conventions, Working with Claude, Do NOT.

### MCP Integrations

Set up MCPs per project for Linear, GitHub, Notion, Slack:

```bash
cw project setup-mcps my-app
```

## File Structure

```
~/.cw/
├── bin/cw                          # main script
├── lib/iterm2.sh                   # iTerm2 integration
├── cw-shell-integration.sh        # completions + aliases
├── accounts/
│   ├── work/                       # Claude config dir
│   └── personal/
├── sessions/
│   └── <project>/
│       └── task-<name>/
│           ├── session.json
│           └── TASK_NOTES.md
├── templates/
│   └── CLAUDE.template.md
└── projects.json                   # registered projects
```

## All Commands

| Command | Description |
|---------|------------|
| `cw work <project> <task>` | Work on feature/bug (worktree + session) |
| `cw work <project> <URL>` | Work from Linear/Notion/GitHub URL |
| `cw work <project> <task> --done` | Close task, archive session |
| `cw review <project> <PR>` | Review PR (worktree + session) |
| `cw review <project> <PR> --done` | Close review |
| `cw open <project>` | Quick open (no worktree) |
| `cw spaces` | Show all active spaces |
| `cw dashboard` | Full workspace overview |
| `cw account add <name>` | Add Claude account |
| `cw account list` | List accounts |
| `cw project register <path>` | Register project |
| `cw project list` | List projects |
| `cw project setup-mcps <name>` | Configure MCP integrations |
| `cw help` | Full help |

## License

MIT
