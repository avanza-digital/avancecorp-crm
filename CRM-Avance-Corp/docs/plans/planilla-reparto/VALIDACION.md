# Planilla de reparto — 15/10/2026

Estado: implementada, validada y **publicada el 15/10/2026**. Sin escrituras a leads de producción. Véase [PUBLICACION.md](PUBLICACION.md) para el commit, artefacto y smoke exactos.

## Comportamiento

Coordinación abre una planilla por supervisor y origen, con pendientes, entregas del período, cantidades preparadas y total previsto. Usa los mismos recursos visuales del CRM. Los destinos salen del padrón activo; las entregas de responsables ya inactivos siguen consultables. La agenda anterior se conserva en una pestaña secundaria.

- Semana de lunes a domingo en Lima por defecto; también día, rango y días específicos. Hasta 366 días por consulta, divididos en ventanas de hasta 14; desglose diario paginado.
- **Ingreso al CRM** selecciona pendientes por `creado_en`. No es la fecha original del formulario o Excel.
- **Fecha de reparto** suma entradas a bandeja; no es stock actual ni contactos únicos. Una nueva entrega se registra hoy. Un período sin hoy no cambia su total histórico al preparar o enviar.
- Origen y supervisor filtran las entregas. Los pendientes no tienen dueño: seleccionar supervisor elige destinos, no reduce la cola.
- Cambiar filtros limpia el borrador con aviso. Revisar relee cola y permisos, fija los IDs FIFO por origen y orden alfabético de supervisor. Confirmar envía secuencialmente por la RPC existente.
- No hay transacción global del lote. Se detiene ante el primer rechazo o resultado incierto; muestra confirmados, rechazado/sin confirmar y no intentados. No sustituye IDs ni reintenta automáticamente. El servidor conserva sus controles de permiso, propietario, etapa y No contactar.
- Mientras se envía se bloquea el cambio de pestaña. La cola individual invalida la planilla al terminar; la planilla invalida cola y resumen. Un cierre de pantalla detiene las siguientes entregas, no revierte una ya confirmada.

## Lectura completa

La planilla pide conteo exacto de la RPC existente y páginas ordenadas por `creado_en,id`, adaptándose al límite real de respuesta. Rechaza conteo ausente/cambiante, duplicados y filas inválidas. Las ventanas de agenda deben cubrir todos los días solicitados y traer desglose por origen. Un error cancela las lecturas hermanas. No se sustituyen lecturas fallidas por cero.

Las consultas no constituyen una fotografía transaccional común; cambios simultáneos pueden actualizar cifras entre lecturas. Se relee antes de revisar y cada escritura es validada atómicamente por el servidor. No se crean migraciones ni se cambia la configuración de reparto libre.

## Revisiones

Claude: `CHANGES_REQUESTED`, con correcciones aplicadas: rechazos conocidos separados de respuestas inciertas, error de revisión sin esconder la tabla, completitud de cola, orden FIFO reproducible, motivo de corte al cambiar el día y paginación del desglose.

Reviewer Codex: aplicados bloqueo y actualización Cola→Planilla; abortar lecturas hermanas tras un fallo. Ambas correcciones tienen regresiones. El dictamen original de Claude se conserva en REVISION-CLAUDE.md; no se presenta como un PASS posterior.

## Verificación

- PASS: gate de realidad administrativo de solo lectura, 15/10 22:09 UTC; 0 errores. Dos divergencias preexistentes ajenas al reparto: ventas de analistas de baja y clientes sin domicilio legal.
- PASS: `npm run check`, 432 archivos / 6.946 tests; lint, TypeScript, cobertura, release config, SW, build, bundle y duplicación.
- PASS: Docker E2E `planilla-reparto.spec.ts`, `repartir.spec.ts`, `reparto-libre.spec.ts`: 40/40, sin reintentos en la pasada final.
- PASS: banco nuevo ampliado, 4/4 E2E en Docker; incluye el cruce Cola→Planilla con respuesta diferida. Son 41 escenarios distintos de reparto verificados en las dos pasadas. Capturas de tabla a 390 y 1366 px revisadas sin desbordamiento de la página.
- NOT RUN: suite E2E completa del CRM; se ejecutó el alcance de reparto afectado. No hay cambios de backend ni de permisos.

Figma actualizado: https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=52-34
