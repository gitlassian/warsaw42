// TEST DATA ONLY. In-memory stand-ins for Yarik's AED repository and availability
// evaluator, used by tests and by local runs with DEFIWAWA_USE_FIXTURES=1.
// The weekly evaluator here is deliberately simple (no date exceptions, holidays,
// or cross-midnight windows); the real one lives with the database work.

import type {
  AedRecord,
  AedRepository,
  AvailabilityEvaluator,
  AvailabilityResult,
  Candidate,
  Origin,
} from "./ports.ts";

type DaySchedule = { state: "open_intervals" | "closed" | "unknown"; intervals: [string, string][] };

export type FixtureSchedule =
  | { kind: "always_open" }
  | { kind: "weekly"; weekly: Record<string, DaySchedule> };

export type FixtureAed = AedRecord & { schedule: FixtureSchedule | null };

// Rough Warsaw bounding box; the real check uses the administrative boundary in PostGIS.
const WARSAW_BBOX = { west: 20.85, south: 52.09, east: 21.28, north: 52.37 };

export function createFixtureRepository(aeds: FixtureAed[], datasetVersion = "fixture-1"): AedRepository {
  return {
    datasetVersion: () => Promise.resolve(datasetVersion),

    isInsideWarsaw: (o) =>
      Promise.resolve(
        o.longitude >= WARSAW_BBOX.west && o.longitude <= WARSAW_BBOX.east &&
          o.latitude >= WARSAW_BBOX.south && o.latitude <= WARSAW_BBOX.north,
      ),

    getByIds: (ids) => Promise.resolve(aeds.filter((a) => ids.includes(a.id)).map(stripSchedule)),

    findCandidates: ({ origin, radius_m, limit, exclude_ids }) =>
      Promise.resolve(
        aeds
          .filter((a) => !exclude_ids.includes(a.id))
          .map((a): Candidate => ({
            ...stripSchedule(a),
            straight_line_distance_m: Math.round(haversineMeters(origin, a.location)),
          }))
          .filter((c) => c.straight_line_distance_m <= radius_m)
          .sort((a, b) => a.straight_line_distance_m - b.straight_line_distance_m)
          .slice(0, limit),
      ),
  };
}

export function createFixtureEvaluator(aeds: FixtureAed[]): AvailabilityEvaluator {
  const schedules = new Map(aeds.map((a) => [a.id, a.schedule]));
  return {
    evaluate: (aedId, from, until) => Promise.resolve(evaluateSchedule(schedules.get(aedId) ?? null, from, until)),
  };
}

function evaluateSchedule(schedule: FixtureSchedule | null, from: Date, until: Date): AvailabilityResult {
  if (!schedule) return { status: "unknown", covers_interval: false, reasons: ["no_schedule"] };
  if (schedule.kind === "always_open") return { status: "open", covers_interval: true, reasons: ["always_open"] };

  const start = warsawParts(from);
  const end = warsawParts(until);
  const day = schedule.weekly[String(start.weekday)];
  if (!day || day.state === "unknown") return { status: "unknown", covers_interval: false, reasons: ["day_unknown"] };
  if (day.state === "closed") return { status: "closed", covers_interval: false, reasons: ["day_closed"] };

  // Opening boundary inclusive, closing boundary exclusive.
  const interval = day.intervals
    .map(([open, close]) => [toMinutes(open), toMinutes(close)])
    .find(([open, close]) => start.minutes >= open && start.minutes < close);
  if (!interval) return { status: "closed", covers_interval: false, reasons: ["outside_hours"] };
  const covers = start.date === end.date && end.minutes <= interval[1];
  return { status: "open", covers_interval: covers, reasons: ["weekly_hours"] };
}

const warsawFormat = new Intl.DateTimeFormat("en-GB", {
  timeZone: "Europe/Warsaw",
  weekday: "short",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
});
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

function warsawParts(date: Date): { weekday: number; date: string; minutes: number } {
  const parts = Object.fromEntries(warsawFormat.formatToParts(date).map((p) => [p.type, p.value]));
  return {
    weekday: WEEKDAYS.indexOf(parts.weekday) + 1,
    date: `${parts.year}-${parts.month}-${parts.day}`,
    minutes: Number(parts.hour) * 60 + Number(parts.minute) + Number(parts.second) / 60,
  };
}

function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

function stripSchedule({ schedule: _schedule, ...record }: FixtureAed): AedRecord {
  return record;
}

export function haversineMeters(a: Origin, b: Origin): number {
  const R = 6_371_000;
  const rad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = rad(b.latitude - a.latitude);
  const dLon = rad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

const WEEKDAY_8_TO_16: DaySchedule = { state: "open_intervals", intervals: [["08:00", "16:00"]] };
const UNKNOWN_DAY: DaySchedule = { state: "unknown", intervals: [] };

function fixture(
  id: string,
  latitude: number,
  longitude: number,
  schedule: FixtureSchedule | null,
  overrides: Partial<AedRecord> = {},
): FixtureAed {
  return {
    id,
    source_id: `fixture-${id}`,
    location: { latitude, longitude },
    venue_name: `Fixture venue ${id}`,
    address: null,
    access_instructions: null,
    public_access: "public",
    operational_status: "unknown",
    active: true,
    schedule,
    ...overrides,
  };
}

// Clearly fake AEDs around central Warsaw. The first one reuses the coordinates and
// hours of the sample record from PLAN.md §4–5.
export const FIXTURE_AEDS: FixtureAed[] = [
  fixture("fx-sample", 52.2086170695684, 21.0148748892902, {
    kind: "weekly",
    weekly: {
      "1": { state: "open_intervals", intervals: [["08:00", "18:00"]] },
      "2": WEEKDAY_8_TO_16,
      "3": WEEKDAY_8_TO_16,
      "4": WEEKDAY_8_TO_16,
      "5": WEEKDAY_8_TO_16,
      "6": UNKNOWN_DAY,
      "7": UNKNOWN_DAY,
    },
  }),
  fixture("fx-centrum-247", 52.2297, 21.0122, { kind: "always_open" }),
  fixture("fx-restricted", 52.2150, 21.0200, { kind: "always_open" }, { public_access: "restricted" }),
  fixture("fx-unknown-hours", 52.2100, 21.0100, null),
  fixture("fx-inactive", 52.2090, 21.0150, { kind: "always_open" }, { active: false }),
  fixture("fx-broken", 52.2095, 21.0140, { kind: "always_open" }, { operational_status: "confirmed_unavailable" }),
  fixture("fx-praga-247", 52.2520, 21.0440, { kind: "always_open" }),
];
