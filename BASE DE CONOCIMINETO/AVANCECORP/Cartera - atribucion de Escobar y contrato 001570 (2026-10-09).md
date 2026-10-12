---
tags: [crm, cartera, facturacion, atribucion, investigacion]
fecha: 2026-10-09
estado: causa confirmada; sin correccion productiva
---

# Cartera: atribución de Escobar y contrato 001570

Miguel reportó que ESCOBAR TELLO CESAR está en la cartera de Betzabeth, pero sus inversiones dicen «Analista de la operación: Pierina» y Facturación octubre atribuye a Pierina el contrato 001570. Investigación con SQL productivo solo lectura, historial de auditoría y código; no se cambiaron datos ni reglas.

## Hechos verificados

Responsable actual en perfiles e inversionistas: BETZABETH FUENMAYOR SAAVEDRA. Pierina tiene membresía CRM desactivada desde el 01/09/2026 11:17 Lima. En esa desactivación el cliente pasó al reemplazo; el 03/09 10:54 Lima pasó a Betzabeth. No confundir el flag public.perfiles.activo con crm.equipo.activo.

| Contrato | Fecha comercial | Importe | Registro del contrato | Atribución calculada |
|---|---|---|---|---|
| 2026-01-000373 | 07/04/2026 | USD 1.000 | Upgrade, Pierina; renovado | Pierina |
| 2026-01-001134 | 30/07/2026 | USD 5.000 | Renovación, Pierina; activo | Pierina |
| 2026-01-001570 | 07/10/2026 | USD 1.000 | Renovación, Betzabeth; activo | Pierina |

Los contratos de abril y julio se importaron el 13/08; la atribución Pierina se completó en el backfill del 29/08. El 000373 nació como upgrade. No se observan cambios posteriores de categoría o analista en su auditoría. El 001570 nació con Betzabeth en analista_cierre_id y creado_por; operaciones_cartera también guarda a Betzabeth en vendedor_id y creado_por. Renueva explícitamente el 000373.

## Causa

private.analista_atribuido_cadena busca hacia atrás el upgrade más cercano y usa su analista_cierre_id. El upgrade 000373 devuelve Pierina, con prioridad sobre Betzabeth del 001570. No consulta actividad del analista ni responsable actual del cliente. private.capital_episodios y private.cartera_f5_fuentes aplican ese mismo criterio. Por eso Facturación y las tres inversiones muestran Pierina; en las antiguas viene del propio registro, en la nueva viene del upgrade antecesor.

No es una regresión de la publicación P9. Huellas vivas: capital_episodios c9e58c1da9dd7a5d52991c9e47dc19d5; analista_atribuido_cadena 3c9cec305b014ad8c933df25057d3e8b; cartera_f5_fuentes fa15f7765d0892c790c7a4b6822e756e. Coinciden con la implementación previa.

En app/src/components/app/inversionista-ficha.tsx:113 la etiqueta «Analista de la operación» presenta analista_origen_nombre, que contiene atribución comercial efectiva. Esa etiqueta confunde atribución heredada con el analista registrado en el contrato. En octubre, entre los contratos de stock del núcleo, el 001570 es el único cuya atribución calculada difiere de su analista_cierre_id (medido el 09/10).

## Alcance de las alternativas

La regla firmada del 30/08 conserva una línea de upgrade incluso al desactivar/reasignar al responsable; el remedio declarado era reasignar su cabeza. public.reasignar_analista_contrato exige motivo y registra la reasignación.

- Reasignar el 001570 a Betzabeth no sirve: ya la tiene; la puerta rechaza P0409 y la cadena seguiría mandando.
- Reasignar la cabeza 000373 a Betzabeth movería las vistas vivas de 000373 (abril) y 001570 (octubre). Se verificaron solo esos dos descendientes. El 001134 seguiría en Pierina. Los snapshots de periodos sellados están declarados inmutables; eso no equivale a conservar las vistas históricas vivas.
- Para atribuir desde la transferencia o desde la nueva operación, preservando la atribución histórica de abril/julio, hace falta definir e implementar vigencia temporal o una excepción explícita de la cadena. No basta filtrar analistas inactivos ni cambiar una etiqueta.
- Conviene distinguir responsable actual, analista registrado y atribución comercial en la ficha. La elección de política y el alcance temporal quedan pendientes de Miguel; su pedido actual fue investigar.

## Revisión secundaria y decisión del PRIMARY

Claude mediante scripts/claude-review: CHANGES_REQUESTED sobre la redacción del informe, diagnóstico confirmado. Primer intento no completó; segundo fuera del sandbox sí devolvió dictamen. Se acepta precisar que reasignar 000373 cambia su propio analista_cierre_id, además de la atribución heredada, y que una regla temporal debe mantener alineados capital_episodios y el mapa de cartera_f5_fuentes. La corrección de etiquetas es independiente del cambio de política comercial.

No se recomienda recategorizar la renovación para eludir la cadena. No se infiere que Pierina hizo materialmente las ventas antiguas: lo verificado es su registro importado. No se adopta la afirmación del reviewer de que el sello de octubre congelaría esta Facturación a nombre de Pierina: Facturación es una lectura viva, el episodio devuelve en_roster=false, y no se midió aquí la eventual inclusión en metas/sello. El estado de cierre de abril no se consultó; no se ofrece la reasignación histórica como operación lista para ejecutar.

Recomendación: conservar las atribuciones antiguas registradas, definir una transferencia con vigencia para que la operación nueva cuente a Betzabeth, y mostrar de forma distinta responsable actual, analista registrado y atribución comercial. El cambio de política y su implementación no forman parte de esta investigación de solo lectura.

## Aclaración posterior de Miguel — traspaso al desactivar

Miguel precisó: «si un analista lo desactivas entonces ya esa regla, que esta bien la regla pero en este caso no debe aplicar» y «cuando se desactiva el analista todo pasa al nuevo». La regla de upgrade se conserva para el analista que sigue activo; la baja debe transferir también las líneas y renovaciones al sustituto.

Medición adicional: la baja viva crm.fijar_membresia_activa_fn (md5 9be9925a221e64119b21e0f6a299ceb9) transfiere equipo/leads/tareas/perfiles y responsable de relación, pero no contratos ni atribución de líneas. Pierina conserva 9 contratos upgrade (8 activos, 1 renovado): 8 líneas bajo responsable actual Betzabeth (7 activas) y 1 bajo Vladimir (activa). Conserva 35 contratos con analista_cierre_id Pierina: 34 activos y 1 renovado. Las cantidades son contratos, no clientes ni capital neto (no sumar origen renovado y sucesor).

Se pidió una única precisión antes de implementar: si «todo» incluye reatribuir operaciones anteriores a la baja en los reportes históricos, o transferir toda la cartera/líneas y operaciones posteriores preservando ese histórico. Pregunta pendiente de respuesta; no se asume opción por silencio. No se han creado migraciones ni modificado código o datos. La copia limpia sigue en main 0f619b024be93f646742e299bfc7c273dbfdda43, sincronizada con avancecorp/main; el checkout compartido se preservó.

PASS: relación 000373→001570, registro de Betzabeth, auditoría de transferencia y desactivación, salidas productivas de ambos núcleos, alcance de descendientes. Tests/build nuevos: NOT RUN, no se modificó implementación. No se usó producción como banco de mutaciones.

Relacionadas: [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]], [[Atribucion de upgrades y sus renovaciones (decision 2026-08-30)]], [[Contrato PDF - analista asignado y creador separados (2026-09-30)]], [[Facturacion - auditoria completa (2026-10-08)]], [[Inicio]].
