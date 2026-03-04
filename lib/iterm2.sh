#!/usr/bin/env bash
# ============================================================================
# CW iTerm2 Helpers — AppleScript + escape sequences
# ============================================================================

# ── Color presets per mode ─────────────────────────────────────────────────

_mode_color() {
    case "$1" in
        code)     echo "50 120 220"  ;;
        review)   echo "180 80 200"  ;;
        research) echo "40 180 160"  ;;
        docs)     echo "220 160 40"  ;;
        planning) echo "60 180 75"   ;;
        comms)    echo "200 60 80"   ;;
        full)     echo "100 100 100" ;;
        shell)    echo "80 80 80"    ;;
        git)      echo "230 120 50"  ;;
        feature)  echo "50 150 250"  ;;
        bug)      echo "230 60 60"   ;;
        *)        echo "100 100 100" ;;
    esac
}

# ── Core AppleScript functions ─────────────────────────────────────────────

# Create a new iTerm2 window, cd to dir
_iterm_new_window() {
    local dir="$1"
    osascript <<EOF
tell application "iTerm2"
    set newWindow to (create window with default profile)
    tell current session of current tab of newWindow
        write text "cd ${dir}"
    end tell
end tell
EOF
}

# Create a new tab in current window, cd to dir
_iterm_new_tab() {
    local dir="$1"
    osascript <<EOF
tell application "iTerm2"
    tell current window
        set newTab to (create tab with default profile)
        tell current session of newTab
            write text "cd ${dir}"
        end tell
    end tell
end tell
EOF
}

# Send a command to current session
_iterm_send() {
    local cmd="$1"
    osascript <<EOF
tell application "iTerm2"
    tell current session of current tab of current window
        write text "${cmd}"
    end tell
end tell
EOF
}

# Select tab by index (1-based)
_iterm_select_tab() {
    local idx="$1"
    osascript <<EOF
tell application "iTerm2"
    tell current window
        select tab ${idx}
    end tell
end tell
EOF
}

# Focus iTerm2
_iterm_focus() {
    osascript -e 'tell application "iTerm2" to activate'
}

# ── Tab coloring via escape sequences ──────────────────────────────────────

# Set tab color on current session (must be called AFTER the tab exists)
_iterm_set_tab_color() {
    local r="$1" g="$2" b="$3"
    _iterm_send "printf '\\\\033]6;1;bg;red;brightness;${r}\\\\a\\\\033]6;1;bg;green;brightness;${g}\\\\a\\\\033]6;1;bg;blue;brightness;${b}\\\\a'"
}

# Set badge on current session
_iterm_set_badge() {
    local text="$1"
    local b64
    b64=$(printf '%s' "$text" | base64)
    _iterm_send "printf '\\\\033]1337;SetBadgeFormat=${b64}\\\\a'"
}

# Set tab title via escape sequence
_iterm_set_title() {
    local title="$1"
    _iterm_send "printf '\\\\033]0;${title}\\\\007'"
}

# ── Compound: configured window and tabs ──────────────────────────────────

# Create a fully configured window: dir, command, badge, mode
_iterm_configured_window() {
    local title="$1" dir="$2" cmd="$3" badge="$4" mode="$5"
    local r g b
    read -r r g b <<< "$(_mode_color "$mode")"

    _iterm_new_window "$dir"
    sleep 0.4

    _iterm_set_title "$title"
    _iterm_set_tab_color "$r" "$g" "$b"
    [[ -n "$badge" ]] && _iterm_set_badge "$badge"

    sleep 0.2
    [[ -n "$cmd" ]] && _iterm_send "$cmd"
}

# Create a fully configured tab: dir, command, badge, mode
_iterm_configured_tab() {
    local title="$1" dir="$2" cmd="$3" badge="$4" mode="$5"
    local r g b
    read -r r g b <<< "$(_mode_color "$mode")"

    _iterm_new_tab "$dir"
    sleep 0.4

    _iterm_set_title "$title"
    _iterm_set_tab_color "$r" "$g" "$b"
    [[ -n "$badge" ]] && _iterm_set_badge "$badge"

    sleep 0.2
    [[ -n "$cmd" ]] && _iterm_send "$cmd"
}
