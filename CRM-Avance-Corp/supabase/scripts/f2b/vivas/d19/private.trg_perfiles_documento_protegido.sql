CREATE OR REPLACE FUNCTION private.trg_perfiles_documento_protegido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(old.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_new text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(new.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_told text := coalesce(nullif(pg_catalog.btrim(old.tipo_documento), ''), 'DNI');
  v_tnew text := coalesce(nullif(pg_catalog.btrim(new.tipo_documento), ''), 'DNI');
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  -- La corrección de Gerencia (crm.corregir_documento_inversionista_fn, b5) fija AMBAS marcas alrededor de sus hechos
  -- (válvula + GUC propia, como el candado de leads) [auditor N2]. SECURITY DEFINER porque los roles del Portal no leen crm.* [N1].
  if coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     and coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false) then
    return new;
  end if;
  if v_old = v_new and v_told = v_tnew then
    return new;   -- mismo documento con otro formato: no es un cambio
  end if;
  -- [Codex B-1] por OLD.id: un UPDATE que envía id+dni no puede esquivar el candado (proteger_campos_inmutables restaura el id DESPUÉS).
  if exists (select 1 from crm.inversionistas i where i.perfil_id = old.id and i.estado <> 'fusionado') then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige desde el CRM (corrección de documento de Gerencia)'
      using errcode = 'P0409';
  end if;
  return new;
end;
$function$
