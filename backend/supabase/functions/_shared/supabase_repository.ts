// AedRepository and AvailabilityEvaluator backed by the Supabase database
// (functions and views from supabase/migrations), called through PostgREST.
// Uses the anon key: everything read here is public under RLS.

import { DataSourceError } from "./ports.ts";
import type {
  AedRecord,
  AedRepository,
  AvailabilityEvaluator,
  AvailabilityResult,
  Candidate,
} from "./ports.ts";

const DEFAULT_TIMEOUT_MS = 5_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const AED_COLUMNS = [
  "id",
  "source_id",
  "lon",
  "lat",
  "object_name",
  "full_address",
  "access_instructions",
  "public_access",
  "operational_status",
].join(",");

export type SupabaseOptions = {
  url: string;
  anonKey: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
};

type AedPublicRow = {
  id: string;
  source_id: string;
  lon: number;
  lat: number;
  object_name: string;
  full_address: string | null;
  access_instructions: string | null;
  public_access: AedRecord["public_access"];
  operational_status: AedRecord["operational_status"];
};

export function createSupabaseClient(options: SupabaseOptions) {
  const fetchImpl = options.fetch ?? fetch;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const base = `${options.url.replace(/\/$/, "")}/rest/v1`;
  const headers = {
    apikey: options.anonKey,
    Authorization: `Bearer ${options.anonKey}`,
    "Content-Type": "application/json",
  };

  async function request(path: string, init: RequestInit = {}): Promise<unknown> {
    let res: Response;
    try {
      res = await fetchImpl(`${base}${path}`, {
        ...init,
        headers,
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      throw new DataSourceError("Database request failed", { cause: err });
    }
    if (!res.ok) throw new DataSourceError(`Database responded with HTTP ${res.status} for ${path.split("?")[0]}`);
    return await res.json();
  }

  return {
    rpc: (fn: string, args: Record<string, unknown>) =>
      request(`/rpc/${fn}`, { method: "POST", body: JSON.stringify(args) }),
    select: (path: string) => request(path),
  };
}

export function createSupabaseRepository(options: SupabaseOptions): AedRepository {
  const db = createSupabaseClient(options);

  async function getByIds(ids: string[]): Promise<AedRecord[]> {
    // Our ids are uuids; anything else cannot exist and would make PostgREST reject the filter.
    const valid = ids.filter((id) => UUID.test(id));
    if (valid.length === 0) return [];
    const rows = await db.select(`/aed_public?select=${AED_COLUMNS}&id=in.(${valid.join(",")})`) as AedPublicRow[];
    return rows.map(toRecord);
  }

  return {
    async datasetVersion() {
      const version = await db.rpc("current_dataset_version", {});
      return version === null ? "unpublished" : String(version);
    },

    async isInsideWarsaw(origin) {
      return await db.rpc("is_inside_warsaw", { p_lat: origin.latitude, p_lon: origin.longitude }) === true;
    },

    getByIds,

    async findCandidates({ origin, radius_m, limit, exclude_ids }) {
      const nearby = await db.rpc("aeds_nearby", {
        p_lat: origin.latitude,
        p_lon: origin.longitude,
        p_radius_m: radius_m,
        p_limit: limit,
        p_exclude: exclude_ids.filter((id) => UUID.test(id)),
      }) as { id: string; distance_m: number }[];
      if (nearby.length === 0) return [];

      const byId = new Map((await getByIds(nearby.map((n) => n.id))).map((r) => [r.id, r]));
      // Keep the distance order from aeds_nearby; skip rows that vanished in between.
      return nearby.flatMap((n): Candidate[] => {
        const record = byId.get(n.id);
        return record ? [{ ...record, straight_line_distance_m: Math.round(n.distance_m) }] : [];
      });
    },
  };
}

export function createSupabaseEvaluator(options: SupabaseOptions): AvailabilityEvaluator {
  const db = createSupabaseClient(options);
  return {
    async evaluate(aedId, from, until) {
      const rows = await db.rpc("aed_availability", {
        p_aed_id: aedId,
        p_from: from.toISOString(),
        p_until: until.toISOString(),
      }) as AvailabilityResult[];
      return rows[0] ?? { status: "unknown", covers_interval: false, reasons: ["no_hours"] };
    },
  };
}

function toRecord(row: AedPublicRow): AedRecord {
  return {
    id: row.id,
    source_id: row.source_id,
    location: { latitude: row.lat, longitude: row.lon },
    venue_name: row.object_name,
    address: row.full_address,
    access_instructions: row.access_instructions,
    public_access: row.public_access,
    operational_status: row.operational_status,
    // aed_public only contains active (not removed) AEDs.
    active: true,
  };
}
