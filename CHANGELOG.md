# Changelog

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
- A bats test suite (214 tests as of this release).

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

### Known limitations

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
  (`CW_ACCOUNT_OWNED`, plus every name in `CW_HARNESS_ALL`), not by content. Anything added to
  that deny-list in the future must genuinely belong to `cw` itself — migration will neither move
  a misclassified entry into `claude/` nor report it as a leftover; it will simply look like it
  was never there.
- Codex, Pi and OpenCode drivers are unverified against real installs of those CLIs on the
  machine this release was built on. Treat them as code-reviewed, not field-tested, until
  someone runs `cw work`/`cw account login` against the genuine binary.

### Compatibility

Existing `~/.cw` layouts, `projects.json` and sessions keep working with no migration step. A
missing `harness` field means `claude`.
