#!/bin/sh
# ^ Run with the POSIX sh shell (small, always available on Alpine).
#   The shebang must be the very first line of the file.

set -e
# ^ "Exit on error": if ANY command below fails, the script stops and
#   the container fails to start. Better than booting with a broken
#   config and serving 500s.

# Environment variables are injected by Vercel at runtime, so caches must be
# built now (never during `docker build`). Routes/views are env-independent.
php artisan config:cache
# ^ Compile config/ into a single cached file (bootstrap/cache/config.php).
#   This READ the Vercel-injected env vars (DB_URL, AWS_*, APP_KEY...),
#   which is why it must run at boot time, after Vercel has set them,
#   and never during the image build when those vars don't exist yet.

php artisan route:cache
# ^ Compile routes/web.php into a cached route table, so every request
#   skips the file-parsing step. Routes don't depend on env vars, so
#   this is safe to cache here.

php artisan view:cache
# ^ Pre-compile all Blade templates to plain PHP for faster rendering.

exec frankenphp run --config /etc/caddy/Caddyfile
# ^ Start FrankenPHP (Caddy + PHP) using our Caddyfile.
#   `exec` REPLACES the shell process with frankenphp: the shell exits
#   and frankenphp becomes PID 1. This matters because Vercel sends
#   stop/restart signals to PID 1 — with `exec`, the server receives
#   them directly and shuts down cleanly instead of being orphaned.
