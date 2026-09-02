-- P-055 FASE 4.a — Las pantallas de gerencia consumen el nucleo.
--
-- Dos funciones reescritas de cuerpo entero: crm.metricas_capital_mes_fn y
-- crm.metricas_vencimientos_fn. Conservan SU firma, SU gate y SU recorte de
-- visibilidad (por asesor del cliente — semantica viva); lo unico que cambia
-- es DE DONDE salen los hechos: de private.capital_episodios.
--
-- TOCA funciones que sirven pantallas VIVAS de gerencia: con permiso explicito
-- de Miguel (orden del 29/08: «quiero ver todo ya... crear el sistema»).
--
-- ANCLADO AL VIVO (hallazgo A1 del auditor RLS): las dos funciones no tienen
-- CREATE en el repo, asi que el preflight fija la huella md5 del cuerpo VIVO
-- leido hoy de produccion; si difiere, ABORTA. El predicado de ambito
-- (asesor_perfil_id, con caida a creado_por para clientes sin asesor), los
-- defaults (12/90) y los topes (60/366) estan COPIADOS de ese cuerpo, no
-- reescritos de memoria. UNICO cambio deliberado ademas de la fuente de los
-- hechos: el search_path pasa de 'private, public, crm' a '' (endurecimiento;
-- todas las referencias del cuerpo nuevo van calificadas).
--
-- EL ORACULO VIAJA DENTRO: antes de reemplazar nada, esta migracion captura
-- el payload VIVO de cada funcion (como gerencia Y como un vendedor real, en
-- ESTA transaccion), aplica el reemplazo, vuelve a capturar, y ABORTA si un
-- solo byte difiere. La paridad no es una promesa: es la condicion de commit.

begin;

set local lock_timeout = '5s';

do $preflight$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'crm.metricas_capital_mes_fn(integer)'::regprocedure;
  if v_h <> '964aac0074889aace136bfd80ab5e6a0' then
    raise exception 'metricas_capital_mes_fn cambio (huella %): ABORTA', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid = 'crm.metricas_vencimientos_fn(integer)'::regprocedure;
  if v_h <> '55c3eda547dc6e5767937e3a7150537b' then
    raise exception 'metricas_vencimientos_fn cambio (huella %): ABORTA', v_h;
  end if;
end
$preflight$;

-- ---------------------------------------------------- ORACULO: FOTO "ANTES" --
create temp table zz_f4a_antes (quien text, fn text, huella text) on commit drop;

do $antes$
declare v_uid_ger uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'; v_uid_vend uuid;
        v_uid_sup uuid; h1 text; h2 text; h3 text; h4 text; h5 text;
begin
  -- A2 del auditor: el vendedor fotografiado es EL DE MAS CONTRATOS activos de
  -- su cartera (una foto vacia probaria '[]'='[]'); y se fotografia tambien un
  -- SUPERVISOR (el recorte de subarbol es el mas delicado).
  select cli.asesor_perfil_id into v_uid_vend
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  join crm.equipo e on e.perfil_id = cli.asesor_perfil_id and e.activo and e.rol_crm='vendedor'
  where not c.es_demo
  group by cli.asesor_perfil_id
  order by count(*) desc limit 1;
  select e.perfil_id into v_uid_sup from crm.equipo e
  where e.activo and e.rol_crm='supervisor'
  order by (select count(*) from crm.equipo h where h.supervisor_id = e.perfil_id) desc
  limit 1;
  create temp table zz_f4a_vend on commit drop as
  select v_uid_vend as uid, v_uid_sup as sup;

  -- ⚠️ la temp table del duenyo NO es escribible bajo `set role`: capturar en
  -- variables con el rol puesto y escribir DESPUES del reset (trampa pagada).
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_ger, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda, t.categoria)::text,'[]'))
    into h1 from crm.metricas_capital_mes_fn(24) t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda)::text,'[]'))
    into h2 from crm.metricas_vencimientos_fn(180) t;
  reset role;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_vend, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda, t.categoria)::text,'[]'))
    into h3 from crm.metricas_capital_mes_fn(24) t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda)::text,'[]'))
    into h4 from crm.metricas_vencimientos_fn(180) t;
  reset role;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_sup, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda, t.categoria)::text,'[]'))
    into h5 from crm.metricas_capital_mes_fn(24) t;
  reset role;

  -- la foto del vendedor tiene que tener CARNE: md5('[]') es paridad trivial
  --
  -- 🔧 PARCHE DE BANCO (divergencia declarada en banco-parches/DIVERGENCIAS.md).
  --    En un banco recien nacido no hay NI UN contrato, asi que las tres fotos
  --    son '[]' y este oraculo no puede probar nada. Se tolera SOLO el caso
  --    EXACTAMENTE vacio — cero contratos no-demo en toda la base. Con datos
  --    parciales vuelve a abortar, que es justo cuando el oraculo si tendria
  --    algo que decir. La LOGICA del reemplazo y la comparacion antes/despues
  --    de mas abajo siguen INTACTAS.
  if h3 = md5('[]') then
    if (select count(*) from public.contratos where not es_demo) = 0 then
      raise notice 'PARCHE DE BANCO · ORACULO F4.a VACUO: 0 contratos no-demo; la paridad se cumple sobre el conjunto vacio. Se probo en PRODUCCION, no aqui.';
    else
      raise exception 'ORACULO F4.a: la foto del vendedor esta vacia — elegir otro actor';
    end if;
  end if;

  insert into zz_f4a_antes values
    ('gerencia','capital_mes',h1), ('gerencia','vencimientos',h2),
    ('vendedor','capital_mes',h3), ('vendedor','vencimientos',h4),
    ('supervisor','capital_mes',h5);
end
$antes$;

-- -------------------------------------------------------------- EL REEMPLAZO --
create or replace function crm.metricas_capital_mes_fn(p_meses integer default 12)
returns table(mes date, moneda text, categoria text, contratos bigint, capital_colocado numeric)
language sql
stable
security definer
set search_path to ''
as $fn$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  -- Los hechos salen del NUCLEO (pierna contrato); el recorte por asesor del
  -- cliente es de ESTA pantalla y se aplica aqui, como siempre lo hizo.
  select
    e.mes_comercial as mes,
    e.moneda,
    e.categoria,
    count(*)::bigint  as contratos,
    sum(e.monto)      as capital_colocado
  from private.capital_episodios(
         ((date_trunc('month', current_date)
            - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date::timestamp
           at time zone 'America/Lima'),
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  join public.perfiles cli on cli.id = e.cliente_id
  cross join ambito a
  where e.tipo like 'contrato_%'
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 2, 3;
$fn$;

create or replace function crm.metricas_vencimientos_fn(p_dias integer default 90)
returns table(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
language sql
stable
security definer
set search_path to ''
as $fn$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', e.fecha_vencimiento))::date as mes,
    e.moneda,
    count(*)::bigint as contratos_por_vencer,
    sum(e.monto)     as capital_por_vencer
  from private.capital_episodios(
         (date '2020-01-01')::timestamp at time zone 'America/Lima',
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  join public.perfiles cli on cli.id = e.cliente_id
  cross join ambito a
  where e.tipo like 'contrato_%'
    and e.estado = 'activo'
    and e.fecha_vencimiento >= current_date
    and e.fecha_vencimiento <  current_date + least(greatest(p_dias, 1), 366)
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2
  order by 1, 2;
$fn$;

-- --------------------------------------------------- ORACULO: FOTO "DESPUES" --
do $despues$
declare v_uid_ger uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'; v_uid_vend uuid;
        v_uid_sup uuid; h1 text; h2 text; h3 text; h4 text; h5 text; v_falla text := '';
begin
  select uid, sup into v_uid_vend, v_uid_sup from zz_f4a_vend;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_ger, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda, t.categoria)::text,'[]'))
    into h1 from crm.metricas_capital_mes_fn(24) t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda)::text,'[]'))
    into h2 from crm.metricas_vencimientos_fn(180) t;
  reset role;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_vend, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda, t.categoria)::text,'[]'))
    into h3 from crm.metricas_capital_mes_fn(24) t;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda)::text,'[]'))
    into h4 from crm.metricas_vencimientos_fn(180) t;
  reset role;

  if h1 <> (select huella from zz_f4a_antes where quien='gerencia' and fn='capital_mes') then v_falla := v_falla || 'capital_mes/gerencia '; end if;
  if h2 <> (select huella from zz_f4a_antes where quien='gerencia' and fn='vencimientos') then v_falla := v_falla || 'vencimientos/gerencia '; end if;
  if h3 <> (select huella from zz_f4a_antes where quien='vendedor' and fn='capital_mes') then v_falla := v_falla || 'capital_mes/vendedor '; end if;
  if h4 <> (select huella from zz_f4a_antes where quien='vendedor' and fn='vencimientos') then v_falla := v_falla || 'vencimientos/vendedor '; end if;

  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_sup, 'role','authenticated')::text);
  set local role authenticated;
  select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.mes, t.moneda, t.categoria)::text,'[]'))
    into h5 from crm.metricas_capital_mes_fn(24) t;
  reset role;
  if h5 <> (select huella from zz_f4a_antes where quien='supervisor' and fn='capital_mes') then v_falla := v_falla || 'capital_mes/supervisor '; end if;

  if v_falla <> '' then
    raise exception 'ORACULO F4.a: el payload cambio en [%]: la migracion NO se publica', v_falla;
  end if;
  raise notice 'ORACULO F4.a OK: paridad byte a byte en gerencia y vendedor';
end
$despues$;

commit;
;
