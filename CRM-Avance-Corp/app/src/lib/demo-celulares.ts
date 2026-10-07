// Demo de «Celulares» (F4-c): los celulares de las personas de la demo (lib/demo-config.ts), con los seis estados de
// salud del prototipo aprobado el 06/10. Sintético y relativo a «ahora». La clave de la demo empieza por «demo» para
// que nadie la confunda con una real (decisión D2); en la base real son 64 hexadecimales.
import type { AsignacionCelular, CelularSalud } from './celulares'
import { catalogoUsuariosAdministrablesDemo } from './demo-config'

const HORA = 3_600_000
const DIA = 24 * HORA
const iso = (ms: number) => new Date(ms).toISOString()

export interface DemoCelulares {
  vigentes: CelularSalud[]
  asignaciones: AsignacionCelular[]
  /** Quién puede recibir un celular en la demo: analistas y supervisores activos. */
  catalogo: { id: string; nombre: string }[]
}

export function demoClaveCelular(): string {
  const hex = '0123456789abcdef'
  let clave = 'demo'
  for (let i = 0; i < 60; i++) clave += hex[Math.floor(Math.random() * 16)]
  return clave
}

export function demoCelulares(ahora: number): DemoCelulares {
  const personas = catalogoUsuariosAdministrablesDemo()
  const porNombre = (nombre: string) => personas.find((p) => p.nombre_completo === nombre)
  const id = (nombre: string) => porNombre(nombre)?.perfil_id ?? `demo-${nombre.toLowerCase().replace(/\s+/g, '-')}`
  const fila = (n: number, nombre: string, desdeDias: number, extra: Partial<CelularSalud>): CelularSalud => ({
    asignacion_id: `demo-asig-C${n}`, etiqueta: `C${n}`, analista_id: id(nombre), analista_nombre: nombre,
    vigente_desde: iso(ahora - desdeDias * DIA), estado_latido: 'al_dia', horas_sin_latido: 0, reloj_desfasado: false,
    version_macro: 'llamadas-v3', eventos_en_cola: 0, ...extra,
  })
  const vigentes: CelularSalud[] = [
    fila(1, 'ANA TORRES', 0, {}),
    fila(2, 'BRUNO DÍAZ', 0, { estado_latido: 'sin_latido', horas_sin_latido: 9, eventos_en_cola: 3 }),
    // Recién asignado: todavía no pegaron la clave en MacroDroid.
    fila(3, 'MARÍA SALAZAR', 0, { estado_latido: 'nunca', horas_sin_latido: null, version_macro: null, eventos_en_cola: null }),
    fila(4, 'DIEGO RAMOS', 4, { reloj_desfasado: true, version_macro: 'llamadas-v2' }),
    // Lucía no tiene rol en el CRM: la tarjeta la muestra como «Analista de baja» y no deja rotar.
    fila(5, 'LUCÍA PAREDES', 6, { estado_latido: 'sin_latido', horas_sin_latido: 31, eventos_en_cola: 12 }),
  ]
  const cerrada = (n: number, nombre: string, desdeDias: number, hastaDias: number, motivo: string): AsignacionCelular => ({
    asignacion_id: `demo-asig-C${n}-cerrada-${hastaDias}`, etiqueta: `C${n}`, analista_id: id(nombre), analista_nombre: nombre,
    vigente_desde: iso(ahora - desdeDias * DIA), vigente_hasta: iso(ahora - hastaDias * DIA), motivo_cierre: motivo,
  })
  const asignaciones: AsignacionCelular[] = [
    ...vigentes.map((c) => ({
      asignacion_id: c.asignacion_id, etiqueta: c.etiqueta, analista_id: c.analista_id, analista_nombre: c.analista_nombre,
      vigente_desde: c.vigente_desde, vigente_hasta: null, motivo_cierre: null,
    })),
    cerrada(1, 'ANA TORRES', 8, 0, 'rotacion'),
    cerrada(2, 'CARLA MENDOZA', 6, 1, 'baja_analista'),
  ]
  const catalogo = personas
    .filter((p) => p.activo_crm === true && (p.rol_crm === 'vendedor' || p.rol_crm === 'supervisor'))
    .map((p) => ({ id: p.perfil_id, nombre: p.nombre_completo }))
  return { vigentes, asignaciones, catalogo }
}
