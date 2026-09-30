-- ENSAYO DESHECHO del ciclo (migración → repetida → reversa → migración → registrador): cuerpos sin begin/commit; termina en raise y rollback.
begin;
set local lock_timeout = '10s';
do $mig$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función viva no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'bff893c533d645be75d884788173bd50' then
    raise notice 'postventa_tarea_json_por_familia: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> 'c29fd1d25ab775ecd63ab2660a847d0e' then
    raise exception 'PREFLIGHT: private.postventa_tarea_json(crm.tareas) no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',(with recursive familia as (
        -- Candidatas: la raíz canónica de la persona y quienes cuelgan de ella (tope 16, como
        -- inversionista_canonica). Es un superconjunto de las personas con la misma canónica; el
        -- filtro de abajo conserva el criterio EXACTO de antes sin recorrer las 565 personas por
        -- tarea (320 de los 532 ms de la agenda de postventa, medido el 29/09/2026).
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'postventa_tarea_json_por_familia: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h1', md5(pg_get_functiondef('private.postventa_tarea_json(crm.tareas)'::regprocedure)), true);
do $mig$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función viva no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'bff893c533d645be75d884788173bd50' then
    raise notice 'postventa_tarea_json_por_familia: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> 'c29fd1d25ab775ecd63ab2660a847d0e' then
    raise exception 'PREFLIGHT: private.postventa_tarea_json(crm.tareas) no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',(with recursive familia as (
        -- Candidatas: la raíz canónica de la persona y quienes cuelgan de ella (tope 16, como
        -- inversionista_canonica). Es un superconjunto de las personas con la misma canónica; el
        -- filtro de abajo conserva el criterio EXACTO de antes sin recorrer las 565 personas por
        -- tarea (320 de los 532 ms de la agenda de postventa, medido el 29/09/2026).
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'postventa_tarea_json_por_familia: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h1b', md5(pg_get_functiondef('private.postventa_tarea_json(crm.tareas)'::regprocedure)), true);
do $rev$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: dueño/ACL/definer/volatilidad/search_path no son los esperados (dueño %, acl %, definer %, vol %, cfg %); no se toca', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'c29fd1d25ab775ecd63ab2660a847d0e' then raise notice 'REVERSA: ya está el cuerpo vivo del 29/09 (%)', v_md5; return; end if;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then raise exception 'REVERSA: huella desconocida (%), no se toca', v_md5; end if;
  execute $def$
CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',array(select i.perfil_id from crm.inversionistas i
      where i.perfil_id is not null and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
      order by i.perfil_id),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'c29fd1d25ab775ecd63ab2660a847d0e' then raise exception 'REVERSA: la huella restaurada no coincide (%)', v_md5; end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: tras restaurar, dueño/ACL/definer/volatilidad/search_path no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'REVERSA_POSTVENTA_TAREA_OK (%)', v_md5;
end $rev$;
select set_config('ensayo.h2', md5(pg_get_functiondef('private.postventa_tarea_json(crm.tareas)'::regprocedure)), true);
do $mig$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función viva no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'bff893c533d645be75d884788173bd50' then
    raise notice 'postventa_tarea_json_por_familia: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> 'c29fd1d25ab775ecd63ab2660a847d0e' then
    raise exception 'PREFLIGHT: private.postventa_tarea_json(crm.tareas) no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',(with recursive familia as (
        -- Candidatas: la raíz canónica de la persona y quienes cuelgan de ella (tope 16, como
        -- inversionista_canonica). Es un superconjunto de las personas con la misma canónica; el
        -- filtro de abajo conserva el criterio EXACTO de antes sin recorrer las 565 personas por
        -- tarea (320 de los 532 ms de la agenda de postventa, medido el 29/09/2026).
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'postventa_tarea_json_por_familia: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h3', md5(pg_get_functiondef('private.postventa_tarea_json(crm.tareas)'::regprocedure)), true);
do $chk$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then
    raise exception 'REGISTRO: la función no tiene la huella nueva (%); aplica primero la migración 20260930000550', v_md5;
  end if;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: dueño/ACL/definer/volatilidad/search_path no son los esperados (dueño %, acl %, definer %, vol %, cfg %); no se registra', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930000550' and coalesce(name,'') <> 'crm_postventa_tarea_json_por_familia') then
    raise exception 'REGISTRO: la versión 20260930000550 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930000550', 'crm_postventa_tarea_json_por_familia', array[$stm$
CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',(with recursive familia as (
        -- Candidatas: la raíz canónica de la persona y quienes cuelgan de ella (tope 16, como
        -- inversionista_canonica). Es un superconjunto de las personas con la misma canónica; el
        -- filtro de abajo conserva el criterio EXACTO de antes sin recorrer las 565 personas por
        -- tarea (320 de los 532 ms de la agenda de postventa, medido el 29/09/2026).
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260930000550' and name = 'crm_postventa_tarea_json_por_familia') then
    raise exception 'REGISTRO: tras el insert, la versión 20260930000550 no quedó con el nombre esperado';
  end if;
  raise notice 'REGISTRO_POSTVENTA_TAREA_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260930000550';
do $$ begin
  raise exception E'CICLO (rollback)\nmig: % (esperado bff893c5…)\nmig repetida (idempotente): %\nreversa: % (esperado c29fd1d2…)\nmig otra vez: %\nregistro: %',
    current_setting('ensayo.h1',true), current_setting('ensayo.h1b',true), current_setting('ensayo.h2',true), current_setting('ensayo.h3',true),
    (select version||' / '||name||' / '||cardinality(statements)||' sentencia(s)' from supabase_migrations.schema_migrations where version='20260930000550');
end $$;
rollback;
