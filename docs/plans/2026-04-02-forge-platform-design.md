# Forge — Integral Development Platform

> Where ideas are shaped into software.

**Date:** 2026-04-02
**Author:** Jose Andrade
**Status:** Approved

---

## Vision

Forge is an integral development platform that unifies the entire software lifecycle — from design to deploy — in a visual web dashboard where every action executes with a single click. Stack-agnostic, module-extensible, and orchestrated by Claude Code as its AI engine.

## Principles

| Principle | Meaning |
|-----------|---------|
| **One click, one action** | Every dashboard button triggers something real |
| **Module everything** | No hardcoded capabilities. Every feature is an installable module |
| **Local first, team ready** | Works offline on your machine. Add `--team` for shared mode |
| **AI-native** | Claude Code is the engine, not an add-on. Every module can invoke skills and MCPs |
| **Zero config, full control** | Smart defaults, everything configurable |

## Audience

1. **Solo dev** — Cockpit for all projects
2. **Small team (2-10)** — Shared visibility and standardized workflows
3. **Freelancer/Agency** — Multiple projects, multiple clients, needs order
4. **OSS contributor** — Creates modules for their stack/workflow

## License

MIT, open source from day 1.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  FORGE CONSOLE                       │
│              (Preact + UnoCSS)                       │
│                                                      │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  │
│  │ Planning │ │ Design  │ │   Dev   │ │   QA    │  │
│  │  Panel   │ │  Panel  │ │  Panel  │ │  Panel  │  │
│  └────┬─────┘ └────┬────┘ └────┬────┘ └────┬────┘  │
│       │            │           │            │        │
│  ┌────┴────────────┴───────────┴────────────┴────┐  │
│  │              Module Shell (router, layout)     │  │
│  └────────────────────┬──────────────────────────┘  │
└───────────────────────┼──────────────────────────────┘
                        │ HTTP + WebSocket + SSE
┌───────────────────────┼──────────────────────────────┐
│                 FORGE SERVER (Hono)                    │
│                                                       │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ Module   │  │ Action   │  │ Claude Code       │  │
│  │ Registry │  │ Runner   │  │ Bridge            │  │
│  │          │  │ (spawn)  │  │ (skills, MCPs)    │  │
│  └────┬─────┘  └────┬─────┘  └────────┬──────────┘  │
│       │             │                  │              │
│  ┌────┴─────────────┴──────────────────┴──────────┐  │
│  │              Module API Layer                   │  │
│  └────────────────────┬───────────────────────────┘  │
│                       │                               │
│  ┌────────────────────┴───────────────────────────┐  │
│  │           SQLite (local) / PostgreSQL (team)    │  │
│  └────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────┘
         │              │                │
    ┌────┴────┐   ┌─────┴─────┐   ┌─────┴──────┐
    │ CW      │   │ External  │   │ Claude     │
    │ (bash)  │   │ Tools     │   │ Code CLI   │
    └─────────┘   └───────────┘   └────────────┘
```

### Core Components

| Component | Responsibility | Tech |
|-----------|---------------|------|
| **Forge Console** | Web dashboard, panels per module | Preact + UnoCSS |
| **Forge Server** | API, WebSocket, module loading, auth | Hono + Node.js |
| **Module Registry** | Discovers, loads, and registers modules | Dynamic imports |
| **Action Runner** | Executes module commands (spawns processes) | Node child_process + PTY |
| **Claude Bridge** | Invokes Claude Code CLI, skills, MCPs | Subprocess + JSON protocol |
| **DB** | Project state, sessions, history | better-sqlite3 / PostgreSQL |
| **Forge CLI** | Thin client calling server API | Commander.js |

### Operation Modes

| Mode | DB | Auth | URL |
|------|-----|------|-----|
| **Local** | SQLite at `~/.forge/forge.db` | None | `localhost:3000` |
| **Team** | PostgreSQL (configurable) | Simple token | `forge.yourdomain.com` |
| **Hybrid** | SQLite local + sync API | Token for sync | `localhost:3000` + remote |

---

## Module System

### Module Manifest (`forge-module.json`)

```json
{
  "name": "@forge-dev/mod-qa",
  "version": "1.0.0",
  "displayName": "Quality Assurance",
  "description": "E2E, unit, visual, security, and load testing",
  "icon": "shield-check",
  "color": "#10b981",

  "panels": [
    {
      "id": "dashboard",
      "title": "QA Overview",
      "component": "./panels/Dashboard",
      "default": true
    }
  ],

  "actions": [
    {
      "id": "run-e2e",
      "label": "Run E2E Tests",
      "icon": "play",
      "command": "npx playwright test",
      "streaming": true,
      "tags": ["test", "e2e"]
    }
  ],

  "detectors": [
    {
      "tool": "playwright",
      "files": ["playwright.config.*", "e2e/**"],
      "suggestion": "Playwright detected. Enable E2E testing?"
    }
  ],

  "claude": {
    "skills": ["test-master", "security-reviewer"],
    "mcpServers": ["playwright"]
  },

  "settings": {
    "schema": {
      "coverageThreshold": { "type": "number", "default": 80 },
      "runOnPush": { "type": "boolean", "default": false }
    }
  }
}
```

### The 7 Core Modules

#### 1. `@forge-dev/mod-planning` — Planning & Architecture

**Panels:** Board (Linear/GitHub issues), Docs (Notion), Architecture (Mermaid/D2 diagrams), ADRs

**Actions:**
- Create Issue → Linear MCP
- Create ADR → `npx log4brains adr new`
- Generate Diagram → Claude Code + Mermaid/D2
- Sync Notion → Notion MCP
- Sprint View → Linear MCP

**Tools:** Linear MCP, Notion MCP, GitHub Projects (`gh`), Mermaid CLI, D2, log4brains

#### 2. `@forge-dev/mod-design` — Design & UI/UX

**Panels:** Designs (Figma/Penpot frames), Tokens (design tokens), Wireframes (Excalidraw), Visual Diff

**Actions:**
- Import from Figma → Figma MCP
- Generate Component → Claude Code + shadcn/ui + frontend-design skill
- Export Tokens → `style-dictionary build`
- Create Wireframe → Excalidraw MCP
- Visual Regression → `npx lost-pixel`

**Tools:** Figma MCP, Penpot MCP, Excalidraw, Style Dictionary, Lost Pixel, shadcn/ui

#### 3. `@forge-dev/mod-dev` — Development (CW Wrapper)

**Panels:** Workspaces (active worktrees), Sessions (Claude Code sessions), Accounts, Shared Context

**Actions:**
- Start Task → `cw work`
- Review PR → `cw review`
- Open Project → `cw open`
- Plan Task → `cw plan`
- Close Task → `cw work --done`

**Tools:** CW CLI, Claude Code, Git worktrees

#### 4. `@forge-dev/mod-qa` — Quality Assurance

**Panels:** Overview (semaphore status cards), Test Runner (streaming terminal), Coverage (treemap), Reports (history)

**Actions:**
- Run Unit Tests → `pytest` / `npx vitest` (auto-detect)
- Run E2E → `npx playwright test`
- Security Scan → `semgrep scan --config auto`
- Load Test → `k6 run`
- Visual Regression → `npx lost-pixel`
- Mutation Test → `mutmut run` / `npx stryker run`
- API Test → `hurl --test`
- Full Suite → all sequential

**Tools:** Playwright MCP, Vitest/pytest, Semgrep, k6, Lost Pixel, Hurl, Stryker/mutmut

#### 5. `@forge-dev/mod-release` — Release & Deploy

**Panels:** Pipeline (visual timeline), Environments (status cards), Changelog (preview), Feature Flags (toggles), Rollback (history)

**Actions:**
- Bump Version → `npx changeset version` / `npx semantic-release`
- Generate Changelog → `git-cliff -o CHANGELOG.md`
- Deploy → auto-detected platform CLI (Vercel/Railway/Fly/Docker/Azure/AWS/GCP/K8s/etc.)
- Create Release → `gh release create`
- Toggle Flag → Flipt API
- Rollback → platform CLI rollback
- Notify Team → Slack webhook

**Deploy detection:** vercel.json, fly.toml, railway.json, netlify.toml, render.yaml, Dockerfile, k8s/, helm/, *.tf, pulumi.yaml, sst.config.ts, app.yaml, appspec.yml, Fastfile, azure-pipelines.yml

**Tools:** semantic-release/changesets, git-cliff, platform CLIs, Flipt, GitHub CLI, Sentry CLI, Slack MCP

#### 6. `@forge-dev/mod-monitor` — Monitoring & Observability

**Panels:** Health (service status grid), Errors (Sentry feed), Uptime (30-day chart), Costs (AI + cloud spend), Activity (live SSE feed)

**Actions:**
- Check Health → HTTP pings
- View Errors → Sentry API
- View Logs → platform CLI logs
- Cost Report → Claude Code stats + cloud billing
- Create Incident → status page API

**Tools:** Gatus, Sentry CLI, Uptime Kuma, CW stats, platform CLIs

#### 7. `@forge-dev/mod-scaffold` — Project Creation Wizard

**Panels:** Wizard (step-by-step), Templates (visual gallery), Recent (last created)

**Actions:**
- Create from Template → Cookiecutter / create-t3 / Vite / custom
- Detect Stack → `cw stack`
- Setup Integrations → `cw project setup-mcps`
- Generate CLAUDE.md → `cw stack --apply`
- Init Git + CI/CD → `git init` + GitHub Actions template
- Create Linear Project → Linear MCP
- Create Notion Space → Notion MCP

**Tools:** CW create, Cookiecutter, create-t3-app, create-vite, GitHub CLI, Linear/Notion MCP

---

## Dashboard UI

### Tech Stack

| Layer | Tech | Why |
|-------|------|-----|
| **Framework** | Preact 10 | 3KB, React API |
| **Routing** | preact-router | Lightweight |
| **CSS** | UnoCSS | Atomic, build-time, zero runtime |
| **Icons** | Lucide | Tree-shakeable, 1000+ icons |
| **Charts** | Chart.js | 60KB, line/bar/doughnut |
| **Terminal** | xterm.js | Real embedded terminal |
| **Themes** | CSS variables | Dark/light toggle |
| **State** | Preact signals | Reactive, zero boilerplate |

**Estimated bundle: ~80KB gzipped**

### Shared UI Components (`@forge-dev/ui`)

StatusCard, ActionButton, Terminal, Timeline, DataTable, Chart, DiffViewer, FileTree, Modal, Toast, Badge, Tabs, CommandPalette

### Layout

- Left sidebar: module navigation with status badges
- Top bar: project selector, search, user, settings
- Main area: active module panel
- Command palette: `Cmd+K` for search and execute any action
- Keyboard shortcuts: `1-7` for modules, `r` for run

---

## CLI

```bash
# Setup
forge init                          # First-time wizard
forge doctor                        # Health check

# Projects
forge project list|add|remove

# Modules
forge module list|add|remove|create

# Actions
forge run <module> <action>         # forge run qa run-e2e
forge run release deploy staging

# Dashboard
forge console                       # Start dashboard
forge console --team                # Team mode
forge console --detach              # Background

# CW passthrough
forge work|review|spaces            # → cw commands

# Info
forge status                        # All projects summary
forge costs                         # AI cost report
```

### Configuration: `~/.forge/`

```
~/.forge/
├── config.json          # Global config
├── forge.db             # SQLite (local mode)
├── modules/             # Installed modules
├── templates/           # Project templates
├── cache/               # Tool outputs
└── logs/                # Action logs
```

---

## Module SDK

### Server side

```typescript
import { defineModule } from '@forge-dev/sdk'

export default defineModule({
  routes(app) { /* Hono routes */ },
  actions: {
    'my-action': async (ctx) => {
      return ctx.exec('command', { stream: true })
    }
  },
  detectors: [ /* stack detection rules */ ],
  onProjectAdd(project) { },
  onActionComplete(action, result) { }
})
```

### UI side

```tsx
import { definePanel } from '@forge-dev/sdk/ui'
import { StatusCard, ActionButton } from '@forge-dev/ui'

export default definePanel({
  render({ project, api, actions }) {
    return (
      <div>
        <StatusCard icon="zap" label="Status" value="OK" status="good" />
        <ActionButton action={actions['my-action']} />
      </div>
    )
  }
})
```

### Claude Integration

```typescript
ctx.claude('prompt', { skill: 'skill-name', files: ['...'] })
ctx.mcp('server', 'tool', { ...args })
ctx.exec('command', { stream: true })
```

---

## End-to-End Flow

```
Scaffold → Planning → Design → Dev → QA → Release → Monitor
   ↑                                                    │
   └──────────────── feedback loop ─────────────────────┘
```

1. **Scaffold:** Click [New Project] → wizard → repo + CI/CD + integrations ready
2. **Planning:** Linear board + Notion docs + architecture diagrams + ADRs
3. **Design:** Figma import → component generation → design tokens → wireframes
4. **Dev:** CW worktrees + Claude Code sessions + shared context
5. **QA:** Unit + E2E + security + visual + load → semaphore dashboard
6. **Release:** Version bump → changelog → deploy staging → verify → deploy prod → notify
7. **Monitor:** Health checks + error tracking + uptime + costs + activity feed

The loop: Monitor detects issue → creates Linear issue → Dev fixes → QA verifies → Release deploys hotfix

---

## Monorepo Structure

```
forge/
├── packages/
│   ├── core/            # @forge-dev/core (Hono server)
│   ├── cli/             # @forge-dev/cli (Commander.js)
│   ├── console/         # @forge-dev/console (Preact dashboard)
│   ├── ui/              # @forge-dev/ui (shared components)
│   ├── sdk/             # @forge-dev/sdk (module SDK)
│   └── platform/        # @forge-dev/platform (entry point)
├── modules/
│   ├── mod-dev/         # @forge-dev/mod-dev
│   ├── mod-scaffold/    # @forge-dev/mod-scaffold
│   ├── mod-planning/    # @forge-dev/mod-planning
│   ├── mod-design/      # @forge-dev/mod-design
│   ├── mod-qa/          # @forge-dev/mod-qa
│   ├── mod-release/     # @forge-dev/mod-release
│   └── mod-monitor/     # @forge-dev/mod-monitor
├── templates/           # Project templates
├── docs/                # Documentation
├── turbo.json           # Turborepo
├── LICENSE              # MIT
└── README.md
```

Build tool: Turborepo

---

## Roadmap

| Phase | Duration | Deliverables |
|-------|----------|-------------|
| **0: Foundation** | 2 weeks | Core server, dashboard shell, module system, CLI basics, UI kit, SQLite |
| **1: Core Modules** | 4 weeks | mod-dev (CW), mod-scaffold, mod-planning, mod-monitor |
| **2: Full Ecosystem** | 4 weeks | mod-qa, mod-design, mod-release, team mode |
| **3: Community** | Ongoing | Module SDK docs, module registry, template gallery, docs site |

---

## Key Tools Researched

### Design
Penpot MCP, Figma MCP, Excalidraw + MCP, Style Dictionary, Lost Pixel, v0.app, Google Stitch

### Frontend
shadcn/ui CLI + Skills, Create T3, Vite, Storybook 9, Chromatic, UnoCSS, Biome

### Backend
Cookiecutter Django, drf-spectacular, Prisma 7, Drizzle ORM, GraphQL Code Generator, Supabase CLI

### DevOps
Terraform, Pulumi, SST, Encore, Dagger, Kompose, GitHub Actions, Azure CLI, 1Password CLI + MCP

### Planning
Linear MCP, Notion MCP, GitHub Projects CLI, Mermaid CLI, D2, Kroki, log4brains, adr-tools, git-cliff

### QA
Playwright MCP, k6, Artillery, Bruno, Hurl, Step CI, Stryker, mutmut, Semgrep, PR-Agent

### Release
semantic-release, release-please, changesets, release-it, git-cliff, Fastlane, EAS, Flipt, Argo Rollouts

### Monitoring
Sentry CLI, Highlight.io, OneUptime, Gatus, Uptime Kuma, Datadog

### Platforms (inspiration)
Backstage (Spotify), Port, Cortex, Windmill, Composio
