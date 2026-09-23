load helpers/setup

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export CW_HOME="$HOME/.cw"
    export SHELL=/bin/zsh
    mkdir -p "$HOME"
    INSTALL="$BATS_TEST_DIRNAME/../install.sh"
}

@test "install.sh installs cw and adds the shell integration" {
    run bash "$INSTALL"
    [ "$status" -eq 0 ]
    [ -x "$CW_HOME/bin/cw" ]
    grep -q cw-shell-integration "$HOME/.zshrc"
}

@test "install.sh --no-shell installs cw without touching shell rc files" {
    touch "$HOME/.zshrc"
    run bash "$INSTALL" --no-shell
    [ "$status" -eq 0 ]
    [ -x "$CW_HOME/bin/cw" ]
    [ -f "$CW_HOME/cw-shell-integration.sh" ]
    run grep -q cw-shell-integration "$HOME/.zshrc"
    [ "$status" -eq 1 ]
    [ ! -f "$HOME/.bashrc" ]
}

@test "install.sh rejects an unknown option" {
    run bash "$INSTALL" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"--bogus"* ]]
    [ ! -e "$CW_HOME/bin/cw" ]
}
