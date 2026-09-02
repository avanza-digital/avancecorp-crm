-- MARCHA ATRAS de 20260902050000_crm_lector_global_definers.
--
-- Devuelve las dos SECURITY DEFINER a su forma anterior AL LITERAL (huellas de
-- prosrc b50148fb… y d1423797…, las que el preflight de la migracion ancla).
-- Volver atras REABRE la fuga: el lector global vuelve a leer el timeline y el
-- estado de cierres de leads borrados.
--
-- ⚠️ Si tambien se revierte 20260902040000, hacerlo DESPUES de este guion: al
--    reves quedarian las DEFINER mas estrictas que la RLS.
begin;

set local lock_timeout = '5s';

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
        and (
          (l.activo = true and (
            l.vendedor_id = any (array(select private.vendedor_ids_visibles((select auth.uid()))))
            or (l.vendedor_id is null and l.asignado_supervisor_id = any (array(select private.vendedor_ids_visibles((select auth.uid())))))
            or (select private.rol_crm((select auth.uid()))) = 'gerencia'
          ))
          or (select private.es_lector_global())
        )
    )
  order by a.creado_en desc, a.id asc
  limit 10000;
$fn$;

-- El cuerpo va COPIADO DEL VOLCADO de produccion, no reescrito a mano: la
-- primera version de esta marcha atras se retecleo y salio con otra huella
-- (f93b393d… en vez de d1423797…). Lo cazó su propio postflight — que es
-- justo para lo que está.
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
      -- ── ESPEJO EXACTO de la policy `leads_select` (anclada en el preflight) ──
      --   using: activo = true
      --          and ( vendedor_id in (vendedor_ids_visibles(uid))
      --                or (vendedor_id is null and asignado_supervisor_id in (...))
      --                or rol_crm(uid) = 'gerencia' )
      --          or es_lector_global()
      -- El `or v_lector` va FUERA del `activo`, igual que en la policy: el
      -- lector global ve tambien lo dado de baja. Copiarlo dentro le habria
      -- escondido filas que la RLS si le muestra.
      and (
        (
          l.activo = true
          and (
            l.vendedor_id = any(v_visibles)
            -- Lead en la bandeja de un supervisor: sin vendedor todavia.
            -- (`NULL = any(...)` da NULL, no TRUE, asi que la rama de arriba
            -- no se lo lleva por delante.)
            or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
            or v_rol = 'gerencia'
          )
        )
        or v_lector
      )
      -- Solo los leads con algo que decir. Un convertido de Avance sano no
      -- viaja: es el caso por defecto del front.
      and (ce.lead_id is not null or ca.lead_id is not null)
  ) f;

  return v_payload;
end;
$fn$;

do $post$
declare v_h text;
begin
  select pg_catalog.md5(p.prosrc) into v_h
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'actividades_del_ambito_fn';
  if v_h is distinct from 'b50148fb6eb60cef8aaf2fedcdd1e690' then
    raise exception 'ROLLBACK INCOMPLETO: actividades_del_ambito_fn quedo con huella % (original b50148fb…)', v_h;
  end if;
  select pg_catalog.md5(p.prosrc) into v_h
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'cierres_estado_fn';
  if v_h is distinct from 'd1423797f10ba97ee58d82f4f63aae86' then
    raise exception 'ROLLBACK INCOMPLETO: cierres_estado_fn quedo con huella % (original d1423797…)', v_h;
  end if;
  raise notice 'ROLLBACK OK: las dos DEFINER de vuelta a su forma original al byte';
end
$post$;

commit;
