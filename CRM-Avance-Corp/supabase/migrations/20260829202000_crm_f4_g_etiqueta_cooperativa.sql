-- P-055 FASE 4.g — La cooperativa se ETIQUETA como cooperativa en el capital
-- del mes. La 4.f la sumo bien (el delta al centimo lo probo) pero el
-- `coalesce(e.categoria, ...)` nunca llegaba al fallback: la pierna coop trae
-- categoria 'nuevo' NO NULA, y la fila se plegaba a esa etiqueta. La cifra era
-- correcta; la etiqueta no. El CASE decide por TIPO, que es lo que corresponde.

begin;
set local lock_timeout = '5s';

do $pre$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
  where p.oid='crm.metricas_capital_mes_fn(integer)'::regprocedure;
  if strpos((select prosrc from pg_proc where oid='crm.metricas_capital_mes_fn(integer)'::regprocedure),
            'coalesce(e.categoria, case when e.tipo=''cooperativa''') = 0 then
    raise exception 'La forma esperada de 4.f no esta (huella %): ABORTA', v_h;
  end if;
end
$pre$;

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
  select
    e.mes_comercial as mes,
    e.moneda,
    case when e.tipo = 'cooperativa' then 'cooperativa' else e.categoria end as categoria,
    count(*)::bigint  as contratos,
    sum(e.monto)      as capital_colocado
  from private.capital_episodios(
         ((date_trunc('month', current_date)
            - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date::timestamp
           at time zone 'America/Lima'),
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  left join public.perfiles cli on cli.id = e.cliente_id
  cross join ambito a
  where e.medida = 'stock'
    and (e.tipo like 'contrato_%' or e.tipo = 'cooperativa')
    and (
      a.es_global
      or (e.tipo like 'contrato_%' and (
            cli.asesor_perfil_id = any (a.ids)
            or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 2, 3;
$fn$;

do $post$
declare v_uid uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'; v_coop numeric; v_esp numeric;
begin
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid, 'role','authenticated')::text);
  set local role authenticated;
  select coalesce(sum(capital_colocado),0) into v_coop
  from crm.metricas_capital_mes_fn(1)
  where mes=date '2026-08-01' and moneda='PEN' and categoria='cooperativa';
  reset role;
  select coalesce(sum(monto),0) into v_esp from crm.cierres_externos
  where anulado_en is null and moneda='PEN'
    and date_trunc('month', creado_en at time zone 'America/Lima') = date '2026-08-01';
  if v_coop is distinct from v_esp then
    raise exception 'POSTFLIGHT: la etiqueta cooperativa suma % y se esperaba %', v_coop, v_esp;
  end if;
  raise notice 'POSTFLIGHT OK: agosto muestra S/ % bajo la etiqueta cooperativa', v_coop;
end
$post$;

commit;
