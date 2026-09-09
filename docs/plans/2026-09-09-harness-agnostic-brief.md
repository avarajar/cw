# CW next release: harness-agnostic workflows

You are working in the CW repo (`~/workspace/personal/cw`). CW is a bash workspace manager
that today launches only Claude Code. The goal of this release is to make the same
`cw work` / `cw review` / `cw loop` flow run on any coding-agent harness: Claude Code,
Codex CLI, Pi, OpenCode. Nobody does this well today. That is the differentiator.

Follow the repo's superpowers process: brainstorm with me first, write a spec in
`docs/specs/`, then a plan in `docs/plans/`, then implement with TDD. Do not skip the
spec. Use `bats` for tests (add it if missing).

## Non-negotiable design decisions

1. **A harness is a driver, not a flag sprinkled around.** Create one abstraction
   (`harness_launch`, `harness_resume`, `harness_login`, `harness_doctor`) and route every
   invocation through it. Today `claude` is called directly at roughly ten sites in `cw`
   (search for `CLAUDE_CONFIG_DIR="$acct_dir" claude`). After this release there must be
   exactly one place that knows how to spawn a binary.
2. **Drivers live in files, not in `if` chains.** Built-in drivers in `lib/harnesses/<name>.sh`
   (claude, codex, pi, opencode). Users can drop custom drivers in `~/.cw/harnesses/`.
   A driver is a small bash file that defines a fixed set of functions and declares
   capabilities (supports resume by name? supports hooks? supports MCP? supports
   non-interactive prompt?).
3. **Account = a person or org, holding one credential dir per harness.** Today
   `~/.cw/accounts/<name>` is itself a `CLAUDE_CONFIG_DIR`. New layout:
   `~/.cw/accounts/<name>/claude/` (CLAUDE_CONFIG_DIR), `.../codex/` (CODEX_HOME),
   `.../pi/` (PI_CODING_AGENT_DIR), `.../opencode/` (verify OpenCode's data dir env var in
   the spec; sources disagree between `~/.opencode/data` and XDG paths). Each account has a
   default `harness`; a project may override it; a session records which harness it used so
   resume always uses the same one. Migration is silent and reversible: on first run,
   detect a legacy flat account dir, move it to `<name>/claude/`, leave a symlink at the
   old path. Nothing the user has today may break.
3b. **Login is a CW command, per account and per harness.**
   `cw account login <account> --harness <h>` runs the harness's native login with the env
   var pointed at the right subdir (`claude /login`, `codex login`, `pi` then `/login`,
   `opencode auth login`). Support `--no-browser` so it never auto-opens a browser, and
   print any URL or device code on a single machine-parseable line
   (`CW_LOGIN_URL=...`, `CW_LOGIN_CODE=...`) so Forge can render it. Accept an API key on
   stdin (`--with-api-key -`) and never write it to any CW config file. `cw doctor` reports
   a matrix of account x harness with: connected, not logged in, not installed. Forge will
   consume that output, so make it available as `cw doctor --json`.
3c. **Provider and model are part of the account, so free, local and third-party models
   are first-class.** Each account+harness pair may carry an optional `provider` and a
   default `model`. A provider is either the harness's native login (default, needs
   `cw account login`) or an API endpoint plus key (no browser login). Drivers translate
   it to their own config: pi and opencode have native providers for OpenRouter, Groq,
   Gemini, Ollama, Z.ai (GLM), MiniMax, Moonshot (Kimi), DeepSeek, Qwen; codex maps it to
   `model_providers` (OpenAI-compatible endpoints, including Ollama via `--oss`); claude
   accepts only Anthropic-compatible endpoints (Z.ai, MiniMax, Moonshot) by setting
   `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`, and `cw doctor` labels that path
   "unofficial, may break on Claude Code updates". API keys are read from
   `~/.cw/accounts/<acct>/<harness>/env` (mode 600) or from the environment, never from
   `config.yaml`. For local providers `cw doctor` checks that Ollama answers and the model
   is pulled instead of looking for a token. Examples that must work:
   ```
   cw account add glm   --harness opencode --provider zai    --model glm-5.1
   cw account add local --harness opencode --provider ollama --model qwen3-coder:14b
   cw account add free  --harness pi       --provider openrouter --model qwen/qwen3-coder:free
   cw work seimseim-reservas SEI-214 --account glm
   ```
4. **Context injection must not depend on Claude-only features.** Today "URL to context"
   relies on Claude fetching the ticket through MCP. Make CW able to fetch Linear, GitHub,
   and Notion content itself (`gh`, Linear GraphQL, Notion API, via tokens in
   `~/.cw/config.yaml`) and write it into `TASK_NOTES.md` before launch. If the harness
   supports MCP, still pass the URL so the agent can refresh, but the notes file is the
   source of truth. This is what makes the workflow portable.
5. **Claude-specific things stay Claude-specific, gated by capability.** Hooks in
   `hooks/`, `--dangerously-skip-permissions`, agent teams, plugin detection: all behind
   `harness_supports <capability>`. Never fail on a harness that lacks a feature; degrade
   and say so once.
6. **Backwards compatible.** Existing `~/.cw` layouts, `projects.json`, and sessions must
   keep working with no migration step. Missing `harness` field means `claude`.

## Steps

1. **Pure refactor first.** Extract every `claude` invocation into `harness_launch`
   with the claude driver as the only implementation. Behavior must be identical. Cover
   with bats tests that put a fake `claude` binary on PATH and assert the argv, env, and
   cwd it receives for `work`, `review`, `loop`, `create`, `launch`, `open`, resume paths
   and the `--done` path. Land this as its own commit before adding any new harness.
2. **Driver contract.** Write `docs/harness-drivers.md` describing the function set,
   capability flags, and env contract. Implement `codex` next (it is the most used
   alternative), then `pi` and `opencode`. Each driver gets the same fake-binary test
   suite as claude.
3. **CLI surface.** `cw account add work --harness codex`, `cw project register ... --harness pi`,
   `cw work my-app PROJ-1 --harness codex` (one-off override), `cw harness list`,
   `cw harness doctor`. `cw doctor` and `cw status` show the harness per account and per
   active session. `cw spaces` shows a harness column.
4. **Portable context fetch.** Implement the URL fetchers in `lib/context/`. Keep the
   existing MCP path when the harness supports it. Tests use recorded fixtures, no network.
5. **Session metadata.** Add `harness` to `session.json`. Resume picks it up. Forge reads
   this field (coordinate the key name: `harness`).
6. **Docs and demo.** Update README with a "one flow, any harness" section and a new
   `demo.tape` showing the same ticket opened in Claude Code and Codex side by side.
   Bump version, write CHANGELOG entry.

## Acceptance criteria

- `grep -c 'claude ' cw` outside `lib/harnesses/claude.sh` returns zero launch sites.
- The full bats suite passes with fake binaries for all four harnesses.
- `cw work demo-app https://github.com/org/repo/issues/1 --harness codex` creates the
  worktree, writes `TASK_NOTES.md` with the issue body, and launches codex in it.
- Running the same command without `--harness` on an existing account behaves exactly as
  the current release.
- Resuming a session launched with codex never launches claude.
- `cw account login monoku --harness codex --no-browser` prints a `CW_LOGIN_URL=` line and
  exits 0 once the token is stored; `cw doctor --json` then reports codex as connected for
  monoku.
- An existing flat account dir keeps working after migration, and `CLAUDE_CONFIG_DIR`
  resolves to the same files through the symlink.
- `cw account add local --harness opencode --provider ollama --model qwen3-coder:14b`
  needs no login; `cw doctor --json` reports it as "local" with the model's pull status,
  and `cw work ... --account local` launches opencode against Ollama.
- `cw spaces` and `cw doctor --json` expose harness, provider and model per session and
  per account, so Forge can show "Claude Code" next to "OpenCode · GLM 5.1".

## Out of scope

Rewriting CW in another language, changing the `~/.cw` directory layout, a plugin system
for CW itself, and any Forge UI work (that is a separate brief).

---

# Session prompts

How to run this brief with an agent, one prompt per phase. Open the session with CW
itself so it works in an isolated worktree with the right account:

```
cw work cw harness-agnostic --account monoku
```

(If the repo is not registered: `cw project register ~/workspace/personal/cw --account monoku`.)

## Prompt 1 — Kickoff and brainstorm

```
Read docs/plans/2026-09-09-harness-agnostic-brief.md in full before doing anything else.
It is the brief for the next release and it is not up for renegotiation on scope.

Then read cw end to end and docs/architecture.md, and list for me:
1. Every site where the claude binary is launched, with line numbers and which
   command it belongs to (work, review, loop, create, launch, open, resume paths).
2. What the current account directory layout looks like and what would break if it
   moved to accounts/<name>/claude/.
3. The open questions you need me to answer before writing the spec. Ask them all
   at once, grouped, with your recommended answer for each.

Do not write code or the spec yet. Only harnesses installed on this machine right now:
claude. Assume codex and pi will be installed before implementation; opencode may not be.
```

## Prompt 2 — Spec (after answering its questions)

```
Write the spec at docs/specs/2026-09-09-harness-agnostic.md using superpowers'
brainstorming output. It must cover: the driver contract (functions, capability flags,
env contract) for claude, codex, pi and opencode; the account layout with per-harness
credential dirs, provider and model; the silent migration with symlink; the
`cw account login` flow with --no-browser and the CW_LOGIN_URL / CW_LOGIN_CODE lines;
`cw doctor --json` output shape; session.json changes; the portable context fetch for
Linear, GitHub and Notion; and how each existing command degrades on a harness that
lacks a capability. Include the exact JSON shapes Forge will consume.
Mark anything you could not verify (OpenCode's data dir env var, exact codex login
flags) as "verify during implementation" instead of guessing.
Stop after the spec so I can review it.
```

## Prompt 3 — Plan (after approving the spec)

```
Spec approved. Write the implementation plan at docs/plans/2026-09-09-harness-agnostic-plan.md
using superpowers:writing-plans. Task 1 must be the pure refactor: extract every claude
launch into harness_launch with the claude driver as the only implementation, behavior
identical, covered by bats tests with a fake claude binary on PATH asserting argv, env
and cwd for every command and resume path. That task lands as its own commit before
anything else. Order the remaining tasks so codex comes before pi and opencode, and
so `cw doctor --json` exists before the login command. Each task needs its tests
listed. Set up bats in the repo if it is not there.
```

## Prompt 4 — Execution (after approving the plan)

```
Execute the plan with superpowers:executing-plans, one task at a time, TDD, stopping
for my review after task 1 (the refactor) and again after the codex driver works
end to end. Commit after each task with the repo's conventional commit style and no
Claude attribution. Do not touch ~/.cw on this machine during tests; every test runs
against a temporary CW_HOME.
```

Why the last rule matters: the real `~/.cw` holds the monoku and meridian sessions and
credentials. The account migration must only run in prompt 5, with the maintainer watching.

## Prompt 5 — Close (when everything passes)

```
Run superpowers:verification-before-completion. Then: update README with a "one flow,
any harness" section, rewrite demo.tape to show the same ticket opened with claude and
codex, write the CHANGELOG entry, bump the version, and run `cw doctor` against my real
~/.cw to confirm the migration left monoku and meridian working. Report the exact
output.
```
