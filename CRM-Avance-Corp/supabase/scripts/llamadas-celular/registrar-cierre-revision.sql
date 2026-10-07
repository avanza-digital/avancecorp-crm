-- Registrar la duodécima después de aplicarla. No modifica funciones ni datos del CRM.
-- Fuente incrustada exacta (LF); valida los siete cuerpos antes de escribir el historial.
begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtext('crm_llamadas_celular_registro'));
do $registro$
declare
  fuente text := $migracion$-- Duodécima de llamadas: cierre del informe #190 (06/10/2026).
-- Veto completo por contacto, visibilidad del antiguo dueño, revalidación tras candado, reserva única del resultado
-- y evento_origen_id en las lecturas. Conserva firmas, dueños, ACL, el núcleo v4 y los once archivos anteriores.
-- Se instala antes de activar C1. Reversa: scripts/llamadas-celular/reversa-cierre-revision.sql, solo antes del uso.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
do $pre$
begin
  if to_regprocedure('private.llamada_celular_contacto_admitido(uuid,text[])') is not null then
    raise exception 'LLAMADAS_CIERRE_REVISION: ya está aplicada';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), 'estado_latido') = 0 then
    raise exception 'LLAMADAS_CIERRE_REVISION: falta la undécima';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)')) is distinct from '3088c2521455c1b0be1b413f2351a0a7' then
    raise exception 'LLAMADAS_CIERRE_REVISION: cuerpo previo inesperado en private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamada_celular_visible(uuid,uuid,uuid)')) is distinct from '19b7141c8da66db144e12b53ad5b7d97' then
    raise exception 'LLAMADAS_CIERRE_REVISION: cuerpo previo inesperado en private.llamada_celular_visible(uuid,uuid,uuid)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)')) is distinct from '764cd147f115a7b9961e1e7348adf0bc' then
    raise exception 'LLAMADAS_CIERRE_REVISION: cuerpo previo inesperado en private.llamada_celular_ingerir(uuid,jsonb,timestamptz)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.trg_llamadas_celular_enlaces_candado()')) is distinct from 'f2446aa037a0dfa799c6b028e6d175e3' then
    raise exception 'LLAMADAS_CIERRE_REVISION: cuerpo previo inesperado en private.trg_llamadas_celular_enlaces_candado()';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)')) is distinct from '00befedcbf3f3dfc2659d7403fa16e64' then
    raise exception 'LLAMADAS_CIERRE_REVISION: cuerpo previo inesperado en private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.actividades_con_llamada_celular(uuid,uuid[])')) is distinct from '6b7773aa9375262f6be9a37c451fa95c' then
    raise exception 'LLAMADAS_CIERRE_REVISION: cuerpo previo inesperado en private.actividades_con_llamada_celular(uuid,uuid[])';
  end if;
end;
$pre$;

-- El número completo manda: un descarte antiguo no elude el veto, el cliente ni un lead abierto ajeno.
-- Misma prioridad que tomar_lead_libre; solo lectura de public.perfiles, sin alterar objetos del portal.
create function private.llamada_celular_contacto_admitido(p_dueno uuid, p_formas text[])
returns boolean
language sql
stable
set search_path = ''
as $function$
  select p_dueno is not null
    and not exists (
      select 1 from crm.leads l
      where (l.telefono = any(p_formas) or l.telefono_alternativo = any(p_formas))
        and (l.no_contactar or private.persona_vetada(l.id)
          or (l.activo and l.etapa not in ('convertido', 'descartado')
              and (l.vendedor_id is not null or l.asignado_supervisor_id is not null)
              and not coalesce(private.sla_gestion_permitida(p_dueno, l.id), false))))
    and not exists (
      select 1 from public.perfiles p
      where p.rol = 'cliente' and p.activo
        and private.normalizar_telefono(p.telefono) = any(p_formas))
$function$;
revoke all on function private.llamada_celular_contacto_admitido(uuid,text[]) from public, anon, authenticated, service_role;
comment on function private.llamada_celular_contacto_admitido(uuid,text[]) is
  'Duodécima de llamadas: veto por número antes de seleccionar candidatos; descarta números tomados por otro ámbito, no contactar/persona vetada y clientes activos. INVOKER, sin acceso desde la API.';

create or replace function private.llamada_celular_candidatos_dueno(p_dueno uuid, p_formas text[], p_ahora timestamptz)
returns uuid[]
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_previo text := pg_catalog.current_setting('request.jwt.claim.sub', true);
  v_cand uuid[];
begin
  if p_dueno is null or pg_catalog.cardinality(coalesce(p_formas, '{}'::text[])) = 0 then
    return '{}'::uuid[];
  end if;
  perform pg_catalog.set_config('request.jwt.claim.sub', p_dueno::text, true);
  if not private.llamada_celular_contacto_admitido(p_dueno, p_formas) then
    perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
    return '{}'::uuid[];
  end if;
  select coalesce(pg_catalog.array_agg(distinct l.id), '{}'::uuid[]) into v_cand
  from crm.leads l
  left join crm.enfriamiento_politica ep on ep.motivo = l.motivo_descarte
  where l.activo
    and (l.telefono = any(p_formas) or l.telefono_alternativo = any(p_formas))
    and (coalesce(private.sla_gestion_permitida(p_dueno, l.id), false)
         or (l.vendedor_id is null and l.asignado_supervisor_id is null
             and l.etapa not in ('convertido', 'descartado'))
         or (l.etapa = 'descartado' and l.descartado_en is not null
             and l.descartado_en + case when coalesce(ep.dias, 0) > 0
                                        then pg_catalog.make_interval(days => ep.dias)
                                        else interval '24 hours' end <= p_ahora));
  -- La identidad vuelve ANTES de que la ingesta escriba: la bitácora no atribuye la llamada a nadie.
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
  return v_cand;
end;
$function$;

create or replace function private.llamada_celular_visible(p_actor uuid, p_lead uuid, p_analista uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select p_actor is not null and case
    when p_lead is not null then
      exists (select 1 from crm.leads l where l.id = p_lead and l.activo)
      and (coalesce(private.rol_crm(p_actor) = 'gerencia', false)
           or (coalesce(private.sla_gestion_permitida(p_actor, p_lead), false)
               and exists (select 1 from crm.leads l where l.id = p_lead
                           and (l.etapa <> 'descartado' or l.vendedor_id = p_analista or p_actor = p_analista))))
    else
      coalesce(private.rol_crm(p_actor) = 'gerencia', false)
      or p_analista = p_actor
      or p_analista in (select private.vendedor_ids_visibles(p_actor))
  end
$function$;

create or replace function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
                                    'duracion_seg', 'ocurrio_en'];
  v_asig crm.celulares_asignaciones%rowtype;
  v_pol crm.llamadas_celular_politica%rowtype;
  v_origen text;
  v_numero text;
  v_dir text;
  v_estado text;
  v_dur integer;
  v_ocurrio timestamptz;
  v_hora_id timestamptz;
  v_recepcion uuid;
  v_formas text[];
  v_e164 text;
  v_cand uuid[];
  v_lead uuid;
  v_ident text;
  v_aten text;
  v_metodo text;
  v_calidad jsonb := '{}'::jsonb;
  v_aceptado constant jsonb := '{"resultado": "aceptado"}'::jsonb;
  v_evento uuid;
  v_admitido boolean;
  v_previo text;
begin
  -- La puerta ya bloqueó la asignación FOR SHARE y la revalidó; aquí se relee bajo el mismo candado.
  select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
  end if;

  -- Validación: todo inválido responde «invalido» y el cupo ya gastado queda (menor 11, Codex P3). El bloque
  -- atrapa SOLO 22023: un error inesperado sigue siendo un error (503, que revierte todo, el cupo incluido).
  begin
    if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
      raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
    end if;
    if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
      raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
    end if;
    if coalesce(p_evento ->> 'v', '') <> '1' then
      raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
    end if;
    v_origen := p_evento ->> 'evento_origen_id';
    if v_origen is null or v_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
    end if;
    if pg_catalog.split_part(v_origen, '-', 1) <> v_asig.etiqueta then
      raise exception using errcode = '22023',
        message = pg_catalog.format('evento_origen_id con la etiqueta de otro celular (esta clave es de %s)', v_asig.etiqueta);
    end if;
    v_hora_id := pg_catalog.to_timestamp(pg_catalog.split_part(v_origen, '-', 2)::bigint);
    if v_hora_id < p_ahora - interval '30 days' or v_hora_id > p_ahora + interval '1 day' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id fuera de la ventana: su hora debe caer entre hace 30 días y mañana (¿hora automática en el celular?)';
    end if;
    v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
    if pg_catalog.length(v_numero) > 40 then
      raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
    end if;
    v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
    if v_dir not in ('saliente', 'entrante', 'desconocida') then
      raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
    end if;
    v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
    if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
      raise exception using errcode = '22023', message = 'estado_tecnico inválido';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg'), 'null') <> 'null' then
      if pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg') <> 'number'
         or (p_evento ->> 'duracion_seg') !~ '^[0-9]{1,5}$' or (p_evento ->> 'duracion_seg')::integer > 86400 then
        raise exception using errcode = '22023', message = 'duracion_seg debe ser un entero de 0 a 86400';
      end if;
      v_dur := (p_evento ->> 'duracion_seg')::integer;
    end if;
    v_ocurrio := private.llamada_celular_fecha(p_evento ->> 'ocurrio_en');
  exception when sqlstate '22023' then
    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
  end;

  -- Recepción ANTES de mirar leads, también si después se ignora (fallo 1). El primer envío gana: un reenvío
  -- del mismo id responde lo mismo sin buscar nada. Si guardar la llamada fallara, la recepción se revierte con
  -- ella: nada lo atrapa (Codex P1).
  insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en)
  values (v_origen, v_asig.id, p_ahora)
  on conflict (evento_origen_id) do nothing
  returning id into v_recepcion;
  if v_recepcion is null then
    return v_aceptado;
  end if;

  -- Solo salientes (decisión 2): la entrante y la dirección desconocida se ignoran (Codex P6).
  if v_dir <> 'saliente' then
    return v_aceptado;
  end if;

  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if v_ocurrio is not null and v_ocurrio > p_ahora + interval '5 minutes' then
    v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
  end if;
  v_formas := private.llamada_celular_formas(v_numero);
  v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
  if v_e164 is null and v_numero is not null then
    v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
  elsif v_numero is null then
    v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
  end if;
  -- Primero anclar las filas del contacto; después consultar candidatura y atención con una instantánea nueva.
  -- Incluye los descartados y los leads ajenos: una reasignación/veto que estaba en vuelo ya es visible al despertar.
  perform 1 from crm.leads l
  where l.telefono = any(v_formas) or l.telefono_alternativo = any(v_formas)
  order by l.id for share;
  -- Un veto no es un número desconocido: jamás cae en guardar_sin_identificar.
  v_previo := pg_catalog.current_setting('request.jwt.claim.sub', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_asig.analista_id::text, true);
  v_admitido := private.llamada_celular_contacto_admitido(v_asig.analista_id, v_formas);
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
  if v_admitido is distinct from true then return v_aceptado; end if;
  v_cand := private.llamada_celular_candidatos_dueno(v_asig.analista_id, v_formas, p_ahora);

  if pg_catalog.cardinality(v_cand) = 1 then
    v_lead := v_cand[1];
    v_ident := 'identificado';
    v_metodo := 'exacto';
    -- Solo un lead del ámbito del dueño puede ser elegible; los de la bolsa y los reutilizables quedan por revisar.
    v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
                   then 'requiere_resultado' else 'por_revisar' end;
  elsif pg_catalog.cardinality(v_cand) > 1 then
    -- Ambigua, sin guardar cuántos (fallo 4).
    v_ident := 'ambiguo';
    v_aten := 'por_revisar';
  elsif coalesce(v_pol.guardar_sin_identificar, false) then
    v_ident := 'sin_identificar';
    v_aten := 'por_revisar';
  else
    -- Decisión 3: sin candidato, la llamada no pertenece al CRM, aunque el número sea de un lead de otro analista.
    return v_aceptado;
  end if;

  -- F4-a: el lead se bloquea ANTES de guardar la llamada, el orden de la v5 (lead → llamada → enlace): un aviso que
  -- llega mientras se guarda la encuesta de esa llamada espera y encuentra su intención.
  if v_lead is not null then
    perform 1 from crm.leads l where l.id = v_lead for share;
  end if;
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
     ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values
    -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
    -- volver a buscar candidatos al asociar.
    (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
     v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end)
  returning id into v_evento;
  -- F4-a: si la encuesta llegó antes, la llamada se une ya a su resultado.
  perform private.llamada_celular_cumplir_intencion(v_evento);
  return v_aceptado;
end;
$function$;

create or replace function private.trg_llamadas_celular_enlaces_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_act crm.actividades%rowtype;
  v_ev  crm.llamadas_celular_eventos%rowtype;
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    if pg_catalog.pg_trigger_depth() > 1 then
      return old; -- cascada: se fue el evento o el lead
    end if;
    raise exception using errcode = '42501', message = 'El enlace de una llamada no se borra';
  end if;

  if tg_op = 'UPDATE' then
    -- La actividad se eliminó (cascada del lead → ON DELETE SET NULL): única escritura anidada
    -- aceptada, y solo si no cambia nada más.
    if pg_catalog.pg_trigger_depth() > 1 and new.actividad_id is null and old.actividad_id is not null
       and (pg_catalog.to_jsonb(new) - 'actividad_id' - 'actualizado_en')
         = (pg_catalog.to_jsonb(old) - 'actividad_id' - 'actualizado_en') then
      new.actualizado_en := pg_catalog.now();
      return new;
    end if;
    if new.id <> old.id or new.evento_id <> old.evento_id or new.lead_id <> old.lead_id
       or new.creado_en <> old.creado_en or new.via <> old.via then
      raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento, de lead ni de vía';
    end if;
    if new.actividad_id is distinct from old.actividad_id then
      if new.actividad_id is null then
        raise exception using errcode = '42501', message = 'Un enlace no se desenlaza: el resultado deshecho se marca, no se borra';
      end if;
      if old.actividad_id is not null then
        select (a.metadata ? 'deshecho_en') into v_deshecha
        from crm.actividades a where a.id = old.actividad_id;
        if not coalesce(v_deshecha, false) then
          raise exception using errcode = '42501',
            message = 'El enlace solo cambia de actividad si el resultado anterior fue deshecho';
        end if;
      end if;
    end if;
  elsif new.actividad_id is null then
    raise exception using errcode = '22023', message = 'Un enlace nace con la actividad registrada';
  end if;

  if new.actividad_id is not null and (tg_op = 'INSERT' or new.actividad_id is distinct from old.actividad_id) then
    select * into v_act from crm.actividades a where a.id = new.actividad_id;
    if not found then
      raise exception using errcode = '22023', message = 'La actividad enlazada no existe';
    end if;
    if v_act.lead_id <> new.lead_id then
      raise exception using errcode = '22023', message = 'La actividad enlazada es de otro lead';
    end if;
    if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
       or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
      raise exception using errcode = '22023',
        message = 'Solo se enlaza un resultado de llamada registrado por la encuesta';
    end if;
  end if;

  select * into v_ev from crm.llamadas_celular_eventos e where e.id = new.evento_id;
  if not found then
    raise exception using errcode = '22023', message = 'La llamada enlazada no existe';
  end if;
  if v_ev.lead_id is distinct from new.lead_id then
    raise exception using errcode = '22023', message = 'El enlace debe apuntar al lead de la llamada';
  end if;

  if tg_op = 'UPDATE' then
    new.actualizado_en := pg_catalog.now();
  end if;
  -- Un resultado enlazado ya no puede reservar otra llamada pendiente. También cubre el enlace manual.
  -- El DELETE anidado está autorizado por el candado de intenciones y revierte si falla el INSERT/UPDATE exterior.
  delete from private.llamadas_celular_intenciones where actividad_id = new.actividad_id;
  return new;
end;
$function$;



create or replace function private.llamadas_celular_resueltas_hoy(
  p_actor uuid, p_limite integer, p_ahora timestamptz, p_antes_resuelto_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with dia as (
    select (pg_catalog.date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima') as desde
  ), resueltas as (
    -- Registradas: cuando su enlace nació o pasó al resultado corregido.
    select en.evento_id as id, en.actualizado_en as resuelto_en
    from dia, crm.llamadas_celular_enlaces en
    join crm.llamadas_celular_eventos e on e.id = en.evento_id
    where e.atencion = 'registrado'
      and en.actualizado_en >= dia.desde and en.actualizado_en < dia.desde + interval '1 day'
      and (p_antes_resuelto_en is null or (en.actualizado_en, en.evento_id) < (p_antes_resuelto_en, p_antes_id))
    union all
    -- Descartadas: cuando se descartaron.
    select e.id, e.descartado_en
    from dia, crm.llamadas_celular_eventos e
    where e.atencion = 'descartado_con_motivo'
      and e.descartado_en >= dia.desde and e.descartado_en < dia.desde + interval '1 day'
      and (p_antes_resuelto_en is null or (e.descartado_en, e.id) < (p_antes_resuelto_en, p_antes_id))
  ), limitada as (
    select r.resuelto_en, e.id, e.evento_origen_id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.atencion, e.lead_id, e.analista_id,
           e.motivo_descarte, e.motivo_descarte_detalle, l.nombre_completo as lead_nombre, ca.etiqueta,
           en.actividad_id, en.via, a.metadata ->> 'resultado' as resultado, (a.metadata ? 'deshecho_en') as deshecho
    from resueltas r
    join crm.llamadas_celular_eventos e on e.id = r.id
    left join crm.leads l on l.id = e.lead_id
    left join crm.celulares_asignaciones ca on ca.id = e.asignacion_id
    left join crm.llamadas_celular_enlaces en on en.evento_id = e.id
    left join crm.actividades a on a.id = en.actividad_id
    where private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by r.resuelto_en desc, e.id desc
    limit p_limite + 1
  ), pagina as (
    select x.*, pg_catalog.row_number() over (order by x.resuelto_en desc, x.id desc) as n
    from limitada x
  )
  select pg_catalog.jsonb_build_object(
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'evento_origen_id', p.evento_origen_id, 'resuelto_en', p.resuelto_en, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
               'numero', p.numero_canonico, 'atencion', p.atencion, 'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
               'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor, 'etiqueta', p.etiqueta,
               'actividad_id', p.actividad_id, 'resultado', p.resultado, 'deshecho', coalesce(p.deshecho, false),
               'via', p.via, 'motivo_descarte', p.motivo_descarte, 'motivo_descarte_detalle', p.motivo_descarte_detalle)
             order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
    'siguiente', (select pg_catalog.jsonb_build_object('resuelto_en', u.resuelto_en, 'evento_id', u.id)
                  from pagina u
                  where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
  from pagina p
$function$;

create or replace function private.actividades_con_llamada_celular(p_actor uuid, p_actividad_ids uuid[])
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'actividad_id', en.actividad_id, 'evento_id', e.id, 'evento_origen_id', e.evento_origen_id, 'etiqueta', ca.etiqueta, 'via', en.via)
         order by en.actividad_id), '[]'::jsonb)
  from crm.llamadas_celular_enlaces en
  join crm.llamadas_celular_eventos e on e.id = en.evento_id
  left join crm.celulares_asignaciones ca on ca.id = e.asignacion_id
  where en.actividad_id = any(p_actividad_ids)
    and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
$function$;

-- FK revisada por advisors: índice del lado dependiente para cierre/consulta de asignaciones.
create index llamadas_celular_eventos_asignacion_idx on crm.llamadas_celular_eventos (asignacion_id);
do $post$
begin
  if has_function_privilege('anon', 'private.llamada_celular_contacto_admitido(uuid,text[])', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.llamada_celular_contacto_admitido(uuid,text[])', 'EXECUTE')
     or has_function_privilege('service_role', 'private.llamada_celular_contacto_admitido(uuid,text[])', 'EXECUTE') then
    raise exception 'LLAMADAS_CIERRE_REVISION: el núcleo no se expone';
  end if;
end;
$post$;
notify pgrst, 'reload schema';
commit;
$migracion$;
begin
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamada_celular_contacto_admitido(uuid,text[])')) is distinct from '9178a33a28f884684b4c83e489744ff2' then
    raise exception 'REGISTRO: cuerpo instalado no coincide con duodécima: private.llamada_celular_contacto_admitido(uuid,text[])';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)')) is distinct from '9be8fdc33117a3618aaf38b96b7baed5' then
    raise exception 'REGISTRO: cuerpo instalado no coincide con duodécima: private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamada_celular_visible(uuid,uuid,uuid)')) is distinct from '5e8a2c249f432e9c2c2459223b59f84f' then
    raise exception 'REGISTRO: cuerpo instalado no coincide con duodécima: private.llamada_celular_visible(uuid,uuid,uuid)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)')) is distinct from '39b94120d32ba6941dfe1a2302003b61' then
    raise exception 'REGISTRO: cuerpo instalado no coincide con duodécima: private.llamada_celular_ingerir(uuid,jsonb,timestamptz)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.trg_llamadas_celular_enlaces_candado()')) is distinct from '0bd9250fa75d274443be2902ff50badd' then
    raise exception 'REGISTRO: cuerpo instalado no coincide con duodécima: private.trg_llamadas_celular_enlaces_candado()';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)')) is distinct from '05480686b16a4449c2ebe1f160f4723e' then
    raise exception 'REGISTRO: cuerpo instalado no coincide con duodécima: private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)';
  end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.actividades_con_llamada_celular(uuid,uuid[])')) is distinct from 'e53de3abed6e2bd57131cc4b0d011dcb' then
    raise exception 'REGISTRO: cuerpo instalado no coincide con duodécima: private.actividades_con_llamada_celular(uuid,uuid[])';
  end if;
  if to_regclass('crm.llamadas_celular_eventos_asignacion_idx') is null then raise exception 'REGISTRO: falta el índice de la duodécima'; end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='20261006162813'
    and (name is distinct from 'crm_llamadas_celular_cierre_revision' or statements is distinct from array[fuente])) then
    raise exception 'REGISTRO: historial diferente para la duodécima; no se sobrescribe';
  end if;
  insert into supabase_migrations.schema_migrations(version,name,statements)
  values('20261006162813','crm_llamadas_celular_cierre_revision',array[fuente]) on conflict(version) do nothing;
end;
$registro$;
commit;
select count(*)=1 as veredicto_registro_20261006162813 from supabase_migrations.schema_migrations
where version='20261006162813' and name='crm_llamadas_celular_cierre_revision' and cardinality(statements)=1
  and md5(statements[1])='9f2ba287659844f9587b052e49b06a82';
