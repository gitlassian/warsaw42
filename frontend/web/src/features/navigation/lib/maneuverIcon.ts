import type { IconName } from '@/design-system/components/AppIcon'
import type { RouteStep } from '@/features/discovery/models/routing'

const TURN: Record<string, IconName> = {
  left: 'turn_left',
  right: 'turn_right',
  'slight left': 'turn_slight_left',
  'slight right': 'turn_slight_right',
  'sharp left': 'turn_sharp_left',
  'sharp right': 'turn_sharp_right',
  uturn: 'u_turn_left',
  straight: 'straight',
}

/** Arrow for a Mapbox maneuver, like the Google Maps direction banner. */
export function maneuverIcon({ maneuverType: type, maneuverModifier: modifier }: RouteStep): IconName {
  const leftish = modifier?.includes('left')
  switch (type) {
    case 'arrive':
      return 'aed'
    case 'depart':
      return 'navigation'
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
    case 'exit roundabout':
    case 'exit rotary':
      return leftish ? 'roundabout_left' : 'roundabout_right'
    case 'fork':
      return leftish ? 'fork_left' : 'fork_right'
    default:
      return (modifier && TURN[modifier]) || 'straight'
  }
}
