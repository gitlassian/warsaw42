import { AppIcon } from '@/design-system/components/AppIcon'
import { Text } from '@/design-system/components/Text'
import styles from './AedGuide.module.css'
import { t } from '@/i18n'

// Basic life support with an AED, following the European Resuscitation Council guidelines.
const STEPS: { title: string; detail: string }[] = [
  {
    title: t('Sprawdź, czy oddycha'),
    detail: t('Jeśli poszkodowany nie reaguje i nie oddycha prawidłowo, działaj od razu.'),
  },
  {
    title: t('Zadzwoń pod 112'),
    detail: t('Włącz głośnik. Jeśli ktoś jest obok, niech przyniesie AED, a Ty zostań przy poszkodowanym.'),
  },
  {
    title: t('Uciskaj klatkę piersiową'),
    detail: t('Środek klatki, na głębokość 5–6 cm, 100–120 razy na minutę. Nie przerywaj, dopóki AED nie jest gotowy.'),
  },
  {
    title: t('Włącz AED'),
    detail: t('Otwórz pokrywę lub naciśnij przycisk zasilania. Urządzenie mówi, co robić: wykonuj jego polecenia.'),
  },
  {
    title: t('Naklej elektrody'),
    detail: t('Na odsłoniętą, suchą klatkę: pod prawym obojczykiem i na lewym boku pod pachą, jak na rysunku.'),
  },
  {
    title: t('Nie dotykaj podczas analizy'),
    detail: t('Odsuń wszystkich. Jeśli AED zaleci wyładowanie, upewnij się, że nikt nie dotyka poszkodowanego, i naciśnij przycisk.'),
  },
  {
    title: t('Wróć do uciskania'),
    detail: t('Zaraz po wyładowaniu lub komunikacie AED. Kontynuuj do przyjazdu pogotowia.'),
  },
]

type AedUsageGuideProps = {
  /** Off inside a disclosure that already names the section. */
  withHeading?: boolean
}

/** Emergency steps for using an AED, with a call button for 112. */
export function AedUsageGuide({ withHeading = true }: AedUsageGuideProps) {
  return (
    <section className={styles.guide} aria-label={withHeading ? undefined : t('Jak użyć defibrylatora')}>
      {withHeading && (
        <Text variant="heading" as="h3">
          {t('Jak użyć defibrylatora')}
        </Text>
      )}
      <a href="tel:112" className={styles.call}>
        <AppIcon name="call" />
        <span>{t('Zadzwoń pod 112')}</span>
      </a>
      <ol className={styles.steps}>
        {STEPS.map((step) => (
          <li key={step.title} className={styles.step}>
            <span className={styles.title}>{step.title}</span>
            <span className={styles.detail}>{step.detail}</span>
          </li>
        ))}
      </ol>
      <Text variant="meta" tone="muted">
        {t('Według wytycznych Europejskiej Rady Resuscytacji. AED nie wyładuje się, jeśli nie jest to potrzebne.')}
      </Text>
    </section>
  )
}
