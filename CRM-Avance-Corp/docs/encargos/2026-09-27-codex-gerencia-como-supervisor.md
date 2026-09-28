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

# Encargo: REFUTAR «gerencia se ve como el supervisor» + arreglos del E2E — LEVEL 2

Rutas relativas a `CRM-Avance-Corp/app/`. Ya revisaste el código de G1/G2 (tus 8 hallazgos se corrigieron).
Ahora Miguel vio la pantalla y pidió: «PULSO DIARIO no se ve igual, adáptalo, y además ¿pulso diario? ponle un
nombre más normal» y «Registro del Equipo de SUPERVISOR UNO: lo mismo no está igual, me refiero a la UI, que quede
como lo ve supervisores».

Busca dónde el cambio rompe algo: números que ya no abren su lista exacta (regla de Miguel: todo número se abre y
«el número es la lista»), cuentas de las pastillas que no coinciden con lo que la tabla muestra, la fila
«Toda la operación» (sticky tfoot, cifras autoritativas, atención desconocida → null), foco/lector (nombres
accesibles, títulos visibles vs `sr-only`), la versión compacta del registro con filtro de equipo y CSV
(`aria-disabled`, aviso), regresiones del SUPERVISOR y del ANALISTA por `registro-actividad.tsx` compartido,
el efecto sin dependencias de `vista-equipo-gerencia.tsx` y las reglas CSS de Hábitos.

## Decisiones del dueño (NO son hallazgos)
- La pestaña «Pulso diario» pasa a «Actividad del día».
- Sin franja de 4 cifras aparte: como el supervisor, pastillas-filtro en la tabla + buscador a la derecha + pie
  «N de N equipos · Actualizado». Las 4 cifras quedan en la fila «Toda la operación» al pie de la tabla; la
  comparación con ayer y la referencia queda SOLO en «Comparar días» (se asume esa pérdida de vista rápida).
- Filas y ficha muestran el nombre del supervisor (como el del analista en su tabla); se oye «Equipo de …».
- El registro de gerencia usa la versión COMPACTA del supervisor; se conserva filtro de equipo y CSV; el filtro
  por etapa y el «Actualizar» propio desaparecen (igual que en supervisor y analista).
- G4 (pendientes de gerencia) sigue fuera.

## Verificación del PRIMARY
- `npm run check` PASS tras el primer commit (lint + typecheck + 4680 pruebas + build + bundle + duplicados).
- Tras el segundo commit: lint y typecheck PASS (pre-commit), 238 pruebas de Gestión Diaria PASS.
- E2E en Docker aislado: EN CURSO al escribir esto (pulso, gestion-diaria, equipo, horizontal-h5).

## Diff (src + el ajuste del spec; el spec migrado por el subagente no se transcribe entero)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/cifras-operacion.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/cifras-operacion.tsx
deleted file mode 100644
index 5e3001d3..00000000
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/cifras-operacion.tsx
+++ /dev/null
@@ -1,50 +0,0 @@
-// Las 4 cifras de la operación (decisión de Miguel, 27/09/2026) en una franja
-// FINA: la jerarquía es de la tabla de equipos y de la ficha, como en el
-// supervisor. Cada número abre su lista exacta (revisión Codex del plan):
-// Llamadas y Contacto → Registro general en «Llamadas» (con el resultado de cada
-// llamada); Citas → los equipos ordenados por citas; Sin registro → quiénes son.
-import type { JSX } from 'react'
-import { cifraPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
-import { referenciaCifra } from '@/lib/gestion-diaria-operacion'
-import { cn } from '@/lib/utils'
-import { FOCO } from './estilos-gestion'
-
-export type DestinoCifra = 'llamadas' | 'contacto' | 'citas' | 'sin_registro'
-
-export function CifrasOperacion({ pulso, esHoy, abrir }: {
-  pulso: PulsoGerencia
-  esHoy: boolean
-  abrir: (destino: DestinoCifra, origen: HTMLElement) => void
-}): JSX.Element {
-  const a = pulso.actual
-  const cifras: { destino: DestinoCifra; etiqueta: string; valor: string; detalle: string; referencia: string; accion: string }[] = [
-    { destino: 'llamadas', etiqueta: 'Llamadas', valor: cifraPulso(a.llamadas), detalle: `${a.contestadas} contestaron`,
-      referencia: referenciaCifra(pulso, 'llamadas', esHoy), accion: 'Ver las llamadas en el registro general' },
-    { destino: 'contacto', etiqueta: 'Contacto', valor: a.tasa_contacto === null ? '—' : `${Math.round(a.tasa_contacto)} %`, detalle: `de ${a.utiles} útiles`,
-      referencia: referenciaCifra(pulso, 'tasa_contacto', esHoy, true), accion: 'Ver las llamadas y su resultado en el registro general' },
-    { destino: 'citas', etiqueta: 'Citas agendadas', valor: cifraPulso(a.citas_agendadas), detalle: esHoy ? 'hoy' : 'ese día',
-      referencia: referenciaCifra(pulso, 'citas_agendadas', esHoy), accion: 'Ver los equipos ordenados por citas' },
-    { destino: 'sin_registro', etiqueta: 'Sin registro', valor: `${a.sin_actividad} de ${a.analistas_activos}`, detalle: 'analistas',
-      referencia: referenciaCifra(pulso, 'sin_actividad', esHoy), accion: 'Ver quiénes no tienen registro' },
-  ]
-  return (
-    <section aria-label="Cifras de la operación" className="shrink-0 rounded-2xl border border-border bg-card">
-      <dl className="grid grid-cols-2 lg:grid-cols-4">
-        {cifras.map((c, i) => (
-          <div key={c.destino} className={cn('min-w-0 px-5 py-2.5', i % 2 === 1 && 'border-l border-border',
-            i === 2 && 'lg:border-l lg:border-border', i >= 2 && 'border-t border-border lg:border-t-0')}>
-            <dt className="text-[11.5px] font-bold uppercase tracking-[0.04em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
-            <dd className="mt-0.5 flex flex-wrap items-baseline gap-x-2">
-              <button type="button" onClick={(e) => abrir(c.destino, e.currentTarget)} aria-label={`${c.etiqueta}: ${c.valor}. ${c.accion}`}
-                className={cn('cursor-pointer rounded-md text-[22px] font-extrabold leading-tight tabular-nums text-primary underline-offset-4 hover:underline pointer-coarse:min-h-11', FOCO)}>
-                {c.valor}
-              </button>
-              <span className="text-xs text-[var(--muted-foreground-strong)]">{c.detalle}</span>
-            </dd>
-            <dd className="text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{c.referencia}</dd>
-          </div>
-        ))}
-      </dl>
-    </section>
-  )
-}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
index ab275bbc..bcc46da6 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-operacion-gerencia.tsx
@@ -3,12 +3,12 @@
 // quienes no tienen registro y el registro (general o del equipo). Las cifras del
 // equipo son las del pulso; el detalle solo aporta atención y barras de sus
 // analistas activos, y lo dice (revisión Codex del plan).
-import type { JSX, ReactNode, RefObject } from 'react'
+import { useRef, type JSX, type ReactNode, type RefObject } from 'react'
 import { Title as TituloDialogo } from '@radix-ui/react-dialog'
 import { ChevronRight, ClipboardList, Maximize2, Minimize2, UserX, Users, X } from 'lucide-react'
 import { Avatar } from '@/components/ui/avatar'
 import { cifraPulso, type EquipoPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
-import { atencionEquipo, barrasEquipo, nombreEquipo, personasSinRegistro, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
+import { atencionEquipo, barrasEquipo, delEquipo, nombreEquipo, personasSinRegistro, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
 import { presentarAtencion, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
 import type { PestanaRegistro } from '@/lib/gestion-diaria'
 import { cn } from '@/lib/utils'
@@ -58,21 +58,27 @@ export function PanelOperacionGerencia({ id, vista, pulso, detalle, detalleFalli
   const equipo = vista?.tipo === 'equipo' || (vista?.tipo === 'registro' && vista.alcance !== 'general')
     ? pulso.equipos.find((e) => e.clave === (vista.tipo === 'equipo' ? vista.clave : vista.alcance)) : undefined
   const nombre = equipo ? nombreEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre }) : ''
+  const del = equipo ? delEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre }) : ''
   const titulo = vista === null ? 'Detalle de la operación' : vista.tipo === 'sin_registro' ? 'Sin registro'
-    : vista.tipo === 'registro' ? vista.alcance === 'general' ? 'Registro general' : `Registro del ${nombre}` : nombre
+    : vista.tipo === 'registro' ? vista.alcance === 'general' ? 'Registro general' : `Registro ${del}` : nombre
+  // Como la ficha del supervisor (Miguel, 27/09): un nombre corto arriba y una línea
+  // debajo. Se ve el nombre del supervisor; se oye «Detalle del Equipo de …».
+  const fuera = equipo?.clave === 'fuera'
   const subtitulo = vista === null ? null : vista.tipo === 'sin_registro'
     ? `${plural(pulso.actual.sin_actividad, 'analista sin ninguna gestión', 'analistas sin ninguna gestión')} ${esHoy ? 'hoy' : 'ese día'}`
-    : equipo ? `${plural(equipo.metricas.analistas_activos, 'analista', 'analistas')} · ${equipo.metricas.con_actividad} con registro${esHoy ? ' hoy' : ''}` : esHoy ? 'Hoy' : pulso.dia
+    : vista.tipo === 'registro' ? equipo ? nombre : null
+      : equipo ? `${fuera ? '' : 'Equipo de '}${plural(equipo.metricas.analistas_activos, 'analista', 'analistas')}` : null
   return (
-    <section id={id} aria-label={vista?.tipo === 'equipo' ? `Detalle del ${nombre}` : titulo} className={FICHA}>
+    <section id={id} aria-label={vista?.tipo === 'equipo' ? `Detalle ${del}` : titulo} className={FICHA}>
       <header className={CABECERA_FICHA}>
         {vista?.tipo === 'equipo' && equipo ? <Avatar nombre={equipo.nombre} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
-          : <span aria-hidden="true" className="grid size-11 shrink-0 place-items-center rounded-full bg-card text-primary">
-            {vista?.tipo === 'sin_registro' ? <UserX className="size-5" /> : vista?.tipo === 'registro' ? <ClipboardList className="size-5" /> : <Users className="size-5" />}
+          : <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary">
+            {vista?.tipo === 'sin_registro' ? <UserX className="size-4" /> : vista?.tipo === 'registro' ? <ClipboardList className="size-4" /> : <Users className="size-4" />}
           </span>}
         <div className="min-w-0 flex-1">
           <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className={TITULO_FICHA}>
-            {vista?.tipo === 'equipo' ? <><span className="sr-only">Detalle del</span>{' '}{nombre}</> : titulo}
+            {vista?.tipo === 'equipo' && equipo ? <><span className="sr-only">{fuera ? 'Detalle del grupo' : 'Detalle del Equipo de'}</span>{' '}{equipo.nombre}</>
+              : vista?.tipo === 'registro' && equipo ? <>Registro del equipo<span className="sr-only">: {nombre}</span></> : titulo}
           </h3></TituloDialogo>
           {subtitulo && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{subtitulo}</p>}
         </div>
@@ -85,17 +91,17 @@ export function PanelOperacionGerencia({ id, vista, pulso, detalle, detalleFalli
         {vista === null ? <div className="flex h-full flex-col items-center justify-center gap-3 px-8 py-10 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
           <Users className="size-9 text-muted-foreground" aria-hidden /><p>Elige un equipo de la tabla para ver su día.</p></div>
           : vista.tipo === 'equipo' ? equipo
-            ? <FichaEquipo equipo={equipo} nombre={nombre} detalle={detalle} detalleFallido={detalleFallido} esHoy={esHoy} abrirVista={abrirVista} entrarEquipo={entrarEquipo} abrirPersona={abrirPersona} />
+            ? <FichaEquipo equipo={equipo} del={del} detalle={detalle} detalleFallido={detalleFallido} esHoy={esHoy} abrirVista={abrirVista} entrarEquipo={entrarEquipo} abrirPersona={abrirPersona} />
             : <p role="status" className="px-5 py-4 text-[13px]">Este equipo ya no aparece en la consulta. Elige otro de la tabla.</p>
             : vista.tipo === 'sin_registro' ? <ListaSinRegistro pulso={pulso} esHoy={esHoy} abrirPersona={abrirPersona} />
-              : <RegistroOperacion key={`${vista.alcance}:${vista.apertura}`} vista={vista} pulso={pulso} equipo={equipo} titulo={titulo} actualizacion={actualizacion} revocar={revocar} abrirGeneral={() => abrirVista({ tipo: 'registro', alcance: 'general', pestana: vista.pestana, apertura: vista.apertura + 1 })} />}
+              : <RegistroOperacion key={`${vista.alcance}:${vista.apertura}`} vista={vista} pulso={pulso} equipo={equipo} esHoy={esHoy} actualizacion={actualizacion} revocar={revocar} abrirGeneral={() => abrirVista({ tipo: 'registro', alcance: 'general', pestana: vista.pestana, apertura: vista.apertura + 1 })} />}
       </div>
     </section>
   )
 }
 
-function FichaEquipo({ equipo: e, nombre, detalle, detalleFallido, esHoy, abrirVista, entrarEquipo, abrirPersona }: {
-  equipo: EquipoPulso; nombre: string; detalle: FilaEquipoPresentada[] | null; detalleFallido: boolean; esHoy: boolean
+function FichaEquipo({ equipo: e, del, detalle, detalleFallido, esHoy, abrirVista, entrarEquipo, abrirPersona }: {
+  equipo: EquipoPulso; del: string; detalle: FilaEquipoPresentada[] | null; detalleFallido: boolean; esHoy: boolean
   abrirVista: (vista: VistaOperacion) => void; entrarEquipo: (clave: string, preset?: PresetEquipo) => void; abrirPersona: (analistaId: string) => void
 }): JSX.Element {
   const m = e.metricas
@@ -108,22 +114,22 @@ function FichaEquipo({ equipo: e, nombre, detalle, detalleFallido, esHoy, abrirV
         <Cuadro etiqueta="Llamadas">
           <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.llamadas}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">{plural(m.contestadas, 'contestó', 'contestaron')}</span>
-          <button type="button" onClick={llamadas} aria-label={`Ver las llamadas del ${nombre}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
+          <button type="button" onClick={llamadas} aria-label={`Ver las llamadas ${del}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
         </Cuadro>
         <Cuadro etiqueta="Contacto">
           <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.tasa_contacto === null ? '—' : `${Math.round(m.tasa_contacto)} %`}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">de {plural(m.utiles, 'llamada útil', 'llamadas útiles')}</span>
-          <button type="button" onClick={llamadas} aria-label={`Ver las llamadas y su resultado del ${nombre}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
+          <button type="button" onClick={llamadas} aria-label={`Ver las llamadas y su resultado ${del}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
         </Cuadro>
         <Cuadro etiqueta="Citas agendadas">
           <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.citas_agendadas}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">{esHoy ? 'hoy' : 'ese día'}</span>
-          <button type="button" onClick={() => entrarEquipo(e.clave, 'citas')} aria-label={`Ver las citas por analista del ${nombre}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
+          <button type="button" onClick={() => entrarEquipo(e.clave, 'citas')} aria-label={`Ver las citas por analista ${del}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
         </Cuadro>
         <Cuadro etiqueta="Tareas vencidas">
           <span className={cn('block text-[28px] font-extrabold leading-tight tabular-nums', e.tareas_vencidas > 0 ? 'text-[var(--destructive-text)]' : 'text-primary')}>{e.tareas_vencidas}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">siguen pendientes</span>
-          <button type="button" onClick={() => entrarEquipo(e.clave, 'vencidas')} aria-label={`Ver las vencidas por analista del ${nombre}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
+          <button type="button" onClick={() => entrarEquipo(e.clave, 'vencidas')} aria-label={`Ver las vencidas por analista ${del}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
         </Cuadro>
       </dl>
 
@@ -208,22 +214,29 @@ function ListaSinRegistro({ pulso, esHoy, abrirPersona }: { pulso: PulsoGerencia
   )
 }
 
-function RegistroOperacion({ vista, pulso, equipo, titulo, actualizacion, revocar, abrirGeneral }: {
-  vista: Extract<VistaOperacion, { tipo: 'registro' }>; pulso: PulsoGerencia; equipo: EquipoPulso | undefined; titulo: string
+const FECHA_TITULO = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })
+
+function RegistroOperacion({ vista, pulso, equipo, esHoy, actualizacion, revocar, abrirGeneral }: {
+  vista: Extract<VistaOperacion, { tipo: 'registro' }>; pulso: PulsoGerencia; equipo: EquipoPulso | undefined; esHoy: boolean
   actualizacion: number; revocar: () => void; abrirGeneral: () => void
 }): JSX.Element {
+  const tituloRegistro = useRef<HTMLHeadingElement>(null)
   // El registro del equipo lleva a todos sus autores con id (activos e inactivos); los sin autor, al general.
   const ids = equipo ? equipo.personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id]) : null
   const sinAutor = equipo?.personas.some((p) => p.analista_id === null) ?? false
   const llamadasSinAutor = equipo?.personas.reduce((n, p) => p.analista_id === null ? n + p.llamadas : n, 0) ?? 0
   return (
-    <section aria-label="Registro seleccionado" className="space-y-3 px-5 py-4">
-      <h4 className="sr-only">{titulo}</h4>
+    // Como el registro del supervisor (Miguel, 27/09): título corto con el día,
+    // filtros en pastilla y filas limpias; gerencia suma equipo y CSV en el mismo tamaño.
+    <section aria-label="Registro seleccionado" className="space-y-2 px-5 py-4">
+      <h4 ref={tituloRegistro} tabIndex={-1} className={cn('rounded-md text-[15px] font-extrabold text-primary', FOCO)}>
+        {esHoy ? 'Actividad de hoy' : `Actividad del ${FECHA_TITULO.format(new Date(`${pulso.dia}T12:00:00-05:00`))}`}
+      </h4>
       {vista.alcance === 'general'
-        ? <RegistroActividad dia={pulso.dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
-        : ids && ids.length > 0 ? <RegistroActividad dia={pulso.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
+        ? <RegistroActividad compacto encabezadoExterno={tituloRegistro} dia={pulso.dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
+        : ids && ids.length > 0 ? <RegistroActividad compacto encabezadoExterno={tituloRegistro} dia={pulso.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
           : <p className="text-[13px]">Este equipo no tiene autores con registro propio.</p>}
-      {sinAutor && <p className="text-[13px]">{llamadasSinAutor > 0 ? `${plural(llamadasSinAutor, 'llamada sin autor no aparece', 'llamadas sin autor no aparecen')} aquí: ` : 'Los registros sin autor se consultan en el '}
+      {sinAutor && <p className="text-xs text-[var(--muted-foreground-strong)]">{llamadasSinAutor > 0 ? `${plural(llamadasSinAutor, 'llamada sin autor no aparece', 'llamadas sin autor no aparecen')} aquí: ` : 'Los registros sin autor se consultan en el '}
         <button type="button" className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)} onClick={abrirGeneral}>{llamadasSinAutor > 0 ? 'verlas en el registro general' : 'registro general del día'}</button>.</p>}
     </section>
   )
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
index 0e3e1992..35586313 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
@@ -29,6 +29,7 @@ import { Badge } from '@/components/ui/badge'
 import { Button } from '@/components/ui/button'
 import { Select } from '@/components/ui/select'
 import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
+import { BOTON_CABECERA } from './estilos-gestion'
 
 const LIMITE_PAGINA = 25
 // Tokens de TEXTO: el chip `soft` pinta el color puro sobre un tinte al 12 %, y
@@ -69,6 +70,8 @@ interface Props {
   /**
    * Compacto dentro de la ficha del supervisor (27/09/2026): el título lo pone
    * la ficha y el foco de respaldo («Ver más» que se va, «Reintentar») va a él.
+   * Gerencia usa esta misma versión (Miguel, 27/09: «como lo ve el supervisor»)
+   * y conserva lo suyo en el mismo tamaño: filtro por equipo y CSV.
    */
   encabezadoExterno?: RefObject<HTMLHeadingElement | null> | undefined
 }
@@ -299,16 +302,34 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
     </Tabs>
   )
   if (compacto && encabezadoExterno) {
+    const rotulo = 'flex flex-wrap items-center gap-2 text-[13px] font-semibold text-[var(--muted-foreground-strong)]'
     return (
       <div className="space-y-2">
+        {permitirEquipo && (
+          <label htmlFor={`${id}-equipo`} className={rotulo}>Equipo
+            <Select id={`${id}-equipo`} value={equipoSel ?? ''} onChange={(e) => { setEquipoSel(e.target.value || null); setAnalista(null) }} className="h-9 min-h-0 w-auto min-w-48 text-[13px]">
+              <option value="">Todos los equipos</option>
+              {supervisores.map((m) => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
+            </Select>
+          </label>
+        )}
         {mostrarAnalista && analistaIds?.length !== 1 && (
-          <label htmlFor={`${id}-analista`} className="flex flex-wrap items-center gap-2 text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Analista
+          <label htmlFor={`${id}-analista`} className={rotulo}>Analista
             <Select id={`${id}-analista`} value={analista ?? ''} onChange={(e) => setAnalista(e.target.value || null)} className="h-9 min-h-0 w-auto min-w-48 text-[13px]">
               <option value="">Todos los analistas</option>
               {analistas.map((m) => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
             </Select>
           </label>
         )}
+        {permitirExportar && (
+          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
+            {/* `aria-disabled` y no `disabled`: sin filas no se exporta, pero el foco no se pierde. */}
+            <button type="button" className={BOTON_CABECERA} aria-disabled={visibles.length === 0} onClick={() => { if (visibles.length > 0) exportar() }}>
+              <Download aria-hidden className="size-4" />Exportar CSV
+            </button>
+            {aviso && !sinPermiso && <p role="status" aria-live="polite" className="text-[12.5px] text-[var(--muted-foreground-strong)]">{aviso}</p>}
+          </div>
+        )}
         {pastillas}
       </div>
     )
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
index 14eeb13d..a5aeb6ac 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipos-gerencia.tsx
@@ -1,19 +1,20 @@
 /* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar con el teclado las columnas que no caben. */
 // Tabla de equipos de «Toda la operación» (diseño de Gestión Diaria, 27/09/2026):
-// la protagonista. Misma forma que la del supervisor —tabla semántica con
-// `aria-sort`, filas de 52 px, botón de selección e «Ir al detalle»— y conserva
-// la comparación de gerencia: buscador, «Con atención», primer intento y
-// dispersión (revisión Codex del plan). Los números de cada fila abren el
-// equipo con ese filtro u orden: el número es la lista.
+// la protagonista. Misma forma que la del supervisor —pastillas que SON los
+// filtros, buscador a la derecha, tabla semántica con `aria-sort`, filas de 52 px,
+// botón de selección e «Ir al detalle»— y conserva la comparación de gerencia:
+// primer intento, dispersión y, al pie, «Toda la operación» con las cifras que
+// antes iban en una franja aparte (Miguel, 27/09: «que quede como lo ve el
+// supervisor»). Cada número abre su lista: el número es la lista.
 import type { JSX } from 'react'
-import { ArrowDown, ArrowRight, ArrowUp, Check, Search } from 'lucide-react'
+import { ArrowDown, ArrowRight, ArrowUp, Check, Search, Users } from 'lucide-react'
 import { Avatar } from '@/components/ui/avatar'
 import { Badge } from '@/components/ui/badge'
 import { COLOR_NIVEL, ETIQUETA_NIVEL, type UmbralesSchema } from '@/lib/gestion-diaria-analista'
 import type * as v from 'valibot'
 import { Input } from '@/components/ui/input'
 import { cifraPulso } from '@/lib/gestion-diaria-pulso'
-import { nivelEquipo, nombreEquipo, type FilaEquipoOperacion, type FiltrosOperacion, type OrdenOperacion } from '@/lib/gestion-diaria-operacion'
+import { delEquipo, enEquipo, nivelEquipo, nombreEquipo, type EstadoOperacion, type FilaEquipoOperacion, type FiltrosOperacion, type OrdenOperacion } from '@/lib/gestion-diaria-operacion'
 import { cn } from '@/lib/utils'
 import { CONTROL, FOCO, PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA } from './estilos-gestion'
 
@@ -25,16 +26,18 @@ const COLUMNAS: { orden: OrdenOperacion; titulo: string; ancho: string; derecha?
   { orden: 'vencidas', titulo: 'Vencidas', ancho: 'w-[72px]', derecha: true }, { orden: 'atencion', titulo: 'Atención', ancho: 'w-[116px]' },
   { orden: 'primer_intento', titulo: 'Primer intento', ancho: 'w-[96px]', derecha: true }, { orden: 'dispersion', titulo: 'Dispersión', ancho: 'w-[104px]', derecha: true },
 ]
-
+const PILDORAS: readonly { valor: EstadoOperacion; etiqueta: string }[] = [
+  { valor: 'todos', etiqueta: 'Todos' }, { valor: 'atencion', etiqueta: 'Con atención' }, { valor: 'vencidas', etiqueta: 'Con vencidas' },
+]
 
 const ENLACE_CIFRA = cn('cursor-pointer rounded-md font-semibold tabular-nums underline-offset-2 hover:underline pointer-coarse:min-h-11', FOCO)
 
-export function TablaEquiposGerencia({ filas, total, conAtencion, sinDetalle = 'cargando', umbrales = null, filtros, setFiltros, ordenar, seleccion, seleccionar, accion, panelId, irAlDetalle }: {
+export function TablaEquiposGerencia({ filas, total, conteos, sinDetalle = 'cargando', umbrales = null, filtros, setFiltros, ordenar, seleccion, seleccionar, accion, totalOperacion, accionTotal, panelId, irAlDetalle }: {
   /** Ya filtradas y ordenadas. */
   filas: FilaEquipoOperacion[]
   total: number
-  /** Equipos con atención; null sin detalle. */
-  conAtencion: number | null
+  /** Equipos de cada pastilla; «Con atención» es null sin detalle. */
+  conteos: { atencion: number | null; vencidas: number }
   /** Por qué falta el detalle: mientras llega se dice «…»; si falló, «—» y «No disponible». */
   sinDetalle?: 'cargando' | 'error'
   /** Umbrales del servidor para el nivel de contacto (llegan con el detalle). */
@@ -45,22 +48,37 @@ export function TablaEquiposGerencia({ filas, total, conAtencion, sinDetalle = '
   seleccion: string | null
   seleccionar: (fila: FilaEquipoOperacion, origen: HTMLElement) => void
   accion: (fila: FilaEquipoOperacion, tipo: AccionEquipo, origen: HTMLElement) => void
+  /** La fila del pie: las cifras de toda la operación, con sus propias listas. */
+  totalOperacion: FilaEquipoOperacion
+  accionTotal: (tipo: AccionEquipo, origen: HTMLElement) => void
   panelId: string
   irAlDetalle: () => void
 }): JSX.Element {
+  const conteo = (p: EstadoOperacion) => p === 'todos' ? total : p === 'vencidas' ? conteos.vencidas : conteos.atencion
   return <>
     <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
-      <label className="relative min-w-40 max-w-[240px] flex-1"><span className="sr-only">Buscar equipo</span>
+      <div role="group" aria-label="Resumen de la operación" className="flex flex-wrap items-center gap-1.5">
+        {PILDORAS.map((p) => {
+          const activa = filtros.estado === p.valor
+          const n = conteo(p.valor)
+          return (
+            // Cada cifra es de la operación entera: abrirla limpia la búsqueda (Codex, 27/09).
+            <button key={p.valor} type="button" aria-pressed={activa} onClick={() => setFiltros((f) => ({ ...f, busqueda: '', estado: p.valor }))}
+              className={cn(PILDORA, activa ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
+              {activa && <Check aria-hidden className="size-3.5" />}{p.etiqueta}{' '}
+              {p.valor === 'atencion' && n !== null && n > 0
+                // Ámbar y no rojo, como «Necesitan atención» del supervisor.
+                ? <span className="grid min-w-5 place-items-center rounded-full bg-[var(--warning-text)] px-1.5 text-[11px] font-bold tabular-nums text-white">{n}</span>
+                : <span className="font-bold tabular-nums">{n ?? (sinDetalle === 'error' ? '—' : '…')}</span>}
+            </button>
+          )
+        })}
+      </div>
+      <label className="relative ml-auto min-w-40 max-w-[220px] flex-1"><span className="sr-only">Buscar equipo</span>
         <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
         <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar equipo…"
           className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
       </label>
-      <button type="button" aria-pressed={filtros.conAtencion} onClick={() => setFiltros((f) => ({ ...f, conAtencion: !f.conAtencion, busqueda: f.conAtencion ? f.busqueda : '' }))}
-        className={cn(PILDORA, filtros.conAtencion ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
-        {filtros.conAtencion && <Check aria-hidden className="size-3.5" />}Con atención{' '}
-        <span className="font-bold tabular-nums">{conAtencion ?? (sinDetalle === 'error' ? '—' : '…')}</span>
-      </button>
-      <p className="ml-auto text-xs text-[var(--muted-foreground-strong)]"><span role="status">{filas.length} de {total} equipos</span></p>
     </div>
     {/* Las dos últimas columnas desplazan dentro de la tabla, no la página. */}
     <div className="gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-auto !overflow-x-auto" tabIndex={0} role="region" aria-label="Desplazar tabla de equipos">
@@ -83,6 +101,7 @@ export function TablaEquiposGerencia({ filas, total, conAtencion, sinDetalle = '
           {filas.map((f) => {
             const activa = f.clave === seleccion
             const nombre = nombreEquipo(f)
+            const abrir = (tipo: AccionEquipo, origen: HTMLElement) => accion(f, tipo, origen)
             return (
               <tr key={f.clave} data-equipo={f.clave} data-activa={activa}
                 className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
@@ -90,15 +109,12 @@ export function TablaEquiposGerencia({ filas, total, conAtencion, sinDetalle = '
                   <div className="flex min-h-[52px] items-center gap-2.5">
                     <Avatar nombre={f.nombre} color="var(--accent-press)" relleno={activa} />
                     <div className="min-w-0 flex-1 py-1">
+                      {/* Se ve el nombre del supervisor, como el del analista en su tabla; se oye «Equipo de …». */}
                       <button type="button" aria-label={`Seleccionar ${nombre}`}
                         aria-current={activa ? 'true' : undefined} aria-controls={panelId} onClick={(e) => seleccionar(f, e.currentTarget)}
                         className={cn('block max-w-full cursor-pointer rounded-md text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
-                          activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{nombre}</button>
-                      <p className="text-[11.5px] text-[var(--muted-foreground-strong)]">
-                        {f.analistas} {f.analistas === 1 ? 'analista' : 'analistas'}
-                        {f.sinRegistro > 0 && <> · <button type="button" onClick={(e) => accion(f, 'sin_registro', e.currentTarget)}
-                          aria-label={`${f.sinRegistro} sin registro en ${nombre}: ver quiénes`} className={ENLACE_CIFRA}>{f.sinRegistro} sin registro</button></>}
-                      </p>
+                          activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{f.nombre}</button>
+                      <Integrantes f={f} en={enEquipo(f)} abrir={abrir} />
                     </div>
                     {activa && <button type="button" aria-label={`Ir al detalle de ${nombre}`} onClick={irAlDetalle}
                       className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
@@ -106,50 +122,89 @@ export function TablaEquiposGerencia({ filas, total, conAtencion, sinDetalle = '
                     </button>}
                   </div>
                 </th>
-                <td data-etiqueta="Llamadas" className="px-2 text-right text-sm tabular-nums text-foreground">
-                  {f.llamadas > 0 ? <button type="button" onClick={(e) => accion(f, 'llamadas', e.currentTarget)} aria-label={`${f.llamadas} llamadas del ${nombre}: ver en el registro`}
-                    className={cn(ENLACE_CIFRA, 'text-foreground')}>{f.llamadas}</button> : <span className="font-semibold">0</span>}
-                </td>
-                <td data-etiqueta="Contacto" className="px-2 text-right">
-                  {f.tasaContacto === null ? <span className="text-sm text-[var(--muted-foreground-strong)]">—</span>
-                    : <button type="button" onClick={(e) => accion(f, 'llamadas', e.currentTarget)} aria-label={`Contacto ${Math.round(f.tasaContacto)} % del ${nombre}: ver las llamadas y su resultado`}
-                      className={cn(ENLACE_CIFRA, 'text-sm font-bold text-foreground')}>{Math.round(f.tasaContacto)} %</button>}
-                  <NivelContacto fila={f} umbrales={umbrales} />
-                </td>
-                <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">
-                  {f.citas > 0 ? <button type="button" onClick={(e) => accion(f, 'citas', e.currentTarget)} aria-label={`${f.citas} citas agendadas del ${nombre}: ver por analista`}
-                    className={cn(ENLACE_CIFRA, 'text-foreground')}>{f.citas}</button> : '0'}
-                </td>
-                <td data-etiqueta="Vencidas" className="px-2 text-right text-sm tabular-nums">
-                  {f.vencidas > 0
-                    ? <button type="button" onClick={(e) => accion(f, 'vencidas', e.currentTarget)} aria-label={`${f.vencidas} tareas vencidas en ${nombre}: ver por analista`}
-                      className={cn(ENLACE_CIFRA, 'text-[var(--destructive-text)]')}>{f.vencidas}</button>
-                    : <span className="text-foreground">0</span>}
-                </td>
-                <td data-etiqueta="Atención" className="py-2 pl-4 pr-2 text-[13px]">
-                  {f.atencion === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">{sinDetalle === 'error' ? '—' : '…'}</span><span className="sr-only">{sinDetalle === 'error' ? 'No disponible' : 'Consultando'}</span></>
-                    : f.atencion === 0 ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin alertas</span></>
-                      : <button type="button" onClick={(e) => accion(f, 'atencion', e.currentTarget)} aria-label={`${f.atencion} ${f.atencion === 1 ? 'analista necesita' : 'analistas necesitan'} atención en ${nombre}: ver quiénes`}
-                        className={cn(ENLACE_CIFRA, 'text-[var(--warning-text)]')}>{f.atencion} {f.atencion === 1 ? 'analista' : 'analistas'}</button>}
-                </td>
-                <td data-etiqueta="Primer intento" className="px-2 text-right text-sm tabular-nums text-foreground">
-                  {f.primerIntento === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Seguimiento no activo</span></> : f.primerIntento}
-                </td>
-                <td data-etiqueta="Dispersión" className="py-2 pl-2 pr-4 text-right">
-                  {f.dispersion.personas > 0 && f.dispersion.minimo !== null && f.dispersion.maximo !== null ? <>
-                    <span className="block text-sm tabular-nums text-foreground">{cifraPulso(Math.round(f.dispersion.minimo))}–{cifraPulso(Math.round(f.dispersion.maximo))} %</span>
-                    <span className="block text-[11.5px] text-[var(--muted-foreground-strong)]">{f.dispersion.personas} con muestra</span>
-                  </> : <span className="text-[11.5px] text-[var(--muted-foreground-strong)]">Sin muestra</span>}
-                </td>
+                <CifrasEquipo f={f} del={delEquipo(f)} en={enEquipo(f)} abrir={abrir} umbrales={umbrales} sinDetalle={sinDetalle} />
               </tr>
             )
           })}
         </tbody>
+        <tfoot className="sticky bottom-0 z-[1] bg-muted">
+          <tr className="[&>*]:border-t [&>*]:border-border">
+            <th scope="row" className="py-0 pl-4 pr-2 text-left font-normal">
+              {/* El nombre va directo en la rejilla: es el rótulo de la fila para el lector. */}
+              <div className="grid min-h-[52px] grid-cols-[auto_minmax(0,1fr)] content-center items-center gap-x-2.5 py-1 text-sm font-extrabold leading-snug text-primary">
+                <span aria-hidden="true" className="row-span-2 grid size-8 place-items-center rounded-full bg-card"><Users className="size-4" /></span>
+                {totalOperacion.nombre}
+                <Integrantes f={totalOperacion} en="en toda la operación" abrir={accionTotal} />
+              </div>
+            </th>
+            <CifrasEquipo f={totalOperacion} del="de toda la operación" en="en toda la operación" abrir={accionTotal} umbrales={umbrales} sinDetalle={sinDetalle} total />
+          </tr>
+        </tfoot>
       </table>
     </div>
   </>
 }
 
+function Integrantes({ f, en, abrir }: { f: FilaEquipoOperacion; en: string; abrir: (tipo: AccionEquipo, origen: HTMLElement) => void }): JSX.Element {
+  return (
+    <p className="text-[11.5px] font-normal text-[var(--muted-foreground-strong)]">
+      {f.analistas} {f.analistas === 1 ? 'analista' : 'analistas'}
+      {f.sinRegistro > 0 && <> · <button type="button" onClick={(e) => abrir('sin_registro', e.currentTarget)}
+        aria-label={`${f.sinRegistro} sin registro ${en}: ver quiénes`} className={ENLACE_CIFRA}>{f.sinRegistro} sin registro</button></>}
+    </p>
+  )
+}
+
+/**
+ * Las siete cifras de una fila: las mismas para cada equipo y para «Toda la
+ * operación». Las de un equipo abren sus analistas; las del total, los equipos.
+ */
+function CifrasEquipo({ f, del, en, abrir, umbrales, sinDetalle, total = false }: {
+  f: FilaEquipoOperacion; del: string; en: string; abrir: (tipo: AccionEquipo, origen: HTMLElement) => void
+  umbrales: v.InferOutput<typeof UmbralesSchema> | null; sinDetalle: 'cargando' | 'error'; total?: boolean
+}): JSX.Element {
+  const ver = total
+    ? { llamadas: 'ver en el registro general', citas: 'ver los equipos ordenados por citas', vencidas: 'ver los equipos con vencidas', atencion: 'ver los equipos con atención' }
+    : { llamadas: 'ver en el registro', citas: 'ver por analista', vencidas: 'ver por analista', atencion: 'ver quiénes' }
+  return <>
+    <td data-etiqueta="Llamadas" className="px-2 text-right text-sm tabular-nums text-foreground">
+      {f.llamadas > 0 ? <button type="button" onClick={(e) => abrir('llamadas', e.currentTarget)} aria-label={`${f.llamadas} llamadas ${del}: ${ver.llamadas}`}
+        className={cn(ENLACE_CIFRA, 'text-foreground')}>{f.llamadas}</button> : <span className="font-semibold">0</span>}
+    </td>
+    <td data-etiqueta="Contacto" className="px-2 text-right">
+      {f.tasaContacto === null ? <span className="text-sm text-[var(--muted-foreground-strong)]">—</span>
+        : <button type="button" onClick={(e) => abrir('llamadas', e.currentTarget)} aria-label={`Contacto ${Math.round(f.tasaContacto)} % ${del}: ver las llamadas y su resultado`}
+          className={cn(ENLACE_CIFRA, 'text-sm font-bold text-foreground')}>{Math.round(f.tasaContacto)} %</button>}
+      <NivelContacto fila={f} umbrales={umbrales} />
+    </td>
+    <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">
+      {f.citas > 0 ? <button type="button" onClick={(e) => abrir('citas', e.currentTarget)} aria-label={`${f.citas} citas agendadas ${del}: ${ver.citas}`}
+        className={cn(ENLACE_CIFRA, 'text-foreground')}>{f.citas}</button> : '0'}
+    </td>
+    <td data-etiqueta="Vencidas" className="px-2 text-right text-sm tabular-nums">
+      {f.vencidas > 0
+        ? <button type="button" onClick={(e) => abrir('vencidas', e.currentTarget)} aria-label={`${f.vencidas} tareas vencidas ${en}: ${ver.vencidas}`}
+          className={cn(ENLACE_CIFRA, 'text-[var(--destructive-text)]')}>{f.vencidas}</button>
+        : <span className="text-foreground">0</span>}
+    </td>
+    <td data-etiqueta="Atención" className="py-2 pl-4 pr-2 text-[13px]">
+      {f.atencion === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">{sinDetalle === 'error' ? '—' : '…'}</span><span className="sr-only">{sinDetalle === 'error' ? 'No disponible' : 'Consultando'}</span></>
+        : f.atencion === 0 ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin alertas</span></>
+          : <button type="button" onClick={(e) => abrir('atencion', e.currentTarget)} aria-label={`${f.atencion} ${f.atencion === 1 ? 'analista necesita' : 'analistas necesitan'} atención ${en}: ${ver.atencion}`}
+            className={cn(ENLACE_CIFRA, 'text-[var(--warning-text)]')}>{f.atencion} {f.atencion === 1 ? 'analista' : 'analistas'}</button>}
+    </td>
+    <td data-etiqueta="Primer intento" className="px-2 text-right text-sm tabular-nums text-foreground">
+      {f.primerIntento === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Seguimiento no activo</span></> : f.primerIntento}
+    </td>
+    <td data-etiqueta="Dispersión" className="py-2 pl-2 pr-4 text-right">
+      {f.dispersion.personas > 0 && f.dispersion.minimo !== null && f.dispersion.maximo !== null ? <>
+        <span className="block text-sm tabular-nums text-foreground">{cifraPulso(Math.round(f.dispersion.minimo))}–{cifraPulso(Math.round(f.dispersion.maximo))} %</span>
+        <span className="block text-[11.5px] text-[var(--muted-foreground-strong)]">{f.dispersion.personas} con muestra</span>
+      </> : <span className="text-[11.5px] text-[var(--muted-foreground-strong)]">Sin muestra</span>}
+    </td>
+  </>
+}
+
 /** El nivel con los umbrales del servidor; sin muestra suficiente se dice con útiles y mínimo. */
 function NivelContacto({ fila, umbrales }: { fila: FilaEquipoOperacion; umbrales: v.InferOutput<typeof UmbralesSchema> | null }): JSX.Element | null {
   const nivel = nivelEquipo(fila, umbrales)
@@ -157,4 +212,3 @@ function NivelContacto({ fila, umbrales }: { fila: FilaEquipoOperacion; umbrales
   if (nivel.estado === 'sin_muestra') return <span className="block text-[11.5px] text-[var(--muted-foreground-strong)]">Sin muestra<span className="sr-only">: {nivel.utiles} de {nivel.minimo} llamadas útiles necesarias</span></span>
   return <span className="block text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{fila.contestadas}/{fila.utiles} útiles</span>
 }
-
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
index 6b590b5d..55481b4b 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/vista-equipo-gerencia.tsx
@@ -59,6 +59,7 @@ export function VistaEquipoGerencia({ equipo, filas, error, cargando, enVuelo, r
   const propia = useRef(false)
   const apertura = useRef(0)
   const autoInhibida = useRef(false)
+  const focoPendiente = useRef<string | null | undefined>(undefined)
   const [local, setLocal] = useState<SeleccionSupervisor | null>(null)
   const [estrecho, setEstrecho] = useState(false)
   const [ampliado, setAmpliado] = useState(false)
@@ -133,9 +134,17 @@ export function VistaEquipoGerencia({ equipo, filas, error, cargando, enVuelo, r
     autoInhibida.current = true
     setAmpliado(false)
     setLocal(null)
-    if (analistaRuta) window.location.hash = rutaEquipo(equipo.clave)
-    devolverFoco(analista)
+    // Con una persona en la ruta, la ventana sigue abierta hasta que llega el cambio de ruta:
+    // devolver el foco antes lo rechaza su trampa y cae en el body (E2E, 27/09).
+    if (analistaRuta) { focoPendiente.current = analista; window.location.hash = rutaEquipo(equipo.clave) }
+    else devolverFoco(analista)
   }
+  useLayoutEffect(() => {
+    if (analistaRuta || focoPendiente.current === undefined) return
+    const analista = focoPendiente.current
+    focoPendiente.current = undefined
+    devolverFoco(analista)
+  })
   const abrirRegistroEquipo = (control: HTMLElement) => {
     origen.current = control
     if (analistaRuta) window.location.hash = rutaEquipo(equipo.clave)
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.test.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.test.ts
index ac88e41c..65452f9c 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.test.ts
@@ -7,14 +7,14 @@ import fixture from './gestion-diaria-f5.test.fixture.json'
 import { PulsoGerenciaSchema } from './gestion-diaria-pulso'
 import { DiaEquipoSchema, presentarEquipo } from './gestion-diaria-equipo'
 import {
-  atencionEquipo, barrasEquipo, filasOperacion, filtrarOrdenarOperacion, nivelEquipo, personasSinRegistro, referenciaCifra,
+  atencionEquipo, barrasEquipo, filasOperacion, filtrarOrdenarOperacion, nivelEquipo, personasSinRegistro, totalOperacion,
   type FiltrosOperacion, type OrdenOperacion,
 } from './gestion-diaria-operacion'
 
 const pulso = v.parse(PulsoGerenciaSchema, fixture.pulso)
 const detalle = presentarEquipo(v.parse(DiaEquipoSchema, fixture.equipo))
 const equipo = (nombre: string) => pulso.equipos.find((e) => e.nombre === nombre)!
-const BASE: FiltrosOperacion = { busqueda: '', conAtencion: false, orden: 'atencion', ascendente: false }
+const BASE: FiltrosOperacion = { busqueda: '', estado: 'todos', orden: 'atencion', ascendente: false }
 
 describe('filasOperacion', () => {
   it('una fila por equipo con las cifras autoritativas del pulso, «fuera» incluido', () => {
@@ -41,13 +41,16 @@ describe('filtrarOrdenarOperacion', () => {
       for (const ascendente of [true, false]) expect(filtrarOrdenarOperacion(filas, { ...BASE, orden, ascendente }).at(-1)?.fuera).toBe(true)
     }
   })
-  it('sin dato al final, búsqueda sin tildes y «Con atención»', () => {
+  it('sin dato al final, búsqueda sin tildes y las pastillas «Con atención» y «Con vencidas»', () => {
     const filas = filasOperacion(pulso, detalle)
     const porContacto = filtrarOrdenarOperacion(filas, { ...BASE, orden: 'contacto', ascendente: true }).filter((f) => !f.fuera)
     const primeroSinDato = porContacto.findIndex((f) => f.tasaContacto === null)
     if (primeroSinDato >= 0) expect(porContacto.slice(primeroSinDato).every((f) => f.tasaContacto === null)).toBe(true)
     expect(filtrarOrdenarOperacion(filas, { ...BASE, busqueda: 'anidádo' }).map((f) => f.nombre)).toEqual(['SUPERVISOR ANIDADO'])
-    expect(filtrarOrdenarOperacion(filas, { ...BASE, conAtencion: true }).every((f) => (f.atencion ?? 0) > 0)).toBe(true)
+    expect(filtrarOrdenarOperacion(filas, { ...BASE, estado: 'atencion' }).every((f) => (f.atencion ?? 0) > 0)).toBe(true)
+    const conVencidas = filtrarOrdenarOperacion(filas, { ...BASE, estado: 'vencidas' })
+    expect(conVencidas.length).toBe(filas.filter((f) => f.vencidas > 0).length)
+    expect(conVencidas.every((f) => f.vencidas > 0)).toBe(true)
   })
 })
 
@@ -78,11 +81,17 @@ describe('atencionEquipo y barrasEquipo', () => {
   })
 })
 
-describe('referenciaCifra', () => {
-  it('«Ayer» hoy, «Día anterior» en un día pasado y las jornadas de la referencia', () => {
-    expect(referenciaCifra(pulso, 'llamadas', true)).toMatch(/^Ayer \d+ · Referencia \d+ \(7 jornadas\)$/)
-    expect(referenciaCifra(pulso, 'llamadas', false)).toMatch(/^Día anterior \d+ · /)
-    expect(referenciaCifra({ ...pulso, referencia: { ...pulso.referencia, cantidad: 0 } }, 'llamadas', true)).toMatch(/ · Sin referencia$/)
+describe('totalOperacion', () => {
+  it('«Toda la operación» suma lo mismo que el pulso y la atención de los equipos', () => {
+    const filas = filasOperacion(pulso, detalle)
+    const total = totalOperacion(pulso, filas)
+    expect(total).toMatchObject({ clave: 'total', llamadas: pulso.actual.llamadas, utiles: pulso.actual.utiles, tasaContacto: pulso.actual.tasa_contacto,
+      citas: pulso.actual.citas_agendadas, vencidas: pulso.vencidas_global, analistas: pulso.actual.analistas_activos, sinRegistro: pulso.actual.sin_actividad })
+    expect(total.atencion).toBe(filas.reduce((n, f) => n + (f.atencion ?? 0), 0))
+    const conMuestra = pulso.equipos.filter((e) => e.dispersion.personas > 0)
+    if (conMuestra.length) expect(total.dispersion.minimo).toBe(Math.min(...conMuestra.map((e) => e.dispersion.minimo!)))
+    // Sin detalle, la atención de la operación es desconocida, no cero.
+    expect(totalOperacion(pulso, filasOperacion(pulso, null)).atencion).toBeNull()
   })
 })
 
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.ts
index 5fa2419c..feecbc19 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-operacion.ts
@@ -4,7 +4,7 @@
 // lo que el pulso no trae —quién necesita atención y las barras por hora— y se
 // restringe a las personas ACTIVAS que el pulso confirma en cada equipo
 // (revisión Codex del plan, 27/09).
-import { cifraPulso, type EquipoPulso, type MetricasPulso, type PulsoGerencia } from './gestion-diaria-pulso'
+import type { EquipoPulso, PulsoGerencia } from './gestion-diaria-pulso'
 import { compararGravedad, horarioConfirmado, type FilaEquipoPresentada, type FiltrosEquipo } from './gestion-diaria-equipo'
 import type { Marcador, UmbralesSchema } from './gestion-diaria-analista'
 import type * as v from 'valibot'
@@ -47,7 +47,9 @@ export function filasOperacion(pulso: PulsoGerencia, detalle: readonly FilaEquip
 
 export type OrdenOperacion = 'nombre' | 'llamadas' | 'contacto' | 'citas' | 'vencidas' | 'atencion' | 'primer_intento' | 'dispersion'
 
-export interface FiltrosOperacion { busqueda: string; conAtencion: boolean; orden: OrdenOperacion; ascendente: boolean }
+/** Las pastillas de la tabla de equipos, como las del supervisor (Miguel, 27/09): la cifra ES el filtro. */
+export type EstadoOperacion = 'todos' | 'atencion' | 'vencidas'
+export interface FiltrosOperacion { busqueda: string; estado: EstadoOperacion; orden: OrdenOperacion; ascendente: boolean }
 
 const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLocaleLowerCase('es').trim()
 const amplitud = (f: FilaEquipoOperacion) => f.dispersion.minimo === null || f.dispersion.maximo === null ? null : f.dispersion.maximo - f.dispersion.minimo
@@ -68,9 +70,12 @@ function valorDe(f: FilaEquipoOperacion, orden: Exclude<OrdenOperacion, 'nombre'
 export const equipoConAtencion = (f: FilaEquipoOperacion) =>
   f.atencion !== null ? f.atencion > 0 : f.vencidas > 0 || f.sinRegistro > 0 || (f.primerIntento ?? 0) > 0
 
+export const cumpleEstado = (f: FilaEquipoOperacion, estado: EstadoOperacion) =>
+  estado === 'todos' || (estado === 'atencion' ? equipoConAtencion(f) : f.vencidas > 0)
+
 export function filtrarOrdenarOperacion(filas: readonly FilaEquipoOperacion[], filtros: FiltrosOperacion): FilaEquipoOperacion[] {
   const q = normalizar(filtros.busqueda)
-  return filas.filter((f) => normalizar(f.nombre).includes(q) && (!filtros.conAtencion || equipoConAtencion(f)))
+  return filas.filter((f) => normalizar(f.nombre).includes(q) && cumpleEstado(f, filtros.estado))
     .toSorted((a, b) => {
       // «Fuera de equipos» no compite con los equipos: siempre al final.
       if (a.fuera !== b.fuera) return a.fuera ? 1 : -1
@@ -86,6 +91,31 @@ export function filtrarOrdenarOperacion(filas: readonly FilaEquipoOperacion[], f
     })
 }
 
+/**
+ * La fila «Toda la operación» al pie de la tabla (Miguel, 27/09: como el
+ * supervisor, sin franja de cifras aparte): las cifras autoritativas del pulso,
+ * la atención sumada por equipo (cada analista está en un solo equipo) y la
+ * dispersión entre los extremos individuales de toda la operación.
+ */
+export function totalOperacion(pulso: PulsoGerencia, filas: readonly FilaEquipoOperacion[]): FilaEquipoOperacion {
+  const a = pulso.actual
+  const conMuestra = pulso.equipos.filter((e) => e.dispersion.personas > 0)
+  const primeros = pulso.equipos.flatMap((e) => e.primer_intento_vencido === null ? [] : [e.primer_intento_vencido])
+  return {
+    clave: 'total', nombre: 'Toda la operación', fuera: false,
+    analistas: a.analistas_activos, sinRegistro: a.sin_actividad,
+    llamadas: a.llamadas, contestadas: a.contestadas, utiles: a.utiles, tasaContacto: a.tasa_contacto,
+    citas: a.citas_agendadas, vencidas: pulso.vencidas_global,
+    primerIntento: primeros.length ? primeros.reduce((n, x) => n + x, 0) : null,
+    dispersion: conMuestra.length === 0 ? { personas: 0, minimo: null, maximo: null } : {
+      personas: conMuestra.reduce((n, e) => n + e.dispersion.personas, 0),
+      minimo: Math.min(...conMuestra.map((e) => e.dispersion.minimo!)),
+      maximo: Math.max(...conMuestra.map((e) => e.dispersion.maximo!)),
+    },
+    atencion: filas.some((f) => f.atencion === null) ? null : filas.reduce((n, f) => n + (f.atencion ?? 0), 0),
+  }
+}
+
 export interface PersonaSinRegistro { analista_id: string; nombre: string; equipo: string; clave: string }
 
 /** Activos sin ninguna gestión en el día (la misma regla que `sin_actividad` del pulso). */
@@ -127,21 +157,11 @@ export function barrasEquipo(detalle: readonly FilaEquipoPresentada[], equipo: E
   return { porHora: [...porHora.values()].toSorted((a, b) => a.hora - b.hora), analistas: filas.length, otros }
 }
 
-/**
- * «Ayer 92 · Referencia 88 (7 jornadas)». En un día pasado dice «Día anterior»;
- * la referencia son hasta 7 jornadas CON actividad, no 7 días calendario (Codex).
- */
-export function referenciaCifra(pulso: PulsoGerencia, campo: keyof MetricasPulso, esHoy: boolean, porcentaje = false): string {
-  // Promedios y tasas a entero, como el diseño («7 días 88»): la cifra exacta vive en «Comparar días».
-  const cifra = (n: number | null) => cifraPulso(n === null ? null : Math.round(n), porcentaje)
-  const anterior = `${esHoy ? 'Ayer' : 'Día anterior'} ${cifra(pulso.ayer.metricas[campo])}`
-  const n = pulso.referencia.cantidad
-  return n === 0 ? `${anterior} · Sin referencia`
-    : `${anterior} · Referencia ${cifra(pulso.referencia.media[campo])} (${n} ${n === 1 ? 'jornada' : 'jornadas'})`
-}
-
 /** «Equipo de SUPERVISOR UNO»; el grupo sin supervisor conserva su nombre. */
 export const nombreEquipo = (f: { fuera: boolean; nombre: string }) => f.fuera ? f.nombre : `Equipo de ${f.nombre}`
+/** «del Equipo de X» / «del grupo Fuera de equipos comerciales»: «del Fuera de…» no se dice (E2E, 27/09). */
+export const delEquipo = (f: { fuera: boolean; nombre: string }) => f.fuera ? `del grupo ${f.nombre}` : `del Equipo de ${f.nombre}`
+export const enEquipo = (f: { fuera: boolean; nombre: string }) => f.fuera ? `en el grupo ${f.nombre}` : `en el Equipo de ${f.nombre}`
 
 /** A dónde lleva un número del equipo: sus analistas con ese filtro u orden. */
 export type PresetEquipo = 'sin_registro' | 'vencidas' | 'atencion' | 'citas'
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia-demo.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia-demo.test.tsx
index 77b9e9c3..652e4714 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia-demo.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia-demo.test.tsx
@@ -38,11 +38,11 @@ describe('Gerencia en modo demo (G0)', () => {
     montar()
     const vista = screen.getByRole('region', { name: 'Toda la operación hoy' })
     expect(screen.queryByText(/requiere una sesión de gerencia/)).not.toBeInTheDocument()
-    expect(within(vista).getByRole('region', { name: 'Cifras de la operación' })).toBeInTheDocument()
+    expect(within(vista).getByRole('rowheader', { name: /^Toda la operación/ })).toBeInTheDocument()
     for (const equipo of ['Equipo de SUPERVISOR UNO', 'Equipo de SUPERVISOR DOS', 'Fuera de equipos comerciales']) {
       expect(within(vista).getByRole('button', { name: `Seleccionar ${equipo}` })).toBeInTheDocument()
     }
-    expect(vista).toHaveTextContent('1 tareas vencidas')
+    expect(within(vista).getByRole('button', { name: '1 tareas vencidas en toda la operación: ver los equipos con vencidas' })).toBeInTheDocument()
     expect(d.rpc).not.toHaveBeenCalled()
   })
   it('abre un equipo por URL con sus analistas del detalle demo, y el registro recibe sus ids', () => {
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.css b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.css
index 979b151b..f54ba8cf 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.css
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.css
@@ -22,7 +22,9 @@
 .gp-referencia>div { display:flex; flex-shrink:0; }
 .gd-cortes.gp-pendientes { display:block; padding:10px 12px; color:var(--muted-foreground-strong); }
 .gp-pendientes strong { color:var(--danger-text); font-weight:600; }
-.gd-pulso .gp-espacio { grid-template-columns:minmax(0,1fr) clamp(360px,30%,414px); }
+/* Sin depender de la raíz vieja `.gd-pulso` (E2E, 27/09): entre 1040 y 1235 px la regla de
+ * una columna del supervisor apilaba la ficha de Hábitos debajo de la tabla. */
+.gp-espacio.gd-espacio { grid-template-columns:minmax(0,1fr) clamp(360px,30%,414px); }
 /* En gerencia el ancho de la pantalla decide la composición; la tabla conserva
  * sus columnas y su propio desplazamiento aunque el panel reduzca su ancho. */
 .gp-espacio>.gd-equipo { container-type:normal; }
@@ -81,7 +83,7 @@
 .gp-registro [role=tablist] { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); width:100%; }
 .gp-registro [role=tablist]>button { min-width:0; padding-inline:8px; }
 .gp-registro [role=tabpanel] { display:block; }
-.gd-pulso :is(a,button,input,select,summary,[tabindex]):focus-visible,.gp-detalle :is(a,button,input,select,summary,[tabindex]):focus-visible,.gp-definiciones :is(a,button,[tabindex]):focus-visible { outline:2px solid var(--accent); outline-offset:-2px; border-radius:4px; }
+:is(.gp-periodo,.gp-habitos-contexto,.gp-espacio) :is(a,button,input,select,summary,[tabindex]):focus-visible,.gp-detalle :is(a,button,input,select,summary,[tabindex]):focus-visible,.gp-definiciones :is(a,button,[tabindex]):focus-visible { outline:2px solid var(--accent); outline-offset:-2px; border-radius:4px; }
 @container (min-width:840px) {
   .gp-espacio .gd-tabla,.gp-espacio .gp-tabla { min-width:840px; }
   .gp-espacio .gd-tabla tr,.gp-espacio .gp-tabla tr { background:var(--card); }
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
index 8e80a172..cdcd9b43 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
@@ -27,14 +27,19 @@ beforeEach(() => {
   pulso = estado(v.parse(PulsoGerenciaSchema, fixture.pulso)); habitos = estado(v.parse(HabitosGerenciaSchema, fixture.habitos)); detalle = estado(v.parse(DiaEquipoSchema, fixture.equipo))
   pedidos.length = 0; periodos.length = 0; recargar.mockClear()
 })
+const filaTotal = () => within(screen.getByRole('table', { name: 'Equipos de la operación' })).getByRole('rowheader', { name: /^Toda la operación/ }).closest('tr')!
 const ruta = (hash: string) => act(() => { history.replaceState(null, '', hash); window.dispatchEvent(new HashChangeEvent('hashchange')) })
 describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos F5/F6', () => {
-  it('cuatro cifras finas con ayer y referencia, pendientes actuales y el grupo sin equipo al final', () => {
+  it('como el supervisor: pastillas que filtran, «Toda la operación» al pie y el grupo sin equipo al final', () => {
     render(<GestionDiariaGerencia />)
-    const cifras = screen.getByRole('region', { name: 'Cifras de la operación' })
-    expect(within(cifras).getAllByRole('term').map((n) => n.textContent)).toEqual(['Llamadas', 'Contacto', 'Citas agendadas', 'Sin registro'])
-    expect(within(cifras).getAllByText(/^Ayer (\d+|—) · Referencia [\d—][^()]* \(\d+ jornadas?\)$/, { selector: 'dd' })).toHaveLength(4)
-    expect(screen.getByRole('region', { name: 'Toda la operación hoy' })).toHaveTextContent('1008 tareas vencidas')
+    expect(screen.queryByRole('region', { name: 'Cifras de la operación' })).not.toBeInTheDocument()
+    const equipos = pulso.datos!.equipos
+    const pastillas = within(screen.getByRole('group', { name: 'Resumen de la operación' })).getAllByRole('button')
+    expect(pastillas.map((b) => b.textContent)).toEqual([`Todos ${equipos.length}`, expect.stringMatching(/^Con atención \d+$/), `Con vencidas ${equipos.filter((e) => e.tareas_vencidas > 0).length}`])
+    expect(pastillas[0]).toHaveAttribute('aria-pressed', 'true')
+    const total = filaTotal()
+    expect(within(total).getByRole('button', { name: '9 llamadas de toda la operación: ver en el registro general' })).toBeInTheDocument()
+    expect(within(total).getByRole('button', { name: '1008 tareas vencidas en toda la operación: ver los equipos con vencidas' })).toBeInTheDocument()
     const filas = within(screen.getByRole('table', { name: 'Equipos de la operación' })).getAllByRole('button', { name: /^Seleccionar / })
     expect(filas.at(-1)).toHaveAccessibleName('Seleccionar Fuera de equipos comerciales')
   })
@@ -52,9 +57,10 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
   it('cero actividad conserva los pendientes y presenta las tasas sin denominador como no disponibles', () => {
     pulso = { ...pulso, datos: { ...pulso.datos!, actual: { ...pulso.datos!.ayer.metricas } } }
     render(<GestionDiariaGerencia />)
-    const cifras = screen.getByRole('region', { name: 'Cifras de la operación' })
-    expect(within(cifras).getAllByRole('button').map((n) => n.textContent)).toEqual(['0', '—', '0', '5 de 5'])
-    expect(screen.getByRole('region', { name: 'Toda la operación hoy' })).toHaveTextContent('1008 tareas vencidas')
+    const total = filaTotal()
+    expect(within(total).getAllByRole('cell').map((n) => n.textContent).slice(0, 3)).toEqual(['0', expect.stringMatching(/^—/), '0'])
+    expect(within(total).getByRole('button', { name: '5 sin registro en toda la operación: ver quiénes' })).toBeInTheDocument()
+    expect(within(total).getByRole('button', { name: /^1008 tareas vencidas/ })).toBeInTheDocument()
     fireEvent.click(screen.getByRole('button', { name: 'Comparar días' }))
     expect(screen.getByRole('table', { name: 'Cifras del día, anterior y referencia' })).toHaveTextContent('Tasa de contacto——0 %')
   })
@@ -153,12 +159,12 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
   })
   it('filtrar equipos no recalcula las cifras globales ni confunde falta de resultados con cero actividad', () => {
     render(<GestionDiariaGerencia />)
-    const cifras = screen.getByRole('region', { name: 'Cifras de la operación' })
-    const valores = within(cifras).getAllByRole('button').map((n) => n.textContent)
-    expect(valores).toEqual(['9', '63 %', '3', '2 de 5'])
+    const valores = within(filaTotal()).getAllByRole('button').map((n) => n.textContent)
+    expect(valores.slice(0, 4)).toEqual(['2 sin registro', '9', '63 %', '3'])
     fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar equipo' }), { target: { value: 'NO EXISTE' } })
     expect(screen.getByRole('table', { name: 'Equipos de la operación' })).toHaveTextContent('Ningún equipo coincide con estos filtros')
-    expect(within(cifras).getAllByRole('button').map((n) => n.textContent)).toEqual(valores)
+    expect(screen.getByText(`0 de ${pulso.datos!.equipos.length} equipos`)).toBeInTheDocument()
+    expect(within(filaTotal()).getAllByRole('button').map((n) => n.textContent)).toEqual(valores)
   })
   it('carga y cambio de cuenta retiran el registro y los filtros de la identidad anterior', () => {
     const { rerender } = render(<GestionDiariaGerencia />)
@@ -188,7 +194,7 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
     pulso = { ...pulso, datos: null!, error: new CrmApiError('Revocado', '42501') }; rerender(<GestionDiariaGerencia />)
     expect(screen.queryByRole('table')).not.toBeInTheDocument()
     expect(screen.getByRole('alert')).toHaveTextContent('ya no tiene permiso')
-    pulso = previa; fireEvent.click(screen.getByRole('tab', { name: 'Pulso diario' }))
+    pulso = previa; fireEvent.click(screen.getByRole('tab', { name: 'Actividad del día' }))
     fireEvent.change(screen.getByLabelText('Día de la operación'), { target: { value: '2026-09-22' } })
     fireEvent.keyDown(screen.getByLabelText('Día de la operación'), { key: 'Enter' })
     expect(screen.queryByRole('table')).not.toBeInTheDocument()
@@ -206,17 +212,21 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
     expect(screen.getByRole('alert')).toHaveTextContent('ya no tiene permiso')
     expect(screen.queryByRole('table')).not.toBeInTheDocument()
   })
-  it('cada cifra abre su lista exacta: llamadas en el registro, sin registro con nombres, citas ordenando equipos', () => {
+  it('cada cifra de «Toda la operación» abre su lista exacta: registro, nombres, equipos ordenados o filtrados', () => {
     render(<GestionDiariaGerencia />)
-    const cifras = screen.getByRole('region', { name: 'Cifras de la operación' })
-    fireEvent.click(within(cifras).getByRole('button', { name: /^Llamadas: 9\./ }))
+    fireEvent.click(within(filaTotal()).getByRole('button', { name: /^9 llamadas de toda la operación/ }))
     expect(screen.getByTestId('registro')).toHaveTextContent(':null:llamadas')
     expect(screen.getByRole('heading', { level: 3, name: 'Registro general' })).toHaveFocus()
-    fireEvent.click(within(cifras).getByRole('button', { name: /^Sin registro: 2 de 5\./ }))
+    fireEvent.click(within(filaTotal()).getByRole('button', { name: '2 sin registro en toda la operación: ver quiénes' }))
     const lista = screen.getByRole('list', { name: 'Analistas sin registro' })
     expect(within(lista).getAllByRole('button').map((b) => b.textContent)).toEqual([expect.stringContaining('ANALISTA ANIDADO'), expect.stringContaining('ANALISTA CUATRO')])
-    fireEvent.click(within(cifras).getByRole('button', { name: /^Citas agendadas: 3\./ }))
+    fireEvent.click(within(filaTotal()).getByRole('button', { name: /^3 citas agendadas de toda la operación/ }))
     expect(screen.getByRole('button', { name: 'Ordenar equipos por citas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
+    fireEvent.click(within(filaTotal()).getByRole('button', { name: /^1008 tareas vencidas en toda la operación/ }))
+    expect(screen.getByRole('button', { name: /^Con vencidas/ })).toHaveAttribute('aria-pressed', 'true')
+    expect(screen.getByRole('button', { name: 'Ordenar equipos por vencidas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
+    const equipos = within(screen.getByRole('table', { name: 'Equipos de la operación' })).getAllByRole('button', { name: /^Seleccionar / })
+    expect(equipos).toHaveLength(pulso.datos!.equipos.filter((e) => e.tareas_vencidas > 0).length)
   })
   it('la ficha del equipo que más atención necesita se abre sola, sin mover el foco, y cerrarla la apaga', () => {
     const { rerender } = render(<GestionDiariaGerencia />)
@@ -230,7 +240,7 @@ describe('Gerencia con el diseño de Gestión Diaria (27/09) sobre los contratos
   })
   it('los números de un equipo abren sus analistas con ese filtro u orden', () => {
     render(<GestionDiariaGerencia />)
-    fireEvent.click(screen.getByRole('button', { name: '1 sin registro en Equipo de SUPERVISOR DOS: ver quiénes' }))
+    fireEvent.click(screen.getByRole('button', { name: '1 sin registro en el Equipo de SUPERVISOR DOS: ver quiénes' }))
     const equipo = screen.getByRole('region', { name: 'Equipo de SUPERVISOR DOS' })
     expect(within(equipo).getByRole('button', { name: /^Sin registro/ })).toHaveAttribute('aria-pressed', 'true')
     expect(within(equipo).getAllByRole('button', { name: /^Seleccionar a / }).map((b) => b.textContent)).toEqual(['ANALISTA CUATRO'])
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
index 7391ff7f..ec150efa 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
@@ -11,14 +11,13 @@ import { fechaLima } from '@/lib/agenda-derivada'
 import { horaLimaDe } from '@/lib/gestion-diaria-analista'
 import { cifraPulso, diaPulsoValido, desplazarDia, type MetricasPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
 import { presentarEquipo, type FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
-import { equipoConAtencion, filasOperacion, filtrarOrdenarOperacion, filtrosDePreset, type FiltrosOperacion, type OrdenOperacion, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
+import { equipoConAtencion, filasOperacion, filtrarOrdenarOperacion, filtrosDePreset, totalOperacion, type FiltrosOperacion, type OrdenOperacion, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
 import { hashDe, leerHash } from '@/lib/router'
 import { CrmApiError } from '@/data/crm-api'
 import { usePulsoGerencia, useHabitosGerencia, useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
 import { ErrorConsultaGerencia } from '@/components/gestion-diaria/error-consulta-gerencia'
 import { ReporteHabitos } from '@/components/gestion-diaria/reporte-habitos'
-import { CifrasOperacion, type DestinoCifra } from '@/components/gestion-diaria/cifras-operacion'
-import { TablaEquiposGerencia } from '@/components/gestion-diaria/tabla-equipos-gerencia'
+import { TablaEquiposGerencia, type AccionEquipo } from '@/components/gestion-diaria/tabla-equipos-gerencia'
 import { PanelOperacionGerencia, type VistaOperacion } from '@/components/gestion-diaria/panel-operacion-gerencia'
 import { PanelSupervisorAdaptable } from '@/components/gestion-diaria/panel-supervisor-adaptable'
 import { VistaEquipoGerencia } from '@/components/gestion-diaria/vista-equipo-gerencia'
@@ -41,7 +40,8 @@ const METRICAS: { campo: keyof MetricasPulso; titulo: string; porcentaje?: boole
   { campo: 'sin_actividad', titulo: 'Analistas sin actividad' }, { campo: 'leads_unicos', titulo: 'Leads distintos' },
   { campo: 'llamadas_por_lead', titulo: 'Llamadas por lead' }, { campo: 'citas_agendadas', titulo: 'Citas agendadas' },
 ]
-const PESTANAS = [{ valor: 'pulso', etiqueta: 'Pulso diario' }, { valor: 'habitos', etiqueta: 'Hábitos del equipo' }] as const
+// «Pulso diario» era jerga (Miguel, 27/09): la pestaña dice lo que muestra.
+const PESTANAS = [{ valor: 'pulso', etiqueta: 'Actividad del día' }, { valor: 'habitos', etiqueta: 'Hábitos del equipo' }] as const
 const SIN_PERMISO = new CrmApiError('Permiso de gerencia revocado', '42501')
 const suscribirRuta = (cambio: () => void) => { window.addEventListener('hashchange', cambio); return () => window.removeEventListener('hashchange', cambio) }
 const fotoRuta = () => window.location.hash
@@ -66,7 +66,7 @@ export function GestionDiariaGerencia({ accesoSeguimiento }: { accesoSeguimiento
  * de la tabla. Por debajo, la ficha se abre encima.
  */
 const ANCHO_EN_LINEA = 1040
-const FILTROS_OPERACION: FiltrosOperacion = { busqueda: '', conAtencion: false, orden: 'atencion', ascendente: false }
+const FILTROS_OPERACION: FiltrosOperacion = { busqueda: '', estado: 'todos', orden: 'atencion', ascendente: false }
 const FECHA_LARGA = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' })
 const FECHA_CORTE = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })
 const rutaDe = (tipo: 'equipo' | 'analista', id: string) => hashDe('gestion-diaria', null, undefined, undefined, { tipo, id })
@@ -123,7 +123,8 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
   const filasDetalle = useMemo(() => detalle.datos ? presentarEquipo(detalle.datos) : null, [detalle.datos])
   const filasOp = useMemo(() => datos ? filasOperacion(datos, filasDetalle) : [], [datos, filasDetalle])
   const mostradas = filtrarOrdenarOperacion(filasOp, filtros)
-  const conAtencion = filasDetalle ? filasOp.filter(equipoConAtencion).length : null
+  const conteos = { atencion: filasDetalle ? filasOp.filter(equipoConAtencion).length : null, vencidas: filasOp.filter((f) => f.vencidas > 0).length }
+  const total = useMemo(() => datos ? totalOperacion(datos, filasOp) : null, [datos, filasOp])
   const grupo = datos && ruta ? datos.equipos.find((e) => ruta.tipo === 'equipo' ? e.clave === ruta.id : e.personas.some((p) => p.analista_id === ruta.id)) : undefined
   const automatica = ficha?.origen === 'automatica'
   const modal = ficha !== null && !automatica && (estrecho || ampliado)
@@ -184,6 +185,8 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
   }
   const entrarEquipo = (clave: string, preset?: PresetEquipo) => {
     if (preset) setFiltrosPorEquipo((p) => ({ ...p, [clave]: filtrosDePreset(preset) }))
+    // En pantalla estrecha la ficha es una ventana: volver con la miga no debe reabrirla (E2E, 27/09).
+    if (estrecho) setFicha(null)
     setAmpliado(false)
     window.location.hash = rutaDe('equipo', clave)
   }
@@ -196,12 +199,17 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
       ;(fila ?? titulo.current)?.focus({ preventScroll: true })
     })
   }
-  const abrirCifra = (destino: DestinoCifra, control: HTMLElement) => {
-    if (destino === 'citas') {
-      setFiltros((f) => ({ ...f, busqueda: '', conAtencion: false, orden: 'citas', ascendente: false }))
-      setAnuncio('Equipos ordenados por citas agendadas, de más a menos.')
-    } else if (destino === 'sin_registro') abrirFicha({ tipo: 'sin_registro' }, control, true)
-    else abrirRegistroGeneral(control, 'llamadas')
+  // Las cifras de «Toda la operación» (pie de la tabla) abren su lista exacta:
+  // llamadas en el registro general, sin registro con nombres y el resto
+  // filtrando u ordenando los equipos (revisión Codex del plan).
+  const accionTotal = (tipo: AccionEquipo, control: HTMLElement) => {
+    if (tipo === 'llamadas') abrirRegistroGeneral(control, 'llamadas')
+    else if (tipo === 'sin_registro') abrirFicha({ tipo: 'sin_registro' }, control, true)
+    else {
+      setFiltros((f) => ({ ...f, busqueda: '', estado: tipo === 'citas' ? 'todos' : tipo, orden: tipo, ascendente: false }))
+      setAnuncio(tipo === 'citas' ? 'Equipos ordenados por citas agendadas, de más a menos.'
+        : tipo === 'vencidas' ? 'Equipos con tareas vencidas, de más a menos.' : 'Equipos con analistas que necesitan atención, de más a menos.')
+    }
   }
   const ordenar = (orden: OrdenOperacion) => {
     setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : orden === 'nombre' }))
@@ -213,7 +221,7 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
   if (error) contenido = <ErrorConsultaGerencia error={error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} />
   else if (consulta.cargando) contenido = <PanelCargando filas={6} />
   else if (activa === 'habitos') contenido = habitos.datos && <>
-    <div className="gp-periodo"><label htmlFor={`${id}-periodo`}>Período hasta {dia}</label><Select id={`${id}-periodo`} className={cn(CONTROL, 'min-h-0 w-auto')} value={dias} onChange={(e) => setDias(Number(e.target.value) as 7 | 14 | 30)}>{[7, 14, 30].map((n) => <option key={n} value={n}>{n} días calendario</option>)}</Select></div>
+    <div className="gp-periodo"><label htmlFor={`${id}-periodo`}>Período hasta {dia}</label><Select id={`${id}-periodo`} className={cn(CONTROL, 'min-h-0')} value={dias} onChange={(e) => setDias(Number(e.target.value) as 7 | 14 | 30)}>{[7, 14, 30].map((n) => <option key={n} value={n}>{n} días calendario</option>)}</Select></div>
     <ReporteHabitos key={`${dia}:${dias}`} datos={habitos.datos} equipos={datos?.equipos ?? []} estrecho={estrecho} alAbrirAnalista={() => setPestana('pulso')} />
   </>
   else if (!datos) contenido = null
@@ -228,26 +236,24 @@ function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy:
   } else if (ruta) contenido = <p role="status" className="rounded-2xl border border-border bg-card p-6 text-[13.5px]">Este equipo o autor ya no aparece en el ámbito actual.{' '}
     <button type="button" className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)} onClick={() => volverOperacion()}>Volver a toda la operación</button></p>
   else contenido = <>
-    <CifrasOperacion pulso={datos} esHoy={esHoy} abrir={abrirCifra} />
     <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
       <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
         {detalle.error && !sinPermiso && <div role="alert" className="flex shrink-0 flex-wrap items-center justify-between gap-2 border-b border-border bg-muted/60 px-4 py-2 text-[13px]">
           No se pudo consultar el detalle por analista: la atención y las barras no están disponibles.
           <Button variant="ghost" className="h-9 text-[13px] pointer-coarse:h-11" onClick={() => void detalle.recargar()} disabled={detalle.enVuelo}>Reintentar</Button>
         </div>}
-        <TablaEquiposGerencia filas={mostradas} total={filasOp.length} conAtencion={conAtencion} sinDetalle={detalle.error ? 'error' : 'cargando'} umbrales={detalle.datos?.umbrales ?? null}
+        <TablaEquiposGerencia filas={mostradas} total={filasOp.length} conteos={conteos} sinDetalle={detalle.error ? 'error' : 'cargando'} umbrales={detalle.datos?.umbrales ?? null}
           filtros={filtros} setFiltros={setFiltros} ordenar={ordenar}
           seleccion={ficha?.vista.tipo === 'equipo' ? ficha.vista.clave : null} seleccionar={(f, control) => abrirFicha({ tipo: 'equipo', clave: f.clave }, control, false)}
           accion={(f, tipo, control) => tipo === 'llamadas'
             ? abrirFicha({ tipo: 'registro', alcance: f.clave, pestana: 'llamadas', apertura: ++aperturas.current }, control, true)
-            : entrarEquipo(f.clave, tipo)} panelId={panelId}
+            : entrarEquipo(f.clave, tipo)} totalOperacion={total!} accionTotal={accionTotal} panelId={panelId}
           irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />
-        <p className="shrink-0 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
-          Organigrama actual · Pendientes al {FECHA_CORTE.format(new Date(datos.pendientes_al))}, {horaLimaDe(datos.pendientes_al)} ·{' '}
-          <button type="button" className={cn('cursor-pointer rounded-md font-bold text-[var(--destructive-text)] underline-offset-2 hover:underline', FOCO)}
-            onClick={() => { setFiltros((f) => ({ ...f, busqueda: '', conAtencion: false, orden: 'vencidas', ascendente: false })); setAnuncio('Equipos ordenados por tareas vencidas, de más a menos.') }}>
-            {datos.vencidas_global} tareas vencidas</button> en total.
-        </p>
+        {/* El pie del supervisor: cuántos se ven y cuándo; aquí, además, de qué momento son los pendientes. */}
+        <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
+          <p><span role="status">{mostradas.length} de {filasOp.length} equipos</span> · Actualizado {hora}</p>
+          <p>Organigrama actual · Pendientes al {FECHA_CORTE.format(new Date(datos.pendientes_al))}, {horaLimaDe(datos.pendientes_al)}</p>
+        </div>
       </div>
       <PanelSupervisorAdaptable modal={modal} cerrar={cerrarFicha} tituloRef={tituloPanel} claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
         <PanelOperacionGerencia id={panelId} vista={ficha?.vista ?? null} pulso={datos} detalle={filasDetalle} detalleFallido={Boolean(detalle.error)} esHoy={esHoy} tituloRef={tituloPanel}
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-pulso.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-pulso.spec.ts
index 9fda8faf..531c6c3d 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-pulso.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-pulso.spec.ts
@@ -105,7 +105,7 @@ test('F6 horizontal: gerencia conserva tabla y detalle con el menú abierto en u
   const ficha = vista.getByRole('region', { name: `Detalle del ${EQUIPO}`, exact: true })
   // La tarjeta de la tabla (buscador + tabla) es la que se compara con la ficha.
   const tarjeta = vista.getByRole('region', { name: 'Desplazar tabla de equipos', exact: true }).locator('..')
-  const cifras = vista.getByRole('region', { name: 'Cifras de la operación', exact: true })
+  const pastillas = vista.getByRole('group', { name: 'Resumen de la operación', exact: true }).getByRole('button')
   // Con el menú fijado, 1366 deja 1078 px a la operación (ficha al lado) y 1280, 992: por debajo de
   // 1040 la tabla ocupa todo el ancho y la ficha automática se cierra sin abrir ninguna ventana.
   for (const [width, height] of [[1366, 900], [1366, 768], [1280, 800]]) {
@@ -124,10 +124,10 @@ test('F6 horizontal: gerencia conserva tabla y detalle con el menú abierto en u
     } else {
       expect(Math.abs(tabla.width - (await raizOperacion(page).boundingBox())!.width)).toBeLessThan(2)
     }
-    // La tabla empieza justo bajo cabecera, pestañas y cifras (~394 px); una fila más de cabecera la pasa de 430.
-    expect(tabla.y).toBeLessThan(420)
-    const posiciones = await cifras.locator('dl>div').evaluateAll(nodos => nodos.map(n => n.getBoundingClientRect().y))
-    expect(posiciones).toHaveLength(4)
+    // Sin franja de cifras (como el supervisor): la tabla empieza bajo cabecera y pestañas.
+    expect(tabla.y).toBeLessThan(360)
+    const posiciones = await pastillas.evaluateAll(nodos => nodos.map(n => n.getBoundingClientRect().y))
+    expect(posiciones).toHaveLength(3)
     expect(new Set(posiciones).size).toBe(1)
     expect(await page.locator('[data-vista-scroll="gestion-diaria"]').evaluate(n => n.scrollHeight <= n.clientHeight + 1 && n.scrollWidth <= n.clientWidth + 1)).toBe(true)
   }
@@ -203,9 +203,11 @@ test('F6 horizontal: gerencia conserva tabla y detalle con el menú abierto en u
 test('F5 escritorio: operación, equipo, analista, registro, ficha y vuelta con contexto', async ({ page }, info) => {
   const estado = await montar(page)
   const vista = operacion(page)
-  await expect(vista).toContainText('1008 tareas vencidas en total')
-  // Cada cifra se compara con el día anterior y con las jornadas de referencia (7 de 7 con actividad).
-  await expect(vista.getByRole('region', { name: 'Cifras de la operación', exact: true })).toContainText('Día anterior 0 · Referencia 4 (7 jornadas)')
+  // «Toda la operación» al pie de la tabla; la comparación con el día anterior y la referencia, en «Comparar días».
+  await expect(vista.getByRole('button', { name: '1008 tareas vencidas en toda la operación: ver los equipos con vencidas', exact: true })).toBeVisible()
+  await botonCabecera(page, 'Comparar días').click()
+  await expect(page.getByRole('dialog', { name: 'Comparación de la operación' })).toContainText('Referencia: 7 de 7 jornadas con actividad')
+  await page.keyboard.press('Escape')
   await page.screenshot({ path: info.outputPath('f5-operacion-escritorio.png'), fullPage: true })
   // Con el teclado: la fila elige el equipo, la flecha lleva a su ficha y «Ver el equipo» entra.
   const filaEquipo = vista.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true })
@@ -251,10 +253,10 @@ test('F5 escritorio: operación, equipo, analista, registro, ficha y vuelta con
 test('F5 móvil: fecha, recarga y enlace directo sin desbordamiento', async ({ page }, info) => {
   const estado = await montar(page)
   const vista = operacion(page)
-  // Ningún texto de las cuatro cifras se sale de su casilla (se mide el texto, no la caja del bloque).
+  // Ninguna pastilla se sale de su fila (se mide el texto, no la caja del bloque).
   for (const width of [390, 360, 320]) {
     await page.setViewportSize({ width, height: 844 })
-    await expect.poll(() => vista.getByRole('region', { name: 'Cifras de la operación', exact: true }).locator('dl>div').evaluateAll(casillas =>
+    await expect.poll(() => vista.getByRole('group', { name: 'Resumen de la operación', exact: true }).locator('xpath=..').evaluateAll(casillas =>
       casillas.flatMap(casilla => Array.from(casilla.children).filter(n => {
         const caja = casilla.getBoundingClientRect(), rango = document.createRange()
         rango.selectNodeContents(n)
@@ -347,7 +349,7 @@ test('F5 error y revocación ocultan datos; recuperación vuelve a consultar', a
   const alerta = vista.getByRole('alert')
   await expect(alerta).toContainText('datos anteriores se han ocultado')
   await expect(page.getByRole('table', { name: 'Equipos de la operación' })).toHaveCount(0)
-  await expect(vista.getByRole('region', { name: 'Cifras de la operación', exact: true })).toHaveCount(0)
+  await expect(vista.getByRole('rowheader', { name: /^Toda la operación/ })).toHaveCount(0)
   await expect(vista.getByRole('region', { name: 'Registro general', exact: true })).toHaveCount(0)
   estado.error = false
   await alerta.getByRole('button', { name: 'Reintentar', exact: true }).click()
@@ -365,7 +367,7 @@ test('F5 conserva la fila fuera de equipos y exportación del registro cargado',
   // El grupo sin supervisor no compite con los equipos: siempre al final.
   await expect(filas.last()).toHaveAccessibleName('Seleccionar Fuera de equipos comerciales')
   await filas.last().click()
-  await vista.getByRole('region', { name: 'Detalle del Fuera de equipos comerciales', exact: true }).getByRole('button', { name: 'Ver el equipo', exact: true }).click()
+  await vista.getByRole('region', { name: 'Detalle del grupo Fuera de equipos comerciales', exact: true }).getByRole('button', { name: 'Ver el equipo', exact: true }).click()
   await expect(page).toHaveURL(/\/gestion-diaria\/equipo\/fuera$/)
   const fuera = vista.getByRole('region', { name: 'Fuera de equipos comerciales', exact: true })
   await expect(fuera).toContainText('Sin autor: 1 llamadas')
@@ -383,8 +385,9 @@ test('F6 gerencia: densidad, filtros y registro permanecen al ampliar, redimensi
   const estado = await montar(page)
   estado.paginado = true
   const vista = operacion(page)
-  const cifras = vista.getByRole('region', { name: 'Cifras de la operación', exact: true }).locator('dl')
-  const valores = await cifras.textContent()
+  // Las cifras de «Toda la operación» (pie de la tabla) no cambian al filtrar equipos.
+  const total = vista.getByRole('table', { name: 'Equipos de la operación' }).locator('tfoot tr')
+  const valores = await total.textContent()
   await expect(vista).toHaveAttribute('data-estrecho', 'false')
   expect(await page.locator('[data-vista-scroll="gestion-diaria"]').evaluate((n) => n.scrollHeight <= n.clientHeight + 1)).toBe(true)
   const equipos = vista.getByRole('table', { name: 'Equipos de la operación' })
@@ -394,7 +397,7 @@ test('F6 gerencia: densidad, filtros y registro permanecen al ampliar, redimensi
   const buscarEquipo = vista.getByRole('searchbox', { name: 'Buscar equipo', exact: true })
   await buscarEquipo.fill(grupo.nombre)
   await expect(equipos.locator('tbody tr')).toHaveCount(1)
-  await expect(cifras).toHaveText(valores!)
+  await expect(total).toHaveText(valores!)
   await equipos.getByRole('button', { name: `Seleccionar ${EQUIPO}`, exact: true }).click()
   const equipo = await entrarAlEquipo(page)
   const buscar = equipo.getByRole('searchbox', { name: 'Buscar analista', exact: true })
@@ -490,7 +493,7 @@ for (const ambito of ['general', 'analista']) test(`F6 una revocación del regis
   let registro: Locator
   if (ambito === 'general') {
     await botonCabecera(page, 'Registro general').click()
-    registro = page.getByRole('region', { name: `Registro de actividad del ${DIA}`, exact: true })
+    registro = vista.getByRole('region', { name: 'Registro general', exact: true }).getByRole('region', { name: 'Registro seleccionado', exact: true })
   } else {
     const equipo = await entrarAlEquipo(page)
     await equipo.getByRole('button', { name: `Seleccionar a ${analista.nombre_completo}`, exact: true }).click()
@@ -500,10 +503,9 @@ for (const ambito of ['general', 'analista']) test(`F6 una revocación del regis
   }
   await expect(registro).toContainText(`Llamada ficticia F5 del ${DIA}`)
   estado.registroRevocado = true
-  // El registro general conserva su «Actualizar»; el compacto de la ficha no lo tiene, así
-  // que la consulta nueva la pide su pastilla de tipo (un control que también desaparece).
-  if (ambito === 'general') await registro.getByRole('button', { name: 'Actualizar', exact: true }).click()
-  else await registro.getByRole('tab', { name: 'Llamadas', exact: true }).click()
+  // Los dos registros son compactos (como el supervisor), sin «Actualizar» propio: la consulta
+  // nueva la pide su pastilla de tipo (un control que también desaparece).
+  await registro.getByRole('tab', { name: 'Llamadas', exact: true }).click()
   await expect(vista.getByRole('alert').filter({ hasText: 'ya no tiene permiso' })).toBeVisible()
   await expect(page.getByRole('table')).toHaveCount(0)
   await expect(registro).toHaveCount(0)
```

## .ai/REVIEW_PROTOCOL.md (transcrito)
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
