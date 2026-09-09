import { fmtFecha } from '@/lib/format'
import { ESTADOS, type CitaEjemplo } from './modelo'

export const siguientePaso = (cita: CitaEjemplo) => cita.cerrado ? 'Cierre posterior registrado' : ESTADOS[cita.estado].next
export function contextoCita(cita: CitaEjemplo) {
  if (cita.nuevaFecha) return `Nueva fecha: ${fmtFecha(cita.nuevaFecha)}`
  if (cita.cerrado) return 'Tiene un cierre posterior a la cita'
  return cita.estado === 'programada' ? 'Cita por realizar' : cita.resultado
}
