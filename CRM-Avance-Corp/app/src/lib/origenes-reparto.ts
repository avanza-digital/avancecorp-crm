import { turnoDeOrigen, type OrigenEntregasReparto, type EntregaAgendaReparto } from './tipos'

const esConteo = (n: number) => Number.isSafeInteger(n) && n >= 0

/** El desglose debe explicar exactamente los totales, también por destino. */
export function origenesRepartoCoherentes(asignacion: {
  origen?: 'landing' | 'formulario' | undefined
  derivados: number
  fuera_turno?: number | undefined
  entregas?: EntregaAgendaReparto[] | undefined
  origenes?: OrigenEntregasReparto[] | undefined
}): boolean {
  if (asignacion.origenes === undefined) return true // Contrato anterior, sin desglose de origen.
  if (asignacion.entregas === undefined || asignacion.fuera_turno === undefined) return false
  if (!esConteo(asignacion.derivados) || !esConteo(asignacion.fuera_turno)) return false

  const agrupar = (entregas: EntregaAgendaReparto[]) => {
    const resultado = new Map<string | null, number>()
    for (const entrega of entregas) {
      if (!esConteo(entrega.derivados) || resultado.has(entrega.supervisor_id)) return null
      resultado.set(entrega.supervisor_id, entrega.derivados)
    }
    return resultado
  }
  const destinos = agrupar(asignacion.entregas)
  if (!destinos) return false
  const grupos = new Set<string>()
  const sumas = new Map<string | null, number>()
  let derivados = 0
  let fueraTurno = 0
  for (const grupo of asignacion.origenes) {
    if (asignacion.origen !== undefined && turnoDeOrigen(grupo.origen) !== asignacion.origen) return false
    if (grupos.has(grupo.origen) || !esConteo(grupo.derivados) || (grupo.fuera_turno === null || !esConteo(grupo.fuera_turno))) return false
    grupos.add(grupo.origen)
    const detalles = agrupar(grupo.entregas)
    if (!detalles) return false
    let total = 0
    let fuera = 0
    for (const entrega of grupo.entregas) {
      const original = asignacion.entregas.find((fila) => fila.supervisor_id === entrega.supervisor_id)
      if (!original || original.coincide_turno !== entrega.coincide_turno
        || original.supervisor_nombre !== entrega.supervisor_nombre
        || original.supervisor_alias !== entrega.supervisor_alias) return false
      total += entrega.derivados
      if (!entrega.coincide_turno) fuera += entrega.derivados
      sumas.set(entrega.supervisor_id, (sumas.get(entrega.supervisor_id) ?? 0) + entrega.derivados)
    }
    if (total !== grupo.derivados || fuera !== grupo.fuera_turno) return false
    derivados += total
    fueraTurno += fuera
  }
  return derivados === asignacion.derivados && fueraTurno === asignacion.fuera_turno
    && destinos.size === sumas.size
    && [...destinos].every(([destino, n]) => sumas.get(destino) === n)
}

/** La tabla diaria y los dos turnos deben describir las mismas entregas. */
export function diaRepartoCoherente(dia: {
  asignaciones: (Parameters<typeof origenesRepartoCoherentes>[0] & { origen: 'landing' | 'formulario' })[]
  origenes?: OrigenEntregasReparto[] | undefined
}): boolean {
  if (!dia.asignaciones.every(origenesRepartoCoherentes)) return false
  if (dia.origenes === undefined) return true
  const vistos = new Set<string>()
  for (const grupo of dia.origenes) {
    const turno = turnoDeOrigen(grupo.origen)
    if (vistos.has(grupo.origen) || grupo.turno !== turno || !esConteo(grupo.derivados)) return false
    vistos.add(grupo.origen)
    const destinos = new Set<string | null>()
    let total = 0
    let fuera = 0
    for (const entrega of grupo.entregas) {
      if (destinos.has(entrega.supervisor_id) || !esConteo(entrega.derivados)) return false
      destinos.add(entrega.supervisor_id)
      total += entrega.derivados
      if (!entrega.coincide_turno) fuera += entrega.derivados
    }
    if (total !== grupo.derivados || grupo.fuera_turno !== (turno === null ? null : fuera)) return false
  }
  for (const turno of ['landing', 'formulario'] as const) {
    const asignaciones = dia.asignaciones.filter((a) => a.origen === turno)
    if (asignaciones.length !== 1) return false
    const asignacion = asignaciones[0]!
    const grupos = dia.origenes.filter((g) => g.turno === turno)
    if (!origenesRepartoCoherentes({ ...asignacion, origenes: grupos })) return false
    if (asignacion.origenes === undefined || asignacion.origenes.length !== grupos.length) return false
    for (const grupo of grupos) {
      const anidado = asignacion.origenes.find((g) => g.origen === grupo.origen)
      if (!anidado || anidado.derivados !== grupo.derivados || anidado.fuera_turno !== grupo.fuera_turno
        || anidado.entregas.length !== grupo.entregas.length
        || !grupo.entregas.every((e) => anidado.entregas.some((a) => a.supervisor_id === e.supervisor_id
          && a.supervisor_nombre === e.supervisor_nombre && a.supervisor_alias === e.supervisor_alias
          && a.derivados === e.derivados && a.coincide_turno === e.coincide_turno))) return false
    }
  }
  return true
}
