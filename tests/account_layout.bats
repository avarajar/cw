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

@test "a legacy flat account does not link the file onto itself" {
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    [ ! -L "$CW_HOME/accounts/acct/CLAUDE.md" ]
}

@test "a CW_HARNESS env var naming a harness with no driver fails cleanly" {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    make_project app >/dev/null
    run bash -c "CW_HARNESS=codex '$CW_BIN' work app fix-auth"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown harness 'codex'"* ]]
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
