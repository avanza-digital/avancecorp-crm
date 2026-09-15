-- Datos ficticios de esta prueba, dentro de la transacción local que se revierte.
create temporary table prueba_responsables as select
 (select perfil_id from crm.equipo where activo and rol_crm='vendedor' order by perfil_id limit 1) analista,
 (select supervisor_id from crm.equipo where activo and rol_crm='vendedor' order by perfil_id limit 1) supervisor;
set local session_replication_role='replica';
insert into auth.users(id,aud,role,email)
 select md5('ficha-limite-perfil-'||n)::uuid,'authenticated','authenticated','ficha-limite-'||n||'@example.invalid'
 from generate_series(1,6) n;
insert into public.perfiles(id,nombre_completo,correo,dni,asesor_perfil_id)
 select md5('ficha-limite-perfil-'||n)::uuid,'CASO SINTETICO '||n,'ficha-limite-'||n||'@example.invalid',
 (79000000+n)::text,r.analista from generate_series(1,6) n cross join prueba_responsables r;
insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
 select md5('ficha-limite-persona-'||n)::uuid,md5('ficha-limite-perfil-'||n)::uuid,
 case when n=5 then null else r.analista end from generate_series(1,6) n cross join prueba_responsables r;
-- 3 y 4 prueban enlaces a perfiles históricos de una identidad fusionada.
insert into crm.inversionistas(id,responsable_relacion_id)
 select md5('ficha-limite-canonica-'||n)::uuid,r.analista from generate_series(3,4) n cross join prueba_responsables r;
update crm.inversionistas set estado='fusionado',fusionado_en=now(),
 inversionista_canonico_id=md5('ficha-limite-canonica-'||n)::uuid
 from generate_series(3,4) n where id=md5('ficha-limite-persona-'||n)::uuid;
insert into crm.leads(id,nombre_completo,telefono,monto_estimado,inversionista_id,vendedor_id,asignado_supervisor_id)
 select md5('ficha-limite-lead-'||n)::uuid,'CASO SINTETICO '||n,'+51988'||lpad(n::text,6,'0'),1000,
 md5('ficha-limite-persona-'||n)::uuid,case when n=5 then null else r.analista end,
 case when n=5 then r.supervisor else null end from generate_series(1,6) n cross join prueba_responsables r;
-- 1 y 3: solo demo. 2 y 4: demo + real. 5: bandeja del supervisor. 6: perfil sin contratos.
insert into public.contratos
 select (jsonb_populate_record(null::public.contratos,to_jsonb(t)||jsonb_build_object(
 'id',md5('ficha-limite-contrato-'||x.numero)::uuid,'numero_contrato','FICHA-LIMITE-'||x.numero,
 'cliente_id',md5('ficha-limite-perfil-'||x.persona)::uuid,'es_demo',x.demo))).*
 from (select * from public.contratos where estado='activo' and not es_demo order by id limit 1) t
 cross join (values(1,1,true),(2,2,true),(3,3,true),(4,4,true),(5,2,false),(6,4,false),(7,5,false)) x(numero,persona,demo);
set local session_replication_role='origin';
create temporary table prueba_huellas(fase text,tabla text,huella text);
create function pg_temp.capturar_huellas(p_fase text) returns void language plpgsql as $huellas$
declare tabla text; huella text;
begin
 foreach tabla in array array['public.contratos','public.cronograma_pagos','crm.inversiones','crm.cierres_externos',
  'crm.inversionistas','crm.inversionista_identificadores','crm.inversionista_leads','crm.leads'] loop
  execute format('select md5(coalesce(string_agg(to_jsonb(t)::text,E''\n'' order by t.id),'''')) from %s t',tabla) into huella;
  insert into prueba_huellas values(p_fase,tabla,huella);
 end loop;
end; $huellas$;
create temporary table prueba_inactivos(fase text,causa text,dato jsonb);
