-- POBLAR (ronda 4, P2-5): tras el montaje y la migración, deja cancelaciones y corridas REALES antes de revertir.
-- Lo arma `armar-ensayo.mjs --reversa-poblada` (montaje + migración + este archivo + reversa + `reversa-poblada-oraculo.sql`),
-- siempre dentro de una transacción que termina en rollback. NUNCA contra producción.
do $poblar$
declare
  v_res text;
  v_j jsonb;
  v_motivos jsonb;
begin
  -- Un alta real por la puerta v2 con N1 (clave de idempotencia = S16): cancela S1 y S2 al instante.
  v_res := pg_temp.llamar(pg_temp.g('v1'),
    pg_temp.contrato(pg_temp.g('c1'), pg_temp.g('v1'), current_setting('ensayo.n1')) || jsonb_build_object('clave_idempotencia', pg_temp.g('s16')));
  if v_res not like 'ok|%' then
    raise exception 'POBLAR: el alta con N1 no entró: %', v_res;
  end if;
  -- Una corrida nocturna: S14 (número usado), S10, S11 y S18 (30 días); S8 y S17 rechazadas.
  v_j := private.solicitudes_desechar_ciclo(now(), 30, 200);
  perform set_config('ensayo.poblada.corrida', v_j ->> 'corrida_id', true);
  select jsonb_object_agg(s.id::text, s.cancelacion_motivo) into v_motivos
    from crm.inversion_solicitudes s join ensayo_siembra e on e.id = s.id
   where s.estado = 'cancelada' and s.cancelacion_motivo is not null;
  perform set_config('ensayo.poblada.motivos', coalesce(v_motivos, '{}'::jsonb)::text, true);
  -- Ronda 5 (Codex r2, P3): lo que se pierde en la fila al revertir, COMPLETO, para exigir después igualdad exacta con audit_log:
  -- por solicitud, motivo y cancelacion_detalle enteros; de la corrida, la fila entera (to_jsonb).
  perform set_config('ensayo.poblada.detalles',
    coalesce((select jsonb_object_agg(s.id::text, jsonb_build_object('motivo', s.cancelacion_motivo, 'detalle', s.cancelacion_detalle))
                from crm.inversion_solicitudes s join ensayo_siembra e on e.id = s.id
               where s.estado = 'cancelada' and s.cancelacion_motivo is not null), '{}'::jsonb)::text, true);
  perform set_config('ensayo.poblada.corrida_fila',
    (select to_jsonb(c) from crm.solicitudes_desechadas_corridas c where c.id = (v_j ->> 'corrida_id')::uuid)::text, true);
  perform set_config('ensayo.poblada.preparadas',
    (select string_agg(s.id::text, ',' order by s.id) from crm.inversion_solicitudes s join ensayo_siembra e on e.id = s.id where s.estado = 'preparada'), true);
  perform set_config('ensayo.poblada.corridas_n', (select count(*) from crm.solicitudes_desechadas_corridas)::text, true);
  raise notice 'POBLAR: % canceladas con motivo (%), corrida %, % corridas',
    (select count(*) from jsonb_object_keys(coalesce(v_motivos, '{}'::jsonb))), coalesce(v_motivos, '{}'::jsonb), v_j ->> 'corrida_id',
    current_setting('ensayo.poblada.corridas_n');
end;
$poblar$;
