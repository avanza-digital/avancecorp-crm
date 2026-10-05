-- B9 · comprobación de COMPORTAMIENTO tras aplicar 20261004222602 (Bases cargadas: repartir y recoger). La migración solo
-- acredita el catálogo; esto se corre DESPUÉS del commit: en el banco, en la rama con datos y, si Miguel quiere, en producción
-- con `!` (`supabase db query --linked --file`).
-- NO ESCRIBE NADA: una sola transacción que termina SIEMPRE en ROLLBACK, y el recorrido entero además en una subtransacción
-- deshecha (los resultados viajan en variables). Solo crea filas NUEVAS transitorias (una base, tres contactos con teléfonos que
-- no existen, sus recibos) y las deshace. No toca leads existentes ni la bandera de identidad. lock_timeout corto: un candado
-- ocupado cuenta como NOT RUN, no como PASS.
-- Casos (con un supervisor activo que tenga un analista activo en su subárbol; el núcleo se llama con los claims del actor, sin
-- SET ROLE, salvo P9):
--   C1 catálogo: 3 puertas DEFINER con EXECUTE solo authenticated; núcleo sin EXECUTE; ninguna función de B9 en el censo; la
--      ayudante de B6 con la regla de B9 r1 (cuerpo exacto) y el candado B6 usándola;
--   P1 crear la base del supervisor y cargar 3 contactos; P2 bloque «analista 2» → 2 repartidos;
--   P3 los repartidos SIGUEN dormidos (descartados, sin bandeja, sin tenencia, sin ciclo SLA ni episodio) y su pertenencia dice
--      analista y quién; P4 el replay devuelve la MISMA respuesta; P5 si no alcanzan → 22023 con detail = disponibles (1);
--   P6 la lista de la base (todos): 2 sin_tocar y 1 sin_repartir; P7 recoger al analista → 2 recogidos, de vuelta en la
--      bandeja del supervisor; P8 el analista como actor → 42501; P9 la puerta crm.contactos_de_base como authenticated (NOT RUN
--      si el rol de la sesión no puede pasar a authenticated, p. ej. la CLI de producción).
-- El VEREDICTO viaja como FILA: B9_COMPORTAMIENTO_OK n/n · B9_COMPORTAMIENTO_PARCIAL (con los NOT RUN) ·
--   B9_COMPORTAMIENTO_FALLA (y además aborta). Sin B9 aplicada: todo NOT RUN.
begin;
set local lock_timeout = '2s';
set local statement_timeout = '30s';
set local search_path = '';
create temp table _b9_r (n serial, caso text, esperado text, obtenido text, estado text);

do $comprobar$
declare
  v_sup uuid;
  v_ana uuid;
  v_tels text[] := '{}';
  v_tel text;
  v_res jsonb := '{}'::jsonb;  -- resultados del recorrido (sobreviven al deshacer la subtransacción)
  v_base uuid;
  v_rep jsonb;
  v_rep2 jsonb;
  v_ids uuid[];
  v_r text;
  v_i integer;
  c record;
begin
  if to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is null or to_regprocedure('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)') is null then
    insert into pg_temp._b9_r (caso, esperado, obtenido, estado) values ('precondición', 'B9 aplicada', 'B9 NO está aplicada', 'NOT RUN');
    return;
  end if;
  -- Un supervisor activo con un analista activo en su subárbol (el primero, en orden de id).
  select s.perfil_id, a.perfil_id into v_sup, v_ana
    from crm.equipo s
    join lateral (select x as perfil_id from private.bases_carga_subarbol(s.perfil_id) x
                   where private.es_destino_crm_activo(x, array['vendedor']::text[]) order by x limit 1) a on true
   where private.rol_crm(s.perfil_id) = 'supervisor'
   order by s.perfil_id limit 1;
  for v_i in 1..60 loop
    v_tel := '9' || pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 100000000))::bigint::text, 8, '0');
    if not exists (select 1 from crm.leads l where l.telefono = private.normalizar_telefono(v_tel))
       and not exists (select 1 from public.perfiles p where private.normalizar_telefono(p.telefono) = private.normalizar_telefono(v_tel))
       and not (v_tel = any (v_tels)) then
      v_tels := v_tels || v_tel;
    end if;
    exit when pg_catalog.cardinality(v_tels) = 3;
  end loop;
  if v_sup is null or v_ana is null or pg_catalog.cardinality(v_tels) < 3 then
    insert into pg_temp._b9_r (caso, esperado, obtenido, estado)
    values ('precondición', 'un supervisor activo con un analista activo y tres teléfonos libres', format('supervisor %s · analista %s · teléfonos %s', v_sup, v_ana, pg_catalog.cardinality(v_tels)), 'NOT RUN');
    return;
  end if;

  -- C1 · Catálogo.
  begin
    select ((select count(*) from pg_proc p where p.oid in (to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)'), to_regprocedure('crm.recoger_de_base(uuid,uuid,uuid)'),
                                                                   to_regprocedure('crm.contactos_de_base(uuid,text)'))
                    and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
                    and not has_function_privilege('service_role', p.oid, 'EXECUTE')) = 3
               and not exists (select 1 from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                                where p.pronamespace = 'private'::regnamespace
                                  and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))
                                  and has_function_privilege(r.rol, p.oid, 'EXECUTE'))
               and not exists (select 1 from private.contadores_crudos_leads_citas() x
                                where x.objeto ~ 'bases_carga_reparto_|bases_carga_repartir_core|bases_carga_recoger_core|bases_carga_contactos_core|repartir_base|recoger_de_base|contactos_de_base')
               and (select md5(p.prosrc) = '72621c4311876d39be13e0dfc4278f39' and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
                      from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
               and (select p.prosrc ~ 'base_gestion_en_gestion_hasta' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_seguimiento_activo()')))::text
      into v_r;
  exception when others then
    v_r := sqlstate || ' ' || sqlerrm;
  end;
  insert into pg_temp._b9_r (caso, esperado, obtenido, estado)
  values ('C1 catálogo: puertas, núcleo cerrado, fuera del censo, regla nueva de B6', 'true', v_r, case when v_r = 'true' then 'PASS' else 'FAIL' end);

  -- P · El recorrido completo, deshecho al final (los resultados quedan en v_res).
  begin
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    v_base := (private.bases_carga_crear_core(v_sup, pg_catalog.gen_random_uuid(), 'COMPROBACION B9 ' || pg_catalog.gen_random_uuid()::text, 'archivo', null, 'comprobacion.csv')->>'base_id')::uuid;
    v_r := private.bases_carga_cargar_lote_core(v_sup, pg_catalog.gen_random_uuid(), v_base,
             (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('fila', x.o, 'nombre', 'COMPROBACION B9 ' || x.o, 'telefono', x.t) order by x.o)
                from unnest(v_tels) with ordinality x(t, o)))->'lote'->>'cargadas';
    v_res := v_res || pg_catalog.jsonb_build_object('P1', v_r);
    v_rep := private.bases_carga_repartir_core(v_sup, '00000000-0000-4000-8000-0000000b9001', v_base,
               pg_catalog.jsonb_build_object('modo', 'bloque', 'asignaciones', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('analista_id', v_ana, 'cantidad', 2))));
    v_res := v_res || pg_catalog.jsonb_build_object('P2', (v_rep->>'repartidos') || '|' || ((v_rep->'por_analista'->0->>'analista_id')::uuid = v_ana)::text);
    v_ids := array(select bl.lead_id from crm.base_carga_leads bl where bl.base_id = v_base and bl.analista_id = v_ana);
    v_res := v_res || pg_catalog.jsonb_build_object('P3', (pg_catalog.cardinality(v_ids) = 2
        and not exists (select 1 from crm.leads l where l.id = any (v_ids)
                         and not (l.vendedor_id = v_ana and l.asignado_supervisor_id is null and l.etapa = 'descartado' and l.motivo_descarte = 'base_cargada'
                                  and l.tenencia_desde is null))
        and not exists (select 1 from crm.lead_sla_ciclos s where s.lead_id = any (v_ids))
        and not exists (select 1 from crm.lead_asignaciones a where a.lead_id = any (v_ids))
        and not exists (select 1 from crm.base_carga_leads bl where bl.lead_id = any (v_ids) and (bl.asignado_por is distinct from v_sup or bl.asignado_en is null)))::text);
    v_rep2 := private.bases_carga_repartir_core(v_sup, '00000000-0000-4000-8000-0000000b9001', v_base,
               pg_catalog.jsonb_build_object('modo', 'bloque', 'asignaciones', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('analista_id', v_ana, 'cantidad', 2))));
    v_res := v_res || pg_catalog.jsonb_build_object('P4', (v_rep2 = v_rep)::text);
    begin
      perform private.bases_carga_repartir_core(v_sup, pg_catalog.gen_random_uuid(), v_base,
                pg_catalog.jsonb_build_object('modo', 'bloque', 'asignaciones', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('analista_id', v_ana, 'cantidad', 5))));
      v_r := 'paso';
    exception when others then
      get stacked diagnostics v_r = pg_exception_detail;
      v_r := sqlstate || '|' || coalesce(v_r, '');
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P5', v_r);
    v_res := v_res || pg_catalog.jsonb_build_object('P6', (select string_agg(x.estado, ',' order by x.estado) from private.bases_carga_contactos_core(v_sup, v_base, 'todos') x));
    v_r := (select concat_ws('|', r->>'recogidos', r->>'omitidos', r->>'pendientes') from (select private.bases_carga_recoger_core(v_sup, pg_catalog.gen_random_uuid(), v_base, v_ana) r) q);
    v_res := v_res || pg_catalog.jsonb_build_object('P7', v_r || '|' || (not exists (select 1 from crm.leads l where l.id = any (v_ids)
                                                                                     and (l.vendedor_id is not null or l.asignado_supervisor_id is distinct from v_sup)))::text);
    begin
      perform private.bases_carga_repartir_core(v_ana, pg_catalog.gen_random_uuid(), v_base,
                pg_catalog.jsonb_build_object('modo', 'bloque', 'asignaciones', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('analista_id', v_ana, 'cantidad', 1))));
      v_r := 'paso';
    exception when others then
      v_r := sqlstate || ' ' || sqlerrm;
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P8', v_r);
    -- P9 · La puerta real como authenticated (el supervisor), si el rol de la sesión puede.
    begin
      perform pg_catalog.set_config('role', 'authenticated', true);
      v_r := (select pg_catalog.count(*)::text from crm.contactos_de_base(v_base, 'todos'));
      perform pg_catalog.set_config('role', 'none', true);
    exception when others then
      v_r := sqlstate || ' ' || sqlerrm;
    end;
    v_res := v_res || pg_catalog.jsonb_build_object('P9', v_r);
    raise exception using errcode = 'P0001', message = 'B9_DESHACER';
  exception when others then
    if sqlerrm <> 'B9_DESHACER' then
      v_res := v_res || pg_catalog.jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
    end if;
  end;
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);

  for c in select * from (values
      (1, 'P1', 'P1 crear la base del supervisor y cargar 3 contactos', '3'),
      (2, 'P2', 'P2 bloque «analista 2» → 2 repartidos a ese analista', '2|true'),
      (3, 'P3', 'P3 los repartidos siguen dormidos (sin bandeja, sin tenencia, sin ciclo SLA ni episodio) con su pertenencia', 'true'),
      (4, 'P4', 'P4 el replay devuelve la MISMA respuesta', 'true'),
      (5, 'P5', 'P5 si no alcanzan → 22023 con detail = disponibles', '22023|1'),
      (6, 'P6', 'P6 la lista de la base: 1 sin repartir y 2 sin tocar', 'sin_repartir,sin_tocar,sin_tocar'),
      (7, 'P7', 'P7 recoger al analista: 2 recogidos, de vuelta en la bandeja del supervisor', '2|0|0|true'),
      (8, 'P8', 'P8 el analista como actor → 42501', '42501 Solo Supervisión y Gerencia reparten y ven las bases'),
      (9, 'P9', 'P9 la puerta crm.contactos_de_base como authenticated', '3')) x(k, clave, caso, esperado) loop
    v_r := coalesce(v_res->>c.clave, 'sin resultado: ' || coalesce(v_res->>'error', '(nada)'));
    insert into pg_temp._b9_r (caso, esperado, obtenido, estado)
    values (c.caso, c.esperado, v_r,
            case when v_r = c.esperado then 'PASS'
                 when v_r like '55P03 %' or coalesce(v_res->>'error', '') like '55P03 %' then 'NOT RUN'
                 when c.k = 9 and v_r like '42501 permission denied to set role%' then 'NOT RUN'
                 else 'FAIL' end);
  end loop;
end;
$comprobar$;

-- Detalle (para psql) y, al final, el veredicto en UNA fila.
select format('%s %s · esperado %s · obtenido %s', r.estado, r.caso, r.esperado, left(r.obtenido, 200)) from pg_temp._b9_r r order by r.n;
select case
         when count(*) filter (where r.estado = 'FAIL') > 0 then
           'B9_COMPORTAMIENTO_FALLA: ' || string_agg(r.caso || ' → ' || left(r.obtenido, 120), ' | ' order by r.n) filter (where r.estado = 'FAIL')
         when count(*) filter (where r.estado = 'NOT RUN') > 0 then
           format('B9_COMPORTAMIENTO_PARCIAL: %s PASS · NOT RUN: %s', count(*) filter (where r.estado = 'PASS'),
                  string_agg(r.caso || ' (' || left(r.obtenido, 100) || ')', ' | ' order by r.n) filter (where r.estado = 'NOT RUN'))
         else format('B9_COMPORTAMIENTO_OK %s/%s', count(*), count(*))
       end as veredicto
  from pg_temp._b9_r r;
do $falla$
begin
  if exists (select 1 from pg_temp._b9_r where estado = 'FAIL') then
    raise exception 'B9: la comprobacion de comportamiento FALLA (ver el veredicto)';
  end if;
end;
$falla$;
rollback;
