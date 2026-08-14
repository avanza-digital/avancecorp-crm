// Helper PURO de Mi cartera: parte la cartera ya agrupada por cliente en
// BLOQUES POR MES, para que el asesor pueda ver qué cerró en cada uno en vez de
// una lista única con todo mezclado (pedido de Miguel, 2026-08-14).
//
// Vive aparte de la pantalla para probarse sin montar React (cartera-meses.test.ts)
// y no importa nada de UI.
import { fechaLima } from './agenda-derivada'
import { ordenDeCartera, resumirCliente, type GrupoCartera } from './cartera-vista'
import { duenoDeCartera } from './clientes-vista'
import type { ContratoRow } from './clientes-tipos'

/** Cubo de los clientes que todavía no tienen ningún contrato. */
export const CLAVE_SIN_CONTRATOS = 'sin-contratos'
/** Cubo defensivo: contrato cuya fecha de registro no se puede leer. */
export const CLAVE_SIN_FECHA = 'sin-fecha'

/**
 * Nombres LARGOS y en mayúscula inicial, para la cabecera del bloque. No se
 * reutiliza `MESES` de agenda-derivada porque ese es el rótulo corto de una
 * celda de calendario ('Ago') y aquí el bloque es un titular ('Agosto 2026').
 */
const MESES_LARGOS = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
]

/** Un bloque de la cartera: un mes (o uno de los dos cubos) con sus clientes. */
export interface MesCartera {
  /** 'YYYY-MM' | CLAVE_SIN_FECHA | CLAVE_SIN_CONTRATOS. Clave estable del bloque
   *  — la usan el plegado y la paginación, así que no puede ser el índice. */
  clave: string
  /** 'Agosto 2026' | 'Sin fecha de registro' | 'Clientes sin contrato'. */
  etiqueta: string
  /** El cliente con SOLO sus contratos de este mes y el resumen recalculado. */
  grupos: GrupoCartera[]
  /** Contratos cerrados en el mes, DE CUALQUIER ESTADO (ver nota de abajo). */
  contratos: number
  capitalPen: number
  capitalUsd: number
  /** De esos, cuántos los registró alguien distinto del asesor del cliente. */
  registradosPorOtro: number
}

function redondear2(n: number): number {
  return Math.round(n * 100) / 100
}

/**
 * Mes 'YYYY-MM' del instante en LIMA, no en UTC. Un contrato registrado el 31
 * de julio a las 20:00 de Lima es 1 de agosto en UTC: sin esta conversión el
 * contrato saltaría de bloque él solo y el total del mes mentiría. Reutiliza
 * `fechaLima`, que ya resuelve exactamente esto para la agenda.
 *
 * Devuelve null si la fecha no se puede leer: `new Date(NaN).toISOString()`
 * LANZA, y una excepción aquí dejaría toda la pantalla en blanco.
 */
export function mesLima(iso: string | null | undefined): string | null {
  if (iso == null || iso === '') return null
  const ms = Date.parse(iso)
  if (Number.isNaN(ms)) return null
  return fechaLima(ms).slice(0, 7)
}

/**
 * ¿Este contrato lo registró alguien distinto del asesor del cliente? Importa
 * porque Miguel decidió (2026-08-14) que el bloque cuente TODO contrato de sus
 * clientes, mientras que la CUOTA solo le paga por los que registró él. Cuando
 * un mes incluye alguno de estos, la cabecera lo dice: sin eso, el asesor vería
 * un capital aquí y otro distinto en Hoy sin ninguna explicación.
 *
 * Un `creado_por` nulo (contrato legado) NO cuenta como ajeno: no se sabe.
 */
export function registradoPorOtro(contrato: ContratoRow, grupo: GrupoCartera): boolean {
  const dueno = duenoDeCartera(grupo.cliente)
  if (dueno == null || contrato.creado_por == null) return false
  return contrato.creado_por !== dueno
}

/** Rótulo del bloque a partir de su clave. */
function etiquetaDe(clave: string): string {
  if (clave === CLAVE_SIN_CONTRATOS) return 'Clientes sin contrato'
  if (clave === CLAVE_SIN_FECHA) return 'Sin fecha de registro'
  const anio = clave.slice(0, 4)
  const mes = Number(clave.slice(5, 7))
  return `${MESES_LARGOS[mes - 1] ?? clave} ${anio}`
}

/**
 * Los cubos van SIEMPRE al final, y entre meses manda el más reciente. Se
 * comparan como texto porque 'YYYY-MM' ya ordena bien: no hace falta parsear.
 */
function ordenDeBloque(a: string, b: string): number {
  const peso = (c: string) => (c === CLAVE_SIN_CONTRATOS ? 2 : c === CLAVE_SIN_FECHA ? 1 : 0)
  return peso(a) - peso(b) || (a > b ? -1 : a < b ? 1 : 0)
}

/**
 * Parte la cartera en bloques por mes de CIERRE.
 *
 * · **La fecha que manda es `creado_en`** (cuándo se registró el contrato), no
 *   `fecha_inicio`: es la misma ventana con la que se mide la cuota del mes, y
 *   `fecha_inicio` sí puede retro-datarse — con ella, dos contratos idénticos
 *   acabarían en meses distintos según quién los mire.
 *
 * · **Un cliente aparece en CADA mes en el que cerró**, con los contratos de ese
 *   mes y su resumen recalculado sobre ellos (`resumirCliente`).
 *
 * · **El total del bloque cuenta los contratos de CUALQUIER estado**, porque la
 *   pregunta es «qué cerré en agosto» y un contrato que ya venció se cerró
 *   igual. Ojo: la columna «Capital invertido» de cada fila sigue midiendo lo
 *   que está VIVO (contratos activos), así que en un mes viejo el total de la
 *   cabecera puede ser mayor que la suma de las filas. Son dos preguntas
 *   distintas y cada una lleva su rótulo.
 *
 * · **PEN y USD nunca se suman**: dos acumuladores separados.
 *
 * Recibe los grupos YA filtrados por la pantalla y con `contratos` recortado a
 * los que pasan los filtros vivos, para que el bloque cuente exactamente lo que
 * se ve. Un cliente sin ningún contrato visible cae en CLAVE_SIN_CONTRATOS.
 */
export function agruparPorMes(grupos: GrupoCartera[]): MesCartera[] {
  const porClave = new Map<string, { grupos: GrupoCartera[]; contratos: number; pen: number; usd: number; otros: number }>()

  const bloque = (clave: string) => {
    let b = porClave.get(clave)
    if (!b) {
      b = { grupos: [], contratos: 0, pen: 0, usd: 0, otros: 0 }
      porClave.set(clave, b)
    }
    return b
  }

  for (const g of grupos) {
    if (g.contratos.length === 0) {
      bloque(CLAVE_SIN_CONTRATOS).grupos.push(g)
      continue
    }
    // Un cliente puede tener contratos de varios meses: se reparte, y en cada
    // bloque entra una COPIA del grupo con solo los contratos de ese mes.
    const porMes = new Map<string, ContratoRow[]>()
    for (const c of g.contratos) {
      const clave = mesLima(c.creado_en) ?? CLAVE_SIN_FECHA
      const lista = porMes.get(clave)
      if (lista) lista.push(c)
      else porMes.set(clave, [c])
    }
    for (const [clave, contratos] of porMes) {
      const b = bloque(clave)
      b.grupos.push(resumirCliente(g.cliente, contratos))
      for (const c of contratos) {
        b.contratos += 1
        const cap = Number(c.capital) || 0 // numeric-como-string de PostgREST
        if (c.moneda === 'USD') b.usd += cap
        else b.pen += cap
        if (registradoPorOtro(c, g)) b.otros += 1
      }
    }
  }

  return [...porClave.entries()]
    .map(([clave, b]) => ({
      clave,
      etiqueta: etiquetaDe(clave),
      grupos: [...b.grupos].sort(ordenDeCartera),
      contratos: b.contratos,
      capitalPen: redondear2(b.pen),
      capitalUsd: redondear2(b.usd),
      registradosPorOtro: b.otros,
    }))
    .sort((a, b) => ordenDeBloque(a.clave, b.clave))
}
