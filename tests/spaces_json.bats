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

@test "spaces --json treats a session with no provider field as native" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    python3 - "$CW_HOME/sessions/app/task-fix-auth/session.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m.pop("provider", None)
json.dump(m, open(p, "w"))
PY
    run bash -c "'$CW_BIN' spaces --json | python3 -c '
import json, sys
print(json.load(sys.stdin)[\"spaces\"][0][\"provider\"])'"
    [ "$output" = "native" ]
}

@test "the human spaces output shows a harness column" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    run "$CW_BIN" spaces
    [[ "$output" == *claude* ]]
}

@test "spaces --json is valid json with nothing to report" {
    run "$CW_BIN" spaces --json
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d == {\"schema\": 1, \"spaces\": []}, d
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "spaces --json escapes a quote in a free-form value so the output still parses" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    python3 - "$CW_HOME/sessions/app/task-fix-auth/session.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["model"] = 'weird"model'
json.dump(m, open(p, "w"))
PY
    run "$CW_BIN" spaces --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" > "$BATS_TEST_TMPDIR/spaces.json"
    run python3 -c "
import json
d = json.load(open('$BATS_TEST_TMPDIR/spaces.json'))
assert d['spaces'][0]['model'] == 'weird\"model', d
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
