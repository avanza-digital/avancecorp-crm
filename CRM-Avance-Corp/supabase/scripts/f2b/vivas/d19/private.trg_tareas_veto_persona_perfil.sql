CREATE OR REPLACE FUNCTION private.trg_tareas_veto_persona_perfil()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_personas uuid[];
begin
  -- F2.b [D-3] (v3/v4, Codex #5/#10/N1): la tarea de PERFIL (cliente) respeta el veto de la PERSONA (contrato §7.3) igual
  -- que la de lead, en un trigger propio de crm.tareas (el trigger de gestión compartido con actividades sigue byte a byte).
  -- Corre ANTES que el resto (00_0): toma a las personas del perfil FOR SHARE —persona → perfil, el orden de reasignar—
  -- SIN ESPERAR: si alguien las tiene (veto, fusión, reasignación, baja) → 40001 y se reintenta (nunca se espera con una
  -- tarea en la mano: cerrar_tarea agenda la siguiente con la tarea bloqueada y marcar espera esa tarea con la persona
  -- bloqueada). Después revalida que lo bloqueado siga siendo lo actual (una fusión pudo mover el perfil de persona).
  -- Writers internos (auth.uid NULL) y la válvula quedan fuera, como en leads.
  if (select auth.uid()) is null
     or new.lead_id is not null or new.perfil_id is null
     or coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  v_personas := array(select x from private.personas_de_perfil(new.perfil_id) x order by 1);
  begin
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share nowait;
  exception when lock_not_available then
    raise exception 'La persona del cliente está siendo actualizada (veto, fusión o reasignación); vuelve a intentarlo'
      using errcode = '40001';
  end;
  if array(select x from private.personas_de_perfil(new.perfil_id) x order by 1) is distinct from v_personas then
    raise exception 'La persona del cliente cambió mientras se agendaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if private.persona_vetada_perfil(new.perfil_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  return new;
end;
$function$
