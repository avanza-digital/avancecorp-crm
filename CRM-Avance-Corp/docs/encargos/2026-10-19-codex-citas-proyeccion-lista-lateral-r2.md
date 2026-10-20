ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo r2 (LEVEL 2, segunda y última pasada, por alcance nuevo): REFUTA la lista lateral de la Proyección en escritorio y tablet

Contexto. CRM Avance Corp (React 19 + TS). Pestaña «Proyección» de Citas: todo número abre una lista lateral (`Sheet`, `fixed … w-[460px] max-w-[92vw]` por defecto, aquí `w-[980px]`). En la r1 revisaste las tarjetas del celular; aceptamos tus dos hallazgos (44 px de ancho en el botón de la persona bajo `pointer: coarse`; la prueba de orden ya compara la secuencia exacta sin `.sort()`) y añadimos al E2E la comprobación a 320 px.

Alcance nuevo de esta pasada (pedido del dueño: «hazlo bien, no quiero deudas técnicas»):
1. Escritorio: la tabla medía 892 px en un panel de 760 (Monto y Origen cortados). Ahora el panel mide 980 px y Persona y Analista pueden partir línea (`min-width` 160/110 px) en vez de ensanchar la tabla. Medido en navegador a 1440 px: tabla 979 = panel 979.
2. Donde la tabla no cabe (ventana < 1 080 px: 92 vw < 980 px), la lista usa las tarjetas del celular aunque la hoja siga siendo tabla (≥ 768 px). Constante `LISTA_EN_TARJETAS = '(max-width: 1079px)'` con `useMediaQuery`.
3. Fila y tarjeta comparten las piezas de cada dato (`creada`, `momento`, `EstadoCita`, `OrigenCita`, `MontoCita`, `PersonaCita`); la tabla pasa a `TablaCitas`.
4. Ayuda: «En el celular la hoja y sus listas se muestran en tarjetas.»
5. Pruebas: el stub de `matchMedia` del bloque de celular resuelve cada `max-width` contra un ancho simulado (390 por defecto; 900 y 1280 en la prueba de tablet). E2E: a 1440 la tabla del total (con Analista, 10 citas) no desborda; a 1024 la misma lista pasa a tarjetas sin desbordar.

Busca con evidencia (archivo:línea, caso concreto): (a) anchos de contenido reales que aún desborden 980 px en escritorio (estado más largo, montos en dólares grandes con su conversión, origen «Referido», nombres largos) o que el umbral 1 080 sea incoherente con 92 vw/980; (b) un dato distinto entre fila y tarjeta; (c) que el stub nuevo de `matchMedia` cambie en silencio el comportamiento de otras pruebas del bloque (otras `max-width` del CRM ahora coinciden a 390); (d) regresiones de accesibilidad en la tabla (cabeceras, `th scope=row`, caption) o en la Ayuda; (e) cualquier deuda técnica que quede.

Verificación reportada (NOT RUN por ti): vitest de Citas 185/185, tsc y oxlint en verde; check completo (7 461 en la pasada anterior) y E2E Docker completo en curso.

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Archivo completo: app/src/components/citas/proyeccion-detalle.tsx
```tsx
// Lista lateral detrás de una cifra de la Proyección: las citas exactas que la
// componen, con su monto original y en soles, y su CSV. Donde la tabla no cabe
// entera (celular y tablet) cada cita es una tarjeta: nada se desliza de lado.
import { useState } from 'react'
import { Download, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { fmtFecha, money, numero } from '@/lib/format'
import { useMediaQuery } from '@/lib/media'
import { useDatosCitas } from './contexto'
import { fechaLocalCitas } from './fecha-comercial'
import { ESTADOS } from './modelo'
import { ROTULO_ORIGEN, csvCitasProyeccion, type CitaProyectada } from './proyeccion'
import { descargarCsv } from './proyeccion-descarga'

/** La tabla necesita unos 900 px; el panel mide 980 y como mucho el 92 % de la ventana: por debajo de 1 080 px no cabe. */
const LISTA_EN_TARJETAS = '(max-width: 1079px)'

export interface ListaProyeccion { titulo: string; periodo: string; lista: CitaProyectada[]; conAnalista: boolean; archivo: string }
type AbrirFicha = ((leadId: string, tareaId: string) => void) | undefined

// Cada dato se pinta con la misma pieza en la fila y en la tarjeta: las dos vistas no pueden diferir.
const creada = (c: CitaProyectada) => c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'
const momento = (c: CitaProyectada) => `${fmtFecha(c.cita.fecha)} · ${c.cita.hora}`
const EstadoCita = ({ c }: { c: CitaProyectada }) => <span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span>
const OrigenCita = ({ c }: { c: CitaProyectada }) => <span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span>

function MontoCita({ c }: { c: CitaProyectada }) {
  if (c.cita.monto == null) return <span className="pc-cero">—</span>
  if (c.cita.moneda === 'PEN') return <>{money(c.cita.monto, 'PEN')}</>
  return <><span className="pc-m">{money(c.cita.monto, 'USD')} ·</span>{c.enSoles === null ? 'Pendiente de TC' : `S/ ${numero(c.enSoles)}`}</>
}

/** La persona abre su ficha de lead; una reunión con un cliente sin lead no tiene ficha que abrir. */
function PersonaCita({ c, onAbrir }: { c: CitaProyectada; onAbrir: AbrirFicha }) {
  const leadId = c.cita.leadId
  if (!onAbrir || leadId === null) return <span className="pc-persona">{c.cita.nombre}</span>
  return <button type="button" className="pc-persona" onClick={() => onAbrir(leadId, c.cita.id)}>{c.cita.nombre}</button>
}

/** Escritorio: una fila por cita. */
function TablaCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: AbrirFicha }) {
  return <table className="pc-lista">
    <caption className="sr-only">{detalle.titulo}</caption>
    <thead><tr><th scope="col">Creada</th><th scope="col">Cita</th><th scope="col">Persona</th>{detalle.conAnalista && <th scope="col">Analista</th>}<th scope="col">Estado</th><th scope="col" className="pc-num">Monto</th><th scope="col">Origen</th></tr></thead>
    <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
      <td>{creada(c)}</td>
      <td>{momento(c)}</td>
      <th scope="row"><PersonaCita c={c} onAbrir={onAbrir} /></th>
      {detalle.conAnalista && <td className="pc-lista-analista">{c.cita.analistaNombre}</td>}
      <td><EstadoCita c={c} /></td>
      <td className="pc-num"><MontoCita c={c} /></td>
      <td><OrigenCita c={c} /></td>
    </tr>)}</tbody>
  </table>
}

/** Celular y tablet: una tarjeta por cita, con los mismos datos y en el mismo orden que la tabla. */
function TarjetasCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: AbrirFicha }) {
  return <ul className="pc-citas" aria-label={detalle.titulo}>{detalle.lista.map(c => <li key={c.cita.id} className="pc-cita">
    <div className="pc-cita-cab"><PersonaCita c={c} onAbrir={onAbrir} /><OrigenCita c={c} /></div>
    <dl className="pc-cita-datos">
      <div><dt>Creada</dt><dd>{creada(c)}</dd></div>
      <div><dt>Cita</dt><dd>{momento(c)}</dd></div>
      {detalle.conAnalista && <div><dt>Analista</dt><dd>{c.cita.analistaNombre}</dd></div>}
      <div><dt>Estado</dt><dd><EstadoCita c={c} /></dd></div>
      <div><dt>Monto</dt><dd><MontoCita c={c} /></dd></div>
    </dl>
  </li>)}</ul>
}

export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle: ListaProyeccion | null; onCerrar: () => void; focoRespaldo: () => HTMLElement | null }) {
  const { onAbrirLead } = useDatosCitas()
  const enTarjetas = useMediaQuery(LISTA_EN_TARJETAS)
  const [aviso, setAviso] = useState('')
  const n = detalle?.lista.length ?? 0
  const cerrar = () => { setAviso(''); onCerrar() }
  const abrirFicha = onAbrirLead && ((leadId: string, tareaId: string) => { cerrar(); requestAnimationFrame(() => requestAnimationFrame(() => onAbrirLead(leadId, tareaId))) })
  function exportar() {
    if (!detalle) return
    setAviso(descargarCsv(detalle.archivo, csvCitasProyeccion(detalle.lista)) ? `Se descargó el CSV con ${n} ${n === 1 ? 'cita' : 'citas'}.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
  }
  return <Sheet open={Boolean(detalle)} onClose={cerrar} focoRespaldo={focoRespaldo} className="citas-crm-dialogo pc-detalle w-[980px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div>
      <SheetTitle>{detalle?.titulo ?? 'Citas'}</SheetTitle>
      <p className="mt-1 text-sm text-muted-foreground-strong" data-testid="pc-detalle-conteo">{detalle?.periodo} · {numero(n)} {n === 1 ? 'cita' : 'citas'}</p>
    </div><Button variant="ghost" size="icon" aria-label="Cerrar lista" onClick={cerrar}><X aria-hidden /></Button></div></SheetHeader>
    {detalle && <>
      <SheetBody className="p-0">
        {enTarjetas ? <TarjetasCitas detalle={detalle} onAbrir={abrirFicha} /> : <TablaCitas detalle={detalle} onAbrir={abrirFicha} />}
      </SheetBody>
      <SheetFooter className="justify-end"><p role="status" className={aviso ? 'mr-auto text-xs text-muted-foreground-strong' : 'sr-only'}>{aviso}</p><Button variant="outline" onClick={exportar} disabled={!n}><Download aria-hidden />Exportar CSV</Button></SheetFooter>
    </>}
  </Sheet>
}
```

## CSS existente relevante (proyeccion.css)
```css
100:.pc-m { margin-right: 4px; color: var(--muted-foreground-strong); font-size: 12px; font-weight: 400; }
127:.pc-lista { width: 100%; border-collapse: collapse; font-size: 14px; font-variant-numeric: tabular-nums; }
128:.pc-lista thead th { position: sticky; top: 0; z-index: 1; padding: 8px 10px; border-bottom: 1px solid var(--border-strong); background: var(--muted); color: var(--muted-foreground-strong); text-align: left; font-size: 13px; font-weight: 600; }
129:.pc-lista :is(td, tbody th) { height: 42px; padding: 0 10px; border-bottom: 1px solid var(--border); text-align: left; white-space: nowrap; font-weight: 400; }
130:.pc-lista .pc-num { text-align: right; }
132:.pc-lista tbody th { min-width: 160px; white-space: normal; }
133:.pc-lista .pc-lista-analista { min-width: 110px; white-space: normal; }
134:.pc-persona { color: var(--primary); font-size: 16px; font-weight: 600; }
135:button.pc-persona { cursor: pointer; text-align: left; }
136:button.pc-persona:hover { color: var(--accent-press); text-decoration: underline; }
137:.pc-estado, .pc-origen { display: inline-flex; align-items: center; height: 22px; padding: 0 8px; border-radius: 5px; background: var(--secondary); color: var(--muted-foreground-strong); font-size: 12px; font-weight: 600; }
```

## Estados posibles (ESTADOS[..].label) y orígenes (ROTULO_ORIGEN)
```ts
37:  vencida: { label: 'Vencida sin resultado', short: 'Sin resultado', icon: 'circle-alert', next: 'Registrar resultado' },
38:  programada: { label: 'Programada', short: 'Programadas', icon: 'clock3', next: 'Preparar cita' },
39:  realizada: { label: 'Realizada', short: 'Realizadas', icon: 'circle-check', next: 'Continuar seguimiento' },
40:  no_show: { label: 'No asistió', short: 'No asistieron', icon: 'circle-x', next: 'Recuperar contacto' },
41:  reprogramada: { label: 'Reprogramada', short: 'Reprogramadas', icon: 'calendar-clock', next: 'Revisar nueva fecha' },
42:  cancelada: { label: 'Cancelada por asesor', short: 'Canceladas por asesor', icon: 'circle-x', next: 'Revisar motivo' },
43:  sistema: { label: 'Cancelada por sistema', short: 'Canceladas por sistema', icon: 'circle-x', next: 'Revisar contexto' },
421:export const ROTULO_ORIGEN: Record<OrigenCita, string> = { referido: 'Referido', cliente: 'Cliente', lead: 'Lead' }
422-
423-/** En Semanas o Días, una columna por tramo después de «Analista». */
--
```

## Otros usos de useMediaQuery / matchMedia en el árbol que monta TableroCitas
```
/Users/usuario/dev/avancecorp-crm-lista-lateral/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx:74:  const enTarjetas = useMediaQuery(LISTA_EN_TARJETAS)
/Users/usuario/dev/avancecorp-crm-lista-lateral/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx:93:  const esMovil = useEsMovil()
```

## Diff completo frente a main
```diff
diff --git a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
index 2f0c6c74..8f688079 100644
--- a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
@@ -148,6 +148,19 @@ test('Proyección: la hoja pinta una fila por analista, un número abre su lista
   await expect(lista.locator('tbody tr')).toHaveCount(4)
   await page.keyboard.press('Escape')
   await expect(lista).toHaveCount(0)
+  // En escritorio la tabla del total (con la columna Analista) cabe entera en el panel: nada que deslizar de lado.
+  await hoja.getByRole('button', { name: '10 citas de todos los analistas' }).click()
+  const listaTotal = page.getByRole('dialog', { name: 'Citas · Total' })
+  await expect(listaTotal.locator('tbody tr')).toHaveCount(10)
+  expect(await listaTotal.locator('table').evaluate(t => t.parentElement!.scrollWidth - t.parentElement!.clientWidth)).toBeLessThanOrEqual(0)
+  // En una tablet (la hoja sigue siendo tabla) la tabla ya no cabe: la lista pasa a tarjetas.
+  await page.setViewportSize({ width: 1024, height: 900 })
+  await expect(listaTotal.locator('table')).toHaveCount(0)
+  await expect(listaTotal.getByRole('listitem')).toHaveCount(10)
+  expect(await listaTotal.locator('.pc-citas').evaluate(el => el.parentElement!.scrollWidth - el.parentElement!.clientWidth)).toBeLessThanOrEqual(0)
+  await page.setViewportSize({ width: 1440, height: 1000 })
+  await page.keyboard.press('Escape')
+  await expect(listaTotal).toHaveCount(0)
 
   const conversion = hoja.getByRole('button', { name: /^% Conv\. de ANALISTA UNO: 50%/ })
   await conversion.click()
@@ -280,7 +293,23 @@ test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el c
   await uno.getByRole('button', { name: '4 citas de ANALISTA UNO' }).click()
   const lista = page.getByRole('dialog', { name: 'Citas · ANALISTA UNO' })
   await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 4 citas')
-  await expect(lista.locator('tbody tr')).toHaveCount(4)
+  // La lista lateral también es de tarjetas: todo a la vista sin deslizar de lado, nombre a 16 px y detalle a 14 px.
+  await expect(lista.locator('table')).toHaveCount(0)
+  const citas = lista.getByRole('list', { name: 'Citas · ANALISTA UNO' }).getByRole('listitem')
+  await expect(citas).toHaveCount(4)
+  const cuerpo = lista.locator('.pc-citas')
+  expect(await cuerpo.evaluate(el => el.parentElement!.scrollWidth - el.parentElement!.clientWidth)).toBeLessThanOrEqual(0)
+  for (const derecha of await citas.evaluateAll(lis => lis.map(li => li.getBoundingClientRect().right))) expect(derecha).toBeLessThanOrEqual(390)
+  const tamanos = await citas.evaluateAll(lis => lis.flatMap(li => [...li.querySelectorAll('.pc-persona, dt, dd, .pc-estado, .pc-origen, .pc-m')]
+    .map(e => ({ que: e.classList[0] ?? e.tagName, px: parseFloat(getComputedStyle(e).fontSize) }))))
+  expect(tamanos.filter(t => t.que === 'pc-persona').map(t => t.px)).toEqual([16, 16, 16, 16])
+  expect(tamanos.filter(t => t.px < 14)).toEqual([])
+  await page.screenshot({ path: info.outputPath('proyeccion-lista-390.png') })
+  // A 320 px tampoco se desliza de lado.
+  await page.setViewportSize({ width: 320, height: 800 })
+  expect(await cuerpo.evaluate(el => el.parentElement!.scrollWidth - el.parentElement!.clientWidth)).toBeLessThanOrEqual(0)
+  for (const derecha of await citas.evaluateAll(lis => lis.map(li => li.getBoundingClientRect().right))) expect(derecha).toBeLessThanOrEqual(320)
+  await page.setViewportSize({ width: 390, height: 844 })
   await page.keyboard.press('Escape')
   await expect(lista).toHaveCount(0)
   // Días: la fila de tramos se desplaza dentro de la tarjeta, nunca la página.
diff --git a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
index ce8d3fc6..40f910c0 100644
--- a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
@@ -52,7 +52,7 @@ function Guia({ abierta, onCerrar }: { abierta: boolean; onCerrar: () => void })
       <section><h3 className="font-semibold">2. Empieza por lo que necesita atención</h3><p className="mt-1 text-muted-foreground-strong">En «Bandeja comercial», pulsa «Sin resultado» para encontrar citas vencidas cuyo resultado no se registró. «Programadas» muestra las que todavía están por realizar en el período.</p></section>
       <section><h3 className="font-semibold">3. Combina los filtros</h3><p className="mt-1 text-muted-foreground-strong">Abre «Más filtros» para elegir varios estados, modalidad, origen, resultado y seguimiento. Para filtrar un importe, selecciona primero soles o dólares.</p></section>
       <section><h3 className="font-semibold">4. Cambia de vista según la tarea</h3><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Bandeja comercial:</strong> revisa responsable, estado y siguiente paso. «Pendientes primero» deja las vencidas arriba.</li><li><strong>Agenda:</strong> revisa citas por día y hora. Siempre usa orden cronológico.</li><li><strong>Resultados:</strong> empieza por el recorrido de quienes no asistieron. Pulsa una etapa para ver sus personas y abre un nombre para consultar el historial, las fechas y el depósito. Debajo, compara citas por lead y cumplimiento de cada analista: el 100% indica que alcanzó la meta interna configurada. La flecha junto al analista abre sus leads. «Columnas» muestra información adicional de actividad y supervisor.</li><li><strong>Proyección:</strong> hoja por analista con su propio periodo (Desde–Hasta). Se explica en el paso 5.</li></ul><p className="mt-2 text-muted-foreground-strong">Bandeja, Agenda y Resultados conservan tus filtros y consultan el mismo conjunto de citas. Los filtros seleccionan las citas de origen; el seguimiento puede encontrar depósitos posteriores fuera del mes o semana, hasta el corte indicado. Cada etapa cuenta leads únicos y parte de la anterior. El porcentaje final usa como base quienes faltaron al inicio; un depósito anterior a la asistencia no entra en este flujo.</p></section>
-      <section><h3 className="font-semibold">5. Lee la Proyección</h3><p className="mt-1 text-muted-foreground-strong">Tiene su propio periodo: elige Desde y Hasta o un atajo, y el supervisor en su barra; los filtros de arriba no se aplican aquí. Cuenta cada cita el día en que se creó, no el de su fecha prevista, e incluye las reuniones con clientes que no tienen lead. «Semanas» y «Días» reparten esas citas en columnas; «Días» admite hasta 31 días.</p><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Monto S/:</strong> suma del monto estimado de las citas con lead; los dólares se pasan a soles con el tipo de cambio del periodo.</li><li><strong>Ticket cita S/:</strong> Monto ÷ citas con lead. No es el «Ticket del mes» de Resultados, que divide el capital cerrado entre los clientes.</li><li><strong>% Entrev.:</strong> entrevistas ÷ citas con resultado (realizadas y no asistió). Una reunión con cliente a la que asistió cuenta como entrevista.</li><li><strong>% Conv.:</strong> personas entrevistadas con lead que después cerraron una venta del mismo analista, con la misma regla que Resultados.</li><li><strong>Proyectado citas S/:</strong> las citas que se esperan al cierre del periodo, al ritmo actual, × % de entrevistas × % de conversión × ticket cita. Se calcula solo con las citas con lead. No es el «Cierre proyectado» de Resultados.</li><li><strong>Referidos, Clientes y Leads:</strong> de dónde viene cada cita; suman el total de citas. «Clientes» son personas que ya eran clientes. Las reuniones con clientes que no tienen lead no suman al monto, al ticket, a la conversión ni al proyectado.</li></ul><p className="mt-2 text-muted-foreground-strong">Cada número abre su lista de citas. El embudo de cada columna ordena y filtra. En el celular la hoja se muestra en tarjetas.</p></section>
+      <section><h3 className="font-semibold">5. Lee la Proyección</h3><p className="mt-1 text-muted-foreground-strong">Tiene su propio periodo: elige Desde y Hasta o un atajo, y el supervisor en su barra; los filtros de arriba no se aplican aquí. Cuenta cada cita el día en que se creó, no el de su fecha prevista, e incluye las reuniones con clientes que no tienen lead. «Semanas» y «Días» reparten esas citas en columnas; «Días» admite hasta 31 días.</p><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Monto S/:</strong> suma del monto estimado de las citas con lead; los dólares se pasan a soles con el tipo de cambio del periodo.</li><li><strong>Ticket cita S/:</strong> Monto ÷ citas con lead. No es el «Ticket del mes» de Resultados, que divide el capital cerrado entre los clientes.</li><li><strong>% Entrev.:</strong> entrevistas ÷ citas con resultado (realizadas y no asistió). Una reunión con cliente a la que asistió cuenta como entrevista.</li><li><strong>% Conv.:</strong> personas entrevistadas con lead que después cerraron una venta del mismo analista, con la misma regla que Resultados.</li><li><strong>Proyectado citas S/:</strong> las citas que se esperan al cierre del periodo, al ritmo actual, × % de entrevistas × % de conversión × ticket cita. Se calcula solo con las citas con lead. No es el «Cierre proyectado» de Resultados.</li><li><strong>Referidos, Clientes y Leads:</strong> de dónde viene cada cita; suman el total de citas. «Clientes» son personas que ya eran clientes. Las reuniones con clientes que no tienen lead no suman al monto, al ticket, a la conversión ni al proyectado.</li></ul><p className="mt-2 text-muted-foreground-strong">Cada número abre su lista de citas. El embudo de cada columna ordena y filtra. En el celular la hoja y sus listas se muestran en tarjetas.</p></section>
       <section><h3 className="font-semibold">6. Abre la ficha</h3><p className="mt-1 text-muted-foreground-strong">Pulsa el nombre del prospecto o «Detalle». La ficha lateral muestra fecha, responsable, monto estimado, resultado, notas y siguiente paso. «Ubicar en agenda» abre esa cita. «Citas de…» abre todas las citas de ese analista en el mes de la ficha. Estas dos acciones restablecen los demás filtros para que el destino sea visible.</p></section>
       <section><h3 className="font-semibold">7. Limpia o exporta la consulta</h3><p className="mt-1 text-muted-foreground-strong">La × de cada etiqueta quita ese filtro. «Restablecer consulta» vuelve al mes completo. «Exportar citas» descarga todas las coincidencias, incluidas las de otras páginas. El CSV contiene el detalle de las citas; el promedio por lead y el seguimiento se consultan en Resultados. En Proyección, «Exportar» descarga la hoja por analista o las citas del periodo.</p></section>
       <p className="rounded-lg bg-muted p-3 text-xs text-muted-foreground-strong">Responsable: el analista registrado en la cita; no acredita quién la creó. Las fechas de asistencia corresponden al registro de su resultado. Seguimiento al {corteLima(corte)}.</p>
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
index 252fa7d4..1af0db1b 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
@@ -1,17 +1,29 @@
 // Lista lateral detrás de una cifra de la Proyección: las citas exactas que la
-// componen, con su monto original y en soles, y su CSV.
+// componen, con su monto original y en soles, y su CSV. Donde la tabla no cabe
+// entera (celular y tablet) cada cita es una tarjeta: nada se desliza de lado.
 import { useState } from 'react'
 import { Download, X } from 'lucide-react'
 import { Button } from '@/components/ui/button'
 import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
 import { fmtFecha, money, numero } from '@/lib/format'
+import { useMediaQuery } from '@/lib/media'
 import { useDatosCitas } from './contexto'
 import { fechaLocalCitas } from './fecha-comercial'
 import { ESTADOS } from './modelo'
 import { ROTULO_ORIGEN, csvCitasProyeccion, type CitaProyectada } from './proyeccion'
 import { descargarCsv } from './proyeccion-descarga'
 
+/** La tabla necesita unos 900 px; el panel mide 980 y como mucho el 92 % de la ventana: por debajo de 1 080 px no cabe. */
+const LISTA_EN_TARJETAS = '(max-width: 1079px)'
+
 export interface ListaProyeccion { titulo: string; periodo: string; lista: CitaProyectada[]; conAnalista: boolean; archivo: string }
+type AbrirFicha = ((leadId: string, tareaId: string) => void) | undefined
+
+// Cada dato se pinta con la misma pieza en la fila y en la tarjeta: las dos vistas no pueden diferir.
+const creada = (c: CitaProyectada) => c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'
+const momento = (c: CitaProyectada) => `${fmtFecha(c.cita.fecha)} · ${c.cita.hora}`
+const EstadoCita = ({ c }: { c: CitaProyectada }) => <span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span>
+const OrigenCita = ({ c }: { c: CitaProyectada }) => <span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span>
 
 function MontoCita({ c }: { c: CitaProyectada }) {
   if (c.cita.monto == null) return <span className="pc-cero">—</span>
@@ -20,14 +32,46 @@ function MontoCita({ c }: { c: CitaProyectada }) {
 }
 
 /** La persona abre su ficha de lead; una reunión con un cliente sin lead no tiene ficha que abrir. */
-function PersonaCita({ c, onAbrir }: { c: CitaProyectada; onAbrir: ((leadId: string, tareaId: string) => void) | undefined }) {
+function PersonaCita({ c, onAbrir }: { c: CitaProyectada; onAbrir: AbrirFicha }) {
   const leadId = c.cita.leadId
   if (!onAbrir || leadId === null) return <span className="pc-persona">{c.cita.nombre}</span>
   return <button type="button" className="pc-persona" onClick={() => onAbrir(leadId, c.cita.id)}>{c.cita.nombre}</button>
 }
 
+/** Escritorio: una fila por cita. */
+function TablaCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: AbrirFicha }) {
+  return <table className="pc-lista">
+    <caption className="sr-only">{detalle.titulo}</caption>
+    <thead><tr><th scope="col">Creada</th><th scope="col">Cita</th><th scope="col">Persona</th>{detalle.conAnalista && <th scope="col">Analista</th>}<th scope="col">Estado</th><th scope="col" className="pc-num">Monto</th><th scope="col">Origen</th></tr></thead>
+    <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
+      <td>{creada(c)}</td>
+      <td>{momento(c)}</td>
+      <th scope="row"><PersonaCita c={c} onAbrir={onAbrir} /></th>
+      {detalle.conAnalista && <td className="pc-lista-analista">{c.cita.analistaNombre}</td>}
+      <td><EstadoCita c={c} /></td>
+      <td className="pc-num"><MontoCita c={c} /></td>
+      <td><OrigenCita c={c} /></td>
+    </tr>)}</tbody>
+  </table>
+}
+
+/** Celular y tablet: una tarjeta por cita, con los mismos datos y en el mismo orden que la tabla. */
+function TarjetasCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: AbrirFicha }) {
+  return <ul className="pc-citas" aria-label={detalle.titulo}>{detalle.lista.map(c => <li key={c.cita.id} className="pc-cita">
+    <div className="pc-cita-cab"><PersonaCita c={c} onAbrir={onAbrir} /><OrigenCita c={c} /></div>
+    <dl className="pc-cita-datos">
+      <div><dt>Creada</dt><dd>{creada(c)}</dd></div>
+      <div><dt>Cita</dt><dd>{momento(c)}</dd></div>
+      {detalle.conAnalista && <div><dt>Analista</dt><dd>{c.cita.analistaNombre}</dd></div>}
+      <div><dt>Estado</dt><dd><EstadoCita c={c} /></dd></div>
+      <div><dt>Monto</dt><dd><MontoCita c={c} /></dd></div>
+    </dl>
+  </li>)}</ul>
+}
+
 export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle: ListaProyeccion | null; onCerrar: () => void; focoRespaldo: () => HTMLElement | null }) {
   const { onAbrirLead } = useDatosCitas()
+  const enTarjetas = useMediaQuery(LISTA_EN_TARJETAS)
   const [aviso, setAviso] = useState('')
   const n = detalle?.lista.length ?? 0
   const cerrar = () => { setAviso(''); onCerrar() }
@@ -36,26 +80,14 @@ export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle
     if (!detalle) return
     setAviso(descargarCsv(detalle.archivo, csvCitasProyeccion(detalle.lista)) ? `Se descargó el CSV con ${n} ${n === 1 ? 'cita' : 'citas'}.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
   }
-  return <Sheet open={Boolean(detalle)} onClose={cerrar} focoRespaldo={focoRespaldo} className="citas-crm-dialogo pc-detalle w-[760px]">
+  return <Sheet open={Boolean(detalle)} onClose={cerrar} focoRespaldo={focoRespaldo} className="citas-crm-dialogo pc-detalle w-[980px]">
     <SheetHeader><div className="flex items-start justify-between gap-3"><div>
       <SheetTitle>{detalle?.titulo ?? 'Citas'}</SheetTitle>
       <p className="mt-1 text-sm text-muted-foreground-strong" data-testid="pc-detalle-conteo">{detalle?.periodo} · {numero(n)} {n === 1 ? 'cita' : 'citas'}</p>
     </div><Button variant="ghost" size="icon" aria-label="Cerrar lista" onClick={cerrar}><X aria-hidden /></Button></div></SheetHeader>
     {detalle && <>
       <SheetBody className="p-0">
-        <table className="pc-lista">
-          <caption className="sr-only">{detalle.titulo}</caption>
-          <thead><tr><th scope="col">Creada</th><th scope="col">Cita</th><th scope="col">Persona</th>{detalle.conAnalista && <th scope="col">Analista</th>}<th scope="col">Estado</th><th scope="col" className="pc-num">Monto</th><th scope="col">Origen</th></tr></thead>
-          <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
-            <td>{c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'}</td>
-            <td>{fmtFecha(c.cita.fecha)} · {c.cita.hora}</td>
-            <th scope="row"><PersonaCita c={c} onAbrir={abrirFicha} /></th>
-            {detalle.conAnalista && <td>{c.cita.analistaNombre}</td>}
-            <td><span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span></td>
-            <td className="pc-num"><MontoCita c={c} /></td>
-            <td><span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span></td>
-          </tr>)}</tbody>
-        </table>
+        {enTarjetas ? <TarjetasCitas detalle={detalle} onAbrir={abrirFicha} /> : <TablaCitas detalle={detalle} onAbrir={abrirFicha} />}
       </SheetBody>
       <SheetFooter className="justify-end"><p role="status" className={aviso ? 'mr-auto text-xs text-muted-foreground-strong' : 'sr-only'}>{aviso}</p><Button variant="outline" onClick={exportar} disabled={!n}><Download aria-hidden />Exportar CSV</Button></SheetFooter>
     </>}
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
index 17707871..68bf122d 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
@@ -663,11 +663,15 @@ describe('Proyección con reuniones con clientes sin lead', () => {
 
 // Fase 3: en el celular (< 768 px) la hoja se vuelve tarjetas, con el mismo estado (orden, embudos y listas).
 describe('Proyección en el celular: tarjetas', () => {
+  /** Ancho simulado de la ventana: cada `max-width` se resuelve contra él. */
+  let ancho = 390
   beforeEach(() => {
-    vi.stubGlobal('matchMedia', (consulta: string) => ({
-      matches: consulta.includes('max-width: 767px') || consulta.includes('prefers-reduced-motion'), media: consulta,
-      addEventListener: () => {}, removeEventListener: () => {},
-    }))
+    ancho = 390
+    vi.stubGlobal('matchMedia', (consulta: string) => {
+      const maximo = /max-width: (\d+)px/.exec(consulta)
+      return { matches: maximo ? ancho <= Number(maximo[1]) : consulta.includes('prefers-reduced-motion'), media: consulta,
+        addEventListener: () => {}, removeEventListener: () => {} }
+    })
   })
   afterEach(() => { vi.unstubAllGlobals() })
 
@@ -681,6 +685,9 @@ describe('Proyección en el celular: tarjetas', () => {
   const nombresTarjetas = (lista: HTMLElement) => tarjetas(lista).map(t => t.querySelector('.pc-tarjeta-nombre')!.textContent)
   const tarjeta = (lista: HTMLElement, nombre: string) => tarjetas(lista).find(t => t.querySelector('.pc-tarjeta-nombre')!.textContent === nombre)!
   const filtros = () => screen.getByRole('button', { name: /^Filtros/ })
+  /** La lista lateral en el celular: una tarjeta por cita. */
+  const citasDe = (detalle: HTMLElement) => within(within(detalle).getByRole('list')).getAllByRole('listitem')
+  const citaDe = (detalle: HTMLElement, persona: string) => citasDe(detalle).find(li => li.querySelector('.pc-persona')!.textContent === persona)!
 
   it('una tarjeta por analista en el orden de la hoja, con el Total primero; cada cifra es botón (salvo ceros y «—») y abre la misma lista', async () => {
     const { usuario, lista } = await abrirTarjetas()
@@ -703,15 +710,60 @@ describe('Proyección en el celular: tarjetas', () => {
     await usuario.click(within(ana).getByRole('button', { name: '4 citas de Ana Torres' }))
     let detalle = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
     expect(within(detalle).getByTestId('pc-detalle-conteo')).toHaveTextContent('1–19 oct 2026 · 4 citas')
-    expect(within(detalle).getAllByRole('row')).toHaveLength(5)
+    // La lista lateral también es de tarjetas: una por cita, sin tabla que deslizar de lado.
+    expect(within(detalle).queryByRole('table')).not.toBeInTheDocument()
+    expect(citasDe(detalle)).toHaveLength(4)
     await usuario.click(within(detalle).getByRole('button', { name: 'Cerrar lista' }))
     const total = tarjeta(lista, 'Total · 3 analistas')
     await usuario.click(within(total).getByRole('button', { name: '1 cita con cliente de todos los analistas' }))
     detalle = screen.getByRole('dialog', { name: 'Citas con clientes · Total' })
-    expect(within(detalle).getByRole('row', { name: /Persona d1/ })).toHaveTextContent('Diego Salas')
+    expect(citaDe(detalle, 'Persona d1')).toHaveTextContent('Diego Salas')
     await usuario.keyboard('{Escape}')
     await usuario.click(within(ana).getByRole('button', { name: /^% Conv\. de Ana Torres: 50%/ }))
-    expect(within(screen.getByRole('dialog', { name: 'Entrevistas que cerraron cliente · Ana Torres' })).getAllByRole('row')).toHaveLength(2)
+    expect(citasDe(screen.getByRole('dialog', { name: 'Entrevistas que cerraron cliente · Ana Torres' }))).toHaveLength(1)
+  })
+
+  it('la lista lateral pinta una tarjeta por cita con los mismos datos de la tabla y la persona abre su ficha', async () => {
+    const onAbrirLead = vi.fn()
+    const usuario = userEvent.setup()
+    render(<ContextoCitas value={{ ...fuente, onAbrirLead }}><TableroCitas /></ContextoCitas>)
+    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
+    const lista = screen.getByRole('list', { name: 'Proyección de citas por analista · 1–19 oct 2026' })
+    await usuario.click(within(tarjeta(lista, 'Total · 3 analistas')).getByRole('button', { name: '7 citas de todos los analistas' }))
+    const detalle = screen.getByRole('dialog', { name: 'Citas · Total' })
+    expect(within(detalle).getByRole('list', { name: 'Citas · Total' })).toBeVisible()
+    // El mismo orden que la tabla: por fecha y hora de la cita (aquí todas a la misma hora, así que por código), no el de llegada.
+    expect(citasDe(detalle).map(li => li.querySelector('.pc-persona')!.textContent)).toEqual(
+      ['Persona a1', 'Persona a2', 'Persona a3', 'Persona a4', 'Persona d1', 'Persona d2', 'Persona l1'])
+    // Los mismos datos que la fila de la tabla, en el mismo orden; con varios analistas, también el analista.
+    const a2 = citaDe(detalle, 'Persona a2')
+    expect(within(a2).getAllByRole('term').map(dt => dt.textContent)).toEqual(['Creada', 'Cita', 'Analista', 'Estado', 'Monto'])
+    expect(within(a2).getAllByRole('definition').map(dd => dd.textContent)).toEqual(['03 oct. 2026', '10 oct. 2026 · 10:00', 'Ana Torres', 'Realizada', 'US$ 2,000 ·S/ 7,500'])
+    expect(a2.querySelector('.pc-origen')).toHaveTextContent('Lead')
+    expect(citaDe(detalle, 'Persona a3').querySelector('.pc-origen')).toHaveTextContent('Referido')
+    expect(within(citaDe(detalle, 'Persona a4')).getAllByRole('definition').at(-1)).toHaveTextContent('—')
+    await usuario.click(within(a2).getByRole('button', { name: 'Persona a2' }))
+    await vi.waitFor(() => expect(onAbrirLead).toHaveBeenCalledWith('lead-a2', 'a2'))
+    expect(screen.queryByRole('dialog', { name: 'Citas · Total' })).not.toBeInTheDocument()
+    // La lista de un solo analista no repite su nombre en cada tarjeta.
+    await usuario.click(within(tarjeta(lista, 'Ana Torres')).getByRole('button', { name: '4 citas de Ana Torres' }))
+    expect(within(citaDe(screen.getByRole('dialog', { name: 'Citas · Ana Torres' }), 'Persona a1')).getAllByRole('term').map(dt => dt.textContent)).toEqual(['Creada', 'Cita', 'Estado', 'Monto'])
+  })
+
+  it('en una tablet la hoja sigue siendo tabla, pero su lista lateral usa tarjetas porque la tabla no cabe en el panel', async () => {
+    ancho = 900
+    const { usuario, hoja } = await abrirProyeccion()
+    await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '4 citas de Ana Torres' }))
+    const detalle = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
+    expect(within(detalle).queryByRole('table')).not.toBeInTheDocument()
+    expect(citasDe(detalle)).toHaveLength(4)
+    await usuario.keyboard('{Escape}')
+    // Con la ventana ancha, la lista vuelve a ser tabla.
+    cleanup()
+    ancho = 1280
+    const ancha = await abrirProyeccion()
+    await usuario.click(within(fila(ancha.hoja, 'Ana Torres')).getByRole('button', { name: '4 citas de Ana Torres' }))
+    expect(within(screen.getByRole('dialog', { name: 'Citas · Ana Torres' })).getAllByRole('row')).toHaveLength(5)
   })
 
   it('«Ordenar por» y «Filtros» usan el mismo orden y los mismos embudos de la hoja', async () => {
@@ -779,7 +831,7 @@ describe('Proyección en el celular: tarjetas', () => {
     expect(within(tarjeta(lista, 'Total · 3 analistas')).getByRole('group', { name: 'Citas por semana de todos los analistas' })).toBeVisible()
     await usuario.click(within(semanas).getByRole('button', { name: '1 cita de Ana Torres, S2 8–14 oct' }))
     const detalle = screen.getByRole('dialog', { name: 'Citas · S2 8–14 oct · Ana Torres' })
-    expect(within(detalle).getByRole('row', { name: /Persona a4/ })).toBeVisible()
+    expect(citaDe(detalle, 'Persona a4')).toBeVisible()
     await usuario.keyboard('{Escape}')
     await usuario.click(tiempo('Días'))
     const dias = within(tarjeta(lista, 'Luis Vega')).getByRole('group', { name: 'Citas por día de Luis Vega' })
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
index cd7491a6..907a8079 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
@@ -128,6 +128,9 @@ button.pc-n:hover { background: color-mix(in srgb, var(--accent) 12%, white); co
 .pc-lista thead th { position: sticky; top: 0; z-index: 1; padding: 8px 10px; border-bottom: 1px solid var(--border-strong); background: var(--muted); color: var(--muted-foreground-strong); text-align: left; font-size: 13px; font-weight: 600; }
 .pc-lista :is(td, tbody th) { height: 42px; padding: 0 10px; border-bottom: 1px solid var(--border); text-align: left; white-space: nowrap; font-weight: 400; }
 .pc-lista .pc-num { text-align: right; }
+/* Un nombre largo parte en dos líneas en vez de ensanchar la tabla. */
+.pc-lista tbody th { min-width: 160px; white-space: normal; }
+.pc-lista .pc-lista-analista { min-width: 110px; white-space: normal; }
 .pc-persona { color: var(--primary); font-size: 16px; font-weight: 600; }
 button.pc-persona { cursor: pointer; text-align: left; }
 button.pc-persona:hover { color: var(--accent-press); text-decoration: underline; }
@@ -136,6 +139,18 @@ button.pc-persona:hover { color: var(--accent-press); text-decoration: underline
 .pc-origen[data-origen='cliente'] { background: var(--primary); color: #fff; }
 .pc-origen[data-origen='referido'] { background: color-mix(in srgb, var(--accent) 10%, white); color: var(--accent-press); }
 .pc-origen[data-origen='lead'] { color: var(--primary); }
+/* Lista lateral en el celular y la tablet: una tarjeta por cita; nombre a 16 px y todo el detalle a 14 px, sin deslizar de lado. */
+.pc-citas { display: grid; gap: 8px; padding: 12px; }
+.pc-cita { padding: 10px 12px; border: 1px solid var(--border); border-radius: 12px; background: var(--card); font-variant-numeric: tabular-nums; }
+.pc-cita-cab { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
+.pc-cita-cab .pc-persona { min-width: 0; line-height: 1.3; overflow-wrap: anywhere; }
+.pc-cita-cab .pc-origen { flex: none; }
+.pc-cita-datos { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px 12px; margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--border); }
+.pc-cita-datos > div:last-child:nth-child(odd) { grid-column: 1 / -1; }
+.pc-cita-datos dt { color: var(--muted-foreground-strong); font-size: 14px; font-weight: 500; line-height: 1.3; }
+.pc-cita-datos dd { color: var(--foreground); font-size: 14px; line-height: 1.4; overflow-wrap: anywhere; }
+.pc-cita :is(.pc-estado, .pc-origen, .pc-m) { font-size: 14px; }
+.pc-cita :is(.pc-estado, .pc-origen) { height: 24px; }
 
 /* ── Celular (< 768 px): una tarjeta por analista, el Total primero ── */
 .pc-controles { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 8px; margin-bottom: 10px; }
@@ -201,6 +216,7 @@ button.pc-persona:hover { color: var(--accent-press); text-decoration: underline
   /* También el 0 y el «—»: así los ceros quedan a la altura de los botones de su fila. */
   .pc-tarjeta :is(.pc-n, button.cm-senal) { min-height: 44px; }
   .pc-tarjeta-cifras dd { min-height: 44px; }
+  .pc-cita button.pc-persona { min-width: 44px; min-height: 44px; }
   .pc-acciones button, .pc-controles button, .pc-panel [role='menuitem'] { min-height: 44px; }
   .pc-sentido { width: 44px; }
   .pc-op, .pc-atajo { min-height: 44px; }
```
