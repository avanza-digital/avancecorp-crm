import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CAMPOS_LEGALES_ANALISTA, CAMPOS_LEGALES_CLIENTE, CrmApiError, type DatosLegalesContrato } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'
import type { CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'
import type { Moneda } from '@/lib/format'

// Venta cruzada: una inversión nueva o un upgrade de un cliente de OTRA cartera, sin lead,
// sin tocar a su responsable. Todas las llamadas pasan por las puertas del servidor
// (crm.*_cliente_existente_fn); la llave es la búsqueda por documento de quien vende o, ya
// preparada, la propia solicitud.

const Id = v.pipe(v.string(), v.uuid())
const TipoDocumento = v.picklist(['DNI', 'CE', 'PASAPORTE'])
export type TipoDocumentoBusqueda = v.InferOutput<typeof TipoDocumento>

const AccionesSchema = v.object({
  ver_ficha: v.boolean(), nueva_inversion: v.boolean(), requiere_documento: v.boolean(),
  motivo_codigo: v.nullable(v.string()), motivo_no_operable: v.nullable(v.string()),
})
const ClienteSchema = v.object({
  inversionista_id: v.nullable(Id), nombre: v.nullable(v.string()), documento_tipo: v.nullable(TipoDocumento),
  documento_enmascarado: v.nullable(v.string()), responsable_nombre: v.nullable(v.string()),
  empresas: v.array(v.string()), es_mi_cartera: v.boolean(),
})
export const BusquedaClienteSchema = v.variant('estado', [
  v.object({
    estado: v.picklist(['no_encontrado', 'ambiguo', 'conflicto', 'limite', 'invalido']),
    busqueda_id: Id, criterio: v.picklist(['documento', 'telefono', 'lead']),
  }),
  v.object({
    estado: v.picklist(['encontrado', 'no_operable']), busqueda_id: Id, criterio: v.picklist(['documento', 'telefono', 'lead']),
    // Con un motivo reservado el servidor no nombra a la persona: solo dice si es de tu cartera.
    cliente: v.union([ClienteSchema, v.object({es_mi_cartera: v.boolean()})]),
    acciones: AccionesSchema,
  }),
])
export type BusquedaCliente = v.InferOutput<typeof BusquedaClienteSchema>

export const ContextoClienteExistenteSchema = v.object({
  solicitud_id: v.nullable(Id), documento_tipo: v.nullable(TipoDocumento),
  persona: v.object({
    inversionista_id: Id, perfil_id: v.nullable(Id), tiene_acceso_avance: v.nullable(v.boolean()),
    nombre: v.nullable(v.string()), correo: v.null(), telefono: v.null(),
    responsable_id: v.nullable(Id), responsable_nombre: v.nullable(v.string()),
  }),
  capacidades: v.object({
    nueva_inversion: v.boolean(), motivo_codigo: v.nullable(v.string()), motivo_no_operable: v.nullable(v.string()),
  }),
})
export type ContextoClienteExistente = v.InferOutput<typeof ContextoClienteExistenteSchema>

const CuentaEnmascaradaSchema = v.object({
  cuenta_id: Id, moneda: v.picklist(['PEN', 'USD']), banco: v.string(), tipo_cuenta: v.picklist(['ahorros', 'corriente']),
  numero_enmascarado: v.string(), cci_enmascarado: v.string(), titular_distinto: v.boolean(), creada_en: v.string(),
})
const DatosLegalesSchema = v.object({
  version: v.literal(1), cliente_id: Id, falta_domicilio: v.boolean(),
  faltan_cliente: v.array(v.picklist(CAMPOS_LEGALES_CLIENTE)), faltan_analista: v.array(v.picklist(CAMPOS_LEGALES_ANALISTA)),
})
const ContratoUpgradeSchema = v.object({
  contrato_id: Id, numero_contrato: v.string(), capital: v.number(), moneda: v.picklist(['PEN', 'USD']),
  tasa_anual: v.number(), fecha_vencimiento: v.string(),
})

/** La llave de una lectura: la búsqueda vigente (antes de preparar) o la solicitud. */
export type LlaveVentaCruzada = {busquedaId: string; solicitudId?: undefined} | {solicitudId: string; busquedaId?: undefined}
const argsLlave = (llave: LlaveVentaCruzada): {p_solicitud: string} | {p_busqueda: string} =>
  llave.solicitudId !== undefined ? {p_solicitud: llave.solicitudId} : {p_busqueda: llave.busquedaId}

function cliente() {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb
}

export type CriterioBusqueda =
  | {tipo: 'documento'; tipoDocumento: TipoDocumentoBusqueda; numero: string}
  | {tipo: 'telefono'; telefono: string}
  | {tipo: 'lead'; leadId: string}

/** Búsqueda exacta. Siempre deja rastro en el servidor; el veredicto viene en la respuesta. */
export async function buscarClienteExistente(criterio: CriterioBusqueda): Promise<BusquedaCliente> {
  const args = criterio.tipo === 'documento' ? {p_tipo_documento: criterio.tipoDocumento, p_documento: criterio.numero}
    : criterio.tipo === 'telefono' ? {p_telefono: criterio.telefono} : {p_lead: criterio.leadId}
  return respuestaInversionistas(BusquedaClienteSchema, await cliente().schema('crm').rpc('buscar_cliente_existente_fn', args))
}

export async function obtenerContextoClienteExistente(llave: LlaveVentaCruzada, signal: AbortSignal): Promise<ContextoClienteExistente> {
  return respuestaInversionistas(ContextoClienteExistenteSchema,
    await cliente().schema('crm').rpc('contexto_cliente_existente_fn', argsLlave(llave)).abortSignal(signal))
}

/** Cuentas registradas del cliente, enmascaradas (D3), con la forma que usa el formulario
 * del contrato. Seleccionar una manda {tipo: 'existente', cuenta_id}. */
export async function cuentasClienteExistente(llave: LlaveVentaCruzada, moneda: Moneda, signal?: AbortSignal): Promise<CuentaBancariaSeleccionable[]> {
  const q = cliente().schema('crm').rpc('cuentas_cliente_existente_fn', {...argsLlave(llave), p_moneda: moneda})
  const filas = respuestaInversionistas(v.array(CuentaEnmascaradaSchema), await (signal ? q.abortSignal(signal) : q))
  return filas.map(f => ({
    cuenta_id: f.cuenta_id, moneda: f.moneda, banco: f.banco, tipo_cuenta: f.tipo_cuenta,
    numero_cuenta: f.numero_enmascarado, cci: f.cci_enmascarado, titular_distinto: f.titular_distinto,
    beneficiario_nombre: null, beneficiario_dni: null, origen: 'contrato', es_cuenta_perfil: false, creada_en: f.creada_en,
  }))
}

/** Mismo contenido y forma que los datos legales de siempre, con la llave de la venta. */
export async function datosLegalesClienteExistente(llave: LlaveVentaCruzada, signal?: AbortSignal): Promise<DatosLegalesContrato> {
  const q = cliente().schema('crm').rpc('datos_legales_cliente_existente_fn', argsLlave(llave))
  const r = respuestaInversionistas(DatosLegalesSchema, await (signal ? q.abortSignal(signal) : q))
  return {clienteId: r.cliente_id, faltaDomicilio: r.falta_domicilio, faltanCliente: [...r.faltan_cliente], faltanAnalista: [...r.faltan_analista]}
}

/** Contratos Avance activos del cliente que un upgrade puede ampliar (D5). */
export async function contratosUpgradeClienteExistente(llave: LlaveVentaCruzada, signal?: AbortSignal) {
  const q = cliente().schema('crm').rpc('contratos_upgrade_cliente_existente_fn', argsLlave(llave))
  return respuestaInversionistas(v.array(ContratoUpgradeSchema), await (signal ? q.abortSignal(signal) : q))
}
