-- B7 · comprobación de COMPORTAMIENTO tras aplicar 20261004160034 (Bases cargadas, esquema). La migración solo acredita el
-- catálogo (sin DML con los candados de crm.leads puestos); esto se corre DESPUÉS del commit: en el banco, en la rama con datos
-- y, si Miguel quiere, en producción con `!` (`supabase db query --linked --file`).
-- NO ESCRIBE NADA: una sola transacción que termina SIEMPRE en ROLLBACK, y cada caso además en su subtransacción deshecha.
-- No toca leads existentes: solo crea filas NUEVAS transitorias (un lead con un teléfono que no existe, una base y un recibo)
-- y las deshace. lock_timeout corto: un candado ocupado cuenta como NOT RUN, no como PASS.
-- Casos:
--   T1–T3 la API (role authenticated con una Gerencia activa) no lee las bases ni escribe recibos; service_role no lee filas;
--   K1 un lead de origen oficina sin capital → 23514; K2 un lead base_cargada sin la válvula → 42501;
--   K3 con las válvulas (crm.op_bases_carga + crm.op_privilegiada) un contacto sin capital NACE descartado con motivo
--      base_cargada (y sin descartado_en: pendiente de B8); K4 sin capital no puede nacer 'nuevo', ni con la válvula → 23514;
--   K5 sacarlo del descarte sin capital → 23514 (CHECK), con la válvula de las puertas de reapertura encendida para que el
--      ÚNICO freno posible sea el CHECK, con la bandera resolver_en_puertas encendida (producción) o apagada; un P0409 del
--      candado de reapertura es FAIL, nunca PASS (r3: hallazgo de la rama con datos); K5b control: con el capital puesto la
--      misma reapertura pasa; K6 vaciar un capital → 23514 (sello);
--   R1/R2 un recibo no se cambia ni se borra → P0409.
-- El VEREDICTO viaja como FILA (db query no trae los avisos): B7_COMPORTAMIENTO_OK n/n · B7_COMPORTAMIENTO_PARCIAL (con los
--   NOT RUN) · B7_COMPORTAMIENTO_FALLA (y además aborta).
begin;
set local lock_timeout = '2s';
set local statement_timeout = '30s';
set local search_path = '';
create temp table _b7_r (n serial, caso text, esperado text, obtenido text, estado text);

do $comprobar$
declare
  v_ger uuid;
  v_sup uuid;
  v_tel text;
  v_lead uuid := pg_catalog.gen_random_uuid();
  v_base uuid := pg_catalog.gen_random_uuid();
  v_r text;
  v_caso record;
  v_i integer;
begin
  if to_regclass('crm.bases_carga') is null or to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is null
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass
                     and t.tgname = 'trg_leads_000_base_cargada_solo_puerta' and t.tgenabled = 'O') then
    insert into pg_temp._b7_r (caso, esperado, obtenido, estado) values ('precondición', 'B7 aplicada', 'B7 NO está aplicada (o el sello está deshabilitado)', 'NOT RUN');
    return;
  end if;
  select e.perfil_id into v_ger from crm.equipo e where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  select e.perfil_id into v_sup from crm.equipo e where private.rol_crm(e.perfil_id) = 'supervisor' order by e.perfil_id limit 1;
  -- Un teléfono que NO tenga ningún lead (9 dígitos al azar; hasta 20 intentos).
  for v_i in 1..20 loop
    v_tel := '9' || pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 100000000))::bigint::text, 8, '0');
    exit when not exists (select 1 from crm.leads l where l.telefono = private.normalizar_telefono(v_tel));
    v_tel := null;
  end loop;
  if v_ger is null or v_sup is null or v_tel is null then
    insert into pg_temp._b7_r (caso, esperado, obtenido, estado)
    values ('precondición', 'una Gerencia y un supervisor activos y un teléfono libre', format('gerencia %s · supervisor %s · teléfono %s', v_ger, v_sup, v_tel), 'NOT RUN');
    return;
  end if;

  -- T · La API no lee ni escribe las tablas nuevas.
  for v_caso in select * from (values
      (1, 'T1 Gerencia (authenticated) lee crm.bases_carga', 'authenticated', 'select count(*) from crm.bases_carga', '42501 permission denied for table bases_carga'),
      (2, 'T2 Gerencia (authenticated) escribe un recibo', 'authenticated', 'insert into crm.base_carga_operaciones default values', '42501 permission denied for table base_carga_operaciones'),
      (3, 'T3 service_role lee crm.base_carga_leads', 'service_role', 'select count(*) from crm.base_carga_leads', '42501 permission denied for table base_carga_leads')) x(k, caso, rol, sql, esperado) loop
    v_r := null;
    begin
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', v_caso.rol)::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
      perform pg_catalog.set_config('role', v_caso.rol, true);
      execute v_caso.sql;
      v_r := 'paso';
      raise exception using errcode = 'P0001', message = 'B7_DESHACER';
    exception when others then
      if v_r is null then v_r := sqlstate || ' ' || sqlerrm; end if;
    end;
    insert into pg_temp._b7_r (caso, esperado, obtenido, estado)
    values (v_caso.caso, v_caso.esperado, v_r, case when v_r = v_caso.esperado then 'PASS' when v_r like '55P03 %' or v_r like '42501 permission denied to set role%' then 'NOT RUN' else 'FAIL' end);
  end loop;
  perform pg_catalog.set_config('role', 'none', true);
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);

  -- K · Capital, origen y motivo (sin usuario: como una migración o el importador).
  for v_caso in select * from (values
      (1, 'K1 lead de origen oficina sin capital', '23514 new row for relation "leads" violates check constraint "leads_monto_estimado_valido"'),
      (2, 'K2 lead base_cargada sin la válvula', '42501 El origen base_cargada solo lo pone la carga de bases'),
      (3, 'K3 un contacto sin capital nace descartado con base_cargada (sin descartado_en: pendiente de B8)', 'descartado|base_cargada|true|false'),
      (4, 'K4 sin capital no puede nacer nuevo, ni con la válvula', '23514 new row for relation "leads" violates check constraint "leads_monto_estimado_valido"'),
      (5, 'K5 sacarlo del descarte sin capital (solo puede frenarlo el CHECK)', '23514 new row for relation "leads" violates check constraint "leads_monto_estimado_valido"'),
      (7, 'K5b control: la misma reapertura con el capital puesto pasa', 'paso'),
      (6, 'K6 vaciar el capital de un lead de base', '23514 El capital del lead no se puede vaciar')) x(k, caso, esperado) loop
    v_r := null;
    begin
      if v_caso.k >= 2 then
        -- K2 sin válvulas; K4 solo con la de bases y naciendo 'nuevo'; K3/K5/K5b/K6 con las dos, naciendo descartado.
        if v_caso.k >= 3 then perform pg_catalog.set_config('crm.op_bases_carga', 'on', true); end if;
        if v_caso.k in (3, 5, 6, 7) then perform pg_catalog.set_config('crm.op_privilegiada', 'on', true); end if;
        insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte, asignado_supervisor_id, vendedor_id, monto_estimado, moneda, creado_por, activo)
        values (v_lead, 'COMPROBACION B7', v_tel, 'base_cargada',
                case when v_caso.k in (2, 4) then 'nuevo' else 'descartado' end,
                case when v_caso.k in (2, 4) then null else 'base_cargada' end, v_sup, null,
                case when v_caso.k = 6 then 1000 end, 'PEN', v_sup, true);
        perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
        perform pg_catalog.set_config('crm.op_bases_carga', 'off', true);
      end if;
      if v_caso.k = 1 then
        insert into crm.leads (id, nombre_completo, telefono, origen, etapa, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo)
        values (v_lead, 'COMPROBACION B7', v_tel, 'oficina', 'nuevo', v_sup, null, 'PEN', v_sup, true);
        v_r := 'paso';
      elsif v_caso.k = 2 then
        v_r := 'paso';
      elsif v_caso.k = 3 then
        select format('%s|%s|%s|%s', l.etapa, l.motivo_descarte, (l.monto_estimado is null)::text, (l.descartado_en is not null)::text)
          into v_r from crm.leads l where l.id = v_lead;
      elsif v_caso.k = 4 then
        v_r := 'paso';
      elsif v_caso.k in (5, 7) then
        -- r3 (rama con datos, 04/10): con resolver_en_puertas ENCENDIDA (producción) trg_leads_zz_reapertura_solo_rpc frena el
        -- UPDATE directo con P0409 ANTES del CHECK. Las puertas de reapertura (reabrir_lead_fn, tomar_lead_libre,
        -- rescatar_descartes) encienden crm.reapertura_identidad; se enciende igual aquí (sin crm.op_privilegiada), así lo único
        -- que puede frenar K5 es el CHECK, con la bandera encendida o apagada. K5b pone el capital en el mismo UPDATE.
        perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
        if v_caso.k = 5 then
          update crm.leads set etapa = 'nuevo', motivo_descarte = null where id = v_lead;
        else
          update crm.leads set etapa = 'nuevo', motivo_descarte = null, monto_estimado = 2000 where id = v_lead;
        end if;
        v_r := 'paso';
      else
        update crm.leads set monto_estimado = null where id = v_lead;
        v_r := 'paso';
      end if;
      raise exception using errcode = 'P0001', message = 'B7_DESHACER';
    exception when others then
      if v_r is null then v_r := sqlstate || ' ' || sqlerrm; end if;
    end;
    -- Solo la coincidencia EXACTA es PASS: un P0409 del candado de reapertura (u otro rechazo) en K5 es FAIL.
    insert into pg_temp._b7_r (caso, esperado, obtenido, estado)
    values (v_caso.caso, v_caso.esperado, v_r, case when v_r = v_caso.esperado then 'PASS' when v_r like '55P03 %' then 'NOT RUN' else 'FAIL' end);
  end loop;

  -- R · Los recibos no se cambian ni se borran (como el dueño de la tabla).
  for v_caso in select * from (values (1, 'R1 cambiar un recibo'), (2, 'R2 borrar un recibo')) x(k, caso) loop
    v_r := null;
    begin
      insert into crm.bases_carga (id, nombre, origen, supervisor_id, creada_por, operacion_id)
      values (v_base, 'COMPROBACION B7 ' || v_base::text, 'crm', v_sup, v_sup, pg_catalog.gen_random_uuid());
      insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
      values (v_sup, pg_catalog.gen_random_uuid(), v_base, 'crear', pg_catalog.md5('comprobacion'), '{"ok": true}');
      if v_caso.k = 1 then
        update crm.base_carga_operaciones set tipo = 'recoger' where base_id = v_base;
      else
        delete from crm.base_carga_operaciones where base_id = v_base;
      end if;
      v_r := 'paso';
      raise exception using errcode = 'P0001', message = 'B7_DESHACER';
    exception when others then
      if v_r is null then v_r := sqlstate || ' ' || sqlerrm; end if;
    end;
    insert into pg_temp._b7_r (caso, esperado, obtenido, estado)
    values (v_caso.caso, 'P0409 Los recibos de las bases cargadas no se modifican ni se borran', v_r,
            case when v_r = 'P0409 Los recibos de las bases cargadas no se modifican ni se borran' then 'PASS' when v_r like '55P03 %' then 'NOT RUN' else 'FAIL' end);
  end loop;
end;
$comprobar$;

-- Detalle (para psql) y, al final, el veredicto en UNA fila.
select format('%s %s · esperado %s · obtenido %s', r.estado, r.caso, r.esperado, left(r.obtenido, 200)) from pg_temp._b7_r r order by r.n;
select case
         when count(*) filter (where r.estado = 'FAIL') > 0 then
           'B7_COMPORTAMIENTO_FALLA: ' || string_agg(r.caso || ' → ' || left(r.obtenido, 120), ' | ' order by r.n) filter (where r.estado = 'FAIL')
         when count(*) filter (where r.estado = 'NOT RUN') > 0 then
           format('B7_COMPORTAMIENTO_PARCIAL: %s PASS · NOT RUN: %s', count(*) filter (where r.estado = 'PASS'),
                  string_agg(r.caso || ' (' || left(r.obtenido, 100) || ')', ' | ' order by r.n) filter (where r.estado = 'NOT RUN'))
         else format('B7_COMPORTAMIENTO_OK %s/%s', count(*), count(*))
       end as veredicto
  from pg_temp._b7_r r;
do $falla$
begin
  if exists (select 1 from pg_temp._b7_r where estado = 'FAIL') then
    raise exception 'B7: la comprobacion de comportamiento FALLA (ver el veredicto)';
  end if;
end;
$falla$;
rollback;
