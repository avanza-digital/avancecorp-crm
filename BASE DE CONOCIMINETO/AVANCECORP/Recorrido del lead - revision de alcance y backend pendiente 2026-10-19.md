# Recorrido del lead: revisión de alcance y backend pendiente

El 19/10 Miguel pidió una evaluación independiente de Claude después de comprobar que el objetivo comercial todavía no estaba operativo. Claude devolvió **CHANGES_REQUESTED**. El Goal hasta ZIP se cumplió, pero no equivale a impedir conversiones en producción.

Una lectura directa a las 05:55:37 UTC confirmó: control, evaluador y bloqueo del recorrido ausentes; **0 de 8 migraciones aplicadas**. El frontend publicado es compatible con el servidor anterior y mantiene la guía oculta cuando falta la RPC. No decir que los analistas ya ven la nueva guía.

El SQL preparado exige asistencia y entrevista de la misma cita y ciclo únicamente para ciclos iniciados desde el corte. La respuesta «cuando se active, cualquier Contactado sin esos hechos quedará bloqueado» omitió esta restricción. Cubrir también los leads actuales aún no convertidos exige una migración adicional; la política de históricos sigue pendiente de aprobación. No fabricar ni completar hechos históricos en lote.

Miguel pidió **un plan para completar el backend**, no ejecutar su instalación en esta intervención. La propuesta debe llegar hasta validación alojada, revisión, instalación, activación y aceptación comercial. Codex revisa y corrige cada fase antes de avanzar; Claude revisa el cambio crítico. El avance de desarrollo hasta ZIP debe distinguirse del avance de puesta en marcha en Figma.

La hipótesis de Claude sobre un posible UPDATE de etapa sin guard no quedó demostrada: `private.conversion_lead_con_inversion()` ya llama a `private.recorrido_exigir` en `20261019001700_crm_recorrido_conversion.sql:774`. Se debe verificar el inventario de rutas y tests en el nuevo trabajo, sin presentar esa hipótesis como un defecto confirmado.

Dictamen y evaluación primaria: `/Users/usuario/Downloads/CRM-publicacion-20261019-recorrido/revision-claude/DICTAMEN.txt` y `EVALUACION-CODEX.md`.

Relacionado: [[Recorrido del lead - frontend publicado 2026-10-19]] · [[Conversion - recorrido obligatorio por hechos (propuesta 2026-10-12)]] · [[Etapas del CRM - mapa de funcionamiento (2026-10-12)]]
