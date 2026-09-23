# Changelog

## Unreleased

### Added

- `install.sh --no-shell` installs CW without adding the shell integration to `.zshrc` or
  `.bashrc`, for installers that run `~/.cw/bin/cw` by path. An unknown option now stops the
  installer before it copies anything.
- `cw work` records `base_branch` in a new task's `session.json`: the `origin/` ref its worktree
  starts from (`--base`, else the remote's default branch, else `origin/main`). Resumed sessions
  keep what they have; sessions created before this change have no `base_branch`.
- Every Claude Code launch links the global skills in `~/.claude/skills` into the account's config
  dir, since `CLAUDE_CONFIG_DIR` points Claude away from `~/.claude`. An account skill with the same
  name wins, links to removed skills are dropped on the next launch, and an account migrated to
  `accounts/<name>/claude` also gets its own `skills/` linked there.

### Changed

- `cw forge` runs Forge's npm package under its new name, `forge-cw` (`npx forge-cw`).

## 0.3.0

### Added

- Harness drivers: the same `cw work` / `review` / `loop` / `plan` / `create` / `open` flow runs
  on Claude Code, Codex CLI, Pi and OpenCode, routed through one driver layer
  (`lib/harnesses/<name>.sh`). **Only Claude Code has been run against a real installed binary.**
  Codex, Pi and OpenCode are exercised only through recording fakes in the test suite; the Pi
  driver in particular rests almost entirely on its documentation rather than a live install.
  See `README.md` and `docs/commands.md` for what's actually been verified before relying on one
  of the other three.
- `cw account login <account> --harness <h>` with `--no-browser` and `--with-api-key -`. What
  those two flags do depends on the harness — today only Codex honors `--no-browser` (it adds
  its own device-code flag) and only Codex has a confirmed `--with-api-key` import path.
- `cw account migrate <account> [--dry-run|-n] [--undo]` to move a flat account's Claude state
  into `<account>/claude/`, so an account can hold more than one harness's credentials at once.
  Purely opt-in and cosmetic — resolution already understands both layouts, so an account that
  never migrates keeps working exactly as before.
- `cw harness list` and `cw harness doctor` (the latter is an alias for `cw doctor`).
- `cw doctor --json` and `cw spaces --json` for machine-readable status.
- `--harness, -H <name>` on `work`, `review`, `loop`, `plan`, `create`, `open` and
  `project register`.
- Per-account provider and model fields, including local providers such as Ollama.
- `cw` fetches Linear, GitHub and Notion ticket content into `TASK_NOTES.md` itself, ahead of
  launching any harness (`LINEAR_API_KEY`, the `gh` CLI's own auth, `NOTION_TOKEN`), instead of
  relying solely on the harness's own MCP connectors. Falls back to the old MCP-based flow when
  no credential is configured.
- A bats test suite.

### Changed

- Every harness invocation goes through one driver layer; no launch site in `cw` spawns a
  harness binary directly (enforced by `tests/no_direct_launch.bats`).
- Every non-claude harness gets its own credential directory under the account root
  (`<account>/<harness>/`) automatically. Claude can move into its own `claude/` subdirectory
  too, but only via `cw account migrate` — see the `layout` contract change below, which
  tracks claude's placement specifically, not this general per-harness mechanism.

### Contract changes (breaking for `doctor --json` / `spaces --json` consumers)

- **`layout` in `cw doctor --json` is now three-valued: `legacy`, `split`, or `none`.** It was
  `legacy` or `split`. `legacy` has also been redefined to mean exactly "there is claude state at
  the account root that `cw account migrate` would move" rather than "this account uses the flat
  shape" — those used to be the same thing, but aren't once an account can hold no Claude state
  at all. A consumer written as `layout == "legacy" ? flat : split` now mishandles `none` and
  must be updated to check for it explicitly. `none` means no recognized Claude state at the
  account root — see the marker-list caveat below.
- `spaces --json` and `doctor --json` now include `harness`, `provider` and `model` per
  session/account. A session or account with none of these recorded reports harness `"claude"`
  and provider `"native"` (unchanged default behavior, now made explicit in the schema).

### Fixed

- `cw work` resolved `.git/info/exclude` relative to the directory it was run from, not the
  project: run from `$HOME` it created `~/.git/info/exclude`, and run from inside another
  repository it appended `.tasks`, `TASK_NOTES.md` and `SHARED_CONTEXT.md` to that repository's
  exclude, leaving the project's own untouched. It now writes to the project's shared git dir
  wherever it runs from, so the task files linked into a worktree stay out of `git status`.
- `cw stack`'s plugin probe and install ran against the ambient `~/.claude` instead of the
  account's own config directory (no `CLAUDE_CONFIG_DIR` was set), so a plugin present in the
  ambient config but absent from the account was wrongly reported as already installed and never
  installed into that account.
- `review` and `loop`'s fallback resume attempts (the `resume` → `continue` → `name` chain) did
  not carry `CW_PROJECT` / `CW_TASK` / `CW_TASK_TYPE` — only the first attempt in each chain did.
  A review resumed via a fallback (e.g. `--continue`, when resume-by-name failed) ran without
  `CW_TASK_TYPE=review` set, so the `review-autoclose` hook couldn't see it and the session never
  auto-closed on that path. All three attempts now export the same context, so autoclose fires
  regardless of which attempt in the chain actually succeeded.

### Behaviour on non-claude harnesses

- **`cw work` creates the task worktree itself.** On codex, pi, opencode and any user driver, a
  new `cw work` session runs `git fetch origin` and `git worktree add .tasks/<task>` before
  launching, on the branch the agent-driven prompt would have used: the task name, `task/<id>`
  for a GitHub issue or Notion page, the PR's head branch from `origin/<branch>` (resolved with
  `gh pr view <url> --json headRefName`), or the Linear issue's `branchName` when `cw` fetched
  it, else `task/<id>`. It links `TASK_NOTES.md`, `SHARED_CONTEXT.md`, and the root's `.env` and
  `.claude/` when the worktree lacks them, and launches the harness inside the worktree with a
  prompt that carries no setup steps. Claude keeps the agent-driven setup unchanged.
- **`cw` never deletes a branch.** Where the agent-driven prompt tells the agent to
  `git branch -D` an existing branch, `cw` attaches the new worktree to it as it is, so a stale
  branch is reused rather than restarted from the base branch. When `cw` falls back, the
  non-claude setup prompt asks the agent to attach the existing branch instead of deleting it.
  Claude's prompt keeps its `git branch -D` step.
- **A worktree `cw` cannot create falls back to the agent-driven setup.** No `origin`, a failed
  fetch, a missing start point, an invalid branch name, a branch checked out in another
  worktree, an unresolvable PR branch, or anything already at `.tasks/<task>`: `cw` prints one
  line, sends the setup prompt, and launches where the old flow did (the project root, unless
  something already exists at `.tasks/<task>`). `cw` claims `.tasks/<task>` with an atomic
  `mkdir` and on failure removes only what it claimed, so a second run of the same task never
  removes the first run's worktree, and no other worktree's registration is pruned. A branch
  `cw` had just created stays, and the warning names it.
- **Resume is attributable or fresh.** A session resumes only a conversation `cw` can attribute
  to it: a recorded harness session id, or — Codex only — `codex resume --last` inside the task's
  own worktree after the session has already run there. Because `cw` now creates that worktree
  before the first launch, a codex task can use `--last` from its first resume. Reviews, loops,
  and a task whose worktree `cw` could not create run in the shared project root, where "the
  last conversation here" may be another task's, so `--last` is never used there. OpenCode's
  `--continue` is not used at all. When nothing is attributable, `cw` prints one line and
  launches fresh with the resume prompt and a pointer to the notes file.
  Claude's `--resume` / `--continue` / `--name` chain is unchanged.
- **Codex session ids are captured from `$CODEX_HOME/sessions/`, unverified.** After a launch
  `cw` records the id of the one new rollout file that mentions the session's notes file. That
  file layout has not been checked against a real Codex install; if it differs, nothing is
  recorded and resume starts fresh as above. `session.json` also gains `harness_workdir` (the
  directory a non-claude harness last ran in) for this.
- **A resumed non-claude session keeps its account.** Without `--account`, `work`, `review` and
  `loop` resume on the account recorded in `session.json`. Claude sessions resolve the account
  exactly as before; `cw spaces` shows each session's own account and adds `--account` to the
  suggested resume command when it differs from the project's.
- **`cw loop` refuses on codex, pi and opencode.** It sends Claude Code's `/loop` command, which
  they do not have. `cw work` likewise asks them for a self-review in plain words instead of
  `/simplify`, and a harness without MCP is pointed at `TASK_NOTES.md` rather than told to fetch
  the ticket through a Linear or Notion MCP. Both are gated by capabilities (`slash_commands`,
  `mcp`); claude's prompts are byte-identical to before.
- **`cw account login` keeps the terminal.** The login runs attached to your terminal. Only
  `--no-browser` pipes it to emit `CW_LOGIN_URL=` / `CW_LOGIN_CODE=`, and only on a harness
  declaring `headless_login` (Codex); on claude, pi and opencode `--no-browser` is refused
  instead of silently ignored.
- **A provider the driver cannot apply is refused.** Only the codex and opencode drivers apply a
  non-native provider. An account with a provider on claude or pi (for example
  `cw account add free --harness pi --provider openrouter`) is warned about at `account add` and
  refused at launch, rather than run on the harness's own login while claiming to use the
  provider.
- **`CW_CLAUDE_FLAGS` applies to claude only.** Other harnesses read `CW_<HARNESS>_FLAGS`.
- **Drivers do not overwrite user files.** Codex's `config.toml` gets only its top-level `model`
  and `model_provider` lines set, with every other byte left in place; a file cw cannot safely
  edit is refused with an error. An existing `AGENTS.md` / `CLAUDE.md` is never replaced by the
  account instructions link, and an `opencode.json` that is not plain JSON is left alone.
- **`cw doctor --json` fills `issues` and `warnings`** from the same checks as the human report.

### Not built, or not verified

- **OpenCode's interactive session argv is unverified.** A new OpenCode session with a prompt is
  started with `opencode run "<prompt>"`, which is OpenCode's non-interactive mode: it runs the
  prompt and exits rather than opening the TUI. The right argv for an interactive session with
  an initial prompt has not been confirmed against a real install, so it has not been guessed.
- **The Anthropic-compatible provider path for claude (brief item 3c) was not built.** Claude
  never reads `CW_PROVIDER`; `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` routing for Z.ai,
  MiniMax or Moonshot does not exist, and `cw doctor` never reports `"unofficial": true`. An
  account with a provider on claude is refused at launch instead.
- **Pi applies no provider.** The pi driver does not translate `CW_PROVIDER`, so the brief's
  `cw account add free --harness pi --provider openrouter` example is refused at launch.

### Known limitations

- **Claude's `--continue` fallback still runs in the shared project root.** When resuming a
  claude session by name fails, `cw` runs `claude --continue` in the directory it opens in,
  which is the project root until the agent has created the task's worktree. There,
  `--continue` can reopen another task's claude conversation. This is the previous release's
  behaviour, kept so that a command without `--harness` behaves exactly as before; the
  never-guess resume rule above covers codex, pi and opencode only.
- **A claude session created with `--account X` resumes on the project's account.** Unless
  `--account X` is passed again, claude resolves the account as the previous release did. `cw
  spaces` shows the session's own account and puts `--account X` in the suggested resume
  command.
- **`codex resume --last` is assumed, not verified, to look only at the current directory.**
  `cw` offers it only inside a task's own worktree, and only after the session has run there;
  it is tried when no Codex session id was recorded (the rollout-file capture above is itself
  unverified) or when resuming the recorded id exits non-zero. Now that codex launches in its
  own worktree, a directory-scoped `--last` finds only that task's conversations. If `--last`
  is in fact global to `CODEX_HOME`, that protection is gone: it reopens the account's most
  recent Codex conversation, which can belong to another task or project. Unlike the other
  unverified assumptions in this release, this one does not fail safe, and it should be checked
  against a real Codex install before relying on codex resume.
- **`layout`/`legacy` recognition depends on a fixed marker list** (`CW_CLAUDE_MARKERS` in `cw`:
  `.claude.json`, `.credentials.json`, `settings.json`, `projects`, `todos`, `statsig`,
  `shell-snapshots`, `history.jsonl`, `ide`, `plugins`). An account whose Claude state carries
  none of these names reports `layout: "none"`, and `cw account migrate` reports "no claude
  state at its root — nothing to move" and exits 0 without moving anything, even though the
  account does have *some* state there. This is the safe failure direction (a no-op beats
  inventing an empty `claude/` that credential resolution would then trust), and in practice
  every account that has completed a real Claude login writes `.claude.json`, so it doesn't come
  up. If a future Claude release renames these files, `CW_CLAUDE_MARKERS` is the single place to
  update.
- **`cw account migrate` classifies root entries by name against a short deny-list**
  (`CW_ACCOUNT_OWNED`, every built-in harness, and every user driver in `~/.cw/harnesses/`), not
  by content. Anything added to
  that deny-list in the future must genuinely belong to `cw` itself — migration will neither move
  a misclassified entry into `claude/` nor report it as a leftover; it will simply look like it
  was never there.
- Codex, Pi and OpenCode drivers are unverified against real installs of those CLIs on the
  machine this release was built on. Treat them as code-reviewed, not field-tested, until
  someone runs `cw work`/`cw account login` against the genuine binary.

### Compatibility

Existing `~/.cw` layouts, `projects.json` and sessions keep working with no migration step. A
missing `harness` field means `claude`.
