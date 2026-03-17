#!/usr/bin/env bash
# CW v3 Shell Integration — source from .zshrc / .bashrc

export CW_HOME="${CW_HOME:-$HOME/.cw}"
export PATH="$CW_HOME/bin:$PATH"

# ── Account aliases ─────────────────────────────────────────────────────────
_cw_load_aliases() {
    [[ -d "$CW_HOME/accounts" ]] || return
    for d in "$CW_HOME/accounts"/*/; do
        [[ -d "$d" ]] || continue
        alias "claude-$(basename "$d")"="CLAUDE_CONFIG_DIR=${d} claude"
    done
}
_cw_load_aliases

# ── Quick aliases ───────────────────────────────────────────────────────────
alias cwd='cw dashboard'
alias cws='cw status'
alias cwrl='cw review --list'         # list active reviews
alias cwsp='cw spaces'                   # show active spaces
alias cwl='cw project list'

# ── Mode shortcuts: cwc = code, cwr = review, etc. ─────────────────────────
cwc()  { cw open "$1" --mode code "${@:2}"; }
cwr()  { cw open "$1" --mode review "${@:2}"; }
cwpr() { cw review "$@"; }           # PR review con worktree
cww()  { cw work "$@"; }              # work task con worktree
cwi()  { cw open "$1" --mode research "${@:2}"; }
cwdoc(){ cw open "$1" --mode docs "${@:2}"; }
cwp()  { cw open "$1" --mode planning "${@:2}"; }
cwm()  { cw open "$1" --mode comms "${@:2}"; }
cwf()  { cw open "$1" --mode full "${@:2}"; }

# ── Quick launch ────────────────────────────────────────────────────────────
cc() { cw launch "${1:-work}" "${@:2}"; }

# ── Fuzzy project opener (requires fzf) ─────────────────────────────────────
cwo() {
    command -v fzf &>/dev/null || { echo "Requires fzf"; return 1; }
    [[ -f "$CW_HOME/projects.json" ]] || { echo "No projects found"; return 1; }
    local project; project=$(python3 -c "
import json
with open('$CW_HOME/projects.json') as f:
    for n in json.load(f): print(n)
" 2>/dev/null | fzf --prompt="Project ❯ " --height=10)
    [[ -n "$project" ]] && cw open "$project" "$@"
}

# ── Prompt info (for custom prompts) ────────────────────────────────────────
cw_prompt_info() {
    [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && echo " [claude:$(basename "$CLAUDE_CONFIG_DIR")]"
}

# ── Bash completions ────────────────────────────────────────────────────────
if [[ -n "${BASH_VERSION:-}" ]]; then
    _cw_comp() {
        local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
        case "$prev" in
            cw) COMPREPLY=($(compgen -W "init account project open work review plan spaces launch dashboard status stats doctor help" -- "$cur")) ;;
            account) COMPREPLY=($(compgen -W "add list remove" -- "$cur")) ;;
            project) COMPREPLY=($(compgen -W "register list scaffold setup-mcps setup-agents info" -- "$cur")) ;;
            open|info|setup-mcps|setup-agents)
                [[ -f "$CW_HOME/projects.json" ]] && \
                COMPREPLY=($(compgen -W "$(python3 -c "import json;[print(n) for n in json.load(open('$CW_HOME/projects.json'))]" 2>/dev/null)" -- "$cur")) ;;
            work)
                if [[ $COMP_CWORD -eq 2 ]]; then
                    [[ -f "$CW_HOME/projects.json" ]] && \
                    COMPREPLY=($(compgen -W "$(python3 -c "import json;[print(n) for n in json.load(open('$CW_HOME/projects.json'))]" 2>/dev/null)" -- "$cur"))
                elif [[ $COMP_CWORD -eq 3 ]]; then
                    local proj="${COMP_WORDS[2]}"
                    [[ -d "$CW_HOME/sessions/$proj" ]] && \
                    COMPREPLY=($(compgen -W "$(for d in $CW_HOME/sessions/$proj/task-*/session.json; do [[ -f "$d" ]] && python3 -c "import json; m=json.load(open('$d')); m.get('status')=='active' and print(m.get('task',''))" 2>/dev/null; done)" -- "$cur"))
                fi ;;
            review)
                if [[ $COMP_CWORD -eq 2 ]]; then
                    [[ -f "$CW_HOME/projects.json" ]] && \
                    COMPREPLY=($(compgen -W "$(python3 -c "import json;[print(n) for n in json.load(open('$CW_HOME/projects.json'))]" 2>/dev/null)" -- "$cur"))
                elif [[ $COMP_CWORD -eq 3 ]]; then
                    local proj="${COMP_WORDS[2]}"
                    [[ -d "$CW_HOME/sessions/$proj" ]] && \
                    COMPREPLY=($(compgen -W "$(for d in $CW_HOME/sessions/$proj/review-*/session.json; do [[ -f "$d" ]] && python3 -c "import json; m=json.load(open('$d')); m.get('status')=='active' and print(m.get('pr',''))" 2>/dev/null; done)" -- "$cur"))
                fi ;;
            launch|add)
                [[ -d "$CW_HOME/accounts" ]] && \
                COMPREPLY=($(compgen -W "$(ls "$CW_HOME/accounts" 2>/dev/null)" -- "$cur")) ;;
            --mode|-m) COMPREPLY=($(compgen -W "code review research docs planning comms full" -- "$cur")) ;;
            --task|-t)
                # Complete with active tasks for the project
                local proj="${COMP_WORDS[2]}"
                [[ -d "$CW_HOME/sessions/$proj" ]] && \
                COMPREPLY=($(compgen -W "$(for d in $CW_HOME/sessions/$proj/task-*/session.json; do [[ -f "$d" ]] && python3 -c "import json; m=json.load(open('$d')); m.get('status')=='active' and print(m.get('task',''))" 2>/dev/null; done)" -- "$cur")) ;;
            --pr)
                local proj="${COMP_WORDS[2]}"
                [[ -d "$CW_HOME/sessions/$proj" ]] && \
                COMPREPLY=($(compgen -W "$(for d in $CW_HOME/sessions/$proj/review-*/session.json; do [[ -f "$d" ]] && python3 -c "import json; m=json.load(open('$d')); m.get('status')=='active' and print(m.get('pr',''))" 2>/dev/null; done)" -- "$cur")) ;;
            --type|-t) COMPREPLY=($(compgen -W "fullstack api knowledge infra agents" -- "$cur")) ;;
            --workflow|-w) COMPREPLY=($(compgen -W "$(ls "$CW_HOME/templates/workflows/" 2>/dev/null | sed 's/\.md$//')" -- "$cur")) ;;
            --account|-a) [[ -d "$CW_HOME/accounts" ]] && COMPREPLY=($(compgen -W "$(ls "$CW_HOME/accounts" 2>/dev/null)" -- "$cur")) ;;
        esac
    }
    complete -F _cw_comp cw
fi

# ── Zsh completions ─────────────────────────────────────────────────────────
if [[ -n "${ZSH_VERSION:-}" ]]; then
    _cw_comp_zsh() {
        local -a cmds=('init' 'account' 'project' 'open' 'work' 'review' 'plan' 'spaces' 'launch' 'dashboard' 'status' 'stats' 'doctor' 'help')
        _arguments '1:command:($cmds)' '*::arg:->args'
        case "$state" in
            args)
                case "${words[1]}" in
                    account) _values 'sub' add list remove ;;
                    project) _values 'sub' register list scaffold setup-mcps setup-agents info ;;
                    open|work|review)
                        [[ -f "$CW_HOME/projects.json" ]] && {
                            local -a projs=($(python3 -c "import json;[print(n) for n in json.load(open('$CW_HOME/projects.json'))]" 2>/dev/null))
                            _values 'project' $projs
                        } ;;
                esac ;;
        esac
    }
    if (( $+functions[compdef] )); then
        compdef _cw_comp_zsh cw
    fi
fi
