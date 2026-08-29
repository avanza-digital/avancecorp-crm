// Episodios de asignación del modo demo — el ESPEJO del ledger que la demo
// nunca tuvo (demo-sla fabrica un asignacion_id suelto, pero ningún episodio
// con asignado_en, y sin episodios la conversión mensual no existe).
//
// Los meses son RELATIVOS (0 = mes en curso, 1 = anterior) y se resuelven
// contra `periodoLima` en el derivador: la conversión es mensual y un fixture
// clavado a `hace(n)` días enseñaría un negocio distinto cada día del mes
// (§4bis-E4 del plan). Aquí no hay fechas: hay MESES.
//
// Trae los TRES casos que la ley obliga a poder enseñar (§5 del plan):
//   · A→B: el lead 'l20' pasa por ANALISTA UNO (lo suelta) y lo cierra
//     ANALISTA DOS — al divisor de LOS DOS, al numerador solo de quien cerró.
//   · ARRASTRE: 'la1' recibido el mes pasado y cerrado este mes — numerador de
//     este mes, divisor del pasado. Y ANALISTA TRES vive entero de arrastre
//     (divisor 0 + cierre): el estado `solo_arrastre` en pantalla.
//   · REFERIDO CERRADO: 'l21' referido de ANALISTA UNO que cierra — fuera del
//     divisor, 15 % en el numerador, `aporta_pct` distinto de 0.
export interface EpisodioDemo {
  leadId: string
  analistaId: 'd-v1' | 'd-v2' | 'd-v3'
  /** 0 = mes en curso · 1 = mes anterior (se resuelve contra periodoLima). */
  asignadoHaceMeses: 0 | 1
  origen: 'referido' | 'landing' | 'formulario' | 'web' | 'oficina' | 'otro'
  resultado?: 'convertido' | 'descartado'
  /** Mes del cierre; solo tiene sentido con `resultado`. */
  resultadoHaceMeses?: 0 | 1
}

export const EPISODIOS_DEMO: readonly EpisodioDemo[] = [
  // ── ANALISTA UNO (d-v1) · divisor 8 · cierra 2 no-ref (1 de arrastre) + 1 ref
  { leadId: 'l2', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'landing' },
  { leadId: 'l8', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'web', resultado: 'descartado', resultadoHaceMeses: 0 },
  { leadId: 'l9', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'landing' },
  { leadId: 'l12', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'formulario' },
  { leadId: 'l15', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'landing' },
  { leadId: 'l16', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'formulario', resultado: 'convertido', resultadoHaceMeses: 0 },
  { leadId: 'l17', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'landing' },
  // El traspaso A→B: UNO lo recibe y lo suelta (episodio sin resultado)…
  { leadId: 'l20', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'landing' },
  // …y el ARRASTRE: recibido el mes pasado, cerrado este mes.
  { leadId: 'la1', analistaId: 'd-v1', asignadoHaceMeses: 1, origen: 'landing', resultado: 'convertido', resultadoHaceMeses: 0 },
  // Referidos de UNO: uno abierto (l1, el de la cartera demo) y uno cerrado.
  { leadId: 'l1', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'referido' },
  { leadId: 'l21', analistaId: 'd-v1', asignadoHaceMeses: 0, origen: 'referido', resultado: 'convertido', resultadoHaceMeses: 0 },

  // ── ANALISTA DOS (d-v2) · divisor 6 · cierra el traspasado
  { leadId: 'l3', analistaId: 'd-v2', asignadoHaceMeses: 0, origen: 'landing' },
  { leadId: 'l6', analistaId: 'd-v2', asignadoHaceMeses: 0, origen: 'formulario' },
  { leadId: 'l10', analistaId: 'd-v2', asignadoHaceMeses: 0, origen: 'landing', resultado: 'descartado', resultadoHaceMeses: 0 },
  { leadId: 'l18', analistaId: 'd-v2', asignadoHaceMeses: 0, origen: 'web' },
  { leadId: 'l19', analistaId: 'd-v2', asignadoHaceMeses: 0, origen: 'landing' },
  // …la otra mitad del traspaso: DOS lo recibe y lo CIERRA. Mismo lead, mismo
  // mes: divisor de ambos, numerador solo de DOS.
  { leadId: 'l20', analistaId: 'd-v2', asignadoHaceMeses: 0, origen: 'landing', resultado: 'convertido', resultadoHaceMeses: 0 },

  // ── ANALISTA TRES (d-v3) · SOLO ARRASTRE: nada recibido este mes, un cierre
  { leadId: 'l7', analistaId: 'd-v3', asignadoHaceMeses: 1, origen: 'landing', resultado: 'convertido', resultadoHaceMeses: 0 },
  { leadId: 'l4', analistaId: 'd-v3', asignadoHaceMeses: 1, origen: 'web' },
  { leadId: 'l5', analistaId: 'd-v3', asignadoHaceMeses: 1, origen: 'landing' },
]
