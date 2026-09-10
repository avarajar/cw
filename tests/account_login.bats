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

@test "a secret already stored in an account's env file never appears in argv of a later launch" {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    printf 'CODEX_API_KEY=sk-LEAKCANARY-123\n' > "$CW_HOME/accounts/acct/codex/env"
    local argvlog="$BATS_TEST_TMPDIR/launch-argv.log"
    local envlog="$BATS_TEST_TMPDIR/launch-env.log"
    local leaklog="$BATS_TEST_TMPDIR/env-shim-leak.log"
    cat > "$BATS_TEST_TMPDIR/fakes/codex" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$argvlog"
env > "$envlog"
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/codex"
    # shims the real env binary to catch a secret riding in ITS argv, the
    # actual leak vector: "env KEY=VAL cmd" puts KEY=VAL on env's own argv,
    # not the launched process's, which is why the fake codex above can't see it
    cat > "$BATS_TEST_TMPDIR/fakes/env" <<FAKE
#!/usr/bin/env bash
if [[ \$# -eq 0 ]]; then
    exec /usr/bin/env
fi
for a in "\$@"; do
    [[ "\$a" == CODEX_API_KEY=* ]] && printf '%s\n' "\$a" >> "$leaklog"
done
while [[ \$# -gt 0 && "\$1" == *=* ]]; do
    export "\$1"
    shift
done
exec "\$@"
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/env"
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    run grep -q 'sk-LEAKCANARY-123' "$argvlog"
    [ "$status" -ne 0 ]
    run grep -qx 'CODEX_API_KEY=sk-LEAKCANARY-123' "$envlog"
    [ "$status" -eq 0 ]
    run bash -c "[ ! -f '$leaklog' ] || ! grep -q 'CODEX_API_KEY=sk-LEAKCANARY-123' '$leaklog'"
    [ "$status" -eq 0 ]
}

# runs argv under a 5s watchdog so a reintroduced infinite loop fails fast
_run_with_watchdog() {
    python3 -c "
import subprocess, sys
try:
    r = subprocess.run(sys.argv[1:], capture_output=True, timeout=5, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    print('TIMEOUT-HANG-DETECTED')
    sys.exit(124)
" "$@"
}

@test "--with-api-key without a trailing dash fails cleanly instead of spinning forever" {
    run _run_with_watchdog "$CW_BIN" account login acct --harness codex --with-api-key
    [ "$status" -ne 0 ]
    [[ "$output" != *"TIMEOUT-HANG-DETECTED"* ]]
    [[ "$output" == *"--with-api-key requires a trailing -"* ]]
}

@test "--harness as the final argument fails cleanly instead of an unbound-variable error" {
    run _run_with_watchdog "$CW_BIN" account login acct --harness
    [ "$status" -ne 0 ]
    [[ "$output" == *"--harness requires a value"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "a failed --harness login leaves no stray credential directory behind" {
    run "$CW_BIN" account login acct --harness pi
    [ "$status" -ne 0 ]
    [ ! -d "$CW_HOME/accounts/acct/pi" ]
}

@test "an unterminated final line from the harness is not silently dropped" {
    cat > "$BATS_TEST_TMPDIR/fakes/codex" <<'FAKE'
#!/usr/bin/env bash
echo "Open this URL to continue:"
printf 'Paste the code: '
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/codex"
    run "$CW_BIN" account login acct --harness codex --no-browser
    [ "$status" -eq 0 ]
    [[ "$output" == *"Paste the code: "* ]]
}
