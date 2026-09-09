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
| `custom_provider` | Accepts a non-native provider endpoint |
| `statusline` | Has a statusline `cw` can configure |
| `instructions_file` | Has a user-level instructions file `cw` can install `CLAUDE.md`-equivalent content into |
| `skills` | Has a user-level skills directory `cw` can symlink account skills into |

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
| `CW_HARNESS_DIR` | Credential dir for this account (passed as `$1` context today; becomes account-root-relative in a later change) |
| `CW_SESSION_NAME` | `<account>/<project>/<task>`, or empty |
| `CW_SESSION_REF` | Harness-native session id, or empty |
| `CW_PROMPT` | Prompt text, or empty |
| `CW_MODEL` | Resolved model, or empty |
| `CW_PROVIDER` | Resolved provider, defaults to `native` |
| `CW_EXTRA_FLAGS` | Word-split extra flags, already translated for this harness (see below) |
| `CW_TEAM_ENV` | `HARNESS_ENV` entry enabling agent teams, or empty |

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

Running `cw work myproject sometask` with `CW_HARNESS_DEFAULT=echoagent` (once per-command harness
selection lands) would then call `echoagent_launch`, land in `_harness_exec`, and spawn
`echoagent --session ... "..."` with `ECHOAGENT_HOME` set — never touching any other part of `cw`.
Since `echoagent_doctor`, `echoagent_login` and `echoagent_plugin` are omitted, `harness_doctor`,
`harness_login` and `harness_plugin` are bound to functions that return 1, and any `cw` command
gated on those capabilities degrades or errors accordingly.
