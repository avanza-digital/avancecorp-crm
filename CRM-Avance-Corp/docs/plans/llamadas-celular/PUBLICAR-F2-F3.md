# Publicar F2 + F3 de «Llamadas desde el celular» — guía técnica (02/10/2026)

Todo está preparado en la rama `feat/llamadas-f2` y **nada está aplicado ni desplegado**. Esta guía dice, en
orden, qué falta para que lo de hoy funcione en producción: el celular avisa solo al CRM de cada llamada
saliente y el CRM la guarda. F1 (la encuesta al colgar) ya está en producción y no cambia.

Regla del proyecto (`CRM-Avance-Corp/CLAUDE.md`): rama de Supabase → aplicar → gate `test-rls.mjs` →
advisors → merge. **Nunca `apply_migration` directo a producción.**

## 0. Antes de que Miguel empiece (lo preparan Claude y Jhosep)

| # | Qué | Estado al 02/10 |
| --- | --- | --- |
| 0.1 | Escribir el bloque `testLlamadasCelular` en `supabase/scripts/test-rls.mjs` (con su interruptor `CRM_RLS_EXIGE_LLAMADAS`), como pide `F2-PLAN-CORTO.md` | **No existe todavía**: los planes lo citan, pero no se escribió |
| 0.2 | ~~Revisión `auditor-rls`~~ → **la hace Miguel** (paso 2) | Jhosep, 02/10: las revisiones las hace Miguel |
| 0.3 | ~~Revisión Codex LEVEL 3~~ → **la hace Miguel** (paso 2): él tiene Codex | Ídem |
| 0.4 | Espejo de la Edge en `_supabase_functions/functions/crm-llamadas-ingesta/` (`index.ts` y `handler.ts` byte a byte, como `crm-notificaciones-tasa`) | Pendiente |
| 0.5 | PR `feat/llamadas-f2` → `main`. `main` tiene que contener lo que se aplica en producción | Pendiente |

## 1. Decisiones de Miguel antes de aplicar

Las migraciones llevan las decisiones **provisionales** de Jhosep. Si Miguel cambia alguna, se hace una
migración nueva antes de aplicar:
- Las 7 de F2 (`F2-PLAN-CORTO.md`) y las 4 de F3 (`F3-PLAN-CORTO.md`).
- Las de criterio de Claude (`MIGRACIONES.md`): solo gerencia asigna celulares; la llamada a un lead ajeno
  queda por revisar; el resultado tiene que ser posterior a la llamada; el celular es para analista o
  supervisor; la tabla técnica va en `private` sin bitácora; ventanas fijas en el límite; la elegibilidad se
  evalúa como el dueño del celular; la Edge responde igual a guardada, repetida o ignorada.
- Propuesta #12 (la respuesta no delata si un número es lead).

Nota para Miguel: las migraciones **no modifican nada de `public`**. Solo referencian `public.perfiles` en
las llaves de autoría, con `ON DELETE RESTRICT`, para que la baja de usuarios detecte su historial (el mismo
criterio que el resto del CRM).

## 2. Revisiones y ensayo en un banco con el esquema de producción (rama de Supabase o copia)

0. **Revisiones (las hace Miguel; Jhosep, 02/10):**
   - `auditor-rls` (subagente de Claude) sobre las 4 migraciones: lo que toca funciones, grants y RLS.
   - Codex LEVEL 3 (`scripts/codex-review-mcp`, encargo por stdin que empieza por `ROLE: SECONDARY_REVIEWER.`).
     Codex no ve la base: se le transcriben las 4 migraciones y lo que haya que juzgar. Máximo 2 rondas, con
     evidencia nueva (`.ai/REVIEW_PROTOCOL.md`).
   - Lo que acepten las revisiones va en una migración nueva antes de aplicar; las migraciones ya commiteadas
     no se editan.
1. Aplicar **en este orden**:
   1. `20261001145242_crm_llamadas_celular_datos.sql`
   2. `20261001160219_crm_llamadas_celular_nucleo.sql`
   3. `20261001212258_crm_llamadas_celular_ingesta.sql`
   4. `20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql`

   (`20261001212341_crm_cartera_filtro_potencial.sql` es de otro trabajo e independiente.)
2. **Comprobar que `auth.uid()` lee `request.jwt.claim.sub`.** La corrección del supervisor depende de eso:
   ```sql
   select pg_get_functiondef('auth.uid()'::regprocedure);
   ```
   La definición tiene que consultar `current_setting('request.jwt.claim.sub', true)`.
3. Gate: `CRM_RLS_EXIGE_LLAMADAS=1 node supabase/scripts/test-rls.mjs` (con el bloque del paso 0.1).
4. `supabase/scripts/llamadas-celular/verificar-datos.sql`.
5. El trabajo de retención quedó programado:
   ```sql
   select jobname, schedule, active from cron.job where jobname = 'crm-llamadas-celular-caducidad';
   ```
   Esperado: `23 6 * * *`, activo.
6. Advisors de seguridad y rendimiento: ninguna alerta nueva.
7. Ensayar la reversa en orden inverso: `reversa-elegibilidad.sql` → `reversa-ingesta.sql` →
   `reversa-nucleo.sql` → `reversa-datos.sql` (en `supabase/scripts/llamadas-celular/`).

## 3. Producción (con el `!` de Miguel)

1. Las 4 migraciones en el mismo orden, con el procedimiento habitual (`db query --linked --file` + registro en
   el historial). Marcarlas «EN PROD» en `MIGRACIONES.md`.
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
- Todavía no hay pantalla para esto (llega en F4). Desde SQL, actuando como gerencia (no lo probé en producción):
  ```sql
  begin;
  select set_config('request.jwt.claim.sub', '<uuid de un usuario de gerencia>', true);
  set local role authenticated;
  select crm.asignar_celular('C1', '<uuid del analista>');
  commit;
  ```
- La clave se pasa a Jhosep por un canal privado. Nunca va al repo, a un chat de grupo ni a un registro.

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
- Base: las reversas del paso 2.7, en orden inverso. `reversa-datos-total.sql` borra también los datos.
- Celular: volver la URL de la «Solicitud HTTP» al receptor de pruebas. Apagar «Llamadas-Enviar cola» no basta:
  «Llamadas-Al colgar» la lanza con «Siempre iniciar». Para cortar el envío hay que quitar también su acción
  «Iniciar macro».
