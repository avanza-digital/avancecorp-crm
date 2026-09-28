-- Procedencia confirmada de fuentes históricas que carecen de lead.
-- No crea leads, acreditaciones ni hechos económicos retroactivos.
create table crm.origenes_capital_confirmados (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid references public.contratos(id),
  cierre_externo_id uuid references crm.cierres_externos(id),
  origen text not null check (origen in ('landing','formulario','referido','oficina')),
  motivo text not null check (length(btrim(motivo)) between 10 and 500),
  confirmado_por uuid not null references public.perfiles(id),
  creado_en timestamptz not null default now(),
  activo boolean not null default true,
  check (num_nonnulls(contrato_id,cierre_externo_id)=1)
);
alter table crm.origenes_capital_confirmados enable row level security;
revoke all on crm.origenes_capital_confirmados from public,anon,authenticated,service_role;
create unique index origenes_capital_contrato_activo on crm.origenes_capital_confirmados(contrato_id) where activo;
create unique index origenes_capital_externo_activo on crm.origenes_capital_confirmados(cierre_externo_id) where activo;
comment on table crm.origenes_capital_confirmados is
'Confirmaciones administrativas de canal para fuentes sin lead. SQL de mantenimiento autorizado, RLS deny-by-default; lectura exclusiva desde el ranking. No acredita conversiones ni altera el contrato.';

create function private.origen_capital_confirmado_guardar()
returns trigger language plpgsql security invoker set search_path='' as $function$
declare
  v_fecha date;
  v_periodo date;
begin
  if tg_op='DELETE' then raise exception 'Las confirmaciones se desactivan, no se eliminan'; end if;
  if current_user <> 'postgres' or (select auth.uid()) is null
     or private.rol_crm((select auth.uid())) is distinct from 'gerencia'
     or not exists(select 1 from crm.equipo where perfil_id=(select auth.uid()) and activo)
  then raise exception using errcode='42501',message='Requiere mantenimiento autorizado por Gerencia'; end if;
  if tg_op='UPDATE' then
    if not old.activo or new.activo or
       (to_jsonb(new)-'activo') is distinct from (to_jsonb(old)-'activo') then
      raise exception 'Una confirmacion solo admite desactivacion auditada';
    end if;
  elsif new.confirmado_por is distinct from (select auth.uid()) then
    raise exception 'El actor de la confirmacion debe coincidir con la sesion';
  end if;
  if new.contrato_id is not null then
    select fecha_cierre_comercial into v_fecha from public.contratos
    where id=new.contrato_id and not es_demo and categoria='nuevo';
  else
    select coalesce(fecha_comercial,(creado_en at time zone 'America/Lima')::date)
    into v_fecha from crm.cierres_externos where id=new.cierre_externo_id and anulado_en is null;
  end if;
  if v_fecha is null then raise exception 'Fuente comercial no elegible'; end if;
  v_periodo:=date_trunc('month',v_fecha)::date;
  perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),(v_periodo-date '2000-01-01')::integer);
  if exists(select 1 from crm.periodos_cerrados where periodo=v_periodo) then
    raise exception 'El mes comercial ya esta sellado';
  end if;
  return new;
end;
$function$;
revoke all on function private.origen_capital_confirmado_guardar() from public,anon,authenticated,service_role;
create trigger trg_origen_capital_confirmado_guardar before insert or update or delete
on crm.origenes_capital_confirmados for each row execute function private.origen_capital_confirmado_guardar();
create trigger trg_audit_origenes_capital_confirmados after insert or update or delete
on crm.origenes_capital_confirmados for each row execute function private.log_audit_crm();

create function private.ranking_origen_confirmado(p_contrato_id uuid,p_cierre_id uuid)
returns text language sql stable security definer set search_path='' as $function$
  select origen from crm.origenes_capital_confirmados
  where activo and ((contrato_id=p_contrato_id and p_cierre_id is null)
    or (cierre_externo_id=p_cierre_id and p_contrato_id is null));
$function$;
alter function private.ranking_origen_confirmado(uuid,uuid) owner to postgres;
revoke all on function private.ranking_origen_confirmado(uuid,uuid) from public,anon,authenticated,service_role;
comment on function private.ranking_origen_confirmado(uuid,uuid) is
'Lector privado de confirmacion por fuente exacta. Solo se usa como ultimo recurso tras leads, acreditaciones y cartera; no modifica la conversion.';

do $lector$
declare
  v_def text:=pg_get_functiondef('private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure);
  v_cambio text[];
begin
  foreach v_cambio slice 1 in array array[
    array[
      E'        when private.ranking_solicitud_cartera(c.id, null::uuid) then ''cartera''\n        else ''sin_origen''',
      E'        when private.ranking_solicitud_cartera(c.id, null::uuid) then ''cartera''\n        else coalesce(private.ranking_origen_confirmado(c.id,null::uuid),''sin_origen'')'
    ],
    array[
      E'        when private.ranking_solicitud_cartera(null::uuid, ce.id) then ''cartera''\n        else ''sin_origen'' end as origen',
      E'        when private.ranking_solicitud_cartera(null::uuid, ce.id) then ''cartera''\n        else coalesce(private.ranking_origen_confirmado(null::uuid,ce.id),''sin_origen'') end as origen'
    ]
  ] loop
    if (length(v_def)-length(replace(v_def,v_cambio[1],'')))/length(v_cambio[1])<>1 then
      raise exception 'Preflight: fallback de origen no coincide';
    end if;
    v_def:=replace(v_def,v_cambio[1],v_cambio[2]);
  end loop;
  execute v_def;
end;
$lector$;
