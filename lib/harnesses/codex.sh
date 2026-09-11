# codex cli driver
# unverified: no skip-permissions equivalent flag confirmed, so it stays unsupported
codex_supports() {
    case "$1" in
        continue_last|non_interactive_prompt|model_flag|custom_provider) return 0 ;;
        instructions_file|api_key_login) return 0 ;;
        headless_login) return 0 ;;
        *) return 1 ;;
    esac
}

codex_config_env() {
    printf 'CODEX_HOME=%s\n' "$CW_HARNESS_DIR"
}
# unverified: model_providers config.toml keys for custom_provider are not implemented yet

# lists the rollout files codex has written for this account
_codex_rollouts() {
    [[ -d "$CW_HARNESS_DIR/sessions" ]] || return 0
    find "$CW_HARNESS_DIR/sessions" -type f -name 'rollout-*.jsonl' 2>/dev/null | sort
}

# remembers which rollouts existed before a launch, so the new one can be told apart
_codex_snapshot() {
    _CW_CODEX_BEFORE="$(_codex_rollouts)"
}

# unverified: rollout file naming and json-lines layout under $CODEX_HOME/sessions
# prints the id of the one new rollout that mentions this session's notes file, else nothing
codex_session_ref() {
    local marker="${CW_NOTES_FILE:-}"
    [[ -n "$marker" && "${CW_PROMPT:-}" == *"$marker"* ]] || return 0
    CW_CX_BEFORE="${_CW_CODEX_BEFORE:-}" CW_CX_AFTER="$(_codex_rollouts)" CW_CX_MARKER="$marker" \
    python3 - <<'PY' 2>/dev/null
import json, os, re
before = set(filter(None, os.environ["CW_CX_BEFORE"].split("\n")))
after = [p for p in os.environ["CW_CX_AFTER"].split("\n") if p and p not in before]
marker = os.environ["CW_CX_MARKER"]
def mentions(value):
    if isinstance(value, str):
        return marker in value
    if isinstance(value, dict):
        return any(mentions(v) for v in value.values())
    if isinstance(value, list):
        return any(mentions(v) for v in value)
    return False
hits = []
for path in after:
    try:
        with open(path) as f:
            if any(mentions(json.loads(line)) for line in f if line.strip()):
                hits.append(path)
    except Exception:
        continue
uuid = r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$"
m = re.search(uuid, hits[0]) if len(hits) == 1 else None
if m:
    print(m.group(1), end="")
PY
    return 0
}

# writes an openai-compatible provider into the account's codex config
_codex_write_provider() {
    local provider="$1" model="$2"
    [[ -n "$provider" && "$provider" != "native" ]] || return 0
    mkdir -p "$CW_HARNESS_DIR"
    printf 'model = "%s"\nmodel_provider = "%s"\n' "$model" "$provider" \
        > "$CW_HARNESS_DIR/config.toml"
}

_codex_base() {
    _codex_write_provider "${CW_PROVIDER:-}" "${CW_MODEL:-}"
    HARNESS_ENV=("CODEX_HOME=$CW_HARNESS_DIR")
    if [[ -f "$CW_HARNESS_DIR/env" ]]; then
        local -a extra_env=()
        mapfile -t extra_env < <(_harness_env_file "$CW_HARNESS_DIR/env")
        [[ ${#extra_env[@]} -gt 0 ]] && HARNESS_ENV+=("${extra_env[@]}")
    fi
    HARNESS_ARGV=(codex)
    local f
    # unverified: flag ordering around the resume subcommand (before vs after)
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    return 0
}

# unverified: interactive launch argv beyond the bare binary
codex_launch() {
    _codex_base
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    _codex_snapshot
    return 0
}

# only attempts that can be attributed to this session: its recorded id, then --last
# where cw vouches the directory holds nothing but this session's conversations
# unverified: that codex scopes resume --last to the working directory
codex_resume() {
    local attempt="$1"
    local -a plan=()
    [[ -n "$CW_SESSION_REF" ]] && plan+=(id)
    [[ -n "${CW_CONTINUE_LAST_SAFE:-}" ]] && plan+=(last)
    local step="${plan[$((attempt - 1))]:-}"
    [[ -n "$step" ]] || return 1
    _codex_base
    case "$step" in
        id)   HARNESS_ARGV+=(resume "$CW_SESSION_REF") ;;
        last) HARNESS_ARGV+=(resume --last) ;;
        *)    return 1 ;;
    esac
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    _codex_snapshot
    return 0
}

codex_doctor() {
    local status detail="null"
    if ! command -v codex >/dev/null 2>&1; then
        status="not_installed"; detail='"codex not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/auth.json" || -f "$CW_HARNESS_DIR/env" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"codex","status":"%s","detail":%s}\n' "$status" "$detail"
}

codex_login() {
    HARNESS_ENV=("CODEX_HOME=$CW_HARNESS_DIR")
    HARNESS_ARGV=(codex login)
    [[ -n "${CW_LOGIN_NO_BROWSER:-}" ]] && HARNESS_ARGV+=(--device-auth)
    [[ -n "${CW_LOGIN_API_KEY_STDIN:-}" ]] && HARNESS_ARGV=(codex login --with-api-key)
    return 0
}
