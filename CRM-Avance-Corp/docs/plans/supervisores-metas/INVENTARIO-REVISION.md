# Inventario y resolución de la revisión final

Claude devolvió CHANGES_REQUESTED con dos P2 que pedían cambios **o evidencia**.
Se conserva el dictamen íntegro en `claude-final.txt`. Evaluación del PRIMARY:

## P2-1: consumidores de producción de supervisores

Aceptado el endurecimiento de tipos: `CumplimientoMetasJerarquico.supervisores`
es obligatorio. Los dos constructores de demo ahora declaran explícitamente `[]`.
Typecheck PASS. El inventario completo de runtime se incluye abajo.

Solo hay dos llamadas productivas a `RankingVendedoresPanel`: `equipo.tsx` y
`hoy/gerencia.tsx`; ambas pasan `supervisores`. Las rutas de consulta de Gerencia,
Directorio y Coordinación reutilizan esas pantallas, no tienen un tercer
consumidor del arreglo. `produccionPorPersona` integra los dos arreglos para
«Por empresa». El total de empresa se calcula con el arreglo RPC completo antes
de separarlo; el test septiembre/octubre exige igualdad exacta.

## P2-2: vista por equipo en Gerencia

Hipótesis descartada con el código actual, no se mezclan métricas distintas.
`equipo.tsx:921` construye el tablero con `metricas.equipos`, que viene de
`useMetricasVendedoresOperativas`; su capital está rotulado «Capital en proceso»
(`equipo.tsx:983`, `1036`). No consume `cumplimientoMetas`, metas ni capital
confirmado. No corresponde añadirle ventas cerradas.

`config-metas.tsx:207` agrupa **objetivos**, sin producción; esos objetivos no
cambian. `hoy/gerencia.tsx:514` consume `cumplimientoRanking.gerencia` para el
cumplimiento de empresa; `datos-supervisor.ts:167` consume `.supervisor` para el
cumplimiento de equipo. No existe en estas rutas otro agregado de cumplimiento
por supervisor construido con `porVendedor` que haya quedado pendiente.
Se añadió una prueba que obtiene el mismo cumplimiento de un equipo desde una
respuesta global y desde la respuesta recortada a ese supervisor.

## P3 y límites

- **Septiembre E2E:** la hipótesis no aplica. `_helpers.ts:3318-3331` lee `p_periodo`, devuelve ese periodo y conserva `fuera_ranking`. El comentario y el corte son correctos; se adjunta el handler abajo.
- **Rendimiento:** medición read-only del bloque SQL nuevo en la base productiva, sin instalar funciones ni devolver datos personales. `EXPLAIN (ANALYZE, BUFFERS)` tardó **181,270 ms**, planning 4,405 ms, 24.903 shared hits. Guion `supabase/scripts/supervisores-metas/rendimiento.sql`, salida `rendimiento.txt`. Es una muestra del bloque adicional, no latencia HTTP completa ni prueba de concurrencia/p95. No justifica duplicar o cambiar núcleos financieros.
- **Título «Ranking comercial»:** se conserva para abarcar las filas de supervisores que el usuario pidió incorporar. Las dos rutas nuevas pasaron E2E; los puestos y sus desempates no cambiaron.
- **Sello inexistente:** observación preexistente de una combinación que la lectura del cierre no produce en el mismo snapshot; se conserva la función para mantener paridad. No es una regresión de esta migración.
- **Metas de analista anteriores a una promoción:** se mantiene su pertenencia publicada. No se automatiza reatribución histórica. Consulta previa: cero supervisores actuales con meta de analista en octubre.
- **Cloud:** Auth/PostgREST, advisors y promoción siguen NOT RUN, como consta en VERIFICACION.md. La revisión local no los sustituye.

No se solicita una tercera opinión para conseguir un PASS. El PRIMARY resuelve
los hallazgos con cambios, código y pruebas; el dictamen original sigue visible.

## Inventario automático

```text
app/src/screens/hoy.tsx:9:import { HoyGerencia } from './hoy/gerencia'
app/src/screens/hoy.tsx:19:      return <HoyGerencia seccion="resumen" />
app/src/data/crm-queries.ts:21:import { cumplimientoDesdeRpc } from '@/lib/objetivos'
app/src/data/crm-queries.ts:1151:    select: (respuesta) => cumplimientoDesdeRpc(respuesta, actorId),
app/src/screens/equipo.tsx:41:import { RankingVendedoresPanel } from './hoy/ranking-vendedores'
app/src/screens/equipo.tsx:820:        <RankingVendedoresPanel
app/src/lib/demo-inteligencia-comercial.ts:11:  agregarCumplimientos,
app/src/lib/demo-inteligencia-comercial.ts:358:    gerencia: agregarCumplimientos(filas),
app/src/lib/demo-inteligencia-comercial.ts:360:    fueraRanking: [],
app/src/lib/store.tsx:82:  cumplimientoDesdeRpc,
app/src/lib/store.tsx:1095:        cumplimientoMetas: cumplimientoCoherente ? cumplimientoDesdeRpc(cumplimientoCoherente, yo?.id) : null,
app/src/screens/gerencia.tsx:2:import { HoyGerencia } from '@/screens/hoy/gerencia'
app/src/screens/gerencia.tsx:8:  return <HoyGerencia seccion="conversiones" />
app/src/screens/gerencia.tsx:12:  return <HoyGerencia seccion="ranking-vendedores" />
app/src/screens/gerencia.tsx:17:  return can(yo?.rol, 'verCitasEquipo') ? <CitasGerencia key={yo?.id} /> : <HoyGerencia seccion="reuniones" />
app/src/screens/gerencia.tsx:21:  return <HoyGerencia seccion="metas" />
app/src/screens/gerencia.tsx:25:  return <HoyGerencia seccion="rendimiento" />
app/src/lib/demo.ts:12:  agregarCumplimientos,
app/src/lib/demo.ts:295:  supervisor: agregarCumplimientos(CUMPLIMIENTO_DEMO_FILAS.filter((fila) => fila.supervisorId === 'd-sup1')),
app/src/lib/demo.ts:296:  gerencia: agregarCumplimientos(CUMPLIMIENTO_DEMO_FILAS),
app/src/lib/demo.ts:298:  fueraRanking: [],
app/src/lib/objetivos.ts:493:  fueraRanking: ProduccionFueraRanking[]
app/src/lib/objetivos.ts:566:export function agregarCumplimientos(
app/src/lib/objetivos.ts:647: * ya lleva dentro su propia meta, construida en `agregarCumplimientos` a partir
app/src/lib/objetivos.ts:659: * meta), `fueraRanking` y `supervisores` (desde octubre). «Por empresa»
app/src/lib/objetivos.ts:665:  cumplimiento: Pick<CumplimientoMetasJerarquico, 'porVendedor'> & { fueraRanking?: readonly ProduccionFueraRanking[]; supervisores?: readonly ProduccionFueraRanking[] } | null | undefined,
app/src/lib/objetivos.ts:668:  const fuera = Object.fromEntries([...(cumplimiento.fueraRanking ?? []), ...(cumplimiento.supervisores ?? [])]
app/src/lib/objetivos.ts:675:export function cumplimientoDesdeRpc(
app/src/lib/objetivos.ts:683:  const fueraRanking: ProduccionFueraRanking[] = (respuesta.fuera_ranking ?? []).map((fila) => ({
app/src/lib/objetivos.ts:726:    ? fueraRanking.filter((fila) => fila.rolCrm === 'supervisor' && fila.motivo === 'supervisor')
app/src/lib/objetivos.ts:741:  const metaEquipo = agregarCumplimientos(equipo)
app/src/lib/objetivos.ts:742:  const equipoConVentas = agregarCumplimientos([...equipo, ...(propia ? [propia] : [])])
app/src/lib/objetivos.ts:759:    gerencia: agregarCumplimientos([...filas, ...fueraRanking.map(comoCumplimiento)]),
app/src/lib/objetivos.ts:761:    fueraRanking: fueraRanking.filter((fila) => !supervisores.includes(fila)),
app/src/screens/hoy/ranking-vendedores.tsx:40:interface RankingVendedoresPanelProps {
app/src/screens/hoy/ranking-vendedores.tsx:78:  fueraRanking?: ProduccionFueraRanking[]
app/src/screens/hoy/ranking-vendedores.tsx:663:export function RankingVendedoresPanel({
app/src/screens/hoy/ranking-vendedores.tsx:678:  fueraRanking = [],
app/src/screens/hoy/ranking-vendedores.tsx:696:}: RankingVendedoresPanelProps): JSX.Element {
app/src/screens/hoy/ranking-vendedores.tsx:955:          <ProduccionFueraRankingPanel filas={fueraRanking} tc={tc} />
app/src/screens/hoy/gerencia.tsx:63:import { RankingVendedoresPanel } from './ranking-vendedores'
app/src/screens/hoy/gerencia.tsx:219:export function HoyGerencia({ seccion = 'completo' }: { seccion?: SeccionGerencia }): JSX.Element {
app/src/screens/hoy/gerencia.tsx:735:        <RankingVendedoresPanel
app/src/screens/hoy/gerencia.tsx:755:          fueraRanking={cumplimientoRanking?.fueraRanking ?? []}
```

### app/e2e/_helpers.ts

```text
3318:     if (p === '/rest/v1/rpc/cumplimiento_metas_fn' && method === 'POST') {
3319:       const body = (req.postDataJSON() ?? {}) as { p_periodo?: string }
3320:       const periodo = body.p_periodo ?? String(estado.cumplimientoMetas.periodo)
3321:       const mes = periodo.slice(0, 7)
3322:       const mismaFoto = periodo === estado.cumplimientoMetas.periodo
3323:       return json(route, {
3324:         ...estado.cumplimientoMetas,
3325:         periodo,
3326:         vendedores: mismaFoto ? estado.cumplimientoMetas.vendedores : [],
3327:         cierre: mes <= '2026-07'
3328:           ? { cerrado: true, cerrado_en: '2026-08-10T14:20:00.000Z', automatico: true }
3329:           : { cerrado: false },
3330:       })
3331:     }
3332:     // Las suites históricas conservan el modo legado. El spec SLA activo
3333:     // sobrescribe estas rutas con una política y una cola v2 completas.
```

### app/src/screens/equipo.tsx

```text
921:   const tablero = useMemo(() => {
922:     if (!metricas) return null
923:     const filas = metricas.equipos
924:     const bloques = filas.map((f) => {
925:       const rosterSup = new Set(
926:         (d.vendedoresPorSupervisor.get(f.supervisor.perfil_id) ?? []).map((m) => m.perfil_id),
927:       )
928:       const delEquipo = metricas.filas.filter((r) => rosterSup.has(r.m.perfil_id))
929:       // Cartera primero (ya vienen por capital PEN desc): los analistas en
930:       // cero absoluto van al final — la mirada cae en el capital en juego.
931:       // OJO: activos=0 con cierres u operaciones de cartera NO es cero. Una
932:       // renovación/upgrade acreditada debe seguir visible aunque no haya lead.
933:       const conActividadORevision = delEquipo.filter((r) => (
934:         r.activos > 0
935:         || !r.conversionDisponible
```

### app/src/screens/equipo.tsx

```text
978:       label: 'Equipos',
979:       value: tablero ? String(tablero.filas.length) : '—',
980:       tone: 'accent',
981:       sub: `${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} en total`,
982:     },
983:     tablero
984:       ? chipCapitalEnProceso(tablero.capPEN, tablero.capUSD, tc)
985:       : { icon: Wallet, label: 'Capital en proceso (PEN)', value: '—', tone: 'primary' },
986:     {
987:       icon: Activity,
```

### app/src/screens/config-metas.tsx

```text
196: 
197: /**
198:  * Cada bloque es un equipo, y su subtotal es lo que de verdad se le está
199:  * pidiendo a ese supervisor este mes.
200:  *
201:  * Se agrupa por `supervisor_id`, NO por nombre: la RPC ordena por
202:  * `supervisor_nombre`, así que dos supervisores homónimos salen adyacentes con
203:  * sus analistas intercalados, y un corte por nombre los fundiría en un grupo
204:  * con el subtotal equivocado. El Map conserva el orden de primera aparición,
205:  * que es el que ya trae el servidor.
206:  */
207: function agruparPorSupervisor(vendedores: ConfiguracionMetas['vendedores']) {
208:   const porId = new Map<string, {
209:     id: string
210:     supervisor: string
211:     filas: ConfiguracionMetas['vendedores']
212:   }>()
213:   for (const vendedor of vendedores) {
214:     const grupo = porId.get(vendedor.supervisor_id)
215:       ?? { id: vendedor.supervisor_id, supervisor: vendedor.supervisor_nombre, filas: [] }
216:     grupo.filas.push(vendedor)
217:     porId.set(vendedor.supervisor_id, grupo)
218:   }
219:   return [...porId.values()]
220: }
```

### app/src/screens/hoy/gerencia.tsx

```text
510:       : cumplimientoMetas
511:   // Meta, capital e identidad salen de la MISMA foto mensual. Si la foto no
512:   // llegó, se falla cerrado con ceros de objetivo y capital «—»: nunca se
513:   // recicla el store del mes vigente dentro de un histórico.
514:   const cumplimiento = cumplimientoRanking?.gerencia ?? null
515:   const metaBase = useMemo(
516:     () => objetivosCero(periodoRanking.desde).gerencia,
517:     [periodoRanking.desde],
518:   )
519:   const meta = metaVigente(sesionReal ? metaBase : objetivos.gerencia, cumplimiento)
520:   const equipoConversionHistorico = useMemo(
```

### app/src/screens/hoy/datos-supervisor.ts

```text
167:   const meta = metaVigente(objetivosMensuales.supervisor, cumplimientoMensual?.supervisor ?? null)
168:   const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
169:   const cumplimiento = cumplimientoMensual?.supervisor ?? null
170:   const metaCapitalPen = capitalObjetivo(meta, 'PEN')
171:   const metaCapitalUsd = capitalObjetivo(meta, 'USD')
172:   const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
173:   const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
174: 
175:   // LA CONVERSIÓN DEL MES del EQUIPO — total del payload de alcance 'equipo'
176:   // (crm.conversion_mensual_fn), no el cumplimiento: la definición acordada
177:   // llega ya, sin esperar a la migración B (E1, plan §4bis). El total viene
178:   // RECALCULADO del servidor (suma÷suma, jamás media de porcentajes).
```
