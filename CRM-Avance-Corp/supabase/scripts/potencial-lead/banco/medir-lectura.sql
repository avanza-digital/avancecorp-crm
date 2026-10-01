-- Cuánto tarda la puerta de lectura en el caso caro (Codex f3a r1): un supervisor con un equipo de 67
-- personas en tres niveles (su subárbol se resuelve en cada «puede marcar»), con una página (50 ids) y
-- con el tope (200 ids), sobre marcas recientes y sobre marcas de hace 400 días con historial de
-- contactos (los días se cuentan desde el reloj). SOLO en un banco, como supabase_admin; todo se deshace.
begin;
create temp table m_act (k text primary key, sup text, id uuid not null default gen_random_uuid()) on commit drop;
insert into m_act (k, sup) values ('T', null);
insert into m_act (k, sup) select 'S' || s, 'T' from generate_series(1, 6) s;
insert into m_act (k, sup) select 'V' || s || '_' || v, 'S' || s from generate_series(1, 6) s, generate_series(1, 10) v;
create temp table m_lds (n int primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into m_lds (n) select g from generate_series(1, 400) g;  -- 1..200 recientes · 201..400 antiguas
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@medir-lectura.banco' from m_act;
insert into public.perfiles (id, nombre_completo, rol, activo) select id, 'MEDIR ' || k, 'analista', true from m_act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
select a.id, case when a.k like 'V%' then 'vendedor' else 'supervisor' end, s.id, true
from m_act a left join m_act s on s.k = a.sup;
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
select l.id, 'MEDIR ' || l.n, '+5198763' || lpad(l.n::text, 4, '0'), 'landing', 10000, 'PEN', 'contactado',
       (select a.id from m_act a where a.k = 'V' || (1 + (l.n - 1) % 6) || '_' || (1 + ((l.n - 1) / 6) % 10)), true
from m_lds l;
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
select l.id, (array['estrella', 'tibio', 'frio'])[1 + l.n % 3]::crm.nivel_potencial, 'manual', v.vendedor_id,
       now() - case when l.n <= 200 then interval '3 days' else interval '400 days' end
from m_lds l join crm.leads v on v.id = l.id;
insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en)
select p.lead_id, null, p.nivel, 'manual', p.marcado_por, p.marcado_en from crm.lead_potencial p join m_lds l on l.id = p.lead_id;
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
select l.id, 'llamada_realizada', 'medición', v.vendedor_id, now() - interval '2 days'
from m_lds l join crm.leads v on v.id = l.id where l.n <= 200 and l.n % 2 = 0;
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
select l.id, 'whatsapp_enviado', 'medición', v.vendedor_id, now() - interval '401 days' - (g || ' days')::interval
from m_lds l join crm.leads v on v.id = l.id, generate_series(1, 20) g where l.n > 200;
set local session_replication_role = origin;
analyze crm.leads; analyze crm.lead_potencial; analyze crm.lead_potencial_eventos; analyze crm.actividades; analyze crm.equipo;
update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';
do $m$
declare
  v_rec uuid[]; v_ant uuid[]; v jsonb; t0 timestamptz; v_txt text := '';
  v_top uuid := (select id from m_act where k = 'T'); v_ana uuid := (select id from m_act where k = 'V1_1');
  ms numeric;
begin
  select array_agg(id order by n) into v_rec from m_lds where n <= 200;
  select array_agg(id order by n) into v_ant from m_lds where n > 200;
  perform set_config('request.jwt.claim.sub', v_top::text, true),
          set_config('request.jwt.claims', json_build_object('sub', v_top, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v := crm.potencial_leads_fn(v_rec[1:5]);  -- calentamiento
  t0 := clock_timestamp(); v := crm.potencial_leads_fn(v_rec[1:50]); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  v_txt := v_txt || format(' · supervisor de 67, recientes: 50 ids = %s ms (%s ítems)', round(ms, 1), jsonb_array_length(v -> 'items'));
  t0 := clock_timestamp(); v := crm.potencial_leads_fn(v_rec); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  v_txt := v_txt || format(', 200 ids = %s ms (%s ítems)', round(ms, 1), jsonb_array_length(v -> 'items'));
  t0 := clock_timestamp(); v := crm.potencial_leads_fn(v_ant); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  v_txt := v_txt || format(' · antiguas de 400 días con 20 contactos: 200 ids = %s ms (%s ítems)', round(ms, 1), jsonb_array_length(v -> 'items'));
  reset role;
  perform set_config('request.jwt.claim.sub', v_ana::text, true),
          set_config('request.jwt.claims', json_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  set local role authenticated;
  t0 := clock_timestamp(); v := crm.potencial_leads_fn(v_rec); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  reset role;
  v_txt := v_txt || format(' · analista pidiendo 200: %s ms (%s ítems suyos)', round(ms, 1), jsonb_array_length(v -> 'items'));
  raise exception 'MEDIR lectura%', v_txt using errcode = 'P0001';
end $m$;
rollback;
