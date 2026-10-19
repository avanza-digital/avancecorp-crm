-- Correcciones del PR #331. Captura sin acreditar ciclos ausentes y locks de evidencia.
-- No modifica modos, cortes, permisos, hechos históricos ni las migraciones anteriores.
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$ begin
  if md5(pg_get_functiondef('private.recorrido_capturar_actividad()'::regprocedure))<>'8d70961c89b675abee174944c5a33b50'
    or md5(pg_get_functiondef('private.recorrido_serializar_invalidacion()'::regprocedure))<>'befde73f1aafd2079af8ff67d85969b8' then
    raise exception 'Cambio el contrato del recorrido; revisar antes de aplicar la correccion' using errcode='55000';
  end if;
  perform private.assert_sla_nucleo();
end $$;

alter table crm.actividad_ciclo_contexto
  drop constraint actividad_ciclo_contexto_estado_ciclo_check,
  drop constraint actividad_ciclo_contexto_check1,
  add constraint actividad_ciclo_contexto_estado_ciclo_check
    check (estado_ciclo in ('ciclo','base_sin_ciclo','sin_ciclo')),
  add constraint actividad_ciclo_contexto_check1
    check ((estado_ciclo='ciclo' and ciclo_n is not null)
      or (estado_ciclo in ('base_sin_ciclo','sin_ciclo') and ciclo_n is null));

-- Registrar gestión no exige fabricar ni reparar un ciclo. La captura sin ciclo
-- permanece inmutable y nunca se reasigna por fecha o por un ciclo añadido después.
-- El evaluador excluye ciclo_n NULL; la conversión conserva su guard y cohorte.
create or replace function private.recorrido_capturar_actividad() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  v_estado text:='ciclo'; v_ciclo integer; v_hora timestamptz; v_lead crm.leads%rowtype;
  v_writer text:=coalesce(current_setting('crm.recorrido_contexto_writer',true),'off');
  v_oficina jsonb; v_gesto uuid; v_tarea uuid;
begin
  select * into strict v_lead from crm.leads where id=new.lead_id for update;
  v_ciclo:=v_lead.ciclo_actual;
  v_hora:=clock_timestamp();
  if not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id and c.ciclo_n=v_ciclo) then
    if v_lead.origen='base_cargada' and v_lead.etapa='descartado'
      and v_lead.motivo_descarte='base_cargada' and v_lead.activo
      and not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id) then
      v_estado:='base_sin_ciclo';
    else
      v_estado:='sin_ciclo';
    end if;
    v_ciclo:=null;
  end if;
  v_oficina:=nullif(current_setting('crm.recorrido_oficina',true),'')::jsonb;
  if new.tipo='reunion_realizada' and v_oficina#>>'{payload,lead_id}'=new.lead_id::text
    and v_oficina#>>'{payload,tarea_id}'=new.metadata->>'tarea_id'
    and v_oficina->>'clave'='recorrido_oficina:'||(select auth.uid())::text||':'||(v_oficina->>'operacion_id')
    and exists(select 1 from crm.multiempresa_idempotencia m
      where m.clave=v_oficina->>'clave' and m.tipo='recorrido_oficina'
        and m.creado_por=(select auth.uid()) and m.resultado is null
        and m.hash_payload=private.idem_hash(v_oficina->'payload')) then
    v_gesto:=(v_oficina->>'operacion_id')::uuid;
    v_tarea:=(v_oficina#>>'{payload,tarea_id}')::uuid;
  end if;
  perform set_config('crm.recorrido_contexto_writer','on',true);
  insert into crm.actividad_ciclo_contexto(actividad_id,lead_id,ciclo_n,estado_ciclo,registrado_en,gesto_oficina_id,oficina_tarea_id)
    values(new.id,new.lead_id,v_ciclo,v_estado,v_hora,v_gesto,v_tarea);
  perform set_config('crm.recorrido_contexto_writer',v_writer,true);
  return null;
end $$;

create or replace function private.recorrido_serializar_invalidacion() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_lead uuid:=old.lead_id; v_cambia boolean:=true;
begin
  if tg_op='UPDATE' then
    if new.lead_id is distinct from old.lead_id then
      raise exception 'La evidencia no cambia de lead' using errcode='23514';
    end if;
    -- Incluye TODO campo consumido por el evaluador, también tipo/ID/vence_en.
    -- confirmada_en, título o notas no cambian asistencia ni entrevista.
    if tg_table_name='tareas' then
      v_cambia:=row(new.id,new.tipo,new.estado,new.activo,new.vence_en,new.resultado_actividad_id,new.resultado_reunion)
        is distinct from row(old.id,old.tipo,old.estado,old.activo,old.vence_en,old.resultado_actividad_id,old.resultado_reunion);
    elsif tg_table_name='actividades' then
      v_cambia:=row(new.id,new.tipo,new.metadata,new.creado_en)
        is distinct from row(old.id,old.tipo,old.metadata,old.creado_en);
    end if;
  end if;
  if v_lead is not null and v_cambia then
    -- DELETE y cambios de evidencia conservan NOWAIT para evitar espera inversa.
    perform 1 from crm.leads where id=v_lead for update nowait;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;

revoke all on function private.recorrido_capturar_actividad(),private.recorrido_serializar_invalidacion()
  from public,anon,authenticated,service_role;
select private.assert_sla_nucleo();
commit;
