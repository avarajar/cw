#!/usr/bin/env python3
"""
CW Review Auto-Close Hook (PostToolUse on Bash)
================================================
Detects when Claude posts a review via `gh api` or `gh pr review`
and automatically closes the review session + tells Claude to stop.

Only triggers session close on APPROVE. REQUEST_CHANGES and COMMENT
leave the session open so the reviewer can continue iterating.

Reads CW_PROJECT, CW_TASK, CW_TASK_TYPE from environment (set by cmd_review).
"""

import sys
import json
import os
import re
from datetime import datetime, timezone


def _debug(msg):
    """Write debug info to a log file for troubleshooting."""
    try:
        cw_home = os.environ.get("CW_HOME", os.path.expanduser("~/.cw"))
        log_path = os.path.join(cw_home, "review-autoclose.log")
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(log_path, "a") as f:
            f.write(f"{now} {msg}\n")
    except Exception:
        pass


def main():
    # Only act on review sessions
    task_type = os.environ.get("CW_TASK_TYPE", "")
    if task_type != "review":
        sys.exit(0)

    project = os.environ.get("CW_PROJECT", "")
    task = os.environ.get("CW_TASK", "")  # e.g. "pr-123"
    if not project or not task:
        _debug(f"SKIP: missing env — project={project!r} task={task!r}")
        sys.exit(0)

    # Read hook data from stdin
    try:
        stdin_content = sys.stdin.read().strip()
        if not stdin_content:
            sys.exit(0)
        hook_data = json.loads(stdin_content)
    except (json.JSONDecodeError, Exception) as e:
        _debug(f"SKIP: stdin parse error — {e}")
        sys.exit(0)

    # Check the command submitted a review
    tool_input = hook_data.get("tool_input", {})
    command = tool_input.get("command", "")

    is_review = False
    review_event = ""

    # Pattern 1: gh api ... /reviews ... event=<EVENT> (with -f or -F flags)
    if "gh api" in command and "reviews" in command:
        # Match: -f event=APPROVE, -F event=APPROVE, event=APPROVE
        m = re.search(
            r'event[=\s]+["\']?(APPROVE|REQUEST_CHANGES|COMMENT)["\']?',
            command,
            re.IGNORECASE,
        )
        if m:
            is_review = True
            review_event = m.group(1).upper()
        else:
            # Also match JSON body: "event": "APPROVE" or "event":"APPROVE"
            m = re.search(
                r'"event"\s*:\s*"(APPROVE|REQUEST_CHANGES|COMMENT)"',
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
        _debug(f"SKIP: not a review command — {command[:200]}")
        sys.exit(0)

    _debug(f"DETECTED: {review_event} for {project} {task}")

    # Only auto-close on APPROVE — REQUEST_CHANGES and COMMENT leave
    # the session open so the reviewer can keep iterating.
    if review_event != "APPROVE":
        _debug(f"SKIP: not closing session — event is {review_event}, not APPROVE")
        sys.exit(0)

    # Check that the command succeeded
    # tool_response has: stdout, stderr, interrupted — no exit_code field
    tool_response = hook_data.get("tool_response", {})

    # Guard: tool_response might be a string in some cases
    if isinstance(tool_response, str):
        tool_response = {"stdout": tool_response, "stderr": "", "interrupted": False}

    stderr = tool_response.get("stderr", "")
    stdout = tool_response.get("stdout", "")
    interrupted = tool_response.get("interrupted", False)

    # gh pr review outputs its success message to stderr (e.g. "✓ Approved pull request #334")
    # so we can't treat stderr-only output as failure. Instead, only bail if interrupted
    # or if stderr looks like an actual error (no success indicator and no stdout).
    has_error = stderr and "error" in stderr.lower() and not stdout
    if interrupted or has_error:
        _debug(f"SKIP: command failed — interrupted={interrupted} has_error={has_error} stderr={stderr[:200]}")
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
            _debug(f"CLOSED: session updated — {session_meta}")
        except Exception as e:
            _debug(f"ERROR: failed to update session — {e}")
    else:
        _debug(f"WARN: session.json not found at {session_meta}")

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
