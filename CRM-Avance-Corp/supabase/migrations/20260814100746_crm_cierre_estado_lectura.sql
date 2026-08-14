-- ---------------------------------------------------------------------------
-- El estado del cierre de un lead, para que la aplicacion pueda VERLO
-- ---------------------------------------------------------------------------
-- QUE ARREGLA. El 2026-08-14 entro en produccion `crm.anular_cierre_avance`
-- (migracion 20260813235119): gerencia ya puede anular un cierre de Avance y
-- ese cierre deja de acreditar en la cuota y en la conversion. Pero la
-- anulacion es INVISIBLE para el front: `crm.cierres_avance_anulados` es
-- deny-by-default con cero policies y cero grants, y el gate lo comprueba a
-- proposito. Sin una via de lectura, gerencia anularia y al recargar veria el
-- lead exactamente igual que antes; un segundo intento moriria con «ese cierre
-- ya estaba anulado». Una accion cuyo efecto no se ve es una accion que se
-- repite.
--
-- QUE DEVUELVE. Una fila por lead que TIENE ALGO QUE DECIR: o cerro en
-- cooperativa, o su cierre esta anulado (por cualquiera de los dos canales).
-- El lead convertido de Avance sin anulacion no aparece — el front asume ese
-- caso por defecto y asi el payload no crece con la operacion normal.
--
-- EL `canal` NO ES ADORNO. Es lo que impide ofrecerle a gerencia «Anular el
-- cierre» sobre un lead que cerro en COOPERATIVA, que `crm.anular_cierre_avance`
-- rechaza a proposito («usa crm.anular_cierre_externo»). Hoy ese es literalmente
-- el UNICO lead convertido que hay en produccion: sin el canal, el primer boton
-- que gerencia viera seria el que no funciona.
--
-- ⚠️ POR QUE `SECURITY DEFINER` Y NO INVOKER. La regla de la casa para una RPC
-- que devuelve filas de leads es INVOKER, «el ALCANCE lo pone la RLS»
-- (`crm.cartera_pagina_fn`, migracion 20260810141953). Aqui es IMPOSIBLE: las dos
-- tablas de anulacion no tienen ni una policy ni un grant, asi que un INVOKER no
-- veria ni una fila y la funcion mentiria devolviendo «no hay anulaciones». Es el
-- mismo caso que `crm.cierres_externos_fn`, que tambien es DEFINER por esto.
-- El precio es que el AMBITO hay que espejarlo a mano, y un predicado copiado se
-- desincroniza en silencio: por eso el preflight ancla el md5 de la policy
-- `leads_select` y el gate compara conjuntos, no ejemplos.
--
-- NO TOCA NADA DE `public` ni cambia el deny-by-default de ninguna tabla.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight — el ambito que se copia
-- ---------------------------------------------------------------------------
do $preflight$
begin
  -- Esta funcion REPRODUCE el `using` de `leads_select` porque es DEFINER y la
  -- RLS no la alcanza. Si la policy cambia y esto no, la funcion respondera por
  -- leads que su llamador ya no puede ver — una fuga silenciosa y con motivo
  -- escrito dentro. El ancla obliga a mirar.
  if (select md5(pg_catalog.pg_get_expr(polqual, polrelid))
        from pg_catalog.pg_policy
       where polrelid = 'crm.leads'::regclass
         and polname = 'leads_select')
     is distinct from '4fc91b80d5486cb2d7bff5e0abf29eab' then
    raise exception 'La policy leads_select cambio: revisar el ambito espejado en crm.cierres_estado_fn antes de aplicar.';
  end if;

  -- Y la pregunta «¿esta anulado?» tiene que seguir teniendo UNA definicion:
  -- si `private.cierre_anulado` desapareciera, esto la reimplementaria.
  if to_regprocedure('private.cierre_anulado(uuid)') is null then
    raise exception 'Falta private.cierre_anulado(uuid): aplicar antes 20260813235119.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La funcion
-- ---------------------------------------------------------------------------
create or replace function crm.cierres_estado_fn(p_lead_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
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
$function$;

comment on function crm.cierres_estado_fn(uuid[]) is
  'Estado del cierre de los leads pedidos, SOLO los que el llamador puede ver (espejo de la policy leads_select, anclada por md5 en el preflight de su migracion). Devuelve una fila por lead que cerro en cooperativa o cuyo cierre esta anulado, con canal (avance/cooperativa), anulado_en y motivo. Existe porque crm.cierres_avance_anulados es deny-by-default y sin esto la anulacion de gerencia seria invisible en la aplicacion; y el canal es lo que impide ofrecer el boton de Avance sobre un cierre en cooperativa, que la RPC rechaza.';

revoke all on function crm.cierres_estado_fn(uuid[])
  from public, anon, service_role;
grant execute on function crm.cierres_estado_fn(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Postflight — estructural, sin depender de datos de negocio
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_def text := pg_get_functiondef('crm.cierres_estado_fn(uuid[])'::regprocedure);
begin
  -- Que mire los DOS canales: si se quedara solo con cooperativas, la funcion
  -- existiria y responderia «no anulado» a todo cierre de Avance anulado — el
  -- mismo defecto vacuo que ya hubo que corregir dos veces en esta familia.
  if position('crm.cierres_avance_anulados' in v_def) = 0 then
    raise exception 'postflight: la lectura no mira el canal Avance';
  end if;
  if position('crm.cierres_externos' in v_def) = 0 then
    raise exception 'postflight: la lectura no mira el canal cooperativa';
  end if;
  -- Que el ambito siga ahi. Una funcion DEFINER sobre leads sin recorte es una
  -- fuga, no un bug de presentacion.
  if position('vendedor_ids_visibles' in v_def) = 0
     or position('puede_acceder_crm' in v_def) = 0 then
    raise exception 'postflight: la lectura perdio el recorte de ambito';
  end if;
  -- Y que las tablas de anulacion sigan SIN abrirse: esta migracion da una
  -- ventana, no una puerta.
  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'crm.cierres_avance_anulados'::regclass
  ) then
    raise exception 'postflight: crm.cierres_avance_anulados dejo de ser deny-by-default';
  end if;
  if has_table_privilege('authenticated', 'crm.cierres_avance_anulados', 'select') then
    raise exception 'postflight: crm.cierres_avance_anulados quedo legible por la Data API';
  end if;
end;
$postflight$;

commit;
