-- Solo datos sintéticos; el llamante abre y revierte la transacción.
-- Banco local exclusivo de fase 2. Todas las pruebas terminan con ROLLBACK.
do $banco$
begin
  if current_database() not like 'formulario3_fase2_%' then
    raise exception 'Estas fixtures requieren un banco exclusivo de Formulario 3';
  end if;
  if exists(select 1 from auth.users where id::text like 'f3%0000-0000-0000-0000-00000000000%')
     or exists(select 1 from public.perfiles where dni in ('49100001','49200001','49200002','49100091','49100092','49100093','49100094','49100095','49100096','49100097'))
     or exists(select 1 from crm.leads where dni in ('49100001','49200001','49200002')
       or regexp_replace(telefono,'[^0-9]','','g') ~ '^(51)?98[123]0000(0[1-7]|99)$') then
    raise exception 'Colisión de fixtures; no se tocarán contactos existentes';
  end if;
end;
$banco$;
insert into crm.conversion_pesos(vigente_desde,peso_referido,nota)
select '2026-01-01',0.15,'Fixture local de campaña'
where not exists(select 1 from crm.conversion_pesos);
with p as (
  insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
  select 1,'-infinity','America/Lima','corrido',1440,1440
  where not exists(select 1 from crm.sla_politicas) returning id
)
insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
select p.id,x.etapa,x.minutos from p cross join (values
  ('nuevo',1440),('contactado',4320),('reunion_agendada',4320),('propuesta_enviada',7200)
) x(etapa,minutos);
insert into crm.multiempresa_flags(nombre,activo) values ('resolver_en_puertas',false),('inversiones_escritura',false)
on conflict(nombre) do update set activo=false;
select set_config('crm.op_privilegiada','on',true);
insert into auth.users(id) values
 ('f3000000-0000-0000-0000-000000000001'),
 ('f3000000-0000-0000-0000-000000000002'),
 ('f3000000-0000-0000-0000-000000000003'),
 ('f3000000-0000-0000-0000-000000000004'),
 ('f3000000-0000-0000-0000-000000000005'),
 ('f3000000-0000-0000-0000-000000000006'),
 ('f3000000-0000-0000-0000-000000000007');
insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo) values
 ('f3000000-0000-0000-0000-000000000001','Prueba vendedor uno','comercial','DNI','49100091',true),
 ('f3000000-0000-0000-0000-000000000002','Prueba gerencia','comercial','DNI','49100092',true),
 ('f3000000-0000-0000-0000-000000000003','Prueba supervisor','comercial','DNI','49100093',true),
 ('f3000000-0000-0000-0000-000000000004','Prueba vendedor externo','comercial','DNI','49100094',true),
 ('f3000000-0000-0000-0000-000000000005','Prueba supervisor externo','comercial','DNI','49100095',true),
 ('f3000000-0000-0000-0000-000000000006','Prueba coordinador','comercial','DNI','49100096',true),
 ('f3000000-0000-0000-0000-000000000007','Prueba inactivo','comercial','DNI','49100097',true);
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo,creado_por) values
 ('f3000000-0000-0000-0000-000000000003','supervisor',null,true,'f3000000-0000-0000-0000-000000000003'),
 ('f3000000-0000-0000-0000-000000000001','vendedor','f3000000-0000-0000-0000-000000000003',true,'f3000000-0000-0000-0000-000000000003'),
 ('f3000000-0000-0000-0000-000000000005','supervisor',null,true,'f3000000-0000-0000-0000-000000000005'),
 ('f3000000-0000-0000-0000-000000000004','vendedor','f3000000-0000-0000-0000-000000000005',true,'f3000000-0000-0000-0000-000000000004'),
 ('f3000000-0000-0000-0000-000000000006','coordinador',null,true,'f3000000-0000-0000-0000-000000000006'),
 ('f3000000-0000-0000-0000-000000000007','gerencia',null,false,'f3000000-0000-0000-0000-000000000007'),
 ('f3000000-0000-0000-0000-000000000002','gerencia',null,true,'f3000000-0000-0000-0000-000000000002');
select set_config('crm.op_privilegiada','off',true);

insert into auth.users(id) values ('f3000000-0000-0000-0000-000000000008');
insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo)
values('f3000000-0000-0000-0000-000000000008','Prueba Directorio','directorio','DNI','49100098',true);

-- 60 históricos antes de la primera campaña: filtrar la página descargada fallaría.
insert into crm.leads(id,nombre_completo,telefono,origen,campania_origen,monto_estimado,moneda,vendedor_id)
select ('f3200000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'F3 FASE2 '||lpad(i::text,3,'0'), '98400'||lpad(i::text,4,'0'), 'formulario',
 case when i<=60 then null when i<=130 or i>=136 then 'Formulario 3' else 'Campaña anterior' end,
 1000,case when i%2=0 then 'USD' else 'PEN' end,
 case when i<=135 then 'f3000000-0000-0000-0000-000000000001'::uuid
 else 'f3000000-0000-0000-0000-000000000004'::uuid end
from generate_series(1,144) i;
