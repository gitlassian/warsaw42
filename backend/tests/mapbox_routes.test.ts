import { test } from "node:test";
import assert from "node:assert/strict";
import { createMapboxRoutesProvider } from "../supabase/functions/_shared/mapbox_routes.ts";
import { RoutesProviderError } from "../supabase/functions/_shared/ports.ts";

const A = { latitude: 52.2, longitude: 21.0 };
const B = { latitude: 52.21, longitude: 21.01 };
const C = { latitude: 52.22, longitude: 21.02 };

function fakeFetch(status: number, body: unknown, urls: URL[] = []): typeof fetch {
  return ((url: string) => {
    urls.push(new URL(url));
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  }) as typeof fetch;
}

test("matrix maps one source row to destinations, with null as no route", async () => {
  const urls: URL[] = [];
  const provider = createMapboxRoutesProvider({
    accessToken: "test-token",
    fetch: fakeFetch(200, {
      code: "Ok",
      durations: [[753.6, null, 120]],
      distances: [[910.2, null, 150]],
    }, urls),
  });

  const elements = await provider.walkingMatrix(A, [A, B, C]);

  assert.deepEqual(elements, [
    { status: "ok", duration_seconds: 754, distance_m: 910 },
    { status: "no_route" },
    { status: "ok", duration_seconds: 120, distance_m: 150 },
  ]);
  const url = urls[0];
  assert.match(url.pathname, /\/directions-matrix\/v1\/mapbox\/walking\//);
  assert.ok(url.pathname.endsWith("/21,52.2;21,52.2;21.01,52.21;21.02,52.22"));
  assert.equal(url.searchParams.get("access_token"), "test-token");
  assert.equal(url.searchParams.get("sources"), "0");
  assert.equal(url.searchParams.get("destinations"), "1;2;3");
  assert.equal(url.searchParams.get("annotations"), "duration,distance");
});

test("matrix splits more than 24 destinations into several requests", async () => {
  const urls: URL[] = [];
  const destinations = Array.from({ length: 30 }, (_, i) => ({ latitude: 52.2, longitude: 21 + i / 1000 }));
  const provider = createMapboxRoutesProvider({
    accessToken: "k",
    fetch: ((url: string) => {
      const parsed = new URL(url);
      urls.push(parsed);
      const count = parsed.searchParams.get("destinations")!.split(";").length;
      const row = Array.from({ length: count }, (_, i) => i + 1);
      return Promise.resolve(new Response(JSON.stringify({ code: "Ok", durations: [row], distances: [row] })));
    }) as typeof fetch,
  });

  const elements = await provider.walkingMatrix(A, destinations);

  assert.equal(urls.length, 2);
  assert.equal(elements.length, 30);
  assert.deepEqual(elements[24], { status: "ok", duration_seconds: 1, distance_m: 1 });
});

test("matrix with no destinations does not call Mapbox", async () => {
  let called = false;
  const provider = createMapboxRoutesProvider({
    accessToken: "k",
    fetch: (() => {
      called = true;
      return Promise.reject(new Error("unexpected"));
    }) as typeof fetch,
  });
  assert.deepEqual(await provider.walkingMatrix(A, []), []);
  assert.equal(called, false);
});

test("HTTP errors, network failures and error codes become RoutesProviderError", async () => {
  const httpError = createMapboxRoutesProvider({ accessToken: "k", fetch: fakeFetch(401, { message: "Not Authorized" }) });
  await assert.rejects(httpError.walkingMatrix(A, [B]), RoutesProviderError);

  const networkError = createMapboxRoutesProvider({
    accessToken: "k",
    fetch: (() => Promise.reject(new TypeError("offline"))) as typeof fetch,
  });
  await assert.rejects(networkError.walkingRoute(A, B), RoutesProviderError);

  const badCode = createMapboxRoutesProvider({ accessToken: "k", fetch: fakeFetch(200, { code: "InvalidInput" }) });
  await assert.rejects(badCode.walkingMatrix(A, [B]), RoutesProviderError);
});

test("route returns full GeoJSON geometry in [longitude, latitude] order", async () => {
  const urls: URL[] = [];
  const geometry = { type: "LineString", coordinates: [[21.0, 52.2], [21.005, 52.205], [21.01, 52.21]] };
  const provider = createMapboxRoutesProvider({
    accessToken: "k",
    fetch: fakeFetch(200, {
      code: "Ok",
      routes: [{ duration: 311.7, distance: 400.6, geometry }],
    }, urls),
  });

  const route = await provider.walkingRoute(A, B);

  assert.deepEqual(route, { duration_seconds: 312, distance_m: 401, geometry });
  const url = urls[0];
  assert.match(url.pathname, /\/directions\/v5\/mapbox\/walking\/21,52.2;21.01,52.21$/);
  assert.equal(url.searchParams.get("geometries"), "geojson");
  assert.equal(url.searchParams.get("overview"), "full");
});

test("route returns null when Mapbox finds no route", async () => {
  for (const code of ["NoRoute", "NoSegment"]) {
    const provider = createMapboxRoutesProvider({ accessToken: "k", fetch: fakeFetch(200, { code, routes: [] }) });
    assert.equal(await provider.walkingRoute(A, B), null);
  }
});

test("route without geometry is a provider error", async () => {
  const provider = createMapboxRoutesProvider({
    accessToken: "k",
    fetch: fakeFetch(200, { code: "Ok", routes: [{ duration: 10, distance: 5 }] }),
  });
  await assert.rejects(provider.walkingRoute(A, B), RoutesProviderError);
});
