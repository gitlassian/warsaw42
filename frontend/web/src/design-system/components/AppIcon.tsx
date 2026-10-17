import type { CSSProperties } from 'react'
import arrowBendDownLeft from '@phosphor-icons/core/bold/arrow-bend-down-left-bold.svg'
import arrowBendDownRight from '@phosphor-icons/core/bold/arrow-bend-down-right-bold.svg'
import arrowBendUpLeft from '@phosphor-icons/core/bold/arrow-bend-up-left-bold.svg'
import arrowBendUpRight from '@phosphor-icons/core/bold/arrow-bend-up-right-bold.svg'
import arrowClockwise from '@phosphor-icons/core/bold/arrow-clockwise-bold.svg'
import arrowCounterClockwise from '@phosphor-icons/core/bold/arrow-counter-clockwise-bold.svg'
import arrowUDownLeft from '@phosphor-icons/core/bold/arrow-u-down-left-bold.svg'
import arrowUDownRight from '@phosphor-icons/core/bold/arrow-u-down-right-bold.svg'
import arrowUp from '@phosphor-icons/core/bold/arrow-up-bold.svg'
import arrowUpLeft from '@phosphor-icons/core/bold/arrow-up-left-bold.svg'
import arrowUpRight from '@phosphor-icons/core/bold/arrow-up-right-bold.svg'
import caretDown from '@phosphor-icons/core/bold/caret-down-bold.svg'
import caretLeft from '@phosphor-icons/core/bold/caret-left-bold.svg'
import caretRight from '@phosphor-icons/core/bold/caret-right-bold.svg'
import checkCircle from '@phosphor-icons/core/bold/check-circle-bold.svg'
import circlesThree from '@phosphor-icons/core/bold/circles-three-bold.svg'
import clock from '@phosphor-icons/core/bold/clock-bold.svg'
import dotsThree from '@phosphor-icons/core/bold/dots-three-bold.svg'
import doorOpen from '@phosphor-icons/core/bold/door-open-bold.svg'
import downloadSimple from '@phosphor-icons/core/bold/download-simple-bold.svg'
import flag from '@phosphor-icons/core/bold/flag-bold.svg'
import flagCheckered from '@phosphor-icons/core/bold/flag-checkered-bold.svg'
import funnelSimple from '@phosphor-icons/core/bold/funnel-simple-bold.svg'
import gpsFix from '@phosphor-icons/core/bold/gps-fix-bold.svg'
import heartbeat from '@phosphor-icons/core/bold/heartbeat-bold.svg'
import info from '@phosphor-icons/core/bold/info-bold.svg'
import listBullets from '@phosphor-icons/core/bold/list-bullets-bold.svg'
import lockSimple from '@phosphor-icons/core/bold/lock-simple-bold.svg'
import magnifyingGlass from '@phosphor-icons/core/bold/magnifying-glass-bold.svg'
import mapPin from '@phosphor-icons/core/bold/map-pin-bold.svg'
import navigationArrow from '@phosphor-icons/core/bold/navigation-arrow-bold.svg'
import path from '@phosphor-icons/core/bold/path-bold.svg'
import personSimpleWalk from '@phosphor-icons/core/bold/person-simple-walk-bold.svg'
import phone from '@phosphor-icons/core/bold/phone-bold.svg'
import question from '@phosphor-icons/core/bold/question-bold.svg'
import stairs from '@phosphor-icons/core/bold/stairs-bold.svg'
import warning from '@phosphor-icons/core/bold/warning-bold.svg'
import warningCircle from '@phosphor-icons/core/bold/warning-circle-bold.svg'
import wifiSlash from '@phosphor-icons/core/bold/wifi-slash-bold.svg'
import x from '@phosphor-icons/core/bold/x-bold.svg'
import circlesThreeFill from '@phosphor-icons/core/fill/circles-three-fill.svg'
import clockFill from '@phosphor-icons/core/fill/clock-fill.svg'
import funnelSimpleFill from '@phosphor-icons/core/fill/funnel-simple-fill.svg'
import infoFill from '@phosphor-icons/core/fill/info-fill.svg'
import googleMaps from '@/assets/brand/google-maps.svg'
import styles from './AppIcon.module.css'

// Phosphor Icons, bold weight (DESIGN.md §4), bundled as local SVGs so they work offline.
// App names stay stable; only the glyphs behind them change. `google_maps` is the Simple Icons logo (CC0).
const ICONS = {
  aed: heartbeat,
  call: phone,
  check_circle: checkCircle,
  chevron_left: caretLeft,
  chevron_right: caretRight,
  close: x,
  directions_walk: personSimpleWalk,
  door_front: doorOpen,
  download: downloadSimple,
  error: warningCircle,
  expand_more: caretDown,
  filter_list: funnelSimple,
  flag,
  fork_left: arrowUpLeft,
  fork_right: arrowUpRight,
  google_maps: googleMaps,
  help: question,
  info,
  layers: circlesThree,
  list: listBullets,
  location_on: mapPin,
  lock: lockSimple,
  more: dotsThree,
  my_location: gpsFix,
  navigation: navigationArrow,
  near_me: navigationArrow,
  roundabout_left: arrowCounterClockwise,
  roundabout_right: arrowClockwise,
  route: path,
  schedule: clock,
  search: magnifyingGlass,
  sports_score: flagCheckered,
  stairs,
  straight: arrowUp,
  turn_left: arrowBendUpLeft,
  turn_right: arrowBendUpRight,
  turn_sharp_left: arrowBendDownLeft,
  turn_sharp_right: arrowBendDownRight,
  turn_slight_left: arrowUpLeft,
  turn_slight_right: arrowUpRight,
  u_turn_left: arrowUDownLeft,
  u_turn_right: arrowUDownRight,
  warning,
  wifi_off: wifiSlash,
} as const

/** Filled glyphs for the switched-on state of toggle controls. */
const FILLED: Partial<Record<keyof typeof ICONS, string>> = {
  info: infoFill,
  layers: circlesThreeFill,
  schedule: clockFill,
  filter_list: funnelSimpleFill,
}

export type IconName = keyof typeof ICONS

type AppIconProps = {
  name: IconName
  size?: 16 | 20 | 24 | 32 | 40
  /** Accessible name; omit for decorative icons next to a text label. */
  label?: string
  /** Switched-on state: the filled glyph when there is one. */
  filled?: boolean
}

export function AppIcon({ name, size = 24, label, filled }: AppIconProps) {
  const src = (filled && FILLED[name]) || ICONS[name]
  return (
    <span
      className={styles.icon}
      style={{ '--icon': `url("${src}")`, '--size': `${size}px` } as CSSProperties}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    />
  )
}
