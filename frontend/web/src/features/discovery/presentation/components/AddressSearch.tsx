import { useEffect, useId, useState, type KeyboardEvent } from 'react'
import { useNavigate } from 'react-router'
import { buildPath } from '@/app/routePaths'
import symbol from '@/assets/brand/defiwawa-symbol.svg'
import { Button } from '@/design-system/components/Button'
import { IconButton } from '@/design-system/components/IconButton'
import type { AddressHit, FindResult } from '../../models/routing'
import { searchAddresses } from '../../services/geocodingApi'
import { findFrom, findFromAddress, startPicking } from '../../store'
import styles from './AddressSearch.module.css'
import { t } from '@/i18n'

const MIN_LENGTH = 3
const DEBOUNCE_MS = 300

type Lookup = { status: 'idle' | 'loading' | 'failed' } | { status: 'done'; query: string; hits: AddressHit[] }

/** Start screen: the nearest AED from a typed Warsaw address, a manual start point like one picked on the map. */
export function AddressSearch() {
  const navigate = useNavigate()
  const id = useId()
  const [query, setQuery] = useState('')
  const [lookup, setLookup] = useState<Lookup>({ status: 'idle' })
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(-1)
  // The chosen address fills the field; it is not searched again.
  const [chosen, setChosen] = useState<string | null>(null)

  const trimmed = query.trim()
  useEffect(() => {
    if (trimmed.length < MIN_LENGTH || trimmed === chosen) return
    const controller = new AbortController()
    const timer = setTimeout(() => {
      setLookup({ status: 'loading' })
      searchAddresses(trimmed, controller.signal).then(
        (hits) => {
          setLookup({ status: 'done', query: trimmed, hits })
          setActive(-1)
        },
        () => {
          if (!controller.signal.aborted) setLookup({ status: 'failed' })
        },
      )
    }, DEBOUNCE_MS)
    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [trimmed, chosen])

  const hits = lookup.status === 'done' ? lookup.hits : []
  const showList = open && trimmed.length >= MIN_LENGTH && trimmed !== chosen && lookup.status !== 'idle'

  const showResult = (result: FindResult | null) => {
    if (result?.selected) navigate(buildPath.aed(result.selected.aed.id))
  }
  const choose = (hit: AddressHit) => {
    setChosen(hit.name)
    setQuery(hit.name)
    setOpen(false)
    findFromAddress(hit.location).then(showResult)
  }
  const pickOnMap = () => {
    setOpen(false)
    startPicking((picked) => findFrom(picked).then(showResult))
  }
  const clear = () => {
    setChosen(null)
    setQuery('')
    setLookup({ status: 'idle' })
  }

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (!hits.length) return
      e.preventDefault()
      setOpen(true)
      const step = e.key === 'ArrowDown' ? 1 : -1
      setActive((i) => (i + step + hits.length) % hits.length)
    } else if (e.key === 'Enter' && showList && hits.length) {
      e.preventDefault()
      choose(hits[Math.max(active, 0)])
    } else if (e.key === 'Escape') {
      if (showList) setOpen(false)
      else clear()
    }
  }

  const listId = `${id}-list`
  return (
    <div className={styles.search}>
      <div className={styles.field}>
        {/* Like Google Maps: the brand mark sits at the start of the field, the magnifier at its end. */}
        <img src={symbol} alt="" className={styles.mark} />
        <input
          className={styles.input}
          type="search"
          role="combobox"
          aria-label={t('Adres')}
          aria-autocomplete="list"
          aria-expanded={showList}
          aria-controls={listId}
          aria-activedescendant={showList && active >= 0 ? `${id}-${active}` : undefined}
          placeholder={t('Szukaj adresu')}
          autoComplete="off"
          enterKeyHint="search"
          value={query}
          onChange={(e) => {
            setChosen(null)
            setQuery(e.target.value)
            setOpen(true)
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => setOpen(false)}
          onKeyDown={onKeyDown}
        />
        {query && <IconButton icon="close" label={t('Wyczyść adres')} onClick={clear} />}
        <IconButton
          icon="search"
          label={t('Szukaj')}
          onClick={() => (hits.length ? choose(hits[Math.max(active, 0)]) : setOpen(true))}
        />
      </div>

      {/* Mouse down on the list would blur the input and close it before the click lands. */}
      <div className={styles.results} hidden={!showList} onMouseDown={(e) => e.preventDefault()}>
        <ul id={listId} role="listbox" aria-label={t('Adresy')} className={styles.list}>
          {hits.map((hit, i) => (
            <li
              key={hit.id}
              id={`${id}-${i}`}
              role="option"
              aria-selected={i === active}
              className={styles.option}
              onClick={() => choose(hit)}
            >
              <span className={styles.name}>{hit.name}</span>
              {hit.detail && <span className={styles.detail}>{hit.detail}</span>}
            </li>
          ))}
        </ul>
        <p className={styles.message} role="status">
          {lookup.status === 'loading' && t('Szukamy…')}
          {lookup.status === 'done' && !hits.length && t('Nie znaleźliśmy tego adresu w Warszawie.')}
          {lookup.status === 'failed' && t('Nie udało się wyszukać adresu.')}
        </p>
        {(lookup.status === 'failed' || (lookup.status === 'done' && !hits.length)) && (
          <div className={styles.action}>
            <Button icon="location_on" onClick={pickOnMap}>
              {t('Wybierz punkt na mapie')}
            </Button>
          </div>
        )}
      </div>
    </div>
  )
}
