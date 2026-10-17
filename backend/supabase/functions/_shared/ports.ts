// Contracts between the routing endpoints and their dependencies.
// AedRepository and AvailabilityEvaluator are implemented on top of Yarik's schema;
// until then the fixture implementations in fixtures.ts stand in for them.

export type Origin = { latitude: number; longitude: number };

export type PublicAccess = "public" | "restricted" | "unknown";
export type OperationalStatus = "unknown" | "confirmed_unavailable" | "confirmed_operational";
export type Availability = "open" | "closed" | "unknown";

export type AedRecord = {
  id: string;
  source_id: string;
  location: Origin;
  venue_name: string | null;
  address: string | null;
  access_instructions: string | null;
  public_access: PublicAccess;
  operational_status: OperationalStatus;
  active: boolean;
};

export type Candidate = AedRecord & { straight_line_distance_m: number };

export type AvailabilityResult = {
  status: Availability;
  // True only when known opening hours cover the whole [from, until] window.
  covers_interval: boolean;
  reasons: string[];
};

export type CandidateQuery = {
  origin: Origin;
  radius_m: number;
  limit: number;
  exclude_ids: string[];
};

export interface AedRepository {
  datasetVersion(): Promise<string>;
  isInsideWarsaw(origin: Origin): Promise<boolean>;
  getByIds(ids: string[]): Promise<AedRecord[]>;
  // Ordered by straight-line distance from the origin.
  findCandidates(query: CandidateQuery): Promise<Candidate[]>;
}

export interface AvailabilityEvaluator {
  evaluate(aedId: string, from: Date, until: Date): Promise<AvailabilityResult>;
}

export type MatrixElement =
  | { status: "ok"; duration_seconds: number; distance_m: number }
  | { status: "no_route" }
  | { status: "provider_error" };

export type LineString = { type: "LineString"; coordinates: [number, number][] };

export type WalkingRoute = {
  duration_seconds: number;
  distance_m: number;
  geometry: LineString;
};

export interface RoutesProvider {
  readonly attribution: string;
  // One element per destination, in the same order.
  walkingMatrix(origin: Origin, destinations: Origin[]): Promise<MatrixElement[]>;
  // Resolves to null when the provider finds no walking route.
  walkingRoute(origin: Origin, destination: Origin): Promise<WalkingRoute | null>;
}

// Thrown when the routing provider is unreachable or returns an unusable response.
export class RoutesProviderError extends Error {
  override name = "RoutesProviderError";
}

// Thrown when the AED database is unreachable; the API answers 503.
export class DataSourceError extends Error {
  override name = "DataSourceError";
}

export type SearchRound = { radius_m: number; limit: number };

export type Deps = {
  repo: AedRepository;
  availability: AvailabilityEvaluator;
  routes: RoutesProvider;
  now: () => Date;
  config: {
    accessBufferSeconds: number;
    allowedOrigins: string[];
    findRounds: SearchRound[];
  };
};
