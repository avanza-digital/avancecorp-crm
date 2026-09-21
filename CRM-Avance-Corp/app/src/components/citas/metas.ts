import { METAS_CITAS_INICIALES } from '@/lib/metas-citas-config'
import type { GestionMensualCitas, TestigoCitas } from '@/lib/gestion-citas'
import { type CitaConLead } from './datos'
import { normalizar, type FiltrosCitas, type PersonaCitas } from './modelo'

export interface LeadBaseCitas extends PersonaCitas {
  leadId: string; nombreLead: string; telefono: string; asignadoEn: string;
  manualPropio: boolean; origen: string; moneda: string; monto: number;
  registroManual?: boolean;
}
export interface GestionCitas {
  citasPorLead: number; entrevistasPorcentaje: number; depositosPorcentaje: number;
  asignaciones: LeadBaseCitas[];
  actividadManuales?: 'excluir' | 'incluir';
  excluirManualesBase?: boolean;
  avance?: GestionMensualCitas;
  /** F2: cálculo independiente del servidor para el total sin filtros. */
  testigo?: TestigoCitas;
}

/** La semana delimita la actividad; la base de la meta sigue siendo mensual.
 * Estado/modalidad/resultado de una cita no eliminan leads aún sin cita. */
export function baseCitasFiltrada(base: LeadBaseCitas[], f: FiltrosCitas) {
  const palabras = normalizar(f.q).split(/\s+/).filter(Boolean)
  const numeros = f.q.replace(/\D/g, '')
  return base.filter(l => {
    const texto = normalizar(`${l.nombreLead} ${l.telefono} ${l.leadId}`)
    const busqueda = palabras.every(p => texto.includes(p)) || (numeros.length > 2 && /^[\d\s+()-]+$/.test(f.q) && l.telefono.replace(/\D/g, '').includes(numeros))
    return busqueda && (!f.leadId || l.leadId === f.leadId)
      && (!f.analista || l.id === f.analista) && (!f.equipo || l.supervisorId === f.equipo)
      && (!f.origen || l.origen === f.origen) && (!f.moneda || l.moneda === f.moneda)
      && (!f.registro || (l.registroManual ?? l.manualPropio) === (f.registro === 'manual'))
      && (!f.moneda || f.min === '' || l.monto >= Number(f.min))
      && (!f.moneda || f.max === '' || l.monto <= Number(f.max))
  })
}

/** Sin base del servidor nunca se infiere la cartera a partir de sus citas.
 * Deduplica personas por analista; el total se recalcula con personas únicas. */
export function metaCitas(citas: CitaConLead[], base?: LeadBaseCitas[], meta: number = METAS_CITAS_INICIALES.citas_por_lead, actividadManuales?: 'excluir' | 'incluir', excluirManualesBase = true) {
  const elegibles = citas.filter(c => c.manualPropio === false || actividadManuales === 'incluir')
  const leads = base === undefined ? null : new Set(base.filter(l => !excluirManualesBase || !l.manualPropio).map(l => l.leadId)).size
  const comprobada = base !== undefined && citas.every(c => c.manualPropio !== undefined)
    && (actividadManuales !== undefined || citas.every(c => c.manualPropio === false))
  const promedio = comprobada && leads ? elegibles.length / leads : null
  return {
    leads, citas: comprobada ? elegibles.length : null, promedio,
    cumplimiento: promedio === null || !Number.isFinite(meta) || meta <= 0 ? null : promedio / meta * 100,
    manuales: citas.length - elegibles.length,
  }
}
