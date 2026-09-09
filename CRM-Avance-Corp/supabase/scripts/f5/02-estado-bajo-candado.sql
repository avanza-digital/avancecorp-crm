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
