ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 2, una pasada): REFUTA la Fase 3 de la pestaña «Proyección» de Citas (front)

Contexto. CRM Avance Corp (React 19 + TS). La pestaña «Proyección» (en producción) es una hoja tipo Excel por analista sobre un rango Desde–Hasta con fila Σ, embudos tipo Excel por columna, columnas de tiempo (Mes/Semanas/Días) y listas laterales: todo número abre su lista. Regla del dueño: «no puede haber data distinta» y «en celular, tarjetas»; nombre ≥16 px, detalle ≥14 px; sin textos explicativos en pantalla (la explicación va en la Ayuda).

Fase 3:
1. Celular (< 768 px): la hoja se reemplaza por tarjetas (Total primero, luego una por analista en el mismo orden y con los mismos embudos); cada cifra es botón y abre la misma lista; Semanas/Días en una fila desplazable dentro de la tarjeta; «Ordenar por» (select + sentido) y «Filtros» (menú de columnas que abre el mismo embudo) reutilizan el estado de la hoja. Catálogo de columnas y componentes de cifra compartidos entre celda y tarjeta (`proyeccion-columnas.ts`, `proyeccion-cifras.tsx`, `proyeccion-tarjetas.tsx`).
2. «Exportar» con dos opciones: «Hoja por analista» y «Citas del periodo» (todas las citas que suma el total tras supervisor, rango y embudos, incluidas las reuniones con clientes sin lead); el CSV de citas añade la fecha de creación.
3. Ayuda «Cómo usar Citas» actualizada (texto en `propuesta.tsx`).

Busca con evidencia (archivo:línea, caso concreto): (a) una tarjeta que muestre una cifra distinta de la celda equivalente de la hoja o que abra otra lista; (b) el CSV «Citas del periodo» que no coincida con las citas del total (tras embudos de personas, monedas y Mín/Máx por fila); (c) estados de foco/teclado rotos (menú Exportar, «Filtros», embudo anclado al botón, retorno de foco al quitar un chip); (d) que la Ayuda diga algo falso respecto al cálculo (reglas en `proyeccion.ts`: % Entrev. = realizadas ÷ (realizadas + no_show) incluidas reuniones con clientes; % Conv. y Proyectado sobre citas con lead con la regla de Resultados; Ticket cita = Monto ÷ citas con lead; reuniones con clientes sin lead fuera de Monto/Ticket/% Conv./Proyectado); (e) regresiones en escritorio; (f) pruebas que no prueben lo que dicen.

Verificación reportada (NOT RUN por ti): vitest de Citas 181/181, oxlint, tsc y jscpd en verde; check completo y E2E Docker en curso.

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Diff
```diff
diff --git a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
index a275679c..ce8d3fc6 100644
--- a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
@@ -51,9 +51,10 @@ function Guia({ abierta, onCerrar }: { abierta: boolean; onCerrar: () => void })
       <section><h3 className="font-semibold">1. Define a quién y cuándo quieres revisar</h3><p className="mt-1 text-muted-foreground-strong">Elige supervisor, analista, mes y semana. Cada mes tiene cuatro tramos: 1–7, 8–14, 15–21 y 22 hasta el último día. También puedes buscar por nombre, teléfono o código. La consulta se actualiza al cambiar cada filtro.</p></section>
       <section><h3 className="font-semibold">2. Empieza por lo que necesita atención</h3><p className="mt-1 text-muted-foreground-strong">En «Bandeja comercial», pulsa «Sin resultado» para encontrar citas vencidas cuyo resultado no se registró. «Programadas» muestra las que todavía están por realizar en el período.</p></section>
       <section><h3 className="font-semibold">3. Combina los filtros</h3><p className="mt-1 text-muted-foreground-strong">Abre «Más filtros» para elegir varios estados, modalidad, origen, resultado y seguimiento. Para filtrar un importe, selecciona primero soles o dólares.</p></section>
-      <section><h3 className="font-semibold">4. Cambia de vista según la tarea</h3><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Bandeja comercial:</strong> revisa responsable, estado y siguiente paso. «Pendientes primero» deja las vencidas arriba.</li><li><strong>Agenda:</strong> revisa citas por día y hora. Siempre usa orden cronológico.</li><li><strong>Resultados:</strong> empieza por el recorrido de quienes no asistieron. Pulsa una etapa para ver sus personas y abre un nombre para consultar el historial, las fechas y el depósito. Debajo, compara citas por lead y cumplimiento de cada analista: el 100% indica que alcanzó la meta interna configurada. La flecha junto al analista abre sus leads. «Columnas» muestra información adicional de actividad y supervisor.</li></ul><p className="mt-2 text-muted-foreground-strong">Las tres vistas conservan tus filtros y consultan el mismo conjunto de citas. Los filtros seleccionan las citas de origen; el seguimiento puede encontrar depósitos posteriores fuera del mes o semana, hasta el corte indicado. Cada etapa cuenta leads únicos y parte de la anterior. El porcentaje final usa como base quienes faltaron al inicio; un depósito anterior a la asistencia no entra en este flujo.</p></section>
-      <section><h3 className="font-semibold">5. Abre la ficha</h3><p className="mt-1 text-muted-foreground-strong">Pulsa el nombre del prospecto o «Detalle». La ficha lateral muestra fecha, responsable, monto estimado, resultado, notas y siguiente paso. «Ubicar en agenda» abre esa cita. «Citas de…» abre todas las citas de ese analista en el mes de la ficha. Estas dos acciones restablecen los demás filtros para que el destino sea visible.</p></section>
-      <section><h3 className="font-semibold">6. Limpia o exporta la consulta</h3><p className="mt-1 text-muted-foreground-strong">La × de cada etiqueta quita ese filtro. «Restablecer consulta» vuelve al mes completo. «Exportar citas» descarga todas las coincidencias, incluidas las de otras páginas. El CSV contiene el detalle de las citas; el promedio por lead y el seguimiento se consultan en Resultados.</p></section>
+      <section><h3 className="font-semibold">4. Cambia de vista según la tarea</h3><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Bandeja comercial:</strong> revisa responsable, estado y siguiente paso. «Pendientes primero» deja las vencidas arriba.</li><li><strong>Agenda:</strong> revisa citas por día y hora. Siempre usa orden cronológico.</li><li><strong>Resultados:</strong> empieza por el recorrido de quienes no asistieron. Pulsa una etapa para ver sus personas y abre un nombre para consultar el historial, las fechas y el depósito. Debajo, compara citas por lead y cumplimiento de cada analista: el 100% indica que alcanzó la meta interna configurada. La flecha junto al analista abre sus leads. «Columnas» muestra información adicional de actividad y supervisor.</li><li><strong>Proyección:</strong> hoja por analista con su propio periodo (Desde–Hasta). Se explica en el paso 5.</li></ul><p className="mt-2 text-muted-foreground-strong">Bandeja, Agenda y Resultados conservan tus filtros y consultan el mismo conjunto de citas. Los filtros seleccionan las citas de origen; el seguimiento puede encontrar depósitos posteriores fuera del mes o semana, hasta el corte indicado. Cada etapa cuenta leads únicos y parte de la anterior. El porcentaje final usa como base quienes faltaron al inicio; un depósito anterior a la asistencia no entra en este flujo.</p></section>
+      <section><h3 className="font-semibold">5. Lee la Proyección</h3><p className="mt-1 text-muted-foreground-strong">Tiene su propio periodo: elige Desde y Hasta o un atajo, y el supervisor en su barra; los filtros de arriba no se aplican aquí. Cuenta cada cita el día en que se creó, no el de su fecha prevista, e incluye las reuniones con clientes que no tienen lead. «Semanas» y «Días» reparten esas citas en columnas; «Días» admite hasta 31 días.</p><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Monto S/:</strong> suma del monto estimado de las citas con lead; los dólares se pasan a soles con el tipo de cambio del periodo.</li><li><strong>Ticket cita S/:</strong> Monto ÷ citas con lead. No es el «Ticket del mes» de Resultados, que divide el capital cerrado entre los clientes.</li><li><strong>% Entrev.:</strong> entrevistas ÷ citas con resultado (realizadas y no asistió). Una reunión con cliente a la que asistió cuenta como entrevista.</li><li><strong>% Conv.:</strong> personas entrevistadas con lead que después cerraron una venta del mismo analista, con la misma regla que Resultados.</li><li><strong>Proyectado citas S/:</strong> las citas que se esperan al cierre del periodo, al ritmo actual, × % de entrevistas × % de conversión × ticket cita. Se calcula solo con las citas con lead. No es el «Cierre proyectado» de Resultados.</li><li><strong>Referidos, Clientes y Leads:</strong> de dónde viene cada cita; suman el total de citas. «Clientes» son personas que ya eran clientes. Las reuniones con clientes que no tienen lead no suman al monto, al ticket, a la conversión ni al proyectado.</li></ul><p className="mt-2 text-muted-foreground-strong">Cada número abre su lista de citas. El embudo de cada columna ordena y filtra. En el celular la hoja se muestra en tarjetas.</p></section>
+      <section><h3 className="font-semibold">6. Abre la ficha</h3><p className="mt-1 text-muted-foreground-strong">Pulsa el nombre del prospecto o «Detalle». La ficha lateral muestra fecha, responsable, monto estimado, resultado, notas y siguiente paso. «Ubicar en agenda» abre esa cita. «Citas de…» abre todas las citas de ese analista en el mes de la ficha. Estas dos acciones restablecen los demás filtros para que el destino sea visible.</p></section>
+      <section><h3 className="font-semibold">7. Limpia o exporta la consulta</h3><p className="mt-1 text-muted-foreground-strong">La × de cada etiqueta quita ese filtro. «Restablecer consulta» vuelve al mes completo. «Exportar citas» descarga todas las coincidencias, incluidas las de otras páginas. El CSV contiene el detalle de las citas; el promedio por lead y el seguimiento se consultan en Resultados. En Proyección, «Exportar» descarga la hoja por analista o las citas del periodo.</p></section>
       <p className="rounded-lg bg-muted p-3 text-xs text-muted-foreground-strong">Responsable: el analista registrado en la cita; no acredita quién la creó. Las fechas de asistencia corresponden al registro de su resultado. Seguimiento al {corteLima(corte)}.</p>
     </SheetBody>
     <SheetFooter><Button className="w-full" onClick={onCerrar}>Entendido, volver a las citas</Button></SheetFooter>
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-cifras.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-cifras.tsx
new file mode 100644
index 00000000..1326ee03
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-cifras.tsx
@@ -0,0 +1,56 @@
+// Cifras de la Proyección: la misma pieza en la celda de la hoja (escritorio) y
+// en la tarjeta (celular). Todo número se abre en su lista; un 0 o «—» no es botón.
+import { numero } from '@/lib/format'
+import { cn } from '@/lib/utils'
+import type { ColumnaNumerica, MetricasProyeccion } from './proyeccion'
+import { ORIGEN_DE_COLUMNA, etiquetaCitas, type AbrirLista } from './proyeccion-columnas'
+import type { TramoProyeccion } from './proyeccion-rango'
+import { SenalMetrica } from './senal-resultado'
+
+export interface ObjetivosProyeccion { entrevistas: number; conversion: number }
+const soles = (valor: number | null) => valor === null ? '—' : `S/ ${numero(valor)}`
+
+/** Cifra que se abre: un 0 no es botón. */
+function Cifra({ cantidad, texto, etiqueta, onAbrir, dinero = false }: { cantidad: number; texto: string; etiqueta: string; onAbrir: () => void; dinero?: boolean }) {
+  const contenido = dinero && texto.startsWith('S/ ') ? <><span className="pc-m" aria-hidden>S/</span>{texto.slice(3)}</> : texto
+  if (!cantidad) return <span className="pc-n pc-cero">{contenido}</span>
+  return <button type="button" className="pc-n" aria-label={`${texto} ${etiqueta}`} onClick={onAbrir}>{contenido}</button>
+}
+
+/** Ticket cita y Proyectado: derivados, no listas; «—» sin base. */
+function Derivada({ valor }: { valor: number | null }) {
+  return <span className={cn('pc-n', valor === null && 'pc-cero')}>{valor === null ? '—' : <><span className="pc-m" aria-hidden>S/</span>{numero(valor)}</>}</span>
+}
+
+/** La cifra de una columna para una fila (`nombre`: el analista o «todos los analistas»). */
+export function CifraColumna({ columna, m, nombre, objetivos, abrir }: {
+  columna: ColumnaNumerica; m: MetricasProyeccion; nombre: string; objetivos: ObjetivosProyeccion; abrir: AbrirLista
+}) {
+  const de = `de ${nombre}`
+  switch (columna) {
+    case 'citas': return <Cifra cantidad={m.citas.length} texto={numero(m.citas.length)} etiqueta={`${etiquetaCitas('citas', m.citas.length)} ${de}`} onAbrir={() => abrir('citas')} />
+    case 'monto': return <Cifra cantidad={m.conMonto.length} texto={m.pendienteTc ? 'Pendiente de TC' : m.conMonto.length ? soles(m.monto) : '—'} etiqueta={`en citas ${de}`} onAbrir={() => abrir('monto')} dinero />
+    case 'ticket': return <Derivada valor={m.ticket} />
+    case 'entrevistas': return <SenalMetrica valor={m.pctEntrevistas} objetivo={objetivos.entrevistas} etiqueta={`% Entrev. ${de}`} abrir={m.entrevistas.length ? () => abrir('entrevistas') : undefined} />
+    case 'conversion': return <SenalMetrica valor={m.pctConversion} objetivo={objetivos.conversion} etiqueta={`% Conv. ${de}`} abrir={m.convertidas.length ? () => abrir('conversion') : undefined} />
+    case 'proyectado': return <Derivada valor={m.proyectado} />
+    default: {
+      const origen = ORIGEN_DE_COLUMNA[columna]!
+      const n = m[columna].length
+      return <Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas(origen, n)} ${de}`} onAbrir={() => abrir(origen)} />
+    }
+  }
+}
+
+/** Citas de una columna de tiempo (`i`: su posición en los tramos de la hoja). */
+export function CifraTramo({ m, i, tramo, nombre, abrir }: { m: MetricasProyeccion; i: number; tramo: TramoProyeccion; nombre: string; abrir: AbrirLista }) {
+  const n = m.porTramo[i]?.length ?? 0
+  return <Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas('citas', n)} de ${nombre}, ${tramo.rotulo}`} onAbrir={() => abrir('citas', tramo.id)} />
+}
+
+/** Título de una columna de tiempo: «S2» sobre «8–14» o «19» sobre «lun»; el lector oye «S2 8–14 oct» o «lun 19 oct». */
+export function CabeceraTramo({ tramo }: { tramo: TramoProyeccion }) {
+  // Cada palabra del detalle va entera: si no cabe, solo baja el mes («22–30» / «set»).
+  return <><span className="pc-tiempo-cab" aria-hidden>{tramo.titulo}<small>{tramo.detalle.split(' ').flatMap((parte, i) =>
+    i ? [' ', <span key={i}>{parte}</span>] : [<span key={i}>{parte}</span>])}</small></span><span className="sr-only">{tramo.nombre}</span></>
+}
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-columnas.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion-columnas.ts
new file mode 100644
index 00000000..cbce3f2c
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-columnas.ts
@@ -0,0 +1,43 @@
+// Catálogo de columnas de la Proyección y de las listas que abren sus cifras:
+// lo comparten la hoja (escritorio) y las tarjetas (celular). Módulo PURO.
+import { cn } from '@/lib/utils'
+import { COLUMNA_DE_ORIGEN, type CitaProyectada, type ColumnaNumerica, type ColumnaProyeccion, type MetricasProyeccion, type OrigenCita } from './proyeccion'
+import type { TramoProyeccion } from './proyeccion-rango'
+
+export type TipoColumna = 'texto' | 'num' | 'monto' | 'personas'
+/** `corto`: la etiqueta de la cifra en la tarjeta del celular. */
+export const COLUMNAS: readonly { id: ColumnaProyeccion; titulo: string; corto: string; tipo: TipoColumna }[] = [
+  { id: 'analista', titulo: 'Analista', corto: 'Analista', tipo: 'texto' },
+  { id: 'citas', titulo: 'Citas', corto: 'Citas', tipo: 'num' },
+  { id: 'monto', titulo: 'Monto S/', corto: 'Monto', tipo: 'monto' },
+  // «Ticket cita» y «Proyectado citas»: Resultados ya llama «Ticket del mes» y «Cierre proyectado» a otras cifras.
+  { id: 'ticket', titulo: 'Ticket cita S/', corto: 'Ticket cita', tipo: 'num' },
+  { id: 'entrevistas', titulo: '% Entrev.', corto: '% Entrev.', tipo: 'num' },
+  { id: 'conversion', titulo: '% Conv.', corto: '% Conv.', tipo: 'num' },
+  { id: 'proyectado', titulo: 'Proyectado citas S/', corto: 'Proyectado citas', tipo: 'num' },
+  { id: 'referidos', titulo: 'Referidos', corto: 'Referidos', tipo: 'personas' },
+  { id: 'clientes', titulo: 'Clientes', corto: 'Clientes', tipo: 'personas' },
+  { id: 'leads', titulo: 'Leads', corto: 'Leads', tipo: 'personas' },
+]
+/** Las columnas con cifra (todas menos Analista), en el orden de la hoja. */
+export const CIFRAS = COLUMNAS.filter((c): c is (typeof COLUMNAS)[number] & { id: ColumnaNumerica } => c.id !== 'analista')
+export const ORIGEN_DE_COLUMNA: Partial<Record<ColumnaProyeccion, OrigenCita>> = { referidos: 'referido', clientes: 'cliente', leads: 'lead' }
+
+export type TipoLista = 'citas' | 'monto' | 'entrevistas' | 'conversion' | OrigenCita
+/** Abre la lista de una cifra; `tramo`, la de una columna de tiempo. */
+export type AbrirLista = (tipo: TipoLista, tramo?: string) => void
+export const TITULOS_LISTA: Record<TipoLista, string> = {
+  citas: 'Citas', monto: 'Monto en citas', entrevistas: 'Entrevistas', conversion: 'Entrevistas que cerraron cliente',
+  referido: 'Citas de referidos', cliente: 'Citas con clientes', lead: 'Citas con leads',
+}
+const ETIQUETAS_CITAS: Record<'citas' | OrigenCita, [string, string]> = {
+  citas: ['cita', 'citas'], referido: ['cita de referido', 'citas de referidos'],
+  cliente: ['cita con cliente', 'citas con clientes'], lead: ['cita con lead', 'citas con leads'],
+}
+export const etiquetaCitas = (tipo: 'citas' | OrigenCita, n: number) => ETIQUETAS_CITAS[tipo][n === 1 ? 0 : 1]
+export const listaDe = (m: MetricasProyeccion, tipo: TipoLista) => tipo === 'citas' ? m.citas : tipo === 'monto' ? m.conMonto
+  : tipo === 'entrevistas' ? m.entrevistas : tipo === 'conversion' ? m.convertidas : m[COLUMNA_DE_ORIGEN[tipo]]
+/** Orden de toda lista de citas (y de su CSV): fecha y hora de la cita; a igualdad, el código. */
+export const porFechaDeCita = (a: CitaProyectada, b: CitaProyectada) =>
+  `${a.cita.fecha} ${a.cita.hora}`.localeCompare(`${b.cita.fecha} ${b.cita.hora}`) || a.cita.id.localeCompare(b.cita.id)
+export const claseTramo = (t: TramoProyeccion) => cn('pc-tiempo', t.domingo && 'pc-domingo', t.hoy && 'pc-hoy', t.futuro && 'pc-futuro')
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-embudo.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-embudo.tsx
index 84c657e0..57433dce 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-embudo.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-embudo.tsx
@@ -52,8 +52,18 @@ export function EmbudoColumna({ titulo, tipo, ancla, orden, opciones, seleccion,
 
   useLayoutEffect(() => {
     const r = ancla.getBoundingClientRect()
+    const left = Math.max(8, Math.min(r.left, window.innerWidth - 288))
+    // Si no cabe debajo y arriba hay más sitio («Filtros» de las tarjetas, al pie de la pantalla), se abre hacia arriba.
+    const alto = caja.current?.scrollHeight ?? 0
+    const debajo = window.innerHeight - r.bottom - 12
+    const encima = r.top - 12
+    if (alto > debajo && encima > debajo) {
+      const top = Math.max(8, r.top - 4 - alto)
+      setPosicion({ left, top, maxHeight: r.top - 4 - top })
+      return
+    }
     const top = Math.min(r.bottom + 4, Math.max(8, window.innerHeight - 220))
-    setPosicion({ left: Math.max(8, Math.min(r.left, window.innerWidth - 288)), top, maxHeight: window.innerHeight - top - 8 })
+    setPosicion({ left, top, maxHeight: window.innerHeight - top - 8 })
   }, [ancla])
   useEffect(() => {
     const menu = caja.current
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
index 5f4ab343..11015536 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
@@ -59,6 +59,18 @@ const tiempo = (nombre: 'Mes' | 'Semanas' | 'Días') => within(screen.getByRole(
 const atajo = (nombre: string) => within(screen.getByRole('group', { name: 'Atajos de periodo' })).getByRole('button', { name: nombre })
 /** Cabeceras de las columnas de tiempo tal como se ven (título y detalle). */
 const cabecerasTiempo = (hoja: HTMLElement) => [...hoja.querySelectorAll('thead th.pc-tiempo .pc-tiempo-cab')].map(e => `${e.firstChild?.textContent} ${e.querySelector('small')?.textContent}`)
+/** Intercepta las descargas: nombre del archivo y filas del CSV (sin la cabecera), en orden. */
+function capturarDescargas() {
+  const archivos: { nombre: string; blob: Blob }[] = []
+  const original = { crear: URL.createObjectURL, revocar: URL.revokeObjectURL }
+  let ultimo: Blob | null = null
+  URL.createObjectURL = vi.fn((blob: Blob) => { ultimo = blob; return 'blob:proyeccion' })
+  URL.revokeObjectURL = vi.fn()
+  const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) { archivos.push({ nombre: this.download, blob: ultimo! }) })
+  const filas = async (i: number) => (await archivos[i]!.blob.text()).split('\r\n').slice(1)
+  return { archivos, filas, restaurar: () => { URL.createObjectURL = original.crear; URL.revokeObjectURL = original.revocar; click.mockRestore() } }
+}
+const codigos = (filas: string[]) => filas.map(f => f.slice(1, f.indexOf('"', 1)))
 
 describe('Pestaña Proyección de Citas', () => {
   it('pinta una hoja plana, una fila por analista y # continuo; toda cifra es botón, salvo los ceros y los derivados', async () => {
@@ -209,7 +221,8 @@ describe('Pestaña Proyección de Citas', () => {
     })
     try {
       const { usuario, hoja } = await abrirProyeccion()
-      await usuario.click(screen.getByRole('button', { name: 'Exportar CSV' }))
+      await usuario.click(screen.getByRole('button', { name: 'Exportar' }))
+      await usuario.click(screen.getByRole('menuitem', { name: 'Hoja por analista' }))
       expect(click).toHaveBeenCalledOnce()
       const csvHoja = (await leer(blobs[0]!)).split('\r\n')
       expect(csvHoja).toHaveLength(5)
@@ -221,7 +234,7 @@ describe('Pestaña Proyección de Citas', () => {
       await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
       const csvLista = (await leer(blobs[1]!)).split('\r\n')
       expect(csvLista).toHaveLength(5)
-      expect(csvLista.find(l => l.startsWith('"a2"'))).toBe('"a2","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
+      expect(csvLista.find(l => l.startsWith('"a2"'))).toBe('"a2","2026-10-03","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
       expect(within(lista).getByText('Se descargó el CSV con 4 citas.')).toBeVisible()
       URL.createObjectURL = vi.fn(() => { throw new Error('sin memoria') })
       await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
@@ -232,6 +245,40 @@ describe('Pestaña Proyección de Citas', () => {
     }
   })
 
+  it('Exportar abre un menú con «Hoja por analista» y «Citas del periodo»: flechas para moverse y Esc lo cierra devolviendo el foco', async () => {
+    const descargas = capturarDescargas()
+    try {
+      const { usuario } = await abrirProyeccion()
+      const exportar = screen.getByRole('button', { name: 'Exportar' })
+      expect(exportar).toHaveAttribute('aria-haspopup', 'menu')
+      await usuario.click(exportar)
+      const menu = screen.getByRole('menu')
+      expect(within(menu).getAllByRole('menuitem').map(item => item.textContent)).toEqual(['Hoja por analista', 'Citas del periodo'])
+      expect(within(menu).getByRole('menuitem', { name: 'Hoja por analista' })).toHaveFocus()
+      await usuario.keyboard('{ArrowDown}')
+      expect(within(menu).getByRole('menuitem', { name: 'Citas del periodo' })).toHaveFocus()
+      await usuario.keyboard('{Escape}')
+      expect(screen.queryByRole('menu')).not.toBeInTheDocument()
+      expect(exportar).toHaveFocus()
+      expect(descargas.archivos).toHaveLength(0)
+      // Con teclado: Enter elige; el menú se cierra, el foco vuelve a Exportar y el aviso lo cuenta.
+      await usuario.keyboard('{Enter}')
+      await usuario.keyboard('{ArrowDown}')
+      await usuario.keyboard('{Enter}')
+      expect(screen.queryByRole('menu')).not.toBeInTheDocument()
+      expect(exportar).toHaveFocus()
+      expect(descargas.archivos.map(a => a.nombre)).toEqual(['proyeccion-citas-del-periodo-2026-10-01_2026-10-19.csv'])
+      expect(screen.getByText('Se descargaron las 7 citas del periodo.')).toBeVisible()
+      // (Blob.text() descarta el BOM que el CSV lleva para Excel.)
+      const [cabecera] = (await descargas.archivos[0]!.blob.text()).split('\r\n')
+      expect(cabecera).toBe('"Código de cita","Creada","Fecha","Hora","Persona","Analista","Supervisor","Estado","Moneda","Monto","Monto S/","Origen"')
+      await usuario.click(exportar)
+      await usuario.click(screen.getByRole('menuitem', { name: 'Hoja por analista' }))
+      expect(descargas.archivos[1]!.nombre).toBe('proyeccion-por-analista-2026-10-01_2026-10-19.csv')
+      expect(await descargas.filas(1)).toHaveLength(4)
+    } finally { descargas.restaurar() }
+  })
+
   it('el rango nace del mes de arriba hasta hoy; los atajos y las fechas lo cambian y se valida', async () => {
     const { usuario, hoja } = await abrirProyeccion()
     expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–19 oct 2026')
@@ -306,7 +353,7 @@ describe('Pestaña Proyección de Citas', () => {
     expect(within(hoja).queryAllByRole('button', { name: /de todos los analistas/ })).toEqual([])
     expect(within(filaTotal(hoja)).getAllByRole('cell').map(td => td.textContent)).toEqual(['Σ', '0', '—', '—', '— · Sin base para evaluar', '— · Sin base para evaluar', '—', '0', '0', '0'])
     expect(screen.queryByRole('group', { name: 'Totales de la proyección' })).not.toBeInTheDocument()
-    expect(screen.getByRole('button', { name: 'Exportar CSV' })).toBeDisabled()
+    expect(screen.getByRole('button', { name: 'Exportar' })).toBeDisabled()
     // Sin citas, las columnas de tiempo también se pintan, en cero y sin botones.
     await userEvent.setup().click(tiempo('Semanas'))
     expect(cabecerasTiempo(hoja)).toEqual(['S1 1–7', 'S2 8–14', 'S3 15–19'])
@@ -331,10 +378,10 @@ describe('Pestaña Proyección de Citas', () => {
     const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
     expect(nombres(hoja)).toEqual(['ATAna Torres', 'DSDiego Salas', 'LVLuis Vega'])
     expect(screen.queryByText('Revisa los filtros de la consulta')).not.toBeInTheDocument()
-    // Barra única: Supervisor · rango · atajos · columnas de tiempo · Exportar CSV.
+    // Barra única: Supervisor · rango · atajos · columnas de tiempo · Exportar.
     const barra = screen.getByRole('group', { name: 'Consulta de la proyección' })
     expect([...barra.querySelectorAll('label, strong, [role=group], .pc-acciones')].map(e => e.getAttribute('aria-label') ?? e.textContent!.slice(0, 10)))
-      .toEqual(['Supervisor', '1–19 oct 2', 'Desde', 'Hasta', 'Atajos de periodo', 'Columnas de tiempo', 'Exportar C'])
+      .toEqual(['Supervisor', '1–19 oct 2', 'Desde', 'Hasta', 'Atajos de periodo', 'Columnas de tiempo', 'Exportar'])
     const supervisor = within(barra).getByLabelText('Supervisor')
     expect([...supervisor.querySelectorAll('option')].map(o => o.textContent)).toEqual(['Todos', 'Claudia Ríos', 'Javier Vega'])
     await usuario.selectOptions(supervisor, 'sup-2')
@@ -539,7 +586,7 @@ describe('Proyección con reuniones con clientes sin lead', () => {
       expect(within(lista).getByRole('row', { name: /Cliente fuera de tu cartera/ })).toHaveTextContent('No asistió—Cliente')
       await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
       const texto = await blobs[0]!.text()
-      expect(texto.split('\r\n')[1]).toBe('"r1","2026-10-10","10:00","CLIENTE UNO","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
+      expect(texto.split('\r\n')[1]).toBe('"r1","2026-10-08","2026-10-10","10:00","CLIENTE UNO","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
       await usuario.click(within(lista).getByRole('button', { name: 'Cerrar lista' }))
       // Las citas con lead siguen abriendo su ficha.
       await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '6 citas de Ana Torres' }))
@@ -552,6 +599,37 @@ describe('Proyección con reuniones con clientes sin lead', () => {
     }
   })
 
+  it('«Citas del periodo» trae exactamente las citas que suma la columna Citas del total, reuniones con clientes incluidas, también tras un embudo', async () => {
+    const descargas = capturarDescargas()
+    try {
+      const { usuario, hoja } = await abrirProyeccion(cargador())
+      const total = filaTotal(hoja)
+      expect(within(total).getByRole('button', { name: '9 citas de todos los analistas' })).toBeVisible()
+      const exportarPeriodo = async () => {
+        await usuario.click(screen.getByRole('button', { name: 'Exportar' }))
+        await usuario.click(screen.getByRole('menuitem', { name: 'Citas del periodo' }))
+        return descargas.filas(descargas.archivos.length - 1)
+      }
+      const periodo = await exportarPeriodo()
+      expect(descargas.archivos[0]!.nombre).toBe('proyeccion-citas-del-periodo-2026-10-01_2026-10-19.csv')
+      expect(codigos(periodo).sort()).toEqual(['a1', 'a2', 'a3', 'a4', 'd1', 'd2', 'l1', 'r1', 'r2'])
+      expect(periodo.find(f => f.startsWith('"r2"'))).toBe('"r2","2026-10-11","2026-10-10","10:00","Cliente fuera de tu cartera","Ana Torres","Claudia Ríos","No asistió","","","","Cliente"')
+      // Las mismas filas, en el mismo orden, que el CSV de la lista detrás de esa cifra.
+      await usuario.click(within(total).getByRole('button', { name: '9 citas de todos los analistas' }))
+      const lista = screen.getByRole('dialog', { name: 'Citas · Total' })
+      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
+      expect(await descargas.filas(1)).toEqual(periodo)
+      await usuario.click(within(lista).getByRole('button', { name: 'Cerrar lista' }))
+      // Un Mín de Citas oculta filas: el total y el CSV del periodo dejan fuera las mismas citas.
+      await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Citas' }))
+      await usuario.type(within(screen.getByRole('dialog', { name: 'Filtrar Citas' })).getByRole('spinbutton', { name: 'Mín' }), '3')
+      await usuario.click(within(screen.getByRole('dialog', { name: 'Filtrar Citas' })).getByRole('button', { name: 'Aplicar' }))
+      expect(within(total).getByRole('button', { name: '6 citas de todos los analistas' })).toBeVisible()
+      expect(codigos(await exportarPeriodo()).sort()).toEqual(['a1', 'a2', 'a3', 'a4', 'r1', 'r2'])
+      expect(screen.getByText('Se descargaron las 6 citas del periodo.')).toBeVisible()
+    } finally { descargas.restaurar() }
+  })
+
   it('pide el rango a la pantalla y, mientras sus reuniones no lleguen o si fallan, no pinta cifras parciales', async () => {
     const pedirRango = vi.fn()
     const datos = { ...cargador({ rango: null }), onRangoProyeccion: pedirRango }
@@ -580,3 +658,132 @@ describe('Proyección con reuniones con clientes sin lead', () => {
     expect(pedirRango).toHaveBeenLastCalledWith(null)
   })
 })
+
+// Fase 3: en el celular (< 768 px) la hoja se vuelve tarjetas, con el mismo estado (orden, embudos y listas).
+describe('Proyección en el celular: tarjetas', () => {
+  beforeEach(() => {
+    vi.stubGlobal('matchMedia', (consulta: string) => ({
+      matches: consulta.includes('max-width: 767px') || consulta.includes('prefers-reduced-motion'), media: consulta,
+      addEventListener: () => {}, removeEventListener: () => {},
+    }))
+  })
+  afterEach(() => { vi.unstubAllGlobals() })
+
+  async function abrirTarjetas() {
+    const usuario = userEvent.setup()
+    render(<ContextoCitas value={fuente}><TableroCitas /></ContextoCitas>)
+    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
+    return { usuario, lista: screen.getByRole('list', { name: 'Proyección de citas por analista · 1–19 oct 2026' }) }
+  }
+  const tarjetas = (lista: HTMLElement) => within(lista).getAllByRole('listitem')
+  const nombresTarjetas = (lista: HTMLElement) => tarjetas(lista).map(t => t.querySelector('.pc-tarjeta-nombre')!.textContent)
+  const tarjeta = (lista: HTMLElement, nombre: string) => tarjetas(lista).find(t => t.querySelector('.pc-tarjeta-nombre')!.textContent === nombre)!
+  const filtros = () => screen.getByRole('button', { name: /^Filtros/ })
+
+  it('una tarjeta por analista en el orden de la hoja, con el Total primero; cada cifra es botón (salvo ceros y derivados) y abre la misma lista', async () => {
+    const { usuario, lista } = await abrirTarjetas()
+    expect(screen.queryByRole('table', { name: /Proyección de citas por analista/ })).not.toBeInTheDocument()
+    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Ana Torres', 'Diego Salas', 'Luis Vega'])
+    const ana = tarjeta(lista, 'Ana Torres')
+    expect(ana.querySelector('.pc-tarjeta-sup')).toHaveTextContent('Claudia Ríos')
+    expect(within(ana).getAllByRole('term').map(dt => dt.textContent)).toEqual(
+      ['Citas', 'Monto', 'Ticket cita', '% Entrev.', '% Conv.', 'Proyectado citas', 'Referidos', 'Clientes', 'Leads'])
+    for (const t of tarjetas(lista)) {
+      for (const par of t.querySelectorAll<HTMLElement>('dl > div')) {
+        const texto = within(par).getByRole('definition').textContent!.trim().replace(/ · .*$/, '')
+        const sinValor = ['0', '—', '0%'].includes(texto)
+        expect(within(par).queryByRole('button') !== null, `${t.textContent} · ${par.dataset.col}`).toBe(!sinValor && !['ticket', 'proyectado'].includes(par.dataset.col!))
+      }
+    }
+    // El semáforo de % Entrev. y % Conv. se conserva.
+    expect(within(ana).getByRole('button', { name: /^% Entrev\. de Ana Torres: 66\.7%/ })).toHaveAttribute('data-senal')
+    expect(ana.querySelector('[data-col="ticket"] dd')).toHaveTextContent('S/9,375')
+    await usuario.click(within(ana).getByRole('button', { name: '4 citas de Ana Torres' }))
+    let detalle = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
+    expect(within(detalle).getByTestId('pc-detalle-conteo')).toHaveTextContent('1–19 oct 2026 · 4 citas')
+    expect(within(detalle).getAllByRole('row')).toHaveLength(5)
+    await usuario.click(within(detalle).getByRole('button', { name: 'Cerrar lista' }))
+    const total = tarjeta(lista, 'Total · 3 analistas')
+    await usuario.click(within(total).getByRole('button', { name: '1 cita con cliente de todos los analistas' }))
+    detalle = screen.getByRole('dialog', { name: 'Citas con clientes · Total' })
+    expect(within(detalle).getByRole('row', { name: /Persona d1/ })).toHaveTextContent('Diego Salas')
+    await usuario.keyboard('{Escape}')
+    await usuario.click(within(ana).getByRole('button', { name: /^% Conv\. de Ana Torres: 50%/ }))
+    expect(within(screen.getByRole('dialog', { name: 'Entrevistas que cerraron cliente · Ana Torres' })).getAllByRole('row')).toHaveLength(2)
+  })
+
+  it('«Ordenar por» y «Filtros» usan el mismo orden y los mismos embudos de la hoja', async () => {
+    const { usuario, lista } = await abrirTarjetas()
+    const ordenar = screen.getByRole('combobox', { name: 'Ordenar por' })
+    expect(ordenar).toHaveValue('citas')
+    const sentido = screen.getByRole('button', { name: 'Orden de mayor a menor' })
+    await usuario.selectOptions(ordenar, 'ticket')
+    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Diego Salas', 'Ana Torres', 'Luis Vega'])
+    await usuario.click(sentido)
+    expect(sentido).toHaveAccessibleName('Orden de menor a mayor')
+    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Luis Vega', 'Ana Torres', 'Diego Salas'])
+    await usuario.selectOptions(ordenar, 'analista')
+    expect(sentido).toHaveAccessibleName('Orden de A a Z')
+    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Ana Torres', 'Diego Salas', 'Luis Vega'])
+
+    // Filtros: las mismas columnas que tienen embudo en la hoja; cada una abre su embudo.
+    await usuario.click(filtros())
+    expect(screen.getAllByRole('menuitem').map(item => item.textContent)).toEqual(
+      ['Analista', 'Citas', 'Monto', 'Ticket cita', '% Entrev.', '% Conv.', 'Proyectado citas', 'Referidos', 'Clientes', 'Leads'])
+    await usuario.click(screen.getByRole('menuitem', { name: 'Analista' }))
+    let embudo = screen.getByRole('dialog', { name: 'Filtrar Analista' })
+    expect(within(embudo).getByRole('searchbox', { name: 'Buscar analista' })).toHaveFocus()
+    await usuario.click(within(embudo).getByRole('checkbox', { name: 'Luis Vega · 1 cita' }))
+    await usuario.click(within(embudo).getByRole('button', { name: 'Aplicar' }))
+    expect(nombresTarjetas(lista)).toEqual(['Total · 2 analistas', 'Ana Torres', 'Diego Salas'])
+    expect(screen.getByRole('group', { name: 'Filtros de columna' })).toHaveTextContent('Analista Ana Torres, Diego Salas')
+    // El embudo se ancla a «Filtros»: al cerrarse, el foco vuelve ahí, que ya cuenta el filtro.
+    expect(filtros()).toHaveFocus()
+    expect(filtros()).toHaveAccessibleName('Filtros, 1 con filtro')
+    await usuario.click(filtros())
+    expect(screen.getByRole('menuitem', { name: 'Analista, con filtro' })).toBeVisible()
+    await usuario.keyboard('{Escape}')
+    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
+    expect(filtros()).toHaveFocus()
+    // Sin cabeceras, quitar el chip devuelve el foco a «Filtros», no a <body>.
+    await usuario.click(screen.getByRole('button', { name: 'Quitar filtro de Analista' }))
+    expect(nombresTarjetas(lista)).toHaveLength(4)
+    expect(filtros()).toHaveFocus()
+    expect(filtros()).toHaveAccessibleName('Filtros')
+
+    await usuario.click(filtros())
+    await usuario.click(screen.getByRole('menuitem', { name: 'Clientes' }))
+    embudo = screen.getByRole('dialog', { name: 'Filtrar Clientes' })
+    expect(within(embudo).getAllByRole('checkbox').map(c => c.getAttribute('aria-label'))).toEqual(['Seleccionar todo', 'Persona d1 · 1 cita'])
+    await usuario.keyboard('{Escape}')
+    expect(filtros()).toHaveFocus()
+    await usuario.click(filtros())
+    await usuario.click(screen.getByRole('menuitem', { name: 'Monto' }))
+    embudo = screen.getByRole('dialog', { name: 'Filtrar Monto S/' })
+    await usuario.click(within(embudo).getByRole('checkbox', { name: 'Soles · S/ 115,000 · 6 citas' }))
+    await usuario.click(within(embudo).getByRole('button', { name: 'Aplicar' }))
+    expect(nombresTarjetas(lista)).toEqual(['Total · 1 analista', 'Ana Torres'])
+    expect(within(tarjeta(lista, 'Ana Torres')).getByRole('button', { name: 'S/ 7,500 en citas de Ana Torres' })).toBeVisible()
+  })
+
+  it('Semanas y Días: los tramos van en una fila de la tarjeta, cada número abre su lista; Exportar sigue en la barra', async () => {
+    const { usuario, lista } = await abrirTarjetas()
+    expect(lista.querySelectorAll('.pc-tarjeta-tramos')).toHaveLength(0)
+    await usuario.click(tiempo('Semanas'))
+    const ana = tarjeta(lista, 'Ana Torres')
+    const semanas = within(ana).getByRole('group', { name: 'Citas por semana de Ana Torres' })
+    expect([...semanas.querySelectorAll('.sr-only')].map(e => e.textContent)).toEqual(['S1 1–7 oct', 'S2 8–14 oct', 'S3 15–19 oct'])
+    expect([...semanas.querySelectorAll('.pc-n')].map(e => e.textContent)).toEqual(['3', '1', '0'])
+    expect(within(tarjeta(lista, 'Total · 3 analistas')).getByRole('group', { name: 'Citas por semana de todos los analistas' })).toBeVisible()
+    await usuario.click(within(semanas).getByRole('button', { name: '1 cita de Ana Torres, S2 8–14 oct' }))
+    const detalle = screen.getByRole('dialog', { name: 'Citas · S2 8–14 oct · Ana Torres' })
+    expect(within(detalle).getByRole('row', { name: /Persona a4/ })).toBeVisible()
+    await usuario.keyboard('{Escape}')
+    await usuario.click(tiempo('Días'))
+    const dias = within(tarjeta(lista, 'Luis Vega')).getByRole('group', { name: 'Citas por día de Luis Vega' })
+    expect(dias.querySelectorAll('.pc-tiempo')).toHaveLength(19)
+    expect(dias.querySelector('.pc-hoy .sr-only')).toHaveTextContent('lun 19 oct')
+    expect(within(dias).getByRole('button', { name: '1 cita de Luis Vega, 18 oct' })).toBeVisible()
+    expect(screen.getByRole('button', { name: 'Exportar' })).toBeEnabled()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
index 46b3116f..eb2efb85 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
@@ -1,62 +1,39 @@
 // Pestaña «Proyección» de Citas: hoja plana, una fila por analista, con embudos
 // tipo Excel en cada cabecera y, a elección, columnas de semanas o días antes de
-// «Citas». Todo número se abre en su lista.
+// «Citas». En el celular (< 768 px), una tarjeta por analista con el mismo orden,
+// los mismos embudos y las mismas listas. Todo número se abre en su lista.
 import { useCallback, useMemo, useRef, useState } from 'react'
-import { ArrowDown, Download, Filter, X } from 'lucide-react'
+import { ArrowDown, ChevronDown, Download, Filter, X } from 'lucide-react'
 import { Button } from '@/components/ui/button'
+import { DropdownItem, DropdownMenu } from '@/components/ui/dropdown-menu'
 import { Select } from '@/components/ui/select'
 import { iniciales, numero } from '@/lib/format'
+import { useEsMovil } from '@/lib/media'
 import { METAS_CITAS_INICIALES } from '@/lib/metas-citas-config'
 import { useTipoCambio } from '@/lib/tipo-cambio'
 import { cn } from '@/lib/utils'
 import { useDatosCitas } from './contexto'
 import { fechaLocalCitas } from './fecha-comercial'
 import {
-  COLUMNA_DE_ORIGEN, ORDEN_INICIAL, ORIGENES, calcularProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas,
+  ORDEN_INICIAL, calcularProyeccion, csvCitasProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas,
   opcionesPersonas, type ColumnaNumerica, type ColumnaProyeccion, type FiltrosColumnas,
-  type MetricasProyeccion, type OrdenProyeccion, type OrigenCita, type ReunionClienteProyeccion,
+  type MetricasProyeccion, type OrdenProyeccion, type ReunionClienteProyeccion,
 } from './proyeccion'
 import {
   diasPermitidos, mesesDelRango, rotuloRango, tiempoEfectivo, type RangoProyeccion, type TiempoProyeccion, type TramoProyeccion,
 } from './proyeccion-rango'
+import { CIFRAS, COLUMNAS, ORIGEN_DE_COLUMNA, TITULOS_LISTA, claseTramo, listaDe, porFechaDeCita, type AbrirLista, type TipoLista } from './proyeccion-columnas'
+import { CabeceraTramo, CifraColumna, CifraTramo, type ObjetivosProyeccion } from './proyeccion-cifras'
 import { BarraRango } from './proyeccion-barra-rango'
 import { EmbudoColumna, type CambioEmbudo } from './proyeccion-embudo'
 import { DetalleProyeccion, type ListaProyeccion } from './proyeccion-detalle'
 import { descargarCsv } from './proyeccion-descarga'
-import { SenalMetrica } from './senal-resultado'
+import { ControlesTarjetas, TarjetasProyeccion } from './proyeccion-tarjetas'
 import './avance-mensual.css'
 import './proyeccion.css'
 
-type TipoColumna = 'texto' | 'num' | 'monto' | 'personas'
-const COLUMNAS: readonly { id: ColumnaProyeccion; titulo: string; tipo: TipoColumna }[] = [
-  { id: 'analista', titulo: 'Analista', tipo: 'texto' },
-  { id: 'citas', titulo: 'Citas', tipo: 'num' },
-  { id: 'monto', titulo: 'Monto S/', tipo: 'monto' },
-  // «Ticket cita» y «Proyectado citas»: Resultados ya llama «Ticket del mes» y «Cierre proyectado» a otras cifras.
-  { id: 'ticket', titulo: 'Ticket cita S/', tipo: 'num' },
-  { id: 'entrevistas', titulo: '% Entrev.', tipo: 'num' },
-  { id: 'conversion', titulo: '% Conv.', tipo: 'num' },
-  { id: 'proyectado', titulo: 'Proyectado citas S/', tipo: 'num' },
-  { id: 'referidos', titulo: 'Referidos', tipo: 'personas' },
-  { id: 'clientes', titulo: 'Clientes', tipo: 'personas' },
-  { id: 'leads', titulo: 'Leads', tipo: 'personas' },
-]
-const ORIGEN_DE_COLUMNA: Partial<Record<ColumnaProyeccion, OrigenCita>> = { referidos: 'referido', clientes: 'cliente', leads: 'lead' }
-type TipoLista = 'citas' | 'monto' | 'entrevistas' | 'conversion' | OrigenCita
-const TITULOS_LISTA: Record<TipoLista, string> = {
-  citas: 'Citas', monto: 'Monto en citas', entrevistas: 'Entrevistas', conversion: 'Entrevistas que cerraron cliente',
-  referido: 'Citas de referidos', cliente: 'Citas con clientes', lead: 'Citas con leads',
-}
-const ETIQUETAS_CITAS: Record<'citas' | OrigenCita, [string, string]> = {
-  citas: ['cita', 'citas'], referido: ['cita de referido', 'citas de referidos'],
-  cliente: ['cita con cliente', 'citas con clientes'], lead: ['cita con lead', 'citas con leads'],
-}
-const etiquetaCitas = (tipo: 'citas' | OrigenCita, n: number) => ETIQUETAS_CITAS[tipo][n === 1 ? 0 : 1]
 const SIN_CITAS: never[] = []
 const SIN_REUNIONES: readonly ReunionClienteProyeccion[] = []
-const listaDe = (m: MetricasProyeccion, tipo: TipoLista) => tipo === 'citas' ? m.citas : tipo === 'monto' ? m.conMonto
-  : tipo === 'entrevistas' ? m.entrevistas : tipo === 'conversion' ? m.convertidas : m[COLUMNA_DE_ORIGEN[tipo]]
-const soles = (valor: number | null) => valor === null ? '—' : `S/ ${numero(valor)}`
 const resumirNombres = (nombres: string[]) => nombres.slice(0, 2).join(', ') + (nombres.length > 2 ? ` +${nombres.length - 2}` : '')
 const textoRango = (r: { min?: number | undefined; max?: number | undefined } | undefined) => !r ? ''
   : r.min !== undefined && r.max !== undefined ? `${numero(r.min, 2)} – ${numero(r.max, 2)}` : r.min !== undefined ? `≥ ${numero(r.min, 2)}` : r.max !== undefined ? `≤ ${numero(r.max, 2)}` : ''
@@ -64,7 +41,6 @@ const textoRango = (r: { min?: number | undefined; max?: number | undefined } |
 const TIEMPOS: readonly { id: TiempoProyeccion; etiqueta: string }[] = [
   { id: 'mes', etiqueta: 'Mes' }, { id: 'semanas', etiqueta: 'Semanas' }, { id: 'dias', etiqueta: 'Días' },
 ]
-const claseTramo = (t: TramoProyeccion) => cn('pc-tiempo', t.domingo && 'pc-domingo', t.hoy && 'pc-hoy', t.futuro && 'pc-futuro')
 
 /** Supervisores del equipo y de las citas del rango; el elegido siempre aparece. «Sin supervisor» al final. */
 function supervisoresDe(listas: readonly (readonly { supervisorId: string; supervisor: string }[])[], elegido: string): [string, string][] {
@@ -74,33 +50,13 @@ function supervisoresDe(listas: readonly (readonly { supervisorId: string; super
   return [...nombres].sort(([a, x], [b, y]) => Number(a === 'sin_supervisor') - Number(b === 'sin_supervisor') || x.localeCompare(y, 'es'))
 }
 
-/** Cifra que se abre: un 0 no es botón. */
-function Cifra({ cantidad, texto, etiqueta, onAbrir, dinero = false }: { cantidad: number; texto: string; etiqueta: string; onAbrir: () => void; dinero?: boolean }) {
-  const contenido = dinero && texto.startsWith('S/ ') ? <><span className="pc-m" aria-hidden>S/</span>{texto.slice(3)}</> : texto
-  if (!cantidad) return <span className="pc-n pc-cero">{contenido}</span>
-  return <button type="button" className="pc-n" aria-label={`${texto} ${etiqueta}`} onClick={onAbrir}>{contenido}</button>
-}
-
 function Celdas({ m, nombre, objetivos, tramos, abrir }: {
-  m: MetricasProyeccion; nombre: string; objetivos: { entrevistas: number; conversion: number }
-  tramos: readonly TramoProyeccion[]; abrir: (tipo: TipoLista, tramo?: string) => void
+  m: MetricasProyeccion; nombre: string; objetivos: ObjetivosProyeccion; tramos: readonly TramoProyeccion[]; abrir: AbrirLista
 }) {
-  const de = `de ${nombre}`
   return <>
-    {tramos.map((t, i) => {
-      const n = m.porTramo[i]?.length ?? 0
-      return <td key={t.id} className={claseTramo(t)}><Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas('citas', n)} ${de}, ${t.rotulo}`} onAbrir={() => abrir('citas', t.id)} /></td>
-    })}
-    <td className={tramos.length ? 'pc-tcierre' : undefined}><Cifra cantidad={m.citas.length} texto={numero(m.citas.length)} etiqueta={`${etiquetaCitas('citas', m.citas.length)} ${de}`} onAbrir={() => abrir('citas')} /></td>
-    <td><Cifra cantidad={m.conMonto.length} texto={m.pendienteTc ? 'Pendiente de TC' : m.conMonto.length ? soles(m.monto) : '—'} etiqueta={`en citas ${de}`} onAbrir={() => abrir('monto')} dinero /></td>
-    <td><span className={cn('pc-n', m.ticket === null && 'pc-cero')}>{m.ticket === null ? '—' : <><span className="pc-m" aria-hidden>S/</span>{numero(m.ticket)}</>}</span></td>
-    <td><SenalMetrica valor={m.pctEntrevistas} objetivo={objetivos.entrevistas} etiqueta={`% Entrev. ${de}`} abrir={m.entrevistas.length ? () => abrir('entrevistas') : undefined} /></td>
-    <td><SenalMetrica valor={m.pctConversion} objetivo={objetivos.conversion} etiqueta={`% Conv. ${de}`} abrir={m.convertidas.length ? () => abrir('conversion') : undefined} /></td>
-    <td className="pc-proyectado"><span className={cn('pc-n', m.proyectado === null && 'pc-cero')}>{m.proyectado === null ? '—' : <><span className="pc-m" aria-hidden>S/</span>{numero(m.proyectado)}</>}</span></td>
-    {ORIGENES.map(origen => {
-      const n = m[COLUMNA_DE_ORIGEN[origen]].length
-      return <td key={origen}><Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas(origen, n)} ${de}`} onAbrir={() => abrir(origen)} /></td>
-    })}
+    {tramos.map((t, i) => <td key={t.id} className={claseTramo(t)}><CifraTramo m={m} i={i} tramo={t} nombre={nombre} abrir={abrir} /></td>)}
+    {CIFRAS.map(col => <td key={col.id} className={col.id === 'citas' && tramos.length ? 'pc-tcierre' : col.id === 'proyectado' ? 'pc-proyectado' : undefined}>
+      <CifraColumna columna={col.id} m={m} nombre={nombre} objetivos={objetivos} abrir={abrir} /></td>)}
   </>
 }
 
@@ -134,9 +90,14 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
   const [detalle, setDetalle] = useState<{ tipo: TipoLista; filaId: string | null; tramo?: string | undefined } | null>(null)
   const [menu, setMenu] = useState<{ columna: ColumnaProyeccion; ancla: HTMLButtonElement } | null>(null)
   const [aviso, setAviso] = useState('')
+  const esMovil = useEsMovil()
+  // La hoja (escritorio) o la lista de tarjetas (celular): respaldo del foco al cerrar una lista.
   const hojaRef = useRef<HTMLDivElement>(null)
-  // Al quitar un filtro su chip desaparece: el foco vuelve al embudo de esa columna.
+  // Al quitar un filtro su chip desaparece: el foco vuelve al embudo de esa columna
+  // o, en tarjetas (sin cabeceras), al botón «Filtros», que es su ancla.
   const embudos = useRef<Partial<Record<ColumnaProyeccion, HTMLButtonElement | null>>>({})
+  const filtrosRef = useRef<HTMLButtonElement>(null)
+  const enfocarEmbudo = (columna: ColumnaProyeccion) => (embudos.current[columna] ?? filtrosRef.current)?.focus()
   // Un embudo de personas o analistas de otro periodo o equipo vaciaría la hoja.
   const { desde, hasta } = rango
   const firma = [desde, hasta, equipo].join('|')
@@ -151,7 +112,7 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
     conversiones: avance?.conversiones ?? null, poblacion: avance?.poblacion, analistaResultado: avance?.control.configuracion.analista_resultado,
   }, columnas, orden), [citas, reunionesClientes, equipo, desde, hasta, tiempo, corte, tc?.promedio, avance, columnas, orden])
   const vistaTiempo = tiempoEfectivo(tiempo, rango)
-  const objetivos = {
+  const objetivos: ObjetivosProyeccion = {
     entrevistas: avance?.control.configuracion.entrevistas_porcentaje ?? gestion?.entrevistasPorcentaje ?? METAS_CITAS_INICIALES.entrevistas_porcentaje,
     conversion: avance?.control.configuracion.depositos_porcentaje ?? gestion?.depositosPorcentaje ?? METAS_CITAS_INICIALES.depositos_porcentaje,
   }
@@ -171,7 +132,7 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
   const lista: ListaProyeccion | null = detalle && fuenteDetalle && vigente ? {
     titulo: [TITULOS_LISTA[detalle.tipo], tramo?.rotulo, filaAbierta?.nombre ?? 'Total'].filter(Boolean).join(' · '),
     periodo: tramo ? rotuloRango(tramo) : rotulo,
-    lista: [...(tramo ? fuenteDetalle.porTramo[iTramo] ?? [] : listaDe(fuenteDetalle, detalle.tipo))].sort((a, b) => `${a.cita.fecha} ${a.cita.hora}`.localeCompare(`${b.cita.fecha} ${b.cita.hora}`) || a.cita.id.localeCompare(b.cita.id)),
+    lista: [...(tramo ? fuenteDetalle.porTramo[iTramo] ?? [] : listaDe(fuenteDetalle, detalle.tipo))].sort(porFechaDeCita),
     conAnalista: !filaAbierta, archivo: `proyeccion-citas-${detalle.tipo}-${tramo ? `${tramo.desde}_${tramo.hasta}` : sufijo}.csv`,
   } : null
 
@@ -192,9 +153,10 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
       return siguiente
     })
   }
-  function exportar() {
-    setAviso(descargarCsv(`proyeccion-citas-${sufijo}.csv`, csvProyeccion(hoja, rotulo)) ? `Se descargó la proyección de ${hoja.filas.length} analistas.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
-  }
+  const descargar = (archivo: string, csv: string, hecho: string) => setAviso(descargarCsv(archivo, csv) ? hecho : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
+  // «Citas del periodo»: las mismas que suma la columna Citas del total (rango, supervisor y embudos), con su detalle.
+  const citasDelPeriodo = () => [...t.citas].sort(porFechaDeCita)
+  const nCitas = t.citas.length
 
   const nombresAnalista = new Map(hoja.cohorte.map(c => [c.cita.analista, c.cita.analistaNombre]))
   const nombresPersona = new Map(hoja.cohorte.map(c => [c.persona, c.cita.nombre]))
@@ -222,7 +184,10 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
     </div>
     {conAcciones && <div className="pc-acciones">
       {hoja.requiereTc && tc === null && <Button variant="outline" size="sm" onClick={recargar}>Reintentar TC</Button>}
-      <Button variant="outline" size="sm" onClick={exportar} disabled={!hoja.filas.length}><Download aria-hidden />Exportar CSV</Button>
+      <DropdownMenu menuClassName="pc-exportar-menu" trigger={<Button variant="outline" size="sm" disabled={!hoja.filas.length}><Download aria-hidden />Exportar<ChevronDown aria-hidden /></Button>}>
+        <DropdownItem onSelect={() => descargar(`proyeccion-por-analista-${sufijo}.csv`, csvProyeccion(hoja, rotulo), `Se descargó la proyección de ${hoja.filas.length} analistas.`)}>Hoja por analista</DropdownItem>
+        <DropdownItem onSelect={() => descargar(`proyeccion-citas-del-periodo-${sufijo}.csv`, csvCitasProyeccion(citasDelPeriodo()), nCitas === 1 ? 'Se descargó la cita del periodo.' : `Se descargaron las ${numero(nCitas)} citas del periodo.`)}>Citas del periodo</DropdownItem>
+      </DropdownMenu>
     </div>}
   </BarraRango>
   if (delRango?.error) return <div className="pc-panel">{barra(false)}<div role="alert" className="space-y-3 py-8"><p>{delRango.error}</p><Button variant="outline" onClick={delRango.onReintentar}>Reintentar</Button></div></div>
@@ -241,38 +206,38 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
     </th>
   }
 
+  const abrirDe = (filaId: string | null): AbrirLista => (tipo, tramo) => setDetalle({ tipo, filaId, tramo })
   return <div className="pc-panel">
     {barra(true)}
+    {esMovil && <ControlesTarjetas orden={orden} onOrdenar={alternarOrden} conFiltro={new Set(chips.map(ch => ch.id))} filtrosRef={filtrosRef}
+      onFiltrar={columna => { const ancla = filtrosRef.current; if (ancla) setMenu({ columna, ancla }) }} />}
     {chips.length > 0 && <div className="pc-chips" role="group" aria-label="Filtros de columna">
-      {chips.map(ch => <span key={ch.id} className="pc-chip"><b>{ch.titulo}</b> {ch.texto}<button type="button" aria-label={`Quitar filtro de ${ch.titulo}`} onClick={() => { cambiarColumna(ch.id, null); embudos.current[ch.id]?.focus() }}><X aria-hidden /></button></span>)}
-      <Button variant="ghost" size="sm" onClick={() => { const primero = chips[0]!.id; setColumnas({}); embudos.current[primero]?.focus() }}>Limpiar</Button>
+      {chips.map(ch => <span key={ch.id} className="pc-chip"><b>{ch.titulo}</b> {ch.texto}<button type="button" aria-label={`Quitar filtro de ${ch.titulo}`} onClick={() => { cambiarColumna(ch.id, null); enfocarEmbudo(ch.id) }}><X aria-hidden /></button></span>)}
+      <Button variant="ghost" size="sm" onClick={() => { const primero = chips[0]!.id; setColumnas({}); enfocarEmbudo(primero) }}>Limpiar</Button>
     </div>}
-    {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Hoja ancha consultable con flechas del teclado. */}
-    <div ref={hojaRef} className="pc-scroll" role="region" tabIndex={0} aria-label="Hoja de proyección por analista">
+    {esMovil ? <TarjetasProyeccion hoja={hoja} rotulo={rotulo} objetivos={objetivos} vista={vistaTiempo} abrirDe={abrirDe} listaRef={hojaRef} />
+    // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Hoja ancha consultable con flechas del teclado.
+    : <div ref={hojaRef} className="pc-scroll" role="region" tabIndex={0} aria-label="Hoja de proyección por analista">
       <table className="pc-hoja" data-tiempo={vistaTiempo}>
         <caption className="sr-only">Proyección de citas por analista · {rotulo}</caption>
         <thead><tr>
           <th scope="col" className="pc-n0"><span aria-hidden>#</span><span className="sr-only">Número</span></th>
           {cabecera(COLUMNAS[0]!)}
-          {hoja.tramos.map(tr => <th key={tr.id} scope="col" className={claseTramo(tr)}>
-            {/* Cada palabra del detalle va entera: si no cabe, solo baja el mes («22–30» / «set»). */}
-            <span className="pc-tiempo-cab" aria-hidden>{tr.titulo}<small>{tr.detalle.split(' ').flatMap((parte, i) =>
-              i ? [' ', <span key={i}>{parte}</span>] : [<span key={i}>{parte}</span>])}</small></span><span className="sr-only">{tr.nombre}</span>
-          </th>)}
+          {hoja.tramos.map(tr => <th key={tr.id} scope="col" className={claseTramo(tr)}><CabeceraTramo tramo={tr} /></th>)}
           {COLUMNAS.slice(1).map(cabecera)}
         </tr></thead>
         <tbody>{hoja.filas.map((f, i) => <tr key={f.id} className="pc-fila">
           <td className="pc-n0">{i + 1}</td>
           <th scope="row" className="pc-analista"><span className="pc-nombre"><span className="pc-avatar" aria-hidden>{iniciales(f.nombre)}</span>{f.nombre}</span></th>
-          <Celdas m={f} nombre={f.nombre} objetivos={objetivos} tramos={hoja.tramos} abrir={(tipo, tramo) => setDetalle({ tipo, filaId: f.id, tramo })} />
+          <Celdas m={f} nombre={f.nombre} objetivos={objetivos} tramos={hoja.tramos} abrir={abrirDe(f.id)} />
         </tr>)}</tbody>
         <tfoot><tr>
           <td className="pc-n0"><span aria-hidden>Σ</span></td>
           <th scope="row" className="pc-analista">Total · {numero(hoja.filas.length)} {hoja.filas.length === 1 ? 'analista' : 'analistas'}</th>
-          <Celdas m={t} nombre="todos los analistas" objetivos={objetivos} tramos={hoja.tramos} abrir={(tipo, tramo) => setDetalle({ tipo, filaId: null, tramo })} />
+          <Celdas m={t} nombre="todos los analistas" objetivos={objetivos} tramos={hoja.tramos} abrir={abrirDe(null)} />
         </tr></tfoot>
       </table>
-    </div>
+    </div>}
     <p role="status" className={aviso ? 'citas-nota py-2' : 'sr-only'}>{aviso}</p>
     {menu && columnaMenu && <EmbudoColumna key={menu.columna} titulo={columnaMenu.titulo} tipo={columnaMenu.tipo} ancla={menu.ancla}
       orden={orden.columna === menu.columna ? orden.direccion : null}
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-tarjetas.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-tarjetas.tsx
new file mode 100644
index 00000000..7589f2aa
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-tarjetas.tsx
@@ -0,0 +1,86 @@
+// Proyección en el celular (< 768 px): la hoja no cabe en un teléfono, así que
+// cada analista es una tarjeta con las mismas cifras, en el mismo orden y con los
+// mismos embudos. El Total va PRIMERO: en escritorio la fila Σ queda fija a la
+// vista; en el celular, arriba es donde se ve sin recorrer todas las tarjetas.
+// Las columnas de tiempo van en una fila que se desplaza dentro de la tarjeta:
+// así cada tarjeta mide lo mismo con 3 semanas que con 31 días.
+import type { Ref } from 'react'
+import { ArrowDownWideNarrow, ArrowUpNarrowWide, Filter } from 'lucide-react'
+import { Button } from '@/components/ui/button'
+import { DropdownItem, DropdownMenu } from '@/components/ui/dropdown-menu'
+import { Select } from '@/components/ui/select'
+import { numero } from '@/lib/format'
+import type { ColumnaProyeccion, HojaProyeccion, MetricasProyeccion, OrdenProyeccion } from './proyeccion'
+import { CIFRAS, COLUMNAS, claseTramo, type AbrirLista } from './proyeccion-columnas'
+import { CabeceraTramo, CifraColumna, CifraTramo, type ObjetivosProyeccion } from './proyeccion-cifras'
+import type { TiempoProyeccion, TramoProyeccion } from './proyeccion-rango'
+
+function Tarjeta({ m, marca, nombre, para, supervisor, objetivos, tramos, vista, abrir }: {
+  m: MetricasProyeccion; marca: string; nombre: string
+  /** Cómo se nombra la fila en cada cifra: el analista o «todos los analistas». */
+  para: string; supervisor?: string | undefined
+  objetivos: ObjetivosProyeccion; tramos: readonly TramoProyeccion[]; vista: TiempoProyeccion; abrir: AbrirLista
+}) {
+  return <div role="listitem" className="pc-tarjeta" data-total={marca === 'Σ' || undefined}>
+    <div className="pc-tarjeta-cab">
+      <span className="pc-tarjeta-n" aria-hidden>{marca}</span>
+      <p className="pc-tarjeta-nombre">{nombre}</p>
+      {supervisor && <p className="pc-tarjeta-sup">{supervisor}</p>}
+    </div>
+    {tramos.length > 0 && (
+      // Sin citas no hay botones que lleven el foco: la fila se alcanza con Tab para desplazarla.
+      // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex
+      <div className="pc-tarjeta-tramos" role="group" aria-label={`Citas por ${vista === 'dias' ? 'día' : 'semana'} de ${para}`} tabIndex={m.citas.length ? undefined : 0}>
+        {tramos.map((t, i) => <div key={t.id} className={claseTramo(t)}><CabeceraTramo tramo={t} /><CifraTramo m={m} i={i} tramo={t} nombre={para} abrir={abrir} /></div>)}
+      </div>
+    )}
+    <dl className="pc-tarjeta-cifras">
+      {CIFRAS.map(col => <div key={col.id} data-col={col.id}><dt>{col.corto}</dt>
+        <dd><CifraColumna columna={col.id} m={m} nombre={para} objetivos={objetivos} abrir={abrir} /></dd></div>)}
+    </dl>
+  </div>
+}
+
+export function TarjetasProyeccion({ hoja, rotulo, objetivos, vista, abrirDe, listaRef }: {
+  hoja: HojaProyeccion; rotulo: string; objetivos: ObjetivosProyeccion; vista: TiempoProyeccion
+  /** Las listas de una fila (`null`: el Total). */
+  abrirDe: (filaId: string | null) => AbrirLista
+  listaRef: Ref<HTMLDivElement>
+}) {
+  const n = hoja.filas.length
+  return <div ref={listaRef} role="list" tabIndex={-1} className="pc-tarjetas" aria-label={`Proyección de citas por analista · ${rotulo}`}>
+    <Tarjeta m={hoja.total} marca="Σ" nombre={`Total · ${numero(n)} ${n === 1 ? 'analista' : 'analistas'}`} para="todos los analistas"
+      objetivos={objetivos} tramos={hoja.tramos} vista={vista} abrir={abrirDe(null)} />
+    {hoja.filas.map((f, i) => <Tarjeta key={f.id} m={f} marca={String(i + 1)} nombre={f.nombre} para={f.nombre} supervisor={f.supervisor}
+      objetivos={objetivos} tramos={hoja.tramos} vista={vista} abrir={abrirDe(f.id)} />)}
+  </div>
+}
+
+/** En tarjetas no hay cabeceras: el orden y los embudos de columna se ofrecen aquí, sobre el mismo estado de la hoja. */
+export function ControlesTarjetas({ orden, onOrdenar, conFiltro, onFiltrar, filtrosRef }: {
+  orden: OrdenProyeccion
+  /** Como pulsar la cabecera: otra columna toma su sentido inicial; la misma lo invierte. */
+  onOrdenar: (columna: ColumnaProyeccion) => void
+  conFiltro: ReadonlySet<ColumnaProyeccion>
+  onFiltrar: (columna: ColumnaProyeccion) => void
+  filtrosRef: Ref<HTMLButtonElement>
+}) {
+  const texto = orden.columna === 'analista'
+  const asc = orden.direccion === 'asc'
+  const sentido = asc ? texto ? 'de A a Z' : 'de menor a mayor' : texto ? 'de Z a A' : 'de mayor a menor'
+  const Icono = asc ? ArrowUpNarrowWide : ArrowDownWideNarrow
+  return <div className="pc-controles" role="group" aria-label="Orden y filtros">
+    <div className="pc-ordenar">
+      <label className="pc-fecha">Ordenar por<Select aria-label="Ordenar por" className="h-8" value={orden.columna} onChange={e => onOrdenar(e.target.value as ColumnaProyeccion)}>
+        {COLUMNAS.map(c => <option key={c.id} value={c.id}>{c.corto}</option>)}
+      </Select></label>
+      <Button variant="outline" size="icon" className="pc-sentido" aria-label={`Orden ${sentido}`} title={`Orden ${sentido}`} onClick={() => onOrdenar(orden.columna)}><Icono aria-hidden /></Button>
+    </div>
+    <DropdownMenu className="pc-filtros" menuClassName="pc-filtros-menu" trigger={
+      <Button ref={filtrosRef} variant="outline" size="sm" aria-label={conFiltro.size ? `Filtros, ${conFiltro.size} con filtro` : 'Filtros'}>
+        <Filter aria-hidden />Filtros{conFiltro.size > 0 && <span className="pc-filtros-n" aria-hidden>{conFiltro.size}</span>}
+      </Button>}>
+      {COLUMNAS.map(c => <DropdownItem key={c.id} onSelect={() => onFiltrar(c.id)}>{c.corto}{conFiltro.has(c.id) && <><span className="sr-only">, con filtro</span><span className="pc-con-filtro" aria-hidden>con filtro</span></>}</DropdownItem>)}
+    </DropdownMenu>
+  </div>
+}
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
index b34e5da6..9f71d9a2 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
@@ -1,4 +1,5 @@
-/* Proyección de citas: hoja tipo Excel a todo el ancho (propuesta B aprobada el 19/10/2026). */
+/* Proyección de citas: hoja tipo Excel a todo el ancho (propuesta B aprobada el 19/10/2026).
+   Tarjetas del celular: nombre ≥16 px y detalle ≥14 px (regla de Miguel «cómodo para la vista»). */
 .pc-panel { font-variant-numeric: tabular-nums; --pc-cruz: color-mix(in srgb, var(--accent) 6%, white); }
 .pc-chips { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; margin-bottom: 10px; }
 .pc-chip { display: inline-flex; align-items: center; gap: 6px; min-height: 28px; padding: 0 3px 0 10px; border: 1px solid color-mix(in srgb, var(--accent) 22%, white); border-radius: 999px; background: color-mix(in srgb, var(--accent) 9%, white); color: var(--accent-press); font-size: 12px; font-weight: 500; }
@@ -136,15 +137,60 @@ button.pc-persona:hover { color: var(--accent-press); text-decoration: underline
 .pc-origen[data-origen='referido'] { background: color-mix(in srgb, var(--accent) 10%, white); color: var(--accent-press); }
 .pc-origen[data-origen='lead'] { color: var(--primary); }
 
+/* ── Celular (< 768 px): una tarjeta por analista, el Total primero ── */
+.pc-controles { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 8px; margin-bottom: 10px; }
+/* Como Desde y Hasta: la etiqueta encima, para que Orden, sentido y Filtros quepan en una fila a 320 px. */
+.pc-ordenar { display: flex; flex: 1 1 150px; align-items: flex-end; gap: 6px; min-width: 0; }
+.pc-ordenar .pc-fecha { flex: 1; flex-direction: column; align-items: stretch; gap: 2px; min-width: 0; }
+.pc-sentido { flex-shrink: 0; width: 36px; height: 32px; }
+.pc-filtros { margin-left: auto; }
+.pc-filtros-n { display: inline-grid; place-items: center; min-width: 18px; height: 18px; padding: 0 5px; border-radius: 999px; background: var(--accent); color: #fff; font-size: 11px; font-weight: 700; }
+.pc-filtros-menu, .pc-exportar-menu { min-width: 190px; }
+.pc-con-filtro { margin-left: auto; color: var(--accent-press); font-size: 12px; font-weight: 600; }
+.pc-tarjetas { display: grid; gap: 10px; border-radius: 12px; }
+.pc-tarjeta { min-width: 0; padding: 12px 14px; border: 1px solid var(--border); border-radius: 12px; background: var(--card); }
+.pc-tarjeta[data-total] { border-color: var(--border-strong); background: var(--muted); }
+.pc-tarjeta-cab { display: grid; grid-template-columns: auto minmax(0, 1fr); column-gap: 10px; align-items: center; }
+.pc-tarjeta-n { grid-row: span 2; display: grid; place-items: center; min-width: 28px; height: 28px; padding: 0 6px; border-radius: 8px; background: var(--muted); color: var(--muted-foreground-strong); font-size: 12px; font-weight: 600; font-variant-numeric: tabular-nums; }
+.pc-tarjeta[data-total] .pc-tarjeta-n { background: var(--card); color: var(--primary); font-size: 14px; }
+.pc-tarjeta-nombre { color: var(--primary); font-size: 16px; font-weight: 600; line-height: 1.3; overflow-wrap: anywhere; }
+.pc-tarjeta[data-total] .pc-tarjeta-nombre { font-weight: 700; }
+.pc-tarjeta-sup { color: var(--muted-foreground-strong); font-size: 14px; line-height: 1.3; }
+.pc-tarjeta-cifras { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px 10px; margin-top: 10px; padding-top: 10px; border-top: 1px solid var(--border); }
+.pc-tarjeta-cifras dt { color: var(--muted-foreground-strong); font-size: 14px; font-weight: 500; line-height: 1.2; }
+.pc-tarjeta-cifras dd { display: flex; align-items: center; min-height: 32px; color: var(--foreground); font-size: 16px; font-weight: 600; }
+.pc-tarjeta[data-total] .pc-tarjeta-cifras dd { color: var(--primary); }
+.pc-tarjeta-cifras .pc-n { justify-content: flex-start; min-width: 0; margin: 0 -6px; padding: 0 6px; font-weight: 600; }
+.pc-tarjeta-cifras .cm-senal { min-width: 0; }
+/* Proyectado: el mismo fondo suave que su columna en la hoja. */
+.pc-tarjeta-cifras [data-col='proyectado'] dd .pc-n:not(.pc-cero) { background: color-mix(in srgb, var(--background) 65%, white); }
+/* Semanas o Días: una fila que se desplaza dentro de la tarjeta, nunca la página. */
+.pc-tarjeta-tramos { display: flex; gap: 4px; margin: 10px -14px 0; padding: 0 14px 2px; overflow-x: auto; overscroll-behavior-x: contain; scroll-padding-inline: 14px; scrollbar-width: thin; }
+.pc-tarjeta-tramos .pc-tiempo { display: flex; flex: 0 0 auto; flex-direction: column; align-items: center; min-width: 50px; padding: 4px 4px 2px; border: 1px solid var(--border); border-radius: 8px; background: var(--card); }
+.pc-tarjeta-tramos .pc-tiempo-cab { display: flex; flex-direction: column; align-items: center; color: var(--primary); font-size: 14px; font-weight: 600; line-height: 1.15; white-space: nowrap; }
+.pc-tarjeta-tramos .pc-tiempo-cab small { color: var(--muted-foreground-strong); font-size: 13px; font-weight: 500; }
+.pc-tarjeta-tramos .pc-n { justify-content: center; min-width: 40px; margin: 0; padding: 0 6px; font-size: 16px; font-weight: 600; }
+.pc-tarjeta-tramos .pc-cero { font-weight: 400; }
+.pc-tarjeta-tramos .pc-domingo { background: color-mix(in srgb, var(--primary) 5%, white); }
+.pc-tarjeta-tramos .pc-hoy { border-color: color-mix(in srgb, var(--accent) 45%, white); background: color-mix(in srgb, var(--accent) 8%, white); }
+.pc-tarjeta-tramos .pc-hoy .pc-tiempo-cab { color: var(--accent-press); }
+.pc-tarjeta-tramos .pc-futuro .pc-n { color: var(--muted-foreground); }
+@media (max-width: 359px) { .pc-tarjeta-cifras { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
+
 :is(.pc-panel, .pc-menu, .pc-detalle) :is(button, [tabindex], input):focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
 /* Dentro de la hoja el anillo va hacia dentro: el contenedor con desplazamiento lo recortaría. */
-.pc-panel :is(.pc-scroll, .pc-hoja button):focus-visible { outline-offset: -2px; }
+.pc-panel :is(.pc-scroll, .pc-hoja button, .pc-tarjeta-tramos, .pc-tarjeta-tramos button):focus-visible { outline-offset: -2px; }
 @media (max-width: 1440px) { .pc-avatar { display: none; } .pc-hoja :is(th, td) { padding-inline: 8px; } .pc-nombre { min-width: 150px; max-width: 210px; } .pc-scroll { scroll-padding-left: 270px; } }
 @media (max-width: 767px) {
   .pc-nombre { min-width: 132px; }
   .pc-hoja tbody th.pc-analista { white-space: normal; }
   .pc-scroll { max-height: none; }
   .pc-tiempos { padding-left: 0; border-left: 0; }
+  /* Barra en el celular: Supervisor y rótulo a lo ancho; Desde y Hasta lado a lado, con su etiqueta encima. */
+  .pc-supervisor, .pc-rotulo { flex: 1 1 100%; }
+  .pc-supervisor > div { flex: 1; width: auto; min-width: 0; }
+  .pc-periodo > .pc-fecha:not(.pc-supervisor) { flex: 1 1 0; flex-direction: column; align-items: stretch; gap: 2px; min-width: 0; }
+  .pc-periodo > .pc-fecha:not(.pc-supervisor) input { width: 100%; min-width: 0; }
 }
 /* Táctil: toda zona pulsable mide al menos 44 px. */
 @media (pointer: coarse) {
@@ -152,6 +198,11 @@ button.pc-persona:hover { color: var(--accent-press); text-decoration: underline
   .pc-chip button { position: relative; }
   .pc-chip button::after { content: ''; position: absolute; inset: -11px; }
   .pc-hoja .pc-n, .pc-hoja button.cm-senal { height: 44px; min-height: 44px; }
+  /* También el 0 y el «—»: así los ceros quedan a la altura de los botones de su fila. */
+  .pc-tarjeta :is(.pc-n, button.cm-senal) { min-height: 44px; }
+  .pc-tarjeta-cifras dd { min-height: 44px; }
+  .pc-acciones button, .pc-controles button, .pc-panel [role='menuitem'] { min-height: 44px; }
+  .pc-sentido { width: 44px; }
   .pc-op, .pc-atajo { min-height: 44px; }
   .pc-fecha :is(input, select) { height: 44px; }
   .pc-menu input:not([type='checkbox']) { height: 44px; }
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
index 52b20975..ba978d4d 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
@@ -292,8 +292,10 @@ describe('Proyección de citas: periodo y CSV', () => {
     // Ana: 124/19 × 2/3 × 50 % × 9 375 = 20 394,74.
     expect(lineas[1]).toBe('"Octubre 2026","Claudia Ríos","Ana Torres","4","37500","9375","66.7","50","20394.74","1","0","3"')
     expect(lineas.at(-1)).toBe('"Octubre 2026","","Total · 3 analistas","7","122500","17500","75","33.3","20394.74","2","1","4"')
-    const lista = csvCitasProyeccion(fila(hoja, 'ana')!.conMonto.filter(c => c.cita.id === 'a2'))
-    expect(lista.split('\r\n')[1]).toBe('"a2","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
+    const lista = csvCitasProyeccion(fila(hoja, 'ana')!.conMonto.filter(c => c.cita.id === 'a2')).split('\r\n')
+    // Autosuficiente: el día de creación (Lima) decide su periodo y su columna de tiempo.
+    expect(lista[0]).toBe('\uFEFF"Código de cita","Creada","Fecha","Hora","Persona","Analista","Supervisor","Estado","Moneda","Monto","Monto S/","Origen"')
+    expect(lista[1]).toBe('"a2","2026-10-03","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
   })
 
   it('las columnas de origen suman las citas en cada fila', () => {
@@ -546,8 +548,8 @@ describe('Proyección de citas: reuniones con clientes sin lead', () => {
     // S1 1–7: a1 a2 a3 · S2 8–14: r1 r2 · S3 · S4.
     expect(ana.porTramo.map(ids)).toEqual([['a1', 'a2', 'a3'], ['r1', 'r2'], [], []])
     const csv = csvCitasProyeccion(ana.clientes).split('\r\n')
-    expect(csv[1]).toBe('"r1","2026-10-12","11:00","CLIENTE R1","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
-    expect(csv[2]).toBe('"r2","2026-10-12","11:00","Cliente fuera de tu cartera","Ana Torres","Claudia Ríos","No asistió","","","","Cliente"')
+    expect(csv[1]).toBe('"r1","2026-10-08","2026-10-12","11:00","CLIENTE R1","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
+    expect(csv[2]).toBe('"r2","2026-10-11","2026-10-12","11:00","Cliente fuera de tu cartera","Ana Torres","Claudia Ríos","No asistió","","","","Cliente"')
     const hojaCsv = csvProyeccion(calcularProyeccion(ejemplo()), 'Octubre').split('\r\n')
     // Citas 5 · Monto 60 000 · Ticket 20 000 · % Entrev. 60 · % Conv. 50 · Proyectado · Referidos 0 · Clientes 2 · Leads 3.
     expect(hojaCsv[1]).toBe('"Octubre","Claudia Ríos","Ana Torres","5","60000","20000","60","50","32631.58","0","2","3"')
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
index 3eae0e3b..757e88a0 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
@@ -432,10 +432,11 @@ export function csvProyeccion(hoja: HojaProyeccion, rotulo: string): string {
   ])
 }
 
+/** Cada cita con lo que la ubica en la hoja: el día (de Lima) en que se creó decide su periodo y su columna de tiempo. */
 export function csvCitasProyeccion(lista: readonly CitaProyectada[]): string {
   return archivoCsv([
-    ['Código de cita', 'Fecha', 'Hora', 'Persona', 'Analista', 'Supervisor', 'Estado', 'Moneda', 'Monto', 'Monto S/', 'Origen'],
-    ...lista.map(({ cita, enSoles, origen }) => [cita.id, cita.fecha, cita.hora, cita.nombre, cita.analistaNombre, cita.supervisor,
+    ['Código de cita', 'Creada', 'Fecha', 'Hora', 'Persona', 'Analista', 'Supervisor', 'Estado', 'Moneda', 'Monto', 'Monto S/', 'Origen'],
+    ...lista.map(({ cita, creada, enSoles, origen }) => [cita.id, creada, cita.fecha, cita.hora, cita.nombre, cita.analistaNombre, cita.supervisor,
       ESTADOS[cita.estado].label, cita.moneda, cita.monto ?? '', redondeo(enSoles), ROTULO_ORIGEN[origen]]),
   ])
 }
```

## Diff e2e
```diff
diff --git a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
index 680cc788..2f0c6c74 100644
--- a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
@@ -1,3 +1,4 @@
+import { readFile } from 'node:fs/promises'
 import { expect, test, type Page } from '@playwright/test'
 import { loginReal, montarBackendReal } from './_helpers'
 
@@ -93,6 +94,7 @@ async function abrirProyeccion(page: Page) {
 }
 const atajo = (page: Page, nombre: string) => page.getByRole('group', { name: 'Atajos de periodo' }).getByRole('button', { name: nombre, exact: true })
 const tiempo = (page: Page, nombre: 'Mes' | 'Semanas' | 'Días') => page.getByRole('group', { name: 'Columnas de tiempo' }).getByRole('button', { name: nombre, exact: true })
+const desbordePagina = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
 
 test('Proyección: la hoja pinta una fila por analista, un número abre su lista y un embudo filtra', async ({ page }, info) => {
   await page.setViewportSize({ width: 1440, height: 1000 })
@@ -115,6 +117,31 @@ test('Proyección: la hoja pinta una fila por analista, un número abre su lista
   expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
   await page.screenshot({ path: info.outputPath('proyeccion-1440.png'), fullPage: true })
 
+  // Exportar: un menú con la hoja por analista y las citas del periodo; Esc lo cierra y devuelve el foco.
+  const exportar = page.getByRole('button', { name: 'Exportar', exact: true })
+  await exportar.click()
+  const menuExportar = page.getByRole('menu')
+  await expect(menuExportar.getByRole('menuitem')).toHaveText(['Hoja por analista', 'Citas del periodo'])
+  await expect(menuExportar.getByRole('menuitem', { name: 'Hoja por analista' })).toBeFocused()
+  await page.screenshot({ path: info.outputPath('proyeccion-exportar-1440.png') })
+  await page.keyboard.press('Escape')
+  await expect(menuExportar).toHaveCount(0)
+  await expect(exportar).toBeFocused()
+  // «Citas del periodo» trae exactamente las 10 que suma Citas del total: 5 con lead, 2 de ANALISTA TRES y sus 3 reuniones con clientes sin lead.
+  await expect(hoja.getByRole('button', { name: '10 citas de todos los analistas' })).toBeVisible()
+  await exportar.click()
+  const descarga = page.waitForEvent('download')
+  await page.getByRole('menuitem', { name: 'Citas del periodo' }).click()
+  const archivo = await descarga
+  expect(archivo.suggestedFilename()).toBe('proyeccion-citas-del-periodo-2026-10-01_2026-10-19.csv')
+  const filas = (await readFile((await archivo.path())!, 'utf8')).replace(/^\uFEFF/, '').split('\r\n')
+  expect(filas[0]).toBe('"Código de cita","Creada","Fecha","Hora","Persona","Analista","Supervisor","Estado","Moneda","Monto","Monto S/","Origen"')
+  expect(filas).toHaveLength(11)
+  const reuniones = filas.filter(f => f.endsWith('"Cliente"'))
+  expect(reuniones.map(f => f.slice(1, 37)).sort()).toEqual([id(201), id(202), id(203)])
+  expect(reuniones.every(f => f.includes('"ANALISTA TRES","SUPERVISOR SUR"'))).toBe(true)
+  await expect(page.getByText('Se descargaron las 10 citas del periodo.')).toBeVisible()
+
   await hoja.getByRole('button', { name: '4 citas de ANALISTA UNO' }).click()
   const lista = page.getByRole('dialog', { name: 'Citas · ANALISTA UNO' })
   await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 4 citas')
@@ -224,7 +251,7 @@ test('Proyección: Semanas y Días ponen columnas de tiempo antes de Citas y cad
   await expect(hoja.locator('thead th.pc-tiempo .sr-only').first()).toHaveText('S1 1–7 set')
 })
 
-test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el celular solo desplaza la hoja', async ({ page }, info) => {
+test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el celular pinta tarjetas sin desplazar la página', async ({ page }, info) => {
   await page.setViewportSize({ width: 1440, height: 1000 })
   const hoja = await abrirProyeccion(page)
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
@@ -234,27 +261,64 @@ test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el c
   await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–31 ago 2026')
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(0)
   await expect(hoja.getByRole('row', { name: /^Total · 0 analistas/ })).toBeVisible()
-  await expect(page.getByRole('button', { name: 'Exportar CSV' })).toBeDisabled()
+  await expect(page.getByRole('button', { name: 'Exportar', exact: true })).toBeDisabled()
   await expect(page.getByRole('alert')).toHaveCount(0)
   await expect(page.getByText('No hay citas con esta combinación')).toHaveCount(0)
   await atajo(page, 'Mes').click()
   await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('1–19 oct 2026')
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
+  // En el celular la hoja se vuelve tarjetas: el Total primero y una por analista, en el orden de la hoja.
   await page.setViewportSize({ width: 390, height: 844 })
-  await expect(hoja.locator('tr.pc-fila')).toHaveCount(3)
-  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
-  const scroll = page.getByRole('region', { name: 'Hoja de proyección por analista' })
-  expect(await scroll.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true)
+  await expect(hoja).toHaveCount(0)
+  const tarjetas = page.getByRole('list', { name: /^Proyección de citas por analista/ }).getByRole('listitem')
+  await expect(tarjetas).toHaveCount(4)
+  await expect(tarjetas.first()).toContainText('Total · 3 analistas')
+  expect(await desbordePagina(page)).toBeLessThanOrEqual(0)
   await page.screenshot({ path: info.outputPath('proyeccion-390.png'), fullPage: true })
-  // Con cuatro pestañas, a 375 y 320 px ninguna queda fuera de la pantalla.
+  // Una cifra de la tarjeta abre la misma lista que en la hoja.
+  const uno = tarjetas.filter({ hasText: 'ANALISTA UNO' })
+  await uno.getByRole('button', { name: '4 citas de ANALISTA UNO' }).click()
+  const lista = page.getByRole('dialog', { name: 'Citas · ANALISTA UNO' })
+  await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 4 citas')
+  await expect(lista.locator('tbody tr')).toHaveCount(4)
+  await page.keyboard.press('Escape')
+  await expect(lista).toHaveCount(0)
+  // Días: la fila de tramos se desplaza dentro de la tarjeta, nunca la página.
+  await tiempo(page, 'Días').click()
+  const dias = uno.getByRole('group', { name: 'Citas por día de ANALISTA UNO' })
+  await expect(dias.locator('.pc-tiempo')).toHaveCount(19)
+  expect(await dias.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true)
+  expect(await desbordePagina(page)).toBeLessThanOrEqual(0)
+  await tiempo(page, 'Mes').click()
+  // A 375 y 320 px: ninguna pestaña ni control de la barra, del orden o de los filtros queda fuera de la pantalla.
   for (const ancho of [375, 320]) {
     await page.setViewportSize({ width: ancho, height: 800 })
     const pestanas = page.getByRole('tablist', { name: 'Cómo ver las citas' })
     expect(await pestanas.evaluate(el => el.scrollWidth - el.clientWidth), `${ancho} px`).toBeLessThanOrEqual(0)
     await expect(page.getByRole('tab', { name: 'Proyección' })).toBeInViewport()
-    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
+    await expect(tarjetas).toHaveCount(4)
+    const fuera = await page.locator('.pc-periodo, .pc-controles').locator('button, select, input').evaluateAll(controles => controles
+      .filter(c => { const r = c.getBoundingClientRect(); return r.left < -0.5 || r.right > window.innerWidth + 0.5 })
+      .map(c => c.getAttribute('aria-label') ?? c.textContent))
+    expect(fuera, `${ancho} px`).toEqual([])
+    expect(await desbordePagina(page), `${ancho} px`).toBeLessThanOrEqual(0)
   }
   await page.screenshot({ path: info.outputPath('proyeccion-320.png') })
+  // «Filtros» abre los mismos embudos de la hoja, dentro de la pantalla; al cerrarlo el foco vuelve a «Filtros».
+  const filtros = page.getByRole('button', { name: /^Filtros/ })
+  await filtros.click()
+  await page.getByRole('menuitem', { name: 'Analista' }).click()
+  const embudo = page.getByRole('dialog', { name: 'Filtrar Analista' })
+  await expect(embudo.getByRole('searchbox', { name: 'Buscar analista' })).toBeFocused()
+  const caja = (await embudo.boundingBox())!
+  expect(caja.x).toBeGreaterThanOrEqual(0)
+  expect(caja.x + caja.width).toBeLessThanOrEqual(320)
+  await embudo.getByRole('checkbox', { name: 'ANALISTA DOS · 1 cita' }).uncheck()
+  await embudo.getByRole('button', { name: 'Aplicar' }).click()
+  await expect(tarjetas).toHaveCount(3)
+  await expect(filtros).toBeFocused()
+  await expect(filtros).toHaveAccessibleName('Filtros, 1 con filtro')
+  expect(await desbordePagina(page)).toBeLessThanOrEqual(0)
 })
 
 test('Proyección: las reuniones con clientes sin lead cuentan en Citas, Clientes y % Entrev., no en Monto, Ticket ni Proyectado', async ({ page }, info) => {
```
