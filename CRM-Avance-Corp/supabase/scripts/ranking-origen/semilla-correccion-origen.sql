begin;
do $$begin if current_database()<>'ranking_origen_correccion_20260928' then raise exception 'Solo banco local exclusivo';end if;end $$;
set local session_replication_role=replica;
insert into auth.users(id,email,aud,role) select md5('correccion-perfil-'||i)::uuid,'correccion-'||i||'@example.test','authenticated','authenticated' from generate_series(1,7) i;
insert into public.perfiles(id,nombre_completo,rol,activo) select md5('correccion-perfil-'||i)::uuid,'PRUEBA CORRECCION '||i,'cliente',true from generate_series(1,7) i;
insert into crm.inversionistas(id,perfil_id) select md5('correccion-persona-'||i)::uuid,md5('correccion-perfil-'||i)::uuid from generate_series(1,7) i;
insert into public.contratos
select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
 'id',md5('correccion-fuente-'||i)::uuid,'numero_contrato','CORRECCION-'||i,
 'cliente_id',md5('correccion-perfil-'||i)::uuid,'capital',1000*i,'moneda',case when i=5 then 'USD' else 'PEN' end,
 'fecha_cierre_comercial','2026-09-05','creado_en','2026-09-05T16:00:00Z','analista_cierre_id','b0000000-0000-4000-8000-000000000002'))).*
from public.contratos c cross join generate_series(1,5) i where c.numero_contrato='BANCO-A1';
insert into crm.leads
select (jsonb_populate_record(null::crm.leads,to_jsonb(l)||jsonb_build_object(
 'id',md5('correccion-lead-'||i)::uuid,'nombre_completo','PRUEBA CORRECCION '||i,'telefono','+5198800070'||i,
 'dni','8800070'||i,'correo','correccion-'||i||'@example.test','origen','otro','nota',null,
 'perfil_id',case when i<=5 then md5('correccion-perfil-'||i)::uuid end,
 'contrato_id',case when i<=5 then md5('correccion-fuente-'||i)::uuid end,
 'inversionista_id',md5('correccion-persona-'||i)::uuid,'vendedor_id','b0000000-0000-4000-8000-000000000002',
 'sla_global_iniciado_en',case when i=7 then '2026-08-31T10:00:00Z' else '2026-09-05T10:00:00Z' end,
 'creado_en',case when i=7 then '2026-08-31T10:00:00Z' else '2026-09-05T10:00:00Z' end,
 'convertido_en',case when i=7 then '2026-08-31T16:00:00Z' else '2026-09-05T16:00:00Z' end))).*
from crm.leads l cross join generate_series(1,7) i where l.nombre_completo='BANCO CLIENTE A UNO';
insert into crm.lead_asignaciones
select (jsonb_populate_record(null::crm.lead_asignaciones,to_jsonb(la)||jsonb_build_object(
 'id',md5('correccion-episodio-'||i)::uuid,'lead_id',md5('correccion-lead-'||i)::uuid,'origen','otro',
 'analista_id','b0000000-0000-4000-8000-000000000002',
 'sla_global_iniciado_en',case when i=7 then '2026-08-31T10:00:00Z' else '2026-09-05T10:00:00Z' end,
 'asignado_en',case when i=7 then '2026-08-31T10:00:00Z' else '2026-09-05T10:00:00Z' end,
 'finalizado_en',case when i=7 then '2026-08-31T16:00:00Z' else '2026-09-05T16:00:00Z' end,
 'resultado_en',case when i=7 then '2026-08-31T16:00:00Z' else '2026-09-05T16:00:00Z' end))).*
from crm.lead_asignaciones la join crm.leads l on l.id=la.lead_id
cross join generate_series(1,7) i where l.nombre_completo='BANCO CLIENTE A UNO' and la.resultado='convertido';
insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en,es_cierre_inicial,inversionista_id)
select md5('correccion-fuente-'||i)::uuid,md5('correccion-lead-'||i)::uuid,'qorilazo',i*1000,'PEN','DNI','8800070'||i,
 'PRUEBA CORRECCION '||i,'CORRECCION-'||i,'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002',
 '2026-09-05 16:00Z',true,md5('correccion-persona-'||i)::uuid from generate_series(6,7) i;
update crm.conversion_politica set activada_en=now(),manifiesto_huella=repeat('0',64),resultado='{"prueba":true}';
set local session_replication_role=origin;
select private.conversion_acreditar_fuente(md5('correccion-lead-'||i)::uuid,case when i<=5 then 'contrato' else 'cierre_externo' end,md5('correccion-fuente-'||i)::uuid,'Fuente ficticia de prueba') from generate_series(1,6) i;
commit;
