import { restGet } from '@/shared/lib/supabase'
import { toSchedule, type HoursFields } from '../lib/schedule'
import type { Aed, DataStatus, OperationalStatus, PublicAccess } from '../models/aed'

// Supabase tables `aeds` (active rows) and `app_data` key `status`, read with the publishable key.

type AedRow = HoursFields & {
  id: string
  object_name: string
  full_address: string
  lon: number
  lat: number
  in_building: boolean
  floor: number | null
  access_instructions: string | null
  public_access: PublicAccess
  operational_status: OperationalStatus
  hours_text: string | null
}

type StatusDoc = { aed_count: number; updated_at: string; attribution: string }

const AED_COLUMNS =
  'id,object_name,full_address,lon,lat,in_building,floor,access_instructions,public_access,operational_status,hours_text,hours_status,hours_verified,hours'

const toAed = (row: AedRow): Aed => ({
  id: row.id,
  location: { lng: row.lon, lat: row.lat },
  venueName: row.object_name,
  address: row.full_address,
  entrance: row.access_instructions,
  indoor: row.in_building,
  floor: row.floor,
  publicAccess: row.public_access,
  operationalStatus: row.operational_status,
  schedule: toSchedule(row),
  sourceHours: row.hours_text,
})

let aedsRequest: Promise<Aed[]> | null = null

export function fetchAeds(): Promise<Aed[]> {
  // shortcut: one request; PostgREST caps a response at 1000 rows by default, paginate if Warsaw ever has more AEDs.
  aedsRequest ??= restGet<AedRow[]>(`aeds?select=${AED_COLUMNS}&active=eq.true`)
    .then((rows) => rows.map(toAed))
    .catch((error: unknown) => {
      aedsRequest = null
      throw error
    })
  return aedsRequest
}

export async function fetchDataStatus(): Promise<DataStatus> {
  const [row] = await restGet<{ data: StatusDoc }[]>('app_data?select=data&key=eq.status')
  if (!row) throw new Error('status_missing')
  return { fetchedAt: row.data.updated_at, aedCount: row.data.aed_count, attribution: row.data.attribution }
}
