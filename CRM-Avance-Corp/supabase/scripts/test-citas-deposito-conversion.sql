\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database()<>'citas_integracion_20260908' then
    raise exception 'Solo banco local aislado de Citas';
  end if;
end $$;
set local session_replication_role=replica;
insert into public.perfiles(id,nombre_completo,rol,activo)
values ('86000000-0000-4000-8000-000000000001','GERENCIA DE PRUEBA','comercial',true),
       ('86000000-0000-4000-8000-000000000002','CLIENTE DE PRUEBA','cliente',true),
       ('86000000-0000-4000-8000-000000000003','CLIENTE CON ACCESO INACTIVO','cliente',false);
insert into crm.equipo(perfil_id,rol_crm,activo)
values ('86000000-0000-4000-8000-000000000001','gerencia',true);
insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,perfil_id,convertido_en,activo)
select ('87000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'CONVERSIÓN '||n,'+5190000000'||n,20000,
  case when n=5 then 'nuevo' else 'convertido' end,
  case when n=4 then null when n=9 then '86000000-0000-4000-8000-000000000001'::uuid
    when n=10 then '86000000-0000-4000-8000-000000000003'::uuid else '86000000-0000-4000-8000-000000000002'::uuid end,
  case when n=6 then now()+interval '1 day' when n=2 then '2026-09-02 15:00+00'::timestamptz else '2026-09-05 15:00+00'::timestamptz end,
  n<>8
from generate_series(1,10) n;
insert into crm.tareas(lead_id,tipo,titulo,vence_en,modalidad_reunion,creado_en)
select ('87000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'reunion','Cita de prueba',
  case when n=7 then '2026-10-01 16:00+00'::timestamptz else '2026-09-01 16:00+00'::timestamptz end,
  'virtual','2026-08-31 15:00+00'::timestamptz from generate_series(1,10) n;
insert into crm.tareas(lead_id,tipo,titulo,vence_en,modalidad_reunion,creado_en)
values ('87000000-0000-4000-8000-000000000001','reunion','Otra cita del mismo lead','2026-09-03 16:00+00','virtual','2026-09-01 17:00+00');
insert into crm.cierres_avance_anulados(lead_id,motivo,anulado_por)
values ('87000000-0000-4000-8000-000000000003','Anulación de prueba','86000000-0000-4000-8000-000000000001');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-4000-8000-000000000001',true);
do $$ declare r jsonb; begin
  r:=crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');
  assert r->>'version'='2' and r->>'disponibilidad_depositos'='conversion_cliente','Contrato V2 de fuente confirmada por negocio';
  assert jsonb_array_length(r->'conversiones')=3,'Solo conversiones a cliente vigentes, dentro de la cohorte y hasta el corte';
  assert not exists(select 1 from jsonb_array_elements(r->'conversiones') c
    where c->>'lead_id'='87000000-0000-4000-8000-000000000009'),'Un perfil comercial no es un cliente';
  assert exists(select 1 from jsonb_array_elements(r->'conversiones') c
    where c->>'lead_id'='87000000-0000-4000-8000-000000000010'),'Inactivar el acceso del cliente no anula la conversión';
  assert (select count(*)=1 from jsonb_array_elements(r->'conversiones') c
    where c->>'lead_id'='87000000-0000-4000-8000-000000000001'),'Varias citas no duplican una conversión';
  assert (select (c->>'convertido_en')::timestamptz='2026-09-05 15:00+00' from jsonb_array_elements(r->'conversiones') c
    where c->>'lead_id'='87000000-0000-4000-8000-000000000001'),'Fecha exacta de conversión a cliente';
  assert not exists(select 1 from jsonb_array_elements(r->'conversiones') c where c ? 'monto' or c ? 'moneda'),
    'No transforma el monto estimado en un abono';
  -- Una conversión anterior a asistir sigue siendo un evento real; el flujo
  -- del frontend exige la secuencia temporal y no la contará en su etapa final.
  assert exists(select 1 from jsonb_array_elements(r->'conversiones') c
    where c->>'lead_id'='87000000-0000-4000-8000-000000000002'),'Conserva el evento para evaluar su fecha';
end $$;
reset role;
select 'CITAS_DEPOSITO_POR_CONVERSION_OK' as resultado;
rollback;
