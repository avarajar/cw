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
    ! call_argv 1 | grep -q -- '--name'
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
