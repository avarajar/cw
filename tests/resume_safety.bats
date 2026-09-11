load helpers/setup

UUID_A=11111111-2222-3333-4444-555555555555
UUID_B=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee

setup() {
    setup_cw_home
    mkdir -p "$CW_HOME/accounts/acct/codex" "$BATS_TEST_TMPDIR/fakes"
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "codex"
json.dump(m, open(p, "w"))
PY
    # writes rollouts the way codex is believed to, then records the call via the shared fake
    cat > "$BATS_TEST_TMPDIR/fakes/codex" <<FAKE
#!/usr/bin/env bash
write_rollout() {
    local id="\$1" text="\$2" d="\$CODEX_HOME/sessions/2026/09/10"
    mkdir -p "\$d"
    python3 - "\$d/rollout-2026-09-10T00-00-00-\$id.jsonl" "\$text" "\$PWD" <<'PY'
import json, sys
p, text, cwd = sys.argv[1:4]
with open(p, "w") as f:
    f.write(json.dumps({"type": "session_meta", "payload": {"cwd": cwd}}) + "\n")
    f.write(json.dumps({"type": "message", "role": "user", "content": [{"type": "input_text", "text": text}]}) + "\n")
PY
}
if [[ "\${1:-}" != resume ]]; then
    [[ -n "\${FAKE_ROLLOUT_ID:-}" ]] && write_rollout "\$FAKE_ROLLOUT_ID" "\${@: -1}"
    [[ -n "\${FAKE_OTHER_ROLLOUT_ID:-}" ]] && write_rollout "\$FAKE_OTHER_ROLLOUT_ID" "\${FAKE_OTHER_TEXT:-another task}"
fi
exec "$BATS_TEST_DIRNAME/fakes/codex" "\$@"
FAKE
    chmod +x "$BATS_TEST_TMPDIR/fakes/codex"
    export PATH="$BATS_TEST_TMPDIR/fakes:$PATH"
}

meta_get() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' "$1" "$2"
}

META="sessions/app/task-fix-auth/session.json"

@test "a new codex task records the id of the one rollout that mentions its notes file" {
    local path; path="$(make_project app)"
    FAKE_ROLLOUT_ID=$UUID_A run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(meta_get "$CW_HOME/$META" harness_session_id)" = "$UUID_A" ]
    [ "$(meta_get "$CW_HOME/$META" harness_workdir)" = "$path" ]
}

@test "a rollout written by a concurrent task is never recorded as this session's" {
    make_project app >/dev/null
    FAKE_OTHER_ROLLOUT_ID=$UUID_B FAKE_OTHER_TEXT="other task notes /x/TASK_NOTES.md" \
        run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ -z "$(meta_get "$CW_HOME/$META" harness_session_id)" ]
}

@test "the right rollout is recorded when a concurrent task wrote one at the same time" {
    make_project app >/dev/null
    FAKE_ROLLOUT_ID=$UUID_A FAKE_OTHER_ROLLOUT_ID=$UUID_B run "$CW_BIN" work app fix-auth
    [ "$(meta_get "$CW_HOME/$META" harness_session_id)" = "$UUID_A" ]
}

@test "two new rollouts that both mention this session record nothing" {
    make_project app >/dev/null
    local notes="$CW_HOME/sessions/app/task-fix-auth/TASK_NOTES.md"
    FAKE_ROLLOUT_ID=$UUID_A FAKE_OTHER_ROLLOUT_ID=$UUID_B FAKE_OTHER_TEXT="also $notes" \
        run "$CW_BIN" work app fix-auth
    [ -z "$(meta_get "$CW_HOME/$META" harness_session_id)" ]
}

@test "resume tries the recorded session id first" {
    make_project app >/dev/null
    FAKE_ROLLOUT_ID=$UUID_A "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 1 ]
    [ "$(call_argv 1 | sed -n 1p)" = "resume" ]
    [ "$(call_argv 1 | sed -n 2p)" = "$UUID_A" ]
}

@test "resume in the shared project root never uses --last and starts fresh from the notes" {
    local path; path="$(make_project app)"
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 1 ]
    [ "$(grep -c -- '^arg=--last$' "$CW_FAKE_LOG")" -eq 0 ]
    [ "$(call_argv 1 | sed -n 1p)" != "resume" ]
    [ "$(call_field 1 cwd)" = "$path" ]
    [[ "$(call 1)" == *"could not be resumed"*"$CW_HOME/sessions/app/task-fix-auth/TASK_NOTES.md"* ]]
    [ "$(printf '%s\n' "$output" | grep -c 'No earlier codex conversation')" -eq 1 ]
}

@test "a worktree this session never launched in is not trusted for --last, then is once used" {
    local path; path="$(make_project app)"
    "$CW_BIN" work app fix-auth
    mkdir -p "$path/.tasks/fix-auth"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 1 ]
    [ "$(grep -c -- '^arg=--last$' "$CW_FAKE_LOG")" -eq 0 ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
    [ "$(meta_get "$CW_HOME/$META" harness_workdir)" = "$path/.tasks/fix-auth" ]
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$(call_argv 1 | sed -n 1p)" = "resume" ]
    [ "$(call_argv 1 | sed -n 2p)" = "--last" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
}

@test "a failed id resume falls through to a fresh start, not to --last in the root" {
    make_project app >/dev/null
    FAKE_ROLLOUT_ID=$UUID_A "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 0" run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 2 ]
    [ "$(call_argv 1 | sed -n 2p)" = "$UUID_A" ]
    [ "$(call_argv 2 | sed -n 1p)" != "resume" ]
    [[ "$(call 2)" == *"could not be resumed"* ]]
}

@test "a codex review resume never uses --last in the shared root" {
    make_project app >/dev/null
    "$CW_BIN" review app 123
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" review app 123
    [ "$(call_count)" -eq 1 ]
    [ "$(grep -c -- '^arg=--last$' "$CW_FAKE_LOG")" -eq 0 ]
    [[ "$(call 1)" == *"could not be resumed"*"REVIEW_NOTES.md"* ]]
}

@test "opencode resume never uses --continue and starts fresh from the notes" {
    "$CW_BIN" account add oc --harness opencode >/dev/null
    make_project app >/dev/null
    set_project_account app oc
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "opencode" ]
    [ "$(grep -c -- '^arg=--continue$' "$CW_FAKE_LOG")" -eq 0 ]
    [[ "$(call 1)" == *"could not be resumed"*"TASK_NOTES.md"* ]]
    [[ "$output" == *"No earlier opencode conversation"* ]]
}

@test "opencode resume uses a recorded session id when there is one" {
    "$CW_BIN" account add oc --harness opencode >/dev/null
    make_project app >/dev/null
    set_project_account app oc
    "$CW_BIN" work app fix-auth
    python3 - "$CW_HOME/$META" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness_session_id"] = "ses_123"
json.dump(m, open(p, "w"))
PY
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 1 ]
    call_argv 1 | grep -qx -- '--session'
    call_argv 1 | grep -qx 'ses_123'
}

@test "pi resume says it is starting fresh and hands pi the notes file" {
    "$CW_BIN" account add pa --harness pi >/dev/null
    make_project app >/dev/null
    set_project_account app pa
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 1 ]
    [ "$(call_field 1 bin)" = "pi" ]
    [[ "$(call 1)" == *"could not be resumed"*"TASK_NOTES.md"* ]]
    [[ "$output" == *"No earlier pi conversation"* ]]
}

@test "claude's resume chain ends at its own third attempt, with no extra fresh launch" {
    make_project app >/dev/null
    python3 - "$CW_HOME/accounts/acct/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p)); m["harness"] = "claude"
json.dump(m, open(p, "w"))
PY
    "$CW_BIN" work app fix-auth
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    CW_FAKE_EXIT_SEQ="1 1 1" run "$CW_BIN" work app fix-auth
    [ "$(call_count)" -eq 3 ]
    [[ "$output" != *"No earlier"* ]]
    run grep -q harness_workdir "$CW_HOME/$META"
    [ "$status" -ne 0 ]
}
