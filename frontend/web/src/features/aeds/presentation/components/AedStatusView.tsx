import { Stack } from '@/design-system/components/Stack'
import { StatusText } from '@/design-system/components/StatusText'
import { Text } from '@/design-system/components/Text'
import type { AedStatus } from '../../lib/aedStatus'

/** Access status with the next known change in hours. */
export function AedStatusView({ status }: { status: AedStatus }) {
  return (
    <Stack gap={4}>
      <StatusText tone={status.tone}>{status.label}</StatusText>
      {status.detail && <Text>{status.detail}</Text>}
    </Stack>
  )
}
