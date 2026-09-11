# F7 multiempresa — informe de Gerencia en sombra

Candidata local del 11/09/2026. **No instalada ni publicada en producción.**
G6 requiere conciliación y firma humana; F8/F9 siguen pendientes.
Este módulo es distinto de los antiguos scripts `gate-f7-*` de altas.

La pantalla **Empresas** reúne capital, cantidad de inversiones, personas en
una/dos/tres empresas, primeras y posteriores registradas, atribución,
conversión, vencimientos y oportunidades. Reutiliza los componentes del CRM.
Avance, Qorilazo y Prodelco conservan sus importes PEN/USD separados.
Comisiones externas. [Significado exacto de las cifras](CONTRATO.md).

## SQL y compatibilidad

- [Migración exacta](../../migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql):
  cuatro funciones nuevas, una bandera OFF, sin tablas ni cambios en núcleos,
  permisos previos, dinero, Auth, periodos sellados o banderas F4/F5/F6.
- Dos RPC `crm.metricas_multiempresa_estado_fn()` y
  `crm.metricas_multiempresa_fn(date)`. Solo Gerencia activa en CRM y Portal.
  No admite parámetros de ámbito. Auxiliares privados cerrados a Data API.
- [Reversa](reversa-operativa.sql): apaga solo F7 y conserva objetos e historia.
- [Base productiva leída](base-productiva-2026-09-11.json): cuatro huellas,
  273 migraciones, F7 ausente, F3 ON y F4/F5/F6 OFF. La migración rechaza una
  divergencia de los lectores antes de crear objetos.
- El frontend tolera únicamente `PGRST202` como RPC aún ausente. OFF no pide
  cifras. Un error de red, permiso revocado o contrato incompleto oculta los
  datos anteriores; no convierte el error en un informe de ceros.
- Los tipos se generaron con `supabase gen types typescript` contra la copia
  F7; se integraron solo las dos firmas nuevas en `database.types.ts` para
  conservar los contratos ajenos que no existen en el banco sintético.

## Banco local reproducible

Destino cerrado en `banco-local.mjs`: contenedor
`supabase_db_avancecorp-f5-bank`, base **`multiempresa_f7_20260911`**, puerto
Postgres 58322. No acepta URL ni base del llamador. La base `postgres` original
del banco F5/F6 se conserva. Nunca ejecutar estas sondas contra datos reales.

La copia se preparó desde un `pg_dump -Fc` del banco ficticio F6 con schemas
`public,crm,private,auth,storage`, restaurado en una base nueva de `template0`
con `pgcrypto`, `uuid-ossp`, `btree_gist` y `pg_trgm`. El dump, claves locales y
fixtures se guardan en el respaldo privado, fuera de Git:
`/private/tmp/avancecorp-f7-20260911` y `/private/tmp/avancecorp-f5-bank`.
Para una máquina nueva hay que restaurar ese banco privado antes de las pruebas;
estos scripts no siembran ni descargan datos de producción.

El lector de conversión del antiguo banco omitía tres comentarios respecto a
producción. Se cotejó el cuerpo y se restauró su definición exacta únicamente
en la nueva copia F7. Las cuatro huellas ensayadas coinciden con producción;
la migración F7 no reemplaza ninguna de esas funciones.

PostgREST exclusivo: contenedor `avancecorp-multiempresa-f7-rest`, puerto
59431, conectado solo a la nueva base. Usa la imagen/configuración JWT del
banco local. El ajuste `pgrst.db_schemas='public,crm'` se aplicó únicamente al
rol `authenticator` **en esa base**; no al rol global ni a otros bancos.
Auth real del banco F5 (58321) emite las sesiones ficticias usadas por HTTP.

Desde `CRM-Avance-Corp`, ejecutar en serie:

```sh
npm run check:multiempresa:f7
npm run test:multiempresa:f7
npm run check:scripts
npm run seed:preflight
npm run test:rls:preflight
npm run test:edge-preflight
```

Seed/RLS preflight reciben exclusivamente las variables del banco local;
son validaciones offline. `test:multiempresa:f7` sí usa PostgreSQL, Auth y
PostgREST reales. El primer test reinstala solo los cuatro objetos nuevos y
su bandera en la copia descartable. Los fixtures transaccionales revierten;
HTTP restaura la bandera en `finally`. No lanzar ambos archivos en paralelo.
El comando usa `--experimental-strip-types` (compatible con el mínimo Node
22.12 del proyecto) para ejecutar el mismo esquema TypeScript del frontend
sobre el JSON devuelto por PostgreSQL y HTTP, sin un validador paralelo.

Desde `CRM-Avance-Corp/app`:

```sh
npm run check:all
```

En una máquina compartida, los mismos gates pueden ejecutarse con concurrencia
acotada, sin cambiar los límites ni las aserciones:

```sh
VITEST_MAX_WORKERS=2 npm run check
npm run test:e2e -- --workers=2
```

La variable está soportada por la versión instalada de Vitest y también puede
usarse al hacer push: el hook conserva la suite completa. La evidencia final
identifica los comandos exactos usados y los intentos anteriores que fallaron.

Playwright usa loopback y respuestas sintéticas interceptadas. Las capturas
contienen cifras inventadas; no son una conciliación real ni una revisión
manual de Miguel. El modo demo requiere `VITE_ENABLE_DEMO=true` y build de
desarrollo; no se habilita en el artefacto productivo.

## Instalación posterior

1. Revisar y aprobar el SQL concreto. Integrar cambios de `avancecorp/main`,
   sin sobrescribir ni hacer force push; publicar solo un artefacto construido
   desde el commit verificado común de Main y `avancecorp/main`.
2. Preparar la rama Supabase autorizada, sembrar datos ficticios antes del
   ensayo y comprobar huellas contra el padre. Ensayar el archivo exacto en
   transacción, permisos, paridad, reversa, matriz RLS pertinente y advisors.
   Registrar las diferencias del gate general preexistente, sin llamarlo PASS.
3. Publicar primero el consumidor compatible con RPC ausente/OFF. Antes del
   merge de Supabase volver a verificar padre, historial, hashes y artefacto.
   No `apply_migration` directo a producción, `db push`, repair ni replay global.
4. Instalar únicamente esta migración por el ciclo de rama. Verificar las cuatro
   funciones, propietarios, ACL, bandera OFF y núcleos/datos anteriores intactos.
   La publicación no activa los escritores F4, la ficha F5 ni la postventa F6.
5. Realizar la lectura de conciliación acordada con Gerencia y completar
   [el acta G6](ACTA-G6.md). El ensayo sintético no firma el informe real, no
   resuelve los quince huecos históricos ni autoriza el piloto económico F8.

La medición local de rendimiento sirve solo como evidencia del banco pequeño;
las mediciones con volumen real y los gates remotos pertenecen al ensayo de
instalación y posterior conciliación.

Código guardado en `2a9ff19`, sobre `avancecorp/main@5d49bcf`. El respaldo
duradero se conserva en `/Users/usuario/.codex/backups/avancecorp-f7-20260911`;
incluye un bundle Git, dumps sintéticos y evidencia privada. No copiar las
claves locales a Git. [Estado de aceptación](ACEPTACION.md).

El informe completo se actualiza al entrar, cambiar mes o pulsar Actualizar;
no consulta toda la historia cada treinta segundos. El estado de permiso se
verifica cada quince segundos cuando está activo, y cada cinco minutos si el
informe no está disponible. Una revocación oculta el contenido almacenado.
