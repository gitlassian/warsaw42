import { buildPath } from '@/app/routePaths'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { aedStatus } from '@/features/aeds/lib/aedStatus'
import type { Aed } from '@/features/aeds/models/aed'
import { AedListItem } from '@/features/aeds/presentation/components/AedListItem'
import { distanceMeters, type LngLat } from '@/shared/geo/geo'
import type { EtaEntry } from '../../models/routing'
import { TravelTime } from './TravelTime'

type AedListProps = {
  title: string
  aeds: Aed[]
  now: Date
  etas: Record<string, EtaEntry>
  /** Without an origin the rows show no time or distance (DESIGN.md §7). */
  origin: LngLat | null
  selectedId?: string
}

/** Titled list of AED rows; selecting a row opens its card and marker. */
export function AedList({ title, aeds, now, etas, origin, selectedId }: AedListProps) {
  if (!aeds.length) return null
  return (
    <section>
      <Stack gap={4}>
        <Text variant="heading" as="h3">
          {title}
        </Text>
        <ul>
          {aeds.map((aed) => (
            <AedListItem
              key={aed.id}
              aed={aed}
              status={aedStatus(aed, now)}
              to={buildPath.aed(aed.id)}
              selected={aed.id === selectedId}
              travel={
                origin && <TravelTime eta={etas[aed.id]} straightLineM={distanceMeters(origin, aed.location)} />
              }
            />
          ))}
        </ul>
      </Stack>
    </section>
  )
}
