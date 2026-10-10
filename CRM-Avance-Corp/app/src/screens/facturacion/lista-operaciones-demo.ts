import type { ListaOperacionesFacturacion, OperacionFacturacion, ParametrosOperacionesFacturacion } from '@/data/crm-api'
import type { FilaFacturacionDia } from '@/lib/facturacion'
import { filasDeCifra, totalesDeCifra } from './parametros-de-cifra'

/** Solo DEMO: reparte sus agregados ficticios conservando cada céntimo. Nunca consulta clientes reales. */
export function listaOperacionesDemo(filas: readonly FilaFacturacionDia[], p: ParametrosOperacionesFacturacion): ListaOperacionesFacturacion {
  const operaciones: OperacionFacturacion[] = []
  for (const f of filasDeCifra(filas, p).sort((a, b) => a.dia.localeCompare(b.dia) || a.tipo.localeCompare(b.tipo))) {
    const centimos = Math.round(f.capital * 100)
    const parte = Math.floor(centimos / f.operaciones)
    for (let i = 0; i < f.operaciones; i += 1) {
      const n = operaciones.length + 1
      const comun = { n, fecha: f.dia, moneda: f.moneda, monto: (parte + (i < centimos % f.operaciones ? 1 : 0)) / 100,
        anulado: false, analista_id: f.analistaId, analista_nombre: f.analistaNombre,
        supervisor_id: f.supervisorId, supervisor_nombre: f.supervisorNombre, visible: true as const,
        cliente_nombre: `Cliente de ejemplo ${n}`, estado: 'vigente' }
      operaciones.push(f.tipo === 'cooperativa' ? { ...comun, tipo: 'cooperativa', cierre_externo_id: `demo-${n}`, cooperativa: 'Cooperativa de ejemplo', lead_id: null }
        : { ...comun, tipo: f.tipo as 'contrato_nuevo' | 'contrato_upgrade' | 'contrato_renovacion', contrato_id: `demo-${n}`, numero_contrato: `Ejemplo ${n}`, cliente_id: null })
    }
  }
  const pagina = p.p_pagina ?? 1
  const tamano = (p.p_tamano ?? 25) as 25 | 50 | 100
  return { version: 1, pagina, tamano, total: operaciones.length, totales: totalesDeCifra(filas, p), filas: operaciones.slice((pagina - 1) * tamano, pagina * tamano) }
}
