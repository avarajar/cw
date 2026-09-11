load helpers/setup

setup() {
    setup_cw_home
    "$CW_BIN" account add local --harness opencode --provider ollama --model qwen3-coder:14b >/dev/null
    make_project app >/dev/null
}

# prints the value after a flag in the Nth call's argv
argv_after() {
    call_argv "$1" | awk -v f="$2" 'p{print; exit} $0==f{p=1}'
}

@test "work --account launches opencode against the local ollama account" {
    run "$CW_BIN" work app fix-auth --account local
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "opencode" ]
    [ "$(call_field 1 'env:OPENCODE_DATA_DIR')" = "$CW_HOME/accounts/local/opencode" ]
    [ "$(argv_after 1 --model)" = "ollama/qwen3-coder:14b" ]
    run python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['model'])" "$CW_HOME/accounts/local/opencode/opencode.json"
    [ "$output" = "ollama/qwen3-coder:14b" ]
}

@test "resuming without --account uses the account the session was created on" {
    "$CW_BIN" work app fix-auth --account local
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "opencode" ]
    [ "$(call_field 1 'env:OPENCODE_DATA_DIR')" = "$CW_HOME/accounts/local/opencode" ]
    [ "$(argv_after 1 --model)" = "ollama/qwen3-coder:14b" ]
}

@test "the exact resume command spaces --json suggests runs on the session's account" {
    "$CW_BIN" work app fix-auth --account local
    local cmd
    cmd=$("$CW_BIN" spaces --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["spaces"][0]["resume"])')
    [[ "$cmd" == "cw work app fix-auth"* ]]
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run bash -c "cw() { '$CW_BIN' \"\$@\"; }; $cmd"
    [ "$status" -eq 0 ]
    [ "$(call_field 1 'env:OPENCODE_DATA_DIR')" = "$CW_HOME/accounts/local/opencode" ]
    [ "$(argv_after 1 --model)" = "ollama/qwen3-coder:14b" ]
}

@test "spaces reports the session's account, not the project's" {
    "$CW_BIN" work app fix-auth --account local
    run bash -c "'$CW_BIN' spaces --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"spaces\"][0][\"account\"])'"
    [ "$output" = "local" ]
    run "$CW_BIN" spaces
    [[ "$output" == *"@local"* ]]
}

@test "a review resumed without --account stays on its codex account" {
    mkdir -p "$CW_HOME/accounts/work2"
    echo '{"name":"work2","harness":"codex"}' > "$CW_HOME/accounts/work2/meta.json"
    "$CW_BIN" review app 123 --account work2
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" review app 123
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "codex" ]
    [ "$(call_field 1 'env:CODEX_HOME')" = "$CW_HOME/accounts/work2/codex" ]
}

@test "a claude session created on another account still resumes on the project account, as before" {
    mkdir -p "$CW_HOME/accounts/other"
    echo '{"name":"other"}' > "$CW_HOME/accounts/other/meta.json"
    "$CW_BIN" work app t6 --account other
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app t6
    [ "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" = "$CW_HOME/accounts/acct" ]
}

@test "spaces suggests --account for a claude session on another account, and that command uses it" {
    mkdir -p "$CW_HOME/accounts/other"
    echo '{"name":"other"}' > "$CW_HOME/accounts/other/meta.json"
    "$CW_BIN" work app t6 --account other
    local cmd
    cmd=$("$CW_BIN" spaces --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["spaces"][0]["resume"])')
    [ "$cmd" = "cw work app t6 --account other" ]
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run bash -c "cw() { '$CW_BIN' \"\$@\"; }; $cmd"
    [ "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" = "$CW_HOME/accounts/other" ]
}

@test "a session whose account was removed refuses to resume on another" {
    "$CW_BIN" work app fix-auth --account local
    rm -rf "$CW_HOME/accounts/local"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer exists"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "opencode with a native provider passes the model without a native/ prefix" {
    mkdir -p "$CW_HOME/accounts/oc"
    echo '{"name":"oc","harness":"opencode","harnesses":{"opencode":{"model":"gpt-5"}}}' \
        > "$CW_HOME/accounts/oc/meta.json"
    run "$CW_BIN" work app fix-auth --account oc
    [ "$status" -eq 0 ]
    [ "$(argv_after 1 --model)" = "gpt-5" ]
    ! grep -q 'native/' "$CW_FAKE_LOG"
}

@test "opencode does not double a provider prefix the model already carries" {
    mkdir -p "$CW_HOME/accounts/oc"
    echo '{"name":"oc","harness":"opencode","harnesses":{"opencode":{"provider":"zai","model":"zai/glm-5.1"}}}' \
        > "$CW_HOME/accounts/oc/meta.json"
    run "$CW_BIN" work app fix-auth --account oc
    [ "$(argv_after 1 --model)" = "zai/glm-5.1" ]
}

@test "plan --account launches on that account instead of the project's" {
    run "$CW_BIN" plan app "migrate auth" --account local
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "opencode" ]
    [ "$(call_field 1 'env:OPENCODE_DATA_DIR')" = "$CW_HOME/accounts/local/opencode" ]
}
