load helpers/setup

setup() { setup_cw_home; }

teardown() { stop_ollama_stub; }

@test "account add stores harness, provider and model" {
    run "$CW_BIN" account add glm --harness opencode --provider zai --model glm-5.1
    [ "$status" -eq 0 ]
    run bash -c "source '$CW_BIN'; _account_meta_get glm opencode model"
    [ "$output" = "glm-5.1" ]
    run bash -c "source '$CW_BIN'; _account_default_harness glm"
    [ "$output" = "opencode" ]
}

@test "account add --harness with no value fails cleanly instead of an unbound-variable error" {
    run "$CW_BIN" account add glm --harness
    [ "$status" -ne 0 ]
    [[ "$output" == *"--harness requires a value"* ]]
    [[ "$output" != *"unbound variable"* ]]
    [ ! -d "$CW_HOME/accounts/glm" ]
}

@test "account add --model with no value fails cleanly instead of an unbound-variable error" {
    run "$CW_BIN" account add glm --model
    [ "$status" -ne 0 ]
    [[ "$output" == *"--model requires a value"* ]]
    [[ "$output" != *"unbound variable"* ]]
    [ ! -d "$CW_HOME/accounts/glm" ]
}

@test "account add with an unknown flag errors instead of silently ignoring it" {
    run "$CW_BIN" account add glm --modle glm-5.1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown flag"* ]]
    [ ! -d "$CW_HOME/accounts/glm" ]
}

@test "config.yaml models apply to claude" {
    make_project app >/dev/null
    run bash -c "source '$CW_BIN'; _resolve_model acct claude work '' ''"
    [ "$output" = "sonnet" ]
}

@test "config.yaml models do not apply to another harness" {
    run bash -c "source '$CW_BIN'; _resolve_model acct codex work '' ''"
    [ -z "$output" ]
}

@test "the account model beats the config default" {
    bash -c "source '$CW_BIN'; _account_meta_set acct claude model opus"
    run bash -c "source '$CW_BIN'; _resolve_model acct claude work '' ''"
    [ "$output" = "opus" ]
}

@test "an explicit override beats everything" {
    bash -c "source '$CW_BIN'; _account_meta_set acct claude model opus"
    run bash -c "source '$CW_BIN'; _resolve_model acct claude work haiku ''"
    [ "$output" = "haiku" ]
}

@test "a session's recorded model beats the account default" {
    bash -c "source '$CW_BIN'; _account_meta_set acct claude model opus"
    local meta="$BATS_TEST_TMPDIR/session.json"
    echo '{"model":"haiku"}' > "$meta"
    run bash -c "source '$CW_BIN'; _resolve_model acct claude work '' '$meta'"
    [ "$output" = "haiku" ]
}

@test "ollama is a local provider" {
    run bash -c "source '$CW_BIN'; _provider_kind ollama"
    [ "$output" = "local" ]
}

@test "an api provider is neither native nor local" {
    run bash -c "source '$CW_BIN'; _provider_kind zai"
    [ "$output" = "api" ]
}

@test "no provider is native" {
    run bash -c "source '$CW_BIN'; _provider_kind ''"
    [ "$output" = "native" ]
}

@test "a local account needs no login and doctor reports it local" {
    "$CW_BIN" account add local --harness opencode --provider ollama --model qwen3-coder:14b
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
a = [x for x in d[\"accounts\"] if x[\"name\"] == \"local\"][0]
h = [x for x in a[\"harnesses\"] if x[\"harness\"] == \"opencode\"][0]
assert h[\"provider_kind\"] == \"local\", h
assert h[\"model\"] == \"qwen3-coder:14b\", h
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "doctor --json reports ollama reachability and pull status for a local account" {
    "$CW_BIN" account add local --harness opencode --provider ollama --model qwen3-coder:14b
    start_ollama_stub
    run bash -c "'$CW_BIN' doctor --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
a = [x for x in d[\"accounts\"] if x[\"name\"] == \"local\"][0]
h = [x for x in a[\"harnesses\"] if x[\"harness\"] == \"opencode\"][0]
assert h[\"status\"] == \"local\", h
assert h[\"detail\"][\"reachable\"] is True, h
assert h[\"detail\"][\"model_pulled\"] is True, h
print(\"ok\")'"
    [ "$output" = "ok" ]
}

@test "_ollama_reachable is true against a local stub" {
    start_ollama_stub
    run bash -c "source '$CW_BIN'; OLLAMA_HOST='$OLLAMA_HOST' _ollama_reachable"
    [ "$status" -eq 0 ]
}

@test "_ollama_reachable is false when nothing is listening" {
    local port; port="$(free_local_port)"
    run bash -c "source '$CW_BIN'; OLLAMA_HOST='http://127.0.0.1:$port' _ollama_reachable"
    [ "$status" -ne 0 ]
}

@test "_ollama_has_model is true when the stub lists the model" {
    start_ollama_stub '[{"name":"qwen3-coder:14b"}]'
    run bash -c "source '$CW_BIN'; OLLAMA_HOST='$OLLAMA_HOST' _ollama_has_model 'qwen3-coder:14b'"
    [ "$status" -eq 0 ]
}

@test "_ollama_has_model is false when the stub's list omits the model" {
    start_ollama_stub '[{"name":"llama3:8b"}]'
    run bash -c "source '$CW_BIN'; OLLAMA_HOST='$OLLAMA_HOST' _ollama_has_model 'qwen3-coder:14b'"
    [ "$status" -ne 0 ]
}

@test "_ollama_has_model is false with nothing listening" {
    local port; port="$(free_local_port)"
    run bash -c "source '$CW_BIN'; OLLAMA_HOST='http://127.0.0.1:$port' _ollama_has_model 'qwen3-coder:14b'"
    [ "$status" -ne 0 ]
}

@test "_ollama_reachable never executes code injected through OLLAMA_HOST" {
    local marker="$BATS_TEST_TMPDIR/pwned"
    rm -f "$marker"
    local host="' + str(__import__('os').system('touch $marker')) + '"
    OLLAMA_HOST="$host" run bash -c "source '$CW_BIN'; _ollama_reachable"
    [ ! -f "$marker" ]
}

@test "codex writes the account's provider and model into config.toml" {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
    bash -c "source '$CW_BIN'; _account_meta_set acct codex provider zai"
    bash -c "source '$CW_BIN'; _account_meta_set acct codex model glm-5.1"
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    local cfg="$CW_HOME/accounts/acct/codex/config.toml"
    [ -f "$cfg" ]
    grep -qx 'model = "glm-5.1"' "$cfg"
    grep -qx 'model_provider = "zai"' "$cfg"
}

@test "codex writes no config.toml for the native provider" {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ ! -f "$CW_HOME/accounts/acct/codex/config.toml" ]
}

@test "codex rewrites config.toml on resume when the provider changed" {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
    bash -c "source '$CW_BIN'; _account_meta_set acct codex provider zai"
    bash -c "source '$CW_BIN'; _account_meta_set acct codex model glm-5.1"
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    rm -f "$CW_HOME/accounts/acct/codex/config.toml"
    bash -c "source '$CW_BIN'; _account_meta_set acct codex provider openrouter"
    bash -c "source '$CW_BIN'; _account_meta_set acct codex model qwen/qwen3-coder:free"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    local cfg="$CW_HOME/accounts/acct/codex/config.toml"
    [ -f "$cfg" ]
    grep -qx 'model_provider = "openrouter"' "$cfg"
}

@test "cw open resolves the account's provider and model for codex" {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
    bash -c "source '$CW_BIN'; _account_meta_set acct codex provider zai"
    bash -c "source '$CW_BIN'; _account_meta_set acct codex model glm-5.1"
    make_project app >/dev/null
    run "$CW_BIN" open app
    [ "$status" -eq 0 ]
    local cfg="$CW_HOME/accounts/acct/codex/config.toml"
    [ -f "$cfg" ]
    grep -qx 'model_provider = "zai"' "$cfg"
    [ "$(call_argv 1 | sed -n 1p)" = "--model" ]
    [ "$(call_argv 1 | sed -n 2p)" = "glm-5.1" ]
}

@test "cw launch resolves the account's provider and model for codex" {
    mkdir -p "$CW_HOME/accounts/acct/codex"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
    bash -c "source '$CW_BIN'; _account_meta_set acct codex provider zai"
    bash -c "source '$CW_BIN'; _account_meta_set acct codex model glm-5.1"
    CW_HARNESS=codex run "$CW_BIN" launch acct
    [ "$status" -eq 0 ]
    local cfg="$CW_HOME/accounts/acct/codex/config.toml"
    [ -f "$cfg" ]
    grep -qx 'model_provider = "zai"' "$cfg"
}

@test "cw doctor's human output reports a local account needs no login" {
    "$CW_BIN" account add local --harness opencode --provider ollama --model qwen3-coder:14b
    run "$CW_BIN" doctor
    [[ "$output" == *"local — local (no login needed)"* ]]
    [[ "$output" != *"local — "*"not authenticated"* ]]
}
