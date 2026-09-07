-- REGISTRO en supabase_migrations.schema_migrations del HOTFIX R1 (20260906233000). `db query --linked --file` NO registra:
-- correr DESPUÉS de aplicar el hotfix. Idempotente; se niega si la función no lleva el cuerpo del hotfix (md5(prosrc)
-- 55193777…) o si la versión ya está registrada con OTRO contenido. md5 del archivo 6eaccec77d1e39bf2be47956e524cd36.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r1'));
do $chk$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from '5519377757c09621da1671fb60b9f49f' then
    raise exception 'REGISTRO HOTFIX R1: la función no lleva el cuerpo del hotfix (55193777…)';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906233000' and coalesce(md5(statements[1]), '') <> '6eaccec77d1e39bf2be47956e524cd36') then
    raise exception 'REGISTRO HOTFIX R1: la versión 20260906233000 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906233000', 'crm_rentabilidad_r1_hotfix_conflicto_version_p0409', array[$m$-- ===================================================================
-- CRM · RENTABILIDAD R1 · HOTFIX — el conflicto de versión al publicar la política deja de ser SQLSTATE 40001
-- ===================================================================
-- Por qué. En Supabase, PostgREST trata 40001 (serialization_failure) como un fallo transitorio y REINTENTA la
-- llamada hasta que el gateway corta con «upstream request timeout» (~125 s). Reproducido en banco-f7 el 06/09/2026:
-- una función que solo hace `raise ... errcode '40001'` tarda 125 143 ms vía RPC; la misma con 'P0409', 590 ms.
-- Así, publicar la política con una versión vieja (control optimista) colgaba 2 minutos en vez de responder
-- «Conflicto de versión». P0409 es el código que este proyecto ya usa para los conflictos de negocio.
--
-- Qué. `create or replace` de crm.publicar_politica_rentabilidad_fn(integer, jsonb) con el MISMO cuerpo de R1 salvo el
-- errcode del conflicto (40001 → P0409) y su comentario. Nada más cambia: firma, DEFINER, search_path, lock_timeout,
-- grants (solo authenticated) y comportamiento. Reversa: scripts/rollback-rentabilidad-r1-hotfix.sql.
-- Registro: scripts/registrar-rentabilidad-r1-hotfix.sql. Se aplica con `db query --linked --file` (no registra).
--
-- NOTA para otro trabajo (fuera de este alcance): el mismo 40001 lo usan funciones vivas de metas SLA versionados,
-- catálogo de productos versionado y usuarios/jerarquía (agosto 2026); sus conflictos de versión cuelgan igual.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r1'));
do $pre$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from '47ef8010d248d32f6edae2d7fa117354' then
    raise exception 'HOTFIX R1: crm.publicar_politica_rentabilidad_fn no lleva el cuerpo de R1 (47ef8010…): no se toca';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906233000') then
    raise exception 'HOTFIX R1: la versión 20260906233000 ya está registrada';
  end if;
end
$pre$;

create or replace function crm.publicar_politica_rentabilidad_fn(p_expected_version integer, p_config jsonb)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_actual integer; v_anterior uuid; v_ultimo timestamptz;
  v_tasa numeric; v_tope numeric; v_dias numeric; v_modo text; v_nota text;
  v_fila crm.politica_rentabilidad;
  v_desde timestamptz := clock_timestamp();
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa publica la política de rentabilidad' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'expected_version inválido' using errcode = '22023';
  end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object'
     or not (p_config ?& array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo'])
     or (p_config - array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo', 'nota']) <> '{}'::jsonb
     or jsonb_typeof(p_config -> 'tasa_base_nueva') is distinct from 'number'
     or jsonb_typeof(p_config -> 'tope_tecnico') is distinct from 'number'
     or jsonb_typeof(p_config -> 'vigencia_solicitud_dias') is distinct from 'number'
     or jsonb_typeof(p_config -> 'modo') is distinct from 'string'
     or (p_config ? 'nota' and jsonb_typeof(p_config -> 'nota') not in ('string', 'null')) then
    raise exception 'Formato de política inválido' using errcode = '22023';
  end if;
  v_tasa := (p_config ->> 'tasa_base_nueva')::numeric;
  v_tope := (p_config ->> 'tope_tecnico')::numeric;
  v_dias := (p_config ->> 'vigencia_solicitud_dias')::numeric;
  v_modo := p_config ->> 'modo';
  v_nota := nullif(btrim(p_config ->> 'nota'), '');
  if v_tasa <= 0 or v_tasa > 50 or v_tope <= 0 or v_tope > 50 or v_tope < v_tasa
     or trunc(v_dias) <> v_dias or v_dias < 1 or v_dias > 30 then
    raise exception 'Política fuera de rango (tasa 0-50, tope >= tasa y <= 50, vigencia 1-30 días)' using errcode = '22023';
  end if;
  if v_modo not in ('observacion', 'enforcement') then
    raise exception 'Modo inválido: observacion o enforcement' using errcode = '22023';
  end if;
  if v_modo = 'enforcement' then
    -- R1/R2: nada lee aún el modo enforcement; publicarlo prometería un bloqueo que no existe. Se habilita en R4.
    raise exception 'El modo enforcement todavía no está construido (llega en R4); publica en observacion' using errcode = '0A000';
  end if;
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'La nota no puede superar 500 caracteres' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('crm.politica_rentabilidad'), 1);
  select p.id, p.version, p.vigente_desde into v_anterior, v_actual, v_ultimo
  from crm.politica_rentabilidad p order by p.version desc limit 1;
  if p_expected_version <> v_actual then
    raise exception 'Conflicto de versión: esperada %, vigente %', p_expected_version, v_actual using errcode = 'P0409';
  end if;
  if v_desde <= v_ultimo then
    v_desde := v_ultimo + interval '1 millisecond';
  end if;
  insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico,
                                         vigencia_solicitud_dias, modo, nota, publicada_por)
  values (v_actual + 1, v_anterior, v_desde, v_tasa, v_tope, v_dias::integer, v_modo, v_nota, v_uid)
  returning * into v_fila;
  return to_jsonb(v_fila) || jsonb_build_object('ok', true);
end;
$function$;
comment on function crm.publicar_politica_rentabilidad_fn(integer, jsonb) is
  'Rentabilidad R1: Gerencia publica una revisión {tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota?} con control optimista por versión (P0409). En R1 el modo enforcement se rechaza (0A000).';

do $post$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from '5519377757c09621da1671fb60b9f49f' then
    raise exception 'POSTFLIGHT HOTFIX R1: el cuerpo no es el esperado (55193777…)';
  end if;
  -- R1 guardó el search_path vacío como search_path="" (comillas literales) y no como search_path=: se aceptan ambas formas.
  if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')
                   and p.prosecdef and p.proowner = 'postgres'::regrole
                   and exists (select 1 from unnest(p.proconfig) c where c in ('search_path=', 'search_path=""'))) then
    raise exception 'POSTFLIGHT HOTFIX R1: la función ya no es DEFINER de postgres con search_path vacío';
  end if;
  if not has_function_privilege('authenticated', 'crm.publicar_politica_rentabilidad_fn(integer,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.publicar_politica_rentabilidad_fn(integer,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.publicar_politica_rentabilidad_fn(integer,jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)') and a.grantee = 0) then
    raise exception 'POSTFLIGHT HOTFIX R1: los grants ya no son «solo authenticated»';
  end if;
  raise notice 'RENTABILIDAD R1 HOTFIX OK: publicar_politica_rentabilidad_fn responde P0409 (no 40001) al conflicto de versión.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260906233000' and md5(statements[1]) = '6eaccec77d1e39bf2be47956e524cd36') then
    raise exception 'REGISTRO HOTFIX R1: la versión no quedó registrada con el contenido esperado';
  end if;
  raise notice 'REGISTRO HOTFIX R1 OK (20260906233000, md5 6eaccec7…)';
end
$post$;
commit;
