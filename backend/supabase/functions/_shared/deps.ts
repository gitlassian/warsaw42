// Production wiring for the Edge Functions (Deno runtime).

import { createGoogleRoutesProvider } from "./google_routes.ts";
import { createFixtureEvaluator, createFixtureRepository, FIXTURE_AEDS } from "./fixtures.ts";
import type { Deps } from "./ports.ts";

export const DEFAULT_CONFIG: Deps["config"] = {
  // Product default, not a medical standard (PLAN.md §6).
  accessBufferSeconds: 120,
  allowedOrigins: [],
  // At most two matrix calls (40 elements) per find request.
  findRounds: [
    { radius_m: 2_000, limit: 20 },
    { radius_m: 5_000, limit: 20 },
  ],
};

export function buildDeps(): Deps {
  const apiKey = requireEnv("GOOGLE_ROUTES_API_KEY");

  // TODO: replace with the Supabase-backed repository and the shared availability
  // evaluator once the AED schema lands.
  if (Deno.env.get("DEFIWAWA_USE_FIXTURES") !== "1") {
    throw new Error("AED repository is not wired yet; set DEFIWAWA_USE_FIXTURES=1 for local runs");
  }

  return {
    repo: createFixtureRepository(FIXTURE_AEDS),
    availability: createFixtureEvaluator(FIXTURE_AEDS),
    routes: createGoogleRoutesProvider({ apiKey }),
    now: () => new Date(),
    config: {
      ...DEFAULT_CONFIG,
      allowedOrigins: (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((o) => o.trim()).filter(Boolean),
    },
  };
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}
