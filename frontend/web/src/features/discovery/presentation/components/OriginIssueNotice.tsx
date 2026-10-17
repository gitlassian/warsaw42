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
    text: 'Spróbuj ponownie albo wybierz punkt startowy na mapie.',
  },
  outside: {
    title: 'Aplikacja obejmuje Warszawę.',
    text: 'Twoja lokalizacja jest poza miastem. Wybierz punkt startowy w Warszawie.',
  },
}

type OriginIssueNoticeProps = {
  issue: LocationIssue
  onPick: () => void
}

/** Location problem with the manual-origin fallback (DESIGN.md §8). */
export function OriginIssueNotice({ issue, onPick }: OriginIssueNoticeProps) {
  if (issue === 'outside_pick') return null
  const { title, text } = MESSAGES[issue]
  return (
    <Notice
      tone="warning"
      title={title}
      actions={
        <Button icon="location_on" onClick={onPick}>
          Wybierz punkt na mapie
        </Button>
      }
    >
      {text}
    </Notice>
  )
}
