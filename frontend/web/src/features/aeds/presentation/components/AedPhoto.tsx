import { useState } from 'react'
import type { Aed } from '../../models/aed'
import styles from './AedGuide.module.css'

/** Photo of the cabinet's surroundings; nothing when the AED has none or it fails to load. */
export function AedPhoto({ aed }: { aed: Aed }) {
  // A row can name a photo the bucket does not hold yet; hide it instead of a broken image.
  const [failedPhoto, setFailedPhoto] = useState<string | null>(null)
  if (!aed.photoUrl || aed.photoUrl === failedPhoto) return null
  return (
    <img
      className={styles.photo}
      src={aed.photoUrl}
      alt={`Miejsce defibrylatora: ${aed.venueName}`}
      loading="lazy"
      onError={() => setFailedPhoto(aed.photoUrl ?? null)}
    />
  )
}
