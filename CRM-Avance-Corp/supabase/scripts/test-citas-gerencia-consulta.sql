\set ON_ERROR_STOP on
-- Sólo base local aislada; todos los datos ficticios se revierten.
begin;
do $$ begin
  if current_database() <> 'citas_integracion_20260908' then
    raise exception 'Este ensayo sólo admite la base local aislada de Citas';
  end if;
end $$;
set local session_replication_role=replica;
insert into public.perfiles(id,nombre_completo,rol,activo)
select ('80000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'PRUEBA CITAS '||n,
  case when n in (4,7) then 'directorio' else 'comercial' end,true from generate_series(1,7) n;
insert into crm.equipo(perfil_id,rol_crm,activo)
select ('80000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case n when 2 then 'vendedor' when 3 then 'supervisor' when 4 then 'directorio' else 'gerencia' end,n<>6
from generate_series(1,7) n;
update public.perfiles set activo=false where id='80000000-0000-4000-8000-000000000005';
insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id)
values ('81000000-0000-4000-8000-000000000001','PERSONA DE AGOSTO','+51900000001',10000,'80000000-0000-4000-8000-000000000002'),
       ('81000000-0000-4000-8000-000000000002','PERSONA DE SEPTIEMBRE','+51900000002',10000,'80000000-0000-4000-8000-000000000002');
insert into crm.actividades(id,lead_id,tipo,creado_en)
values ('83000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','reunion_realizada','2026-09-02 16:30+00');
insert into crm.tareas(id,lead_id,vendedor_id,tipo,titulo,vence_en,estado,modalidad_reunion,motivo_no_realizada,creado_en)
values ('82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000002','reunion','Ausencia','2026-08-28 16:00+00','no_show','virtual','cliente_no_asistio','2026-08-27 15:00+00');
insert into crm.tareas(id,lead_id,vendedor_id,tipo,titulo,vence_en,estado,modalidad_reunion,resultado_reunion,reagendada_de,resultado_actividad_id,creado_en)
values ('82000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000002','reunion','Recuperada fuera del mes','2026-09-02 16:00+00','completada','virtual','interesado','82000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','2026-08-28 17:00+00');
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,estado,modalidad_reunion,reagendada_de,creado_en)
values ('82000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000002','reunion','No pertenece a la cohorte','2026-09-03 16:00+00','pendiente','virtual','82000000-0000-4000-8000-000000000001','2026-08-28 18:00+00');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000001',true);
do $$ declare r jsonb; begin
  r:=crm.citas_gerencia_consulta_fn('2026-08-01','2026-08-31');
  assert jsonb_array_length(r->'citas')=2,'Mes trae cohorte y seguimiento, sin otra persona';
  assert r->'citas'->1->>'reagendada_de'='82000000-0000-4000-8000-000000000001','Conserva el vínculo';
  assert (r->'citas'->1->>'asistencia_registrada_en')::timestamptz='2026-09-02 16:30+00','Asistencia viene del resultado vinculado';
  assert r->>'disponibilidad_depositos'='conversion_cliente' and r->'conversiones'='[]'::jsonb,'Sin conversiones no inventa depósitos';
  assert r->'citas'->0->>'vence_en' ~ '^2026-08-28T','JSON timestamptz usa ISO con T';
  r:=crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');
  assert r->'citas'->2->'reagendada_de'='null'::jsonb,'No permite enlaces entre leads distintos';
  r:=crm.citas_gerencia_consulta_fn('2026-07-01','2026-07-31');
  assert r->'citas'='[]'::jsonb,'Mes vacío es explícito';
  begin
    perform crm.citas_gerencia_consulta_fn('2026-08-02','2026-08-31');
    raise exception 'Aceptó un rango que no es mes';
  exception when sqlstate '22023' then null; end;
end $$;
do $$ declare n integer; begin
  for n in 2..7 loop
    perform set_config('request.jwt.claim.sub','80000000-0000-4000-8000-'||lpad(n::text,12,'0'),true);
    begin
      perform crm.citas_gerencia_consulta_fn('2026-08-01','2026-08-31');
      raise exception 'Autorizó actor que debía ser rechazado: %',n;
    exception when insufficient_privilege then null; end;
  end loop;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform crm.citas_gerencia_consulta_fn('2026-08-01','2026-08-31');
    raise exception 'Autorizó sin identidad';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert not has_function_privilege('anon','crm.citas_gerencia_consulta_fn(date,date)','execute'),'Anon no ejecuta';
  assert not has_function_privilege('anon','private.citas_gerencia_consulta(date,date)','execute'),'Anon no ejecuta el núcleo';
  assert has_function_privilege('authenticated','crm.citas_gerencia_consulta_fn(date,date)','execute'),'Autenticado tiene entrada con guardia interna';
end $$;
-- Cierre anterior al mes: el historial no debe marcarlo como abierto.
set local session_replication_role=replica;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,estado,modalidad_reunion,resultado_reunion,creado_en)
values ('82000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000001','reunion','Histórica con cierre','2026-08-15 16:00+00','completada','virtual','interesado','2026-08-14 16:00+00');
insert into crm.lead_asignaciones(lead_id,ciclo_n,episodio_n,analista_id,motivo_apertura,asignado_en,moneda,origen,
  finalizado_en,motivo_cierre,resultado,resultado_en,sla_global_iniciado_en,sla_politica_asignacion_id,primera_gestion_limite_en,primer_contacto_limite_en)
values ('81000000-0000-4000-8000-000000000001',1,1,'80000000-0000-4000-8000-000000000002','ingreso','2026-08-01 15:00+00','PEN','referido',
  '2026-08-20 15:00+00','convertido','convertido','2026-08-20 15:00+00','2026-08-01 15:00+00','85000000-0000-4000-8000-000000000001','2026-08-01 16:00+00','2026-08-01 17:00+00');
insert into crm.tareas(perfil_id,tipo,titulo,vence_en,estado,modalidad_reunion,creado_en)
values ('80000000-0000-4000-8000-000000000001','reunion','Postventa existente','2026-09-05 16:00+00','pendiente','virtual','2026-09-01 15:00+00'),
       ('80000000-0000-4000-8000-000000000001','reunion','Registro posterior al corte','2026-09-05 16:00+00','pendiente','virtual',now()+interval '1 day');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000001',true);
do $$ declare r jsonb; begin
  r:=crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');
  assert (select (c->>'cierre_posterior')::boolean from jsonb_array_elements(r->'citas') c
    where c->>'id'='82000000-0000-4000-8000-000000000004'),'Reconoce cierre previo al mes';
  assert (select not (c->>'cierre_posterior')::boolean from jsonb_array_elements(r->'citas') c
    where c->>'id'='82000000-0000-4000-8000-000000000002'),'Un cierre anterior a la cita no es posterior';
  assert (r->>'citas_clientes')::int=1,'Postventa cuenta citas existentes al corte, separadas de leads';
end $$;
reset role;
do $$ begin
  assert (select count(*)=5 from pg_attribute where attrelid='crm.leads'::regclass
    and attname in ('nombre_completo','telefono','origen','moneda','monto_estimado') and attnotnull),
    'Los campos obligatorios de la frontera están respaldados por NOT NULL';
end $$;

-- Límite completo: 10000 se entregan; 10001 falla sin publicar un subtotal.
set local session_replication_role=replica;
insert into crm.leads(id,nombre_completo,telefono,monto_estimado)
values ('81000000-0000-4000-8000-000000000003','PRUEBA DE VOLUMEN','+51900000003',1000);
insert into crm.tareas(lead_id,tipo,titulo,vence_en,modalidad_reunion,creado_en)
select '81000000-0000-4000-8000-000000000003','reunion','Volumen '||n,'2026-07-02 16:00+00'::timestamptz,'virtual','2026-07-01 16:00+00'::timestamptz
from generate_series(1,10000) n;
set local session_replication_role=origin;
set local role authenticated;
do $$ begin
  assert jsonb_array_length(crm.citas_gerencia_consulta_fn('2026-07-01','2026-07-31')->'citas')=10000,'Entrega el límite completo';
end $$;
reset role;
set local session_replication_role=replica;
insert into crm.tareas(lead_id,tipo,titulo,vence_en,modalidad_reunion,creado_en)
values ('81000000-0000-4000-8000-000000000003','reunion','Exceso','2026-07-02 16:00+00','virtual','2026-07-01 16:00+00');
set local session_replication_role=origin;
set local role authenticated;
do $$ begin
  begin
    perform crm.citas_gerencia_consulta_fn('2026-07-01','2026-07-31');
    raise exception 'Aceptó un historial truncado';
  exception when sqlstate '54000' then null; end;
end $$;
reset role;
select 'CITAS_GERENCIA_CONSULTA_OK' as resultado;
rollback;
