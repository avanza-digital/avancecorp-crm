---
tags: [crm, conversion, c0-1, ficha-360, checkpoint, continuidad]
actualizado: 2026-08-28
estado: candidato-local-certificado-sin-produccion
serial: AVC-F41-360-20260827-R3
serial_origen: AVC-F41-360-20260825-R2
rama: feature/c01-nucleo-unico-20260827
head_origen: 6dda4b4002dbf13b9baf5639744c49edae85a640
sha_candidato_local: a1f7b2ec2608fbbedb6107157fdb7a9033d26a00
base_c01_local: 7c94d77c39f642e27af676dce6178e6b9f64a315
head_canonico_pendiente: 1f012829f4dbd4b45d8d1615d6a579b730dbfb05
commits_canonicos_pendientes: 5
---

# Checkpoint C0.1 — núcleo único — R3

Serial de continuación: **AVC-F41-360-20260827-R3**

Este checkpoint continúa [[Ficha 360 - plan de reintegracion sobre nucleo unico (2026-08-27)]]
y conserva como origen `AVC-F41-360-20260825-R2`. El objetivo comercial de
C0.1 es que HOY, Ranking, Metas, Gestión y Directorio expliquen una sola
conversión mensual, tomada del mismo núcleo, sin fórmulas paralelas ni cifras
aparentemente válidas cuando la cobertura no es confiable.

## Punto seguro alcanzado

- Worktree aislado: `/private/tmp/crm-c01-nucleo-unico-20260827`.
- Rama: `feature/c01-nucleo-unico-20260827`.
- El candidato técnico quedó congelado en
  `a1f7b2ec2608fbbedb6107157fdb7a9033d26a00`; el punto de reanudación original
  era `6dda4b4002dbf13b9baf5639744c49edae85a640`.
- No se creó migración y no se tocó Supabase, producción, PostgREST ni una base
  compartida. Tampoco hubo push ni deploy.
- El clúster PG17, la base y el directorio temporal fueron desechados; no quedó
  ningún `/tmp/crm-c01-local.*`.

## Certificación local ejecutada

- El runner hermético quedó conectado una sola vez desde su snapshot privado,
  rechaza `PGSERVICEFILE` y `PGPASSWORD` además de los demás selectores de
  conexión, y solo usa un socket Unix privado sin TCP.
- La corrida completa aprobó PostgreSQL 17.10, 21 placeholders capturados desde
  el catálogo, sesiones distintas para propuesta y banco, caso real verde,
  mutantes internos verdes y una única salida final
  `C0.1_BANCO_ADVERSARIO_OK`.
- La matriz de cuerpos terminó 17/17: cada mutante murió en su oráculo declarado,
  nunca por sintaxis, fixture o permisos. Las guardas de variables de conexión
  rechazaron las corridas de prueba con código 64.
- El check integral del frontend aprobó 181/181 archivos y 2.424/2.424 pruebas,
  además de cobertura, typecheck, lint, build, bundle de producción y control de
  duplicación. El hook del commit repitió lint y typecheck en verde.
- `bash -n`, `node --check` y `git diff --check` quedaron verdes. El snippet
  duplicado `C0.1-cartera-desde-episodios-snippet.sql` fue eliminado porque su
  contenido ya vivía en la propuesta principal.

## Contrato técnico congelado

- La propuesta reemplaza dos cuerpos sin cambiar firmas:
  `private.metricas_cartera_por_vendedor(date)` y
  `crm.metricas_vendedores_fn()`.
- Los conteos de cartera salen exclusivamente de la pierna `operacion` de
  `private.conversion_episodios`; los importes y desgloses económicos siguen en
  `crm.operaciones_cartera`.
- Los 21 placeholders fail-closed representan 18 cuerpos live, un fingerprint
  agregado de catálogo/ACL y dos hashes candidatos.
- Las funciones definer fijan `search_path=''`, califican sus objetos y dejan el
  RPC público en allowlist owner + `authenticated`; `anon` y `service_role` no
  reciben ejecución directa.
- El gate histórico GCAR-07 es transicional: valida la deduplicación legacy y,
  cuando detecta C0.1, exige episodios sin `row_number`, `orden_conversion` ni
  `elegible_conversion`.
- El banco cubre tres renovaciones, tres upgrades, siete métricas económicas,
  cartera fuera de roster y el borde de doble redondeo: exacto `38.50`, legacy
  `39`, división paralela `38`.
- Se mantiene como gate externo un `EXPLAIN (ANALYZE, BUFFERS)` con volumen
  representativo: una llamada puede materializar episodios hasta tres veces.

## Lecciones del cierre R3

- Después del caso real se restauran solo los dos cuerpos candidatos mediante
  `pg_get_functiondef`; recargar las veinte funciones extraídas colisionaba con
  objetos auxiliares creados por el banco.
- El oráculo de un mutante debe declarar la primera guarda válida que lo detecta.
  Los casos 01, 05, 09 y 10 se calibraron así, sin debilitar la propuesta ni el
  fixture.
- Las cuatro condiciones del cleanup no eran duplicadas: validan directorio,
  prefijo exacto, existencia del marcador y pertenencia al nombre de base. Se
  conservaron porque cada una cierra una frontera distinta.

## Divergencia canónica pendiente

El candidato y el árbol canónico actual comparten `7c94d77`, pero desde allí
divergieron 5/5 commits. El árbol canónico está en
`1f012829f4dbd4b45d8d1615d6a579b730dbfb05`. Antes de integrar C0.1 se deben
reconciliar explícitamente esos cinco commits, revisar los solapes frontend y
repetir el runner más el check integral. El GO local de R3 no autoriza omitir
esta reconciliación.

## Gates que continúan fuera del entorno local

- Reproducir todas las migraciones vigentes, en orden, sobre un runtime
  compatible; el bootstrap focal no equivale a esa prueba.
- Capturar en un servidor autorizado las 18 huellas live y el fingerprint de
  catálogo/ACL, comparar deriva y recalcular los dos hashes candidatos exactos.
- Confirmar permisos reales para los locks de `pg_proc`, `pg_namespace`,
  `pg_authid` y `pg_auth_members`.
- Ejecutar `EXPLAIN (ANALYZE, BUFFERS)` con volumen representativo.
- Revisar y aprobar el SQL exacto; crear/aplicar una migración solo bajo una
  autorización separada.
- Hacer readback PostgREST/JWT por rol y publicar frontend y servidor como una
  sola salida coordinada.

R3 queda cerrado como **candidato local certificado, sin producción**. El
próximo serial debe abrirse al iniciar la reconciliación canónica o cuando se
autorice uno de los gates externos; no hace falta repetir esta corrida mientras
el snapshot no cambie.

Relacionado: [[Conversion unica en todo el CRM - plan de migraciones]],
[[Conversion mensual - definicion cerrada]] y
[[Ficha comercial 360 de clientes - plan]].
