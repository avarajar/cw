# opencode driver
opencode_supports() {
    case "$1" in
        continue_last|non_interactive_prompt|model_flag|custom_provider) return 0 ;;
        *) return 1 ;;
    esac
}

opencode_config_env() {
    printf 'OPENCODE_DATA_DIR=%s\n' "$CW_HARNESS_DIR"
    printf 'OPENCODE_CONFIG=%s\n' "$CW_HARNESS_DIR/opencode.json"
}

# opencode has no name cw controls; no confirmed way to read one back either
opencode_session_ref() {
    printf '%s' ""
}

_opencode_base() {
    HARNESS_ENV=("OPENCODE_DATA_DIR=$CW_HARNESS_DIR"
                 "OPENCODE_CONFIG=$CW_HARNESS_DIR/opencode.json")
    if [[ -f "$CW_HARNESS_DIR/env" ]]; then
        local -a extra_env=()
        mapfile -t extra_env < <(_harness_env_file "$CW_HARNESS_DIR/env")
        [[ ${#extra_env[@]} -gt 0 ]] && HARNESS_ENV+=("${extra_env[@]}")
    fi
    HARNESS_ARGV=(opencode)
    local f
    # unverified: flag ordering, and whether these flags exist on opencode at all
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    return 0
}

# writes the provider and model into the account's opencode config
_opencode_write_config() {
    [[ -n "$CW_PROVIDER" && "$CW_PROVIDER" != "native" ]] || return 0
    mkdir -p "$CW_HARNESS_DIR"
    CW_OC_FILE="$CW_HARNESS_DIR/opencode.json" CW_OC_MODEL="$CW_MODEL" \
    CW_OC_PROVIDER="$CW_PROVIDER" python3 - <<'PY'
import json, os
p = os.environ["CW_OC_FILE"]
try:
    with open(p) as f: cfg = json.load(f)
except Exception:
    cfg = {}
provider, model = os.environ["CW_OC_PROVIDER"], os.environ["CW_OC_MODEL"]
if model:
    cfg["model"] = f"{provider}/{model}" if "/" not in model else model
with open(p, "w") as f: json.dump(cfg, f, indent=2)
PY
}

# unverified: --model flag ordering, whether the prompt can be passed on argv for a bare launch
opencode_launch() {
    _opencode_write_config
    _opencode_base
    if [[ -n "$CW_PROMPT" ]]; then
        HARNESS_ARGV=(opencode run "$CW_PROMPT")
        [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_PROVIDER/$CW_MODEL")
    elif [[ -n "$CW_MODEL" ]]; then
        HARNESS_ARGV+=(--model "$CW_PROVIDER/$CW_MODEL")
    fi
    return 0
}

# unverified: whether --continue is scoped to the working directory the way codex's --last is
# continue the last session here, then a recorded session id
opencode_resume() {
    local attempt="$1"
    _opencode_write_config
    _opencode_base
    case "$attempt" in
        1) HARNESS_ARGV=(opencode run "$CW_PROMPT" --continue) ;;
        2) [[ -n "$CW_SESSION_REF" ]] || return 1
           HARNESS_ARGV=(opencode run "$CW_PROMPT" --session "$CW_SESSION_REF") ;;
        *) return 1 ;;
    esac
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_PROVIDER/$CW_MODEL")
    return 0
}

opencode_doctor() {
    local status detail="null"
    if ! command -v opencode >/dev/null 2>&1; then
        status="not_installed"; detail='"opencode not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/auth.json" || -f "$CW_HARNESS_DIR/env" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"opencode","status":"%s","detail":%s}\n' "$status" "$detail"
}

# unverified: no confirmed --no-browser/device-code flag or api-key import path for opencode
opencode_login() {
    HARNESS_ENV=("OPENCODE_DATA_DIR=$CW_HARNESS_DIR")
    HARNESS_ARGV=(opencode auth login)
    return 0
}
