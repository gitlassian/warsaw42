import { buildDeps } from "../_shared/deps.ts";
import { createFindHandler } from "../_shared/handlers/find.ts";

Deno.serve(createFindHandler(buildDeps()));
