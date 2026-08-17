# 🌐 Shubham International Hospital — Complete Guide

The one document for this project. It covers the architecture, every file in the repo,
local development, the database (migrations + seeding), the frontend, Vercel hosting,
environment variables, the full CI/CD setup (with the actual workflow files), Vercel Blob
image storage, the git workflow, and troubleshooting.

**Remote**: `https://github.com/uttam-kharel/aaa.git` (branches: `development`, `production`)

## 0. Quick start — do these in order (every step is explained below)

1. [ ] Install the tools: PHP 8.3+, Composer, Node 20+, Git (Docker only needed for the optional image test)
2. [ ] Clone the repo and set up locally (§3) — you should see the coming-soon page at `http://localhost:8000`
3. [ ] Create the Vercel project, Postgres and Blob stores (§6.1–6.2)
4. [ ] Add the Vercel environment variables (§6.3)
5. [ ] Add the GitHub secrets (§6.4)
6. [ ] Create the `production` branch (§10) — needed for the deploy trigger
7. [ ] Push to GitHub and watch the CI run pass (§7)
8. [ ] Open a PR `development` → `production` and merge it — this deploys (§11)
9. [ ] Run `php artisan blob:test` to confirm image storage works (§9)

---

## 1. What this project is

- Laravel 13 (PHP 8.3+, runs on PHP 8.4 in production) + Tailwind CSS v4 + Vite.
- Currently a coming-soon landing page (`resources/views/welcome.blade.php`).
- Hosted on **Vercel** using the official container runtime (FrankenPHP = Caddy + PHP).
- Database: **Vercel Postgres** (Neon). Sessions, cache and queue also live in Postgres.
- Images/files: **Vercel Blob**, used through Laravel's built-in `s3` disk (S3-compatible).
- CI/CD: **GitHub Actions** — merge to `production` runs checks, migrates, and deploys.

```
GitHub ── push/merge to `production` ──▶ GitHub Actions
                                             │
                                    1. Quality checks (Pint, PHPUnit, stylelint, build)
                                    2. php artisan migrate --force  → Vercel Postgres
                                    3. vercel deploy --prod          → your account
                                             │
                                             ▼
                                   Vercel container (Dockerfile.vercel)
                                   FrankenPHP (Caddy + PHP 8.4)
                                   Laravel serves from /app/public
                                   Sessions/cache/queue → Postgres
                                   Images/files → Vercel Blob
```

---

## 2. Repository structure

```
.
├── app/
│   ├── Console/Commands/BlobTest.php   # php artisan blob:test — verify Blob store
│   └── Models/                          # Eloquent models (add as you build features)
├── bootstrap/                           # Laravel bootstrap + app.php
├── config/                              # Laravel config (database, filesystems, ...)
├── database/
│   ├── migrations/                      # schema: users, cache, jobs, sessions
│   ├── factories/                       # model factories for fake data
│   └── seeders/                         # DatabaseSeeder etc.
├── public/                              # web root (index.php, favicons, build/)
├── resources/
│   ├── css/app.css                      # Tailwind v4 entry point + @theme
│   ├── js/app.js                        # frontend entry
│   └── views/                           # Blade templates (welcome.blade.php)
├── routes/web.php                       # routes (GET / → welcome)
├── tests/                               # PHPUnit tests
├── .github/workflows/
│   ├── ci.yml                           # quality checks on every push/PR
│   └── deploy.yml                       # production + preview deploys
├── .dockerignore / .vercelignore        # exclude non-prod files from builds/uploads
├── Caddyfile                            # FrankenPHP server config
├── Dockerfile.vercel                    # the production image (built by Vercel)
├── vercel.json                          # container service + rewrite
├── vercel-entrypoint.sh                 # boot script (cache warm + start server)
├── GUIDE.md                             # this file
├── composer.json / package.json         # PHP + Node dependencies
└── .env.example                         # env template (local + Vercel placeholders)
```

---

## 3. Local development (fresh machine)

Requirements: **PHP 8.3+**, **Composer**, **Node 20+**.

```bash
git clone https://github.com/uttam-kharel/aaa.git
cd aaa
git checkout development

composer install
cp .env.example .env        # create local env (sqlite by default)
php artisan key:generate    # sets APP_KEY in .env
npm install

touch database/database.sqlite   # create the empty sqlite file
php artisan migrate              # create tables (users, cache, jobs, sessions)

npm run dev                 # terminal 1: Vite dev server
php artisan serve           # terminal 2: http://localhost:8000
```

**Success looks like**: `http://localhost:8000` shows the Shubham International Hospital
coming-soon page, and `php artisan test` passes. Or run the full stack with one command:
`composer run dev`.

Common commands:

| Task             | Command                    |
| ---------------- | -------------------------- |
| Serve locally    | `php artisan serve`        |
| Full dev stack   | `composer run dev`         |
| Run tests        | `php artisan test`         |
| Code style check | `./vendor/bin/pint --test` |
| Code style fix   | `./vendor/bin/pint`        |
| CSS lint         | `npm run lint:css`         |
| Build assets     | `npm run build`            |
| Tinker (REPL)    | `php artisan tinker`       |

---

## 4. Database

### Configuration

- **Local**: SQLite (`DB_CONNECTION=sqlite`, file `database/database.sqlite`).
- **Production**: Vercel Postgres via `DB_CONNECTION=pgsql` + `DB_URL`
  (the `POSTGRES_URL_NON_POOLING` value) + `DB_SSLMODE=require`.

### Existing tables

| Migration                                     | Creates                                            |
| --------------------------------------------- | -------------------------------------------------- |
| `0001_01_01_000000_create_users_table.php`    | `users`, `password_reset_tokens`                   |
| `0001_01_01_000001_create_cache_table.php`    | `cache`, `cache_locks`                             |
| `0001_01_01_000002_create_jobs_table.php`     | `jobs`, `job_batches`, `failed_jobs`               |
| `0001_01_01_000003_create_sessions_table.php` | `sessions` (required by `SESSION_DRIVER=database`) |

### Create a migration

```bash
php artisan make:migration create_doctors_table
```

Edit the generated file:

```php
Schema::create('doctors', function (Blueprint $table) {
    $table->id();
    $table->string('name');
    $table->string('specialty');
    $table->string('photo_path')->nullable();   // path stored in Vercel Blob
    $table->timestamps();
});
```

Apply / rollback:

```bash
php artisan migrate            # apply
php artisan migrate:rollback   # roll back the last batch
```

### Create a model + factory + migration in one go

```bash
php artisan make:model Doctor -m -f
```

### Seed data

```bash
php artisan make:seeder DoctorSeeder
```

```php
use App\Models\Doctor;

Doctor::create(['name' => 'Dr. Sharma', 'specialty' => 'Cardiology']);
```

```bash
php artisan db:seed --class=DoctorSeeder
```

Register seeders in `database/seeders/DatabaseSeeder.php` so `php artisan db:seed` runs all.
Fake data: `php artisan tinker --execute="App\Models\Doctor::factory()->count(10)->create()"`

### Production migrations

Run automatically by CI before every production deploy. To run against a copy of your
production database manually:

```bash
DB_CONNECTION=pgsql DB_URL="<POSTGRES_URL_NON_POOLING>" DB_SSLMODE=require php artisan migrate --force
```

---

## 5. Frontend (Tailwind CSS v4)

- Entry point: `resources/css/app.css` — imports Tailwind, scans Blade views, and defines
  the `@theme` block (currently the Instrument Sans font stack).
- Build tool: Vite (`vite.config.js` + `@tailwindcss/vite`).
- Layout: `resources/views/welcome.blade.php` (coming-soon page, loads assets via `@vite`).

To add theme colors (Tailwind v4 CSS-first), extend the `@theme` block in `app.css`:

```css
@theme {
    --color-primary-700: #046095;
    --color-surface: #fefdfd;
}
```

…and use utilities like `bg-primary-700`, `bg-surface` in Blade templates.

---

## 6. Vercel setup (one-time, with YOUR account)

### 6.1 Create the project

```bash
npm i -g vercel
vercel login          # logs in as your account
vercel link           # inside this repo; choose "Other" framework preset
```

Writes `.vercel/project.json` (gitignored) with `orgId` and `projectId`.

**Success looks like**: the file `.vercel/project.json` exists locally with `orgId` and
`projectId` values (you'll need those for the GitHub secrets in §6.4).

> The container runtime is a Vercel product feature — confirm your plan includes container
> images (the dashboard warns during project setup if not).

### 6.2 Create storage

1. **Vercel dashboard → Storage → Create Database → Postgres** (Neon). Keep the
   `POSTGRES_URL_NON_POOLING` connection string.
2. **Vercel dashboard → Storage → Create Database → Blob** for images. Open the store →
   **Settings → S3 API** and note the access key ID, secret, endpoint and store ID.

### 6.3 Vercel environment variables

Path: `Vercel dashboard → your project → Settings → Environment Variables` → add each with
**Environment: Production** (add Preview too if previews should share the same DB).

| Variable                      | Value                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `APP_ENV`                     | `production`                                                                         |
| `APP_DEBUG`                   | `false`                                                                              |
| `APP_URL`                     | your domain, e.g. `https://your-app.vercel.app`                                      |
| `APP_KEY`                     | `php artisan key:generate --show` (run locally once, paste full `base64:...`)        |
| `DB_CONNECTION`               | `pgsql`                                                                              |
| `DB_URL`                      | the `POSTGRES_URL_NON_POOLING` value                                                 |
| `DB_SSLMODE`                  | `require`                                                                            |
| `SESSION_DRIVER`              | `database`                                                                           |
| `CACHE_STORE`                 | `database`                                                                           |
| `QUEUE_CONNECTION`            | `database`                                                                           |
| `FILESYSTEM_DISK`             | `s3`                                                                                 |
| `AWS_ACCESS_KEY_ID`           | from Blob store → Settings → S3 API                                                  |
| `AWS_SECRET_ACCESS_KEY`       | from Blob store → Settings → S3 API                                                  |
| `AWS_BUCKET`                  | your Blob store ID                                                                   |
| `AWS_ENDPOINT`                | `https://<store-id>.blob.vercel-storage.com` (from the S3 API section)               |
| `AWS_URL`                     | `https://<store-id>.public.blob.vercel-storage.com` — makes `Storage::url()` correct |
| `AWS_DEFAULT_REGION`          | `us-east-1`                                                                          |
| `AWS_USE_PATH_STYLE_ENDPOINT` | `true` — required for Vercel Blob (per-store URL)                                    |
| `LOG_LEVEL`                   | `warning`                                                                            |

**Never** set `SESSION_DRIVER=file` / `CACHE_STORE=file` in production, and never commit a
real token or `.env` file.

### 6.4 GitHub secrets

Path: `GitHub repo → Settings → Secrets and variables → Actions → New repository secret`

| Secret              | Value                                                                    |
| ------------------- | ------------------------------------------------------------------------ |
| `VERCEL_TOKEN`      | Vercel → your avatar → **Settings → Tokens → Create**                    |
| `VERCEL_ORG_ID`     | `orgId` from `.vercel/project.json`                                      |
| `VERCEL_PROJECT_ID` | `projectId` from `.vercel/project.json`                                  |
| `DB_URL`            | the same `POSTGRES_URL_NON_POOLING` value (used by CI to run migrations) |

These make the workflow deploy **from your own account** — official Vercel CLI, no third-party action.

### 6.5 Protect `production`

GitHub → **Settings → Branches → Add rule** for `production`: require pull requests + the
`Quality checks` status check. Then deploys can only happen via reviewed PRs merged into
`production`.

---

## 7. CI/CD — the actual workflows

### `ci.yml` — Quality checks

Runs on every push to `main` / `development` / `production` and on every pull request, and
can be called from other workflows (`workflow_call`):

```yaml
name: CI

on:
    push:
        branches: [main, development, production]
    pull_request:
    workflow_call:

jobs:
    quality:
        name: Quality checks
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4

            - name: Setup PHP
              uses: shivammathur/setup-php@v2
              with:
                  php-version: '8.4'
                  extensions: mbstring, intl, bcmath, sqlite3
                  coverage: none
                  tools: composer:v2

            - name: Cache Composer dependencies
              uses: actions/cache@v4
              with:
                  path: vendor
                  key: composer-${{ hashFiles('composer.lock') }}
                  restore-keys: composer-

            - name: Install PHP dependencies
              run: composer install --no-interaction --prefer-dist --no-progress

            - name: Check code style (Pint)
              run: ./vendor/bin/pint --test

            - name: Run tests
              run: |
                  cp .env.example .env
                  php artisan key:generate
                  php artisan test

            - name: Setup Node
              uses: actions/setup-node@v4
              with:
                  node-version: 22
                  cache: npm

            - name: Install Node dependencies
              run: npm ci --no-audit --no-fund

            - name: Lint CSS
              run: npm run lint:css

            - name: Build frontend assets
              run: npm run build
```

### `deploy.yml` — Deploys

| Trigger                             | What happens                                                  |
| ----------------------------------- | ------------------------------------------------------------- |
| Push/merge to `production`          | quality checks → **migrations** → **`vercel deploy --prod`**  |
| Pull request targeting `production` | quality checks → **preview deploy** → URL commented on the PR |

Production deploys are serialized (`concurrency` group) so two merges can't race.

```yaml
name: Deploy to Vercel

on:
    push:
        branches: [production]
    pull_request:
        branches: [production]

concurrency:
    group: vercel-${{ github.ref }}
    cancel-in-progress: false

jobs:
    quality:
        name: Quality checks
        uses: ./.github/workflows/ci.yml

    preview:
        name: Preview deploy (PR)
        if: github.event_name == 'pull_request'
        needs: quality
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4

            - name: Deploy preview to Vercel
              id: preview
              continue-on-error: true
              env:
                  VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
                  VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
                  VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
              run: |
                  OUTPUT="$(npx --yes vercel@latest deploy --yes --token "$VERCEL_TOKEN" 2>&1)"
                  URL="$(printf '%s' "$OUTPUT" | grep -oE 'https://[a-zA-Z0-9.-]+\.(vercel|app)' | tail -1)"
                  echo "url=$URL" >> "$GITHUB_OUTPUT"

            - name: Comment preview URL on the PR
              if: steps.preview.outputs.url != ''
              uses: actions/github-script@v7
              with:
                  script: |
                      github.rest.issues.createComment({
                          issue_number: context.issue.number,
                          owner: context.repo.owner,
                          repo: context.repo.repo,
                          body: `🚀 Preview deployment: ${process.env.PREVIEW_URL}`,
                      });
              env:
                  PREVIEW_URL: ${{ steps.preview.outputs.url }}

    production:
        name: Production deploy
        if: github.event_name == 'push' && github.ref == 'refs/heads/production'
        needs: quality
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4

            - name: Setup PHP
              uses: shivammathur/setup-php@v2
              with:
                  php-version: '8.4'
                  extensions: mbstring, intl, bcmath, pgsql, pdo_pgsql
                  coverage: none
                  tools: composer:v2

            - name: Install PHP dependencies
              run: composer install --no-dev --no-interaction --prefer-dist --no-progress

            - name: Run database migrations
              env:
                  APP_ENV: production
                  DB_CONNECTION: pgsql
                  DB_URL: ${{ secrets.DB_URL }}
                  DB_SSLMODE: require
              run: php artisan migrate --force

            - name: Deploy to Vercel (production)
              env:
                  VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
                  VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
                  VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
              run: npx --yes vercel@latest deploy --prod --yes --token "$VERCEL_TOKEN"
```

---

## 8. How Vercel runs Laravel (the config files)

### `vercel.json`

Declares a container service and routes every request to it:

```json
{
    "$schema": "https://openapi.vercel.sh/vercel.json",
    "services": {
        "api": {
            "root": ".",
            "entrypoint": "Dockerfile.vercel",
            "runtime": "container"
        }
    },
    "rewrites": [
        {
            "source": "/(.*)",
            "destination": {
                "service": "api"
            }
        }
    ]
}
```

### `Dockerfile.vercel`

Three stages: (1) build Vite assets with Node 22, (2) install Composer deps, (3) runtime
image — FrankenPHP with PHP 8.4 + Postgres/image extensions. Built entirely on Vercel's
infrastructure; you never build locally.

```dockerfile
# syntax=docker/dockerfile:1

# Stage 1: Build frontend assets with Vite
FROM node:22-alpine AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# Stage 2: Install PHP dependencies
FROM composer:2 AS dependencies
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --prefer-dist --optimize-autoloader

# Stage 3: Runtime — FrankenPHP (Caddy + PHP)
FROM dunglas/frankenphp:1-php8.4-alpine

WORKDIR /app

RUN install-php-extensions pdo_pgsql pgsql intl bcmath gd exif zip

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY . .
COPY --from=assets /app/public/build ./public/build
COPY --from=dependencies /app/vendor ./vendor

COPY Caddyfile /etc/caddy/Caddyfile

RUN composer dump-autoload --no-dev --optimize --classmap-authoritative \
    && php artisan package:discover --ansi \
    && mkdir -p storage/framework/sessions storage/framework/views storage/framework/cache storage/logs \
    && chmod -R 775 storage bootstrap/cache \
    && chmod +x vercel-entrypoint.sh

ENV PORT=80
EXPOSE 80

CMD ["/app/vercel-entrypoint.sh"]
```

### `Caddyfile`

```caddy
:{$PORT:80} {
    root * /app/public
    encode zstd gzip
    php_server
}
```

### `vercel-entrypoint.sh`

Env vars are injected by Vercel at runtime, so caches are built at boot, not during the image
build:

```sh
#!/bin/sh
set -e

php artisan config:cache
php artisan route:cache
php artisan view:cache

exec frankenphp run --config /etc/caddy/Caddyfile
```

### `.vercelignore` / `.dockerignore`

Keep uploads and the Docker context lean (identical content): `.git`, `.github`, `.husky`,
`.freebuff`, `.idea`, `.vscode`, `node_modules`, `vendor`, `storage`, `tests`, `public/build`,
`.env`, `.env.*`, `*.log`, OS junk.

---

## 9. Vercel Blob (images & files)

Vercel Blob is S3-compatible, so Laravel's standard `Storage` API is used with the `s3` disk
(`config/filesystems.php`). No custom service or extra SDK needed.

### Verify your store

```bash
php artisan blob:test
```

Uploads, reads back, prints the public URL, and deletes a test file. Warns if `AWS_URL` is
missing. Run locally with the `AWS_*` vars in `.env`, or anywhere with them exported.

### Upload an image (public — best for a hospital site)

```php
use Illuminate\Support\Facades\Storage;

$path = Storage::disk('s3')->putFile('doctors', $request->file('photo'));
// or: Storage::disk('s3')->put('doctors/dr-sharma.jpg', $contents);

$url = Storage::disk('s3')->url($path);
// https://<store-id>.public.blob.vercel-storage.com/doctors/xxxx.jpg
```

Store `$path` in your DB (e.g. `doctors.photo_path`), display later with
`Storage::disk('s3')->url($doctor->photo_path)`.

### Delete / exists / list

```php
Storage::disk('s3')->delete($doctor->photo_path);
Storage::disk('s3')->exists($path);
Storage::disk('s3')->files('doctors/');   // list files under a prefix
```

### Requirements & limits

- `AWS_URL` must be `https://<store-id>.public.blob.vercel-storage.com` or `Storage::url()`
  builds a default AWS-style link that 404s.
- `AWS_USE_PATH_STYLE_ENDPOINT=true` is required (Vercel Blob serves each store from its own
  subdomain; virtual-host style can't address it).
- **Private blobs and presigned URLs are not supported** through the S3 disk (Vercel Blob
  signs those with its own tokens). Public website images don't need them; if you ever need
  private files, use the official `@vercel/blob` Node SDK for that flow.

---

## 10. Git workflow

- **`development`** — active development; push here freely.
- **`production`** — what's live. Only via PRs merged from `development` (deploy happens on
  merge).

### Create the `production` branch (first time only)

The deploy workflow only triggers on pushes to `production`, so the branch must exist.
Easiest one-liner (creates it on GitHub at the current `development` tip):

```bash
git push origin development:production
git branch production origin/production
git checkout production
git checkout development   # back to working
```

Or via the GitHub UI: **repo → Branches → New branch → name `production`, source
`development`**.

- Commit style: conventional commits (`feat:`, `fix:`, `chore:`, ...) enforced by
  commitlint + husky. Prettier/Pint auto-run on staged files.

```bash
git checkout development
git add <files>
git commit -m "feat: add doctor profiles"
git push origin development

# Ship it:
# 1. PR development → production
# 2. CI runs + preview deploy on the PR
# 3. Merge → migrations + production deploy
```

---

## 11. The deployment flow, step by step

1. Commit changes on `development`, push.
2. Open a PR from `development` → `production`.
3. CI runs quality checks; a **preview deploy** is created and its URL is commented on the PR.
4. Merge the PR (review + checks required if branch protection is on).
5. GitHub Actions runs: checks → `php artisan migrate --force` → `vercel deploy --prod`.
6. Live site updates on your domain. Rollback = revert the merge and re-merge.

---

## 12. Troubleshooting

| Symptom                             | Cause / fix                                                                                             |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| 502 Bad Gateway                     | Caddy not on `$PORT`. Keep `:{$PORT:80}` in `Caddyfile`.                                                |
| 404 on routes                       | Docroot/rewrite: keep `root * /app/public` + `php_server`.                                              |
| PHP changes not applied             | Caches rebuild at boot, but stale compiled views can linger — restart the deployment in Vercel.         |
| `blob:test` fails / wrong URLs      | Check the `AWS_*` env vars — especially `AWS_URL` (public base) and `AWS_USE_PATH_STYLE_ENDPOINT=true`. |
| Migrations fail in deploy           | `DB_URL` GitHub secret must be the **non-pooling** Postgres URL.                                        |
| Preview deploys fail but PR is fine | Missing `VERCEL_*` secrets (previews use the same project).                                             |
| "Unable to resolve driver [s3]"     | `league/flysystem-aws-s3-v3` missing — `composer require league/flysystem-aws-s3-v3:^3.0`.              |
| Deploy triggers but Vercel rejects  | Container runtime not enabled on your Vercel plan.                                                      |
| Composer audit reports advisories   | Run `composer audit`; `composer update <package>` to fix (all current advisories cleared).              |

---

## 13. Cheat sheets

### Commands

| Task                            | Command                                                                             |
| ------------------------------- | ----------------------------------------------------------------------------------- |
| Local server                    | `php artisan serve`                                                                 |
| Full dev stack                  | `composer run dev`                                                                  |
| Tests                           | `php artisan test`                                                                  |
| New migration                   | `php artisan make:migration create_xxx_table`                                       |
| Migrate / rollback              | `php artisan migrate` / `php artisan migrate:rollback`                              |
| New seeder                      | `php artisan make:seeder XxxSeeder`                                                 |
| Seed                            | `php artisan db:seed`                                                               |
| New model + migration + factory | `php artisan make:model Xxx -m -f`                                                  |
| REPL                            | `php artisan tinker`                                                                |
| Style check / fix               | `./vendor/bin/pint --test` / `./vendor/bin/pint`                                    |
| Blob test                       | `php artisan blob:test`                                                             |
| Generate APP_KEY                | `php artisan key:generate --show`                                                   |
| Production migrate (manual)     | `DB_CONNECTION=pgsql DB_URL="<url>" DB_SSLMODE=require php artisan migrate --force` |

### Environment variables

| Where                       | Variables                                                                                                                                                                                                                                                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Vercel env (Production)** | `APP_ENV`, `APP_DEBUG`, `APP_URL`, `APP_KEY`, `DB_CONNECTION`, `DB_URL`, `DB_SSLMODE`, `SESSION_DRIVER`, `CACHE_STORE`, `QUEUE_CONNECTION`, `FILESYSTEM_DISK`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_BUCKET`, `AWS_ENDPOINT`, `AWS_URL`, `AWS_DEFAULT_REGION`, `AWS_USE_PATH_STYLE_ENDPOINT`, `LOG_LEVEL` |
| **GitHub secrets**          | `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `DB_URL`                                                                                                                                                                                                                                                         |
| **Local `.env` only**       | everything from `.env.example` — local sqlite + (optionally) the `AWS_*` vars for `blob:test`                                                                                                                                                                                                                          |
