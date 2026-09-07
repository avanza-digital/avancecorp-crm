-- Sólo PostgreSQL desechable, sin TCP. Catálogo/Auth/capital son dobles;
-- citas, conversión, agregador y fachada se cargan desde su fuente real.
create schema crm;
create schema private;
create schema auth;
create role authenticated nologin;
create role anon nologin;
create function auth.uid() returns uuid language sql stable as
  'select nullif(current_setting(''test.uid'',true),'''')::uuid';
create table public.perfiles(id uuid primary key,activo boolean default true,nombre_completo text);
create table crm.equipo(perfil_id uuid primary key,activo boolean default true,rol_crm text,supervisor_id uuid);
create function private.rol_crm(uuid) returns text language sql stable as
  'select e.rol_crm from crm.equipo e join public.perfiles p on p.id=e.perfil_id where e.perfil_id=$1 and e.activo and p.activo';
create function private.es_lector_global() returns boolean language sql stable as 'select false';
create table crm.leads(id uuid primary key,creado_en timestamptz,origen text,alta_manual boolean default false,
  etapa text,perfil_id uuid,contrato_id uuid,convertido_en timestamptz,moneda text);
create table crm.tareas(id uuid primary key,lead_id uuid,vendedor_id uuid,tipo text,estado text,vence_en timestamptz,
  modalidad_reunion text,resultado_reunion text,cancelada_por text,cancelada_por_id uuid,activo boolean default true);
create table crm.lead_asignaciones(id uuid default gen_random_uuid(),lead_id uuid,analista_id uuid,origen text,
  aproximado boolean default false,asignado_en timestamptz,ciclo_n int default 1,episodio_n int default 1,
  resultado text,resultado_en timestamptz,finalizado_en timestamptz);
create table crm.operaciones_cartera(id uuid,cliente_id uuid,vendedor_id uuid,tipo text,periodo date,
  fecha_operacion date,creado_en timestamptz,elegible_conversion boolean,contrato_nuevo_id uuid,moneda text);
create table private.anulados_stub(lead_id uuid);
create function private.cierre_externo_anulado(uuid) returns boolean language sql stable as
  'select exists(select 1 from private.anulados_stub where lead_id=$1)';
create function private.peso_referido_conversion(date) returns numeric language sql stable as 'select 0.15::numeric';
create function private.analista_atribuido_cadena(uuid) returns uuid language sql stable as 'select null::uuid';
create table private.capital_stub(tipo text,medida text,cliente_id uuid,lead_id uuid,moneda text,monto numeric,fecha timestamptz);
create function private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])
  returns setof private.capital_stub language sql stable as 'select * from private.capital_stub';
grant usage on schema crm,auth to authenticated,anon;

insert into public.perfiles(id,nombre_completo)
select ('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case n when 1 then 'Analista activo' when 2 then 'Analista anterior' when 3 then 'Otro asesor' else 'Gerencia' end
from generate_series(1,4) n;
insert into crm.equipo(perfil_id,rol_crm,activo)
select id,case when nombre_completo='Gerencia' then 'gerencia' else 'vendedor' end,
  nombre_completo<>'Analista anterior' from public.perfiles;
insert into crm.leads(id,creado_en,origen,perfil_id,moneda,etapa)
select ('20000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'2026-07-01 08:00-05',
  case when n=2 then 'landing' else 'formulario' end,
  ('30000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n=2 then 'USD' else 'PEN' end,'convertido' from generate_series(1,6) n;
insert into crm.lead_asignaciones(lead_id,analista_id,origen,asignado_en,resultado,resultado_en)
select id,'10000000-0000-4000-8000-000000000001',origen,creado_en,
  case when id::text like '%000004' then null else 'convertido' end,
  case right(id::text,1) when '1' then '2026-07-10 09:59:40-05'::timestamptz
    when '2' then '2026-07-10 10:00-05'::timestamptz
    when '3' then '2026-08-10 10:00-05'::timestamptz
    when '4' then null else '2026-07-10 11:00-05'::timestamptz end from crm.leads;
insert into private.anulados_stub values('20000000-0000-4000-8000-000000000005');
insert into crm.tareas(id,lead_id,vendedor_id,tipo,estado,vence_en,modalidad_reunion,
  resultado_reunion,cancelada_por,cancelada_por_id,activo)
select ('40000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n=8 then null else ('20000000-0000-4000-8000-'||lpad((case when n<=5 then n when n<=7 then 6 else 4 end)::text,12,'0'))::uuid end,
  case when n=3 then '10000000-0000-4000-8000-000000000002'::uuid else '10000000-0000-4000-8000-000000000001'::uuid end,
  case when n=18 then 'llamada' else 'reunion' end,
  case when n<=8 or n>=17 then 'completada' when n=9 then 'no_show'
    when n<=13 then 'cancelada' when n=14 then 'reprogramada' else 'pendiente' end,
  case when n=6 then '2026-07-05 10:00-05'::timestamptz when n=7 then '2026-07-20 10:00-05'::timestamptz
    when n=16 then (((now() at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima')-interval '1 microsecond'
    else '2026-07-10 10:00-05'::timestamptz end,
  case when n=2 then 'virtual' else 'presencial' end,'interesado',
  case when n in(10,11) then 'asesor' when n=12 then 'sistema' end,
  case when n=11 then '10000000-0000-4000-8000-000000000003'::uuid
    when n=10 then '10000000-0000-4000-8000-000000000001'::uuid end,n<>17
from generate_series(1,18) n;
insert into private.capital_stub values
  ('contrato_real','stock','30000000-0000-4000-8000-000000000001',null,'PEN',200000,'2026-07-10 09:59:40-05'),
  ('contrato_real','stock','30000000-0000-4000-8000-000000000002',null,'USD',5000,'2026-07-10 10:00-05'),
  ('contrato_real','stock','30000000-0000-4000-8000-000000000003',null,'PEN',1000,'2026-08-10 10:00-05'),
  ('contrato_real','stock','30000000-0000-4000-8000-000000000006',null,'PEN',600,'2026-07-10 11:00-05');
