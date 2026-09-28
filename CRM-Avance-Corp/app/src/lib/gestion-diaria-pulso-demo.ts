// Gestión Diaria F5 — espejo DEMO del pulso y los hábitos de gerencia (G0).
// En demo no hay servidor: se arma la MISMA forma que `crm.gestion_diaria_pulso_fn`,
// `crm.gestion_diaria_habitos_fn` y `crm.gestion_diaria_equipo_fn` sin supervisor
// (migraciones 20260924201358 y 20260921040335) con el mundo en memoria. Es un
// espejo, no una segunda verdad: las cifras de cada analista salen de
// `diaEquipoDesdeDemo`, el mismo detalle que abre la tabla del equipo, así que
// pulso y detalle cuadran por construcción. Aquí sólo se reparte por supervisor,
// se suman los autores fuera del organigrama activo y se comparan jornadas.
// No importa fixtures: recibe el mundo del store, igual que el demo del supervisor.
import type { Actividad, Lead, Miembro, Tarea } from './tipos'
import { fechaLima } from './agenda-derivada'
import type { DiaEquipo } from './gestion-diaria-equipo'
import { diaEquipoDesdeDemo } from './gestion-diaria-equipo-demo'
import { desplazarDia, diaPulsoValido, type MetricasPulso, type PersonaPulso, type PulsoGerencia } from './gestion-diaria-pulso'
import type { HabitosGerencia, PersonaHabitos } from './gestion-diaria-habitos'

/** El mundo demo tal como lo expone el store (para gerencia, todo el ámbito). */
export interface MundoDemo {
  miembros: readonly Miembro[]
  leads: readonly Lead[]
  actividades: readonly Actividad[]
  tareas: readonly Tarea[]
  ahora: number
}

type DiaHabitos = PersonaHabitos['dias'][number]
type Contacto = { llamadas: number; utiles: number; contestadas: number }
interface Grupo { clave: string; supervisor_id: string | null; nombre: string }
/** Una llamada del día con su autor y su equipo: la base de los leads distintos y de los huecos. */
interface Llamada { persona: string | null; clave: string; lead_id: string; en: number; id: string }
interface Foto { dia: string; detalle: DiaEquipo; personas: PersonaPulso[]; llamadas: Llamada[] }
interface Organigrama {
  grupos: Grupo[]
  /** Analista activo → su equipo: el supervisor ACTIVO más cercano, o «fuera». */
  equipoDe: ReadonlyMap<string, Grupo>
  porId: ReadonlyMap<string, Miembro>
  /** El demo firma las actividades por nombre, no por id. */
  porNombre: ReadonlyMap<string, Miembro>
}

const LLAMADAS: ReadonlySet<string> = new Set(['llamada_realizada', 'llamada_no_contestada'])
// Misma definición de «actividad» que el servidor y que `diaEquipoDesdeDemo`.
const GESTIONES: ReadonlySet<string> = new Set([...LLAMADAS, 'whatsapp_enviado', 'reunion_realizada', 'nota', 'conversion'])
const FUERA: Grupo = { clave: 'fuera', supervisor_id: null, nombre: 'Fuera de equipos comerciales' }
// Política 1 = cortes desactivados. El espejo no inventa cortes: los decide el servidor.
const CORTES: DiaHabitos['cortes'] = { estado: 'desactivados', politica_version: 1, cartera_referencia: 'consulta_actual', primer_corte: null, segundo_corte: null }
const CUMPLIMIENTO_SIN_CORTES: PersonaHabitos['cumplimiento'] = { evaluables: 0, cumplidos_a_tiempo: 0, recuperados: 0, incumplidos: 0, pendientes: 0, sin_cartera: 0 }

const redondear = (n: number, decimales: number) => Math.round(n * 10 ** decimales) / 10 ** decimales
const tasa = (contestadas: number, utiles: number) => utiles > 0 ? redondear(100 * contestadas / utiles, 1) : null
const minutos = (ms: number) => redondear(ms / 60_000, 1)
const iso = (ms: number) => new Date(ms).toISOString()
const porTexto = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0
/** Día Lima de un instante; vacío si no es una fecha (nunca coincide con un día pedido). */
function diaDe(instante: string): string {
  const ms = Date.parse(instante)
  return Number.isFinite(ms) ? fechaLima(ms) : ''
}
/** El mismo rango que acepta el servidor: hoy o los últimos 365 días. */
function exigirDia(dia: string, ahora: number): void {
  if (!diaPulsoValido(dia, fechaLima(ahora))) throw new RangeError('Día inválido: elige hoy o los últimos 365 días.')
}

/** Partición disjunta como `gestion_diaria_pulso_roster`: sube también por puentes inactivos; un ciclo corta. */
function organigrama(miembros: readonly Miembro[]): Organigrama {
  const porId = new Map(miembros.map((m) => [m.perfil_id, m]))
  const supervisores = new Map(miembros.filter((m) => m.activo && m.rol_crm === 'supervisor')
    .map((m): [string, Grupo] => [m.perfil_id, { clave: m.perfil_id, supervisor_id: m.perfil_id, nombre: m.nombre_completo }]))
  const equipoDe = new Map<string, Grupo>()
  for (const m of miembros) {
    if (!m.activo || m.rol_crm !== 'vendedor') continue
    const vistos = new Set([m.perfil_id])
    let jefe = m.supervisor_id ?? null
    while (jefe !== null && !supervisores.has(jefe) && !vistos.has(jefe)) {
      vistos.add(jefe)
      jefe = porId.get(jefe)?.supervisor_id ?? null
    }
    equipoDe.set(m.perfil_id, (jefe === null ? undefined : supervisores.get(jefe)) ?? FUERA)
  }
  return { grupos: [...supervisores.values(), FUERA], equipoDe, porId, porNombre: new Map(miembros.map((m) => [m.nombre_completo, m])) }
}

function contacto(filas: readonly Contacto[]) {
  const suma = (campo: keyof Contacto) => filas.reduce((n, f) => n + f[campo], 0)
  return { llamadas: suma('llamadas'), utiles: suma('utiles'), contestadas: suma('contestadas'), tasa_contacto: tasa(suma('contestadas'), suma('utiles')) }
}

/** Una jornada del mundo demo, autosuficiente para el pulso y los hábitos. */
function foto(m: MundoDemo, org: Organigrama, dia: string): Foto {
  const detalle = diaEquipoDesdeDemo(null, m.miembros, m.leads, m.actividades, m.tareas, m.ahora, dia)
  // Las optimistas locales quedan fuera, como en el detalle: sólo lo confirmado.
  const delDia = m.actividades.filter((a) => !a.local && diaDe(a.creado_en) === dia)
  const llamadas: Llamada[] = []
  const anotar = (persona: string | null, clave: string, propias: readonly Actividad[]) => {
    for (const a of propias) if (LLAMADAS.has(a.tipo)) llamadas.push({ persona, clave, lead_id: a.lead_id, en: Date.parse(a.creado_en), id: a.id })
  }
  // Organigrama activo: las cifras son las del detalle, con su mismo filtro por autor.
  const personas = detalle.equipo.map(({ analista_id, nombre_completo, marcador: mk, gestiones_hoy }): PersonaPulso => {
    const grupo = org.equipoDe.get(analista_id) ?? FUERA
    anotar(analista_id, grupo.clave, delDia.filter((a) => a.autor_nombre === nombre_completo))
    return {
      analista_id, nombre_completo, activo: true, supervisor_id: grupo.supervisor_id, clave_equipo: grupo.clave,
      llamadas: mk.llamadas, utiles: mk.utiles, contestadas: mk.contestadas, gestiones: gestiones_hoy,
      citas_agendadas: mk.citas_agendadas, leads_tocados: mk.leads_tocados,
      primera_llamada_en: mk.primera_llamada_en, ultima_llamada_en: mk.ultima_llamada_en,
    }
  })
  // Otros autores del día (supervisores, bajas o sin identidad) van a «fuera», como en el servidor.
  const enOrganigrama = new Set(detalle.equipo.map((f) => f.nombre_completo))
  const otros = new Map<string | null, { propias: Actividad[]; citas: number }>()
  const otro = (id: string | null) => {
    const actual = otros.get(id) ?? { propias: [], citas: 0 }
    otros.set(id, actual)
    return actual
  }
  for (const a of delDia) {
    if (GESTIONES.has(a.tipo) && !enOrganigrama.has(a.autor_nombre)) otro(org.porNombre.get(a.autor_nombre)?.perfil_id ?? null).propias.push(a)
  }
  for (const t of m.tareas) {
    if (t.tipo !== 'reunion' || diaDe(t.creado_en) !== dia) continue
    // El detalle da la cita al dueño actual del lead; aquí sólo la que no es de nadie del organigrama.
    const lead = m.leads.find((l) => l.id === t.lead_id)
    const dueno = (lead ? lead.vendedor_id : t.vendedor_id) ?? null
    if (dueno === null || !org.equipoDe.has(dueno)) otro(dueno).citas += 1
  }
  for (const [id, { propias, citas }] of otros) {
    anotar(id, FUERA.clave, propias)
    const suyas = propias.filter((a) => LLAMADAS.has(a.tipo))
    const instantes = suyas.map((a) => a.creado_en).sort((x, y) => Date.parse(x) - Date.parse(y))
    personas.push({
      analista_id: id, nombre_completo: id === null ? null : org.porId.get(id)?.nombre_completo ?? null,
      activo: false, supervisor_id: null, clave_equipo: FUERA.clave,
      // El demo no tipifica el resultado: toda llamada es útil (la regla del detalle).
      llamadas: suyas.length, utiles: suyas.length, contestadas: suyas.filter((a) => a.tipo === 'llamada_realizada').length,
      gestiones: propias.length, citas_agendadas: citas, leads_tocados: new Set(suyas.map((a) => a.lead_id)).size,
      primera_llamada_en: instantes[0] ?? null, ultima_llamada_en: instantes.at(-1) ?? null,
    })
  }
  return { dia, detalle, personas, llamadas }
}

/** Agrega hechos ya contados. Los leads distintos se deduplican en el ámbito: nunca se suman por persona. */
function metricas(personas: readonly PersonaPulso[], llamadas: readonly Llamada[]): MetricasPulso {
  const { llamadas: total, utiles, contestadas, tasa_contacto } = contacto(personas)
  const leads = new Set(llamadas.map((l) => l.lead_id)).size
  const activos = personas.filter((p) => p.activo)
  const conActividad = activos.filter((p) => p.gestiones > 0).length
  return {
    llamadas: total, utiles, contestadas, tasa_contacto, leads_unicos: leads,
    llamadas_por_lead: leads > 0 ? redondear(total / leads, 2) : null,
    citas_agendadas: personas.reduce((n, p) => n + p.citas_agendadas, 0),
    analistas_activos: activos.length, con_actividad: conActividad, sin_actividad: activos.length - conActividad,
  }
}

/** Promedio diario de los recuentos; tasa y llamadas por lead reúnen numerador y denominador. */
function media(dias: readonly MetricasPulso[]): PulsoGerencia['referencia']['media'] {
  const suma = (campo: keyof MetricasPulso) => dias.reduce((n, d) => n + (d[campo] ?? 0), 0)
  const promedio = (campo: keyof MetricasPulso) => dias.length ? redondear(suma(campo) / dias.length, 2) : null
  const leads = suma('leads_unicos')
  return {
    llamadas: promedio('llamadas'), utiles: promedio('utiles'), contestadas: promedio('contestadas'),
    tasa_contacto: tasa(suma('contestadas'), suma('utiles')), leads_unicos: promedio('leads_unicos'),
    llamadas_por_lead: leads > 0 ? redondear(suma('llamadas') / leads, 2) : null,
    citas_agendadas: promedio('citas_agendadas'), analistas_activos: promedio('analistas_activos'),
    con_actividad: promedio('con_actividad'), sin_actividad: promedio('sin_actividad'),
  }
}

/** Jornadas con gestiones o citas creadas, de la más reciente a la más antigua; los días vacíos no son base. */
function fechasActivas(m: MundoDemo): string[] {
  const dias = new Set<string>()
  for (const a of m.actividades) if (!a.local && GESTIONES.has(a.tipo)) dias.add(diaDe(a.creado_en))
  for (const t of m.tareas) if (t.tipo === 'reunion') dias.add(diaDe(t.creado_en))
  return [...dias].filter(Boolean).sort().reverse()
}

/** Tareas vencidas AHORA (también al mirar un día pasado), con el mismo dueño que usa el detalle. */
function vencidasPorEquipo(m: MundoDemo, org: Organigrama): Map<string, number> {
  const cuenta = new Map<string, number>()
  for (const t of m.tareas) {
    if (!t.activo || t.estado !== 'pendiente' || !(Date.parse(t.vence_en) < m.ahora)) continue
    const dueno = t.vendedor_id ?? m.leads.find((l) => l.id === t.lead_id)?.vendedor_id ?? null
    const clave = (dueno === null ? undefined : org.equipoDe.get(dueno)?.clave) ?? FUERA.clave
    cuenta.set(clave, (cuenta.get(clave) ?? 0) + 1)
  }
  return cuenta
}

const porAnalista = (a: PersonaPulso, b: PersonaPulso) => a.analista_id === b.analista_id ? 0
  : a.analista_id === null ? 1 : b.analista_id === null ? -1 : porTexto(a.analista_id, b.analista_id)

/** El pulso de gerencia del mundo demo, con la forma y las cuentas de `PulsoGerenciaSchema`. */
export function pulsoGerenciaDesdeDemo(m: MundoDemo, dia: string): PulsoGerencia {
  exigirDia(dia, m.ahora)
  const org = organigrama(m.miembros)
  const busqueda = desplazarDia(dia, -365)
  const referencia = fechasActivas(m).filter((d) => d >= busqueda && d < dia).slice(0, 7)
  const elegido = foto(m, org, dia)
  const anterior = foto(m, org, desplazarDia(dia, -1))
  const base = referencia.map((d) => {
    const f = foto(m, org, d)
    return metricas(f.personas, f.llamadas)
  })
  const vencidas = vencidasPorEquipo(m, org)
  const minimo = elegido.detalle.umbrales.minimo_llamadas_utiles
  // Todos los supervisores activos y SIEMPRE «fuera», aunque estén vacíos.
  const equipos = org.grupos.map((g) => {
    const personas = elegido.personas.filter((p) => p.clave_equipo === g.clave).sort(porAnalista)
    const tasas = personas.filter((p) => p.activo && p.utiles >= minimo).map((p) => 100 * p.contestadas / p.utiles)
    return {
      ...g, personas, metricas: metricas(personas, elegido.llamadas.filter((l) => l.clave === g.clave)),
      tareas_vencidas: vencidas.get(g.clave) ?? 0, primer_intento_vencido: null,
      dispersion: { personas: tasas.length, minimo: tasas.length ? Math.min(...tasas) : null, maximo: tasas.length ? Math.max(...tasas) : null },
    }
  }).sort((a, b) => b.tareas_vencidas - a.tareas_vencidas || porTexto(a.clave, b.clave))
  return {
    version: 1, dia, generado_en: iso(m.ahora), organigrama_referencia: 'consulta_actual', minimo_llamadas_utiles: minimo,
    actual: metricas(elegido.personas, elegido.llamadas),
    ayer: { dia: anterior.dia, metricas: metricas(anterior.personas, anterior.llamadas) },
    referencia: {
      dias: referencia, busqueda_desde: busqueda, cantidad: referencia.length,
      dias_con_tasa: base.filter((d) => d.tasa_contacto !== null).length, media: media(base),
    },
    // El espejo no inventa vencimientos de primer intento: el SLA queda en observación.
    equipos, pendientes_al: iso(m.ahora), modo_sla: 'observacion',
    vencidas_global: equipos.reduce((n, e) => n + e.tareas_vencidas, 0),
  }
}

/** El detalle de gerencia: TODOS los analistas activos, como `obtenerDiaEquipo(dia, null)`. */
export function detalleOperacionDesdeDemo(m: MundoDemo, dia: string): DiaEquipo {
  exigirDia(dia, m.ahora)
  return diaEquipoDesdeDemo(null, m.miembros, m.leads, m.actividades, m.tareas, m.ahora, dia)
}

/** percentile_cont de Postgres: interpolación lineal entre los rangos vecinos. */
function percentil(ordenados: readonly number[], p: number): number | null {
  if (!ordenados.length) return null
  const posicion = p * (ordenados.length - 1)
  const bajo = ordenados[Math.floor(posicion)]!, alto = ordenados[Math.ceil(posicion)]!
  return redondear(bajo + (alto - bajo) * (posicion - Math.floor(posicion)), 1)
}

/** Horario de la jornada Lima (09–18 h, sábado 09–13 h, domingo no laborable), como `gestion_diaria_habitos_jornada`. */
function jornada(dia: string, llamadas: readonly Llamada[], ahora: number): DiaHabitos['jornada'] {
  const semana = new Date(`${dia}T12:00:00Z`).getUTCDay()
  if (semana === 0) return { estado: 'no_laborable', inicio: null, cierre: null, observado_hasta: null, primera_en_jornada: null,
    ultima_en_jornada: null, silencio_inicio_minutos: null, silencio_final_minutos: null, hueco: null }
  const inicio = Date.parse(`${dia}T09:00:00-05:00`)
  const cierre = Date.parse(`${dia}T${semana === 6 ? '13' : '18'}:00:00-05:00`)
  const fin = Math.max(inicio, Math.min(ahora, cierre))
  const eventos = llamadas.filter((l) => l.en >= inicio && l.en < fin).sort((a, b) => a.en - b.en || porTexto(a.id, b.id))
  let hueco: { desde: number; hasta: number } | null = null
  for (let i = 1; i < eventos.length; i++) {
    const desde = eventos[i - 1]!.en, hasta = eventos[i]!.en
    // A igual pausa gana la primera, como el orden del servidor.
    if (hueco === null || hasta - desde > hueco.hasta - hueco.desde) hueco = { desde, hasta }
  }
  const primera = eventos[0]?.en ?? null, ultima = eventos.at(-1)?.en ?? null
  return {
    estado: ahora < inicio ? 'no_iniciada' : ahora < cierre ? 'en_curso' : 'finalizada',
    inicio: iso(inicio), cierre: iso(cierre), observado_hasta: iso(fin),
    primera_en_jornada: primera === null ? null : iso(primera), ultima_en_jornada: ultima === null ? null : iso(ultima),
    silencio_inicio_minutos: minutos((primera ?? fin) - inicio), silencio_final_minutos: minutos(fin - (ultima ?? inicio)),
    hueco: hueco && { desde: iso(hueco.desde), hasta: iso(hueco.hasta), minutos: minutos(hueco.hasta - hueco.desde) },
  }
}

function personaHabitos(analista: Miembro, grupo: Grupo, fotos: readonly Foto[], ahora: number): PersonaHabitos {
  const dias = fotos.map((f): DiaHabitos => {
    // Todo analista activo está en cada foto: el detalle parte del organigrama, no de la actividad.
    const p = f.personas.find((x) => x.activo && x.analista_id === analista.perfil_id)!
    return {
      dia: f.dia, llamadas: p.llamadas, utiles: p.utiles, contestadas: p.contestadas, tasa_contacto: tasa(p.contestadas, p.utiles),
      primera_llamada_en: p.primera_llamada_en, ultima_llamada_en: p.ultima_llamada_en,
      minimo_llamadas_utiles: f.detalle.umbrales.minimo_llamadas_utiles,
      jornada: jornada(f.dia, f.llamadas.filter((l) => l.persona === analista.perfil_id), ahora), cortes: CORTES,
    }
  })
  const validas = dias.filter((d) => d.utiles >= d.minimo_llamadas_utiles).map((d) => d.tasa_contacto ?? 0).sort((a, b) => a - b)
  const equipo = grupo.supervisor_id === null ? null : contacto(fotos.flatMap((f) => f.personas.filter((p) => p.clave_equipo === grupo.clave)))
  return {
    analista_id: analista.perfil_id, nombre_completo: analista.nombre_completo, supervisor_id: grupo.supervisor_id,
    dias, resumen: contacto(dias),
    equipo: equipo ? { utiles: equipo.utiles, contestadas: equipo.contestadas, tasa_contacto: equipo.tasa_contacto }
      : { utiles: null, contestadas: null, tasa_contacto: null },
    distribucion_contacto: { dias_validos: validas.length, minimo: validas[0] ?? null, p25: percentil(validas, 0.25),
      mediana: percentil(validas, 0.5), p75: percentil(validas, 0.75), maximo: validas.at(-1) ?? null },
    cumplimiento: CUMPLIMIENTO_SIN_CORTES,
  }
}

/** Hábitos de 7/14/30 días hasta el día elegido, con la forma de `HabitosGerenciaSchema`. */
export function habitosGerenciaDesdeDemo(m: MundoDemo, hasta: string, dias: 7 | 14 | 30): HabitosGerencia {
  exigirDia(hasta, m.ahora)
  // El informe respeta el mismo límite histórico que el pulso.
  const desde = [desplazarDia(hasta, 1 - dias), desplazarDia(fechaLima(m.ahora), -365)].sort().at(-1)!
  const org = organigrama(m.miembros)
  const fotos: Foto[] = []
  for (let d = desde; d <= hasta; d = desplazarDia(d, 1)) fotos.push(foto(m, org, d))
  const personas = [...org.equipoDe].map(([id, grupo]) => personaHabitos(org.porId.get(id)!, grupo, fotos, m.ahora))
    .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es') || porTexto(a.analista_id, b.analista_id))
  return {
    version: 1, generado_en: iso(m.ahora), desde, hasta, dias_solicitados: dias, dias_incluidos: fotos.length,
    organigrama_referencia: 'consulta_actual', cartera_referencia: 'consulta_actual', umbral_tasa_baja: null,
    operacion: contacto(fotos.flatMap((f) => f.personas)),
    jornadas: fotos.map((f) => ({ dia: f.dia, minimo_llamadas_utiles: f.detalle.umbrales.minimo_llamadas_utiles,
      estado_cortes: CORTES.estado, politica_version: CORTES.politica_version })),
    personas,
  }
}
