import {
  useCallback,
  useMemo,
  useState,
  type JSX,
  type ReactNode,
} from 'react'
import { mensajeDeError } from '@/data/crm-api'
import { useMetricasConversiones } from '@/data/crm-queries'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  derivarAlertasSupervisor,
  derivarAlertasVendedor,
  type AlertaCRM,
} from '@/lib/alertas'
import {
  derivarAlertasGerencia,
  periodoAnteriorComparable,
  type AlertaGerencia,
} from '@/lib/alertas-gerencia'
import { AlertasCRMContext, type EstadoAlertasCRM } from '@/lib/alertas-context'
import { useAuth } from '@/lib/auth-context'
import { identidadesEquipoConversion } from '@/lib/conversion-equipo'
import {
  conversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import { useAhora } from '@/lib/ahora'
import { useCRMData } from '@/lib/store-context'
import type { Rol } from '@/lib/roles'

function adaptarAlertaGerencial(alerta: AlertaGerencia): AlertaCRM {
  if (alerta.tipo === 'bajo_meta_conversion') {
    return {
      id: alerta.id,
      tipo: alerta.tipo,
      severidad: alerta.severidad,
      alcance: 'empresa',
      titulo: 'Conversión bajo meta',
      detalle: `${alerta.responsable}: ${alerta.actual ?? alerta.valor}% frente a ${alerta.objetivo ?? '—'}% · brecha ${alerta.brechaPp ?? '—'} pp`,
      responsableId: alerta.responsableId,
      responsable: alerta.responsable,
      valor: alerta.valor,
      destino: {
        vista: 'ranking-vendedores',
        etiqueta: 'Ver ranking',
      },
    }
  }

  return {
    id: alerta.id,
    tipo: alerta.tipo,
    severidad: alerta.severidad,
    alcance: 'empresa',
    titulo: 'Cayó la conversión general',
    detalle: `${alerta.actual ?? alerta.valor}% frente a ${alerta.objetivo ?? '—'}% del corte comparable · caída ${alerta.brechaPp ?? '—'} pp`,
    responsableId: null,
    responsable: 'Equipo comercial',
    valor: alerta.valor,
    destino: {
      vista: 'conversiones',
      etiqueta: 'Ver conversión',
    },
  }
}

function esRolOperativo(rol: Rol | null): rol is 'vendedor' | 'supervisor' {
  return rol === 'vendedor' || rol === 'supervisor'
}

export function AlertasCRMProvider({ children }: { children: ReactNode }): JSX.Element {
  const { yo } = useAuth()
  const {
    ambito,
    actividadesDelAmbito,
    tareas,
    equipo,
    objetivos,
    objetivosError,
    recargar,
  } = useCRMData()
  const ahora = useAhora()
  const [actualizandoOperativo, setActualizandoOperativo] = useState(false)
  const rol = yo?.rol ?? null
  const diaLima = fechaLima(ahora)
  const periodoActual = useMemo(
    () => ({ desde: `${diaLima.slice(0, 7)}-01`, hasta: diaLima }),
    [diaLima],
  )
  const periodoAnterior = useMemo(() => periodoAnteriorComparable(diaLima), [diaLima])
  const sesionGerenciaReal = Boolean(yo && !yo.demo && rol === 'gerencia')

  // Solo Gerencia consulta conversiones globales. Vendedor y supervisor derivan
  // sus pendientes de los datos ya recortados por RLS que carga el store.
  const conversionAnterior = useMetricasConversiones(
    sesionGerenciaReal,
    periodoAnterior.desde,
    periodoAnterior.hasta,
  )
  const conversionActual = useMetricasConversiones(
    sesionGerenciaReal,
    periodoActual.desde,
    periodoActual.hasta,
  )

  const identidadesGerencia = useMemo(
    () => yo?.demo
      ? conversionEquipoDemo()
      : identidadesEquipoConversion(ambito.vendedores, equipo),
    [ambito.vendedores, equipo, yo?.demo],
  )
  const metasGerencia = useMemo(
    () => yo?.demo ? metasConversionEquipoDemo() : (objetivos.porVendedor ?? {}),
    [objetivos.porVendedor, yo?.demo],
  )
  const conversionGerencia = useMemo(
    () => yo?.demo
      ? metricasConversionesDemo(periodoActual.desde, periodoActual.hasta)
      : conversionActual.data,
    [conversionActual.data, periodoActual.desde, periodoActual.hasta, yo?.demo],
  )

  const alertas = useMemo<AlertaCRM[]>(() => {
    if (!yo) return []
    if (rol === 'vendedor') {
      return derivarAlertasVendedor({
        vendedorId: yo.id,
        leads: ambito.leads,
        actividades: actividadesDelAmbito,
        tareas,
        ahora,
      })
    }
    if (rol === 'supervisor') {
      return derivarAlertasSupervisor({
        supervisorId: yo.id,
        leads: ambito.leads,
        actividades: actividadesDelAmbito,
        tareas,
        vendedores: ambito.vendedores,
        ahora,
      })
    }
    if (rol !== 'gerencia') return []

    return derivarAlertasGerencia({
      conversiones: conversionGerencia,
      conversionesAnteriores: yo.demo ? undefined : conversionAnterior.data,
      equipoConversion: identidadesGerencia,
      metasVendedores: metasGerencia,
      objetivosError,
      diaDelMes: Number(diaLima.slice(8, 10)),
    }).map(adaptarAlertaGerencial)
  }, [
    actividadesDelAmbito,
    ambito.leads,
    ambito.vendedores,
    ahora,
    conversionAnterior.data,
    conversionGerencia,
    diaLima,
    identidadesGerencia,
    metasGerencia,
    objetivosError,
    rol,
    tareas,
    yo,
  ])

  const errores = useMemo(() => {
    if (rol !== 'gerencia' || yo?.demo) return []
    const mensajes = [
      conversionActual.error
        ? mensajeDeError(conversionActual.error, 'No se pudo calcular la conversión actual.')
        : null,
      conversionAnterior.error
        ? mensajeDeError(conversionAnterior.error, 'No se pudo comparar con el mes anterior.')
        : null,
      objetivosError ? 'No se pudieron cargar las metas individuales.' : null,
    ]
    return mensajes.filter((mensaje): mensaje is string => Boolean(mensaje))
  }, [
    conversionActual.error,
    conversionAnterior.error,
    objetivosError,
    rol,
    yo?.demo,
  ])

  const cargandoGerencia = sesionGerenciaReal && (
    conversionActual.isPending
    || conversionActual.isFetching
    || conversionAnterior.isPending
    || conversionAnterior.isFetching
  )

  const reintentar = useCallback(() => {
    if (rol === 'gerencia' && !yo?.demo) {
      void conversionActual.refetch()
      void conversionAnterior.refetch()
      if (objetivosError) void recargar()
      return
    }
    if (esRolOperativo(rol) && !yo?.demo) {
      setActualizandoOperativo(true)
      void recargar().finally(() => setActualizandoOperativo(false))
    }
  }, [
    conversionActual,
    conversionAnterior,
    objetivosError,
    recargar,
    rol,
    yo?.demo,
  ])

  const cargando = cargandoGerencia || actualizandoOperativo
  const valor = useMemo<EstadoAlertasCRM>(() => ({
    alertas,
    rol,
    cargando,
    errores,
    generadoEn: rol === 'gerencia'
      ? (conversionGerencia?.generado_en ?? null)
      : new Date(ahora).toISOString(),
    reintentar,
  }), [
    alertas,
    ahora,
    cargando,
    conversionGerencia?.generado_en,
    errores,
    reintentar,
    rol,
  ])

  return <AlertasCRMContext.Provider value={valor}>{children}</AlertasCRMContext.Provider>
}
