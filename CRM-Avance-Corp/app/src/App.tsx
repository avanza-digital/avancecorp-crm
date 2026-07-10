import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import { DatabaseZap, LogOut } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions, usePanelesState } from '@/lib/store-context'
import { can } from '@/lib/roles'
import { escribirHash, leerHash, type Vista } from '@/lib/router'
import { ErrorBoundary } from '@/components/app/error-boundary'
import { Sidebar } from '@/components/app/sidebar'
import { Topbar } from '@/components/app/topbar'
import { LeadDrawer } from '@/components/app/lead-drawer'
import { LeadNuevo } from '@/components/app/lead-nuevo'
import { Login } from '@/screens/login'
import { NoEnrolado } from '@/screens/no-enrolado'
import { Skeleton } from '@/components/ui/skeleton'
import { Button } from '@/components/ui/button'

// Vista vive en lib/router (el router la necesita sin ciclos); se re-exporta
// aquí para no romper a quien ya importaba `type { Vista } from '@/App'`.
export type { Vista } from '@/lib/router'

// Pantallas fuera del bundle inicial (chunk por vista). Login/NoEnrolado
// quedan estáticas: son la primera pintura, lazy solo las retrasaría.
const Hoy = lazy(() => import('@/screens/hoy').then((m) => ({ default: m.Hoy })))
const Pipeline = lazy(() => import('@/screens/pipeline').then((m) => ({ default: m.Pipeline })))
const Cartera = lazy(() => import('@/screens/cartera').then((m) => ({ default: m.Cartera })))
const Agenda = lazy(() => import('@/screens/agenda').then((m) => ({ default: m.Agenda })))
const Equipo = lazy(() => import('@/screens/equipo').then((m) => ({ default: m.Equipo })))
const Config = lazy(() => import('@/screens/config').then((m) => ({ default: m.Config })))

function Splash() {
  return (
    <div className="flex min-h-svh items-center justify-center">
      <div className="w-64 space-y-3">
        <Skeleton className="h-8 w-32" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-3/4" />
        <p className="pt-2 text-center text-xs text-muted-foreground">Preparando tu información…</p>
      </div>
    </div>
  )
}

/** Fallback sobrio del Suspense mientras baja el chunk de la pantalla. */
function PantallaCargando() {
  return (
    <div className="space-y-5" aria-busy>
      <Skeleton className="h-7 w-44" />
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Skeleton className="h-28" />
        <Skeleton className="h-28" />
        <Skeleton className="h-28" />
        <Skeleton className="h-28" />
      </div>
      <Skeleton className="h-64 w-full" />
    </div>
  )
}

/** Estado seguro mientras la capa remota todavía no está activada. */
function DatosRealesPendientes() {
  const { salir } = useAuth()
  return (
    <div className="flex min-h-svh items-center justify-center p-6">
      <div className="w-full max-w-md space-y-4 rounded-2xl border border-border bg-card p-7 text-center shadow-[var(--shadow-card)]">
        <div className="mx-auto grid size-12 place-items-center rounded-2xl bg-primary/10 text-primary">
          <DatabaseZap className="size-6" aria-hidden />
        </div>
        <div className="space-y-1.5">
          <h1 className="text-lg font-extrabold text-primary">Datos reales aún no conectados</h1>
          <p className="text-sm leading-relaxed text-muted-foreground">
            Tu sesión es válida, pero la fuente real del CRM todavía no está habilitada.
            Para proteger la información, una cuenta real nunca recibe datos de demostración.
          </p>
        </div>
        <Button type="button" variant="outline" onClick={() => void salir()}>
          <LogOut className="size-4" aria-hidden /> Cerrar sesión
        </Button>
      </div>
    </div>
  )
}

/** Vista corregida por capacidad — espejo del guard (doble defensa F1c). */
function sanearVista(vista: Vista, puedeConfig: boolean, puedeEquipo: boolean): Vista {
  if (vista === 'config' && !puedeConfig) return 'hoy'
  if (vista === 'equipo' && !puedeEquipo) return 'hoy'
  return vista
}

function Workspace() {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const { leadAbiertoId } = usePanelesState()
  const { abrirLead, cerrarPaneles } = usePanelesActions()
  const rol = yo?.rol

  // Arranca en lo que diga el hash (recargar conserva pantalla); saneado por
  // capacidad para no pintar ni un frame de config/equipo a quien no puede.
  const [vista, setVista] = useState<Vista>(() =>
    sanearVista(leerHash().vista ?? 'hoy', can(rol, 'verConfiguracion'), can(rol, 'verEquipo')),
  )

  // Contexto vivo para el listener de hashchange (registrado una sola vez).
  const ctxRef = useRef({ rol, vista, leadAbiertoId, leads: ambito.leads, abrirLead, cerrarPaneles })
  ctxRef.current = { rol, vista, leadAbiertoId, leads: ambito.leads, abrirLead, cerrarPaneles }

  // Cuando el hash ORIGINA un cambio de estado, aquí queda el estado esperado:
  // el efecto estado→hash no escribe hasta converger (evita bucles y pisadas).
  const objetivoHash = useRef<{ vista: Vista; leadId: string | null } | null>(null)

  // hash → estado (montaje + back/forward + URL editada a mano)
  useEffect(() => {
    const alCambiarHash = () => {
      const ctx = ctxRef.current
      const leido = leerHash()
      // Ruta desconocida → hoy; vista sin permiso → hoy (espejo del guard).
      let destino = sanearVista(
        leido.vista ?? 'hoy',
        can(ctx.rol, 'verConfiguracion'),
        can(ctx.rol, 'verEquipo'),
      )
      let leadDestino = destino === leido.vista ? leido.leadId : null
      // Lead fuera del ÁMBITO por rol (o inexistente) → se ignora: el hash no
      // puede abrir fichas que la RLS espejo (F1c) no le muestra al usuario.
      if (leadDestino != null && !ctx.leads.some((l) => l.id === leadDestino)) {
        leadDestino = null
      }
      // Normaliza la URL a lo aceptado sin ensuciar el historial (compara antes).
      escribirHash(destino, leadDestino, true)
      const cambiaVista = destino !== ctx.vista
      const cambiaLead = leadDestino !== ctx.leadAbiertoId
      if (!cambiaVista && !cambiaLead) {
        objetivoHash.current = null // el hash ya refleja el estado
        return
      }
      objetivoHash.current = { vista: destino, leadId: leadDestino }
      if (cambiaVista) setVista(destino)
      if (cambiaLead) {
        if (leadDestino != null) ctx.abrirLead(leadDestino)
        else ctx.cerrarPaneles()
      }
    }
    alCambiarHash()
    window.addEventListener('hashchange', alCambiarHash)
    return () => window.removeEventListener('hashchange', alCambiarHash)
  }, [])

  // estado → hash (navegación por UI: sidebar/búsqueda/drawer). Push normal:
  // back/forward recorren pantallas y fichas abiertas.
  useEffect(() => {
    const objetivo = objetivoHash.current
    if (objetivo) {
      // El cambio vino DEL hash: no reescribir hasta que el estado converja.
      if (objetivo.vista !== vista || objetivo.leadId !== leadAbiertoId) return
      objetivoHash.current = null
      return
    }
    escribirHash(vista, leadAbiertoId) // compara antes de escribir → sin bucles
  }, [vista, leadAbiertoId])

  // Guard por capacidad: el nav ya oculta, esto expulsa (doble defensa, patrón
  // VITANOVA). Cubre cambios de rol en caliente; el hash se corrige detrás.
  useEffect(() => {
    if (vista === 'config' && !can(rol, 'verConfiguracion')) setVista('hoy')
    if (vista === 'equipo' && !can(rol, 'verEquipo')) setVista('hoy')
  }, [vista, rol])

  return (
    <div className="relative z-10 flex h-svh overflow-hidden">
      <Sidebar vista={vista} />
      <main className="ac-scroll flex min-w-0 flex-1 flex-col">
        <Topbar vista={vista} />
        <div className="ac-scroll flex-1 overflow-auto p-6" key={vista}>
          {/* Boundary POR pantalla (key la remonta al cambiar de vista) */}
          <ErrorBoundary>
            <Suspense fallback={<PantallaCargando />}>
              {vista === 'hoy' && <Hoy />}
              {vista === 'pipeline' && <Pipeline />}
              {vista === 'cartera' && <Cartera />}
              {vista === 'agenda' && <Agenda />}
              {vista === 'equipo' && <Equipo />}
              {vista === 'config' && <Config />}
            </Suspense>
          </ErrorBoundary>
        </div>
      </main>
      {/* Paneles globales: cualquier pantalla los abre vía usePanelesActions(). */}
      <ErrorBoundary>
        <LeadDrawer />
        <LeadNuevo />
      </ErrorBoundary>
    </div>
  )
}

export default function App() {
  const { fase, yo } = useAuth()

  const content =
    fase === 'init' || fase === 'resolviendo' ? (
      <Splash />
    ) : fase === 'anon' || fase === 'error' ? (
      <Login />
    ) : fase === 'no_enrolado' ? (
      <NoEnrolado />
    ) : yo?.demo ? (
      <Workspace />
    ) : (
      <DatosRealesPendientes />
    )

  return (
    <>
      <div className="ac-aurora" aria-hidden>
        <i />
      </div>
      {content}
    </>
  )
}
