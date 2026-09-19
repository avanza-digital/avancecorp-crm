-- Cancelar una intención sin borrar antecedentes ni tocar el hecho económico.
-- La misma puerta sirve a Cartera y al lead, también después de un veto.
create or replace function crm.cancelar_solicitud_inversion_fn(p_solicitud uuid,p_revision_datos_esperada integer)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare s crm.inversion_solicitudes%rowtype; v_origen uuid; v_ctx jsonb; v_saga jsonb;
begin
  select inversionista_id into v_origen from crm.inversion_solicitudes where id=p_solicitud;
  v_ctx:=private.inversion_persona_autorizada(v_origen);
  select * into s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if s.estado in ('confirmada','cancelada') then
    return private.inversion_solicitud_resultado(s.id,v_ctx);
  end if;
  if p_revision_datos_esperada is null or s.revision_datos<>p_revision_datos_esperada then
    raise exception 'La solicitud cambió; revisa sus datos antes de cancelarla' using errcode='P0409';
  end if;
  if s.auth_claim_id is not null then
    select resultado into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
      coalesce(s.auth_contexto->>'inversionista_id',v_origen::text) for update;
    if v_saga->>'claim_id' is distinct from s.auth_claim_id::text or
      v_saga->>'estado' is distinct from 'enlazado' or v_ctx->>'perfil_id' is null or
      v_saga->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'Completa el acceso Avance pendiente antes de cancelar esta solicitud' using errcode='P0409';
    end if;
  end if;
  update crm.inversion_solicitudes set estado='cancelada',actualizado_en=statement_timestamp() where id=s.id;
  -- El trigger de auditoría conserva quién canceló y los datos originales.
  return private.inversion_solicitud_resultado(s.id,v_ctx);
end $$;
revoke all on function crm.cancelar_solicitud_inversion_fn(uuid,integer) from public,anon,service_role;
grant execute on function crm.cancelar_solicitud_inversion_fn(uuid,integer) to authenticated;
