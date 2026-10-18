import { restGet, supabaseEnabled } from '@/shared/lib/supabase'
import type { PlacementData } from '../models/placement'

// GET app_data `placement` from the database (written by backend/pipeline/placement.py through the seed); without
// Supabase the same document is read from the mock copy in public/mock/placement.json.
export async function fetchPlacement(): Promise<PlacementData> {
  if (supabaseEnabled) {
    const [row] = await restGet<{ data: PlacementData }[]>('app_data?key=eq.placement&select=data')
    if (!row) throw new Error('app_data placement missing')
    return row.data
  }
  const response = await fetch('/mock/placement.json')
  if (!response.ok) throw new Error(`placement ${response.status}`)
  return response.json() as Promise<PlacementData>
}
