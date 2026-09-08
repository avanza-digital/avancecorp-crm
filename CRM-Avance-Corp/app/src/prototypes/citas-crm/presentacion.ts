import { fmtFecha } from '@/lib/format'
import { EQUIPO, ESTADOS, type CitaEjemplo } from '../../../prototypes/citas-assets/model.mjs'

export const nombreAnalista = (id: string) => EQUIPO.find(persona => persona.id === id)?.nombre ?? 'Sin analista'
export const siguientePaso = (cita: CitaEjemplo) => cita.cerrado ? 'Cierre posterior registrado' : ESTADOS[cita.estado].next
export function contextoCita(cita: CitaEjemplo) {
  if (cita.nuevaFecha) return `Nueva fecha: ${fmtFecha(cita.nuevaFecha)}`
  if (cita.cerrado) return 'Tiene un cierre posterior a la cita'
  return cita.estado === 'programada' ? 'Cita por realizar' : cita.resultado
}
