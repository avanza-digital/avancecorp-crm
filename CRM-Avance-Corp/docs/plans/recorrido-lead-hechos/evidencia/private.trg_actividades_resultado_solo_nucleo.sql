CREATE OR REPLACE FUNCTION private.trg_actividades_resultado_solo_nucleo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_meta jsonb := coalesce(new.metadata, '{}'::jsonb);
begin
  -- Los escritores internos (auth.uid() nulo: backfills, restauraciones del
  -- banco) quedan exentos, como en trg_gestion_lead_serializada. Toda sesión
  -- con identidad, incluida service_role con JWT, pasa por el GUC.
  if (select auth.uid()) is null then
    return new;
  end if;
  -- Claves EXCLUSIVAS del resultado de llamada (ningún escritor vivo las usa:
  -- medido en el banco el 20/09; `tarea_id` la escribe crm.cerrar_reunion y
  -- `descartado`/`siguiente_id`/`motivo_descarte` son nombres genéricos, por
  -- eso NO se reservan). El evento propio se reserva siempre.
  if (v_meta ?| array['resultado', 'submotivo', 'intento_n', 'etapa_al_descartar', 'no_insista',
                      'deshecho_en', 'deshecho_por', 'descarte_revertido', 'cita_no_restaurada']
      or v_meta->>'evento' in ('resultado_llamada', 'resultado_deshecho'))
     and coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off') <> 'on' then
    raise exception 'El resultado de una llamada solo lo escribe crm.registrar_llamada_v3 (y crm.deshacer_resultado_llamada)'
      using errcode = '42501';
  end if;
  -- Append-only incluso bajo el GUC: un resultado escrito no se reescribe (el
  -- deshacer AÑADE deshecho_en; nunca cambia resultado ni submotivo).
  if tg_op = 'UPDATE' and old.metadata ? 'resultado'
     and (new.metadata->>'resultado' is distinct from old.metadata->>'resultado'
          or new.metadata->>'submotivo' is distinct from old.metadata->>'submotivo') then
    raise exception 'El resultado de una llamada no se reescribe' using errcode = '42501';
  end if;
  return new;
end;
$function$
