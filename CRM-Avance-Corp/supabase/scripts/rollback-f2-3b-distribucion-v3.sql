-- Vuelta atras de F2.3b (20260827090000_crm_f2_3b_distribucion_v3.sql).
--
-- F2.3b fue ADITIVA: creo la puerta v3, su motor y el helper de punteria, y
-- añadio una rama `elsif p_version=3` al despachador. Revertir = borrar lo
-- nuevo y devolver el despachador a su texto anterior (md5 vivo pre-F2.3b:
-- a45b00eb7beca4cf80dea2c138d65848). El bundle vivo NUNCA llamo a la v3, asi
-- que este rollback no puede romper ninguna pantalla.
--
-- Ejecutar con: supabase db query --linked --file <este fichero>

begin;

-- ---------------------------------------------------------------------------
-- 0. Guarda (Codex e8): este fichero SOLO revierte el estado post-F2.3b.
--    Si la migracion aborto en su preflight (nada aplicado) o alguien dejo
--    una v3 ajena, aqui NO se toca nada: borrar seria destruir estado que la
--    migracion decidio no tocar.
-- ---------------------------------------------------------------------------
do $guarda$
declare
  v_src text;
  v_owner name;
begin
  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname = 'metricas_distribucion_leads_autorizada'
     and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date, p_version smallint';
  if v_src is null then
    raise exception 'NADA QUE REVERTIR: el despachador de 3 argumentos no existe';
  end if;
  -- strpos, nunca LIKE (el guion bajo es comodin)
  if pg_catalog.strpos(
       lower(regexp_replace(v_src, '\s+', ' ', 'g')),
       'p_version=3 then v_payload:=private.metricas_distribucion_leads_v3_core(') = 0 then
    raise exception 'NADA QUE REVERTIR: el despachador vivo no tiene la rama v3 (F2.3b no esta aplicada)';
  end if;

  select pg_catalog.pg_get_userbyid(p.proowner) into v_owner
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'metricas_distribucion_leads_v3_fn';
  if v_owner is not null and v_owner is distinct from 'crm_metricas_bridge' then
    raise exception 'la v3 viva tiene dueño % — NO es la de F2.3b; revisar a mano antes de borrar nada', v_owner;
  end if;
end $guarda$;

-- ---------------------------------------------------------------------------
-- 1. Borrar lo nuevo. La puerta pertenece al puente: borrarla exige los
--    privilegios del dueño (Codex e7) — misma danza que la migracion, con
--    INHERIT en vez de SET, devuelta al terminar.
-- ---------------------------------------------------------------------------
do $drops$
declare
  v_tenia_inherit boolean;
begin
  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm' and p.proname = 'metricas_distribucion_leads_v3_fn'
  ) then
    v_tenia_inherit := pg_catalog.pg_has_role(current_user, 'crm_metricas_bridge', 'USAGE');
    if not v_tenia_inherit then
      execute pg_catalog.format('grant crm_metricas_bridge to %I with inherit true', current_user);
    end if;
    drop function crm.metricas_distribucion_leads_v3_fn(date, date);
    if not v_tenia_inherit then
      execute pg_catalog.format('revoke inherit option for crm_metricas_bridge from %I', current_user);
    end if;
  end if;
end $drops$;

drop function if exists private.metricas_distribucion_leads_v3_core(date, date, timestamp with time zone);
drop function if exists private.conversion_punteria(integer, integer);

-- El despachador vuelve a su texto pre-F2.3b (capturado vivo el 27/08).
create or replace function private.metricas_distribucion_leads_autorizada(p_desde date, p_hasta date, p_version smallint)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'Solo Gerencia o un lector global puede consultar estas metricas'
      using errcode='42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde>p_hasta
     or p_hasta>v_hoy or p_hasta-p_desde>365 then
    raise exception 'Periodo invalido: usa fechas hasta hoy y un maximo de 366 dias'
      using errcode='22023';
  end if;

  if p_version=1 then
    v_payload:=private.metricas_distribucion_leads_core(p_desde,p_hasta,v_ahora);
  elsif p_version=2 then
    v_payload:=private.metricas_distribucion_leads_v2_core(p_desde,p_hasta,v_ahora);
  else
    raise exception 'Version de metricas no soportada' using errcode='22023';
  end if;
  return private.sanitizar_sujetos_distribucion_crm(v_payload);
end;
$function$;

-- Postflight del rollback: el texto restaurado es EXACTAMENTE el vivo pre-F2.3b,
-- la puerta v3 dejo de existir y el puente quedo sin CREATE sobre crm.
do $check$
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'metricas_distribucion_leads_autorizada')
     is distinct from 'a45b00eb7beca4cf80dea2c138d65848' then
    raise exception 'el despachador restaurado NO coincide byte a byte con el pre-F2.3b';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm' and p.proname = 'metricas_distribucion_leads_v3_fn'
  ) then
    raise exception 'la puerta v3 sigue existiendo';
  end if;
  if pg_catalog.has_schema_privilege('crm_metricas_bridge', 'crm', 'CREATE') then
    raise exception 'el puente quedo con CREATE sobre crm';
  end if;
  raise notice 'ROLLBACK F2.3b OK: despachador restaurado byte a byte, v3 borrada, puente intacto';
end $check$;

commit;
