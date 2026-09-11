load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
m["harnesses"] = {"codex": {"provider": "zai", "model": "glm-5.1"}}
json.dump(m, open(p, "w"))
PY
    make_project app >/dev/null
    CFG="$CW_HOME/accounts/acct/codex/config.toml"
}

set_codex_model() {
    python3 - "$CW_HOME/accounts/acct/meta.json" "$1" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harnesses"]["codex"]["model"] = sys.argv[2]
json.dump(m, open(p, "w"))
PY
}

# the file with cw's two top-level lines taken out, table contents kept
without_cw_keys() {
    awk '/^\[/{t=1} t || !/^(model|model_provider) = /' "$1"
}

USER_TOML='# my codex settings
approval_policy = "on-request"

[projects."/Users/me/work"]
trust_level = "trusted"

[mcp_servers.docs]
command = "npx"
args = ["-y", "docs-mcp"]
model = "not-top-level"
'

@test "a user's config.toml keeps its projects and mcp_servers byte-identical" {
    printf '%s' "$USER_TOML" > "$CFG"
    cp "$CFG" "$BATS_TEST_TMPDIR/before.toml"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "codex" ]
    diff <(without_cw_keys "$CFG") "$BATS_TEST_TMPDIR/before.toml"
    grep -qx 'model = "glm-5.1"' "$CFG"
    grep -qx 'model_provider = "zai"' "$CFG"
    [ "$(sed -n 1,2p "$CFG" | sort | tr '\n' '|')" = 'model = "glm-5.1"|model_provider = "zai"|' ]
}

@test "existing top-level model keys are replaced in place, leaving the rest untouched" {
    printf 'model = "o3"  # old\nmodel_provider = "openai"\n%s' "$USER_TOML" > "$CFG"
    printf '%s' "$USER_TOML" > "$BATS_TEST_TMPDIR/rest.toml"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$CFG")" = 'model = "glm-5.1"' ]
    [ "$(sed -n 2p "$CFG")" = 'model_provider = "zai"' ]
    diff <(without_cw_keys "$CFG") "$BATS_TEST_TMPDIR/rest.toml"
    grep -qx 'model = "not-top-level"' "$CFG"
}

@test "a launch with the values already in place leaves config.toml byte-identical" {
    printf 'model = "glm-5.1"\nmodel_provider = "zai"\n%s' "$USER_TOML" > "$CFG"
    cp "$CFG" "$BATS_TEST_TMPDIR/before.toml"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    cmp "$CFG" "$BATS_TEST_TMPDIR/before.toml"
}

@test "a model string with quotes, backslashes and newlines cannot inject toml" {
    printf '%s' "$USER_TOML" > "$CFG"
    set_codex_model $'glm"\n[evil]\nx = "1\\'
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    run grep -c '^\[evil\]' "$CFG"
    [ "$output" = "0" ]
    run python3 - "$CFG" <<'PY'
import json, re, sys
line = [l for l in open(sys.argv[1]) if l.startswith("model = ")][0]
value = json.loads(re.match(r'model = (".*")$', line.rstrip("\n")).group(1))
print(value == 'glm"\n[evil]\nx = "1\\')
PY
    [ "$output" = "True" ]
}

@test "a top-level multi-line string is refused and the file is left alone" {
    printf 'notes = """\nmodel = "inside a string"\n"""\n%s' "$USER_TOML" > "$CFG"
    cp "$CFG" "$BATS_TEST_TMPDIR/before.toml"
    run "$CW_BIN" work app fix-auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot apply provider 'zai'"* ]]
    cmp "$CFG" "$BATS_TEST_TMPDIR/before.toml"
    [ "$(call_count)" -eq 0 ]
}

@test "a top-level multi-line array is refused and the file is left alone" {
    printf 'writable_roots = [\n  ["a", "b"],\n]\n%s' "$USER_TOML" > "$CFG"
    cp "$CFG" "$BATS_TEST_TMPDIR/before.toml"
    run "$CW_BIN" work app fix-auth
    [ "$status" -ne 0 ]
    cmp "$CFG" "$BATS_TEST_TMPDIR/before.toml"
    [ "$(call_count)" -eq 0 ]
}

@test "a user-written codex AGENTS.md is never replaced by the account's instructions" {
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    printf 'my own agent rules\n' > "$CW_HOME/accounts/acct/codex/AGENTS.md"
    cp "$CW_HOME/accounts/acct/codex/AGENTS.md" "$BATS_TEST_TMPDIR/before.md"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ ! -L "$CW_HOME/accounts/acct/codex/AGENTS.md" ]
    cmp "$CW_HOME/accounts/acct/codex/AGENTS.md" "$BATS_TEST_TMPDIR/before.md"
    [[ "$output" == *"Keeping your own"* ]]
}

@test "the account instructions are still linked where no AGENTS.md exists" {
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ -L "$CW_HOME/accounts/acct/codex/AGENTS.md" ]
    [ "$CW_HOME/accounts/acct/codex/AGENTS.md" -ef "$CW_HOME/accounts/acct/CLAUDE.md" ]
}

@test "a user-written CLAUDE.md in a split claude dir is never replaced" {
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "claude"
json.dump(m, open(p, "w"))
PY
    mkdir -p "$CW_HOME/accounts/acct/claude"
    echo "account rules" > "$CW_HOME/accounts/acct/CLAUDE.md"
    printf 'hand written\n' > "$CW_HOME/accounts/acct/claude/CLAUDE.md"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ ! -L "$CW_HOME/accounts/acct/claude/CLAUDE.md" ]
    [ "$(cat "$CW_HOME/accounts/acct/claude/CLAUDE.md")" = "hand written" ]
}

@test "an opencode.json that is not plain json is refused and left byte-identical" {
    "$CW_BIN" account add glm --harness opencode --provider zai --model glm-5.1 >/dev/null
    set_project_account app glm
    printf '{\n  // my comment\n  "theme": "dark"\n}\n' > "$CW_HOME/accounts/glm/opencode/opencode.json"
    cp "$CW_HOME/accounts/glm/opencode/opencode.json" "$BATS_TEST_TMPDIR/before.json"
    run "$CW_BIN" work app fix-auth
    [ "$status" -ne 0 ]
    cmp "$CW_HOME/accounts/glm/opencode/opencode.json" "$BATS_TEST_TMPDIR/before.json"
    [ "$(call_count)" -eq 0 ]
}

@test "an opencode.json keeps the user's other keys when cw sets the model" {
    "$CW_BIN" account add glm --harness opencode --provider zai --model glm-5.1 >/dev/null
    set_project_account app glm
    printf '{"theme": "dark", "mcp": {"x": {"type": "local"}}}\n' > "$CW_HOME/accounts/glm/opencode/opencode.json"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    run python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['theme'], d['mcp']['x']['type'], d['model'])" \
        "$CW_HOME/accounts/glm/opencode/opencode.json"
    [ "$output" = "dark local zai/glm-5.1" ]
}
