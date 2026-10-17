import { Badge } from '@/design-system/components/Badge'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { aedsStore } from '@/features/aeds/store'
import { formatDateTime } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'

/** Data source, freshness and the meaning of each status. */
export function DataInfoPanel() {
  const dataStatus = useStore(aedsStore, (s) => s.dataStatus)

  return (
    <Stack gap={24}>
      <PanelHeader title="O danych" />

      {dataStatus ? (
        <Stack gap={8}>
          <Text>Dane pobrano: {formatDateTime(dataStatus.fetchedAt)}</Text>
          <Text>Defibrylatory w danych: {dataStatus.aedCount}</Text>
          <Text tone="secondary">
            {dataStatus.attribution}. Dane odświeżamy co 2 godziny.
          </Text>
        </Stack>
      ) : (
        <LoadingText>Wczytujemy dane…</LoadingText>
      )}

      <Stack gap={12}>
        <Text variant="heading" as="h3">
          Co oznaczają statusy
        </Text>
        <Badge tone="accent" icon="check_circle">
          Dostępny według godzin
        </Badge>
        <Badge tone="neutral" icon="lock">
          Teraz zamknięty
        </Badge>
        <Badge tone="neutral" icon="lock">
          Niedostępny: brak informacji o godzinach lub dostępie
        </Badge>
        <Badge tone="warning" icon="warning">
          Dostęp niepotwierdzony
        </Badge>
        <Badge tone="danger" icon="error">
          AED niedostępny
        </Badge>
        <Text tone="secondary">
          Status opisuje dostęp według godzin podanych w źródle. Nie potwierdza, że urządzenie działa. Pobranie danych
          nie oznacza kontroli urządzenia.
        </Text>
      </Stack>

      <Text variant="meta" tone="muted">
        Mapa © Mapbox © OpenStreetMap. Granica miasta © OpenStreetMap contributors (ODbL).
      </Text>
    </Stack>
  )
}
