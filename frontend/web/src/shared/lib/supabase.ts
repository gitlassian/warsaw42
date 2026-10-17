import { ApiError } from './apiError'

/** Supabase REST, Storage and Edge Functions access without an SDK. Unset env vars keep the mock AED data active. */
const url = (import.meta.env.VITE_SUPABASE_URL as string | undefined)?.replace(/\/+$/, '')
const key = (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? import.meta.env.VITE_SUPABASE_ANON_KEY) as string | undefined

export const supabaseEnabled = Boolean(url && key)

// Legacy anon keys are JWTs and go in both headers; publishable keys (sb_publishable_…) only in `apikey`.
const headers = (): Record<string, string> =>
  key!.startsWith('eyJ') ? { apikey: key!, Authorization: `Bearer ${key}` } : { apikey: key! }

/** GET /rest/v1/<path> (PostgREST). Row-level security limits anon to active AEDs and `app_data`. */
export async function restGet<T>(path: string): Promise<T> {
  const response = await fetch(`${url}/rest/v1/${path}`, { headers: headers() })
  if (!response.ok) throw new Error(`supabase ${path.split('?')[0]} ${response.status}`)
  return response.json() as Promise<T>
}

export const storagePublicUrl = (bucket: string, file: string) => `${url}/storage/v1/object/public/${bucket}/${file}`

/** POST /functions/v1/<name>. Routing functions answer `{ data, meta }`, failures `{ error: { code } }`. */
export async function callFunction<T>(name: string, body: unknown): Promise<T> {
  const response = await fetch(`${url}/functions/v1/${name}`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const json = await response.json().catch(() => null)
  if (!response.ok) throw new ApiError(json?.error?.code ?? `http_${response.status}`)
  return json as T
}
