import { Navigate, createBrowserRouter } from 'react-router'
import { RoutePaths } from '@/app/routePaths'
import type { SheetSnap } from '@/design-system/components/Sheet'
import { CoveragePanel } from '@/features/coverage/presentation/sheets/CoveragePanel'
import { DataInfoPanel } from '@/features/dataInfo/presentation/sheets/DataInfoPanel'
import { AedDetailsPanel } from '@/features/discovery/presentation/sheets/AedDetailsPanel'
import { NearbyListPanel } from '@/features/discovery/presentation/sheets/NearbyListPanel'
import { StartPanel } from '@/features/discovery/presentation/sheets/StartPanel'
import { MapPage } from '@/features/map/presentation/pages/MapPage'
import { OfflinePanel } from '@/features/offline/presentation/sheets/OfflinePanel'
import { ReportPanel } from '@/features/report/presentation/sheets/ReportPanel'

export type RouteHandle = {
  /** Initial bottom-sheet height on narrow screens. */
  sheet?: SheetSnap
  /** The panel renders location problems itself; otherwise the map overlay does. */
  showsLocationIssue?: boolean
  /** A white card over the map (bottom on narrow, bottom-right on wide) instead of the sheet / side panel. */
  floating?: boolean
  /** The panel shows the selected AED; its close button returns to the start screen. */
  closable?: boolean
}

const handle = (h: RouteHandle) => h

export const appRouter = createBrowserRouter([
  {
    path: RoutePaths.map,
    element: <MapPage />,
    children: [
      { index: true, element: <StartPanel />, handle: handle({ floating: true, showsLocationIssue: true }) },
      { path: RoutePaths.aeds, element: <NearbyListPanel />, handle: handle({ sheet: 'medium', showsLocationIssue: true }) },
      { path: RoutePaths.aed, element: <AedDetailsPanel />, handle: handle({ sheet: 'medium', showsLocationIssue: true, closable: true }) },
      { path: RoutePaths.report, element: <ReportPanel />, handle: handle({ sheet: 'expanded', closable: true }) },
      { path: RoutePaths.coverage, element: <CoveragePanel />, handle: handle({ sheet: 'compact' }) },
      { path: RoutePaths.offline, element: <OfflinePanel />, handle: handle({ sheet: 'medium' }) },
      { path: RoutePaths.data, element: <DataInfoPanel />, handle: handle({ sheet: 'medium' }) },
      { path: '*', element: <Navigate to={RoutePaths.map} replace /> },
    ],
  },
])
