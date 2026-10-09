CREATE OR REPLACE FUNCTION private.registrar_evento_usuario(p_accion text, p_objetivo_id uuid, p_detalle jsonb, p_idempotencia uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_detalle jsonb := coalesce(p_detalle, '{}'::jsonb);
begin
  if (select auth.uid()) is null or p_idempotencia is null then
    raise insufficient_privilege using message = 'Actor e idempotencia requeridos';
  end if;

  if pg_catalog.jsonb_typeof(v_detalle) <> 'object'
     or pg_catalog.octet_length(v_detalle::text) > 4096
     or lower(v_detalle::text) ~ '(password|contrase|token|secret|clave)' then
    raise exception 'Detalle de auditoria no permitido';
  end if;

  insert into crm.usuario_eventos (
    actor_id, objetivo_id, accion, detalle, idempotencia
  ) values (
    (select auth.uid()), p_objetivo_id, p_accion, v_detalle, p_idempotencia
  )
  on conflict (actor_id, accion, idempotencia) do nothing;
end;
$function$
