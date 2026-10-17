import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { Link, type LinkProps } from 'react-router'
import { AppIcon, type IconName } from './AppIcon'
import { Spinner } from './Spinner'
import styles from './Button.module.css'

type Variant = 'primary' | 'secondary' | 'link'

type CommonProps = {
  variant?: Variant
  icon?: IconName
  children: ReactNode
}

type ButtonProps = CommonProps &
  Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> & {
    /** Keeps the button size, shows the status label and ignores repeated presses. */
    loading?: boolean
    loadingLabel?: string
  }

export function Button({
  variant = 'secondary',
  icon,
  loading = false,
  loadingLabel,
  children,
  onClick,
  type = 'button',
  ...rest
}: ButtonProps) {
  return (
    <button
      {...rest}
      type={type}
      className={styles[variant]}
      aria-busy={loading || undefined}
      onClick={loading ? undefined : onClick}
    >
      {loading ? <Spinner /> : icon && <AppIcon name={icon} />}
      <span>{loading && loadingLabel ? loadingLabel : children}</span>
    </button>
  )
}

/** Navigation styled as a button. */
export function ButtonLink({ variant = 'secondary', icon, children, ...rest }: CommonProps & Omit<LinkProps, 'children'>) {
  return (
    <Link {...rest} className={styles[variant]}>
      {icon && <AppIcon name={icon} />}
      <span>{children}</span>
    </Link>
  )
}
