#!/bin/sh
set -e

# Environment variables are injected by Vercel at runtime, so caches must be
# built now (never during `docker build`). Routes/views are env-independent.
php artisan config:cache
php artisan route:cache
php artisan view:cache

exec frankenphp run --config /etc/caddy/Caddyfile
