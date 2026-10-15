-- Solo datos sintéticos; el llamante abre y revierte la transacción.
-- Banco local exclusivo de Coordinación. Todas las pruebas terminan con ROLLBACK.
do $banco$
begin
  if current_database() not like 'origen_f3_%' then
    raise exception 'Estas fixtures requieren un banco exclusivo de Formulario 3';
  end if;
  if exists(select 1 from auth.users where id::text like 'f6%0000-0000-0000-0000-00000000000%')
     or exists(select 1 from public.perfiles where dni in ('49500001','49600001','49600002','49500091','49500092','49500093','49500094','49500095','49500096','49500097'))
     or exists(select 1 from crm.leads where dni in ('49500001','49600001','49600002')
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
 ('f6000000-0000-0000-0000-000000000001'),
 ('f6000000-0000-0000-0000-000000000002'),
 ('f6000000-0000-0000-0000-000000000003'),
 ('f6000000-0000-0000-0000-000000000004'),
 ('f6000000-0000-0000-0000-000000000005'),
 ('f6000000-0000-0000-0000-000000000006'),
 ('f6000000-0000-0000-0000-000000000007');
insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo) values
 ('f6000000-0000-0000-0000-000000000001','Prueba vendedor uno','comercial','DNI','49500091',true),
 ('f6000000-0000-0000-0000-000000000002','Prueba gerencia','comercial','DNI','49500092',true),
 ('f6000000-0000-0000-0000-000000000003','Prueba supervisor','comercial','DNI','49500093',true),
 ('f6000000-0000-0000-0000-000000000004','Prueba vendedor externo','comercial','DNI','49500094',true),
 ('f6000000-0000-0000-0000-000000000005','Prueba supervisor externo','comercial','DNI','49500095',true),
 ('f6000000-0000-0000-0000-000000000006','Prueba coordinador','comercial','DNI','49500096',true),
 ('f6000000-0000-0000-0000-000000000007','Prueba inactivo','comercial','DNI','49500097',true);
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo,creado_por) values
 ('f6000000-0000-0000-0000-000000000003','supervisor',null,true,'f6000000-0000-0000-0000-000000000003'),
 ('f6000000-0000-0000-0000-000000000001','vendedor','f6000000-0000-0000-0000-000000000003',true,'f6000000-0000-0000-0000-000000000003'),
 ('f6000000-0000-0000-0000-000000000005','supervisor',null,true,'f6000000-0000-0000-0000-000000000005'),
 ('f6000000-0000-0000-0000-000000000004','vendedor','f6000000-0000-0000-0000-000000000005',true,'f6000000-0000-0000-0000-000000000004'),
 ('f6000000-0000-0000-0000-000000000006','coordinador',null,true,'f6000000-0000-0000-0000-000000000006'),
 ('f6000000-0000-0000-0000-000000000007','gerencia',null,false,'f6000000-0000-0000-0000-000000000007'),
 ('f6000000-0000-0000-0000-000000000002','gerencia',null,true,'f6000000-0000-0000-0000-000000000002');
select set_config('crm.op_privilegiada','off',true);

insert into auth.users(id) values ('f6000000-0000-0000-0000-000000000008');
insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo)
values('f6000000-0000-0000-0000-000000000008','Prueba Directorio','directorio','DNI','49500098',true);


create function pg_temp.exigir(condicion boolean, mensaje text) returns void
language plpgsql as $$ begin
  if condicion is distinct from true then raise exception 'FAIL: %', mensaje; end if;
  raise notice 'PASS: %', mensaje;
end $$;
