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
import { MOCK_OTP_CODE } from '../../services/reportApi'
import {
  confirmAndSubmit,
  editDraft,
  getFlow,
  reportStore,
  resendCode,
  resetFlow,
  sendCode,
  updateDraft,
} from '../../store'

const ERROR_MESSAGES: Record<string, string> = {
  otp_invalid: 'Nieprawidłowy kod. Spróbuj ponownie.',
  otp_expired: 'Kod wygasł. Wyślij nowy.',
  rate_limited: 'Nowy kod można wysłać za chwilę.',
  network: 'Nie udało się połączyć. Zgłoszenie jest zachowane, spróbuj ponownie.',
}
const errorMessage = (code: string) => ERROR_MESSAGES[code] ?? ERROR_MESSAGES.network

/** "Zgłoś problem" (DESIGN.md §9): form, SMS code, confirmation. No login or profile. */
export function ReportPanel() {
  const { id = '' } = useParams()
  const back = useSafeBack(buildPath.aed(id))
  const aed = useStore(aedsStore, (s) => s.byId.get(id))
  const flow = useStore(reportStore, (s) => s.flows[id]) ?? getFlow(id)
  const [fieldErrors, setFieldErrors] = useState<DraftErrors>({})
  const [code, setCode] = useState('')
  const { draft, challenge, busy, error } = flow

  const setField = <K extends keyof typeof draft>(field: K, value: (typeof draft)[K]) => {
    updateDraft(id, { [field]: value })
    setFieldErrors((e) => ({ ...e, [field]: undefined }))
  }

  const onSendCode = (e: SubmitEvent) => {
    e.preventDefault()
    if (busy) return
    const errors = validateDraft(draft)
    setFieldErrors(errors)
    if (Object.keys(errors).length === 0) sendCode(id)
  }

  const onConfirm = (e: SubmitEvent) => {
    e.preventDefault()
    if (!busy) confirmAndSubmit(id, code)
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
        <form onSubmit={onSendCode} noValidate>
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
            <TextField
              type="tel"
              label="Numer telefonu"
              hint="Potwierdzimy zgłoszenie kodem SMS."
              inputMode="tel"
              autoComplete="tel"
              value={draft.phone}
              onChange={(value) => setField('phone', value)}
              error={fieldErrors.phone}
            />
            {error && <Notice tone="danger" title={errorMessage(error)} />}
            <Button type="submit" variant="primary" loading={busy} loadingLabel="Wysyłamy kod…">
              Wyślij kod SMS
            </Button>
          </Stack>
        </form>
      )}

      {flow.step === 'verify' && challenge && (
        <form onSubmit={onConfirm} noValidate>
          <Stack gap={24}>
            <Stack gap={4}>
              <Text>Wysłaliśmy kod SMS na numer {challenge.maskedPhone}.</Text>
              <div>
                <Button variant="link" onClick={() => editDraft(id)}>
                  Zmień numer lub opis
                </Button>
              </div>
            </Stack>
            {/* Mock-only hint; remove with the real SMS provider. */}
            <Notice title="Wersja testowa">Kod SMS: {MOCK_OTP_CODE}</Notice>
            <TextField
              label="Kod SMS"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={challenge.codeLength}
              value={code}
              onChange={(value) => setCode(value.replace(/\D/g, ''))}
              error={error ? errorMessage(error) : undefined}
              autoFocus
            />
            <Button type="submit" variant="primary" loading={busy} loadingLabel="Sprawdzamy kod…" disabled={!code}>
              Potwierdź i wyślij
            </Button>
            <ResendCode resendAt={challenge.resendAt} busy={busy} onResend={() => resendCode(id)} />
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

/** Resend button with the remaining cooldown; mounts with the verify step, so its clock starts fresh. */
function ResendCode({ resendAt, busy, onResend }: { resendAt: number; busy: boolean; onResend: () => void }) {
  const [now, setNow] = useState(Date.now)
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])
  const seconds = Math.ceil((resendAt - now) / 1000)
  return seconds > 0 ? (
    <Text variant="meta" tone="secondary">
      Nowy kod możesz wysłać za {seconds} s.
    </Text>
  ) : (
    <Button onClick={onResend} disabled={busy}>
      Wyślij kod ponownie
    </Button>
  )
}
