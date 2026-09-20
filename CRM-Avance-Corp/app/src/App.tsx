import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { DatabaseZap, Hourglass, LogOut, RotateCcw, WifiOff, type LucideIcon } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { vincularCuentaPushTasa } from '@/lib/notificaciones-tasa'
import { useCRMData, usePanelesActions, usePanelesState, useStoreEstado } from '@/lib/store-context'
import { funcionesLeadsVisibles } from '@/lib/config'
import { escribirHash, leerHash, type Vista } from '@/lib/router'
import { ContextoSplashVisible } from '@/lib/splash-visible'
import { sanearVista, vistaBase } from '@/lib/vistas'
import { puedeAdministrarRolesCrm } from '@/lib/roles'
import { ErrorBoundary } from '@/components/app/error-boundary'
import { Sidebar } from '@/components/app/sidebar'
import { SplashCrm, type FaseSplashCrm } from '@/components/app/splash-crm'
import { Topbar } from '@/components/app/topbar'
import { RespuestasTasaProvider } from '@/components/app/respuestas-tasa-provider'
import { recibeRespuestasTasa } from '@/lib/respuestas-tasa'
import { AyudaVendedorPanel } from '@/components/app/ayuda-vendedor-panel'
import { LeadDrawer } from '@/components/app/lead-drawer'
import { GuardadosSlaPendientes } from '@/components/app/guardados-sla-pendientes'
import { LeadNuevo } from '@/components/app/lead-nuevo'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { AreaConsultaGerencia } from '@/components/gerencia/area-consulta-gerencia'
import { AlertasCRMProvider } from '@/lib/alertas-provider'
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
const Alertas = lazy(() => import('@/screens/alertas').then((m) => ({ default: m.Alertas })))
const Seguimiento = lazy(() => import('@/screens/seguimiento').then((m) => ({ default: m.Seguimiento })))
const GestionDiaria = lazy(() => import('@/screens/gestion-diaria').then((m) => ({ default: m.GestionDiaria })))
const ConversionesGerencia = lazy(() => import('@/screens/gerencia').then((m) => ({ default: m.ConversionesGerencia })))
const RankingVendedoresGerencia = lazy(() => import('@/screens/gerencia').then((m) => ({ default: m.RankingVendedoresGerencia })))
const ReunionesGerencia = lazy(() => import('@/screens/gerencia').then((m) => ({ default: m.ReunionesGerencia })))
const MetasGerencia = lazy(() => import('@/screens/gerencia').then((m) => ({ default: m.MetasGerencia })))
const RendimientoGerencia = lazy(() => import('@/screens/gerencia').then((m) => ({ default: m.RendimientoGerencia })))
const Pipeline = lazy(() => import('@/screens/pipeline').then((m) => ({ default: m.Pipeline })))
const Cartera = lazy(() => import('@/screens/cartera').then((m) => ({ default: m.Cartera })))
const Agenda = lazy(() => import('@/screens/agenda').then((m) => ({ default: m.Agenda })))
const MiCartera = lazy(() => import('@/screens/mi-cartera').then((m) => ({ default: m.MiCartera })))
const Repartir = lazy(() => import('@/screens/repartir').then((m) => ({ default: m.Repartir })))
const RescateDescartados = lazy(() => import('@/screens/rescate-descartados').then((m) => ({ default: m.RescateDescartados })))
const RescateCarpeta = lazy(() => import('@/screens/rescate-carpeta').then((m) => ({ default: m.RescateCarpeta })))
const Derivaciones = lazy(() => import('@/screens/derivaciones').then((m) => ({ default: m.Derivaciones })))
const Equipo = lazy(() => import('@/screens/equipo').then((m) => ({ default: m.Equipo })))
const MetricasMultiempresa = lazy(() => import('@/screens/metricas-multiempresa').then((m) => ({ default: m.MetricasMultiempresa })))
const Facturacion = lazy(() => import('@/screens/facturacion').then((m) => ({ default: m.Facturacion })))
const Config = lazy(() => import('@/screens/config').then((m) => ({ default: m.Config })))
const ConfigUsuarios = lazy(() => import('@/screens/config-usuarios').then((m) => ({ default: m.ConfigUsuarios })))
const ConfigProductos = lazy(() => import('@/screens/config-productos').then((m) => ({ default: m.ConfigProductos })))
const ConfigMetas = lazy(() => import('@/screens/config-metas').then((m) => ({ default: m.ConfigMetas })))
const ConfigSla = lazy(() => import('@/screens/config-sla').then((m) => ({ default: m.ConfigSla })))
const ConfigRentabilidad = lazy(() => import('@/screens/config-rentabilidad').then((m) => ({ default: m.ConfigRentabilidad })))
const ConfigCitas = lazy(() => import('@/screens/config-citas').then((m) => ({ default: m.ConfigCitas })))

/** Registro exhaustivo: una Vista nueva exige declarar también su pantalla. */
const PANTALLA_POR_VISTA = {
  hoy: Hoy,
  alertas: Alertas,
  seguimiento: Seguimiento,
  'gestion-diaria': GestionDiaria,
  conversiones: ConversionesGerencia,
  'ranking-vendedores': RankingVendedoresGerencia,
  reuniones: ReunionesGerencia,
  metas: MetasGerencia,
  rendimiento: RendimientoGerencia,
  facturacion: Facturacion,
  'informes-empresas': MetricasMultiempresa,
  pipeline: Pipeline,
  cartera: Cartera,
  agenda: Agenda,
  'mi-cartera': MiCartera,
  repartir: Repartir,
  rescate: RescateDescartados,
  'rescate-carpeta': RescateCarpeta,
  derivaciones: Derivaciones,
  equipo: Equipo,
  config: Config,
  'config-usuarios': ConfigUsuarios,
  'config-productos': ConfigProductos,
  'config-metas': ConfigMetas,
  'config-sla': ConfigSla,
  'config-rentabilidad': ConfigRentabilidad,
  'config-citas': ConfigCitas,
} satisfies Record<Vista, unknown>

/**
 * Tope de paciencia del splash. Deliberadamente MAYOR que el presupuesto de la
 * carga real del store (LIMITE_CARGA_REAL_MS) y que el de la verificación de
 * acceso: esos dos son la defensa primaria (abortan y caen en un estado de
 * error). Esto es la red de seguridad de último recurso — cubre el cuelgue que
 * ninguno de los dos vea (p. ej. un efecto que nunca llega a correr). El analista
 * NUNCA debe quedarse mirando un spinner sin salida.
 */
export const LIMITE_SPLASH_MS = 25_000

/**
 * En respuestas instantáneas (sobre todo el modo demo), deja respirar la marca
 * antes de la salida. El tiempo ya consumido por la carga real cuenta dentro
 * de este mínimo; una carga lenta no recibe una demora adicional.
 */
export const MINIMO_SPLASH_VISIBLE_MS = 2_000

/** Tarjeta a pantalla completa de los estados de arranque (mismo molde para los tres). */
function AvisoArranque({
  icono: Icono,
  tono = 'primary',
  titulo,
  children,
  acciones,
  alerta = false,
  enfocarTitulo = false,
}: {
  icono: LucideIcon
  tono?: 'primary' | 'destructive'
  titulo: string
  children: ReactNode
  acciones: ReactNode
  alerta?: boolean
  enfocarTitulo?: boolean
}) {
  const tituloRef = useRef<HTMLHeadingElement>(null)

  useEffect(() => {
    if (enfocarTitulo) tituloRef.current?.focus()
  }, [enfocarTitulo])

  return (
    <div
      className="flex min-h-svh items-center justify-center p-6"
      role={alerta ? 'alert' : undefined}
    >
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
          <h1
            ref={tituloRef}
            className="text-lg font-extrabold text-primary outline-none"
            tabIndex={enfocarTitulo ? -1 : undefined}
          >
            {titulo}
          </h1>
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
      alerta
      enfocarTitulo
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
 * ⚠️ La caducidad pertenece a la FASE, no al montaje completo. Acceso y datos
 * comparten el mismo nodo para mantener la continuidad visual, pero al cambiar
 * de fase el efecto cancela el reloj anterior y comienza otro. Así 12 s de auth
 * + 20 s de datos no se confunden con un único cuelgue de 32 s (regresión
 * 2026-07-25).
 */
function Splash({
  fase,
  ciclo,
  onReintentar,
  onFinalizar,
}: {
  fase: FaseSplashCrm
  ciclo: number
  onReintentar: () => void
  onFinalizar?: () => void
}) {
  const [caducidad, setCaducidad] = useState<{
    fase: FaseSplashCrm
    ciclo: number
    atascado: boolean
  }>({ fase, ciclo, atascado: false })
  // Un atasco pertenece a una fase Y a un intento concreto. La fase puede
  // volver a llamarse "datos" durante la salida, pero ya es otro ciclo.
  const atascado =
    caducidad.ciclo === ciclo
    && caducidad.fase === fase
    && caducidad.atascado

  useEffect(() => {
    if (fase === 'listo' || atascado) return
    const reloj = setTimeout(
      () => setCaducidad({ fase, ciclo, atascado: true }),
      LIMITE_SPLASH_MS,
    )
    return () => clearTimeout(reloj)
  }, [atascado, ciclo, fase])

  if (fase !== 'listo' && atascado) {
    return (
      <CargaAtascada
        onReintentar={() => {
          // Vuelve al spinner: el reintento arranca de cero y, si se vuelve a
          // atascar, el reloj lo detectará otra vez.
          setCaducidad({ fase, ciclo, atascado: false })
          onReintentar()
        }}
      />
    )
  }

  return <SplashCrm fase={fase} onFinalizar={onFinalizar} />
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
  useEffect(() => {
    vincularCuentaPushTasa(yo?.rol === 'gerencia' && !yo.demo ? yo.id : null)
  }, [yo?.id, yo?.rol, yo?.demo])
  const { ambito } = useCRMData()
  const { leadAbiertoId, nuevoLeadAbierto } = usePanelesState()
  const { abrirLead, abrirNuevoLead, cerrarPaneles } = usePanelesActions()
  const rol = yo?.rol
  // La ruta excepcional de Usuarios se abre por la capacidad viva del
  // servidor; el string del Portal por sí solo no concede nada.
  const rolPortal = puedeAdministrarRolesCrm(yo) ? 'superadmin' : null
  // Gate de leads: el demo enseña el CRM completo; una cuenta real solo ve el
  // mundo leads cuando Miguel lo apruebe (FUNCIONES_LEADS_APROBADAS).
  const leadsVisibles = funcionesLeadsVisibles(yo?.demo === true, yo?.rol)

  // Arranca en lo que diga el hash (recargar conserva pantalla); saneado por
  // capacidad para no pintar ni un frame de config/equipo a quien no puede.
  const [vista, setVista] = useState<Vista>(() =>
    sanearVista(
      leerHash().vista ?? vistaBase(rol, leadsVisibles, rolPortal),
      rol,
      leadsVisibles,
      rolPortal,
    ),
  )
  const [ayudaAbierta, setAyudaAbierta] = useState(false)
  const panelTrabajoAbierto = leadAbiertoId != null || nuevoLeadAbierto
  const panelTrabajoAnteriorRef = useRef(panelTrabajoAbierto)

  // Al abrir una ficha o el alta, la guía se aparta una vez para no competir
  // con el formulario. Su contenido sigue montado y queda en “Continuar guía”.
  // Si el analista decide reabrirla mientras trabaja, se respeta esa intención.
  useEffect(() => {
    if (panelTrabajoAbierto && !panelTrabajoAnteriorRef.current) {
      setAyudaAbierta(false)
    }
    panelTrabajoAnteriorRef.current = panelTrabajoAbierto
  }, [panelTrabajoAbierto])

  // Contexto vivo para el listener de hashchange (registrado una sola vez).
  const ctxRef = useRef({ rol, rolPortal, vista, leadAbiertoId, leads: ambito.leads, abrirLead, cerrarPaneles, leadsVisibles })
  ctxRef.current = { rol, rolPortal, vista, leadAbiertoId, leads: ambito.leads, abrirLead, cerrarPaneles, leadsVisibles }

  // Cuando el hash ORIGINA un cambio de estado, aquí queda el estado esperado:
  // el efecto estado→hash no escribe hasta converger (evita bucles y pisadas).
  const objetivoHash = useRef<{ vista: Vista; leadId: string | null } | null>(null)

  // Navegación iniciada por la UI: cambia la pantalla en el mismo evento que
  // pulsó el usuario. Si el sidebar solo escribe el hash, `hashchange` llega
  // después y la pantalla anterior sigue siendo interactiva durante ese lapso:
  // una apertura de ficha ahí puede ser cerrada por la ruta que aún aterriza.
  const navegarDesdeUI = useCallback((destino: Vista) => {
    const destinoSeguro = sanearVista(destino, rol, leadsVisibles, rolPortal)
    objetivoHash.current = null // una intención nueva de UI sustituye cualquier hash pendiente
    cerrarPaneles()
    setVista(destinoSeguro)
  }, [cerrarPaneles, leadsVisibles, rol, rolPortal])

  // hash → estado (montaje + back/forward + URL editada a mano)
  useEffect(() => {
    const alCambiarHash = () => {
      const ctx = ctxRef.current
      const leido = leerHash()
      // Ruta desconocida → vista base; vista sin permiso o gateada → base (espejo del guard).
      let destino = sanearVista(
        leido.vista ?? vistaBase(ctx.rol, ctx.leadsVisibles, ctx.rolPortal),
        ctx.rol,
        ctx.leadsVisibles,
        ctx.rolPortal,
      )
      // El hash NO se contrasta contra la foto de leads en memoria: esa foto
      // está capada (MAX_LEADS_AMBITO) y dejaba inabrible por enlace a todo lead
      // que no cupiera en ella (Fase 1 «sin topes», 19/09/2026). `abrirLead`
      // relee cualquier lead por id a través de su propia puerta RLS y avisa si
      // ya no está disponible — esa es la comprobación de ámbito que vale.
      const leadDestino = destino === leido.vista ? leido.leadId : null
      // Normaliza la URL a lo aceptado sin ensuciar el historial (compara antes).
      escribirHash(destino, leadDestino, true, destino === 'mi-cartera' ? leido.inversionistaId : undefined,
        destino === 'hoy' && (ctx.rol === 'gerencia' || recibeRespuestasTasa(ctx.rol)) ? leido.solicitudTasaId : undefined)
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
    const ruta = leerHash()
    escribirHash(vista, leadAbiertoId, false, ruta.vista === vista ? ruta.inversionistaId : undefined,
      ruta.vista === vista && (rol === 'gerencia' || recibeRespuestasTasa(rol)) ? ruta.solicitudTasaId : undefined) // compara antes de escribir → sin bucles
  }, [vista, leadAbiertoId, rol])

  // Guard por capacidad + gate de leads: el nav ya oculta, esto expulsa (doble
  // defensa, patrón VITANOVA). Cubre cambios de rol en caliente; el hash se
  // corrige detrás.
  useEffect(() => {
    const vistaSegura = sanearVista(vista, rol, leadsVisibles, rolPortal)
    if (vistaSegura !== vista) setVista(vistaSegura)
  }, [vista, rol, leadsVisibles, rolPortal])

  const Pantalla = PANTALLA_POR_VISTA[vista]

  return (
    <AlertasCRMProvider>
      <RespuestasTasaProvider>
      <div className="relative z-10 flex h-svh overflow-hidden">
        <Sidebar vista={vista} onNavegar={navegarDesdeUI} />
        <main className="ac-scroll flex min-w-0 flex-1 flex-col" tabIndex={-1}>
          <PeriodoGerenciaProvider>
            <Topbar
              vista={vista}
              ayudaAbierta={ayudaAbierta}
              onAlternarAyuda={() => setAyudaAbierta((actual) => !actual)}
            />
            <AreaConsultaGerencia vista={vista} habilitada={yo?.rol === 'gerencia'} key={vista}>
              {/* Boundary POR pantalla (key la remonta al cambiar de vista) */}
              <ErrorBoundary>
                <Suspense fallback={<PantallaCargando />}>
                  <Pantalla />
                </Suspense>
              </ErrorBoundary>
            </AreaConsultaGerencia>
          </PeriodoGerenciaProvider>
        </main>
        <AyudaVendedorPanel
          abierto={ayudaAbierta}
          onAbiertoChange={setAyudaAbierta}
          vista={vista}
          onNavegar={navegarDesdeUI}
          onAbrirNuevoLead={() => abrirNuevoLead()}
        />
        {/* Paneles globales: cualquier pantalla los abre vía usePanelesActions(). */}
        <ErrorBoundary>
          <LeadDrawer />
          <LeadNuevo />
          {/* Los guardados por confirmar se montan UNA vez (antes vivían dentro
              de la bandeja SLA, y desde Gestión Diaria F3 hay más de una
              pantalla que registra gestiones). Se autoapaga si no hay ninguno. */}
          <GuardadosSlaPendientes />
        </ErrorBoundary>
      </div>
      </RespuestasTasaProvider>
    </AlertasCRMProvider>
  )
}

/**
 * Mantiene una sola entrada visual durante ACCESO → DATOS → LISTO. El Workspace
 * real se monta en cuanto llegan los datos; permanece inerte y fuera del árbol
 * accesible durante el breve cierre de la capa.
 */
type EstadoVisualEntrada = 'cargando' | 'completando' | 'saliendo' | 'oculto'

interface EstadoEntrada {
  estado: EstadoVisualEntrada
  ciclo: number
}

const ahoraMonotono = () =>
  typeof performance === 'undefined' ? 0 : performance.now()

export function EntradaCrm({
  faseCarga,
  onReintentar,
  children,
}: {
  faseCarga: Exclude<FaseSplashCrm, 'listo'> | null
  onReintentar: () => void
  /** Punto de inyección para pruebas; producción siempre usa Workspace. */
  children?: ReactNode
}) {
  const [entrada, setEntrada] = useState<EstadoEntrada>(() => ({
    estado: faseCarga ? 'cargando' : 'completando',
    ciclo: 1,
  }))
  const workspaceRef = useRef<HTMLDivElement>(null)
  const faseCargaAnteriorRef = useRef(faseCarga)
  const inicioVisualRef = useRef(ahoraMonotono())

  // Acceso y datos son capítulos de una misma presentación. Solo una recarga
  // nueva (listo → cargando) incrementa el ciclo y reinicia el mínimo visible.
  // LayoutEffect registra únicamente props ya comprometidas: ningún callback
  // asíncrono observa valores de un render que React pudiera descartar.
  useLayoutEffect(() => {
    const faseAnterior = faseCargaAnteriorRef.current
    faseCargaAnteriorRef.current = faseCarga

    if (faseCarga) {
      const iniciaCiclo = faseAnterior === null
      if (iniciaCiclo) inicioVisualRef.current = ahoraMonotono()
      setEntrada((actual) => ({
        estado: 'cargando',
        ciclo: actual.ciclo + (iniciaCiclo ? 1 : 0),
      }))
      return
    }

    setEntrada((actual) => (
      actual.estado === 'cargando'
        ? { ...actual, estado: 'completando' }
        : actual
    ))
  }, [faseCarga])

  // La espera mínima se programa una sola vez al completar la carga, no en
  // cada render ni en cada salto entre acceso y datos.
  useEffect(() => {
    if (faseCarga !== null || entrada.estado !== 'completando') return
    const cicloProgramado = entrada.ciclo
    const restante = Math.max(
      0,
      MINIMO_SPLASH_VISIBLE_MS - (ahoraMonotono() - inicioVisualRef.current),
    )
    if (restante === 0) {
      setEntrada((actual) => (
        actual.ciclo === cicloProgramado && actual.estado === 'completando'
          ? { ...actual, estado: 'saliendo' }
          : actual
      ))
      return
    }

    const espera = setTimeout(() => {
      setEntrada((actual) => (
        actual.ciclo === cicloProgramado && actual.estado === 'completando'
          ? { ...actual, estado: 'saliendo' }
          : actual
      ))
    }, restante)
    return () => clearTimeout(espera)
  }, [entrada.ciclo, entrada.estado, faseCarga])

  // Si el navegador interrumpe la timeline, el CRM listo no puede quedar
  // inerte indefinidamente. La salida normal termina bastante antes.
  useEffect(() => {
    if (faseCarga !== null || entrada.estado !== 'saliendo') return
    const cicloProgramado = entrada.ciclo
    const salvavidas = setTimeout(() => {
      setEntrada((actual) => (
        actual.ciclo === cicloProgramado && actual.estado === 'saliendo'
          ? { ...actual, estado: 'oculto' }
          : actual
      ))
    }, 2_000)
    return () => clearTimeout(salvavidas)
  }, [entrada.ciclo, entrada.estado, faseCarga])

  const cicloSplash =
    faseCarga !== null && entrada.estado !== 'cargando'
      ? entrada.ciclo + 1
      : entrada.ciclo
  const finalizarSalida = useCallback(() => {
    const cicloFinalizado = cicloSplash
    setEntrada((actual) => (
      actual.ciclo === cicloFinalizado && actual.estado === 'saliendo'
        ? { ...actual, estado: 'oculto' }
        : actual
    ))
  }, [cicloSplash])
  const mostrarSplash = faseCarga !== null || entrada.estado !== 'oculto'
  const faseSplash: FaseSplashCrm = faseCarga
    ?? (entrada.estado === 'saliendo' ? 'listo' : 'datos')

  // Al desaparecer la capa, un botón de Login/splash recién desmontado suele
  // devolver el foco a <body>. En ese único caso dejamos al lector de pantalla
  // dentro del CRM; si otra interacción ya dejó un foco válido, se respeta.
  useEffect(() => {
    if (faseCarga !== null || entrada.estado !== 'oculto') return
    const activo = document.activeElement
    if (activo !== document.body && activo !== document.documentElement) return
    workspaceRef.current
      ?.querySelector<HTMLElement>('main')
      ?.focus({ preventScroll: true })
  }, [entrada.estado, faseCarga])

  return (
    <>
      {faseCarga === null && (
        // El contexto publica si la capa aún tapa el workspace: las pantallas
        // que anotan «visitas» (F4.3) esperan a ser visibles de verdad.
        <ContextoSplashVisible.Provider value={mostrarSplash}>
          <div
            ref={workspaceRef}
            className="h-svh"
            inert={mostrarSplash ? true : undefined}
            aria-hidden={mostrarSplash ? true : undefined}
          >
            {children ?? <Workspace />}
          </div>
        </ContextoSplashVisible.Provider>
      )}
      {mostrarSplash && (
        <Splash
          fase={faseSplash}
          ciclo={cicloSplash}
          onReintentar={onReintentar}
          onFinalizar={finalizarSalida}
        />
      )}
    </>
  )
}

export default function App() {
  const { fase, yo, reintentar } = useAuth()
  const estadoDatos = useStoreEstado()

  const content =
    fase === 'init' || fase === 'resolviendo' ? (
      // El mismo componente continúa en DATOS al resolver Auth: no remonta la
      // marca ni reinicia la animación. El cambio de fase sí renueva el reloj.
      <EntradaCrm
        key="entrada-crm"
        faseCarga="acceso"
        onReintentar={reintentar}
      />
    ) : fase === 'anon' || fase === 'error' ? (
      <Login />
    ) : fase === 'no_enrolado' ? (
      <NoEnrolado />
    ) : yo ? (
      // Sesión válida: la carga remota decide qué pintar. El error muestra
      // reintento (nunca el CRM vacío); mientras carga, splash; luego workspace.
      estadoDatos.error ? (
        <ErrorCargaReal onReintentar={estadoDatos.reintentar} />
      ) : (
        <EntradaCrm
          key="entrada-crm"
          faseCarga={estadoDatos.cargando ? 'datos' : null}
          onReintentar={estadoDatos.reintentar}
        />
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
