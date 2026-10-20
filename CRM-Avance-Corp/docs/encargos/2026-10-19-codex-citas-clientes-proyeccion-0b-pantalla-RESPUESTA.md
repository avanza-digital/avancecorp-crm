**VERDICT: REQUEST_CHANGES**

**SUMMARY:** La separación aritmética del diff respeta las reglas: las reuniones no alteran ticket, conversión ni proyectado; compartir identidad con un lead tampoco las incorpora al cierre de ventas. Encontré tres problemas de carga/refresco.

**FINDINGS P0–P3**

1. **P2 — La entrada a Proyección permite un render con cifras parciales.** En [citas-gerencia.tsx:44](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx:44), el proveedor omite `proyeccion` mientras `mesesProyeccion` está vacío. Entretanto, [proyeccion-hoja.tsx:124](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx:124) interpreta su ausencia como datos preparados y usa las citas mensuales. **Caso:** mes ya cargado, tres citas con lead y dos reuniones aún sin solicitar; al entrar queda habilitada una hoja con tres citas hasta que los efectos registren meses/rango. La pintura efectiva depende del calendario de React, pero el estado parcial existe. Debe distinguirse «cargador todavía no solicitado» de «fuente demo sin cargador».

2. **P2 — «Actualizar» no refresca las reuniones después de una carga exitosa.** [use-datos-citas-gerencia.ts:91](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts:91) llama a `consulta.refetch()` únicamente si `consulta.isError`; el reintento mensual también selecciona solo errores. **Caso:** otro analista registra una reunión después de cargar la hoja; pulsar «Actualizar» no solicita ninguna lectura exitosa y deja las cifras anteriores hasta otro disparador. El [test de Actualizar:413](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx:413) solo comprueba la invocación de un `vi.fn()`: no demuestra que recargue datos.

3. **P2 — Los rangos rechazados siguen reconsultándose automáticamente.** [citas-clientes-proyeccion.ts:138](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.ts:138) desactiva intervalo y reintentos para `54000`/`57014`, pero hereda `refetchOnWindowFocus: true` y `refetchOnReconnect: true` de [citas-gerencia.ts:210](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/data/citas-gerencia.ts:210). **Caso:** primera lectura termina en `57014`, sin datos; recuperar foco o conexión puede iniciar otra consulta del mismo rango. `retry: false` no impide esos nuevos ciclos. Esto contradice «no se reintenta ni se refresca solo».

**TEST GAPS**

- Falta integrar pantalla, proveedor y opciones reales para comprobar entrada inicial, «Actualizar» y eventos de foco/conexión. Los tests del hook sustituyen precisamente las opciones de caché y cadencia.
- Los fixtures usan IDs distintos entre lectores. No demuestran exclusión real entre ambos RPC. Con el contrato suministrado **no afirmo que haya duplicación**, pero tampoco la descarto mediante evidencia del servidor.
- Falta comprobar cargas desde caché con cortes distintos y refrescos solapados: `listo` exige datos disponibles, pero no considera `isFetching`.

**NEXT ACTIONS**

Corregir los tres puntos y añadir comprobaciones de integración que fallen con las rutas actuales.

Sobre **Proyectado**: usar 66,7 % de entrevistas con lead mientras la columna muestra 60 % es defendible y cumple la decisión del dueño. Sí puede confundir: conviene exponer «Proyectado sobre citas con lead» y su tasa/base en la ayuda del cálculo; igualmente, aclarar el denominador de Ticket. No cambiaría la fórmula para usar el 60 %. El material adjunto no acredita esa explicación visible.

**CONFIDENCE:** Alta en los defectos de refresco y la separación matemática; media en la visibilidad del render transitorio. Revisión estática del material adjunto. Pruebas, mutantes, E2E y checks: **NOT RUN por mí**.
