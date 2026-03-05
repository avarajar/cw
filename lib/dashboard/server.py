#!/usr/bin/env python3
"""CW Retro Dashboard — Data server.

Tiny HTTP server that:
  GET /           → serves index.html
  GET /api/data   → returns live CW workspace data as JSON
  GET /api/activity?after=<ts> → returns recent activity events
  GET /api/stream → SSE stream of real-time activity events
"""

import http.server
import json
import os
import glob
import sys
import webbrowser
import socket
import time
import threading
from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import urlparse, parse_qs

CW_HOME = os.environ.get("CW_HOME", os.path.expanduser("~/.cw"))
DASHBOARD_DIR = os.path.dirname(os.path.abspath(__file__))
ACTIVITY_FILE = os.path.join(CW_HOME, "activity.jsonl")


def collect_data():
    data = {
        "version": "0.1.0",
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "accounts": [],
        "projects": [],
        "sessions": [],
        "stats": {},
        "recent_log": [],
    }

    # ── Accounts ──────────────────────────────────────────────
    accounts_dir = os.path.join(CW_HOME, "accounts")
    if os.path.isdir(accounts_dir):
        for name in sorted(os.listdir(accounts_dir)):
            acct_path = os.path.join(accounts_dir, name)
            if not os.path.isdir(acct_path) or name.startswith("."):
                continue
            auth_file = os.path.join(acct_path, ".claude.json")
            data["accounts"].append(
                {"name": name, "authenticated": os.path.isfile(auth_file)}
            )

    # ── Projects ──────────────────────────────────────────────
    registry = os.path.join(CW_HOME, "projects.json")
    if os.path.isfile(registry):
        with open(registry) as f:
            projects = json.load(f)
        for name, info in projects.items():
            pp = info.get("path", "")
            claude_md = os.path.isfile(os.path.join(pp, "CLAUDE.md"))
            agents_dir = os.path.join(pp, ".claude", "agents")
            commands_dir = os.path.join(pp, ".claude", "commands")
            agents = (
                len(glob.glob(os.path.join(agents_dir, "*.md")))
                if os.path.isdir(agents_dir)
                else 0
            )
            commands = (
                len(glob.glob(os.path.join(commands_dir, "*.md")))
                if os.path.isdir(commands_dir)
                else 0
            )
            has_mcp = False
            settings_file = os.path.join(pp, ".claude", "settings.json")
            if os.path.isfile(settings_file):
                try:
                    with open(settings_file) as sf:
                        s = json.load(sf)
                    if s.get("mcpServers") or s.get("mcp_servers"):
                        has_mcp = True
                except Exception:
                    pass

            data["projects"].append(
                {
                    "name": name,
                    "account": info.get("account", ""),
                    "path": pp,
                    "type": info.get("type", ""),
                    "has_claude_md": claude_md,
                    "agents": agents,
                    "commands": commands,
                    "has_mcp": has_mcp,
                    "git": os.path.isdir(os.path.join(pp, ".git")),
                }
            )

    # ── Sessions ──────────────────────────────────────────────
    sessions_dir = os.path.join(CW_HOME, "sessions")
    if os.path.isdir(sessions_dir):
        for project in sorted(os.listdir(sessions_dir)):
            project_dir = os.path.join(sessions_dir, project)
            if not os.path.isdir(project_dir):
                continue
            for session in sorted(os.listdir(project_dir)):
                meta_file = os.path.join(project_dir, session, "session.json")
                if os.path.isfile(meta_file):
                    try:
                        with open(meta_file) as f:
                            meta = json.load(f)
                        data["sessions"].append(meta)
                    except Exception:
                        pass

    # ── Recent log ────────────────────────────────────────────
    log_file = os.path.join(CW_HOME, "sessions.log")
    if os.path.isfile(log_file):
        with open(log_file) as f:
            lines = f.readlines()
        data["recent_log"] = [l.strip() for l in lines[-30:] if l.strip()]

    # ── Stats ─────────────────────────────────────────────────
    active = [s for s in data["sessions"] if s.get("status") == "active"]
    done = [s for s in data["sessions"] if s.get("status") == "done"]
    tasks = [s for s in active if s.get("type") == "task"]
    reviews = [s for s in active if s.get("type") == "review"]
    total_opens = sum(s.get("opens", 0) for s in data["sessions"])

    data["stats"] = {
        "total_sessions": len(data["sessions"]),
        "active_sessions": len(active),
        "completed_sessions": len(done),
        "active_tasks": len(tasks),
        "active_reviews": len(reviews),
        "total_opens": total_opens,
        "total_projects": len(data["projects"]),
        "total_accounts": len(data["accounts"]),
    }

    return data


def collect_activity(after_ts=0.0, limit=100):
    """Read recent activity events from the JSONL file."""
    events = []
    if not os.path.isfile(ACTIVITY_FILE):
        return events

    try:
        with open(ACTIVITY_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if entry.get("ts", 0) > after_ts:
                        events.append(entry)
                except Exception:
                    continue
    except Exception:
        pass

    # Return most recent entries
    return events[-limit:]


def get_live_sessions(events, window=30):
    """Derive which sessions are 'live' (had activity in last N seconds)."""
    now = time.time()
    cutoff = now - window
    live = {}

    for e in events:
        ts = e.get("ts", 0)
        if ts < cutoff:
            continue
        key = e.get("project", "") + "/" + e.get("task", "")
        if not key or key == "/":
            key = e.get("session", "unknown")

        existing = live.get(key)
        if not existing or ts > existing["ts"]:
            live[key] = {
                "project": e.get("project", ""),
                "task": e.get("task", ""),
                "type": e.get("type", ""),
                "account": e.get("account", ""),
                "session": e.get("session", ""),
                "event": e.get("event", ""),
                "tool": e.get("tool", ""),
                "summary": e.get("summary", ""),
                "ts": ts,
                "age": round(now - ts, 1),
            }

    return list(live.values())


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DASHBOARD_DIR, **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/api/data":
            self._json_response(collect_data())

        elif parsed.path == "/api/activity":
            qs = parse_qs(parsed.query)
            after = float(qs.get("after", ["0"])[0])
            limit = int(qs.get("limit", ["100"])[0])
            events = collect_activity(after, limit)
            live = get_live_sessions(events)
            self._json_response({"events": events, "live": live})

        elif parsed.path == "/api/stream":
            self._sse_stream()

        elif parsed.path == "/" or parsed.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.end_headers()
            html_path = os.path.join(DASHBOARD_DIR, "index.html")
            with open(html_path, "rb") as f:
                self.wfile.write(f.read())
        else:
            super().do_GET()

    def _json_response(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _sse_stream(self):
        """Server-Sent Events: tail activity.jsonl and push new lines."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        # Seek to end of file
        try:
            if os.path.isfile(ACTIVITY_FILE):
                f = open(ACTIVITY_FILE, "r")
                f.seek(0, 2)  # seek to end
            else:
                f = None

            last_size = os.path.getsize(ACTIVITY_FILE) if f else 0

            while True:
                # Check if file was recreated/truncated
                try:
                    cur_size = os.path.getsize(ACTIVITY_FILE) if os.path.isfile(ACTIVITY_FILE) else 0
                except OSError:
                    cur_size = 0

                if f is None and os.path.isfile(ACTIVITY_FILE):
                    f = open(ACTIVITY_FILE, "r")
                    f.seek(0, 2)
                    last_size = cur_size
                elif f and cur_size < last_size:
                    # File was truncated/rotated, reopen
                    f.close()
                    f = open(ACTIVITY_FILE, "r")
                    last_size = 0

                if f:
                    new_lines = f.readlines()
                    last_size = cur_size
                    for line in new_lines:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            entry = json.loads(line)
                            # Send as SSE event
                            payload = json.dumps(entry, ensure_ascii=False)
                            self.wfile.write(f"data: {payload}\n\n".encode())
                            self.wfile.flush()
                        except Exception:
                            continue

                # Send keepalive comment every cycle
                try:
                    self.wfile.write(f": keepalive {time.time()}\n\n".encode())
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    break

                time.sleep(0.5)

        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            if f:
                f.close()

    def log_message(self, format, *args):
        pass


def find_free_port(start=3737):
    for port in range(start, start + 100):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    return start


def main():
    port = find_free_port()
    # Use ThreadingHTTPServer so SSE doesn't block other requests
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), DashboardHandler)
    url = f"http://127.0.0.1:{port}"
    print(f"\033[0;32m[cw]\033[0m Retro Dashboard \u2192 {url}")
    print(f"\033[2m     Press Ctrl+C to stop\033[0m")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print(f"\n\033[0;32m[cw]\033[0m Dashboard stopped")
        server.server_close()


if __name__ == "__main__":
    main()
