#!/usr/bin/env bash

set -euo pipefail

SERVER_DOMAIN="${1:-}"
TARGET_DOMAIN="${2:-}"

if [[ -z "$SERVER_DOMAIN" || -z "$TARGET_DOMAIN" ]]; then
    echo "Usage:"
    echo "  $0 <server-domain> <target-domain>"
    echo
    echo "Example:"
    echo "  $0 webhook.example.com api.example.com"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed."
    exit 1
fi

WORKDIR="/opt/webhook-proxy"

echo "[1/7] Creating directories..."

mkdir -p "$WORKDIR/nginx/conf.d"
mkdir -p "$WORKDIR/certbot/conf"
mkdir -p "$WORKDIR/certbot/www"

echo "[2/7] Creating docker-compose.yml..."

cat > "$WORKDIR/docker-compose.yml" <<'EOF'
services:
  nginx:
    image: nginx:1.28-alpine
    container_name: webhook-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot

  certbot:
    image: certbot/certbot:latest
    container_name: webhook-certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
EOF

echo "[3/7] Creating temporary nginx config for Let's Encrypt..."

cat > "$WORKDIR/nginx/conf.d/webhook.conf" <<EOF
server {
    listen 80;
    server_name $SERVER_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 404;
    }
}
EOF

cd "$WORKDIR"

echo "[4/7] Starting nginx..."
docker compose up -d nginx

echo "[5/7] Obtaining Let's Encrypt certificate..."

docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --agree-tos \
    --register-unsafely-without-email \
    --non-interactive \
    -d "$SERVER_DOMAIN"

echo "[6/7] Installing production nginx config..."

cat > "$WORKDIR/nginx/conf.d/webhook.conf" <<EOF
server {
    listen 80;
    server_name $SERVER_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;

    server_name $SERVER_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$SERVER_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$SERVER_DOMAIN/privkey.pem;

    access_log off;
    error_log /dev/null crit;

    location = /webhook {

        if (\$request_method != POST) {
            return 405;
        }

        client_max_body_size 5m;

        proxy_pass https://$TARGET_DOMAIN/api/webhook;

        proxy_set_header Host $TARGET_DOMAIN;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_pass_request_headers on;
        proxy_pass_request_body on;

        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    location / {
        return 404;
    }
}
EOF

docker compose restart nginx

echo "[7/7] Installing automatic certificate renewal..."

cat > /etc/cron.d/webhook-certbot-renew <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

17 3 * * * root cd $WORKDIR && docker compose run --rm certbot renew --quiet && docker compose restart nginx >/dev/null 2>&1
EOF

chmod 644 /etc/cron.d/webhook-certbot-renew

systemctl reload cron 2>/dev/null || true
systemctl reload crond 2>/dev/null || true

echo
echo "========================================"
echo "Installation completed successfully"
echo "========================================"
echo
echo "Webhook URL:"
echo "  https://$SERVER_DOMAIN/webhook"
echo
echo "Proxy target:"
echo "  https://$TARGET_DOMAIN/api/webhook"
echo
echo "Configuration:"
echo "  ✓ HTTPS (Let's Encrypt)"
echo "  ✓ Automatic certificate renewal"
echo "  ✓ POST requests only"
echo "  ✓ Maximum body size: 5 MB"
echo "  ✓ Headers and request body forwarded"
echo "  ✓ Access logs disabled"
echo "  ✓ All other URLs return 404"
echo
echo "Test certificate renewal:"
echo "  cd $WORKDIR && docker compose run --rm certbot renew --dry-run"
echo
echo "========================================"