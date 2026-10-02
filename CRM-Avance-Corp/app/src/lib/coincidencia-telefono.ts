// lib/coincidencia-telefono.ts — ¿a qué lead corresponde el número que trajo el
// celular? (F1.3 del plan «Llamadas desde el celular al CRM», 30/09/2026).
//
// En la base conviven DOS formas canónicas (propuesta de ajuste #2, verificada
// en las migraciones 20260709000001 y 20260826182000):
//  · `crm.leads.telefono` la escribe el trigger con `private.normalizar_telefono`:
//    9 dígitos → `+51` + dígitos; cualquier otra cosa → `+` + dígitos tal cual.
//    Un fijo de Lima tecleado como 014457890 quedó guardado como +51014457890.
//  · `telefono_alternativo` la escribe `private.canonizar_contacto` (E.164 de
//    verdad: celular +519…, fijo +51 + 8 dígitos, internacional). En el cliente
//    es `reconocerTelefono` (lib/validacion.ts).
// Por eso el número capturado se canoniza con las dos reglas y se compara,
// completo y exacto, contra las dos columnas. Nunca se recorta a nueve dígitos
// ni se «corrige» por parecido: un dígito distinto es otro número.
import { MIN_DIGITOS_BUSQUEDA } from './cartera-keyset'
import { soloDigitos } from './telefono'
import { TERMINALES_K, type Lead } from './tipos'
import { reconocerTelefono } from './validacion'

/** Lo que hace falta de un lead para decidir si es el del número. */
export type LeadCandidato = Pick<Lead, 'id' | 'nombre_completo' | 'telefono' | 'telefono_alternativo' | 'etapa' | 'activo' | 'vendedor_id'>

export type Coincidencia<T extends LeadCandidato = LeadCandidato> =
  /** Un solo lead vivo con el número. `terminales`: descartados o convertidos con el mismo número (contexto, no candidatos). */
  | { estado: 'unico'; numero: string; lead: T; terminales: T[] }
  /** Varios leads vivos: decide la persona. */
  | { estado: 'ambiguo'; numero: string; leads: T[] }
  /** Ningún lead vivo. `reconocido`: si el número al menos tiene forma de teléfono. */
  | { estado: 'sin_coincidencia'; numero: string; reconocido: boolean; terminales: T[] }
  /** El servidor devolvió una página llena: puede haber más y una página no demuestra unicidad. */
  | { estado: 'incompleto'; numero: string; leads: T[] }
  /** Sin dígitos (oculto, vacío): no hay nada que comparar. */
  | { estado: 'invalido'; numero: string }
  /** Falla operativa al consultar; distinta de «sin coincidencia». */
  | { estado: 'error'; numero: string; mensaje: string }

/** La regla del trigger de `crm.leads.telefono` (`private.normalizar_telefono`). */
export function canonicoLegado(valor: string): string | null {
  const digitos = soloDigitos(valor)
  if (!digitos) return null
  return digitos.length === 9 ? `+51${digitos}` : `+${digitos}`
}

/**
 * Todas las formas en que ESTE número puede estar guardado: la E.164 (el
 * alternativo y los leads nuevos), la legado del trigger y, para un fijo
 * peruano, la legado de cómo se teclea un fijo —con el 0 de larga distancia,
 * 014457890 → +51014457890—, que es como quedaron los fijos históricos.
 */
export function formasCanonicas(numero: string): ReadonlySet<string> {
  const formas = new Set<string>()
  const reconocido = reconocerTelefono(numero)
  if (reconocido) {
    formas.add(reconocido.e164)
    if (reconocido.clase === 'fijo_pe') {
      const conCero = canonicoLegado(`0${reconocido.e164.slice(3)}`)
      if (conCero) formas.add(conCero)
    }
  }
  const legado = canonicoLegado(numero)
  if (legado) formas.add(legado)
  return formas
}

/** El número para mostrar y guardar: E.164 si se reconoce; si no, la forma legado; si no, tal cual. */
export function numeroCanonico(numero: string): string {
  return reconocerTelefono(numero)?.e164 ?? canonicoLegado(numero) ?? numero.trim()
}

/** ¿Alguna de las dos columnas del lead es exactamente una de las formas? */
export function leadCoincide(lead: LeadCandidato, formas: ReadonlySet<string>): boolean {
  return formas.has(lead.telefono) || (lead.telefono_alternativo != null && formas.has(lead.telefono_alternativo))
}

/**
 * Los dígitos con los que pedir candidatos al servidor (`cartera_pagina_fn`
 * busca por subcadena en telefono, telefono_alternativo y dni). Para un número
 * peruano van los NACIONALES —sin el 51— para que salgan las dos formas
 * guardadas; para el resto, todos. `null` si no llegan al mínimo del servidor.
 */
export function digitosParaBuscar(numero: string): string | null {
  const reconocido = reconocerTelefono(numero)
  const digitos = reconocido && reconocido.clase !== 'internacional' ? reconocido.e164.slice(3) : soloDigitos(numero)
  return digitos.length >= MIN_DIGITOS_BUSQUEDA ? digitos : null
}

/**
 * Decide con los candidatos que devolvió el servidor. `completa` dice si la
 * recuperación trajo TODO lo que casaba con los dígitos: si vino una página
 * llena puede haber más, y una página no demuestra unicidad (plan, sección 3).
 */
export function clasificarCoincidencia<T extends LeadCandidato>(numero: string, candidatos: readonly T[], completa: boolean): Coincidencia<T> {
  const canon = numeroCanonico(numero)
  const formas = formasCanonicas(numero)
  if (formas.size === 0) return { estado: 'invalido', numero: canon }
  // Contar leads DISTINTOS, no campos: el mismo número en las dos columnas de un lead es un lead.
  const porId = new Map<string, T>()
  for (const l of candidatos) if (leadCoincide(l, formas) && !porId.has(l.id)) porId.set(l.id, l)
  const todos = [...porId.values()]
  // Solo cuentan los leads vivos; los terminales (descartado, convertido) son
  // contexto —«número reciclado», «existe como cliente»—, no candidatos.
  const vivos = todos.filter((l) => l.activo && !TERMINALES_K.has(l.etapa))
  const terminales = todos.filter((l) => !vivos.includes(l))
  if (vivos.length > 1) return { estado: 'ambiguo', numero: canon, leads: vivos }
  if (!completa) return { estado: 'incompleto', numero: canon, leads: vivos }
  const unico = vivos[0]
  if (unico) return { estado: 'unico', numero: canon, lead: unico, terminales }
  return { estado: 'sin_coincidencia', numero: canon, reconocido: reconocerTelefono(numero) !== null, terminales }
}
