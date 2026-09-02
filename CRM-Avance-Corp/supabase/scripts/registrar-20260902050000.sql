-- Registrador de 20260902050000_crm_lector_global_definers para PRODUCCION.
-- Se corre INMEDIATAMENTE despues de aplicar la migracion, por la misma via.
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260902050000', 'crm_lector_global_definers', array[$reg_p055$-- P-055 · El lector global tampoco ve lo borrado POR LAS PUERTAS DEFINER.
--
-- ENMIENDA de 20260902040000, que cerro la puerta de RLS (`leads_select`,
-- `tareas_select`, `actividades_select`). El auditor RLS refuto que aquello
-- bastara: DOS funciones SECURITY DEFINER llevan el MISMO espejo copiado y la
-- RLS no las alcanza, asi que la regla de Miguel («el lector global ve TODO lo
-- vivo y NADA de lo borrado») quedaba incumplida por dos puertas:
--
--   1. `crm.actividades_del_ambito_fn()` — timeline de 365 dias, hasta 10 000
--      filas, con EXECUTE para `authenticated`. Servia el `detalle` de las
--      conversaciones de leads borrados. Es justo lo que la migracion anterior
--      decia estar cerrando al tocar `actividades_select`.
--   2. `crm.cierres_estado_fn(uuid[])` — canal, `anulado_en` y motivo de los
--      cierres de leads borrados. Su comentario interno afirma «El `or
--      v_lector` va FUERA del `activo`, igual que en la policy»: sin esta
--      enmienda ese comentario pasaba a documentar una mentira.
--
-- Es el caso de libro de la «desincronizacion silenciosa del predicado
-- copiado» contra la que la propia suite avisa. Se corrige de raiz.
--
-- 🔴 Y ARREGLA UN FALSO VERDE DE LA MIGRACION ANTERIOR: su postflight contaba
-- las actividades visibles con un `join crm.leads ... and not l.activo` BAJO
-- el rol `authenticated` — pero a esas alturas `leads_select` ya ocultaba los
-- leads inactivos, asi que el conteo daba 0 SIEMPRE, aunque
-- `actividades_select` hubiera quedado rota. Aqui la sonda calcula los ids
-- COMO postgres y luego pregunta SOLO a `crm.actividades`.
--
-- Marcha atras: scripts/rollback-lector-global-definers.sql
begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
declare v_h text;
begin
  -- 0.1 Las dos DEFINER son las que se auditaron (huella del cuerpo).
  select pg_catalog.md5(p.prosrc) into v_h
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'actividades_del_ambito_fn';
  if v_h is distinct from 'b50148fb6eb60cef8aaf2fedcdd1e690' then
    raise exception 'actividades_del_ambito_fn cambio (huella %): re-auditar antes de aplicar', v_h;
  end if;

  select pg_catalog.md5(p.prosrc) into v_h
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'cierres_estado_fn';
  if v_h is distinct from 'd1423797f10ba97ee58d82f4f63aae86' then
    raise exception 'cierres_estado_fn cambio (huella %): re-auditar antes de aplicar', v_h;
  end if;

  -- 0.2 La migracion anterior YA esta aplicada: sin ella, esta enmienda
  --     dejaria las DEFINER mas estrictas que la RLS (incoherencia al reves).
  if (select pg_catalog.md5(p.qual)
        from pg_catalog.pg_policies p
       where p.schemaname = 'crm' and p.tablename = 'leads'
         and p.policyname = 'leads_select' and p.cmd = 'SELECT')
     = '4fc91b80d5486cb2d7bff5e0abf29eab' then
    raise exception 'leads_select sigue en su forma VIEJA: aplicar antes 20260902040000';
  end if;
end
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El timeline: el lector entra al mismo candado de `l.activo`.
--    Todo lo demas (ventana de 365 dias, orden, tope de 10 000, search_path,
--    firma y volatilidad) se conserva AL LITERAL.
-- ---------------------------------------------------------------------------
create or replace function crm.actividades_del_ambito_fn()
returns table(id uuid, lead_id uuid, tipo text, detalle text, autor_nombre text, creado_en timestamp with time zone)
language sql
stable security definer
set search_path to 'private', 'public', 'crm'
as $fn$
  select a.id, a.lead_id, a.tipo, a.detalle,
         coalesce(p.nombre_completo, '—') as autor_nombre, a.creado_en
  from crm.actividades a
  left join public.perfiles p on p.id = a.creado_por
  where a.creado_en >= now() - interval '365 days'
    and exists (
      select 1 from crm.leads l
      where l.id = a.lead_id
        and l.activo = true
        and (
          l.vendedor_id = any (array(select private.vendedor_ids_visibles((select auth.uid()))))
          or (l.vendedor_id is null and l.asignado_supervisor_id = any (array(select private.vendedor_ids_visibles((select auth.uid())))))
          or (select private.rol_crm((select auth.uid()))) = 'gerencia'
          or (select private.es_lector_global())
        )
    )
  order by a.creado_en desc, a.id asc
  limit 10000;
$fn$;

-- ---------------------------------------------------------------------------
-- 2. El estado de cierres: mismo espejo, y el comentario interno corregido
--    para que siga diciendo la verdad.
-- ---------------------------------------------------------------------------
-- 🔴 El cuerpo va COPIADO DEL VOLCADO VIVO con UN solo cambio quirurgico (el
--    espejo). La primera version de esta migracion lo reescribio a mano y
--    salio MAL: perdia el gate `puede_acceder_crm()`, el `order by` del
--    jsonb_agg, el mensaje exacto del tope de 200 y hasta la FORMA del
--    payload (canal/anulado_en/motivo). Lo destapo la marcha atras al no
--    cuadrar la huella. Una funcion viva no se reteclea: se copia y se toca
--    lo justo.
create or replace function crm.cierres_estado_fn(p_lead_ids uuid[])
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $fn$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text;
  v_lector   boolean;
  v_visibles uuid[];
  v_payload  jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();

  -- Guardia de ADMISION, igual que cartera_pagina_fn: quien no es del CRM ni
  -- lector global no pregunta.
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- El gate RESTRICTIVO de `crm.leads` (`crm_actor_activo_gate`) se INVOCA en
  -- vez de copiarse: una llamada no se desincroniza. Sin esto, un actor
  -- revocado —que la RLS expulsa de la tabla— seguiria leyendo por aqui.
  if not coalesce(private.puede_acceder_crm(), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Tope alineado con `cartera_pagina_fn` (p_limite maximo 200): esta funcion
  -- sirve a una pagina en pantalla, no a un volcado.
  if p_lead_ids is not null and array_length(p_lead_ids, 1) > 200 then
    raise exception 'Parametro p_lead_ids invalido: maximo 200'
      using errcode = '22023';
  end if;
  if p_lead_ids is null or array_length(p_lead_ids, 1) is null then
    return '[]'::jsonb;
  end if;

  -- Se resuelve UNA vez (la policy lo evalua como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  select coalesce(jsonb_agg(f.fila order by f.lead_id), '[]'::jsonb)
    into v_payload
  from (
    select
      l.id as lead_id,
      jsonb_build_object(
        'lead_id', l.id,
        -- La foto del cierre manda sobre la etapa: si hay fila en
        -- cierres_externos, ese lead cerro en cooperativa, punto.
        'canal', case when ce.lead_id is not null then 'cooperativa' else 'avance' end,
        -- `coalesce` y no un case: los dos canales son excluyentes por
        -- construccion (crm.anular_cierre_avance rechaza un lead con cierre en
        -- cooperativa), asi que como mucho uno de los dos trae fecha.
        'anulado_en', coalesce(ce.anulado_en, ca.anulado_en),
        -- El motivo viaja: la regla de Miguel es que a quien se le quita el
        -- merito merece una razon escrita, no un numero que baja sin explicacion.
        'motivo', coalesce(ce.motivo_anulacion, ca.motivo)
      ) as fila
    from crm.leads l
    -- Los dos son UNIQUE por lead (`cierres_externos_un_cierre_por_lead` y el
    -- unique de `lead_id` en cierres_avance_anulados), asi que ningun join
    -- duplica la fila del lead.
    left join crm.cierres_externos ce on ce.lead_id = l.id
    left join crm.cierres_avance_anulados ca on ca.lead_id = l.id
    where l.id = any(p_lead_ids)
      -- ── ESPEJO EXACTO de la policy `leads_select` (20260902040000) ─────────
      --   using: activo = true
      --          and ( vendedor_id in (vendedor_ids_visibles(uid))
      --                or (vendedor_id is null and asignado_supervisor_id in (...))
      --                or rol_crm(uid) = 'gerencia'
      --                or es_lector_global() )
      -- 🔴 El `or v_lector` va DENTRO del `activo`, igual que en la policy: el
      -- lector global ve todo lo VIVO y NADA de lo borrado. Hasta el 01/09 iba
      -- fuera —aqui y en la policy— y por eso el Directorio leia el estado de
      -- cierre de leads dados de baja.
      and l.activo = true
      and (
        l.vendedor_id = any(v_visibles)
        -- Lead en la bandeja de un supervisor: sin vendedor todavia.
        -- (`NULL = any(...)` da NULL, no TRUE, asi que la rama de arriba
        -- no se lo lleva por delante.)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
      -- Solo los leads con algo que decir. Un convertido de Avance sano no
      -- viaja: es el caso por defecto del front.
      and (ce.lead_id is not null or ca.lead_id is not null)
  ) f;

  return v_payload;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 3. Postflight de CONDUCTA — esta vez SIN la tautologia de la anterior.
--    Los ids de actividades de leads muertos se calculan COMO postgres; luego,
--    con los claims del lector, se pregunta SOLO a `crm.actividades` por esos
--    ids. Asi la sonda mide la funcion y no la policy que ya filtra.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_lector uuid;
  v_acts_muertas uuid[];
  v_leads_muertos uuid[];
  v_visibles_muertas int;
  v_timeline_muerto int;
  v_cierres_muertos int;
  v_timeline_vivo int;
  v_acts_vivas_esperadas int;
begin
  select coalesce(array_agg(a.id), '{}') into v_acts_muertas
    from crm.actividades a join crm.leads l on l.id = a.lead_id
   where not l.activo and a.creado_en >= now() - interval '365 days';
  select coalesce(array_agg(l.id), '{}') into v_leads_muertos
    from crm.leads l where not l.activo;
  select count(*) into v_acts_vivas_esperadas
    from crm.actividades a join crm.leads l on l.id = a.lead_id
   where l.activo and a.creado_en >= now() - interval '365 days';

  select p.id into v_lector
    from public.perfiles p
   where p.rol = 'directorio' and p.activo
   order by p.id
   limit 1;

  if v_lector is null then
    raise notice 'POSTFLIGHT: sin perfil directorio activo; quedan las anclas estructurales';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_lector, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);

    -- El actor tiene que ser lector global DE VERDAD; si no, la sonda mediria
    -- otra cosa y abortaria culpando a la migracion (falso NO-GO).
    if not private.es_lector_global() then
      perform set_config('role', 'none', true);
      perform set_config('request.jwt.claims', '', true);
      raise notice 'POSTFLIGHT: el perfil directorio elegido NO es lector global (membresia desalineada); sonda omitida';
    else
      select count(*) into v_visibles_muertas
        from crm.actividades a where a.id = any(v_acts_muertas);
      select count(*) into v_timeline_muerto
        from crm.actividades_del_ambito_fn() t where t.lead_id = any(v_leads_muertos);
      select count(*) into v_timeline_vivo from crm.actividades_del_ambito_fn();
      select jsonb_array_length(crm.cierres_estado_fn(
               (select coalesce(array_agg(x), '{}') from unnest(v_leads_muertos) x limit 200)))
        into v_cierres_muertos;

      perform set_config('role', 'none', true);
      perform set_config('request.jwt.claims', '', true);

      if v_visibles_muertas <> 0 then
        raise exception 'POSTFLIGHT: la policy deja ver % actividades de leads borrados', v_visibles_muertas;
      end if;
      if v_timeline_muerto <> 0 then
        raise exception 'POSTFLIGHT: actividades_del_ambito_fn sirve % filas de leads borrados', v_timeline_muerto;
      end if;
      if v_cierres_muertos <> 0 then
        raise exception 'POSTFLIGHT: cierres_estado_fn sirve % filas de leads borrados', v_cierres_muertos;
      end if;
      if v_timeline_vivo <> v_acts_vivas_esperadas then
        raise exception 'POSTFLIGHT: el timeline vivo devolvio % y hay % actividades vivas — se rompio la rama VIVA',
          v_timeline_vivo, v_acts_vivas_esperadas;
      end if;
      raise notice 'POSTFLIGHT OK: 0 por las tres puertas (policy, timeline, cierres) y % actividades vivas intactas',
        v_timeline_vivo;
    end if;
  end if;
end
$postflight$;

commit;
$reg_p055$])
on conflict (version) do nothing;
select version, name, md5(array_to_string(statements, E';\n')) as md5_texto
  from supabase_migrations.schema_migrations where version = '20260902050000';
