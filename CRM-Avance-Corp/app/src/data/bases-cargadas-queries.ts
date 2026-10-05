// Lecturas y escrituras de «Bases cargadas» (F5) con TanStack Query. Todo cuelga del prefijo de la base para gestión
// (que cuelga de `leads()`): repartir, recoger o cargar refresca a la vez la pestaña «Bases» y «Gestión de la base», y
// cualquier escritura sobre un lead (un intento, una reactivación) refresca el seguimiento de las bases.
import { useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { crearFuenteDemoBases } from '@/lib/bases-cargadas-demo'
import type { CifraSeguimiento, EstadoContactos } from '@/lib/bases-cargadas'
import { crmQueryKeys } from './crm-queries'
import { FUENTE_REAL, type FuenteBases } from './bases-cargadas-fuente'

type Modo = 'real' | 'demo'

export const clavesBases = {
  raiz: (modo: Modo) => [...crmQueryKeys.baseGestionPrefijo(), 'bases', modo] as const,
  lista: (modo: Modo) => [...clavesBases.raiz(modo), 'lista'] as const,
  seguimiento: (modo: Modo, baseId: string) => [...clavesBases.raiz(modo), 'seguimiento', baseId] as const,
  detalle: (modo: Modo, baseId: string, analistaId: string | null, cifra: CifraSeguimiento) => [...clavesBases.raiz(modo), 'detalle', baseId, analistaId, cifra] as const,
  contactos: (modo: Modo, baseId: string, estado: EstadoContactos) => [...clavesBases.raiz(modo), 'contactos', baseId, estado] as const,
}

export interface PuertasBases {
  fuente: FuenteBases
  modo: Modo
  /** Hay sesión: las lecturas pueden salir. */
  activa: boolean
}

/** La fuente de la sesión: el servidor, o el espejo en memoria si es la demo (fail-closed: la demo nunca toca la red). */
export function usePuertasBases(): PuertasBases {
  const { yo } = useAuth()
  const { leads, equipo } = useCRMData()
  const demo = yo?.demo === true
  // El espejo demo guarda sus bases por supervisor: recrearlo al cambiar los leads no las pierde.
  const fuenteDemo = useMemo(() => (demo && yo ? crearFuenteDemoBases({ leads, equipo, yo }) : null), [demo, yo, leads, equipo])
  return { fuente: fuenteDemo ?? FUENTE_REAL, modo: demo ? 'demo' : 'real', activa: yo !== null }
}

const LECTURA = { staleTime: 30_000, refetchOnWindowFocus: 'always' as const }

/** La hoja de bases (B10). `data === null` = el servidor aún no tiene la lectura: «disponible pronto». */
export function useSeguimientoBases(p: PuertasBases) {
  return useQuery({
    queryKey: clavesBases.lista(p.modo),
    queryFn: ({ signal }) => p.fuente.seguimientoBases(signal),
    enabled: p.activa,
    ...LECTURA,
  })
}

/** El seguimiento por analista de una base (B10). */
export function useSeguimientoBase(p: PuertasBases, baseId: string | null) {
  return useQuery({
    queryKey: clavesBases.seguimiento(p.modo, baseId ?? ''),
    queryFn: ({ signal }) => p.fuente.seguimientoBase(baseId ?? '', signal),
    enabled: p.activa && baseId !== null,
    ...LECTURA,
  })
}

/** Lo que hay detrás de una cifra; solo mientras el detalle está abierto. */
export function useSeguimientoBaseDetalle(p: PuertasBases, abierto: { baseId: string; analistaId: string | null; cifra: CifraSeguimiento } | null) {
  return useQuery({
    queryKey: clavesBases.detalle(p.modo, abierto?.baseId ?? '', abierto?.analistaId ?? null, abierto?.cifra ?? 'total'),
    queryFn: ({ signal }) => p.fuente.seguimientoBaseDetalle(abierto?.baseId ?? '', abierto?.analistaId ?? null, abierto?.cifra ?? 'total', signal),
    enabled: p.activa && abierto !== null,
    staleTime: 30_000,
  })
}

/** Los contactos de una base para el reparto por selección (B9). `data === null` = B9 aún no está en el servidor. */
export function useContactosDeBase(p: PuertasBases, baseId: string | null, estado: EstadoContactos) {
  return useQuery({
    queryKey: clavesBases.contactos(p.modo, baseId ?? '', estado),
    queryFn: ({ signal }) => p.fuente.contactosDeBase(baseId ?? '', estado, signal),
    enabled: p.activa && baseId !== null,
    ...LECTURA,
    // Al pasar de «sin repartir» a «todos», la lista anterior se queda mientras llega la otra.
    placeholderData: (anterior) => anterior,
  })
}

/** Tras escribir en una base: la pestaña «Bases» y «Gestión de la base» (los contactos repartidos salen allí). También
 *  al final de una carga de archivo (que no es UNA mutación: la lleva su propio proceso por lotes). */
export function useInvalidarBases() {
  const queryClient = useQueryClient()
  return () => queryClient.invalidateQueries({ queryKey: crmQueryKeys.baseGestionPrefijo() })
}

export function useArmarBase(p: PuertasBases) {
  const invalidar = useInvalidarBases()
  return useMutation({ mutationFn: (e: Parameters<FuenteBases['armarBaseCrm']>[0]) => p.fuente.armarBaseCrm(e), onSuccess: invalidar })
}

export function useRepartirBase(p: PuertasBases) {
  const invalidar = useInvalidarBases()
  return useMutation({ mutationFn: (e: Parameters<FuenteBases['repartirBase']>[0]) => p.fuente.repartirBase(e), onSuccess: invalidar })
}

export function useRecogerDeBase(p: PuertasBases) {
  const invalidar = useInvalidarBases()
  return useMutation({ mutationFn: (e: Parameters<FuenteBases['recogerDeBase']>[0]) => p.fuente.recogerDeBase(e), onSuccess: invalidar })
}

