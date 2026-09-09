load helpers/setup

setup() { setup_cw_home; }

@test "claude supports every capability it needs today" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/harnesses/claude.sh'
                 for c in resume_by_name continue_last mcp hooks skip_permissions \
                          agent_teams plugins model_flag statusline skills; do
                     claude_supports \$c || { echo \"missing \$c\"; exit 1; }
                 done"
    [ "$status" -eq 0 ]
}

@test "an unknown capability is unsupported" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/harnesses/claude.sh'
                 claude_supports teleportation"
    [ "$status" -ne 0 ]
}

@test "degrade prints once per command and returns non-zero" {
    run bash -c "source '$CW_BIN'
                 CW_HARNESS=fakeharness
                 _degrade agent_teams 'no agent teams'
                 _degrade agent_teams 'no agent teams'"
    [ "$status" -ne 0 ]
    [ "$(echo "$output" | grep -c 'no agent teams')" -eq 1 ]
}

@test "CW_CLAUDE_FLAGS is not duplicated by the per-harness flag lookup" {
    make_project app >/dev/null
    CW_CLAUDE_FLAGS="--dangerously-skip-permissions" run "$CW_BIN" work app fix-auth
    [ "$(call_argv 1 | grep -c -- '--dangerously-skip-permissions')" -eq 1 ]
}
