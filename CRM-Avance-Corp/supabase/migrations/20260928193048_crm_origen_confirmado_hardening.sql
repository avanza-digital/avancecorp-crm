-- Hardening del bloque de procedencia: conservar la fecha auditada permite
-- desactivar una confirmación aunque su fuente cambie o sea anulada.
-- Las referencias son UUID validados por el escritor, sin impedir el ciclo
-- administrativo de las tablas financieras mediante nuevas FKs.
do $$ begin
  if exists(select 1 from crm.origenes_capital_confirmados) then
    raise exception 'Hardening inicial requiere la tabla de confirmaciones vacia';
  end if;
end $$;
alter table crm.origenes_capital_confirmados
  drop constraint origenes_capital_confirmados_contrato_id_fkey,
  drop constraint origenes_capital_confirmados_cierre_externo_id_fkey,
  drop constraint origenes_capital_confirmados_confirmado_por_fkey,
  add column fecha_comercial date not null;

create or replace function private.origen_capital_confirmado_guardar()
returns trigger language plpgsql security invoker set search_path='' as $function$
declare
  v_fecha date;
  v_periodo date;
begin
  if tg_op='DELETE' then raise exception 'Las confirmaciones se desactivan, no se eliminan'; end if;
  -- Atribucion declarativa de SQL de mantenimiento; no es una puerta API.
  if current_user <> 'postgres' or (select auth.uid()) is null
     or private.rol_crm((select auth.uid())) is distinct from 'gerencia'
     or not exists(select 1 from crm.equipo where perfil_id=(select auth.uid()) and activo)
  then raise exception using errcode='42501',message='Requiere mantenimiento autorizado por Gerencia'; end if;
  if tg_op='UPDATE' then
    if not old.activo or new.activo or
       (to_jsonb(new)-'activo') is distinct from (to_jsonb(old)-'activo') then
      raise exception 'Una confirmacion solo admite desactivacion auditada';
    end if;
    v_fecha:=old.fecha_comercial;
  else
    if new.confirmado_por is distinct from (select auth.uid()) then
      raise exception 'El actor de la confirmacion debe coincidir con la sesion';
    end if;
    if new.contrato_id is not null and new.cierre_externo_id is null then
      select fecha_cierre_comercial into v_fecha from public.contratos
      where id=new.contrato_id and not es_demo and categoria='nuevo' for share;
    elsif new.cierre_externo_id is not null and new.contrato_id is null then
      select coalesce(fecha_comercial,(creado_en at time zone 'America/Lima')::date)
      into v_fecha from crm.cierres_externos
      where id=new.cierre_externo_id and anulado_en is null for share;
    end if;
    if v_fecha is null then raise exception 'Fuente comercial no elegible'; end if;
    new.fecha_comercial:=v_fecha;
  end if;
  v_periodo:=date_trunc('month',v_fecha)::date;
  perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),(v_periodo-date '2000-01-01')::integer);
  if exists(select 1 from crm.periodos_cerrados where periodo=v_periodo) then
    raise exception 'El mes comercial ya esta sellado';
  end if;
  return new;
end;
$function$;
revoke all on function private.origen_capital_confirmado_guardar() from public,anon,authenticated,service_role;

-- Evitar un default ambiguo: toda puerta debe enviar su canal expresamente.
alter table crm.leads alter column origen drop default;
comment on column crm.origenes_capital_confirmados.fecha_comercial is
'Fecha verificada de la fuente al confirmar, inmutable; determina el mes cuyo sello protege altas y desactivaciones.';
