import type { Moneda } from '@/lib/format'
import { CORTE } from '../../../prototypes/citas-assets/model.mjs'
import type { CitaConLead } from './datos'

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
  depositos: DepositoEjemplo[]
}

export function montosDepositados(depositos: DepositoEjemplo[]): Record<Moneda, number> {
  return depositos.reduce((montos, deposito) => {
    montos[deposito.moneda] += deposito.monto
    return montos
  }, { PEN: 0, USD: 0 })
}

/** Cohorte de leads únicos con inasistencia filtrada. Sigue sus depósitos
 * desde la primera inasistencia de esa consulta hasta el corte, aunque no
 * haya otra cita. No atribuye causalidad a una cita ni exige asistencia.
 * Cada movimiento se suma una vez por id; un lead con varios depósitos
 * incrementa el número de depositantes una sola vez. Solo para el prototipo. */
export function depositosDeInasistencias(citas: CitaConLead[], depositos = DEPOSITOS_EJEMPLO, corte = CORTE) {
  const limite = Date.parse(corte)
  const instante = (cita: CitaConLead) => Date.parse(`${cita.fecha}T${cita.hora}:00-05:00`)
  const originales = new Map<string, CitaConLead>()
  for (const cita of citas) {
    if (cita.estado !== 'no_show' || !(instante(cita) <= limite)) continue
    const anterior = originales.get(cita.leadId)
    if (!anterior || instante(cita) < instante(anterior)) originales.set(cita.leadId, cita)
  }

  const movimientos = new Map<string, DepositoEjemplo>()
  for (const deposito of depositos) {
    const original = originales.get(deposito.leadId)
    const fecha = Date.parse(deposito.depositadoEn)
    const confirmacion = Date.parse(deposito.confirmadoEn ?? '')
    if (!original || !Number.isFinite(deposito.monto) || deposito.monto <= 0) continue
    if (!(fecha >= instante(original) && fecha <= limite && confirmacion >= fecha && confirmacion <= limite)) continue
    if (deposito.anuladoEn && !(Date.parse(deposito.anuladoEn) > limite)) continue
    movimientos.set(deposito.id, deposito)
  }

  const confirmados = [...movimientos.values()].sort((a, b) => Date.parse(a.depositadoEn) - Date.parse(b.depositadoEn) || a.id.localeCompare(b.id))
  const leads: LeadConDeposito[] = [...originales.values()].map(original => ({ original, depositos: confirmados.filter(deposito => deposito.leadId === original.leadId) })).filter(lead => lead.depositos.length > 0)
  return {
    leads,
    base: originales.size,
    convertidos: leads.length,
    porcentaje: originales.size ? leads.length / originales.size * 100 : null,
    montos: montosDepositados(confirmados),
  }
}
