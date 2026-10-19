# Evaluación de Codex · revisión de arquitectura de Claude

18/10/2026. Riesgo LEVEL 3. Revisión 1 del goal, solo lectura mediante scripts/claude-review. Dictamen original: CHANGES_REQUESTED, confianza MEDIUM. Fuente íntegra: evidencia/review-arquitectura.txt. No se solicitó otro dictamen para obtener aprobación.

| Observación | Decisión de Codex y evidencia |
|---|---|
| Contexto en metadata | Aceptada la mejora estructural: tabla causal 1:1, índice lead/ciclo, captura del servidor. No se afirma una vulnerabilidad probada: actividades no tiene policy UPDATE para authenticated. |
| Horas internas y lock de actividad | Aceptada: AFTER INSERT propio con lock incluso auth NULL y clock_timestamp posterior. |
| Hora de tarea | Verificada en catálogo vivo: tarea_sla_contexto.registrado_en DEFAULT clock_timestamp(); trg_sla_tarea_contexto inserta después del FOR UPDATE. Se reutiliza, sin tocar guard SLA. |
| Lectura fresca y orden de locks | Aceptada: persona → lead → solicitud en rutas de inversión; el evaluador no bloquea filas, se invoca en sentencia posterior al lock. Invalidaciones toman lead NOWAIT para no invertir esperas. Configuración FOR SHARE y revisión capturada. |
| Ámbito de oficina | Parcial: requiere analista asignado, conserva permisos y veto; no exige resolver persona/responsable de inversión para registrar una atención real. La conversión conserva sus validaciones de identidad actuales. |
| Capital fuera de oficina | Rechazada: cerrar_reunion_v3 exige capital estimado y moneda para entrevistas positivas; no es el capital confirmado de una inversión. Se reutiliza ese cierre y el hash incluye capital/siguiente. |
| Idempotencia oficina | Función hermana con multiempresa_idempotencia/idem_* existentes y namespace propio. No amplía sla_ejecutar_comando ni sla_operacion_recibos. Conflictos conservan P0409. |
| Singleton y tenant | Aceptado singleton de instalación; no se inventa negocio_id en un CRM sin esa dimensión. Auditoría existente con before/after, actor y motivo, evitando historial duplicado. |
| Recuperación Auth con conversion_reservas | Rechazada para este flujo: acceso_inversion_fn usa auth_claim_id y saga auth_persona. Se exige prueba persistida de alta externa; un reclamo sin Auth no exime. Fuente adicional evidencia/crm.acceso_inversion_fn.sql. |
| Historia | Aceptados vínculos causales de tarea/episodio/ciclo único; ciclo único no prueba cronología. No se backfillean hechos inventados. |
| Borrado inmutable absoluto | Ajustado: compatibilidad explícita con eliminar_lead_error_carga auditado. No modificar el guard del núcleo SLA. |

Inventario verificado: actividades permite INSERT propio en ámbito y no UPDATE/DELETE autenticados; tareas tiene UPDATE acotado y guardianes de cierre/inmutabilidad; mutaciones internas incluyen cierres, reprogramación, cancelación por veto/cambio de etapa, fusión de personas, postventa, deshacer llamada y eliminación oficial. La cobertura de concurrencia se sitúa además en triggers propios de invalidación para cubrir writers privilegiados y futuros.

PASS: análisis de contrato, alcance y decisión de cada hallazgo. NOT RUN: pruebas del candidato, permisos, concurrencia, recuperación Auth y carga; pertenecen a la implementación y no se sustituyen por este documento.

## Aclaración comercial posterior del usuario

El usuario precisó que el objetivo obligatorio es impedir convertir sin asistencia a cita y entrevista realizada. Codex adapta el contrato: la pareja cita/asistencia/resultado del ciclo actual es la condición de habilitación; gestión y contacto son guía, no candados adicionales. Se conservan captura causal, autorización, modos, concurrencia, recuperación e idempotencia. Añadir prueba que permita convertir con asistencia+entrevista válidas aunque no haya una llamada/contacto previo separado, y que impida hacerlo solo por mover una tarjeta.
