# Evaluación de Codex de la revisión independiente del contrato de llamadas

13/10/2026. PRIMARY: Codex. El contrato revisado es
`2026-10-13-llamadas-crm-unificadas.md`; dictamen original conservado en
`2026-10-13-llamadas-crm-unificadas-review.txt`.

Se usó `scripts/claude-review` con evidencia saneada, sin herramientas para el reviewer. El primer intento dentro
del sandbox no completó la ejecución. El primer intento externo no devolvió un VERDICT válido; no se aceptó un
dictamen. Un último pedido acotado, con formato explícito, devolvió **CHANGES_REQUESTED**. No se pidió otro PASS.

## Decisiones del PRIMARY

| Observación | Evaluación y acción |
| --- | --- |
| No existe puerta de asociación | **Se rechaza esa afirmación.** Existe `crm.enlazar_llamada_celular` en `20261001160219_crm_llamadas_celular_nucleo.sql:765–775` y el cliente la llama en `app/src/data/llamadas-celular-api.ts:184–193`. Su núcleo en `20261005143843_crm_llamadas_celular_correccion.sql:680–752` ya autoriza ámbito, valida resultado y garantiza 1:1/repetición del mismo par. Sí faltaba citarla y especificar su reuso: agregado §3.1, incluido descarte con motivo, orden actividad → lead → evento y límite de corregir sin desenlazar libremente. No se crea otra puerta por este hallazgo. |
| Reserva/captura incompatible o ausente | **Aceptado parcialmente.** La validación actual no es solo formato: `20261005182227:68–71` ya verifica asignación; el cumplimiento en `:200–202` rechaza otro actor/lead. La ingesta bloquea lead antes de insertar (`20261005155914:531–546`) y el helper usa `KEY SHARE NOWAIT` (`20261005182227:204–219`). Se añade §3.2 con esos hechos, estados visibles, permisos y plazo actual de intención (32 días). No se transforma un rechazo de vínculo en anulación automática de una actividad. |
| Guarda contra v5 antigua | **Aceptado el prerrequisito.** La guarda compatible debe entrar antes del frontend. Se rechaza que una excepción en un helper posterior sea necesariamente demasiado tarde: una excepción propagada revierte los efectos transaccionales previos. No se prescribe el orden recibo → lead sin las autorizaciones y bloqueos de persona aplicables. Tampoco se promete devolver literalmente una respuesta v5 que el recibo v4 no almacena; se exige recuperación sin efectos nuevos y vínculo sustentado en evidencia. |
| Identidad/día/purga | **Aceptado con límite de retención.** §4 fija identidad/alias para hechos y versiones, y §5 define revisión del conjunto, cambio de día e invalidación del cursor. Se rechaza conservar indefinidamente una identidad huérfana para evadir la purga: el mapa de evidencia no resuelta caduca con ella. Una actividad existente conserva su identidad según su propio historial autorizado. |
| Conteo de Por revisar | **Aceptado.** §4 fija cubeta exclusiva y total `null` mientras la identidad está por conciliar. No sumar como llamadas exactas las dos evidencias candidatas. La lectura comparte este estado entre roles; captura incompleta/fecha declarada implica cobertura parcial. |
| Deshacer actividad manual sin captura | **Aceptado sin ampliar a un borrado nuevo.** Se conserva como revisión, no como llamada física probada. No se inventa un endpoint de anulación libre ni se borra el historial para cuadrar un contador. |
| Cohorte de contacto | **Aceptado.** Queda explícita «Contacto de resultados registrados hoy», por fecha de registro, con exclusiones actuales y denominador del mismo conjunto. No usa el total de llamadas ocurridas hoy. |
| No contestó sin próxima acción | **Hipótesis resuelta por código.** `20260921153654_crm_resultado_llamada_seguimiento.sql:95–116` declara opcional la próxima acción de `no_contesto`; `:189–195` solo la exige para `volver_a_llamar`/`agendo_reunion`. Agregada evidencia a §7. No se requiere crear tareas ficticias por cada elemento del lote. |
| Normalización v6 en el cliente SLA | **Aceptado, ya estaba encargado.** Se mantiene adaptación explícita de lista de comandos, nombre confirmado y campos, además de recuperación de intenciones antiguas. No debilitar el validador para admitir cualquier nombre. |

## Verificación y límites

- PASS: revisión directa de las rutas citadas y del plan de #21 en el SHA `3fc596a0` del #270.
- PASS: rutas locales, enlaces internos de la nota y `git diff --cached --check` en la entrega final.
- Revisión independiente: **CHANGES_REQUESTED**; correcciones evaluadas por el PRIMARY y asentadas arriba.
- NOT RUN: código local de #21 (no publicado), nueva migración, tests de aplicación, SQL/concurrencia, E2E y producción
  de #23. El contrato incorpora 26 casos que deberá demostrar la implementación delegada.

Este cierre acredita un contrato corregido y un encargo verificable; no acredita el funcionamiento de la nueva
unificación. La implementación queda a cargo de Jhosep/Claude y su validación posterior a cargo de Codex.
