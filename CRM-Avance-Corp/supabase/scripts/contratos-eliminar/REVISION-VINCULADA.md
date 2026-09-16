# Revisión de eliminación con inversión vinculada — 16/09/2026

LEVEL 3. Codex PRIMARY; Claude SECONDARY_REVIEWER (auditor-rls), wrapper
`scripts/claude-review`, sin herramientas ni delegación. Dos consultas máximo.

## Dictamen y decisión del PRIMARY

Primera revisión: **BLOCK**, principalmente por no adjuntar el cuerpo anterior
y la ubicación del bloqueo de meses cerrados. No se interpreta como PASS.

- P1 hipotético, guarda de mes cerrado: descartado con el diff literal de
  `20260916003000` y catálogo productivo. Permanece en
  `private.trg_preparar_eliminacion_operacion_cartera` (INSERT de reserva) y
  `private.trg_restaurar_operacion_antes_borrar_contrato` (DELETE). Prueba SQL
  dedicada PASS local/remota, sin efectos parciales.
- P2, FK conocida retirada: aceptado. Se exige el conjunto de cinco tablas,
  columna `inversion_id` → `id`, NO ACTION, no diferible. Se rechazan relaciones
  nuevas y toda FK a titulares. Pruebas de ausencia, acción/columna alterada y
  descendiente CASCADE PASS. El lock del padre sigue bloqueando inserciones.
- P2 hipotético, renovación y referencias lógicas: catálogo sin `inversion_id`
  ni `fuente_id` carentes de FK. Referencias históricas sin FK a contrato en
  auditoría, ledger_rentabilidad y solicitudes_tasa permanecen intactas.
  `trg_contratos_f4_vincular` es AFTER INSERT, no UPDATE. Las pruebas demuestran:
  Admin conserva la restricción previa de reapertura y revierte todo;
  Superadmin restaura contrato origen, con inversión/eventos del origen idénticos.
- P3, cotitulares omitidos del texto: aceptado en SQL, UI y allowlist Edge.
- P3, mensajes anteriores: retenidos deliberadamente para la reversa.
- P3 hipotético, interbloqueo: Edge ya convierte 40P01/55P03 en conflicto
  reintentable; cuatro carreras reales PASS. No se cambiaron esos códigos.
- Gaps: agregadas pruebas de solicitudes, ajustes, orígenes cotitulares, cierre,
  renovación por rol y reversa/reaplicación con huellas exactas. La misma suite
  de 21 casos se ejecuta local y remotamente desde `auditoria-casos.mjs`.

La segunda consulta adjuntó cuerpo anterior/diff, triggers, reversa y resultados.
El wrapper terminó exit 1: «resultado incompleto o sin VERDICT válido».
**No hay segundo dictamen válido ni se afirma aprobación independiente.**
No se repitió la consulta para obtener conformidad. El PRIMARY cerró los puntos
con catálogo y pruebas reales; ninguna hipótesis se convirtió en hallazgo probado.

## Límite que se conserva

Reabrir el contrato origen de una renovación sigue reservado a Superadmin por
`public.validar_transicion_estado_contrato`. No se amplía ese permiso desde esta
corrección. Un Admin rechazado conserva contrato, inversión, titulares, operación
y auditoría sin cambios. El caso reportado es un contrato nuevo sin ese bloqueo.

## Evidencia

[Acta verificable](VERIFICACION-VINCULADA.json),
[Auth/Edge/Storage](http-vinculada-remoto.resultado.json),
[SQL compartido](auditoria-casos.mjs), [carreras](concurrencia.test.mjs).
La matriz global cerrada en `../rls-vigente/` no se vuelve a acreditar como nueva
corrida: aquí se valida el dominio afectado, con roles reales en rama sintética.
