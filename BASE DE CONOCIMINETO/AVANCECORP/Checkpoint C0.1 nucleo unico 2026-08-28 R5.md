---
tags: [crm, conversion, c0-1, ficha-360, checkpoint, release, continuidad]
actualizado: 2026-08-28
estado: listo-para-aprobacion-deploy-sin-produccion
serial: AVC-F41-360-20260828-R5
serial_origen: AVC-F41-360-20260828-R4
rama: feature/c01-nucleo-unico-r5-20260828
base_release_vivo: 03f2abce82a711614313b9fa9f733e1414ca3624
merge_release_vivo: c5d6e09
---

# Checkpoint C0.1 — núcleo único — R5

Serial de continuación: **AVC-F41-360-20260828-R5**

Este checkpoint reemplaza como punto vigente a
[[Checkpoint C0.1 nucleo unico 2026-08-28 R4]] y continúa
[[Conversion unica en todo el CRM - plan de migraciones]].

## Veredicto actual

C0.1 quedó técnicamente preparado para aprobación y despliegue coordinado, pero
**todavía no está aplicado ni publicado en producción**. La rama R5 integró el
release F6 que estaba vivo (`03f2abc`) mediante el merge `c5d6e09`, por lo que
el candidato no pierde cambios productivos anteriores.

- Worktree aislado: `/private/tmp/crm-c01-nucleo-unico-r4-20260828`.
- Rama: `feature/c01-nucleo-unico-r5-20260828`.
- El árbol canónico sucio y su rama no fueron modificados.
- No se aplicó DDL irreversible ni se desplegó el frontend a Hostinger.

## Base viva y compatibilidad SQL

- Se capturaron las 18 funciones ancladas desde Supabase y las 18 coincidieron
  con las migraciones canónicas.
- Fingerprint live de catálogo/ACL:
  `91029038fb842066de0c29443d599715`.
- Hash candidato de `private.metricas_cartera_por_vendedor(date)`:
  `a5ec29bd68511a286a3d2ea4d316a9be`.
- Hash candidato de `crm.metricas_vendedores_fn()`:
  `d8226991aba1783b042eaf087568ba49`.
- La estrategia de exclusión se adaptó a Supabase administrado: 18
  `ALTER FUNCTION ... COST` conservando el costo vivo fuerzan la actualización
  de cada tupla `pg_proc`; el XID se comprueba al adquirir y al cerrar los
  locks. No se afirma poder bloquear `pg_authid`, `pg_auth_members` ni
  `pg_namespace` con el rol del proyecto.
- El SQL completo fue ejecutado contra la base viva dentro de una transacción
  que terminó en `ROLLBACK`. El readback posterior confirmó 18/18 huellas
  baseline intactas.

## Migración e historial remoto

La migración materializada es:

`CRM-Avance-Corp/supabase/migrations/20260828173154_crm_c0_1_metricas_vendedores_nucleo_unico.sql`

SHA-256:
`f232306bb088ec6e71bd3fcefd953fb4609f3f8d3e30e2ea916599f2ddd8bf14`.

El historial local del repositorio no coincide con el remoto y no se reparó a
ciegas. Se creó un directorio de release aislado desde `migration fetch`; el
dry-run de `db push` propuso **una sola migración**, la de C0.1.

La reproducción integral desde cero llegó hasta la migración histórica
`20260812000259_crm_cierres_externos.sql` y allí abortó porque su postflight
exige una fila real de `crm.equipo` que el historial no siembra. Es un defecto
de replay histórico anterior a C0.1. La compatibilidad específica de C0.1 quedó
probada directamente sobre datos y esquema vivos mediante la transacción con
rollback.

## Rollback ejecutado

La reversa exacta vive en:

`artifacts/sql-proposals/C0.1-metricas-vendedores-nucleo-unico.rollback.sql`

SHA-256:
`d258702ebd704a2a182fa4eaafb46b7dbf22a22a0b18819958456125d5358f94`.

Restaura los dos cuerpos baseline, owner `postgres`, `COST 100`, comentarios y
ACL directas. En PostgreSQL 17.10 aprobó el ciclo
`forward → rollback → forward`; una segunda reversa abortó porque el estado ya
no era el candidato aprobado. El banco adversarial volvió a cerrar con un único
`C0.1_BANCO_ADVERSARIO_OK` y 17/17 mutantes cazados.

Evidencia sin datos:
`/private/tmp/c01-evidence-r5-roundtrip-20260828`.

## Frontend y pruebas

Los fixtures E2E reales fueron actualizados a los contratos vigentes: núcleo
mensual completo, cartera obligatoria y Distribución V3. No se cambió lógica
productiva en esa corrección.

- `npm run check`: 182/182 archivos y 2.430/2.430 pruebas.
- Cobertura: statements 75,19 %, branches 71,44 %, functions 73,54 % y lines
  77,55 %.
- Lint, typecheck, build, bundle y duplicación verdes; permanecen cuatro avisos
  de accesibilidad preexistentes del carrusel y el aviso no bloqueante de chunk.
- Playwright completo: 107 aprobadas, 26 omitidas por diseño y 0 fallos.

## Gate productivo pendiente

El orden seguro sigue siendo:

1. construir y verificar el release frontend puente desde un commit limpio;
2. validar una preview y el smoke de roles;
3. obtener aprobación expresa de Miguel sobre los hashes exactos del frontend,
   la migración, el banco y el rollback;
4. publicar el frontend en `crm.miavance.com` y comprobar hash servido;
5. repetir el dry-run remoto y aplicar únicamente C0.1;
6. hacer readback de hashes/ACL, PostgREST/JWT por rol, paridad, rendimiento y
   logs; ante cualquier desviación, ejecutar la reversa exacta.

Hasta completar esos pasos, los asesores siguen usando el frontend puente
actual y C0.1 no debe declararse productivo.

Relacionado: [[Conversion mensual - definicion cerrada]],
[[Deploy a Hostinger]], [[Ficha comercial 360 de clientes - plan]] y
[[Auditoria conversion CRM - nucleo unico (handoff 2026-08-26)]].
