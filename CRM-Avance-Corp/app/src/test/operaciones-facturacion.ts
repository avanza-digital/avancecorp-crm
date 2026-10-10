import type { ListaOperacionesFacturacion, OperacionFacturacion, ParametrosOperacionesFacturacion } from '@/data/crm-api'
import type { FilaFacturacionDia } from '@/lib/facturacion'
import { filasDeCifra } from '@/screens/facturacion/parametros-de-cifra'

export const operacion: OperacionFacturacion = {
  n: 1, fecha: '2026-10-05', tipo: 'contrato_nuevo', moneda: 'PEN', monto: 25000,
  anulado: false, analista_id: 'ana', analista_nombre: 'Ana Prueba', supervisor_id: 'sup', supervisor_nombre: 'Supervisora Prueba',
  visible: true, cliente_nombre: 'Cliente Prueba', estado: 'vigente', contrato_id: 'contrato', numero_contrato: '2026-10-000001', cliente_id: 'cliente',
}
export const oculta: OperacionFacturacion = {
  n: 2, fecha: '2026-10-05', tipo: 'cooperativa', moneda: 'USD', monto: 1000, anulado: false,
  analista_id: 'ana', analista_nombre: 'Ana Prueba', supervisor_id: 'sup', supervisor_nombre: 'Supervisora Prueba',
  visible: false, cliente_nombre: 'Cliente de otro equipo',
}
export function respuesta(filas: OperacionFacturacion[] = [operacion], pagina = 1, tamano: 25 | 50 | 100 = 25): ListaOperacionesFacturacion {
  return { version: 1, pagina, tamano, total: filas.length,
    totales: (['PEN', 'USD'] as const).flatMap((moneda) => {
      const propias = filas.filter((f) => f.moneda === moneda)
      return propias.length ? [{ moneda, operaciones: propias.length, monto: propias.reduce((n, f) => n + f.monto, 0) }] : []
    }), filas: filas.slice((pagina - 1) * tamano, pagina * tamano) }
}
/** Adaptador exclusivo de tests de fase 1; las pruebas de frontera usan respuestas independientes. */
export function respuestaDeAgregados(filas: readonly FilaFacturacionDia[], p: ParametrosOperacionesFacturacion): ListaOperacionesFacturacion {
  let n = 0
  const ops = filasDeCifra(filas, p).flatMap((f) => Array.from({ length: f.operaciones }, () => ({ ...operacion,
    n: ++n, fecha: f.dia, moneda: f.moneda, tipo: f.tipo, monto: f.capital / f.operaciones,
    analista_id: f.analistaId, analista_nombre: f.analistaNombre, supervisor_id: f.supervisorId, supervisor_nombre: f.supervisorNombre,
  } as OperacionFacturacion)))
  return respuesta(ops, p.p_pagina, p.p_tamano as 25 | 50 | 100)
}
