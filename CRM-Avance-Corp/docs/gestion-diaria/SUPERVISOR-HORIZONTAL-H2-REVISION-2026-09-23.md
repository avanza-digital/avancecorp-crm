# Supervisor horizontal — revisión H2

23/09/2026 · Codex PRIMARY → Claude SECONDARY_REVIEWER, wrapper `scripts/claude-review`.
Un review completado. El primer intento no finalizó en el sandbox; se repitió
la misma evidencia con el wrapper autorizado. No se cambiaron MCP ni ajustes.

**Dictamen original: CHANGES_REQUESTED; confianza MEDIUM.** Sin P0/P1.
No se presenta el dictamen de Claude como PASS. Codex resuelve con pruebas.
**VERIFICADO:** gate integral PASS (4.192 tests) y E2E final Docker 29/29;
la corrida completa inicial y sus tres fallos repetidos se documentan en el acta H2.

## Resolución de Codex

| Observación | Decisión y evidencia |
|---|---|
| P2 foco modal → región | La hipótesis no se reprodujo en el test unitario agregado sobre el código anterior. Se reforzó igualmente la captura mediante `focusin` sobre el destino estable, antes del desmontaje; E2E comprueba Restaurar y 390→1512 manteniendo el selector y las 26 filas. |
| P2 nombres en spans genéricos | Aceptado. Contexto de contacto y motivos son texto `sr-only`, con tasa/nivel visibles y prueba de presencia. El nuevo test falló antes del cambio y pasa tras aplicarlo. |
| P3 Con pendientes | No cambia la definición. `resumenEquipo` y H1 cuentan personas con tareas o primer intento vencido. El filtro usa exactamente ese OR. Prueba de tareas 0 + señal 3 y distinción de unidades en el panel. |
| P3 pedido tras revocación | Aceptado. Se consume el evento ante 42501; prueba de recuperación sin reapertura. Un fallo de red aún espera la lectura autorizada. |
| P3 encabezados/etiquetas | Un solo `Dialog.Title` visible dentro del portal, compartido por región/modal; cierre auxiliar distingue Información/Avisos. Ampliar se ofrece cuando puede cambiar la presentación (escritorio). |
| P3 altura del shell | Se documenta 64 px de Topbar + 48 px de padding junto al presupuesto CSS. Pruebas DOM contra scroll de página, controles y filas; viewport bajo usa flujo vertical. |
| Gap aviso→registro | Reproducido y resuelto: el cierre del diálogo auxiliar enfoca el título nuevo después de retirar su trampa. Prop opcional `focoAlCerrar` en Dialog, predeterminado compatible; prueba con aviso válido y banco previo de diálogos anidados. |
| Gap actualización/permisos | Pruebas: la carga inicial no recarga; actualizar conserva filtros, reinicia cursor y recarga una vez; 42501 limpia filas y notifica una vez para revalidar equipo. |
| Gap empates atención | Prueba de ambas direcciones: motivos como clave, vencidas descendentes y nombre/id ascendentes como desempate. |

Comprobaciones finales y medidas: [acta H2](SUPERVISOR-HORIZONTAL-H2-EVIDENCIA-2026-09-23.md).
Sin segunda consulta: observaciones resueltas mediante evidencia y gates del PRIMARY.

## Dictamen recibido

VERDICT:
CHANGES_REQUESTED

SUMMARY:
La arquitectura de H2 cumple lo que declara. El portal DOM estable se mueve entre la ranura en línea y `Dialog.Content`. La identidad de selección tiene dos niveles de `key`. El error de red conserva el Registro, y la revocación (42501) o la salida del equipo lo cierra. La evidencia E2E y unitaria cubre bien densidad, reflow, trampa de foco y la ficha del lead anidada.

No encontré P0 ni P1. Pido cambios por dos P2 accionables:
1. Al pasar de diálogo a panel en línea (Restaurar o ensanchar la ventana) el foco se pierde con alta probabilidad. No hay test que lo cubra.
2. Los motivos y el contexto de Contacto de la tabla solo existen como `aria-label` sobre `<span>` genérico, que no tiene nombre accesible fiable.

El gate completo (`npm run check`) sigue pendiente tras los últimos cambios, y `gate:realidad` no se ejecutó.

FINDINGS:

[P2] Pérdida de foco al volver de modal a en línea (Restaurar panel o ventana que se ensancha)
File:
src/components/gestion-diaria/panel-supervisor-adaptable.tsx
Lines:
23-40, 43, 46, 58
Problem:
`focoInterno` solo se captura dentro de `mover()`, y `mover()` corre en el ref callback `alojarEnLinea`. En la transición `modal: true → false` ocurren varias cosas en el mismo commit:
- Radix desmonta `Dialog.Content`. No hay animación de salida en `.gd-panel-modal`, así que `Presence` lo quita de inmediato.
- Ese desmontaje ocurre en la fase de mutación. El nodo de Content sale del documento y se lleva `destino` con el botón enfocado dentro.
- El nuevo ref `alojarEnLinea` (su identidad cambia con `modal`) se adjunta en la fase de layout, es decir, después.

Cuando `mover()` consulta `document.activeElement`, el botón «Restaurar panel» ya está desconectado y `activeElement` es `body`. Por eso `focoInterno` queda en `null` y el `useLayoutEffect([modal])` (líneas 35-40) no restaura nada. `onCloseAutoFocus` está prevenido (línea 58), así que Radix tampoco devuelve el foco.
Evidence:
- El razonamiento anterior sobre el orden de commit de React 19 (detach/eliminación en mutation, attach de refs en layout).
- Ningún test verifica el foco tras restaurar. En `supervisor.test.tsx` el caso «Registro monta al visitarlo…» pulsa `Restaurar panel` y solo compara la identidad del botón `Página 2`. En el E2E F4.2, tras `Restaurar panel` solo se cuenta `listitem` (25).
- El caso inverso (en línea → modal) sí funciona, porque `destino` sigue en el documento cuando corre `alojarEnDialogo`.
- Hipótesis no reproducida; confianza media-alta.
Impact:
Un usuario de teclado que pulsa «Restaurar panel», o que tiene el diálogo abierto por `estrecho` y ensancha la ventana o reduce el zoom, queda con el foco en `body`. Es una regresión de gestión de foco dentro del propio ciclo de vida que H2 pretende preservar.
Recommendation:
Capturar el foco antes del cambio de estado, no en el ref:
- en `ampliar` / `onOpenChange`, o
- con un `focusout`/`focusin` que mantenga `focoInterno` actualizado mientras el foco esté en `destino`, o
- en un `useLayoutEffect` de limpieza que lea `activeElement` antes del commit siguiente.

Añadir un test unitario (jsdom ya aplica focus fixup al remover nodos) y un paso E2E que comprueben que tras «Restaurar panel» el foco queda en el mismo botón, ahora «Ampliar panel». Cubrir también la transición 756→1512 con el diálogo abierto por `estrecho`.

[P2] Motivos de atención y contexto de contacto sin nombre accesible fiable
File:
src/components/gestion-diaria/tabla-equipo-diaria.tsx
Lines:
48, 51-54
Problem:
`contextoContacto` (tasa, «x de y útiles», mínimo, nivel) y la lista de motivos (`MOTIVOS_EQUIPO[...]`) solo se exponen como `aria-label` sobre `<span>`. ARIA 1.2 prohíbe nombrar el rol `generic`, y varios lectores de pantalla ignoran ese `aria-label` en celdas de tabla. El texto visible ahora es solo «2 motivos» o «50 %».
Evidence:
- La versión anterior mostraba «Tareas vencidas» como texto: el test eliminado tenía `within(tabla).getByText('Tareas vencidas')`.
- El test nuevo ya no verifica ninguna exposición accesible de los motivos en la tabla, solo en el panel (E2E «nombre largo»).
Impact:
Los usuarios de lector de pantalla que recorren la tabla oyen «2 motivos» sin saber cuáles, a menos que seleccionen cada fila. Es una pérdida de información frente a la vista previa.
Recommendation:
Mantener el texto visible compacto y añadir un `<span className="sr-only">` con los motivos o el contexto, en lugar de `aria-label` sobre un span. Añadir una aserción unitaria del tipo `within(fila).getByText('Tareas vencidas')`.

[P3] Filtro «Con pendientes» posiblemente no coincide con el indicador «Con pendientes»
File:
src/lib/gestion-diaria-equipo.ts (diff `filtrarOrdenarEquipo`); src/screens/gestion-diaria/supervisor.tsx:132
Problem:
El filtro incluye filas con `tareas_pendientes === 0` y `primer_intento_vencido > 0`. El indicador usa `dia.resumen.con_pendientes` del servidor, cuya definición no está adjunta.

La pestaña Pendientes de esas filas dice «Sin tareas pendientes.», y la propia UI afirma que las señales de primer intento «no se suman como tareas» (panel-analista-supervisor.tsx:93). Es una hipótesis: depende de `resumenEquipo` y del RPC.
Impact:
El indicador y el resultado filtrado pueden diferir, lo que confunde al supervisor.
Recommendation:
Alinear el filtro con la definición de `con_pendientes` o renombrar la opción. Añadir un test en `gestion-diaria-equipo.test.ts` con una fila de 0 tareas y primer intento > 0.

[P3] Pedido de registro retenido indefinidamente si el equipo está revocado
File:
src/screens/gestion-diaria/supervisor.tsx
Lines:
86-97
Problem:
`if (!pedido || !dia) return` no consume el pedido cuando `dia` es `null` por 42501 o por error de red. Si luego se recupera el acceso, el registro se abre sin una acción reciente del usuario. Hipótesis de baja severidad: actor y día se validan igual.
Recommendation:
Consumir el pedido y anunciar que no está disponible cuando `sinPermiso`.

[P3] Nombres accesibles duplicados o imprecisos
File:
panel-supervisor-adaptable.tsx:59; supervisor.tsx:169
Problem:
- En modal hay dos encabezados «Detalle de X»: el `Dialog.Title` sr-only y el `h3`. El E2E necesita `.last()` para distinguirlos.
- El botón de cierre del diálogo auxiliar dice «Cerrar información» también en «Cortes de llamadas y otros avisos».
Recommendation:
- Nombrar el `Content` con `aria-labelledby` apuntando al `h3`, o mantener `Title` y retirar el encabezado visible del lector.
- Hacer que la etiqueta de cierre dependa de `auxiliar`.

[P3] Acoplamiento de altura con el shell
File:
supervisor.css:2
Problem:
`height: calc(100svh - 112px)` fija la altura del chrome de la app. Si el shell cambia, reaparece el scroll de página. Solo lo detecta el E2E (`scrollPagina ≤ 1`).
Recommendation:
Documentarlo junto al shell, o derivarlo de una variable CSS compartida.

TEST GAPS:
- Foco tras «Restaurar panel» y tras la transición `estrecho: true → false` con el diálogo abierto (ver P2).
- Pedido de registro desde el diálogo de avisos. No hay test de que el cierre de `Dialog` auxiliar no devuelva el foco a su disparador después de que `ContenidoSeleccionado` enfoque el título. Depende de la implementación de `@/components/ui/dialog`, que no está adjunta. En `estrecho` coinciden el cierre de un diálogo y la apertura de otro.
- `actualizacion`/`onSinPermiso` en `RegistroActividad`: los diffs de `registro-actividad.test.tsx` no están adjuntos. Falta confirmar que:
  - la carga inicial no dispara `recargar`,
  - «Actualizar» vuelve a la página 1 y recarga una sola vez,
  - `onSinPermiso` se llama una vez por transición.
- Tie-breakers de `orden: 'atencion'`: el empate devuelve antes del cambio de dirección. Es correcto si se busca estabilidad, pero no hay test de dirección ascendente con empates.
- Exposición accesible de motivos en la tabla (ver P2).

ARCHITECTURE RISKS:
- El modelo de «portal a nodo movido» depende del orden de commit de React y de que `Dialog.Content` no tenga animación de salida. Si se añade una animación, `Presence` mantendría Content montado y `destino` quedaría dentro del diálogo en cierre hasta el `animationend`. Conviene documentarlo en el comentario de `panel-supervisor-adaptable.tsx:6-8`.
- `onInteractOutside` con `destino.contains` es correcto y necesario: `DismissableLayer` decide «dentro» por el árbol React, y el portal no desciende de Content. Merece un test explícito de clic dentro del panel en modal que no cierre.

SECURITY RISKS:
- Ninguno nuevo. La validación del pedido (actor, día, pertenencia) es solo de presentación y la autorización sigue en RLS/RPC. `permitirExportar={false}` y `permitirEquipo={false}` se mantienen.

REGRESSION RISKS:
- Foco al restaurar (P2).
- Pérdida de información accesible en la tabla (P2).
- «Actualizar» ahora devuelve el Registro abierto a la primera página. Es intencional según el comentario de la prop, pero cambia el comportamiento percibido.

RECOMMENDED NEXT ACTIONS:
1. Corregir la captura de foco en la transición modal→en línea y añadir los tests unitario y E2E correspondientes.
2. Sustituir los `aria-label` sobre `<span>` por texto `sr-only` y afirmarlo en el test.
3. Verificar la definición de `con_pendientes` frente al filtro y ajustar con un test.
4. Ejecutar el `npm run check` completo tras los últimos cambios y reportar `gate:realidad` como no ejecutado (falta `SUPABASE_URL`).

CONFIDENCE:
MEDIUM. No pude ver `ui/dialog`, `ui/tabs`, `escape-dialogo` ni los diffs de `registro-actividad.test.tsx` y `gestion-diaria-equipo.test.ts`. El primer P2 se basa en el orden de commit de React y no se reprodujo.
