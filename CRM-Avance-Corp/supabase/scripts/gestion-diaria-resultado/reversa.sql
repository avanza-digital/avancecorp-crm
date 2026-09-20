-- Reversa de 20260920005000_crm_gestion_diaria_resultado_llamada.sql
-- (Gestión Diaria F2). Retira los objetos nuevos, devuelve el gate de F1 a su
-- nombre y el núcleo del historial por lead a su cuerpo del 19/09 (20260919185718).
-- La metadata ya escrita en crm.actividades (resultado, deshecho_en…) se
-- CONSERVA: es historia del lead, no se borra. Tras retirar el trigger, esas
-- claves siguen siendo válidas para el CHECK de forma mientras exista; si se
-- retira también el CHECK, no hay nada que las valide (queda anotado).
begin;
set local lock_timeout = '5s';
drop function if exists private.assert_gestion_diaria_resultado_mutantes();
drop function if exists private.assert_gestion_diaria();
drop function if exists private.assert_gestion_diaria_resultado();
alter function private.assert_gestion_diaria_registro() rename to assert_gestion_diaria;
comment on function private.assert_gestion_diaria() is
  'Trinquete de Gestión Diaria: puerta y núcleo INVOKER con search_path vacío, EXECUTE solo para authenticated, índice actividades_autor_fecha_idx presente, nombre_de_autor en su forma, y las policies actividades_select/leads_select selladas vía private.assert_actividades_de_lead_base().';
drop function if exists crm.deshacer_resultado_llamada(uuid);
drop function if exists crm.registrar_llamada_v3(uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean);
drop function if exists private.llamada_registrar(uuid, uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean);
drop trigger if exists trg_00_actividades_resultado_solo_nucleo on crm.actividades;
drop function if exists private.trg_actividades_resultado_solo_nucleo();
alter table crm.actividades drop constraint if exists actividades_resultado_llamada_forma;

-- Núcleo del historial por lead: cuerpo EXACTO de 20260919185718 (sin metadata).
create or replace function private.actividades_de_lead_core(
  p_lead uuid,
  p_limite integer,
  p_antes_de timestamptz,
  p_antes_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select a.id, a.lead_id, a.tipo, a.detalle, a.creado_por, a.creado_en
    from crm.actividades a
    where a.lead_id = p_lead
      and (
        p_antes_de is null
        or a.creado_en < p_antes_de
        or (a.creado_en = p_antes_de and a.id > p_antes_id)
      )
    order by a.creado_en desc, a.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pg.id,
          'lead_id', pg.lead_id,
          'tipo', pg.tipo,
          'detalle', pg.detalle,
          'autor_nombre', coalesce(private.nombre_de_autor(pg.creado_por), '—'),
          'creado_en', pg.creado_en
        )
        order by pg.creado_en desc, pg.id asc
      )
      from pagina pg
    ), '[]'::jsonb),
    -- Una sola pasada por el historial del lead para las tres señales
    -- (auditoría RLS del 19/09): bool_or/max filter, nunca count(.
    'senales', (
      select jsonb_build_object(
        'tiene_reunion_realizada', coalesce(bool_or(a.tipo = 'reunion_realizada'), false),
        'tiene_contacto', coalesce(bool_or(a.tipo in (
          'llamada_realizada', 'llamada_no_contestada',
          'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')), false),
        'ultima_conversacion_en', max(a.creado_en) filter (where a.tipo in (
          'llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'))
      )
      from crm.actividades a
      where a.lead_id = p_lead
    )
  );
$function$;
comment on function private.actividades_de_lead_core(uuid, integer, timestamptz, uuid) is
  'NÚCLEO: página keyset (creado_en desc, id asc) del historial de UN lead bajo la RLS del actor, más las señales «alguna vez» (reunión realizada, contacto, última conversación). Puro: sin auth ni autoridad propia.';

do $reversa$
begin
  if private.assert_gestion_diaria() not like 'OK%' then
    raise exception 'REVERSA: el gate de F1 no volvio a verde';
  end if;
  if md5(pg_get_functiondef('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)'::regprocedure))
     is distinct from 'ef77de1e7f58ee8abe294678a103785c' then
    raise exception 'REVERSA: el nucleo del historial no volvio a su cuerpo del 19/09';
  end if;
  perform private.assert_actividades_de_lead();
  perform private.assert_sla_comandos();
end;
$reversa$;
notify pgrst, 'reload schema';
commit;
