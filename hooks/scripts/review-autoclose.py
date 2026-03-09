#!/usr/bin/env python3
"""
CW Review Auto-Close Hook (PostToolUse on Bash)
================================================
Detects when Claude posts an APPROVE review via `gh api` and automatically
closes the review session — equivalent to `cw review <project> <pr> --done`.

Reads CW_PROJECT, CW_TASK, CW_TASK_TYPE from environment (set by cmd_review).
"""

import sys
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path


def main():
    # Only act on review sessions
    task_type = os.environ.get("CW_TASK_TYPE", "")
    if task_type != "review":
        sys.exit(0)

    project = os.environ.get("CW_PROJECT", "")
    task = os.environ.get("CW_TASK", "")  # e.g. "pr-123"
    if not project or not task:
        sys.exit(0)

    # Read hook data from stdin
    try:
        stdin_content = sys.stdin.read().strip()
        if not stdin_content:
            sys.exit(0)
        hook_data = json.loads(stdin_content)
    except (json.JSONDecodeError, Exception):
        sys.exit(0)

    # Check this is a Bash PostToolUse
    if hook_data.get("hook_event_name") != "PostToolUse":
        sys.exit(0)
    if hook_data.get("tool_name") != "Bash":
        sys.exit(0)

    # Check the command contained an APPROVE review
    tool_input = hook_data.get("tool_input", {})
    command = tool_input.get("command", "")

    # Match patterns like: event=APPROVE, event='APPROVE', -f event=APPROVE
    if not re.search(r'event[=\s]+["\']?APPROVE["\']?', command, re.IGNORECASE):
        sys.exit(0)

    # Also verify it's a gh api call to pulls/reviews
    if "gh api" not in command or "reviews" not in command:
        sys.exit(0)

    # Check that the command succeeded
    tool_result = hook_data.get("tool_result", {})
    if tool_result.get("exitCode", 1) != 0:
        sys.exit(0)

    # ── Close the review session (same as cw review --done) ──────────
    cw_home = os.environ.get("CW_HOME", os.path.expanduser("~/.cw"))
    sessions_log = os.path.join(cw_home, "sessions.log")
    session_dir = os.path.join(cw_home, "sessions", project, f"review-{task}")
    session_meta = os.path.join(session_dir, "session.json")

    # Update session.json
    if os.path.isfile(session_meta):
        try:
            with open(session_meta) as f:
                meta = json.load(f)
            meta["status"] = "done"
            meta["closed"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            with open(session_meta, "w") as f:
                json.dump(meta, f, indent=2)
        except Exception as e:
            print(f"review-autoclose: error updating session: {e}", file=sys.stderr)

    # Log to sessions.log
    try:
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(sessions_log, "a") as f:
            f.write(f"{now} DONE {project} review={task}\n")
    except Exception as e:
        print(f"review-autoclose: error logging: {e}", file=sys.stderr)

    print(f"review-autoclose: session closed for {project} {task}", file=sys.stderr)
    sys.exit(0)


if __name__ == "__main__":
    main()
