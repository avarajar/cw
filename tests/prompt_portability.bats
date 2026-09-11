load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$BATS_TEST_TMPDIR/fakes"
    cp "$BATS_TEST_DIRNAME/helpers/fake_gh" "$BATS_TEST_TMPDIR/fakes/gh"
    export CW_FAKE_GH_FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    export PATH="$BATS_TEST_TMPDIR/fakes:$PATH"
    make_project app >/dev/null
}

teardown() { stop_context_stub; }

use_harness() {
    mkdir -p "$CW_HOME/accounts/acct/$1"
    python3 - "$CW_HOME/accounts/acct/meta.json" "$1" <<'PY'
import json, sys
p, h = sys.argv[1], sys.argv[2]
m = json.load(open(p)); m["harness"] = h
json.dump(m, open(p, "w"))
PY
}

@test "codex is pointed at TASK_NOTES.md for a fetched github issue, never at an MCP" {
    use_harness codex
    run "$CW_BIN" work app https://github.com/org/repo/issues/1
    [ "$status" -eq 0 ]
    [[ "$(call 1)" != *"MCP"* ]]
    [[ "$(call 1)" == *"already been fetched into $CW_HOME/sessions/app/task-issues-1/TASK_NOTES.md"* ]]
}

@test "codex is told a linear issue could not be fetched rather than to use a Linear MCP" {
    use_harness codex
    run bash -c "unset LINEAR_API_KEY; '$CW_BIN' work app https://linear.app/x/issue/SEI-214"
    [ "$status" -eq 0 ]
    [[ "$(call 1)" != *"MCP (get_issue"* ]]
    [[ "$(call 1)" != *"list_comments"* ]]
    [[ "$(call 1)" == *"could not be fetched"* ]]
}

@test "codex takes the branch name from TASK_NOTES.md once the linear issue is fetched" {
    use_harness codex
    start_context_stub 200 "$(cat "$BATS_TEST_DIRNAME/fixtures/linear-issue.json")"
    CW_LINEAR_API="$CTX_STUB_URL" LINEAR_API_KEY=lin_test run "$CW_BIN" work app https://linear.app/x/issue/SEI-214
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"Branch line in TASK_NOTES.md"* ]]
    [[ "$(call 1)" != *"branchName field"* ]]
    [[ "$(call 1)" != *"MCP"* ]]
}

@test "codex gets no Notion MCP instruction" {
    use_harness codex
    run bash -c "unset NOTION_TOKEN; '$CW_BIN' work app https://www.notion.so/Spec-1234567890abcdef1234567890abcdef"
    [ "$status" -eq 0 ]
    [[ "$(call 1)" != *"using the Notion MCP"* ]]
    [[ "$(call 1)" == *"could not be fetched"* ]]
}

@test "codex is asked to review its changes instead of running /simplify" {
    use_harness codex
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [[ "$(call 1)" != *"/simplify"* ]]
    [[ "$(call 1)" == *"review your own changes for reuse, quality, and efficiency"* ]]
}

@test "claude keeps /simplify and the MCP fetch instruction" {
    run bash -c "unset LINEAR_API_KEY; '$CW_BIN' work app https://linear.app/x/issue/SEI-214"
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"run /simplify"* ]]
    [[ "$(call 1)" == *"using the Linear MCP (get_issue tool)"* ]]
    [[ "$(call 1)" == *"the branchName field"* ]]
}

@test "codex create from a linear url gets no Linear MCP instruction" {
    use_harness codex
    run "$CW_BIN" create https://linear.app/x/issue/SEI-1 --account acct --name lin --dir "$BATS_TEST_TMPDIR/created"
    [ "$status" -eq 0 ]
    [[ "$(call 1)" != *"MCP:"* ]]
    [[ "$(call 1)" == *"https://linear.app/x/issue/SEI-1"* ]]
}

@test "codex review without gh is not told to use GitHub MCP tools" {
    use_harness codex
    local minpath; minpath="$(restricted_path)"
    ln -sf "$BATS_TEST_DIRNAME/fakes/codex" "$minpath/codex"
    run env PATH="$minpath" "$CW_BIN" review app 123
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "codex" ]
    [[ "$(call 1)" != *"GitHub MCP tools"* ]]
}

@test "cw loop refuses on every harness without slash commands and launches nothing" {
    local h
    for h in codex pi opencode; do
        use_harness "$h"
        rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
        run "$CW_BIN" loop app "check the deploy" --name "lp-$h"
        [ "$status" -ne 0 ] || { echo "$h: loop was not refused"; return 1; }
        [[ "$output" == *"drives Claude Code's /loop command, which $h does not have"* ]] \
            || { echo "$h: $output"; return 1; }
        [ "$(call_count)" -eq 0 ] || { echo "$h: something was launched"; return 1; }
        [ ! -e "$CW_HOME/sessions/app/loop-lp-$h/session.json" ] || { echo "$h: session written"; return 1; }
    done
}

@test "only claude declares slash_commands" {
    run bash -c "
        for h in claude codex pi opencode; do
            source '$BATS_TEST_DIRNAME/../lib/harnesses/'\$h.sh
            \${h}_supports slash_commands && echo \"\$h yes\" || echo \"\$h no\"
        done"
    [ "$output" = $'claude yes\ncodex no\npi no\nopencode no' ]
}
