import { createContext, useContext } from 'react'
import { equipoCitas } from './modelo'
import type { CitaConLead } from './datos'
import type { DepositoEjemplo } from './depositos'
import type { GestionCitas } from './metas'
import type { ReunionClienteProyeccion } from './proyeccion'
import type { RangoProyeccion } from './proyeccion-rango'
/** Citas fusionadas de los meses del rango de Proyección y las reuniones con clientes sin lead de ese rango (lo provee la pantalla). */
export interface DatosProyeccionCitas {
  meses: string[]; citas: CitaConLead[]; gestion: GestionCitas | undefined; corte: string;
  /** Rango al que corresponden `reunionesClientes` (null: aún no se pidió ninguno). */
  rango: RangoProyeccion | null; reunionesClientes: ReunionClienteProyeccion[];
  cargando: boolean; error: string | null; onReintentar: () => void;
  /** «Actualizar»: relee todo el rango (no solo lo que falló). */
  onActualizar?: () => void;
}
export interface DatosCitas {
  citas: CitaConLead[]; corte: string; depositos: DepositoEjemplo[]; depositosDisponibles: boolean;
  depositoPorConversion?: boolean;
  gestion?: GestionCitas;
  mesInicial: string; modoDemo: boolean; meses: string[];
  cargando?: boolean; error?: string | null; onReintentar?: () => void;
  onMes?: (mes: string) => void; onAbrirLead?: (id: string, tareaId: string) => void;
  /** Proyección avisa qué meses y qué rango necesita (null o vacío: ninguno); sin cargador usa las citas de arriba. */
  onMesesProyeccion?: (meses: string[]) => void; onRangoProyeccion?: (rango: RangoProyeccion | null) => void;
  proyeccion?: DatosProyeccionCitas;
}
export const ContextoCitas = createContext<DatosCitas | null>(null)
export function useDatosCitas() {
  const datos = useContext(ContextoCitas)
  if (!datos) throw new Error('Citas requiere su fuente de datos')
  const origen = (datos.gestion?.avance?.poblacion ?? []).filter(p => p.analista_origen_id).map(p => ({
    id: p.analista_origen_id!, nombre: p.analista_origen_nombre,
    supervisor: p.supervisor_origen_nombre, supervisorId: p.supervisor_origen_id ?? 'sin_supervisor',
  }))
  const cierres = (datos.gestion?.avance?.conversiones ?? []).filter(c => c.analista_id).map(c => ({
    id: c.analista_id!, nombre: c.analista_nombre, supervisor: c.supervisor_nombre, supervisorId: c.supervisor_id ?? 'sin_supervisor',
  }))
  // Un analista con capital en el mes pero sin leads ni citas también se puede
  // seleccionar; las fuentes con actividad conservan la prioridad del nombre.
  const capital = (datos.gestion?.avance?.capital ?? []).filter(k => k.analista_id).map(k => ({
    id: k.analista_id!, nombre: k.analista_nombre ?? 'Sin analista',
    supervisor: k.supervisor_nombre ?? 'Sin supervisor', supervisorId: k.supervisor_id ?? 'sin_supervisor',
  }))
  const equipo = [...new Map([...capital, ...origen, ...cierres, ...equipoCitas(datos.citas), ...(datos.gestion?.asignaciones ?? [])].map(p => [p.id, p])).values()]
    .sort((a,b) => a.nombre.localeCompare(b.nombre, 'es'))
  return { ...datos, equipo, nombreAnalista: (id: string) => equipo.find(p => p.id === id)?.nombre ?? 'Sin analista' }
}
export function horaLima(fecha: string) { return new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(fecha)) }
export function corteLima(fecha: string) { return new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', dateStyle: 'medium', timeStyle: 'short' }).format(new Date(fecha)) + ' Lima' }
