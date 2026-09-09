load helpers/setup

@test "no harness binary is spawned outside lib/harnesses" {
    run grep -nE '(^|[;&|] *|env [^;|]* )(claude|codex|pi|opencode)( +[-$"]|$)' \
        "$BATS_TEST_DIRNAME/../cw"
    [ "$status" -ne 0 ]
}
