# Architecture

## Overview

CW is a Bash CLI that orchestrates Claude Code sessions with iTerm2. It manages three concerns:

1. **Account routing** — maps projects to Claude accounts
2. **Workspace isolation** — uses git worktrees for parallel work
3. **Session persistence** — notes files survive conversation loss

## Directory Structure

```
~/.cw/
├── bin/
│   └── cw                          # main script (~1500 lines bash)
├── cw-shell-integration.sh         # PATH, completions, aliases
├── accounts/
│   ├── work/                       # CLAUDE_CONFIG_DIR for "work"
│   │   ├── settings.json
│   │   └── ...
│   └── personal/
├── sessions/
│   └── <project>/
│       ├── task-<name>/
│       │   ├── session.json        # metadata
│       │   ├── TASK_NOTES.md       # persistent context
│       │   └── init_prompt.txt     # first-run prompt
│       └── review-pr-<N>/
│           ├── session.json
│           └── REVIEW_NOTES.md
├── templates/
│   └── CLAUDE.template.md
├── projects.json                   # { "name": { path, account, type } }
└── cw.log                          # session open log
```

## Worktree Strategy

Each task/review gets its own [git worktree](https://git-scm.com/docs/git-worktree) — a physical directory linked to a branch, sharing the same `.git` history.

```
my-app/                             # main branch (untouched)
├── src/
├── .tasks/
│   ├── fix-auth/                   # worktree → branch: fix-auth
│   │   ├── src/
│   │   └── TASK_NOTES.md → symlink
│   └── PROJ-123/                   # worktree → branch from Linear
│       ├── src/
│       └── TASK_NOTES.md → symlink
└── .reviews/
    └── pr-42/                      # worktree → PR branch
        ├── src/
        └── REVIEW_NOTES.md → symlink
```

**Why worktrees?**
- No `git checkout` switching — work on multiple branches simultaneously
- No stashing — each worktree has its own working directory
- Shared object store — no disk duplication of git history
- Proper isolation — one broken build doesn't affect another

**Git exclude:** `.tasks/`, `.reviews/`, and `*_NOTES.md` are added to `.git/info/exclude` (per-repo, not committed to `.gitignore`).

## Session Persistence

Claude Code's `--continue` flag resumes the last conversation. But sessions can be lost if:
- Too much time passes
- Claude is opened elsewhere with the same account
- The conversation exceeds context limits

CW provides a fallback: `TASK_NOTES.md` / `REVIEW_NOTES.md` files that Claude reads on startup. Even if the conversation is gone, the context survives.

### Session Lifecycle

```
NEW: cw work app fix-auth
  → create session dir + session.json
  → create TASK_NOTES.md (symlinked to worktree)
  → save init_prompt.txt
  → open Claude with init prompt
  → Claude creates worktree + fetches context

RESUME: cw work app fix-auth (2nd time)
  → update session.json (opens++, last_opened)
  → open Claude with --continue
  → Claude reads TASK_NOTES.md if session is lost

DONE: cw work app fix-auth --done
  → remove worktree
  → archive session (status: done)
  → branch remains for PR
```

### Session Metadata (session.json)

```json
{
  "project": "my-app",
  "task": "fix-auth",
  "type": "task",
  "account": "work",
  "branch": "joselito/proj-123-fix-auth",
  "worktree": "/path/to/.tasks/fix-auth",
  "notes": "/path/to/sessions/.../TASK_NOTES.md",
  "source": "linear",
  "source_url": "https://linear.app/...",
  "status": "active",
  "created": "2025-01-15T10:00:00Z",
  "last_opened": "2025-01-15T14:30:00Z",
  "opens": 3
}
```

## URL Integration

When a URL is passed as the task argument, CW detects the source and adjusts the init prompt:

| Source | Detection | Extracted ID | Branch Strategy |
|--------|-----------|-------------|----------------|
| Linear | `linear.app` in URL | `ABC-123` regex | Fetched from Linear issue via MCP |
| GitHub | `github.com` + `issues`/`pull` | Issue/PR number | PR branch or `task/<id>` |
| Notion | `notion.so` or `notion.site` | Page slug | `task/<slug>` |
| Plain text | No URL detected | Used as-is | Used as branch name directly |

Claude handles the actual MCP calls and worktree creation via the init prompt.

## Account Routing

Each project maps to an account in `projects.json`:

```json
{
  "my-app": {
    "path": "/Users/you/code/my-app",
    "account": "work",
    "type": "fullstack"
  }
}
```

When you run `cw work my-app fix-auth`, CW:
1. Looks up `my-app` in `projects.json`
2. Finds `account: "work"`
3. Sets `CLAUDE_CONFIG_DIR=~/.cw/accounts/work`
4. Launches Claude with that config

No manual account switching needed.
