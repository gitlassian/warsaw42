import type { Deps } from "./ports.ts";

const MAX_BODY_BYTES = 16_384;

export class ApiError extends Error {
  override name = "ApiError";
  readonly status: number;
  readonly code: string;
  readonly details: Record<string, unknown>;

  constructor(status: number, code: string, message: string, details: Record<string, unknown> = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export type EndpointResult = { data: unknown; meta: Record<string, unknown> };

// Wraps a JSON POST endpoint with CORS, body parsing, the shared response envelope,
// and error mapping. Every routing response is `no-store`.
export function postEndpoint(
  deps: Pick<Deps, "now" | "config">,
  run: (body: unknown) => Promise<EndpointResult>,
): (req: Request) => Promise<Response> {
  return async (req) => {
    const requestId = crypto.randomUUID();
    const cors = corsHeaders(req, deps.config.allowedOrigins);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    try {
      if (req.method !== "POST") throw new ApiError(405, "method_not_allowed", "Use POST.");
      const body = await readJson(req);
      const { data, meta } = await run(body);
      return json(200, {
        data,
        meta: { request_id: requestId, generated_at: deps.now().toISOString(), ...meta },
      }, cors);
    } catch (err) {
      if (err instanceof ApiError) {
        return json(err.status, {
          error: { code: err.code, message: err.message, details: err.details },
          request_id: requestId,
        }, cors);
      }
      // Never log request bodies: they contain the caller's location.
      console.error(JSON.stringify({
        request_id: requestId,
        error: err instanceof Error ? `${err.name}: ${err.message}` : "unknown",
      }));
      return json(500, {
        error: { code: "internal_error", message: "Unexpected server error.", details: {} },
        request_id: requestId,
      }, cors);
    }
  };
}

async function readJson(req: Request): Promise<unknown> {
  const text = await req.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new ApiError(413, "payload_too_large", "Request body is too large.");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, "malformed_json", "Request body is not valid JSON.");
  }
}

function json(status: number, body: unknown, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...headers,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function corsHeaders(req: Request, allowedOrigins: string[]): Record<string, string> {
  const origin = req.headers.get("Origin");
  if (!origin || !allowedOrigins.includes(origin)) return { Vary: "Origin" };
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    Vary: "Origin",
  };
}
