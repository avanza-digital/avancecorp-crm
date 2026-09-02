-- ============================================================================
-- Conversion mensual: el contador de analistas representa solo el ranking
-- ============================================================================
--
-- La migracion 20260902202247 separo correctamente las identidades no
-- rankeables de `responsables`, pero en la rama de mes abierto el contador
-- `total.analistas` todavia sumaba el agregado `fuera_de_roster`. Eso hacia que
-- Gerencia leyera, por ejemplo, 18 analistas aunque solo existieran 16 filas
-- con derecho a puesto.
--
-- No nace ninguna funcion, tabla ni RPC. Se reemplaza en sitio el mismo nucleo
-- existente. Divisor, numerador, cierres, porcentaje y produccion empresarial
-- fuera del ranking permanecen exactamente en el total; solo cambia el conteo
-- de personas que compiten.
-- ============================================================================

begin;

set local lock_timeout = '10s';

do $preflight$
declare
  v_src text;
  v_old constant text :=
    '(count(*) + (select fr.analistas from fuera fr))::int as analistas,';
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );

  if to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)') is null then
    raise exception 'Falta crm.conversion_mensual_sin_cartera_fn(date).';
  end if;

  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure;

  if md5(v_src) is distinct from '971b18ac58e569c7fc397da24d985e24' then
    raise exception 'El nucleo de conversion cambio desde la auditoria; revisar antes de aplicar.';
  end if;

  if length(v_src) - length(replace(v_src, v_old, '')) <> length(v_old) then
    raise exception 'La suma de identidades externas no aparece exactamente una vez.';
  end if;
end;
$preflight$;

do $parche$
declare
  v_src text;
  v_old constant text :=
    '(count(*) + (select fr.analistas from fuera fr))::int as analistas,';
  v_new constant text := 'count(*)::int as analistas,';
begin
  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure;

  v_src := replace(v_src, v_old, v_new);

  execute format(
    'create or replace function crm.conversion_mensual_sin_cartera_fn(p_periodo date) returns jsonb language plpgsql stable security definer set search_path = '''' as %L',
    v_src
  );
end;
$parche$;

comment on function crm.conversion_mensual_sin_cartera_fn(date) is
  'Nucleo mensual de conversion: mes vigente con roster operativo, historico abierto con la ultima publicacion de ese mes y cerrado desde la foto sellada. El total.analistas cuenta solo responsables rankeables; Gerencia conserva divisor, numerador, porcentaje y produccion fuera del ranking en el total empresarial.';

revoke all on function crm.conversion_mensual_sin_cartera_fn(date)
  from public, anon, authenticated, service_role;

-- El nucleo pertenece al censo sellado: se actualiza su huella en la misma
-- transaccion y luego se exige que todo el censo siga verde.
do $reseal$
declare
  v_actualizadas integer;
begin
  update private.analitica_leads_citas_exenciones e
  set huella = (
    select md5(regexp_replace(regexp_replace(
             lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
             '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
    from pg_catalog.pg_proc p
    where p.oid = to_regprocedure(e.objeto)
  )
  where e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)';

  get diagnostics v_actualizadas = row_count;
  if v_actualizadas <> 1 then
    raise exception 'El nucleo no aparece exactamente una vez en el censo: %.',
      v_actualizadas;
  end if;

  update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;
end;
$reseal$;

do $postflight$
declare
  v_src text;
  v_acl text[];
  v_new constant text := 'count(*)::int as analistas,';
begin
  select p.prosrc,
         coalesce(array_agg(distinct case
           when a.grantee = 0 then 'PUBLIC' else r.rolname end
           order by case when a.grantee = 0 then 'PUBLIC' else r.rolname end)
           filter (where a.privilege_type = 'EXECUTE'), '{}'::text[])
    into v_src, v_acl
  from pg_catalog.pg_proc p
  left join lateral aclexplode(
    coalesce(p.proacl, acldefault('f', p.proowner))
  ) a on true
  left join pg_catalog.pg_roles r on r.oid = a.grantee
  where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure
  group by p.prosrc;

  if md5(v_src) is distinct from 'a64a30be3182589c02553759728276f2' then
    raise exception 'La huella final del nucleo no coincide.';
  end if;
  if v_src like '%(count(*) + (select fr.analistas from fuera fr))::int as analistas,%'
     or length(v_src) - length(replace(v_src, v_new, '')) <> 3 * length(v_new) then
    raise exception 'El contador abierto/cerrado no quedo limitado al ranking.';
  end if;

  if (select p.proowner from pg_catalog.pg_proc p
      where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       <> 'postgres'::regrole
     or (select l.lanname from pg_catalog.pg_proc p
         join pg_catalog.pg_language l on l.oid = p.prolang
         where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       <> 'plpgsql'
     or (select p.provolatile from pg_catalog.pg_proc p
         where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       <> 's'
     or (select p.proparallel from pg_catalog.pg_proc p
         where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       <> 'u'
     or (select p.prosecdef from pg_catalog.pg_proc p
         where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       is not true
     or (select p.proleakproof from pg_catalog.pg_proc p
         where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       is not false
     or (select p.prorettype from pg_catalog.pg_proc p
         where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       <> 'jsonb'::regtype
     or (select p.proconfig from pg_catalog.pg_proc p
         where p.oid = 'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure)
       is distinct from array['search_path=""']::text[] then
    raise exception 'Firma o atributos de seguridad inesperados en el nucleo.';
  end if;

  if v_acl is distinct from array['postgres']::text[] then
    raise exception 'ACL inesperada en el nucleo: %.', v_acl;
  end if;

  if not (
    v_src like '%+ (select fr.divisor from fuera fr))::int as divisor,%'
    and v_src like '%+ (select fr.numerador from fuera fr)) as numerador%'
  ) then
    raise exception 'El total empresarial dejo de sumar las medidas externas.';
  end if;

  if (select e.huella
      from private.analitica_leads_citas_exenciones e
      where e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)')
       is distinct from '6ce60dcdab28267cbfc6bdc42227588b'
     or (select private.assert_analitica_leads_citas()) !~ '^OK:' then
    raise exception 'El censo analitico no quedo sellado y verde.';
  end if;
end;
$postflight$;

commit;
