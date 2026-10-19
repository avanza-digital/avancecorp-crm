# Fase 5 · primera conversión protegida

**PASS local. No desplegado ni activado en producción.** Migraciones candidatas `20261019001700/01701`.

La decisión del servidor se toma en preparación inicial de identidad, creación de solicitud, antes de iniciar un acceso externo y al confirmar. El trigger final de lead y el de solicitud cubren escrituras internas. Una solicitud confirmada conserva una fotografía inmutable de cita/actividad/ciclo/modo/revisión. La conversión y la inversión siguen en la misma transacción y las reglas financieras vigentes no se sustituyen.

Retomar un borrador es lectura autorizada y no exige recrear hechos ni cambia su clave, condiciones o comprobante. Un claim sin Auth persistido no habilita acceso; un Auth ya creado con claim y correo de esa solicitud se puede recuperar. Esta recuperación no habilita confirmar sin evidencia. El candado SQL no se mantiene durante el HTTP de Auth: la comprobación final es la autoridad para convertir.

| Comprobación | Resultado |
|---|---|
| Instalación y hardening | PASS; instalación inicial en stack propio y replay completo final en base desechable desde contratos de fase 3. |
| SQL de negocio y permisos | PASS, 6 grupos de aserciones; RPC authenticated, anon/service negativas, rollback total. |
| Concurrencia | PASS, 5 escenarios con conexiones reales y esperas observadas: confirmar/invalidar en ambos órdenes, doble confirmación, rollback durante espera y cambio de modo. |
| Cartera existente | PASS, contrato de cartera + upgrade + renovación + replay con exigencia activa; todo revertido. |
| Frontend de conversión/cartera | PASS, 161 tests en 6 archivos; incluye retención de borrador, mensaje del servidor y reintento con la misma solicitud. |
| Edge de acceso | PASS, 16 tests; rechazo de recorrido antes de cualquier llamada privilegiada Auth. |
| Typecheck, lint y scripts | PASS; tipos generados del banco local, manteniendo PostgREST 14.5. |
| Build | PASS; aviso previo de chunks grandes, sin error. |
| Claude | CHANGES_REQUESTED inicial; hallazgos aceptados corregidos y comprobados por Codex, detalle en REVISION-CONVERSION.md. |
| Auditor de RLS | PASS acotado a ACL/ámbito sobre evidencia; gate general pendiente. |
| Matriz general, HTTP y Docker E2E | NOT RUN en esta fase; fase 6. |

Los modos observación y apagado permiten primera conversión sin evidencia, incluso en ciclos posteriores al corte; reactivar conserva el corte. Una fecha inicial explícita se limita a 24 horas. Antiguos siguen sin retrobloqueo y requieren política antes de activar producción. Si a un ciclo nuevo le falta su fila, no queda exento por ese daño.

La evidencia es declarativa y trazable: el analista registra la asistencia y el resultado de entrevista; la aplicación comprueba su vínculo y ciclo. La agenda permite registrar una atención pasada, pero una cita cerrada no permite cambiar su fecha. No se incorporó ubicación física independiente ni otro requisito comercial.

## Reproducción local

Con el stack propio del goal y actores sintéticos inicializados:

```sh
node supabase/scripts/recorrido-lead/banco.mjs test-conversion
node supabase/scripts/recorrido-lead/concurrencia-conversion.mjs
node supabase/scripts/recorrido-lead/regresion-cartera.mjs
```

El segundo comando crea una base aleatoria `recorrido_carrera_*` dentro del contenedor propio, completa referencias de autores de configuración con perfiles ficticios inactivos, restaura todas las constraints, ensaya migración completa y carreras, y elimina únicamente esa base. No cambia el modo/corte del banco principal. Auth y Storage del SQL son fixtures explícitos; no equivalen a HTTP real.
