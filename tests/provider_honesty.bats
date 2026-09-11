load helpers/setup

setup() {
    setup_cw_home
    make_project app >/dev/null
}

@test "a pi account on openrouter is refused rather than launched on pi's own login" {
    "$CW_BIN" account add free --harness pi --provider openrouter --model qwen/qwen3-coder:free >/dev/null
    run "$CW_BIN" work app fix-auth --account free
    [ "$status" -ne 0 ]
    [[ "$output" == *"Provider 'openrouter' is configured, but the pi driver cannot apply a provider"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "account add warns when the harness cannot apply the provider" {
    run "$CW_BIN" account add free --harness pi --provider openrouter
    [ "$status" -eq 0 ]
    [[ "$output" == *"cannot apply provider 'openrouter'"* ]]
}

@test "account add does not warn for a harness that applies the provider" {
    run "$CW_BIN" account add glm --harness opencode --provider zai --model glm-5.1
    [ "$status" -eq 0 ]
    [[ "$output" != *"cannot apply provider"* ]]
}

@test "a claude account with a third-party provider is refused, since claude never reads it" {
    bash -c "source '$CW_BIN'; _account_meta_set acct claude provider zai"
    run "$CW_BIN" work app fix-auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"the claude driver cannot apply a provider"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "a pi resume is refused too once a provider it cannot apply is configured" {
    "$CW_BIN" account add pa --harness pi >/dev/null
    "$CW_BIN" work app fix-auth --account pa
    bash -c "source '$CW_BIN'; _account_meta_set pa pi provider openrouter"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -ne 0 ]
    [ "$(call_count)" -eq 0 ]
}

@test "opencode and codex accounts with a provider still launch" {
    "$CW_BIN" account add glm --harness opencode --provider zai --model glm-5.1 >/dev/null
    run "$CW_BIN" work app t1 --account glm
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "opencode" ]
    "$CW_BIN" account add cx --harness codex --provider zai --model glm-5.1 >/dev/null
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app t2 --account cx
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "codex" ]
}

@test "a pi account on its native login still launches" {
    "$CW_BIN" account add pa --harness pi >/dev/null
    run "$CW_BIN" work app fix-auth --account pa
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "pi" ]
}

@test "only drivers that apply CW_PROVIDER declare custom_provider" {
    run bash -c "
        for h in claude codex pi opencode; do
            source '$BATS_TEST_DIRNAME/../lib/harnesses/'\$h.sh
            \${h}_supports custom_provider && echo \"\$h yes\" || echo \"\$h no\"
        done"
    [ "$output" = $'claude no\ncodex yes\npi no\nopencode yes' ]
}
