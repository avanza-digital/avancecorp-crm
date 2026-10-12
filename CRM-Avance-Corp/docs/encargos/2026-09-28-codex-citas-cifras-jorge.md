ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado de este encargo), TEST GAPS,
REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como
hipótesis lo no demostrado. Omite secciones vacías.

# Encargo: REFUTAR la coherencia de las cifras del módulo de Citas (tabla «Avance mensual por analista») — LEVEL 2

No hay código nuevo. Es una VALIDACIÓN: Miguel (dueño del CRM) ve en producción, en Citas → Resultados,
la fila del equipo del supervisor JORGE MARZANO con **160 citas · 37 entrevistas · 40,2 %** y pregunta si
esos números son coherentes (37/160 = 23,1 %, no 40,2 %). Tu trabajo: intentar REFUTAR la conclusión del
PRIMARY con la evidencia transcrita, señalar errores de lectura del código, huecos en la reproducción SQL y
riesgos de interpretación para el usuario. No propongas rediseños genéricos.

## Conclusión provisional del PRIMARY (a refutar)

1. «160 citas» = citas (tareas tipo reunión, activas, con lead activo) CREADAS en septiembre hasta el corte,
   atribuidas al responsable de la cita (`tareas.vendedor_id`), de cualquier estado (incluye programadas,
   vencidas sin resultado, canceladas y reprogramadas).
2. «37 entrevistas» = citas `completada` cuya actividad `reunion_realizada` (registro de asistencia) se creó en
   septiembre hasta el corte.
3. «40,2 %» = 37 / 92, donde 92 = citas CON RESULTADO en septiembre = 37 realizadas + 55 «no asistió» (estas por
   su fecha prevista, hora de Lima al minuto). Configuración vigente: `base_avance = actividad_real`,
   `conteo_entrevistas = citas_realizadas`. El divisor NO son las 160 citas: excluye 29 programadas, 24 vencidas
   sin resultado, 12 canceladas, 5 reprogramadas y 1 no asistió con fecha futura; e incluye 3 citas creadas en
   agosto con resultado en septiembre. 37/92 = 40,217 % → «40,2 %».
4. Veredicto provisional: las tres cifras son coherentes entre sí y con las reglas de negocio acordadas con
   Miguel el 13–14/09/2026 («La base inicial del avance de entrevistas es entrevistas / citas con resultado
   (entrevista o no-show)»; «Cita: generada en el CRM. Entrevista: asistencia a una cita. Si una persona asiste
   dos veces, suma dos entrevistas»; objetivo de entrevistas 70 %).

## Reglas de negocio (vault, notas del 13/09 y 14/09/2026)

- Meta de citas: 1,25 citas por lead. Objetivos de entrevistas y depósitos: 70 % y 70 %.
- La base mensual incluye los leads asignados, incluso sin citas; cuentan también los leads manuales.
- Cita: generada en el CRM. Entrevista: asistencia a una cita. Si una persona asiste dos veces, suma dos entrevistas.
- «La base inicial del avance de entrevistas es entrevistas / citas con resultado (entrevista o no-show),
  identificada en la ayuda y configurable.»
- Reglas aplicadas en producción desde septiembre 2026 (versión 1, aplicada el 14/09 12:38 Lima):
  `mes_resultado = evento`, `analista_resultado = evento`, `base_depositos = personas_entrevistadas`.

## Configuración vigente en producción (leída el 28/09 15:41–15:46 Lima, `private.control_citas_vigente(date '2026-09-01')`)

| Clave | Valor |
|---|---|
| base_avance | actividad_real |
| conteo_entrevistas | citas_realizadas |
| citas_por_lead | 1.25 |
| entrevistas_porcentaje | 70 |
| depositos_porcentaje | 70 |
| mes_resultado | evento |
| analista_resultado | evento |
| base_depositos | personas_entrevistadas |
| actividad_manuales | incluir |
| excluir_manuales_base | false |
| mostrar_meta_citas | false |

## Dónde se pinta la fila (front)

- Recorrido: `App.tsx` vista `reuniones` → `screens/gerencia.tsx` (exige `verCitasEquipo`: supervisor y gerencia)
  → `screens/hoy/citas-gerencia.tsx` → `TableroCitas` (pestaña «Resultados») → `components/citas/resultados.tsx:52`
  → `<AvanceMensualCitas>` (`components/citas/avance-mensual.tsx:99-109`).
- La tabla tiene UNA FILA POR ANALISTA y un pie «Total del equipo» (`avance-mensual.tsx:108`). El supervisor aparece
  como subtítulo bajo el nombre del analista (`:107`). «Jorge» es, por tanto, el pie «Total del equipo» con Jorge
  conectado como supervisor (la RPC recorta cada fuente a `private.vendedor_ids_visibles(uid)`, su subárbol) o con el
  filtro «Supervisor: Jorge» (un solo nivel: `roster.get(id)?.supervisorId === filtros.equipo`, `avance.ts:70-71`).
- La columna «Entrevistas» pinta el % de `tasaEntrevistas` y debajo `<small>{fila.entrevistas} entrevistas</small>`
  (`avance-mensual.tsx:31`). El % se formatea con 1 decimal (`senal-resultado.tsx:29`).
- Al pulsar el nombre de un analista, el detalle imprime `{fila.entrevistas} entrevistas / {baseEntrevistas} citas con
  resultado` (`avance-mensual.tsx:54`). El pie «Total del equipo» NO tiene detalle; el CSV no exporta el divisor.
- Ayuda de la pantalla (`avance-mensual.tsx:116`): «Cada cita realizada con registro de entrevista suma una
  entrevista. La tasa usa las citas con resultado: realizadas y no asistidas. Las futuras, canceladas y pendientes
  de resultado quedan fuera del divisor.»
- Regla del front: la RPC `crm.citas_gerencia_consulta_fn(p_desde, p_hasta)` se llama con el primer y último día
  del mes; `corte = generado_en` (now() del servidor). Para supervisor el servidor NO envía `testigo` (migración
  `20260927172931`, aplicada en producción el 27/09). El testigo, cuando existe, solo contrasta entrevistas,
  personas entrevistadas y depósito; nunca las citas registradas ni las citas con resultado.

## Código del cálculo (transcrito)

### app/src/components/citas/avance.ts (líneas 1-30, 45-90, 105-130, 165-205)
```ts
import { normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
import { baseCitasFiltrada, type GestionCitas } from './metas'
import type { GestionMensualCitas } from '@/lib/gestion-citas'
import { totalEnSoles, tcAplicable } from '@/lib/capital-unificado'

type Persona = GestionMensualCitas['poblacion'][number]
type Capital = GestionMensualCitas['capital'][number]
const TIPOS_CAPITAL = { contrato_nuevo: 'nuevos', contrato_upgrade: 'upgrades', contrato_renovacion: 'renovaciones', cooperativa: 'cooperativas' } as const
export type OperacionesCapital = Record<(typeof TIPOS_CAPITAL)[keyof typeof TIPOS_CAPITAL], number>
const instanteCita = (c: CitaEjemplo) => Date.parse(`${c.fecha}T${c.hora}:00-05:00`)
// El registro de entrevista acredita la relación; la fecha prevista sola no.
const instanteEntrevista = (c: CitaEjemplo) => c.asistioEn ? Date.parse(c.asistioEn) : Number.POSITIVE_INFINITY
const fechaResultado = (c: CitaEjemplo) => c.estado === 'realizada' ? c.asistioEn : `${c.fecha}T${c.hora}:00-05:00`
export const fechaLocalCitas = (fecha: string) => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date(fecha))
export function periodoAvance(mes: string, corte: string) {
  const [anio, numero] = mes.split('-').map(Number)
  const dias = new Date(Date.UTC(anio!, numero!, 0)).getUTCDate()
  const inicio = Date.parse(`${mes}-01T00:00:00-05:00`)
  const fin = Date.parse(`${mes}-${dias}T23:59:59.999-05:00`)
  const ahora = Date.parse(corte)
  const transcurridos = ahora < inicio ? 0 : ahora > fin ? dias : Number(fechaLocalCitas(corte).slice(8))
  return { inicio, fin, corte: Math.min(ahora, fin), dias, transcurridos, cerrado: ahora > fin,
    ritmo: transcurridos ? transcurridos / dias * 100 : null }
}

/** Filtros de población; un estado de cita nunca recorta el divisor de una tasa. */
function coincidePersona(p: Persona, f: FiltrosCitas, todas: CitaEjemplo[]) {
  const q = normalizar(f.q)
  const datos = gestion.avance!
  const config = datos.control.configuracion
  const perfiles = new Map(datos.conversiones.map(c => [c.lead_id, c.perfil_id]))
  const identidades = new Map(datos.poblacion.map(p => [p.lead_id,
    p.identidad_persona ?? (perfiles.has(p.lead_id) ? `perfil:${perfiles.get(p.lead_id)}` : `lead:${p.lead_id}`)]))
  const personaEntrevistada = (lead: string) => identidades.get(lead) ?? `lead:${lead}`
  // El capital se cuenta por persona: identidad canónica del servidor o, si falta,
  // la del lead vinculado, el perfil cliente o el cierre externo.
  const personaCapital = (k: Capital) => k.identidad_persona ?? (k.lead_id && identidades.has(k.lead_id) ? identidades.get(k.lead_id)!
    : k.perfil_id ? `perfil:${k.perfil_id}` : k.lead_id ? `lead:${k.lead_id}` : `externo:${k.cierre_externo_id}`)
  const periodo = periodoAvance(filtros.mes, corte)
  const personas = new Map(datos.poblacion.filter(p => coincidePersona(p, filtros, todas)).map(p => [p.lead_id, p]))
  const roster = new Map([
    ...datos.capital.filter(k => k.analista_id).map(k => [k.analista_id!, {
      id: k.analista_id!, nombre: k.analista_nombre ?? 'Sin analista',
      supervisor: k.supervisor_nombre ?? 'Sin supervisor', supervisorId: k.supervisor_id ?? 'sin_supervisor',
    }] as const),
    ...datos.poblacion.filter(p => p.analista_origen_id).map(p => [p.analista_origen_id!, {
      id: p.analista_origen_id!, nombre: p.analista_origen_nombre,
      supervisor: p.supervisor_origen_nombre, supervisorId: p.supervisor_origen_id ?? 'sin_supervisor',
    }] as const),
    ...gestion.asignaciones.map(a => [a.id, { id: a.id, nombre: a.nombre, supervisor: a.supervisor, supervisorId: a.supervisorId }] as const),
    ...todas.map(c => [c.analista, { id: c.analista, nombre: c.analistaNombre, supervisor: c.supervisor, supervisorId: c.supervisorId }] as const),
    ...datos.conversiones.filter(c => c.analista_id).map(c => [c.analista_id!, { id: c.analista_id!, nombre: c.analista_nombre, supervisor: c.supervisor_nombre, supervisorId: c.supervisor_id ?? 'sin_supervisor' }] as const),
  ])
  const ambito = (id: string | null) => id !== null && (!filtros.analista || id === filtros.analista)
    && (!filtros.equipo || roster.get(id)?.supervisorId === filtros.equipo)
  const owner = (lead: string, evento: string | null) => config.analista_resultado === 'asignacion'
    ? personas.get(lead)?.analista_origen_id ?? null : evento
  const mesResultado = (p: Persona, fecha: string) => config.mes_resultado === 'asignacion'
    ? p.primera_asignacion_en !== null && fechaLocalCitas(p.primera_asignacion_en).startsWith(filtros.mes)
    : fechaLocalCitas(fecha).startsWith(filtros.mes)
  const limiteResultado = config.mes_resultado === 'asignacion' ? Date.parse(corte) : periodo.corte
  const actividad = (lead: string, id: string | null) => {
    const p = personas.get(lead)
    return p && (config.actividad_manuales === 'incluir' || !p.registro_manual || p.creado_por !== id)
  }
  const asignados = baseCitasFiltrada(gestion.asignaciones, { ...filtros, q: '' })
    .filter(p => personas.has(p.leadId) && (!config.excluir_manuales_base || !p.manualPropio))
  const registradas = todas.filter(c => c.creadoEn && personas.has(c.leadId) && ambito(c.analista)
    && actividad(c.leadId, c.analista) && Date.parse(c.creadoEn) >= periodo.inicio && Date.parse(c.creadoEn) <= periodo.corte)
  const resueltas = todas.filter(c => ['realizada', 'no_show'].includes(c.estado) && fechaResultado(c)
    && personas.has(c.leadId) && ambito(owner(c.leadId, c.analista)) && actividad(c.leadId, owner(c.leadId, c.analista))
    && Date.parse(fechaResultado(c)!) <= limiteResultado && mesResultado(personas.get(c.leadId)!, fechaResultado(c)!))
  const entrevistas = resueltas.filter(c => c.estado === 'realizada')
  const cierres = datos.conversiones.filter(c => personas.has(c.lead_id)
  const reglasListas = datos.control.version > 0 && datos.control.mes_inicio !== null && config.mes_inicio !== null
    && config.mes_resultado !== null && config.analista_resultado !== null && config.base_depositos !== null
    && config.base_avance !== null && config.conteo_entrevistas !== null && config.actividad_manuales !== null
  const resultados = (id?: string) => {
    const base = asignados.filter(p => !id || p.id === id)
    const citas = registradas.filter(c => !id || c.analista === id)
    const resultado = resueltas.filter(c => !id || owner(c.leadId, c.analista) === id)
    const visitas = entrevistas.filter(c => !id || owner(c.leadId, c.analista) === id)
    const gente = new Set(visitas.map(c => personaEntrevistada(c.leadId)))
    const clientesMes = cierres.filter(c => !id || owner(c.lead_id, c.analista_id) === id)
    // Cada fila compara entrevistas propias. El total del ámbito reconoce
    // también la colaboración entre analistas incluidos en la consulta.
    const vinculados = clientesMes.filter(c => visitas.some(v => personaEntrevistada(v.leadId) === personaEntrevistada(c.lead_id)
      && (!id || owner(v.leadId, v.analista) === owner(c.lead_id, c.analista_id))
      && instanteEntrevista(v) <= Date.parse(c.convertido_en)))
    const perfilesVinculados = new Set(vinculados.map(c => personaEntrevistada(c.lead_id)))
    const clientes = perfilesVinculados.size
    const clientesPeriodo = new Set(clientesMes.map(c => personaEntrevistada(c.lead_id))).size
    const fuera = new Set(clientesMes.filter(c => !perfilesVinculados.has(personaEntrevistada(c.lead_id))).map(c => personaEntrevistada(c.lead_id))).size
    const leads = new Set(base.map(p => p.leadId)).size
    const nEntrevistas = config.conteo_entrevistas === 'personas_unicas' ? gente.size : visitas.length
    const baseEntrevistas = config.base_avance === 'meta_proyectada' ? leads * config.citas_por_lead : resultado.length
    const baseConversion = config.base_depositos === 'entrevistas' ? visitas.length : gente.size
    const tasaEntrevistas = reglasListas && baseEntrevistas ? nEntrevistas / baseEntrevistas : null
    const conversion = reglasListas && baseConversion ? clientes / baseConversion : null
    // El ticket es mensual aunque el seguimiento esté configurado por cohorte.
        : !reglasListas ? 'Completa las reglas de gestión'
          : ticket === null ? 'Sin capital cerrado en el mes'
            : clientesEsperados === null ? 'Sin base de entrevistas' : null
    const proyeccion = monto === null || motivoProyeccion !== null ? null
      : periodo.cerrado ? monto
        : monto + Math.max(0, clientesEsperados! - clientesReales) * ticket!
    return { leads, citas: citas.length, promedio: leads ? citas.length / leads : null,
      cumplimiento: leads ? citas.length / (leads * config.citas_por_lead) * 100 : null,
      entrevistas: visitas.length, unicas: gente.size, resueltas: resultado.length, baseEntrevistas,
      tasaEntrevistas, conversion, clientes, clientesPeriodo, clientesFueraCohorte: fuera, baseConversion,
      ticket, motivoTicket, capital: monto, capitalPen, capitalUsd, faltaTipoCambio,
      clientesTicket: capitalPerfiles.size, sinContrato, operaciones, proyeccion, clientesEsperados, motivoProyeccion,
      manuales: base.filter(p => p.registroManual ?? p.manualPropio).length,
      sinCita: base.filter(p => !citas.some(c => c.leadId === p.leadId)),
      base, actividad: citas, visitas, vinculados, cierres: clientesMes, reglasListas }
  }
  // Un analista con capital en el mes tiene fila aunque no tenga leads ni citas.
  const ids = new Set([...asignados.map(p => p.id), ...registradas.map(c => c.analista),
    ...resueltas.map(c => owner(c.leadId, c.analista)), ...cierres.map(c => owner(c.lead_id, c.analista_id)),
    ...capitalMes.map(k => k.analista_id)])
  const filas = [...roster.values()].filter(a => ids.has(a.id) && ambito(a.id))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es')).map(a => ({ ...a, ...resultados(a.id) }))
  const calculables = filas.filter(f => f.proyeccion !== null)
  const total = { ...resultados(), proyeccion: calculables.length ? calculables.reduce((n, f) => n + f.proyeccion!, 0) : null,
    parciales: calculables.length, analistas: filas.length }
  // TESTIGO (F2, 21/09/2026). Sin ningún filtro puesto, el total de arriba tiene
  // que coincidir con lo que el servidor calculó por su cuenta. `null` = no
  // aplica (hay filtros, o el servidor aún no manda testigo). `false` = las
  // dos contabilidades discrepan: el número no se publica.
  const sinFiltros = !normalizar(filtros.q) && !filtros.leadId && !filtros.origen && !filtros.registro
    && !filtros.moneda && !filtros.analista && !filtros.equipo
  const testigo = gestion.testigo
  const testigoCuadra = !testigo || !sinFiltros ? null
    : testigo.reglas_listas === reglasListas
      && testigo.entrevistas === total.entrevistas
      && testigo.personas_entrevistadas === total.unicas
      && testigo.clientes_periodo === total.clientesPeriodo
      && testigo.clientes_vinculados === total.clientes
      && testigo.base_conversion === total.baseConversion
  return { filas, total, periodo, config, reglasListas, version: datos.control.version,
    tc: total.capitalUsd > 0 ? tcAplicable(tipoCambio) : null, testigoCuadra }
```

### app/src/components/citas/avance-mensual.tsx (líneas 25-35, 50-56, 99-118)
```tsx
  abrir?: (() => void) | undefined; parcial?: boolean;
}) {
  return <>
    <td>{numero(fila.leads)}</td>
    <td><strong>{numero(fila.citas)}</strong><small>{numero(fila.promedio, 2)} por lead</small></td>
    <td><SenalMetrica valor={fila.cumplimiento} objetivo={100} ritmo={resumen.periodo.ritmo} etiqueta="Avance de citas" abrir={abrir} barra /></td>
    <td><SenalMetrica valor={porcentaje(fila.tasaEntrevistas)} objetivo={resumen.config.entrevistas_porcentaje} etiqueta="Entrevistas" abrir={abrir} /><small>{numero(fila.entrevistas)} entrevistas</small></td>
    <td><SenalMetrica valor={porcentaje(fila.conversion)} objetivo={resumen.config.depositos_porcentaje} etiqueta="Depósito" abrir={abrir} /><small>{numero(fila.clientesPeriodo)} clientes</small>{fila.clientesFueraCohorte > 0 && <small>{numero(fila.clientes)} de entrevistas del periodo</small>}</td>
    <td title={fila.motivoTicket ?? `${fila.clientesTicket} clientes únicos con capital en el mes · ${desglose(fila.operaciones)} · todas las monedas convertidas a soles`}>{importe(fila.ticket, fila.faltaTipoCambio)}</td>
    <td className="cm-cierre" title={parcial && fila.proyeccion !== null ? 'Suma de los analistas con proyección calculable; los pendientes quedan fuera' : fila.motivoProyeccion ?? 'Estimación con el ritmo y el ticket del mes'}><strong>{importe(fila.proyeccion, fila.faltaTipoCambio)}</strong><small>{fila.proyeccion === null ? fila.motivoProyeccion : parcial ? 'Estimación parcial' : resumen.periodo.cerrado ? 'Resultado del mes' : 'Estimado al cierre'}</small></td>
  </>
  return <>
    <p className="cm-texto">{fila.supervisor} · {fila.manuales} leads de registro manual incluidos en la base.</p>
    <dl className="cm-desglose">
      <div><dt>Avance de citas</dt><dd><SenalMetrica valor={fila.cumplimiento} objetivo={100} ritmo={resumen.periodo.ritmo} etiqueta="Avance de citas" /><small>{faltantes ? `Faltan ${numero(faltantes)} citas para la meta del mes` : fila.leads ? 'Meta mensual alcanzada' : 'Sin base de leads asignados'}</small></dd></div>
      <div><dt>Entrevistas · objetivo {resumen.config.entrevistas_porcentaje}%</dt><dd><SenalMetrica valor={porcentaje(fila.tasaEntrevistas)} objetivo={resumen.config.entrevistas_porcentaje} etiqueta="Entrevistas" /><small>{fila.entrevistas} entrevistas / {numero(fila.baseEntrevistas, 2)} {resumen.config.base_avance === 'meta_proyectada' ? 'citas de meta' : 'citas con resultado'}</small></dd></div>
      <div><dt>Depósito · objetivo {resumen.config.depositos_porcentaje}%</dt><dd><SenalMetrica valor={porcentaje(fila.conversion)} objetivo={resumen.config.depositos_porcentaje} etiqueta="Depósito" /><small>{fila.clientes} clientes / {fila.baseConversion} {resumen.config.base_depositos === 'entrevistas' ? 'entrevistas' : 'personas entrevistadas'}</small></dd></div>
      <div><dt>Ticket del mes</dt><dd>{importe(fila.ticket, fila.faltaTipoCambio)}<small>{importe(fila.capital, fila.faltaTipoCambio)} / {fila.clientesTicket} clientes únicos con capital</small><small>{desglose(fila.operaciones)}</small><small>Originales: {money(fila.capitalPen, 'PEN')} · {money(fila.capitalUsd, 'USD')}</small></dd></div>
    <div className="cm-cabecera"><div><h2 id="cm-titulo">Avance mensual por analista</h2><p>{mes} · {resumen.config.excluir_manuales_base ? 'Sin altas manuales propias' : 'Leads manuales incluidos'} · ticket y proyección en soles</p><p aria-label="Capital del mes por moneda">Capital del mes: <strong>{money(resumen.total.capitalPen, 'PEN')}</strong> · <strong>{money(resumen.total.capitalUsd, 'USD')}</strong>{hayDolares && resumen.tc !== null && <> · {rotuloTipoCambio(resumen.tc, tc!.fuente)}</>}</p></div><div className="cm-acciones"><Button size="sm" variant="ghost" onClick={() => setAyuda(true)} aria-label="Cómo se calcula el avance mensual"><Info aria-hidden /></Button><Button size="sm" var
    {hayDolares && resumen.tc === null && <div role="status" className="cm-aviso cm-acciones"><span>{tc === undefined ? 'Consultando el tipo de cambio para incluir dólares…' : 'No se pudo obtener el tipo de cambio. El ticket y la proyección con dólares están pendientes.'}</span>{tc !== undefined && <Button size="sm" variant="outline" onClick={recargar}>Reintentar tipo de cambio</Button>}</div>}
    {!resumen.reglasListas && <p role="status" className="cm-aviso">Completa y aplica las reglas en el Control de Citas de Superadmin para calcular las tasas y la proyección.</p>}
    {(filtros.semana || filtros.estados.length || filtros.modalidad || filtros.resultado || filtros.seguimiento) && <p className="cm-alcance">La semana y los filtros de estado, modalidad, resultado y seguimiento delimitan el recorrido y la bandeja. Esta tabla conserva el acumulado mensual con su base completa.</p>}
    {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Tabla ancha consultable con flechas del teclado. */}
    <div className="cm-scroll" role="region" tabIndex={0} aria-label="Avance mensual por analista"><table className="cm-tabla">
      <caption className="sr-only">Leads, citas, entrevistas, depósito y proyección mensual. Los indicadores incluyen descripción de su estado.</caption>
      <thead><tr><th scope="col">Analista</th><th scope="col">Leads</th><th scope="col">Citas</th><th scope="col">Avance de citas<small>Meta mensual</small></th><th scope="col">Entrevistas<small>Objetivo {resumen.config.entrevistas_porcentaje}%</small></th><th scope="col">Depósito<small>Objetivo {resumen.config.depositos_porcentaje}%</small></th><th scope="col">Ticket del mes</th><th scope="col">Cierre proyectado</th></tr></thead>
      <tbody>{resumen.filas.map(f => <tr key={f.id}><th scope="row"><button className="cm-nombre" onClick={() => setAbierto(f.id)}><span className="cm-avatar" aria-hidden>{f.nombre.split(' ').slice(0, 2).map(p => p[0]).join('')}</span><span>{f.nombre}<small>{f.supervisor}</small></span><ChevronRight aria-hidden /></button></th><ColumnasAvance fila={f} resumen={resumen} abrir={() => setAbierto(f.id)} /></tr>)}</tbody>
      <tfoot><tr><th scope="row">Total del equipo<small>{resumen.total.parciales} de {resumen.total.analistas} con proyección</small></th><ColumnasAvance fila={resumen.total} resumen={resumen} parcial={resumen.total.parciales < resumen.total.analistas} /></tr></tfoot>
    </table></div>
    {!resumen.filas.length && <p className="cm-texto">No hay actividad ni leads asignados con estos filtros.</p>}
    <div className="cm-pie"><LeyendaResultados /><button onClick={() => setAyuda(true)} className="cm-ayuda">Cómo se calcula <Info aria-hidden /></button></div>
    <p role="status" className="sr-only">{exportado}</p>
    <Sheet open={Boolean(fila)} onClose={() => setAbierto(null)} className="cm-detalle w-[530px]"><SheetHeader><div className="cm-cabecera"><SheetTitle>{fila?.nombre ?? 'Detalle del analista'}</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar detalle del analista" onClick={() => setAbierto(null)}><X aria-hidden /></Button></div></SheetHeader><SheetBody>{fila && <DatosDelAnalista key={`${fila.id}-${filtros.mes}`} fila={fila} resumen={resumen} cerrar={() => setAbierto(null)} verCitas={() => { setAbierto(null); onAnalista(fila.id) }} />}</SheetBody></Sheet>
    <Sheet open={ayuda} onClose={() => setAyuda(false)} className="cm-detalle w-[530px]"><SheetHeader><div className="cm-cabecera"><SheetTitle>Cómo se calcula el avance</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar ayuda del avance" onClick={() => setAyuda(false)}><X aria-hidden /></Button></div></SheetHeader><SheetBody><div className="cm-reglas">
      <section><h3>Citas y base mensual</h3><p>Citas registradas en el CRM durante el mes, aunque su fecha prevista sea posterior. Se comparan con los leads asignados del mes, incluidos quienes aún no tienen cita. La meta se configura internamente en Superadmin.</p></section>
      <section><h3>Entrevistas y depósito</h3><p>Cada cita realizada con registro de entrevista suma una entrevista. {resumen.config.base_avance === 'meta_proyectada' ? 'La tasa compara entrevistas con la meta de citas.' : 'La tasa usa las citas con resultado: realizadas y no asistidas. Las futuras, canceladas y pendientes de resultado quedan fuera del divisor.'}</p><p>Se considera depósito cuando la persona se convierte en cliente. El porcentaje de depósito divide los clientes vinculados después de una entrevista entre {resumen.config.base_depositos === 'entrevistas' ? 'todas las entrevistas' : 'personas distintas entrevistadas'}. El cliente cuenta una vez; las visitas repetidas se conserva
      <section><h3>Mes y responsable</h3><p>{resumen.config.mes_resultado === 'asignacion' ? 'Los resultados siguen a los leads desde el mes de su primera asignación hasta el corte de seguimiento.' : 'Las entrevistas y los depósitos corresponden al mes en que se registraron sus resultados. Las inasistencias usan la fecha prevista de su cita.'} {resumen.config.analista_resultado === 'asignacion' ? 'Se atribuyen al primer analista del ledger de asignación.' : 'Se atribuyen al responsable de la cita y al analista que obtuvo el depósito, conservado en el historial.'}</p><p>La tasa de cada analista compara sus entrevistas. El total reconoce también cuando otro analista del equipo consigue el cier
      <section><h3>Ticket y cierre proyectado</h3><p>El ticket divide todo el capital real que el analista cierra en el mes entre sus clientes únicos con capital. Cuenta contratos nuevos, upgrades, renovaciones y cierres en cooperativas, tomados del mismo núcleo que Mi cartera y el Ranking y atribuidos al analista que figura allí; no exige que el cliente proceda de un lead convertido. No utiliza montos estimados. Incluye todas las monedas: conserva los totales originales en soles y dólares y convierte el capital en dólares a soles con el mismo servicio de tipo de cambio del CRM. Divide el total convertido entre clientes únicos, aunque una persona firme varias operaciones o invierta en ambas
```

### app/src/lib/control-citas.ts (líneas 7-36: esquema y valores iniciales)
```ts
export const ControlCitasSchema = v.strictObject({
  citas_por_lead: v.pipe(v.number(), v.finite(), v.minValue(0.01), v.maxValue(10), DosDecimales),
  entrevistas_porcentaje: Porcentaje,
  depositos_porcentaje: Porcentaje,
  excluir_manuales_base: v.boolean(),
  actividad_manuales: v.nullable(v.picklist(['excluir', 'incluir'])),
  conteo_entrevistas: v.nullable(v.picklist(['citas_realizadas', 'personas_unicas'])),
  base_avance: v.nullable(v.picklist(['meta_proyectada', 'actividad_real'])),
  mes_resultado: v.nullable(v.picklist(['asignacion', 'evento'])),
  analista_resultado: v.nullable(v.picklist(['asignacion', 'evento'])),
  mes_inicio: MesControlCitasSchema,
  mostrar_meta_citas: v.literal(false),
  base_depositos: v.nullable(v.picklist(['personas_entrevistadas', 'entrevistas'])),
})
export function controlCitasInicial(): ControlCitas {
  return {
    ...METAS_CITAS_INICIALES,
    excluir_manuales_base: false, actividad_manuales: 'incluir', conteo_entrevistas: 'citas_realizadas',
    base_avance: 'actividad_real', mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: null,
    mostrar_meta_citas: false, base_depositos: 'personas_entrevistadas',
  }
}
```

## Fuente SQL de las citas que recibe el front (transcrita)

### supabase/migrations/20260913225755_crm_citas_avance_fuentes.sql (líneas 80-140: fuente `citas` de la RPC)
```sql
    select t.*, l.nombre_completo, l.telefono, l.origen, l.moneda, l.monto_estimado, l.alta_manual, l.creado_por as lead_creado_por,
      e.modalidad as modalidad_canonica, e.resultado as resultado_canonico,
      case when e.pendiente_cierre then 'vencida'
        when e.programada_futura then 'programada'
        when e.realizada then 'realizada'
        when e.no_show then 'no_show'
        when e.reprogramada then 'reprogramada'
        when e.cancelada_asesor then 'cancelada'
        when e.cancelada_sistema then 'sistema'
      end as estado_comercial
    from limites_historial b
    cross join lateral private.citas_episodios(
      coalesce(b.inicio,v_ini),coalesce(b.fin,v_fin),v_ahora,
      coalesce((select array_agg(c.lead_id) from cohorte c),'{}'::uuid[])) e
    join cohorte c on c.lead_id=e.lead_id
    join crm.tareas t on t.id=e.tarea_id
    join crm.leads l on l.id=e.lead_id
    where t.creado_en<=v_ahora
    -- La fila extra dispara un error; nunca se entrega un historial truncado.
    order by t.vence_en,t.id limit 10001
  ), cierres as materialized (
    -- Los hechos de cierre proceden del núcleo. Ningún aporte ponderado
    -- participa en este indicador operativo. El factor no modifica el hecho.
    -- Basta desde la primera cita: sólo se pregunta por cierres posteriores.
    select e.lead_id,max(e.fecha_numerador) as ultimo_cierre
    from private.conversion_cierres(
      coalesce((select min(h.vence_en) from historial h),v_ini),
      v_ahora+interval '1 microsecond',p_desde,true,'{}'::uuid[],1,
      coalesce((select array_agg(c.lead_id) from cohorte c),'{}'::uuid[])) e
    join cohorte c on c.lead_id=e.lead_id
    where e.tipo='cierre' and not e.anulado and e.fecha_numerador<=v_ahora
    group by e.lead_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'lead_id',t.lead_id,'nombre',t.nombre_completo,'telefono',t.telefono,
    'analista_id',t.vendedor_id,'analista_nombre',coalesce(p.nombre_completo,'Sin analista'),
    'supervisor_id',coalesce(e.supervisor_id,t.asignado_supervisor_id),
    'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'vence_en',t.vence_en,'estado',t.estado,'estado_comercial',t.estado_comercial,'cancelada_por',t.cancelada_por,
    'modalidad',t.modalidad_canonica,'origen',t.origen,
    'moneda',t.moneda,'monto_estimado',t.monto_estimado,
    'resultado',t.resultado_canonico,
    'nota',coalesce(t.detalle_cierre_reunion,t.nota,''),
    'reagendada_de',anterior.id,
    'creado_en',t.creado_en,
    'manual_propio',coalesce(t.alta_manual and t.lead_creado_por=t.vendedor_id,false),
    'registro_manual',coalesce(t.alta_manual,false),
    'asistencia_registrada_en',case when t.estado='completada' then a.creado_en end,
    'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false)
  ) order by t.vence_en,t.id),'[]'::jsonb) into v_filas
  from historial t
  left join historial anterior on anterior.id=t.reagendada_de and anterior.lead_id=t.lead_id
  left join cierres c on c.lead_id=t.lead_id
  left join public.perfiles p on p.id=t.vendedor_id
  left join crm.equipo e on e.perfil_id=t.vendedor_id
  left join public.perfiles ps on ps.id=coalesce(e.supervisor_id,t.asignado_supervisor_id)
  left join crm.actividades a on a.id=t.resultado_actividad_id and a.lead_id=t.lead_id
    and a.tipo='reunion_realizada' and a.creado_en<=v_ahora;

  -- Nunca devolver un subconjunto como si fuera la totalidad de la consulta.
  if jsonb_array_length(v_filas)>10000 then
```

Notas del lector SQL (`private.citas_gerencia_consulta`, parcheada después en `20260914044939`, `20260915170018` y
`20260927172931`): las citas se atribuyen a `tareas.vendedor_id` (tenencia espejo del lead; un trigger la reescribe
al reasignar SOLO en tareas `pendiente`; las cerradas conservan el analista que tenían). `asistioEn` viene de
`actividades.creado_en` de la actividad `reunion_realizada` enlazada por `resultado_actividad_id`; sin esa
actividad, una `completada` NO cuenta como entrevista. El estado `no_show` toma como fecha de resultado
`vence_en` (hora de Lima, al minuto).

## Reproducción en producción (solo SELECT, CLI `supabase db query --linked`, 28/09 15:41–15:46 Lima)

La puerta `crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30')` ejecutada sin sesión devuelve
`ERROR 42501 No autorizado` (depende de `auth.uid()`), así que el PRIMARY rehízo el lector a mano con el subárbol
de Jorge (`crm.equipo`, recursivo) y, como segunda vía, contó directo sobre `crm.tareas`. Ambas vías coinciden.

JORGE MARZANO: id `0eeb8c64…`, rol CRM `supervisor`. 10 analistas a cargo, todos activos: Alan Yutronic, Astrid
Centenaro, Daniela A. Castillo, Fiorella Ruiz, Grecia Ramírez, Kelly Vega, Merlys García, Miguel Briceño (perfil
de PRUEBAS del dueño), Rosa Aguirre, Vladimir Jurado.

```sql
-- Conteo equivalente a la pantalla → 160 / 37 / 55 (92 = 37 + 55)
with recursive vis(perfil_id) as (
  select perfil_id from crm.equipo where perfil_id='0eeb8c64-25e4-418b-b5d5-e07b06758b5e'
  union select e.perfil_id from crm.equipo e join vis s on e.supervisor_id=s.perfil_id
), t as (
  select t.*, a.creado_en as asistio_en
  from crm.tareas t join crm.leads l on l.id=t.lead_id and l.activo
  left join crm.actividades a on a.id=t.resultado_actividad_id and a.lead_id=t.lead_id
       and a.tipo='reunion_realizada' and a.creado_en<=now()
  where t.tipo='reunion' and t.activo and t.vendedor_id in (select perfil_id from vis))
select
  count(*) filter (where creado_en>='2026-09-01 00:00-05' and creado_en<=now()) as citas,
  count(*) filter (where estado='completada' and asistio_en>='2026-09-01 00:00-05' and asistio_en<'2026-10-01 00:00-05' and asistio_en<=now()) as entrevistas,
  count(*) filter (where estado='no_show' and date_trunc('minute',vence_en)>='2026-09-01 00:00-05'
                   and date_trunc('minute',vence_en)<'2026-10-01 00:00-05' and date_trunc('minute',vence_en)<=now()) as no_asistio
from t;
-- → citas 160 · entrevistas 37 · no_asistio 55
```

### Resultado frente a la pantalla

| Pantalla | Reproducido | Definición que lo reproduce |
|---|---|---|
| 160 citas | 160 | tareas reunión activas con lead activo, `creado_en` en [01/09 00:00 Lima, now()], `vendedor_id` en el subárbol de Jorge, cualquier estado |
| 37 entrevistas | 37 | `completada` con actividad `reunion_realizada` creada en septiembre hasta now() |
| divisor | 92 | 37 realizadas + 55 `no_show` con `vence_en` (al minuto) en septiembre y ≤ now() |
| 40,2 % | 37/92 = 40,22 % | `tasaEntrevistas` con `base_avance = actividad_real` |

Matices: (a) en 159 de las 160 el creador coincide con el responsable; la excepción (`a1921fa9`) la creó Carlos
Valles (gerencia) y su responsable es Kelly Vega. (b) La población son TODOS los leads del payload, no solo los
asignados en el mes: contando solo leads asignados al equipo en septiembre saldrían 143 citas, no 160.

### Desglose por estado

| Estado | Creadas en sep. (las 160) | Con fecha en sep. | Dentro del divisor 92 |
|---|---|---|---|
| Realizada | 35 | 36 | 37 |
| No asistió | 55 | 56 | 55 |
| Vencida sin resultado | 24 | 25 | 0 |
| Programada | 29 (17 con fecha en octubre) | 12 | 0 |
| Cancelada por asesor | 6 | 6 | 0 |
| Cancelada por sistema | 6 | 6 | 0 |
| Reprogramada | 5 | 6 | 0 |
| Total | 160 | 147 | 92 |

- De las 92 con resultado, 89 están entre las 160; las otras 3 se crearon en agosto (dos realizadas `38b0ceac`,
  `6a26687a`, y un no asistió `5057a53a`).
- De las 160 quedan fuera del divisor 71: 29 programadas, 24 vencidas, 17 canceladas/reprogramadas y 1 no asistió
  con fecha futura.
- Las 160 citas corresponden a 95 leads distintos; 39 son reprogramaciones o recuperaciones de otra cita. Las 92
  con resultado corresponden a 62 leads; las 37 entrevistas a 29 personas distintas.
- El equipo tiene en realidad 162 reuniones creadas en septiembre: 2 de Vladimir con un inversionista y SIN lead,
  que el módulo de Citas no cuenta (el lector exige lead).

### Por analista (subárbol de Jorge)

| Analista | Leads asignados en sep. | Citas creadas | Con resultado | Realizadas | No asistió | % |
|---|---|---|---|---|---|---|
| Alan Yutronic | 139 | 56 | 33 | 12 | 21 | 36,4 |
| Astrid Centenaro | 119 | 7 | 5 | 3 | 2 | 60,0 |
| Daniela A. Castillo | 77 | 9 | 5 | 2 | 3 | 40,0 |
| Fiorella Ruiz | 113 | 22 | 16 | 7 | 9 | 43,8 |
| Grecia Ramírez | 0 | 0 | 0 | 0 | 0 | — |
| Kelly Vega | 92 | 1 | 1 | 1 | 0 | 100 |
| Merlys García | 79 | 0 | 0 | 0 | 0 | — |
| Miguel Briceño (pruebas) | 46 | 1 (vencida) | 0 | 0 | 0 | — |
| Rosa Aguirre | 116 | 28 | 14 | 8 | 6 | 57,1 |
| Vladimir Jurado | 121 | 36 | 18 | 4 | 14 | 22,2 |
| Jorge Marzano | 1 | 0 | 0 | 0 | 0 | — |
| Total | 895 leads distintos (903 pares) | 160 | 92 | 37 | 55 | 40,2 |

### Variantes probadas (ninguna reproduce la pantalla)

- Por fecha de la cita en vez de creación: 147 (134 solo pasadas).
- Realizadas por fecha de la cita en vez de por asistencia: 36 → 36/91 = 39,6 % (diferencia: `38b0ceac`, cita del
  31/08 con asistencia registrada el 28/09).
- Por dueño del lead (primer analista asignado): sigue 160/92/37.
- Personas únicas: 29 → 29/92 = 31,5 %.
- Meta proyectada como divisor: 37 / (895 × 1,25) = 3,3 %.
- Entrevistas sobre citas creadas: 37/160 = 23,1 %.

### Anomalías de datos detectadas

1. **Un «no asistió» con fecha FUTURA.** Cita `53b4ac59` (Fiorella Ruiz), creada el 23/09 17:15 como
   reprogramación de `4f73735d` (prevista 22/09 10:00). Quedó con fecha 30/09 17:14:56 (parece un «+7 días»
   automático) y 2,5 minutos después se marcó `cliente_no_asistio`. Hoy queda fuera del divisor; el 30/09 a las
   17:14 entrará sola y la tasa bajará a 37/93 = 39,8 % sin que nadie toque nada.
2. **Entrevistas repetidas:** 5 leads suman 13 de las 37 entrevistas; Alan tiene dos leads con tres entrevistas
   cada uno en días seguidos.
3. **Asistencia registrada ANTES de la fecha de la cita:** dos entrevistas de Alan tienen la asistencia el 23/09 y la
   cita prevista el 24/09 y 25/09.
4. Las 25 citas vencidas sin resultado quedan fuera del divisor: según cómo se cierren, la tasa del mes podría
   moverse entre 31,6 % (37/117, todas «no asistió») y 53,0 % (62/117, todas entrevista).

## Qué te pido refutar (con evidencia de este encargo)

1. ¿La lectura del código es correcta? En particular: `registradas` (creación, `vendedor_id`), `resueltas`
   (`realizada` por `asistioEn`, `no_show` por fecha prevista), `limiteResultado`/`mesResultado` con `evento`, y
   `baseEntrevistas = resultado.length` con `actividad_real`. ¿Hay algún filtro del front (`ambito`, `actividad`,
   `personas`, `owner`) que la reproducción SQL NO aplicó y que podría cambiar 160, 92 o 37?
2. ¿Es coherente mostrar «160 citas» y «40,2 %» en la misma fila cuando el divisor del % (92) no es un subconjunto
   de las 160 (3 citas de agosto entran; 71 de las 160 no)? ¿Es un defecto de presentación que el pie «Total del
   equipo» no exponga el divisor (solo lo hace el detalle por analista, `avance-mensual.tsx:54`)? Clasifica su
   severidad para el usuario que pregunta «¿37 de 160 es 40,2 %?».
3. La anomalía 1 (no asistió con fecha futura): ¿evidencia un defecto del flujo de reprogramación/cierre en el CRM
   (marcar «no asistió» sobre una cita futura) o del cálculo (usar `vence_en` como fecha de resultado del no_show en
   vez de la fecha en que se marcó)? Argumenta con el código transcrito; marca como hipótesis lo que no puedas ver.
4. La anomalía 3 (asistencia antes de la cita) y las entrevistas repetidas del mismo lead en días seguidos: ¿son
   compatibles con la regla «si una persona asiste dos veces, suma dos entrevistas» o apuntan a registros dobles?
   ¿Qué comprobación concreta (SQL de solo lectura o test) lo distinguiría?
5. El perfil de pruebas de Miguel está dentro del equipo de Jorge (46 leads asignados en sep., 1 cita vencida).
   ¿Afecta a alguna de las tres cifras? Cuantifica con la tabla por analista.
6. ¿Hay TEST GAPS reales? Según el PRIMARY, ningún test del front fija un `no_show` en el divisor, ni
   `meta_proyectada`, ni `personas_unicas` aplicados a la tasa; y el testigo del servidor no cubre 160 ni 92.

## Protocolo transcrito (.ai/REVIEW_PROTOCOL.md)

# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.
