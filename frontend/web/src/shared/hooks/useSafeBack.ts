import { useLocation, useNavigate } from 'react-router'

/** Goes back in history, or to `fallback` when the page was opened directly from a link. */
export function useSafeBack(fallback: string) {
  const navigate = useNavigate()
  const location = useLocation()
  return () => (location.key === 'default' ? navigate(fallback) : navigate(-1))
}
