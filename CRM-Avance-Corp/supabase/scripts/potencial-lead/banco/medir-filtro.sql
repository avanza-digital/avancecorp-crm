-- Cuánto cuesta el filtro por potencial en crm.cartera_filtrada_fn (entrega B): la función ANTERIOR
-- (firma de 13) contra la nueva sin filtro y con filtro, sobre 6 000 leads y 2 400 marcas, como
-- gerencia (ve todo), como un supervisor (1 000 leads) y como un analista (100). Mediana de 5.
-- SOLO en un banco, como supabase_admin, con banco/anterior-13.sql delante; todo se deshace.
begin;
create temp table m_act (k text primary key, sup text, id uuid not null default gen_random_uuid()) on commit drop;
insert into m_act (k, sup) values ('G', null);
insert into m_act (k, sup) select 'S' || s, null from generate_series(1, 6) s;
insert into m_act (k, sup) select 'V' || s || '_' || v, 'S' || s from generate_series(1, 6) s, generate_series(1, 10) v;
create temp table m_lds (n int primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into m_lds (n) select g from generate_series(1, 6000) g;
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@medir-filtro.banco' from m_act;
insert into public.perfiles (id, nombre_completo, rol, activo) select id, 'MEDIR ' || k, case when k = 'G' then 'admin' else 'analista' end, true from m_act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
select a.id, case when a.k = 'G' then 'gerencia' when a.k like 'V%' then 'vendedor' else 'supervisor' end, s.id, true
from m_act a left join m_act s on s.k = a.sup;
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo, actualizado_en)
select l.id, 'MEDIR ' || l.n, '+519876' || lpad(l.n::text, 5, '0'), 'landing', 10000, 'PEN',
       (array['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada'])[1 + l.n % 4],
       (select a.id from m_act a where a.k = 'V' || (1 + (l.n - 1) % 6) || '_' || (1 + ((l.n - 1) / 6) % 10)), true,
       now() - (l.n || ' seconds')::interval
from m_lds l;
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
select l.id, (array['estrella', 'tibio', 'frio'])[1 + l.n % 3]::crm.nivel_potencial, 'manual', v.vendedor_id, now() - interval '3 days'
from m_lds l join crm.leads v on v.id = l.id where l.n % 5 < 2;
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
select l.id, 'llamada_realizada', 'medición', v.vendedor_id, now() - interval '2 days'
from m_lds l join crm.leads v on v.id = l.id where l.n % 2 = 0;
set local session_replication_role = origin;
analyze crm.leads; analyze crm.lead_potencial; analyze crm.actividades; analyze crm.equipo;
update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';

create function pg_temp.mediana(p_sql text) returns numeric language plpgsql as $f$
declare t0 timestamptz; v jsonb; ms numeric[] := '{}'; i int;
begin
  execute p_sql into v;  -- calentamiento
  for i in 1..5 loop
    t0 := clock_timestamp();
    execute p_sql into v;
    ms := ms || (extract(epoch from clock_timestamp() - t0) * 1000)::numeric;
  end loop;
  return round((select x from unnest(ms) x order by x offset 2 limit 1), 1);
end $f$;

do $m$
declare
  v_txt text := ''; r record; v jsonb;
begin
  for r in select * from (values ('gerencia', 'G'), ('supervisor', 'S1'), ('analista', 'V1_1')) t(rol, k) loop
    perform set_config('request.jwt.claim.sub', (select id::text from m_act where k = r.k), true),
            set_config('request.jwt.claims', json_build_object('sub', (select id from m_act where k = r.k), 'role', 'authenticated')::text, true);
    set local role authenticated;
    v := crm.cartera_filtrada_fn(p_limite => 50);
    v_txt := v_txt || format(' · %s (%s leads, %s marcas): anterior %s ms, nueva %s ms, con estrella %s ms, con sin_marca %s ms',
      r.rol, v #>> '{resumen,totales,vivos}',
      (v #>> '{resumen,potencial,estrella}')::int + (v #>> '{resumen,potencial,tibio}')::int + (v #>> '{resumen,potencial,frio}')::int,
      pg_temp.mediana('select pg_temp.cartera_filtrada_anterior(p_limite => 50)'),
      pg_temp.mediana('select crm.cartera_filtrada_fn(p_limite => 50)'),
      pg_temp.mediana($c$select crm.cartera_filtrada_fn(p_limite => 50, p_potencial => 'estrella')$c$),
      pg_temp.mediana($c$select crm.cartera_filtrada_fn(p_limite => 50, p_potencial => 'sin_marca')$c$));
    reset role;
  end loop;
  raise exception 'MEDIR filtro%', v_txt using errcode = 'P0001';
end $m$;
rollback;
