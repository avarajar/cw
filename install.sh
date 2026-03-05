#!/bin/bash
set -euo pipefail

# CW Installer — Claude Workspace Manager
# Usage: ./install.sh
#   or:  curl -fsSL https://raw.githubusercontent.com/avarajar/cw/main/install.sh | bash

CW_HOME="${CW_HOME:-$HOME/.cw}"
REPO_URL="https://github.com/avarajar/cw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" && pwd 2>/dev/null || echo ".")"

NC='\033[0m'
BOLD='\033[1m'
C='\033[36m'
G='\033[32m'
Y='\033[33m'
R='\033[31m'

log()  { echo -e "${C}[cw]${NC} $*"; }
ok()   { echo -e "${G}[✓]${NC} $*"; }
warn() { echo -e "${Y}[!]${NC} $*"; }
err()  { echo -e "${R}[✗]${NC} $*" >&2; }

# ── Check requirements ──────────────────────────────────────────────────────

check_requirements() {
    local missing=()

    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi

    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
    fi

    if ! command -v claude &>/dev/null; then
        warn "Claude Code CLI not found. Install: npm install -g @anthropic-ai/claude-code"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # Check git version (need 2.15+ for worktrees)
    local git_version
    git_version=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local major minor
    major=$(echo "$git_version" | cut -d. -f1)
    minor=$(echo "$git_version" | cut -d. -f2)
    if [[ $major -lt 2 ]] || [[ $major -eq 2 && $minor -lt 15 ]]; then
        err "Git 2.15+ required for worktree support. Current: $(git --version)"
        exit 1
    fi

    ok "Requirements met"
}

# ── Install ─────────────────────────────────────────────────────────────────

install_files() {
    local source_dir="$SCRIPT_DIR"

    # If running from curl pipe, clone to temp dir
    if [[ ! -f "$source_dir/cw" ]]; then
        log "Downloading CW..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        git clone --depth 1 "$REPO_URL" "$tmp_dir" 2>/dev/null
        source_dir="$tmp_dir"
    fi

    # Create directory structure
    mkdir -p "$CW_HOME"/{bin,lib,accounts,sessions,templates,agents,commands,mcps}

    # Copy scripts
    cp "$source_dir/cw" "$CW_HOME/bin/cw"
    chmod +x "$CW_HOME/bin/cw"

    cp "$source_dir/cw-shell-integration.sh" "$CW_HOME/cw-shell-integration.sh"

    # Copy lib
    if [[ -d "$source_dir/lib" ]]; then
        cp "$source_dir"/lib/*.sh "$CW_HOME/lib/" 2>/dev/null || true
    fi

    # Copy templates
    cp "$source_dir/templates/CLAUDE.template.md" "$CW_HOME/templates/CLAUDE.template.md"

    # Copy agents
    if [[ -d "$source_dir/agents" ]]; then
        mkdir -p "$CW_HOME/agents"
        cp "$source_dir"/agents/*.md "$CW_HOME/agents/" 2>/dev/null || true
        ok "Agents installed"
    fi

    # Copy hooks
    if [[ -d "$source_dir/hooks" ]]; then
        mkdir -p "$CW_HOME/hooks"
        cp -r "$source_dir/hooks/." "$CW_HOME/hooks/"
        ok "Hooks installed"
    fi

    # Copy MCP configs
    if [[ -d "$source_dir/mcps" ]]; then
        mkdir -p "$CW_HOME/mcps"
        cp "$source_dir"/mcps/*.json "$CW_HOME/mcps/" 2>/dev/null || true
        ok "MCP configs installed"
    fi

    # Initialize projects.json if not exists
    [[ -f "$CW_HOME/projects.json" ]] || echo '{}' > "$CW_HOME/projects.json"

    ok "Files installed to $CW_HOME"

    # Cleanup temp dir if used
    [[ -d "${tmp_dir:-}" ]] && rm -rf "$tmp_dir"
}

# ── Shell integration ───────────────────────────────────────────────────────

setup_shell() {
    local shell_line='[[ -f "$HOME/.cw/cw-shell-integration.sh" ]] && source "$HOME/.cw/cw-shell-integration.sh"'
    local added=false

    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [[ -f "$rc" ]]; then
            if ! grep -q "cw-shell-integration" "$rc" 2>/dev/null; then
                echo "" >> "$rc"
                echo "# CW — Claude Workspace Manager" >> "$rc"
                echo "$shell_line" >> "$rc"
                ok "Added to $rc"
                added=true
            else
                ok "Already in $rc"
                added=true
            fi
        fi
    done

    if ! $added; then
        warn "Could not detect shell rc file. Add manually:"
        echo "  $shell_line"
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}CW — Claude Workspace Manager${NC}"
    echo -e "Installing to ${C}$CW_HOME${NC}"
    echo ""

    check_requirements
    install_files
    setup_shell

    echo ""
    ok "Installation complete!"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "  1. Restart your terminal (or: ${C}source ~/.zshrc${NC})"
    echo -e "  2. ${C}cw init${NC}"
    echo -e "  3. ${C}cw account add work${NC}"
    echo -e "  4. ${C}cw project register <path> --account work${NC}"
    echo -e "  5. ${C}cw work <project> <task>${NC}"
    echo ""
}

main "$@"
