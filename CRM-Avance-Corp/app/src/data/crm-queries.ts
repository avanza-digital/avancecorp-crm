import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
  type QueryKey,
} from '@tanstack/react-query'
import type { CursorCartera, FiltrosCartera, PaginaCartera } from './crm-api'
import {
  actualizarCapacidadLeadsObjetivo,
  listarCarteraPagina,
  listarClientes,
  listarColaAccion,
  listarCuentasBancariasCliente,
  listarMetricasAgenda,
  listarMetricasVendedores,
  listarResumenCartera,
  listarResumenReparto,
  listarMetricasConversiones,
  listarMetricasConversionesEquipo,
  listarMetricasReuniones,
  listarMetricasAltasAnalista,
  listarMetricasCapitalMes,
  listarMetricasDistribucionLeads,
  listarMetricasPagosMes,
  listarMetricasVencimientos,
  listarMisContratos,
  obtenerClienteDetalle,
  obtenerCronograma,
  obtenerTitulares,
} from './crm-api'

// El store sigue cargando el ámbito completo (listarLeadsDelAmbito) para las
// pantallas que aún no migraron; la prohibición general de claves de leads se
// levanta en F3. La ÚNICA excepción viva es `carteraPagina` (F2): esa pantalla
// ya no cuenta filas del store, pagina por cursor keyset contra el servidor.
export const crmQueryKeys = {
  raiz: ['crm'] as const,
  config: () => [...crmQueryKeys.raiz, 'config'] as const,
  configUsuarios: (busqueda: string, limite: number, desde: number) =>
    [...crmQueryKeys.config(), 'usuarios', busqueda, limite, desde] as const,
  configUsuariosCatalogo: () => [...crmQueryKeys.config(), 'usuarios-catalogo'] as const,
  configProductos: () => [...crmQueryKeys.config(), 'productos'] as const,
  productosSeleccionables: () => [...crmQueryKeys.raiz, 'productos-seleccionables'] as const,
  configMetas: (periodo: string) => [...crmQueryKeys.config(), 'metas', periodo] as const,
  configSla: () => [...crmQueryKeys.config(), 'sla'] as const,
  metricasSla: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'sla', desde, hasta] as const,
  estadoSlaLeads: () => [...crmQueryKeys.raiz, 'sla', 'estado-leads'] as const,
  // Cartera del portal (panel del analista): bajo la misma raíz para que el
  // logout (queryClient.clear) y las invalidaciones jerárquicas la cubran.
  clientes: () => [...crmQueryKeys.raiz, 'clientes'] as const,
  contratos: () => [...crmQueryKeys.raiz, 'contratos'] as const,
  // Detalle POR REGISTRO colgado del PREFIJO de su lista: invalidar contratos()
  // tras corregir cubre lista + cronograma + titulares de UNA sola pasada
  // (matching jerárquico de TanStack) — actualizar_contrato REGENERA el
  // cronograma y puede reemplazar el set de co-titulares, así que las tres
  // cachés caducan juntas o el detalle reviviría datos viejos.
  cronograma: (contratoId: string) => [...crmQueryKeys.contratos(), contratoId, 'cronograma'] as const,
  titulares: (contratoId: string) => [...crmQueryKeys.contratos(), contratoId, 'titulares'] as const,
  clienteDetalle: (clienteId: string) => [...crmQueryKeys.clientes(), clienteId, 'detalle'] as const,
  cuentasBancarias: (clienteId: string, moneda: 'PEN' | 'USD') =>
    [...crmQueryKeys.clientes(), clienteId, 'cuentas-bancarias', moneda] as const,
  // Métricas de gerencia (RPCs crm.metricas_*_fn): misma raíz por lo mismo.
  metricas: () => [...crmQueryKeys.raiz, 'metricas'] as const,
  metricasCapital: (meses: number) => [...crmQueryKeys.metricas(), 'capital', meses] as const,
  metricasPagos: (meses: number) => [...crmQueryKeys.metricas(), 'pagos', meses] as const,
  metricasAltas: (meses: number) => [...crmQueryKeys.metricas(), 'altas', meses] as const,
  metricasVencimientos: (dias: number) => [...crmQueryKeys.metricas(), 'vencimientos', dias] as const,
  metricasDistribucionLeads: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'distribucion-leads', desde, hasta] as const,
  metricasAgenda: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'agenda-equipo', desde, hasta] as const,
  metricasConversiones: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'conversiones', desde, hasta] as const,
  // Clave PROPIA y no una variante de la anterior: el payload es distinto (el del
  // equipo no trae los agregados de empresa) y el ÁMBITO depende de quién pregunta.
  // Compartir clave serviría a un supervisor la foto global cacheada por gerencia.
  metricasConversionesEquipo: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'conversiones-equipo', desde, hasta] as const,
  metricasReuniones: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'reuniones', desde, hasta] as const,
  // Métricas del ÁMBITO OPERATIVO (RPC de F1: los tiles dejan de contar filas).
  // Prefijo PROPIO, separado de metricas(): el puente transitorio del store
  // (persistir/resincronizarReal) las invalida tras CADA mutación de leads, y
  // hacerlo sobre metricas() refrescaría también las fotografías por periodo
  // de gerencia en cada llamada del vendedor. Se retira en F3.
  metricasAmbito: () => [...crmQueryKeys.raiz, 'metricas-ambito'] as const,
  resumenCartera: () => [...crmQueryKeys.metricasAmbito(), 'resumen-cartera'] as const,
  colaAccion: (limite: number) => [...crmQueryKeys.metricasAmbito(), 'cola-accion', limite] as const,
  metricasVendedores: () => [...crmQueryKeys.metricasAmbito(), 'metricas-vendedores'] as const,
  // Cuelga del MISMO prefijo aunque su ámbito sea la cola GLOBAL (no el del
  // usuario): es lo que la hace caducar con el logout (queryClient.clear) y lo
  // que permite invalidarla por prefijo desde la pantalla de reparto.
  resumenReparto: () => [...crmQueryKeys.metricasAmbito(), 'resumen-reparto'] as const,
  // Cartera paginada por keyset (F2). Prefijo PROPIO `leads`: las mutaciones
  // que aún pasan por el store lo invalidan entero (resincronizarReal), y una
  // invalidación de leads no debe arrastrar las fotografías por periodo de
  // gerencia ni al revés.
  leads: () => [...crmQueryKeys.raiz, 'leads'] as const,
  // Los filtros forman parte de la clave: con keyset NO se puede filtrar en el
  // cliente sobre lo ya cargado (mentiría con vacíos falsos), así que cada
  // combinación es una lista distinta con su propio cursor.
  carteraPagina: (etapa: string, vendedor: string, texto: string) =>
    [...crmQueryKeys.leads(), 'cartera-pagina', etapa, vendedor, texto] as const,
}

// ── Cartera del portal (clientes + contratos) ─────────────────────────────────
// Sin retry propio: query-client.ts lo desactiva adrede (supabase-js >= 2.102 ya
// reintenta las lecturas transitorias; dos capas multiplicarían tráfico justo
// cuando el backend está degradado). `habilitada=false` = modo demo: una sesión
// demo no tiene Supabase y ni un request debe salir (fail-closed) — es DOBLE
// defensa, porque cada pantalla ya bifurca a su variante demo antes del hook.

/** Contratos visibles (vista crm.contratos_cartera, ya scopeada por la RLS).
 * Su clave crmQueryKeys.contratos() es CONTRATO público: la pantalla Clientes
 * la invalida tras crear un contrato para que esta tabla refresque sin reload. */
export function useContratos(habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.contratos(),
    queryFn: ({ signal }) => listarMisContratos(signal),
    enabled: habilitada,
  })
}

/** Cartera de clientes (vista crm.clientes_basicos, ya scopeada por la RLS).
 * La comparten la pantalla Clientes y el selector de "+ Contrato" en Contratos:
 * misma clave = el selector abre instantáneo si la cartera está fresca. */
export function useClientes(habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.clientes(),
    queryFn: ({ signal }) => listarClientes(signal),
    enabled: habilitada,
  })
}

/**
 * UNA fila de la cartera de contratos SIN query nueva: `select` sobre la MISMA
 * clave contratos() — abrir el detalle desde la tabla NO re-descarga la lista
 * (fresca < 30 s viene de caché) y cualquier invalidación de contratos() lo
 * refresca también. `data === null` con éxito significa "fuera de tu cartera o
 * inexistente" (la RLS ya recortó): el caller decide el mensaje.
 */
export function useContrato(contratoId: string, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.contratos(),
    queryFn: ({ signal }) => listarMisContratos(signal),
    select: (filas) => filas.find((f) => f.id === contratoId) ?? null,
    enabled: habilitada,
  })
}

/** Cronograma del contrato (RPC cronograma_contrato_fn; RLS fail-closed: ajeno = 0 filas). */
export function useCronograma(contratoId: string, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.cronograma(contratoId),
    queryFn: ({ signal }) => obtenerCronograma(contratoId, signal),
    enabled: habilitada,
  })
}

/**
 * Co-titulares del contrato. `opciones.staleTime: 0` existe para la PRECARGA
 * que blinda un UPDATE destructivo (contrato-corregir: la clave 'titulares'
 * presente REEMPLAZA el set completo en el servidor) — ese form debe revalidar
 * SIEMPRE al abrir, jamás fiarse de una copia cacheada por el detalle. El
 * detalle (solo lectura) usa el staleTime por defecto.
 */
export function useTitulares(
  contratoId: string,
  habilitada = true,
  opciones: { staleTime?: number } = {},
) {
  return useQuery({
    queryKey: crmQueryKeys.titulares(contratoId),
    queryFn: ({ signal }) => obtenerTitulares(contratoId, signal),
    enabled: habilitada,
    ...opciones,
  })
}

/**
 * Detalle completo del cliente — la precarga del form "corregir" (cliente-form).
 * `staleTime: 0` OBLIGATORIO y fijo: el UPDATE viaja con el set completo de
 * campos (bancarios incluidos); precargar de una caché vieja pisaría en el
 * servidor lo que otro dispositivo/sesión ya corrigió.
 */
export function useClienteDetalle(clienteId: string, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.clienteDetalle(clienteId),
    queryFn: ({ signal }) => obtenerClienteDetalle(clienteId, signal),
    enabled: habilitada,
    staleTime: 0,
  })
}

/**
 * Cuentas elegibles para un contrato nuevo. Siempre obsoletas al desmontar:
 * son datos sensibles y una cuenta puede haberse versionado en otra sesión.
 */
export function useCuentasBancariasCliente(
  clienteId: string,
  moneda: 'PEN' | 'USD',
  habilitada = true,
) {
  return useQuery({
    queryKey: crmQueryKeys.cuentasBancarias(clienteId, moneda),
    queryFn: ({ signal }) => listarCuentasBancariasCliente(clienteId, moneda, signal),
    enabled: habilitada,
    staleTime: 0,
    // No retener números/CCI al cerrar el modal; al reabrir siempre se pide una
    // fotografía autorizada y fresca al servidor.
    gcTime: 0,
  })
}

// ── Métricas del ámbito operativo (F1) — SOLO sesión real (`habilitada`): en
//    demo el MISMO shape lo calcula lib/resumen-cartera sobre el estado vivo y
//    NUNCA se toca la red (fail-closed). Las pantallas no usan este hook a pelo:
//    consumen data/use-resumen-cartera-operativo, que decide la fuente. ─────────

export function useResumenCartera(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.resumenCartera(),
    queryFn: ({ signal }) => listarResumenCartera(signal),
    enabled: habilitada,
  })
}

// refetchInterval 60 s: los buckets de la cola y los «días sin actividad»
// dependen del RELOJ, no solo de mutaciones — antes el cliente los recalculaba
// con useAhora cada minuto; el snapshot servido debe refrescarse igual o un
// lead cruza su umbral (3 d de seguimiento, 5 d de estancado) sin que la
// pantalla se entere mientras la pestaña siga enfocada (revisión Codex).
export function useColaAccion(habilitada: boolean, limite: number) {
  return useQuery({
    queryKey: crmQueryKeys.colaAccion(limite),
    queryFn: ({ signal }) => listarColaAccion(limite, signal),
    enabled: habilitada,
    refetchInterval: 60_000,
  })
}

export function useMetricasVendedores(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.metricasVendedores(),
    queryFn: ({ signal }) => listarMetricasVendedores(signal),
    enabled: habilitada,
    refetchInterval: 60_000,
  })
}

// La «espera más larga» de la cola la calcula el servidor con su propio now():
// depende del RELOJ, no solo de las mutaciones. Sin intervalo, un lead que cruza
// su primer día no movería el tile mientras la pestaña siga abierta — misma
// doctrina que cola_accion y metricas_vendedores.
export function useResumenReparto(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.resumenReparto(),
    queryFn: ({ signal }) => listarResumenReparto(signal),
    enabled: habilitada,
    refetchInterval: 60_000,
  })
}

// ── Cartera paginada por cursor keyset (F2) ───────────────────────────────────

/**
 * Páginas de la cartera servidas por `crm.cartera_pagina_fn`. SOLO sesión real:
 * en demo la pantalla pagina el ámbito vivo del store (fail-closed, ni un
 * request sale). Los filtros van en la clave Y en el request: filtrar en el
 * cliente sobre lo ya cargado es exactamente lo que el keyset hace imposible.
 */
export function useCarteraInfinita(habilitada: boolean, filtros: FiltrosCartera) {
  const etapa = filtros.etapa ?? 'todas'
  const vendedor = filtros.vendedorId ?? 'todos'
  const texto = filtros.texto ?? ''
  return useInfiniteQuery({
    queryKey: crmQueryKeys.carteraPagina(etapa, vendedor, texto),
    queryFn: ({ pageParam, signal }) => listarCarteraPagina(filtros, pageParam, signal),
    initialPageParam: null as CursorCartera | null,
    // `cursor: null` significa "no hay más" y lo decide el SERVIDOR (pidió una
    // fila de más y no llegó), nunca el tamaño de la última página.
    getNextPageParam: (ultima: PaginaCartera) => ultima.cursor,
    enabled: habilitada,
  })
}

// ── Métricas de gerencia — SOLO sesión real (`habilitada`): en demo las
//    gráficas se alimentan de agregados de fixtures y NUNCA se toca la red. ─────

export function useMetricasCapitalMes(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.metricasCapital(meses),
    queryFn: ({ signal }) => listarMetricasCapitalMes(meses, signal),
    enabled: habilitada,
  })
}

export function useMetricasPagosMes(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.metricasPagos(meses),
    queryFn: ({ signal }) => listarMetricasPagosMes(meses, signal),
    enabled: habilitada,
  })
}

export function useMetricasAltasAnalista(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.metricasAltas(meses),
    queryFn: ({ signal }) => listarMetricasAltasAnalista(meses, signal),
    enabled: habilitada,
  })
}

export function useMetricasVencimientos(habilitada: boolean, dias = 90) {
  return useQuery({
    queryKey: crmQueryKeys.metricasVencimientos(dias),
    queryFn: ({ signal }) => listarMetricasVencimientos(dias, signal),
    enabled: habilitada,
  })
}

interface ConsultaMetricaPorPeriodo<TData> {
  queryKey: QueryKey
  cargar: (signal: AbortSignal) => Promise<TData>
  habilitada: boolean
  desde: string
  hasta: string
}

/** Contrato común de las fotografías F2: misma habilitación fail-closed y el
 * periodo siempre forma parte de la clave y del payload del RPC. */
function useMetricaPorPeriodo<TData>({
  queryKey,
  cargar,
  habilitada,
  desde,
  hasta,
}: ConsultaMetricaPorPeriodo<TData>) {
  return useQuery({
    queryKey,
    queryFn: ({ signal }) => cargar(signal),
    enabled: habilitada && Boolean(desde) && Boolean(hasta),
  })
}

/**
 * Fotografía V1 de distribución/capacidad/SLA para un periodo inclusivo en
 * America/Lima. Las fechas forman parte de la clave: cambiar el periodo nunca
 * reutiliza silenciosamente la fotografía anterior.
 */
export function useMetricasDistribucionLeads(
  habilitada: boolean,
  desde: string,
  hasta: string,
) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasDistribucionLeads(desde, hasta),
    cargar: (signal) => listarMetricasDistribucionLeads(desde, hasta, signal),
    habilitada,
    desde,
    hasta,
  })
}

/**
 * Fotografía V1 de la agenda del equipo (toques, cierres de reuniones y carga
 * viva por miembro) para un periodo inclusivo en America/Lima. Igual que en
 * distribución, las fechas forman parte de la clave: cambiar el periodo nunca
 * reutiliza silenciosamente la fotografía anterior.
 */
export function useMetricasAgenda(
  habilitada: boolean,
  desde: string,
  hasta: string,
) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasAgenda(desde, hasta),
    cargar: (signal) => listarMetricasAgenda(desde, hasta, signal),
    habilitada,
    desde,
    hasta,
  })
}

export function useMetricasConversiones(
  habilitada: boolean,
  desde: string,
  hasta: string,
) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasConversiones(desde, hasta),
    cargar: (signal) => listarMetricasConversiones(desde, hasta, signal),
    habilitada,
    desde,
    hasta,
  })
}

/** Ranking de conversión del equipo del actor (decisión #10, parte b2). */
export function useMetricasConversionesEquipo(
  habilitada: boolean,
  desde: string,
  hasta: string,
) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasConversionesEquipo(desde, hasta),
    cargar: (signal) => listarMetricasConversionesEquipo(desde, hasta, signal),
    habilitada,
    desde,
    hasta,
  })
}

export function useMetricasReuniones(
  habilitada: boolean,
  desde: string,
  hasta: string,
) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasReuniones(desde, hasta),
    cargar: (signal) => listarMetricasReuniones(desde, hasta, signal),
    habilitada,
    desde,
    hasta,
  })
}

export interface ActualizarCapacidadLeadsObjetivoVariables {
  analistaId: string
  capacidad: number | null
}

/** Mutación de Gerencia; el prefijo invalida todas las fotografías métricas. */
export function useActualizarCapacidadLeadsObjetivo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ analistaId, capacidad }: ActualizarCapacidadLeadsObjetivoVariables) =>
      actualizarCapacidadLeadsObjetivo(analistaId, capacidad),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: crmQueryKeys.metricas() })
    },
  })
}
