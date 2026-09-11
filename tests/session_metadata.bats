load helpers/setup

setup() { setup_cw_home; }

# prints one field of a session.json exactly, via argv so nothing is interpolated
session_get() {
    python3 -c 'import json,sys; sys.stdout.write(str(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$1" "$2"
}

@test "a task id with a single quote still writes session.json and resumes on its harness" {
    make_project app >/dev/null
    run "$CW_BIN" work app "fix-o'neil" --harness codex
    [ "$status" -eq 0 ]
    local meta="$CW_HOME/sessions/app/task-fix-o'neil/session.json"
    [ -f "$meta" ]
    [ "$(session_get "$meta" task)" = "fix-o'neil" ]
    [ "$(session_get "$meta" harness)" = "codex" ]
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app "fix-o'neil"
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "codex" ]
    ! grep -q '^bin=claude$' "$CW_FAKE_LOG"
}

@test "a task id with a backslash and a double quote round-trips through session.json" {
    make_project app >/dev/null
    local task='fix\n"quoted"\\back'
    run "$CW_BIN" work app "$task"
    [ "$status" -eq 0 ]
    [ "$(session_get "$CW_HOME/sessions/app/task-$task/session.json" task)" = "$task" ]
}

@test "a task id with a newline round-trips through session.json" {
    make_project app >/dev/null
    local task=$'line-one\nline-two'
    run "$CW_BIN" work app "$task"
    [ "$status" -eq 0 ]
    [ "$(session_get "$CW_HOME/sessions/app/task-$task/session.json" task)" = "$task" ]
}

@test "a model with quotes, a backslash and a newline round-trips through work's session.json" {
    make_project app >/dev/null
    local model=$'m\'o"d\\el\nx'
    run "$CW_BIN" work app fix-auth --model "$model"
    [ "$status" -eq 0 ]
    [ "$(session_get "$CW_HOME/sessions/app/task-fix-auth/session.json" model)" = "$model" ]
}

@test "a model override with a quote on resume is stored verbatim" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth
    run "$CW_BIN" work app fix-auth --model "o'pus"
    [ "$status" -eq 0 ]
    [ "$(session_get "$CW_HOME/sessions/app/task-fix-auth/session.json" model)" = "o'pus" ]
}

@test "a model with a quote round-trips through review's session.json, new and resumed" {
    make_project app >/dev/null
    run "$CW_BIN" review app 123 --model "o'pus"
    [ "$status" -eq 0 ]
    [ "$(session_get "$CW_HOME/sessions/app/review-pr-123/session.json" model)" = "o'pus" ]
    run "$CW_BIN" review app 123 --model "ha\\iku'"
    [ "$status" -eq 0 ]
    [ "$(session_get "$CW_HOME/sessions/app/review-pr-123/session.json" model)" = "ha\\iku'" ]
}

@test "a pasted url cannot execute python through work's session writer" {
    make_project app >/dev/null
    local marker="$BATS_TEST_TMPDIR/pwned"
    local url="https://example.com/a'+str(__import__('os').system('touch $marker'))+'"
    run "$CW_BIN" work app "$url"
    [ ! -e "$marker" ]
    local meta; meta=$(find "$CW_HOME/sessions/app" -name session.json | head -1)
    [ -n "$meta" ]
    [ "$(session_get "$meta" source_url)" = "$url" ]
}

@test "a pasted url cannot execute python through create's session writer" {
    local marker="$BATS_TEST_TMPDIR/pwned2"
    local url="https://example.com/a'+str(__import__('os').system('touch $marker'))+'"
    run "$CW_BIN" create "$url" --account acct --name qurl --dir "$BATS_TEST_TMPDIR/created"
    [ ! -e "$marker" ]
    [ "$(session_get "$CW_HOME/sessions/qurl/task-init/session.json" source_url)" = "$url" ]
}

@test "an unparseable session.json refuses to launch instead of falling back to claude" {
    make_project app >/dev/null
    "$CW_BIN" work app fix-auth --harness codex
    printf '{"harness": "codex", broken' > "$CW_HOME/sessions/app/task-fix-auth/session.json"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to launch"* ]]
    [ "$(call_count)" -eq 0 ]
}

@test "a session.json that is valid json but not an object refuses to launch" {
    make_project app >/dev/null
    "$CW_BIN" review app 123 --harness codex
    echo '["codex"]' > "$CW_HOME/sessions/app/review-pr-123/session.json"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" review app 123
    [ "$status" -ne 0 ]
    [ "$(call_count)" -eq 0 ]
}

@test "an unreadable loop session.json refuses to launch" {
    make_project app >/dev/null
    "$CW_BIN" loop app "check the deploy" --name lp
    printf 'garbage' > "$CW_HOME/sessions/app/loop-lp/session.json"
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" loop app "check the deploy" --name lp
    [ "$status" -ne 0 ]
    [ "$(call_count)" -eq 0 ]
}
