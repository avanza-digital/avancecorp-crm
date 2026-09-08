-- La correccion de documento de una persona es una operacion administrativa:
-- admin/superadmin desde el Portal, nunca Analista, Operaciones, Cliente o Gerencia CRM.

DO $migration$
DECLARE
  v_def text;
  v_guard_count integer;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)'::pg_catalog.regprocedure
  ) INTO v_def;

  IF pg_catalog.md5(v_def) <> '49d73e13f8969161060e2ce2b669a85a' THEN
    RAISE EXCEPTION 'Deriva inesperada en crm.corregir_documento_inversionista_fn; no se aplica el cambio de autoridad';
  END IF;

  v_guard_count := (
    pg_catalog.length(v_def)
    - pg_catalog.length(pg_catalog.replace(v_def, 'private.es_gerencia_crm_activa()', ''))
  ) / pg_catalog.length('private.es_gerencia_crm_activa()');

  IF v_guard_count <> 2 THEN
    RAISE EXCEPTION 'Se esperaban 2 guardas de Gerencia y se encontraron %', v_guard_count;
  END IF;

  v_def := pg_catalog.replace(v_def, 'private.es_gerencia_crm_activa()', 'public.es_admin()');
  v_def := pg_catalog.replace(v_def, 'Gerencia', 'Administracion');
  EXECUTE v_def;
END
$migration$;

-- La llamada publica usa el id de public.perfiles que ya conoce Administracion.
-- Si existe identidad CRM, delega en la correccion atomica que sincroniza
-- identificadores, perfil, lead, operacion y actividad. Si aun no existe,
-- actualiza solo el perfil (que conserva su auditoria general).
CREATE OR REPLACE FUNCTION crm.corregir_documento_cliente_admin_fn(
  p_cliente_id uuid,
  p_tipo text,
  p_documento text,
  p_motivo text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET lock_timeout TO '5s'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_tipo text;
  v_norm text;
  v_old_tipo text;
  v_old_norm text;
  v_inv_id uuid;
  v_old_identifier_id uuid;
BEGIN
  IF NOT public.es_admin() THEN
    RAISE EXCEPTION 'Solo un usuario administrador puede corregir el documento de un cliente'
      USING ERRCODE = '42501';
  END IF;

  v_tipo := pg_catalog.upper(pg_catalog.btrim(pg_catalog.coalesce(p_tipo, '')));
  v_norm := pg_catalog.upper(
    pg_catalog.regexp_replace(pg_catalog.coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g')
  );

  IF v_tipo NOT IN ('DNI', 'CE', 'PASAPORTE') THEN
    RAISE EXCEPTION 'Tipo de documento invalido' USING ERRCODE = '22023';
  END IF;
  IF (v_tipo = 'DNI' AND v_norm !~ '^[0-9]{8}$')
     OR (v_tipo = 'CE' AND v_norm !~ '^[0-9]{9,12}$')
     OR (v_tipo = 'PASAPORTE' AND v_norm !~ '^[A-Z0-9]{6,12}$') THEN
    RAISE EXCEPTION 'Documento invalido para el tipo' USING ERRCODE = '22023';
  END IF;

  SELECT
    pg_catalog.coalesce(pg_catalog.nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI'),
    pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g'))
  INTO v_old_tipo, v_old_norm
  FROM public.perfiles p
  WHERE p.id = p_cliente_id
    AND p.rol = 'cliente';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El cliente no existe' USING ERRCODE = 'P0002';
  END IF;

  SELECT i.id
  INTO v_inv_id
  FROM crm.inversionistas i
  WHERE i.perfil_id = p_cliente_id
    AND i.estado <> 'fusionado'
  ORDER BY i.creado_en DESC, i.id
  LIMIT 1;

  IF v_inv_id IS NULL THEN
    PERFORM private.motivo_sin_documento(p_motivo, ARRAY[v_norm, v_old_norm]);
    BEGIN
      UPDATE public.perfiles
      SET dni = v_norm,
          tipo_documento = v_tipo,
          actualizado_en = pg_catalog.now()
      WHERE id = p_cliente_id
        AND rol = 'cliente';
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Otro cliente del Portal lleva ese documento'
        USING ERRCODE = '23505';
    END;
    RETURN pg_catalog.jsonb_build_object(
      'ok', true,
      'estado', 'corregido_sin_identidad_crm',
      'cliente_id', p_cliente_id,
      'por', v_uid
    );
  END IF;

  SELECT d.id
  INTO v_old_identifier_id
  FROM crm.inversionista_identificadores d
  WHERE d.inversionista_id = v_inv_id
    AND d.estado = 'vigente'
    AND d.tipo_documento = v_old_tipo
    AND d.documento_normalizado = v_old_norm
  ORDER BY d.verificado DESC, d.vigente_desde DESC, d.id
  LIMIT 1;

  IF v_old_identifier_id IS NULL THEN
    RAISE EXCEPTION 'El documento del Portal no coincide con la identidad CRM; requiere revision administrativa'
      USING ERRCODE = 'P0409';
  END IF;

  RETURN crm.corregir_documento_inversionista_fn(
    v_inv_id,
    v_tipo,
    v_norm,
    p_motivo,
    v_old_identifier_id
  );
END
$function$;

REVOKE ALL ON FUNCTION crm.corregir_documento_cliente_admin_fn(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION crm.corregir_documento_cliente_admin_fn(uuid, text, text, text)
  TO authenticated;

-- La funcion interna ya no se expone directamente a usuarios autenticados.
REVOKE EXECUTE ON FUNCTION crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid)
  FROM authenticated;

CREATE OR REPLACE FUNCTION private.trg_perfiles_documento_protegido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_old text := pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.coalesce(old.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_new text := pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.coalesce(new.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_told text := pg_catalog.coalesce(pg_catalog.nullif(pg_catalog.btrim(old.tipo_documento), ''), 'DNI');
  v_tnew text := pg_catalog.coalesce(pg_catalog.nullif(pg_catalog.btrim(new.tipo_documento), ''), 'DNI');
BEGIN
  IF NOT private.resolver_en_puertas_bajo_candado() THEN
    RETURN new;
  END IF;
  IF pg_catalog.coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     AND pg_catalog.coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false) THEN
    RETURN new;
  END IF;
  IF v_old = v_new AND v_told = v_tnew THEN
    RETURN new;
  END IF;
  IF (SELECT auth.uid()) IS NOT NULL AND NOT public.es_admin() THEN
    RAISE EXCEPTION 'Solo un usuario administrador puede corregir el documento de un cliente'
      USING ERRCODE = '42501';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM crm.inversionistas i
    WHERE i.perfil_id = old.id
      AND i.estado <> 'fusionado'
  ) THEN
    RAISE EXCEPTION 'El documento de un cliente reconocido como persona solo se corrige mediante la correccion administrativa auditada'
      USING ERRCODE = 'P0409';
  END IF;
  RETURN new;
END
$function$;

COMMENT ON FUNCTION crm.corregir_documento_cliente_admin_fn(uuid, text, text, text) IS
  'Corrige el documento de un cliente desde Administracion. Solo admin/superadmin; sincroniza identidad CRM cuando existe.';
