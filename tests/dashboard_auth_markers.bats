load helpers/setup

setup() { setup_cw_home; }

# cross-checks lib/dashboard/server.py's HARNESS_AUTH_MARKERS against what each
# driver's own doctor logic treats as a login marker. The two live in separate
# files with no shared source of truth; this test makes their drift detectable:
# any marker file that flips <h>_doctor to "connected" must also flip
# harness_authenticated() to True, for every harness with a driver.
@test "dashboard auth markers agree with each driver's doctor status" {
    local dash="$BATS_TEST_DIRNAME/../lib/dashboard"
    local drivers="$BATS_TEST_DIRNAME/../lib/harnesses"

    # claude: split layout, marker is .claude.json
    local acct="$BATS_TEST_TMPDIR/acct-claude"
    mkdir -p "$acct/claude"
    touch "$acct/claude/.claude.json"
    run bash -c "source '$drivers/claude.sh'; CW_HARNESS_DIR='$acct/claude' claude_doctor"
    [[ "$output" == *'"status":"connected"'* ]]
    run python3 -c "
import sys; sys.path.insert(0, '$dash')
import server
assert server.harness_authenticated('$acct', 'claude') is True
print('ok')"
    [ "$output" = "ok" ]

    # codex, pi, opencode: flat per-harness dir, markers are auth.json and env
    local h marker
    for h in codex pi opencode; do
        for marker in auth.json env; do
            acct="$BATS_TEST_TMPDIR/acct-$h-$marker"
            mkdir -p "$acct/$h"
            touch "$acct/$h/$marker"
            run bash -c "source '$drivers/$h.sh'; CW_HARNESS_DIR='$acct/$h' ${h}_doctor"
            [[ "$output" == *'"status":"connected"'* ]]
            run python3 -c "
import sys; sys.path.insert(0, '$dash')
import server
assert server.harness_authenticated('$acct', '$h') is True, '$h/$marker not recognized by dashboard'
print('ok')"
            [ "$output" = "ok" ]
        done
    done
}
