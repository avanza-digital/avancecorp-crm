-- Solo en la branch autorizada. Ensayo transaccional, termina en ROLLBACK.
-- Dobla únicamente el reloj de las dos guardas temporales de cerrar_periodo
-- a 11/11/2026; su cálculo, permisos, sellado y lecturas son los reales.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='90s';
create temp table resultados(caso text);
create function pg_temp.exigir(ok boolean,motivo text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FALLA: %',motivo; end if;
  insert into resultados values(motivo);
end $$;
select set_config('request.jwt.claim.sub',
  (select perfil_id::text from crm.equipo where rol_crm='gerencia' and activo order by perfil_id limit 1),true);
create temp table sellos_anteriores as select to_jsonb(p) j from crm.periodos_cerrados p;
create temp table fotos_anteriores as select to_jsonb(f) j from crm.cierre_mes_vendedor f;
create temp table vivo as select crm.conversion_mensual_fn('2026-10-01') j;
do $reloj$
declare original text:=pg_get_functiondef('crm.cerrar_periodo(date)'::regprocedure); simulado text;
begin
  if position('v_mes_actual  date := date_trunc(''month'', now() at time zone ''America/Lima'')::date;' in original)=0
    or position('if now() < v_ventana then' in original)=0 then
    raise exception 'El cierre cambió; revisar el doble del reloj';
  end if;
  simulado:=replace(original,
    'v_mes_actual  date := date_trunc(''month'', now() at time zone ''America/Lima'')::date;',
    'v_mes_actual  date := date ''2026-11-01'';');
  simulado:=replace(simulado,'if now() < v_ventana then',
    'if timestamptz ''2026-11-11 12:00 America/Lima'' < v_ventana then');
  execute simulado;
end $reloj$;
select crm.cerrar_periodo('2026-10-01')->>'ok' as cierre_ok;
select pg_temp.exigir((select numerador=4 and divisor=67 and conversion_pct=5.97
  and (cartera->>'conversiones_upgrade')::int=2
  and (cartera->>'conversiones_renovacion')::int=0
  and (cartera->>'operaciones_renovacion')::int=1
  and (cartera->>'capital_renovado_usd')::numeric=5000
  and (cartera->>'capital_adicional_usd')::numeric=7000
  from crm.cierre_mes_vendedor where periodo='2026-10-01'
    and vendedor_id='2c10b18a-a15d-4952-952b-c4ab91b96153'),
  '01: cierre conserva el punto de Vladimir y el desglose real');
select pg_temp.exigir(not exists(select 1 from vivo v,jsonb_array_elements(v.j->'responsables') r
  left join crm.cierre_mes_vendedor f on f.periodo='2026-10-01' and f.vendedor_id=(r->>'vendedor_id')::uuid
  where (f.vendedor_id is not null and (f.numerador<>(r->>'numerador')::numeric
    or f.divisor<>(r->>'divisor')::int or f.conversion_pct is distinct from (r->>'conversion_pct')::numeric))
    or (f.vendedor_id is null and (
      (r->>'divisor')::int<>0 or (r->>'numerador')::numeric<>0
      or (r->>'cierres_no_referidos')::int<>0 or (r->>'cierres_referidos')::int<>0
      or exists(select 1 from jsonb_each(r->'cartera') c where c.value::text::numeric<>0)))),
  '02: la foto coincide por analista; permite omitir perfiles sin metas ni actividad como hace el cierre vigente');
select pg_temp.exigir((select ponderacion_renovacion=0 and ponderacion_referido=1 and tope_referidos_pct=15
  from crm.periodos_cerrados where periodo='2026-10-01'),
  '03: el sello conserva ambos pesos y el límite de referido');
\ir nucleo-anterior.sql
select pg_temp.exigir((select (r->>'numerador')::numeric=4 and (r->>'conversion_pct')::numeric=5.97
  from jsonb_array_elements(crm.conversion_mensual_fn('2026-10-01')->'responsables') r
  where r->>'vendedor_id'='2c10b18a-a15d-4952-952b-c4ab91b96153'),
  '04: la puerta oficial sigue leyendo la foto aun con el núcleo anterior');
select pg_temp.exigir((select numerador=3 from private.conversion_mensual_por_vendedor(
  '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima',true,'{}',1)
  where analista_id='2c10b18a-a15d-4952-952b-c4ab91b96153'),
  '05: el control realmente distingue foto congelada de recálculo vivo');
select pg_temp.exigir((crm.metricas_conversiones_fn('2026-10-01','2026-10-14')#>>'{nucleo,numerador}')::numeric=51.05
  and (crm.conversion_divisor_coordinacion_fn('2026-10-01')#>>'{empresa,numerador}')::numeric=51.05,
  '06: métricas y Coordinación sirven el total congelado');
select pg_temp.exigir(not exists(
  (select j from sellos_anteriores except all select to_jsonb(p) from crm.periodos_cerrados p where periodo<'2026-10-01')
  union all (select to_jsonb(p) from crm.periodos_cerrados p where periodo<'2026-10-01' except all select j from sellos_anteriores)
  union all (select j from fotos_anteriores except all select to_jsonb(f) from crm.cierre_mes_vendedor f where periodo<'2026-10-01')
  union all (select to_jsonb(f) from crm.cierre_mes_vendedor f where periodo<'2026-10-01' except all select j from fotos_anteriores)),
  '07: todos los cierres y fotos anteriores permanecen idénticos');
select jsonb_build_object('estado','PASS','reloj_simulado','2026-11-11','comprobaciones',count(*),'casos',jsonb_agg(caso order by caso)) from resultados;
rollback;
