#!/usr/bin/env python3
"""
CW Review Auto-Close Hook (PostToolUse on Bash)
================================================
Detects when Claude posts a review via `gh api` or `gh pr review`
and automatically closes the review session + tells Claude to stop.

Triggers on any review event: APPROVE, REQUEST_CHANGES, or COMMENT.

Reads CW_PROJECT, CW_TASK, CW_TASK_TYPE from environment (set by cmd_review).
"""

import sys
import json
import os
import re
from datetime import datetime, timezone


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

    # Check the command submitted a review
    tool_input = hook_data.get("tool_input", {})
    command = tool_input.get("command", "")

    is_review = False
    review_event = ""

    # Pattern 1: gh api ... /reviews ... event=<EVENT>
    if "gh api" in command and "reviews" in command:
        m = re.search(
            r'event[=\s]+["\']?(APPROVE|REQUEST_CHANGES|COMMENT)["\']?',
            command,
            re.IGNORECASE,
        )
        if m:
            is_review = True
            review_event = m.group(1).upper()

    # Pattern 2: gh pr review --approve / --request-changes / --comment
    if "gh pr review" in command:
        if "--approve" in command:
            is_review = True
            review_event = "APPROVE"
        elif "--request-changes" in command:
            is_review = True
            review_event = "REQUEST_CHANGES"
        elif "--comment" in command:
            is_review = True
            review_event = "COMMENT"

    if not is_review:
        sys.exit(0)

    # Check that the command succeeded
    # tool_response has: stdout, stderr, interrupted — no exit_code field
    tool_response = hook_data.get("tool_response", {})
    stderr = tool_response.get("stderr", "")
    stdout = tool_response.get("stdout", "")
    interrupted = tool_response.get("interrupted", False)

    if interrupted or (not stdout and stderr):
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
            meta["review_event"] = review_event
            meta["closed"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            with open(session_meta, "w") as f:
                json.dump(meta, f, indent=2)
        except Exception:
            pass

    # Log to sessions.log
    try:
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(sessions_log, "a") as f:
            f.write(f"{now} DONE {project} review={task}\n")
    except Exception:
        pass

    # Tell Claude to stop — exit code 2 sends stderr as feedback
    event_label = review_event.replace("_", " ").title()
    print(
        f"STOP. The review session for {project} PR #{task.replace('pr-', '')} "
        f"has been automatically closed after {event_label}. "
        "The session metadata and logs have been updated. "
        "Do NOT continue working. Say a brief goodbye and stop.",
        file=sys.stderr,
    )
    sys.exit(2)


if __name__ == "__main__":
    main()
