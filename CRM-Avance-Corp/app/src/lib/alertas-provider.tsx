import {
  useCallback,
  useMemo,
  useState,
  type JSX,
  type ReactNode,
} from 'react'
import { mensajeDeError } from '@/data/crm-api'
import { useMetricasConversiones, useRecordatoriosDisponibilidad } from '@/data/crm-queries'
import { derivarAlertasRecordatorios } from '@/lib/recordatorios-disponibilidad'
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
import { funcionesLeadsVisibles } from '@/lib/config'
import {
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import { useAhora } from '@/lib/ahora'
import { useCRMData } from '@/lib/store-context'
import { administraSoloRolesCrm, type Rol } from '@/lib/roles'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'

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
    objetivos,
    objetivosError,
    cumplimientoMetas,
    cumplimientoMetasError,
    recargar,
  } = useCRMData()
  const ahora = useAhora()
  const [actualizandoOperativo, setActualizandoOperativo] = useState(false)
  const rol = yo?.rol ?? null
  const soloRoles = administraSoloRolesCrm(yo)
  const estadoSla = useEstadoSlaOperativo(
    ambito.leads,
    actividadesDelAmbito,
    !soloRoles && esRolOperativo(rol),
  )
  const diaLima = fechaLima(ahora)
  const periodoActual = useMemo(
    () => ({ desde: `${diaLima.slice(0, 7)}-01`, hasta: diaLima }),
    [diaLima],
  )
  const periodoAnterior = useMemo(() => periodoAnteriorComparable(diaLima), [diaLima])
  const sesionGerenciaReal = Boolean(yo && !yo.demo && rol === 'gerencia')
  // F3 «Recordar»: SOLO el vendedor real tiene recordatorios (la RLS es
  // owner-only y el rol es la antesala de la toma). En demo no existen. Y solo
  // con las funciones de leads VISIBLES (Codex F3-R2, espejo de vistas.ts): la
  // campana vive tras ese gate — consultar con el gate cerrado sería trabajo
  // invisible y una insignia que el vendedor no puede ni abrir.
  const sesionVendedorReal = Boolean(
    yo && !yo.demo && rol === 'vendedor' && !soloRoles
    && funcionesLeadsVisibles(yo.demo, rol, yo.id),
  )
  const recordatorios = useRecordatoriosDisponibilidad(sesionVendedorReal)

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

  const metasGerencia = useMemo(
    () => yo?.demo ? metasConversionEquipoDemo() : (objetivos.porVendedor ?? {}),
    [objetivos.porVendedor, yo?.demo],
  )
  const cumplimientoGerencia = useMemo(
    () => yo?.demo
      ? cumplimientoMetasConversionEquipoDemo().porVendedor
      : (cumplimientoMetas?.porVendedor ?? {}),
    [cumplimientoMetas?.porVendedor, yo?.demo],
  )
  const conversionGerencia = useMemo(
    () => yo?.demo
      ? metricasConversionesDemo(periodoActual.desde, periodoActual.hasta)
      : conversionActual.data,
    [conversionActual.data, periodoActual.desde, periodoActual.hasta, yo?.demo],
  )

  const alertas = useMemo<AlertaCRM[]>(() => {
    if (!yo || soloRoles) return []
    if (rol === 'vendedor') {
      return [
        // F3: los recordatorios VENCIDOS primero — son acción inmediata y
        // barata («verifica si ya está libre»); los vigentes no suenan.
        ...derivarAlertasRecordatorios(recordatorios.data ?? [], ahora),
        ...derivarAlertasVendedor({
          vendedorId: yo.id,
          leads: ambito.leads,
          actividades: actividadesDelAmbito,
          tareas,
          ahora,
          estadosSla: estadoSla.indice,
        }),
      ]
    }
    if (rol === 'supervisor') {
      return derivarAlertasSupervisor({
        supervisorId: yo.id,
        leads: ambito.leads,
        actividades: actividadesDelAmbito,
        tareas,
        vendedores: ambito.vendedores,
        ahora,
        estadosSla: estadoSla.indice,
      })
    }
    if (rol !== 'gerencia') return []

    return derivarAlertasGerencia({
      conversiones: conversionGerencia,
      conversionesAnteriores: yo.demo ? undefined : conversionAnterior.data,
      metasVendedores: metasGerencia,
      cumplimientosVendedores: cumplimientoGerencia,
      objetivosError,
      cumplimientoError: cumplimientoMetasError,
      diaDelMes: Number(diaLima.slice(8, 10)),
      // Los días del mes salen de la fecha de LIMA, no del reloj de la máquina:
      // el día 0 del mes siguiente es el último del actual, y en UTC eso puede
      // caer en otro mes. Febrero corre el último corte a su día 28 o 29.
      diasDelMes: new Date(
        Number(diaLima.slice(0, 4)),
        Number(diaLima.slice(5, 7)),
        0,
      ).getDate(),
    }).map(adaptarAlertaGerencial)
  }, [
    actividadesDelAmbito,
    ambito.leads,
    ambito.vendedores,
    ahora,
    conversionAnterior.data,
    conversionGerencia,
    diaLima,
    estadoSla.indice,
    cumplimientoGerencia,
    cumplimientoMetasError,
    metasGerencia,
    objetivosError,
    recordatorios.data,
    rol,
    tareas,
    yo,
    soloRoles,
  ])

  const errores = useMemo(() => {
    if (yo?.demo || soloRoles) return []
    const mensajes = [
      rol === 'gerencia' && conversionActual.error
        ? mensajeDeError(conversionActual.error, 'No se pudo calcular la conversión actual.')
        : null,
      rol === 'gerencia' && conversionAnterior.error
        ? mensajeDeError(conversionAnterior.error, 'No se pudo comparar con el mes anterior.')
        : null,
      rol === 'gerencia' && objetivosError
        ? 'No se pudieron cargar las metas individuales.'
        : null,
      rol === 'gerencia' && cumplimientoMetasError
        ? 'No se pudo calcular el cumplimiento confirmado.'
        : null,
      esRolOperativo(rol) && estadoSla.error
        ? mensajeDeError(
            estadoSla.error,
            'No se pudo verificar el reloj SLA; se ocultaron las escalaciones temporales.',
          )
        : null,
    ]
    return mensajes.filter((mensaje): mensaje is string => Boolean(mensaje))
  }, [
    conversionActual.error,
    conversionAnterior.error,
    objetivosError,
    cumplimientoMetasError,
    estadoSla.error,
    rol,
    soloRoles,
    yo?.demo,
  ])

  const cargandoGerencia = sesionGerenciaReal && (
    conversionActual.isPending
    || conversionActual.isFetching
    || conversionAnterior.isPending
    || conversionAnterior.isFetching
  )

  const reintentar = useCallback(() => {
    if (soloRoles) return
    if (rol === 'gerencia' && !yo?.demo) {
      void conversionActual.refetch()
      void conversionAnterior.refetch()
      if (objetivosError) void recargar()
      return
    }
    if (esRolOperativo(rol) && !yo?.demo) {
      setActualizandoOperativo(true)
      void Promise.all([
        recargar(),
        estadoSla.error ? estadoSla.recargar() : Promise.resolve(),
      ]).finally(() => setActualizandoOperativo(false))
    }
  }, [
    conversionActual,
    conversionAnterior,
    objetivosError,
    recargar,
    rol,
    soloRoles,
    estadoSla,
    yo?.demo,
  ])

  const cargando = cargandoGerencia
    || actualizandoOperativo
    || (!soloRoles && esRolOperativo(rol) && estadoSla.cargando)
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
