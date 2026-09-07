# Primera atención: refresco después de una llamada contestada

Estado: **PUBLICADO Y VERIFICADO EN PRODUCCIÓN EL 07/09/2026**.

Miguel reportó que cerrar una llamada como «Contestó» desde sus acciones deja la oportunidad en «Primera atención» hasta registrar otra actividad. El comportamiento esperado es que la llamada del analista asignado cuente por sí misma: cierre, historial y atención deben ser coherentes, sin duplicar la gestión.

## Hallazgo reproducido

La primera lectura de SLA puede seguir viajando cuando se confirma el cierre. Si aún no existe un valor en caché, TanStack Query reutiliza esa petición al invalidarla; su respuesta anterior al guardado puede quedar visible aunque el servidor ya reconozca la llamada.

La resincronización central del store cancela ahora las lecturas de métricas operativas antes de invalidarlas. Ficha, cola paginada y campana comparten ese prefijo y vuelven a consultar después del guardado. Se conserva la respuesta del servidor como fuente del estado. Una escritura rechazada no elimina el pendiente. No se añade ningún cálculo ni núcleo y no se requiere SQL.

## Contraste de servidor y límite del diagnóstico

Se inspeccionaron en producción, solo en lectura, el cierre atómico, su comando con recibo y el trigger que registra los hitos de actividad. Cerrar una llamada con resultado `llamada_realizada` ya inserta una actividad y reconoce el contacto dentro de la misma transacción, sin exigir detalle escrito.

El contraste agregado no encontró llamadas contestadas del analista de la asignación vigente que carecieran de sus hitos. En la muestra de 33 oportunidades con llamadas contestadas cerradas ese día, no se encontró un contacto ausente ni registrado más de cinco segundos después de la primera llamada. Los recuentos son una observación puntual, no una garantía sobre datos posteriores.

Se conserva la regla existente de atribución: una gestión de otro usuario no se imputa al analista de la asignación. El usuario todavía no identificó la oportunidad concreta, por lo que el fallo de caché está reproducido pero no se afirma que sea la causa exclusiva de su caso.

## Verificación

- Sin la corrección: dos regresiones fallan, tanto desde cierre de tarea como desde registro directo; reciben el pendiente anterior al guardado. El caso de rechazo conserva correctamente el pendiente.
- Con la corrección: los tres casos pasan con QueryClient y observadores reales, manteniendo una sola escritura. Cubren las claves de ficha, cola y campana con respuestas anteriores que llegan tarde.
- Store real completo: 66 pruebas correctas. Suite general: 3.021 pruebas correctas en 208 archivos. TypeScript correcto y lint sin errores; cuatro advertencias previas de accesibilidad en `coverflow-carousel.tsx`.
- Navegador: 11 recorridos de SLA correctos, incluido uno nuevo que cierra «Contestó», omite la siguiente tarea y no registra ninguna actividad adicional. La lectura inicial se demora deliberadamente y el aviso se actualiza. Estos recorridos usan un backend simulado local; no se crean llamadas de prueba en producción.

## Publicación

Commit de aplicación `8a3169291601cd33284c460fd80c7c7e391180b1`, integrado en Main y confirmado idéntico a `avancecorp/main` antes de construir en un checkout limpio. Conserva los cambios de Rentabilidad y el enlace del portal que ya estaban en Main; el artefacto solo se desplegó en `crm.miavance.com`.

Release `crm-20260907T193510Z-8a3169291601`, build `build-20260907T193429314Z`. ZIP de 1.944.713 bytes, SHA-256 `bb823de38f2249a7ac7c6d30e9f06dac170e98d8b6a241332907c265488f2c07`; manifiesto SHA-256 `f9a5c02ad4517c289a93714787a3b25d00d3c91142ebc06b1eac233a62746c0b`.

Build, configuración pública y verificación del bundle correctos. El preflight confirmó que desciende del commit vivo `82b25d175680`. Hostinger confirmó la publicación en la cuenta del CRM. Verificación HTTP: 79 archivos, 66 hashes exactos, 12 imágenes transformadas por Hostinger, `.htaccess` protegido, versión estable y ZIP inaccesible públicamente en CRM y portal. Cero fallos. [Evidencia HTTP completa](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/primera-atencion-20260907/produccion-http.json).

Se abrió Seguimiento con la sesión existente de Gerencia y la versión nueva: carga correcta, filtro «Primera atención» seleccionable y diez oportunidades por página. Solo se consultaron datos en producción. La llamada contestada y el retraso de red se probaron en el navegador local con respuestas simuladas. No se aplicó SQL ni se alteraron registros comerciales.

[[Seguimiento - avisos accionables implementados 2026-09-07]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].
