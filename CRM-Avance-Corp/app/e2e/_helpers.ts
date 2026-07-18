// Helpers compartidos de los E2E del CRM. Dos mundos:
//  - DEMO: login demo por rol (sin backend, datos de lib/demo.ts).
//  - REAL: sesión autenticada (yo.demo=false) con TODO el backend Supabase
//    interceptado (fail-closed) → prueba la ruta real sin tocar prod.
import { expect, type Page, type Route } from '@playwright/test'

export const ROLES_DEMO = ['Vendedor', 'Supervisor', 'Gerencia', 'Directorio'] as const
export type RolDemo = (typeof ROLES_DEMO)[number]

/** Entra a la demo con el rol dado y espera el workspace (nav lateral visible). */
export async function entrarDemo(page: Page, rol: RolDemo): Promise<void> {
  await page.goto('/')
  await page.getByRole('button', { name: /explorar en modo demo/i }).click()
  await page.getByRole('button', { name: new RegExp(`^${rol}`) }).click()
  await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible()
}

/** Navega al Pipeline (donde viven las cards de lead operables). */
export async function irAPipeline(page: Page): Promise<void> {
  await page.getByRole('button', { name: 'Pipeline' }).click()
  await expect(page.getByText('Nuevo', { exact: true }).first()).toBeVisible()
}

/** Abre la ficha (drawer) de un lead por su nombre desde el Pipeline.
 * El Sheet (Radix) queda etiquetado por el SheetTitle (aria-labelledby gana a
 * aria-label), así que el nombre accesible del dialog ES el nombre del lead. */
export async function abrirLead(page: Page, nombre: string | RegExp) {
  const card = page.getByRole('button', { name: nombre }).first()
  await card.scrollIntoViewIfNeeded()
  await card.click()
  const drawer = page.getByRole('dialog', { name: nombre })
  await expect(drawer).toBeVisible()
  return drawer
}

// ── Backend Supabase simulado para la RUTA REAL ───────────────────────────────

const SUPABASE_HOST = 'dctqcbznekcyxhjujuci.supabase.co'
export const UID = '00000000-0000-4000-8000-000000000abc'

/** JWT decodable (firma inválida a propósito: el servidor está mockeado). */
function jwtFalso(sub: string): string {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url')
  const header = b64({ alg: 'HS256', typ: 'JWT' })
  const payload = b64({
    sub, role: 'authenticated', aud: 'authenticated', iss: 'supabase',
    iat: 1_700_000_000, exp: 4_102_444_800, // exp año 2100
    email: 'qa-real@avancecorp.pe',
  })
  return `${header}.${payload}.firma-no-verificada`
}

const USER = {
  id: UID,
  aud: 'authenticated',
  role: 'authenticated',
  email: 'qa-real@avancecorp.pe',
  app_metadata: { provider: 'email' },
  user_metadata: {},
  created_at: '2026-01-01T00:00:00.000Z',
}

const SESSION = {
  access_token: jwtFalso(UID),
  token_type: 'bearer',
  expires_in: 3600,
  refresh_token: 'refresh-e2e',
  user: USER,
}

export interface LeadReal {
  id: string
  nombre_completo: string
  telefono: string
  correo: string | null
  dni: string | null
  distrito: string | null
  origen: string
  etapa: string
  motivo_descarte: string | null
  monto_estimado: number
  moneda: string
  categoria_interes: string | null
  vendedor_id: string | null
  asignado_supervisor_id: string | null
  creado_en: string
  actualizado_en: string
  activo: boolean
  nota: string | null
}

export function leadReal(over: Partial<LeadReal> = {}): LeadReal {
  return {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    nombre_completo: 'CLIENTE REAL UNO',
    telefono: '+51999000111',
    correo: null,
    dni: null,
    distrito: null,
    origen: 'landing',
    etapa: 'nuevo',
    motivo_descarte: null,
    monto_estimado: 10000,
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: 'vend-1',
    asignado_supervisor_id: null,
    creado_en: '2026-07-01T00:00:00.000Z',
    actualizado_en: '2026-07-01T00:00:00.000Z',
    activo: true,
    nota: null,
    ...over,
  }
}

// ── Clientes del portal (public.perfiles + vista crm.clientes_basicos) ────────
export interface PerfilReal {
  id: string
  nombre_completo: string
  nombres: string | null
  apellidos: string | null
  rol: string
  tipo_documento: string
  dni: string | null
  correo: string | null
  telefono: string | null
  activo: boolean
  asesor_perfil_id: string | null
  creado_por: string | null
  creado_en: string
  banco: string | null
  tipo_cuenta: string | null
  numero_cuenta: string | null
  cci: string | null
  titular_distinto: boolean
  beneficiario_nombre: string | null
  beneficiario_dni: string | null
  banco_usd: string | null
  tipo_cuenta_usd: string | null
  numero_cuenta_usd: string | null
  cci_usd: string | null
  titular_distinto_usd: boolean
  beneficiario_nombre_usd: string | null
  beneficiario_dni_usd: string | null
}

export function clienteReal(over: Partial<PerfilReal> = {}): PerfilReal {
  return {
    id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    nombre_completo: 'CLIENTE PORTAL UNO',
    nombres: 'CLIENTE',
    apellidos: 'PORTAL UNO',
    rol: 'cliente',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'cliente1@correo.pe',
    telefono: '+51999888777',
    activo: true,
    asesor_perfil_id: UID, // el creador queda como asesor → cae en su cartera
    creado_por: UID,
    creado_en: '2026-07-01T00:00:00.000Z',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: null,
    tipo_cuenta_usd: null,
    numero_cuenta_usd: null,
    cci_usd: null,
    titular_distinto_usd: false,
    beneficiario_nombre_usd: null,
    beneficiario_dni_usd: null,
    ...over,
  }
}

// ── Contratos del portal (public.contratos con el embed cliente:perfiles) ─────
export interface ContratoReal {
  id: string
  numero_contrato: string
  cliente_id: string
  capital: number
  moneda: string
  tasa_anual: number
  modalidad: string
  tipo_interes: string
  categoria: string | null
  estado: string
  fecha_inicio: string
  fecha_vencimiento: string
  notas_internas: string | null
  creado_por: string | null
  creado_en: string
  /** Plano, como lo devuelve la vista crm.contratos_cartera. */
  cliente_nombre: string | null
  asesor_perfil_id: string | null
}

export function contratoReal(over: Partial<ContratoReal> = {}): ContratoReal {
  return {
    id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    numero_contrato: '2026-01-000123',
    cliente_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    capital: 10000,
    moneda: 'PEN',
    tasa_anual: 15,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    categoria: 'nuevo',
    estado: 'activo',
    fecha_inicio: '2026-07-01',
    fecha_vencimiento: '2027-07-01',
    notas_internas: null,
    creado_por: UID,
    creado_en: '2026-07-01T00:00:00.000Z',
    cliente_nombre: 'CLIENTE PORTAL UNO',
    asesor_perfil_id: UID,
    ...over,
  }
}

const ROSTER = [
  { perfil_id: UID, nombre_completo: 'Gerente Real', rol_crm: 'gerencia', supervisor_id: null, activo: true },
  { perfil_id: 'vend-1', nombre_completo: 'Vendedor Real Uno', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
  { perfil_id: 'vend-2', nombre_completo: 'Vendedor Real Dos', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
]

export const ANALISTA_ANA_ID = '11111111-1111-4111-8111-111111111111'
const ANALISTA_BRUNO_ID = '22222222-2222-4222-8222-222222222222'
const SUPERVISOR_DIEGO_ID = '33333333-3333-4333-8333-333333333333'

const RANGOS_DISTRIBUCION = [
  { id: 'pen_0_1000', orden: 1, etiqueta: 'Hasta S/ 1 mil', desde_exclusivo: 0, hasta_inclusivo: 1000 },
  { id: 'pen_1000_5000', orden: 2, etiqueta: 'S/ 1 mil a 5 mil', desde_exclusivo: 1000, hasta_inclusivo: 5000 },
  { id: 'pen_5000_10000', orden: 3, etiqueta: 'S/ 5 mil a 10 mil', desde_exclusivo: 5000, hasta_inclusivo: 10000 },
  { id: 'pen_10000_20000', orden: 4, etiqueta: 'S/ 10 mil a 20 mil', desde_exclusivo: 10000, hasta_inclusivo: 20000 },
  { id: 'pen_20000_50000', orden: 5, etiqueta: 'S/ 20 mil a 50 mil', desde_exclusivo: 20000, hasta_inclusivo: 50000 },
  { id: 'pen_50000_100000', orden: 6, etiqueta: 'S/ 50 mil a 100 mil', desde_exclusivo: 50000, hasta_inclusivo: 100000 },
  { id: 'pen_mas_100000', orden: 7, etiqueta: 'Mas de S/ 100 mil', desde_exclusivo: 100000, hasta_inclusivo: null },
  { id: 'sin_monto', orden: 8, etiqueta: 'Sin monto valido', desde_exclusivo: null, hasta_inclusivo: null },
] as const

type RangoDistribucionId = (typeof RANGOS_DISTRIBUCION)[number]['id']
type ValoresRangoAnalista = readonly [
  carteraEpisodios: number,
  carteraCapital: number,
  episodiosRecibidos: number,
  leadsUnicosRecibidos: number,
  convertidos: number,
  descartados: number,
  leadsUnicosResueltos: number,
]

function rangosAnalista(
  valores: Partial<Record<RangoDistribucionId, ValoresRangoAnalista>> = {},
) {
  return RANGOS_DISTRIBUCION.map(({ id }) => {
    const [
      carteraEpisodios,
      carteraCapital,
      episodiosRecibidos,
      leadsUnicosRecibidos,
      convertidos,
      descartados,
      leadsUnicosResueltos,
    ] = valores[id] ?? [0, 0, 0, 0, 0, 0, 0]
    return {
      rango_id: id,
      cartera_actual: { episodios: carteraEpisodios, capital: carteraCapital },
      cohorte: {
        episodios_recibidos: episodiosRecibidos,
        leads_unicos_recibidos: leadsUnicosRecibidos,
        convertidos,
        descartados,
        leads_unicos_resueltos: leadsUnicosResueltos,
      },
    }
  })
}

function rangosCola(
  valores: Partial<Record<RangoDistribucionId, readonly [cantidad: number, capital: number]>> = {},
) {
  return RANGOS_DISTRIBUCION.map(({ id }) => {
    const [cantidad, capital] = valores[id] ?? [0, 0]
    return { rango_id: id, cantidad, capital }
  })
}

function fechaSiguiente(fecha: string): string {
  const dia = new Date(`${fecha}T00:00:00.000Z`)
  dia.setUTCDate(dia.getUTCDate() + 1)
  return dia.toISOString().slice(0, 10)
}

/**
 * Fotografía rica y contractual de `crm.metricas_distribucion_leads_fn`.
 * Los IDs son UUID válidos porque el parser de producción falla cerrado.
 */
export function metricasDistribucionReal(
  desde = '2026-04-19',
  hasta = '2026-07-17',
): unknown {
  const ana = {
    analista_id: ANALISTA_ANA_ID,
    nombre: 'Ana Capital',
    rol: 'vendedor',
    supervisor_id: SUPERVISOR_DIEGO_ID,
    supervisor_nombre: 'Diego Supervisor',
    activo: true,
    disponible_para_recibir: true,
    capacidad: { objetivo: 20, carga_activa: 8, carga_pen: 7, carga_usd: 1 },
    pen: {
      cartera_actual: { episodios: 7, capital: 134300 },
      cohorte: {
        episodios_recibidos: 6,
        leads_unicos_recibidos: 6,
        convertidos: 3,
        descartados: 3,
        ciclos_resueltos: 6,
        leads_unicos_resueltos: 6,
      },
      rangos: rangosAnalista({
        pen_0_1000: [1, 800, 1, 1, 0, 1, 1],
        pen_1000_5000: [2, 7000, 3, 3, 2, 1, 3],
        pen_5000_10000: [1, 7500, 2, 2, 1, 1, 2],
        pen_10000_20000: [1, 15000, 0, 0, 0, 0, 0],
        pen_20000_50000: [1, 30000, 0, 0, 0, 0, 0],
        pen_50000_100000: [1, 74000, 0, 0, 0, 0, 0],
      }),
    },
    usd_no_segmentado: {
      cartera_actual_episodios: 1,
      cartera_actual_capital: 2000,
      cohorte_episodios_recibidos: 1,
      cohorte_leads_unicos: 1,
      convertidos: 1,
      descartados: 0,
    },
    operacion: {
      cohorte_episodios: 7,
      contactos: 6,
      sla_evaluables: 6,
      sla_en_24h: 5,
      primer_contacto_mediana_minutos: 45,
      transferidos: 1,
      parqueados: 0,
      desactivados: 0,
      sin_tocar_actual: 1,
      estancados_actual: 2,
    },
  }

  const bruno = {
    analista_id: ANALISTA_BRUNO_ID,
    nombre: 'Bruno Crecimiento',
    rol: 'vendedor',
    supervisor_id: SUPERVISOR_DIEGO_ID,
    supervisor_nombre: 'Diego Supervisor',
    activo: true,
    disponible_para_recibir: true,
    capacidad: { objetivo: 12, carga_activa: 4, carga_pen: 4, carga_usd: 0 },
    pen: {
      cartera_actual: { episodios: 4, capital: 151000 },
      cohorte: {
        episodios_recibidos: 4,
        leads_unicos_recibidos: 4,
        convertidos: 1,
        descartados: 3,
        ciclos_resueltos: 4,
        leads_unicos_resueltos: 4,
      },
      rangos: rangosAnalista({
        pen_0_1000: [1, 1000, 1, 1, 0, 1, 1],
        pen_5000_10000: [1, 10000, 1, 1, 1, 0, 1],
        pen_10000_20000: [1, 20000, 1, 1, 0, 1, 1],
        pen_mas_100000: [1, 120000, 1, 1, 0, 1, 1],
      }),
    },
    usd_no_segmentado: {
      cartera_actual_episodios: 0,
      cartera_actual_capital: 0,
      cohorte_episodios_recibidos: 0,
      cohorte_leads_unicos: 0,
      convertidos: 0,
      descartados: 0,
    },
    operacion: {
      cohorte_episodios: 4,
      contactos: 3,
      sla_evaluables: 4,
      sla_en_24h: 2,
      primer_contacto_mediana_minutos: 180,
      transferidos: 1,
      parqueados: 1,
      desactivados: 0,
      sin_tocar_actual: 1,
      estancados_actual: 1,
    },
  }

  const totalRangos = rangosCola({
    pen_1000_5000: [1, 5000],
    pen_10000_20000: [1, 20000],
  })
  const globalRangos = rangosCola({ pen_1000_5000: [1, 5000] })
  const bandejaRangos = rangosCola({ pen_10000_20000: [1, 20000] })

  return {
    version: 1,
    generado_en: '2026-07-17T17:00:00.000Z',
    cohorte: {
      desde_inclusivo: desde,
      hasta_inclusivo: hasta,
      hasta_exclusivo: fechaSiguiente(hasta),
      criterio: 'episodio_asignado_en',
      zona_horaria: 'America/Lima',
    },
    alcances: {
      matriz: 'PEN',
      capacidad: 'TODAS_LAS_MONEDAS',
      operacion_sla: 'TODAS_LAS_MONEDAS',
    },
    rangos: RANGOS_DISTRIBUCION.map((rango) => ({ ...rango })),
    resumen: {
      leads_operativos_actuales: 15,
      asignados_actuales: 12,
      por_repartir_actuales: 3,
      capital_pen_asignado_actual: 285300,
      capital_usd_asignado_actual: 2000,
      cohorte_episodios: 11,
      cohorte_leads_unicos: 10,
      convertidos_pen: 4,
      descartados_pen: 6,
      sla_evaluables: 10,
      sla_en_24h: 7,
    },
    analistas: [ana, bruno],
    por_repartir: {
      total: {
        carga_total: 3,
        pen: { cantidad: 2, capital: 25000, rangos: totalRangos },
        usd: { cantidad: 1, capital: 1000 },
      },
      global: {
        responsabilidad: 'gerencia',
        carga_total: 2,
        pen: { cantidad: 1, capital: 5000, rangos: globalRangos },
        usd: { cantidad: 1, capital: 1000 },
      },
      bandejas: [{
        supervisor_id: SUPERVISOR_DIEGO_ID,
        supervisor_nombre: 'Diego Supervisor',
        supervisor_activo: true,
        carga_total: 1,
        pen: { cantidad: 1, capital: 20000, rangos: bandejaRangos },
        usd: { cantidad: 0, capital: 0 },
      }],
    },
    calidad: {
      episodios_aproximados_actuales: 0,
      episodios_aproximados_cohorte: 0,
      episodios_sin_monto_actuales: 0,
      episodios_sin_monto_cohorte: 0,
    },
  }
}

function metricasDistribucionVaciaReal(): unknown {
  const base = metricasDistribucionReal()
  if (!esRegistro(base)) return base
  return {
    ...base,
    resumen: {
      leads_operativos_actuales: 0,
      asignados_actuales: 0,
      por_repartir_actuales: 0,
      capital_pen_asignado_actual: 0,
      capital_usd_asignado_actual: 0,
      cohorte_episodios: 0,
      cohorte_leads_unicos: 0,
      convertidos_pen: 0,
      descartados_pen: 0,
      sla_evaluables: 0,
      sla_en_24h: 0,
    },
    analistas: [],
    por_repartir: {
      total: {
        carga_total: 0,
        pen: { cantidad: 0, capital: 0, rangos: rangosCola() },
        usd: { cantidad: 0, capital: 0 },
      },
      global: {
        responsabilidad: 'gerencia',
        carga_total: 0,
        pen: { cantidad: 0, capital: 0, rangos: rangosCola() },
        usd: { cantidad: 0, capital: 0 },
      },
      bandejas: [],
    },
  }
}

function esRegistro(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === 'object' && valor !== null && !Array.isArray(valor)
}

function metricasParaPeriodo(payload: unknown, desde: string, hasta: string): unknown {
  if (!esRegistro(payload) || !esRegistro(payload.cohorte)) return payload
  return {
    ...payload,
    cohorte: {
      ...payload.cohorte,
      desde_inclusivo: desde,
      hasta_inclusivo: hasta,
      hasta_exclusivo: fechaSiguiente(hasta),
    },
  }
}

function actualizarCapacidadMock(
  payload: unknown,
  analistaId: string,
  capacidad: number | null,
): void {
  if (!esRegistro(payload) || !Array.isArray(payload.analistas)) return
  const analista = payload.analistas.find(
    (item) => esRegistro(item) && item.analista_id === analistaId,
  )
  if (!esRegistro(analista) || !esRegistro(analista.capacidad)) return
  analista.capacidad.objetivo = capacidad
}

/** Estado mutable del backend simulado — cada test ajusta los "modos de fallo". */
export interface BackendReal {
  leads: LeadReal[]
  rolCrm: string
  /**
   * Rol del PORTAL del usuario (`perfiles.rol`). Define si el CRM le ofrece dar
   * de alta clientes/contratos: analista/admin/superadmin sí, directorio no.
   * Por defecto 'analista' = el equipo real (los 17 vendedores y los 2
   * supervisores lo son); Carlos (gerencia) es 'directorio'.
   */
  rolPortal: string
  /** El próximo GET de leads (carga/resync) responde 500 una vez. */
  fallarProximaCargaLeads: boolean
  /** El próximo PATCH de leads responde 400 (rechazo del servidor, error genérico). */
  fallarProximoPatch: boolean
  /** El próximo PATCH de leads responde 400 con 23505/uq_leads_telefono_vivo. */
  fallarProximoPatchTelefono: boolean
  /** El próximo POST de leads (insertar) responde 400. */
  fallarProximoPostLead: boolean
  /** El próximo POST de actividades responde 400 (nota del descarte, etc.). */
  fallarProximoInsertActividad: boolean
  /** Cualquier GET de leads responde 500 (servidor caído para resync). */
  leadsSiempreCaido: boolean
  /** Clientes del portal (alimentan clientes_basicos + el detalle de perfiles). */
  clientes: PerfilReal[]
  /** Contratos del portal (con el embed cliente ya resuelto). */
  contratos: ContratoReal[]
  /** El próximo GET de contratos_cartera responde 500 una vez (panel de error + Reintentar). */
  fallarProximaCargaContratos: boolean
  /** Cronograma por contrato_id (el GET filtra por eq.<id>). */
  cuotas: Record<string, unknown[]>
  /** Co-titulares por contrato_id (cuentas mancomunadas). */
  titulares: Record<string, unknown[]>
  /** Respuestas de las RPC de métricas del panel Hoy. */
  metricas: {
    capital: unknown[]
    pagos: unknown[]
    altas: unknown[]
    vencimientos: unknown[]
    distribucion: unknown
  }
  /**
   * Simula la TRAMPA de la ventana de 5 h vencida: el PATCH a perfiles responde
   * 200 con [] (0 filas, SIN error) y la RPC actualizar_contrato rechaza P0001.
   */
  ventanaVencida: boolean
  /** El próximo POST a la edge crear-cliente responde 409 (documento duplicado). */
  fallarProximaAlta: boolean
  /** Contadores para aserciones. */
  llamadas: {
    insertLead: number
    patchLead: number
    insertActividad: number
    getLeads: number
    altaCliente: number
    patchPerfil: number
    rpcCrearContrato: number
    rpcActualizarContrato: number
    rpcMetricasDistribucion: number
    rpcActualizarCapacidad: number
  }
  ultimaActualizacionCapacidad: {
    analistaId: string
    capacidad: number | null
  } | null
}

type BackendRealInit = Omit<Partial<BackendReal>, 'metricas'> & {
  metricas?: Partial<BackendReal['metricas']>
}

/**
 * Bloqueo FAIL-CLOSED del host de Supabase para las pruebas DEMO: una sesión
 * demo no tiene backend y JAMÁS debe pegarle a producción. Cualquier request al
 * host se ABORTA y se cuenta; el test asevera 0 al final (una fuga = fallo, no un
 * 500 silencioso). Devuelve un getter del número de requests interceptados.
 */
export async function bloquearSupabase(page: Page): Promise<() => number> {
  let intentos = 0
  await page.route(`**://${SUPABASE_HOST}/**`, async (route) => {
    intentos += 1
    await route.abort()
  })
  return () => intentos
}

/**
 * Intercepta TODO el HTTP del host de Supabase (auth + rest). Nada llega a
 * producción: lo no reconocido responde 500 (fail-closed) y el test falla en vez
 * de escribir. (El CRM no usa realtime/WebSocket — verificado en el código —, así
 * que no hay canal WS que interceptar.) El enrutado es por pathname; el header
 * Accept-Profile/Content-Profile del esquema no se valida (la app siempre usa el
 * esquema correcto, así que no aporta cobertura). Devuelve el estado mutable para
 * que cada test configure fallos y aserte llamadas.
 */
export async function montarBackendReal(
  page: Page,
  init: BackendRealInit = {},
): Promise<BackendReal> {
  const estado: BackendReal = {
    leads: init.leads ?? [leadReal()],
    rolCrm: init.rolCrm ?? 'gerencia',
    rolPortal: init.rolPortal ?? 'analista',
    fallarProximaCargaLeads: init.fallarProximaCargaLeads ?? false,
    fallarProximoPatch: init.fallarProximoPatch ?? false,
    fallarProximoPatchTelefono: init.fallarProximoPatchTelefono ?? false,
    fallarProximoPostLead: init.fallarProximoPostLead ?? false,
    fallarProximoInsertActividad: init.fallarProximoInsertActividad ?? false,
    leadsSiempreCaido: init.leadsSiempreCaido ?? false,
    clientes: init.clientes ?? [clienteReal()],
    contratos: init.contratos ?? [contratoReal()],
    fallarProximaCargaContratos: init.fallarProximaCargaContratos ?? false,
    cuotas: init.cuotas ?? {},
    titulares: init.titulares ?? {},
    metricas: {
      capital: init.metricas?.capital ?? [],
      pagos: init.metricas?.pagos ?? [],
      altas: init.metricas?.altas ?? [],
      vencimientos: init.metricas?.vencimientos ?? [],
      distribucion: init.metricas?.distribucion ?? metricasDistribucionVaciaReal(),
    },
    ventanaVencida: init.ventanaVencida ?? false,
    fallarProximaAlta: init.fallarProximaAlta ?? false,
    llamadas: {
      insertLead: 0, patchLead: 0, insertActividad: 0, getLeads: 0,
      altaCliente: 0, patchPerfil: 0, rpcCrearContrato: 0, rpcActualizarContrato: 0,
      rpcMetricasDistribucion: 0, rpcActualizarCapacidad: 0,
    },
    ultimaActualizacionCapacidad: init.ultimaActualizacionCapacidad ?? null,
  }

  const cors: Record<string, string> = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': '*',
    'access-control-expose-headers': 'content-range',
  }
  const json = (route: Route, obj: unknown, status = 200) =>
    route.fulfill({ status, headers: cors, contentType: 'application/json', body: JSON.stringify(obj) })

  await page.route(`**://${SUPABASE_HOST}/**`, async (route) => {
    const req = route.request()
    const method = req.method()
    const url = new URL(req.url())
    const p = url.pathname

    if (method === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })

    // ── Auth ──
    if (p === '/auth/v1/token') return json(route, SESSION) // password + refresh
    if (p === '/auth/v1/user') return json(route, USER)
    if (p === '/auth/v1/logout') return route.fulfill({ status: 204, headers: cors })

    // ── resolverRol + clientes del portal (misma tabla perfiles) ──
    if (p === '/rest/v1/equipo') return json(route, [{ rol_crm: estado.rolCrm, activo: true }])
    if (p === '/rest/v1/perfiles') {
      const idFiltro = (url.searchParams.get('id') ?? '').replace(/^eq\./, '')
      if (method === 'GET') {
        // Detalle de un cliente de la cartera (obtenerClienteDetalle usa eq.id
        // + limit 1 → frontera SIEMPRE array); si el id no es de un cliente,
        // es resolverRol pidiendo el perfil del usuario logueado.
        const cli = estado.clientes.find((c) => c.id === idFiltro)
        if (cli) return json(route, [cli])
        return json(route, [{ nombre_completo: 'Gerente Real', activo: true, rol: estado.rolPortal }])
      }
      if (method === 'PATCH') {
        estado.llamadas.patchPerfil += 1
        // LA TRAMPA de la ventana de 5 h: vencida, la RLS no matchea la fila y
        // PostgREST responde 200 con [] — 0 filas y NINGÚN error.
        if (estado.ventanaVencida) return json(route, [])
        const cambios = (req.postDataJSON() ?? {}) as Partial<PerfilReal>
        estado.clientes = estado.clientes.map((c) => (c.id === idFiltro ? { ...c, ...cambios } : c))
        return json(route, [{ id: idFiltro }])
      }
    }

    // ── vista crm.clientes_basicos (cartera scopeada; sin bancarios) ──
    if (p === '/rest/v1/clientes_basicos' && method === 'GET') {
      return json(route, estado.clientes.map((c) => ({
        id: c.id,
        nombres: c.nombres,
        apellidos: c.apellidos,
        nombre_completo: c.nombre_completo,
        tipo_documento: c.tipo_documento,
        dni: c.dni,
        correo: c.correo,
        telefono: c.telefono,
        asesor_perfil_id: c.asesor_perfil_id,
        // Con asesor NULL define el dueño de cartera (regla de Corregir/+Contrato).
        creado_por: c.creado_por,
        activo: c.activo,
        creado_en: c.creado_en,
      })))
    }

    // ── contratos: vista con ámbito + RPCs de detalle (esquema crm) ──
    // El ámbito real lo decide el servidor; el mock devuelve lo configurado.
    if (p === '/rest/v1/contratos_cartera' && method === 'GET') {
      if (estado.fallarProximaCargaContratos) {
        estado.fallarProximaCargaContratos = false
        return json(route, { message: 'server down' }, 500)
      }
      return json(route, estado.contratos)
    }

    if (p === '/rest/v1/rpc/cronograma_contrato_fn' && method === 'POST') {
      const cid = String(((req.postDataJSON() ?? {}) as { p_contrato_id?: string }).p_contrato_id ?? '')
      return json(route, estado.cuotas[cid] ?? [])
    }

    if (p === '/rest/v1/rpc/titulares_contrato_fn' && method === 'POST') {
      const cid = String(((req.postDataJSON() ?? {}) as { p_contrato_id?: string }).p_contrato_id ?? '')
      return json(route, estado.titulares[cid] ?? [])
    }

    // ── RPC crear_contrato (portal): crea contrato + cronograma atómico ──
    if (p === '/rest/v1/rpc/crear_contrato' && method === 'POST') {
      estado.llamadas.rpcCrearContrato += 1
      const body = (req.postDataJSON() ?? {}) as { p_contrato?: Record<string, unknown> }
      const pc = body.p_contrato ?? {}
      // Espejo del servidor: sin numero_contrato inventa la numeración VIEJA
      // 'AC-2026-XXXX' (por eso el campo del CRM debe ser obligatorio).
      const numero = typeof pc.numero_contrato === 'string' && pc.numero_contrato
        ? pc.numero_contrato
        : `AC-2026-0${900 + estado.contratos.length}`
      const clienteId = String(pc.cliente_id ?? '')
      const duenio = estado.clientes.find((c) => c.id === clienteId)
      const nuevo = contratoReal({
        ...(pc as Partial<ContratoReal>),
        id: `ct-nuevo-${estado.contratos.length + 1}`,
        numero_contrato: numero,
        cliente_id: clienteId,
        creado_en: new Date().toISOString(), // recién creado → ventana de 5 h viva
        cliente: { nombre_completo: duenio?.nombre_completo ?? null },
      })
      estado.contratos = [nuevo, ...estado.contratos]
      return json(route, { id: nuevo.id, numero_contrato: numero })
    }

    // ── RPC actualizar_contrato (portal): valida creado_por → 5 h → cartera ──
    if (p === '/rest/v1/rpc/actualizar_contrato' && method === 'POST') {
      estado.llamadas.rpcActualizarContrato += 1
      if (estado.ventanaVencida) {
        // A diferencia del PATCH a perfiles, la RPC SÍ es ruidosa: RAISE → P0001.
        return json(route, {
          code: 'P0001',
          message: 'Solo puedes corregir un contrato dentro de las 5 horas de creado',
          details: '',
        }, 400)
      }
      const body = (req.postDataJSON() ?? {}) as { p_id?: string; p_contrato?: Record<string, unknown> }
      const { titulares: titularesNuevos, ...cambios } = (body.p_contrato ?? {}) as
        Record<string, unknown> & { titulares?: unknown[] }
      const pId = String(body.p_id ?? '')
      estado.contratos = estado.contratos.map((k) => (k.id === pId ? { ...k, ...cambios } : k))
      // Semántica del servidor: clave ausente = no tocar; presente (incl. []) = reemplazar.
      if (titularesNuevos) {
        estado.titulares[pId] = titularesNuevos.map((t, i) => ({ ...(t as object), orden: i + 1 }))
      }
      return route.fulfill({ status: 204, headers: cors }) // RPC void → 204 sin cuerpo
    }

    // ── edge crear-cliente (alta REAL en el portal: Auth + perfil + correo) ──
    if (p === '/functions/v1/crear-cliente' && method === 'POST') {
      estado.llamadas.altaCliente += 1
      if (estado.fallarProximaAlta) {
        estado.fallarProximaAlta = false
        return json(route, { error: 'Este documento ya está registrado para otro cliente.' }, 409)
      }
      const b = (req.postDataJSON() ?? {}) as Record<string, unknown>
      const nuevo = clienteReal({
        id: `cli-nuevo-${estado.clientes.length + 1}`,
        nombre_completo: String(b.nombre_completo ?? ''),
        nombres: (b.nombres as string | undefined) ?? null,
        apellidos: (b.apellidos as string | undefined) ?? null,
        tipo_documento: String(b.tipo_documento ?? 'DNI'),
        dni: (b.dni as string | undefined) ?? null,
        correo: (b.email as string | undefined) ?? null,
        telefono: (b.telefono as string | undefined) ?? null,
        creado_en: new Date().toISOString(), // recién creado → ventana de 5 h viva
        // La edge NO recibe bancarios: nacen vacíos y llegan por el 2º paso (PATCH).
        banco: null, tipo_cuenta: null, numero_cuenta: null, cci: null,
      })
      estado.clientes = [nuevo, ...estado.clientes]
      return json(route, { ok: true, user_id: nuevo.id, email: nuevo.correo, email_enviado: true })
    }

    // ── cargarReal ──
    if (p === '/rest/v1/rpc/equipo_visible_fn') return json(route, ROSTER)
    if (p === '/rest/v1/rpc/actividades_del_ambito_fn') return json(route, [])

    // ── métricas de gerencia (gráficas del panel Hoy) ──
    if (p === '/rest/v1/rpc/metricas_capital_mes_fn') return json(route, estado.metricas.capital)
    if (p === '/rest/v1/rpc/metricas_pagos_mes_fn') return json(route, estado.metricas.pagos)
    if (p === '/rest/v1/rpc/metricas_altas_analista_fn') return json(route, estado.metricas.altas)
    if (p === '/rest/v1/rpc/metricas_vencimientos_fn') return json(route, estado.metricas.vencimientos)
    if (p === '/rest/v1/rpc/metricas_distribucion_leads_fn' && method === 'POST') {
      estado.llamadas.rpcMetricasDistribucion += 1
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string; p_hasta?: string }
      const desde = String(body.p_desde ?? '')
      const hasta = String(body.p_hasta ?? '')
      return json(route, metricasParaPeriodo(estado.metricas.distribucion, desde, hasta))
    }
    if (p === '/rest/v1/rpc/actualizar_capacidad_leads_objetivo' && method === 'POST') {
      estado.llamadas.rpcActualizarCapacidad += 1
      const body = (req.postDataJSON() ?? {}) as {
        p_analista_id?: string
        p_capacidad_leads_objetivo?: number | null
      }
      const analistaId = String(body.p_analista_id ?? '')
      const capacidadCruda = body.p_capacidad_leads_objetivo
      const capacidad = capacidadCruda == null ? null : Number(capacidadCruda)
      estado.ultimaActualizacionCapacidad = { analistaId, capacidad }
      actualizarCapacidadMock(estado.metricas.distribucion, analistaId, capacidad)
      return json(route, [{
        perfil_id: analistaId,
        capacidad_leads_objetivo: capacidad,
      }])
    }

    // ── leads ──
    if (p === '/rest/v1/leads') {
      if (method === 'GET') {
        estado.llamadas.getLeads += 1
        if (estado.leadsSiempreCaido) return json(route, { message: 'server down' }, 500)
        if (estado.fallarProximaCargaLeads) {
          estado.fallarProximaCargaLeads = false
          return json(route, { message: 'server down' }, 500)
        }
        return json(route, estado.leads)
      }
      if (method === 'POST') {
        estado.llamadas.insertLead += 1
        if (estado.fallarProximoPostLead) {
          estado.fallarProximoPostLead = false
          return json(route, { code: '', message: 'insert rechazado', details: '' }, 400)
        }
        // Servidor con estado: la fila insertada aparece en el próximo GET (resync).
        const cuerpo = (req.postDataJSON() ?? {}) as Partial<LeadReal>
        estado.leads = [leadReal(cuerpo), ...estado.leads]
        return json(route, [], 201)
      }
      if (method === 'PATCH') {
        estado.llamadas.patchLead += 1
        if (estado.fallarProximoPatchTelefono) {
          estado.fallarProximoPatchTelefono = false
          return json(route, { code: '23505', message: 'duplicate key', details: 'uq_leads_telefono_vivo' }, 400)
        }
        if (estado.fallarProximoPatch) {
          estado.fallarProximoPatch = false
          return json(route, { code: '', message: 'update rechazado', details: '' }, 400)
        }
        // Servidor con estado: aplica el update a la fila (el resync lo refleja).
        const idFiltro = (url.searchParams.get('id') ?? '').replace(/^eq\./, '')
        const cambios = (req.postDataJSON() ?? {}) as Partial<LeadReal>
        estado.leads = estado.leads.map((l) => (l.id === idFiltro ? { ...l, ...cambios } : l))
        return json(route, [{ id: idFiltro }])
      }
    }

    // ── actividades ──
    if (p === '/rest/v1/actividades' && method === 'POST') {
      estado.llamadas.insertActividad += 1
      if (estado.fallarProximoInsertActividad) {
        estado.fallarProximoInsertActividad = false
        return json(route, { code: '', message: 'actividad rechazada', details: '' }, 400)
      }
      return json(route, [], 201)
    }

    // Fail-closed: cualquier otra cosa NO debe salir a prod.
    return json(route, { message: `E2E: ruta no mockeada ${method} ${p}` }, 500)
  })

  return estado
}

/** Inicia sesión REAL vía el formulario (supabase-js guarda la sesión solo). */
export async function loginReal(page: Page): Promise<void> {
  await page.goto('/')
  await page.locator('#correo').fill('qa-real@avancecorp.pe')
  await page.locator('#clave').fill('cualquier-cosa')
  await page.getByRole('button', { name: /^Entrar$/ }).click()
}
