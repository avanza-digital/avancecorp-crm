import { useMemo } from 'react'
import { useAuth } from '@/lib/auth-context'
import { can } from '@/lib/roles'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { useCitasGerencia, adaptarCitas, type ConsultaCitasRpc } from '@/data/citas-gerencia'
import { defaults, rango } from '@/components/citas/modelo'

/** La misma lectura y adaptación para el módulo Citas y el Resumen móvil. */
export function useDatosCitasGerencia(mes: string) {
  const { yo } = useAuth()
  const { tareas, ambito, equipo } = useCRMData()
  const ahora = useAhora()
  const puedeVerCitas = can(yo?.rol, 'verCitasEquipo')
  const consulta = useCitasGerencia(mes, yo?.id ?? null, puedeVerCitas && !yo?.demo)
  const demo = useMemo<ConsultaCitasRpc>(() => {
    const [desde,hasta] = rango(defaults(mes))
    return {
      // El store demo no expone el vínculo al cliente. Conserva ausencia de
      // evidencia; las conversiones completas se prueban con el contrato V2.
      version:1,periodo:{desde,hasta},generado_en:new Date(ahora).toISOString(),
      disponibilidad_depositos:'sin_registro',depositos:[],citas_clientes:0,
      citas:tareas.filter(t => t.tipo==='reunion' && t.activo && ambito.leads.some(l => l.id===t.lead_id)).map(t => {
        const lead = ambito.leads.find(l => l.id===t.lead_id)!
        const analista = equipo.find(e => e.perfil_id===t.vendedor_id)
        const supervisor = equipo.find(e => e.perfil_id===(analista?.supervisor_id ?? t.asignado_supervisor_id))
        return { id:t.id,lead_id:lead.id,nombre:lead.nombre_completo,telefono:lead.telefono,
          analista_id:t.vendedor_id ?? null,analista_nombre:analista?.nombre_completo ?? 'Sin analista',
          supervisor_id:supervisor?.perfil_id ?? null,supervisor_nombre:supervisor?.nombre_completo ?? 'Sin supervisor',
          vence_en:t.vence_en,estado:t.estado,cancelada_por:null,modalidad:t.modalidad_reunion ?? 'sin_clasificar',
          origen:lead.origen,moneda:lead.moneda,monto_estimado:lead.monto_estimado,resultado:t.resultado_reunion ?? 'sin_clasificar',
          nota:t.detalle_cierre_reunion ?? t.nota ?? '',reagendada_de:t.reagendada_de ?? null,creado_en:t.creado_en,
          // El store no expone resultado_actividad_id: no inventar la hora de asistencia.
          asistencia_registrada_en:null,cierre_posterior:false,
        }
      }),
    }
  },[mes,ahora,tareas,ambito.leads,equipo])
  const datos = yo?.demo ? demo : consulta.data
  const citas = useMemo(() => datos ? adaptarCitas(datos) : [],[datos])
  return { yo, ahora, datos, citas, consulta, equipo }
}
