load helpers/setup

scan() {
    python3 "$BATS_TEST_DIRNAME/helpers/scan_launch_sites.py" "$1"
}

@test "no harness binary is spawned outside the driver layer" {
    run scan "$BATS_TEST_DIRNAME/../cw"
    [ "$status" -eq 0 ]
}

@test "the scanner flags every launch site the driver layer replaced" {
    run scan "$BATS_TEST_DIRNAME/fixtures/legacy_launch_sites.txt"
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 22 ]
}

@test "a quoted binary literal in command position is still flagged" {
    local f="$BATS_TEST_TMPDIR/quoted.sh"
    printf '%s\n' '"claude" --resume "$x"' > "$f"
    run scan "$f"
    [ "$status" -eq 1 ]
}

@test "a case label naming a binary is not flagged" {
    local f="$BATS_TEST_TMPDIR/case.sh"
    printf '%s\n' 'case "$harness" in' 'claude) dest="$dir/CLAUDE.md" ;;' 'esac' > "$f"
    run scan "$f"
    [ "$status" -eq 0 ]
}

@test "a real launch right after a case label is still flagged" {
    local f="$BATS_TEST_TMPDIR/case_launch.sh"
    printf '%s\n' 'claude) claude --resume "$session_name" ;;' > "$f"
    run scan "$f"
    [ "$status" -eq 1 ]
}
