#!/usr/bin/env bash
# ============================================================================
# CW — Claude Workspace Manager
# Orchestrates projects, accounts, modes, MCPs, agents and sessions
# Multi-project orchestrator for Claude Code.
#
# Usage: cw <command> [options]
# ============================================================================
set -uo pipefail

CW_VERSION="0.1.0"
CW_HOME="${CW_HOME:-$HOME/.cw}"
CW_ACCOUNTS_DIR="$CW_HOME/accounts"
CW_REGISTRY="$CW_HOME/projects.json"
CW_SESSIONS_LOG="$CW_HOME/sessions.log"
CW_CONFIG="$CW_HOME/config.yaml"
CW_ACTIVE="$CW_HOME/active-sessions.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extra flags passed to every `claude` invocation
CW_CLAUDE_FLAGS="${CW_CLAUDE_FLAGS:-}"

# Resolve claude flags from config + env + CLI
_resolve_claude_flags() {
    # CLI flag (--skip-permissions) takes highest priority
    if [[ "${_CW_SKIP_PERMS:-}" == "true" ]]; then
        CW_CLAUDE_FLAGS="--dangerously-skip-permissions $CW_CLAUDE_FLAGS"
        return
    fi
    # Then env var (already set above)
    if [[ -n "$CW_CLAUDE_FLAGS" ]]; then
        return
    fi
    # Then config file
    if [[ -f "$CW_CONFIG" ]]; then
        local val
        val=$(python3 -c "
import re
with open('$CW_CONFIG') as f: text = f.read()
m = re.search(r'^skip_permissions:\s*(true|false)', text, re.M)
print(m.group(1) if m else 'false')
" 2>/dev/null || echo "false")
        if [[ "$val" == "true" ]]; then
            CW_CLAUDE_FLAGS="--dangerously-skip-permissions"
        fi
    fi
}

# CLI output colors
R=$'\033[0;31m' G=$'\033[0;32m' Y=$'\033[1;33m' B=$'\033[0;34m'
M=$'\033[0;35m' C=$'\033[0;36m' BOLD=$'\033[1m' DIM=$'\033[2m' NC=$'\033[0m'

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

_default_account() {
    if [[ -f "$CW_CONFIG" ]]; then
        python3 -c "
import re
with open('$CW_CONFIG') as f: text = f.read()
m = re.search(r'^default_account:\s*(\S+)', text, re.M)
print(m.group(1) if m else 'default')
" 2>/dev/null || echo "default"
    else
        echo "default"
    fi
}

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
        # Ask about skip_permissions
        echo ""
        echo -e "  ${BOLD}Skip permission prompts?${NC}"
        echo -e "  Claude Code normally asks for confirmation before running commands."
        echo -e "  ${Y}--dangerously-skip-permissions${NC} disables this (faster, but less safe)."
        echo ""
        echo -e "  ${C}[1]${NC} No  — keep permission prompts ${DIM}(recommended for teams)${NC}"
        echo -e "  ${C}[2]${NC} Yes — skip prompts ${DIM}(faster, trust Claude fully)${NC}"
        echo ""
        local skip_perms="false"
        read -rp "  Choose [1]: " sp_choice
        [[ "$sp_choice" == "2" ]] && skip_perms="true"
        echo ""

        cat > "$CW_CONFIG" << YAML
# CW v3 Configuration
default_account: monoku
default_mode: code
notifications: true
max_concurrent: 8

# Skip Claude permission prompts (--dangerously-skip-permissions)
# Override per-command with: cw --skip-permissions work ...
# Or per-session with: CW_CLAUDE_FLAGS="--dangerously-skip-permissions" cw work ...
skip_permissions: $skip_perms

# Default tools
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

    # Copy dashboard lib from repo to ~/.cw/lib/dashboard
    local repo_dashboard=""
    # Find dashboard files: first check repo root (git clone), then SCRIPT_DIR
    for candidate in "$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null)/lib/dashboard" "$SCRIPT_DIR/../lib/dashboard" "$SCRIPT_DIR/lib/dashboard"; do
        if [[ -f "$candidate/server.py" ]]; then
            repo_dashboard="$candidate"
            break
        fi
    done
    if [[ -n "$repo_dashboard" ]]; then
        mkdir -p "$CW_HOME/lib/dashboard"
        cp "$repo_dashboard"/{server.py,index.html,activity-hook.py,start.sh} "$CW_HOME/lib/dashboard/" 2>/dev/null
        chmod +x "$CW_HOME/lib/dashboard/start.sh" 2>/dev/null
        _log "Dashboard installed to ${C}$CW_HOME/lib/dashboard${NC}"
    fi

    _log "${G}✓${NC} Initialized at ${C}$CW_HOME${NC}"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "  ${Y}1.${NC} ${C}cw account add work${NC}              — Create account"
    echo -e "  ${Y}2.${NC} ${C}CLAUDE_CONFIG_DIR=~/.cw/accounts/work claude /login${NC}"
    echo -e "                                        — Authenticate"
    echo -e "  ${Y}3.${NC} ${C}cw project register --account work${NC}"
    echo -e "                                        — Register project (from project dir)"
    echo -e "  ${Y}4.${NC} ${C}cw open <project>${NC}                — Open workspace"
    echo ""
    echo -e "  ${DIM}Or use ${C}cw launch work${NC}${DIM} to chat with Claude without a project${NC}"
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

            # Auto-install arcade hooks if setup was done
            if [[ -f "$CW_HOME/.arcade-hook" ]]; then
                local hook_script; hook_script=$(cat "$CW_HOME/.arcade-hook")
                if [[ -f "$hook_script" ]]; then
                    _arcade_install_hooks_for "$dir/settings.json" "$hook_script"
                    _log "  Activity hooks auto-installed."
                fi
            fi

            _log "Account ${C}$name${NC} created."
            echo ""
            echo -e "  ${BOLD}Next steps:${NC}"
            echo -e "  ${Y}1.${NC} Authenticate this account:"
            echo -e "     ${BOLD}CLAUDE_CONFIG_DIR=$dir claude /login${NC}"
            echo ""
            echo -e "  ${Y}2.${NC} Register a project:"
            echo -e "     ${C}cw project register <path> --account $name${NC}"
            echo -e "     ${DIM}(or cd into a repo and run: cw project register --account $name)${NC}"
            echo ""
            echo -e "  ${DIM}Tip: Use ${C}cw launch $name${NC}${DIM} to open Claude with this account without registering a project${NC}"
            echo ""
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
            [[ "$c" =~ ^[yY]$ ]] && rm -rf "$CW_ACCOUNTS_DIR/$name" && _log "Removed."
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
        remove|rm)      _project_remove "$@" ;;
        list|ls)        _project_list ;;
        scaffold)       _project_scaffold "$@" ;;
        setup-mcps)     _project_setup_mcps "$@" ;;
        setup-agents)   _project_setup_agents "$@" ;;
        info)           _project_info "$@" ;;
        *) _err "Subcommands: register | remove | list | scaffold | setup-mcps | setup-agents | info" ;;
    esac
}

_project_register() {
    local path="" alias_name=""
    local account; account=$(_default_account)
    local ptype="fullstack"

    # Parse all args — path is the first positional (optional, defaults to cwd)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account|-a) account="$2"; shift 2 ;;
            --type|-t)    ptype="$2"; shift 2 ;;
            --alias)      alias_name="$2"; shift 2 ;;
            -*)           shift ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"
                fi
                shift ;;
        esac
    done

    # Default to current directory if no path given
    if [[ -z "$path" ]]; then
        path="$(pwd)"
        _log "Using current directory: ${C}$path${NC}"
    fi

    path=$(realpath "$path" 2>/dev/null || echo "$path")
    [[ -d "$path" ]] || { _err "Directory does not exist: $path"; return 1; }

    local name="${alias_name:-$(basename "$path")}"

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

_project_remove() {
    local name="${1:?Usage: cw project remove <name>}"
    local pj; pj=$(_get_project "$name") || { _err "'$name' not registered."; return 1; }
    echo -e "  Remove project ${C}$name${NC} from registry? (files won't be deleted)"
    read -rp "  [y/N] " c
    [[ "$c" =~ ^[yY]$ ]] || { echo "  Cancelled."; return; }
    python3 -c "
import json
f = '$CW_REGISTRY'
with open(f) as fh: reg = json.load(fh)
reg.pop('$name', None)
with open(f, 'w') as fh: json.dump(reg, fh, indent=2)
"
    _log "Project ${C}$name${NC} removed from registry."
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
    local account; account=$(_get_field "$pj" account "$(_default_account)")
    local acct_dir="$CW_ACCOUNTS_DIR/$account"

    # Check which MCPs are already installed
    local existing=""
    existing=$(CLAUDE_CONFIG_DIR="$acct_dir" claude mcp list 2>/dev/null || true)

    echo -e "\n${BOLD}Configure MCPs for ${C}$name${NC} (account: ${Y}$account${NC})\n"

    # Show status for each MCP
    local gh_status="${DIM}not installed${NC}" li_status="${DIM}not installed${NC}"
    local no_status="${DIM}not installed${NC}" sl_status="${DIM}not installed${NC}"
    [[ "$existing" == *"github"* ]] && gh_status="${G}installed${NC}"
    [[ "$existing" == *"linear"* ]] && li_status="${G}installed${NC}"
    [[ "$existing" == *"notion"* ]] && no_status="${G}installed${NC}"
    [[ "$existing" == *"slack"* ]]  && sl_status="${G}installed${NC}"

    echo -e "  ${C}[1]${NC} GitHub     — PRs, issues, code search       [$gh_status]"
    echo -e "  ${C}[2]${NC} Linear     — Issues, projects, sprints      [$li_status]"
    echo -e "  ${C}[3]${NC} Notion     — Docs, wikis, knowledge base    [$no_status]"
    echo -e "  ${C}[4]${NC} Slack      — Messages, channels, threads    [$sl_status]"
    echo -e "  ${C}[5]${NC} All"
    echo -e "  ${C}[0]${NC} Cancel\n"
    read -rp "Select (e.g. 1,2,3): " choices
    [[ "$choices" == "0" ]] && return
    [[ "$choices" == "5" ]] && choices="1,2,3,4"

    echo ""
    local installed=0

    if [[ "$choices" == *"1"* ]]; then
        if [[ "$existing" == *"github"* ]]; then
            _dim "  GitHub: already installed, skipping"
        else
            _log "Installing GitHub MCP..."
            if CLAUDE_CONFIG_DIR="$acct_dir" claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --scope user 2>/dev/null; then
                echo -e "  ${G}✓${NC} GitHub MCP added"
                installed=$((installed+1))
            else
                _warn "GitHub MCP failed. Run manually:"
                echo -e "    ${BOLD}CLAUDE_CONFIG_DIR=$acct_dir claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --scope user${NC}"
            fi
        fi
    fi

    if [[ "$choices" == *"2"* ]]; then
        if [[ "$existing" == *"linear"* ]]; then
            _dim "  Linear: already installed, skipping"
        else
            _log "Installing Linear MCP..."
            if CLAUDE_CONFIG_DIR="$acct_dir" claude mcp add --transport http linear https://mcp.linear.app/mcp --scope user 2>/dev/null; then
                echo -e "  ${G}✓${NC} Linear MCP added"
                installed=$((installed+1))
            else
                _warn "Linear MCP failed. Run manually:"
                echo -e "    ${BOLD}CLAUDE_CONFIG_DIR=$acct_dir claude mcp add --transport http linear https://mcp.linear.app/mcp --scope user${NC}"
            fi
        fi
    fi

    if [[ "$choices" == *"3"* ]]; then
        if [[ "$existing" == *"notion"* ]]; then
            _dim "  Notion: already installed, skipping"
        else
            _log "Installing Notion MCP..."
            if CLAUDE_CONFIG_DIR="$acct_dir" claude mcp add --transport http notion https://mcp.notion.com/mcp --scope user 2>/dev/null; then
                echo -e "  ${G}✓${NC} Notion MCP added"
                installed=$((installed+1))
            else
                _warn "Notion MCP failed. Run manually:"
                echo -e "    ${BOLD}CLAUDE_CONFIG_DIR=$acct_dir claude mcp add --transport http notion https://mcp.notion.com/mcp --scope user${NC}"
            fi
        fi
    fi

    if [[ "$choices" == *"4"* ]]; then
        echo -e "\n  ${Y}Slack${NC}: No official MCP yet. Options:"
        echo -e "    • ${C}https://mcp.composio.dev${NC} — Composio connector"
        echo -e "    • Custom MCP via stdio transport"
    fi

    echo ""
    if [[ $installed -gt 0 ]]; then
        _log "${G}✓${NC} $installed MCP(s) installed for account ${C}$account${NC}"
        echo -e "  Each MCP will prompt for OAuth on first use inside Claude Code."
        echo -e "  Verify with ${C}/mcp${NC} inside a Claude session.\n"
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

    account="${account:-$(_get_field "$pj" account "$(_default_account)")}"
    local acct_dir="$CW_ACCOUNTS_DIR/$account"
    _log "Opening ${C}$name${NC}  account=${M}$account${NC}"

    cd "$path"
    _set_tab_title "$name"
    CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OPEN $name account=$account" >> "$CW_SESSIONS_LOG"
}




# ════════════════════════════════════════════════════════════════════════════
# LAUNCH — Quick Claude with account
# ════════════════════════════════════════════════════════════════════════════
cmd_launch() {
    local account="${1:-$(_default_account)}"; shift || true
    local dir="$CW_ACCOUNTS_DIR/$account"
    [[ -d "$dir" ]] || { _err "Account '$account' does not exist."; return 1; }
    _log "Launching Claude (${C}$account${NC})..."
    CLAUDE_CONFIG_DIR="$dir" claude "$@"
}

# ════════════════════════════════════════════════════════════════════════════
# REVIEW — PR review with persistent session (no worktree)
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
    local account; account=$(_get_field "$pj" account "$(_default_account)")
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
    local notes_file="$session_dir/REVIEW_NOTES.md"

    # ── Done: close review session ───────────────────────────────────────
    if $done_flag; then
        _log "Closing review: ${C}$name${NC} PR #${Y}$pr${NC}"
        if [[ -f "$session_dir/session.json" ]]; then
            python3 -c "
import json
from datetime import datetime, timezone
with open('$session_dir/session.json') as f: meta = json.load(f)
meta['status'] = 'done'
meta['closed'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open('$session_dir/session.json', 'w') as f: json.dump(meta, f, indent=2)
"
        fi
        _log "${G}Review PR #$pr closed${NC}"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) DONE $name review=pr-$pr" >> "$CW_SESSIONS_LOG"
        return
    fi

    # ── Create or resume review ──────────────────────────────────────────
    mkdir -p "$session_dir"

    local is_new=true
    [[ -f "$session_meta" ]] && is_new=false

    # If session exists but is done, reset it for a fresh start
    if ! $is_new; then
        local session_status
        session_status=$(python3 -c "import json; print(json.load(open('$session_meta')).get('status',''))" 2>/dev/null)
        if [[ "$session_status" == "done" ]]; then
            _log "Previous review for PR #${Y}$pr${NC} was closed — starting fresh"
            rm -f "$session_meta"
            is_new=true
        fi
    fi

    if $is_new; then
        _log "New review: ${C}$name${NC} PR #${Y}$pr${NC}"

        # Save session metadata
        python3 -c "
import json
from datetime import datetime, timezone
meta = {
    'project': '$name',
    'pr': '$pr',
    'type': 'review',
    'account': '$account',
    'notes': '$notes_file',
    'status': 'active',
    'created': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'last_opened': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
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

    else
        # Existing review - update metadata
        _log "Resuming review: ${C}$name${NC} PR #${Y}$pr${NC}"
        python3 -c "
import json
from datetime import datetime, timezone
with open('$session_meta') as f: meta = json.load(f)
meta['last_opened'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
meta['opens'] = meta.get('opens', 0) + 1
with open('$session_meta', 'w') as f:
    json.dump(meta, f, indent=2)
"
    fi

    # ── Run Claude ────────────────────────────────────────────────────
    cd "$path"
    _set_tab_title "PR#$pr - $name"
    if ! $is_new; then
        # Re-review: check if previously requested changes were addressed
        local pr_fetch_instructions=""
        if command -v gh &>/dev/null; then
            pr_fetch_instructions="Fetch the latest state of the PR:
   \`gh pr view $pr --json reviews,comments\`
   \`gh pr diff $pr\`
   \`gh api repos/{owner}/{repo}/pulls/$pr/reviews\`
   \`gh api repos/{owner}/{repo}/pulls/$pr/comments\`"
        else
            pr_fetch_instructions="Fetch the latest review comments and requested changes using the GitHub MCP tools (get_pull_request_reviews, get_pull_request_comments, get_pull_request). If no GitHub MCP is available, check REVIEW_NOTES.md for your previous findings."
        fi

        local recheck_prompt="This is a follow-up review of PR #$pr for project $name.

1. Read $notes_file to recall your previous findings.
2. $pr_fetch_instructions
3. For each previously requested change, verify if it was addressed in the latest diff:
   - Compare the current diff against your previous findings
   - Check the relevant files for each requested change
4. Report:
   - Resolved: which requested changes were fixed
   - Still pending: which ones are not addressed yet
   - New issues: anything new introduced in the latest commits
5. Update $notes_file with the follow-up findings.

IMPORTANT — DO NOT post comments to GitHub yet. Present your findings to me first:
- Show a summary: what was resolved, what's still pending, any new issues
- Classify new issues as: critical | major | minor | nit
- Show your updated verdict: APPROVE | REQUEST CHANGES | NEEDS DISCUSSION
- Then ASK me: 'Which levels should I post? (e.g. critical+major / all / none / edit)'

Only after I confirm, post as inline review comments on specific lines.
IMPORTANT: When posting comments to GitHub, DO NOT include severity labels (critical/major/minor/nit) in the comment text. Write each comment as a natural, helpful review comment — just the issue and suggested fix, no tags or prefixes.
Use: \`gh api repos/{owner}/{repo}/pulls/$pr/reviews -f event=<APPROVE|REQUEST_CHANGES|COMMENT> -f body='<summary>' -f comments='[{\"path\":\"<file>\",\"line\":<line>,\"body\":\"<comment>\"}]'\`

If I say 'none', do not post. If I say 'edit', let me modify before posting."

        local prompt_file="$session_dir/recheck_prompt.txt"
        printf '%s' "$recheck_prompt" > "$prompt_file"
        CW_PROJECT="$name" CW_TASK="pr-$pr" CW_TASK_TYPE="review" CW_ACCOUNT="$account" \
        CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS --continue "$(cat "$prompt_file")"
    else
        # Build review prompt: project skill > global skill > default
        # Search order:
        #   1. .claude/skills/review-pr/SKILL.md  (project skill)
        #   2. .claude/skills/code-review*/SKILL.md (project skill, alt name)
        #   3. ~/.claude/skills/code-reviewer/SKILL.md (user global skill)
        #   4. ~/.cw/commands/review-pr.md (CW global command)
        #   5. built-in default
        local review_skill="" skill_source=""
        local _skill_file=""
        # 1. Project skills (.claude/skills/)
        for _name in code-review review-pr review code-reviewer; do
            if [[ -f "$path/.claude/skills/$_name/SKILL.md" ]]; then
                _skill_file="$path/.claude/skills/$_name/SKILL.md"
                skill_source="project skill ($_name)"
                break
            fi
        done
        # 2. User global skills (~/.claude/skills/)
        if [[ -z "$_skill_file" ]]; then
            for _name in code-review code-reviewer review-pr review; do
                if [[ -f "$HOME/.claude/skills/$_name/SKILL.md" ]]; then
                    _skill_file="$HOME/.claude/skills/$_name/SKILL.md"
                    skill_source="global skill ($_name)"
                    break
                fi
            done
        fi
        # 3. CW commands fallback (~/.cw/commands/)
        if [[ -z "$_skill_file" ]] && [[ -f "$CW_HOME/commands/review-pr.md" ]]; then
            _skill_file="$CW_HOME/commands/review-pr.md"
            skill_source="CW command"
        fi
        [[ -n "$_skill_file" ]] && review_skill=$(cat "$_skill_file")
        [[ -n "$skill_source" ]] && _dim "  Using $skill_source"

        # Detect gh CLI for PR details
        local pr_detail_instructions=""
        if command -v gh &>/dev/null; then
            pr_detail_instructions="Fetch PR details: \`gh pr view $pr --json title,body,files,additions,deletions,commits\`
   And the diff: \`gh pr diff $pr\`"
        else
            pr_detail_instructions="Fetch PR details using the GitHub MCP tools (get_pull_request, list_pull_request_files). If no GitHub MCP is available, use git commands only."
        fi

        local review_prompt="Review PR #$pr for project $name.

Read $notes_file first for context.

1. $pr_detail_instructions
2. Review every changed file thoroughly."

        if [[ -n "$review_skill" ]]; then
            review_prompt="$review_prompt

Use these review instructions:
$review_skill"
        else
            review_prompt="$review_prompt

Review for: correctness, security, performance, tests, naming, error handling.
For each finding: File:Line, Severity, Issue, Suggested fix."
        fi

        review_prompt="$review_prompt

3. Fill in $notes_file with your findings.

IMPORTANT — DO NOT post comments to GitHub yet. Present your findings to me first:
- Classify each finding as: critical | major | minor | nit
- Group findings by severity in the summary table (file, line, severity, issue)
- Show counts per severity level
- Show your overall verdict: APPROVE | REQUEST CHANGES | NEEDS DISCUSSION
- Then ASK me: 'Which levels should I post? (e.g. critical+major / all / none / edit)'

Only after I confirm, post the review using inline comments on specific lines.
IMPORTANT: When posting comments to GitHub, DO NOT include severity labels (critical/major/minor/nit) in the comment text. Write each comment as a natural, helpful review comment — just the issue and suggested fix, no tags or prefixes.
Use: \`gh api repos/{owner}/{repo}/pulls/$pr/reviews -f event=<APPROVE|REQUEST_CHANGES|COMMENT> -f body='<summary>' -f comments='[{\"path\":\"<file>\",\"line\":<line>,\"body\":\"<comment>\"}]'\`

If I say 'none', do not post. If I say 'edit', let me modify the findings before posting."

        local prompt_file="$session_dir/init_prompt.txt"
        printf '%s' "$review_prompt" > "$prompt_file"
        CW_PROJECT="$name" CW_TASK="pr-$pr" CW_TASK_TYPE="review" CW_ACCOUNT="$account" \
        CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS "$(cat "$prompt_file")"
    fi

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) REVIEW $name pr=$pr account=$account" >> "$CW_SESSIONS_LOG"
}

# ════════════════════════════════════════════════════════════════════════════
# WORK — Feature/bugfix with worktree + persistent session
# ════════════════════════════════════════════════════════════════════════════
cmd_work() {
    local name="" task="" done_flag=false list_flag=false team_flag=false team_prompt="" base_branch=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task|-t)   task="$2"; shift 2 ;;
            --done)      done_flag=true; shift ;;
            --list)      list_flag=true; shift ;;
            --base|-b)   base_branch="$2"; shift 2 ;;
            --team)      team_flag=true; shift
                         # Capture optional team prompt (rest of args in quotes)
                         if [[ $# -gt 0 && "$1" != -* ]]; then
                             team_prompt="$1"; shift
                         fi ;;
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
    local account; account=$(_get_field "$pj" account "$(_default_account)")
    local acct_dir="$CW_ACCOUNTS_DIR/$account"

    local session_dir="$CW_HOME/sessions/$name/task-$task"
    local session_meta="$session_dir/session.json"
    local wt_dir="$path/.tasks/$task"
    local notes_file="$session_dir/TASK_NOTES.md"

    # Resolve base branch: --base flag > detect default branch from remote
    if [[ -z "$base_branch" ]]; then
        base_branch=$(cd "$path" && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/||') || true
        [[ -z "$base_branch" ]] && base_branch="origin/main"
    else
        # Ensure it has origin/ prefix if user passed just a branch name
        [[ "$base_branch" != origin/* ]] && base_branch="origin/$base_branch"
    fi

    # ── Done ────────────────────────────────────────────────────────────
    if $done_flag; then
        _space_done "$name" "$task" "task" "$path" "$wt_dir" "$session_dir"
        return
    fi

    # ── Create or resume ─────────────────────────────────────────────────
    mkdir -p "$session_dir"

    local is_new=true
    [[ -f "$session_meta" ]] && is_new=false

    # If session exists but is done, reset it for a fresh start
    if ! $is_new; then
        local session_status
        session_status=$(python3 -c "import json; print(json.load(open('$session_meta')).get('status',''))" 2>/dev/null)
        if [[ "$session_status" == "done" ]]; then
            _log "Previous session for ${Y}$task${NC} was closed — starting fresh"
            rm -f "$session_meta"
            is_new=true
        fi
    fi

    if $is_new; then
        _log "New task: ${C}$name${NC} task=${Y}$task${NC}"

        # Build initial prompt for Claude based on source
        local init_prompt=""
        if [[ "$task_source" == "linear" ]]; then
            init_prompt="Fetch Linear issue $task using the Linear MCP (get_issue tool). Get the git branch name from the issue. Also fetch the issue comments (list_comments tool) to check for discussion, decisions, or additional context. Then:
1. Run: git fetch origin
2. If the branch already exists locally, delete it: git branch -D <branch_name> (ignore errors)
3. Create a worktree from $base_branch: git worktree add .tasks/$task -b <branch_name> $base_branch
4. Symlink notes: ln -sf $notes_file .tasks/$task/TASK_NOTES.md
5. Symlink .env if it exists in repo root: [ -f .env ] && ln -sf \"\$(pwd)/.env\" .tasks/$task/.env
6. Fill in the TASK_NOTES.md Context section with the issue details (title, description, acceptance criteria, priority). If there are comments, include a summary of relevant decisions or clarifications.
7. Then start working from the .tasks/$task/ directory.

Source URL: $task_url"
        elif [[ "$task_source" == "notion" ]]; then
            init_prompt="Fetch this Notion page using the Notion MCP: $task_url
Then:
1. Run: git fetch origin
2. If branch task/$task exists locally, delete it: git branch -D task/$task (ignore errors)
3. Create a worktree from $base_branch: git worktree add .tasks/$task -b task/$task $base_branch
4. Symlink notes: ln -sf $notes_file .tasks/$task/TASK_NOTES.md
5. Symlink .env if it exists in repo root: [ -f .env ] && ln -sf \"\$(pwd)/.env\" .tasks/$task/.env
6. Fill in the TASK_NOTES.md Context section with the page content.
7. Then start working from the .tasks/$task/ directory."
        elif [[ "$task_source" == "github" ]]; then
            init_prompt="Fetch this GitHub issue/PR using the GitHub MCP: $task_url
Get the branch name if it is a PR. Then:
1. Run: git fetch origin
2. If the branch already exists locally, delete it: git branch -D <branch_name> (ignore errors)
3. Create a worktree from $base_branch: git worktree add .tasks/$task -b <branch_name_or_task/$task> $base_branch
4. Symlink notes: ln -sf $notes_file .tasks/$task/TASK_NOTES.md
5. Symlink .env if it exists in repo root: [ -f .env ] && ln -sf \"\$(pwd)/.env\" .tasks/$task/.env
6. Fill in the TASK_NOTES.md Context section.
7. Then start working from the .tasks/$task/ directory."
        else
            # No URL — just a branch/task name
            init_prompt="Set up the workspace:
1. Run: git fetch origin
2. If branch $task exists locally, delete it: git branch -D $task (ignore errors)
3. Create a worktree from $base_branch: git worktree add .tasks/$task -b $task $base_branch
4. Symlink notes: ln -sf $notes_file .tasks/$task/TASK_NOTES.md
5. Symlink .env if it exists in repo root: [ -f .env ] && ln -sf \"\$(pwd)/.env\" .tasks/$task/.env
6. If there is a TASK_NOTES.md in .tasks/$task/, read it for context.
7. Then start working from the .tasks/$task/ directory."
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

        # Exclude .tasks from git (but DON'T pre-create the task dir — worktree needs it empty)
        mkdir -p "$path/.tasks"
        local proj_git_dir
        proj_git_dir=$(cd "$path" && git rev-parse --git-dir 2>/dev/null) || true
        if [[ -n "$proj_git_dir" ]]; then
            local proj_exclude="$proj_git_dir/info/exclude"
            mkdir -p "$(dirname "$proj_exclude")" 2>/dev/null || true
            grep -q ".tasks" "$proj_exclude" 2>/dev/null || echo ".tasks" >> "$proj_exclude"
            grep -q "TASK_NOTES.md" "$proj_exclude" 2>/dev/null || echo "TASK_NOTES.md" >> "$proj_exclude"
        fi

        # Save session
        python3 -c "
import json
from datetime import datetime, timezone
meta = {
    'project': '$name', 'task': '$task', 'type': 'task',
    'account': '$account',
    'worktree': '$wt_dir', 'notes': '$notes_file',
    'source': '$task_source', 'source_url': '$task_url',
    'status': 'active',
    'created': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'last_opened': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'opens': 1
}
with open('$session_meta', 'w') as f: json.dump(meta, f, indent=2)
"

    else
        _log "Resuming task: ${C}$name${NC} task=${Y}$task${NC}"
        python3 -c "
import json
from datetime import datetime, timezone
with open('$session_meta') as f: meta = json.load(f)
meta['last_opened'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
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

    export CW_PROJECT="$name" CW_TASK="$task" CW_TASK_TYPE="task" CW_ACCOUNT="$account"

    # ── Agent teams ────────────────────────────────────────────────────
    local team_env=""
    if $team_flag; then
        team_env="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
        _log "Agent teams ${G}enabled${NC}"
    fi

    if $is_new && [[ -n "$init_prompt" ]]; then
        # Append team instructions to init prompt if --team
        if $team_flag && [[ -n "$team_prompt" ]]; then
            init_prompt="$init_prompt

After setting up the workspace, create an agent team for this task:
$team_prompt"
        elif $team_flag; then
            init_prompt="$init_prompt

After setting up the workspace, analyze the task scope and create an agent team to work on it in parallel. Split the work into logical domains (e.g. backend, frontend, tests) and spawn teammates accordingly."
        fi

        local prompt_file="$session_dir/init_prompt.txt"
        printf '%s' "$init_prompt" > "$prompt_file"
        env $team_env CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS "$(cat "$prompt_file")"
    elif ! $is_new; then
        # Try to continue last conversation; if none found, start fresh
        env $team_env CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS --continue \
            || env $team_env CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS
    else
        if $team_flag && [[ -n "$team_prompt" ]]; then
            env $team_env CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS "Create an agent team for this task: $team_prompt"
        elif $team_flag; then
            env $team_env CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS
        else
            CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS
        fi
    fi

    unset CW_PROJECT CW_TASK CW_TASK_TYPE CW_ACCOUNT
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) WORK $name task=$task account=$account" >> "$CW_SESSIONS_LOG"
}

# ════════════════════════════════════════════════════════════════════════════
# SPACES — Show all active spaces
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
from datetime import datetime, timezone
with open('$session_dir/session.json') as f: meta = json.load(f)
meta['status'] = 'done'
meta['closed'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
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

cmd_arcade() {
    local setup_flag=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --setup) setup_flag=true; shift ;;
            *) shift ;;
        esac
    done

    local dashboard_dir="$SCRIPT_DIR/lib/dashboard"
    if [[ ! -f "$dashboard_dir/server.py" ]]; then
        dashboard_dir="$CW_HOME/lib/dashboard"
    fi
    if [[ ! -f "$dashboard_dir/server.py" ]]; then
        _err "Dashboard not found. Run: cw init"
        return 1
    fi

    if $setup_flag; then
        _arcade_setup_hooks "$dashboard_dir"
        return
    fi

    python3 "$dashboard_dir/server.py"
}

_arcade_install_hooks_for() {
    local settings="$1" hook_script="$2"
    # Also install CW hooks (review-autoclose, etc.)
    local cw_hooks_dir
    cw_hooks_dir="${CW_HOME:-$HOME/.cw}/hooks/scripts"
    python3 - "$settings" "$hook_script" "$cw_hooks_dir" << 'PYEOF'
import json, sys, os

settings_path = sys.argv[1]
hook_script = sys.argv[2]
cw_hooks_dir = sys.argv[3]

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

hook_cmd = f"python3 {hook_script}"
hook_handler = {"type": "command", "command": hook_cmd, "timeout": 3000}

# Events that support matcher vs those that don't
matcher_events = ["PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop"]
no_matcher_events = ["Stop", "SessionStart", "SessionEnd", "TeammateIdle", "TaskCompleted"]

# Disable Co-Authored-By in commits and PRs
if "attribution" not in settings:
    settings["attribution"] = {"commit": "", "pr": ""}

if "hooks" not in settings:
    settings["hooks"] = {}

for event in matcher_events + no_matcher_events:
    entry = {"hooks": [hook_handler]}
    if event in matcher_events:
        entry["matcher"] = ""

    if event not in settings["hooks"]:
        settings["hooks"][event] = []
    existing = settings["hooks"][event]
    already = any(
        hook_cmd in h.get("command", "")
        or any(hook_cmd in sub.get("command", "") for sub in h.get("hooks", []) if isinstance(sub, dict))
        for h in existing if isinstance(h, dict)
    )
    if not already:
        settings["hooks"][event].append(entry)

# ── CW hooks: review-autoclose (PostToolUse on Bash) ──
autoclose_script = os.path.join(cw_hooks_dir, "review-autoclose.py")
if os.path.isfile(autoclose_script):
    autoclose_cmd = f"python3 {autoclose_script}"
    autoclose_handler = {"type": "command", "command": autoclose_cmd, "timeout": 5000}
    autoclose_entry = {"matcher": "Bash", "hooks": [autoclose_handler]}

    if "PostToolUse" not in settings["hooks"]:
        settings["hooks"]["PostToolUse"] = []
    existing_post = settings["hooks"]["PostToolUse"]
    already_installed = any(
        autoclose_cmd in h.get("command", "")
        or any(autoclose_cmd in sub.get("command", "") for sub in h.get("hooks", []) if isinstance(sub, dict))
        for h in existing_post if isinstance(h, dict)
    )
    if not already_installed:
        settings["hooks"]["PostToolUse"].append(autoclose_entry)

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF
}

_arcade_setup_hooks() {
    local dashboard_dir="$1"
    local hook_script="$dashboard_dir/activity-hook.py"

    if [[ ! -f "$hook_script" ]]; then
        _err "activity-hook.py not found at $dashboard_dir"
        return 1
    fi

    _log "Setting up live activity hooks..."

    for acct_dir in "$CW_ACCOUNTS_DIR"/*/; do
        [[ -d "$acct_dir" ]] || continue
        local acct; acct=$(basename "$acct_dir")
        _arcade_install_hooks_for "$acct_dir/settings.json" "$hook_script"
        _log "  ${C}$acct${NC} — hooks installed"
    done

    # Save marker so new accounts auto-install hooks
    echo "$hook_script" > "$CW_HOME/.arcade-hook"

    _log "${G}Done!${NC} Activity hooks are now active for all accounts."
    _log "New accounts will auto-install hooks."
    _log "Run ${C}cw arcade${NC} to see live activity."
}

cmd_dashboard() {
    local ws="${CW_WORKSPACE:-$HOME/workspace}"

    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║        ${C}CW v3 — Claude Workspace Orchestrator${NC}${BOLD}               ║${NC}"
    echo -e "${BOLD}║        ${DIM}Multi-project Claude Code orchestrator${NC}${BOLD}             ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"

    # ── Accounts ─────────────────────────────────────────────────────────
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
        echo -e "  ${Y}Workspace directory not found: $ws${NC}"
        echo ""
        if [[ -z "${CW_WORKSPACE:-}" ]]; then
            echo -e "  ${BOLD}Set your workspace folder:${NC}"
            read -rp "  Path to your projects folder (e.g. ~/Documents): " ws_input
            if [[ -n "$ws_input" ]]; then
                # Expand ~ manually
                ws_input="${ws_input/#\~/$HOME}"
                if [[ -d "$ws_input" ]]; then
                    ws="$ws_input"
                    echo ""
                    echo -e "  ${G}✓${NC} Using: ${C}$ws${NC}"
                    echo -e "  ${DIM}To make this permanent, add to your shell rc:${NC}"
                    echo -e "  ${C}echo 'export CW_WORKSPACE=\"$ws\"' >> ~/.zshrc && source ~/.zshrc${NC}"
                    echo ""
                else
                    _err "Directory does not exist: $ws_input"
                    return
                fi
            else
                return
            fi
        else
            echo -e "  ${DIM}Check your CW_WORKSPACE env variable.${NC}\n"
            return
        fi
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

    # ── Legend ────────────────────────────────────────────────────────────
    echo -e "  ${DIM}${G}●${NC}${DIM} registered  ${Y}○${NC}${DIM} not registered  ${G}md${NC}${DIM}=CLAUDE.md  ${C}ag${NC}${DIM}=agents  ${C}cm${NC}${DIM}=commands  ${Y}mcp${NC}${DIM}=MCPs${NC}"

    cmd_spaces

    # ── Quick reference ──────────────────────────────────────────────────
    echo -e "\n${BOLD}Quick${NC}\n"
    echo -e "  ${C}cw work <proy> <task>${NC}             Work on feature/bug (worktree + session)"
    echo -e "  ${C}cw review <proy> <PR>${NC}             Review PR (persistent session)"
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
# GSD — Get Shit Done workflow integration
# ════════════════════════════════════════════════════════════════════════════
cmd_gsd() {
    local subcmd="${1:-init}"; shift || true
    case "$subcmd" in
        init)  _gsd_init "$@" ;;
        sync)  _gsd_sync ;;
        *)     _err "Usage: cw gsd [init|sync]" ;;
    esac
}

_gsd_init() {
    local target="${1:-$(pwd)}"
    [[ -d "$target" ]] || { _err "Directory not found: $target"; return 1; }
    _log "Initializing GSD in: ${C}$target${NC}"
    if ! command -v npx &>/dev/null; then
        _err "npx not found. Install Node.js first."
        return 1
    fi
    if [[ -f "$target/STATE.md" ]]; then
        _warn "GSD already initialized (STATE.md exists). Skipping."
        return 0
    fi
    (cd "$target" && npx get-shit-done-cc@latest --claude --local)
    _log "GSD initialized in ${C}$target${NC}"
}

_gsd_sync() {
    _log "Syncing GSD to all active CW worktrees..."
    local sessions_dir="$CW_HOME/sessions"
    [[ -d "$sessions_dir" ]] || { _warn "No sessions directory found."; return 0; }
    local count=0
    for proj_dir in "$sessions_dir"/*/; do
        for space_dir in "$proj_dir"/*/; do
            local meta="$space_dir/session.json"
            [[ -f "$meta" ]] || continue
            local status worktree
            status=$(python3 -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null)
            [[ "$status" != "active" ]] && continue
            worktree=$(python3 -c "import json; print(json.load(open('$meta')).get('worktree',''))" 2>/dev/null)
            [[ -d "$worktree" ]] || continue
            if [[ -f "$worktree/STATE.md" ]]; then
                _log "GSD already present: ${DIM}$worktree${NC}"
            else
                _log "Initializing GSD: ${C}$worktree${NC}"
                _gsd_init "$worktree"
                (( count++ )) || true
            fi
        done
    done
    _log "GSD sync complete. Initialized in ${Y}$count${NC} worktree(s)."
}

# ════════════════════════════════════════════════════════════════════════════
# CREATE — Bootstrap a new project from a description
# ════════════════════════════════════════════════════════════════════════════
cmd_create() {
    local description="" account="" team_flag=false team_prompt="" proj_name="" base_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account|-a)  account="$2"; shift 2 ;;
            --name|-n)     proj_name="$2"; shift 2 ;;
            --dir|-d)      base_dir="$2"; shift 2 ;;
            --team)        team_flag=true; shift
                           if [[ $# -gt 0 && "$1" != -* && "$1" != http* ]]; then
                               team_prompt="$1"; shift
                           fi ;;
            -*)            shift ;;
            *)             description="$1"; shift ;;
        esac
    done

    [[ -z "$description" ]] && { _err "Usage: cw create \"<description or URL>\" [--account X] [--team]"; return 1; }

    # ── Parse URL source ──────────────────────────────────────────────
    local source="" source_url=""
    if [[ "$description" == http* ]]; then
        source_url="$description"
        if [[ "$description" == *linear.app* ]]; then
            source="linear"
        elif [[ "$description" == *notion.so* ]] || [[ "$description" == *notion.site* ]]; then
            source="notion"
        elif [[ "$description" == *github.com* ]]; then
            source="github"
        else
            source="url"
        fi
    fi

    # ── Pick account ──────────────────────────────────────────────────
    if [[ -z "$account" ]]; then
        local accounts=()
        for dir in "$CW_ACCOUNTS_DIR"/*/; do
            [[ -d "$dir" ]] || continue
            accounts+=("$(basename "$dir")")
        done
        if [[ ${#accounts[@]} -eq 0 ]]; then
            _err "No accounts. Run: cw account add <name>"
            return 1
        elif [[ ${#accounts[@]} -eq 1 ]]; then
            account="${accounts[0]}"
        else
            echo -e "\n${BOLD}Select account:${NC}"
            local i=1
            for a in "${accounts[@]}"; do
                echo -e "  ${C}$i${NC}) $a"
                ((i++))
            done
            echo ""
            read -rp "Account [1]: " choice
            choice=${choice:-1}
            account="${accounts[$((choice - 1))]}"
        fi
    fi
    local acct_dir="$CW_ACCOUNTS_DIR/$account"
    [[ -d "$acct_dir" ]] || { _err "Account '$account' not found."; return 1; }

    # ── Project name ──────────────────────────────────────────────────
    if [[ -z "$proj_name" ]]; then
        if [[ -n "$source_url" ]]; then
            proj_name=$(echo "$source_url" | sed 's|.*/||' | sed 's|-[a-f0-9]*$||' | head -c 40)
        else
            # Ask Claude-style: derive from description
            read -rp "Project name: " proj_name
        fi
    fi
    [[ -z "$proj_name" ]] && { _err "Project name required."; return 1; }
    # Sanitize name
    proj_name=$(echo "$proj_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

    # ── Create directory ──────────────────────────────────────────────
    base_dir="${base_dir:-${CW_WORKSPACE:-$HOME/workspace}}"
    local proj_path="$base_dir/$proj_name"

    if [[ -d "$proj_path" ]]; then
        _warn "Directory already exists: $proj_path"
        read -rp "Use it anyway? [y/N] " c
        [[ "$c" =~ ^[yY]$ ]] || return 1
    else
        mkdir -p "$proj_path"
        _log "Created ${C}$proj_path${NC}"
    fi

    # ── Git init ──────────────────────────────────────────────────────
    if [[ ! -d "$proj_path/.git" ]]; then
        git -C "$proj_path" init -b main -q
        _log "Initialized git repo"
    fi

    # ── Register in CW ────────────────────────────────────────────────
    python3 -c "
import json
f = '$CW_REGISTRY'
try:
    with open(f) as fh: reg = json.load(fh)
except: reg = {}
reg['$proj_name'] = {
    'path': '$proj_path', 'account': '$account', 'type': 'fullstack',
    'registered': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}
with open(f, 'w') as fh: json.dump(reg, fh, indent=2)
"
    _log "Registered project ${C}$proj_name${NC} (account=${Y}$account${NC})"

    # ── Setup .claude dir & CLAUDE.md template ───────────────────────
    mkdir -p "$proj_path/.claude"
    if [[ ! -f "$proj_path/CLAUDE.md" ]]; then
        local tpl="$CW_HOME/templates/CLAUDE.fullstack.md"
        [[ -f "$tpl" ]] && cp "$tpl" "$proj_path/CLAUDE.md"
    fi

    # ── Build init prompt ─────────────────────────────────────────────
    local init_prompt=""
    if [[ -n "$source_url" ]]; then
        case "$source" in
            linear)
                init_prompt="Fetch this Linear issue/epic using the Linear MCP: $source_url
Use the content as the project specification." ;;
            notion)
                init_prompt="Fetch this Notion page using the Notion MCP: $source_url
Use the content as the project specification." ;;
            github)
                init_prompt="Fetch this GitHub page for context: $source_url
Use it as reference for the project." ;;
            *)
                init_prompt="Reference URL: $source_url" ;;
        esac
        init_prompt="$init_prompt

"
    fi

    init_prompt="${init_prompt}You are starting a brand new project from scratch.

Project: $proj_name
Working directory: $proj_path
Description: $description

Your job:
1. Analyze the description/spec and decide the tech stack, architecture, and structure
2. Scaffold the project (package.json/Cargo.toml/etc, directory structure, configs)
3. Build out the core functionality
4. Create a CLAUDE.md with project context for future sessions
5. Make an initial git commit when the scaffold is ready

IMPORTANT: When you're done building, ask the user:
\"Ready to push to GitHub. Which organization?\" and list options using: gh org list
Then create the repo with: gh repo create <org>/$proj_name --source . --push
If they want it on their personal account: gh repo create $proj_name --source . --push"

    if $team_flag && [[ -n "$team_prompt" ]]; then
        init_prompt="$init_prompt

Create an agent team to build this project in parallel:
$team_prompt"
    elif $team_flag; then
        init_prompt="$init_prompt

Create an agent team to build this project in parallel. Analyze the scope and split the work into logical domains (e.g. backend API, frontend UI, tests, infrastructure). Spawn teammates accordingly and coordinate the build."
    fi

    # ── Create session ────────────────────────────────────────────────
    local session_dir="$CW_HOME/sessions/$proj_name/task-init"
    mkdir -p "$session_dir"

    local session_meta="$session_dir/session.json"
    python3 -c "
import json
from datetime import datetime, timezone
meta = {
    'project': '$proj_name', 'task': 'init', 'type': 'task',
    'account': '$account',
    'worktree': '$proj_path',
    'source': '$source', 'source_url': '$source_url',
    'status': 'active',
    'created': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'last_opened': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'opens': 1
}
with open('$session_meta', 'w') as f: json.dump(meta, f, indent=2)
"

    # ── Launch Claude ─────────────────────────────────────────────────
    cd "$proj_path"
    _set_tab_title "create: $proj_name"

    export CW_PROJECT="$proj_name" CW_TASK="init" CW_TASK_TYPE="task" CW_ACCOUNT="$account"

    local team_env=""
    $team_flag && team_env="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"

    local prompt_file="$session_dir/init_prompt.txt"
    printf '%s' "$init_prompt" > "$prompt_file"

    _log "Launching Claude..."
    $team_flag && _log "Agent teams ${G}enabled${NC}"

    env $team_env CLAUDE_CONFIG_DIR="$acct_dir" claude $CW_CLAUDE_FLAGS "$(cat "$prompt_file")"

    unset CW_PROJECT CW_TASK CW_TASK_TYPE CW_ACCOUNT
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) CREATE $proj_name account=$account" >> "$CW_SESSIONS_LOG"
}

# ════════════════════════════════════════════════════════════════════════════
# HELP
# ════════════════════════════════════════════════════════════════════════════
cmd_help() {
    cat << EOF

${BOLD}CW — Claude Workspace Manager${NC}

${BOLD}MAIN COMMANDS${NC}
  create "<description>" [opts]       Bootstrap new project from scratch
    --account, -a <account>           Which account to use
    --name, -n <name>                 Project name (prompted if omitted)
    --dir, -d <path>                  Base directory (default: ~/workspace)
    --team ["<prompt>"]               Use agent teams for parallel build
  work <project> <task>               Work on feature/bug (worktree + session)
    --base, -b <branch>              Base branch for worktree (default: auto-detect)
  work <project> <task> --team        Launch with agent team (parallel work)
  work <project> <url>                Work from Linear/Notion/GitHub URL
  review <project> <PR>               Review PR (persistent session)
  review <project> <url>              Review from GitHub PR URL
  open <project>                      Open project quick (no worktree)
  launch [account]                    Open Claude with account (no project needed)
  spaces                              Show active spaces

${BOLD}MANAGE${NC}
  --done                              Close a work/review space
  --list                              List active work/reviews

${BOLD}SETUP${NC}
  init                                Initialize CW
  account add <name>                  Create account profile
  account list                        List accounts
  account remove <name>               Remove account
  project register [path] [opts]       Register project (path defaults to cwd)
    --account, -a <account>
    --type, -t <type>                 fullstack | api | knowledge | infra | agents
    --alias <name>                    Custom name (default: folder name)
  project remove <name>               Unregister project (keeps files)
  project list                        List projects
  project setup-mcps <name>           Configure GitHub/Linear/Notion/Slack
  project setup-agents <name>         Install agents and commands

${BOLD}INFO${NC}
  dashboard                           Full workspace overview
  status                              Quick status
  help                                This help
  version                             Show version

${BOLD}GLOBAL FLAGS${NC}
  --skip-permissions                  Skip Claude permission prompts for this run
                                      (sets --dangerously-skip-permissions)
                                      Can also be set permanently in ~/.cw/config.yaml:
                                        skip_permissions: true
                                      Or via env: CW_CLAUDE_FLAGS="--dangerously-skip-permissions"

${BOLD}EXAMPLES${NC}
  cw create "SaaS de analytics con Stripe"          # New project from description
  cw create "CLI tool en Rust" --team               # With agent teams
  cw create https://notion.so/.../spec -a work      # From Notion spec

  cw work daycast fix-auth                          # New task
  cw work daycast NEW-789                           # Task by ticket ID
  cw work daycast https://linear.app/.../NEW-789    # From Linear URL
  cw work daycast fix-auth                          # Resume (auto --continue)
  cw work daycast fix-auth --done                   # Close and cleanup
  cw work daycast big-feat --team                   # Launch with agent team (auto-split)
  cw work daycast big-feat --team "3 teammates: backend, frontend, tests"

  cw review triton 123                              # New PR review
  cw review triton https://github.com/.../pull/123  # From GitHub URL
  cw review triton 123 --done                       # Close review

  cw spaces                                         # All active spaces
  cw open daycast                                   # Quick open (no worktree)
  cw dashboard                                      # Full overview
  cw arcade                                         # Retro visual dashboard

${BOLD}INTEGRATIONS${NC}
  cw gsd:init [path]                Initialize GSD workflow in a worktree
  cw gsd:sync                       Initialize GSD in all active worktrees

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
    # Parse global flags before command
    _CW_SKIP_PERMS="false"
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --skip-permissions) _CW_SKIP_PERMS="true" ;;
            *) args+=("$arg") ;;
        esac
    done
    set -- "${args[@]+"${args[@]}"}"

    _resolve_claude_flags

    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        init)       cmd_init "$@" ;;
        account)    cmd_account "$@" ;;
        project)    cmd_project "$@" ;;
        open)       cmd_open "$@" ;;
        review)     cmd_review "$@" ;;
        work)       cmd_work "$@" ;;
        create)     cmd_create "$@" ;;
        spaces)     cmd_spaces "$@" ;;
        launch)     cmd_launch "$@" ;;
        dashboard)  cmd_dashboard "$@" ;;
        arcade)     cmd_arcade "$@" ;;
        status)     cmd_status "$@" ;;
        gsd|gsd:init|gsd:sync) cmd_gsd "${cmd#gsd:}" "$@" ;;
        help|-h|--help) cmd_help ;;
        version|-v|--version) echo "cw $CW_VERSION" ;;
        *) _err "Unknown: $cmd"; cmd_help; exit 1 ;;
    esac
}

main "$@"
