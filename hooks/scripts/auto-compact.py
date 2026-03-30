#!/usr/bin/env python3
"""
CW Auto-Compact Hook (PostToolUse)
===================================
Counts tool calls per session. After a threshold, injects additionalContext
telling Claude to run /compact proactively before the system auto-compacts.

Counter files stored in ~/.cw/compact-counters/<session_hash>.json
Configurable via hooks-config.json: "disableAutoCompactHook": true/false
                                    "autoCompactThreshold": N (default 100)
                                    "autoCompactCooldown": N (default 60)
"""

import sys
import json
import os
import hashlib
from pathlib import Path


DEFAULT_THRESHOLD = 100  # Tool calls before first compact suggestion
DEFAULT_COOLDOWN = 60    # Tool calls between subsequent suggestions


def _read_config():
    """Read auto-compact settings from hooks-config files."""
    script_dir = Path(__file__).parent
    config_dir = script_dir.parent / "config"
    local_path = config_dir / "hooks-config.local.json"
    default_path = config_dir / "hooks-config.json"

    local_cfg = {}
    default_cfg = {}

    try:
        if local_path.exists():
            with open(local_path) as f:
                local_cfg = json.load(f)
    except Exception:
        pass

    try:
        if default_path.exists():
            with open(default_path) as f:
                default_cfg = json.load(f)
    except Exception:
        pass

    def _get(key, fallback):
        if key in local_cfg:
            return local_cfg[key]
        if key in default_cfg:
            return default_cfg[key]
        return fallback

    return {
        "disabled": _get("disableAutoCompactHook", False),
        "threshold": _get("autoCompactThreshold", DEFAULT_THRESHOLD),
        "cooldown": _get("autoCompactCooldown", DEFAULT_COOLDOWN),
    }


def main():
    try:
        stdin_content = sys.stdin.read().strip()
        if not stdin_content:
            sys.exit(0)

        hook_data = json.loads(stdin_content)
        session_id = hook_data.get("session_id", "")
        if not session_id:
            sys.exit(0)

        cfg = _read_config()
        if cfg["disabled"]:
            sys.exit(0)

        # Counter directory
        cw_home = os.environ.get("CW_HOME", os.path.expanduser("~/.cw"))
        counter_dir = os.path.join(cw_home, "compact-counters")
        os.makedirs(counter_dir, exist_ok=True)

        # Hash session_id for filename safety
        session_hash = hashlib.sha256(session_id.encode()).hexdigest()[:16]
        counter_file = os.path.join(counter_dir, f"{session_hash}.json")

        # Read current state
        count = 0
        last_compact_at = 0
        try:
            with open(counter_file) as f:
                data = json.load(f)
                count = data.get("count", 0)
                last_compact_at = data.get("last_compact_at", 0)
        except (FileNotFoundError, json.JSONDecodeError):
            pass

        count += 1

        # Decide whether to suggest compact
        suggest = False
        if last_compact_at == 0 and count >= cfg["threshold"]:
            suggest = True
        elif last_compact_at > 0 and (count - last_compact_at) >= cfg["cooldown"]:
            suggest = True

        # Save updated counter
        save_data = {"count": count, "last_compact_at": last_compact_at}
        if suggest:
            save_data["last_compact_at"] = count
        with open(counter_file, "w") as f:
            json.dump(save_data, f)

        # Inject context for Claude
        if suggest:
            result = {
                "additionalContext": (
                    f"[CW Auto-Compact] This session has reached {count} tool calls. "
                    "You MUST run /compact now to preserve context quality. "
                    "Tell the user you're compacting proactively, then run /compact."
                )
            }
            print(json.dumps(result))

        sys.exit(0)

    except Exception:
        # Never block Claude's work
        sys.exit(0)


if __name__ == "__main__":
    main()
