// Production wiring for the Edge Functions (Deno runtime).

import { createFixtureEvaluator, createFixtureRepository, FIXTURE_AEDS } from "./fixtures.ts";
import { createMapboxRoutesProvider } from "./mapbox_routes.ts";
import { createSupabaseEvaluator, createSupabaseRepository } from "./supabase_repository.ts";
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
  const accessToken = requireEnv("MAPBOX_ACCESS_TOKEN");

  // DEFIWAWA_USE_FIXTURES=1 serves the fake AEDs from fixtures.ts instead of the database.
  const useFixtures = Deno.env.get("DEFIWAWA_USE_FIXTURES") === "1";
  // SUPABASE_URL and SUPABASE_ANON_KEY are provided by the Edge Functions runtime.
  const supabase = useFixtures ? null : {
    url: requireEnv("SUPABASE_URL"),
    anonKey: requireEnv("SUPABASE_ANON_KEY"),
  };

  return {
    repo: supabase ? createSupabaseRepository(supabase) : createFixtureRepository(FIXTURE_AEDS),
    availability: supabase ? createSupabaseEvaluator(supabase) : createFixtureEvaluator(FIXTURE_AEDS),
    routes: createMapboxRoutesProvider({ accessToken }),
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
