import { test } from "node:test";
import assert from "node:assert/strict";
import { createWalkingHandler } from "../supabase/functions/_shared/handlers/walking.ts";
import { RoutesProviderError } from "../supabase/functions/_shared/ports.ts";
import { call, fakeRoutes, makeDeps, ORIGIN, post } from "./helpers.ts";

test("returns route geometry, arrival time and eligibility", async () => {
  const res = await call(createWalkingHandler(makeDeps()), post({ origin: ORIGIN, aed_id: "fx-sample" }));

  assert.equal(res.status, 200);
  const data = res.body.data;
  assert.equal(data.aed.id, "fx-sample");
  assert.equal(data.geometry.type, "LineString");
  assert.deepEqual(data.geometry.coordinates[0], [ORIGIN.longitude, ORIGIN.latitude]);
  assert.deepEqual(data.steps, []);
  assert.equal(data.duration_seconds, 300);
  assert.equal(data.estimated_arrival_at, "2026-10-19T08:05:00.000Z");
  assert.equal(data.eligible_for_automatic_selection, true);
  assert.deepEqual(data.warnings, []);
  assert.equal(res.headers.get("Cache-Control"), "no-store");
});

test("routes to a restricted AED but marks it ineligible", async () => {
  const res = await call(createWalkingHandler(makeDeps()), post({ origin: ORIGIN, aed_id: "fx-restricted" }));

  assert.equal(res.status, 200);
  assert.equal(res.body.data.eligible_for_automatic_selection, false);
  assert.deepEqual(res.body.data.warnings, ["access_restricted"]);
});

test("warns about unknown hours", async () => {
  const res = await call(createWalkingHandler(makeDeps()), post({ origin: ORIGIN, aed_id: "fx-unknown-hours" }));

  assert.equal(res.body.data.eligible_for_automatic_selection, false);
  assert.deepEqual(res.body.data.warnings, ["hours_unknown_at_arrival"]);
});

test("404 for an unknown AED", async () => {
  const res = await call(createWalkingHandler(makeDeps()), post({ origin: ORIGIN, aed_id: "nope" }));
  assert.equal(res.status, 404);
  assert.equal(res.body.error.code, "aed_not_found");
});

test("422 route_not_found when Mapbox has no walking route", async () => {
  const deps = makeDeps({ routes: fakeRoutes({ route: () => null }) });
  const res = await call(createWalkingHandler(deps), post({ origin: ORIGIN, aed_id: "fx-sample" }));
  assert.equal(res.status, 422);
  assert.equal(res.body.error.code, "route_not_found");
});

test("503 when the routing provider fails", async () => {
  const deps = makeDeps({
    routes: fakeRoutes({
      route: () => {
        throw new RoutesProviderError("down");
      },
    }),
  });
  const res = await call(createWalkingHandler(deps), post({ origin: ORIGIN, aed_id: "fx-sample" }));
  assert.equal(res.status, 503);
  assert.equal(res.body.error.code, "routing_unavailable");
});
