# Primera atención: refresco después de una llamada contestada

Estado: corrección verificada, pendiente de publicación.

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

[[Seguimiento - avisos accionables implementados 2026-09-07]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].
