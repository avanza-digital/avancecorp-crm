// Demo de F4-e: «la operación de hoy» del celular para la gerencia y el supervisor de ejemplo, armada con el MISMO
// organigrama del store (lib/demo.ts: d-sup1 con d-v1 y d-v2; d-sup2 con d-v3) y la misma forma que devuelve
// `crm.llamadas_celular_operacion_hoy_fn`. Es un espejo, no una segunda verdad: lo calculado pasa por el mismo
// esquema que la respuesta real, con sus sumas, así que si no cuadra se oculta como un fallo. Las situaciones son las
// del prototipo aprobado el 06/10: un celular al día con trabajo, uno sin latido con avisos en cola y uno que nunca
// habló (sin dato).
import { fechaLima } from './agenda-derivada'
import { VERSION_MACRO_VIGENTE } from './celulares'
import {
  claveEquipoCelular, sumarCelulares, sumarCifras,
  type AnalistaCelular, type CelularOperacion, type CifrasCelular, type EquipoCelular, type OperacionCelularHoy,
} from './llamadas-celular-operacion'
import type { Miembro, Yo } from './tipos'

const DIAS_RETENCION = 30
const SIN_CIFRAS: CifrasCelular = {
  llamadas_hoy: { total: 0, con_resultado: 0, deshechas_sin_corregir: 0, sin_resultado: 0, cerradas_despues: 0, descartadas: 0, por_revisar: 0, requiere_devolucion: 0 },
  resultados_hoy: { total: 0, al_colgar: 0, desde_pestana: 0, a_mano: 0 },
  pendientes: { total: 0, de_hoy: 0, anteriores: 0, mas_antigua_dias: null, deshechas_sin_corregir: 0 },
  por_revisar: 0,
}
const alDia = (etiqueta: string): CelularOperacion =>
  ({ etiqueta, estado_latido: 'al_dia', horas_sin_latido: 0, reloj_desfasado: false, eventos_en_cola: 0, version_macro: VERSION_MACRO_VIGENTE })

/** Las cifras de cada analista de la demo. Quien no está aquí tiene 0 llamadas y ningún celular: «sin dato». */
const CIFRAS_DEMO: Record<string, { cifras: CifrasCelular; celulares: CelularOperacion[] }> = {
  // ANALISTA UNO: C1 al día; 8 llamadas detectadas, 1 sin resultado de hoy y 1 de ayer, 1 ambigua por revisar y una
  // que deshizo y no corrigió (hallazgo de P9).
  'd-v1': {
    cifras: {
      llamadas_hoy: { total: 8, con_resultado: 5, deshechas_sin_corregir: 1, sin_resultado: 1, cerradas_despues: 0, descartadas: 0, por_revisar: 1, requiere_devolucion: 0 },
      resultados_hoy: { total: 7, al_colgar: 5, desde_pestana: 1, a_mano: 1 },
      pendientes: { total: 2, de_hoy: 1, anteriores: 1, mas_antigua_dias: 1, deshechas_sin_corregir: 1 },
      por_revisar: 1,
    },
    celulares: [alDia('C1')],
  },
  // ANALISTA DOS: C2 sin latido desde hace 9 h con 3 avisos en cola; 6 llamadas, 2 sin resultado de hoy, 1 descartada.
  'd-v2': {
    cifras: {
      llamadas_hoy: { total: 6, con_resultado: 3, deshechas_sin_corregir: 0, sin_resultado: 2, cerradas_despues: 0, descartadas: 1, por_revisar: 0, requiere_devolucion: 0 },
      resultados_hoy: { total: 4, al_colgar: 3, desde_pestana: 1, a_mano: 0 },
      pendientes: { total: 2, de_hoy: 2, anteriores: 0, mas_antigua_dias: 0, deshechas_sin_corregir: 0 },
      por_revisar: 0,
    },
    celulares: [{ etiqueta: 'C2', estado_latido: 'sin_latido', horas_sin_latido: 9, reloj_desfasado: false, eventos_en_cola: 3, version_macro: VERSION_MACRO_VIGENTE }],
  },
  // ANALISTA TRES: C3 recién asignado, nunca habló → 0 llamadas y «sin dato» (D1).
  'd-v3': {
    cifras: SIN_CIFRAS,
    celulares: [{ etiqueta: 'C3', estado_latido: 'nunca', horas_sin_latido: null, reloj_desfasado: false, eventos_en_cola: null, version_macro: null }],
  },
}
/** El celular del supervisor de ejemplo (A7): fuera de la tabla y sin sumar al equipo. */
const SU_CELULAR_DEMO: Record<string, CelularOperacion[]> = { 'd-sup1': [alDia('C4')] }

/**
 * La operación de hoy como la vería `rol` (gerencia: toda la operación con el roster; supervisor: su subárbol). Los
 * analistas son los vendedores activos del organigrama del store; el equipo es su supervisor activo o «fuera».
 */
export function operacionCelularDesdeDemo(miembros: readonly Miembro[], ahora: number, actorId: string, rol: Yo['rol']): OperacionCelularHoy {
  const porId = new Map(miembros.map((m) => [m.perfil_id, m]))
  const supervisorActivo = (id: string | null) => id !== null && porId.get(id)?.rol_crm === 'supervisor' && porId.get(id)?.activo === true ? id : null
  const vendedores = miembros.filter((m) => m.rol_crm === 'vendedor' && m.activo)
    .map((m) => ({ m, supervisor_id: supervisorActivo(m.supervisor_id ?? null) }))
    .filter((x) => rol !== 'supervisor' || x.supervisor_id === actorId)
  const analistas: AnalistaCelular[] = vendedores.map(({ m, supervisor_id }) => {
    const d = CIFRAS_DEMO[m.perfil_id] ?? { cifras: SIN_CIFRAS, celulares: [] }
    return { ...d.cifras, analista_id: m.perfil_id, nombre: m.nombre_completo, supervisor_id,
      sin_dato: d.cifras.llamadas_hoy.total === 0 && !d.celulares.some((c) => c.estado_latido === 'al_dia'), celulares: d.celulares }
  }).toSorted((a, b) => a.nombre.localeCompare(b.nombre, 'es') || a.analista_id.localeCompare(b.analista_id))
  const claves = [...new Set(analistas.map((a) => a.supervisor_id))]
  const equipos: EquipoCelular[] = claves.map((supervisor_id) => {
    const suyos = analistas.filter((a) => a.supervisor_id === supervisor_id)
    return { ...sumarCifras(suyos), ...sumarCelulares(suyos), supervisor_id,
      supervisor_nombre: supervisor_id === null ? 'Sin supervisor' : porId.get(supervisor_id)?.nombre_completo ?? 'Sin supervisor', analistas: suyos.length }
  }).toSorted((a, b) => a.supervisor_nombre.localeCompare(b.supervisor_nombre, 'es') || claveEquipoCelular(a.supervisor_id).localeCompare(claveEquipoCelular(b.supervisor_id)))
  return {
    dia: fechaLima(ahora), generado_en: new Date(ahora).toISOString(), alcance: rol === 'supervisor' ? 'equipo' : 'operacion',
    rotulos: {
      llamadas_hoy: 'Llamadas de hoy (por la hora de la llamada)',
      resultados_hoy: 'Resultados registrados hoy (de llamadas de cualquier día)',
      pendientes: `Sin resultado ahora (hasta ${DIAS_RETENCION} días)`,
    },
    totales: { ...sumarCifras(analistas), ...sumarCelulares(analistas) },
    equipos, analistas,
    su_celular: rol === 'supervisor' ? SU_CELULAR_DEMO[actorId] ?? [] : null,
  }
}
