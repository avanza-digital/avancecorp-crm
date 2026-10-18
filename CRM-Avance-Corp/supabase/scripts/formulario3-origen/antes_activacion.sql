insert into private.agenda_reparto_destinos(supervisor_id,alias,orden) values
 ('f6000000-0000-0000-0000-000000000003','Prueba uno',8),
 ('f6000000-0000-0000-0000-000000000005','Prueba dos',9);
insert into private.agenda_reparto_diaria(fecha,origen,supervisor_id,creado_por,actualizado_por)
select (now() at time zone 'America/Lima')::date, origen, supervisor,
 'f6000000-0000-0000-0000-000000000006'::uuid,'f6000000-0000-0000-0000-000000000006'::uuid
from (values
 ('formulario','f6000000-0000-0000-0000-000000000003'::uuid),
 ('landing','f6000000-0000-0000-0000-000000000005'::uuid)
) a(origen,supervisor);
update crm.configuracion_reparto set coordinacion_libre=false where singleton;

insert into crm.leads(id,nombre_completo,telefono,origen,campania_origen,creado_en,
 monto_estimado,moneda,vendedor_id,asignado_supervisor_id,no_contactar,activo)
select ('f6100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'CONTACTO SINTETICO '||i, '98500'||lpad(i::text,4,'0'),
 case when i=3 then 'landing' when i=8 then 'referido' else 'formulario' end,
 case when i in (1,4,5,6,7) then 'Formulario 3' end,
 greatest(now()-interval '1 hour',timestamptz '2026-10-15 00:00:00-05'),
 1000,'PEN',case when i=4 then 'f6000000-0000-0000-0000-000000000001'::uuid end,
 case when i=7 then 'f6000000-0000-0000-0000-000000000003'::uuid end,
 i=5, i<>6 from generate_series(1,8) i;
insert into crm.actividades(lead_id,tipo,metadata,creado_por)
values('f6100000-0000-0000-0000-000000000004','nota','{"nota":"Historia sintética que debe conservarse"}',
 'f6000000-0000-0000-0000-000000000001');
insert into crm.tareas(lead_id,tipo,titulo,vence_en,vendedor_id,creado_por)
values('f6100000-0000-0000-0000-000000000004','llamada','Tarea que debe conservar titular y estado',now()+interval '1 day',
 'f6000000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000001');

-- Simula movimiento histórico real; el origen se proyectará, el evento no se reescribe.
insert into crm.actividades(lead_id,tipo,metadata,creado_por)
select ('f6100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'reasignacion',
 jsonb_build_object('movimiento','entra_bandeja','supervisor_nuevo','f6000000-0000-0000-0000-000000000003'),
 'f6000000-0000-0000-0000-000000000006' from unnest(array[2,4,7,8]) i;

set local role authenticated;
select set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000002',true);
select pg_temp.exigir((crm.cartera_filtrada_fn(p_origen=>'formulario_3')#>>'{resumen,totales,vivos}')::int=4,
 'A: el filtro F3 encuentra legados antes del backfill');
select pg_temp.exigir((crm.cartera_filtrada_fn(p_origen=>'formulario')#>>'{resumen,totales,vivos}')::int=1,
 'A: Formulario excluye el conjunto F3; filtros disjuntos');
reset role;
select set_config('request.jwt.claim.sub','',true);
