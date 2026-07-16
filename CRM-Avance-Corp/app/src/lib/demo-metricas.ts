// Agregados DEMO para las gráficas de gerencia — derivados EN CLIENTE de las
// fixtures existentes (lib/demo-clientes + lib/demo), con el MISMO shape de
// filas que las RPCs crm.metricas_*_fn. Nada se inventa: cada número sale de
// los contratos/cronogramas/clientes ficticios que ya alimentan Clientes y
// Contratos en demo (regla A3: cero series fabricadas).
//
// Este módulo SOLO se carga por import() dinámico gated (patrón store.tsx ↔
// demo.ts): sus imports estáticos de fixtures viajan en el mismo subgrafo demo
// y Rolldown los elimina de cualquier build de producción. Cero red: una
// sesión demo no tiene Supabase.
import type {
  FilaAltasAnalista,
  FilaCapitalMes,
  FilaPagosMes,
  FilaVencimientos,
} from './metricas'
import type { Moneda } from './format'
import { formatDateLocal } from './cronograma'
import { CLIENTES_DEMO, CONTRATOS_DEMO, CRONOGRAMAS_DEMO } from './demo-clientes'
import { EQUIPO_DEMO } from './demo'

// ── Meses (mismo formato 'YYYY-MM-01' que devuelven las RPCs) ──────────────────

/** 'YYYY-MM-01' desde un date-only 'YYYY-MM-DD' (sin Date: cero líos de TZ). */
function mesDeFechaLocal(fecha: string): string {
  return `${fecha.slice(0, 7)}-01`
}

/** 'YYYY-MM-01' LOCAL desde un timestamp ISO (los creado_en de las fixtures
 *  nacen de Date.now(), así que el mes local es el mes "real" del demo). */
function mesDeTimestamp(iso: string): string {
  const d = new Date(iso)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

// ── (a) Capital colocado por mes/moneda/categoría (espejo de la RPC) ───────────
export function demoMetricasCapitalMes(): FilaCapitalMes[] {
  const buckets = new Map<string, FilaCapitalMes>()
  for (const contrato of CONTRATOS_DEMO) {
    const mes = mesDeFechaLocal(contrato.fecha_inicio)
    const clave = `${mes}|${contrato.moneda}|${contrato.categoria ?? ''}`
    const fila = buckets.get(clave) ?? {
      mes,
      moneda: contrato.moneda,
      categoria: contrato.categoria,
      contratos: 0,
      capital_colocado: 0,
    }
    fila.contratos += 1
    fila.capital_colocado += contrato.capital
    buckets.set(clave, fila)
  }
  return [...buckets.values()]
}

// ── (b) Pagos por mes/moneda/tipo/estado (la moneda vive en el contrato) ────
export function demoMetricasPagosMes(): FilaPagosMes[] {
  const monedaPorContrato = new Map<string, Moneda>(
    CONTRATOS_DEMO.map((c) => [c.id, c.moneda]),
  )
  const buckets = new Map<string, FilaPagosMes>()
  for (const [contratoId, cuotas] of Object.entries(CRONOGRAMAS_DEMO)) {
    const moneda = monedaPorContrato.get(contratoId)
    if (!moneda) continue
    for (const cuota of cuotas) {
      const mes = mesDeFechaLocal(cuota.fecha_programada)
      const clave = `${mes}|${moneda}|${cuota.tipo}|${cuota.estado}`
      const fila = buckets.get(clave) ?? {
        mes,
        moneda,
        tipo: cuota.tipo,
        estado: cuota.estado,
        cuotas: 0,
        monto_programado: 0,
        monto_pagado: 0,
      }
      fila.cuotas += 1
      fila.monto_programado += cuota.monto_programado
      fila.monto_pagado += cuota.monto_pagado ?? 0
      buckets.set(clave, fila)
    }
  }
  return [...buckets.values()]
}

// ── (c) Altas de clientes por analista/mes (asesor de la cartera demo) ─────────
export function demoMetricasAltasAnalista(): FilaAltasAnalista[] {
  const nombrePorId = new Map(EQUIPO_DEMO.map((m) => [m.perfil_id, m.nombre_completo]))
  const buckets = new Map<string, FilaAltasAnalista>()
  for (const cliente of CLIENTES_DEMO) {
    const analistaId = cliente.asesor_perfil_id
    if (!analistaId) continue
    const mes = mesDeTimestamp(cliente.creado_en)
    const clave = `${mes}|${analistaId}`
    const fila = buckets.get(clave) ?? {
      mes,
      analista_id: analistaId,
      analista_nombre: nombrePorId.get(analistaId) ?? analistaId,
      altas: 0,
    }
    fila.altas += 1
    buckets.set(clave, fila)
  }
  return [...buckets.values()]
}

// ── (d) Vencimientos dentro de p_dias por mes/moneda (espejo de la RPC) ────────
export function demoMetricasVencimientos(pDias = 90): FilaVencimientos[] {
  const hoy = new Date()
  const desde = formatDateLocal(hoy)
  const hasta = formatDateLocal(
    new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() + pDias),
  )
  const buckets = new Map<string, FilaVencimientos>()
  for (const contrato of CONTRATOS_DEMO) {
    // date-only 'YYYY-MM-DD': la comparación lexicográfica ES la cronológica.
    if (contrato.fecha_vencimiento < desde || contrato.fecha_vencimiento > hasta) continue
    const mes = mesDeFechaLocal(contrato.fecha_vencimiento)
    const clave = `${mes}|${contrato.moneda}`
    const fila = buckets.get(clave) ?? {
      mes,
      moneda: contrato.moneda,
      contratos_por_vencer: 0,
      capital_por_vencer: 0,
    }
    fila.contratos_por_vencer += 1
    fila.capital_por_vencer += contrato.capital
    buckets.set(clave, fila)
  }
  return [...buckets.values()]
}
