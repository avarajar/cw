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
