load helpers/setup

setup() { setup_cw_home; }

@test "open launches claude in the project dir with the account config dir" {
    local path; path="$(make_project app)"
    run "$CW_BIN" open app
    [ "$(call_count)" -eq 1 ]
    [ "$(call_field 1 cwd)" = "$path" ]
    [ "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" = "$CW_HOME/accounts/acct" ]
    [ -z "$(call_argv 1)" ]
}

@test "launch passes its arguments through verbatim and adds no flags" {
    run "$CW_BIN" launch acct /login
    [ "$(call_count)" -eq 1 ]
    [ "$(call_argv 1)" = "/login" ]
}

@test "work on a new task launches with model, session name and the init prompt" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 1 ]
    [ "$(call_argv 1 | sed -n 1p)" = "--model" ]
    [ "$(call_argv 1 | sed -n 2p)" = "sonnet" ]
    [ "$(call_argv 1 | sed -n 3p)" = "--name" ]
    [ "$(call_argv 1 | sed -n 4p)" = "acct/app/fix-auth" ]
    [ "$(call_argv 1 | sed -n 5p)" = "Set up the workspace:" ]
    [[ "$(call 1)" == *"git worktree add .tasks/fix-auth"* ]]
}

@test "work exports the session context variables" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 'env:CW_PROJECT')" = "app" ]
    [ "$(call_field 1 'env:CW_TASK')" = "fix-auth" ]
    [ "$(call_field 1 'env:CW_TASK_TYPE')" = "task" ]
}

@test "work resume walks resume then continue then name when each exits non-zero" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 1 0" run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 3 ]
    [ "$(call_argv 1 | sed -n 3p)" = "--resume" ]
    [ "$(call_argv 2 | sed -n 3p)" = "--continue" ]
    [ "$(call_argv 3 | sed -n 3p)" = "--name" ]
}

@test "work resume stops at the first attempt that succeeds" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="0" run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 1 ]
}

@test "work --team sets the agent teams env var" {
    make_project app >/dev/null
    run "$CW_BIN" work app big --team
    [ "$(call_field 1 'env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')" = "1" ]
}

@test "skip-permissions is word-split into a separate argument" {
    make_project app >/dev/null
    run "$CW_BIN" --skip-permissions work app fix-auth
    [ "$(call_argv 1 | sed -n 1p)" = "--dangerously-skip-permissions" ]
}

@test "review on a new PR launches with the review session name" {
    make_project app >/dev/null
    run "$CW_BIN" review app 123
    [ "$(call_count)" -eq 1 ]
    [ "$(call_argv 1 | sed -n 2p)" = "acct/app/review-pr-123" ]
}

@test "review re-review walks the three step resume chain" {
    make_project app >/dev/null
    "$CW_BIN" review app 123
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 1 0" run "$CW_BIN" review app 123
    [ "$(call_count)" -eq 3 ]
}

@test "loop on a new session passes the slash command as the prompt" {
    make_project app >/dev/null
    run "$CW_BIN" loop app "check the deploy" --every 5m
    [ "$(call_argv 1 | sed -n 3p)" = "/loop 5m check the deploy" ]
}

@test "loop resume walks the three step resume chain" {
    make_project app >/dev/null
    "$CW_BIN" loop app "check the deploy"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 1 0" run "$CW_BIN" loop app "check the deploy"
    [ "$(call_count)" -eq 3 ]
}

@test "plan launches with the plan session name" {
    make_project app >/dev/null
    run "$CW_BIN" plan app "migrate auth"
    [ "$(call_argv 1 | sed -n 2p)" = "acct/app/plan" ]
}

@test "create launches in the new project directory" {
    run "$CW_BIN" create "a tool" --account acct --name newthing --dir "$BATS_TEST_TMPDIR"
    [ "$(call_field 1 cwd)" = "$BATS_TEST_TMPDIR/newthing" ]
    [ "$(call_argv 1 | sed -n 2p)" = "acct/newthing/init" ]
}

@test "work --done closes the session and launches nothing" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth --done
    [ "$(call_count)" -eq 0 ]
    run grep -q '"status": "done"' "$CW_HOME/sessions/app/task-fix-auth/session.json"
    [ "$status" -eq 0 ]
}
