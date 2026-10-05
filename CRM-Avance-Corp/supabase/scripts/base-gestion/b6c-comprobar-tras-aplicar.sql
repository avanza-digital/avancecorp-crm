-- B6c · comprobación de COMPORTAMIENTO tras aplicar 20261004123611 (la nota del veto reservada a sus puertas e inmutable).
-- Se corre DESPUÉS del commit de la migración (Codex r1, P2: la migración no hace DML con el candado del CREATE TRIGGER
-- puesto): en el banco, en la rama con datos y, si Miguel quiere, en producción con `!` (`supabase db query --linked --file`).
-- NO ESCRIBE NADA: una sola transacción que termina SIEMPRE en ROLLBACK, y cada caso además en su subtransacción deshecha.
-- Candados: lock_timeout corto; el lead se toma con FOR UPDATE SKIP LOCKED ANTES de insertar (nunca espera a una sesión de
-- usuario: si el más antiguo está ocupado toma otro; si no hay ninguno libre, omite con «NOT RUN»). La nota del veto para
-- probar UPDATE/DELETE se toma igual (SKIP LOCKED). Un candado ocupado a mitad de un caso cuenta como NOT RUN, no como PASS.
-- Casos (como `role authenticated` + claims de una Gerencia activa, que la policy deja escribir en cualquier lead activo):
--   la API NO escribe la nota del veto (marcar, levantar, sin acción, 'No_Contactar', ' no_contactar ') → 42501 del sello;
--   SÍ entran —con ROW_COUNT = 1: insertada de verdad, no descartada en silencio (Codex r2, P3)— una nota normal, la nota
--   bajo la válvula crm.op_privilegiada y la nota sin usuario; y, como service_role con usuario (la API no tiene UPDATE ni
--   DELETE), cambiar o borrar una nota del veto existente → 42501.
-- El VEREDICTO viaja como FILA (db query no trae los avisos): la última consulta devuelve una sola línea
--   B6C_COMPORTAMIENTO_OK n/n · B6C_COMPORTAMIENTO_PARCIAL (con los NOT RUN) · B6C_COMPORTAMIENTO_FALLA (y además aborta).
begin;
set local lock_timeout = '2s';
set local statement_timeout = '30s';
set local search_path = '';
create temp table _b6c_r (n serial, caso text, esperado text, obtenido text, estado text);

do $comprobar$
declare
  c_msg constant text := '42501 La nota de No contactar solo la escriben sus puertas (marcar, levantar o postventa); no se cambia ni se borra';
  v_ger uuid;
  v_lead uuid;
  v_nota uuid;
  v_r text;
  v_filas bigint;
  v_caso record;
begin
  if to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()') is null
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass
                     and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta' and t.tgenabled = 'O') then
    insert into pg_temp._b6c_r (caso, esperado, obtenido, estado) values ('precondición', 'B6c aplicada', 'B6c NO está aplicada (o el sello está deshabilitado)', 'NOT RUN');
    return;
  end if;
  select e.perfil_id into v_ger from crm.equipo e where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if v_ger is null then
    insert into pg_temp._b6c_r (caso, esperado, obtenido, estado) values ('precondición', 'una Gerencia activa', 'sin Gerencia activa en esta base', 'NOT RUN');
    return;
  end if;
  -- El lead, bloqueado YA (sin esperar a nadie): los inserts de abajo no vuelven a esperar por él.
  select l.id into v_lead from crm.leads l where l.activo order by l.creado_en, l.id limit 1 for update skip locked;
  if v_lead is null then
    insert into pg_temp._b6c_r (caso, esperado, obtenido, estado) values ('precondición', 'un lead activo libre', 'ningún lead activo libre (todos bloqueados por otras sesiones)', 'NOT RUN');
    return;
  end if;

  -- 1. La API (role authenticated + claims de Gerencia) no escribe la nota del veto.
  for v_caso in select * from (values
      ('N1 la API escribe un «marcar»', '{"evento":"no_contactar","accion":"marcar","motivo":"comprobacion B6c"}'),
      ('N2 la API escribe un «levantar»', '{"evento":"no_contactar","accion":"levantar","motivo":"comprobacion B6c"}'),
      ('N3 la API escribe el evento sin acción', '{"evento":"no_contactar"}'),
      ('N4 la API escribe la variante No_Contactar', '{"evento":"No_Contactar","accion":"marcar"}'),
      ('N5 la API escribe la variante con espacios', '{"evento":" no_contactar ","accion":"marcar"}')) x(caso, meta) loop
    v_r := null;
    begin
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
      perform pg_catalog.set_config('role', 'authenticated', true);
      insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values (v_lead, 'nota', 'comprobacion B6c', v_caso.meta::jsonb, v_ger);
      v_r := 'paso';
      raise exception using errcode = 'P0001', message = 'B6C_DESHACER';
    exception when others then
      if v_r is null then v_r := sqlstate || ' ' || sqlerrm; end if;
    end;
    insert into pg_temp._b6c_r (caso, esperado, obtenido, estado)
    values (v_caso.caso, c_msg, v_r, case when v_r = c_msg then 'PASS' when v_r like '55P03 %' then 'NOT RUN' else 'FAIL' end);
  end loop;

  -- 2. Controles: entran una nota normal por la API, la nota bajo la válvula de las puertas y la nota sin usuario.
  for v_caso in select * from (values (1, 'P1 la API escribe una nota normal'), (2, 'P2 la nota del veto bajo la válvula crm.op_privilegiada'),
                                      (3, 'P3 la nota del veto sin usuario (migraciones, backfills)')) x(k, caso) loop
    v_r := null;
    begin
      if v_caso.k < 3 then
        perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
        perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
        perform pg_catalog.set_config('role', 'authenticated', true);
      else
        perform pg_catalog.set_config('request.jwt.claims', '', true);
        perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
      end if;
      if v_caso.k = 2 then
        perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      end if;
      insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
      values (v_lead, 'nota', 'comprobacion B6c',
              case when v_caso.k = 1 then '{}'::jsonb else '{"evento":"no_contactar","accion":"marcar","motivo":"comprobacion B6c"}'::jsonb end, v_ger);
      -- Codex r2 (P3): «paso» solo si la fila ENTRÓ (un trigger que la descarte en silencio con return null deja 0 filas).
      get diagnostics v_filas = row_count;
      v_r := case when v_filas = 1 then 'paso' else format('sin error pero %s filas insertadas (descartada en silencio)', v_filas) end;
      raise exception using errcode = 'P0001', message = 'B6C_DESHACER';
    exception when others then
      if v_r is null then v_r := sqlstate || ' ' || sqlerrm; end if;
    end;
    insert into pg_temp._b6c_r (caso, esperado, obtenido, estado)
    values (v_caso.caso, 'paso', v_r, case when v_r = 'paso' then 'PASS' when v_r like '55P03 %' then 'NOT RUN' else 'FAIL' end);
  end loop;

  -- 3. Inmutable: como service_role CON usuario (la API no tiene UPDATE ni DELETE), cambiar o borrar una nota del veto.
  select a.id into v_nota from crm.actividades a
   where pg_catalog.lower(pg_catalog.btrim(coalesce(a.metadata->>'evento', ''))) = 'no_contactar'
   order by a.creado_en, a.id limit 1 for update skip locked;
  if v_nota is null then
    insert into pg_temp._b6c_r (caso, esperado, obtenido, estado) values ('U1/U2 cambiar o borrar una nota del veto', c_msg, 'no hay ninguna nota del veto libre en esta base', 'NOT RUN');
  else
    for v_caso in select * from (values (1, 'U1 service_role con usuario cambia el detalle de una nota del veto'),
                                        (2, 'U2 service_role con usuario borra una nota del veto')) x(k, caso) loop
      v_r := null;
      begin
        perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'service_role')::text, true);
        perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
        perform pg_catalog.set_config('role', 'service_role', true);
        if v_caso.k = 1 then
          update crm.actividades set detalle = 'comprobacion B6c' where id = v_nota;
        else
          delete from crm.actividades where id = v_nota;
        end if;
        v_r := 'paso';
        raise exception using errcode = 'P0001', message = 'B6C_DESHACER';
      exception when others then
        if v_r is null then v_r := sqlstate || ' ' || sqlerrm; end if;
      end;
      insert into pg_temp._b6c_r (caso, esperado, obtenido, estado)
      values (v_caso.caso, c_msg, v_r,
              case when v_r = c_msg then 'PASS'
                   when v_r like '55P03 %' or v_r like '42501 permission denied to set role%' then 'NOT RUN' else 'FAIL' end);
    end loop;
  end if;
  perform pg_catalog.set_config('role', 'none', true);
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
end;
$comprobar$;

-- Detalle (para psql) y, al final, el veredicto en UNA fila.
select format('%s %s · esperado %s · obtenido %s', r.estado, r.caso, r.esperado, left(r.obtenido, 200)) from pg_temp._b6c_r r order by r.n;
select case
         when count(*) filter (where r.estado = 'FAIL') > 0 then
           'B6C_COMPORTAMIENTO_FALLA: ' || string_agg(r.caso || ' → ' || left(r.obtenido, 120), ' | ' order by r.n) filter (where r.estado = 'FAIL')
         when count(*) filter (where r.estado = 'NOT RUN') > 0 then
           format('B6C_COMPORTAMIENTO_PARCIAL: %s PASS · NOT RUN: %s', count(*) filter (where r.estado = 'PASS'),
                  string_agg(r.caso || ' (' || left(r.obtenido, 100) || ')', ' | ' order by r.n) filter (where r.estado = 'NOT RUN'))
         else format('B6C_COMPORTAMIENTO_OK %s/%s', count(*), count(*))
       end as veredicto
  from pg_temp._b6c_r r;
do $falla$
begin
  if exists (select 1 from pg_temp._b6c_r where estado = 'FAIL') then
    raise exception 'B6c: la comprobacion de comportamiento FALLA (ver el veredicto)';
  end if;
end;
$falla$;
rollback;
