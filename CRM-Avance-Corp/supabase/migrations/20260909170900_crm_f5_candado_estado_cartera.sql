-- F5: corregir el censo D-19 sin alterar el archivo ya versionado.
-- Instalar después de 20260908230249_crm_f5_cartera_ficha_multiempresa.sql.
-- Generado por scripts/f5/generar-candado.mjs; no activa ninguna bandera.
do $pre$
begin
  if to_regprocedure('crm.cartera_inversionistas_estado_fn()') is null
    or to_regprocedure('private.resolver_en_puertas_bajo_candado()') is null then
    raise exception 'Faltan F5 o el bloqueo publicado de identidad';
  end if;
  if (select md5(prosrc) from pg_proc where oid='crm.cartera_inversionistas_estado_fn()'::regprocedure)
    is distinct from 'f8da95a16b2134e5046b82ddaf82a740' then
    raise exception 'La capacidad F5 cambió: revisar antes de sustituirla';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='ficha_360_neutral'),true) then
    raise exception 'Instalar la corrección con F5 apagada';
  end if;
end;
$pre$;

-- D-19: también la capacidad de lectura comparte el bloqueo del cambio de modo.
-- VOLATILE permite que el helper vea el valor confirmado después de esperar.
-- La API conserva el mismo JSON y los mismos permisos; no cambia banderas.
create or replace function crm.cartera_inversionistas_estado_fn()
returns jsonb language plpgsql volatile security definer set search_path='' set lock_timeout='5s'
as $f$
declare
  v_uid uuid:=(select auth.uid());
  v_rol text:=private.rol_crm(v_uid);
  v_lector boolean:=private.es_lector_global();
  v_f3 boolean; v_f5 boolean; v_cobertura boolean;
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_f3:=private.resolver_en_puertas_bajo_candado();
  -- El bloqueo pudo esperar: comprobar otra vez la membresía vigente.
  select private.rol_crm(v_uid),private.es_lector_global() into v_rol,v_lector;
  if not coalesce(v_rol in ('vendedor','supervisor','gerencia') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  select coalesce(bool_or(activo),false) into v_f5
    from crm.multiempresa_flags where nombre='ficha_360_neutral';
  -- OFF no depende del censo ni escanea fuentes: conserva la cartera publicada.
  if not v_f3 or not v_f5 then
    return jsonb_build_object('version',1,'habilitada',false,
      'escritura_habilitada',false,'motivo','La cartera multiempresa aún no está habilitada');
  end if;
  select not exists (
    select 1 from private.cartera_f5_fuentes() f
    left join crm.inversionistas i on i.id=f.inversionista_id
    where not coalesce(f.identidad_coherente,false) or i.id is null
      or i.inversionista_canonico_id is not null
  ) into v_cobertura;
  return jsonb_build_object('version',1,'habilitada',v_cobertura,
    'escritura_habilitada',v_cobertura and not v_lector
      and private.puede_gestionar_contratos_crm()
      and coalesce((select activo from crm.multiempresa_flags where nombre='inversiones_escritura'),false),
    'motivo',case when not v_cobertura then 'La cartera requiere conciliación antes de habilitarse' end);
end;
$f$;

revoke all on function crm.cartera_inversionistas_estado_fn() from public,anon,authenticated,service_role;
grant execute on function crm.cartera_inversionistas_estado_fn() to authenticated;

do $post$
begin
  if not exists(select 1 from pg_proc p where p.oid='crm.cartera_inversionistas_estado_fn()'::regprocedure
    and p.prosecdef and p.proowner='postgres'::regrole and p.provolatile='v'
    and p.proconfig @> array['search_path=""','lock_timeout=5s']
    and strpos(p.prosrc,'resolver_en_puertas_bajo_candado()')>0)
    or has_function_privilege('anon','crm.cartera_inversionistas_estado_fn()','EXECUTE')
    or has_function_privilege('service_role','crm.cartera_inversionistas_estado_fn()','EXECUTE')
    or not has_function_privilege('authenticated','crm.cartera_inversionistas_estado_fn()','EXECUTE') then
    raise exception 'Postflight: revisar bloqueo, volatilidad y permisos de F5';
  end if;
end;
$post$;
notify pgrst, 'reload schema';
