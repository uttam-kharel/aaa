# vercel.json — annotated

`vercel.json` is strict JSON, so it can't hold comments itself. This file
explains every line. The actual config lives in [`vercel.json`](./vercel.json);
keep this document in sync when you change it.

```jsonc
// vercel.json — tells Vercel how to host this project
{
    // (optional) Lets editors validate this file against Vercel's official
    // schema and gives autocomplete for valid keys.
    "$schema": "https://openapi.vercel.sh/vercel.json",

    // Declares a container service — this is the "container runtime" feature.
    "services": {
        // Name of the service (arbitrary; the rewrite below references it).
        "api": {
            // Which directory in the repo contains the service (the whole repo).
            "root": ".",

            // The Dockerfile Vercel builds and runs.
            "entrypoint": "Dockerfile.vercel",

            // Tells Vercel: this is a Docker container, NOT a Node/static site.
            // This is what makes PHP/Laravel possible on Vercel.
            "runtime": "container"
        }
    },

    // Rules that route incoming requests.
    "rewrites": [
        {
            // Match every URL path ("/(.*)" catches everything).
            "source": "/(.*)",

            // Send it into the "api" container → Caddy → Laravel (index.php).
            "destination": {
                "service": "api"
            }
        }
    ]
}
```

## How the pieces fit together

1. **`services.api.runtime: "container"`** — the one line that changes
   everything. Vercel's default runtime is Node.js/static and cannot run PHP.
   This line tells Vercel to build `Dockerfile.vercel` and run it as a Docker
   container instead. Without it you get no app at all.
2. **`services.api.entrypoint: "Dockerfile.vercel"`** — the multi-stage
   Dockerfile that produces the runtime image: FrankenPHP (Caddy + PHP 8.4),
   Postgres extensions, compiled Vite assets, and production `vendor/`.
3. **`rewrites[0]`** — every request (homepage, routes, uploads) is routed
   into the container. Inside, Caddy serves `public/` and FrankenPHP rewrites
   non-file requests to Laravel's `index.php`, which routes them via
   `routes/web.php`.
4. **At boot** (`vercel-entrypoint.sh`), the container caches config/routes/
   views using the env vars Vercel injected at runtime, then starts FrankenPHP.

## Rules of thumb

- Keep `"runtime": "container"` — removing it breaks the deploy.
- Keep `"source": "/(.*)"` + the rewrite — without it requests never reach
  the container.
- `services.api` can be renamed, but the `destination.service` value must
  match. Keep both as `api` unless you have a reason to rename.
- This file is JSON — no comments allowed. If it ever fails to deploy, check
  this file first for stray commas or missing quotes.
