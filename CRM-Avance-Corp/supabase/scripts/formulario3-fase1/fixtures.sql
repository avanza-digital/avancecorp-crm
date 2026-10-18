-- Solo datos sintéticos; el llamante abre y revierte la transacción.
-- La guarda remota solo la establece branch-prueba.py, cuyo destino es fijo.
do $banco$
begin
  if current_database() not like 'formulario3_fase1_%'
     and coalesce(current_setting('prueba.formulario3.branch',true),'')<>'sdgqkuejylkeqabpplyk' then
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
