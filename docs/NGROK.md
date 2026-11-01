# Using ngrok to reach the local system from another machine (temporary)

**Status:** set up on 2026-10-25 as a temporary convenience, reverted on 2026-10-27, set up again on 2026-10-27. Revert when no longer needed (see the end).

## How it works
One tunnel, to the admin dashboard (port 3100), reaches both sites:
- `https://<address>/`        the admin dashboard
- `https://<address>/portal`  the business (owner) portal

In ngrok mode the admin dashboard forwards `/portal/*` to the portal dev server (port 3200, which then serves itself under `/portal`)
and `/backend/*` to the API (port 8000). Both sites call the API through `/backend`, so there is no CORS setup and nothing else to tunnel.
A free ngrok account has a single address, which is why the two sites share it and are told apart by the path.

## Use it
1. Frontends in ngrok mode: `.\scripts\frontends.ps1 -Mode ngrok` (restarts only ports 3100 and 3200; repeat after any restart of the frontends).
2. Make sure the API (8000) and n8n are up as usual.
3. `ngrok http 3100` and copy the `https://....ngrok-free.dev` address it prints.
4. On the other machine open that address (dashboard) or that address + `/portal` (owner portal). Click ngrok's "Visit Site" once.
5. The address stays the same on a free account's own domain, but the tunnel only lives while ngrok runs.
   Stop it with Ctrl+C, or from PowerShell: `Get-Process ngrok | Stop-Process`.

Local use keeps working in this mode: `http://localhost:3100` (dashboard) and `http://localhost:3200/portal` (portal; note the `/portal`).

## What was changed (for the revert)
- `scripts/frontends.ps1` (new): restarts the two frontends in `ngrok` or `local` mode and sets, for ngrok mode only:
  `NEXT_PUBLIC_API_URL=/backend`, `API_PROXY_TARGET=http://localhost:8000`, `PORTAL_PROXY_TARGET=http://localhost:3200`, `PORTAL_BASE_PATH=/portal`.
- `admin-dashboard/next.config.js`: `rewrites()` for `/backend/*` and `/portal/*` (only when the variables above are set).
- `business-portal/next.config.js`: `basePath` from `PORTAL_BASE_PATH` and a `/backend/*` rewrite (only when the variables are set).
- The two sites keep their login in different browser keys (`token`, `portal_token`), so they do not clash on the shared address.

## Revert (when told)
1. Stop ngrok.
2. `.\scripts\frontends.ps1 -Mode local` (normal mode: pages call `http://localhost:8000`, portal at `http://localhost:3200`).
3. Full removal: delete `scripts/frontends.ps1` and this file, and put both `next.config.js` files back to just
   `transpilePackages: ['@mostafa-hussein-dev/ui']` (remove the ngrok comment, the `rewrites()` blocks and the `basePath` line).
   Without the variables those blocks do nothing, so step 2 alone already restores normal behaviour.
