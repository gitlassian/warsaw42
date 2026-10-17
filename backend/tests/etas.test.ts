import { test } from "node:test";
import assert from "node:assert/strict";
import { createEtasHandler } from "../supabase/functions/_shared/handlers/etas.ts";
import { RoutesProviderError } from "../supabase/functions/_shared/ports.ts";
import { call, fakeRoutes, makeDeps, ORIGIN, post } from "./helpers.ts";

test("returns one entry per requested id, in request order", async () => {
  const routes = fakeRoutes({
    matrix: (destinations) =>
      destinations.map((_, i) =>
        i === 0
          ? { status: "ok" as const, duration_seconds: 300, distance_m: 350 }
          : { status: "no_route" as const }
      ),
  });
  const handler = createEtasHandler(makeDeps({ routes }));

  const res = await call(handler, post({ origin: ORIGIN, aed_ids: ["fx-sample", "missing", "fx-centrum-247"] }));

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.data.map((e: { aed_id: string; status: string }) => [e.aed_id, e.status]), [
    ["fx-sample", "ok"],
    ["missing", "not_found"],
    ["fx-centrum-247", "no_route"],
  ]);
  const ok = res.body.data[0];
  assert.equal(ok.duration_seconds, 300);
  assert.equal(ok.estimated_arrival_at, "2026-10-19T08:05:00.000Z");
  assert.deepEqual(ok.availability_at_arrival, { status: "open", covers_access_buffer: true, reasons: ["weekly_hours"] });
  assert.equal(res.body.data[1].duration_seconds, null);
  assert.equal(routes.matrixCalls[0].length, 2, "unknown ids are not sent to Google");
  assert.equal(res.body.meta.dataset_version, "fixture-1");
  assert.equal(res.body.meta.attribution, "Google Maps");
  assert.equal(res.headers.get("Cache-Control"), "no-store");
});

test("a provider failure degrades to per-entry provider_error", async () => {
  const routes = fakeRoutes({
    matrix: () => {
      throw new RoutesProviderError("down");
    },
  });
  const res = await call(createEtasHandler(makeDeps({ routes })), post({ origin: ORIGIN, aed_ids: ["fx-sample"] }));

  assert.equal(res.status, 200);
  assert.equal(res.body.data[0].status, "provider_error");
  assert.equal(res.body.data[0].duration_seconds, null);
});

test("validates aed_ids", async () => {
  const handler = createEtasHandler(makeDeps());
  const tooMany = Array.from({ length: 21 }, (_, i) => `id-${i}`);

  for (const aed_ids of [[], tooMany, ["a", "a"], ["bad id with spaces"], "fx-sample"]) {
    const res = await call(handler, post({ origin: ORIGIN, aed_ids }));
    assert.equal(res.status, 422, JSON.stringify(aed_ids));
    assert.equal(res.body.error.code, "invalid_input");
    assert.ok(res.body.request_id);
  }
});

test("rejects origins outside Warsaw and invalid coordinates", async () => {
  const handler = createEtasHandler(makeDeps());

  const krakow = await call(handler, post({ origin: { latitude: 50.06, longitude: 19.94 }, aed_ids: ["fx-sample"] }));
  assert.equal(krakow.status, 422);
  assert.equal(krakow.body.error.code, "outside_service_area");

  const swapped = await call(handler, post({ origin: { latitude: 21.0, longitude: 252.2 }, aed_ids: ["fx-sample"] }));
  assert.equal(swapped.status, 422);
  assert.equal(swapped.body.error.details.field, "origin.longitude");
});

test("rejects malformed JSON and non-POST methods", async () => {
  const handler = createEtasHandler(makeDeps());

  const malformed = await call(handler, post("{not json"));
  assert.equal(malformed.status, 400);
  assert.equal(malformed.body.error.code, "malformed_json");

  const get = await call(handler, new Request("http://localhost/", { method: "GET" }));
  assert.equal(get.status, 405);
});

test("CORS headers only for allowed origins", async () => {
  const handler = createEtasHandler(makeDeps());

  const preflight = await handler(new Request("http://localhost/", {
    method: "OPTIONS",
    headers: { Origin: "https://defiwawa.example" },
  }));
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get("Access-Control-Allow-Origin"), "https://defiwawa.example");

  const other = await handler(post({ origin: ORIGIN, aed_ids: ["fx-sample"] }, {
    headers: { "Content-Type": "application/json", Origin: "https://evil.example" },
  }));
  assert.equal(other.headers.get("Access-Control-Allow-Origin"), null);
});
