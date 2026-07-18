import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import { DatabaseZap, LogOut, RotateCcw, WifiOff } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions, usePanelesState, useStoreEstado } from '@/lib/store-context'
import { can } from '@/lib/roles'
import { funcionesLeadsVisibles } from '@/lib/config'
import { escribirHash, esVistaLeads, leerHash, type Vista } from '@/lib/router'
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
const Clientes = lazy(() => import('@/screens/clientes').then((m) => ({ default: m.Clientes })))
const Contratos = lazy(() => import('@/screens/contratos').then((m) => ({ default: m.Contratos })))
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

/** La carga real falló: NUNCA se pinta el CRM vacío (parecería "no hay leads").
 * Reintento explícito + salida, con la sesión intacta. */
function ErrorCargaReal({ onReintentar }: { onReintentar: () => void }) {
  const { salir } = useAuth()
  return (
    <div className="flex min-h-svh items-center justify-center p-6">
      <div className="w-full max-w-md space-y-4 rounded-2xl border border-border bg-card p-7 text-center shadow-[var(--shadow-card)]">
        <div className="mx-auto grid size-12 place-items-center rounded-2xl bg-destructive/10 text-destructive">
          <WifiOff className="size-6" aria-hidden />
        </div>
        <div className="space-y-1.5">
          <h1 className="text-lg font-extrabold text-primary">No pudimos cargar tu información</h1>
          <p className="text-sm leading-relaxed text-muted-foreground">
            Hubo un problema al conectar con el servidor del CRM. Tu sesión sigue activa —
            revisa tu conexión y vuelve a intentarlo.
          </p>
        </div>
        <div className="flex flex-col gap-2 sm:flex-row sm:justify-center">
          <Button type="button" onClick={onReintentar}>
            <RotateCcw className="size-4" aria-hidden /> Reintentar
          </Button>
          <Button type="button" variant="outline" onClick={() => void salir()}>
            <LogOut className="size-4" aria-hidden /> Cerrar sesión
          </Button>
        </div>
      </div>
    </div>
  )
}

/**
 * Vista corregida por capacidad y por el GATE de leads — espejo del guard
 * (doble defensa F1c). Con el gate cerrado (cuenta real, leads sin aprobar) las
 * vistas de leads redirigen a 'clientes', que además es la vista base.
 */
function sanearVista(vista: Vista, puedeConfig: boolean, puedeEquipo: boolean, leadsVisibles: boolean): Vista {
  const base: Vista = leadsVisibles ? 'hoy' : 'clientes'
  if (!leadsVisibles && esVistaLeads(vista)) return 'clientes'
  if (vista === 'config' && !puedeConfig) return base
  if (vista === 'equipo' && !puedeEquipo) return base
  return vista
}

function Workspace() {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const { leadAbiertoId } = usePanelesState()
  const { abrirLead, cerrarPaneles } = usePanelesActions()
  const rol = yo?.rol
  // Gate de leads: el demo enseña el CRM completo; una cuenta real solo ve el
  // mundo leads cuando Miguel lo apruebe (FUNCIONES_LEADS_APROBADAS).
  const leadsVisibles = funcionesLeadsVisibles(yo?.demo === true, yo?.rol)

  // Arranca en lo que diga el hash (recargar conserva pantalla); saneado por
  // capacidad para no pintar ni un frame de config/equipo a quien no puede.
  const [vista, setVista] = useState<Vista>(() =>
    sanearVista(
      leerHash().vista ?? (leadsVisibles ? 'hoy' : 'clientes'),
      can(rol, 'verConfiguracion'),
      can(rol, 'verEquipo'),
      leadsVisibles,
    ),
  )

  // Contexto vivo para el listener de hashchange (registrado una sola vez).
  const ctxRef = useRef({ rol, vista, leadAbiertoId, leads: ambito.leads, abrirLead, cerrarPaneles, leadsVisibles })
  ctxRef.current = { rol, vista, leadAbiertoId, leads: ambito.leads, abrirLead, cerrarPaneles, leadsVisibles }

  // Cuando el hash ORIGINA un cambio de estado, aquí queda el estado esperado:
  // el efecto estado→hash no escribe hasta converger (evita bucles y pisadas).
  const objetivoHash = useRef<{ vista: Vista; leadId: string | null } | null>(null)

  // hash → estado (montaje + back/forward + URL editada a mano)
  useEffect(() => {
    const alCambiarHash = () => {
      const ctx = ctxRef.current
      const leido = leerHash()
      // Ruta desconocida → vista base; vista sin permiso o gateada → base (espejo del guard).
      let destino = sanearVista(
        leido.vista ?? (ctx.leadsVisibles ? 'hoy' : 'clientes'),
        can(ctx.rol, 'verConfiguracion'),
        can(ctx.rol, 'verEquipo'),
        ctx.leadsVisibles,
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

  // Guard por capacidad + gate de leads: el nav ya oculta, esto expulsa (doble
  // defensa, patrón VITANOVA). Cubre cambios de rol en caliente; el hash se
  // corrige detrás.
  useEffect(() => {
    const base: Vista = leadsVisibles ? 'hoy' : 'clientes'
    if (!leadsVisibles && esVistaLeads(vista)) setVista('clientes')
    if (vista === 'config' && !can(rol, 'verConfiguracion')) setVista(base)
    if (vista === 'equipo' && !can(rol, 'verEquipo')) setVista(base)
  }, [vista, rol, leadsVisibles])

  return (
    <div className="relative z-10 flex h-svh overflow-hidden">
      <Sidebar vista={vista} />
      <main className="ac-scroll flex min-w-0 flex-1 flex-col">
        <Topbar vista={vista} />
        <div className="ac-scroll flex-1 overflow-auto p-3 sm:p-6" key={vista}>
          {/* Boundary POR pantalla (key la remonta al cambiar de vista) */}
          <ErrorBoundary>
            <Suspense fallback={<PantallaCargando />}>
              {vista === 'hoy' && <Hoy />}
              {vista === 'pipeline' && <Pipeline />}
              {vista === 'cartera' && <Cartera />}
              {vista === 'agenda' && <Agenda />}
              {vista === 'clientes' && <Clientes />}
              {vista === 'contratos' && <Contratos />}
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
  const estadoDatos = useStoreEstado()

  const content =
    fase === 'init' || fase === 'resolviendo' ? (
      <Splash />
    ) : fase === 'anon' || fase === 'error' ? (
      <Login />
    ) : fase === 'no_enrolado' ? (
      <NoEnrolado />
    ) : yo ? (
      // Sesión válida: la carga remota decide qué pintar. El error muestra
      // reintento (nunca el CRM vacío); mientras carga, splash; luego workspace.
      estadoDatos.error ? (
        <ErrorCargaReal onReintentar={estadoDatos.reintentar} />
      ) : estadoDatos.cargando ? (
        <Splash />
      ) : (
        <Workspace />
      )
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
