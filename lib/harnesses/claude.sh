# claude code driver
claude_supports() {
    case "$1" in
        resume_by_name|continue_last|non_interactive_prompt|interactive_prompt) return 0 ;;
        mcp|hooks|skip_permissions|agent_teams|plugins) return 0 ;;
        model_flag|statusline|instructions_file|skills|custom_provider) return 0 ;;
        *) return 1 ;;
    esac
}

claude_config_env() {
    printf 'CLAUDE_CONFIG_DIR=%s\n' "$CW_HARNESS_DIR"
}

claude_session_ref() {
    printf '%s' ""
}

# builds argv for a plugin subcommand without spawning it
claude_plugin() {
    local op="${1:-}" plugin="${2:-}"
    _claude_base_env
    case "$op" in
        list) HARNESS_ARGV=(claude plugin list) ;;
        add)  HARNESS_ARGV=(claude plugin add "$plugin") ;;
        *)    return 1 ;;
    esac
    return 0
}

# builds the common prefix shared by launch and resume
_claude_base_argv() {
    HARNESS_ARGV=(claude)
    local f
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    return 0
}

_claude_base_env() {
    HARNESS_ENV=("CLAUDE_CONFIG_DIR=$CW_HARNESS_DIR")
    [[ -n "${CW_TEAM_ENV:-}" ]] && HARNESS_ENV+=("$CW_TEAM_ENV")
    return 0
}

claude_launch() {
    _claude_base_env
    if [[ -n "${CW_PASSTHRU_ARGV+x}" ]]; then
        HARNESS_ARGV=(claude ${CW_PASSTHRU_ARGV[@]+"${CW_PASSTHRU_ARGV[@]}"})
        return 0
    fi
    _claude_base_argv
    [[ -n "$CW_SESSION_NAME" ]] && HARNESS_ARGV+=(--name "$CW_SESSION_NAME")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

# three attempts: resume by name, continue last, start named
claude_resume() {
    local attempt="$1"
    _claude_base_env
    _claude_base_argv
    case "$attempt" in
        1) HARNESS_ARGV+=(--resume "$CW_SESSION_NAME") ;;
        2) HARNESS_ARGV+=(--continue) ;;
        3) HARNESS_ARGV+=(--name "$CW_SESSION_NAME") ;;
        *) return 1 ;;
    esac
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    return 0
}

claude_doctor() {
    local status detail="null"
    if ! command -v claude >/dev/null 2>&1; then
        status="not_installed"; detail='"claude not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/.claude.json" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"claude","status":"%s","detail":%s}\n' "$status" "$detail"
}
