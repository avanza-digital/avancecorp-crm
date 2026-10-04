import { useEffect, useRef } from 'react'
import type { DecisionSolicitudTasa, EstadoSolicitudTasa, IntencionContrato, PublicacionPoliticaRentabilidad } from './crm-api'
import type { CategoriaContrato } from '@/lib/cronograma'
import type { CifraDetalle } from '@/lib/base-gestion'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { senalarSolicitudTasaCreada } from '@/lib/respuestas-tasa'
import { useInfiniteQuery, useMutation, useQueries, useQuery, useQueryClient, type InfiniteData, type QueryClient, type QueryKey } from '@tanstack/react-query'
import type { CursorCartera, FiltrosCartera, PaginaCartera } from './crm-api'
import type {
  AnularCierreAvanceDatos,
  AnularCierreExternoDatos,
  ConvertirLeadExternoDatos,
  CorregirCierreExternoDatos,
} from './crm-api'
import { normalizarLeadIds } from '@/lib/cierre-estado'
import type { ConversionMensual } from '@/lib/conversion-mensual'
import type { MetricasConversionesEquipo } from '@/lib/metricas-conversiones-equipo'
import { cumplimientoDesdeRpc } from '@/lib/objetivos'
import {
  actualizarCapacidadLeadsObjetivo,
  anularCierreAvance,
  anularCierreExterno,
  convertirLeadExterno,
  corregirCierreExterno,
  derivarLeadsEquipo,
  obtenerCierreMesEstado,
  obtenerCierresEstado,
  obtenerConversionEstado,
  obtenerCierresExternos,
  listarCarteraPagina,
  listarActividadesCliente,
  listarClientes,
  listarColaAccion,
  listarCuentasBancariasCliente,
  listarMetricasAgenda,
  listarMetricasVendedores,
  listarReporteDerivacionesEquipo,
  listarResumenCartera,
  listarActividadesRecientes,
  buscarLeadsGlobal,
  listarLeadsSinAsignar,
  listarLeadsPropios,
  obtenerBaseGestion,
  leerBaseGestion,
  baseGestionResumen,
  baseGestionResumenDetalle,
  registrarIntentoBase,
  reactivarLeadBase,
  marcarNoContactar,
  levantarNoContactar,
  listarResumenReparto,
  listarMetricasConversiones,
  listarMetricasConversionesEquipo,
  obtenerConversionMensual,
  obtenerCumplimientoMetas,
  obtenerRankingOrigenVendedor,
  listarMetricasReuniones,
  listarAltasNuevasPorAnalista,
  listarFacturacionDiaria,
  listarObservacionRentabilidad,
  listarSolicitudesTasa,
  type OpcionesSolicitudesTasa,
  obtenerHistorialTasaCliente,
  obtenerPoliticaRentabilidad,
  publicarPoliticaRentabilidad,
  resolverSolicitudTasa,
  resolverTasa,
  responderTopeTasa,
  solicitarTasa,
  listarMetricasCapitalMes,
  listarMetricasDistribucionLeadsV3,
  listarMetricasPagosMes,
  listarMetricasVencimientos,
  listarMisContratos,
  listarOperacionesCartera,
  obtenerResumenCarteraClientes,
  listarReconocimientosAlertas,
  listarRecordatoriosDisponibilidad,
  obtenerClienteDetalle,
  obtenerClienteFichaComercial,
  obtenerSegundoNumeroDelCliente,
  obtenerCronograma,
  obtenerDatosLegalesContrato,
  obtenerAtribucionContrato,
  obtenerTitulares,
  revertirDerivacionEquipo,
  type DerivacionEquipoPendiente,
  listarActividadesDeLead,
  type CursorHistorial,
  type PaginaHistorial,
} from './crm-api'
import { SENALES_VACIAS, type SenalesLead } from '@/lib/historial-lead'
import type { Actividad } from '@/lib/tipos'

// Fase 4e «sin topes» (20/09/2026): el store ya NO carga la foto del ámbito;
// cada pantalla pide al servidor lo que muestra (cartera por cursor, columnas
// del Pipeline, bandeja sin analista, cartera propia, búsqueda global) y el
// store solo conoce lo que las pantallas le registran (`conocerLeads`).
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
  metricasSla: (desde: string, hasta: string) => [...crmQueryKeys.metricas(), 'sla', desde, hasta] as const,
  estadoSlaLeads: () => [...crmQueryKeys.raiz, 'sla', 'estado-leads'] as const,
  recordatoriosDisponibilidad: () =>
    [...crmQueryKeys.raiz, 'recordatorios-disponibilidad'] as const,
  reconocimientosAlertas: () =>
    [...crmQueryKeys.raiz, 'reconocimientos-alertas'] as const,
  // Cartera del portal (panel del analista): bajo la misma raíz para que el
  // logout (queryClient.clear) y las invalidaciones jerárquicas la cubran.
  clientes: () => [...crmQueryKeys.raiz, 'clientes'] as const,
  contratos: () => [...crmQueryKeys.raiz, 'contratos'] as const,
  operacionesCartera: () => [...crmQueryKeys.contratos(), 'operaciones-cartera'] as const,
  // Detalle POR REGISTRO colgado del PREFIJO de su lista: invalidar contratos()
  // tras corregir cubre lista + cronograma + titulares de UNA sola pasada
  // (matching jerárquico de TanStack) — actualizar_contrato REGENERA el
  // cronograma y puede reemplazar el set de co-titulares, así que las tres
  // cachés caducan juntas o el detalle reviviría datos viejos.
  cronograma: (contratoId: string) => [...crmQueryKeys.contratos(), contratoId, 'cronograma'] as const,
  titulares: (contratoId: string) => [...crmQueryKeys.contratos(), contratoId, 'titulares'] as const,
  atribucion: (contratoId: string) => [...crmQueryKeys.contratos(), contratoId, 'atribucion'] as const,
  clienteFichaComercial: (clienteId: string) =>
    [...crmQueryKeys.clientes(), clienteId, 'ficha-comercial'] as const,
  clienteDetalle: (clienteId: string) => [...crmQueryKeys.clientes(), clienteId, 'detalle'] as const,
  actividadesCliente: (clienteId: string) =>
    [...crmQueryKeys.clientes(), clienteId, 'actividades-comerciales'] as const,
  // Historial de UN lead (F2 §5, Fase 1 «sin topes»): por registro y colgado
  // de un prefijo propio para que `resincronizarReal` lo invalide de una
  // pasada tras cada mutación; bajo la raíz para que el logout lo borre.
  historialLeads: () => [...crmQueryKeys.raiz, 'historial-lead'] as const,
  historialLead: (leadId: string) => [...crmQueryKeys.historialLeads(), leadId] as const,
  datosLegalesContrato: (clienteId: string) =>
    [...crmQueryKeys.clientes(), clienteId, 'datos-legales-contrato'] as const,
  cuentasBancarias: (clienteId: string, moneda: 'PEN' | 'USD') =>
    [...crmQueryKeys.clientes(), clienteId, 'cuentas-bancarias', moneda] as const,
  // Métricas de gerencia (RPCs crm.metricas_*_fn): misma raíz por lo mismo.
  metricas: () => [...crmQueryKeys.raiz, 'metricas'] as const,
  resumenCarteraClientes: (actorId?: string | null) =>
    [...crmQueryKeys.metricas(), 'cartera-clientes', actorId ?? null] as const,
  metricasCapital: (meses: number) => [...crmQueryKeys.metricas(), 'capital', meses] as const,
  metricasPagos: (meses: number) => [...crmQueryKeys.metricas(), 'pagos', meses] as const,
  altasNuevas: (meses: number) => [...crmQueryKeys.metricas(), 'altas-nuevas', meses] as const,
  facturacionDiaria: (mes: string) => [...crmQueryKeys.metricas(), 'facturacion-diaria', mes] as const,
  observacionRentabilidad: (dias: number) => [...crmQueryKeys.metricas(), 'observacion-rentabilidad', dias] as const,
  // Rentabilidad R1/R3: el núcleo de la tasa, las solicitudes, el historial por cliente y la política.
  rentabilidad: () => [...crmQueryKeys.raiz, 'rentabilidad'] as const,
  resolucionTasa: (clienteId: string, categoria: string, origenId: string | null) =>
    [...crmQueryKeys.rentabilidad(), 'resolver', clienteId, categoria, origenId ?? null] as const,
  solicitudesTasa: (estados: readonly string[] | null, opciones?: OpcionesSolicitudesTasa) =>
    [...crmQueryKeys.rentabilidad(), 'solicitudes', estados ? [...estados].sort().join(',') : 'todas', opciones?.soloMias ? 'mias' : 'ambito', opciones?.clienteId ?? 'todos', opciones?.limite ?? 200, ...(opciones?.leadId ? ['lead', opciones.leadId] : [])] as const,
  historialTasaCliente: (clienteId: string) => [...crmQueryKeys.rentabilidad(), 'historial', clienteId] as const,
  politicaRentabilidad: () => [...crmQueryKeys.rentabilidad(), 'politica'] as const,
  metricasVencimientos: (dias: number) => [...crmQueryKeys.metricas(), 'vencimientos', dias] as const,
  metricasDistribucionLeads: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'distribucion-leads', desde, hasta] as const,
  metricasDistribucionLeadsV3: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricas(), 'distribucion-leads-v3', desde, hasta] as const,
  metricasAgendaPrefijo: () => [...crmQueryKeys.metricas(), 'agenda-equipo'] as const,
  metricasAgenda: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricasAgendaPrefijo(), desde, hasta] as const,
  metricasConversionesPrefijo: () => [...crmQueryKeys.metricas(), 'conversiones'] as const,
  metricasConversiones: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricasConversionesPrefijo(), desde, hasta] as const,
  // Clave PROPIA y no una variante de la anterior: el payload es distinto (el del
  // equipo no trae los agregados de empresa) y el ÁMBITO depende de quién pregunta.
  // Compartir clave serviría a un supervisor la foto global cacheada por gerencia.
  metricasConversionesEquipoPrefijo: () => [...crmQueryKeys.metricas(), 'conversiones-equipo'] as const,
  metricasConversionesEquipo: (
    desde: string,
    hasta: string,
    alcance: MetricasConversionesEquipo['alcance'],
    actorId?: string | null,
  ) => [
    ...crmQueryKeys.metricasConversionesEquipoPrefijo(),
    desde,
    hasta,
    alcance,
    alcance === 'global' ? null : (actorId ?? null),
  ] as const,
  // La conversión mensual ponderada (LA definición). Periodo + alcance + actor
  // impiden compartir una foto propia, de equipo y global bajo la misma clave.
  conversionMensualPrefijo: () => [...crmQueryKeys.metricas(), 'conversion-mensual'] as const,
  conversionMensual: (
    periodo: string,
    alcance: ConversionMensual['alcance'],
    actorId?: string | null,
  ) => [
    ...crmQueryKeys.conversionMensualPrefijo(),
    periodo,
    alcance,
    alcance === 'global' ? null : (actorId ?? null),
  ] as const,
  // Foto mensual autoritativa de metas + producción confirmada. La RPC ya
  // conserva identidad y jerarquía del snapshot; mes + actor impiden servir la
  // adaptación de un supervisor a otro observador del mismo QueryClient.
  cumplimientoMetasPrefijo: () => [...crmQueryKeys.metricas(), 'cumplimiento-metas'] as const,
  cumplimientoMetasPeriodo: (periodo: string) =>
    [...crmQueryKeys.cumplimientoMetasPrefijo(), periodo] as const,
  cumplimientoMetas: (periodo: string, actorId?: string | null) =>
    [...crmQueryKeys.cumplimientoMetasPeriodo(periodo), actorId ?? null] as const,
  rankingOrigenesPrefijo: () => [...crmQueryKeys.metricas(), 'ranking-origenes'] as const,
  rankingOrigenes: (periodo: string, vendedorId: string, actorId?: string | null) =>
    [...crmQueryKeys.rankingOrigenesPrefijo(), periodo, vendedorId, actorId ?? null] as const,
  // El estado de la maquinaria del cierre de MES (no de los cierres de venta).
  // Sin parámetros: habla del reloj, no del período que se esté mirando.
  cierreMesEstado: () => [...crmQueryKeys.raiz, 'cierre-mes-estado'] as const,
  // Cierres en cooperativas (Qorilazo/Prodelco). Clave propia bajo metricas():
  // el ámbito lo recorta el servidor. El builder SIN periodo existe para que la
  // mutación de convertir invalide todos los meses cacheados de una pasada.
  cierresExternosPrefijo: () => [...crmQueryKeys.metricas(), 'cierres-externos'] as const,
  cierresExternos: (periodo: string) => [...crmQueryKeys.cierresExternosPrefijo(), periodo] as const,
  // El estado del cierre (canal + anulación) de un LOTE de leads. Cuelga del
  // prefijo métrico —anular mueve cuota y conversión— y la clave incluye los ids
  // YA normalizados: sin eso cada render pediría lo mismo con una clave nueva.
  cierresEstadoPrefijo: () => [...crmQueryKeys.metricas(), 'cierres-estado'] as const,
  cierresEstado: (leadIds: readonly string[]) => [...crmQueryKeys.cierresEstadoPrefijo(), leadIds.join(',')] as const,
  conversionEstadoLead: (leadId: string) => [...crmQueryKeys.cierresEstadoPrefijo(), 'conversion-v1', leadId] as const,
  metricasReunionesPrefijo: () => [...crmQueryKeys.metricas(), 'reuniones'] as const,
  metricasReuniones: (desde: string, hasta: string) =>
    [...crmQueryKeys.metricasReunionesPrefijo(), desde, hasta] as const,
  citasGerenciaPrefijo: () => [...crmQueryKeys.metricasReunionesPrefijo(), 'detalle'] as const,
  citasGerencia: (actorId: string | null, mes: string) =>
    [...crmQueryKeys.citasGerenciaPrefijo(), actorId, mes] as const,
  // Métricas del ÁMBITO OPERATIVO (RPC de F1: los tiles dejan de contar filas).
  // Prefijo PROPIO, separado de metricas(): el puente transitorio del store
  // (persistir/resincronizarReal) las invalida tras CADA mutación de leads, y
  // hacerlo sobre metricas() refrescaría también las fotografías por periodo
  // de gerencia en cada llamada del analista. Se retira en F3.
  metricasAmbito: () => [...crmQueryKeys.raiz, 'metricas-ambito'] as const,
  resumenCartera: () => [...crmQueryKeys.metricasAmbito(), 'resumen-cartera'] as const,
  // Bitácora de Hoy · Directorio (Fase 3 «sin topes»): cuelga del prefijo de
  // métricas del ámbito para que cada mutación la invalide como a los tiles.
  actividadesRecientes: (limite: number) => [...crmQueryKeys.metricasAmbito(), 'actividades-recientes', limite] as const,
  // Buscador global (Fase 4a): una lista por texto; cuelga de `leads` para que
  // una mutación de lead la invalide como al resto de listas de leads.
  busquedaGlobal: (texto: string) => [...crmQueryKeys.leads(), 'busqueda-global', texto] as const,
  // Bandeja sin analista (Fase 4c): cuelga de `leads` (repartir/derivar la invalida).
  leadsSinAsignar: () => [...crmQueryKeys.leads(), 'sin-asignar'] as const,
  // Los leads del propio analista (Fase 4d): Hoy · Analista sin la foto inicial.
  leadsPropios: () => [...crmQueryKeys.leads(), 'propios'] as const,
  // Base para gestión (02/10/2026): cuelga de `leads` para que descartar o reabrir un lead en
  // cualquier pantalla la invalide como al resto de listas de leads.
  baseGestionPrefijo: () => [...crmQueryKeys.leads(), 'base-gestion'] as const,
  // El DÍA de Lima es parte de la identidad de la foto (Codex F4 r1): «para llamar hoy», los intentos de hoy y el
  // orden los calcula el servidor para un día; al cruzar la medianoche no se reutiliza la respuesta de ayer.
  baseGestion: (vendedorId: string | null, dia: string) => [...crmQueryKeys.baseGestionPrefijo(), vendedorId, dia] as const,
  // Vista del supervisor (F4): la base del ámbito entero (con o sin los «No contactar»), el panel por analista y el
  // detalle de una cifra. Bajo el mismo prefijo: toda escritura en la base (o en un lead) los refresca juntos.
  baseGestionEquipo: (incluirVetados: boolean, dia: string) => [...crmQueryKeys.baseGestionPrefijo(), 'equipo', incluirVetados, dia] as const,
  baseGestionResumen: (dia: string) => [...crmQueryKeys.baseGestionPrefijo(), 'resumen', dia] as const,
  /** `periodo`: el día de Lima para «intentos de hoy», el mes ('YYYY-MM') para «reactivaciones del mes». */
  baseGestionResumenDetalle: (vendedorId: string, cifra: CifraDetalle, periodo: string) => [...crmQueryKeys.baseGestionPrefijo(), 'resumen-detalle', vendedorId, cifra, periodo] as const,
  colaAccion: (limite: number) => [...crmQueryKeys.metricasAmbito(), 'cola-accion', limite] as const,
  // Aunque la RPC resuelve el mes vigente con su propio reloj, el período es
  // parte de la identidad de la foto: al cruzar medianoche en Lima no se puede
  // reutilizar la respuesta del mes que acaba de cerrar.
  metricasVendedores: (periodo: string) =>
    [...crmQueryKeys.metricasAmbito(), 'metricas-vendedores', periodo] as const,
  reporteDerivacionesEquipoPrefijo: () => [...crmQueryKeys.metricasAmbito(), 'reporte-derivaciones-equipo'] as const,
  reporteDerivacionesEquipo: (desde: string, hasta: string) =>
    [...crmQueryKeys.reporteDerivacionesEquipoPrefijo(), desde, hasta] as const,
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
  // La procedencia también es parte de la clave: si solo cambiara el request,
  // TanStack Query serviría la lista anterior sin volver a pedir (P1 de Codex, 19/09).
  // La gestión, igual y con más motivo: «Nuevo» y «Gestionado» del Pipeline son
  // la MISMA etapa y el mismo analista — sin ella en la clave compartirían
  // caché y las dos columnas pintarían la misma lista. `null` = sin recorte.
  // El potencial (Frío · Tibio · Estrella · sin marca), por el mismo motivo.
  carteraPagina: (etapa: string, vendedor: string, texto: string, integrada = false, desde: string | null = null, hasta: string | null = null, origen = 'todos', procedencia = 'todas', reasignados = false, gestion: string | null = null, potencial: string | null = null) =>
    [...crmQueryKeys.carteraPaginas(), etapa, vendedor, texto, integrada, desde, hasta, origen, procedencia, reasignados, gestion, potencial] as const,
  /** Prefijo de TODAS las listas de la cartera (cualquier combinación de filtros). */
  carteraPaginas: () => [...crmQueryKeys.leads(), 'cartera-pagina'] as const,
}

// Política interna única de caché para mutaciones que cambian atribución o
// cierres. Mantener aquí las familias comunes evita que un flujo nuevo refresque
// solo una de las tres fotografías de conversión y deje rankings desalineados.
const CLAVES_FOTOS_POR_PERIODO = [
  crmQueryKeys.metricasConversionesPrefijo(),
  crmQueryKeys.metricasConversionesEquipoPrefijo(),
  crmQueryKeys.metricasReunionesPrefijo(),
  crmQueryKeys.conversionMensualPrefijo(),
  crmQueryKeys.cumplimientoMetasPrefijo(),
] as const satisfies readonly QueryKey[]

const CLAVES_INVALIDACION_COMERCIAL = {
  derivacionEquipo: [
    crmQueryKeys.reporteDerivacionesEquipoPrefijo(),
    crmQueryKeys.metricasAmbito(),
    ...CLAVES_FOTOS_POR_PERIODO,
    crmQueryKeys.leads(),
  ],
  conversionExterna: [
    crmQueryKeys.cierresEstadoPrefijo(),
    crmQueryKeys.cierresExternosPrefijo(),
    ...CLAVES_FOTOS_POR_PERIODO,
    crmQueryKeys.leads(),
    crmQueryKeys.metricasAmbito(),
  ],
  anulacionExterna: [
    crmQueryKeys.cierresExternosPrefijo(),
    ...CLAVES_FOTOS_POR_PERIODO,
    crmQueryKeys.metricasAmbito(),
    // El chip «CIERRE ANULADO» de la cartera sale de cierres_estado_fn, que
    // responde por los DOS canales: anular en cooperativa también lo mueve.
    crmQueryKeys.cierresEstadoPrefijo(),
  ],
  anulacionAvance: [
    crmQueryKeys.cierresEstadoPrefijo(),
    ...CLAVES_FOTOS_POR_PERIODO,
    crmQueryKeys.metricasAmbito(),
  ],
} as const satisfies Record<string, readonly QueryKey[]>

/** La primera lectura en vuelo también puede preceder a la escritura. Se
 * cancela antes de invalidar para no reutilizar una respuesta anterior. */
export async function invalidarMetricasCitas(cliente: QueryClient, incluirResumen = false) {
  const queryKey = incluirResumen ? crmQueryKeys.metricasReunionesPrefijo() : crmQueryKeys.citasGerenciaPrefijo()
  await cliente.cancelQueries({ queryKey })
  await cliente.invalidateQueries({ queryKey })
}

async function invalidarLecturasComerciales(cliente: QueryClient, claves: readonly QueryKey[]) {
  const prefijo = crmQueryKeys.citasGerenciaPrefijo()
  await cliente.cancelQueries({ queryKey: prefijo })
  await Promise.all([
    cliente.invalidateQueries({ queryKey: prefijo }),
    ...claves.map(queryKey => cliente.invalidateQueries({
      queryKey,
      // El detalle ya se refresca arriba, aunque la lista cambie de alcance.
      predicate: consulta => !prefijo.every((parte, i) => consulta.queryKey[i] === parte),
    })),
  ])
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

/** Renovaciones/upgrades del ámbito con su separación económica. */
export function useOperacionesCartera(habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.operacionesCartera(),
    queryFn: ({ signal }) => listarOperacionesCartera(signal),
    enabled: habilitada,
  })
}

/** Sólo se conecta en ámbitos globales conciliados; no sustituye el fallback de otros roles. */
export function useResumenCarteraClientes(habilitada: boolean, actorId?: string | null) {
  return useQuery({
    queryKey: crmQueryKeys.resumenCarteraClientes(actorId),
    queryFn: ({ signal }) => obtenerResumenCarteraClientes(signal),
    enabled: habilitada,
    refetchInterval: 60_000,
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
export function useTitulares(contratoId: string, habilitada = true, opciones: { staleTime?: number } = {}) {
  return useQuery({
    queryKey: crmQueryKeys.titulares(contratoId),
    queryFn: ({ signal }) => obtenerTitulares(contratoId, signal),
    enabled: habilitada,
    ...opciones,
  })
}

/**
 * De quién es la venta (P-055 Fase 3). `staleTime: 0`: tras reasignar hay que
 * ver el cambio y su motivo al instante, no dentro de 30 s.
 */
export function useAtribucionContrato(contratoId: string, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.atribucion(contratoId),
    queryFn: ({ signal }) => obtenerAtribucionContrato(contratoId, signal),
    enabled: habilitada,
    staleTime: 0,
  })
}

/**
  * Identidad y contacto de la Ficha 360. Usa una frontera/caché propia para no
  * mezclarla con el detalle sensible que precarga el formulario Corregir.
  */
export function useClienteFichaComercial(clienteId: string, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.clienteFichaComercial(clienteId),
    queryFn: ({ signal }) => obtenerClienteFichaComercial(clienteId, signal),
    enabled: habilitada,
    staleTime: 0,
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

/** El 2.º número del lead que originó al cliente (ver obtenerSegundoNumeroDelCliente). */
export function useSegundoNumeroCliente(clienteId: string, habilitada = true) {
  return useQuery({
    queryKey: [...crmQueryKeys.clienteDetalle(clienteId), 'segundo-numero'],
    queryFn: ({ signal }) => obtenerSegundoNumeroDelCliente(clienteId, signal),
    enabled: habilitada,
  })
}

/** Timeline postventa: no toca el SLA ni las etapas de leads. */
export function useActividadesCliente(clienteId: string, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.actividadesCliente(clienteId),
    queryFn: ({ signal }) => listarActividadesCliente(clienteId, signal),
    enabled: habilitada,
  })
}

/**
 * Qué dato legal le falta al cliente (o al propio analista) para poder emitir
 * el contrato. `staleTime: 0` OBLIGATORIO: entre abrir el formulario y pulsar
 * "Crear contrato" otra sesión puede haber rellenado el domicilio, y bloquear
 * el alta contra una caché vieja sería inventarse un muro que ya no existe.
 */
export function useDatosLegalesContrato(clienteId: string, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.datosLegalesContrato(clienteId),
    queryFn: ({ signal }) => obtenerDatosLegalesContrato(clienteId, signal),
    enabled: habilitada,
    staleTime: 0,
  })
}

/**
 * Cuentas del cliente (ledger + casilla del perfil): las elige el contrato
 * nuevo y las muestra la ficha "Ver detalle". Siempre obsoletas al desmontar:
 * son datos sensibles y una cuenta puede haberse versionado en otra sesión.
 */
export function useCuentasBancariasCliente(clienteId: string, moneda: 'PEN' | 'USD', habilitada = true) {
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

/**
 * Las N gestiones más recientes visibles (Fase 3 «sin topes»): sustituye a
 * la descarga del registro entero que el arranque hacía para pintar 8 filas.
 * Se refresca al volver a la pestaña y cada minuto: es un feed, no una foto.
 */
export function useActividadesRecientes(habilitada: boolean, limite: number) {
  return useQuery({
    queryKey: crmQueryKeys.actividadesRecientes(limite),
    queryFn: ({ signal }) => listarActividadesRecientes(limite, signal),
    enabled: habilitada,
    staleTime: 30_000,
    refetchInterval: 60_000,
    refetchOnWindowFocus: 'always',
  })
}

/**
 * Buscador global de la barra (Fase 4a «sin topes»): `texto` ya viene
 * normalizado y por encima del mínimo (`textoBuscable`), o `null` cuando no
 * hay nada que pedir. Sin `keepPreviousData`: la barra solo pinta la lista de
 * la consulta del texto actual (una lista anterior dejaba elegir con Enter un
 * resultado ajeno al texto; Codex 20/09).
 */
export function useBusquedaGlobal(texto: string | null, habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.busquedaGlobal(texto ?? ''),
    queryFn: ({ signal }) => buscarLeadsGlobal(texto ?? '', signal),
    enabled: habilitada && texto !== null,
    staleTime: 30_000,
  })
}

/**
 * Bandeja de leads sin analista (Fase 4c «sin topes»): Equipo, Derivaciones y
 * Hoy · Supervisor la piden al servidor en vez de filtrar la foto inicial.
 */
export function useLeadsSinAsignar(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.leadsSinAsignar(),
    queryFn: ({ signal }) => listarLeadsSinAsignar(signal),
    enabled: habilitada,
    staleTime: 30_000,
    refetchOnWindowFocus: 'always',
  })
}

/** Los leads del propio analista (Fase 4d «sin topes»), por cursor hasta agotar su cartera. */
export function useLeadsPropios(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.leadsPropios(),
    queryFn: ({ signal }) => listarLeadsPropios(signal),
    enabled: habilitada,
    staleTime: 30_000,
    refetchOnWindowFocus: 'always',
  })
}

/**
 * El día de Lima ('YYYY-MM-DD') del reloj vivo (`useAhora`: cada minuto y al volver a la pestaña). Entra en la clave
 * de las lecturas de la base: al cruzar la medianoche la clave cambia, la consulta se repite SIN quitar el foco y la
 * foto de ayer no se presenta como de hoy (sin `placeholderData` entre días: mientras llega, «cargando»). Todas las
 * pantallas lo derivan igual, así que «Hoy» del analista y su base siguen compartiendo UNA petición.
 */
export function useDiaLima(): string {
  return fechaLima(useAhora())
}

/** Base para gestión del actor (analista: la suya; Supervisión y Gerencia: su ámbito o un analista).
 *  SOLO sesión real. Sin intervalo: el orden cambia con los intentos y con el día; lo primero ya la
 *  invalida (mutación de lead) y lo segundo cambia la clave (el día de Lima es parte de ella). */
export function useBaseGestion(habilitada: boolean, vendedorId: string | null = null) {
  const dia = useDiaLima()
  return useQuery({
    queryKey: crmQueryKeys.baseGestion(vendedorId, dia),
    queryFn: ({ signal }) => obtenerBaseGestion(vendedorId, { signal }),
    enabled: habilitada,
    staleTime: 30_000,
    refetchOnWindowFocus: 'always',
  })
}

/** Tras escribir en la base: la lista (contador, orden, quién sale) y el historial de ESE lead. Una reactivación
 *  devuelve el lead a la cartera: también se refresca todo lo que cuelga de `leads()` (la base vive debajo). */
async function invalidarBaseGestion(queryClient: QueryClient, leadId: string, alPipeline: boolean) {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: alPipeline ? crmQueryKeys.leads() : crmQueryKeys.baseGestionPrefijo() }),
    queryClient.invalidateQueries({ queryKey: crmQueryKeys.historialLead(leadId) }),
  ])
}

export function useRegistrarIntentoBase() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: registrarIntentoBase,
    onSuccess: async (respuesta, entrada) => { await invalidarBaseGestion(queryClient, entrada.leadId, respuesta.reactivado) },
  })
}

export function useReactivarLeadBase() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: reactivarLeadBase,
    onSuccess: async (_respuesta, entrada) => { await invalidarBaseGestion(queryClient, entrada.leadId, true) },
  })
}

export function useMarcarNoContactarBase() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (entrada: { leadId: string; motivo: string }) => marcarNoContactar(entrada.leadId, entrada.motivo),
    onSuccess: async (_r, entrada) => { await invalidarBaseGestion(queryClient, entrada.leadId, false) },
  })
}

/**
 * La base del ámbito entero para Supervisión y Gerencia (F4): UNA carga, filtros y páginas en el navegador. Con
 * `incluirVetados` pide también los «No contactar» (B6b). Al encender o apagar el interruptor, la hoja conserva lo
 * que ya mostraba mientras llega la otra lista (no se vacía ni pierde la posición). SOLO sesión real.
 */
export function useBaseGestionEquipo(habilitada: boolean, incluirVetados: boolean) {
  const dia = useDiaLima()
  return useQuery({
    queryKey: crmQueryKeys.baseGestionEquipo(incluirVetados, dia),
    queryFn: ({ signal }) => leerBaseGestion(null, { incluirVetados, signal }),
    enabled: habilitada,
    staleTime: 30_000,
    refetchOnWindowFocus: 'always',
    // Solo entre las dos listas del MISMO día (el interruptor): la foto de ayer nunca hace de la de hoy.
    placeholderData: (anterior, consultaAnterior) => (consultaAnterior?.queryKey.at(-1) === dia ? anterior : undefined),
  })
}

/** El panel por analista (F4). Las cifras de HOY y del mes dependen del reloj: el día de Lima va en la clave. */
export function useBaseGestionResumen(habilitada: boolean) {
  const dia = useDiaLima()
  return useQuery({
    queryKey: crmQueryKeys.baseGestionResumen(dia),
    queryFn: ({ signal }) => baseGestionResumen(signal),
    enabled: habilitada,
    staleTime: 30_000,
    refetchOnWindowFocus: 'always',
  })
}

/** El detalle de una cifra del panel; solo mientras está abierto. `null` en `data` = el servidor aún no lo tiene. */
export function useBaseGestionResumenDetalle(habilitada: boolean, vendedorId: string | null, cifra: CifraDetalle | null) {
  const dia = useDiaLima()
  // Los intentos son de HOY (cambian a medianoche); las reactivaciones, del MES (cambian al empezar el mes).
  const periodo = cifra === 'reactivaciones_mes' ? dia.slice(0, 7) : dia
  return useQuery({
    queryKey: crmQueryKeys.baseGestionResumenDetalle(vendedorId ?? '', cifra ?? 'intentos_hoy', periodo),
    queryFn: ({ signal }) => baseGestionResumenDetalle(vendedorId ?? '', cifra ?? 'intentos_hoy', signal),
    enabled: habilitada && vendedorId !== null && cifra !== null,
    staleTime: 30_000,
  })
}

/** Quitar «No contactar» (D5): se levanta para la persona y TODOS sus leads, que pueden estar en otras listas
 *  (cartera, pipeline): se refresca todo lo que cuelga de `leads()` (la base incluida, con la marca de cada lead). El
 *  historial, solo el de ESE lead: el servidor escribe la actividad «Levantado No contactar» únicamente sobre
 *  `p_lead_id` (migración 20261002061500, líneas 235-236); en los otros leads de la persona solo cambia la marca. */
export function useLevantarNoContactarBase() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (entrada: { leadId: string; motivo: string }) => levantarNoContactar(entrada.leadId, entrada.motivo),
    onSuccess: async (_r, entrada) => { await invalidarBaseGestion(queryClient, entrada.leadId, true) },
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

export function useMetricasVendedores(habilitada: boolean, periodo: string) {
  return useQuery({
    queryKey: crmQueryKeys.metricasVendedores(periodo),
    queryFn: ({ signal }) => listarMetricasVendedores(periodo, signal),
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
    queryKey: crmQueryKeys.carteraPagina(etapa, vendedor, texto, filtros.integrada, filtros.recepcion?.desde, filtros.recepcion?.hasta, filtros.origen ?? 'todos', filtros.procedencia ?? 'todas', filtros.reasignados ?? false, filtros.gestion ?? null, filtros.potencial ?? null),
    queryFn: ({ pageParam, signal }) => listarCarteraPagina(filtros, pageParam, signal),
    initialPageParam: null as CursorCartera | null,
    // `cursor: null` significa "no hay más" y lo decide el SERVIDOR (pidió una
    // fila de más y no llegó), nunca el tamaño de la última página.
    getNextPageParam: (ultima: PaginaCartera) => ultima.cursor,
    enabled: habilitada,
  })
}

// ── Historial de UN lead por cursor keyset (F2 §5, Fase 1 «sin topes») ───────

/**
 * Páginas del historial de un lead servidas por `crm.actividades_de_lead_fn`.
 * SOLO sesión real: en demo el timeline es el del ámbito vivo del store y no
 * sale ni un request (fail-closed). Sin `refetchInterval`: el historial no
 * envejece contra el reloj; lo refresca `resincronizarReal` tras cada mutación.
 */
export function useHistorialLead(habilitada: boolean, leadId: string) {
  return useInfiniteQuery({
    queryKey: crmQueryKeys.historialLead(leadId),
    queryFn: ({ pageParam, signal }) => listarActividadesDeLead(leadId, pageParam, signal),
    initialPageParam: null as CursorHistorial | null,
    // `cursor: null` = no hay más, y lo decide el SERVIDOR (se pidió una fila
    // de más y no llegó), nunca el tamaño de la última página.
    getNextPageParam: (ultima: PaginaHistorial) => ultima.cursor,
    enabled: habilitada,
  })
}

/**
 * Lo que la caché ya sabe del historial de un lead, para los gates del store
 * (descartar por «no responde», retroceso al anular una reunión) que corren
 * fuera de React. `null` = nunca se cargó: el gate cae a su evidencia local.
 * `leidoEn` es el `dataUpdatedAt` de la consulta (ver lib/historial-lead.ts).
 */
export function leerHistorialEnCache(
  cliente: Pick<QueryClient, 'getQueryData' | 'getQueryState'>,
  leadId: string,
): { items: Actividad[]; senales: SenalesLead; leidoEn: number } | null {
  const clave = crmQueryKeys.historialLead(leadId)
  const datos = cliente.getQueryData<InfiniteData<PaginaHistorial>>(clave)
  if (!datos || datos.pages.length === 0) return null
  return {
    items: datos.pages.flatMap((p) => p.items),
    senales: datos.pages[0]?.senales ?? SENALES_VACIAS,
    leidoEn: cliente.getQueryState(clave)?.dataUpdatedAt ?? 0,
  }
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

/** Altas de contratos NUEVOS por analista que cierra (F7: sustituto del reporte viejo). */
export function useAltasNuevasPorAnalista(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.altasNuevas(meses),
    queryFn: ({ signal }) => listarAltasNuevasPorAnalista(meses, signal),
    enabled: habilitada,
  })
}

/**
 * Facturación de un mes comercial (pantalla de Gerencia). `mes` es 'YYYY-MM-01'.
 * El servidor ya agrupó, ya resolvió el ámbito y ya puso el supervisor de
 * entonces; aquí no se recalcula nada. Cuelga de `crmQueryKeys.raiz` para que el
 * cierre de sesión (`queryClient.clear`) la borre con todo lo demás.
 */
export function useFacturacionDiaria(habilitada: boolean, mes: string) {
  return useQuery({
    queryKey: crmQueryKeys.facturacionDiaria(mes),
    queryFn: ({ signal }) => listarFacturacionDiaria(mes, signal),
    enabled: habilitada && mes !== '',
    // Es un TABLERO: se deja abierto en una pantalla toda la mañana. Sin esto,
    // un cierre hecho por un analista no aparecía nunca hasta recargar — el
    // `staleTime` marca el dato como viejo, pero no va a buscarlo.
    // (Auditoría de Codex, 11/09/2026.)
    refetchInterval: 5 * 60_000,
    refetchOnWindowFocus: true,
  })
}

/**
 * Facturación de VARIOS meses a la vez — Miguel, 11/09/2026: «quiero poder
 * seleccionar los días que yo quiera, para ver el avance».
 *
 * Un rango elegido a mano puede cruzar meses, y la RPC del servidor entrega un
 * mes por llamada. Se piden todos los que toca el rango, con la MISMA clave de
 * caché que la consulta mensual: un mes ya traído no se vuelve a pedir.
 */
export function useFacturacionDeMeses(habilitada: boolean, meses: readonly string[]) {
  return useQueries({
    queries: meses.map((mes) => ({
      queryKey: crmQueryKeys.facturacionDiaria(mes),
      queryFn: ({ signal }: { signal: AbortSignal }) => listarFacturacionDiaria(mes, signal),
      enabled: habilitada && mes !== '',
      refetchInterval: 5 * 60_000,
      refetchOnWindowFocus: true,
    })),
  })
}

/** Rentabilidad R2: tarjeta de observación de Gerencia (últimos `dias`). */
export function useObservacionRentabilidad(habilitada: boolean, dias = 30) {
  return useQuery({
    queryKey: crmQueryKeys.observacionRentabilidad(dias),
    queryFn: ({ signal }) => listarObservacionRentabilidad(dias, signal),
    enabled: habilitada,
  })
}

/** Rentabilidad: qué tasa base dice el núcleo para un contrato en intención (solo con cliente y categoría). */
export function useResolucionTasa(clienteId: string, categoria: CategoriaContrato | '', contratoOrigenId: string | null, habilitada: boolean, leadId?: string) {
  return useQuery({
    queryKey: [...crmQueryKeys.resolucionTasa(clienteId, categoria, contratoOrigenId), ...(leadId ? ['lead', leadId] : [])],
    queryFn: ({ signal }) => resolverTasa(clienteId, categoria as CategoriaContrato, contratoOrigenId, signal, leadId),
    enabled: habilitada && (!!clienteId || !!leadId) && !!categoria && (categoria === 'nuevo' || !!contratoOrigenId),
    staleTime: 30_000,
    refetchInterval: 30_000,
    refetchOnWindowFocus: 'always',
  })
}

/** Rentabilidad: solicitudes de tasa visibles para el actor. Se refresca solo mientras hay pendientes que esperar. */
export function useSolicitudesTasa(estados: EstadoSolicitudTasa[] | null, habilitada: boolean, refrescarCadaMs: number | false = false, opciones?: OpcionesSolicitudesTasa) {
  return useQuery({
    queryKey: crmQueryKeys.solicitudesTasa(estados, opciones),
    queryFn: ({ signal }) => listarSolicitudesTasa(estados, signal, opciones),
    enabled: habilitada,
    refetchInterval: refrescarCadaMs,
  })
}

export function useHistorialTasaCliente(clienteId: string, habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.historialTasaCliente(clienteId),
    queryFn: ({ signal }) => obtenerHistorialTasaCliente(clienteId, signal),
    enabled: habilitada && !!clienteId,
  })
}

export function usePoliticaRentabilidad(habilitada: boolean, operativa = false) {
  return useQuery({
    queryKey: crmQueryKeys.politicaRentabilidad(),
    queryFn: ({ signal }) => obtenerPoliticaRentabilidad(signal),
    enabled: habilitada,
    refetchInterval: operativa ? 30_000 : false,
    refetchOnWindowFocus: operativa ? 'always' : true,
  })
}

function invalidarRentabilidad(queryClient: ReturnType<typeof useQueryClient>) {
  return Promise.all([
    queryClient.invalidateQueries({ queryKey: crmQueryKeys.rentabilidad() }),
    queryClient.invalidateQueries({ queryKey: [...crmQueryKeys.metricas(), 'observacion-rentabilidad'] }),
  ])
}

export function useSolicitarTasa() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: { intencion: IntencionContrato; tasaSolicitada: number; motivo: string }) =>
      solicitarTasa(input.intencion, input.tasaSolicitada, input.motivo),
    // La invalidación refresca esta pestaña; la señal avisa a las demás pestañas del navegador
    // para que pasen al ritmo activo del aviso de respuestas sin esperar su reposo.
    onSuccess: async () => { senalarSolicitudTasaCreada(); await invalidarRentabilidad(queryClient) },
  })
}

export function useResolverSolicitudTasa() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: { solicitudId: string; decision: DecisionSolicitudTasa; tasaMaxima: number | null; motivo: string | null }) =>
      resolverSolicitudTasa(input.solicitudId, input.decision, input.tasaMaxima, input.motivo),
    onSuccess: async () => { await invalidarRentabilidad(queryClient) },
  })
}

export function useResponderTopeTasa() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: { solicitudId: string; acepta: boolean; motivo: string | null }) =>
      responderTopeTasa(input.solicitudId, input.acepta, input.motivo),
    onSuccess: async () => { await invalidarRentabilidad(queryClient) },
  })
}

export function usePublicarPoliticaRentabilidad() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: PublicacionPoliticaRentabilidad) => publicarPoliticaRentabilidad(input),
    onSuccess: async () => { await invalidarRentabilidad(queryClient) },
  })
}

export function useMetricasPagosMes(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.metricasPagos(meses),
    queryFn: ({ signal }) => listarMetricasPagosMes(meses, signal),
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
function useMetricaPorPeriodo<TData>({ queryKey, cargar, habilitada, desde, hasta }: ConsultaMetricaPorPeriodo<TData>) {
  return useQuery({
    queryKey,
    queryFn: ({ signal }) => cargar(signal),
    enabled: habilitada && Boolean(desde) && Boolean(hasta),
  })
}

/**
 * Foto histórica de derivaciones del equipo directo del supervisor. La clave
 * contiene ambas fechas y el payload se valida de nuevo en crm-api.
 */
export function useReporteDerivacionesEquipo(habilitada: boolean, desde: string, hasta: string) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.reporteDerivacionesEquipo(desde, hasta),
    cargar: (signal) => listarReporteDerivacionesEquipo(desde, hasta, signal),
    habilitada,
    desde,
    hasta,
  })
}


/**
 * Fotografía V3 (F2.3b): la V2 más puntería servida, núcleo y sondas. Mudada
 * desde `data/metricas-distribucion-v3.ts` al integrarse las ramas — mismo
 * contrato fail-closed y el período siempre en la clave.
 */
export function useMetricasDistribucionLeadsV3(habilitada: boolean, desde: string, hasta: string) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasDistribucionLeadsV3(desde, hasta),
    cargar: (signal) => listarMetricasDistribucionLeadsV3(desde, hasta, signal),
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
export function useMetricasAgenda(habilitada: boolean, desde: string, hasta: string) {
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
  // Filtro de origen del lote (27/08): entra a la queryKey — cambiar el
  // filtro es OTRA consulta, jamas un payload viejo bajo un rotulo nuevo.
  origen: string | null = null,
) {
  return useMetricaPorPeriodo({
    queryKey: [...crmQueryKeys.metricasConversiones(desde, hasta), origen ?? 'todos'],
    cargar: (signal) => listarMetricasConversiones(desde, hasta, origen, signal),
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
export function useConversionMensual(
  habilitada: boolean,
  periodo: string,
  alcanceEsperado: ConversionMensual['alcance'],
  actorId?: string | null,
) {
  return useQuery({
    queryKey: crmQueryKeys.conversionMensual(periodo, alcanceEsperado, actorId),
    queryFn: ({ signal }) => obtenerConversionMensual(periodo, alcanceEsperado, signal),
    enabled: habilitada
      && Boolean(periodo)
      && (alcanceEsperado === 'global' || Boolean(actorId)),
  })
}

/**
 * Meta y producción del MISMO snapshot mensual (`crm.cumplimiento_metas_fn`).
 * No reconstruye objetivos ni resultados: solo adapta el payload autoritativo
 * ya recortado por el rol autenticado.
 */
export function useCumplimientoMetas(
  habilitada: boolean,
  periodo: string,
  actorId?: string | null,
) {
  return useQuery({
    queryKey: crmQueryKeys.cumplimientoMetas(periodo, actorId),
    queryFn: async ({ signal }) => {
      const respuesta = await obtenerCumplimientoMetas(periodo, signal)
      if (respuesta.periodo !== periodo) {
        throw new Error('La foto mensual recibida no corresponde al periodo solicitado')
      }
      return respuesta
    },
    select: (respuesta) => cumplimientoDesdeRpc(respuesta, actorId),
    enabled: habilitada && Boolean(periodo),
  })
}

/** Se consulta solo al abrir la ficha de un analista real del mes seleccionado. */
export function useRankingOrigenVendedor(
  habilitada: boolean,
  periodo: string,
  vendedorId: string | null,
  actorId?: string | null,
) {
  return useQuery({
    queryKey: crmQueryKeys.rankingOrigenes(periodo, vendedorId ?? '', actorId),
    queryFn: ({ signal }) => obtenerRankingOrigenVendedor(periodo, vendedorId!, signal),
    enabled: habilitada && Boolean(periodo) && Boolean(vendedorId) && Boolean(actorId),
  })
}

/**
 * Cada cuánto se re-pregunta el estado del ciclo con la pestaña abierta. El
 * estado cambia por CALENDARIO (medianoche de Lima) y por el cron (09:20):
 * sin intervalo, una pantalla dejada en un monitor jamás vería aparecer la
 * ALARMA de atascado — justo la que existe para no depender de que alguien
 * vuelva a mirar. Cinco minutos: 288 llamadas/día de una función trivial.
 */
export const INTERVALO_CIERRE_MES_ESTADO_MS = 5 * 60_000

/** Opciones de la consulta, puras para poder probarlas sin montar nada. */
export function opcionesCierreMesEstado(habilitada: boolean) {
  return {
    queryKey: crmQueryKeys.cierreMesEstado(),
    queryFn: ({ signal }: { signal?: AbortSignal }) => obtenerCierreMesEstado(signal),
    enabled: habilitada,
    refetchInterval: INTERVALO_CIERRE_MES_ESTADO_MS,
  }
}

/**
 * El estado de la maquinaria del cierre de mes (`crm.cierre_mes_estado_fn`).
 * Es ADVISORY para las pantallas: si esta consulta cae, ninguna acción se
 * habilita de más — el candado real vive en el servidor (trigger 22023 y
 * guardias de `cerrar_periodo`), y el fallo solo apaga avisos.
 */
export function useCierreMesEstado(habilitada: boolean) {
  const queryClient = useQueryClient()
  const consulta = useQuery(opcionesCierreMesEstado(habilitada))
  const ultimoCerradoVisto = useRef<string | null | undefined>(undefined)
  const ultimoCerrado = consulta.data?.ultimo_cerrado?.mes

  useEffect(() => {
    if (consulta.data === undefined) return
    const actual = ultimoCerrado ?? null
    const anterior = ultimoCerradoVisto.current
    ultimoCerradoVisto.current = actual
    if (actual === null || actual === anterior) return

    // La misma pantalla puede atravesar abierto → sellado por el sondeo de
    // cinco minutos. Cumplimiento y conversión sí publican el sello: se
    // refrescan primero. Cosecha no lo trae aún, por lo que se vuelve a pedir
    // DESPUÉS de esas dos fotos; así no puede ganar la carrera una respuesta
    // abierta emitida mientras el cron estaba cerrando el mes.
    void Promise.all([
      queryClient.invalidateQueries({ queryKey: crmQueryKeys.cumplimientoMetasPrefijo() }),
      queryClient.invalidateQueries({ queryKey: crmQueryKeys.conversionMensualPrefijo() }),
      queryClient.invalidateQueries({ queryKey: crmQueryKeys.rankingOrigenesPrefijo() }),
    ]).then(() => queryClient.invalidateQueries({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    }))
  }, [consulta.data, queryClient, ultimoCerrado])

  return consulta
}

/** Ranking de conversión del equipo/global (decisión #10, parte b2). */
export function useMetricasConversionesEquipo(
  habilitada: boolean,
  desde: string,
  hasta: string,
  alcanceEsperado: MetricasConversionesEquipo['alcance'],
  actorId?: string | null,
) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasConversionesEquipo(
      desde,
      hasta,
      alcanceEsperado,
      actorId,
    ),
    cargar: (signal) => listarMetricasConversionesEquipo(
      desde,
      hasta,
      alcanceEsperado,
      signal,
    ),
    habilitada: habilitada
      && (alcanceEsperado === 'global' || Boolean(actorId)),
    desde,
    hasta,
  })
}

export function useMetricasReuniones(habilitada: boolean, desde: string, hasta: string) {
  return useMetricaPorPeriodo({
    queryKey: crmQueryKeys.metricasReuniones(desde, hasta),
    cargar: (signal) => listarMetricasReuniones(desde, hasta, signal),
    habilitada,
    desde,
    hasta,
  })
}

/** El guardado invalida la foto histórica y los indicadores operativos. */
export function useDerivarLeadsEquipo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (derivaciones: readonly DerivacionEquipoPendiente[]) => derivarLeadsEquipo(derivaciones),
    onSuccess: async () => {
      await invalidarLecturasComerciales(queryClient, CLAVES_INVALIDACION_COMERCIAL.derivacionEquipo)
    },
  })
}

/** Devolver un lead también refresca la misma foto y la bandeja local. */
export function useRevertirDerivacionEquipo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (leadId: string) => revertirDerivacionEquipo(leadId),
    onSuccess: async () => {
      await invalidarLecturasComerciales(queryClient, CLAVES_INVALIDACION_COMERCIAL.derivacionEquipo)
    },
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
      await queryClient.invalidateQueries({
        queryKey: crmQueryKeys.metricas(),
      })
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
 * tiles del ámbito y el cumplimiento consultado por ranking. El snapshot que
 * aún conserva el store necesita además la recarga de su llamador.
 */
export function useConvertirLeadExterno() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: ConvertirLeadExternoDatos) => convertirLeadExterno(datos),
    onSuccess: async () => {
      await invalidarLecturasComerciales(queryClient, CLAVES_INVALIDACION_COMERCIAL.conversionExterna)
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
      await queryClient.invalidateQueries({
        queryKey: crmQueryKeys.metricas(),
      })
    },
  })
}

/**
 * Anulación de gerencia. A diferencia de corregir, esto SÍ mueve la conversión
 * del analista —un cierre anulado deja de contar como ganado—, así que invalida
 * lo mismo que convertir: cierres, conversión mensual y los tiles del ámbito.
 * La cartera no hace falta (el lead sigue convertido: no se reabre).
 */
export function useAnularCierreExterno() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: AnularCierreExternoDatos) => anularCierreExterno(datos),
    onSuccess: async () => {
      await invalidarLecturasComerciales(queryClient, CLAVES_INVALIDACION_COMERCIAL.anulacionExterna)
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

export function useConversionEstado(leadId: string) {
  return useQuery({
    queryKey: crmQueryKeys.conversionEstadoLead(leadId),
    queryFn: ({ signal }) => obtenerConversionEstado(leadId, signal),
  })
}

/**
 * Anulación de gerencia sobre un cierre de AVANCE. Mueve las mismas fotografías
 * que su gemela de cooperativas —conversión mensual y tiles del ámbito— más el
 * estado del cierre, que es de donde sale la marca en pantalla.
 *
 * La caché de cumplimiento usada por ranking sí queda invalidada aquí. El
 * snapshot paralelo que aún carga el store exige además `recargar()` en el
 * llamador; esta capa no puede actualizarlo sin tocar ese núcleo.
 *
 * La cartera tampoco hace falta: el lead sigue convertido, no se reabre.
 */
export function useAnularCierreAvance() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: AnularCierreAvanceDatos) => anularCierreAvance(datos),
    onSuccess: async () => {
      await invalidarLecturasComerciales(queryClient, CLAVES_INVALIDACION_COMERCIAL.anulacionAvance)
    },
  })
}

/**
 * F3 «Recordar»: los recordatorios personales del analista, para la campana
 * y para saber en el alta si un contacto ya tiene el suyo. Trae SOLO
 * contacto+fecha (jamás veredictos: la re-verificación es BAJO DEMANDA al
 * clic — regla del plan). El servidor caduca los vencidos >7 días solo.
 */
export function useRecordatoriosDisponibilidad(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.recordatoriosDisponibilidad(),
    queryFn: ({ signal }) => listarRecordatoriosDisponibilidad(signal),
    enabled: habilitada,
    staleTime: 60_000,
  })
}

/**
 * F4 «sin ruido»: el libro de reconocimientos del SUPERVISOR real, para
 * atenuar (reconocer) u ocultar (posponer) las alertas agrupadas de su
 * campana. El servidor solo caduca asientos a los 90 días; la VIGENCIA de
 * ≤7 días la aplica la lógica pura de reconocimientos-alertas.ts.
 */
export function useReconocimientosAlertas(habilitada: boolean) {
  return useQuery({
    queryKey: crmQueryKeys.reconocimientosAlertas(),
    queryFn: ({ signal }) => listarReconocimientosAlertas(signal),
    enabled: habilitada,
    staleTime: 60_000,
    // Codex F4.2 #3: staleTime no es polling. Sin esto, un asiento hecho en
    // OTRA pestaña/dispositivo no convergería aquí mientras la pestaña siga
    // enfocada — y una posposición que la vista del servidor ya venció
    // seguiría aplicada. La tabla es diminuta (≤4 alertas por supervisor).
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  })
}
