-- Aprobado por Miguel: nombres de clientes en Facturación para Coordinación, solo lectura.
-- Añade dos funciones. No modifica RPC v1, RLS, tablas, fórmulas ni permisos de escritura.
-- Backend primero: v1 conserva su contrato para las pestañas ya abiertas; el frontend nuevo usa v2.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
do $originales$
declare r record;
begin
  for r in select * from (values
    ('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', 'f98f0bea3397cb7f054e4f25b6ae5cb8'),
    ('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '3b84fe0660b2257398edfd835828f3eb')
  ) f(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'Facturación nombres: función publicada cambió en %; se deshace todo',r.firma;
    end if;
  end loop;
end $originales$;
do $ausentes$ begin
  if to_regprocedure('private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)') is not null then raise exception 'Facturación nombres: private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) ya existe'; end if;
  if to_regprocedure('crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)') is not null then raise exception 'Facturación nombres: crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) ya existe'; end if;
end $ausentes$;
CREATE FUNCTION private.facturacion_lista_nombres(p_desde date, p_hasta date, p_dias date[] DEFAULT NULL::date[], p_analistas uuid[] DEFAULT NULL::uuid[], p_sin_analista boolean DEFAULT false, p_equipo uuid DEFAULT NULL::uuid, p_sin_equipo boolean DEFAULT false, p_tipos text[] DEFAULT NULL::text[], p_moneda text DEFAULT NULL::text, p_pagina integer DEFAULT 1, p_tamano integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_reporte_coordinacion boolean := private.es_coordinador_reportes();
  v_contratos_todos boolean;
  v_cooperativas_todas boolean;
  v_clientes uuid[] := '{}'::uuid[];
  v_vendedores uuid[] := '{}'::uuid[];
  v_resultado jsonb;
begin
  -- Los demás roles conservan exactamente el núcleo publicado.
  if not v_reporte_coordinacion then
    return private.facturacion_lista(p_desde, p_hasta, p_dias, p_analistas, p_sin_analista, p_equipo, p_sin_equipo, p_tipos, p_moneda, p_pagina, p_tamano);
  end if;
  if p_desde is null or p_hasta is null or not isfinite(p_desde) or not isfinite(p_hasta)
      or p_hasta < p_desde or p_hasta - p_desde > 30 then
    raise exception 'Fechas inválidas: indicar desde y hasta, en orden, con un máximo de 31 días' using errcode = '22023';
  end if;
  if p_dias is not null and (cardinality(p_dias) = 0 or exists (
    select 1 from unnest(p_dias) d(dia) where d.dia is null or d.dia < p_desde or d.dia > p_hasta
  )) then
    raise exception 'Días inválidos: arreglo no vacío, sin NULL y dentro de desde/hasta' using errcode = '22023';
  end if;
  if p_pagina is null or p_pagina < 1 or p_tamano is null or p_tamano not in (25, 50, 100) then
    raise exception 'Paginación inválida: página desde 1 y tamaño 25, 50 o 100' using errcode = '22023';
  end if;
  if p_moneda is not null and p_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida: PEN, USD o NULL' using errcode = '22023';
  end if;
  if p_analistas is not null and p_sin_analista is true then
    raise exception 'Analistas y sin analista son filtros excluyentes' using errcode = '22023';
  end if;
  if p_equipo is not null and p_sin_equipo is true then
    raise exception 'Equipo y sin equipo son filtros excluyentes' using errcode = '22023';
  end if;
  if cardinality(p_analistas) = 0 or cardinality(p_tipos) = 0 then
    raise exception 'Analistas y tipos no admiten arreglos vacíos; usar NULL para todos' using errcode = '22023';
  end if;
  v_cooperativas_todas := coalesce(private.rol_crm(v_uid) = 'gerencia', false);
  v_contratos_todos := v_cooperativas_todas or coalesce(private.es_lector_global(), false);
  -- Una vez por petición, nunca por fila. La verja de operaciones sigue viviendo en la 3A.
  if not v_contratos_todos and not v_reporte_coordinacion then
    v_clientes := array(select c.cliente_id from private.cliente_ids_visibles_crm() c);
    v_vendedores := array(select private.vendedor_ids_visibles(v_uid));
  end if;
  with filtradas as materialized (
    select o.* from private.facturacion_operaciones_visibles(
      (p_desde::timestamp at time zone 'America/Lima'),
      (((p_hasta + 1)::date)::timestamp at time zone 'America/Lima')
    ) o
    where (p_dias is null or o.dia = any(p_dias))
      and (p_analistas is null or o.analista_id = any(p_analistas))
      and (p_sin_analista is not true or o.analista_id is null)
      and (p_equipo is null or o.supervisor_id = p_equipo)
      and (p_sin_equipo is not true or o.supervisor_id is null)
      and (p_tipos is null or o.tipo = any(p_tipos))
      and (p_moneda is null or o.moneda = p_moneda)
  ), pagina as materialized (
    select row_number() over (order by o.fecha, o.tipo, o.operacion_id) as n, o.*
    from filtradas o order by o.fecha, o.tipo, o.operacion_id
    -- bigint evita desbordar integer en páginas grandes, que deben devolver vacío.
    offset (p_pagina::bigint - 1) * p_tamano limit p_tamano
  ), datos as (
    select p.*, c.numero_contrato, pc.nombre_completo as nombre_cliente,
      ce.nombre_completo as nombre_cooperativa, ce.cooperativa, ce.lead_id as lead_cierre,
      coalesce(not v_reporte_coordinacion and case when p.tipo = 'cooperativa' then
        v_cooperativas_todas or (not v_contratos_todos and
          case when ce.inversionista_id is not null then i.responsable_relacion_id = any(v_vendedores)
               else l.vendedor_id = any(v_vendedores) end)
        else v_contratos_todos or p.cliente_id = any(v_clientes) end, false) as visible
    from pagina p
    left join public.contratos c on c.id = p.contrato_id
    left join public.perfiles pc on pc.id = p.cliente_id
    left join crm.cierres_externos ce on ce.id = p.cierre_externo_id
    -- Relación de HOY: regla del TELÉFONO VIVO de «En cooperativas» (crm.cierres_externos_fn),
    -- más estricta que el reparto de filas por analista_efectivo_cierre. Directorio siempre enmascara cooperativas.
    -- Resolución canónica solo para filas de la página (≤ 100) y si quien mira no es global.
    left join lateral (select private.inversionista_canonica(ce.inversionista_id) as id
                       where not v_contratos_todos and not v_reporte_coordinacion and ce.inversionista_id is not null) can on true
    left join crm.inversionistas i on i.id = can.id
    left join crm.leads l on l.id = ce.lead_id
  ), filas as (
    select d.n, jsonb_build_object(
      'n', d.n, 'fecha', d.dia, 'tipo', d.tipo, 'moneda', d.moneda, 'monto', d.monto,
      'anulado', d.anulado, 'analista_id', d.analista_id,
      'analista_nombre', coalesce(pa.nombre_completo, 'Sin analista'),
      'supervisor_id', d.supervisor_id, 'supervisor_nombre', coalesce(ps.nombre_completo, 'Sin supervisor'),
      'visible', d.visible, 'cliente_nombre', case when not d.visible and not v_reporte_coordinacion then 'Cliente de otro equipo'
        when d.tipo = 'cooperativa' then d.nombre_cooperativa else d.nombre_cliente end
    ) || case when v_reporte_coordinacion then jsonb_build_object('nombre_visible', true) else '{}'::jsonb end
      || case when not d.visible then '{}'::jsonb else
      jsonb_build_object('estado', d.estado) || case when d.tipo = 'cooperativa' then
        jsonb_build_object('cierre_externo_id', d.cierre_externo_id, 'cooperativa', d.cooperativa, 'lead_id', d.lead_cierre)
      else jsonb_build_object('contrato_id', d.contrato_id, 'numero_contrato', d.numero_contrato, 'cliente_id', d.cliente_id)
      end end as fila
    from datos d
    left join public.perfiles pa on pa.id = d.analista_id
    left join public.perfiles ps on ps.id = d.supervisor_id
  ), totales as (
    select moneda, count(*) as operaciones, sum(monto) as monto from filtradas group by moneda
  )
  select jsonb_build_object('version', 1, 'pagina', p_pagina, 'tamano', p_tamano,
    'total', (select count(*) from filtradas),
    'totales', coalesce((select jsonb_agg(to_jsonb(t) order by t.moneda) from totales t), '[]'::jsonb),
    'filas', coalesce((select jsonb_agg(f.fila order by f.n) from filas f), '[]'::jsonb)) into v_resultado;
  return v_resultado;
end;
$function$
;
CREATE FUNCTION crm.listar_operaciones_facturacion_v2_fn(p_desde date, p_hasta date, p_dias date[] DEFAULT NULL::date[], p_analistas uuid[] DEFAULT NULL::uuid[], p_sin_analista boolean DEFAULT false, p_equipo uuid DEFAULT NULL::uuid, p_sin_equipo boolean DEFAULT false, p_tipos text[] DEFAULT NULL::text[], p_moneda text DEFAULT NULL::text, p_pagina integer DEFAULT 1, p_tamano integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.facturacion_lista_nombres(p_desde, p_hasta, p_dias, p_analistas, p_sin_analista, p_equipo, p_sin_equipo, p_tipos, p_moneda, p_pagina, p_tamano) || '{"version":2}'::jsonb;
$function$
;
alter function private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) owner to postgres;
alter function crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) owner to postgres;
revoke all on function private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) from public,anon,authenticated,service_role;
revoke all on function crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) from public,anon,authenticated,service_role;
grant execute on function crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) to authenticated;
comment on function private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) is 'Facturación v2: Coordinación activa recibe nombres exclusivamente para reporte, visible=false y sin identificadores de clientes. Otros roles delegan al núcleo v1.';
comment on function crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) is 'Lista de operaciones v2. Mismos filtros y cifras; nombres para Coordinación sin permiso de ficha ni escrituras. v1 permanece compatible.';
do $acl$
begin
  if has_function_privilege('authenticated','private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)','execute')
     or has_function_privilege('anon','crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)','execute')
     or has_function_privilege('service_role','crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)','execute')
     or not has_function_privilege('authenticated','crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)','execute')
     or (select prosecdef or provolatile<>'s' or proconfig is distinct from array['search_path=""']::text[]
         from pg_proc where oid=to_regprocedure('private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)'))
     or (select not prosecdef or provolatile<>'s' or proconfig is distinct from array['search_path=""']::text[]
         from pg_proc where oid=to_regprocedure('crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)')) then
    raise exception 'Facturación nombres: ACL o atributos inesperados';
  end if;
end $acl$;
do $nuevos$
declare r record;
begin
  for r in select * from (values
    ('private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '1f611c3a29e3c5594d6baa8243c56700'),
    ('crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '65b5ac0014d67b23024fe3208fb05b50')
  ) f(firma,huella) loop
    if (select md5(prosrc) from pg_proc where oid=to_regprocedure(r.firma)) is distinct from r.huella then
      raise exception 'Facturación nombres: cuerpo v2 inesperado en %',r.firma;
    end if;
  end loop;
end $nuevos$;
do $originales$
declare r record;
begin
  for r in select * from (values
    ('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', 'f98f0bea3397cb7f054e4f25b6ae5cb8'),
    ('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '3b84fe0660b2257398edfd835828f3eb')
  ) f(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'Facturación nombres: función publicada cambió en %; se deshace todo',r.firma;
    end if;
  end loop;
end $originales$;
commit;
