ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 2, una sola pasada): REFUTA la Fase 2 de la pestaña «Proyección» de Citas (front, React + TypeScript)

Contexto. CRM de Avance Corp (`CRM-Avance-Corp/app`, React 19 + Vite + Valibot + TanStack Query + Vitest + Playwright). La pestaña «Proyección» de Citas (publicada hoy, commit `bc7ad4fb`) es una hoja tipo Excel por analista sobre un rango Desde–Hasta: cohorte = citas cuya FECHA DE CREACIÓN (día de Lima) cae en el rango; columnas Citas · Monto S/ · Ticket · % Entrev. · % Conv. · Proyectado · Referidos · Clientes · Leads; embudos tipo Excel; todo número abre su lista lateral con CSV. Los datos llegan del lector de Citas por mes de fecha PREVISTA; la pantalla carga cada mes del rango y fusiona (dedupe por id de cita).

Regla del dueño (Miguel), innegociable: **«no puede haber data distinta»**: un mismo concepto no puede mostrar dos cifras distintas en el CRM, y cada cifra debe cuadrar con la base.

## Qué cambia en esta Fase 2 (decisiones del dueño, 19/10/2026)
1. Fuera la fila de pastillas de totales (la fila Σ de la tabla ya da los totales y abre sus listas). «Exportar CSV» pasa a la barra del periodo. «Reintentar TC» solo si falta el tipo de cambio.
2. Fuera las bandas por equipo: hoja plana, orden global por la columna elegida, # continuo.
3. En Proyección no se pintan los filtros de arriba ni «Exportar citas»; la línea de corte deja solo «Seguimiento al …». Se reutiliza el selector Supervisor dentro de la barra de la Proyección (mismo estado `filtros.equipo`). El analista se filtra con el embudo de su columna: en Proyección dejan de aplicar `filtros.analista` y `filtros.q`. Un error de los filtros de arriba no bloquea la Proyección. «Actualizar» recarga los meses del rango.
4. Selector Mes · Semanas · Días: columnas de tiempo antes de «Citas» (semanas comerciales 1–7 · 8–14 · 15–21 · 22–fin de cada mes del rango, recortadas al rango; días con hoy, domingo y futuro; Días solo con rangos de hasta 31 días, si no cae a Semanas). Cada celda = citas CREADAS ese tramo; abre su lista. CSV con una columna por tramo.
5. Enlace por URL `#/reuniones/proyeccion/<desde>/<hasta>[/semanas|dias][/equipo/<id>][/lead/<id>]` (variante nueva de `ConsultaCitasEnlace`); cambiar rango, columnas o supervisor dentro de la pestaña reescribe el enlace; ir a otra pestaña lo quita.
6. Consistencia con Resultados (tras una auditoría con datos reales de producción):
   - % Entrev. = realizadas ÷ RESUELTAS (realizada + no_show), como Resultados con `base_avance='actividad_real'` (antes ÷ todas las citas).
   - % Conv. = personas entrevistadas vinculadas a una venta con la MISMA regla de Resultados: `entrevistaCompatibleConVenta(asistioEn, fecha_comercial)` (antes `convertido_en ≥ asistencia`). Sin recortar la venta al mes; tope = el corte.
   - «Ticket S/» → «Ticket cita S/» y «Proyectado S/» → «Proyectado citas S/» (Resultados tiene «Ticket del mes» y «Cierre proyectado» con otras fórmulas).
   - Proyectado = citas esperadas × %Entrev × %Conv × ticket (como Resultados: entrevistas esperadas = citas esperadas × tasa observada).
   - Hoy del supervisor: el título «Citas de hoy» (citas PREVISTAS hoy) NO enlaza a la Proyección (que cuenta CREADAS).
   - Prueba nueva de invariantes (`proyeccion-invariantes.test.ts`): con citas creadas, previstas y resueltas en el mismo mes, Proyección y `calcularAvanceCitas` (Resultados) dan las mismas citas, entrevistas, resueltas, tasa y personas vinculadas.

## Tu trabajo: REFUTAR
Busca, con evidencia (archivo:línea del diff, caso concreto):
(a) cifras que no cuadren con estas reglas o con Resultados (`app/src/components/citas/avance.ts`, función `calcularAvanceCitas`, ~líneas 41–190): cohorte, tramos (¿la suma de tramos = Citas siempre?, ¿un tramo puede perder o duplicar una cita?), % Entrev., % Conv., proyectado, Σ, TC;
(b) la URL: estados que se pisan (bucle hash ⇄ estado, `enlaceAnterior`), enlaces que se quedan colgados al cambiar de pestaña, `sincronizarEnlace` convirtiendo un enlace de Proyección en otro, índices de `equipo`/`lead` en `leerHash`;
(c) filtros ocultos que sigan aplicando en Proyección o que la bloqueen; el Supervisor reutilizado (¿limpia bien el analista?);
(d) roturas en las otras pestañas (Bandeja, Agenda, Resultados) o en Hoy del supervisor;
(e) accesibilidad: dos botones «Mes» en la misma barra (atajo de periodo y columnas), grupos, `aria-pressed`, foco al cambiar de vista, celdas de tiempo como botones;
(f) pruebas que no prueben lo que dicen (en particular la de invariantes: ¿compara de verdad con Resultados o con una copia de la regla?).

Puedes intentar LEER el árbol del worktree (sandbox de solo lectura; cwd = `CRM-Avance-Corp`), pero no cuentes con ello: abajo va el diff completo.

Verificación ya hecha por el PRIMARY (no ejecutada por ti): `npm run check` (lint, typecheck, 7 366 pruebas antes de los últimos ajustes, cobertura, build, jscpd 0,74 %); E2E Docker de los specs de Citas, Hoy y Gerencia 67/69 con 2 fallos por carga del equipo que repetidos solos pasan 6/6 (y pasan sobre `bc7ad4fb`). La auditoría de datos midió en producción: base ↔ Proyección iguales al 100 % (4 rangos, 81 filas).

Formato de respuesta: VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Diff (código)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
index 105e15ea..36afbdf1 100644
--- a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
@@ -13,17 +13,26 @@ import { Filtros } from './filtros'
 import { Agenda, Bandeja, Estado } from './vistas'
 import { Resultados, DetalleLeads } from './resultados'
 import { ProyeccionCitas } from './proyeccion-hoja'
-import { errorRango, mesesDelRango, rangoInicial, rotuloRango, type RangoProyeccion } from './proyeccion-rango'
+import { errorRango, mesesDelRango, rangoInicial, rotuloRango, type RangoProyeccion, type TiempoProyeccion } from './proyeccion-rango'
 import { fechaLocalCitas } from './fecha-comercial'
 import { siguientePaso, contextoCita } from './presentacion'
 import { baseCitasFiltrada } from './metas'
 import { escribirHash, leerHash } from '@/lib/router'
-import { consultaCitasValida, mesConsultaCitas, type ConsultaCitasEnlace } from '@/lib/enlace-citas'
+import { consultaCitasValida, esConsultaProyeccion, mesConsultaCitas, type ConsultaCitasEnlace, type ConsultaProyeccionEnlace } from '@/lib/enlace-citas'
 
+/** Un enlace de Proyección no trae día ni semana: su periodo es su rango. */
 function filtrosDelEnlace(consulta: ConsultaCitasEnlace): FiltrosCitas {
   return { ...defaults(mesConsultaCitas(consulta)), ...(consulta.dia ? { dia: consulta.dia } : {}), semana: consulta.semana ?? '', equipo: consulta.equipo ?? '' }
 }
 
+type RangoMes = { mes: string } & RangoProyeccion
+const rangoDelMes = (mes: string, hoy: string): RangoMes => ({ mes, ...rangoInicial(mes, hoy) })
+/** El rango del enlace; si la pantalla no lo admite (más de 6 meses), el del mes. */
+function rangoDelEnlace(consulta: ConsultaProyeccionEnlace, mes: string, hoy: string): RangoMes {
+  const rango = { desde: consulta.desde, hasta: consulta.hasta }
+  return errorRango(rango) ? rangoDelMes(mes, hoy) : { mes, ...rango }
+}
+
 type VistaCitas = 'bandeja' | 'agenda' | 'resultados' | 'proyeccion'
 const VISTAS = [
   { id: 'bandeja', titulo: 'Bandeja comercial', icono: List },
@@ -78,21 +87,33 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
     return consulta ? filtrosDelEnlace(consulta) : guardada?.filtros ?? inicial()
   }
   const [filtros, setFiltros] = useState<FiltrosCitas>(desdeEnlace)
-  const [vista, setVista] = useState<VistaCitas>(() => leerHash().consultaCitas ? 'agenda' : guardada?.vista ?? 'resultados')
+  const [vista, setVista] = useState<VistaCitas>(() => {
+    const consulta = leerHash().consultaCitas
+    return consulta ? esConsultaProyeccion(consulta) ? 'proyeccion' : 'agenda' : guardada?.vista ?? 'resultados'
+  })
   const enlaceAnterior = useRef(JSON.stringify(leerHash().consultaCitas ?? null))
   const [pagina, setPagina] = useState(() => leerHash().consultaCitas ? 1 : guardada?.pagina ?? 1)
   // Rango Desde–Hasta de Proyección: propio de esa pestaña. Nace del mes de arriba
-  // y vuelve a nacer si ese mes cambia; no toca los filtros de las otras vistas.
-  const rangoDelMes = (mes: string) => ({ mes, ...rangoInicial(mes, fechaLocalCitas(corte)) })
-  const [rangoMes, setRangoMes] = useState<{ mes: string } & RangoProyeccion>(() =>
-    guardada?.rango && guardada.rango.mes === filtros.mes && !errorRango(guardada.rango) ? guardada.rango : rangoDelMes(filtros.mes))
-  if (rangoMes.mes !== filtros.mes && rangoConsulta(defaults(filtros.mes))[0]) setRangoMes(rangoDelMes(filtros.mes))
+  // (o del enlace) y vuelve a nacer si ese mes cambia; no toca los filtros de las otras vistas.
+  const hoyLima = fechaLocalCitas(corte)
+  const [rangoMes, setRangoMes] = useState<RangoMes>(() => {
+    const consulta = leerHash().consultaCitas
+    if (esConsultaProyeccion(consulta)) return rangoDelEnlace(consulta, filtros.mes, hoyLima)
+    const previo = guardada?.rango
+    return previo && previo.mes === filtros.mes && !errorRango(previo) ? { mes: previo.mes, desde: previo.desde, hasta: previo.hasta } : rangoDelMes(filtros.mes, hoyLima)
+  })
+  if (rangoMes.mes !== filtros.mes && rangoConsulta(defaults(filtros.mes))[0]) setRangoMes(rangoDelMes(filtros.mes, hoyLima))
+  // Columnas de tiempo de la Proyección: Mes (ninguna) · Semanas · Días.
+  const [tiempo, setTiempo] = useState<TiempoProyeccion>(() => {
+    const consulta = leerHash().consultaCitas
+    return esConsultaProyeccion(consulta) ? consulta.vista ?? 'mes' : guardada?.rango?.tiempo ?? 'mes'
+  })
   const rangoProyeccion = { desde: rangoMes.desde, hasta: rangoMes.hasta }
   const mesesProyeccion = vista === 'proyeccion' && !errorRango(rangoProyeccion) ? mesesDelRango(rangoProyeccion).join(',') : ''
   useEffect(() => { onMesesProyeccion?.(mesesProyeccion ? mesesProyeccion.split(',') : []) }, [mesesProyeccion, onMesesProyeccion])
   useEffect(() => {
-    guardarConsulta?.(anterior => ({ ...anterior, citas: { filtros, vista, pagina, rango: rangoMes } }))
-  }, [filtros, vista, pagina, rangoMes, guardarConsulta])
+    guardarConsulta?.(anterior => ({ ...anterior, citas: { filtros, vista, pagina, rango: { ...rangoMes, tiempo } } }))
+  }, [filtros, vista, pagina, rangoMes, tiempo, guardarConsulta])
   const [detalle, setDetalle] = useState<CitaEjemplo | null>(null)
   const [desglose, setDesglose] = useState<string | null>(null)
   const [leadAbierto, setLeadAbierto] = useState<string | null>(null)
@@ -112,10 +133,14 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   const analitica = vista === 'resultados' || vista === 'proyeccion'
   // Proyección con cargador propio: su carga y su error son los de los meses de SU
   // rango, no los del mes de arriba (que puede quedar fuera del rango).
-  const proyeccionPropia = vista === 'proyeccion' && proyeccion !== undefined
+  const propia = vista === 'proyeccion' ? proyeccion : undefined
+  const proyeccionPropia = propia !== undefined
   const cargandoVista = cargando && !proyeccionPropia
   const errorVista = proyeccionPropia ? null : errorCarga
-  const textoConteo = cargandoVista ? 'Cargando las citas de tu consulta…' : errorVista ? 'Consulta no disponible. Vuelve a intentarlo.' : error ? 'Revisa los filtros para consultar las citas.' : citas.length + (modoDemo ? ' de ' + CITAS.length + ' citas del ejemplo' : ' citas de tu consulta') + (vista === 'agenda' ? ' · orden cronológico · hora de Lima' : ' · según tus filtros')
+  // En Proyección los filtros de arriba no se pintan: su error no la bloquea ni se anuncia.
+  const textoConteo = cargandoVista ? 'Cargando las citas de tu consulta…' : errorVista ? 'Consulta no disponible. Vuelve a intentarlo.'
+    : vista === 'proyeccion' ? `Proyección por analista · ${rotuloRango(rangoProyeccion)}`
+    : error ? 'Revisa los filtros para consultar las citas.' : citas.length + (modoDemo ? ' de ' + CITAS.length + ' citas del ejemplo' : ' citas de tu consulta') + (vista === 'agenda' ? ' · orden cronológico · hora de Lima' : ' · según tus filtros')
 
   useEffect(() => { if (rangoConsulta(filtros)[0]) onMes?.(filtros.mes) }, [filtros, onMes])
 
@@ -127,15 +152,20 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
       if (firma === enlaceAnterior.current) return
       enlaceAnterior.current = firma
       const consulta = ruta.consultaCitas
-      setFiltros(consulta ? filtrosDelEnlace(consulta) : defaults(mesInicial))
-      setVista(consulta ? 'agenda' : 'resultados')
+      const siguientes = consulta ? filtrosDelEnlace(consulta) : defaults(mesInicial)
+      setFiltros(siguientes)
+      setVista(esConsultaProyeccion(consulta) ? 'proyeccion' : consulta ? 'agenda' : 'resultados')
+      if (esConsultaProyeccion(consulta)) {
+        setRangoMes(rangoDelEnlace(consulta, siguientes.mes, hoyLima))
+        setTiempo(consulta.vista ?? 'mes')
+      }
       setPagina(1)
       setDetalle(null)
       setLeadAbierto(null)
     }
     window.addEventListener('hashchange', recibir)
     return () => window.removeEventListener('hashchange', recibir)
-  }, [mesInicial])
+  }, [mesInicial, hoyLima])
 
   function quitarEnlace() {
     const ruta = leerHash()
@@ -149,6 +179,8 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   function sincronizarEnlace(siguientes: FiltrosCitas) {
     const ruta = leerHash()
     if (!ruta.consultaCitas) return
+    // Un enlace de Proyección sigue siéndolo: solo cambia su supervisor.
+    if (esConsultaProyeccion(ruta.consultaCitas)) { sincronizarProyeccion({ equipo: siguientes.equipo }); return }
     const consulta = {
       ...(siguientes.dia ? { dia: siguientes.dia } : { mes: siguientes.mes, ...(siguientes.semana ? { semana: siguientes.semana } : {}) }),
       ...(siguientes.equipo ? { equipo: siguientes.equipo } : {}),
@@ -159,6 +191,21 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
     window.dispatchEvent(new HashChangeEvent('hashchange'))
   }
 
+  /** Con un enlace de Proyección abierto, el rango, las columnas y el supervisor que se eligen viajan en él. */
+  function sincronizarProyeccion(cambio: { rango?: RangoProyeccion; tiempo?: TiempoProyeccion; equipo?: string }) {
+    const ruta = leerHash()
+    if (!esConsultaProyeccion(ruta.consultaCitas)) return
+    const { desde: inicio, hasta: fin } = cambio.rango ?? rangoProyeccion
+    const columnas = cambio.tiempo ?? tiempo
+    const equipo = cambio.equipo ?? filtros.equipo
+    const consulta = { desde: inicio, hasta: fin, ...(columnas !== 'mes' ? { vista: columnas } : {}), ...(equipo ? { equipo } : {}) }
+    if (!consultaCitasValida(consulta)) { quitarEnlace(); return }
+    escribirHash('reuniones', ruta.leadId, true, undefined, undefined, undefined, undefined, consulta)
+    // La firma es la que lee el router, para que el oyente no la tome por un enlace nuevo.
+    enlaceAnterior.current = JSON.stringify(leerHash().consultaCitas ?? null)
+    window.dispatchEvent(new HashChangeEvent('hashchange'))
+  }
+
   useEffect(() => {
     const temporizador = window.setTimeout(() => setAnuncio(textoConteo), 250)
     return () => window.clearTimeout(temporizador)
@@ -176,7 +223,14 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
     setLeadAbierto(null)
   }
   function restablecer() { quitarEnlace(); setFiltros(inicial()); setPagina(1); setExportacion(''); setLeadAbierto(null) }
-  function cambiarVista(destino: VistaCitas) { setVista(destino); setLeadAbierto(null) }
+  function cambiarVista(destino: VistaCitas) {
+    // Un enlace de Proyección no describe otra pestaña.
+    if (destino !== 'proyeccion' && esConsultaProyeccion(leerHash().consultaCitas)) quitarEnlace()
+    setVista(destino)
+    setLeadAbierto(null)
+  }
+  function cambiarRango(rango: RangoProyeccion) { setRangoMes({ mes: filtros.mes, ...rango }); sincronizarProyeccion({ rango }) }
+  function cambiarTiempo(columnas: TiempoProyeccion) { setTiempo(columnas); sincronizarProyeccion({ tiempo: columnas }) }
   function enfocarVista(destino: VistaCitas) {
     requestAnimationFrame(() => requestAnimationFrame(() => pestañas.current[destino]?.focus()))
   }
@@ -214,17 +268,21 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   return <div className="gerencia-inteligencia citas-integradas" data-consulta-lista={!cargando && !errorCarga}>
       <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
         <div><h1 className="citas-titulo-seccion">Citas del equipo</h1><p className="citas-nota">Seguimiento, recuperación y metas por lead{modoDemo ? ' · Datos de ejemplo' : ''}</p></div>
-        <div className="flex max-w-full flex-wrap gap-2"><Button variant="ghost" aria-label="Cómo usar Citas" onClick={() => setGuia(true)}><CircleHelp aria-hidden />Ayuda</Button><Button variant="outline" onClick={onReintentar} disabled={cargando}>Actualizar</Button><Button variant="outline" onClick={exportar} disabled={Boolean(error || errorCarga || cargando || !citas.length)}><Download aria-hidden />Exportar citas</Button></div>
+        <div className="flex max-w-full flex-wrap gap-2"><Button variant="ghost" aria-label="Cómo usar Citas" onClick={() => setGuia(true)}><CircleHelp aria-hidden />Ayuda</Button>
+          {/* Con cargador propio, la Proyección recarga los meses de SU rango. */}
+          <Button variant="outline" onClick={propia ? propia.onReintentar : onReintentar} disabled={propia ? propia.cargando : cargando}>Actualizar</Button>
+          {vista !== 'proyeccion' && <Button variant="outline" onClick={exportar} disabled={Boolean(error || errorCarga || cargando || !citas.length)}><Download aria-hidden />Exportar citas</Button>}</div>
       </div>
       <div id="consulta-citas" tabIndex={-1} className="outline-none">
-        <Filtros filtros={filtros} onCambiar={cambiar} onRestablecer={restablecer} />
+        {/* La Proyección tiene su propia barra (Supervisor, rango y columnas): los filtros de arriba no aplican allí. */}
+        {vista !== 'proyeccion' && <Filtros filtros={filtros} onCambiar={cambiar} onRestablecer={restablecer} />}
         <div className="citas-controles-vista"><div className="citas-vistas" role="tablist" tabIndex={-1} aria-label="Cómo ver las citas" onKeyDown={tecladoVista}>
           {VISTAS.map(item => <Button key={item.id} id={'citas-tab-' + item.id} ref={elemento => { pestañas.current[item.id] = elemento }}
             role="tab" aria-controls="citas-panel" aria-selected={vista === item.id} tabIndex={vista === item.id ? 0 : -1}
             variant="ghost" className={cn('citas-pestana', vista === item.id && 'citas-pestana-activa')} onClick={() => cambiarVista(item.id)}>
             <item.icono aria-hidden />{item.titulo}
           </Button>)}
-        </div><p className="citas-corte">Citas: {vista === 'proyeccion' ? rotuloRango(rangoProyeccion) : `${fmtFecha(desde)}–${fmtFecha(hasta)}`}<span>Seguimiento al {corteLima(corte)}</span></p></div>
+        </div><p className="citas-corte">{vista !== 'proyeccion' && `Citas: ${fmtFecha(desde)}–${fmtFecha(hasta)}`}<span>Seguimiento al {corteLima(corte)}</span></p></div>
         <section className={analitica ? undefined : 'gi-card citas-vista-operativa'} aria-label="Resultados de la consulta">
           <div className={analitica ? 'sr-only' : 'flex flex-wrap items-center justify-between gap-3 py-4'}>
             <div><h2 className="text-base font-semibold">{vista === 'agenda' ? 'Agenda por día' : vista === 'resultados' ? 'Resultados por analista' : vista === 'proyeccion' ? 'Proyección por analista' : 'Todas las citas de tu consulta'}</h2>
@@ -242,11 +300,11 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
             })}
           </div>}
           <div id="citas-panel" role="tabpanel" aria-labelledby={'citas-tab-' + vista} tabIndex={0} className="outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent">
-            {cargandoVista ? <p role="status" className="p-8">Cargando las citas de tu consulta…</p> : errorVista ? <div role="alert" className="space-y-3 p-8"><p>{errorVista}</p><Button variant="outline" onClick={onReintentar}>Reintentar</Button></div> : error || (citas.length === 0 && vista !== 'proyeccion' && !(vista === 'resultados' && hayBase)) ? <div className="space-y-3 px-4 py-12 text-center">
+            {cargandoVista ? <p role="status" className="p-8">Cargando las citas de tu consulta…</p> : errorVista ? <div role="alert" className="space-y-3 p-8"><p>{errorVista}</p><Button variant="outline" onClick={onReintentar}>Reintentar</Button></div> : vista !== 'proyeccion' && (error || (citas.length === 0 && !(vista === 'resultados' && hayBase))) ? <div className="space-y-3 px-4 py-12 text-center">
               <SearchX aria-hidden className="mx-auto size-7 text-muted-foreground" /><h3 className="font-semibold">{error ? 'Revisa los filtros de la consulta' : 'No hay citas con esta combinación'}</h3>
               <p className="text-sm text-muted-foreground-strong">{error || 'Quita algún filtro o elige otro período.'}</p><Button variant="outline" onClick={restablecer}>Limpiar filtros</Button>
             </div> : vista === 'bandeja' ? <Bandeja citas={visibles} onDetalle={setDetalle} /> : vista === 'agenda' ? <Agenda citas={citas} onDetalle={setDetalle} />
-              : vista === 'proyeccion' ? <ProyeccionCitas filtros={filtros} rango={rangoProyeccion} onRango={r => setRangoMes({ mes: filtros.mes, ...r })} />
+              : vista === 'proyeccion' ? <ProyeccionCitas equipo={filtros.equipo} rango={rangoProyeccion} tiempo={tiempo} onRango={cambiarRango} onTiempo={cambiarTiempo} onEquipo={equipo => cambiar({ equipo })} />
               : <Resultados citas={citas} filtros={filtros} onAnalista={verAnalista} onDesglose={id => { setLeadAbierto(null); setDesglose(id) }} onDetalle={abrirCitaDelRecorrido} leadAbierto={leadAbierto} onLead={setLeadAbierto} />}
           </div>
           {vista === 'bandeja' && !error && !errorCarga && !cargando && citas.length > 0 && <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border py-3">
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-barra-rango.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-barra-rango.tsx
index 95b1d181..3461aa97 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-barra-rango.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-barra-rango.tsx
@@ -1,10 +1,14 @@
-// Periodo de la Proyección: Desde–Hasta propios de la pestaña y atajos. Un rango
-// inválido no se aplica: se avisa y la hoja conserva el último válido.
-import { useState } from 'react'
+// Barra de la Proyección: Desde–Hasta propios de la pestaña y atajos, con lo que
+// la pestaña ponga antes (Supervisor) y después (columnas de tiempo y acciones),
+// en una sola línea que se parte si no cabe. Un rango inválido no se aplica: se
+// avisa y la hoja conserva el último válido.
+import { useState, type ReactNode } from 'react'
 import { Input } from '@/components/ui/input'
 import { atajosRango, errorRango, rotuloRango, type RangoProyeccion } from './proyeccion-rango'
 
-export function BarraRango({ rango, hoy, onRango }: { rango: RangoProyeccion; hoy: string; onRango: (rango: RangoProyeccion) => void }) {
+export function BarraRango({ rango, hoy, onRango, antes, children }: {
+  rango: RangoProyeccion; hoy: string; onRango: (rango: RangoProyeccion) => void; antes?: ReactNode; children?: ReactNode
+}) {
   const [borrador, setBorrador] = useState(rango)
   const [previo, setPrevio] = useState(rango)
   // Un cambio que llega de fuera (atajo, otro mes arriba) reemplaza lo escrito.
@@ -15,7 +19,8 @@ export function BarraRango({ rango, hoy, onRango }: { rango: RangoProyeccion; ho
     setBorrador(siguiente)
     if (!errorRango(siguiente)) onRango(siguiente)
   }
-  return <div className="pc-periodo" role="group" aria-label="Periodo de la proyección">
+  return <div className="pc-periodo" role="group" aria-label="Consulta de la proyección">
+    {antes}
     <strong className="pc-rotulo" data-testid="pc-rotulo-rango">{rotuloRango(rango)}</strong>
     <label className="pc-fecha">Desde<Input type="date" className="h-8" value={borrador.desde} aria-invalid={Boolean(error)} aria-describedby={error ? 'pc-rango-error' : undefined} onChange={e => cambiar({ desde: e.target.value })} /></label>
     <label className="pc-fecha">Hasta<Input type="date" className="h-8" value={borrador.hasta} aria-invalid={Boolean(error)} aria-describedby={error ? 'pc-rango-error' : undefined} onChange={e => cambiar({ hasta: e.target.value })} /></label>
@@ -25,6 +30,7 @@ export function BarraRango({ rango, hoy, onRango }: { rango: RangoProyeccion; ho
         return <button key={atajo.id} type="button" className="pc-atajo" aria-pressed={activo} onClick={() => onRango(atajo.rango)}>{atajo.etiqueta}</button>
       })}
     </div>
+    {children}
     {error && <p id="pc-rango-error" role="alert" className="pc-rango-error">{error}</p>}
   </div>
 }
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
index 0628ee5b..9c17301d 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
@@ -1,22 +1,24 @@
-// Pestaña «Proyección» de Citas: hoja por analista, agrupada por equipo, con
-// embudos tipo Excel en cada cabecera. Todo número se abre en su lista.
+// Pestaña «Proyección» de Citas: hoja plana, una fila por analista, con embudos
+// tipo Excel en cada cabecera y, a elección, columnas de semanas o días antes de
+// «Citas». Todo número se abre en su lista.
 import { useCallback, useMemo, useRef, useState } from 'react'
-import { ArrowDown, ChevronDown, Download, Filter, X } from 'lucide-react'
+import { ArrowDown, Download, Filter, X } from 'lucide-react'
 import { Button } from '@/components/ui/button'
-import { Pastilla } from '@/components/ui/pastilla'
+import { Select } from '@/components/ui/select'
 import { iniciales, numero } from '@/lib/format'
 import { METAS_CITAS_INICIALES } from '@/lib/metas-citas-config'
 import { useTipoCambio } from '@/lib/tipo-cambio'
 import { cn } from '@/lib/utils'
 import { useDatosCitas } from './contexto'
 import { fechaLocalCitas } from './fecha-comercial'
-import type { FiltrosCitas } from './modelo'
 import {
   COLUMNA_DE_ORIGEN, ORDEN_INICIAL, ORIGENES, calcularProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas,
   opcionesPersonas, type ColumnaNumerica, type ColumnaProyeccion, type FiltrosColumnas,
   type MetricasProyeccion, type OrdenProyeccion, type OrigenCita,
 } from './proyeccion'
-import { mesesDelRango, rotuloRango, type RangoProyeccion } from './proyeccion-rango'
+import {
+  diasPermitidos, mesesDelRango, rotuloRango, tiempoEfectivo, type RangoProyeccion, type TiempoProyeccion, type TramoProyeccion,
+} from './proyeccion-rango'
 import { BarraRango } from './proyeccion-barra-rango'
 import { EmbudoColumna, type CambioEmbudo } from './proyeccion-embudo'
 import { DetalleProyeccion, type ListaProyeccion } from './proyeccion-detalle'
@@ -30,10 +32,11 @@ const COLUMNAS: readonly { id: ColumnaProyeccion; titulo: string; tipo: TipoColu
   { id: 'analista', titulo: 'Analista', tipo: 'texto' },
   { id: 'citas', titulo: 'Citas', tipo: 'num' },
   { id: 'monto', titulo: 'Monto S/', tipo: 'monto' },
-  { id: 'ticket', titulo: 'Ticket S/', tipo: 'num' },
+  // «Ticket cita» y «Proyectado citas»: Resultados ya llama «Ticket del mes» y «Cierre proyectado» a otras cifras.
+  { id: 'ticket', titulo: 'Ticket cita S/', tipo: 'num' },
   { id: 'entrevistas', titulo: '% Entrev.', tipo: 'num' },
   { id: 'conversion', titulo: '% Conv.', tipo: 'num' },
-  { id: 'proyectado', titulo: 'Proyectado S/', tipo: 'num' },
+  { id: 'proyectado', titulo: 'Proyectado citas S/', tipo: 'num' },
   { id: 'referidos', titulo: 'Referidos', tipo: 'personas' },
   { id: 'clientes', titulo: 'Clientes', tipo: 'personas' },
   { id: 'leads', titulo: 'Leads', tipo: 'personas' },
@@ -53,11 +56,23 @@ const SIN_CITAS: never[] = []
 const listaDe = (m: MetricasProyeccion, tipo: TipoLista) => tipo === 'citas' ? m.citas : tipo === 'monto' ? m.conMonto
   : tipo === 'entrevistas' ? m.entrevistas : tipo === 'conversion' ? m.convertidas : m[COLUMNA_DE_ORIGEN[tipo]]
 const soles = (valor: number | null) => valor === null ? '—' : `S/ ${numero(valor)}`
-const porcentaje = (valor: number | null) => valor === null ? '—' : `${numero(valor, 1)}%`
 const resumirNombres = (nombres: string[]) => nombres.slice(0, 2).join(', ') + (nombres.length > 2 ? ` +${nombres.length - 2}` : '')
 const textoRango = (r: { min?: number | undefined; max?: number | undefined } | undefined) => !r ? ''
   : r.min !== undefined && r.max !== undefined ? `${numero(r.min, 2)} – ${numero(r.max, 2)}` : r.min !== undefined ? `≥ ${numero(r.min, 2)}` : r.max !== undefined ? `≤ ${numero(r.max, 2)}` : ''
 
+const TIEMPOS: readonly { id: TiempoProyeccion; etiqueta: string }[] = [
+  { id: 'mes', etiqueta: 'Mes' }, { id: 'semanas', etiqueta: 'Semanas' }, { id: 'dias', etiqueta: 'Días' },
+]
+const claseTramo = (t: TramoProyeccion) => cn('pc-tiempo', t.domingo && 'pc-domingo', t.hoy && 'pc-hoy', t.futuro && 'pc-futuro')
+
+/** Supervisores del equipo y de las citas del rango; el elegido siempre aparece. «Sin supervisor» al final. */
+function supervisoresDe(listas: readonly (readonly { supervisorId: string; supervisor: string }[])[], elegido: string): [string, string][] {
+  const nombres = new Map<string, string>()
+  for (const lista of listas) for (const p of lista) if (!nombres.has(p.supervisorId)) nombres.set(p.supervisorId, p.supervisor)
+  if (elegido && !nombres.has(elegido)) nombres.set(elegido, elegido === 'sin_supervisor' ? 'Sin supervisor' : 'Equipo seleccionado')
+  return [...nombres].sort(([a, x], [b, y]) => Number(a === 'sin_supervisor') - Number(b === 'sin_supervisor') || x.localeCompare(y, 'es'))
+}
+
 /** Cifra que se abre: un 0 no es botón. */
 function Cifra({ cantidad, texto, etiqueta, onAbrir, dinero = false }: { cantidad: number; texto: string; etiqueta: string; onAbrir: () => void; dinero?: boolean }) {
   const contenido = dinero && texto.startsWith('S/ ') ? <><span className="pc-m" aria-hidden>S/</span>{texto.slice(3)}</> : texto
@@ -65,12 +80,17 @@ function Cifra({ cantidad, texto, etiqueta, onAbrir, dinero = false }: { cantida
   return <button type="button" className="pc-n" aria-label={`${texto} ${etiqueta}`} onClick={onAbrir}>{contenido}</button>
 }
 
-function Celdas({ m, nombre, objetivos, abrir }: {
-  m: MetricasProyeccion; nombre: string; objetivos: { entrevistas: number; conversion: number }; abrir: (tipo: TipoLista) => void
+function Celdas({ m, nombre, objetivos, tramos, abrir }: {
+  m: MetricasProyeccion; nombre: string; objetivos: { entrevistas: number; conversion: number }
+  tramos: readonly TramoProyeccion[]; abrir: (tipo: TipoLista, tramo?: string) => void
 }) {
   const de = `de ${nombre}`
   return <>
-    <td><Cifra cantidad={m.citas.length} texto={numero(m.citas.length)} etiqueta={`${etiquetaCitas('citas', m.citas.length)} ${de}`} onAbrir={() => abrir('citas')} /></td>
+    {tramos.map((t, i) => {
+      const n = m.porTramo[i]?.length ?? 0
+      return <td key={t.id} className={claseTramo(t)}><Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas('citas', n)} ${de}, ${t.rotulo}`} onAbrir={() => abrir('citas', t.id)} /></td>
+    })}
+    <td className={tramos.length ? 'pc-tcierre' : undefined}><Cifra cantidad={m.citas.length} texto={numero(m.citas.length)} etiqueta={`${etiquetaCitas('citas', m.citas.length)} ${de}`} onAbrir={() => abrir('citas')} /></td>
     <td><Cifra cantidad={m.conMonto.length} texto={m.pendienteTc ? 'Pendiente de TC' : m.conMonto.length ? soles(m.monto) : '—'} etiqueta={`en citas ${de}`} onAbrir={() => abrir('monto')} dinero /></td>
     <td><span className={cn('pc-n', m.ticket === null && 'pc-cero')}>{m.ticket === null ? '—' : <><span className="pc-m" aria-hidden>S/</span>{numero(m.ticket)}</>}</span></td>
     <td><SenalMetrica valor={m.pctEntrevistas} objetivo={objetivos.entrevistas} etiqueta={`% Entrev. ${de}`} abrir={m.entrevistas.length ? () => abrir('entrevistas') : undefined} /></td>
@@ -83,7 +103,18 @@ function Celdas({ m, nombre, objetivos, abrir }: {
   </>
 }
 
-export function ProyeccionCitas({ filtros, rango, onRango }: { filtros: FiltrosCitas; rango: RangoProyeccion; onRango: (rango: RangoProyeccion) => void }) {
+export interface PropsProyeccion {
+  /** Supervisor elegido ('' = todos): el mismo estado que la consulta de las otras pestañas. */
+  equipo: string
+  rango: RangoProyeccion
+  /** Lo elegido; con más de 31 días, «Días» se pinta como «Semanas». */
+  tiempo: TiempoProyeccion
+  onRango: (rango: RangoProyeccion) => void
+  onTiempo: (tiempo: TiempoProyeccion) => void
+  onEquipo: (equipo: string) => void
+}
+
+export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEquipo }: PropsProyeccion) {
   const datos = useDatosCitas()
   // Con cargador, las citas son las de los meses del rango ya fusionados; sin él
   // (ejemplo y pruebas), las de arriba. Mientras falte un mes no hay cifras.
@@ -96,41 +127,48 @@ export function ProyeccionCitas({ filtros, rango, onRango }: { filtros: FiltrosC
   const avance = gestion?.avance
   const [columnas, setColumnas] = useState<FiltrosColumnas>({})
   const [orden, setOrden] = useState<OrdenProyeccion>(ORDEN_INICIAL)
-  const [cerradas, setCerradas] = useState<ReadonlySet<string>>(() => new Set())
-  const [detalle, setDetalle] = useState<{ tipo: TipoLista; filaId: string | null } | null>(null)
+  const [detalle, setDetalle] = useState<{ tipo: TipoLista; filaId: string | null; tramo?: string | undefined } | null>(null)
   const [menu, setMenu] = useState<{ columna: ColumnaProyeccion; ancla: HTMLButtonElement } | null>(null)
   const [aviso, setAviso] = useState('')
   const hojaRef = useRef<HTMLDivElement>(null)
   // Al quitar un filtro su chip desaparece: el foco vuelve al embudo de esa columna.
   const embudos = useRef<Partial<Record<ColumnaProyeccion, HTMLButtonElement | null>>>({})
   // Un embudo de personas o analistas de otro periodo o equipo vaciaría la hoja.
-  const firma = [rango.desde, rango.hasta, filtros.equipo, filtros.analista].join('|')
+  const { desde, hasta } = rango
+  const firma = [desde, hasta, equipo].join('|')
   const [firmaColumnas, setFirmaColumnas] = useState(firma)
   if (firma !== firmaColumnas) { setFirmaColumnas(firma); setColumnas({}) }
 
   // El tipo de cambio se toma al fin del rango o a hoy, si el rango sigue abierto.
   const hoy = fechaLocalCitas(corte)
-  const { tc, recargar } = useTipoCambio(citas.some(c => c.moneda === 'USD' && (c.monto ?? 0) > 0), rango.hasta < hoy ? rango.hasta : hoy)
+  const { tc, recargar } = useTipoCambio(citas.some(c => c.moneda === 'USD' && (c.monto ?? 0) > 0), hasta < hoy ? hasta : hoy)
   const hoja = useMemo(() => calcularProyeccion({
-    citas, filtros, rango, corte, tipoCambio: tc?.promedio, conversiones: avance?.conversiones ?? null, poblacion: avance?.poblacion,
-  }, columnas, orden), [citas, filtros, rango, corte, tc?.promedio, avance, columnas, orden])
+    citas, filtros: { equipo }, rango: { desde, hasta }, tiempo, corte, tipoCambio: tc?.promedio,
+    conversiones: avance?.conversiones ?? null, poblacion: avance?.poblacion,
+  }, columnas, orden), [citas, equipo, desde, hasta, tiempo, corte, tc?.promedio, avance, columnas, orden])
+  const vistaTiempo = tiempoEfectivo(tiempo, rango)
   const objetivos = {
     entrevistas: avance?.control.configuracion.entrevistas_porcentaje ?? gestion?.entrevistasPorcentaje ?? METAS_CITAS_INICIALES.entrevistas_porcentaje,
     conversion: avance?.control.configuracion.depositos_porcentaje ?? gestion?.depositosPorcentaje ?? METAS_CITAS_INICIALES.depositos_porcentaje,
   }
   const rotulo = rotuloRango(rango)
-  const sufijo = `${rango.desde}_${rango.hasta}`
+  const sufijo = `${desde}_${hasta}`
   const t = hoja.total
   const cerrarMenu = useCallback(() => setMenu(null), [])
 
   const filaAbierta = detalle?.filaId ? hoja.filas.find(f => f.id === detalle.filaId) : undefined
   const fuenteDetalle = detalle && (detalle.filaId === null ? t : filaAbierta)
-  // Si la fila sale de la hoja (recarga o embudo), la lista se cierra y no reaparece sola.
-  if (detalle && !fuenteDetalle) setDetalle(null)
-  const lista: ListaProyeccion | null = detalle && fuenteDetalle ? {
-    titulo: `${TITULOS_LISTA[detalle.tipo]} · ${filaAbierta?.nombre ?? 'Total'}`, periodo: rotulo,
-    lista: [...listaDe(fuenteDetalle, detalle.tipo)].sort((a, b) => `${a.cita.fecha} ${a.cita.hora}`.localeCompare(`${b.cita.fecha} ${b.cita.hora}`) || a.cita.id.localeCompare(b.cita.id)),
-    conAnalista: !filaAbierta, archivo: `proyeccion-citas-${detalle.tipo}-${sufijo}.csv`,
+  const iTramo = detalle?.tramo === undefined ? -1 : hoja.tramos.findIndex(tr => tr.id === detalle.tramo)
+  const tramo = hoja.tramos[iTramo]
+  // Si la fila o su columna de tiempo salen de la hoja (recarga, embudo u otro
+  // rango), la lista se cierra y no reaparece sola.
+  const vigente = Boolean(fuenteDetalle && (detalle?.tramo === undefined || tramo))
+  if (detalle && !vigente) setDetalle(null)
+  const lista: ListaProyeccion | null = detalle && fuenteDetalle && vigente ? {
+    titulo: [TITULOS_LISTA[detalle.tipo], tramo?.rotulo, filaAbierta?.nombre ?? 'Total'].filter(Boolean).join(' · '),
+    periodo: tramo ? rotuloRango(tramo) : rotulo,
+    lista: [...(tramo ? fuenteDetalle.porTramo[iTramo] ?? [] : listaDe(fuenteDetalle, detalle.tipo))].sort((a, b) => `${a.cita.fecha} ${a.cita.hora}`.localeCompare(`${b.cita.fecha} ${b.cita.hora}`) || a.cita.id.localeCompare(b.cita.id)),
+    conAnalista: !filaAbierta, archivo: `proyeccion-citas-${detalle.tipo}-${tramo ? `${tramo.desde}_${tramo.hasta}` : sufijo}.csv`,
   } : null
 
   function alternarOrden(columna: ColumnaProyeccion) {
@@ -167,78 +205,67 @@ export function ProyeccionCitas({ filtros, rango, onRango }: { filtros: FiltrosC
   }
   const columnaMenu = menu && COLUMNAS.find(c => c.id === menu.columna)!
   const origenMenu = menu ? ORIGEN_DE_COLUMNA[menu.columna] : undefined
-  const inicios = hoja.bandas.map((_, i) => hoja.bandas.slice(0, i).reduce((n, b) => n + b.filas.length, 0))
-  const pastilla = (etiqueta: string, valor: string, cantidad: number, tipo: TipoLista) =>
-    <Pastilla etiqueta={etiqueta} valor={valor} pista="ver la lista" onAbrir={cantidad ? () => setDetalle({ tipo, filaId: null }) : undefined} />
 
-  const barraRango = <BarraRango rango={rango} hoy={hoy} onRango={onRango} />
-  if (delRango?.error) return <div className="pc-panel">{barraRango}<div role="alert" className="space-y-3 py-8"><p>{delRango.error}</p><Button variant="outline" onClick={delRango.onReintentar}>Reintentar</Button></div></div>
-  if (!preparado) return <div className="pc-panel">{barraRango}<p role="status" className="py-8 text-sm text-muted-foreground-strong">Cargando las citas del rango…</p></div>
+  // Barra única: Supervisor · periodo · columnas de tiempo · acciones (estas, solo con la hoja lista).
+  const supervisores = supervisoresDe([datos.equipo, citas], equipo)
+  const barra = (conAcciones: boolean) => <BarraRango rango={rango} hoy={hoy} onRango={onRango}
+    antes={<label className="pc-fecha pc-supervisor">Supervisor<Select aria-label="Supervisor" className="h-8" value={equipo} onChange={e => onEquipo(e.target.value)}>
+      <option value="">Todos</option>{supervisores.map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}
+    </Select></label>}>
+    <div className="pc-atajos pc-tiempos" role="group" aria-label="Columnas de tiempo">
+      {TIEMPOS.map(op => <button key={op.id} type="button" className="pc-atajo" aria-pressed={vistaTiempo === op.id}
+        disabled={op.id === 'dias' && !diasPermitidos(rango)} onClick={() => onTiempo(op.id)}>{op.etiqueta}</button>)}
+    </div>
+    {conAcciones && <div className="pc-acciones">
+      {hoja.requiereTc && tc === null && <Button variant="outline" size="sm" onClick={recargar}>Reintentar TC</Button>}
+      <Button variant="outline" size="sm" onClick={exportar} disabled={!hoja.filas.length}><Download aria-hidden />Exportar CSV</Button>
+    </div>}
+  </BarraRango>
+  if (delRango?.error) return <div className="pc-panel">{barra(false)}<div role="alert" className="space-y-3 py-8"><p>{delRango.error}</p><Button variant="outline" onClick={delRango.onReintentar}>Reintentar</Button></div></div>
+  if (!preparado) return <div className="pc-panel">{barra(false)}<p role="status" className="py-8 text-sm text-muted-foreground-strong">Cargando las citas del rango…</p></div>
 
-  return <div className="pc-panel">
-    {barraRango}
-    <div className="pc-barra">
-      <div className="pc-pastillas" role="group" aria-label="Totales de la proyección">
-        {pastilla('Citas', numero(t.citas.length), t.citas.length, 'citas')}
-        {pastilla('Monto', t.pendienteTc ? 'Pendiente de TC' : soles(t.monto ?? 0), t.conMonto.length, 'monto')}
-        <Pastilla etiqueta="Ticket" valor={soles(t.ticket)} />
-        {pastilla('Entrevistas', porcentaje(t.pctEntrevistas), t.entrevistas.length, 'entrevistas')}
-        {pastilla('Conversión', porcentaje(t.pctConversion), t.convertidas.length, 'conversion')}
-        <Pastilla etiqueta="Proyectado" valor={soles(t.proyectado)} />
-        {pastilla('Referidos', numero(t.referidos.length), t.referidos.length, 'referido')}
-        {pastilla('Clientes', numero(t.clientes.length), t.clientes.length, 'cliente')}
-        {pastilla('Leads', numero(t.leads.length), t.leads.length, 'lead')}
-        <Pastilla etiqueta="Analistas" valor={numero(hoja.filas.length)} />
-        <Pastilla etiqueta="TC" valor={tc ? numero(tc.promedio, 3) : hoja.requiereTc ? 'Pendiente' : '—'} title={tc?.fuente} />
-      </div>
-      <div className="pc-acciones">
-        {hoja.requiereTc && tc === null && <Button variant="outline" size="sm" onClick={recargar}>Reintentar TC</Button>}
-        <Button variant="outline" size="sm" onClick={exportar} disabled={!hoja.filas.length}><Download aria-hidden />Exportar CSV</Button>
+  const cabecera = (col: (typeof COLUMNAS)[number]) => {
+    const activo = chips.some(ch => ch.id === col.id)
+    return <th key={col.id} scope="col" data-col={col.id} data-filtro={activo}
+      className={cn(col.id === 'analista' && 'pc-analista pc-texto', col.id === 'citas' && hoja.tramos.length > 0 && 'pc-tcierre') || undefined}
+      aria-sort={orden.columna === col.id ? orden.direccion === 'asc' ? 'ascending' : 'descending' : undefined}>
+      <div className="pc-th">
+        <button type="button" className="pc-th-orden" onClick={() => alternarOrden(col.id)}>{col.titulo}<ArrowDown className="pc-flecha" aria-hidden /></button>
+        <button ref={boton => { embudos.current[col.id] = boton }} type="button" className="pc-embudo" aria-label={`Filtrar ${col.titulo}${activo ? ', con filtro' : ''}`} aria-haspopup="dialog" aria-expanded={menu?.columna === col.id}
+          onClick={evento => { const ancla = evento.currentTarget; setMenu(actual => actual?.columna === col.id ? null : { columna: col.id, ancla }) }}><Filter aria-hidden /></button>
       </div>
-    </div>
+    </th>
+  }
+
+  return <div className="pc-panel">
+    {barra(true)}
     {chips.length > 0 && <div className="pc-chips" role="group" aria-label="Filtros de columna">
       {chips.map(ch => <span key={ch.id} className="pc-chip"><b>{ch.titulo}</b> {ch.texto}<button type="button" aria-label={`Quitar filtro de ${ch.titulo}`} onClick={() => { cambiarColumna(ch.id, null); embudos.current[ch.id]?.focus() }}><X aria-hidden /></button></span>)}
       <Button variant="ghost" size="sm" onClick={() => { const primero = chips[0]!.id; setColumnas({}); embudos.current[primero]?.focus() }}>Limpiar</Button>
     </div>}
     {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Hoja ancha consultable con flechas del teclado. */}
     <div ref={hojaRef} className="pc-scroll" role="region" tabIndex={0} aria-label="Hoja de proyección por analista">
-      <table className="pc-hoja">
+      <table className="pc-hoja" data-tiempo={vistaTiempo}>
         <caption className="sr-only">Proyección de citas por analista · {rotulo}</caption>
         <thead><tr>
           <th scope="col" className="pc-n0"><span aria-hidden>#</span><span className="sr-only">Número</span></th>
-          {COLUMNAS.map(col => {
-            const activo = chips.some(ch => ch.id === col.id)
-            return <th key={col.id} scope="col" className={col.id === 'analista' ? 'pc-analista pc-texto' : undefined} data-filtro={activo}
-              aria-sort={orden.columna === col.id ? orden.direccion === 'asc' ? 'ascending' : 'descending' : undefined}>
-              <div className="pc-th">
-                <button type="button" className="pc-th-orden" onClick={() => alternarOrden(col.id)}>{col.titulo}<ArrowDown className="pc-flecha" aria-hidden /></button>
-                <button ref={boton => { embudos.current[col.id] = boton }} type="button" className="pc-embudo" aria-label={`Filtrar ${col.titulo}${activo ? ', con filtro' : ''}`} aria-haspopup="dialog" aria-expanded={menu?.columna === col.id}
-                  onClick={evento => { const ancla = evento.currentTarget; setMenu(actual => actual?.columna === col.id ? null : { columna: col.id, ancla }) }}><Filter aria-hidden /></button>
-              </div>
-            </th>
-          })}
+          {cabecera(COLUMNAS[0]!)}
+          {hoja.tramos.map(tr => <th key={tr.id} scope="col" className={claseTramo(tr)}>
+            {/* Cada palabra del detalle va entera: si no cabe, solo baja el mes («22–30» / «set»). */}
+            <span className="pc-tiempo-cab" aria-hidden>{tr.titulo}<small>{tr.detalle.split(' ').flatMap((parte, i) =>
+              i ? [' ', <span key={i}>{parte}</span>] : [<span key={i}>{parte}</span>])}</small></span><span className="sr-only">{tr.nombre}</span>
+          </th>)}
+          {COLUMNAS.slice(1).map(cabecera)}
         </tr></thead>
-        {hoja.bandas.map((banda, b) => {
-          const abierta = !cerradas.has(banda.id)
-          return <tbody key={banda.id}>
-            <tr className="pc-banda">
-              <th scope="rowgroup" colSpan={COLUMNAS.length + 1}>
-                <button type="button" aria-expanded={abierta} onClick={() => setCerradas(actual => { const s = new Set(actual); if (s.has(banda.id)) s.delete(banda.id); else s.add(banda.id); return s })}>
-                  <ChevronDown aria-hidden />{banda.id === 'sin_supervisor' ? 'Sin supervisor' : `Equipo ${banda.nombre}`}<small>· {numero(banda.filas.length)} {banda.filas.length === 1 ? 'analista' : 'analistas'} · {numero(banda.citas)} citas</small>
-                </button>
-              </th>
-            </tr>
-            {abierta && banda.filas.map((f, i) => <tr key={f.id} className="pc-fila">
-              <td className="pc-n0">{inicios[b]! + i + 1}</td>
-              <th scope="row" className="pc-analista"><span className="pc-nombre"><span className="pc-avatar" aria-hidden>{iniciales(f.nombre)}</span>{f.nombre}</span></th>
-              <Celdas m={f} nombre={f.nombre} objetivos={objetivos} abrir={tipo => setDetalle({ tipo, filaId: f.id })} />
-            </tr>)}
-          </tbody>
-        })}
+        <tbody>{hoja.filas.map((f, i) => <tr key={f.id} className="pc-fila">
+          <td className="pc-n0">{i + 1}</td>
+          <th scope="row" className="pc-analista"><span className="pc-nombre"><span className="pc-avatar" aria-hidden>{iniciales(f.nombre)}</span>{f.nombre}</span></th>
+          <Celdas m={f} nombre={f.nombre} objetivos={objetivos} tramos={hoja.tramos} abrir={(tipo, tramo) => setDetalle({ tipo, filaId: f.id, tramo })} />
+        </tr>)}</tbody>
         <tfoot><tr>
           <td className="pc-n0"><span aria-hidden>Σ</span></td>
           <th scope="row" className="pc-analista">Total · {numero(hoja.filas.length)} {hoja.filas.length === 1 ? 'analista' : 'analistas'}</th>
-          <Celdas m={t} nombre="todos los analistas" objetivos={objetivos} abrir={tipo => setDetalle({ tipo, filaId: null })} />
+          <Celdas m={t} nombre="todos los analistas" objetivos={objetivos} tramos={hoja.tramos} abrir={(tipo, tramo) => setDetalle({ tipo, filaId: null, tramo })} />
         </tr></tfoot>
       </table>
     </div>
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-rango.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion-rango.ts
index 2b97c728..4aeb093b 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-rango.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-rango.ts
@@ -6,8 +6,11 @@ import { fechaValida } from './modelo'
 export interface RangoProyeccion { desde: string; hasta: string }
 /** Tope de meses: cada mes del rango es una consulta al servidor. */
 export const MAX_MESES_RANGO = 6
+/** Tope de columnas de la vista por días; con más, la hoja cae a semanas. */
+export const MAX_DIAS_COLUMNAS = 31
 const DIA = 86_400_000
 const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic']
+const DIAS_CORTOS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb']
 const aDia = (fecha: string) => Date.UTC(Number(fecha.slice(0, 4)), Number(fecha.slice(5, 7)) - 1, Number(fecha.slice(8, 10)))
 const dos = (n: number) => String(n).padStart(2, '0')
 
@@ -18,6 +21,10 @@ function mesSiguiente(mes: string, paso = 1) {
   const d = new Date(Date.UTC(Number(mes.slice(0, 4)), Number(mes.slice(5, 7)) - 1 + paso, 1))
   return `${d.getUTCFullYear()}-${dos(d.getUTCMonth() + 1)}`
 }
+/** Semana comercial n (1–4) del mes: 1–7 · 8–14 · 15–21 · 22–fin. */
+const semanaDelMes = (mes: string, n: number): RangoProyeccion =>
+  ({ desde: `${mes}-${dos((n - 1) * 7 + 1)}`, hasta: n < 4 ? `${mes}-${dos(n * 7)}` : finDeMes(mes) })
+const mesCorto = (fecha: string) => MESES_CORTOS[Number(fecha.slice(5, 7)) - 1]!
 
 /** Día 1 del mes de la consulta hasta hoy; si el mes ya pasó (o aún no empieza), el mes entero. */
 export function rangoInicial(mes: string, hoy: string): RangoProyeccion {
@@ -51,8 +58,7 @@ export function atajosRango(hoy: string, hasta: string): AtajoRango[] {
     { id: 'semana', etiqueta: 'Esta semana', rango: { desde: lunes, hasta: hoy } },
     { id: 'mes', etiqueta: 'Mes', rango: { desde: `${hoy.slice(0, 7)}-01`, hasta: hoy } },
     { id: 'mes-pasado', etiqueta: 'Mes pasado', rango: { desde: `${pasado}-01`, hasta: finDeMes(pasado) } },
-    ...[1, 2, 3, 4].map(n => ({ id: `s${n}`, etiqueta: `S${n}`,
-      rango: { desde: `${mes}-${dos((n - 1) * 7 + 1)}`, hasta: n < 4 ? `${mes}-${dos(n * 7)}` : finDeMes(mes) } })),
+    ...[1, 2, 3, 4].map(n => ({ id: `s${n}`, etiqueta: `S${n}`, rango: semanaDelMes(mes, n) })),
   ]
 }
 
@@ -60,11 +66,64 @@ export function atajosRango(hoy: string, hasta: string): AtajoRango[] {
 export function rotuloRango(rango: RangoProyeccion): string {
   if (!fechaValida(rango.desde) || !fechaValida(rango.hasta)) return 'Periodo no válido'
   const dia = (f: string) => Number(f.slice(8))
-  const mes = (f: string) => MESES_CORTOS[Number(f.slice(5, 7)) - 1]!
   const { desde, hasta } = rango
   const anio = hasta.slice(0, 4)
-  if (desde === hasta) return `${dia(desde)} ${mes(desde)} ${anio}`
-  if (desde.slice(0, 7) === hasta.slice(0, 7)) return `${dia(desde)}–${dia(hasta)} ${mes(hasta)} ${anio}`
-  if (desde.slice(0, 4) === anio) return `${dia(desde)} ${mes(desde)} – ${dia(hasta)} ${mes(hasta)} ${anio}`
-  return `${dia(desde)} ${mes(desde)} ${desde.slice(0, 4)} – ${dia(hasta)} ${mes(hasta)} ${anio}`
+  if (desde === hasta) return `${dia(desde)} ${mesCorto(desde)} ${anio}`
+  if (desde.slice(0, 7) === hasta.slice(0, 7)) return `${dia(desde)}–${dia(hasta)} ${mesCorto(hasta)} ${anio}`
+  if (desde.slice(0, 4) === anio) return `${dia(desde)} ${mesCorto(desde)} – ${dia(hasta)} ${mesCorto(hasta)} ${anio}`
+  return `${dia(desde)} ${mesCorto(desde)} ${desde.slice(0, 4)} – ${dia(hasta)} ${mesCorto(hasta)} ${anio}`
+}
+
+// ───────── Columnas de tiempo (Fase 2) ─────────
+/** «mes»: la hoja sin columnas de tiempo; «semanas» y «dias» reparten las citas del rango. */
+export type TiempoProyeccion = 'mes' | 'semanas' | 'dias'
+
+export interface TramoProyeccion extends RangoProyeccion {
+  id: string
+  /** Cabecera: «S2», o el día («19»; «1 nov» el día 1 de un mes y la primera columna). */
+  titulo: string
+  /** Bajo el título: los días de la semana («8–14»; «22–30 set» si el rango cruza meses) o el día corto («lun»). */
+  detalle: string
+  /** Título de la lista: «S2 8–14 oct» · «19 oct». */
+  rotulo: string
+  /** Lector de pantalla y CSV: «S2 8–14 oct» · «lun 19 oct». */
+  nombre: string
+  domingo: boolean
+  hoy: boolean
+  futuro: boolean
+}
+
+/** La vista por días admite rangos de hasta 31 días. */
+export const diasPermitidos = (rango: RangoProyeccion) => !errorRango(rango) && diasEntre(rango.desde, rango.hasta) < MAX_DIAS_COLUMNAS
+
+/** La vista que de verdad se pinta: «Días» con más de 31 días cae a «Semanas». */
+export const tiempoEfectivo = (tiempo: TiempoProyeccion, rango: RangoProyeccion): TiempoProyeccion =>
+  tiempo === 'dias' && !diasPermitidos(rango) ? 'semanas' : tiempo
+
+const textoDias = (desde: string, hasta: string) => desde === hasta ? `${Number(desde.slice(8))}` : `${Number(desde.slice(8))}–${Number(hasta.slice(8))}`
+
+/** Columnas de tiempo del rango, en orden. Semanas comerciales de cada mes recortadas al rango; días, uno por columna. */
+export function tramosDelRango(rango: RangoProyeccion, tiempo: TiempoProyeccion, hoy: string): TramoProyeccion[] {
+  const vista = tiempoEfectivo(tiempo, rango)
+  if (vista === 'mes' || errorRango(rango)) return []
+  if (vista === 'dias') {
+    return Array.from({ length: diasEntre(rango.desde, rango.hasta) + 1 }, (_, i) => {
+      const fecha = sumarDias(rango.desde, i)
+      const dia = Number(fecha.slice(8))
+      const semana = DIAS_CORTOS[new Date(aDia(fecha)).getUTCDay()]!
+      const rotulo = `${dia} ${mesCorto(fecha)}`
+      return { id: fecha, desde: fecha, hasta: fecha, titulo: i === 0 || dia === 1 ? rotulo : String(dia), detalle: semana,
+        rotulo, nombre: `${semana} ${rotulo}`, domingo: semana === 'dom', hoy: fecha === hoy, futuro: fecha > hoy }
+    })
+  }
+  const cruza = rango.desde.slice(0, 7) !== rango.hasta.slice(0, 7)
+  return mesesDelRango(rango).flatMap(mes => [1, 2, 3, 4].map(n => {
+    const semana = semanaDelMes(mes, n)
+    const desde = semana.desde < rango.desde ? rango.desde : semana.desde
+    const hasta = semana.hasta > rango.hasta ? rango.hasta : semana.hasta
+    const dias = textoDias(desde, hasta)
+    const rotulo = `S${n} ${dias} ${mesCorto(desde)}`
+    return { id: `${mes}-s${n}`, desde, hasta, titulo: `S${n}`, detalle: cruza ? `${dias} ${mesCorto(desde)}` : dias,
+      rotulo, nombre: rotulo, domingo: false, hoy: false, futuro: desde > hoy }
+  })).filter(tramo => tramo.desde <= tramo.hasta)
 }
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
index 72d2b39e..b34e5da6 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
@@ -1,9 +1,5 @@
 /* Proyección de citas: hoja tipo Excel a todo el ancho (propuesta B aprobada el 19/10/2026). */
 .pc-panel { font-variant-numeric: tabular-nums; --pc-cruz: color-mix(in srgb, var(--accent) 6%, white); }
-.pc-barra { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px 12px; margin-bottom: 10px; }
-.pc-pastillas { display: flex; flex: 1 1 0; flex-wrap: wrap; gap: 6px; min-width: 0; }
-.pc-pastillas > * { padding-block: 4px; font-size: 13px; }
-.pc-acciones { display: flex; flex-wrap: wrap; gap: 8px; }
 .pc-chips { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; margin-bottom: 10px; }
 .pc-chip { display: inline-flex; align-items: center; gap: 6px; min-height: 28px; padding: 0 3px 0 10px; border: 1px solid color-mix(in srgb, var(--accent) 22%, white); border-radius: 999px; background: color-mix(in srgb, var(--accent) 9%, white); color: var(--accent-press); font-size: 12px; font-weight: 500; }
 .pc-chip b { font-weight: 600; }
@@ -11,15 +7,19 @@
 .pc-chip button:hover { background: color-mix(in srgb, var(--accent) 16%, white); }
 .pc-chip svg { width: 12px; height: 12px; }
 
-/* ── Periodo: Desde–Hasta y atajos ── */
+/* ── Barra única: Supervisor · periodo · atajos · columnas de tiempo · acciones ── */
 .pc-periodo { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 12px; margin-bottom: 10px; }
+.pc-supervisor > div { width: 190px; }
 .pc-rotulo { min-width: 110px; color: var(--primary); font-size: 16px; font-weight: 700; font-variant-numeric: tabular-nums; }
 .pc-fecha { display: inline-flex; align-items: center; gap: 6px; color: var(--muted-foreground-strong); font-size: 13px; font-weight: 500; }
 .pc-fecha input { width: 150px; }
 .pc-atajos { display: flex; flex-wrap: wrap; gap: 4px; }
 .pc-atajo { height: 28px; padding: 0 10px; border: 1px solid var(--border); border-radius: 999px; background: var(--card); color: var(--muted-foreground-strong); font-size: 12px; font-weight: 600; cursor: pointer; transition: border-color 0.15s, background 0.15s, color 0.15s; }
-.pc-atajo:hover { border-color: var(--border-strong); color: var(--primary); }
+.pc-atajo:hover:not(:disabled, [aria-pressed='true']) { border-color: var(--border-strong); color: var(--primary); }
 .pc-atajo[aria-pressed='true'] { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 10%, white); color: var(--accent-press); }
+.pc-atajo:disabled { opacity: 0.45; cursor: not-allowed; }
+.pc-tiempos { padding-left: 12px; border-left: 1px solid var(--border-strong); }
+.pc-acciones { display: flex; flex-wrap: wrap; gap: 8px; margin-left: auto; }
 .pc-rango-error { flex-basis: 100%; color: var(--destructive-text); font-size: 13px; }
 
 /* ── La hoja ── */
@@ -54,21 +54,43 @@ th[data-filtro='true'] .pc-th-orden { color: var(--accent-press); }
 .pc-hoja tbody th.pc-analista { color: var(--primary); font-size: 16px; font-weight: 600; }
 .pc-nombre { display: flex; align-items: center; gap: 10px; min-width: 180px; max-width: 260px; white-space: normal; line-height: 1.25; }
 .pc-avatar { display: grid; place-items: center; width: 28px; height: 28px; flex-shrink: 0; border-radius: 50%; background: var(--secondary); color: var(--primary); font-size: 10px; font-weight: 700; }
+
+/* Columnas de tiempo, justo antes de «Citas» (que lleva el borde que las cierra). Sin embudo ni orden. */
+.pc-hoja .pc-tiempo { min-width: 52px; }
+.pc-hoja thead th.pc-tiempo { padding: 0 8px; }
+.pc-tiempo-cab { display: flex; flex-direction: column; align-items: flex-end; justify-content: center; height: 42px; color: var(--primary); font-size: 13px; font-weight: 600; line-height: 1.15; }
+.pc-tiempo-cab small { color: var(--muted-foreground-strong); font-size: 12px; font-weight: 500; }
+.pc-hoja :is(th, td).pc-domingo { background: color-mix(in srgb, var(--primary) 4%, white); }
+.pc-hoja thead th.pc-domingo { background: color-mix(in srgb, var(--primary) 10%, white); }
+.pc-hoja :is(th, td).pc-hoy { background: color-mix(in srgb, var(--accent) 7%, white); }
+.pc-hoja thead th.pc-hoy { background: color-mix(in srgb, var(--accent) 16%, white); }
+.pc-hoja thead th.pc-hoy .pc-tiempo-cab { color: var(--accent-press); }
+.pc-hoja td.pc-futuro .pc-n { color: var(--muted-foreground); }
+.pc-hoja :is(th, td).pc-tcierre { border-left: 2px solid var(--border-strong); }
+.pc-hoja[data-tiempo='dias'] .pc-tiempo { min-width: 44px; padding-inline: 6px; }
+.pc-hoja[data-tiempo='dias'] thead th.pc-tiempo { padding-inline: 6px; }
+/* Semanas: hasta 5 columnas de tiempo (un mes que no empieza el día 1) caben a 1440 px sin desplazar.
+   Como «Días» en la pieza aprobada: celdas más apretadas, y los títulos largos en dos líneas. */
+.pc-hoja[data-tiempo='semanas'] :is(td, tbody th, tfoot th) { padding-inline: 5px; }
+.pc-hoja[data-tiempo='semanas'] .pc-th { padding: 0 1px 0 5px; }
+.pc-hoja[data-tiempo='semanas'] .pc-tiempo { min-width: 40px; }
+.pc-hoja[data-tiempo='semanas'] thead th.pc-tiempo { padding-inline: 5px; }
+/* Si el rango cruza meses, el mes del detalle («22–30 set») baja de línea solo cuando no cabe. */
+.pc-hoja[data-tiempo='semanas'] .pc-tiempo-cab small { white-space: normal; line-height: 1.05; text-align: right; }
+.pc-tiempo-cab small > span { white-space: nowrap; }
+.pc-hoja[data-tiempo='semanas'] .pc-nombre { min-width: 120px; }
+.pc-hoja[data-tiempo='semanas'] tfoot th.pc-analista { white-space: normal; line-height: 1.2; }
+.pc-hoja[data-tiempo='semanas'] :is([data-col='monto'], [data-col='ticket'], [data-col='proyectado']) .pc-th-orden { white-space: normal; line-height: 1.15; text-align: right; }
+.pc-hoja[data-tiempo='semanas'] .pc-n { margin: 0 -4px; padding: 0 4px; }
+.pc-hoja[data-tiempo='semanas'] .cm-senal { min-width: 60px; margin-left: -4px; }
 .pc-fila:is(:hover, :focus-within) :is(td, th) { background: var(--pc-cruz); }
 .pc-fila:hover .pc-n0 { background: color-mix(in srgb, var(--accent) 12%, white); color: var(--primary); }
 .pc-hoja .pc-proyectado { background: color-mix(in srgb, var(--background) 65%, white); }
 
-.pc-banda th { height: 36px; padding: 0; background: var(--secondary); border-right: 0; text-align: left; }
-.pc-banda button { position: sticky; left: 0; display: inline-flex; align-items: center; gap: 8px; height: 36px; padding: 0 12px 0 16px; color: var(--primary); font-size: 13px; font-weight: 600; cursor: pointer; }
-.pc-banda button:hover { color: var(--accent-press); }
-.pc-banda small { font-size: 12px; font-weight: 500; color: var(--muted-foreground-strong); }
-.pc-banda svg { width: 14px; height: 14px; transition: transform 0.2s var(--ease-out-expo); }
-.pc-banda button[aria-expanded='false'] svg { transform: rotate(-90deg); }
-
 .pc-hoja tfoot :is(th, td) { position: sticky; bottom: 0; z-index: 3; height: 46px; border-top: 1px solid var(--border-strong); border-bottom: 0; background: var(--muted); color: var(--primary); font-weight: 700; }
 .pc-hoja tfoot :is(.pc-n0, .pc-analista) { z-index: 4; }
 .pc-hoja tfoot .pc-n { font-weight: 700; }
-.pc-hoja tfoot .pc-proyectado { background: var(--muted); }
+.pc-hoja tfoot :is(.pc-proyectado, .pc-tiempo) { background: var(--muted); }
 
 .pc-n { display: inline-flex; align-items: center; justify-content: flex-end; min-width: 36px; height: 32px; margin: 0 -8px; padding: 0 8px; border-radius: 6px; color: inherit; font: inherit; font-weight: 500; transition: background 0.14s, color 0.14s; }
 button.pc-n { cursor: pointer; }
@@ -119,22 +141,21 @@ button.pc-persona:hover { color: var(--accent-press); text-decoration: underline
 .pc-panel :is(.pc-scroll, .pc-hoja button):focus-visible { outline-offset: -2px; }
 @media (max-width: 1440px) { .pc-avatar { display: none; } .pc-hoja :is(th, td) { padding-inline: 8px; } .pc-nombre { min-width: 150px; max-width: 210px; } .pc-scroll { scroll-padding-left: 270px; } }
 @media (max-width: 767px) {
-  .pc-pastillas { flex-basis: 100%; }
   .pc-nombre { min-width: 132px; }
   .pc-hoja tbody th.pc-analista { white-space: normal; }
   .pc-scroll { max-height: none; }
-  .pc-pastillas > * { font-size: 12px; }
+  .pc-tiempos { padding-left: 0; border-left: 0; }
 }
 /* Táctil: toda zona pulsable mide al menos 44 px. */
 @media (pointer: coarse) {
   .pc-embudo { min-width: 44px; min-height: 44px; }
   .pc-chip button { position: relative; }
   .pc-chip button::after { content: ''; position: absolute; inset: -11px; }
-  .pc-hoja .pc-n, .pc-hoja button.cm-senal, .pc-banda button { height: 44px; min-height: 44px; }
+  .pc-hoja .pc-n, .pc-hoja button.cm-senal { height: 44px; min-height: 44px; }
   .pc-op, .pc-atajo { min-height: 44px; }
-  .pc-fecha input { height: 44px; }
+  .pc-fecha :is(input, select) { height: 44px; }
   .pc-menu input:not([type='checkbox']) { height: 44px; }
 }
 @media (prefers-reduced-motion: reduce) {
-  .pc-menu, .pc-flecha, .pc-banda svg, .pc-n { animation: none !important; transition: none !important; }
+  .pc-menu, .pc-flecha, .pc-n, .pc-atajo { animation: none !important; transition: none !important; }
 }
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
index 7c99d412..dc9c7475 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
@@ -2,15 +2,19 @@
 // React ni red, para que cada cifra de la hoja se pruebe con datos fijos.
 //
 // Cohorte: las citas cuya FECHA DE CREACIÓN (día de Lima) cae en el rango
-// Desde–Hasta de la pestaña, con el supervisor, el analista y la búsqueda de la
-// consulta de arriba (su semana y su día no aplican aquí: manda el rango). Las
-// citas llegan del servidor por mes de su fecha prevista; la pantalla carga cada
-// mes del rango y los fusiona antes de llegar aquí.
+// Desde–Hasta de la pestaña y, si se eligió, del supervisor de su barra. El
+// analista se acota con el embudo de su columna. Las citas llegan del servidor por
+// mes de su fecha prevista; la pantalla carga cada mes del rango y los fusiona
+// antes de llegar aquí.
+//
+// «No puede haber data distinta» (Miguel, 19/10/2026): % Entrev. y % Conv. usan
+// las MISMAS reglas que Resultados (`calcularAvanceCitas`): entrevistas ÷ citas
+// resueltas y el vínculo entrevista → venta por fecha comercial.
 import { tcAplicable } from '@/lib/capital-unificado'
 import { usdAPen } from '@/lib/tipo-cambio'
-import { fechaLocalCitas } from './fecha-comercial'
-import { ESTADOS, coincideBusqueda, normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
-import { diasEntre, errorRango, type RangoProyeccion } from './proyeccion-rango'
+import { entrevistaCompatibleConVenta, fechaLocalCitas } from './fecha-comercial'
+import { ESTADOS, normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
+import { diasEntre, errorRango, tramosDelRango, type RangoProyeccion, type TiempoProyeccion, type TramoProyeccion } from './proyeccion-rango'
 
 /** Una cita cuenta en una sola de las tres: Referidos + Clientes + Leads = Citas. */
 export type OrigenCita = 'referido' | 'cliente' | 'lead'
@@ -21,13 +25,19 @@ export type ColumnaNumerica = Exclude<ColumnaProyeccion, 'analista'>
 export const ORIGENES: readonly OrigenCita[] = ['referido', 'cliente', 'lead']
 export const COLUMNA_DE_ORIGEN: Record<OrigenCita, 'referidos' | 'clientes' | 'leads'> = { referido: 'referidos', cliente: 'clientes', lead: 'leads' }
 
-export interface ConversionProyeccion { lead_id: string; perfil_id?: string | null; convertido_en: string }
+export interface ConversionProyeccion {
+  lead_id: string; perfil_id?: string | null; convertido_en: string
+  /** Día comercial de la venta; null (renovación, fuente retirada…): no se vincula a ninguna entrevista. */
+  fecha_comercial?: string | null | undefined
+}
 export interface PersonaProyeccion { lead_id: string; identidad_persona?: string | undefined }
 export interface FuenteProyeccion {
   citas: readonly CitaEjemplo[]
-  /** De la consulta de arriba solo cuentan supervisor, analista y búsqueda. */
-  filtros: Pick<FiltrosCitas, 'q' | 'equipo' | 'analista'>
+  /** Solo el supervisor: los demás filtros de la consulta de arriba no aplican aquí. */
+  filtros: Pick<FiltrosCitas, 'equipo'>
   rango: RangoProyeccion
+  /** Columnas de tiempo; sin ellas («mes»), la hoja no reparte las citas. */
+  tiempo?: TiempoProyeccion | undefined
   /** Instante de la consulta («hoy» de la proyección). */
   corte: string
   tipoCambio?: number | null | undefined
@@ -38,6 +48,8 @@ export interface FuenteProyeccion {
 
 export interface CitaProyectada {
   cita: CitaEjemplo
+  /** Día de Lima en que se creó la cita (la cohorte y los tramos se cortan por él). */
+  creada: string
   /** Identidad de la persona (misma regla que el avance mensual). */
   persona: string
   origen: OrigenCita
@@ -49,17 +61,21 @@ export interface PeriodoProyeccion { desde: string; hasta: string; hoy: string;
 
 export interface MetricasProyeccion {
   citas: CitaProyectada[]; conMonto: CitaProyectada[]; entrevistas: CitaProyectada[]
-  /** Entrevistas de personas que se convirtieron en cliente después (o en el mismo instante). */
+  /** Base de % Entrev., como en Resultados: realizadas + no asistió. */
+  resueltas: CitaProyectada[]
+  /** Entrevistas vinculadas a una venta con la regla de Resultados: fecha comercial no anterior al día de la entrevista. */
   convertidas: CitaProyectada[]
   referidos: CitaProyectada[]; clientes: CitaProyectada[]; leads: CitaProyectada[]
   montoPen: number; montoUsd: number; pendienteTc: boolean
+  /** «Ticket cita»: monto en citas ÷ citas. No es el «Ticket del mes» de Resultados (capital real ÷ clientes). */
   monto: number | null; ticket: number | null
   pctEntrevistas: number | null; pctConversion: number | null
   personasEntrevistadas: number; personasClientes: number
   citasEsperadas: number | null; proyectado: number | null
+  /** Las citas de cada columna de tiempo, en el orden de `HojaProyeccion.tramos`. */
+  porTramo: CitaProyectada[][]
 }
 export interface FilaProyeccion extends MetricasProyeccion { id: string; nombre: string; supervisor: string; supervisorId: string }
-export interface BandaProyeccion { id: string; nombre: string; filas: FilaProyeccion[]; citas: number }
 
 export interface RangoColumna { min?: number | undefined; max?: number | undefined }
 export interface FiltrosColumnas {
@@ -80,8 +96,9 @@ export interface HojaProyeccion {
   cohorte: CitaProyectada[]
   /** Hay citas en dólares con monto: la hoja necesita tipo de cambio. */
   requiereTc: boolean
-  bandas: BandaProyeccion[]
-  /** Filas visibles en el orden de las bandas (la numeración # es continua). */
+  /** Columnas de tiempo (semanas o días); vacío en la vista del mes. */
+  tramos: TramoProyeccion[]
+  /** Una fila por analista, en el orden elegido (la numeración # es continua). */
   filas: FilaProyeccion[]
   /** El proyectado del total SUMA el de cada analista con base; nunca promedia tasas. */
   total: MetricasProyeccion
@@ -102,9 +119,13 @@ const esReferido = (origen: string) => normalizar(origen).replace(/[\s_-]+/g, '
 
 interface Contexto {
   periodo: PeriodoProyeccion | null
+  tramos: TramoProyeccion[]
   tc: number | null
   conocidas: boolean
-  conversionesDe: (persona: string) => readonly number[]
+  /** Conversiones de la persona: el respaldo de «cliente» mira `convertido_en`. */
+  conversionesDe: (persona: string) => readonly ConversionProyeccion[]
+  /** Ventas de la persona hasta el corte, sin recortarlas al mes: la cohorte se sigue hasta hoy. */
+  ventasDe: (persona: string) => readonly ConversionProyeccion[]
 }
 
 function prepararContexto(fuente: FuenteProyeccion) {
@@ -115,42 +136,62 @@ function prepararContexto(fuente: FuenteProyeccion) {
   const identidades = new Map((fuente.poblacion ?? []).map(p => [p.lead_id,
     p.identidad_persona ?? (perfiles.has(p.lead_id) ? `perfil:${perfiles.get(p.lead_id)}` : `lead:${p.lead_id}`)]))
   const persona = (lead: string) => identidades.get(lead) ?? `lead:${lead}`
-  const porPersona = new Map<string, number[]>()
-  for (const c of conversiones) {
-    const instante = Date.parse(c.convertido_en)
-    if (!Number.isFinite(instante)) continue
-    const clave = persona(c.lead_id)
-    porPersona.set(clave, [...(porPersona.get(clave) ?? []), instante])
+  const periodo = periodoProyeccion(fuente.rango, fuente.corte)
+  const corte = Date.parse(fuente.corte)
+  const agrupar = (lista: readonly ConversionProyeccion[]) => {
+    const porPersona = new Map<string, ConversionProyeccion[]>()
+    for (const c of lista) {
+      const clave = persona(c.lead_id)
+      const suyas = porPersona.get(clave)
+      if (suyas) suyas.push(c)
+      else porPersona.set(clave, [c])
+    }
+    return porPersona
   }
+  const porPersona = agrupar(conversiones)
+  // Una venta registrada después del corte aún no existe para la consulta.
+  const ventas = agrupar(conversiones.filter(c => periodo !== null && c.fecha_comercial != null
+    && c.fecha_comercial <= periodo.hoy && Date.parse(c.convertido_en) <= corte))
   const contexto: Contexto = {
-    periodo: periodoProyeccion(fuente.rango, fuente.corte), tc: tcAplicable(fuente.tipoCambio),
-    conocidas: fuente.conversiones !== null, conversionesDe: clave => porPersona.get(clave) ?? [],
+    periodo, tramos: periodo ? tramosDelRango(fuente.rango, fuente.tiempo ?? 'mes', periodo.hoy) : [], tc: tcAplicable(fuente.tipoCambio),
+    conocidas: fuente.conversiones !== null, conversionesDe: clave => porPersona.get(clave) ?? [], ventasDe: clave => ventas.get(clave) ?? [],
   }
   return { contexto, persona }
 }
 
-function proyectar(cita: CitaEjemplo, persona: string, contexto: Contexto): CitaProyectada {
+function proyectar(cita: CitaEjemplo, creada: string, persona: string, contexto: Contexto): CitaProyectada {
   // RESPALDO hasta la Fase 0: mientras el servidor no mande `es_cliente`, una cita
   // es de cliente si su persona ya se había convertido ANTES de crearse la cita.
   // Cuando el campo llegue, manda el servidor y este respaldo deja de usarse.
-  const creada = Date.parse(cita.creadoEn ?? '')
-  const esCliente = cita.esCliente ?? contexto.conversionesDe(persona).some(instante => instante < creada)
+  const instanteCreada = Date.parse(cita.creadoEn ?? '')
+  const esCliente = cita.esCliente ?? contexto.conversionesDe(persona).some(c => Date.parse(c.convertido_en) < instanteCreada)
   const origen: OrigenCita = esCliente ? 'cliente' : esReferido(cita.origen) ? 'referido' : 'lead'
   const enSoles = cita.monto == null ? null : cita.moneda === 'PEN' ? cita.monto
     : contexto.tc === null ? null : usdAPen(cita.monto, contexto.tc)
-  return { cita, persona, origen, enSoles }
+  return { cita, creada, persona, origen, enSoles }
 }
 
 function cohorte(fuente: FuenteProyeccion, persona: (lead: string) => string, contexto: Contexto): CitaProyectada[] {
   const periodo = contexto.periodo
   if (!periodo) return []
-  const { q, equipo, analista } = fuente.filtros
-  return fuente.citas.filter(c => {
-    if (!c.creadoEn || !Number.isFinite(Date.parse(c.creadoEn))) return false
+  const { equipo } = fuente.filtros
+  const lista: CitaProyectada[] = []
+  for (const c of fuente.citas) {
+    if (!c.creadoEn || !Number.isFinite(Date.parse(c.creadoEn)) || (equipo && c.supervisorId !== equipo)) continue
     const creada = fechaLocalCitas(c.creadoEn)
-    return creada >= periodo.desde && creada <= periodo.hasta && coincideBusqueda(c, q)
-      && (!equipo || c.supervisorId === equipo) && (!analista || c.analista === analista)
-  }).map(c => proyectar(c, persona(c.leadId), contexto))
+    if (creada >= periodo.desde && creada <= periodo.hasta) lista.push(proyectar(c, creada, persona(c.leadId), contexto))
+  }
+  return lista
+}
+
+/** Reparte las citas en las columnas de tiempo por su día de creación; las de un rango ya cortado suman la lista entera. */
+export function repartirEnTramos(lista: readonly CitaProyectada[], tramos: readonly RangoProyeccion[]): CitaProyectada[][] {
+  const porTramo = tramos.map(() => [] as CitaProyectada[])
+  for (const c of lista) {
+    const i = tramos.findIndex(t => c.creada >= t.desde && c.creada <= t.hasta)
+    if (i >= 0) porTramo[i]!.push(c)
+  }
+  return porTramo
 }
 
 const suma = (lista: readonly CitaProyectada[], moneda: Moneda) =>
@@ -165,29 +206,30 @@ function medir(lista: CitaProyectada[], contexto: Contexto): MetricasProyeccion
   const monto = pendienteTc ? null : montoPen + (contexto.tc === null ? 0 : usdAPen(montoUsd, contexto.tc))
   const ticket = monto !== null && n ? monto / n : null
   const entrevistas = lista.filter(c => c.cita.estado === 'realizada')
-  // Vínculo entrevista → cliente: la conversión es posterior o igual a la asistencia.
-  const convertidas = entrevistas.filter(c => {
-    const asistio = Date.parse(c.cita.asistioEn ?? '')
-    return Number.isFinite(asistio) && contexto.conversionesDe(c.persona).some(instante => asistio <= instante)
-  })
+  // Como Resultados: las programadas, canceladas o aún sin resultado no son base.
+  const resueltas = lista.filter(c => c.cita.estado === 'realizada' || c.cita.estado === 'no_show')
+  // Vínculo entrevista → cliente: la MISMA regla de Resultados, importada, no copiada.
+  const convertidas = entrevistas.filter(c => contexto.ventasDe(c.persona)
+    .some(v => entrevistaCompatibleConVenta(c.cita.asistioEn, v.fecha_comercial ?? null)))
   const personasEntrevistadas = new Set(entrevistas.map(c => c.persona)).size
   const personasClientes = new Set(convertidas.map(c => c.persona)).size
-  const pctEntrevistas = n ? entrevistas.length / n * 100 : null
+  const pctEntrevistas = resueltas.length ? entrevistas.length / resueltas.length * 100 : null
   const pctConversion = contexto.conocidas && personasEntrevistadas ? personasClientes / personasEntrevistadas * 100 : null
   const periodo = contexto.periodo
-  const hastaHoy = periodo ? lista.filter(c => fechaLocalCitas(c.cita.creadoEn!) <= periodo.hoy).length : n
+  const hastaHoy = periodo ? lista.filter(c => c.creada <= periodo.hoy).length : n
   // Citas esperadas al cierre: el ritmo de los días transcurridos llevado al periodo entero.
   const citasEsperadas = !n || !periodo ? null : periodo.cerrado || !periodo.transcurridos ? n
     : Math.max(n, hastaHoy / periodo.transcurridos * periodo.dias)
-  // Con citas pero sin entrevistas el proyectado es 0 (hay base), no «sin base».
+  // Como Resultados: citas esperadas × tasa de entrevistas × conversión × ticket.
+  // Sin citas resueltas, o sin personas entrevistadas para la conversión, queda «sin base», nunca 0.
   const proyectado = citasEsperadas !== null && pctEntrevistas !== null && pctConversion !== null && ticket !== null
     ? citasEsperadas * (pctEntrevistas / 100) * (pctConversion / 100) * ticket : null
   return {
-    citas: lista, conMonto, entrevistas, convertidas,
+    citas: lista, conMonto, entrevistas, resueltas, convertidas,
     referidos: lista.filter(c => c.origen === 'referido'), clientes: lista.filter(c => c.origen === 'cliente'),
     leads: lista.filter(c => c.origen === 'lead'),
     montoPen, montoUsd, pendienteTc, monto, ticket, pctEntrevistas, pctConversion,
-    personasEntrevistadas, personasClientes, citasEsperadas, proyectado,
+    personasEntrevistadas, personasClientes, citasEsperadas, proyectado, porTramo: repartirEnTramos(lista, contexto.tramos),
   }
 }
 
@@ -243,18 +285,12 @@ export function calcularProyeccion(fuente: FuenteProyeccion, columnas: FiltrosCo
   const filas: FilaProyeccion[] = [...porAnalista.values()].map(lista => {
     const { analista: id, analistaNombre: nombre, supervisor, supervisorId } = lista[0]!.cita
     return { id, nombre, supervisor, supervisorId, ...medir(lista, contexto) }
-  }).filter(f => dentroDeRangos(f, columnas.rangos))
-  const equipos = new Map<string, FilaProyeccion[]>()
-  for (const f of filas) equipos.set(f.supervisorId, [...(equipos.get(f.supervisorId) ?? []), f])
-  const bandas = [...equipos.entries()].map(([id, del]) => ({
-    id, nombre: del[0]!.supervisor, filas: del.sort(comparar(orden)), citas: del.reduce((n, f) => n + f.citas.length, 0),
-  })).sort((a, b) => Number(a.id === 'sin_supervisor') - Number(b.id === 'sin_supervisor') || a.nombre.localeCompare(b.nombre, 'es'))
-  const ordenadas = bandas.flatMap(b => b.filas)
-  const conBase = ordenadas.filter(f => f.proyectado !== null)
-  const total = { ...medir(ordenadas.flatMap(f => f.citas), contexto),
+  }).filter(f => dentroDeRangos(f, columnas.rangos)).sort(comparar(orden))
+  const conBase = filas.filter(f => f.proyectado !== null)
+  const total = { ...medir(filas.flatMap(f => f.citas), contexto),
     proyectado: conBase.length ? conBase.reduce((n, f) => n + f.proyectado!, 0) : null }
   return {
-    periodo: contexto.periodo, tc: contexto.tc, cohorte: base, bandas, filas: ordenadas, total,
+    periodo: contexto.periodo, tc: contexto.tc, cohorte: base, tramos: contexto.tramos, filas, total,
     requiereTc: base.some(c => c.cita.moneda === 'USD' && (c.cita.monto ?? 0) > 0),
   }
 }
@@ -291,12 +327,13 @@ const archivoCsv = (filas: unknown[][]) => '﻿' + filas.map(fila => fila.map(ce
 const redondeo = (valor: number | null, decimales = 2) => valor === null ? '' : Math.round(valor * 10 ** decimales) / 10 ** decimales
 export const ROTULO_ORIGEN: Record<OrigenCita, string> = { referido: 'Referido', cliente: 'Cliente', lead: 'Lead' }
 
+/** En Semanas o Días, una columna por tramo después de «Analista». */
 export function csvProyeccion(hoja: HojaProyeccion, rotulo: string): string {
-  const fila = (f: MetricasProyeccion, equipo: string, analista: string) => [rotulo, equipo, analista, f.citas.length,
+  const fila = (f: MetricasProyeccion, equipo: string, analista: string) => [rotulo, equipo, analista, ...f.porTramo.map(l => l.length), f.citas.length,
     f.pendienteTc ? 'Pendiente de TC' : redondeo(f.monto), redondeo(f.ticket), redondeo(f.pctEntrevistas, 1), redondeo(f.pctConversion, 1),
     redondeo(f.proyectado), f.referidos.length, f.clientes.length, f.leads.length]
   return archivoCsv([
-    ['Periodo', 'Equipo', 'Analista', 'Citas', 'Monto S/', 'Ticket S/', '% Entrev.', '% Conv.', 'Proyectado S/', 'Referidos', 'Clientes', 'Leads'],
+    ['Periodo', 'Equipo', 'Analista', ...hoja.tramos.map(t => t.nombre), 'Citas', 'Monto S/', 'Ticket cita S/', '% Entrev.', '% Conv.', 'Proyectado citas S/', 'Referidos', 'Clientes', 'Leads'],
     ...hoja.filas.map(f => fila(f, f.supervisor, f.nombre)),
     fila(hoja.total, '', `Total · ${hoja.filas.length} analistas`),
   ])
diff --git a/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts b/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts
index bce40ffe..44de49b3 100644
--- a/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts
+++ b/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts
@@ -1,13 +1,18 @@
 import { createContext, type Dispatch, type RefObject, type SetStateAction } from 'react'
 
 import type { ConsultaCitas } from '@/components/citas/datos'
+import type { TiempoProyeccion } from '@/components/citas/proyeccion-rango'
 import type { ConsultaAlertas } from './use-consulta-alertas'
 
 export type TipoRankingGerencia = 'conversion' | 'capital-total' | 'cosecha'
 
 export interface ConsultaGerencia {
   alertas?: ConsultaAlertas
-  citas?: { filtros: ConsultaCitas; vista: 'bandeja' | 'agenda' | 'resultados' | 'proyeccion'; pagina: number; rango?: { mes: string; desde: string; hasta: string } }
+  citas?: {
+    filtros: ConsultaCitas; vista: 'bandeja' | 'agenda' | 'resultados' | 'proyeccion'; pagina: number
+    /** Rango de la Proyección y sus columnas de tiempo (Mes · Semanas · Días). */
+    rango?: { mes: string; desde: string; hasta: string; tiempo?: TiempoProyeccion }
+  }
   gestionAnalista: { id: string; nombre: string } | null
   administrarMetasPeriodo: string | null
   rendimientoEquipo: string | null
diff --git a/CRM-Avance-Corp/app/src/lib/enlace-citas.ts b/CRM-Avance-Corp/app/src/lib/enlace-citas.ts
index 52584030..b0a07de8 100644
--- a/CRM-Avance-Corp/app/src/lib/enlace-citas.ts
+++ b/CRM-Avance-Corp/app/src/lib/enlace-citas.ts
@@ -1,10 +1,25 @@
+/** Cómo se lee el rango de la Proyección: por semanas o por días. */
+export type VistaProyeccionEnlace = 'semanas' | 'dias'
+
 /** Contexto de lectura del Resumen; nunca concede permisos sobre un equipo. */
 export type ConsultaCitasEnlace = (
-  | { dia: string; mes?: never; semana?: never }
-  | { mes: string; dia?: never; semana?: string }
+  | { dia: string; mes?: never; semana?: never; desde?: never; hasta?: never; vista?: never }
+  | { mes: string; dia?: never; semana?: string; desde?: never; hasta?: never; vista?: never }
+  | { desde: string; hasta: string; vista?: VistaProyeccionEnlace; dia?: never; mes?: never; semana?: never }
 ) & { equipo?: string }
 
+/** El rango de la Proyección; el tope de meses lo aplica la pantalla, no el enlace. */
+export type ConsultaProyeccionEnlace = Extract<ConsultaCitasEnlace, { desde: string }>
+
+const VISTAS_PROYECCION: readonly string[] = ['semanas', 'dias'] satisfies VistaProyeccionEnlace[]
+const EQUIPO_CITAS = /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|d-[a-z0-9-]{1,60}|sin_supervisor)$/i
+
+export function esConsultaProyeccion(consulta: ConsultaCitasEnlace | undefined): consulta is ConsultaProyeccionEnlace {
+  return consulta?.desde !== undefined
+}
+
 export function mesConsultaCitas(consulta: ConsultaCitasEnlace): string {
+  if (esConsultaProyeccion(consulta)) return consulta.hasta.slice(0, 7)
   return consulta.dia ? consulta.dia.slice(0, 7) : consulta.mes!
 }
 
@@ -15,9 +30,14 @@ export function diaCitasValido(dia: string): boolean {
 }
 
 export function consultaCitasValida(consulta: ConsultaCitasEnlace | undefined): consulta is ConsultaCitasEnlace {
-  const periodoValido = consulta?.dia ? diaCitasValido(consulta.dia)
-    : !!consulta?.mes && /^\d{4}-(0[1-9]|1[0-2])$/.test(consulta.mes)
-      && (consulta.semana === undefined || /^[1-4]$/.test(consulta.semana))
-  return !!consulta && periodoValido && (consulta.equipo === undefined
-    || /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|d-[a-z0-9-]{1,60}|sin_supervisor)$/i.test(consulta.equipo))
+  if (!consulta) return false
+  // Una variante nunca arrastra campos de otra: el enlace solo significa una cosa.
+  const periodoValido = esConsultaProyeccion(consulta)
+    ? consulta.dia === undefined && consulta.mes === undefined && consulta.semana === undefined
+      && diaCitasValido(consulta.desde) && diaCitasValido(consulta.hasta) && consulta.desde <= consulta.hasta
+      && (consulta.vista === undefined || VISTAS_PROYECCION.includes(consulta.vista))
+    : consulta.hasta === undefined && consulta.vista === undefined && (consulta.dia ? diaCitasValido(consulta.dia)
+      : !!consulta.mes && /^\d{4}-(0[1-9]|1[0-2])$/.test(consulta.mes)
+        && (consulta.semana === undefined || /^[1-4]$/.test(consulta.semana)))
+  return periodoValido && (consulta.equipo === undefined || EQUIPO_CITAS.test(consulta.equipo))
 }
diff --git a/CRM-Avance-Corp/app/src/lib/router.ts b/CRM-Avance-Corp/app/src/lib/router.ts
index a91e55be..c9a5397e 100644
--- a/CRM-Avance-Corp/app/src/lib/router.ts
+++ b/CRM-Avance-Corp/app/src/lib/router.ts
@@ -8,7 +8,7 @@
 
 // 'repartir' (C1, 2026-07-22) NO entra en VISTAS_LEADS a propósito: el gate de
 // leads está cerrado para el coordinador y ocultaría la única pantalla que debe ver.
-import { consultaCitasValida, type ConsultaCitasEnlace } from './enlace-citas'
+import { consultaCitasValida, esConsultaProyeccion, type ConsultaCitasEnlace, type VistaProyeccionEnlace } from './enlace-citas'
 
 export const VISTAS = [
   'hoy',
@@ -192,7 +192,8 @@ function detalleGestionValido(detalle: DetalleGestion | undefined): detalle is D
 
 export function hashDe(vista: Vista, leadId?: string | null, inversionistaId?: string, solicitudTasaId?: string, detalleGestion?: DetalleGestion, llamadaNumero?: string, consultaCitas?: ConsultaCitasEnlace, llamadaOrigenId?: string): string {
   if (vista === 'reuniones' && consultaCitasValida(consultaCitas)) {
-    const periodo = consultaCitas.dia ? `dia/${consultaCitas.dia}` : `mes/${consultaCitas.mes}${consultaCitas.semana ? `/semana/${consultaCitas.semana}` : ''}`
+    const periodo = esConsultaProyeccion(consultaCitas) ? `proyeccion/${consultaCitas.desde}/${consultaCitas.hasta}${consultaCitas.vista ? `/${consultaCitas.vista}` : ''}`
+      : consultaCitas.dia ? `dia/${consultaCitas.dia}` : `mes/${consultaCitas.mes}${consultaCitas.semana ? `/semana/${consultaCitas.semana}` : ''}`
     return `#/reuniones/${periodo}${consultaCitas.equipo ? `/equipo/${consultaCitas.equipo}` : ''}${leadId ? `/lead/${encodeURIComponent(leadId)}` : ''}`
   }
   if (vista === 'gestion-diaria' && detalleGestionValido(detalleGestion)) {
@@ -216,11 +217,18 @@ export function leerHash(): RutaHash {
   const crudo = window.location.hash.replace(/^#\/?/, '')
   const partes = crudo.split('/').filter(Boolean)
   const vista = resolverVista(partes[0])
-  const indiceEquipo = partes[1] === 'mes' && partes[3] === 'semana' ? 5 : 3
+  // Proyección: «proyeccion/<desde>/<hasta>[/<vista>]»; lo que ocupe el lugar de la vista y no sea
+  // «equipo» ni «lead» se toma como vista y la validación lo descarta si no lo es.
+  const vistaProyeccion = partes[1] === 'proyeccion' && partes[4] !== 'equipo' && partes[4] !== 'lead' ? partes[4] : undefined
+  const indiceEquipo = partes[1] === 'proyeccion' ? (vistaProyeccion === undefined ? 4 : 5)
+    : partes[1] === 'mes' && partes[3] === 'semana' ? 5 : 3
   const equipoCitas = partes[indiceEquipo] === 'equipo' ? { equipo: partes[indiceEquipo + 1] ?? '' } : {}
   const candidataCitas = vista === 'reuniones' && partes[2]
     ? partes[1] === 'dia' ? { dia: partes[2], ...equipoCitas }
-      : partes[1] === 'mes' ? { mes: partes[2], ...(partes[3] === 'semana' ? { semana: partes[4] ?? '' } : {}), ...equipoCitas } : undefined
+      : partes[1] === 'mes' ? { mes: partes[2], ...(partes[3] === 'semana' ? { semana: partes[4] ?? '' } : {}), ...equipoCitas }
+      : partes[1] === 'proyeccion' ? { desde: partes[2], hasta: partes[3] ?? '',
+        ...(vistaProyeccion === undefined ? {} : { vista: vistaProyeccion as VistaProyeccionEnlace }), ...equipoCitas }
+      : undefined
     : undefined
   const consultaCitas = consultaCitasValida(candidataCitas) ? candidataCitas : undefined
   let leadId: string | null = null
```

## Diff (pruebas y e2e)
```diff
diff --git a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
index 54afdfd7..138aecec 100644
--- a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
@@ -66,14 +66,24 @@ async function abrirProyeccion(page: Page) {
   await page.getByRole('tab', { name: 'Proyección' }).click()
   return page.getByRole('table', { name: /Proyección de citas por analista/ })
 }
+const atajo = (page: Page, nombre: string) => page.getByRole('group', { name: 'Atajos de periodo' }).getByRole('button', { name: nombre, exact: true })
+const tiempo = (page: Page, nombre: 'Mes' | 'Semanas' | 'Días') => page.getByRole('group', { name: 'Columnas de tiempo' }).getByRole('button', { name: nombre, exact: true })
 
 test('Proyección: la hoja pinta una fila por analista, un número abre su lista y un embudo filtra', async ({ page }, info) => {
   await page.setViewportSize({ width: 1440, height: 1000 })
   const hoja = await abrirProyeccion(page)
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
-  await expect(hoja.getByRole('button', { name: /^Equipo SUPERVISORA NORTE/ })).toContainText('2 analistas · 5 citas')
+  // Hoja plana: sin bandas por equipo ni pastillas de totales, # continuo; los filtros de arriba no se pintan.
+  await expect(hoja.getByRole('button', { name: /^Equipo / })).toHaveCount(0)
+  await expect(page.getByRole('group', { name: 'Totales de la proyección' })).toHaveCount(0)
+  await expect(hoja.locator('tr.pc-fila td.pc-n0')).toHaveText(['1', '2', '3'])
+  await expect(page.getByRole('region', { name: 'Consulta de citas' })).toHaveCount(0)
+  await expect(page.getByRole('button', { name: 'Exportar citas' })).toHaveCount(0)
   await expect(hoja.getByRole('row', { name: /^Total · 3 analistas/ })).toBeVisible()
-  // Sin desplazamiento horizontal a 1440 px en la vista del mes.
+  // Nombres propios: Resultados ya usa «Ticket del mes» y «Cierre proyectado» para otras cifras.
+  await expect(hoja.locator('thead th[data-col]')).toHaveText(['Analista', 'Citas', 'Monto S/', 'Ticket cita S/', '% Entrev.', '% Conv.',
+    'Proyectado citas S/', 'Referidos', 'Clientes', 'Leads'])
+  // Sin desplazamiento horizontal a 1440 px en la vista del mes, aun con esos dos nombres largos.
   const scroll = page.getByRole('region', { name: 'Hoja de proyección por analista' })
   const anchos = await hoja.locator('thead th').evaluateAll(ths => ths.map(th => `${th.textContent}:${Math.round(th.getBoundingClientRect().width)}`).join(' · '))
   expect(await scroll.evaluate(el => el.scrollWidth - el.clientWidth), anchos).toBeLessThanOrEqual(0)
@@ -114,23 +124,91 @@ test('Proyección: la hoja pinta una fila por analista, un número abre su lista
   await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('25 set – 19 oct 2026')
   await expect(hoja.getByRole('button', { name: '5 citas de ANALISTA UNO' })).toBeVisible()
   await expect(hoja.getByRole('button', { name: '3 citas de ANALISTA TRES' })).toBeVisible()
-  await page.getByRole('button', { name: 'S3' }).click()
+  await atajo(page, 'S3').click()
   await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('15–21 oct 2026')
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(2)
+  // El Supervisor de la barra acota la hoja.
+  await page.getByRole('group', { name: 'Consulta de la proyección' }).getByLabel('Supervisor').selectOption({ label: 'SUPERVISOR SUR' })
+  await expect(hoja.locator('tr.pc-fila')).toHaveCount(1)
+  await expect(hoja.getByRole('row', { name: /ANALISTA TRES/ })).toBeVisible()
+})
+
+test('Proyección: Semanas y Días ponen columnas de tiempo antes de Citas y cada número abre su lista', async ({ page }, info) => {
+  await page.setViewportSize({ width: 1440, height: 1000 })
+  const hoja = await abrirProyeccion(page)
+  const uno = hoja.getByRole('row', { name: /ANALISTA UNO/ })
+  // ANALISTA UNO, 1–19 oct: tres citas creadas el 2, 3 y 4 (S1) y una el 12 (S2).
+  await tiempo(page, 'Semanas').click()
+  await expect(tiempo(page, 'Semanas')).toHaveAttribute('aria-pressed', 'true')
+  await expect(hoja.locator('thead th.pc-tiempo .sr-only')).toHaveText(['S1 1–7 oct', 'S2 8–14 oct', 'S3 15–19 oct'])
+  await expect(hoja.locator('thead th.pc-tcierre')).toContainText('Citas')
+  expect(await uno.locator('td').evaluateAll(celdas => celdas.slice(0, 5).map(td => td.textContent))).toEqual(['1', '3', '1', '0', '4'])
+  const sumas = await hoja.locator('tbody tr, tfoot tr').evaluateAll(filas => filas.map(tr => {
+    const n = [...tr.querySelectorAll('td')].map(td => Number(td.textContent))
+    return n[1]! + n[2]! + n[3]! - n[4]!
+  }))
+  expect(sumas).toEqual([0, 0, 0, 0])
+  await page.screenshot({ path: info.outputPath('proyeccion-semanas-1440.png'), fullPage: true })
+  await uno.getByRole('button', { name: '3 citas de ANALISTA UNO, S1 1–7 oct' }).click()
+  const semana = page.getByRole('dialog', { name: 'Citas · S1 1–7 oct · ANALISTA UNO' })
+  await expect(semana.getByTestId('pc-detalle-conteo')).toHaveText('1–7 oct 2026 · 3 citas')
+  await expect(semana.locator('tbody tr')).toHaveCount(3)
+  await page.keyboard.press('Escape')
+  await expect(semana).toHaveCount(0)
+  // Un mes completo en Semanas (4 semanas) y un rango de un mes que cruza dos (5) caben a 1440 px sin desplazar la hoja.
+  const scroll = page.getByRole('region', { name: 'Hoja de proyección por analista' })
+  for (const [desde, hasta, semanas] of [['2026-10-01', '2026-10-31', 4], ['2026-09-20', '2026-10-20', 5]] as const) {
+    await page.getByLabel('Desde', { exact: true }).fill(desde)
+    await page.getByLabel('Hasta', { exact: true }).fill(hasta)
+    await expect(hoja.locator('thead th.pc-tiempo')).toHaveCount(semanas)
+    const anchos = await hoja.locator('thead th').evaluateAll(ths => ths.map(th => `${th.textContent}:${Math.round(th.getBoundingClientRect().width)}`).join(' · '))
+    expect(await scroll.evaluate(el => el.scrollWidth - el.clientWidth), `${desde} → ${hasta}: ${anchos}`).toBeLessThanOrEqual(0)
+    await page.screenshot({ path: info.outputPath(`proyeccion-semanas-${semanas}-1440.png`), fullPage: true })
+  }
+  await atajo(page, 'Mes').click()
+  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–19 oct 2026')
+
+  await tiempo(page, 'Días').click()
+  await expect(hoja.locator('thead th.pc-tiempo')).toHaveCount(19)
+  await expect(hoja.locator('thead th.pc-hoy .sr-only')).toHaveText('lun 19 oct')
+  await expect(hoja.locator('thead th.pc-domingo')).toHaveCount(3)
+  // La hoja se desplaza dentro de su contenedor, nunca la página; # y Analista quedan fijos.
+  expect(await scroll.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true)
+  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
+  const nombre = uno.getByRole('rowheader')
+  const antes = await nombre.boundingBox()
+  await scroll.evaluate(el => { el.scrollLeft = el.scrollWidth })
+  expect((await nombre.boundingBox())?.x).toBe(antes?.x)
+  await scroll.evaluate(el => { el.scrollLeft = 0 })
+  await page.screenshot({ path: info.outputPath('proyeccion-dias-1440.png'), fullPage: true })
+  await uno.getByRole('button', { name: '1 cita de ANALISTA UNO, 2 oct' }).click()
+  const dia = page.getByRole('dialog', { name: 'Citas · 2 oct · ANALISTA UNO' })
+  await expect(dia.getByTestId('pc-detalle-conteo')).toHaveText('2 oct 2026 · 1 cita')
+  await expect(dia.locator('tbody tr')).toHaveCount(1)
+  await page.keyboard.press('Escape')
+  await expect(dia).toHaveCount(0)
+  // Con más de 31 días, «Días» se deshabilita y la hoja cae a semanas.
+  await page.getByLabel('Desde', { exact: true }).fill('2026-09-01')
+  await expect(tiempo(page, 'Días')).toBeDisabled()
+  await expect(tiempo(page, 'Semanas')).toHaveAttribute('aria-pressed', 'true')
+  await expect(hoja.locator('thead th.pc-tiempo .sr-only').first()).toHaveText('S1 1–7 set')
 })
 
 test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el celular solo desplaza la hoja', async ({ page }, info) => {
   await page.setViewportSize({ width: 1440, height: 1000 })
   const hoja = await abrirProyeccion(page)
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
-  await page.getByLabel('Mes').fill('2026-08')
+  // Los filtros de arriba no se pintan en Proyección: el periodo se elige en su barra.
+  await page.getByLabel('Desde', { exact: true }).fill('2026-08-01')
+  await page.getByLabel('Hasta', { exact: true }).fill('2026-08-31')
   await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–31 ago 2026')
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(0)
   await expect(hoja.getByRole('row', { name: /^Total · 0 analistas/ })).toBeVisible()
   await expect(page.getByRole('button', { name: 'Exportar CSV' })).toBeDisabled()
   await expect(page.getByRole('alert')).toHaveCount(0)
   await expect(page.getByText('No hay citas con esta combinación')).toHaveCount(0)
-  await page.getByRole('button', { name: 'Quitar Mes: 2026-08' }).click()
+  await atajo(page, 'Mes').click()
+  await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–19 oct 2026')
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
   await page.setViewportSize({ width: 390, height: 844 })
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
index 6cde3882..3a4462c7 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
@@ -1,5 +1,5 @@
 import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
-import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
+import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
 import userEvent from '@testing-library/user-event'
 import { controlCitasInicial } from '@/lib/control-citas'
 import { ContextoCitas, type DatosCitas } from './contexto'
@@ -51,15 +51,22 @@ async function abrirProyeccion(cambios: Partial<DatosCitas> = {}) {
   return { usuario, vista, hoja: screen.getByRole('table', { name: /Proyección de citas por analista/ }) }
 }
 const fila = (hoja: HTMLElement, nombre: string) => within(hoja).getByRole('row', { name: new RegExp(`^\\d+ ${nombre}`) })
+const filaTotal = (hoja: HTMLElement) => within(hoja).getByRole('row', { name: /^Total · / })
+const nombres = (hoja: HTMLElement) => [...hoja.querySelectorAll('tr.pc-fila th')].map(th => th.textContent)
+const tiempo = (nombre: 'Mes' | 'Semanas' | 'Días') => within(screen.getByRole('group', { name: 'Columnas de tiempo' })).getByRole('button', { name: nombre })
+const atajo = (nombre: string) => within(screen.getByRole('group', { name: 'Atajos de periodo' })).getByRole('button', { name: nombre })
+/** Cabeceras de las columnas de tiempo tal como se ven (título y detalle). */
+const cabecerasTiempo = (hoja: HTMLElement) => [...hoja.querySelectorAll('thead th.pc-tiempo .pc-tiempo-cab')].map(e => `${e.firstChild?.textContent} ${e.querySelector('small')?.textContent}`)
 
 describe('Pestaña Proyección de Citas', () => {
-  it('pinta una fila por analista en su equipo; toda cifra es botón, salvo los ceros y los derivados', async () => {
+  it('pinta una hoja plana, una fila por analista y # continuo; toda cifra es botón, salvo los ceros y los derivados', async () => {
     const { hoja } = await abrirProyeccion()
     expect(screen.getByRole('tab', { name: 'Proyección' })).toHaveAttribute('aria-selected', 'true')
-    expect(within(hoja).getAllByRole('button', { name: /^(Equipo|Sin supervisor)/ }).map(b => b.textContent)).toEqual([
-      'Equipo Claudia Ríos· 2 analistas · 5 citas', 'Equipo Javier Vega· 1 analista · 2 citas',
-    ])
+    // Sin bandas por equipo ni pastillas de totales: la fila Σ da los totales.
+    expect(within(hoja).queryByRole('button', { name: /^(Equipo|Sin supervisor)/ })).not.toBeInTheDocument()
+    expect(screen.queryByRole('group', { name: 'Totales de la proyección' })).not.toBeInTheDocument()
     expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(3)
+    expect([...hoja.querySelectorAll('tr.pc-fila td.pc-n0')].map(td => td.textContent)).toEqual(['1', '2', '3'])
     // Columnas: # · Citas · Monto · Ticket · % Entrev. · % Conv. · Proyectado · Referidos · Clientes · Leads
     const DERIVADAS = [3, 6]
     for (const tr of hoja.querySelectorAll<HTMLTableRowElement>('tr.pc-fila')) {
@@ -76,7 +83,9 @@ describe('Pestaña Proyección de Citas', () => {
     const ana = fila(hoja, 'Ana Torres')
     expect(within(ana).getByRole('button', { name: '4 citas de Ana Torres' })).toBeVisible()
     expect(within(ana).getByRole('button', { name: 'S/ 37,500 en citas de Ana Torres' })).toBeVisible()
-    expect(within(ana).getByRole('button', { name: /^% Entrev\. de Ana Torres: 50%/ })).toBeVisible()
+    // % Entrev. como Resultados: 2 realizadas ÷ 3 resueltas (la programada a4 no es base).
+    expect(within(ana).getByRole('button', { name: /^% Entrev\. de Ana Torres: 66\.7%/ })).toBeVisible()
+    expect(within(fila(hoja, 'Luis Vega')).getAllByRole('cell')[4]).toHaveTextContent('— · Sin base para evaluar')
     expect(within(ana).getAllByRole('cell')[3]).toHaveTextContent('S/9,375')
     expect(within(ana).queryByRole('button', { name: /con clientes/ })).not.toBeInTheDocument()
     const total = within(hoja).getByRole('row', { name: /^Total · 3 analistas/ })
@@ -93,7 +102,7 @@ describe('Pestaña Proyección de Citas', () => {
     expect(within(lista).getByRole('row', { name: /Persona a2/ })).toHaveTextContent('US$ 2,000 ·S/ 7,500')
     expect(within(lista).getByRole('button', { name: 'Exportar CSV' })).toBeEnabled()
     await usuario.click(within(lista).getByRole('button', { name: 'Cerrar lista' }))
-    await usuario.click(screen.getByRole('button', { name: 'Clientes: 1, ver la lista' }))
+    await usuario.click(within(filaTotal(hoja)).getByRole('button', { name: '1 cita con cliente de todos los analistas' }))
     lista = screen.getByRole('dialog', { name: 'Citas con clientes · Total' })
     expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('· 1 cita')
     expect(within(lista).getByRole('columnheader', { name: 'Analista' })).toBeVisible()
@@ -162,19 +171,16 @@ describe('Pestaña Proyección de Citas', () => {
     expect(screen.getByRole('group', { name: 'Filtros de columna' })).toHaveTextContent('Monto S/ Solo dólares')
   })
 
-  it('ordena con la cabecera y con el embudo', async () => {
+  it('ordena con la cabecera y con el embudo, en un orden global que mezcla equipos', async () => {
     const { usuario, hoja } = await abrirProyeccion()
-    const nombres = () => [...hoja.querySelectorAll('tr.pc-fila th')].map(th => th.textContent)
-    expect(nombres()).toEqual(['ATAna Torres', 'LVLuis Vega', 'DSDiego Salas'])
+    expect(nombres(hoja)).toEqual(['ATAna Torres', 'DSDiego Salas', 'LVLuis Vega'])
     await usuario.click(within(hoja).getByRole('button', { name: 'Citas' }))
     expect(within(hoja).getByRole('columnheader', { name: /Citas/ })).toHaveAttribute('aria-sort', 'ascending')
-    expect(nombres()).toEqual(['LVLuis Vega', 'ATAna Torres', 'DSDiego Salas'])
-    await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Ticket S/' }))
+    expect(nombres(hoja)).toEqual(['LVLuis Vega', 'DSDiego Salas', 'ATAna Torres'])
+    await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Ticket cita S/' }))
     await usuario.click(screen.getByRole('button', { name: 'Ordenar de mayor a menor' }))
-    expect(nombres()).toEqual(['ATAna Torres', 'LVLuis Vega', 'DSDiego Salas'])
-    await usuario.click(within(hoja).getByRole('button', { name: /^Equipo Claudia Ríos/ }))
-    expect(nombres()).toEqual(['DSDiego Salas'])
-    expect(within(hoja).getByText('3')).toHaveClass('pc-n0')
+    expect(nombres(hoja)).toEqual(['DSDiego Salas', 'ATAna Torres', 'LVLuis Vega'])
+    expect([...hoja.querySelectorAll('tr.pc-fila td.pc-n0')].map(td => td.textContent)).toEqual(['1', '2', '3'])
   })
 
   it('sin tipo de cambio: el monto con dólares queda pendiente y se puede reintentar', async () => {
@@ -182,7 +188,7 @@ describe('Pestaña Proyección de Citas', () => {
     const { usuario, hoja } = await abrirProyeccion()
     expect(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: 'Pendiente de TC en citas de Ana Torres' })).toBeVisible()
     expect(within(fila(hoja, 'Ana Torres')).getAllByRole('cell')[3]).toHaveTextContent('—')
-    expect(screen.getByRole('button', { name: 'Monto: Pendiente de TC, ver la lista' })).toBeVisible()
+    expect(within(filaTotal(hoja)).getByRole('button', { name: 'Pendiente de TC en citas de todos los analistas' })).toBeVisible()
     await usuario.click(screen.getByRole('button', { name: 'Reintentar TC' }))
     expect(cotizacion.recargar).toHaveBeenCalledTimes(1)
   })
@@ -205,8 +211,8 @@ describe('Pestaña Proyección de Citas', () => {
       expect(click).toHaveBeenCalledOnce()
       const csvHoja = (await leer(blobs[0]!)).split('\r\n')
       expect(csvHoja).toHaveLength(5)
-      expect(csvHoja[0]).toContain('"Ticket S/","% Entrev.","% Conv.","Proyectado S/","Referidos","Clientes","Leads"')
-      expect(csvHoja[1]).toMatch(/^"1–19 oct 2026","Claudia Ríos","Ana Torres","4","37500","9375","50","50",/)
+      expect(csvHoja[0]).toContain('"Ticket cita S/","% Entrev.","% Conv.","Proyectado citas S/","Referidos","Clientes","Leads"')
+      expect(csvHoja[1]).toMatch(/^"1–19 oct 2026","Claudia Ríos","Ana Torres","4","37500","9375","66.7","50",/)
       expect(screen.getByText('Se descargó la proyección de 3 analistas.')).toBeVisible()
       await usuario.click(within(hoja).getByRole('button', { name: '4 citas de Ana Torres' }))
       const lista = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
@@ -227,10 +233,10 @@ describe('Pestaña Proyección de Citas', () => {
   it('el rango nace del mes de arriba hasta hoy; los atajos y las fechas lo cambian y se valida', async () => {
     const { usuario, hoja } = await abrirProyeccion()
     expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–19 oct 2026')
-    expect(screen.getByRole('button', { name: 'Mes' })).toHaveAttribute('aria-pressed', 'true')
-    await usuario.click(screen.getByRole('button', { name: 'S3' }))
+    expect(atajo('Mes')).toHaveAttribute('aria-pressed', 'true')
+    await usuario.click(atajo('S3'))
     expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('15–21 oct 2026')
-    expect([...hoja.querySelectorAll('tr.pc-fila th')].map(th => th.textContent)).toEqual(['LVLuis Vega', 'DSDiego Salas'])
+    expect(nombres(hoja)).toEqual(['DSDiego Salas', 'LVLuis Vega'])
     expect(screen.getByLabelText('Desde')).toHaveValue('2026-10-15')
     // Un rango al revés no se aplica: se avisa y la hoja conserva el último válido.
     fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-10-25' } })
@@ -245,7 +251,7 @@ describe('Pestaña Proyección de Citas', () => {
     expect(screen.getByLabelText('Semana')).toHaveValue('')
     await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
     expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('3–21 oct 2026')
-    await usuario.click(screen.getByRole('button', { name: 'Mes pasado' }))
+    await usuario.click(atajo('Mes pasado'))
     expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–30 set 2026')
     expect(screen.getByRole('table', { name: /Proyección de citas por analista/ }).querySelectorAll('tr.pc-fila')).toHaveLength(0)
   })
@@ -292,14 +298,161 @@ describe('Pestaña Proyección de Citas', () => {
     const { hoja } = await abrirProyeccion({ citas: [], gestion: gestion([]) })
     expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(0)
     expect(within(hoja).getAllByRole('columnheader').map(th => th.textContent)).toEqual([
-      '#Número', 'Analista', 'Citas', 'Monto S/', 'Ticket S/', '% Entrev.', '% Conv.', 'Proyectado S/', 'Referidos', 'Clientes', 'Leads',
+      '#Número', 'Analista', 'Citas', 'Monto S/', 'Ticket cita S/', '% Entrev.', '% Conv.', 'Proyectado citas S/', 'Referidos', 'Clientes', 'Leads',
     ])
     expect(within(hoja).getByRole('row', { name: /^Total · 0 analistas/ })).toBeVisible()
     expect(within(hoja).queryAllByRole('button', { name: /de todos los analistas/ })).toEqual([])
-    expect(screen.getByRole('group', { name: 'Totales de la proyección' })).toHaveTextContent(/^Citas:0Monto:S\/ 0Ticket:—Entrevistas:—Conversión:—Proyectado:—Referidos:0Clientes:0Leads:0Analistas:0TC:—$/)
-    expect(screen.queryByRole('button', { name: /^Citas: / })).not.toBeInTheDocument()
+    expect(within(filaTotal(hoja)).getAllByRole('cell').map(td => td.textContent)).toEqual(['Σ', '0', '—', '—', '— · Sin base para evaluar', '— · Sin base para evaluar', '—', '0', '0', '0'])
+    expect(screen.queryByRole('group', { name: 'Totales de la proyección' })).not.toBeInTheDocument()
     expect(screen.getByRole('button', { name: 'Exportar CSV' })).toBeDisabled()
+    // Sin citas, las columnas de tiempo también se pintan, en cero y sin botones.
+    await userEvent.setup().click(tiempo('Semanas'))
+    expect(cabecerasTiempo(hoja)).toEqual(['S1 1–7', 'S2 8–14', 'S3 15–19'])
+    expect(within(filaTotal(hoja)).getAllByRole('cell').slice(1, 4).map(td => td.textContent)).toEqual(['0', '0', '0'])
     expect(screen.queryByRole('alert')).not.toBeInTheDocument()
     expect(screen.queryByText('No hay citas con esta combinación')).not.toBeInTheDocument()
   })
+  it('en Proyección no se pintan los filtros de arriba: el Supervisor vive en su barra y el analista o un error de arriba no aplican', async () => {
+    const usuario = userEvent.setup()
+    render(<ContextoCitas value={fuente}><TableroCitas /></ContextoCitas>)
+    // Arriba: Luis como analista y un monto imposible (error de filtros).
+    fireEvent.change(screen.getByLabelText('Analista'), { target: { value: 'luis' } })
+    await usuario.click(screen.getByRole('button', { name: /^Más filtros/ }))
+    fireEvent.change(screen.getByLabelText(/^Moneda del monto estimado/), { target: { value: 'PEN' } })
+    fireEvent.change(screen.getByLabelText('Monto desde'), { target: { value: '10' } })
+    fireEvent.change(screen.getByLabelText('Monto hasta'), { target: { value: '5' } })
+    expect(screen.getAllByText('El monto mínimo debe ser menor o igual al máximo.')[0]).toBeVisible()
+    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
+    expect(screen.queryByRole('region', { name: 'Consulta de citas' })).not.toBeInTheDocument()
+    expect(screen.queryByRole('button', { name: /Exportar citas/ })).not.toBeInTheDocument()
+    expect(document.querySelector('.citas-corte')!.textContent).toMatch(/^Seguimiento al /)
+    const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
+    expect(nombres(hoja)).toEqual(['ATAna Torres', 'DSDiego Salas', 'LVLuis Vega'])
+    expect(screen.queryByText('Revisa los filtros de la consulta')).not.toBeInTheDocument()
+    // Barra única: Supervisor · rango · atajos · columnas de tiempo · Exportar CSV.
+    const barra = screen.getByRole('group', { name: 'Consulta de la proyección' })
+    expect([...barra.querySelectorAll('label, strong, [role=group], .pc-acciones')].map(e => e.getAttribute('aria-label') ?? e.textContent!.slice(0, 10)))
+      .toEqual(['Supervisor', '1–19 oct 2', 'Desde', 'Hasta', 'Atajos de periodo', 'Columnas de tiempo', 'Exportar C'])
+    const supervisor = within(barra).getByLabelText('Supervisor')
+    expect([...supervisor.querySelectorAll('option')].map(o => o.textContent)).toEqual(['Todos', 'Claudia Ríos', 'Javier Vega'])
+    await usuario.selectOptions(supervisor, 'sup-2')
+    expect(nombres(hoja)).toEqual(['DSDiego Salas'])
+    // Es el mismo supervisor de las otras pestañas; Luis no es de ese equipo y sale del filtro de analista.
+    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
+    expect(screen.getByLabelText('Supervisor')).toHaveValue('sup-2')
+    expect(screen.getByLabelText('Analista')).toHaveValue('')
+  })
+
+  it('Semanas: columnas S1–S3 justo antes de Citas; cada número abre su lista y los tramos suman la columna Citas', async () => {
+    const { usuario, hoja } = await abrirProyeccion()
+    expect(tiempo('Mes')).toHaveAttribute('aria-pressed', 'true')
+    expect(hoja.querySelectorAll('th.pc-tiempo')).toHaveLength(0)
+    await usuario.click(tiempo('Semanas'))
+    expect(tiempo('Semanas')).toHaveAttribute('aria-pressed', 'true')
+    expect(cabecerasTiempo(hoja)).toEqual(['S1 1–7', 'S2 8–14', 'S3 15–19'])
+    expect(within(hoja).getByRole('columnheader', { name: 'S2 8–14 oct' })).toBeVisible()
+    const cabeceras = [...hoja.querySelectorAll('thead th')]
+    expect(cabeceras[1]).toHaveTextContent('Analista')
+    expect(cabeceras[5]).toHaveClass('pc-tcierre')
+    expect(cabeceras[5]).toHaveTextContent('Citas')
+    // Sin embudo ni orden en las columnas de tiempo.
+    expect(within(hoja).queryByRole('button', { name: /^Filtrar S\d/ })).not.toBeInTheDocument()
+    const ana = fila(hoja, 'Ana Torres')
+    expect(within(ana).getAllByRole('cell').slice(1, 5).map(td => td.textContent)).toEqual(['3', '1', '0', '4'])
+    expect(within(ana).queryByRole('button', { name: /S3 15–19 oct/ })).not.toBeInTheDocument()
+    for (const tr of [...hoja.querySelectorAll<HTMLTableRowElement>('tbody tr, tfoot tr')]) {
+      const [, s1, s2, s3, citas] = within(tr).getAllByRole('cell').map(td => Number(td.textContent))
+      expect(s1! + s2! + s3!, tr.textContent!).toBe(citas)
+    }
+    await usuario.click(within(ana).getByRole('button', { name: '1 cita de Ana Torres, S2 8–14 oct' }))
+    let lista = screen.getByRole('dialog', { name: 'Citas · S2 8–14 oct · Ana Torres' })
+    expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('8–14 oct 2026 · 1 cita')
+    expect(within(lista).getByRole('row', { name: /Persona a4/ })).toBeVisible()
+    await usuario.keyboard('{Escape}')
+    await usuario.click(within(filaTotal(hoja)).getByRole('button', { name: '2 citas de todos los analistas, S3 15–19 oct' }))
+    lista = screen.getByRole('dialog', { name: 'Citas · S3 15–19 oct · Total' })
+    expect(within(lista).getByRole('columnheader', { name: 'Analista' })).toBeVisible()
+    expect(within(lista).getAllByRole('row')).toHaveLength(3)
+    await usuario.keyboard('{Escape}')
+    // Un rango que cruza meses lleva el mes en el detalle de cada semana.
+    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-09-25' } })
+    expect(cabecerasTiempo(hoja)).toEqual(['S4 25–30 set', 'S1 1–7 oct', 'S2 8–14 oct', 'S3 15–19 oct'])
+  })
+
+  it('Días: una columna por día con domingo, hoy y futuros marcados; con más de 31 días cae a Semanas', async () => {
+    const { usuario, hoja } = await abrirProyeccion()
+    await usuario.click(tiempo('Días'))
+    expect(hoja).toHaveAttribute('data-tiempo', 'dias')
+    const dias = cabecerasTiempo(hoja)
+    expect(dias).toHaveLength(19)
+    expect(dias.slice(0, 3)).toEqual(['1 oct jue', '2 vie', '3 sáb'])
+    expect([...hoja.querySelectorAll('thead th.pc-domingo')].map(th => th.querySelector('.sr-only')!.textContent)).toEqual(['dom 4 oct', 'dom 11 oct', 'dom 18 oct'])
+    expect([...hoja.querySelectorAll('thead th.pc-hoy')].map(th => th.querySelector('.sr-only')!.textContent)).toEqual(['lun 19 oct'])
+    await usuario.click(within(fila(hoja, 'Luis Vega')).getByRole('button', { name: '1 cita de Luis Vega, 18 oct' }))
+    const lista = screen.getByRole('dialog', { name: 'Citas · 18 oct · Luis Vega' })
+    expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('18 oct 2026 · 1 cita')
+    expect(within(lista).getByRole('row', { name: /Persona l1/ })).toBeVisible()
+    await usuario.keyboard('{Escape}')
+    // Días que aún no llegan: atenuados (3 filas × 6 días).
+    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-10-25' } })
+    expect(hoja.querySelectorAll('tbody td.pc-futuro')).toHaveLength(18)
+    // Más de 31 días: «Días» se deshabilita y la hoja se pinta por semanas.
+    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-09-01' } })
+    expect(tiempo('Días')).toBeDisabled()
+    expect(tiempo('Semanas')).toHaveAttribute('aria-pressed', 'true')
+    expect(hoja).toHaveAttribute('data-tiempo', 'semanas')
+    expect(cabecerasTiempo(hoja)[0]).toBe('S1 1–7 set')
+    // Al volver a 31 días o menos, vuelve lo elegido.
+    await usuario.click(atajo('Mes'))
+    expect(tiempo('Días')).toHaveAttribute('aria-pressed', 'true')
+    expect(cabecerasTiempo(hoja)).toHaveLength(19)
+  })
+
+  it('Actualizar recarga los meses del rango cuando la Proyección tiene cargador propio', async () => {
+    const recargarMes = vi.fn()
+    const propia = { onMesesProyeccion: vi.fn(), proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, cargando: false, error: null, onReintentar: vi.fn() } }
+    const { usuario } = await abrirProyeccion({ ...propia, onReintentar: recargarMes })
+    await usuario.click(screen.getByRole('button', { name: 'Actualizar' }))
+    expect(propia.proyeccion.onReintentar).toHaveBeenCalledTimes(1)
+    expect(recargarMes).not.toHaveBeenCalled()
+    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
+    await usuario.click(screen.getByRole('button', { name: 'Actualizar' }))
+    expect(recargarMes).toHaveBeenCalledTimes(1)
+  })
+
+  it('un enlace de Proyección abre la pestaña con su rango, columnas y supervisor; los cambios lo reescriben y otra pestaña lo quita', async () => {
+    const usuario = userEvent.setup()
+    // El enlace solo admite supervisores reales (uuid) o «sin_supervisor».
+    const sinSupervisor = cita('x1', 'luis', { supervisorId: 'sin_supervisor', supervisor: 'Sin supervisor', creadoEn: '2026-10-06T15:00:00Z' })
+    window.history.replaceState(null, '', '#/reuniones/proyeccion/2026-10-03/2026-10-19/semanas')
+    render(<ContextoCitas value={{ ...fuente, citas: [...CITAS, sinSupervisor] }}><TableroCitas /></ContextoCitas>)
+    expect(screen.getByRole('tab', { name: 'Proyección' })).toHaveAttribute('aria-selected', 'true')
+    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('3–19 oct 2026')
+    expect(tiempo('Semanas')).toHaveAttribute('aria-pressed', 'true')
+    const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
+    expect(cabecerasTiempo(hoja)).toEqual(['S1 3–7', 'S2 8–14', 'S3 15–19'])
+    await usuario.selectOptions(screen.getByLabelText('Supervisor'), 'sin_supervisor')
+    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-03/2026-10-19/semanas/equipo/sin_supervisor')
+    expect(nombres(hoja)).toEqual(['LVLuis Vega'])
+    await usuario.click(tiempo('Días'))
+    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-03/2026-10-19/dias/equipo/sin_supervisor')
+    await usuario.click(atajo('S1'))
+    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-07/dias/equipo/sin_supervisor')
+    await usuario.click(tiempo('Mes'))
+    await usuario.selectOptions(screen.getByLabelText('Supervisor'), '')
+    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-07')
+    // Reescribir el enlace no reinicia la pestaña (el oyente reconoce su propia firma).
+    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–7 oct 2026')
+    // Un enlace nuevo desde fuera manda; si su rango pasa de 6 meses, cae al mes de «Hasta».
+    act(() => { window.history.replaceState(null, '', '#/reuniones/proyeccion/2026-09-28/2026-10-04/dias'); window.dispatchEvent(new HashChangeEvent('hashchange')) })
+    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('28 set – 4 oct 2026')
+    expect(tiempo('Días')).toHaveAttribute('aria-pressed', 'true')
+    act(() => { window.history.replaceState(null, '', '#/reuniones/proyeccion/2026-01-01/2026-10-19'); window.dispatchEvent(new HashChangeEvent('hashchange')) })
+    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–19 oct 2026')
+    expect(tiempo('Mes')).toHaveAttribute('aria-pressed', 'true')
+    // Otra pestaña: el enlace de Proyección ya no la describe.
+    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
+    expect(window.location.hash).toBe('#/reuniones')
+    expect(screen.getByRole('tab', { name: 'Agenda' })).toHaveAttribute('aria-selected', 'true')
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
index ab20515b..6ca0a770 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
@@ -2,9 +2,11 @@ import { describe, expect, it } from 'vitest'
 import { defaults, type CitaEjemplo, type FiltrosCitas } from './modelo'
 import {
   calcularProyeccion, csvCitasProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas, opcionesPersonas,
-  periodoProyeccion, type ConversionProyeccion, type FiltrosColumnas, type FuenteProyeccion, type PersonaProyeccion,
+  periodoProyeccion, repartirEnTramos, type ConversionProyeccion, type FiltrosColumnas, type FuenteProyeccion, type PersonaProyeccion,
 } from './proyeccion'
-import { atajosRango, errorRango, mesesDelRango, rangoInicial, rotuloRango, type RangoProyeccion } from './proyeccion-rango'
+import {
+  atajosRango, diasPermitidos, errorRango, mesesDelRango, rangoInicial, rotuloRango, tiempoEfectivo, tramosDelRango, type RangoProyeccion,
+} from './proyeccion-rango'
 
 // Hoy: lunes 19/10/2026, 12:00 de Lima. Octubre tiene 31 días; van 19.
 const HOY = '2026-10-19T17:00:00Z'
@@ -35,10 +37,10 @@ function mesLleno() {
     cita('m1', 'mateo', { leadId: 'lead-8', fecha: '2026-10-02', creadoEn: '2026-09-28T15:00:00Z' }),
   ]
   const conversiones: ConversionProyeccion[] = [
-    // Cliente DESPUÉS de su entrevista (a1): cuenta en la conversión de Ana.
-    { lead_id: 'lead-1', perfil_id: 'perfil-1', convertido_en: '2026-10-08T15:00:00Z' },
+    // Venta con fecha comercial posterior a su entrevista (a1): cuenta en la conversión de Ana.
+    { lead_id: 'lead-1', perfil_id: 'perfil-1', convertido_en: '2026-10-08T15:00:00Z', fecha_comercial: '2026-10-08' },
     // Ya era cliente cuando Diego le creó la cita (d1): va a Clientes y no convierte.
-    { lead_id: 'lead-5', perfil_id: 'perfil-5', convertido_en: '2026-10-01T15:00:00Z' },
+    { lead_id: 'lead-5', perfil_id: 'perfil-5', convertido_en: '2026-10-01T15:00:00Z', fecha_comercial: '2026-10-01' },
   ]
   const fuente: FuenteProyeccion = { citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones }
   return { citas, conversiones, fuente }
@@ -49,33 +51,40 @@ const con = (fuente: FuenteProyeccion, filtros: Partial<FiltrosCitas>): FuentePr
 const en = (fuente: FuenteProyeccion, desde: string, hasta: string): FuenteProyeccion => ({ ...fuente, rango: { desde, hasta } })
 
 describe('Proyección de citas: cohorte y columnas', () => {
-  it('mes lleno: agrupa por equipo, ordena por citas y calcula cada columna con su regla', () => {
+  it('mes lleno: hoja plana, una fila por analista ordenada por citas, y cada columna con su regla (% Entrev. sobre citas resueltas)', () => {
     const hoja = calcularProyeccion(mesLleno().fuente)
-    expect(hoja.bandas.map(b => [b.nombre, b.filas.map(f => f.id), b.citas])).toEqual([
-      ['Claudia Ríos', ['ana', 'luis'], 5], ['Javier Vega', ['diego'], 2],
+    // Sin bandas por equipo: el orden es global, aunque mezcle equipos.
+    expect(hoja.filas.map(f => [f.id, f.supervisor, f.citas.length])).toEqual([
+      ['ana', 'Claudia Ríos', 4], ['diego', 'Javier Vega', 2], ['luis', 'Claudia Ríos', 1],
     ])
+    expect(hoja.tramos).toEqual([])
     const ana = fila(hoja, 'ana')!
     expect(ana.citas).toHaveLength(4)
     // 30 000 PEN + 2 000 USD × 3,75; la cita sin monto no suma pero sí divide el ticket.
-    expect(ana).toMatchObject({ montoPen: 30_000, montoUsd: 2_000, monto: 37_500, ticket: 9_375, pctEntrevistas: 50, pctConversion: 50, pendienteTc: false })
+    expect(ana).toMatchObject({ montoPen: 30_000, montoUsd: 2_000, monto: 37_500, ticket: 9_375, pctConversion: 50, pendienteTc: false })
+    // % Entrev.: 2 realizadas ÷ 3 resueltas (a3 no asistió); la programada a4 no es base.
+    expect(ids(ana.resueltas)).toEqual(['a1', 'a2', 'a3'])
+    expect(ana.pctEntrevistas).toBeCloseTo(200 / 3, 10)
     expect(ids(ana.conMonto)).toEqual(['a1', 'a2', 'a3'])
     expect(ids(ana.convertidas)).toEqual(['a1'])
-    // Ritmo: 4 citas en 19 de 31 días → 124/19 citas esperadas × 50 % × 50 % × S/ 9 375.
+    // Ritmo: 4 citas en 19 de 31 días → 124/19 citas esperadas × 2/3 × 50 % × S/ 9 375.
     expect(ana.citasEsperadas).toBeCloseTo(124 / 19, 10)
-    expect(ana.proyectado).toBeCloseTo(124 / 19 * 0.5 * 0.5 * 9_375, 6)
+    expect(ana.proyectado).toBeCloseTo(124 / 19 * (2 / 3) * 0.5 * 9_375, 6)
     expect([ana.referidos.length, ana.clientes.length, ana.leads.length]).toEqual([1, 0, 3])
     const diego = fila(hoja, 'diego')!
-    expect(diego).toMatchObject({ monto: 80_000, ticket: 40_000, pctEntrevistas: 50, pctConversion: 0, proyectado: 0 })
+    // d2 cancelada no es base: 1 realizada ÷ 1 resuelta.
+    expect(diego).toMatchObject({ monto: 80_000, ticket: 40_000, pctEntrevistas: 100, pctConversion: 0, proyectado: 0 })
     expect([ids(diego.referidos), ids(diego.clientes), ids(diego.leads)]).toEqual([['d2'], ['d1'], []])
-    // Sin entrevistas no hay base para proyectar.
-    expect(fila(hoja, 'luis')).toMatchObject({ pctEntrevistas: 0, pctConversion: null, proyectado: null, ticket: 5_000 })
+    // Sin citas resueltas no hay base: ni % Entrev. ni proyectado (nunca 0 %).
+    expect(fila(hoja, 'luis')).toMatchObject({ pctEntrevistas: null, pctConversion: null, proyectado: null, ticket: 5_000 })
   })
 
   it('el total recalcula sobre todas las citas, suma proyectados con base y nunca promedia tasas ni tickets', () => {
     const { total, filas } = calcularProyeccion(mesLleno().fuente)
     expect(total.citas).toHaveLength(7)
     expect(total).toMatchObject({ monto: 122_500, ticket: 17_500, personasEntrevistadas: 3, personasClientes: 1 })
-    expect(total.pctEntrevistas).toBeCloseTo(300 / 7, 10)
+    // 3 realizadas ÷ 4 resueltas de todas las citas: no es el promedio de 66,7 % y 100 %.
+    expect(total.pctEntrevistas).toBe(75)
     expect(total.pctConversion).toBeCloseTo(100 / 3, 10)
     expect(total.proyectado).toBeCloseTo(filas.reduce((n, f) => n + (f.proyectado ?? 0), 0), 6)
     expect(total.referidos.length + total.clientes.length + total.leads.length).toBe(total.citas.length)
@@ -84,12 +93,11 @@ describe('Proyección de citas: cohorte y columnas', () => {
   it('mes vacío (estado de producción hoy): sin filas, total en cero y tasas sin base', () => {
     const hoja = calcularProyeccion({ citas: [], filtros: defaults('2026-10'), rango: rangoInicial('2026-10', '2026-10-19'), corte: HOY, tipoCambio: null, conversiones: [] })
     expect(hoja.filas).toEqual([])
-    expect(hoja.bandas).toEqual([])
     expect(hoja.requiereTc).toBe(false)
     expect(hoja.total).toMatchObject({ monto: 0, ticket: null, pctEntrevistas: null, pctConversion: null, proyectado: null, pendienteTc: false })
     expect(hoja.total.citas).toEqual([])
     expect(csvProyeccion(hoja, 'Octubre 2026').split('\r\n')).toEqual([
-      '﻿"Periodo","Equipo","Analista","Citas","Monto S/","Ticket S/","% Entrev.","% Conv.","Proyectado S/","Referidos","Clientes","Leads"',
+      '﻿"Periodo","Equipo","Analista","Citas","Monto S/","Ticket cita S/","% Entrev.","% Conv.","Proyectado citas S/","Referidos","Clientes","Leads"',
       '"Octubre 2026","","Total · 0 analistas","0","0","","","","","0","0","0"',
     ])
   })
@@ -97,7 +105,7 @@ describe('Proyección de citas: cohorte y columnas', () => {
   it('sin tipo de cambio, el monto con dólares queda pendiente y el ticket y el proyectado sin base', () => {
     const hoja = calcularProyeccion({ ...mesLleno().fuente, tipoCambio: null })
     expect(hoja.requiereTc).toBe(true)
-    expect(fila(hoja, 'ana')).toMatchObject({ pendienteTc: true, monto: null, ticket: null, proyectado: null, pctEntrevistas: 50 })
+    expect(fila(hoja, 'ana')).toMatchObject({ pendienteTc: true, monto: null, ticket: null, proyectado: null, pctConversion: 50 })
     // Un analista solo en soles sigue calculándose.
     expect(fila(hoja, 'diego')).toMatchObject({ pendienteTc: false, monto: 80_000, ticket: 40_000, proyectado: 0 })
     expect(hoja.total).toMatchObject({ pendienteTc: true, monto: null, ticket: null, proyectado: 0 })
@@ -110,18 +118,17 @@ describe('Proyección de citas: cohorte y columnas', () => {
   it('periodo cerrado: las citas esperadas son las registradas', () => {
     const hoja = calcularProyeccion({ ...mesLleno().fuente, corte: '2026-11-03T15:00:00Z' })
     expect(hoja.periodo).toMatchObject({ cerrado: true, dias: 31, transcurridos: 31 })
-    expect(fila(hoja, 'ana')).toMatchObject({ citasEsperadas: 4, proyectado: 4 * 0.5 * 0.5 * 9_375 })
+    expect(fila(hoja, 'ana')).toMatchObject({ citasEsperadas: 4 })
+    expect(fila(hoja, 'ana')!.proyectado).toBeCloseTo(4 * (2 / 3) * 0.5 * 9_375, 6)
   })
 
   it('la cohorte es por fecha de creación: el analista cuya cita se creó en otro mes no tiene fila', () => {
     const { fuente } = mesLleno()
     expect(fila(calcularProyeccion(fuente), 'mateo')).toBeUndefined()
-    expect(calcularProyeccion(con(fuente, { analista: 'mateo' })).filas).toEqual([])
-    // Semana y día de arriba no aplican: manda el rango.
-    expect(calcularProyeccion(con(fuente, { semana: '1', dia: '2026-10-02' })).total.citas).toHaveLength(7)
-    // Equipo y búsqueda de la consulta.
+    // De la consulta de arriba solo cuenta el supervisor: semana, día, analista y búsqueda
+    // (ocultos en la Proyección) no recortan nada; el analista se acota con su embudo.
+    expect(calcularProyeccion(con(fuente, { semana: '1', dia: '2026-10-02', analista: 'mateo', q: 'persona d2' })).total.citas).toHaveLength(7)
     expect(calcularProyeccion(con(fuente, { equipo: 'sup-2' })).filas.map(f => f.id)).toEqual(['diego'])
-    expect(calcularProyeccion(con(fuente, { q: 'persona d2' })).total.citas.map(c => c.cita.id)).toEqual(['d2'])
   })
 })
 
@@ -140,7 +147,6 @@ describe('Proyección de citas: rango Desde–Hasta', () => {
   it('rango que cruza dos meses: entran las citas creadas a fines del mes anterior', () => {
     const hoja = calcularProyeccion(en(mesLleno().fuente, '2026-09-25', '2026-10-05'))
     expect(hoja.filas.map(f => [f.id, f.citas.map(c => c.cita.id)])).toEqual([['ana', ['a1', 'a2', 'a3']], ['mateo', ['m1']]])
-    expect(hoja.bandas.map(b => b.nombre)).toEqual(['Claudia Ríos', 'Javier Vega'])
   })
 
   it('rango futuro: sin citas, sin filas y sin proyección', () => {
@@ -191,7 +197,7 @@ describe('Proyección de citas: embudos de columna', () => {
     expect(fila(sinClientes, 'ana')!.citas).toHaveLength(4)
     const vacio = calcularProyeccion(fuente, { personas: { cliente: [], referido: [] } })
     expect(fila(vacio, 'diego')).toBeUndefined()
-    expect(vacio.bandas.map(b => b.nombre)).toEqual(['Claudia Ríos'])
+    expect(vacio.filas.map(f => f.id)).toEqual(['ana', 'luis'])
     // La lista de personas de un origen ignora su propio embudo para poder volver a marcar.
     expect(opcionesPersonas(vacio, { personas: { cliente: [], referido: [] } }, 'cliente')).toHaveLength(1)
   })
@@ -210,16 +216,17 @@ describe('Proyección de citas: embudos de columna', () => {
     expect(opcionesAnalistas(base, {})).toEqual([
       { id: 'ana', nombre: 'Ana Torres', citas: 4 }, { id: 'diego', nombre: 'Diego Salas', citas: 2 }, { id: 'luis', nombre: 'Luis Vega', citas: 1 },
     ])
-    expect(calcularProyeccion(fuente, { analistas: ['luis', 'diego'] }).filas.map(f => f.id)).toEqual(['luis', 'diego'])
+    expect(calcularProyeccion(fuente, { analistas: ['luis', 'diego'] }).filas.map(f => f.id)).toEqual(['diego', 'luis'])
     expect(calcularProyeccion(fuente, { rangos: { citas: { min: 2 } } }).filas.map(f => f.id)).toEqual(['ana', 'diego'])
     // Una fila sin base no cumple ningún rango.
     expect(calcularProyeccion(fuente, { rangos: { conversion: { max: 10 } } }).filas.map(f => f.id)).toEqual(['diego'])
     expect(calcularProyeccion(fuente, { rangos: { monto: { min: 10_000, max: 50_000 } } }).filas.map(f => f.id)).toEqual(['ana'])
-    expect(calcularProyeccion(fuente, {}, { columna: 'analista', direccion: 'desc' }).bandas[0]!.filas.map(f => f.id)).toEqual(['luis', 'ana'])
-    for (const direccion of ['asc', 'desc'] as const) {
-      expect(calcularProyeccion(fuente, {}, { columna: 'proyectado', direccion }).bandas[0]!.filas.map(f => f.id)).toEqual(['ana', 'luis'])
-    }
-    expect(calcularProyeccion(fuente, {}, { columna: 'ticket', direccion: 'asc' }).bandas[0]!.filas.map(f => f.id)).toEqual(['luis', 'ana'])
+    const ordenar = (columna: 'analista' | 'proyectado' | 'ticket', direccion: 'asc' | 'desc') => calcularProyeccion(fuente, {}, { columna, direccion }).filas.map(f => f.id)
+    expect(ordenar('analista', 'desc')).toEqual(['luis', 'diego', 'ana'])
+    // Luis no tiene base: su «—» va al final en los dos sentidos.
+    expect(ordenar('proyectado', 'asc')).toEqual(['diego', 'ana', 'luis'])
+    expect(ordenar('proyectado', 'desc')).toEqual(['ana', 'diego', 'luis'])
+    expect(ordenar('ticket', 'asc')).toEqual(['luis', 'ana', 'diego'])
   })
 })
 
@@ -233,7 +240,7 @@ describe('Proyección de citas: identidad y clientes', () => {
       // Creada después de que la persona se convirtiera (por el otro lead): ya es cliente.
       cita('x2', 'ana', { leadId: 'lead-x', creadoEn: '2026-10-12T15:00:00Z' }),
     ]
-    const conversiones = [{ lead_id: 'lead-y', perfil_id: 'perfil-y', convertido_en: '2026-10-10T15:00:00Z' }]
+    const conversiones = [{ lead_id: 'lead-y', perfil_id: 'perfil-y', convertido_en: '2026-10-10T15:00:00Z', fecha_comercial: '2026-10-10' }]
     const ana = calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones, poblacion }).filas[0]!
     expect(ana).toMatchObject({ personasEntrevistadas: 1, personasClientes: 1, pctConversion: 100 })
     expect(ids(ana.convertidas)).toEqual(['x1', 'y1'])
@@ -276,11 +283,13 @@ describe('Proyección de citas: periodo y CSV', () => {
     expect(periodoProyeccion(OCTUBRE, 'no es fecha')).toBeNull()
   })
 
-  it('el CSV de la hoja lleva el ticket y el total; el de la lista, el monto original y en soles', () => {
+  it('el CSV de la hoja lleva el ticket por cita y el total; el de la lista, el monto original y en soles', () => {
     const hoja = calcularProyeccion(mesLleno().fuente)
     const lineas = csvProyeccion(hoja, 'Octubre 2026').split('\r\n')
-    expect(lineas[1]).toBe('"Octubre 2026","Claudia Ríos","Ana Torres","4","37500","9375","50","50","15296.05","1","0","3"')
-    expect(lineas.at(-1)).toBe('"Octubre 2026","","Total · 3 analistas","7","122500","17500","42.9","33.3","15296.05","2","1","4"')
+    expect(lineas[0]).toContain('"Monto S/","Ticket cita S/","% Entrev."')
+    // Ana: 124/19 × 2/3 × 50 % × 9 375 = 20 394,74.
+    expect(lineas[1]).toBe('"Octubre 2026","Claudia Ríos","Ana Torres","4","37500","9375","66.7","50","20394.74","1","0","3"')
+    expect(lineas.at(-1)).toBe('"Octubre 2026","","Total · 3 analistas","7","122500","17500","75","33.3","20394.74","2","1","4"')
     const lista = csvCitasProyeccion(fila(hoja, 'ana')!.conMonto.filter(c => c.cita.id === 'a2'))
     expect(lista.split('\r\n')[1]).toBe('"a2","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
   })
@@ -294,3 +303,145 @@ describe('Proyección de citas: periodo y CSV', () => {
     }
   })
 })
+
+describe('Proyección de citas: columnas de tiempo', () => {
+  const HOY_LIMA = '2026-10-19'
+  const vista = (tramos: ReturnType<typeof tramosDelRango>) => tramos.map(t => `${t.titulo}|${t.detalle}|${t.desde}/${t.hasta}|${t.rotulo}`)
+
+  it('semanas de un mes: las cuatro comerciales recortadas al rango', () => {
+    expect(vista(tramosDelRango({ desde: '2026-10-03', hasta: '2026-10-19' }, 'semanas', HOY_LIMA))).toEqual([
+      'S1|3–7|2026-10-03/2026-10-07|S1 3–7 oct', 'S2|8–14|2026-10-08/2026-10-14|S2 8–14 oct', 'S3|15–19|2026-10-15/2026-10-19|S3 15–19 oct',
+    ])
+    // Mes entero: la cuarta llega al último día; la que aún no empieza queda como futura.
+    const octubre = tramosDelRango(OCTUBRE, 'semanas', HOY_LIMA)
+    expect(vista(octubre).at(-1)).toBe('S4|22–31|2026-10-22/2026-10-31|S4 22–31 oct')
+    expect(octubre.map(t => t.futuro)).toEqual([false, false, false, true])
+    // Un tramo de un solo día se rotula con ese día.
+    expect(vista(tramosDelRango({ desde: '2026-10-07', hasta: '2026-10-08' }, 'semanas', HOY_LIMA))).toEqual([
+      'S1|7|2026-10-07/2026-10-07|S1 7 oct', 'S2|8|2026-10-08/2026-10-08|S2 8 oct',
+    ])
+    expect(tramosDelRango(OCTUBRE, 'mes', HOY_LIMA)).toEqual([])
+  })
+
+  it('semanas de un rango que cruza meses (y años): el detalle lleva el mes', () => {
+    expect(vista(tramosDelRango({ desde: '2026-09-25', hasta: '2026-10-05' }, 'semanas', HOY_LIMA))).toEqual([
+      'S4|25–30 set|2026-09-25/2026-09-30|S4 25–30 set', 'S1|1–5 oct|2026-10-01/2026-10-05|S1 1–5 oct',
+    ])
+    const anio = tramosDelRango({ desde: '2025-12-28', hasta: '2026-01-03' }, 'semanas', HOY_LIMA)
+    expect(vista(anio)).toEqual(['S4|28–31 dic|2025-12-28/2025-12-31|S4 28–31 dic', 'S1|1–3 ene|2026-01-01/2026-01-03|S1 1–3 ene'])
+    expect(new Set(anio.map(t => t.id)).size).toBe(2)
+  })
+
+  it('días: número y día corto; el mes en la primera columna y en el día 1; domingo, hoy y futuros marcados', () => {
+    const dias = tramosDelRango({ desde: '2026-10-17', hasta: '2026-10-21' }, 'dias', HOY_LIMA)
+    expect(dias.map(t => [t.titulo, t.detalle, t.rotulo, t.nombre])).toEqual([
+      ['17 oct', 'sáb', '17 oct', 'sáb 17 oct'], ['18', 'dom', '18 oct', 'dom 18 oct'], ['19', 'lun', '19 oct', 'lun 19 oct'],
+      ['20', 'mar', '20 oct', 'mar 20 oct'], ['21', 'mié', '21 oct', 'mié 21 oct'],
+    ])
+    expect(dias.map(t => [t.domingo, t.hoy, t.futuro])).toEqual([
+      [false, false, false], [true, false, false], [false, true, false], [false, false, true], [false, false, true],
+    ])
+    expect(tramosDelRango({ desde: '2026-10-30', hasta: '2026-11-02' }, 'dias', HOY_LIMA).map(t => `${t.titulo} ${t.detalle}`)).toEqual([
+      '30 oct vie', '31 sáb', '1 nov dom', '2 lun',
+    ])
+  })
+
+  it('tope de 31 días: con más, «Días» cae a «Semanas»; un rango inválido no tiene columnas', () => {
+    expect(diasPermitidos(OCTUBRE)).toBe(true)
+    expect(tramosDelRango(OCTUBRE, 'dias', HOY_LIMA)).toHaveLength(31)
+    const largo = { desde: '2026-10-01', hasta: '2026-11-01' }
+    expect(diasPermitidos(largo)).toBe(false)
+    expect(tiempoEfectivo('dias', largo)).toBe('semanas')
+    expect(tiempoEfectivo('mes', largo)).toBe('mes')
+    expect(tramosDelRango(largo, 'dias', HOY_LIMA).map(t => t.titulo)).toEqual(['S1', 'S2', 'S3', 'S4', 'S1'])
+    expect(diasPermitidos({ desde: '2026-10-05', hasta: '2026-10-01' })).toBe(false)
+    expect(tramosDelRango({ desde: '2026-10-05', hasta: '2026-10-01' }, 'semanas', HOY_LIMA)).toEqual([])
+  })
+
+  it('cada fila reparte sus citas por día de creación y la suma de sus tramos es su columna Citas', () => {
+    const { fuente } = mesLleno()
+    const semanas = calcularProyeccion({ ...fuente, tiempo: 'semanas' })
+    const conteo = (m: { porTramo: unknown[][] }) => m.porTramo.map(l => l.length)
+    expect(conteo(fila(semanas, 'ana')!)).toEqual([3, 1, 0, 0])
+    expect(conteo(fila(semanas, 'diego')!)).toEqual([0, 1, 1, 0])
+    expect(conteo(semanas.total)).toEqual([3, 2, 2, 0])
+    expect(ids(fila(semanas, 'diego')!.porTramo[2]!)).toEqual(['d2'])
+    const dias = calcularProyeccion({ ...fuente, tiempo: 'dias' })
+    expect(dias.tramos).toHaveLength(31)
+    expect(ids(fila(dias, 'ana')!.porTramo[1]!)).toEqual(['a1'])
+    // Con cualquier vista, rango y embudo: suma de tramos = citas, por fila y en el total.
+    for (const tiempo of ['semanas', 'dias'] as const) {
+      for (const rango of [OCTUBRE, { desde: '2026-09-25', hasta: '2026-10-05' }, { desde: '2026-10-03', hasta: '2026-10-19' }]) {
+        for (const columnas of [{}, { monedas: ['PEN'] }, { personas: { lead: [] } }] as FiltrosColumnas[]) {
+          const hoja = calcularProyeccion({ ...fuente, tiempo, rango }, columnas)
+          for (const m of [...hoja.filas, hoja.total]) expect(conteo(m).reduce((n, x) => n + x, 0)).toBe(m.citas.length)
+        }
+      }
+    }
+    // Sin columnas de tiempo no se reparte nada; fuera de todo tramo, una cita no se cuenta.
+    expect(fila(calcularProyeccion(fuente), 'ana')!.porTramo).toEqual([])
+    expect(repartirEnTramos(fila(semanas, 'ana')!.citas, [{ desde: '2026-10-02', hasta: '2026-10-02' }]).map(l => l.length)).toEqual([1])
+  })
+
+  it('el CSV en Semanas o Días añade una columna por tramo después de «Analista»', () => {
+    const lineas = csvProyeccion(calcularProyeccion({ ...mesLleno().fuente, tiempo: 'semanas' }), 'Octubre 2026').split('\r\n')
+    expect(lineas[0]).toBe('\uFEFF"Periodo","Equipo","Analista","S1 1–7 oct","S2 8–14 oct","S3 15–21 oct","S4 22–31 oct","Citas","Monto S/","Ticket cita S/","% Entrev.","% Conv.","Proyectado citas S/","Referidos","Clientes","Leads"')
+    expect(lineas[1]).toBe('"Octubre 2026","Claudia Ríos","Ana Torres","3","1","0","0","4","37500","9375","66.7","50","20394.74","1","0","3"')
+    expect(lineas.at(-1)).toMatch(/^"Octubre 2026","","Total · 3 analistas","3","2","2","0","7",/)
+    const dias = csvProyeccion(calcularProyeccion({ ...mesLleno().fuente, tiempo: 'dias', rango: { desde: '2026-10-17', hasta: '2026-10-19' } }), 'x').split('\r\n')
+    expect(dias[0]).toContain('"Analista","sáb 17 oct","dom 18 oct","lun 19 oct","Citas"')
+  })
+})
+
+describe('Proyección de citas: % Entrev. y % Conv. con las reglas de Resultados', () => {
+  const sinVentas = (citas: CitaEjemplo[]) => calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones: [] })
+
+  it('% Entrev. = realizadas ÷ (realizadas + no asistió): programadas, futuras, vencidas y canceladas no son base', () => {
+    const citas = [
+      cita('e1', 'ana', { estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z' }),
+      cita('e2', 'ana', { estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z' }),
+      cita('e3', 'ana', { estado: 'no_show' }),
+      cita('e4', 'ana', { fecha: '2026-10-28' }),
+      cita('e5', 'ana', { fecha: '2026-11-04' }),
+      cita('e6', 'ana', { estado: 'vencida' }),
+      cita('e7', 'ana', { estado: 'cancelada' }),
+    ]
+    const ana = sinVentas(citas).filas[0]!
+    // Antes: 2 ÷ 7 = 28,6 % (las futuras contaban como no asistidas). Ahora: 2 ÷ 3.
+    expect(ids(ana.resueltas)).toEqual(['e1', 'e2', 'e3'])
+    expect(ids(ana.entrevistas)).toEqual(['e1', 'e2'])
+    expect(ana.pctEntrevistas).toBeCloseTo(200 / 3, 10)
+    // Todas resueltas sin asistencia: 0 % con base; ninguna resuelta: sin base, nunca 0 %.
+    expect(sinVentas(citas.filter(c => c.id === 'e3')).filas[0]!.pctEntrevistas).toBe(0)
+    expect(sinVentas(citas.filter(c => !['e1', 'e2', 'e3'].includes(c.id))).filas[0]!.pctEntrevistas).toBeNull()
+  })
+
+  it('% Conv. vincula como Resultados: venta con fecha comercial el día de la entrevista o después, hasta el corte y sin recortarla al mes', () => {
+    const realizada = (id: string) => cita(id, 'ana', { leadId: `lead-${id}`, estado: 'realizada', asistioEn: '2026-10-06T20:00:00Z', creadoEn: '2026-10-02T15:00:00Z' })
+    const venta = (lead: string, convertidoEn: string, fechaComercial: string | null): ConversionProyeccion =>
+      ({ lead_id: lead, perfil_id: `perfil-${lead}`, convertido_en: convertidoEn, fecha_comercial: fechaComercial })
+    const citas = ['v1', 'v2', 'v3', 'v4', 'v5', 'v6'].map(realizada)
+    const conversiones = [
+      // Mismo día de Lima aunque se registró antes de la hora de la entrevista: la fecha comercial no ordena dentro del día.
+      venta('lead-v1', '2026-10-06T14:00:00Z', '2026-10-06'),
+      // Registrada después, pero con la venta ANTERIOR al día de la entrevista: la regla vieja la contaba.
+      venta('lead-v2', '2026-10-09T15:00:00Z', '2026-10-05'),
+      // Sin hecho comercial (renovación, fuente retirada): la regla vieja también la contaba.
+      venta('lead-v3', '2026-10-09T15:00:00Z', null),
+      // Venta del mes siguiente: la Proyección sigue su cohorte hasta el corte.
+      venta('lead-v4', '2026-11-10T15:00:00Z', '2026-11-10'),
+      // Venta posterior al corte: aún no existe para la consulta.
+      venta('lead-v5', '2026-11-25T15:00:00Z', '2026-11-25'),
+    ]
+    const hoja = calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: '2026-11-20T17:00:00Z', tipoCambio: TC, conversiones })
+    const ana = hoja.filas[0]!
+    expect(ids(ana.convertidas)).toEqual(['v1', 'v4'])
+    expect(ana).toMatchObject({ personasEntrevistadas: 6, personasClientes: 2 })
+    expect(ana.pctConversion).toBeCloseTo(100 / 3, 10)
+    // Una realizada sin hora de asistencia no se vincula a ninguna venta.
+    const sinHora = cita('v1', 'ana', { leadId: 'lead-v1', estado: 'realizada', creadoEn: '2026-10-02T15:00:00Z' })
+    const sinAsistencia = calcularProyeccion({ citas: [sinHora], filtros: defaults('2026-10'), rango: OCTUBRE,
+      corte: HOY, tipoCambio: TC, conversiones: [venta('lead-v1', '2026-10-06T14:00:00Z', '2026-10-06')] })
+    expect(sinAsistencia.filas[0]).toMatchObject({ personasEntrevistadas: 1, personasClientes: 0, pctConversion: 0 })
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/router.test.ts b/CRM-Avance-Corp/app/src/lib/router.test.ts
index 0061e7e7..34395d02 100644
--- a/CRM-Avance-Corp/app/src/lib/router.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/router.test.ts
@@ -10,6 +10,7 @@ import {
   VISTAS,
   VISTAS_GERENCIA,
 } from './router'
+import { esConsultaProyeccion, mesConsultaCitas, type ConsultaCitasEnlace } from './enlace-citas'
 
 describe('router por hash', () => {
   beforeEach(() => {
@@ -46,6 +47,68 @@ describe('router por hash', () => {
     }
   })
 
+  it('lleva la Proyección por rango con y sin vista, equipo y ficha, y vuelve igual', () => {
+    const casos: [ConsultaCitasEnlace, string | null, string][] = [
+      [{ desde: '2026-10-01', hasta: '2026-10-19' }, null, '#/reuniones/proyeccion/2026-10-01/2026-10-19'],
+      [{ desde: '2026-10-01', hasta: '2026-10-19', vista: 'dias' }, null, '#/reuniones/proyeccion/2026-10-01/2026-10-19/dias'],
+      [{ desde: '2026-05-01', hasta: '2026-10-31', vista: 'semanas', equipo: 'd-sup1' }, null, '#/reuniones/proyeccion/2026-05-01/2026-10-31/semanas/equipo/d-sup1'],
+      [{ desde: '2026-10-19', hasta: '2026-10-19', equipo: 'sin_supervisor' }, 'lead/1', '#/reuniones/proyeccion/2026-10-19/2026-10-19/equipo/sin_supervisor/lead/lead%2F1'],
+      [{ desde: '2026-10-01', hasta: '2026-10-19', vista: 'dias' }, 'l1', '#/reuniones/proyeccion/2026-10-01/2026-10-19/dias/lead/l1'],
+      [{ desde: '2026-10-01', hasta: '2026-10-19' }, 'l1', '#/reuniones/proyeccion/2026-10-01/2026-10-19/lead/l1'],
+      [{ desde: '2026-10-01', hasta: '2026-10-19', vista: 'semanas', equipo: '10000000-0000-4000-8000-000000000001' }, 'l1',
+        '#/reuniones/proyeccion/2026-10-01/2026-10-19/semanas/equipo/10000000-0000-4000-8000-000000000001/lead/l1'],
+    ]
+    for (const [consulta, leadId, hash] of casos) {
+      escribirHash('reuniones', leadId, true, undefined, undefined, undefined, undefined, consulta)
+      expect(window.location.hash).toBe(hash)
+      expect(leerHash()).toEqual({ vista: 'reuniones', leadId, consultaCitas: consulta })
+      // Al cerrar la ficha el rango sigue en la URL.
+      escribirHash('reuniones', null, true, undefined, undefined, undefined, undefined, leerHash().consultaCitas)
+      expect(leerHash().consultaCitas).toEqual(consulta)
+    }
+    expect(hashDe('hoy', null, undefined, undefined, undefined, undefined, { desde: '2026-10-01', hasta: '2026-10-19' })).toBe('#/hoy')
+  })
+
+  it('rechaza rangos imposibles, invertidos, vistas desconocidas y equipos con forma rara', () => {
+    for (const hash of [
+      '#/reuniones/proyeccion/2026-10-20/2026-10-01',
+      '#/reuniones/proyeccion/2026-02-30/2026-03-01',
+      '#/reuniones/proyeccion/2026-10-01/2026-13-01',
+      '#/reuniones/proyeccion/2026-10-01/2026-10-19/anios',
+      '#/reuniones/proyeccion/2026-10-01/2026-10-19/Dias',
+      '#/reuniones/proyeccion/2026-10-01/2026-10-19/equipo/../../x',
+      '#/reuniones/proyeccion/2026-10-01/2026-10-19/dias/equipo/x-sup1',
+      '#/reuniones/proyeccion/2026-10-01/2026-10-19/equipo',
+      '#/reuniones/proyeccion/2026-10-01',
+      '#/reuniones/proyeccion/2026-10/2026-10-19',
+      '#/reuniones/proyeccion/2026-10-01/equipo/d-sup1',
+      '#/hoy/proyeccion/2026-10-01/2026-10-19',
+    ]) {
+      window.history.replaceState(null, '', hash)
+      expect(leerHash().consultaCitas, hash).toBeUndefined()
+    }
+    // Un rango inválido no se escribe: la URL cae en la vista sin contexto.
+    expect(hashDe('reuniones', null, undefined, undefined, undefined, undefined, { desde: '2026-10-20', hasta: '2026-10-01' })).toBe('#/reuniones')
+    expect(hashDe('reuniones', null, undefined, undefined, undefined, undefined,
+      { desde: '2026-10-01', hasta: '2026-10-19', vista: 'anios' } as unknown as ConsultaCitasEnlace)).toBe('#/reuniones')
+    // Ni mezclas de variantes: el enlace significa una sola cosa.
+    expect(hashDe('reuniones', null, undefined, undefined, undefined, undefined,
+      { desde: '2026-10-01', hasta: '2026-10-19', dia: '2026-10-05' } as unknown as ConsultaCitasEnlace)).toBe('#/reuniones')
+    expect(hashDe('reuniones', null, undefined, undefined, undefined, undefined,
+      { dia: '2026-10-05', vista: 'dias' } as unknown as ConsultaCitasEnlace)).toBe('#/reuniones')
+  })
+
+  it('el mes que carga Citas sale del final del rango; la guarda distingue la Proyección', () => {
+    expect(mesConsultaCitas({ desde: '2026-05-01', hasta: '2026-10-19', vista: 'semanas' })).toBe('2026-10')
+    expect(mesConsultaCitas({ desde: '2026-09-28', hasta: '2026-11-02' })).toBe('2026-11')
+    expect(mesConsultaCitas({ dia: '2026-10-05' })).toBe('2026-10')
+    expect(mesConsultaCitas({ mes: '2026-09', semana: '2' })).toBe('2026-09')
+    expect(esConsultaProyeccion({ desde: '2026-10-01', hasta: '2026-10-19' })).toBe(true)
+    expect(esConsultaProyeccion({ dia: '2026-10-05' })).toBe(false)
+    expect(esConsultaProyeccion({ mes: '2026-10' })).toBe(false)
+    expect(esConsultaProyeccion(undefined)).toBe(false)
+  })
+
   it('conserva equipo/analista al abrir y cerrar la ficha desde Gestión Diaria', () => {
     const id = '10000000-0000-4000-8000-000000000001'
     for (const tipo of ['equipo', 'analista'] as const) {
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-jornada.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-jornada.test.tsx
index dd8d776e..9a95b05f 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-jornada.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-jornada.test.tsx
@@ -137,6 +137,9 @@ describe('portada comercial del supervisor', () => {
   it('enlaza las citas con su fecha; no concede esta vista a otros roles', () => {
     const { rerender } = render(<HoySupervisorJornada />)
     expect(screen.getByRole('link', { name: /Ver citas del equipo/ })).toHaveAttribute('href', '#/reuniones/dia/2026-10-18')
+    expect(screen.getByRole('link', { name: /pendientes? de resultado/ })).toHaveAttribute('href', '#/reuniones/dia/2026-10-18')
+    // «Citas de hoy» cuenta citas PREVISTAS hoy; la Proyección cuenta citas CREADAS: el título no enlaza allí (misma palabra, otra cifra).
+    expect(screen.queryByRole('link', { name: 'Citas de hoy' })).not.toBeInTheDocument()
     actor = { ...actor, rol: 'vendedor' }; rerender(<HoySupervisorJornada />)
     expect(screen.queryByRole('heading', { name: 'Dirección de la jornada' })).not.toBeInTheDocument()
     expect(screen.getByRole('alert')).toHaveTextContent('supervisores autorizados')
```

## Archivo nuevo: app/src/components/citas/proyeccion-invariantes.test.ts
```ts
// Invariantes de la Proyección de Citas (auditoría de consistencia, 19/10/2026).
// Regla del dueño: «no puede haber data distinta». Lo que debe cumplirse SIEMPRE,
// sean cuales sean los datos, y que la Proyección y Resultados
// (`calcularAvanceCitas`) cuenten lo mismo cuando dicen lo mismo.
import { describe, expect, it } from 'vitest'
import { controlCitasInicial } from '@/lib/control-citas'
import { fusionarConsultasCitas, type ConsultaCitasRpc } from '@/data/citas-gerencia'
import { calcularAvanceCitas } from './avance'
import { fechaLocalCitas } from './fecha-comercial'
import type { GestionCitas } from './metas'
import { defaults, type CitaEjemplo } from './modelo'
import { calcularProyeccion, type FuenteProyeccion, type HojaProyeccion, type MetricasProyeccion } from './proyeccion'
import { sumarDias, type RangoProyeccion, type TiempoProyeccion } from './proyeccion-rango'

const HOY = '2026-10-19T17:00:00Z' // lunes 19/10/2026, 12:00 de Lima
const TC = 3.4391
const OCTUBRE: RangoProyeccion = { desde: '2026-10-01', hasta: '2026-10-31' }
const SEPTIEMBRE: RangoProyeccion = { desde: '2026-09-01', hasta: '2026-09-30' }
type Conversion = NonNullable<GestionCitas['avance']>['conversiones'][number]

const ANALISTAS = [['ana', 'sup-1'], ['luis', 'sup-1'], ['diego', 'sup-2'], ['mateo', 'sup-2']] as const
function cita(n: number, cambios: Partial<CitaEjemplo> & { creadoEn: string }): CitaEjemplo {
  const [analista, supervisorId] = ANALISTAS[n % ANALISTAS.length]!
  return {
    id: `c${n}`, leadId: `lead-${n}`, nombre: `Persona ${n}`, telefono: '900000000', analista, analistaNombre: analista,
    supervisor: supervisorId, supervisorId, fecha: cambios.creadoEn.slice(0, 10), hora: '10:00', estado: 'programada',
    modalidad: 'Virtual', origen: 'Formulario', moneda: 'PEN', monto: 10_000, resultado: 'Sin clasificar', cerrado: false,
    seguimiento: false, nuevaFecha: null, nota: '', ...cambios,
  }
}
const venta = (c: CitaEjemplo, convertidoEn: string, fechaComercial: string | null): Conversion => ({
  lead_id: c.leadId, perfil_id: `perfil-${c.leadId}`, convertido_en: convertidoEn, fecha_comercial: fechaComercial,
  analista_id: c.analista, analista_nombre: c.analistaNombre, supervisor_id: c.supervisorId, supervisor_nombre: c.supervisor, contrato_id: null,
})

/** Lote determinista y variado: 45 días, monedas, orígenes, estados, sin monto, ya clientes, previstas en otro mes y ventas de todo tipo. */
function lote(): { citas: CitaEjemplo[]; conversiones: Conversion[] } {
  const estados = ['realizada', 'no_show', 'programada', 'vencida', 'cancelada', 'sistema', 'reprogramada'] as const
  const citas: CitaEjemplo[] = []
  for (let d = 0; d < 45; d += 1) {
    const dia = sumarDias('2026-09-20', d)
    for (let k = 0; k < 3; k += 1) {
      const i = d * 3 + k
      const estado = estados[i % estados.length]!
      citas.push(cita(i + 1, {
        creadoEn: `${dia}T${String(5 + k * 7).padStart(2, '0')}:30:00Z`, // 05:30Z = 00:30 de Lima (borde de día)
        fecha: sumarDias(dia, (i * 7) % 41), // prevista 0–40 días después: parte cae en el mes siguiente
        estado,
        ...(estado === 'realizada' ? { asistioEn: `${sumarDias(dia, 1)}T16:00:00Z` } : {}),
        moneda: i % 5 === 0 ? 'USD' : 'PEN',
        monto: i % 11 === 0 ? null : 1_000 * (1 + (i % 13)),
        origen: i % 4 === 0 ? 'Referido' : i % 4 === 1 ? 'referido' : 'Formulario',
        esCliente: i % 9 === 0,
        // La misma persona con dos citas (y de otro analista).
        ...(i % 6 === 1 ? { leadId: `lead-${i - 1}` } : {}),
      }))
    }
  }
  // Ventas: posterior a la entrevista (vincula), anterior a su día (no) y sin fecha comercial (no).
  const conversiones = citas.filter(c => c.estado === 'realizada').flatMap((c, i) => {
    const dia = fechaLocalCitas(c.asistioEn!)
    if (i % 4 === 3) return []
    return [venta(c, `${sumarDias(dia, 3)}T15:00:00Z`, i % 4 === 0 ? sumarDias(dia, 3) : i % 4 === 1 ? sumarDias(dia, -1) : null)]
  })
  return { citas, conversiones }
}

const fuente = (rango: RangoProyeccion, cambios: Partial<FuenteProyeccion> = {}): FuenteProyeccion =>
  ({ ...lote(), filtros: { equipo: '' }, rango, corte: HOY, tipoCambio: TC, ...cambios })
const filasYTotal = (h: HojaProyeccion): MetricasProyeccion[] => [...h.filas, h.total]
const ids = (lista: readonly { cita: CitaEjemplo }[]) => lista.map(c => c.cita.id).sort()
const RANGOS: RangoProyeccion[] = [
  { desde: '2026-10-01', hasta: '2026-10-07' }, { desde: '2026-10-01', hasta: '2026-10-19' }, OCTUBRE,
  { desde: '2026-09-25', hasta: '2026-10-19' }, { desde: '2026-10-19', hasta: '2026-10-19' },
]
const TIEMPOS: TiempoProyeccion[] = ['mes', 'semanas', 'dias']

describe('Invariantes de la Proyección (siempre ciertas)', () => {
  it.each(RANGOS)('Referidos + Clientes + Leads = Citas, por fila y en el total, sin una cita en dos orígenes ($desde → $hasta)', rango => {
    for (const tiempo of TIEMPOS) {
      for (const m of filasYTotal(calcularProyeccion(fuente(rango, { tiempo })))) {
        expect(m.referidos.length + m.clientes.length + m.leads.length).toBe(m.citas.length)
        expect(new Set([...m.referidos, ...m.clientes, ...m.leads].map(c => c.cita.id)).size).toBe(m.citas.length)
      }
    }
  })

  it.each(RANGOS)('el total es la suma de las filas: citas, resueltas, entrevistas, PEN, USD y proyectado ($desde → $hasta)', rango => {
    const hoja = calcularProyeccion(fuente(rango))
    const suma = (f: (m: MetricasProyeccion) => number) => hoja.filas.reduce((s, m) => s + f(m), 0)
    expect(hoja.filas.length).toBeGreaterThan(0)
    expect(suma(m => m.citas.length)).toBe(hoja.total.citas.length)
    expect(suma(m => m.resueltas.length)).toBe(hoja.total.resueltas.length)
    expect(suma(m => m.entrevistas.length)).toBe(hoja.total.entrevistas.length)
    expect(suma(m => m.montoPen)).toBeCloseTo(hoja.total.montoPen, 6)
    expect(suma(m => m.montoUsd)).toBeCloseTo(hoja.total.montoUsd, 6)
    const conBase = hoja.filas.filter(f => f.proyectado !== null)
    expect(hoja.total.proyectado).toEqual(conBase.length ? expect.closeTo(conBase.reduce((s, f) => s + f.proyectado!, 0), 6) : null)
  })

  it.each(RANGOS)('Semanas y Días: la suma de los tramos es Citas y cada tramo es la consulta de su propio rango ($desde → $hasta)', rango => {
    for (const tiempo of ['semanas', 'dias'] as const) {
      const hoja = calcularProyeccion(fuente(rango, { tiempo }))
      expect(hoja.tramos.length).toBeGreaterThan(0)
      for (const m of filasYTotal(hoja)) expect(m.porTramo.reduce((s, l) => s + l.length, 0)).toBe(m.citas.length)
      // Elegir el rango de un tramo da las mismas citas que su columna (y, con un mismo TC, el mismo dinero).
      const partes = hoja.tramos.map(t => calcularProyeccion(fuente({ desde: t.desde, hasta: t.hasta })).total)
      partes.forEach((parte, i) => expect(ids(parte.citas)).toEqual(ids(hoja.total.porTramo[i]!)))
      expect(partes.reduce((s, m) => s + m.entrevistas.length, 0)).toBe(hoja.total.entrevistas.length)
      expect(partes.reduce((s, m) => s + (m.monto ?? 0), 0)).toBeCloseTo(hoja.total.monto ?? 0, 4)
    }
  })

  it('la suma por supervisor es el total sin filtro', () => {
    const todo = calcularProyeccion(fuente(OCTUBRE))
    const porEquipo = ['sup-1', 'sup-2'].map(equipo => calcularProyeccion(fuente(OCTUBRE, { filtros: { equipo } })).total)
    expect(porEquipo.reduce((s, m) => s + m.citas.length, 0)).toBe(todo.total.citas.length)
    expect(porEquipo.reduce((s, m) => s + m.montoPen, 0)).toBeCloseTo(todo.total.montoPen, 6)
  })

  it.each(RANGOS)('aritmética de columnas: Monto = PEN + USD×TC; Ticket cita × Citas = Monto; % Entrev. = realizadas ÷ resueltas; Proyectado = citas esperadas × tasas × ticket ($desde → $hasta)', rango => {
    for (const m of filasYTotal(calcularProyeccion(fuente(rango)))) {
      if (!m.citas.length) continue
      expect(m.monto).toBeCloseTo(m.montoPen + m.montoUsd * TC, 6)
      expect(m.ticket! * m.citas.length).toBeCloseTo(m.monto!, 6)
      expect(m.entrevistas.every(c => c.cita.estado === 'realizada')).toBe(true)
      expect(m.resueltas.every(c => c.cita.estado === 'realizada' || c.cita.estado === 'no_show')).toBe(true)
      expect(m.pctEntrevistas).toEqual(m.resueltas.length ? expect.closeTo(m.entrevistas.length / m.resueltas.length * 100, 9) : null)
      expect(m.convertidas.every(c => m.entrevistas.includes(c))).toBe(true)
      expect(m.personasClientes).toBeLessThanOrEqual(m.personasEntrevistadas)
      if (m.pctConversion !== null) expect(m.pctConversion).toBeCloseTo(m.personasClientes / m.personasEntrevistadas * 100, 9)
    }
    for (const f of calcularProyeccion(fuente(rango)).filas) {
      if (f.proyectado === null) continue
      expect(f.proyectado).toBeCloseTo(f.citasEsperadas! * (f.pctEntrevistas! / 100) * (f.pctConversion! / 100) * f.ticket!, 6)
    }
  })

  it('la cohorte es por fecha de CREACIÓN (día de Lima), nunca por fecha prevista', () => {
    const { citas } = lote()
    const hoja = calcularProyeccion(fuente(OCTUBRE))
    const esperadas = citas.filter(c => fechaLocalCitas(c.creadoEn!) >= OCTUBRE.desde && fechaLocalCitas(c.creadoEn!) <= OCTUBRE.hasta)
    expect(ids(hoja.total.citas)).toEqual(ids(esperadas.map(c => ({ cita: c }))))
    // En la cohorte hay citas previstas en noviembre; fuera de ella, citas previstas en octubre.
    expect(hoja.total.citas.some(c => c.cita.fecha > OCTUBRE.hasta)).toBe(true)
    expect(citas.some(c => c.fecha.startsWith('2026-10') && !esperadas.includes(c))).toBe(true)
  })

  it('USD sin tipo de cambio: «pendiente de TC», nunca un monto parcial en soles', () => {
    const hoja = calcularProyeccion(fuente(OCTUBRE, { tipoCambio: null }))
    expect(hoja.total.montoUsd).toBeGreaterThan(0)
    expect(hoja.total).toMatchObject({ pendienteTc: true, monto: null, ticket: null })
  })
})

// Misma palabra, misma cifra: con citas creadas, previstas y resueltas en el MISMO
// mes, la Proyección (mes entero) y Resultados cuentan las mismas citas y
// entrevistas, con la misma tasa de entrevistas y las mismas personas vinculadas a cliente.
describe('Proyección ↔ Resultados (avance mensual)', () => {
  function escenario(ventasFuera: Conversion[] = []) {
    // Creadas en septiembre; la prevista y la asistencia, el mismo día de Lima que la creación.
    const citas = lote().citas.filter(c => fechaLocalCitas(c.creadoEn!).startsWith('2026-09')).map(c => {
      const dia = fechaLocalCitas(c.creadoEn!)
      return { ...c, fecha: dia, hora: '18:00', ...(c.asistioEn ? { asistioEn: `${dia}T23:00:00Z` } : {}) }
    })
    // Ventas de septiembre, todas registradas DESPUÉS de su entrevista (la regla vieja las contaba todas):
    // la fecha comercial va después, el mismo día, antes del día de la entrevista o falta.
    const tope = (f: string) => f > SEPTIEMBRE.hasta ? SEPTIEMBRE.hasta : f
    const conversiones = [...citas.filter(c => c.estado === 'realizada').map((c, i) => venta(c, `${tope(sumarDias(c.fecha, 2))}T23:30:00Z`,
      [tope(sumarDias(c.fecha, 2)), c.fecha, sumarDias(c.fecha, -1), null][i % 4]!)), ...ventasFuera]
    const leads = [...new Set(citas.map(c => c.leadId))]
    const gestion: GestionCitas = {
      citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones: [],
      avance: {
        control: { version: 1, mes_inicio: '2026-09', configuracion: { ...controlCitasInicial(), base_avance: 'actividad_real',
          conteo_entrevistas: 'citas_realizadas', base_depositos: 'personas_entrevistadas', mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: '2026-09' } },
        poblacion: leads.map(lead_id => ({ lead_id, nombre: lead_id, telefono: '900000000', origen: 'formulario', moneda: 'PEN' as const,
          monto_estimado: 1000, registro_manual: false, creado_por: null, analista_origen_id: null, analista_origen_nombre: 'Sin analista',
          supervisor_origen_id: null, supervisor_origen_nombre: 'Sin supervisor', primera_asignacion_en: null })),
        conversiones, capital: [],
      },
    }
    const resultados = calcularAvanceCitas(gestion, citas, defaults('2026-09'), HOY, TC)
    // Igual que la pantalla: las conversiones y la población del lector del avance.
    const proyeccion = calcularProyeccion({ citas, filtros: { equipo: '' }, rango: SEPTIEMBRE, corte: HOY, tipoCambio: TC,
      conversiones: gestion.avance!.conversiones, poblacion: gestion.avance!.poblacion })
    return { citas, conversiones, resultados, proyeccion }
  }

  it('Citas, entrevistas, resueltas y % Entrev. (base «actividad real»): iguales en el total y por analista', () => {
    const { citas, resultados, proyeccion } = escenario()
    expect(citas.length).toBeGreaterThan(20)
    const t = proyeccion.total, r = resultados.total
    expect([t.citas.length, t.entrevistas.length, t.resueltas.length]).toEqual([r.citas, r.entrevistas, r.resueltas])
    expect(t.citas.length).toBeGreaterThan(t.resueltas.length) // hay citas sin resultado: no entran en la base
    expect(t.pctEntrevistas! / 100).toBeCloseTo(r.tasaEntrevistas!, 12)
    expect(proyeccion.filas.length).toBe(resultados.filas.length)
    for (const f of proyeccion.filas) {
      const rf = resultados.filas.find(x => x.id === f.id)!
      expect([f.id, f.citas.length, f.entrevistas.length, f.resueltas.length]).toEqual([rf.id, rf.citas, rf.entrevistas, rf.resueltas])
      expect(f.pctEntrevistas! / 100).toBeCloseTo(rf.tasaEntrevistas!, 12)
    }
  })

  it('% Conv.: las mismas personas vinculadas a cliente, en el total y por analista', () => {
    const { citas, conversiones, resultados, proyeccion } = escenario()
    const t = proyeccion.total, r = resultados.total
    // El escenario tiene ventas que la regla vieja (convertido_en ≥ asistencia) contaba y Resultados no.
    const asistencia = new Map(citas.filter(c => c.asistioEn).map(c => [c.leadId, Date.parse(c.asistioEn!)]))
    const vieja = conversiones.filter(c => asistencia.has(c.lead_id) && Date.parse(c.convertido_en) >= asistencia.get(c.lead_id)!)
    expect(vieja.length).toBeGreaterThan(r.clientes)
    expect(r.clientes).toBeGreaterThan(0)
    expect([t.personasEntrevistadas, t.personasClientes]).toEqual([r.unicas, r.clientes])
    expect(new Set(t.convertidas.map(c => c.cita.leadId))).toEqual(new Set(r.vinculados.map(c => c.lead_id)))
    expect(t.pctConversion! / 100).toBeCloseTo(r.conversion!, 12)
    for (const f of proyeccion.filas) {
      const rf = resultados.filas.find(x => x.id === f.id)!
      expect([f.id, f.personasEntrevistadas, f.personasClientes]).toEqual([rf.id, rf.unicas, rf.clientes])
    }
  })

  it('diferencia a propósito: una venta del mes siguiente cuenta en la Proyección (sigue su cohorte hasta el corte) y no en Resultados del mes', () => {
    const base = escenario()
    const sinVenta = base.proyeccion.total.entrevistas.find(e => !base.proyeccion.total.convertidas.includes(e))!
    const tardia = venta(sinVenta.cita, '2026-10-05T15:00:00Z', '2026-10-05')
    const { resultados, proyeccion } = escenario([tardia])
    expect(proyeccion.total.personasClientes).toBe(base.proyeccion.total.personasClientes + 1)
    expect(resultados.total.clientes).toBe(base.resultados.total.clientes)
  })
})

// Fusión de meses: una cita que llega en dos meses (el lector entrega el historial
// de los leads de su cohorte) cuenta UNA vez, por id de cita.
describe('Fusión de meses del rango', () => {
  const crudo = (id: string, lead: string, creado: string, vence: string) => ({
    id, lead_id: lead, nombre: 'X', telefono: '1', analista_id: '00000000-0000-4000-8000-000000000001', analista_nombre: 'A',
    supervisor_id: null, supervisor_nombre: 'S', vence_en: vence, estado: 'pendiente' as const, estado_comercial: 'programada' as const,
    cancelada_por: null, modalidad: 'virtual', origen: 'formulario', moneda: 'PEN' as const, monto_estimado: 1000, resultado: 'sin_clasificar',
    nota: '', reagendada_de: null, creado_en: creado, asistencia_registrada_en: null, cierre_posterior: false, es_cliente: false,
  })
  const mes = (desde: string, hasta: string, citas: ReturnType<typeof crudo>[]) => ({
    version: 1, periodo: { desde, hasta }, generado_en: HOY, citas, citas_clientes: 0, disponibilidad_depositos: 'sin_registro', depositos: [],
  }) as unknown as ConsultaCitasRpc

  it('una cita creada el 30/09 con fecha en noviembre, presente en septiembre y octubre, cuenta una vez', () => {
    const L1 = '00000000-0000-4000-8000-0000000000a1', L2 = '00000000-0000-4000-8000-0000000000a2'
    const C1 = '00000000-0000-4000-8000-0000000000c1', C2 = '00000000-0000-4000-8000-0000000000c2', C3 = '00000000-0000-4000-8000-0000000000c3'
    const c1 = crudo(C1, L1, '2026-09-30T20:00:00Z', '2026-11-05T15:00:00Z')
    const c2 = crudo(C2, L1, '2026-10-02T20:00:00Z', '2026-10-03T15:00:00Z') // mismo lead, otra cita: NO se colapsa
    const c3 = crudo(C3, L2, '2026-10-05T20:00:00Z', '2026-10-06T15:00:00Z')
    const fusion = fusionarConsultasCitas([mes('2026-09-01', '2026-09-30', [c1]), mes('2026-10-01', '2026-10-31', [c1, c2, c3])])
    expect(fusion.citas.map(c => c.id).sort()).toEqual([C1, C2, C3])
    const hoja = calcularProyeccion({ citas: fusion.citas, filtros: { equipo: '' }, rango: { desde: '2026-09-25', hasta: '2026-10-19' }, corte: HOY,
      tipoCambio: TC, conversiones: null, tiempo: 'semanas' })
    expect(hoja.total.citas.length).toBe(3)
    // S4 25–30 set · S1 1–7 oct · S2 · S3: la cita fusionada cae una sola vez, en la semana de su creación.
    expect(hoja.total.porTramo.map(l => l.length)).toEqual([1, 2, 0, 0])
  })
})
```

## Contexto: reglas de Resultados (app/src/components/citas/avance.ts, líneas 41–135) y fecha-comercial.ts
```ts
export function calcularAvanceCitas(gestion: GestionCitas, todas: CitaEjemplo[], filtros: FiltrosCitas, corte: string, tipoCambio: number | null | undefined) {
  const datos = gestion.avance!
  const valoracion = datos.valoracion
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
    && ambito(owner(c.lead_id, c.analista_id)) && actividad(c.lead_id, owner(c.lead_id, c.analista_id))
    && ventaComercialDelMes(c, filtros.mes, corte))
  // Todo el capital del mes cuenta para el ticket: contratos nuevos, upgrades,
  // renovaciones y cooperativas, atribuidos al analista del núcleo (Miguel,
  // 15/09/2026: «nada debe quedar fuera»). No exige que el cliente venga de un
  // lead. Los filtros de persona, origen, registro y moneda estimada acotan el
  // capital a los leads que los cumplen; sin ellos entra todo lo cerrado.
  const acotaPersonas = Boolean(normalizar(filtros.q) || filtros.leadId || filtros.origen || filtros.registro || filtros.moneda)
  const capitalPeriodo = datos.capital.filter(k => (!acotaPersonas || (k.lead_id !== null && personas.has(k.lead_id)))
    && Date.parse(k.fecha) >= periodo.inicio && Date.parse(k.fecha) <= periodo.fin)
  const capitalMes = capitalPeriodo.filter(k => ambito(k.analista_id))
  // Personas con capital en el mes, antes del recorte por analista o equipo: un
  // cliente convertido por Ana cuyo contrato firmó Luis no «carece» de capital.
  const conCapital = new Set(capitalPeriodo.map(personaCapital))
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
      && entrevistaCompatibleConVenta(v.asistioEn, c.fecha_comercial)))
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
    const cierresTicket = datos.conversiones.filter(c => personas.has(c.lead_id) && ambito(c.analista_id)
      && (!id || c.analista_id === id) && actividad(c.lead_id, c.analista_id)
      && ventaComercialDelMes(c, filtros.mes, corte))
    const capital = capitalMes.filter(k => !id || k.analista_id === id)
    const capitalPerfiles = new Set(capital.map(personaCapital))
    const operaciones: OperacionesCapital = { nuevos: 0, upgrades: 0, renovaciones: 0, cooperativas: 0 }
    for (const k of capital) operaciones[TIPOS_CAPITAL[k.tipo ?? 'contrato_nuevo']]++
/** Fechas comerciales sin hora: comparar por día de Lima, nunca por UTC. */
export const fechaLocalCitas = (fecha: string) => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date(fecha))

/** Una fecha comercial no acredita el orden intradía. Sí excluye días posteriores. */
export function entrevistaCompatibleConVenta(asistencia: string | undefined, fechaComercial: string | null): boolean {
  return Boolean(fechaComercial && asistencia && Number.isFinite(Date.parse(asistencia))
    && fechaLocalCitas(asistencia) <= fechaComercial)
}

export function ventaComercialDelMes(
  venta: { fecha_comercial: string | null; convertido_en: string }, mes: string, corte: string,
): boolean {
  return venta.fecha_comercial !== null && venta.fecha_comercial.startsWith(`${mes}-`)
    && venta.fecha_comercial <= fechaLocalCitas(corte)
    && Date.parse(venta.convertido_en) <= Date.parse(corte)
}
```
