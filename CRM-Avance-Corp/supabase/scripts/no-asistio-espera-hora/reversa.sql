-- REVERSA de 20261022170100_crm_no_asistio_espera_hora.sql («No asistió» espera a la hora de la cita).
--
-- QUÉ COMPRUEBA antes de revertir: SOLO la huella del cuerpo. Se niega si el `md5(prosrc)` del candado no es
-- `4a0a6b0048cdb6d8f2ac1d3b7ecc2852`: la migración no está aplicada, o alguien cambió el CUERPO después (en ese caso
-- no se revierte: se corrige hacia delante con otra migración). No comprueba dueño, ACL, atributos, comentario ni la
-- forma del trigger. Es deliberado: una reversa no debe negarse por una deriva ajena justo cuando hace falta revertir.
--
-- QUÉ RESTAURA: el cuerpo de `20260805180000_crm_inteligencia_comercial_reuniones.sql` (`md5(prosrc)` =
-- `ded27e36f21f4cf34263ce10c8731f5d`, medido en el laboratorio el 06/10/2026), con `security definer` y
-- `set search_path = ''`, y deja la función SIN comentario (ninguna migración anterior se lo puso).
--
-- QUÉ CONSERVA: firma, dueño y ACL (`create or replace` no los toca) y el trigger, que esta reversa no toca.
--
-- QUÉ SOBRESCRIBIRÍA si alguien lo hubiera cambiado DESPUÉS de la migración sin tocar el cuerpo —la huella seguiría
-- coincidiendo y el preflight no lo vería—:
--   · los `SET` añadidos con `ALTER FUNCTION … SET …`: `create or replace` deja solo el `search_path` vacío que
--     escribe esta reversa;
--   · el comentario, sea el de la migración u otro puesto después: queda NULO.
-- Y si antes de la migración la función SÍ tuviera un comentario (en el laboratorio no lo tenía; producción no se ha
-- mirado), esta reversa no lo recupera: la migración no lo guarda.
--
-- No hay datos que deshacer: la regla solo rechazaba. Tras revertir, el servidor vuelve a aceptar «No asistió»
-- antes de la hora de la cita por todas las entradas; es el defecto que la migración cerraba.
-- Se aplica por el mismo ciclo que la migración.
begin;
set local lock_timeout = '5s';

do $preflight$
begin
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'private.trg_tareas_before_update()'::regprocedure)
     is distinct from '4a0a6b0048cdb6d8f2ac1d3b7ecc2852' then
    raise exception 'REVERSA no_asistio_espera_hora: el candado no es el que dejó la migración (no está aplicada o cambió después); revisar antes de revertir';
  end if;
end
$preflight$;

create or replace function private.trg_tareas_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_op      boolean := coalesce(current_setting('crm.op_tarea', true), 'off') = 'on';
  v_sistema boolean := coalesce(current_setting('crm.cancela_sistema', true), 'off') = 'on';
  v_uid     uuid    := (select auth.uid());
  v_asesor  boolean;
  v_cambio_vencimiento boolean;
begin
  v_cambio_vencimiento := new.vence_en is distinct from old.vence_en;

  if old.estado <> 'pendiente' then
    raise exception 'La tarea ya esta cerrada; una reunion reprogramada conserva su historia'
      using errcode = '22023';
  end if;
  if new.estado in ('completada','no_show','reprogramada') and not v_op then
    raise exception 'Cerrar o reprogramar una reunion va por la RPC de agenda'
      using errcode = '22023';
  end if;
  if new.estado = 'cancelada' and not v_op and not v_sistema and v_uid is not null then
    raise exception 'Anular una tarea va por crm.cerrar_tarea()'
      using errcode = '22023';
  end if;
  if new.resultado_actividad_id is distinct from old.resultado_actividad_id and not v_op then
    raise exception 'El resultado lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if (
    new.resultado_reunion is distinct from old.resultado_reunion
    or new.motivo_no_realizada is distinct from old.motivo_no_realizada
    or new.detalle_cierre_reunion is distinct from old.detalle_cierre_reunion
  ) and not v_op then
    raise exception 'El resultado de la reunion lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if old.tipo = 'reunion' and v_cambio_vencimiento and not v_op then
    raise exception 'Reprogramar una reunion va por crm.reprogramar_reunion()'
      using errcode = '22023';
  end if;

  if new.estado = 'cancelada' then
    v_asesor := (not v_sistema) and v_op and v_uid is not null;
    new.cancelada_por    := case when v_asesor then 'asesor' else 'sistema' end;
    new.cancelada_por_id := case when v_asesor then v_uid else null end;
  else
    new.cancelada_por    := old.cancelada_por;
    new.cancelada_por_id := old.cancelada_por_id;
  end if;

  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.lead_id := old.lead_id;
  new.perfil_id := old.perfil_id;
  new.reagendada_de := old.reagendada_de;
  new.tipo := old.tipo;
  new.modalidad_reunion := old.modalidad_reunion;
  new.ubicacion_reunion := old.ubicacion_reunion;
  new.enlace_reunion := old.enlace_reunion;

  if v_cambio_vencimiento then
    new.reprogramaciones := old.reprogramaciones + 1;
  else
    new.reprogramaciones := old.reprogramaciones;
  end if;
  return new;
end;
$$;

comment on function private.trg_tareas_before_update() is null;

do $postflight$
begin
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'private.trg_tareas_before_update()'::regprocedure)
     is distinct from 'ded27e36f21f4cf34263ce10c8731f5d' then
    raise exception 'REVERSA no_asistio_espera_hora: el candado no quedó como estaba antes de la migración';
  end if;
  -- Los writers no se tocaron al aplicar ni al revertir: sus sellos siguen pasando.
  perform private.assert_sla_comandos();
  perform private.assert_entrevista_al_asistir();
end
$postflight$;

commit;
