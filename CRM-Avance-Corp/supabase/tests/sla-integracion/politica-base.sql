-- Configuración histórica sintética inicial (migrador); ninguna fila productiva.
begin;
insert into crm.sla_politicas(id,version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos,publicada_por)
values ('00000000-0000-0000-0000-000000002001',1,'2026-01-01Z','America/Lima','corrido',120,1440,'00000000-0000-0000-0000-000000001004');
insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
select '00000000-0000-0000-0000-000000002001'::uuid,e,m from (values ('nuevo',1440),('contactado',11520),('reunion_agendada',21600),('propuesta_enviada',28800)) v(e,m);
commit;
