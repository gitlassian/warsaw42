# Edge Functions — routing (Вітя)

The simplified API is in [ENDPOINTS.md](../../../ENDPOINTS.md); database setup and
migration notes are in [../README.md](../README.md). Existing routing responses remain compatible.

| Function | Endpoint | Handler |
| --- | --- | --- |
| `routes-etas` | `POST /api/v1/routes/etas` | `_shared/handlers/etas.ts` |
| `routes-walking` | `POST /api/v1/routes/walking` | `_shared/handlers/walking.ts` |
| `aeds-find` | `POST /api/v1/aeds/find` | `_shared/handlers/find.ts` |

Handlers depend only on the interfaces in `_shared/ports.ts`, wired in `_shared/deps.ts`:

- Google Routes: `_shared/google_routes.ts`
- AED data and availability: `_shared/supabase_repository.ts`, which calls the database functions
  `aeds_nearby`, `aed_availability`, `is_inside_warsaw`, `current_dataset_version` and the `aed_public`
  view through PostgREST with the anon key
- `_shared/fixtures.ts`: fake AEDs for tests and for running without a database

All commands below run from `backend/`.

## Tests

```sh
npm test   # Node 22.18+ runs the TypeScript directly
```

## Local run

Requires the Supabase CLI and Docker. `supabase start` applies the migrations; the database is empty
until AED data is loaded.

```sh
cat > supabase/functions/.env <<EOF
GOOGLE_ROUTES_API_KEY=...
ALLOWED_ORIGINS=http://localhost:3000
EOF
supabase start
supabase functions serve --env-file supabase/functions/.env
```

Environment:

- `GOOGLE_ROUTES_API_KEY`: server-side Routes API key
- `ALLOWED_ORIGINS`: comma-separated web origins for CORS
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`: provided by the Edge Functions runtime
- `DEFIWAWA_USE_FIXTURES=1`: optional; serve the fake AEDs instead of the database
