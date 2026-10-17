# Database

Apply migrations in filename order. `20261017150000_simplify_app_schema` replaces the
original normalized model with five app tables:

| Table | Contents |
| --- | --- |
| `aeds` | Device, address, coordinates, access instructions and JSON hours |
| `reports` | Private issue reports with a client IP hash for rate limiting |
| `app_data` | Public `status`, `coverage` and `offline` JSON documents |
| `service_area` | Warsaw boundary |
| `public_holiday` | Dates needed when evaluating opening hours |

For a new database, apply all migrations, then `seed.sql`. Regenerate the seed
from `backend/` with `python3 -m pipeline.seed_sql`. It loads 710 AEDs and expects
an empty `aeds` table. Do not run it on an already populated deployment.

For an existing database, apply only the migrations it has not run yet. Prefer
`npx supabase db push`, which records applied migrations in
`supabase_migrations.schema_migrations`; migrations pasted into the SQL editor are not
recorded (mark them with `npx supabase migration repair --status applied <version>`).
The simplification migration copies AEDs and reports, preserving IDs, and
moves the old tables/functions/types into the private `defi_legacy` schema.
The archive is for inspecting historical data; its old functions are retired.
Keep `defi_legacy` out of Supabase's exposed schemas. No old data is deleted.

Permanent active corrections are copied and marked `manually_edited`. The migration
stops if scheduled or unexpired temporary overrides exist: review and resolve
those before migrating, since direct row edits no longer have expiry rules.
Old coverage/offline artifacts remain archived; regenerate their public JSON
into `app_data` before enabling those planned endpoints.

Import scripts should upsert by `source_id`, skip `manually_edited` rows, and write
hours and `hours_verified` together. Changed text must be re-parsed before its
schedule is trusted. Preserve the last good dataset on incomplete imports.
Keep holiday dates up to date (the seed covers 2026–2027).

Public roles can read active AEDs and `app_data`. Anyone can insert a report for an
active AED (no phone verification), but cannot read reports or change their status.
A trigger limits inserts to 5 per client IP and 20 per AED per hour (`PT429`, HTTP 429).
The client IP is read only from `cf-connecting-ip`, so the per-client limit is inactive on a
local stack. The trigger also sets `flags` (`fast`, `link`) from `form_ms` and the text.
Moderate from the service-role-only `report_queue` view (pending reports grouped by AED and
category) and `moderate_report_group(aed_id, category, status, last_at)`.
Use the dashboard or server service role for moderation and imports. Never place
private data in `app_data`. For direct report inserts, use `return=minimal`; a
server endpoint can return the report receipt after inserting it.

`aed_public` and four RPCs keep the existing routing Edge Functions compatible;
they now read the flat table. There is no need to change their public responses.

Run the SQL smoke test against a local/test database after all migrations:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/schema_smoke.sql
```

It rolls back its fixtures and checks schedules, routing reads, and report RLS.
`initial_schema_smoke.sql` is retained only for testing the original migration
before the simplification migration is applied.
