import { generatePath } from 'react-router'

export const RoutePaths = {
  map: '/',
  aeds: '/aeds',
  aed: '/aed/:id',
  navigate: '/aed/:id/navigate',
  report: '/report/:id',
  coverage: '/coverage',
  data: '/data',
} as const

export const buildPath = {
  aed: (id: string) => generatePath(RoutePaths.aed, { id }),
  navigate: (id: string) => generatePath(RoutePaths.navigate, { id }),
  report: (id: string) => generatePath(RoutePaths.report, { id }),
}
