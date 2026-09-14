-- Miguel, 13/09/2026: una inversión NUEVA admite tasas positivas hasta la base
-- sin excepción. Superar la base conserva la autorización de Gerencia.
-- Candidata preparada para publicación; no ejecutar automáticamente en producción.
-- No altera tablas, políticas, grants existentes, firmas RPC ni contratos guardados.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare v_f record;
begin
  for v_f in select * from (values
    ('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)', '9822f3d4d45d0fc5767c599ea871da94'),
    ('private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)', '6a9509dd1a4131042d578d3d7d673cbc'),
    ('private.trg_contratos_observar_rentabilidad()', '3e0390e96137c503e5f28a55fe6c04c0'),
    ('public.crear_contrato(jsonb,jsonb)', '2f619ddf650bd0db2ffa64790f894312')
  ) as f(firma, huella) loop
    if (select md5(prosrc) from pg_proc where oid=to_regprocedure(v_f.firma)) is distinct from v_f.huella then
      raise exception 'Preflight de tasas inferiores: % cambió. Revisar la definición instalada antes de publicar.', v_f.firma;
    end if;
  end loop;
  if to_regprocedure('private.rentabilidad_minimo_alta(text,numeric)') is not null then
    raise exception 'Las tasas inferiores ya fueron instaladas o existe otra implementación';
  end if;
  if (select count(distinct proowner) from pg_proc where oid in (
    'private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure,
    'private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)'::regprocedure,
    'private.trg_contratos_observar_rentabilidad()'::regprocedure))<>1 then
    raise exception 'Las puertas de rentabilidad tienen propietarios distintos: revisar antes de instalar';
  end if;
end;
$preflight$;

create function private.rentabilidad_minimo_alta(p_categoria text, p_base numeric)
returns numeric language sql immutable strict security invoker set search_path = ''
as $function$
  select case when p_categoria='nuevo' then 0.01::numeric else p_base end;
$function$;
revoke all on function private.rentabilidad_minimo_alta(text,numeric) from public, anon, authenticated, service_role;
-- La migración puede ejecutarla supabase_admin; los callers DEFINER conservan
-- su propietario original. El helper debe pertenecer a ese mismo propietario.
do $propietario$
begin
  execute format('alter function private.rentabilidad_minimo_alta(text,numeric) owner to %I',
    (select pg_get_userbyid(proowner) from pg_proc where oid='private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure));
end;
$propietario$;
comment on function private.rentabilidad_minimo_alta(text,numeric) is
  'Mínimo de una nueva alta: 0.01 para categoría nuevo; renovaciones y upgrades conservan la base heredada. Solo uso interno. No autoriza correcciones de tasa de contratos existentes.';

-- Ediciones acotadas sobre la versión verificada: conservan ACL, propietario,
-- search_path, locks, identidad, condiciones y los bloqueos de solicitudes.
do $patch$
declare v_def text; v_ancla text; v_nueva text;
begin
  -- El numeric(5,2) del contrato redondea ANTES del trigger. Validar el JSON
  -- en la puerta común evita guardar otra tasa si llaman la API directamente.
  v_def := pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure);
  v_ancla := $antes$  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then$antes$;
  v_nueva := $despues$  if v_categoria='nuevo' and (p_contrato->>'tasa_anual')::numeric
      <> round((p_contrato->>'tasa_anual')::numeric,2) then
    raise exception 'La tasa anual admite hasta dos decimales. Revisa el valor antes de guardar.' using errcode='22023';
  end if;
  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then$despues$;
  if cardinality(string_to_array(v_def,v_ancla))<>2 then raise exception 'Ancla de precisión de tasa no es única'; end if;
  execute replace(v_def,v_ancla,v_nueva);

  v_def := pg_get_functiondef('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure);
  v_ancla := E'    ''tasa_base'', v_base,\n    ''regla'', v_regla,';
  v_nueva := E'    ''tasa_base'', v_base,\n    ''tasa_minima_sin_autorizacion'', private.rentabilidad_minimo_alta(p_categoria, v_base),\n    ''regla'', v_regla,';
  if cardinality(string_to_array(v_def,v_ancla))<>2 then raise exception 'Ancla del resolver no es única'; end if;
  execute replace(v_def,v_ancla,v_nueva);

  v_def := pg_get_functiondef('private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)'::regprocedure);
  v_ancla := 'v_tasa is null or v_tasa<v_base or v_tasa>50 or v_tasa<>round(v_tasa,2)';
  v_nueva := 'v_tasa is null or v_tasa<private.rentabilidad_minimo_alta(v_categoria,v_base) or v_tasa>50 or v_tasa<>round(v_tasa,2)';
  if cardinality(string_to_array(v_def,v_ancla))<>2 then raise exception 'Ancla de validación no es única'; end if;
  v_def := replace(v_def,v_ancla,v_nueva);
  v_ancla := 'if v_tasa=v_base then return; end if;';
  if cardinality(string_to_array(v_def,v_ancla))<>2 then raise exception 'Ancla de tasa sin excepción no es única'; end if;
  execute replace(v_def,v_ancla,'if v_tasa<=v_base then return; end if;');

  v_def := pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure);
  v_ancla := $antes$      elsif v_c.tasa_anual < v_base then
        -- D4: por debajo de la base no se autoriza nada, así que tampoco se ofrece pedir permiso (Codex R4 #12).
$antes$;
  v_nueva := $despues$      elsif v_c.tasa_anual < v_base and not (
        v_c.categoria='nuevo'
        and v_c.tasa_anual >= private.rentabilidad_minimo_alta(v_c.categoria,v_base)
        and (tg_op='INSERT' or (tg_op='UPDATE'
          and old.categoria='nuevo' and old.es_demo is not true
          and old.cliente_id is not distinct from v_c.cliente_id
          and old.tasa_anual is not distinct from v_c.tasa_anual))
      ) then
        -- D4 revisada: el alta nueva admite una tasa menor. Una corrección solo
        -- conserva esa tasa; no concede permiso para rebajar contratos emitidos.
$despues$;
  if cardinality(string_to_array(v_def,v_ancla))<>2 then raise exception 'Ancla del candado no es única'; end if;
  v_def := replace(v_def,v_ancla,v_nueva);
  v_ancla := '    ''tasa_anterior'', case when tg_op = ''UPDATE'' then old.tasa_anual end,';
  v_nueva := v_ancla || E'\n    ''tasa_inferior_sin_excepcion'', case when v_c.categoria=''nuevo'' and v_c.tasa_anual<v_base then true end,';
  if cardinality(string_to_array(v_def,v_ancla))<>2 then raise exception 'Ancla del ledger no es única'; end if;
  execute replace(v_def,v_ancla,v_nueva);
end;
$patch$;

notify pgrst, 'reload schema';
commit;
