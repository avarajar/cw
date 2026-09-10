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
    ! call_argv 1 | grep -q -- '--name'
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
