# Edge Functions — routing (Вітя)

| Function | Endpoint | Handler |
| --- | --- | --- |
| `routes-etas` | `POST /api/v1/routes/etas` | `_shared/handlers/etas.ts` |
| `routes-walking` | `POST /api/v1/routes/walking` | `_shared/handlers/walking.ts` |
| `aeds-find` | `POST /api/v1/aeds/find` | `_shared/handlers/find.ts` |

Handlers depend only on the interfaces in `_shared/ports.ts`. Google Routes is implemented in
`_shared/google_routes.ts`; the AED repository and availability evaluator are still fixtures
(`_shared/fixtures.ts`, test data only) until the database schema lands — swap them in `_shared/deps.ts`.

All commands below run from `backend/`.

## Tests

```sh
npm test   # Node 22.18+ runs the TypeScript directly
```

## Local run

Requires the Supabase CLI.

```sh
cat > supabase/functions/.env <<EOF
GOOGLE_ROUTES_API_KEY=...
DEFIWAWA_USE_FIXTURES=1
ALLOWED_ORIGINS=http://localhost:3000
EOF
supabase functions serve --env-file supabase/functions/.env
```

Environment: `GOOGLE_ROUTES_API_KEY` (server-side Routes API key), `ALLOWED_ORIGINS` (comma-separated
web origins for CORS), `DEFIWAWA_USE_FIXTURES=1` (required until the real repository is wired).
