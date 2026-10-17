import {
  createFixtureEvaluator,
  createFixtureRepository,
  FIXTURE_AEDS,
  haversineMeters,
} from "../supabase/functions/_shared/fixtures.ts";
import type { FixtureAed } from "../supabase/functions/_shared/fixtures.ts";
import type { Deps, MatrixElement, Origin, RoutesProvider, WalkingRoute } from "../supabase/functions/_shared/ports.ts";

// Monday 19 October 2026, 10:00 in Warsaw (CEST, UTC+2).
export const MONDAY_10AM = new Date("2026-10-19T08:00:00Z");

// A few hundred meters from the PLAN.md sample AED.
export const ORIGIN: Origin = { latitude: 52.2080, longitude: 21.0130 };

export type FakeRoutes = RoutesProvider & { matrixCalls: Origin[][]; routeCalls: Origin[] };

// Walking time defaults to straight-line distance at ~1.1 m/s, per destination overridable.
export function fakeRoutes(options: {
  matrix?: (destinations: Origin[]) => MatrixElement[];
  route?: (destination: Origin) => WalkingRoute | null;
} = {}): FakeRoutes {
  const matrixCalls: Origin[][] = [];
  const routeCalls: Origin[] = [];
  return {
    attribution: "Mapbox, © OpenStreetMap contributors",
    matrixCalls,
    routeCalls,
    walkingMatrix(origin, destinations) {
      matrixCalls.push(destinations);
      if (options.matrix) return Promise.resolve(options.matrix(destinations));
      return Promise.resolve(destinations.map((d) => {
        const meters = Math.round(haversineMeters(origin, d) * 1.3);
        return { status: "ok" as const, duration_seconds: Math.round(meters / 1.1), distance_m: meters };
      }));
    },
    walkingRoute(origin, destination) {
      routeCalls.push(destination);
      if (options.route) return Promise.resolve(options.route(destination));
      return Promise.resolve({
        duration_seconds: 300,
        distance_m: 400,
        geometry: {
          type: "LineString",
          coordinates: [[origin.longitude, origin.latitude], [destination.longitude, destination.latitude]],
        },
        steps: [],
      });
    },
  };
}

export function makeDeps(options: {
  aeds?: FixtureAed[];
  routes?: RoutesProvider;
  now?: Date;
} = {}): Deps {
  const aeds = options.aeds ?? FIXTURE_AEDS;
  const now = options.now ?? MONDAY_10AM;
  return {
    repo: createFixtureRepository(aeds),
    availability: createFixtureEvaluator(aeds),
    routes: options.routes ?? fakeRoutes(),
    now: () => now,
    config: {
      accessBufferSeconds: 120,
      allowedOrigins: ["https://defiwawa.example"],
      findRounds: [
        { radius_m: 2_000, limit: 20 },
        { radius_m: 5_000, limit: 20 },
      ],
    },
  };
}

export function post(body: unknown, init: RequestInit = {}): Request {
  return new Request("http://localhost/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
    ...init,
  });
}

// deno-lint-ignore no-explicit-any
export async function call(handler: (req: Request) => Promise<Response>, req: Request): Promise<{ status: number; body: any; headers: Headers }> {
  const res = await handler(req);
  return { status: res.status, body: await res.json(), headers: res.headers };
}
