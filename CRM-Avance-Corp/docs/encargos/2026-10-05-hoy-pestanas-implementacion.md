# HOY del analista: agenda, recibidos y aviso numérico

Estado: implementado y verificado localmente. Esta revisión visual aún no está
publicada. La versión productiva previa es `a98cf73f` (bloque sobre citas).

## Comportamiento aprobado

- «Tu agenda de hoy» y «Leads de hoy» alternan la tarjeta izquierda. Citas ocupa
  toda la columna derecha; cumplimiento continúa debajo de la izquierda.
- La pestaña muestra el total recibido HOY por el analista, obtenido del resumen
  de la misma consulta paginada. No significa «sin leer» ni «sin gestionar».
- Si hay recibidos, el número aparece blanco sobre naranja y da dos latidos
  breves cada 30 s. Abrir la pestaña o la ficha NO elimina el aviso, por petición
  explícita de Miguel. Se reinicia al cambiar total, día o pestaña.
- La consulta permanece montada mientras se ve la agenda, con un solo sondeo
  cada minuto visible. La caché conserva los refrescos de foco/reconexión.
- Filtro por analista y fecha de recepción en Lima, no por creación ni etapa.
  Incluye los recibidos del día ya gestionados/convertidos/descartados. El total
  incluye páginas aún no abiertas. El cambio de día renueva la consulta.
- Carga/error no se presentan como cero. Cero confirmado se muestra neutro.
  Movimiento reducido conserva color sin latido. En móvil las etiquetas se
  acomodan en dos líneas para conservar visible el número.

## Implementación

`AgendaLeadsHoy` mantiene una consulta compartida con `useLeadsRecibidosHoy` y
entrega la misma respuesta a `ListaLeadsRecibidosHoy`. Se reutiliza `Tabs` con su
teclado y accesibilidad. `LeadsRecibidosHoy` conserva el wrapper independiente
para el modo legado/degradado de SLA. No hay cambios de backend, permisos,
dependencias ni persistencia de lectura. Los controles de simulación y los
fixtures de la propuesta no forman parte del producto.

Fuente aislada: `/private/tmp/avancecorp-hoy-20261005-release`, misma rama de
la PR #191. Cambios trasladados mediante parche al taller original, preservando
sus modificaciones e historial ajenos. No se cambió el Main local divergente.

## Verificación

- PASS `npm run check`: 6.096 tests / 378 archivos, lint, typecheck, cobertura,
  configuración de release, build, bundle y duplicación (0,44 %).
- PASS dirigidas: 76 tests en la fuente actual. Taller original: 63 tests y
  typecheck, por diferencias previas de versiones; no se sobrescribieron.
- PASS Docker local: 26/26 (`hoy-leads-recibidos`, `demo-roles`, `sla-operacion`).
  Tras el ajuste final de móvil: 2/2 HOY, build y verify:bundle PASS.
- PASS capturas escritorio/portátil/móvil: columna de citas idéntica antes y
  después de cambiar de pestaña; lista útil de citas >=200px en portátil;
  contador dentro de la franja móvil. Navegación por teclado y foco paginado.
- PASS recorridos de error/vacío, nuevas asignaciones con agenda abierta,
  cambio de día de Lima y de analista, total más allá de primera página, mantener
  aviso al abrir ficha, reduced motion y no duplicar consultas/intervalos.
- PASS `git diff --check`.
- NOT RUN gate de realidad hospedado: `SUPABASE_URL` ausente en el entorno.
  El contrato de recepción no cambia; se verificó read-only con un analista en
  la publicación anterior del mismo día. No se afirma una sesión productiva de
  analista para esta revisión.

El primer check general tuvo un fallo de arranque de un worker de jsdom
(`Range`, módulo ajeno a HOY). Ese módulo pasó 6/6 aislado y la repetición
integral pasó sin errores. Cuatro avisos de lint previos en coverflow y aviso
de tamaño de chunks permanecen fuera de alcance.

La vista local `http://127.0.0.1:5187/#/hoy` sirve esta implementación con datos
demo y un adaptador local de SLA activo. Ese adaptador solo afecta al servidor
de desarrollo; no se distribuye en el bundle. Capturas en
`app/artifacts/hoy-implementacion/`.

## Revisión independiente

El primer intento mediante `scripts/claude-review` no entregó un VERDICT válido
y no se contó como aprobación. El único reintento, con evidencia acotada y el
CSS móvil final, entregó **PASS**, sin defectos obligatorios.

Decisiones del PRIMARY sobre sus observaciones P3:

- Aceptada: el sondeo ahora espera mientras se carga otra página, para no
  cancelarla ni perder el foco de las filas nuevas. Prueba dirigida añadida y
  PASS; recargar manual ya tenía esta protección.
- Se conserva refrescar todas las páginas cargadas. Mantiene coherencia de
  lista y cursores cuando llegan asignaciones; el volumen diario es acotado.
  Pedir solo un resumen separado duplicaría el estado/contrato de esta entrega.
- La hipótesis de estirar la tarjeta vacía no aplica: `CitasAnalista`, líneas
  334–336, conserva `lg:self-start` cuando no hay citas. El E2E cubre ese fixture;
  se añadió aserción de `align-self: flex-start` y captura explícita.
- Las limitaciones sobre `vivos`, rama legada y Tabs se contrastaron con el
  contrato existente, fuente local y pruebas, no con la opinión del reviewer.

Review completo guardado en `docs/encargos/2026-10-05-hoy-pestanas-review.txt`.

## Integración y publicación

PR: https://github.com/avanza-digital/avancecorp-crm/pull/191. GitHub requiere
aprobación externa; Miguel indicó que la gestionaría. No se eluden protecciones.
La implementación aprobada está preparada para esa integración. La publicación
de esta revisión sigue pendiente y debe construirse desde el commit autorizado
y verificado conforme a las reglas del proyecto.
