ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo: revisar la migración «Retirar cuenta» y «Cambiar cuenta de pago» solo en READ COMMITTED (CRM Avance Corp, 02/10/2026)

Eres el SECONDARY_REVIEWER (asesor). No tienes base de datos ni red: TODO lo que debes juzgar va transcrito aquí. El PRIMARY (Claude) decide con evidencia y ejecuta los checks reales. Responde en español con: VERDICT (APPROVE / APPROVE_WITH_NITS / REQUEST_CHANGES), SUMMARY, FINDINGS P0–P3 (cada uno con evidencia: línea o fragmento citado; distingue hipótesis), RIESGOS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Reglas del proyecto que aplican
- Arquitectura en 4 capas: núcleo en `private` (SECURITY DEFINER solo con justificación, `set search_path = ''`, nombres calificados, verificación explícita de rol); puertas INVOKER en `crm`; la pantalla (portal) solo llama a las puertas por PostgREST (siempre READ COMMITTED).
- Nunca editar una migración ya commiteada; cada migración indica cómo revertirse; nivel 3 (permisos/datos) → 1 review de Codex + auditor-rls; el PRIMARY ejecuta banco y reporta PASS/FAIL/NOT RUN.
- Las funciones afectadas: `private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)` (F4, 27/09) y `private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)` (F3, 26/09, corregida 27/09). Ambas SECURITY DEFINER, search_path vacío, EXECUTE solo para authenticated (más el dueño), llamadas por las puertas INVOKER `crm.retirar_cuenta_cliente` y `crm.cambiar_cuenta_pago_contratos`.
- Antecedente: `private.asignar_cuenta_pago_contrato_autorizado` (20261002005004) ya lleva esta negativa como primera comprobación: `if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then raise exception using errcode = '0A000', message = 'La asignación no admite este modo de transacción'; end if;`. En su banco se midió que, en RR/SERIALIZABLE, «Retirar» podía retirar una cuenta recién asignada que en READ COMMITTED se niega a retirar (lee el vínculo con una fotografía anterior), y «Cambiar» podía dar por vigente a un admin ya revocado. Decisión de Miguel (02/10): migración aparte, después de F6. Objetivo: SOLO ese cierre; nada más cambia.

## La migración (cuerpos sustituidos por su DIFF; el resto literal)
```sql
-- Cuentas de pago · «Retirar cuenta» y «Cambiar cuenta de pago» solo en READ COMMITTED (02/10/2026).
--
-- Qué hace: a los dos núcleos (private.retirar_cuenta_cliente_autorizado, F4 del 27/09, y
-- private.cambiar_cuenta_pago_contratos_autorizado, F3 del 26/09 corregida el 27/09) se les añade, como
-- PRIMERA comprobación, la misma negativa de modo de transacción que ya lleva «Asignar cuenta»
-- (20261002005004): si la transacción no va en READ COMMITTED, error 0A000 antes de mirar nada. El resto
-- del cuerpo queda byte a byte igual: mismas puertas, permisos, candados, textos de error y registros.
--
-- Por qué: riesgo medido en el banco de «Asignar cuenta» (01–02/10): en otro modo de transacción, «Retirar
-- cuenta» podía retirar una cuenta recién asignada que, en READ COMMITTED, se niega a retirar; y «Cambiar
-- cuenta de pago» podía dar por vigente a un administrador ya revocado. Solo alcanzable con SQL lanzado a
-- mano: PostgREST siempre va en READ COMMITTED, así que ninguna pantalla ni edge cambia. Decisión de
-- Miguel, 02/10/2026 (~11:05): «Sí, después de entregar F6».
--
-- Qué NO toca: las puertas crm.retirar_cuenta_cliente y crm.cambiar_cuenta_pago_contratos, grants, ACL,
-- search_path, triggers, tablas, ni nada de public. No crea objetos. Es idempotente en el sentido de que
-- se niega a aplicarse dos veces (los cuerpos vivos ya no serían los esperados).
--
-- Seguros: se niega si los cuerpos vivos no son exactamente los de hoy (huellas de abajo); tras aplicar,
-- exige las huellas nuevas, SECURITY DEFINER, search_path vacío y la ACL de siempre (solo authenticated).
-- Reversa: supabase/scripts/cuentas-pago-negativa/reversa.sql (repone los cuerpos anteriores exactos).
-- Registro: supabase/scripts/cuentas-pago-negativa/registrar.sql (db query no registra).
-- Huellas (md5 de prosrc): retirar vivo 3ab8983f87f343e896acaefafbbcf4d4 → 748918fb544b22cd96c4daf884761b52;
--                          cambiar vivo 61bec6b3d7d7589e67b4740bd9e7d630 → 1d6443c826ecd6b64db32c9dc247f7f8.

-- ── 1. Preflight: los cuerpos vivos son los de hoy ─────────────────────────────────────────────
do $preflight$
begin
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'SOLO_READ_COMMITTED: esta migración se aplica en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)')) is distinct from '3ab8983f87f343e896acaefafbbcf4d4' then
    raise exception 'SOLO_READ_COMMITTED: private.retirar_cuenta_cliente_autorizado no tiene el cuerpo esperado (vivo hoy); no se toca nada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) is distinct from '61bec6b3d7d7589e67b4740bd9e7d630' then
    raise exception 'SOLO_READ_COMMITTED: private.cambiar_cuenta_pago_contratos_autorizado no tiene el cuerpo esperado (vivo hoy); no se toca nada';
  end if;
end $preflight$;

-- ── 2. Los dos núcleos, con la negativa como primera comprobación ──────────────────────────────
-- [cuerpo de private.retirar_cuenta_cliente_autorizado: IDÉNTICO al vivo salvo el bloque añadido; ver DIFF más abajo]


-- [cuerpo de private.cambiar_cuenta_pago_contratos_autorizado: IDÉNTICO al vivo salvo el bloque añadido; ver DIFF más abajo]


-- ── 3. Comentarios: se conserva el texto que tenían y se añade una frase ──────────────────────
do $comentarios$
declare
  v_f record;
begin
  for v_f in select * from (values
      ('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)'),
      ('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) as f(firma)
  loop
    execute pg_catalog.format('comment on function %s is %L', v_f.firma,
      pg_catalog.rtrim(coalesce(pg_catalog.obj_description(pg_catalog.to_regprocedure(v_f.firma), 'pg_proc'), ''))
      || ' Solo admite READ COMMITTED (0A000 en cualquier otro modo; 20261002163158).');
  end loop;
end $comentarios$;

-- ── 4. Postflight: huellas nuevas y nada más cambió ────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)')) is distinct from '748918fb544b22cd96c4daf884761b52' then
    raise exception 'SOLO_READ_COMMITTED: private.retirar_cuenta_cliente_autorizado no tiene el cuerpo esperado (tras aplicar); no se toca nada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) is distinct from '1d6443c826ecd6b64db32c9dc247f7f8' then
    raise exception 'SOLO_READ_COMMITTED: private.cambiar_cuenta_pago_contratos_autorizado no tiene el cuerpo esperado (tras aplicar); no se toca nada';
  end if;
  for v_f in select * from (values
      ('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)'),
      ('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) as f(firma)
  loop
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = pg_catalog.to_regprocedure(v_f.firma)
                     and p.prosecdef and p.provolatile = 'v' and p.proconfig @> array['search_path=""']) then
      raise exception 'SOLO_READ_COMMITTED: % perdió DEFINER, VOLATILE o el search_path vacío', v_f.firma;
    end if;
    if exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
               where p.oid = pg_catalog.to_regprocedure(v_f.firma) and a.privilege_type = 'EXECUTE'
                 and a.grantee <> p.proowner and a.grantee <> 'authenticated'::regrole::oid)
       or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_f.firma))
       or not pg_catalog.has_function_privilege('authenticated', v_f.firma, 'EXECUTE') then
      raise exception 'SOLO_READ_COMMITTED: ACL inesperada en %', v_f.firma;
    end if;
  end loop;
end $postflight$;

select 'RETIRAR_CAMBIAR_SOLO_READ_COMMITTED_OK' as resultado;

```

## DIFF del cuerpo de retirar (vivo → nuevo)
```diff
--- private.retirar_cuenta_cliente_autorizado (vivo, md5 3ab8983f87f343e896acaefafbbcf4d4)
+++ private.retirar_cuenta_cliente_autorizado (nuevo, md5 748918fb544b22cd96c4daf884761b52)
@@ -8,8 +8,16 @@
   v_obj storage.objects%rowtype;
   v_abiertos text[];
   v_quien text;
 begin
+  -- Solo READ COMMITTED: la misma negativa que lleva «Asignar cuenta» (20261002005004). Con una
+  -- fotografía fija (REPEATABLE READ o SERIALIZABLE) se podría ver vigente a un administrador ya
+  -- revocado, o no ver un vínculo que otro intento acaba de crear. Se comprueba antes de mirar nada.
+  -- Por la API (PostgREST) la transacción siempre va en READ COMMITTED: ninguna pantalla cambia.
+  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
+    raise exception using errcode = '0A000',
+      message = 'El retiro de cuenta no admite este modo de transacción';
+  end if;
   if not coalesce(private.admin_banca_vigente(v_actor), false) then
     raise exception using errcode = '42501', message = 'Solo administración puede retirar cuentas bancarias';
   end if;
   if p_solicitud_id is null or p_cliente_id is null or p_cuenta_id is null then

```

## DIFF del cuerpo de cambiar (vivo → nuevo)
```diff
--- private.cambiar_cuenta_pago_contratos_autorizado (vivo, md5 61bec6b3d7d7589e67b4740bd9e7d630)
+++ private.cambiar_cuenta_pago_contratos_autorizado (nuevo, md5 1d6443c826ecd6b64db32c9dc247f7f8)
@@ -13,8 +13,16 @@
   v_hechos integer;
   v_etag text;
   v_en_curso text;
 begin
+  -- Solo READ COMMITTED: la misma negativa que lleva «Asignar cuenta» (20261002005004). Con una
+  -- fotografía fija (REPEATABLE READ o SERIALIZABLE) se podría ver vigente a un administrador ya
+  -- revocado, o no ver un vínculo que otro intento acaba de crear. Se comprueba antes de mirar nada.
+  -- Por la API (PostgREST) la transacción siempre va en READ COMMITTED: ninguna pantalla cambia.
+  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
+    raise exception using errcode = '0A000',
+      message = 'El cambio de cuenta de pago no admite este modo de transacción';
+  end if;
   if not coalesce(private.admin_banca_vigente(v_actor), false) then
     raise exception using errcode = '42501',
       message = 'Solo administración puede cambiar la cuenta de pago';
   end if;

```

## reversa.sql (generado; cuerpos anteriores sustituidos por nota)
```sql
-- REVERSA de 20261002163158_crm_retirar_y_cambiar_cuenta_solo_read_committed.sql. GENERADA por generar-derivados.py (no se edita a mano).
-- Repone en los dos núcleos los cuerpos EXACTOS que tenían antes (huellas 3ab8983f87f343e896acaefafbbcf4d4 y
-- 61bec6b3d7d7589e67b4740bd9e7d630), deja el comentario sin la frase añadida y borra la fila del registro. Se niega si los
-- cuerpos vivos no son los de la migración (alguien tocó algo después) o si no va en READ COMMITTED.
-- No toca vínculos, retiros, cambios, grants ni nada más. Solo Miguel, con autorización expresa.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
do $pre$
begin
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA SOLO_READ_COMMITTED: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)')) is distinct from '748918fb544b22cd96c4daf884761b52' then
    raise exception 'REVERSA SOLO_READ_COMMITTED: private.retirar_cuenta_cliente_autorizado no tiene el cuerpo esperado (no es el de la migración); no se toca nada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) is distinct from '1d6443c826ecd6b64db32c9dc247f7f8' then
    raise exception 'REVERSA SOLO_READ_COMMITTED: private.cambiar_cuenta_pago_contratos_autorizado no tiene el cuerpo esperado (no es el de la migración); no se toca nada';
  end if;
end $pre$;

-- [create or replace de private.retirar_cuenta_cliente_autorizado con el cuerpo ANTERIOR exacto, md5 3ab8983f87f343e896acaefafbbcf4d4]


-- [create or replace de private.cambiar_cuenta_pago_contratos_autorizado con el cuerpo ANTERIOR exacto, md5 61bec6b3d7d7589e67b4740bd9e7d630]


do $post$
declare
  v_f record;
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)')) is distinct from '3ab8983f87f343e896acaefafbbcf4d4' then
    raise exception 'REVERSA SOLO_READ_COMMITTED: private.retirar_cuenta_cliente_autorizado no tiene el cuerpo esperado (no quedó el anterior); no se toca nada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) is distinct from '61bec6b3d7d7589e67b4740bd9e7d630' then
    raise exception 'REVERSA SOLO_READ_COMMITTED: private.cambiar_cuenta_pago_contratos_autorizado no tiene el cuerpo esperado (no quedó el anterior); no se toca nada';
  end if;
  for v_f in select * from (values ('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)'), ('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) as f(firma) loop
    execute pg_catalog.format('comment on function %s is %L', v_f.firma,
      pg_catalog.rtrim(pg_catalog.replace(coalesce(pg_catalog.obj_description(pg_catalog.to_regprocedure(v_f.firma), 'pg_proc'), ''),
        ' Solo admite READ COMMITTED (0A000 en cualquier otro modo; 20261002163158).', '')));
    if not exists (select 1 from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_f.firma)
                   and p.prosecdef and p.proconfig @> array['search_path=""'])
       or not pg_catalog.has_function_privilege('authenticated', v_f.firma, 'EXECUTE') then
      raise exception 'REVERSA SOLO_READ_COMMITTED: % perdió DEFINER, search_path o el permiso de authenticated', v_f.firma;
    end if;
  end loop;
  if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'delete from supabase_migrations.schema_migrations where version = ' || pg_catalog.quote_literal('20261002163158');
  end if;
end $post$;
select 'REVERTIDA_SOLO_READ_COMMITTED' as resultado;
commit;

```

## test-negativa.sql (banco)
```sql
-- PRUEBA de la negativa de modo de transacción en «Retirar cuenta» y «Cambiar cuenta de pago» — SOLO BANCO.
-- No siembra nada: llama a los dos núcleos y a las dos puertas con identificadores al azar y sin actor.
--   · En REPEATABLE READ y en SERIALIZABLE deben negarse con 0A000 ANTES de mirar nada.
--   · En READ COMMITTED deben pasar la negativa y caer en la comprobación siguiente (42501: sin actor no hay
--     administración vigente): prueba que la negativa va primera y que no rompe el camino normal.
-- Nada queda escrito salvo la tabla temporal de resultados. Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-negativa.sql
\set ON_ERROR_STOP 1
\set QUIET 1
-- Los núcleos fallan antes de escribir (0A000 o 42501), cada llamada va en su propio bloque EXCEPTION
-- (savepoint implícito) y la transacción se CONFIRMA para que queden solo los resultados.
create temporary table _veredicto (n int generated always as identity, caso text, esperado text, obtenido text, ok boolean);

\echo [negativa] REPEATABLE READ
begin isolation level repeatable read;
do $t$
declare v_caso text; v_sql text; v_est text;
begin
  for v_caso, v_sql in values
    ('nucleo retirar · RR', 'select private.retirar_cuenta_cliente_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), ''motivo de prueba'', null)'),
    ('nucleo cambiar · RR', 'select private.cambiar_cuenta_pago_contratos_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], ''motivo de prueba'', ''ruta/x.pdf'')'),
    ('puerta retirar · RR', 'select crm.retirar_cuenta_cliente(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), ''motivo de prueba'', null)'),
    ('puerta cambiar · RR', 'select crm.cambiar_cuenta_pago_contratos(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], ''motivo de prueba'', ''ruta/x.pdf'')')
  loop
    begin
      execute v_sql; v_est := 'SIN ERROR';
    exception when others then v_est := sqlstate;
    end;
    insert into _veredicto(caso, esperado, obtenido, ok) values (v_caso, '0A000', v_est, v_est = '0A000');
  end loop;
end $t$;
commit;

\echo [negativa] SERIALIZABLE
begin isolation level serializable;
do $t$
declare v_est text;
begin
  begin
    perform private.retirar_cuenta_cliente_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo de prueba', null); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo retirar · SERIALIZABLE', '0A000', v_est, v_est = '0A000');
  begin
    perform private.cambiar_cuenta_pago_contratos_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo de prueba', 'ruta/x.pdf'); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo cambiar · SERIALIZABLE', '0A000', v_est, v_est = '0A000');
end $t$;
commit;

\echo [negativa] READ COMMITTED: la negativa deja pasar y cae en la comprobación de administración (42501)
begin;
do $t$
declare v_est text;
begin
  begin
    perform private.retirar_cuenta_cliente_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo de prueba', null); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo retirar · READ COMMITTED sin actor', '42501', v_est, v_est = '42501');
  begin
    perform private.cambiar_cuenta_pago_contratos_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo de prueba', 'ruta/x.pdf'); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo cambiar · READ COMMITTED sin actor', '42501', v_est, v_est = '42501');
end $t$;
commit;

\set QUIET 0
select caso, esperado, obtenido, case when ok then '✓' else '✗' end as res from _veredicto order by n;
select (count(*) filter (where not ok)) > 0 as hay_fallos, count(*) filter (where not ok) as fallos, count(*) as casos from _veredicto \gset
\if :hay_fallos
  \echo [negativa] FALLOS: :fallos de :casos
  do $f$ begin raise exception 'NEGATIVA: hay casos sin la respuesta esperada'; end $f$;
\else
  \echo [negativa] PASS: :casos casos
\endif
drop table _veredicto;

```

## Resultados del banco
── Resumen del ciclo en banco Docker propio (esquema de producción sin datos) ──
✓ 0.0–0.4 banco listo (storage.objects mínimo, auth.uid() como prod, catálogo d0…02 solo banco); huellas vivas = producción
✓ 1.1 sin la migración la prueba FALLA (6 casos sin 0A000): detecta el mundo sin guarda
✓ 2.1 migración aplicada: fila RETIRAR_CAMBIAR_SOLO_READ_COMMITTED_OK · ✓ 2.2 huellas nuevas · ✓ 2.3 ACL/DEFINER/search_path intactos · ✓ 2.4 comentarios · ✓ 2.5 segunda aplicación se niega y nada cambia
✓ 3.1 prueba de la negativa PASS 8/8 · ✓ 3.2 cuentas-gloria/test-retirar-cuenta-cliente PASS (RETIRO_CUENTA_OK)
✗ 3.2 cuentas-gloria/test-cambio-cuenta-pago: falla en su dry_run (línea 551, «Solo el servicio de avisos reclama avisos») — IGUAL sin la migración (comprobado revirtiéndola): banco sin datos, no este cambio
✓ 4.1 registrar · ✓ 4.2 idempotente · ✓ 5.1 reversa en RR se niega · ✓ 5.2 REVERTIDA · ✓ 5.3 huellas de antes · ✓ 5.4 registro borrado · ✓ 5.5 comentarios de antes · ✓ 5.6 tras la reversa la prueba FALLA (mutante) · ✓ 5.7 reaplicada y registrada · ✓ 5.8 PASS final

## Preguntas concretas
1. ¿La negativa va antes de cualquier lectura/escritura y cubre las dos puertas? ¿Algún camino legítimo (edge, job, PostgREST, Supabase Studio) corre fuera de READ COMMITTED y se rompería?
2. ¿El pre/postflight (huellas, ACL, DEFINER, VOLATILE, search_path) es suficiente para garantizar «solo cambió el bloque añadido»? ¿Falta algo (p. ej. proowner, proleakproof, comentarios)?
3. ¿La reversa repone exactamente lo anterior y se niega en los casos correctos? ¿El `replace` del comentario puede dejar restos?
4. ¿La prueba es suficiente como mutante (sin la guarda falla)? ¿Qué test gap ves (p. ej. probar con actor admin real en RR que no llegue a escribir)?
5. ¿El ✗ de test-cambio-cuenta-pago en dry_run («Solo el servicio de avisos reclama avisos»), idéntico sin la migración, puede ocultar algo de este cambio?
