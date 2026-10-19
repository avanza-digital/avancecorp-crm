/** Descarga un CSV ya armado. Devuelve false si el navegador no pudo generarlo. */
export function descargarCsv(nombre: string, contenido: string): boolean {
  try {
    const url = URL.createObjectURL(new Blob([contenido], { type: 'text/csv;charset=utf-8;' }))
    const enlace = document.createElement('a')
    try { enlace.href = url; enlace.download = nombre; document.body.append(enlace); enlace.click() }
    finally { enlace.remove(); window.setTimeout(() => URL.revokeObjectURL(url), 1000) }
    return true
  } catch { return false }
}
