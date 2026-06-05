# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Academic Research Scraper — microservices system for scraping SINTA (Indonesian academic index) data and displaying it via a web UI. Three services orchestrated via Docker Compose:

- **KP-Backend** (Python/FastAPI) — Scrapes SINTA, stores to MySQL, exposes API
- **KP-Penelitian-Dosen** (PHP Custom MVC) — Web UI, dashboard, reporting
- **MySQL** — Shared database server with separate DBs per service

Both KP-Backend and KP-Penelitian-Dosen are git submodules. Work inside their directories for service-specific changes.

## Common Commands

### Docker (Root)

```bash
# Start all services
docker compose up -d

# Rebuild after code changes
docker compose up -d --build

# View logs
docker compose logs -f [service_name]

# Stop all
docker compose down

# Stop and reset database
docker compose down -v

# Execute command in container
docker compose exec backend sh
docker compose exec frontend sh
docker compose exec mysql mysql -u academic_user -p
```

### Backend (KP-Backend/)

```bash
cd KP-Backend

# Install dependencies
uv sync

# Run dev server
uv run fastapi dev

# Run production
uv run fastapi run

# Run tests
uv run pytest

# Run specific test
uv run pytest tests/test_config.py -v

# Lint
uv run ruff check .

# Format
uv run ruff format .
```

### Frontend (KP-Penelitian-Dosen/)

No build step. Edit PHP files directly. For local dev with Laragon/XAMPP:

```bash
cd KP-Penelitian-Dosen
cp .env.example .env
# Import database/schema.sql
```

## Architecture

### Network Topology

```
Docker Network: academic_network

frontend:8081 ──HTTP──> backend:8000 ──HTTP──> SINTA website
      │                      │
      └───────PDO────────────┴───aiomysql───> mysql:3306
                                              ├── DB: kp-penelitian-dosen (frontend)
                                              └── DB: KP-Scrapping (backend)
```

### Data Flow

1. Backend scrapes SINTA → stores in `KP-Scrapping` DB
2. Frontend calls `GET /api/v1/sinta-authors` → syncs to `kp-penelitian-dosen` DB
3. Frontend displays data from its own DB

### Key Environment Variables

**Root `.env`:**
- `API_KEY` — Shared auth key between frontend/backend
- `BASE_URL` — Frontend public URL
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` — OAuth

**Backend additional:** `SINTA_AFFILIATION_ID=528` (UNIKOM), `SCHEDULER_ENABLED`, `SCRAPE_DAY_OF_MONTH`

## Service-Specific Docs

- `KP-Backend/README.md` — Backend API endpoints, scraping workflow
- `KP-Penelitian-Dosen/CLAUDE.md` — PHP MVC patterns, routing, controllers

## Development Notes

- **Backend**: Always use async I/O (`httpx`, `aiomysql`) for external calls. Use `uv` commands, not `pip`.
- **Frontend**: Custom MVC — no Composer. Read `app/core/Router.php` before modifying routes. Controllers extend `Controller`, models use `Database` PDO wrapper.
- **Database**: Schema changes require updating both `KP-Penelitian-Dosen/database/schema.sql` and backend ORM models.
- **CORS**: Backend `ALLOWED_ORIGINS` must include frontend `BASE_URL`.