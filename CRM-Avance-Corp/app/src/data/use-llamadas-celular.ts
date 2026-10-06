import { useCallback, useRef, useState } from 'react'
import { useInfiniteQuery, useQueryClient } from '@tanstack/react-query'
import { cambiarLlamadaCelular, listarLlamadasCelular, listarResueltasCelular, llamadasCelularKeys } from './llamadas-celular-api'
import type { Bandeja, ResueltasHoy } from '@/lib/llamadas-celular'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { demoPendientesCelular, demoResueltasHoyCelular } from '@/lib/demo-llamadas-celular'
import { etiquetaMotivoDescarte, numeroLegible, type FilaBandeja, type MotivoDescarte, type ResueltaHoy } from '@/lib/llamadas-celular'
import type { Lead } from '@/lib/tipos'

export interface FuenteLlamadasCelular {
  estadoPendientes: EstadoListaCelular
  estadoResueltas: EstadoListaCelular
  pendientes: readonly FilaBandeja[]
  resueltas: readonly ResueltaHoy[]
  /** evento_id con una acción en curso. */
  ocupado: string | null
  descartar: (fila: FilaBandeja, motivo: MotivoDescarte, detalle: string | null) => void
  elegirLead: (fila: FilaBandeja, lead: Lead) => void
}

export interface EstadoListaCelular {
  cargando: boolean
  error: boolean
  hayMas: boolean
  cargandoMas: boolean
  cargarMas: () => void
  reintentar: () => void
}
const LISTA_DEMO: EstadoListaCelular = { cargando: false, error: false, hayMas: false, cargandoMas: false, cargarMas: () => {}, reintentar: () => {} }
const quien = (fila: FilaBandeja) => fila.lead_nombre ?? numeroLegible(fila.numero)

export function useLlamadasCelular(): FuenteLlamadasCelular | null {
  const { yo } = useAuth()
  const demo = yo?.demo === true
  const cache = useQueryClient()
  const actor = yo?.id ?? ''
  const pendientes = useInfiniteQuery({
    queryKey: llamadasCelularKeys.pendientes(actor), enabled: !!actor && !demo,
    initialPageParam: null as Bandeja['siguiente'],
    queryFn: ({ pageParam, signal }) => listarLlamadasCelular(pageParam, signal),
    getNextPageParam: (pagina) => pagina.siguiente,
    refetchInterval: 30_000,
  })
  const resueltas = useInfiniteQuery({
    queryKey: llamadasCelularKeys.hoy(actor), enabled: !!actor && !demo,
    initialPageParam: null as ResueltasHoy['siguiente'],
    queryFn: ({ pageParam, signal }) => listarResueltasCelular(pageParam, signal),
    getNextPageParam: (pagina) => pagina.siguiente,
    refetchInterval: 30_000,
  })
  const [ocupado, setOcupado] = useState<string | null>(null)
  const enCurso = useRef(false)
  const cambiar = async (fila: FilaBandeja, accion: Parameters<typeof cambiarLlamadaCelular>[1]) => {
    if (enCurso.current) return
    enCurso.current = true
    setOcupado(fila.evento_id)
    try {
      await cambiarLlamadaCelular(fila.evento_id, accion)
      toast.success('lead' in accion ? 'Llamada asociada. Ahora registra su resultado.' : 'Llamada descartada. No cuenta como gestión del lead.')
    } catch {
      toast.error('No se pudo confirmar el cambio. La lista se actualizará; revisa su estado antes de reintentarlo.')
    } finally {
      await cache.invalidateQueries({ queryKey: llamadasCelularKeys.raiz })
      enCurso.current = false
      setOcupado(null)
    }
  }
  const [estado, setEstado] = useState(() => ({
    pendientes: demoPendientesCelular(Date.now()),
    resueltas: demoResueltasHoyCelular(Date.now()),
  }))

  const descartarDemo = useCallback((fila: FilaBandeja, motivo: MotivoDescarte, detalle: string | null) => {
    setEstado((e) => ({
      pendientes: e.pendientes.filter((f) => f.evento_id !== fila.evento_id),
      resueltas: [{
        evento_id: fila.evento_id, resuelto_en: new Date().toISOString(), recibido_en: fila.recibido_en, ocurrio_en: fila.ocurrio_en, numero: fila.numero,
        atencion: 'descartado_con_motivo', lead_id: fila.lead_id, lead_nombre: fila.lead_nombre, analista_id: fila.analista_id,
        es_propia: fila.es_propia, etiqueta: 'C1', actividad_id: null, resultado: null, deshecho: false, via: null,
        motivo_descarte: motivo, motivo_descarte_detalle: detalle,
      }, ...e.resueltas],
    }))
    toast.success(`Descartada: ${quien(fila)} (${etiquetaMotivoDescarte(motivo, detalle).toLowerCase()}). No cuenta como gestión del lead.`)
  }, [])

  const elegirLeadDemo = useCallback((fila: FilaBandeja, lead: Lead) => {
    setEstado((e) => ({
      ...e,
      pendientes: e.pendientes.map((f) => (f.evento_id === fila.evento_id
        ? { ...f, identificacion: 'identificado', atencion: 'requiere_resultado', lead_id: lead.id, lead_nombre: lead.nombre_completo }
        : f)),
    }))
    toast.success(`La llamada quedó asociada a ${lead.nombre_completo}. Ahora pide su resultado.`)
  }, [])

  if (!yo) return null
  if (demo) return { ...estado, ocupado: null, descartar: descartarDemo, elegirLead: elegirLeadDemo,
    estadoPendientes: LISTA_DEMO, estadoResueltas: LISTA_DEMO }
  return {
    pendientes: pendientes.data?.pages.flatMap((p) => p.filas) ?? [],
    resueltas: resueltas.data?.pages.flatMap((p) => p.filas) ?? [],
    ocupado,
    descartar: (fila, motivo, detalle) => { void cambiar(fila, { motivo, detalle }) },
    elegirLead: (fila, lead) => { void cambiar(fila, { lead: lead.id }) },
    estadoPendientes: { cargando: pendientes.isPending, error: pendientes.isError, hayMas: pendientes.hasNextPage,
      cargandoMas: pendientes.isFetchingNextPage, cargarMas: () => { void pendientes.fetchNextPage() }, reintentar: () => { void pendientes.refetch() } },
    estadoResueltas: { cargando: resueltas.isPending, error: resueltas.isError, hayMas: resueltas.hasNextPage,
      cargandoMas: resueltas.isFetchingNextPage, cargarMas: () => { void resueltas.fetchNextPage() }, reintentar: () => { void resueltas.refetch() } },
  }
}
