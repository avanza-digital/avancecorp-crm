import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { crmQueryKeys } from './crm-queries'
import { CADENCIA_CITAS, estadoDeCita, fechaLima } from './citas-gerencia'
import { camposIdentidadCliente, identidadClienteValida } from '@/lib/sujeto-gestion'
import { FechaSchema } from '@/lib/esquemas-rpc'
import { horaLima } from '@/components/citas/contexto'
import type { ReunionClienteProyeccion } from '@/components/citas/proyeccion'
import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'

/**
 * Proyección de citas, Fase 0b (19/10/2026): reuniones con CLIENTES que no tienen lead,
 * contadas por fecha de CREACIÓN (día de Lima), sin paginar. Puerta
 * `crm.citas_clientes_proyeccion_fn` → núcleo `private.citas_clientes_proyeccion`
 * (migración 20261019213516 + enmienda 20261019224227). La usa la pestaña Proyección de Citas.
 *
 * `generado_en` es el CORTE (enmienda 20261019224227): el servidor sólo devuelve reuniones
 * creadas, y asistencias registradas, hasta ese instante; por eso el validador lo exige.
 * Coste medido en el banco: ~0,7 ms por persona F6 distinta y ~6 ms por perfil distinto; con
 * el `statement_timeout` de 8 s, un rango con más de ~1 000 perfiles distintos da 57014
 * (en producción no hay reuniones de perfil: las 39 históricas son de persona F6).
 *
 * Para la pantalla:
 * - Estas reuniones NO están en `crm.citas_gerencia_consulta[_v2]_fn` (que sólo recorre
 *   tareas con lead): se suman sin duplicar. El total `citas_clientes` de ese lector
 *   cuenta otra población (perfil, por fecha programada): no sumar ambos.
 * - Todas son citas con quien ya es cliente (perfil o persona F6).
 * - `identidad_persona` sólo nombra a la persona si su identidad es visible; si no, es
 *   `oculta:<id de la tarea>` (una por cita). No sirve para emparejar con el
 *   `identidad_persona` del lector de leads.
 */
const Instante = v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s))))
const Id = v.pipe(v.string(), v.uuid())
const UUID_TEXTO = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

const CitaClienteProyeccionCampos = v.object({
  ...camposIdentidadCliente,
  id: Id, creado_en: Instante, vence_en: Instante,
  estado: v.picklist(['pendiente','completada','no_show','cancelada','reprogramada']),
  cancelada_por: v.nullable(v.string()),
  asistencia_registrada_en: v.nullable(Instante),
  analista_id: v.nullable(Id), analista_nombre: v.string(),
  supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
  identidad_persona: v.pipe(v.string(), v.regex(new RegExp(`^(persona|perfil|oculta):${UUID_TEXTO}$`))),
})
type CitaClienteProyeccionCruda = v.InferOutput<typeof CitaClienteProyeccionCampos>

/** La clave de persona tiene que salir de la identidad que el servidor dejó ver, y de nada más. */
function identidadPersonaCoherente(c: CitaClienteProyeccionCruda): boolean {
  if (!c.identidad_visible) return c.identidad_persona === `oculta:${c.id}`
  if (c.inversionista_id) return c.identidad_persona === `persona:${c.inversionista_id}`
  return c.perfil_id !== null && c.identidad_persona === `perfil:${c.perfil_id}`
}

export const CitaClienteProyeccionSchema = v.pipe(CitaClienteProyeccionCampos, v.check(c =>
  identidadClienteValida(c) && identidadPersonaCoherente(c)
  && (c.asistencia_registrada_en === null || c.estado === 'completada')))

export const CitasClientesProyeccionSchema = v.object({
  version: v.literal(1),
  periodo: v.object({ desde: FechaSchema, hasta: FechaSchema }),
  criterio: v.literal('creado_en'),
  generado_en: Instante,
  citas: v.pipe(v.array(CitaClienteProyeccionSchema), v.maxLength(10000)),
})
export type CitasClientesProyeccionRpc = v.InferOutput<typeof CitasClientesProyeccionSchema>
export type CitaClienteProyeccion = CitasClientesProyeccionRpc['citas'][number]

/** El payload corresponde a lo pedido: mismo período, ids únicos y cada cita GENERADA dentro del rango. */
export function citasClientesProyeccionCoherentes(d: CitasClientesProyeccionRpc, desde: string, hasta: string): boolean {
  if (d.periodo.desde !== desde || d.periodo.hasta !== hasta) return false
  if (new Set(d.citas.map(c => c.id)).size !== d.citas.length) return false
  const generado = Date.parse(d.generado_en)
  return d.citas.every(c => {
    const dia = fechaLima(c.creado_en)
    return dia >= desde && dia <= hasta && Date.parse(c.creado_en) <= generado
      && (c.asistencia_registrada_en === null || Date.parse(c.asistencia_registrada_en) <= generado)
  })
}

/** Puerta tipada (tipos generados tras instalar 20261019213516 y su enmienda); la respuesta se valida siempre con su esquema. */
async function rpcProyeccionClientes(args: { p_desde: string; p_hasta: string }, signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No se pudo conectar con el CRM.', 'CITAS_SIN_CONEXION')
  const consulta = sb.schema('crm').rpc('citas_clientes_proyeccion_fn', args)
  return signal ? consulta.abortSignal(signal) : consulta
}

/** Más de 10 000 reuniones (54000) o la consulta agotó su tiempo (57014): el rango es demasiado grande. */
const RANGO_DEMASIADO_GRANDE = new Set(['54000', '57014'])
export const esRangoDemasiadoGrande = (error: unknown) => error instanceof CrmApiError && RANGO_DEMASIADO_GRANDE.has(error.code)

function mensajeDeError(code: string | null | undefined): string {
  if (code === 'PGRST202') return 'Las reuniones con clientes de la Proyección aún no están habilitadas en este servidor.'
  if (code && RANGO_DEMASIADO_GRANDE.has(code)) return 'El rango es demasiado grande. Acorta las fechas.'
  return 'No se pudieron cargar las reuniones con clientes. Reintenta la consulta.'
}

/** Reuniones con clientes sin lead generadas entre `desde` y `hasta` (YYYY-MM-DD, día de Lima; hasta un año). */
export async function cargarCitasClientesProyeccion(desde: string, hasta: string, signal?: AbortSignal): Promise<CitasClientesProyeccionRpc> {
  if (!v.is(FechaSchema, desde) || !v.is(FechaSchema, hasta) || desde > hasta) {
    throw new CrmApiError('Selecciona un rango válido.', 'CITAS_PERIODO')
  }
  const { data, error } = await rpcProyeccionClientes({ p_desde: desde, p_hasta: hasta }, signal)
  if (error) throw new CrmApiError(mensajeDeError(error.code), error.code ?? undefined)
  const resultado = v.safeParse(CitasClientesProyeccionSchema, data)
  if (!resultado.success || !citasClientesProyeccionCoherentes(resultado.output, desde, hasta)) {
    throw new CrmApiError('La respuesta de reuniones con clientes está incompleta o no corresponde al rango.', 'CITAS_CONTRATO')
  }
  return resultado.output
}

/**
 * Cada reunión como cita de la hoja: origen Cliente, sin lead, monto ni moneda; analista y supervisor del
 * lector (con los mismos «sin analista» / «sin supervisor» que Citas) y el estado en el vocabulario de Citas.
 */
export function adaptarCitasClientesProyeccion(datos: CitasClientesProyeccionRpc): ReunionClienteProyeccion[] {
  return datos.citas.map(c => ({
    id: c.id, leadId: null, moneda: null, monto: null, persona: c.identidad_persona, nombre: c.sujeto_nombre,
    analista: c.analista_id ?? 'sin_analista', analistaNombre: c.analista_nombre,
    supervisor: c.supervisor_nombre, supervisorId: c.supervisor_id ?? 'sin_supervisor',
    fecha: fechaLima(c.vence_en), hora: horaLima(c.vence_en), estado: estadoDeCita(c, datos.generado_en), creadoEn: c.creado_en,
    ...(c.asistencia_registrada_en ? { asistioEn: c.asistencia_registrada_en } : {}),
  }))
}

/**
 * Una consulta por rango, con la cadencia y la caché de los meses de Citas. Sin rango (otra pestaña) o en
 * demostración no consulta. Un rango demasiado grande no se reintenta ni se refresca solo: fallaría igual.
 */
export function opcionesCitasClientesProyeccion(rango: RangoProyeccion | null, actorId: string | null, habilitada: boolean) {
  const desde = rango?.desde ?? '', hasta = rango?.hasta ?? ''
  return {
    queryKey: crmQueryKeys.citasClientesProyeccion(actorId, desde, hasta),
    queryFn: ({ signal }: { signal: AbortSignal }) => cargarCitasClientesProyeccion(desde, hasta, signal),
    enabled: habilitada && Boolean(actorId) && rango !== null,
    ...CADENCIA_CITAS,
    refetchInterval: (consulta: { state: { error: unknown } }) => esRangoDemasiadoGrande(consulta.state.error) ? false : CADENCIA_CITAS.refetchInterval,
    // Codex 19/10: ni al recuperar el foco ni la conexión (fallaría igual).
    refetchOnWindowFocus: (consulta: { state: { error: unknown } }) => !esRangoDemasiadoGrande(consulta.state.error),
    refetchOnReconnect: (consulta: { state: { error: unknown } }) => !esRangoDemasiadoGrande(consulta.state.error),
    retry: (fallos: number, error: Error) => fallos < 1 && !esRangoDemasiadoGrande(error),
  }
}
