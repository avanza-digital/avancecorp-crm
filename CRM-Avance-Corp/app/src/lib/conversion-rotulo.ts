// ─────────────────────────────────────────────────────────────────────────────
// EL RÓTULO DE LA CIFRA
//
// Cierra la última mitad del trabajo de unificación: que ninguna pantalla
// publique un porcentaje de conversión sin decir qué es.
//
// Desde la Ola 1b el servidor DECLARA de dónde salió cada cifra. Este módulo
// traduce esa declaración a una línea de apoyo, en castellano llano y sin
// siglas, que va debajo del número.
//
// La regla que se está rotulando (Miguel, 21/09/2026): mes calendario completo
// y sin filtro de fuente → la cifra la sirve `crm.conversion_mensual_fn`.
// Cualquier otro caso → cálculo en vivo, DECLARADO.
//
// Qué se dice y qué se calla:
//   · Cifra oficial de un mes ABIERTO → nada. Es lo normal; no hay noticia.
//   · Cifra oficial de un mes CERRADO → se dice, porque significa que ya no se
//     mueve aunque cambien los datos: es una foto.
//   · Recálculo en vivo → SIEMPRE se dice. Es la única forma de que dos
//     porcentajes distintos del mismo mes dejen de ser un misterio.
//   · Servidor previo (sin declaración) → nada. `undefined` no es «no se sabe»
//     para el usuario; es que ese servidor todavía no lo cuenta.
// ─────────────────────────────────────────────────────────────────────────────

/** Lo mínimo que hace falta declarar; encaja con el bloque `nucleo` y con
 *  `resumen.conversion` de distribución. */
// El `| undefined` explícito no es adorno: este proyecto compila con
// `exactOptionalPropertyTypes`, y sin él un payload que declare
// `es_mes_calendario?: boolean | undefined` —que es justo lo que produce el
// esquema valibot con `v.optional`— no encaja aquí.
export interface DeclaracionCifra {
  es_mes_calendario?: boolean | undefined
  fuente?: 'mensual' | 'rango_vivo' | undefined
  sellado?: boolean | null | undefined
  ajuste_aplicado?: boolean | undefined
}

/**
 * La línea de apoyo del número, o `null` cuando no hay nada que añadir.
 *
 * @param declaracion el bloque que publica la puerta (`nucleo`, o
 *   `resumen.conversion` en distribución). `null`/`undefined` → sin rótulo.
 * @param hayFiltroDeFuente `true` cuando la pantalla está mirando un origen
 *   concreto. Ese desglose SIEMPRE se calcula en vivo, aunque el bloque venga
 *   de un mes completo: la regla exige «sin filtro de fuente» para delegar.
 */
export function rotuloDeLaCifra(
  declaracion: DeclaracionCifra | null | undefined,
  hayFiltroDeFuente = false,
): string | null {
  if (declaracion == null) return null
  const { fuente, sellado } = declaracion
  // Servidor previo: no declara nada. No se inventa un rótulo.
  if (fuente == null) return null

  if (hayFiltroDeFuente) {
    return 'Calculado sobre el origen elegido; no es la cifra oficial del mes.'
  }
  if (fuente === 'mensual') {
    return sellado === true
      ? 'Cifra oficial del mes cerrado: ya no cambia aunque cambien los datos.'
      : null
  }
  // rango_vivo
  return declaracion.es_mes_calendario === true
    ? 'Calculado ahora, no pedido a la cifra oficial del mes.'
    : 'Calculado sobre el rango elegido; no es la cifra oficial de ningún mes.'
}

/**
 * `true` cuando lo que se está enseñando ES la cifra oficial del mes. Sirve
 * para que una pantalla decida si puede comparar contra una meta mensual sin
 * mezclar peras con manzanas.
 */
export function esLaCifraOficial(declaracion: DeclaracionCifra | null | undefined): boolean {
  return declaracion?.fuente === 'mensual'
}
