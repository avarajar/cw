# shared setup for every bats file
setup_cw_home() {
    unset CLAUDE_CONFIG_DIR CODEX_HOME PI_CODING_AGENT_DIR OPENCODE_DATA_DIR CW_HARNESS
    export HOME="$BATS_TEST_TMPDIR/home"
    export CW_HOME="$BATS_TEST_TMPDIR/cw"
    export CW_FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
    mkdir -p "$HOME/.claude/skills"
    mkdir -p "$CW_HOME"/{accounts,sessions,templates/workflows,agents,commands,stacks}
    echo '{}' > "$CW_HOME/projects.json"
    echo '{}' > "$CW_HOME/active-sessions.json"
    printf 'default_account: acct\nskip_permissions: false\nmodels:\n  work: sonnet\n' \
        > "$CW_HOME/config.yaml"
    mkdir -p "$CW_HOME/accounts/acct"
    echo '{"name":"acct","created":"2026-01-01T00:00:00Z"}' \
        > "$CW_HOME/accounts/acct/meta.json"
    export CW_BIN="$BATS_TEST_DIRNAME/../cw"
    export PATH="$BATS_TEST_DIRNAME/fakes:$PATH"
}

# creates a git repo and registers it under the given name
make_project() {
    local name="$1"
    local path="$BATS_TEST_TMPDIR/$name"
    mkdir -p "$path"
    git -C "$path" init -q -b main
    git -C "$path" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    python3 - "$CW_HOME/projects.json" "$name" "$path" <<'PY'
import json, sys
f, name, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(f) as fh: reg = json.load(fh)
reg[name] = {"path": path, "account": "acct", "type": "fullstack"}
with open(f, "w") as fh: json.dump(reg, fh)
PY
    echo "$path"
}

# prints the Nth recorded invocation, 1-indexed
call() {
    awk -v n="$1" 'BEGIN{c=1} /^--- end ---$/{c++; next} c==n' "$CW_FAKE_LOG"
}

call_count() {
    [[ -f "$CW_FAKE_LOG" ]] || { echo 0; return; }
    grep -c '^--- end ---$' "$CW_FAKE_LOG" || true
}

# prints the argv of the Nth invocation, one per line
call_argv() {
    call "$1" | sed -n 's/^arg=//p'
}

call_field() {
    call "$1" | sed -n "s/^$2=//p"
}

# repoints a registered project at another account
set_project_account() {
    python3 - "$CW_HOME/projects.json" "$1" "$2" <<'PYX'
import json, sys
f, project, account = sys.argv[1], sys.argv[2], sys.argv[3]
with open(f) as fh: reg = json.load(fh)
reg[project]["account"] = account
with open(f, "w") as fh: json.dump(reg, fh)
PYX
}

# prints a file's permission bits portably
mode_of() {
    python3 -c "import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[-3:])" "$1"
}
