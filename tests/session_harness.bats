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
    # give the account a non-claude default so a wrong fallback would show up
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
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

@test "a --harness with no driver fails clearly and launches nothing" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown harness 'codex'"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "the CW_HARNESS env var routes like --harness would" {
    make_project app >/dev/null
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
    run bash -c "CW_HARNESS=claude '$CW_BIN' work app fix-auth"
    [ "$status" -eq 0 ]
    run grep -q '"harness": "claude"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}

@test "--harness beats the CW_HARNESS env var when both are set" {
    make_project app >/dev/null
    run bash -c "CW_HARNESS=codex '$CW_BIN' work app fix-auth --harness claude"
    [ "$status" -eq 0 ]
    run grep -q '"harness": "claude"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}

@test "cw launch fails cleanly when CW_HARNESS names a harness with no driver" {
    run bash -c "CW_HARNESS=codex '$CW_BIN' launch acct"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown harness 'codex'"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "cw mcp fails cleanly when CW_HARNESS names a harness with no driver" {
    run bash -c "CW_HARNESS=codex '$CW_BIN' mcp list"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown harness 'codex'"* ]]
}

@test "a closed task session can be reopened with a different harness" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    "$CW_BIN" work app fix-auth --done
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth --harness codex
    [[ "$output" != *"was created with claude"* ]]
    run grep -q '"harness": "codex"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}

@test "a closed review session can be reopened with a different harness" {
    make_project app >/dev/null
    "$CW_BIN" review app 123
    "$CW_BIN" review app 123 --done
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" review app 123 --harness codex
    [[ "$output" != *"was created with claude"* ]]
    run grep -q '"harness": "codex"' "$CW_HOME/sessions/app/review-pr-123/session.json"
    [ "$status" -eq 0 ]
}

@test "a closed loop session can be reopened with a different harness" {
    make_project app >/dev/null
    "$CW_BIN" loop app "check the deploy" --name lp
    "$CW_BIN" loop app lp --done
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" loop app "check the deploy" --name lp --harness codex
    [[ "$output" != *"was created with claude"* ]]
    run grep -q '"harness": "codex"' "$CW_HOME/sessions/app/loop-lp/session.json"
    [ "$status" -eq 0 ]
}

@test "project register --harness writes the field into projects.json" {
    local path="$BATS_TEST_TMPDIR/app2"
    mkdir -p "$path"
    git -C "$path" init -q -b main
    git -C "$path" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    run "$CW_BIN" project register "$path" --alias app2 --harness codex
    [ "$status" -eq 0 ]
    run grep -q '"harness": "codex"' "$CW_HOME/projects.json"
    [ "$status" -eq 0 ]
}

@test "project register without --harness leaves the field out" {
    local path="$BATS_TEST_TMPDIR/app3"
    mkdir -p "$path"
    git -C "$path" init -q -b main
    git -C "$path" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    run "$CW_BIN" project register "$path" --alias app3
    [ "$status" -eq 0 ]
    run grep -q 'harness' "$CW_HOME/projects.json"
    [ "$status" -ne 0 ]
}
