// Gestión Diaria — contrato del REGISTRO CRUDO de actividad (Fase 1) y sus
// helpers puros. La fuente única es `crm.registro_actividad_fn` (migración
// 20260919211958): una página keyset (creado_en desc, id asc) de actividades de
// una ventana de días Lima, por analistas, tipos y etapa del lead. Aquí no se
// cuenta ni se decide nada de negocio: solo se valida la forma y se presenta.
import * as v from 'valibot'
import { ETAPA_INFO, TIPOS_ACTIVIDAD, type Actividad, type Etapa, type Miembro, type TipoActividad } from '@/lib/tipos'
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
  lead_id: v.string(),
  lead_nombre: v.string(),
  lead_etapa: v.string(),
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
  version: v.literal(1),
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
}

export interface FiltrosRegistro {
  /** Día Lima (YYYY-MM-DD). La Fase 1 lista un solo día. */
  dia: string
  /** null = todo lo visible por la RLS; el analista siempre manda el suyo. */
  analistaIds: readonly string[] | null
  pestana: PestanaRegistro
  etapa: Etapa | null
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
  return ultimo ? { antes_de: ultimo.creado_en, antes_id: ultimo.id } : null
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
  reunion_realizada: 'Cita realizada',
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
    .filter((a) => fechaLima(Date.parse(a.creado_en)) === filtros.dia)
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
    cabecera: ['Fecha', 'Hora (Lima)', 'Analista', 'Lead', 'Etapa entonces', 'Etapa actual', 'Tipo', 'Detalle', 'Resultado'],
    filas: items.map((i) => [
      fechaLima(Date.parse(i.creado_en)),
      horaDeItem(i),
      i.autor_nombre,
      i.lead_nombre,
      etiquetaEtapa(i.etapa_en_ese_momento),
      etiquetaEtapa(i.lead_etapa),
      ETIQUETA_CORTA[i.tipo],
      i.detalle,
      typeof i.metadata['resultado'] === 'string' ? (i.metadata['resultado'] as string) : null,
    ]),
  }
}
