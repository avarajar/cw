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
    [ "${#lines[@]}" -eq 21 ]
}
