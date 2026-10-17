import { useEffect, useState, type SubmitEvent } from 'react'
import { useParams } from 'react-router'
import { buildPath } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { ChoiceGroup } from '@/design-system/components/ChoiceGroup'
import { Notice } from '@/design-system/components/Notice'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { TextField } from '@/design-system/components/TextField'
import { aedsStore } from '@/features/aeds/store'
import { useSafeBack } from '@/shared/hooks/useSafeBack'
import { useStore } from '@/shared/lib/store'
import { DESCRIPTION_MAX, REPORT_CATEGORIES, validateDraft, type DraftErrors } from '../../models/report'
import { getFlow, openFlow, reportStore, resetFlow, submit, updateDraft } from '../../store'

const ERROR_MESSAGES: Record<string, string> = {
  rate_limited: 'Wysłano zbyt wiele zgłoszeń. Spróbuj ponownie później.',
  aed_not_found: 'Tego AED nie można już zgłosić. Mógł zostać usunięty z bazy.',
  network: 'Nie udało się połączyć. Zgłoszenie jest zachowane, spróbuj ponownie.',
}
const errorMessage = (code: string) => ERROR_MESSAGES[code] ?? ERROR_MESSAGES.network

/** "Zgłoś problem" (DESIGN.md §9): form, confirmation. No login or profile. */
export function ReportPanel() {
  const { id = '' } = useParams()
  const back = useSafeBack(buildPath.aed(id))
  const aed = useStore(aedsStore, (s) => s.byId.get(id))
  const flow = useStore(reportStore, (s) => s.flows[id]) ?? getFlow(id)
  const [fieldErrors, setFieldErrors] = useState<DraftErrors>({})
  const [honeypot, setHoneypot] = useState('')
  const { draft, busy, error } = flow

  useEffect(() => openFlow(id), [id])

  const setField = <K extends keyof typeof draft>(field: K, value: (typeof draft)[K]) => {
    updateDraft(id, { [field]: value })
    setFieldErrors((e) => ({ ...e, [field]: undefined }))
  }

  const onSubmit = (e: SubmitEvent) => {
    e.preventDefault()
    if (busy) return
    const errors = validateDraft(draft)
    setFieldErrors(errors)
    if (Object.keys(errors).length === 0) submit(id, honeypot)
  }

  return (
    <Stack gap={24}>
      <Stack gap={4}>
        <PanelHeader title="Zgłoś problem" onBack={back} />
        {aed && (
          <Text tone="secondary">
            {aed.venueName}, {aed.address}
          </Text>
        )}
      </Stack>

      {flow.step === 'form' && (
        <form onSubmit={onSubmit} noValidate>
          <Stack gap={24}>
            <ChoiceGroup
              legend="Rodzaj problemu"
              options={REPORT_CATEGORIES}
              value={draft.category}
              onChange={(value) => setField('category', value)}
              error={fieldErrors.category}
            />
            <TextField
              multiline
              label="Opis"
              hint="Co się stało? Np. szafka jest zamknięta albo godziny są inne."
              value={draft.description}
              onChange={(value) => setField('description', value)}
              maxLength={DESCRIPTION_MAX}
              error={fieldErrors.description}
            />
            {/* Honeypot: hidden from people and assistive technology, filled in by naive bots. */}
            <div className="visually-hidden" aria-hidden="true">
              <label>
                Strona internetowa
                <input
                  type="text"
                  name="homepage"
                  tabIndex={-1}
                  autoComplete="off"
                  value={honeypot}
                  onChange={(e) => setHoneypot(e.target.value)}
                />
              </label>
            </div>
            {error && <Notice tone="danger" title={errorMessage(error)} />}
            <Button type="submit" variant="primary" loading={busy} loadingLabel="Wysyłamy zgłoszenie…">
              Wyślij zgłoszenie
            </Button>
          </Stack>
        </form>
      )}

      {flow.step === 'done' && (
        <Stack gap={16}>
          <Notice tone="accent" title="Dziękujemy. Zgłoszenie czeka na sprawdzenie.">
            Zgłoszenie nie zmienia od razu statusu defibrylatora.
          </Notice>
          <ButtonLink variant="primary" to={buildPath.aed(id)} onClick={() => resetFlow(id)}>
            Wróć do AED
          </ButtonLink>
        </Stack>
      )}
    </Stack>
  )
}
