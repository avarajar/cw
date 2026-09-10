# notion needs an internal integration token from the env or ~/.cw/tokens.env
context_credential_notion() {
    [[ -n "${NOTION_TOKEN:-}" ]] && return 0
    [[ -f "$CW_HOME/tokens.env" ]] && grep -q '^NOTION_TOKEN=' "$CW_HOME/tokens.env"
}

context_fetch_notion() {
    local url="$1"
    local page; page=$(printf '%s' "$url" | grep -oE '[a-f0-9]{32}' | head -1)
    [[ -n "$page" ]] || return 1
    local tok="${NOTION_TOKEN:-}"
    [[ -z "$tok" && -f "$CW_HOME/tokens.env" ]] && \
        tok=$(sed -n 's/^NOTION_TOKEN=//p' "$CW_HOME/tokens.env" | head -1)
    [[ -n "$tok" ]] || return 1
    local api="${CW_NOTION_API:-https://api.notion.com}"
    CW_NOTION_TOKEN="$tok" CW_NOTION_PAGE="$page" CW_NOTION_URL="$api" python3 - <<'PY'
import json, os, sys, urllib.request
req = urllib.request.Request(
    f"{os.environ['CW_NOTION_URL']}/v1/blocks/{os.environ['CW_NOTION_PAGE']}/children?page_size=100",
    headers={"Authorization": f"Bearer {os.environ['CW_NOTION_TOKEN']}",
             "Notion-Version": "2022-06-28"},
)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        d = json.load(r)
except Exception as e:
    print(f"_Notion fetch failed: {e}_", file=sys.stderr)
    sys.exit(1)
prefix = {"heading_1": "# ", "heading_2": "## ", "heading_3": "### ",
          "bulleted_list_item": "- ", "numbered_list_item": "1. "}
for b in d.get("results", []):
    t = b.get("type")
    rich = (b.get(t) or {}).get("rich_text") or []
    text = "".join(x.get("plain_text", "") for x in rich)
    if text:
        print(prefix.get(t, "") + text)
PY
}
