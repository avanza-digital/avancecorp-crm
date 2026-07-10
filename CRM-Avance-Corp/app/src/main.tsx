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

instalarLimpiezaCacheAutenticacion()
instalarSentry() // no-op sin VITE_SENTRY_DSN (y el chunk ni se descarga)

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <StoreProvider>
          <App />
        </StoreProvider>
      </AuthProvider>
    </QueryClientProvider>
    {/* Sin richColors: sonner pintaría los success de verde; el chrome es navy/azul. */}
    <Toaster
      position="top-right"
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
