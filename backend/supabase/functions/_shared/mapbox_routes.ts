// Mapbox walking routes (server-side only; the token never reaches the apps).
// Routing runs on OpenStreetMap, the same data as the Mapbox base map, so drawn routes follow its paths.
// https://docs.mapbox.com/api/navigation/matrix/
// https://docs.mapbox.com/api/navigation/directions/

import { RoutesProviderError } from "./ports.ts";
import type { LineString, MatrixElement, Origin, RouteStep, RoutesProvider, WalkingRoute } from "./ports.ts";

const MATRIX_URL = "https://api.mapbox.com/directions-matrix/v1/mapbox/walking";
const DIRECTIONS_URL = "https://api.mapbox.com/directions/v5/mapbox/walking";
// The Matrix API accepts at most 25 coordinates per request, the origin included.
const MAX_MATRIX_DESTINATIONS = 24;
const DEFAULT_TIMEOUT_MS = 8_000;

export type MapboxRoutesOptions = {
  accessToken: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
};

type MatrixResponse = {
  code?: string;
  // One row per source; null where no route exists.
  durations?: (number | null)[][];
  distances?: (number | null)[][];
};

type DirectionsStep = {
  distance?: number;
  duration?: number;
  name?: string;
  maneuver?: { type?: string; modifier?: string; instruction?: string; location?: [number, number] };
};

type DirectionsResponse = {
  code?: string;
  routes?: { duration?: number; distance?: number; geometry?: LineString; legs?: { steps?: DirectionsStep[] }[] }[];
};

export function createMapboxRoutesProvider(options: MapboxRoutesOptions): RoutesProvider {
  const fetchImpl = options.fetch ?? fetch;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  async function get(baseUrl: string, points: Origin[], params: Record<string, string>): Promise<unknown> {
    const query = new URLSearchParams({ ...params, access_token: options.accessToken });
    const url = `${baseUrl}/${points.map(coordinate).join(";")}?${query}`;
    let res: Response;
    try {
      res = await fetchImpl(url, { signal: AbortSignal.timeout(timeoutMs) });
    } catch (err) {
      throw new RoutesProviderError("Mapbox request failed", { cause: err });
    }
    if (!res.ok) throw new RoutesProviderError(`Mapbox responded with HTTP ${res.status}`);
    try {
      return await res.json();
    } catch (err) {
      throw new RoutesProviderError("Mapbox returned invalid JSON", { cause: err });
    }
  }

  async function matrixChunk(origin: Origin, destinations: Origin[]): Promise<MatrixElement[]> {
    const response = await get(MATRIX_URL, [origin, ...destinations], {
      sources: "0",
      destinations: destinations.map((_, i) => i + 1).join(";"),
      annotations: "duration,distance",
    }) as MatrixResponse;
    if (response.code !== "Ok") throw new RoutesProviderError(`Mapbox matrix returned ${response.code}`);
    const durations = response.durations?.[0];
    const distances = response.distances?.[0];
    if (!Array.isArray(durations) || !Array.isArray(distances)) {
      throw new RoutesProviderError("Unexpected route matrix response");
    }
    return destinations.map((_, i) => parseMatrixElement(durations[i], distances[i]));
  }

  return {
    attribution: "Mapbox, © OpenStreetMap contributors",

    async walkingMatrix(origin, destinations) {
      const chunks: Origin[][] = [];
      for (let i = 0; i < destinations.length; i += MAX_MATRIX_DESTINATIONS) {
        chunks.push(destinations.slice(i, i + MAX_MATRIX_DESTINATIONS));
      }
      const results = await Promise.all(chunks.map((chunk) => matrixChunk(origin, chunk)));
      return results.flat();
    },

    async walkingRoute(origin, destination) {
      const response = await get(DIRECTIONS_URL, [origin, destination], {
        geometries: "geojson",
        overview: "full",
        steps: "true",
        language: "pl",
      }) as DirectionsResponse;

      // NoRoute: no walking connection; NoSegment: a point is too far from any path.
      if (response.code === "NoRoute" || response.code === "NoSegment") return null;
      if (response.code !== "Ok") throw new RoutesProviderError(`Mapbox directions returned ${response.code}`);
      const route = response.routes?.[0];
      if (!route) return null;
      const geometry = route.geometry;
      if (geometry?.type !== "LineString" || !Array.isArray(geometry.coordinates)) {
        throw new RoutesProviderError("Route is missing GeoJSON geometry");
      }
      return {
        duration_seconds: parseNumber(route.duration, "duration"),
        distance_m: Math.round(route.distance ?? 0),
        geometry,
        steps: (route.legs ?? []).flatMap((leg) => leg.steps ?? []).flatMap(parseStep),
      } satisfies WalkingRoute;
    },
  };
}

function parseMatrixElement(duration: number | null | undefined, distance: number | null | undefined): MatrixElement {
  if (duration === null || distance === null) return { status: "no_route" };
  if (typeof duration !== "number" || typeof distance !== "number") return { status: "provider_error" };
  return { status: "ok", duration_seconds: Math.round(duration), distance_m: Math.round(distance) };
}

// Steps are guidance on top of the geometry: a malformed one is skipped instead of failing the route.
function parseStep(step: DirectionsStep): RouteStep[] {
  const m = step.maneuver;
  const location = m?.location;
  if (!m?.instruction || !m.type || !Array.isArray(location) || location.length !== 2) return [];
  return [{
    instruction: m.instruction,
    maneuver_type: m.type,
    maneuver_modifier: m.modifier ?? null,
    street: step.name || null,
    location,
    distance_m: Math.round(step.distance ?? 0),
    duration_seconds: Math.round(step.duration ?? 0),
  }];
}

// Mapbox reports seconds and meters as floats.
function parseNumber(value: number | undefined, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new RoutesProviderError(`Invalid ${field}: ${value}`);
  }
  return Math.round(value);
}

function coordinate(point: Origin): string {
  return `${point.longitude},${point.latitude}`;
}
