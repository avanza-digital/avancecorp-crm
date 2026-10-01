-- REGISTRO en supabase_migrations.schema_migrations de 20260930000550_crm_postventa_tarea_json_por_familia.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si la función
-- no tiene la huella nueva o sus invariantes, o si la versión ya está registrada con otro nombre; relee la fila antes de confirmar.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_postventa_tarea_json_por_familia'));
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
commit;
