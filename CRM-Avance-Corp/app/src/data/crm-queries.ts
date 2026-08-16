import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
  type QueryKey,
} from '@tanstack/react-query'
import type { CursorCartera, FiltrosCartera, PaginaCartera } from './crm-api'
import type {
  AnularCierreAvanceDatos,
  AnularCierreExternoDatos,
  ConvertirLeadExternoDatos,
  CorregirCierreExternoDatos,
} from './crm-api'
import { normalizarLeadIds } from '@/lib/cierre-estado'
import {
  actualizarCapacidadLeadsObjetivo,
  anularCierreAvance,
  anularCierreExterno,
  convertirLeadExterno,
  corregirCierreExterno,
  obtenerCierreMesEstado,
  obtenerCierresEstado,
  obtenerCierresExternos,
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
  obtenerConversionMensual,
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
  // La conversión mensual ponderada (LA definición). También con clave propia y
  // por el mismo motivo: el ámbito lo recorta el servidor según quién pregunta.
  conversionMensual: (periodo: string) =>
    [...crmQueryKeys.metricas(), 'conversion-mensual', periodo] as const,
  // El estado de la maquinaria del cierre de MES (no de los cierres de venta).
  // Sin parámetros: habla del reloj, no del período que se esté mirando.
  cierreMesEstado: () => [...crmQueryKeys.raiz, 'cierre-mes-estado'] as const,
  // Cierres en cooperativas (Qorilazo/Prodelco). Clave propia bajo metricas():
  // el ámbito lo recorta el servidor. El builder SIN periodo existe para que la
  // mutación de convertir invalide todos los meses cacheados de una pasada.
  cierresExternosPrefijo: () => [...crmQueryKeys.metricas(), 'cierres-externos'] as const,
  cierresExternos: (periodo: string) =>
    [...crmQueryKeys.cierresExternosPrefijo(), periodo] as const,
  // El estado del cierre (canal + anulación) de un LOTE de leads. Cuelga del
  // prefijo métrico —anular mueve cuota y conversión— y la clave incluye los ids
  // YA normalizados: sin eso cada render pediría lo mismo con una clave nueva.
  cierresEstadoPrefijo: () => [...crmQueryKeys.metricas(), 'cierres-estado'] as const,
  cierresEstado: (leadIds: readonly string[]) =>
    [...crmQueryKeys.cierresEstadoPrefijo(), leadIds.join(',')] as const,
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
 * Cuentas del cliente (ledger + casilla del perfil): las elige el contrato
 * nuevo y las muestra la ficha "Ver detalle". Siempre obsoletas al desmontar:
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

/**
 * La conversión mensual ponderada (crm.conversion_mensual_fn). No pasa por
 * `useMetricaPorPeriodo` a propósito: ese molde exige desde+hasta y esta RPC es
 * MENSUAL por contrato — un solo argumento, el primer día del mes.
 */
export function useConversionMensual(habilitada: boolean, periodo: string) {
  return useQuery({
    queryKey: crmQueryKeys.conversionMensual(periodo),
    queryFn: ({ signal }) => obtenerConversionMensual(periodo, signal),
    enabled: habilitada && Boolean(periodo),
  })
}

/**
 * El estado de la maquinaria del cierre de mes (`crm.cierre_mes_estado_fn`).
 * Es ADVISORY para las pantallas: si esta consulta cae, ninguna acción se
 * habilita de más — el candado real vive en el servidor (trigger 22023 y
 * guardias de `cerrar_periodo`), y el fallo solo apaga avisos.
 */
export function useCierreMesEstado(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.cierreMesEstado(),
    queryFn: ({ signal }) => obtenerCierreMesEstado(signal),
    enabled: habilitada,
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

// ── Cierres externos en cooperativas (Qorilazo / Prodelco) ────────────────────

/**
 * La fotografía de cierres externos (crm.cierres_externos_fn): la sección
 * «En cooperativas» de Mi cartera y el desglose «Por empresa» de supervisor y
 * gerencia. MENSUAL por contrato, como la conversión: un solo argumento, el
 * primer día del mes (las filas y los totales son históricos del ámbito; lo
 * mensual es el bloque por_empresa).
 */
export function useCierresExternos(habilitada: boolean, periodo: string) {
  return useQuery({
    queryKey: crmQueryKeys.cierresExternos(periodo),
    queryFn: ({ signal }) => obtenerCierresExternos(periodo, signal),
    enabled: habilitada && Boolean(periodo),
  })
}

/**
 * Convertir cerrando en una COOPERATIVA. Invalida las cuatro fotografías que
 * el cierre mueve: los cierres externos (todos los meses cacheados), la
 * conversión mensual, la cartera paginada (el lead cambió de etapa) y los
 * tiles del ámbito. El cumplimiento de metas NO vive en TanStack (lo carga el
 * store): el llamador debe refrescarlo por su vía, igual que el flujo Avance.
 */
export function useConvertirLeadExterno() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: ConvertirLeadExternoDatos) => convertirLeadExterno(datos),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.cierresExternosPrefijo() }),
        queryClient.invalidateQueries({
          queryKey: [...crmQueryKeys.metricas(), 'conversion-mensual'],
        }),
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.leads() }),
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.metricasAmbito() }),
      ])
    },
  })
}

/** Corrección de gerencia sobre un cierre externo (monto/cooperativa/n.º de
 * operación/certificado/vencimiento/nota). El prefijo métrico cubre cierres y
 * cuota; la conversión NO se mueve (corregir no cambia si hubo cierre o no). */
export function useCorregirCierreExterno() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: CorregirCierreExternoDatos) => corregirCierreExterno(datos),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: crmQueryKeys.metricas() })
    },
  })
}

/**
 * Anulación de gerencia. A diferencia de corregir, esto SÍ mueve la conversión
 * del vendedor —un cierre anulado deja de contar como ganado—, así que invalida
 * lo mismo que convertir: cierres, conversión mensual y los tiles del ámbito.
 * La cartera no hace falta (el lead sigue convertido: no se reabre).
 */
export function useAnularCierreExterno() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: AnularCierreExternoDatos) => anularCierreExterno(datos),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.cierresExternosPrefijo() }),
        queryClient.invalidateQueries({
          queryKey: [...crmQueryKeys.metricas(), 'conversion-mensual'],
        }),
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.metricasAmbito() }),
        // El chip «CIERRE ANULADO» de la cartera sale de cierres_estado_fn, que
        // responde por los DOS canales: anular en cooperativa también lo mueve.
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.cierresEstadoPrefijo() }),
      ])
    },
  })
}

/**
 * El estado del cierre de los leads que hay EN PANTALLA (canal y anulación).
 *
 * Se pide por lote y no por período a propósito: así sirve igual a la ficha de
 * un lead viejo que a una página de cartera, y no crece con el histórico.
 */
export function useCierresEstado(habilitada: boolean, leadIds: readonly string[]) {
  // Normalizado ANTES de la clave: dos renders con los mismos leads en otro
  // orden —o con uno repetido— tienen que compartir caché, no pelearse por ella.
  const ids = normalizarLeadIds(leadIds)
  return useQuery({
    queryKey: crmQueryKeys.cierresEstado(ids),
    queryFn: ({ signal }) => obtenerCierresEstado(ids, signal),
    enabled: habilitada && ids.length > 0,
  })
}

/**
 * Anulación de gerencia sobre un cierre de AVANCE. Mueve las mismas fotografías
 * que su gemela de cooperativas —conversión mensual y tiles del ámbito— más el
 * estado del cierre, que es de donde sale la marca en pantalla.
 *
 * ⚠️ El CUMPLIMIENTO DE METAS no vive en TanStack (lo carga el store), así que
 * esta invalidación no lo alcanza: quien llame debe hacer además `recargar()`.
 * Sin eso, el desglose resta cifras frescas de un cumplimiento viejo — es el bug
 * que ya se midió en cooperativas.
 *
 * La cartera tampoco hace falta: el lead sigue convertido, no se reabre.
 */
export function useAnularCierreAvance() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: AnularCierreAvanceDatos) => anularCierreAvance(datos),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.cierresEstadoPrefijo() }),
        queryClient.invalidateQueries({
          queryKey: [...crmQueryKeys.metricas(), 'conversion-mensual'],
        }),
        queryClient.invalidateQueries({ queryKey: crmQueryKeys.metricasAmbito() }),
      ])
    },
  })
}
