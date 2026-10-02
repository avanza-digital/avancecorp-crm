import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import {
  TAMANO_PAGINA_CARTERA,
  concatenarPaginas,
  filtrarCarteraLocal,
  ordenarCarteraLocal,
  type FiltrosCarteraLocal,
} from '@/lib/cartera-keyset'
import { enVentanaOperativa, resumenCarteraDesdeAmbito, type ResumenCartera } from '@/lib/resumen-cartera'
import { contarPotencial } from '@/lib/potencial'
import { leerPotencialDemo, suscribirPotencialDemo } from '@/lib/potencial-demo'
import type { Lead } from '@/lib/tipos'
import { CrmApiError, type FiltrosCartera, type ResumenCarteraFiltrada } from './crm-api'
import { crmQueryKeys, useCarteraInfinita } from './crm-queries'
import { rangoFechaCarteraValido } from '@/lib/filtro-fecha-cartera'
import { fechaLima } from '@/lib/agenda-derivada'

export interface CarteraPaginada {
  /** Páginas ya cargadas, concatenadas y sin repetidos. */
  leads: Lead[]
  resumenDemo?: ResumenCartera | undefined
  /** Con el potencial encendido trae además `potencial`: los conteos por nivel. */
  resumen?: ResumenCarteraFiltrada | undefined
  hayMas: boolean
  /** Primera página en vuelo (la tabla aún no tiene nada que pintar). */
  cargando: boolean
  cargandoMas: boolean
  error: unknown
  cargarMas: () => void
  recargar: () => Promise<void>
}

/**
 * Une la RPC `crm.cartera_pagina_fn` (cursor keyset, F2) con su espejo demo.
 *
 * En sesión real el servidor decide QUÉ filas y en qué orden; el navegador solo
 * concatena páginas. En demo no se toca la red (fail-closed) y las mismas
 * reglas —filtros, orden, tamaño de página— se aplican sobre el ámbito VIVO del
 * store, de modo que crear un lead en demo lo hace aparecer donde aparecería en
 * real.
 *
 * Lo que este hook NO hace: filtrar en el cliente lo ya cargado. Con keyset eso
 * produce vacíos falsos («no hay resultados» cuando solo no están en las
 * páginas descargadas), y por eso los filtros viajan al servidor y cada
 * combinación es su propia lista.
 */
export function useCarteraPaginada(
  leadsDelAmbito: readonly Lead[],
  filtros: FiltrosCartera & FiltrosCarteraLocal,
): CarteraPaginada {
  const { yo } = useAuth()
  const esDemo = Boolean(yo?.demo)
  const sesionReal = Boolean(yo && !yo.demo)

  const etapa = filtros.etapa ?? 'todas'
  const vendedorId = filtros.vendedorId ?? 'todos'
  const texto = filtros.texto ?? ''
  const origen = filtros.origen ?? 'todos'
  const procedencia = filtros.procedencia ?? 'todas'
  const reasignados = filtros.reasignados ?? false
  // Gestión vigente (columnas «Nuevo»/«Gestionado» del Pipeline). Solo recorta
  // en sesión real: el espejo demo de este hook conoce leads, no timelines, y
  // ahí la reparte quien tiene las actividades (lib/pipeline-columnas).
  const gestion = filtros.gestion
  // Potencial del lead (fila «Por potencial» de Leads). En sesión real lo
  // recorta y lo cuenta el servidor; en demo, el espejo de abajo con las marcas
  // en memoria.
  const potencial = filtros.potencial
  const desde = filtros.recepcion?.desde ?? (esDemo ? filtros.recepcionDemo?.desde : undefined)
  const hasta = filtros.recepcion?.hasta ?? (esDemo ? filtros.recepcionDemo?.hasta : undefined)
  const filtrosEstables = useMemo<FiltrosCartera & FiltrosCarteraLocal>(
    () => ({ etapa, vendedorId, texto, integrada: true,
      // El origen solo viaja cuando recorta: «todos» es el valor neutro y no se manda.
      ...(origen !== 'todos' ? { origen } : {}),
      ...(procedencia !== 'todas' ? { procedencia } : {}),
      ...(reasignados ? { reasignados: true } : {}),
      ...(gestion ? { gestion } : {}),
      ...(potencial ? { potencial } : {}),
      ...(desde != null && hasta != null ? { recepcion: { desde, hasta }, recepcionDemo: { desde, hasta } } : {}) }),
    [etapa, vendedorId, texto, origen, procedencia, reasignados, gestion, potencial, desde, hasta],
  )

  const rangoValido = rangoFechaCarteraValido(filtrosEstables.recepcion ?? null, fechaLima(Date.now()))
  const consulta = useCarteraInfinita(sesionReal && rangoValido, filtrosEstables)

  // El servidor apagó el potencial con el filtro puesto. Las OTRAS listas en
  // caché se pidieron cuando estaba encendido y aún traen sus conteos: si se
  // sirvieran al soltar el filtro, la fila «Por potencial» seguiría ofreciendo
  // algo que el servidor va a rechazar. Se retiran (solo las que nadie mira:
  // la que falló es de quien la tiene en pantalla) para que se pidan de nuevo.
  const cliente = useQueryClient()
  const potencialApagado = consulta.error instanceof CrmApiError && consulta.error.code === 'POTENCIAL_APAGADO'
  useEffect(() => {
    if (potencialApagado) cliente.removeQueries({ queryKey: crmQueryKeys.carteraPaginas(), type: 'inactive' })
  }, [potencialApagado, cliente])

  // ── Espejo demo: mismas reglas, paginación en memoria ──
  const [paginasDemo, setPaginasDemo] = useState(1)
  // Cambiar de filtro EMPIEZA una lista nueva: conservar el número de páginas
  // dejaría la vista mostrando 150 resultados de una búsqueda que acaba de
  // cambiar (y en real el cursor viejo ni siquiera sería válido).
  useEffect(() => { setPaginasDemo(1) }, [etapa, vendedorId, texto, origen, procedencia, reasignados, gestion, potencial, desde, hasta])

  // Como en el servidor: primero todos los DEMÁS filtros (`previa`), de ahí salen
  // los conteos por potencial, y después el recorte por potencial.
  const previaDemo = useMemo(
    () => (esDemo ? ordenarCarteraLocal(filtrarCarteraLocal(leadsDelAmbito, filtrosEstables)
      .filter((lead) => filtrosEstables.recepcion ? lead.activo : enVentanaOperativa(lead, Date.now()))) : []),
    [esDemo, filtrosEstables, leadsDelAmbito],
  )
  const marcasDemo = useSyncExternalStore(suscribirPotencialDemo, leerPotencialDemo, leerPotencialDemo)
  const filtradosDemo = useMemo(() => {
    if (!potencial) return previaDemo
    return previaDemo.filter((lead) => (marcasDemo.get(lead.id)?.nivel ?? 'sin_marca') === potencial)
  }, [previaDemo, marcasDemo, potencial])
  const resumenDemo = useMemo(() => esDemo
    ? resumenCarteraDesdeAmbito(filtradosDemo, [], Date.now(), Boolean(desde)) : undefined, [esDemo, filtradosDemo, desde])
  const conteosDemo = useMemo(() => esDemo
    ? contarPotencial(previaDemo.map((lead) => lead.id), (id) => marcasDemo.get(id)?.nivel, potencial ?? null)
    : undefined, [esDemo, previaDemo, marcasDemo, potencial])

  const leadsReales = useMemo(
    () => concatenarPaginas((consulta.data?.pages ?? []).map((p) => p.items)),
    [consulta.data],
  )

  const cargarMas = useCallback(() => {
    if (esDemo) {
      setPaginasDemo((n) => n + 1)
      return
    }
    if (consulta.hasNextPage && !consulta.isFetchingNextPage) void consulta.fetchNextPage()
  }, [consulta, esDemo])

  const recargar = useCallback(async () => { await consulta.refetch() }, [consulta])

  if (esDemo) {
    const tope = paginasDemo * TAMANO_PAGINA_CARTERA
    return {
      leads: filtradosDemo.slice(0, tope),
      resumenDemo,
      resumen: resumenDemo && conteosDemo ? { ...resumenDemo, potencial: conteosDemo } : resumenDemo,
      hayMas: filtradosDemo.length > tope,
      cargando: false,
      cargandoMas: false,
      error: null,
      cargarMas,
      recargar,
    }
  }

  return {
    leads: leadsReales,
    resumen: consulta.data?.pages[0]?.resumen,
    // `hasNextPage` lo decide el cursor que devolvió el SERVIDOR, no el tamaño
    // de la última página. Con error se fuerza a false: prometer más páginas
    // que no se pueden pedir es peor que decir que ahí termina lo cargado — el
    // aviso de degradación es quien explica que la lista está incompleta.
    hayMas: consulta.hasNextPage && !consulta.error,
    cargando: rangoValido && consulta.isPending,
    cargandoMas: consulta.isFetchingNextPage,
    error: consulta.error,
    cargarMas,
    recargar,
  }
}
