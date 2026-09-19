// Exportación CSV de la casa, extraída de citas/avance-mensual.tsx (Fase 0 de
// Gestión Diaria) para que el registro crudo de actividad y cualquier tabla
// futura exporten con las MISMAS defensas:
// - BOM UTF-8 para que Excel en Windows lea las tildes;
// - anti-inyección de fórmulas: un valor que empieza por = + @ - o espacio se
//   antepone con comilla simple (Excel/Sheets lo tratarían como fórmula);
// - comillas dobles escapadas por duplicado; separador coma; fin de línea CRLF.
// La función pura `csvDe` se prueba sola; `descargarCsv` solo toca el DOM.

export type CeldaCsv = string | number | boolean | null | undefined

export function celdaCsv(valor: CeldaCsv): string {
  return '"' + String(valor ?? '').replace(/^[\s=+@-]/, (m) => `'${m}`).replaceAll('"', '""') + '"'
}

/** Texto CSV completo (con BOM) a partir de cabecera y filas. */
export function csvDe(cabecera: readonly string[], filas: readonly (readonly CeldaCsv[])[]): string {
  return '﻿' + [cabecera, ...filas].map((fila) => fila.map(celdaCsv).join(',')).join('\r\n')
}

/**
 * Dispara la descarga en el navegador. Devuelve `true` si el clic se emitió.
 * El `revokeObjectURL` se difiere un segundo: Safari cancela la descarga si la
 * URL se revoca en el mismo tick.
 */
export function descargarCsv(nombreArchivo: string, contenido: string): boolean {
  const url = URL.createObjectURL(new Blob([contenido], { type: 'text/csv;charset=utf-8;' }))
  const enlace = document.createElement('a')
  try {
    enlace.href = url
    enlace.download = nombreArchivo.endsWith('.csv') ? nombreArchivo : `${nombreArchivo}.csv`
    document.body.append(enlace)
    enlace.click()
    return true
  } catch {
    return false
  } finally {
    enlace.remove()
    window.setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
}
