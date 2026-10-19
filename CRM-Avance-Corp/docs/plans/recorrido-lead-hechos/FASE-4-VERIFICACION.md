# Fase 4 · Guía del analista

Estado: **PASS local**, 18/10/2026. No publicada. El bloqueo de conversión pertenece a la fase 5.

## Implementación

- Lectura central `recorrido_leads_fn`: contrato validado en runtime, IDs únicos del lote, lotes secuenciales de 100, configuración coherente entre lotes, cancelación. No consulta por tarjeta.
- Caché bajo el prefijo de leads: se invalida con los escritores existentes. Clave por actor, rol e IDs; sin reutilizar una fotografía de otra página, sesión o ciclo. Refresco/error significa desconocido, nunca un permiso optimista.
- Ficha: asistencia y entrevista del ciclo actual, siguiente acción, cita pendiente e historial ambiguo. Cierre de cita existente y atención de oficina reutilizan sus formularios. Agendar abre el formulario vigente y conserva el título ya escrito.
- Mi día y tablero: resumen por lead y entrada a la misma ficha. Una consulta fallida no interviene en el ACK de una gestión ni en el avance de la cola. No se infiere evidencia por etapa.
- Modos: sin backend/apagado/demo no inventan requisitos; observación indica seguimiento informativo; exigencia se muestra solo cuando el servidor declara exigible ese lead.
- Permisos: conserva ámbito, rol, analista asignado y No contactar. Una respuesta tardía no abre un cierre tras cambiar de actor. Formularios abiertos sobreviven a fallos de lectura.
- Capacitación corregida: contacto no es un bloqueo adicional; «Saltar esta vez» omite la siguiente tarea propuesta, no los requisitos de conversión.

## Gate de Codex

| Comprobación | Resultado |
|---|---|
| Tests de lectura, caché, guía, citas, oficina, fichas, tablero, Mi día e idempotencia | **PASS: 469 casos / 20 archivos** |
| Contratos: backend anterior, error, otra revisión, filas ajenas/duplicadas, cancelación | PASS |
| Sesión/rol, invalidación y respuesta tardía | PASS |
| Foco con diálogo Radix real, con botón inicial presente y retirado por error de lectura | PASS |
| Estado accesible persistente al terminar la consulta y lista explícita | PASS |
| Typecheck | PASS |
| Oxlint | PASS; avisos previos fuera de estos cambios |
| Build | PASS; aviso de chunks grandes preexistente |
| Revisión especializada revisor-a11y | CHANGES_REQUESTED: P2 de semántica de lista aceptado y corregido; Codex revalidó |
| Safari/VoiceOver manual | NOT RUN; no se declara conformidad asistiva completa |
| E2E Docker integral | NOT RUN en esta fase; programado en fase 6 con el guard de conversión |

## Correcciones antes de avanzar

- El `<ul>` de requisitos declara `role=list` con excepción local documentada para Safari/VoiceOver; ninguna regla global desactivada.
- Una sola restauración de foco mediante la propiedad existente del diálogo. Vuelve al botón si sigue presente o al encabezado de la guía; comprobado con Radix real.
- El estado accesible permanece montado desde carga hasta resultado para anunciar la finalización.
- Prueba aislada de cola actualizada con estado de recorrido inactivo; no tenía AuthProvider porque antes sustituía sus únicos hooks. El contrato de producción anterior se prueba además contra la red simulada con PGRST202.
- El banco de foco simula `scrollIntoView`, ausente en jsdom. Repetición final: 469 PASS sin ese error de entorno.

Revisión de Codex: no quedan hallazgos aceptados pendientes dentro de fase 4. No se habilita producción ni se confunde este gate con la prueba final de conversión.
