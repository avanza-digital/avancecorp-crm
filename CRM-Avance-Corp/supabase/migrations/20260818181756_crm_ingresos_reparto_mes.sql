-- Rosa / Coordinacion: lectura historica de INGRESOS al CRM por mes.
-- Version aplicada en produccion: 20260818181756.
--
-- Responde una sola pregunta operativa: cuantos leads llegaron en el mes y
-- como se distribuyen por semanas calendario (lunes-domingo, recortadas al
-- borde del mes). Cuenta por creado_en aunque el lead ya haya sido repartido o
-- descartado: una entrada historica no desaparece cuando Rosa trabaja la cola.
--
-- No devuelve PII ni abre SELECT sobre crm.leads. El unico acceso desde la Data
-- API es esta RPC SECURITY DEFINER, con el mismo gate vivo que las demas
-- lecturas de reparto.

begin;

create function crm.ingresos_reparto_mes_fn(p_mes date)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_ahora timestamptz := now();
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_fin date;
  v_hasta date;
  v_inicio_ts timestamptz;
  v_fin_ts timestamptz;
  v_payload jsonb;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver los ingresos de reparto'
      using errcode = '42501';
  end if;

  if p_mes is null or p_mes <> date_trunc('month', p_mes)::date then
    raise exception 'El mes debe enviarse como su primer dia'
      using errcode = '22023';
  end if;

  if p_mes > v_mes_actual then
    raise exception 'El mes no puede ser posterior al mes actual de Lima'
      using errcode = '22023';
  end if;

  v_fin := (p_mes + interval '1 month')::date;
  v_hasta := least(v_fin - 1, (v_ahora at time zone 'America/Lima')::date);
  v_inicio_ts := p_mes::timestamp at time zone 'America/Lima';
  v_fin_ts := v_fin::timestamp at time zone 'America/Lima';

  with semanas as materialized (
    select
      row_number() over (order by s.inicio_semana)::int as numero,
      greatest(s.inicio_semana::date, p_mes) as desde,
      least((s.inicio_semana + interval '6 days')::date, v_fin - 1, v_hasta) as hasta
    from generate_series(
      date_trunc('week', p_mes::timestamp),
      date_trunc('week', v_hasta::timestamp),
      interval '1 week'
    ) as s(inicio_semana)
  ),
  conteos as materialized (
    select
      count(*)::int as total,
      (l.creado_en at time zone 'America/Lima')::date as dia_lima
    from crm.leads l
    where l.creado_en >= v_inicio_ts
      and l.creado_en < v_fin_ts
    group by (l.creado_en at time zone 'America/Lima')::date
  ),
  total_mes as (
    select coalesce(sum(c.total), 0)::int as total
    from conteos c
  ),
  semanas_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'numero', s.numero,
          'desde', s.desde,
          'hasta', s.hasta,
          'total', coalesce((
            select sum(c.total)::int
            from conteos c
            where c.dia_lima between s.desde and s.hasta
          ), 0)
        )
        order by s.numero
      ),
      '[]'::jsonb
    ) as semanas
    from semanas s
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'mes', p_mes,
    'total', (select t.total from total_mes t),
    'semanas', (select sj.semanas from semanas_json sj)
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.ingresos_reparto_mes_fn(date) is
  'Ingresos historicos al CRM por mes de Lima y semanas lunes-domingo recortadas al mes. Cuenta creado_en aunque el lead ya no este en cola. Sin PII. Solo Coordinacion/Gerencia activas.';

revoke all on function crm.ingresos_reparto_mes_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.ingresos_reparto_mes_fn(date) to authenticated;

commit;
