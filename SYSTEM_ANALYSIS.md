# System Analysis: Academic Research Scraper (Analisis Mendalam)

> **Versi Analisis**: 2.1  
> **Cakupan**: Berdasarkan pembacaan kode sumber aktual (`KP-Backend` & `KP-Penelitian-Dosen`)  
> **Status Proyek**: Aktif — Microservices, Docker-orchestrated

---

## Daftar Isi

1. [Gambaran Umum & Arsitektur](#1-gambaran-umum--arsitektur)
2. [Infrastruktur Docker](#2-infrastruktur-docker)
3. [Backend — KP-Backend (Python/FastAPI)](#3-backend--kp-backend-pythonfastapi)
   - [3.1 Stack & Dependensi](#31-stack--dependensi)
   - [3.2 Struktur Modul](#32-struktur-modul)
   - [3.3 Core Layer](#33-core-layer)
   - [3.4 Scraping Engine](#34-scraping-engine)
   - [3.5 Services Layer](#35-services-layer)
   - [3.6 API Layer](#36-api-layer)
   - [3.7 ORM Models](#37-orm-models)
4. [Frontend — KP-Penelitian-Dosen (PHP MVC)](#4-frontend--kp-penelitian-dosen-php-mvc)
   - [4.1 Stack & Framework](#41-stack--framework)
   - [4.2 Custom MVC Core](#42-custom-mvc-core)
   - [4.3 Routing Map](#43-routing-map)
   - [4.4 Controllers](#44-controllers)
   - [4.5 Models](#45-models)
   - [4.6 Views & Komponen UI](#46-views--komponen-ui)
5. [Skema Database](#5-skema-database)
6. [Alur Sistem (Workflows)](#6-alur-sistem-workflows)
7. [Keamanan & Konfigurasi](#7-keamanan--konfigurasi)
8. [Temuan & Isu yang Diidentifikasi](#8-temuan--isu-yang-diidentifikasi)
9. [Rekomendasi](#9-rekomendasi)

---

## 1. Gambaran Umum & Arsitektur

Academic Research Scraper adalah sistem berbasis microservices yang dirancang untuk mengumpulkan, menyimpan, dan menampilkan data akademik dosen dari **SINTA** (Science and Technology Index — Kemdiktisaintek). Sistem ini terdiri dari tiga layanan utama yang dioperasikan bersama melalui Docker Compose.

### Diagram Arsitektur Tingkat Tinggi

```
+----------------------------------------------------------------------------+
|                      Docker Network: academic_network                      |
|                                                                            |
|  +------------------------+  POST /api/v1/scrape   +--------------------+ |
|  |  KP-Penelitian-Dosen   | ----------------------> |   KP-Backend       | |
|  |  (PHP 8 Custom MVC)    |  GET /api/v1/sinta-*   |   (Python FastAPI) | |
|  |  Port: 8081            | <---------------------- |   Port: 8000       | |
|  +----------+-------------+                         +----------+---------+ |
|             | PDO/MySQL                                         | aiomysql  |
|             v                                                   v           |
|  +------------------------+             +---------------------------+       |
|  |  DB: kp-penelitian     |             |  DB: KP-Scrapping         |       |
|  |      -dosen            |             |                           |       |
|  |  - authors             | <--sync---- |  - sinta_authors          |       |
|  |  - articles            |  via API    |  - sinta_articles         |       |
|  |  - author_article      |             |  - scraping_jobs          |       |
|  |  - users               |             |  - scraping_logs          |       |
|  +------------------------+             +---------------------------+       |
|                                                      |                      |
|                            MySQL 8 Server (Port 3308)+                     |
|                                                                            |
|                         ^ HTTP scraping (BeautifulSoup)                   |
|                         |                                                  |
|           +----------------------------+                                   |
|           | SINTA (sinta.kemdiktisaintek|                                  |
|           | .go.id)  Affil ID: 528      |                                  |
|           +----------------------------+                                   |
+----------------------------------------------------------------------------+
```

---

## 2. Infrastruktur Docker

File: `docker-compose.yml` (root)

| Layanan    | Image                             | Container Name      | Port Mapping | Depends On |
| ---------- | --------------------------------- | ------------------- | ------------ | ---------- |
| `mysql`    | `aprnna/academic-mysql:latest`    | `academic_mysql`    | `3308:3306`  | —          |
| `backend`  | `aprnna/academic-backend:latest`  | `academic_scraper`  | `8000:8000`  | `mysql`    |
| `frontend` | `aprnna/academic-frontend:latest` | `academic_frontend` | `8081:80`    | `mysql`    |

### Variabel Lingkungan Penting

> **Catatan Arsitektur Database**: Kedua service menggunakan **database yang berbeda** pada server MySQL yang sama.
>
> - **KP-Backend** → database `KP-Scrapping`
> - **KP-Penelitian-Dosen** → database `kp-penelitian-dosen`
> - Sinkronisasi data dilakukan eksplisit melalui endpoint `GET /api/v1/sinta-authors`

**Backend** (`academic_scraper`):

| Variabel               | Nilai Default/Contoh | Fungsi                               |
| ---------------------- | -------------------- | ------------------------------------ |
| `DB_HOST`              | `mysql`              | Hostname DB di dalam Docker network  |
| `DB_NAME`              | `KP-Scrapping`       | Database khusus hasil scraping SINTA |
| `API_KEY`              | `${API_KEY}`         | Kunci autentikasi antar service      |
| `SCHEDULER_ENABLED`    | `true`               | Aktifkan cron job bulanan            |
| `SCRAPE_DAY_OF_MONTH`  | `1`                  | Hari dalam sebulan untuk auto-scrape |
| `SINTA_AFFILIATION_ID` | `528`                | ID afiliasi UNIKOM di SINTA          |
| `SINTA_REQUEST_DELAY`  | `2.0`                | Jeda (detik) antar request ke SINTA  |

**Frontend** (`academic_frontend`):

| Variabel                  | Fungsi                                        |
| ------------------------- | --------------------------------------------- |
| `API_URL`                 | URL internal backend: `http://backend:8000`   |
| `API_KEY`                 | Harus sama dengan backend untuk proxy request |
| `GOOGLE_CLIENT_ID/SECRET` | Kredensial Google OAuth                       |
| `BASE_URL`                | URL publik frontend (untuk OAuth redirect)    |

---

## 3. Backend — KP-Backend (Python/FastAPI)

### 3.1 Stack & Dependensi

| Komponen        | Library/Tool            | Versi     |
| --------------- | ----------------------- | --------- |
| Framework       | FastAPI                 | ≥ 0.117.1 |
| Package Manager | `uv`                    | —         |
| ASGI Server     | Uvicorn                 | ≥ 0.37.0  |
| ORM             | SQLAlchemy (async)      | ≥ 2.0.0   |
| DB Driver       | aiomysql                | ≥ 0.2.0   |
| HTTP Client     | httpx                   | ≥ 0.28.0  |
| HTML Parsing    | BeautifulSoup4          | ≥ 4.14.3  |
| Scheduler       | APScheduler             | ≥ 3.10.0  |
| Settings        | pydantic-settings       | ≥ 2.11.0  |
| Linting         | ruff + flake8           | ≥ 0.13.2  |
| Testing         | pytest + pytest-asyncio | ≥ 8.4.2   |

### 3.2 Struktur Modul

```
KP-Backend/
├── app/
│   ├── main.py               # Entry point: memanggil create_application()
│   ├── api/
│   │   ├── health_route.py   # /health endpoint
│   │   ├── routes.py         # Router aggregator
│   │   ├── schemas.py        # Pydantic request/response schemas
│   │   └── v1/
│   │       ├── router.py     # Prefix /api/v1 aggregator
│   │       ├── scrape.py     # POST /api/v1/scrape
│   │       ├── jobs.py       # GET /api/v1/jobs[/{id}[/logs]]
│   │       ├── sinta_authors.py  # GET /api/v1/sinta-authors
│   │       └── sinta_articles.py # GET /api/v1/sinta-articles
│   ├── core/
│   │   ├── config.py         # Settings via pydantic-settings
│   │   ├── database.py       # Async SQLAlchemy engine & session factory
│   │   ├── security.py       # X-API-Key header dependency
│   │   ├── server.py         # create_application(), middlewares, lifespan
│   │   ├── health.py         # Health check logic
│   │   └── schema.py         # Shared schema utilities
│   ├── models/
│   │   ├── job.py            # ScrapingJob, ScrapingLog (+ enum JobStatus, JobSource, LogLevel)
│   │   ├── sinta_author.py   # SintaAuthor ORM model
│   │   ├── sinta_article.py  # SintaArticle ORM model
│   │   └── raw_response.py   # RawResponse ORM model
│   └── services/
│       ├── job_service.py         # CRUD operasi ScrapingJob
│       ├── scraping_service.py    # Orchestrator scraping pipeline
│       ├── scheduler_service.py   # APScheduler setup & cron job
│       ├── health.py              # Health check service
│       └── scraper/
│           ├── base.py            # BaseScraper (abstract, retry, rate-limit)
│           ├── sinta_author.py    # SintaAuthorScraper
│           ├── sinta_article.py   # SintaArticleScraper
│           └── utils.py           # Utility functions
├── tests/                    # pytest test suite
├── pyproject.toml            # Dependency manifest (uv)
├── Dockerfile
└── .python-version           # Python version pin
```

### 3.3 Core Layer

#### `config.py` — Settings Management

Menggunakan `pydantic-settings` dengan `BaseSettings`. Konfigurasi dibaca dari environment variables dengan fallback default. Kelas `Settings` mengekspos:

- **DB**: `db_host`, `db_port`, `db_user`, `db_password`, `db_name`
- **SINTA**: `sinta_base_url`, `sinta_affiliation_id` (default: 528), `sinta_request_delay` (default: 2.0s), `sinta_max_retries` (default: 3)
- **Scheduler**: `scheduler_enabled`, `scrape_day_of_month`
- **Computed Properties**: `async_database_url` (untuk aiomysql), `database_url` (sync), `allowed_origins_list`, `allowed_hosts_list`, `is_production`

#### `database.py` — Async Session Management

```python
engine = create_async_engine(
    settings.async_database_url,
    echo=settings.debug,
    pool_pre_ping=True,
    pool_size=10,         # 10 koneksi dasar
    max_overflow=20,      # +20 koneksi burst
    pool_recycle=3600,    # Recycle setiap 1 jam
)
```

Menyediakan dua pola akses DB:

- `get_db()` — FastAPI dependency injection (auto commit/rollback)
- `get_db_context()` — async context manager untuk penggunaan di luar route handler

#### `server.py` — Application Factory & Lifespan

`create_application()` mengonfigurasi FastAPI dengan:

1. **Middlewares** (urutan eksekusi):
   - `CORSMiddleware` — mengizinkan cross-origin berdasarkan `allowed_origins_list`
   - `TrustedHostMiddleware` — hanya aktif di `production`
   - Custom `add_timing` — inject header `X-Process-Time` dan log tiap request
   - Custom `add_security_headers` — inject `X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`

2. **Lifespan Events** (startup):
   - Inisialisasi DB (`init_db()`)
   - **Stale Job Recovery**: Setiap job dengan status `RUNNING` dari sesi sebelumnya direset ke `FAILED` dengan pesan `"Server restarted while job was running"` — mencegah zombie job yang memblokir run baru
   - Start APScheduler

3. **Lifespan Events** (shutdown):
   - Stop scheduler
   - Close DB engine

#### `security.py` — API Key Authentication

Dependency `verify_api_key` membaca header `X-API-Key`. Jika `settings.api_key` kosong, validasi dilewati (mode development). Pola penggunaan:

```python
@router.post("/protected")
async def endpoint(api_key: str = Depends(verify_api_key)):
    ...
```

### 3.4 Scraping Engine

#### `base.py` — `BaseScraper` (Abstract)

Kelas dasar abstrak untuk semua scraper. Mengimplementasikan:

- **Async HTTP Client** via `httpx.AsyncClient` dengan timeout 30s dan `User-Agent: AcademicScraper/1.0`
- **Rate Limiting** (`_rate_limit()`): memastikan jeda minimum `request_delay` antar request menggunakan `asyncio.get_event_loop().time()`
- **Retry dengan Exponential Backoff** (`_request_with_retry()`):
  - `429 Too Many Requests`: tidur sesuai `Retry-After` header (default 5s), **tanpa** membuang satu slot retry
  - `5xx Server Errors`: retry dengan backoff `2^attempt` detik
  - `4xx Client Errors`: langsung raise `ApiError` (tidak retry)
  - `TimeoutException` / `RequestError`: retry dengan backoff
  - Total: maksimum `max_retries` (default 3) percobaan nyata

```python
# Skema retry logic:
for attempt in range(max_retries):
    if 429: sleep(retry_after); continue  # tidak increment attempt
    if 5xx: sleep(2^attempt); continue
    if 4xx: raise immediately
    if timeout/error: sleep(2^attempt); continue
    return data
raise ApiError("All retries exhausted")
```

#### `sinta_author.py` — `SintaAuthorScraper`

**Proses dua fase per run:**

**Fase 1: Affiliation List** (`scrape_affiliation_list()`)

- URL: `{sinta_base_url}/affiliations/authors/{affiliation_id}/?page={n}`
- Paginasi otomatis hingga halaman kosong
- Parse `div.col-lg` cards → ekstrak: `id_sinta`, `fullname`, `major`, `profile_url`, 4 skor SINTA (sinta_score_overall, sinta_score_3yr, affil_score, affil_score_3yr)

**Fase 2: Detail Profile** (`scrape_author_profile()`)

- URL: `{sinta_base_url}/authors/profile/{id_sinta}`
- Parse metrics table (3 kolom: label | Scopus | GScholar)
- Mapping label HTML ke kolom DB menggunakan dict constant:
  - `METRICS_MAPPING_SCOPUS`: Article → s_article_scopus, h-index → s_hindex_scopus, dst.
  - `METRICS_MAPPING_GSCHOLAR`: sama untuk Google Scholar
- Parse `ul.subject-list` untuk `subject_research` (semicolon-separated)

**Flow utama** `scrape()`:

```
scrape(sinta_ids=None) → Fase 1 + Fase 2 (Full run)
scrape(sinta_ids=[...]) → Fase 2 saja (Incremental)
```

#### `sinta_article.py` — `SintaArticleScraper`

Scraping artikel dari 4 **view SINTA** per author:

| View            | Sumber Data                                |
| --------------- | ------------------------------------------ |
| `scopus`        | Artikel terindeks Scopus                   |
| `garuda`        | Artikel di Garuda (portal Kemdiktisaintek) |
| `googlescholar` | Artikel terindeks Google Scholar           |
| `rama`          | Repositori Akademik Mahasiswa dan Alumni   |

**Concurrency**: `asyncio.Semaphore(MAX_CONCURRENT_AUTHORS=3)` — maksimum 3 author diproses paralel

**HTML Parsing per view:**

- Selector: `.ar-list-item` (setiap item artikel)
- Ekstrak: `.ar-title a` (judul + link), `.ar-year` (tahun), `.ar-cited` (sitasi), `.ar-quartile` (kuartil/akreditasi), `.ar-pub` (publisher/jurnal), `a[text*="Authors :"]` (string penulis)

**Output per artikel:**

```python
{
    "id_sinta": int,
    "source": "scopus|garuda|googlescholar|rama",
    "article_title": str, "authors": str,
    "publisher": str, "year": str,
    "cited": str, "quartile": str,
    "url": str, "scraped_at": datetime
}
```

### 3.5 Services Layer

#### `scraping_service.py` — `ScrapingService`

Orkestrator utama pipeline scraping. Menggunakan pola **session-per-operation** (bukan long-lived session) untuk menghindari konflik antara background task dan request lifecycle.

**Pipeline Eksekusi** (`run_scraping_job(job_id)`):

```
1. _start_job_and_get_params()  → set status=RUNNING, return (db_id, params, source)
   │
   ├─► [source == SINTA_AUTHORS atau BOTH]
   │     └─► SintaAuthorScraper().scrape(sinta_ids=None)
   │           └─► _save_authors() → MySQL INSERT...ON DUPLICATE KEY UPDATE
   │
   └─► [source == SINTA_ARTICLES atau BOTH]
         └─► _resolve_sinta_ids() jika tidak ada dari phase sebelumnya
               └─► SintaArticleScraper().scrape(sinta_ids)
                     └─► _save_articles_batched() → batch 200 artikel
                           └─► _flush_article_batch() → ON DUPLICATE KEY UPDATE

4. _finish_job()  → set status=FINISHED, processed_records=total
5. _fail_job()    → set status=FAILED, error_message=exc (jika ada error)
```

**Batch Insert Artikel**: 200 artikel per batch (`ARTICLE_BATCH_SIZE = 200`). Buffer diisi iteratif, di-flush saat penuh atau di akhir.

**Upsert Strategy** (MySQL-native):

```sql
INSERT INTO sinta_articles (...) VALUES (...)
ON DUPLICATE KEY UPDATE
    authors=inserted.authors,
    publisher=inserted.publisher,
    year=inserted.year,
    cited=inserted.cited,
    quartile=inserted.quartile,
    url=inserted.url,
    scraped_at=inserted.scraped_at
```

**Metrics Tracking**: `JobMetrics` dataclass mencatat `total_sinta_ids`, `total_articles`, `total_authors_saved`, dan `elapsed_seconds()` — di-log sebagai structured log saat job selesai.

#### `scheduler_service.py` — APScheduler

```python
scheduler = AsyncIOScheduler(timezone="UTC")
scheduler.add_job(
    monthly_scrape_job,
    CronTrigger(day=settings.scrape_day_of_month, hour=2, minute=0),
    id="monthly_scrape",
    coalesce=True,          # Gabungkan jika terlewat
    max_instances=1,        # Hanya 1 instance berjalan
    misfire_grace_time=3600 # Toleransi 1 jam keterlambatan
)
```

`monthly_scrape_job()`:

1. Buat `ScrapingJob` baru dengan `source=JobSource.BOTH`
2. Panggil `ScrapingService().run_scraping_job(job.job_id)`
3. Log event via `job_listener` (EVENT_JOB_ERROR | EVENT_JOB_EXECUTED)

#### `job_service.py` — `JobService`

CRUD layer untuk `ScrapingJob`:

- `create_job(source, parameters)` → buat job baru dengan `status=PENDING`, `job_id=UUID`
- `get_job_with_logs(job_id)` → return `{job, logs}` dict
- `list_jobs(status, source, limit, offset)` → query dengan filter
- `check_no_running_jobs()` → bool guard untuk mencegah double-run

### 3.6 API Layer

#### Endpoint Map

| Method | Path                         | Auth         | Deskripsi                                          |
| ------ | ---------------------------- | ------------ | -------------------------------------------------- |
| `GET`  | `/`                          | None         | Welcome message & versi                            |
| `GET`  | `/health`                    | None         | Health check (DB + scheduler status)               |
| `POST` | `/api/v1/scrape`             | ✅ X-API-Key | Trigger manual scraping job                        |
| `GET`  | `/api/v1/jobs`               | None         | List semua jobs (filter: status, source, paginate) |
| `GET`  | `/api/v1/jobs/{job_id}`      | None         | Detail job + logs                                  |
| `GET`  | `/api/v1/jobs/{job_id}/logs` | None         | Logs job (filter: level, limit)                    |
| `GET`  | `/api/v1/sinta-authors`      | None         | Query data `sinta_authors`                         |
| `GET`  | `/api/v1/sinta-articles`     | None         | Query data `sinta_articles`                        |
| `GET`  | `/docs`                      | None         | Swagger UI (OpenAPI)                               |
| `GET`  | `/redoc`                     | None         | ReDoc UI                                           |

#### `POST /api/v1/scrape` — Trigger Job

Request body (`ScrapeRequest`):

```json
{
  "source": "both | sinta_articles | sinta_authors",
  "authors": ["string"], // optional
  "sinta_ids": [12345] // optional
}
```

Response `202 Accepted` (`ScrapeResponse`):

```json
{
  "job_id": "uuid-v4",
  "status": "pending",
  "message": "Scraping job created successfully...",
  "created_at": "ISO 8601"
}
```

Guard: Jika ada job dengan status `RUNNING`, return `503 Service Unavailable`.

Background task (`run_scraping_background`) berjalan via FastAPI `BackgroundTasks` — tidak memblokir response HTTP.

### 3.7 ORM Models

#### `SintaAuthor` (tabel: `sinta_authors`)

| Kolom                  | Tipe     | Deskripsi                          |
| ---------------------- | -------- | ---------------------------------- |
| `id_sinta`             | INT PK   | SINTA Author ID (primary key)      |
| `fullname`             | TEXT     | Nama lengkap                       |
| `major`                | TEXT     | Program studi/departemen           |
| `sinta_score_overall`  | INT      | Skor SINTA keseluruhan             |
| `sinta_score_3yr`      | INT      | Skor SINTA 3 tahun terakhir        |
| `affil_score`          | INT      | Skor afiliasi                      |
| `affil_score_3yr`      | INT      | Skor afiliasi 3 tahun              |
| `s_article_scopus`     | INT      | Jumlah artikel Scopus              |
| `s_citation_scopus`    | INT      | Total sitasi Scopus                |
| `s_hindex_scopus`      | INT      | H-Index Scopus                     |
| `s_i10_index_scopus`   | INT      | i10-Index Scopus                   |
| `s_gindex_scopus`      | INT      | G-Index Scopus                     |
| `s_article_gscholar`   | INT      | Jumlah artikel GScholar            |
| `s_citation_gscholar`  | INT      | Total sitasi GScholar              |
| `s_hindex_gscholar`    | INT      | H-Index GScholar                   |
| `s_i10_index_gscholar` | INT      | i10-Index GScholar                 |
| `s_gindex_gscholar`    | INT      | G-Index GScholar                   |
| `subject_research`     | TEXT     | Bidang riset (semicolon-separated) |
| `scraped_at`           | DATETIME | Timestamp scraping terakhir        |

#### `SintaArticle` (tabel: `sinta_articles`)

| Kolom           | Tipe          | Deskripsi                                    |
| --------------- | ------------- | -------------------------------------------- |
| `id`            | INT PK (auto) | Primary key internal                         |
| `id_sinta`      | INT (indexed) | Referensi ke `sinta_authors.id_sinta`        |
| `source`        | VARCHAR(20)   | View SINTA: scopus/garuda/googlescholar/rama |
| `article_title` | TEXT          | Judul artikel                                |
| `authors`       | TEXT          | String penulis                               |
| `publisher`     | TEXT          | Nama jurnal/penerbit                         |
| `year`          | VARCHAR(10)   | Tahun publikasi                              |
| `cited`         | VARCHAR(20)   | Jumlah sitasi                                |
| `quartile`      | VARCHAR(100)  | Kuartil atau akreditasi                      |
| `url`           | TEXT          | Link ke artikel                              |
| `scraped_at`    | DATETIME      | Timestamp scraping                           |

#### `ScrapingJob` (tabel: `scraping_jobs`)

| Kolom               | Tipe               | Deskripsi                                  |
| ------------------- | ------------------ | ------------------------------------------ |
| `id`                | INT PK (auto)      | Primary key DB internal                    |
| `job_id`            | VARCHAR(36) UNIQUE | UUID sebagai public identifier             |
| `source`            | ENUM               | `sinta_articles \| sinta_authors \| both`  |
| `status`            | ENUM (indexed)     | `pending \| running \| finished \| failed` |
| `total_records`     | INT                | Target records (0 = belum tahu)            |
| `processed_records` | INT                | Records yang sudah diproses                |
| `created_at`        | DATETIME (indexed) | Waktu pembuatan job                        |
| `started_at`        | DATETIME           | Waktu mulai eksekusi                       |
| `finished_at`       | DATETIME           | Waktu selesai                              |
| `error_message`     | TEXT               | Pesan error jika gagal                     |
| `parameters`        | JSON               | Parameter job (year_start, authors, dll.)  |

**Computed Properties**:

- `progress_percentage` → `(processed_records / total_records) * 100`
- `duration_seconds` → selisih `finished_at - started_at`

#### `ScrapingLog` (tabel: `scraping_logs`)

- FK ke `scraping_jobs.id` (CASCADE DELETE)
- Fields: `level` (DEBUG/INFO/WARNING/ERROR), `message`, `extra_data` (JSON), `created_at`

---

## 4. Frontend — KP-Penelitian-Dosen (PHP MVC)

### 4.1 Stack & Framework

| Komponen        | Detail                                             |
| --------------- | -------------------------------------------------- |
| Bahasa          | PHP 8+                                             |
| Framework       | Custom MVC (tanpa Composer, tanpa Laravel/Symfony) |
| Web Server      | Apache (dengan `mod_rewrite` via `.htaccess`)      |
| Database Driver | PDO (MySQL)                                        |
| Auth            | Session-based + Google OAuth 2.0                   |
| Styling         | Custom CSS + Tailwind (existing design)            |
| HTTP Client     | cURL (native PHP)                                  |

### 4.2 Custom MVC Core

```
app/core/
├── App.php        # Bootstrap: load config, inisialisasi Router, dispatch request
├── Router.php     # Definisi & dispatch route (GET/POST/PUT/DELETE + dynamic params)
├── Controller.php # Base controller: model(), render(), redirect()
├── Database.php   # PDO wrapper (query, bind, execute, resultSet, single)
├── Auth.php       # Session-based auth: check(), user(), login*, logout, register
└── Env.php        # Pembaca file .env untuk definisi konstanta
```

#### `Router.php`

Mendukung exact-match dan dynamic routes dengan parameter `{name}`:

```php
// Route definition
$router->get('user/detail/{id}', 'UserController@detail');

// Konversi ke regex: #^user/detail/([a-zA-Z0-9_-]+)$#
// Match → call UserController::detail($id)
```

Dispatch mechanism: `executeCallback()` membaca
Dispatch mechanism: `executeCallback()` membaca format `"ControllerClass@method"`, melakukan `require_once` controller file secara dinamis, lalu memanggil method dengan parameter yang diekstrak dari URL.

#### `Database.php`

Wrapper PDO dengan konfigurasi persistent connection:

```php
$options = [
    PDO::ATTR_PERSISTENT => true,           // Persistent connection pooling
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_OBJ  // Return stdClass objects
];
```

API: `query($sql)` → `bind($param, $value)` → `resultSet()` / `single()` / `execute()`

Auto-type detection pada `bind()`: int, bool, null, string dipetakan ke `PDO::PARAM_*` yang sesuai.

#### `Auth.php`

Mengelola state autentikasi via PHP `$_SESSION`. Mendukung:

- `loginWithPassword($username, $password)` — verifikasi `password_hash`
- `loginWithGoogle($googleUser)` — delegate ke `User::findByProvider()`
- `registerWithGoogle($googleUser)` — delegate ke `User::createOrUpdateFromProvider()`
- `check()` — cek apakah session aktif
- `user()` — return data user dari session
- `logout()` — destroy session

### 4.3 Routing Map

```
GET  /                              → HomeController@index
GET  /dashboard                     → DashboardController@index
GET  /dashboard/filterData          → DashboardController@filterData (AJAX API)
GET  /penelitian                    → PenelitianController@index
GET  /penelitian/detail/{id}        → PenelitianController@detail

GET  /user                          → UserController@index
GET  /user/detail/{id}              → UserController@detail
GET  /user/create                   → UserController@create
POST /user/store                    → UserController@store
GET  /user/edit/{id}                → UserController@edit
POST /user/update/{id}              → UserController@update
POST /user/delete/{id}              → UserController@delete

GET  /auth/login                    → AuthController@login
POST /auth/login                    → AuthController@doLogin
POST /auth/logout                   → AuthController@logout
GET  /auth/register                 → AuthController@register
POST /auth/register                 → AuthController@doRegister
GET  /auth/google/login             → AuthController@googleLogin
GET  /auth/google/register          → AuthController@googleRegister
GET  /auth/google/callback          → AuthController@googleCallback

GET  /scraping                      → ScrapingController@index
POST /scraping/triggerScraping      → ScrapingController@triggerScraping
GET  /scraping/getJobs              → ScrapingController@getJobs (AJAX proxy)
GET  /scraping/getJobDetails/{id}   → ScrapingController@getJobDetails (AJAX proxy)
GET  /scraping/getJobProgress/{id}  → ScrapingController@getJobProgress (AJAX proxy)
GET  /scraping/getLogs/{id}         → ScrapingController@getLogs (AJAX proxy)
POST /scraping/webhook              → ScrapingController@webhook
```

### 4.4 Controllers

#### `AuthController`

Flow autentikasi:

1. **Login Biasa**: POST `/auth/login` → `Auth::loginWithPassword()` → redirect `/dashboard`
2. **Register**: POST `/auth/register` → validasi (min 6 char, password match, field tidak kosong) → `Auth::register()` → redirect `/auth/login`
3. **Google Login/Register**:
   - Generate `$authUrl` dari `GoogleAuthService::getAuthUrl()`
   - Simpan flow (`login`/`register`) di session sebagai `$_SESSION['google_flow']`
   - Redirect ke Google
   - Callback di `/auth/google/callback`:
     - Verifikasi state CSRF via `GoogleAuthService::verifyState($state)`
     - Exchange code → access token
     - Fetch user info dari Google API
     - Route ke `loginWithGoogle()` atau `registerWithGoogle()` sesuai flow

#### `DashboardController`

Mengambil data untuk 7 widget visualisasi pada halaman dashboard:

1. **Stats Cards**: total dosen, total publikasi (filtered by year), total terindeksasi (filtered by year)
2. **Ranked List**: Top 10 author berdasarkan jumlah publikasi terindeks (`getTopAuthorsByPublicationCount`), dengan badge emas/perak/perunggu untuk rank 1-3
3. **Productivity Trend Chart**: Top 5 author berdasarkan total publikasi di rentang 5 tahun, data per tahun
4. **Treemap Faculty Distribution**: Distribusi total publikasi per fakultas
5. **Publication Type Chart**: Trend tipe artikel (jurnal/prosiding/dll.) per tahun, 5 tahun terakhir
6. **Top Journals Bar Chart**: Top 5 jurnal berdasarkan jumlah artikel
7. **Top Impact Authors Chart**: Top 5 author berdasarkan `sinta_score_overall` per fakultas

**AJAX Filter Endpoint** (`GET /dashboard/filterData?type=...&faculty=...&year=...`):

Tipe filter yang didukung: `ranked_list`, `productivity`, `treemap`, `pub_type`, `top_journals`, `top_impact`, `stats`. Tiap tipe mengeksekusi query yang berbeda dan return JSON.

#### `ScrapingController`

Bertindak sebagai **proxy transparan** antara browser/UI dan FastAPI backend.

**Pattern komunikasi**:

```php
private function apiRequest($endpoint, $method = 'GET', $data = null) {
    $ch = curl_init($this->apiBaseUrl . $endpoint);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json',
        'X-API-Key: ' . $this->apiKey
    ]);
    // eksekusi cURL, return {success, data, http_code}
}
```

- `getJobs()` → proxy ke `GET /api/v1/jobs?status=&limit=&offset=`, transform response untuk frontend
- `getJobDetails($uuid)` → proxy ke `GET /api/v1/jobs/{uuid}`, kalkulasi duration (`DateTime::diff`), count logs per level
- `getJobProgress($uuid)` → polling endpoint, kalkulasi `elapsed_seconds` dan `estimated_remaining`
- `getLogs($uuid)` → proxy ke `GET /api/v1/jobs/{uuid}/logs`, support filter `since_id` (client-side)
- `triggerScraping()` → proxy ke `POST /api/v1/scrape`

### 4.5 Models

#### `Author.php`

Query ke tabel `authors` (legacy schema dari `init.sql`). Metode utama:

| Method                                                              | Fungsi                                                          |
| ------------------------------------------------------------------- | --------------------------------------------------------------- |
| `getAuthors($limit, $offset, $faculty, $search)`                    | Paginasi dengan filter                                          |
| `countAuthors($faculty, $search)`                                   | Hitung total untuk pagination                                   |
| `getTopAuthorsByPublicationCount($limit, $faculty, $year)`          | JOIN authors + articles, filter `indexed_date_time IS NOT NULL` |
| `getTopAuthorsByRangeCount($limit, $startYear, $endYear, $faculty)` | Top 5 untuk trend chart, filter by BETWEEN                      |
| `getFacultyPublicationStats($year)`                                 | Distribusi publikasi per fakultas untuk treemap                 |
| `getTopAuthorsByFaculty($faculty, $year, $limit)`                   | Top 5 berdasarkan `sinta_score_overall`                         |
| `getUniqueFaculties()`                                              | List fakultas unik untuk filter dropdown                        |

#### `Article.php`

Query ke tabel `articles` dan `author_article` (JOIN). Metode utama:

| Method                                                                | Fungsi                                                          |
| --------------------------------------------------------------------- | --------------------------------------------------------------- |
| `getArticlesByAuthorId($authorId)`                                    | Semua artikel satu author via `author_article`                  |
| `getProductivityTrend($authorId)`                                     | Jumlah artikel per tahun (`GROUP BY SUBSTRING(published,1,4)`)  |
| `getTopJournals($limit, $faculty, $year)`                             | Top N jurnal berdasarkan jumlah artikel                         |
| `countTotalArticles($year, $faculty)`                                 | Hitung total dengan optional filter                             |
| `countIndexedArticles($year, $faculty)`                               | Filter `indexed_date_time IS NOT NULL`                          |
| `getArticleTypeStats($startYear, $endYear, $faculty)`                 | Tipe artikel (journal/proceeding) per tahun                     |
| `getAuthorRoleRatios($authorId, $year)`                               | Rasio main author vs co-author (string parsing field `authors`) |
| `getArticlesByJournalAndAuthor($authorId, $journal, $limit, $offset)` | Paginasi per jurnal per author                                  |

#### `User.php`

Query ke tabel `users`. Mendukung dual-auth model:

- **Local users**: `createLocalUser($data)` → simpan dengan `password_hash`
- **OAuth users**: `createOrUpdateFromProvider($provider, $providerId, $name, $email)` — smart upsert: cari by provider+id → update; jika tidak ada, cari by email → link provider; jika tidak ada sama sekali → buat baru
- `findByEmail($email)`, `findByProvider($provider, $providerId)` — lookup helpers

### 4.6 Views & Komponen UI

```
app/views/
├── auth/            # login.php, register.php
├── components/      # ranked_list_item.php, dll. (reusable partials)
├── dashboard/       # index.php (7 chart widgets + stats cards + ranked list)
├── home/            # Landing page publik
├── layouts/         # main.php (authenticated layout), auth.php (unauthenticated layout)
├── partials/        # navbar.php, footer.php, sidebar.php
├── penelitian/      # index.php (daftar artikel paginasi), detail.php (profil author + chart)
├── scraping/        # index.php (job dashboard dengan real-time polling)
└── user/            # index.php, create.php, edit.php, detail.php
```

---

## 5. Skema Database

### Dua Database Terpisah

Kedua service berjalan pada server MySQL yang sama tetapi menggunakan **database yang berbeda**
sehingga tidak ada coupling langsung pada level DB.

#### Database A: `kp-penelitian-dosen` (dimiliki KP-Penelitian-Dosen)

| Tabel            | Keterangan                                                                                    |
| ---------------- | --------------------------------------------------------------------------------------------- |
| `authors`        | Data dosen: `id_sinta` PK, fullname, nidn, degree, major, faculty, sinta scores, bibliometrik |
| `articles`       | Publikasi: `id_article` PK, doi, title, journal_title, published, type, indexed_date_time     |
| `author_article` | Junction M:N antara `authors` dan `articles` (id_sinta, id_article)                           |
| `users`          | Akun sistem: id, name, email, password_hash, provider, provider_id                            |

KP-Penelitian-Dosen **membaca dan menulis** ke database ini.
Data `authors` di-populate awal dari `init.sql`, lalu di-update berkala
melalui mekanisme sync API (`ScrapingController::syncAuthors`).

#### Database B: `KP-Scrapping` (dimiliki KP-Backend)

| Tabel            | Keterangan                                                                                   |
| ---------------- | -------------------------------------------------------------------------------------------- |
| `sinta_authors`  | Hasil scraping profil dosen: `id_sinta` PK, scores, bibliometrik Scopus & GScholar           |
| `sinta_articles` | Hasil scraping artikel: id auto PK, id_sinta, source (scopus/garuda/gscholar/rama), metadata |
| `scraping_jobs`  | Tracking job: `job_id` UUID UNIQUE, source enum, status enum, timestamps, parameters JSON    |
| `scraping_logs`  | Log per job: level (DEBUG/INFO/WARNING/ERROR), message, FK → scraping_jobs.id                |
| `raw_responses`  | Raw HTTP response untuk debugging (opsional)                                                 |

KP-Backend **hanya menulis** ke database ini.
KP-Penelitian-Dosen **tidak pernah** terhubung langsung ke database ini —
akses dilakukan eksklusif melalui HTTP API.

### Alur Sinkronisasi Data (DB A ← API ← DB B)

```
[DB: KP-Scrapping]              API Call                [DB: kp-penelitian-dosen]
sinta_authors                                           authors
  id_sinta                                                id_sinta
  fullname           GET /api/v1/sinta-authors            fullname
  major             ─────────────────────────►           major
  sinta_score_*                                           sinta_score_*
  s_*_scopus        ScrapingController::syncAuthors()     s_*_scopus
  s_*_gscholar        - compare field by field            s_*_gscholar
  subject_research    - updateFromSinta() jika beda       subject_research
  scraped_at          - insertFromSinta() jika baru
```

### ERD Logis

```
[DB: kp-penelitian-dosen]
authors (id_sinta PK)
    | 1:N via author_article
articles (id_article PK)

users (id PK, email UNIQUE)

[DB: KP-Scrapping]
sinta_authors (id_sinta PK) ──► sinta_articles.id_sinta  [logical, non-FK]
sinta_articles (id INT PK auto_increment)

scraping_jobs (id PK, job_id UUID UNIQUE)
    | 1:N CASCADE DELETE
scraping_logs (id PK, job_id FK)
    | 1:N CASCADE DELETE
raw_responses (id PK, job_id FK)
```

---

## 6. Alur Sistem (Workflows)

### Alur A: Auto-Scraping Bulanan

```
[APScheduler — hari ke-N bulan ini, 02:00 UTC]
       |
       v
monthly_scrape_job()
       | create ScrapingJob (source=BOTH, status=PENDING)
       |
       v
ScrapingService.run_scraping_job(job_id)
       | set status=RUNNING
       |
       +--► [Phase 1] SintaAuthorScraper
       |         |  GET /affiliations/authors/528/?page=1,2,...
       |         |  Parse HTML div.col-lg cards
       |         |  → fullname, id_sinta, major, 4 skor SINTA
       |         |
       |         |  GET /authors/profile/{id_sinta}  (per author, sequential)
       |         |  Parse metrics table 3-kolom
       |         |  → Scopus stats (6 field) + GScholar stats (6 field) + subject_research
       |         |
       |         └──► INSERT INTO sinta_authors ON DUPLICATE KEY UPDATE (all fields)
       |
       └──► [Phase 2] SintaArticleScraper
                 |  Ambil sinta_ids dari hasil Phase 1
                 |  Semaphore(3) — maks 3 author concurrent
                 |
                 |  Per author → 4 views: scopus, garuda, googlescholar, rama
                 |    GET /authors/profile/{id}/?view={view}
                 |    Parse .ar-list-item HTML elements
                 |    → article_title, authors, publisher, year, cited, quartile, url
                 |
                 └──► INSERT INTO sinta_articles (batch 200) ON DUPLICATE KEY UPDATE

       | set status=FINISHED, processed_records=total_articles
       | log JobMetrics: elapsed_sec, total_sinta_ids, total_articles, total_authors_saved
```

### Alur B: Manual Scraping via UI

```
[User Admin — Browser]
       | klik tombol "Trigger Scraping"
       |
       v
POST /scraping/triggerScraping  (PHP Frontend)
       | cURL POST http://backend:8000/api/v1/scrape
       |   header: X-API-Key: {API_KEY}
       |   body:   {"source": "both"}
       |
       v
FastAPI POST /api/v1/scrape
       | verify_api_key()
       | check_no_running_jobs() — return 503 jika ada job running
       | create ScrapingJob (status=PENDING)
       | BackgroundTasks.add_task(run_scraping_background, job_id)
       | return 202 {"job_id": "uuid"}
       |
       v                              v
PHP return JSON {job_id}     [Background Task berjalan]
       |                       (identik dengan Alur A Phase 1 & 2)
       v
Browser polling setiap N detik:
  GET /scraping/getJobProgress/{uuid}
       | PHP cURL GET /api/v1/jobs/{uuid}
       | return {status, processed, elapsed_seconds, estimated_remaining}
       |
  GET /scraping/getLogs/{uuid}?since_id={last_id}
       | PHP cURL GET /api/v1/jobs/{uuid}/logs
       | filter client-side by since_id → incremental log streaming
```

### Alur C: User Melihat Data (Dashboard & Penelitian)

```
[User Browser — GET /dashboard]
       |
       v
DashboardController@index
       | Auth::check() — redirect ke /auth/login jika tidak terautentikasi
       |
       | Author::countAuthors()
       | Article::countTotalArticles($defaultYear)
       | Article::countIndexedArticles($defaultYear)
       | Author::getTopAuthorsByPublicationCount(10, ...)
       | getChartData():
       |   Author::getTopAuthorsByRangeCount(5, startYear, endYear, null)
       |   Article::getProductivityTrend($authorId) per top author
       |   Author::getFacultyPublicationStats($defaultYear)
       |   Article::getTopJournals(5, $defaultFaculty, $defaultYear)
       |   Article::getArticleTypeStats($startYear, $defaultYear, null)
       |   Author::getTopAuthorsByFaculty($defaultFaculty, $defaultYear, 5)
       |
       v
render('dashboard/index', $data, 'main')

[User AJAX — GET /dashboard/filterData?type=productivity&faculty=FT&year=2024]
       | DashboardController@filterData
       | Eksekusi query sesuai type, return JSON
       v
JavaScript update chart/list tanpa full page reload
```

### Alur D: Sync Data dari Backend ke Database Lokal

```
[User Admin — klik "Sync Authors Now"]
       |
       v
POST /scraping/syncAuthors  (PHP Frontend)
       |
       v
ScrapingController::syncAuthors()
       |
       | Loop halaman (page=1, size=200, sampai respons kosong):
       |   cURL GET http://backend:8000/api/v1/sinta-authors?page=N&size=200
       |   Terima: JSON array of SintaAuthorResponse
       |
       | allAuthors = semua record dari semua halaman
       |
       | Untuk setiap author di allAuthors:
       |   localAuthor = Author::getAuthorById(id_sinta)
       |   if localAuthor exists:
       |     if sintaFieldsChanged(local, remote):
       |       Author::updateFromSinta(id_sinta, data)  → stats[updated]++
       |     else:
       |       stats[skipped]++
       |   else:
       |     Author::insertFromSinta(data)              → stats[inserted]++
       |
       v
Return JSON:
  { success, message, stats: { total, updated, inserted, skipped, errors } }
       |
       v
UI tampilkan alert dengan badge stats (Total / Updated / Inserted / Skipped)
```

**Catatan**:

- Field yang di-sync: semua kolom bibliometrik SINTA (sinta*score*_, affil*score*_, s*\*\_scopus, s*\*\_gscholar, subject_research, fullname, major)
- Field yang **tidak** di-overwrite: `nidn`, `degree`, `faculty` (harus diisi dari sumber lain)
- Perbandingan dilakukan dengan cast ke string agar NULL == NULL dan int == "int" tidak dianggap beda

---

## 7. Keamanan & Konfigurasi

### Backend

| Mekanisme           | Detail                                                                                                     |
| ------------------- | ---------------------------------------------------------------------------------------------------------- |
| API Key Auth        | Header `X-API-Key` — wajib untuk `POST /api/v1/scrape`; dilewati jika `settings.api_key` kosong (mode dev) |
| CORS                | Via `ALLOWED_ORIGINS` env var (comma-separated); default `*` di docker-compose production                  |
| TrustedHost         | Aktif hanya di environment `production` berdasarkan `ALLOWED_HOSTS`                                        |
| Security Headers    | `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection: 1; mode=block`              |
| Request Timing      | Header `X-Process-Time` pada setiap response                                                               |
| Stale Job Recovery  | Job dengan status `RUNNING` saat startup → direset ke `FAILED` (anti zombie-job)                           |
| SINTA Rate Limiting | 2.0s delay per request + exponential backoff (1s, 2s, 4s) + 429 Retry-After                                |
| DB Connection Pool  | `pool_size=10`, `max_overflow=20`, `pool_recycle=3600`, `pool_pre_ping=True`                               |

### Frontend

| Mekanisme                | Detail                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------ |
| Session Auth             | PHP `$_SESSION` + `AuthMiddleware::handle()` pada controller terproteksi             |
| Password Hashing         | PHP native `password_hash()` / `password_verify()`                                   |
| Google OAuth CSRF        | State parameter diverifikasi via `GoogleAuthService::verifyState($state)`            |
| SQL Injection Prevention | Semua query via PDO `prepare()` + `bindValue()` (tidak ada raw string interpolation) |
| API Key Proxy            | `API_KEY` konstanta dari env var, dikirim via cURL header ke backend                 |
| No Hardcoded Secrets     | Semua credential dibaca dari env vars via `Env.php` dan konstanta PHP                |

---

- `KP-Backend/app/` — Python/FastAPI (scraping engine, REST API, scheduler)
- `KP-Penelitian-Dosen/app/` — PHP Custom MVC (dashboard, auth, UI)
- `docker-compose.yml` — root orchestrator
- `database/init.sql` — skema database legacy
