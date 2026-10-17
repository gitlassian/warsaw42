import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createSupabaseEvaluator,
  createSupabaseRepository,
} from "../supabase/functions/_shared/supabase_repository.ts";
import { createFindHandler } from "../supabase/functions/_shared/handlers/find.ts";
import { DataSourceError } from "../supabase/functions/_shared/ports.ts";
import { call, makeDeps, ORIGIN, post } from "./helpers.ts";

const AED_A = "11111111-1111-4111-8111-111111111111";
const AED_B = "22222222-2222-4222-8222-222222222222";

function row(id: string, lat: number, lon: number) {
  return {
    id,
    source_id: id.slice(0, 4),
    lon,
    lat,
    object_name: `Venue ${id.slice(0, 4)}`,
    full_address: "ul. Rakowiecka 25/27, 02-517 Warszawa",
    access_instructions: "Przy wejściu głównym",
    public_access: "public",
    operational_status: "unknown",
  };
}

type Call = { url: string; method: string; body: unknown; headers: Record<string, string> };

// Fake PostgREST: answers by path, records every request.
function fakeSupabase(routes: Record<string, (body: unknown, url: URL) => unknown>, status = 200) {
  const calls: Call[] = [];
  const fetchImpl = ((input: string, init: RequestInit = {}) => {
    const url = new URL(input);
    const body = init.body ? JSON.parse(init.body as string) : null;
    calls.push({ url: input, method: init.method ?? "GET", body, headers: init.headers as Record<string, string> });
    const handler = routes[url.pathname];
    if (!handler) return Promise.resolve(new Response("not found", { status: 404 }));
    return Promise.resolve(new Response(JSON.stringify(handler(body, url)), { status }));
  }) as typeof fetch;
  return { calls, options: { url: "https://project.supabase.co/", anonKey: "anon-key", fetch: fetchImpl } };
}

test("findCandidates keeps the database distance order and maps aed_public rows", async () => {
  const db = fakeSupabase({
    "/rest/v1/rpc/aeds_nearby": () => [{ id: AED_B, distance_m: 120.4 }, { id: AED_A, distance_m: 480.6 }],
    "/rest/v1/aed_public": () => [row(AED_A, 52.21, 21.01), row(AED_B, 52.209, 21.014)],
  });
  const repo = createSupabaseRepository(db.options);

  const candidates = await repo.findCandidates({
    origin: ORIGIN,
    radius_m: 2000,
    limit: 20,
    exclude_ids: [AED_A, "not-a-uuid"],
  });

  assert.deepEqual(candidates.map((c) => [c.id, c.straight_line_distance_m]), [[AED_B, 120], [AED_A, 481]]);
  assert.deepEqual(candidates[0].location, { latitude: 52.209, longitude: 21.014 });
  assert.equal(candidates[0].venue_name, "Venue 2222");
  assert.equal(candidates[0].active, true);
  assert.deepEqual(db.calls[0].body, {
    p_lat: ORIGIN.latitude,
    p_lon: ORIGIN.longitude,
    p_radius_m: 2000,
    p_limit: 20,
    p_exclude: [AED_A],
  });
  assert.equal(db.calls[0].headers.apikey, "anon-key");
  assert.match(db.calls[1].url, /\/rest\/v1\/aed_public\?select=.*&id=in\.\(2222.*,1111.*\)$/);
});

test("findCandidates skips the details query when nothing is nearby", async () => {
  const db = fakeSupabase({ "/rest/v1/rpc/aeds_nearby": () => [] });
  const repo = createSupabaseRepository(db.options);
  assert.deepEqual(await repo.findCandidates({ origin: ORIGIN, radius_m: 2000, limit: 20, exclude_ids: [] }), []);
  assert.equal(db.calls.length, 1);
});

test("getByIds ignores ids that are not uuids without querying for them", async () => {
  const db = fakeSupabase({ "/rest/v1/aed_public": () => [row(AED_A, 52.21, 21.01)] });
  const repo = createSupabaseRepository(db.options);

  assert.deepEqual(await repo.getByIds(["fx-sample"]), []);
  assert.equal(db.calls.length, 0);

  const records = await repo.getByIds([AED_A, "fx-sample"]);
  assert.equal(records.length, 1);
  assert.match(db.calls[0].url, new RegExp(`id=in\\.\\(${AED_A}\\)$`));
});

test("service area and dataset version come from database functions", async () => {
  const db = fakeSupabase({
    "/rest/v1/rpc/is_inside_warsaw": (body) => (body as { p_lat: number }).p_lat < 53,
    "/rest/v1/rpc/current_dataset_version": () => 42,
  });
  const repo = createSupabaseRepository(db.options);

  assert.equal(await repo.isInsideWarsaw(ORIGIN), true);
  assert.equal(await repo.isInsideWarsaw({ latitude: 54.35, longitude: 18.65 }), false);
  assert.equal(await repo.datasetVersion(), "42");
});

test("an empty database reports an unpublished dataset", async () => {
  const db = fakeSupabase({ "/rest/v1/rpc/current_dataset_version": () => null });
  assert.equal(await createSupabaseRepository(db.options).datasetVersion(), "unpublished");
});

test("evaluator passes the arrival window to aed_availability", async () => {
  const db = fakeSupabase({
    "/rest/v1/rpc/aed_availability": () => [{ status: "open", covers_interval: true, reasons: ["weekly_hours"] }],
  });
  const evaluator = createSupabaseEvaluator(db.options);

  const result = await evaluator.evaluate(AED_A, new Date("2026-10-19T08:05:00Z"), new Date("2026-10-19T08:07:00Z"));

  assert.deepEqual(result, { status: "open", covers_interval: true, reasons: ["weekly_hours"] });
  assert.deepEqual(db.calls[0].body, {
    p_aed_id: AED_A,
    p_from: "2026-10-19T08:05:00.000Z",
    p_until: "2026-10-19T08:07:00.000Z",
  });
});

test("database errors surface as DataSourceError", async () => {
  const db = fakeSupabase({ "/rest/v1/rpc/is_inside_warsaw": () => ({ message: "boom" }) }, 500);
  await assert.rejects(createSupabaseRepository(db.options).isInsideWarsaw(ORIGIN), DataSourceError);
});

test("the API answers 503 data_unavailable when the database is down", async () => {
  const db = fakeSupabase({}, 500);
  const deps = { ...makeDeps(), repo: createSupabaseRepository(db.options) };

  const res = await call(createFindHandler(deps), post({ origin: ORIGIN }));

  assert.equal(res.status, 503);
  assert.equal(res.body.error.code, "data_unavailable");
});
