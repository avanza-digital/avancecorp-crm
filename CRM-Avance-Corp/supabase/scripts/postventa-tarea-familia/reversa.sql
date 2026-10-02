-- REVERSA de 20260930000550_crm_postventa_tarea_json_por_familia: restaura el cuerpo VIVO del 29/09/2026 de private.postventa_tarea_json(crm.tareas) tal cual.
-- Se niega si la función no tiene la huella nueva o sus invariantes. NO toca schema_migrations: si se revierte,
-- anotarlo en MIGRACIONES.md el mismo día.
begin;
set local lock_timeout = '10s';
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
commit;
