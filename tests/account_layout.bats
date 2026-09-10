load helpers/setup

setup() { setup_cw_home; }

@test "a legacy flat account resolves claude to the account root" {
    run bash -c "source '$CW_BIN'; _harness_dir acct claude"
    [ "$output" = "$CW_HOME/accounts/acct" ]
}

@test "a legacy flat account resolves codex to a subdir" {
    run bash -c "source '$CW_BIN'; _harness_dir acct codex"
    [ "$output" = "$CW_HOME/accounts/acct/codex" ]
}

@test "a split account resolves claude to the claude subdir" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    run bash -c "source '$CW_BIN'; _harness_dir acct claude"
    [ "$output" = "$CW_HOME/accounts/acct/claude" ]
}

@test "resolve_account returns the name, not a path" {
    run bash -c "source '$CW_BIN'; _resolve_account --account acct"
    [ "$output" = "acct" ]
}

@test "mcp list names the account, not the harness dir" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    run "$CW_BIN" mcp list --account acct
    local clean; clean="$(printf '%s' "$output" | sed -E 's/\x1b\[[0-9;]*m//g')"
    [[ "$clean" == *"account acct"* ]]
    [[ "$clean" != *"account claude"* ]]
}

@test "_mcp_peek_account fails cleanly when --account has no value" {
    run bash -c "source '$CW_BIN'; _mcp_peek_account --account"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--account requires a value"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "account meta round-trips a per-harness model" {
    bash -c "source '$CW_BIN'; _account_meta_set acct codex model gpt-5-codex"
    run bash -c "source '$CW_BIN'; _account_meta_get acct codex model"
    [ "$output" = "gpt-5-codex" ]
}

@test "an account with no harness field defaults to claude" {
    run bash -c "source '$CW_BIN'; _account_default_harness acct"
    [ "$output" = "claude" ]
}

@test "the account instructions file is linked into a split claude dir" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    [ -L "$CW_HOME/accounts/acct/claude/CLAUDE.md" ]
    run cat "$CW_HOME/accounts/acct/claude/CLAUDE.md"
    [ "$output" = "account rules" ]
}

@test "_install_account_instructions no-ops when the loaded driver differs from the requested harness" {
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    mkdir -p "$BATS_TEST_TMPDIR/codexdir"
    run bash -c "
        source '$CW_BIN'
        _harness_load claude
        _install_account_instructions acct codex '$BATS_TEST_TMPDIR/codexdir'
        [[ -e '$BATS_TEST_TMPDIR/codexdir/AGENTS.md' ]] && echo CREATED
        [[ \"\$_CW_HARNESS_LOADED\" == claude ]] && echo STILL_CLAUDE
    "
    [[ "$output" != *"CREATED"* ]]
    [[ "$output" == *"STILL_CLAUDE"* ]]
}

@test "a legacy flat account does not link the file onto itself" {
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    [ ! -L "$CW_HOME/accounts/acct/CLAUDE.md" ]
}

@test "a CW_HARNESS env var naming a harness with no driver fails cleanly" {
    mkdir -p "$CW_HOME/accounts/acct/ghostharness"
    make_project app >/dev/null
    run bash -c "CW_HARNESS=ghostharness '$CW_BIN' work app fix-auth"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown harness 'ghostharness'"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "harness_context falls back to the split dir when CW_HARNESS_DIR is unset" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    run bash -c "
        source '$CW_BIN'
        CW_ACCOUNT=acct
        _harness_context
        printf '%s' \"\$CW_HARNESS_DIR\"
    "
    [ "$output" = "$CW_HOME/accounts/acct/claude" ]
}
