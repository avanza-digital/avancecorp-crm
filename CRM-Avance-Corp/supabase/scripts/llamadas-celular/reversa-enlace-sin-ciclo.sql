-- Reversa de 20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql (séptima). Solo cambia cuerpos y COMMENT de dos
-- funciones del núcleo, sin tablas ni datos: se puede correr también después de dar de alta celulares, pero devuelve el
-- interbloqueo con Deshacer que la séptima corrige (revisión de Miguel en el #190). Vuelve EXACTAMENTE al estado de las
-- seis: los cuerpos y los COMMENT de private.llamada_celular_enlazar_exacto y private.llamada_celular_cumplir_intencion
-- (de 20261005155914) se copiaron con un guion desde el blob de git (nada a mano), y el banco reducido compara la huella
-- del catálogo antes de la séptima y después de esta reversa.
--
-- Orden de las reversas: esta → F4-a (reversa-enlace-exacto.sql) → corrección → elegibilidad → ingesta → núcleo → datos.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-enlace-sin-ciclo.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.llamada_celular_cumplir_intencion(uuid)') is null
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_cumplir_intencion(uuid)'::regprocedure),
                          'for key share nowait') = 0 then
    raise exception 'REVERSA_ENLACE_SIN_CICLO: la migración 20261005182227 no está aplicada';
  end if;
end;
$precondicion$;

create or replace function private.llamada_celular_enlazar_exacto(
  p_actor uuid, p_lead_id uuid, p_actividad_id uuid, p_origen text, p_via text, p_ahora timestamptz)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_act crm.actividades%rowtype;
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  v_int private.llamadas_celular_intenciones%rowtype;
  v_hora timestamptz;
  v_deshecha boolean;
  v_restriccion text;
  v_estado text;
begin
  -- 1. El id: forma fija, dentro de la ventana de la ingesta y de un celular del analista que registra.
  if p_origen is null or p_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
  end if;
  v_hora := pg_catalog.to_timestamp(pg_catalog.split_part(p_origen, '-', 2)::bigint);
  if v_hora < p_ahora - interval '30 days' or v_hora > p_ahora + interval '1 day' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
  end if;
  if not exists (select 1 from crm.celulares_asignaciones a
                 where a.etiqueta = pg_catalog.split_part(p_origen, '-', 1) and a.analista_id = p_actor
                   and (a.vigente_hasta is null or a.vigente_hasta >= v_hora)) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
  end if;

  -- 2. El resultado: lo creó o reconfirmó la v4 en esta transacción, con el lead ya bloqueado.
  select * into v_act from crm.actividades a where a.id = p_actividad_id;
  if not found or v_act.lead_id <> p_lead_id or v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
     or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
    raise exception using errcode = '23514', message = 'El servidor no confirmó el resultado de la llamada';
  end if;
  if v_act.metadata ? 'deshecho_en' then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_deshecho');
  end if;

  -- 3. ¿La llamada ya llegó? Candado: lead (v4) → llamada → enlace.
  select * into v_ev from crm.llamadas_celular_eventos e where e.evento_origen_id = p_origen for update;
  if found then
    if v_ev.analista_id <> p_actor then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
    end if;
    if v_ev.atencion = 'descartado_con_motivo' then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'descartada');
    end if;
    if v_ev.identificacion <> 'identificado' or v_ev.lead_id is distinct from p_lead_id then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
    end if;
    select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
    if found then
      if v_enl.actividad_id = p_actividad_id then
        return pg_catalog.jsonb_build_object('estado', 'repetido');
      end if;
      select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
      if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
      end if;
      begin
        update crm.llamadas_celular_enlaces set actividad_id = p_actividad_id, enlazado_por = p_actor
         where id = v_enl.id;
      exception when unique_violation then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
      end;
      v_estado := 'movido';
    else
      begin
        insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
        values (v_ev.id, p_actividad_id, v_ev.lead_id, p_actor, p_via);
      exception when unique_violation then
        return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
      end;
      v_estado := 'enlazado';
    end if;
    -- La máquina de estados de la tabla exige pasar por «requiere resultado».
    if v_ev.atencion = 'por_revisar' then
      update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
    end if;
    if v_ev.atencion <> 'registrado' then
      update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
    end if;
    return pg_catalog.jsonb_build_object('estado', v_estado);
  end if;

  -- 4. Todavía no llegó. Si el aviso llegó y se ignoró, no se guarda nada: nunca se cumpliría.
  if exists (select 1 from private.llamadas_celular_recepciones r where r.evento_origen_id = p_origen) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'sin_llamada');
  end if;
  if exists (select 1 from crm.llamadas_celular_enlaces l where l.actividad_id = p_actividad_id) then
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
  end if;
  select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = p_origen for update;
  if found then
    if v_int.actividad_id = p_actividad_id then
      return pg_catalog.jsonb_build_object('estado', 'pendiente');
    end if;
    if v_int.analista_id <> p_actor or v_int.lead_id <> p_lead_id then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
    end if;
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_int.actividad_id;
    if not coalesce(v_deshecha, false) then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
    end if;
    begin
      update private.llamadas_celular_intenciones set actividad_id = p_actividad_id where id = v_int.id;
    exception when unique_violation then
      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
    end;
    return pg_catalog.jsonb_build_object('estado', 'pendiente');
  end if;
  begin
    insert into private.llamadas_celular_intenciones (evento_origen_id, analista_id, lead_id, actividad_id, via)
    values (p_origen, p_actor, p_lead_id, p_actividad_id, p_via);
  exception when unique_violation then
    get stacked diagnostics v_restriccion = constraint_name;
    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo',
      case when v_restriccion = 'llamadas_celular_intenciones_origen_uq' then 'ya_tiene_resultado'
           else 'resultado_ya_enlazado' end);
  end;
  return pg_catalog.jsonb_build_object('estado', 'pendiente');
end;
$function$;

create or replace function private.llamada_celular_cumplir_intencion(p_evento_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_int private.llamadas_celular_intenciones%rowtype;
  v_act crm.actividades%rowtype;
begin
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found then
    return;
  end if;
  select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = v_ev.evento_origen_id for update;
  if not found then
    return;
  end if;
  perform pg_catalog.set_config('crm.op_enlace_llamadas', 'on', true);
  delete from private.llamadas_celular_intenciones where id = v_int.id;
  perform pg_catalog.set_config('crm.op_enlace_llamadas', 'off', true);
  if v_int.analista_id <> v_ev.analista_id or v_ev.identificacion <> 'identificado'
     or v_ev.lead_id is distinct from v_int.lead_id then
    return;
  end if;
  -- Sin candado sobre el resultado: Deshacer lo toma ANTES que el lead, y aquí el lead ya está bloqueado.
  select * into v_act from crm.actividades a where a.id = v_int.actividad_id;
  if not found or v_act.metadata ? 'deshecho_en' then
    return;
  end if;
  begin
    insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
    values (v_ev.id, v_int.actividad_id, v_ev.lead_id, v_int.analista_id, v_int.via);
  exception when unique_violation then
    return;  -- ese resultado ya quedó unido a otra llamada
  end;
  if v_ev.atencion = 'por_revisar' then
    update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
  end if;
  update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
end;
$function$;

comment on function private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz) is
  'Enlace EXACTO (F4-a) de un resultado recién registrado por la v5 con la llamada de su id: id con forma y ventana de un celular del analista; llamada ya llegada, del mismo analista, identificada con ese lead → enlace (o lo mueve si el anterior se deshizo); no llegada → intención de enlace (o la mueve); sin la regla de los 10 minutos. Nunca lanza por un enlace imposible: {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}. Candados: lead (ya bloqueado por la v4) → llamada → enlace o intención.';
comment on function private.llamada_celular_cumplir_intencion(uuid) is
  'La ingesta, guardada una llamada, cumple la intención de su id: la retira y, si coincide (mismo analista, llamada identificada con ese lead, resultado vigente y sin otra llamada), crea el enlace con su vía y deja la llamada en «registrado». Lee el resultado sin candado (Deshacer toma resultado → lead).';

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_cumplir_intencion(uuid)'::regprocedure),
                       'for key share nowait') > 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)'::regprocedure),
                          'for key share nowait') > 0 then
    raise exception 'REVERSA_ENLACE_SIN_CICLO: no se volvió al estado de las seis migraciones';
  end if;
end;
$postcheck$;

commit;
