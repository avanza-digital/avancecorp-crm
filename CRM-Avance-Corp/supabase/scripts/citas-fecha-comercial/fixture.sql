-- Banco aislado: postestados sintéticos, lectores/núcleos/permisos reales.
-- La preparación omite triggers de escritura; no verifica los flujos de alta.
begin;
do $$ begin
 if current_database() not like 'citas_%' or exists(select 1 from auth.users) then
   raise exception 'Solo banco vacío de Citas';
 end if;
end $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
 select ('92000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
set local session_replication_role=replica;
insert into public.perfiles(id,nombre_completo,rol,activo)
select pg_temp.id(n),'Persona sintética '||n,case when n>=100 then 'cliente' else 'analista' end,true
from unnest(array[1,2,3,4,5,6,7,101,102,103,104,105,106]) n;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values
(pg_temp.id(1),'gerencia',null,true),(pg_temp.id(2),'supervisor',null,true),
(pg_temp.id(3),'vendedor',pg_temp.id(2),true),(pg_temp.id(4),'supervisor',null,true),
(pg_temp.id(5),'vendedor',pg_temp.id(4),true),(pg_temp.id(6),'coordinador',null,true),
(pg_temp.id(7),'supervisor',null,false);
insert into crm.conversion_politica(unica,activada_en,manifiesto_huella,resultado) values(true,now(),repeat('a',32),'{}');
insert into crm.control_citas_versiones(version,configuracion,guardado_por)
values(1,'{"mes_inicio":"2026-09","base_avance":"actividad_real","mes_resultado":"evento","base_depositos":"personas_entrevistadas","citas_por_lead":1.25,"actividad_manuales":"incluir","analista_resultado":"evento","conteo_entrevistas":"citas_realizadas","mostrar_meta_citas":false,"depositos_porcentaje":70,"excluir_manuales_base":false,"entrevistas_porcentaje":70}',pg_temp.id(1));
insert into crm.control_citas_aplicaciones(version,mes_inicio,aplicado_por) values(1,'2026-09-01',pg_temp.id(1));
create temp table casos as select n,pg_temp.id(100+n) cliente,pg_temp.id(200+n) lead,
 pg_temp.id(300+n) contrato,pg_temp.id(400+n) episodio,
 pg_temp.id(case when n=4 then 5 else 3 end) analista,
 case n when 1 then date '2026-09-01' when 2 then date '2026-09-05'
 when 3 then date '2026-09-14' when 4 then date '2026-09-21' else date '2026-10-01' end fecha,
 case when n=5 then '2026-10-01 23:59:00 America/Lima'::timestamptz
 when n=2 then '2026-10-02 09:00:00 America/Lima'::timestamptz
 when n=3 then '2026-09-15 09:00:00 America/Lima'::timestamptz
 else '2026-09-01 23:59:00 America/Lima'::timestamptz end asistencia
from generate_series(1,6) n;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
 fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,es_demo)
select contrato,'CITAS-SINTETICO-'||n,cliente,1000,'PEN','mensual',fecha,fecha+365,'nuevo',pg_temp.id(999),fecha,analista,false from casos;
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,vendedor_id,perfil_id,contrato_id,convertido_en,creado_en,activo,monto_estimado)
select lead,'Lead sintético '||n,'90000000'||n,'landing','convertido',analista,cliente,contrato,
 '2026-10-06 10:00:00 America/Lima','2026-08-01 10:00:00 America/Lima',true,1000 from casos;
insert into crm.lead_asignaciones(id,lead_id,ciclo_n,episodio_n,analista_id,motivo_apertura,asignado_en,moneda,origen,
 sla_global_iniciado_en,sla_politica_asignacion_id,primera_gestion_limite_en,primer_contacto_limite_en)
select episodio,lead,1,1,analista,'asignado','2026-09-01 08:00:00 America/Lima','PEN','landing',
 '2026-09-01 08:00:00 America/Lima',pg_temp.id(999),'2026-09-02 08:00:00 America/Lima','2026-09-02 08:00:00 America/Lima' from casos;
insert into crm.conversion_acreditaciones(lead_id,episodio_id,analista_id,origen,fuente_tipo,fuente_id,fecha_comercial,
 confirmado_en,vinculado_en,acreditado_en,periodo_comercial,plazo_hasta,estado,motivo)
select lead,episodio,analista,'landing','contrato',contrato,fecha,
 '2026-10-06 10:00:00 America/Lima','2026-10-06 10:00:00 America/Lima','2026-10-06 10:00:00 America/Lima',
 date_trunc('month',fecha)::date,'2026-12-31 23:59:59 America/Lima','acreditada','Evidencia sintética del banco' from casos where n<>6;
insert into crm.actividades(id,lead_id,tipo,creado_en)
select pg_temp.id(500+n),lead,'reunion_realizada',asistencia from casos;
insert into crm.tareas(id,lead_id,tipo,titulo,vendedor_id,vence_en,creado_en,estado,resultado_actividad_id,
 modalidad_reunion,resultado_reunion,activo,ubicacion_reunion)
select pg_temp.id(600+n),lead,'reunion','Cita sintética',analista,asistencia,'2026-09-01 08:00:00 America/Lima',
 'completada',pg_temp.id(500+n),'presencial','interesado',true,'Oficina sintética' from casos;
set local session_replication_role=origin;
commit;
