// Conteo del día para el botón «GESTIÓN DIARIA» de la cabecera de «Hoy» del
// analista: cuántas gestiones hizo hoy, cuántas le quedan y cuántas se le
// pasaron, más si ya entró hoy a Gestión diaria (la insistencia del botón se
// calma). Aquí se cuenta, no se decide negocio: las dos lecturas son las MISMAS
// que abre la pantalla de destino (`screens/gestion-diaria/analista.tsx`), con
// las mismas claves de consulta, así que la caché se comparte y el botón dice
// exactamente lo que el analista va a ver al entrar.
//
// FUENTES (sesión real):
//  · `useDiaAnalista(null, null)` → `crm.gestion_diaria_analista_fn` (hoy, el
//    propio analista): `marcador` y `cartera` (señales por lead abierto).
//  · `useColaDiaPagina({ senal: 'todas', etapa: null, analista_id: null }, null,
//    LIMITE_COLA_DIA, …)` → `crm.cola_accion_v3_fn` (desde el 29/09/2026), la
//    cola del día tal cual la ordena el destino: leads y tareas de CLIENTES.
//
// MAPEO:
//  · hechas     = `marcador.llamadas`: llamadas registradas HOY (contestadas +
//                 no contestadas). Es lo que Gestión diaria registra como
//                 gestión (F2, «resultado de la llamada»); WhatsApp y notas no
//                 cuentan, igual que en el marcador de la pantalla.
//  · vencidas   = filas con `grupo === 'tarea_vencida'` de
//                 `ordenarColaDiaria(pagina.items, dia.cartera)` (bucket
//                 `tarea_vencida` de la cola, de leads o de clientes).
//  · pendientes = el resto de esas filas: `primera_atencion`, `tarea_hoy` y
//                 `sin_conversacion` (este último lo añade `ordenarColaDiaria`
//                 desde `cartera[].sin_conversacion`). Un lead cuenta UNA sola
//                 vez, en su grupo más urgente; un cliente cuenta una vez POR
//                 TAREA, como una fila de la pantalla.
//
// CUÁNDO HAY CIFRAS (`disponible`): solo con el día de HOY en Lima
// (`dia.dia === fechaLima(ahora)`: el reloj pudo cruzar la medianoche antes del
// refetch), con la cartera entera (`cartera_truncada === false`; el servidor la
// recorta a 500 leads abiertos) y, en sesión real, con la cola llegada sin
// error y SIN recortar (`hay_mas === false`). Si la página de LIMITE_COLA_DIA se
// queda corta NO se usan `pagina.totales`: cuentan SEÑALES de la cola
// (`pendientes`, `seguimientos_pendientes`, `revisiones`…), no los grupos del
// día, así que no cuadran con lo que muestra el destino; antes que una cifra
// dudosa, el botón va sin cifras. Sin `disponible`, las cifras son 0 y el
// botón NO debe leerse como «al día» (fail-closed, como el día y la cola).
//
// DEMO: la cola v3 no corre (`useColaDiaPagina` va deshabilitada) y
// `useDiaAnalista` devuelve el espejo `diaAnalistaDesdeDemo`; las filas salen
// de `filasDiariasDemo(cartera, ahora, dia, tareas, yo)`, exactamente como en el destino.
//
// VISITA: `localStorage` `crm:gd-visita:<yo.id>` = 'YYYY-MM-DD' Lima del último
// día en que entró. Todo en try/catch: puede no haber almacenamiento.
import { useCallback, useMemo, useState } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  FILTROS_COLA_DIA,
  LIMITE_COLA_DIA,
  filasDiariasDemo,
  ordenarColaDiaria,
  type DiaAnalista,
  type FilaDiaria,
  type TareaClienteDemo,
} from '@/lib/gestion-diaria-analista'
import type { ColaDiaPagina } from '@/lib/sla-operacion'
import { useDiaAnalista } from './gestion-diaria-queries'
import { useColaDiaPagina } from './sla-operacion-queries'

// La MISMA página que abre Gestión diaria del analista: `FILTROS_COLA_DIA` y
// `LIMITE_COLA_DIA` viven en `lib/gestion-diaria-analista` y los usan los dos
// consumidores, así la clave de TanStack coincide y la consulta se comparte.

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
  /** Primera carga del día o de la cola en sesión real (en demo, nunca). */
  cargando: boolean
  /**
   * Hay cifras de HOY completas (día de hoy, cartera entera y, en real, cola
   * llegada sin error ni recorte). Es false mientras carga, si algo cayó o si
   * el día no es el de hoy: las cifras van a 0 y NO deben leerse como «al día».
   */
  disponible: boolean
}

function contarFilas(filas: readonly FilaDiaria[]): Pick<ConteoGestionDiaria, 'vencidas' | 'pendientes'> {
  const vencidas = filas.filter((f) => f.grupo === 'tarea_vencida').length
  return { vencidas, pendientes: filas.length - vencidas }
}

/** Sesión real: la cola del servidor ordenada como en el destino. Función pura. */
export function conteoDelDia(
  dia: Pick<DiaAnalista, 'marcador' | 'cartera'>,
  pagina: Pick<ColaDiaPagina, 'items'>,
): ConteoGestionDiaria {
  return { hechas: dia.marcador.llamadas, ...contarFilas(ordenarColaDiaria(pagina.items, dia.cartera)) }
}

/** Demo: el espejo sobre las señales de la cartera y las tareas de clientes (la cola v3 no corre). Función pura. */
export function conteoDelDiaDemo(
  dia: Pick<DiaAnalista, 'marcador' | 'cartera' | 'dia'>,
  ahora: number,
  tareas: readonly TareaClienteDemo[] = [],
  analistaId: string | null = null,
): ConteoGestionDiaria {
  return { hechas: dia.marcador.llamadas, ...contarFilas(filasDiariasDemo(dia.cartera, ahora, dia.dia, tareas, analistaId)) }
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
  const demo = yo?.demo === true
  const { tareas } = useCRMData()
  const { dia, cargando: diaCargando } = useDiaAnalista(null, null)
  const cola = useColaDiaPagina(FILTROS_COLA_DIA, null, LIMITE_COLA_DIA, !demo)
  const hoy = fechaLima(ahora)
  const clave = yo ? claveVisita(yo.id) : null
  // Fail-closed también en refetch: TanStack conserva `data` cuando un refetch
  // falla y servir esa foto vieja como fresca sería mentir (igual que el destino).
  const pagina = cola.error == null ? cola.data : undefined
  const colaCargando = !demo && cola.error == null && cola.data === undefined
  const conteo = useMemo<ConteoGestionDiaria | null>(() => {
    if (dia === null || dia.dia !== hoy || dia.cartera_truncada) return null
    if (demo) return conteoDelDiaDemo(dia, ahora, tareas, yo?.id ?? null)
    if (pagina === undefined || pagina.hay_mas) return null
    return conteoDelDia(dia, pagina)
  }, [ahora, demo, dia, hoy, pagina, tareas, yo?.id])
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
    cargando: diaCargando || colaCargando,
    disponible: conteo !== null,
  }
}
