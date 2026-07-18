import * as v from 'valibot'
import { sb, type ClienteCrm } from '@/lib/supabase'
import type { Database } from '@/lib/database.types'
import { idCorrelacion, registrarError } from '@/lib/observabilidad'
import {
  CATEGORIAS_INTERES,
  ETAPAS,
  GENEROS,
  MOTIVOS_DESCARTE,
  ORIGENES_TODOS,
  TERMINALES,
  TIPOS_ACTIVIDAD,
  type Actividad,
  type Etapa,
  type Lead,
  type Miembro,
  type TipoActividad,
} from '@/lib/tipos'
import type {
  CategoriaContrato,
  CuotaCronograma,
  ModalidadContrato,
  TipoInteres,
} from '@/lib/cronograma'
import {
  ESTADOS_CONTRATO,
  ESTADOS_CUOTA,
  type ClienteBasico,
  type ClienteDetalle,
  type ContratoRow,
  type Cuota,
  type Titular,
  type TitularInput,
} from '@/lib/clientes-tipos'
import { TIPOS_DOCUMENTO_K } from '@/lib/documento'
import type {
  FilaAltasAnalista,
  FilaCapitalMes,
  FilaPagosMes,
  FilaVencimientos,
} from '@/lib/metricas'
import {
  MetricasDistribucionLeadsSchema,
  type MetricasDistribucionLeads,
} from '@/lib/metricas-distribucion'

export const TAMANO_PAGINA_LEADS = 50
const MAX_TAMANO_PAGINA = 100
const MAX_BUSQUEDA = 80

const COLUMNAS_LEAD = [
  'id',
  'nombre_completo',
  'telefono',
  'correo',
  'dni',
  'genero',
  'fecha_nacimiento',
  'distrito',
  'origen',
  'etapa',
  'motivo_descarte',
  'monto_estimado',
  'moneda',
  'categoria_interes',
  'vendedor_id',
  'asignado_supervisor_id',
  'creado_en',
  'actualizado_en',
  'activo',
  'nota',
].join(',')

// Validación en runtime del borde con Supabase (los unions de TS se borran al
// compilar: un dato viejo o una migración a medias entrarían "compilando
// limpio"). Los picklist salen de los MISMOS catálogos de tipos.ts — una sola
// fuente de verdad para el CHECK, el union y el parser.
const MontoEstimadoSchema = v.pipe(
  v.union([v.number(), v.string()]),
  v.check((valor) => Number.isFinite(Number(valor)) && Number(valor) > 0),
)

const LeadRowSchema = v.object({
  id: v.string(),
  nombre_completo: v.string(),
  telefono: v.string(),
  correo: v.nullable(v.string()),
  dni: v.nullable(v.string()),
  // Mismo catálogo que el CHECK leads_genero_valido y el union Genero.
  // OPCIONALES a propósito (no solo nullable): si el frontend llegara a correr
  // contra una base sin la migración, el lead debe seguir mostrándose sin
  // silueta — jamás desaparecer de la cartera por un campo cosmético.
  genero: v.optional(v.nullable(v.picklist(GENEROS.map((g) => g.k)))),
  fecha_nacimiento: v.optional(v.nullable(v.string())),
  distrito: v.nullable(v.string()),
  origen: v.picklist(ORIGENES_TODOS.map((o) => o.k)),
  etapa: v.picklist([...ETAPAS.map((e) => e.k), ...TERMINALES.map((t) => t.k)]),
  motivo_descarte: v.nullable(v.picklist(MOTIVOS_DESCARTE.map((m) => m.k))),
  // numeric con CHECK de rango/2 decimales: PostgREST puede serializarlo como string
  monto_estimado: MontoEstimadoSchema,
  moneda: v.picklist(['PEN', 'USD']),
  categoria_interes: v.nullable(v.picklist(CATEGORIAS_INTERES.map((c) => c.k))),
  vendedor_id: v.nullable(v.string()),
  asignado_supervisor_id: v.nullable(v.string()),
  creado_en: v.string(),
  actualizado_en: v.string(),
  activo: v.boolean(),
  nota: v.nullable(v.string()),
})

type LeadRow = v.InferOutput<typeof LeadRowSchema>

export interface FiltrosLeads {
  pagina: number
  tamano?: number
  texto?: string
  etapa?: Etapa | 'todas'
  vendedorId?: string | 'todos' | 'sin_asignar'
  incluirInactivos?: boolean
}

export interface Pagina<T> {
  items: T[]
  pagina: number
  tamano: number
  total: number
  paginas: number
}

export class CrmApiError extends Error {
  readonly code: string
  readonly correlationId: string

  constructor(message: string, code = 'CRM_API_ERROR', correlationId = idCorrelacion()) {
    super(message)
    this.name = 'CrmApiError'
    this.code = code
    this.correlationId = correlationId
  }
}

/**
 * Mensaje MOSTRABLE de un fallo de esta capa: los CrmApiError ya traen su texto
 * es-PE (este módulo los traduce con código estable); cualquier otra cosa
 * (TypeError de red, bug) cae al texto por defecto de la pantalla — jamás un
 * `message` crudo en inglés frente al usuario. La variante del store
 * (`persistir`) sigue LOCAL a propósito: además excluye POSTGREST_ERROR porque
 * su mensaje genérico es de lectura y no sirve como feedback de una mutación.
 */
export function mensajeDeError(e: unknown, porDefecto: string): string {
  return e instanceof CrmApiError ? e.message : porDefecto
}

function cliente(): ClienteCrm {
  if (!sb) {
    const error = new CrmApiError('Supabase no está configurado.', 'SUPABASE_NOT_CONFIGURED')
    registrarError('crm.cliente_no_disponible', error)
    throw error
  }
  return sb
}

function enteroSeguro(valor: number, minimo: number, maximo: number): number {
  if (!Number.isFinite(valor)) return minimo
  return Math.min(maximo, Math.max(minimo, Math.trunc(valor)))
}

/**
 * PostgREST `.or()` recibe una mini-sintaxis, no parámetros independientes.
 * Usamos una allowlist pequeña (letras, números, espacios y guiones) para que
 * el texto del usuario solo pueda ser un patrón ILIKE, nunca parte de la
 * expresión lógica. Los dígitos se conservan aparte para teléfono/DNI.
 */
export function normalizarBusquedaPostgrest(valor: string | undefined): {
  texto: string
  digitos: string
} {
  const crudo = (valor ?? '').normalize('NFKC').trim().slice(0, MAX_BUSQUEDA)
  const texto = crudo
    .replace(/[^\p{L}\p{N}\s-]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const digitos = crudo.replace(/\D/g, '').slice(0, 15)
  return { texto, digitos }
}

function aNumero(valor: number | string | null): number | null {
  if (valor == null) return null
  const n = typeof valor === 'number' ? valor : Number(valor)
  return Number.isFinite(n) ? n : null
}

function aLead(fila: LeadRow): Lead {
  return {
    id: fila.id,
    nombre_completo: fila.nombre_completo,
    telefono: fila.telefono,
    correo: fila.correo,
    dni: fila.dni,
    genero: fila.genero ?? null,
    fecha_nacimiento: fila.fecha_nacimiento ?? null,
    distrito: fila.distrito,
    origen: fila.origen, // ya validado contra el catálogo por LeadRowSchema
    etapa: fila.etapa,
    motivo_descarte: fila.motivo_descarte,
    monto_estimado: Number(fila.monto_estimado),
    moneda: fila.moneda,
    categoria_interes: fila.categoria_interes,
    vendedor_id: fila.vendedor_id,
    asignado_supervisor_id: fila.asignado_supervisor_id,
    creado_en: fila.creado_en,
    activo: fila.activo,
    nota: fila.nota,
  }
}

/**
 * RESERVA paginada server-side — hoy sin consumidores en la app (los leads se
 * cargan de una vez vía listarLeadsDelAmbito). Reactivar cuando el volumen
 * supere MAX_LEADS_AMBITO=2000: RLS decide el ámbito y el navegador jamás
 * descarga la cartera global para recortarla después. Sus tests MSW
 * (crm-api-msw.test.ts) la mantienen honesta mientras espera.
 */
export async function listarLeads(
  filtros: FiltrosLeads,
  signal?: AbortSignal,
): Promise<Pagina<Lead>> {
  const pagina = enteroSeguro(filtros.pagina, 0, Number.MAX_SAFE_INTEGER)
  const tamano = enteroSeguro(filtros.tamano ?? TAMANO_PAGINA_LEADS, 1, MAX_TAMANO_PAGINA)
  const desde = pagina * tamano
  const hasta = desde + tamano - 1

  let consulta = cliente()
    .schema('crm')
    .from('leads')
    .select(COLUMNAS_LEAD, { count: 'exact' })
    .order('actualizado_en', { ascending: false })
    .order('id', { ascending: true })
    .range(desde, hasta)

  if (!filtros.incluirInactivos) consulta = consulta.eq('activo', true)
  if (filtros.etapa && filtros.etapa !== 'todas') consulta = consulta.eq('etapa', filtros.etapa)

  if (filtros.vendedorId === 'sin_asignar') {
    consulta = consulta.is('vendedor_id', null)
  } else if (filtros.vendedorId && filtros.vendedorId !== 'todos') {
    consulta = consulta.eq('vendedor_id', filtros.vendedorId)
  }

  const busqueda = normalizarBusquedaPostgrest(filtros.texto)
  if (busqueda.texto.length >= 2) {
    const ramas = [`nombre_completo.ilike.%${busqueda.texto}%`]
    if (busqueda.digitos.length >= 3) {
      ramas.push(`telefono.ilike.%${busqueda.digitos}%`, `dni.ilike.%${busqueda.digitos}%`)
    }
    consulta = consulta.or(ramas.join(','))
  }

  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error, count } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la cartera.', error.code || 'POSTGREST_ERROR')
    // No se registra el texto ni IDs del filtro: pueden contener PII.
    registrarError('crm.leads.listado_fallido', fallo, {
      pagina,
      tamano,
      etapa: filtros.etapa ?? 'todas',
      incluyeInactivos: filtros.incluirInactivos === true,
      filtraVendedor: Boolean(filtros.vendedorId && filtros.vendedorId !== 'todos'),
      tieneBusqueda: busqueda.texto.length >= 2,
    })
    throw fallo
  }

  // Frontera validada en runtime: una fila que no cumple el contrato (dato
  // viejo, migración a medias) se REGISTRA y se descarta — nunca un cast ciego
  // que reviente la UI río abajo con un union imposible.
  const items: Lead[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const resultado = v.safeParse(LeadRowSchema, cruda)
    if (resultado.success) {
      items.push(aLead(resultado.output))
    } else {
      descartadas += 1
    }
  }
  if (descartadas > 0) {
    registrarError('crm.leads.filas_invalidas', new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'), {
      descartadas,
      pagina,
    })
  }

  const total = count ?? 0
  return {
    items,
    pagina,
    tamano,
    total,
    paginas: Math.ceil(total / tamano),
  }
}

// ── Ámbito completo para el store (lectura NO paginada) ───────────────────────
// El store necesita TODA la cartera del ámbito para los cálculos agregados
// (métricas, embudo, colas). La RLS ya recorta a lo visible; el tope alto es una
// salvaguarda de payload, no seguridad. Con volumen bajo (piloto) sobra.
const MAX_LEADS_AMBITO = 2000

export async function listarLeadsDelAmbito(signal?: AbortSignal): Promise<Lead[]> {
  let consulta = cliente()
    .schema('crm')
    .from('leads')
    .select(COLUMNAS_LEAD)
    .order('actualizado_en', { ascending: false })
    .order('id', { ascending: true })
    .limit(MAX_LEADS_AMBITO)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la cartera.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.leads.ambito_fallido', fallo)
    throw fallo
  }
  const items: Lead[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(LeadRowSchema, cruda)
    if (r.success) items.push(aLead(r.output))
    else descartadas += 1
  }
  if (descartadas > 0) {
    registrarError(
      'crm.leads.ambito_filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas, limite: MAX_LEADS_AMBITO },
    )
  }
  return items
}

// ── Roster del equipo con NOMBRES (RPC SECURITY DEFINER equipo_visible_fn) ─────
const ROLES_EQUIPO = ['vendedor', 'supervisor', 'gerencia'] as const
const MiembroRowSchema = v.object({
  perfil_id: v.string(),
  nombre_completo: v.string(),
  rol_crm: v.picklist(ROLES_EQUIPO),
  supervisor_id: v.nullable(v.string()),
  activo: v.boolean(),
})

export async function listarEquipo(signal?: AbortSignal): Promise<Miembro[]> {
  let consulta = cliente().schema('crm').rpc('equipo_visible_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el equipo.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.equipo.listado_fallido', fallo)
    throw fallo
  }
  const items: Miembro[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(MiembroRowSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

// ── Timeline del ámbito con AUTOR (RPC SECURITY DEFINER actividades_del_ambito_fn)
const TIPOS_ACT = Object.keys(TIPOS_ACTIVIDAD) as [TipoActividad, ...TipoActividad[]]
const ActividadRowSchema = v.object({
  id: v.string(),
  lead_id: v.string(),
  tipo: v.picklist(TIPOS_ACT),
  detalle: v.nullable(v.string()),
  autor_nombre: v.string(),
  creado_en: v.string(),
})

export async function listarActividadesDelAmbito(signal?: AbortSignal): Promise<Actividad[]> {
  let consulta = cliente().schema('crm').rpc('actividades_del_ambito_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el historial.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.actividades.listado_fallido', fallo)
    throw fallo
  }
  const items: Actividad[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(ActividadRowSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

// ── Mutaciones reales (insert/update; RLS + triggers del servidor mandan) ─────
type LeadInsert = Database['crm']['Tables']['leads']['Insert']
type LeadUpdate = Database['crm']['Tables']['leads']['Update']
type ActividadInsert = Database['crm']['Tables']['actividades']['Insert']

/**
 * Traduce un error de PostgREST a un CrmApiError con código estable y mensaje
 * es-PE seguro (nunca el texto crudo de Postgres, salvo los RAISE propios).
 */
function aErrorApi(
  error: { code?: string | null; message?: string | null; details?: string | null },
  contexto: string,
): CrmApiError {
  const codigoPg = error.code ?? ''
  const texto = `${error.message ?? ''} ${error.details ?? ''}`
  let code = 'POSTGREST_ERROR'
  let mensaje = 'No se pudo guardar el cambio.'
  if (codigoPg === '23505') {
    // Índices únicos parciales del dedup GLOBAL (uq_leads_*_vivo): el espejo
    // local solo ve el ámbito; el servidor cubre choques con leads ajenos.
    if (texto.includes('uq_leads_telefono_vivo')) {
      code = 'DUP_TELEFONO'
      mensaje = 'Ese teléfono ya pertenece a otro lead abierto de la empresa'
    } else if (texto.includes('uq_leads_dni_vivo')) {
      code = 'DUP_DNI'
      mensaje = 'Ese DNI ya pertenece a otro lead abierto de la empresa'
    } else if (texto.includes('perfiles_dni')) {
      // Índices parciales del portal (perfiles_dni_cliente_key / _staff_key):
      // corregir el documento de un cliente puede chocar con otro cliente.
      code = 'DUP_DNI_CLIENTE'
      mensaje = 'Ese documento ya pertenece a otro cliente del portal'
    } else if (texto.includes('perfiles_correo')) {
      code = 'DUP_CORREO'
      mensaje = 'Ese correo ya está registrado en el portal'
    }
  } else if (
    (codigoPg === '23502' && texto.includes('monto_estimado'))
    || (codigoPg === '23514' && texto.includes('leads_monto_estimado_valido'))
  ) {
    code = 'MONTO_INVALIDO'
    mensaje = 'El capital estimado es obligatorio y debe ser mayor que 0'
  } else if (codigoPg === '42501' || codigoPg === 'PGRST301') {
    code = 'SIN_PERMISO'
    mensaje = 'No tienes permiso para esa acción'
  } else if (codigoPg === 'P0001') {
    // RAISE EXCEPTION de nuestros propios triggers (es-PE, sin PII).
    code = 'REGLA_SERVIDOR'
    if (error.message) mensaje = error.message
  }
  const fallo = new CrmApiError(mensaje, code)
  registrarError(contexto, fallo, { pg: codigoPg })
  return fallo
}

export async function insertarLead(fila: LeadInsert): Promise<void> {
  const { error } = await cliente().schema('crm').from('leads').insert(fila)
  if (error) throw aErrorApi(error, 'crm.leads.insert_fallido')
}

export async function actualizarLead(id: string, cambios: LeadUpdate): Promise<void> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('leads')
    .update(cambios)
    .eq('id', id)
    .select('id')
  if (error) throw aErrorApi(error, 'crm.leads.update_fallido')
  if (!data || data.length === 0) {
    // La RLS ocultó el lead (fuera del ámbito) o no existe: mismo mensaje,
    // sin revelar existencia (igual que el espejo del store).
    throw new CrmApiError('Lead no encontrado', 'NO_ENCONTRADO')
  }
}

export async function insertarActividad(fila: ActividadInsert): Promise<void> {
  const { error } = await cliente().schema('crm').from('actividades').insert(fila)
  if (error) throw aErrorApi(error, 'crm.actividades.insert_fallido')
}

// ── Conversión lead → cliente (edge crm-convertir-lead: crea el cliente en el
//    portal con service_role + correo de bienvenida + enlaza el lead vía la RPC
//    privilegiada crm.convertir_lead). El navegador nunca crea usuarios ni envía
//    correos: eso vive en el edge. Aquí solo se invoca y se traduce el error. ────
export type TipoDocumentoCliente = 'DNI' | 'CE' | 'PASAPORTE'

export interface ConvertirLeadInput {
  lead_id: string
  correo: string
  tipo_documento: TipoDocumentoCliente
  documento: string
  nombre_completo: string
  telefono?: string | null
  apellidos?: string | null
  nombres?: string | null
}

export interface ConvertirLeadResultado {
  perfil_id: string
  ya_existia: boolean
  email_enviado: boolean
}

export async function convertirLead(input: ConvertirLeadInput): Promise<ConvertirLeadResultado> {
  const { data, error } = await cliente().functions.invoke('crm-convertir-lead', { body: input })
  if (error) {
    let mensaje = 'No se pudo convertir el lead.'
    // FunctionsHttpError expone la respuesta del edge en `context`: extraemos
    // nuestro { error } es-PE (mensaje seguro que arma el propio edge).
    try {
      const ctx = (error as { context?: Response }).context
      if (ctx && typeof ctx.json === 'function') {
        const cuerpo = await ctx.json()
        if (cuerpo?.error) mensaje = traducirErrorAlta(String(cuerpo.error))
      }
    } catch { /* nos quedamos con el mensaje genérico */ }
    const fallo = new CrmApiError(mensaje, 'CONVERTIR_FALLIDO')
    registrarError('crm.convertir.fallido', fallo)
    throw fallo
  }
  const cuerpo = (data ?? {}) as Partial<ConvertirLeadResultado>
  return {
    perfil_id: String(cuerpo.perfil_id ?? ''),
    ya_existia: Boolean(cuerpo.ya_existia),
    email_enviado: Boolean(cuerpo.email_enviado),
  }
}

// ── Contrato del cliente convertido (RPC public.crear_contrato del PORTAL, reusada
//    tal cual: crea contrato + cronograma de forma atómica y valida rol/cartera
//    server-side). El cronograma se calcula con lib/cronograma (espejo del portal). ─
export interface CrearContratoInput {
  cliente_id: string
  capital: number
  moneda: 'PEN' | 'USD'
  tasa_anual: number
  modalidad: ModalidadContrato
  tipo_interes: TipoInteres
  categoria: CategoriaContrato
  fecha_inicio: string
  fecha_vencimiento: string
  numero_contrato?: string | null
  notas_internas?: string | null
  /**
   * Co-titulares (cuentas mancomunadas, máx 5): viajan DENTRO de p_contrato —
   * crear_contrato ya los persiste vía _sync_contrato_titulares. Ausente o []
   * en el ALTA es lo mismo: contrato sin co-titulares.
   */
  titulares?: TitularInput[]
}

export interface CrearContratoResultado {
  id: string
  numero_contrato: string
}

export async function crearContrato(
  input: CrearContratoInput,
  cronograma: CuotaCronograma[],
): Promise<CrearContratoResultado> {
  const p_contrato: Record<string, unknown> = {
    cliente_id: input.cliente_id,
    capital: input.capital,
    moneda: input.moneda,
    tasa_anual: input.tasa_anual,
    modalidad: input.modalidad,
    tipo_interes: input.tipo_interes,
    categoria: input.categoria,
    fecha_inicio: input.fecha_inicio,
    fecha_vencimiento: input.fecha_vencimiento,
    numero_contrato: input.numero_contrato?.trim() || null,
    notas_internas: input.notas_internas?.trim() || null,
  }
  // En el alta, [] equivale a ausente: solo viajan si de verdad hay co-titulares.
  if (input.titulares && input.titulares.length > 0) p_contrato.titulares = input.titulares
  const p_cronograma = cronograma as unknown as Record<string, unknown>[]
  const { data, error } = await cliente().rpc('crear_contrato', { p_contrato, p_cronograma })
  if (error) throw aErrorApi(error, 'crm.contrato.crear_fallido')
  const r = (data ?? {}) as Partial<CrearContratoResultado>
  return { id: String(r.id ?? ''), numero_contrato: String(r.numero_contrato ?? '') }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL DEL ANALISTA EN EL CRM — clientes del portal + contratos (traspaso íntegro
// de public_html/admin/analista). El motor (edge crear-cliente v20, RPCs
// public.crear_contrato/actualizar_contrato, RLS con ventana de 5 h) YA está en
// prod y NO se toca: aquí solo se consume, con Valibot en cada frontera.
// ═══════════════════════════════════════════════════════════════════════════════

// Catálogos del portal como picklists runtime (espejo de los CHECK de `public`).
const MODALIDADES_CONTRATO = ['mensual', 'trimestral', 'semestral', 'anual'] as const
const TIPOS_INTERES = ['simple', 'compuesto'] as const
const CATEGORIAS_CONTRATO = ['nuevo', 'renovacion', 'upgrade'] as const
const TIPOS_CUOTA = ['cuota', 'retorno', 'devolucion'] as const

// Salvaguarda de payload (no seguridad — la vista/RLS ya recortan el ámbito).
const MAX_CLIENTES_CARTERA = 2000
const MAX_CONTRATOS_CARTERA = 2000

// ── Clientes: lista (vista crm.clientes_basicos, ya scopeada por rol) ──────────
const COLUMNAS_CLIENTE_BASICO = [
  'id',
  'nombres',
  'apellidos',
  'nombre_completo',
  'tipo_documento',
  'dni',
  'correo',
  'telefono',
  'asesor_perfil_id',
  'creado_por',
  'activo',
  'creado_en',
].join(',')

const ClienteBasicoRowSchema = v.object({
  id: v.string(),
  nombres: v.nullable(v.string()),
  apellidos: v.nullable(v.string()),
  nombre_completo: v.nullable(v.string()),
  // Tolerante A PROPÓSITO: un tipo de documento NUEVO en el portal no tira la
  // fila de la lista — degrada al default histórico 'DNI' (mismo criterio que
  // normalizarTipoDocumento). El detalle (ClienteDetalleRowSchema) sí es
  // estricto: ahí el tipo alimenta la validación del formulario.
  tipo_documento: v.fallback(v.picklist(TIPOS_DOCUMENTO_K), 'DNI'),
  dni: v.nullable(v.string()),
  correo: v.nullable(v.string()),
  telefono: v.nullable(v.string()),
  asesor_perfil_id: v.nullable(v.string()),
  // Junto con asesor_perfil_id decide la regla de cartera POR FILA en la UI
  // (Corregir/+Contrato solo sobre clientes propios — espejo del servidor).
  creado_por: v.nullable(v.string()),
  activo: v.boolean(),
  creado_en: v.string(),
})

export async function listarClientes(signal?: AbortSignal): Promise<ClienteBasico[]> {
  let consulta = cliente()
    .schema('crm')
    .from('clientes_basicos')
    .select(COLUMNAS_CLIENTE_BASICO)
    .order('creado_en', { ascending: false })
    .order('id', { ascending: true })
    .limit(MAX_CLIENTES_CARTERA)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar tu cartera de clientes.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.clientes.listado_fallido', fallo)
    throw fallo
  }
  const items: ClienteBasico[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(ClienteBasicoRowSchema, cruda)
    if (r.success) {
      items.push({ ...r.output, nombre_completo: r.output.nombre_completo ?? '' })
    } else {
      descartadas += 1
    }
  }
  if (descartadas > 0) {
    registrarError(
      'crm.clientes.filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas },
    )
  }
  return items
}

// ── Cliente: detalle con las 14 bancarias (public.perfiles vía RLS de cartera) ─
const COLUMNAS_CLIENTE_DETALLE = [
  'id',
  'nombre_completo',
  'nombres',
  'apellidos',
  'tipo_documento',
  'dni',
  'correo',
  'telefono',
  'asesor_perfil_id',
  'creado_por',
  'creado_en',
  'banco',
  'tipo_cuenta',
  'numero_cuenta',
  'cci',
  'titular_distinto',
  'beneficiario_nombre',
  'beneficiario_dni',
  'banco_usd',
  'tipo_cuenta_usd',
  'numero_cuenta_usd',
  'cci_usd',
  'titular_distinto_usd',
  'beneficiario_nombre_usd',
  'beneficiario_dni_usd',
].join(',')

const ClienteDetalleRowSchema = v.object({
  id: v.string(),
  nombre_completo: v.nullable(v.string()),
  nombres: v.nullable(v.string()),
  apellidos: v.nullable(v.string()),
  tipo_documento: v.picklist(TIPOS_DOCUMENTO_K),
  dni: v.nullable(v.string()),
  correo: v.nullable(v.string()),
  telefono: v.nullable(v.string()),
  asesor_perfil_id: v.nullable(v.string()),
  creado_por: v.nullable(v.string()),
  creado_en: v.string(),
  banco: v.nullable(v.string()),
  tipo_cuenta: v.nullable(v.string()),
  numero_cuenta: v.nullable(v.string()),
  cci: v.nullable(v.string()),
  titular_distinto: v.boolean(),
  beneficiario_nombre: v.nullable(v.string()),
  beneficiario_dni: v.nullable(v.string()),
  banco_usd: v.nullable(v.string()),
  tipo_cuenta_usd: v.nullable(v.string()),
  numero_cuenta_usd: v.nullable(v.string()),
  cci_usd: v.nullable(v.string()),
  titular_distinto_usd: v.boolean(),
  beneficiario_nombre_usd: v.nullable(v.string()),
  beneficiario_dni_usd: v.nullable(v.string()),
})

/**
 * Detalle completo para el modo "corregir". Se usa `.limit(1)` (no `.single()`)
 * a propósito: la frontera HTTP queda SIEMPRE con forma de array — mismos mocks
 * en msw/Playwright y sin el 406 especial de PostgREST.
 */
export async function obtenerClienteDetalle(id: string, signal?: AbortSignal): Promise<ClienteDetalle> {
  let consulta = cliente()
    .from('perfiles')
    .select(COLUMNAS_CLIENTE_DETALLE)
    .eq('id', id)
    .limit(1)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el cliente.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.clientes.detalle_fallido', fallo)
    throw fallo
  }
  const cruda = (data ?? [])[0]
  if (!cruda) {
    // La RLS ocultó el perfil (fuera de tu cartera) o no existe: mismo mensaje,
    // sin revelar existencia (igual que actualizarLead).
    throw new CrmApiError('Cliente no encontrado', 'NO_ENCONTRADO')
  }
  const r = v.safeParse(ClienteDetalleRowSchema, cruda)
  if (!r.success) {
    const fallo = new CrmApiError('Los datos del cliente no tienen el formato esperado.', 'ROW_CONTRACT')
    registrarError('crm.clientes.detalle_fuera_de_contrato', fallo)
    throw fallo
  }
  return { ...r.output, nombre_completo: r.output.nombre_completo ?? '' }
}

// ── Alta de cliente (edge crear-cliente del portal: Auth + perfil + correo REAL
//    de bienvenida; clave temporal = documento con padStart(8,'0') server-side).
//    La edge NO acepta bancarios: esos van en un SEGUNDO paso con
//    actualizarClientePortal (mismo flujo que el portal). ────────────────────────
export interface CrearClientePortalInput {
  email: string
  /** Opcional: sin password la edge usa la clave temporal (= documento). */
  password?: string | null
  nombre_completo: string
  apellidos: string
  nombres: string
  dni: string
  telefono?: string | null
  tipo_documento: TipoDocumentoCliente
}

export interface AltaClienteResultado {
  userId: string
  emailEnviado: boolean
}

// Los fallos de Supabase Auth llegan en inglés crudo desde las edges que crean
// usuarios (solo reenvían createErr.message). Espejo del mapeo del portal
// (analista.js:624-630): el analista lee es-PE, no 'A user with this email…'.
function traducirErrorAlta(mensaje: string): string {
  if (/already.+(registered|exists)/i.test(mensaje)) return 'Este correo ya está registrado.'
  if (/invalid.+email|email.+invalid/i.test(mensaje)) return 'El correo electrónico no es válido.'
  return mensaje
}

export async function crearClientePortal(payload: CrearClientePortalInput): Promise<AltaClienteResultado> {
  const body: Record<string, unknown> = {
    email: payload.email,
    nombre_completo: payload.nombre_completo,
    apellidos: payload.apellidos,
    nombres: payload.nombres,
    dni: payload.dni,
    telefono: payload.telefono ?? null,
    tipo_documento: payload.tipo_documento,
  }
  if (payload.password) body.password = payload.password

  const { data, error } = await cliente().functions.invoke('crear-cliente', { body })
  if (error) {
    let mensaje = 'No se pudo crear el cliente.'
    // FunctionsHttpError expone la respuesta del edge en `context`: extraemos
    // nuestro { error } es-PE (mensaje seguro que arma la propia edge).
    try {
      const ctx = (error as { context?: Response }).context
      if (ctx && typeof ctx.json === 'function') {
        const cuerpo = await ctx.json()
        if (cuerpo?.error) mensaje = traducirErrorAlta(String(cuerpo.error))
      }
    } catch { /* nos quedamos con el mensaje genérico */ }
    const fallo = new CrmApiError(mensaje, 'ALTA_CLIENTE_FALLIDA')
    registrarError('crm.clientes.alta_fallida', fallo)
    throw fallo
  }
  const cuerpo = (data ?? {}) as { ok?: boolean; user_id?: string; email_enviado?: boolean; error?: string }
  if (cuerpo.error) {
    const fallo = new CrmApiError(String(cuerpo.error), 'ALTA_CLIENTE_FALLIDA')
    registrarError('crm.clientes.alta_fallida', fallo)
    throw fallo
  }
  const userId = String(cuerpo.user_id ?? '')
  if (!userId) {
    // Sin id no hay 2º paso de bancarios ni contrato: se reporta como fallo,
    // nunca como éxito silencioso (lección del portal).
    const fallo = new CrmApiError('El alta no devolvió el id del cliente.', 'ALTA_SIN_ID')
    registrarError('crm.clientes.alta_sin_id', fallo)
    throw fallo
  }
  return { userId, emailEnviado: Boolean(cuerpo.email_enviado) }
}

// ── Corrección del cliente (UPDATE directo a perfiles; RLS = dueño + 5 h) ──────
export type ClientePortalPatch = Database['public']['Tables']['perfiles']['Update']

/**
 * Devuelve `true` si el servidor guardó y `false` si el UPDATE tocó 0 filas —
 * LA trampa de la ventana de 5 h: al vencer, la RLS deja de matchear la fila y
 * PostgREST responde 200 con lista vacía, SIN error. Jamás asumir éxito sin filas.
 */
export async function actualizarClientePortal(id: string, patch: ClientePortalPatch): Promise<boolean> {
  const { data, error } = await cliente()
    .from('perfiles')
    .update(patch)
    .eq('id', id)
    .select('id')
  if (error) throw aErrorApi(error, 'crm.clientes.update_fallido')
  return (data?.length ?? 0) > 0
}

// ── Contratos de mi cartera (public.contratos + nombre del cliente embebido) ───
// El embed va DESAMBIGUADO por FK: contratos tiene más de una relación a
// perfiles (cliente_id, cerrado_por) y un hint ausente sería un 300 de PostgREST.
const COLUMNAS_CONTRATO = [
  'id',
  'numero_contrato',
  'cliente_id',
  'capital',
  'moneda',
  'tasa_anual',
  'modalidad',
  'tipo_interes',
  'categoria',
  'estado',
  'fecha_inicio',
  'fecha_vencimiento',
  'notas_internas',
  'creado_por',
  'creado_en',
  'cliente_nombre',
].join(',')

const ContratoRowSchema = v.object({
  id: v.string(),
  numero_contrato: v.string(),
  cliente_id: v.string(),
  // numeric(12,2): PostgREST puede serializarlo como string
  capital: v.union([v.number(), v.string()]),
  moneda: v.picklist(['PEN', 'USD']),
  tasa_anual: v.union([v.number(), v.string()]),
  modalidad: v.picklist(MODALIDADES_CONTRATO),
  tipo_interes: v.picklist(TIPOS_INTERES),
  categoria: v.nullable(v.picklist(CATEGORIAS_CONTRATO)),
  estado: v.picklist(ESTADOS_CONTRATO),
  fecha_inicio: v.string(),
  fecha_vencimiento: v.string(),
  notas_internas: v.nullable(v.string()),
  creado_por: v.nullable(v.string()),
  creado_en: v.string(),
  cliente_nombre: v.nullable(v.string()),
})

export async function listarMisContratos(signal?: AbortSignal): Promise<ContratoRow[]> {
  // Vista con ámbito del esquema crm (molde clientes_basicos): gerencia ve
  // todo, supervisor su subárbol, vendedor su cartera. La RLS directa de
  // public.contratos dejaba a gerencia en 0 filas y al supervisor sin su equipo.
  let consulta = cliente()
    .schema('crm')
    .from('contratos_cartera')
    .select(COLUMNAS_CONTRATO)
    .order('creado_en', { ascending: false })
    .order('id', { ascending: true })
    .limit(MAX_CONTRATOS_CARTERA)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar tus contratos.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.contratos.listado_fallido', fallo)
    throw fallo
  }
  const items: ContratoRow[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(ContratoRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    const fila = r.output
    items.push({
      id: fila.id,
      numero_contrato: fila.numero_contrato,
      cliente_id: fila.cliente_id,
      cliente_nombre: fila.cliente_nombre,
      capital: aNumero(fila.capital) ?? 0,
      moneda: fila.moneda,
      tasa_anual: aNumero(fila.tasa_anual) ?? 0,
      modalidad: fila.modalidad,
      tipo_interes: fila.tipo_interes,
      categoria: fila.categoria,
      estado: fila.estado,
      fecha_inicio: fila.fecha_inicio,
      fecha_vencimiento: fila.fecha_vencimiento,
      notas_internas: fila.notas_internas,
      creado_por: fila.creado_por,
      creado_en: fila.creado_en,
    })
  }
  if (descartadas > 0) {
    registrarError(
      'crm.contratos.filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas },
    )
  }
  return items
}

// ── Cronograma del contrato (solo lectura; RLS fail-closed: ajeno = 0 filas) ───
const COLUMNAS_CUOTA = [
  'id',
  'numero_cuota',
  'fecha_programada',
  'monto_programado',
  'estado',
  'tipo',
  'fecha_pago_real',
  'monto_pagado',
].join(',')

const CuotaRowSchema = v.object({
  id: v.string(),
  numero_cuota: v.number(),
  fecha_programada: v.string(),
  monto_programado: v.union([v.number(), v.string()]),
  estado: v.picklist(ESTADOS_CUOTA),
  tipo: v.picklist(TIPOS_CUOTA),
  fecha_pago_real: v.nullable(v.string()),
  monto_pagado: v.nullable(v.union([v.number(), v.string()])),
})

export async function obtenerCronograma(contratoId: string, signal?: AbortSignal): Promise<Cuota[]> {
  // RPC con ámbito (crm.cronograma_contrato_fn): fuera de ámbito = 0 filas.
  // La lectura directa por RLS dejaba el detalle VACÍO a gerencia/supervisor.
  let consulta = cliente()
    .schema('crm')
    .rpc('cronograma_contrato_fn', { p_contrato_id: contratoId })
    .select(COLUMNAS_CUOTA)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el cronograma.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.cronograma.listado_fallido', fallo)
    throw fallo
  }
  const items: Cuota[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(CuotaRowSchema, cruda)
    if (r.success) {
      items.push({
        ...r.output,
        monto_programado: aNumero(r.output.monto_programado) ?? 0,
        monto_pagado: aNumero(r.output.monto_pagado),
      })
    }
  }
  return items
}

// ── Co-titulares del contrato (cuentas mancomunadas, solo lectura) ─────────────
const TitularRowSchema = v.object({
  nombre_completo: v.string(),
  tipo_documento: v.picklist(TIPOS_DOCUMENTO_K),
  documento: v.string(),
  orden: v.number(),
})

export async function obtenerTitulares(contratoId: string, signal?: AbortSignal): Promise<Titular[]> {
  let consulta = cliente()
    .schema('crm')
    .rpc('titulares_contrato_fn', { p_contrato_id: contratoId })
    .select('nombre_completo, tipo_documento, documento, orden')
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar los co-titulares.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.titulares.listado_fallido', fallo)
    throw fallo
  }
  const items: Titular[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(TitularRowSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

// ── Corrección del contrato (RPC actualizar_contrato: creado_por → 5 h → cartera;
//    regenera el cronograma conservando cuotas pagadas). ────────────────────────
export interface ActualizarContratoInput {
  capital: number
  moneda: 'PEN' | 'USD'
  tasa_anual: number
  modalidad: ModalidadContrato
  tipo_interes: TipoInteres
  categoria: CategoriaContrato
  fecha_inicio: string
  fecha_vencimiento: string
  numero_contrato: string
  /**
   * SIEMPRE cargar el valor vigente antes de abrir el form: si p_contrato no
   * trae esta clave, el servidor BORRA las notas. Por eso aquí NO es opcional.
   */
  notas_internas: string | null
  /**
   * Semántica del servidor: clave AUSENTE = no tocar; PRESENTE (incluso []) =
   * REEMPLAZAR el set completo. Cargar los actuales (obtenerTitulares) antes de
   * mandar, o los co-titulares se borran en silencio.
   */
  titulares?: TitularInput[]
}

export async function actualizarContrato(
  id: string,
  contrato: ActualizarContratoInput,
  cronograma: CuotaCronograma[],
): Promise<void> {
  const p_contrato: Record<string, unknown> = {
    capital: contrato.capital,
    moneda: contrato.moneda,
    tasa_anual: contrato.tasa_anual,
    modalidad: contrato.modalidad,
    tipo_interes: contrato.tipo_interes,
    categoria: contrato.categoria,
    fecha_inicio: contrato.fecha_inicio,
    fecha_vencimiento: contrato.fecha_vencimiento,
    numero_contrato: contrato.numero_contrato,
    notas_internas: contrato.notas_internas, // presente SIEMPRE, aunque sea null
  }
  // `titulares` solo viaja si el caller lo decidió (ver ActualizarContratoInput).
  if (contrato.titulares) p_contrato.titulares = contrato.titulares
  const { error } = await cliente().rpc('actualizar_contrato', {
    p_id: id,
    p_contrato,
    p_cronograma: cronograma as unknown as Record<string, unknown>[],
  })
  // La ventana vencida AQUÍ sí es un error explícito (RAISE P0001 de la RPC),
  // a diferencia del UPDATE a perfiles que se queda callado.
  if (error) throw aErrorApi(error, 'crm.contrato.actualizar_fallido')
}

// ═══════════════════════════════════════════════════════════════════════════════
// MÉTRICAS DE GERENCIA — 4 RPCs crm.metricas_*_fn (SECURITY DEFINER, ya en prod).
// El ÁMBITO lo resuelve el servidor (gerencia=todo, supervisor=subárbol,
// vendedor=él): el navegador jamás recorta ni agrega seguridad. Aquí solo se
// valida cada fila con Valibot y se coerciona numeric/bigint (PostgREST puede
// serializar numeric como string — mismo trato que monto_estimado/capital).
// El pivoteo para las gráficas vive en lib/metricas (helpers puros).
// ═══════════════════════════════════════════════════════════════════════════════

// numeric/bigint del servidor: número o string según el serializador.
const NumericoRpc = v.union([v.number(), v.string()])

const MetricaCapitalRowSchema = v.object({
  mes: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  // Sin picklist a propósito: una categoría nueva del portal NO debe tirar la
  // fila — lib/metricas ya agrupa lo desconocido como '—' (sin categoría).
  categoria: v.nullable(v.string()),
  contratos: NumericoRpc,
  capital_colocado: NumericoRpc,
})

const MetricaPagosRowSchema = v.object({
  mes: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  tipo: v.picklist(TIPOS_CUOTA),
  estado: v.picklist(ESTADOS_CUOTA),
  cuotas: NumericoRpc,
  monto_programado: NumericoRpc,
  monto_pagado: NumericoRpc,
})

const MetricaAltasRowSchema = v.object({
  mes: v.string(),
  analista_id: v.string(),
  analista_nombre: v.string(),
  altas: NumericoRpc,
})

const MetricaVencimientosRowSchema = v.object({
  mes: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  contratos_por_vencer: NumericoRpc,
  capital_por_vencer: NumericoRpc,
})

/** Error de RPC de métricas → CrmApiError es-PE + registro (patrón del módulo). */
function falloMetricas(
  error: { code?: string | null },
  contexto: string,
): CrmApiError {
  const fallo = new CrmApiError('No se pudieron cargar las métricas.', error.code || 'POSTGREST_ERROR')
  registrarError(contexto, fallo)
  return fallo
}

/** Registra (sin PII) cuántas filas de una RPC de métricas quedaron fuera de contrato. */
function registrarFilasMetricasInvalidas(rpc: string, descartadas: number): void {
  if (descartadas === 0) return
  registrarError(
    'crm.metricas.filas_invalidas',
    new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
    { rpc, descartadas },
  )
}

/** Capital colocado por mes/moneda/categoría (default: últimos 12 meses). */
export async function listarMetricasCapitalMes(
  pMeses = 12,
  signal?: AbortSignal,
): Promise<FilaCapitalMes[]> {
  let consulta = cliente().schema('crm').rpc('metricas_capital_mes_fn', { p_meses: pMeses })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw falloMetricas(error, 'crm.metricas.capital_fallido')
  const items: FilaCapitalMes[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaCapitalRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      moneda: r.output.moneda,
      categoria: r.output.categoria,
      contratos: aNumero(r.output.contratos) ?? 0,
      capital_colocado: aNumero(r.output.capital_colocado) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('capital_mes', descartadas)
  return items
}

/** Pagos por mes/moneda/tipo/estado (default: últimos 12 meses). */
export async function listarMetricasPagosMes(
  pMeses = 12,
  signal?: AbortSignal,
): Promise<FilaPagosMes[]> {
  let consulta = cliente().schema('crm').rpc('metricas_pagos_mes_fn', { p_meses: pMeses })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw falloMetricas(error, 'crm.metricas.pagos_fallido')
  const items: FilaPagosMes[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaPagosRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      moneda: r.output.moneda,
      tipo: r.output.tipo,
      estado: r.output.estado,
      cuotas: aNumero(r.output.cuotas) ?? 0,
      monto_programado: aNumero(r.output.monto_programado) ?? 0,
      monto_pagado: aNumero(r.output.monto_pagado) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('pagos_mes', descartadas)
  return items
}

/** Altas de clientes por analista y mes (default: últimos 12 meses). */
export async function listarMetricasAltasAnalista(
  pMeses = 12,
  signal?: AbortSignal,
): Promise<FilaAltasAnalista[]> {
  let consulta = cliente().schema('crm').rpc('metricas_altas_analista_fn', { p_meses: pMeses })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw falloMetricas(error, 'crm.metricas.altas_fallido')
  const items: FilaAltasAnalista[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaAltasRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      analista_id: r.output.analista_id,
      analista_nombre: r.output.analista_nombre,
      altas: aNumero(r.output.altas) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('altas_analista', descartadas)
  return items
}

/** Contratos/capital por vencer por mes/moneda dentro de p_dias (default 90). */
export async function listarMetricasVencimientos(
  pDias = 90,
  signal?: AbortSignal,
): Promise<FilaVencimientos[]> {
  let consulta = cliente().schema('crm').rpc('metricas_vencimientos_fn', { p_dias: pDias })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw falloMetricas(error, 'crm.metricas.vencimientos_fallido')
  const items: FilaVencimientos[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaVencimientosRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      moneda: r.output.moneda,
      contratos_por_vencer: aNumero(r.output.contratos_por_vencer) ?? 0,
      capital_por_vencer: aNumero(r.output.capital_por_vencer) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('vencimientos', descartadas)
  return items
}

// ── Distribución de leads por capital (JSON V1 atómico) ──────────────────────

const FechaMetricaSchema = v.pipe(v.string(), v.isoDate())

const CapacidadActualizadaSchema = v.strictObject({
  perfil_id: v.pipe(v.string(), v.uuid()),
  capacidad_leads_objetivo: v.nullable(
    v.pipe(
      v.union([v.number(), v.string()]),
      v.transform((valor) => Number(valor)),
      v.number(),
      v.finite(),
      v.integer(),
      v.minValue(1),
      v.maxValue(1000),
    ),
  ),
})

export interface CapacidadLeadsObjetivoActualizada {
  analistaId: string
  capacidad: number | null
}

function periodoMetricasValido(desde: string, hasta: string): boolean {
  return v.safeParse(FechaMetricaSchema, desde).success
    && v.safeParse(FechaMetricaSchema, hasta).success
    && desde <= hasta
}

function lanzarAbortSiCorresponde(signal?: AbortSignal): void {
  if (!signal?.aborted) return
  throw signal.reason instanceof Error
    ? signal.reason
    : new DOMException('La solicitud fue cancelada.', 'AbortError')
}

/**
 * Fotografía atómica de distribución, capacidad, resultados y SLA.
 * A diferencia de las RPC tabulares antiguas, aquí no se descartan ramas
 * inválidas: una sola falla invalida el payload completo para no mezclar
 * denominadores o periodos incompatibles en Gerencia.
 */
export async function listarMetricasDistribucionLeads(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasDistribucionLeads> {
  if (!periodoMetricasValido(desde, hasta)) {
    const fallo = new CrmApiError(
      'El período de métricas no es válido.',
      'PERIODO_METRICAS_INVALIDO',
    )
    registrarError('crm.metricas.distribucion_periodo_invalido', fallo)
    throw fallo
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_distribucion_leads_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.distribucion_fallido')

  const resultado = v.safeParse(MetricasDistribucionLeadsSchema, data)
  if (
    !resultado.success
    || resultado.output.cohorte.desde_inclusivo !== desde
    || resultado.output.cohorte.hasta_inclusivo !== hasta
  ) {
    const fallo = new CrmApiError(
      'Las métricas de distribución no tienen el formato esperado.',
      'METRICAS_DISTRIBUCION_CONTRACT',
    )
    registrarError('crm.metricas.distribucion_fuera_de_contrato', fallo)
    throw fallo
  }

  return resultado.output
}

/** Gerencia fija o limpia la capacidad objetivo de un analista activo. */
export async function actualizarCapacidadLeadsObjetivo(
  analistaId: string,
  capacidad: number | null,
): Promise<CapacidadLeadsObjetivoActualizada> {
  const idValido = v.safeParse(v.pipe(v.string(), v.uuid()), analistaId).success
  const capacidadValida = capacidad == null
    || (Number.isInteger(capacidad) && capacidad >= 1 && capacidad <= 1000)
  if (!idValido || !capacidadValida) {
    throw new CrmApiError(
      'La capacidad debe estar entre 1 y 1000 leads, o quedar sin configurar.',
      'CAPACIDAD_INVALIDA',
    )
  }

  const { data, error } = await cliente().schema('crm').rpc(
    'actualizar_capacidad_leads_objetivo',
    {
      p_analista_id: analistaId,
      p_capacidad_leads_objetivo: capacidad,
    },
  )

  if (error) {
    let fallo: CrmApiError
    if (error.code === '22023') {
      fallo = new CrmApiError(
        'La capacidad debe estar entre 1 y 1000 leads, o quedar sin configurar.',
        'CAPACIDAD_INVALIDA',
      )
    } else if (error.code === 'P0002') {
      fallo = new CrmApiError('Analista activo no encontrado.', 'ANALISTA_NO_ENCONTRADO')
    } else if (error.code === '42501' || error.code === 'PGRST301') {
      fallo = new CrmApiError('No tienes permiso para configurar capacidades.', 'SIN_PERMISO')
    } else {
      fallo = new CrmApiError(
        'No se pudo actualizar la capacidad del analista.',
        error.code || 'POSTGREST_ERROR',
      )
    }
    registrarError('crm.equipo.capacidad_actualizar_fallido', fallo, { pg: error.code ?? '' })
    throw fallo
  }

  const respuesta = v.safeParse(v.strictTuple([CapacidadActualizadaSchema]), data)
  if (
    !respuesta.success
    || respuesta.output[0].perfil_id !== analistaId
    || respuesta.output[0].capacidad_leads_objetivo !== capacidad
  ) {
    const fallo = new CrmApiError(
      'La capacidad actualizada no tiene el formato esperado.',
      'CAPACIDAD_CONTRACT',
    )
    registrarError('crm.equipo.capacidad_fuera_de_contrato', fallo)
    throw fallo
  }

  return {
    analistaId: respuesta.output[0].perfil_id,
    capacidad: respuesta.output[0].capacidad_leads_objetivo,
  }
}
