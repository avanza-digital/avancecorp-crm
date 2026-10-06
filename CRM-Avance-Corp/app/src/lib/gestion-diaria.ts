import { identidadClienteValida } from './sujeto-gestion'
import { instantePendiente } from './gestion-diaria-pendientes'
// Gestión Diaria — contrato del REGISTRO CRUDO de actividad (Fase 1) y sus
// helpers puros. La fuente única es `crm.registro_actividad_fn` (migración
// 20260919211958): una página keyset (creado_en desc, id asc) de actividades de
// una ventana de días Lima, por analistas, tipos y etapa del lead. Aquí no se
// cuenta ni se decide nada de negocio: solo se valida la forma y se presenta.
import * as v from 'valibot'
import { ETAPA_INFO, TIPOS_ACTIVIDAD, RESULTADOS_REUNION, type Actividad, type Etapa, type Miembro, type TipoActividad } from '@/lib/tipos'
import { RESULTADOS } from '@/lib/resultado-llamada'
import { fechaLima } from '@/lib/agenda-derivada'

const TIPOS_ACT = Object.keys(TIPOS_ACTIVIDAD) as [TipoActividad, ...TipoActividad[]]

/** Pestañas del registro: cada una acota `p_tipos`; «todo» no manda filtro. */
export const PESTANAS_REGISTRO = [
  { valor: 'llamadas', etiqueta: 'Llamadas', tipos: ['llamada_realizada', 'llamada_no_contestada'] },
  { valor: 'whatsapp', etiqueta: 'WhatsApp', tipos: ['whatsapp_enviado', 'whatsapp_recibido'] },
  { valor: 'notas', etiqueta: 'Notas', tipos: ['nota'] },
  { valor: 'todo', etiqueta: 'Todo', tipos: null },
] as const satisfies readonly { valor: string; etiqueta: string; tipos: readonly TipoActividad[] | null }[]
export type PestanaRegistro = (typeof PESTANAS_REGISTRO)[number]['valor']

export function tiposDePestana(pestana: PestanaRegistro): readonly TipoActividad[] | null {
  return PESTANAS_REGISTRO.find((p) => p.valor === pestana)?.tipos ?? null
}

/** Ítem tal como lo devuelve el servidor. `metadata` viaja completo (Fase 2 lo tipifica). */
export const RegistroItemSchema = v.object({
  id: v.string(),
  lead_id: v.nullable(v.string()),
  lead_nombre: v.nullable(v.string()),
  lead_etapa: v.nullable(v.string()),
  origen: v.optional(v.picklist(['lead', 'perfil', 'postventa'])),
  sujeto_tipo: v.optional(v.picklist(['lead', 'perfil', 'inversionista'])),
  sujeto_id: v.optional(v.nullable(v.string())),
  sujeto_nombre: v.optional(v.string()),
  inversionista_id: v.optional(v.nullable(v.string())),
  perfil_id: v.optional(v.nullable(v.string())),
  identidad_visible: v.optional(v.boolean()),
  etapa_en_ese_momento: v.nullable(v.string()),
  tipo: v.picklist(TIPOS_ACT),
  detalle: v.nullable(v.string()),
  metadata: v.record(v.string(), v.unknown()),
  creado_por: v.nullable(v.string()),
  autor_nombre: v.string(),
  creado_en: v.string(),
})
export type RegistroItem = v.InferOutput<typeof RegistroItemSchema>

export const RegistroPaginaSchema = v.object({
  version: v.union([v.literal(1), v.literal(2)]),
  generado_en: v.string(),
  desde: v.string(),
  hasta: v.string(),
  zona: v.literal('America/Lima'),
  limite: v.number(),
  items: v.array(RegistroItemSchema),
})
export type RegistroPagina = v.InferOutput<typeof RegistroPaginaSchema>

/** Cursor keyset: los dos componentes o ninguno (el servidor rechaza cursores a medias). */
export interface CursorRegistro {
  antes_de: string
  antes_id: string
  antes_origen?: 'lead' | 'perfil' | 'postventa'
}

export interface FiltrosRegistro {
  /** Día Lima (YYYY-MM-DD). La Fase 1 lista un solo día. */
  dia: string
  /** null = todo lo visible por la RLS; el analista siempre manda el suyo. */
  analistaIds: readonly string[] | null
  pestana: PestanaRegistro
  etapa: Etapa | null
  cartera?: 'leads' | 'clientes' | null | undefined
}

/** Cuántas filas pedir para saber si hay más sin contar: `limite + 1` (contrato del historial por lead). */
export function limiteConSonda(limite: number): number {
  return limite + 1
}

/** Recorta la sonda: devuelve la página visible y si el servidor tiene más. */
export function paginaVisible(items: readonly RegistroItem[], limite: number): { items: RegistroItem[]; hayMas: boolean } {
  return { items: items.slice(0, limite), hayMas: items.length > limite }
}

/** El cursor para pedir la página siguiente a partir de la última fila visible. */
export function cursorSiguiente(items: readonly RegistroItem[]): CursorRegistro | null {
  const ultimo = items[items.length - 1]
  return ultimo ? { antes_de: ultimo.creado_en, antes_id: ultimo.id, ...(ultimo.origen ? { antes_origen: ultimo.origen } : {}) } : null
}

/** Hora Lima «HH:MM» de una fila. */
export function horaDeItem(item: Pick<RegistroItem, 'creado_en'>): string {
  const ms = Date.parse(item.creado_en)
  if (!Number.isFinite(ms)) return '—'
  return new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(ms))
}

/** Chip corto por tipo: lo que el supervisor lee de un vistazo. */
export const ETIQUETA_CORTA: Record<TipoActividad, string> = {
  llamada_realizada: 'Contestó',
  llamada_no_contestada: 'No contestó',
  whatsapp_enviado: 'WhatsApp enviado',
  whatsapp_recibido: 'WhatsApp recibido',
  reunion_realizada: 'Entrevista realizada',
  nota: 'Nota',
  cambio_etapa: 'Cambio de etapa',
  reasignacion: 'Reasignación',
  conversion: 'Conversión',
}

/** Severidad visual del chip (color + texto, nunca solo color). */
export function tonoDeTipo(tipo: TipoActividad): 'ok' | 'atencion' | 'neutro' {
  if (tipo === 'llamada_realizada' || tipo === 'whatsapp_recibido' || tipo === 'reunion_realizada' || tipo === 'conversion') return 'ok'
  if (tipo === 'llamada_no_contestada') return 'atencion'
  return 'neutro'
}

/**
 * Espejo DEMO: la misma página a partir del timeline y los leads del ámbito en
 * memoria. El demo no conoce `creado_por` (el tipo Actividad no lo trae), así
 * que los analistas se resuelven por NOMBRE contra el roster demo. Mismo orden,
 * mismo cursor y misma sonda que el servidor, para que la pantalla no distinga.
 */
export function registroDesdeDemo(
  actividades: readonly Actividad[],
  leads: ReadonlyMap<string, { nombre_completo: string; etapa: string; activo?: boolean }>,
  equipo: readonly Miembro[],
  filtros: FiltrosRegistro,
  cursor: CursorRegistro | null,
  limiteConSondaN: number,
): RegistroPagina {
  const tipos = tiposDePestana(filtros.pestana)
  const nombresPermitidos = filtros.analistaIds === null
    ? null
    : new Set(equipo.filter((m) => filtros.analistaIds!.includes(m.perfil_id)).map((m) => m.nombre_completo))
  const filas = actividades
    .filter((a) => filtros.cartera !== 'clientes' && fechaLima(Date.parse(a.creado_en)) === filtros.dia)
    .filter((a) => tipos === null || (tipos as readonly string[]).includes(a.tipo))
    .filter((a) => nombresPermitidos === null || nombresPermitidos.has(a.autor_nombre))
    .map((a) => ({ a, lead: leads.get(a.lead_id) }))
    .filter((x): x is { a: Actividad; lead: { nombre_completo: string; etapa: string; activo?: boolean } } => x.lead !== undefined && x.lead.activo !== false)
    .filter((x) => filtros.etapa === null || x.lead.etapa === filtros.etapa)
    .sort((x, y) => y.a.creado_en.localeCompare(x.a.creado_en) || x.a.id.localeCompare(y.a.id))
    .filter((x) => cursor === null || x.a.creado_en < cursor.antes_de || (x.a.creado_en === cursor.antes_de && x.a.id > cursor.antes_id))
    .slice(0, limiteConSondaN)
  const idPorNombre = new Map(equipo.map((m) => [m.nombre_completo, m.perfil_id]))
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    desde: filtros.dia,
    hasta: filtros.dia,
    zona: 'America/Lima',
    limite: limiteConSondaN,
    items: filas.map(({ a, lead }) => ({
      id: a.id,
      lead_id: a.lead_id,
      lead_nombre: lead.nombre_completo,
      lead_etapa: lead.etapa,
      etapa_en_ese_momento: null,
      tipo: a.tipo,
      detalle: a.detalle,
      metadata: {},
      creado_por: idPorNombre.get(a.autor_nombre) ?? null,
      autor_nombre: a.autor_nombre,
      creado_en: a.creado_en,
    })),
  }
}

/** Analistas ACTIVOS del subárbol de un supervisor (la puerta rechaza inactivos en el filtro). */
export function analistasDelEquipo(equipo: readonly Miembro[], supervisorId: string): string[] {
  const raiz = new Set([supervisorId])
  let crecio = true
  while (crecio) {
    crecio = false
    for (const m of equipo) {
      if (m.supervisor_id && raiz.has(m.supervisor_id) && !raiz.has(m.perfil_id)) { raiz.add(m.perfil_id); crecio = true }
    }
  }
  return equipo.filter((m) => m.activo && m.rol_crm === 'vendedor' && raiz.has(m.perfil_id)).map((m) => m.perfil_id)
}

/** Etiqueta visible de una etapa (el CSV habla el mismo idioma que la pantalla). */
export function etiquetaEtapa(etapa: string | null): string | null {
  return etapa === null ? null : ETAPA_INFO[etapa as Etapa]?.label ?? etapa
}

/** Filas del CSV de exportación (gerencia): el detalle va íntegro, sin transformar. */
export function filasCsvRegistro(items: readonly RegistroItem[]): { cabecera: string[]; filas: (string | null)[][] } {
  return {
    cabecera: ['Fecha', 'Hora (Lima)', 'Analista', 'Persona', 'Cartera', 'Etapa entonces', 'Etapa actual', 'Tipo', 'Detalle', 'Resultado'],
    filas: items.map((i) => [
      fechaLima(Date.parse(i.creado_en)),
      horaDeItem(i),
      i.autor_nombre,
      i.sujeto_nombre ?? i.lead_nombre,
      i.sujeto_tipo && i.sujeto_tipo !== 'lead' ? 'Clientes' : 'Leads',
      etiquetaEtapa(i.etapa_en_ese_momento),
      etiquetaEtapa(i.lead_etapa),
      etiquetaGestion(i),
      i.detalle,
      resultadoGestion(i),
    ]),
  }
}

/** Los históricos F6 sin clasificación no afirman que hubo contacto. */
export function etiquetaGestion(item: RegistroItem): string {
  if (item.metadata['estado'] === 'no_show') return 'No asistió'
  if (item.metadata['estado'] === 'cancelada') return 'Tarea cancelada'
  if (item.origen === 'postventa' && item.tipo === 'llamada_realizada' && item.metadata['resultado'] === 'sin_resultado') return 'Llamada sin resultado'
  return ETIQUETA_CORTA[item.tipo]
}
export function resultadoGestion(item: RegistroItem): string | null {
  const valor = item.tipo === 'reunion_realizada' ? item.metadata['resultado_reunion'] : item.metadata['resultado']
  return typeof valor === 'string' ? valor : null
}
export function etiquetaResultadoCliente(resultado: string | null): string | null {
  if (!resultado) return null
  return RESULTADOS_REUNION.find(r => r.k === resultado)?.label ?? RESULTADOS.find(r => r.clave === resultado)?.etiqueta
    ?? ({ sin_clasificar: 'Sin resultado comercial registrado', sin_resultado: 'Sin resultado registrado', respondio: 'Respondió', enviado: 'Mensaje enviado' } as Record<string, string>)[resultado]
    ?? resultado.replaceAll('_', ' ')
}
export function resultadoGestionVisible(item: RegistroItem): string | null {
  const resultado = resultadoGestion(item)
  return item.origen === 'postventa' || item.origen === 'perfil' ? etiquetaResultadoCliente(resultado) : resultado?.replaceAll('_', ' ') ?? null
}

/** La v1 se conserva para demo; la RPC v2 exige identidad coherente para cada fuente. */
export const RegistroPaginaV2Schema = v.object({
  ...RegistroPaginaSchema.entries, version: v.literal(2),
  items: v.array(v.pipe(RegistroItemSchema, v.check(i => Boolean(i.origen && i.sujeto_tipo && i.sujeto_nombre)
    && (i.origen === 'lead'
      ? i.sujeto_tipo === 'lead' && i.identidad_visible === true && i.lead_id !== null && i.sujeto_id === i.lead_id && i.lead_nombre === i.sujeto_nombre && i.lead_etapa !== null && i.inversionista_id === null && i.perfil_id === null
      : i.lead_id === null && i.lead_nombre === null && i.lead_etapa === null && identidadClienteValida(i)
        && (i.origen === 'perfil' ? i.sujeto_tipo === 'perfil' : i.sujeto_tipo === 'inversionista')
        && (i.identidad_visible || i.detalle === null && i.metadata['tarea_id'] == null))))),
})
export function ordenRegistro(a: { creado_en: string; origen?: string | undefined; id: string }, b: { creado_en: string; origen?: string | undefined; id: string }): number {
  const x = instantePendiente(a.creado_en), y = instantePendiente(b.creado_en)
  if (x === null || y === null) return NaN
  return x > y ? -1 : x < y ? 1 : (a.origen ?? 'lead').localeCompare(b.origen ?? 'lead') || a.id.localeCompare(b.id)
}
export function registroCoherente(pagina: RegistroPagina, filtros: FiltrosRegistro, cursor: CursorRegistro | null, limite: number): boolean {
  if (pagina.desde !== filtros.dia || pagina.hasta !== filtros.dia || pagina.limite !== limite || pagina.items.length > limite) return false
  const claves = new Set<string>()
  const tipos = tiposDePestana(filtros.pestana)
  let anterior = cursor ? { creado_en: cursor.antes_de, id: cursor.antes_id, origen: cursor.antes_origen } : null
  for (const i of pagina.items) {
    const clave = `${i.origen}:${i.id}`
    if (claves.has(clave) || instantePendiente(i.creado_en) === null || fechaLima(Date.parse(i.creado_en)) !== filtros.dia
      || (anterior && !(ordenRegistro(anterior, i) < 0))
      || (tipos && !(tipos as readonly string[]).includes(i.tipo))
      || (filtros.etapa && i.lead_etapa !== filtros.etapa)
      || (filtros.cartera && (filtros.cartera === 'leads') !== (i.origen === 'lead'))
      || (filtros.analistaIds && (!i.creado_por || !filtros.analistaIds.includes(i.creado_por)))) return false
    claves.add(clave); anterior = { creado_en: i.creado_en, id: i.id, origen: i.origen }
  }
  return true
}
