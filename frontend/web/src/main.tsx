import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider } from 'react-router/dom'
import '@fontsource/noto-sans/400.css'
import '@fontsource/noto-sans/600.css'
import '@fontsource/noto-sans/700.css'
import 'mapbox-gl/dist/mapbox-gl.css'
import { appRouter } from '@/app/router'
import '@/design-system/global.css'
import { locale, t } from '@/i18n'

// The page language follows the URL: /en/... is English.
document.documentElement.lang = locale
document.title = 'DefiWawa'
document
  .querySelector('meta[name="description"]')
  ?.setAttribute('content', t('Mapa defibrylatorów AED w Warszawie. Znajdź najbliższy dostępny AED i trasę pieszą.'))

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RouterProvider router={appRouter} />
  </StrictMode>,
)
