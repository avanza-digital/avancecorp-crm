ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 2, una pasada): REFUTA las tarjetas de la lista lateral de la Proyección en el celular (front)

Contexto. CRM Avance Corp (React 19 + TS). La pestaña «Proyección» de Citas (en producción) es una hoja por analista; todo número abre una lista lateral (`Sheet`) con las citas exactas que lo componen. En el celular (< 768 px, `useEsMovil()` = `matchMedia('(max-width: 767px)')`) la hoja ya se pinta como tarjetas (Fase 3), pero la lista lateral seguía siendo la tabla de escritorio: 7 columnas, 892 px de ancho en un panel de 358 px, nombre cortado y desplazamiento lateral. Regla del dueño: «en celular, tarjetas»; nombre ≥16 px, detalle ≥14 px; zonas táctiles ≥44 px; «no puede haber data distinta».

Cambio: en `proyeccion-detalle.tsx`, con `esMovil` la lista se pinta como `<ul aria-label={titulo}>` con una tarjeta `<li>` por cita (mismo `detalle.lista`, mismo orden): cabecera con la persona (botón que abre la ficha si tiene lead; texto si es reunión con cliente sin lead) y la pastilla de origen; debajo un `<dl>` de dos columnas con Creada, Cita, Analista (solo si `conAnalista`), Estado y Monto (mismo `MontoCita`). En escritorio, la tabla queda igual. CSS nuevo en `proyeccion.css`.

Busca con evidencia (archivo:línea, caso concreto): (a) un dato de la tarjeta distinto del de la fila de la tabla para la misma cita, o una cita que falte o sobre; (b) tamaños por debajo de 14 px en el detalle o zonas táctiles < 44 px; (c) desbordes horizontales a 320–390 px (montos en dólares largos, nombres largos sin espacios, fecha+hora); (d) accesibilidad: lista sin nombre, términos/definiciones mal asociados, foco al abrir/cerrar y al abrir la ficha; (e) regresiones en escritorio; (f) pruebas que no prueben lo que dicen (hay un mutante verificado: forzar la tabla en el celular hace fallar 3 pruebas).

Verificación reportada (NOT RUN por ti): vitest de Citas 184/184, oxlint y tsc en verde; check completo y E2E Docker de la Proyección en curso.

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Archivo completo tras el cambio: app/src/components/citas/proyeccion-detalle.tsx
```tsx
// Lista lateral detrás de una cifra de la Proyección: las citas exactas que la
// componen, con su monto original y en soles, y su CSV. En el celular cada cita
// es una tarjeta: la tabla de escritorio no cabe y obliga a deslizar de lado.
import { useState } from 'react'
import { Download, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { fmtFecha, money, numero } from '@/lib/format'
import { useEsMovil } from '@/lib/media'
import { useDatosCitas } from './contexto'
import { fechaLocalCitas } from './fecha-comercial'
import { ESTADOS } from './modelo'
import { ROTULO_ORIGEN, csvCitasProyeccion, type CitaProyectada } from './proyeccion'
import { descargarCsv } from './proyeccion-descarga'

export interface ListaProyeccion { titulo: string; periodo: string; lista: CitaProyectada[]; conAnalista: boolean; archivo: string }

function MontoCita({ c }: { c: CitaProyectada }) {
  if (c.cita.monto == null) return <span className="pc-cero">—</span>
  if (c.cita.moneda === 'PEN') return <>{money(c.cita.monto, 'PEN')}</>
  return <><span className="pc-m">{money(c.cita.monto, 'USD')} ·</span>{c.enSoles === null ? 'Pendiente de TC' : `S/ ${numero(c.enSoles)}`}</>
}

/** La persona abre su ficha de lead; una reunión con un cliente sin lead no tiene ficha que abrir. */
function PersonaCita({ c, onAbrir }: { c: CitaProyectada; onAbrir: ((leadId: string, tareaId: string) => void) | undefined }) {
  const leadId = c.cita.leadId
  if (!onAbrir || leadId === null) return <span className="pc-persona">{c.cita.nombre}</span>
  return <button type="button" className="pc-persona" onClick={() => onAbrir(leadId, c.cita.id)}>{c.cita.nombre}</button>
}

/** Celular: una tarjeta por cita, con los mismos datos y en el mismo orden que la tabla. */
function TarjetasCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: ((leadId: string, tareaId: string) => void) | undefined }) {
  return <ul className="pc-citas" aria-label={detalle.titulo}>{detalle.lista.map(c => <li key={c.cita.id} className="pc-cita">
    <div className="pc-cita-cab"><PersonaCita c={c} onAbrir={onAbrir} /><span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span></div>
    <dl className="pc-cita-datos">
      <div><dt>Creada</dt><dd>{c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'}</dd></div>
      <div><dt>Cita</dt><dd>{fmtFecha(c.cita.fecha)} · {c.cita.hora}</dd></div>
      {detalle.conAnalista && <div><dt>Analista</dt><dd>{c.cita.analistaNombre}</dd></div>}
      <div><dt>Estado</dt><dd><span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span></dd></div>
      <div><dt>Monto</dt><dd><MontoCita c={c} /></dd></div>
    </dl>
  </li>)}</ul>
}

export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle: ListaProyeccion | null; onCerrar: () => void; focoRespaldo: () => HTMLElement | null }) {
  const { onAbrirLead } = useDatosCitas()
  const esMovil = useEsMovil()
  const [aviso, setAviso] = useState('')
  const n = detalle?.lista.length ?? 0
  const cerrar = () => { setAviso(''); onCerrar() }
  const abrirFicha = onAbrirLead && ((leadId: string, tareaId: string) => { cerrar(); requestAnimationFrame(() => requestAnimationFrame(() => onAbrirLead(leadId, tareaId))) })
  function exportar() {
    if (!detalle) return
    setAviso(descargarCsv(detalle.archivo, csvCitasProyeccion(detalle.lista)) ? `Se descargó el CSV con ${n} ${n === 1 ? 'cita' : 'citas'}.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
  }
  return <Sheet open={Boolean(detalle)} onClose={cerrar} focoRespaldo={focoRespaldo} className="citas-crm-dialogo pc-detalle w-[760px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div>
      <SheetTitle>{detalle?.titulo ?? 'Citas'}</SheetTitle>
      <p className="mt-1 text-sm text-muted-foreground-strong" data-testid="pc-detalle-conteo">{detalle?.periodo} · {numero(n)} {n === 1 ? 'cita' : 'citas'}</p>
    </div><Button variant="ghost" size="icon" aria-label="Cerrar lista" onClick={cerrar}><X aria-hidden /></Button></div></SheetHeader>
    {detalle && <>
      <SheetBody className="p-0">
        {esMovil ? <TarjetasCitas detalle={detalle} onAbrir={abrirFicha} /> : <table className="pc-lista">
          <caption className="sr-only">{detalle.titulo}</caption>
          <thead><tr><th scope="col">Creada</th><th scope="col">Cita</th><th scope="col">Persona</th>{detalle.conAnalista && <th scope="col">Analista</th>}<th scope="col">Estado</th><th scope="col" className="pc-num">Monto</th><th scope="col">Origen</th></tr></thead>
          <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
            <td>{c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'}</td>
            <td>{fmtFecha(c.cita.fecha)} · {c.cita.hora}</td>
            <th scope="row"><PersonaCita c={c} onAbrir={abrirFicha} /></th>
            {detalle.conAnalista && <td>{c.cita.analistaNombre}</td>}
            <td><span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span></td>
            <td className="pc-num"><MontoCita c={c} /></td>
            <td><span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span></td>
          </tr>)}</tbody>
        </table>}
      </SheetBody>
      <SheetFooter className="justify-end"><p role="status" className={aviso ? 'mr-auto text-xs text-muted-foreground-strong' : 'sr-only'}>{aviso}</p><Button variant="outline" onClick={exportar} disabled={!n}><Download aria-hidden />Exportar CSV</Button></SheetFooter>
    </>}
  </Sheet>
}
```

## CSS relevante ya existente (proyeccion.css, sin cambios)
```css
100:.pc-m { margin-right: 4px; color: var(--muted-foreground-strong); font-size: 12px; font-weight: 400; }
131:.pc-persona { color: var(--primary); font-size: 16px; font-weight: 600; }
132:button.pc-persona { cursor: pointer; text-align: left; }
133:button.pc-persona:hover { color: var(--accent-press); text-decoration: underline; }
134:.pc-estado, .pc-origen { display: inline-flex; align-items: center; height: 22px; padding: 0 8px; border-radius: 5px; background: var(--secondary); color: var(--muted-foreground-strong); font-size: 12px; font-weight: 600; }
136:.pc-origen[data-origen='cliente'] { background: var(--primary); color: #fff; }
137:.pc-origen[data-origen='referido'] { background: color-mix(in srgb, var(--accent) 10%, white); color: var(--accent-press); }
138:.pc-origen[data-origen='lead'] { color: var(--primary); }
```

## Diff
```diff
diff --git a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
index 2f0c6c74..f7b7b46f 100644
--- a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
@@ -280,7 +280,18 @@ test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el c
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
   await page.keyboard.press('Escape')
   await expect(lista).toHaveCount(0)
   // Días: la fila de tramos se desplaza dentro de la tarjeta, nunca la página.
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
index 252fa7d4..67acad60 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
@@ -1,10 +1,12 @@
 // Lista lateral detrás de una cifra de la Proyección: las citas exactas que la
-// componen, con su monto original y en soles, y su CSV.
+// componen, con su monto original y en soles, y su CSV. En el celular cada cita
+// es una tarjeta: la tabla de escritorio no cabe y obliga a deslizar de lado.
 import { useState } from 'react'
 import { Download, X } from 'lucide-react'
 import { Button } from '@/components/ui/button'
 import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
 import { fmtFecha, money, numero } from '@/lib/format'
+import { useEsMovil } from '@/lib/media'
 import { useDatosCitas } from './contexto'
 import { fechaLocalCitas } from './fecha-comercial'
 import { ESTADOS } from './modelo'
@@ -26,8 +28,23 @@ function PersonaCita({ c, onAbrir }: { c: CitaProyectada; onAbrir: ((leadId: str
   return <button type="button" className="pc-persona" onClick={() => onAbrir(leadId, c.cita.id)}>{c.cita.nombre}</button>
 }
 
+/** Celular: una tarjeta por cita, con los mismos datos y en el mismo orden que la tabla. */
+function TarjetasCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: ((leadId: string, tareaId: string) => void) | undefined }) {
+  return <ul className="pc-citas" aria-label={detalle.titulo}>{detalle.lista.map(c => <li key={c.cita.id} className="pc-cita">
+    <div className="pc-cita-cab"><PersonaCita c={c} onAbrir={onAbrir} /><span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span></div>
+    <dl className="pc-cita-datos">
+      <div><dt>Creada</dt><dd>{c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'}</dd></div>
+      <div><dt>Cita</dt><dd>{fmtFecha(c.cita.fecha)} · {c.cita.hora}</dd></div>
+      {detalle.conAnalista && <div><dt>Analista</dt><dd>{c.cita.analistaNombre}</dd></div>}
+      <div><dt>Estado</dt><dd><span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span></dd></div>
+      <div><dt>Monto</dt><dd><MontoCita c={c} /></dd></div>
+    </dl>
+  </li>)}</ul>
+}
+
 export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle: ListaProyeccion | null; onCerrar: () => void; focoRespaldo: () => HTMLElement | null }) {
   const { onAbrirLead } = useDatosCitas()
+  const esMovil = useEsMovil()
   const [aviso, setAviso] = useState('')
   const n = detalle?.lista.length ?? 0
   const cerrar = () => { setAviso(''); onCerrar() }
@@ -43,7 +60,7 @@ export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle
     </div><Button variant="ghost" size="icon" aria-label="Cerrar lista" onClick={cerrar}><X aria-hidden /></Button></div></SheetHeader>
     {detalle && <>
       <SheetBody className="p-0">
-        <table className="pc-lista">
+        {esMovil ? <TarjetasCitas detalle={detalle} onAbrir={abrirFicha} /> : <table className="pc-lista">
           <caption className="sr-only">{detalle.titulo}</caption>
           <thead><tr><th scope="col">Creada</th><th scope="col">Cita</th><th scope="col">Persona</th>{detalle.conAnalista && <th scope="col">Analista</th>}<th scope="col">Estado</th><th scope="col" className="pc-num">Monto</th><th scope="col">Origen</th></tr></thead>
           <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
@@ -55,7 +72,7 @@ export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle
             <td className="pc-num"><MontoCita c={c} /></td>
             <td><span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span></td>
           </tr>)}</tbody>
-        </table>
+        </table>}
       </SheetBody>
       <SheetFooter className="justify-end"><p role="status" className={aviso ? 'mr-auto text-xs text-muted-foreground-strong' : 'sr-only'}>{aviso}</p><Button variant="outline" onClick={exportar} disabled={!n}><Download aria-hidden />Exportar CSV</Button></SheetFooter>
     </>}
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
index 17707871..f73c834a 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
@@ -681,6 +681,9 @@ describe('Proyección en el celular: tarjetas', () => {
   const nombresTarjetas = (lista: HTMLElement) => tarjetas(lista).map(t => t.querySelector('.pc-tarjeta-nombre')!.textContent)
   const tarjeta = (lista: HTMLElement, nombre: string) => tarjetas(lista).find(t => t.querySelector('.pc-tarjeta-nombre')!.textContent === nombre)!
   const filtros = () => screen.getByRole('button', { name: /^Filtros/ })
+  /** La lista lateral en el celular: una tarjeta por cita. */
+  const citasDe = (detalle: HTMLElement) => within(within(detalle).getByRole('list')).getAllByRole('listitem')
+  const citaDe = (detalle: HTMLElement, persona: string) => citasDe(detalle).find(li => li.querySelector('.pc-persona')!.textContent === persona)!
 
   it('una tarjeta por analista en el orden de la hoja, con el Total primero; cada cifra es botón (salvo ceros y «—») y abre la misma lista', async () => {
     const { usuario, lista } = await abrirTarjetas()
@@ -703,15 +706,42 @@ describe('Proyección en el celular: tarjetas', () => {
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
+    expect(citasDe(detalle).map(li => li.querySelector('.pc-persona')!.textContent).sort()).toEqual(CITAS.map(c => c.nombre).sort())
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
   })
 
   it('«Ordenar por» y «Filtros» usan el mismo orden y los mismos embudos de la hoja', async () => {
@@ -779,7 +809,7 @@ describe('Proyección en el celular: tarjetas', () => {
     expect(within(tarjeta(lista, 'Total · 3 analistas')).getByRole('group', { name: 'Citas por semana de todos los analistas' })).toBeVisible()
     await usuario.click(within(semanas).getByRole('button', { name: '1 cita de Ana Torres, S2 8–14 oct' }))
     const detalle = screen.getByRole('dialog', { name: 'Citas · S2 8–14 oct · Ana Torres' })
-    expect(within(detalle).getByRole('row', { name: /Persona a4/ })).toBeVisible()
+    expect(citaDe(detalle, 'Persona a4')).toBeVisible()
     await usuario.keyboard('{Escape}')
     await usuario.click(tiempo('Días'))
     const dias = within(tarjeta(lista, 'Luis Vega')).getByRole('group', { name: 'Citas por día de Luis Vega' })
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
index cd7491a6..bf9fd3ab 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.css
@@ -136,6 +136,18 @@ button.pc-persona:hover { color: var(--accent-press); text-decoration: underline
 .pc-origen[data-origen='cliente'] { background: var(--primary); color: #fff; }
 .pc-origen[data-origen='referido'] { background: color-mix(in srgb, var(--accent) 10%, white); color: var(--accent-press); }
 .pc-origen[data-origen='lead'] { color: var(--primary); }
+/* Lista lateral en el celular: una tarjeta por cita; nombre a 16 px y todo el detalle a 14 px, sin deslizar de lado. */
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
@@ -201,6 +213,7 @@ button.pc-persona:hover { color: var(--accent-press); text-decoration: underline
   /* También el 0 y el «—»: así los ceros quedan a la altura de los botones de su fila. */
   .pc-tarjeta :is(.pc-n, button.cm-senal) { min-height: 44px; }
   .pc-tarjeta-cifras dd { min-height: 44px; }
+  .pc-cita button.pc-persona { min-height: 44px; }
   .pc-acciones button, .pc-controles button, .pc-panel [role='menuitem'] { min-height: 44px; }
   .pc-sentido { width: 44px; }
   .pc-op, .pc-atajo { min-height: 44px; }
```
