import type { Moneda } from '@/lib/format'
import { CORTE } from '../../../prototypes/citas-assets/model.mjs'
import { CITAS_CRM, seguimientoInasistencias, type CitaConLead, type Recuperacion } from './datos'

/** Movimientos ficticios: no se deducen de cerrado ni del monto estimado de la cita. */
export interface DepositoEjemplo {
  id: string
  leadId: string
  monto: number
  moneda: Moneda
  depositadoEn: string
  confirmadoEn: string | null
  anuladoEn?: string
}

export const DEPOSITOS_EJEMPLO: DepositoEjemplo[] = [
  { id: 'DEP-001', leadId: 'L-031', monto: 35000, moneda: 'PEN', depositadoEn: '2026-09-04T10:00:00-05:00', confirmadoEn: '2026-09-04T10:05:00-05:00' },
  { id: 'DEP-002', leadId: 'L-032', monto: 5000, moneda: 'USD', depositadoEn: '2026-09-04T12:00:00-05:00', confirmadoEn: '2026-09-04T12:10:00-05:00' },
  { id: 'DEP-003', leadId: 'L-029', monto: 50000, moneda: 'PEN', depositadoEn: '2026-09-06T12:00:00-05:00', confirmadoEn: null },
  { id: 'DEP-004', leadId: 'L-030', monto: 15000, moneda: 'USD', depositadoEn: '2026-09-07T09:00:00-05:00', confirmadoEn: '2026-09-07T09:05:00-05:00', anuladoEn: '2026-09-07T10:00:00-05:00' },
]

export interface LeadConDeposito {
  original: CitaConLead
  asistencia: CitaConLead
  depositos: DepositoEjemplo[]
}

export function montosDepositados(depositos: DepositoEjemplo[]): Record<Moneda, number> {
  return depositos.reduce((montos, deposito) => {
    montos[deposito.moneda] += deposito.monto
    return montos
  }, { PEN: 0, USD: 0 })
}

/** La ficha y el flujo deben reconocer exactamente la misma asistencia. */
export function asistioTrasInasistencia(original: CitaConLead, cita: CitaConLead, corte = CORTE) {
  const asistencia = Date.parse(cita.asistioEn ?? '')
  return cita.estado === 'realizada'
    && asistencia > Date.parse(`${original.fecha}T${original.hora}:00-05:00`)
    && asistencia >= Date.parse(cita.reprogramadaEn ?? '')
    && asistencia <= Date.parse(corte)
}

/** Flujo de conjuntos anidados de leads: inasistencia → reprogramación
 * vinculada → asistencia registrada → depósito confirmado posterior.
 * Cada lead y movimiento se cuenta una vez. Una etapa nunca incorpora
 * personas ajenas a la anterior. Solo para el prototipo local. */
export function depositosDeInasistencias(citas: CitaConLead[], depositos = DEPOSITOS_EJEMPLO, corte = CORTE, todas = CITAS_CRM) {
  const limite = Date.parse(corte)
  const instante = (cita: CitaConLead) => Date.parse(`${cita.fecha}T${cita.hora}:00-05:00`)
  const ordenarOrigen = (a: Recuperacion, b: Recuperacion) => instante(a.original) - instante(b.original) || a.original.id.localeCompare(b.original.id)
  const originales = new Map<string, Recuperacion>()
  const reprogramadas = new Map<string, Recuperacion>()
  const recuperadas = new Map<string, Recuperacion>()
  for (const fila of seguimientoInasistencias(citas, todas, corte)) {
    const { original, nueva } = fila
    if (!(instante(original) <= limite)) continue
    const anterior = originales.get(original.leadId)
    if (!anterior || ordenarOrigen(fila, anterior) < 0) originales.set(original.leadId, fila)
    if (!nueva) continue
    const reprogramada = reprogramadas.get(original.leadId)
    if (!reprogramada || ordenarOrigen(fila, reprogramada) < 0) reprogramadas.set(original.leadId, fila)
    // Haber asistido sigue siendo un paso cumplido aunque haya otra cita posterior.
    for (const cita of fila.recorrido) {
      const asistencia = Date.parse(cita.asistioEn ?? '')
      if (!asistioTrasInasistencia(original, cita, corte)) continue
      const previa = recuperadas.get(original.leadId)
      const orden = previa ? asistencia - Date.parse(previa.nueva!.asistioEn!) || ordenarOrigen(fila, previa) || cita.id.localeCompare(previa.nueva!.id) : -1
      if (orden < 0) recuperadas.set(original.leadId, { ...fila, nueva: cita, estado: 'recuperada' })
    }
  }

  const movimientos = new Map<string, DepositoEjemplo>()
  for (const deposito of depositos) {
    const recuperada = recuperadas.get(deposito.leadId)
    const fecha = Date.parse(deposito.depositadoEn)
    const confirmacion = Date.parse(deposito.confirmadoEn ?? '')
    if (!recuperada || !Number.isFinite(deposito.monto) || deposito.monto <= 0) continue
    if (!(fecha > Date.parse(recuperada.nueva!.asistioEn!) && fecha <= limite && confirmacion >= fecha && confirmacion <= limite)) continue
    if (deposito.anuladoEn && !(Date.parse(deposito.anuladoEn) > limite)) continue
    movimientos.set(deposito.id, deposito)
  }

  const confirmados = [...movimientos.values()].sort((a, b) => Date.parse(a.depositadoEn) - Date.parse(b.depositadoEn) || a.id.localeCompare(b.id))
  const leads: LeadConDeposito[] = [...recuperadas.values()].map(fila => ({ original: fila.original, asistencia: fila.nueva!, depositos: confirmados.filter(deposito => deposito.leadId === fila.original.leadId) })).filter(lead => lead.depositos.length > 0)
  return {
    inasistencias: [...originales.values()],
    reprogramadas: [...reprogramadas.values()],
    recuperadas: [...recuperadas.values()],
    sinNueva: [...originales.values()].filter(fila => !reprogramadas.has(fila.original.leadId)),
    leads,
    base: originales.size,
    convertidos: leads.length,
    porcentaje: originales.size ? leads.length / originales.size * 100 : null,
    montos: montosDepositados(confirmados),
  }
}
