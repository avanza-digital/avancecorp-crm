---
tags: [crm, conversion, c0-1, ficha-360, checkpoint, release, continuidad]
actualizado: 2026-08-28
estado: desplegado-y-verificado-en-produccion
serial: AVC-F41-360-20260828-R5
serial_origen: AVC-F41-360-20260828-R4
rama: feature/c01-nucleo-unico-r5-20260828
base_release_vivo: 03f2abce82a711614313b9fa9f733e1414ca3624
merge_release_vivo: c5d6e09
commit_fuente: d2ebf50b2a5394eb77813e8920c81595356075c3
build_productivo: build-20260828T193547294Z
zip_sha256: 4e4362f1a13eac9d8c95701c6b483de7bf8e841cc6a59206e3e8d6ba212f6ebc
migracion_productiva: 20260828173154_crm_c0_1_metricas_vendedores_nucleo_unico.sql
---

# Checkpoint C0.1 — núcleo único — R5

Serial de continuación: **AVC-F41-360-20260828-R5**

Este checkpoint reemplaza como punto vigente a
[[Checkpoint C0.1 nucleo unico 2026-08-28 R4]] y continúa
[[Conversion unica en todo el CRM - plan de migraciones]].

## Veredicto actual

C0.1 está **aplicado, publicado y verificado en producción**. Desde el cierre
del 2026-08-28 los asesores pueden usar Gestión de cartera y el equipo puede
usar sus métricas con un único núcleo mensual. La rama R5 integró el release F6
que estaba vivo (`03f2abc`) mediante el merge `c5d6e09`, por lo que el
candidato no perdió cambios productivos anteriores.

- Worktree aislado: `/private/tmp/crm-c01-nucleo-unico-r4-20260828`.
- Rama: `feature/c01-nucleo-unico-r5-20260828`.
- El árbol canónico sucio y su rama no fueron modificados.
- Commit fuente del release: `d2ebf50b2a5394eb77813e8920c81595356075c3`.
- La migración C0.1 quedó aplicada en Supabase y el frontend corregido quedó
  desplegado en Hostinger.

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

El historial local del repositorio no coincidía con el remoto y no se reparó a
ciegas. Se creó un directorio de release aislado desde `migration fetch`; el
dry-run de `db push` propuso **una sola migración**, la de C0.1. Se aplicó esa
única migración y el dry-run posterior cerró `upToDate: true`.

La reproducción integral desde cero llegó hasta la migración histórica
`20260812000259_crm_cierres_externos.sql` y allí abortó porque su postflight
exige una fila real de `crm.equipo` que el historial no siembra. Es un defecto
de replay histórico anterior a C0.1. La compatibilidad específica de C0.1 quedó
probada directamente sobre datos y esquema vivos mediante la transacción con
rollback.

## Rollback preparado y probado

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
- Cobertura final: statements 75,34 %, branches 71,54 %, functions 73,56 % y
  lines 77,73 %.
- Lint, typecheck, build, bundle y duplicación verdes; permanecen cuatro avisos
  de accesibilidad preexistentes del carrusel y el aviso no bloqueante de chunk.
- Playwright completo: 107 aprobadas, 26 omitidas por diseño y 0 fallos.

## Cierre productivo del 2026-08-28

La primera compilación `crm-20260828T182359Z-d2ebf50b2a53` (ZIP SHA-256
`9e63a3898cc00a019d6c7d1dca0206fa0a090558234ca0bdadc5b5811776c859`)
se invalidó: el worktree aislado no tenía el `app/.env` ignorado por Git y el
smoke de Chrome detectó que el acceso con cuenta quedaba deshabilitado. Se
revirtió inmediatamente el frontend al F6 exacto
`crm-20260828T165035Z-03f2abce82a7.zip` (SHA-256
`5d6b0de859168ababad1e079457e7048f05a4241cfc39ab108bb10b384deef9f`).
La base C0.1 permaneció aplicada porque el puente F6 era compatible. No se
filtró ninguna llave privilegiada: al primer artefacto le faltaba configuración
pública.

Se copió al worktree solo el `.env` productivo ignorado, se validaron
`VITE_SUPABASE_URL` y la llave pública/anon contra el project ref correcto,
y se rechazó cualquier llave `service_role` o `secret`. El segundo
`npm run check` volvió a cerrar verde con 182/182 archivos y 2.430/2.430
pruebas. Miguel aprobó expresamente el ZIP corregido:

- Release: `crm-20260828T193547Z-d2ebf50b2a53`.
- Build: `build-20260828T193547294Z`.
- ZIP SHA-256:
  `4e4362f1a13eac9d8c95701c6b483de7bf8e841cc6a59206e3e8d6ba212f6ebc`.
- Manifiesto SHA-256:
  `e245313605bd0ac9a6ea5747438463e4b49f9de7d2a485ab943a6664dd94247b`.
- `index.html` SHA-256:
  `0b7790759a43256841e98057ab81caa5cbcd0969dff736d80c5942a3cfb6bfba`.
- `assets/index-BOt3HtRl.js` SHA-256:
  `eb673e566542475eca79ba0d014d6683e7cddbefcfdf7d129b3a0267a259f9b3`.
- Puente `assets/use-metricas-vendedores-operativas-BFg0dJTb.js` SHA-256:
  `215ea43db224b4a1cdc4556b2ae3ab17a11ad49af39a2a37533a82f5ffe6a39f`.

Hostinger publicó el ZIP corregido. `version.json`, `index.html`, el bundle
principal, el puente, CSS y el chunk de API coincidieron byte a byte con el
release aprobado; el ZIP público respondió 404. El bundle contiene el project
ref y una llave pública/anon, sin `service_role` ni secretos.

Readback final de Supabase:

- `crm.metricas_vendedores_fn()`:
  `md5(prosrc) = d8226991aba1783b042eaf087568ba49`.
- `private.metricas_cartera_por_vendedor(date)`:
  `md5(prosrc) = a5ec29bd68511a286a3d2ea4d316a9be`.
- La migración `20260828173154` está registrada.
- `authenticated` puede ejecutar la RPC y `anon` no.
- La paridad JWT cerró por rol: gerencia 25 vendedores/2 equipos; supervisor
  10/1; vendedor exactamente su propia fila; coordinador 0/0 con totales nulos,
  sin inventar métricas.
- Rendimiento observado: gerencia 66,584 ms; supervisor 61,611 ms; vendedor
  53,069 ms; coordinador 5,336 ms; sin lecturas de disco ni temporales.

Smoke final autenticado:

- Mi cartera cargó datos reales sin errores.
- Gestión de equipo cargó una tabla de 8 filas, etiquetas de conversión de
  agosto de 2026, cero mensaje de fallo de métricas y cero errores/advertencias
  de consola.
- Ventana de logs posterior al release: API 100 eventos (95×200, 4×201 y
  1×101), 54 RPC, 2 hits explícitos de métricas C0.1 y 0 respuestas 5xx; Auth
  27/27 en nivel `info`; PostgreSQL sin errores relacionados con C0.1. El único
  ERROR del intervalo fue una consulta ajena (`column "monto" does not exist`).

Rollback SQL inmediato:
`artifacts/sql-proposals/C0.1-metricas-vendedores-nucleo-unico.rollback.sql`.
Rollback frontend probado: F6 exacto indicado arriba.

Relacionado: [[Conversion mensual - definicion cerrada]],
[[Deploy a Hostinger]], [[Ficha comercial 360 de clientes - plan]] y
[[Auditoria conversion CRM - nucleo unico (handoff 2026-08-26)]].
