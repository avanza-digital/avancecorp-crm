# Análisis de propuesta SLA por etapas — 2026-09-06

Estado: análisis solicitado; sin autorización ni ejecución de implementación.

Fuente: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/spec-prorroga-sla-etapas.md`.
Informe: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/ANALISIS-2026-09-06.md`.

La separación entre seguimiento del analista y antigüedad en etapa es útil, pero la especificación requiere revisión. Hallazgos contrastados con el repositorio:

- Los lectores actuales son estrictos: ampliar el estado o devolver configuración v2 rompe el contrato de frontend v1. Hace falta transición compatible.
- El guard propuesto para no prorrogar una etapa recién nacida compara `statement_timestamp()` de etapa con `clock_timestamp()` de actividad; esa diferencia permite conceder una prórroga en nuevo → contactado.
- La condición de tarea futura retira la pausa al llegar `vence_en`, por lo que su margen desaparece. La fórmula se reprodujo aisladamente.
- «Sin gestión» compara una duración con una fecha y carece de umbral propio. Dos prórrogas tempranas pueden dejar un lead con 14 días sin gestión y sin vencimiento efectivo.
- El backfill necesita una secuencia compatible con el guard de configuración inmutable y el CHECK de techo.
- El 87 % es presencia de tareas pendientes, no cobertura elegible demostrada. Las 277 etapas históricas conservarían v5 y no reciben alivio por publicar v6.
- La cola operativa debe incorporarse al alcance, además del estado SLA y los badges.

No se consultó producción. Los conteos y el branch de la propuesta no se revalidaron. Los plazos propuestos no quedaron aprobados. La propuesta original se conserva intacta.

Relacionadas: [[Inicio]] · [[Configuración operativa CRM 2026-08-07]] · [[Inventario de indicadores de Gerencia - Citas y operacion]] · [[Agenda comercial del CRM (plan v2)]] · [[Hoy del vendedor - Ahora y Después]] · [[Terminología comercial del CRM]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].

Continuación solicitada en la misma sesión: [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]]. Se entregó un plan SLA-R1 con decisiones y fases ejecutables; en esa continuación sí se consultó producción en modo lectura y se actualizó el corte a 827 etapas abiertas / 492 vencidas, con v5 vigente. La ausencia de consulta productiva descrita arriba corresponde únicamente al análisis inicial. La implementación y el SQL siguen sin ejecutarse.
