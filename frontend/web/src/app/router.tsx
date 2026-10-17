import { createBrowserRouter } from 'react-router'
import { RoutePaths } from '@/app/routePaths'
import { MapPage } from '@/features/map/presentation/pages/MapPage'

export const appRouter = createBrowserRouter([
  { path: RoutePaths.map, element: <MapPage /> },
])
