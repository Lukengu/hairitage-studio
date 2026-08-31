#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-hairitage-studio.co.za}"
EMAIL="${2:-info@hairitage-studio.co.za}"
COMPOSE="docker compose -f docker-compose.prod.yml"

echo "==> Requesting Let's Encrypt certificate for ${DOMAIN}..."
$COMPOSE run --rm certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  -d "$DOMAIN" \
  -d "www.${DOMAIN}"

echo "==> Enabling HTTPS nginx config..."
cp nginx/nginx.ssl.conf nginx/nginx.bootstrap.conf
$COMPOSE build nginx
$COMPOSE up -d nginx certbot

echo "==> SSL setup complete. Site should be available at https://${DOMAIN}"
