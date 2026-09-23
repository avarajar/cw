# Harness drivers

`cw` launches a coding-agent CLI ("harness") through a small driver contract instead of
hard-coding `claude` at every call site. This document describes that contract: the functions a
driver must define, the capability enumeration, the globals a driver may read, and the
`HARNESS_ARGV` / `HARNESS_ENV` handoff that keeps process-spawning in one place.

## Search order

`_harness_load <name>` looks for a driver in this order and sources the first match:

1. `$CW_HOME/harnesses/<name>.sh` — user-supplied, always wins
2. `$SCRIPT_DIR/../lib/harnesses/<name>.sh`
3. `$SCRIPT_DIR/lib/harnesses/<name>.sh` — bundled with the repo

If no file matches, every generic `harness_*` function is stubbed to `return 1` and `_harness_load`
returns 1, so a missing harness fails safe instead of silently reusing whatever driver was loaded
before it.

## The eight functions

A driver is a plain `.sh` file, sourced into the current shell, that defines up to eight functions
prefixed with the harness name (`<h>`). `_harness_load` rebinds whichever of them exist to the
generic `harness_*` names; any it omits is bound to a function that returns 1.

| Function | Contract |
|---|---|
| `<h>_supports <cap>` | Returns 0 if the capability is supported, 1 otherwise. Must not print anything. |
| `<h>_config_env` | Prints one `VAR=value` line naming the credential env var and its path. May print more than one line. |
| `<h>_session_ref` | Prints the harness-native reference for the current session, or an empty string if the harness has none. |
| `<h>_launch` | Populates `HARNESS_ARGV` and `HARNESS_ENV` for a fresh session. Must not spawn anything. |
| `<h>_resume <attempt>` | Populates `HARNESS_ARGV` / `HARNESS_ENV` for resume attempt N (1, 2, 3, ...). Returns 1 once there is no such attempt, so `_harness_resume` knows to stop. Must not spawn. |
| `<h>_plugin <op> <name>` | Populates `HARNESS_ARGV` / `HARNESS_ENV` for a plugin `list` or `add`. Must not spawn. Only meaningful when `plugins` is supported. |
| `<h>_doctor` | Reports install/auth state for `cw doctor`. Must not fail just because the harness isn't installed. |
| `<h>_login` | Runs the harness's native login flow against the account's credential dir. |

`<h>_launch`, `<h>_resume` and `<h>_plugin` never call `exec`, `env`, or the binary directly — they
only set two arrays and return. The one function in `cw` allowed to start a harness process is:

```bash
# the only place in cw that starts a harness process
_harness_exec() {
    env ${HARNESS_ENV[@]+"${HARNESS_ENV[@]}"} "${HARNESS_ARGV[@]}"
}
```

`tests/no_direct_launch.bats` enforces this with `tests/helpers/scan_launch_sites.py`, which flags
any line in `cw` that spawns `claude`, `codex`, `pi`, or `opencode` in command position — including
a quoted command word such as `"claude" --resume "$x"`.

## Capabilities

The capability enumeration is fixed; an unknown capability is always unsupported.

| Capability | Meaning |
|---|---|
| `resume_by_name` | Sessions can be named by `cw` and resumed by that name |
| `continue_last` | The harness can continue its most recent session in the cwd |
| `non_interactive_prompt` | A prompt can be passed on argv for a scripted run |
| `interactive_prompt` | A prompt can be passed on argv and still open an interactive session |
| `mcp` | Reads MCP server config `cw` can write |
| `hooks` | Supports the hook system in `hooks/` |
| `skip_permissions` | Has an equivalent of `--dangerously-skip-permissions` |
| `agent_teams` | Supports the agent-teams env flag |
| `plugins` | Has a plugin CLI `cw stack` can drive |
| `model_flag` | Accepts a model on argv |
| `custom_provider` | Applies a non-native `CW_PROVIDER` itself. Declare it only if the driver really reads `CW_PROVIDER`: `cw` refuses to launch a harness without it when a non-native provider is configured, rather than run it silently on its own login. Today codex and opencode declare it; claude and pi do not |
| `statusline` | Has a statusline `cw` can configure |
| `instructions_file` | Has a user-level instructions file `cw` can install `CLAUDE.md`-equivalent content into |
| `skills` | Has a user-level skills directory in its config dir; every launch links the global `~/.claude/skills` and the account's skills into it |
| `api_key_login` | Has an API-key import path `cw account login --with-api-key -` can drive |
| `headless_login` | Has a login that prints a URL or device code instead of a browser or TUI, so `cw account login --no-browser` can pipe it and emit `CW_LOGIN_URL=` / `CW_LOGIN_CODE=`. Without it `--no-browser` is refused; a normal login always keeps the terminal |
| `slash_commands` | Understands the Claude Code slash commands `cw` sends as prompts (`/loop`, `/simplify`). `cw loop` refuses on a harness without it, and `cw work` asks for a self-review in plain words instead of `/simplify` |

A command that wants a capability but can proceed without it calls `_degrade`, which prints one
dim line the first time a given capability is missing in the current process and then returns 1:

```bash
harness_supports agent_teams || _degrade agent_teams "Agent teams not supported — running without a team"
```

A command where the missing capability makes the whole operation meaningless (for example `cw mcp`
on a harness with no `mcp` support) calls `_err` and returns 1 instead of degrading.

## Globals a driver may read

`_harness_context` sets these before any `harness_*` function runs. Drivers read them; they never
parse `cw`'s own argv.

| Variable | Meaning |
|---|---|
| `CW_HARNESS` | Resolved harness name |
| `CW_HARNESS_DIR` | This account's credential dir for `CW_HARNESS`, from `_harness_dir <account> <harness>` — the account root itself for a flat `claude` account, otherwise `<account root>/<harness>` |
| `CW_SESSION_NAME` | `<account>/<project>/<task>`, or empty |
| `CW_SESSION_REF` | Harness-native session id recorded in `session.json`, or empty |
| `CW_WORKDIR` | Directory the harness is launched in |
| `CW_NOTES_FILE` | The session's notes file (`TASK_NOTES.md`, `REVIEW_NOTES.md`, `LOOP_NOTES.md`), or empty |
| `CW_CONTINUE_LAST_SAFE` | Non-empty only when `cw` vouches that "the last conversation in `CW_WORKDIR`" can only be this session's — today, a task's own worktree that this session has already launched in, which on every harness but claude `cw work` creates before the first launch. Never set for the shared project root, where reviews, loops, and a task whose worktree `cw` could not create run |
| `CW_PROMPT` | Prompt text, or empty |
| `CW_MODEL` | Resolved model, or empty |
| `CW_PROVIDER` | Resolved provider, defaults to `native` |
| `CW_EXTRA_FLAGS` | Word-split extra flags, already translated for this harness (see below) |
| `CW_TEAM_ENV` | `HARNESS_ENV` entry enabling agent teams, or empty |
| `CW_LOGIN_NO_BROWSER` | Set (non-empty) when `cw account login` was given `--no-browser`; only read by `<h>_login` |
| `CW_LOGIN_API_KEY_STDIN` | Set (non-empty) when `cw account login` was given `--with-api-key -`; only read by `<h>_login`, and only meaningful when `api_key_login` is supported |

`CW_PROJECT`, `CW_TASK`, `CW_TASK_TYPE` and `CW_ACCOUNT` are exported alongside these for hooks and
`lib/dashboard`; their meaning is unchanged from before the driver layer existed.

`CW_EXTRA_FLAGS` is computed by `_harness_extra_flags`, which merges `CW_CLAUDE_FLAGS` with a
per-harness override (`CW_<HARNESS-UPPER>_FLAGS`) and strips `--dangerously-skip-permissions` —
degrading instead — when the loaded harness lacks `skip_permissions`.

## `HARNESS_ARGV` / `HARNESS_ENV`

Every function that builds a launch populates these two arrays and returns; `_harness_exec` is the
only caller of `env`/the binary itself:

```bash
HARNESS_ARGV=(codex exec --model gpt-5-codex "$CW_PROMPT")
HARNESS_ENV=(CODEX_HOME=/Users/x/.cw/accounts/monoku/codex)
```

`_harness_launch` and `_harness_resume` reset both arrays to empty before calling into the driver,
so a driver only ever needs to set what it uses.

## Resume must be attributable

`<h>_resume` may only offer an attempt that can be attributed to this session: a recorded
`CW_SESSION_REF`, or "continue the last conversation" when `CW_CONTINUE_LAST_SAFE` is set. It must
never offer "the last conversation here" in a directory other tasks share, because that silently
reopens another task's conversation. When the driver has nothing safe to offer it returns 1 for
attempt 1.

After the driver's attempts are exhausted, `cw` itself takes the last rung for any harness without
`resume_by_name`: it prints one line saying so and launches fresh with the resume prompt plus a
pointer to `CW_NOTES_FILE`. Claude's own three-step chain is unchanged and ends inside its driver.

`<h>_session_ref` runs after every launch. It may print an id only when it can prove the
conversation is this session's; the codex driver looks for exactly one new rollout file under
`$CODEX_HOME/sessions/` that mentions `CW_NOTES_FILE`, and prints nothing otherwise. That file
layout is unverified against a real codex install, so the capture fails safe to a fresh start.

## A minimal custom driver

Drop this at `~/.cw/harnesses/echoagent.sh` to see the contract end to end. It "supports" nothing
fancy — just enough to launch and resume — and every other capability check correctly reports
unsupported.

```bash
# echoagent driver — minimal example, not a real harness
echoagent_supports() {
    case "$1" in
        resume_by_name|non_interactive_prompt) return 0 ;;
        *) return 1 ;;
    esac
}

echoagent_config_env() {
    printf 'ECHOAGENT_HOME=%s\n' "$CW_HARNESS_DIR"
}

echoagent_session_ref() {
    printf '%s' ""
}

echoagent_launch() {
    HARNESS_ENV=("ECHOAGENT_HOME=$CW_HARNESS_DIR")
    HARNESS_ARGV=(echoagent --session "$CW_SESSION_NAME" "$CW_PROMPT")
    return 0
}

echoagent_resume() {
    local attempt="$1"
    [[ "$attempt" == 1 ]] || return 1
    HARNESS_ENV=("ECHOAGENT_HOME=$CW_HARNESS_DIR")
    HARNESS_ARGV=(echoagent --resume "$CW_SESSION_NAME" "$CW_PROMPT")
    return 0
}
```

Running `cw work myproject sometask --harness echoagent` (or registering the project or account
with that harness) would then call `echoagent_launch`, land in `_harness_exec`, and spawn
`echoagent --session ... "..."` with `ECHOAGENT_HOME` set — never touching any other part of `cw`.
Since `echoagent_doctor`, `echoagent_login` and `echoagent_plugin` are omitted, `harness_doctor`,
`harness_login` and `harness_plugin` are bound to functions that return 1, and any `cw` command
gated on those capabilities degrades or errors accordingly.
