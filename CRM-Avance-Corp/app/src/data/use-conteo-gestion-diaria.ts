// Conteo del día para el botón «GESTIÓN DIARIA» de la cabecera de «Hoy» del
// analista: cuántas gestiones hizo hoy, cuántas le quedan y cuántas se le
// pasaron, más si ya entró hoy a Gestión diaria (la insistencia del botón se
// calma). Es una LECTURA del día que ya sirve `useDiaAnalista(null, null)`
// (`crm.gestion_diaria_analista_fn`: hoy, el propio analista). Aquí se cuenta,
// no se decide negocio, y no se lanza ninguna consulta nueva.
//
// MAPEO sobre el payload `DiaAnalista` (lib/gestion-diaria-analista.ts):
//  · hechas     = `marcador.llamadas`: llamadas registradas HOY (contestadas +
//                 no contestadas). Es lo que Gestión diaria registra como
//                 gestión (F2, «resultado de la llamada»); WhatsApp y notas no
//                 cuentan, igual que en el marcador de la pantalla.
//  · vencidas   = leads de `cartera` cuya `proxima_tarea_en` ya pasó (grupo
//                 `tarea_vencida` de la cola del día).
//  · pendientes = el resto de la cola del día, sin las vencidas: los leads sin
//                 primer intento (`llamadas_ciclo === 0` y etapa `nuevo`), los
//                 acordados para HOY (`proxima_tarea_en` cae hoy en Lima) y los
//                 `sin_conversacion`. Un lead cuenta UNA sola vez, en su grupo
//                 más urgente (`ordenarColaDiaria`).
//  La cola se deriva con `filasDiariasDemo(cartera, ahora, dia)`: la misma
//  regla pura con la que la pantalla del analista arma su cola en demo, espejo
//  de los buckets de `cola_accion_v2_fn`. Se usa en los DOS modos porque el
//  botón cuenta, no lista, y la cabecera de «Hoy» no debe lanzar un segundo
//  RPC (la cola) cada minuto. En sesión real el destino ordena la cola que
//  devuelve el servidor, así que en casos límite las cifras pueden diferir en
//  uno; manda lo que el analista ve al entrar. `cartera` viene recortada a 500
//  leads abiertos (`cartera_truncada`), lejos de cualquier cartera real.
//
// DEMO: `useDiaAnalista` ya devuelve el espejo `diaAnalistaDesdeDemo` sobre el
// ámbito en memoria (leads, actividades y tareas del store), así que el mismo
// mapeo vale y el demo muestra cifras (sus tareas son relativas al reloj).
//
// VISITA: `localStorage` `crm:gd-visita:<yo.id>` = 'YYYY-MM-DD' Lima del último
// día en que entró. Todo en try/catch: puede no haber almacenamiento.
import { useCallback, useMemo, useState } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { filasDiariasDemo, type DiaAnalista } from '@/lib/gestion-diaria-analista'
import { useDiaAnalista } from './gestion-diaria-queries'

export interface ConteoGestionDiaria {
  /** Gestiones vencidas (ya pasó su hora). */
  vencidas: number
  /** Por hacer hoy, sin contar las vencidas. */
  pendientes: number
  /** Gestiones (llamadas) registradas hoy. */
  hechas: number
}

export interface ConteoGestionDiariaHook extends ConteoGestionDiaria {
  /** Ya entró hoy a Gestión diaria: el botón deja de insistir. */
  yaVisitoHoy: boolean
  /** Anota la visita de hoy (se llama al ir a Gestión diaria). */
  marcarVisita: () => void
  /** Primera carga del día en sesión real (en demo, nunca). */
  cargando: boolean
  /**
   * Hay un día del que contar. Es false mientras carga o si el RPC cayó: las
   * cifras van a 0 y NO deben leerse como «al día» (fail-closed, como el día).
   */
  disponible: boolean
}

/** Cuenta el día: hechas del marcador; vencidas y pendientes de la cola derivada de `cartera`. Función pura. */
export function conteoDelDia(dia: Pick<DiaAnalista, 'marcador' | 'cartera' | 'dia'>, ahora: number): ConteoGestionDiaria {
  const filas = filasDiariasDemo(dia.cartera, ahora, dia.dia)
  const vencidas = filas.filter((f) => f.grupo === 'tarea_vencida').length
  return { hechas: dia.marcador.llamadas, vencidas, pendientes: filas.length - vencidas }
}

export function claveVisita(analistaId: string): string {
  return `crm:gd-visita:${analistaId}`
}

function leerVisita(clave: string | null): string | null {
  if (clave === null) return null
  try {
    return window.localStorage.getItem(clave)
  } catch {
    return null
  }
}

function guardarVisita(clave: string | null, dia: string): void {
  if (clave === null) return
  try {
    window.localStorage.setItem(clave, dia)
  } catch {
    /* sin almacenamiento: el botón insistirá como si fuera la primera vez */
  }
}

export function useConteoGestionDiaria(): ConteoGestionDiariaHook {
  const { yo } = useAuth()
  const ahora = useAhora()
  const { dia, cargando } = useDiaAnalista(null, null)
  const hoy = fechaLima(ahora)
  const clave = yo ? claveVisita(yo.id) : null
  const conteo = useMemo(() => (dia === null ? null : conteoDelDia(dia, ahora)), [dia, ahora])
  // La visita se lee UNA vez por clave (cambiar de usuario relee) y se
  // actualiza al marcarla: sin efectos ni relecturas en cada render.
  const [visita, setVisita] = useState<{ clave: string | null; dia: string | null }>(() => ({ clave, dia: leerVisita(clave) }))
  const visitaDia = visita.clave === clave ? visita.dia : leerVisita(clave)
  const marcarVisita = useCallback(() => {
    guardarVisita(clave, hoy)
    setVisita({ clave, dia: hoy })
  }, [clave, hoy])
  return {
    vencidas: conteo?.vencidas ?? 0,
    pendientes: conteo?.pendientes ?? 0,
    hechas: conteo?.hechas ?? 0,
    yaVisitoHoy: visitaDia === hoy,
    marcarVisita,
    cargando,
    disponible: conteo !== null,
  }
}
