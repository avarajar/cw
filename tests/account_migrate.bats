load helpers/setup

setup() {
    setup_cw_home
    seed_legacy
}

# a legacy account root holding claude state, cw state and another harness
seed_legacy() {
    local root="$CW_HOME/accounts/acct"
    echo '{"oauth":"token"}' > "$root/.claude.json"
    echo '{"key":"secret"}'  > "$root/.credentials.json"
    echo '{}'               > "$root/settings.json"
    mkdir -p "$root/projects/-Users-x"
    echo '{"type":"user"}'  > "$root/projects/-Users-x/session.jsonl"
    mkdir -p "$root/todos"
    echo 'a note'           > "$root/history file.txt"
    echo 'odd'              > "$root/..oddball"
    ln -s "$root/settings.json" "$root/alias.json"
    echo 'account rules'    > "$root/CLAUDE.md"
    mkdir -p "$root/templates" "$root/skills/demo"
    echo 'ctx'              > "$root/templates/work_init.md"
    echo '# demo'           > "$root/skills/demo/SKILL.md"
    mkdir -p "$root/codex" "$root/pi"
    echo '{}'               > "$root/codex/auth.json"
    echo '{}'               > "$root/pi/config.json"
}

# a stable fingerprint of a tree — path, kind, mode, link target, content hash
tree_manifest() {
    python3 - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
out = []
for dirpath, dirnames, filenames in os.walk(root):
    for name in dirnames + filenames:
        p = os.path.join(dirpath, name)
        rel = os.path.relpath(p, root)
        st = os.lstat(p)
        mode = oct(st.st_mode & 0o7777)
        if os.path.islink(p):
            out.append("L %s %s %s" % (rel, mode, os.readlink(p)))
        elif os.path.isdir(p):
            out.append("D %s %s" % (rel, mode))
        else:
            with open(p, "rb") as fh:
                out.append("F %s %s %s" % (rel, mode, hashlib.sha256(fh.read()).hexdigest()))
print("\n".join(sorted(out)))
PY
}

@test "dry run moves nothing" {
    run "$CW_BIN" account migrate acct --dry-run
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/.claude.json" ]
    [ ! -d "$CW_HOME/accounts/acct/claude" ]
}

@test "dry run leaves the account tree byte-identical" {
    local before after
    before="$(tree_manifest "$CW_HOME/accounts/acct")"
    run "$CW_BIN" account migrate acct --dry-run
    [ "$status" -eq 0 ]
    after="$(tree_manifest "$CW_HOME/accounts/acct")"
    [ "$before" = "$after" ]
}

@test "dry run names every file it would move" {
    run "$CW_BIN" account migrate acct --dry-run
    [[ "$output" == *".claude.json"* ]]
    [[ "$output" == *"settings.json"* ]]
    [[ "$output" != *"meta.json -> claude"* ]]
}

@test "migrate moves claude files and leaves cw files at the root" {
    run "$CW_BIN" account migrate acct
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/claude/.claude.json" ]
    [ -f "$CW_HOME/accounts/acct/claude/settings.json" ]
    [ -f "$CW_HOME/accounts/acct/meta.json" ]
    [ -f "$CW_HOME/accounts/acct/templates/work_init.md" ]
}

@test "migrate moves the dotfiles that hold the credentials" {
    run "$CW_BIN" account migrate acct
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/claude/.claude.json" ]
    [ -f "$CW_HOME/accounts/acct/claude/.credentials.json" ]
    [ ! -e "$CW_HOME/accounts/acct/.claude.json" ]
    [ ! -e "$CW_HOME/accounts/acct/.credentials.json" ]
    run cat "$CW_HOME/accounts/acct/claude/.claude.json"
    [ "$output" = '{"oauth":"token"}' ]
}

@test "migrate moves a dotfile whose name starts with two dots" {
    run "$CW_BIN" account migrate acct
    [ -f "$CW_HOME/accounts/acct/claude/..oddball" ]
    [ ! -e "$CW_HOME/accounts/acct/..oddball" ]
}

@test "migrate keeps cw-owned files and other harness dirs at the root" {
    run "$CW_BIN" account migrate acct
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/CLAUDE.md" ]
    [ -f "$CW_HOME/accounts/acct/skills/demo/SKILL.md" ]
    [ -f "$CW_HOME/accounts/acct/codex/auth.json" ]
    [ -f "$CW_HOME/accounts/acct/pi/config.json" ]
    [ ! -e "$CW_HOME/accounts/acct/claude/codex" ]
    [ ! -e "$CW_HOME/accounts/acct/claude/pi" ]
    [ ! -e "$CW_HOME/accounts/acct/claude/skills" ]
}

@test "migrate preserves nested trees, spaces in names and symlinks" {
    run "$CW_BIN" account migrate acct
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/claude/projects/-Users-x/session.jsonl" ]
    [ -d "$CW_HOME/accounts/acct/claude/todos" ]
    [ -f "$CW_HOME/accounts/acct/claude/history file.txt" ]
    [ -L "$CW_HOME/accounts/acct/claude/alias.json" ]
    run readlink "$CW_HOME/accounts/acct/claude/alias.json"
    [ "$output" = "$CW_HOME/accounts/acct/settings.json" ]
}

@test "resolution follows the account after migration" {
    "$CW_BIN" account migrate acct
    run bash -c "source '$CW_BIN'; _harness_dir acct claude"
    [ "$output" = "$CW_HOME/accounts/acct/claude" ]
}

@test "work still launches with the right config dir after migration" {
    make_project app >/dev/null
    "$CW_BIN" account migrate acct
    run "$CW_BIN" work app fix-auth
    [ "$(call_field 1 'env:CLAUDE_CONFIG_DIR')" = "$CW_HOME/accounts/acct/claude" ]
}

@test "undo restores the flat layout" {
    "$CW_BIN" account migrate acct
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -eq 0 ]
    [ -f "$CW_HOME/accounts/acct/.claude.json" ]
    [ ! -d "$CW_HOME/accounts/acct/claude" ]
}

@test "migrate then undo round-trips to a byte-identical tree" {
    local before after
    before="$(tree_manifest "$CW_HOME/accounts/acct")"
    "$CW_BIN" account migrate acct
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -eq 0 ]
    after="$(tree_manifest "$CW_HOME/accounts/acct")"
    [ "$before" = "$after" ]
}

@test "undo dry run moves nothing" {
    "$CW_BIN" account migrate acct
    local before after
    before="$(tree_manifest "$CW_HOME/accounts/acct")"
    run "$CW_BIN" account migrate acct --undo --dry-run
    [ "$status" -eq 0 ]
    after="$(tree_manifest "$CW_HOME/accounts/acct")"
    [ "$before" = "$after" ]
}

@test "a second migrate changes nothing" {
    "$CW_BIN" account migrate acct
    local before after
    before="$(tree_manifest "$CW_HOME/accounts/acct")"
    run "$CW_BIN" account migrate acct
    [ "$status" -eq 0 ]
    after="$(tree_manifest "$CW_HOME/accounts/acct")"
    [ "$before" = "$after" ]
}

@test "a second undo changes nothing" {
    "$CW_BIN" account migrate acct
    "$CW_BIN" account migrate acct --undo
    local before after
    before="$(tree_manifest "$CW_HOME/accounts/acct")"
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -eq 0 ]
    after="$(tree_manifest "$CW_HOME/accounts/acct")"
    [ "$before" = "$after" ]
}

@test "an interrupted migration loses nothing and re-running finishes it" {
    local root="$CW_HOME/accounts/acct"
    mkdir -p "$root/locked"
    echo 'keep me' > "$root/locked/state.json"
    chmod 555 "$root/locked"
    run "$CW_BIN" account migrate acct
    [ "$status" -ne 0 ]
    [ -f "$root/locked/state.json" ] || [ -f "$root/claude/locked/state.json" ]
    chmod 755 "$root/locked"
    run "$CW_BIN" account migrate acct
    [ "$status" -eq 0 ]
    [ -f "$root/claude/.claude.json" ]
    [ -f "$root/claude/locked/state.json" ]
    [ -f "$root/claude/settings.json" ]
    [ -f "$root/meta.json" ]
}

@test "migrate refuses to overwrite an entry that already exists in claude" {
    local root="$CW_HOME/accounts/acct"
    mkdir -p "$root/claude"
    echo 'newer' > "$root/claude/settings.json"
    run "$CW_BIN" account migrate acct
    [ "$status" -ne 0 ]
    run cat "$root/claude/settings.json"
    [ "$output" = "newer" ]
    [ -f "$root/settings.json" ]
}

@test "undo refuses to overwrite an entry that already exists at the root" {
    local root="$CW_HOME/accounts/acct"
    "$CW_BIN" account migrate acct
    echo 'newer' > "$root/settings.json"
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -ne 0 ]
    run cat "$root/settings.json"
    [ "$output" = "newer" ]
    [ -f "$root/claude/settings.json" ]
}

@test "undo drops the instructions symlink instead of pointing it at itself" {
    local root="$CW_HOME/accounts/acct"
    make_project app >/dev/null
    "$CW_BIN" account migrate acct
    "$CW_BIN" work app fix-auth
    [ -L "$root/claude/CLAUDE.md" ]
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -eq 0 ]
    [ ! -d "$root/claude" ]
    [ ! -L "$root/CLAUDE.md" ]
    run cat "$root/CLAUDE.md"
    [ "$output" = "account rules" ]
}

@test "migrate rejects an unknown account without touching anything" {
    run "$CW_BIN" account migrate ghost
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "migrate rejects an unknown flag" {
    local before after
    before="$(tree_manifest "$CW_HOME/accounts/acct")"
    run "$CW_BIN" account migrate acct --wipe
    [ "$status" -ne 0 ]
    after="$(tree_manifest "$CW_HOME/accounts/acct")"
    [ "$before" = "$after" ]
}

@test "migrate on an account with no claude state creates no claude dir" {
    local root="$CW_HOME/accounts/free"
    mkdir -p "$root/pi"
    echo '{"name":"free","harness":"pi"}' > "$root/meta.json"
    echo '{}' > "$root/pi/config.json"
    run "$CW_BIN" account migrate free
    [ "$status" -eq 0 ]
    [ ! -d "$root/claude" ]
    [ -f "$root/pi/config.json" ]
}

@test "no other command migrates an account on its own" {
    make_project app >/dev/null
    local before after
    before="$(tree_manifest "$CW_HOME/accounts/acct")"
    "$CW_BIN" work app fix-auth
    "$CW_BIN" open app
    "$CW_BIN" account list
    "$CW_BIN" doctor --json >/dev/null
    after="$(tree_manifest "$CW_HOME/accounts/acct")"
    [ -f "$CW_HOME/accounts/acct/.claude.json" ]
    [ ! -d "$CW_HOME/accounts/acct/claude" ]
    [[ "$after" == "$before"* ]]
}

@test "the migration helper is named only by itself and the account dispatcher" {
    run bash -c "awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ {fn=\$1} /_account_migrate/ {print fn}' '$CW_BIN' | LC_ALL=C sort -u"
    [ "$output" = "_account_migrate()
_account_migrate_split()
_account_migrate_undo()
cmd_account()" ]
}

@test "doctor --json reports layout none for an account with no claude state" {
    mkdir -p "$CW_HOME/accounts/free/pi"
    echo '{"name":"free","harness":"pi"}' > "$CW_HOME/accounts/free/meta.json"
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
by = {a[\"name\"]: a[\"layout\"] for a in d[\"accounts\"]}
assert by[\"free\"] == \"none\", by
assert by[\"acct\"] == \"legacy\", by
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "doctor --json reports layout split once the account is migrated" {
    "$CW_BIN" account migrate acct
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d[\"accounts\"][0][\"layout\"] == \"split\", d
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "help lists the migrate subcommand" {
    run "$CW_BIN" help
    [[ "$output" == *"account migrate"* ]]
}

@test "an unknown account subcommand still lists migrate" {
    run "$CW_BIN" account bogus
    [[ "$output" == *"migrate"* ]]
}

@test "a failed first move leaves no claude dir behind" {
    local root="$CW_HOME/accounts/solo"
    mkdir -p "$root/.blocked"
    echo '{"name":"solo"}' > "$root/meta.json"
    echo '{"oauth":"token"}' > "$root/.claude.json"
    echo 'keep me' > "$root/.blocked/state.json"
    chmod 555 "$root/.blocked"
    run "$CW_BIN" account migrate solo
    [ "$status" -ne 0 ]
    [ ! -d "$root/claude" ]
    [ -f "$root/.claude.json" ]
    chmod 755 "$root/.blocked"
    run bash -c "source '$CW_BIN'; _harness_dir solo claude"
    [ "$output" = "$root" ]
}

@test "migrate fails loudly when a move silently leaves a file at the root" {
    run bash -c "
        source '$CW_BIN'
        mv() { [[ \"\$1\" == *'.claude.json' ]] && return 0; command mv \"\$@\"; }
        _account_migrate acct
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"Migration incomplete"* ]]
    [[ "$output" == *".claude.json"* ]]
    [[ "$output" != *"migrated to the split layout"* ]]
}

@test "undo keeps a self-pointing link whose target is gone" {
    local root="$CW_HOME/accounts/acct"
    "$CW_BIN" account migrate acct
    ln -s "$root/ghost" "$root/claude/ghost"
    run "$CW_BIN" account migrate acct --undo
    [ "$status" -eq 0 ]
    [ ! -d "$root/claude" ]
    [ -L "$root/ghost" ]
    run readlink "$root/ghost"
    [ "$output" = "$root/ghost" ]
}

@test "a stray file does not make a claude-free account look legacy" {
    local root="$CW_HOME/accounts/free"
    mkdir -p "$root/pi"
    echo '{"name":"free","harness":"pi"}' > "$root/meta.json"
    echo 'junk' > "$root/.DS_Store"
    run bash -c "source '$CW_BIN'; _account_layout free"
    [ "$output" = "none" ]
    run "$CW_BIN" account migrate free
    [ "$status" -eq 0 ]
    [ ! -d "$root/claude" ]
    [ -f "$root/.DS_Store" ]
}
