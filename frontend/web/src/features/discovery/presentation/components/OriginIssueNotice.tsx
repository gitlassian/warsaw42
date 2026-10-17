import { Button } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import type { LocationIssue } from '../../models/routing'

const MESSAGES: Record<Exclude<LocationIssue, 'outside_pick'>, { title: string; text: string }> = {
  denied: {
    title: 'Nie możemy ustalić Twojej lokalizacji.',
    text: 'Dostęp do lokalizacji jest wyłączony. Możesz wybrać punkt startowy na mapie.',
  },
  unavailable: {
    title: 'Nie możemy ustalić Twojej lokalizacji.',
    text: 'Sprawdź, czy lokalizacja jest włączona w ustawieniach urządzenia, i spróbuj ponownie. Możesz też wybrać punkt startowy na mapie.',
  },
  insecure: {
    title: 'Lokalizacja wymaga bezpiecznego połączenia.',
    text: 'Przeglądarka udostępnia lokalizację tylko stronom HTTPS. Wybierz punkt startowy na mapie.',
  },
  outside: {
    title: 'Aplikacja obejmuje Warszawę.',
    text: 'Twoja lokalizacja jest poza miastem. Wybierz punkt startowy w Warszawie.',
  },
}

type OriginIssueNoticeProps = {
  issue: LocationIssue
  onPick: () => void
  /** Shown for a failed fix, which often succeeds on a second try. */
  onRetry?: () => void
}

/** Location problem with the manual-origin fallback (DESIGN.md §8). */
export function OriginIssueNotice({ issue, onPick, onRetry }: OriginIssueNoticeProps) {
  if (issue === 'outside_pick') return null
  const { title, text } = MESSAGES[issue]
  return (
    <Notice
      tone="warning"
      title={title}
      actions={
        <>
          {issue === 'unavailable' && onRetry && (
            <Button icon="my_location" onClick={onRetry}>
              Spróbuj ponownie
            </Button>
          )}
          <Button icon="location_on" onClick={onPick}>
            Wybierz punkt na mapie
          </Button>
        </>
      }
    >
      {text}
    </Notice>
  )
}
