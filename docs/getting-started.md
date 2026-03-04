# Getting Started

## Prerequisites

Before installing CW, make sure you have:

1. **Claude Code CLI** — Install via `npm install -g @anthropic-ai/claude-code` (see [docs](https://docs.anthropic.com/en/docs/claude-code))
2. **Git 2.15+** — For worktree support. Check: `git --version`
3. **Python 3.6+** — For JSON processing. Check: `python3 --version`
4. **Bash 4+ or Zsh** — Most modern systems have this
5. *(Optional)* **iTerm2** (macOS) — For tab coloring, badges, and window management

## Installation

```bash
git clone https://github.com/avarajar/cw.git
cd cw
./install.sh
```

The installer:
- Creates `~/.cw/` directory structure
- Copies scripts to `~/.cw/bin/` and `~/.cw/lib/`
- Adds `source ~/.cw/cw-shell-integration.sh` to your shell rc file
- Gives you `cw` in your PATH

## First-Time Setup

### 1. Initialize

```bash
cw init
```

### 2. Add Your Claude Account

```bash
cw account add work
```

This creates a config directory at `~/.cw/accounts/work/`. Then authenticate:

```bash
cw launch work
# In the Claude session: /login
```

If you have multiple accounts (work + personal), add them separately:

```bash
cw account add personal
cw launch personal
# /login with different credentials
```

### 3. Register Your Projects

```bash
cw project register ~/code/my-app --account work --type fullstack
cw project register ~/code/api-service --account work --type api
cw project register ~/code/blog --account personal --type knowledge
```

The `--account` flag links each project to a Claude account. CW will auto-route.

### 4. Verify

```bash
cw dashboard
```

You should see your accounts and registered projects.

## Your First Task

```bash
cw work my-app fix-login-bug
```

This:
1. Creates session metadata
2. Launches Claude in the project with the correct account
3. Claude creates a git worktree at `.tasks/fix-login-bug/`
4. Creates `TASK_NOTES.md` for persistent context

When you're done:

```bash
cw work my-app fix-login-bug --done
```

## Your First PR Review

```bash
cw review my-app 42
```

This:
1. Fetches PR #42 branch from remote
2. Creates a worktree at `my-app/.reviews/pr-42/`
3. Launches Claude with the correct account
4. Creates `REVIEW_NOTES.md` for findings

## What's Next

- Set up MCP integrations for Linear, GitHub, Notion (`cw project setup-mcps <name>`)
- Customize the [CLAUDE.md template](./claude-md.md) for your projects
- Learn about [session persistence](./architecture.md#session-persistence)
