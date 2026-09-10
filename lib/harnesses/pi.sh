# pi coding agent driver
# unverified: entire capability set below is inferred from docs, no binary to check against
pi_supports() {
    case "$1" in
        model_flag|custom_provider|instructions_file) return 0 ;;
        *) return 1 ;;
    esac
}

pi_config_env() {
    printf 'PI_CODING_AGENT_DIR=%s\n' "$CW_HARNESS_DIR"
}

# pi has no name cw controls; no confirmed way to read one back either
pi_session_ref() {
    printf '%s' ""
}

_pi_base() {
    HARNESS_ENV=("PI_CODING_AGENT_DIR=$CW_HARNESS_DIR")
    if [[ -f "$CW_HARNESS_DIR/env" ]]; then
        local -a extra_env=()
        mapfile -t extra_env < <(_harness_env_file "$CW_HARNESS_DIR/env")
        [[ ${#extra_env[@]} -gt 0 ]] && HARNESS_ENV+=("${extra_env[@]}")
    fi
    HARNESS_ARGV=(pi)
    local f
    # unverified: flag ordering and whether these flags exist on pi at all
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    return 0
}

# unverified: --model flag, and whether a prompt can be passed on argv at all
pi_launch() {
    _pi_base
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

# unverified: no resume mechanism confirmed, so this is one fresh-launch attempt
# the resume prompt plus TASK_NOTES.md carry context instead of a real resume
pi_resume() {
    local attempt="$1"
    [[ "$attempt" == "1" ]] || return 1
    _pi_base
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

pi_doctor() {
    local status detail="null"
    if ! command -v pi >/dev/null 2>&1; then
        status="not_installed"; detail='"pi not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/auth.json" || -f "$CW_HARNESS_DIR/env" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"pi","status":"%s","detail":%s}\n' "$status" "$detail"
}

# unverified: login is documented as an in-session /login command, not a subcommand or flag
# cw can only drop the user into a bare interactive session to run it themselves
pi_login() {
    HARNESS_ENV=("PI_CODING_AGENT_DIR=$CW_HARNESS_DIR")
    HARNESS_ARGV=(pi)
    return 0
}
