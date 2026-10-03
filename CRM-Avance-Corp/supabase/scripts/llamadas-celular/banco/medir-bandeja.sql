-- Mide la bandeja con llamadas acumuladas (nadie las enlaza hasta F4). ROLLBACK al final.
\set ON_ERROR_STOP on
begin;
select set_config('t.ger', (select id::text from public.perfiles where correo = 'gerencia.crm@demo.avancecorp.pe'), true);
select set_config('t.v1', (select id::text from public.perfiles where correo = 'vend1.crm@demo.avancecorp.pe'), true);
select set_config('t.s1', (select id::text from public.perfiles where correo = 'sup1.crm@demo.avancecorp.pe'), true);
select set_config('request.jwt.claim.sub', current_setting('t.ger'), true);
set local role authenticated;
select set_config('t.asig', (crm.asignar_celular('C94', current_setting('t.v1')::uuid) ->> 'asignacion_id'), true);
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- 20 000 llamadas «por atender» de un mes de 10 analistas (~65/día cada uno), repartidas entre los leads vivos.
insert into crm.llamadas_celular_eventos
  (asignacion_id, analista_id, evento_origen_id, hash_payload, numero_canonico, direccion, estado_tecnico,
   identificacion, atencion, lead_id, metodo_asociacion, asociado_en, recibido_en)
select current_setting('t.asig')::uuid, current_setting('t.v1')::uuid, 'PERF-' || g, md5(g::text) || md5(g::text),
       '+51900000000', 'saliente', 'desconocido', 'identificado',
       case when g % 3 = 0 then 'por_revisar' else 'requiere_resultado' end,
       l.id, 'exacto', now(), now() - (g || ' minutes')::interval
from generate_series(1, 20000) g
join lateral (select id from crm.leads where activo order by md5(id::text || g) limit 1) l on true;
\timing on
select set_config('request.jwt.claim.sub', current_setting('t.v1'), true);
set local role authenticated;
select 'vend1 bandeja(50)', jsonb_array_length(crm.llamadas_celular_pendientes_fn(50));
reset role;
select set_config('request.jwt.claim.sub', current_setting('t.s1'), true);
set local role authenticated;
select 'sup1 bandeja(50)', jsonb_array_length(crm.llamadas_celular_pendientes_fn(50));
reset role;
select set_config('request.jwt.claim.sub', current_setting('t.ger'), true);
set local role authenticated;
select 'gerencia bandeja(50)', jsonb_array_length(crm.llamadas_celular_pendientes_fn(50));
reset role;
\timing off
rollback;
