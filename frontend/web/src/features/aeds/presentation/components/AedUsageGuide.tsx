import { AppIcon } from '@/design-system/components/AppIcon'
import { Text } from '@/design-system/components/Text'
import styles from './AedGuide.module.css'

// Basic life support with an AED, following the European Resuscitation Council guidelines.
const STEPS: { title: string; detail: string }[] = [
  {
    title: 'Sprawdź, czy oddycha',
    detail: 'Jeśli poszkodowany nie reaguje i nie oddycha prawidłowo, działaj od razu.',
  },
  {
    title: 'Zadzwoń pod 112',
    detail: 'Włącz głośnik. Jeśli ktoś jest obok, niech przyniesie AED, a Ty zostań przy poszkodowanym.',
  },
  {
    title: 'Uciskaj klatkę piersiową',
    detail: 'Środek klatki, na głębokość 5–6 cm, 100–120 razy na minutę. Nie przerywaj, dopóki AED nie jest gotowy.',
  },
  {
    title: 'Włącz AED',
    detail: 'Otwórz pokrywę lub naciśnij przycisk zasilania. Urządzenie mówi, co robić: wykonuj jego polecenia.',
  },
  {
    title: 'Naklej elektrody',
    detail: 'Na odsłoniętą, suchą klatkę: pod prawym obojczykiem i na lewym boku pod pachą, jak na rysunku.',
  },
  {
    title: 'Nie dotykaj podczas analizy',
    detail: 'Odsuń wszystkich. Jeśli AED zaleci wyładowanie, upewnij się, że nikt nie dotyka poszkodowanego, i naciśnij przycisk.',
  },
  {
    title: 'Wróć do uciskania',
    detail: 'Zaraz po wyładowaniu lub komunikacie AED. Kontynuuj do przyjazdu pogotowia.',
  },
]

type AedUsageGuideProps = {
  /** Off inside a disclosure that already names the section. */
  withHeading?: boolean
}

/** Emergency steps for using an AED, with a call button for 112. */
export function AedUsageGuide({ withHeading = true }: AedUsageGuideProps) {
  return (
    <section className={styles.guide} aria-label={withHeading ? undefined : 'Jak użyć defibrylatora'}>
      {withHeading && (
        <Text variant="heading" as="h3">
          Jak użyć defibrylatora
        </Text>
      )}
      <a href="tel:112" className={styles.call}>
        <AppIcon name="call" />
        <span>Zadzwoń pod 112</span>
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
        Według wytycznych Europejskiej Rady Resuscytacji. AED nie wyładuje się, jeśli nie jest to potrzebne.
      </Text>
    </section>
  )
}
