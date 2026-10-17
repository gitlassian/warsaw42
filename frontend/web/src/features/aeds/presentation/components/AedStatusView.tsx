import { Badge } from '@/design-system/components/Badge'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import type { AedStatus } from '../../lib/aedStatus'

/** Access status with the next known change in hours. */
export function AedStatusView({ status }: { status: AedStatus }) {
  return (
    <Stack gap={4}>
      <Badge tone={status.tone} icon={status.icon}>
        {status.label}
      </Badge>
      {status.detail && <Text>{status.detail}</Text>}
    </Stack>
  )
}
