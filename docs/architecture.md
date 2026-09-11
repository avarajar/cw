# Architecture

## Overview

CW is a Bash CLI that orchestrates coding-agent sessions (Claude Code and others) with iTerm2.
It manages four concerns:

1. **Account routing** — maps projects to accounts
2. **Harness routing** — maps each account to a coding-agent CLI ("harness") through a driver
   layer, so `cw work`/`review`/`loop`/`plan`/`create`/`open` run the same way on Claude Code,
   Codex CLI, Pi or OpenCode. See [harness-drivers.md](harness-drivers.md) for the driver
   contract and capability enumeration.
3. **Workspace isolation** — uses git worktrees for parallel work
4. **Session persistence** — notes files survive conversation loss

## Directory Structure

```
~/.cw/
├── bin/
│   └── cw                          # main script (~2500 lines bash)
├── cw-shell-integration.sh         # PATH, completions, aliases
├── accounts/
│   ├── work/                       # flat layout — the account root IS Claude's config dir
│   │   ├── settings.json
│   │   ├── meta.json               # harness, provider, model per harness (cw-owned)
│   │   └── ...
│   └── personal/                   # split layout — one subdir per harness
│       ├── meta.json
│       ├── claude/                 # CLAUDE_CONFIG_DIR for "personal" on claude
│       └── codex/                  # CODEX_HOME for "personal" on codex
├── sessions/
│   └── <project>/
│       ├── SHARED_CONTEXT.md       # shared across all worktrees
│       ├── task-<name>/
│       │   ├── session.json        # metadata (incl. workflow field)
│       │   ├── TASK_NOTES.md       # persistent context
│       │   └── init_prompt.txt     # first-run prompt
│       └── review-pr-<N>/
│           ├── session.json
│           └── REVIEW_NOTES.md
├── templates/
│   ├── CLAUDE.template.md
│   └── workflows/              # workflow templates (feature, bugfix, refactor, etc.)
├── projects.json                   # { "name": { path, account, type } }
└── cw.log                          # session open log
```

An account has one of two layouts, and `cw` resolves both the same way through `_harness_dir`:

- **Flat (legacy)** — the account root itself holds Claude's state (`.claude.json`,
  `settings.json`, ...). This is what every pre-0.3.0 account looks like, and it keeps working
  with no migration step; `claude` is the only harness a flat account can hold.
- **Split** — a `<harness>/` subdirectory under the account root holds that harness's
  credential dir (`claude/`, `codex/`, ...). An account created with `--harness` other than
  `claude`, or one moved with `cw account migrate`, uses this layout. Multiple harnesses can
  coexist on one account, each in its own subdirectory.

`cw doctor --json` reports which layout an account is in as `legacy`, `split`, or `none` (no
recognized Claude state in either place — see [Account Routing](#account-routing)).

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
  "harness": "claude",
  "provider": "native",
  "model": "sonnet",
  "workflow": "bugfix",
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

## Shared Context

When working on multiple tasks for the same project, worktrees can share context via `SHARED_CONTEXT.md`:

```
~/.cw/sessions/my-app/
├── SHARED_CONTEXT.md           # shared across all worktrees
├── task-fix-auth/
│   └── ...
└── task-add-tests/
    └── ...
```

The file is auto-created on the first `cw work` for a project and symlinked into every worktree. When one worktree discovers something relevant to others (schema changes, API changes, conventions), Claude updates `SHARED_CONTEXT.md` — and other worktrees see it immediately.

This is inspired by multi-agent memory sharing, adapted for CW's worktree-per-task model.

## Workflow Templates

Workflows provide structured instructions for different types of work. When you run `cw work my-app fix-auth --workflow bugfix`, the bugfix workflow template is appended to the init prompt, guiding Claude through a reproduce → root cause → fix → test → verify process.

Templates live in `~/.cw/templates/workflows/`:

```
~/.cw/templates/workflows/
├── feature.md          # design-first feature development
├── bugfix.md           # reproduce-first bug fixing
├── refactor.md         # test-driven refactoring
├── security-audit.md   # OWASP-based security review
└── docs.md             # audience-first documentation
```

Templates are generated by `cw init` and fully customizable. The workflow type is stored in `session.json` for tracking via `cw stats`.

## URL Integration

When a URL is passed as the task argument, CW detects the source and adjusts the init prompt:

| Source | Detection | Extracted ID | Branch Strategy |
|--------|-----------|-------------|----------------|
| Linear | `linear.app` in URL | `ABC-123` regex | `task/<id>` |
| GitHub | `github.com` + `issues`/`pull` | Issue/PR number | PR branch or `task/<id>` |
| Notion | `notion.so` or `notion.site` | Page slug | `task/<slug>` |
| Plain text | No URL detected | Used as-is | Used as branch name directly |

`cw` fetches the ticket content itself, before launching any harness — Linear via
`LINEAR_API_KEY`, GitHub via the `gh` CLI's own auth, Notion via `NOTION_TOKEN` — and writes it
straight into `TASK_NOTES.md`. This is what makes the URL flow harness-agnostic: the context is
already on disk by the time the agent starts, so it doesn't depend on that harness having a
matching MCP connector. If no credential is configured for that source, `cw` falls back to its
older behavior and asks the agent to fetch it and fill in `TASK_NOTES.md` itself via MCP — the
agent then handles the worktree creation and the fetch via the init prompt, same as before.

## Account Routing

Each project maps to an account in `projects.json`, with an optional `harness` override:

```json
{
  "my-app": {
    "path": "/Users/you/code/my-app",
    "account": "work",
    "type": "fullstack",
    "harness": "codex"
  }
}
```

When you run `cw work my-app fix-auth`, CW:
1. Looks up `my-app` in `projects.json`
2. Finds `account: "work"` (and `harness: "codex"`, or the account's own default harness if the
   project doesn't set one; `--harness` on the command line overrides both)
3. Resolves the credential directory with `_harness_dir <account> <harness>` — for `claude` on a
   flat account this is the account root itself (`~/.cw/accounts/work`), otherwise it's
   `~/.cw/accounts/work/<harness>`
4. Sets that harness's config-dir env var (`CLAUDE_CONFIG_DIR` for claude, `CODEX_HOME` for
   codex, and so on — each driver declares its own in `<h>_config_env`) and launches it through
   the driver layer

No manual account switching, and no hard-coded `CLAUDE_CONFIG_DIR`, needed.

A running session remembers the harness it was created with (`session.json`'s `harness` field)
and resuming it always uses that harness — `--harness` on a later `cw work` for the same task is
only honored if it matches, otherwise `cw` refuses rather than silently switching agents
mid-session.
