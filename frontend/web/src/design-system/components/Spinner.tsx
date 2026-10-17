import styles from './Spinner.module.css'

/** Decorative progress indicator; always pair it with a text status. */
export function Spinner() {
  return <span className={styles.spinner} aria-hidden="true" />
}

/** Spinner with a visible status text, e.g. while a panel loads. */
export function LoadingText({ children }: { children: string }) {
  return (
    <p className={styles.loading} role="status">
      <Spinner />
      {children}
    </p>
  )
}
