import type { ReactNode } from 'react'

type StackProps = {
  /** DESIGN.md §5: 8 between related rows, 24 between groups. */
  gap?: 4 | 8 | 12 | 16 | 24
  children: ReactNode
}

export function Stack({ gap = 8, children }: StackProps) {
  return <div style={{ display: 'flex', flexDirection: 'column', gap }}>{children}</div>
}
