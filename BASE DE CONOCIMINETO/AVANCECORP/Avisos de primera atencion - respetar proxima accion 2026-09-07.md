# Primera atención: respetar la próxima acción válida

Estado: **APLICADO Y VERIFICADO EN PRODUCCIÓN**, 07/09/2026, 15:17 Lima. Miguel aprobó el SQL concreto: «ok me gusta tu correcion hazla».

Miguel aclaró que la insistencia «Contacta al cliente y registra el resultado», cuando ya hubo gestión y existe una próxima acción programada, es un problema del sistema. La captura solo permitió observar un ejemplo; no corresponde corregir una oportunidad individual.

La regla anterior distinguía intento de contacto y respuesta efectiva, pero la cobertura de una tarea solo suspendía el seguimiento recurrente. Por eso mantenía el aviso de primer contacto aunque la pantalla se actualizara correctamente. El ajuste de caché ya publicado no resolvía esta causa.

Se aplicó una modificación del núcleo operativo existente: con primera gestión en el ciclo y en la asignación coherente, y cobertura comercial válida, se difiere la insistencia operativa. Al vencer la tarea, Agenda avisa a su hora; sin cobertura vuelve el contacto pendiente. Agendar sin intento inicial no silencia el aviso. Se conservan los hitos de respuesta real, las métricas históricas, los techos, la revisión comercial y los permisos.

No se añade un núcleo ni cálculo frontend. Ficha, cola y campana reciben la decisión común del servidor. [SQL exacto, condiciones, pruebas y reversión](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/avisos-compromiso-20260907/REVISION.md).

Verificación local: 64 pruebas en PostgreSQL 16 y otras 64 en PostgreSQL 17, más nueve casos focalizados con reversión. Hay evidencia de regresión con la definición anterior. Producción: fuente exacta aprobada, contrato y gate correctos, control/política intactos y advisors sin novedades. Lecturas autenticadas de analista, supervisor y gerencia verifican concordancia entre ficha, filtro y campana; ficha real recargada sin insistencia y con la próxima acción intacta.

La comparación de cartera fijó el mismo instante SLA: 1.271 filas, 1.270 con hechos estables. Se retiraron 30 avisos vencidos de primera atención y se reemplazaron 21 acciones iniciales futuras por la siguiente acción que correspondía. Las otras señales y los 11 casos con cobertura pero sin gestión inicial quedaron iguales. Una llamada y un descarte reales concurrentes explican la fila excluida; no se atribuyen al SQL. Son conteos de ese instante.

Migración canónica `20260907194756`, ejecutada por MCP como `20260907201712`; una actualización de metadatos alineó únicamente la versión después de comprobar nombre, fuente y destino libre. SHA-256 `a0126d8089b07d743e58450145d4bb20b4e64da4c3cbf159f49a8b6428f29f89`; función viva MD5 `d880268ef586322e0589586cb8cde30d`. No se escribieron datos comerciales ni se ejecutaron otras migraciones. No requirió un nuevo despliegue frontend. [Evidencia productiva sin PII](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/avisos-compromiso-20260907/produccion-verificacion.json).

[[Primera atencion - refresco tras llamada contestada 2026-09-07]] · [[Seguimiento - avisos accionables implementados 2026-09-07]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]].
