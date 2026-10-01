-- Medición del lote de la caducidad (fase 2): cuánto dura una pasada de private.potencial_caducar.
-- SOLO en el banco, como supabase_admin; UNA transacción que se deshace. Siembra 2 000 marcas Estrella
-- vencidas (con 3 contactos viejos cada una) y mide una pasada de 200, otra de 200 y el resto sin
-- acotar. Es el tiempo que la tarea sostiene sus candados: lo máximo que puede esperar un usuario que
-- toque uno de esos leads a esa hora. Medido el 30/09/2026: 200 leads = 34 ms; 1 600 = 162 ms.
begin;
set local session_replication_role = replica;
insert into auth.users (id, email) values ('00000000-0000-4000-8000-00000000e0a1','med@caducidad.banco');
insert into public.perfiles (id, nombre_completo, rol, activo) values ('00000000-0000-4000-8000-00000000e0a1','MEDICION V1','analista',true);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values ('00000000-0000-4000-8000-00000000e0a1','vendedor',null,true);
create temp table ml on commit drop as select gen_random_uuid() as id, g from generate_series(1, 2000) g;
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
select id, 'MEDICION ' || g, '+5197' || lpad(g::text, 7, '0'), 'landing', 10000, 'PEN', 'contactado', '00000000-0000-4000-8000-00000000e0a1', true from ml;
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
select id, 'estrella', 'manual', '00000000-0000-4000-8000-00000000e0a1', ('2026-10-05 10:00'::timestamp at time zone 'America/Lima') + (g || ' seconds')::interval from ml;
-- 3 contactos viejos por lead (no reinician: son anteriores a la marca)
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
select id, 'llamada_realizada', 'medición', '00000000-0000-4000-8000-00000000e0a1', ('2026-09-2' || k || ' 10:00')::timestamp at time zone 'America/Lima' from ml, generate_series(1,3) k;
set local session_replication_role = origin;
analyze crm.lead_potencial; analyze crm.leads;
do $m$
declare t0 timestamptz; n int; ms numeric;
begin
  set local role postgres;
  t0 := clock_timestamp();
  n := private.potencial_caducar('2026-10-12', ('2026-10-12 05:10'::timestamp at time zone 'America/Lima'), 200);
  ms := round(1000 * extract(epoch from clock_timestamp() - t0)::numeric, 1);
  raise notice 'MEDICION lote de 200 (de 2000 vencidas): % bajadas en % ms', n, ms;
  t0 := clock_timestamp();
  n := private.potencial_caducar('2026-10-12', ('2026-10-12 05:10'::timestamp at time zone 'America/Lima'), 200);
  ms := round(1000 * extract(epoch from clock_timestamp() - t0)::numeric, 1);
  raise notice 'MEDICION segunda pasada de 200: % bajadas en % ms', n, ms;
  t0 := clock_timestamp();
  n := private.potencial_caducar('2026-10-12', ('2026-10-12 05:10'::timestamp at time zone 'America/Lima'), 5000);
  ms := round(1000 * extract(epoch from clock_timestamp() - t0)::numeric, 1);
  raise notice 'MEDICION sin acotar (las 1600 restantes): % bajadas en % ms', n, ms;
  reset role;
end $m$;
rollback;
