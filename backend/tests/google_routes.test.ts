import { test } from "node:test";
import assert from "node:assert/strict";
import { createGoogleRoutesProvider } from "../supabase/functions/_shared/google_routes.ts";
import { RoutesProviderError } from "../supabase/functions/_shared/ports.ts";

const A = { latitude: 52.2, longitude: 21.0 };
const B = { latitude: 52.21, longitude: 21.01 };
const C = { latitude: 52.22, longitude: 21.02 };

function fakeFetch(status: number, body: unknown, seen: { url?: string; init?: RequestInit } = {}): typeof fetch {
  return ((url: string, init: RequestInit) => {
    seen.url = url;
    seen.init = init;
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  }) as typeof fetch;
}

test("matrix maps elements back to destinations, including an omitted index 0", async () => {
  const seen: { url?: string; init?: RequestInit } = {};
  const provider = createGoogleRoutesProvider({
    apiKey: "test-key",
    fetch: fakeFetch(200, [
      { destinationIndex: 2, status: {}, condition: "ROUTE_NOT_FOUND" },
      { status: {}, condition: "ROUTE_EXISTS", duration: "754s", distanceMeters: 910 },
      { destinationIndex: 1, status: { code: 3, message: "bad" } },
    ], seen),
  });

  const elements = await provider.walkingMatrix(A, [A, B, C]);

  assert.deepEqual(elements, [
    { status: "ok", duration_seconds: 754, distance_m: 910 },
    { status: "provider_error" },
    { status: "no_route" },
  ]);
  const headers = seen.init?.headers as Record<string, string>;
  assert.equal(headers["X-Goog-Api-Key"], "test-key");
  assert.match(headers["X-Goog-FieldMask"], /condition/);
  const body = JSON.parse(seen.init?.body as string);
  assert.equal(body.travelMode, "WALK");
  assert.equal(body.destinations.length, 3);
});

test("matrix elements missing from the response count as provider errors", async () => {
  const provider = createGoogleRoutesProvider({
    apiKey: "k",
    fetch: fakeFetch(200, [{ destinationIndex: 1, condition: "ROUTE_EXISTS", duration: "60s", distanceMeters: 70 }]),
  });
  const elements = await provider.walkingMatrix(A, [A, B]);
  assert.deepEqual(elements[0], { status: "provider_error" });
  assert.equal(elements[1].status, "ok");
});

test("matrix with no destinations does not call Google", async () => {
  let called = false;
  const provider = createGoogleRoutesProvider({
    apiKey: "k",
    fetch: (() => {
      called = true;
      return Promise.reject(new Error("unexpected"));
    }) as typeof fetch,
  });
  assert.deepEqual(await provider.walkingMatrix(A, []), []);
  assert.equal(called, false);
});

test("HTTP errors and network failures become RoutesProviderError", async () => {
  const httpError = createGoogleRoutesProvider({ apiKey: "k", fetch: fakeFetch(500, { error: {} }) });
  await assert.rejects(httpError.walkingMatrix(A, [B]), RoutesProviderError);

  const networkError = createGoogleRoutesProvider({
    apiKey: "k",
    fetch: (() => Promise.reject(new TypeError("offline"))) as typeof fetch,
  });
  await assert.rejects(networkError.walkingRoute(A, B), RoutesProviderError);
});

test("route returns GeoJSON geometry in [longitude, latitude] order", async () => {
  const seen: { url?: string; init?: RequestInit } = {};
  const geometry = { type: "LineString", coordinates: [[21.0, 52.2], [21.01, 52.21]] };
  const provider = createGoogleRoutesProvider({
    apiKey: "k",
    fetch: fakeFetch(200, {
      routes: [{ duration: "312s", distanceMeters: 401, polyline: { geoJsonLinestring: geometry } }],
    }, seen),
  });

  const route = await provider.walkingRoute(A, B);

  assert.deepEqual(route, { duration_seconds: 312, distance_m: 401, geometry });
  const body = JSON.parse(seen.init?.body as string);
  assert.equal(body.polylineEncoding, "GEO_JSON_LINESTRING");
  assert.deepEqual(body.origin, { location: { latLng: { latitude: 52.2, longitude: 21.0 } } });
});

test("route returns null when Google finds no route", async () => {
  const provider = createGoogleRoutesProvider({ apiKey: "k", fetch: fakeFetch(200, {}) });
  assert.equal(await provider.walkingRoute(A, B), null);
});

test("route without geometry is a provider error", async () => {
  const provider = createGoogleRoutesProvider({
    apiKey: "k",
    fetch: fakeFetch(200, { routes: [{ duration: "10s", distanceMeters: 5 }] }),
  });
  await assert.rejects(provider.walkingRoute(A, B), RoutesProviderError);
});
