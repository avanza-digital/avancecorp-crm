-- Verificación del paso 3a «SLA por filas» (kit v4) (M1 20261017054425_crm_sla_ventana_por_filas · M2 20261017054426_crm_sla_avisos_por_filas · M3 20261017054427_crm_sla_cola_por_filas). SOLO LECTURA.
-- Correr ANTES y DESPUÉS de cada migración (y de cada reversa):
--   supabase db query --linked --file supabase/scripts/sla-por-filas/verificar.sql
-- Corre en BEGIN READ ONLY (las escrituras persistentes ordinarias fallan con 25006) y termina SIEMPRE en raise P0001: el
-- informe sale en el mensaje del error. NO es un gate por código de salida: hay que LEER el informe y detenerse ante
-- cualquier otro error. Informa:
--   * el estado de cada pieza por huellas (md5 de pg_get_functiondef y de prosrc + metadatos) y la SERIE (ANTES, M1, M2, M3
--     o MIXTO); «GATE SERIE COMPLETA» exige M3 (Codex);
--   * que el productor, el helper de clientes y sla_leads_operativos siguen siendo los ensayados;
--   * la familia SLA; la ACL EFECTIVA de las piezas privadas para TODOS los roles no superusuario y ajenos a postgres
--     (has_function_privilege) y la ACL guardada (aclexplode); la de las puertas;
--   * el censo analítico (private.contadores_crudos_leads_citas(), sin el esquema bench del banco): tiene que ser IGUAL
--     antes y después;
--   * los guardianes: los 3 del SLA tienen que dar OK; los otros 4 se informan para comparar antes/después;
--   * v4: el historial de la serie en el índice (estado, eventos y si coincide con la serie viva) y cuántas versiones del
--     índice posteriores a la M1 de esta generación NO son de la serie (antes de aplicar M1 tiene que ser 0).
-- «GATE SERIE COMPLETA: OK» identifica el estado de la serie; NO es una aprobación (ver LEEME).
-- Esperado: ANTES → familia 62 · 1adaf6c5708637fd916705cc090a4218 · M1 → 64 · 1a632cfd48a2cc1602646a8fb0fb5285 · M2 → 64 · 5e4e27c4548576663fa65b801a839f0e · M3 → 64 · f9ea903841b9186ac985e103e050e6d5
begin read only;
do $verificar$
declare
  v_tabla jsonb := $tabla${"private.sla_operacion_ambito(uuid[],boolean)": {"M1": ["e843f6cd039b92a5fcd1e629d6ad4138", "b75fb4c86471cba36687c15986bd60dc", "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|ba5d2ec895f334e53417ef36cffebb2b"]}, "private.sla_operacion_autorizada_filas(uuid[])": {"M1": ["5aa191534358b819d8b8f0254f91c471", "250863962d4a0a5adb564d2e7c8a39cb", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|record|3094558e14db3ba8d8fa684e5ce99ca5"]}, "private.sla_operacion_autorizada(uuid[],boolean)": {"ANTES": ["a5bd718f2f288565ecb510f6ba1e8634", "a5fd870bf432dc907f5849a61a5fb9a8", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9"], "M1": ["4cdaa81a538473ea322ca5e4835652d4", "7d8c87935730be5f3b43559dc05e977a", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9"]}, "private.assert_sla_nucleo()": {"ANTES": ["6bc541b2e3ba1549b4b4ed419c22d455", "dfdbedf7e2a2b0f6790be6b307a88a85", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"], "M1": ["a938047d5c98aa009984a9e836b2fc9d", "7f5a08dde907b343b8562b6024eba110", "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"]}, "private.assert_sla_avisos()": {"ANTES": ["9b9edc86c3a55d89367b6d64203d38dc", "0eeb9efef832ddfbb5acbf48a812f9b1", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"], "M1": ["fb433efc037f09647481744a5f36380c", "7c6007603919f41406649edffa63429d", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"], "M2": ["1cbce7c3cdd9d39e61e9c26af29a9f7e", "d307e5acaa84517072d8f65db882c1f3", "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"]}, "crm.avisos_sla_resumen_v2_fn()": {"ANTES": ["e9ce617ab0cc33bc5614ef69e877cc71", "576b1aa6e4d3eddd947d6bbdb1c99f40", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|502d0d8cb0124b164f936cf6ef6dba63"], "M2": ["82a7cabdae761ea7b3707db9f9c62452", "3387f3aff90b1e47e05bcddea14a91e3", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|0003d4f1991eab3f3d0105e52a9a9f2a"]}, "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {"ANTES": ["1ec76074c9b5650cb8bac4c79440eccb", "828989da281bc8c32fab812542e86ba9", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|4fc30931ad31e222dc19423d89befb12"], "M3": ["6096aa636688f01677327c5504ffaa8b", "34b5abf032aac26cf5453f6e85f3d370", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|3f313ac52acf379e299c15a75344f9b6"]}, "private.assert_cola_v3()": {"ANTES": ["162fe9e053c8b57f8b501dadbe2afca7", "97d9d1b96c9b9a882a6518b890d082c0", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2"], "M3": ["5b000de8271604d1c6780dcc2425e90f", "862b765b58b1cb7725b375b587733b81", "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2"]}}$tabla$::jsonb;
  v_estados jsonb := $estados${"ANTES": {"private.sla_operacion_ambito(uuid[],boolean)": "AUSENTE", "private.sla_operacion_autorizada_filas(uuid[])": "AUSENTE", "private.sla_operacion_autorizada(uuid[],boolean)": "ANTES", "private.assert_sla_nucleo()": "ANTES", "private.assert_sla_avisos()": "ANTES", "crm.avisos_sla_resumen_v2_fn()": "ANTES", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "ANTES", "private.assert_cola_v3()": "ANTES"}, "M1": {"private.sla_operacion_ambito(uuid[],boolean)": "M1", "private.sla_operacion_autorizada_filas(uuid[])": "M1", "private.sla_operacion_autorizada(uuid[],boolean)": "M1", "private.assert_sla_nucleo()": "M1", "private.assert_sla_avisos()": "M1", "crm.avisos_sla_resumen_v2_fn()": "ANTES", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "ANTES", "private.assert_cola_v3()": "ANTES"}, "M2": {"private.sla_operacion_ambito(uuid[],boolean)": "M1", "private.sla_operacion_autorizada_filas(uuid[])": "M1", "private.sla_operacion_autorizada(uuid[],boolean)": "M1", "private.assert_sla_nucleo()": "M1", "private.assert_sla_avisos()": "M2", "crm.avisos_sla_resumen_v2_fn()": "M2", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "ANTES", "private.assert_cola_v3()": "ANTES"}, "M3": {"private.sla_operacion_ambito(uuid[],boolean)": "M1", "private.sla_operacion_autorizada_filas(uuid[])": "M1", "private.sla_operacion_autorizada(uuid[],boolean)": "M1", "private.assert_sla_nucleo()": "M1", "private.assert_sla_avisos()": "M2", "crm.avisos_sla_resumen_v2_fn()": "M2", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "M3", "private.assert_cola_v3()": "M3"}}$estados$::jsonb;
  v_exigidas jsonb := $exigidas${"private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": ["0abdf640b5f4f10ab2e85b6bd2494522", "e47f610fb4cde0741f2a22c3e2e7ee2c"], "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": ["234ee27f745ef1817be0e0cbdd2b2e25", "8d02b260a0aa0bc50536afdc82c32ba3"], "private.sla_leads_operativos()": ["8d478d783e4c591662388ddf7405058a", "fd8f5800b253b137e82e666b9a89ab0a"]}$exigidas$::jsonb;
  v_exigidas_ok boolean := true;
  v_firma text; v_versiones jsonb; v_oid oid; v_md5_def text; v_md5_src text; v_meta text; v_et text; v_e text;
  v_actual jsonb := '{}'; v_serie text; v_informe text := '';
  v_h_tabla boolean; v_h_estado integer := 0; v_h_ok boolean := true; v_h_max text; v_h_lista text := '';
  v_h_apl text[] := array[null, null, null]::text[]; v_h_version text; v_h_nombre text; v_h_n integer;
  v_h_max_global numeric; v_n_ajenas bigint;
  v_familias jsonb := $familias${"ANTES": "62 · 1adaf6c5708637fd916705cc090a4218", "M1": "64 · 1a632cfd48a2cc1602646a8fb0fb5285", "M2": "64 · 5e4e27c4548576663fa65b801a839f0e", "M3": "64 · f9ea903841b9186ac985e103e050e6d5"}$familias$::jsonb;
  v_familia text; v_g text; v_res text;
  v_guardianes text[] := array['private.assert_sla_nucleo()', 'private.assert_cola_v3()', 'private.assert_sla_avisos()',
    'private.assert_gestion_diaria()', 'private.assert_analitica_leads_citas()', 'private.assert_analista_vigencia()',
    'private.assert_f7_piezas_cerradas()'];
begin
  perform pg_catalog.set_config('search_path', '', true);
  perform pg_catalog.set_config('quote_all_identifiers', 'off', true);
  for v_firma, v_versiones in select e.key, e.value from pg_catalog.jsonb_each(v_tabla) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      v_et := 'AUSENTE';
    else
      select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')))
        into v_md5_def, v_md5_src, v_meta from pg_catalog.pg_proc p where p.oid = v_oid;
      v_et := null;
      for v_e in select k.key from pg_catalog.jsonb_each(v_versiones) k loop
        if v_versiones->v_e = pg_catalog.jsonb_build_array(v_md5_def, v_md5_src, v_meta) then v_et := v_e; end if;
      end loop;
      v_et := coalesce(v_et, 'DESCONOCIDA def=' || v_md5_def || ' prosrc=' || v_md5_src || ' meta=' || v_meta);
    end if;
    v_actual := v_actual || pg_catalog.jsonb_build_object(v_firma, v_et);
    v_informe := v_informe || E'\n  ' || v_firma || ' = ' || v_et;
  end loop;
  select min(s.key) into v_serie from pg_catalog.jsonb_each(v_estados) s where s.value = v_actual;
  -- Piezas que la serie EXIGE sin cambios (productor, helper de clientes, ayudante de operativos).
  for v_firma, v_versiones in select e.key, e.value from pg_catalog.jsonb_each(v_exigidas) e loop
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc) into v_md5_def, v_md5_src
      from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_firma);
    if pg_catalog.jsonb_build_array(v_md5_def, v_md5_src) is distinct from v_versiones then
      v_exigidas_ok := false;
      v_informe := v_informe || E'\n  EXIGIDA CAMBIADA: ' || v_firma || ' def=' || coalesce(v_md5_def, 'AUSENTE');
    end if;
  end loop;
  v_serie := coalesce(v_serie, 'MIXTO');
  perform pg_catalog.set_config('search_path', 'pg_catalog', true);
  select count(*) || ' · ' || md5(string_agg(firma || '|' || m || '|' || cfg || '|' || d || '|' || v || '|' || o || '|' || a, E'\n' order by firma collate "C"))
    into v_familia
    from (select p.oid::regprocedure::text firma, md5(p.prosrc) m, coalesce(array_to_string(p.proconfig, ','), '') cfg,
                 p.prosecdef::text d, p.provolatile::text v, pg_get_userbyid(p.proowner)::text o, coalesce(p.proacl::text, '') a
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('crm', 'private')
             and (p.proname like 'sla\_%' or p.proname like 'avisos\_sla%' or p.proname like 'cola\_accion%'
                  or p.proname like 'estado\_sla%' or p.proname like 'gestion\_diaria\_%')) f;
  perform pg_catalog.set_config('search_path', '', true);
  v_informe := 'SERIE=' || v_serie || ' · familia SLA=' || v_familia
    || case when v_familia = v_familias->>v_serie then ' (la esperada)' else ' (NO es la esperada para la serie)' end
    || E'\nGATE SERIE COMPLETA (exige M3): ' || case when v_serie = 'M3' and v_exigidas_ok then 'OK' else 'NO' end
    || E'\nPiezas exigidas sin cambios (productor, helper, operativos): ' || case when v_exigidas_ok then 'IGUALES' else 'CAMBIADAS' end
    || v_informe;
  -- v4: historial de la serie en el índice y orden global (solo lectura; sin índice, lo dice).
  begin
  -- Historial de la serie (v3, Codex P1). Sus filas del índice, en orden de versión, tienen que formar una secuencia válida
  -- ANTES → M1 → M2 → M3 y vuelta: aplicar mN solo desde M(N-1) y revertir mN solo desde MN. De ahí salen el estado al que
  -- lleva el historial (v_h_estado), la última aplicación de cada mN (v_h_apl) y la versión más alta de la serie (v_h_max).
  -- Las aplicaciones se reconocen por su nombre (cualquier generación) y las reversas por «<nombre>_revertir».
  v_h_tabla := pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null;
  if v_h_tabla then
    for v_h_version, v_h_nombre in execute
        'select m.version, m.name from supabase_migrations.schema_migrations m where m.name = any ($1) order by m.version collate "C"'
        using array['crm_sla_ventana_por_filas', 'crm_sla_avisos_por_filas', 'crm_sla_cola_por_filas', 'crm_sla_ventana_por_filas_revertir', 'crm_sla_avisos_por_filas_revertir', 'crm_sla_cola_por_filas_revertir']::text[] loop
      v_h_n := pg_catalog.array_position(array['crm_sla_ventana_por_filas', 'crm_sla_avisos_por_filas', 'crm_sla_cola_por_filas', 'crm_sla_ventana_por_filas_revertir', 'crm_sla_avisos_por_filas_revertir', 'crm_sla_cola_por_filas_revertir']::text[], v_h_nombre);
      if v_h_n <= 3 and v_h_estado = v_h_n - 1 then
        v_h_estado := v_h_n;
        v_h_apl[v_h_n] := v_h_version;
      elsif v_h_n > 3 and v_h_estado = v_h_n - 3 then
        v_h_estado := v_h_n - 4;
      else
        v_h_ok := false;
      end if;
      v_h_max := v_h_version;
      v_h_lista := v_h_lista || ' ' || v_h_version || '=' || v_h_nombre;
    end loop;
  end if;
    if not v_h_tabla then
      v_informe := v_informe || E'\nÍndice de migraciones: AUSENTE (banco o arnés)';
    else
    execute 'select count(*) from supabase_migrations.schema_migrations m where m.version ~ ''^[0-9]+$'' and m.version::numeric > $1::numeric and not (m.name = any ($2))'
      into v_n_ajenas using '20261017054425', array['crm_sla_ventana_por_filas', 'crm_sla_avisos_por_filas', 'crm_sla_cola_por_filas', 'crm_sla_ventana_por_filas_revertir', 'crm_sla_avisos_por_filas_revertir', 'crm_sla_cola_por_filas_revertir']::text[];
      v_informe := v_informe || E'\nHistorial de la serie en el índice: '
        || case when not v_h_ok then 'NO VÁLIDO' when v_h_estado = 0 then 'ANTES' else 'M' || v_h_estado end
        || ' · coincide con la serie viva: ' || case when v_h_ok and (case when v_h_estado = 0 then 'ANTES' else 'M' || v_h_estado end) = v_serie then 'SÍ' else 'NO' end
        || ' · eventos:' || coalesce(nullif(v_h_lista, ''), ' ninguno')
        || E'\nVersiones del índice posteriores a 20261017054425 que no son de la serie: ' || v_n_ajenas || ' (antes de aplicar M1 tiene que ser 0)';
    end if;
  exception when others then
    v_informe := v_informe || E'\nÍndice de migraciones: no se pudo leer [' || sqlstate || '] ' || left(sqlerrm, 120);
  end;
  -- ACL efectiva de las piezas privadas: todos los roles no superusuario que no son (ni heredan) postgres.
  select coalesce(pg_catalog.string_agg(f.firma || ' ejecutable por ' || r.rolname, '; ' order by f.firma, r.rolname), 'ninguna') into v_res
    from pg_catalog.unnest(array['private.sla_operacion_ambito(uuid[],boolean)', 'private.sla_operacion_autorizada_filas(uuid[])',
           'private.sla_operacion_autorizada(uuid[],boolean)']) f(firma), pg_catalog.pg_roles r
   where pg_catalog.to_regprocedure(f.firma) is not null and not r.rolsuper and r.rolname <> 'postgres'
     and not pg_catalog.pg_has_role(r.oid, 'postgres', 'MEMBER')
     and pg_catalog.has_function_privilege(r.oid, f.firma, 'EXECUTE');
  v_informe := v_informe || E'\nACL efectiva de las piezas privadas, todos los roles (debe ser «ninguna»): ' || v_res;
  select coalesce(pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::text || ' → ' || a.grantee::pg_catalog.regrole::text, '; '), 'ninguna') into v_res
    from pg_catalog.pg_proc p, pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
   where p.oid in (pg_catalog.to_regprocedure('private.sla_operacion_ambito(uuid[],boolean)'),
                   pg_catalog.to_regprocedure('private.sla_operacion_autorizada_filas(uuid[])'),
                   pg_catalog.to_regprocedure('private.sla_operacion_autorizada(uuid[],boolean)'))
     and a.grantee <> p.proowner;
  v_informe := v_informe || E'\nACL guardada de las piezas privadas fuera del dueño (debe ser «ninguna»): ' || v_res;
  select pg_catalog.string_agg(f.firma || '=' || coalesce(pg_catalog.array_to_string(array(select r.rolname from pg_catalog.pg_roles r
           where not r.rolsuper and r.rolname <> 'postgres' and not pg_catalog.pg_has_role(r.oid, 'postgres', 'MEMBER')
             and pg_catalog.has_function_privilege(r.oid, f.firma, 'EXECUTE') order by r.rolname), ','), ''), '; ') into v_res
    from pg_catalog.unnest(array['crm.avisos_sla_resumen_v2_fn()', 'crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)']) f(firma);
  v_informe := v_informe || E'\nACL efectiva de las puertas (authenticated y quien lo herede; nunca anon ni service_role): ' || v_res;
  -- Censo analítico (sin bench, el andamiaje del banco): igual antes y después.
  begin
    select pg_catalog.count(*) || ' · ' || coalesce(pg_catalog.md5(pg_catalog.string_agg(c.tipo || '|' || c.objeto || '|' || c.declarada::text || '|'
             || c.huella_ok::text, E'\n' order by c.tipo, c.objeto)), '-')
      into v_res from private.contadores_crudos_leads_citas() c where c.objeto not like 'bench.%';
    v_informe := v_informe || E'\nCenso analítico (contadores_crudos_leads_citas, sin bench): ' || v_res;
  exception when others then
    v_informe := v_informe || E'\nCenso analítico: FALLA [' || sqlstate || '] ' || left(sqlerrm, 120);
  end;
  foreach v_g in array v_guardianes loop
    begin
      execute 'select ' || v_g into v_res;
      v_informe := v_informe || E'\n' || v_g || ': ' || case when (v_res like 'OK%') is true then 'OK' else 'NO OK: ' || coalesce(left(v_res, 120), 'NULL') end;
    exception when others then
      v_informe := v_informe || E'\n' || v_g || ': FALLA [' || sqlstate || '] ' || left(sqlerrm, 160);
    end;
  end loop;
  raise exception using errcode = 'P0001', message = E'VERIFICACION SLA POR FILAS (no escribe nada)\n' || v_informe;
end $verificar$;
rollback;
