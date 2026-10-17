import { test } from "node:test";
import assert from "node:assert/strict";
import { createFindHandler } from "../supabase/functions/_shared/handlers/find.ts";
import { FIXTURE_AEDS } from "../supabase/functions/_shared/fixtures.ts";
import type { FixtureAed } from "../supabase/functions/_shared/fixtures.ts";
import { RoutesProviderError } from "../supabase/functions/_shared/ports.ts";
import type { MatrixElement, Origin } from "../supabase/functions/_shared/ports.ts";
import { call, fakeRoutes, makeDeps, ORIGIN, post } from "./helpers.ts";

const byId = (id: string) => FIXTURE_AEDS.find((a) => a.id === id)!;

function aed(id: string, latitude: number, longitude: number, overrides: Partial<FixtureAed> = {}): FixtureAed {
  return { ...byId("fx-centrum-247"), id, source_id: id, location: { latitude, longitude }, ...overrides };
}

function matrixByLocation(durations: Map<string, number>) {
  return (destinations: Origin[]): MatrixElement[] =>
    destinations.map((d) => {
      const seconds = durations.get(`${d.latitude},${d.longitude}`);
      return seconds === undefined
        ? { status: "no_route" }
        : { status: "ok", duration_seconds: seconds, distance_m: seconds };
    });
}

test("selects the open AED with a route on a weekday morning", async () => {
  const routes = fakeRoutes();
  const res = await call(createFindHandler(makeDeps({ routes })), post({ origin: ORIGIN }));

  assert.equal(res.status, 200);
  const data = res.body.data;
  assert.equal(data.status, "found");
  assert.equal(data.selected.aed.id, "fx-sample");
  assert.equal(data.selected.availability_at_arrival.covers_access_buffer, true);
  assert.equal(data.selected.route.geometry.type, "LineString");
  assert.deepEqual(data.warnings, []);
  // Inactive, broken, restricted and unknown-hours AEDs are never routed or selected.
  assert.deepEqual(routes.matrixCalls[0].length, 1);
  assert.deepEqual(
    data.unknown_access_alternatives.map((u: { aed: { id: string }; reason: string }) => [u.aed.id, u.reason]),
    [["fx-unknown-hours", "hours_unknown"], ["fx-restricted", "access_restricted"]],
  );
  assert.deepEqual(res.body.meta.search, {
    evaluated_count: 1,
    searched_radius_m: 2000,
    budget_exhausted: false,
    ranking_scope: "evaluated_nearby_candidates",
  });
});

test("ranks by walking time, not straight-line distance", async () => {
  // "near" is closer as the crow flies but behind a barrier.
  const near = aed("near", 52.2085, 21.0135);
  const far = aed("far", 52.2110, 21.0160);
  const routes = fakeRoutes({
    matrix: matrixByLocation(new Map([["52.2085,21.0135", 900], ["52.211,21.016", 400]])),
  });
  const res = await call(createFindHandler(makeDeps({ aeds: [near, far], routes })), post({ origin: ORIGIN }));

  assert.equal(res.body.data.selected.aed.id, "far");
  assert.deepEqual(res.body.data.alternatives.map((a: { aed: { id: string } }) => a.aed.id), ["near"]);
  assert.equal(res.body.data.alternatives[0].walking.duration_seconds, 900);
});

test("respects max_results", async () => {
  const aeds = [1, 2, 3, 4, 5, 6].map((i) => aed(`a${i}`, 52.2080 + i * 0.001, 21.0130));
  const res = await call(createFindHandler(makeDeps({ aeds })), post({ origin: ORIGIN, max_results: 2 }));

  assert.equal(res.body.data.selected.aed.id, "a1");
  assert.equal(res.body.data.alternatives.length, 1);
});

test("skips an AED that closes within the access buffer and widens the search", async () => {
  // Monday 17:57 in Warsaw: the sample AED closes at 18:00.
  const now = new Date("2026-10-19T15:57:00Z");
  const routes = fakeRoutes({
    matrix: (destinations) =>
      destinations.map(() => ({ status: "ok" as const, duration_seconds: 90, distance_m: 120 })),
  });
  const res = await call(createFindHandler(makeDeps({ now, routes })), post({ origin: ORIGIN }));

  assert.equal(res.body.data.status, "found");
  assert.equal(res.body.data.selected.aed.id, "fx-centrum-247");
  assert.equal(res.body.meta.search.searched_radius_m, 5000);
  assert.equal(res.body.meta.search.evaluated_count, 2);
  assert.equal(routes.matrixCalls.length, 2);
});

test("an AED open exactly through arrival + buffer is eligible", async () => {
  // 17:55 + 180 s walk + 120 s buffer = 18:00, the exclusive closing boundary.
  const now = new Date("2026-10-19T15:55:00Z");
  const routes = fakeRoutes({
    matrix: (destinations) =>
      destinations.map(() => ({ status: "ok" as const, duration_seconds: 180, distance_m: 200 })),
  });
  const res = await call(createFindHandler(makeDeps({ now, routes })), post({ origin: ORIGIN }));

  assert.equal(res.body.data.selected.aed.id, "fx-sample");
});

test("no eligible AED returns 200 with unknown alternatives and budget exhausted", async () => {
  const aeds = [byId("fx-unknown-hours"), byId("fx-restricted"), byId("fx-inactive")];
  const routes = fakeRoutes();
  const res = await call(createFindHandler(makeDeps({ aeds, routes })), post({ origin: ORIGIN }));

  assert.equal(res.status, 200);
  assert.equal(res.body.data.status, "no_eligible_aed");
  assert.equal(res.body.data.selected, null);
  assert.equal(res.body.data.unknown_access_alternatives.length, 2);
  assert.equal(res.body.meta.search.budget_exhausted, true);
  assert.equal(routes.matrixCalls.length, 0);
});

test("weekend hours are unknown, so the sample AED is not auto-selected", async () => {
  const saturday = new Date("2026-10-24T08:00:00Z");
  const res = await call(createFindHandler(makeDeps({ now: saturday })), post({ origin: ORIGIN }));

  assert.equal(res.body.data.selected.aed.id, "fx-centrum-247");
  assert.ok(
    res.body.data.unknown_access_alternatives.some((u: { aed: { id: string } }) => u.aed.id === "fx-sample"),
  );
});

test("routing outage returns straight-line alternatives without ETAs", async () => {
  const routes = fakeRoutes({
    matrix: () => {
      throw new RoutesProviderError("down");
    },
  });
  const res = await call(createFindHandler(makeDeps({ routes })), post({ origin: ORIGIN }));

  assert.equal(res.status, 200);
  assert.equal(res.body.data.status, "routing_unavailable");
  assert.equal(res.body.data.selected, null);
  assert.deepEqual(res.body.data.warnings, ["walking_times_unavailable"]);
  assert.equal(res.body.data.alternatives[0].aed.id, "fx-sample");
  assert.equal(res.body.data.alternatives[0].walking, null);
  assert.ok(res.body.data.alternatives[0].aed.straight_line_distance_m > 0);
});

test("missing route geometry still returns the selected AED with a warning", async () => {
  const routes = fakeRoutes({
    route: () => {
      throw new RoutesProviderError("down");
    },
  });
  const res = await call(createFindHandler(makeDeps({ routes })), post({ origin: ORIGIN }));

  assert.equal(res.body.data.status, "found");
  assert.equal(res.body.data.selected.route, null);
  assert.deepEqual(res.body.data.warnings, ["route_geometry_unavailable"]);
});

test("validates input", async () => {
  const handler = createFindHandler(makeDeps());

  assert.equal((await call(handler, post({ origin: ORIGIN, max_results: 6 }))).status, 422);
  assert.equal((await call(handler, post({ origin: ORIGIN, max_results: 1.5 }))).status, 422);
  assert.equal((await call(handler, post({}))).status, 422);
  assert.equal((await call(handler, post([]))).status, 422);

  const outside = await call(handler, post({ origin: { latitude: 52.4, longitude: 20.7 } }));
  assert.equal(outside.body.error.code, "outside_service_area");
});
