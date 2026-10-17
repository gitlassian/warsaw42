# Warsaw AED Map — API Endpoints

Proposed API specification for the shared web and Flutter mobile backend, based on [plan.md](plan.md). These endpoints describe the implementation contract; they are not implemented yet.

- **Base path:** `/api/v1`, mapped to the Supabase-backed API at deployment.
- **Public access:** browsing, discovery, routing, coverage, and offline downloads require no login.
- **Reporting:** phone verification issues a short-lived authorization for one report.
- **Administration:** `Authorization: Bearer <supabase_jwt_token>` with a server-verified moderator/admin role. Phone verification does not grant this role.
- **Internal jobs:** separate server-only credentials; never exposed to either client app.
- **Format:** JSON, with GeoJSON geometries where appropriate. Coordinates in GeoJSON use `[longitude, latitude]`; origin objects use named `latitude` and `longitude` fields.
- **Time and units:** RFC 3339 timestamps with an explicit offset, hours evaluated in `Europe/Warsaw`, distances in meters, durations in seconds.

---

### 1. AED Map and Details — Public

- **GET `/api/v1/aeds`** — List AEDs inside a map viewport. Accepts `bbox=west,south,east,north`, optional `availability=open|closed|unknown`, `public_access=public|restricted|unknown`, `at`, `limit`, and `cursor`. Returns marker data, evaluated availability, source freshness, and pagination.
- **GET `/api/v1/aeds/{id}`** — Get an AED's coordinates, venue, address, manufacturer, indoor/outdoor placement, public-access restrictions, entrance instructions, original access text, normalized schedule, reviewed operational status, and source timestamps.
- **GET `/api/v1/aeds/{id}/availability`** — Evaluate availability at `at` (defaults to server time), optionally through `until`. Returns `open|closed|unknown`, reasons, evaluation time, next known change, and whether the entire requested interval is covered by known opening hours.

Use a stable string AED ID; expose the original Warsaw `source_id` separately. Unknown hours must remain unknown. `operational_status=unknown|confirmed_unavailable|confirmed_operational` is independent of opening hours, with verification provenance where available. Opening hours alone never establish device health.

List responses use `{ "data": [], "meta": {}, "next_cursor": null }`. Default page size is 100, maximum 500. Cursors bind to the filters and dataset version; an expired/version-mismatched cursor returns `409 cursor_expired`, requiring a fresh first page. Clients may cluster downloaded viewport markers locally.

---

### 2. Nearby Discovery and Automatic Selection — Public

- **POST `/api/v1/aeds/nearby`** — Find AEDs near an `origin`, ordered by straight-line distance. Accepts `radius_m` (default 2,000; maximum 20,000), `limit` (default 20; maximum 100), and optional availability/access filters. Returns AED summaries, `distance_m`, and `distance_type=straight_line`. Does not call Google routing.
- **POST `/api/v1/aeds/find`** — Implement “Znajdź defibrylator.” Accepts an `origin` and optional `max_results` (default 3; maximum 5). Uses server time, public-access and operational-status checks, Google walking times, and availability at arrival plus the configured access buffer. Returns the selected AED, alternatives, and the selected walking route when available.

`origin` has the shape `{ "latitude": 52.2086, "longitude": 21.0149 }`. The find operation begins with up to 20 candidates within 2 km and may expand within a bounded server-side budget. Clients cannot bypass access filtering or increase paid API limits.

The find response includes `status=found|no_eligible_aed|routing_unavailable`, `selected` (nullable), `alternatives`, `unknown_access_alternatives`, and search metadata: evaluated count, searched radius, budget exhaustion, dataset version, and evaluation time. State that ranking applies to evaluated candidates, not every AED in the city. Unknown/restricted alternatives are never silently treated as eligible results.

Return `200` for a completed search with no eligible AED. A routing failure with usable distance-only alternatives may return `200` with `status=routing_unavailable`, `route=null`, and an explicit warning. A total dependency failure with no usable result returns `503`.

---

### 3. Walking Times and Routes — Public

- **POST `/api/v1/routes/etas`** — Get walking times for visible individual AED markers. Accepts `origin` and `aed_ids` (1–20 unique IDs). Returns one result per requested ID with `status=ok|no_route|not_found|provider_error`, `duration_seconds`, `distance_m`, `estimated_arrival_at`, and availability at arrival. Failed entries have null route values.
- **POST `/api/v1/routes/walking`** — Build a walking route to a selected AED. Accepts `origin` and `aed_id`. Returns route geometry, distance, duration, predicted arrival, access-buffer eligibility, and availability warnings. Allows manually selected destinations with uncertain/closed access, but clearly marks them ineligible for automatic selection.

Use Google Routes API through the backend. Return geometry as a GeoJSON `LineString` in `[longitude, latitude]` order and include required provider attribution. The initial interface uses geometry and summary metrics; Google route descriptions/steps are outside this contract. AED entrance instructions come from our own source records.

Partial ETA failures do not discard successful results. If no walking route exists, the walking endpoint returns `422 route_not_found`. Do not represent straight-line distance as a walking route or a successful Google ETA.

Routing responses use `Cache-Control: no-store` and do not enter offline packages. Bound request size, rate-limit anonymous usage, and keep provider secrets server-side. Do not log origin coordinates in routine request logs.

---

### 4. Phone Verification and Reports — OTP Required for Submission

- **POST `/api/v1/reports/otp/request`** — Start phone verification for a report. Accepts `phone` in E.164 format, `aed_id`, `category`, and `description`. Returns an opaque `challenge_id`, expiration, masked phone display, and resend time. The server binds the challenge to the validated report draft.
- **POST `/api/v1/reports/otp/resend`** — Resend the code for an active `challenge_id`, subject to cooldowns and send limits. Returns updated expiry/resend metadata. Changing the phone or report draft requires a new challenge.
- **POST `/api/v1/reports/otp/verify`** — Verify `challenge_id` and `code` through the configured OTP provider. Returns a short-lived, single-use `report_token` bound to that draft. A saved auth session does not replace a fresh OTP check.
- **POST `/api/v1/reports`** — Submit the bound draft using `Authorization: Bearer <report_token>` and `Idempotency-Key: <client-generated UUID>`. Consumes the authorization atomically and returns `201` with a report ID, `status=pending`, and submission time.

Report categories: `missing`, `malfunction`, `inaccessible`, `incorrect_hours`, `incorrect_location`, and `other`. Require a trimmed description of 10–2,000 characters. Reports do not immediately change public AED status; they enter moderation.

Proposed limits: five-minute OTP lifetime, 60-second resend cooldown, five verification attempts per challenge, and a ten-minute report-token lifetime. Enforce additional phone/IP send quotas and return the actual configured timings to clients. Store tokens hashed, invalidate superseded codes/challenges, and never log OTPs or raw tokens.

Keep phone numbers in private auth/provider storage; challenge/report records reference private identities. The OTP endpoints wrap the provider flow and do not expose a general account/profile feature. Expire abandoned challenge drafts with their verification state.

For submission retries, retain a receipt keyed to the authorization and idempotency key for 24 hours. Repeating the successful request returns the original receipt without creating another report; using a consumed token with a different key returns `409 authorization_used`. There is no public report listing or phone lookup endpoint.

---

### 5. Coverage Gaps — Public

- **GET `/api/v1/coverage`** — Get a viewport's coverage layer as a GeoJSON `FeatureCollection` inside `data`. Accepts `bbox`, `scenario=all_public|available_at|always_open`, `threshold_m` (default 500; range 100–2,000), and `at` for `available_at` (defaults to server time). Returns cells/regions, distance metrics, eligible AED counts, data version, and calculation time.
- **GET `/api/v1/coverage/{layer_id}/regions/{region_id}`** — Explain a region from a versioned coverage response: nearest eligible AED at its representative point, distance, threshold, scenario, evaluation time, sampling method, and data-quality limitations.

Use the planned 250 m grid and straight-line distances. `all_public` ignores opening hours, `always_open` requires confidently known 24/7 public access, and `available_at` evaluates schedules at the selected time. Every scenario excludes inactive and confirmed unavailable devices.

Include `layer_id`, `scenario`, `evaluated_at`, `valid_until`, `threshold_m`, `grid_size_m`, and `distance_type=straight_line` in metadata. Return `nearest_aed_id=null`, `nearest_distance_m=null`, and `coverage_status=no_known_eligible_aed` when no eligible AED exists; do not encode infinity as a JSON number.

For an uncached layer requiring background calculation, return `202` with `status=processing` and `Retry-After`; clients retry the same GET. Bound supported area/time ranges and calculation concurrency. Reject unsupported requests with `422`. Cached time-specific layers expire at relevant schedule/override boundaries even if no import occurs. Return `410 layer_expired` if a requested region's version has been retired.

---

### 6. Offline Map Packages — Public, Used by Mobile

- **GET `/api/v1/offline/regions`** — List downloadable areas such as Warsaw and supported districts, with IDs, names, bounds, available package versions, total download sizes, and update dates.
- **GET `/api/v1/offline/regions/{region_id}/manifest`** — Get the latest manifest, optionally supplying `installed_version` and `schema_version`. Returns `update_available`, compatibility, package/data versions, generation time, attribution, and separate basemap/AED assets with download URLs, byte sizes, formats, and SHA-256 checksums.

Asset download URLs point directly to Storage/CDN resources; do not proxy large map files through an Edge Function. Assets are immutable and versioned, support resumable HTTP Range downloads, and remain available for the published retention window. The manifest states `assets_available_until`; if a download URL expires, fetch a fresh manifest.

An AED asset contains sanitized locations, schedules, original access instructions, effective reviewed overrides with validity periods, and freshness timestamps. A basemap asset includes the map resources needed for an offline cold start. Version these independently so updated AED data does not require downloading the basemap again.

Use ETag/conditional GET for manifests, return `304` when unchanged, and return `409 schema_unsupported` for an incompatible requested schema. There are no offline Google route/ETA assets. Downloads require no account; the mobile client validates checksums and activates complete packages atomically.

---

### 7. Public Dataset Status

- **GET `/api/v1/data/status`** — Return the published dataset version, active AED count, source attribution, last successful fetch, known source update time, and `fresh|stale|unavailable` synchronization status. Include the expected two-hour refresh interval and a user-safe notice if the last usable snapshot is stale.

A successful fetch is not a physical inspection. Expose source update and verification timestamps separately, and use null when unknown. This endpoint must not expose credentials, raw importer errors, private reports, or administrative configuration.

---

### 8. Report Moderation and AED Corrections — Moderator/Admin Only

- **GET `/api/v1/admin/reports`** — List reports with `status=pending|accepted|rejected|resolved`, optional `aed_id`, and cursor pagination. Return report content and internal reporter references, not raw phone numbers by default.
- **GET `/api/v1/admin/reports/{id}`** — Get one report, its AED context, and moderation history.
- **PATCH `/api/v1/admin/reports/{id}`** — Record a moderation decision with `status`, mandatory `reason`, and `expected_version` for concurrency control. Enforce permitted state transitions and audit the reviewer.
- **POST `/api/v1/admin/aeds/{id}/overrides`** — Create a reviewed correction to hours, access, coordinates, or operational condition. Requires `type`, schema-validated `value`, `reason`, `valid_from`, `valid_until`, and optional `report_id`.
- **PATCH `/api/v1/admin/aeds/{id}/overrides/{override_id}`** — Revoke an override with a reason and `expected_version`, preserving its audit history. Changes to its content require a replacement override.

Accepting a report records the moderation decision; changing public AED behavior requires an explicit override. Reject ambiguous overlapping overrides with `409 override_conflict`. Creating/revoking an override updates the published data version and invalidates affected coverage/package outputs. Imports must never overwrite reviewed corrections.

These endpoints support a future administration interface. The initial restricted Supabase moderation workflow may invoke the same validated database operations without implementing a separate admin app.

---

### 9. Warsaw Import and Hours Parsing — Internal Only

- **POST `/api/v1/internal/sources/warsaw/sync`** — Queue a Warsaw Open Data import. Called every two hours or manually by an authorized operator. Validates snapshot completeness, upserts source records, queues changed schedules, and publishes a coherent dataset version. Returns `202` with `job_id`.
- **GET `/api/v1/internal/sources/warsaw/status`** — Inspect the last successful run, current job, source counts, quarantined rows, pending parsing work, and sanitized failure details.
- **POST `/api/v1/internal/aeds/{id}/parse-hours`** — Queue reprocessing of an AED's current access text, optionally with a parser version and reason. Returns `202` with `job_id`. Input comes from the stored source record, not arbitrary public text.
- **GET `/api/v1/internal/jobs/{job_id}`** — Get `queued|running|succeeded|failed`, progress counts, timestamps, and sanitized errors for an import, parsing, coverage, or package job.

AI parsing runs in the background and produces the schedule schema defined in `plan.md`, including source hashes and validation/review state. Ambiguous or invalid results remain unknown. No client-side AI endpoint is needed.

Importer errors and partial/empty snapshots cannot erase the last successful dataset. Use job locks and an `Idempotency-Key` for mutation retries. Deduplicate active jobs by resource/input version and return their existing job ID when equivalent work is already queued.

The exact upstream Warsaw endpoint, resource ID, and credentials remain configuration tasks. The internal `/sources/warsaw/sync` path is our API endpoint, not a claimed Warsaw Open Data URL.

---

### 10. Coverage and Offline Generation — Internal Only

- **POST `/api/v1/internal/coverage/rebuild`** — Queue coverage computation for a published dataset version, scenario, evaluation time, and threshold. Reuse the same job for duplicate inputs. Returns `202` with `job_id`.
- **POST `/api/v1/internal/offline/regions/{region_id}/build`** — Queue a versioned offline package build for a published dataset version. Reuse unchanged basemap assets, validate generated artifacts, and publish the manifest only after all assets are ready. Returns `202` with `job_id`.

Workers invoke these operations after relevant source/override updates and when time-dependent coverage expires. Internal endpoints require scoped server credentials and cannot be triggered using the public application key or a phone-verified reporter token.

---

### 11. Shared Response and Error Rules

- Successful JSON responses use `{ "data": ..., "meta": ... }`; paginated lists also include `next_cursor`.
- Include `request_id` and `generated_at` in `meta`. AED-derived responses also include `dataset_version` and relevant freshness/evaluation timestamps. Authentication responses do not need a dataset version.
- Errors use `{ "error": { "code": "invalid_input", "message": "...", "details": {} }, "request_id": "..." }`. Do not expose stack traces, secrets, OTPs, or phone numbers.
- Return `400` for malformed JSON/query syntax; `422` for field/domain validation failures; `401` for missing/invalid authorization; `403` for insufficient role; `404` for unknown resources; `409` for conflicts; `410` for expired resources; `429` for rate limits; and `503` for unavailable dependencies without a usable fallback.
- Return `Retry-After` on rate limits and queued coverage responses. UI clients localize stable error codes rather than relying on message text.
- Validate finite WGS84 coordinates, ordered/bounded bounding boxes, allowed timestamps, IDs, and request sizes. Reject invalid input rather than silently swapping coordinate order.
- Apply `Cache-Control: no-store` to OTP, report, admin, nearby-origin, and routing responses. Public AED/coverage caching must expire at the next relevant schedule/override boundary. Offline assets are immutable and versioned.
- Allow the deployed web origins through CORS. CORS is not authorization; enforce access rules on the server and prevent direct Supabase table access from bypassing them.

The web and mobile apps use these same contracts. Offline mobile browsing and schedule evaluation operate on downloaded data locally and do not call the API until connectivity returns.
