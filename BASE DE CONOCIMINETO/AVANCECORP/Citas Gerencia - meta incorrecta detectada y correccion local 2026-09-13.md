---
fecha: 2026-09-13
estado: correccion-local-no-publicada
tags: [crm, citas, gerencia, metas, pendiente]
---

# Citas — meta incorrecta y alcance pendiente

**Actualización posterior:** [[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]] sustituye la exclusión de manuales y resuelve el conteo de visitas y el período del ticket. La implementación y las pruebas descritas abajo todavía corresponden a las reglas anteriores; no acreditan la integración de estas últimas respuestas.

Miguel reclamó que no ve lo acordado y que hasta la meta está mal. La pantalla publicada sigue usando **3 citas por lead = 100%, objetivo 125% = 3,75**. Se confirmó técnicamente el despliegue de d3ce2c1, pero eso NO completó las métricas acordadas. La confirmación de entrega completa fue incorrecta.

La meta vigente acordada es **1,25 citas por lead**, interna, con 70% entrevistas y 70% conversión a cliente. Véase [[Citas Gerencia - analisis del Excel de proyeccion por analista 2026-09-10]].

## Corrección hecha sólo en local

- Retiradas las referencias a tres citas y el objetivo adicional de 125% de tabla, ayuda y ficha personal.
- Cumplimiento lee la meta del servidor; usa personas asignadas en el mes, incluyendo sin citas, excluye altas manuales propias.
- Nueva candidata SQL `20260913204847_crm_citas_base_asignada_meta_interna.sql`: agrega la base desde `lead_asignaciones` y evidencia `alta_manual` + `creado_por`. Conserva V2, Gerencia, núcleos, recuperación y conversión. No modifica `public` ni instala una nueva puerta API.
- Tabla y filtros incluyen analistas con cero citas. La semana delimita actividad y conserva base mensual; no prorratea una meta mensual.
- Sin base se muestra ausencia de dato. Cuando hay citas de registros manuales y no se ha decidido su aporte, no se calcula un cumplimiento inventado. Se soportan ambas decisiones.
- La configuración Superadmin sigue siendo borrador y no alimenta estas constantes iniciales. No confundir este arreglo con activar el panel.

## Verificación

`npm run check`: **PASS**, 3.470 pruebas/240 archivos, lint/typecheck/cobertura/build/bundle. Quedan cuatro warnings de accesibilidad preexistentes del coverflow ajeno. Playwright de Citas: **4 PASS** en puerto independiente 5196 (5199 estaba ocupado y no se tocó). Captura de QA con datos ficticios: `UX-UI-GERENCIA/citas-meta-correccion-2026-09-13/captura-local.png`.

Ensayo en banco propio `xhgsjtzpmwlqfkninphl`: **PASS**, transacción completa con **ROLLBACK**. Prueba ocho asignados, cinco sin citas, manual propio/ajeno, analista sin citas, meta1,25 y70/70, campos V2 idénticos al eliminar añadidos, corte, permisos y gobernanza. El primer ensayo detectó correctamente al comparador temporal como consumidor sin declarar; se retiró ese comparador antes del censo final, sin cambiar ni exceptuar el SQL de producto. Revisor RLS estático: PASS. No se instala la candidata en producción ni se registra en el banco.

`gate:realidad`: **NOT RUN**, falta SUPABASE_URL en entorno del script. Comprobación directa de producción: RPC de control de Citas ausente; 43 altas manuales con autor y ninguna sin autor. Matriz RLS general/advisors de esta candidata: **NOT RUN**. Tipos SQL: firma sigue retornando JSONB y no cambió esquema de tablas/API; validación runtime ampliada.

## Todavía falta

1. Integrar y activar configuración de Superadmin: [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]].
2. Integrar avance70/70, ticket y proyección: [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]].
3. Respuestas solicitadas en esta conversación: fuente del ticket; visitas repetidas frente a personas entrevistadas; si actividad de manuales aporta al cumplimiento. No llegaron durante el trabajo. Conservar además las decisiones pendientes previas de atribución/vigencia, sin presentarlas como confirmadas.
4. Completar validación pertinente, integrar Main/remoto y publicar el alcance final concreto. **Esta corrección no está publicada**.

Relacionada: [[Citas Gerencia - preparacion verificada 2026-09-13]], que verifica sólo la publicación técnica anterior.
