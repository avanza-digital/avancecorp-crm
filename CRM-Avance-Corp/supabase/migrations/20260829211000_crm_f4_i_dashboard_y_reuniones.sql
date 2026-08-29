-- P-055 FASE 4.i — Las dos ultimas pantallas entran al nucleo (piezas 5 y 6).
--
-- 5) public.dashboard_admin_metricas: era INVOKER apoyada en la RLS (quien la
--    llamaba veia "sus" contratos; para el admin, todos). Pasa a DEFINER con
--    GATE EXPLICITO es_gestor_cartera() — la misma autoridad que la RLS le
--    daba de facto a quien la usa (es el tablero del admin del portal) — y lee
--    del nucleo. Oraculo: payload del admin byte a byte.
-- 6) private.metricas_reuniones_implementacion: sus CONVERSIONES ya beben del
--    ledger (C0.1); su CAPITAL seguia colgando del enlace muerto
--    leads.contrato_id y por eso "capital tras reunion" fue SIEMPRE CERO en la
--    pantalla. Se conecta al nucleo con la misma regla del panel de
--    Conversiones (capital vivo del lead: contratos del perfil + coops del
--    lead). ⚠️ CAMBIO VISIBLE A PROPOSITO: los ceros pasan a numeros reales
--    (orden de Miguel: «terminemos la calculadora»); el oraculo aqui exige que
--    TODO LO DEMAS del payload quede identico y que el capital deje de ser 0.

begin;

set local lock_timeout = '5s';

create temp table zz_f4i (k text, h text) on commit drop;

do $antes$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'; h1 text; h2 text;
begin
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select md5(public.dashboard_admin_metricas()::text) into h1;
  reset role;
  -- reuniones es private: como postgres con claims (gate interno gerencia)
  select md5((private.metricas_reuniones_implementacion(date '2026-08-01', current_date)
              - 'generado_en'
              #- '{conversion,capital_pen}'::text[] #- '{conversion,capital_usd}'::text[]
             )::text) into h2;
  perform set_config('request.jwt.claims', '', true);
  insert into zz_f4i values ('dashboard',h1), ('reuniones_sin_capital',h2);
end
$antes$;

do $pre$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p where p.oid='public.dashboard_admin_metricas()'::regprocedure;
  if v_h <> '5e61e7a814b8908dcc30d1107ee48d67' then
    raise exception 'dashboard cambio (huella %): ABORTA', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid='private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if v_h <> 'b833b1f95d8427c34a551b8abe20309c' then
    raise exception 'reuniones cambio (huella %): ABORTA', v_h; end if;
end
$pre$;

-- ── 5) el tablero del admin ──
create or replace function public.dashboard_admin_metricas()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $fn$
declare v jsonb;
begin
  -- Antes era INVOKER y la RLS decidia: en la practica, solo el gestor de
  -- cartera (admin/superadmin/operaciones) veia el tablero completo. El gate
  -- explicito conserva EXACTAMENTE esa autoridad.
  if not (select public.es_gestor_cartera()) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  with contratos_norm as (
    select
      case
        when e.estado = 'vencido' then 'vencido'
        when e.fecha_vencimiento < current_date then 'vencido'
        else e.estado
      end as estado_real,
      e.fecha_vencimiento,
      e.monto as capital,
      e.moneda
    from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) e
    where e.tipo like 'contrato_%' and e.medida='stock'
      and e.estado in ('activo','vencido')
  ),
  metricas as (
    select
      count(*) filter (where estado_real = 'activo') as contratos_activos,
      count(*) filter (where estado_real = 'vencido') as vencidos,
      count(*) filter (where estado_real = 'activo' and fecha_vencimiento <= current_date + 30) as por_vencer,
      coalesce(sum(capital) filter (where estado_real = 'activo' and moneda = 'PEN'), 0) as capital_pen,
      coalesce(sum(capital) filter (where estado_real = 'activo' and moneda = 'USD'), 0) as capital_usd
    from contratos_norm
  ),
  total_clientes as (
    select count(*) as total from public.perfiles where rol = 'cliente'
  )
  select jsonb_build_object(
    'contratosActivos', m.contratos_activos,
    'capitalPEN',       m.capital_pen,
    'capitalUSD',       m.capital_usd,
    'totalClientes',    tc.total,
    'porVencer',        m.por_vencer,
    'vencidos',         m.vencidos
  ) into v
  from metricas m, total_clientes tc;
  return v;
end;
$fn$;

-- ── 6) reuniones: el capital, del nucleo ──
do $r$
declare v_src text; v_nuevo text;
  a1 text; r1 text;
begin
  select p.prosrc into v_src from pg_proc p
  where p.oid='private.metricas_reuniones_implementacion(date,date)'::regprocedure;

  a1 := '    left join public.contratos c on c.id = l.contrato_id';
  r1 := '    left join lateral (
      -- F4.i: el capital VIVO del lead, del NUCLEO (misma regla que el panel
      -- de Conversiones): contratos del perfil + cooperativas del lead. El
      -- enlace leads.contrato_id jamas se rello (0/466) y por eso esta
      -- pantalla mostro capital 0 SIEMPRE.
      select sum(k.monto) filter (where k.moneda=''PEN'') as capital_pen_nucleo,
             sum(k.monto) filter (where k.moneda=''USD'') as capital_usd_nucleo,
             min(k.fecha) as contrato_creado_en_nucleo
      from private.capital_episodios(''-infinity''::timestamptz,''infinity''::timestamptz,true,''{}''::uuid[]) k
      where k.medida = ''stock''
        and ((k.tipo like ''contrato_%'' and k.cliente_id = l.perfil_id)
          or (k.tipo = ''cooperativa'' and k.lead_id = l.id))
    ) c on true';
  if (length(v_src)-length(replace(v_src,a1,'')))/length(a1) <> 1 then
    raise exception 'El ancla del join muerto no aparece exactamente una vez: ABORTA';
  end if;
  v_nuevo := replace(v_src, a1, r1);

  -- el select de base leia c.capital / c.moneda / c.creado_en del join muerto:
  a1 := 'c.capital, c.moneda, c.creado_en as contrato_creado_en,';
  r1 := 'case when l.moneda = ''USD'' then c.capital_usd_nucleo else c.capital_pen_nucleo end as capital,
      l.moneda, c.contrato_creado_en_nucleo as contrato_creado_en,';
  if (length(v_nuevo)-length(replace(v_nuevo,a1,'')))/length(a1) <> 1 then
    raise exception 'El ancla de las columnas muertas no aparece exactamente una vez: ABORTA';
  end if;
  v_nuevo := replace(v_nuevo, a1, r1);

  execute format(
    'create or replace function private.metricas_reuniones_implementacion(p_desde date, p_hasta date) '
    'returns jsonb language plpgsql stable security definer set search_path to '''' as %L', v_nuevo);
end
$r$;

-- ------------------------------------------------------------------ ORACULO --
do $despues$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        h1 text; h2 text; v_cap numeric; v_falla text := '';
begin
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select md5(public.dashboard_admin_metricas()::text) into h1;
  reset role;
  select md5((private.metricas_reuniones_implementacion(date '2026-08-01', current_date)
              - 'generado_en'
              #- '{conversion,capital_pen}'::text[] #- '{conversion,capital_usd}'::text[]
             )::text) into h2;
  perform set_config('request.jwt.claims', '', true);

  if h1 <> (select h from zz_f4i where k='dashboard') then v_falla := v_falla || 'dashboard '; end if;
  if h2 <> (select h from zz_f4i where k='reuniones_sin_capital') then v_falla := v_falla || 'reuniones/resto-del-payload '; end if;

  -- El capital del payload HOY es 0 legitimamente: no existe todavia ninguna
  -- cadena reunion-realizada→conversion en los datos (medido). Lo que se
  -- prueba es EL CABLE: para un lead real con capital conocido, la regla del
  -- nucleo que la funcion ahora usa devuelve ese capital, no NULL.
  select coalesce(sum(k.monto),0) into v_cap
  from (select l.id, l.perfil_id from crm.leads l
        where l.perfil_id is not null
          and exists (select 1 from public.contratos c
                      where c.cliente_id = l.perfil_id and not c.es_demo)
        limit 1) lx
  cross join lateral (
    select monto from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) k
    where k.medida='stock' and k.moneda='PEN'
      and ((k.tipo like 'contrato_%' and k.cliente_id = lx.perfil_id)
        or (k.tipo='cooperativa' and k.lead_id = lx.id))) k;
  if v_cap is null or v_cap = 0 then
    -- ese lead TIENE contratos PEN? comprueba en crudo antes de acusar al cable
    if exists (select 1 from crm.leads l join public.contratos c on c.cliente_id=l.perfil_id
               where l.perfil_id is not null and not c.es_demo and c.moneda='PEN') then
      v_falla := v_falla || 'reuniones/el-cable-devuelve-vacio ';
    end if;
  end if;

  if v_falla <> '' then
    raise exception 'ORACULO F4.i: fallo en [%]: NO se publica', v_falla;
  end if;
  raise notice 'ORACULO F4.i OK: dashboard identico; reuniones identica en todo lo demas; el cable de capital funciona (lead de prueba: PEN %)', v_cap;
end
$despues$;

commit;
