# CLAUDE.md Guide

Every project should have a `CLAUDE.md` file at its root. This is Claude Code's project-level instruction file — Claude reads it automatically when entering the directory.

## Why It Matters

Without a `CLAUDE.md`, Claude:
- Doesn't know your tech stack or conventions
- Might run the wrong commands
- Won't know your testing patterns
- Could make changes you explicitly don't want

With a good `CLAUDE.md`, Claude:
- Follows your project's conventions from the start
- Runs the right dev/test/build commands
- Knows what NOT to touch
- Reads `TASK_NOTES.md` for session context

## Using the Template

```bash
cp ~/.cw/templates/CLAUDE.template.md ~/code/my-app/CLAUDE.md
```

Then fill in the sections. The most important ones:

### Stack

Be specific. Don't just say "Python" — say "Python 3.11 + Django 4.2 + PostgreSQL 15 + Redis".

### Development Commands

Claude needs to know how to run things:

```markdown
## Development
\```bash
# Setup
python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt

# Dev server
python manage.py runserver

# Tests
pytest tests/ -v

# Lint
ruff check . && mypy .

# Build
docker build -t my-app .
\```
```

### Working with me (Claude)

This section is critical. Tell Claude about session notes:

```markdown
## Working with me (Claude)
- If you see a TASK_NOTES.md or REVIEW_NOTES.md, read it first — it has context from previous sessions.
- Run tests after every change.
- Never touch `.env`, credentials, or secrets.
- Ask before making architectural changes.
```

### Do NOT

Explicit restrictions prevent expensive mistakes:

```markdown
## Do NOT
- Do not create or modify database migrations without confirmation
- Do not delete tests
- Do not change infrastructure config (Terraform, Docker Compose)
- Do not modify CI/CD pipeline files
- Do not change auth/permissions logic without explicit approval
```

## Tips

- **Be specific** — "Use `pytest` not `unittest`" is better than "run tests"
- **Include paths** — "Tests are in `tests/`, not `src/tests/`"
- **List tools** — If you use specific linters, formatters, or CLI tools, name them
- **Add context** — Link to ADRs, design docs, or important decisions
- **Update it** — Keep it current as the project evolves
