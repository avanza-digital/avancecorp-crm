-- Mejora corta del SLA: «próximo cambio» en el mismo paso (plan «foto del SLA», 16/10/2026).
-- Decisión de Miguel (16/10): hacerla por el disco. private.sla_operacion_autorizada calculaba proximo_cambio_en
-- recorriendo otra vez todo v_filas con jsonb_array_elements; ahora sale con min() en el mismo SELECT que arma
-- v_filas. Mismo jsonb y mismos errores para todo lo que devuelve el productor (2.403 casos + 43 de un
-- verificador independiente + 163 tras aplicar esta migración en el banco, 0 diferencias). Banco con el esquema de
-- producción y 30+ consultas pesadas a la vez: −16 a −19 % de escrituras temporales (no es el I/O total ni una mejora de
-- latencia); la memoria total no cambia de forma medible.
-- Cambio protegido por huella productiva 0f4f44bed201e7eeb00301d82cc6401f (y productor e47f610fb4cde0741f2a22c3e2e7ee2c); resultado a5fd870bf432dc907f5849a61a5fb9a8.
-- Exige además el md5 del DDL ensayado, conserva firma, SECURITY DEFINER, search_path, dueño, ACL, volatilidad,
-- paralelismo, comentario y el resto de atributos, y corre los 3 guardianes del SLA antes del commit.
-- No toca public, tablas, policies, grants, datos ni sellos. Reversa condicionada: supabase/scripts/sla-proximo-cambio/reversa.sql.
begin;
set local lock_timeout = '5s';
do $cambio$
declare
  v_oid oid := pg_catalog.to_regprocedure('private.sla_operacion_autorizada(uuid[],boolean)');
  v_def text;
  v_meta text;
  v_extra text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_sla_proximo_cambio_en_un_paso'));
  if v_oid is null then
    raise exception 'PREFLIGHT: no existe private.sla_operacion_autorizada(uuid[],boolean)';
  end if;
  if (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid = v_oid) is distinct from '0f4f44bed201e7eeb00301d82cc6401f' then
    raise exception 'PREFLIGHT: la función del SLA no es la versión revisada (md5 esperado 0f4f44bed201e7eeb00301d82cc6401f)';
  end if;
  if (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
       where oid = pg_catalog.to_regprocedure('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'))
     is distinct from 'e47f610fb4cde0741f2a22c3e2e7ee2c' then
    raise exception 'PREFLIGHT: cambió el productor private.sla_operacion_leads; la equivalencia está probada contra e47f610fb4cde0741f2a22c3e2e7ee2c';
  end if;
  select concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
      p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
      pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')))
    from pg_catalog.pg_proc p where p.oid = v_oid into v_meta;
  if v_meta is distinct from 'postgres|{postgres=X/postgres}|search_path=""|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9' then
    raise exception 'PREFLIGHT: dueño, permisos, configuración o comentario distintos de los revisados: %', v_meta;
  end if;
  select concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
      p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
    from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang where p.oid = v_oid into v_extra;
  v_def := pg_catalog.pg_get_functiondef(v_oid);
  if pg_catalog.strpos(v_def, $antes$  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer;
$antes$) = 0 then
    raise exception 'PREFLIGHT: no encuentro el texto a cambiar';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer;
$antes$, $despues$  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer; v_prox timestamptz;
$despues$);
  if pg_catalog.strpos(v_def, $antes$    order by s.lead_id),'[]'::jsonb) into v_filas
$antes$) = 0 then
    raise exception 'PREFLIGHT: no encuentro el texto a cambiar';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    order by s.lead_id),'[]'::jsonb) into v_filas
$antes$, $despues$    order by s.lead_id),'[]'::jsonb), min((s.estado#>>'{operacion,proximo_cambio_en}')::timestamptz) into v_filas, v_prox
$despues$);
  if pg_catalog.strpos(v_def, $antes$    'proximo_cambio_en',(select min((f.value#>>'{estado,operacion,proximo_cambio_en}')::timestamptz)
      from jsonb_array_elements(v_filas) f),
$antes$) = 0 then
    raise exception 'PREFLIGHT: no encuentro el texto a cambiar';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    'proximo_cambio_en',(select min((f.value#>>'{estado,operacion,proximo_cambio_en}')::timestamptz)
      from jsonb_array_elements(v_filas) f),
$antes$, $despues$    'proximo_cambio_en',v_prox,
$despues$);
  if pg_catalog.md5(v_def) is distinct from 'a5bd718f2f288565ecb510f6ba1e8634' then
    raise exception 'PREFLIGHT: el DDL resultante no es el ensayado (md5 esperado a5bd718f2f288565ecb510f6ba1e8634)';
  end if;
  execute v_def;
  if (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid = v_oid) is distinct from 'a5fd870bf432dc907f5849a61a5fb9a8' then
    raise exception 'POSTFLIGHT: el cuerpo no coincide con el ensayado (md5 esperado a5fd870bf432dc907f5849a61a5fb9a8)';
  end if;
  select concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
      p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
      pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')))
    from pg_catalog.pg_proc p where p.oid = v_oid into v_meta;
  if v_meta is distinct from 'postgres|{postgres=X/postgres}|search_path=""|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9' then
    raise exception 'POSTFLIGHT: cambiaron dueño, permisos, configuración o comentario: %', v_meta;
  end if;
  if (select concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
      p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
    from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang where p.oid = v_oid) is distinct from v_extra then
    raise exception 'POSTFLIGHT: cambió algún otro atributo de la función (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado)';
  end if;
  -- Guardianes del SLA dentro de la misma transacción: si alguno no pasa, no queda nada aplicado.
  -- (assert_gestion_diaria no va aquí: el 16/10 ya fallaba en producción por actividades_select, ajeno a este cambio.)
  perform private.assert_sla_nucleo();
  perform private.assert_cola_v3();
  perform private.assert_sla_avisos();
end $cambio$;
commit;
