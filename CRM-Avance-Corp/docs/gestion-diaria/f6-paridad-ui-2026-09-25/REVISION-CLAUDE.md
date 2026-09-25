VERDICT: CHANGES_REQUESTED

SUMMARY:
La dirección técnica es correcta. El umbral de 960 coincide entre `usePanelGerencia` y `@container (max-width:959px)`. Anular `container-type` en `.gp-espacio>.gd-equipo` es coherente con que el ancho de la pantalla decida la composición. Las ocho comparaciones del diálogo usan los mismos campos (`d.actual`, `d.ayer.metricas`, `d.referencia.media`) y el mismo `cifraPulso` que antes.

Lo que impide `PASS`:
1. Parte del comportamiento a 1366 con el menú abierto depende del orden de carga de `supervisor.css` y `gerencia.css`, porque los selectores tienen la misma especificidad. La evidencia adjunta no muestra ese orden.
2. La nueva columna fija puede pintarse encima de la cabecera fija de `.gd-tabla`.
3. Según el propio PRIMARY, el E2E completo sigue en curso.

Límite: no puedo ver las capturas. No evalúo el resultado visual, sólo el código y las salidas descritas.

FINDINGS:

[P2] La paridad en el rango 960–1235 depende del orden de las hojas de estilo
File: CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.css y supervisor.css
Lines: gerencia.css `.gp-espacio { grid-template-columns:… }` y `.gp-indicadores dl { grid-template-columns:repeat(8,…) }`; supervisor.css `@container (max-width:1235px)`
Problem: La sección ahora lleva `gd-supervisor`, que es un contenedor. Por eso, en el rango 960–1235 se activan las reglas de `supervisor.css` dentro de `@container (max-width:1235px)`:
- `.gd-espacio { grid-template-columns:minmax(0,1fr) }` (0,1,0) compite con `.gp-espacio { … clamp(360px,30%,414px) }` (0,1,0).
- `.gd-indicadores dl { repeat(auto-fit,minmax(200px,1fr)) }` (0,1,1) compite con `.gp-indicadores dl { repeat(8,…) }` (0,1,1).
- `.gd-pulso { max-width:1640px }` (0,1,0) compite con `.gd-supervisor { max-width:1440px }` (0,1,0).

Las reglas `@container` no suman especificidad, así que gana la que aparezca después en el CSS. Sólo el alojamiento del panel se protegió con más especificidad (`.gp-espacio[data-estrecho=false]>.gd-panel-alojamiento:not([hidden])`).
Evidence: Diff de `gerencia.css` y contexto de `supervisor.css` adjunto. Los E2E a 1280 y 1366 con el menú abierto pasan, lo que sugiere que hoy `gerencia.css` se carga después. Ese orden no aparece en la evidencia.
Impact: Si cambia el orden de import o el code-splitting de Vite, vuelve exactamente el fallo reproducido: panel oculto y tarjetas en varias filas. Además, `max-width:1640` puede quedar silenciosamente en 1440.
Recommendation:
- Subir la especificidad de las tres reglas, por ejemplo con `.gd-pulso .gp-espacio`, `.gd-pulso .gp-indicadores dl` y `.gd-supervisor.gd-pulso`.
- O bien acotar la regla 1235 de `supervisor.css` con `:not(.gd-pulso)`.
- Documentar la dependencia en el comentario de cabecera del CSS.

[P2] La columna fija puede solaparse con la cabecera fija de `.gd-tabla`
File: gerencia.css, bloque `@container (min-width:840px)`
Lines: `.gp-espacio :is(.gd-tabla,.gp-tabla) th:first-child { position:sticky; left:0; z-index:1; background:inherit; }`
Problem: `supervisor.css` define `.gd-tabla thead { position:sticky; top:0; z-index:1; }`. Las celdas `th:first-child` del cuerpo también quedan posicionadas con `z-index:1`, en el mismo contexto de apilamiento. Con el mismo z-index gana el orden del DOM, así que las celdas del `tbody` se pintan encima de la cabecera al desplazar verticalmente.
Evidence: Las dos reglas citadas. En la descripción de los 11 E2E no hay ninguno que desplace la tabla verticalmente y después lateralmente.
Impact: Los nombres de las filas taparían la celda «Nombre» de la cabecera al desplazar hacia abajo. Es un defecto visual en la vista principal. Es una hipótesis de alta probabilidad; no hay reproducción.
Recommendation:
- Dar `z-index:2` a `thead` (o a `thead th:first-child`) y dejar el cuerpo en 1.
- Añadir un E2E que desplace el `.gd-tabla-scroll` en ambos ejes y compruebe con `elementFromPoint` que la cabecera queda encima.

[P3] El recuento «Con atención (N)» de analistas puede no coincidir con el filtro
File: CRM-Avance-Corp/app/src/components/gestion-diaria/espacio-pulso-gerencia.tsx
Lines: hunk @@ -110
Problem: El recuento usa `filas.filter((f) => f.requiere_atencion)`, pero el filtro real es `soloProblemas`, aplicado en `filtrarOrdenarEquipo`. La evidencia no muestra que los dos usen el mismo predicado. En cambio, en `comparacion-equipos-gerencia.tsx` el recuento y el filtro comparten `conAtencion`, que es el patrón correcto.
Impact: Si los predicados difieren, el botón anuncia N y el filtro muestra otra cantidad.
Recommendation: Confirmar que `soloProblemas` filtra por `requiere_atencion`, o calcular ambos con un único predicado exportado. Añadir un test que compare «Con atención (N)» con «N de M analistas» tras activar el filtro.

[P3] El diálogo compartido cambia de contenido mientras se cierra
File: CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx
Lines: `ResumenPulso`
Problem: `open={abierto !== null}`, y el título, la tabla y el botón dependen de `abierto`. Al cerrar la comparación, `abierto` pasa a `null` y el contenido cambia de inmediato a «Fechas y definiciones del pulso».
Impact: Si `Dialog` tiene animación de salida, el usuario ve un parpadeo con el contenido equivocado. Es una hipótesis: no se adjunta el componente `Dialog`.
Recommendation: Guardar el último contenido en un estado separado del `open`, o usar dos `Dialog` independientes.

[P3] Posible falta de foco visible en la región del diálogo
File: gerencia.tsx y gerencia.css
Problem: La regla de foco `.gd-pulso :is(…,[tabindex]):focus-visible` no alcanza al diálogo si este se renderiza en un portal. En ese caso, la región `tabIndex={0}` «Desplazar comparación de días» depende del outline por defecto del navegador. Es una hipótesis que depende de un posible reset global de `outline`.
Recommendation: Añadir `.gp-definiciones [tabindex]:focus-visible` a la regla de foco, o verificarlo en el E2E de teclado.

[P3] Mutación del fixture compartido en el test
File: CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.test.tsx
Lines: `pulso.datos!.actual = { ...pulso.datos!.ayer.metricas }`
Problem: El test asigna directamente sobre el fixture del módulo. La evidencia no muestra un `beforeEach` que lo restaure.
Impact: Si no se restaura, los tests posteriores del archivo heredan el estado de cero actividad y dependen del orden de ejecución.
Recommendation: Confirmar que existe la restauración, o clonar el fixture dentro del test.

[P3] Mantenimiento del CSS
File: gerencia.css
Problem: `.gp-cabecera { gap:8px }` repite y sobrescribe `.gp-cabecera,.gp-cabecera-fila { gap:8px 16px }`. Además, el aviso «Hoy en curso» ya no aparece en el resumen visible, sólo dentro del diálogo.
Recommendation:
- Unificar las dos reglas de `gap`.
- Confirmar con producto que basta mostrar «Hoy en curso» en el diálogo, ya que las cifras principales del día en curso aparecen sin ese aviso.

TEST GAPS:
- Falta un E2E justo en el umbral: contenedor de 960 px con el panel inline y 8 columnas en una fila, y de 959 px con el panel modal y 4 columnas.
- Falta un E2E de desplazamiento horizontal y vertical que verifique la columna fija y la cabecera (P2 anterior).
- Falta una verificación de que el recuento de «Con atención» coincide con las filas filtradas, tanto en equipos como en analistas.
- Falta el E2E completo, que sigue en curso. `gate:realidad` no se ejecutó; es aceptable al no haber cambios de SQL ni datos, pero hay que declararlo en la entrega.

ARCHITECTURE RISKS:
- Gerencia reutiliza `gd-supervisor` pero neutraliza sus container queries mediante el orden de la cascada. Cualquier cambio futuro en `supervisor.css` (breakpoint 1235, `.gd-indicadores dl`) afectará a gerencia sin que nadie lo note. Conviene un contrato explícito: selectores con más especificidad o una variante con modificador `.gd-supervisor--gerencia`.

SECURITY RISKS:
- Ninguno dentro del alcance. No hay cambios de SQL, RPC, auth ni permisos.

REGRESSION RISKS:
- Supervisor: el diff no toca `supervisor.css`, así que el riesgo es bajo.
- Gerencia con viewport de 651–750 px de alto: el media query pasó de `max-height:750px` a `650px`. Ahora se mantiene la altura fija, y el cuerpo de la tabla queda en unos 270–340 px. Los E2E a 1366x768 pasan, pero 1280x700 no se probó.
- Los selectores de tests o E2E que usaban los textos antiguos de los checkboxes («Con vencidas o sin actividad», «Requieren atención») deben estar actualizados. Los tests en verde indican que sí.

RECOMMENDED NEXT ACTIONS:
1. Eliminar la dependencia del orden de carga en las tres reglas del P2.
2. Corregir el z-index entre la cabecera fija y la columna fija, y añadir un E2E de desplazamiento en ambos ejes.
3. Terminar el E2E completo y confirmar el predicado de `soloProblemas` y la restauración del fixture antes de declarar DONE.

CONFIDENCE:
MEDIUM. Sin acceso al orden real de import de las hojas de estilo, al componente `Dialog`, a `filtrarOrdenarEquipo` ni a las capturas.
