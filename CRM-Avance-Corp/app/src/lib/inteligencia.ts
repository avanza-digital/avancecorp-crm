// lib/inteligencia.ts — Inteligencia comercial por rol (contrato F1c).
// Funciones PURAS sobre (leads, actividades, equipo): sin React, sin store,
// sin efectos. Cada pantalla las alimenta con su ÁMBITO (useCRMData().ambito),
// así la misma función sirve para vendedor/supervisor/gerencia/directorio.
//
// Los colores salen de lib/semaforo.ts (paleta única, sin verde en el chrome).
import { ETAPAS, ETAPA_INFO, ORIGENES_TODOS, TERMINALES_K, TIPOS_CONTACTO_K, TIPOS_CONVERSACION_K, type Actividad, type EtapaActiva, type Lead, type Miembro } from './tipos'
import { SEMAFORO } from './semaforo'
import { money, moneyK, type Moneda } from './format'
import type { PlanPorLead } from './plan-lead'
import { entradaEnEtapa } from './antiguedad-etapa'
import { UMBRAL_ETAPA_MS } from './estancamiento'

export const DIA_MS = 86_400_000

/** Lead abierto = activo y en etapa de trabajo (ni convertido ni descartado). */
export const esAbierto = (l: Lead): boolean => l.activo && !TERMINALES_K.has(l.etapa)

// ── Capital por moneda ────────────────────────────────────────────────────────

/**
 * Capital estimado por moneda de los leads RECIBIDOS (el caller decide el
 * subconjunto — típicamente abiertos). Regla central del negocio: PEN y USD
 * JAMÁS se suman entre sí. Fuente única (antes reimplementado en 8 sitios).
 */
export function capitalPorMoneda(leads: Lead[]): { pen: number; usd: number } {
  let pen = 0
  let usd = 0
  for (const l of leads) {
    if (l.moneda === 'USD') usd += l.monto_estimado ?? 0
    else pen += l.monto_estimado ?? 0
  }
  return { pen, usd }
}

/** Qué dice un chip de capital: el número grande y su letra chica. */
export interface CapitalPrincipal {
  /** La cartera es ÍNTEGRAMENTE en dólares → el número grande es el USD. */
  soloDolares: boolean
  /** Moneda que manda en el número grande. */
  moneda: Moneda
  /** El número grande, ya formateado con su símbolo. */
  valor: string
  /**
   * La OTRA moneda, compacta ("US$ 40k"), cuando también tiene volumen; `null`
   * si no hay nada que añadir (o si ella misma es la que manda).
   */
  otra: string | null
  /** Subtítulo estándar de moneda: 'PEN' · 'USD' · 'PEN · +US$ 40k'. */
  sub: string
}

/**
 * Qué moneda MANDA en el número grande de un chip de capital, y qué se dice de
 * la otra.
 *
 * EL DEFECTO QUE CIERRA (pedido de Miguel, 2026-07-26). Tres pantallas pintan el
 * mismo capital y las tres fijaban PEN a mano: una cartera íntegramente en
 * dólares anunciaba "S/ 0.00" con su capital real escondido en la letra chica —
 * el chip decía justo lo contrario de lo que el asesor tiene en juego. Cartera y
 * Pipeline ya lo corrigieron por su cuenta y Hoy se quedó atrás, así que las
 * pantallas llegaron a contradecirse sobre el MISMO lead. El criterio vive aquí
 * una sola vez para que eso no pueda volver a pasar.
 *
 * REGLA: PEN manda cuando hay soles (es la moneda del negocio); si solo hay
 * dólares, manda USD; con las dos se muestran las dos, cada una con su símbolo.
 * PEN y USD JAMÁS se suman ni se convierten para caber en un número.
 */
export function capitalPrincipal(pen: number, usd: number): CapitalPrincipal {
  const soloDolares = pen <= 0 && usd > 0
  const moneda: Moneda = soloDolares ? 'USD' : 'PEN'
  const otra = !soloDolares && usd > 0 ? moneyK(usd, 'USD') : null
  return {
    soloDolares,
    moneda,
    valor: money(soloDolares ? usd : pen, moneda),
    otra,
    sub: soloDolares ? 'USD' : otra ? `PEN · +${otra}` : 'PEN',
  }
}

// ── Semáforo compartido de avance de meta ─────────────────────────────────────

/**
 * Color del avance hacia una meta (pct 0–100, puede exceder 100): azul ≥75
 * en buen camino · ámbar ≥40 atención · rojo <40 crítico. Escala ÚNICA para
 * todos los roles (sin verde; navy queda reservado a ganado/convertido).
 */
export const colorMeta = (pct: number): string =>
  pct >= 75 ? SEMAFORO.ok : pct >= 40 ? SEMAFORO.atencion : SEMAFORO.critico

/** Semáforo de un valor contra su objetivo: llega azul · a medias ámbar · lejos rojo. */
export function colorVsObjetivo(valor: number, objetivo: number): string {
  if (objetivo <= 0 || valor >= objetivo) return SEMAFORO.ok
  if (valor >= objetivo / 2) return SEMAFORO.atencion
  return SEMAFORO.critico
}

/** % de avance hacia el objetivo (la UI recorta a 0–100 al pintar la barra). */
export const pctMeta = (actual: number, objetivo: number): number =>
  objetivo > 0 ? (actual / objetivo) * 100 : 0

/**
 * Chip de tendencia "▲ +13%" desde una serie (últimos 2 puntos). Con
 * `mostrarCero` el 0% devuelve "— 0%" (dashboards ejecutivos); sin él,
 * undefined (sin chip). Semántica unificada — antes divergía por copia.
 *
 * REACTIVADA (Fase 3, 2026-07-19): las series ahora son REALES — el store las
 * calcula de los leads del ámbito (lib/series-comerciales) y el hero de
 * gerencia vuelve a dibujar el chip. Con historia insuficiente (mes anterior
 * en 0) devuelve undefined: sin chip, sin inventar tendencia.
 */
export function tendenciaDe(serie: number[], opts?: { mostrarCero?: boolean }): string | undefined {
  if (serie.length < 2) return undefined
  const [prev, ult] = serie.slice(-2)
  if (prev == null || ult == null || prev === 0) return undefined
  const pct = Math.round(((ult - prev) / prev) * 100)
  if (pct === 0) return opts?.mostrarCero ? '— 0%' : undefined
  return pct > 0 ? `▲ +${pct}%` : `▼ −${Math.abs(pct)}%`
}

// ── Cola de acción ────────────────────────────────────────────────────────────

export type BucketCola =
  | 'sin_responder'
  | 'insistir'
  | 'propuesta_sin_respuesta'
  | 'seguimiento'
  | 'sin_avance'
  | 'plan_vencido'
  | 'por_repartir'

export interface ItemCola {
  lead: Lead
  bucket: BucketCola
  motivo: string
  sev: 'critica' | 'media' | 'baja'
  dias: number
}

/** Orden de severidad para la cola (crítica primero). */
const PESO_SEV: Record<ItemCola['sev'], number> = { critica: 0, media: 1, baja: 2 }

/** Labels es-PE de los buckets de la cola (antes copiado en vendedor y supervisor). */
export const BUCKET_LABEL: Record<BucketCola, string> = {
  sin_responder: 'Sin responder',
  insistir: 'Insistir',
  propuesta_sin_respuesta: 'Propuesta sin respuesta',
  seguimiento: 'Seguimiento',
  sin_avance: 'Sin avance',
  plan_vencido: 'Plan vencido',
  por_repartir: 'Por repartir',
}

/** "hace horas" / "hace N días" para motivos y timestamps es-PE — fuente única. */
export function haceTexto(dias: number): string {
  if (dias < 1) return 'hace horas'
  const d = Math.floor(dias)
  return d === 1 ? 'hace 1 día' : `hace ${d} días`
}

/** "hoy" / "N d" compacto para columnas de días (dias viene con fracción). */
export const diasTxt = (d: number): string => (d < 1 ? 'hoy' : `${Math.floor(d)} d`)

export type IndiceUltimaActividad = ReadonlyMap<string, Actividad>

/**
 * Índice O(actividades) reutilizable por todos los cálculos de una pantalla.
 * Evita volver a recorrer el timeline completo por cada lead.
 */
export function indexarUltimaActividad(acts: Actividad[]): IndiceUltimaActividad {
  const indice = new Map<string, Actividad>()
  for (const actividad of acts) {
    const anterior = indice.get(actividad.lead_id)
    if (!anterior || actividad.creado_en > anterior.creado_en) {
      indice.set(actividad.lead_id, actividad)
    }
  }
  return indice
}

/**
 * Índice del último CONTACTO REAL (llamada, WhatsApp, reunión) — NO de cualquier
 * fila del timeline.
 *
 * Por qué existe (auditoría 2026-07-25, hallazgo crítico verificado en prod):
 * el timeline se llena de actividades que emite el SISTEMA, no una persona.
 * Cada movimiento de tenencia escribe una `reasignacion` (trigger
 * `private.trg_leads_reasignacion` en el servidor + copia optimista del store),
 * y cada cambio de etapa un `cambio_etapa`. Como `colaDe` preguntaba "¿tiene
 * ALGUNA actividad?" para decidir si nadie lo ha contactado, **todo lead que
 * pasaba por el circuito Rosa → supervisor → vendedor salía de la cola el
 * instante en que se asignaba**: llegaba con su `reasignacion` puesta. El
 * vendedor veía "Al día ✦ sin pendientes" sobre un lead que nadie había
 * llamado. En prod el 100% de las actividades eran `reasignacion`/`cambio_etapa`.
 *
 * `indexarUltimaActividad` se deja INTACTA: el timeline de la ficha sí quiere
 * verlo todo, y las métricas rotuladas "Última actividad" siguen midiendo
 * actividad a secas. Este índice es solo para las señales que afirman que
 * alguien HABLÓ con el cliente.
 */
export function indexarUltimoContacto(acts: Actividad[]): IndiceUltimaActividad {
  return indexarUltimaActividad(acts.filter((a) => TIPOS_CONTACTO_K.has(a.tipo)))
}

/**
 * Días (con fracción, nunca negativos) desde un ISO hasta `ahora` (epoch ms).
 * Pasa el reloj vivo de useAhora() como `ahora` para que el valor refresque
 * solo — NUNCA re-derivar con Date.now() en render (queda congelado).
 */
export function diasDesdeReferencia(creadoEn: string, ahora: number): number {
  const t = new Date(creadoEn).getTime()
  if (Number.isNaN(t)) return 0
  return Math.max(0, (ahora - t) / DIA_MS)
}

function diasSinActividadIndexado(
  lead: Lead,
  indice: IndiceUltimaActividad,
  ahora: number,
): number {
  return diasDesdeReferencia(indice.get(lead.id)?.creado_en ?? lead.creado_en, ahora)
}

/**
 * Instante desde el que se mide la espera de un lead ANTE SU DUEÑO ACTUAL: el
 * MÁS RECIENTE entre su última actividad y el momento en que su asesor lo
 * recibió (`tenencia_desde`).
 *
 * Por qué existe (pedido de Miguel, 2026-07-24): con el circuito de leads vivo
 * — origen → hoja → cola de Rosa → bandeja del supervisor → vendedor — un lead
 * puede pasar DÍAS antes de llegar a un asesor. Midiendo desde `creado_en`, su
 * cola lo pintaba en ROJO CRÍTICO el primer segundo que lo veía, culpándolo de
 * una espera que no fue suya. Tomar el MÁXIMO resuelve de una vez los tres
 * casos: el lead recién asignado arranca en cero; el TRANSFERIDO no le hereda
 * al nuevo dueño la mora del anterior (aunque tenga actividades viejas); y el
 * lead sin dueño —`tenencia_desde` null, la cola de Rosa— sigue midiéndose
 * desde que entró, que es lo correcto para quien lo reparte.
 *
 * SOLO para la cola de acción. `diasSinActividadMax` y `estancados` siguen
 * midiendo inactividad PURA: sus etiquetas dicen "Última actividad" y mezclar
 * la tenencia ahí las volvería mentira.
 *
 * EXPORTADA (2026-07-25) para que el semáforo del kanban use ESTE reloj y no
 * una copia: dos fórmulas gemelas divergen, y entonces Hoy y Pipeline dan días
 * distintos sobre el mismo lead y el CRM pierde autoridad.
 */
export function referenciaEspera(lead: Lead, indice: IndiceUltimaActividad): string {
  return masReciente(indice.get(lead.id)?.creado_en ?? lead.creado_en, lead.tenencia_desde)
}

/**
 * El más reciente de dos instantes ISO, con `b` opcional. Fuente única de la
 * regla "el reloj del dueño actual nunca corre hacia atrás": ausente o corrupto,
 * `b` degrada a `a` en vez de romper la cola (Date.parse → NaN y la comparación
 * da false). La usan los DOS relojes de tenencia: el de la espera
 * (`referenciaEspera`) y el de la etapa (bucket `sin_avance`).
 */
function masReciente(a: string, b: string | null | undefined): string {
  if (b == null) return a
  return Date.parse(b) > Date.parse(a) ? b : a
}

function diasEnEsperaIndexado(
  lead: Lead,
  indice: IndiceUltimaActividad,
  ahora: number,
): number {
  return diasDesdeReferencia(referenciaEspera(lead, indice), ahora)
}

/**
 * Días (con fracción) sin actividad: desde la última actividad, o desde
 * creado_en si el lead nunca fue tocado. Nunca negativo.
 * `ahora` (epoch ms, default Date.now()) permite un reloj vivo (useAhora)
 * o fechas fijas en tests; la firma sigue siendo retro-compatible.
 */
export function diasSinActividad(lead: Lead, acts: Actividad[], ahora: number = Date.now(), indice?: IndiceUltimaActividad): number {
  return diasSinActividadIndexado(lead, indice ?? indexarUltimaActividad(acts), ahora)
}

/**
 * Cola de acción — SOLO leads abiertos; a lo sumo UN bucket por lead
 * (el más urgente gana). Orden: severidad desc, luego días desc.
 * Reglas (contrato F1c):
 *  - vendedor_id null → por_repartir (crítica) — solo la ven supervisor/gerencia
 *    porque el ámbito del vendedor nunca incluye parkeados.
 *  - nuevo SIN NINGÚN CONTACTO → sin_responder (crítica si ≥1 día; media antes).
 *  - nuevo YA INTENTADO ≥1 día → insistir (media).
 *  - propuesta_enviada sin contacto ≥5 días → propuesta_sin_respuesta (media).
 *  - contactado/reunion_agendada sin contacto ≥3 días → seguimiento (baja).
 *
 * ⚠️ TODA la cola se mide contra el último CONTACTO REAL, no contra cualquier
 * fila del timeline (auditoría 2026-07-25). Las actividades que emite el
 * SISTEMA —`reasignacion` en cada movimiento de tenencia, `cambio_etapa` en
 * cada paso de etapa— no son trabajo comercial: contarlas hacía que un lead
 * recién repartido saliera de la cola por completo, porque llegaba con su
 * `reasignacion` ya puesta. Ver `indexarUltimoContacto`.
 */
export function colaDe(
  leads: Lead[],
  acts: Actividad[],
  ahora: number = Date.now(),
  // Plan de cada lead (lib/plan-lead.ts). Los buckets por INACTIVIDAD
  // (seguimiento/propuesta/insistir) son el FALLBACK de quien no tiene plan
  // VIVO — un lead con tarea futura ya tiene dueño de su siguiente paso.
  // Asignación (por_repartir) y speed-to-lead (sin_responder) se mantienen
  // SIEMPRE: son estados de tenencia/primer contacto, no de planificación.
  //
  // ⚠️ `vigente`, NO "tiene alguna tarea": una tarea pendiente que venció hace
  // dos semanas NO es un plan. Antes lo era, y el lead se escondía de la cola
  // detrás de una promesa incumplida — cuanto más se abandonaba, más invisible.
  plan?: Pick<PlanPorLead, 'vigente' | 'vencido'>,
): ItemCola[] {
  const items: ItemCola[] = []
  // El índice se construye AQUÍ DENTRO a propósito: antes se aceptaba uno ya
  // calculado por el caller, pero `IndiceUltimaActividad` es el mismo TIPO para
  // el índice de toda actividad y para el de contacto — nada impedía pasar el
  // equivocado, y el compilador no diría nada. Esa ambigüedad es justo lo que
  // dejó vivo el bug. Filtrar 3 tipos sobre unas pocas filas no es un costo real.
  const indice = indexarUltimoContacto(acts)
  for (const lead of leads) {
    if (!esAbierto(lead)) continue
    const ultima = indice.get(lead.id)
    // La espera se mide ANTE SU DUEÑO ACTUAL, no desde que el lead entró al
    // CRM: quien acaba de recibirlo no puede nacer en rojo (ver
    // diasEnEsperaIndexado). Sin dueño, `tenencia_desde` es null y esto es
    // exactamente lo de siempre.
    const dias = diasEnEsperaIndexado(lead, indice, ahora)
    const tienePlan = plan?.vigente.has(lead.id) === true
    const desdeEtapa = entradaEnEtapa(lead, acts)
    const umbralEtapa = UMBRAL_ETAPA_MS[lead.etapa]
    const diasEnEtapa = desdeEtapa ? diasDesdeReferencia(desdeEtapa, ahora) : 0
    // EL MISMO reloj de dueño de `diasEnEsperaIndexado`, aplicado a la etapa
    // (alineación pedida por Miguel, 2026-07-26). El estancamiento de etapa se
    // le cobra a quien tiene el lead AHORA: un lead clavado 20 días en
    // Contactado y reasignado ayer disparaba "o avanza o se cierra" en el primer
    // día del nuevo asesor, con una antigüedad HEREDADA del dueño anterior — la
    // misma injusticia que ya se corrigió en el resto de la cola. Era la única
    // rama que se había quedado fuera de ese reloj. Sin `tenencia_desde` (demo,
    // o base sin la migración) esto es exactamente el comportamiento de siempre.
    const diasEtapaDueno = desdeEtapa
      ? diasDesdeReferencia(masReciente(desdeEtapa, lead.tenencia_desde), ahora)
      : 0
    if (lead.vendedor_id == null) {
      items.push({ lead, bucket: 'por_repartir', sev: 'critica', dias, motivo: `Sin vendedor asignado ${haceTexto(dias)} — hay que repartirlo` })
    } else if (lead.etapa === 'nuevo' && !ultima) {
      // El motivo lleva LOS DOS relojes cuando difieren de verdad (≥1 día): el
      // del asesor —que es el que lo juzga— y el del cliente, que no puede
      // desaparecer. Alguien lleva días esperando aunque su asesor lo tenga
      // hace minutos, y esa urgencia es real. Redacción neutra a propósito:
      // esta cola también la leen supervisor y gerencia sobre leads ajenos.
      const esperaCliente = diasDesdeReferencia(lead.creado_en, ahora)
      const motivo = esperaCliente - dias >= 1
        ? `Asignado ${haceTexto(dias)} · el cliente escribió ${haceTexto(esperaCliente)}`
        : `Entró ${haceTexto(dias)} y nadie lo ha contactado`
      items.push({ lead, bucket: 'sin_responder', sev: dias >= 1 ? 'critica' : 'media', dias, motivo })
    } else if (desdeEtapa && umbralEtapa != null && ultima && diasEtapaDueno * DIA_MS >= umbralEtapa * 2) {
      // RELOJ DE ETAPA — va ANTES del atajo `tienePlan` a propósito: una tarea
      // viva es un plan para el PRÓXIMO TOQUE, no un plan para AVANZAR. El lead
      // clavado tres semanas en la misma etapa, al que se sigue llamando cada
      // dos días, tenía siempre plan vigente y por eso este bucket no se podía
      // disparar nunca. `estancados` tampoco lo ve: mide inactividad, y este
      // está muy activo. Es justo el que consume tiempo sin avanzar.
      //
      // DISPARA con el reloj del DUEÑO (`diasEtapaDueno`) y CUENTA con el de la
      // etapa (`diasEnEtapa`): cuándo es justo reclamar depende de hace cuánto
      // el lead es tuyo, pero los días clavado en la etapa son un hecho del lead
      // y no se pueden reescribir. Cuando los dos relojes difieren de verdad
      // (≥1 día) el motivo dice LOS DOS — mismo criterio que `sin_responder` e
      // `insistir`, y redacción neutra porque esta cola también la leen
      // supervisor y gerencia sobre leads ajenos.
      items.push({
        lead,
        bucket: 'sin_avance',
        sev: 'media',
        dias: diasEnEtapa,
        motivo: diasEnEtapa - diasEtapaDueno >= 1
          ? `Lleva ${haceTexto(diasEnEtapa)} en ${ETAPA_INFO[lead.etapa].label} · ${haceTexto(diasEtapaDueno)} con su asesor actual — o avanza o se cierra`
          : `Lleva ${haceTexto(diasEnEtapa)} en ${ETAPA_INFO[lead.etapa].label} y se sigue trabajando — o avanza o se cierra`,
      })
    } else if (tienePlan) {
      continue // tiene próxima acción agendada: su cola es la agenda, no esta
    } else if (lead.etapa === 'nuevo' && ultima && dias >= 1) {
      // EL AGUJERO QUE ESTA RAMA TAPA (auditoría 2026-07-25, verificado en prod):
      // un lead en `nuevo` al que alguien YA intentó contactar no caía en NINGÚN
      // bucket — `sin_responder` exige `!ultima`, y los otros tres solo miran
      // `contactado`/`reunion_agendada`/`propuesta_enviada`. Bastaba pulsar
      // "No contestó" una vez para que el lead se evaporara de la cola y no
      // volviera nunca. Es la mitad complementaria del avance automático de
      // etapa: el que SÍ contesta sube a `contactado` y reaparece por
      // seguimiento; el que NO contesta se queda en `nuevo`, y sin esta rama se
      // quedaría además invisible.
      //
      // Va DESPUÉS de `tienePlan` a propósito: quien ya tiene su WhatsApp
      // agendado para mañana vive en la agenda, no aquí (si no, doble aviso).
      // Y exige ≥1 día: reaparecer el mismo día se lee como ruido.
      const hablo = TIPOS_CONVERSACION_K.has(ultima.tipo)
      // El intento se fecha con SU PROPIO reloj, no con el de la tenencia: un
      // lead reasignado hace 3 días cuyo único intento fue hace 9 decía
      // "Intentado hace 3 días", que es sencillamente falso. Cuando los dos
      // relojes difieren, se dicen los dos (mismo criterio que sin_responder).
      const diasIntento = diasDesdeReferencia(ultima.creado_en, ahora)
      const dosRelojes = diasIntento - dias >= 1
      items.push({
        lead,
        bucket: 'insistir',
        sev: 'media',
        dias,
        // Dos motivos porque hay dos historias distintas, y ninguna puede
        // mentir. El segundo caso solo existe con datos anteriores al avance
        // automático (o si el trigger no llegó a correr): el lead habló pero
        // sigue en `nuevo`, y lo que toca no es insistir sino moverlo.
        motivo: hablo
          ? `Ya hablaron ${haceTexto(diasIntento)} pero sigue en Nuevo — muévelo de etapa`
          : dosRelojes
            ? `En tus manos ${haceTexto(dias)} · último intento ${haceTexto(diasIntento)} — cambia de canal`
            : `Intentado ${haceTexto(diasIntento)} y aún no responde — cambia de canal`,
      })
    } else if (lead.etapa === 'propuesta_enviada' && dias >= 5) {
      items.push({ lead, bucket: 'propuesta_sin_respuesta', sev: 'media', dias, motivo: `Propuesta enviada sin movimiento ${haceTexto(dias)}` })
    } else if ((lead.etapa === 'contactado' || lead.etapa === 'reunion_agendada') && dias >= 3) {
      items.push({ lead, bucket: 'seguimiento', sev: 'baja', dias, motivo: `Sin actividad ${haceTexto(dias)} — toca retomar el seguimiento` })
    } else {
      // RESIDUO, y por eso va AL FINAL de la cadena. Al quitarle el escudo al
      // lead, lo normal es que vuelva por su propio pie al bucket que le toca
      // por inactividad (insistir / propuesta / seguimiento), con su motivo y
      // su severidad correctos. Esta rama solo captura al que no cae en
      // ninguno: el trabajado hace poco cuya tarea de la semana pasada sigue
      // abierta. Sin ella, volvería a ser invisible.
      //
      // Si `plan_vencido` fuera PRIMERO, un `propuesta_enviada` con 10 días
      // muertos se degradaría de 'media' a 'baja' y su motivo pasaría de
      // "propuesta sin movimiento" a "tienes una tarea sin cerrar" — nadie
      // contacta a nadie por cerrar una tarea.
      // RELOJ DE ETAPA: el lead que SÍ recibe toques pero lleva el doble de su
      // plazo clavado en la misma etapa. No lo ve ninguna otra señal —
      // `estancados` y los buckets de arriba miden INACTIVIDAD, y este está
      // muy activo. Es justo el que consume tiempo del asesor sin avanzar:
      // hay que rescatarlo o cerrarlo, no seguir tocándolo.
      const muerta = plan?.vencido.get(lead.id)
      if (muerta) {
        const diasMuerta = diasDesdeReferencia(muerta.vence_en, ahora)
        items.push({
          lead,
          bucket: 'plan_vencido',
          sev: 'baja',
          dias: diasMuerta,
          motivo: `«${muerta.titulo}» venció ${haceTexto(diasMuerta)} y sigue abierta — ciérrala o reprográmala`,
        })
      }
    }
  }
  return items.sort((a, b) => PESO_SEV[a.sev] - PESO_SEV[b.sev] || b.dias - a.dias)
}

/**
 * Leads abiertos CON vendedor y SIN tarea pendiente — el bucket AMARILLO del
 * semáforo (plan v2): el mecanismo real de la industria no es el candado, es
 * esta lista inocultable. Orden: capital PEN desc (lo que más plata arriesga
 * primero); USD después, también desc — JAMÁS mezclados en un mismo número.
 */
export function sinProximaAccion(leads: Lead[], conTareaPendiente: ReadonlySet<string>): Lead[] {
  return leads
    .filter((l) => esAbierto(l) && l.vendedor_id != null && !conTareaPendiente.has(l.id))
    .sort((a, b) => {
      if (a.moneda !== b.moneda) return a.moneda === 'PEN' ? -1 : 1
      return b.monto_estimado - a.monto_estimado
    })
}

// ── Métricas por vendedor (ranking) ──────────────────────────────────────────

export interface MetricasVendedor {
  m: Miembro
  activos: number
  capitalPEN: number // capital en proceso de sus leads abiertos en PEN
  capitalUSD: number // ídem en USD — JAMÁS se suma con el PEN
  convertidos: number
  conversion: number // 0-100: convertidos / total de sus leads
  /** Abiertos que NADIE ha contactado (ni llamada, ni WhatsApp, ni reunión).
   *  Cuenta CONTACTO, no cualquier fila del timeline: la `reasignacion` que
   *  escribe el sistema al repartir un lead lo dejaba en 0 para siempre. */
  sinTocar: number
  diasSinActividadMax: number // el abierto más abandonado (0 si no tiene abiertos)
}

/**
 * Métricas de captación por vendedor sobre el ámbito recibido.
 * Orden: capitalPEN desc (el ranking por capital captado en proceso).
 *
 * Ojo a los DOS índices: `sinTocar` afirma que nadie habló con el cliente y por
 * tanto mide CONTACTO; `diasSinActividadMax` alimenta una columna rotulada
 * "Última actividad" y sigue midiendo actividad a secas. No se fusionan.
 */
export function metricasPorVendedor(vs: Miembro[], leads: Lead[], acts: Actividad[], ahora: number = Date.now(), indicePrevio?: IndiceUltimaActividad): MetricasVendedor[] {
  const indice = indicePrevio ?? indexarUltimaActividad(acts)
  const indiceContacto = indexarUltimoContacto(acts)
  const porVendedor = new Map<string, Lead[]>()
  for (const lead of leads) {
    if (!lead.activo || !lead.vendedor_id) continue
    const actuales = porVendedor.get(lead.vendedor_id)
    if (actuales) actuales.push(lead)
    else porVendedor.set(lead.vendedor_id, [lead])
  }

  return vs
    .map((m) => {
      const suyos = porVendedor.get(m.perfil_id) ?? []
      const abiertos = suyos.filter(esAbierto)
      const convertidos = suyos.filter((l) => l.etapa === 'convertido').length
      const capital = capitalPorMoneda(abiertos)
      let sinTocar = 0
      let diasMax = 0
      for (const l of abiertos) {
        if (!indiceContacto.has(l.id)) sinTocar++
        const d = diasSinActividadIndexado(l, indice, ahora)
        if (d > diasMax) diasMax = d
      }
      return {
        m,
        activos: abiertos.length,
        capitalPEN: capital.pen,
        capitalUSD: capital.usd,
        convertidos,
        conversion: suyos.length > 0 ? Math.round((convertidos / suyos.length) * 100) : 0,
        sinTocar,
        diasSinActividadMax: diasMax,
      }
    })
    .sort((a, b) => b.capitalPEN - a.capitalPEN)
}

// ── Embudo y conversión ───────────────────────────────────────────────────────

/**
 * Embudo por etapa activa sobre los leads ABIERTOS del ámbito.
 * Devuelve SIEMPRE las 4 etapas en orden de pipeline (n puede ser 0);
 * pctDelTotal es sobre el total de abiertos (0 si no hay ninguno).
 */
export function embudo(leads: Lead[]): Array<{ etapa: EtapaActiva; n: number; pctDelTotal: number }> {
  const abiertos = leads.filter(esAbierto)
  const total = abiertos.length
  return ETAPAS.map((e) => {
    const n = abiertos.filter((l) => l.etapa === e.k).length
    return { etapa: e.k, n, pctDelTotal: total > 0 ? Math.round((n / total) * 100) : 0 }
  })
}

/**
 * Conversión por origen (histórico completo del ámbito, terminales incluidos).
 * Solo orígenes con al menos un lead; incluye el catálogo activo y el histórico.
 * Orden: % de conversión desc, luego volumen desc.
 */
export function conversionPorOrigen(leads: Lead[]): Array<{ origen: string; label: string; total: number; convertidos: number; pct: number }> {
  const vivos = leads.filter((l) => l.activo)
  const filas: Array<{ origen: string; label: string; total: number; convertidos: number; pct: number }> = []
  for (const o of ORIGENES_TODOS) {
    const del = vivos.filter((l) => l.origen === o.k)
    if (del.length === 0) continue
    const convertidos = del.filter((l) => l.etapa === 'convertido').length
    filas.push({ origen: o.k, label: o.label, total: del.length, convertidos, pct: Math.round((convertidos / del.length) * 100) })
  }
  return filas.sort((a, b) => b.pct - a.pct || b.total - a.total)
}

// ── Estancados (capital en riesgo) ────────────────────────────────────────────

/**
 * Leads ABIERTOS sin actividad hace `dias` o más (default 7).
 * Orden: días desc (el más abandonado primero). `dias` va con fracción;
 * la UI decide cómo redondear.
 */
export function estancados(
  leads: Lead[],
  acts: Actividad[],
  dias = 7,
  ahora: number = Date.now(),
  indicePrevio?: IndiceUltimaActividad,
  // Fase B: un lead con tarea pendiente NO está estancado aunque lleve días
  // sin actividad — tiene un plan con fecha (antes el supervisor veía riesgo
  // donde el vendedor tenía una reunión agendada la próxima semana).
  conTareaPendiente?: ReadonlySet<string>,
): Array<{ lead: Lead; dias: number }> {
  const indice = indicePrevio ?? indexarUltimaActividad(acts)
  return leads
    .filter((l) => esAbierto(l) && conTareaPendiente?.has(l.id) !== true)
    .map((lead) => ({ lead, dias: diasSinActividadIndexado(lead, indice, ahora) }))
    .filter((x) => x.dias >= dias)
    .sort((a, b) => b.dias - a.dias)
}

// ── Conversión global del ámbito ──────────────────────────────────────────────

/**
 * Conversión del ámbito: convertidos / leads activos CON vendedor (misma base
 * que comparativaEquipos — los parkeados no cuentan porque nadie los trabaja).
 * Fuente única (antes copiado con comentarios gemelos en supervisor y gerencia).
 */
export function conversionGlobal(leads: Lead[]): { convertidos: number; base: number; pct: number } {
  const asignados = leads.filter((l) => l.activo && l.vendedor_id != null)
  const convertidos = asignados.filter((l) => l.etapa === 'convertido').length
  return {
    convertidos,
    base: asignados.length,
    pct: asignados.length > 0 ? Math.round((convertidos / asignados.length) * 100) : 0,
  }
}

// ── Comparativa de equipos (gerencia / directorio) ────────────────────────────

/**
 * Una fila por SUPERVISOR activo del equipo. El universo de cada fila es el
 * mismo que el ámbito de ese supervisor: sus leads propios + los de sus
 * vendedores (métricas de activos/capital/conversión) MÁS sus parkeados
 * (vendedor_id null asignados a su bandeja), que se cuentan aparte en
 * `parkeados` y NO suman al capital (aún no tienen dueño trabajándolos).
 */
export function comparativaEquipos(equipo: Miembro[], leads: Lead[], acts: Actividad[]):
  Array<{ supervisor: Miembro; vendedores: number; activos: number; capitalPEN: number; capitalUSD: number; convertidos: number; conversion: number; parkeados: number }> {
  void acts // reservado: SLA/semaforización por equipo llega en F2 sin romper la firma
  const vivos = leads.filter((l) => l.activo)
  return equipo
    .filter((m) => m.rol_crm === 'supervisor' && m.activo)
    .map((supervisor) => {
      const suyos = equipo.filter((m) => m.supervisor_id === supervisor.perfil_id && m.activo)
      const ids = new Set<string>([supervisor.perfil_id, ...suyos.map((v) => v.perfil_id)])
      const asignados = vivos.filter((l) => l.vendedor_id != null && ids.has(l.vendedor_id))
      const abiertos = asignados.filter(esAbierto)
      const convertidos = asignados.filter((l) => l.etapa === 'convertido').length
      const capital = capitalPorMoneda(abiertos)
      return {
        supervisor,
        vendedores: suyos.length,
        activos: abiertos.length,
        capitalPEN: capital.pen,
        capitalUSD: capital.usd,
        convertidos,
        conversion: asignados.length > 0 ? Math.round((convertidos / asignados.length) * 100) : 0,
        parkeados: vivos.filter((l) => esAbierto(l) && l.vendedor_id == null && l.asignado_supervisor_id === supervisor.perfil_id).length,
      }
    })
    .sort((a, b) => b.capitalPEN - a.capitalPEN)
}
