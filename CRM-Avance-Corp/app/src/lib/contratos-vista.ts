// Helpers PUROS de la pantalla Contratos (screens/contratos.tsx): búsqueda
// normalizada y filtro por estado sobre la cartera de contratos. Viven aparte
// de la pantalla para poder probarse sin montar React (contratos-vista.test.ts)
// — misma convención que lib/clientes-vista. La paginación NO se re-implementa
// aquí: es la compartida de lib/paginacion (la pantalla la aplica DESPUÉS de
// este filtrado, igual que Clientes y Cartera).
import type { EstadoContrato } from './clientes-tipos'
import { normalizar } from './clientes-vista'

/** Lo mínimo de una fila de contrato que necesita el filtrado (subset de ContratoRow). */
export interface ContratoBuscable {
  numero_contrato: string
  /** Del embed cliente:perfiles; null si la RLS no dejó verlo → no matchea. */
  cliente_nombre: string | null
  estado: EstadoContrato
}

/** 'todos' | uno de ESTADOS_CONTRATO (los 4 del CHECK del portal). */
export type FiltroEstado = 'todos' | EstadoContrato

/**
 * Búsqueda por N° de contrato o nombre del cliente (insensible a mayúsculas y
 * acentos — la MISMA normalizar de la cartera de clientes, no una copia) +
 * filtro por estado del ciclo de vida. Se componen en AND, como filtrarClientes.
 * El N° también se normaliza: cubre la numeración vieja alfanumérica
 * ('AC-2026-…') que aún vive en contratos históricos.
 */
export function filtrarContratos<T extends ContratoBuscable>(
  contratos: T[],
  q: string,
  fEstado: FiltroEstado,
): T[] {
  const nq = normalizar(q.trim())
  return contratos.filter((k) => {
    if (fEstado !== 'todos' && k.estado !== fEstado) return false
    if (!nq) return true
    if (normalizar(k.numero_contrato).includes(nq)) return true
    if (k.cliente_nombre != null && normalizar(k.cliente_nombre).includes(nq)) return true
    return false
  })
}
