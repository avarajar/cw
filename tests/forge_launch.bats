load helpers/setup

setup() {
    setup_cw_home
    FAKEBIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKEBIN"
    printf '#!/bin/sh\necho "npx $*"\n' > "$FAKEBIN/npx"
    chmod +x "$FAKEBIN/npx"
    # cw needs bash 4+, but nothing else from PATH that could be a real forge
    ln -s "$(command -v bash)" "$FAKEBIN/bash"
}

@test "cw forge runs the forge-cw package through npx when forge is not installed" {
    run env PATH="$FAKEBIN:/usr/bin:/bin" "$CW_BIN" forge 4000
    [ "$status" -eq 0 ]
    [[ "$output" == *"npx forge-cw --port 4000"* ]]
}
