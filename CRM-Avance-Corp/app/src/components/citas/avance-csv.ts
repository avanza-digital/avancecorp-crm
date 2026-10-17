import type { AvanceCitas } from './avance'

/** Pantalla y CSV comparten el modelo ya calculado y la referencia de su corte. */
export function csvAvanceCitas(resumen: AvanceCitas, mes: string, datos: 'CRM' | 'Ejemplo', fuenteTc: string | undefined, fechaTc: string) {
  const valorado = resumen.valoracion
  const celda = (valor: unknown) => '"' + String(valor ?? '').replace(/^[\s=+@-]/, m => `'${m}`).replaceAll('"', '""') + '"'
  const cabecera = ['Mes', 'Analista', 'Supervisor', 'Leads asignados', 'Citas registradas', 'Citas por lead', 'Cumplimiento %', 'Entrevistas', 'Entrevistas %', 'Clientes de entrevistas', 'Depósito %', 'Ticket del mes', 'Cierre proyectado', 'Moneda', 'Versión de reglas', 'Datos', 'Clientes del periodo', 'Personas entrevistadas', 'Capital real PEN', 'Capital real USD', 'TC USD a PEN', 'Fuente del TC', 'Corte del TC', 'Estado del ticket', 'Estado de proyección', 'Clientes con capital', 'Contratos nuevos', 'Upgrades', 'Renovaciones', 'Cooperativas', 'Convertidos sin capital',
    'Capital confirmado en soles', 'Régimen del capital', 'Referencia del corte de capital', 'Fecha del corte de capital', 'Cobertura del ámbito CRM', 'Operaciones por incorporar del ámbito CRM', 'Ventas pendientes del ámbito CRM', 'PEN pendiente del ámbito CRM', 'USD pendiente del ámbito CRM']
  const filas = resumen.filas.map(f => [mes, f.nombre, f.supervisor, f.leads, f.citas, f.promedio, f.cumplimiento, f.entrevistas, f.tasaEntrevistas === null ? null : f.tasaEntrevistas * 100, f.clientes, f.conversion === null ? null : f.conversion * 100, f.ticket, f.proyeccion, 'PEN', resumen.version, datos, f.clientesPeriodo, f.unicas, f.capitalPen, f.capitalUsd,
    f.capitalUsd > 0 ? resumen.tc : null, valorado ? 'Valoraciones por operación' : f.capitalUsd > 0 && resumen.tc !== null ? fuenteTc : null,
    !valorado && f.capitalUsd > 0 && resumen.tc !== null ? fechaTc : null, f.motivoTicket ?? 'Calculado', f.motivoProyeccion ?? 'Calculado',
    f.clientesTicket, f.operaciones.nuevos, f.operaciones.upgrades, f.operaciones.renovaciones, f.operaciones.cooperativas, f.sinContrato,
    f.capital, valorado ? 'TC fijado por venta' : 'TC mensual legado', valorado?.corte_id, valorado?.cobertura.corte,
    valorado?.cobertura.estado, valorado?.cobertura.por_incorporar.cantidad, valorado?.cobertura.pendientes.cantidad,
    valorado?.cobertura.pendientes.pen, valorado?.cobertura.pendientes.usd])
  return '\uFEFF' + [cabecera, ...filas].map(r => r.map(celda).join(',')).join('\r\n')
}
