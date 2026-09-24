# H4 — revisión independiente y resolución

Una consulta mediante `scripts/claude-review`, Codex PRIMARY y Claude
SECONDARY_REVIEWER sin herramientas. Evidencia: diff y fuentes con líneas,
contratos, pruebas, protocolo y checklist de accesibilidad. CodeGraph no tiene
índice en la copia aislada; se usaron lecturas puntuales como indica su salida.

El dictamen original es **CHANGES_REQUESTED / MEDIUM**. No se sustituye por PASS
ni se solicita otra revisión para cambiarlo. Codex resuelve con evidencia.

## Resolución

| Hallazgo | Resolución del PRIMARY | Evidencia |
|---|---|---|
| P2: falta legítima de `diarias` | Aceptado. Otros pendientes consume las mismas alertas no asociadas a cortes de la campana; contexto y modo diario son opcionales. | Caso unitario sin `diarias/contexto` y E2E de contrato anterior. |
| P2: nombre accesible | Aceptado. El botón usa su texto visible «Cortes y avisos» como nombre. | Localizadores por nombre visible en pruebas de componente, supervisor y E2E. |
| P2: reloj del mock | Aceptado como riesgo demostrado por el contrato. El mock consulta el reloj de la página, incluido `page.clock`. | E2E fijo al 26/09; avisos se cargan sin error de jornada. |
| P2: Actualizar recarga store | Aceptado. Con fuente diaria, `reintentar` consulta cortes y libro; conserva el camino anterior para otros casos. Botón bloqueado durante carga. | Test del proveedor exige una lectura de cada fuente y cero recargas de store o resumen alternativo. |
| P3: anuncio doble | Aceptado. Confirmación por foco; progreso conserva `role=status` y fallo `role=alert`. | Prueba de foco después de confirmar y después de fallar. NVDA/VoiceOver humano NOT RUN. |
| P3: marcador de disclosure | Aceptado. Icono SVG decorativo `aria-hidden`; marcador nativo suprimido explícitamente. | Capturas y teclado en Chromium; Safari NOT RUN. |
| P3: contador durante refresco | Aceptado. Mantiene el último conteo confirmado mientras refresca y lo retira ante error. | Caso de refresco y error del libro. La franja se remonta por actor/día con la vista. |

Cuatro regresiones nuevas fallaron antes del arreglo y el banco de cuatro
archivos terminó en **60 PASS** después. Logs `review-regresiones-antes.log` y
`review-regresiones-despues.log`. Posteriormente se mejoró solo la coherencia del
fixture y se amplió el E2E de contrato anterior: **14/14 PASS** incluyendo el
archivo completo de postventa, sin modificarlo.

Se añadió el caso de aviso antiguo con un miembro retirado de la foto vigente.
La búsqueda de `seguimientoKeys.avisos` solo encontró el hook y su prueba: no
quedan lectores/escritores con la clave anterior sin día. La retirada del
popup cuando no hay datos confirmados y el cambio de día del hook tienen
pruebas separadas; no se afirma un ensayo humano ni E2E de medianoche real.

El rechazo de una jornada distinta del reloj Lima del cliente es deliberado:
falla de forma visible, sin reutilizar la foto anterior. Un equipo con fecha
local incorrecta debe corregirla; no se afirma una fuente de tiempo central
nueva ni se cambia el reloj de evaluación del servidor.

No se hizo segunda consulta: las correcciones tienen evidencia local. Los
resultados integrales definitivos y sus límites figuran en el acta H4.

## Dictamen íntegro

VERDICT:
CHANGES_REQUESTED

SUMMARY:
El núcleo de H4 es sólido y no encontré ningún P0 ni P1 en la evidencia adjunta:

- Las acciones reconocer/posponer siguen controladas por el servidor, sin estado optimista.
- `abrirRegistro` se valida ahora contra la foto vigente (`gestion-diaria-avisos-provider.tsx:47`).
- El aislamiento por día está en la clave de la query y en `queryFn` (`gestion-diaria-seguimiento-queries.ts:24-28`).
- La lista, el popup y la campana comparten `MiembrosAvisoCorte`.
- El foco tras la acción se rescata sin robarlo.

Hay cuatro hallazgos P2 accionables:

- un falso error cuando el servidor no envía `diarias`;
- una violación de *label-in-name* en el botón de la franja;
- un riesgo del mock E2E ante relojes simulados;
- un cambio de alcance no declarado en el botón «Actualizar».

Se suman algunos P3 de accesibilidad y pulido.

FINDINGS:

**[P2] «Otros pendientes» muestra un error permanente cuando `diarias` falta legítimamente**
File: `src/components/gestion-diaria/alertas-del-dia.tsx`
Lines: 11-14
Problem: la condición `cortes?.error || !cortes?.datos?.diarias` trata la ausencia de `diarias` como fallo. El texto dice «No pudimos confirmar los otros pendientes… Esto no significa que no haya avisos» y ofrece un botón de reintento.
Evidence:
- `AvisosCortesSchema` declara `diarias: v.optional(...)` (`gestion-diaria-avisos.ts:46`). La ausencia es un contrato válido, por ejemplo con servidores anteriores o con el mock legado de `_helpers.ts:2997`, que no incluye `diarias`.
- `AlertasCRMProvider` contempla ese caso y cambia al resumen SLA: `consultarResumen = sesionAvisosReal && !(rol === 'supervisor' && diarias)` (`alertas-provider.tsx:132`, `:229-238`).
- La franja también lo contempla y omite el contador (`franja-cortes-supervisor.tsx:30`).
- Antes, el componente devolvía `null`.
Impact:
- El supervisor ve un error persistente que el reintento no puede resolver.
- Las alertas operativas del resumen SLA aparecen en la campana pero no en la pestaña, así que las dos superficies muestran listas distintas. Eso contradice «Lista y campana comparten el mismo libro» (línea 7).
Recommendation:
- Distinguir tres casos: `cortes.error` (mostrar el error actual), `cargando` y datos sin `diarias`.
- Para datos sin `diarias`, renderizar la lista de `estado.alertas` que ya consume la campana, o un mensaje neutro que no hable de fallo.
- Añadir un test unitario con `datos` válidos y sin `diarias/contexto`.

**[P2] El nombre accesible del botón de la franja no contiene su texto visible (WCAG 2.5.3, Label in Name)**
File: `src/components/gestion-diaria/franja-cortes-supervisor.tsx`
Lines: 19-21
Problem: el texto visible es «Cortes y avisos», pero `aria-label` es «Cortes de llamadas y otros avisos». La cadena visible no aparece de forma contigua en el nombre accesible.
Evidence: la línea 19 define `aria-label="Cortes de llamadas y otros avisos"` y la línea 20 muestra el texto `Cortes y avisos`. El E2E localiza el botón por el aria-label (`gestion-diaria-cortes.spec.ts:55`, `:168`), por lo que no detecta el problema.
Impact: un usuario de control por voz que diga «pulsar Cortes y avisos» puede no activar el botón. Es exactamente el caso que protege la regla, y ahora que el linter no vigila esto, el revisor a11y es el gate.
Recommendation:
- Opción preferida: quitar el `aria-label` y dejar que el texto visible sea el nombre. El título del diálogo ya da el contexto completo.
- Alternativa: un nombre que empiece por el texto visible, por ejemplo `aria-label="Cortes y avisos: cortes de llamadas y otros avisos"`.
- En ambos casos, ajustar los locators del E2E.

**[P2] El mock legado ahora depende del reloj real de Node, mientras la app usa el reloj simulado del navegador**
File: `e2e/_helpers.ts`
Lines: 2997-2998 (diff)
Problem:
- El mock devuelve `dia` con `new Date()` evaluado en el proceso de Node de Playwright.
- `useAvisosCortes` rechaza ahora cualquier `datos.dia !== fechaLima(useAhora())` con `GESTION_DIARIA_JORNADA` (`gestion-diaria-seguimiento-queries.ts:27`).
- Si un spec instala `page.clock` en otra fecha, el navegador calcula otro `hoy`.
Evidence:
- El nuevo spec evita el problema porque usa `fechaLima(Date.now())` (`gestion-diaria-cortes.spec.ts:9-10`).
- Las suites históricas que usan `montarBackendReal` con `page.clock.install` en una fecha fija no lo evitan.
- El comentario de las líneas 2994-2995 dice que conservan el modo legado.
- La suite Docker completa (272 tests) todavía no ha terminado, así que esto no está verificado.
Impact:
- En esas suites, los avisos pasan a error.
- `AlertasCRMProvider` añade «No se pudieron confirmar los avisos de Gestión Diaria» a `errores` (`alertas-provider.tsx:509`).
- La campana y otras aserciones cambian: son fallos o flakes que no tienen relación con el producto.
Recommendation:
- Esperar el resultado completo de los 272 tests antes de cerrar.
- Si falla algún spec con reloj fijo, derivar `dia` y `generado_en` del reloj de la página, por ejemplo leyendo `Date.now()` con `page.evaluate` al montar, o aceptar un override de `dia` en `montarBackendReal`.

**[P2] «Actualizar» de Gestión Diaria ahora recarga todo el store del CRM (cambio de alcance no declarado)**
File: `src/screens/gestion-diaria/supervisor.tsx`
Lines: 134
Problem: el botón pasó de `avisos?.recargar()` a `alertas.reintentar()`. Para un supervisor real, `reintentar` ejecuta varias cosas, incluido `recargar()` de `useCRMData`:
- `cortes?.recargar()`;
- `recargar()` de `useCRMData`, es decir, el store completo;
- `reconocimientos.refetch()`;
- `setActualizandoOperativo(true)`.
Evidence:
- La rama `esRolOperativo(rol) && !yo?.demo` está en `alertas-provider.tsx:454-468`.
- El botón solo se deshabilita con `consulta.enVuelo` (el equipo), no mientras dura la recarga operativa.
- El E2E cuenta `estado.lecturas` de avisos, pero no mide las lecturas del store.
Impact:
- Tráfico adicional en cada pulsación.
- Parpadeo de «Actualizando otros avisos…» en la franja y ocultación temporal del estado vacío en `AlertasDelDia:24-26`, porque `cargando` pasa a true.
- Si la recarga del store es cara, pulsaciones repetidas acumulan peticiones.
Recommendation:
- Si el objetivo era refrescar solo avisos y libro, llamar `avisos?.recargar()` y un refetch explícito del libro, en lugar de `reintentar` completo.
- Si la recarga total es intencional, documentarla y deshabilitar el botón mientras `alertas.cargando` sea true.

**[P3] Doble anuncio del estado del corte tras una acción**
File: `src/components/gestion-diaria/acciones-corte.tsx`
Lines: 18, 30
Problem: tras el éxito, el `<p>` cambia de texto dentro de una región `aria-live="polite"` y además recibe el foco (`estado.current.focus()`).
Evidence: la línea 30 declara `aria-live="polite"` con `tabIndex={-1}`, y el rescate de la línea 18 enfoca ese mismo nodo.
Impact:
- Los lectores de pantalla leen el nuevo estado dos veces.
- El aria-live también anuncia cambios de otras sesiones en cada refetch de 60 s, en todas las instancias montadas: la lista, el popup y `#/alertas`.
Recommendation: elegir un solo mecanismo. Lo más simple es mantener el foco y quitar `aria-live`; el `role="status"` de «Confirmando…» ya cubre el progreso.

**[P3] El marcador `+`/`−` generado por CSS entra en el nombre accesible del `summary` y puede duplicar el marcador nativo**
File: `src/screens/gestion-diaria/supervisor.css`
Lines: nuevas reglas de `.gd-resultado-corte summary::before`
Problem:
- En Chromium, `content:'+'` se incluye en el nombre accesible («más Primer corte · 11:30…»), además del estado expandido nativo.
- Con `display:flex` no se suprime explícitamente `::-webkit-details-marker`. Hipótesis: en WebKit podría verse un segundo marcador.
Recommendation:
- Usar `content:'+' / ''` y `content:'−' / ''`.
- Añadir `list-style:none` y `summary::-webkit-details-marker{display:none}`.
- Verificar el resultado en Safari.

**[P3] El contador de la franja parpadea con cada refetch del libro**
File: `src/components/gestion-diaria/franja-cortes-supervisor.tsx`
Lines: 30
Problem: `otros.cargando` incluye `reconocimientos.isFetching` (`alertas-provider.tsx:495`). En cada refetch en segundo plano o al recuperar el foco de la ventana, «Otros avisos: N» se sustituye por «Actualizando otros avisos…», que es una cadena de otra longitud dentro de una franja de 44 px con `flex-wrap`.
Recommendation: mostrar el texto de carga solo si todavía no hay dato confirmado, y mantener el último conteo durante los refetch.

TEST GAPS:
- No hay test de `AlertasDelDia` ni de la franja con `datos` válidos y sin `diarias/contexto` (ver el primer P2).
- Falta una aserción de *label-in-name* para el botón de la franja; basta un `getByRole('button', { name: /Cortes y avisos/ })`.
- Falta un caso de rollover de medianoche con el popup abierto. El test actual (`queries.test.tsx:53`) cubre el hook, pero no el cierre del popup en el provider cuando `datos` pasa a `null`.
- Falta comprobar que no quedan consumidores de `seguimientoKeys.avisos(id)` sin día que usen `getQueryData`/`setQueryData`, que ya no coincidirían. `invalidateQueries` sí sigue funcionando por prefijo. Es una hipótesis: conviene que Codex haga un grep.
- Falta un test de `alNavegar` cuando `destino.vista` es la vista actual, donde el hash no cambia y solo se limpia la selección.

ARCHITECTURE RISKS:
- `useAvisosCortes` introduce una dependencia del reloj del cliente (`fechaLima(useAhora())`) para aceptar una respuesta del servidor. Con un reloj local desviado un día, los avisos quedan en error permanente hasta que se corrija el reloj. Es aceptable si el objetivo es fallar de forma visible, que es lo que ocurre, pero conviene documentarlo como decisión consciente.

REGRESSION RISKS:
- Suites E2E legadas con reloj fijo (ver el tercer P2); sigue pendiente la suite de 272 tests.
- El botón «Actualizar» ahora recarga el store completo (ver el cuarto P2).

SECURITY RISKS:
- No encontré ninguno nuevo. Los permisos (`habilitada`, `SIN_PERMISO`, `sinPermiso`/42501) no cambian, y el nuevo guard de `abrirRegistro` reduce la superficie para aperturas sobre fotos obsoletas.

RECOMMENDED NEXT ACTIONS:
1. Corregir el fallback de `AlertasDelDia` cuando falta `diarias` y añadir su test.
2. Alinear el nombre accesible del botón de la franja con su texto visible y ajustar los locators.
3. Esperar el resultado de la suite Docker completa. Si falla algún spec con reloj fijo, derivar `dia` del reloj de la página en `_helpers.ts`.
4. Decidir si «Actualizar» debe recargar el store y, según eso, restringir la llamada o deshabilitar el botón durante la recarga.
5. Opcional: aplicar los P3 de aria-live, el marcador de `summary` y el parpadeo de la franja.

CONFIDENCE:
MEDIUM. Es alta para los hallazgos de `AlertasDelDia`, label-in-name y la cadena de `reintentar`, que se siguen directamente del código adjunto. Es media para el riesgo del E2E, que depende de specs no adjuntados, y para el comportamiento del marcador en WebKit.

