import type { Etapa, Lead } from './tipos'
import { coincideFechaRecepcionDemo, type RangoFechaCartera } from './filtro-fecha-cartera'

/**
 * Reglas de la cartera paginada por cursor keyset (F2), en un solo sitio.
 *
 * El SERVIDOR (`crm.cartera_pagina_fn`) es quien pagina y filtra en sesión
 * real. Este módulo existe por dos motivos:
 *
 *  1. el modo demo no tiene Supabase y debe pintar la MISMA película sobre el
 *     ámbito vivo del store — si el espejo filtrara con otras reglas, la demo
 *     enseñaría un producto que no existe;
 *  2. la normalización del texto de búsqueda tiene que ser idéntica en los dos
 *     lados: el servidor RECHAZA (22023) un texto de un solo carácter, así que
 *     quien decide si el filtro viaja es esta función, no la pantalla.
 */

export const TAMANO_PAGINA_CARTERA = 50

/** Por debajo de 2 caracteres el trigram no puede servir el patrón `%x%`. */
export const MIN_TEXTO_BUSQUEDA = 2
/**
 * Teléfono y DNI solo entran a partir de 3 dígitos. Es la regla que ya aplicaba
 * `listarLeads` y una DIVERGENCIA DELIBERADA respecto del filtro local viejo,
 * que reaccionaba desde el primer dígito: con la cartera grande, `%9%` sobre
 * dos columnas es un escaneo completo en cada tecla.
 */
export const MIN_DIGITOS_BUSQUEDA = 3

const MAX_BUSQUEDA = 80

export interface FiltrosCarteraLocal {
  etapa?: Etapa | 'todas'
  vendedorId?: string | 'todos' | 'sin_asignar'
  texto?: string
  /** Vista previa local: el servidor real conserva su contrato hasta integrar el ledger. */
  recepcionDemo?: RangoFechaCartera | null
}

/**
 * Allowlist pequeña (letras, números, espacios y guiones) heredada de la época
 * en que el texto viajaba dentro de la mini-sintaxis `.or()` de PostgREST. Con
 * la RPC tipada ya no hay superficie de inyección que cerrar, pero la
 * normalización se conserva porque define QUÉ se busca: los dígitos se guardan
 * aparte para teléfono/DNI.
 */
export function normalizarBusquedaCartera(valor: string | undefined): {
  texto: string
  digitos: string
} {
  const crudo = (valor ?? '').normalize('NFKC').trim().slice(0, MAX_BUSQUEDA)
  const texto = crudo
    .replace(/[^\p{L}\p{N}\s-]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const digitos = crudo.replace(/\D/g, '').slice(0, 15)
  return { texto, digitos }
}

/** ¿El filtro de texto llega al servidor? (por debajo del mínimo, no se aplica). */
export function textoBuscable(valor: string | undefined): string | null {
  const { texto } = normalizarBusquedaCartera(valor)
  return texto.length >= MIN_TEXTO_BUSQUEDA ? texto : null
}

/** Espejo del predicado de texto del servidor: nombre, y teléfono/DNI con 3+ dígitos. */
export function coincideTextoCartera(lead: Lead, valor: string | undefined): boolean {
  const buscable = textoBuscable(valor)
  if (buscable === null) return true
  const { digitos } = normalizarBusquedaCartera(valor)
  if (lead.nombre_completo.toLowerCase().includes(buscable.toLowerCase())) return true
  if (digitos.length >= MIN_DIGITOS_BUSQUEDA) {
    if (lead.telefono.includes(digitos)) return true
    if ((lead.telefono_alternativo ?? '').includes(digitos)) return true
    if ((lead.dni ?? '').includes(digitos)) return true
  }
  return false
}

/** Espejo demo del WHERE de `crm.cartera_pagina_fn` (sin la RLS: el store ya la aplicó). */
export function filtrarCarteraLocal(
  leads: readonly Lead[],
  filtros: FiltrosCarteraLocal,
): Lead[] {
  return leads.filter((l) => {
    // Soft-delete: fuera de la cartera operativa, igual que en el servidor. Un
    // lead DESCARTADO no es un lead borrado — conserva `activo` y sigue aquí
    // con su motivo; lo que este filtro saca es lo que cerró la cola global.
    if (l.activo === false) return false
    if (!coincideFechaRecepcionDemo(l, filtros.recepcionDemo)) return false
    if (filtros.etapa && filtros.etapa !== 'todas' && l.etapa !== filtros.etapa) return false
    if (filtros.vendedorId === 'sin_asignar') {
      if (l.vendedor_id != null) return false
    } else if (filtros.vendedorId && filtros.vendedorId !== 'todos'
      && l.vendedor_id !== filtros.vendedorId) {
      return false
    }
    return coincideTextoCartera(l, filtros.texto)
  })
}

/**
 * Mismo orden que el keyset del servidor: `actualizado_en desc, id asc`. El
 * desempate por `id` no es decorativo — es lo que hace que dos leads con el
 * mismo sello no se repitan ni se pierdan entre páginas. En demo
 * `actualizado_en` puede no venir; se degrada a `creado_en` (que sí es
 * obligatorio) en vez de mandar la fila al fondo.
 */
export function ordenarCarteraLocal(leads: readonly Lead[]): Lead[] {
  return [...leads].sort((a, b) => {
    const sa = a.actualizado_en ?? a.creado_en
    const sb = b.actualizado_en ?? b.creado_en
    if (sa !== sb) return sa < sb ? 1 : -1
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  })
}

/**
 * Concatena páginas descartando repetidos por `id`. Un lead editado mientras se
 * hace scroll cambia su `actualizado_en` y puede saltar a la primera página: sin
 * este dedup aparecería DOS veces en la lista (React también avisaría por la
 * key duplicada). No se congela un snapshot del servidor a propósito — ver el
 * plan F2: se acepta que un lead editado migre de página.
 *
 * El caso simétrico —un lead que salta hacia DELANTE del cursor y por tanto no
 * aparece en las páginas siguientes— es INDETECTABLE desde aquí y también se
 * acepta: para cerrarlo haría falta un snapshot del servidor, es decir, servir
 * datos viejos. Quien acaba de tocar ese lead es quien lo mueve, y lo tiene
 * delante en la primera página.
 */
export function concatenarPaginas(paginas: readonly (readonly Lead[])[]): Lead[] {
  const vistos = new Set<string>()
  const salida: Lead[] = []
  for (const pagina of paginas) {
    for (const lead of pagina) {
      if (vistos.has(lead.id)) continue
      vistos.add(lead.id)
      salida.push(lead)
    }
  }
  return salida
}
