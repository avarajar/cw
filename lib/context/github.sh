# github needs no cw credential; gh carries its own auth
context_credential_github() {
    command -v gh >/dev/null 2>&1
}

# passes gh the canonical url so it never resolves the repo from the caller's cwd
context_fetch_github() {
    local url="$1"
    local re='^https?://(www\.)?github\.com/([^/[:space:]]+)/([^/[:space:]]+)/(issues|pull)/([0-9]+)([/?#].*)?$'
    [[ "$url" =~ $re ]] || return 1
    local owner="${BASH_REMATCH[2]}" repo="${BASH_REMATCH[3]}" path="${BASH_REMATCH[4]}" num="${BASH_REMATCH[5]}"
    local kind=issue
    [[ "$path" == pull ]] && kind=pr
    local canonical="https://github.com/$owner/$repo/$path/$num"
    local json
    json=$(gh "$kind" view "$canonical" --json title,body,number,state,labels 2>/dev/null) || return 1
    CW_GH_JSON="$json" CW_GH_NUM="$num" python3 - <<'PY'
import json, os, sys
try:
    d = json.loads(os.environ["CW_GH_JSON"])
except Exception:
    sys.exit(1)
# a response for a different number means gh answered a different question
if str(d.get("number")) != os.environ["CW_GH_NUM"]:
    sys.exit(1)
labels = ", ".join(l["name"] for l in d.get("labels", []))
print(f"**#{d.get('number')} — {d.get('title','')}**")
print(f"State: {d.get('state','')}" + (f" · Labels: {labels}" if labels else ""))
print()
print(d.get("body") or "_No description._")
PY
}
