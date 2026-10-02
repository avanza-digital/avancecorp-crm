-- REVERSA de 20260930172255_crm_cartera_f5_fuentes_mapas: restaura el cuerpo VIVO del 30/09/2026 de private.cartera_f5_fuentes() tal cual.
-- Se niega si la función no tiene la huella nueva o sus invariantes. NO toca schema_migrations: si se revierte,
-- anotarlo en MIGRACIONES.md el mismo día. Restaura también el COMMENT previo (no había: NULL; auditor-rls P3-2). No exige
-- las huellas de inversionista_canonica / analista_atribuido_cadena: el cuerpo vivo las llama, no las copia.
begin;
set local lock_timeout = '10s';
do $rev$
declare
  v_md5 text; v_oid oid := 'private.cartera_f5_fuentes()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = '94fa33cfcca657f70a1a94f98c3bf482' then raise notice 'REVERSA: ya está el cuerpo vivo del 30/09 (%)', v_md5; return; end if;
  if v_md5 <> 'fa15f7765d0892c790c7a4b6822e756e' then raise exception 'REVERSA: huella desconocida (%), no se toca', v_md5; end if;
  execute $def$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce(private.analista_atribuido_cadena(c.id),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> '94fa33cfcca657f70a1a94f98c3bf482' then raise exception 'REVERSA: huella inesperada tras restaurar (%)', v_md5; end if;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA-POST: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'REVERSA: cuerpo vivo del 30/09 restaurado (%)', v_md5;
end $rev$;
comment on function private.cartera_f5_fuentes() is null;
commit;
