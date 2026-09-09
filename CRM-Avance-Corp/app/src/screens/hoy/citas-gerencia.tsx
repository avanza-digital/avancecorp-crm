import { useMemo, useState } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { useCitasGerencia, adaptarCitas, type ConsultaCitasRpc } from '@/data/citas-gerencia'
import { ContextoCitas } from '@/components/citas/contexto'
import { TableroCitas } from '@/components/citas/propuesta'
import { defaults, mesLima, rango } from '@/components/citas/modelo'
import '@/components/citas/presentacion.css'

export function CitasGerencia() {
  const { yo } = useAuth()
  const { tareas, ambito, equipo } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const ahora = useAhora()
  const [mes, setMes] = useState(() => mesLima(new Date(ahora)))
  const consulta = useCitasGerencia(mes, yo?.id ?? null, yo?.rol==='gerencia' && !yo.demo)
  const demo = useMemo<ConsultaCitasRpc>(() => {
    const [desde,hasta] = rango(defaults(mes))
    return {
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
  const error = consulta.error instanceof Error ? consulta.error.message : 'No se pudieron cargar las citas.'
  return <ContextoCitas value={{
    citas,corte:datos?.generado_en ?? new Date(ahora).toISOString(),depositos:[],depositosDisponibles:false,
    modoDemo:Boolean(yo?.demo),mesInicial:mesLima(new Date(ahora)),meses:[],
    cargando:!yo?.demo && consulta.isPending,error:!yo?.demo && consulta.isError ? error : null,
    onMes:setMes,onReintentar:() => { if (!yo?.demo) void consulta.refetch() },
    onAbrirLead:(id) => { void abrirLead(id) },
  }}>
    {datos && datos.citas_clientes>0 && <p className="mb-3 text-sm">{datos.citas_clientes} citas de clientes se consultan en Agenda. Las metas de este módulo corresponden a leads.</p>}
    <TableroCitas />
  </ContextoCitas>
}
