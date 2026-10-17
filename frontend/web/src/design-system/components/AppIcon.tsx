import type { CSSProperties } from 'react'
import arrowBack from '@material-symbols/svg-500/rounded/arrow_back.svg'
import checkCircle from '@material-symbols/svg-500/rounded/check_circle.svg'
import close from '@material-symbols/svg-500/rounded/close.svg'
import directionsWalk from '@material-symbols/svg-500/rounded/directions_walk.svg'
import download from '@material-symbols/svg-500/rounded/download.svg'
import ecgHeart from '@material-symbols/svg-500/rounded/ecg_heart.svg'
import error from '@material-symbols/svg-500/rounded/error.svg'
import expandMore from '@material-symbols/svg-500/rounded/keyboard_arrow_down.svg'
import filterList from '@material-symbols/svg-500/rounded/filter_list.svg'
import flag from '@material-symbols/svg-500/rounded/flag.svg'
import help from '@material-symbols/svg-500/rounded/help.svg'
import info from '@material-symbols/svg-500/rounded/info.svg'
import layers from '@material-symbols/svg-500/rounded/layers.svg'
import list from '@material-symbols/svg-500/rounded/list.svg'
import locationOn from '@material-symbols/svg-500/rounded/location_on.svg'
import lock from '@material-symbols/svg-500/rounded/lock.svg'
import menu from '@material-symbols/svg-500/rounded/menu.svg'
import myLocation from '@material-symbols/svg-500/rounded/my_location.svg'
import route from '@material-symbols/svg-500/rounded/route.svg'
import schedule from '@material-symbols/svg-500/rounded/schedule.svg'
import warning from '@material-symbols/svg-500/rounded/warning.svg'
import wifiOff from '@material-symbols/svg-500/rounded/wifi_off.svg'
import styles from './AppIcon.module.css'

// Material Symbols Rounded, wght 500, FILL 0 (DESIGN.md §4), bundled as local SVGs.
// `heart_bolt` is not in the published set, so the AED icon is `ecg_heart`.
const ICONS = {
  aed: ecgHeart,
  arrow_back: arrowBack,
  check_circle: checkCircle,
  close,
  directions_walk: directionsWalk,
  download,
  error,
  expand_more: expandMore,
  filter_list: filterList,
  flag,
  help,
  info,
  layers,
  list,
  location_on: locationOn,
  lock,
  menu,
  my_location: myLocation,
  route,
  schedule,
  warning,
  wifi_off: wifiOff,
} as const

export type IconName = keyof typeof ICONS

type AppIconProps = {
  name: IconName
  size?: 16 | 20 | 24 | 32
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
