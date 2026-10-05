-- Reversa de 20261005155914_crm_llamadas_celular_enlace_exacto.sql (F4-a). SOLO antes del primer aviso: sin enlaces
-- ni intenciones (se comprueba bajo candado). Vuelve EXACTAMENTE al estado de las cinco: los cuerpos y los COMMENT de
-- la ingesta y la purga (de 20261005143843) y del candado de enlaces (de 20261001145242) se copiaron con un guion desde
-- el blob de git (nada a mano), y el banco reducido compara la huella del catálogo antes de F4-a y después de esta
-- reversa. Después del primer aviso no se revierte: se apaga y se corrige hacia adelante.
--
-- Orden de las reversas: esta → corrección (reversa-correccion.sql) → elegibilidad → ingesta → núcleo → datos.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-enlace-exacto.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_intenciones') is null
     or to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is null then
    raise exception 'REVERSA_ENLACE_EXACTO: la migración 20261005155914 no está aplicada';
  end if;
end;
$precondicion$;

lock table crm.llamadas_celular_eventos, crm.llamadas_celular_enlaces, private.llamadas_celular_intenciones
  in access exclusive mode;

do $sin_avisos$
begin
  if exists (select 1 from private.llamadas_celular_intenciones) or exists (select 1 from crm.llamadas_celular_enlaces) then
    raise exception 'REVERSA_ENLACE_EXACTO: ya hay enlaces o intenciones: F4-a no se revierte; se apaga y se corrige hacia adelante';
  end if;
end;
$sin_avisos$;

-- ── 1. La puerta v5 y el núcleo del enlace exacto, fuera ─────────────────────────────────────
drop function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text);

-- ── 2. La ingesta y la purga de la quinta; el candado de enlaces de F2-b ─────────────────────
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

  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
     ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values
    -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
    -- volver a buscar candidatos al asociar.
    (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
     v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end);
  return v_aceptado;
end;
$function$;

create or replace function private.caducar_llamadas_celular()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
  v_n integer := 0;
  v_parcial integer;
begin
  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if not found then
    return 0;
  end if;
  perform pg_catalog.set_config('crm.op_purga_llamadas', 'on', true);

  -- Descartadas con motivo: su plazo, desde descartado_en. El motivo y quién lo dio quedan en la auditoría.
  delete from crm.llamadas_celular_eventos e
   where e.atencion = 'descartado_con_motivo'
     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin resolver: identificadas sin enlace y ambiguas, desde recibido_en. La atención también se mira: si una
  -- encuesta enlaza la llamada mientras la purga espera su candado, la fila vuelve con «registrado» y se queda.
  delete from crm.llamadas_celular_eventos e
   where e.identificacion in ('identificado', 'ambiguo')
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
  delete from crm.llamadas_celular_eventos e
   where e.identificacion = 'sin_identificar'
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Recepciones: 32 días (30 de ventana + 1 de tolerancia + 1 de margen). Pasado ese plazo, su id ya no entra
  -- por la ventana, así que no queda un registro eterno de a qué hora llamaba el analista (Codex P9).
  delete from private.llamadas_celular_recepciones r
   where r.recibido_en < pg_catalog.now() - interval '32 days';
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
  return v_n;
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
       or new.creado_en <> old.creado_en then
      raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento ni de lead';
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
  return new;
end;
$function$;

drop function private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz);
drop function private.llamada_celular_cumplir_intencion(uuid);

-- ── 3. Tablas ────────────────────────────────────────────────────────────────────────────────
drop table private.llamadas_celular_intenciones;
drop function private.trg_llamadas_celular_intenciones_candado();
alter table crm.llamadas_celular_enlaces drop column via;

-- ── 4. Comentarios de antes ──────────────────────────────────────────────────────────────────
comment on function private.llamada_celular_ingerir(uuid,jsonb,timestamptz) is
  'Núcleo de la ingesta (lo llama crm.ingerir_llamada_celular_servicio tras la clave y el cupo, con la hora de la puerta): valida el evento v1 en un bloque que atrapa SOLO 22023 (inválido → {resultado: invalido, mensaje}); id C<n>-<segundos> con la etiqueta de la asignación y dentro de la ventana (30 días atrás, 1 adelante); registra la recepción antes de mirar leads (repetido → aceptado sin buscar nada); solo salientes; candidatos del dueño (uno → identificada, pide resultado si es elegible como el dueño; varios → ambigua sin conteo; ninguno → no se guarda salvo guardar_sin_identificar). Recepción y llamada confirman juntas. Siempre {resultado: aceptado} si es válido. DATO PERSONAL: el número.';
comment on function private.caducar_llamadas_celular() is
  'Retención de llamadas del celular (decisión 4 de Miguel, 03/10): descartadas por su plazo desde descartado_en; identificadas sin enlace y ambiguas a dias_retencion_sin_resolver desde recibido_en; sin identificar a dias_retencion_sin_identificar; las registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones a los 32 días. Devuelve cuántas filas retiró (llamadas y recepciones). Fija el GUC crm.op_purga_llamadas para pasar los candados. La invoca pg_cron (crm-llamadas-celular-caducidad). SECURITY DEFINER: borra sin privilegios de la API.';
comment on function private.trg_llamadas_celular_enlaces_candado() is
  'Candado de crm.llamadas_celular_enlaces: nace con actividad; la actividad es de llamada, con metadata.evento = resultado_llamada y del mismo lead que la llamada; el enlace cambia de actividad solo si la anterior fue deshecha (metadata.deshecho_en); sin DELETE salvo cascada. SECURITY DEFINER porque lee crm.actividades y crm.llamadas_celular_eventos sin privilegios para la API.';

do $postcheck$
begin
  if to_regclass('private.llamadas_celular_intenciones') is not null
     or to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is not null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attrelid = 'crm.llamadas_celular_enlaces'::regclass and a.attname = 'via' and not a.attisdropped)
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'::regprocedure),
                          'cumplir_intencion') > 0 then
    raise exception 'REVERSA_ENLACE_EXACTO: no se volvió al estado de las cinco migraciones';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
