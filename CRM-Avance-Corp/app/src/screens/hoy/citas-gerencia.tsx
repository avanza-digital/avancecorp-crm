import { CitasClientes } from '@/components/citas/citas-clientes'
import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'
import { useCallback, useMemo, useState } from 'react'
import { usePanelesActions } from '@/lib/store-context'
import { adaptarDepositos, adaptarGestion } from '@/data/citas-gerencia'
import { leerHash } from '@/lib/router'
import { consultaCitasValida, mesConsultaCitas } from '@/lib/enlace-citas'
import { useDatosCitasGerencia, useDatosProyeccionCitas } from './use-datos-citas-gerencia'
import { ContextoCitas } from '@/components/citas/contexto'
import { TableroCitas } from '@/components/citas/propuesta'
import { mesLima } from '@/components/citas/modelo'
import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'
import '@/components/citas/presentacion.css'

export function CitasGerencia() {
  const consultaSesion = useConsultaGerencia()
  const [mes, setMes] = useState(() => {
    const consulta = leerHash().consultaCitas
    if (consulta) return mesConsultaCitas(consulta)
    const guardado = consultaSesion?.consulta.citas?.filtros.mes
    return guardado && consultaCitasValida({ mes: guardado }) ? guardado : mesLima()
  })
  const { yo, ahora, datos, citas, consulta } = useDatosCitasGerencia(mes)
  const { abrirLead } = usePanelesActions()
  // Meses y rango que pide la Proyección (vacío y null en las otras pestañas).
  const [mesesProyeccion, setMesesProyeccion] = useState<string[]>([])
  const pedirMeses = useCallback((meses: string[]) => setMesesProyeccion(actual => actual.join() === meses.join() ? actual : meses), [])
  const [rangoProyeccion, setRangoProyeccion] = useState<RangoProyeccion | null>(null)
  const pedirRango = useCallback((rango: RangoProyeccion | null) => setRangoProyeccion(actual =>
    actual?.desde === rango?.desde && actual?.hasta === rango?.hasta ? actual : rango), [])
  const proyeccion = useDatosProyeccionCitas(mesesProyeccion, rangoProyeccion)
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
    // En demostración las citas de arriba ya traen todos los meses del ejemplo.
    // Con sesión real la Proyección SIEMPRE recibe su cargador: antes de pedir sus meses espera (Codex 19/10:
    // sin él se pintaban un instante solo las citas del mes, sin las reuniones con clientes).
    onMesesProyeccion:pedirMeses,onRangoProyeccion:pedirRango,...(yo?.demo ? {} : {proyeccion}),
  }}>
    <TableroCitas conservarConsulta={yo?.rol === 'gerencia'} />
    <CitasClientes mes={mes} />
  </ContextoCitas>
}
