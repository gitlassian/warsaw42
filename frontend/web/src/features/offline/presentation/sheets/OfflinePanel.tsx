import { RoutePaths } from '@/app/routePaths'
import { Notice } from '@/design-system/components/Notice'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { useSafeBack } from '@/shared/hooks/useSafeBack'

/** On web, "Mapa offline" explains the mobile capability; downloads live in the mobile app (DESIGN.md §6). */
export function OfflinePanel() {
  const back = useSafeBack(RoutePaths.map)
  return (
    <Stack gap={24}>
      <PanelHeader title="Mapa offline" onBack={back} />
      <Notice icon="download" title="Pobieranie map jest dostępne w aplikacji mobilnej.">
        Aplikacja mobilna DefiWawa jest w przygotowaniu.
      </Notice>
      <Stack gap={8}>
        <Text variant="heading" as="h3">
          Co działa bez internetu
        </Text>
        <ul>
          <Text as="li">Mapa Warszawy lub wybranej dzielnicy.</Text>
          <Text as="li">Lokalizacje defibrylatorów, godziny dostępu i informacje o wejściu.</Text>
          <Text as="li">Odległość w linii prostej do najbliższych AED.</Text>
        </ul>
      </Stack>
      <Text tone="secondary">
        Bez internetu nie wyznaczymy trasy pieszej, a dostępność mogła się zmienić od czasu pobrania danych.
      </Text>
    </Stack>
  )
}
