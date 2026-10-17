import type { CSSProperties } from 'react'
import call from '@material-symbols/svg-500/rounded/call.svg'
import checkCircle from '@material-symbols/svg-500/rounded/check_circle.svg'
import chevronLeft from '@material-symbols/svg-500/rounded/chevron_left.svg'
import chevronRight from '@material-symbols/svg-500/rounded/chevron_right.svg'
import close from '@material-symbols/svg-500/rounded/close.svg'
import directionsWalk from '@material-symbols/svg-500/rounded/directions_walk.svg'
import doorFront from '@material-symbols/svg-500/rounded/door_front.svg'
import download from '@material-symbols/svg-500/rounded/download.svg'
import ecgHeart from '@material-symbols/svg-500/rounded/ecg_heart.svg'
import error from '@material-symbols/svg-500/rounded/error.svg'
import filterList from '@material-symbols/svg-500/rounded/filter_list.svg'
import flag from '@material-symbols/svg-500/rounded/flag.svg'
import forkLeft from '@material-symbols/svg-500/rounded/fork_left.svg'
import forkRight from '@material-symbols/svg-500/rounded/fork_right.svg'
import help from '@material-symbols/svg-500/rounded/help.svg'
import info from '@material-symbols/svg-500/rounded/info.svg'
import expandMore from '@material-symbols/svg-500/rounded/keyboard_arrow_down.svg'
import layers from '@material-symbols/svg-500/rounded/layers.svg'
import list from '@material-symbols/svg-500/rounded/list.svg'
import locationOn from '@material-symbols/svg-500/rounded/location_on.svg'
import lock from '@material-symbols/svg-500/rounded/lock.svg'
import menu from '@material-symbols/svg-500/rounded/menu.svg'
import myLocation from '@material-symbols/svg-500/rounded/my_location.svg'
import navigation from '@material-symbols/svg-500/rounded/navigation.svg'
import nearMe from '@material-symbols/svg-500/rounded/near_me.svg'
import roundaboutLeft from '@material-symbols/svg-500/rounded/roundabout_left.svg'
import roundaboutRight from '@material-symbols/svg-500/rounded/roundabout_right.svg'
import route from '@material-symbols/svg-500/rounded/route.svg'
import schedule from '@material-symbols/svg-500/rounded/schedule.svg'
import sportsScore from '@material-symbols/svg-500/rounded/sports_score.svg'
import stairs from '@material-symbols/svg-500/rounded/stairs.svg'
import straight from '@material-symbols/svg-500/rounded/straight.svg'
import turnLeft from '@material-symbols/svg-500/rounded/turn_left.svg'
import turnRight from '@material-symbols/svg-500/rounded/turn_right.svg'
import turnSharpLeft from '@material-symbols/svg-500/rounded/turn_sharp_left.svg'
import turnSharpRight from '@material-symbols/svg-500/rounded/turn_sharp_right.svg'
import turnSlightLeft from '@material-symbols/svg-500/rounded/turn_slight_left.svg'
import turnSlightRight from '@material-symbols/svg-500/rounded/turn_slight_right.svg'
import uTurnLeft from '@material-symbols/svg-500/rounded/u_turn_left.svg'
import uTurnRight from '@material-symbols/svg-500/rounded/u_turn_right.svg'
import warning from '@material-symbols/svg-500/rounded/warning.svg'
import wifiOff from '@material-symbols/svg-500/rounded/wifi_off.svg'
import googleMaps from '@/assets/brand/google-maps.svg'
import styles from './AppIcon.module.css'

// Material Symbols Rounded, wght 500, FILL 0 (DESIGN.md §4), bundled as local SVGs.
// `heart_bolt` is not in the published set, so the AED icon is `ecg_heart`.
// `google_maps` is the Simple Icons logo (CC0), masked like the rest.
const ICONS = {
  aed: ecgHeart,
  call,
  check_circle: checkCircle,
  chevron_left: chevronLeft,
  chevron_right: chevronRight,
  close,
  directions_walk: directionsWalk,
  door_front: doorFront,
  download,
  error,
  expand_more: expandMore,
  filter_list: filterList,
  flag,
  fork_left: forkLeft,
  fork_right: forkRight,
  google_maps: googleMaps,
  help,
  info,
  layers,
  list,
  location_on: locationOn,
  lock,
  menu,
  my_location: myLocation,
  navigation,
  near_me: nearMe,
  roundabout_left: roundaboutLeft,
  roundabout_right: roundaboutRight,
  route,
  schedule,
  sports_score: sportsScore,
  stairs,
  straight,
  turn_left: turnLeft,
  turn_right: turnRight,
  turn_sharp_left: turnSharpLeft,
  turn_sharp_right: turnSharpRight,
  turn_slight_left: turnSlightLeft,
  turn_slight_right: turnSlightRight,
  u_turn_left: uTurnLeft,
  u_turn_right: uTurnRight,
  warning,
  wifi_off: wifiOff,
} as const

export type IconName = keyof typeof ICONS

type AppIconProps = {
  name: IconName
  size?: 16 | 20 | 24 | 32 | 40
  /** Accessible name; omit for decorative icons next to a text label. */
  label?: string
}

export function AppIcon({ name, size = 24, label }: AppIconProps) {
  return (
    <span
      className={styles.icon}
      style={{ '--icon': `url("${ICONS[name]}")`, '--size': `${size}px` } as CSSProperties}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    />
  )
}
