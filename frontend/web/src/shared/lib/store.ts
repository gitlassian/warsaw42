import { useSyncExternalStore } from 'react'

export type Store<T> = {
  get: () => T
  set: (patch: Partial<T> | ((state: T) => Partial<T>)) => void
  subscribe: (listener: () => void) => () => void
}

/** Minimal observable store; feature state lives in `features/<name>/store.ts`. */
export function createStore<T extends object>(initial: T): Store<T> {
  let state = initial
  const listeners = new Set<() => void>()
  return {
    get: () => state,
    set: (patch) => {
      state = { ...state, ...(typeof patch === 'function' ? patch(state) : patch) }
      listeners.forEach((listener) => listener())
    },
    subscribe: (listener) => {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
  }
}

/** The selector must return existing references (a field, not a new object). */
export function useStore<T extends object, S>(store: Store<T>, selector: (state: T) => S): S {
  return useSyncExternalStore(store.subscribe, () => selector(store.get()))
}
