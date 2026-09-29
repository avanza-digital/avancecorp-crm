---
tags: [crm, conversion, reasignacion, backend]
actualizado: 2026-09-29
estado: validado-pendiente-publicacion
---

# Conversión: sincronización al reasignar

**Implementada y validada en una rama Supabase; todavía no activada en producción.**
Miguel pidió la solución permanente después de la reparación puntual. PR
[#137](https://github.com/avanza-digital/avancecorp-crm/pull/137).

El problema era que la reasignación cambiaba el analista del lead mientras la
persona y el borrador conservaban al anterior. La validación de inversión
rechazaba esa discrepancia correctamente.

La migración `20260929201813_crm_reasignacion_conversion_consistente.sql`
agrega un trigger privado diferido al final de la transacción. Tras una
reasignación autorizada, sincroniza la persona y su primera conversión pendiente
usando la RPC canónica de revisión del borrador. Conserva contenido, autoría,
historial y atribución económica. En una baja espera a que termine el traslado
canónico para no crear tramos duplicados.

RLS, roles, ámbito y destinos activos siguen rigiendo. Identidad ambigua,
restricciones, saga o historia incompatible conservan la reasignación del lead
y dejan una nota visible para Gerencia; invertir sigue vetado hasta conciliar.
No prometer que cualquier inconsistencia histórica se corregirá automáticamente.
Con conflicto concurrente se revierte toda la reasignación y se pide reintentar.

Recuperación: Gerencia resuelve la causa y usa las puertas existentes
`reasignar_responsable_relacion_fn` y `revisar_solicitud_inversion_fn`, con la
revisión vigente y en la misma transacción autenticada. No editar tablas a mano.

Verificación: SQL local/remoto 36 PASS cada uno; concurrencia 4; PostgREST 3;
RLS remoto contratos 287 e identidad 30; cliente 88, lint/typecheck y
preflights PASS. Regresión económica, reversa y reinstalación PASS. Advisors
sin avisos nuevos. Guardas: 27 PASS, 5 fallos previos idénticos, cero nuevos.
Dos reviews Claude con observaciones resueltas por el PRIMARY y sus pruebas.
E2E frontend: NOT RUN; no se modifica código frontend de producto.

Rama autorizada `reasignacion-conversion-20260929`, creada 21:45:59 UTC,
US$0,01344/h; ref `zlqywmvvtfknypkmfpbe`. Replay histórico falló y se
reconstruyó exclusivamente la rama con esquema vivo y fixtures sintéticos.
Rebase incorporó el índice productivo `20260929220021`; no se copiaron clientes.
CI completo PASS: 4.925 tests en 318 archivos, tipos, build, bundle y duplicación.
Checks `verify` y `preflight` PASS al 29/09 22:44:29 UTC. El merge normal del
PR #137 fue rechazado por falta de aprobación externa; Miguel la gestionará.
No se usó override. Pendiente integrar Main, merge de Supabase y retirar la rama.

Relacionado: [[Conversion - conciliacion de responsable tras reasignar (2026-09-29)]],
[[Conversion de lead con Nueva inversion - preparado 2026-09-19]],
[[Offboarding seguro del CRM (P04)]] y [[Inicio]].
