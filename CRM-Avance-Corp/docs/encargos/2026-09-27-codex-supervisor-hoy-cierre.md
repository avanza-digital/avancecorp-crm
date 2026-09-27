ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia, TEST GAPS, REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE.
Sin hallazgo sin evidencia. Omite secciones vacías.

# Encargo: CONFIRMAR el cierre de tu auditoría final del «Hoy» del supervisor — LEVEL 2

Tu auditoría final (CHANGES_REQUESTED: 1 P1 + 2 P2) se atendió en el commit 4b54e495 (diff abajo):
- P1: `useDatosSupervisor` anula la conversión mensual cuando la consulta tiene error (todos los
  consumidores reciben null): franja «—», «Detalle» sin porcentaje ni divisor, y la pantalla clásica
  también (cambio deliberado de fail-closed).
- P2: `nombresCortos` por niveles (primer nombre → inicial del último apellido → apellido entero →
  nombre completo); cada nombre se queda en el primer nivel sin choque.
- P2: área de toque: botón compartido de `AvisoDegradacion` con pseudo-elemento `after:-inset-x-2
  after:-inset-y-3` (≥36 px sin cambiar el diseño; `pointer-coarse:after:-inset-y-3.5`); acciones
  compactas con min-h/min-w 9 (10 táctil); «Cerrar» con `pointer-coarse:min-h-10`.
- Tests añadidos: conversión con error dentro de «Detalle», foco inicial en el título, salida del
  popover por `focusout`, nombres con la misma inicial y con mismo apellido final.

VERIFICACIÓN del PRIMARY sobre 4b54e495: `npm run check` PASS (lint, typecheck, 4589/4589 tests con
cobertura, build, verify:bundle, dup); e2e Docker `hoy-supervisor-mando.spec.ts` + `sla-operacion.spec.ts`
17/17 PASS.

Pregunta: ¿quedan bien cerrados tus 3 hallazgos? ¿El cambio en el componente compartido
`AvisoDegradacion` (usado en ~9 pantallas) introduce algún riesgo (p. ej. el pseudo-elemento tapando
otro control cercano)? No repitas hallazgos ya cerrados.

## DIFF del commit 4b54e495
```diff
commit 4b54e4957e86b93de6932b3568d945ae281b608f
Author: Miguel Briceño <avancecorp26@gmail.com>
Date:   Sun Sep 27 14:16:31 2026 -0500

    CRM: Hoy del supervisor — arreglos de la auditoría final de Codex
    
    - La conversión del mes con error no se publica en ningún consumidor
      (franja, «Detalle» y pantalla clásica): «—» y «no disponible».
    - nombresCortos sube de nivel hasta que las etiquetas no choquen
      (inicial → apellido → nombre completo).
    - Área de toque ≥36/40 px: botón «Reintentar» del aviso compartido (con
      pseudo-elemento, sin mover el diseño), acciones compactas en alto y
      ancho, y «Cerrar» del detalle.
    
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

diff --git a/CRM-Avance-Corp/app/src/components/common/aviso-degradacion.tsx b/CRM-Avance-Corp/app/src/components/common/aviso-degradacion.tsx
index 92d2e67b..106eb8c9 100644
--- a/CRM-Avance-Corp/app/src/components/common/aviso-degradacion.tsx
+++ b/CRM-Avance-Corp/app/src/components/common/aviso-degradacion.tsx
@@ -85,7 +85,9 @@ export function AvisoDegradacion({
               // Anillo SÓLIDO (4,62:1): el token /40 de la casa se queda en
               // 1,76:1 y no llega al 3:1 que exige un indicador de foco. El
               // subrayado añade un segundo canal que no depende del color.
-              className="rounded font-semibold text-foreground underline-offset-2 hover:underline focus-visible:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring"
+              // Área de toque ≥36 px (40 táctil) con un pseudo-elemento: el botón
+              // se ve igual y la franja no crece, pero el dedo no falla.
+              className="relative rounded font-semibold text-foreground underline-offset-2 after:absolute after:-inset-x-2 after:-inset-y-3 after:content-[''] hover:underline focus-visible:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring pointer-coarse:after:-inset-y-3.5"
               onClick={() => {
                 // Solo hay foco que rescatar si el foco estaba de verdad AQUÍ.
                 // Con ratón puede no estarlo (Safari no enfoca al hacer clic):
diff --git a/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts b/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts
index cbaf5743..8c969096 100644
--- a/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts
@@ -47,4 +47,20 @@ describe('nombresCortos', () => {
     expect(m.get('KAREN LÓPEZ')).toBe('Karen L.')
     expect(m.get('JORGE HUAMÁN')).toBe('Jorge')
   })
+
+  it('con la MISMA inicial de apellido sube de nivel hasta que no choquen (Codex)', () => {
+    const m = nombresCortos(['KAREN ZAPATA', 'KAREN ZÚÑIGA', 'KAREN LÓPEZ'])
+    expect(m.get('KAREN ZAPATA')).toBe('Karen Zapata')
+    expect(m.get('KAREN ZÚÑIGA')).toBe('Karen Zúñiga')
+    // La que ya se distinguía con la inicial no se alarga de más.
+    expect(m.get('KAREN LÓPEZ')).toBe('Karen L.')
+    const etiquetas = [...m.values()]
+    expect(new Set(etiquetas).size).toBe(etiquetas.length)
+  })
+
+  it('mismo primer nombre y mismo apellido final: recurre al nombre completo', () => {
+    const m = nombresCortos(['ANA MARÍA TORRES', 'ANA LUCÍA TORRES'])
+    expect(m.get('ANA MARÍA TORRES')).toBe('Ana María Torres')
+    expect(m.get('ANA LUCÍA TORRES')).toBe('Ana Lucía Torres')
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/lib/cola-supervision.ts b/CRM-Avance-Corp/app/src/lib/cola-supervision.ts
index 6406bd89..e67d5538 100644
--- a/CRM-Avance-Corp/app/src/lib/cola-supervision.ts
+++ b/CRM-Avance-Corp/app/src/lib/cola-supervision.ts
@@ -42,20 +42,47 @@ export function momentoCaso(bucket: string, referenciaEn: string | null, ahora:
   return dias >= 0 ? `venció ${haceTexto(dias)}` : `vence en ${duracionTexto(-dias)}`
 }
 
+const capital = (palabra: string) => palabra.charAt(0).toUpperCase() + palabra.slice(1).toLowerCase()
+
 /**
  * Nombre corto de cada persona para chips y columnas estrechas: el primer
- * nombre, y si dos lo comparten, la inicial del último apellido para
- * distinguirlos («Karen Z.» / «Karen L.»). Dos chips iguales no se pueden elegir.
+ * nombre; si dos lo comparten, se añade lo MÍNIMO que los distingue, por
+ * niveles: inicial del último apellido («Karen Z.»), el apellido entero
+ * («Karen Zapata») y, si aún chocan, el nombre completo. Dos chips iguales no
+ * se pueden elegir. Nombres completos idénticos quedan iguales: ahí la
+ * identidad la da el id, no la etiqueta.
  */
 export function nombresCortos(nombres: readonly string[]): Map<string, string> {
   const unicos = [...new Set(nombres.map((n) => n.trim()).filter(Boolean))]
-  const porPila = new Map<string, number>()
-  for (const n of unicos) porPila.set(primerNombre(n), (porPila.get(primerNombre(n)) ?? 0) + 1)
-  return new Map(unicos.map((n) => {
-    const pila = primerNombre(n)
-    if ((porPila.get(pila) ?? 0) < 2) return [n, pila] as const
-    const partes = n.split(/\s+/)
-    const inicial = partes.length > 1 ? (partes[partes.length - 1] ?? '').charAt(0).toUpperCase() : ''
-    return [n, inicial ? `${pila} ${inicial}.` : pila] as const
-  }))
+  const niveles: Array<(n: string) => string> = [
+    (n) => primerNombre(n),
+    (n) => {
+      const partes = n.split(/\s+/)
+      return partes.length > 1 ? `${primerNombre(n)} ${(partes[partes.length - 1] ?? '').charAt(0).toUpperCase()}.` : primerNombre(n)
+    },
+    (n) => {
+      const partes = n.split(/\s+/)
+      return partes.length > 1 ? `${primerNombre(n)} ${capital(partes[partes.length - 1] ?? '')}` : primerNombre(n)
+    },
+    (n) => n.split(/\s+/).map(capital).join(' '),
+  ]
+  const resultado = new Map<string, string>()
+  let pendientes = unicos
+  for (const [i, nivel] of niveles.entries()) {
+    const etiquetas = new Map(pendientes.map((n) => [n, nivel(n)] as const))
+    const cuenta = new Map<string, number>()
+    for (const e of etiquetas.values()) cuenta.set(e, (cuenta.get(e) ?? 0) + 1)
+    const esUltimo = i === niveles.length - 1
+    // Cada nombre se queda en el primer nivel en que su etiqueta ya no choca.
+    pendientes = pendientes.filter((n) => {
+      const e = etiquetas.get(n) ?? n
+      if ((cuenta.get(e) ?? 0) < 2 || esUltimo) {
+        resultado.set(n, e)
+        return false
+      }
+      return true
+    })
+    if (pendientes.length === 0) break
+  }
+  return resultado
 }
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts b/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts
index b2013d40..30faab45 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts
+++ b/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts
@@ -186,12 +186,17 @@ export function useDatosSupervisor() {
   const conversionMensualCargando = !esDemoConversion
     && qConversionMensual.isPending
     && qConversionMensual.data === undefined
+  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
+  // Fail-closed: tras un refetch fallido TanStack conserva la respuesta
+  // anterior; con error NO se publica (ni porcentaje, ni divisor, ni nota) —
+  // se dice «no disponible» y se ofrece reintentar (Codex, auditoría final).
   const conversionMensual = esDemoConversion
     ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
     : conversionMensualCargando
       ? undefined
-      : (qConversionMensual.data ?? null)
-  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
+      : conversionMensualError
+        ? null
+        : (qConversionMensual.data ?? null)
   // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
   // 2026-08-14). La regla vive en `lecturaCobertura`, compartida con las otras
   // tres pantallas que pintan esta misma cifra.
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
index ff8a03e1..4345e0fc 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
@@ -663,9 +663,36 @@ describe('Hoy · supervisor — puesto de mando: arreglos de la revisión F2/F3'
       },
       isError: true,
     }
+    vi.useRealTimers()
     montar()
     expect(screen.getByRole('list', { name: 'Cifras del equipo' })).toHaveTextContent('— conversión del mes')
     expect(screen.getByText(/No se pudieron cargar algunos indicadores del equipo/)).toBeInTheDocument()
+    // Tampoco dentro del detalle: ni porcentaje ni divisor retenidos.
+    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
+    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
+    expect(dialogo).toHaveTextContent('Conversión del mes no disponible')
+    expect(dialogo).not.toHaveTextContent(/40[,.]?\d*\s?%|10 recibidos/)
+  })
+
+  it('«Detalle» abre con el foco en su título, no en mitad de la rejilla', async () => {
+    vi.useRealTimers()
+    montar()
+    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
+    await waitFor(() => expect(document.activeElement).toHaveTextContent('Detalle del equipo'))
+  })
+
+  it('«Esta semana» se cierra cuando el foco SALE con el teclado', () => {
+    METRICAS_AGENDA = agenda([
+      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2 },
+      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 5 },
+    ])
+    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
+    montar()
+    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
+    fireEvent.click(disparador)
+    const fuera = screen.getByRole('button', { name: 'Detalle' })
+    fireEvent.focusOut(disparador, { relatedTarget: fuera })
+    expect(disparador).toHaveAttribute('aria-expanded', 'false')
   })
 
   it('al cerrar «Detalle» con Esc el foco VUELVE al botón', async () => {
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
index ad17b04f..f6956eb0 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
@@ -548,8 +548,8 @@ function PuestoDeMando(): JSX.Element {
                             <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                           </button>
                           {leadStore && (
-                            // Las acciones compactas miden 28 px: se llevan al mínimo de 36 (40 táctil).
-                            <div className="[&_a]:min-h-9 [&_button]:min-h-9 pointer-coarse:[&_a]:min-h-10 pointer-coarse:[&_button]:min-h-10">
+                            // Las acciones compactas miden 28 px: se llevan al mínimo de 36 (40 táctil), alto Y ancho.
+                            <div className="[&_a]:min-h-9 [&_a]:min-w-9 [&_button]:min-h-9 [&_button]:min-w-9 pointer-coarse:[&_a]:min-h-10 pointer-coarse:[&_a]:min-w-10 pointer-coarse:[&_button]:min-h-10 pointer-coarse:[&_button]:min-w-10">
                               <AccionesContacto lead={leadStore} compacto />
                             </div>
                           )}
@@ -829,7 +829,7 @@ function PuestoDeMando(): JSX.Element {
           </p>
         </DialogBody>
         <DialogFooter>
-          <Button variant="outline" size="sm" className="min-h-9" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
+          <Button variant="outline" size="sm" className="min-h-9 pointer-coarse:min-h-10" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
         </DialogFooter>
       </Dialog>
     </div>
```

### `app/src/components/common/aviso-degradacion.tsx` (estado final)
```
     1	// aviso-degradacion.tsx — la franja que aparece cuando una fuente de métricas
     2	// se cae: la pantalla NO se bloquea, los indicadores quedan en «—» y aquí se
     3	// explica por qué, con un botón para reintentar (precedente objetivosError).
     4	//
     5	// Fuente ÚNICA a propósito. El patrón vivió clonado en 9 sitios y los defectos
     6	// que arrastraba estaban clonados con él:
     7	//   1. Texto en `muted-foreground` sobre el fondo ámbar: 4,25:1 a 12 px, por
     8	//      debajo del 4,5:1 exigible. Justo el texto que explica por qué faltan
     9	//      los números era el menos legible de la pantalla. Va en `warning-text`
    10	//      (6,34:1 medido sobre el fondo compuesto real).
    11	//   2. El botón se desmonta cuando el reintento SALE BIEN (el aviso desaparece
    12	//      con él) y el foco del teclado caía a <body>: había que retabular la
    13	//      pantalla entera. Lo recoge el ancla de abajo.
    14	// Cualquier aviso nuevo que use este componente nace con ambos resueltos.
    15	import { useEffect, useRef, type ReactNode } from 'react'
    16	import { cn } from '@/lib/utils'
    17	
    18	export interface AvisoDegradacionProps {
    19	  /** Si no, no hay nada que avisar (queda solo el ancla de foco, sin pintar). */
    20	  activo: boolean
    21	  /** Qué no se pudo cargar y qué implica. Frase completa, en español. */
    22	  children: ReactNode
    23	  /**
    24	   * Complemento que completa el nombre accesible del botón
    25	   * («Reintentar la carga ___»). Llega YA DECLINADO, con su preposición:
    26	   * «de los indicadores de la cartera», «del reloj SLA». Se pide así para no
    27	   * anteponer un `de` a ciegas y acabar diciendo «de el reloj SLA» en voz alta.
    28	   *
    29	   * Existe porque varias pantallas tienen más de un «Reintentar» a la vez
    30	   * —Pipeline muestra dos avisos, y las listas traen el suyo en el panel de
    31	   * error— y en el rotor del lector se verían botones idénticos.
    32	   */
    33	  queReintenta: string
    34	  onReintentar: () => void
    35	}
    36	
    37	export function AvisoDegradacion({
    38	  activo,
    39	  children,
    40	  queReintenta,
    41	  onReintentar,
    42	}: AvisoDegradacionProps) {
    43	  // Ancla SIEMPRE montada, `sr-only` cuando no hay aviso —absoluta y recortada,
    44	  // NUNCA `hidden`: un display:none no se puede enfocar— para que sobreviva al
    45	  // aviso y recoja el foco cuando el botón se va. Al estar en la MISMA posición
    46	  // del DOM, el siguiente Tab continúa por donde tocaba. tabIndex={-1} = destino
    47	  // programático, no alcanzable con Tab, que es lo que hace legítimo el
    48	  // outline-none.
    49	  const ancla = useRef<HTMLDivElement>(null)
    50	  const boton = useRef<HTMLButtonElement>(null)
    51	  const esperandoFoco = useRef(false)
    52	  const activoPrevio = useRef(activo)
    53	
    54	  // El rescate del foco se cuelga del cambio de `activo`, NO del click: el
    55	  // reintento es un refetch de red y el aviso desaparece cientos de ms después,
    56	  // no en el par de cuadros siguientes. Colgarlo del click dejaba el rescate en
    57	  // código muerto (lo cazó la revisión de Codex y la de a11y).
    58	  useEffect(() => {
    59	    const desaparecio = activoPrevio.current && !activo
    60	    activoPrevio.current = activo
    61	    if (!desaparecio || !esperandoFoco.current) return
    62	    esperandoFoco.current = false
    63	    // Solo si el foco quedó huérfano: si el usuario ya se movió a otro control
    64	    // —el reintento pudo tardar—, no se lo robamos. Tras un desmontaje algunos
    65	    // motores dejan `activeElement` en null en vez de en <body>.
    66	    const foco = document.activeElement
    67	    if (!foco || foco === document.body) ancla.current?.focus()
    68	  }, [activo])
    69	
    70	  return (
    71	    <div ref={ancla} tabIndex={-1} className={cn('outline-none', !activo && 'sr-only')}>
    72	      {/* La región vive SIEMPRE en el DOM y el contenido llega después: es el
    73	          orden fiable para que un lector de pantalla anuncie el cambio.
    74	          `status` (polite) y no `alert`: la pantalla queda operable con «—», no
    75	          hay nada urgente ni con plazo, y un anuncio asertivo interrumpiría la
    76	          lectura en curso sin necesidad. */}
    77	      <div role="status">
    78	        {activo && (
    79	          <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warning/30 bg-warning/5 px-3 py-2 text-xs text-warning-text">
    80	            <span>{children}</span>
    81	            <button
    82	              ref={boton}
    83	              type="button"
    84	              aria-label={`Reintentar la carga ${queReintenta}`}
    85	              // Anillo SÓLIDO (4,62:1): el token /40 de la casa se queda en
    86	              // 1,76:1 y no llega al 3:1 que exige un indicador de foco. El
    87	              // subrayado añade un segundo canal que no depende del color.
    88	              // Área de toque ≥36 px (40 táctil) con un pseudo-elemento: el botón
    89	              // se ve igual y la franja no crece, pero el dedo no falla.
    90	              className="relative rounded font-semibold text-foreground underline-offset-2 after:absolute after:-inset-x-2 after:-inset-y-3 after:content-[''] hover:underline focus-visible:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring pointer-coarse:after:-inset-y-3.5"
    91	              onClick={() => {
    92	                // Solo hay foco que rescatar si el foco estaba de verdad AQUÍ.
    93	                // Con ratón puede no estarlo (Safari no enfoca al hacer clic):
    94	                // inferirlo de <body> daría un falso positivo y movería el foco
    95	                // de quien nunca lo tuvo puesto (hallazgo de Codex).
    96	                esperandoFoco.current = document.activeElement === boton.current
    97	                onReintentar()
    98	              }}
    99	            >
   100	              Reintentar
   101	            </button>
   102	          </div>
   103	        )}
   104	      </div>
   105	    </div>
   106	  )
   107	}
```

### `app/src/lib/cola-supervision.ts` (estado final)
```
     1	// lib/cola-supervision.ts — cómo lee el SUPERVISOR una fila del seguimiento
     2	// activo (crm.cola_accion_v2_fn) en su pantalla Hoy (27/09/2026).
     3	//
     4	// ACCIONES_SLA habla al analista en imperativo («Contactar al cliente»); el
     5	// supervisor no gestiona el lead, lo revisa con su analista (textoAvisoSla con
     6	// supervision = true). Por eso aquí el bucket se nombra como un ESTADO del
     7	// caso, y el tiempo dice qué significa la fecha de referencia de ese bucket:
     8	// en unos es un plazo (vence / venció), en otros el inicio (desde).
     9	import { DIA_MS, duracionTexto, haceTexto } from './inteligencia'
    10	import { primerNombre } from './format'
    11	
    12	/** Estado del caso visto desde supervisión, por bucket del seguimiento. */
    13	export const ESTADO_CASO_SUPERVISION: Record<string, string> = {
    14	  primera_atencion: 'Primera gestión pendiente',
    15	  tarea_vencida: 'Actividad vencida',
    16	  tarea_hoy: 'Actividad para hoy',
    17	  seguimiento: 'Seguimiento pendiente',
    18	  revision_comercial: 'Revisión comercial',
    19	  datos_incompletos: 'Datos incompletos',
    20	  proxima_tarea: 'Próxima actividad',
    21	  por_repartir: 'Sin analista asignado',
    22	}
    23	
    24	export function estadoCasoSupervision(bucket: string): string {
    25	  return ESTADO_CASO_SUPERVISION[bucket] ?? 'Revisar oportunidad'
    26	}
    27	
    28	// En estos buckets `referencia_en` es un PLAZO (private.sla_operacion_leads):
    29	// el límite de la primera gestión, el vencimiento de la actividad o el límite
    30	// del seguimiento. En los demás es el inicio del caso (creado_en, etapa).
    31	const BUCKETS_CON_PLAZO = new Set(['primera_atencion', 'tarea_vencida', 'tarea_hoy', 'seguimiento', 'proxima_tarea'])
    32	
    33	/**
    34	 * «venció hace 2 días» / «vence en 3 horas» / «desde hace 5 días».
    35	 * Sin fecha confirmada lo dice: no se inventa un tiempo (referencia_en es nullable).
    36	 */
    37	export function momentoCaso(bucket: string, referenciaEn: string | null, ahora: number): string {
    38	  const ms = referenciaEn == null ? Number.NaN : Date.parse(referenciaEn)
    39	  if (!Number.isFinite(ms)) return 'sin fecha confirmada'
    40	  const dias = (ahora - ms) / DIA_MS
    41	  if (!BUCKETS_CON_PLAZO.has(bucket)) return `desde ${haceTexto(Math.max(0, dias))}`
    42	  return dias >= 0 ? `venció ${haceTexto(dias)}` : `vence en ${duracionTexto(-dias)}`
    43	}
    44	
    45	const capital = (palabra: string) => palabra.charAt(0).toUpperCase() + palabra.slice(1).toLowerCase()
    46	
    47	/**
    48	 * Nombre corto de cada persona para chips y columnas estrechas: el primer
    49	 * nombre; si dos lo comparten, se añade lo MÍNIMO que los distingue, por
    50	 * niveles: inicial del último apellido («Karen Z.»), el apellido entero
    51	 * («Karen Zapata») y, si aún chocan, el nombre completo. Dos chips iguales no
    52	 * se pueden elegir. Nombres completos idénticos quedan iguales: ahí la
    53	 * identidad la da el id, no la etiqueta.
    54	 */
    55	export function nombresCortos(nombres: readonly string[]): Map<string, string> {
    56	  const unicos = [...new Set(nombres.map((n) => n.trim()).filter(Boolean))]
    57	  const niveles: Array<(n: string) => string> = [
    58	    (n) => primerNombre(n),
    59	    (n) => {
    60	      const partes = n.split(/\s+/)
    61	      return partes.length > 1 ? `${primerNombre(n)} ${(partes[partes.length - 1] ?? '').charAt(0).toUpperCase()}.` : primerNombre(n)
    62	    },
    63	    (n) => {
    64	      const partes = n.split(/\s+/)
    65	      return partes.length > 1 ? `${primerNombre(n)} ${capital(partes[partes.length - 1] ?? '')}` : primerNombre(n)
    66	    },
    67	    (n) => n.split(/\s+/).map(capital).join(' '),
    68	  ]
    69	  const resultado = new Map<string, string>()
    70	  let pendientes = unicos
    71	  for (const [i, nivel] of niveles.entries()) {
    72	    const etiquetas = new Map(pendientes.map((n) => [n, nivel(n)] as const))
    73	    const cuenta = new Map<string, number>()
    74	    for (const e of etiquetas.values()) cuenta.set(e, (cuenta.get(e) ?? 0) + 1)
    75	    const esUltimo = i === niveles.length - 1
    76	    // Cada nombre se queda en el primer nivel en que su etiqueta ya no choca.
    77	    pendientes = pendientes.filter((n) => {
    78	      const e = etiquetas.get(n) ?? n
    79	      if ((cuenta.get(e) ?? 0) < 2 || esUltimo) {
    80	        resultado.set(n, e)
    81	        return false
    82	      }
    83	      return true
    84	    })
    85	    if (pendientes.length === 0) break
    86	  }
    87	  return resultado
    88	}
```

---
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
