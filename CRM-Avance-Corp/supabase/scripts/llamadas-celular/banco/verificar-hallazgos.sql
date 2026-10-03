-- Reproduce en el stack propio (esquema de producción + semilla del gate) los hallazgos de la revisión.
-- Todo en una transacción que termina en ROLLBACK: no deja rastro.
\set ON_ERROR_STOP on
begin;
create temp table r (n serial, caso text, resultado text);
grant all on r to public;
grant all on sequence r_n_seq to public;

select set_config('t.ger', (select id::text from public.perfiles where correo = 'gerencia.crm@demo.avancecorp.pe'), true);
select set_config('t.v1', (select id::text from public.perfiles where correo = 'vend1.crm@demo.avancecorp.pe'), true);
select set_config('t.juan', '11000000-0000-4000-8000-000000000001', true);

-- Gerencia asigna un celular de prueba (C95) a vend1.
select set_config('request.jwt.claim.sub', current_setting('t.ger'), true);
set local role authenticated;
select set_config('t.clave', (crm.asignar_celular('C95', current_setting('t.v1')::uuid) ->> 'credencial'), true);
reset role;

-- ── H1 · Oráculo del reenvío (A-P2-1): mismo origen, segundo número distinto ──
select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
-- (a) primer envío a un número SIN lead, luego el mismo origen con el número de juan
insert into r (caso, resultado) select 'H1a envío 1 (sin lead)', crm.ingerir_llamada_celular_servicio(current_setting('t.clave'),
  '{"v":1,"evento_origen_id":"H1-A","numero":"911000001","direccion":"saliente"}'::jsonb)::text;
insert into r (caso, resultado) select 'H1a envío 2 (mismo origen, número de juan)', crm.ingerir_llamada_celular_servicio(current_setting('t.clave'),
  '{"v":1,"evento_origen_id":"H1-A","numero":"987654321","direccion":"saliente"}'::jsonb)::text;
-- (b) primer envío a juan, luego el mismo origen con otro número
insert into r (caso, resultado) select 'H1b envío 1 (juan)', crm.ingerir_llamada_celular_servicio(current_setting('t.clave'),
  '{"v":1,"evento_origen_id":"H1-B","numero":"987654321","direccion":"saliente"}'::jsonb)::text;
do $$ begin
  perform crm.ingerir_llamada_celular_servicio(current_setting('t.clave'),
    '{"v":1,"evento_origen_id":"H1-B","numero":"911000001","direccion":"saliente"}'::jsonb);
  insert into r (caso, resultado) values ('H1b envío 2 (mismo origen, otro número)', 'aceptado');
exception when others then
  insert into r (caso, resultado) values ('H1b envío 2 (mismo origen, otro número)', sqlstate || ' ' || sqlerrm);
end $$;

-- ── H2 · Entrantes encendidas (#14): una entrante PERDIDA de juan ──
reset role;
select set_config('request.jwt.claim.sub', current_setting('t.ger'), true);
set local role authenticated;
select crm.fijar_politica_llamadas_celular(p_entrantes_activas => true);
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
insert into r (caso, resultado) select 'H2 entrante perdida con la perilla encendida',
  crm.ingerir_llamada_celular_servicio(current_setting('t.clave'),
  '{"v":1,"evento_origen_id":"H2-A","numero":"987654321","direccion":"entrante","estado_tecnico":"no_atendida"}'::jsonb)::text;
reset role;
insert into r (caso, resultado) select 'H2 atención guardada de esa entrante', atencion
  from crm.llamadas_celular_eventos where evento_origen_id = 'H2-A';

-- ── H3 · Gerencia y un lead borrado (A-P2-2) ──
-- Como dueño de las tablas: el lead juan pasa a inactivo (soft-delete) sin pasar por la app.
alter table crm.leads disable trigger user;
update crm.leads set activo = false where id = current_setting('t.juan')::uuid;
alter table crm.leads enable trigger user;
select set_config('request.jwt.claim.sub', current_setting('t.ger'), true);
set local role authenticated;
insert into r (caso, resultado) select 'H3 gerencia ve llamadas de juan (borrado) en su bandeja',
  (select count(*) from jsonb_array_elements(crm.llamadas_celular_pendientes_fn(200)) f
    where f ->> 'lead_id' = current_setting('t.juan'))::text;
insert into r (caso, resultado) select 'H3 gerencia ve el nombre del lead borrado',
  (select string_agg(distinct f ->> 'lead_nombre', ',') from jsonb_array_elements(crm.llamadas_celular_pendientes_fn(200)) f
    where f ->> 'lead_id' = current_setting('t.juan'));
do $$ declare v uuid; begin
  select (f ->> 'evento_id')::uuid into v from jsonb_array_elements(crm.llamadas_celular_pendientes_fn(200)) f
   where f ->> 'lead_id' = current_setting('t.juan') limit 1;
  perform crm.descartar_llamada_celular(v, 'personal');
  insert into r (caso, resultado) values ('H3 gerencia DESCARTA una llamada del lead borrado', 'aceptado');
exception when others then
  insert into r (caso, resultado) values ('H3 gerencia DESCARTA una llamada del lead borrado', sqlstate || ' ' || sqlerrm);
end $$;
reset role;
select set_config('request.jwt.claim.sub', current_setting('t.v1'), true);
set local role authenticated;
insert into r (caso, resultado) select 'H3 vend1 (dueño) ve llamadas de juan borrado',
  (select count(*) from jsonb_array_elements(crm.llamadas_celular_pendientes_fn(200)) f
    where f ->> 'lead_id' = current_setting('t.juan'))::text;
reset role;

select n, caso, resultado from r order by n;
rollback;
