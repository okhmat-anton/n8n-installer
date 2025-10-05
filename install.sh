#!/usr/bin/env bash
set -euo pipefail

############################################
# USER INPUT
############################################
read -p "Domain for n8n (example, n8n.example.com) [default: your-site.com]: " DOMAIN
DOMAIN=${DOMAIN:-your-site.com}

read -p "Email for Let's Encrypt (example, admin@example.com) [default: admin@${DOMAIN}]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@${DOMAIN}}

read -p "Time Zone (example, Europe/Kyiv or America/Los_Angeles) [default: America/New_York]: " TZ
TZ=${TZ:-America/New_York}

############################################
# CONFIG
############################################
BASE_DIR="/opt/n8n"
POSTGRES_USER="n8n"
POSTGRES_DB="n8n"

############################################
# HELPERS
############################################
random() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"; echo; }
need()  { command -v "$1" >/dev/null 2>&1 || return 1; }

############################################
# SECRETS
############################################
N8N_ENCRYPTION_KEY="$(random 64)"
POSTGRES_PASSWORD="$(random 32)"

############################################
# FIX CURL-MINIMAL (AL2023)
############################################
if command -v dnf >/dev/null 2>&1; then
  if dnf list installed curl-minimal >/dev/null 2>&1; then
    echo "[*] Fixing curl-minimal conflict..."
    sudo dnf -y swap curl-minimal curl --allowerasing || {
      sudo dnf -y distro-sync
      sudo dnf -y swap curl-minimal curl --allowerasing
    }
  fi
fi

############################################
# BASE PACKAGES
############################################
echo "[*] Installing base packages..."
if need dnf; then
  sudo dnf -y update
  sudo dnf -y install curl jq tar xz ca-certificates
elif need yum; then
  sudo yum -y update
  sudo yum -y install curl jq tar xz ca-certificates
else
  echo "Unsupported distro. Need dnf or yum."
  exit 1
fi

############################################
# FFMPEG (static on host)
############################################
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[*] Installing static FFmpeg..."
  cd /tmp
  curl -LO https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
  tar -xJf ffmpeg-release-amd64-static.tar.xz
  sudo mv ffmpeg-*-amd64-static/ffmpeg /usr/local/bin/
  sudo mv ffmpeg-*-amd64-static/ffprobe /usr/local/bin/
  sudo chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe
  rm -rf /tmp/ffmpeg-*-amd64-static*
  echo "[*] FFmpeg: $(ffmpeg -version | head -n1)"
fi

############################################
# DOCKER + COMPOSE
############################################
echo "[*] Installing Docker..."
source /etc/os-release || true

if command -v dnf >/dev/null 2>&1; then
  sudo dnf -y install docker
  sudo systemctl enable --now docker
elif command -v yum >/dev/null 2>&1; then
  if [[ "${ID:-}" = "amzn" && "${VERSION_ID:-}" =~ ^2 ]]; then
    sudo amazon-linux-extras install -y docker
    sudo systemctl enable --now docker
  else
    sudo yum -y install docker
    sudo systemctl enable --now docker
  fi
fi

sudo usermod -aG docker "$USER" || true

# Compose v2 (binary, если не найден)
if ! docker compose version >/dev/null 2>&1; then
  echo "[*] Installing Docker Compose v2..."
  sudo mkdir -p /usr/lib/docker/cli-plugins
  sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o /usr/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/lib/docker/cli-plugins/docker-compose
fi

############################################
# FOLDERS
############################################
echo "[*] Preparing directories..."
sudo mkdir -p "${BASE_DIR}"/{data,postgres,caddy}
sudo chown -R "$USER":"$USER" "$BASE_DIR"

############################################
# .ENV
############################################
cat > "${BASE_DIR}/.env" <<EOF
GENERIC_TIMEZONE=${TZ}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_PORT=5678
N8N_EDITOR_BASE_URL=https://${DOMAIN}
N8N_PUBLIC_URL=https://${DOMAIN}
N8N_SECURE_COOKIE=true
EXECUTIONS_MODE=regular

POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}

DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
DB_POSTGRESDB_USER=${POSTGRES_USER}
DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
EOF

############################################
# Caddyfile (SSL reverse proxy)
############################################
cat > "${BASE_DIR}/caddy/Caddyfile" <<EOF
{
  email ${ADMIN_EMAIL}
}
${DOMAIN} {
  encode zstd gzip
  reverse_proxy n8n:5678
}
EOF

############################################
# docker-compose.yaml (mount host ffmpeg)
############################################
cat > "${BASE_DIR}/docker-compose.yaml" <<'YAML'
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - ./postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    env_file: .env
    environment:
      GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}
    volumes:
      - ./data:/home/node/.n8n
      - /usr/local/bin/ffmpeg:/usr/local/bin/ffmpeg:ro
      - /usr/local/bin/ffprobe:/usr/local/bin/ffprobe:ro

  caddy:
    image: caddy:latest
    restart: unless-stopped
    depends_on:
      - n8n
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    ports:
      - "80:80"
      - "443:443"

volumes:
  caddy_data:
  caddy_config:
YAML

############################################
# START STACK (with permission fallback)
############################################
echo "[*] Starting Docker stack..."
cd "$BASE_DIR"
if docker info >/dev/null 2>&1; then
  docker compose version
  docker compose pull
  docker compose up -d
else
  echo "[*] Using sudo for docker (permissions fix)..."
  sudo docker compose version
  sudo docker compose pull
  sudo docker compose up -d
fi

############################################
# INFO
############################################
echo
echo "========================================="
echo " ✅ n8n started with PostgreSQL and SSL (Caddy)"
echo " 🌐 Domain:        https://${DOMAIN}"
echo " 🕒 Timme Zone:     ${TZ}"
echo " 📁 Directory:   ${BASE_DIR}"
echo " 🧰 Postgres user: ${POSTGRES_USER}"
echo " 🔑 Postgres pass: ${POSTGRES_PASSWORD}"
echo " 🔐 N8N ENC KEY:   ${N8N_ENCRYPTION_KEY}"
echo "========================================="
echo "Check ports 80/443 в Lightsail firewall."
echo "FFmpeg mounted in container n8n: /usr/local/bin/ffmpeg, /usr/local/bin/ffprobe"
echo "Containers: restart: unless-stopped"
