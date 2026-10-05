-- B8 · comprobación de COMPORTAMIENTO tras aplicar 20261004184501 (Bases cargadas: cargar un archivo y armar bases). La
-- migración solo acredita el catálogo; esto se corre DESPUÉS del commit: en el banco, en la rama con datos y, si Miguel quiere,
-- en producción con `!` (`supabase db query --linked --file`).
-- NO ESCRIBE NADA: una sola transacción que termina SIEMPRE en ROLLBACK, y el recorrido entero además en una subtransacción
-- deshecha (los resultados viajan en variables). Solo crea filas NUEVAS transitorias (una base, un contacto con un teléfono que
-- no existe, sus recibos) y las deshace. No toca leads existentes ni la bandera de identidad. lock_timeout corto: un candado
-- ocupado cuenta como NOT RUN, no como PASS.
-- Casos (con un supervisor y una Gerencia activos de verdad; el núcleo se llama con los claims del supervisor, sin SET ROLE):
--   C1 catálogo: 3 puertas DEFINER con EXECUTE solo authenticated; núcleo sin EXECUTE; disparador de la fecha habilitado; el sello
--      del descarte con la huella que sella assert_gestion_diaria_resultado, y ese assert pasa;
--   P1 crear la base del supervisor; P2 un lote de 2 filas (una libre, una inválida) → cargada · invalida/telefono_invalido;
--   P3 el contacto nace dormido: base_cargada/descartado/base_cargada, sin capital, bandeja del supervisor, sin analista,
--      descartado_en = la carga, descartado_por = el supervisor, sin ciclo SLA, en la base; P4 la válvula queda apagada;
--   P5 el alta de ese teléfono ve «enfriamiento» (no duplicaría); P6 el replay del lote devuelve la MISMA respuesta;
--   P7 armar una base con ese contacto (ya en una base viva) → 22023 sin elegibles, detail en_otra_base;
--   P8 Gerencia sin supervisor → 22023; P9 la puerta crm.cargar_base_lote como authenticated (NOT RUN si el rol de la
--      sesión no puede pasar a authenticated, p. ej. la CLI de producción); P10 (r1) el enfriamiento base_cargada no baja a
--      0 días (CHECK enfriamiento_politica_base_cargada_dias_positivos → 23514); P11 (r2) un lote de 101 filas → 22023 (tope 100).
-- El VEREDICTO viaja como FILA: B8_COMPORTAMIENTO_OK n/n · B8_COMPORTAMIENTO_PARCIAL (con los NOT RUN) ·
--   B8_COMPORTAMIENTO_FALLA (y además aborta). Sin B8 aplicada: todo NOT RUN.
begin;
set local lock_timeout = '2s';
set local statement_timeout = '30s';
set local search_path = '';
create temp table _b8_r (n serial, caso text, esperado text, obtenido text, estado text);

do $comprobar$
declare
  v_ger uuid;
  v_sup uuid;
  v_tel text;
  v_res jsonb := '{}'::jsonb;  -- resultados del recorrido (sobreviven al deshacer la subtransacción)
  v_base jsonb;
  v_lote jsonb;
  v_lote2 jsonb;
  v_lead crm.leads%rowtype;
  v_r text;
  v_i integer;
  v_filas jsonb;
  c record;
begin
  if to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is null or to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)') is null
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_descarte_base_cargada' and t.tgenabled = 'O') then
    insert into pg_temp._b8_r (caso, esperado, obtenido, estado) values ('precondición', 'B8 aplicada', 'B8 NO está aplicada (o su disparador está deshabilitado)', 'NOT RUN');
    return;
  end if;
  select e.perfil_id into v_ger from crm.equipo e where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  select e.perfil_id into v_sup from crm.equipo e where private.rol_crm(e.perfil_id) = 'supervisor' order by e.perfil_id limit 1;
  for v_i in 1..20 loop
    v_tel := '9' || pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 100000000))::bigint::text, 8, '0');
    exit when not exists (select 1 from crm.leads l where l.telefono = private.normalizar_telefono(v_tel))
          and not exists (select 1 from public.perfiles p where private.normalizar_telefono(p.telefono) = private.normalizar_telefono(v_tel));
    v_tel := null;
  end loop;
  if v_ger is null or v_sup is null or v_tel is null then
    insert into pg_temp._b8_r (caso, esperado, obtenido, estado)
    values ('precondición', 'una Gerencia y un supervisor activos y un teléfono libre', format('gerencia %s · supervisor %s · teléfono %s', v_ger, v_sup, v_tel), 'NOT RUN');
    return;
  end if;

  -- C1 · Catálogo (un error del assert sale como FAIL con su mensaje).
  begin
    select ((select count(*) from pg_proc p where p.oid in (to_regprocedure('crm.crear_base(uuid,text,text,uuid,text)'), to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)'),
                                                                   to_regprocedure('crm.armar_base_crm(uuid,text,uuid,uuid[])'))
                    and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
                    and not has_function_privilege('service_role', p.oid, 'EXECUTE')) = 3
               and not exists (select 1 from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                                where p.pronamespace = 'private'::regnamespace and (p.proname like 'bases\_carga\_%' or p.proname = 'trg_leads_sello_descarte_base_cargada')
                                  and has_function_privilege(r.rol, p.oid, 'EXECUTE'))
               and (select md5(pg_get_functiondef(p.oid)) = '150d7ae56bb2094733f7620a1362c29e' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_sello_descarte()'))
               and private.assert_gestion_diaria_resultado() like 'OK%')::text into v_r;
  exception when others then
    v_r := sqlstate || ' ' || sqlerrm;
  end;
  insert into pg_temp._b8_r (caso, esperado, obtenido, estado)
  values ('C1 catálogo: puertas, núcleo, disparador, sello del descarte y su assert', 'true', v_r, case when v_r = 'true' then 'PASS' else 'FAIL' end);

  -- P · El recorrido completo, deshecho al final (los resultados quedan en v_res).
  begin
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    v_base := private.bases_carga_crear_core(v_sup, pg_catalog.gen_random_uuid(), 'COMPROBACION B8 ' || pg_catalog.gen_random_uuid()::text, 'archivo', null, 'comprobacion.csv');
    v_res := v_res || pg_catalog.jsonb_build_object('P1', ((v_base->>'supervisor_id')::uuid = v_sup and v_base->>'origen' = 'archivo')::text);
    v_filas := pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('fila', 1, 'nombre', 'COMPROBACION B8', 'telefono', v_tel),
                                            pg_catalog.jsonb_build_object('fila', 2, 'nombre', 'COMPROBACION B8 MALA', 'telefono', '12345'));
    v_lote := private.bases_carga_cargar_lote_core(v_sup, '00000000-0000-4000-8000-0000000b8001', (v_base->>'base_id')::uuid, v_filas);
    v_res := v_res || pg_catalog.jsonb_build_object('P2', (select string_agg((x->>'fila') || ':' || (x->>'veredicto') || coalesce('/' || (x->>'motivo'), ''), ',' order by (x->>'fila')::int)
                                                            from pg_catalog.jsonb_array_elements(v_lote->'filas') x));
    select l.* into v_lead from crm.leads l where l.telefono = private.normalizar_telefono(v_tel);
    v_res := v_res || pg_catalog.jsonb_build_object('P3', (v_lead.origen = 'base_cargada' and v_lead.etapa = 'descartado' and v_lead.motivo_descarte = 'base_cargada'
        and v_lead.monto_estimado is null and v_lead.asignado_supervisor_id = v_sup and v_lead.vendedor_id is null and v_lead.descartado_en = v_lead.creado_en
        and v_lead.descartado_por = v_sup and not exists (select 1 from crm.lead_sla_ciclos s where s.lead_id = v_lead.id)
        and exists (select 1 from crm.base_carga_leads bl where bl.lead_id = v_lead.id and bl.base_id = (v_base->>'base_id')::uuid and bl.procedencia = 'archivo'))::text);
    v_res := v_res || pg_catalog.jsonb_build_object('P4', coalesce(pg_catalog.current_setting('crm.op_bases_carga', true), 'off'));
    v_res := v_res || pg_catalog.jsonb_build_object('P5', private.verificar_disponibilidad_lead_impl(v_tel, null)->>'estado');
    v_lote2 := private.bases_carga_cargar_lote_core(v_sup, '00000000-0000-4000-8000-0000000b8001', (v_base->>'base_id')::uuid, v_filas);
    v_res := v_res || pg_catalog.jsonb_build_object('P6', (v_lote2 = v_lote)::text);
    begin
      perform private.bases_carga_armar_core(v_sup, pg_catalog.gen_random_uuid(), 'COMPROBACION B8 ARMAR ' || pg_catalog.gen_random_uuid()::text, null, array[v_lead.id]);
      v_r := 'paso';
    exception when others then
      get stacked diagnostics v_r = pg_exception_detail;
      v_r := sqlstate || '|' || coalesce(v_r, '');
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P7', v_r);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    begin
      perform private.bases_carga_crear_core(v_ger, pg_catalog.gen_random_uuid(), 'COMPROBACION B8 G', 'archivo', null, 'g.csv');
      v_r := 'paso';
    exception when others then
      v_r := sqlstate || ' ' || sqlerrm;
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P8', v_r);
    -- P9 · La puerta real como authenticated (el supervisor), si el rol de la sesión puede.
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    begin
      perform pg_catalog.set_config('role', 'authenticated', true);
      v_r := crm.cargar_base_lote('00000000-0000-4000-8000-0000000b8001', (v_base->>'base_id')::uuid, v_filas)::text;
      v_r := ((v_r::jsonb) = v_lote)::text;
      perform pg_catalog.set_config('role', 'none', true);
    exception when others then
      v_r := sqlstate || ' ' || sqlerrm;
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P9', v_r);
    begin
      update crm.enfriamiento_politica set dias = 0 where motivo = 'base_cargada';
      v_r := 'paso';
    exception when others then
      v_r := sqlstate || ' ' || sqlerrm;
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P10', v_r);
    begin
      perform private.bases_carga_cargar_lote_core(v_sup, pg_catalog.gen_random_uuid(), (v_base->>'base_id')::uuid,
        (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('fila', g, 'nombre', 'X', 'telefono', '12345')) from pg_catalog.generate_series(1, 101) g));
      v_r := 'paso';
    exception when others then
      v_r := sqlstate || ' ' || sqlerrm;
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P11', v_r);
    raise exception using errcode = 'P0001', message = 'B8_DESHACER';
  exception when others then
    if sqlerrm <> 'B8_DESHACER' then
      v_res := v_res || pg_catalog.jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
    end if;
  end;
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);

  for c in select * from (values
      (1, 'P1', 'P1 crear la base del supervisor (dueño él, origen archivo)', 'true'),
      (2, 'P2', 'P2 un lote de 2 filas: libre e inválida', '1:cargada,2:invalida/telefono_invalido'),
      (3, 'P3', 'P3 el contacto nace dormido (descartado, sin capital, bandeja, fecha = carga, sin ciclo SLA, en la base)', 'true'),
      (4, 'P4', 'P4 la válvula queda apagada', 'off'),
      (5, 'P5', 'P5 el alta de ese teléfono ve «enfriamiento» (no duplicaría)', 'enfriamiento'),
      (6, 'P6', 'P6 el replay del lote devuelve la MISMA respuesta', 'true'),
      (7, 'P7', 'P7 armar con ese contacto (ya en una base viva) → sin elegibles', '22023|{"excluidos_por_motivo": {"en_otra_base": [1]}}'),
      (8, 'P8', 'P8 Gerencia sin supervisor → 22023', '22023 Gerencia debe elegir el supervisor dueño de la base'),
      (9, 'P9', 'P9 la puerta crm.cargar_base_lote como authenticated (replay idéntico)', 'true'),
      (10, 'P10', 'P10 el enfriamiento base_cargada no baja a 0 días (r1)', '23514 new row for relation "enfriamiento_politica" violates check constraint "enfriamiento_politica_base_cargada_dias_positivos"'),
      (11, 'P11', 'P11 un lote de 101 filas → 22023 (tope 100, r2)', '22023 Un lote trae entre 1 y 100 filas (este trae 101)')) x(k, clave, caso, esperado) loop
    v_r := coalesce(v_res->>c.clave, 'sin resultado: ' || coalesce(v_res->>'error', '(nada)'));
    insert into pg_temp._b8_r (caso, esperado, obtenido, estado)
    values (c.caso, c.esperado, v_r,
            case when v_r = c.esperado then 'PASS'
                 when v_r like '55P03 %' or coalesce(v_res->>'error', '') like '55P03 %' then 'NOT RUN'
                 when c.k = 9 and v_r like '42501 permission denied to set role%' then 'NOT RUN'
                 else 'FAIL' end);
  end loop;
end;
$comprobar$;

-- Detalle (para psql) y, al final, el veredicto en UNA fila.
select format('%s %s · esperado %s · obtenido %s', r.estado, r.caso, r.esperado, left(r.obtenido, 200)) from pg_temp._b8_r r order by r.n;
select case
         when count(*) filter (where r.estado = 'FAIL') > 0 then
           'B8_COMPORTAMIENTO_FALLA: ' || string_agg(r.caso || ' → ' || left(r.obtenido, 120), ' | ' order by r.n) filter (where r.estado = 'FAIL')
         when count(*) filter (where r.estado = 'NOT RUN') > 0 then
           format('B8_COMPORTAMIENTO_PARCIAL: %s PASS · NOT RUN: %s', count(*) filter (where r.estado = 'PASS'),
                  string_agg(r.caso || ' (' || left(r.obtenido, 100) || ')', ' | ' order by r.n) filter (where r.estado = 'NOT RUN'))
         else format('B8_COMPORTAMIENTO_OK %s/%s', count(*), count(*))
       end as veredicto
  from pg_temp._b8_r r;
do $falla$
begin
  if exists (select 1 from pg_temp._b8_r where estado = 'FAIL') then
    raise exception 'B8: la comprobacion de comportamiento FALLA (ver el veredicto)';
  end if;
end;
$falla$;
rollback;
