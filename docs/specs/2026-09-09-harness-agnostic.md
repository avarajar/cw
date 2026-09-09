# Spec: harness-agnostic workflows

**Status:** draft for review
**Date:** 2026-09-09
**Brief:** `docs/plans/2026-09-09-harness-agnostic-brief.md`
**Target version:** 0.3.0

## 1. Goal

The same `cw work` / `cw review` / `cw loop` / `cw plan` / `cw create` / `cw open` flow runs on
any coding-agent harness: Claude Code, Codex CLI, Pi, OpenCode. A harness is a driver file, not
a flag. After this release exactly one function in `cw` spawns a harness binary.

Everything a user has today keeps working with no migration step and no change in behaviour.

## 2. Decisions

These were settled during brainstorming. Items marked *(assumed)* were taken on the
recommendation of the analysis and are called out here so they can be reviewed in one pass.

| # | Decision |
|---|---|
| A1 | Account dirs are resolved, not moved. `accounts/<name>/claude/` if it exists, else `accounts/<name>`. No silent migration. |
| A2 | Account-root `CLAUDE.md` becomes a CW concept: the driver installs it into the harness's own instruction slot. *(assumed)* |
| A3 | CW-owned per-account files live at the account root and are harness-neutral. *(assumed)* |
| A4 | `cw mcp` stays Claude-only this release, gated by capability. *(assumed)* |
| B1 | Seven driver functions. *(assumed)* |
| B2 | Drivers build argv + env; one shared `_harness_exec` spawns. *(assumed)* |
| B3 | Fixed capability enumeration, unknown capability = unsupported. *(assumed)* |
| B4 | Driver search order: `$CW_HOME/harnesses/` then the repo `lib/harnesses/`. *(assumed)* |
| B5 | `CLAUDE.md`'s "single-file architecture" rule is superseded by the brief and gets updated. |
| C1 | Resume degrades: by name, else by recorded session id, else fresh with the notes file. *(assumed)* |
| C2 | `--harness` on an existing session is refused. *(assumed)* |
| C3 | One session dir per task; `harness` is a field. *(assumed)* |
| D1 | Account `harness` is a default; credential dirs are created lazily by login. *(assumed)* |
| D2 | Non-secret `provider` / `model` live in `accounts/<name>/meta.json`. *(assumed)* |
| D3 | `config.yaml` `models:` applies only when the harness is claude. *(assumed)* |
| D4 | Login pipes and scrapes line-buffered; emits `CW_LOGIN_URL=` / `CW_LOGIN_CODE=`. *(assumed)* |
| D5 | Unofficial Anthropic-compatible endpoints are labelled by doctor, never blocked. *(assumed)* |
| E1 | GitHub via `gh`; Linear and Notion via opt-in env-var tokens; CW stores no credentials. |
| E2 | The fetcher always runs when a credential is available. *(assumed)* |
| E3 | `gh` when present, else python3 `urllib`. No curl, no jq. *(assumed)* |
| F1 | `CW_CLAUDE_FLAGS` keeps working; `CW_<HARNESS>_FLAGS` added. *(assumed)* |
| F2 | Missing capabilities produce one dim line, never an error. *(assumed)* |
| F3 | Acceptance criterion restated as zero *executions* outside the claude driver. |
| G1 | bats-core vendored as a git submodule. *(assumed)* |
| G2 | `cw` becomes sourceable via a `BASH_SOURCE` guard. *(assumed)* |
| G3 | Every test runs against a temp `CW_HOME` with fake binaries; no real harness is ever spawned. *(assumed)* |

### 2.1 Deviation from the brief: the migration symlink

Decision 3 of the brief asks for the legacy flat account dir to be moved to `<name>/claude/`
with "a symlink at the old path". That is not physically possible: after the move,
`accounts/<name>` must be a real directory containing `claude/`, and a path cannot at the same
time be a symlink pointing inside itself.

The requirement behind it — "nothing the user has today may break", including a hardcoded
`CLAUDE_CONFIG_DIR=~/.cw/accounts/monoku` in a shell rc — is met more directly by not moving
anything. See §5.2. An explicit, opt-in `cw account migrate` is specified in §5.6 for users who
want the clean layout, but it is never run automatically.

## 3. Driver contract

### 3.1 Files

```
lib/harnesses/claude.sh      # built-in
lib/harnesses/codex.sh       # built-in
lib/harnesses/pi.sh          # built-in
lib/harnesses/opencode.sh    # built-in
~/.cw/harnesses/<name>.sh    # user-supplied, wins over built-in
```

Search order when loading harness `<h>`: `$CW_HOME/harnesses/<h>.sh`, then
`$SCRIPT_DIR/../lib/harnesses/<h>.sh`, then `$SCRIPT_DIR/lib/harnesses/<h>.sh`. First hit wins.
`install.sh` and `cmd_init` copy `lib/harnesses/` into `$CW_HOME/lib/harnesses/`, the same way
`lib/dashboard` is already handled.

A driver is sourced into the current shell. It defines eight functions, each prefixed with the
harness name, and `_harness_load` aliases them to the generic names.

### 3.2 Functions

Every function is called with named context already exported by CW (see §3.4).

| Function | Contract |
|---|---|
| `<h>_supports <cap>` | Exit 0 if the capability is supported, 1 otherwise. Must not print. |
| `<h>_config_env` | Print one `VAR=value` line naming the credential env var and its path. May print more than one line. |
| `<h>_doctor` | Print one JSON object describing install + auth state (§7.2). Must not exit non-zero for "not installed". |
| `<h>_login` | Run the harness's native login against the account's credential dir. Honours `CW_LOGIN_NO_BROWSER` and `CW_LOGIN_API_KEY_STDIN`. |
| `<h>_session_ref` | Print the harness-native reference for the current session, or empty if the harness has none. |
| `<h>_launch` | Populate `HARNESS_ARGV` and `HARNESS_ENV` for a fresh session. Must not spawn. |
| `<h>_resume` | Populate `HARNESS_ARGV` and `HARNESS_ENV` for a resumed session. Must not spawn. |
| `<h>_plugin <op> <name>` | Populate `HARNESS_ARGV` and `HARNESS_ENV` for a plugin `list` or `add`. Must not spawn. Only meaningful when `plugins` is supported. |

`<h>_launch` and `<h>_resume` never exec. They build two arrays:

```bash
HARNESS_ARGV=(codex exec --model gpt-5-codex "$CW_PROMPT")
HARNESS_ENV=(CODEX_HOME=/Users/x/.cw/accounts/monoku/codex)
```

A single function spawns:

```bash
# the only place in cw that starts a harness process
_harness_exec() {
    env "${HARNESS_ENV[@]}" "${HARNESS_ARGV[@]}"
}
```

This is what makes the bats argv assertions possible and makes "exactly one place that knows how
to spawn a binary" literally true.

### 3.3 Capabilities

Fixed enumeration. An unknown capability is unsupported.

| Capability | Meaning |
|---|---|
| `resume_by_name` | Sessions can be named by CW and resumed by that name |
| `continue_last` | The harness can continue its most recent session in the cwd |
| `non_interactive_prompt` | A prompt can be passed on argv for a scripted run |
| `interactive_prompt` | A prompt can be passed on argv and still open an interactive session |
| `mcp` | Reads MCP server config CW can write |
| `hooks` | Supports the hook system in `hooks/` |
| `skip_permissions` | Has an equivalent of `--dangerously-skip-permissions` |
| `agent_teams` | Supports the agent-teams env flag |
| `plugins` | Has a plugin CLI `cw stack` can drive |
| `model_flag` | Accepts a model on argv |
| `custom_provider` | Accepts a non-native provider endpoint |
| `statusline` | Has a statusline CW can configure |
| `instructions_file` | Has a user-level instructions file CW can install `CLAUDE.md` into |
| `skills` | Has a user-level skills directory CW can symlink account skills into |

### 3.4 Env contract

CW exports these before calling any driver function. Drivers read them; they never parse argv.

| Variable | Meaning |
|---|---|
| `CW_HARNESS` | Resolved harness name |
| `CW_ACCOUNT` | Account name |
| `CW_ACCOUNT_ROOT` | `$CW_ACCOUNTS_DIR/<account>` |
| `CW_HARNESS_DIR` | Credential dir for this account+harness (§5.2) |
| `CW_PROJECT` | Project name |
| `CW_TASK` | Task or review id |
| `CW_TASK_TYPE` | `task` / `review` / `loop` / `plan` / `open` / `create` |
| `CW_SESSION_NAME` | `<account>/<project>/<task>` |
| `CW_SESSION_REF` | Harness-native session id from `session.json`, or empty |
| `CW_PROMPT` | Prompt text, or empty |
| `CW_MODEL` | Resolved model, or empty |
| `CW_PROVIDER` | Resolved provider, or `native` |
| `CW_WORKDIR` | Directory the harness is launched in |
| `CW_EXTRA_FLAGS` | Word-split extra flags (§11.1) |

`CW_PROJECT`, `CW_TASK`, `CW_TASK_TYPE` and `CW_ACCOUNT` are already exported today and are
consumed by the hooks in `hooks/` and by `lib/dashboard`. Their meaning does not change.

## 4. The four built-in drivers

Rows marked **verify** are unconfirmed and must be checked against the installed binary during
implementation rather than guessed at.

### 4.1 Credential env var

| Harness | Variable | Default when unset | Verified |
|---|---|---|---|
| claude | `CLAUDE_CONFIG_DIR` | `~/.claude` | yes, in use today |
| codex | `CODEX_HOME` | `~/.codex` | yes |
| pi | `PI_CODING_AGENT_DIR` | `~/.pi/agent` | yes |
| opencode | `OPENCODE_DATA_DIR` | `${XDG_DATA_HOME:-~/.local/share}/opencode` | yes |

OpenCode splits config from data: `OPENCODE_DATA_DIR` holds `auth.json` and sessions,
`OPENCODE_CONFIG` points at a config *file* and `OPENCODE_CONFIG_DIR` at a config *directory*.
The credential dir CW owns is the data dir; the driver additionally sets `OPENCODE_CONFIG` to
`$CW_HARNESS_DIR/opencode.json` so provider and model config is per-account too.

### 4.2 Launch and resume

| Harness | Fresh launch | Resume | Non-interactive |
|---|---|---|---|
| claude | `claude [--model M] --name <name> [prompt]` | `--resume <name>` then `--continue` then `--name <name>` | prompt on argv |
| codex | `codex [--model M] [prompt]` **verify** | `codex resume --last` or `codex resume <id>` | `codex exec` / `codex exec resume --last "prompt"` |
| pi | `pi [prompt]` **verify** | **verify** — sessions are JSONL under `$PI_CODING_AGENT_DIR/sessions/` | **verify** |
| opencode | `opencode` (TUI, no args) | `opencode run "p" --continue` or `--session <id>` | `opencode run "prompt"` |

Two consequences worth stating explicitly:

**Only claude has `resume_by_name`.** Codex and OpenCode resume by opaque session id or by
"last". Pi is unverified. This is why `session.json` gains `harness_session_id` (§8).

**Codex's `--last` is scoped to the working directory by default**, which happens to be exactly
CW's model: one worktree per task means "the last codex session started here" is unambiguously
this task's session. The codex driver therefore prefers `resume --last` from `CW_WORKDIR` and
falls back to a recorded id. The same needs verifying for OpenCode's `--continue`.

### 4.3 Login

| Harness | Native login | `--no-browser` | API key on stdin |
|---|---|---|---|
| claude | `claude` then `/login` | **verify** | **verify** |
| codex | `codex login` | `codex login --device-auth` | `codex login --with-api-key` (reads stdin) |
| pi | `pi` then `/login`; writes `auth.json` | **verify** | **verify** |
| opencode | `opencode auth login` | **verify** | **verify** |

Codex's `--with-api-key` reading from stdin matches the brief's `--with-api-key -` requirement
exactly. Claude and Pi both authenticate through an in-session slash command rather than a
subcommand, so their drivers spawn the harness with the credential dir set and let the user
complete the flow; `harness_login` returns the child's exit status unchanged.

### 4.4 Capability matrix

| Capability | claude | codex | pi | opencode |
|---|---|---|---|---|
| `resume_by_name` | yes | no | verify | no |
| `continue_last` | yes | yes | verify | yes |
| `non_interactive_prompt` | yes | yes | verify | yes |
| `interactive_prompt` | yes | verify | verify | no |
| `mcp` | yes | yes (different shape, unused this release) | verify | verify |
| `hooks` | yes | no | no | no |
| `skip_permissions` | yes | verify | verify | verify |
| `agent_teams` | yes | no | no | no |
| `plugins` | yes | no | no | no |
| `model_flag` | yes | yes | yes | yes |
| `custom_provider` | unofficial only | yes | yes | yes |
| `statusline` | yes | verify | verify | verify |
| `instructions_file` | `CLAUDE.md` | `AGENTS.md` **verify** | verify | verify |
| `skills` | yes | verify | verify | verify |

## 5. Account layout

### 5.1 Shape

An account is a person or an org. It holds one credential dir per harness plus CW-owned,
harness-neutral files at its root.

```
~/.cw/accounts/<name>/
  meta.json                 # CW-owned: name, created, default harness, per-harness settings
  CLAUDE.md                 # CW-owned: account-wide instructions, installed per harness
  templates/
    work_init.md            # CW-owned
    work_resume.md          # CW-owned
  skills/                   # CW-owned
  claude/                   # CLAUDE_CONFIG_DIR
  codex/                    # CODEX_HOME
  pi/                       # PI_CODING_AGENT_DIR
  opencode/                 # OPENCODE_DATA_DIR + OPENCODE_CONFIG
    env                     # mode 600, API keys only, never written by cw account add
```

### 5.2 Resolution rule

There are two valid layouts and both are supported forever. A single function decides:

```bash
# claude keeps the legacy flat dir unless a claude/ subdir exists
_harness_dir() {
    local account="$1" harness="$2"
    local root="$CW_ACCOUNTS_DIR/$account"
    if [[ "$harness" == "claude" && ! -d "$root/claude" ]]; then
        echo "$root"
    else
        echo "$root/$harness"
    fi
}
```

Consequences:

- `monoku` and `meridian` on this machine are untouched. `CLAUDE_CONFIG_DIR` still resolves to
  `~/.cw/accounts/monoku`, byte-identical to today.
- A hardcoded `CLAUDE_CONFIG_DIR=~/.cw/accounts/monoku` in a shell rc keeps working.
- Adding a second harness to a legacy account creates only `accounts/monoku/codex/`; the flat
  claude files sit alongside it. Claude Code ignores directories it does not own.
- Accounts created after this release get `accounts/<name>/claude/` and are clean from the start.
- `cw-shell-integration.sh` regenerates its `claude-<account>` aliases from `_harness_dir`, so
  they follow whichever layout each account has.

The cost is that `$acct_dir` is no longer a single meaningful value. Every current use splits
into an **account root** (identity, CW-owned files) and a **harness dir** (credentials,
settings). `_resolve_account_dir` is replaced by `_resolve_account` returning the name, plus
`_account_root` and `_harness_dir`. The three sites that derive an account name with
`basename "$acct_dir"` (`_mcp_add`, `_mcp_remove`, `_mcp_list`) use the resolved name directly.

### 5.3 `meta.json`

```json
{
  "name": "monoku",
  "created": "2026-05-17T00:08:10Z",
  "harness": "claude",
  "harnesses": {
    "claude": { "provider": "native", "model": null },
    "codex":  { "provider": "native", "model": "gpt-5-codex" }
  }
}
```

`harness` is the account default. A missing `harness` reads as `claude`, and a missing
`harnesses` map reads as `{}` — both existing `meta.json` files on this machine are valid
unchanged.

Secrets never appear here. API keys live only in `accounts/<name>/<harness>/env`, mode 600,
written by `cw account login --with-api-key -` and by nothing else. `cw doctor` reports whether
a key is present, never its value, and the file is never sourced into the env of a launched
harness beyond the variable that harness itself requires.

### 5.4 Provider

A provider is either the harness's native login or an API endpoint plus key.

```
cw account add glm   --harness opencode --provider zai        --model glm-5.1
cw account add local --harness opencode --provider ollama     --model qwen3-coder:14b
cw account add free  --harness pi       --provider openrouter --model qwen/qwen3-coder:free
```

Each driver translates `CW_PROVIDER` to its own config: pi and opencode have native provider
entries, codex maps to `model_providers` in `config.toml`, claude accepts only
Anthropic-compatible endpoints via `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`. Exact config
keys per harness are **verify during implementation**.

For `provider: ollama` there is no token. `harness_doctor` checks that the endpoint answers and
that the model is pulled, and reports `status: "local"`.

For claude with a third-party Anthropic-compatible endpoint, doctor sets `"unofficial": true`
and the human output labels it *unofficial, may break on Claude Code updates*. CW does not
refuse to launch it.

### 5.5 Model resolution

First match wins:

1. `--model` on the command line
2. `session.json` `model` for an existing session
3. `meta.json` `harnesses.<harness>.model`
4. `config.yaml` `models.<task_type>` — **only when the harness is claude**
5. the harness's own default

Step 4 is claude-only because `sonnet` / `opus` / `haiku` are meaningless to codex or to a GLM
endpoint. While here, `loop:` is added to the generated `models:` block; `_model_for_type loop`
currently falls through to an unset `CW_DEFAULT_MODEL`.

### 5.6 `cw account migrate`

Explicit, opt-in, never automatic, and never run by any other command.

```
cw account migrate <name> [--dry-run]
```

Moves the flat claude files into `<name>/claude/`, leaving CW-owned files (`meta.json`,
`templates/`, `skills/`, `CLAUDE.md`) at the root. Prints the exact `mv` operations under
`--dry-run`. Reversible with `cw account migrate <name> --undo`.

Because §5.2 resolves both layouts, migrating changes nothing functionally — it is cosmetic, and
the only thing it can break is a user's own hardcoded `CLAUDE_CONFIG_DIR`, which the command
warns about before doing anything.

### 5.7 Account instructions file

`accounts/<name>/CLAUDE.md` works today only as a side effect of the account dir being the
Claude config dir. It becomes explicit: when `harness_supports instructions_file`, the driver
installs it into the harness's user-level instruction slot at launch — claude symlinks it into
the config dir as `CLAUDE.md`, codex as `AGENTS.md` (**verify**). For legacy flat accounts the
file is already in place and the claude driver is a no-op.

## 6. `cw account login`

```
cw account login <account> --harness <h> [--no-browser] [--with-api-key -]
```

Resolves the credential dir with `_harness_dir`, creates it if missing, exports the harness's
env var, and runs the driver's login.

`--no-browser` sets `CW_LOGIN_NO_BROWSER=1`. Drivers translate it to their own flag — codex to
`--device-auth`, the others **verify during implementation**. It is a request, not a guarantee:
if a harness has no headless flow the driver says so on one line and exits non-zero.

`--with-api-key -` reads one line from stdin, writes it to
`accounts/<name>/<harness>/env` with mode 600, and passes it to the harness's own key-import
path when one exists. The key is never echoed, never written to `config.yaml` or `meta.json`,
and never appears in argv — which is also why codex's `--with-api-key` reading stdin is the
right target.

### 6.1 Machine-parseable output

While the child runs, CW pipes its output line-buffered, echoes every line through unchanged,
and additionally emits on its own stdout:

```
CW_LOGIN_URL=https://...
CW_LOGIN_CODE=ABCD-1234
```

on the first match of a URL or a device code. If neither matches, nothing extra is printed and
CW exits with the child's status. The scrape is best-effort by design: it must never swallow or
reorder the harness's own output, because that output is what the user reads when the scrape
misses.

Detection is a regex per driver, not a global one, so a harness that prints a URL for an
unrelated reason does not produce a false `CW_LOGIN_URL=` line.

## 7. `cw doctor --json`

`cw doctor` keeps its current human output and grows an account × harness matrix. `--json`
prints one object on stdout and nothing else — no colour, no log lines, exit 0 even when there
are findings, so Forge can parse it unconditionally.

### 7.1 Shape

```json
{
  "schema": 1,
  "cw_version": "0.3.0",
  "cw_home": "/Users/joselito/.cw",
  "generated": "2026-09-09T18:00:00Z",
  "harnesses": [
    {
      "name": "claude",
      "installed": true,
      "path": "/Users/joselito/.local/bin/claude",
      "version": "2.1.267",
      "source": "builtin"
    },
    {
      "name": "codex",
      "installed": false,
      "path": null,
      "version": null,
      "source": "builtin"
    }
  ],
  "accounts": [
    {
      "name": "monoku",
      "root": "/Users/joselito/.cw/accounts/monoku",
      "layout": "legacy",
      "default_harness": "claude",
      "harnesses": [
        {
          "harness": "claude",
          "status": "connected",
          "config_env": "CLAUDE_CONFIG_DIR",
          "config_dir": "/Users/joselito/.cw/accounts/monoku",
          "provider": "native",
          "provider_kind": "native",
          "model": null,
          "unofficial": false,
          "has_api_key": false,
          "detail": null
        },
        {
          "harness": "codex",
          "status": "not_installed",
          "config_env": "CODEX_HOME",
          "config_dir": "/Users/joselito/.cw/accounts/monoku/codex",
          "provider": "native",
          "provider_kind": "native",
          "model": null,
          "unofficial": false,
          "has_api_key": false,
          "detail": "codex not found on PATH"
        }
      ]
    },
    {
      "name": "local",
      "root": "/Users/joselito/.cw/accounts/local",
      "layout": "split",
      "default_harness": "opencode",
      "harnesses": [
        {
          "harness": "opencode",
          "status": "local",
          "config_env": "OPENCODE_DATA_DIR",
          "config_dir": "/Users/joselito/.cw/accounts/local/opencode",
          "provider": "ollama",
          "provider_kind": "local",
          "model": "qwen3-coder:14b",
          "unofficial": false,
          "has_api_key": false,
          "detail": {
            "endpoint": "http://localhost:11434",
            "reachable": true,
            "model_pulled": true
          }
        }
      ]
    }
  ],
  "issues": [
    { "code": "git_too_old", "message": "git 2.10 (need 2.15+)" }
  ],
  "warnings": [
    { "code": "stale_sessions", "message": "3 stale session(s)", "count": 3 }
  ]
}
```

### 7.2 Enums

`status`: `connected` | `not_logged_in` | `not_installed` | `local` | `error`
`provider_kind`: `native` | `api` | `local`
`layout`: `legacy` (flat claude dir) | `split` (per-harness subdirs)
`source`: `builtin` | `user`

`detail` is `null`, a string, or an object. Forge must treat it as opaque except for
`provider_kind: "local"`, where the object above is guaranteed.

A driver's `<h>_doctor` returns the per-harness object minus `config_env` and `config_dir`,
which CW fills in. A driver that cannot determine auth state returns `status: "error"` with a
`detail` string; it never crashes the matrix.

## 8. `session.json`

Four new fields. Everything existing keeps its meaning.

```json
{
  "project": "cw",
  "task": "harness-agnostic",
  "type": "task",
  "account": "monoku",
  "harness": "claude",
  "harness_session_id": "",
  "provider": "native",
  "model": "sonnet",
  "workflow": "",
  "worktree": "/Users/joselito/workspace/personal/cw/.tasks/harness-agnostic",
  "notes": "/Users/joselito/.cw/sessions/cw/task-harness-agnostic/TASK_NOTES.md",
  "source": "",
  "source_url": "",
  "status": "active",
  "created": "2026-09-09T18:10:41Z",
  "last_opened": "2026-09-09T18:10:41Z",
  "opens": 1
}
```

| Field | Meaning |
|---|---|
| `harness` | Which harness this session runs on. **Missing reads as `claude`.** |
| `harness_session_id` | The harness's own session reference, when it has one. Empty for claude, which resumes by name. |
| `provider` | Resolved provider at creation time, or `native` |
| `model` | Already exists; now harness-relative |

Session directories are not keyed by harness. One task, one directory, one harness — recorded,
not encoded in the path. Every session directory that exists today stays valid.

`harness` is written once, at creation, and is authoritative for every later resume. Passing
`--harness` to an existing session is refused:

```
[cw] Session 'fix-auth' was created with codex. Refusing to resume it with claude.
     Close it first: cw work my-app fix-auth --done
```

## 9. `cw spaces` and `cw status`

`cw spaces` grows a harness column. Provider and model are shown when they are not the default:

```
  cw  (monoku)
    task: harness-agnostic  (1x, 2026-09-09)  claude
    task: glm-experiment    (3x, 2026-09-08)  opencode · GLM 5.1
```

`cw spaces --json` is added for Forge, mirroring the fields above:

```json
{
  "schema": 1,
  "spaces": [
    {
      "project": "cw",
      "account": "monoku",
      "type": "task",
      "id": "harness-agnostic",
      "harness": "claude",
      "provider": "native",
      "model": "sonnet",
      "opens": 1,
      "last_opened": "2026-09-09T18:10:41Z",
      "worktree": "/Users/joselito/workspace/personal/cw/.tasks/harness-agnostic",
      "resume": "cw work cw harness-agnostic",
      "close": "cw work cw harness-agnostic --done"
    }
  ]
}
```

`cw status` gains a per-account harness line. `lib/dashboard/server.py` reads `harness` from
`session.json` and the account matrix from `_harness_dir` rather than testing for `.claude.json`
directly.

## 10. Portable context fetch

### 10.1 Why it exists

Today "URL to context" works only because Claude Code fetches the ticket through its own MCP
connection. Those OAuth tokens belong to Claude Code, live in an undocumented shape inside its
config dir, and are per-harness — the token `monoku/claude` obtained is useless for launching
codex. So the portable path cannot reuse them. CW fetches the content itself and writes it into
`TASK_NOTES.md` before launch; the notes file is the source of truth on every harness.

### 10.2 Credentials

CW stores nothing. It reads, in order: the environment, then `~/.cw/tokens.env` (mode 600,
created by the user, never written by CW).

| Source | Credential | Notes |
|---|---|---|
| GitHub | none — uses `gh` | Already authenticated on any machine running `cw review` |
| Linear | `LINEAR_API_KEY` | Personal API key from Linear settings |
| Notion | `NOTION_TOKEN` | Internal integration token |

Tokens are read into the fetcher process only. They are **not** exported into the environment of
the launched harness, so the agent cannot read them out of `env`.

With no credential, the fetch is skipped with one warning and the behaviour is exactly today's:
the URL is passed through and the harness's MCP resolves it if it can. GitHub therefore works
out of the box everywhere; Linear and Notion are opt-in.

### 10.3 Structure

```
lib/context/github.sh
lib/context/linear.sh
lib/context/notion.sh
```

Each defines two functions:

```bash
context_credential_github   # exit 0 if a credential is available
context_fetch_github        # print markdown for $1 (a URL) on stdout
```

Splitting credential lookup from fetching is deliberate: if CW ever grows its own OAuth, only
`context_credential_*` changes. The fetchers and the drivers do not.

Transport is `gh` when present, otherwise python3 `urllib`. No curl, no jq — consistent with the
project's dependency rule.

### 10.4 Behaviour

1. `cw work <proj> <url>` detects the source exactly as it does today (`cw:1512`).
2. If a credential is available, the fetcher runs and its markdown is written into the
   `## Context` section of `TASK_NOTES.md` before the harness launches.
3. If `harness_supports mcp`, the URL is still passed in the init prompt so the agent can
   refresh — but the prompt no longer *instructs* the agent to fetch it, because the content is
   already in the notes.
4. If no credential is available, step 2 is skipped, one warning is printed, and the init prompt
   keeps today's fetch instruction.

Acceptance target from the brief:
`cw work demo-app https://github.com/org/repo/issues/1 --harness codex` creates the worktree,
writes `TASK_NOTES.md` with the issue body, and launches codex in it — with no credential setup
beyond `gh auth login`.

### 10.5 Tests

Recorded fixtures, no network. `gh` and python3's `urlopen` are both stubbed; each fetcher has a
fixture for a normal response, a 404, and a 401.

## 11. Degradation

Rule: never fail on a harness that lacks a feature. Degrade, and say so once per command as a
single dim line.

| Feature | Site today | Capability | Degradation |
|---|---|---|---|
| Statusline | `_ensure_statusline` `cw:122` | `statusline` | skip |
| Platform-default model | `_use_platform_default_model` `cw:106` | `model_flag` | skip |
| `--dangerously-skip-permissions` | `_resolve_claude_flags` `cw:36` | `skip_permissions` | map to the harness flag, else drop and say so |
| Agent teams (`--team`) | `cw:1866`, `cw:4546` | `agent_teams` | run without the team; one line |
| `cw mcp` | `_mcp_*` | `mcp` | clear error naming the harness — this is a direct user request, not an implicit feature |
| `cw project setup-mcps` | `cw:422` | `mcp` | clear error |
| Arcade hooks | `_arcade_install_hooks_for` `cw:2616` | `hooks` | skip that account+harness, keep going |
| `cw stack` plugins | `_stack_apply` `cw:3983` | `plugins` | skip plugins, still install agents and the `CLAUDE.md` section |
| Account skills symlink | `cw:1083`, `cw:1408`, `cw:1798` | `skills` | skip |
| Resume by name | `cw:1166`, `cw:1473`, `cw:1903` | `resume_by_name` | see §11.2 |

`cw mcp` and `cw project setup-mcps` are the two that error rather than degrade, because the user
asked for that specific thing by name.

### 11.1 Flags

`CW_CLAUDE_FLAGS` keeps working verbatim — it is documented in the generated `config.yaml` and
may be in a user's shell. `CW_<HARNESS>_FLAGS` is added, and for claude the two are concatenated
with `CW_CLAUDE_FLAGS` first. The global `--skip-permissions` flag and `skip_permissions: true`
in `config.yaml` route through `harness_supports skip_permissions` to the harness's own
equivalent; codex's exact flag is **verify during implementation**.

### 11.2 Resume degradation

```
resume_by_name        -> resume by CW_SESSION_NAME             (claude)
else continue_last    -> resume the last session in CW_WORKDIR (codex, opencode)
else recorded id      -> resume by session.json harness_session_id
else                  -> launch fresh with the resume prompt; warn once
```

The last rung is not a failure. `TASK_NOTES.md` exists precisely so a lost conversation is
recoverable — that is the design already documented in `docs/architecture.md`.

For claude, the existing three-step `--resume` then `--continue` then `--name` chain is preserved
byte-identically, including the fact that it chains on exit status. It is claude-specific
behaviour and lives in the claude driver.

## 12. CLI surface

New:

```
cw account add <name> [--harness <h>] [--provider <p>] [--model <m>]
cw account login <name> --harness <h> [--no-browser] [--with-api-key -]
cw account migrate <name> [--dry-run] [--undo]
cw harness list
cw harness doctor
cw doctor --json
cw spaces --json
```

New flag on existing commands, as a one-off override:

```
cw work <proj> <task> --harness <h>
cw review <proj> <pr> --harness <h>
cw loop <proj> "<prompt>" --harness <h>
cw plan | cw create | cw open --harness <h>
cw project register <path> --harness <h>
```

Harness resolution, first match wins: `--harness` flag, `session.json` `harness` (and then the
flag is refused if it disagrees, §8), `projects.json` `harness`, `meta.json` `harness`, `claude`.

### 12.1 `projects.json`

One optional field, so a project can override its account's default harness:

```json
{
  "cw": {
    "path": "/Users/joselito/workspace/personal/cw",
    "account": "monoku",
    "type": "fullstack",
    "harness": "codex",
    "registered": "2026-05-17T00:08:10Z"
  }
}
```

A missing `harness` reads as "use the account default". Every entry in the current
`projects.json` is valid unchanged.

## 13. Testing

`bats-core`, `bats-support` and `bats-assert` vendored as git submodules under `tests/`, with
`tests/run.sh` as the entry point. There is no CI today; this is the first test suite in the
repo.

Two structural changes make it possible:

1. `cw` becomes sourceable. `main "$@"` at `cw:4727` is guarded:
   ```bash
   [[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
   ```
2. Every test runs against a temporary `CW_HOME` with fake harness binaries first on `PATH`.
   **No test ever touches the real `~/.cw` and no test ever spawns a real harness**, so the suite
   is green on a machine with only claude installed and stays green after codex and pi arrive.

A fake binary records its argv, its env and its cwd to a file the test asserts on:

```bash
# tests/fakes/claude — records the call and exits with $FAKE_EXIT
printf '%s\n' "$PWD" "$CLAUDE_CONFIG_DIR" "$@" >> "$FAKE_LOG"
exit "${FAKE_EXIT:-0}"
```

Coverage required before the refactor commit lands:

- argv, env and cwd for `work` new / resume / `--team` / `--done`
- argv, env and cwd for `review` new / re-review, `loop` new / resume, `plan`, `create`,
  `open`, `launch`
- the three-step resume chain, including that a non-zero exit advances to the next step
- `$CW_CLAUDE_FLAGS` word-splitting and `--skip-permissions`
- legacy flat account resolves to the account root; split account resolves to `<name>/claude`

And for the acceptance criterion (§2, F3), a test asserting **zero executions** of a harness
binary outside `lib/harnesses/`:

```bash
# no harness may be spawned outside its driver
! grep -nE '(^|[;&| ]|env .*)(claude|codex|pi|opencode)( |$)' cw | grep -vE '^\s*#|echo|printf'
```

The exact pattern is refined during implementation. In particular `pi` is a common word
fragment and a bare word-boundary match will fire on prose, so the pattern must anchor on
execution shape rather than on the binary name alone. The requirement is that it catches every
shape in the inventory (`CLAUDE_CONFIG_DIR=… claude`, `env $team_env … claude`,
`command -v claude`, `claude plugin`) and tolerates help text and prompt bodies.

## 14. Verify during implementation

Collected from above, so nothing here is guessed at in code:

- pi: launch argv, resume mechanism, non-interactive prompt, `--no-browser` equivalent, API-key
  import, instructions file
- opencode: `--no-browser` equivalent, API-key import, whether `--continue` is cwd-scoped,
  provider config keys, statusline
- codex: interactive launch argv, `skip_permissions` equivalent flag, `model_providers` config
  keys, `AGENTS.md` as the instructions file
- claude: whether `/login` has a headless or `--no-browser` equivalent, and an API-key import
  path
- All four: the login output shape, to build the `CW_LOGIN_URL` / `CW_LOGIN_CODE` regexes
- Whether OpenCode reads `OPENCODE_CONFIG` reliably when `OPENCODE_DATA_DIR` is also set

Sources consulted for the confirmed rows: OpenAI Codex CLI docs (`CODEX_HOME`, `codex login
--device-auth`, `codex login --with-api-key`, `codex resume --last`, `codex exec resume`),
OpenCode docs (`OPENCODE_DATA_DIR`, `OPENCODE_CONFIG`, `opencode auth login`, `opencode run
--continue --session`), Pi coding-agent docs (`PI_CODING_AGENT_DIR`, `~/.pi/agent`, `/login`,
`auth.json`).

## 15. Out of scope

From the brief: rewriting CW in another language, a plugin system for CW itself, and Forge UI
work.

Added by this spec:

- **CW doing its own OAuth** against Linear or Notion. It would require registering CW as an
  OAuth application with each provider, PKCE for a public client, a local callback server,
  refresh-token storage and rotation, and would make CW responsible for credentials it has never
  held. It buys about thirty seconds of one-time setup over a personal API key. §10.3 leaves the
  seam so it can land later without touching the fetchers or the drivers.
- **Per-harness MCP configuration.** `cw mcp` stays Claude-only (§2, A4).
- **Automatic account migration.** `cw account migrate` is opt-in (§5.6).

## 16. Documentation to update

- `docs/harness-drivers.md` — new, the driver contract from §3, written as part of the driver
  task
- `docs/architecture.md` — §18-23 and §183 document the flat account layout and
  `CLAUDE_CONFIG_DIR`; add the harness abstraction as a fourth concern
- `docs/getting-started.md:41` — `cw account login` replaces the printed
  `CLAUDE_CONFIG_DIR=… claude /login`
- `CLAUDE.md` — the single-file rule, superseded by `lib/harnesses/` (§2, B5)
- `README.md` — the "one flow, any harness" section
- `cw:234`, `cw:281` — printed next-step instructions point at `cw account login`
