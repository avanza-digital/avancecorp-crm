// Generación de cronograma de pagos — PORT FIEL de public_html/js/admin/contratos.js
// (mismo cálculo que usa el portal para crear contratos). Se mantiene idéntico
// para que el CRM y el portal produzcan EXACTAMENTE el mismo cronograma; la RPC
// public.crear_contrato es la que persiste. Si cambia la regla en el portal,
// cambiar aquí también (espejo consciente, como documento-core ↔ documento.ts).

export type ModalidadContrato = 'mensual' | 'trimestral' | 'semestral' | 'anual'
export type TipoInteres = 'simple' | 'compuesto'
export type CategoriaContrato = 'nuevo' | 'renovacion' | 'upgrade'
export type TipoCuota = 'cuota' | 'retorno' | 'devolucion'

export interface CuotaCronograma {
  numero_cuota: number
  fecha_programada: string // YYYY-MM-DD
  monto_programado: number
  estado: 'pendiente'
  tipo: TipoCuota
}

/**
 * ¿La fila es una cuota de INTERÉS (el rendimiento que cobra el cliente)?
 * Son 'cuota' (interés simple, una por periodo) y 'devolucion' (interés
 * compuesto acumulado, se paga al vencimiento). 'retorno' NO lo es: es la
 * devolución del capital y el generador la empuja SIEMPRE, así que
 * `cronograma.length` nunca vale 0 y NO sirve para validar que el contrato
 * tenga rendimiento (auditoría 2026-07-25: se podían crear/corregir contratos
 * con cero cuotas de interés). Vive aquí porque saber qué fila es interés es
 * conocimiento del generador, no de los formularios.
 */
export function esCuotaDeInteres(cuota: CuotaCronograma): boolean {
  return cuota.tipo !== 'retorno'
}

// Parse/format de fechas YYYY-MM-DD en zona LOCAL. `new Date("2026-05-22")` las
// interpreta como UTC midnight → en Perú (UTC-5) es el día anterior 19:00 local.
export function parseDateLocal(s: string): Date {
  const [y, m, d] = s.split('-').map(Number) as [number, number, number]
  return new Date(y, m - 1, d)
}
export function formatDateLocal(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

// Redondeo monetario a 2 decimales medio-arriba (half-up), igual que round() de
// Postgres. Evita que toFixed(2) trunque el borde .005. Auditoría 2026-06-13.
export function redondear2(x: number): number {
  return Number(Math.round(Number(x + 'e2')) + 'e-2')
}

// Saldo con capitalización ANUAL entre inicio y corte (interés compuesto).
function saldoCompuesto(capital: number, tasaAnual: number, inicio: Date, corte: Date): number {
  const i = Number(tasaAnual) / 100
  let saldo = Number(capital)
  if (!(corte > inicio)) return saldo
  let anios = corte.getFullYear() - inicio.getFullYear()
  const anivActual = new Date(inicio.getFullYear() + anios, inicio.getMonth(), inicio.getDate())
  if (corte < anivActual) anios--
  for (let k = 0; k < anios; k++) {
    const interes = Math.round(saldo * i * 100) / 100
    saldo = Math.round((saldo + interes) * 100) / 100
  }
  const ultimoAniv = new Date(inicio.getFullYear() + anios, inicio.getMonth(), inicio.getDate())
  const proxAniv = new Date(inicio.getFullYear() + anios + 1, inicio.getMonth(), inicio.getDate())
  const frac = (corte.getTime() - ultimoAniv.getTime()) / (proxAniv.getTime() - ultimoAniv.getTime())
  if (frac > 0) {
    const interesFrac = Math.round(saldo * i * frac * 100) / 100
    saldo = Math.round((saldo + interesFrac) * 100) / 100
  }
  return saldo
}

// Nº de años EXACTOS si fin cae justo en un aniversario (mismo día/mes); si no, null.
export function aniosExactos(inicio: Date, fin: Date): number | null {
  const n = fin.getFullYear() - inicio.getFullYear()
  if (n < 1) return null
  const aniv = new Date(inicio.getFullYear() + n, inicio.getMonth(), inicio.getDate())
  return aniv.getTime() === fin.getTime() ? n : null
}

/**
 * Vencimiento desde el plazo en MESES (misma lógica que calcularVencimiento del
 * portal: relativo al inicio, recorta fin de mes desbordado). Devuelve ISO local.
 */
export function vencimientoDesdePlazo(fechaInicio: string, meses: number): string {
  const [y, m, d] = fechaInicio.split('-').map(Number) as [number, number, number]
  const targetMes = (m - 1) + meses
  let resultado = new Date(y, targetMes, d)
  const mesNorm = ((targetMes % 12) + 12) % 12
  if (resultado.getMonth() !== mesNorm) {
    resultado = new Date(y, targetMes + 1, 0)
  }
  return formatDateLocal(resultado)
}

/**
 * Genera el cronograma (espejo EXACTO de generarCronograma del portal).
 * COMPUESTO: intereses al vencimiento ('devolucion') + capital 7 días después
 * ('retorno'). SIMPLE: cuota fija de interés por periodo + retorno del capital.
 * Devuelve [] si los datos no son válidos (fin ≤ inicio, compuesto sin años exactos…).
 */
export function generarCronograma(
  capital: number,
  tasaAnual: number,
  fechaInicio: string,
  fechaVencimiento: string,
  modalidad: ModalidadContrato,
  tipoInteres: TipoInteres,
): CuotaCronograma[] {
  const inicio = parseDateLocal(fechaInicio)
  const fin = parseDateLocal(fechaVencimiento)
  if (fin <= inicio) return []

  if (tipoInteres === 'compuesto') {
    const anios = aniosExactos(inicio, fin)
    if (!anios) return []
    const montoFinal = saldoCompuesto(capital, tasaAnual, inicio, fin)
    const interesTotal = redondear2(montoFinal - Number(capital))
    const fechaRetornoComp = new Date(fin)
    fechaRetornoComp.setDate(fechaRetornoComp.getDate() + 7)
    return [
      { numero_cuota: 1, fecha_programada: formatDateLocal(fin), monto_programado: interesTotal, estado: 'pendiente', tipo: 'devolucion' },
      { numero_cuota: 2, fecha_programada: formatDateLocal(fechaRetornoComp), monto_programado: Number(Number(capital).toFixed(2)), estado: 'pendiente', tipo: 'retorno' },
    ]
  }

  const cuotasPorAnio = ({ mensual: 12, trimestral: 4, semestral: 2, anual: 1 } as const)[modalidad]
  if (!cuotasPorAnio) return []
  const mesesIntervalo = 12 / cuotasPorAnio
  const montoFijo = redondear2((capital * (tasaAnual / 100)) / cuotasPorAnio)

  const diaObjetivo = inicio.getDate()
  const mesInicio = inicio.getMonth()
  const yearInicio = inicio.getFullYear()

  const fechas: Date[] = []
  let i = 1
  // Cota dura: 5 años mensual = 60 cuotas; 120 es margen defensivo anti-bucle.
  while (i <= 120) {
    const targetMes = mesInicio + i * mesesIntervalo
    let candidato = new Date(yearInicio, targetMes, diaObjetivo)
    const mesNorm = ((targetMes % 12) + 12) % 12
    if (candidato.getMonth() !== mesNorm) {
      candidato = new Date(yearInicio, targetMes + 1, 0)
    }
    if (candidato > fin) break
    fechas.push(candidato)
    i++
  }

  const cuotas: CuotaCronograma[] = fechas.map((fecha, idx) => ({
    numero_cuota: idx + 1,
    fecha_programada: formatDateLocal(fecha),
    monto_programado: montoFijo,
    estado: 'pendiente',
    tipo: 'cuota',
  }))

  const fechaRetorno = new Date(fin)
  fechaRetorno.setDate(fechaRetorno.getDate() + 7)
  cuotas.push({
    numero_cuota: cuotas.length + 1,
    fecha_programada: formatDateLocal(fechaRetorno),
    // toFixed (no redondear2) en la línea del capital: espejo EXACTO del portal.
    monto_programado: Number(Number(capital).toFixed(2)),
    estado: 'pendiente',
    tipo: 'retorno',
  })
  return cuotas
}
