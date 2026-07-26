import { lazy, Suspense, useEffect, useRef, useState, type ReactNode } from 'react'
import { DatabaseZap, Hourglass, LogOut, RotateCcw, WifiOff, type LucideIcon } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions, usePanelesState, useStoreEstado } from '@/lib/store-context'
import { can } from '@/lib/roles'
import { funcionesLeadsVisibles } from '@/lib/config'
import { escribirHash, esVistaLeads, leerHash, type Vista } from '@/lib/router'
import { sanearVista, vistaBase } from '@/lib/vistas'
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
const MiCartera = lazy(() => import('@/screens/mi-cartera').then((m) => ({ default: m.MiCartera })))
const Repartir = lazy(() => import('@/screens/repartir').then((m) => ({ default: m.Repartir })))
const Equipo = lazy(() => import('@/screens/equipo').then((m) => ({ default: m.Equipo })))
const Config = lazy(() => import('@/screens/config').then((m) => ({ default: m.Config })))

/**
 * Tope de paciencia del splash. Deliberadamente MAYOR que el presupuesto de la
 * carga real del store (LIMITE_CARGA_REAL_MS) y que el de la verificación de
 * acceso: esos dos son la defensa primaria (abortan y caen en un estado de
 * error). Esto es la red de seguridad de último recurso — cubre el cuelgue que
 * ninguno de los dos vea (p. ej. un efecto que nunca llega a correr). El asesor
 * NUNCA debe quedarse mirando un spinner sin salida.
 */
export const LIMITE_SPLASH_MS = 25_000

/** Tarjeta a pantalla completa de los estados de arranque (mismo molde para los tres). */
function AvisoArranque({
  icono: Icono,
  tono = 'primary',
  titulo,
  children,
  acciones,
}: {
  icono: LucideIcon
  tono?: 'primary' | 'destructive'
  titulo: string
  children: ReactNode
  acciones: ReactNode
}) {
  return (
    <div className="flex min-h-svh items-center justify-center p-6">
      <div className="w-full max-w-md space-y-4 rounded-2xl border border-border bg-card p-7 text-center shadow-[var(--shadow-card)]">
        <div
          className={
            tono === 'destructive'
              ? 'mx-auto grid size-12 place-items-center rounded-2xl bg-destructive/10 text-destructive'
              : 'mx-auto grid size-12 place-items-center rounded-2xl bg-primary/10 text-primary'
          }
        >
          <Icono className="size-6" aria-hidden />
        </div>
        <div className="space-y-1.5">
          <h1 className="text-lg font-extrabold text-primary">{titulo}</h1>
          <p className="text-sm leading-relaxed text-muted-foreground">{children}</p>
        </div>
        <div className="flex flex-col gap-2 sm:flex-row sm:justify-center">{acciones}</div>
      </div>
    </div>
  )
}

/**
 * La carga NO falló: simplemente no termina. Un spinner eterno es peor que un
 * error porque no ofrece salida — aquí sí la hay (reintentar / cerrar sesión).
 */
function CargaAtascada({ onReintentar }: { onReintentar: () => void }) {
  const { salir } = useAuth()
  return (
    <AvisoArranque
      icono={Hourglass}
      titulo="Esto está tardando demasiado"
      acciones={
        <>
          <Button type="button" onClick={onReintentar}>
            <RotateCcw className="size-4" aria-hidden /> Reintentar
          </Button>
          <Button type="button" variant="outline" onClick={() => void salir()}>
            <LogOut className="size-4" aria-hidden /> Cerrar sesión
          </Button>
        </>
      }
    >
      No pudimos terminar de preparar tu información. Puede ser tu conexión o el
      servidor del CRM. Tu sesión sigue activa — vuelve a intentarlo.
    </AvisoArranque>
  )
}

/**
 * Splash con FECHA DE CADUCIDAD: pasado `LIMITE_SPLASH_MS` sin que nadie lo
 * desmonte, se transforma en un estado accionable. `onReintentar` es lo que
 * hace ese estado (recargar los datos o re-verificar el acceso).
 *
 * ⚠️ El reloj mide LO QUE DURA ESTE MONTAJE, no el arranque entero. Cada uso
 * debe llevar su `key` propia (ver App): sin ella, React ve el mismo nodo en el
 * árbol al pasar del splash de ACCESO al de DATOS, no remonta, y un único reloj
 * de 25 s cubre los dos presupuestos seguidos (12 s de auth + 20 s de datos).
 * Una carga lenta pero SANA se declaraba atascada y el «Reintentar» abortaba un
 * fetch bueno (regresión 2026-07-25).
 */
function Splash({ onReintentar }: { onReintentar: () => void }) {
  const [atascado, setAtascado] = useState(false)

  useEffect(() => {
    if (atascado) return
    const reloj = setTimeout(() => setAtascado(true), LIMITE_SPLASH_MS)
    return () => clearTimeout(reloj)
  }, [atascado])

  if (atascado) {
    return (
      <CargaAtascada
        onReintentar={() => {
          // Vuelve al spinner: el reintento arranca de cero y, si se vuelve a
          // atascar, el reloj lo detectará otra vez (efecto con dep [atascado]).
          setAtascado(false)
          onReintentar()
        }}
      />
    )
  }

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
    <AvisoArranque
      icono={DatabaseZap}
      titulo="Datos reales aún no conectados"
      acciones={
        <Button type="button" variant="outline" onClick={() => void salir()}>
          <LogOut className="size-4" aria-hidden /> Cerrar sesión
        </Button>
      }
    >
      Tu sesión es válida, pero la fuente real del CRM todavía no está habilitada.
      Para proteger la información, una cuenta real nunca recibe datos de demostración.
    </AvisoArranque>
  )
}

/** La carga real falló: NUNCA se pinta el CRM vacío (parecería "no hay leads").
 * Reintento explícito + salida, con la sesión intacta. */
function ErrorCargaReal({ onReintentar }: { onReintentar: () => void }) {
  const { salir } = useAuth()
  return (
    <AvisoArranque
      icono={WifiOff}
      tono="destructive"
      titulo="No pudimos cargar tu información"
      acciones={
        <>
          <Button type="button" onClick={onReintentar}>
            <RotateCcw className="size-4" aria-hidden /> Reintentar
          </Button>
          <Button type="button" variant="outline" onClick={() => void salir()}>
            <LogOut className="size-4" aria-hidden /> Cerrar sesión
          </Button>
        </>
      }
    >
      Hubo un problema al conectar con el servidor del CRM. Tu sesión sigue activa —
      revisa tu conexión y vuelve a intentarlo.
    </AvisoArranque>
  )
}

function Workspace() {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const { leadAbiertoId } = usePanelesState()
  const { abrirLead, cerrarPaneles } = usePanelesActions()
  const rol = yo?.rol
  // Gate de leads: el demo enseña el CRM completo; una cuenta real solo ve el
  // mundo leads cuando Miguel lo apruebe (FUNCIONES_LEADS_APROBADAS).
  const leadsVisibles = funcionesLeadsVisibles(yo?.demo === true, yo?.rol, yo?.id)

  // Arranca en lo que diga el hash (recargar conserva pantalla); saneado por
  // capacidad para no pintar ni un frame de config/equipo a quien no puede.
  const [vista, setVista] = useState<Vista>(() =>
    sanearVista(leerHash().vista ?? vistaBase(rol, leadsVisibles), rol, leadsVisibles),
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
        leido.vista ?? vistaBase(ctx.rol, ctx.leadsVisibles),
        ctx.rol,
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
    const base = vistaBase(rol, leadsVisibles)
    if (!leadsVisibles && esVistaLeads(vista)) setVista(base)
    if (vista === 'config' && !can(rol, 'verConfiguracion')) setVista(base)
    if (vista === 'equipo' && !can(rol, 'verEquipo')) setVista(base)
    if (vista === 'repartir' && !can(rol, 'repartirCola')) setVista(base)
    if (vista === 'mi-cartera' && !can(rol, 'verCartera')) setVista(base)
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
              {vista === 'mi-cartera' && <MiCartera />}
              {vista === 'repartir' && <Repartir />}
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
  const { fase, yo, reintentar } = useAuth()
  const estadoDatos = useStoreEstado()

  const content =
    fase === 'init' || fase === 'resolviendo' ? (
      // Splash del ACCESO: si se atasca, su salida es re-verificar la sesión.
      // La `key` distinta de la del splash de DATOS es LOAD-BEARING: obliga a
      // React a remontar al pasar de uno al otro y reinicia el reloj de
      // caducidad, para que cada etapa estrene sus 25 s de paciencia.
      <Splash key="splash-acceso" onReintentar={reintentar} />
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
        // Splash de DATOS: su salida es volver a pedirlos. `key` propia → reloj
        // propio (no hereda los segundos que ya consumió el splash del acceso).
        <Splash key="splash-datos" onReintentar={estadoDatos.reintentar} />
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
