// Demo de «Llamadas del celular» (F4-b): las llamadas de C1 de ANALISTA UNO (d-v1) con leads de su cartera demo
// (lib/demo.ts). Sintéticas y relativas a «ahora», como el resto de la demo. Las mismas situaciones del prototipo que
// le gustó a Miguel: pide resultado, ambigua, la que llegó tarde (sin señal) y lo resuelto hoy.
import type { FilaBandeja, ResueltaHoy } from './llamadas-celular'

const MIN = 60_000
const iso = (ms: number) => new Date(ms).toISOString()

export function demoPendientesCelular(ahora: number): FilaBandeja[] {
  const fila = (id: string, haceMin: number, extra: Partial<FilaBandeja>): FilaBandeja => ({
    evento_id: `demo-llamada-${id}`, evento_origen_id: `C1-${Math.floor((ahora - haceMin * MIN) / 1000)}`,
    recibido_en: iso(ahora - haceMin * MIN + 11_000), ocurrio_en: iso(ahora - haceMin * MIN),
    numero: null, direccion: 'saliente', estado_tecnico: 'conectada', duracion_seg: 95, identificacion: 'identificado',
    atencion: 'requiere_resultado', lead_id: null, lead_nombre: null, analista_id: 'd-v1', es_propia: true, ...extra,
  })
  return [
    fila('maria', 16, { numero: '+51987654322', lead_id: 'l2', lead_nombre: 'MARÍA LÓPEZ CASTRO' }),
    fila('fernando', 40, { numero: '+51922334455', lead_id: 'l16', lead_nombre: 'FERNANDO QUIROZ BEDOYA', duracion_seg: 210 }),
    fila('ambigua', 63, { numero: '+51987654330', identificacion: 'ambiguo', atencion: 'por_revisar', duracion_seg: 30 }),
    // Llamó ayer en la tarde y el aviso llegó esta mañana: el celular estuvo sin señal.
    { ...fila('gloria', 16 * 60, { numero: '+51933445566', lead_id: 'l17', lead_nombre: 'GLORIA NAVARRO IBÁÑEZ', duracion_seg: 340 }),
      recibido_en: iso(ahora - 3 * 60 * MIN) },
  ]
}

export function demoResueltasHoyCelular(ahora: number): ResueltaHoy[] {
  const resuelta = (id: string, haceMin: number, extra: Partial<ResueltaHoy>): ResueltaHoy => ({
    evento_id: `demo-llamada-${id}`, recibido_en: iso(ahora - haceMin * MIN + 11_000), ocurrio_en: iso(ahora - haceMin * MIN),
    resuelto_en: iso(ahora - (haceMin - 4) * MIN),
    numero: null, atencion: 'registrado', lead_id: null, lead_nombre: null, analista_id: 'd-v1', es_propia: true,
    etiqueta: 'C1', actividad_id: null, resultado: null, deshecho: false, via: null, motivo_descarte: null,
    motivo_descarte_detalle: null, ...extra,
  })
  return [
    // Hallazgo de P9 (F4-d): guardó un resultado y lo deshizo; la fila ofrece «Registrar el corregido».
    resuelta('juan-deshecho', 60, { evento_origen_id: `C1-${Math.floor((ahora - 60 * MIN) / 1000)}`, numero: '+51987654321',
      lead_id: 'l1', lead_nombre: 'JUAN PÉREZ ROJAS', actividad_id: 'demo-act-juan-deshecho', resultado: 'no_contesto',
      deshecho: true, via: 'al_colgar' }),
    resuelta('teresa', 90, { numero: '+51911223344', lead_id: 'l15', lead_nombre: 'TERESA GONZALES PAZ',
      actividad_id: 'demo-act-teresa', resultado: 'agendo_reunion', via: 'al_colgar' }),
    resuelta('juan', 110, { numero: '+51987654321', lead_id: 'l1', lead_nombre: 'JUAN PÉREZ ROJAS',
      actividad_id: 'demo-act-juan', resultado: 'no_contesto', via: 'al_colgar' }),
    // Con la política de hoy un número sin lead no se guarda: lo descartado es una llamada a un lead que no era de trabajo.
    resuelta('patricia', 150, { numero: '+51954321876', lead_id: 'l12', lead_nombre: 'PATRICIA FERNÁNDEZ SOTO',
      atencion: 'descartado_con_motivo', motivo_descarte: 'personal' }),
  ]
}
