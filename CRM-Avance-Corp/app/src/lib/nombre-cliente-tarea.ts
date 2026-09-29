/**
 * El nombre del cliente que se lee en el TÍTULO de una tarea de postventa
 * («Llamar a ROSA DÍAZ» → «ROSA DÍAZ»). Solo sirve cuando no hay otra fuente:
 * el cierre de tarea sin lead y el espejo DEMO de la cola del día. Una sola
 * regla para los dos (en producción el nombre lo da el servidor).
 */
export function nombreClienteDeTitulo(titulo: string): string {
  return titulo.replace(/^(Llamar a|Escribir a|Reuni[oó]n con|Cita con|Gestionar a)\s+/i, '').trim() || 'cliente'
}
