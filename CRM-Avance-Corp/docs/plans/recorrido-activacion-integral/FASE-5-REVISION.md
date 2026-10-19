# Fase 5 — Revisión e integración

Claude entregó **CHANGES_REQUESTED**, con confianza MEDIA. Se conserva el dictamen íntegro en `evidencia/fase5-claude-review.txt`; Codex evaluó cada observación con código y pruebas. No se pidió otro dictamen para sustituirlo por un PASS.

## Resolución de Codex

| Observación | Resolución y evidencia |
|---|---|
| P1, hipótesis: descartar/desactivar un lead con borrador evita los hechos | No se reproduce en las puertas financieras: `private.inversion_persona_contexto_para` rechaza descartados con P0409 e inactivos con 42501 antes del guard. Regresión SQL y HTTP en las dos cooperativas y en reclamar acceso Avance, con borrador previo al bloqueo. El PATCH inactivo del analista además es rechazado por RLS. Se fabrica ese estado únicamente como fixture administrativo para comprobar la segunda defensa. Borradores, Auth y dinero conservados. No se amplía el alcance a clientes cerrados ni se cambia el evaluador por una hipótesis descartada. |
| P2: tres conflictos 40001 deterministas en acceso Portal | Confirmados también en el cuerpo productivo previo: riesgo preexistente. Corrección aditiva 61005/61006 a PT409. HTTP con token real y versión desactualizada devuelve 409 en menos de cinco segundos; claim/Auth intactos y recuperación posterior completa. |
| P3: fecha explícita en observación | Corregido: solo se acepta al configurar exigir. SQL y HTTP negativos PASS. Reversa conserva la fecha sin reenviarla. |
| P3: hashes entre PostgreSQL 17.6 y 17.11 | Replay local PASS sobre PostgreSQL 17.6, igual que producción; rama hosted en 17.11. Preflight productivo de solo lectura PASS en 17.6: seis contratos anteriores y las 509 entradas del historial coinciden. Las huellas intermedias pertenecen a funciones todavía ausentes en producción; se verifican durante el replay y fallan cerradas si hay diferencias. No se afirma haberlas ejecutado en producción. |
| P3: lock compartido del control | Conservado para serializar activación con conversiones. Quitar el lock en observación puede permitir una operación que leyó el modo anterior mientras se activa. Coste aceptado y concurrencia probada; no se extrapola una prueba sintética a capacidad productiva. |

El trigger de conversión es **BEFORE UPDATE OF etapa**; lee el estado previo cuando revalida. El de inserción terminal es **BEFORE INSERT WHEN new.etapa='convertido'**. Definiciones adjuntas en `fase5-evidencia-contexto.json`.

## Verificación después de las correcciones

- SQL local de evaluación, antiguos, borradores cerrados/inactivos, inicio futuro, INSERT terminal antes/después de la fecha y ciclo corrupto: **PASS**.
- Replay de migraciones y hardening, grant ajeno rechazado, instalación/activación concurrente y carreras financieras: **PASS**.
- HTTP/Auth/RLS local y hosted: **99 comprobaciones PASS en cada entorno**. Mismo archivo `http-matriz.mjs`; handler oficial en proceso contra Auth/PostgREST reales, sin afirmar ejecución de Edge desplegada.
- SQL hosted adicional de descarte/inactividad y guard INSERT con exigencia vigente: **PASS**, rollback exacto. La inserción antes/después de una fecha programada y el ciclo corrupto se acreditan localmente; no se repitieron hosted con el control ya activado.
- Reversión hosted, catálogo, historial **524 = 509 + 15**, ACL previas, esquema public y núcleo SLA: **PASS**.
- Advisors repetidos después de 61005/61006: mismos avisos que el cierre de fase 4; sin exposición adicional. Remediaciones y justificaciones en FASE-4-ENSAYO-HOSTED.md.
- `check:scripts` y `git diff --check`: **PASS**. Los otros tres preflights y los **42 E2E Docker** conservan el PASS de fase 3; no hubo cambios de interfaz ni de Edge. Prueba manual con navegador/VoiceOver: **NOT RUN**, conforme a la restricción del usuario.
- SQL propuesto de activación, comprobación negativa y reversión: **PASS local con rollback**. No se ha ejecutado en producción.

## Gate de integración

La revisión y las correcciones de Codex están acreditadas. [PR #332](https://github.com/avanza-digital/avancecorp-crm/pull/332) abierto. CodeRabbit señaló que contar entradas no acredita su identidad; se corrigió el postflight para comparar versión, nombre y MD5 de cada uno de los 15 SQL, además de comprobar el índice operativo. Cinco regresiones PASS: paquete correcto aceptado; versión sustituida, nombre distinto, contenido distinto e índice ausente rechazados, con rollback y sin modificar el ledger real. Ver `evidencia/fase5-postflight-regresiones.json`. Falta terminar la actualización del review y verificar Main antes de generar el paquete exacto. Producción sigue sin backend de recorrido, guía oculta y bloqueo inactivo. El paquete ahora contiene **15 migraciones**, incluidas las ocho ya integradas en PR #331.

La instalación productiva debe presentar primero el SQL concreto. La activación propuesta usa la cuenta administrativa del CRM y un motivo que identifica la actuación técnica autorizada por Miguel; requiere que esa autorización incluya expresamente la activación. No se registrará como un login ni una acción humana realizada en pantalla.

CI inicial del PR en `a7d4fd14`: preflight, app-check (lint, tipos, cobertura y build) y verify PASS. Supabase Preview se omite por la configuración de ruta del repositorio; la rama propia ensayada acredita la base. No hay E2E en GitHub.
