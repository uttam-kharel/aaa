# Shubham International Hospital — Complete Guide

Everything you need: how the project runs, how to develop locally, how the database works,
how to create migrations and seed data, how CI/CD works, and exactly what to put where in
Vercel and GitHub to make it deploy.

---

## 1. Architecture overview

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

- **Runtime**: Vercel's official container support. `Dockerfile.vercel` builds the image on
  Vercel's infrastructure (no local build needed).
- **Web server**: FrankenPHP (Caddy + PHP) — `Caddyfile` listens on `$PORT` and serves
  `/app/public`.
- **Database**: Vercel Postgres (Neon). Sessions, cache and queue also live in Postgres
  because the container file system is ephemeral.
- **File storage**: Vercel Blob through Laravel's built-in `s3` disk — Vercel Blob is
  S3-compatible, so the standard `Storage::disk('s3')` API just works.

### Key files

| File                                | Purpose                                                                |
| ----------------------------------- | ---------------------------------------------------------------------- |
| `Dockerfile.vercel`                 | Multi-stage image: Vite build → Composer → FrankenPHP runtime          |
| `Caddyfile`                         | FrankenPHP config (`:{$PORT:80}`, `php_server`, docroot `/app/public`) |
| `vercel.json`                       | Declares the container service + catch-all rewrite                     |
| `vercel-entrypoint.sh`              | Writes `config/route/view` caches at boot (env injected at runtime)    |
| `.github/workflows/ci.yml`          | Lint + tests + build on every push/PR                                  |
| `.github/workflows/deploy.yml`      | Production deploy + migrations; preview deploys for PRs                |
| `app/Console/Commands/BlobTest.php` | `php artisan blob:test` — verifies your Blob store via the `s3` disk   |
| `config/filesystems.php`            | `s3` disk reused for Vercel Blob (S3-compatible endpoint)              |

---

## 2. Local development

Requirements: PHP 8.3+, Composer, Node 20+.

```bash
composer install
cp .env.example .env          # if .env doesn't exist yet
php artisan key:generate
npm install
php artisan migrate           # creates sqlite db + tables (users, cache, jobs, sessions)
npm run dev                   # Vite dev server
```

Then in a second terminal:

```bash
php artisan serve             # http://localhost:8000
```

Or run the full dev stack (server + queue + logs + vite) with:

```bash
composer run dev
```

---

## 3. Database

### How the database is configured

- **Local**: SQLite (`DB_CONNECTION=sqlite`, file `database/database.sqlite`).
- **Production**: Vercel Postgres. Laravel connects through `DB_URL`
  (the `POSTGRES_URL_NON_POOLING` value) with `DB_CONNECTION=pgsql` and `DB_SSLMODE=require`.

### Existing tables (migrations in `database/migrations/`)

| Migration                                     | Creates                                                                                            |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `0001_01_01_000000_create_users_table.php`    | `users`, `password_reset_tokens`, `sessions` _(users only — sessions has its own migration below)_ |
| `0001_01_01_000001_create_cache_table.php`    | `cache`, `cache_locks`                                                                             |
| `0001_01_01_000002_create_jobs_table.php`     | `jobs`, `job_batches`, `failed_jobs`                                                               |
| `0001_01_01_000003_create_sessions_table.php` | `sessions` (needed because `SESSION_DRIVER=database`)                                              |

### Creating a new migration

```bash
php artisan make:migration create_doctors_table
```

Open the generated file in `database/migrations/` and define the schema:

```php
Schema::create('doctors', function (Blueprint $table) {
    $table->id();
    $table->string('name');
    $table->string('specialty');
    $table->string('photo_path')->nullable();   // path stored in Vercel Blob
    $table->timestamps();
});
```

Apply it locally:

```bash
php artisan migrate
```

Roll it back (last batch only):

```bash
php artisan migrate:rollback
```

### Creating data (seeders)

```bash
php artisan make:seeder DoctorSeeder
```

Fill it in `database/seeders/DoctorSeeder.php`:

```php
use App\Models\Doctor;

Doctor::create(['name' => 'Dr. Sharma', 'specialty' => 'Cardiology']);
```

Run it:

```bash
php artisan db:seed --class=DoctorSeeder
```

And register it in `DatabaseSeeder` so `php artisan db:seed` runs everything, or create a
model + factory for fake data:

```bash
php artisan make:model Doctor -m -f     # model + migration + factory
php artisan make:factory DoctorFactory
php artisan tinker --execute="App\Models\Doctor::factory()->count(10)->create()"
```

### Production migrations

They run **automatically** as step 2 of the production deploy (see §7). You never migrate
production by hand — merging to `production` does it. To preview exactly what CI will run,
execute against a copy of your Postgres URL locally:

```bash
DB_CONNECTION=pgsql DB_URL="<POSTGRES_URL_NON_POOLING>" DB_SSLMODE=require php artisan migrate --force
```

---

## 4. Vercel setup (one-time, with YOUR account)

### 4.1 Create the project

```bash
npm i -g vercel
vercel login          # logs in as your account
vercel link           # inside this repo; choose "Other" framework preset
```

This writes `.vercel/project.json` (gitignored) with your `orgId` and `projectId`.

> The container runtime is a Vercel product feature — confirm your plan includes container
> images (the dashboard will warn during project setup if not).

### 4.2 Create storage

1. **Vercel dashboard → Storage → Create Database → Postgres** (Neon). Note the
   `POSTGRES_URL_NON_POOLING` connection string.
2. **Vercel dashboard → Storage → Create Database → Blob**. Open the store → **Settings →
   S3 API** and note the access key ID, secret, endpoint, and store ID.

### 4.3 Add Vercel environment variables

Path: `Vercel dashboard → your project → Settings → Environment Variables` → add each with
**Environment: Production** (add Preview too if you want previews to use the same DB).

| Variable                      | Value                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `APP_ENV`                     | `production`                                                                         |
| `APP_DEBUG`                   | `false`                                                                              |
| `APP_URL`                     | your domain, e.g. `https://your-app.vercel.app`                                      |
| `APP_KEY`                     | `php artisan key:generate --show` (run once locally, paste the full `base64:...`)    |
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
| `AWS_USE_PATH_STYLE_ENDPOINT` | `true` — required, Vercel Blob uses a per-store URL (no virtual-host style)          |
| `LOG_LEVEL`                   | `warning`                                                                            |

**Never** set `SESSION_DRIVER=file` / `CACHE_STORE=file` in production, and never commit a
real token or `.env` file.

### 4.4 Add GitHub secrets

Path: `GitHub repo → Settings → Secrets and variables → Actions → New repository secret`

| Secret              | Value                                                                    |
| ------------------- | ------------------------------------------------------------------------ |
| `VERCEL_TOKEN`      | Vercel → your avatar → **Settings → Tokens → Create**                    |
| `VERCEL_ORG_ID`     | `orgId` from `.vercel/project.json`                                      |
| `VERCEL_PROJECT_ID` | `projectId` from `.vercel/project.json`                                  |
| `DB_URL`            | the same `POSTGRES_URL_NON_POOLING` value (used by CI to run migrations) |

These are what make the workflow deploy **from your own account** — the official Vercel CLI,
no third-party action.

### 4.5 Protect `production`

GitHub → **Settings → Branches → Add rule** for `production`: require pull requests and the
`Quality checks` status check. Then the only way to deploy is a reviewed PR merged into
`production`.

---

## 5. CI/CD — what runs and when

### `ci.yml` (Quality checks)

Runs on every push to `main` / `development` / `production` and on every pull request:

1. PHP 8.4 + Composer install
2. `pint --test` (code style)
3. `php artisan test` (PHPUnit)
4. `npm ci` + `stylelint` + `npm run build`

### `deploy.yml`

| Trigger                             | What happens                                                                  |
| ----------------------------------- | ----------------------------------------------------------------------------- |
| Push/merge to `production`          | quality checks → **migrations** against Postgres → **`vercel deploy --prod`** |
| Pull request targeting `production` | quality checks → **preview deploy** → URL commented on the PR                 |

Production deploys are serialized (`concurrency` group) so two merges can't race.

---

## 6. Vercel Blob (images & files)

Vercel Blob is S3-compatible, so you use Laravel's standard `Storage` API with the `s3`
disk. No custom service, no `@vercel/blob` SDK, no extra packages beyond the built-in
`league/flysystem-aws-s3-v3`.

### Verify your store works

```bash
php artisan blob:test
```

Uploads, reads back, prints the public URL, and deletes a test file. Run it locally with the
`AWS_*` vars in your `.env`, or from anywhere with them exported. It also warns you if
`AWS_URL` is missing.

### Upload an image (public — best for a hospital site)

```php
use Illuminate\Support\Facades\Storage;

$path = Storage::disk('s3')->putFile('doctors', $request->file('photo'));
// or with a string: Storage::disk('s3')->put('doctors/dr-sharma.jpg', $contents);

// Build the public link for display:
$url = Storage::disk('s3')->url($path);
// https://<store-id>.public.blob.vercel-storage.com/doctors/xxxx.jpg
```

Store the returned `$path` in your DB (e.g. `doctors.photo_path`), then display with
`Storage::disk('s3')->url($doctor->photo_path)`.

### Delete / exists / list

```php
Storage::disk('s3')->delete($doctor->photo_path);
Storage::disk('s3')->exists($path);
Storage::disk('s3')->files('doctors/');   // list files under a prefix
```

### Requirements & limits

- `AWS_URL` **must** be set to `https://<store-id>.public.blob.vercel-storage.com` or
  `Storage::url()` will build a default AWS-style link that 404s.
- `AWS_USE_PATH_STYLE_ENDPOINT=true` is **required** — Vercel Blob serves each store from its
  own subdomain, which the SDK's default virtual-host style can't address.
- **Private blobs and presigned URLs are not supported** through the S3 disk — Vercel Blob
  signs those with its own tokens. Public website images (doctors, gallery) don't need them.
  If you ever need private files, use the official `@vercel/blob` Node SDK for that flow.

---

## 7. The deployment flow, step by step

1. Commit your changes on `development` and push.
2. Open a PR from `development` → `production`.
3. CI runs quality checks; a **preview deploy** is created and its URL is commented on the PR
   (log in to Vercel if you want to see the exact deployment).
4. Merge the PR (review + checks required if you set up branch protection).
5. GitHub Actions runs: checks → `php artisan migrate --force` → `vercel deploy --prod`.
6. Your live site is updated on your domain. Rollback = revert the merge and re-merge.

---

## 8. Troubleshooting

| Symptom                             | Cause / fix                                                                                                     |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| 502 Bad Gateway                     | Caddy not on `$PORT`. Keep `:{$PORT:80}` in `Caddyfile`.                                                        |
| 404 on routes                       | Docroot/rewrite: keep `root * /app/public` + `php_server`.                                                      |
| PHP changes not applied             | Caches rebuild at boot, but stale compiled views can linger — restart the deployment from Vercel.               |
| `blob:test` fails or wrong URLs     | Check the `AWS_*` env vars — especially `AWS_URL` (public base) and `AWS_USE_PATH_STYLE_ENDPOINT=true`.         |
| Migrations fail in deploy           | Check the `DB_URL` GitHub secret — must be the **non-pooling** URL.                                             |
| Preview deploys fail but PR is fine | Missing `VERCEL_*` secrets (previews use the same project).                                                     |
| Composer audit fails locally        | We cleared all current advisories (`league/commonmark`, `guzzlehttp/guzzle`) — run `composer audit` to confirm. |

---

## 9. Env var cheat sheet (one glance)

| Where                       | Variables                                                                                                                                                                                                                                                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Vercel env (Production)** | `APP_ENV`, `APP_DEBUG`, `APP_URL`, `APP_KEY`, `DB_CONNECTION`, `DB_URL`, `DB_SSLMODE`, `SESSION_DRIVER`, `CACHE_STORE`, `QUEUE_CONNECTION`, `FILESYSTEM_DISK`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_BUCKET`, `AWS_ENDPOINT`, `AWS_URL`, `AWS_DEFAULT_REGION`, `AWS_USE_PATH_STYLE_ENDPOINT`, `LOG_LEVEL` |
| **GitHub secrets**          | `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `DB_URL`                                                                                                                                                                                                                                                         |
| **Local `.env` only**       | everything from `.env.example` — local sqlite + (optionally) the `AWS_*` vars for `blob:test`                                                                                                                                                                                                                          |
