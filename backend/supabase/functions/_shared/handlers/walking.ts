// POST /api/v1/routes/walking — walking route to one selected AED.
// Manually selected AEDs with uncertain or closed access are still routed,
// but marked ineligible for automatic selection.

import { ApiError, postEndpoint } from "../http.ts";
import {
  aedView,
  arrivalWarnings,
  arrivalWindow,
  availabilityView,
  isEligibleAtArrival,
} from "../eligibility.ts";
import { assertInsideWarsaw, parseAedId, parseOrigin, requireObject } from "../validation.ts";
import { RoutesProviderError } from "../ports.ts";
import type { Deps, WalkingRoute } from "../ports.ts";

export function createWalkingHandler(deps: Deps): (req: Request) => Promise<Response> {
  return postEndpoint(deps, async (body) => {
    const input = requireObject(body);
    const origin = parseOrigin(input.origin);
    const aedId = parseAedId(input.aed_id);
    await assertInsideWarsaw(deps.repo, origin);

    const now = deps.now();
    const [records, datasetVersion] = await Promise.all([
      deps.repo.getByIds([aedId]),
      deps.repo.datasetVersion(),
    ]);
    const aed = records.find((r) => r.id === aedId);
    if (!aed) throw new ApiError(404, "aed_not_found", "AED not found.", { aed_id: aedId });

    let route: WalkingRoute | null;
    try {
      route = await deps.routes.walkingRoute(origin, aed.location);
    } catch (err) {
      if (!(err instanceof RoutesProviderError)) throw err;
      throw new ApiError(503, "routing_unavailable", "Walking routes are temporarily unavailable.");
    }
    if (!route) throw new ApiError(422, "route_not_found", "No walking route to this AED.", { aed_id: aedId });

    const window = arrivalWindow(now, route.duration_seconds, deps.config.accessBufferSeconds);
    const availability = await deps.availability.evaluate(aed.id, window.arrival, window.until);

    return {
      data: {
        aed: aedView(aed),
        geometry: route.geometry,
        distance_m: route.distance_m,
        duration_seconds: route.duration_seconds,
        steps: route.steps,
        estimated_arrival_at: window.arrival.toISOString(),
        availability_at_arrival: availabilityView(availability),
        eligible_for_automatic_selection: isEligibleAtArrival(aed, availability),
        warnings: arrivalWarnings(aed, availability),
      },
      meta: {
        dataset_version: datasetVersion,
        evaluated_at: now.toISOString(),
        access_buffer_seconds: deps.config.accessBufferSeconds,
        attribution: deps.routes.attribution,
      },
    };
  });
}
