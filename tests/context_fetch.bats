load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$BATS_TEST_TMPDIR/fakes"
    # a copy, not a link, so a test that rewrites fakes/gh cannot clobber the helper
    cp "$BATS_TEST_DIRNAME/helpers/fake_gh" "$BATS_TEST_TMPDIR/fakes/gh"
    export CW_FAKE_GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export CW_FAKE_GH_FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    export PATH="$BATS_TEST_TMPDIR/fakes:$PATH"
}

# a git repo whose origin is some other github repository
make_unrelated_repo() {
    local dir="$BATS_TEST_TMPDIR/unrelated"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" remote add origin https://github.com/evil/unrelated.git
    printf '%s' "$dir"
}

teardown() { stop_context_stub; }

# ── GitHub ──────────────────────────────────────────────────────────────

@test "github fetch needs no credential" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'; context_credential_github"
    [ "$status" -eq 0 ]
}

@test "github reports no credential when gh is not on PATH" {
    mkdir -p "$BATS_TEST_TMPDIR/emptybin"
    run bash -c "export PATH='$BATS_TEST_TMPDIR/emptybin'
                 source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_credential_github"
    [ "$status" -ne 0 ]
}

@test "github fetch renders the issue body as markdown" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Login button does nothing"* ]]
    [[ "$output" == *"no-op in Safari 17"* ]]
}

@test "github fetch hands gh the full url, never a bare number" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/7"
    [ "$status" -eq 0 ]
    run sed -n 4p "$CW_FAKE_GH_LOG"
    [ "$output" = "https://github.com/org/repo/issues/7" ]
}

@test "github fetch from inside an unrelated repo still fetches the linked issue" {
    local other; other="$(make_unrelated_repo)"
    run bash -c "cd '$other'
                 source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/7"
    [ "$status" -eq 0 ]
    [[ "$output" == *"body-of-org/repo#7"* ]]
    [[ "$output" != *"evil/unrelated"* ]]
}

@test "github fetch ignores a trailing comment anchor instead of reading its number" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github 'https://github.com/org/repo/issues/7#issuecomment-99'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"body-of-org/repo#7"* ]]
}

@test "github fetch uses gh pr view for a pull request url" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/pull/42"
    [ "$status" -eq 0 ]
    [ "$(sed -n 2p "$CW_FAKE_GH_LOG")" = "pr" ]
    [ "$(sed -n 4p "$CW_FAKE_GH_LOG")" = "https://github.com/org/repo/pull/42" ]
}

@test "github fetch refuses a url that names no issue or pull request" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/releases/1"
    [ "$status" -ne 0 ]
    [ ! -f "$CW_FAKE_GH_LOG" ]
}

@test "github fetch fails cleanly on a 404" {
    cat > "$BATS_TEST_TMPDIR/fakes/gh" <<'FAKE'
#!/usr/bin/env bash
echo "GraphQL: Could not resolve to an issue (repository.issue)" >&2
exit 1
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/gh"
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/999"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "github fetch fails cleanly on a 401" {
    cat > "$BATS_TEST_TMPDIR/fakes/gh" <<'FAKE'
#!/usr/bin/env bash
echo "HTTP 401: Bad credentials" >&2
exit 1
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/gh"
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/1"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "github fetch never trusts stdout from a failed gh invocation" {
    cat > "$BATS_TEST_TMPDIR/fakes/gh" <<FAKE
#!/usr/bin/env bash
cat "$BATS_TEST_DIRNAME/fixtures/github-issue.json"
exit 1
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/gh"
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/1"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "github fetch fails cleanly when gh exits 0 with nothing to show" {
    cat > "$BATS_TEST_TMPDIR/fakes/gh" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/gh"
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/1"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# ── Linear ──────────────────────────────────────────────────────────────

@test "linear reports no credential when the env var is unset" {
    run bash -c "unset LINEAR_API_KEY
                 source '$BATS_TEST_DIRNAME/../lib/context/linear.sh'
                 context_credential_linear"
    [ "$status" -ne 0 ]
}

@test "linear reports a credential when the env var is set" {
    run bash -c "export LINEAR_API_KEY=lin_test
                 source '$BATS_TEST_DIRNAME/../lib/context/linear.sh'
                 context_credential_linear"
    [ "$status" -eq 0 ]
}

@test "linear fetch renders the issue as markdown" {
    start_context_stub 200 "$(cat "$BATS_TEST_DIRNAME/fixtures/linear-issue.json")"
    run bash -c "export LINEAR_API_KEY=lin_test CW_LINEAR_API='$CTX_STUB_URL'
                 source '$BATS_TEST_DIRNAME/../lib/context/linear.sh'
                 context_fetch_linear https://linear.app/x/issue/SEI-214"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SEI-214"* ]]
    [[ "$output" == *"Two guests can book the same slot."* ]]
    [[ "$output" == *"Repro needs two browsers."* ]]
}

@test "linear fetch fails cleanly on a 404" {
    start_context_stub 404 '{"errors":"not found"}'
    run bash -c "export LINEAR_API_KEY=lin_test CW_LINEAR_API='$CTX_STUB_URL'
                 source '$BATS_TEST_DIRNAME/../lib/context/linear.sh'
                 context_fetch_linear https://linear.app/x/issue/SEI-214 2>/dev/null"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "linear fetch fails cleanly on a 401" {
    start_context_stub 401 '{"errors":"unauthorized"}'
    run bash -c "export LINEAR_API_KEY=lin_bad CW_LINEAR_API='$CTX_STUB_URL'
                 source '$BATS_TEST_DIRNAME/../lib/context/linear.sh'
                 context_fetch_linear https://linear.app/x/issue/SEI-214 2>/dev/null"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# ── Notion ──────────────────────────────────────────────────────────────

@test "notion reports no credential when the token is unset" {
    run bash -c "unset NOTION_TOKEN
                 source '$BATS_TEST_DIRNAME/../lib/context/notion.sh'
                 context_credential_notion"
    [ "$status" -ne 0 ]
}

@test "notion reports a credential when the token is set" {
    run bash -c "export NOTION_TOKEN=secret_test
                 source '$BATS_TEST_DIRNAME/../lib/context/notion.sh'
                 context_credential_notion"
    [ "$status" -eq 0 ]
}

@test "notion fetch renders the page as markdown" {
    start_context_stub 200 "$(cat "$BATS_TEST_DIRNAME/fixtures/notion-page.json")"
    run bash -c "export NOTION_TOKEN=secret_test CW_NOTION_API='$CTX_STUB_URL'
                 source '$BATS_TEST_DIRNAME/../lib/context/notion.sh'
                 context_fetch_notion https://notion.so/Spec-1234567890abcdef1234567890abcdef"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Spec"* ]]
    [[ "$output" == *"Sessions expire after 30 days."* ]]
}

@test "notion fetch fails cleanly on a 404" {
    start_context_stub 404 '{"object":"error"}'
    run bash -c "export NOTION_TOKEN=secret_test CW_NOTION_API='$CTX_STUB_URL'
                 source '$BATS_TEST_DIRNAME/../lib/context/notion.sh'
                 context_fetch_notion https://notion.so/Spec-1234567890abcdef1234567890abcdef 2>/dev/null"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "notion fetch fails cleanly on a 401" {
    start_context_stub 401 '{"object":"error"}'
    run bash -c "export NOTION_TOKEN=secret_bad CW_NOTION_API='$CTX_STUB_URL'
                 source '$BATS_TEST_DIRNAME/../lib/context/notion.sh'
                 context_fetch_notion https://notion.so/Spec-1234567890abcdef1234567890abcdef 2>/dev/null"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# ── _context_write_notes ────────────────────────────────────────────────

@test "_context_write_notes replaces the Context section in place" {
    local notes="$BATS_TEST_TMPDIR/TASK_NOTES.md"
    printf '# Task: t\n\n## Context\n<!-- placeholder -->\n\n## Objective\n<!-- x -->\n' > "$notes"
    run bash -c "source '$CW_BIN'; _context_write_notes '$notes' 'fetched body here'"
    [ "$status" -eq 0 ]
    run grep -c "placeholder" "$notes"
    [ "$output" = "0" ]
    run grep -q "fetched body here" "$notes"
    [ "$status" -eq 0 ]
    run grep -q "## Objective" "$notes"
    [ "$status" -eq 0 ]
}

@test "_context_write_notes treats a backslash-laden body as literal text" {
    local notes="$BATS_TEST_TMPDIR/TASK_NOTES.md"
    printf '# Task: t\n\n## Context\n<!-- placeholder -->\n\n## Objective\n<!-- x -->\n' > "$notes"
    run bash -c "source '$CW_BIN'; _context_write_notes '$notes' 'See ref \\1 and \\g<name> for details'"
    [ "$status" -eq 0 ]
    run grep -F -q 'See ref \1 and \g<name> for details' "$notes"
    [ "$status" -eq 0 ]
}

@test "_context_write_notes is a no-op when the notes file does not exist" {
    run bash -c "source '$CW_BIN'; _context_write_notes '$BATS_TEST_TMPDIR/missing.md' 'x'"
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/missing.md" ]
}

@test "_context_write_notes neutralizes a forged heading so it cannot outlive a clean re-fetch" {
    local notes="$BATS_TEST_TMPDIR/TASK_NOTES.md"
    printf '# Task: t\n\n## Context\n<!-- placeholder -->\n\n## Objective\n<!-- x -->\n' > "$notes"
    local script="$BATS_TEST_TMPDIR/inject.sh"
    cat > "$script" <<SCRIPT
source '$CW_BIN'
_context_write_notes '$notes' 'INJECTED
## Objective
HIJACK'
_context_write_notes '$notes' 'clean body'
SCRIPT
    run bash "$script"
    [ "$status" -eq 0 ]
    run grep -c "HIJACK" "$notes"
    [ "$output" = "0" ]
    run grep -q "clean body" "$notes"
    [ "$status" -eq 0 ]
    run bash -c "grep -c '^## Objective\$' '$notes'"
    [ "$output" = "1" ]
}

@test "_context_write_notes writes a body too large for argv/environ" {
    local notes="$BATS_TEST_TMPDIR/TASK_NOTES.md"
    printf '# Task: t\n\n## Context\n<!-- placeholder -->\n\n## Objective\n<!-- x -->\n' > "$notes"
    local bigfile="$BATS_TEST_TMPDIR/big.txt"
    python3 -c "print('x' * 2000000)" > "$bigfile"
    # the body reaches the function as one argument via command substitution,
    # never as a single argv/environ string handed to execve — that's the fix
    run bash -c "source '$CW_BIN'; _context_write_notes '$notes' \"\$(cat '$bigfile')\""
    [ "$status" -eq 0 ]
    run grep -c "xxxxxxxxxx" "$notes"
    [ "$status" -eq 0 ]
    run grep -q "<!-- placeholder -->" "$notes"
    [ "$status" -ne 0 ]
}

@test "_context_write_notes removes its temp file when interrupted mid-write" {
    local notes="$BATS_TEST_TMPDIR/TASK_NOTES.md"
    printf '# Task: t\n\n## Context\n<!-- placeholder -->\n' > "$notes"
    local slowbin="$BATS_TEST_TMPDIR/slowbin"
    mkdir -p "$slowbin"
    local faketmp="$BATS_TEST_TMPDIR/faketmp"
    mkdir -p "$faketmp"
    # macOS mktemp ignores TMPDIR, so a fake mktemp pins the file where we can watch it
    cat > "$slowbin/mktemp" <<FAKE
#!/usr/bin/env bash
f="$faketmp/tmp.\$\$"
touch "\$f"
printf '%s\n' "\$f"
FAKE
    chmod +x "$slowbin/mktemp"
    cat > "$slowbin/python3" <<'FAKE'
#!/usr/bin/env bash
sleep 1
FAKE
    chmod +x "$slowbin/python3"
    PATH="$slowbin:$PATH" bash -c "
        source '$CW_BIN'
        _context_write_notes '$notes' 'body text'
    " &
    local pid=$!
    sleep 0.3
    kill -TERM "$pid"
    wait "$pid" 2>/dev/null || true
    [ -z "$(find "$faketmp" -type f 2>/dev/null)" ]
}

@test "_context_fetch_for_task fails when writing the notes fails, instead of reporting success" {
    mkdir -p "$CW_HOME/context"
    cat > "$CW_HOME/context/dummy.sh" <<'EOF'
context_credential_dummy() { return 0; }
context_fetch_dummy() { echo 'some content'; return 0; }
EOF
    local notes="$BATS_TEST_TMPDIR/TASK_NOTES.md"
    printf '## Context\nplaceholder\n' > "$notes"
    run bash -c "export CW_HOME='$CW_HOME'
                 source '$CW_BIN'
                 _context_write_notes() { return 1; }
                 _context_fetch_for_task dummy http://example.com/x '$notes'"
    [ "$status" -ne 0 ]
}

# ── cmd_work wiring ─────────────────────────────────────────────────────

@test "work writes the fetched issue into TASK_NOTES.md before launching" {
    make_project app >/dev/null
    run "$CW_BIN" work app https://github.com/org/repo/issues/1
    [ "$status" -eq 0 ]
    run grep -q "no-op in Safari 17" "$CW_HOME/sessions/app/task-issues-1/TASK_NOTES.md"
    [ "$status" -eq 0 ]
}

@test "work run from inside an unrelated repo writes the linked issue, not the cwd's" {
    make_project app >/dev/null
    local other; other="$(make_unrelated_repo)"
    run bash -c "cd '$other' && '$CW_BIN' work app https://github.com/org/repo/issues/7"
    [ "$status" -eq 0 ]
    local notes="$CW_HOME/sessions/app/task-issues-7/TASK_NOTES.md"
    run grep -q "body-of-org/repo#7" "$notes"
    [ "$status" -eq 0 ]
    run grep -q "evil/unrelated" "$notes"
    [ "$status" -ne 0 ]
}

@test "work drops the fill-in-Context instruction from the prompt when the fetch succeeded" {
    make_project app >/dev/null
    run "$CW_BIN" work app https://github.com/org/repo/issues/1
    [ "$status" -eq 0 ]
    [[ "$(call 1)" != *"Fill in the TASK_NOTES.md Context section"* ]]
}

@test "work keeps the fill-in-Context instruction when no credential is available" {
    make_project app >/dev/null
    run bash -c "unset LINEAR_API_KEY; '$CW_BIN' work app https://linear.app/x/issue/SEI-214"
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"Fill in the TASK_NOTES.md Context section"* ]]
}

@test "work drops the fill-in-Context instruction for a PR and renumbers the final step" {
    make_project app >/dev/null
    run "$CW_BIN" work app https://github.com/org/repo/pull/42
    [ "$status" -eq 0 ]
    [[ "$(call 1)" != *"Fill in the TASK_NOTES.md Context section"* ]]
    [[ "$(call 1)" == *$'\n8. Then start working from the .tasks/pull-42/ directory.'* ]]
}

@test "work keeps the fill-in-Context instruction for a PR when gh cannot fetch it" {
    make_project app >/dev/null
    cat > "$BATS_TEST_TMPDIR/fakes/gh" <<'FAKE'
#!/usr/bin/env bash
exit 127
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/gh"
    run "$CW_BIN" work app https://github.com/org/repo/pull/42
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"Fill in the TASK_NOTES.md Context section with the PR details."* ]]
    [[ "$(call 1)" == *$'\n9. Then start working from the .tasks/pull-42/ directory.'* ]]
}

@test "work still launches when no credential is available" {
    make_project app >/dev/null
    run bash -c "unset LINEAR_API_KEY; '$CW_BIN' work app https://linear.app/x/issue/SEI-214"
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 1 ]
}

@test "work skips the fetch and warns exactly once when no credential is available" {
    make_project app >/dev/null
    run bash -c "unset LINEAR_API_KEY; '$CW_BIN' work app https://linear.app/x/issue/SEI-214"
    [ "$status" -eq 0 ]
    local warnings
    warnings=$(printf '%s\n' "$output" | grep -c "No linear credential")
    [ "$warnings" -eq 1 ]
}

@test "tokens are not exported into the harness process" {
    make_project app >/dev/null
    local argvlog="$BATS_TEST_TMPDIR/canary-argv.log"
    local envlog="$BATS_TEST_TMPDIR/canary-env.log"
    cat > "$BATS_TEST_TMPDIR/fakes/claude" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$argvlog"
env > "$envlog"
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/claude"
    LINEAR_API_KEY=lin_secret_canary run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    run grep -q 'lin_secret_canary' "$argvlog"
    [ "$status" -ne 0 ]
    run grep -q 'lin_secret_canary' "$envlog"
    [ "$status" -ne 0 ]
}

@test "tokens are not exported into the harness process even when the fetch runs" {
    make_project app >/dev/null
    local argvlog="$BATS_TEST_TMPDIR/canary-argv2.log"
    local envlog="$BATS_TEST_TMPDIR/canary-env2.log"
    cat > "$BATS_TEST_TMPDIR/fakes/claude" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$argvlog"
env > "$envlog"
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/claude"
    start_context_stub 200 "$(cat "$BATS_TEST_DIRNAME/fixtures/linear-issue.json")"
    CW_LINEAR_API="$CTX_STUB_URL" LINEAR_API_KEY=lin_secret_canary run "$CW_BIN" work app https://linear.app/x/issue/SEI-214
    [ "$status" -eq 0 ]
    run grep -q "double-booking" "$CW_HOME/sessions/app/task-SEI-214/TASK_NOTES.md"
    [ "$status" -eq 0 ]
    run grep -q 'lin_secret_canary' "$argvlog"
    [ "$status" -ne 0 ]
    run grep -q 'lin_secret_canary' "$envlog"
    [ "$status" -ne 0 ]
}

@test "tokens exported by the caller's own shell do not reach cw open either" {
    make_project app >/dev/null
    local argvlog="$BATS_TEST_TMPDIR/canary-argv3.log"
    local envlog="$BATS_TEST_TMPDIR/canary-env3.log"
    cat > "$BATS_TEST_TMPDIR/fakes/claude" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$argvlog"
env > "$envlog"
exit 0
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/claude"
    LINEAR_API_KEY=lin_secret_canary NOTION_TOKEN=notion_secret_canary run "$CW_BIN" open app
    [ "$status" -eq 0 ]
    run grep -Eq 'lin_secret_canary|notion_secret_canary' "$argvlog"
    [ "$status" -ne 0 ]
    run grep -Eq 'lin_secret_canary|notion_secret_canary' "$envlog"
    [ "$status" -ne 0 ]
}
