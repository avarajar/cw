#!/usr/bin/env bash
# ============================================================================
# CW — Claude Workspace Manager
# Orchestrates projects, accounts, modes, MCPs, agents and sessions
# Multi-project orchestrator for Claude Code.
#
# Usage: cw <comando> [opciones]
# ============================================================================
set -uo pipefail

CW_HOME="${CW_HOME:-$HOME/.cw}"
CW_ACCOUNTS_DIR="$CW_HOME/accounts"
CW_REGISTRY="$CW_HOME/projects.json"
CW_SESSIONS_LOG="$CW_HOME/sessions.log"
CW_CONFIG="$CW_HOME/config.yaml"
CW_ACTIVE="$CW_HOME/active-sessions.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colores para output del CLI
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m'
M='\033[0;35m' C='\033[0;36m' BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'

_log()  { echo -e "${G}[cw]${NC} $*"; }
_warn() { echo -e "${Y}[cw]${NC} $*"; }
_err()  { echo -e "${R}[cw]${NC} $*" >&2; }
_set_tab_title() {
    # Set window/tab title (standard)
    printf '\033]1;%s\007' "$1"
    printf '\033]2;%s\007' "$1"
    # Set iTerm2 badge (persists even if Claude changes title)
    printf '\033]1337;SetBadgeFormat=%s\007' "$(printf '%s' "$1" | base64)"
}
_dim()  { echo -e "${DIM}$*${NC}"; }

_ensure_dirs() {
    mkdir -p "$CW_HOME"/{accounts,templates,agents,commands,mcps,hooks,lib,bin}
}

_get_project() {
    python3 -c "
import json, sys
try:
    with open('$CW_REGISTRY') as f: reg = json.load(f)
    if '$1' in reg:
        print(json.dumps(reg['$1']))
    else: sys.exit(1)
except: sys.exit(1)
" 2>/dev/null
}

_get_field() {
    echo "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$2','$3'))" 2>/dev/null
}

# ════════════════════════════════════════════════════════════════════════════
# INIT
# ════════════════════════════════════════════════════════════════════════════
cmd_init() {
    _log "Initializing CW..."
    _ensure_dirs

    [[ -f "$CW_REGISTRY" ]] || echo '{}' > "$CW_REGISTRY"
    [[ -f "$CW_ACTIVE" ]]   || echo '{}' > "$CW_ACTIVE"

    if [[ ! -f "$CW_CONFIG" ]]; then
        cat > "$CW_CONFIG" << 'YAML'
# CW v3 Configuration
default_account: work
default_mode: code
notifications: true
max_concurrent: 8

# Herramientas principales
tools:
  tracker: linear
  docs: notion
  chat: slack
  repo: github
YAML
    fi

    _generate_templates
    _generate_agents
    _generate_commands
    _generate_mcp_docs

    # Copy lib

    _log "${G}✓${NC} Initialized at ${C}$CW_HOME${NC}"
    echo ""
    echo -e "  ${C}cw account add work${NC}              — Create work account"
    echo -e "  ${C}cw account add personal${NC}           — Create personal account"
    echo -e "  ${C}cw project register <path>${NC}        — Register project"
    echo -e "  ${C}cw open <project> -m code${NC}        — Open workspace"
    echo -e "  ${C}cw dashboard${NC}                      — Overview"
}

# ════════════════════════════════════════════════════════════════════════════
# ACCOUNT
# ════════════════════════════════════════════════════════════════════════════
cmd_account() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        add)
            local name="${1:?Usage: cw account add <name>}"
            local dir="$CW_ACCOUNTS_DIR/$name"
            [[ -d "$dir" ]] && { _warn "Account '$name' already exists."; return 1; }
            mkdir -p "$dir"
            echo "{\"name\":\"$name\",\"created\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$dir/meta.json"
            _log "Account ${C}$name${NC} created. Authenticate:"
            echo -e "\n  ${BOLD}CLAUDE_CONFIG_DIR=$dir claude /login${NC}\n"
            ;;
        list|ls)
            echo -e "\n${BOLD}Accounts${NC}"
            for dir in "$CW_ACCOUNTS_DIR"/*/; do
                [[ -d "$dir" ]] || continue
                local n; n=$(basename "$dir")
                local auth="${R}✗${NC}"; [[ -f "$dir/.claude.json" ]] && auth="${G}✓${NC}"
                echo -e "  ${C}$n${NC}  [$auth auth]"
            done; echo ""
            ;;
        remove|rm)
            local name="${1:?Usage: cw account remove <name>}"
            read -rp "Delete account '$name'? [y/N] " c
            [[ "$c" =~ ^[yY]$ ]] && rm -rf "$CW_ACCOUNTS_DIR/$name" && _log "Eliminada."
            ;;
        *) _err "Subcommands: add | list | remove" ;;
    esac
}

# ════════════════════════════════════════════════════════════════════════════
# PROJECT
# ════════════════════════════════════════════════════════════════════════════
cmd_project() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        register|reg)   _project_register "$@" ;;
        list|ls)        _project_list ;;
        scaffold)       _project_scaffold "$@" ;;
        setup-mcps)     _project_setup_mcps "$@" ;;
        setup-agents)   _project_setup_agents "$@" ;;
        info)           _project_info "$@" ;;
        *) _err "Subcommands: register | list | scaffold | setup-mcps | setup-agents | info" ;;
    esac
}

_project_register() {
    local path="${1:?Usage: cw project register <path> [--account X] [--type X]}"; shift
    path=$(realpath "$path" 2>/dev/null || echo "$path")
    local account="work" ptype="fullstack"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account|-a) account="$2"; shift 2 ;;
            --type|-t)    ptype="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local name; name=$(basename "$path")

    python3 -c "
import json
f = '$CW_REGISTRY'
try:
    with open(f) as fh: reg = json.load(fh)
except: reg = {}
reg['$name'] = {
    'path': '$path', 'account': '$account', 'type': '$ptype',
    'registered': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}
with open(f, 'w') as fh: json.dump(reg, fh, indent=2)
"
    mkdir -p "$path/.claude"
    if [[ ! -f "$path/CLAUDE.md" ]]; then
        local tpl="$CW_HOME/templates/CLAUDE.${ptype}.md"
        [[ -f "$tpl" ]] && cp "$tpl" "$path/CLAUDE.md" || cp "$CW_HOME/templates/CLAUDE.fullstack.md" "$path/CLAUDE.md"
    fi

    _log "Project ${C}$name${NC} registered (account=${Y}$account${NC}, type=$ptype)"
    echo -e "  → ${C}cw project setup-mcps $name${NC}     Configure integrations"
    echo -e "  → ${C}cw project setup-agents $name${NC}   Install agents"
}

_project_list() {
    echo -e "\n${BOLD}Projects${NC}\n"
    [[ -f "$CW_REGISTRY" ]] || { _dim "  (none)"; echo ""; return; }
    python3 -c "
import json
with open('$CW_REGISTRY') as f: reg = json.load(f)
if not reg: print('  (none)')
for n, i in reg.items():
    print(f'  \033[0;36m{n:<22}\033[0m [\033[0;33m{i.get(\"account\",\"?\")}\033[0m]  {i.get(\"type\",\"?\")}')
    print(f'                         {i[\"path\"]}')
" 2>/dev/null; echo ""
}

_project_scaffold() {
    local name="${1:?Usage: cw project scaffold <name> [--type X]}"; shift
    local ptype="fullstack"
    while [[ $# -gt 0 ]]; do
        case "$1" in --type|-t) ptype="$2"; shift 2 ;; *) shift ;; esac
    done
    local dir="${CW_PROJECTS_DIR:-$HOME/projects}/$name"
    [[ -d "$dir" ]] && { _err "$dir already exists."; return 1; }
    mkdir -p "$dir"/{.claude/agents,docs,scripts}
    (cd "$dir" && git init -q)
    _project_register "$dir" --type "$ptype"
    _project_setup_agents "$name"
    _log "${G}✓${NC} Scaffolded: ${C}$dir${NC}"
}

_project_setup_mcps() {
    local name="${1:?Usage: cw project setup-mcps <name>}"
    local pj; pj=$(_get_project "$name") || { _err "'$name' not found."; return 1; }
    local account; account=$(_get_field "$pj" account "work")
    local acct_dir="$CW_ACCOUNTS_DIR/$account"

    echo -e "\n${BOLD}Configure MCPs for ${C}$name${NC} (account: ${Y}$account${NC})\n"
    echo -e "  ${C}[1]${NC} GitHub     — PRs, issues, code search"
    echo -e "  ${C}[2]${NC} Linear     — Issues, projects, sprints"
    echo -e "  ${C}[3]${NC} Notion     — Docs, wikis, knowledge base"
    echo -e "  ${C}[4]${NC} Slack      — Mensajes, canales, threads"
    echo -e "  ${C}[5]${NC} Todas"
    echo -e "  ${C}[0]${NC} Cancelar\n"
    read -rp "Select (e.g. 1,2,3): " choices
    [[ "$choices" == "0" ]] && return
    [[ "$choices" == "5" ]] && choices="1,2,3,4"

    echo ""
    local cmds=()
    [[ "$choices" == *"1"* ]] && cmds+=("claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --scope user")
    [[ "$choices" == *"2"* ]] && cmds+=("claude mcp add --transport http linear https://mcp.linear.app/mcp --scope user")
    [[ "$choices" == *"3"* ]] && cmds+=("claude mcp add --transport http notion https://mcp.notion.com/mcp --scope user")
    [[ "$choices" == *"4"* ]] && {
        echo -e "  Slack: configure via ${C}https://mcp.composio.dev${NC} or connector in Claude Desktop.\n"
    }

    if [[ ${#cmds[@]} -gt 0 ]]; then
        _log "Run in your terminal:\n"
        for cmd in "${cmds[@]}"; do
            echo -e "  ${BOLD}CLAUDE_CONFIG_DIR=$acct_dir $cmd${NC}"
        done
        echo -e "\n  Then follow the OAuth flow in your browser."
        echo -e "  Verify with ${C}/mcp${NC} inside Claude Code.\n"
    fi
}

_project_setup_agents() {
    local name="${1:?Usage: cw project setup-agents <name>}"
    local pj; pj=$(_get_project "$name") || { _err "'$name' not found."; return 1; }
    local path; path=$(_get_field "$pj" path "")

    local agents_dir="$path/.claude/agents"
    local cmds_dir="$path/.claude/commands"
    mkdir -p "$agents_dir" "$cmds_dir"

    local ac=0 cc=0
    for f in "$CW_HOME/agents"/*.md; do
        [[ -f "$f" ]] || continue
        local n; n=$(basename "$f")
        [[ -f "$agents_dir/$n" ]] || { cp "$f" "$agents_dir/$n"; ac=$((ac+1)); }
    done
    for f in "$CW_HOME/commands"/*.md; do
        [[ -f "$f" ]] || continue
        local n; n=$(basename "$f")
        [[ -f "$cmds_dir/$n" ]] || { cp "$f" "$cmds_dir/$n"; cc=$((cc+1)); }
    done

    _log "${G}✓${NC} $ac agents + $cc commands → ${C}$path/.claude/${NC}"
}

_project_info() {
    local name="${1:?Usage: cw project info <name>}"
    local pj; pj=$(_get_project "$name") || { _err "'$name' not found."; return 1; }
    python3 -c "
import json, os
info = json.loads('''$pj''')
path = info['path']
print(f'\n\033[1m{\"$name\"}\033[0m')
print(f'  Path:     {path}')
print(f'  Account:  {info.get(\"account\",\"?\")}')
print(f'  Type:     {info.get(\"type\",\"?\")}')
ag = os.path.join(path,'.claude','agents')
if os.path.isdir(ag):
    a = [f[:-3] for f in os.listdir(ag) if f.endswith('.md')]
    print(f'  Agents:   {len(a)} — {\", \".join(a)}')
cm = os.path.join(path,'.claude','commands')
if os.path.isdir(cm):
    c = [f[:-3] for f in os.listdir(cm) if f.endswith('.md')]
    print(f'  Commands: {len(c)} — {\", \".join(c)}')
print(f'  CLAUDE.md: {\"✓\" if os.path.isfile(os.path.join(path,\"CLAUDE.md\")) else \"✗\"}')
print()
" 2>/dev/null
}

# ════════════════════════════════════════════════════════════════════════════
# OPEN — Open Claude in a project
# ════════════════════════════════════════════════════════════════════════════
cmd_open() {
    local name="${1:?Usage: cw open <project> [--mode X] [--account X] [--context X]}"; shift
    local account="" context=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account|-a) account="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local pj; pj=$(_get_project "$name") || { _err "'$name' not found."; return 1; }
    local path; path=$(_get_field "$pj" path "")
    [[ -d "$path" ]] || { _err "Path does not exist: $path"; return 1; }

    account="${account:-$(_get_field "$pj" account "work")}"
    local acct_dir="$CW_ACCOUNTS_DIR/$account"
    _log "Opening ${C}$name${NC}  account=${M}$account${NC}"

    cd "$path"
    _set_tab_title "$name"
    CLAUDE_CONFIG_DIR="$acct_dir" claude --dangerously-skip-permissions

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OPEN $name mode=$mode account=$account" >> "$CW_SESSIONS_LOG"
}




# ════════════════════════════════════════════════════════════════════════════
# LAUNCH — Quick Claude with account
# ════════════════════════════════════════════════════════════════════════════
cmd_launch() {
    local account="${1:-work}"; shift || true
    local dir="$CW_ACCOUNTS_DIR/$account"
    [[ -d "$dir" ]] || { _err "Account '$account' does not exist."; return 1; }
    _log "Launching Claude (${C}$account${NC})..."
    CLAUDE_CONFIG_DIR="$dir" claude "$@"
}

# ════════════════════════════════════════════════════════════════════════════
# REVIEW — PR review con worktree + persistent session
# ════════════════════════════════════════════════════════════════════════════
cmd_review() {
    local name="" pr="" done_flag=false cont_flag=false list_flag=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr)      pr="$2"; shift 2 ;;
            --done)    done_flag=true; shift ;;
            --continue) cont_flag=true; shift ;;
            --list)    list_flag=true; shift ;;
            -*)        shift ;;
            *)         
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$pr" ]]; then
                    pr="$1"
                fi
                shift ;;
        esac
    done

    # ── List active reviews ─────────────────────────────────────────────
    if $list_flag; then
        _spaces_list "$name" "review"
        return
    fi

    [[ -z "$name" ]] && { _err "Usage: cw review <project> <PR>"; return 1; }

    local pj; pj=$(_get_project "$name") || { _err "'$name' not found."; return 1; }
    local path; path=$(_get_field "$pj" path "")
    local account; account=$(_get_field "$pj" account "work")
    local acct_dir="$CW_ACCOUNTS_DIR/$account"

    [[ -z "$pr" ]] && { _err "Missing PR. Usage: cw review $name 123"; return 1; }

    # Parse PR URL if provided
    if [[ "$pr" == http* ]]; then
        local pr_url="$pr"
        if [[ "$pr" == *github.com* ]]; then
            pr=$(echo "$pr" | grep -oE '[0-9]+$')
        elif [[ "$pr" == *linear.app* ]]; then
            pr=$(echo "$pr" | grep -oE '[A-Z]+-[0-9]+' | head -1)
        fi
        _log "URL detected → PR=${C}$pr${NC}"
    fi

    local sessions_dir="$CW_HOME/sessions/$name"
    local session_dir="$sessions_dir/review-pr-$pr"
    local session_meta="$session_dir/session.json"
    local wt_dir="$path/.reviews/pr-$pr"
    local notes_file="$session_dir/REVIEW_NOTES.md"

    # ── Done: limpiar review ────────────────────────────────────────────
    if $done_flag; then
        _space_done "$name" "$pr" "review" "$path" "$wt_dir" "$session_dir"
        (cd "$path" && git branch -D "pr-$pr" 2>/dev/null) || true
        return
    fi

    # ── Create or resume review ──────────────────────────────────────────
    mkdir -p "$session_dir"

    local is_new=true
    [[ -f "$session_meta" ]] && is_new=false

    if $is_new; then
        _log "New review: ${C}$name${NC} PR #${Y}$pr${NC}"

        # Fetch PR branch from remote
        (
            cd "$path"
            git fetch origin 2>/dev/null || true

            # Try to find the PR branch
            local pr_branch=""
            pr_branch=$(git ls-remote --heads origin 2>/dev/null | grep -i "pr\|pull" | head -1 | awk '{print $2}' | sed 's|refs/heads/||') || true

            # Fetch PR ref directly (works with GitHub)
            git fetch origin "pull/$pr/head:pr-$pr" 2>/dev/null || {
                _log "${Y}Could not fetch PR #$pr directamente.${NC}"
                _log "Creating worktree from HEAD. You can checkout manually."
            }
        )

        # Create worktree
        mkdir -p "$(dirname "$wt_dir")"
        if (cd "$path" && git worktree add "$wt_dir" "pr-$pr" 2>/dev/null); then
            _log "Worktree created: ${C}$wt_dir${NC}"
        elif (cd "$path" && git worktree add "$wt_dir" HEAD 2>/dev/null); then
            _log "Worktree created from HEAD (checkout branch manually)"
        else
            _err "Could not create worktree. Check git status."
            return 1
        fi

        # Save session metadata
        python3 -c "
import json
from datetime import datetime
meta = {
    'project': '$name',
    'pr': '$pr',
    'type': 'review',
    'account': '$account',
    'worktree': '$wt_dir',
    'notes': '$notes_file',
    'status': 'active',
    'created': datetime.utcnow().isoformat() + 'Z',
    'last_opened': datetime.utcnow().isoformat() + 'Z',
    'opens': 1
}
with open('$session_meta', 'w') as f:
    json.dump(meta, f, indent=2)
"
        _log "Session created: ${C}$session_dir${NC}"

        # Create review notes
        {
            echo "# Review: PR #$pr"
            echo "**Project:** $name"
            echo "**Created:** $(date +%Y-%m-%d)"
            echo ""
            echo "## PR Summary"
            echo "<!-- Claude fills this during review -->"
            echo ""
            echo "## Findings"
            echo "<!-- Issues found, suggestions -->"
            echo ""
            echo "## Status"
            echo "- [ ] Reviewed"
            echo ""
            echo "## Notes"
            echo "<!-- Additional comments -->"
        } > "$notes_file"

        # Symlink notes into worktree (so Claude can read it)
        ln -sf "$notes_file" "$wt_dir/REVIEW_NOTES.md" 2>/dev/null || true
        # Exclude from git (per-worktree, not committed)
        local wt_git_dir
        wt_git_dir=$(cd "$wt_dir" && git rev-parse --git-dir 2>/dev/null) || true
        if [[ -n "$wt_git_dir" ]]; then
            local exclude_file="$wt_git_dir/info/exclude"
            mkdir -p "$(dirname "$exclude_file")" 2>/dev/null || true
            grep -q "REVIEW_NOTES.md" "$exclude_file" 2>/dev/null || echo "REVIEW_NOTES.md" >> "$exclude_file"
        fi

    else
        # Existing review - update metadata
        _log "Resuming review: ${C}$name${NC} PR #${Y}$pr${NC}"
        python3 -c "
import json
from datetime import datetime
with open('$session_meta') as f: meta = json.load(f)
meta['last_opened'] = datetime.utcnow().isoformat() + 'Z'
meta['opens'] = meta.get('opens', 0) + 1
with open('$session_meta', 'w') as f:
    json.dump(meta, f, indent=2)
"
    fi

    # ── Run Claude ────────────────────────────────────────────────────
    cd "$wt_dir"
    _set_tab_title "PR#$pr - $name"
    if ! $is_new; then
        CLAUDE_CONFIG_DIR="$acct_dir" claude --dangerously-skip-permissions --continue
    else
        CLAUDE_CONFIG_DIR="$acct_dir" claude --dangerously-skip-permissions
    fi


    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) REVIEW $name pr=$pr account=$account" >> "$CW_SESSIONS_LOG"
}

# ════════════════════════════════════════════════════════════════════════════
# WORK — Feature/bugfix con worktree + persistent session
# ════════════════════════════════════════════════════════════════════════════
cmd_work() {
    local name="" task="" done_flag=false list_flag=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task|-t)   task="$2"; shift 2 ;;
            --done)      done_flag=true; shift ;;
            --list)      list_flag=true; shift ;;
            -*)          shift ;;
            *)           
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$task" ]]; then
                    task="$1"
                fi
                shift ;;
        esac
    done

    if $list_flag; then
        _spaces_list "$name" "task"
        return
    fi

    [[ -z "$name" ]] && { _err "Usage: cw work <project> <task>"; return 1; }
    [[ -z "$task" ]] && { _err "Missing task. Usage: cw work $name fix-auth"; return 1; }

    # ── Parse URLs → extract task ID + source ───────────────────────────
    local task_url="" task_source="" task_slug="" task_branch=""
    if [[ "$task" == http* ]]; then
        task_url="$task"
        if [[ "$task" == *linear.app* ]]; then
            task_source="linear"
            task_slug=$(echo "$task" | grep -oE '[A-Z]+-[0-9]+' | head -1)
            [[ -z "$task_slug" ]] && task_slug=$(echo "$task" | sed 's|.*/||' | head -c 30)
        elif [[ "$task" == *notion.so* ]] || [[ "$task" == *notion.site* ]]; then
            task_source="notion"
            task_slug=$(echo "$task" | sed 's|.*/||' | sed 's|-[a-f0-9]*$||' | head -c 30)
        elif [[ "$task" == *github.com* ]] && [[ "$task" == *issue* || "$task" == *pull* ]]; then
            task_source="github"
            task_slug=$(echo "$task" | grep -oE '(issues|pull)/[0-9]+' | sed 's|/|-|')
            [[ -z "$task_slug" ]] && task_slug=$(echo "$task" | sed 's|.*/||' | head -c 30)
        else
            task_source="url"
            task_slug=$(echo "$task" | sed 's|https\?://||' | sed 's|/|-|g' | head -c 30)
        fi
        task="$task_slug"
        _log "URL detected (${Y}$task_source${NC}) → task=${C}$task${NC}"
    fi

    local pj; pj=$(_get_project "$name") || { _err "'$name' not found."; return 1; }
    local path; path=$(_get_field "$pj" path "")
    local account; account=$(_get_field "$pj" account "work")
    local acct_dir="$CW_ACCOUNTS_DIR/$account"

    local session_dir="$CW_HOME/sessions/$name/task-$task"
    local session_meta="$session_dir/session.json"
    local wt_dir="$path/.tasks/$task"
    local notes_file="$session_dir/TASK_NOTES.md"

    # ── Done ────────────────────────────────────────────────────────────
    if $done_flag; then
        _space_done "$name" "$task" "task" "$path" "$wt_dir" "$session_dir"
        return
    fi

    # ── Create or resume ─────────────────────────────────────────────────
    mkdir -p "$session_dir"

    local is_new=true
    [[ -f "$session_meta" ]] && is_new=false

    if $is_new; then
        _log "New task: ${C}$name${NC} task=${Y}$task${NC}"

        # Build initial prompt for Claude based on source
        local init_prompt=""
        if [[ "$task_source" == "linear" ]]; then
            init_prompt="Fetch Linear issue $task using the Linear MCP (get_issue tool). Get the git branch name from the issue. Then:
1. Run: git fetch origin
2. Create a worktree: git worktree add .tasks/$task <branch_from_linear>
   - If branch doesn't exist remotely, create it from main: git worktree add .tasks/$task -b <branch_name> origin/main
3. Read the TASK_NOTES.md symlink in .tasks/$task/ and fill in the Context section with the issue details (title, description, acceptance criteria, priority).
4. Then start working from the .tasks/$task/ directory.

Source URL: $task_url"
        elif [[ "$task_source" == "notion" ]]; then
            init_prompt="Fetch this Notion page using the Notion MCP: $task_url
Then:
1. Create a worktree: git worktree add .tasks/$task -b task/$task origin/main (or main)
2. Read the TASK_NOTES.md symlink in .tasks/$task/ and fill in the Context section with the page content.
3. Then start working from the .tasks/$task/ directory."
        elif [[ "$task_source" == "github" ]]; then
            init_prompt="Fetch this GitHub issue/PR using the GitHub MCP: $task_url
Get the branch name if it is a PR. Then:
1. Run: git fetch origin
2. Create a worktree: git worktree add .tasks/$task <branch> (use PR branch or create task/$task from main)
3. Read the TASK_NOTES.md symlink in .tasks/$task/ and fill in the Context section.
4. Then start working from the .tasks/$task/ directory."
        else
            # No URL — just a branch/task name
            init_prompt="Set up the workspace:
1. Run: git fetch origin
2. Try to create worktree from existing branch: git worktree add .tasks/$task $task
   - If that fails, try: git worktree add .tasks/$task origin/$task
   - If that also fails, create new branch: git worktree add .tasks/$task -b $task origin/main
3. If there is a TASK_NOTES.md in .tasks/$task/, read it for context.
4. Then start working from the .tasks/$task/ directory."
        fi

        # Create notes file in session dir
        {
            echo "# Task: $task"
            echo "**Project:** $name"
            echo "**Created:** $(date +%Y-%m-%d)"
            if [[ -n "$task_url" ]]; then
                echo "**Source:** $task_url"
            fi
            echo ""
            echo "## Context"
            echo "<!-- Claude fills this after fetching from source -->"
            echo ""
            echo "## Objective"
            echo "<!-- Describe what needs to be done -->"
            echo ""
            echo "## Decisions"
            echo "<!-- Claude and you log important decisions here -->"
            echo ""
            echo "## Status"
            echo "- [ ] Pending"
            echo ""
            echo "## Notes"
            echo "<!-- Findings, context, references -->"
        } > "$notes_file"

        # Pre-create .tasks dir and symlink notes
        mkdir -p "$path/.tasks/$task"
        # Exclude .tasks from git
        local proj_git_dir
        proj_git_dir=$(cd "$path" && git rev-parse --git-dir 2>/dev/null) || true
        if [[ -n "$proj_git_dir" ]]; then
            local proj_exclude="$proj_git_dir/info/exclude"
            mkdir -p "$(dirname "$proj_exclude")" 2>/dev/null || true
            grep -q ".tasks" "$proj_exclude" 2>/dev/null || echo ".tasks" >> "$proj_exclude"
            grep -q "TASK_NOTES.md" "$proj_exclude" 2>/dev/null || echo "TASK_NOTES.md" >> "$proj_exclude"
        fi
        ln -sf "$notes_file" "$path/.tasks/$task/TASK_NOTES.md" 2>/dev/null || true

        # Save session
        python3 -c "
import json
from datetime import datetime
meta = {
    'project': '$name', 'task': '$task', 'type': 'task',
    'account': '$account',
    'worktree': '$wt_dir', 'notes': '$notes_file',
    'source': '$task_source', 'source_url': '$task_url',
    'status': 'active',
    'created': datetime.utcnow().isoformat() + 'Z',
    'last_opened': datetime.utcnow().isoformat() + 'Z',
    'opens': 1
}
with open('$session_meta', 'w') as f: json.dump(meta, f, indent=2)
"

    else
        _log "Resuming task: ${C}$name${NC} task=${Y}$task${NC}"
        python3 -c "
import json
from datetime import datetime
with open('$session_meta') as f: meta = json.load(f)
meta['last_opened'] = datetime.utcnow().isoformat() + 'Z'
meta['opens'] = meta.get('opens', 0) + 1
with open('$session_meta', 'w') as f: json.dump(meta, f, indent=2)
"
    fi

    # ── Run Claude ──────────────────────────────────────────────────────
    # If worktree exists, open there. Otherwise project root.
    local open_dir="$path"
    [[ -d "$wt_dir" ]] && open_dir="$wt_dir"

    cd "$open_dir"
    _set_tab_title "$task - $name"

    if $is_new && [[ -n "$init_prompt" ]]; then
        local prompt_file="$session_dir/init_prompt.txt"
        printf '%s' "$init_prompt" > "$prompt_file"
        CLAUDE_CONFIG_DIR="$acct_dir" claude --dangerously-skip-permissions "$(cat "$prompt_file")"
    elif ! $is_new; then
        CLAUDE_CONFIG_DIR="$acct_dir" claude --dangerously-skip-permissions --continue
    else
        CLAUDE_CONFIG_DIR="$acct_dir" claude --dangerously-skip-permissions
    fi

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) WORK $name task=$task account=$account" >> "$CW_SESSIONS_LOG"
}

# ════════════════════════════════════════════════════════════════════════════
# SPACES — Ver todos los espacios activos
# ════════════════════════════════════════════════════════════════════════════
cmd_spaces() {
    local filter="${1:-}"
    local sessions_dir="$CW_HOME/sessions"

    echo -e "\n${BOLD}Active spaces${NC}\n"

    if [[ ! -d "$sessions_dir" ]]; then
        echo -e "  ${DIM}No active spaces${NC}\n"
        return
    fi

    local found=false

    # Group by project
    for proj_dir in "$sessions_dir"/*/; do
        [[ -d "$proj_dir" ]] || continue
        local proj; proj=$(basename "$proj_dir")
        [[ -n "$filter" ]] && [[ "$proj" != "$filter" ]] && continue

        local proj_has_active=false

        # Collect active spaces for this project
        local spaces_output=""
        for space_dir in "$proj_dir"/*/; do
            [[ -d "$space_dir" ]] || continue
            local meta="$space_dir/session.json"
            [[ -f "$meta" ]] || continue

            local status stype sid sopens slast
            status=$(python3 -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null)
            [[ "$status" != "active" ]] && continue

            stype=$(python3 -c "import json; print(json.load(open('$meta')).get('type','?'))" 2>/dev/null)
            sopens=$(python3 -c "import json; print(json.load(open('$meta')).get('opens',0))" 2>/dev/null)
            slast=$(python3 -c "import json; print(json.load(open('$meta')).get('last_opened','?')[:10])" 2>/dev/null)

            local label="" cmd=""
            if [[ "$stype" == "task" ]]; then
                sid=$(python3 -c "import json; print(json.load(open('$meta')).get('task','?'))" 2>/dev/null)
                label="task: $sid"
                cmd="cw work $proj --task $sid"
            elif [[ "$stype" == "review" ]]; then
                sid=$(python3 -c "import json; print(json.load(open('$meta')).get('pr','?'))" 2>/dev/null)
                label="review: PR #$sid"
                cmd="cw review $proj --pr $sid"
            fi

            spaces_output+="    ${Y}$label${NC}  ${DIM}(${sopens}x, $slast)${NC}\n"
            spaces_output+="      ${DIM}resume:${NC} $cmd\n"
            spaces_output+="      ${DIM}close:${NC}  $cmd --done\n"
            proj_has_active=true
            found=true
        done

        if $proj_has_active; then
            # Get account for this project
            local pacct=""
            local ppj; ppj=$(_get_project "$proj" 2>/dev/null) && pacct=$(_get_field "$ppj" account "")
            echo -e "  ${C}$proj${NC}  ${DIM}($pacct)${NC}"
            echo -e "$spaces_output"
        fi
    done

    $found || echo -e "  ${DIM}No active spaces${NC}\n"

    echo -e "  ${DIM}Close all for a project: cw work <proy> --task <t> --done${NC}"
    echo -e "  ${DIM}                            cw review <proy> --pr <n> --done${NC}\n"
}

# ── Shared: close space ──────────────────────────────────────────────────
_space_done() {
    local name="$1" id="$2" type="$3" path="$4" wt_dir="$5" session_dir="$6"

    _log "Closing $type: ${C}$name${NC} ${Y}$id${NC}"

    # Remove worktree
    if [[ -d "$wt_dir" ]]; then
        (cd "$path" && git worktree remove "$wt_dir" --force 2>/dev/null) || {
            rm -rf "$wt_dir"
            (cd "$path" && git worktree prune 2>/dev/null) || true
        }
        _log "Worktree removed"
    fi

    # Clean up parent dir if empty
    local parent_dir="$(dirname "$wt_dir")"
    [[ -d "$parent_dir" ]] && rmdir "$parent_dir" 2>/dev/null || true

    # Update session
    if [[ -f "$session_dir/session.json" ]]; then
        python3 -c "
import json
from datetime import datetime
with open('$session_dir/session.json') as f: meta = json.load(f)
meta['status'] = 'done'
meta['closed'] = datetime.utcnow().isoformat() + 'Z'
with open('$session_dir/session.json', 'w') as f: json.dump(meta, f, indent=2)
"
    fi

    _log "${G}$type $id closed${NC}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) DONE $name $type=$id" >> "$CW_SESSIONS_LOG"
}

# ── Shared: list by type ─────────────────────────────────────────────────
_spaces_list() {
    local filter="$1" type_filter="$2"
    local sessions_dir="$CW_HOME/sessions"

    if [[ ! -d "$sessions_dir" ]]; then
        echo -e "  ${DIM}No active spaces${NC}"
        return
    fi

    for proj_dir in "$sessions_dir"/*/; do
        [[ -d "$proj_dir" ]] || continue
        local proj; proj=$(basename "$proj_dir")
        [[ -n "$filter" ]] && [[ "$proj" != "$filter" ]] && continue

        for space_dir in "$proj_dir"/${type_filter}-*/; do
            [[ -d "$space_dir" ]] || continue
            local meta="$space_dir/session.json"
            [[ -f "$meta" ]] || continue
            local st; st=$(python3 -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null)
            [[ "$st" != "active" ]] && continue
            local sid; sid=$(python3 -c "import json; m=json.load(open('$meta')); print(m.get('task','') or m.get('pr','?'))" 2>/dev/null)
            local sopens; sopens=$(python3 -c "import json; print(json.load(open('$meta')).get('opens',0))" 2>/dev/null)
            echo -e "  ${C}$proj${NC}  ${Y}$sid${NC}  ${DIM}(${sopens}x)${NC}"
        done
    done
}

# ════════════════════════════════════════════════════════════════════════════
# STATUS / DASHBOARD
# ════════════════════════════════════════════════════════════════════════════
cmd_status() {
    echo -e "\n${BOLD}CW Status${NC}\n"
    local accts=0 projs=0
    [[ -d "$CW_ACCOUNTS_DIR" ]] && accts=$(find "$CW_ACCOUNTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    [[ -f "$CW_REGISTRY" ]] && projs=$(python3 -c "import json; print(len(json.load(open('$CW_REGISTRY'))))" 2>/dev/null || echo 0)
    echo -e "  Accounts:     ${C}$accts${NC}"
    echo -e "  Projects:   ${C}$projs${NC}"

    # Recent sessions
    if [[ -f "$CW_SESSIONS_LOG" ]]; then
        local recent; recent=$(tail -5 "$CW_SESSIONS_LOG" 2>/dev/null)
        if [[ -n "$recent" ]]; then
            echo -e "\n  ${BOLD}Recent sessions:${NC}"
            echo "$recent" | while read -r line; do echo -e "    ${DIM}$line${NC}"; done
        fi
    fi
    echo ""
}

cmd_dashboard() {
    local ws="${CW_WORKSPACE:-$HOME/workspace}"

    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║        ${C}CW v3 — Claude Workspace Orchestrator${NC}${BOLD}               ║${NC}"
    echo -e "${BOLD}║        ${DIM}Multi-project Claude Code orchestrator${NC}${BOLD}             ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"

    # ── Cuentas ──────────────────────────────────────────────────────────
    echo -e "\n${BOLD}Accounts${NC}\n"
    if [[ -d "$CW_ACCOUNTS_DIR" ]]; then
        for dir in "$CW_ACCOUNTS_DIR"/*/; do
            [[ -d "$dir" ]] || continue
            local n; n=$(basename "$dir")
            local auth="${R}✗${NC}"; [[ -f "$dir/.claude.json" ]] && auth="${G}✓${NC}"
            echo -e "  ${C}$n${NC}  [$auth]"
        done
    fi

    # ── Workspace scan ───────────────────────────────────────────────────
    echo -e "\n${BOLD}Workspace${NC}  ${DIM}$ws${NC}\n"

    if [[ ! -d "$ws" ]]; then
        echo -e "  ${Y}No encontrado: $ws${NC}\n"
        return
    fi

    # Show organized groups first (monoku/, meridian/, personal/)
    for group_dir in "$ws"/*/; do
        [[ -d "$group_dir" ]] || continue
        local group; group=$(basename "$group_dir")

        # Check if this is a group folder (has subdirs that are projects)
        local has_subprojects=false
        for sub in "$group_dir"/*/; do
            [[ -d "$sub" ]] && { [[ -d "$sub/.git" ]] || [[ -d "$sub/.claude" ]] || [[ -f "$sub/CLAUDE.md" ]]; } && { has_subprojects=true; break; }
        done

        if $has_subprojects; then
            # This is a group folder — show its contents
            local group_account=""
            # Detect account from first registered project
            for sub in "$group_dir"/*/; do
                [[ -d "$sub" ]] || continue
                local sname; sname=$(basename "$sub")
                local pj; pj=$(_get_project "$sname" 2>/dev/null) && {
                    group_account=$(_get_field "$pj" account "")
                    break
                }
            done
            [[ -n "$group_account" ]] && group_account=" → ${Y}$group_account${NC}"

            echo -e "  ${BOLD}📁 $group/${NC}${group_account}"

            for sub in "$group_dir"/*/; do
                [[ -d "$sub" ]] || continue
                local sname; sname=$(basename "$sub")

                # Skip hidden dirs
                [[ "$sname" == .* ]] && continue

                # Check what it has
                local indicators=""
                local registered=false
                local pj; pj=$(_get_project "$sname" 2>/dev/null) && registered=true

                if $registered; then
                    indicators="${G}●${NC}"
                else
                    indicators="${DIM}○${NC}"
                fi

                [[ -f "$sub/CLAUDE.md" ]] && indicators="$indicators ${G}md${NC}"
                [[ -d "$sub/.claude/agents" ]] && {
                    local ac; ac=$(find "$sub/.claude/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
                    [[ "$ac" -gt 0 ]] && indicators="$indicators ${C}${ac}ag${NC}"
                }
                [[ -d "$sub/.claude/commands" ]] && {
                    local cc; cc=$(find "$sub/.claude/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
                    [[ "$cc" -gt 0 ]] && indicators="$indicators ${C}${cc}cm${NC}"
                }
                if [[ -f "$sub/.claude/settings.json" ]]; then
                    python3 -c "
import json
with open('$sub/.claude/settings.json') as f:
    s = json.load(f)
if s.get('mcpServers') or s.get('mcp_servers'): exit(0)
exit(1)
" 2>/dev/null && indicators="$indicators ${Y}mcp${NC}"
                fi
                [[ -d "$sub/.git" ]] && indicators="$indicators ${DIM}git${NC}"

                echo -e "     $indicators  $sname"
            done
            echo ""

        else
            # This is a standalone item in workspace root
            local sname="$group"

            # Skip known non-projects
            [[ "$sname" == .* ]] && continue
            [[ "$sname" == *env* ]] && continue
            [[ "$sname" == __* ]] && continue

            # Check if it's a project
            local is_project=false
            { [[ -d "$group_dir/.git" ]] || [[ -d "$group_dir/.claude" ]] || [[ -f "$group_dir/CLAUDE.md" ]]; } && is_project=true

            if $is_project; then
                local registered=false
                local pj; pj=$(_get_project "$sname" 2>/dev/null) && registered=true

                if $registered; then
                    local acct; acct=$(_get_field "$pj" account "?")
                    echo -e "  ${G}●${NC}  $sname  ${DIM}→ $acct${NC}"
                else
                    echo -e "  ${Y}○${NC}  $sname  ${DIM}(not registered)${NC}"
                fi
            fi
        fi
    done

    # Show files at root
    local loose_files=()
    for f in "$ws"/*; do
        [[ -f "$f" ]] && loose_files+=("$(basename "$f")")
    done
    if [[ ${#loose_files[@]} -gt 0 ]]; then
        echo -e "  ${DIM}Loose files: ${loose_files[*]}${NC}"
        echo ""
    fi

    # Show non-project dirs
    local other_dirs=()
    for d in "$ws"/*/; do
        [[ -d "$d" ]] || continue
        local dn; dn=$(basename "$d")
        [[ "$dn" == .* ]] && continue

        # Skip if group folder
        local is_group=false
        for sub in "$d"/*/; do
            [[ -d "$sub" ]] && { [[ -d "$sub/.git" ]] || [[ -d "$sub/.claude" ]]; } && { is_group=true; break; }
        done
        $is_group && continue

        # Skip if project
        { [[ -d "$d/.git" ]] || [[ -d "$d/.claude" ]] || [[ -f "$d/CLAUDE.md" ]]; } && continue

        other_dirs+=("$dn")
    done
    if [[ ${#other_dirs[@]} -gt 0 ]]; then
        echo -e "  ${DIM}Other: ${other_dirs[*]}${NC}"
        echo ""
    fi

    # ── Leyenda ──────────────────────────────────────────────────────────
    echo -e "  ${DIM}${G}●${NC}${DIM} registered  ${Y}○${NC}${DIM} not registered  ${G}md${NC}${DIM}=CLAUDE.md  ${C}ag${NC}${DIM}=agents  ${C}cm${NC}${DIM}=commands  ${Y}mcp${NC}${DIM}=MCPs${NC}"

    cmd_spaces

    # ── Quick reference ──────────────────────────────────────────────────
    echo -e "\n${BOLD}Quick${NC}\n"
    echo -e "  ${C}cw work <proy> <task>${NC}             Work on feature/bug (worktree + session)"
    echo -e "  ${C}cw review <proy> <PR>${NC}             Review PR (worktree + session)"
    echo -e "  ${C}cw open <proy>${NC}                    Open project quick (no worktree)"
    echo -e "  ${C}cw spaces${NC}                         Show active spaces"
    echo ""
}

# ════════════════════════════════════════════════════════════════════════════
# GENERATE ASSETS (templates, agents, commands, mcp docs)
# ════════════════════════════════════════════════════════════════════════════

_generate_templates() {
    cat > "$CW_HOME/templates/CLAUDE.fullstack.md" << 'MD'
# Project Instructions

## Overview
<!-- Brief description -->

## Architecture
<!-- Stack, patterns, key decisions -->

## Conventions
- Follow existing code style
- Write tests for new features
- Conventional commits
- Self-review diffs before requesting review

## Development
<!-- Common commands: dev, test, build, deploy -->

## Integrations
When I ask you to create an issue, use Linear.
When I ask you to document something, use Notion.
When I reference a conversation, check Slack.
MD

    cat > "$CW_HOME/templates/CLAUDE.api.md" << 'MD'
# API Project

## Architecture
<!-- API design, database, patterns -->

## Conventions
- RESTful design following OpenAPI spec
- Input validation on all endpoints
- Integration tests for every endpoint
- Database migrations must be reversible
MD

    cat > "$CW_HOME/templates/CLAUDE.knowledge.md" << 'MD'
# Knowledge Base

## Structure
- `/docs` — Documentation
- `/decisions` — ADRs
- `/runbooks` — Operational procedures
- `/research` — Research notes

## Conventions
- Markdown for everything
- Date-prefix: YYYY-MM-DD-title.md
- Sync key docs to Notion
MD

    cat > "$CW_HOME/templates/CLAUDE.infra.md" << 'MD'
# Infrastructure Project

## Safety
- NEVER apply to production without explicit confirmation
- Always plan before apply
- Review diffs carefully
- Use dry-run when available
MD

    cat > "$CW_HOME/templates/CLAUDE.agents.md" << 'MD'
# Agents & Automation

## Structure
- `/agents` — Custom sub-agents
- `/hooks` — Claude Code hooks
- `/skills` — Custom skills
- `/commands` — Slash commands

## Principles
- Single responsibility per agent
- Document input/output contracts
- Test in isolation before composing
MD
}

_generate_agents() {
    cat > "$CW_HOME/agents/code-reviewer.md" << 'MD'
---
name: code-reviewer
description: >
  Invoke for code review tasks: review a PR, audit code quality, check a diff.
  Examples: "review PR #123", "review changes in src/", "audit this code"
model: inherit
tools: Read, Grep, Glob, Bash
---
You are a senior code reviewer. Review thoroughly:

1. **Correctness** — Does it work? Edge cases?
2. **Security** — Vulnerabilities? Auth issues?
3. **Performance** — N+1 queries? Memory leaks?
4. **Tests** — Coverage? Important cases?
5. **Naming & clarity** — Clear code?
6. **Error handling** — Graceful?

For each finding: File:Line, Severity (🔴🟡🔵), Issue, Fix.
End with: APPROVE | REQUEST CHANGES | NEEDS DISCUSSION.
MD

    cat > "$CW_HOME/agents/researcher.md" << 'MD'
---
name: researcher
description: >
  Invoke for research/investigation: explore topics, compare technologies,
  investigate bugs, gather info before decisions.
  Examples: "research auth libraries", "investigate slow API"
model: inherit
tools: Read, Grep, Glob, Bash, WebFetch, WebSearch
---
You are a research specialist.

1. Understand the question clearly
2. Search codebase, docs, and web
3. Organize by relevance
4. Present pros/cons and trade-offs
5. Give clear recommendation with justification

Save findings to `docs/research/YYYY-MM-DD-<topic>.md`.
MD

    cat > "$CW_HOME/agents/doc-writer.md" << 'MD'
---
name: doc-writer
description: >
  Invoke for documentation: write docs, update README, create ADRs,
  write runbooks, sync to Notion.
  Examples: "document the auth flow", "create Notion page for API docs"
model: inherit
tools: Read, Write, Edit, Grep, Glob, Bash
---
You are a technical documentation specialist.

Types: README, ADR, Runbook, API docs, Guides.
When asked for Notion: use MCP tools (search, create-pages, update-page).
Keep docs clear, with examples, date-prefixed.
MD

    cat > "$CW_HOME/agents/planner.md" << 'MD'
---
name: planner
description: >
  Invoke for planning and issue tracking: create/update issues, plan sprints,
  break down features, track progress.
  Examples: "create Linear issue for auth bug", "break down payment feature"
model: inherit
tools: Read, Grep, Glob, Bash
---
You are a project planner.

When creating issues: clear title, description, acceptance criteria,
priority (P0-P3), labels, estimate.
Use Linear MCP to search, create, and update issues.
MD

    cat > "$CW_HOME/agents/comms.md" << 'MD'
---
name: comms
description: >
  Invoke for communication tasks: Slack conversations, draft messages,
  summarize threads, find past discussions.
  Examples: "summarize #dev today", "draft deployment announcement"
model: inherit
tools: Read, Grep, Glob
---
You are a communication specialist.

Search Slack via MCP for context. Summarize threads clearly.
Draft concise, professional messages with bullet points and links.
MD
}

_generate_commands() {
    cat > "$CW_HOME/commands/review-pr.md" << 'MD'
Review the PR thoroughly using the code-reviewer agent.
Check: correctness, security, performance, tests, style.
Provide: APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION.
MD

    cat > "$CW_HOME/commands/research.md" << 'MD'
Research the topic using the researcher agent.
Search codebase, web, Notion, and Linear for context.
Save findings to docs/research/ with date prefix.
MD

    cat > "$CW_HOME/commands/document.md" << 'MD'
Document the topic using the doc-writer agent.
Write clear Markdown docs. If requested, sync to Notion.
MD

    cat > "$CW_HOME/commands/plan-feature.md" << 'MD'
Break down the feature into tasks using the planner agent.
Each task: title, description, acceptance criteria, priority, estimate.
Create issues in Linear if requested.
MD

    cat > "$CW_HOME/commands/status.md" << 'MD'
Generate a status report gathering from:
- Git: recent commits, branches, pending merges
- Linear: open issues, sprint progress, blockers
- GitHub: open PRs, CI status
- Notion: recent doc updates

Compile: completed, in progress, blockers, next steps.
MD
}

_generate_mcp_docs() {
    cat > "$CW_HOME/mcps/README.md" << 'MD'
# MCP Setup

Replace `$ACCT` with your account path (e.g., ~/.cw/accounts/work).

```bash
# GitHub
CLAUDE_CONFIG_DIR=$ACCT claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --scope user

# Linear
CLAUDE_CONFIG_DIR=$ACCT claude mcp add --transport http linear https://mcp.linear.app/mcp --scope user

# Notion
CLAUDE_CONFIG_DIR=$ACCT claude mcp add --transport http notion https://mcp.notion.com/mcp --scope user
```

Verify with `/mcp` inside Claude Code.
MD
}

# ════════════════════════════════════════════════════════════════════════════
# HELP
# ════════════════════════════════════════════════════════════════════════════
cmd_help() {
    cat << EOF

${BOLD}CW — Claude Workspace Manager${NC}

${BOLD}MAIN COMMANDS${NC}
  work <project> <task>               Work on feature/bug (worktree + session)
  work <project> <url>                Work from Linear/Notion/GitHub URL
  review <project> <PR>               Review PR (worktree + session)
  review <project> <url>              Review from GitHub PR URL
  open <project>                      Open project quick (no worktree)
  spaces                              Show active spaces

${BOLD}MANAGE${NC}
  --done                              Close a work/review space
  --list                              List active work/reviews

${BOLD}SETUP${NC}
  init                                Initialize CW
  account add <name>                  Create account profile
  account list                        List accounts
  account remove <name>               Remove account
  project register <path> [opts]      Register project
    --account, -a <account>
    --type, -t <type>                 fullstack | api | knowledge | infra | agents
  project list                        List projects
  project setup-mcps <name>           Configure GitHub/Linear/Notion/Slack
  project setup-agents <name>         Install agents and commands

${BOLD}INFO${NC}
  dashboard                           Full workspace overview
  status                              Quick status
  help                                This help

${BOLD}EXAMPLES${NC}
  cw work daycast fix-auth                          # New task
  cw work daycast NEW-789                           # Task by ticket ID
  cw work daycast https://linear.app/.../NEW-789    # From Linear URL
  cw work daycast fix-auth                          # Resume (auto --continue)
  cw work daycast fix-auth --done                   # Close and cleanup

  cw review triton 123                              # New PR review
  cw review triton https://github.com/.../pull/123  # From GitHub URL
  cw review triton 123 --done                       # Close review

  cw spaces                                         # All active spaces
  cw open daycast                                   # Quick open (no worktree)
  cw dashboard                                      # Full overview

${BOLD}TIPS${NC}
  Cmd + number        Jump to tab
  Cmd + arrow         Next/previous tab
  Cmd + T             New tab
  Cmd + D             Split vertical
  Cmd + Shift + D     Split horizontal

EOF
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        init)       cmd_init "$@" ;;
        account)    cmd_account "$@" ;;
        project)    cmd_project "$@" ;;
        open)       cmd_open "$@" ;;
        review)     cmd_review "$@" ;;
        work)       cmd_work "$@" ;;
        spaces)     cmd_spaces "$@" ;;
        launch)     cmd_launch "$@" ;;
        dashboard)  cmd_dashboard "$@" ;;
        status)     cmd_status "$@" ;;
        help|-h|--help) cmd_help ;;
        *) _err "Unknown: $cmd"; cmd_help; exit 1 ;;
    esac
}

main "$@"
