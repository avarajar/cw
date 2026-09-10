# github needs no cw credential; gh carries its own auth
context_credential_github() {
    command -v gh >/dev/null 2>&1
}

context_fetch_github() {
    local url="$1"
    local num; num=$(printf '%s' "$url" | grep -oE '[0-9]+$')
    [[ -n "$num" ]] || return 1
    local kind=issue
    [[ "$url" == */pull/* ]] && kind=pr
    local json
    json=$(gh "$kind" view "$num" --json title,body,number,state,labels 2>/dev/null) || return 1
    CW_GH_JSON="$json" python3 - <<'PY'
import json, os, sys
try:
    d = json.loads(os.environ["CW_GH_JSON"])
except Exception:
    sys.exit(1)
labels = ", ".join(l["name"] for l in d.get("labels", []))
print(f"**#{d.get('number')} — {d.get('title','')}**")
print(f"State: {d.get('state','')}" + (f" · Labels: {labels}" if labels else ""))
print()
print(d.get("body") or "_No description._")
PY
}
