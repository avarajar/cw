load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$BATS_TEST_TMPDIR/fakes"
    cat > "$BATS_TEST_TMPDIR/fakes/gh" <<FAKE
#!/usr/bin/env bash
cat "$BATS_TEST_DIRNAME/fixtures/github-issue.json"
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/gh"
    export PATH="$BATS_TEST_TMPDIR/fakes:$PATH"
}

teardown() { stop_context_stub; }

# ── GitHub ──────────────────────────────────────────────────────────────

@test "github fetch needs no credential" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'; context_credential_github"
    [ "$status" -eq 0 ]
}

@test "github fetch renders the issue body as markdown" {
    run bash -c "source '$BATS_TEST_DIRNAME/../lib/context/github.sh'
                 context_fetch_github https://github.com/org/repo/issues/1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Login button does nothing"* ]]
    [[ "$output" == *"no-op in Safari 17"* ]]
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

# ── cmd_work wiring ─────────────────────────────────────────────────────

@test "work writes the fetched issue into TASK_NOTES.md before launching" {
    make_project app >/dev/null
    run "$CW_BIN" work app https://github.com/org/repo/issues/1
    [ "$status" -eq 0 ]
    run grep -q "no-op in Safari 17" "$CW_HOME/sessions/app/task-issues-1/TASK_NOTES.md"
    [ "$status" -eq 0 ]
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

@test "work keeps the fill-in-Context instruction for a PR when no credential is available" {
    make_project app >/dev/null
    rm -f "$BATS_TEST_TMPDIR/fakes/gh"
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
