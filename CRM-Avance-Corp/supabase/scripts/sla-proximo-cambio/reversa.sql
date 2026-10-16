-- Reversa de 20261016190408_crm_sla_proximo_cambio_en_un_paso: vuelve al cuerpo anterior de private.sla_operacion_autorizada.
-- SOLO actúa si sigue vigente exactamente la versión de la mejora (md5 a5fd870bf432dc907f5849a61a5fb9a8) con sus metadatos; si no, falla sin tocar nada.
-- No exige el productor ni corre guardianes, para que nada ajeno bloquee una vuelta atrás: comprobar después con verificar.sql.
-- Se aplica como MIGRACIÓN NUEVA (ver LEEME.md, «Si hay que revertir»), nunca borrando la fila del índice.
begin;
set local lock_timeout = '5s';
do $reversa$
declare
  v_oid oid := pg_catalog.to_regprocedure('private.sla_operacion_autorizada(uuid[],boolean)');
  v_def text;
  v_meta text;
  v_extra text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_sla_proximo_cambio_en_un_paso'));
  if v_oid is null then
    raise exception 'PREFLIGHT REVERSA: no existe private.sla_operacion_autorizada(uuid[],boolean)';
  end if;
  if (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid = v_oid) is distinct from 'a5fd870bf432dc907f5849a61a5fb9a8' then
    raise exception 'PREFLIGHT REVERSA: la función del SLA no es la versión revisada (md5 esperado a5fd870bf432dc907f5849a61a5fb9a8)';
  end if;
  select concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
      p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
      pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')))
    from pg_catalog.pg_proc p where p.oid = v_oid into v_meta;
  if v_meta is distinct from 'postgres|{postgres=X/postgres}|search_path=""|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9' then
    raise exception 'PREFLIGHT REVERSA: dueño, permisos, configuración o comentario distintos de los revisados: %', v_meta;
  end if;
  select concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
      p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
    from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang where p.oid = v_oid into v_extra;
  v_def := pg_catalog.pg_get_functiondef(v_oid);
  if pg_catalog.strpos(v_def, $antes$    'proximo_cambio_en',v_prox,
$antes$) = 0 then
    raise exception 'PREFLIGHT REVERSA: no encuentro el texto a cambiar';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    'proximo_cambio_en',v_prox,
$antes$, $despues$    'proximo_cambio_en',(select min((f.value#>>'{estado,operacion,proximo_cambio_en}')::timestamptz)
      from jsonb_array_elements(v_filas) f),
$despues$);
  if pg_catalog.strpos(v_def, $antes$    order by s.lead_id),'[]'::jsonb), min((s.estado#>>'{operacion,proximo_cambio_en}')::timestamptz) into v_filas, v_prox
$antes$) = 0 then
    raise exception 'PREFLIGHT REVERSA: no encuentro el texto a cambiar';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    order by s.lead_id),'[]'::jsonb), min((s.estado#>>'{operacion,proximo_cambio_en}')::timestamptz) into v_filas, v_prox
$antes$, $despues$    order by s.lead_id),'[]'::jsonb) into v_filas
$despues$);
  if pg_catalog.strpos(v_def, $antes$  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer; v_prox timestamptz;
$antes$) = 0 then
    raise exception 'PREFLIGHT REVERSA: no encuentro el texto a cambiar';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer; v_prox timestamptz;
$antes$, $despues$  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer;
$despues$);
  if pg_catalog.md5(v_def) is distinct from '26216085857a74fcbb010ef53e8d6e69' then
    raise exception 'PREFLIGHT REVERSA: el DDL resultante no es el ensayado (md5 esperado 26216085857a74fcbb010ef53e8d6e69)';
  end if;
  execute v_def;
  if (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid = v_oid) is distinct from '0f4f44bed201e7eeb00301d82cc6401f' then
    raise exception 'POSTFLIGHT REVERSA: el cuerpo no coincide con el ensayado (md5 esperado 0f4f44bed201e7eeb00301d82cc6401f)';
  end if;
  select concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
      p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
      pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')))
    from pg_catalog.pg_proc p where p.oid = v_oid into v_meta;
  if v_meta is distinct from 'postgres|{postgres=X/postgres}|search_path=""|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9' then
    raise exception 'POSTFLIGHT REVERSA: cambiaron dueño, permisos, configuración o comentario: %', v_meta;
  end if;
  if (select concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
      p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
    from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang where p.oid = v_oid) is distinct from v_extra then
    raise exception 'POSTFLIGHT REVERSA: cambió algún otro atributo de la función (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado)';
  end if;
end $reversa$;
commit;
