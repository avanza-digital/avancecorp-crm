-- Oraculo transaccional de SLA versionado.
-- Exito: SLA_VERSIONADO_TX_OK. Todo queda en rollback.

begin;

insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
  ('72000000-0000-4000-8000-000000000001','authenticated','authenticated','sla-g@test.invalid',now(),'{}','{}',now(),now()),
  ('72000000-0000-4000-8000-000000000002','authenticated','authenticated','sla-s@test.invalid',now(),'{}','{}',now(),now()),
  ('72000000-0000-4000-8000-000000000003','authenticated','authenticated','sla-v1@test.invalid',now(),'{}','{}',now(),now()),
  ('72000000-0000-4000-8000-000000000004','authenticated','authenticated','sla-v2@test.invalid',now(),'{}','{}',now(),now()),
  ('72000000-0000-4000-8000-000000000005','authenticated','authenticated','sla-d@test.invalid',now(),'{}','{}',now(),now()),
  ('72000000-0000-4000-8000-000000000006','authenticated','authenticated','sla-sa@test.invalid',now(),'{}','{}',now(),now()),
  ('72000000-0000-4000-8000-000000000007','authenticated','authenticated','sla-a@test.invalid',now(),'{}','{}',now(),now());

insert into public.perfiles(id,nombre_completo,correo,rol,activo) values
  ('72000000-0000-4000-8000-000000000001','SLA Gerencia','sla-g@test.invalid','superadmin',true),
  ('72000000-0000-4000-8000-000000000002','SLA Supervisor','sla-s@test.invalid','comercial',true),
  ('72000000-0000-4000-8000-000000000003','SLA Vendedor Uno','sla-v1@test.invalid','comercial',true),
  ('72000000-0000-4000-8000-000000000004','SLA Vendedor Dos','sla-v2@test.invalid','comercial',true),
  ('72000000-0000-4000-8000-000000000005','SLA Directorio','sla-d@test.invalid','directorio',true),
  ('72000000-0000-4000-8000-000000000006','SLA Superadmin','sla-sa@test.invalid','superadmin',true),
  ('72000000-0000-4000-8000-000000000007','SLA Admin','sla-a@test.invalid','admin',true);

-- Membresía residual/preexistente deliberada, sembrada por debajo del trigger:
-- nunca debe devolver autoridad ni disponibilidad comercial efectiva.
set local session_replication_role=replica;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values
  ('72000000-0000-4000-8000-000000000001','gerencia',null,true),
  ('72000000-0000-4000-8000-000000000002','supervisor',null,true),
  ('72000000-0000-4000-8000-000000000003','vendedor','72000000-0000-4000-8000-000000000002',true),
  ('72000000-0000-4000-8000-000000000004','vendedor','72000000-0000-4000-8000-000000000002',true),
  ('72000000-0000-4000-8000-000000000006','vendedor','72000000-0000-4000-8000-000000000002',true);
set local session_replication_role=origin;

-- Lead inicial: nace bajo la politica seed v1.
select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000003',true);
insert into crm.leads(
  id,nombre_completo,telefono,origen,etapa,monto_estimado,moneda,categoria_interes,
  vendedor_id,creado_por
) values (
  '72000000-0000-4000-8000-000000000101','Lead SLA Uno','51999007201','otro','nuevo',
  10000,'PEN','nuevo','72000000-0000-4000-8000-000000000003',
  '72000000-0000-4000-8000-000000000003'
);

do $test$
begin
  if (select p.version from crm.lead_sla_ciclos c join crm.sla_politicas p on p.id=c.politica_id
      where c.lead_id='72000000-0000-4000-8000-000000000101')<>1
     or (select count(*) from crm.lead_asignaciones
      where lead_id='72000000-0000-4000-8000-000000000101'
        and sla_politica_asignacion_id=(select id from crm.sla_politicas where version=1))<>1
     or (select count(*) from crm.lead_asignacion_sla_hitos h
      join crm.lead_asignaciones a on a.id=h.lead_asignacion_id
      where a.lead_id='72000000-0000-4000-8000-000000000101')<>1
     or (select count(*) from crm.lead_sla_etapas
      where lead_id='72000000-0000-4000-8000-000000000101' and etapa='nuevo' and finalizado_en is null)<>1 then
    raise exception 'S01 no fotografio ciclo/asignacion/etapa v1';
  end if;
end;
$test$;

-- No contestada = gestion, no contacto y no avanza etapa.
set local role authenticated;
insert into crm.actividades(lead_id,tipo,detalle,creado_por) values(
  '72000000-0000-4000-8000-000000000101','llamada_no_contestada','Sin respuesta',
  '72000000-0000-4000-8000-000000000003'
);
reset role;
do $test$
begin
  if not exists(select 1 from crm.lead_sla_ciclos
      where lead_id='72000000-0000-4000-8000-000000000101'
        and primera_gestion_en is not null and primer_contacto_en is null)
     or not exists(select 1 from crm.lead_asignacion_sla_hitos h
       join crm.lead_asignaciones a on a.id=h.lead_asignacion_id
       where a.lead_id='72000000-0000-4000-8000-000000000101'
         and h.primera_gestion_en is not null and h.primer_contacto_en is null)
     or (select etapa from crm.leads where id='72000000-0000-4000-8000-000000000101')<>'nuevo' then
    raise exception 'S02 confundio intento con contacto efectivo';
  end if;
end;
$test$;

-- WhatsApp recibido = contacto efectivo y avance estructurado a contactado.
set local role authenticated;
insert into crm.actividades(lead_id,tipo,detalle,creado_por) values(
  '72000000-0000-4000-8000-000000000101','whatsapp_recibido','Respondio',
  '72000000-0000-4000-8000-000000000003'
);
reset role;
do $test$
begin
  if not exists(select 1 from crm.lead_sla_ciclos
      where lead_id='72000000-0000-4000-8000-000000000101' and primer_contacto_en is not null)
     or not exists(select 1 from crm.lead_sla_etapas
      where lead_id='72000000-0000-4000-8000-000000000101'
        and etapa='nuevo' and finalizado_en is not null)
     or not exists(select 1 from crm.lead_sla_etapas
      where lead_id='72000000-0000-4000-8000-000000000101'
        and etapa='contactado' and finalizado_en is null) then
    raise exception 'S03 contacto no sello/avanzo episodios';
  end if;
end;
$test$;

-- Gerencia publica v2.
select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $test$
declare v_cfg jsonb:=jsonb_build_object(
  'zona_horaria','America/Lima','tipo_reloj','corrido',
  'primera_gestion_minutos',10,'primer_contacto_minutos',20,
  'etapas',jsonb_build_array(
    jsonb_build_object('etapa','nuevo','maximo_minutos',30),
    jsonb_build_object('etapa','contactado','maximo_minutos',40),
    jsonb_build_object('etapa','reunion_agendada','maximo_minutos',50),
    jsonb_build_object('etapa','propuesta_enviada','maximo_minutos',60)
  ));
begin
  perform * from crm.publicar_politica_sla(1,null,v_cfg);
  begin
    perform * from crm.publicar_politica_sla(1,null,v_cfg);
    raise exception 'S04 acepto expected_version obsoleta';
  exception when serialization_failure then null;
  end;
end;
$test$;
reset role;

-- Incluso service_role/owner pasa por el trigger: una tarea pendiente sin lead
-- no puede quedar asignada a una membresía cruda enmascarada.
do $test$
begin
  begin
    insert into crm.tareas(
      perfil_id,vendedor_id,tipo,titulo,vence_en,creado_por
    ) values (
      '72000000-0000-4000-8000-000000000007',
      '72000000-0000-4000-8000-000000000006',
      'tarea','Destino Superadmin residual',
      timestamptz '2099-08-01 10:00:00-05',
      '72000000-0000-4000-8000-000000000001'
    );
    raise exception 'S04b permitio tarea pendiente hacia Superadmin residual';
  exception when check_violation then null;
  end;
end;
$test$;

-- Un lead posterior nace enteramente bajo v2; el anterior conserva v1.
insert into crm.leads(
  id,nombre_completo,telefono,origen,etapa,monto_estimado,moneda,categoria_interes,
  vendedor_id,creado_por
) values (
  '72000000-0000-4000-8000-000000000102','Lead SLA Dos','51999007202','otro','nuevo',
  12000,'USD','upgrade','72000000-0000-4000-8000-000000000003',
  '72000000-0000-4000-8000-000000000003'
);
do $test$
begin
  if (select p.version from crm.lead_sla_ciclos c join crm.sla_politicas p on p.id=c.politica_id
      where c.lead_id='72000000-0000-4000-8000-000000000102')<>2
     or (select p.version from crm.lead_sla_ciclos c join crm.sla_politicas p on p.id=c.politica_id
      where c.lead_id='72000000-0000-4000-8000-000000000101')<>1 then
    raise exception 'S05 una publicacion reescribio historia o no rigio nuevos ciclos';
  end if;
end;
$test$;

-- Publica v3; transferencia usa v3, pero ciclo existente sigue v2.
set local role authenticated;
do $test$
declare v_cfg jsonb:=jsonb_build_object(
  'zona_horaria','America/Lima','tipo_reloj','corrido',
  'primera_gestion_minutos',15,'primer_contacto_minutos',25,
  'etapas',jsonb_build_array(
    jsonb_build_object('etapa','nuevo','maximo_minutos',35),
    jsonb_build_object('etapa','contactado','maximo_minutos',45),
    jsonb_build_object('etapa','reunion_agendada','maximo_minutos',55),
    jsonb_build_object('etapa','propuesta_enviada','maximo_minutos',65)
  ));
begin
  perform * from crm.publicar_politica_sla(2,null,v_cfg);
end;
$test$;
reset role;

update crm.leads set vendedor_id='72000000-0000-4000-8000-000000000004'
where id='72000000-0000-4000-8000-000000000102';
update crm.leads set etapa='contactado'
where id='72000000-0000-4000-8000-000000000102';

do $test$
begin
  if (select p.version from crm.lead_sla_ciclos c join crm.sla_politicas p on p.id=c.politica_id
      where c.lead_id='72000000-0000-4000-8000-000000000102')<>2
     or (select p.version from crm.lead_asignaciones a join crm.sla_politicas p
      on p.id=a.sla_politica_asignacion_id
      where a.lead_id='72000000-0000-4000-8000-000000000102'
      order by a.episodio_n desc limit 1)<>3
     or (select p.version from crm.lead_sla_etapas e join crm.sla_politicas p on p.id=e.politica_id
      where e.lead_id='72000000-0000-4000-8000-000000000102'
        and e.finalizado_en is null)<>3 then
    raise exception 'S06 snapshots de ciclo/asignacion/etapa no son independientes';
  end if;
end;
$test$;

-- Reapertura crea ciclo 2 con politica v3; el ciclo 1 permanece.
update crm.leads set etapa='descartado',motivo_descarte='otro'
where id='72000000-0000-4000-8000-000000000102';
update crm.leads set etapa='nuevo',motivo_descarte=null
where id='72000000-0000-4000-8000-000000000102';
do $test$
begin
  if (select count(*) from crm.lead_sla_ciclos
      where lead_id='72000000-0000-4000-8000-000000000102')<>2
     or (select p.version from crm.lead_sla_ciclos c join crm.sla_politicas p on p.id=c.politica_id
       where c.lead_id='72000000-0000-4000-8000-000000000102' and c.ciclo_n=2)<>3 then
    raise exception 'S07 reapertura no creo nuevo ciclo versionado';
  end if;
end;
$test$;

-- Config y metricas: nombres genericos y publicador visible.
set local role authenticated;
do $test$
declare v_c jsonb; v_m jsonb; v_d jsonb;
begin
  v_c:=crm.configuracion_sla_fn();
  v_m:=crm.metricas_sla_fn(current_date,current_date);
  v_d:=crm.metricas_distribucion_leads_v2_fn(current_date,current_date);
  if (v_c->>'expected_version')::int<>3
     or lower(v_c#>>'{politica,publicada_por_nombre}')<>'sla gerencia'
     or v_c#>>'{politica,publicada_por}'<>'72000000-0000-4000-8000-000000000001'
     or (v_c->>'puede_editar')::boolean is distinct from true
     or not (v_m ? 'ciclos') or not (v_m ? 'asignaciones') or not (v_m ? 'etapas')
     or v_m::text like '%en_24h%' then
    raise exception 'S08 configuracion/metricas fuera de contrato generico';
  end if;
  if not exists(
    select 1
    from jsonb_array_elements(v_d->'analistas') as a(elemento)
    where a.elemento->>'analista_id'='72000000-0000-4000-8000-000000000006'
      and (a.elemento->>'activo')::boolean is false
      and (a.elemento->>'disponible_para_recibir')::boolean is false
  ) then
    raise exception 'S08a Superadmin residual quedo activo/disponible en distribucion';
  end if;
  if not exists(
    select 1 from jsonb_array_elements(v_m#>'{asignaciones,primera_gestion}') x
    where (x.value->>'politica_version')::integer=2
      and (x.value->>'fuera_objetivo')::integer=1
      and (x.value->>'pendientes')::integer=0
  ) then
    raise exception 'S08b asignacion cerrada sin gestion quedo pendiente';
  end if;
  if (v_d->>'version')::integer<>2
     or (v_d->'cohorte') ?| array['criterio_sla_global','politica_pausas']
     or (v_d->'alcances') ?| array['operacion_sla','sla_principal','sla_operativo']
     or (v_d->'resumen') ?| array[
       'sla_evaluables','sla_en_24h','sla_global_ciclos_cohorte',
       'sla_global_leads_unicos_cohorte','sla_global_contactos',
       'sla_global_evaluables','sla_global_en_24h',
       'primer_contacto_global_mediana_minutos',
       'sla_global_sin_contacto_vencidos_actuales'
     ]
     or not (v_d->'resumen' ? 'reasignaciones_cohorte')
     or exists(
       select 1
       from jsonb_array_elements(v_d->'analistas') as a(elemento)
       where (a.elemento->'operacion') ?| array[
         'contactos','contactos_asignacion','sla_evaluables','sla_en_24h',
         'sla_asignacion_evaluables','sla_asignacion_en_24h',
         'primer_contacto_mediana_minutos',
         'primer_contacto_asignacion_mediana_minutos','estancados_actual'
       ]
          or not ((a.elemento->'operacion') ?& array[
            'cohorte_episodios','transferidos','parqueados','desactivados',
            'sin_tocar_actual'
          ])
     )
     or (v_d->'calidad') ? 'ciclos_sla_global_aproximados_cohorte' then
    raise exception 'S08c distribucion V2 aun mezcla el SLA fijo retirado';
  end if;
  if (select count(*) from crm.estado_sla_leads_fn())<>2
     or not exists(
       select 1 from crm.estado_sla_leads_fn() e
       where e.lead_id='72000000-0000-4000-8000-000000000101'
         and e.ciclo_politica_version=1
         and e.asignacion_politica_version=1
         and e.etapa_politica_version=1
         and e.etapa='contactado'
     )
     or not exists(
       select 1 from crm.estado_sla_leads_fn() e
       where e.lead_id='72000000-0000-4000-8000-000000000102'
         and e.ciclo_politica_version=3
         and e.asignacion_politica_version=3
         and e.etapa_politica_version=3
         and e.etapa='nuevo'
     ) then
    raise exception 'S08d estado vivo no conserva fotografias independientes';
  end if;
end;
$test$;
reset role;

-- El estado vivo conserva exactamente el mismo ambito que crm.leads.
select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.estado_sla_leads_fn())<>1
     or not exists(
       select 1 from crm.estado_sla_leads_fn()
       where lead_id='72000000-0000-4000-8000-000000000101'
     ) then
    raise exception 'S08e vendedor obtuvo estado SLA fuera de su cartera';
  end if;
end;
$test$;
reset role;

-- Directorio lee y no publica.
select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000005',true);
set local role authenticated;
do $test$
declare v_c jsonb; v_m jsonb; v_d jsonb;
begin
  v_c:=crm.configuracion_sla_fn();
  v_m:=crm.metricas_sla_fn(current_date,current_date);
  v_d:=crm.metricas_distribucion_leads_v2_fn(current_date,current_date);
  if (v_c->>'puede_editar')::boolean is distinct from false
     or not (v_m ? 'ciclos')
     or (v_d->>'version')::integer<>2 then
    raise exception 'S09 Directorio no quedo solo lectura';
  end if;
  if (select count(*) from crm.estado_sla_leads_fn())<>2 then
    raise exception 'S09b Directorio no ve el estado SLA global';
  end if;
  begin
    perform * from crm.publicar_politica_sla(3,null,'{}');
    raise exception 'S10 Directorio publico SLA';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Superadmin Portal sin Gerencia solo gobierna roles. No obtiene SLA,
-- distribucion ni lectura global por su rol del Portal.
select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000006',true);
set local role authenticated;
do $test$
begin
  if private.rol_crm('72000000-0000-4000-8000-000000000006') is not null
     or (select count(*) from crm.sla_politicas)<>0
     or (select count(*) from crm.sla_politica_etapas)<>0 then
    raise exception 'S10b Superadmin puro leyo tablas SLA';
  end if;
  begin
    perform crm.configuracion_sla_fn();
    raise exception 'S10c Superadmin puro obtuvo configuracion SLA';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_sla_fn(current_date,current_date);
    raise exception 'S10d Superadmin puro obtuvo metricas SLA';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from crm.estado_sla_leads_fn();
    raise exception 'S10e Superadmin puro obtuvo estado SLA';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_distribucion_leads_v2_fn(current_date,current_date);
    raise exception 'S10f Superadmin puro obtuvo distribucion';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from crm.publicar_politica_sla(3,null,'{}');
    raise exception 'S10g Superadmin puro publico SLA';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Admin Portal no recibe capacidades CRM implicitas.
select set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000007',true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.sla_politicas)<>0
     or (select count(*) from crm.sla_politica_etapas)<>0 then
    raise exception 'S10h Admin Portal leyo tablas SLA';
  end if;
  begin
    perform crm.configuracion_sla_fn();
    raise exception 'S10i Admin Portal obtuvo configuracion SLA';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_sla_fn(current_date,current_date);
    raise exception 'S10j Admin Portal obtuvo metricas SLA';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from crm.estado_sla_leads_fn();
    raise exception 'S10k Admin Portal obtuvo estado SLA';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.metricas_distribucion_leads_v2_fn(current_date,current_date);
    raise exception 'S10l Admin Portal obtuvo distribucion';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from crm.publicar_politica_sla(3,null,'{}');
    raise exception 'S10m Admin Portal publico SLA';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Inmutabilidad/ACL estructural.
do $test$
begin
  begin
    update crm.sla_politicas set primera_gestion_minutos=1 where version=1;
    raise exception 'S11 permitio mutar politica historica';
  exception when object_not_in_prerequisite_state then null;
  end;
  if has_function_privilege('anon','crm.publicar_politica_sla(integer,timestamp with time zone,jsonb)','execute')
     or has_function_privilege('anon','crm.estado_sla_leads_fn()','execute')
     or has_function_privilege('anon','crm.metricas_distribucion_leads_v2_fn(date,date)','execute')
     or has_function_privilege('service_role','crm.metricas_distribucion_leads_v2_fn(date,date)','execute')
     or not has_function_privilege('authenticated','crm.metricas_distribucion_leads_v2_fn(date,date)','execute')
     or has_function_privilege('authenticated','private.metricas_distribucion_leads_autorizada(date,date,smallint)','execute')
     or has_table_privilege('authenticated','crm.lead_sla_ciclos','select')
     or has_table_privilege('authenticated','crm.lead_asignacion_sla_hitos','select')
     or has_table_privilege('authenticated','crm.sla_politicas','insert,update,delete') then
    raise exception 'S12 ACL SLA incorrecta';
  end if;
  if not exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    join pg_roles r on r.oid=p.proowner
    where n.nspname='crm'
      and p.proname='metricas_distribucion_leads_v2_fn'
      and pg_get_function_identity_arguments(p.oid)='p_desde date, p_hasta date'
      and r.rolname='crm_metricas_bridge'
      and p.prosecdef
  ) then
    raise exception 'S12c RPC distribucion V2 perdio owner o SECURITY DEFINER';
  end if;
  if not exists(select 1 from pg_constraint
    where conrelid='crm.lead_sla_etapas'::regclass
      and conname='lead_sla_etapas_ciclo_fk' and contype='f') then
    raise exception 'S12b falta FK etapa a ciclo';
  end if;
  if not exists(select 1 from public.audit_log
    where tabla='crm.sla_politicas' and usuario_id='72000000-0000-4000-8000-000000000001') then
    raise exception 'S13 publicaciones SLA sin auditoria';
  end if;
end;
$test$;

select 'SLA_VERSIONADO_TX_OK' as resultado;
rollback;
