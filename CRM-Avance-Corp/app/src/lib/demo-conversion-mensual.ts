// La conversión mensual del MODO DEMO — DERIVADA, no escrita a mano.
//
// «El fixture se deriva» (§5 del plan) porque la alternativa es mantener a
// mano un payload que diga otra cosa que la aritmética real: la demo enseñaría
// otro negocio. Este módulo reimplementa LA MISMA regla que
// `private.conversion_mensual_por_vendedor` (divisor = leads NO referidos
// recibidos en el mes, un lead por analista; numerador = cierres del mes con
// los referidos al 15 %; NULL sin divisor; estados por el MISMO orden de
// ramas) sobre episodios de asignación demo.
//
// Hay DOS mundos demo con roster propio (las pantallas «Hoy» viven en
// EQUIPO_DEMO `d-v*`; la familia de gerencia en `demo-v*` de
// demo-inteligencia-comercial): el derivador es uno solo y cada mundo le pasa
// sus episodios y su roster — así ninguno puede contar con otra regla.
//
// Lo único que ata esta copia TS a la copia SQL es el test: el caso canónico
// del oráculo (CONV-04) y estas cuentas se verifican con los mismos números en
// `demo-conversion-mensual.test.ts`. Si un día divergen, revienta un test, no
// una demo muda.
import { EQUIPO_DEMO } from './demo'
import { EPISODIOS_DEMO } from './demo-asignaciones'
import { periodoLima } from './objetivos'
import type {
  ConversionMensual,
  ResponsableConversionMensual,
} from './conversion-mensual'

export const PESO_REFERIDO_DEMO = 0.15

const MESES_ES = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre',
] as const

/**
 * El episodio mínimo que el derivador necesita — la versión ancha (analistaId
 * `string`) de `EpisodioDemo` de demo-asignaciones, para que cada mundo demo
 * declare los suyos con su propio roster.
 */
export interface EpisodioConversionDemo {
  leadId: string
  analistaId: string
  /** 0 = mes en curso · 1 = mes anterior (se resuelve contra periodoLima). */
  asignadoHaceMeses: 0 | 1
  origen: 'referido' | 'landing' | 'formulario' | 'web' | 'oficina' | 'otro'
  resultado?: 'convertido' | 'descartado'
  /** Mes del cierre; solo tiene sentido con `resultado`. */
  resultadoHaceMeses?: 0 | 1
}

export interface RosterConversionDemo {
  analistaId: string
  supervisorId: string | null
  /** Arrastre de un mes cerrado (demo): rebaja el numerador y estrena el chip
   * del descuento. El origen siempre es el mes anterior. */
  arrastre?: { pendiente: number; motivo: string }
}

/** Redondeo half-up a 2 decimales, una sola vez — igual que la RPC. */
const round2 = (n: number) => Math.round(n * 100) / 100

const carteraResponsableVacia = (): ResponsableConversionMensual['cartera'] => ({
  conversiones_clientes: 0,
  conversiones_renovacion: 0,
  conversiones_upgrade: 0,
  capital_renovado_pen: 0,
  capital_renovado_usd: 0,
  capital_adicional_pen: 0,
  capital_adicional_usd: 0,
  renovaciones_sin_desglose: 0,
})

function mesRelativo(periodo: string, haceMeses: 0 | 1): { mes: string; nombre: string; anio: number } {
  const [anioTxt = '1970', mesTxt = '01'] = periodo.split('-')
  let anio = Number(anioTxt)
  let mes = Number(mesTxt) - haceMeses
  if (mes < 1) {
    mes += 12
    anio -= 1
  }
  return {
    mes: `${anio}-${String(mes).padStart(2, '0')}`,
    nombre: MESES_ES[mes - 1] ?? 'enero',
    anio,
  }
}

function filaDe(
  analista: RosterConversionDemo,
  periodo: string,
  episodios: readonly EpisodioConversionDemo[],
): ResponsableConversionMensual {
  const propios = episodios.filter((episodio) => episodio.analistaId === analista.analistaId)

  // DIVISOR: leads NO referidos con episodio del mes en curso — contando el
  // LEAD, no el episodio (un A→B→A pesaría uno). Los referidos, aparte.
  const recibidosMes = propios.filter((episodio) => episodio.asignadoHaceMeses === 0)
  const divisor = new Set(
    recibidosMes.filter((episodio) => episodio.origen !== 'referido').map((episodio) => episodio.leadId),
  ).size
  const referidosRecibidos = new Set(
    recibidosMes.filter((episodio) => episodio.origen === 'referido').map((episodio) => episodio.leadId),
  ).size

  // NUMERADOR: cierres convertidos DEL MES, con «era referido» del snapshot del
  // episodio y la procedencia por el mes de SU asignación.
  const cierres = propios.filter((episodio) => (
    episodio.resultado === 'convertido' && episodio.resultadoHaceMeses === 0
  ))
  const cierresNoReferidos = cierres.filter((episodio) => episodio.origen !== 'referido').length
  const cierresReferidos = cierres.filter((episodio) => episodio.origen === 'referido').length
  const cierresDeArrastre = cierres.filter((episodio) => episodio.asignadoHaceMeses !== 0).length
  const brutoNumerador = round2(cierresNoReferidos + PESO_REFERIDO_DEMO * cierresReferidos)
  // El arrastre rebaja el numerador con suelo en cero — la MISMA regla
  // (`private.conversion_con_ajuste`) que la lectura real aplica al servir.
  const pendienteArrastre = analista.arrastre?.pendiente ?? 0
  const numerador = round2(Math.max(0, brutoNumerador - pendienteArrastre))
  const conversionPct = divisor > 0 ? round2((100 * numerador) / divisor) : null

  const estado: ResponsableConversionMensual['estado'] = divisor > 0
    ? 'medible'
    : referidosRecibidos > 0
      ? 'solo_referidos'
      : cierresNoReferidos + cierresReferidos > 0
        ? 'solo_arrastre'
        : 'sin_actividad'

  const porMes = new Map<0 | 1, { cierres: number; referidos: number }>()
  for (const episodio of cierres) {
    const cubo = porMes.get(episodio.asignadoHaceMeses) ?? { cierres: 0, referidos: 0 }
    cubo.cierres += 1
    if (episodio.origen === 'referido') cubo.referidos += 1
    porMes.set(episodio.asignadoHaceMeses, cubo)
  }
  const procedencia = [...porMes.entries()]
    .sort(([a], [b]) => a - b)
    .map(([haceMeses, cubo]) => {
      const info = mesRelativo(periodo, haceMeses)
      return {
        mes: info.mes,
        mes_nombre: info.nombre,
        anio: info.anio,
        cierres: cubo.cierres,
        cierres_referidos: cubo.referidos,
      }
    })

  return {
    vendedor_id: analista.analistaId,
    supervisor_id: analista.supervisorId,
    divisor,
    cierres_no_referidos: cierresNoReferidos,
    cierres_referidos: cierresReferidos,
    cierres_de_arrastre: cierresDeArrastre,
    numerador,
    conversion_pct: conversionPct,
    estado,
    procedencia,
    referidos: {
      recibidos: referidosRecibidos,
      cerrados: cierresReferidos,
      dados_de_alta: referidosRecibidos,
      aporta_pct: divisor > 0
        ? round2((100 * PESO_REFERIDO_DEMO * cierresReferidos) / divisor)
        : null,
    },
    // La demo no simula renovaciones, pero conserva el MISMO contrato que el
    // RPC real. Cero es explícito; ausencia sería una versión incompatible.
    cartera: carteraResponsableVacia(),
    ajuste: analista.arrastre
      ? {
        pendiente: analista.arrastre.pendiente,
        origenes: [{
          periodo: mesRelativo(periodo, 1).mes,
          motivo: analista.arrastre.motivo,
          numerador: analista.arrastre.pendiente,
        }],
      }
      : undefined,
  }
}

export interface AmbitoConversionDemo {
  alcance: ConversionMensual['alcance']
  /** propio → el analista; equipo → el supervisor. Global lo ignora. */
  actorId?: string
}

/**
 * El derivador común: mismo contrato que `crm.conversion_mensual_fn`, mismo
 * recorte por ámbito, total RECALCULADO sobre el recorte (jamás la media de
 * los porcentajes — la regla del servidor). Cada mundo demo lo invoca con sus
 * episodios y su roster.
 */
export function derivarConversionMensual(
  ahoraMs: number,
  ambito: AmbitoConversionDemo,
  episodios: readonly EpisodioConversionDemo[],
  roster: readonly RosterConversionDemo[],
): ConversionMensual {
  const periodo = periodoLima(ahoraMs)
  const mesActual = mesRelativo(periodo, 0)

  const todas: ResponsableConversionMensual[] = roster
    .map((analista) => filaDe(analista, periodo, episodios))

  const responsables = ambito.alcance === 'global'
    ? todas
    : ambito.alcance === 'equipo'
      ? todas.filter((fila) => fila.supervisor_id === ambito.actorId)
      : todas.filter((fila) => fila.vendedor_id === ambito.actorId)

  const ordenadas = [...responsables].sort((a, b) => (
    ((b.conversion_pct ?? -1) - (a.conversion_pct ?? -1))
    || (b.numerador - a.numerador)
    || (b.divisor - a.divisor)
    || a.vendedor_id.localeCompare(b.vendedor_id)
  ))

  const divisor = ordenadas.reduce((total, fila) => total + fila.divisor, 0)
  const numerador = round2(ordenadas.reduce((total, fila) => total + fila.numerador, 0))
  const cierresReferidos = ordenadas.reduce((total, fila) => total + fila.cierres_referidos, 0)
  const cartera = {
    ...carteraResponsableVacia(),
    operaciones_renovacion: 0,
    operaciones_upgrade: 0,
  }

  return {
    version: 1,
    generado_en: new Date(ahoraMs).toISOString(),
    alcance: ambito.alcance,
    periodo: {
      mes: mesActual.mes,
      mes_nombre: mesActual.nombre,
      anio: mesActual.anio,
      zona: 'America/Lima',
      desde: new Date(ahoraMs).toISOString(),
      hasta: new Date(ahoraMs).toISOString(),
    },
    ponderacion: { referido: PESO_REFERIDO_DEMO, fuente: 'crm.conversion_pesos' },
    fuentes: {
      divisor: 'crm.lead_asignaciones.asignado_en',
      numerador: 'crm.lead_asignaciones.resultado_en',
      referido: 'crm.lead_asignaciones.origen',
    },
    cobertura: {
      medible: true,
      suelo_historico: null,
      motivo_no_medible: null,
      divisor_aproximado: 0,
      divisor_por_motivo: divisor > 0 ? { ingreso: divisor } : {},
      cierres_sin_episodio: 0,
      fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 },
    },
    cartera,
    total: {
      analistas: ordenadas.length,
      divisor,
      cierres_no_referidos: ordenadas.reduce((total, fila) => total + fila.cierres_no_referidos, 0),
      cierres_referidos: cierresReferidos,
      cierres_de_arrastre: ordenadas.reduce((total, fila) => total + fila.cierres_de_arrastre, 0),
      referidos_recibidos: ordenadas.reduce((total, fila) => total + fila.referidos.recibidos, 0),
      numerador,
      conversion_pct: divisor > 0 ? round2((100 * numerador) / divisor) : null,
      referidos_aporta_pct: divisor > 0
        ? round2((100 * PESO_REFERIDO_DEMO * cierresReferidos) / divisor)
        : null,
      cartera: { ...cartera },
    },
    responsables: ordenadas,
  }
}

/**
 * El payload que la demo de las pantallas «Hoy» serviría (mundo EQUIPO_DEMO,
 * ids `d-v*`), derivado de `demo-asignaciones.ts`.
 */
export function conversionMensualDemo(
  ahoraMs: number,
  ambito: AmbitoConversionDemo,
): ConversionMensual {
  // ⚠️ Ningún analista demo lleva `arrastre`: los números de los dos mundos
  // curados están narrados cifra a cifra en sus tests (2.15÷8, 4.15÷12…) y un
  // descuento los movería todos. El chip se prueba en los tests de pantalla
  // con filas sintéticas; en producción se estrena con la primera anulación
  // posterior a un sellado.
  const roster: RosterConversionDemo[] = EQUIPO_DEMO
    .filter((miembro) => miembro.rol_crm === 'vendedor')
    .map((miembro) => ({ analistaId: miembro.perfil_id, supervisorId: miembro.supervisor_id ?? null }))
  return derivarConversionMensual(ahoraMs, ambito, EPISODIOS_DEMO, roster)
}
