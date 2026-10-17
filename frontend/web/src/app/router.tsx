import { Navigate, createBrowserRouter } from 'react-router'
import { RoutePaths } from '@/app/routePaths'
import type { SheetSnap } from '@/design-system/components/Sheet'
import { CoveragePanel } from '@/features/coverage/presentation/sheets/CoveragePanel'
import { DataInfoPanel } from '@/features/dataInfo/presentation/sheets/DataInfoPanel'
import { AedDetailsPanel } from '@/features/discovery/presentation/sheets/AedDetailsPanel'
import { NearbyListPanel } from '@/features/discovery/presentation/sheets/NearbyListPanel'
import { StartPanel } from '@/features/discovery/presentation/sheets/StartPanel'
import { NavigationPanel } from '@/features/navigation/presentation/sheets/NavigationPanel'
import { MapPage } from '@/features/map/presentation/pages/MapPage'
import { ReportPanel } from '@/features/report/presentation/sheets/ReportPanel'

export type RouteHandle = {
  /** Initial bottom-sheet height on narrow screens. */
  sheet?: SheetSnap
  /** The panel renders location problems itself; otherwise the map overlay does. */
  showsLocationIssue?: boolean
  /** A white card over the map (bottom on narrow, bottom-right on wide) instead of the sheet / side panel. */
  floating?: boolean
  /**
   * Close button back to the start screen. `selection`: the selected AED (sheet corner on narrow screens,
   * header on wide ones), closing also clears its route. `panel`: header close button on wide screens only.
   */
  close?: 'selection' | 'panel'
  /** Turn-by-turn mode: the direction banner replaces the header and the find button is hidden. */
  navigation?: boolean
}

const handle = (h: RouteHandle) => h

export const appRouter = createBrowserRouter([
  {
    path: RoutePaths.map,
    element: <MapPage />,
    children: [
      { index: true, element: <StartPanel />, handle: handle({ floating: true, showsLocationIssue: true }) },
      { path: RoutePaths.aeds, element: <NearbyListPanel />, handle: handle({ sheet: 'medium', showsLocationIssue: true }) },
      { path: RoutePaths.aed, element: <AedDetailsPanel />, handle: handle({ sheet: 'medium', showsLocationIssue: true, close: 'selection' }) },
      { path: RoutePaths.navigate, element: <NavigationPanel />, handle: handle({ sheet: 'compact', navigation: true }) },
      { path: RoutePaths.report, element: <ReportPanel />, handle: handle({ sheet: 'expanded', close: 'selection' }) },
      { path: RoutePaths.coverage, element: <CoveragePanel />, handle: handle({ sheet: 'compact', close: 'panel' }) },
      { path: RoutePaths.data, element: <DataInfoPanel />, handle: handle({ sheet: 'medium', close: 'panel' }) },
      { path: '*', element: <Navigate to={RoutePaths.map} replace /> },
    ],
  },
])
