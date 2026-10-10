import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import './index.css'
import App from './App.tsx'
import { AuthProvider } from '@/lib/auth.tsx'
import { StoreProvider } from '@/lib/store.tsx'
import { instalarLimpiezaCacheAutenticacion, queryClient } from '@/lib/query-client'
import { instalarSentry } from '@/lib/sentry'
import { VersionPublicadaAviso } from '@/components/app/version-publicada'
import { limpiarMarcaDeVersion } from '@/lib/version-publicada'

// La recarga por versión nueva llega con `?crm_version=…` (llave contra cachés).
// Se retira ANTES de montar React: el router lee una URL limpia y la llave no
// se queda pegada en la barra de direcciones ni en los enlaces que salen de ella.
limpiarMarcaDeVersion()
instalarLimpiezaCacheAutenticacion()
instalarSentry() // no-op sin VITE_SENTRY_DSN (y el chunk ni se descarga)

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <div id="app-content" className="h-full">
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <StoreProvider>
            <App />
          </StoreProvider>
        </AuthProvider>
      </QueryClientProvider>
      <VersionPublicadaAviso />
    </div>
    {/* Sin richColors: sonner pintaría los success de verde; el chrome es navy/azul. */}
    <Toaster
      position="top-right"
      // a11y: botón de cierre visible — sin él, un toast con acción (p.ej.
      // "Deshacer" del descarte) solo se despacha esperando su timeout.
      closeButton
      toastOptions={{
        style: {
          background: 'var(--card)',
          color: 'var(--card-foreground)',
          border: '1px solid var(--border)',
        },
      }}
    />
  </StrictMode>,
)
