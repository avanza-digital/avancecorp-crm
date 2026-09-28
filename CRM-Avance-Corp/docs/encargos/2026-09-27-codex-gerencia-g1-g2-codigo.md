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

# Encargo: REFUTAR el CÓDIGO de la pantalla de GERENCIA (G1 operación + G2 equipo) — LEVEL 2

Rutas relativas a `CRM-Avance-Corp/app/`. El plan v2 (tras tu revisión del plan: 4 P1 + 4 P2, todos incorporados)
está transcrito abajo. Busca dónde el CÓDIGO no cumple el plan o rompe algo: números que no abren su lista exacta,
foco/lector de pantalla, selección automática vs ruta, umbrales, 42501 global, «fuera», autores inactivos/sin autor,
detalle al entrar y su actualización, regresiones en el SUPERVISOR por las piezas compartidas (barra-equipo,
estilos-gestion, tabla-equipo-diaria, panel-analista-supervisor, resumen-analista, registro-actividad).

## Decisiones del dueño (NO son hallazgos)
- «Aplica para gerencia las mejoras del supervisor»: cifras finas (no tablero) que abren su lista; tabla y ficha
  protagonistas; ficha con borde azul/sombra/cabecera teñida; cifras-filtro dentro del equipo.
- G4 aparte: gerencia NO tiene permiso sobre `gestion_diaria_pendientes_fn` (el ámbito exige supervisor) → la ficha de
  gerencia va SIN pestaña Pendientes; «Citas» y «Vencidas» por equipo abren el desglose por analista, no tareas.
- G0 (modo demo de gerencia) lo hace otra rama en paralelo; G3 (Registro general, Hábitos y Comparar días con la
  escala del diseño) viene después: aquí el registro general sigue siendo el completo (filtros + CSV).

## Verificación del PRIMARY
- `npm run check` PASS (lint + typecheck + 4634 pruebas + build + bundle + duplicados).
- Unitarias de gerencia reescritas (21) y de la lógica (9). E2E de gerencia en migración (otra rama).

## Plan de la pantalla de GERENCIA — v2 tras Codex (27/09, ESPERANDO OK de Miguel)

Pedido de Miguel: «las mejoras que ya hemos hecho, aplícalas para gerencia». Diseño: `vista-previa/avance-gerencia.png`.
Codex (plan v1): CHANGES_REQUESTED — 4 P1 + 4 P2; todo incorporado aquí. Encargo y respuesta en `docs/encargos/`.

**Hechos comprobados en el código:**
- El detalle por analista de gerencia ES la consulta del supervisor (`gestion_diaria_equipo_fn(dia, null)`): dentro de
  un equipo se reutilizan la tabla y la ficha nuevas.
- `gestion_diaria_pendientes_core` llama al ámbito con el id de QUIEN CONSULTA y exige que sea supervisor activo:
  con gerencia devuelve 42501 (y dispararía el retiro global de la vista). Pendientes para gerencia = migración de
  permisos (LEVEL 3) → fase aparte G4.
- «Citas agendadas» = tareas `reunion` CREADAS ese día (no actividades): el registro no es su lista exacta.
- Seguimiento no admite filtros por enlace.

**G1 — «Toda la operación» (nivel operación):**
- Cabecera como el supervisor (título con el día elegido, fecha que se aplica al cambiar, «Hoy», «Seguimiento
  completo ›», «Registro general», «Actualizado», «Actualizar», «i» con definiciones y «Comparar días» de las 8).
- 4 cifras compactas (no tablero): Llamadas, Contacto, Citas agendadas, Sin registro, con «Ayer/Día anterior X ·
  Referencia Y (N jornadas)». Destinos EXACTOS: Llamadas y Contacto → Registro general en «Llamadas» (con el
  resultado de cada llamada visible y la definición contestaron ÷ útiles); Sin registro → lista en el panel de las
  personas activas con 0 gestiones (cada una abre su equipo con ella elegida); Citas → la tabla de equipos
  ordenada por Citas (desglose; la lista de citas creadas queda para G4). Vencidas totales → equipos ordenados por
  vencidas.
- Tabla de equipos protagonista (filas de 52 px): avatar, «Equipo de X» + «N analistas · N sin registro»,
  Llamadas, Contacto (% + nivel), Citas, Vencidas, Atención (analistas DISTINTOS con `requiere_atencion`), Primer
  intento y Dispersión (se conserva la comparación y el orden entre equipos), buscador y «Con atención». «fuera»
  al final. Los números de cada fila abren el equipo con ese filtro u orden.
- Panel del equipo (ficha protagonista): cabecera teñida, avatar relleno, nombre 22 px, 4 cuadros 28 px con las
  cifras AUTORITATIVAS del pulso, «Necesitan atención» (persona → equipo con ella elegida), primer intento y
  dispersión, «Ver el equipo». Barras por hora: solo de los analistas activos y rotuladas así; si no cuadran con
  el total del equipo se dice cuántas llamadas son de otros autores.
- Selección de la ficha SEPARADA de la ruta del equipo: la automática (equipo que más atención necesita) solo
  elige ficha, sin mover el foco; cerrar la apaga; al estrechar se cierra; las aperturas manuales devuelven el foco.
- El detalle se carga al entrar, se actualiza con «Actualizar» aunque no haya ruta, y mientras llega «Atención»
  dice «…», nunca 0. Umbral de dos columnas por ancho del contenedor (tabla mínima + 360 px), como el supervisor.

**G2 — Dentro del equipo:** la pantalla del supervisor (filtros-cifra, buscador, tabla nueva con la columna
Pendientes de gerencia, ficha protagonista con Resumen y Registro compacto) SIN pestaña Pendientes hasta G4; los
avisos de vencidas se muestran sin enlace. Se conservan «Otros autores de los registros» y los registros sin autor.
42501 de cualquier fuente → retiro global de la vista (como hoy).

**G3 — Registro general, Hábitos y Comparar días** con la escala del diseño, conservando filtros de equipo, analista y
etapa y el CSV.

**G4 (opcional, LEVEL 3, plan propio):** migración para que gerencia consulte pendientes por analista (y lista de
citas creadas del día) → pestaña Pendientes y listas exactas de vencidas y citas.

**Ver en local:** el modo demo no tiene gerencia. Miguel entra con su cuenta real en la copia local (solo mirar);
yo reviso con capturas E2E.

## DIFF (git diff 9c08305d c7021744 -- CRM-Avance-Corp/app/src, sin pruebas)

```diff
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/barra-equipo.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/barra-equipo.tsx
new file mode 100644
index 00000000..a1656d10
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/barra-equipo.tsx
@@ -0,0 +1,65 @@
+// Barra de la tabla de analistas (diseño de Gestión Diaria, 27/09/2026): el
+// resumen del equipo SON los filtros —cada número abre su lista en la tabla— y
+// el buscador. La comparten el supervisor y gerencia dentro de un equipo.
+import type { JSX } from 'react'
+import { Check, Search } from 'lucide-react'
+import { Input } from '@/components/ui/input'
+import type { EstadoEquipo, FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
+import { cn } from '@/lib/utils'
+import { CONTROL, PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA } from './estilos-gestion'
+
+export type Pildora = EstadoEquipo | 'atencion'
+const PILDORAS: readonly { valor: Pildora; etiqueta: string }[] = [
+  { valor: 'todos', etiqueta: 'Todos' }, { valor: 'con_registro', etiqueta: 'Con registro' },
+  { valor: 'sin_registro', etiqueta: 'Sin registro' }, { valor: 'con_pendientes', etiqueta: 'Con pendientes' },
+  { valor: 'atencion', etiqueta: 'Necesitan atención' },
+]
+
+export interface ConteosEquipo { analistas: number; con_actividad: number; sin_actividad: number; con_pendientes: number }
+
+/** Las MISMAS reglas que el filtro (`resumenEquipo`): el número es la lista. */
+function conteoPildora(p: Pildora, r: ConteosEquipo, atencion: number): number {
+  return p === 'todos' ? r.analistas : p === 'con_registro' ? r.con_actividad : p === 'sin_registro' ? r.sin_actividad
+    : p === 'con_pendientes' ? r.con_pendientes : atencion
+}
+
+const pildoraDe = (f: FiltrosEquipo): Pildora => f.soloProblemas ? 'atencion' : f.estado ?? 'todos'
+/** Cada cifra es del equipo entero: abrirla limpia la búsqueda, así la lista ES esa cifra (Codex, 27/09). */
+const aplicarPildora = (f: FiltrosEquipo, p: Pildora): FiltrosEquipo =>
+  ({ ...f, busqueda: '', estado: p === 'atencion' ? 'todos' : p, soloProblemas: p === 'atencion' })
+
+export function BarraEquipo({ filtros, setFiltros, conteos, atencion }: {
+  filtros: FiltrosEquipo
+  setFiltros: (cambio: (f: FiltrosEquipo) => FiltrosEquipo) => void
+  conteos: ConteosEquipo
+  atencion: number
+}): JSX.Element {
+  const pildora = pildoraDe(filtros)
+  return (
+    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
+      {/* El resumen del equipo SON los filtros: cada número abre su lista en la
+          tabla (Miguel, 27/09: la jerarquía es de la tabla y de la ficha). */}
+      <div role="group" aria-label="Resumen del equipo" className="flex flex-wrap items-center gap-1.5">
+        {PILDORAS.map((p) => {
+          const activa = pildora === p.valor
+          const n = conteoPildora(p.valor, conteos, atencion)
+          return (
+            <button key={p.valor} type="button" aria-pressed={activa} onClick={() => setFiltros((f) => aplicarPildora(f, p.valor))}
+              className={cn(PILDORA, activa ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
+              {activa && <Check aria-hidden className="size-3.5" />}{p.etiqueta}{' '}
+              {p.valor === 'atencion' && n > 0
+                // Ámbar y no rojo: mezcla vencidas con cortes y tiempo sin llamar (Codex, 27/09).
+                ? <span className="grid min-w-5 place-items-center rounded-full bg-[var(--warning-text)] px-1.5 text-[11px] font-bold tabular-nums text-white">{n}</span>
+                : <span className="font-bold tabular-nums">{n}</span>}
+            </button>
+          )
+        })}
+      </div>
+      <label className="relative ml-auto min-w-40 max-w-[220px] flex-1"><span className="sr-only">Buscar analista</span>
+        <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
+        <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista…"
+          className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
+      </label>
+    </div>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/cifras-operacion.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/cifras-operacion.tsx
new file mode 100644
index 00000000..5e3001d3
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/cifras-operacion.tsx
@@ -0,0 +1,50 @@
+// Las 4 cifras de la operación (decisión de Miguel, 27/09/2026) en una franja
+// FINA: la jerarquía es de la tabla de equipos y de la ficha, como en el
+// supervisor. Cada número abre su lista exacta (revisión Codex del plan):
+// Llamadas y Contacto → Registro general en «Llamadas» (con el resultado de cada
+// llamada); Citas → los equipos ordenados por citas; Sin registro → quiénes son.
+import type { JSX } from 'react'
+import { cifraPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
+import { referenciaCifra } from '@/lib/gestion-diaria-operacion'
+import { cn } from '@/lib/utils'
+import { FOCO } from './estilos-gestion'
+
+export type DestinoCifra = 'llamadas' | 'contacto' | 'citas' | 'sin_registro'
+
+export function CifrasOperacion({ pulso, esHoy, abrir }: {
+  pulso: PulsoGerencia
+  esHoy: boolean
+  abrir: (destino: DestinoCifra, origen: HTMLElement) => void
+}): JSX.Element {
+  const a = pulso.actual
+  const cifras: { destino: DestinoCifra; etiqueta: string; valor: string; detalle: string; referencia: string; accion: string }[] = [
+    { destino: 'llamadas', etiqueta: 'Llamadas', valor: cifraPulso(a.llamadas), detalle: `${a.contestadas} contestaron`,
+      referencia: referenciaCifra(pulso, 'llamadas', esHoy), accion: 'Ver las llamadas en el registro general' },
+    { destino: 'contacto', etiqueta: 'Contacto', valor: a.tasa_contacto === null ? '—' : `${Math.round(a.tasa_contacto)} %`, detalle: `de ${a.utiles} útiles`,
+      referencia: referenciaCifra(pulso, 'tasa_contacto', esHoy, true), accion: 'Ver las llamadas y su resultado en el registro general' },
+    { destino: 'citas', etiqueta: 'Citas agendadas', valor: cifraPulso(a.citas_agendadas), detalle: esHoy ? 'hoy' : 'ese día',
+      referencia: referenciaCifra(pulso, 'citas_agendadas', esHoy), accion: 'Ver los equipos ordenados por citas' },
+    { destino: 'sin_registro', etiqueta: 'Sin registro', valor: `${a.sin_actividad} de ${a.analistas_activos}`, detalle: 'analistas',
+      referencia: referenciaCifra(pulso, 'sin_actividad', esHoy), accion: 'Ver quiénes no tienen registro' },
+  ]
+  return (
+    <section aria-label="Cifras de la operación" className="shrink-0 rounded-2xl border border-border bg-card">
+      <dl className="grid grid-cols-2 lg:grid-cols-4">
+        {cifras.map((c, i) => (
+          <div key={c.destino} className={cn('min-w-0 px-5 py-2.5', i % 2 === 1 && 'border-l border-border',
+            i === 2 && 'lg:border-l lg:border-border', i >= 2 && 'border-t border-border lg:border-t-0')}>
+            <dt className="text-[11.5px] font-bold uppercase tracking-[0.04em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
+            <dd className="mt-0.5 flex flex-wrap items-baseline gap-x-2">
+              <button type="button" onClick={(e) => abrir(c.destino, e.currentTarget)} aria-label={`${c.etiqueta}: ${c.valor}. ${c.accion}`}
+                className={cn('cursor-pointer rounded-md text-[22px] font-extrabold leading-tight tabular-nums text-primary underline-offset-4 hover:underline pointer-coarse:min-h-11', FOCO)}>
+                {c.valor}
+              </button>
+              <span className="text-xs text-[var(--muted-foreground-strong)]">{c.detalle}</span>
+            </dd>
+            <dd className="text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{c.referencia}</dd>
+          </div>
+        ))}
+      </dl>
+    </section>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/comparacion-equipos-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/comparacion-equipos-gerencia.tsx
deleted file mode 100644
index e9cd1add..00000000
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/comparacion-equipos-gerencia.tsx
+++ /dev/null
@@ -1,71 +0,0 @@
-/* oxlint-disable jsx-a11y/no-redundant-roles, jsx-a11y/no-interactive-element-to-noninteractive-role -- Conserva la semántica de tabla en WebKit al apilar celdas. */
-/* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar las columnas con el teclado. */
-import { useState } from 'react'
-import { ArrowDown, ArrowUp, ListFilter, Search } from 'lucide-react'
-import { cifraPulso, type EquipoPulso } from '@/lib/gestion-diaria-pulso'
-import { hashDe } from '@/lib/router'
-import { Input } from '@/components/ui/input'
-import { Button } from '@/components/ui/button'
-
-type Orden = 'nombre' | 'llamadas' | 'contacto' | 'sin_actividad' | 'vencidas' | 'primer_intento' | 'dispersion'
-const COLUMNAS: { orden: Orden; titulo: string }[] = [
-  { orden: 'nombre', titulo: 'Equipo' }, { orden: 'llamadas', titulo: 'Llamadas' },
-  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'sin_actividad', titulo: 'Sin actividad' },
-  { orden: 'vencidas', titulo: 'Vencidas' }, { orden: 'primer_intento', titulo: 'Primer intento vencido' },
-  { orden: 'dispersion', titulo: 'Dispersión de contacto' },
-]
-function valor(e: EquipoPulso, orden: Exclude<Orden, 'nombre'>) {
-  switch (orden) {
-    case 'llamadas': return e.metricas.llamadas
-    case 'contacto': return e.metricas.tasa_contacto
-    case 'sin_actividad': return e.metricas.sin_actividad
-    case 'vencidas': return e.tareas_vencidas
-    case 'primer_intento': return e.primer_intento_vencido
-    case 'dispersion': return e.dispersion.maximo === null || e.dispersion.minimo === null ? null : e.dispersion.maximo - e.dispersion.minimo
-  }
-}
-
-export function ComparacionEquiposGerencia({ equipos, abrir }: { equipos: EquipoPulso[]; abrir: (equipo: EquipoPulso, origen: HTMLElement) => void }) {
-  const [busqueda, setBusqueda] = useState('')
-  const [atencion, setAtencion] = useState(false)
-  const [orden, setOrden] = useState<Orden>('nombre')
-  const [ascendente, setAscendente] = useState(true)
-  const conAtencion = equipos.filter((e) => e.metricas.sin_actividad > 0 || e.tareas_vencidas > 0 || (e.primer_intento_vencido ?? 0) > 0)
-  const filas = equipos.filter((e) => e.nombre.toLocaleLowerCase('es').includes(busqueda.trim().toLocaleLowerCase('es'))
-    && (!atencion || conAtencion.includes(e)))
-    .toSorted((a, b) => {
-      const nombre = a.nombre.localeCompare(b.nombre, 'es')
-      if (orden === 'nombre') return nombre * (ascendente ? 1 : -1)
-      const va = valor(a, orden), vb = valor(b, orden)
-      if (va === null || vb === null) return va === vb ? nombre : va === null ? 1 : -1
-      return (va - vb) * (ascendente ? 1 : -1) || nombre
-    })
-  return <>
-    <div className="gd-filtros gp-filtros">
-      <div className="gd-busqueda"><Search aria-hidden /><Input type="search" aria-label="Buscar equipo" placeholder="Buscar equipo" className="min-h-11 pl-9 text-base" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} /></div>
-      <Button variant={atencion ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={atencion} onClick={() => setAtencion(!atencion)}><ListFilter aria-hidden />Con atención ({conAtencion.length})</Button>
-      <span className="gd-conteo">{filas.length} de {equipos.length} equipos</span>
-    </div>
-    <div className="gd-tabla-scroll ac-scroll" tabIndex={0} role="region" aria-label="Desplazar tabla de equipos"><table role="table" className="gp-tabla gp-tabla-equipos" aria-label="Resumen por supervisor">
-      <thead role="rowgroup"><tr role="row">{COLUMNAS.map((c) => <th role="columnheader" scope="col" key={c.orden} aria-sort={orden === c.orden ? ascendente ? 'ascending' : 'descending' : 'none'}>
-        <button type="button" onClick={() => { setOrden(c.orden); setAscendente(orden === c.orden ? !ascendente : c.orden === 'nombre') }} aria-label={`Ordenar equipos por ${c.titulo.toLocaleLowerCase('es')}`}>
-          {c.titulo}{orden === c.orden && (ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />)}
-        </button>
-      </th>)}</tr></thead>
-      <tbody role="rowgroup">
-        {filas.length === 0 && <tr role="row"><td role="cell" colSpan={7} className="gd-sin-filas">Ningún equipo coincide con estos filtros.</td></tr>}
-        {filas.map((e) => <tr role="row" key={e.clave}>
-          <th role="rowheader" scope="row"><a className="gp-nombre" aria-label={e.nombre} href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: e.clave })} onClick={(evento) => {
-            if (!evento.ctrlKey && !evento.metaKey && !evento.shiftKey && !evento.altKey) { evento.preventDefault(); abrir(e, evento.currentTarget) }
-          }}><span>{e.nombre}</span><span className="gp-metadato">{e.metricas.analistas_activos} analistas activos</span></a></th>
-          <td role="cell" data-etiqueta="Llamadas">{e.metricas.llamadas}</td>
-          <td role="cell" data-etiqueta="Contacto">{cifraPulso(e.metricas.tasa_contacto, true)}<p>{e.metricas.contestadas}/{e.metricas.utiles} útiles</p></td>
-          <td role="cell" data-etiqueta="Sin actividad">{e.metricas.sin_actividad}</td>
-          <td role="cell" data-etiqueta="Vencidas" className={e.tareas_vencidas ? 'text-[var(--danger-text)] font-semibold' : ''}>{e.tareas_vencidas}</td>
-          <td role="cell" data-etiqueta="Primer intento vencido">{cifraPulso(e.primer_intento_vencido)}{e.primer_intento_vencido === null && <p>SLA no activo</p>}</td>
-          <td role="cell" data-etiqueta="Dispersión de contacto">{e.dispersion.personas ? <>{cifraPulso(e.dispersion.minimo, true)}–{cifraPulso(e.dispersion.maximo, true)}<p>{e.dispersion.personas} con muestra</p></> : 'Muestra insuficiente'}</td>
-        </tr>)}
-      </tbody>
-    </table></div>
-  </>
-}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/detalle-analista.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/detalle-analista.tsx
deleted file mode 100644
index a26caec6..00000000
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/detalle-analista.tsx
+++ /dev/null
@@ -1,67 +0,0 @@
-import { useId } from 'react'
-import { Button } from '@/components/ui/button'
-import { FRANJA_LLAMADAS, barrasPorHora, horaLimaDe } from '@/lib/gestion-diaria-analista'
-import { horarioConfirmado, tiempoSinLlamar, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
-
-/** F4.2: explica la foto del servidor; no reconstruye cifras desde el store. */
-export function DetalleAnalista({ fila: f, dia, abrirLlamadas }: {
-  fila: FilaEquipoPresentada
-  dia: string
-  abrirLlamadas: () => void
-}) {
-  const id = useId()
-  const barras = barrasPorHora(f.marcador)
-  const contestadasPorHora = f.marcador.por_hora.reduce((total, h) => total + h.contestadas, 0)
-  const fuera = f.marcador.por_hora.filter((h) => h.hora < FRANJA_LLAMADAS.desde || h.hora > FRANJA_LLAMADAS.hasta).toSorted((a, b) => a.hora - b.hora)
-  return (
-    <div className="space-y-5 pb-3 text-base">
-      <dl className="gd-metricas-detalle">
-        {[
-          ['Llamadas útiles', f.marcador.utiles], ['Leads distintos', f.marcador.leads_tocados],
-          ['Llamadas por lead', f.llamadas_por_lead ?? '—'], ['Citas pendientes del día', f.citas_hoy],
-          ['Primera llamada', horaLimaDe(f.marcador.primera_llamada_en)], ['Última llamada', horaLimaDe(f.marcador.ultima_llamada_en)],
-          ['Tiempo sin llamar', tiempoSinLlamar(f.minutos_sin_llamar)], ['Última gestión', horaLimaDe(f.ultima_gestion_en)],
-        ].map(([titulo, valor]) => <div key={titulo}><dt className="text-[var(--muted-foreground-strong)]">{titulo}</dt><dd className="mt-1 font-semibold tabular-nums">{valor}</dd></div>)}
-      </dl>
-      <div className="space-y-3 border-t border-border pt-4">
-        <h3 id={`${id}-horas`} className="font-semibold text-primary">Llamadas por hora de {f.nombre_completo}</h3>
-        <p className="text-[var(--muted-foreground-strong)]">{dia} · Hora de Lima. Llamadas / contestadas en cada hora.</p>
-        {!horarioConfirmado(f.marcador) ? (
-          <p role="status">No se pudo confirmar el desglose por hora. Consulta las llamadas en el registro; no se muestran ceros como sustituto.</p>
-        ) : f.marcador.llamadas === 0 ? (
-          <p>No hay llamadas registradas ese día. Esto no indica ausencia ni descarta otras gestiones.</p>
-        ) : (
-          <>
-            <div role="img" aria-label="Llamadas y contestadas de 08 a 20 horas. Cifras completas en el desplegable siguiente.">
-              <div aria-hidden className="gd-grafico-horas">
-                {barras.map((b) => <div key={b.hora} className="relative flex h-20 items-end border-b border-border">
-                  <span className="w-full rounded-t bg-primary" style={{ height: `${b.llamadas / b.maximo * 100}%` }} />
-                  <span className="absolute bottom-0 left-1/4 w-1/2 rounded-t bg-accent" style={{ height: `${b.contestadas / b.maximo * 100}%` }} />
-                </div>)}
-              </div>
-              <div aria-hidden className="mt-2 flex justify-between tabular-nums"><span>08 h</span><span>14 h</span><span>20 h</span></div>
-            </div>
-            <p>Llamadas: azul oscuro · Contestadas: azul</p>
-            <details className="gd-cifras-horas">
-              <summary>Ver cifras por hora</summary>
-              <ol aria-labelledby={`${id}-horas`}>
-                {barras.map((b) => <li key={b.hora}>De {b.hora}:00 a {b.hora}:59: {b.llamadas} llamadas, {b.contestadas} contestadas</li>)}
-              </ol>
-            </details>
-            {contestadasPorHora !== f.marcador.contestadas && (
-              <p className="text-[var(--muted-foreground-strong)]">Las contestadas por hora incluyen registros de «Número errado» o «No es la persona» que el total de contacto útil excluye.</p>
-            )}
-            {fuera.length > 0 && (
-              <p className="text-[var(--muted-foreground-strong)]">Fuera de la franja 08–20: {fuera.map((h) => `${String(h.hora).padStart(2, '0')} h: ${h.llamadas} ${h.llamadas === 1 ? 'llamada' : 'llamadas'} / ${h.contestadas} ${h.contestadas === 1 ? 'contestada' : 'contestadas'}`).join('; ')}.</p>
-            )}
-          </>
-        )}
-        <div className="flex flex-wrap items-center gap-4">
-          <Button variant="outline" className="min-h-11 text-base" onClick={abrirLlamadas}
-            aria-label={`Ver llamadas del día de ${f.nombre_completo}`}>Ver llamadas del día</Button>
-          <p className="max-w-2xl text-[var(--muted-foreground-strong)]">En el registro puedes leer cada resultado y abrir la ficha del lead. Se consulta al abrirlo y sólo muestra actividades cuyos leads siguen visibles para tu sesión; puede diferir de esta foto.</p>
-        </div>
-      </div>
-    </div>
-  )
-}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/espacio-pulso-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/espacio-pulso-gerencia.tsx
deleted file mode 100644
index 2d27df54..00000000
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/espacio-pulso-gerencia.tsx
+++ /dev/null
@@ -1,179 +0,0 @@
-import { useEffect, useId, useRef, useState, type RefObject, type MouseEvent } from 'react'
-import { ArrowLeft, ListFilter, Search } from 'lucide-react'
-import { type PulsoGerencia, type EquipoPulso, cifraPulso } from '@/lib/gestion-diaria-pulso'
-import { filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
-import { hashDe } from '@/lib/router'
-import type { useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
-import { Button } from '@/components/ui/button'
-import { Input } from '@/components/ui/input'
-import { Tabs } from '@/components/ui/tabs'
-import { PanelCargando } from '@/components/common/estado-panel'
-import { TablaEquipoDiaria } from './tabla-equipo-diaria'
-import { DetalleAnalista } from './detalle-analista'
-import { RegistroActividad } from './registro-actividad'
-import { PanelGerencia } from './panel-gerencia'
-import { ComparacionEquiposGerencia } from './comparacion-equipos-gerencia'
-import { ErrorConsultaGerencia } from './error-consulta-gerencia'
-
-type Ruta = { tipo: 'equipo' | 'analista'; id: string } | undefined
-type Consulta = ReturnType<typeof useDetallePulso>
-const FILTROS: FiltrosEquipo = { busqueda: '', soloProblemas: false, orden: 'atencion', ascendente: false }
-const PESTANAS = [{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }] as const
-const rutaEquipo = (grupo: EquipoPulso) => hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: grupo.clave })
-const navegarEnVentana = (e: MouseEvent<HTMLAnchorElement>) => !e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey
-
-/** La tabla conserva su estado al cambiar de analista y al abrir la ficha de un lead. */
-export function EspacioPulsoGerencia({ datos, ruta, consulta, actualizacion, estrecho, general, cerrarGeneral, abrirGeneral, rutaEnfocada, oculto, setOculto, origenGeneral, sinPermiso }: {
-  datos: PulsoGerencia; ruta: Ruta; consulta: Consulta; actualizacion: number; estrecho: boolean
-  general: boolean; cerrarGeneral: () => void; abrirGeneral: () => void
-  rutaEnfocada: RefObject<string | null>
-  oculto: string | null; setOculto: (clave: string | null) => void
-  origenGeneral: RefObject<HTMLButtonElement | null>
-  sinPermiso: () => void
-}) {
-  const grupo = datos.equipos.find((e) => ruta?.tipo === 'equipo' ? e.clave === ruta.id : e.personas.some((p) => p.analista_id === ruta?.id))
-  const persona = ruta?.tipo === 'analista' ? grupo?.personas.find((p) => p.analista_id === ruta.id) : null
-  const [filtrosPorEquipo, setFiltrosPorEquipo] = useState<Record<string, FiltrosEquipo>>({})
-  const filtros = grupo ? filtrosPorEquipo[grupo.clave] ?? FILTROS : FILTROS
-  const cambiarFiltros = (cambio: (actual: FiltrosEquipo) => FiltrosEquipo) => {
-    if (grupo) setFiltrosPorEquipo((todos) => ({ ...todos, [grupo.clave]: cambio(todos[grupo.clave] ?? FILTROS) }))
-  }
-  const [ampliado, setAmpliado] = useState(false)
-  const [generalVisitado, setGeneralVisitado] = useState(general)
-  if (general && !generalVisitado) setGeneralVisitado(true)
-  const titulo = useRef<HTMLHeadingElement>(null)
-  const tituloTabla = useRef<HTMLHeadingElement>(null)
-  const origen = useRef<HTMLElement | null>(null)
-  const clave = ruta ? `${ruta.tipo}:${ruta.id}` : null
-  const abierto = general || Boolean(ruta && oculto !== clave)
-  const anchoAnterior = useRef(estrecho)
-  const id = useId()
-  useEffect(() => {
-    const ampliarDesdeMovil = anchoAnterior.current && !estrecho
-    anchoAnterior.current = estrecho
-    if (ampliarDesdeMovil && ruta?.tipo === 'equipo' && oculto === clave) setOculto(null)
-  }, [estrecho, ruta?.tipo, oculto, clave, setOculto])
-  useEffect(() => {
-    if (clave && clave !== rutaEnfocada.current && abierto) titulo.current?.focus({ preventScroll: true })
-    rutaEnfocada.current = clave
-  }, [clave, abierto, rutaEnfocada])
-  useEffect(() => { if (general) titulo.current?.focus({ preventScroll: true }) }, [general])
-  const recordarOrigen = (control?: HTMLElement | null) => {
-    const activo = control ?? document.activeElement
-    origen.current = activo instanceof HTMLElement && activo !== document.body ? activo : null
-  }
-  const devolverFoco = (registroGeneral: boolean) => requestAnimationFrame(() => {
-    // Una interacción posterior tiene prioridad sobre el retorno pendiente.
-    const activo = document.activeElement
-    if (activo instanceof HTMLElement && activo !== document.body && activo.matches('input,select,textarea')) return
-    const destino = registroGeneral ? origenGeneral.current : origen.current?.isConnected ? origen.current : tituloTabla.current
-    destino?.focus({ preventScroll: true })
-    if (document.activeElement !== destino) tituloTabla.current?.focus({ preventScroll: true })
-  })
-  const cerrar = () => {
-    setAmpliado(false)
-    if (general) cerrarGeneral()
-    else if (ruta?.tipo === 'analista' && grupo) { setOculto(`equipo:${grupo.clave}`); window.location.hash = rutaEquipo(grupo) }
-    else setOculto(clave)
-    devolverFoco(general)
-  }
-  const abrirEquipo = (e: EquipoPulso, control?: HTMLElement) => {
-    recordarOrigen(control); cerrarGeneral(); setAmpliado(false)
-    setOculto(estrecho ? `equipo:${e.clave}` : null)
-    rutaEnfocada.current = `equipo:${e.clave}`
-    window.location.hash = rutaEquipo(e)
-    requestAnimationFrame(() => tituloTabla.current?.focus({ preventScroll: true }))
-  }
-  const volverOperacion = (e: MouseEvent<HTMLAnchorElement>) => {
-    if (!navegarEnVentana(e)) return
-    e.preventDefault(); cerrarGeneral(); setOculto(null); setAmpliado(false)
-    window.location.hash = hashDe('gestion-diaria')
-    requestAnimationFrame(() => tituloTabla.current?.focus({ preventScroll: true }))
-  }
-  const abrirAnalista = (analista: string, control?: HTMLElement) => {
-    const fila = Array.from(tituloTabla.current?.closest('section')?.querySelectorAll<HTMLElement>('tr[data-analista]') ?? []).find((n) => n.dataset.analista === analista)
-    recordarOrigen(control ?? fila?.querySelector<HTMLElement>('button')); cerrarGeneral(); setOculto(null)
-    rutaEnfocada.current = `analista:${analista}`
-    window.location.hash = hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: analista })
-  }
-  const filas = consulta.datos && grupo ? presentarEquipo(consulta.datos).filter((f) => grupo.personas.some((p) => p.analista_id === f.analista_id)) : []
-  const mostradas = filtrarOrdenarEquipo(filas, filtros)
-  const nombre = persona ? persona.nombre_completo ?? 'Autor no disponible' : grupo?.nombre ?? 'Detalle no disponible'
-  return <div className="gd-espacio gp-espacio" data-estrecho={estrecho}>
-    <section className="gd-equipo" aria-label={grupo ? 'Analistas del equipo' : 'Equipos de la operación'}>
-      <div className="gp-tabla-cabecera">
-        <div>{grupo && <a className="gp-volver" href={hashDe('gestion-diaria')} onClick={volverOperacion}><ArrowLeft aria-hidden />Toda la operación</a>}
-          <h3 ref={tituloTabla} tabIndex={-1}>{grupo?.nombre ?? 'Equipos y atención actual'}</h3></div>
-        {grupo && <Button variant="outline" className="min-h-11 text-base" onClick={() => { recordarOrigen(); cerrarGeneral(); setOculto(null); titulo.current?.focus() }}>Ver detalle</Button>}
-      </div>
-      <div className="gp-comparacion" hidden={Boolean(grupo)} inert={Boolean(grupo)}><ComparacionEquiposGerencia equipos={datos.equipos} abrir={abrirEquipo} /></div>
-      {grupo && <>
-        <div className="gd-filtros gp-filtros">
-          <div className="gd-busqueda"><Search aria-hidden /><Input type="search" aria-label="Buscar analista del equipo" placeholder="Buscar analista" className="min-h-11 pl-9 text-base" value={filtros.busqueda} onChange={(e) => cambiarFiltros((f) => ({ ...f, busqueda: e.target.value }))} /></div>
-          <Button variant={filtros.soloProblemas ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={filtros.soloProblemas} onClick={() => cambiarFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}><ListFilter aria-hidden />Con atención ({filas.filter((f) => f.requiere_atencion).length})</Button>
-          <span className="gd-conteo">{mostradas.length} de {filas.length} analistas</span>
-        </div>
-        {consulta.error ? <ErrorConsultaGerencia error={consulta.error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} /> : consulta.cargando ? <PanelCargando /> : <>
-          {persona?.activo && !mostradas.some((f) => f.analista_id === persona.analista_id) && <p className="gd-seleccion-oculta">La selección no aparece con los filtros actuales.</p>}
-          <TablaEquipoDiaria filas={mostradas} filtros={filtros} ordenar={(orden) => cambiarFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : true }))}
-            seleccion={persona?.analista_id ?? null} seleccionar={(f) => abrirAnalista(f.analista_id)} panelId={id} irAlDetalle={() => { setOculto(null); titulo.current?.focus() }} minimo={datos.minimo_llamadas_utiles} />
-          {grupo.personas.some((p) => !p.activo) && <div className="gp-otros-autores"><h4>Otros autores de los registros</h4><ul>{grupo.personas.filter((p) => !p.activo).map((p) => <li key={p.analista_id ?? 'sin-autor'}>{p.analista_id
-            ? <button type="button" onClick={(e) => abrirAnalista(p.analista_id!, e.currentTarget)}>{p.nombre_completo ?? 'Autor no disponible'}</button> : 'Sin autor'}: {p.llamadas} llamadas · {p.citas_agendadas} citas agendadas</li>)}</ul>
-            {grupo.personas.some((p) => p.analista_id === null) && <Button variant="outline" className="min-h-11 text-base" onClick={abrirGeneral}>Ver registros sin autor en el registro general</Button>}
-          </div>}
-        </>}
-      </>}
-    </section>
-    <PanelGerencia id={id} titulo={general ? 'Registro general del día' : ruta ? nombre : 'Detalle de la operación'} abierto={abierto} estrecho={estrecho} ampliado={ampliado}
-      ampliar={() => setAmpliado((v) => !v)} cerrar={cerrar} tituloRef={titulo} vacio="Elige un equipo para comparar a sus analistas y consultar sus registros.">
-      {generalVisitado && <section className="gd-panel-cuerpo gp-registro" hidden={!general} inert={!general} aria-label="Registro general de la operación">
-        <RegistroActividad dia={datos.dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial="todo" actualizacion={actualizacion} onSinPermiso={sinPermiso} />
-      </section>}
-      {ruta && <div className="gp-detalle-contenido" hidden={general} inert={general}>
-        <nav aria-label="Ruta de la operación" className="gp-ruta"><a href={hashDe('gestion-diaria')} onClick={volverOperacion}>Toda la operación</a>{ruta.tipo === 'analista' && grupo && <a href={rutaEquipo(grupo)} onClick={(e) => { if (navegarEnVentana(e)) { e.preventDefault(); abrirEquipo(grupo, e.currentTarget) } }}>{grupo.nombre}</a>}</nav>
-        <DetallePulsoGerencia key={`${ruta.tipo}:${ruta.id}`} datos={datos} grupo={grupo} seleccion={ruta} consulta={consulta} actualizacion={actualizacion} abrirGeneral={abrirGeneral} sinPermiso={sinPermiso} />
-      </div>}
-    </PanelGerencia>
-  </div>
-}
-
-function DetallePulsoGerencia({ datos, grupo, seleccion, consulta, actualizacion, abrirGeneral, sinPermiso }: {
-  datos: PulsoGerencia; grupo: EquipoPulso | undefined; seleccion: NonNullable<Ruta>; consulta: Consulta; actualizacion: number; abrirGeneral: () => void; sinPermiso: () => void
-}) {
-  const persona = seleccion.tipo === 'analista' ? grupo?.personas.find((p) => p.analista_id === seleccion.id) : null
-  const personas = seleccion.tipo === 'equipo' ? grupo?.personas ?? [] : persona ? [persona] : []
-  const ids = personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id])
-  const fila = consulta.datos && persona ? presentarEquipo(consulta.datos).find((f) => f.analista_id === persona.analista_id) : undefined
-  const [pestana, setPestana] = useState<'resumen' | 'registro'>('resumen')
-  const [registroVisitado, setRegistroVisitado] = useState(false)
-  const abrirRegistro = () => { setPestana('registro'); setRegistroVisitado(true) }
-  if (!grupo || (seleccion.tipo === 'analista' && !persona)) return <p role="status" className="gd-panel-cuerpo">Este equipo o autor ya no aparece en el ámbito actual. Vuelve a toda la operación.</p>
-  if (consulta.error) return <ErrorConsultaGerencia error={consulta.error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} />
-  if (consulta.cargando) return <PanelCargando />
-  return <Tabs etiqueta="Detalle gerencial" className="gd-pestanas-panel" tamano="grande" pestanas={PESTANAS} valor={pestana} onCambio={(v) => { setPestana(v); if (v === 'registro') setRegistroVisitado(true) }}>
-    <div className="gd-panel-cuerpo" hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
-      {seleccion.tipo === 'equipo' && <>
-        <p>{grupo.metricas.analistas_activos} analistas activos · {datos.dia}</p>
-        <dl className="gd-metricas-detalle">{[
-          ['Llamadas', grupo.metricas.llamadas], ['Contacto', cifraPulso(grupo.metricas.tasa_contacto, true)],
-          ['Llamadas útiles', grupo.metricas.utiles], ['Contestadas', grupo.metricas.contestadas],
-          ['Sin actividad', grupo.metricas.sin_actividad], ['Leads distintos', grupo.metricas.leads_unicos],
-          ['Llamadas por lead', cifraPulso(grupo.metricas.llamadas_por_lead)], ['Citas agendadas', grupo.metricas.citas_agendadas],
-          ['Tareas vencidas actuales', grupo.tareas_vencidas], ['Primer intento vencido', grupo.primer_intento_vencido ?? 'SLA no activo'],
-        ].map(([etiqueta, valor]) => <div key={etiqueta}><dt>{etiqueta}</dt><dd className="font-semibold">{valor}</dd></div>)}</dl>
-        <Button variant="outline" className="min-h-11 text-base" onClick={abrirRegistro}>Ver registro del equipo</Button>
-      </>}
-      {persona && <>
-        <p className="gd-resumen-principal"><strong>{persona.llamadas}</strong> llamadas del día</p>
-        {fila && <DetalleAnalista fila={fila} dia={datos.dia} abrirLlamadas={abrirRegistro} />}
-        {!persona.activo && <p>Autor fuera del organigrama comercial activo: {persona.llamadas} llamadas, {persona.utiles} útiles, {persona.contestadas} contestadas.</p>}
-        {persona.activo && !fila && <p role="status">El analista ya no aparece en la consulta actual del equipo. Actualiza la operación para confirmar su ámbito.</p>}
-      </>}
-      {personas.some((p) => p.analista_id === null) && <p className="mt-4">Los registros sin autor se consultan en el <button type="button" className="gp-enlace" onClick={abrirGeneral}>registro general del día</button>.</p>}
-    </div>
-    {registroVisitado && <div className="gd-panel-cuerpo gp-registro" hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
-      {ids.length ? <RegistroActividad dia={datos.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial="llamadas" actualizacion={actualizacion} onSinPermiso={sinPermiso} />
-        : <p>Consulta estos registros desde el <button type="button" className="gp-enlace" onClick={abrirGeneral}>registro general del día</button>.</p>}
-    </div>}
-  </Tabs>
-}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/estilos-gestion.ts b/CRM-Avance-Corp/app/src/components/gestion-diaria/estilos-gestion.ts
new file mode 100644
index 00000000..3549e76e
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/estilos-gestion.ts
@@ -0,0 +1,14 @@
+// Escala del diseño de Gestión Diaria (27/09/2026) compartida por supervisor y
+// gerencia: controles compactos que crecen a 44 px en pantallas táctiles.
+export const CONTROL = 'h-9 text-[13px] pointer-coarse:h-11'
+export const BOTON_CABECERA = 'inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50 aria-disabled:hover:bg-card pointer-coarse:h-11'
+export const BOTON_ICONO = 'grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] text-[var(--muted-foreground-strong)] transition-colors hover:bg-muted hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:size-11'
+export const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
+/** La ficha protagonista (Miguel, 27/09): borde azul, sombra y cabecera teñida. */
+export const FICHA = 'flex min-h-0 min-w-0 flex-1 flex-col overflow-clip rounded-2xl border border-accent/30 bg-card shadow-[0_14px_34px_-18px_rgba(17,30,61,0.35)]'
+export const CABECERA_FICHA = 'flex shrink-0 items-center gap-3.5 border-b border-accent/15 bg-accent/[0.06] px-5 py-4'
+export const TITULO_FICHA = 'rounded-md text-[22px] font-extrabold leading-tight tracking-[-0.015em] text-primary [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
+/** Pastilla de filtro con número (la cifra ES el filtro). */
+export const PILDORA = 'inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-full border px-3 text-[13px] font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11'
+export const PILDORA_ACTIVA = 'border-accent bg-accent text-accent-foreground'
+export const PILDORA_INACTIVA = 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-border-strong hover:text-primary'
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
index d923b279..f9541dd2 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
@@ -25,7 +25,7 @@ type PestanaPanel = 'resumen' | 'registro' | 'pendientes'
 
 const BOTON_ICONO = 'grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] text-[var(--muted-foreground-strong)] transition-colors hover:bg-muted hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:size-11'
 
-export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, tituloRef, ampliado, ampliar, cerrar, puedeAmpliar, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, vacio, silencioso = false }: {
+export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, tituloRef, ampliado, ampliar, cerrar, puedeAmpliar, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, vacio, silencioso = false, conPendientes = true, idsEquipo = null, subtitulo = 'Analista de tu equipo' }: {
   id: string
   seleccion: SeleccionSupervisor | null
   fila: FilaEquipoPresentada | undefined
@@ -46,6 +46,11 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
   vacio?: string | undefined
   /** Selección automática: sus cargas y errores no se anuncian (el usuario no la abrió). */
   silencioso?: boolean
+  /** Gerencia (27/09): sin pestaña Pendientes hasta tener permiso sobre esa consulta (G4). */
+  conPendientes?: boolean
+  /** Alcance del registro del equipo; null = lo que la sesión puede ver (el equipo del supervisor). */
+  idsEquipo?: readonly string[] | null
+  subtitulo?: string
 }) {
   const equipo = seleccion?.analista === null
   const nombre = seleccion && !equipo ? fila?.nombre_completo ?? seleccion.nombre ?? 'Analista' : null
@@ -62,7 +67,7 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
             {/* El espacio va FUERA del texto oculto: dentro se perdía («Detalle deANA»). */}
             {nombre !== null ? <><span className="sr-only">Detalle de</span>{' '}{nombre}</> : titulo}
           </h3></TituloDialogo>
-          {nombre !== null && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">Analista de tu equipo</p>}
+          {nombre !== null && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{subtitulo}</p>}
         </div>
         {seleccion && <div className="flex shrink-0 gap-0.5">
           {puedeAmpliar && <button type="button" className={BOTON_ICONO} aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden className="size-4" /> : <Maximize2 aria-hidden className="size-4" />}</button>}
@@ -71,7 +76,7 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
       </header>
       {!seleccion ? <div className="flex flex-1 flex-col items-center justify-center gap-3 px-8 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
         <Users className="size-9 text-muted-foreground" aria-hidden /><p>{vacio ?? 'Selecciona un analista de la tabla para consultar su día.'}</p></div>
-        : <ContenidoSeleccionado key={`${seleccion.analista ?? 'equipo'}:${seleccion.apertura}`} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo}
+        : <ContenidoSeleccionado key={`${seleccion.analista ?? 'equipo'}:${seleccion.apertura}`} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo} conPendientes={conPendientes} idsEquipo={idsEquipo}
           tituloRef={tituloRef} oculta={oculta} limpiar={limpiar} actualizacion={actualizacion} revalidar={revalidar} esHoy={esHoy} ahora={ahora} silencioso={silencioso} />}
     </section>
   )
@@ -79,7 +84,7 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
 
 const FECHA_TITULO = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })
 
-function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, silencioso }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor; esHoy: boolean; ahora: number; silencioso: boolean }) {
+function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, silencioso, conPendientes, idsEquipo }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor; esHoy: boolean; ahora: number; silencioso: boolean; conPendientes: boolean; idsEquipo: readonly string[] | null }) {
   const equipo = seleccion.analista === null
   const [pestana, setPestana] = useState<PestanaPanel>(equipo || seleccion.enfocar ? 'registro' : 'resumen')
   const [registro, setRegistro] = useState<{ pestana: PestanaRegistro; apertura: number } | null>(equipo || seleccion.enfocar ? { pestana: seleccion.pestana, apertura: 0 } : null)
@@ -116,7 +121,7 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
     <div ref={cuerpoResumen} className={cn(cuerpo, 'space-y-5')} hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
       {!fila || minimo === undefined ? <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">El resumen no está disponible. El registro conserva su consulta independiente.</p>
         : <ResumenAnalista fila={fila} dia={dia} minimo={minimo} esHoy={esHoy} ahora={ahora}
-          abrirLlamadas={() => abrirRegistro('llamadas')} abrirPendientes={abrirPendientes} />}
+          abrirLlamadas={() => abrirRegistro('llamadas')} abrirPendientes={conPendientes ? abrirPendientes : undefined} />}
       {seleccion.analista !== null && <>
         <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} silencioso={silencioso} />
         <div className="space-y-2">
@@ -136,11 +141,11 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
           {esHoy ? 'Actividad de hoy' : `Actividad del ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
         </h4>
         <RegistroActividad compacto encabezadoExterno={tituloRegistro} key={registro.apertura} dia={dia} pestanaInicial={registro.pestana}
-          analistaIds={seleccion.analista === null ? null : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
+          analistaIds={seleccion.analista === null ? idsEquipo : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
       </section>}
     </div>
     <div className={cuerpo} hidden={pestana !== 'pendientes'} inert={pestana !== 'pendientes'}>
-      {pendientes && seleccion.analista !== null && <PendientesSupervisor key={pendientes.apertura}
+      {conPendientes && pendientes && seleccion.analista !== null && <PendientesSupervisor key={pendientes.apertura}
         analista={seleccion.analista} nombre={fila?.nombre_completo ?? seleccion.nombre ?? 'Analista'} dia={dia} fila={fila}
         visible={pestana === 'pendientes'} soloVencidasInicial={pendientes.soloVencidas} apertura={pendientes.apertura}
         enfocar={pendientes.enfocar} actualizacion={actualizacion} revalidar={revalidar} />}
@@ -153,7 +158,7 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
         así el texto tras el último control se alcanza sin ratón. */}
     {equipo ? <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">{contenido}</div>
       : <Tabs etiqueta="Detalle del analista" variante="subrayado" valor={pestana} onCambio={cambiar}
-        pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, { valor: 'pendientes', etiqueta: 'Pendientes' }]}
+        pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, ...(conPendientes ? [{ valor: 'pendientes' as const, etiqueta: 'Pendientes' }] : [])]}
         className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]]:px-5 [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm pointer-coarse:[&>[role=tablist]>[role=tab]]:min-h-11"
         clasePanel="ac-scroll min-h-0 flex-1 overflow-y-auto focus-visible:!-outline-offset-2">{contenido}</Tabs>}
   </>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
new file mode 100644
index 00000000..03cd359f
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
@@ -0,0 +1,222 @@
+// Panel de «Toda la operación» (diseño de Gestión Diaria, 27/09/2026): la ficha
+// protagonista del equipo —como la del analista en el supervisor—, la lista de
+// quienes no tienen registro y el registro (general o del equipo). Las cifras del
+// equipo son las del pulso; el detalle solo aporta atención y barras de sus
+// analistas activos, y lo dice (revisión Codex del plan).
+import type { JSX, ReactNode, RefObject } from 'react'
+import { Title as TituloDialogo } from '@radix-ui/react-dialog'
+import { ChevronRight, ClipboardList, Maximize2, Minimize2, UserX, Users, X } from 'lucide-react'
+import { Avatar } from '@/components/ui/avatar'
+import { cifraPulso, type EquipoPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
+import { atencionEquipo, barrasEquipo, nombreEquipo, personasSinRegistro, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
+import { presentarAtencion, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
+import type { PestanaRegistro } from '@/lib/gestion-diaria'
+import { cn } from '@/lib/utils'
+import { BarrasPorHora } from './barras-por-hora'
+import { RegistroActividad } from './registro-actividad'
+import { BOTON_ICONO, CABECERA_FICHA, FICHA, FOCO, TITULO_FICHA } from './estilos-gestion'
+
+export type VistaOperacion =
+  | { tipo: 'equipo'; clave: string }
+  | { tipo: 'sin_registro' }
+  | { tipo: 'registro'; alcance: 'general' | string; pestana: PestanaRegistro; apertura: number }
+
+export type { PresetEquipo } from '@/lib/gestion-diaria-operacion'
+
+const ENLACE = cn('mt-1.5 inline-flex min-h-6 cursor-pointer items-center gap-0.5 rounded-md text-xs font-semibold text-[var(--accent-press)] hover:underline pointer-coarse:min-h-11', FOCO)
+const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`
+
+function Cuadro({ etiqueta, children }: { etiqueta: string; children: ReactNode }): JSX.Element {
+  return (
+    <div className="min-w-0 rounded-xl bg-muted/70 px-3.5 py-3">
+      <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</dt>
+      <dd className="mt-1 min-w-0">{children}</dd>
+    </div>
+  )
+}
+
+export function PanelOperacionGerencia({ id, vista, pulso, detalle, esHoy, tituloRef, ampliado, puedeAmpliar, ampliar, cerrar, abrirVista, entrarEquipo, abrirPersona, actualizacion, revocar }: {
+  id: string
+  vista: VistaOperacion | null
+  pulso: PulsoGerencia
+  /** Filas del detalle de la operación; null mientras no llega. */
+  detalle: FilaEquipoPresentada[] | null
+  esHoy: boolean
+  tituloRef: RefObject<HTMLHeadingElement | null>
+  ampliado: boolean
+  puedeAmpliar: boolean
+  ampliar: () => void
+  cerrar: () => void
+  abrirVista: (vista: VistaOperacion) => void
+  entrarEquipo: (clave: string, preset?: PresetEquipo) => void
+  abrirPersona: (analistaId: string) => void
+  actualizacion: number
+  revocar: () => void
+}): JSX.Element {
+  const equipo = vista?.tipo === 'equipo' || (vista?.tipo === 'registro' && vista.alcance !== 'general')
+    ? pulso.equipos.find((e) => e.clave === (vista.tipo === 'equipo' ? vista.clave : vista.alcance)) : undefined
+  const nombre = equipo ? nombreEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre }) : ''
+  const titulo = vista === null ? 'Detalle de la operación' : vista.tipo === 'sin_registro' ? 'Sin registro'
+    : vista.tipo === 'registro' ? vista.alcance === 'general' ? 'Registro general' : `Registro del ${nombre}` : nombre
+  const subtitulo = vista === null ? null : vista.tipo === 'sin_registro'
+    ? `${plural(pulso.actual.sin_actividad, 'analista sin ninguna gestión', 'analistas sin ninguna gestión')} ${esHoy ? 'hoy' : 'ese día'}`
+    : equipo ? `${plural(equipo.metricas.analistas_activos, 'analista', 'analistas')} · ${equipo.metricas.con_actividad} con registro${esHoy ? ' hoy' : ''}` : esHoy ? 'Hoy' : pulso.dia
+  return (
+    <section id={id} aria-label={vista?.tipo === 'equipo' ? `Detalle del ${nombre}` : titulo} className={FICHA}>
+      <header className={CABECERA_FICHA}>
+        {vista?.tipo === 'equipo' && equipo ? <Avatar nombre={equipo.nombre} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
+          : <span aria-hidden="true" className="grid size-11 shrink-0 place-items-center rounded-full bg-card text-primary">
+            {vista?.tipo === 'sin_registro' ? <UserX className="size-5" /> : vista?.tipo === 'registro' ? <ClipboardList className="size-5" /> : <Users className="size-5" />}
+          </span>}
+        <div className="min-w-0 flex-1">
+          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className={TITULO_FICHA}>
+            {vista?.tipo === 'equipo' ? <><span className="sr-only">Detalle del</span>{' '}{nombre}</> : titulo}
+          </h3></TituloDialogo>
+          {subtitulo && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{subtitulo}</p>}
+        </div>
+        {vista && <div className="flex shrink-0 gap-0.5">
+          {puedeAmpliar && <button type="button" className={BOTON_ICONO} aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden className="size-4" /> : <Maximize2 aria-hidden className="size-4" />}</button>}
+          <button type="button" className={BOTON_ICONO} aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden className="size-[18px]" /></button>
+        </div>}
+      </header>
+      <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">
+        {vista === null ? <div className="flex h-full flex-col items-center justify-center gap-3 px-8 py-10 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
+          <Users className="size-9 text-muted-foreground" aria-hidden /><p>Elige un equipo de la tabla para ver su día.</p></div>
+          : vista.tipo === 'equipo' ? equipo
+            ? <FichaEquipo equipo={equipo} nombre={nombre} detalle={detalle} esHoy={esHoy} abrirVista={abrirVista} entrarEquipo={entrarEquipo} abrirPersona={abrirPersona} />
+            : <p role="status" className="px-5 py-4 text-[13px]">Este equipo ya no aparece en la consulta. Elige otro de la tabla.</p>
+            : vista.tipo === 'sin_registro' ? <ListaSinRegistro pulso={pulso} esHoy={esHoy} abrirPersona={abrirPersona} />
+              : <RegistroOperacion key={`${vista.alcance}:${vista.apertura}`} vista={vista} pulso={pulso} equipo={equipo} titulo={titulo} actualizacion={actualizacion} revocar={revocar} abrirGeneral={() => abrirVista({ tipo: 'registro', alcance: 'general', pestana: 'todo', apertura: vista.apertura + 1 })} />}
+      </div>
+    </section>
+  )
+}
+
+function FichaEquipo({ equipo: e, nombre, detalle, esHoy, abrirVista, entrarEquipo, abrirPersona }: {
+  equipo: EquipoPulso; nombre: string; detalle: FilaEquipoPresentada[] | null; esHoy: boolean
+  abrirVista: (vista: VistaOperacion) => void; entrarEquipo: (clave: string, preset?: PresetEquipo) => void; abrirPersona: (analistaId: string) => void
+}): JSX.Element {
+  const m = e.metricas
+  const atencion = detalle ? atencionEquipo(detalle, e) : null
+  const barras = detalle ? barrasEquipo(detalle, e) : undefined
+  const llamadas = () => abrirVista({ tipo: 'registro', alcance: e.clave, pestana: 'llamadas', apertura: Date.now() })
+  return (
+    <div className="space-y-5 px-5 py-4 text-[13.5px]">
+      <dl className="grid grid-cols-2 gap-2.5">
+        <Cuadro etiqueta="Llamadas">
+          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.llamadas}</span>
+          <span className="block text-xs text-[var(--muted-foreground-strong)]">{plural(m.contestadas, 'contestó', 'contestaron')}</span>
+          <button type="button" onClick={llamadas} aria-label={`Ver las llamadas del ${nombre}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
+        </Cuadro>
+        <Cuadro etiqueta="Contacto">
+          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.tasa_contacto === null ? '—' : `${Math.round(m.tasa_contacto)} %`}</span>
+          <span className="block text-xs text-[var(--muted-foreground-strong)]">de {plural(m.utiles, 'llamada útil', 'llamadas útiles')}</span>
+          <button type="button" onClick={llamadas} aria-label={`Ver las llamadas y su resultado del ${nombre}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
+        </Cuadro>
+        <Cuadro etiqueta="Citas agendadas">
+          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.citas_agendadas}</span>
+          <span className="block text-xs text-[var(--muted-foreground-strong)]">{esHoy ? 'hoy' : 'ese día'}</span>
+          <button type="button" onClick={() => entrarEquipo(e.clave, 'citas')} aria-label={`Ver las citas por analista del ${nombre}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
+        </Cuadro>
+        <Cuadro etiqueta="Tareas vencidas">
+          <span className={cn('block text-[28px] font-extrabold leading-tight tabular-nums', e.tareas_vencidas > 0 ? 'text-[var(--destructive-text)]' : 'text-primary')}>{e.tareas_vencidas}</span>
+          <span className="block text-xs text-[var(--muted-foreground-strong)]">siguen pendientes</span>
+          <button type="button" onClick={() => entrarEquipo(e.clave, 'vencidas')} aria-label={`Ver las vencidas por analista del ${nombre}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
+        </Cuadro>
+      </dl>
+
+      <div className="space-y-1.5">
+        {barras === undefined ? <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">Consultando las llamadas por hora…</p>
+          : barras === null ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">No se pudo confirmar el desglose por hora de todos sus analistas; no se muestran ceros como sustituto.</p>
+            : <>
+              <BarrasPorHora porHora={barras.porHora} titulo="Llamadas por hora del equipo" apoyo={`de sus ${plural(barras.analistas, 'analista activo', 'analistas activos')}`} />
+              {barras.otros > 0 && <p className="text-xs text-[var(--muted-foreground-strong)]">{plural(barras.otros, 'llamada de otros autores no está', 'llamadas de otros autores no están')} en la gráfica.</p>}
+            </>}
+      </div>
+
+      <div className="space-y-2">
+        <h4 className="text-[15px] font-extrabold text-primary">Necesitan atención</h4>
+        {atencion === null ? <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">Consultando…</p>
+          : atencion.length === 0 ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">Nadie del equipo necesita atención ahora.</p>
+            // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+            : <ul role="list" aria-label="Necesitan atención" className="space-y-1.5">
+              {atencion.map((f) => {
+                const a = presentarAtencion(f)
+                return (
+                  <li key={f.analista_id}>
+                    <button type="button" onClick={() => abrirPersona(f.analista_id)}
+                      className={cn('flex min-h-11 w-full cursor-pointer items-center gap-2 rounded-xl border border-border px-3.5 py-2 text-left transition-colors hover:border-border-strong hover:bg-muted/50', FOCO)}>
+                      <span className="min-w-0 flex-1">
+                        <span className="text-sm font-bold text-primary [overflow-wrap:anywhere]">{f.nombre_completo}</span>{' '}
+                        <span className="text-[13px] font-semibold" style={{ color: a.tono === 'vencido' ? 'var(--destructive-text)' : 'var(--warning-text)' }}>{a.texto}</span>
+                        {a.mas > 0 && <span className="ml-1 text-xs text-[var(--muted-foreground-strong)]">+{a.mas}</span>}
+                        {a.lista.length > 1 && <span className="sr-only">: {a.lista.join('; ')}</span>}
+                      </span>
+                      <ChevronRight aria-hidden className="size-4 shrink-0 text-[var(--muted-foreground-strong)]" />
+                    </button>
+                  </li>
+                )
+              })}
+            </ul>}
+      </div>
+
+      <dl className="space-y-1 text-[13px]">
+        <div className="flex flex-wrap gap-x-1.5"><dt className="text-[var(--muted-foreground-strong)]">Primer intento tarde:</dt>
+          <dd className="font-semibold">{e.primer_intento_vencido === null ? 'seguimiento no activo' : plural(e.primer_intento_vencido, 'lead', 'leads')}</dd></div>
+        <div className="flex flex-wrap gap-x-1.5"><dt className="text-[var(--muted-foreground-strong)]">Contacto entre analistas:</dt>
+          <dd className="font-semibold">{e.dispersion.personas > 0 && e.dispersion.minimo !== null && e.dispersion.maximo !== null
+            ? `${cifraPulso(Math.round(e.dispersion.minimo))} % a ${cifraPulso(Math.round(e.dispersion.maximo))} % (${e.dispersion.personas} con muestra)` : 'muestra insuficiente'}</dd></div>
+      </dl>
+
+      <button type="button" onClick={() => entrarEquipo(e.clave)}
+        className={cn('flex h-11 w-full cursor-pointer items-center justify-center rounded-xl bg-accent text-sm font-bold text-accent-foreground transition-colors hover:bg-[var(--accent-press)]', FOCO)}>
+        Ver el equipo
+      </button>
+    </div>
+  )
+}
+
+function ListaSinRegistro({ pulso, esHoy, abrirPersona }: { pulso: PulsoGerencia; esHoy: boolean; abrirPersona: (analistaId: string) => void }): JSX.Element {
+  const personas = personasSinRegistro(pulso)
+  return (
+    <div className="space-y-3 px-5 py-4 text-[13.5px]">
+      {personas.length === 0 ? <p className="text-[var(--muted-foreground-strong)]">Todos los analistas tienen registro {esHoy ? 'hoy' : 'ese día'}.</p>
+        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+        : <ul role="list" aria-label="Analistas sin registro" className="space-y-1.5">
+          {personas.map((p) => (
+            <li key={p.analista_id}>
+              <button type="button" onClick={() => abrirPersona(p.analista_id)}
+                className={cn('flex min-h-11 w-full cursor-pointer items-center gap-2.5 rounded-xl border border-border px-3.5 py-2 text-left transition-colors hover:border-border-strong hover:bg-muted/50', FOCO)}>
+                <Avatar nombre={p.nombre} color="var(--accent-press)" />
+                <span className="min-w-0 flex-1">
+                  <span className="block text-sm font-bold text-primary [overflow-wrap:anywhere]">{p.nombre}</span>
+                  <span className="block text-xs text-[var(--muted-foreground-strong)]">{nombreEquipo({ fuera: p.clave === 'fuera', nombre: p.equipo })}</span>
+                </span>
+                <ChevronRight aria-hidden className="size-4 shrink-0 text-[var(--muted-foreground-strong)]" />
+              </button>
+            </li>
+          ))}
+        </ul>}
+      <p className="text-xs text-[var(--muted-foreground-strong)]">Sin registro significa sin llamadas, WhatsApp enviado, reunión realizada, nota ni conversión; no indica ausencia.</p>
+    </div>
+  )
+}
+
+function RegistroOperacion({ vista, pulso, equipo, titulo, actualizacion, revocar, abrirGeneral }: {
+  vista: Extract<VistaOperacion, { tipo: 'registro' }>; pulso: PulsoGerencia; equipo: EquipoPulso | undefined; titulo: string
+  actualizacion: number; revocar: () => void; abrirGeneral: () => void
+}): JSX.Element {
+  // El registro del equipo lleva a todos sus autores con id (activos e inactivos); los sin autor, al general.
+  const ids = equipo ? equipo.personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id]) : null
+  const sinAutor = equipo?.personas.some((p) => p.analista_id === null) ?? false
+  return (
+    <section aria-label="Registro seleccionado" className="space-y-3 px-5 py-4">
+      <h4 className="sr-only">{titulo}</h4>
+      {vista.alcance === 'general'
+        ? <RegistroActividad dia={pulso.dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
+        : ids && ids.length > 0 ? <RegistroActividad dia={pulso.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
+          : <p className="text-[13px]">Este equipo no tiene autores con registro propio.</p>}
+      {sinAutor && <p className="text-[13px]">Los registros sin autor se consultan en el <button type="button" className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)} onClick={abrirGeneral}>registro general del día</button>.</p>}
+    </section>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
index 54ba6f1d..9c483383 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
@@ -42,7 +42,8 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
   esHoy: boolean
   ahora: number
   abrirLlamadas: () => void
-  abrirPendientes: (soloVencidas: boolean) => void
+  /** Sin él (gerencia, hasta tener permiso sobre pendientes) las vencidas se dicen sin enlace. */
+  abrirPendientes?: ((soloVencidas: boolean) => void) | undefined
 }): JSX.Element {
   const atencion = presentarAtencion(f)
   const contacto = presentarContacto(f.marcador, minimo)
@@ -55,14 +56,18 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
       <p className="text-xs text-[var(--muted-foreground-strong)]">
         {plural(f.gestiones_hoy, 'gestión', 'gestiones')} · {FECHA_RESUMEN.format(new Date(`${dia}T12:00:00-05:00`))} · Lima
       </p>
-      {f.tareas_vencidas > 0 && (
+      {f.tareas_vencidas > 0 && (abrirPendientes ? (
         <button type="button" onClick={() => abrirPendientes(true)}
           className={cn('flex w-full cursor-pointer items-center gap-2.5 rounded-xl bg-destructive/10 px-4 py-3 text-left text-sm font-bold text-[var(--destructive-text)] transition-colors hover:bg-destructive/15', FOCO)}>
           <AlertCircle aria-hidden className="size-[18px] shrink-0" />
           <span className="flex-1">{plural(f.tareas_vencidas, 'tarea vencida', 'tareas vencidas')}</span>
           <ChevronRight aria-hidden className="size-4 shrink-0" />
         </button>
-      )}
+      ) : (
+        <p className="flex w-full items-center gap-2.5 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
+          <AlertCircle aria-hidden className="size-[18px] shrink-0" />{plural(f.tareas_vencidas, 'tarea vencida', 'tareas vencidas')}
+        </p>
+      ))}
       {otros.length > 0 && (
         // oxlint-disable-next-line jsx-a11y/no-redundant-roles
         <ul role="list" aria-label="Otros motivos de atención" className="space-y-1 rounded-xl bg-warning/10 px-4 py-2.5 text-[13px] font-semibold text-[var(--warning-text)]">
@@ -97,9 +102,9 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
           <span className={cn('block text-xs', f.tareas_vencidas > 0 ? 'font-semibold text-[var(--destructive-text)]' : 'text-[var(--muted-foreground-strong)]')}>
             {plural(f.tareas_vencidas, 'vencida', 'vencidas')}
           </span>
-          <button type="button" onClick={() => abrirPendientes(false)} aria-label={`Ver pendientes de ${f.nombre_completo}`} className={ENLACE}>
+          {abrirPendientes && <button type="button" onClick={() => abrirPendientes(false)} aria-label={`Ver pendientes de ${f.nombre_completo}`} className={ENLACE}>
             Ver pendientes<ChevronRight aria-hidden className="size-3.5" />
-          </button>
+          </button>}
         </Cuadro>
       </dl>
 
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx
index d72e09b9..3b654c85 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx
@@ -1,16 +1,10 @@
 import { ArrowDown, ArrowUp, ArrowRight } from 'lucide-react'
-import { COLOR_NIVEL, ETIQUETA_NIVEL, textoTasa } from '@/lib/gestion-diaria-analista'
-import { MOTIVOS_EQUIPO, presentarAtencion, presentarContacto, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
+import { COLOR_NIVEL, ETIQUETA_NIVEL } from '@/lib/gestion-diaria-analista'
+import { presentarAtencion, presentarContacto, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
 import { Avatar } from '@/components/ui/avatar'
 import { Badge } from '@/components/ui/badge'
 import { cn } from '@/lib/utils'
 
-const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
-  { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
-  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'pendientes', titulo: 'Pendientes' },
-  { orden: 'vencidas', titulo: 'Vencidas' }, { orden: 'atencion', titulo: 'Atención' },
-]
-
 interface PropsTabla {
   filas: readonly FilaEquipoPresentada[]
   filtros: FiltrosEquipo
@@ -20,58 +14,14 @@ interface PropsTabla {
   panelId: string
   irAlDetalle: () => void
   minimo: number
-  /** `gerencia` (por defecto): la tabla de siempre, con Pendientes. `supervisor`:
-   * el diseño de Gestión Diaria (27/09) — iniciales, Citas, atención en palabras.
-   * Gerencia no cambia hasta su propio plan (revisión Codex del plan supervisor). */
-  contexto?: 'gerencia' | 'supervisor' | undefined
-}
-
-/** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. */
-export function TablaEquipoDiaria({ contexto = 'gerencia', ...props }: PropsTabla) {
-  return contexto === 'supervisor' ? <TablaSupervisor {...props} /> : <TablaGerencia {...props} />
+  /** Gerencia dentro de un equipo compara también Pendientes (27/09). */
+  conPendientes?: boolean | undefined
 }
 
-function TablaGerencia({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: Omit<PropsTabla, 'contexto'>) {
-  return (
-    <div className="gd-tabla-scroll ac-scroll">
-      <table aria-label="Actividad y pendientes por analista" className="gd-tabla">
-        <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={`gd-col-${c.orden}`} />)}</colgroup>
-        <thead><tr>{COLUMNAS.map((c) => (
-          <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}>
-            <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}>
-              {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />)}
-            </button>
-          </th>
-        ))}</tr></thead>
-        <tbody>
-          {filas.length === 0 && <tr><td colSpan={6} className="gd-sin-filas">Ningún analista coincide con estos filtros.</td></tr>}
-          {filas.map((f) => {
-            const activa = f.analista_id === seleccion
-            const sinMuestra = f.marcador.nivel === null
-            const contacto = f.marcador.utiles === 0 ? '—' : sinMuestra ? 'Sin muestra' : `${f.marcador.tasa_contacto_pct} %`
-            const contextoContacto = f.marcador.utiles === 0 ? 'Sin llamadas útiles' : `${textoTasa(f.marcador)}; ${f.marcador.contestadas} de ${f.marcador.utiles} útiles; mínimo ${minimo}${sinMuestra ? '; sin muestra suficiente' : `; nivel ${ETIQUETA_NIVEL[f.marcador.nivel!]}`}`
-            return (
-              <tr key={f.analista_id} data-analista={f.analista_id} data-activa={activa}>
-                <th scope="row" className="gd-nombre"><div>
-                  <button type="button" aria-label={`Seleccionar a ${f.nombre_completo}`} aria-current={activa ? 'true' : undefined}
-                    aria-controls={panelId} onClick={() => seleccionar(f)}>{f.nombre_completo}</button>
-                  {activa && <button type="button" className="gd-ir-detalle" aria-label={`Ir al detalle de ${f.nombre_completo}`} onClick={irAlDetalle}><ArrowRight aria-hidden /></button>}
-                </div></th>
-                <td data-etiqueta="Llamadas">{f.marcador.llamadas}</td>
-                <td data-etiqueta="Contacto"><span style={f.marcador.nivel ? { color: COLOR_NIVEL[f.marcador.nivel] } : undefined}><span aria-hidden>{contacto}{f.marcador.nivel && <span className="gd-nivel-contacto">{ETIQUETA_NIVEL[f.marcador.nivel]}</span>}</span><span className="sr-only">{contextoContacto}</span></span></td>
-                <td data-etiqueta="Pendientes">{f.tareas_pendientes}</td>
-                <td data-etiqueta="Vencidas"><span className={f.tareas_vencidas > 0 ? 'text-[var(--danger-text)] font-semibold' : ''}>{f.tareas_vencidas}</span></td>
-                <td data-etiqueta="Atención"><span className={f.requiere_atencion ? 'gd-motivos' : 'text-[var(--muted-foreground-strong)]'}>
-                  {f.motivos_atencion.length ? `${f.motivos_atencion.length} ${f.motivos_atencion.length === 1 ? 'motivo' : 'motivos'}` : f.gestiones_hoy === 0 ? 'Sin registro' : 'Sin alertas'}
-                  {f.motivos_atencion.length > 0 && <span className="sr-only">: {f.motivos_atencion.map((m) => MOTIVOS_EQUIPO[m]).join('; ')}</span>}
-                </span></td>
-              </tr>
-            )
-          })}
-        </tbody>
-      </table>
-    </div>
-  )
+/** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. La
+ * usan el supervisor y gerencia dentro de un equipo (27/09): el diseño de Gestión Diaria. */
+export function TablaEquipoDiaria(props: PropsTabla) {
+  return <TablaSupervisor {...props} />
 }
 
 const COLUMNAS_SUPERVISOR: { orden: OrdenEquipo; titulo: string; ancho: string; derecha?: boolean }[] = [
@@ -88,15 +38,17 @@ const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visib
  * flecha «Ir al detalle»; en un contenedor estrecho (celular, zoom 200 %) las
  * filas se vuelven tarjetas con rótulos (`mi-equipo.css`), sin scroll lateral.
  */
-function TablaSupervisor({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: Omit<PropsTabla, 'contexto'>) {
+function TablaSupervisor({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo, conPendientes = false }: PropsTabla) {
+  const columnas = conPendientes ? COLUMNAS_SUPERVISOR.flatMap((c) => c.orden === 'citas'
+    ? [c, { orden: 'pendientes' as const, titulo: 'Pendientes', ancho: 'w-[84px]', derecha: true }] : [c]) : COLUMNAS_SUPERVISOR
   return (
-    <div className="gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-y-auto">
-      <table aria-label="Actividad y pendientes por analista" className="me-tabla w-full table-fixed border-separate border-spacing-0">
-        <colgroup>{COLUMNAS_SUPERVISOR.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
+    <div className={cn('gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-y-auto', conPendientes && '!overflow-x-auto')}>
+      <table aria-label="Actividad y pendientes por analista" className={cn('me-tabla w-full table-fixed border-separate border-spacing-0', conPendientes && '@min-[641px]:min-w-[760px]')}>
+        <colgroup>{columnas.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
         <thead className="sticky top-0 z-[1] bg-card">
-          <tr>{COLUMNAS_SUPERVISOR.map((c, i) => (
+          <tr>{columnas.map((c, i) => (
             <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}
-              className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === COLUMNAS_SUPERVISOR.length - 1 && 'pr-4')}>
+              className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === columnas.length - 1 && 'pr-4')}>
               <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}
                 className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
                   c.derecha && 'justify-end', filtros.orden === c.orden && 'text-primary')}>
@@ -106,7 +58,7 @@ function TablaSupervisor({ filas, filtros, ordenar, seleccion, seleccionar, pane
           ))}</tr>
         </thead>
         <tbody>
-          {filas.length === 0 && <tr><td colSpan={6} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún analista coincide con estos filtros.</td></tr>}
+          {filas.length === 0 && <tr><td colSpan={columnas.length} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún analista coincide con estos filtros.</td></tr>}
           {filas.map((f) => {
             const activa = f.analista_id === seleccion
             const contacto = presentarContacto(f.marcador, minimo)
@@ -141,6 +93,7 @@ function TablaSupervisor({ filas, filtros, ordenar, seleccion, seleccionar, pane
                   <span className="sr-only">{contacto.accesible}</span>
                 </td>
                 <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">{f.marcador.citas_agendadas}</td>
+                {conPendientes && <td data-etiqueta="Pendientes" className="px-2 text-right text-sm tabular-nums text-foreground">{f.tareas_pendientes}</td>}
                 <td data-etiqueta="Vencidas" className={cn('px-2 text-right text-sm font-semibold tabular-nums', f.tareas_vencidas > 0 ? 'text-[var(--destructive-text)]' : 'text-foreground')}>{f.tareas_vencidas}</td>
                 <td data-etiqueta="Atención" className="py-2 pl-4 pr-4 text-[13px]">
                   {atencion.texto === null
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
new file mode 100644
index 00000000..93ff65fa
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
@@ -0,0 +1,139 @@
+/* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar con el teclado las columnas que no caben. */
+// Tabla de equipos de «Toda la operación» (diseño de Gestión Diaria, 27/09/2026):
+// la protagonista. Misma forma que la del supervisor —tabla semántica con
+// `aria-sort`, filas de 52 px, botón de selección e «Ir al detalle»— y conserva
+// la comparación de gerencia: buscador, «Con atención», primer intento y
+// dispersión (revisión Codex del plan). Los números de cada fila abren el
+// equipo con ese filtro u orden: el número es la lista.
+import type { JSX } from 'react'
+import { ArrowDown, ArrowRight, ArrowUp, Check, Search } from 'lucide-react'
+import { Avatar } from '@/components/ui/avatar'
+import { Input } from '@/components/ui/input'
+import { cifraPulso } from '@/lib/gestion-diaria-pulso'
+import { nombreEquipo, type FilaEquipoOperacion, type FiltrosOperacion, type OrdenOperacion } from '@/lib/gestion-diaria-operacion'
+import { cn } from '@/lib/utils'
+import { CONTROL, FOCO, PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA } from './estilos-gestion'
+
+export type AccionEquipo = 'sin_registro' | 'vencidas' | 'atencion'
+
+const COLUMNAS: { orden: OrdenOperacion; titulo: string; ancho: string; derecha?: boolean }[] = [
+  { orden: 'nombre', titulo: 'Equipo', ancho: 'me-col-nombre' }, { orden: 'llamadas', titulo: 'Llamadas', ancho: 'w-[72px]', derecha: true },
+  { orden: 'contacto', titulo: 'Contacto', ancho: 'w-[96px]', derecha: true }, { orden: 'citas', titulo: 'Citas', ancho: 'w-[56px]', derecha: true },
+  { orden: 'vencidas', titulo: 'Vencidas', ancho: 'w-[72px]', derecha: true }, { orden: 'atencion', titulo: 'Atención', ancho: 'w-[116px]' },
+  { orden: 'primer_intento', titulo: 'Primer intento', ancho: 'w-[96px]', derecha: true }, { orden: 'dispersion', titulo: 'Dispersión', ancho: 'w-[104px]', derecha: true },
+]
+
+
+const ENLACE_CIFRA = cn('cursor-pointer rounded-md font-semibold tabular-nums underline-offset-2 hover:underline pointer-coarse:min-h-11', FOCO)
+
+export function TablaEquiposGerencia({ filas, total, conAtencion, sinDetalle = 'cargando', filtros, setFiltros, ordenar, seleccion, seleccionar, accion, panelId, irAlDetalle }: {
+  /** Ya filtradas y ordenadas. */
+  filas: FilaEquipoOperacion[]
+  total: number
+  /** Equipos con atención; null sin detalle. */
+  conAtencion: number | null
+  /** Por qué falta el detalle: mientras llega se dice «…»; si falló, «—» y «No disponible». */
+  sinDetalle?: 'cargando' | 'error'
+  filtros: FiltrosOperacion
+  setFiltros: (cambio: (f: FiltrosOperacion) => FiltrosOperacion) => void
+  ordenar: (orden: OrdenOperacion) => void
+  seleccion: string | null
+  seleccionar: (fila: FilaEquipoOperacion, origen: HTMLElement) => void
+  accion: (fila: FilaEquipoOperacion, tipo: AccionEquipo, origen: HTMLElement) => void
+  panelId: string
+  irAlDetalle: () => void
+}): JSX.Element {
+  return <>
+    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
+      <label className="relative min-w-40 max-w-[240px] flex-1"><span className="sr-only">Buscar equipo</span>
+        <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
+        <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar equipo…"
+          className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
+      </label>
+      <button type="button" aria-pressed={filtros.conAtencion} onClick={() => setFiltros((f) => ({ ...f, conAtencion: !f.conAtencion }))}
+        className={cn(PILDORA, filtros.conAtencion ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
+        {filtros.conAtencion && <Check aria-hidden className="size-3.5" />}Con atención{' '}
+        <span className="font-bold tabular-nums">{conAtencion ?? (sinDetalle === 'error' ? '—' : '…')}</span>
+      </button>
+      <p className="ml-auto text-xs text-[var(--muted-foreground-strong)]"><span role="status">{filas.length} de {total} equipos</span></p>
+    </div>
+    {/* Las dos últimas columnas desplazan dentro de la tabla, no la página. */}
+    <div className="gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-auto !overflow-x-auto" tabIndex={0} role="region" aria-label="Desplazar tabla de equipos">
+      <table aria-label="Equipos de la operación" className="me-tabla w-full table-fixed border-separate border-spacing-0 @min-[641px]:min-w-[860px]">
+        <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
+        <thead className="sticky top-0 z-[1] bg-card">
+          <tr>{COLUMNAS.map((c, i) => (
+            <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}
+              className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === COLUMNAS.length - 1 && 'pr-4')}>
+              <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar equipos por ${c.titulo.toLocaleLowerCase('es')}`}
+                className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
+                  c.derecha && 'justify-end', filtros.orden === c.orden && 'text-primary')}>
+                {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden className="size-3.5" /> : <ArrowDown aria-hidden className="size-3.5" />)}
+              </button>
+            </th>
+          ))}</tr>
+        </thead>
+        <tbody>
+          {filas.length === 0 && <tr><td colSpan={COLUMNAS.length} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún equipo coincide con estos filtros.</td></tr>}
+          {filas.map((f) => {
+            const activa = f.clave === seleccion
+            const nombre = nombreEquipo(f)
+            return (
+              <tr key={f.clave} data-equipo={f.clave} data-activa={activa}
+                className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
+                <th scope="row" className={cn('py-0 pl-4 pr-2 text-left font-normal', activa && 'shadow-[inset_3px_0_0_var(--color-accent)]')}>
+                  <div className="flex min-h-[52px] items-center gap-2.5">
+                    <Avatar nombre={f.nombre} color="var(--accent-press)" relleno={activa} />
+                    <div className="min-w-0 flex-1 py-1">
+                      <button type="button" aria-label={`Seleccionar ${nombre}`}
+                        aria-current={activa ? 'true' : undefined} aria-controls={panelId} onClick={(e) => seleccionar(f, e.currentTarget)}
+                        className={cn('block max-w-full cursor-pointer rounded-md text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
+                          activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{nombre}</button>
+                      <p className="text-[11.5px] text-[var(--muted-foreground-strong)]">
+                        {f.analistas} {f.analistas === 1 ? 'analista' : 'analistas'}
+                        {f.sinRegistro > 0 && <> · <button type="button" onClick={(e) => accion(f, 'sin_registro', e.currentTarget)}
+                          aria-label={`${f.sinRegistro} sin registro en ${nombre}: ver quiénes`} className={ENLACE_CIFRA}>{f.sinRegistro} sin registro</button></>}
+                      </p>
+                    </div>
+                    {activa && <button type="button" aria-label={`Ir al detalle de ${nombre}`} onClick={irAlDetalle}
+                      className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
+                      <ArrowRight aria-hidden className="size-4" />
+                    </button>}
+                  </div>
+                </th>
+                <td data-etiqueta="Llamadas" className="px-2 text-right text-sm font-semibold tabular-nums text-foreground">{f.llamadas}</td>
+                <td data-etiqueta="Contacto" className="px-2 text-right">
+                  <span className="block text-sm font-bold tabular-nums text-foreground">{f.tasaContacto === null ? '—' : `${Math.round(f.tasaContacto)} %`}</span>
+                  <span className="block text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{f.contestadas}/{f.utiles} útiles</span>
+                </td>
+                <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">{f.citas}</td>
+                <td data-etiqueta="Vencidas" className="px-2 text-right text-sm tabular-nums">
+                  {f.vencidas > 0
+                    ? <button type="button" onClick={(e) => accion(f, 'vencidas', e.currentTarget)} aria-label={`${f.vencidas} tareas vencidas en ${nombre}: ver por analista`}
+                      className={cn(ENLACE_CIFRA, 'text-[var(--destructive-text)]')}>{f.vencidas}</button>
+                    : <span className="text-foreground">0</span>}
+                </td>
+                <td data-etiqueta="Atención" className="py-2 pl-4 pr-2 text-[13px]">
+                  {f.atencion === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">{sinDetalle === 'error' ? '—' : '…'}</span><span className="sr-only">{sinDetalle === 'error' ? 'No disponible' : 'Consultando'}</span></>
+                    : f.atencion === 0 ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin alertas</span></>
+                      : <button type="button" onClick={(e) => accion(f, 'atencion', e.currentTarget)} aria-label={`${f.atencion} ${f.atencion === 1 ? 'analista necesita' : 'analistas necesitan'} atención en ${nombre}: ver quiénes`}
+                        className={cn(ENLACE_CIFRA, 'text-[var(--warning-text)]')}>{f.atencion} {f.atencion === 1 ? 'analista' : 'analistas'}</button>}
+                </td>
+                <td data-etiqueta="Primer intento" className="px-2 text-right text-sm tabular-nums text-foreground">
+                  {f.primerIntento === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Seguimiento no activo</span></> : f.primerIntento}
+                </td>
+                <td data-etiqueta="Dispersión" className="py-2 pl-2 pr-4 text-right">
+                  {f.dispersion.personas > 0 && f.dispersion.minimo !== null && f.dispersion.maximo !== null ? <>
+                    <span className="block text-sm tabular-nums text-foreground">{cifraPulso(Math.round(f.dispersion.minimo))}–{cifraPulso(Math.round(f.dispersion.maximo))} %</span>
+                    <span className="block text-[11.5px] text-[var(--muted-foreground-strong)]">{f.dispersion.personas} con muestra</span>
+                  </> : <span className="text-[11.5px] text-[var(--muted-foreground-strong)]">Sin muestra</span>}
+                </td>
+              </tr>
+            )
+          })}
+        </tbody>
+      </table>
+    </div>
+  </>
+}
+
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/use-panel-gerencia.ts b/CRM-Avance-Corp/app/src/components/gestion-diaria/use-panel-gerencia.ts
deleted file mode 100644
index 4e1dc76b..00000000
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/use-panel-gerencia.ts
+++ /dev/null
@@ -1,18 +0,0 @@
-import { useLayoutEffect, useState, type RefObject } from 'react'
-
-/** Medir el área real respeta el espacio que ocupa el menú, incluso al cambiarlo. */
-export function usePanelGerencia(pantalla: RefObject<HTMLElement | null>) {
-  const [estrecho, setEstrecho] = useState(false)
-  useLayoutEffect(() => {
-    const nodo = pantalla.current
-    if (!nodo || typeof ResizeObserver === 'undefined') return
-    // Desde 960 px útiles caben tabla (584) + separación (16) + detalle (360).
-    // Las columnas adicionales desplazan dentro de la tabla, no toda la página.
-    const medir = () => setEstrecho(nodo.clientWidth < 960)
-    const observer = new ResizeObserver(medir)
-    observer.observe(nodo)
-    medir()
-    return () => observer.disconnect()
-  }, [pantalla])
-  return { estrecho }
-}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
new file mode 100644
index 00000000..c9e80494
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
@@ -0,0 +1,206 @@
+// Gerencia dentro de un equipo («Toda la operación / Equipo de X», 27/09/2026):
+// la pantalla del supervisor —cifras-filtro, buscador, tabla nueva (más
+// Pendientes, que gerencia compara) y la ficha protagonista del analista— SIN
+// pestaña Pendientes hasta que gerencia tenga permiso sobre esa consulta (G4).
+// La selección del usuario vive en la ruta (atrás/adelante, enlaces directos); la
+// automática —quien más atención necesita— solo en la pantalla y sin mover el
+// foco. Se conservan los autores inactivos y los registros sin autor (Codex).
+import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type JSX, type MouseEvent } from 'react'
+import { ChevronRight, ClipboardList, Users } from 'lucide-react'
+import { hashDe } from '@/lib/router'
+import type { EquipoPulso } from '@/lib/gestion-diaria-pulso'
+import { compararGravedad, filtrarOrdenarEquipo, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
+import { filtrosDePreset, nombreEquipo } from '@/lib/gestion-diaria-operacion'
+import { PanelVacio } from '@/components/common/estado-panel'
+import { cn } from '@/lib/utils'
+import { TablaEquipoDiaria } from './tabla-equipo-diaria'
+import { PanelAnalistaSupervisor, type SeleccionSupervisor } from './panel-analista-supervisor'
+import { PanelSupervisorAdaptable } from './panel-supervisor-adaptable'
+import { BarraEquipo } from './barra-equipo'
+import { ErrorConsultaGerencia } from './error-consulta-gerencia'
+import { BOTON_CABECERA, FOCO } from './estilos-gestion'
+
+/** Tabla (con su columna extra desplazable) + separación + ficha mínima, como el supervisor. */
+const ANCHO_EN_LINEA = 1100
+const BASE = filtrosDePreset()
+
+const rutaAnalista = (id: string) => hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id })
+const rutaEquipo = (clave: string) => hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: clave })
+const navegarEnVentana = (e: MouseEvent<HTMLAnchorElement>) => !e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey
+
+export function VistaEquipoGerencia({ equipo, filas, error, cargando, enVuelo, recargar, minimo, dia, esHoy, ahora, analistaRuta, filtros, setFiltros, actualizacion, revocar, volver, abrirGeneral, enfocarAlEntrar = false }: {
+  equipo: EquipoPulso
+  /** Filas del detalle de los analistas ACTIVOS del equipo; null mientras llegan. */
+  filas: FilaEquipoPresentada[] | null
+  error: unknown
+  cargando: boolean
+  enVuelo: boolean
+  recargar: () => Promise<void>
+  minimo: number | undefined
+  dia: string
+  esHoy: boolean
+  ahora: number
+  analistaRuta: string | null
+  filtros: FiltrosEquipo
+  setFiltros: (cambio: (f: FiltrosEquipo) => FiltrosEquipo) => void
+  actualizacion: number
+  revocar: () => void
+  volver: () => void
+  abrirGeneral: () => void
+  /** Solo cuando el usuario ENTRA al equipo; no al volver de una recarga ni por enlace directo. */
+  enfocarAlEntrar?: boolean
+}): JSX.Element {
+  const nombre = nombreEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre })
+  const panelId = useId()
+  const raiz = useRef<HTMLElement>(null)
+  const tituloEquipo = useRef<HTMLHeadingElement>(null)
+  const tituloPanel = useRef<HTMLHeadingElement>(null)
+  const origen = useRef<HTMLElement | null>(null)
+  const propia = useRef(false)
+  const apertura = useRef(0)
+  const autoInhibida = useRef(false)
+  const [local, setLocal] = useState<SeleccionSupervisor | null>(null)
+  const [estrecho, setEstrecho] = useState(false)
+  const [ampliado, setAmpliado] = useState(false)
+  const [enfocarRuta, setEnfocarRuta] = useState(false)
+  const idsEquipo = equipo.personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id])
+  const persona = analistaRuta ? equipo.personas.find((p) => p.analista_id === analistaRuta) : undefined
+  const seleccion: SeleccionSupervisor | null = analistaRuta
+    ? { analista: analistaRuta, nombre: persona?.nombre_completo ?? null, apertura: 0, pestana: 'todo', enfocar: enfocarRuta, origen: 'usuario' }
+    : local
+  const mostradas = useMemo(() => filas ? filtrarOrdenarEquipo(filas, filtros) : [], [filas, filtros])
+  const fila = filas?.find((f) => f.analista_id === seleccion?.analista)
+  const automatica = seleccion?.origen === 'automatica'
+  const modal = seleccion !== null && !automatica && (estrecho || ampliado)
+  const oculta = Boolean(fila && !mostradas.some((f) => f.analista_id === fila.analista_id))
+  const atencion = filas?.filter((f) => f.requiere_atencion).length ?? 0
+  const conteos = filas ? {
+    analistas: filas.length, con_actividad: filas.filter((f) => f.gestiones_hoy > 0).length,
+    sin_actividad: filas.filter((f) => f.gestiones_hoy === 0).length,
+    con_pendientes: filas.filter((f) => f.tareas_pendientes > 0 || (f.primer_intento_vencido ?? 0) > 0).length,
+  } : null
+
+  // Al entrar desde la operación, el foco llega al título del equipo (con una persona elegida, a su ficha).
+  const alEntrar = useRef(enfocarAlEntrar && !analistaRuta)
+  useEffect(() => { if (alEntrar.current) tituloEquipo.current?.focus({ preventScroll: true }) }, [])
+  // Una persona elegida FUERA de esta tabla (la operación, un enlace) lleva el foco a su ficha;
+  // la elegida en la tabla lo deja en su fila, como el supervisor.
+  useLayoutEffect(() => {
+    if (!analistaRuta) return
+    setEnfocarRuta(!propia.current)
+    propia.current = false
+  }, [analistaRuta])
+  useLayoutEffect(() => {
+    const nodo = raiz.current
+    if (!nodo || typeof ResizeObserver === 'undefined') return
+    const medir = () => setEstrecho(nodo.clientWidth < ANCHO_EN_LINEA)
+    const observador = new ResizeObserver(medir)
+    observador.observe(nodo)
+    medir()
+    return () => observador.disconnect()
+  }, [])
+  // Selección automática: pantalla ancha, sin ruta, sin cierre voluntario; el más grave de lo visible.
+  useEffect(() => {
+    if (analistaRuta || local || autoInhibida.current || estrecho || !filas) return
+    const candidata = mostradas.filter((f) => f.requiere_atencion).toSorted(compararGravedad)[0]
+    if (candidata) setLocal({ analista: candidata.analista_id, nombre: candidata.nombre_completo, apertura: ++apertura.current, pestana: 'todo', enfocar: false, origen: 'automatica' })
+  }, [analistaRuta, local, estrecho, filas, mostradas])
+  // Una automática que se queda sin sitio se cierra, sin abrir ninguna ventana.
+  useLayoutEffect(() => { if (estrecho && local?.origen === 'automatica') setLocal(null) }, [estrecho, local])
+
+  const devolverFoco = (analista: string | null) => requestAnimationFrame(() => {
+    const activo = document.activeElement
+    if (activo instanceof HTMLElement && activo !== document.body && !document.getElementById(panelId)?.contains(activo)) return
+    const enTabla = analista ? raiz.current?.querySelector<HTMLElement>(`tr[data-analista="${CSS.escape(analista)}"] button`) : null
+    const destino = origen.current?.isConnected ? origen.current : enTabla ?? tituloEquipo.current
+    destino?.focus({ preventScroll: true })
+    destino?.scrollIntoView?.({ block: 'nearest' })
+  })
+  const seleccionar = (f: FilaEquipoPresentada) => {
+    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
+    propia.current = true
+    setLocal(null)
+    if (f.analista_id !== analistaRuta) window.location.hash = rutaAnalista(f.analista_id)
+  }
+  const seleccionarAutor = (analista: string, control: HTMLElement) => {
+    origen.current = control
+    propia.current = false
+    setLocal(null)
+    window.location.hash = rutaAnalista(analista)
+  }
+  const cerrar = () => {
+    const analista = seleccion?.analista ?? null
+    autoInhibida.current = true
+    setAmpliado(false)
+    setLocal(null)
+    if (analistaRuta) window.location.hash = rutaEquipo(equipo.clave)
+    devolverFoco(analista)
+  }
+  const abrirRegistroEquipo = (control: HTMLElement) => {
+    origen.current = control
+    if (analistaRuta) window.location.hash = rutaEquipo(equipo.clave)
+    setLocal({ analista: null, nombre: null, apertura: ++apertura.current, pestana: 'todo', enfocar: true, origen: 'usuario' })
+  }
+  const ordenar = (orden: OrdenEquipo) => setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : orden === 'nombre' }))
+  const volverClick = (e: MouseEvent<HTMLAnchorElement>) => { if (navegarEnVentana(e)) { e.preventDefault(); volver() } }
+
+  return (
+    <section ref={raiz} aria-label={nombre} className="flex min-h-0 flex-1 flex-col gap-3">
+      <div className="flex shrink-0 flex-wrap items-end justify-between gap-x-4 gap-y-2">
+        <div className="min-w-0">
+          <nav aria-label="Ruta de la operación" className="flex flex-wrap items-center gap-1 text-[12.5px] text-[var(--muted-foreground-strong)]">
+            <a href={hashDe('gestion-diaria')} onClick={volverClick} className={cn('rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)}>Toda la operación</a>
+            <ChevronRight aria-hidden className="size-3.5" /><span aria-current="page">{nombre}</span>
+          </nav>
+          <h3 ref={tituloEquipo} tabIndex={-1} className={cn('mt-0.5 rounded-md text-xl font-extrabold leading-tight text-primary', FOCO)}>{nombre}</h3>
+          <p className="text-[12.5px] text-[var(--muted-foreground-strong)]">{equipo.metricas.analistas_activos} {equipo.metricas.analistas_activos === 1 ? 'analista' : 'analistas'} · {equipo.metricas.con_actividad} con registro{esHoy ? ' hoy' : ''}</p>
+        </div>
+        <button type="button" className={BOTON_CABECERA} onClick={(e) => abrirRegistroEquipo(e.currentTarget)}><ClipboardList aria-hidden className="size-4" />Registro del equipo</button>
+      </div>
+
+      <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
+        <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
+          {error ? <div className="p-6"><ErrorConsultaGerencia error={error} recargar={recargar} enVuelo={enVuelo} /></div>
+            : cargando || !filas || !conteos ? <p role="status" className="p-6 text-[13.5px] text-[var(--muted-foreground-strong)]">Consultando los analistas del equipo…</p>
+              : <>
+                {filas.length > 0 && <BarraEquipo filtros={filtros} setFiltros={setFiltros} conteos={conteos} atencion={atencion} />}
+                {filas.length === 0
+                  ? <PanelVacio icono={Users} titulo="Este equipo no tiene analistas activos" detalle="Sus registros de autores inactivos siguen disponibles abajo y en el registro del equipo." />
+                  : <TablaEquipoDiaria conPendientes filas={mostradas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null}
+                    seleccionar={seleccionar} panelId={panelId} minimo={minimo ?? 1}
+                    irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />}
+                <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
+                  <p><span role="status">{mostradas.length} de {filas.length} analistas</span></p>
+                  <p>La actividad registrada no acredita presencia.</p>
+                </div>
+                {equipo.personas.some((p) => !p.activo) && (
+                  <div className="shrink-0 space-y-1.5 border-t border-border px-4 py-3 text-[13px]">
+                    <h4 className="font-bold text-primary">Otros autores de los registros</h4>
+                    {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
+                    <ul role="list" className="space-y-1">
+                      {equipo.personas.filter((p) => !p.activo).map((p) => (
+                        <li key={p.analista_id ?? 'sin-autor'}>
+                          {p.analista_id
+                            ? <button type="button" onClick={(e) => seleccionarAutor(p.analista_id!, e.currentTarget)} className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)}>{p.nombre_completo ?? 'Autor no disponible'}</button>
+                            : 'Sin autor'}: {p.llamadas} llamadas · {p.citas_agendadas} citas agendadas
+                        </li>
+                      ))}
+                    </ul>
+                    {equipo.personas.some((p) => p.analista_id === null) && (
+                      <button type="button" onClick={abrirGeneral} className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)}>Ver registros sin autor en el registro general</button>
+                    )}
+                  </div>
+                )}
+              </>}
+        </div>
+        <PanelSupervisorAdaptable modal={modal} cerrar={cerrar} tituloRef={tituloPanel} claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
+          <PanelAnalistaSupervisor id={panelId} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo} tituloRef={tituloPanel}
+            ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => { setAmpliado((v) => !v); if (automatica && local) setLocal({ ...local, origen: 'usuario' }) }} cerrar={cerrar}
+            oculta={oculta} limpiar={() => setFiltros(() => BASE)} actualizacion={actualizacion} revalidar={revocar} esHoy={esHoy} ahora={ahora}
+            vacio="Nadie del equipo necesita atención ahora. Elige un analista para ver su día." silencioso={automatica}
+            conPendientes={false} idsEquipo={idsEquipo} subtitulo={equipo.clave === 'fuera' ? 'Analista fuera de equipos comerciales' : `Analista del equipo de ${equipo.nombre}`} />
+        </PanelSupervisorAdaptable>
+      </div>
+    </section>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.ts
new file mode 100644
index 00000000..3bedb88a
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.ts
@@ -0,0 +1,158 @@
+// «Toda la operación» de gerencia con el diseño de Gestión Diaria (27/09/2026).
+// Las cifras de cada equipo salen SIEMPRE del pulso (autoritativas: incluyen
+// autores inactivos y registros sin autor). El detalle por analista solo aporta
+// lo que el pulso no trae —quién necesita atención y las barras por hora— y se
+// restringe a las personas ACTIVAS que el pulso confirma en cada equipo
+// (revisión Codex del plan, 27/09).
+import { cifraPulso, type EquipoPulso, type MetricasPulso, type PulsoGerencia } from './gestion-diaria-pulso'
+import { compararGravedad, horarioConfirmado, type FilaEquipoPresentada, type FiltrosEquipo } from './gestion-diaria-equipo'
+import type { Marcador } from './gestion-diaria-analista'
+
+export interface FilaEquipoOperacion {
+  clave: string
+  nombre: string
+  /** El grupo de quienes no cuelgan de ningún supervisor: siempre al final. */
+  fuera: boolean
+  analistas: number
+  sinRegistro: number
+  llamadas: number
+  contestadas: number
+  utiles: number
+  tasaContacto: number | null
+  citas: number
+  vencidas: number
+  primerIntento: number | null
+  dispersion: EquipoPulso['dispersion']
+  /** Analistas DISTINTOS que necesitan atención; null mientras no llega el detalle (nunca 0 inventado). */
+  atencion: number | null
+}
+
+const activosDe = (equipo: EquipoPulso) =>
+  new Set(equipo.personas.flatMap((p) => p.activo && p.analista_id !== null ? [p.analista_id] : []))
+
+export function filasOperacion(pulso: PulsoGerencia, detalle: readonly FilaEquipoPresentada[] | null): FilaEquipoOperacion[] {
+  return pulso.equipos.map((e) => {
+    const activos = activosDe(e)
+    return {
+      clave: e.clave, nombre: e.nombre, fuera: e.clave === 'fuera',
+      analistas: e.metricas.analistas_activos, sinRegistro: e.metricas.sin_actividad,
+      llamadas: e.metricas.llamadas, contestadas: e.metricas.contestadas, utiles: e.metricas.utiles,
+      tasaContacto: e.metricas.tasa_contacto, citas: e.metricas.citas_agendadas, vencidas: e.tareas_vencidas,
+      primerIntento: e.primer_intento_vencido, dispersion: e.dispersion,
+      atencion: detalle === null ? null : detalle.filter((f) => activos.has(f.analista_id) && f.requiere_atencion).length,
+    }
+  })
+}
+
+export type OrdenOperacion = 'nombre' | 'llamadas' | 'contacto' | 'citas' | 'vencidas' | 'atencion' | 'primer_intento' | 'dispersion'
+
+export interface FiltrosOperacion { busqueda: string; conAtencion: boolean; orden: OrdenOperacion; ascendente: boolean }
+
+const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLocaleLowerCase('es').trim()
+const amplitud = (f: FilaEquipoOperacion) => f.dispersion.minimo === null || f.dispersion.maximo === null ? null : f.dispersion.maximo - f.dispersion.minimo
+
+function valorDe(f: FilaEquipoOperacion, orden: Exclude<OrdenOperacion, 'nombre'>): number | null {
+  switch (orden) {
+    case 'llamadas': return f.llamadas
+    case 'contacto': return f.tasaContacto
+    case 'citas': return f.citas
+    case 'vencidas': return f.vencidas
+    case 'atencion': return f.atencion
+    case 'primer_intento': return f.primerIntento
+    case 'dispersion': return amplitud(f)
+  }
+}
+
+/** «Con atención»: analistas que la necesitan; sin detalle todavía, las señales del pulso. */
+export const equipoConAtencion = (f: FilaEquipoOperacion) =>
+  f.atencion !== null ? f.atencion > 0 : f.vencidas > 0 || f.sinRegistro > 0 || (f.primerIntento ?? 0) > 0
+
+export function filtrarOrdenarOperacion(filas: readonly FilaEquipoOperacion[], filtros: FiltrosOperacion): FilaEquipoOperacion[] {
+  const q = normalizar(filtros.busqueda)
+  return filas.filter((f) => normalizar(f.nombre).includes(q) && (!filtros.conAtencion || equipoConAtencion(f)))
+    .toSorted((a, b) => {
+      // «Fuera de equipos» no compite con los equipos: siempre al final.
+      if (a.fuera !== b.fuera) return a.fuera ? 1 : -1
+      const nombre = a.nombre.localeCompare(b.nombre, 'es')
+      if (filtros.orden === 'nombre') return filtros.ascendente ? nombre : -nombre
+      const va = valorDe(a, filtros.orden), vb = valorDe(b, filtros.orden)
+      // Sin dato al final en ambos sentidos.
+      if (va === null || vb === null) return va === vb ? nombre : va === null ? 1 : -1
+      const diferencia = (va - vb) * (filtros.ascendente ? 1 : -1)
+      if (diferencia) return diferencia
+      // Empate en atención: primero el que más vencidas arrastra.
+      return filtros.orden === 'atencion' ? b.vencidas - a.vencidas || nombre : nombre
+    })
+}
+
+export interface PersonaSinRegistro { analista_id: string; nombre: string; equipo: string; clave: string }
+
+/** Activos sin ninguna gestión en el día (la misma regla que `sin_actividad` del pulso). */
+export function personasSinRegistro(pulso: PulsoGerencia): PersonaSinRegistro[] {
+  return pulso.equipos.flatMap((e) => e.personas.flatMap((p) => p.activo && p.gestiones === 0 && p.analista_id !== null
+    ? [{ analista_id: p.analista_id, nombre: p.nombre_completo ?? 'Analista', equipo: e.nombre, clave: e.clave }] : []))
+    .toSorted((a, b) => a.equipo.localeCompare(b.equipo, 'es') || a.nombre.localeCompare(b.nombre, 'es'))
+}
+
+/** Quién necesita atención dentro del equipo, el más grave primero. */
+export function atencionEquipo(detalle: readonly FilaEquipoPresentada[], equipo: EquipoPulso): FilaEquipoPresentada[] {
+  const activos = activosDe(equipo)
+  return detalle.filter((f) => activos.has(f.analista_id) && f.requiere_atencion).toSorted(compararGravedad)
+}
+
+export interface BarrasEquipo {
+  porHora: Marcador['por_hora']
+  /** Analistas activos que forman la gráfica. */
+  analistas: number
+  /** Llamadas del equipo que NO están en la gráfica (autores inactivos o sin autor). */
+  otros: number
+}
+
+/**
+ * Llamadas por hora de los analistas ACTIVOS del equipo. Si el desglose de
+ * alguno no se puede confirmar, no se dibuja (no se pintan ceros como sustituto).
+ */
+export function barrasEquipo(detalle: readonly FilaEquipoPresentada[], equipo: EquipoPulso): BarrasEquipo | null {
+  const activos = activosDe(equipo)
+  const filas = detalle.filter((f) => activos.has(f.analista_id))
+  if (filas.length === 0 || filas.length !== activos.size || !filas.every((f) => horarioConfirmado(f.marcador))) return null
+  const porHora = new Map<number, { hora: number; llamadas: number; contestadas: number }>()
+  for (const f of filas) for (const h of f.marcador.por_hora) {
+    const actual = porHora.get(h.hora) ?? { hora: h.hora, llamadas: 0, contestadas: 0 }
+    porHora.set(h.hora, { hora: h.hora, llamadas: actual.llamadas + h.llamadas, contestadas: actual.contestadas + h.contestadas })
+  }
+  const enGrafica = filas.reduce((n, f) => n + f.marcador.llamadas, 0)
+  return { porHora: [...porHora.values()].toSorted((a, b) => a.hora - b.hora), analistas: filas.length, otros: Math.max(0, equipo.metricas.llamadas - enGrafica) }
+}
+
+/**
+ * «Ayer 92 · Referencia 88 (7 jornadas)». En un día pasado dice «Día anterior»;
+ * la referencia son hasta 7 jornadas CON actividad, no 7 días calendario (Codex).
+ */
+export function referenciaCifra(pulso: PulsoGerencia, campo: keyof MetricasPulso, esHoy: boolean, porcentaje = false): string {
+  // Promedios y tasas a entero, como el diseño («7 días 88»): la cifra exacta vive en «Comparar días».
+  const cifra = (n: number | null) => cifraPulso(n === null ? null : Math.round(n), porcentaje)
+  const anterior = `${esHoy ? 'Ayer' : 'Día anterior'} ${cifra(pulso.ayer.metricas[campo])}`
+  const n = pulso.referencia.cantidad
+  return n === 0 ? `${anterior} · Sin referencia`
+    : `${anterior} · Referencia ${cifra(pulso.referencia.media[campo])} (${n} ${n === 1 ? 'jornada' : 'jornadas'})`
+}
+
+/** «Equipo de SUPERVISOR UNO»; el grupo sin supervisor conserva su nombre. */
+export const nombreEquipo = (f: { fuera: boolean; nombre: string }) => f.fuera ? f.nombre : `Equipo de ${f.nombre}`
+
+/** A dónde lleva un número del equipo: sus analistas con ese filtro u orden. */
+export type PresetEquipo = 'sin_registro' | 'vencidas' | 'atencion' | 'citas'
+
+const FILTROS_EQUIPO: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false, gravedad: true }
+
+/** El número que se abrió desde la operación llega como filtro u orden: el número es la lista. */
+export function filtrosDePreset(preset?: PresetEquipo): FiltrosEquipo {
+  switch (preset) {
+    case 'atencion': return { ...FILTROS_EQUIPO, soloProblemas: true }
+    case 'sin_registro': return { ...FILTROS_EQUIPO, estado: 'sin_registro' }
+    case 'vencidas': return { ...FILTROS_EQUIPO, orden: 'vencidas', ascendente: false }
+    case 'citas': return { ...FILTROS_EQUIPO, orden: 'citas', ascendente: false }
+    default: return FILTROS_EQUIPO
+  }
+}
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
index ac53a2a0..47bd6b67 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
@@ -1,26 +1,39 @@
 /* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar la comparación con el teclado. */
-import { useCallback, useEffect, useId, useRef, useState, useSyncExternalStore, type ReactNode } from 'react'
-import { Columns3, Info, RefreshCw } from 'lucide-react'
+// «Toda la operación» de gerencia con el diseño de Gestión Diaria y las mejoras
+// del supervisor (Miguel, 27/09/2026): cifras finas que abren su lista, tabla de
+// equipos protagonista, ficha del equipo al lado y, dentro de cada equipo, la
+// pantalla del supervisor. Plan v2 tras la revisión de Codex (vault).
+import { useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from 'react'
+import { ClipboardList, Columns3, RefreshCw } from 'lucide-react'
 import { useAuth } from '@/lib/auth-context'
 import { useAhora } from '@/lib/ahora'
 import { fechaLima } from '@/lib/agenda-derivada'
 import { horaLimaDe } from '@/lib/gestion-diaria-analista'
 import { cifraPulso, diaPulsoValido, desplazarDia, type MetricasPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
+import { presentarEquipo, type FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
+import { equipoConAtencion, filasOperacion, filtrarOrdenarOperacion, filtrosDePreset, type FiltrosOperacion, type OrdenOperacion, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
 import { hashDe, leerHash } from '@/lib/router'
 import { CrmApiError } from '@/data/crm-api'
 import { usePulsoGerencia, useHabitosGerencia, useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
-import { EspacioPulsoGerencia } from '@/components/gestion-diaria/espacio-pulso-gerencia'
 import { ErrorConsultaGerencia } from '@/components/gestion-diaria/error-consulta-gerencia'
-import { usePanelGerencia } from '@/components/gestion-diaria/use-panel-gerencia'
 import { ReporteHabitos } from '@/components/gestion-diaria/reporte-habitos'
+import { CifrasOperacion, type DestinoCifra } from '@/components/gestion-diaria/cifras-operacion'
+import { TablaEquiposGerencia } from '@/components/gestion-diaria/tabla-equipos-gerencia'
+import { PanelOperacionGerencia, type VistaOperacion } from '@/components/gestion-diaria/panel-operacion-gerencia'
+import { PanelSupervisorAdaptable } from '@/components/gestion-diaria/panel-supervisor-adaptable'
+import { VistaEquipoGerencia } from '@/components/gestion-diaria/vista-equipo-gerencia'
+import { BOTON_CABECERA, CONTROL, FOCO } from '@/components/gestion-diaria/estilos-gestion'
 import { PanelCargando } from '@/components/common/estado-panel'
 import { Button } from '@/components/ui/button'
 import { Dialog, DialogHeader, DialogTitle, DialogBody } from '@/components/ui/dialog'
 import { Input } from '@/components/ui/input'
 import { Select } from '@/components/ui/select'
 import { Tabs } from '@/components/ui/tabs'
+import { cn } from '@/lib/utils'
 import './supervisor.css'
 import './gerencia.css'
+import './mi-equipo.css'
+
 
 const METRICAS: { campo: keyof MetricasPulso; titulo: string; porcentaje?: boolean }[] = [
   { campo: 'llamadas', titulo: 'Llamadas' }, { campo: 'utiles', titulo: 'Llamadas útiles' },
@@ -44,30 +57,59 @@ export function GestionDiariaGerencia({ accesoSeguimiento }: { accesoSeguimiento
   return <VistaGerencia key={yo.id} actor={yo.id} hoy={hoy} accesoSeguimiento={accesoSeguimiento} />
 }
 
+
+/**
+ * Tabla de equipos con sus seis primeras columnas (nombre ≥ 220 + 404 + rellenos
+ * y canal ≥ 40) + separación (16) + ficha mínima (360) = 1040: a 1440 con el menú
+ * abierto (~1150) caben lado a lado. Primer intento y Dispersión desplazan dentro
+ * de la tabla. Por debajo, la ficha se abre encima.
+ */
+const ANCHO_EN_LINEA = 1040
+const FILTROS_OPERACION: FiltrosOperacion = { busqueda: '', conAtencion: false, orden: 'atencion', ascendente: false }
+const FECHA_LARGA = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' })
+const rutaDe = (tipo: 'equipo' | 'analista', id: string) => hashDe('gestion-diaria', null, undefined, undefined, { tipo, id })
+
 function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy: string; accesoSeguimiento?: ReactNode }) {
   const [elegido, setElegido] = useState(() => diaRecordado(actor, hoy))
   const dia = elegido && diaPulsoValido(elegido, hoy) ? elegido : hoy
+  const esHoy = dia === hoy
+  const ahora = useAhora()
   const entrada = useRef<HTMLInputElement>(null)
   const pantalla = useRef<HTMLElement>(null)
-  const { estrecho } = usePanelGerencia(pantalla)
+  const titulo = useRef<HTMLHeadingElement>(null)
+  const tituloPanel = useRef<HTMLHeadingElement>(null)
+  const origenPanel = useRef<HTMLElement | null>(null)
+  // Un cierre voluntario apaga la selección automática en esta visita (como el supervisor).
+  const autoInhibida = useRef(false)
+  const aperturas = useRef(0)
+  // Último equipo cuyo título recibió el foco: entrar (o un enlace directo) lo enfoca; volver
+  // de una recarga con el mismo equipo, no (como la ruta enfocada de F6).
+  const equipoEnfocado = useRef<string | null>(null)
+  const panelId = useId()
+  const id = useId()
   const [avisoFecha, setAvisoFecha] = useState('')
   const [pestana, setPestana] = useState<'pulso' | 'habitos'>('pulso')
   const [dias, setDias] = useState<7 | 14 | 30>(14)
   const [actualizacion, setActualizacion] = useState(0)
-  const [general, setGeneral] = useState(false)
   const [revocada, setRevocada] = useState(false)
   const revocar = useCallback(() => setRevocada(true), [])
-  const [panelOculto, setPanelOculto] = useState<string | null>(null)
-  const botonRegistro = useRef<HTMLButtonElement>(null)
+  const [comparar, setComparar] = useState(false)
+  const [estrecho, setEstrecho] = useState(false)
+  const [ampliado, setAmpliado] = useState(false)
+  const [filtros, setFiltros] = useState<FiltrosOperacion>(FILTROS_OPERACION)
+  const [ficha, setFicha] = useState<{ vista: VistaOperacion; origen: 'automatica' | 'usuario' } | null>(null)
+  const [filtrosPorEquipo, setFiltrosPorEquipo] = useState<Record<string, FiltrosEquipo>>({})
+  const [anuncio, setAnuncio] = useState('')
+  const [pedidoFoco, setPedidoFoco] = useState(0)
   useSyncExternalStore(suscribirRuta, fotoRuta)
   const detalleRuta = leerHash().detalleGestion
   const ruta = detalleRuta?.tipo === 'cola' ? undefined : detalleRuta
-  const rutaEnfocada = useRef<string | null>(null)
-  useEffect(() => { if (!ruta) rutaEnfocada.current = null }, [ruta])
   const activa = ruta ? 'pulso' : pestana
   const pulso = usePulsoGerencia(dia)
   const habitos = useHabitosGerencia(dia, dias, activa === 'habitos')
-  const detalle = useDetallePulso(dia, Boolean(ruta) && pulso.datos !== null)
+  // El detalle sostiene la atención y las barras de la operación: se carga al entrar
+  // y se actualiza con el pulso, haya o no un equipo abierto (Codex, plan v2).
+  const detalle = useDetallePulso(dia, activa === 'pulso' && pulso.datos !== null)
   // Una denegación en cualquier consulta retira toda la vista, aunque se cambie
   // de pestaña o se deshabilite después esa consulta. Revalidar sesión inicia
   // consultas nuevas, sin reutilizar la memoria paginada anterior.
@@ -75,83 +117,217 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
   if (sinPermiso && !revocada) setRevocada(true)
   const error = sinPermiso ? SIN_PERMISO : activa === 'habitos' ? habitos.error : pulso.error
   const consulta = activa === 'habitos' ? habitos : pulso
-  const id = useId()
+  const datos = pulso.datos
+  const filasDetalle = useMemo(() => detalle.datos ? presentarEquipo(detalle.datos) : null, [detalle.datos])
+  const filasOp = useMemo(() => datos ? filasOperacion(datos, filasDetalle) : [], [datos, filasDetalle])
+  const mostradas = filtrarOrdenarOperacion(filasOp, filtros)
+  const conAtencion = filasDetalle ? filasOp.filter(equipoConAtencion).length : null
+  const grupo = datos && ruta ? datos.equipos.find((e) => ruta.tipo === 'equipo' ? e.clave === ruta.id : e.personas.some((p) => p.analista_id === ruta.id)) : undefined
+  const automatica = ficha?.origen === 'automatica'
+  const modal = ficha !== null && !automatica && (estrecho || ampliado)
+  const registroDisponible = Boolean(datos) && !pulso.error && !sinPermiso
+
   useEffect(() => { if (entrada.current) entrada.current.value = dia }, [dia])
+  useLayoutEffect(() => {
+    const nodo = pantalla.current
+    if (!nodo || typeof ResizeObserver === 'undefined') return
+    const medir = () => setEstrecho(nodo.clientWidth < ANCHO_EN_LINEA)
+    const observador = new ResizeObserver(medir)
+    observador.observe(nodo)
+    medir()
+    return () => observador.disconnect()
+  }, [])
+  // Selección automática del equipo que más atención necesita: solo elige la ficha,
+  // no navega ni mueve el foco (Codex: separada de la ruta del equipo).
+  useEffect(() => {
+    if (ruta || ficha || autoInhibida.current || estrecho || !filasDetalle || activa !== 'pulso') return
+    const candidato = filtrarOrdenarOperacion(filasOp, FILTROS_OPERACION).find((f) => !f.fuera && (f.atencion ?? 0) > 0)
+    if (candidato) setFicha({ vista: { tipo: 'equipo', clave: candidato.clave }, origen: 'automatica' })
+  }, [ruta, ficha, estrecho, filasDetalle, filasOp, activa])
+  // Una automática que se queda sin sitio se cierra, sin abrir ninguna ventana.
+  useLayoutEffect(() => { if (estrecho && ficha?.origen === 'automatica') setFicha(null) }, [estrecho, ficha])
+  useEffect(() => { if (!ruta) equipoEnfocado.current = null; else if (grupo) equipoEnfocado.current = grupo.clave })
+  // Abrir una lista lejos del control (registro, sin registro) lleva el foco a la ficha.
+  useLayoutEffect(() => { if (pedidoFoco) tituloPanel.current?.focus({ preventScroll: true }) }, [pedidoFoco])
+
   const cambiarDia = (nuevo: string) => {
     if (!diaPulsoValido(nuevo, hoy)) {
       setAvisoFecha('Elige una fecha válida entre hoy y los últimos 365 días.')
       if (entrada.current) entrada.current.value = dia
       return
     }
-    setElegido(nuevo === hoy ? null : nuevo); setAvisoFecha(''); setGeneral(false)
+    setElegido(nuevo === hoy ? null : nuevo); setAvisoFecha(''); setFicha(null); setAmpliado(false); autoInhibida.current = false
     try { if (nuevo === hoy) sessionStorage.removeItem(memoria(actor)); else sessionStorage.setItem(memoria(actor), nuevo) } catch { /* Sesión sin almacenamiento: selección en memoria. */ }
   }
-  const actualizar = async () => { await consulta.recargar(); if (ruta && !sinPermiso) await detalle.recargar(); setActualizacion((n) => n + 1) }
-  return <section ref={pantalla} className="gd-supervisor gd-pulso" data-estrecho={estrecho} aria-label="Toda la operación">
-    <header className="gd-cabecera gp-cabecera">
-      <h2>Toda la operación</h2>
-      <div className="gd-selector-fecha gp-controles">
-        <label className="sr-only" htmlFor={`${id}-dia`}>Día de la operación</label><Input ref={entrada} id={`${id}-dia`} aria-label="Día de la operación" type="date" defaultValue={dia} min={desplazarDia(hoy, -365)} max={hoy} className="min-h-11 w-auto text-base" aria-describedby={avisoFecha ? `${id}-aviso` : undefined}
-          onChange={() => setAvisoFecha('')}
-          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); cambiarDia(e.currentTarget.value) } }} />
-        <Button variant="outline" className="min-h-11 text-base" onClick={() => cambiarDia(entrada.current?.value ?? dia)}>Consultar</Button>
-        <Button variant="outline" className="min-h-11 text-base" onClick={() => cambiarDia(hoy)} disabled={dia === hoy}>Hoy</Button>
-        <span className="gd-fecha">Lima</span>
-      </div>
-      <div className="gd-acciones-cabecera gp-acciones">
-        {accesoSeguimiento}
-        <Button ref={botonRegistro} variant="ghost" className="min-h-11 text-base" onClick={() => { setPestana('pulso'); setGeneral(true) }} aria-pressed={general} disabled={Boolean(pulso.error || sinPermiso || !pulso.datos)}>Registro general</Button>
-        <Button variant="outline" size="icon" className="size-11" aria-label="Actualizar operación" onClick={() => void actualizar()} disabled={consulta.enVuelo || sinPermiso}><RefreshCw aria-hidden /></Button>
+  const actualizar = async () => {
+    await Promise.all([consulta.recargar(), activa === 'pulso' ? detalle.recargar() : Promise.resolve()])
+    setActualizacion((n) => n + 1)
+  }
+  const abrirFicha = (vista: VistaOperacion, control: HTMLElement | null, enfocar: boolean) => {
+    origenPanel.current = control ?? (document.activeElement instanceof HTMLElement ? document.activeElement : null)
+    setFicha({ vista, origen: 'usuario' })
+    if (enfocar) setPedidoFoco((n) => n + 1)
+  }
+  const abrirRegistroGeneral = (control: HTMLElement | null, pestanaInicial: 'todo' | 'llamadas' = 'todo') =>
+    abrirFicha({ tipo: 'registro', alcance: 'general', pestana: pestanaInicial, apertura: ++aperturas.current }, control, true)
+  const cerrarFicha = () => {
+    autoInhibida.current = true
+    setAmpliado(false)
+    setFicha(null)
+    requestAnimationFrame(() => {
+      const activo = document.activeElement
+      if (activo instanceof HTMLElement && activo !== document.body && !document.getElementById(panelId)?.contains(activo)) return
+      ;(origenPanel.current?.isConnected ? origenPanel.current : titulo.current)?.focus({ preventScroll: true })
+    })
+  }
+  const entrarEquipo = (clave: string, preset?: PresetEquipo) => {
+    if (preset) setFiltrosPorEquipo((p) => ({ ...p, [clave]: filtrosDePreset(preset) }))
+    setAmpliado(false)
+    window.location.hash = rutaDe('equipo', clave)
+  }
+  const abrirPersona = (analistaId: string) => { setAmpliado(false); window.location.hash = rutaDe('analista', analistaId) }
+  const volverOperacion = (clave?: string) => {
+    window.location.hash = hashDe('gestion-diaria')
+    requestAnimationFrame(() => {
+      const fila = clave ? pantalla.current?.querySelector<HTMLElement>(`tr[data-equipo="${CSS.escape(clave)}"] th button`) : null
+      ;(fila ?? titulo.current)?.focus({ preventScroll: true })
+    })
+  }
+  const abrirCifra = (destino: DestinoCifra, control: HTMLElement) => {
+    if (destino === 'citas') {
+      setFiltros((f) => ({ ...f, busqueda: '', conAtencion: false, orden: 'citas', ascendente: false }))
+      setAnuncio('Equipos ordenados por citas agendadas, de más a menos.')
+    } else if (destino === 'sin_registro') abrirFicha({ tipo: 'sin_registro' }, control, true)
+    else abrirRegistroGeneral(control, 'llamadas')
+  }
+  const ordenar = (orden: OrdenOperacion) => {
+    setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : orden === 'nombre' }))
+    setAnuncio(`Equipos ordenados por ${orden === 'primer_intento' ? 'primer intento' : orden}.`)
+  }
+  const hora = datos ? horaLimaDe(datos.generado_en) : null
+
+  let contenido: ReactNode
+  if (error) contenido = <ErrorConsultaGerencia error={error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} />
+  else if (consulta.cargando) contenido = <PanelCargando filas={6} />
+  else if (activa === 'habitos') contenido = habitos.datos && <>
+    <div className="gp-periodo"><label htmlFor={`${id}-periodo`}>Período hasta {dia}</label><Select id={`${id}-periodo`} className={cn(CONTROL, 'min-h-0 w-auto')} value={dias} onChange={(e) => setDias(Number(e.target.value) as 7 | 14 | 30)}>{[7, 14, 30].map((n) => <option key={n} value={n}>{n} días calendario</option>)}</Select></div>
+    <ReporteHabitos key={`${dia}:${dias}`} datos={habitos.datos} equipos={datos?.equipos ?? []} estrecho={estrecho} alAbrirAnalista={() => setPestana('pulso')} />
+  </>
+  else if (!datos) contenido = null
+  else if (ruta && grupo) {
+    const activos = new Set(grupo.personas.flatMap((p) => p.activo && p.analista_id !== null ? [p.analista_id] : []))
+    contenido = <VistaEquipoGerencia key={grupo.clave} equipo={grupo} filas={filasDetalle ? filasDetalle.filter((f) => activos.has(f.analista_id)) : null}
+      error={detalle.error} cargando={detalle.cargando} enVuelo={detalle.enVuelo} recargar={detalle.recargar} minimo={detalle.datos?.umbrales.minimo_llamadas_utiles}
+      dia={dia} esHoy={esHoy} ahora={ahora} analistaRuta={ruta.tipo === 'analista' ? ruta.id : null}
+      filtros={filtrosPorEquipo[grupo.clave] ?? filtrosDePreset()} setFiltros={(cambio) => setFiltrosPorEquipo((p) => ({ ...p, [grupo.clave]: cambio(p[grupo.clave] ?? filtrosDePreset()) }))}
+      actualizacion={actualizacion} revocar={revocar} volver={() => volverOperacion(grupo.clave)}
+      abrirGeneral={() => { volverOperacion(); abrirRegistroGeneral(null) }} enfocarAlEntrar={equipoEnfocado.current !== grupo.clave} />
+  } else if (ruta) contenido = <p role="status" className="rounded-2xl border border-border bg-card p-6 text-[13.5px]">Este equipo o autor ya no aparece en el ámbito actual.{' '}
+    <button type="button" className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)} onClick={() => volverOperacion()}>Volver a toda la operación</button></p>
+  else contenido = <>
+    <CifrasOperacion pulso={datos} esHoy={esHoy} abrir={abrirCifra} />
+    <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
+      <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
+        {detalle.error && !sinPermiso && <div role="alert" className="flex shrink-0 flex-wrap items-center justify-between gap-2 border-b border-border bg-muted/60 px-4 py-2 text-[13px]">
+          No se pudo consultar el detalle por analista: la atención y las barras no están disponibles.
+          <Button variant="ghost" className="h-9 text-[13px] pointer-coarse:h-11" onClick={() => void detalle.recargar()} disabled={detalle.enVuelo}>Reintentar</Button>
+        </div>}
+        <TablaEquiposGerencia filas={mostradas} total={filasOp.length} conAtencion={conAtencion} sinDetalle={detalle.error ? 'error' : 'cargando'}
+          filtros={filtros} setFiltros={setFiltros} ordenar={ordenar}
+          seleccion={ficha?.vista.tipo === 'equipo' ? ficha.vista.clave : null} seleccionar={(f, control) => abrirFicha({ tipo: 'equipo', clave: f.clave }, control, false)}
+          accion={(f, tipo) => entrarEquipo(f.clave, tipo)} panelId={panelId}
+          irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />
+        <p className="shrink-0 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
+          Organigrama actual · Pendientes al {fechaLima(Date.parse(datos.pendientes_al))}, {horaLimaDe(datos.pendientes_al)} ·{' '}
+          <button type="button" className={cn('cursor-pointer rounded-md font-bold text-[var(--destructive-text)] underline-offset-2 hover:underline', FOCO)}
+            onClick={() => { setFiltros((f) => ({ ...f, busqueda: '', conAtencion: false, orden: 'vencidas', ascendente: false })); setAnuncio('Equipos ordenados por tareas vencidas, de más a menos.') }}>
+            {datos.vencidas_global} tareas vencidas</button> en total.
+        </p>
       </div>
-    </header>
-    {avisoFecha && <p role="alert" id={`${id}-aviso`}>{avisoFecha}</p>}
-    <Tabs etiqueta="Vistas de gerencia" className="gp-vistas" tamano="grande" pestanas={PESTANAS} valor={activa} onCambio={(valor) => {
-      setPestana(valor); setGeneral(false); if (ruta) window.location.hash = hashDe('gestion-diaria')
-    }}>
-      {activa === 'habitos' && !sinPermiso && <div className="gp-periodo"><label htmlFor={`${id}-periodo`}>Período hasta {dia}</label><Select id={`${id}-periodo`} className="min-h-11 text-base" value={dias} onChange={(e) => setDias(Number(e.target.value) as 7 | 14 | 30)}>{[7, 14, 30].map((n) => <option key={n} value={n}>{n} días calendario</option>)}</Select></div>}
-      {error ? <ErrorConsultaGerencia error={error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} /> : consulta.cargando ? <PanelCargando filas={6} />
-        : activa === 'habitos' ? habitos.datos && <ReporteHabitos key={`${dia}:${dias}`} datos={habitos.datos} equipos={pulso.datos?.equipos ?? []} estrecho={estrecho} alAbrirAnalista={() => setPestana('pulso')} />
-          : pulso.datos && <>
-            <ResumenPulso datos={pulso.datos} />
-            <EspacioPulsoGerencia key={dia} datos={pulso.datos} ruta={ruta} consulta={detalle} actualizacion={actualizacion} estrecho={estrecho}
-              general={general} abrirGeneral={() => setGeneral(true)} cerrarGeneral={() => setGeneral(false)} rutaEnfocada={rutaEnfocada} oculto={panelOculto} setOculto={setPanelOculto} origenGeneral={botonRegistro} sinPermiso={revocar} />
-            <p className="gd-cortes gp-pendientes">Organigrama actual · Pendientes al {fechaLima(Date.parse(pulso.datos.pendientes_al))}, {horaLimaDe(pulso.datos.pendientes_al)} · <strong>{pulso.datos.vencidas_global} tareas vencidas</strong> en total.</p>
-          </>}
-    </Tabs>
-  </section>
+      <PanelSupervisorAdaptable modal={modal} cerrar={cerrarFicha} tituloRef={tituloPanel} claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
+        <PanelOperacionGerencia id={panelId} vista={ficha?.vista ?? null} pulso={datos} detalle={filasDetalle} esHoy={esHoy} tituloRef={tituloPanel}
+          ampliado={ampliado} puedeAmpliar={!estrecho} cerrar={cerrarFicha}
+          ampliar={() => { setAmpliado((v) => !v); if (ficha && automatica) setFicha({ ...ficha, origen: 'usuario' }) }}
+          abrirVista={(vista) => abrirFicha(vista, null, true)} entrarEquipo={entrarEquipo} abrirPersona={abrirPersona}
+          actualizacion={actualizacion} revocar={revocar} />
+      </PanelSupervisorAdaptable>
+    </div>
+  </>
+
+  return (
+    <section ref={pantalla} aria-label={esHoy ? 'Toda la operación hoy' : 'Toda la operación'} data-estrecho={estrecho}
+      className="me-pantalla mx-auto flex w-full max-w-[1440px] flex-col gap-4 text-foreground">
+      <header className="flex shrink-0 flex-wrap items-start justify-between gap-x-6 gap-y-3">
+        <div className="min-w-0">
+          <h2 ref={titulo} tabIndex={-1} className={cn('rounded-md text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary', FOCO)}>{esHoy ? 'Toda la operación hoy' : 'Toda la operación'}</h2>
+          <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">
+            {esHoy ? 'Cómo va el día frente a ayer y a los días de referencia.' : `El ${FECHA_LARGA.format(new Date(`${dia}T12:00:00-05:00`))} frente al día anterior y a los días de referencia.`}
+          </p>
+        </div>
+        <div className="flex min-w-0 flex-wrap items-center gap-2">
+          <label><span className="sr-only">Día de la operación</span>
+            <Input ref={entrada} type="date" defaultValue={dia} min={desplazarDia(hoy, -365)} max={hoy} aria-describedby={avisoFecha ? `${id}-aviso` : undefined}
+              className={cn(CONTROL, 'w-[150px] min-h-0')}
+              onChange={(e) => {
+                // El campo nativo conserva la escritura por segmentos; solo una fecha completa consulta.
+                const valor = e.currentTarget.value
+                if (e.currentTarget.validity.valid && valor) cambiarDia(valor)
+                else if (valor.length === 10) { setAvisoFecha('Elige una fecha válida entre hoy y los últimos 365 días.'); e.currentTarget.value = dia }
+              }}
+              onBlur={(e) => { e.currentTarget.value = dia }} />
+          </label>
+          <button type="button" className={BOTON_CABECERA} aria-disabled={esHoy} onClick={() => { if (!esHoy) cambiarDia(hoy) }}>Hoy</button>
+          {accesoSeguimiento}
+          <button type="button" className={BOTON_CABECERA} aria-disabled={!registroDisponible}
+            onClick={(e) => { if (registroDisponible) { if (ruta) window.location.hash = hashDe('gestion-diaria'); setPestana('pulso'); abrirRegistroGeneral(e.currentTarget) } }}>
+            <ClipboardList aria-hidden className="size-4" />Registro general
+          </button>
+          {hora && <p className="whitespace-nowrap pl-1 text-xs tabular-nums text-[var(--muted-foreground-strong)]">Actualizado {hora}</p>}
+          <button type="button" className={BOTON_CABECERA} aria-disabled={consulta.enVuelo || sinPermiso} aria-busy={consulta.enVuelo}
+            onClick={() => { if (!consulta.enVuelo && !sinPermiso) void actualizar() }}>
+            <RefreshCw aria-hidden className={cn('size-4', consulta.enVuelo && 'motion-safe:animate-spin')} />Actualizar
+          </button>
+          <button type="button" className={BOTON_CABECERA} aria-disabled={!datos} aria-haspopup="dialog" onClick={() => { if (datos) setComparar(true) }}>
+            <Columns3 aria-hidden className="size-4" />Comparar días
+          </button>
+        </div>
+      </header>
+      {avisoFecha && <p role="alert" id={`${id}-aviso`} className="text-[13px] font-semibold text-[var(--destructive-text)]">{avisoFecha}</p>}
+      <p role="status" className="sr-only">{anuncio}</p>
+      <Tabs etiqueta="Vistas de gerencia" variante="subrayado" pestanas={PESTANAS} valor={activa} panelEnfocable={false}
+        onCambio={(valor) => { setPestana(valor); if (ruta) window.location.hash = hashDe('gestion-diaria') }}
+        className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm pointer-coarse:[&>[role=tablist]>[role=tab]]:min-h-11"
+        clasePanel="flex min-h-0 flex-1 flex-col gap-4 pt-4">
+        {contenido}
+      </Tabs>
+      {datos && <DialogoComparacion datos={datos} abierto={comparar} cerrar={() => setComparar(false)} />}
+    </section>
+  )
 }
 
-function ResumenPulso({ datos: d }: { datos: PulsoGerencia }) {
-  const [abierto, setAbierto] = useState(false)
-  const [contenido, setContenido] = useState<'comparacion' | 'definiciones'>('comparacion')
-  const abrir = (tipo: typeof contenido) => { setContenido(tipo); setAbierto(true) }
-  return <section className="gp-resumen" aria-label="Indicadores de la operación">
-    <div className="gd-indicadores gp-indicadores"><dl>{METRICAS.map((m) => <div key={m.campo}><dt>{m.titulo}</dt><dd>{cifraPulso(d.actual[m.campo], m.porcentaje)}</dd></div>)}</dl></div>
-    <div className="gp-referencia"><p>Anterior: {d.ayer.dia} completo · Promedio: {d.referencia.cantidad} de 7 días con actividad.</p>
-      <div><Button variant="ghost" className="min-h-11 text-base" aria-haspopup="dialog" onClick={() => abrir('comparacion')}><Columns3 aria-hidden />Comparar días</Button>
-        <Button variant="ghost" size="icon" className="size-11" aria-label="Definiciones" onClick={() => abrir('definiciones')}><Info aria-hidden /></Button></div></div>
-    <Dialog open={abierto} onClose={() => setAbierto(false)} className="gp-definiciones">
-      <DialogHeader><DialogTitle>{contenido === 'comparacion' ? 'Comparación de la operación' : 'Fechas y definiciones del pulso'}</DialogTitle></DialogHeader>
-      <DialogBody><div className="space-y-4 text-base">
-        {contenido === 'comparacion' ? <>
-          <p>Día elegido: {d.dia} · Anterior: {d.ayer.dia} completo · Referencia: {d.referencia.cantidad} de 7 días con actividad.</p>
-          {d.dia === fechaLima(Date.parse(d.generado_en)) && <p>Hoy en curso; referencias de jornadas completas.</p>}
-          <div className="gp-tabla-scroll" tabIndex={0} role="region" aria-label="Desplazar comparación de días"><table className="gp-comparacion-dias" aria-label="Cifras del día, anterior y referencia">
-            <thead><tr><th scope="col">Indicador</th><th scope="col">Día elegido</th><th scope="col">Anterior</th><th scope="col">Promedio / referencia</th></tr></thead>
-            <tbody>{METRICAS.map((m) => <tr key={m.campo}><th scope="row">{m.titulo}</th>
-              <td>{cifraPulso(d.actual[m.campo], m.porcentaje)}</td><td>{cifraPulso(d.ayer.metricas[m.campo], m.porcentaje)}</td>
-              <td>{cifraPulso(d.referencia.media[m.campo], m.porcentaje)}</td></tr>)}</tbody>
-          </table></div>
-        </> : null}
-        <p>Personas y equipos corresponden al organigrama actual.</p>
-        <p>Referencia: {d.referencia.dias.length ? d.referencia.dias.join(' · ') : `Sin jornadas con actividad desde ${d.referencia.busqueda_desde}.`}</p>
-        <p>Los recuentos muestran el promedio diario. La tasa de referencia reúne contestadas y útiles de {d.referencia.dias_con_tasa} días; llamadas por lead divide las llamadas por los leads distintos de cada día sumados.</p>
-        <p>Sin actividad significa sin llamadas, WhatsApp enviado, reunión realizada, nota ni conversión; no indica ausencia.</p>
-        <p>Dispersión: mínimo y máximo individual con al menos {d.minimo_llamadas_utiles} llamadas útiles. Al ordenar, se compara la amplitud entre esos extremos.</p>
-        <p>Los leads distintos se deduplican en toda la operación; no se suman entre equipos.</p>
-        <p>Las tareas y el primer intento vencido se consultan en el momento actual, incluso al elegir un día pasado.</p>
-        <Button variant="outline" className="min-h-11 text-base" onClick={() => setAbierto(false)}>{contenido === 'comparacion' ? 'Cerrar comparación' : 'Cerrar definiciones'}</Button>
-      </div></DialogBody>
-    </Dialog>
-  </section>
+/** «Comparar días» conserva las 8 cifras con el día anterior y la referencia, y las definiciones. */
+function DialogoComparacion({ datos: d, abierto, cerrar }: { datos: PulsoGerencia; abierto: boolean; cerrar: () => void }) {
+  return <Dialog open={abierto} onClose={cerrar} className="gp-definiciones">
+    <DialogHeader><DialogTitle>Comparación de la operación</DialogTitle></DialogHeader>
+    <DialogBody><div className="space-y-4 text-[13.5px]">
+      <p>Día elegido: {d.dia} · Anterior: {d.ayer.dia} completo · Referencia: {d.referencia.cantidad} de 7 jornadas con actividad.</p>
+      {d.dia === fechaLima(Date.parse(d.generado_en)) && <p>Hoy en curso; referencias de jornadas completas.</p>}
+      <div className="gp-tabla-scroll" tabIndex={0} role="region" aria-label="Desplazar comparación de días"><table className="gp-comparacion-dias" aria-label="Cifras del día, anterior y referencia">
+        <thead><tr><th scope="col">Indicador</th><th scope="col">Día elegido</th><th scope="col">Anterior</th><th scope="col">Promedio / referencia</th></tr></thead>
+        <tbody>{METRICAS.map((m) => <tr key={m.campo}><th scope="row">{m.titulo}</th>
+          <td>{cifraPulso(d.actual[m.campo], m.porcentaje)}</td><td>{cifraPulso(d.ayer.metricas[m.campo], m.porcentaje)}</td>
+          <td>{cifraPulso(d.referencia.media[m.campo], m.porcentaje)}</td></tr>)}</tbody>
+      </table></div>
+      <h3 className="text-[15px] font-extrabold text-primary">Fechas y definiciones</h3>
+      <p>Personas y equipos corresponden al organigrama actual.</p>
+      <p>Referencia: {d.referencia.dias.length ? d.referencia.dias.join(' · ') : `Sin jornadas con actividad desde ${d.referencia.busqueda_desde}.`}</p>
+      <p>Los recuentos muestran el promedio diario. La tasa de referencia reúne contestadas y útiles de {d.referencia.dias_con_tasa} días; llamadas por lead divide las llamadas por los leads distintos de cada día sumados.</p>
+      <p>Contacto = contestaron ÷ llamadas útiles (sin «número errado» ni «no es la persona»).</p>
+      <p>Sin registro significa sin llamadas, WhatsApp enviado, reunión realizada, nota ni conversión; no indica ausencia.</p>
+      <p>Dispersión: mínimo y máximo individual con al menos {d.minimo_llamadas_utiles} llamadas útiles. Al ordenar, se compara la amplitud entre esos extremos.</p>
+      <p>Los leads distintos se deduplican en toda la operación; no se suman entre equipos.</p>
+      <p>Las tareas y el primer intento vencido se consultan en el momento actual, incluso al elegir un día pasado.</p>
+      <Button variant="outline" className="h-9 text-[13px] pointer-coarse:h-11" onClick={cerrar}>Cerrar comparación</Button>
+    </div></DialogBody>
+  </Dialog>
 }
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
index c5e1aa36..b935f4e9 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
@@ -1,11 +1,11 @@
 import { useEffect, useId, useLayoutEffect, useRef, useState, type JSX, type ReactNode } from 'react'
-import { Check, ClipboardList, Info, RefreshCw, Search, Users, X } from 'lucide-react'
+import { ClipboardList, Info, RefreshCw, Users, X } from 'lucide-react'
 import { useAlertasCRM } from '@/lib/alertas-context'
 import { useAuth } from '@/lib/auth-context'
 import { useAhora } from '@/lib/ahora'
 import { fechaLima } from '@/lib/agenda-derivada'
 import { horaLimaDe } from '@/lib/gestion-diaria-analista'
-import { compararGravedad, filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo, type OrdenEquipo, type FilaEquipoPresentada, type EstadoEquipo } from '@/lib/gestion-diaria-equipo'
+import { compararGravedad, filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo, type OrdenEquipo, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
 import { useDiaEquipo } from '@/data/gestion-diaria-equipo-queries'
 import { CrmApiError } from '@/data/crm-api'
 import { TablaEquipoDiaria } from '@/components/gestion-diaria/tabla-equipo-diaria'
@@ -16,6 +16,8 @@ import { Button } from '@/components/ui/button'
 import { Input } from '@/components/ui/input'
 import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
 import { FranjaCortesSupervisor } from '@/components/gestion-diaria/franja-cortes-supervisor'
+import { BarraEquipo } from '@/components/gestion-diaria/barra-equipo'
+import { BOTON_CABECERA, CONTROL } from '@/components/gestion-diaria/estilos-gestion'
 import { AvisosEquipo } from '@/components/gestion-diaria/avisos-equipo'
 import { EstadoCortesEquipo } from '@/components/gestion-diaria/estado-cortes-equipo'
 import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
@@ -27,17 +29,6 @@ import './mi-equipo.css'
 
 const FECHA_JORNADA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })
 // «Atención» por gravedad (revisión Codex, 27/09): lo vencido primero.
-type Pildora = EstadoEquipo | 'atencion'
-const PILDORAS: readonly { valor: Pildora; etiqueta: string }[] = [
-  { valor: 'todos', etiqueta: 'Todos' }, { valor: 'con_registro', etiqueta: 'Con registro' },
-  { valor: 'sin_registro', etiqueta: 'Sin registro' }, { valor: 'con_pendientes', etiqueta: 'Con pendientes' },
-  { valor: 'atencion', etiqueta: 'Necesitan atención' },
-]
-/** El resumen del servidor usa las MISMAS reglas que el filtro (`resumenEquipo`): el número es la lista. */
-function conteoPildora(p: Pildora, r: { analistas: number; con_actividad: number; sin_actividad: number; con_pendientes: number }, atencion: number): number {
-  return p === 'todos' ? r.analistas : p === 'con_registro' ? r.con_actividad : p === 'sin_registro' ? r.sin_actividad
-    : p === 'con_pendientes' ? r.con_pendientes : atencion
-}
 const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false, gravedad: true }
 /**
  * Ancho mínimo de la pantalla para tener tabla y panel LADO A LADO: columnas
@@ -48,8 +39,6 @@ const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloPr
  * por debajo de 640 px (mi-equipo.css): nunca en línea. Solo del supervisor.
  */
 const ANCHO_EN_LINEA = 1100
-const CONTROL = 'h-9 text-[13px] pointer-coarse:h-11'
-const BOTON_CABECERA = 'inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50 aria-disabled:hover:bg-card pointer-coarse:h-11'
 
 export function GestionDiariaSupervisor({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode } = {}): JSX.Element {
   const { yo } = useAuth()
@@ -99,9 +88,6 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
   const filas = filtrarOrdenarEquipo(equipo, filtros)
   const fila = equipo.find((f) => f.analista_id === seleccion?.analista)
   const atencion = equipo.filter((f) => f.requiere_atencion).length
-  const pildora: Pildora = filtros.soloProblemas ? 'atencion' : filtros.estado ?? 'todos'
-  // Cada cifra es del equipo entero: abrirla limpia la búsqueda, así la lista ES esa cifra (Codex, 27/09).
-  const elegirPildora = (p: Pildora) => setFiltros((f) => ({ ...f, busqueda: '', estado: p === 'atencion' ? 'todos' : p, soloProblemas: p === 'atencion' }))
   const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
   const fueraDeAmbito = seleccion !== null && (sinPermiso || (dia !== null && seleccion.analista !== null && !fila))
   const automatica = seleccion?.origen === 'automatica'
@@ -312,36 +298,11 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
               onClick={() => { if (consulta.enVuelo) return; setReintentando(true); void consulta.recargar() }}>{reintentando ? 'Reintentando…' : 'Reintentar'}</Button>}
           </div> : consulta.cargando || !dia ? <p role="status" className="p-6 text-[13.5px] text-[var(--muted-foreground-strong)]">Consultando el equipo completo…</p>
             : <>
-              {dia.equipo.length > 0 && <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
-                {/* El resumen del equipo SON los filtros: cada número abre su
-                    lista en la tabla (Miguel, 27/09: la jerarquía es de la tabla
-                    y de la ficha, no de un tablero de cifras). */}
-                <div role="group" aria-label="Resumen del equipo" className="flex flex-wrap items-center gap-1.5">
-                  {PILDORAS.map((p) => {
-                    const activa = pildora === p.valor
-                    const n = conteoPildora(p.valor, dia.resumen, atencion)
-                    return (
-                      <button key={p.valor} type="button" aria-pressed={activa} onClick={() => elegirPildora(p.valor)}
-                        className={cn('inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-full border px-3 text-[13px] font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11',
-                          activa ? 'border-accent bg-accent text-accent-foreground' : 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-border-strong hover:text-primary')}>
-                        {activa && <Check aria-hidden className="size-3.5" />}{p.etiqueta}{' '}
-                        {p.valor === 'atencion' && n > 0
-                          // Ámbar y no rojo: mezcla vencidas con cortes y tiempo sin llamar (Codex, 27/09).
-                          ? <span className="grid min-w-5 place-items-center rounded-full bg-[var(--warning-text)] px-1.5 text-[11px] font-bold tabular-nums text-white">{n}</span>
-                          : <span className="font-bold tabular-nums">{n}</span>}
-                      </button>
-                    )
-                  })}
-                </div>
-                <label className="relative ml-auto min-w-40 max-w-[220px] flex-1"><span className="sr-only">Buscar analista</span>
-                  <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
-                  <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista…" className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
-                </label>
-              </div>}
+              {dia.equipo.length > 0 && <BarraEquipo filtros={filtros} setFiltros={setFiltros} conteos={dia.resumen} atencion={atencion} />}
               {dia.equipo.length === 0
                 ? <PanelVacio icono={Users} titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
                 : <>
-                  <TablaEquipoDiaria contexto="supervisor" filas={filas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null} seleccionar={seleccionar}
+                  <TablaEquipoDiaria filas={filas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null} seleccionar={seleccionar}
                     panelId={panelId} minimo={dia.umbrales.minimo_llamadas_utiles} irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />
                   <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
                     <p><span role="status">{filas.length} de {dia.resumen.analistas} analistas</span> · Actualizado {hora}</p>
```

## PROTOCOLO DEL PROYECTO (.ai/REVIEW_PROTOCOL.md, íntegro)

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

## PROTOCOLO GLOBAL (~/.config/ai-collaboration/REVIEW_PROTOCOL.md, íntegro)

# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
