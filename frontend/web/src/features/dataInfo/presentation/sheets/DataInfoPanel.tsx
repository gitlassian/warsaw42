import { Badge } from '@/design-system/components/Badge'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { aedsStore } from '@/features/aeds/store'
import { t } from '@/i18n'
import { formatDateTime } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'

/** Data source, freshness and the meaning of each status. */
export function DataInfoPanel() {
  const dataStatus = useStore(aedsStore, (s) => s.dataStatus)

  return (
    <Stack gap={24}>
      <PanelHeader title={t('O danych')} />

      {dataStatus ? (
        <Stack gap={8}>
          <Text>{t('Dane pobrano: {time}', { time: formatDateTime(dataStatus.fetchedAt) })}</Text>
          <Text>{t('Defibrylatory w danych: {count}', { count: dataStatus.aedCount })}</Text>
          <Text tone="secondary">
            {dataStatus.attribution}. {t('Dane odświeżamy co 2 godziny.')}
          </Text>
        </Stack>
      ) : (
        <LoadingText>{t('Wczytujemy dane…')}</LoadingText>
      )}

      <Stack gap={12}>
        <Text variant="heading" as="h3">
          {t('Co oznaczają statusy')}
        </Text>
        <Badge tone="accent" icon="check_circle">
          {t('Dostępny według godzin')}
        </Badge>
        <Badge tone="neutral" icon="lock">
          {t('Teraz zamknięty')}
        </Badge>
        <Badge tone="neutral" icon="lock">
          {t('Niedostępny: brak informacji o godzinach lub dostępie')}
        </Badge>
        <Badge tone="warning" icon="warning">
          {t('Dostęp niepotwierdzony')}
        </Badge>
        <Badge tone="danger" icon="error">
          {t('AED niedostępny')}
        </Badge>
        <Text tone="secondary">
          {t(
            'Status opisuje dostęp według godzin podanych w źródle. Nie potwierdza, że urządzenie działa. Pobranie danych nie oznacza kontroli urządzenia.',
          )}
        </Text>
      </Stack>

      <Text variant="meta" tone="muted">
        {t('Mapa © Mapbox © OpenStreetMap. Granica miasta © OpenStreetMap contributors (ODbL).')}
      </Text>
    </Stack>
  )
}
