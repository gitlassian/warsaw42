import { useState } from 'react'
import type { Aed } from '../../models/aed'
import styles from './AedGuide.module.css'
import { t } from '@/i18n'

/** Photo of the cabinet's surroundings; nothing when the AED has none or it fails to load. */
export function AedPhoto({ aed }: { aed: Aed }) {
  // A row can name a photo the bucket does not hold yet; hide it instead of a broken image.
  const [failedPhoto, setFailedPhoto] = useState<string | null>(null)
  if (!aed.photoUrl || aed.photoUrl === failedPhoto) return null
  return (
    <img
      className={styles.photo}
      src={aed.photoUrl}
      alt={t('Miejsce defibrylatora: {name}', { name: aed.venueName })}
      loading="lazy"
      onError={() => setFailedPhoto(aed.photoUrl ?? null)}
    />
  )
}
