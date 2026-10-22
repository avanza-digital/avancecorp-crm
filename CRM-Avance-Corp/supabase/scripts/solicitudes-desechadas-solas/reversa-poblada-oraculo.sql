-- ORÁCULO de la reversa con datos poblados (ronda 4, P2-5). Corre DESPUÉS de `reversa.sql` dentro del ensayo armado por
-- `armar-ensayo.mjs --reversa-poblada`. Exige: las solicitudes que el CRM canceló SIGUEN canceladas (nunca se «des-cancela»); las
-- preparadas siguen preparadas; cada motivo perdido en la fila se recupera desde public.audit_log (el UPDATE auditado lleva
-- cancelacion_motivo y cancelacion_detalle en data_despues); la corrida borrada con la tabla se recupera desde public.audit_log
-- (el INSERT auditado); y no queda ninguna pieza, columna, tabla ni job. Termina SIEMPRE en excepción: ese es el veredicto.
do $rp$
declare
  v_motivos jsonb := current_setting('ensayo.poblada.motivos', true)::jsonb;
  v_detalles jsonb := coalesce(current_setting('ensayo.poblada.detalles', true), '{}')::jsonb;
  v_fila jsonb := nullif(current_setting('ensayo.poblada.corrida_fila', true), '')::jsonb;
  v_fallos text := '';
  v_n integer;
  r record;
begin
  if v_motivos is null or (select count(*) from jsonb_object_keys(v_motivos)) <> 6 then
    v_fallos := v_fallos || format('se esperaban 6 canceladas con motivo antes de revertir (S1, S2, S10, S11, S14, S18) y hay %s; ', coalesce((select count(*) from jsonb_object_keys(v_motivos)), 0));
  end if;
  for r in select key as id, value as motivo from jsonb_each_text(coalesce(v_motivos, '{}'::jsonb)) loop
    if (select s.estado from crm.inversion_solicitudes s where s.id = r.id::uuid) is distinct from 'cancelada' then
      v_fallos := v_fallos || format('la solicitud %s ya no está cancelada tras la reversa; ', r.id);
    end if;
    -- Ronda 5 (Codex r2, P3): igualdad EXACTA con lo capturado antes de revertir: el motivo y el cancelacion_detalle enteros
    -- tienen que estar, iguales, en el data_despues del UPDATE auditado de esa solicitud.
    if not exists (select 1 from public.audit_log a
                    where a.tabla = 'crm.inversion_solicitudes' and a.fila_id = r.id and a.operacion = 'UPDATE'
                      and a.data_despues ->> 'cancelacion_motivo' = (v_detalles -> r.id ->> 'motivo')
                      and a.data_despues -> 'cancelacion_detalle' = (v_detalles -> r.id -> 'detalle')
                      and (v_detalles -> r.id -> 'detalle') is not null and jsonb_typeof(v_detalles -> r.id -> 'detalle') = 'object') then
      v_fallos := v_fallos || format('el motivo «%s» y el detalle completo de %s no se recuperan iguales desde public.audit_log (capturado: %s); ', r.motivo, r.id, coalesce((v_detalles -> r.id)::text, '-'));
    end if;
  end loop;
  if current_setting('ensayo.poblada.preparadas', true) is distinct from
     (select string_agg(s.id::text, ',' order by s.id) from crm.inversion_solicitudes s join ensayo_siembra e on e.id = s.id where s.estado = 'preparada') then
    v_fallos := v_fallos || 'el conjunto de preparadas cambió con la reversa; ';
  end if;
  -- La fila ENTERA de la corrida (to_jsonb antes de revertir) tiene que ser igual al data_despues de su INSERT auditado
  -- (private.log_audit_crm solo enmascara columnas de crm.cuentas_bancarias: aquí no enmascara nada).
  if v_fila is null or not exists (select 1 from public.audit_log a
                  where a.tabla = 'crm.solicitudes_desechadas_corridas' and a.operacion = 'INSERT'
                    and a.fila_id = current_setting('ensayo.poblada.corrida', true)
                    and a.data_despues = v_fila) then
    v_fallos := v_fallos || format('la fila completa de la corrida %s no se recupera igual desde public.audit_log (capturada: %s); ', current_setting('ensayo.poblada.corrida', true), coalesce(left(v_fila::text, 300), '-'));
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace
              and p.proname in ('solicitud_desechar', 'solicitudes_desechar_por_contrato', 'solicitudes_desechar_ciclo', 'solicitud_cancelacion_vista'))
     or to_regclass('crm.solicitudes_desechadas_corridas') is not null
     or exists (select 1 from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and not a.attisdropped
                 and a.attname in ('cancelacion_motivo', 'cancelacion_detalle'))
     or (to_regclass('cron.job') is not null and exists (select 1 from cron.job where jobname = 'crm-solicitudes-desechar')) then
    v_fallos := v_fallos || 'quedó una pieza, la tabla, una columna o el job; ';
  end if;
  select count(*) into v_n from public.audit_log a where a.tabla = 'crm.inversion_solicitudes' and a.operacion = 'UPDATE'
    and a.data_despues ->> 'cancelacion_motivo' is not null and a.fila_id in (select e.id::text from ensayo_siembra e);
  raise exception E'REVERSA POBLADA %:\n%\nmotivos antes de revertir: %\nfilas de auditoría con motivo (sembradas): %\n(rollback a propósito — nada queda escrito)',
    case when v_fallos = '' then 'VERDE' else 'ROJO' end,
    case when v_fallos = '' then 'estados conservados, motivos y corrida recuperables desde public.audit_log, nada de lo nuevo presente' else v_fallos end,
    coalesce(v_motivos::text, '-'), v_n;
end;
$rp$;
