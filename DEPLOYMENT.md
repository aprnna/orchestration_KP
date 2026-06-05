# Deployment Guide

Production deployment for SINTA Research Visualizer with separate frontend and backend servers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Frontend Server                            │
│                                                                 │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────┐   │
│  │   Nginx     │────▶│  Frontend   │────▶│     MySQL       │   │
│  │  (Port 80)  │     │  (PHP/Apache)│     │(kp_penelitian)  │   │
│  └─────────────┘     └─────────────┘     └─────────────────┘   │
│                              │                                   │
│                              │ HTTP API                         │
│                              ▼                                   │
│                      ┌─────────────────┐                        │
│                      │   Backend API   │                        │
│                      │(Remote Server)  │                        │
│                      └─────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Backend Server                             │
│                                                                 │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────┐   │
│  │   Nginx     │────▶│   Backend   │────▶│     MySQL       │   │
│  │  (Port 80)  │     │  (FastAPI)  │     │ (kp_scrapping)  │   │
│  └─────────────┘     └─────────────┘     └─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Requirements

### Backend Server
- Docker & Docker Compose
- 4GB RAM minimum
- Python 3.10+ (for local dev)
- Port 80/443 open

### Frontend Server
- Docker & Docker Compose
- 2GB RAM minimum
- PHP 7.4+ (for local dev)
- Port 80/443 open

---

## Backend Deployment

### 1. Prepare Environment

```bash
cd KP-Backend
cp .env.example .env
```

### 2. Edit `.env`

```bash
# Database
DB_ROOT_PASSWORD=your_secure_root_password
DB_USER=backend_user
DB_PASSWORD=your_secure_db_password

# API Security
API_KEY=your_shared_api_key_here

# SINTA Scraper
SINTA_AFFILIATION_ID=528

# CORS (comma-separated frontend URLs)
ALLOWED_ORIGINS=https://your-frontend-domain.com

# Scheduler
SCHEDULER_ENABLED=true
SCRAPE_DAY_OF_MONTH=1
```

### 3. Build and Start

```bash
docker-compose up -d --build
```

### 4. Verify

```bash
# Check containers
docker-compose ps

# Test API
curl http://localhost:8000/api/v1/ping/

# Check logs
docker-compose logs -f backend
```

### 5. Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_ROOT_PASSWORD` | MySQL root password | Required |
| `DB_USER` | Database user | `backend_user` |
| `DB_PASSWORD` | Database password | Required |
| `API_KEY` | Shared secret for API auth | Required |
| `SINTA_AFFILIATION_ID` | SINTA institution ID | `528` |
| `ALLOWED_ORIGINS` | CORS allowed origins | `*` |
| `SCHEDULER_ENABLED` | Enable monthly scraping | `true` |
| `SCRAPE_DAY_OF_MONTH` | Day to run scraping | `1` |

---

## Frontend Deployment

### 1. Prepare Environment

```bash
cd KP-Penelitian-Dosen
cp .env.example .env
```

### 2. Edit `.env`

```bash
# Database
DB_ROOT_PASSWORD=your_secure_root_password
DB_USER=frontend_user
DB_PASSWORD=your_secure_db_password

# App
APP_NAME="SINTA Research Visualizer"
BASE_URL=https://your-frontend-domain.com

# Backend API
API_URL=https://your-backend-domain.com
API_KEY=your_shared_api_key_here

# Google OAuth
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
GOOGLE_REDIRECT_URI=https://your-frontend-domain.com/auth/google/callback

# Port
WEB_PORT=80
```

### 3. Build and Start

```bash
docker-compose up -d --build
```

### 4. Verify

```bash
# Check containers
docker-compose ps

# Test frontend
curl http://localhost/

# Check logs
docker-compose logs -f frontend
```

### 5. Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_ROOT_PASSWORD` | MySQL root password | Required |
| `DB_USER` | Database user | `frontend_user` |
| `DB_PASSWORD` | Database password | Required |
| `BASE_URL` | Public URL of frontend | Required |
| `API_URL` | Backend API URL | Required |
| `API_KEY` | Shared secret (match backend) | Required |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID | Required |
| `GOOGLE_CLIENT_SECRET` | Google OAuth secret | Required |
| `GOOGLE_REDIRECT_URI` | OAuth callback URL | Required |
| `WEB_PORT` | Public port | `80` |

---

## Local Development Setup

### Both Services on Same Machine

If running both frontend and backend locally with Docker:

```bash
# Backend
cd KP-Backend
# In .env, use default ports

# Frontend - use host.docker.internal to reach backend
cd KP-Penelitian-Dosen
# In .env:
API_URL=http://host.docker.internal:8000
```

### Without Docker

**Backend:**
```bash
cd KP-Backend
uv sync
uv run fastapi dev  # Runs on port 8000
```

**Frontend:**
```bash
cd KP-Penelitian-Dosen
# Configure .env with:
# DB_HOST=localhost
# API_URL=http://localhost:8000
# Use Laragon/XAMPP for PHP/MySQL
```

---

## SSL Configuration

### Option 1: Cloudflare (Recommended)

1. Point domain DNS to Cloudflare
2. Enable "Full SSL" mode in Cloudflare
3. No certificate needed on server

### Option 2: Nginx + Let's Encrypt

```bash
# Install certbot
apt install certbot python3-certbot-nginx

# Get certificate
certbot --nginx -d your-domain.com

# Auto-renew
certbot renew --dry-run
```

### Option 3: Custom SSL Certificates

Add to `docker-compose.yml`:
```yaml
nginx:
  volumes:
    - /path/to/cert.pem:/etc/nginx/ssl/cert.pem:ro
    - /path/to/key.pem:/etc/nginx/ssl/key.pem:ro
```

---

## Troubleshooting

### Frontend can't connect to Backend

1. Verify `API_URL` in frontend `.env`
2. Check `ALLOWED_ORIGINS` in backend `.env`
3. Verify `API_KEY` matches in both `.env` files
4. Test connectivity: `curl http://backend-url/api/v1/ping/`

### Database Connection Failed

```bash
# Check MySQL logs
docker-compose logs mysql

# Verify credentials
docker-compose exec mysql mysql -u user -p

# Check health
docker-compose ps
```

### Navigation URLs Missing Slash

Symptom: URLs like `http://localhostauth/login` instead of `http://localhost/auth/login`

Fix: `config.php` automatically adds trailing slash to `BASE_URL`:
```php
define('BASE_URL', rtrim(getenv('BASE_URL') ?: 'http://localhost:8080/', '/') . '/');
```

### MySQL 8 Strict Mode DATETIME Error

Symptom: `Incorrect DATETIME value: ''`

Fix: Use `IS NOT NULL` instead of `!= ''` for DATETIME columns:
```php
// Wrong
'WHERE indexed_date_time IS NOT NULL AND indexed_date_time != ""'

// Correct
'WHERE indexed_date_time IS NOT NULL'
```

### Mobile Navbar Toggle Not Working

Fix: Ensure CSS `!important` is on mobile media queries, not desktop defaults:
```css
/* Wrong */
.navbar-nav { display: flex !important; }

/* Correct */
@media (max-width: 991.98px) {
  .navbar-nav { display: none !important; }
  .navbar-nav.show { display: flex !important; }
}
```

---

## Maintenance

### View Logs

```bash
docker-compose logs -f [service_name]
```

### Restart Services

```bash
docker-compose restart [service_name]
```

### Update Application

```bash
git pull
docker-compose up -d --build
```

### Backup Database

```bash
docker-compose exec mysql mysqldump -u root -p db_name > backup_$(date +%Y%m%d).sql
```

### Restore Database

```bash
docker-compose exec -T mysql mysql -u root -p db_name < backup.sql
```

### Reset Everything

```bash
# Stop and remove volumes (WARNING: destroys data)
docker-compose down -v

# Rebuild from scratch
docker-compose up -d --build
```

---

## File Structure

```
KP-Backend/
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── nginx/
│   └── backend.conf
└── mysql-init/
    ├── 01-schema.sql
    └── 02-user.sql

KP-Penelitian-Dosen/
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── nginx/
│   └── frontend.conf
└── mysql-init/
    ├── 01-schema.sql
    └── 02-user.sql
```

---

## Domain Setup

### Architecture with Domain

```
                    ┌─────────────────┐
                    │   Cloudflare    │
                    │  (SSL + DNS)    │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                                   │
           ▼                                   ▼
    api.domain.com                     app.domain.com
   (Backend Server)                    (Frontend Server)
           │                                   │
           ▼                                   ▼
    ┌─────────────┐                    ┌─────────────┐
    │   Nginx     │                    │   Nginx     │
    │  Port 443   │                    │  Port 443   │
    └─────────────┘                    └─────────────┘
           │                                   │
           ▼                                   ▼
    ┌─────────────┐                    ┌─────────────┐
    │   Backend   │                    │  Frontend   │
    │  (FastAPI)  │                    │  (PHP)      │
    └─────────────┘                    └─────────────┘
```

### 1. DNS Configuration

**Cloudflare / Domain Registrar:**

| Type | Name | Content |
|------|------|---------|
| A | api | BACKEND_SERVER_IP |
| A | app (or @) | FRONTEND_SERVER_IP |

### 2. Backend Nginx SSL Config

Create `KP-Backend/nginx/ssl-backend.conf`:

```nginx
# HTTP redirect to HTTPS
server {
    listen 80;
    server_name api.domain.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS
server {
    listen 443 ssl http2;
    server_name api.domain.com;

    # SSL certificates
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://backend:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

### 3. Frontend Nginx SSL Config

Create `KP-Penelitian-Dosen/nginx/ssl-frontend.conf`:

```nginx
# HTTP redirect to HTTPS
server {
    listen 80;
    server_name app.domain.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS
server {
    listen 443 ssl http2;
    server_name app.domain.com;

    # SSL certificates
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

    # Security headers
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;

    location / {
        proxy_pass http://frontend:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 4. SSL Certificate Options

**Option A: Cloudflare (Recommended - Free)**

1. Point domain nameservers to Cloudflare
2. Enable "Full SSL" mode in Cloudflare dashboard
3. No certificate needed on server
4. Cloudflare handles SSL termination

**Option B: Let's Encrypt (Free)**

```bash
# Install certbot on server
apt update
apt install certbot

# Get certificate (stop nginx first)
docker-compose down nginx
certbot certonly --standalone -d api.domain.com
certbot certonly --standalone -d app.domain.com

# Copy certificates
cp /etc/letsencrypt/live/api.domain.com/fullchain.pem KP-Backend/nginx/cert.pem
cp /etc/letsencrypt/live/api.domain.com/privkey.pem KP-Backend/nginx/key.pem

# Auto-renewal
crontab -e
# Add: 0 0 1 * * certbot renew --quiet && docker-compose restart nginx
```

**Option C: Self-Signed (Development Only)**

```bash
# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem \
  -subj "/CN=api.domain.com"

# Copy to nginx folders
cp cert.pem key.pem KP-Backend/nginx/
cp cert.pem key.pem KP-Penelitian-Dosen/nginx/
```

### 5. Update Environment Variables

**Backend `.env`:**
```bash
ALLOWED_ORIGINS=https://app.domain.com
API_KEY=your-secure-api-key-here
```

**Frontend `.env`:**
```bash
BASE_URL=https://app.domain.com
API_URL=https://api.domain.com
API_KEY=your-secure-api-key-here
GOOGLE_REDIRECT_URI=https://app.domain.com/auth/google/callback
```

### 6. Update Docker Compose for SSL

```yaml
# Add to docker-compose.yml nginx service
nginx:
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./nginx/ssl-backend.conf:/etc/nginx/conf.d/default.conf:ro
    - ./nginx/cert.pem:/etc/nginx/ssl/cert.pem:ro
    - ./nginx/key.pem:/etc/nginx/ssl/key.pem:ro
```

### 7. Update Google OAuth

In Google Cloud Console:
```
Authorized JavaScript origins: https://app.domain.com
Authorized redirect URIs: https://app.domain.com/auth/google/callback
```

---

## VPS Deployment

### Prerequisites

```bash
# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER

# Install Docker Compose
apt install docker-compose-plugin

# Install Git
apt install git

# Install certbot (for Let's Encrypt)
apt install certbot
```

### Backend Server Setup

```bash
# 1. Clone repository
git clone https://github.com/username/academic-system.git
cd academic-system/KP-Backend

# 2. Create SSL directory
mkdir -p nginx/ssl

# 3. Get SSL certificate (Let's Encrypt)
docker-compose down nginx 2>/dev/null || true
certbot certonly --standalone -d api.domain.com

# 4. Copy certificates
cp /etc/letsencrypt/live/api.domain.com/fullchain.pem nginx/ssl/cert.pem
cp /etc/letsencrypt/live/api.domain.com/privkey.pem nginx/ssl/key.pem

# 5. Configure environment
cp .env.example .env
nano .env
# Set: DB_ROOT_PASSWORD, DB_PASSWORD, API_KEY, ALLOWED_ORIGINS

# 6. Update nginx config for SSL
# Rename or update nginx/backend.conf to use SSL config

# 7. Deploy
docker-compose up -d --build

# 8. Verify
curl https://api.domain.com/api/v1/ping/
```

### Frontend Server Setup

```bash
# 1. Clone repository (if separate server)
git clone https://github.com/username/academic-system.git
cd academic-system/KP-Penelitian-Dosen

# 2. Create SSL directory
mkdir -p nginx/ssl

# 3. Get SSL certificate
docker-compose down nginx 2>/dev/null || true
certbot certonly --standalone -d app.domain.com

# 4. Copy certificates
cp /etc/letsencrypt/live/app.domain.com/fullchain.pem nginx/ssl/cert.pem
cp /etc/letsencrypt/live/app.domain.com/privkey.pem nginx/ssl/key.pem

# 5. Configure environment
cp .env.example .env
nano .env
# Set:
# - DB_ROOT_PASSWORD, DB_PASSWORD
# - BASE_URL=https://app.domain.com
# - API_URL=https://api.domain.com
# - API_KEY (match backend)
# - GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
# - GOOGLE_REDIRECT_URI=https://app.domain.com/auth/google/callback

# 6. Deploy
docker-compose up -d --build

# 7. Verify
curl https://app.domain.com/
```

### SSL Certificate Renewal

```bash
# Add to crontab
crontab -e

# Add this line (runs monthly at 3am)
0 3 1 * * certbot renew --quiet && docker-compose restart nginx
```

### Firewall Setup (UFW)

```bash
# Allow SSH
ufw allow 22/tcp

# Allow HTTP and HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Enable firewall
ufw enable
```

### Systemd Service (Auto-start)

```bash
# Create systemd service
cat > /etc/systemd/system/academic-backend.service << EOF
[Unit]
Description=Academic Backend
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/root/academic-system/KP-Backend
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable service
systemctl enable academic-backend
systemctl start academic-backend
```

### Update Deployment

```bash
# Pull latest code
git pull origin main

# Rebuild and restart
docker-compose down
docker-compose up -d --build

# Check logs
docker-compose logs -f
```

### Backup Database

```bash
# Create backup
docker-compose exec mysql mysqldump -u root -p kp_scrapping > backup_$(date +%Y%m%d).sql

# Restore backup
docker-compose exec -T mysql mysql -u root -p kp_scrapping < backup_20260101.sql
```

### Monitor Resources

```bash
# Check container resources
docker stats

# Check disk usage
df -h

# Check memory
free -h

# Check running containers
docker-compose ps
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Start services | `docker-compose up -d --build` |
| Stop services | `docker-compose down` |
| View logs | `docker-compose logs -f [service]` |
| Check status | `docker-compose ps` |
| Shell into container | `docker-compose exec [service] sh` |
| MySQL shell | `docker-compose exec mysql mysql -u root -p` |
| Rebuild image | `docker-compose build --no-cache [service]` |
| Remove volumes | `docker-compose down -v` |