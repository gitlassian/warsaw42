// Google Routes API client (server-side only; the key never reaches the apps).
// https://developers.google.com/maps/documentation/routes/compute_route_matrix
// https://developers.google.com/maps/documentation/routes/compute_route_directions

import { RoutesProviderError } from "./ports.ts";
import type { LineString, MatrixElement, Origin, RoutesProvider, WalkingRoute } from "./ports.ts";

const MATRIX_URL = "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix";
const ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes";
const MATRIX_FIELDS = "originIndex,destinationIndex,status,condition,duration,distanceMeters";
const ROUTE_FIELDS = "routes.duration,routes.distanceMeters,routes.polyline.geoJsonLinestring";
const DEFAULT_TIMEOUT_MS = 8_000;

export type GoogleRoutesOptions = {
  apiKey: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
};

type MatrixResponseElement = {
  destinationIndex?: number;
  status?: { code?: number; message?: string };
  condition?: string;
  duration?: string;
  distanceMeters?: number;
};

type RoutesResponse = {
  routes?: {
    duration?: string;
    distanceMeters?: number;
    polyline?: { geoJsonLinestring?: LineString };
  }[];
};

export function createGoogleRoutesProvider(options: GoogleRoutesOptions): RoutesProvider {
  const fetchImpl = options.fetch ?? fetch;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  async function post(url: string, fieldMask: string, body: unknown): Promise<unknown> {
    let res: Response;
    try {
      res = await fetchImpl(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": options.apiKey,
          "X-Goog-FieldMask": fieldMask,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      throw new RoutesProviderError("Google Routes request failed", { cause: err });
    }
    if (!res.ok) throw new RoutesProviderError(`Google Routes responded with HTTP ${res.status}`);
    try {
      return await res.json();
    } catch (err) {
      throw new RoutesProviderError("Google Routes returned invalid JSON", { cause: err });
    }
  }

  return {
    attribution: "Google Maps",

    async walkingMatrix(origin, destinations) {
      if (destinations.length === 0) return [];
      const response = await post(MATRIX_URL, MATRIX_FIELDS, {
        origins: [{ waypoint: waypoint(origin) }],
        destinations: destinations.map((d) => ({ waypoint: waypoint(d) })),
        travelMode: "WALK",
      });
      if (!Array.isArray(response)) throw new RoutesProviderError("Unexpected route matrix response");

      // Elements Google leaves out stay as provider errors.
      const elements: MatrixElement[] = destinations.map(() => ({ status: "provider_error" }));
      for (const element of response as MatrixResponseElement[]) {
        // Proto3 JSON omits zero values, so index 0 arrives as a missing field.
        const index = element.destinationIndex ?? 0;
        if (index < 0 || index >= destinations.length) continue;
        elements[index] = parseMatrixElement(element);
      }
      return elements;
    },

    async walkingRoute(origin, destination) {
      const response = await post(ROUTES_URL, ROUTE_FIELDS, {
        origin: waypoint(origin),
        destination: waypoint(destination),
        travelMode: "WALK",
        polylineEncoding: "GEO_JSON_LINESTRING",
      }) as RoutesResponse;

      // Google answers with `{}` when no walking route exists.
      const route = response.routes?.[0];
      if (!route) return null;
      const geometry = route.polyline?.geoJsonLinestring;
      if (geometry?.type !== "LineString" || !Array.isArray(geometry.coordinates)) {
        throw new RoutesProviderError("Route is missing GeoJSON geometry");
      }
      return {
        duration_seconds: parseDuration(route.duration),
        distance_m: route.distanceMeters ?? 0,
        geometry,
      } satisfies WalkingRoute;
    },
  };
}

function parseMatrixElement(element: MatrixResponseElement): MatrixElement {
  if (element.status?.code) return { status: "provider_error" };
  if (element.condition !== "ROUTE_EXISTS") return { status: "no_route" };
  return {
    status: "ok",
    duration_seconds: parseDuration(element.duration),
    distance_m: element.distanceMeters ?? 0,
  };
}

// Durations arrive as protobuf Duration strings such as "754s".
function parseDuration(value: string | undefined): number {
  const seconds = Number.parseFloat(value ?? "");
  if (!Number.isFinite(seconds)) throw new RoutesProviderError(`Invalid duration: ${value}`);
  return Math.round(seconds);
}

function waypoint(point: Origin) {
  return { location: { latLng: { latitude: point.latitude, longitude: point.longitude } } };
}
