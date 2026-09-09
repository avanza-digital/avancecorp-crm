import { createContext, useContext } from 'react'
import { equipoCitas } from './modelo'
import type { CitaConLead } from './datos'
import type { DepositoEjemplo } from './depositos'
export interface DatosCitas {
  citas: CitaConLead[]; corte: string; depositos: DepositoEjemplo[]; depositosDisponibles: boolean;
  mesInicial: string; modoDemo: boolean; meses: string[];
  cargando?: boolean; error?: string | null; onReintentar?: () => void;
  onMes?: (mes: string) => void; onAbrirLead?: (id: string, tareaId: string) => void;
}
export const ContextoCitas = createContext<DatosCitas | null>(null)
export function useDatosCitas() {
  const datos = useContext(ContextoCitas)
  if (!datos) throw new Error('Citas requiere su fuente de datos')
  return { ...datos, equipo: equipoCitas(datos.citas), nombreAnalista: (id: string) => datos.citas.find(c => c.analista === id)?.analistaNombre ?? 'Sin analista' }
}
export function horaLima(fecha: string) { return new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(fecha)) }
export function corteLima(fecha: string) { return new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', dateStyle: 'medium', timeStyle: 'short' }).format(new Date(fecha)) + ' Lima' }
