# Banco de atención y venta

Candidata del 13/10/2026. Ejecutar desde `CRM-Avance-Corp/`. Estos scripts usan exclusivamente datos sintéticos del banco propio; no ejecutar contra una base productiva. Resultado y límites: [acta](../../../docs/encargos/facturacion-atribucion-20261013/VERIFICACION.md).

## Entorno utilizado

- PostgreSQL: contenedor `avancecorp-facturacion-atribucion-20261013`, imagen `public.ecr.aws/supabase/postgres:17.6.1.105`, puerto local 55483.
- PostgREST: contenedor `avancecorp-facturacion-atencion-rest-20261013`, imagen `public.ecr.aws/supabase/postgrest:v14.5`, puerto local 55484.
- Base `postgres`: esquema sin datos, candidata instalada; `prueba.sql` siempre termina en ROLLBACK.
- Base `atencion_http`: mismo esquema candidato y fixtures persistentes. Credenciales y JWT de los scripts son sintéticos, exclusivos de localhost.
- Snapshot previo de esquema: `/private/tmp/facturacion-atribucion-schema-20261013.sql`. No se versiona el volcado completo. El montaje reutiliza `../potencial-lead/banco/montar-banco.sh` con contenedor/puerto propios. Hay una dependencia esperada de `storage.objects` ausente de la imagen bare, ajena al cambio; se comprobó paridad de todas las funciones CRM y private.

## Repetir las pruebas sobre el banco existente

```bash
env PGPASSWORD=postgres /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 55483 -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -f supabase/scripts/atencion-venta/prueba.sql

node supabase/scripts/atencion-venta/http-concurrencia.mjs
```

SQL: 29 aserciones, con fixtures en una transacción revertida. El script exige que `public.perfiles` esté vacío antes de sembrar. Las bajas históricas y el cierre cooperativo ya convertido se preparan con réplica; todas las llamadas evaluadas usan triggers activos y SET ROLE authenticated/service_role según el caso.

HTTP: JWT de Gerencia, admin portal, vendedor y sin sesión; modificación directa prohibida, una sesión retiene un candado y otra recibe conflicto, después dos confirmaciones simultáneas dejan un solo historial. Restablece la venta sintética mediante el adaptador auditado si se repite; no borra historial.

## Reversa y reinstalación del código, solo banco

```bash
env PGPASSWORD=postgres /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 55483 -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -f supabase/scripts/atencion-venta/reversa.sql \
  -f supabase/scripts/atencion-venta/validar-reversa.sql \
  -f supabase/migrations/20261013192850_crm_atencion_venta_separadas.sql \
  -f supabase/migrations/20261013193653_crm_atencion_venta_hardening.sql \
  -f supabase/scripts/atencion-venta/prueba.sql
```

`validar-reversa.sql` compara las huellas de todas las funciones CRM/private con el snapshot inicial y comprueba permisos restaurados. Solo tiene sentido sobre ese snapshot, sin otras migraciones posteriores. La reversa no elimina datos ni historial. No se ejecuta mientras otra sesión use esta candidata.

## Crear un banco nuevo a partir del snapshot previo

El helper de montaje rechaza un contenedor existente. Usar un snapshot de esquema autorizado y puertos libres; no resetear bancos de otros trabajos.

```bash
env BANCO_CONTENEDOR=avancecorp-facturacion-atribucion-20261013 BANCO_PUERTO=55483 \
  bash supabase/scripts/potencial-lead/banco/montar-banco.sh \
  /private/tmp/facturacion-atribucion-schema-20261013.sql

env PGPASSWORD=postgres /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 55483 -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20261013192850_crm_atencion_venta_separadas.sql \
  -f supabase/migrations/20261013193653_crm_atencion_venta_hardening.sql
```

Para HTTP, crear una base nueva `atencion_http` con el mismo esquema candidato (se puede clonar `postgres` vacío mediante `CREATE DATABASE ... TEMPLATE postgres`, sin sesiones conectadas a esa plantilla). No copiar una base con datos reales. Aplicar `banco-http.sql` como el administrador de ese banco y `fixture-http.sql` como postgres. El primero ajusta únicamente dueño/roles y paridad de `auth.uid()` del banco; no es una migración de producto. El segundo rechaza una base de otro nombre o con perfiles existentes.

El contenedor HTTP usado se crea así, con la base anterior preparada:

```bash
docker run -d --name avancecorp-facturacion-atencion-rest-20261013 \
  -p 127.0.0.1:55484:3000 \
  -e PGRST_DB_URI=postgresql://authenticator:solo-banco-atencion@host.docker.internal:55483/atencion_http \
  -e PGRST_DB_SCHEMAS=public,crm -e PGRST_DB_ANON_ROLE=anon \
  -e PGRST_JWT_SECRET=solo-banco-atencion-secreto-sintetico-20261013 \
  public.ecr.aws/supabase/postgrest:v14.5
```

## Portal en Chromium/Docker

`portal.spec.cjs` carga el HTML y los módulos reales de `public_html`; sustituye auth y transporte con fixtures y bloquea toda red externa. Comprueba revisión antes de guardar, invalidación al editar, conflicto y confirmación de la misma versión. La autorización real se verifica por separado en SQL/HTTP.

```bash
docker run --rm --init --ipc=host -e CI=1 -e ATENCION_PORTAL_DIR=/portal \
  -v "$PWD":/repo -v "$PWD/../public_html":/portal:ro \
  -v avancecorp-crm-e2e-node-modules:/repo/app/node_modules -w /repo/app \
  mcr.microsoft.com/playwright:v1.61.1-noble \
  node node_modules/@playwright/test/cli.js test \
  --config ../supabase/scripts/atencion-venta/playwright.portal.config.cjs
```

El volumen de dependencias se prepara con el runner habitual `app/scripts/e2e-docker.sh`. No usa `_DEV_NO_SUBIR/tests/helpers.js` ni sus credenciales reales.

Advisors de esta candidata: CLI 2.117.0, `db advisors --db-url 'postgresql://postgres:postgres@127.0.0.1:55483/postgres?sslmode=disable' --type all --output json`. El delta observado fue 7 → 7, sin avisos nuevos. Los snapshots de resultados están en la carpeta del acta.

## Integración final con Auth real

`node supabase/scripts/test-rls.mjs --atencion-venta` usa exclusivamente el banco de integración en 56461/56462; `ATENCION_DESTINO=rama` selecciona exclusivamente cdntljznxaubchkhusqo. Las credenciales se leen de archivos privados fuera del repositorio. Resultado final: 83 aserciones en ambos destinos. Incluye offboarding real y rechazo legacy después de una baja que cambia herencia de venta.

La matriz oficial se ejecutó en otro stack aislado (56561/56562), reconstruido antes de `gate-local.mjs semilla` y `gate-local.mjs matriz`: 3.933 aserciones PASS. F4 usa `F4_BANCO=atencion`, sin elegir destinos arbitrarios.

`limite-referidos-oraculo.sql` conserva los primeros 16 casos numéricos del ensayo vigente de límite total de referidos: extraídos hasta antes de la expectativa histórica de atribución NULL, que ya cambió por la herencia del episodio. No altera la implementación y termina en ROLLBACK. El valor absoluto complementa la agregación D8 de la matriz.
