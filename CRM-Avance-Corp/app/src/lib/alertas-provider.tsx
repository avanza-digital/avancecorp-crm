import {
  useCallback,
  useMemo,
  useState,
  type JSX,
  type ReactNode,
} from 'react'
import { useQueryClient } from '@tanstack/react-query'
import {
  CrmApiError,
  MAX_LEADS_AMBITO,
  mensajeDeError,
  reconocerAlertaSupervisor,
} from '@/data/crm-api'
import {
  crmQueryKeys,
  useMetricasConversiones,
  useReconocimientosAlertas,
  useRecordatoriosDisponibilidad,
} from '@/data/crm-queries'
import { derivarAlertasRecordatorios } from '@/lib/recordatorios-disponibilidad'
import {
  aplicarReconocimientos,
  type AccionReconocimiento,
  type AsientoReconocimiento,
} from '@/lib/reconocimientos-alertas'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  derivarAlertasSupervisor,
  derivarAlertasVendedor,
  type AlertaCRM,
} from '@/lib/alertas'
import {
  derivarAlertasGerencia,
  LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL,
  MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR,
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
import { useResumenAvisosSla } from '@/data/sla-operacion-queries'
import { alertaResumenSla } from '@/lib/sla-avisos-presentacion'

function adaptarAlertaGerencial(alerta: AlertaGerencia, periodo: { desde: string; hasta: string }): AlertaCRM {
  if (alerta.tipo === 'bajo_meta_conversion') {
    // H10/H21 (F3): el aviso dice su VENTANA (mes en curso — la misma cifra
    // ponderada que pinta el ranking al que manda) y su UMBRAL de muestra;
    // un corte que no se dice hace parecer arbitraria la alerta que aparece
    // y sospechosa la que no.
    const muestra = alerta.muestra == null
      ? ''
      : ` · base de conversión: ${alerta.muestra} (se avisa desde ${MUESTRA_MINIMA_ALERTA_CONVERSION_VENDEDOR})`
    return {
      id: alerta.id,
      tipo: alerta.tipo,
      severidad: alerta.severidad,
      alcance: 'empresa',
      titulo: 'Conversión bajo meta',
      detalle: `${alerta.responsable}: ${alerta.actual ?? alerta.valor}% frente a ${alerta.objetivo ?? '—'}% · brecha ${alerta.brechaPp ?? '—'} pp · mes en curso${muestra}`,
      responsableId: alerta.responsableId,
      responsable: alerta.responsable,
      valor: alerta.valor,
      destino: {
        vista: 'ranking-vendedores',
        etiqueta: 'Ver ranking',
        periodo,
      },
    }
  }

  // H11: desde F3 esta cifra es la del NÚCLEO (la misma que HOY/Ranking y que
  // su vecina individual), comparada contra el mismo corte del mes anterior.
  const muestra = alerta.muestra == null
    ? ''
    : ` · base de conversión: ${alerta.muestra} (se compara desde ${LEADS_MINIMOS_ALERTA_CAIDA_GLOBAL})`
  return {
    id: alerta.id,
    tipo: alerta.tipo,
    severidad: alerta.severidad,
    alcance: 'empresa',
    titulo: 'Cayó la conversión general',
    detalle: `${alerta.actual ?? alerta.valor}% frente a ${alerta.objetivo ?? '—'}% del mismo corte del mes anterior · caída ${alerta.brechaPp ?? '—'} pp · cifra del núcleo${muestra}`,
    responsableId: null,
    responsable: 'Equipo comercial',
    valor: alerta.valor,
    destino: {
      vista: 'conversiones',
      etiqueta: 'Ver conversión',
      periodo,
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
  const sesionAvisosReal = Boolean(yo && !yo.demo && !soloRoles
    && (rol === 'vendedor' || rol === 'supervisor' || rol === 'gerencia' || rol === 'directorio')
    && funcionesLeadsVisibles(yo.demo, rol))
  const resumenSla = useResumenAvisosSla(sesionAvisosReal)
  // Un fallo o modo sin confirmar no reactiva los cálculos anteriores.
  const legado = Boolean(yo?.demo || (!resumenSla.error && resumenSla.data && resumenSla.data.modo !== 'activo'))
  const estadoSla = useEstadoSlaOperativo(
    ambito.leads,
    actividadesDelAmbito,
    !soloRoles && esRolOperativo(rol) && legado,
  )
  const diaLima = fechaLima(ahora)
  const periodoActual = useMemo(
    () => ({ desde: `${diaLima.slice(0, 7)}-01`, hasta: diaLima }),
    [diaLima],
  )
  const periodoAnterior = useMemo(() => periodoAnteriorComparable(diaLima), [diaLima])
  const sesionGerenciaReal = Boolean(yo && !yo.demo && rol === 'gerencia')
  // F3 «Recordar»: SOLO el analista real tiene recordatorios (la RLS es
  // owner-only y el rol es la antesala de la toma). En demo no existen. Y solo
  // con las funciones de leads VISIBLES (Codex F3-R2, espejo de vistas.ts): la
  // campana vive tras ese gate — consultar con el gate cerrado sería trabajo
  // invisible y una insignia que el analista no puede ni abrir.
  const sesionVendedorReal = Boolean(
    yo && !yo.demo && rol === 'vendedor' && !soloRoles
    && funcionesLeadsVisibles(yo.demo, rol),
  )
  const recordatorios = useRecordatoriosDisponibilidad(sesionVendedorReal)
  // F4 «sin ruido»: el libro de reconocimientos es del SUPERVISOR real, y
  // solo con la campana pintada (el mismo gate de leads que usa vistas.ts
  // para #/alertas): consultar el libro con la campana apagada sería trabajo
  // invisible — la misma regla que los recordatorios del analista.
  const sesionSupervisorReal = Boolean(
    yo && !yo.demo && rol === 'supervisor' && !soloRoles
    && funcionesLeadsVisibles(yo.demo, rol),
  )
  const reconocimientos = useReconocimientosAlertas(sesionSupervisorReal && legado)
  // Espejo LOCAL para la demo: mismo contrato y misma lógica pura, sin
  // servidor — el supervisor de demo prueba el circuito completo y su libro
  // muere con la sesión.
  const [asientosDemo, setAsientosDemo] = useState<AsientoReconocimiento[]>([])
  const queryClient = useQueryClient()

  // Solo Gerencia consulta conversiones globales. Analista y supervisor derivan
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
    const operativas = sesionAvisosReal && !resumenSla.error && resumenSla.data?.modo === 'activo'
      ? alertaResumenSla(resumenSla.data, yo.id, rol) : []
    if (rol === 'vendedor') {
      return [
        // F3: los recordatorios VENCIDOS primero — son acción inmediata y
        // barata («verifica si ya está libre»); los vigentes no suenan.
        ...derivarAlertasRecordatorios(recordatorios.data ?? [], ahora),
        // Fase 3 «sin topes»: el arranque real ya no baja el registro de
        // actividades, así que las alertas LEGADO (derivadas de él) solo se
        // pueden calcular en demo. En sesión real con el modo SLA apagado no
        // se inventan alertas «sin contacto» sobre una lista vacía: se callan.
        ...(legado && yo.demo ? derivarAlertasVendedor({
          vendedorId: yo.id,
          leads: ambito.leads,
          actividades: actividadesDelAmbito,
          tareas,
          ahora,
          estadosSla: estadoSla.indice,
        }) : operativas),
      ]
    }
    if (rol === 'supervisor') {
      return legado && yo.demo ? derivarAlertasSupervisor({
        supervisorId: yo.id,
        leads: ambito.leads,
        actividades: actividadesDelAmbito,
        tareas,
        vendedores: ambito.vendedores,
        ahora,
        estadosSla: estadoSla.indice,
      }) : operativas
    }
    if (rol !== 'gerencia') return operativas

    return [...operativas, ...derivarAlertasGerencia({
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
    }).map((alerta) => adaptarAlertaGerencial(alerta, periodoActual))]
  }, [
    legado,
    resumenSla.data,
    resumenSla.error,
    sesionAvisosReal,
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
    periodoActual,
    recordatorios.data,
    rol,
    tareas,
    yo,
    soloRoles,
  ])

  // F4 (Codex #5): con el ámbito EN el tope local, la foto de miembros puede
  // estar incompleta — una foto trunca que el servidor acepta callaría al
  // lead 2001. Sin foto confiable, reconocer se desactiva Y el libro se
  // ignora: la comparación de «empeoró» tampoco es de fiar.
  const fotoConfiable = !legado || ambito.leads.length < MAX_LEADS_AMBITO

  // F4: el libro atenúa (reconocer) u oculta (posponer) las alertas AGRUPADAS
  // del supervisor. Con el libro caído se aplica []: TODO suena — un fallo de
  // lectura jamás se convierte en silencio (y el error se dice abajo).
  // `error` manda sobre `data` (bloqueante Codex #1): TanStack CONSERVA los
  // datos del último fetch bueno cuando un refetch falla, y aplicar esos
  // asientos viejos con el libro caído sería exactamente el silencio indebido.
  const { visibles, pendientes, pospuestas } = useMemo(() => {
    if (!yo || rol !== 'supervisor' || !legado) {
      return { visibles: alertas, pendientes: alertas.length, pospuestas: 0 }
    }
    if (!fotoConfiable) {
      return {
        visibles: alertas.map(({ miembros: _foto, ...resto }) => resto),
        pendientes: alertas.length,
        pospuestas: 0,
      }
    }
    const asientos = yo.demo
      ? asientosDemo
      : (reconocimientos.error ? [] : (reconocimientos.data ?? []))
    return aplicarReconocimientos(alertas, asientos, ahora)
  }, [ahora, alertas, asientosDemo, fotoConfiable, legado, reconocimientos.data, reconocimientos.error, rol, yo])

  // Asienta en el libro y refresca la query; el toast y el foco son de la
  // pantalla. En demo escribe el espejo local con secuencia monotónica —
  // el MISMO contrato que la identity del servidor.
  const reconocer = useCallback(async (
    alerta: AlertaCRM,
    accion: AccionReconocimiento,
    hasta: string | null,
  ): Promise<void> => {
    if (!yo || rol !== 'supervisor' || alerta.miembros == null) return
    const miembros = [...alerta.miembros]
    if (yo.demo) {
      setAsientosDemo((previos) => [...previos, {
        id: crypto.randomUUID(),
        alerta_id: alerta.id,
        accion,
        miembros,
        severidad: alerta.severidad,
        hasta,
        creado_en: new Date().toISOString(),
        secuencia: (previos[previos.length - 1]?.secuencia ?? 0) + 1,
      }])
      return
    }
    await reconocerAlertaSupervisor(yo.id, alerta.id, accion, miembros, alerta.severidad, hasta)
    // throwOnError (Codex #4): sin él, un refetch caído se ABSORBE, la
    // promesa resuelve y la pantalla cantaría éxito con la fila vieja en
    // pantalla. El asiento SÍ quedó: el mensaje lo distingue del fallo real.
    try {
      await queryClient.invalidateQueries(
        { queryKey: crmQueryKeys.reconocimientosAlertas() },
        { throwOnError: true },
      )
    } catch {
      throw new CrmApiError(
        'Quedó asentado, pero la lista no se pudo refrescar: usa Actualizar.',
        'RECONOCIMIENTOS_REFRESCO',
      )
    }
  }, [queryClient, rol, yo])

  const errores = useMemo(() => {
    if (yo?.demo || soloRoles) return []
    const mensajes = [
      // Fase 3 «sin topes»: sin el registro de actividades del ámbito (ya no se
      // descarga), las alertas LEGADO por actividad no pueden calcularse en
      // sesión real; con el modo SLA apagado la campana se calla y lo DICE.
      // (La demo ya salió arriba; un rol no nulo implica sesión.)
      legado && (rol === 'vendedor' || rol === 'supervisor')
        ? 'Las alertas por actividad de leads necesitan el modo SLA activo: el CRM ya no descarga el registro de actividades del ámbito.'
        : null,
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
      sesionAvisosReal && resumenSla.error
        ? 'No se pudieron confirmar los avisos de seguimiento. Pulsa Actualizar.'
        : null,
      legado && esRolOperativo(rol) && estadoSla.error
        ? mensajeDeError(
            estadoSla.error,
            'No se pudo verificar el reloj SLA; se ocultaron las escalaciones temporales.',
          )
        : null,
      // F3.1: un fallo al listar recordatorios NO puede ser mudo — la campana
      // omitiría los «Revisar contacto» y el analista leería «sin pendientes»
      // como verdad (hallazgo convergente de la auditoría del 18/08).
      sesionVendedorReal && recordatorios.error
        ? mensajeDeError(
            recordatorios.error,
            'No se pudieron cargar tus recordatorios de contacto.',
          )
        : null,
      // F4: un libro ilegible tampoco es mudo — sin él las alertas suenan
      // COMPLETAS (reconocimientos incluidos) y el supervisor debe saber por
      // qué su campana volvió a llenarse.
      sesionSupervisorReal && legado && reconocimientos.error
        ? mensajeDeError(
            reconocimientos.error,
            'No se pudieron leer tus reconocimientos; las alertas se muestran completas.',
          )
        : null,
      // F4 (Codex #5): la foto trunca se DICE, no se disimula quitando botones.
      rol === 'supervisor' && !soloRoles && !fotoConfiable
        ? 'Tu cartera alcanzó el tope local de leads: Reconocer y Posponer quedan desactivados porque la foto de los grupos podría estar incompleta.'
        : null,
    ]
    return mensajes.filter((mensaje): mensaje is string => Boolean(mensaje))
  }, [
    legado,
    resumenSla.error,
    sesionAvisosReal,
    conversionActual.error,
    conversionAnterior.error,
    objetivosError,
    cumplimientoMetasError,
    estadoSla.error,
    fotoConfiable,
    reconocimientos.error,
    recordatorios.error,
    rol,
    sesionSupervisorReal,
    sesionVendedorReal,
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
    if (sesionAvisosReal) void resumenSla.refetch()
    if (rol === 'gerencia' && !yo?.demo) {
      void conversionActual.refetch()
      void conversionAnterior.refetch()
      // H10 (F3): «Actualizar» converge TODO lo que alimenta la campana de
      // gerencia — también metas y cumplimiento (la alerta individual), no
      // solo cuando fallaron. Sin esto, la individual vivía congelada desde
      // el arranque salvo error.
      void recargar()
      return
    }
    if (esRolOperativo(rol) && !yo?.demo) {
      setActualizandoOperativo(true)
      void Promise.all([
        recargar(),
        estadoSla.error ? estadoSla.recargar() : Promise.resolve(),
        // F3.1: Reintentar también reintenta los recordatorios caídos.
        sesionVendedorReal && recordatorios.error
          ? recordatorios.refetch()
          : Promise.resolve(),
        // F4 (Codex #3): Actualizar refresca el libro SIEMPRE (no solo caído)
        // — es la vía manual de converger con lo asentado en otra pestaña.
        sesionSupervisorReal && legado
          ? reconocimientos.refetch()
          : Promise.resolve(),
      ]).finally(() => setActualizandoOperativo(false))
    }
  }, [
    legado,
    resumenSla,
    sesionAvisosReal,
    conversionActual,
    conversionAnterior,
    recargar,
    reconocimientos,
    recordatorios,
    rol,
    sesionSupervisorReal,
    sesionVendedorReal,
    soloRoles,
    estadoSla,
    yo?.demo,
  ])

  const cargando = cargandoGerencia
    || actualizandoOperativo
    || (sesionAvisosReal && (resumenSla.isPending || resumenSla.isFetching))
    || (legado && !soloRoles && esRolOperativo(rol) && estadoSla.cargando)
    // isPending sería true PERPETUO con la query deshabilitada — el AND con
    // sesionVendedorReal (la misma condición de enabled) lo impide.
    || (sesionVendedorReal && (recordatorios.isPending || recordatorios.isFetching))
    || (sesionSupervisorReal && legado && (reconocimientos.isPending || reconocimientos.isFetching))
  const valor = useMemo<EstadoAlertasCRM>(() => ({
    alertas: visibles,
    pendientes,
    pospuestas,
    rol,
    cargando,
    errores,
    generadoEn: sesionAvisosReal && !legado ? (resumenSla.data?.calculado_en ?? null) : rol === 'gerencia'
      ? (conversionGerencia?.generado_en ?? null)
      : new Date(ahora).toISOString(),
    reintentar,
    reconocer,
  }), [
    legado,
    resumenSla.data?.calculado_en,
    sesionAvisosReal,
    visibles,
    pendientes,
    pospuestas,
    ahora,
    cargando,
    conversionGerencia?.generado_en,
    errores,
    reconocer,
    reintentar,
    rol,
  ])

  return <AlertasCRMContext.Provider value={valor}>{children}</AlertasCRMContext.Provider>
}
