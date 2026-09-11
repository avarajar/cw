load helpers/setup

setup() {
    setup_cw_home
    make_project app >/dev/null
}

use_codex() {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
}

@test "CW_CLAUDE_FLAGS never reaches codex" {
    use_codex
    CW_CLAUDE_FLAGS="--verbose --add-dir /tmp" run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "codex" ]
    [ "$(call_argv 1 | grep -c -e '--verbose' -e '--add-dir')" -eq 0 ]
}

@test "CW_CODEX_FLAGS reaches codex as separate arguments" {
    use_codex
    CW_CODEX_FLAGS="--search --foo" run "$CW_BIN" work app fix-auth
    [ "$(call_argv 1 | sed -n 1p)" = "--search" ]
    [ "$(call_argv 1 | sed -n 2p)" = "--foo" ]
}

@test "CW_CLAUDE_FLAGS still reaches claude" {
    CW_CLAUDE_FLAGS="--verbose" run "$CW_BIN" work app fix-auth
    [ "$(call_argv 1 | sed -n 1p)" = "--verbose" ]
}

@test "--skip-permissions on codex degrades with one line instead of passing claude's flag" {
    use_codex
    run "$CW_BIN" --skip-permissions work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_argv 1 | grep -c -- 'skip-permissions')" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'no skip-permissions flag')" -eq 1 ]
}

@test "skip_permissions in config.yaml degrades on codex too" {
    use_codex
    printf 'default_account: acct\nskip_permissions: true\n' > "$CW_HOME/config.yaml"
    run "$CW_BIN" work app fix-auth
    [ "$(call_argv 1 | grep -c -- 'skip-permissions')" -eq 0 ]
    [[ "$output" == *"no skip-permissions flag"* ]]
}

@test "a one-off --harness codex launches with a CODEX_HOME that exists" {
    cat > "$BATS_TEST_TMPDIR/codex" <<FAKE
#!/usr/bin/env bash
[ -d "\$CODEX_HOME" ] && echo exists > "$BATS_TEST_TMPDIR/home.log" || echo missing > "$BATS_TEST_TMPDIR/home.log"
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/codex"
    [ ! -d "$CW_HOME/accounts/acct/codex" ]
    PATH="$BATS_TEST_TMPDIR:$PATH" run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/home.log")" = "exists" ]
}

@test "no credential dir is created for an account that does not exist" {
    run "$CW_BIN" work app fix-auth --harness codex --account ghost
    [ ! -d "$CW_HOME/accounts/ghost" ]
}
