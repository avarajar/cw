#!/usr/bin/env python3
"""
CW Review Auto-Close Hook (PostToolUse on Bash)
================================================
Detects when Claude posts an APPROVE review via `gh api` or `gh pr review`
and automatically closes the review session + stops the conversation.

Reads CW_PROJECT, CW_TASK, CW_TASK_TYPE from environment (set by cmd_review).
"""

import sys
import json
import os
import re
from datetime import datetime, timezone

DEBUG_LOG = os.path.join(os.environ.get("CW_HOME", os.path.expanduser("~/.cw")), "review-autoclose-debug.log")

def _debug(msg):
    with open(DEBUG_LOG, "a") as f:
        f.write(f"[{datetime.now().isoformat()}] {msg}\n")


def main():
    _debug("=== HOOK INVOKED ===")

    # Only act on review sessions
    task_type = os.environ.get("CW_TASK_TYPE", "")
    project = os.environ.get("CW_PROJECT", "")
    task = os.environ.get("CW_TASK", "")
    _debug(f"ENV: CW_TASK_TYPE={task_type!r} CW_PROJECT={project!r} CW_TASK={task!r}")

    if task_type != "review":
        _debug("EXIT: not a review session")
        sys.exit(0)

    if not project or not task:
        _debug("EXIT: missing project or task")
        sys.exit(0)

    # Read hook data from stdin
    try:
        stdin_content = sys.stdin.read().strip()
        if not stdin_content:
            _debug("EXIT: empty stdin")
            sys.exit(0)
        hook_data = json.loads(stdin_content)
    except (json.JSONDecodeError, Exception) as e:
        _debug(f"EXIT: stdin parse error: {e}")
        sys.exit(0)

    _debug(f"STDIN KEYS: {list(hook_data.keys())}")
    _debug(f"FULL STDIN: {json.dumps(hook_data, default=str)[:2000]}")

    # Check the command contained an APPROVE review
    tool_input = hook_data.get("tool_input", {})
    command = tool_input.get("command", "")
    _debug(f"COMMAND: {command[:500]}")

    is_approve = False

    # Pattern 1: gh api ... event=APPROVE (inline review via API)
    if "gh api" in command and "reviews" in command:
        if re.search(r'event[=\s]+["\']?APPROVE["\']?', command, re.IGNORECASE):
            is_approve = True
            _debug("MATCH: gh api + event=APPROVE")

    # Pattern 2: gh pr review --approve
    if "gh pr review" in command and "--approve" in command:
        is_approve = True
        _debug("MATCH: gh pr review --approve")

    if not is_approve:
        _debug("EXIT: no approve pattern found")
        sys.exit(0)

    # Check that the command succeeded
    tool_response = hook_data.get("tool_response", {})
    _debug(f"TOOL_RESPONSE KEYS: {list(tool_response.keys()) if isinstance(tool_response, dict) else type(tool_response)}")
    _debug(f"TOOL_RESPONSE: {json.dumps(tool_response, default=str)[:1000]}")

    exit_code = tool_response.get("exit_code", tool_response.get("exitCode", 1))
    _debug(f"EXIT_CODE: {exit_code!r} (type={type(exit_code).__name__})")

    if exit_code != 0:
        _debug(f"EXIT: command failed (exit_code={exit_code})")
        sys.exit(0)

    # ── Close the review session (same as cw review --done) ──────────
    _debug("CLOSING SESSION")
    cw_home = os.environ.get("CW_HOME", os.path.expanduser("~/.cw"))
    sessions_log = os.path.join(cw_home, "sessions.log")
    session_dir = os.path.join(cw_home, "sessions", project, f"review-{task}")
    session_meta = os.path.join(session_dir, "session.json")
    _debug(f"SESSION_META: {session_meta} (exists={os.path.isfile(session_meta)})")

    # Update session.json
    if os.path.isfile(session_meta):
        try:
            with open(session_meta) as f:
                meta = json.load(f)
            meta["status"] = "done"
            meta["closed"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            with open(session_meta, "w") as f:
                json.dump(meta, f, indent=2)
            _debug("SESSION UPDATED: status=done")
        except Exception as e:
            _debug(f"ERROR updating session: {e}")

    # Log to sessions.log
    try:
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(sessions_log, "a") as f:
            f.write(f"{now} DONE {project} review={task}\n")
        _debug("SESSIONS.LOG updated")
    except Exception as e:
        _debug(f"ERROR logging: {e}")

    # Stop the Claude conversation
    output = {"continue": False, "stopReason": f"Review session closed — PR approved ({project} {task})"}
    _debug(f"OUTPUT: {json.dumps(output)}")
    print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
