import { buildDeps } from "../_shared/deps.ts";
import { createEtasHandler } from "../_shared/handlers/etas.ts";

Deno.serve(createEtasHandler(buildDeps()));
