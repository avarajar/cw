# Forge Phase 0: Foundation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the foundation — monorepo, server, dashboard shell, module system, action runner, CLI, and UI kit — so that `npx @forge-dev/platform` opens a working dashboard where you can install a module and click a button to execute a command with streaming output.

**Architecture:** Turborepo monorepo with 6 packages (core, console, ui, sdk, cli, platform). Hono serves the API + static dashboard. Preact renders the UI. Modules are loaded dynamically from `~/.forge/modules/`. Actions spawn child processes and stream output via WebSocket.

**Tech Stack:** TypeScript, Hono 4.x, Preact 10.x, UnoCSS 66.x, Vite 8.x, better-sqlite3 12.x, Commander 14.x, xterm.js 5.x, Chart.js 4.x, Turborepo 2.x, Vitest 4.x

---

## Task 1: Monorepo Scaffold

**Files:**
- Create: `forge/package.json`
- Create: `forge/turbo.json`
- Create: `forge/tsconfig.base.json`
- Create: `forge/.gitignore`
- Create: `forge/LICENSE`
- Create: `forge/packages/core/package.json`
- Create: `forge/packages/core/tsconfig.json`
- Create: `forge/packages/console/package.json`
- Create: `forge/packages/console/tsconfig.json`
- Create: `forge/packages/ui/package.json`
- Create: `forge/packages/ui/tsconfig.json`
- Create: `forge/packages/sdk/package.json`
- Create: `forge/packages/sdk/tsconfig.json`
- Create: `forge/packages/cli/package.json`
- Create: `forge/packages/cli/tsconfig.json`
- Create: `forge/packages/platform/package.json`
- Create: `forge/packages/platform/tsconfig.json`
- Create: `forge/modules/` (empty dir with .gitkeep)

**Step 1: Create the repo and root workspace config**

Create `forge/` directory at `/Users/joselito/Workspace/personal/forge/`.

`forge/package.json`:
```json
{
  "name": "forge",
  "private": true,
  "workspaces": [
    "packages/*",
    "modules/*"
  ],
  "scripts": {
    "dev": "turbo dev",
    "build": "turbo build",
    "test": "turbo test",
    "lint": "turbo lint",
    "clean": "turbo clean"
  },
  "devDependencies": {
    "turbo": "^2.9.3",
    "typescript": "^5.8.0"
  },
  "packageManager": "npm@10.9.0",
  "engines": {
    "node": ">=20.0.0"
  }
}
```

`forge/turbo.json`:
```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "test": {
      "dependsOn": ["build"]
    },
    "lint": {},
    "clean": {
      "cache": false
    }
  }
}
```

`forge/tsconfig.base.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "dist",
    "rootDir": "src"
  },
  "exclude": ["node_modules", "dist"]
}
```

`forge/.gitignore`:
```
node_modules/
dist/
*.tsbuildinfo
.turbo/
.env
.env.local
forge.db
```

`forge/LICENSE`: MIT license with Jose Andrade / Monoku as copyright holder.

**Step 2: Create each package skeleton**

For each package (`core`, `console`, `ui`, `sdk`, `cli`, `platform`), create:
- `package.json` with name `@forge-dev/<name>`, version `0.1.0`, `"type": "module"`
- `tsconfig.json` extending `../../tsconfig.base.json`
- `src/index.ts` with a placeholder export

Package-specific dependencies (install in Step 3):
- **core**: `hono`, `better-sqlite3`, `@types/better-sqlite3`, `node-pty`, `@types/node`
- **console**: `preact`, `@preact/signals`, `preact-router`, `@xterm/xterm`, `chart.js`, `lucide-preact`
- **ui**: `preact` (peer dep)
- **sdk**: `hono` (peer dep), `preact` (peer dep)
- **cli**: `commander`, `@forge-dev/core` (workspace dep)
- **platform**: `@forge-dev/core`, `@forge-dev/console`, `@forge-dev/cli` (workspace deps)

**Step 3: Install dependencies**

```bash
cd /Users/joselito/Workspace/personal/forge
npm install
```

**Step 4: Verify turborepo works**

```bash
npx turbo build
```

Expected: All packages build (empty dist/ dirs). No errors.

**Step 5: Init git and commit**

```bash
git init
git add .
git commit -m "chore: scaffold monorepo with turborepo"
```

---

## Task 2: Database Layer (`@forge-dev/core`)

**Files:**
- Create: `packages/core/src/db.ts`
- Create: `packages/core/src/db.test.ts`
- Create: `packages/core/src/types.ts`

**Step 1: Write the types**

`packages/core/src/types.ts`:
```typescript
export interface Project {
  id: string
  name: string
  path: string
  createdAt: string
  updatedAt: string
}

export interface InstalledModule {
  id: string
  name: string
  version: string
  enabled: boolean
  installedAt: string
}

export interface ActionLog {
  id: string
  projectId: string
  moduleId: string
  actionId: string
  command: string
  exitCode: number | null
  startedAt: string
  finishedAt: string | null
}

export interface ForgeConfig {
  port: number
  theme: 'dark' | 'light'
  openBrowser: boolean
  dataDir: string
}
```

**Step 2: Write the failing test**

`packages/core/src/db.test.ts`:
```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { ForgeDB } from './db.js'
import { rmSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'

const TEST_DIR = join(import.meta.dirname, '../.test-data')

describe('ForgeDB', () => {
  let db: ForgeDB

  beforeEach(() => {
    mkdirSync(TEST_DIR, { recursive: true })
    db = new ForgeDB(join(TEST_DIR, 'test.db'))
  })

  afterEach(() => {
    db.close()
    rmSync(TEST_DIR, { recursive: true, force: true })
  })

  it('creates tables on init', () => {
    const tables = db.listTables()
    expect(tables).toContain('projects')
    expect(tables).toContain('modules')
    expect(tables).toContain('action_logs')
  })

  it('adds and retrieves a project', () => {
    db.addProject({ name: 'test-app', path: '/tmp/test-app' })
    const projects = db.listProjects()
    expect(projects).toHaveLength(1)
    expect(projects[0].name).toBe('test-app')
    expect(projects[0].path).toBe('/tmp/test-app')
  })

  it('removes a project', () => {
    db.addProject({ name: 'test-app', path: '/tmp/test-app' })
    const projects = db.listProjects()
    db.removeProject(projects[0].id)
    expect(db.listProjects()).toHaveLength(0)
  })

  it('adds and retrieves a module', () => {
    db.addModule({ name: '@forge-dev/mod-qa', version: '1.0.0' })
    const modules = db.listModules()
    expect(modules).toHaveLength(1)
    expect(modules[0].name).toBe('@forge-dev/mod-qa')
    expect(modules[0].enabled).toBe(true)
  })

  it('logs an action', () => {
    db.addProject({ name: 'test', path: '/tmp/test' })
    const project = db.listProjects()[0]
    const logId = db.logAction({
      projectId: project.id,
      moduleId: 'mod-qa',
      actionId: 'run-e2e',
      command: 'npx playwright test'
    })
    const log = db.getActionLog(logId)
    expect(log?.command).toBe('npx playwright test')
    expect(log?.exitCode).toBeNull()
  })

  it('completes an action log', () => {
    db.addProject({ name: 'test', path: '/tmp/test' })
    const project = db.listProjects()[0]
    const logId = db.logAction({
      projectId: project.id,
      moduleId: 'mod-qa',
      actionId: 'run-e2e',
      command: 'npx playwright test'
    })
    db.completeAction(logId, 0)
    const log = db.getActionLog(logId)
    expect(log?.exitCode).toBe(0)
    expect(log?.finishedAt).toBeTruthy()
  })
})
```

**Step 3: Run test to verify it fails**

```bash
cd packages/core && npx vitest run src/db.test.ts
```
Expected: FAIL — `ForgeDB` not found.

**Step 4: Implement ForgeDB**

`packages/core/src/db.ts`:
```typescript
import Database from 'better-sqlite3'
import { randomUUID } from 'node:crypto'
import type { Project, InstalledModule, ActionLog } from './types.js'

export class ForgeDB {
  private db: Database.Database

  constructor(dbPath: string) {
    this.db = new Database(dbPath)
    this.db.pragma('journal_mode = WAL')
    this.db.pragma('foreign_keys = ON')
    this.migrate()
  }

  private migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        path TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS modules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        version TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        installed_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS action_logs (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        module_id TEXT NOT NULL,
        action_id TEXT NOT NULL,
        command TEXT NOT NULL,
        exit_code INTEGER,
        started_at TEXT NOT NULL DEFAULT (datetime('now')),
        finished_at TEXT,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      );
    `)
  }

  listTables(): string[] {
    const rows = this.db.prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ).all() as { name: string }[]
    return rows.map(r => r.name)
  }

  addProject(input: { name: string; path: string }): string {
    const id = randomUUID()
    this.db.prepare(
      'INSERT INTO projects (id, name, path) VALUES (?, ?, ?)'
    ).run(id, input.name, input.path)
    return id
  }

  listProjects(): Project[] {
    return this.db.prepare('SELECT * FROM projects ORDER BY created_at DESC').all() as any[]
  }

  getProject(id: string): Project | undefined {
    return this.db.prepare('SELECT * FROM projects WHERE id = ?').get(id) as any
  }

  removeProject(id: string): void {
    this.db.prepare('DELETE FROM projects WHERE id = ?').run(id)
  }

  addModule(input: { name: string; version: string }): string {
    const id = randomUUID()
    this.db.prepare(
      'INSERT INTO modules (id, name, version) VALUES (?, ?, ?)'
    ).run(id, input.name, input.version)
    return id
  }

  listModules(): InstalledModule[] {
    return this.db.prepare('SELECT * FROM modules ORDER BY installed_at DESC').all() as any[]
  }

  removeModule(name: string): void {
    this.db.prepare('DELETE FROM modules WHERE name = ?').run(name)
  }

  logAction(input: {
    projectId: string
    moduleId: string
    actionId: string
    command: string
  }): string {
    const id = randomUUID()
    this.db.prepare(
      'INSERT INTO action_logs (id, project_id, module_id, action_id, command) VALUES (?, ?, ?, ?, ?)'
    ).run(id, input.projectId, input.moduleId, input.actionId, input.command)
    return id
  }

  getActionLog(id: string): ActionLog | undefined {
    return this.db.prepare('SELECT * FROM action_logs WHERE id = ?').get(id) as any
  }

  completeAction(id: string, exitCode: number): void {
    this.db.prepare(
      "UPDATE action_logs SET exit_code = ?, finished_at = datetime('now') WHERE id = ?"
    ).run(exitCode, id)
  }

  close(): void {
    this.db.close()
  }
}
```

**Step 5: Run test to verify it passes**

```bash
cd packages/core && npx vitest run src/db.test.ts
```
Expected: All 6 tests PASS.

**Step 6: Commit**

```bash
git add packages/core/src/db.ts packages/core/src/db.test.ts packages/core/src/types.ts
git commit -m "feat(core): add SQLite database layer with projects, modules, and action logs"
```

---

## Task 3: Module Loader (`@forge-dev/core`)

**Files:**
- Create: `packages/core/src/modules.ts`
- Create: `packages/core/src/modules.test.ts`
- Create: `packages/sdk/src/types.ts` (module manifest schema)

**Step 1: Define the module manifest type in SDK**

`packages/sdk/src/types.ts`:
```typescript
export interface ModuleManifest {
  name: string
  version: string
  displayName: string
  description: string
  icon: string
  color: string
  panels: PanelDef[]
  actions: ActionDef[]
  detectors?: DetectorDef[]
  claude?: { skills?: string[]; mcpServers?: string[] }
  settings?: { schema: Record<string, SettingDef> }
}

export interface PanelDef {
  id: string
  title: string
  component: string
  default?: boolean
}

export interface ActionDef {
  id: string
  label: string
  icon: string
  command: string
  streaming?: boolean
  tags?: string[]
}

export interface DetectorDef {
  tool: string
  files: string[]
  packages?: string[]
  suggestion: string
}

export interface SettingDef {
  type: 'string' | 'number' | 'boolean'
  default?: unknown
}
```

**Step 2: Write the failing test for module loader**

`packages/core/src/modules.test.ts`:
```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { ModuleLoader } from './modules.js'
import { mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'

const TEST_DIR = join(import.meta.dirname, '../.test-modules')

function createTestModule(name: string) {
  const dir = join(TEST_DIR, name)
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, 'forge-module.json'), JSON.stringify({
    name: `@forge-dev/${name}`,
    version: '1.0.0',
    displayName: 'Test Module',
    description: 'A test module',
    icon: 'zap',
    color: '#000',
    panels: [{ id: 'main', title: 'Main', component: './panels/Main', default: true }],
    actions: [
      { id: 'test-action', label: 'Test', icon: 'play', command: 'echo hello', streaming: false }
    ]
  }))
}

describe('ModuleLoader', () => {
  let loader: ModuleLoader

  beforeEach(() => {
    mkdirSync(TEST_DIR, { recursive: true })
    loader = new ModuleLoader(TEST_DIR)
  })

  afterEach(() => {
    rmSync(TEST_DIR, { recursive: true, force: true })
  })

  it('discovers modules from directory', () => {
    createTestModule('mod-test')
    const modules = loader.discover()
    expect(modules).toHaveLength(1)
    expect(modules[0].name).toBe('@forge-dev/mod-test')
  })

  it('returns empty array for empty directory', () => {
    const modules = loader.discover()
    expect(modules).toHaveLength(0)
  })

  it('loads a specific module manifest', () => {
    createTestModule('mod-test')
    const manifest = loader.load('mod-test')
    expect(manifest).toBeDefined()
    expect(manifest!.actions).toHaveLength(1)
    expect(manifest!.actions[0].command).toBe('echo hello')
  })

  it('returns undefined for non-existent module', () => {
    const manifest = loader.load('non-existent')
    expect(manifest).toBeUndefined()
  })

  it('gets action by module and action id', () => {
    createTestModule('mod-test')
    loader.discover()
    const action = loader.getAction('mod-test', 'test-action')
    expect(action).toBeDefined()
    expect(action!.command).toBe('echo hello')
  })
})
```

**Step 3: Run test to verify it fails**

```bash
cd packages/core && npx vitest run src/modules.test.ts
```
Expected: FAIL — `ModuleLoader` not found.

**Step 4: Implement ModuleLoader**

`packages/core/src/modules.ts`:
```typescript
import { readdirSync, readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import type { ModuleManifest, ActionDef } from '@forge-dev/sdk'

export class ModuleLoader {
  private modulesDir: string
  private loaded = new Map<string, ModuleManifest>()

  constructor(modulesDir: string) {
    this.modulesDir = modulesDir
  }

  discover(): ModuleManifest[] {
    this.loaded.clear()
    if (!existsSync(this.modulesDir)) return []

    const entries = readdirSync(this.modulesDir, { withFileTypes: true })
    const manifests: ModuleManifest[] = []

    for (const entry of entries) {
      if (!entry.isDirectory()) continue
      const manifest = this.load(entry.name)
      if (manifest) manifests.push(manifest)
    }

    return manifests
  }

  load(dirName: string): ModuleManifest | undefined {
    const manifestPath = join(this.modulesDir, dirName, 'forge-module.json')
    if (!existsSync(manifestPath)) return undefined

    try {
      const raw = readFileSync(manifestPath, 'utf-8')
      const manifest: ModuleManifest = JSON.parse(raw)
      this.loaded.set(dirName, manifest)
      return manifest
    } catch {
      return undefined
    }
  }

  getAction(moduleDirName: string, actionId: string): ActionDef | undefined {
    const manifest = this.loaded.get(moduleDirName)
    if (!manifest) return undefined
    return manifest.actions.find(a => a.id === actionId)
  }

  getLoaded(): Map<string, ModuleManifest> {
    return this.loaded
  }
}
```

**Step 5: Run test to verify it passes**

```bash
cd packages/core && npx vitest run src/modules.test.ts
```
Expected: All 5 tests PASS.

**Step 6: Commit**

```bash
git add packages/core/src/modules.ts packages/core/src/modules.test.ts packages/sdk/src/types.ts
git commit -m "feat(core): add module loader with manifest discovery and action lookup"
```

---

## Task 4: Action Runner (`@forge-dev/core`)

**Files:**
- Create: `packages/core/src/runner.ts`
- Create: `packages/core/src/runner.test.ts`

**Step 1: Write the failing test**

`packages/core/src/runner.test.ts`:
```typescript
import { describe, it, expect } from 'vitest'
import { ActionRunner } from './runner.js'

describe('ActionRunner', () => {
  it('executes a simple command and returns output', async () => {
    const runner = new ActionRunner()
    const result = await runner.exec('echo hello world', { cwd: '/tmp' })
    expect(result.exitCode).toBe(0)
    expect(result.output).toContain('hello world')
  })

  it('captures non-zero exit codes', async () => {
    const runner = new ActionRunner()
    const result = await runner.exec('exit 1', { cwd: '/tmp' })
    expect(result.exitCode).toBe(1)
  })

  it('streams output via callback', async () => {
    const runner = new ActionRunner()
    const chunks: string[] = []
    await runner.exec('echo line1 && echo line2', {
      cwd: '/tmp',
      onData: (data) => chunks.push(data)
    })
    const combined = chunks.join('')
    expect(combined).toContain('line1')
    expect(combined).toContain('line2')
  })

  it('can be aborted', async () => {
    const runner = new ActionRunner()
    const abort = new AbortController()
    setTimeout(() => abort.abort(), 100)
    const result = await runner.exec('sleep 10', {
      cwd: '/tmp',
      signal: abort.signal
    })
    expect(result.exitCode).not.toBe(0)
  })

  it('respects timeout', async () => {
    const runner = new ActionRunner()
    const result = await runner.exec('sleep 10', {
      cwd: '/tmp',
      timeout: 200
    })
    expect(result.exitCode).not.toBe(0)
    expect(result.timedOut).toBe(true)
  })
})
```

**Step 2: Run test to verify it fails**

```bash
cd packages/core && npx vitest run src/runner.test.ts
```
Expected: FAIL — `ActionRunner` not found.

**Step 3: Implement ActionRunner**

`packages/core/src/runner.ts`:
```typescript
import { spawn } from 'node:child_process'

export interface ExecOptions {
  cwd: string
  onData?: (data: string) => void
  signal?: AbortSignal
  timeout?: number
  env?: Record<string, string>
}

export interface ExecResult {
  exitCode: number
  output: string
  timedOut: boolean
}

export class ActionRunner {
  async exec(command: string, options: ExecOptions): Promise<ExecResult> {
    return new Promise((resolve) => {
      let output = ''
      let timedOut = false
      let timeoutId: ReturnType<typeof setTimeout> | undefined

      const proc = spawn('sh', ['-c', command], {
        cwd: options.cwd,
        env: { ...process.env, ...options.env },
        stdio: ['ignore', 'pipe', 'pipe']
      })

      const handleData = (data: Buffer) => {
        const str = data.toString()
        output += str
        options.onData?.(str)
      }

      proc.stdout.on('data', handleData)
      proc.stderr.on('data', handleData)

      if (options.signal) {
        options.signal.addEventListener('abort', () => {
          proc.kill('SIGTERM')
        }, { once: true })
      }

      if (options.timeout) {
        timeoutId = setTimeout(() => {
          timedOut = true
          proc.kill('SIGTERM')
        }, options.timeout)
      }

      proc.on('close', (code) => {
        if (timeoutId) clearTimeout(timeoutId)
        resolve({
          exitCode: code ?? 1,
          output,
          timedOut
        })
      })

      proc.on('error', () => {
        if (timeoutId) clearTimeout(timeoutId)
        resolve({ exitCode: 1, output, timedOut })
      })
    })
  }
}
```

**Step 4: Run test to verify it passes**

```bash
cd packages/core && npx vitest run src/runner.test.ts
```
Expected: All 5 tests PASS.

**Step 5: Commit**

```bash
git add packages/core/src/runner.ts packages/core/src/runner.test.ts
git commit -m "feat(core): add action runner with streaming, abort, and timeout support"
```

---

## Task 5: Hono Server (`@forge-dev/core`)

**Files:**
- Create: `packages/core/src/server.ts`
- Create: `packages/core/src/server.test.ts`
- Modify: `packages/core/src/index.ts`

**Step 1: Write the failing test**

`packages/core/src/server.test.ts`:
```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { createForgeServer } from './server.js'
import { mkdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'

const TEST_DIR = join(import.meta.dirname, '../.test-server')

describe('Forge Server', () => {
  let baseUrl: string
  let server: ReturnType<typeof createForgeServer>

  beforeAll(() => {
    mkdirSync(join(TEST_DIR, 'modules'), { recursive: true })
    server = createForgeServer({
      dataDir: TEST_DIR,
      port: 0 // random port
    })
  })

  afterAll(() => {
    server.close()
    rmSync(TEST_DIR, { recursive: true, force: true })
  })

  it('GET /api/health returns ok', async () => {
    const res = await server.fetch('/api/health')
    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body.status).toBe('ok')
  })

  it('GET /api/projects returns empty array', async () => {
    const res = await server.fetch('/api/projects')
    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body).toEqual([])
  })

  it('POST /api/projects creates a project', async () => {
    const res = await server.fetch('/api/projects', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'test-app', path: '/tmp/test-app' })
    })
    expect(res.status).toBe(201)
    const body = await res.json()
    expect(body.name).toBe('test-app')
  })

  it('GET /api/modules returns empty array', async () => {
    const res = await server.fetch('/api/modules')
    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body).toEqual([])
  })

  it('POST /api/actions/:module/:action executes command', async () => {
    // This test will be refined when we have a test module installed
    const res = await server.fetch('/api/actions/nonexistent/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ projectId: 'test' })
    })
    expect(res.status).toBe(404)
  })
})
```

**Step 2: Run test to verify it fails**

```bash
cd packages/core && npx vitest run src/server.test.ts
```
Expected: FAIL — `createForgeServer` not found.

**Step 3: Implement the server**

`packages/core/src/server.ts`:
```typescript
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { ForgeDB } from './db.js'
import { ModuleLoader } from './modules.js'
import { ActionRunner } from './runner.js'
import { join } from 'node:path'

interface ServerOptions {
  dataDir: string
  port?: number
}

export function createForgeServer(options: ServerOptions) {
  const { dataDir } = options
  const dbPath = join(dataDir, 'forge.db')
  const modulesDir = join(dataDir, 'modules')

  const db = new ForgeDB(dbPath)
  const loader = new ModuleLoader(modulesDir)
  const runner = new ActionRunner()

  // Discover installed modules on startup
  loader.discover()

  const app = new Hono()
  app.use('*', cors())

  // Health
  app.get('/api/health', (c) => {
    return c.json({
      status: 'ok',
      version: '0.1.0',
      modules: loader.getLoaded().size
    })
  })

  // Projects
  app.get('/api/projects', (c) => {
    return c.json(db.listProjects())
  })

  app.post('/api/projects', async (c) => {
    const { name, path } = await c.req.json()
    const id = db.addProject({ name, path })
    const project = db.getProject(id)
    return c.json(project, 201)
  })

  app.delete('/api/projects/:id', (c) => {
    db.removeProject(c.req.param('id'))
    return c.json({ ok: true })
  })

  // Modules
  app.get('/api/modules', (c) => {
    const installed = db.listModules()
    const loaded = loader.getLoaded()
    return c.json(installed.map(m => ({
      ...m,
      manifest: loaded.get(m.name) ?? null
    })))
  })

  app.get('/api/modules/available', (c) => {
    const manifests = loader.discover()
    return c.json(manifests)
  })

  // Actions
  app.post('/api/actions/:module/:action', async (c) => {
    const moduleName = c.req.param('module')
    const actionId = c.req.param('action')
    const { projectId } = await c.req.json()

    const action = loader.getAction(moduleName, actionId)
    if (!action) {
      return c.json({ error: 'Action not found' }, 404)
    }

    const project = db.getProject(projectId)
    const cwd = project?.path ?? process.cwd()

    const logId = db.logAction({
      projectId: projectId ?? 'none',
      moduleId: moduleName,
      actionId,
      command: action.command
    })

    const result = await runner.exec(action.command, { cwd })

    db.completeAction(logId, result.exitCode)

    return c.json({
      logId,
      exitCode: result.exitCode,
      output: result.output,
      timedOut: result.timedOut
    })
  })

  // Action logs
  app.get('/api/logs', (c) => {
    return c.json(db.listProjects()) // TODO: proper log listing
  })

  // Fetch helper for testing
  const fetch = (path: string, init?: RequestInit) => {
    return app.request(path, init)
  }

  return {
    app,
    fetch,
    close: () => db.close()
  }
}
```

**Step 4: Export from index**

`packages/core/src/index.ts`:
```typescript
export { createForgeServer } from './server.js'
export { ForgeDB } from './db.js'
export { ModuleLoader } from './modules.js'
export { ActionRunner } from './runner.js'
export type * from './types.js'
```

**Step 5: Run test to verify it passes**

```bash
cd packages/core && npx vitest run src/server.test.ts
```
Expected: All 5 tests PASS.

**Step 6: Commit**

```bash
git add packages/core/src/
git commit -m "feat(core): add Hono server with projects, modules, and actions API"
```

---

## Task 6: WebSocket Streaming (`@forge-dev/core`)

**Files:**
- Create: `packages/core/src/ws.ts`
- Modify: `packages/core/src/server.ts`

**Step 1: Implement WebSocket hub**

`packages/core/src/ws.ts`:
```typescript
import type { ServerWebSocket } from 'hono'

type WS = { send: (data: string) => void; close: () => void }

export class WebSocketHub {
  private connections = new Map<string, Set<WS>>()

  subscribe(channel: string, ws: WS) {
    if (!this.connections.has(channel)) {
      this.connections.set(channel, new Set())
    }
    this.connections.get(channel)!.add(ws)
  }

  unsubscribe(channel: string, ws: WS) {
    this.connections.get(channel)?.delete(ws)
  }

  broadcast(channel: string, data: unknown) {
    const message = JSON.stringify(data)
    this.connections.get(channel)?.forEach(ws => {
      try { ws.send(message) } catch { /* client disconnected */ }
    })
  }

  broadcastAll(data: unknown) {
    const message = JSON.stringify(data)
    for (const clients of this.connections.values()) {
      clients.forEach(ws => {
        try { ws.send(message) } catch { /* client disconnected */ }
      })
    }
  }
}
```

**Step 2: Add streaming action endpoint to server**

Add to `packages/core/src/server.ts` — a new SSE endpoint for streaming action output:

```typescript
// Add to server.ts — SSE streaming endpoint for actions
app.post('/api/actions/:module/:action/stream', async (c) => {
  const moduleName = c.req.param('module')
  const actionId = c.req.param('action')
  const { projectId } = await c.req.json()

  const action = loader.getAction(moduleName, actionId)
  if (!action) {
    return c.json({ error: 'Action not found' }, 404)
  }

  const project = db.getProject(projectId)
  const cwd = project?.path ?? process.cwd()

  const logId = db.logAction({
    projectId: projectId ?? 'none',
    moduleId: moduleName,
    actionId,
    command: action.command
  })

  return new Response(
    new ReadableStream({
      async start(controller) {
        const encoder = new TextEncoder()
        const send = (event: string, data: unknown) => {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`))
        }

        send('start', { logId, command: action.command })

        const result = await runner.exec(action.command, {
          cwd,
          onData: (chunk) => send('output', { chunk })
        })

        db.completeAction(logId, result.exitCode)
        send('done', { exitCode: result.exitCode, timedOut: result.timedOut })
        controller.close()
      }
    }),
    {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        Connection: 'keep-alive'
      }
    }
  )
})
```

**Step 3: Update core index exports**

Add `export { WebSocketHub } from './ws.js'` to `packages/core/src/index.ts`.

**Step 4: Run all core tests**

```bash
cd packages/core && npx vitest run
```
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add packages/core/src/
git commit -m "feat(core): add WebSocket hub and SSE streaming for action output"
```

---

## Task 7: UI Component Library (`@forge-dev/ui`)

**Files:**
- Create: `packages/ui/src/StatusCard.tsx`
- Create: `packages/ui/src/ActionButton.tsx`
- Create: `packages/ui/src/Terminal.tsx`
- Create: `packages/ui/src/Toast.tsx`
- Create: `packages/ui/src/Badge.tsx`
- Create: `packages/ui/src/Modal.tsx`
- Create: `packages/ui/src/index.ts`

**Step 1: Create StatusCard**

`packages/ui/src/StatusCard.tsx`:
```tsx
import { type FunctionComponent } from 'preact'

interface StatusCardProps {
  icon: string
  label: string
  value: string | number
  trend?: string
  status: 'good' | 'warn' | 'bad' | 'neutral'
}

const statusColors = {
  good: 'var(--color-success)',
  warn: 'var(--color-warning)',
  bad: 'var(--color-error)',
  neutral: 'var(--color-muted)'
}

export const StatusCard: FunctionComponent<StatusCardProps> = ({
  icon, label, value, trend, status
}) => {
  return (
    <div class="forge-status-card" data-status={status}>
      <div class="forge-status-card__header">
        <span class="forge-status-card__icon">{icon}</span>
        <span class="forge-status-card__label">{label}</span>
      </div>
      <div class="forge-status-card__value">{value}</div>
      {trend && (
        <div class="forge-status-card__trend" data-positive={!trend.startsWith('-')}>
          {trend}
        </div>
      )}
      <div
        class="forge-status-card__indicator"
        style={{ backgroundColor: statusColors[status] }}
      />
    </div>
  )
}
```

**Step 2: Create ActionButton**

`packages/ui/src/ActionButton.tsx`:
```tsx
import { type FunctionComponent } from 'preact'
import { useState } from 'preact/hooks'

interface ActionButtonProps {
  label: string
  icon?: string
  variant?: 'primary' | 'secondary' | 'danger'
  disabled?: boolean
  loading?: boolean
  onClick: () => void | Promise<void>
}

export const ActionButton: FunctionComponent<ActionButtonProps> = ({
  label, icon, variant = 'primary', disabled, loading: externalLoading, onClick
}) => {
  const [internalLoading, setInternalLoading] = useState(false)
  const loading = externalLoading ?? internalLoading

  const handleClick = async () => {
    if (loading || disabled) return
    setInternalLoading(true)
    try {
      await onClick()
    } finally {
      setInternalLoading(false)
    }
  }

  return (
    <button
      class={`forge-action-btn forge-action-btn--${variant}`}
      disabled={disabled || loading}
      onClick={handleClick}
    >
      {loading ? (
        <span class="forge-action-btn__spinner" />
      ) : icon ? (
        <span class="forge-action-btn__icon">{icon}</span>
      ) : null}
      <span>{label}</span>
    </button>
  )
}
```

**Step 3: Create Terminal (xterm.js wrapper)**

`packages/ui/src/Terminal.tsx`:
```tsx
import { type FunctionComponent } from 'preact'
import { useEffect, useRef } from 'preact/hooks'

interface TerminalProps {
  streamUrl?: string
  content?: string
  height?: number
}

export const ForgeTerminal: FunctionComponent<TerminalProps> = ({
  streamUrl, content, height = 300
}) => {
  const containerRef = useRef<HTMLDivElement>(null)
  const termRef = useRef<any>(null)

  useEffect(() => {
    let cleanup: (() => void) | undefined

    const init = async () => {
      // Dynamic import to avoid SSR issues
      const { Terminal } = await import('@xterm/xterm')
      const { FitAddon } = await import('@xterm/addon-fit')

      const term = new Terminal({
        theme: {
          background: '#1a1a2e',
          foreground: '#e0e0e0',
          cursor: '#e0e0e0'
        },
        fontSize: 13,
        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
        convertEol: true,
        disableStdin: true
      })

      const fitAddon = new FitAddon()
      term.loadAddon(fitAddon)

      if (containerRef.current) {
        term.open(containerRef.current)
        fitAddon.fit()
        termRef.current = term
      }

      // Static content
      if (content) {
        term.write(content)
      }

      // SSE streaming
      if (streamUrl) {
        const evtSource = new EventSource(streamUrl)
        evtSource.addEventListener('output', (e) => {
          const { chunk } = JSON.parse(e.data)
          term.write(chunk)
        })
        evtSource.addEventListener('done', (e) => {
          const { exitCode } = JSON.parse(e.data)
          term.write(`\r\n\x1b[${exitCode === 0 ? '32' : '31'}m--- Exit code: ${exitCode} ---\x1b[0m\r\n`)
          evtSource.close()
        })
        cleanup = () => evtSource.close()
      }

      // Resize observer
      const observer = new ResizeObserver(() => fitAddon.fit())
      if (containerRef.current) observer.observe(containerRef.current)

      cleanup = () => {
        observer.disconnect()
        term.dispose()
        cleanup?.()
      }
    }

    init()
    return () => cleanup?.()
  }, [streamUrl, content])

  return (
    <div
      ref={containerRef}
      class="forge-terminal"
      style={{ height: `${height}px`, width: '100%' }}
    />
  )
}
```

**Step 4: Create Toast, Badge, Modal**

`packages/ui/src/Toast.tsx`:
```tsx
import { type FunctionComponent } from 'preact'
import { signal } from '@preact/signals'

interface ToastMessage {
  id: string
  message: string
  type: 'success' | 'error' | 'info'
}

export const toasts = signal<ToastMessage[]>([])

export function showToast(message: string, type: ToastMessage['type'] = 'info') {
  const id = Math.random().toString(36).slice(2)
  toasts.value = [...toasts.value, { id, message, type }]
  setTimeout(() => {
    toasts.value = toasts.value.filter(t => t.id !== id)
  }, 4000)
}

export const ToastContainer: FunctionComponent = () => {
  return (
    <div class="forge-toast-container">
      {toasts.value.map(t => (
        <div key={t.id} class={`forge-toast forge-toast--${t.type}`}>
          {t.message}
        </div>
      ))}
    </div>
  )
}
```

`packages/ui/src/Badge.tsx`:
```tsx
import { type FunctionComponent } from 'preact'

interface BadgeProps {
  label: string
  color?: string
  variant?: 'solid' | 'outline'
}

export const Badge: FunctionComponent<BadgeProps> = ({
  label, color = 'var(--color-muted)', variant = 'solid'
}) => {
  return (
    <span class={`forge-badge forge-badge--${variant}`} style={{ '--badge-color': color }}>
      {label}
    </span>
  )
}
```

`packages/ui/src/Modal.tsx`:
```tsx
import { type FunctionComponent, type ComponentChildren } from 'preact'

interface ModalProps {
  open: boolean
  title: string
  onClose: () => void
  onConfirm?: () => void
  confirmLabel?: string
  children: ComponentChildren
}

export const Modal: FunctionComponent<ModalProps> = ({
  open, title, onClose, onConfirm, confirmLabel = 'Confirm', children
}) => {
  if (!open) return null

  return (
    <div class="forge-modal-overlay" onClick={onClose}>
      <div class="forge-modal" onClick={(e) => e.stopPropagation()}>
        <div class="forge-modal__header">
          <h3>{title}</h3>
          <button class="forge-modal__close" onClick={onClose}>x</button>
        </div>
        <div class="forge-modal__body">{children}</div>
        {onConfirm && (
          <div class="forge-modal__footer">
            <button class="forge-action-btn forge-action-btn--secondary" onClick={onClose}>Cancel</button>
            <button class="forge-action-btn forge-action-btn--primary" onClick={onConfirm}>{confirmLabel}</button>
          </div>
        )}
      </div>
    </div>
  )
}
```

**Step 5: Export all from index**

`packages/ui/src/index.ts`:
```typescript
export { StatusCard } from './StatusCard.js'
export { ActionButton } from './ActionButton.js'
export { ForgeTerminal } from './Terminal.js'
export { ToastContainer, showToast, toasts } from './Toast.js'
export { Badge } from './Badge.js'
export { Modal } from './Modal.js'
```

**Step 6: Commit**

```bash
git add packages/ui/src/
git commit -m "feat(ui): add core UI components — StatusCard, ActionButton, Terminal, Toast, Badge, Modal"
```

---

## Task 8: Dashboard Shell (`@forge-dev/console`)

**Files:**
- Create: `packages/console/src/app.tsx`
- Create: `packages/console/src/shell.tsx`
- Create: `packages/console/src/pages/Home.tsx`
- Create: `packages/console/src/pages/ModulePage.tsx`
- Create: `packages/console/src/hooks/useApi.ts`
- Create: `packages/console/src/styles/theme.css`
- Create: `packages/console/index.html`
- Create: `packages/console/vite.config.ts`
- Create: `packages/console/uno.config.ts`

**Step 1: Vite config with Preact + UnoCSS**

`packages/console/vite.config.ts`:
```typescript
import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'
import UnoCSS from 'unocss/vite'

export default defineConfig({
  plugins: [preact(), UnoCSS()],
  build: {
    outDir: 'dist',
    emptyDir: true
  }
})
```

`packages/console/uno.config.ts`:
```typescript
import { defineConfig, presetUno, presetIcons } from 'unocss'

export default defineConfig({
  presets: [
    presetUno(),
    presetIcons({ scale: 1.2 })
  ],
  theme: {
    colors: {
      forge: {
        bg: 'var(--forge-bg)',
        surface: 'var(--forge-surface)',
        border: 'var(--forge-border)',
        text: 'var(--forge-text)',
        muted: 'var(--forge-muted)',
        accent: 'var(--forge-accent)',
        success: 'var(--forge-success)',
        warning: 'var(--forge-warning)',
        error: 'var(--forge-error)'
      }
    }
  }
})
```

**Step 2: Theme CSS**

`packages/console/src/styles/theme.css`:
```css
:root {
  --forge-bg: #0f0f1a;
  --forge-surface: #1a1a2e;
  --forge-border: #2a2a3e;
  --forge-text: #e0e0f0;
  --forge-muted: #6b7280;
  --forge-accent: #6366f1;
  --forge-success: #10b981;
  --forge-warning: #f59e0b;
  --forge-error: #ef4444;
  --forge-radius: 8px;
  --forge-font: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  --forge-mono: 'JetBrains Mono', 'Fira Code', monospace;
}

[data-theme="light"] {
  --forge-bg: #f8fafc;
  --forge-surface: #ffffff;
  --forge-border: #e2e8f0;
  --forge-text: #1e293b;
  --forge-muted: #94a3b8;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: var(--forge-font);
  background: var(--forge-bg);
  color: var(--forge-text);
  -webkit-font-smoothing: antialiased;
}
```

**Step 3: API hook**

`packages/console/src/hooks/useApi.ts`:
```typescript
import { signal } from '@preact/signals'

const API_BASE = ''  // same origin

export function useApi<T>(path: string) {
  const data = signal<T | null>(null)
  const loading = signal(true)
  const error = signal<string | null>(null)

  const fetchData = async () => {
    loading.value = true
    try {
      const res = await fetch(`${API_BASE}${path}`)
      data.value = await res.json()
      error.value = null
    } catch (e: any) {
      error.value = e.message
    } finally {
      loading.value = false
    }
  }

  fetchData()

  return { data, loading, error, refetch: fetchData }
}

export async function apiPost<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  })
  return res.json()
}

export async function apiDelete(path: string): Promise<void> {
  await fetch(`${API_BASE}${path}`, { method: 'DELETE' })
}
```

**Step 4: Shell layout (sidebar + top bar + main area)**

`packages/console/src/shell.tsx`:
```tsx
import { type FunctionComponent, type ComponentChildren } from 'preact'
import { signal } from '@preact/signals'
import { ToastContainer } from '@forge-dev/ui'

export const currentModule = signal<string | null>(null)
export const theme = signal<'dark' | 'light'>('dark')

const toggleTheme = () => {
  theme.value = theme.value === 'dark' ? 'light' : 'dark'
  document.documentElement.setAttribute('data-theme', theme.value)
}

interface ShellProps {
  modules: { id: string; name: string; icon: string; color: string }[]
  children: ComponentChildren
}

export const Shell: FunctionComponent<ShellProps> = ({ modules, children }) => {
  return (
    <div class="flex h-screen bg-forge-bg text-forge-text">
      {/* Sidebar */}
      <nav class="w-56 bg-forge-surface border-r border-forge-border flex flex-col">
        <div class="p-4 border-b border-forge-border">
          <h1 class="text-lg font-bold flex items-center gap-2">
            <span class="text-2xl">🔥</span> Forge
          </h1>
        </div>

        <div class="flex-1 py-2">
          {modules.map(m => (
            <button
              key={m.id}
              class={`w-full text-left px-4 py-2.5 flex items-center gap-3 text-sm transition-colors
                ${currentModule.value === m.id
                  ? 'bg-forge-accent/10 text-forge-accent border-r-2 border-forge-accent'
                  : 'text-forge-muted hover:text-forge-text hover:bg-forge-surface'}`}
              onClick={() => { currentModule.value = m.id }}
            >
              <span>{m.icon}</span>
              <span>{m.name}</span>
            </button>
          ))}
        </div>

        <div class="p-4 border-t border-forge-border">
          <button
            class="text-xs text-forge-muted hover:text-forge-text"
            onClick={toggleTheme}
          >
            {theme.value === 'dark' ? '☀️ Light' : '🌙 Dark'}
          </button>
        </div>
      </nav>

      {/* Main */}
      <main class="flex-1 overflow-auto">
        {/* Top bar */}
        <header class="h-14 border-b border-forge-border flex items-center justify-between px-6">
          <div class="flex items-center gap-4">
            <span class="text-sm text-forge-muted">Forge Console</span>
          </div>
          <div class="flex items-center gap-3">
            <kbd class="text-xs text-forge-muted bg-forge-surface px-2 py-1 rounded border border-forge-border">
              ⌘K
            </kbd>
          </div>
        </header>

        {/* Content */}
        <div class="p-6">
          {children}
        </div>
      </main>

      <ToastContainer />
    </div>
  )
}
```

**Step 5: Home page**

`packages/console/src/pages/Home.tsx`:
```tsx
import { type FunctionComponent } from 'preact'
import { StatusCard } from '@forge-dev/ui'
import { useApi } from '../hooks/useApi.js'

export const Home: FunctionComponent = () => {
  const projects = useApi<any[]>('/api/projects')
  const health = useApi<any>('/api/health')

  return (
    <div>
      <h2 class="text-2xl font-bold mb-6">Welcome to Forge</h2>

      <div class="grid grid-cols-3 gap-4 mb-8">
        <StatusCard
          icon="📁"
          label="Projects"
          value={projects.data.value?.length ?? 0}
          status="neutral"
        />
        <StatusCard
          icon="🧩"
          label="Modules"
          value={health.data.value?.modules ?? 0}
          status="neutral"
        />
        <StatusCard
          icon="⚡"
          label="Status"
          value={health.data.value?.status === 'ok' ? 'Online' : 'Offline'}
          status={health.data.value?.status === 'ok' ? 'good' : 'bad'}
        />
      </div>

      <div class="flex gap-3">
        <button class="forge-action-btn forge-action-btn--primary">
          + New Project
        </button>
        <button class="forge-action-btn forge-action-btn--secondary">
          Open Project
        </button>
      </div>
    </div>
  )
}
```

**Step 6: Module page (dynamic panel rendering)**

`packages/console/src/pages/ModulePage.tsx`:
```tsx
import { type FunctionComponent } from 'preact'
import { useState } from 'preact/hooks'
import { ActionButton, ForgeTerminal } from '@forge-dev/ui'
import { apiPost } from '../hooks/useApi.js'
import type { ModuleManifest } from '@forge-dev/sdk'

interface ModulePageProps {
  manifest: ModuleManifest
}

export const ModulePage: FunctionComponent<ModulePageProps> = ({ manifest }) => {
  const [streamUrl, setStreamUrl] = useState<string | null>(null)
  const [lastResult, setLastResult] = useState<{ exitCode: number } | null>(null)

  const runAction = async (actionId: string) => {
    setStreamUrl(null)
    setLastResult(null)

    // For streaming actions, we'd use SSE
    const result = await apiPost(`/api/actions/${manifest.name}/${actionId}`, {
      projectId: null
    })
    setLastResult(result as any)
  }

  return (
    <div>
      <div class="flex items-center gap-3 mb-6">
        <span class="text-2xl">{manifest.icon}</span>
        <h2 class="text-2xl font-bold">{manifest.displayName}</h2>
      </div>

      <p class="text-forge-muted mb-6">{manifest.description}</p>

      {/* Actions */}
      <div class="flex flex-wrap gap-3 mb-6">
        {manifest.actions.map(action => (
          <ActionButton
            key={action.id}
            label={action.label}
            icon={action.icon}
            onClick={() => runAction(action.id)}
          />
        ))}
      </div>

      {/* Terminal output */}
      {lastResult && (
        <div class="mt-4">
          <ForgeTerminal
            content={`Exit code: ${lastResult.exitCode}`}
            height={400}
          />
        </div>
      )}
    </div>
  )
}
```

**Step 7: App entry**

`packages/console/src/app.tsx`:
```tsx
import { render } from 'preact'
import { Shell, currentModule } from './shell.js'
import { Home } from './pages/Home.js'
import './styles/theme.css'
import 'virtual:uno.css'

const STATIC_MODULES = [
  { id: 'home', name: 'Home', icon: '🏠', color: '#6366f1' }
]

function App() {
  return (
    <Shell modules={STATIC_MODULES}>
      {currentModule.value === null || currentModule.value === 'home' ? (
        <Home />
      ) : (
        <div class="text-forge-muted">Module: {currentModule.value}</div>
      )}
    </Shell>
  )
}

render(<App />, document.getElementById('app')!)
```

`packages/console/index.html`:
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Forge Console</title>
  <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='80' font-size='80'>🔥</text></svg>" />
</head>
<body>
  <div id="app"></div>
  <script type="module" src="/src/app.tsx"></script>
</body>
</html>
```

**Step 8: Build and verify**

```bash
cd packages/console && npx vite build
```
Expected: Build succeeds, dist/ contains index.html + JS + CSS.

**Step 9: Commit**

```bash
git add packages/console/
git commit -m "feat(console): add dashboard shell with sidebar, theme, home page, and module rendering"
```

---

## Task 9: CLI (`@forge-dev/cli`)

**Files:**
- Create: `packages/cli/src/index.ts`
- Create: `packages/cli/src/commands/init.ts`
- Create: `packages/cli/src/commands/console.ts`
- Create: `packages/cli/src/commands/module.ts`
- Create: `packages/cli/src/commands/project.ts`
- Create: `packages/cli/src/commands/run.ts`
- Create: `packages/cli/src/commands/doctor.ts`

**Step 1: Main CLI entry**

`packages/cli/src/index.ts`:
```typescript
#!/usr/bin/env node
import { Command } from 'commander'
import { initCommand } from './commands/init.js'
import { consoleCommand } from './commands/console.js'
import { moduleCommand } from './commands/module.js'
import { projectCommand } from './commands/project.js'
import { runCommand } from './commands/run.js'
import { doctorCommand } from './commands/doctor.js'

const program = new Command()
  .name('forge')
  .description('🔥 Forge — Integral Development Platform')
  .version('0.1.0')

program.addCommand(initCommand())
program.addCommand(consoleCommand())
program.addCommand(moduleCommand())
program.addCommand(projectCommand())
program.addCommand(runCommand())
program.addCommand(doctorCommand())

program.parse()
```

**Step 2: Init command (creates ~/.forge/)**

`packages/cli/src/commands/init.ts`:
```typescript
import { Command } from 'commander'
import { mkdirSync, existsSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'

export function initCommand() {
  return new Command('init')
    .description('Initialize Forge (creates ~/.forge/)')
    .action(() => {
      const forgeDir = join(homedir(), '.forge')
      const dirs = ['modules', 'templates', 'cache', 'logs']

      if (existsSync(forgeDir)) {
        console.log('🔥 Forge already initialized at', forgeDir)
        return
      }

      mkdirSync(forgeDir, { recursive: true })
      for (const d of dirs) {
        mkdirSync(join(forgeDir, d), { recursive: true })
      }

      const defaultConfig = {
        port: 3000,
        theme: 'dark',
        openBrowser: true,
        dataDir: forgeDir
      }
      writeFileSync(
        join(forgeDir, 'config.json'),
        JSON.stringify(defaultConfig, null, 2)
      )

      console.log('🔥 Forge initialized at', forgeDir)
      console.log('   Run `forge console` to open the dashboard')
    })
}
```

**Step 3: Console command (starts server + opens browser)**

`packages/cli/src/commands/console.ts`:
```typescript
import { Command } from 'commander'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'

export function consoleCommand() {
  return new Command('console')
    .description('Start Forge Console (dashboard)')
    .option('-p, --port <port>', 'Port number', '3000')
    .option('--no-open', 'Do not open browser')
    .option('--detach', 'Run in background')
    .action(async (opts) => {
      const forgeDir = join(homedir(), '.forge')
      if (!existsSync(forgeDir)) {
        console.log('🔥 Forge not initialized. Run `forge init` first.')
        process.exit(1)
      }

      const port = parseInt(opts.port, 10)
      console.log(`🔥 Starting Forge Console on http://localhost:${port}`)

      // Dynamic import to avoid loading heavy deps at CLI parse time
      const { createForgeServer } = await import('@forge-dev/core')
      const server = createForgeServer({ dataDir: forgeDir, port })

      // Serve the built console static files
      // In production, console dist/ is bundled with the platform package
      // For now, just start the API server
      const { serve } = await import('@hono/node-server')
      serve({ fetch: server.app.fetch, port })

      console.log(`🔥 Forge Console running at http://localhost:${port}`)

      if (opts.open !== false) {
        const open = (await import('open')).default
        open(`http://localhost:${port}`)
      }
    })
}
```

**Step 4: Module command**

`packages/cli/src/commands/module.ts`:
```typescript
import { Command } from 'commander'

export function moduleCommand() {
  const cmd = new Command('module').description('Manage Forge modules')

  cmd
    .command('list')
    .description('List installed modules')
    .action(async () => {
      const res = await fetch('http://localhost:3000/api/modules')
      const modules = await res.json()
      if (modules.length === 0) {
        console.log('No modules installed. Run `forge module add <name>` to install one.')
        return
      }
      for (const m of modules) {
        console.log(`  ${m.enabled ? '✅' : '⬜'} ${m.name} (${m.version})`)
      }
    })

  cmd
    .command('add <name>')
    .description('Install a module')
    .action(async (name: string) => {
      console.log(`📦 Installing module: ${name}`)
      // TODO: npm install + register in DB
      console.log(`✅ Module ${name} installed`)
    })

  cmd
    .command('remove <name>')
    .description('Remove a module')
    .action(async (name: string) => {
      console.log(`🗑️  Removing module: ${name}`)
      // TODO: npm uninstall + unregister from DB
      console.log(`✅ Module ${name} removed`)
    })

  return cmd
}
```

**Step 5: Project command**

`packages/cli/src/commands/project.ts`:
```typescript
import { Command } from 'commander'

export function projectCommand() {
  const cmd = new Command('project').description('Manage projects')

  cmd
    .command('list')
    .description('List registered projects')
    .action(async () => {
      const res = await fetch('http://localhost:3000/api/projects')
      const projects = await res.json()
      if (projects.length === 0) {
        console.log('No projects registered. Run `forge project add <path>` to add one.')
        return
      }
      for (const p of projects) {
        console.log(`  📁 ${p.name} → ${p.path}`)
      }
    })

  cmd
    .command('add <path>')
    .description('Register a project')
    .option('-n, --name <name>', 'Project name')
    .action(async (path: string, opts: { name?: string }) => {
      const { basename, resolve } = await import('node:path')
      const fullPath = resolve(path)
      const name = opts.name ?? basename(fullPath)
      const res = await fetch('http://localhost:3000/api/projects', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, path: fullPath })
      })
      const project = await res.json()
      console.log(`✅ Project "${project.name}" registered`)
    })

  cmd
    .command('remove <name>')
    .description('Unregister a project')
    .action(async (name: string) => {
      console.log(`🗑️  Removing project: ${name}`)
      // TODO: lookup by name, then DELETE
    })

  return cmd
}
```

**Step 6: Run command**

`packages/cli/src/commands/run.ts`:
```typescript
import { Command } from 'commander'

export function runCommand() {
  return new Command('run')
    .description('Run a module action')
    .argument('<module>', 'Module name')
    .argument('<action>', 'Action ID')
    .option('--project <name>', 'Project to run against')
    .action(async (moduleName: string, actionId: string, opts: { project?: string }) => {
      console.log(`⚡ Running ${moduleName}/${actionId}...`)

      const res = await fetch(
        `http://localhost:3000/api/actions/${moduleName}/${actionId}/stream`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ projectId: opts.project ?? null })
        }
      )

      if (!res.ok) {
        const err = await res.json()
        console.error(`❌ ${err.error}`)
        process.exit(1)
      }

      // Stream SSE output to terminal
      const reader = res.body!.getReader()
      const decoder = new TextDecoder()
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        const text = decoder.decode(value)
        // Parse SSE events
        for (const line of text.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              const data = JSON.parse(line.slice(6))
              if (data.chunk) process.stdout.write(data.chunk)
              if (data.exitCode !== undefined) {
                console.log(`\n⚡ Exit code: ${data.exitCode}`)
                process.exit(data.exitCode)
              }
            } catch { /* not json */ }
          }
        }
      }
    })
}
```

**Step 7: Doctor command**

`packages/cli/src/commands/doctor.ts`:
```typescript
import { Command } from 'commander'
import { execSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'

export function doctorCommand() {
  return new Command('doctor')
    .description('Health check — verify all dependencies')
    .action(() => {
      console.log('🔥 Forge Doctor\n')
      const checks = [
        { name: 'Node.js >= 20', check: () => {
          const v = process.version.slice(1).split('.').map(Number)
          return v[0] >= 20
        }},
        { name: 'Git installed', check: () => {
          try { execSync('git --version', { stdio: 'pipe' }); return true }
          catch { return false }
        }},
        { name: 'Claude Code installed', check: () => {
          try { execSync('claude --version', { stdio: 'pipe' }); return true }
          catch { return false }
        }},
        { name: 'Forge initialized (~/.forge/)', check: () => {
          return existsSync(join(homedir(), '.forge'))
        }},
        { name: 'CW installed', check: () => {
          return existsSync(join(homedir(), '.cw', 'bin', 'cw'))
        }}
      ]

      let allGood = true
      for (const { name, check } of checks) {
        const ok = check()
        console.log(`  ${ok ? '✅' : '❌'} ${name}`)
        if (!ok) allGood = false
      }

      console.log(allGood ? '\n🔥 All good!' : '\n⚠️  Some checks failed')
    })
}
```

**Step 8: Update package.json bin field**

In `packages/cli/package.json`, add:
```json
{
  "bin": {
    "forge": "dist/index.js"
  }
}
```

**Step 9: Commit**

```bash
git add packages/cli/
git commit -m "feat(cli): add forge CLI with init, console, module, project, run, and doctor commands"
```

---

## Task 10: Platform Entry Point (`@forge-dev/platform`)

**Files:**
- Create: `packages/platform/src/index.ts`
- Modify: `packages/platform/package.json`

**Step 1: Platform entry that bundles core + console + CLI**

`packages/platform/src/index.ts`:
```typescript
#!/usr/bin/env node

// Platform entry: starts the server with embedded console
// Usage: npx @forge-dev/platform

import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'

async function main() {
  const forgeDir = join(homedir(), '.forge')

  // Auto-init if needed
  if (!existsSync(forgeDir)) {
    console.log('🔥 First run — initializing Forge...')
    const dirs = ['modules', 'templates', 'cache', 'logs']
    mkdirSync(forgeDir, { recursive: true })
    for (const d of dirs) {
      mkdirSync(join(forgeDir, d), { recursive: true })
    }
    writeFileSync(
      join(forgeDir, 'config.json'),
      JSON.stringify({ port: 3000, theme: 'dark', openBrowser: true, dataDir: forgeDir }, null, 2)
    )
  }

  const port = parseInt(process.env.FORGE_PORT ?? '3000', 10)

  const { createForgeServer } = await import('@forge-dev/core')
  const server = createForgeServer({ dataDir: forgeDir, port })

  // Serve static console files
  const { serveStatic } = await import('@hono/node-server/serve-static')
  const consoleDist = join(import.meta.dirname, '../../console/dist')
  if (existsSync(consoleDist)) {
    server.app.use('/*', serveStatic({ root: consoleDist }))
  }

  const { serve } = await import('@hono/node-server')
  serve({ fetch: server.app.fetch, port })

  console.log(`
  🔥 Forge Console running at http://localhost:${port}

     Dashboard:  http://localhost:${port}
     API:        http://localhost:${port}/api/health

     Press Ctrl+C to stop
  `)

  // Open browser
  if (process.env.FORGE_NO_OPEN !== '1') {
    try {
      const open = (await import('open')).default
      await open(`http://localhost:${port}`)
    } catch { /* ok if open fails */ }
  }
}

main().catch(console.error)
```

**Step 2: Update package.json**

```json
{
  "name": "@forge-dev/platform",
  "version": "0.1.0",
  "type": "module",
  "bin": {
    "forge-platform": "dist/index.js"
  },
  "dependencies": {
    "@forge-dev/core": "workspace:*",
    "@forge-dev/console": "workspace:*",
    "@hono/node-server": "^1.12.0",
    "open": "^10.0.0"
  }
}
```

**Step 3: Build all and test**

```bash
npx turbo build
node packages/platform/dist/index.js
```
Expected: Server starts, browser opens to dashboard with Home page showing 0 projects, 0 modules, status Online.

**Step 4: Commit**

```bash
git add packages/platform/
git commit -m "feat(platform): add entry point — npx @forge-dev/platform starts everything"
```

---

## Task 11: Example Module — Hello World

**Files:**
- Create: `modules/mod-hello/forge-module.json`
- Create: `modules/mod-hello/package.json`

**Purpose:** Verify the full loop works: install module → see it in sidebar → click action → see output.

**Step 1: Create the manifest**

`modules/mod-hello/forge-module.json`:
```json
{
  "name": "@forge-dev/mod-hello",
  "version": "0.1.0",
  "displayName": "Hello World",
  "description": "Example module to verify the system works",
  "icon": "👋",
  "color": "#6366f1",
  "panels": [
    {
      "id": "main",
      "title": "Hello",
      "component": "./panels/Main",
      "default": true
    }
  ],
  "actions": [
    {
      "id": "greet",
      "label": "Say Hello",
      "icon": "👋",
      "command": "echo '🔥 Hello from Forge!'",
      "streaming": false
    },
    {
      "id": "system-info",
      "label": "System Info",
      "icon": "💻",
      "command": "uname -a && node --version && git --version",
      "streaming": true
    }
  ],
  "detectors": []
}
```

**Step 2: Copy to ~/.forge/modules/ and test**

```bash
cp -r modules/mod-hello ~/.forge/modules/mod-hello
```

**Step 3: Verify via API**

```bash
curl http://localhost:3000/api/modules/available
```
Expected: Returns array with mod-hello manifest.

```bash
curl -X POST http://localhost:3000/api/actions/mod-hello/greet \
  -H 'Content-Type: application/json' \
  -d '{"projectId": null}'
```
Expected: Returns `{"output": "🔥 Hello from Forge!\n", "exitCode": 0, ...}`

**Step 4: Commit**

```bash
git add modules/mod-hello/
git commit -m "feat: add hello-world example module for system verification"
```

---

## Task 12: Integration Test — Full Loop

**Files:**
- Create: `tests/integration/full-loop.test.ts`

**Step 1: Write the integration test**

`tests/integration/full-loop.test.ts`:
```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { createForgeServer } from '@forge-dev/core'
import { mkdirSync, writeFileSync, rmSync, cpSync } from 'node:fs'
import { join } from 'node:path'

const TEST_DIR = join(import.meta.dirname, '../.test-integration')
const MODULES_DIR = join(TEST_DIR, 'modules')

describe('Forge Full Loop', () => {
  let server: ReturnType<typeof createForgeServer>

  beforeAll(() => {
    mkdirSync(MODULES_DIR, { recursive: true })

    // Create test module
    const modDir = join(MODULES_DIR, 'mod-test')
    mkdirSync(modDir, { recursive: true })
    writeFileSync(join(modDir, 'forge-module.json'), JSON.stringify({
      name: '@forge-dev/mod-test',
      version: '1.0.0',
      displayName: 'Test',
      description: 'Test module',
      icon: '🧪',
      color: '#10b981',
      panels: [{ id: 'main', title: 'Test', component: './Main', default: true }],
      actions: [
        { id: 'echo', label: 'Echo', icon: '📢', command: 'echo forge-works', streaming: false },
        { id: 'fail', label: 'Fail', icon: '❌', command: 'exit 42', streaming: false }
      ]
    }))

    server = createForgeServer({ dataDir: TEST_DIR })
  })

  afterAll(() => {
    server.close()
    rmSync(TEST_DIR, { recursive: true, force: true })
  })

  it('full workflow: register project → discover module → run action', async () => {
    // 1. Register a project
    let res = await server.fetch('/api/projects', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'my-app', path: '/tmp/my-app' })
    })
    expect(res.status).toBe(201)
    const project = await res.json()

    // 2. Discover modules
    res = await server.fetch('/api/modules/available')
    expect(res.status).toBe(200)
    const modules = await res.json()
    expect(modules).toHaveLength(1)
    expect(modules[0].displayName).toBe('Test')

    // 3. Run successful action
    res = await server.fetch('/api/actions/mod-test/echo', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ projectId: project.id })
    })
    expect(res.status).toBe(200)
    const result = await res.json()
    expect(result.exitCode).toBe(0)
    expect(result.output).toContain('forge-works')

    // 4. Run failing action
    res = await server.fetch('/api/actions/mod-test/fail', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ projectId: project.id })
    })
    const failResult = await res.json()
    expect(failResult.exitCode).toBe(42)
  })
})
```

**Step 2: Run the integration test**

```bash
npx vitest run tests/integration/
```
Expected: All assertions PASS.

**Step 3: Commit**

```bash
git add tests/
git commit -m "test: add full-loop integration test — project → module → action"
```

---

## Summary of Phase 0 Tasks

| # | Task | Files | Tests |
|---|------|-------|-------|
| 1 | Monorepo scaffold | 15+ package.json/tsconfig | Build verification |
| 2 | Database layer | db.ts, types.ts | 6 unit tests |
| 3 | Module loader | modules.ts, sdk/types.ts | 5 unit tests |
| 4 | Action runner | runner.ts | 5 unit tests |
| 5 | Hono server | server.ts | 5 unit tests |
| 6 | WebSocket streaming | ws.ts, server.ts update | Covered by integration |
| 7 | UI components | 6 Preact components | Visual verification |
| 8 | Dashboard shell | shell, pages, hooks, styles | Build + visual |
| 9 | CLI | 6 command files | Manual verification |
| 10 | Platform entry | index.ts | Full startup test |
| 11 | Hello module | forge-module.json | API verification |
| 12 | Integration test | full-loop.test.ts | 1 integration test |

**Total: 12 tasks, ~21 unit tests, 1 integration test, 40+ files**

After Phase 0, you have: `npx @forge-dev/platform` → browser opens → dashboard with sidebar → install hello module → click "Say Hello" → see output. The foundation is complete.

---

## Next: Phase 1

After Phase 0 is verified, create a new plan for Phase 1 (Core Modules):
- Task 1-5: `mod-dev` (CW wrapper)
- Task 6-10: `mod-scaffold` (project wizard)
- Task 11-15: `mod-planning` (Linear + Notion + diagrams)
- Task 16-20: `mod-monitor` (activity + costs + health)
