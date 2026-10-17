import { generatePath } from 'react-router'

export const RoutePaths = {
  map: '/',
  aeds: '/aeds',
  aed: '/aed/:id',
  report: '/report/:id',
  coverage: '/coverage',
  data: '/data',
} as const

export const buildPath = {
  aed: (id: string) => generatePath(RoutePaths.aed, { id }),
  report: (id: string) => generatePath(RoutePaths.report, { id }),
}
