VERDICT:
CHANGES_REQUESTED

SUMMARY:
Las tres correcciones pedidas están bien resueltas en la ficha. La continuidad etiqueta activo o registrado por par empresa/moneda, la tarjeta compacta muestra la anulación y el PDF pendiente, y el nombre accesible empieza con el texto visible. Quedan dos problemas accionables:
1. Mantener `PostventaPersona` montado de forma permanente conserva la acción elegida cuando F6 se retira. El diálogo se vuelve a abrir solo cuando F6 se recupera.
2. `ResumenEmpresas` sigue usando la etiqueta por empresa que se corrigió en la continuidad.

FINDINGS:

[P2] El diálogo de postventa reaparece solo tras una caída o desactivación de F6
File: CRM-Avance-Corp/app/src/components/app/postventa-persona.tsx
Lines: 41, 45-47, 69; inversionista-ficha.tsx 139, 287-288
Problem: El diálogo se cierra por `habilitada=false`, pero la acción elegida no se limpia. Cuando `habilitada` vuelve a ser `true`, el diálogo se abre de nuevo sin que el usuario lo pida.
Evidence:
- `open={habilitada && actual !== null}` (l.69).
- `actual` sale de `retiroElegido ?? accion` (l.46). Ambos solo se limpian en `cerrar()` (l.47), que el cierre por `habilitada=false` no llama.
- `refetchInterval: 15_000` y `retry: false` (postventa-queries.ts l.8): un solo fallo de red deja `isSuccess=false`.
- La nueva garantía de "siempre envuelve el mismo árbol" hace que `accion` sobreviva al paso de `capacidades.postventa` de true a false y de vuelta a true (test l.132-152). Antes, un desmontaje la habría reiniciado. Hipótesis sobre el comportamiento anterior; no está en la evidencia.
- `retiroElegido` vive en `InversionistaFicha`, que no se desmonta.
Impact:
- Pasos: el usuario abre "Agendar gestión" o "Revisar solicitud", ocurre un corte F6 y el diálogo se cierra. Hasta 15 s después, o al pulsar Reintentar, el diálogo reaparece.
- En `revisar_retiro` se abre con el `retiro.revision` anterior, así que el servidor lo rechazaría como obsoleto.
- El usuario percibe que el texto escrito se perdió (el hijo se desmontó) y luego ve un modal inesperado, que además desplaza el foco.
- Los tests nuevos afirman conservación de foco/detalle, pero ninguno tiene un diálogo abierto durante el corte.
Recommendation:
- Limpiar `accion` y llamar `onRetiroCerrado()` cuando `habilitada` pase a `false`, con un efecto sobre `habilitada` o derivando una clave de apertura.
- Añadir un test: abrir "Agendar gestión", invalidar con rechazo F6, recuperar y verificar que no hay `dialog` y que el foco no se movió.
- Si `ocupado` es `true` al caer F6, conviene decidir explícitamente qué pasa. El cierre en sí es preexistente según PRIMARY; no se pide cambiar Dialog.

[P2] `ResumenEmpresas` sigue etiquetando por empresa, no por el dato mostrado
File: CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx
Lines: 28-30
Problem:
- El valor usa `t.capital_activo ?? t.capital_registrado`, pero la etiqueta usa `t.empresa === 'avance' ? 'Capital activo' : 'Capital registrado'`.
- Un total Avance con `capital_activo: null` muestra el capital registrado bajo "Capital activo".
- Una cooperativa con `capital_activo` no nulo muestra el activo bajo "Capital registrado".
Evidence:
- La continuidad (l.209) ya usa la condición correcta, `t.capital_activo !== null`. Es la misma corrección pedida en la primera revisión, aplicada solo a una de las dos vistas de totales.
- El test l.88-98 solo inspecciona la región de continuidad.
Impact: En la vista que consuma `ResumenEmpresas` (exportado; probablemente la cartera), un importe registrado se presenta como activo. Es información financiera mal rotulada, aunque no cambia ningún número.
Recommendation: Usar en l.30 la misma condición que en l.209. Cubrir con un test de `ResumenEmpresas` o de la cartera con Avance `capital_activo: null`.

[P3] "registro N de esta página" describe la posición dentro del grupo, no dentro de la página
File: CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx
Lines: 65, 247
Problem: `posicion` es el índice dentro de `grupos` (empresa:moneda). Dos grupos distintos tienen cada uno un "registro 1 de esta página".
Evidence: `inversiones.map((i, posicion) => … posicion={posicion + 1}` dentro de cada grupo.
Impact: El nombre sigue siendo único porque incluye empresa y moneda, pero el texto es impreciso para lectores de pantalla.
Recommendation: Redactar como "registro N de Qorilazo PEN en esta página", o no hacer nada. Tampoco hay test del caso sin `numero`.

[P3] Hipótesis: "Recuperar PDF pendiente" no está condicionado por capacidades ni por demo
File: CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx
Lines: 76, 117, 249
Problem: Ahora el botón está visible en la tarjeta compacta. Solo depende de `!desactualizada` y de `i.pdf?.reintentable`, no de `capacidades.documentos`/`nueva_inversion` ni de `i.es_demo`.
Evidence: `onRecuperarPdf={!desactualizada ? onRecuperarPdf : undefined}`. En cambio, documentos y operaciones sí se condicionan por capacidades (l.248, l.250).
Impact: Si el condicionado no cambió respecto a la versión anterior, solo aumenta la exposición visual. La autorización debería seguir en servidor. Confianza baja: no hay diff previo adjunto.
Recommendation: Confirmar que el gating de esta acción no cambió y que el RPC la autoriza. Si no es así, condicionarla igual que `onOperacion`.

TEST GAPS:
- Diálogo F6 abierto durante un corte y posterior recuperación: no debe reabrirse.
- `ResumenEmpresas` con Avance `capital_activo: null` y cooperativa con activo no nulo.
- Nombre accesible sin `numero` y con dos grupos en la misma página.
- El gate total + E2E final sigue en ejecución y su salida no está adjunta. `ficha-multiempresa-visual.spec.ts` y el E2E reforzado de f6-postventa no se incluyeron, así que no pude revisarlos.

REGRESSION RISKS:
- Un árbol persistente conserva cualquier estado local de `PostventaPersona` a través de cambios de habilitación. Hoy afecta a `accion`; futuros estados locales heredarán el mismo riesgo.

SECURITY RISKS:
- No hay cambios observables en la frontera REST/SQL. Solo queda la hipótesis P3 sobre el condicionado de Recuperar PDF.

RECOMMENDED NEXT ACTIONS:
1. Limpiar `accion`/`retiroElegido` al perder `habilitada` y añadir el test de no reapertura.
2. Alinear la etiqueta de `ResumenEmpresas` con `capital_activo !== null` y cubrirla con un test.
3. Confirmar que el condicionado de Recuperar PDF no cambió y adjuntar el resultado del gate final antes de declarar DONE.

CONFIDENCE:
MEDIUM
