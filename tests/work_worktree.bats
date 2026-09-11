load helpers/setup

setup() {
    setup_cw_home
    mkdir -p "$BATS_TEST_TMPDIR/fakes"
    cp "$BATS_TEST_DIRNAME/helpers/fake_gh" "$BATS_TEST_TMPDIR/fakes/gh"
    export CW_FAKE_GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export CW_FAKE_GH_FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    export PATH="$BATS_TEST_TMPDIR/fakes:$PATH"
}

teardown() {
    stop_context_stub
    [[ -n "${BG_PID:-}" ]] && kill "$BG_PID" 2>/dev/null
    true
}

# a registered project whose origin is a local bare repo, so fetch and origin/main work offline
make_origin_project() {
    local name="$1" path
    path="$(make_project "$name")"
    git init -q --bare "$BATS_TEST_TMPDIR/$name-origin.git"
    git -C "$path" remote add origin "$BATS_TEST_TMPDIR/$name-origin.git"
    git -C "$path" push -q origin main
    printf '%s' "$path"
}

# commits on a new branch and leaves the project back on main
commit_on() {
    local path="$1" branch="$2"
    git -C "$path" checkout -q -b "$branch"
    git -C "$path" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work on $branch"
    git -C "$path" checkout -q main
}

branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD; }

worktree_count() { git -C "$1" worktree list --porcelain | grep -c '^worktree '; }

warnings() { printf '%s\n' "$output" | grep -c 'Could not create the worktree' || true; }

# fails when a prompt still asks the agent to set up the workspace itself
no_setup_steps() {
    local prompt="$1" step bad=""
    for step in "Set up the workspace" "git fetch origin" "git branch -D" "git worktree add" \
                "ln -sf" "gh pr view" "Then start working from the .tasks/"; do
        [[ "$prompt" == *"$step"* ]] && bad="$bad [$step]"
    done
    [ -z "$bad" ] || { echo "setup steps left in the prompt:$bad" >&2; return 1; }
}

@test "work demo-app <github issue> --harness codex creates the worktree, writes the issue into TASK_NOTES.md and launches codex in it" {
    local path; path="$(make_origin_project demo-app)"
    run "$CW_BIN" work demo-app https://github.com/org/repo/issues/1 --harness codex
    [ "$status" -eq 0 ]
    local wt="$path/.tasks/issues-1"
    [ -f "$wt/.git" ]
    [ "$(cd "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)" = "$(cd "$path/.git" && pwd -P)" ]
    [ "$(branch_of "$wt")" = "task/issues-1" ]
    [ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$path" rev-parse origin/main)" ]
    [ -L "$wt/TASK_NOTES.md" ]
    [ "$(readlink "$wt/TASK_NOTES.md")" = "$CW_HOME/sessions/demo-app/task-issues-1/TASK_NOTES.md" ]
    grep -q "no-op in Safari 17" "$wt/TASK_NOTES.md"
    [ "$(call_count)" -eq 1 ]
    [ "$(call_field 1 bin)" = "codex" ]
    [ "$(call_field 1 cwd)" = "$wt" ]
    [ "$(warnings)" -eq 0 ]
}

@test "a plain task name gets a worktree on a branch of that name, started from origin/main" {
    local path; path="$(make_origin_project app)"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(branch_of "$path/.tasks/fix-auth")" = "fix-auth" ]
    [ "$(git -C "$path" rev-parse fix-auth)" = "$(git -C "$path" rev-parse origin/main)" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
    no_setup_steps "$(call 1)"
}

@test "a notion page gets a worktree on task/<slug>" {
    local path; path="$(make_origin_project app)"
    run "$CW_BIN" work app https://www.notion.so/Spec-1234567890abcdef1234567890abcdef --harness codex
    [ "$status" -eq 0 ]
    [ "$(branch_of "$path/.tasks/Spec")" = "task/Spec" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/Spec" ]
    no_setup_steps "$(call 1)"
}

@test "a linear issue gets a worktree on the branchName the fetch returned" {
    local path; path="$(make_origin_project app)"
    start_context_stub 200 "$(cat "$BATS_TEST_DIRNAME/fixtures/linear-issue.json")"
    CW_LINEAR_API="$CTX_STUB_URL" LINEAR_API_KEY=lin_test run "$CW_BIN" work app https://linear.app/x/issue/SEI-214 --harness codex
    [ "$status" -eq 0 ]
    [ "$(branch_of "$path/.tasks/SEI-214")" = "jose/sei-214-double-booking" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/SEI-214" ]
    no_setup_steps "$(call 1)"
    [[ "$(call 1)" != *"Branch line"* ]]
}

@test "a linear issue that could not be fetched gets a worktree on task/<id>" {
    local path; path="$(make_origin_project app)"
    run bash -c "unset LINEAR_API_KEY; '$CW_BIN' work app https://linear.app/x/issue/SEI-214 --harness codex"
    [ "$status" -eq 0 ]
    [ "$(branch_of "$path/.tasks/SEI-214")" = "task/SEI-214" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/SEI-214" ]
    no_setup_steps "$(call 1)"
    [[ "$(call 1)" == *"Fill in the Context section of TASK_NOTES.md"* ]]
}

@test "a pull request gets a worktree on its head branch, at the PR's commits rather than the base" {
    local path; path="$(make_origin_project app)"
    commit_on "$path" feature/pr-42
    git -C "$path" push -q origin feature/pr-42
    git -C "$path" branch -q -D feature/pr-42
    run "$CW_BIN" work app https://github.com/org/repo/pull/42 --harness codex
    [ "$status" -eq 0 ]
    local wt="$path/.tasks/pull-42"
    [ "$(branch_of "$wt")" = "feature/pr-42" ]
    [ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$path" rev-parse origin/feature/pr-42)" ]
    [ "$(git -C "$wt" rev-parse HEAD)" != "$(git -C "$path" rev-parse origin/main)" ]
    grep -qx 'https://github.com/org/repo/pull/42' "$CW_FAKE_GH_LOG"
    grep -qx 'headRefName' "$CW_FAKE_GH_LOG"
    [ "$(call_field 1 cwd)" = "$wt" ]
    no_setup_steps "$(call 1)"
}

@test "an existing branch is attached to the new worktree, never deleted or reset" {
    local path; path="$(make_origin_project app)"
    commit_on "$path" fix-auth
    local unpushed; unpushed="$(git -C "$path" rev-parse fix-auth)"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(git -C "$path" rev-parse fix-auth)" = "$unpushed" ]
    [ "$(git -C "$path/.tasks/fix-auth" rev-parse HEAD)" = "$unpushed" ]
    [ "$(branch_of "$path/.tasks/fix-auth")" = "fix-auth" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
    [ "$(warnings)" -eq 0 ]
}

@test "a cw-created worktree links .env, .claude/ and the shared context from the repository root" {
    local path; path="$(make_origin_project app)"
    printf 'A=1\n' > "$path/.env"
    mkdir -p "$path/.claude"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    local wt="$path/.tasks/fix-auth"
    [ "$(readlink "$wt/.env")" = "$path/.env" ]
    [ "$(readlink "$wt/.claude")" = "$path/.claude" ]
    [ "$(readlink "$wt/SHARED_CONTEXT.md")" = "$CW_HOME/sessions/app/SHARED_CONTEXT.md" ]
    [ -f "$wt/SHARED_CONTEXT.md" ]
}

@test "a .env the worktree already has from the repository is left alone" {
    local path; path="$(make_origin_project app)"
    printf 'TRACKED=1\n' > "$path/.env"
    git -C "$path" add .env
    git -C "$path" -c user.email=t@t -c user.name=t commit -q -m env
    git -C "$path" push -q origin main
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ ! -L "$path/.tasks/fix-auth/.env" ]
    [ "$(cat "$path/.tasks/fix-auth/.env")" = "TRACKED=1" ]
}

@test "the init prompt for a cw-created worktree says it is set up and carries no setup steps" {
    local path; path="$(make_origin_project app)"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    local prompt; prompt="$(call 1)"
    [[ "$prompt" == *"already set up"*"$path/.tasks/fix-auth"*"branch fix-auth"* ]]
    [[ "$prompt" == *"SHARED_CONTEXT.md"* ]]
    no_setup_steps "$prompt"
}

@test "with no origin remote, work falls back to agent-driven setup in the project root with one warning" {
    local path; path="$(make_project app)"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(warnings)" -eq 1 ]
    [[ "$(call 1)" == *"Set up the workspace:"*"git worktree add .tasks/fix-auth -b fix-auth"* ]]
    [ "$(call_field 1 cwd)" = "$path" ]
    [ ! -e "$path/.tasks/fix-auth" ]
    [ "$(worktree_count "$path")" -eq 1 ]
}

@test "a worktree git reports as failed after creating it is removed before the fallback" {
    local path; path="$(make_origin_project app)"
    printf '#!/bin/sh\nexit 1\n' > "$path/.git/hooks/post-checkout"
    chmod +x "$path/.git/hooks/post-checkout"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(warnings)" -eq 1 ]
    [ ! -e "$path/.tasks/fix-auth" ]
    [ "$(worktree_count "$path")" -eq 1 ]
    [ -z "$(ls -A "$path/.git/worktrees" 2>/dev/null)" ]
    [[ "$output" == *"kept branch fix-auth, which cw had just created"* ]]
    git -C "$path" show-ref --verify --quiet refs/heads/fix-auth
    [[ "$(call 1)" == *"git worktree add .tasks/fix-auth"* ]]
    [ "$(call_field 1 cwd)" = "$path" ]
}

@test "a branch checked out in another worktree makes work fall back and leaves that branch alone" {
    local path; path="$(make_origin_project app)"
    commit_on "$path" fix-auth
    local keep; keep="$(git -C "$path" rev-parse fix-auth)"
    git -C "$path" worktree add -q "$BATS_TEST_TMPDIR/elsewhere" fix-auth
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(warnings)" -eq 1 ]
    [ ! -e "$path/.tasks/fix-auth" ]
    [ "$(git -C "$path" rev-parse fix-auth)" = "$keep" ]
    [ "$(branch_of "$BATS_TEST_TMPDIR/elsewhere")" = "fix-auth" ]
    [ "$(worktree_count "$path")" -eq 2 ]
    [ "$(call_field 1 cwd)" = "$path" ]
}

@test "an existing path at the worktree location is never touched, and work falls back" {
    local path; path="$(make_origin_project app)"
    mkdir -p "$path/.tasks/fix-auth"
    printf 'mine\n' > "$path/.tasks/fix-auth/keep.txt"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(warnings)" -eq 1 ]
    [ "$(cat "$path/.tasks/fix-auth/keep.txt")" = "mine" ]
    [ "$(worktree_count "$path")" -eq 1 ]
}

@test "a pull request whose branch gh cannot resolve falls back with one warning" {
    local path; path="$(make_origin_project app)"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/fakes/gh"
    run "$CW_BIN" work app https://github.com/org/repo/pull/42 --harness codex
    [ "$status" -eq 0 ]
    [ "$(warnings)" -eq 1 ]
    [[ "$output" == *"Could not create the worktree (gh could not resolve the pull request's branch)"* ]]
    [[ "$(call 1)" == *"Set up the workspace for GitHub PR #42"* ]]
    [ "$(call_field 1 cwd)" = "$path" ]
    [ ! -e "$path/.tasks/pull-42" ]
}

@test "claude on a project with an origin keeps the agent-driven setup and gets no worktree from cw" {
    local path; path="$(make_origin_project app)"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_field 1 bin)" = "claude" ]
    [ "$(call_field 1 cwd)" = "$path" ]
    [ ! -e "$path/.tasks/fix-auth" ]
    [ "$(worktree_count "$path")" -eq 1 ]
    [ "$(warnings)" -eq 0 ]
    [[ "$(call 1)" == *"git worktree add .tasks/fix-auth -b fix-auth"* ]]
}

@test "codex resume opens in the worktree cw created and uses --last there" {
    local path; path="$(make_origin_project app)"
    "$CW_BIN" work app fix-auth --harness codex
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 1 ]
    [ "$(call_field 1 bin)" = "codex" ]
    [ "$(call_argv 1 | sed -n 1p)" = "resume" ]
    [ "$(call_argv 1 | sed -n 2p)" = "--last" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
}

@test "pi resume opens in the worktree cw created" {
    local path; path="$(make_origin_project app)"
    "$CW_BIN" work app fix-auth --harness pi
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 1 ]
    [ "$(call_field 1 bin)" = "pi" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
}

@test "opencode resume opens in the worktree cw created" {
    local path; path="$(make_origin_project app)"
    "$CW_BIN" work app fix-auth --harness opencode
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
    rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 1 ]
    [ "$(call_field 1 bin)" = "opencode" ]
    [ "$(call_field 1 cwd)" = "$path/.tasks/fix-auth" ]
}

@test "review, open and plan on codex never create a worktree" {
    local path; path="$(make_origin_project app)"
    run "$CW_BIN" review app 123 --harness codex
    [ "$status" -eq 0 ]
    run "$CW_BIN" open app --harness codex
    [ "$status" -eq 0 ]
    run "$CW_BIN" plan app "migrate auth" --harness codex
    [ "$status" -eq 0 ]
    [ "$(call_count)" -eq 3 ]
    [ "$(worktree_count "$path")" -eq 1 ]
    [ -z "$(ls -A "$path/.tasks" 2>/dev/null)" ]
}

@test "two overlapping new runs of one task never remove the first run's worktree or its uncommitted work" {
    local path; path="$(make_origin_project app)"
    local hold="$BATS_TEST_TMPDIR/hold"
    # holds a fetch in upload-pack until released, the way a credential prompt would
    cat > "$BATS_TEST_TMPDIR/slow-upload-pack" <<SLOW
#!/usr/bin/env bash
if [[ -n "\${CW_TEST_HOLD:-}" ]]; then
    touch "$hold.waiting"
    while [[ ! -e "$hold.release" ]]; do sleep 0.05; done
fi
exec git upload-pack "\$@"
SLOW
    chmod +x "$BATS_TEST_TMPDIR/slow-upload-pack"
    git -C "$path" config remote.origin.uploadpack "$BATS_TEST_TMPDIR/slow-upload-pack"
    CW_TEST_HOLD=1 "$CW_BIN" work app fix-auth --harness codex > "$BATS_TEST_TMPDIR/second.out" 2>&1 3>&- &
    BG_PID=$!
    local i
    for i in $(seq 1 200); do [[ -e "$hold.waiting" ]] && break; sleep 0.05; done
    [ -e "$hold.waiting" ]
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    local wt="$path/.tasks/fix-auth"
    [ "$(branch_of "$wt")" = "fix-auth" ]
    printf 'unsaved\n' > "$wt/agent-work.txt"
    touch "$hold.release"
    wait "$BG_PID"
    BG_PID=""
    [ "$(cat "$wt/agent-work.txt")" = "unsaved" ]
    [ "$(branch_of "$wt")" = "fix-auth" ]
    [ "$(worktree_count "$path")" -eq 2 ]
    [ "$(grep -c 'Could not create the worktree' "$BATS_TEST_TMPDIR/second.out")" -eq 1 ]
}

@test "a fallback never unregisters another worktree, even one whose directory is missing" {
    local path; path="$(make_origin_project app)"
    git -C "$path" worktree add -q -b side "$BATS_TEST_TMPDIR/unmounted" main
    commit_on "$path" fix-auth
    git -C "$path" worktree add -q "$BATS_TEST_TMPDIR/elsewhere" fix-auth
    mv "$BATS_TEST_TMPDIR/unmounted" "$BATS_TEST_TMPDIR/unmounted.away"
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(warnings)" -eq 1 ]
    mv "$BATS_TEST_TMPDIR/unmounted.away" "$BATS_TEST_TMPDIR/unmounted"
    [ "$(branch_of "$BATS_TEST_TMPDIR/unmounted")" = "side" ]
    [ "$(worktree_count "$path")" -eq 3 ]
}

@test "the fallback prompt tells a non-claude agent to attach an existing branch, never to delete it" {
    local path; path="$(make_project app)"
    commit_on "$path" fix-auth
    run "$CW_BIN" work app fix-auth --harness codex
    [ "$status" -eq 0 ]
    [ "$(warnings)" -eq 1 ]
    [[ "$(call 1)" != *"git branch -D"* ]]
    [[ "$(call 1)" == *"If branch fix-auth exists locally, do not delete or reset it: attach the worktree to it with \`git worktree add .tasks/fix-auth fix-auth\` and skip step 3."* ]]
    [[ "$(call 1)" == *"git worktree add .tasks/fix-auth -b fix-auth"* ]]
}

@test "no non-claude fallback prompt asks the agent to delete a branch, for any task source" {
    make_project app >/dev/null
    local t bad="" n=0
    for t in plain-task https://github.com/org/repo/issues/1 https://github.com/org/repo/pull/42 \
             https://linear.app/x/issue/SEI-214 https://www.notion.so/Spec-1234567890abcdef1234567890abcdef; do
        rm -f "$CW_FAKE_LOG" "$CW_FAKE_LOG.n"
        run bash -c "unset LINEAR_API_KEY NOTION_TOKEN; '$CW_BIN' work app '$t' --harness codex"
        [[ "$(call 1)" == *"git branch -D"* ]] && bad="$bad [$t deletes]"
        [[ "$(call 1)" == *"do not delete or reset it: attach the worktree to it"* ]] || bad="$bad [$t no attach]"
        n=$((n + 1))
    done
    [ "$n" -eq 5 ]
    [ -z "$bad" ] || { echo "$bad" >&2; return 1; }
}

@test "claude's legacy prompt still carries its git branch -D step" {
    make_project app >/dev/null
    run "$CW_BIN" work app fix-auth
    [ "$status" -eq 0 ]
    [[ "$(call 1)" == *"2. If branch fix-auth exists locally, delete it: git branch -D fix-auth (ignore errors)"* ]]
}

@test "a branch name git would reject is refused before cw fetches or runs git with it" {
    local path; path="$(make_origin_project app)"
    local body
    body=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["data"]["issue"]["branchName"]="bad..name"; print(json.dumps(d))' \
        "$BATS_TEST_DIRNAME/fixtures/linear-issue.json")
    start_context_stub 200 "$body"
    git -C "$path" remote set-url origin "$BATS_TEST_TMPDIR/no-such-origin.git"
    CW_LINEAR_API="$CTX_STUB_URL" LINEAR_API_KEY=lin_test run "$CW_BIN" work app https://linear.app/x/issue/SEI-214 --harness codex
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not create the worktree ('bad..name' is not a valid branch name)"* ]]
    [ ! -e "$path/.tasks/SEI-214" ]
}
