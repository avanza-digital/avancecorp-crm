-- SOLO banco vacío autorizado. Datos sintéticos; nunca ejecutar en producción.
begin;
do $$ begin
  if exists(select 1 from public.perfiles) or exists(select 1 from crm.leads) then
    raise exception 'La semilla requiere un banco vacío';
  end if;
end $$;
set local session_replication_role=replica;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,raw_app_meta_data,raw_user_meta_data)
select ('b0000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'ranking-'||i||'@example.test','',now(),now(),now(),'','','','','{"provider":"email"}','{}'
from generate_series(1,39) i;
insert into public.perfiles(id,nombre_completo,rol,activo)
select id,'PRUEBA RANKING '||email,case when email='ranking-3@example.test' then 'admin' when email='ranking-7@example.test' then 'cliente' else 'analista' end,true
from auth.users;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select id,case when email in ('ranking-1@example.test','ranking-4@example.test') then 'supervisor' when email='ranking-3@example.test' then 'gerencia' else 'vendedor' end,
case when email in ('ranking-1@example.test','ranking-3@example.test','ranking-4@example.test') then null
when email='ranking-5@example.test' then 'b0000000-0000-4000-8000-000000000004'::uuid else 'b0000000-0000-4000-8000-000000000001'::uuid end,
email<>'ranking-6@example.test'
from auth.users where email<>'ranking-7@example.test';
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota) values('2026-01-01',0.15,0.15,'PRUEBA');
insert into crm.sla_politicas(id,version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
values(md5('ranking-sla')::uuid,1,'2026-01-01','America/Lima','corrido',60,120);
insert into crm.productos_inversion(id,codigo) values(md5('ranking-producto')::uuid,'RANKING_TEST');
insert into crm.producto_versiones(id,producto_id,numero_version,nombre,vigente_desde)
values(md5('ranking-version')::uuid,md5('ranking-producto')::uuid,1,'PRUEBA','2026-01-01');
insert into crm.producto_condiciones(id,version_id,orden,categoria,moneda,plazo_meses,modalidad,tipo_interes,capital_minimo,capital_maximo,tasa_referencia,tasa_minima,tasa_maxima)
values(md5('ranking-condicion')::uuid,md5('ranking-version')::uuid,1,'nuevo','PEN',12,'anual','simple',100,100000000,15,1,50);
insert into crm.meta_periodos(id,periodo,revision,publicada_por)
select md5('ranking-meta-'||m)::uuid,('2026-'||m||'-01')::date,1,'b0000000-0000-4000-8000-000000000003' from (values('08'),('09')) meses(m);
insert into crm.metas_vendedor(id,meta_periodo_id,vendedor_id,supervisor_id,conversion_objetivo)
select md5(mp.id::text||e.perfil_id::text)::uuid,mp.id,e.perfil_id,e.supervisor_id,10 from crm.meta_periodos mp cross join crm.equipo e where e.rol_crm='vendedor' and e.activo;
insert into crm.metas_vendedor_detalle(meta_vendedor_id,categoria,moneda,capital_objetivo,contratos_objetivo)
select mv.id,c,m,10000,10 from crm.metas_vendedor mv cross join (values('nuevo'),('renovacion'),('upgrade')) cat(c) cross join (values('PEN'),('USD')) mon(m);
-- 2 048 llegadas / 34 vendedores activos / dos meses. Solo 32 se cierran.
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,perfil_id,contrato_id,etapa,creado_en,convertido_en)
select md5('ranking-lead-'||i)::uuid,'PRUEBA '||i,'+519'||lpad(i::text,8,'0'),
(array['landing','formulario','referido','oficina'])[1+(i-1)%4],1000,
case when i<=32 then 'b0000000-0000-4000-8000-000000000002'::uuid else ('b0000000-0000-4000-8000-'||lpad((8+i%32)::text,12,'0'))::uuid end,
case when i<=32 then 'b0000000-0000-4000-8000-000000000007'::uuid end,
case when i<=32 then md5('ranking-contrato-'||i)::uuid end,
case when i<=32 then 'convertido' else 'nuevo' end,
case when i%8<4 then timestamptz '2026-08-01 00:00:00-05' else timestamptz '2026-09-01 00:00:00-05' end,
case when i<=32 then case when i%8<4 then timestamptz '2026-08-15 12:00:00-05' else timestamptz '2026-09-15 12:00:00-05' end end
from generate_series(1,2048) i;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,fecha_vencimiento,fecha_cierre_comercial,categoria,analista_cierre_id,creado_por,producto_condicion_id)
select l.contrato_id,'RANKING-'||i,'b0000000-0000-4000-8000-000000000007',1000,case when i>24 then 'USD' else 'PEN' end,'anual',
(l.convertido_en at time zone 'America/Lima')::date,'2027-09-15',(l.convertido_en at time zone 'America/Lima')::date,
case when i>28 then 'renovacion' when i>24 then 'upgrade' else 'nuevo' end,l.vendedor_id,l.vendedor_id,md5('ranking-condicion')::uuid
from generate_series(1,32) i join crm.leads l on l.id=md5('ranking-lead-'||i)::uuid;
insert into crm.lead_asignaciones(lead_id,ciclo_n,episodio_n,analista_id,motivo_apertura,asignado_en,moneda,origen,finalizado_en,motivo_cierre,resultado,resultado_en,sla_global_iniciado_en,sla_politica_asignacion_id,primera_gestion_limite_en,primer_contacto_limite_en)
select id,1,1,vendedor_id,'ingreso',creado_en,'PEN',origen,convertido_en,case when convertido_en is not null then 'convertido' end,
case when convertido_en is not null then 'convertido' end,convertido_en,creado_en,md5('ranking-sla')::uuid,creado_en+interval '1 hour',creado_en+interval '2 hours' from crm.leads;
set local session_replication_role=origin;
-- La carga histórica fuera de banda no permite dejar FKs rotas.
do $$ declare r record; v_bad boolean; begin
for r in select conrelid::regclass tabla,confrelid::regclass padre,conkey,confkey from pg_constraint where contype='f' and connamespace in ('crm'::regnamespace,'public'::regnamespace) loop
execute format('select exists(select 1 from %s c where %s and not exists(select 1 from %s p where %s))',r.tabla,
(select string_agg(format('c.%I is not null',attname),' and ') from pg_attribute where attrelid=r.tabla and attnum=any(r.conkey)),r.padre,
(select string_agg(format('p.%I=c.%I',p.attname,c.attname),' and ') from unnest(r.conkey,r.confkey) k(cn,pn) join pg_attribute c on c.attrelid=r.tabla and c.attnum=k.cn join pg_attribute p on p.attrelid=r.padre and p.attnum=k.pn)) into v_bad;
if v_bad then raise exception 'FK rota: % hacia %',r.tabla,r.padre;end if;
end loop;
end $$;
commit;
