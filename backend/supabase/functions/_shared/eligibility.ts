import { RoutesProviderError } from "./ports.ts";
import type {
  AedRecord,
  AvailabilityResult,
  Candidate,
  MatrixElement,
  Origin,
  RoutesProvider,
} from "./ports.ts";

export type ArrivalWindow = { arrival: Date; until: Date };

// The AED must stay open from arrival through arrival + access buffer.
export function arrivalWindow(now: Date, durationSeconds: number, bufferSeconds: number): ArrivalWindow {
  const arrival = new Date(now.getTime() + durationSeconds * 1000);
  return { arrival, until: new Date(arrival.getTime() + bufferSeconds * 1000) };
}

export function exclusionReason(aed: AedRecord): "inactive" | "confirmed_unavailable" | null {
  if (!aed.active) return "inactive";
  if (aed.operational_status === "confirmed_unavailable") return "confirmed_unavailable";
  return null;
}

export function accessWarning(aed: AedRecord): "access_restricted" | "access_unknown" | null {
  if (aed.public_access === "restricted") return "access_restricted";
  if (aed.public_access === "unknown") return "access_unknown";
  return null;
}

export function isEligibleAtArrival(aed: AedRecord, availability: AvailabilityResult): boolean {
  return exclusionReason(aed) === null &&
    accessWarning(aed) === null &&
    availability.status === "open" &&
    availability.covers_interval;
}

export function arrivalWarnings(aed: AedRecord, availability: AvailabilityResult): string[] {
  const warnings: string[] = [];
  const exclusion = exclusionReason(aed);
  if (exclusion) warnings.push(exclusion);
  const access = accessWarning(aed);
  if (access) warnings.push(access);
  if (availability.status === "closed") warnings.push("closed_at_arrival");
  if (availability.status === "unknown") warnings.push("hours_unknown_at_arrival");
  if (availability.status === "open" && !availability.covers_interval) {
    warnings.push("closes_within_access_buffer");
  }
  return warnings;
}

export function availabilityView(availability: AvailabilityResult) {
  return {
    status: availability.status,
    covers_access_buffer: availability.covers_interval,
    reasons: availability.reasons,
  };
}

export function aedView(aed: AedRecord | Candidate) {
  return {
    id: aed.id,
    source_id: aed.source_id,
    location: aed.location,
    venue_name: aed.venue_name,
    address: aed.address,
    access_instructions: aed.access_instructions,
    public_access: aed.public_access,
    operational_status: aed.operational_status,
    ...("straight_line_distance_m" in aed ? { straight_line_distance_m: aed.straight_line_distance_m } : {}),
  };
}

// A failed matrix call degrades to per-entry provider errors instead of failing the request.
export async function walkingMatrixOrErrors(
  routes: RoutesProvider,
  origin: Origin,
  destinations: Origin[],
): Promise<MatrixElement[]> {
  try {
    return await routes.walkingMatrix(origin, destinations);
  } catch (err) {
    if (!(err instanceof RoutesProviderError)) throw err;
    return destinations.map(() => ({ status: "provider_error" }));
  }
}
