# codex cli driver
# unverified: no skip-permissions equivalent flag confirmed, so it stays unsupported
codex_supports() {
    case "$1" in
        continue_last|non_interactive_prompt|model_flag|custom_provider) return 0 ;;
        instructions_file) return 0 ;;
        *) return 1 ;;
    esac
}

codex_config_env() {
    printf 'CODEX_HOME=%s\n' "$CW_HARNESS_DIR"
}
# unverified: model_providers config.toml keys for custom_provider are not implemented yet

# codex has no name cw controls; the id is discovered after the run
codex_session_ref() {
    printf '%s' ""
}

_codex_base() {
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
    return 0
}

# resume the last session started in this directory, then a recorded id
codex_resume() {
    local attempt="$1"
    _codex_base
    case "$attempt" in
        1) HARNESS_ARGV+=(resume --last) ;;
        2) [[ -n "$CW_SESSION_REF" ]] || return 1
           HARNESS_ARGV+=(resume "$CW_SESSION_REF") ;;
        *) return 1 ;;
    esac
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
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
