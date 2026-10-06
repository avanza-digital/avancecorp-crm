import { consultaInicial, consultarCitas, type CitaConLead } from '@/components/citas/datos'
import type { Miembro } from '@/lib/tipos'

/** Todas las citas de leads del día, con los mismos filtros que el destino. */
export function resumirCitasDia(citas: CitaConLead[], dia: string, miembros: Miembro[]) {
  const delDia = consultarCitas({ ...consultaInicial(dia.slice(0, 7)), dia }, citas)
  const grupos = new Map<string, { id: string; nombre: string; total: number }>()
  for (const miembro of miembros) {
    if (miembro.activo && miembro.rol_crm === 'supervisor') {
      grupos.set(miembro.perfil_id, { id: miembro.perfil_id, nombre: `Equipo de ${miembro.nombre_completo}`, total: 0 })
    }
  }
  for (const cita of delDia) {
    const id = cita.supervisorId
    const grupo = grupos.get(id) ?? { id, nombre: id === 'sin_supervisor' ? 'Sin supervisor' : `Equipo de ${cita.supervisor}`, total: 0 }
    grupo.total += 1
    grupos.set(id, grupo)
  }
  return {
    total: delDia.length,
    realizadas: delDia.filter(cita => cita.estado === 'realizada').length,
    equipos: [...grupos.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es')),
  }
}
