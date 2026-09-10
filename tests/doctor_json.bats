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

@test "doctor --json marks a per-account harness with no driver as error, not not_installed" {
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
by = {h[\"harness\"]: h for h in d[\"accounts\"][0][\"harnesses\"]}
assert by[\"opencode\"][\"status\"] == \"error\", by
assert by[\"opencode\"][\"detail\"] == \"no driver for opencode\", by
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "harness list shows the built-in drivers" {
    run "$CW_BIN" harness list
    [[ "$output" == *claude* ]]
    [[ "$output" == *codex* ]]
}
