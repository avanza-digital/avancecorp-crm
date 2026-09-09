import { CORTE } from '../../../prototypes/citas-assets/model.mjs'
import { CITAS_CRM, type CitaConLead } from './datos'
import { depositosDeInasistencias as calcular, asistioTrasInasistencia as asistio, type DepositoEjemplo } from '@/components/citas/depositos'
export type { DepositoEjemplo, LeadConDeposito } from '@/components/citas/depositos'
export { montosDepositados } from '@/components/citas/depositos'
export const DEPOSITOS_EJEMPLO: DepositoEjemplo[] = [
  { id: 'DEP-001', leadId: 'L-031', monto: 35000, moneda: 'PEN', depositadoEn: '2026-09-04T10:00:00-05:00', confirmadoEn: '2026-09-04T10:05:00-05:00' },
  { id: 'DEP-002', leadId: 'L-032', monto: 5000, moneda: 'USD', depositadoEn: '2026-09-04T12:00:00-05:00', confirmadoEn: '2026-09-04T12:10:00-05:00' },
  { id: 'DEP-003', leadId: 'L-029', monto: 50000, moneda: 'PEN', depositadoEn: '2026-09-06T12:00:00-05:00', confirmadoEn: null },
  { id: 'DEP-004', leadId: 'L-030', monto: 15000, moneda: 'USD', depositadoEn: '2026-09-07T09:00:00-05:00', confirmadoEn: '2026-09-07T09:05:00-05:00', anuladoEn: '2026-09-07T10:00:00-05:00' },
]


export const depositosDeInasistencias = (citas: CitaConLead[], depositos = DEPOSITOS_EJEMPLO, corte = CORTE, todas = CITAS_CRM) => calcular(citas,depositos,corte,todas)
export const asistioTrasInasistencia = (original: CitaConLead, cita: CitaConLead, corte = CORTE) => asistio(original,cita,corte)
