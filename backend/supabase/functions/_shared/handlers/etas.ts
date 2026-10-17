// POST /api/v1/routes/etas — walking times for visible AED markers.

import { postEndpoint } from "../http.ts";
import { arrivalWindow, availabilityView, walkingMatrixOrErrors } from "../eligibility.ts";
import { assertInsideWarsaw, parseAedIds, parseOrigin, requireObject } from "../validation.ts";
import type { Deps } from "../ports.ts";

type EtaStatus = "ok" | "no_route" | "not_found" | "provider_error";

export function createEtasHandler(deps: Deps): (req: Request) => Promise<Response> {
  return postEndpoint(deps, async (body) => {
    const input = requireObject(body);
    const origin = parseOrigin(input.origin);
    const aedIds = parseAedIds(input.aed_ids);
    await assertInsideWarsaw(deps.repo, origin);

    const now = deps.now();
    const [records, datasetVersion] = await Promise.all([
      deps.repo.getByIds(aedIds),
      deps.repo.datasetVersion(),
    ]);
    const known = records.filter((r) => aedIds.includes(r.id));
    const elements = await walkingMatrixOrErrors(deps.routes, origin, known.map((r) => r.location));
    const elementById = new Map(known.map((r, i) => [r.id, elements[i]]));

    const data = await Promise.all(aedIds.map(async (id) => {
      const element = elementById.get(id);
      if (!element) return failedEta(id, "not_found");
      if (element.status !== "ok") return failedEta(id, element.status);

      const window = arrivalWindow(now, element.duration_seconds, deps.config.accessBufferSeconds);
      const availability = await deps.availability.evaluate(id, window.arrival, window.until);
      return {
        aed_id: id,
        status: "ok" as EtaStatus,
        duration_seconds: element.duration_seconds,
        distance_m: element.distance_m,
        estimated_arrival_at: window.arrival.toISOString(),
        availability_at_arrival: availabilityView(availability),
      };
    }));

    return {
      data,
      meta: {
        dataset_version: datasetVersion,
        evaluated_at: now.toISOString(),
        access_buffer_seconds: deps.config.accessBufferSeconds,
        attribution: deps.routes.attribution,
      },
    };
  });
}

function failedEta(id: string, status: EtaStatus) {
  return {
    aed_id: id,
    status,
    duration_seconds: null,
    distance_m: null,
    estimated_arrival_at: null,
    availability_at_arrival: null,
  };
}
