import { AppIcon, type IconName } from '@/design-system/components/AppIcon'
import { Text } from '@/design-system/components/Text'
import { placementLabel } from '../../lib/aedStatus'
import type { Aed } from '../../models/aed'
import { AedPhoto } from './AedPhoto'
import styles from './AedGuide.module.css'
import { t } from '@/i18n'

/** On-site directions to the cabinet: place, entrance, floor, access and photo. */
export function AedFindingGuide({ aed }: { aed: Aed }) {
  const rows: { icon: IconName; text: string }[] = [
    { icon: 'location_on', text: `${aed.venueName}, ${aed.address}` },
    { icon: 'door_front', text: aed.entrance ?? t('Źródło nie opisuje wejścia. Zapytaj obsługę lub ochronę budynku.') },
    { icon: 'stairs', text: placementLabel(aed) },
  ]
  if (aed.publicAccess !== 'public') {
    rows.push({ icon: 'lock', text: t('Dostęp może wymagać pomocy obsługi lub ochrony budynku.') })
  }

  return (
    <section className={styles.guide}>
      <Text variant="heading" as="h3">
        {t('Jak znaleźć urządzenie')}
      </Text>
      <AedPhoto aed={aed} />
      <ul className={styles.facts}>
        {rows.map((row) => (
          <li key={row.icon} className={styles.fact}>
            <AppIcon name={row.icon} size={20} />
            <span>{row.text}</span>
          </li>
        ))}
      </ul>
      <Text variant="meta" tone="secondary">
        {t('Szukaj zielonego znaku AED z sercem i błyskawicą. Szafka zwykle wisi przy wejściu, recepcji lub windach.')}
      </Text>
    </section>
  )
}
