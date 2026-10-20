ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo r2 (LEVEL 3, última pasada): VERIFICA las correcciones a tu revisión r1 de «Proyección: % Entrev. y % Conv. como Resultados»

Tu r1 (REQUEST_CHANGES) y lo que hizo el PRIMARY con cada punto:

1. P2 base de `meta_proyectada` con asignaciones fuera del rango → ACEPTADO. Evidencia previa (producción, solo lectura): las 1 983 asignaciones del lector de octubre tienen `asignado_en` en octubre, así que acotar por día no cambia Resultados. `asignadosDeLaMeta(base, personas, control, { desde, hasta })` ahora exige el día de Lima de `asignadoEn` dentro del periodo (fecha inválida → fuera); Resultados le pasa el mes y la Proyección su rango. Tu caso numérico es una prueba: 1–10 oct → base 1 y 100 %; 1–31 oct → base 2 y 50 %. Además, con `meta_proyectada` los analistas con base en el rango tienen fila (Citas 0, 0 %) como en Resultados (`conMeta`), y la comprobación inversa de filas exige también esas filas.
2. P3 Ayuda → ACEPTADO. % Entrev.: «el de Resultados para el periodo … con las reglas de gestión; cuenta resultados de citas creadas antes del periodo» (sin afirmar la regla de fecha). Proyectado: «× la proporción de citas con resultado que fueron entrevista» (la tasa observada que usa el código).
3. P3 copias cuadráticas → ACEPTADO: `push` en la agrupación de conversiones y también en `porAnalista` (esa ya era cuadrática antes).
4. TEST GAPS:
   - Combinaciones: `REGLAS` añade todas las reglas no habituales a la vez y { asignacion + entrevistas + personas_unicas }; `CONSULTAS` añade supervisor + analista (mismo equipo y otro equipo).
   - Regresión compartida: verificación TEMPORAL (no versionada) con el `avance.ts` ANTERIOR (de git) frente al nuevo: `expect(ahora).toEqual(antes)` sobre filas y total completos en 420 casos = 3 meses × 10 reglas (incluidas `actividad_manuales: null` y `mes_inicio: null`) × 7 filtros (incl. origen y búsqueda q) × 2 cortes, con asignaciones en el mes (como el servidor). 420/420 idénticos.
   - Rendimiento (medido, temporal): 3 000 citas, 2 000 personas, 600 ventas. Antes de cachear el formateador: Proyección anterior 106 ms, nueva 286 ms, nueva con embudo de Analista 523 ms. Causa: `fechaLocalCitas` creaba un `Intl.DateTimeFormat` en cada llamada. Ahora es un formateador de módulo (mismas opciones) y las citas proyectadas del lector se calculan una vez y se reutilizan en las dos pasadas: anterior 14 ms, nueva 30 ms, con embudo 34 ms.
   - `fusionarConsultasCitas`/`ultimoPorLead` en rangos multi-mes: NO tocado; es el comportamiento previo de la Proyección (una conversión por lead). Lo dejo como hipótesis tuya no confirmada.

Verificación (PRIMARY; NOT RUN por ti): `npm run check` PASS 7 492; vitest de Citas 262/262 con la verificación temporal; E2E Docker de los 5 specs de Citas 20/20 (antes de estas correcciones; el E2E completo va después de esta revisión). Datos reales de Alan: Resultados y Proyección 15,0376 % (20/133).

Busca con evidencia: (a) si alguna corrección rompe la paridad mensual o introduce otra diferencia; (b) si el filtro por `asignadoEn` puede excluir en Resultados algo que antes contaba con datos reales del servidor (fechas en UTC vs día de Lima: `asignado_en` 2026-10-01T03:00Z es 30/09 en Lima); (c) el formateador compartido (concurrencia, zona, fechas inválidas); (d) filas `conMeta` con el embudo de Analista/supervisor; (e) pruebas que no prueben lo que dicen.

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## resultados-periodo.ts (completo)
```ts
// Resultados de citas de un PERIODO: qué citas tuvieron su resultado en él, qué
// ventas caen en su fecha comercial y las tasas de entrevistas y de conversión.
// UNA sola implementación para Resultados (`calcularAvanceCitas`, el mes de la
// consulta) y la Proyección (`calcularProyeccion`, su rango Desde–Hasta): «no
// puede haber data distinta» (Miguel, 19/10/2026). El 20/10 la Proyección daba
// otro % Entrev. porque medía las citas CREADAS en el rango: un resultado cuenta
// en el periodo en que ocurrió, no en el que se creó la cita.
import type { GestionMensualCitas } from '@/lib/gestion-citas'
import { reglaDueno, ventaCierraEntrevista } from './atribucion'
import { fechaLocalCitas, ventaComercialDelPeriodo, type PeriodoComercial } from './fecha-comercial'
import type { LeadBaseCitas } from './metas'
import type { CitaEjemplo } from './modelo'

type Control = GestionMensualCitas['control']
export type CitaResultado = Pick<CitaEjemplo, 'leadId' | 'analista' | 'estado' | 'asistioEn' | 'fecha' | 'hora'>
export type PersonaResultado = Pick<GestionMensualCitas['poblacion'][number],
  'analista_origen_id' | 'registro_manual' | 'creado_por' | 'primera_asignacion_en'>
export interface VentaResultado { lead_id: string; analista_id: string | null; fecha_comercial?: string | null | undefined; convertido_en: string }

/** Instante del resultado: la asistencia registrada de una realizada; la hora prevista de una inasistencia. */
export const fechaResultado = (c: CitaResultado) => c.estado === 'realizada' ? c.asistioEn : `${c.fecha}T${c.hora}:00-05:00`

/** Reglas de gestión completas; sin ellas las tasas quedan «sin base». */
export function reglasListas({ version, mes_inicio, configuracion: config }: Control): boolean {
  return version > 0 && mes_inicio !== null && config.mes_inicio !== null
    && config.mes_resultado !== null && config.analista_resultado !== null && config.base_depositos !== null
    && config.base_avance !== null && config.conteo_entrevistas !== null && config.actividad_manuales !== null
}

/**
 * Leads de la base que cuentan para la meta: asignados en el periodo, de la consulta y sin los manuales propios si
 * la regla los excluye. El lector del mes ya trae solo los asignados en el mes; un rango más corto los recorta.
 */
export const asignadosDeLaMeta = <L extends Pick<LeadBaseCitas, 'leadId' | 'manualPropio' | 'asignadoEn'>>(
  base: readonly L[], personas: ReadonlyMap<string, unknown>, control: Control, { desde, hasta }: Pick<PeriodoComercial, 'desde' | 'hasta'>,
) => base.filter(p => {
  const dia = Number.isFinite(Date.parse(p.asignadoEn)) ? fechaLocalCitas(p.asignadoEn) : ''
  return dia >= desde && dia <= hasta && personas.has(p.leadId) && (!control.configuracion.excluir_manuales_base || !p.manualPropio)
})

export interface AnalistaRoster { id: string; nombre: string; supervisor: string; supervisorId: string }
type Fuente<T> = readonly T[] | undefined
/**
 * Analistas con su nombre y supervisor, de todo lo que llega en la consulta. Si
 * un analista aparece en varias fuentes manda la ÚLTIMA: capital, población de
 * origen, base asignada, citas y ventas. El supervisor decide el ámbito.
 */
export function rosterDeAnalistas(f: {
  capital?: Fuente<{ analista_id: string | null; analista_nombre?: string | null | undefined; supervisor_id?: string | null | undefined; supervisor_nombre?: string | null | undefined }>
  poblacion?: Fuente<{ analista_origen_id?: string | null | undefined; analista_origen_nombre?: string | undefined; supervisor_origen_id?: string | null | undefined; supervisor_origen_nombre?: string | undefined }>
  asignaciones?: Fuente<Pick<LeadBaseCitas, 'id' | 'nombre' | 'supervisor' | 'supervisorId'>>
  citas: readonly Pick<CitaEjemplo, 'analista' | 'analistaNombre' | 'supervisor' | 'supervisorId'>[]
  ventas?: Fuente<{ analista_id: string | null; analista_nombre?: string | undefined; supervisor_id?: string | null | undefined; supervisor_nombre?: string | undefined }>
}): Map<string, AnalistaRoster> {
  const fila = (id: string, nombre: string | null | undefined, supervisor: string | null | undefined, supervisorId: string | null | undefined) =>
    [id, { id, nombre: nombre ?? 'Sin analista', supervisor: supervisor ?? 'Sin supervisor', supervisorId: supervisorId ?? 'sin_supervisor' }] as const
  return new Map([
    ...(f.capital ?? []).flatMap(k => k.analista_id ? [fila(k.analista_id, k.analista_nombre, k.supervisor_nombre, k.supervisor_id)] : []),
    ...(f.poblacion ?? []).flatMap(p => p.analista_origen_id ? [fila(p.analista_origen_id, p.analista_origen_nombre, p.supervisor_origen_nombre, p.supervisor_origen_id)] : []),
    ...(f.asignaciones ?? []).map(a => fila(a.id, a.nombre, a.supervisor, a.supervisorId)),
    ...f.citas.map(c => fila(c.analista, c.analistaNombre, c.supervisor, c.supervisorId)),
    ...(f.ventas ?? []).flatMap(c => c.analista_id ? [fila(c.analista_id, c.analista_nombre, c.supervisor_nombre, c.supervisor_id)] : []),
  ])
}

export interface EntradaResultados<C extends CitaResultado, V extends VentaResultado> {
  citas: readonly C[]
  ventas: readonly V[]
  /** Personas (leads) que admite la consulta. */
  personas: ReadonlyMap<string, PersonaResultado>
  /** Identidad de la persona del lead: el cliente cuenta una vez aunque tenga varios leads. */
  identidad: (lead: string) => string
  control: Control
  periodo: PeriodoComercial
  /** Analistas de la consulta (`enAmbito`). */
  ambito: (analista: string | null) => boolean
}

export function resultadosDelPeriodo<C extends CitaResultado, V extends VentaResultado>(e: EntradaResultados<C, V>) {
  const config = e.control.configuracion
  const listas = reglasListas(e.control)
  const corte = Date.parse(e.periodo.corte)
  const dueno = reglaDueno(config.analista_resultado, lead => e.personas.get(lead)?.analista_origen_id)
  const actividad = (lead: string, id: string | null) => {
    const p = e.personas.get(lead)
    return p !== undefined && (config.actividad_manuales === 'incluir' || !p.registro_manual || p.creado_por !== id)
  }
  const enPeriodo = (instante: string) => {
    const dia = fechaLocalCitas(instante)
    return dia >= e.periodo.desde && dia <= e.periodo.hasta
  }
  // «asignacion»: los resultados de los leads asignados por primera vez en el periodo, hasta el corte.
  const delPeriodo = (p: PersonaResultado, fecha: string) => config.mes_resultado === 'asignacion'
    ? p.primera_asignacion_en !== null && enPeriodo(p.primera_asignacion_en) : enPeriodo(fecha)
  const resueltas = e.citas.filter(c => {
    const fecha = fechaResultado(c)
    const suyo = dueno(c.leadId, c.analista)
    return (c.estado === 'realizada' || c.estado === 'no_show') && fecha !== undefined
      && e.personas.has(c.leadId) && e.ambito(suyo) && actividad(c.leadId, suyo)
      && Date.parse(fecha) <= corte && delPeriodo(e.personas.get(c.leadId)!, fecha)
  })
  const entrevistas = resueltas.filter(c => c.estado === 'realizada')
  const cierres = e.ventas.filter(c => e.personas.has(c.lead_id)
    && e.ambito(dueno(c.lead_id, c.analista_id)) && actividad(c.lead_id, dueno(c.lead_id, c.analista_id))
    && ventaComercialDelPeriodo(c, e.periodo))

  /**
   * Tasas de un analista o, sin él, del total del ámbito. `leads`: base de la meta
   * (regla «meta_proyectada»). `duenos` acota las citas del total a esos analistas
   * (filas visibles); las ventas siguen siendo las del ámbito.
   */
  function medir(analista?: string, leads = 0, duenos?: ReadonlySet<string>) {
    const suya = (id: string | null) => analista ? id === analista : !duenos || (id !== null && duenos.has(id))
    const resultado = resueltas.filter(c => suya(dueno(c.leadId, c.analista)))
    const visitas = entrevistas.filter(c => suya(dueno(c.leadId, c.analista)))
    const gente = new Set(visitas.map(c => e.identidad(c.leadId)))
    const ventas = cierres.filter(c => !analista || dueno(c.lead_id, c.analista_id) === analista)
    // Cada fila compara entrevistas propias. El total del ámbito reconoce
    // también la colaboración entre analistas incluidos en la consulta.
    const cierra = (v: C, venta: V) => e.identidad(v.leadId) === e.identidad(venta.lead_id)
      && ventaCierraEntrevista(v.asistioEn, { dueno: dueno(venta.lead_id, venta.analista_id), fecha_comercial: venta.fecha_comercial ?? null }, analista || null)
    const vinculados = ventas.filter(venta => visitas.some(v => cierra(v, venta)))
    const clientes = new Set(vinculados.map(c => e.identidad(c.lead_id))).size
    const nEntrevistas = config.conteo_entrevistas === 'personas_unicas' ? gente.size : visitas.length
    const baseEntrevistas = config.base_avance === 'meta_proyectada' ? leads * config.citas_por_lead : resultado.length
    const baseConversion = config.base_depositos === 'entrevistas' ? visitas.length : gente.size
    return {
      resultado, visitas, gente, ventas, vinculados, clientes, nEntrevistas, baseEntrevistas, baseConversion,
      /** Las entrevistas que cerraron una de esas ventas. */
      visitasVinculadas: visitas.filter(v => vinculados.some(venta => cierra(v, venta))),
      tasaEntrevistas: listas && baseEntrevistas ? nEntrevistas / baseEntrevistas : null,
      conversion: listas && baseConversion ? clientes / baseConversion : null,
    }
  }
  return { listas, dueno, actividad, resueltas, entrevistas, cierres, medir }
}
```

## Diff completo de app/src (frente a producción; resultados-periodo.ts es nuevo)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/citas/avance.ts b/CRM-Avance-Corp/app/src/components/citas/avance.ts
index acc03154..f415922d 100644
--- a/CRM-Avance-Corp/app/src/components/citas/avance.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/avance.ts
@@ -3,7 +3,8 @@ import { baseCitasFiltrada, type GestionCitas } from './metas'
 import type { GestionMensualCitas } from '@/lib/gestion-citas'
 import { totalEnSoles, tcAplicable } from '@/lib/capital-unificado'
 import { fechaLocalCitas, ventaComercialDelMes } from './fecha-comercial'
-import { enAmbito, reglaDueno, ventaCierraEntrevista } from './atribucion'
+import { enAmbito } from './atribucion'
+import { asignadosDeLaMeta, resultadosDelPeriodo, rosterDeAnalistas } from './resultados-periodo'
 export { fechaLocalCitas } from './fecha-comercial'
 
 type Persona = GestionMensualCitas['poblacion'][number]
@@ -11,7 +12,6 @@ type Capital = GestionMensualCitas['capital'][number]
 const TIPOS_CAPITAL = { contrato_nuevo: 'nuevos', contrato_upgrade: 'upgrades', contrato_renovacion: 'renovaciones', cooperativa: 'cooperativas' } as const
 export type OperacionesCapital = Record<(typeof TIPOS_CAPITAL)[keyof typeof TIPOS_CAPITAL], number>
 const instanteCita = (c: CitaEjemplo) => Date.parse(`${c.fecha}T${c.hora}:00-05:00`)
-const fechaResultado = (c: CitaEjemplo) => c.estado === 'realizada' ? c.asistioEn : `${c.fecha}T${c.hora}:00-05:00`
 export function periodoAvance(mes: string, corte: string) {
   const [anio, numero] = mes.split('-').map(Number)
   const dias = new Date(Date.UTC(anio!, numero!, 0)).getUTCDate()
@@ -53,41 +53,17 @@ export function calcularAvanceCitas(gestion: GestionCitas, todas: CitaEjemplo[],
     : k.perfil_id ? `perfil:${k.perfil_id}` : k.lead_id ? `lead:${k.lead_id}` : `externo:${k.cierre_externo_id}`)
   const periodo = periodoAvance(filtros.mes, corte)
   const personas = new Map(datos.poblacion.filter(p => coincidePersona(p, filtros, todas)).map(p => [p.lead_id, p]))
-  const roster = new Map([
-    ...datos.capital.filter(k => k.analista_id).map(k => [k.analista_id!, {
-      id: k.analista_id!, nombre: k.analista_nombre ?? 'Sin analista',
-      supervisor: k.supervisor_nombre ?? 'Sin supervisor', supervisorId: k.supervisor_id ?? 'sin_supervisor',
-    }] as const),
-    ...datos.poblacion.filter(p => p.analista_origen_id).map(p => [p.analista_origen_id!, {
-      id: p.analista_origen_id!, nombre: p.analista_origen_nombre,
-      supervisor: p.supervisor_origen_nombre, supervisorId: p.supervisor_origen_id ?? 'sin_supervisor',
-    }] as const),
-    ...gestion.asignaciones.map(a => [a.id, { id: a.id, nombre: a.nombre, supervisor: a.supervisor, supervisorId: a.supervisorId }] as const),
-    ...todas.map(c => [c.analista, { id: c.analista, nombre: c.analistaNombre, supervisor: c.supervisor, supervisorId: c.supervisorId }] as const),
-    ...datos.conversiones.filter(c => c.analista_id).map(c => [c.analista_id!, { id: c.analista_id!, nombre: c.analista_nombre, supervisor: c.supervisor_nombre, supervisorId: c.supervisor_id ?? 'sin_supervisor' }] as const),
-  ])
+  const roster = rosterDeAnalistas({ capital: datos.capital, poblacion: datos.poblacion, asignaciones: gestion.asignaciones, citas: todas, ventas: datos.conversiones })
   const alcance = { analistas: filtros.analista ? new Set([filtros.analista]) : null, equipo: filtros.equipo, supervisorDe: (id: string) => roster.get(id)?.supervisorId }
   const ambito = (id: string | null) => enAmbito(id, alcance)
-  const owner = reglaDueno(config.analista_resultado, lead => personas.get(lead)?.analista_origen_id)
-  const mesResultado = (p: Persona, fecha: string) => config.mes_resultado === 'asignacion'
-    ? p.primera_asignacion_en !== null && fechaLocalCitas(p.primera_asignacion_en).startsWith(filtros.mes)
-    : fechaLocalCitas(fecha).startsWith(filtros.mes)
-  const limiteResultado = config.mes_resultado === 'asignacion' ? Date.parse(corte) : periodo.corte
-  const actividad = (lead: string, id: string | null) => {
-    const p = personas.get(lead)
-    return p && (config.actividad_manuales === 'incluir' || !p.registro_manual || p.creado_por !== id)
-  }
-  const asignados = baseCitasFiltrada(gestion.asignaciones, { ...filtros, q: '' })
-    .filter(p => personas.has(p.leadId) && (!config.excluir_manuales_base || !p.manualPropio))
+  // Citas con resultado, ventas y tasas del mes: la regla compartida con la Proyección.
+  const delPeriodo = { desde: `${filtros.mes}-01`, hasta: `${filtros.mes}-${String(periodo.dias).padStart(2, '0')}`, corte }
+  const delMes = resultadosDelPeriodo({ citas: todas, ventas: datos.conversiones, personas, identidad: personaEntrevistada,
+    control: datos.control, periodo: delPeriodo, ambito })
+  const { dueno: owner, actividad, resueltas, cierres, listas: reglasListas } = delMes
+  const asignados = asignadosDeLaMeta(baseCitasFiltrada(gestion.asignaciones, { ...filtros, q: '' }), personas, datos.control, delPeriodo)
   const registradas = todas.filter(c => c.creadoEn && personas.has(c.leadId) && ambito(c.analista)
     && actividad(c.leadId, c.analista) && Date.parse(c.creadoEn) >= periodo.inicio && Date.parse(c.creadoEn) <= periodo.corte)
-  const resueltas = todas.filter(c => ['realizada', 'no_show'].includes(c.estado) && fechaResultado(c)
-    && personas.has(c.leadId) && ambito(owner(c.leadId, c.analista)) && actividad(c.leadId, owner(c.leadId, c.analista))
-    && Date.parse(fechaResultado(c)!) <= limiteResultado && mesResultado(personas.get(c.leadId)!, fechaResultado(c)!))
-  const entrevistas = resueltas.filter(c => c.estado === 'realizada')
-  const cierres = datos.conversiones.filter(c => personas.has(c.lead_id)
-    && ambito(owner(c.lead_id, c.analista_id)) && actividad(c.lead_id, owner(c.lead_id, c.analista_id))
-    && ventaComercialDelMes(c, filtros.mes, corte))
   // Todo el capital del mes cuenta para el ticket: contratos nuevos, upgrades,
   // renovaciones y cooperativas, atribuidos al analista del núcleo (Miguel,
   // 15/09/2026: «nada debe quedar fuera»). No exige que el cliente venga de un
@@ -100,32 +76,14 @@ export function calcularAvanceCitas(gestion: GestionCitas, todas: CitaEjemplo[],
   // Personas con capital en el mes, antes del recorte por analista o equipo: un
   // cliente convertido por Ana cuyo contrato firmó Luis no «carece» de capital.
   const conCapital = new Set(capitalPeriodo.map(personaCapital))
-  const reglasListas = datos.control.version > 0 && datos.control.mes_inicio !== null && config.mes_inicio !== null
-    && config.mes_resultado !== null && config.analista_resultado !== null && config.base_depositos !== null
-    && config.base_avance !== null && config.conteo_entrevistas !== null && config.actividad_manuales !== null
   const resultados = (id?: string) => {
     const base = asignados.filter(p => !id || p.id === id)
     const citas = registradas.filter(c => !id || c.analista === id)
-    const resultado = resueltas.filter(c => !id || owner(c.leadId, c.analista) === id)
-    const visitas = entrevistas.filter(c => !id || owner(c.leadId, c.analista) === id)
-    const gente = new Set(visitas.map(c => personaEntrevistada(c.leadId)))
-    const clientesMes = cierres.filter(c => !id || owner(c.lead_id, c.analista_id) === id)
-    // Cada fila compara entrevistas propias. El total del ámbito reconoce
-    // también la colaboración entre analistas incluidos en la consulta.
-    const vinculados = clientesMes.filter(c => {
-      const venta = { dueno: owner(c.lead_id, c.analista_id), fecha_comercial: c.fecha_comercial }
-      return visitas.some(v => personaEntrevistada(v.leadId) === personaEntrevistada(c.lead_id) && ventaCierraEntrevista(v.asistioEn, venta, id || null))
-    })
+    const leads = new Set(base.map(p => p.leadId)).size
+    const { resultado, visitas, gente, ventas: clientesMes, vinculados, clientes, baseEntrevistas, baseConversion, tasaEntrevistas, conversion } = delMes.medir(id, leads)
     const perfilesVinculados = new Set(vinculados.map(c => personaEntrevistada(c.lead_id)))
-    const clientes = perfilesVinculados.size
     const clientesPeriodo = new Set(clientesMes.map(c => personaEntrevistada(c.lead_id))).size
     const fuera = new Set(clientesMes.filter(c => !perfilesVinculados.has(personaEntrevistada(c.lead_id))).map(c => personaEntrevistada(c.lead_id))).size
-    const leads = new Set(base.map(p => p.leadId)).size
-    const nEntrevistas = config.conteo_entrevistas === 'personas_unicas' ? gente.size : visitas.length
-    const baseEntrevistas = config.base_avance === 'meta_proyectada' ? leads * config.citas_por_lead : resultado.length
-    const baseConversion = config.base_depositos === 'entrevistas' ? visitas.length : gente.size
-    const tasaEntrevistas = reglasListas && baseEntrevistas ? nEntrevistas / baseEntrevistas : null
-    const conversion = reglasListas && baseConversion ? clientes / baseConversion : null
     // El ticket es mensual aunque el seguimiento esté configurado por cohorte.
     const cierresTicket = datos.conversiones.filter(c => personas.has(c.lead_id) && ambito(c.analista_id)
       && (!id || c.analista_id === id) && actividad(c.lead_id, c.analista_id)
diff --git a/CRM-Avance-Corp/app/src/components/citas/fecha-comercial.ts b/CRM-Avance-Corp/app/src/components/citas/fecha-comercial.ts
index 043756c5..ccae1a16 100644
--- a/CRM-Avance-Corp/app/src/components/citas/fecha-comercial.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/fecha-comercial.ts
@@ -1,7 +1,7 @@
+// Un solo formateador: crearlo en cada llamada costaba más que el resto del cálculo de Resultados y la Proyección.
+const DIA_DE_LIMA = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' })
 /** Fechas comerciales sin hora: comparar por día de Lima, nunca por UTC. */
-export const fechaLocalCitas = (fecha: string) => new Intl.DateTimeFormat('en-CA', {
-  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
-}).format(new Date(fecha))
+export const fechaLocalCitas = (fecha: string) => DIA_DE_LIMA.format(new Date(fecha))
 
 /** Una fecha comercial no acredita el orden intradía. Sí excluye días posteriores. */
 export function entrevistaCompatibleConVenta(asistencia: string | undefined, fechaComercial: string | null): boolean {
@@ -9,10 +9,22 @@ export function entrevistaCompatibleConVenta(asistencia: string | undefined, fec
     && fechaLocalCitas(asistencia) <= fechaComercial)
 }
 
+/** Días de Lima de un periodo (ambos incluidos) e instante de la consulta. */
+export interface PeriodoComercial { desde: string; hasta: string; corte: string }
+
+/** Venta del periodo: su fecha comercial cae en él, no después del día del corte, y ya estaba registrada al corte. */
+export function ventaComercialDelPeriodo(
+  venta: { fecha_comercial?: string | null | undefined; convertido_en: string }, { desde, hasta, corte }: PeriodoComercial,
+): boolean {
+  const dia = venta.fecha_comercial
+  return dia != null && dia >= desde && dia <= hasta
+    && dia <= fechaLocalCitas(corte)
+    && Date.parse(venta.convertido_en) <= Date.parse(corte)
+}
+
+/** El mes como periodo: una fecha comercial válida del mes está entre su día 01 y el 31. */
 export function ventaComercialDelMes(
   venta: { fecha_comercial: string | null; convertido_en: string }, mes: string, corte: string,
 ): boolean {
-  return venta.fecha_comercial !== null && venta.fecha_comercial.startsWith(`${mes}-`)
-    && venta.fecha_comercial <= fechaLocalCitas(corte)
-    && Date.parse(venta.convertido_en) <= Date.parse(corte)
+  return ventaComercialDelPeriodo(venta, { desde: `${mes}-01`, hasta: `${mes}-31`, corte })
 }
diff --git a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
index 40f910c0..da17663f 100644
--- a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
@@ -52,7 +52,7 @@ function Guia({ abierta, onCerrar }: { abierta: boolean; onCerrar: () => void })
       <section><h3 className="font-semibold">2. Empieza por lo que necesita atención</h3><p className="mt-1 text-muted-foreground-strong">En «Bandeja comercial», pulsa «Sin resultado» para encontrar citas vencidas cuyo resultado no se registró. «Programadas» muestra las que todavía están por realizar en el período.</p></section>
       <section><h3 className="font-semibold">3. Combina los filtros</h3><p className="mt-1 text-muted-foreground-strong">Abre «Más filtros» para elegir varios estados, modalidad, origen, resultado y seguimiento. Para filtrar un importe, selecciona primero soles o dólares.</p></section>
       <section><h3 className="font-semibold">4. Cambia de vista según la tarea</h3><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Bandeja comercial:</strong> revisa responsable, estado y siguiente paso. «Pendientes primero» deja las vencidas arriba.</li><li><strong>Agenda:</strong> revisa citas por día y hora. Siempre usa orden cronológico.</li><li><strong>Resultados:</strong> empieza por el recorrido de quienes no asistieron. Pulsa una etapa para ver sus personas y abre un nombre para consultar el historial, las fechas y el depósito. Debajo, compara citas por lead y cumplimiento de cada analista: el 100% indica que alcanzó la meta interna configurada. La flecha junto al analista abre sus leads. «Columnas» muestra información adicional de actividad y supervisor.</li><li><strong>Proyección:</strong> hoja por analista con su propio periodo (Desde–Hasta). Se explica en el paso 5.</li></ul><p className="mt-2 text-muted-foreground-strong">Bandeja, Agenda y Resultados conservan tus filtros y consultan el mismo conjunto de citas. Los filtros seleccionan las citas de origen; el seguimiento puede encontrar depósitos posteriores fuera del mes o semana, hasta el corte indicado. Cada etapa cuenta leads únicos y parte de la anterior. El porcentaje final usa como base quienes faltaron al inicio; un depósito anterior a la asistencia no entra en este flujo.</p></section>
-      <section><h3 className="font-semibold">5. Lee la Proyección</h3><p className="mt-1 text-muted-foreground-strong">Tiene su propio periodo: elige Desde y Hasta o un atajo, y el supervisor en su barra; los filtros de arriba no se aplican aquí. Cuenta cada cita el día en que se creó, no el de su fecha prevista, e incluye las reuniones con clientes que no tienen lead. «Semanas» y «Días» reparten esas citas en columnas; «Días» admite hasta 31 días.</p><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Monto S/:</strong> suma del monto estimado de las citas con lead; los dólares se pasan a soles con el tipo de cambio del periodo.</li><li><strong>Ticket cita S/:</strong> Monto ÷ citas con lead. No es el «Ticket del mes» de Resultados, que divide el capital cerrado entre los clientes.</li><li><strong>% Entrev.:</strong> entrevistas ÷ citas con resultado (realizadas y no asistió). Una reunión con cliente a la que asistió cuenta como entrevista.</li><li><strong>% Conv.:</strong> personas entrevistadas con lead que después cerraron una venta del mismo analista, con la misma regla que Resultados.</li><li><strong>Proyectado citas S/:</strong> las citas que se esperan al cierre del periodo, al ritmo actual, × % de entrevistas × % de conversión × ticket cita. Se calcula solo con las citas con lead. No es el «Cierre proyectado» de Resultados.</li><li><strong>Referidos, Clientes y Leads:</strong> de dónde viene cada cita; suman el total de citas. «Clientes» son personas que ya eran clientes. Las reuniones con clientes que no tienen lead no suman al monto, al ticket, a la conversión ni al proyectado.</li></ul><p className="mt-2 text-muted-foreground-strong">Cada número abre su lista de citas. El embudo de cada columna ordena y filtra. En el celular la hoja y sus listas se muestran en tarjetas.</p></section>
+      <section><h3 className="font-semibold">5. Lee la Proyección</h3><p className="mt-1 text-muted-foreground-strong">Tiene su propio periodo: elige Desde y Hasta o un atajo, y el supervisor en su barra; los filtros de arriba no se aplican aquí. Cuenta cada cita el día en que se creó, no el de su fecha prevista, e incluye las reuniones con clientes que no tienen lead. «Semanas» y «Días» reparten esas citas en columnas; «Días» admite hasta 31 días. «% Entrev.» y «% Conv.» son los de Resultados: con el rango de un mes dan las mismas cifras.</p><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Monto S/:</strong> suma del monto estimado de las citas con lead; los dólares se pasan a soles con el tipo de cambio del periodo.</li><li><strong>Ticket cita S/:</strong> Monto ÷ citas con lead. No es el «Ticket del mes» de Resultados, que divide el capital cerrado entre los clientes.</li><li><strong>% Entrev.:</strong> el de Resultados para el periodo: entrevistas ÷ citas con resultado (realizadas y no asistió), con las reglas de gestión; cuenta resultados de citas creadas antes del periodo.</li><li><strong>% Conv.:</strong> el de Resultados: personas entrevistadas que cerraron una venta del mismo analista con fecha comercial en el periodo.</li><li><strong>Proyectado citas S/:</strong> las citas que se esperan al cierre del periodo, al ritmo actual, × la proporción de citas con resultado que fueron entrevista × % de conversión × ticket cita. Se calcula solo con las citas con lead. No es el «Cierre proyectado» de Resultados.</li><li><strong>Referidos, Clientes y Leads:</strong> de dónde viene cada cita; suman el total de citas. «Clientes» son personas que ya eran clientes. Las reuniones con clientes que no tienen lead no suman al monto, al ticket, a las entrevistas, a la conversión ni al proyectado.</li></ul><p className="mt-2 text-muted-foreground-strong">Cada número abre su lista de citas. El embudo de cada columna ordena y filtra. En el celular la hoja y sus listas se muestran en tarjetas.</p></section>
       <section><h3 className="font-semibold">6. Abre la ficha</h3><p className="mt-1 text-muted-foreground-strong">Pulsa el nombre del prospecto o «Detalle». La ficha lateral muestra fecha, responsable, monto estimado, resultado, notas y siguiente paso. «Ubicar en agenda» abre esa cita. «Citas de…» abre todas las citas de ese analista en el mes de la ficha. Estas dos acciones restablecen los demás filtros para que el destino sea visible.</p></section>
       <section><h3 className="font-semibold">7. Limpia o exporta la consulta</h3><p className="mt-1 text-muted-foreground-strong">La × de cada etiqueta quita ese filtro. «Restablecer consulta» vuelve al mes completo. «Exportar citas» descarga todas las coincidencias, incluidas las de otras páginas. El CSV contiene el detalle de las citas; el promedio por lead y el seguimiento se consultan en Resultados. En Proyección, «Exportar» descarga la hoja por analista o las citas del periodo.</p></section>
       <p className="rounded-lg bg-muted p-3 text-xs text-muted-foreground-strong">Responsable: el analista registrado en la cita; no acredita quién la creó. Las fechas de asistencia corresponden al registro de su resultado. Seguimiento al {corteLima(corte)}.</p>
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
index eb2efb85..918315ad 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
@@ -109,8 +109,10 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
   const { tc, recargar } = useTipoCambio(citas.some(c => c.moneda === 'USD' && (c.monto ?? 0) > 0), hasta < hoy ? hasta : hoy)
   const hoja = useMemo(() => calcularProyeccion({
     citas, reunionesClientes, filtros: { equipo }, rango: { desde, hasta }, tiempo, corte, tipoCambio: tc?.promedio,
-    conversiones: avance?.conversiones ?? null, poblacion: avance?.poblacion, analistaResultado: avance?.control.configuracion.analista_resultado,
-  }, columnas, orden), [citas, reunionesClientes, equipo, desde, hasta, tiempo, corte, tc?.promedio, avance, columnas, orden])
+    // Lo mismo que usa Resultados para sus tasas: % Entrev. y % Conv. salen de su código.
+    conversiones: avance?.conversiones ?? null, poblacion: avance?.poblacion, control: avance?.control,
+    asignaciones: gestion?.asignaciones, capital: avance?.capital,
+  }, columnas, orden), [citas, reunionesClientes, equipo, desde, hasta, tiempo, corte, tc?.promedio, avance, gestion?.asignaciones, columnas, orden])
   const vistaTiempo = tiempoEfectivo(tiempo, rango)
   const objetivos: ObjetivosProyeccion = {
     entrevistas: avance?.control.configuracion.entrevistas_porcentaje ?? gestion?.entrevistasPorcentaje ?? METAS_CITAS_INICIALES.entrevistas_porcentaje,
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
index 757e88a0..4df47adf 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
@@ -5,22 +5,26 @@
 // Desde–Hasta de la pestaña y, si se eligió, del supervisor de su barra. El
 // analista se acota con el embudo de su columna. Las citas llegan del servidor por
 // mes de su fecha prevista; la pantalla carga cada mes del rango y los fusiona
-// antes de llegar aquí.
+// antes de llegar aquí. La cohorte decide Citas, Monto, Ticket cita, las columnas
+// de tiempo y el ritmo del Proyectado.
 //
-// «No puede haber data distinta» (Miguel, 19/10/2026): % Entrev. y % Conv. usan
-// las MISMAS reglas que Resultados (`calcularAvanceCitas`): entrevistas ÷ citas
-// resueltas y el vínculo entrevista → venta por fecha comercial y por DUEÑO de la
-// venta (`atribucion.ts`, compartido con Resultados).
+// «No puede haber data distinta» (Miguel, 19 y 20/10/2026): % Entrev. y % Conv.
+// son los de Resultados, calculados por el MISMO código (`resultados-periodo.ts`)
+// con el rango como periodo: cuentan las citas cuyo RESULTADO cae en el rango
+// (aunque se crearan antes) y las ventas con fecha comercial en él. Con el rango
+// de un mes, cada analista y el total dan lo mismo que Resultados de ese mes.
 //
 // Reuniones con CLIENTES sin lead (Fase 0b, decisión de Miguel 19/10/2026): son
-// citas de origen Cliente. Cuentan en Citas, Clientes, las columnas de tiempo y
-// % Entrev.; no tienen monto ni se «convierten», así que Monto, Ticket cita,
-// % Conv. y Proyectado siguen siendo los de las citas con lead, sin cambio.
-import type { ControlCitas } from '@/lib/control-citas'
+// citas de origen Cliente. Cuentan en Citas, Clientes y las columnas de tiempo;
+// no tienen monto, no son de Resultados ni se «convierten»: Monto, Ticket cita,
+// % Entrev., % Conv. y Proyectado no las usan (Miguel, 20/10/2026).
+import type { GestionMensualCitas } from '@/lib/gestion-citas'
 import { tcAplicable } from '@/lib/capital-unificado'
 import { usdAPen } from '@/lib/tipo-cambio'
-import { enAmbito, reglaDueno, ventaCierraEntrevista, type AmbitoAnalistas } from './atribucion'
+import { enAmbito, type AmbitoAnalistas } from './atribucion'
 import { fechaLocalCitas } from './fecha-comercial'
+import type { LeadBaseCitas } from './metas'
+import { asignadosDeLaMeta, resultadosDelPeriodo, rosterDeAnalistas, type AnalistaRoster } from './resultados-periodo'
 import { ESTADOS, normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
 import { diasEntre, errorRango, tramosDelRango, type RangoProyeccion, type TiempoProyeccion, type TramoProyeccion } from './proyeccion-rango'
 
@@ -41,12 +45,12 @@ export interface ConversionProyeccion {
   analista_id: string | null
   /** Su supervisor: decide si la venta entra en el ámbito del supervisor elegido. */
   supervisor_id?: string | null | undefined
+  analista_nombre?: string | undefined; supervisor_nombre?: string | undefined
 }
-export interface PersonaProyeccion {
-  lead_id: string; identidad_persona?: string | undefined
-  /** Analista (y su supervisor) de origen del lead: dueño de sus ventas con la regla «asignacion». */
-  analista_origen_id?: string | null | undefined; supervisor_origen_id?: string | null | undefined
-}
+type Persona = GestionMensualCitas['poblacion'][number]
+/** Persona de la población del avance: solo las que admite Resultados tienen resultados y ventas. */
+export type PersonaProyeccion = Pick<Persona, 'lead_id' | 'analista_origen_id' | 'registro_manual' | 'creado_por' | 'primera_asignacion_en'>
+  & Partial<Pick<Persona, 'identidad_persona' | 'supervisor_origen_id' | 'analista_origen_nombre' | 'supervisor_origen_nombre'>>
 /**
  * Reunión con un cliente que no tiene lead (lector `crm.citas_clientes_proyeccion_fn`): sin lead, monto ni moneda.
  * Analista y supervisor son los del lector; el estado, el de Citas (`ESTADOS`).
@@ -74,14 +78,18 @@ export interface FuenteProyeccion {
   tipoCambio?: number | null | undefined
   /** null: el servidor no envió conversiones; la conversión queda sin base, nunca en 0 %. */
   conversiones: readonly ConversionProyeccion[] | null
+  /** Lo que usa Resultados para sus tasas, del lector del avance; sin control ni población, % Entrev. y % Conv. quedan sin base. */
   poblacion?: readonly PersonaProyeccion[] | undefined
-  /** Regla de Resultados para el dueño de una venta (`analista_resultado` de la gestión); sin ella, la del evento. */
-  analistaResultado?: ControlCitas['analista_resultado'] | undefined
+  control?: GestionMensualCitas['control'] | undefined
+  /** Base asignada: la meta de la regla «meta_proyectada». */
+  asignaciones?: readonly LeadBaseCitas[] | undefined
+  /** Capital del avance: solo aporta analistas y supervisores, como en Resultados. */
+  capital?: GestionMensualCitas['capital'] | undefined
 }
 
 export interface CitaProyectada {
   cita: CitaHoja
-  /** Día de Lima en que se creó la cita (la cohorte y los tramos se cortan por él). */
+  /** Día de Lima en que se creó la cita (la cohorte y los tramos se cortan por él); '' si no lo trae (solo de un resultado). */
   creada: string
   /** Identidad de la persona (misma regla que el avance mensual). */
   persona: string
@@ -95,23 +103,25 @@ export const conLead = (c: CitaProyectada): boolean => c.cita.leadId !== null
 export interface PeriodoProyeccion { desde: string; hasta: string; hoy: string; dias: number; transcurridos: number; cerrado: boolean }
 
 export interface MetricasProyeccion {
-  citas: CitaProyectada[]; conMonto: CitaProyectada[]; entrevistas: CitaProyectada[]
-  /** Las citas con lead: la base de Monto, Ticket cita, % Conv. y Proyectado. */
+  citas: CitaProyectada[]; conMonto: CitaProyectada[]
+  /** Las citas con lead de la cohorte: la base de Monto, Ticket cita y el ritmo del Proyectado. */
   citasConLead: CitaProyectada[]
-  /** Base de % Entrev., como en Resultados: realizadas + no asistió. */
+  /** Las de Resultados en el rango: citas con lead cuyo resultado (realizada o no asistió) cae en él, sean de cuando sean. */
   resueltas: CitaProyectada[]
+  entrevistas: CitaProyectada[]
   /**
-   * Entrevistas vinculadas a una venta con la regla de Resultados: fecha comercial no anterior al día de la
-   * entrevista y venta del analista de la fila (en el total, de un analista del ámbito).
+   * Entrevistas del rango vinculadas a una venta del rango con la regla de Resultados: fecha comercial no anterior al
+   * día de la entrevista y venta del analista de la fila (en el total, de un analista del ámbito).
    */
   convertidas: CitaProyectada[]
   referidos: CitaProyectada[]; clientes: CitaProyectada[]; leads: CitaProyectada[]
   montoPen: number; montoUsd: number; pendienteTc: boolean
   /** «Ticket cita»: monto en citas ÷ citas con lead. No es el «Ticket del mes» de Resultados (capital real ÷ clientes). */
   monto: number | null; ticket: number | null
-  /** % Entrev. de la hoja (todas las citas) y el de las citas con lead, que es el que proyecta. */
-  pctEntrevistas: number | null; pctEntrevistasConLead: number | null; pctConversion: number | null
-  /** Personas de las entrevistas CON LEAD: la base de % Conv. */
+  /** Las tasas de Resultados (`tasaEntrevistas` y `conversion`) en porcentaje, con sus bases según las reglas de gestión. */
+  pctEntrevistas: number | null; pctConversion: number | null
+  baseEntrevistas: number; baseConversion: number
+  /** Personas distintas entrevistadas en el rango y las que cerraron cliente. */
   personasEntrevistadas: number; personasClientes: number
   /** Citas con lead esperadas al cierre del rango. */
   citasEsperadas: number | null; proyectado: number | null
@@ -145,6 +155,8 @@ export interface HojaProyeccion {
   filas: FilaProyeccion[]
   /** El proyectado del total SUMA el de cada analista con base; nunca promedia tasas. */
   total: MetricasProyeccion
+  /** Analistas con resultados (o base de meta) en el rango, sin el embudo de Analista: también son opciones de ese embudo. */
+  conResultados: AnalistaRoster[]
 }
 
 /** Días del rango, días ya transcurridos hasta hoy y si el rango ya terminó. */
@@ -167,18 +179,9 @@ interface Contexto {
   conocidas: boolean
   /** Conversiones de la persona: el respaldo de «cliente» mira `convertido_en`. */
   conversionesDe: (persona: string) => readonly ConversionProyeccion[]
-  /** Ventas de la persona hasta el corte, sin recortarlas al mes: la cohorte se sigue hasta hoy. */
-  ventasDe: (persona: string) => readonly VentaProyeccion[]
-}
-interface VentaProyeccion {
-  lead_id: string; fecha_comercial: string | null
-  /** Analista al que Resultados atribuye la venta (`reglaDueno`). */
-  dueno: string | null
-  /** Su dueño está en el ámbito de la hoja: solo así cuenta en el total. */
-  enAmbito: boolean
 }
 
-function prepararContexto(fuente: FuenteProyeccion, columnas: FiltrosColumnas) {
+function prepararContexto(fuente: FuenteProyeccion) {
   // Misma identidad que el avance mensual: la del servidor; si falta, el perfil
   // cliente del lead convertido; si no, el propio lead.
   const conversiones = fuente.conversiones ?? []
@@ -187,46 +190,19 @@ function prepararContexto(fuente: FuenteProyeccion, columnas: FiltrosColumnas) {
     p.identidad_persona ?? (perfiles.has(p.lead_id) ? `perfil:${perfiles.get(p.lead_id)}` : `lead:${p.lead_id}`)]))
   const persona = (lead: string) => identidades.get(lead) ?? `lead:${lead}`
   const periodo = periodoProyeccion(fuente.rango, fuente.corte)
-  const corte = Date.parse(fuente.corte)
-  const agrupar = <T extends { lead_id: string }>(lista: readonly T[]) => {
-    const porPersona = new Map<string, T[]>()
-    for (const c of lista) {
-      const clave = persona(c.lead_id)
-      const suyas = porPersona.get(clave)
-      if (suyas) suyas.push(c)
-      else porPersona.set(clave, [c])
-    }
-    return porPersona
-  }
-  const porPersona = agrupar(conversiones)
-  // Dueño de la venta, como en Resultados: con «asignacion», el analista de origen del lead; si no, el de la venta.
-  const origenes = new Map((fuente.poblacion ?? []).map(p => [p.lead_id, p.analista_origen_id]))
-  const dueno = reglaDueno(fuente.analistaResultado, lead => origenes.get(lead))
-  // Supervisor de cada analista con la precedencia del roster de Resultados para
-  // las fuentes que llegan aquí: origen de la población, citas y, al final, ventas.
-  const supervisores = new Map<string, string>([
-    ...(fuente.poblacion ?? []).filter(p => p.analista_origen_id).map(p => [p.analista_origen_id!, p.supervisor_origen_id ?? 'sin_supervisor'] as const),
-    ...fuente.citas.map(c => [c.analista, c.supervisorId] as const),
-    ...conversiones.filter(c => c.analista_id).map(c => [c.analista_id!, c.supervisor_id ?? 'sin_supervisor'] as const),
-  ])
-  // ÁMBITO de la hoja (el de la consulta de Resultados): los analistas que deja el
-  // embudo de Analista (sin embudo, todos) del supervisor elegido en la barra (sin
-  // él, todos). Una venta cuenta en el TOTAL solo si su dueño está dentro; los
-  // embudos de Mín/Máx ocultan filas, no cambian el ámbito.
-  const ambito: AmbitoAnalistas = {
-    analistas: columnas.analistas ? new Set(columnas.analistas) : null, equipo: fuente.filtros.equipo, supervisorDe: id => supervisores.get(id),
+  const porPersona = new Map<string, ConversionProyeccion[]>()
+  for (const c of conversiones) {
+    const suyas = porPersona.get(persona(c.lead_id))
+    if (suyas) suyas.push(c)
+    else porPersona.set(persona(c.lead_id), [c])
   }
-  // Una venta registrada después del corte aún no existe para la consulta.
-  const ventas = agrupar(conversiones.filter(c => periodo !== null && c.fecha_comercial != null
-    && c.fecha_comercial <= periodo.hoy && Date.parse(c.convertido_en) <= corte).map((c): VentaProyeccion => {
-    const suyo = dueno(c.lead_id, c.analista_id)
-    return { lead_id: c.lead_id, fecha_comercial: c.fecha_comercial ?? null, dueno: suyo, enAmbito: enAmbito(suyo, ambito) }
-  }))
   const contexto: Contexto = {
     periodo, tramos: periodo ? tramosDelRango(fuente.rango, fuente.tiempo ?? 'mes', periodo.hoy) : [], tc: tcAplicable(fuente.tipoCambio),
-    conocidas: fuente.conversiones !== null, conversionesDe: clave => porPersona.get(clave) ?? [], ventasDe: clave => ventas.get(clave) ?? [],
+    conocidas: fuente.conversiones !== null, conversionesDe: clave => porPersona.get(clave) ?? [],
   }
-  return { contexto, persona }
+  // Analistas y supervisores con las fuentes y la precedencia de Resultados: el supervisor decide el ámbito.
+  const roster = rosterDeAnalistas({ capital: fuente.capital, poblacion: fuente.poblacion, asignaciones: fuente.asignaciones, citas: fuente.citas, ventas: conversiones })
+  return { contexto, persona, roster }
 }
 
 function proyectar(cita: CitaEjemplo, creada: string, persona: string, contexto: Contexto): CitaProyectada {
@@ -241,6 +217,48 @@ function proyectar(cita: CitaEjemplo, creada: string, persona: string, contexto:
   return { cita, creada, persona, origen, enSoles }
 }
 
+/** Día de Lima en que se creó la cita; '' si no trae una fecha válida. */
+const diaDeCreacion = (c: CitaHoja) => c.creadoEn && Number.isFinite(Date.parse(c.creadoEn)) ? fechaLocalCitas(c.creadoEn) : ''
+
+/**
+ * % Entrev. y % Conv. de la hoja: `resultadosDelPeriodo` (el código de Resultados) con el rango como periodo,
+ * sobre las citas con lead que dejan los embudos de moneda y personas. El de Analista entra en el ámbito
+ * (por dueño del resultado, como el filtro de analista de Resultados); sin `analistas`, no se aplica.
+ */
+function resultadosDelRango(fuente: FuenteProyeccion, contexto: Contexto, persona: (lead: string) => string, roster: ReadonlyMap<string, AnalistaRoster>,
+  delLector: readonly CitaProyectada[], columnas: FiltrosColumnas, analistas: readonly string[] | undefined) {
+  const { periodo } = contexto
+  if (!periodo || !fuente.control) return null
+  const control = fuente.control
+  const proyectadas = new Map(delLector.map(c => [c.cita.id, c]))
+  const citas = recortar(delLector, columnas, 'analistas').map(c => c.cita as CitaEjemplo)
+  const personas = new Map((fuente.poblacion ?? []).map(p => [p.lead_id, p]))
+  const elegidos = analistas ? new Set(analistas) : null
+  const { equipo } = fuente.filtros
+  const ambito: AmbitoAnalistas = { analistas: elegidos, equipo, supervisorDe: id => roster.get(id)?.supervisorId }
+  const resultados = resultadosDelPeriodo({
+    citas, ventas: fuente.conversiones ?? [], personas, identidad: persona, control,
+    periodo: { desde: periodo.desde, hasta: periodo.hasta, corte: fuente.corte }, ambito: id => enAmbito(id, ambito),
+  })
+  // La base de la meta («meta_proyectada»): asignados en el rango, con el supervisor y los analistas de la consulta, como en Resultados.
+  const asignados = asignadosDeLaMeta((fuente.asignaciones ?? []).filter(l => (!equipo || l.supervisorId === equipo)
+    && (!elegidos || elegidos.has(l.id))), personas, control, periodo)
+  const leads = (analista?: string, duenos?: ReadonlySet<string>) =>
+    new Set(asignados.filter(l => analista ? l.id === analista : !duenos || duenos.has(l.id)).map(l => l.leadId)).size
+  return {
+    dueno: resultados.dueno,
+    resueltas: resultados.resueltas,
+    /** Con la regla «meta_proyectada», los analistas con base en el rango: su % Entrev. existe (0 % sin entrevistas), como en Resultados. */
+    conMeta: control.configuracion.base_avance === 'meta_proyectada' ? [...new Set(asignados.map(l => l.id))] : [],
+    medir: (analista?: string, duenos?: ReadonlySet<string>): ResultadosDeFila => ({
+      medida: resultados.medir(analista, leads(analista, duenos), duenos), de: c => proyectadas.get(c.id)!,
+    }),
+  }
+}
+type MedidaResultados = ReturnType<ReturnType<typeof resultadosDelPeriodo<CitaEjemplo, ConversionProyeccion>>['medir']>
+/** Lo que Resultados mide para una fila (o el total) y cómo volver de sus citas a las de la hoja. */
+interface ResultadosDeFila { medida: MedidaResultados; de: (cita: CitaEjemplo) => CitaProyectada }
+
 function cohorte(fuente: FuenteProyeccion, persona: (lead: string) => string, contexto: Contexto): CitaProyectada[] {
   const periodo = contexto.periodo
   if (!periodo) return []
@@ -277,13 +295,8 @@ export function repartirEnTramos(lista: readonly CitaProyectada[], tramos: reado
 const suma = (lista: readonly CitaProyectada[], moneda: Moneda) =>
   lista.reduce((n, c) => n + (c.cita.moneda === moneda && c.cita.monto != null ? c.cita.monto : 0), 0)
 
-const realizada = (c: CitaProyectada) => c.cita.estado === 'realizada'
-// Como Resultados: las programadas, canceladas o aún sin resultado no son base.
-const resuelta = (c: CitaProyectada) => realizada(c) || c.cita.estado === 'no_show'
-const tasa = (parte: number, base: number) => base ? parte / base * 100 : null
-
-/** `fila`: el analista de la fila; null, el total de la hoja. */
-function medir(lista: CitaProyectada[], contexto: Contexto, fila: string | null): MetricasProyeccion {
+/** `resultados`: lo que Resultados mide para la fila o el total; null sin reglas de gestión ni periodo válido. */
+function medir(lista: CitaProyectada[], contexto: Contexto, resultados: ResultadosDeFila | null): MetricasProyeccion {
   // Métricas de prospectos: solo las citas con lead (las reuniones con clientes sin lead no tienen monto ni se convierten).
   const citasConLead = lista.filter(conLead)
   const n = citasConLead.length
@@ -293,35 +306,29 @@ function medir(lista: CitaProyectada[], contexto: Contexto, fila: string | null)
   const pendienteTc = montoUsd > 0 && contexto.tc === null
   const monto = pendienteTc ? null : montoPen + (contexto.tc === null ? 0 : usdAPen(montoUsd, contexto.tc))
   const ticket = monto !== null && n ? monto / n : null
-  // % Entrev. de la hoja: también las reuniones con clientes (completada = entrevista, no asistió = resuelta).
-  const entrevistas = lista.filter(realizada)
-  const resueltas = lista.filter(resuelta)
-  const entrevistasConLead = citasConLead.filter(realizada)
-  // Vínculo entrevista → cliente: la MISMA regla de Resultados, importada, no copiada.
-  // En la fila, solo una venta de ese analista; en el total, la de cualquier dueño
-  // del ámbito (dos analistas que entrevistan a la misma persona colaboran).
-  const convertidas = entrevistasConLead.filter(c => contexto.ventasDe(c.persona)
-    .some(v => (fila !== null || v.enAmbito) && ventaCierraEntrevista(c.cita.asistioEn, v, fila)))
-  const personasEntrevistadas = new Set(entrevistasConLead.map(c => c.persona)).size
-  const personasClientes = new Set(convertidas.map(c => c.persona)).size
-  const pctEntrevistas = tasa(entrevistas.length, resueltas.length)
-  const pctEntrevistasConLead = tasa(entrevistasConLead.length, citasConLead.filter(resuelta).length)
-  const pctConversion = contexto.conocidas ? tasa(personasClientes, personasEntrevistadas) : null
+  // % Entrev. y % Conv.: los de Resultados en el rango, medidos por su código, no recalculados aquí.
+  const r = resultados?.medida
+  const deLaHoja = (citas: readonly CitaEjemplo[] | undefined) => resultados ? (citas ?? []).map(resultados.de) : []
+  const pctEntrevistas = r?.tasaEntrevistas == null ? null : r.tasaEntrevistas * 100
+  const pctConversion = contexto.conocidas && r?.conversion != null ? r.conversion * 100 : null
   const periodo = contexto.periodo
   const hastaHoy = periodo ? citasConLead.filter(c => c.creada <= periodo.hoy).length : n
   // Citas esperadas al cierre: el ritmo de los días transcurridos llevado al periodo entero.
   const citasEsperadas = !n || !periodo ? null : periodo.cerrado || !periodo.transcurridos ? n
     : Math.max(n, hastaHoy / periodo.transcurridos * periodo.dias)
-  // Como Resultados: citas esperadas × tasa de entrevistas × conversión × ticket, todo de las citas con lead.
-  // Sin citas resueltas, o sin personas entrevistadas para la conversión, queda «sin base», nunca 0.
-  const proyectado = citasEsperadas !== null && pctEntrevistasConLead !== null && pctConversion !== null && ticket !== null
-    ? citasEsperadas * (pctEntrevistasConLead / 100) * (pctConversion / 100) * ticket : null
+  // Como el cierre proyectado de Resultados: la tasa OBSERVADA de entrevistas (realizadas ÷ citas con resultado,
+  // sea cual sea la regla de conteo del % Entrev.) × conversión × ticket cita. Sin base, «sin base», nunca 0.
+  const tasaObservada = r?.resultado.length ? r.visitas.length / r.resultado.length : null
+  const proyectado = citasEsperadas !== null && tasaObservada !== null && pctConversion !== null && ticket !== null
+    ? citasEsperadas * tasaObservada * (pctConversion / 100) * ticket : null
   return {
-    citas: lista, citasConLead, conMonto, entrevistas, resueltas, convertidas,
+    citas: lista, citasConLead, conMonto, entrevistas: deLaHoja(r?.visitas), resueltas: deLaHoja(r?.resultado), convertidas: deLaHoja(r?.visitasVinculadas),
     referidos: lista.filter(c => c.origen === 'referido'), clientes: lista.filter(c => c.origen === 'cliente'),
     leads: lista.filter(c => c.origen === 'lead'),
-    montoPen, montoUsd, pendienteTc, monto, ticket, pctEntrevistas, pctEntrevistasConLead, pctConversion,
-    personasEntrevistadas, personasClientes, citasEsperadas, proyectado, porTramo: repartirEnTramos(lista, contexto.tramos),
+    montoPen, montoUsd, pendienteTc, monto, ticket, pctEntrevistas, pctConversion,
+    baseEntrevistas: r?.baseEntrevistas ?? 0, baseConversion: r?.baseConversion ?? 0,
+    personasEntrevistadas: r?.gente.size ?? 0, personasClientes: r?.clientes ?? 0,
+    citasEsperadas, proyectado, porTramo: repartirEnTramos(lista, contexto.tramos),
   }
 }
 
@@ -370,21 +377,37 @@ function comparar(orden: OrdenProyeccion) {
 }
 
 export function calcularProyeccion(fuente: FuenteProyeccion, columnas: FiltrosColumnas = {}, orden: OrdenProyeccion = ORDEN_INICIAL): HojaProyeccion {
-  const { contexto, persona } = prepararContexto(fuente, columnas)
+  const { contexto, persona, roster } = prepararContexto(fuente)
   const base = cohorte(fuente, persona, contexto)
   const visibles = recortar(base, columnas)
+  // Todas las citas del lector como citas de la hoja: de ellas salen los resultados del rango.
+  const delLector = contexto.periodo && fuente.control ? fuente.citas.map(c => proyectar(c, diaDeCreacion(c), persona(c.leadId), contexto)) : []
+  const delRango = resultadosDelRango(fuente, contexto, persona, roster, delLector, columnas, columnas.analistas)
   const porAnalista = new Map<string, CitaProyectada[]>()
-  for (const c of visibles) porAnalista.set(c.cita.analista, [...(porAnalista.get(c.cita.analista) ?? []), c])
-  const filas: FilaProyeccion[] = [...porAnalista.values()].map(lista => {
-    const { analista: id, analistaNombre: nombre, supervisor, supervisorId } = lista[0]!.cita
-    return { id, nombre, supervisor, supervisorId, ...medir(lista, contexto, id) }
+  for (const c of visibles) {
+    const suyas = porAnalista.get(c.cita.analista)
+    if (suyas) suyas.push(c)
+    else porAnalista.set(c.cita.analista, [c])
+  }
+  // Un analista con resultados en el rango (o con base de meta) tiene fila aunque no haya creado citas en él: Resultados también la tiene.
+  const duenos = (resultados: ReturnType<typeof resultadosDelRango>) => resultados === null ? []
+    : [...new Set([...resultados.resueltas.flatMap(c => resultados.dueno(c.leadId, c.analista) ?? []), ...resultados.conMeta])]
+  for (const id of duenos(delRango)) if (!porAnalista.has(id)) porAnalista.set(id, [])
+  const quien = (id: string): AnalistaRoster => roster.get(id) ?? { id, nombre: 'Sin analista', supervisor: 'Sin supervisor', supervisorId: 'sin_supervisor' }
+  const filas: FilaProyeccion[] = [...porAnalista].map(([id, lista]) => {
+    const { analistaNombre: nombre, supervisor, supervisorId } = lista[0]?.cita ?? { ...quien(id), analistaNombre: quien(id).nombre }
+    return { id, nombre, supervisor, supervisorId, ...medir(lista, contexto, delRango?.medir(id) ?? null) }
   }).filter(f => dentroDeRangos(f, columnas.rangos)).sort(comparar(orden))
+  // Con Mín/Máx, el total mide solo las filas que quedan; sin ellos, todo el ámbito, como el total de Resultados.
+  const hayRangos = Object.values(columnas.rangos ?? {}).some(r => r && (r.min !== undefined || r.max !== undefined))
   const conBase = filas.filter(f => f.proyectado !== null)
-  const total = { ...medir(filas.flatMap(f => f.citas), contexto, null),
+  const total = { ...medir(filas.flatMap(f => f.citas), contexto, delRango?.medir(undefined, hayRangos ? new Set(filas.map(f => f.id)) : undefined) ?? null),
     proyectado: conBase.length ? conBase.reduce((n, f) => n + f.proyectado!, 0) : null }
+  const sinEmbudo = columnas.analistas ? resultadosDelRango(fuente, contexto, persona, roster, delLector, columnas, undefined) : delRango
   return {
     periodo: contexto.periodo, tc: contexto.tc, cohorte: base, tramos: contexto.tramos, filas, total,
     requiereTc: base.some(c => c.cita.moneda === 'USD' && (c.cita.monto ?? 0) > 0),
+    conResultados: duenos(sinEmbudo).map(quien),
   }
 }
 
@@ -399,9 +422,11 @@ function contar(lista: readonly CitaProyectada[], clave: (c: CitaProyectada) =>
   }
   return ordenarOpciones(opciones)
 }
-/** Analistas de la cohorte con su n.º de citas (respetando los demás embudos). */
+/** Analistas de la cohorte con su n.º de citas (respetando los demás embudos) y, con 0, los que solo tienen resultados en el rango. */
 export function opcionesAnalistas(hoja: HojaProyeccion, columnas: FiltrosColumnas): OpcionEmbudo[] {
-  return contar(recortar(hoja.cohorte, columnas, 'analistas'), c => [c.cita.analista, c.cita.analistaNombre])
+  const opciones = new Map(contar(recortar(hoja.cohorte, columnas, 'analistas'), c => [c.cita.analista, c.cita.analistaNombre]).map(o => [o.id, o]))
+  for (const a of hoja.conResultados) if (!opciones.has(a.id)) opciones.set(a.id, { id: a.id, nombre: a.nombre, citas: 0 })
+  return ordenarOpciones(opciones)
 }
 /** Personas de un origen (id = identidad) con su n.º de citas. */
 export function opcionesPersonas(hoja: HojaProyeccion, columnas: FiltrosColumnas, origen: OrigenCita): OpcionEmbudo[] {
```

## Pruebas nuevas (bloque final de proyeccion-invariantes.test.ts)
```ts
// Caso de Alan (Miguel, 20/10/2026): Resultados de octubre le daba 15,0 % de entrevistas
// y la Proyección del 1 al 20 de octubre, 11,3 %: la Proyección medía las citas CREADAS en
// el rango y 27 de sus resultados de octubre eran de citas creadas en septiembre. Las
// pruebas de arriba no lo veían porque sus citas se crean y se resuelven el mismo día.
// Desde entonces las dos tasas salen del mismo código (`resultados-periodo.ts`): con el
// rango de un mes, la misma cifra por analista y en el total, con cualquier regla de
// gestión y con o sin filtros.
describe('Proyección ↔ Resultados con citas creadas en un mes y resueltas en otro', () => {
  const EQUIPO: Record<string, string> = Object.fromEntries(ANALISTAS)
  /**
   * El lote con la asistencia el día previsto (hasta 40 días después de crearse: muchas cruzan de mes) y lo que
   * activa cada regla: leads de otro analista de origen, manuales propios y asignados en meses distintos.
   */
  function datos() {
    const crudo = lote()
    const citas = crudo.citas.map(c => c.asistioEn ? { ...c, asistioEn: `${c.fecha}T16:00:00Z` } : c)
    const asistencia = new Map(citas.filter(c => c.asistioEn).map(c => [c.leadId, c.asistioEn!]))
    // Ventas tras la nueva asistencia: el mismo día, después o antes (no vincula), como las del lote.
    const conversiones = crudo.conversiones.map((v, i) => {
      const dia = fechaLocalCitas(asistencia.get(v.lead_id)!)
      return { ...v, convertido_en: `${sumarDias(dia, 2)}T15:00:00Z`, fecha_comercial: v.fecha_comercial && [sumarDias(dia, 2), dia, sumarDias(dia, -1)][i % 3]! }
    })
    const primera = new Map<string, CitaEjemplo>()
    for (const c of citas) if (!primera.has(c.leadId)) primera.set(c.leadId, c)
    const poblacion = [...primera.values()].map((c, i) => {
      const [origen] = ANALISTAS[(ANALISTAS.findIndex(([a]) => a === c.analista) + (i % 5 === 0 ? 1 : 0)) % ANALISTAS.length]!
      return personaDe(c.leadId, { analista_origen_id: origen, analista_origen_nombre: origen, supervisor_origen_id: EQUIPO[origen]!,
        supervisor_origen_nombre: EQUIPO[origen]!, registro_manual: i % 7 === 0, creado_por: i % 7 === 0 ? c.analista : null, primera_asignacion_en: c.creadoEn! })
    })
    const asignaciones: LeadBaseCitas[] = poblacion.map(p => ({ id: p.analista_origen_id!, nombre: p.analista_origen_nombre, supervisor: p.supervisor_origen_nombre,
      supervisorId: p.supervisor_origen_id!, leadId: p.lead_id, nombreLead: p.lead_id, telefono: '900000000', asignadoEn: p.primera_asignacion_en!,
      manualPropio: p.registro_manual, origen: 'formulario', moneda: 'PEN', monto: 1000 }))
    return { citas, conversiones, poblacion, asignaciones }
  }
  const REGLAS: Partial<ControlCitas>[] = [
    {}, { conteo_entrevistas: 'personas_unicas' }, { base_avance: 'meta_proyectada' }, { base_depositos: 'entrevistas' },
    { analista_resultado: 'asignacion' }, { mes_resultado: 'asignacion' }, { actividad_manuales: 'excluir', excluir_manuales_base: true },
    // Combinaciones: todas las reglas no habituales a la vez, y dueño por asignación con conversión por entrevistas.
    { conteo_entrevistas: 'personas_unicas', base_avance: 'meta_proyectada', base_depositos: 'entrevistas', analista_resultado: 'asignacion',
      mes_resultado: 'asignacion', actividad_manuales: 'excluir', excluir_manuales_base: true },
    { analista_resultado: 'asignacion', base_depositos: 'entrevistas', conteo_entrevistas: 'personas_unicas' },
  ]
  const CONSULTAS = [{ equipo: '', analista: '' }, { equipo: 'sup-1', analista: '' }, { equipo: 'sup-2', analista: '' }, { equipo: '', analista: 'luis' },
    { equipo: 'sup-1', analista: 'luis' }, { equipo: 'sup-2', analista: 'luis' }]
  const tasa = (x: number | null) => x === null ? null : Math.round(x * 1e9) / 1e9

  /** Corre Resultados del mes y la Proyección con ese mes como rango sobre los MISMOS datos. */
  function ambas(mes: string, reglas: Partial<ControlCitas> = {}, { equipo, analista } = CONSULTAS[0]!) {
    const { citas, conversiones, poblacion, asignaciones } = datos()
    const control = { ...CONTROL, configuracion: { ...CONTROL.configuracion, ...reglas } }
    const gestion: GestionCitas = { citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones,
      avance: { control, poblacion, conversiones, capital: [] } }
    const resultados = calcularAvanceCitas(gestion, citas, { ...defaults(mes), equipo, analista }, HOY, TC)
    const rango = { desde: `${mes}-01`, hasta: `${mes}-${resultados.periodo.dias}` }
    const proyeccion = calcularProyeccion({ citas, filtros: { equipo }, rango, corte: HOY, tipoCambio: TC, conversiones, poblacion, control, asignaciones },
      analista ? { analistas: [analista] } : {})
    return { resultados, proyeccion }
  }
  type FilaResultados = Pick<ReturnType<typeof calcularAvanceCitas>['total'],
    'resueltas' | 'visitas' | 'unicas' | 'clientes' | 'baseEntrevistas' | 'baseConversion' | 'tasaEntrevistas' | 'conversion'>
  const cifrasProyeccion = (m: MetricasProyeccion) => ({
    resueltas: m.resueltas.length, entrevistas: ids(m.entrevistas), personas: m.personasEntrevistadas, clientes: m.personasClientes,
    baseEntrevistas: m.baseEntrevistas, baseConversion: m.baseConversion,
    entrevistasPct: tasa(m.pctEntrevistas === null ? null : m.pctEntrevistas / 100), conversionPct: tasa(m.pctConversion === null ? null : m.pctConversion / 100),
  })
  const cifrasResultados = (r: FilaResultados) => ({
    resueltas: r.resueltas, entrevistas: ids(r.visitas.map(cita => ({ cita }))), personas: r.unicas, clientes: r.clientes,
    baseEntrevistas: r.baseEntrevistas, baseConversion: r.baseConversion, entrevistasPct: tasa(r.tasaEntrevistas), conversionPct: tasa(r.conversion),
  })

  it('el lote ejercita el caso: resultados del mes de citas creadas el mes anterior, que la regla de antes dejaba fuera', () => {
    const { resultados, proyeccion } = ambas('2026-10')
    const deSeptiembre = resultados.total.visitas.filter(c => fechaLocalCitas(c.creadoEn!) < '2026-10-01')
    expect(deSeptiembre.length).toBeGreaterThan(0)
    expect(ids(proyeccion.total.entrevistas)).toEqual(expect.arrayContaining(ids(deSeptiembre.map(cita => ({ cita })))))
    expect(proyeccion.total.resueltas.filter(c => c.creada < '2026-10-01').length).toBeGreaterThanOrEqual(3)
    expect(resultados.total.resueltas).toBe(proyeccion.total.resueltas.length)
    // Y hay ventas que vinculan entrevistas, para que la conversión también se compare con base.
    expect(ambas('2026-09').resultados.total.clientes).toBeGreaterThan(0)
  })

  it.each(['2026-09', '2026-10'])('con el rango del mes, % Entrev. y % Conv. y sus bases son los de Resultados, por analista y en el total, con cada regla, combinaciones y filtros (%s)', mes => {
    for (const reglas of REGLAS) {
      for (const consulta of CONSULTAS) {
        const { resultados, proyeccion } = ambas(mes, reglas, consulta)
        const nombre = `${mes} · ${JSON.stringify(reglas)} · ${JSON.stringify(consulta)}`
        expect(cifrasProyeccion(proyeccion.total), `${nombre} · total`).toEqual(cifrasResultados(resultados.total))
        for (const f of proyeccion.filas) {
          const r = resultados.filas.find(x => x.id === f.id)
          expect(r, `${nombre} · ${f.id} sin fila en Resultados`).toBeDefined()
          expect(cifrasProyeccion(f), `${nombre} · ${f.id}`).toEqual(cifrasResultados(r!))
        }
        // Todo analista con resultados en el mes (o con base de meta, con «meta_proyectada») tiene fila en la Proyección.
        const conCifra = resultados.filas.filter(x => x.resueltas > 0 || (reglas.base_avance === 'meta_proyectada' && x.baseEntrevistas > 0))
        for (const r of conCifra) expect(proyeccion.filas.map(f => f.id), `${nombre} · ${r.id}`).toContain(r.id)
      }
    }
  })

  it('caso Alan: dos citas de septiembre resueltas en octubre cuentan en octubre; quien solo tiene resultados tiene fila y es opción del embudo', () => {
    // Ana (n múltiplo de 4) y Mateo (n ≡ 3).
    const citas = [
      cita(0, { creadoEn: '2026-09-28T15:00:00Z', fecha: '2026-10-02', estado: 'realizada', asistioEn: '2026-10-02T16:00:00Z' }),
      cita(4, { creadoEn: '2026-09-29T15:00:00Z', fecha: '2026-10-03', estado: 'no_show' }),
      cita(8, { creadoEn: '2026-10-05T15:00:00Z', fecha: '2026-10-06', estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z' }),
      cita(12, { creadoEn: '2026-10-07T15:00:00Z', fecha: '2026-10-28' }),
      cita(3, { creadoEn: '2026-09-30T15:00:00Z', fecha: '2026-10-03', estado: 'realizada', asistioEn: '2026-10-03T16:00:00Z' }),
    ]
    const base = { citas, conversiones: [], poblacion: poblacionDe(citas), control: CONTROL, filtros: { equipo: '' }, corte: HOY, tipoCambio: TC }
    const hoja = calcularProyeccion({ ...base, rango: { desde: '2026-10-01', hasta: '2026-10-19' } })
    const ana = hoja.filas.find(f => f.id === 'ana')!
    // Citas: las 2 creadas en octubre. % Entrev.: 2 entrevistas ÷ 3 con resultado en octubre (antes: 1 ÷ 1 = 100 %).
    expect([ids(ana.citas), ids(ana.resueltas), ids(ana.entrevistas)]).toEqual([['c12', 'c8'], ['c0', 'c4', 'c8'], ['c0', 'c8']])
    expect(ana.pctEntrevistas).toBeCloseTo(200 / 3, 10)
    const gestion: GestionCitas = { citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones: [],
      avance: { control: CONTROL, poblacion: base.poblacion, conversiones: [], capital: [] } }
    expect(calcularAvanceCitas(gestion, citas, defaults('2026-10'), HOY, TC).filas.find(f => f.id === 'ana')!.tasaEntrevistas).toBeCloseTo(2 / 3, 10)
    // Mateo no creó citas en octubre, pero tuvo una entrevista: fila con Citas 0 y opción del embudo con 0 citas.
    expect(hoja.filas.find(f => f.id === 'mateo')).toMatchObject({ citas: [], pctEntrevistas: 100, ticket: null, proyectado: null })
    expect(opcionesAnalistas(hoja, { analistas: ['ana'] }).map(o => [o.id, o.citas])).toEqual([['ana', 2], ['mateo', 0]])
    expect(calcularProyeccion({ ...base, rango: { desde: '2026-10-01', hasta: '2026-10-19' } }, { analistas: ['ana'] }).filas.map(f => f.id)).toEqual(['ana'])
    // Septiembre no cuenta esos resultados: su resultado no cae en el rango.
    expect(calcularProyeccion({ ...base, rango: SEPTIEMBRE }).total.resueltas).toEqual([])
  })

  it('«meta_proyectada» con un rango parcial: la base son los asignados en el rango (Codex, 20/10/2026)', () => {
    // Ana: L1 asignado el 5/10 y entrevistado el 6/10; L2 asignado el 15/10, sin citas. Rango 1–10 oct, corte 20 oct, 1 cita por lead.
    const entrevista = cita(0, { leadId: 'L1', creadoEn: '2026-10-02T15:00:00Z', fecha: '2026-10-06', estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z' })
    const asignado = (leadId: string, dia: string): LeadBaseCitas => ({ id: 'ana', nombre: 'ana', supervisor: 'sup-1', supervisorId: 'sup-1', leadId,
      nombreLead: leadId, telefono: '900000000', asignadoEn: `${dia}T15:00:00Z`, manualPropio: false, origen: 'formulario', moneda: 'PEN', monto: 1000 })
    const control = { ...CONTROL, configuracion: { ...CONTROL.configuracion, base_avance: 'meta_proyectada' as const, citas_por_lead: 1 } }
    const base = { citas: [entrevista], conversiones: [], poblacion: [personaDe('L1'), personaDe('L2')], control, filtros: { equipo: '' },
      corte: '2026-10-20T17:00:00Z', tipoCambio: TC, asignaciones: [asignado('L1', '2026-10-05'), asignado('L2', '2026-10-15')] }
    const diez = calcularProyeccion({ ...base, rango: { desde: '2026-10-01', hasta: '2026-10-10' } }).filas.find(f => f.id === 'ana')!
    expect([diez.baseEntrevistas, diez.pctEntrevistas]).toEqual([1, 100])
    const mes = calcularProyeccion({ ...base, rango: { desde: '2026-10-01', hasta: '2026-10-31' } }).filas.find(f => f.id === 'ana')!
    expect([mes.baseEntrevistas, mes.pctEntrevistas]).toEqual([2, 50])
    // Con solo base y sin actividad en el rango, la fila existe con 0 %, como en Resultados.
    const tarde = calcularProyeccion({ ...base, rango: { desde: '2026-10-11', hasta: '2026-10-20' } }).filas.find(f => f.id === 'ana')!
    expect([tarde.citas.length, tarde.baseEntrevistas, tarde.pctEntrevistas]).toEqual([0, 1, 0])
  })

  it('sin reglas de gestión o sin la persona en la población, no hay tasa: lo mismo que muestra Resultados', () => {
    const sinReglas = calcularProyeccion(fuente(OCTUBRE, { control: undefined }))
    expect(sinReglas.total.citas.length).toBeGreaterThan(0)
    for (const m of filasYTotal(sinReglas)) expect([m.pctEntrevistas, m.pctConversion, m.proyectado, m.resueltas.length]).toEqual([null, null, null, 0])
    const borrador = calcularProyeccion(fuente(OCTUBRE, { control: { ...CONTROL, version: 0 } }))
    for (const m of filasYTotal(borrador)) expect([m.pctEntrevistas, m.pctConversion]).toEqual([null, null])
    // Un lead fuera de la población del avance no aporta resultados.
    const todo = calcularProyeccion(fuente(OCTUBRE))
    const fuera = todo.total.resueltas[0]!.cita.leadId
    const sinEse = calcularProyeccion(fuente(OCTUBRE, { poblacion: poblacionDe(lote().citas).filter(p => p.lead_id !== fuera) }))
    expect(sinEse.total.resueltas.some(c => c.cita.leadId === fuera)).toBe(false)
    expect(sinEse.total.resueltas.length).toBeLessThan(todo.total.resueltas.length)
  })

  it.each(RANGOS)('con Mín/Máx, el total mide solo las filas que quedan ($desde → $hasta)', rango => {
    for (const rangos of [{ entrevistas: { min: 50 } }, { citas: { max: 8 } }, { conversion: { max: 30 } }]) {
      const hoja = calcularProyeccion(fuente(rango), { rangos })
      expect(ids(hoja.total.resueltas), JSON.stringify(rangos)).toEqual(ids(hoja.filas.flatMap(f => f.resueltas)))
      expect(ids(hoja.total.entrevistas), JSON.stringify(rangos)).toEqual(ids(hoja.filas.flatMap(f => f.entrevistas)))
    }
  })
})
```
