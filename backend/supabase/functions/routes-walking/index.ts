import { buildDeps } from "../_shared/deps.ts";
import { createWalkingHandler } from "../_shared/handlers/walking.ts";

Deno.serve(createWalkingHandler(buildDeps()));
