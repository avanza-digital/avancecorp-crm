-- Hotfix: COALESCE es una expresion SQL especial, no una funcion invocable
-- como pg_catalog.coalesce(...). La migracion anterior compilo PL/pgSQL, pero
-- PostgreSQL resolvio esas referencias recien al ejecutar la RPC/trigger.

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
        '3db88a3237d4e705a94e1595b1739737'::text,
        4::integer
      ),
      (
        'private.trg_perfiles_documento_protegido()'::pg_catalog.regprocedure,
        '074be38111565d8877e4ffc3dee477a1'::text,
        6::integer
      )
    ) AS expected(proc_oid, definition_md5, coalesce_count)
  LOOP
    SELECT pg_catalog.pg_get_functiondef(v_item.proc_oid)
    INTO v_def;

    IF pg_catalog.md5(v_def) <> v_item.definition_md5 THEN
      RAISE EXCEPTION 'Deriva inesperada en %; hotfix COALESCE cancelado', v_item.proc_oid;
    END IF;

    v_count := (
      pg_catalog.length(v_def)
      - pg_catalog.length(pg_catalog.replace(v_def, 'pg_catalog.coalesce', ''))
    ) / pg_catalog.length('pg_catalog.coalesce');

    IF v_count <> v_item.coalesce_count THEN
      RAISE EXCEPTION 'Se esperaban % referencias calificadas en % y se encontraron %',
        v_item.coalesce_count, v_item.proc_oid, v_count;
    END IF;

    v_def := pg_catalog.replace(v_def, 'pg_catalog.coalesce', 'coalesce');
    EXECUTE v_def;
  END LOOP;
END
$migration$;
