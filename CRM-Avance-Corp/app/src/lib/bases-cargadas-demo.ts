// Espejo DEMO (sin red) de «Bases cargadas» (F5): las mismas puertas que el servidor, en memoria del navegador, para
// que la demo de Supervisión y Gerencia muestre la pestaña entera (hoja de bases, carga con informe, reparto, seguimiento
// y recoger). Vive mientras dure la pestaña del navegador; cada supervisor de la demo tiene sus bases. Reglas de
// juguete, solo para ver la pantalla: un teléfono que ya está en alguna base «ya existía»; los que terminan en 7 son
// clientes y en 13, «No contactar»; lo demás se carga sin repartir.
import { demoBaseEquipo } from './base-gestion'
import type { FuenteBases } from '@/data/bases-cargadas-fuente'
import { ErrorBases } from '@/data/bases-cargadas-api'
import {
  DIAS_SIN_TOCAR,
  MAX_REPARTO_CONTACTOS,
  type CifraSeguimiento,
  type ContactoBase,
  type FilaDetalleSeguimiento,
  type FilaSeguimientoBase,
  type FilaSeguimientoBases,
  type RespuestaCargarLote,
} from './bases-cargadas'
import type { Lead, Miembro } from './tipos'

const DIA_MS = 86_400_000

interface ContactoDemo {
  lead_id: string
  nombre_completo: string
  telefono: string
  distrito: string | null
  agregado_en: string
  analista_id: string | null
  analista_nombre: string | null
  asignado_en: string | null
  estado: string
  ultimo_intento_en: string | null
  ultimo_resultado: string | null
}

interface BaseDemo {
  base_id: string
  nombre: string
  origen: 'archivo' | 'crm'
  supervisor_id: string
  supervisor_nombre: string | null
  creado_en: string
  contactos: ContactoDemo[]
}

const NOMBRES = ['ROSA', 'LUIS', 'CARMEN', 'JORGE', 'ANA', 'MIGUEL', 'PATRICIA', 'CÉSAR', 'LUCÍA', 'RAÚL', 'GLADYS', 'VÍCTOR', 'ELENA', 'ANDRÉS', 'KAREN', 'FERNANDO']
const APELLIDOS = ['QUISPE', 'MENDOZA', 'TORRES', 'FLORES', 'RAMÍREZ', 'VARGAS', 'CASTRO', 'PAREDES', 'HUAMÁN', 'CHÁVEZ', 'SALAS', 'LEÓN', 'NÚÑEZ', 'PRADO', 'TAPIA', 'ROJAS']
const DISTRITOS = ['Surco', 'Miraflores', 'Los Olivos', 'San Miguel', 'Comas', 'La Molina', 'Lince', 'Ate']

/** Las bases de cada supervisor de la demo (por id de quien entra), en memoria. */
const bases = new Map<string, BaseDemo[]>()
let secuencia = 0

const pausa = (ms: number) => new Promise<void>((resolver) => { setTimeout(resolver, ms) })

function nombreDemo(i: number): string {
  return `${NOMBRES[i % NOMBRES.length]} ${APELLIDOS[(i * 7) % APELLIDOS.length]} ${APELLIDOS[(i * 3 + 5) % APELLIDOS.length]}`
}

/** Una base de muestra: `reparto` dice cuántos contactos de cada analista y en qué estado están. */
function baseMuestra(id: string, nombre: string, origen: 'archivo' | 'crm', supervisor: Miembro | { perfil_id: string; nombre_completo: string }, haceDias: number, sinRepartir: number,
  reparto: { analista: Miembro; estados: Record<string, number>; asignadoHace: number }[], ahora: number, semilla: number): BaseDemo {
  const contactos: ContactoDemo[] = []
  let n = semilla
  const nuevo = (analista: Miembro | null, estado: string, asignadoHace: number): ContactoDemo => {
    n += 1
    const trabajado = !['sin_repartir', 'sin_tocar'].includes(estado)
    return {
      lead_id: `demo-bc-${id}-${n}`, nombre_completo: nombreDemo(n), telefono: `+5199${String(1000000 + n * 7919).slice(-7)}`,
      distrito: DISTRITOS[n % DISTRITOS.length] ?? null, agregado_en: new Date(ahora - haceDias * DIA_MS).toISOString(),
      analista_id: analista?.perfil_id ?? null, analista_nombre: analista?.nombre_completo ?? null,
      asignado_en: analista ? new Date(ahora - asignadoHace * DIA_MS).toISOString() : null, estado,
      ultimo_intento_en: trabajado ? new Date(ahora - Math.max(0, asignadoHace - 1 - (n % 2)) * DIA_MS).toISOString() : null,
      ultimo_resultado: trabajado ? (estado === 'cita' ? 'agendo_reunion' : 'no_contesto') : null,
    }
  }
  for (let i = 0; i < sinRepartir; i += 1) contactos.push(nuevo(null, 'sin_repartir', 0))
  for (const r of reparto) for (const [estado, cantidad] of Object.entries(r.estados)) for (let i = 0; i < cantidad; i += 1) contactos.push(nuevo(r.analista, estado, r.asignadoHace))
  return { base_id: id, nombre, origen, supervisor_id: supervisor.perfil_id, supervisor_nombre: supervisor.nombre_completo, creado_en: new Date(ahora - haceDias * DIA_MS).toISOString(), contactos }
}

function analistasDe(equipo: readonly Miembro[], yo: { id: string; rol: string }): Miembro[] {
  return equipo
    .filter((m) => m.activo && m.rol_crm === 'vendedor' && (yo.rol === 'gerencia' || m.supervisor_id === yo.id))
    .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es'))
}

function semillaDe(equipo: readonly Miembro[], yo: { id: string; rol: string; nombre_completo?: string }, ahora: number): BaseDemo[] {
  const analistas = analistasDe(equipo, yo)
  const supervisor = yo.rol === 'gerencia'
    ? equipo.find((m) => m.activo && m.rol_crm === 'supervisor') ?? { perfil_id: yo.id, nombre_completo: yo.nombre_completo ?? 'SUPERVISOR' }
    : { perfil_id: yo.id, nombre_completo: equipo.find((m) => m.perfil_id === yo.id)?.nombre_completo ?? yo.nombre_completo ?? 'SUPERVISOR' }
  const [a, b] = [analistas[0], analistas[1] ?? analistas[0]]
  if (!a || !b) return []
  return [
    baseMuestra('feria-2025', 'Feria 2025', 'archivo', supervisor, 6, 85, [
      { analista: a, estados: { sin_tocar: 12, trabajado: 18, en_descanso: 4, cita: 3, reactivado: 2, movido_otra_via: 1 }, asignadoHace: 5 },
      { analista: b, estados: { sin_tocar: 14, trabajado: 9, cita: 1 }, asignadoHace: 1 },
    ], ahora, 0),
    baseMuestra('descartes-julio', 'Descartes de julio', 'crm', supervisor, 12, 0, [
      { analista: b, estados: { trabajado: 16, en_descanso: 6, cita: 2, reactivado: 3 }, asignadoHace: 10 },
      { analista: a, estados: { sin_tocar: 5, trabajado: 10 }, asignadoHace: 4 },
    ], ahora, 500),
  ]
}

const cuenta = (contactos: readonly ContactoDemo[], cifra: CifraSeguimiento, ahora: number): ContactoDemo[] => contactos.filter((c) => {
  const repartido = c.analista_id !== null
  switch (cifra) {
    case 'total': return true
    case 'sin_repartir': return !repartido
    case 'repartidos': case 'asignados': return repartido
    case 'sin_tocar': return repartido && c.estado === 'sin_tocar'
    case 'sin_tocar_3_dias': return repartido && c.estado === 'sin_tocar' && c.asignado_en !== null && ahora - Date.parse(c.asignado_en) >= DIAS_SIN_TOCAR * DIA_MS
    case 'trabajados': return repartido && c.ultimo_intento_en !== null
    case 'en_descanso': return c.estado === 'en_descanso'
    case 'citas': return c.estado === 'cita'
    case 'reactivados': return c.estado === 'reactivado'
    case 'movidos_otra_via': return c.estado === 'movido_otra_via'
    case 'retirados': return c.estado === 'retirado'
    case 'no_contactar': return c.estado === 'no_contactar'
  }
})

function filaBases(b: BaseDemo, ahora: number): FilaSeguimientoBases {
  const n = (cifra: CifraSeguimiento) => cuenta(b.contactos, cifra, ahora).length
  const repartidos = n('repartidos')
  return {
    base_id: b.base_id, nombre: b.nombre, origen: b.origen, supervisor_id: b.supervisor_id, supervisor_nombre: b.supervisor_nombre,
    creado_en: b.creado_en, total: n('total'), sin_repartir: n('sin_repartir'), repartidos, sin_tocar: n('sin_tocar'),
    trabajados: n('trabajados'), en_descanso: n('en_descanso'), citas: n('citas'), reactivados: n('reactivados'),
    avance: repartidos > 0 ? n('trabajados') / repartidos : null,
    movidos_otra_via: n('movidos_otra_via'), retirados: n('retirados'), no_contactar: n('no_contactar'),
  }
}

function errorDemo(mensaje: string, code = 'REGLA_SERVIDOR', detalle: unknown = null): ErrorBases {
  return new ErrorBases(mensaje, code, detalle)
}

/**
 * Las puertas de «Bases» para la demo de `yo`. Los analistas salen del organigrama de la demo; «Armar desde el CRM» usa
 * la misma base del equipo que «Gestión de la base» (lo que tiene seguimiento activo queda fuera, como en el servidor).
 */
export function crearFuenteDemoBases(contexto: { leads: readonly Lead[]; equipo: readonly Miembro[]; yo: { id: string; rol: string; nombre_completo?: string } }): FuenteBases {
  const { leads, equipo, yo } = contexto
  const mias = (): BaseDemo[] => {
    let lista = bases.get(yo.id)
    if (!lista) { lista = semillaDe(equipo, yo, Date.now()); bases.set(yo.id, lista) }
    return lista
  }
  const base = (baseId: string): BaseDemo => {
    const b = mias().find((x) => x.base_id === baseId)
    if (!b) throw errorDemo('Base no encontrada o fuera de tu ámbito', 'FUERA_DE_AMBITO')
    return b
  }
  const analista = (id: string) => equipo.find((m) => m.perfil_id === id && m.rol_crm === 'vendedor' && m.activo)
  const nuevaBase = (nombre: string, origen: 'archivo' | 'crm', supervisorId: string | null | undefined): BaseDemo => {
    const limpio = nombre.trim()
    if (mias().some((b) => b.nombre.toLowerCase() === limpio.toLowerCase())) throw errorDemo('Ya hay una base viva con ese nombre en la bandeja de ese supervisor', 'NOMBRE_REPETIDO')
    const supervisor = equipo.find((m) => m.perfil_id === (supervisorId ?? yo.id))
    secuencia += 1
    const nueva: BaseDemo = {
      base_id: `demo-nueva-${secuencia}`, nombre: limpio, origen, supervisor_id: supervisorId ?? yo.id,
      supervisor_nombre: supervisor?.nombre_completo ?? yo.nombre_completo ?? null, creado_en: new Date().toISOString(), contactos: [],
    }
    mias().unshift(nueva)
    return nueva
  }

  return {
    async seguimientoBases() {
      await pausa(150)
      const ahora = Date.now()
      return mias().map((b) => filaBases(b, ahora))
    },
    async seguimientoBase(baseId) {
      await pausa(100)
      const ahora = Date.now()
      const porAnalista = new Map<string, ContactoDemo[]>()
      for (const c of base(baseId).contactos) if (c.analista_id) porAnalista.set(c.analista_id, [...(porAnalista.get(c.analista_id) ?? []), c])
      return [...porAnalista.values()].map((cs): FilaSeguimientoBase => {
        const n = (cifra: CifraSeguimiento) => cuenta(cs, cifra, ahora).length
        const ultimo = cs.map((c) => c.ultimo_intento_en).filter((x): x is string => x !== null).sort().at(-1) ?? null
        return {
          analista_id: cs[0]?.analista_id ?? '', analista_nombre: cs[0]?.analista_nombre ?? null, asignados: n('asignados'),
          sin_tocar: n('sin_tocar'), sin_tocar_3_dias: n('sin_tocar_3_dias'), trabajados: n('trabajados'), en_descanso: n('en_descanso'),
          citas: n('citas'), reactivados: n('reactivados'), ultimo_intento_en: ultimo, movidos_otra_via: n('movidos_otra_via'),
          retirados: n('retirados'), no_contactar: n('no_contactar'),
        }
      }).sort((x, y) => (x.analista_nombre ?? '').localeCompare(y.analista_nombre ?? '', 'es'))
    },
    async seguimientoBaseDetalle(baseId, analistaId, cifra) {
      await pausa(100)
      const ahora = Date.now()
      return cuenta(base(baseId).contactos.filter((c) => analistaId === null || c.analista_id === analistaId), cifra, ahora)
        .map((c): FilaDetalleSeguimiento => ({
          lead_id: c.lead_id, nombre_completo: c.nombre_completo, estado: c.estado, asignado_en: c.asignado_en,
          ultimo_intento_en: c.ultimo_intento_en, ultimo_resultado: c.ultimo_resultado,
        }))
    },
    async contactosDeBase(baseId, estado) {
      await pausa(100)
      return base(baseId).contactos
        .filter((c) => estado === 'todos' || (estado === 'sin_repartir' ? c.analista_id === null : c.analista_id !== null))
        .map((c): ContactoBase => ({
          lead_id: c.lead_id, nombre_completo: c.nombre_completo, telefono: c.telefono, distrito: c.distrito, agregado_en: c.agregado_en,
          analista_id: c.analista_id, analista_nombre: c.analista_nombre, estado: c.estado,
        }))
    },
    async crearBase(entrada) {
      await pausa(200)
      const b = nuevaBase(entrada.nombre, 'archivo', entrada.supervisorId)
      return { ok: true as const, base_id: b.base_id, supervisor_id: b.supervisor_id }
    },
    async cargarBaseLote({ baseId, filas }) {
      await pausa(180)
      const b = base(baseId)
      const telefonos = new Map<string, string>()
      for (const otra of mias()) for (const c of otra.contactos) telefonos.set(c.telefono, otra.base_id)
      const conteo = { cargadas: 0, ya_existian: 0, no_contactar: 0, invalidas: 0, repetidas: 0 }
      const veredictos: RespuestaCargarLote['filas'] = filas.map((f) => {
        const enBase = telefonos.get(f.telefono)
        if (enBase === baseId) { conteo.repetidas += 1; return { fila: f.fila, veredicto: 'repetida', motivo: 'en_base', lead_id: null } }
        if (enBase || f.telefono.endsWith('7')) { conteo.ya_existian += 1; return { fila: f.fila, veredicto: 'ya_existia', motivo: enBase ? 'descartado' : 'cliente', lead_id: null } }
        if (f.telefono.endsWith('13')) { conteo.no_contactar += 1; return { fila: f.fila, veredicto: 'no_contactar', motivo: 'no_insistir', lead_id: null } }
        conteo.cargadas += 1
        telefonos.set(f.telefono, baseId)
        b.contactos.push({
          lead_id: `demo-cargado-${baseId}-${f.fila}`, nombre_completo: f.nombre.toUpperCase(), telefono: f.telefono, distrito: f.distrito ?? null,
          agregado_en: new Date().toISOString(), analista_id: null, analista_nombre: null, asignado_en: null, estado: 'sin_repartir',
          ultimo_intento_en: null, ultimo_resultado: null,
        })
        return { fila: f.fila, veredicto: 'cargada', motivo: null, lead_id: null }
      })
      return {
        ok: true as const, base_id: baseId, lote: conteo,
        base: { filas_recibidas: b.contactos.length, cargadas: b.contactos.length }, filas: veredictos,
      }
    },
    async armarBaseCrm(entrada) {
      await pausa(300)
      const candidatas = new Map(demoBaseEquipo(leads, equipo, yo).filas.map((f) => [f.lead_id, f]))
      const enOtraBase = new Set(mias().flatMap((b) => b.contactos.map((c) => c.lead_id)))
      const ahora = Date.now()
      const porMotivo: Record<string, number[]> = {}
      const incluidos: string[] = []
      entrada.leadIds.forEach((id, i) => {
        const f = candidatas.get(id)
        // B6: un intento de los últimos 7 días o una rellamada vigente = seguimiento activo: no entra.
        const enGestion = f && ((f.ultimo_intento_en && ahora - Date.parse(f.ultimo_intento_en) <= 7 * DIA_MS) || (f.proxima_llamada_en && Date.parse(f.proxima_llamada_en) >= ahora))
        const motivo = !f ? 'no_encontrado' : f.no_contactar ? 'no_contactar' : enOtraBase.has(id) ? 'en_otra_base' : enGestion ? 'en_gestion' : incluidos.includes(id) ? 'repetido' : null
        if (motivo) porMotivo[motivo] = [...(porMotivo[motivo] ?? []), i + 1]
        else incluidos.push(id)
      })
      if (incluidos.length === 0) throw errorDemo('Ningún lead de la lista es elegible: no se crea la base', 'SIN_ELEGIBLES', porMotivo)
      const b = nuevaBase(entrada.nombre, 'crm', entrada.supervisorId)
      for (const id of incluidos) {
        const f = candidatas.get(id)
        b.contactos.push({
          lead_id: id, nombre_completo: f?.nombre_completo ?? id, telefono: f?.telefono ?? '', distrito: f?.distrito ?? null,
          agregado_en: new Date().toISOString(), analista_id: null, analista_nombre: null, asignado_en: null, estado: 'sin_repartir',
          ultimo_intento_en: null, ultimo_resultado: null,
        })
      }
      return {
        ok: true as const, base_id: b.base_id, recibidos: entrada.leadIds.length, incluidos: incluidos.length,
        excluidos: entrada.leadIds.length - incluidos.length, excluidos_por_motivo: porMotivo,
        excluidos_detalle: Object.entries(porMotivo).flatMap(([motivo, pos]) => pos.map((p) => ({ posicion: p, lead_id: entrada.leadIds[p - 1] ?? null, motivo }))),
      }
    },
    async repartirBase({ baseId, reparto }) {
      await pausa(250)
      const b = base(baseId)
      const ahora = new Date().toISOString()
      const asignar = (c: ContactoDemo, analistaId: string) => {
        const a = analista(analistaId)
        if (!a) throw errorDemo('El analista no está activo o no es de tu equipo')
        Object.assign(c, { analista_id: a.perfil_id, analista_nombre: a.nombre_completo, asignado_en: ahora, estado: 'sin_tocar' })
      }
      const pedidosTotal = reparto.modo === 'bloque' ? reparto.asignaciones.reduce((s, x) => s + x.cantidad, 0) : reparto.asignaciones.length
      if (pedidosTotal > MAX_REPARTO_CONTACTOS) throw errorDemo(`Un reparto mueve hasta ${MAX_REPARTO_CONTACTOS} contactos por operación (este pide ${pedidosTotal})`)
      if (reparto.modo === 'bloque') {
        const libres = b.contactos.filter((c) => c.analista_id === null)
        const pedidos = reparto.asignaciones.reduce((s, x) => s + x.cantidad, 0)
        if (pedidos > libres.length) throw errorDemo('No alcanzan los contactos disponibles', 'SIN_DISPONIBLES', libres.length)
        let i = 0
        for (const x of reparto.asignaciones) for (let k = 0; k < x.cantidad; k += 1) { const c = libres[i++]; if (c) asignar(c, x.analista_id) }
        return { repartidos: pedidos, por_analista: reparto.asignaciones.map((x) => ({ analista_id: x.analista_id, cantidad: x.cantidad })), omitidos: [] }
      }
      // Como el servidor: el que ya es de ese analista sale «omitido» (ya_asignado); los demás se asignan.
      const omitidos: { lead_id: string; motivo: string; cantidad: number }[] = []
      for (const x of reparto.asignaciones) {
        const c = b.contactos.find((y) => y.lead_id === x.lead_id)
        if (!c) continue
        if (c.analista_id === x.analista_id) omitidos.push({ lead_id: c.lead_id, motivo: 'ya_asignado', cantidad: 1 })
        else asignar(c, x.analista_id)
      }
      return { repartidos: reparto.asignaciones.length - omitidos.length, por_analista: [], omitidos }
    },
    async recogerDeBase({ baseId, analistaId }) {
      await pausa(200)
      const deEl = base(baseId).contactos.filter((c) => c.analista_id === analistaId)
      const sinTocar = deEl.filter((c) => c.estado === 'sin_tocar')
      for (const c of sinTocar) Object.assign(c, { analista_id: null, analista_nombre: null, asignado_en: null, estado: 'sin_repartir' })
      return { recogidos: sinTocar.length, omitidos: deEl.length - sinTocar.length, pendientes: 0 }
    },
  }
}

/** Solo para las pruebas: vuelve a la semilla. */
export function reiniciarDemoBases(): void {
  bases.clear()
  secuencia = 0
}
