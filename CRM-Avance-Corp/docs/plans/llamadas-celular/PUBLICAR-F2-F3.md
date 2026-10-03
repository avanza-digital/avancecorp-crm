# Publicar F2 + F3 de «Llamadas desde el celular» — guía técnica (02/10/2026)

Las 4 migraciones están en `main` desde el PR #169 y **nada está aplicado ni desplegado**. Esta guía dice, en
orden, qué falta para que funcione en producción: el celular avisa solo al CRM de cada llamada saliente y el CRM
la guarda. F1 (la encuesta al colgar) ya está en producción y no cambia.

> **⛔ No aplicar todavía.** La revisión de Miguel del 02/10 (PR #170, `REVISION-2026-10-02.md`) encontró 5 fallos
> que bloquean. Se corrigen con una **quinta migración** (plan: `CORRECCION-PLAN-CORTO.md`), que espera el OK de
> Miguel. Esta guía ya incluye los arreglos de la sección C de la revisión (puntos 17–20, 03/10); la quinta
> migración se suma a los pasos 2 y 3 cuando exista.

Regla del proyecto (`CRM-Avance-Corp/CLAUDE.md`): rama de Supabase → aplicar → gate `test-rls.mjs` →
advisors → merge. **Nunca `apply_migration` directo a producción.**

## 0. Antes de que Miguel empiece (lo preparan Claude y Jhosep)

| # | Qué | Estado al 02/10 |
| --- | --- | --- |
| 0.1 | Escribir el bloque `testLlamadasCelular` en `supabase/scripts/test-rls.mjs` (con su interruptor `CRM_RLS_EXIGE_LLAMADAS`), como pide `F2-PLAN-CORTO.md` | **Escrito el 03/10, sin correr**: `node --check` y `oxlint` limpios. Aquí no hay un banco con el esquema de producción: **lo corre Miguel en el paso 2** |
| 0.2 | ~~Revisión `auditor-rls`~~ → **la hace Miguel** (paso 2) | Jhosep, 02/10: las revisiones las hace Miguel |
| 0.3 | ~~Revisión Codex LEVEL 3~~ → **la hace Miguel** (paso 2): él tiene Codex | Ídem |
| 0.4 | ~~Espejo de la Edge en `_supabase_functions/`~~ | **Retirado el 03/10** (punto 20 de la revisión): `supabase/functions/LEEME.md` dice «sin espejo legado» para esta función. Se despliega desde `CRM-Avance-Corp/supabase/functions/` |
| 0.5 | PR `feat/llamadas-f2` → `main`. `main` tiene que contener lo que se aplica en producción | **Hecho: PR #169** (02/10) |
| 0.6 | Registradores de las 4 migraciones (punto 18): `supabase/scripts/llamadas-celular/registrar-{datos,nucleo,ingesta,elegibilidad}.sql`, con el patrón de `scripts/potencial-lead/` | **Hecho el 03/10**: cada uno lleva su migración idéntica al archivo de git (md5 comprobado). Sin correr: aquí no hay base |
| 0.7 | Archivo del alta de un celular (puntos 17 y 19): `supabase/scripts/llamadas-celular/alta-celular.sql`, el mismo para el ensayo y para producción | **Hecho el 03/10**, sin correr |
| 0.8 | Quinta migración de la corrección, con su reversa, su registrador y el bloque del gate corregido | **Pendiente del OK de Miguel** (`CORRECCION-PLAN-CORTO.md`) |

**El paso 0 queda completo cuando exista la 0.8.** Hasta entonces, no se aplica nada.

## 1. Decisiones de Miguel antes de aplicar

Miguel **ratificó** el 02/10 las 7 decisiones de F2 (`F2-PLAN-CORTO.md`) y las 5 de F3 (`F3-PLAN-CORTO.md`), y
aprobó las propuestas #13–#15. Faltan:
- Las **seis decisiones de la corrección** (`CORRECCION-PLAN-CORTO.md`; la 1 es el fallo 5).
- Tres confirmaciones de la revisión:
  - la regla extra de la decisión 4: el enlace pasa al resultado nuevo;
  - los criterios de Claude de `MIGRACIONES.md`: solo gerencia asigna celulares; el resultado tiene que ser posterior
    a la llamada; el celular es para analista o supervisor; la tabla técnica va en `private` sin bitácora; ventanas
    fijas en el límite; la elegibilidad se evalúa como el dueño del celular; la Edge responde igual a guardada,
    repetida o ignorada. (La llamada a un lead ajeno cambia con la corrección: decisión 3 de su plan.)
  - la propuesta #12 (la respuesta no delata si un número es lead).

Nota para Miguel: las migraciones **no modifican nada de `public`**. Solo referencian `public.perfiles` en
las llaves de autoría, con `ON DELETE RESTRICT`, para que la baja de usuarios detecte su historial (el mismo
criterio que el resto del CRM).

## 2. Revisiones y ensayo en un banco con el esquema de producción (rama de Supabase o copia)

0. **Revisiones (las hace Miguel):**
   - Primera ronda hecha el 02/10: `auditor-rls` pidió cambios y Codex LEVEL 3 r1 dio BLOCK (`REVISION-2026-10-02.md`).
   - Falta la **segunda ronda de Codex sobre el diff de la quinta migración**, con la evidencia nueva
     (`scripts/codex-review-mcp`, encargo por stdin que empieza por `ROLE: SECONDARY_REVIEWER.`; máximo 2 rondas,
     `.ai/REVIEW_PROTOCOL.md`). Codex no ve la base: se le transcribe lo que haya que juzgar.
   - Las migraciones ya commiteadas no se editan: todo arreglo va en una migración nueva.
1. Aplicar **en este orden**:
   1. `20261001145242_crm_llamadas_celular_datos.sql`
   2. `20261001160219_crm_llamadas_celular_nucleo.sql`
   3. `20261001212258_crm_llamadas_celular_ingesta.sql`
   4. `20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql`
   5. La quinta migración de la corrección, cuando exista. **Las cuatro sin la quinta no se aplican.**

   (`20261001212341_crm_cartera_filtro_potencial.sql` es de otro trabajo e independiente.)
2. **Comprobar que `auth.uid()` lee `request.jwt.claim.sub`.** La corrección del supervisor depende de eso:
   ```sql
   select pg_get_functiondef('auth.uid()'::regprocedure);
   ```
   La definición tiene que consultar `current_setting('request.jwt.claim.sub', true)`.
3. Gate: `node supabase/scripts/test-rls.mjs` con `CRM_RLS_EXIGE_LLAMADAS=1` (si el bloque se salta, falla) y con
   `CRM_BANCO_PSQL_URL` (detecta la instalación por el catálogo). El bloque `testLlamadasCelular` va el último y prueba:
   - nadie lee ni toca las 4 tablas directo;
   - cada puerta, solo su rol: gerencia asigna, rota y cierra celulares; supervisión ve los de su equipo; las puertas de
     servicio son solo de `service_role`; anon, coordinación, directorio y un analista de baja, nada;
   - ingesta: clave desconocida → 42501; repetida → mismo evento; otro contenido → **termina normal y gasta cupo,
     sin P0409** (hoy el bloque todavía exige el P0409, que es la fuga 1: se corrige con la quinta migración); dos
     envíos a la vez → un solo evento; número sin lead → no se guarda;
   - con la quinta migración, además: lead borrado (nadie lo ve), entrantes bloqueadas y un enlace real con su
     encuesta;
   - ámbito: dueño, su supervisor y gerencia ven la llamada; otro equipo no la ve ni la toca;
   - la corrección del supervisor (si falla, revisar `auth.uid()`);
   - rotación y cierre: la clave vieja deja de valer.

   Deja la corrida limpia: descarta los eventos, cierra los celulares y desactiva su lead. Lo que no cubre (reasignación
   del lead, enlace con la encuesta, límite por minuto) lo prueban los oráculos del banco reducido
   (`npm run test:llamadas:local`).
4. `supabase/scripts/llamadas-celular/verificar-datos.sql`.
   - 4b. **Ensayar el alta de un celular por la misma vía que en producción** (punto 19): `alta-celular.sql` con
     `db query --file`, con un usuario de gerencia del banco y un analista activo. Esperado: devuelve la clave una
     vez. Con un usuario que no es gerencia, 42501. Después, cerrar esa asignación de prueba.
   - 4c. Correr los cuatro registradores (y el de la quinta), cada uno después de su migración: esperado
     `REGISTRO: <versión> / <nombre> (1 sentencia: el archivo entero)`.
5. El trabajo de retención quedó programado:
   ```sql
   select jobname, schedule, active from cron.job where jobname = 'crm-llamadas-celular-caducidad';
   ```
   Esperado: `23 6 * * *`, activo.
6. Advisors de seguridad y rendimiento: ninguna alerta nueva.
7. Ensayar la reversa en orden inverso: `reversa-elegibilidad.sql` → `reversa-ingesta.sql` →
   `reversa-nucleo.sql` → `reversa-datos.sql` (en `supabase/scripts/llamadas-celular/`).

## 3. Producción (con el `!` de Miguel)

1. Las migraciones en el mismo orden, **una por mensaje**, con `db query --linked --file`, y después de cada una su
   registrador (`supabase/scripts/llamadas-celular/registrar-*.sql`, punto 18): `db query --file` aplica, pero no
   anota la migración en el historial. Los registradores se corren desde un checkout con finales de línea LF (la Mac
   de Miguel), porque comparan el md5 del archivo. Marcarlas «EN PROD» en `MIGRACIONES.md`.
2. Tipos: `npm run gen:types` en `app/` y commit. La pantalla todavía no usa las puertas nuevas (llegan en F4).
3. Edge, desde `CRM-Avance-Corp/`:
   ```bash
   npx supabase@2.114.0 functions deploy crm-llamadas-ingesta --project-ref dctqcbznekcyxhjujuci --use-api
   ```
   Toma `verify_jwt = false` de `supabase/config.toml`, donde está documentado el motivo. **No necesita secretos
   nuevos**: usa `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`, que Supabase pone en toda Edge.
4. Comprobar el despliegue, sin clave:
   ```bash
   curl -s -X POST https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta \
     -H 'content-type: application/json' -d '{}'
   ```
   Esperado: `{"error":"No autorizado"}` (el 401 de la propia función). Un «Invalid JWT» de la plataforma
   significaría que `verify_jwt` quedó encendido.

## 4. Dar de alta el celular C1

- Solo gerencia asigna celulares: `crm.asignar_celular('C1', '<uuid del analista>')`. Devuelve la
  `credencial` **una sola vez**: en la base solo queda su sha256.
- El dueño tiene que ser **analista (`vendedor`) o supervisor activo**. Si la cuenta de Jhosep no tiene ese rol,
  se asigna a un analista del piloto.
- Todavía no hay pantalla para esto (llega en F4). Se usa `supabase/scripts/llamadas-celular/alta-celular.sql`,
  ensayado en el paso 2.4b: se cambian sus tres valores (uuid de gerencia, etiqueta y uuid del analista) y se corre
  con `npx supabase db query --linked --file supabase/scripts/llamadas-celular/alta-celular.sql`.
- **⚠️ La salida trae la clave en claro (punto 17).** Miguel lo corre **en su propia terminal**, nunca en una sesión
  de Claude ni pegando la salida en un chat: lo que pasa por Claude queda en la conversación. La clave se copia
  directo al celular, o se le pasa a Jhosep por un canal privado, y después se limpia la terminal.
- Nunca va al repo, a un chat de grupo ni a un registro. El archivo no se commitea con valores reales.

## 5. Cambiar la macro de C1 (Jhosep, con Claude)

1. **Antes de nada, vaciar `cola_llamadas`** (MacroDroid → Variables globales). Tiene avisos de prueba, con
   números reales y horas antiguas: si se mandan a producción, entrarían como llamadas de verdad.
2. En «Llamadas-Enviar cola» → «Solicitud HTTP»: URL
   `https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta`, y en «Parámetros de
   Encabezado» la clave real en `x-celular-credencial`.
3. Repetir A1 y A3 **con datos móviles**, y las pruebas 1 y 6 de F3.3 (`macrodroid.md` §3c, `REGISTRO.md` §5d).
4. Comprobar en la base que la llamada a un lead quedó guardada y que la de un número sin lead no se guardó
   (decisión 3).

## Reversa

- Edge: borrar la función o volver a desplegar la anterior.
- Base: primero la reversa de la quinta migración (cuando exista); después las del paso 2.7, en orden inverso.
  `reversa-datos-total.sql` borra también los datos.
- Celular: volver la URL de la «Solicitud HTTP» al receptor de pruebas. Apagar «Llamadas-Enviar cola» no basta:
  «Llamadas-Al colgar» la lanza con «Siempre iniciar». Para cortar el envío hay que quitar también su acción
  «Iniciar macro».
