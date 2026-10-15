-- Reversa de 20261015044917_crm_eliminar_lead_error_carga.sql
--
-- Retira las puertas crm.eliminar_lead_error_carga y crm.listar_leads_eliminados y la llave
-- private.borrado_lead_error_autoriza, y devuelve los 8 candados a su cuerpo de producción del 14/10/2026 (copias en
-- candados-produccion/, con su huella md5). Se NIEGA si algún candado ya no es exactamente «producción del 14/10 + el
-- bloque de la migración» (otro trabajo lo cambió después: revertir a ciegas lo borraría).
-- crm.leads_eliminados se CONSERVA si tiene filas (no se pierde auditoría); vacía, se retira con su candado.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), solo con OK de Miguel.

begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
declare
  v_bloque constant text := $b$  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
$b$;
begin
  if to_regprocedure('crm.eliminar_lead_error_carga(uuid,text)') is null
     or to_regprocedure('crm.listar_leads_eliminados()') is null
     or to_regprocedure('private.borrado_lead_error_autoriza(text,jsonb)') is null then
    raise exception 'REVERSA eliminar_lead_error_carga: la migración no está aplicada';
  end if;
  if (
      md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure), v_bloque, '')) = '3d052e4dc970d0b2b23a81cb73d6c60f'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure), v_bloque, '')) = '2e2971b4325c7aad4253387dad301400'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure), v_bloque, '')) = 'ab7507ef09420c7f8445a4d563a3566f'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure), v_bloque, '')) = '04ce52eeb57ea8fde1fa71f9d021e025'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure), v_bloque, '')) = 'bdc42cc17888cffea22aaf63162344fe'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure), v_bloque, '')) = '903e9260918bc7e100bde650d46c1ee4'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure), v_bloque, '')) = 'a9eed979747620bb83d8670a2ffcf869'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure), v_bloque, '')) = '30015d7ddda774c110082de47b5b3056'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
  ) is not true then
    raise exception 'REVERSA eliminar_lead_error_carga: un candado cambió después de la migración; no se revierte a ciegas';
  end if;
end
$preflight$;

drop function crm.eliminar_lead_error_carga(uuid, text);
drop function crm.listar_leads_eliminados();

CREATE OR REPLACE FUNCTION private.trg_sla_nucleo_entrada_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_lead uuid;v_evento crm.actividades%rowtype;v_etapa crm.lead_sla_etapas%rowtype;
  v_regla crm.sla_politica_etapas_operacion%rowtype;v_hechos record;v_control crm.sla_operacion_control%rowtype;v_decision record;
begin
  if tg_op in ('DELETE','TRUNCATE') then raise exception 'Los hechos SLA no se borran' using errcode='55000';end if;
  if current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
    raise exception 'Solo el nucleo escribe entradas SLA' using errcode='42501';end if;
  if tg_table_name='sla_operacion_control' then
    if tg_op<>'UPDATE' or current_setting('crm.sla_control_writer',true) is distinct from 'on' then
      raise exception 'El modo solo cambia por su comando' using errcode='55000';end if;
    if (old.primera_activacion_en is not null and
       (new.primera_activacion_en is distinct from old.primera_activacion_en
        or new.politica_adopcion_id is distinct from old.politica_adopcion_id))
      or new.revision<>old.revision+1 then
      raise exception 'Adopcion inmutable o revision invalida' using errcode='55000';end if;
    if new.politica_adopcion_id is not null and not private.sla_reglas_operacion_validas(
      (select jsonb_agg(to_jsonb(r)-'politica_id') from crm.sla_politica_etapas_operacion r where r.politica_id=new.politica_adopcion_id)) then
      raise exception 'La adopcion requiere cuatro reglas completas' using errcode='23514';end if;
  elsif tg_op='UPDATE' then
    raise exception 'Entrada SLA inmutable' using errcode='55000';
  elsif tg_table_name='sla_politica_etapas_operacion' then
    if current_setting('crm.sla_config_writer',true) is distinct from 'on'
      or exists(select 1 from crm.lead_sla_etapas e where e.politica_id=new.politica_id) then
      raise exception 'Reglas solo durante publicacion, nunca sobre episodios existentes' using errcode='55000';end if;
  elsif tg_table_name='tarea_sla_contexto' then
    if ((new.fuente='evento' and pg_trigger_depth()>=2
               and current_setting('crm.sla_contexto_writer',true)='evento')
         or (new.fuente='reconstruido' and current_setting('crm.sla_contexto_writer',true)='reconstruido')) is distinct from true then
      raise exception 'Contexto solo por captura o reconstruccion privada' using errcode='55000';end if;
    select lead_id into v_lead from crm.tareas where id=new.tarea_id;
    if v_lead is distinct from new.lead_id then
      raise exception 'Contexto ajeno a tarea' using errcode='23514';end if;
  elsif tg_table_name='lead_sla_etapa_ajustes' then
    if (pg_trigger_depth()<2 and current_setting('crm.sla_finalizando_gesto',true) is distinct from 'on')
      or current_setting('crm.sla_ajuste_writer',true) is distinct from 'on' then
      raise exception 'Ajuste solo desde evento de gestion' using errcode='55000';end if;
    select * into strict v_evento from crm.actividades where id=new.origen_actividad_id;
    select * into strict v_etapa from crm.lead_sla_etapas where id=new.etapa_sla_id;
    select * into strict v_regla from crm.sla_politica_etapas_operacion
      where politica_id=v_etapa.politica_id and etapa=v_etapa.etapa;
    select * into strict v_control from crm.sla_operacion_control where id;
    select * into strict v_hechos from private.sla_etapa_hechos(v_etapa.id,v_etapa.lead_id,v_etapa.ciclo_n,v_etapa.etapa);
    select * into strict v_decision from private.sla_evaluar_prorroga(v_etapa.etapa,v_evento.tipo,v_evento.creado_por,
      v_etapa.finalizado_en is null,v_control.modo,v_control.primera_activacion_en,v_evento.creado_en,
      v_etapa.limite_en+v_hechos.minutos*interval '1 minute',v_etapa.limite_en+v_regla.tope_extra_minutos*interval '1 minute',
      v_regla.prorroga_minutos,v_regla.prorroga_max,v_hechos.usadas,false);
    if v_evento.lead_id<>v_etapa.lead_id or v_evento.creado_por is distinct from new.creado_por
      or auth.uid() is distinct from new.creado_por or not v_decision.elegible
      or new.secuencia<>v_hechos.usadas+1 or new.minutos_reales<>v_decision.minutos_reales
      or new.limite_antes<>v_etapa.limite_en+v_hechos.minutos*interval '1 minute'
      or new.limite_despues<>v_decision.limite_despues then
      raise exception 'Ajuste fuera de causa, secuencia o presupuesto' using errcode='23514';end if;
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.trg_lead_asignacion_sla_hitos_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_asignado_en timestamptz;
  v_finalizado_en timestamptz;
begin
  if tg_op='DELETE' then
    raise exception 'Los hitos SLA de asignacion no se eliminan' using errcode='55000';
  end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on'
    or pg_trigger_depth()<2 then
    raise exception 'Los hitos SLA solo se sellan desde eventos CRM' using errcode='42501';
  end if;
  select a.asignado_en,a.finalizado_en into v_asignado_en,v_finalizado_en
  from crm.lead_asignaciones a where a.id=new.lead_asignacion_id;
  if not found then raise exception 'Asignacion SLA inexistente' using errcode='23503'; end if;
  if tg_op='UPDATE' and (
    old.id is distinct from new.id
    or old.lead_asignacion_id is distinct from new.lead_asignacion_id
    or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null
      and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null
      and old.primer_contacto_en is distinct from new.primer_contacto_en)
  ) then
    raise exception 'Los hitos SLA de asignacion son inmutables' using errcode='55000';
  end if;
  if (new.primera_gestion_en is not null and (
      new.primera_gestion_en<v_asignado_en
      or (v_finalizado_en is not null and new.primera_gestion_en>v_finalizado_en)
    )) or (new.primer_contacto_en is not null and (
      new.primera_gestion_en is null
      or new.primer_contacto_en<new.primera_gestion_en
      or (v_finalizado_en is not null and new.primer_contacto_en>v_finalizado_en)
    )) then
    raise exception 'Hito SLA fuera del episodio de asignacion' using errcode='23514';
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.trg_lead_asignaciones_inmutables()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Los episodios de asignacion no se eliminan';
  end if;

  if coalesce(current_setting('crm.ledger_writer', true), 'off') <> 'on'
     or pg_trigger_depth() < 2 then
    raise exception 'El ledger solo se escribe desde el movimiento del lead';
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;

  if old.finalizado_en is not null then
    raise exception 'Un episodio cerrado es inmutable';
  end if;

  if old.id is distinct from new.id
     or old.lead_id is distinct from new.lead_id
     or old.ciclo_n is distinct from new.ciclo_n
     or old.episodio_n is distinct from new.episodio_n
     or old.analista_id is distinct from new.analista_id
     or old.motivo_apertura is distinct from new.motivo_apertura
     or old.asignado_en is distinct from new.asignado_en
     or old.asignado_por is distinct from new.asignado_por
     or old.supervisor_origen_id is distinct from new.supervisor_origen_id
     or old.monto_estimado is distinct from new.monto_estimado
     or old.moneda is distinct from new.moneda
     or old.origen is distinct from new.origen
     or old.categoria_interes is distinct from new.categoria_interes
     or old.aproximado is distinct from new.aproximado
     or old.creado_en is distinct from new.creado_en then
    raise exception 'La fotografia de un episodio es inmutable';
  end if;

  if new.finalizado_en is null or new.motivo_cierre is null then
    raise exception 'La unica actualizacion valida del ledger es su cierre completo';
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.trg_lead_sla_ciclos_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op='DELETE' then raise exception 'Los ciclos SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Los ciclos SLA solo se escriben desde eventos CRM' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en
    or old.primera_gestion_limite_en is distinct from new.primera_gestion_limite_en
    or old.primer_contacto_limite_en is distinct from new.primer_contacto_limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null and old.primer_contacto_en is distinct from new.primer_contacto_en) then
    raise exception 'Snapshot/eventos SLA inmutables' using errcode='55000';
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.trg_lead_sla_etapas_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op='DELETE' then raise exception 'Las etapas SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Las etapas SLA solo se escriben desde crm.leads' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.finalizado_en is not null or new.finalizado_en is null or new.motivo_cierre is null
    or old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.episodio_n is distinct from new.episodio_n
    or old.etapa is distinct from new.etapa or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en or old.limite_en is distinct from new.limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en then
    raise exception 'Solo se permite cerrar una etapa SLA abierta' using errcode='55000';
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.trg_sla_recibo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'Los recibos de gestion no se borran' using errcode='55000';
  end if;
  if tg_op='UPDATE' and (old.respuesta is not null or new.respuesta is null
      or (to_jsonb(new)-'respuesta'-'confirmado_en') is distinct from
         (to_jsonb(old)-'respuesta'-'confirmado_en')) then
    raise exception 'El recibo solo puede confirmarse una vez' using errcode='55000';
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.potencial_evento_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'El historial de potencial no se modifica ni se borra' using errcode = 'P0409';
end;
$function$;
CREATE OR REPLACE FUNCTION private.trg_actividades_no_contactar_solo_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exento boolean := false;
  v_veto boolean := false;
begin
  -- B6c: la nota del veto (metadata evento = no_contactar) es la fuente de la marca que la base para gestión muestra a
  -- Supervisión y Gerencia (cuándo, motivo, quién). Solo la escriben sus puertas, bajo la válvula de transacción
  -- crm.op_privilegiada = on (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn), y no se cambia ni se borra.
  if (select auth.uid()) is null then
    v_exento := true;  -- sin usuario (migraciones, backfills, service_role sin sub), como los otros sellos de crm.actividades
  elsif coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') = 'on' then
    v_exento := true;  -- la válvula de las puertas del veto
  end if;
  if not v_exento then
    if tg_op <> 'DELETE' then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(new.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if tg_op <> 'INSERT' and not v_veto then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(old.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if v_veto then
      raise exception 'La nota de No contactar solo la escriben sus puertas (marcar, levantar o postventa); no se cambia ni se borra'
        using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

drop function private.borrado_lead_error_autoriza(text, jsonb);

do $tabla$
begin
  if not exists (select 1 from crm.leads_eliminados) then
    drop table crm.leads_eliminados;
    drop function private.proteger_lead_eliminado();
  end if;
end
$tabla$;

do $postflight$
begin
  if (
      md5(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure)) = '3d052e4dc970d0b2b23a81cb73d6c60f'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure)) = '2e2971b4325c7aad4253387dad301400'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure)) = 'ab7507ef09420c7f8445a4d563a3566f'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure)) = '04ce52eeb57ea8fde1fa71f9d021e025'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure)) = 'bdc42cc17888cffea22aaf63162344fe'
      and md5(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure)) = '903e9260918bc7e100bde650d46c1ee4'
      and md5(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure)) = 'a9eed979747620bb83d8670a2ffcf869'
      and md5(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) = '30015d7ddda774c110082de47b5b3056'
  ) is not true then
    raise exception 'REVERSA POSTFLIGHT: un candado no volvió a su huella de producción';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
