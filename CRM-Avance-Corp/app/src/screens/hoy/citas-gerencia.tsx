import { useMemo, useState } from 'react'
import { usePanelesActions } from '@/lib/store-context'
import { adaptarDepositos, adaptarGestion } from '@/data/citas-gerencia'
import { leerHash } from '@/lib/router'
import { mesConsultaCitas } from '@/lib/enlace-citas'
import { useDatosCitasGerencia } from './use-datos-citas-gerencia'
import { ContextoCitas } from '@/components/citas/contexto'
import { TableroCitas } from '@/components/citas/propuesta'
import { mesLima } from '@/components/citas/modelo'
import '@/components/citas/presentacion.css'

export function CitasGerencia() {
  const [mes, setMes] = useState(() => {
    const consulta = leerHash().consultaCitas
    return consulta ? mesConsultaCitas(consulta) : mesLima()
  })
  const { yo, ahora, datos, citas, consulta } = useDatosCitasGerencia(mes)
  const { abrirLead } = usePanelesActions()
  const depositos = useMemo(() => datos ? adaptarDepositos(datos) : [],[datos])
  const gestion = useMemo(() => datos ? adaptarGestion(datos) : undefined,[datos])
  const error = consulta.error instanceof Error ? consulta.error.message : 'No se pudieron cargar las citas.'
  return <ContextoCitas value={{
    citas,corte:datos?.generado_en ?? new Date(ahora).toISOString(),depositos,depositosDisponibles:datos?.version===2,
    depositoPorConversion:datos?.version===2,
    ...(gestion ? {gestion} : {}),
    modoDemo:Boolean(yo?.demo),mesInicial:mesLima(new Date(ahora)),meses:[],
    cargando:!yo?.demo && consulta.isPending,error:!yo?.demo && consulta.isError ? error : null,
    onMes:setMes,onReintentar:() => { if (!yo?.demo) void consulta.refetch() },
    onAbrirLead:(id) => { void abrirLead(id) },
  }}>
    {datos && datos.citas_clientes>0 && <p className="mb-3 text-sm">{datos.citas_clientes} citas de clientes se consultan en Agenda. Las metas de este módulo corresponden a leads.</p>}
    <TableroCitas />
  </ContextoCitas>
}
