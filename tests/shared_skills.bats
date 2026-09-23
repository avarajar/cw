load helpers/setup

setup() { setup_cw_home; }

# writes a minimal skill folder
make_skill() {
    mkdir -p "$1"
    printf -- '---\nname: %s\n---\n' "$(basename "$1")" > "$1/SKILL.md"
}

@test "a launch links global skills into the account's config dir" {
    make_skill "$HOME/.claude/skills/council"
    run "$CW_BIN" launch acct
    [ "$status" -eq 0 ]
    [ -L "$CW_HOME/accounts/acct/skills/council" ]
    [ "$(readlink "$CW_HOME/accounts/acct/skills/council")" = "$HOME/.claude/skills/council" ]
}

@test "a task session links global skills too" {
    make_project app >/dev/null
    make_skill "$HOME/.claude/skills/council"
    "$CW_BIN" work app fix-auth
    [ -L "$CW_HOME/accounts/acct/skills/council" ]
}

@test "an account skill wins over a global skill with the same name" {
    make_skill "$HOME/.claude/skills/review"
    make_skill "$CW_HOME/accounts/acct/skills/review"
    "$CW_BIN" launch acct
    [ ! -L "$CW_HOME/accounts/acct/skills/review" ]
}

@test "account skill links in ~/.claude/skills are not linked back" {
    make_skill "$CW_HOME/accounts/other/skills/x"
    ln -s "$CW_HOME/accounts/other/skills/x" "$HOME/.claude/skills/acct--other--x"
    "$CW_BIN" launch acct
    [ ! -e "$CW_HOME/accounts/acct/skills/acct--other--x" ]
}

@test "a link to a removed global skill is dropped on the next launch" {
    make_skill "$HOME/.claude/skills/council"
    "$CW_BIN" launch acct
    rm -rf "$HOME/.claude/skills/council"
    "$CW_BIN" launch acct
    [ ! -L "$CW_HOME/accounts/acct/skills/council" ]
}

@test "a migrated account gets its own skills and the global ones in its claude dir" {
    mkdir -p "$CW_HOME/accounts/acct/claude"
    make_skill "$CW_HOME/accounts/acct/skills/mine"
    make_skill "$HOME/.claude/skills/council"
    "$CW_BIN" launch acct
    [ -L "$CW_HOME/accounts/acct/claude/skills/mine" ]
    [ -L "$CW_HOME/accounts/acct/claude/skills/council" ]
}

@test "a harness without skills gets no links" {
    make_skill "$HOME/.claude/skills/council"
    CW_HARNESS=codex "$CW_BIN" launch acct
    [ ! -e "$CW_HOME/accounts/acct/skills/council" ]
    [ ! -e "$CW_HOME/accounts/acct/codex/skills/council" ]
}

@test "undoing a migration drops the skill links a launch made" {
    make_project app >/dev/null
    echo '{}' > "$CW_HOME/accounts/acct/settings.json"
    make_skill "$CW_HOME/accounts/acct/skills/mine"
    make_skill "$HOME/.claude/skills/council"
    "$CW_BIN" account migrate acct
    "$CW_BIN" work app fix-auth
    [ -L "$CW_HOME/accounts/acct/claude/skills/council" ]
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -eq 0 ]
    [ ! -d "$CW_HOME/accounts/acct/claude" ]
    [ -f "$CW_HOME/accounts/acct/skills/mine/SKILL.md" ]
    [ -d "$HOME/.claude/skills/council" ]
}
