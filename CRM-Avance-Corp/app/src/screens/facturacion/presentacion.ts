// Proyección de la hoja. Los totales y las conversiones siguen siendo los del modelo.
import {
  combinarEnSoles, construirMallaDeDias, etiquetaDiaLargo, numeroDia, TIPO_TODOS,
  TIPOS_FACTURACION, type CeldaFacturacion, type FilaFacturacion, type FilaFacturacionDia,
  type MallaFacturacion, type MetricaFacturacion, type PersonaFacturacion,
} from '@/lib/facturacion'
import { money, numero, type Moneda } from '@/lib/format'

export interface ColumnaHoja {
  clave: string
  titulo: string
  dias: readonly string[]
  tipo?: string
  futura?: boolean
  malla?: MallaFacturacion | undefined
  combinada?: MallaFacturacion | null
  pen?: MallaFacturacion
  usd?: MallaFacturacion
}
const ROTULOS: Record<string, string> = {
  contrato_nuevo: 'Nuevo', contrato_renovacion: 'Renovación',
  contrato_upgrade: 'Upgrade', cooperativa: 'Cooperativa',
}
const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic']
const mesCorto = (dia: string): string => MESES[Number(dia.slice(5, 7)) - 1] ?? ''

/** El rótulo abreviado se conserva a la vista; el lector recibe el rango completo. */
export function nombreColumna(columna: ColumnaHoja): string {
  const primero = columna.dias[0]
  const ultimo = columna.dias.at(-1)
  if (!columna.futura || !primero || !ultimo) return columna.titulo
  const fecha = (dia: string): string => etiquetaDiaLargo(dia).replace(/^.*?,?\s(?=\d)/, '')
  if (primero === ultimo) return `${fecha(primero)}, por venir`
  const desde = primero.slice(0, 7) === ultimo.slice(0, 7) ? numeroDia(primero) : fecha(primero)
  return `del ${desde} al ${fecha(ultimo)}, por venir`
}

export function columnasDeDias(dias: readonly string[], hoy: string): ColumnaHoja[] {
  const futuros = dias.includes(hoy) ? dias.filter((d) => d > hoy) : []
  const columnas: ColumnaHoja[] = dias.filter((d) => !futuros.includes(d))
    .map((dia) => ({ clave: dia, titulo: etiquetaDiaLargo(dia), dias: [dia] }))
  const primero = futuros[0]
  const ultimo = futuros.at(-1)
  if (primero && ultimo) {
    const desde = `${numeroDia(primero)}${primero.slice(0, 7) === ultimo.slice(0, 7) ? '' : ` ${mesCorto(primero)}`}`
    const rango = primero === ultimo ? `${numeroDia(primero)} ${mesCorto(primero)}` : `${desde}–${numeroDia(ultimo)} ${mesCorto(ultimo)}`
    columnas.push({ clave: 'por-venir', titulo: `${rango} · por venir`, dias: futuros, futura: true })
  }
  return columnas
}

/** Cada columna por tipo usa el mismo constructor y la misma conversión que la malla original. */
export function columnasDeTipos(filas: readonly FilaFacturacionDia[], dias: readonly string[], mes: string,
  tipo: string, roster: readonly PersonaFacturacion[], vista: 'TOTAL' | Moneda, tasa?: number): ColumnaHoja[] {
  const tipos = tipo === TIPO_TODOS
    ? [...new Set([...TIPOS_FACTURACION.filter((t) => t !== TIPO_TODOS), ...filas.map((f) => f.tipo)])]
    : [tipo]
  return tipos.map((t) => {
    const pen = construirMallaDeDias(filas, dias, mes, 'PEN', t, roster)
    const usd = construirMallaDeDias(filas, dias, mes, 'USD', t, roster)
    const combinada = combinarEnSoles(pen, usd, tasa)
    return { clave: t, titulo: ROTULOS[t] ?? t, tipo: t, dias, pen, usd,
      malla: vista === 'TOTAL' ? (combinada ?? pen) : vista === 'PEN' ? pen : usd, combinada }
  })
}

const CERO: CeldaFacturacion = { capital: 0, contratos: 0 }
/** Agrupa únicamente columnas de presentación; no sustituye ni vuelve a calcular los totales. */
export function celdaDeColumna(malla: MallaFacturacion, columna: ColumnaHoja, grupoId?: string, analistaId?: string): CeldaFacturacion {
  const origen = columna.malla ?? malla
  const grupo = origen.grupos.find((g) => g.id === grupoId)
  const fila: FilaFacturacion | undefined = analistaId == null ? grupo : grupo?.analistas.find((a) => a.id === analistaId)
  const valores = grupoId == null ? origen.totalPorDia : fila?.dias
  return columna.dias.reduce((s, dia) => {
    const c = valores?.[origen.dias.indexOf(dia)] ?? CERO
    return { capital: s.capital + c.capital, contratos: s.contratos + c.contratos }
  }, CERO)
}

/** Caché por vista, descartada al cambiar de moneda/métrica: abrir el panel no reformatea toda la hoja. */
export function crearFormatoCifras(moneda: Moneda, metrica: MetricaFacturacion) {
  const cache = new Map<string, string>()
  return (valor: number, compacto = false): string => {
    const clave = `${valor}:${compacto}`
    const anterior = cache.get(clave)
    if (anterior != null) return anterior
    let texto: string
    if (!compacto) texto = metrica === 'capital' ? money(valor, moneda) : numero(valor)
    else if (valor === 0) texto = '·'
    else if (metrica === 'contratos') texto = String(valor)
    else if (Math.abs(valor) >= 1_000_000) texto = `${(valor / 1_000_000).toFixed(1)}M`
    else if (Math.abs(valor) < 1_000) texto = String(Math.round(valor))
    else texto = `${Math.round(valor / 1000)}k`
    cache.set(clave, texto)
    return texto
  }
}

/** Conserva por referencia cada total del modelo; solo cambia el vector de columnas. */
export function proyectarMalla(malla: MallaFacturacion, columnas: readonly ColumnaHoja[]): MallaFacturacion {
  return {
    ...malla,
    dias: columnas.map((c) => c.clave),
    grupos: malla.grupos.map((g) => ({ ...g,
      dias: columnas.map((c) => celdaDeColumna(malla, c, g.id)),
      analistas: g.analistas.map((a) => ({ ...a, dias: columnas.map((c) => celdaDeColumna(malla, c, g.id, a.id)) })),
    })),
    totalPorDia: columnas.map((c) => celdaDeColumna(malla, c)),
  }
}

export const accionOperaciones = (cantidad: number) => cantidad === 0 ? 'sin operaciones, abrir' : `ver ${numero(cantidad)} ${cantidad === 1 ? 'operación' : 'operaciones'}`
