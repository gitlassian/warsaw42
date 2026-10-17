import mapboxgl, { type GeoJSONSource, type Map as MapboxMap, type MapMouseEvent } from 'mapbox-gl'
import type { Point } from 'geojson'
import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useMatch } from 'react-router'
import { RoutePaths, buildPath } from '@/app/routePaths'
import { AppIcon } from '@/design-system/components/AppIcon'
import { passesFilters } from '@/features/aeds/lib/aedAvailability'
import { aedStatus } from '@/features/aeds/lib/aedStatus'
import { aedsStore } from '@/features/aeds/store'
import type { CoverageCell } from '@/features/coverage/models/coverage'
import { nearestSite } from '@/features/coverage/lib/coverageGeometry'
import { coverageStore, selectCoverageCell } from '@/features/coverage/store'
import { discoveryStore, pickOrigin, requestEtas } from '@/features/discovery/store'
import { headingAt, locateOnRoute } from '@/features/navigation/lib/progress'
import { navigationStore, routePlan, stopFollowing } from '@/features/navigation/store'
import { WARSAW_CENTER, WARSAW_MAX_BOUNDS, circlePolygon, type LngLat } from '@/shared/geo/geo'
import { useStore } from '@/shared/lib/store'
import { mapCamera } from '../../lib/mapCamera'
import { mapFiltersStore } from '@/features/aeds/filterStore'
import { ACCURACY_LAYER, ACCURACY_OPACITY, AEDS_LAYER, COVERAGE_HALO_LAYER, COVERAGE_LAYER, EMPTY_COLLECTION, SOURCE, addAppLayers, setSourceData } from '../../lib/mapLayers'
import { MapMarker } from './MapMarker'
import { AedMarker, ClusterMarker, HeadingMarker, OriginMarker } from './MapMarkers'
import styles from './MapView.module.css'

/** A rendered point of the clustered AED source: one AED or a cluster. */
type VisibleFeature = { key: string; lngLat: LngLat } & (
  | { aedId: string }
  | { clusterId: number; count: number; available: number }
)

const ACCURACY_VISIBLE_MS = 2500

const sameKeys = (a: VisibleFeature[], b: VisibleFeature[]) =>
  a.length === b.length && a.every((f, i) => f.key === b[i].key)

type MapViewProps = {
  onLoadError: () => void
  onLocate: () => void
  locating: boolean
}

/** Mapbox Standard (light, flat, north-up) locked to Warsaw, with AED markers, route, origin and coverage. */
export function MapView({ onLoadError, onLocate, locating }: MapViewProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  // Mapbox control group for the small location button; React renders the button into it.
  const [locateGroup] = useState(() => Object.assign(document.createElement('div'), { className: 'mapboxgl-ctrl mapboxgl-ctrl-group' }))
  const [map, setMap] = useState<MapboxMap | null>(null)
  const [visible, setVisible] = useState<VisibleFeature[]>([])

  const aeds = useStore(aedsStore, (s) => s.aeds)
  const byId = useStore(aedsStore, (s) => s.byId)
  const now = useStore(aedsStore, (s) => s.now)
  const showAvailable = useStore(mapFiltersStore, (s) => s.available)
  const showUnavailable = useStore(mapFiltersStore, (s) => s.unavailable)
  const origin = useStore(discoveryStore, (s) => s.origin)
  const etas = useStore(discoveryStore, (s) => s.etas)
  const route = useStore(discoveryStore, (s) => s.route)
  const picking = useStore(discoveryStore, (s) => s.picking)
  const coverageLayer = useStore(coverageStore, (s) => s.layer)
  const livePosition = useStore(navigationStore, (s) => s.position)
  const following = useStore(navigationStore, (s) => s.following)
  const navigatedId = useStore(navigationStore, (s) => s.aedId)

  const aedMatch = useMatch(RoutePaths.aed)
  const reportMatch = useMatch(RoutePaths.report)
  const navigateMatch = useMatch(RoutePaths.navigate)
  const showCoverage = useMatch(RoutePaths.coverage) !== null
  const selectedId = aedMatch?.params.id ?? reportMatch?.params.id ?? navigateMatch?.params.id
  const selectedAed = selectedId ? byId.get(selectedId) : undefined

  // Create the map once.
  useEffect(() => {
    let loaded = false
    let instance: MapboxMap
    try {
      instance = new mapboxgl.Map({
        container: containerRef.current!,
        accessToken: import.meta.env.VITE_MAPBOX_TOKEN,
        style: 'mapbox://styles/mapbox/standard',
        config: { basemap: { lightPreset: 'day', show3dObjects: false } },
        center: [WARSAW_CENTER.lng, WARSAW_CENTER.lat],
        zoom: 11,
        // Flat map: no tilt, no rotation.
        maxPitch: 0,
        dragRotate: false,
        touchPitch: false,
        minZoom: 10,
        maxBounds: WARSAW_MAX_BOUNDS,
        language: 'pl',
        attributionControl: false,
        locale: { 'NavigationControl.ZoomIn': 'Przybliż', 'NavigationControl.ZoomOut': 'Oddal' },
      })
      // Small zoom and location buttons in the bottom-right corner, shown on wide screens only (MapView.module.css).
      instance.addControl(new mapboxgl.NavigationControl({ showCompass: false }), 'bottom-right')
      // Added later, so Mapbox stacks it above the zoom buttons.
      instance.addControl({ onAdd: () => locateGroup, onRemove: () => locateGroup.remove() }, 'bottom-right')
      instance.touchZoomRotate.disableRotation()
      instance.keyboard.disableRotation()
    } catch {
      onLoadError()
      return
    }
    // Mapbox tracks only window resizes; the side panel appears and disappears with the route.
    const resizeObserver = new ResizeObserver(() => instance.resize())
    resizeObserver.observe(containerRef.current!)
    instance.on('error', () => {
      if (!loaded) onLoadError()
    })
    // Panning by hand stops the navigation camera from following the walker.
    instance.on('dragstart', stopFollowing)
    instance.on('load', () => {
      loaded = true
      addAppLayers(instance)
      mapCamera.attach(instance)
      setMap(instance)
    })
    return () => {
      resizeObserver.disconnect()
      mapCamera.attach(null)
      instance.remove()
    }
  }, [onLoadError, locateGroup])

  useEffect(() => {
    if (!map) return
    setSourceData(map, SOURCE.aeds, {
      type: 'FeatureCollection',
      // Filters follow the clock: an AED that closes at 16:00 leaves the map without a reload.
      features: aeds
        .filter((a) => passesFilters(a, now, { available: showAvailable, unavailable: showUnavailable }))
        .map((a) => ({
          type: 'Feature',
          properties: { id: a.id, available: aedStatus(a, now).available ? 1 : 0 },
          geometry: { type: 'Point', coordinates: [a.location.lng, a.location.lat] },
        })),
    })
  }, [map, aeds, now, showAvailable, showUnavailable])

  // Mirror the clustered source into HTML markers whenever the view or tiles change.
  useEffect(() => {
    if (!map) return
    const update = () => {
      const seen = new Map<string, VisibleFeature>()
      // Rendered features only: no duplicates from parent/child tiles, nothing off screen.
      for (const f of map.queryRenderedFeatures({ layers: [AEDS_LAYER] })) {
        const p = f.properties ?? {}
        const [lng, lat] = (f.geometry as Point).coordinates
        const feature: VisibleFeature = p.cluster
          ? { key: `c${p.cluster_id}`, lngLat: { lng, lat }, clusterId: p.cluster_id, count: p.point_count, available: p.available }
          : { key: `a${p.id}`, lngLat: { lng, lat }, aedId: String(p.id) }
        seen.set(feature.key, feature)
      }
      const next = [...seen.values()].sort((a, b) => a.key.localeCompare(b.key))
      setVisible((prev) => (sameKeys(prev, next) ? prev : next))
    }
    map.on('moveend', update)
    map.on('idle', update)
    return () => {
      map.off('moveend', update)
      map.off('idle', update)
    }
  }, [map])

  // Walking-time pills for individually visible markers, debounced and batched in the store.
  const visibleAedKey = visible.flatMap((f) => ('aedId' in f ? [f.aedId] : [])).join()
  useEffect(() => {
    if (!origin || !visibleAedKey) return
    const timer = setTimeout(() => requestEtas(visibleAedKey.split(',')), 300)
    return () => clearTimeout(timer)
  }, [origin, visibleAedKey])

  useEffect(() => {
    if (map) setSourceData(map, SOURCE.route, route ? route.geometry : EMPTY_COLLECTION)
  }, [map, route])

  // Accuracy area (DESIGN.md §12): shown for a moment after a GPS fix, then faded out, as in Google Maps.
  // Hidden while navigating, where the walker is an arrow on the route.
  useEffect(() => {
    if (!map) return
    const accuracy =
      !livePosition && origin?.source === 'gps' && origin.accuracyM ? circlePolygon(origin, origin.accuracyM) : null
    setSourceData(map, SOURCE.accuracy, accuracy ?? EMPTY_COLLECTION)
    if (!accuracy) return
    map.setPaintProperty(ACCURACY_LAYER, 'fill-opacity', ACCURACY_OPACITY)
    const timer = setTimeout(() => map.setPaintProperty(ACCURACY_LAYER, 'fill-opacity', 0), ACCURACY_VISIBLE_MS)
    return () => clearTimeout(timer)
  }, [map, origin, livePosition])

  useEffect(() => {
    if (map) setSourceData(map, SOURCE.coverage, showCoverage && coverageLayer ? coverageLayer.data : EMPTY_COLLECTION)
  }, [map, showCoverage, coverageLayer])

  useEffect(() => {
    if (!map) return
    map.getCanvas().style.cursor = picking ? 'crosshair' : ''
    const onClick = (e: MapMouseEvent) => {
      if (discoveryStore.get().picking) return pickOrigin(e.lngLat)
      const [area] = map.queryRenderedFeatures(e.point, { layers: [COVERAGE_LAYER, COVERAGE_HALO_LAYER] })
      const layer = coverageStore.get().layer
      if (!area || !layer) return selectCoverageCell(null)
      const nearest = nearestSite(e.lngLat.lng, e.lngLat.lat, layer.eligible)
      selectCoverageCell({
        kind: area.properties?.kind,
        nearestDistanceM: nearest ? Math.round(nearest.distanceM) : null,
        nearestAedId: nearest?.site.id ?? null,
      } satisfies CoverageCell)
    }
    map.on('click', onClick)
    return () => {
      map.off('click', onClick)
    }
  }, [map, picking])

  // Move the camera only after an explicit selection or a new route (DESIGN.md §12).
  // Navigation moves the camera itself (heading-up); leaving it shows the whole route again.
  const navigating = navigateMatch !== null
  useEffect(() => {
    if (!map || !selectedAed || navigating) return
    if (route?.aedId === selectedAed.id) mapCamera.fitRoute(route)
    else mapCamera.focus(selectedAed.location)
  }, [map, selectedAed, route, navigating])

  // Walking direction along the navigated route at the live position: turns the map and the arrow.
  const heading = useMemo(() => {
    if (!livePosition || !route || route.aedId !== navigatedId) return null
    const plan = routePlan(route)
    return plan.coordinates.length > 1 ? headingAt(plan, locateOnRoute(plan, livePosition).alongM) : null
  }, [livePosition, route, navigatedId])

  useEffect(() => {
    if (map && following && livePosition) mapCamera.navigate(livePosition, heading ?? map.getBearing())
  }, [map, following, livePosition, heading])

  const expandCluster = (clusterId: number, center: LngLat) =>
    map?.getSource<GeoJSONSource>(SOURCE.aeds)?.getClusterExpansionZoom(clusterId, (error, zoom) => {
      if (!error && zoom != null) map.easeTo({ center, zoom })
    })

  const renderAed = (id: string, lngLat: LngLat, key?: string) => {
    const aed = byId.get(id)
    if (!aed || !map) return null
    return (
      <MapMarker key={key} map={map} lngLat={lngLat} raised={id === selectedId}>
        <AedMarker
          aed={aed}
          status={aedStatus(aed, now)}
          to={buildPath.aed(id)}
          eta={origin ? etas[id] : undefined}
          selected={id === selectedId}
        />
      </MapMarker>
    )
  }

  return (
    <div ref={containerRef} className={styles.map} role="region" aria-label="Mapa defibrylatorów w Warszawie">
      {map &&
        visible.map((f) =>
          'clusterId' in f ? (
            <MapMarker key={f.key} map={map} lngLat={f.lngLat} anchor="center">
              <ClusterMarker count={f.count} available={f.available} onExpand={() => expandCluster(f.clusterId, f.lngLat)} />
            </MapMarker>
          ) : f.aedId === selectedId ? null : (
            renderAed(f.aedId, f.lngLat, f.key)
          ),
        )}
      {createPortal(
        <button type="button" className={styles.locate} aria-label="Pokaż moją lokalizację" title="Pokaż moją lokalizację" onClick={onLocate} disabled={locating}>
          <AppIcon name="my_location" size={20} />
        </button>,
        locateGroup,
      )}
      {/* The selected AED stays visible even inside a cluster. */}
      {map && selectedAed && renderAed(selectedAed.id, selectedAed.location)}
      {map && origin && !livePosition && (
        <MapMarker map={map} lngLat={origin} anchor={origin.source === 'gps' ? 'center' : 'bottom'}>
          <OriginMarker source={origin.source} />
        </MapMarker>
      )}
      {/* While navigating, the live position replaces the search start point. */}
      {map && livePosition && (
        <MapMarker map={map} lngLat={livePosition} anchor="center" rotation={heading ?? undefined}>
          {heading === null ? <OriginMarker source="gps" /> : <HeadingMarker />}
        </MapMarker>
      )}
    </div>
  )
}
