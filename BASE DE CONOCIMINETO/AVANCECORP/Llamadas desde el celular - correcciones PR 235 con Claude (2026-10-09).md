# Llamadas desde el celular - correcciones PR 235 con Claude (2026-10-09)

Relacionado: [[Inicio]] · [[Llamadas desde el celular - revision detallada PR 235 (2026-10-09)]] · [[Llamadas desde el celular - instalacion y publicacion (2026-10-07)]]

## Resultado

Miguel autorizó a Codex corregir los hallazgos del #235 con revisión de Claude. Commit **e047986dd1efa745b97a9e4e7533dfe5ac305967**, subido a la misma rama del PR. Solo cinco archivos documentales. Se trabajó en la copia aislada `/private/tmp/avancecorp-pr190-correcciones-20261006`; el checkout compartido se preservó.

- **P2 corregido:** SOPORTE §2.1 exige preservar la encuesta y confirmar el guardado antes de cerrar/actualizar. Este rechazo no guarda el intento actual; la comprobación de «Guardados por confirmar» corresponde a un envío anterior. Si persiste, copiar nota/opciones de inmediato y revisar la tarea con soporte. Una copia no equivale a un resultado registrado.
- El error también ocurre con una tarea completada, cancelada o no disponible en una versión corregida; no prueba que el CRM esté desactualizado.
- **P3 corregido:** pérdida del borrador H-P5 confirmada; la causa del salto A→B todavía requiere captura focalizada en C1. Se precisaron SOPORTE, REGISTRO, SEGUIMIENTO y F4.4.1/AVANCE; el historial fechado se conserva.
- **45/102 tareas, 2/8 fases**, sin cambios de `done`/`estado`. F4.2.4 bloqueada; H-P5/H-P10 abiertos.

## Verificación

- Claude SECONDARY_REVIEWER mediante `scripts/claude-review`: **PASS**. Codex incorporó las precisiones menores y comprobó las afirmaciones vigentes de H-P5.
- **PASS:** JSON válido, 102 IDs únicos, historial previo intacto; regeneración repetida sin diferencias en PLAN/AVANCE, referencias locales y `git diff --check`.
- Evidencia anterior de esta revisión: **8/8 pruebas focalizadas de store**, incluidos rechazos de tareas completadas/canceladas; no hubo cambios de código.
- **NOT RUN en esta corrección documental:** build, E2E y pruebas físicas C1.
- GitHub al cierre (09/10 ~15:40 Lima): `preflight` y `cambios` PASS; `app-check` en curso; Supabase Preview omitido. No se afirma que la CI completa haya terminado.

## Coordinación y siguiente paso

[PR #235](https://github.com/avanza-digital/avancecorp-crm/pull/235) abierto, **sin fusionar ni publicar**. Descripción corregida y [comentario único de coordinación actualizado](https://github.com/avanza-digital/avancecorp-crm/pull/235#issuecomment-6088778853). Turno de escritura documental devuelto a Jhosep; debe sincronizar la nota vigente F4.4.1, novedad y nueva entrada de `estado.json` con su tablero antes del siguiente volcado, para no restaurar el diagnóstico anterior.

Evidencia local: `/private/tmp/avancecorp-pr235-review-20261009/claude-correcciones-review.txt` y `verificacion-correcciones.txt`.
