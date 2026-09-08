-- Hotfix complementario: NULLIF tambien es una expresion SQL especial y no
-- puede invocarse como pg_catalog.nullif(...).

DO $migration$
DECLARE
  v_item record;
  v_def text;
  v_count integer;
BEGIN
  FOR v_item IN
    SELECT *
    FROM (VALUES
      (
        'crm.corregir_documento_cliente_admin_fn(uuid,text,text,text)'::pg_catalog.regprocedure,
        'a3e50e649e3cfddeaa6052863062e4f5'::text,
        1::integer
      ),
      (
        'private.trg_perfiles_documento_protegido()'::pg_catalog.regprocedure,
        'e1cbc2f1a794978e8ee848aa92de4ee5'::text,
        2::integer
      )
    ) AS expected(proc_oid, definition_md5, nullif_count)
  LOOP
    SELECT pg_catalog.pg_get_functiondef(v_item.proc_oid)
    INTO v_def;

    IF pg_catalog.md5(v_def) <> v_item.definition_md5 THEN
      RAISE EXCEPTION 'Deriva inesperada en %; hotfix NULLIF cancelado', v_item.proc_oid;
    END IF;

    v_count := (
      pg_catalog.length(v_def)
      - pg_catalog.length(pg_catalog.replace(v_def, 'pg_catalog.nullif', ''))
    ) / pg_catalog.length('pg_catalog.nullif');

    IF v_count <> v_item.nullif_count THEN
      RAISE EXCEPTION 'Se esperaban % referencias calificadas en % y se encontraron %',
        v_item.nullif_count, v_item.proc_oid, v_count;
    END IF;

    v_def := pg_catalog.replace(v_def, 'pg_catalog.nullif', 'nullif');
    EXECUTE v_def;
  END LOOP;
END
$migration$;
