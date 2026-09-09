# Harness-Agnostic Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `cw work` / `review` / `loop` / `plan` / `create` / `open` run on Claude Code, Codex CLI, Pi and OpenCode through a single driver abstraction, with no change to what exists today.

**Architecture:** Every harness invocation is routed through one function pair — a driver builds `HARNESS_ARGV` and `HARNESS_ENV`, and a single `_harness_exec` spawns the process. Drivers are sourced bash files in `lib/harnesses/<name>.sh` that declare capabilities; anything a harness cannot do is gated by `harness_supports` and degrades to a one-line notice. Accounts hold one credential directory per harness, resolved rather than moved, so existing layouts keep working untouched.

**Tech Stack:** Pure bash 4+, python3 for JSON, bats-core for tests. No new runtime dependencies.

**Spec:** `docs/specs/2026-09-09-harness-agnostic.md`

## Global Constraints

- Pure bash 4+ and python3 only. **No jq, no node, no new runtime dependencies.**
- JSON is read and written with inline `python3 -c` or heredocs, never with a parser dependency.
- YAML is parsed with grep/sed patterns, not a full parser.
- Public commands are `cmd_<name>()`; internal helpers are `_<name>()`.
- Output goes through `_log` / `_warn` / `_err` / `_dim` with the existing `$C` / `$BOLD` / `$NC` colours.
- `set -uo pipefail` is already active; guard required args with `${var:?Usage: ...}`.
- **Every comment is a single short line.** No multi-line comment blocks, no docstring-style explanations, in any file this plan touches.
- Comments never reference task numbers, branch names, or issue/PR numbers.
- **No test may touch the real `~/.cw` or the real `~/.claude`.** Every test exports both `CW_HOME` and `HOME` into `$BATS_TEST_TMPDIR`. This is not optional: `_space_done` deletes `$HOME/.claude/skills/acct--*`, so a suite run with the real `HOME` would destroy the user's skill symlinks.
- **No test spawns a real harness binary.** Fakes go first on `PATH`.
- Commits use conventional style (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`).
- A missing `harness` field anywhere means `claude`.
- Do not commit `.tasks/`, `.reviews/`, or `*_NOTES.md`.

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `lib/harnesses/claude.sh` | Claude Code driver — the only implementation until Task 6 |
| `lib/harnesses/codex.sh` | Codex CLI driver |
| `lib/harnesses/pi.sh` | Pi driver |
| `lib/harnesses/opencode.sh` | OpenCode driver |
| `lib/context/github.sh` | GitHub issue/PR fetch via `gh` |
| `lib/context/linear.sh` | Linear issue fetch via GraphQL |
| `lib/context/notion.sh` | Notion page fetch via the Notion API |
| `docs/harness-drivers.md` | The driver contract, for anyone writing a custom driver |
| `tests/run.sh` | Suite entry point |
| `tests/helpers/setup.bash` | `setup_cw_home`, `make_project`, assertion helpers |
| `tests/fakes/claude`, `codex`, `pi`, `opencode` | Recording fake binaries |
| `tests/*.bats` | One file per area |

**Modified files:**

| Path | Change |
|---|---|
| `cw` | All 21 launch sites routed through the harness layer; account/session/CLI changes |
| `install.sh:94-101` | Copy `lib/harnesses/` and `lib/context/` into `$CW_HOME/lib/` |
| `cw-shell-integration.sh:9-13` | Generate aliases from the resolved harness dir |
| `lib/dashboard/server.py:41-50` | Read the account matrix and `harness` instead of testing for `.claude.json` |
| `docs/architecture.md` | Harness abstraction as a fourth concern |
| `docs/getting-started.md:41` | `cw account login` replaces the printed env-var command |
| `CLAUDE.md` | The single-file rule, superseded |
| `README.md` | "One flow, any harness" |
| `demo.tape` | Same ticket in Claude Code and Codex |

**Task ordering rationale:** Task 1 builds the safety net and Task 2 is the pure refactor it proves — the tests are written against *today's* code and must pass unchanged afterwards. Tasks 3–5 build the account, capability and session plumbing that any second harness needs. Codex (Task 6) lands before pi and opencode. `cw doctor --json` (Task 7) lands before `cw account login` (Task 8), which consumes it.

---

## Task 1: Test infrastructure and characterization tests

The brief asks for the refactor as Task 1. It is split in two here for one reason: tests written *before* the refactor, against the current code, and left **byte-unchanged** afterwards are the only thing that actually proves behaviour is identical. Tests written alongside a refactor only prove the refactor matches itself. Task 2 is still the pure refactor and still lands as its own commit before any new harness.

**Files:**
- Create: `tests/run.sh`
- Create: `tests/helpers/setup.bash`
- Create: `tests/fakes/claude`
- Create: `tests/launch_sites.bats`
- Modify: `cw:4727` (the `main "$@"` guard)
- Create: `.gitmodules` (bats submodules)

**Interfaces:**
- Consumes: nothing
- Produces: `setup_cw_home()`, `make_project <name>`, `call <n>` (raw record), `call_count`, `call_argv <n>`, `call_field <n> <key>`, `set_project_account <project> <account>`, `mode_of <file>` — used by every later task's tests. `tests/fakes/claude` writes one record per invocation to `$CW_FAKE_LOG`.
- **`call_argv` truncates a multi-line argv element to its first line**, because it selects lines starting with `arg=`. Any assertion on content inside a prompt must use `call <n>` and a substring match.

- [ ] **Step 1: Vendor bats**

```bash
git submodule add https://github.com/bats-core/bats-core.git tests/bats
git submodule add https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
```

- [ ] **Step 2: Write the suite entry point**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# runs the whole bats suite against a throwaway CW_HOME
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/bats/bin/bats" "$@" "$here"/*.bats
```

```bash
chmod +x tests/run.sh
```

- [ ] **Step 3: Write the recording fake**

Create `tests/fakes/claude`:

```bash
#!/usr/bin/env bash
# records one invocation, then exits with the next code in CW_FAKE_EXIT_SEQ
{
    printf 'bin=%s\n' "$(basename "$0")"
    printf 'cwd=%s\n' "$PWD"
    printf 'env:CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR:-}"
    printf 'env:CODEX_HOME=%s\n' "${CODEX_HOME:-}"
    printf 'env:PI_CODING_AGENT_DIR=%s\n' "${PI_CODING_AGENT_DIR:-}"
    printf 'env:OPENCODE_DATA_DIR=%s\n' "${OPENCODE_DATA_DIR:-}"
    printf 'env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=%s\n' "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}"
    printf 'env:CW_PROJECT=%s\n' "${CW_PROJECT:-}"
    printf 'env:CW_TASK=%s\n' "${CW_TASK:-}"
    printf 'env:CW_TASK_TYPE=%s\n' "${CW_TASK_TYPE:-}"
    for a in "$@"; do printf 'arg=%s\n' "$a"; done
    printf -- '--- end ---\n'
} >> "$CW_FAKE_LOG"

n=0
[[ -f "$CW_FAKE_LOG.n" ]] && n=$(cat "$CW_FAKE_LOG.n")
echo $((n + 1)) > "$CW_FAKE_LOG.n"
read -r -a codes <<< "${CW_FAKE_EXIT_SEQ:-0}"
idx=$(( n < ${#codes[@]} ? n : ${#codes[@]} - 1 ))
exit "${codes[$idx]}"
```

```bash
chmod +x tests/fakes/claude
```

- [ ] **Step 4: Write the test helper**

Create `tests/helpers/setup.bash`:

```bash
# shared setup for every bats file
setup_cw_home() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export CW_HOME="$BATS_TEST_TMPDIR/cw"
    export CW_FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
    mkdir -p "$HOME/.claude/skills"
    mkdir -p "$CW_HOME"/{accounts,sessions,templates/workflows,agents,commands,stacks}
    echo '{}' > "$CW_HOME/projects.json"
    echo '{}' > "$CW_HOME/active-sessions.json"
    printf 'default_account: acct\nskip_permissions: false\nmodels:\n  work: sonnet\n' \
        > "$CW_HOME/config.yaml"
    mkdir -p "$CW_HOME/accounts/acct"
    echo '{"name":"acct","created":"2026-01-01T00:00:00Z"}' \
        > "$CW_HOME/accounts/acct/meta.json"
    export CW_BIN="$BATS_TEST_DIRNAME/../cw"
    export PATH="$BATS_TEST_DIRNAME/fakes:$PATH"
}

# creates a git repo and registers it under the given name
make_project() {
    local name="$1"
    local path="$BATS_TEST_TMPDIR/$name"
    mkdir -p "$path"
    git -C "$path" init -q -b main
    git -C "$path" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    python3 - "$CW_HOME/projects.json" "$name" "$path" <<'PY'
import json, sys
f, name, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(f) as fh: reg = json.load(fh)
reg[name] = {"path": path, "account": "acct", "type": "fullstack"}
with open(f, "w") as fh: json.dump(reg, fh)
PY
    echo "$path"
}

# prints the Nth recorded invocation, 1-indexed
call() {
    awk -v n="$1" 'BEGIN{c=1} /^--- end ---$/{c++; next} c==n' "$CW_FAKE_LOG"
}

call_count() {
    [[ -f "$CW_FAKE_LOG" ]] || { echo 0; return; }
    grep -c '^--- end ---$' "$CW_FAKE_LOG" || true
}

# prints the argv of the Nth invocation, one per line
call_argv() {
    call "$1" | sed -n 's/^arg=//p'
}

call_field() {
    call "$1" | sed -n "s/^$2=//p"
}

# repoints a registered project at another account
set_project_account() {
    python3 - "$CW_HOME/projects.json" "$1" "$2" <<'PYX'
import json, sys
f, project, account = sys.argv[1], sys.argv[2], sys.argv[3]
with open(f) as fh: reg = json.load(fh)
reg[project]["account"] = account
with open(f, "w") as fh: json.dump(reg, fh)
PYX
}

# prints a file's permission bits portably
mode_of() {
    python3 -c "import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[-3:])" "$1"
}
```

- [ ] **Step 5: Make `cw` sourceable**

Modify the last line of `cw` (`cw:4727`):

```bash
# only run when executed, so tests can source the script
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
```

- [ ] **Step 6: Write the characterization tests**

Create `tests/launch_sites.bats`. These assert **current** behaviour and must not change in Task 2.

```bash
load helpers/setup

setup() { setup_cw_home; }

@test "open launches claude in the project dir with the account config dir" {
    local path; path="$(make_project app)"
    run "$CW_BIN" open app
    [ "$(call_count)" -eq 1 ]
    [ "$(call_field 1 cwd)" = "$path" ]
    [ "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" = "$CW_HOME/accounts/acct" ]
    [ -z "$(call_argv 1)" ]
}

@test "launch passes its arguments through verbatim and adds no flags" {
    run "$CW_BIN" launch acct /login
    [ "$(call_count)" -eq 1 ]
    [ "$(call_argv 1)" = "/login" ]
}

@test "work on a new task launches with model, session name and the init prompt" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 1 ]
    [ "$(call_argv 1 | sed -n 1p)" = "--model" ]
    [ "$(call_argv 1 | sed -n 2p)" = "sonnet" ]
    [ "$(call_argv 1 | sed -n 3p)" = "--name" ]
    [ "$(call_argv 1 | sed -n 4p)" = "acct/app/fix-auth" ]
    [[ "$(call_argv 1 | sed -n 5p)" == *"git worktree add .tasks/fix-auth"* ]]
}

@test "work exports the session context variables" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 'env:CW_PROJECT')" = "app" ]
    [ "$(call_field 1 'env:CW_TASK')" = "fix-auth" ]
    [ "$(call_field 1 'env:CW_TASK_TYPE')" = "task" ]
}

@test "work resume walks resume then continue then name when each exits non-zero" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 1 0" run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 3 ]
    [ "$(call_argv 1 | sed -n 3p)" = "--resume" ]
    [ "$(call_argv 2 | sed -n 3p)" = "--continue" ]
    [ "$(call_argv 3 | sed -n 3p)" = "--name" ]
}

@test "work resume stops at the first attempt that succeeds" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="0" run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 1 ]
}

@test "work --team sets the agent teams env var" {
    make_project app >/dev/null
    run "$CW_BIN" work app big --team
    [ "$(call_field 1 'env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')" = "1" ]
}

@test "skip-permissions is word-split into a separate argument" {
    make_project app >/dev/null
    run "$CW_BIN" --skip-permissions work app fix-auth
    [ "$(call_argv 1 | sed -n 1p)" = "--dangerously-skip-permissions" ]
}

@test "review on a new PR launches with the review session name" {
    make_project app >/dev/null
    run "$CW_BIN" review app 123
    [ "$(call_count)" -eq 1 ]
    [ "$(call_argv 1 | sed -n 4p)" = "acct/app/review-pr-123" ]
}

@test "review re-review walks the three step resume chain" {
    make_project app >/dev/null
    "$CW_BIN" review app 123
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 1 0" run "$CW_BIN" review app 123
    [ "$(call_count)" -eq 3 ]
}

@test "loop on a new session passes the slash command as the prompt" {
    make_project app >/dev/null
    run "$CW_BIN" loop app "check the deploy" --every 5m
    [ "$(call_argv 1 | sed -n 5p)" = "/loop 5m check the deploy" ]
}

@test "loop resume walks the three step resume chain" {
    make_project app >/dev/null
    "$CW_BIN" loop app "check the deploy"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 1 0" run "$CW_BIN" loop app "check the deploy"
    [ "$(call_count)" -eq 3 ]
}

@test "plan launches with the plan session name" {
    make_project app >/dev/null
    run "$CW_BIN" plan app "migrate auth"
    [ "$(call_argv 1 | sed -n 4p)" = "acct/app/plan" ]
}

@test "create launches in the new project directory" {
    run "$CW_BIN" create "a tool" --account acct --name newthing --dir "$BATS_TEST_TMPDIR"
    [ "$(call_field 1 cwd)" = "$BATS_TEST_TMPDIR/newthing" ]
    [ "$(call_argv 1 | sed -n 4p)" = "acct/newthing/init" ]
}

@test "work --done closes the session and launches nothing" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth --done
    [ "$(call_count)" -eq 0 ]
    run grep -q '"status": "done"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 7: Run the suite against unmodified `cw`**

Run: `./tests/run.sh`
Expected: **all tests PASS.** They describe what `cw` does today. If any fails, the test is wrong — fix the test, not `cw`. This is the baseline the refactor must preserve.

- [ ] **Step 8: Commit**

```bash
git add .gitmodules tests cw
git commit -m "test: add bats suite characterizing every claude launch site"
```

---

## Task 2: Pure refactor — one place that spawns a harness

Behaviour must be identical. **The tests from Task 1 are not edited in this task.** If a test needs changing, the refactor is wrong.

**Files:**
- Create: `lib/harnesses/claude.sh`
- Modify: `cw` — add the harness layer, rewire all 21 launch sites
- Modify: `install.sh:94-101`

**Interfaces:**
- Consumes: `tests/helpers/setup.bash` from Task 1
- Produces: `_harness_load <name>`, `_harness_exec`, `_harness_launch`, `_harness_resume`, `harness_supports <cap>`, and the globals `HARNESS_ARGV` / `HARNESS_ENV`. Drivers define `<h>_supports`, `<h>_config_env`, `<h>_launch`, `<h>_resume <attempt>`, `<h>_session_ref`, `<h>_doctor`, `<h>_login`.

- [ ] **Step 1: Write the claude driver**

Create `lib/harnesses/claude.sh`:

```bash
# claude code driver
claude_supports() {
    case "$1" in
        resume_by_name|continue_last|non_interactive_prompt|interactive_prompt) return 0 ;;
        mcp|hooks|skip_permissions|agent_teams|plugins) return 0 ;;
        model_flag|statusline|instructions_file|skills|custom_provider) return 0 ;;
        *) return 1 ;;
    esac
}

claude_config_env() {
    printf 'CLAUDE_CONFIG_DIR=%s\n' "$CW_HARNESS_DIR"
}

claude_session_ref() {
    printf '%s' ""
}

# builds the common prefix shared by launch and resume
_claude_base_argv() {
    HARNESS_ARGV=(claude)
    local f
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    return 0
}

_claude_base_env() {
    HARNESS_ENV=("CLAUDE_CONFIG_DIR=$CW_HARNESS_DIR")
    [[ -n "${CW_TEAM_ENV:-}" ]] && HARNESS_ENV+=("$CW_TEAM_ENV")
    return 0
}

claude_launch() {
    _claude_base_env
    if [[ -n "${CW_PASSTHRU_ARGV+x}" ]]; then
        HARNESS_ARGV=(claude "${CW_PASSTHRU_ARGV[@]}")
        return 0
    fi
    _claude_base_argv
    [[ -n "$CW_SESSION_NAME" ]] && HARNESS_ARGV+=(--name "$CW_SESSION_NAME")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

# three attempts: resume by name, continue last, start named
claude_resume() {
    local attempt="$1"
    _claude_base_env
    _claude_base_argv
    case "$attempt" in
        1) HARNESS_ARGV+=(--resume "$CW_SESSION_NAME") ;;
        2) HARNESS_ARGV+=(--continue) ;;
        3) HARNESS_ARGV+=(--name "$CW_SESSION_NAME") ;;
        *) return 1 ;;
    esac
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}
```

- [ ] **Step 2: Add the harness layer to `cw`**

Insert after `_get_field` (around `cw:154`):

```bash
CW_HARNESS_DEFAULT="claude"

# sources a driver and aliases its functions to the generic names
_harness_load() {
    local h="${1:?Usage: _harness_load <harness>}"
    [[ "${_CW_HARNESS_LOADED:-}" == "$h" ]] && return 0
    local candidate found=""
    for candidate in "$CW_HOME/harnesses/$h.sh" \
                     "$SCRIPT_DIR/../lib/harnesses/$h.sh" \
                     "$SCRIPT_DIR/lib/harnesses/$h.sh"; do
        [[ -f "$candidate" ]] && { found="$candidate"; break; }
    done
    [[ -n "$found" ]] || { _err "Unknown harness '$h'."; return 1; }
    # shellcheck disable=SC1090
    source "$found"
    local fn
    for fn in supports config_env session_ref launch resume doctor login; do
        if declare -F "${h}_${fn}" >/dev/null; then
            eval "harness_${fn}() { ${h}_${fn} \"\$@\"; }"
        else
            eval "harness_${fn}() { return 1; }"
        fi
    done
    _CW_HARNESS_LOADED="$h"
    return 0
}

# the only place in cw that starts a harness process
_harness_exec() {
    env "${HARNESS_ENV[@]}" "${HARNESS_ARGV[@]}"
}

_harness_launch() {
    HARNESS_ARGV=(); HARNESS_ENV=()
    harness_launch || return 1
    _harness_exec
}

# tries each resume attempt until one succeeds
_harness_resume() {
    local attempt=1 rc=1
    while :; do
        HARNESS_ARGV=(); HARNESS_ENV=()
        harness_resume "$attempt" || break
        _harness_exec && return 0
        rc=$?
        attempt=$((attempt + 1))
    done
    return $rc
}
```

- [ ] **Step 3: Add the context-setting helper**

Insert directly after `_harness_resume`:

```bash
# sets the globals every driver reads
_harness_context() {
    CW_HARNESS="${CW_HARNESS:-$CW_HARNESS_DEFAULT}"
    CW_HARNESS_DIR="${CW_HARNESS_DIR:-$CW_ACCOUNTS_DIR/$CW_ACCOUNT}"
    CW_SESSION_NAME="${CW_SESSION_NAME:-}"
    CW_SESSION_REF="${CW_SESSION_REF:-}"
    CW_PROMPT="${CW_PROMPT:-}"
    CW_MODEL="${CW_MODEL:-}"
    CW_PROVIDER="${CW_PROVIDER:-native}"
    CW_EXTRA_FLAGS="${CW_EXTRA_FLAGS:-$CW_CLAUDE_FLAGS}"
    export CW_PROJECT CW_TASK CW_TASK_TYPE CW_ACCOUNT
}
```

- [ ] **Step 4: Rewire `cmd_open` (`cw:921`)**

Replace `CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS` with:

```bash
    CW_ACCOUNT="$account" CW_HARNESS_DIR="$acct_dir" CW_TASK_TYPE="open" \
    CW_PROJECT="$name" CW_TASK="" CW_SESSION_NAME="" CW_PROMPT="" CW_MODEL=""
    _harness_load "$CW_HARNESS_DEFAULT" || return 1
    _harness_context
    _harness_launch
```

- [ ] **Step 5: Rewire `cmd_launch` (`cw:938`)**

Replace `CLAUDE_CONFIG_DIR="$dir" claude "$@"` with:

```bash
    CW_ACCOUNT="$account" CW_HARNESS_DIR="$dir" CW_TASK_TYPE="launch"
    CW_PASSTHRU_ARGV=("$@")
    CW_EXTRA_FLAGS=""
    _harness_load "$CW_HARNESS_DEFAULT" || return 1
    _harness_context
    _harness_launch
    unset CW_PASSTHRU_ARGV
```

- [ ] **Step 6: Rewire the remaining 19 sites**

Apply the same pattern at each site from the inventory. Fresh launches become `_harness_launch`; three-step chains become a single `_harness_resume`.

| Lines | Command | Replace with |
|---|---|---|
| `cw:1166-1168` | review re-review | one `_harness_resume` |
| `cw:1254` | review new | `_harness_launch` |
| `cw:1469` | loop new | `_harness_launch` |
| `cw:1473-1475` | loop resume | one `_harness_resume` |
| `cw:1873` | work new | `_harness_launch` |
| `cw:1903-1905` | work resume | one `_harness_resume` |
| `cw:1909`, `1911`, `1913` | work new, no init prompt | `_harness_launch` with `CW_PROMPT` set or empty |
| `cw:2586` | plan | `_harness_launch` |
| `cw:4550` | create | `_harness_launch` |

For the three `work` fallback branches, set `CW_TEAM_ENV="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"` when `$team_flag`, and leave it unset otherwise — that reproduces today's `env $team_env` with an empty `$team_env`.

- [ ] **Step 7: Route the two plugin sites (`cw:3983`, `cw:3988`)**

In `_stack_apply`, replace the `claude plugin` calls with a capability check. Note this also fixes an existing bug: the probe at `cw:3983` runs without `CLAUDE_CONFIG_DIR` and so checks the ambient `~/.claude`.

```bash
                    if ! harness_supports plugins; then
                        _dim "  $CW_HARNESS has no plugin support — skipping $plugin"
                        continue
                    fi
                    HARNESS_ENV=("CLAUDE_CONFIG_DIR=$acct_dir")
                    HARNESS_ARGV=(claude plugin list)
                    if _harness_exec 2>/dev/null | grep -q "$plugin"; then
                        _dim "  Plugin $plugin already installed"
                    else
                        _log "  Installing plugin: ${C}$plugin${NC}"
                        HARNESS_ARGV=(claude plugin add "$plugin")
                        _harness_exec 2>/dev/null || _warn "  Could not install plugin $plugin"
                    fi
```

**Behaviour change to record, not revert:** `_harness_context` exports `CW_PROJECT`, `CW_TASK`,
`CW_TASK_TYPE` and `CW_ACCOUNT`, so the `review` and `loop` fallback resume attempts now carry them
where previously only the first attempt did. `hooks/scripts/review-autoclose.py` gates on
`CW_TASK_TYPE == "review"`, so a review resumed via `--continue` now auto-closes where before it
silently did not. This is a fix and it is intentional; it goes in the CHANGELOG under Fixed.

- [ ] **Step 8: Teach `install.sh` about the new directories**

Modify `install.sh` after line 95:

```bash
    for sub in harnesses context; do
        if [[ -d "$source_dir/lib/$sub" ]]; then
            mkdir -p "$CW_HOME/lib/$sub"
            cp "$source_dir"/lib/$sub/*.sh "$CW_HOME/lib/$sub/" 2>/dev/null || true
        fi
    done
```

- [ ] **Step 9: Run the Task 1 suite unchanged**

Run: `./tests/run.sh`
Expected: **all tests PASS, with zero edits to `tests/launch_sites.bats`.**

- [ ] **Step 10: Add the no-direct-launch guard**

Create `tests/no_direct_launch.bats`:

```bash
load helpers/setup

@test "no harness binary is spawned outside lib/harnesses" {
    run grep -nE '(^|[;&|] *|env [^;|]* )(claude|codex|pi|opencode)( +[-$"]|$)' \
        "$BATS_TEST_DIRNAME/../cw"
    [ "$status" -ne 0 ]
}
```

Run: `./tests/run.sh`
Expected: PASS. If it fails it prints the offending line, which is a launch site the refactor missed. The pattern anchors on execution shape rather than on the bare binary name because `pi` matches ordinary prose.

- [ ] **Step 11: Commit**

```bash
git add cw lib/harnesses install.sh tests/no_direct_launch.bats
git commit -m "refactor: route every claude launch through the harness layer"
```

---

## Task 3: Driver contract, capabilities and degradation

**Files:**
- Modify: `cw` — gate every Claude-only feature behind `harness_supports`
- Create: `docs/harness-drivers.md`
- Create: `tests/capabilities.bats`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `_harness_load`, `harness_supports` from Task 2
- Produces: `_degrade <capability> <message>` — prints one dim line the first time a capability is missing in a command, and returns 1 so callers can skip.

- [ ] **Step 1: Write the failing test**

Create `tests/capabilities.bats`:

```bash
load helpers/setup

setup() { setup_cw_home; }

@test "claude supports every capability it needs today" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/harnesses/claude.sh'
                 for c in resume_by_name continue_last mcp hooks skip_permissions \
                          agent_teams plugins model_flag statusline skills; do
                     claude_supports \$c || { echo \"missing \$c\"; exit 1; }
                 done"
    [ "$status" -eq 0 ]
}

@test "an unknown capability is unsupported" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/harnesses/claude.sh'
                 claude_supports teleportation"
    [ "$status" -ne 0 ]
}

@test "degrade prints once per command and returns non-zero" {
    run bash -c "source '$CW_BIN'
                 CW_HARNESS=fakeharness
                 _degrade agent_teams 'no agent teams'
                 _degrade agent_teams 'no agent teams'"
    [ "$status" -ne 0 ]
    [ "$(echo "$output" | grep -c 'no agent teams')" -eq 1 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/capabilities.bats`
Expected: FAIL — `_degrade: command not found`.

- [ ] **Step 3: Implement `_degrade`**

Insert into `cw` after `_harness_context`:

```bash
# says once per command that a capability is missing, then returns 1
_degrade() {
    local cap="$1" msg="$2"
    local seen="_CW_DEGRADED_${cap}"
    if [[ -z "${!seen:-}" ]]; then
        _dim "  $msg (harness: ${CW_HARNESS:-claude})"
        eval "$seen=1"
    fi
    return 1
}
```

- [ ] **Step 4: Gate the Claude-only features**

`_ensure_statusline` — return early:

```bash
_ensure_statusline() {
    local acct_dir="${1:?Usage: _ensure_statusline <acct_dir>}"
    harness_supports statusline || return 0
```

`_use_platform_default_model` — same guard on `model_flag`.

The account skills symlink block, which appears at `cw:1083`, `cw:1408` and `cw:1798`, is
duplicated three times. Extract it once and gate it:

```bash
# symlinks account skills where the harness looks for them
_link_account_skills() {
    local account="$1" acct_root="$2"
    harness_supports skills || return 0
    local skills_dir="$acct_root/skills"
    [[ -d "$skills_dir" ]] || return 0
    local skill_dir skill_name target
    for skill_dir in "$skills_dir"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name=$(basename "$skill_dir")
        case "$skill_name" in acct--*) continue ;; esac
        target="$HOME/.claude/skills/acct--${account}--${skill_name}"
        [[ -e "$target" ]] || ln -sf "$skill_dir" "$target"
    done
}
```

Replace all three copies with `_link_account_skills "$account" "$acct_root"`.

`--team` in `cmd_work` and `cmd_create`:

```bash
    if $team_flag; then
        if harness_supports agent_teams; then
            CW_TEAM_ENV="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
            _log "Agent teams ${G}enabled${NC}"
        else
            _degrade agent_teams "Agent teams not supported — running without a team" || true
        fi
    fi
```

`cmd_mcp` and `_project_setup_mcps` error instead of degrading, because the user asked for MCP by name:

```bash
    if ! harness_supports mcp; then
        _err "Harness '$CW_HARNESS' has no MCP support that cw can configure."
        return 1
    fi
```

`_arcade_setup_hooks` — skip accounts whose harness lacks hooks, keep going:

```bash
        if ! harness_supports hooks; then
            _dim "  ${C}$acct${NC} — harness has no hooks, skipping"
            continue
        fi
```

- [ ] **Step 5: Map `--skip-permissions` through the capability**

In `_resolve_claude_flags`, keep the resolved value in `CW_CLAUDE_FLAGS` and add a translation
step used by `_harness_context`:

```bash
# translates the skip-permissions request to whatever the harness calls it
_harness_extra_flags() {
    local flags="${CW_CLAUDE_FLAGS:-}"
    local per_harness_var="CW_$(echo "$CW_HARNESS" | tr '[:lower:]' '[:upper:]')_FLAGS"
    flags="$flags ${!per_harness_var:-}"
    if [[ "$flags" == *--dangerously-skip-permissions* ]] && ! harness_supports skip_permissions; then
        flags="${flags//--dangerously-skip-permissions/}"
        _degrade skip_permissions "Harness has no skip-permissions flag — prompts stay on" || true
    fi
    printf '%s' "$flags"
}
```

Set `CW_EXTRA_FLAGS="$(_harness_extra_flags)"` inside `_harness_context`, replacing the direct
`$CW_CLAUDE_FLAGS` default.

- [ ] **Step 6: Run the tests**

Run: `./tests/run.sh`
Expected: PASS — including every Task 1 characterization test, still unedited.

- [ ] **Step 7: Write the driver contract doc**

Create `docs/harness-drivers.md` documenting: the seven functions and their contracts, the
capability enumeration, the `CW_*` globals a driver may read, `HARNESS_ARGV` / `HARNESS_ENV`, the
search order `$CW_HOME/harnesses/` then `lib/harnesses/`, and a complete worked example of a
minimal custom driver. Content comes from §3 of the spec.

- [ ] **Step 8: Update `CLAUDE.md`**

Replace the "Do NOT break the single-file architecture of the `cw` script" bullet with:

```markdown
- Keep command logic in the single `cw` script; harness drivers live in `lib/harnesses/<name>.sh`
  and context fetchers in `lib/context/<source>.sh`
```

- [ ] **Step 9: Commit**

```bash
git add cw docs/harness-drivers.md CLAUDE.md tests/capabilities.bats
git commit -m "feat: add harness capability gating and driver contract docs"
```

---

## Task 4: Account layout with per-harness credential dirs

**Files:**
- Modify: `cw` — `_account_root`, `_harness_dir`, replace `_resolve_account_dir`
- Modify: `cw-shell-integration.sh:9-13`
- Create: `tests/account_layout.bats`

**Interfaces:**
- Consumes: `_harness_load` from Task 2
- Produces: `_account_root <account>` prints `$CW_ACCOUNTS_DIR/<account>`; `_harness_dir <account> <harness>` prints the credential dir; `_resolve_account [--account a] [project]` prints the account **name**; `_account_meta_get <account> <harness> <field>` prints a value from `meta.json`; `_account_meta_set <account> <harness> <field> <value>`.

- [ ] **Step 1: Write the failing test**

Create `tests/account_layout.bats`:

```bash
load helpers/setup

setup() { setup_cw_home; }

@test "a legacy flat account resolves claude to the account root" {
    run bash -c "source '$CW_BIN'; _harness_dir acct claude"
    [ "$output" = "$CW_HOME/accounts/acct" ]
}

@test "a legacy flat account resolves codex to a subdir" {
    run bash -c "source '$CW_BIN'; _harness_dir acct codex"
    [ "$output" = "$CW_HOME/accounts/acct/codex" ]
}

@test "a split account resolves claude to the claude subdir" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    run bash -c "source '$CW_BIN'; _harness_dir acct claude"
    [ "$output" = "$CW_HOME/accounts/acct/claude" ]
}

@test "resolve_account returns the name, not a path" {
    run bash -c "source '$CW_BIN'; _resolve_account --account acct"
    [ "$output" = "acct" ]
}

@test "mcp list names the account, not the harness dir" {
    run "$CW_BIN" mcp list --account acct
    [[ "$output" == *"account acct"* ]]
    [[ "$output" != *"account claude"* ]]
}

@test "account meta round-trips a per-harness model" {
    bash -c "source '$CW_BIN'; _account_meta_set acct codex model gpt-5-codex"
    run bash -c "source '$CW_BIN'; _account_meta_get acct codex model"
    [ "$output" = "gpt-5-codex" ]
}

@test "an account with no harness field defaults to claude" {
    run bash -c "source '$CW_BIN'; _account_default_harness acct"
    [ "$output" = "claude" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/account_layout.bats`
Expected: FAIL — `_harness_dir: command not found`.

- [ ] **Step 3: Implement the resolution functions**

Insert into `cw` after `_get_field`:

```bash
_account_root() {
    printf '%s' "$CW_ACCOUNTS_DIR/${1:?Usage: _account_root <account>}"
}

# claude keeps the legacy flat dir unless a claude subdir exists
_harness_dir() {
    local account="${1:?Usage: _harness_dir <account> <harness>}" harness="${2:?}"
    local root; root="$(_account_root "$account")"
    if [[ "$harness" == "claude" && ! -d "$root/claude" ]]; then
        printf '%s' "$root"
    else
        printf '%s' "$root/$harness"
    fi
}

_account_meta_get() {
    local account="$1" harness="$2" field="$3"
    local meta; meta="$(_account_root "$account")/meta.json"
    [[ -f "$meta" ]] || return 0
    python3 - "$meta" "$harness" "$field" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f: m = json.load(f)
except Exception:
    sys.exit(0)
v = m.get("harnesses", {}).get(sys.argv[2], {}).get(sys.argv[3])
print(v if v is not None else "")
PY
}

_account_meta_set() {
    local account="$1" harness="$2" field="$3" value="$4"
    local meta; meta="$(_account_root "$account")/meta.json"
    python3 - "$meta" "$harness" "$field" "$value" <<'PY'
import json, os, sys
p, harness, field, value = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(p) as f: m = json.load(f)
except Exception:
    m = {}
m.setdefault("harnesses", {}).setdefault(harness, {})[field] = value or None
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, "w") as f: json.dump(m, f, indent=2)
PY
}

_account_default_harness() {
    local account="$1"
    local meta; meta="$(_account_root "$account")/meta.json"
    local h=""
    if [[ -f "$meta" ]]; then
        h=$(python3 -c "
import json
try: print(json.load(open('$meta')).get('harness') or '')
except Exception: print('')
" 2>/dev/null)
    fi
    printf '%s' "${h:-$CW_HARNESS_DEFAULT}"
}
```

- [ ] **Step 4: Replace `_resolve_account_dir`**

`_resolve_account_dir` (`cw:562`) returns a path that callers use as both identity and config
location. Replace it with a name-returning version and fix the three `basename` sites:

```bash
# resolves an account name from a flag, a project, or the default
_resolve_account() {
    local account="" project=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account|-a) account="${2:?--account requires a value}"; shift 2 ;;
            *) project="$1"; shift ;;
        esac
    done
    if [[ -n "$account" ]]; then
        [[ -d "$(_account_root "$account")" ]] || { _err "Account '$account' not found."; return 1; }
        printf '%s' "$account"; return 0
    fi
    if [[ -n "$project" ]]; then
        local pj; pj=$(_get_project "$project") || { _err "Project '$project' not found."; return 1; }
        _get_field "$pj" account "$(_default_account)"; return 0
    fi
    account=$(_default_account)
    [[ -n "$account" ]] || { _err "No account specified and no default account."; return 1; }
    printf '%s' "$account"
}
```

In `_mcp_add`, `_mcp_remove` and `_mcp_list`, replace the `acct_dir=$(_resolve_account_dir …)`
plus `account=$(basename "$acct_dir")` pairs with:

```bash
    local account; account=$(_resolve_account ${account_flag:+--account "$account_flag"} ${project_flag:+"$project_flag"}) || return 1
    local settings_file; settings_file="$(_harness_dir "$account" claude)/settings.json"
```

- [ ] **Step 5: Point every settings.json and auth check at `_harness_dir`**

| Site | Change |
|---|---|
| `_ensure_statusline` calls | pass `$(_harness_dir "$account" "$CW_HARNESS")` |
| `_use_platform_default_model` calls | same |
| `_project_setup_mcps` `cw:426` | `_harness_dir "$account" claude` |
| `cmd_account list` `cw:268` | auth via `harness_doctor`, not `.claude.json` |
| `cmd_doctor` `cw:2288` | same |
| `cmd_dashboard` `cw:2766` | same |
| account templates `cw:1735`, `cw:1885` | `$(_account_root "$account")/templates/…` |
| `_link_account_skills` | `$(_account_root "$account")/skills` |
| `_space_done` `cw:2035` | iterate `$CW_ACCOUNTS_DIR/*/skills/acct--*` at the root level |

- [ ] **Step 6: Install the account instructions file per harness**

`accounts/<name>/CLAUDE.md` works today only because the account dir *is* the Claude config dir.
Under the split layout it would go silently dead, so it becomes explicit.

Add to `cw`:

```bash
# puts the account instructions file where the harness looks for it
_install_account_instructions() {
    local account="$1" harness="$2" dir="$3"
    harness_supports instructions_file || return 0
    local src; src="$(_account_root "$account")/CLAUDE.md"
    [[ -f "$src" ]] || return 0
    local dest
    case "$harness" in
        claude) dest="$dir/CLAUDE.md" ;;
        codex)  dest="$dir/AGENTS.md" ;;
        *)      return 0 ;;
    esac
    [[ "$src" -ef "$dest" ]] && return 0
    ln -sf "$src" "$dest"
}
```

Call it from `_harness_context` after `CW_HARNESS_DIR` is known. The `-ef` guard makes it a
no-op for a legacy flat account, where source and destination are the same path.

Add to `tests/account_layout.bats`:

```bash
@test "the account instructions file is linked into a split claude dir" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    [ -L "$CW_HOME/accounts/acct/claude/CLAUDE.md" ]
    run cat "$CW_HOME/accounts/acct/claude/CLAUDE.md"
    [ "$output" = "account rules" ]
}

@test "a legacy flat account does not link the file onto itself" {
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    [ ! -L "$CW_HOME/accounts/acct/CLAUDE.md" ]
}
```

- [ ] **Step 7: Update the shell integration**

Modify `cw-shell-integration.sh:9-13`:

```bash
    [[ -d "$CW_HOME/accounts" ]] || return
    for d in "$CW_HOME/accounts"/*/; do
        local n; n="$(basename "$d")"
        local cdir="$d"
        [[ -d "$d/claude" ]] && cdir="$d/claude"
        alias "claude-$n"="CLAUDE_CONFIG_DIR=${cdir} claude"
    done
```

- [ ] **Step 8: Run the tests**

Run: `./tests/run.sh`
Expected: PASS, Task 1 tests still unedited.

- [ ] **Step 9: Commit**

```bash
git add cw cw-shell-integration.sh tests/account_layout.bats
git commit -m "feat: resolve per-harness account credential directories"
```

---

## Task 5: Session metadata and harness resolution

**Files:**
- Modify: `cw` — `--harness` flag on six commands, `session.json` fields, refusal on mismatch
- Create: `tests/session_harness.bats`

**Interfaces:**
- Consumes: `_account_default_harness`, `_harness_dir` from Task 4
- Produces: `_resolve_harness <account> <project> <session_meta> <override>` prints the harness name and returns 1 on a refused override. `session.json` gains `harness`, `harness_session_id`, `provider`.

- [ ] **Step 1: Write the failing test**

Create `tests/session_harness.bats`:

```bash
load helpers/setup

setup() { setup_cw_home; }

@test "a new session records claude when nothing specifies a harness" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    run grep -q '"harness": "claude"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}

@test "a session with no harness field is treated as claude" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    python3 - "$CW_HOME/sessions/app/task-fix-auth/session.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m.pop("harness", None)
json.dump(m, open(p, "w"))
PY
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" = "$CW_HOME/accounts/acct" ]
}

@test "--harness on a new session is recorded" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth --harness codex
    run grep -q '"harness": "codex"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}

@test "--harness disagreeing with an existing session is refused" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -ne 0 ]
    [[ "$output" == *"was created with claude"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "the project harness overrides the account default" {
    local path; path="$(make_project app)"
    python3 - "$CW_HOME/projects.json" <<'PY'
import json, sys
f = sys.argv[1]
reg = json.load(open(f)); reg["app"]["harness"] = "codex"
json.dump(reg, open(f, "w"))
PY
    run "$CW_BIN" work app fix-auth
    run grep -q '"harness": "codex"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/session_harness.bats`
Expected: FAIL — `session.json` has no `harness` key.

- [ ] **Step 3: Implement harness resolution**

```bash
# resolves the harness for a command, refusing an override that fights a session
_resolve_harness() {
    local account="$1" project="$2" session_meta="$3" override="$4"
    local recorded=""
    if [[ -f "$session_meta" ]]; then
        recorded=$(python3 -c "
import json
try: print(json.load(open('$session_meta')).get('harness') or '')
except Exception: print('')
" 2>/dev/null)
        [[ -z "$recorded" ]] && recorded="$CW_HARNESS_DEFAULT"
    fi
    if [[ -n "$recorded" ]]; then
        if [[ -n "$override" && "$override" != "$recorded" ]]; then
            _err "Session was created with $recorded. Refusing to resume it with $override."
            _err "Close it first, then create a new one with the harness you want."
            return 1
        fi
        printf '%s' "$recorded"; return 0
    fi
    if [[ -n "$override" ]]; then printf '%s' "$override"; return 0; fi
    local pj proj_harness=""
    if [[ -n "$project" ]] && pj=$(_get_project "$project" 2>/dev/null); then
        proj_harness=$(_get_field "$pj" harness "")
    fi
    if [[ -n "$proj_harness" ]]; then printf '%s' "$proj_harness"; return 0; fi
    _account_default_harness "$account"
}
```

- [ ] **Step 4: Add `--harness` to the six commands**

Add to the arg loop of `cmd_work`, `cmd_review`, `cmd_loop`, `cmd_plan`, `cmd_create`, `cmd_open`:

```bash
            --harness|-H) harness_override="$2"; shift 2 ;;
```

And in `_project_register`:

```bash
            --harness|-H) harness="$2"; shift 2 ;;
```

writing `harness` into the `projects.json` entry when non-empty.

- [ ] **Step 5: Write the new session fields**

In each command's session-creation python block, add:

```python
    'harness': '$harness',
    'harness_session_id': '',
    'provider': '$provider',
```

And after a successful launch, record the harness's own session reference when it has one:

```bash
    local ref; ref=$(harness_session_ref 2>/dev/null || true)
    if [[ -n "$ref" ]]; then
        CW_META="$session_meta" CW_REF="$ref" python3 - <<'PY'
import json, os
p = os.environ['CW_META']
with open(p) as f: meta = json.load(f)
meta['harness_session_id'] = os.environ['CW_REF']
with open(p, 'w') as f: json.dump(meta, f, indent=2)
PY
    fi
```

- [ ] **Step 6: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add cw tests/session_harness.bats
git commit -m "feat: record harness per session and resolve it per command"
```

---

## Task 6: Codex driver

Stop here for review once this works end to end.

**Files:**
- Create: `lib/harnesses/codex.sh`
- Create: `tests/fakes/codex`
- Create: `tests/driver_codex.bats`

**Interfaces:**
- Consumes: `_harness_load`, `_harness_exec`, `_harness_resume` from Task 2; `_harness_dir` from Task 4
- Produces: `codex_supports`, `codex_config_env`, `codex_launch`, `codex_resume`, `codex_session_ref`, `codex_doctor`, `codex_login`

**Verify before writing code:** codex's interactive launch argv, its skip-permissions flag, and whether `AGENTS.md` is the instructions file. Confirmed already: `CODEX_HOME`, `codex login --device-auth`, `codex login --with-api-key` reading stdin, `codex resume --last`, `codex resume <id>`, `codex exec resume --last "prompt"`, and that `--last` is scoped to the working directory.

- [ ] **Step 1: Write the fake**

Create `tests/fakes/codex` with the same body as `tests/fakes/claude` from Task 1, Step 3 — the fake reads `$0` for the binary name, so the file is a copy:

```bash
cp tests/fakes/claude tests/fakes/codex
chmod +x tests/fakes/codex
```

- [ ] **Step 2: Write the failing test**

Create `tests/driver_codex.bats`:

```bash
load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
}

@test "codex launches with CODEX_HOME pointing at the per-harness dir" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 bin)" = "codex" ]
    [ "$(call_field 1 'env:CODEX_HOME')" = "$CW_HOME/accounts/acct/codex" ]
    [ -z "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" ]
}

@test "codex never receives claude session-name flags" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    run bash -c "call_argv 1 | grep -c -- '--name'"
    [ "$output" = "0" ]
}

@test "codex resume uses resume --last from the working directory" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$(call_argv 1 | sed -n 1p)" = "resume" ]
    [ "$(call_argv 1 | sed -n 2p)" = "--last" ]
}

@test "codex resume falls back to a recorded session id" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    python3 - "$CW_HOME/sessions/app/task-fix-auth/session.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness_session_id"] = "abc-123"
json.dump(m, open(p, "w"))
PY
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 0" run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 2 ]
    [ "$(call_argv 2 | sed -n 2p)" = "abc-123" ]
}

@test "codex degrades agent teams instead of failing" {
    make_project app >/dev/null
    run "$CW_BIN" work app big --team
    [ "$status" -eq 0 ]
    [[ "$output" == *"Agent teams not supported"* ]]
    [ -z "$(call_field 1 'env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')" ]
}

@test "cw mcp errors on codex rather than writing claude settings" {
    run "$CW_BIN" mcp list --account acct
    [ "$status" -ne 0 ]
    [[ "$output" == *"no MCP support"* ]]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `./tests/run.sh tests/driver_codex.bats`
Expected: FAIL — `Unknown harness 'codex'`.

- [ ] **Step 4: Write the driver**

Create `lib/harnesses/codex.sh`:

```bash
# codex cli driver
codex_supports() {
    case "$1" in
        continue_last|non_interactive_prompt|model_flag|custom_provider) return 0 ;;
        instructions_file) return 0 ;;
        *) return 1 ;;
    esac
}

codex_config_env() {
    printf 'CODEX_HOME=%s\n' "$CW_HARNESS_DIR"
}

# codex has no name cw controls; the id is discovered after the run
codex_session_ref() {
    printf '%s' ""
}

_codex_base() {
    HARNESS_ENV=("CODEX_HOME=$CW_HARNESS_DIR")
    [[ -f "$CW_HARNESS_DIR/env" ]] && HARNESS_ENV+=("$(_harness_env_file "$CW_HARNESS_DIR/env")")
    HARNESS_ARGV=(codex)
    local f
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    return 0
}

codex_launch() {
    _codex_base
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

# resume the last session started in this directory, then a recorded id
codex_resume() {
    local attempt="$1"
    _codex_base
    case "$attempt" in
        1) HARNESS_ARGV+=(resume --last) ;;
        2) [[ -n "$CW_SESSION_REF" ]] || return 1
           HARNESS_ARGV+=(resume "$CW_SESSION_REF") ;;
        *) return 1 ;;
    esac
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

codex_doctor() {
    local status detail="null"
    if ! command -v codex >/dev/null 2>&1; then
        status="not_installed"; detail='"codex not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/auth.json" || -f "$CW_HARNESS_DIR/env" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"codex","status":"%s","detail":%s}\n' "$status" "$detail"
}

codex_login() {
    HARNESS_ENV=("CODEX_HOME=$CW_HARNESS_DIR")
    HARNESS_ARGV=(codex login)
    [[ -n "${CW_LOGIN_NO_BROWSER:-}" ]] && HARNESS_ARGV+=(--device-auth)
    [[ -n "${CW_LOGIN_API_KEY_STDIN:-}" ]] && HARNESS_ARGV=(codex login --with-api-key)
    return 0
}
```

- [ ] **Step 5: Add the env-file helper to `cw`**

Insert after `_harness_context`:

```bash
# reads KEY=VALUE lines from a 600 env file for the harness process only
_harness_env_file() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    grep -E '^[A-Z_][A-Z0-9_]*=' "$f" | tr '\n' ' '
}
```

- [ ] **Step 6: Run the tests**

Run: `./tests/run.sh`
Expected: PASS, including every earlier test.

- [ ] **Step 7: Verify the end-to-end acceptance case by hand**

Once codex is installed, with `CW_HOME` pointed at a scratch directory:

```bash
CW_HOME=/tmp/cw-scratch cw account add work --harness codex
CW_HOME=/tmp/cw-scratch cw account login work --harness codex
CW_HOME=/tmp/cw-scratch cw project register ~/some/repo --account work
CW_HOME=/tmp/cw-scratch cw work some-repo test-task
```

Expected: codex starts in the worktree with `CODEX_HOME` set to the account's codex dir.
**Never run this against the real `~/.cw`.**

- [ ] **Step 8: Commit**

```bash
git add lib/harnesses/codex.sh tests/fakes/codex tests/driver_codex.bats cw
git commit -m "feat: add codex driver"
```

---

## Task 7: `cw doctor --json` and `cw harness`

Lands before the login command, which consumes this output.

**Files:**
- Modify: `cw` — `cmd_doctor` gains `--json` and the account × harness matrix
- Create: `cmd_harness` in `cw`
- Create: `tests/doctor_json.bats`

**Interfaces:**
- Consumes: `_harness_dir`, `_account_meta_get`, `harness_doctor` from Tasks 4 and 6
- Produces: `_doctor_matrix_json` prints the `accounts` array; `cmd_harness list|doctor`

- [ ] **Step 1: Write the failing test**

Create `tests/doctor_json.bats`:

```bash
load helpers/setup

setup() { setup_cw_home; }

@test "doctor --json emits parseable json and nothing else" {
    run "$CW_BIN" doctor --json
    [ "$status" -eq 0 ]
    run bash -c "'$CW_BIN' doctor --json | python3 -c 'import json,sys; json.load(sys.stdin)'"
    [ "$status" -eq 0 ]
}

@test "doctor --json reports the schema version and every account" {
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d[\"schema\"] == 1, d
assert [a[\"name\"] for a in d[\"accounts\"]] == [\"acct\"], d
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "doctor --json marks an uninstalled harness as not_installed" {
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
by = {h[\"name\"]: h for h in d[\"harnesses\"]}
assert by[\"opencode\"][\"installed\"] is False, by
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "doctor --json reports the layout of a legacy account" {
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d[\"accounts\"][0][\"layout\"] == \"legacy\", d
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "doctor --json reports a split account layout" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d[\"accounts\"][0][\"layout\"] == \"split\", d
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "harness list shows the built-in drivers" {
    run "$CW_BIN" harness list
    [[ "$output" == *claude* ]]
    [[ "$output" == *codex* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/doctor_json.bats`
Expected: FAIL — `doctor --json` prints coloured human output that is not JSON.

- [ ] **Step 3: Implement the matrix**

```bash
CW_HARNESS_ALL="claude codex pi opencode"

# prints the account x harness matrix as json
_doctor_matrix_json() {
    local first_a=true account root layout h dir status detail
    printf '['
    for root in "$CW_ACCOUNTS_DIR"/*/; do
        [[ -d "$root" ]] || continue
        account=$(basename "$root")
        layout="legacy"; [[ -d "$root/claude" ]] && layout="split"
        $first_a || printf ','
        first_a=false
        printf '{"name":%s,"root":%s,"layout":"%s","default_harness":"%s","harnesses":[' \
            "$(_json_str "$account")" "$(_json_str "${root%/}")" \
            "$layout" "$(_account_default_harness "$account")"
        local first_h=true
        for h in $CW_HARNESS_ALL; do
            $first_h || printf ','
            first_h=false
            dir="$(_harness_dir "$account" "$h")"
            CW_HARNESS="$h" CW_HARNESS_DIR="$dir" _harness_load "$h" >/dev/null 2>&1
            local raw; raw=$(CW_HARNESS_DIR="$dir" harness_doctor 2>/dev/null)
            [[ -n "$raw" ]] || raw="{\"harness\":\"$h\",\"status\":\"error\",\"detail\":\"driver produced no output\"}"
            CW_RAW="$raw" CW_H="$h" CW_DIR="$dir" \
            CW_ENV="$(CW_HARNESS_DIR="$dir" harness_config_env | cut -d= -f1)" \
            CW_PROV="$(_account_meta_get "$account" "$h" provider)" \
            CW_MOD="$(_account_meta_get "$account" "$h" model)" \
            CW_KEY="$([[ -f "$dir/env" ]] && echo true || echo false)" \
            python3 - <<'PY'
import json, os
d = json.loads(os.environ["CW_RAW"])
d.update({
    "harness": os.environ["CW_H"],
    "config_env": os.environ["CW_ENV"] or None,
    "config_dir": os.environ["CW_DIR"],
    "provider": os.environ["CW_PROV"] or "native",
    "provider_kind": "native",
    "model": os.environ["CW_MOD"] or None,
    "unofficial": False,
    "has_api_key": os.environ["CW_KEY"] == "true",
})
d.setdefault("detail", None)
print(json.dumps(d), end="")
PY
        done
        printf ']}'
    done
    printf ']'
}

_json_str() {
    python3 -c "import json,sys; print(json.dumps(sys.argv[1]), end='')" "$1"
}
```

- [ ] **Step 4: Add `--json` to `cmd_doctor`**

At the top of `cmd_doctor`, parse the flag and branch before any coloured output:

```bash
    local json_out=false
    while [[ $# -gt 0 ]]; do
        case "$1" in --json) json_out=true; shift ;; *) shift ;; esac
    done

    if $json_out; then
        printf '{"schema":1,"cw_version":"%s","cw_home":%s,"generated":"%s",' \
            "$CW_VERSION" "$(_json_str "$CW_HOME")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '"harnesses":%s,' "$(_harness_inventory_json)"
        printf '"accounts":%s,' "$(_doctor_matrix_json)"
        printf '"issues":[],"warnings":[]}\n'
        return 0
    fi
```

```bash
# prints which harnesses are installed on this machine
_harness_inventory_json() {
    local first=true h path ver src
    printf '['
    for h in $CW_HARNESS_ALL; do
        $first || printf ','
        first=false
        src="builtin"; [[ -f "$CW_HOME/harnesses/$h.sh" ]] && src="user"
        if path=$(command -v "$h" 2>/dev/null); then
            ver=$("$h" --version 2>/dev/null | head -1 | tr -d '\n')
            printf '{"name":"%s","installed":true,"path":%s,"version":%s,"source":"%s"}' \
                "$h" "$(_json_str "$path")" "$(_json_str "$ver")" "$src"
        else
            printf '{"name":"%s","installed":false,"path":null,"version":null,"source":"%s"}' \
                "$h" "$src"
        fi
    done
    printf ']'
}
```

- [ ] **Step 5: Add `cmd_harness`**

```bash
cmd_harness() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list|ls)
            echo -e "\n${BOLD}Harnesses${NC}\n"
            local h mark
            for h in $CW_HARNESS_ALL; do
                if command -v "$h" &>/dev/null; then mark="${G}✓${NC}"; else mark="${DIM}—${NC}"; fi
                echo -e "  $mark ${C}$h${NC}"
            done
            echo ""
            ;;
        doctor) cmd_doctor "$@" ;;
        *) _err "Usage: cw harness <list|doctor>" ;;
    esac
}
```

Add `harness) cmd_harness "$@" ;;` to the dispatch in `main`, and the command to `cmd_help`.

- [ ] **Step 6: Add `claude_doctor`**

Append to `lib/harnesses/claude.sh`:

```bash
claude_doctor() {
    local status detail="null"
    if ! command -v claude >/dev/null 2>&1; then
        status="not_installed"; detail='"claude not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/.claude.json" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"claude","status":"%s","detail":%s}\n' "$status" "$detail"
}
```

- [ ] **Step 7: Point the three auth checks at the driver**

Replace the `[[ -f "$dir/.claude.json" ]]` tests in `cmd_account list` (`cw:268`), `cmd_doctor`
(`cw:2288`) and `cmd_dashboard` (`cw:2766`) with a call that reads `status` from the driver's
JSON, so a codex-only account is not reported as unauthenticated.

- [ ] **Step 8: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add cw lib/harnesses/claude.sh tests/doctor_json.bats
git commit -m "feat: add cw doctor --json and cw harness"
```

---

## Task 8: `cw account login`

**Files:**
- Modify: `cw` — `cmd_account` gains `login`
- Create: `tests/account_login.bats`

**Interfaces:**
- Consumes: `_harness_dir` (Task 4), `harness_login` (Task 6), `cw doctor --json` (Task 7)
- Produces: `_login_scrape` reads the child's output line by line, echoes it through, and emits `CW_LOGIN_URL=` / `CW_LOGIN_CODE=` on first match

- [ ] **Step 1: Write the failing test**

Create `tests/account_login.bats`:

```bash
load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$BATS_TEST_TMPDIR/fakes"
    cat > "$BATS_TEST_TMPDIR/fakes/codex" <<'FAKE'
#!/usr/bin/env bash
echo "Open this URL to continue:"
echo "https://auth.example.com/device?code=WXYZ-7788"
echo "Your code is WXYZ-7788"
mkdir -p "$CODEX_HOME"; echo '{}' > "$CODEX_HOME/auth.json"
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/codex"
    export PATH="$BATS_TEST_TMPDIR/fakes:$PATH"
}

@test "login emits a machine-parseable url line" {
    run "$CW_BIN" account login acct --harness codex --no-browser
    [ "$status" -eq 0 ]
    [[ "$output" == *"CW_LOGIN_URL=https://auth.example.com/device?code=WXYZ-7788"* ]]
}

@test "login passes the harness output through unchanged" {
    run "$CW_BIN" account login acct --harness codex --no-browser
    [[ "$output" == *"Open this URL to continue:"* ]]
}

@test "login creates the per-harness credential dir" {
    run "$CW_BIN" account login acct --harness codex --no-browser
    [ -d "$CW_HOME/accounts/acct/codex" ]
}

@test "doctor reports codex connected after login" {
    "$CW_BIN" account login acct --harness codex --no-browser
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = [x for x in d[\"accounts\"][0][\"harnesses\"] if x[\"harness\"] == \"codex\"][0]
assert h[\"status\"] == \"connected\", h
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "an api key on stdin is written 600 and never echoed" {
    run bash -c "echo 'sk-secret-value' | '$CW_BIN' account login acct --harness codex --with-api-key -"
    [[ "$output" != *"sk-secret-value"* ]]
    run mode_of "$CW_HOME/accounts/acct/codex/env"
    [ "$output" = "600" ]
    run grep -q 'sk-secret-value' "$CW_HOME/accounts/acct/codex/env"
    [ "$status" -eq 0 ]
}

@test "the api key never reaches config.yaml or meta.json" {
    echo 'sk-secret-value' | "$CW_BIN" account login acct --harness codex --with-api-key -
    run grep -r 'sk-secret-value' "$CW_HOME/config.yaml" "$CW_HOME/accounts/acct/meta.json"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/account_login.bats`
Expected: FAIL — `Subcommands: add | list | remove`.

- [ ] **Step 3: Implement the scraper**

```bash
# echoes the child's output through and emits the first url and code it sees
_login_scrape() {
    local url_seen=false code_seen=false line
    while IFS= read -r line; do
        printf '%s\n' "$line"
        if ! $url_seen && [[ "$line" =~ (https?://[^[:space:]\"\'\)]+) ]]; then
            printf 'CW_LOGIN_URL=%s\n' "${BASH_REMATCH[1]}"
            url_seen=true
        fi
        if ! $code_seen && [[ "$line" =~ ([A-Z0-9]{4}-[A-Z0-9]{4}) ]]; then
            printf 'CW_LOGIN_CODE=%s\n' "${BASH_REMATCH[1]}"
            code_seen=true
        fi
    done
}
```

- [ ] **Step 4: Implement the subcommand**

```bash
_account_login() {
    local account="${1:?Usage: cw account login <account> --harness <h>}"; shift
    local harness="" no_browser="" api_key_stdin=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --harness|-H)   harness="$2"; shift 2 ;;
            --no-browser)   no_browser=1; shift ;;
            --with-api-key) api_key_stdin=1; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -d "$(_account_root "$account")" ]] || { _err "Account '$account' not found."; return 1; }
    harness="${harness:-$(_account_default_harness "$account")}"

    local dir; dir="$(_harness_dir "$account" "$harness")"
    mkdir -p "$dir"

    CW_HARNESS="$harness" CW_HARNESS_DIR="$dir"
    _harness_load "$harness" || return 1

    if [[ -n "$api_key_stdin" ]]; then
        local key; IFS= read -r key
        [[ -n "$key" ]] || { _err "No API key on stdin."; return 1; }
        local envf="$dir/env"
        ( umask 077; printf '%s\n' "$(_harness_api_key_var "$harness")=$key" > "$envf" )
        chmod 600 "$envf"
        _log "API key stored for ${C}$account${NC}/${Y}$harness${NC}"
        CW_LOGIN_API_KEY_STDIN=1
        printf '%s\n' "$key" | { harness_login && _harness_exec >/dev/null 2>&1; } || true
        return 0
    fi

    CW_LOGIN_NO_BROWSER="$no_browser"
    harness_login || { _err "Harness '$harness' has no login flow cw can drive."; return 1; }
    _harness_exec 2>&1 | _login_scrape
    return "${PIPESTATUS[0]}"
}

# names the env var each harness reads its key from
_harness_api_key_var() {
    case "$1" in
        codex)    printf 'CODEX_API_KEY' ;;
        claude)   printf 'ANTHROPIC_AUTH_TOKEN' ;;
        pi)       printf 'PI_API_KEY' ;;
        opencode) printf 'OPENCODE_API_KEY' ;;
        *)        printf 'API_KEY' ;;
    esac
}
```

The exact key variable for pi and opencode is **verify during implementation**; the fallback is
harmless because the value also lands in the harness's own `auth.json` via its login path.

Add `login) _account_login "$@" ;;` to the `cmd_account` case and to `cmd_help`.

- [ ] **Step 5: Replace the printed login instructions**

`cw:234` and `cw:281` print `CLAUDE_CONFIG_DIR=… claude /login`. Replace both with:

```bash
    echo -e "     ${BOLD}cw account login $name --harness claude${NC}"
```

- [ ] **Step 6: Add `claude_login`**

Append to `lib/harnesses/claude.sh`:

```bash
claude_login() {
    HARNESS_ENV=("CLAUDE_CONFIG_DIR=$CW_HARNESS_DIR")
    HARNESS_ARGV=(claude /login)
    return 0
}
```

- [ ] **Step 7: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add cw lib/harnesses/claude.sh tests/account_login.bats
git commit -m "feat: add cw account login with headless url and code output"
```

---

## Task 9: Provider and model as first-class account fields

**Files:**
- Modify: `cw` — `cmd_account add` gains `--harness`, `--provider`, `--model`; model resolution order
- Modify: `lib/harnesses/codex.sh` — provider translation
- Create: `tests/provider_model.bats`

**Interfaces:**
- Consumes: `_account_meta_get` / `_account_meta_set` (Task 4)
- Produces: `_resolve_model <account> <harness> <task_type> <override> <session_meta>` prints the model; `_provider_kind <provider>` prints `native` / `api` / `local`

- [ ] **Step 1: Write the failing test**

Create `tests/provider_model.bats`:

```bash
load helpers/setup

setup() { setup_cw_home; }

@test "account add stores harness, provider and model" {
    run "$CW_BIN" account add glm --harness opencode --provider zai --model glm-5.1
    [ "$status" -eq 0 ]
    run bash -c "source '$CW_BIN'; _account_meta_get glm opencode model"
    [ "$output" = "glm-5.1" ]
    run bash -c "source '$CW_BIN'; _account_default_harness glm"
    [ "$output" = "opencode" ]
}

@test "config.yaml models apply to claude" {
    make_project app >/dev/null
    run bash -c "source '$CW_BIN'; _resolve_model acct claude work '' ''"
    [ "$output" = "sonnet" ]
}

@test "config.yaml models do not apply to another harness" {
    run bash -c "source '$CW_BIN'; _resolve_model acct codex work '' ''"
    [ -z "$output" ]
}

@test "the account model beats the config default" {
    bash -c "source '$CW_BIN'; _account_meta_set acct claude model opus"
    run bash -c "source '$CW_BIN'; _resolve_model acct claude work '' ''"
    [ "$output" = "opus" ]
}

@test "an explicit override beats everything" {
    bash -c "source '$CW_BIN'; _account_meta_set acct claude model opus"
    run bash -c "source '$CW_BIN'; _resolve_model acct claude work haiku ''"
    [ "$output" = "haiku" ]
}

@test "ollama is a local provider" {
    run bash -c "source '$CW_BIN'; _provider_kind ollama"
    [ "$output" = "local" ]
}

@test "a local account needs no login and doctor reports it local" {
    "$CW_BIN" account add local --harness opencode --provider ollama --model qwen3-coder:14b
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
a = [x for x in d[\"accounts\"] if x[\"name\"] == \"local\"][0]
h = [x for x in a[\"harnesses\"] if x[\"harness\"] == \"opencode\"][0]
assert h[\"provider_kind\"] == \"local\", h
assert h[\"model\"] == \"qwen3-coder:14b\", h
print(\"ok\")'"
    [ "$output" = "ok" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/provider_model.bats`
Expected: FAIL — `account add` ignores the new flags.

- [ ] **Step 3: Implement the resolvers**

```bash
_provider_kind() {
    case "$1" in
        ""|native)                              printf 'native' ;;
        ollama|lmstudio|llamacpp)               printf 'local' ;;
        *)                                      printf 'api' ;;
    esac
}

# first match wins: override, session, account, config models, harness default
_resolve_model() {
    local account="$1" harness="$2" task_type="$3" override="$4" session_meta="$5"
    if [[ -n "$override" ]]; then printf '%s' "$override"; return 0; fi
    if [[ -n "$session_meta" && -f "$session_meta" ]]; then
        local stored
        stored=$(python3 -c "
import json
try: print(json.load(open('$session_meta')).get('model') or '')
except Exception: print('')
" 2>/dev/null)
        [[ -n "$stored" ]] && { printf '%s' "$stored"; return 0; }
    fi
    local acct_model; acct_model=$(_account_meta_get "$account" "$harness" model)
    [[ -n "$acct_model" ]] && { printf '%s' "$acct_model"; return 0; }
    if [[ "$harness" == "claude" ]]; then
        _model_for_type "$task_type"
        return 0
    fi
    printf '%s' ""
}
```

- [ ] **Step 4: Extend `cw account add`**

```bash
        add)
            local name="${1:?Usage: cw account add <name>}"; shift || true
            local harness="" provider="" model=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --harness|-H) harness="$2"; shift 2 ;;
                    --provider|-p) provider="$2"; shift 2 ;;
                    --model|-m)   model="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            local dir; dir="$(_account_root "$name")"
            [[ -d "$dir" ]] && { _warn "Account '$name' already exists."; return 1; }
            harness="${harness:-$CW_HARNESS_DEFAULT}"
            mkdir -p "$dir" "$(_harness_dir "$name" "$harness")"
            CW_A_NAME="$name" CW_A_H="$harness" CW_A_META="$dir/meta.json" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
meta = {
    "name": os.environ["CW_A_NAME"],
    "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "harness": os.environ["CW_A_H"],
    "harnesses": {},
}
with open(os.environ["CW_A_META"], "w") as f: json.dump(meta, f, indent=2)
PY
            [[ -n "$provider" ]] && _account_meta_set "$name" "$harness" provider "$provider"
            [[ -n "$model" ]]    && _account_meta_set "$name" "$harness" model "$model"
```

Keep the existing arcade-hook install and default-account logic that follows.

Note the new accounts branch creates `$(_harness_dir "$name" "$harness")` — for claude that is
`accounts/<name>/claude/`, so accounts created from here on use the split layout while existing
ones stay flat, exactly as the spec describes.

- [ ] **Step 5: Report local providers in doctor**

Extend the python block in `_doctor_matrix_json` (Task 7, Step 3):

```python
prov = os.environ["CW_PROV"] or "native"
kind = os.environ["CW_KIND"]
d["provider"] = prov
d["provider_kind"] = kind
if kind == "local":
    d["status"] = "local"
    d["detail"] = {
        "endpoint": os.environ.get("CW_ENDPOINT") or "http://localhost:11434",
        "reachable": os.environ.get("CW_REACHABLE") == "true",
        "model_pulled": os.environ.get("CW_PULLED") == "true",
    }
```

with the shell side adding:

```bash
            CW_KIND="$(_provider_kind "$(_account_meta_get "$account" "$h" provider)")" \
            CW_ENDPOINT="${OLLAMA_HOST:-http://localhost:11434}" \
            CW_REACHABLE="$(_ollama_reachable && echo true || echo false)" \
            CW_PULLED="$(_ollama_has_model "$(_account_meta_get "$account" "$h" model)" && echo true || echo false)" \
```

```bash
_ollama_reachable() {
    python3 -c "
import urllib.request, sys
try:
    urllib.request.urlopen('${OLLAMA_HOST:-http://localhost:11434}/api/tags', timeout=1)
except Exception: sys.exit(1)
" 2>/dev/null
}

_ollama_has_model() {
    [[ -n "$1" ]] || return 1
    python3 - "$1" <<'PY' 2>/dev/null
import json, os, sys, urllib.request
host = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
try:
    with urllib.request.urlopen(host + "/api/tags", timeout=1) as r:
        tags = json.load(r)
except Exception:
    sys.exit(1)
names = {m.get("name", "") for m in tags.get("models", [])}
sys.exit(0 if sys.argv[1] in names else 1)
PY
}
```

- [ ] **Step 6: Translate the provider in the codex driver**

Append to `lib/harnesses/codex.sh`:

```bash
# writes an openai-compatible provider into the account's codex config
_codex_write_provider() {
    local provider="$1" model="$2"
    [[ -n "$provider" && "$provider" != "native" ]] || return 0
    mkdir -p "$CW_HARNESS_DIR"
    printf 'model = "%s"\nmodel_provider = "%s"\n' "$model" "$provider" \
        > "$CW_HARNESS_DIR/config.toml"
}
```

Call it from `codex_launch` before building argv. The exact `model_providers` table keys are
**verify during implementation**; the test asserts only that the file is written with the
provider and model the account carries.

- [ ] **Step 7: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add cw lib/harnesses/codex.sh tests/provider_model.bats
git commit -m "feat: make provider and model first-class account fields"
```

---

## Task 10: `cw spaces` harness column and `--json`

**Files:**
- Modify: `cw` — `cmd_spaces`, `_spaces_list`, `cmd_status`
- Modify: `lib/dashboard/server.py:41-50`
- Create: `tests/spaces_json.bats`

**Interfaces:**
- Consumes: `session.json` `harness` / `provider` / `model` (Task 5), `_account_meta_get` (Task 4)
- Produces: `cw spaces --json` with the shape in §9 of the spec

- [ ] **Step 1: Write the failing test**

Create `tests/spaces_json.bats`:

```bash
load helpers/setup

setup() { setup_cw_home; }

@test "spaces --json lists the harness per session" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    run bash -c "'$CW_BIN' spaces --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
s = d[\"spaces\"][0]
assert s[\"harness\"] == \"claude\", s
assert s[\"id\"] == \"fix-auth\", s
assert s[\"resume\"] == \"cw work app fix-auth\", s
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "spaces --json treats a session with no harness field as claude" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    python3 - "$CW_HOME/sessions/app/task-fix-auth/session.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m.pop("harness", None)
json.dump(m, open(p, "w"))
PY
    run bash -c "'$CW_BIN' spaces --json | python3 -c '
import json, sys
print(json.load(sys.stdin)[\"spaces\"][0][\"harness\"])'"
    [ "$output" = "claude" ]
}

@test "the human spaces output shows a harness column" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    run "$CW_BIN" spaces
    [[ "$output" == *claude* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/spaces_json.bats`
Expected: FAIL — `spaces --json` prints the human table.

- [ ] **Step 3: Implement `--json`**

Add a flag parse at the top of `cmd_spaces` and a python walker that mirrors the existing one but
emits JSON, reading `m.get("harness") or "claude"`, `m.get("provider") or "native"` and
`m.get("model")`, and building `resume` / `close` strings from the session type.

- [ ] **Step 4: Add the human column**

In the existing `cmd_spaces` python block, append the harness to the label line, showing provider
and model only when the provider is not `native`:

```python
        label_extra = harness
        if provider and provider != "native":
            label_extra = f"{harness} · {model or provider}"
```

- [ ] **Step 5: Update the dashboard**

Modify `lib/dashboard/server.py`. Replace the `.claude.json` auth test with a per-harness scan
that mirrors `_harness_dir`, and add `harness` to the session payload:

```python
def harness_dir(account_path, harness):
    """claude keeps the flat dir unless a claude subdir exists"""
    sub = os.path.join(account_path, "claude")
    if harness == "claude" and not os.path.isdir(sub):
        return account_path
    return os.path.join(account_path, harness)
```

- [ ] **Step 6: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add cw lib/dashboard/server.py tests/spaces_json.bats
git commit -m "feat: expose harness, provider and model in spaces and the dashboard"
```

---

## Task 11: Portable context fetch

**Files:**
- Create: `lib/context/github.sh`, `lib/context/linear.sh`, `lib/context/notion.sh`
- Modify: `cw` — `cmd_work` writes fetched content into `TASK_NOTES.md` before launch
- Create: `tests/context_fetch.bats`, `tests/fixtures/github-issue.json`, `tests/fixtures/linear-issue.json`, `tests/fixtures/notion-page.json`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `context_credential_<source>` returns 0 when a credential exists; `context_fetch_<source> <url>` prints markdown; `_context_write_notes <notes_file> <markdown>` replaces the `## Context` section

- [ ] **Step 1: Write the fixtures**

Create `tests/fixtures/github-issue.json`:

```json
{"title":"Login button does nothing","body":"Clicking Sign in on /login is a no-op in Safari 17.","number":1,"state":"open","labels":[{"name":"bug"}]}
```

Create `tests/fixtures/linear-issue.json`:

```json
{"data":{"issue":{"identifier":"SEI-214","title":"Reservation double-booking","description":"Two guests can book the same slot.","branchName":"jose/sei-214-double-booking","priority":1,"comments":{"nodes":[{"body":"Repro needs two browsers."}]}}}}
```

Create `tests/fixtures/notion-page.json`:

```json
{"results":[{"type":"heading_1","heading_1":{"rich_text":[{"plain_text":"Spec"}]}},{"type":"paragraph","paragraph":{"rich_text":[{"plain_text":"Sessions expire after 30 days."}]}}]}
```

- [ ] **Step 2: Write the failing test**

Create `tests/context_fetch.bats`:

```bash
load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$BATS_TEST_TMPDIR/fakes"
    cat > "$BATS_TEST_TMPDIR/fakes/gh" <<FAKE
#!/usr/bin/env bash
cat "$BATS_TEST_DIRNAME/fixtures/github-issue.json"
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/gh"
    export PATH="$BATS_TEST_TMPDIR/fakes:$PATH"
}

@test "github fetch needs no credential" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'; context_credential_github"
    [ "$status" -eq 0 ]
}

@test "github fetch renders the issue body as markdown" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/1"
    [[ "$output" == *"Login button does nothing"* ]]
    [[ "$output" == *"no-op in Safari 17"* ]]
}

@test "linear reports no credential when the env var is unset" {
    run bash -c "unset LINEAR_API_KEY
                 source '$BATS_TEST_DIRNAME/../lib/context/linear.sh'
                 context_credential_linear"
    [ "$status" -ne 0 ]
}

@test "work writes the fetched issue into TASK_NOTES.md before launching" {
    make_project app >/dev/null
    run "$CW_BIN" work app https://github.com/org/repo/issues/1
    run grep -q "no-op in Safari 17" "$CW_HOME/sessions/app/task-issues-1/TASK_NOTES.md"
    [ "$status" -eq 0 ]
}

@test "work still launches when no credential is available" {
    make_project app >/dev/null
    run bash -c "unset LINEAR_API_KEY; '$CW_BIN' work app https://linear.app/x/issue/SEI-214"
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 1 ]
}

@test "tokens are not exported into the harness process" {
    make_project app >/dev/null
    LINEAR_API_KEY=lin_secret run "$CW_BIN" work app fix-auth
    run grep -c 'lin_secret' "$CW_FAKE_LOG"
    [ "$output" = "0" ]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `./tests/run.sh tests/context_fetch.bats`
Expected: FAIL — `lib/context/github.sh` does not exist.

- [ ] **Step 4: Write the GitHub fetcher**

Create `lib/context/github.sh`:

```bash
# github needs no cw credential; gh carries its own
context_credential_github() {
    command -v gh >/dev/null 2>&1
}

context_fetch_github() {
    local url="$1"
    local num; num=$(printf '%s' "$url" | grep -oE '[0-9]+$')
    [[ -n "$num" ]] || return 1
    local kind=issue
    [[ "$url" == */pull/* ]] && kind=pr
    gh "$kind" view "$num" --json title,body,number,state,labels 2>/dev/null | python3 - <<'PY'
import json, sys
d = json.load(sys.stdin)
labels = ", ".join(l["name"] for l in d.get("labels", []))
print(f"**#{d.get('number')} — {d.get('title','')}**")
print(f"State: {d.get('state','')}" + (f" · Labels: {labels}" if labels else ""))
print()
print(d.get("body") or "_No description._")
PY
}
```

- [ ] **Step 5: Write the Linear fetcher**

Create `lib/context/linear.sh`:

```bash
# linear needs a personal api key from the env or ~/.cw/tokens.env
context_credential_linear() {
    [[ -n "${LINEAR_API_KEY:-}" ]] && return 0
    [[ -f "$CW_HOME/tokens.env" ]] && grep -q '^LINEAR_API_KEY=' "$CW_HOME/tokens.env"
}

context_fetch_linear() {
    local url="$1"
    local id; id=$(printf '%s' "$url" | grep -oE '[A-Z]+-[0-9]+' | head -1)
    [[ -n "$id" ]] || return 1
    local key="${LINEAR_API_KEY:-}"
    [[ -z "$key" && -f "$CW_HOME/tokens.env" ]] && \
        key=$(sed -n 's/^LINEAR_API_KEY=//p' "$CW_HOME/tokens.env" | head -1)
    [[ -n "$key" ]] || return 1
    CW_LINEAR_KEY="$key" CW_LINEAR_ID="$id" python3 - <<'PY'
import json, os, sys, urllib.request
q = """query($id:String!){issue(id:$id){identifier title description branchName priority
      comments{nodes{body}}}}"""
req = urllib.request.Request(
    "https://api.linear.app/graphql",
    data=json.dumps({"query": q, "variables": {"id": os.environ["CW_LINEAR_ID"]}}).encode(),
    headers={"Authorization": os.environ["CW_LINEAR_KEY"], "Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        d = json.load(r)
except Exception as e:
    print(f"_Linear fetch failed: {e}_", file=sys.stderr)
    sys.exit(1)
i = (d.get("data") or {}).get("issue")
if not i:
    sys.exit(1)
print(f"**{i['identifier']} — {i['title']}**")
if i.get("branchName"):
    print(f"Branch: `{i['branchName']}`")
print()
print(i.get("description") or "_No description._")
nodes = (i.get("comments") or {}).get("nodes") or []
if nodes:
    print("\n**Comments**")
    for c in nodes:
        print(f"- {c['body']}")
PY
}
```

- [ ] **Step 6: Write the Notion fetcher**

Create `lib/context/notion.sh`:

```bash
# notion needs an internal integration token
context_credential_notion() {
    [[ -n "${NOTION_TOKEN:-}" ]] && return 0
    [[ -f "$CW_HOME/tokens.env" ]] && grep -q '^NOTION_TOKEN=' "$CW_HOME/tokens.env"
}

context_fetch_notion() {
    local url="$1"
    local page; page=$(printf '%s' "$url" | grep -oE '[a-f0-9]{32}' | head -1)
    [[ -n "$page" ]] || return 1
    local tok="${NOTION_TOKEN:-}"
    [[ -z "$tok" && -f "$CW_HOME/tokens.env" ]] && \
        tok=$(sed -n 's/^NOTION_TOKEN=//p' "$CW_HOME/tokens.env" | head -1)
    [[ -n "$tok" ]] || return 1
    CW_NOTION_TOKEN="$tok" CW_NOTION_PAGE="$page" python3 - <<'PY'
import json, os, sys, urllib.request
req = urllib.request.Request(
    f"https://api.notion.com/v1/blocks/{os.environ['CW_NOTION_PAGE']}/children?page_size=100",
    headers={"Authorization": f"Bearer {os.environ['CW_NOTION_TOKEN']}",
             "Notion-Version": "2022-06-28"},
)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        d = json.load(r)
except Exception as e:
    print(f"_Notion fetch failed: {e}_", file=sys.stderr)
    sys.exit(1)
prefix = {"heading_1": "# ", "heading_2": "## ", "heading_3": "### ",
          "bulleted_list_item": "- ", "numbered_list_item": "1. "}
for b in d.get("results", []):
    t = b.get("type")
    rich = (b.get(t) or {}).get("rich_text") or []
    text = "".join(x.get("plain_text", "") for x in rich)
    if text:
        print(prefix.get(t, "") + text)
PY
}
```

- [ ] **Step 7: Wire it into `cmd_work`**

After the URL is parsed and before the init prompt is built:

```bash
    if [[ -n "$task_source" && "$task_source" != "url" ]]; then
        local ctx_lib="$SCRIPT_DIR/../lib/context/$task_source.sh"
        [[ -f "$ctx_lib" ]] || ctx_lib="$CW_HOME/lib/context/$task_source.sh"
        if [[ -f "$ctx_lib" ]]; then
            # shellcheck disable=SC1090
            source "$ctx_lib"
            if "context_credential_$task_source"; then
                local fetched
                fetched=$("context_fetch_$task_source" "$task_url" 2>/dev/null) || fetched=""
                [[ -n "$fetched" ]] && _context_write_notes "$notes_file" "$fetched"
            else
                _dim "  No $task_source credential — the agent will fetch it instead"
            fi
        fi
    fi
```

```bash
# replaces the Context section of a notes file with fetched markdown
_context_write_notes() {
    local notes="$1" body="$2"
    [[ -f "$notes" ]] || return 0
    CW_NOTES="$notes" CW_BODY="$body" python3 - <<'PY'
import os, re
p = os.environ["CW_NOTES"]
with open(p) as f: text = f.read()
block = "## Context\n" + os.environ["CW_BODY"] + "\n"
if "## Context" in text:
    text = re.sub(r"## Context\n.*?(?=\n## |\Z)", block, text, count=1, flags=re.S)
else:
    text += "\n" + block
with open(p, "w") as f: f.write(text)
PY
}
```

Then drop the "Fill in the TASK_NOTES.md Context section" instruction from the init prompt when
the fetch succeeded, keeping it when it did not.

- [ ] **Step 8: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/context cw tests/context_fetch.bats tests/fixtures
git commit -m "feat: fetch Linear, GitHub and Notion context into TASK_NOTES.md"
```

---

## Task 12: Pi driver

**Verify before writing code** — none of this is confirmed and none of it may be guessed:
pi's launch argv, whether it accepts a prompt on argv, its resume mechanism, whether it has a
non-interactive mode, its `--no-browser` equivalent, and its API-key import path. Confirmed
already: `PI_CODING_AGENT_DIR` (default `~/.pi/agent`), sessions stored as JSONL under
`sessions/`, `/login` as an in-session command, and `auth.json` as the credential file.

**Files:**
- Create: `lib/harnesses/pi.sh`
- Create: `tests/fakes/pi`
- Create: `tests/driver_pi.bats`

**Interfaces:**
- Consumes: `_harness_load`, `_harness_exec` (Task 2), `_harness_dir` (Task 4)
- Produces: `pi_supports`, `pi_config_env`, `pi_launch`, `pi_resume`, `pi_session_ref`, `pi_doctor`, `pi_login`

- [ ] **Step 1: Record what the binary actually does**

With pi installed, capture the real behaviour before writing the driver:

```bash
pi --help
PI_CODING_AGENT_DIR=/tmp/pi-scratch pi --version
ls /tmp/pi-scratch
```

Write the findings into §14 of the spec, replacing the **verify** markers with what you observed.

- [ ] **Step 2: Write the fake**

```bash
cp tests/fakes/claude tests/fakes/pi
chmod +x tests/fakes/pi
```

- [ ] **Step 3: Write the failing test**

Create `tests/driver_pi.bats`:

```bash
load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$CW_HOME/accounts/acct/pi"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "pi"
json.dump(m, open(p, "w"))
PY
}

@test "pi launches with PI_CODING_AGENT_DIR pointing at the per-harness dir" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 bin)" = "pi" ]
    [ "$(call_field 1 'env:PI_CODING_AGENT_DIR')" = "$CW_HOME/accounts/acct/pi" ]
}

@test "pi never receives claude session-name flags" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    run bash -c "call_argv 1 | grep -c -- '--name'"
    [ "$output" = "0" ]
}

@test "pi degrades hooks, teams and plugins without failing" {
    make_project app >/dev/null
    run "$CW_BIN" work app big --team
    [ "$status" -eq 0 ]
    [ -z "$(call_field 1 'env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')" ]
}

@test "pi doctor reports not_logged_in with no auth.json" {
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = [x for x in d[\"accounts\"][0][\"harnesses\"] if x[\"harness\"] == \"pi\"][0]
assert h[\"status\"] in (\"not_logged_in\", \"not_installed\"), h
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "pi doctor reports connected once auth.json exists" {
    touch "$CW_HOME/accounts/acct/pi/auth.json"
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = [x for x in d[\"accounts\"][0][\"harnesses\"] if x[\"harness\"] == \"pi\"][0]
assert h[\"status\"] in (\"connected\", \"not_installed\"), h
print(\"ok\")'"
    [ "$output" = "ok" ]
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `./tests/run.sh tests/driver_pi.bats`
Expected: FAIL — `Unknown harness 'pi'`.

- [ ] **Step 5: Write the driver**

Create `lib/harnesses/pi.sh`. Start from what Step 1 observed; this is the skeleton with the
confirmed parts filled in and the rest resolved from the recording:

```bash
# pi coding agent driver
pi_supports() {
    case "$1" in
        model_flag|custom_provider|instructions_file) return 0 ;;
        *) return 1 ;;
    esac
}

pi_config_env() {
    printf 'PI_CODING_AGENT_DIR=%s\n' "$CW_HARNESS_DIR"
}

pi_session_ref() {
    printf '%s' ""
}

_pi_base() {
    HARNESS_ENV=("PI_CODING_AGENT_DIR=$CW_HARNESS_DIR")
    [[ -f "$CW_HARNESS_DIR/env" ]] && HARNESS_ENV+=("$(_harness_env_file "$CW_HARNESS_DIR/env")")
    HARNESS_ARGV=(pi)
    local f
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    return 0
}

pi_launch() {
    _pi_base
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

pi_resume() {
    local attempt="$1"
    [[ "$attempt" == "1" ]] || return 1
    _pi_base
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

pi_doctor() {
    local status detail="null"
    if ! command -v pi >/dev/null 2>&1; then
        status="not_installed"; detail='"pi not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/auth.json" || -f "$CW_HARNESS_DIR/env" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"pi","status":"%s","detail":%s}\n' "$status" "$detail"
}

pi_login() {
    HARNESS_ENV=("PI_CODING_AGENT_DIR=$CW_HARNESS_DIR")
    HARNESS_ARGV=(pi)
    return 0
}
```

Until pi is confirmed to support resume, `pi_resume` returning a single fresh-launch attempt is
the correct degradation: the resume prompt plus `TASK_NOTES.md` carry the context. Add
`resume_by_name` or `continue_last` to `pi_supports` only if Step 1 proved it.

- [ ] **Step 6: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/harnesses/pi.sh tests/fakes/pi tests/driver_pi.bats docs/specs/2026-09-09-harness-agnostic.md
git commit -m "feat: add pi driver"
```

---

## Task 13: OpenCode driver

**Verify before writing code:** whether `opencode run --continue` is scoped to the working
directory, the `--no-browser` equivalent for `opencode auth login`, the API-key import path, and
the provider config keys. Confirmed already: `OPENCODE_DATA_DIR` holds `auth.json` and sessions,
`OPENCODE_CONFIG` names a config file, `opencode auth login`, `opencode run "prompt"` for
non-interactive use, `--continue` / `-c` and `--session` / `-s`, `--model provider/model`.

OpenCode may not be installed on the maintainer's machine. The driver must be complete and
fully tested against the fake regardless; the manual end-to-end check is optional here.

**Files:**
- Create: `lib/harnesses/opencode.sh`
- Create: `tests/fakes/opencode`
- Create: `tests/driver_opencode.bats`

**Interfaces:**
- Consumes: `_harness_load`, `_harness_exec` (Task 2), `_harness_dir` (Task 4), `_provider_kind` (Task 9)
- Produces: `opencode_supports`, `opencode_config_env`, `opencode_launch`, `opencode_resume`, `opencode_session_ref`, `opencode_doctor`, `opencode_login`

- [ ] **Step 1: Write the fake**

```bash
cp tests/fakes/claude tests/fakes/opencode
chmod +x tests/fakes/opencode
```

- [ ] **Step 2: Write the failing test**

Create `tests/driver_opencode.bats`:

```bash
load helpers/setup

setup() {
    setup_cw_home
    "$CW_BIN" account add glm --harness opencode --provider zai --model glm-5.1
    make_project app >/dev/null
    set_project_account app glm
}

@test "opencode launches with OPENCODE_DATA_DIR and OPENCODE_CONFIG set" {
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 bin)" = "opencode" ]
    [ "$(call_field 1 'env:OPENCODE_DATA_DIR')" = "$CW_HOME/accounts/glm/opencode" ]
}

@test "opencode receives the account model" {
    run "$CW_BIN" work app fix-auth
    run bash -c "'$CW_BIN' spaces --json >/dev/null; grep -c 'glm-5.1' '$CW_FAKE_LOG'"
    [ "$output" != "0" ]
}

@test "opencode resume uses run --continue" {
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    "$CW_BIN" work app fix-auth
    run bash -c "grep -c -- '^arg=--continue$' '$CW_FAKE_LOG'"
    [ "$output" = "1" ]
}

@test "opencode carries the account provider through to doctor" {
    touch "$CW_HOME/accounts/glm/opencode/auth.json"
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
a = [x for x in d[\"accounts\"] if x[\"name\"] == \"glm\"][0]
h = [x for x in a[\"harnesses\"] if x[\"harness\"] == \"opencode\"][0]
assert h[\"provider\"] == \"zai\", h
assert h[\"model\"] == \"glm-5.1\", h
print(\"ok\")'"
    [ "$output" = "ok" ]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `./tests/run.sh tests/driver_opencode.bats`
Expected: FAIL — `Unknown harness 'opencode'`.

- [ ] **Step 4: Write the driver**

Create `lib/harnesses/opencode.sh`:

```bash
# opencode driver
opencode_supports() {
    case "$1" in
        continue_last|non_interactive_prompt|model_flag|custom_provider) return 0 ;;
        *) return 1 ;;
    esac
}

opencode_config_env() {
    printf 'OPENCODE_DATA_DIR=%s\n' "$CW_HARNESS_DIR"
    printf 'OPENCODE_CONFIG=%s\n' "$CW_HARNESS_DIR/opencode.json"
}

opencode_session_ref() {
    printf '%s' ""
}

_opencode_base() {
    HARNESS_ENV=("OPENCODE_DATA_DIR=$CW_HARNESS_DIR"
                 "OPENCODE_CONFIG=$CW_HARNESS_DIR/opencode.json")
    [[ -f "$CW_HARNESS_DIR/env" ]] && HARNESS_ENV+=("$(_harness_env_file "$CW_HARNESS_DIR/env")")
    HARNESS_ARGV=(opencode)
    local f
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    return 0
}

# writes the provider and model into the account's opencode config
_opencode_write_config() {
    [[ -n "$CW_PROVIDER" && "$CW_PROVIDER" != "native" ]] || return 0
    mkdir -p "$CW_HARNESS_DIR"
    CW_OC_FILE="$CW_HARNESS_DIR/opencode.json" CW_OC_MODEL="$CW_MODEL" \
    CW_OC_PROVIDER="$CW_PROVIDER" python3 - <<'PY'
import json, os
p = os.environ["CW_OC_FILE"]
try:
    with open(p) as f: cfg = json.load(f)
except Exception:
    cfg = {}
provider, model = os.environ["CW_OC_PROVIDER"], os.environ["CW_OC_MODEL"]
if model:
    cfg["model"] = f"{provider}/{model}" if "/" not in model else model
with open(p, "w") as f: json.dump(cfg, f, indent=2)
PY
}

opencode_launch() {
    _opencode_write_config
    _opencode_base
    if [[ -n "$CW_PROMPT" ]]; then
        HARNESS_ARGV=(opencode run "$CW_PROMPT")
        [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_PROVIDER/$CW_MODEL")
    elif [[ -n "$CW_MODEL" ]]; then
        HARNESS_ARGV+=(--model "$CW_PROVIDER/$CW_MODEL")
    fi
    return 0
}

# continue the last session here, then a recorded session id
opencode_resume() {
    local attempt="$1"
    _opencode_write_config
    _opencode_base
    case "$attempt" in
        1) HARNESS_ARGV=(opencode run "$CW_PROMPT" --continue) ;;
        2) [[ -n "$CW_SESSION_REF" ]] || return 1
           HARNESS_ARGV=(opencode run "$CW_PROMPT" --session "$CW_SESSION_REF") ;;
        *) return 1 ;;
    esac
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_PROVIDER/$CW_MODEL")
    return 0
}

opencode_doctor() {
    local status detail="null"
    if ! command -v opencode >/dev/null 2>&1; then
        status="not_installed"; detail='"opencode not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/auth.json" || -f "$CW_HARNESS_DIR/env" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"opencode","status":"%s","detail":%s}\n' "$status" "$detail"
}

opencode_login() {
    HARNESS_ENV=("OPENCODE_DATA_DIR=$CW_HARNESS_DIR")
    HARNESS_ARGV=(opencode auth login)
    return 0
}
```

- [ ] **Step 5: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/harnesses/opencode.sh tests/fakes/opencode tests/driver_opencode.bats
git commit -m "feat: add opencode driver"
```

---

## Task 14: `cw account migrate`

**Files:**
- Modify: `cw` — `cmd_account` gains `migrate`
- Create: `tests/account_migrate.bats`

**Interfaces:**
- Consumes: `_account_root`, `_harness_dir` (Task 4)
- Produces: `_account_migrate <account> [--dry-run|--undo]`

- [ ] **Step 1: Write the failing test**

Create `tests/account_migrate.bats`:

```bash
load helpers/setup

setup() {
    setup_cw_home
    echo '{}' > "$CW_HOME/accounts/acct/.claude.json"
    echo '{}' > "$CW_HOME/accounts/acct/settings.json"
    mkdir -p "$CW_HOME/accounts/acct/templates"
    echo 'ctx' > "$CW_HOME/accounts/acct/templates/work_init.md"
}

@test "dry run moves nothing" {
    run "$CW_BIN" account migrate acct --dry-run
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/.claude.json" ]
    [ ! -d "$CW_HOME/accounts/acct/claude" ]
}

@test "migrate moves claude files and leaves cw files at the root" {
    run "$CW_BIN" account migrate acct
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/claude/.claude.json" ]
    [ -f "$CW_HOME/accounts/acct/claude/settings.json" ]
    [ -f "$CW_HOME/accounts/acct/meta.json" ]
    [ -f "$CW_HOME/accounts/acct/templates/work_init.md" ]
}

@test "resolution follows the account after migration" {
    "$CW_BIN" account migrate acct
    run bash -c "source '$CW_BIN'; _harness_dir acct claude"
    [ "$output" = "$CW_HOME/accounts/acct/claude" ]
}

@test "work still launches with the right config dir after migration" {
    make_project app >/dev/null
    "$CW_BIN" account migrate acct
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" = "$CW_HOME/accounts/acct/claude" ]
}

@test "undo restores the flat layout" {
    "$CW_BIN" account migrate acct
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/.claude.json" ]
    [ ! -d "$CW_HOME/accounts/acct/claude" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh tests/account_migrate.bats`
Expected: FAIL — `Subcommands: add | list | remove | login`.

- [ ] **Step 3: Implement it**

```bash
CW_ACCOUNT_OWNED="meta.json CLAUDE.md templates skills codex pi opencode"

_account_migrate() {
    local account="${1:?Usage: cw account migrate <account>}"; shift || true
    local dry=false undo=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n) dry=true; shift ;;
            --undo)       undo=true; shift ;;
            *) shift ;;
        esac
    done
    local root; root="$(_account_root "$account")"
    [[ -d "$root" ]] || { _err "Account '$account' not found."; return 1; }

    if $undo; then
        [[ -d "$root/claude" ]] || { _warn "Account '$account' is already flat."; return 0; }
        local f
        for f in "$root/claude"/* "$root/claude"/.[!.]*; do
            [[ -e "$f" ]] || continue
            $dry && { _dim "  would move $(basename "$f") up"; continue; }
            mv "$f" "$root/"
        done
        $dry || rmdir "$root/claude"
        _log "Account ${C}$account${NC} restored to the flat layout."
        return 0
    fi

    [[ -d "$root/claude" ]] && { _warn "Account '$account' is already split."; return 0; }
    _warn "If you have CLAUDE_CONFIG_DIR=$root hardcoded anywhere, update it to $root/claude."
    $dry || mkdir -p "$root/claude"
    local entry base owned
    for entry in "$root"/* "$root"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="$(basename "$entry")"
        [[ "$base" == "claude" ]] && continue
        owned=false
        for keep in $CW_ACCOUNT_OWNED; do
            [[ "$base" == "$keep" ]] && { owned=true; break; }
        done
        $owned && continue
        if $dry; then
            _dim "  would move $base -> claude/$base"
        else
            mv "$entry" "$root/claude/$base"
        fi
    done
    $dry && { _log "Dry run — nothing moved."; return 0; }
    _log "Account ${C}$account${NC} migrated to the split layout."
}
```

Add `migrate) _account_migrate "$@" ;;` to `cmd_account` and to `cmd_help`.

- [ ] **Step 4: Run the tests**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add cw tests/account_migrate.bats
git commit -m "feat: add opt-in cw account migrate"
```

---

## Task 15: Docs, demo, changelog, version

**Files:**
- Modify: `README.md`, `docs/architecture.md`, `docs/getting-started.md`, `docs/commands.md`, `demo.tape`
- Create: `CHANGELOG.md`
- Modify: `cw:22` (`CW_VERSION`), `cmd_help`

- [ ] **Step 1: Bump the version**

```bash
sed -i '' 's/^CW_VERSION="0.2.0"$/CW_VERSION="0.3.0"/' cw
```

- [ ] **Step 2: Update `cmd_help`**

Add to the SETUP block:

```
  account login <name> --harness <h>   Authenticate an account for a harness
    --no-browser                       Print a URL or device code instead of opening a browser
    --with-api-key -                   Read an API key from stdin
  account migrate <name>               Move a flat account to per-harness dirs
  harness list                         Show available harnesses
  harness doctor                       Per-account harness status
```

And to INFO:

```
  doctor --json                        Machine-readable health and harness matrix
  spaces --json                        Machine-readable active spaces
```

And to GLOBAL FLAGS:

```
  --harness, -H <name>                 Run this command on a specific harness
                                       (claude | codex | pi | opencode)
```

- [ ] **Step 3: Write the README section**

Add "One flow, any harness" after the intro, covering: the same `cw work` on four harnesses,
`cw account add glm --harness opencode --provider zai --model glm-5.1`, `cw account login`, the
capability degradation rule, and the fact that `TASK_NOTES.md` is fetched by CW so the workflow
is portable.

- [ ] **Step 4: Update `docs/architecture.md`**

Add "Harness routing" as a fourth concern alongside the existing three, replace the account
layout block at lines 18-23 with the two supported layouts, and update line 183 so the account
routing section describes `_harness_dir` rather than a hardcoded `CLAUDE_CONFIG_DIR`.

- [ ] **Step 5: Update `docs/getting-started.md`**

Replace the `CLAUDE_CONFIG_DIR=… claude /login` instruction at line 41 with
`cw account login work --harness claude`.

- [ ] **Step 6: Rewrite `demo.tape`**

Show the same ticket opened twice — `cw work demo-app SEI-214` on claude, then
`cw work demo-app SEI-214 --harness codex` on a second account — with `cw spaces` at the end
showing both rows and their harness column.

- [ ] **Step 7: Write the changelog**

Create `CHANGELOG.md`:

```markdown
# Changelog

## 0.3.0

### Added
- Harness drivers: the same `cw work` / `review` / `loop` / `plan` / `create` / `open` flow runs
  on Claude Code, Codex CLI, Pi and OpenCode
- `cw account login <account> --harness <h>` with `--no-browser` and `--with-api-key -`
- `cw account migrate` to move a flat account to per-harness credential directories
- `cw harness list` and `cw harness doctor`
- `cw doctor --json` and `cw spaces --json`
- `--harness` on `work`, `review`, `loop`, `plan`, `create`, `open` and `project register`
- Per-account provider and model, including local providers such as Ollama
- CW fetches Linear, GitHub and Notion content into `TASK_NOTES.md` itself
- A bats test suite

### Changed
- Every harness invocation goes through one driver layer
- Accounts may hold one credential directory per harness

### Fixed
- `cw stack` checked for installed plugins against the ambient `~/.claude` instead of the
  account's config directory

### Compatibility
Existing `~/.cw` layouts, `projects.json` and sessions keep working with no migration step. A
missing `harness` field means `claude`.
```

- [ ] **Step 8: Run the full suite**

Run: `./tests/run.sh`
Expected: all tests PASS.

- [ ] **Step 9: Verify against the real `~/.cw`**

This is the only step in the plan that touches real data, and it is read-only:

```bash
cw doctor
cw doctor --json | python3 -m json.tool | head -40
cw spaces
```

Expected: `monoku` and `meridian` both report `layout: "legacy"` and claude `connected`, and
every active session shows `harness: "claude"`. If either account reports `not_logged_in`, stop
— the resolution rule is wrong.

- [ ] **Step 10: Commit**

```bash
git add cw README.md docs demo.tape CHANGELOG.md
git commit -m "docs: document harness-agnostic workflows and bump to 0.3.0"
```

---

## Verification checklist

Run before opening the PR. Each line maps to an acceptance criterion from the brief.

- [ ] `./tests/run.sh` — every test passes
- [ ] `tests/no_direct_launch.bats` passes — zero harness executions outside `lib/harnesses/`
- [ ] `cw work demo-app https://github.com/org/repo/issues/1 --harness codex` creates the worktree, writes the issue body into `TASK_NOTES.md`, and launches codex
- [ ] The same command with no `--harness` on an existing account behaves exactly as 0.2.0
- [ ] A session created with codex never launches claude on resume
- [ ] `cw account login monoku --harness codex --no-browser` prints a `CW_LOGIN_URL=` line and exits 0, and `cw doctor --json` then reports codex `connected` for monoku
- [ ] An existing flat account still works and `CLAUDE_CONFIG_DIR` resolves to the same files
- [ ] `cw account add local --harness opencode --provider ollama --model qwen3-coder:14b` needs no login, and `cw doctor --json` reports it `local` with the model's pull status
- [ ] `cw spaces` and `cw doctor --json` expose harness, provider and model per session and per account
- [ ] `cw doctor` against the real `~/.cw` leaves monoku and meridian working
