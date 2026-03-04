# Commands Reference

## Main Commands

### `cw work <project> <task|URL> [--done]`

Work on a feature or bug with an isolated worktree and persistent session.

**Arguments:**
- `project` — registered project name
- `task` — branch name, ticket ID, or URL (Linear, Notion, GitHub)
- `--done` — close the task, remove worktree, archive session
- `--list` — list active tasks (optionally filtered by project)

**Examples:**
```bash
cw work my-app fix-auth                        # plain branch name
cw work my-app PROJ-123                        # ticket ID as branch
cw work my-app https://linear.app/.../PROJ-123 # fetch from Linear
cw work my-app fix-auth                        # resume existing
cw work my-app fix-auth --done                 # close and cleanup
cw work --list                                 # list all active tasks
cw work my-app --list                          # list tasks for project
```

**URL behavior:**

| URL Source | What happens |
|-----------|-------------|
| Linear | Extracts issue ID, Claude fetches branch name + description via MCP |
| GitHub | Extracts issue/PR number, Claude fetches details via MCP |
| Notion | Extracts page slug, Claude fetches content via MCP |

---

### `cw review <project> <PR|URL> [--done]`

Review a PR with an isolated worktree.

**Arguments:**
- `project` — registered project name
- `PR` — PR number or GitHub PR URL
- `--done` — close the review, remove worktree, archive session
- `--list` — list active reviews

**Examples:**
```bash
cw review my-app 42                            # by PR number
cw review my-app https://github.com/.../pull/42 # by URL
cw review my-app 42                            # resume
cw review my-app 42 --done                     # close
```

---

### `cw open <project>`

Quick-open Claude in a project. No worktree, no session tracking.

```bash
cw open my-app
```

---

### `cw spaces`

Show all active tasks and reviews across all projects, grouped by project.

```bash
cw spaces
```

---

### `cw dashboard`

Full workspace overview: accounts, projects with status indicators, active spaces.

```bash
cw dashboard
```

---

## Setup Commands

### `cw init`

Initialize CW directory structure at `~/.cw/`.

### `cw account add <name>`

Create a new Claude account profile. After creation, authenticate:

```bash
cw account add work
cw launch work
# Then: /login
```

### `cw account list`

List all configured accounts.

### `cw account remove <name>`

Remove an account profile.

### `cw project register <path> [options]`

Register a project directory.

**Options:**
- `--account, -a <name>` — Claude account to use
- `--type, -t <type>` — Project type: `fullstack`, `api`, `knowledge`, `infra`, `agents`

```bash
cw project register ~/code/my-app --account work --type fullstack
```

### `cw project list`

List all registered projects.

### `cw project setup-mcps <name>`

Interactive setup of MCP integrations (GitHub, Linear, Notion, Slack) for a project.

### `cw project setup-agents <name>`

Install agents and commands for a project.

### `cw project info <name>`

Show detailed project information.

---

## Utility Commands

### `cw launch <account> [args]`

Quick-launch Claude with a specific account. Useful for authentication.

```bash
cw launch work
cw launch personal
```

### `cw status`

Quick status: account count, project count, active spaces.

### `cw help`

Full command reference.

---

## Shell Aliases

Available after sourcing `cw-shell-integration.sh`:

| Alias | Command | Description |
|-------|---------|-------------|
| `cww` | `cw work` | Work on task with worktree |
| `cwpr` | `cw review` | PR review with worktree |
| `cwsp` | `cw spaces` | Show active spaces |
| `cwd` | `cw dashboard` | Full workspace overview |
| `cws` | `cw status` | Quick status |
| `cwrl` | `cw review --list` | List active reviews |
| `cwl` | `cw project list` | List projects |
| `cwc` | `cw open <project> --mode code` | Open in code mode |
| `cwr` | `cw open <project> --mode review` | Open in review mode |
| `cwi` | `cw open <project> --mode research` | Open in research mode |
| `cwdoc` | `cw open <project> --mode docs` | Open in docs mode |
| `cwp` | `cw open <project> --mode planning` | Open in planning mode |
| `cwm` | `cw open <project> --mode comms` | Open in comms mode |
| `cwf` | `cw open <project> --mode full` | Open in full mode |
| `cwo` | Fuzzy project opener | Requires `fzf` |
| `cc` | `cw launch` | Quick launch Claude |
