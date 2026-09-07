# Primera atención: respetar la próxima acción válida

Estado: **AJUSTE GENERAL PREPARADO Y PROBADO; SQL PENDIENTE DE CONFIRMACIÓN**.

Miguel aclaró que la insistencia «Contacta al cliente y registra el resultado», cuando ya hubo gestión y existe una próxima acción programada, es un problema del sistema. La captura solo permitió observar un ejemplo; no corresponde corregir una oportunidad individual.

La regla vigente distingue intento de contacto y respuesta efectiva. La cobertura de una tarea suspende el seguimiento recurrente, pero no el aviso de primer contacto. Por eso el núcleo devuelve ambos estados aunque la pantalla se actualice correctamente. El ajuste de caché ya publicado no resolvía esta causa.

Se preparó una modificación del núcleo operativo existente: con primera gestión en el ciclo y en la asignación coherente, y cobertura comercial válida, se difiere la insistencia operativa. Al vencer la tarea, Agenda avisa a su hora; sin cobertura vuelve el contacto pendiente. Agendar sin intento inicial no silencia el aviso. Se conservan los hitos de respuesta real, las métricas históricas, los techos, la revisión comercial y los permisos.

No se añade un núcleo ni cálculo frontend. Ficha, cola y campana reciben la decisión común del servidor. [SQL exacto, condiciones, pruebas y reversión](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/avisos-compromiso-20260907/REVISION.md).

Verificación local: 64 pruebas en PostgreSQL 16 y otras 64 en PostgreSQL 17, más nueve casos focalizados con reversión. Hay evidencia de regresión con la definición anterior. No se aplicó este SQL ni se modificaron datos de producción. La aprobación sigue pendiente conforme a [[Inicio]].

[[Primera atencion - refresco tras llamada contestada 2026-09-07]] · [[Seguimiento - avisos accionables implementados 2026-09-07]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]].
