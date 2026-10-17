import { ApiError } from './apiError'

// Public project URL and publishable key; Row Level Security decides what they can read or write.
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL as string
const PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: { apikey: PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
  })
  const body = await response.json().catch(() => null)
  // Edge Functions answer `{ error: { code } }`, PostgREST `{ code }`.
  if (!response.ok) throw new ApiError(body?.error?.code ?? body?.code ?? `http_${response.status}`)
  return body as T
}

/** PostgREST read, e.g. `aeds?select=id&active=eq.true`. */
export const restGet = <T>(query: string) => request<T>(`/rest/v1/${query}`)

/** Edge Function call (routing functions answer `{ data, meta }`). */
export const callFunction = <T>(name: string, body: unknown) =>
  request<T>(`/functions/v1/${name}`, { method: 'POST', body: JSON.stringify(body) })
