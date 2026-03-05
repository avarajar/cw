#!/usr/bin/env python3
"""CW Activity Feed Hook — emits lightweight events to ~/.cw/activity.jsonl.

This script is called by Claude Code hooks (PreToolUse, PostToolUse, etc.)
and writes a single JSON line per event for the retro dashboard to display.

CW injects env vars before launching Claude:
  CW_PROJECT, CW_TASK, CW_TASK_TYPE, CW_ACCOUNT
"""

import sys
import json
import os
import time
from pathlib import Path

CW_HOME = os.environ.get("CW_HOME", os.path.expanduser("~/.cw"))
ACTIVITY_FILE = os.path.join(CW_HOME, "activity.jsonl")
MAX_SIZE = 500_000  # ~500KB before rotation
MAX_LINES = 2000


def main():
    try:
        raw = sys.stdin.read().strip()
        if not raw:
            sys.exit(0)
        data = json.loads(raw)
    except Exception:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    session_id = data.get("session_id", "")
    tool = data.get("tool_name", "")
    cwd = data.get("cwd", "")

    # CW context from environment (set by cw work/review before launching claude)
    project = os.environ.get("CW_PROJECT", "")
    task = os.environ.get("CW_TASK", "")
    task_type = os.environ.get("CW_TASK_TYPE", "")
    account = os.environ.get("CW_ACCOUNT", "")

    # Fallback: infer from cwd if env vars not set
    if not project and cwd:
        if "/.tasks/" in cwd:
            parts = cwd.split("/.tasks/")
            project = os.path.basename(parts[0])
            task = parts[1].split("/")[0] if len(parts) > 1 else ""
            task_type = "task"
        elif "/.reviews/" in cwd:
            parts = cwd.split("/.reviews/")
            project = os.path.basename(parts[0])
            task = parts[1].split("/")[0] if len(parts) > 1 else ""
            task_type = "review"
        else:
            project = os.path.basename(cwd)

    # Build summary (keep it short)
    summary = ""
    ti = data.get("tool_input", {})
    if isinstance(ti, str):
        try:
            ti = json.loads(ti)
        except Exception:
            ti = {}

    if tool == "Bash":
        cmd = ti.get("command", "")
        summary = cmd[:100]
    elif tool in ("Read", "Write"):
        fp = ti.get("file_path", "")
        summary = os.path.basename(fp) if fp else ""
    elif tool == "Edit":
        fp = ti.get("file_path", "")
        summary = os.path.basename(fp) if fp else ""
    elif tool in ("Glob",):
        summary = ti.get("pattern", "")[:60]
    elif tool in ("Grep",):
        summary = ti.get("pattern", ti.get("query", ""))[:60]
    elif tool == "Agent":
        summary = ti.get("description", "")[:60]
    elif tool == "WebFetch":
        summary = ti.get("url", "")[:80]
    elif tool == "WebSearch":
        summary = ti.get("query", "")[:60]
    elif event == "SubagentStart":
        summary = data.get("agent_type", "")
    elif event == "SubagentStop":
        summary = data.get("agent_type", "")
    elif event == "Stop":
        summary = "response complete"
    elif event == "SessionStart":
        summary = data.get("source", "")
    elif event == "SessionEnd":
        summary = data.get("reason", "")
    elif event == "TeammateIdle":
        summary = f"teammate idle: {data.get('teammate_name', '')}"
    elif event == "TaskCompleted":
        summary = f"task done: {data.get('task_description', '')[:60]}"

    entry = {
        "ts": time.time(),
        "event": event,
        "session": session_id[:12] if session_id else "",
        "tool": tool,
        "project": project,
        "task": task,
        "type": task_type,
        "account": account,
        "summary": summary,
    }

    try:
        os.makedirs(os.path.dirname(ACTIVITY_FILE), exist_ok=True)
        with open(ACTIVITY_FILE, "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        # Rotate if too large
        try:
            if os.path.getsize(ACTIVITY_FILE) > MAX_SIZE:
                with open(ACTIVITY_FILE) as f:
                    lines = f.readlines()
                with open(ACTIVITY_FILE, "w") as f:
                    f.writelines(lines[-MAX_LINES:])
        except Exception:
            pass
    except Exception:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
