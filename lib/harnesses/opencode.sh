# opencode driver
# continue_last is not claimed: its --continue has no confirmed per-worktree scope
opencode_supports() {
    local cap
    for cap in non_interactive_prompt model_flag custom_provider; do
        [[ "$1" == "$cap" ]] && return 0
    done
    return 1
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

# prints the provider/model ref opencode expects; a native provider adds no prefix
_opencode_model_ref() {
    local provider="${CW_PROVIDER:-native}" model="$CW_MODEL"
    if [[ -z "$provider" || "$provider" == "native" || "$model" == "$provider/"* ]]; then
        printf '%s' "$model"
    else
        printf '%s/%s' "$provider" "$model"
    fi
}

# writes the provider and model into the account's opencode config
_opencode_write_config() {
    [[ -n "$CW_PROVIDER" && "$CW_PROVIDER" != "native" ]] || return 0
    mkdir -p "$CW_HARNESS_DIR"
    local why
    why=$(CW_OC_FILE="$CW_HARNESS_DIR/opencode.json" CW_OC_MODEL="$(_opencode_model_ref)" \
          python3 - <<'PY'
import json, os, sys
p = os.environ["CW_OC_FILE"]
model = os.environ["CW_OC_MODEL"]
try:
    with open(p) as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
except Exception:
    print("it is not plain json cw can edit", end="")
    sys.exit(3)
if not isinstance(cfg, dict):
    print("it is not a json object", end="")
    sys.exit(3)
if not model or cfg.get("model") == model:
    sys.exit(0)
cfg["model"] = model
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
PY
    ) && return 0
    _err "Cannot apply model '$(_opencode_model_ref)' to $CW_HARNESS_DIR/opencode.json: ${why:-unknown error}."
    _err "Set \"model\" in that file yourself; cw left it untouched."
    return 1
}

# unverified: --model flag ordering, whether the prompt can be passed on argv for a bare launch
opencode_launch() {
    _opencode_write_config || return 1
    _opencode_base
    if [[ -n "$CW_PROMPT" ]]; then
        HARNESS_ARGV=(opencode run "$CW_PROMPT")
        [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$(_opencode_model_ref)")
    elif [[ -n "$CW_MODEL" ]]; then
        HARNESS_ARGV+=(--model "$(_opencode_model_ref)")
    fi
    return 0
}

# only a recorded session id can be attributed to this session; --continue is never used
# unverified: --continue picks opencode's last session with no confirmed per-worktree scope
opencode_resume() {
    local attempt="$1"
    [[ "$attempt" == "1" && -n "$CW_SESSION_REF" ]] || return 1
    _opencode_write_config || return 1
    _opencode_base
    HARNESS_ARGV=(opencode run "$CW_PROMPT" --session "$CW_SESSION_REF")
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$(_opencode_model_ref)")
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
