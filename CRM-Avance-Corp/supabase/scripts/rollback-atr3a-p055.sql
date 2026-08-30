-- MARCHA ATRAS de P-055 ATR-3a (lentes y ficha al analista).
-- Repone los TRES cuerpos originales (literales de maquina del 31/08).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- 0) PREFLIGHT anti-pisado: solo se pisa el estado ATR-3a (cuerpo Y atributos).
do $$
declare
  v_fn constant text[][] := array[
    array['crm.metricas_capital_mes_fn(integer)',  'b21f9a7a134f76f9f2eabfe75578cbca'],
    array['crm.metricas_vencimientos_fn(integer)', '54a9bf11bb4e0bbf0fc4d7c12bed7fcb'],
    array['crm.atribucion_contrato_fn(uuid)',      '1eccb3a1ff8b73e91f2f7870d08f83e8']
  ];
  v_fila text[]; v_h text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'rollback ATR-3a: % NO esta en el estado ATR-3a (huella %) — regenerar el rollback', v_fila[1], v_h;
    end if;
    if not exists (select 1 from pg_proc p
      where p.oid = v_fila[1]::regprocedure
        and p.prosecdef and p.provolatile = 's'
        and p.proconfig::text = '{"search_path=\"\""}'
        and p.proowner = 'postgres'::regrole
        and p.prolang = (select oid from pg_language where lanname = 'sql')
        and not p.proisstrict and p.proparallel = 'u'
        and not p.proleakproof and p.procost = 100) then
      raise exception 'rollback ATR-3a: los ATRIBUTOS de % no son los del estado ATR-3a', v_fila[1];
    end if;
  end loop;
end $$;

CREATE OR REPLACE FUNCTION crm.metricas_capital_mes_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, moneda text, categoria text, contratos bigint, capital_colocado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION crm.metricas_vencimientos_fn(p_dias integer DEFAULT 90)
 RETURNS TABLE(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
         '-infinity'::timestamptz,
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  left join public.perfiles cli on cli.id = e.cliente_id
  cross join ambito a
  where e.medida = 'stock'
    and ((e.tipo like 'contrato_%' and e.estado = 'activo')
         or (e.tipo = 'cooperativa' and e.estado = 'vigente'))
    and e.fecha_vencimiento >= current_date
    and e.fecha_vencimiento <  current_date + least(greatest(p_dias, 1), 366)
    and (
      a.es_global
      or (e.tipo like 'contrato_%' and (
            cli.asesor_perfil_id = any (a.ids)
            or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2
  order by 1, 2;
$function$;

CREATE OR REPLACE FUNCTION crm.atribucion_contrato_fn(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    -- La MISMA regla de visibilidad que ya gobierna los contratos del CRM: se
    -- pregunta a la vista viva en vez de copiar su `where`.
    when not exists (
      select 1 from crm.contratos_cartera v where v.id = p_contrato_id
    ) then null
    else (
      select jsonb_build_object(
        'contrato_id',   c.id,
        'analista_id',   c.analista_cierre_id,
        'analista_nombre', pa.nombre_completo,
        'es_demo',       c.es_demo,
        'registrado_por', pr.nombre_completo,
        'reasignaciones', case
          -- El historial con motivos, solo para la autoridad o el propio
          -- analista (A3). Mismo conjunto que la policy de la tabla, con P04.
          when (((select public.es_gestor_cartera())
                 or coalesce(private.rol_crm((select auth.uid())) = 'gerencia', false))
                and not (select private.membresia_crm_revocada()))
               or c.analista_cierre_id = (select auth.uid())
          then coalesce((
            select jsonb_agg(jsonb_build_object(
              'cuando',  r.reasignado_en,
              'de',      pde.nombre_completo,
              'a',       pa2.nombre_completo,
              'motivo',  r.motivo,
              'por',     ppor.nombre_completo
            ) order by r.reasignado_en desc)
            from crm.reasignaciones_analista r
            left join public.perfiles pde  on pde.id  = r.analista_de
            left join public.perfiles pa2  on pa2.id  = r.analista_a
            left join public.perfiles ppor on ppor.id = r.reasignado_por
            where r.contrato_id = c.id
          ), '[]'::jsonb)
          else '[]'::jsonb
        end
      )
      from public.contratos c
      left join public.perfiles pa on pa.id = c.analista_cierre_id
      left join public.perfiles pr on pr.id = c.creado_por
      where c.id = p_contrato_id
    )
  end;
$function$;

do $$
declare
  v_fn constant text[][] := array[
    array['crm.metricas_capital_mes_fn(integer)',  'd8b5d898d6eb7b3d3ef3f287c3264707', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.metricas_vencimientos_fn(integer)', 'cf1a07e39e82272db01c6b86482ba612', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.atribucion_contrato_fn(uuid)',      'b95687bb1e95ba78adc832e65a8b5d5b', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}']
  ];
  v_fila text[]; v_h text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'rollback ATR-3a: % no volvio al byte (huella %)', v_fila[1], v_h;
    end if;
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[3] then
      raise exception 'rollback ATR-3a: proacl de % no es el original', v_fila[1];
    end if;
  end loop;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
