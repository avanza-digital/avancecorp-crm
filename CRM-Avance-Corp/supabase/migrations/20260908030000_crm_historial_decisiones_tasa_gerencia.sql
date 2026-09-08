-- Historial completo y paginado de las decisiones de tasa tomadas por el usuario de Gerencia.
-- No reutiliza solicitudes_tasa_fn: esa RPC es una bandeja operativa y recorta terminales a siete días.

create index if not exists solicitudes_tasa_resuelta_por_en_idx
  on crm.solicitudes_tasa (resuelta_por, resuelta_en desc, id desc)
  where resuelta_por is not null and resuelta_en is not null;

create or replace function crm.historial_decisiones_tasa_gerencia_fn(
  p_periodo_dias integer default 30, p_decision text default null, p_busqueda text default null, p_limite integer default 10,
  p_cursor_resuelta_en timestamptz default null, p_cursor_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_uid uuid := (select auth.uid());
  v_limite integer := least(greatest(coalesce(p_limite, 10), 1), 25);
  v_periodo integer := coalesce(p_periodo_dias, 30);
  v_busqueda text := nullif(left(btrim(coalesce(p_busqueda, '')), 100), '');
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then raise exception 'Solo Gerencia consulta su historial de decisiones de tasa' using errcode = '42501'; end if;
  if v_periodo not in (0, 7, 30, 90) then raise exception 'Período inválido' using errcode = '22023'; end if;
  if p_decision is not null and p_decision not in ('aprobada', 'aprobada_con_tope', 'rechazada') then raise exception 'Decisión inválida' using errcode = '22023'; end if;
  if (p_cursor_resuelta_en is null) <> (p_cursor_id is null) then raise exception 'Cursor incompleto' using errcode = '22023'; end if;

  return (
    with resueltas as (
      select s.*,
        case when s.tasa_maxima_autorizada is null then 'rechazada' when s.tasa_maxima_autorizada = s.tasa_solicitada then 'aprobada' else 'aprobada_con_tope' end as decision_gerencia,
        case when s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista') and s.vence_en < statement_timestamp() then 'vencida' else s.estado end as estado_actual,
        coalesce(cl.nombre_completo, 'Cliente') as cliente_nombre, coalesce(so.nombre_completo, 'Sin nombre') as solicitante_nombre,
        coalesce(re.nombre_completo, 'Gerencia') as resolutor_nombre, c.numero_contrato as contrato_numero, p.version as politica_version
      from crm.solicitudes_tasa s
      left join public.perfiles cl on cl.id = s.cliente_id
      left join public.perfiles so on so.id = s.solicitada_por
      left join public.perfiles re on re.id = s.resuelta_por
      left join public.contratos c on c.id = s.contrato_id
      left join crm.politica_rentabilidad p on p.id = s.politica_id
      where s.resuelta_por = v_uid and s.resuelta_en is not null
    ), filtradas as (
      select r.* from resueltas r
      where (v_periodo = 0 or r.resuelta_en >= statement_timestamp() - make_interval(days => v_periodo))
        and (p_decision is null or r.decision_gerencia = p_decision)
        and (v_busqueda is null or r.cliente_nombre ilike '%' || v_busqueda || '%' or r.solicitante_nombre ilike '%' || v_busqueda || '%')
    ), pagina_mas_uno as (
      select f.* from filtradas f where p_cursor_resuelta_en is null or (f.resuelta_en, f.id) < (p_cursor_resuelta_en, p_cursor_id)
      order by f.resuelta_en desc, f.id desc limit v_limite + 1
    ), pagina as (
      select p.* from pagina_mas_uno p order by p.resuelta_en desc, p.id desc limit v_limite
    )
    select jsonb_build_object(
      'version', 1, 'total', (select count(*) from filtradas),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', x.id, 'decision', x.decision_gerencia, 'estado_actual', x.estado_actual, 'categoria', x.categoria,
        'cliente_nombre', x.cliente_nombre, 'contrato_origen_numero', x.contrato_origen_numero, 'contrato_numero', x.contrato_numero,
        'capital', x.capital, 'moneda', x.moneda, 'modalidad', x.modalidad, 'tipo_interes', x.tipo_interes,
        'fecha_inicio', x.fecha_inicio, 'fecha_vencimiento', x.fecha_vencimiento, 'tasa_base', x.tasa_base, 'regla_base', x.regla_base,
        'tasa_solicitada', x.tasa_solicitada, 'tasa_maxima_autorizada', x.tasa_maxima_autorizada, 'motivo', x.motivo,
        'motivo_resolucion', x.motivo_resolucion, 'solicitante_nombre', x.solicitante_nombre, 'solicitada_en', x.solicitada_en,
        'vence_en', x.vence_en, 'resolutor_nombre', x.resolutor_nombre, 'resuelta_en', x.resuelta_en,
        'respondida_por_analista_en', x.respondida_por_analista_en, 'consumida_en', x.consumida_en, 'politica_version', x.politica_version
      ) order by x.resuelta_en desc, x.id desc) from pagina x), '[]'::jsonb),
      'siguiente_cursor', case when (select count(*) from pagina_mas_uno) > v_limite then
        (select jsonb_build_object('resuelta_en', x.resuelta_en, 'id', x.id) from pagina x order by x.resuelta_en asc, x.id asc limit 1)
      else null end
    )
  );
end;
$function$;

revoke all on function crm.historial_decisiones_tasa_gerencia_fn(integer, text, text, integer, timestamptz, uuid) from public, anon, service_role;
grant execute on function crm.historial_decisiones_tasa_gerencia_fn(integer, text, text, integer, timestamptz, uuid) to authenticated;
comment on function crm.historial_decisiones_tasa_gerencia_fn(integer, text, text, integer, timestamptz, uuid) is
  'Historial paginado de las decisiones de tasa tomadas por la Gerencia autenticada. Filtros y cursor estable resuelta_en+id; máximo 25 filas.';
