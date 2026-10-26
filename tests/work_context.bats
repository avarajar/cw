load helpers/setup

setup() {
    setup_cw_home
    make_project app >/dev/null
    mkdir -p "$CW_HOME/accounts/acct/templates"
}

@test "a global work_init.md reaches the init prompt of every account" {
    printf 'GLOBAL RULES for ${project}/${task}\n' > "$CW_HOME/templates/work_init.md"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"GLOBAL RULES for app/fix-auth"* ]]
}

@test "the global work_init.md comes before the account's" {
    echo 'GLOBAL RULES' > "$CW_HOME/templates/work_init.md"
    echo 'ACCOUNT RULES' > "$CW_HOME/accounts/acct/templates/work_init.md"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"GLOBAL RULES"*"ACCOUNT RULES"* ]]
}

@test "an account's work_init.md still works with no global one" {
    echo 'ACCOUNT RULES' > "$CW_HOME/accounts/acct/templates/work_init.md"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"ACCOUNT RULES"* ]]
    [[ "$(call 1)" != *"GLOBAL"* ]]
}
