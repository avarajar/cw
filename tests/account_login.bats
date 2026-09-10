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

@test "login emits a machine-parseable code line" {
    run "$CW_BIN" account login acct --harness codex --no-browser
    [ "$status" -eq 0 ]
    [[ "$output" == *"CW_LOGIN_CODE=WXYZ-7788"* ]]
}

@test "login passes the harness output through unchanged" {
    run "$CW_BIN" account login acct --harness codex --no-browser
    [[ "$output" == *"Open this URL to continue:"* ]]
}

@test "login preserves the harness output order around the scraped lines" {
    run "$CW_BIN" account login acct --harness codex --no-browser
    local line_no_of
    line_no_of() { printf '%s\n' "$output" | grep -nxF "$1" | head -1 | cut -d: -f1; }
    local l1 l2 l3
    l1=$(line_no_of "Open this URL to continue:")
    l2=$(line_no_of "https://auth.example.com/device?code=WXYZ-7788")
    l3=$(line_no_of "Your code is WXYZ-7788")
    [ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l3" ]
    [ "$l1" -lt "$l2" ]
    [ "$l2" -lt "$l3" ]
}

@test "login exits with the child harness's exit status" {
    cat > "$BATS_TEST_TMPDIR/fakes/codex" <<'FAKE'
#!/usr/bin/env bash
echo "login failed"
exit 7
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/codex"
    run "$CW_BIN" account login acct --harness codex --no-browser
    [ "$status" -eq 7 ]
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

@test "the api key appears nowhere under CW_HOME except the env file" {
    echo 'sk-secret-value' | "$CW_BIN" account login acct --harness codex --with-api-key -
    run grep -rl 'sk-secret-value' "$CW_HOME"
    [ "$status" -eq 0 ]
    [ "$output" = "$CW_HOME/accounts/acct/codex/env" ]
}

@test "the api key never appears in the harness's argv, only on its stdin" {
    local argvlog="$BATS_TEST_TMPDIR/argv.log"
    cat > "$BATS_TEST_TMPDIR/fakes/codex" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$argvlog"
cat > "$BATS_TEST_TMPDIR/stdin.log"
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/codex"
    echo 'sk-secret-value' | "$CW_BIN" account login acct --harness codex --with-api-key - >/dev/null
    run cat "$argvlog"
    [[ "$output" == *"login"* ]]
    [[ "$output" == *"--with-api-key"* ]]
    [[ "$output" != *"sk-secret-value"* ]]
    run grep -q 'sk-secret-value' "$BATS_TEST_TMPDIR/stdin.log"
    [ "$status" -eq 0 ]
}

@test "an account with no driver for the harness fails cleanly instead of doing something surprising" {
    run "$CW_BIN" account login acct --harness pi
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown harness 'pi'"* ]]
}

@test "login on an unknown account fails without touching a harness" {
    run "$CW_BIN" account login ghost --harness codex --no-browser
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    [ ! -d "$CW_HOME/accounts/ghost" ]
}
