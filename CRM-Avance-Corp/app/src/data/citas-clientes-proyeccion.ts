import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { camposIdentidadCliente, identidadClienteValida } from '@/lib/sujeto-gestion'
import { FechaSchema } from '@/lib/esquemas-rpc'

/**
 * Proyección de citas, Fase 0b (19/10/2026): reuniones con CLIENTES que no tienen lead,
 * contadas por fecha de CREACIÓN (día de Lima), sin paginar. Puerta
 * `crm.citas_clientes_proyeccion_fn` → núcleo `private.citas_clientes_proyeccion`
 * (migración 20261019213516 + enmienda 20261019224227). BORRADOR: todavía no lo usa ninguna pantalla.
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

const fechaLima = (instante: string) => new Intl.DateTimeFormat('en-CA', {
  timeZone:'America/Lima', year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date(instante))

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

type RespuestaSinTipos = { data: unknown; error: { code?: string | null; message?: string | null } | null }
type ConsultaSinTipos = PromiseLike<RespuestaSinTipos> & { abortSignal: (s: AbortSignal) => PromiseLike<RespuestaSinTipos> }

/**
 * La puerta todavía no sale de `gen:types` (se instala con la migración 20261019213516).
 * Misma llamada que `.rpc()` tipado; la respuesta se valida siempre con su esquema.
 * Se retira el cast cuando los tipos generados la conozcan.
 */
function rpcProyeccionClientes(args: { p_desde: string; p_hasta: string }, signal?: AbortSignal): PromiseLike<RespuestaSinTipos> {
  if (!sb) throw new CrmApiError('No se pudo conectar con el CRM.', 'CITAS_SIN_CONEXION')
  const crm = sb.schema('crm') as unknown as { rpc: (fn: string, a: Record<string, unknown>) => ConsultaSinTipos }
  const consulta = crm.rpc('citas_clientes_proyeccion_fn', args)
  return signal ? consulta.abortSignal(signal) : consulta
}

/** Reuniones con clientes sin lead generadas entre `desde` y `hasta` (YYYY-MM-DD, día de Lima; hasta un año). */
export async function cargarCitasClientesProyeccion(desde: string, hasta: string, signal?: AbortSignal): Promise<CitasClientesProyeccionRpc> {
  if (!v.is(FechaSchema, desde) || !v.is(FechaSchema, hasta) || desde > hasta) {
    throw new CrmApiError('Selecciona un rango válido.', 'CITAS_PERIODO')
  }
  const { data, error } = await rpcProyeccionClientes({ p_desde: desde, p_hasta: hasta }, signal)
  if (error) throw new CrmApiError(error.code === 'PGRST202'
    ? 'Las reuniones con clientes de la Proyección aún no están habilitadas en este servidor.'
    : 'No se pudieron cargar las reuniones con clientes. Reintenta la consulta.', error.code ?? undefined)
  const resultado = v.safeParse(CitasClientesProyeccionSchema, data)
  if (!resultado.success || !citasClientesProyeccionCoherentes(resultado.output, desde, hasta)) {
    throw new CrmApiError('La respuesta de reuniones con clientes está incompleta o no corresponde al rango.', 'CITAS_CONTRATO')
  }
  return resultado.output
}
