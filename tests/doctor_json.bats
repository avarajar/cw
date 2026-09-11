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
    local minpath; minpath="$(restricted_path)"
    run bash -c "PATH='$minpath' '$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
by = {h[\"name\"]: h for h in d[\"harnesses\"]}
assert by[\"opencode\"][\"installed\"] is False, by
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "doctor --json reports the layout of a legacy account" {
    echo '{}' > "$CW_HOME/accounts/acct/.claude.json"
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

@test "doctor --json marks a per-account harness with no driver as error, not not_installed" {
    run bash -c "
        source '$CW_BIN'
        CW_HARNESS_ALL='fakeharness'
        _doctor_matrix_json | python3 -c '
import json, sys
d = json.load(sys.stdin)
by = {h[\"harness\"]: h for h in d[0][\"harnesses\"]}
assert by[\"fakeharness\"][\"status\"] == \"error\", by
assert by[\"fakeharness\"][\"detail\"] == \"no driver for fakeharness\", by
print(\"ok\")'
    "
    [ "$output" = "ok" ]
}

@test "doctor --json stays valid when default_harness contains a quote" {
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = 'x"y'
json.dump(m, open(p, "w"))
PY
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d[\"accounts\"][0][\"default_harness\"] == chr(120)+chr(34)+chr(121), d
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "harness list shows the built-in drivers" {
    run "$CW_BIN" harness list
    [[ "$output" == *claude* ]]
    [[ "$output" == *codex* ]]
}

@test "doctor --json reports the warnings the human doctor shows" {
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
codes = [w[\"code\"] for w in d[\"warnings\"]]
assert \"not_authenticated\" in codes and \"no_projects\" in codes, codes
assert all(w[\"message\"] for w in d[\"warnings\"]), d
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "doctor --json and the human doctor count the same findings" {
    rm -rf "$CW_HOME/templates/workflows"
    python3 - "$CW_HOME/projects.json" <<'PY'
import json, sys
json.dump({"gone": {"path": "/nonexistent/x", "account": "acct"}}, open(sys.argv[1], "w"))
PY
    local human; human="$("$CW_BIN" doctor)"
    local bangs; bangs=$(printf '%s\n' "$human" | grep -c '!')
    local json_count
    json_count=$("$CW_BIN" doctor --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["warnings"]) + len(d["issues"]))')
    [ "$bangs" -eq "$json_count" ]
    [[ "$human" == *"$bangs warning(s)"* ]]
    [[ "$human" == *"gone — path missing"* ]]
    "$CW_BIN" doctor --json | grep -q '"code": "project_path_missing"'
}

@test "doctor --json reports a too-old git as an issue and still exits 0" {
    mkdir -p "$BATS_TEST_TMPDIR/oldgit"
    printf '#!/usr/bin/env bash\necho "git version 2.10.0"\n' > "$BATS_TEST_TMPDIR/oldgit/git"
    chmod +x "$BATS_TEST_TMPDIR/oldgit/git"
    run bash -c "PATH='$BATS_TEST_TMPDIR/oldgit:$PATH' '$CW_BIN' doctor --json"
    [ "$status" -eq 0 ]
    run python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['issues'] == [{'code': 'git_too_old', 'message': 'git 2.10 (need 2.15+)'}], d['issues']
print('ok')" "$output"
    [ "$output" = "ok" ]
}

@test "doctor --json counts stale sessions in its warnings" {
    mkdir -p "$CW_HOME/sessions/app/task-old"
    echo '{"status":"active","type":"task","task":"old","last_opened":"2020-01-01T00:00:00Z"}' \
        > "$CW_HOME/sessions/app/task-old/session.json"
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
w = {x[\"code\"]: x for x in json.load(sys.stdin)[\"warnings\"]}
assert w[\"stale_sessions\"][\"count\"] == 1, w
print(\"ok\")'"
    [ "$output" = "ok" ]
}
