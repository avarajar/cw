# linear needs a personal api key from the env or ~/.cw/tokens.env
context_credential_linear() {
    [[ -n "${LINEAR_API_KEY:-}" ]] && return 0
    [[ -f "$CW_HOME/tokens.env" ]] && grep -q '^LINEAR_API_KEY=' "$CW_HOME/tokens.env"
}

context_fetch_linear() {
    local url="$1"
    local id; id=$(printf '%s' "$url" | grep -oE '[A-Z]+-[0-9]+' | head -1)
    [[ -n "$id" ]] || return 1
    local key="${LINEAR_API_KEY:-}"
    [[ -z "$key" && -f "$CW_HOME/tokens.env" ]] && \
        key=$(sed -n 's/^LINEAR_API_KEY=//p' "$CW_HOME/tokens.env" | head -1)
    [[ -n "$key" ]] || return 1
    local api="${CW_LINEAR_API:-https://api.linear.app/graphql}"
    CW_LINEAR_KEY="$key" CW_LINEAR_ID="$id" CW_LINEAR_URL="$api" python3 - <<'PY'
import json, os, sys, urllib.request
q = """query($id:String!){issue(id:$id){identifier title description branchName priority
      comments{nodes{body}}}}"""
req = urllib.request.Request(
    os.environ["CW_LINEAR_URL"],
    data=json.dumps({"query": q, "variables": {"id": os.environ["CW_LINEAR_ID"]}}).encode(),
    headers={"Authorization": os.environ["CW_LINEAR_KEY"], "Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        d = json.load(r)
except Exception as e:
    print(f"_Linear fetch failed: {e}_", file=sys.stderr)
    sys.exit(1)
i = (d.get("data") or {}).get("issue")
if not i:
    sys.exit(1)
print(f"**{i['identifier']} — {i['title']}**")
if i.get("branchName"):
    print(f"Branch: `{i['branchName']}`")
print()
print(i.get("description") or "_No description._")
nodes = (i.get("comments") or {}).get("nodes") or []
if nodes:
    print("\n**Comments**")
    for c in nodes:
        print(f"- {c['body']}")
PY
}
