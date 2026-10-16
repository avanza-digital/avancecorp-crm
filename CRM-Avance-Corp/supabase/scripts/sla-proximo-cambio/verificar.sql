-- Verificación de 20261016190408_crm_sla_proximo_cambio_en_un_paso (solo lectura).
-- Correr ANTES y DESPUÉS de aplicar la migración, y comparar las dos salidas:
--   supabase db query --linked --file supabase/scripts/sla-proximo-cambio/verificar.sql
-- Solo lectura IMPUESTA: corre dentro de BEGIN READ ONLY (una escritura, incluso escondida en una función llamada,
-- fallaría con 25006) y termina SIEMPRE en raise, así que además todo se deshace. El informe sale en el mensaje del error
-- (db query no muestra avisos). Los 7 guardianes son STABLE y sin escrituras, secuencias, HTTP ni notificaciones (revisado el 16/10).
-- Esperado ANTES:   cuerpo=ANTERIOR (0f4f44be…) · familia SLA 62 · e17a083b…
-- Esperado DESPUÉS: cuerpo=MEJORA (a5fd870b…)   · familia SLA 62 · 1adaf6c5…
-- En los dos: productor e47f610f…, metadatos iguales y cada guardián con el MISMO resultado antes y después.
-- El 16/10 en producción, ANTES: sla_nucleo, cola_v3, sla_avisos y f7 OK; gestion_diaria, analitica_leads_citas y analista_vigencia
-- ya FALLABAN por cambios ajenos (actividades_select, cartera_filtrada_fn, proteger_campos_inmutable).
begin read only;
do $verificar$
declare
  v_oid oid := pg_catalog.to_regprocedure('private.sla_operacion_autorizada(uuid[],boolean)');
  v_md5 text; v_meta text; v_prod text; v_familia text; v_g text; v_informe text := '';
  v_guardianes text[] := array['private.assert_sla_nucleo()', 'private.assert_cola_v3()', 'private.assert_sla_avisos()', 'private.assert_gestion_diaria()',
                               'private.assert_analitica_leads_citas()', 'private.assert_analista_vigencia()',
                               'private.assert_f7_piezas_cerradas()'];
begin
  select pg_catalog.md5(prosrc) into v_md5 from pg_catalog.pg_proc where oid = v_oid;
  v_informe := v_informe || 'cuerpo=' || case v_md5 when '0f4f44bed201e7eeb00301d82cc6401f' then 'ANTERIOR'
                                                   when 'a5fd870bf432dc907f5849a61a5fb9a8' then 'MEJORA'
                                                   else 'DESCONOCIDO ' || coalesce(v_md5, 'null') end;
  select concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
      p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
      pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')))
    into v_meta from pg_catalog.pg_proc p where p.oid = v_oid;
  v_informe := v_informe || ' · metadatos=' || case when v_meta = 'postgres|{postgres=X/postgres}|search_path=""|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9'
                                                  then 'IGUALES' else 'DISTINTOS ' || coalesce(v_meta, 'null') end;
  select pg_catalog.md5(prosrc) into v_prod from pg_catalog.pg_proc
   where oid = pg_catalog.to_regprocedure('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)');
  v_informe := v_informe || ' · productor=' || case when v_prod = 'e47f610fb4cde0741f2a22c3e2e7ee2c' then 'IGUAL' else 'DISTINTO ' || coalesce(v_prod, 'null') end;
  -- Huella de la familia SLA/GD (misma consulta que fase2/banco/paridad/funciones-sla.sql y el Paso 0 del kit de la F1).
  perform pg_catalog.set_config('search_path', 'pg_catalog', true);
  select count(*) || ' · ' || md5(string_agg(firma || '|' || m || '|' || cfg || '|' || d || '|' || v || '|' || o || '|' || a, E'\n' order by firma collate "C"))
    into v_familia
    from (select p.oid::regprocedure::text firma, md5(p.prosrc) m, coalesce(array_to_string(p.proconfig, ','), '') cfg,
                 p.prosecdef::text d, p.provolatile::text v, pg_get_userbyid(p.proowner)::text o, coalesce(p.proacl::text, '') a
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('crm', 'private')
             and (p.proname like 'sla\_%' or p.proname like 'avisos\_sla%' or p.proname like 'cola\_accion%'
                  or p.proname like 'estado\_sla%' or p.proname like 'gestion\_diaria\_%')) f;
  perform pg_catalog.set_config('search_path', '', true);
  v_informe := v_informe || ' · familia SLA=' || v_familia;
  foreach v_g in array v_guardianes loop
    begin
      execute 'select ' || v_g;
      v_informe := v_informe || E'\n' || v_g || ': OK';
    exception when others then
      v_informe := v_informe || E'\n' || v_g || ': FALLA [' || sqlstate || '] ' || left(sqlerrm, 160);
    end;
  end loop;
  raise exception using errcode = 'P0001', message = E'VERIFICACION (no escribe nada)\n' || v_informe;
end $verificar$;
rollback;
