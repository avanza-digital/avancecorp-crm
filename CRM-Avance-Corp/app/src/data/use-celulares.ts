// Celulares (F4-c): la fuente de la tarjeta «Celulares». Real: dos consultas (salud y asignaciones) que se refrescan
// cada minuto y tres acciones que las invalidan. Demo: todo en memoria y con una clave ficticia que empieza por
// «demo» (decisión D2), para que el flujo entero se pueda ensayar sin base. La clave NUNCA entra en la caché ni en
// un toast: la acción la devuelve una vez y la pantalla la suelta al cerrar su ventana.
import { useCallback, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { llamadasCelularHabilitadas } from '@/lib/config'
import type { AsignacionCelular, CelularSalud, CredencialCelular, MotivoCierre } from '@/lib/celulares'
import { demoCelulares, demoClaveCelular } from '@/lib/demo-celulares'
import { CrmApiError } from './crm-api'
import {
  asignarCelular, celularesKeys, cerrarAsignacionCelular, listarAsignacionesCelulares, listarSaludCelulares,
  rotarCredencialCelular,
} from './llamadas-celular-api'

export interface EstadoConsultaCelulares {
  cargando: boolean
  error: boolean
  reintentar: () => void
}

export interface FuenteCelulares {
  /** Los celulares vigentes con su salud (crm.celulares_salud_fn). */
  vigentes: readonly CelularSalud[]
  /** Todas las asignaciones, vigentes y cerradas (crm.celulares_asignaciones_fn); la pantalla separa el historial. */
  asignaciones: readonly AsignacionCelular[]
  estado: EstadoConsultaCelulares
  /** Hay una acción en curso: los botones se bloquean (doble clic = una sola llamada). */
  ocupado: boolean
  demo: boolean
  /**
   * El interruptor de la integración del celular (lib/config, el mismo de la pestaña de F4-b): hasta que la base esté
   * aplicada en producción, las puertas no existen y la tarjeta no consulta nada. En la demo siempre está abierto.
   */
  habilitado: boolean
  asignar: (etiqueta: string, analistaId: string) => Promise<CredencialCelular>
  rotar: (etiqueta: string) => Promise<CredencialCelular>
  cerrar: (asignacionId: string, motivo: MotivoCierre) => Promise<void>
}

const ESTADO_DEMO: EstadoConsultaCelulares = { cargando: false, error: false, reintentar: () => {} }

export function useCelulares(): FuenteCelulares | null {
  const { yo } = useAuth()
  const demo = yo?.demo === true
  const habilitado = llamadasCelularHabilitadas(demo)
  const habilitada = !!yo && !demo && habilitado
  const cache = useQueryClient()
  const salud = useQuery({
    queryKey: celularesKeys.salud, enabled: habilitada, refetchInterval: 60_000,
    queryFn: ({ signal }) => listarSaludCelulares(signal),
  })
  const asignaciones = useQuery({
    queryKey: celularesKeys.asignaciones, enabled: habilitada, refetchInterval: 60_000,
    queryFn: ({ signal }) => listarAsignacionesCelulares(signal),
  })
  const [ocupado, setOcupado] = useState(false)
  const enCurso = useRef(false)
  const ejecutar = useCallback(async <T,>(accion: () => Promise<T>): Promise<T> => {
    if (enCurso.current) throw new CrmApiError('Hay una acción en curso. Espera a que termine.', 'EN_CURSO')
    enCurso.current = true
    setOcupado(true)
    try {
      return await accion()
    } finally {
      await cache.invalidateQueries({ queryKey: celularesKeys.raiz })
      enCurso.current = false
      setOcupado(false)
    }
  }, [cache])

  // ── Demo: en memoria, con las mismas reglas visibles que el servidor ─────────────────────────────────────────────
  const [memoria, setMemoria] = useState(() => demoCelulares(Date.now()))
  const [ocupadoDemo, setOcupadoDemo] = useState(false)
  const demoAsignar = useCallback(async (etiqueta: string, analistaId: string): Promise<CredencialCelular> => {
    const repetido = memoria.vigentes.find((c) => c.etiqueta === etiqueta)
    if (repetido) throw new CrmApiError(`${etiqueta} ya está asignado: ciérralo o rota su credencial`, '23505')
    const analista = memoria.catalogo.find((a) => a.id === analistaId)
    if (!analista) throw new CrmApiError('El celular se asigna a un analista o supervisor activo', '22023')
    const ahora = new Date().toISOString()
    const id = `demo-asig-${etiqueta}-${Date.now()}`
    const nueva: CelularSalud = {
      asignacion_id: id, etiqueta, analista_id: analistaId, analista_nombre: analista.nombre, vigente_desde: ahora,
      estado_latido: 'nunca', horas_sin_latido: null, reloj_desfasado: false, version_macro: null, eventos_en_cola: null,
    }
    setMemoria((m) => ({
      ...m,
      vigentes: [...m.vigentes, nueva].sort((a, b) => a.etiqueta.localeCompare(b.etiqueta, 'es', { numeric: true })),
      asignaciones: [{ asignacion_id: id, etiqueta, analista_id: analistaId, analista_nombre: analista.nombre, vigente_desde: ahora, vigente_hasta: null, motivo_cierre: null }, ...m.asignaciones],
    }))
    return { asignacion_id: id, etiqueta, analista_id: analistaId, credencial: demoClaveCelular() }
  }, [memoria])
  const demoRotar = useCallback(async (etiqueta: string): Promise<CredencialCelular> => {
    const vigente = memoria.vigentes.find((c) => c.etiqueta === etiqueta)
    if (!vigente) throw new CrmApiError('Ese celular no tiene una asignación vigente', '22023')
    if (!memoria.catalogo.some((a) => a.id === vigente.analista_id)) {
      throw new CrmApiError('El analista del celular ya no está activo: ciérralo y asígnalo a otro', '22023')
    }
    const ahora = new Date().toISOString()
    const id = `demo-asig-${etiqueta}-${Date.now()}`
    setMemoria((m) => ({
      ...m,
      vigentes: m.vigentes.map((c) => c.asignacion_id === vigente.asignacion_id
        ? { ...c, asignacion_id: id, vigente_desde: ahora, estado_latido: 'nunca', horas_sin_latido: null, reloj_desfasado: false, version_macro: null, eventos_en_cola: null }
        : c),
      asignaciones: [
        { asignacion_id: id, etiqueta, analista_id: vigente.analista_id, analista_nombre: vigente.analista_nombre, vigente_desde: ahora, vigente_hasta: null, motivo_cierre: null },
        ...m.asignaciones.map((a) => a.asignacion_id === vigente.asignacion_id ? { ...a, vigente_hasta: ahora, motivo_cierre: 'rotacion' } : a),
      ],
    }))
    return { asignacion_id: id, etiqueta, analista_id: vigente.analista_id, credencial: demoClaveCelular(), anterior_id: vigente.asignacion_id }
  }, [memoria])
  const demoCerrar = useCallback(async (asignacionId: string, motivo: MotivoCierre): Promise<void> => {
    const ahora = new Date().toISOString()
    setMemoria((m) => ({
      ...m,
      vigentes: m.vigentes.filter((c) => c.asignacion_id !== asignacionId),
      asignaciones: m.asignaciones.map((a) => a.asignacion_id === asignacionId ? { ...a, vigente_hasta: ahora, motivo_cierre: motivo } : a),
    }))
  }, [])
  const envolverDemo = useCallback(<A extends unknown[], T>(accion: (...args: A) => Promise<T>) => async (...args: A): Promise<T> => {
    setOcupadoDemo(true)
    try {
      // Un respiro para que se vea el estado «en curso», como en la vida real.
      await new Promise((r) => setTimeout(r, 250))
      return await accion(...args)
    } finally {
      setOcupadoDemo(false)
    }
  }, [])

  if (!yo) return null
  if (demo) {
    return {
      vigentes: memoria.vigentes, asignaciones: memoria.asignaciones, estado: ESTADO_DEMO, ocupado: ocupadoDemo, demo: true, habilitado: true,
      asignar: envolverDemo(demoAsignar), rotar: envolverDemo(demoRotar), cerrar: envolverDemo(demoCerrar),
    }
  }
  return {
    vigentes: salud.data ?? [],
    asignaciones: asignaciones.data ?? [],
    estado: {
      // Con el interruptor cerrado no hay consulta en vuelo: la pantalla muestra el aviso, no «cargando».
      cargando: habilitado && (salud.isPending || asignaciones.isPending),
      error: salud.isError || asignaciones.isError,
      reintentar: () => { void salud.refetch(); void asignaciones.refetch() },
    },
    ocupado,
    demo: false,
    habilitado,
    asignar: (etiqueta, analistaId) => ejecutar(() => asignarCelular(etiqueta, analistaId)),
    rotar: (etiqueta) => ejecutar(() => rotarCredencialCelular(etiqueta)),
    cerrar: (asignacionId, motivo) => ejecutar(() => cerrarAsignacionCelular(asignacionId, motivo)),
  }
}
