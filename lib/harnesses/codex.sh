# codex cli driver
# unverified: no skip-permissions equivalent flag confirmed, so it stays unsupported
codex_supports() {
    case "$1" in
        continue_last|non_interactive_prompt|model_flag|custom_provider) return 0 ;;
        instructions_file|api_key_login) return 0 ;;
        headless_login) return 0 ;;
        *) return 1 ;;
    esac
}

codex_config_env() {
    printf 'CODEX_HOME=%s\n' "$CW_HARNESS_DIR"
}
# unverified: no model_providers table is written for a custom endpoint, only the provider name

# lists the rollout files codex has written for this account
_codex_rollouts() {
    [[ -d "$CW_HARNESS_DIR/sessions" ]] || return 0
    find "$CW_HARNESS_DIR/sessions" -type f -name 'rollout-*.jsonl' 2>/dev/null | sort
}

# remembers which rollouts existed before a launch, so the new one can be told apart
_codex_snapshot() {
    _CW_CODEX_BEFORE="$(_codex_rollouts)"
}

# unverified: rollout file naming and json-lines layout under $CODEX_HOME/sessions
# prints the id of the one new rollout that mentions this session's notes file, else nothing
codex_session_ref() {
    local marker="${CW_NOTES_FILE:-}"
    [[ -n "$marker" && "${CW_PROMPT:-}" == *"$marker"* ]] || return 0
    CW_CX_BEFORE="${_CW_CODEX_BEFORE:-}" CW_CX_AFTER="$(_codex_rollouts)" CW_CX_MARKER="$marker" \
    python3 - <<'PY' 2>/dev/null
import json, os, re
before = set(filter(None, os.environ["CW_CX_BEFORE"].split("\n")))
after = [p for p in os.environ["CW_CX_AFTER"].split("\n") if p and p not in before]
marker = os.environ["CW_CX_MARKER"]
def mentions(value):
    if isinstance(value, str):
        return marker in value
    if isinstance(value, dict):
        return any(mentions(v) for v in value.values())
    if isinstance(value, list):
        return any(mentions(v) for v in value)
    return False
hits = []
for path in after:
    try:
        with open(path) as f:
            if any(mentions(json.loads(line)) for line in f if line.strip()):
                hits.append(path)
    except Exception:
        continue
uuid = r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$"
m = re.search(uuid, hits[0]) if len(hits) == 1 else None
if m:
    print(m.group(1), end="")
PY
    return 0
}

# sets only the top-level model and model_provider keys in the account's config.toml
# everything else in the file is left byte-identical; anything it cannot edit safely is refused
_codex_write_provider() {
    local provider="$1" model="$2"
    [[ -n "$provider" && "$provider" != "native" ]] || return 0
    # said once per command, however many launch attempts ask again
    [[ -z "${_CW_CODEX_REFUSED:-}" ]] || return 1
    mkdir -p "$CW_HARNESS_DIR"
    local why
    why=$(CW_TOML="$CW_HARNESS_DIR/config.toml" CW_TOML_PROVIDER="$provider" CW_TOML_MODEL="$model" \
          python3 - <<'PY'
import os, re, shutil, sys, tempfile
path = os.environ["CW_TOML"]
want = [("model_provider", os.environ["CW_TOML_PROVIDER"]), ("model", os.environ["CW_TOML_MODEL"])]

def refuse(msg):
    print(msg, end="")
    sys.exit(3)

# a toml basic string; every control character and DEL goes out as a \u escape
def enc(v):
    out = []
    for ch in v:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif o < 0x20 or o == 0x7F:
            out.append("\\u%04x" % o)
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'

# bracket depth left open by these lines, ignoring strings and comments
def depth(lines):
    d = 0
    for line in lines:
        i = 0
        while i < len(line):
            c = line[i]
            if c == "#":
                break
            if c == '"':
                i += 1
                while i < len(line) and line[i] != '"':
                    i += 2 if line[i] == "\\" else 1
            elif c == "'":
                i += 1
                while i < len(line) and line[i] != "'":
                    i += 1
            elif c in "[{":
                d += 1
            elif c in "]}":
                d -= 1
            i += 1
    return d

try:
    with open(path) as f:
        original = f.read()
except FileNotFoundError:
    original = None
except Exception as e:
    refuse(f"cannot read it ({e})")

lines = [] if original is None else original.splitlines(keepends=True)
first_table = next((i for i, l in enumerate(lines) if l.lstrip().startswith("[")), len(lines))
top = lines[:first_table]
if any(q in l for l in top for q in ('"' * 3, "'" * 3)):
    refuse("its top level holds a multi-line string")
if depth(top) != 0:
    refuse("its top level holds a multi-line array or table")

plain = re.compile(r"""^\s*[^=]+=\s*("(?:[^"\\]|\\.)*"|'[^']*')\s*(#.*)?$""")
for key, value in want:
    if not value:
        continue
    new_line = f"{key} = {enc(value)}\n"
    key_re = re.compile(r'^\s*(%s|"%s")\s*=' % (re.escape(key), re.escape(key)))
    hits = [i for i, l in enumerate(lines[:first_table]) if key_re.match(l)]
    if len(hits) > 1:
        refuse(f"it sets {key} more than once")
    if hits:
        if not plain.match(lines[hits[0]].rstrip("\r\n")):
            refuse(f"its {key} is not a plain one-line string")
        lines[hits[0]] = new_line
    else:
        lines.insert(0, new_line)
        first_table += 1

result = "".join(lines)
if result == original:
    sys.exit(0)
try:
    import tomllib
except ImportError:
    tomllib = None
if tomllib is not None and original is not None:
    try:
        before, after = tomllib.loads(original), tomllib.loads(result)
    except Exception:
        refuse("it does not parse as toml")
    for key, value in want:
        if value:
            before[key] = value
    if before != after:
        refuse("the edit would change more than the keys cw owns")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".config.toml.")
with os.fdopen(fd, "w") as f:
    f.write(result)
if original is not None:
    shutil.copymode(path, tmp)
os.replace(tmp, path)
PY
    ) && return 0
    _CW_CODEX_REFUSED=1
    _err "Cannot apply provider '$provider' to $CW_HARNESS_DIR/config.toml: ${why:-unknown error}."
    _err "Set model_provider and model in that file yourself; cw left it untouched."
    return 1
}

_codex_base() {
    _codex_write_provider "${CW_PROVIDER:-}" "${CW_MODEL:-}" || return 1
    HARNESS_ENV=("CODEX_HOME=$CW_HARNESS_DIR")
    if [[ -f "$CW_HARNESS_DIR/env" ]]; then
        local -a extra_env=()
        mapfile -t extra_env < <(_harness_env_file "$CW_HARNESS_DIR/env")
        [[ ${#extra_env[@]} -gt 0 ]] && HARNESS_ENV+=("${extra_env[@]}")
    fi
    HARNESS_ARGV=(codex)
    local f
    # unverified: flag ordering around the resume subcommand (before vs after)
    for f in $CW_EXTRA_FLAGS; do HARNESS_ARGV+=("$f"); done
    return 0
}

# unverified: interactive launch argv beyond the bare binary
codex_launch() {
    _codex_base || return 1
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    _codex_snapshot
    return 0
}

# only attempts that can be attributed to this session: its recorded id, then --last
# where cw vouches the directory holds nothing but this session's conversations
# unverified: that codex scopes resume --last to the working directory
codex_resume() {
    local attempt="$1"
    local -a plan=()
    [[ -n "$CW_SESSION_REF" ]] && plan+=(id)
    [[ -n "${CW_CONTINUE_LAST_SAFE:-}" ]] && plan+=(last)
    local step="${plan[$((attempt - 1))]:-}"
    [[ -n "$step" ]] || return 1
    _codex_base || return 1
    case "$step" in
        id)   HARNESS_ARGV+=(resume "$CW_SESSION_REF") ;;
        last) HARNESS_ARGV+=(resume --last) ;;
        *)    return 1 ;;
    esac
    [[ -n "$CW_MODEL" ]] && HARNESS_ARGV+=(--model "$CW_MODEL")
    [[ -n "$CW_PROMPT" ]] && HARNESS_ARGV+=("$CW_PROMPT")
    _codex_snapshot
    return 0
}

codex_doctor() {
    local status detail="null"
    if ! command -v codex >/dev/null 2>&1; then
        status="not_installed"; detail='"codex not found on PATH"'
    elif [[ -f "$CW_HARNESS_DIR/auth.json" || -f "$CW_HARNESS_DIR/env" ]]; then
        status="connected"
    else
        status="not_logged_in"
    fi
    printf '{"harness":"codex","status":"%s","detail":%s}\n' "$status" "$detail"
}

codex_login() {
    HARNESS_ENV=("CODEX_HOME=$CW_HARNESS_DIR")
    HARNESS_ARGV=(codex login)
    [[ -n "${CW_LOGIN_NO_BROWSER:-}" ]] && HARNESS_ARGV+=(--device-auth)
    [[ -n "${CW_LOGIN_API_KEY_STDIN:-}" ]] && HARNESS_ARGV=(codex login --with-api-key)
    return 0
}
