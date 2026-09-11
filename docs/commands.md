# Commands Reference

## Harnesses

Most commands below accept `--harness, -H <name>` to run on a specific coding-agent CLI instead
of the account's default one: `claude`, `codex`, `pi`, or `opencode`. **Only `claude` has been
run against a real installed binary.** `codex`, `pi` and `opencode` each have a driver
(`lib/harnesses/<name>.sh`) that is tested against recording fakes, not a live install of that
CLI — treat their commands below as reviewed, not field-proven, until you run them yourself.
`cw harness list` shows which of the four are actually installed on your machine.

## Main Commands

### `cw work <project> <task|URL> [--done]`

Work on a feature or bug with an isolated worktree and persistent session.

**Arguments:**
- `project` — registered project name
- `task` — branch name, ticket ID, or URL (Linear, Notion, GitHub)
- `--workflow, -w <type>` — apply workflow template (`feature`, `bugfix`, `refactor`, `security-audit`, `docs`)
- `--harness, -H <name>` — run this task on a specific harness (`claude` \| `codex` \| `pi` \| `opencode`); resuming an existing session with a different `--harness` than it was created with fails instead of switching agents mid-session
- `--done` — close the task, remove worktree, archive session
- `--list` — list active tasks (optionally filtered by project)

**Examples:**
```bash
cw work my-app fix-auth                        # plain branch name
cw work my-app fix-auth --workflow bugfix      # with bugfix workflow
cw work my-app PROJ-123 -w feature             # feature workflow
cw work my-app https://linear.app/.../PROJ-123 # fetch from Linear
cw work my-app fix-auth                        # resume existing
cw work my-app fix-auth --done                 # close and cleanup
cw work --list                                 # list all active tasks
cw work my-app --list                          # list tasks for project
```

**URL behavior:**

| URL Source | What happens |
|-----------|-------------|
| Linear | Extracts issue ID; `cw` fetches title, description and comments via `LINEAR_API_KEY` and writes them into `TASK_NOTES.md` before launching |
| GitHub | Extracts issue/PR number; `cw` fetches it via the `gh` CLI's own auth |
| Notion | Extracts page slug; `cw` fetches page content via `NOTION_TOKEN` |

Credentials can be set as env vars or in `~/.cw/tokens.env` (`LINEAR_API_KEY=...`,
`NOTION_TOKEN=...`; GitHub uses whatever account `gh` is already logged into). If none is
configured for that source, `cw` falls back to asking the agent to fetch the content itself over
MCP, same as before this fetch existed — so MCP connectors are still worth setting up as a
fallback, not required.

---

### `cw review <project> <PR|URL> [--done]`

Review a PR with an isolated worktree.

**Arguments:**
- `project` — registered project name
- `PR` — PR number or GitHub PR URL
- `--harness, -H <name>` — run this review on a specific harness
- `--done` — close the review, remove worktree, archive session
- `--list` — list active reviews

**Examples:**
```bash
cw review my-app 42                            # by PR number
cw review my-app https://github.com/.../pull/42 # by URL
cw review my-app 42                            # resume
cw review my-app 42 --done                     # close
```

---

### `cw open <project>`

Quick-open the project's harness. No worktree, no session tracking.

```bash
cw open my-app
cw open my-app --harness codex     # open on a specific harness instead
```

---

### `cw spaces [project] [--json]`

Show all active tasks and reviews across all projects, grouped by project.

```bash
cw spaces
cw spaces --json     # machine-readable list, for scripts/dashboards
```

`--json` prints `{"schema": 1, "spaces": [...]}`, one object per active task/review with
`project`, `account`, `type`, `id`, `harness`, `provider`, `model`, `opens`, `last_opened`,
`worktree`, `resume` and `close` (the two commands to run). A session with no `harness` recorded
(pre-0.3.0 sessions) reports `"claude"`; no `provider` recorded reports `"native"`.

---

### `cw dashboard`

Full workspace overview: accounts, projects with status indicators, active spaces.

```bash
cw dashboard
```

**Workflow templates:**

| Workflow | Focus |
|----------|-------|
| `feature` | Design-first development with acceptance criteria checklist |
| `bugfix` | Reproduce → root cause → minimal fix → regression test |
| `refactor` | Test-driven, no behavior changes, incremental steps |
| `security-audit` | OWASP Top 10, dependency scan, secret detection |
| `docs` | Audience-first, tested examples, verified links |

Templates are customizable at `~/.cw/templates/workflows/`.

**Shared context:** All worktrees in the same project share a `SHARED_CONTEXT.md` file (auto-symlinked). Cross-task discoveries are visible to all worktrees immediately.

---

### `cw plan <project> "<description>"`

Plan a large task by having Claude analyze the codebase and split the goal into independent sub-tasks.

```bash
cw plan my-app "migrate auth to OAuth2"
cw plan my-app "add payment processing with Stripe"
cw plan my-app "migrate auth to OAuth2" --harness codex   # plan on a specific harness
```

Claude (or the chosen harness) reads the project structure, proposes 2-6 sub-tasks with branch names, key files, dependencies, and suggested workflows. Then asks if you want to create worktrees for each.

---

### `cw doctor [--json]`

Health check for your CW setup. Verifies:
- Required tools (git, python3, claude CLI)
- CW initialization and config
- Account authentication status
- Project path validity
- Workflow templates
- Stale sessions and orphaned worktrees

```bash
cw doctor
cw doctor --json | python3 -m json.tool
```

`--json` prints a stable schema instead of the human report:

```json
{
  "schema": 1,
  "cw_version": "0.3.0",
  "cw_home": "/Users/you/.cw",
  "generated": "2026-09-10T00:00:00Z",
  "harnesses": [
    {"name": "claude", "installed": true, "path": "/usr/local/bin/claude", "version": "...", "source": "builtin"}
  ],
  "accounts": [
    {
      "name": "work", "root": "/Users/you/.cw/accounts/work",
      "layout": "legacy", "default_harness": "claude",
      "harnesses": [
        {"harness": "claude", "status": "connected", "detail": null,
         "config_env": "CLAUDE_CONFIG_DIR", "config_dir": "...",
         "provider": "native", "provider_kind": "native", "model": null,
         "has_api_key": false, "unofficial": false}
      ]
    }
  ],
  "issues": [], "warnings": []
}
```

**`layout` is three-valued, not a boolean, and it describes only claude's own state** — it says
nothing about whether other harnesses on the same account have their own subdirectories:

| Value | Meaning |
|---|---|
| `split` | a `claude/` subdirectory exists under the account root |
| `legacy` | no `claude/` subdirectory, but recognized Claude state sits at the account root — `cw account migrate` has work to do |
| `none` | no `claude/` subdirectory and no recognized Claude state at the root |

`none` is new in 0.3.0. A consumer that used to treat `layout` as `legacy ? flat : split` must
now handle `none` explicitly — it does **not** mean "flat"; it means the account has no Claude
config in either place. An account created with `--harness codex`/`pi`/`opencode` and never
touched by claude reports `none` even though it has its own `codex/`/`pi/`/`opencode/`
subdirectory — that subdirectory is not what `layout` is reporting on.

`legacy`/`none` are decided by whether the account root contains a name from a fixed marker list
(`.claude.json`, `.credentials.json`, `settings.json`, `projects`, `todos`, `statsig`,
`shell-snapshots`, `history.jsonl`, `ide`, `plugins` — `CW_CLAUDE_MARKERS` in `cw`). If Claude
ever renames or adds to these files, an account with only the new name(s) will incorrectly
report `none` (and `cw account migrate` will report there's nothing to move and exit 0, rather
than actually migrating anything) until `CW_CLAUDE_MARKERS` is updated — that constant is the
single place to fix. This is a known, accepted gap: reporting `none` is the safe failure
direction (it never invents an empty
`claude/` that credential resolution would then trust), and any account that has actually
completed a Claude login always writes `.claude.json`, so it doesn't apply in practice.

Each harness's `status` in the matrix is one of `connected`, `not_logged_in`, `not_installed`,
`local` (a local provider like Ollama — no login needed), or `error` (no driver for that
harness, or the driver produced no output).

---

### `cw stats [project]`

Session metrics and productivity stats.

```bash
cw stats                # all projects
cw stats my-app         # single project
```

Shows: total/active/done sessions, task/review counts, average opens, average duration for completed sessions, completion rate, and workflow usage.

---

## Setup Commands

### `cw init`

Initialize CW directory structure at `~/.cw/`.

### `cw account add <name> [options]`

Create a new account profile.

**Options:**
- `--harness, -H <name>` — harness this account uses by default (`claude` \| `codex` \| `pi` \| `opencode`); defaults to `claude`
- `--provider, -p <name>` — provider for that harness (`native`, `ollama`, `lmstudio`, `llamacpp`, or any other name — anything not `native`/local is treated as a remote API provider)
- `--model, -m <name>` — default model for that harness/provider

```bash
cw account add work                                          # claude, native provider
cw account add glm --harness opencode --provider zai --model glm-5.1
cw account add local --harness opencode --provider ollama --model qwen3-coder:14b
```

After creation, authenticate it (skip this for a `local` provider like Ollama — no login needed):

```bash
cw account login work --harness claude
```

### `cw account list`

List all configured accounts.

### `cw account remove <name>`

Remove an account profile.

### `cw account login <name> [options]`

Authenticate an account against a harness.

**Options:**
- `--harness, -H <name>` — which harness to log in; defaults to the account's own default harness
- `--no-browser` — print a URL or device code instead of opening a browser (only honored today by harnesses with a device-code flow — Codex adds `--device-auth`; claude, pi and opencode ignore this flag and always run their normal interactive login)
- `--with-api-key -` — read an API key from stdin instead of an interactive login; only works on a harness with an API-key import path (Codex today)

```bash
cw account login work --harness claude
cw account login monoku --harness codex --no-browser
printf '%s' "$API_KEY" | cw account login monoku --harness codex --with-api-key -
```

An API key given this way is written to `<harness dir>/env` with `chmod 600` and never appears
in `config.yaml`, `meta.json`, or process argv.

### `cw account migrate <name> [--dry-run|-n] [--undo]`

Move a flat account's Claude state (everything at the account root that isn't cw's own
`meta.json`/`CLAUDE.md`/`templates`/`skills` or another harness's own subdirectory) into
`<account>/claude/`, so claude's credentials sit in their own subdirectory the same way every
other harness's already do. An account does **not** need this to run more than one harness —
`codex`/`pi`/`opencode` each always get their own subdirectory regardless of claude's layout —
so `migrate` is purely cosmetic tidying that only affects where claude's own state lives.

```bash
cw account migrate work --dry-run    # list what would move, touch nothing
cw account migrate work              # move it
cw account migrate work --undo       # move it back to the flat layout
```

Resolution (`_harness_dir`) already understands both of claude's layouts, forever — an account
that stays flat keeps working exactly as before, so running `migrate` is entirely optional. When
it finds no recognized Claude state at the root, it reports there's nothing to move and exits 0
(an idempotent no-op, not an error) rather than inventing an empty `claude/` — see the
`layout: "none"` note under `cw doctor --json` above for what "recognized" means and its one
known edge case.

**A maintenance note for anyone extending `cw` itself:** the deny-list of names migration never
touches (`meta.json`, `CLAUDE.md`, `templates`, `skills`, plus every harness's own subdirectory
name) must only ever contain things `cw` genuinely owns. If a future change starts writing a new
file into the account root and that name isn't added to the deny-list, `migrate` will neither
move it into `claude/` nor report it as a leftover — it will just look like it isn't there.

### `cw harness list`

Show the four harnesses `cw` knows about and whether each is installed on this machine (found on
`PATH`).

```bash
cw harness list
```

### `cw harness doctor`

Alias for `cw doctor` — see its `--json` section above for the per-account, per-harness detail.

### `cw project register <path> [options]`

Register a project directory.

**Options:**
- `--account, -a <name>` — account to use
- `--type, -t <type>` — Project type: `fullstack`, `api`, `knowledge`, `infra`, `agents`
- `--alias <name>` — custom project name (default: folder name)
- `--harness, -H <name>` — pin this project to a harness, overriding the account's default; a session created for this project uses this harness unless `cw work ... --harness` overrides it again

```bash
cw project register ~/code/my-app --account work --type fullstack
cw project register ~/code/api-service --account work --harness codex
```

### `cw project list`

List all registered projects.

### `cw project setup-mcps <name>`

Interactive setup of MCP integrations (GitHub, Linear, Notion, Slack) for a project.

### `cw project setup-agents <name>`

Install agents and commands for a project.

### `cw project info <name>`

Show detailed project information.

---

## Utility Commands

### `cw launch <account> [args]`

Quick-launch a harness with a specific account, passing `[args]` straight through. Useful for
poking at an account interactively.

```bash
cw launch work
cw launch personal
CW_HARNESS=codex cw launch work    # launch a different harness (no --harness flag here)
```

`cw launch` does not take `--harness` — it only reads the `CW_HARNESS` environment variable
(falling back to `claude`, not to the account's own configured default harness). For
authentication, prefer `cw account login <name> --harness <h>`, which does resolve the account's
default and drives the harness's own login flow.

### `cw status`

Quick status: account count, project count, active spaces.

### `cw help`

Full command reference.

---

## Shell Aliases

Available after sourcing `cw-shell-integration.sh`:

| Alias | Command | Description |
|-------|---------|-------------|
| `cww` | `cw work` | Work on task with worktree |
| `cwpr` | `cw review` | PR review with worktree |
| `cwsp` | `cw spaces` | Show active spaces |
| `cwd` | `cw dashboard` | Full workspace overview |
| `cws` | `cw status` | Quick status |
| `cwrl` | `cw review --list` | List active reviews |
| `cwl` | `cw project list` | List projects |
| `cwc` | `cw open <project> --mode code` | Open in code mode |
| `cwr` | `cw open <project> --mode review` | Open in review mode |
| `cwi` | `cw open <project> --mode research` | Open in research mode |
| `cwdoc` | `cw open <project> --mode docs` | Open in docs mode |
| `cwp` | `cw open <project> --mode planning` | Open in planning mode |
| `cwm` | `cw open <project> --mode comms` | Open in comms mode |
| `cwf` | `cw open <project> --mode full` | Open in full mode |
| `cwo` | Fuzzy project opener | Requires `fzf` |
| `cc` | `cw launch` | Quick launch Claude |
