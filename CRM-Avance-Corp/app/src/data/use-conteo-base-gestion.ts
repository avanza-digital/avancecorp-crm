// Conteo para la línea «Base: N rellamadas para hoy» de «Hoy» del analista (F3 de la Base para gestión,
// 03/10/2026). Aquí se cuenta, no se decide negocio: la lectura es la MISMA que abre el destino
// (`screens/rescate/analista.tsx` → `useBaseGestion(…)` con `vendedorId = null`), con la misma clave
// `crmQueryKeys.baseGestion(null)`, así que la caché se comparte (una sola petición) y la línea dice lo
// que el analista va a ver arriba de su base («Para llamar hoy»).
//
// FUENTE (sesión real): `crm.obtener_base_gestion` sin parámetros (el servidor resuelve el actor).
//  · paraHoy  = filas con `rellamada_hoy === true`. El servidor la marca cuando la próxima llamada cae HOY
//               o antes en Lima (una rellamada de ayer que no se hizo sigue tocando hoy).
//  · vencidas = de esas, las que ya pasaron su HORA (`proxima_llamada_en < ahora`): la única razón para
//               pintar rojo en «Hoy». El reloj vivo (`useAhora`) las mueve sin esperar un refresco.
//
// FAIL-CLOSED (`disponible = false` ⇒ la línea NO se pinta; nunca un «0» falso ni un error en «Hoy»):
//  · sin sesión o rol que no es analista (`vendedor`): ni se pide;
//  · cargando, error (incluido 42501 SIN_PERMISO) o refresco fallido: TanStack conserva `data` cuando un
//    refetch falla y servir esa foto vieja como fresca sería mentir (igual que `use-conteo-gestion-diaria`);
//  · la foto es de OTRO día de Lima (la pestaña cruzó la medianoche): `rellamada_hoy` lo calculó el
//    servidor para aquel día; el refresco al volver a la pestaña la repone.
//
// DEMO: sin red. El espejo es el mismo del destino (`filasDemoBaseGestion` sobre los leads del store);
// sin rellamadas de hoy, la cifra es 0 y la pantalla no pinta nada.
import { useMemo } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { filasDemoBaseGestion, type FilaBaseGestion } from '@/lib/base-gestion'
import { useBaseGestion } from './crm-queries'

export interface ConteoRellamadas {
  /** Rellamadas que tocan hoy (incluidas las de días anteriores sin hacer). */
  paraHoy: number
  /** De ellas, las que ya pasaron su hora. */
  vencidas: number
}

export interface ConteoBaseGestion extends ConteoRellamadas {
  /** Hay cifra fiable de HOY. Sin ella las cifras van a 0 y la línea no debe pintarse. */
  disponible: boolean
}

const SIN_CIFRA: ConteoBaseGestion = { paraHoy: 0, vencidas: 0, disponible: false }

/** Cuenta las rellamadas de hoy y cuántas ya pasaron su hora. Función pura. */
export function contarRellamadasHoy(
  filas: readonly Pick<FilaBaseGestion, 'rellamada_hoy' | 'proxima_llamada_en'>[],
  ahora: number,
): ConteoRellamadas {
  let paraHoy = 0
  let vencidas = 0
  for (const f of filas) {
    if (f.rellamada_hoy !== true) continue
    paraHoy += 1
    const ms = f.proxima_llamada_en === null ? Number.NaN : Date.parse(f.proxima_llamada_en)
    if (Number.isFinite(ms) && ms < ahora) vencidas += 1
  }
  return { paraHoy, vencidas }
}

export function useConteoBaseGestion(): ConteoBaseGestion {
  const { yo } = useAuth()
  const { leads } = useCRMData()
  const ahora = useAhora()
  const esAnalista = yo != null && yo.rol === 'vendedor'
  const demo = yo?.demo === true
  // Misma clave que el destino (`vendedorId = null`): la base propia del analista.
  const consulta = useBaseGestion(esAnalista && !demo)
  const filasReales = consulta.error == null ? consulta.data : undefined
  const fotoDeHoy = filasReales !== undefined && fechaLima(consulta.dataUpdatedAt) === fechaLima(ahora)
  return useMemo<ConteoBaseGestion>(() => {
    if (!esAnalista || yo == null) return SIN_CIFRA
    if (demo) return { ...contarRellamadasHoy(filasDemoBaseGestion(leads, yo.id, ahora), ahora), disponible: true }
    if (filasReales === undefined || !fotoDeHoy) return SIN_CIFRA
    return { ...contarRellamadasHoy(filasReales, ahora), disponible: true }
  }, [ahora, demo, esAnalista, filasReales, fotoDeHoy, leads, yo])
}
