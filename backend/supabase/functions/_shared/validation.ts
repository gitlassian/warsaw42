import { ApiError } from "./http.ts";
import type { AedRepository, Origin } from "./ports.ts";

const AED_ID_PATTERN = /^[\w.:-]{1,128}$/;
const MAX_ETA_IDS = 20;

export function requireObject(body: unknown): Record<string, unknown> {
  if (!isRecord(body)) throw invalid("body", "Request body must be a JSON object.");
  return body;
}

export function parseOrigin(value: unknown, field = "origin"): Origin {
  if (!isRecord(value)) throw invalid(field, `${field} must be an object with latitude and longitude.`);
  const { latitude, longitude } = value;
  if (!isFiniteNumber(latitude) || latitude < -90 || latitude > 90) {
    throw invalid(`${field}.latitude`, "latitude must be a finite number between -90 and 90.");
  }
  if (!isFiniteNumber(longitude) || longitude < -180 || longitude > 180) {
    throw invalid(`${field}.longitude`, "longitude must be a finite number between -180 and 180.");
  }
  return { latitude, longitude };
}

export function parseAedId(value: unknown, field = "aed_id"): string {
  if (typeof value !== "string" || !AED_ID_PATTERN.test(value)) {
    throw invalid(field, `${field} must be a valid AED id.`);
  }
  return value;
}

export function parseAedIds(value: unknown): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_ETA_IDS) {
    throw invalid("aed_ids", `aed_ids must contain 1–${MAX_ETA_IDS} ids.`);
  }
  const ids = value.map((id, i) => parseAedId(id, `aed_ids[${i}]`));
  if (new Set(ids).size !== ids.length) throw invalid("aed_ids", "aed_ids must be unique.");
  return ids;
}

export function parseOptionalInt(
  value: unknown,
  field: string,
  bounds: { min: number; max: number; fallback: number },
): number {
  if (value === undefined || value === null) return bounds.fallback;
  if (!Number.isInteger(value) || (value as number) < bounds.min || (value as number) > bounds.max) {
    throw invalid(field, `${field} must be an integer between ${bounds.min} and ${bounds.max}.`);
  }
  return value as number;
}

export async function assertInsideWarsaw(repo: AedRepository, origin: Origin): Promise<void> {
  if (!(await repo.isInsideWarsaw(origin))) {
    throw new ApiError(422, "outside_service_area", "Origin is outside Warsaw.", { field: "origin" });
  }
}

function invalid(field: string, message: string): ApiError {
  return new ApiError(422, "invalid_input", message, { field });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}
