# DefiWawa API

Small API for the Warsaw AED map. This replaces the larger API proposal in
[PLAN.md](PLAN.md). Browsing and routing do not require an account.

Base path: `/api/v1`. JSON coordinates use `{ "latitude": 52.21, "longitude": 21.01 }`;
GeoJSON uses `[longitude, latitude]`. Distances are meters, durations are seconds.

| Endpoint | Input | Result | Owner |
| --- | --- | --- | --- |
| `GET /aeds` | Optional `bbox=west,south,east,north` | AEDs for the map | Ярік |
| `GET /aeds/{id}` | AED ID | One AED with hours and access instructions | Ярік |
| `POST /aeds/find` | `origin`, optional `max_results` (1–5) | Selected AED, walking route and alternatives | Вітя |
| `POST /routes/etas` | `origin`, `aed_ids` (1–20) | Walking time and distance for each AED | Вітя |
| `POST /routes/walking` | `origin`, `aed_id` | Walking route, distance, time and availability | Вітя |
| `POST /reports` | Client-generated `id`, `aed_id`, `category`, `description`, `form_ms`; no auth | Report ID and `pending` status | Вітя |
| `GET /coverage` | None | Latest coverage GeoJSON with calculation date | Ярік |
| `GET /offline` | None | Warsaw basemap and AED download URLs, sizes, checksums and update date | Вітя |

**Implemented:** `aeds/find`, `routes/etas`, `routes/walking`. Supabase serves these
as `/functions/v1/aeds-find`, `/functions/v1/routes-etas`, and
`/functions/v1/routes-walking`; the `/api/v1` paths require a deployment proxy.
The other rows are the remaining implementation contract.

## AED data

Use one flat object: `id`, `source_id`, `object_name`, `full_address`, `lat`, `lon`,
`in_building`, `floor`, `access_instructions`, `public_access`, `operational_status`,
`hours_text`, `hours_status`, `hours_verified`, `hours`, `updated_at`.
The city dataset is small enough to return all active AEDs without cursor pagination.

`public_access` is `public`, `restricted`, or `unknown`. `operational_status` is
`unknown`, `confirmed_unavailable`, or `confirmed_operational`.
`hours_status` is `24/7`, `scheduled`, or `unknown`. Hours use Warsaw local time.
Keep the original `hours_text` for display. Structured hours live in one JSON field:

```json
{
  "weekly": {
    "1": { "state": "open_intervals", "intervals": [[480, 960]] },
    "6": { "state": "closed", "intervals": [] }
  },
  "exceptions": {},
  "holiday_policy": "unknown"
}
```

Weekdays run from `1` (Monday) to `7`; intervals contain minutes after midnight.
Date exceptions use `YYYY-MM-DD` keys with the same day shape. Missing days mean
unknown. The seed writes `closed` for the days a source text leaves out when that text
names its days ("poniedziałek-piątek 8-16"), and from OpenStreetMap, where an unlisted day is closed. Set `hours_verified` only after checking the parsed schedule; unverified
hours stay unknown. Opening hours do not prove that a device works.

## Finding and routing

Automatic selection checks public access, device status, and opening hours at
arrival with a two-minute access buffer. Unknown-hours AEDs remain separate
alternatives. Rank by walking time among checked candidates. Google keys stay on
the server; route geometry is a GeoJSON LineString.

Keep the existing routing response shape: `{ "data": ..., "meta": ... }`.
Find returns `status`, `selected`, `alternatives`, `unknown_access_alternatives`,
and `warnings`. Status is `found`, `no_eligible_aed`, or `routing_unavailable`.
ETA results can fail individually; never label straight-line distance as walking time.

## Reports

Reports need no login or phone verification: insert into `reports` with the anon
key. The client generates the report `id` as its idempotency key, so a retried
submission fails with a unique violation instead of creating a duplicate. Abuse is
limited in the database: 5 reports per client IP per hour and 20 per AED per hour;
over the limit the insert fails with HTTP 429 and message `rate_limited`. The client
IP comes only from the edge-set `cf-connecting-ip` header; `x-forwarded-for` is ignored
because clients can set it.

Send `form_ms`, the milliseconds the form was open. Reports are never rejected as spam;
the database flags them for moderators instead: `fast` (missing or under 3 s `form_ms`)
and `link` (URL in the description). The web form also has a hidden honeypot field;
when it is filled the app shows success without sending the report.

Categories: `missing`, `malfunction`, `inaccessible`, `incorrect_hours`,
`incorrect_location`, `other`. Descriptions are 10–2,000 trimmed characters.
Reports are private and do not automatically change AED data. Review reports and
edit AEDs in the Supabase dashboard; no admin API is needed for this project.
The private `report_queue` view groups pending reports by AED and category, ranked by
distinct unflagged clients, so repeated or flagged spam collapses into one low row.
`moderate_report_group(aed_id, category, status, last_at)` accepts or rejects a whole row.
Set `manually_edited=true` when correcting an AED so imports can skip it.

## Backend and storage

- `aeds`: one row per device, including address and JSON hours.
- `reports`: one row per report; only a hash of the client IP is kept, for rate limiting.
- `app_data`: public JSON documents keyed by `status`, `coverage`, or `offline`.
- `service_area` and `public_holiday`: small lookup tables for Warsaw and hours.

Run imports, hours parsing, coverage generation and offline builds as scripts.
No job-status, override-history, dataset-version, or per-region APIs are required.
Keep existing data when an import fails; skip manually edited rows. Upload offline
files to Storage and store the manifest in `app_data`. Do not store Google routes
in offline packages. Only publish sanitized data in `app_data`.

Use `{ "data": ... }` for new successful responses and
`{ "error": { "code": "...", "message": "..." } }` for failures. Existing routing
metadata remains compatible. Validate inputs, bound routing calls, and keep
reports and write access private. Return `400/422` for invalid input, `401/403`
for authorization failures, `404` for missing records and `503` for unavailable dependencies.
