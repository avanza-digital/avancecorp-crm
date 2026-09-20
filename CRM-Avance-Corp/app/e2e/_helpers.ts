// Helpers compartidos de los E2E del CRM. Dos mundos:
//  - DEMO: login demo por rol (sin backend, datos de lib/demo.ts).
//  - REAL: sesión autenticada (yo.demo=false) con TODO el backend Supabase
//    interceptado (fail-closed) → prueba la ruta real sin tocar prod.
import { expect, type Locator, type Page, type Route } from '@playwright/test'
import { agruparCartera, resumenCartera } from '../src/lib/cartera-vista'
import type { ClienteBasico, ContratoRow } from '../src/lib/clientes-tipos'

export const ROLES_DEMO = ['Analista', 'Supervisor', 'Gerencia', 'Directorio'] as const
export type RolDemo = (typeof ROLES_DEMO)[number]

/** Entra a la demo con el rol dado y espera el workspace (nav lateral visible). */
export async function entrarDemo(page: Page, rol: RolDemo): Promise<void> {
  // Los contadores (AnimatedValue) y las intros GSAP respetan reduced-motion;
  // con los workers en paralelo la CPU los deja a media animación y los
  // asserts de tiles pillan valores de tránsito («2» camino de «6»). El
  // `use.reducedMotion` del config NO llega a la página en Playwright 1.61
  // (sondeado con matchMedia): se emula por página, aquí y en loginReal — los
  // dos únicos puntos de entrada de todos los specs.
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/')
  await page.getByRole('button', { name: /explorar en modo demo/i }).click()
  await page.getByRole('button', { name: new RegExp(`^${rol}`) }).click()
  await expect(page.getByRole('button', { name: 'Pipeline' })).toBeVisible({ timeout: 10_000 })
}

/** Navega al Pipeline (donde viven las cards de lead operables). */
export async function irAPipeline(page: Page): Promise<void> {
  await page.getByRole('button', { name: 'Pipeline' }).click()
  await expect(page.getByText('Nuevo', { exact: true }).first()).toBeVisible()
}

/** Navega a «Mi cartera» (clientes + contratos). Su botón se llama «Mi cartera»
 * para el analista y «Cartera» para quien supervisa. Desde que la llave de leads
 * se abrió (2026-08-18) dejó de ser la pantalla de aterrizaje de la fuerza de
 * ventas —ahora aterrizan en «Hoy»—, así que hay que ir a propósito. Es
 * idempotente: si ya estamos ahí, no hace nada. */
export async function irAMiCartera(page: Page): Promise<void> {
  const titulo = page.getByRole('heading', { level: 1, name: /^(Mi cartera|Cartera)$/ })
  if (await titulo.count() > 0) return
  const propio = page.getByRole('button', { name: 'Mi cartera', exact: true })
  const boton = await propio.count() > 0
    ? propio
    : page.getByRole('button', { name: 'Cartera', exact: true })
  await boton.click()
  await expect(titulo).toBeVisible()
}

/** Navega a la Cartera de LEADS (la tabla paginada por cursor keyset desde F2).
 * Su botón se llama «Leads» desde la Fase 6 (2026-07-21): «Cartera» pasó a ser
 * el rótulo de mi-cartera (clientes+contratos) para quien supervisa, así que
 * pedir «Cartera» aquí aterrizaba en la pantalla equivocada. */
export async function irACartera(page: Page): Promise<void> {
  // exact: gerencia ve además «Repartir leads», que contiene esta palabra.
  await page.getByRole('button', { name: 'Leads', exact: true }).click()
  await expect(page.getByRole('table', { name: 'Cartera de leads' })).toBeVisible()
}

/**
 * Mi cartera ARRANCA filtrada por el mes en curso (decisión de Miguel,
 * 2026-08-14). Los fixtures cuyos contratos son de otros meses tienen que pedir
 * la cartera entera antes de buscar su fila — que es exactamente lo que hace una
 * persona, y por eso se hace aquí en vez de relajar las aserciones.
 */
export async function verTodaLaCartera(page: Page): Promise<void> {
  await page.getByRole('combobox', { name: /Filtrar por mes/ }).selectOption('todos')
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

const SUPABASE_ORIGIN = 'http://127.0.0.1:59999'
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
  /** Solo del mock: la foto inicial (GET /leads sin id) no lo devuelve; por id sí. */
  fueraDelBoot?: boolean
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
  /** Sello del cierre ganado (trigger del servidor); los fixtures viejos no lo traen. */
  convertido_en?: string | null
  actualizado_en: string
  activo: boolean
  nota: string | null
}

export function leadReal(over: Partial<LeadReal> = {}): LeadReal {
  const lead: LeadReal = {
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
  // Un convertido REAL siempre lleva su sello: la operación de conversión lo
  // estampa, así que un fixture convertido sin `convertido_en` no es un caso
  // raro — es un caso que producción no puede fabricar. Y además era una BOMBA
  // DE CALENDARIO: la cartera oculta convertidos de más de 45 días (regla real
  // de `cartera_pagina_fn`, calcada más abajo), y con las fechas fijas del
  // 2026-07-01 las dos pruebas de anulación pasaron 44 días en verde y
  // murieron solas el 15/08 — día 45 — sin que nadie tocara nada. El sello va
  // relativo al reloj, como las fechas del oráculo SQL, para que no caduque.
  // Quien quiera un convertido VIEJO (p. ej. para probar la ventana de 45
  // días) lo pide explícito: `convertido_en: '2026-05-01T...'`.
  if (lead.etapa === 'convertido' && lead.convertido_en === undefined) {
    lead.convertido_en = new Date().toISOString()
  }
  return lead
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
  domicilio: string | null
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
    domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
    activo: true,
    asesor_perfil_id: UID, // el creador queda como analista responsable → cae en su cartera
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

// ── Cuentas bancarias contractuales (crm.cuentas_bancarias) ────────────────────

/**
 * Fila interna del backend E2E. `cliente_id` permite aplicar el mismo ámbito
 * cliente+moneda de la RPC; se retira antes de responder porque la función real
 * no lo expone al navegador.
 */
export interface CuentaBancariaReal {
  cliente_id: string
  cuenta_id: string
  moneda: 'PEN' | 'USD'
  banco: string
  tipo_cuenta: 'ahorros' | 'corriente'
  numero_cuenta: string
  cci: string
  titular_distinto: boolean
  beneficiario_nombre: string | null
  beneficiario_dni: string | null
  origen: 'perfil' | 'contrato'
  es_cuenta_perfil: boolean
  creada_en: string | null
}

/** Cuenta versionada reutilizable para configurar escenarios E2E. */
export function cuentaBancariaReal(over: Partial<CuentaBancariaReal> = {}): CuentaBancariaReal {
  return {
    cliente_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    cuenta_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    moneda: 'PEN',
    banco: 'Interbank',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '200300001234',
    cci: '00320030000123456789',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    origen: 'contrato',
    es_cuenta_perfil: false,
    creada_en: '2026-07-15T10:00:00.000Z',
    ...over,
  }
}

/** Proyecta el slot vigente de public.perfiles al contrato estricto de la RPC. */
function cuentaPerfilReal(
  perfil: PerfilReal,
  moneda: 'PEN' | 'USD',
): Omit<CuentaBancariaReal, 'cliente_id' | 'cuenta_id'> & { cuenta_id: null } | null {
  const usd = moneda === 'USD'
  const banco = usd ? perfil.banco_usd : perfil.banco
  const tipoCuenta = usd ? perfil.tipo_cuenta_usd : perfil.tipo_cuenta
  const numeroCuenta = usd ? perfil.numero_cuenta_usd : perfil.numero_cuenta
  const cci = usd ? perfil.cci_usd : perfil.cci
  if (
    !banco
    || (tipoCuenta !== 'ahorros' && tipoCuenta !== 'corriente')
    || !numeroCuenta
    || !cci
  ) return null

  return {
    cuenta_id: null,
    moneda,
    banco,
    tipo_cuenta: tipoCuenta,
    numero_cuenta: numeroCuenta,
    cci,
    titular_distinto: usd ? perfil.titular_distinto_usd : perfil.titular_distinto,
    beneficiario_nombre: usd ? perfil.beneficiario_nombre_usd : perfil.beneficiario_nombre,
    beneficiario_dni: usd ? perfil.beneficiario_dni_usd : perfil.beneficiario_dni,
    origen: 'perfil',
    es_cuenta_perfil: true,
    creada_en: null,
  }
}

// ── Contratos del portal (public.contratos con el embed cliente:perfiles) ─────
export interface ContratoReal {
  id: string
  /** 'YYYY-MM-DD' — el mes por el que Mi cartera reparte sus bloques. */
  fecha_cierre_comercial?: string
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
  producto_condicion_id: string
  producto_id: string
  producto_codigo: string
  producto_version_id: string
  producto_version: number
  producto_nombre: string
  producto_version_estado: 'borrador' | 'publicada' | 'retirada'
}

export const PRODUCTO_CONDICION_PEN_ID = '10000000-0000-4000-8000-000000000001'
export const PRODUCTO_CONDICION_USD_ID = '10000000-0000-4000-8000-000000000002'
const PRODUCTO_ID = '20000000-0000-4000-8000-000000000001'
const PRODUCTO_VERSION_ID = '30000000-0000-4000-8000-000000000001'

const PRODUCTOS_SELECCIONABLES_REAL: Record<string, unknown>[] = [
  {
    condicion_id: PRODUCTO_CONDICION_PEN_ID,
    producto_id: PRODUCTO_ID,
    producto_codigo: 'RENTA-BASE',
    producto_revision: 2,
    version_id: PRODUCTO_VERSION_ID,
    numero_version: 1,
    version_nombre: 'Plan base 2026',
    vigente_desde: '2026-01-01',
    vigente_hasta: null,
    categoria: 'nuevo',
    moneda: 'PEN',
    plazo_meses: 12,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    capital_minimo: 100,
    capital_maximo: 100_000,
    tasa_referencia: 15,
    tasa_minima: 10,
    tasa_maxima: 20,
  },
  {
    condicion_id: PRODUCTO_CONDICION_USD_ID,
    producto_id: PRODUCTO_ID,
    producto_codigo: 'RENTA-BASE',
    producto_revision: 2,
    version_id: PRODUCTO_VERSION_ID,
    numero_version: 1,
    version_nombre: 'Plan base 2026',
    vigente_desde: '2026-01-01',
    vigente_hasta: null,
    categoria: 'nuevo',
    moneda: 'USD',
    plazo_meses: 12,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    capital_minimo: 100,
    capital_maximo: 50_000,
    tasa_referencia: 15,
    tasa_minima: 10,
    tasa_maxima: 20,
  },
]

export function contratoReal(over: Partial<ContratoReal> = {}): ContratoReal {
  // Por defecto el contrato se cierra el día (Lima) en que se registra: así un
  // spec que mueve `creado_en` para colocarlo en un mes sigue diciendo lo mismo
  // ahora que el bloque va por FECHA DE CIERRE. Quien las quiera distintas pasa
  // `fecha_cierre_comercial`.
  const creadoEn = over.creado_en ?? '2026-07-01T00:00:00.000Z'
  const diaLima = new Date(Date.parse(creadoEn) - 5 * 3600_000).toISOString().slice(0, 10)
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
    fecha_cierre_comercial: diaLima,
    notas_internas: null,
    creado_por: UID,
    creado_en: creadoEn,
    cliente_nombre: 'CLIENTE PORTAL UNO',
    asesor_perfil_id: UID,
    producto_condicion_id: PRODUCTO_CONDICION_PEN_ID,
    producto_id: PRODUCTO_ID,
    producto_codigo: 'RENTA-BASE',
    producto_version_id: PRODUCTO_VERSION_ID,
    producto_version: 1,
    producto_nombre: 'Plan base 2026',
    producto_version_estado: 'publicada',
    ...over,
  }
}

const ROSTER = [
  { perfil_id: UID, nombre_completo: 'Gerente Real', rol_crm: 'gerencia', supervisor_id: null, activo: true },
  { perfil_id: 'vend-1', nombre_completo: 'Analista Real Uno', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
  { perfil_id: 'vend-2', nombre_completo: 'Analista Real Dos', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
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

function punteriaDistribucion(convertidos: number, resueltos: number) {
  return {
    convertidos,
    resueltos,
    pct: resueltos > 0 ? Math.round((100 * convertidos / resueltos) * 100) / 100 : null,
  }
}

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
      conversion: punteriaDistribucion(convertidos, leadsUnicosResueltos),
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
 * Fotografía rica y contractual de `crm.metricas_distribucion_leads_v3_fn`
 * (contrato V3 de lib/metricas-distribucion.ts — objetos ESTRICTOS: una clave
 * de más o de menos y el parser de producción falla cerrado).
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
      transferidos: 1,
      parqueados: 0,
      desactivados: 0,
      sin_tocar_actual: 1,
    },
    conversion: {
      pen: punteriaDistribucion(3, 6),
      usd: punteriaDistribucion(1, 1),
      nucleo_divisor: 6,
      nucleo_referidos_recibidos: 0,
      nucleo_numerador: 4,
      nucleo_conversion_pct: 66.67,
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
      transferidos: 1,
      parqueados: 1,
      desactivados: 0,
      sin_tocar_actual: 1,
    },
    conversion: {
      pen: punteriaDistribucion(1, 4),
      usd: punteriaDistribucion(0, 0),
      nucleo_divisor: 4,
      nucleo_referidos_recibidos: 0,
      nucleo_numerador: 1,
      nucleo_conversion_pct: 25,
    },
  }

  const totalRangos = rangosCola({
    pen_1000_5000: [1, 5000],
    pen_10000_20000: [1, 20000],
  })
  const globalRangos = rangosCola({ pen_1000_5000: [1, 5000] })
  const bandejaRangos = rangosCola({ pen_10000_20000: [1, 20000] })

  return {
    version: 3,
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
      montos: 'SEPARADOS_SIN_CONVERSION',
      conversion_punteria: 'CERRADOS_ENTRE_RESUELTOS',
      conversion_nucleo: 'COHORTE_POR_ASIGNACION_REFERIDOS_PONDERADOS',
      conversion_incluye_cartera: true,
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
      reasignaciones_cohorte: 2,
      conversion: {
        pen: punteriaDistribucion(4, 10),
        usd: punteriaDistribucion(1, 1),
        nucleo_divisor: 10,
        nucleo_referidos_recibidos: 0,
        nucleo_numerador: 5,
        nucleo_conversion_pct: 50,
      },
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
    sondas: {
      peso_referido: 0.15,
      mes_peso: `${desde.slice(0, 7)}-01`,
      paridad_nucleo: 0,
      paridad_filas: 2,
      cuadra: true,
      divisor_sin_analista: 0,
      numerador_sin_analista: 0,
      cierres_anulados: 0,
      episodios_sin_origen: 0,
      nucleo_sin_ficha: 0,
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
      reasignaciones_cohorte: 0,
      conversion: {
        pen: punteriaDistribucion(0, 0),
        usd: punteriaDistribucion(0, 0),
        nucleo_divisor: 0,
        nucleo_referidos_recibidos: 0,
        nucleo_numerador: 0,
        nucleo_conversion_pct: null,
      },
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
    sondas: {
      peso_referido: 0.15,
      mes_peso: '2026-04-01',
      paridad_nucleo: null,
      paridad_filas: 0,
      cuadra: null,
      divisor_sin_analista: 0,
      numerador_sin_analista: 0,
      cierres_anulados: 0,
      episodios_sin_origen: 0,
      nucleo_sin_ficha: 0,
    },
  }
}

/**
 * Payload de crm.resumen_cartera_fn calculado del ESTADO VIVO del mock: tras
 * una mutación + resync, los tiles F1 de Cartera/Pipeline deben reflejar las
 * mismas filas que este backend simulado sirve. Misma semántica que el espejo
 * demo (lib/resumen-cartera): ventana de convertidos de 45 días con la cadena
 * de fallback de cierres-del-mes (los fixtures no traen `convertido_en`) y
 * USD estricto. `sin_tocar` queda en 0: el mock no modela contactos por lead.
 */
/**
 * Espejo de `crm.cartera_pagina_fn` (F2) sobre el estado VIVO del mock: filtra,
 * ordena por `(actualizado_en desc, id asc)` y corta por cursor, igual que el
 * servidor. Devuelve `p_limite` filas COMO MÁXIMO — y el front pide una de más
 * a propósito, así que este mock es también quien decide si aparece «Cargar
 * más». Si aquí se paginara mal, los specs de sesión real pasarían con una
 * lista que en producción se corta o se repite.
 */
export function carteraPaginaReal(
  leads: LeadReal[],
  args: {
    p_limite?: number
    p_antes_de?: string | null
    p_antes_id?: string | null
    p_etapa?: string | null
    p_vendedor_id?: string | null
    p_sin_asignar?: boolean
    p_texto?: string | null
    p_desde?: string | null
    p_hasta?: string | null
    p_origen?: string | null
  },
): Record<string, unknown>[] {
  const corteMs = Date.now() - 45 * 86_400_000
  const texto = (args.p_texto ?? '').trim()
  const digitos = texto.replace(/\D/g, '')
  const filtrados = leads.filter((l) => {
    if (!l.activo) return false
    if (args.p_origen && l.origen !== args.p_origen) return false
    if (args.p_desde) {
      const fecha = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(new Date(l.creado_en))
      if (!l.vendedor_id || fecha < args.p_desde || fecha > String(args.p_hasta)) return false
    }
    if (!args.p_desde && l.etapa === 'convertido') {
      const sello = Date.parse(l.convertido_en ?? l.actualizado_en ?? l.creado_en)
      if (!Number.isFinite(sello) || sello < corteMs) return false
    }
    if (args.p_etapa && l.etapa !== args.p_etapa) return false
    if (args.p_sin_asignar && l.vendedor_id != null) return false
    if (args.p_vendedor_id && l.vendedor_id !== args.p_vendedor_id) return false
    if (texto.length >= 2) {
      const porNombre = l.nombre_completo.toLowerCase().includes(texto.toLowerCase())
      const porDigitos = digitos.length >= 3
        && (l.telefono.includes(digitos) || (l.dni ?? '').includes(digitos))
      if (!porNombre && !porDigitos) return false
    }
    return true
  })
  const ordenados = [...filtrados].sort((a, b) => {
    if (a.actualizado_en !== b.actualizado_en) return a.actualizado_en < b.actualizado_en ? 1 : -1
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  })
  const desde = args.p_antes_de
    ? ordenados.filter((l) => (
      l.actualizado_en < args.p_antes_de!
      || (l.actualizado_en === args.p_antes_de && l.id > String(args.p_antes_id ?? ''))
    ))
    : ordenados
  return desde
    .slice(0, Math.max(1, Number(args.p_limite ?? 51)))
    .map((l) => ({ ...l, genero: null, fecha_nacimiento: null, tenencia_desde: null,
      convertido_en: l.convertido_en ?? null, contrato_id: null, no_contactar: false,
      ultimo_contacto_en: null }))
}

export function resumenCarteraReal(leads: LeadReal[]): Record<string, unknown> {
  const corteMs = Date.now() - 45 * 86_400_000
  const ambito = leads.filter((l) => {
    if (!l.activo) return false
    if (l.etapa !== 'convertido') return true
    const sello = Date.parse(l.convertido_en ?? l.actualizado_en ?? l.creado_en)
    return Number.isFinite(sello) && sello >= corteMs
  })
  const esUsd = (l: LeadReal) => l.moneda === 'USD'
  const abiertos = ambito.filter((l) => l.etapa !== 'convertido' && l.etapa !== 'descartado')
  const asignados = abiertos.filter((l) => l.vendedor_id != null)
  const parkeados = abiertos.filter((l) => l.vendedor_id == null)
  const convertidos = ambito.filter((l) => l.etapa === 'convertido')
  const descartados = ambito.filter((l) => l.etapa === 'descartado')
  const suma = (grupo: LeadReal[], usd: boolean) =>
    grupo.reduce((acc, l) => (esUsd(l) === usd ? acc + (l.monto_estimado ?? 0) : acc), 0)
  const base = ambito.filter((l) => l.vendedor_id != null)
  const ganadosConVendedor = convertidos.filter((l) => l.vendedor_id != null)
  const porMotivo = new Map<string, number>()
  for (const l of descartados) {
    if (l.motivo_descarte != null) {
      porMotivo.set(l.motivo_descarte, (porMotivo.get(l.motivo_descarte) ?? 0) + 1)
    }
  }
  const etapas = ['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada', 'convertido', 'descartado']
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    ventana_convertidos_dias: 45,
    totales: {
      vivos: ambito.length,
      abiertos: abiertos.length,
      asignados: asignados.length,
      parkeados: parkeados.length,
      convertidos: convertidos.length,
      descartados: descartados.length,
      asignados_pen: asignados.filter((l) => !esUsd(l)).length,
      asignados_usd: asignados.filter(esUsd).length,
    },
    capital: {
      asignado: { pen: suma(asignados, false), usd: suma(asignados, true) },
      parkeado: { pen: suma(parkeados, false), usd: suma(parkeados, true) },
      ganado: { pen: suma(convertidos, false), usd: suma(convertidos, true) },
    },
    conversion: {
      convertidos: ganadosConVendedor.length,
      base: base.length,
      pct: base.length > 0 ? Math.round((100 * ganadosConVendedor.length) / base.length) : 0,
    },
    descartes: {
      total: descartados.length,
      sin_motivo: descartados.filter((l) => l.motivo_descarte == null).length,
      por_motivo: [...porMotivo.entries()]
        .map(([motivo, n]) => ({ motivo, n }))
        .sort((a, b) => b.n - a.n || a.motivo.localeCompare(b.motivo)),
    },
    embudo: etapas.map((etapa) => ({ etapa, n: ambito.filter((l) => l.etapa === etapa).length })),
    sin_tocar: 0,
  }
}

/**
 * Payload de crm.metricas_vendedores_fn desde el estado vivo del mock: una
 * fila por analista con leads (sin nombres — el front une con ROSTER), con la
 * ventana de 45 días. `equipos` va vacío: el ROSTER del mock no tiene
 * supervisores, y una comparativa sin miembro con quien unirse se descarta.
 */
export function metricasVendedoresReal(leads: LeadReal[]): Record<string, unknown> {
  const corteMs = Date.now() - 45 * 86_400_000
  const enVentana = leads.filter((l) => {
    if (!l.activo) return false
    if (l.etapa !== 'convertido') return true
    const sello = Date.parse(l.convertido_en ?? l.actualizado_en ?? l.creado_en)
    return Number.isFinite(sello) && sello >= corteMs
  })
  const porVendedor = new Map<string, LeadReal[]>()
  for (const l of enVentana) {
    if (!l.vendedor_id) continue
    const lista = porVendedor.get(l.vendedor_id)
    if (lista) lista.push(l)
    else porVendedor.set(l.vendedor_id, [l])
  }
  const vendedores = [...porVendedor.entries()]
    .map(([id, suyos]) => {
      const abiertos = suyos.filter((l) => l.etapa !== 'convertido' && l.etapa !== 'descartado')
      const convertidos = suyos.filter((l) => l.etapa === 'convertido').length
      const nucleoDivisor = suyos.length
      const nucleoNumerador = convertidos
      return {
        vendedor_id: id,
        rol_crm: 'vendedor',
        activo: true,
        activos: abiertos.length,
        capital_pen: abiertos.reduce((a, l) => (l.moneda !== 'USD' ? a + (l.monto_estimado ?? 0) : a), 0),
        capital_usd: abiertos.reduce((a, l) => (l.moneda === 'USD' ? a + (l.monto_estimado ?? 0) : a), 0),
        convertidos,
        conversion_pct: suyos.length > 0 ? Math.round((100 * convertidos) / suyos.length) : 0,
        nucleo_convertidos: convertidos,
        operaciones_cartera: 0,
        nucleo_divisor: nucleoDivisor,
        nucleo_numerador: nucleoNumerador,
        nucleo_conversion_pct: nucleoDivisor > 0
          ? Math.round((100 * nucleoNumerador / nucleoDivisor) * 100) / 100
          : null,
        sin_tocar: 0,
        dias_sin_actividad_max: 0,
      }
    })
    .sort((a, b) => b.capital_pen - a.capital_pen || a.vendedor_id.localeCompare(b.vendedor_id))
  const nucleoTotal = vendedores.reduce((total, vendedor) => ({
    nucleo_convertidos: total.nucleo_convertidos + vendedor.nucleo_convertidos,
    operaciones_cartera: total.operaciones_cartera + vendedor.operaciones_cartera,
    nucleo_divisor: total.nucleo_divisor + vendedor.nucleo_divisor,
    nucleo_numerador: total.nucleo_numerador + vendedor.nucleo_numerador,
  }), {
    nucleo_convertidos: 0,
    operaciones_cartera: 0,
    nucleo_divisor: 0,
    nucleo_numerador: 0,
  })
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    ventana_convertidos_dias: 45,
    ventana_metrica: 'mes_calendario',
    mes_metrica: '2026-09-01',
    peso_referido: 0.15,
    cobertura_conversion: {
      medible: true,
      suelo_historico: null,
      motivo_no_medible: null,
      divisor_aproximado: 0,
      divisor_por_motivo: {},
      cierres_sin_episodio: 0,
      fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 },
    },
    nucleo_total: {
      ...nucleoTotal,
      nucleo_conversion_pct: nucleoTotal.nucleo_divisor > 0
        ? Math.round((100 * nucleoTotal.nucleo_numerador / nucleoTotal.nucleo_divisor) * 100) / 100
        : null,
    },
    vendedores,
    equipos: [],
  }
}

/**
 * Payload de crm.cola_accion_fn desde el estado vivo del mock. Clasificación
 * SIMPLIFICADA (nuevo→sin_responder; propuesta≥5d; resto≥3d→seguimiento) pero
 * con el shape EXACTO del contrato — el front lo valida fail-closed.
 */
export function colaAccionReal(leads: LeadReal[], pLimite: number): Record<string, unknown> {
  const abiertos = leads.filter(
    (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado',
  )
  const items = abiertos.flatMap((l) => {
    const dias = Math.max(0, (Date.now() - Date.parse(l.creado_en)) / 86_400_000)
    let bucket: string | null = null
    let sev = 'media'
    let datos: Record<string, unknown> = {}
    if (l.vendedor_id == null) {
      bucket = 'por_repartir'
      sev = 'critica'
    } else if (l.etapa === 'nuevo') {
      bucket = 'sin_responder'
      datos = { espera_cliente_dias: Math.round(dias * 10000) / 10000, gestion_vencida: false, contacto_vencido: false }
    } else if (l.etapa === 'propuesta_enviada' && dias >= 5) {
      bucket = 'propuesta_sin_respuesta'
    } else if (dias >= 3) {
      bucket = 'seguimiento'
      sev = 'baja'
    }
    if (!bucket) return []
    return [{
      lead_id: l.id,
      bucket,
      sev,
      dias: Math.round(dias * 10000) / 10000,
      ultimo_contacto_en: null,
      datos_motivo: datos,
      lead: {
        nombre_completo: l.nombre_completo,
        telefono: l.telefono,
        correo: l.correo,
        genero: null,
        no_contactar: false,
        etapa: l.etapa,
        origen: l.origen,
        categoria_interes: l.categoria_interes,
        monto_estimado: l.monto_estimado ?? 0,
        moneda: l.moneda,
        creado_en: l.creado_en,
        tenencia_desde: null,
        vendedor_id: l.vendedor_id,
        asignado_supervisor_id: l.asignado_supervisor_id,
        motivo_descarte: null,
      },
    }]
  })
  const porBucket: Record<string, number> = {}
  const porSev: Record<string, number> = {}
  for (const i of items) {
    porBucket[i.bucket] = (porBucket[i.bucket] ?? 0) + 1
    porSev[i.sev] = (porSev[i.sev] ?? 0) + 1
  }
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    p_limite: pLimite,
    resumen: { total: items.length, por_bucket: porBucket, por_sev: porSev },
    items: items.slice(0, pLimite),
    estancados: { umbral_dias: 5, tope: 50, items: [] },
  }
}

/**
 * Payload de crm.resumen_reparto_fn desde el estado VIVO del mock. Se calcula
 * sobre `estado.colaReparto` —no sobre `estado.leads`—: el coordinador nunca
 * carga leads (su boot los omite), y `colaReparto` es exactamente lo que sirve
 * /rpc/leads_por_repartir y lo que mutan repartir/descartar/deshacer, así que
 * el agregado y la lista se mueven juntos como en producción.
 */
export function resumenRepartoReal(cola: Record<string, unknown>[]): Record<string, unknown> {
  let pen = 0
  let usd = 0
  let posibleCredito = 0
  let esperaMaxDias = 0
  const porOrigen = new Map<string, number>()
  for (const fila of cola) {
    const monto = Number(fila.monto_estimado ?? 0)
    if (fila.moneda === 'USD') usd += monto
    else pen += monto
    if (fila.clasificacion_auto === 'posible_credito') posibleCredito += 1
    const desde = Date.parse(String(fila.creado_en))
    if (Number.isFinite(desde)) {
      esperaMaxDias = Math.max(esperaMaxDias, Math.max(0, Math.floor((Date.now() - desde) / 86_400_000)))
    }
    const origen = String(fila.origen)
    porOrigen.set(origen, (porOrigen.get(origen) ?? 0) + 1)
  }
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    cola: {
      total: cola.length,
      capital: { pen, usd },
      espera_max_dias: esperaMaxDias,
      posible_credito: posibleCredito,
      por_origen: [...porOrigen.entries()]
        .map(([origen, n]) => ({ origen, n }))
        .sort((a, b) => b.n - a.n || a.origen.localeCompare(b.origen)),
    },
  }
}

function periodoMetricasReal(desde = '2026-08-01', hasta = '2026-08-07') {
  const dias = Math.max(
    1,
    Math.round(
      (Date.parse(`${hasta}T00:00:00Z`) - Date.parse(`${desde}T00:00:00Z`)) / 86_400_000,
    ) + 1,
  )
  return { desde, hasta, dias, zona: 'America/Lima' }
}

/**
 * Contrato real de `crm.reporte_derivaciones_coordinacion_fn` para los E2E.
 * Completa incluso los días sin movimiento y reconcilia el resumen legado por
 * analista con el nuevo desglose por origen, igual que hace la RPC.
 */
function reporteDerivacionesCoordinacionReal(
  filas: EntregaCoordinacionReal[],
  desde: string,
  hasta: string,
): Record<string, unknown> {
  const desdeMs = Date.parse(`${desde}T12:00:00Z`)
  const hastaMs = Date.parse(`${hasta}T12:00:00Z`)
  const fechas: string[] = []
  if (Number.isFinite(desdeMs) && Number.isFinite(hastaMs) && desdeMs <= hastaMs) {
    for (let cursor = hastaMs; cursor >= desdeMs; cursor -= 86_400_000) {
      fechas.push(new Date(cursor).toISOString().slice(0, 10))
    }
  }

  const dias = fechas.map((fecha) => {
    const entregasAgrupadas = new Map<string, EntregaCoordinacionReal>()
    for (const fila of filas.filter((item) => item.fecha === fecha)) {
      const clave = `${fila.supervisor_id}:${fila.analista_id}:${fila.origen}`
      const previa = entregasAgrupadas.get(clave)
      entregasAgrupadas.set(clave, {
        ...fila,
        derivados: (previa?.derivados ?? 0) + fila.derivados,
      })
    }
    const entregas = [...entregasAgrupadas.values()].sort((a, b) => (
      a.analista_nombre.localeCompare(b.analista_nombre, 'es')
      || a.origen.localeCompare(b.origen, 'es')
    ))
    const analistasAgrupados = new Map<
      string,
      Omit<EntregaCoordinacionReal, 'fecha' | 'origen'>
    >()
    for (const entrega of entregas) {
      const clave = `${entrega.supervisor_id}:${entrega.analista_id}`
      const previa = analistasAgrupados.get(clave)
      analistasAgrupados.set(clave, {
        analista_id: entrega.analista_id,
        analista_nombre: entrega.analista_nombre,
        supervisor_id: entrega.supervisor_id,
        supervisor_nombre: entrega.supervisor_nombre,
        derivados: (previa?.derivados ?? 0) + entrega.derivados,
      })
    }
    const analistas = [...analistasAgrupados.values()].sort((a, b) => (
      a.analista_nombre.localeCompare(b.analista_nombre, 'es')
    ))
    const totalDerivados = analistas.reduce((total, fila) => total + fila.derivados, 0)
    return {
      fecha,
      total_derivados: totalDerivados,
      analistas,
      entregas,
    }
  })

  return {
    version: 1,
    generado_en: new Date().toISOString(),
    periodo: { desde, hasta, dias: fechas.length, zona: 'America/Lima' },
    total_derivados: dias.reduce((total, dia) => total + dia.total_derivados, 0),
    dias,
  }
}

/**
 * crm.conversion_mensual_fn sin actividad: divisor 0, % NULL — el default del
 * mock, para que los specs de vacío sigan viendo su vacío honesto.
 */
type ConversionMensualRealFixture = {
  cartera: Record<string, unknown>
  total: Record<string, unknown>
  responsables: Record<string, unknown>[]
}

function carteraResponsableVaciaReal(): Record<string, unknown> {
  return {
    conversiones_clientes: 0,
    conversiones_renovacion: 0,
    conversiones_upgrade: 0,
    capital_renovado_pen: 0,
    capital_renovado_usd: 0,
    capital_adicional_pen: 0,
    capital_adicional_usd: 0,
    renovaciones_sin_desglose: 0,
  }
}

function carteraTotalVaciaReal(): Record<string, unknown> {
  return {
    ...carteraResponsableVaciaReal(),
    operaciones_renovacion: 0,
    operaciones_upgrade: 0,
  }
}

export function conversionMensualVaciaReal(): ConversionMensualRealFixture {
  const cartera = carteraTotalVaciaReal()
  return {
    cartera,
    total: {
      analistas: 0,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 0,
      cierres_de_arrastre: 0,
      referidos_recibidos: 0,
      numerador: 0,
      conversion_pct: null,
      referidos_aporta_pct: null,
      cartera,
    },
    responsables: [],
  }
}

/**
 * crm.conversion_mensual_fn con actividad: 2 cierres sobre 20 recibidos (10 %).
 * Los ids son UUID porque el contrato del front los exige (fail-closed).
 */
export function conversionMensualReal(periodo = '2026-09'): ConversionMensualRealFixture {
  const cartera = carteraTotalVaciaReal()
  const [anioTxt = '2026', mesTxt = '09'] = periodo.split('-')
  const nombresMes = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre']
  const filaBase = {
    cierres_referidos: 0,
    cierres_de_arrastre: 0,
    procedencia: [{
      mes: periodo,
      mes_nombre: nombresMes[Number(mesTxt) - 1] ?? 'setiembre',
      anio: Number(anioTxt),
      cierres: 1,
      cierres_referidos: 0,
    }],
    referidos: { recibidos: 0, cerrados: 0, dados_de_alta: 0, aporta_pct: 0 },
    cartera: carteraResponsableVaciaReal(),
  }
  return {
    cartera,
    total: {
      analistas: 2,
      divisor: 20,
      cierres_no_referidos: 2,
      cierres_referidos: 0,
      cierres_de_arrastre: 0,
      referidos_recibidos: 0,
      numerador: 2,
      conversion_pct: 10,
      referidos_aporta_pct: 0,
      cartera,
    },
    responsables: [
      { ...filaBase, vendedor_id: ANALISTA_ANA_ID, supervisor_id: SUPERVISOR_DIEGO_ID, divisor: 12, cierres_no_referidos: 1, numerador: 1, conversion_pct: 8.33, estado: 'medible' },
      { ...filaBase, vendedor_id: ANALISTA_BRUNO_ID, supervisor_id: SUPERVISOR_DIEGO_ID, divisor: 8, cierres_no_referidos: 1, numerador: 1, conversion_pct: 12.5, estado: 'medible' },
    ],
  }
}

/**
 * Foto mensual coherente de agosto para ejercer el ranking REAL de punta a
 * punta. Las tres fuentes usan los mismos UUID/nombres: cumplimiento aporta la
 * identidad y el capital congelados, la mensual aporta la conversión oficial y
 * la cosecha sigue el lote recibido. Si una pantalla vuelve a mezclar el roster
 * vivo con esta foto histórica, los E2E dejan de encontrar estos nombres.
 */
export function rankingAgostoReal(): {
  configuracionMetas: Record<string, unknown>
  cumplimientoMetas: Record<string, unknown>
  conversionMensual: ConversionMensualRealFixture
  cosecha: Record<string, unknown>[]
} {
  const responsables = [
    {
      vendedor_id: ANALISTA_ANA_ID,
      nombre: 'ANA AGOSTO',
      conversion_objetivo: 10,
      conversion_real: 8.33,
      convertidos: 1,
      resueltos: 12,
      numerador: 1,
      cierres_no_referidos: 1,
      cierres_referidos: 0,
      capital_pen: 40_000,
      capital_usd: 1_000,
    },
    {
      vendedor_id: ANALISTA_BRUNO_ID,
      nombre: 'BRUNO AGOSTO',
      conversion_objetivo: 10,
      conversion_real: 12.5,
      convertidos: 1,
      resueltos: 8,
      numerador: 1,
      cierres_no_referidos: 1,
      cierres_referidos: 0,
      capital_pen: 20_000,
      capital_usd: 500,
    },
  ]
  const detalles = (capitalPen: number, capitalUsd: number) => [
    {
      categoria: 'nuevo', moneda: 'PEN', capital_objetivo: 100_000,
      capital_real: capitalPen, capital_cumplimiento_pct: capitalPen / 1_000,
      contratos_objetivo: 2, contratos_real: 1, contratos_cumplimiento_pct: 50,
    },
    {
      categoria: 'nuevo', moneda: 'USD', capital_objetivo: 10_000,
      capital_real: capitalUsd, capital_cumplimiento_pct: capitalUsd / 100,
      contratos_objetivo: 1, contratos_real: 1, contratos_cumplimiento_pct: 100,
    },
    ...(['renovacion', 'upgrade'] as const).flatMap((categoria) => [
      {
        categoria, moneda: 'PEN', capital_objetivo: 0, capital_real: 0,
        capital_cumplimiento_pct: null, contratos_objetivo: 0,
        contratos_real: 0, contratos_cumplimiento_pct: null,
      },
      {
        categoria, moneda: 'USD', capital_objetivo: 0, capital_real: 0,
        capital_cumplimiento_pct: null, contratos_objetivo: 0,
        contratos_real: 0, contratos_cumplimiento_pct: null,
      },
    ]),
  ]

  const conversionBase = conversionMensualReal('2026-08')
  return {
    configuracionMetas: {
      version: 1,
      periodo: '2026-08-01',
      revision: 4,
      publicada_en: '2026-08-01T13:00:00.000Z',
      publicada_por: null,
      publicada_por_nombre: null,
      puede_editar: false,
      sin_supervisor: [],
      vendedores: responsables.map((fila) => ({
        vendedor_id: fila.vendedor_id,
        nombre: fila.nombre,
        supervisor_id: UID,
        supervisor_nombre: 'SUPERVISOR AGOSTO',
        conversion_objetivo: fila.conversion_objetivo,
        detalles: detalles(fila.capital_pen, fila.capital_usd).map((detalle) => ({
          categoria: detalle.categoria,
          moneda: detalle.moneda,
          capital_objetivo: detalle.capital_objetivo,
          contratos_objetivo: detalle.contratos_objetivo,
        })),
      })),
    },
    cumplimientoMetas: {
      version: 1,
      periodo: '2026-08-01',
      revision: 4,
      publicada_en: '2026-08-01T13:00:00.000Z',
      fuentes_reales: {
        capital_y_contratos: 'contratos_confirmados',
        conversion: 'leads_recibidos_ponderado',
      },
      ponderacion_referido: 0.15,
      cierre: { cerrado: false },
      vendedores: responsables.map(({ capital_pen, capital_usd, ...fila }) => ({
        ...fila,
        supervisor_id: UID,
        supervisor_nombre: 'SUPERVISOR AGOSTO',
        ajuste: { pendiente: 0 },
        detalles: detalles(capital_pen, capital_usd),
      })),
    },
    conversionMensual: {
      ...conversionBase,
      responsables: conversionBase.responsables.map((fila) => ({ ...fila, supervisor_id: UID })),
    },
    cosecha: responsables.map((fila) => ({
      vendedor_id: fila.vendedor_id,
      leads: fila.resueltos,
      clientes: fila.convertidos,
      conversion_pct: fila.conversion_real,
      nucleo_divisor: fila.resueltos,
      nucleo_numerador: fila.numerador,
      nucleo_conversion_pct: fila.conversion_real,
    })),
  }
}

/** Snapshot válido de las métricas comerciales que consume el Resumen actual. */
export function metricasConversionesReal(): Record<string, unknown> {
  return {
    origen_filtrado: null,
    version: 1,
    generado_en: '2026-08-07T17:00:00.000Z',
    periodo: periodoMetricasReal(),
    cohorte: {
      leads: 20,
      asignados: 18,
      contactados: 14,
      reuniones_agendadas: 8,
      reuniones_realizadas: 6,
      propuestas: 4,
      clientes: 2,
      contratos: 2,
      descartados: 6,
      conversion_clientes_pct: 10,
      conversion_contratos_pct: 10,
      conversion_resueltos_pct: 25,
    },
    produccion: { clientes: 2, contratos: 2, capital_pen: 125_000, capital_usd: 8_000 },
    embudo: [
      { etapa: 'leads', cantidad: 20, pct_anterior: 100, pct_total: 100 },
      { etapa: 'contactados', cantidad: 14, pct_anterior: 70, pct_total: 70 },
      { etapa: 'reuniones_agendadas', cantidad: 8, pct_anterior: 57.14, pct_total: 40 },
      { etapa: 'reuniones_realizadas', cantidad: 6, pct_anterior: 75, pct_total: 30 },
      { etapa: 'propuestas', cantidad: 4, pct_anterior: 66.67, pct_total: 20 },
      { etapa: 'clientes', cantidad: 2, pct_anterior: 50, pct_total: 10 },
      { etapa: 'contratos', cantidad: 2, pct_anterior: 100, pct_total: 10 },
    ],
    origenes: [{
      origen: 'Referido',
      leads: 20,
      contactados: 14,
      reuniones_agendadas: 8,
      reuniones_realizadas: 6,
      clientes: 2,
      contratos: 2,
      descartados: 6,
      conversion_clientes_pct: 10,
      conversion_contratos_pct: 10,
      conversion_resueltos_pct: 25,
      capital_pen: 125_000,
      capital_usd: 8_000,
      peso_en_nucleo: 0.15,
      fuera_del_divisor_del_nucleo: true,
    }],
    categorias: [],
    responsables: [{
      vendedor_id: 'vend-1',
      leads: 20,
      contactados: 14,
      reuniones_realizadas: 6,
      clientes: 2,
      conversion_pct: 10,
      capital_pen: 125_000,
      capital_usd: 8_000,
      nucleo_divisor: 20,
      nucleo_numerador: 2,
      nucleo_conversion_pct: 10,
      tendencia_semanal: [
        { semana: 1, desde: '2026-08-01', hasta: '2026-08-03', leads: 8, clientes: 1, conversion_pct: 12.5 },
        { semana: 2, desde: '2026-08-04', hasta: '2026-08-07', leads: 12, clientes: 1, conversion_pct: 8.33 },
      ],
    }, {
      vendedor_id: 'vend-2',
      leads: 0,
      contactados: 0,
      reuniones_realizadas: 0,
      clientes: 0,
      conversion_pct: null,
      capital_pen: 0,
      capital_usd: 0,
      nucleo_divisor: 0,
      nucleo_numerador: 0,
      nucleo_conversion_pct: null,
      tendencia_semanal: [
        { semana: 1, desde: '2026-08-01', hasta: '2026-08-03', leads: 0, clientes: 0, conversion_pct: null },
        { semana: 2, desde: '2026-08-04', hasta: '2026-08-07', leads: 0, clientes: 0, conversion_pct: null },
      ],
    }],
    nucleo: {
      base: 'COHORTE_POR_ASIGNACION_REFERIDOS_PONDERADOS',
      divisor: 20,
      numerador: 2,
      conversion_pct: 10,
      cierres_no_referidos: 2,
      cierres_referidos: 0,
      referidos_recibidos: 0,
      referidos_cierran_pct: null,
      operaciones_cartera: 0,
      peso_referido: 0.15,
      mes_peso: '2026-08-01',
      incluye_cartera: true,
    },
    cosecha: {
      base: 'ALTAS_DEL_RANGO',
      leads: 20,
      cerraron: 2,
      conversion_pct: 10,
      madura_hasta: '2026-08-07',
    },
    sondas: {
      cuadra: true,
      paridad_nucleo: 0,
      paridad_filas: 2,
      divisor_fuera_del_roster: 0,
      numerador_fuera_del_roster: 0,
      cierres_sin_ficha_convertida: 0,
      cohorte_convertidos_sin_cierre_elegible: 0,
      cartera_fuera_del_rango: 0,
      cierres_anulados: 0,
      episodios_sin_origen: 0,
      origen_ficha_distinto_del_ledger: 0,
      perfiles_con_leads_de_varios_vendedores: 0,
    },
  }
}

function metricasConversionesVaciasReal(): Record<string, unknown> {
  return {
    origen_filtrado: null,
    version: 1,
    generado_en: '2026-08-07T17:00:00.000Z',
    periodo: periodoMetricasReal(),
    cohorte: {
      leads: 0,
      asignados: 0,
      contactados: 0,
      reuniones_agendadas: 0,
      reuniones_realizadas: 0,
      propuestas: 0,
      clientes: 0,
      contratos: 0,
      descartados: 0,
      conversion_clientes_pct: null,
      conversion_contratos_pct: null,
      conversion_resueltos_pct: null,
    },
    produccion: { clientes: 0, contratos: 0, capital_pen: 0, capital_usd: 0 },
    embudo: [],
    origenes: [],
    categorias: [],
    responsables: [],
  }
}

/** Snapshot válido de reuniones para el Resumen actual. */
export function metricasReunionesReal(): Record<string, unknown> {
  return {
    version: 1,
    generado_en: '2026-08-07T17:00:00.000Z',
    periodo: periodoMetricasReal(),
    resumen: {
      pactadas: 8,
      debieron_ocurrir: 7,
      realizadas: 6,
      no_concretadas: 1,
      no_show: 1,
      canceladas: 0,
      canceladas_sistema: 0,
      reprogramadas: 1,
      pendientes_cierre: 0,
      programadas_futuras: 1,
      pct_realizacion: 85.71,
      pct_asistencia: 85.71,
    },
    conversion: {
      leads_reunidos: 6,
      clientes: 2,
      contratos: 2,
      conversion_cliente_pct: 33.33,
      conversion_contrato_pct: 33.33,
      capital_pen: 125_000,
      capital_usd: 8_000,
    },
    modalidades: [],
    origenes: [],
    responsables: [],
    resultados: [],
  }
}

function metricasReunionesVaciasReal(): Record<string, unknown> {
  const vacias = metricasReunionesReal()
  return {
    ...vacias,
    resumen: {
      pactadas: 0,
      debieron_ocurrir: 0,
      realizadas: 0,
      no_concretadas: 0,
      no_show: 0,
      canceladas: 0,
      canceladas_sistema: 0,
      reprogramadas: 0,
      pendientes_cierre: 0,
      programadas_futuras: 0,
      pct_realizacion: null,
      pct_asistencia: null,
    },
    conversion: {
      leads_reunidos: 0,
      clientes: 0,
      contratos: 0,
      conversion_cliente_pct: null,
      conversion_contrato_pct: null,
      capital_pen: 0,
      capital_usd: 0,
    },
  }
}

function esRegistro(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === 'object' && valor !== null && !Array.isArray(valor)
}

function metricasParaPeriodo(
  payload: unknown,
  desde: string,
  hasta: string,
  origenFiltrado?: string | null,
): unknown {
  if (!esRegistro(payload)) return payload
  if (esRegistro(payload.periodo)) {
    return {
      ...payload,
      ...(origenFiltrado === undefined ? {} : { origen_filtrado: origenFiltrado }),
      periodo: { ...periodoMetricasReal(desde, hasta) },
    }
  }
  if (!esRegistro(payload.cohorte)) return payload
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
/** Fila de `crm.cierres_estado_fn`: el estado del cierre de un lead. */
export interface CierreEstadoReal {
  lead_id: string
  canal: 'avance' | 'cooperativa'
  anulado_en: string | null
  motivo: string | null
}

/** Fila agregada del ledger que alimenta el parte histórico de Coordinación. */
export interface EntregaCoordinacionReal {
  fecha: string
  analista_id: string
  analista_nombre: string
  supervisor_id: string
  supervisor_nombre: string
  origen: string
  derivados: number
}

export interface BackendReal {
  leads: LeadReal[]
  /** Estado del cierre por lead. VACÍO por defecto, que es el estado real de
   *  producción hoy: ningún lead tiene anulación. Un test que quiera la marca
   *  tiene que ponerla a mano. */
  cierresEstado: CierreEstadoReal[]
  /** Lo que gerencia anuló durante la prueba, para aseverar la llamada. */
  anulacionesAvance: { lead_id: string; motivo: string }[]
  rolCrm: string
  /**
   * Rol del PORTAL del usuario (`perfiles.rol`). Define las capacidades nativas
   * del portal. Gerencia obtiene su permiso operativo por el rol CRM activo, sin
   * convertirse en admin/superadmin; Directorio sin rol CRM sigue en lectura.
   * Por defecto 'analista' representa las identidades de fuerza de ventas; los
   * casos de Gerencia usan explícitamente 'comercial' para probar que la
   * autoridad viene del rol CRM. Directorio Portal/CRM siempre coincide.
   */
  rolPortal: string
  /** El próximo GET de leads (carga/resync) responde 500 una vez. */
  fallarProximaCargaLeads: boolean
  /** El próximo PATCH de leads responde 400 (rechazo del servidor, error genérico). */
  fallarProximoPatch: boolean
  /** La próxima RPC de edición responde 400 con 23505/uq_leads_telefono_vivo. */
  fallarProximaEdicionTelefono: boolean
  /** La próxima RPC de alta atómica pierde la última defensa única (23505). */
  fallarProximaCreacionLeadAtomica: boolean
  /** Veredicto de crm.verificar_disponibilidad_lead para P-048. */
  disponibilidadLead: Record<string, unknown>
  /** El próximo POST de actividades responde 400 (nota del descarte, etc.). */
  fallarProximoInsertActividad: boolean
  /** Cualquier GET de leads responde 500 (servidor caído para resync). */
  leadsSiempreCaido: boolean
  /** La RPC resumen_cartera_fn responde 500 SIEMPRE (tiles F1 degradados a «—»). */
  fallarResumenCartera: boolean
  /** La RPC cola_accion_fn responde 500 SIEMPRE (cola degradada). */
  fallarColaAccion: boolean
  /** La RPC metricas_vendedores_fn responde 500 SIEMPRE (ranking/comparativa degradados). */
  fallarMetricasEquipo: boolean
  /** La RPC resumen_reparto_fn responde 500 SIEMPRE (tiles de Repartir a «—»). */
  fallarResumenReparto: boolean
  /** La RPC cartera_pagina_fn responde 500 SIEMPRE (la TABLA de Cartera degradada). */
  fallarCarteraPagina: boolean
  /** Si se setea, resumen_reparto_fn devuelve ESTE payload en vez de derivarlo de
   *  `colaReparto`: sirve para DIVERGIR agregado y filas y probar que el
   *  navegador ya no cuenta (tile en 57 con 2 filas en la lista). */
  resumenRepartoOverride: Record<string, unknown> | null
  /** Clientes del portal (alimentan clientes_basicos y las RPC de ficha/detalle). */
  clientes: PerfilReal[]
  /** El pre-vuelo legal declara el domicilio ausente, sin tocar la fila del cliente. */
  domicilioLegalAusente: boolean
  /** Contratos del portal (con el embed cliente ya resuelto). */
  contratos: ContratoReal[]
  /** Condiciones publicadas y vigentes ofrecidas por el catálogo versionado. */
  productosSeleccionables: Record<string, unknown>[]
  /** Versiones bancarias reutilizables; el slot actual del perfil se deriva aparte. */
  cuentasBancarias: CuentaBancariaReal[]
  /** Enlace cuenta↔contrato creado por el wrapper atómico. */
  cuentasPorContrato: Record<string, string>
  /** Última selección bancaria recibida, para aserciones de frontera. */
  ultimaCuentaPagoContrato: Record<string, unknown> | null
  /** El próximo GET de contratos_cartera responde 500 una vez (panel de error + Reintentar). */
  fallarProximaCargaContratos: boolean
  /** Cronograma por contrato_id (el GET filtra por eq.<id>). */
  cuotas: Record<string, unknown[]>
  /** Co-titulares por contrato_id (cuentas mancomunadas). */
  titulares: Record<string, unknown[]>
  /** Tareas pendientes de crm.tareas (la agenda; el boot las carga SIEMPRE). */
  tareas: Record<string, unknown>[]
  /** Snapshot versionado de crm.configuracion_metas_fn (boot del store). */
  configuracionMetas: Record<string, unknown>
  /** Cumplimiento autoritativo de crm.cumplimiento_metas_fn. */
  cumplimientoMetas: Record<string, unknown>
  /** Respuestas de las RPC de métricas del panel Hoy. */
  metricas: {
    conversiones: Record<string, unknown>
    reuniones: Record<string, unknown>
    capital: unknown[]
    pagos: unknown[]
    altas: unknown[]
    vencimientos: unknown[]
    distribucion: unknown
    /** Analistas de crm.metricas_agenda_fn (panel "Agenda del equipo"). */
    agenda: unknown[]
    /** Total y filas de crm.conversion_mensual_fn (el periodo lo eco-a el handler). */
    conversionMensual: ConversionMensualRealFixture
    /** Filas de crm.metricas_conversiones_equipo_fn (cosecha del lote). */
    cosecha: Record<string, unknown>[]
  }
  /** C1 — cola global que devuelve crm.leads_por_repartir() al coordinador. */
  colaReparto: Record<string, unknown>[]
  /** C1-ter — lo que devuelve crm.leads_descartados() (pestaña Descartados). */
  descartados: Record<string, unknown>[]
  /** C1 — destinos que devuelve crm.supervisores_para_reparto(). */
  supervisoresReparto: Record<string, unknown>[]
  /** Entregas históricas ya agregadas por día, responsable y origen. */
  entregasCoordinacion: EntregaCoordinacionReal[]
  /** Agenda de turnos y conteos que devuelve crm.agenda_reparto_diaria(). */
  agendaReparto: Record<string, unknown> | null
  /**
   * C1 — si está seteado, el próximo crm.repartir_lead responde ese SQLSTATE en
   * vez de repartir (P0429 = veto legal No Insista, P0002 = fuera de cola…).
   */
  fallarProximoReparto: { code: string; message: string } | null
  /** C1-bis — igual que arriba pero para crm.descartar_lead. */
  fallarProximoDescarte: { code: string; message: string } | null
  /** C1-ter — igual pero para crm.deshacer_descarte (ventana vencida, carrera). */
  fallarProximoDeshacer: { code: string; message: string } | null
  /**
   * Simula la TRAMPA de la ventana de 5 h vencida: el PATCH a perfiles responde
   * 200 con [] (0 filas, SIN error) y la RPC actualizar_contrato rechaza P0001.
   */
  ventanaVencida: boolean
  /** El próximo POST a la edge crear-cliente responde 409 (documento duplicado). */
  fallarProximaAlta: boolean
  /** El comando se confirma en el servidor, pero se pierde su respuesta HTTP. */
  perderProximaRespuestaSla: boolean
  /** Contadores para aserciones. */
  llamadas: {
    rpcCrearLeadAtomico: number
    /** Escrituras legacy directas: la UI nueva debe mantener este contador en cero. */
    insertLeadDirecto: number
    rpcDisponibilidadLead: number
    rpcEditarLead: number
    patchLead: number
    insertActividad: number
    rpcSlaComandos: string[]
    getLeads: number
    altaCliente: number
    patchPerfil: number
    rpcActualizarClienteGerencia: number
    rpcListarCuentasBancarias: number
    rpcCompletarDomicilio: number
    rpcCrearContrato: number
    rpcActualizarContrato: number
    rpcMetricasDistribucion: number
    rpcActualizarCapacidad: number
    /** C1 — cuántas veces se llamó a crm.repartir_lead. */
    rpcRepartirLead: number
    /** C1 — cuántas veces se releyó la cola (resincronización tras rechazo). */
    rpcLeadsPorRepartir: number
    /** C1-bis — cuántas veces se llamó a crm.descartar_lead. */
    rpcDescartarLead: number
    /** C1-bis — cuántas veces se llamó a crm.deshacer_descarte. */
    rpcDeshacerDescarte: number
    /** F1b tanda 3 — cuántas veces se pidió el resumen agregado de la cola. */
    rpcResumenReparto: number
    /** F2 — cuántas páginas de cartera keyset pidió la pantalla. */
    rpcCarteraPagina: number
  }
  /** C1 — último par (lead, supervisor) enviado a crm.repartir_lead. */
  ultimoReparto: { lead: string; supervisor: string } | null
  /** C1-bis — último (lead, motivo, nota) enviado a crm.descartar_lead. */
  ultimoDescarte: { lead: string; motivo: string; nota: string | null } | null
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
  await page.route(`${SUPABASE_ORIGIN}/**`, async (route) => {
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
  const rolCrm = init.rolCrm ?? 'gerencia'
  const rolPortal = init.rolPortal ?? 'analista'
  if ((rolCrm === 'directorio') !== (rolPortal === 'directorio')) {
    throw new Error('Fixture inválido: Directorio Portal y Directorio CRM deben coincidir')
  }
  const estado: BackendReal = {
    leads: init.leads ?? [leadReal()],
    cierresEstado: init.cierresEstado ?? [],
    anulacionesAvance: init.anulacionesAvance ?? [],
    rolCrm,
    rolPortal,
    fallarProximaCargaLeads: init.fallarProximaCargaLeads ?? false,
    fallarProximoPatch: init.fallarProximoPatch ?? false,
    fallarProximaEdicionTelefono: init.fallarProximaEdicionTelefono ?? false,
    fallarProximaCreacionLeadAtomica: init.fallarProximaCreacionLeadAtomica ?? false,
    disponibilidadLead: init.disponibilidadLead ?? { estado: 'libre' },
    fallarProximoInsertActividad: init.fallarProximoInsertActividad ?? false,
    leadsSiempreCaido: init.leadsSiempreCaido ?? false,
    fallarResumenCartera: init.fallarResumenCartera ?? false,
    fallarColaAccion: init.fallarColaAccion ?? false,
    fallarMetricasEquipo: init.fallarMetricasEquipo ?? false,
    fallarResumenReparto: init.fallarResumenReparto ?? false,
    fallarCarteraPagina: init.fallarCarteraPagina ?? false,
    resumenRepartoOverride: init.resumenRepartoOverride ?? null,
    clientes: init.clientes ?? [clienteReal()],
    domicilioLegalAusente: init.domicilioLegalAusente ?? false,
    contratos: init.contratos ?? [contratoReal()],
    productosSeleccionables: init.productosSeleccionables
      ?? PRODUCTOS_SELECCIONABLES_REAL.map((fila) => ({ ...fila })),
    cuentasBancarias: init.cuentasBancarias ?? [],
    cuentasPorContrato: init.cuentasPorContrato ?? {},
    ultimaCuentaPagoContrato: init.ultimaCuentaPagoContrato ?? null,
    fallarProximaCargaContratos: init.fallarProximaCargaContratos ?? false,
    cuotas: init.cuotas ?? {},
    titulares: init.titulares ?? {},
    tareas: init.tareas ?? [],
    configuracionMetas: init.configuracionMetas ?? {
      version: 1,
      periodo: '2026-08-01',
      revision: 0,
      publicada_en: null,
      publicada_por: null,
      publicada_por_nombre: null,
      puede_editar: true,
      vendedores: [],
    },
    cumplimientoMetas: init.cumplimientoMetas ?? {
      version: 1,
      periodo: '2026-08-01',
      revision: 0,
      publicada_en: null,
      fuentes_reales: {
        capital_y_contratos: 'contratos_confirmados',
        conversion: 'leads_resueltos',
      },
      vendedores: [],
    },
    metricas: {
      conversiones: init.metricas?.conversiones ?? metricasConversionesVaciasReal(),
      reuniones: init.metricas?.reuniones ?? metricasReunionesVaciasReal(),
      capital: init.metricas?.capital ?? [],
      pagos: init.metricas?.pagos ?? [],
      altas: init.metricas?.altas ?? [],
      vencimientos: init.metricas?.vencimientos ?? [],
      distribucion: init.metricas?.distribucion ?? metricasDistribucionVaciaReal(),
      agenda: init.metricas?.agenda ?? [],
      conversionMensual: init.metricas?.conversionMensual ?? conversionMensualVaciaReal(),
      cosecha: init.metricas?.cosecha ?? [],
    },
    colaReparto: init.colaReparto ?? [],
    descartados: init.descartados ?? [],
    supervisoresReparto: init.supervisoresReparto ?? [],
    entregasCoordinacion: init.entregasCoordinacion ?? [],
    agendaReparto: init.agendaReparto ?? null,
    fallarProximoReparto: init.fallarProximoReparto ?? null,
    fallarProximoDescarte: init.fallarProximoDescarte ?? null,
    fallarProximoDeshacer: init.fallarProximoDeshacer ?? null,
    ventanaVencida: init.ventanaVencida ?? false,
    fallarProximaAlta: init.fallarProximaAlta ?? false,
    perderProximaRespuestaSla: init.perderProximaRespuestaSla ?? false,
    llamadas: {
      rpcCrearLeadAtomico: 0, insertLeadDirecto: 0, rpcDisponibilidadLead: 0,
      rpcEditarLead: 0, patchLead: 0, insertActividad: 0, rpcSlaComandos: [], getLeads: 0,
      altaCliente: 0, patchPerfil: 0, rpcActualizarClienteGerencia: 0,
      rpcListarCuentasBancarias: 0,
      rpcCompletarDomicilio: 0,
      rpcCrearContrato: 0, rpcActualizarContrato: 0,
      rpcMetricasDistribucion: 0, rpcActualizarCapacidad: 0,
      rpcRepartirLead: 0, rpcLeadsPorRepartir: 0,
      rpcDescartarLead: 0, rpcDeshacerDescarte: 0,
      rpcResumenReparto: 0, rpcCarteraPagina: 0,
    },
    ultimaActualizacionCapacidad: init.ultimaActualizacionCapacidad ?? null,
    ultimoReparto: init.ultimoReparto ?? null,
    ultimoDescarte: init.ultimoDescarte ?? null,
  }

  // C1-bis: la última fila descartada, para que deshacer_descarte la devuelva a
  // la cola como haría el servidor real (reabre en 'nuevo' y la cola la lista).
  let filaDescartada: Record<string, unknown> | null = null

  const cors: Record<string, string> = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': '*',
    'access-control-expose-headers': 'content-range',
  }
  const json = (route: Route, obj: unknown, status = 200) => {
    const url = new URL(route.request().url())
    if (status === 200 && Array.isArray(obj) && /\/rest\/v1\/(clientes_basicos|contratos_cartera|operaciones_cartera)$/.test(url.pathname)) {
      const desde = Number(url.searchParams.get('offset') ?? 0)
      const limite = Number(url.searchParams.get('limit') ?? obj.length)
      const filas = obj.slice(desde, desde + limite)
      return route.fulfill({ status, headers: { ...cors,
        'content-range': filas.length ? `${desde}-${desde + filas.length - 1}/${obj.length}` : `*/${obj.length}`,
      }, contentType: 'application/json', body: JSON.stringify(filas) })
    }
    return route.fulfill({ status, headers: cors, contentType: 'application/json', body: JSON.stringify(obj) })
  }

  const recibosSla = new Map<string, { huella: string; respuesta: Record<string, unknown> }>()
  const actividadesSla: Record<string, unknown>[] = []

  await page.route(`${SUPABASE_ORIGIN}/**`, async (route) => {
    const req = route.request()
    const method = req.method()
    const url = new URL(req.url())
    const p = url.pathname

    if (method === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })

    // ── Auth ──
    if (p === '/auth/v1/token') return json(route, SESSION) // password + refresh
    if (p === '/auth/v1/user') return json(route, USER)
    if (p === '/auth/v1/logout') return route.fulfill({ status: 204, headers: cors })

    // ── Acceso canónico + clientes del portal (misma tabla perfiles) ──
    if (p === '/rest/v1/rpc/mi_acceso_fn' && method === 'POST') {
      const esGerencia = estado.rolCrm === 'gerencia'
      const esSuperadmin = estado.rolPortal === 'superadmin'
      if (esSuperadmin && !esGerencia) {
        return json(route, {
          estado: 'administrador_roles',
          perfil_id: UID,
          rol_portal: estado.rolPortal,
          nombre_completo: 'Superadmin Real',
          puede_listar_usuarios: true,
          puede_administrar_usuarios: false,
          puede_organizar_jerarquia: false,
          puede_administrar_roles: true,
          puede_contratar: false,
        })
      }
      return json(route, {
        estado: 'miembro',
        perfil_id: UID,
        rol_crm: estado.rolCrm,
        rol_portal: estado.rolPortal,
        nombre_completo: 'Gerente Real',
        puede_listar_usuarios: esGerencia || esSuperadmin,
        puede_administrar_usuarios: esGerencia,
        puede_organizar_jerarquia: esGerencia,
        puede_administrar_roles: esSuperadmin,
        puede_contratar: ['vendedor', 'supervisor', 'gerencia'].includes(estado.rolCrm),
      })
    }
    if (p === '/rest/v1/equipo') return json(route, [{ rol_crm: estado.rolCrm, activo: true }])
    if (p === '/rest/v1/rpc/usuarios_administrables_fn') {
      return json(route, [])
    }
    if (
      (p === '/rest/v1/rpc/actualizar_cliente_gerencia'
        || p === '/rest/v1/rpc/actualizar_cliente_gerencia_con_domicilio')
      && method === 'POST'
    ) {
      estado.llamadas.rpcActualizarClienteGerencia += 1
      const cuerpo = (req.postDataJSON() ?? {}) as Record<string, unknown>
      const clienteId = String(cuerpo.p_cliente_id ?? '')
      const cambios = (cuerpo.p_patch ?? {}) as Partial<PerfilReal>
      estado.clientes = estado.clientes.map((c) =>
        c.id === clienteId ? { ...c, ...cambios } : c,
      )
      return json(route, true)
    }
    if (p === '/rest/v1/rpc/cliente_ficha_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_cliente_id?: string }
      const clienteId = String(body.p_cliente_id ?? '')
      const cliente = estado.clientes.find((fila) => fila.id === clienteId)
      if (!cliente) return json(route, [])
      return json(route, [{
        id: cliente.id,
        nombres: cliente.nombres,
        apellidos: cliente.apellidos,
        nombre_completo: cliente.nombre_completo,
        tipo_documento: cliente.tipo_documento,
        dni: cliente.dni,
        correo: cliente.correo,
        telefono: cliente.telefono,
        asesor_perfil_id: cliente.asesor_perfil_id,
        activo: cliente.activo,
        creado_en: cliente.creado_en,
      }])
    }
    if (p === '/rest/v1/rpc/cliente_detalle_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_cliente_id?: string }
      const clienteId = String(body.p_cliente_id ?? '')
      const cliente = estado.clientes.find((fila) => fila.id === clienteId)
      if (!cliente) return json(route, [])

      const bancaVisible = estado.rolPortal !== 'directorio' && estado.rolCrm !== 'directorio'
      return json(route, [{
        ...cliente,
        banca_visible: bancaVisible,
        cuentas_bancarias_visibles: bancaVisible && cliente.activo,
        ...(bancaVisible ? {} : {
          domicilio: null,
          banco: null,
          tipo_cuenta: null,
          numero_cuenta: null,
          cci: null,
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
        }),
      }])
    }
    if (p === '/rest/v1/perfiles') {
      const idFiltro = (url.searchParams.get('id') ?? '').replace(/^eq\./, '')
      if (method === 'GET') {
        // El detalle de cliente ya va por cliente_detalle_fn. Esta ruta queda
        // para resolverRol y comprobaciones puntuales del perfil compartido.
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

    if (p === '/rest/v1/rpc/resumen_cartera_clientes_fn' && method === 'POST') {
      // Fixture del endpoint existente; nunca interviene en el bundle real.
      const r = resumenCartera(agruparCartera(
        estado.clientes as unknown as ClienteBasico[], estado.contratos as unknown as ContratoRow[],
      ))
      return json(route, {
        version: 1, generado_en: new Date().toISOString(), zona: 'America/Lima', dias_alarma_renovacion: 30,
        clientes: { en_gestion: r.totalClientes, de_baja: estado.clientes.length - r.totalClientes,
          con_capital: r.clientesConCapital, sin_asesor: 0 },
        capital_activo: { pen: r.capitalActivoPen, usd: r.capitalActivoUsd },
        contratos: { por_estado: {}, por_vencer_30: r.porVencer30, por_vencer_30_de_baja: r.porVencer30DeBaja },
      })
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
        // Con `asesor_perfil_id` NULL, `creado_por` define el dueño de cartera (regla de Corregir/+Contrato).
        creado_por: c.creado_por,
        activo: c.activo,
        creado_en: c.creado_en,
      })))
    }

    // ── Historial comercial de la Ficha 360 ──
    // Vacío explícito: la prueba del detalle valida navegación y alcance, no
    // inventa actividades ni movimientos económicos que el escenario no pidió.
    if (p === '/rest/v1/actividades_cliente' && method === 'GET') {
      return json(route, [])
    }
    if (p === '/rest/v1/operaciones_cartera' && method === 'GET') {
      return json(route, [])
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

    if (p === '/rest/v1/rpc/productos_inversion_seleccion_fn') {
      return json(route, estado.productosSeleccionables)
    }

    if (p === '/rest/v1/rpc/cronograma_contrato_fn' && method === 'POST') {
      const cid = String(((req.postDataJSON() ?? {}) as { p_contrato_id?: string }).p_contrato_id ?? '')
      return json(route, estado.cuotas[cid] ?? [])
    }

    if (p === '/rest/v1/rpc/titulares_contrato_fn' && method === 'POST') {
      const cid = String(((req.postDataJSON() ?? {}) as { p_contrato_id?: string }).p_contrato_id ?? '')
      return json(route, estado.titulares[cid] ?? [])
    }

    // ── Cuenta contractual: listado scopeado por cliente + moneda ──
    if (p === '/rest/v1/rpc/cuentas_bancarias_cliente_fn' && method === 'POST') {
      estado.llamadas.rpcListarCuentasBancarias += 1
      const body = (req.postDataJSON() ?? {}) as {
        p_cliente_id?: string
        p_moneda?: string
      }
      const clienteId = String(body.p_cliente_id ?? '')
      const moneda = body.p_moneda === 'USD' ? 'USD' : 'PEN'
      const cliente = estado.clientes.find((fila) => fila.id === clienteId)
      if (
        !cliente?.activo
        || estado.rolPortal === 'directorio'
        || estado.rolCrm === 'directorio'
      ) {
        return json(route, { message: 'Cliente fuera del ámbito bancario activo', code: '42501' }, 403)
      }
      const guardadas = estado.cuentasBancarias
        .filter((cuenta) => cuenta.cliente_id === clienteId && cuenta.moneda === moneda)
        .map(({ cliente_id: _clienteId, ...fila }) => fila)
      const perfil = cliente ? cuentaPerfilReal(cliente, moneda) : null
      // La RPC real no duplica el slot del perfil cuando ya existe la misma
      // versión activa. El mock conserva esa semántica para no ofrecer dos radios
      // indistinguibles en las pruebas.
      const perfilYaVersionado = perfil != null && guardadas.some((cuenta) =>
        cuenta.banco === perfil.banco
        && cuenta.tipo_cuenta === perfil.tipo_cuenta
        && cuenta.numero_cuenta === perfil.numero_cuenta
        && cuenta.cci === perfil.cci
        && cuenta.titular_distinto === perfil.titular_distinto
        && cuenta.beneficiario_nombre === perfil.beneficiario_nombre
        && cuenta.beneficiario_dni === perfil.beneficiario_dni,
      )
      return json(route, perfil && !perfilYaVersionado ? [...guardadas, perfil] : guardadas)
    }

    // Política explícita del banco E2E. Las pruebas de solicitudes pueden
    // sustituir estas rutas; las demás no deben simular un servidor sin R3/R4.
    if (['/rest/v1/rpc/solicitudes_tasa_fn','/rest/v1/rpc/solicitudes_tasa_lead_fn'].includes(p) && method === 'POST') return json(route, [])
    if (p === '/rest/v1/rpc/politica_rentabilidad_fn' && method === 'POST') return json(route, {
      version: 1, observacion_sin_aprobacion: true, expected_version: 6,
      vigente: { id: 'politica-e2e', version: 6, vigente_desde: '2026-09-01T00:00:00Z',
        tasa_base_nueva: 15, regla_renovacion: 'heredar', regla_upgrade: 'heredar', tope_tecnico: 28,
        vigencia_solicitud_dias: 1, modo: 'enforcement', nota: null, publicada_en: '2026-09-01T00:00:00Z' },
      historial: [], observacion_activa_desde: null, puede_publicar: false,
    })
    if (['/rest/v1/rpc/resolver_tasa_fn','/rest/v1/rpc/resolver_tasa_lead_fn'].includes(p) && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_cliente_id?: string; p_categoria?: string }
      return json(route, {
        cliente_id: body.p_cliente_id ?? null, categoria: body.p_categoria,
        tasa_base: 15, regla: 'primera_inversion', contrato_origen: null,
        contratos_previos: 0, contratos_activos: 0, prioridad_bandeja: false,
        politica: { id: 'politica-e2e', version: 6, modo: 'enforcement', tasa_base_nueva: 15, tope_tecnico: 19, vigencia_solicitud_dias: 1 },
      })
    }
    if (p === '/rest/v1/rpc/observacion_rentabilidad_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string; p_hasta?: string }
      return json(route, {
        version: 1, periodo: { desde: body.p_desde, hasta: body.p_hasta },
        politica: { version: 6, modo: 'enforcement', tasa_base_nueva: 15 },
        totales: { observados: 0, contratos: 0, eventos: 0, divergentes: 0,
          ceden: 0, retienen: 0, sin_regla: 0, correcciones: 0, puntos_promedio_cedido: 0,
          cedido: { PEN: 0, USD: 0 }, retenido: { PEN: 0, USD: 0 } },
        por_regla: [], por_analista: [], sin_regla: [], ultimos_divergentes: [],
        metodo: 'Libro de observación del banco E2E', altas_sin_observar: 0,
        coherente: true, generado_en: new Date().toISOString(),
      })
    }

    // ── RPC CRM: pre-vuelo legal del contrato + relleno del domicilio ──
    // Sin estas dos rutas, cada apertura de "Crear contrato" disparaba una
    // petición contra un backend inexistente: los e2e pasaban en verde SOLO
    // porque el pre-vuelo está diseñado para no bloquear cuando falla. Es
    // decir, no probaban nada del camino nuevo (gate de REALIDAD).
    if (p === '/rest/v1/rpc/datos_legales_contrato_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_cliente_id?: string }
      const clienteId = String(body.p_cliente_id ?? '')
      const cliente = estado.clientes.find((fila) => fila.id === clienteId)
      const faltanCliente: string[] = []
      if (!cliente?.nombre_completo?.trim()) faltanCliente.push('nombre_completo')
      if (!cliente?.tipo_documento?.trim()) faltanCliente.push('tipo_documento')
      if (!cliente?.dni?.trim()) faltanCliente.push('documento')
      if (estado.domicilioLegalAusente || !cliente?.domicilio?.trim()) faltanCliente.push('domicilio')
      if (!cliente?.correo?.trim()) faltanCliente.push('correo')
      return json(route, {
        version: 1,
        cliente_id: clienteId,
        falta_domicilio: faltanCliente.includes('domicilio'),
        faltan_cliente: faltanCliente,
        faltan_analista: [],
      })
    }

    if (p === '/rest/v1/rpc/completar_domicilio_cliente' && method === 'POST') {
      estado.llamadas.rpcCompletarDomicilio += 1
      const body = (req.postDataJSON() ?? {}) as {
        p_cliente_id?: string
        p_domicilio?: string
      }
      const cliente = estado.clientes.find((fila) => fila.id === String(body.p_cliente_id ?? ''))
      if (!cliente) return json(route, { version: 1, accion: 'conservado' })
      // Espeja la regla del servidor: NUNCA pisa un domicilio existente.
      if (!estado.domicilioLegalAusente && cliente.domicilio?.trim()) {
        return json(route, { version: 1, accion: 'conservado' })
      }
      cliente.domicilio = String(body.p_domicilio ?? '').trim()
      estado.domicilioLegalAusente = false
      return json(route, { version: 1, accion: 'completado' })
    }

    // ── RPC CRM: cuenta + contrato + cronograma en una transacción ──
    if (
      (p === '/rest/v1/rpc/crear_contrato_con_cuenta_producto'
        || p === '/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2')
      && method === 'POST'
    ) {
      estado.llamadas.rpcCrearContrato += 1
      const body = (req.postDataJSON() ?? {}) as {
        p_producto_condicion_id?: string
        p_contrato?: Record<string, unknown>
        p_cuenta?: Record<string, unknown>
      }
      const pc = body.p_contrato ?? {}
      const condicionId = body.p_producto_condicion_id
        ?? (pc.moneda === 'USD' ? PRODUCTO_CONDICION_USD_ID : PRODUCTO_CONDICION_PEN_ID)
      const condicion = estado.productosSeleccionables.find(
        (fila) => fila.condicion_id === condicionId,
      )
      const cuentaElegida = body.p_cuenta
      estado.ultimaCuentaPagoContrato = cuentaElegida
        ? JSON.parse(JSON.stringify(cuentaElegida)) as Record<string, unknown>
        : null
      // Espejo del servidor: sin numero_contrato inventa la numeración VIEJA
      // 'AC-2026-XXXX' (por eso el campo del CRM debe ser obligatorio).
      const numero = typeof pc.numero_contrato === 'string' && pc.numero_contrato
        ? pc.numero_contrato
        : `AC-2026-0${900 + estado.contratos.length}`
      const clienteId = String(pc.cliente_id ?? '')
      const duenio = estado.clientes.find((c) => c.id === clienteId)
      const moneda = pc.moneda === 'USD' ? 'USD' : 'PEN'
      if (!duenio || !cuentaElegida || !condicion) {
        return json(route, { code: 'P0001', message: 'Cliente, producto o cuenta de pago inválidos' }, 400)
      }

      let cuentaId: string | null = null
      if (cuentaElegida.tipo === 'existente') {
        const id = String(cuentaElegida.cuenta_id ?? '')
        const existente = estado.cuentasBancarias.find((cuenta) =>
          cuenta.cuenta_id === id
          && cuenta.cliente_id === clienteId
          && cuenta.moneda === moneda,
        )
        if (!existente) {
          return json(route, { code: 'P0001', message: 'La cuenta seleccionada no está disponible' }, 400)
        }
        cuentaId = existente.cuenta_id
      } else if (cuentaElegida.tipo === 'perfil') {
        const perfil = cuentaPerfilReal(duenio, moneda)
        const esperada = esRegistro(cuentaElegida.cuenta_esperada)
          ? cuentaElegida.cuenta_esperada
          : null
        const coincide = perfil != null && esperada != null
          && perfil.banco === esperada.banco
          && perfil.tipo_cuenta === esperada.tipo_cuenta
          && perfil.numero_cuenta === esperada.numero_cuenta
          && perfil.cci === esperada.cci
          && perfil.titular_distinto === esperada.titular_distinto
          && perfil.beneficiario_nombre === esperada.beneficiario_nombre
          && perfil.beneficiario_dni === esperada.beneficiario_dni
        if (!perfil || !coincide) {
          return json(route, { code: 'P0001', message: 'La cuenta actual del perfil cambió' }, 400)
        }
        const version = cuentaBancariaReal({
          cliente_id: clienteId,
          ...perfil,
          cuenta_id: `f0000000-0000-4000-8000-${String(estado.cuentasBancarias.length + 1).padStart(12, '0')}`,
          origen: 'perfil',
          es_cuenta_perfil: false,
          creada_en: new Date().toISOString(),
        })
        estado.cuentasBancarias.push(version)
        cuentaId = version.cuenta_id
      } else if (cuentaElegida.tipo === 'nueva') {
        if (
          typeof cuentaElegida.banco !== 'string'
          || (cuentaElegida.tipo_cuenta !== 'ahorros' && cuentaElegida.tipo_cuenta !== 'corriente')
          || typeof cuentaElegida.numero_cuenta !== 'string'
          || typeof cuentaElegida.cci !== 'string'
        ) {
          return json(route, { code: 'P0001', message: 'La cuenta nueva está incompleta' }, 400)
        }
        const nueva = cuentaBancariaReal({
          cliente_id: clienteId,
          cuenta_id: `f0000000-0000-4000-8000-${String(estado.cuentasBancarias.length + 1).padStart(12, '0')}`,
          moneda,
          banco: cuentaElegida.banco,
          tipo_cuenta: cuentaElegida.tipo_cuenta,
          numero_cuenta: cuentaElegida.numero_cuenta,
          cci: cuentaElegida.cci,
          titular_distinto: cuentaElegida.titular_distinto === true,
          beneficiario_nombre: typeof cuentaElegida.beneficiario_nombre === 'string'
            ? cuentaElegida.beneficiario_nombre
            : null,
          beneficiario_dni: typeof cuentaElegida.beneficiario_dni === 'string'
            ? cuentaElegida.beneficiario_dni
            : null,
          origen: 'contrato',
          es_cuenta_perfil: false,
          creada_en: new Date().toISOString(),
        })
        estado.cuentasBancarias.push(nueva)
        cuentaId = nueva.cuenta_id
      }
      if (!cuentaId) {
        return json(route, { code: 'P0001', message: 'Tipo de cuenta de pago inválido' }, 400)
      }

      const idContrato = `e0000000-0000-4000-8000-${String(estado.contratos.length + 1).padStart(12, '0')}`
      const nuevo = contratoReal({
        ...(pc as Partial<ContratoReal>),
        id: idContrato,
        numero_contrato: numero,
        cliente_id: clienteId,
        creado_en: new Date().toISOString(), // recién creado → ventana de 5 h viva
        cliente_nombre: duenio.nombre_completo,
        producto_condicion_id: String(condicion.condicion_id),
        producto_id: String(condicion.producto_id),
        producto_codigo: String(condicion.producto_codigo),
        producto_version_id: String(condicion.version_id),
        producto_version: Number(condicion.numero_version),
        producto_nombre: String(condicion.version_nombre),
        producto_version_estado: 'publicada',
      })
      estado.contratos = [nuevo, ...estado.contratos]
      estado.cuentasPorContrato[nuevo.id] = cuentaId
      const respuesta: Record<string, unknown> = {
        id: nuevo.id,
        numero_contrato: numero,
        cuenta_bancaria_id: cuentaId,
        producto_condicion_id: condicion.condicion_id,
        producto_id: condicion.producto_id,
        producto_revision: condicion.producto_revision,
        version_id: condicion.version_id,
        version_revision: 1,
        numero_version: condicion.numero_version,
        version_estado: 'publicada',
        version_nombre: condicion.version_nombre,
      }
      if (p.endsWith('_pdf_v2')) {
        const jobId = `a0000000-0000-4000-8000-${String(estado.contratos.length).padStart(12, '0')}`
        respuesta.pdf = {
          contrato_id: nuevo.id,
          job_id: jobId,
          estado: 'pendiente',
          storage_bucket: 'contratos-generados',
          storage_path: `${nuevo.id}/v2/${jobId}/contrato.pdf`,
          nombre_archivo: `Contrato-${numero}.pdf`,
          template_version: 'contrato-aep-17-v5',
          intentos: 0,
          lease_expira_en: null,
          reintentable: true,
          sha256: null,
          bytes: null,
          archivo: null,
        }
      }
      return json(route, respuesta)
    }

    // ── RPC CRM de corrección: preserva la coherencia de la cuenta fijada ──
    if (
      (p === '/rest/v1/rpc/actualizar_contrato_con_cuenta_producto'
        || p === '/rest/v1/rpc/actualizar_contrato_con_cuenta_pdf_v3')
      && method === 'POST'
    ) {
      estado.llamadas.rpcActualizarContrato += 1
      if (estado.ventanaVencida) {
        // A diferencia del PATCH a perfiles, la RPC SÍ es ruidosa: RAISE → P0001.
        return json(route, {
          code: 'P0001',
          message: 'Solo puedes corregir un contrato dentro de las 5 horas de creado',
          details: '',
        }, 400)
      }
      const body = (req.postDataJSON() ?? {}) as {
        p_id?: string
        p_producto_condicion_id?: string
        p_contrato?: Record<string, unknown>
      }
      const { titulares: titularesNuevos, ...cambios } = (body.p_contrato ?? {}) as
        Record<string, unknown> & { titulares?: unknown[] }
      const pId = String(body.p_id ?? '')
      const contratoActual = estado.contratos.find((contrato) => contrato.id === pId)
      const condicion = estado.productosSeleccionables.find(
        (fila) => fila.condicion_id === (
          body.p_producto_condicion_id ?? contratoActual?.producto_condicion_id
        ),
      )
      if (!contratoActual || !condicion) {
        return json(route, { code: 'P0001', message: 'Contrato o producto inválido' }, 400)
      }
      estado.contratos = estado.contratos.map((contrato) => contrato.id === pId
        ? {
            ...contrato,
            ...cambios,
            producto_condicion_id: String(condicion.condicion_id),
            producto_id: String(condicion.producto_id),
            producto_codigo: String(condicion.producto_codigo),
            producto_version_id: String(condicion.version_id),
            producto_version: Number(condicion.numero_version),
            producto_nombre: String(condicion.version_nombre),
            producto_version_estado: 'publicada',
          }
        : contrato)
      // Semántica del servidor: clave ausente = no tocar; presente (incl. []) = reemplazar.
      if (titularesNuevos) {
        estado.titulares[pId] = titularesNuevos.map((t, i) => ({ ...(t as object), orden: i + 1 }))
      }
      return json(route, {
        id: pId,
        ok: true,
        producto_condicion_id: condicion.condicion_id,
        producto_id: condicion.producto_id,
        producto_revision: condicion.producto_revision,
        version_id: condicion.version_id,
        version_revision: 1,
        numero_version: condicion.numero_version,
        version_estado: 'publicada',
        version_nombre: condicion.version_nombre,
      })
    }

    // ── edge crear-cliente (alta REAL en el portal: Auth + perfil + correo) ──
    // Estado productivo degradado: todavía no se configuró el envío de avisos.
    if (p === '/functions/v1/crm-notificaciones-tasa' && method === 'POST') {
      return json(route, { configurado: false, clavePublica: '', dispositivo: null })
    }
    if (p === '/functions/v1/crear-cliente' && method === 'POST') {
      estado.llamadas.altaCliente += 1
      if (estado.fallarProximaAlta) {
        estado.fallarProximaAlta = false
        return json(route, { error: 'Este documento ya está registrado para otro cliente.' }, 409)
      }
      const b = (req.postDataJSON() ?? {}) as Record<string, unknown>
      // Espejo de la frontera real (_shared/bancarios.mjs): sin al menos una
      // cuenta la edge RECHAZA y no se crea nada. Es el punto del blindaje —
      // aquí se comprueba que el front no puede saltárselo.
      const banc = (b.bancarios ?? {}) as { pen?: Record<string, unknown>; usd?: Record<string, unknown> }
      const conCuenta = (s?: Record<string, unknown>) => !!(s && String(s.banco ?? '').trim() && String(s.cci ?? '').trim())
      if (!conCuenta(banc.pen) && !conCuenta(banc.usd)) {
        return json(
          route,
          { error: 'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.' },
          400,
        )
      }
      const nuevo = clienteReal({
        id: `cli-nuevo-${estado.clientes.length + 1}`,
        nombre_completo: String(b.nombre_completo ?? ''),
        nombres: (b.nombres as string | undefined) ?? null,
        apellidos: (b.apellidos as string | undefined) ?? null,
        tipo_documento: String(b.tipo_documento ?? 'DNI'),
        dni: (b.dni as string | undefined) ?? null,
        correo: (b.email as string | undefined) ?? null,
        telefono: (b.telefono as string | undefined) ?? null,
        domicilio: (b.domicilio as string | undefined) ?? null,
        creado_en: new Date().toISOString(), // recién creado → ventana de 5 h viva
        // El cliente NACE con su cuenta: mismo INSERT, sin segundo paso.
        banco: (banc.pen?.banco as string | undefined) || null,
        tipo_cuenta: (banc.pen?.tipo_cuenta as string | undefined) || null,
        numero_cuenta: (banc.pen?.numero_cuenta as string | undefined) || null,
        cci: (banc.pen?.cci as string | undefined) || null,
      })
      estado.clientes = [nuevo, ...estado.clientes]
      return json(route, { ok: true, user_id: nuevo.id, email: nuevo.correo, email_enviado: true })
    }

    // ── Edge PDF v2: jamás sale de loopback en E2E. Los contratos fixture son
    // legacy (sin reserva) para ejercitar la corrección histórica; el alta v2
    // ya fue confirmada atómicamente y aquí queda pendiente de worker.
    if (p === '/functions/v1/crm-contrato-pdf-v2' && method === 'POST') {
      const b = (req.postDataJSON() ?? {}) as { action?: string; contratoId?: string }
      const contratoId = String(b.contratoId ?? '')
      const esAltaV2 = contratoId.startsWith('e0000000-0000-4000-8000-')
      const jobId = esAltaV2
        ? `a0000000-0000-4000-8000-${contratoId.slice(-12)}`
        : null
      return json(route, {
        pdf: {
          contrato_id: contratoId,
          job_id: jobId,
          estado: esAltaV2 ? 'pendiente' : 'sin_reserva',
          storage_bucket: 'contratos-generados',
          storage_path: jobId ? `${contratoId}/v2/${jobId}/contrato.pdf` : null,
          nombre_archivo: jobId ? 'Contrato-archivo-pendiente.pdf' : null,
          template_version: jobId ? 'contrato-aep-17-v5' : null,
          intentos: 0,
          lease_expira_en: null,
          reintentable: true,
          sha256: null,
          bytes: null,
          archivo: null,
        },
      }, esAltaV2 && b.action === 'ensure' ? 202 : 200)
    }

    // ── cargarReal ──
    if (p === '/rest/v1/rpc/equipo_visible_fn') return json(route, ROSTER)
    // P-055 Fase 3: el detalle pregunta de quién es la venta. NULL = «no puedes
    // ver ese contrato» y el bloque no se pinta — suficiente para estos specs.
    if (p === '/rest/v1/rpc/atribucion_contrato_fn') return json(route, null)
    // Fase 3 «sin topes»: el arranque ya NO baja `actividades_del_ambito_fn`
    // (sin ruta a propósito: una llamada olvidada falla por loopback muerto).
    // La bitácora de Hoy · Directorio pide las N más recientes con el nombre
    // del lead embebido, como `crm.actividades_recientes_fn`.
    if (p === '/rest/v1/rpc/actividades_recientes_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_limite?: number }
      const items = [...actividadesSla]
        .sort((a, b) => String(b.creado_en).localeCompare(String(a.creado_en)) || String(a.id).localeCompare(String(b.id)))
        .slice(0, Number(body.p_limite ?? 8))
        .map((a) => ({ ...a, lead_nombre: estado.leads.find((l) => l.id === a.lead_id)?.nombre_completo ?? null }))
      return json(route, { version: 1, items })
    }
    // Historial POR LEAD (Fase 1 «sin topes»): páginas por cursor keyset
    // (creado_en desc, id asc) sobre las mismas gestiones que registra este mock,
    // más las señales «alguna vez» que el pipeline usa para el retroceso.
    if (p === '/rest/v1/rpc/actividades_de_lead_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_lead_id?: string; p_limite?: number; p_antes_de?: string; p_antes_id?: string }
      const leadId = String(body.p_lead_id ?? '')
      if (!estado.leads.some((l) => l.id === leadId && l.activo !== false)) {
        return json(route, { message: 'Lead fuera de tu cartera', code: '42501', details: null, hint: null }, 403)
      }
      const delLead = actividadesSla.filter((a) => a.lead_id === leadId)
        .sort((a, b) => String(b.creado_en).localeCompare(String(a.creado_en)) || String(a.id).localeCompare(String(b.id)))
      const desde = body.p_antes_de
        ? delLead.findIndex((a) => a.creado_en === body.p_antes_de && a.id === body.p_antes_id) + 1
        : 0
      const tipos = new Set(delLead.map((a) => String(a.tipo)))
      const conversaciones = delLead.filter((a) => ['llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'].includes(String(a.tipo)))
      return json(route, {
        version: 1,
        items: delLead.slice(desde, desde + Number(body.p_limite ?? 100)),
        senales: {
          tiene_reunion_realizada: tipos.has('reunion_realizada'),
          tiene_contacto: ['llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada'].some((t) => tipos.has(t)),
          ultima_conversacion_en: conversaciones[0]?.creado_en ?? null,
        },
      })
    }
    if (p === '/rest/v1/rpc/verificar_disponibilidad_lead' && method === 'POST') {
      estado.llamadas.rpcDisponibilidadLead += 1
      return json(route, estado.disponibilidadLead)
    }
    if (p === '/rest/v1/rpc/crear_lead_si_disponible' && method === 'POST') {
      estado.llamadas.rpcCrearLeadAtomico += 1
      if (estado.fallarProximaCreacionLeadAtomica) {
        estado.fallarProximaCreacionLeadAtomica = false
        return json(route, {
          code: '23505',
          message: 'duplicate key value violates unique constraint',
          details: 'uq_leads_telefono_vivo',
        }, 409)
      }

      const cuerpo = (req.postDataJSON() ?? {}) as Record<string, unknown>
      const id = String(cuerpo.p_id ?? '')
      estado.leads = [leadReal({
        id,
        nombre_completo: String(cuerpo.p_nombre_completo ?? ''),
        telefono: String(cuerpo.p_telefono ?? ''),
        correo: (cuerpo.p_correo as string | null | undefined) ?? null,
        dni: (cuerpo.p_dni as string | null | undefined) ?? null,
        distrito: (cuerpo.p_distrito as string | null | undefined) ?? null,
        origen: cuerpo.p_origen as LeadReal['origen'],
        etapa: cuerpo.p_etapa as LeadReal['etapa'],
        monto_estimado: Number(cuerpo.p_monto_estimado),
        moneda: cuerpo.p_moneda as LeadReal['moneda'],
        categoria_interes:
          (cuerpo.p_categoria_interes as LeadReal['categoria_interes'] | undefined) ?? null,
        vendedor_id: (cuerpo.p_vendedor_id as string | null | undefined) ?? null,
        nota: (cuerpo.p_nota as string | null | undefined) ?? null,
      }), ...estado.leads]
      return json(route, { estado: 'creado', lead_id: id })
    }

    // ── C1: reparto de la cola global (pantalla del coordinador) ──
    if (p === '/rest/v1/rpc/leads_por_repartir') {
      estado.llamadas.rpcLeadsPorRepartir += 1
      return json(route, estado.colaReparto)
    }
    if (p === '/rest/v1/rpc/supervisores_para_reparto') {
      return json(route, estado.supervisoresReparto)
    }
    if (p === '/rest/v1/rpc/agenda_reparto_diaria' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string }
      const desde = String(body.p_desde ?? '2026-01-01')
      return json(route, estado.agendaReparto ?? {
        version: 1,
        fecha_desde: desde,
        destinos: [],
        dias: [],
      })
    }
    if (p === '/rest/v1/rpc/reporte_derivaciones_coordinacion_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string; p_hasta?: string }
      return json(route, reporteDerivacionesCoordinacionReal(
        estado.entregasCoordinacion,
        String(body.p_desde ?? ''),
        String(body.p_hasta ?? ''),
      ))
    }
    if (p === '/rest/v1/rpc/panel_distribucion_reparto') {
      return json(route, {
        version: 1,
        generado_en: '2026-08-25T16:00:00.000Z',
        total_leads: estado.supervisoresReparto.reduce(
          (total, supervisor) => total + Number(supervisor.bandeja_pendiente ?? 0),
          0,
        ),
        supervisores: estado.supervisoresReparto.map((supervisor) => ({
          perfil_id: supervisor.perfil_id,
          nombre: supervisor.nombre,
          total_leads: Number(supervisor.bandeja_pendiente ?? 0),
        })),
        analistas: [],
      })
    }
    if (p === '/rest/v1/rpc/leads_descartados') {
      return json(route, estado.descartados)
    }
    if (p === '/rest/v1/rpc/repartir_lead' && method === 'POST') {
      estado.llamadas.rpcRepartirLead += 1
      const args = (req.postDataJSON() ?? {}) as { p_lead?: string; p_supervisor?: string }
      estado.ultimoReparto = { lead: args.p_lead ?? '', supervisor: args.p_supervisor ?? '' }
      const fallo = estado.fallarProximoReparto
      if (fallo) {
        // El servidor RECHAZA y revierte: la cola NO cambia (el frontend debe
        // resincronizar, no adivinar).
        estado.fallarProximoReparto = null
        return json(route, { code: fallo.code, message: fallo.message }, 400)
      }
      // Éxito: el lead sale de la cola global (pasa a la bandeja del supervisor).
      estado.colaReparto = estado.colaReparto.filter((l) => l.id !== args.p_lead)
      estado.supervisoresReparto = estado.supervisoresReparto.map((s) =>
        s.perfil_id === args.p_supervisor
          ? { ...s, bandeja_pendiente: Number(s.bandeja_pendiente ?? 0) + 1 }
          : s,
      )
      return json(route, {
        lead_id: args.p_lead,
        asignado_supervisor_id: args.p_supervisor,
        repartido_en: '2026-07-22T16:00:00.000Z',
      })
    }
    // ── C1-bis: descartar y deshacer (segunda malla del coordinador) ──
    if (p === '/rest/v1/rpc/descartar_lead' && method === 'POST') {
      estado.llamadas.rpcDescartarLead += 1
      const args = (req.postDataJSON() ?? {}) as { p_lead?: string; p_motivo?: string; p_nota?: string }
      estado.ultimoDescarte = {
        lead: args.p_lead ?? '',
        motivo: args.p_motivo ?? '',
        nota: args.p_nota ?? null,
      }
      const fallo = estado.fallarProximoDescarte
      if (fallo) {
        estado.fallarProximoDescarte = null
        return json(route, { code: fallo.code, message: fallo.message }, 400)
      }
      // Éxito: la fila sale de la cola; se recuerda para que deshacer la devuelva
      // (espejo del servidor: reabre en 'nuevo' y la cola la vuelve a listar).
      filaDescartada = estado.colaReparto.find((l) => l.id === args.p_lead) ?? null
      estado.colaReparto = estado.colaReparto.filter((l) => l.id !== args.p_lead)
      return json(route, {
        lead_id: args.p_lead,
        motivo_descarte: args.p_motivo,
        descartado_en: '2026-07-24T16:00:00.000Z',
        ya_estaba: false,
      })
    }
    if (p === '/rest/v1/rpc/deshacer_descarte' && method === 'POST') {
      estado.llamadas.rpcDeshacerDescarte += 1
      const args = (req.postDataJSON() ?? {}) as { p_lead?: string }
      const fallo = estado.fallarProximoDeshacer
      if (fallo) {
        estado.fallarProximoDeshacer = null
        return json(route, { code: fallo.code, message: fallo.message }, 400)
      }
      // Éxito: sale de la lista de descartados y (si venía de la cola) vuelve.
      estado.descartados = estado.descartados.filter((d) => d.id !== args.p_lead)
      if (filaDescartada && filaDescartada.id === args.p_lead) {
        estado.colaReparto = [...estado.colaReparto, filaDescartada]
        filaDescartada = null
      }
      return json(route, { lead_id: args.p_lead, etapa: 'nuevo', ciclo_actual: 2 })
    }

    // ── agenda: crm.tareas (el boot las carga SIEMPRE junto a los leads) ──
    // Fase 2 «sin topes»: la agenda pide las tareas pendientes por cursor
    // (vence_en asc, id asc) en lotes, sobre el mismo estado que el SELECT
    // directo servía. El mock pagina como el servidor: ancladas a lead o
    // perfil, pendientes y activas, después del cursor, `p_limite` filas.
    if (p === '/rest/v1/rpc/tareas_pendientes_fn' && method === 'POST') {
      // Fase 4e: el arranque ya no baja leads; «carga inicial caída» se simula
      // tirando la primera lectura del arranque que sí queda (las tareas).
      if (estado.leadsSiempreCaido) {
        return json(route, { message: 'tareas caidas', code: 'PGRST000', details: null, hint: null }, 500)
      }
      const body = (req.postDataJSON() ?? {}) as { p_limite?: number; p_despues_de?: string; p_despues_id?: string }
      const pendientes = estado.tareas
        .filter((t) => t.estado === 'pendiente' && t.activo !== false && (t.lead_id || t.perfil_id))
        .sort((a, b) => String(a.vence_en).localeCompare(String(b.vence_en)) || String(a.id).localeCompare(String(b.id)))
      // Keyset REAL por valor, como `(vence_en, id) > (cursor)` en el servidor: si la
      // fila del cursor desaparece entre lotes, la lectura sigue desde su valor.
      const despuesDe = body.p_despues_de
      const despuesId = String(body.p_despues_id ?? '')
      const siguientes = despuesDe
        ? pendientes.filter((t) => String(t.vence_en) > despuesDe || (String(t.vence_en) === despuesDe && String(t.id) > despuesId))
        : pendientes
      // Fase 2 + 4b: el lead embebido (nombre, etapa, teléfono, capital y
      // tenencia) bajo `leads_select`; nulo si el lead no es visible.
      const leadDe = (id: unknown) => estado.leads.find((l) => l.id === id)
      const items = siguientes.slice(0, Number(body.p_limite ?? 500)).map((t) => {
        const l = leadDe(t.lead_id)
        return {
          ...t,
          lead_nombre: l?.nombre_completo ?? null, lead_etapa: l?.etapa ?? null,
          lead_telefono: l?.telefono ?? null, lead_monto_estimado: l?.monto_estimado ?? null,
          lead_moneda: l?.moneda ?? null, lead_vendedor_id: l?.vendedor_id ?? null,
          lead_supervisor_id: l?.asignado_supervisor_id ?? null,
          lead_correo: l?.correo ?? null, lead_no_contactar: l?.no_contactar ?? false,
          lead_telefono_alternativo: l?.telefono_alternativo ?? null,
        }
      })
      return json(route, { version: 1, items })
    }
    if (p === '/rest/v1/tareas') {
      if (method === 'GET') return json(route, estado.tareas)
      if (method === 'POST') {
        const fila = (req.postDataJSON() ?? {}) as Record<string, unknown>
        estado.tareas = [
          ...estado.tareas,
          { id: `t-${estado.tareas.length + 1}`, estado: 'pendiente', activo: true, ...fila },
        ]
        return json(route, [], 201)
      }
      if (method === 'PATCH') {
        const idFiltro = (url.searchParams.get('id') ?? '').replace(/^eq\./, '')
        const cambios = (req.postDataJSON() ?? {}) as Record<string, unknown>
        estado.tareas = estado.tareas.map((t) => (t.id === idFiltro ? { ...t, ...cambios } : t))
        return json(route, [{ id: idFiltro }])
      }
    }

    // Comandos SLA con recibo. Este doble ejercita el transporte y la UI;
    // reglas, locks y prórrogas se prueban con PostgreSQL real en el banco SQL.
    const comandoSla = p.match(/^\/rest\/v1\/rpc\/(registrar_actividad|cerrar_tarea|cerrar_reunion|reprogramar_reunion|reprogramar_tarea)_v2$/)?.[1]
      ?? (p === '/rest/v1/rpc/registrar_llamada_v3' ? 'registrar_llamada' : undefined)
    if (comandoSla && method === 'POST') {
      estado.llamadas.rpcSlaComandos.push(comandoSla)
      const args = (req.postDataJSON() ?? {}) as Record<string, unknown>
      const operacion = String(args.p_operacion_id ?? '')
      if (!/^[0-9a-f-]{36}$/i.test(operacion)) return json(route, { code: '22023', message: 'Recibo requerido' }, 400)
      const huella = JSON.stringify({ comandoSla, args })
      const previo = recibosSla.get(operacion)
      if (previo) return previo.huella === huella ? json(route, previo.respuesta)
        : json(route, { code: '23505', message: 'Recibo incompatible' }, 409)
      const tarea = estado.tareas.find((t) => t.id === args.p_tarea_id)
      const leadId = comandoSla === 'registrar_actividad' || comandoSla === 'registrar_llamada' ? args.p_lead_id : tarea?.lead_id
      const lead = estado.leads.find((l) => l.id === leadId)
      if (!lead || (comandoSla !== 'registrar_actividad' && comandoSla !== 'registrar_llamada' && !tarea)) return json(route, { code: 'P0002', message: 'Oportunidad o tarea no disponible' }, 400)
      if (comandoSla === 'registrar_llamada' && args.p_tarea_id && !tarea) return json(route, { code: '22023', message: 'Tarea no encontrada, cerrada o de otro lead' }, 400)
      if (estado.fallarProximoInsertActividad && comandoSla === 'registrar_actividad') {
        estado.fallarProximoInsertActividad = false
        return json(route, { code: '23514', message: 'Actividad rechazada' }, 400)
      }
      const siguiente = args.p_siguiente as Record<string, unknown> | null | undefined
      const guardarSiguiente = () => {
        if (!siguiente) return
        estado.tareas.push({ ...siguiente, lead_id: lead.id, perfil_id: null,
          vendedor_id: lead.vendedor_id, asignado_supervisor_id: lead.asignado_supervisor_id ?? null,
          nota: null, duracion_min: null, resultado_reunion: null, motivo_no_realizada: null, detalle_cierre_reunion: null,
          estado: 'pendiente', activo: true, reprogramaciones: 0, creado_en: new Date().toISOString(),
          creado_por: UID, confirmada_en: null, reagendada_de: null })
      }
      // Gestión Diaria F2: el resultado tipificado (espejo del núcleo
      // private.llamada_registrar): actividad con metadata, cierre de la tarea
      // de llamada, avance automático, descarte con motivo, siguiente.
      let extraRespuesta: Record<string, unknown> = {}
      if (comandoSla === 'registrar_llamada') {
        const resultado = String(args.p_resultado)
        const tipo = ['no_contesto', 'numero_errado', 'no_es_la_persona'].includes(resultado) ? 'llamada_no_contestada' : 'llamada_realizada'
        const descartar = ['no_interesado', 'pide_otro_producto'].includes(resultado) || args.p_descartar === true
        const actividadId = tarea ? crypto.randomUUID() : operacion
        actividadesSla.push({ id: actividadId, lead_id: lead.id, tipo, detalle: args.p_detalle ?? null,
          creado_en: new Date().toISOString(), autor_nombre: 'Gerente Real',
          metadata: { evento: 'resultado_llamada', resultado, submotivo: args.p_submotivo ?? null, intento_n: 1,
            etapa_anterior: lead.etapa, descartado: descartar, no_insista: args.p_no_insista === true, siguiente_id: siguiente?.id ?? null, tarea_id: tarea?.id ?? null } })
        if (tarea) { tarea.estado = 'completada'; tarea.resultado_actividad_id = actividadId }
        if (lead.etapa === 'nuevo' && tipo === 'llamada_realizada') lead.etapa = 'contactado'
        if (descartar) { lead.etapa = 'descartado'; lead.motivo_descarte = resultado === 'pide_otro_producto' ? 'pide_credito' : resultado === 'no_interesado' ? 'sin_interes' : resultado === 'no_contesto' ? 'no_responde' : 'datos_invalidos' }
        else guardarSiguiente()
        extraRespuesta = { actividad_id: actividadId, siguiente_id: descartar ? null : (siguiente?.id ?? null), descartado: descartar,
          no_insista: args.p_no_insista === true, resultado, intento_n: 1, deshecho: false, etapa: lead.etapa, replay: false }
      } else if (comandoSla === 'registrar_actividad') {
        actividadesSla.push({ id: operacion, lead_id: lead.id, tipo: args.p_tipo, detalle: args.p_detalle,
          creado_en: new Date().toISOString(), autor_nombre: 'Gerente Real' })
        if (lead.etapa === 'nuevo' && ['llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'].includes(String(args.p_tipo))) lead.etapa = 'contactado'
        guardarSiguiente()
      } else if (comandoSla === 'reprogramar_reunion') {
        tarea!.estado = 'reprogramada'
        estado.tareas.push({ ...tarea, id: args.p_nueva_id, estado: 'pendiente', vence_en: args.p_vence_en,
          confirmada_en: null, reagendada_de: tarea!.id, reprogramaciones: Number(tarea!.reprogramaciones ?? 0) + 1 })
      } else if (comandoSla === 'reprogramar_tarea') {
        tarea!.vence_en = args.p_vence_en; tarea!.confirmada_en = null
        tarea!.reprogramaciones = Number(tarea!.reprogramaciones ?? 0) + 1
      } else {
        tarea!.estado = args.p_estado
        guardarSiguiente()
      }
      const respuesta = { version: 2, ok: true, operacion_id: operacion, lead_id: lead.id, comando: comandoSla, ...extraRespuesta }
      recibosSla.set(operacion, { huella, respuesta })
      if (estado.perderProximaRespuestaSla) {
        estado.perderProximaRespuestaSla = false
        return route.abort('failed')
      }
      return json(route, respuesta)
    }

    // Gestión Diaria F2: deshacer los EFECTOS de un resultado de llamada.
    if (p === '/rest/v1/rpc/deshacer_resultado_llamada' && method === 'POST') {
      const args = (req.postDataJSON() ?? {}) as Record<string, unknown>
      const act = actividadesSla.find((a) => a.id === args.p_actividad_id) as (Record<string, unknown> & { metadata?: Record<string, unknown> }) | undefined
      if (!act || act.metadata?.evento !== 'resultado_llamada') return json(route, { code: 'P0002', message: 'Resultado no encontrado o no es tuyo' }, 400)
      if (act.metadata.deshecho_en) return json(route, { code: '22023', message: 'Este resultado ya se deshizo' }, 400)
      const lead = estado.leads.find((l) => l.id === act.lead_id)!
      const sig = estado.tareas.find((t) => t.id === act.metadata?.siguiente_id && t.estado === 'pendiente')
      if (sig) sig.estado = 'cancelada'
      const revierte = act.metadata.descartado === true && lead.etapa === 'descartado'
      if (revierte) { lead.etapa = act.metadata.etapa_anterior === 'nuevo' ? 'nuevo' : 'contactado'; lead.motivo_descarte = null }
      act.metadata = { ...act.metadata, deshecho_en: new Date().toISOString() }
      return json(route, { ok: true, actividad_id: act.id, lead_id: lead.id, tarea_cancelada: Boolean(sig), descarte_revertido: revierte, cita_no_restaurada: false, ciclo_nuevo: revierte, etapa: lead.etapa })
    }

    // ── RPC cerrar_tarea (cierre atómico: resultado al log + tarea siguiente) ──
    if (p === '/rest/v1/rpc/cerrar_tarea' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_tarea_id?: string }
      estado.tareas = estado.tareas.filter((t) => t.id !== body.p_tarea_id)
      return json(route, { siguiente_id: null })
    }

    // ── metas versionadas + cumplimiento confirmado (boot del store) ──
    if (p === '/rest/v1/rpc/configuracion_metas_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_periodo?: string }
      const periodo = body.p_periodo ?? String(estado.configuracionMetas.periodo)
      const mismaFoto = periodo === estado.configuracionMetas.periodo
      return json(route, {
        ...estado.configuracionMetas,
        periodo,
        vendedores: mismaFoto ? estado.configuracionMetas.vendedores : [],
      })
    }
    if (p === '/rest/v1/rpc/cierre_mes_estado_fn' && method === 'POST') {
      // Reloj coherente con el clock de los specs mensuales (02/09): agosto
      // sigue en ventana de ajuste y julio es la última foto ya sellada.
      return json(route, {
        version: 1,
        generado_en: '2026-09-02T15:00:00.000Z',
        hoy: '2026-09-02',
        zona: 'America/Lima',
        mes_en_curso: { mes: '2026-09', mes_nombre: 'setiembre', cierra_el: '2026-10-10' },
        pendiente: {
          mes: '2026-08',
          mes_nombre: 'agosto',
          cierra_el: '2026-09-10',
          dias_para_cierre: 8,
          estado: 'en_ventana',
        },
        ultimo_cerrado: {
          mes: '2026-07',
          mes_nombre: 'julio',
          cerrado_en: '2026-08-10T14:20:00.000Z',
          automatico: true,
        },
      })
    }
    if (p === '/rest/v1/rpc/cumplimiento_metas_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_periodo?: string }
      const periodo = body.p_periodo ?? String(estado.cumplimientoMetas.periodo)
      const mes = periodo.slice(0, 7)
      const mismaFoto = periodo === estado.cumplimientoMetas.periodo
      return json(route, {
        ...estado.cumplimientoMetas,
        periodo,
        vendedores: mismaFoto ? estado.cumplimientoMetas.vendedores : [],
        cierre: mes <= '2026-07'
          ? { cerrado: true, cerrado_en: '2026-08-10T14:20:00.000Z', automatico: true }
          : { cerrado: false },
      })
    }
    // Las suites históricas conservan el modo legado. El spec SLA activo
    // sobrescribe estas rutas con una política y una cola v2 completas.
    if (p === '/rest/v1/rpc/avisos_sla_resumen_v2_fn') {
      return json(route, { version: 2, modo: 'legado', control_revision: 0, calculado_en: new Date().toISOString(),
        total_oportunidades: 0, total_avisos: 0, criticas: 0, grupos: [] })
    }
    if (p === '/rest/v1/rpc/estado_sla_leads_v2_fn') {
      return json(route, { version: 2, modo: 'legado', control_revision: 0,
        calculado_en: new Date().toISOString(), filas: [] })
    }
    if (p === '/rest/v1/rpc/configuracion_sla_v2_fn') {
      return json(route, { version: 2, puede_editar: estado.rolCrm === 'gerencia', expected_version: 1,
        vigente: { base: { version: 1 }, operacion: null },
        ultima_publicada: { base: { version: 1 }, operacion: null },
        control: { modo: 'legado', revision: 0, primera_activacion_en: null, politica_adopcion_id: null } })
    }
    if (p === '/rest/v1/rpc/estado_sla_leads_fn') {
      return json(route, [])
    }
    if (p === '/rest/v1/alertas_reconocimientos_vigentes' && method === 'GET') {
      return json(route, [])
    }
    if (p === '/rest/v1/rpc/cierres_externos_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_periodo?: string }
      return json(route, {
        version: 1,
        periodo: String(body.p_periodo ?? '2026-09-01'),
        alcance: estado.rolCrm === 'vendedor'
          ? 'propio'
          : estado.rolCrm === 'supervisor'
            ? 'equipo'
            : 'global',
        cierres: [],
        cierres_total: 0,
        cierres_mes: [],
        cierres_mes_total: 0,
        totales: [],
        por_empresa: [],
      })
    }

    // ── estado del cierre y anulación de gerencia (Avance) ──────────────────
    if (p === '/rest/v1/rpc/postventa_agenda_fn') return json(route, [])
    if (p === '/rest/v1/rpc/postventa_estado_fn') return json(route, {version: 1, habilitada: false})
    if (p === '/rest/v1/rpc/postventa_perfil_fn') return json(route, {habilitada: false, inversionista_id: null})
    if (p === '/rest/v1/rpc/cartera_inversionistas_estado_fn') return json(route, {version: 1, habilitada: false, escritura_habilitada: false, motivo: null})
    if (p === '/rest/v1/rpc/cierres_estado_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_lead_ids?: string[] }
      const pedidos = new Set(body.p_lead_ids ?? [])
      // Se filtra por los ids PEDIDOS igual que el servidor: si el stub
      // devolviera todo, la pantalla parecería funcionar aunque preguntara mal.
      return json(route, estado.cierresEstado.filter((f) => pedidos.has(f.lead_id)))
    }
    if (p === '/rest/v1/rpc/anular_cierre_avance' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_lead_id?: string; p_motivo?: string }
      const leadId = body.p_lead_id ?? ''
      estado.anulacionesAvance.push({ lead_id: leadId, motivo: body.p_motivo ?? '' })
      // El servidor deja el cierre anulado, así que la RELECTURA tiene que
      // reflejarlo. Sin esto el e2e bendeciría un optimismo del front que
      // producción no tiene: el chip aparecería aunque el servidor no guardara.
      estado.cierresEstado = [
        ...estado.cierresEstado.filter((f) => f.lead_id !== leadId),
        {
          lead_id: leadId,
          canal: 'avance',
          anulado_en: '2026-08-14T15:00:00.000Z',
          motivo: body.p_motivo ?? '',
        },
      ]
      return json(route, {
        ok: true,
        lead_id: leadId,
        contratos_afectados: [],
        afecta_cuota: false,
      })
    }

    // ── suscripción ICS (solo se toca si el test abre el diálogo del calendario) ──
    if (p === '/rest/v1/agenda_ics') {
      // maybeSingle sin fila: PostgREST responde 406/PGRST116 y supabase-js lo
      // traduce a data null sin error — el "aún no conectaste tu calendario".
      if (method === 'GET') return json(route, { code: 'PGRST116', message: '0 rows', details: null, hint: null }, 406)
      if (method === 'POST') return json(route, { token: 'tok-e2e' })
      if (method === 'PATCH') return json(route, { token: 'tok-e2e-rotado' })
    }

    // ── edges nuevas: tipo de cambio (meta del analista) y conversión de lead ──
    if (p === '/functions/v1/crm-tipo-cambio') {
      const body = req.postData()
        ? (req.postDataJSON() as { fecha_corte?: string })
        : {}
      return json(route, {
        promedio: 3.53,
        fuente: 'SBS · prom. 7d',
        ...(body.fecha_corte ? { fecha_corte: body.fecha_corte } : {}),
      })
    }
    if (p === '/functions/v1/crm-convertir-lead' && method === 'POST') {
      return json(route, {
        ok: true,
        perfil_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        ya_existia: false,
        domicilio_accion: 'completado',
        email_enviado: true,
      })
    }

    // ── métricas del ámbito operativo (F1: tiles, cola y ranking) ──
    if (p === '/rest/v1/rpc/resumen_cartera_fn' && method === 'POST') {
      if (estado.fallarResumenCartera) {
        return json(route, { message: 'resumen caido', code: 'PGRST000', details: null, hint: null }, 500)
      }
      return json(route, resumenCarteraReal(estado.leads))
    }
    // F2: la TABLA de Cartera. Va con las métricas del ámbito porque comparte
    // su ciclo de invalidación (una mutación refresca tiles Y filas).
    if (p === '/rest/v1/rpc/cartera_pagina_fn' && method === 'POST') {
      estado.llamadas.rpcCarteraPagina += 1
      if (estado.fallarCarteraPagina) {
        return json(route, { message: 'cartera caida', code: 'PGRST000', details: null, hint: null }, 500)
      }
      const body = (req.postDataJSON() ?? {}) as Parameters<typeof carteraPaginaReal>[1]
      return json(route, carteraPaginaReal(estado.leads, body))
    }
    if (p === '/rest/v1/rpc/cartera_filtrada_fn' && method === 'POST') {
      estado.llamadas.rpcCarteraPagina += 1
      if (estado.fallarCarteraPagina) {
        return json(route, { message: 'cartera caida', code: 'PGRST000', details: null, hint: null }, 500)
      }
      const body = (req.postDataJSON() ?? {}) as Parameters<typeof carteraPaginaReal>[1]
      const todos = carteraPaginaReal(estado.leads, { ...body, p_antes_de: null, p_antes_id: null, p_limite: estado.leads.length + 1 })
      const ids = new Set(todos.map((l) => l.id))
      const resumen = resumenCarteraReal(estado.leads.filter((l) => ids.has(l.id)))
      return json(route, { version: 1, generado_en: new Date().toISOString(),
        desde: body.p_desde ?? null, hasta: body.p_hasta ?? null, origen: body.p_origen ?? null, resumen,
        items: carteraPaginaReal(estado.leads, body).map((l) => ({ ...l,
          recibido_en: body.p_desde ? l.creado_en : null, recepcion_aproximada: false })),
      })
    }
    if (p === '/rest/v1/rpc/cola_accion_fn' && method === 'POST') {
      if (estado.fallarColaAccion) {
        return json(route, { message: 'cola caida', code: 'PGRST000', details: null, hint: null }, 500)
      }
      const body = (req.postDataJSON() ?? {}) as { p_limite?: number }
      return json(route, colaAccionReal(estado.leads, Number(body.p_limite ?? 100)))
    }
    if (p === '/rest/v1/rpc/metricas_vendedores_fn' && method === 'POST') {
      if (estado.fallarMetricasEquipo) {
        return json(route, { message: 'metricas caidas', code: 'PGRST000', details: null, hint: null }, 500)
      }
      return json(route, metricasVendedoresReal(estado.leads))
    }
    if (p === '/rest/v1/rpc/resumen_reparto_fn' && method === 'POST') {
      estado.llamadas.rpcResumenReparto += 1
      if (estado.fallarResumenReparto) {
        return json(route, { message: 'resumen de reparto caido', code: 'PGRST000', details: null, hint: null }, 500)
      }
      return json(route, estado.resumenRepartoOverride ?? resumenRepartoReal(estado.colaReparto))
    }

    // ── métricas de gerencia (gráficas del panel Hoy) ──
    if (p === '/rest/v1/rpc/metricas_conversiones_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string; p_hasta?: string; p_origen?: string }
      const desde = String(body.p_desde ?? '')
      const hasta = String(body.p_hasta ?? '')
      return json(route, metricasParaPeriodo(
        estado.metricas.conversiones,
        desde,
        hasta,
        body.p_origen ?? null,
      ))
    }
    if (p === '/rest/v1/rpc/conversion_mensual_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_periodo?: string }
      // El contrato del front ECO-verifica el mes pedido: el mock lo devuelve tal cual.
      const mes = String(body.p_periodo ?? '2026-08-01').slice(0, 7)
      const [anioTxt = '2026', mesTxt = '08'] = mes.split('-')
      const inicioMesSiguiente = new Date(Date.UTC(Number(anioTxt), Number(mesTxt), 1))
      const mesSiguiente = `${inicioMesSiguiente.getUTCFullYear()}-${String(inicioMesSiguiente.getUTCMonth() + 1).padStart(2, '0')}`
      const nombresMes = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre']
      const alcance = estado.rolCrm === 'vendedor' ? 'propio' : estado.rolCrm === 'supervisor' ? 'equipo' : 'global'
      const procedencia = estado.metricas.conversionMensual.responsables[0]?.procedencia
      const mesFuente = Array.isArray(procedencia)
        ? String((procedencia[0] as Record<string, unknown> | undefined)?.mes ?? '')
        : ''
      const foto = mesFuente === '' || mesFuente === mes
        ? estado.metricas.conversionMensual
        : conversionMensualVaciaReal()
      return json(route, {
        version: 1,
        generado_en: '2026-09-02T15:00:00.000Z',
        alcance,
        periodo: {
          mes,
          mes_nombre: nombresMes[Number(mesTxt) - 1] ?? 'agosto',
          anio: Number(anioTxt),
          zona: 'America/Lima',
          desde: `${mes}-01T05:00:00+00:00`,
          hasta: `${mesSiguiente}-01T05:00:00+00:00`,
        },
        ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
        fuentes: {
          divisor: 'crm.lead_asignaciones.asignado_en',
          numerador: 'crm.lead_asignaciones.resultado_en',
          referido: 'crm.lead_asignaciones.origen',
        },
        cobertura: {
          medible: true,
          suelo_historico: null,
          motivo_no_medible: null,
          divisor_aproximado: 0,
          divisor_por_motivo: Number(foto.total.divisor ?? 0) > 0
            ? { ingreso: Number(foto.total.divisor) }
            : {},
          cierres_sin_episodio: 0,
          fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 },
        },
        cierre: mes <= '2026-07'
          ? { cerrado: true, cerrado_en: '2026-08-10T14:20:00.000Z', automatico: true }
          : { cerrado: false },
        cartera: foto.cartera,
        total: foto.total,
        responsables: foto.responsables,
      })
    }
    if (p === '/rest/v1/rpc/metricas_conversiones_equipo_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string; p_hasta?: string }
      const desde = String(body.p_desde ?? '')
      const hasta = String(body.p_hasta ?? '')
      const procedencia = estado.metricas.conversionMensual.responsables[0]?.procedencia
      const mesFuente = Array.isArray(procedencia)
        ? String((procedencia[0] as Record<string, unknown> | undefined)?.mes ?? '')
        : ''
      const cosecha = mesFuente === '' || mesFuente === desde.slice(0, 7)
        ? estado.metricas.cosecha
        : []
      const paridadFilas = cosecha.length
      return json(route, {
        version: 1,
        generado_en: '2026-09-02T15:00:00.000Z',
        alcance: estado.rolCrm === 'supervisor' ? 'equipo' : 'global',
        periodo: { desde, hasta },
        responsables: cosecha,
        nucleo: {
          base: 'asignacion',
          incluye_cartera: true,
          peso_referido: 0.15,
          mes_peso: `${desde.slice(0, 7)}-01`,
        },
        sondas: {
          cuadra: paridadFilas > 0 ? true : null,
          paridad_nucleo: 0,
          paridad_filas: paridadFilas,
          divisor_fuera_del_roster: 0,
          numerador_fuera_del_roster: 0,
          cierres_anulados: 0,
          clientes_acreditados_a_otro_dueno: 0,
        },
      })
    }
    if (p === '/rest/v1/rpc/metricas_reuniones_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string; p_hasta?: string }
      const desde = String(body.p_desde ?? '')
      const hasta = String(body.p_hasta ?? '')
      return json(route, metricasParaPeriodo(estado.metricas.reuniones, desde, hasta))
    }
    if (p === '/rest/v1/rpc/metricas_capital_mes_fn') return json(route, estado.metricas.capital)
    if (p === '/rest/v1/rpc/metricas_pagos_mes_fn') return json(route, estado.metricas.pagos)
    if (p === '/rest/v1/rpc/altas_nuevas_por_analista_fn') return json(route, estado.metricas.altas)
    if (p === '/rest/v1/rpc/metricas_vencimientos_fn') return json(route, estado.metricas.vencimientos)
    if (p === '/rest/v1/rpc/metricas_agenda_fn' && method === 'POST') {
      const body = (req.postDataJSON() ?? {}) as { p_desde?: string; p_hasta?: string }
      const desde = String(body.p_desde ?? '')
      const hasta = String(body.p_hasta ?? '')
      const dias = Math.max(
        1,
        Math.round((Date.parse(`${hasta}T00:00:00Z`) - Date.parse(`${desde}T00:00:00Z`)) / 86_400_000) + 1,
      )
      return json(route, {
        version: 1,
        generado_en: '2026-07-17T17:00:00.000Z',
        periodo: { desde, hasta, dias, zona: 'America/Lima' },
        vendedores: estado.metricas.agenda,
      })
    }
    if (p === '/rest/v1/rpc/metricas_distribucion_leads_v3_fn' && method === 'POST') {
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
    if (p === '/rest/v1/rpc/editar_lead_fn' && method === 'POST') {
      estado.llamadas.rpcEditarLead += 1
      if (estado.fallarProximaEdicionTelefono) {
        estado.fallarProximaEdicionTelefono = false
        return json(route, { code: '23505', message: 'duplicate key', details: 'uq_leads_telefono_vivo' }, 400)
      }
      const body = (req.postDataJSON() ?? {}) as { p_lead_id?: string; p_cambios?: Partial<LeadReal> }
      if (!body.p_lead_id || !body.p_cambios) {
        return json(route, { code: '22023', message: 'Faltan datos de la edición' }, 400)
      }
      if (!estado.leads.some((lead) => lead.id === body.p_lead_id)) {
        return json(route, { code: 'P0002', message: 'Lead no encontrado' }, 400)
      }
      estado.leads = estado.leads.map((lead) => lead.id === body.p_lead_id ? { ...lead, ...body.p_cambios } : lead)
      return json(route, null)
    }
    if (p === '/rest/v1/leads') {
      if (method === 'GET') {
        estado.llamadas.getLeads += 1
        if (estado.leadsSiempreCaido) return json(route, { message: 'server down' }, 500)
        if (estado.fallarProximaCargaLeads) {
          estado.fallarProximaCargaLeads = false
          return json(route, { message: 'server down' }, 500)
        }
        const idPedido = url.searchParams.get('id')
        if (idPedido?.startsWith('eq.')) {
          return json(route, estado.leads.filter((lead) => lead.id === idPedido.slice(3)
            && (url.searchParams.get('activo') !== 'eq.true' || lead.activo)))
        }
        // `fueraDelBoot`: simula un lead que la FOTO inicial no trae (tope de
        // MAX_LEADS_AMBITO) pero que su lectura por id sí sirve (RLS lo ve).
        return json(route, estado.leads.filter((lead) => !lead.fueraDelBoot))
      }
      if (method === 'POST') {
        estado.llamadas.insertLeadDirecto += 1
        return json(route, { message: 'El alta directa de leads es una vía legacy' }, 500)
      }
      if (method === 'PATCH') {
        estado.llamadas.patchLead += 1
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

/** Inicia sesión REAL vía el formulario (supabase-js guarda la sesión solo).
 * `esperarWorkspace: false` para los escenarios en los que la carga inicial cae
 * A PROPÓSITO: ahí el CRM pinta su pantalla de error en vez del workspace, así
 * que esperar el menú lateral sería esperar algo que no debe existir. */
export async function loginReal(
  page: Page,
  { esperarWorkspace = true }: { esperarWorkspace?: boolean } = {},
): Promise<void> {
  // Mismo motivo que en entrarDemo: animaciones instantáneas o los asserts
  // de tiles/paneles pillan estados de tránsito bajo carga.
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/')
  await page.locator('#correo').fill('qa-real@avancecorp.pe')
  await page.locator('#clave').fill('cualquier-cosa')
  await page.getByRole('button', { name: /^Entrar$/ }).click()
  if (!esperarWorkspace) return
  await expect(page.getByRole('button', { name: 'Ocultar menú' })).toBeVisible({ timeout: 10_000 })
}

/** Transporte de la ruta compartida para las suites de UI sin backend.
 * SQL, Auth y Storage reales se cubren en e2e-integration y en el banco HTTP. */
export async function montarConversionCompartida(page:Page) {
  const persona='11111111-1111-4111-8111-111111111111'
  let nombre='PERSONA SINTÉTICA',leadId:string|null=null,perfil:string|null=null
  let solicitud:Record<string,unknown>|null=null
  await page.route('**/rest/v1/rpc/*',async route=>{
    const fn=new URL(route.request().url()).pathname.split('/').at(-1),b=route.request().postDataJSON()
    if(fn==='preparar_persona_lead_inversion_fn'){
      nombre=b.p_nombre;leadId=b.p_lead
      return route.fulfill({json:{inversionista_id:persona,lead_id:leadId,solicitud_id:solicitud?.solicitud_id??null}})
    }
    if(fn==='contexto_conversion_inversion_fn')return route.fulfill({json:{solicitud_id:solicitud?.solicitud_id??null,documento_tipo:'DNI',persona:{inversionista_id:persona,perfil_id:perfil,
      nombre,correo:'persona@pruebas.example',telefono:'999888777',responsable_id:UID,responsable_nombre:'ANALISTA DEL LEAD'},
      capacidades:{nueva_inversion:true,motivo_no_operable:null}}})
    if(fn==='preparar_inversion_fn'){
      solicitud={solicitud_id:b.p_clave,lead_id:leadId,estado:'preparada',inversion_id:null,inversionista_id:persona,
        inversionista_origen_id:persona,identidad_fusionada:false,responsable_esperado_id:UID,responsable_actual_id:UID,
        requiere_revision_responsable:false,revision_datos:0,revision_responsable:0,hash_datos:'prueba',
        necesita_portal:!perfil,comprobante_bucket:null,comprobante_ruta:null,resultado:null,datos:b.p_datos}
      return route.fulfill({json:solicitud})
    }
    if(fn==='solicitud_inversion_fn')return route.fulfill({json:solicitud})
    return route.fallback()
  })
  await page.route('**/functions/v1/crm-inversion-portal',route=>{
    perfil='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    solicitud={...solicitud,necesita_portal:false}
    return route.fulfill({json:{ok:true,solicitud_id:solicitud.solicitud_id,perfil_id:perfil,reintento:false}})
  })
}

/** Abre Avance dentro de Nueva inversión después de confirmar la identidad. */
export async function abrirConversionAvance(page: Page, drawer: Locator): Promise<Locator> {
  await montarConversionCompartida(page)
  await drawer.getByRole('button', { name: /Convertir a cliente/i }).click()
  const documento=page.getByLabel('Documento',{exact:true})
  if(!await documento.inputValue())await documento.fill('93334444')
  await page.getByRole('button',{name:'Continuar a Nueva inversión'}).click()
  await page.getByRole('button',{name:'Avance',exact:true}).click()
  const dialogo = page.getByRole('dialog', { name: 'Acceso Avance' })
  await expect(dialogo).toBeVisible()
  return dialogo
}
