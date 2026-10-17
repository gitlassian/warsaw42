// POST /api/v1/aeds/find — "Znajdź defibrylator".
// Picks the fastest-to-reach AED among the evaluated nearby candidates that is
// expected to be open from arrival through the access buffer (PLAN.md §6).

import { postEndpoint } from "../http.ts";
import {
  accessWarning,
  aedView,
  arrivalWindow,
  availabilityView,
  exclusionReason,
  isEligibleAtArrival,
} from "../eligibility.ts";
import { assertInsideWarsaw, parseOptionalInt, parseOrigin, requireObject } from "../validation.ts";
import { RoutesProviderError } from "../ports.ts";
import type { AvailabilityResult, Candidate, Deps, Origin, WalkingRoute } from "../ports.ts";

const MAX_UNKNOWN_ALTERNATIVES = 5;

type Routed = {
  aed: Candidate;
  duration_seconds: number;
  distance_m: number;
  arrival: Date;
  availability: AvailabilityResult;
};

type UnknownAlternative = { aed: Candidate; reason: string };

type Screened = { routable: Candidate } | { unknown: UnknownAlternative } | null;

export function createFindHandler(deps: Deps): (req: Request) => Promise<Response> {
  return postEndpoint(deps, async (body) => {
    const input = requireObject(body);
    const origin = parseOrigin(input.origin);
    const maxResults = parseOptionalInt(input.max_results, "max_results", { min: 1, max: 5, fallback: 3 });
    await assertInsideWarsaw(deps.repo, origin);

    const now = deps.now();
    const datasetVersion = await deps.repo.datasetVersion();
    const seen = new Set<string>();
    const eligible: Routed[] = [];
    const unknown: UnknownAlternative[] = [];
    let unroutable: Candidate[] = [];
    let evaluatedCount = 0;
    let searchedRadius = 0;
    let budgetExhausted = true;

    // Each round widens the search; stop at the first round that yields an eligible AED.
    for (const round of deps.config.findRounds) {
      const candidates = await deps.repo.findCandidates({
        origin,
        radius_m: round.radius_m,
        limit: round.limit,
        exclude_ids: [...seen],
      });
      searchedRadius = round.radius_m;
      for (const c of candidates) seen.add(c.id);

      const screened = await Promise.all(candidates.map((c) => screen(deps, c, now)));
      const routable: Candidate[] = [];
      for (const s of screened) {
        if (s && "routable" in s) routable.push(s.routable);
        if (s && "unknown" in s) unknown.push(s.unknown);
      }
      if (routable.length === 0) continue;

      let elements;
      try {
        elements = await deps.routes.walkingMatrix(origin, routable.map((c) => c.location));
      } catch (err) {
        if (!(err instanceof RoutesProviderError)) throw err;
        unroutable = routable;
        budgetExhausted = false;
        break;
      }
      evaluatedCount += routable.length;

      await Promise.all(routable.map(async (aed, i) => {
        const element = elements[i];
        if (element.status !== "ok") return;
        const window = arrivalWindow(now, element.duration_seconds, deps.config.accessBufferSeconds);
        const availability = await deps.availability.evaluate(aed.id, window.arrival, window.until);
        if (isEligibleAtArrival(aed, availability)) {
          eligible.push({ aed, ...element, arrival: window.arrival, availability });
        } else if (availability.status === "unknown") {
          unknown.push({ aed, reason: "hours_unknown_at_arrival" });
        }
      }));

      if (eligible.length > 0) {
        budgetExhausted = false;
        break;
      }
    }

    eligible.sort((a, b) => a.duration_seconds - b.duration_seconds || a.distance_m - b.distance_m);
    const top = eligible.slice(0, maxResults);
    const warnings: string[] = [];
    let status: "found" | "no_eligible_aed" | "routing_unavailable";
    let selected = null;
    let alternatives: unknown[] = [];

    if (top.length > 0) {
      status = "found";
      const [first, ...rest] = top;
      const route = await routeOrNull(deps, origin, first.aed.location);
      if (!route) warnings.push("route_geometry_unavailable");
      selected = {
        ...routedView(first),
        route: route && {
          geometry: route.geometry,
          distance_m: route.distance_m,
          duration_seconds: route.duration_seconds,
        },
      };
      alternatives = rest.map(routedView);
    } else if (unroutable.length > 0) {
      // Walking times are unknown: offer the nearest open AEDs by straight-line
      // distance, without presenting them as routes or ETAs.
      status = "routing_unavailable";
      warnings.push("walking_times_unavailable");
      alternatives = unroutable
        .sort(byStraightLine)
        .slice(0, maxResults)
        .map((aed) => ({ aed: aedView(aed), walking: null, availability_at_arrival: null }));
    } else {
      status = "no_eligible_aed";
    }

    return {
      data: {
        status,
        selected,
        alternatives,
        unknown_access_alternatives: unknown
          .sort((a, b) => byStraightLine(a.aed, b.aed))
          .slice(0, MAX_UNKNOWN_ALTERNATIVES)
          .map((u) => ({ aed: aedView(u.aed), reason: u.reason })),
        warnings,
      },
      meta: {
        dataset_version: datasetVersion,
        evaluated_at: now.toISOString(),
        access_buffer_seconds: deps.config.accessBufferSeconds,
        attribution: deps.routes.attribution,
        search: {
          evaluated_count: evaluatedCount,
          searched_radius_m: searchedRadius,
          budget_exhausted: budgetExhausted,
          ranking_scope: "evaluated_nearby_candidates",
        },
      },
    };
  });
}

// Drops unusable or currently closed AEDs before spending routing calls on them.
async function screen(deps: Deps, aed: Candidate, now: Date): Promise<Screened> {
  if (exclusionReason(aed)) return null;
  const access = accessWarning(aed);
  if (access) return { unknown: { aed, reason: access } };
  const current = await deps.availability.evaluate(aed.id, now, now);
  if (current.status === "closed") return null;
  if (current.status === "unknown") return { unknown: { aed, reason: "hours_unknown" } };
  return { routable: aed };
}

async function routeOrNull(deps: Deps, origin: Origin, destination: Origin): Promise<WalkingRoute | null> {
  try {
    return await deps.routes.walkingRoute(origin, destination);
  } catch (err) {
    if (!(err instanceof RoutesProviderError)) throw err;
    return null;
  }
}

function routedView(r: Routed) {
  return {
    aed: aedView(r.aed),
    walking: {
      duration_seconds: r.duration_seconds,
      distance_m: r.distance_m,
      estimated_arrival_at: r.arrival.toISOString(),
    },
    availability_at_arrival: availabilityView(r.availability),
  };
}

function byStraightLine(a: Candidate, b: Candidate): number {
  return a.straight_line_distance_m - b.straight_line_distance_m;
}
