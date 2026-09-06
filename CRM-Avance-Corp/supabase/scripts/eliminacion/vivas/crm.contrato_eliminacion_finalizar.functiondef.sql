CREATE OR REPLACE FUNCTION crm.contrato_eliminacion_finalizar(p_contrato_id uuid, p_token uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_eliminacion private.contrato_eliminaciones%rowtype;
  v_objetos integer;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  select * into v_eliminacion
  from private.contrato_eliminaciones e
  where e.contrato_id = p_contrato_id
    and e.token = p_token
    and e.solicitado_por = p_actor_id
  for update;
  if not found then
    raise exception 'La preparación de eliminación no existe o venció'
      using errcode = 'P0002';
  end if;
  v_objetos := jsonb_array_length(v_eliminacion.objetos);

  perform set_config(
    'crm.contrato_pdf_eliminacion_autorizada', p_contrato_id::text, true
  );
  begin
    delete from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id;
    delete from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id;
    delete from private.contrato_eliminaciones e
    where e.contrato_id = p_contrato_id;
    delete from public.contratos c
    where c.id = p_contrato_id;
    if not found then
      raise exception 'Contrato no encontrado' using errcode = 'P0002';
    end if;
  exception when others then
    perform set_config(
      'crm.contrato_pdf_eliminacion_autorizada', '', true
    );
    raise;
  end;
  perform set_config('crm.contrato_pdf_eliminacion_autorizada', '', true);

  return jsonb_build_object(
    'ok', true,
    'contrato_id', p_contrato_id,
    'objetos_eliminados', v_objetos
  );
end;
$function$
