-- Ensayo para el PRIMARY autorizado. El error final PASS transporta evidencia y DESHACE TODO.
begin;
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
do $precondicion$
begin
  if (exists (select 1 from supabase_migrations.schema_migrations where version = '20261009224000'
    and name = 'crm_facturacion_una_fuente')) is not true then
    raise exception 'ENSAYO 3B: requiere la 3A REGISTRADA (20261009224000)';
  end if;
end $precondicion$;
-- INICIO MIGRACION
do $migracion$
declare
  v_funcion record;
  v_catalogo record;
  v_identidad record;
  v_filtro record;
  v_mes date;
  v_dias date[];
  v_uid uuid;
  v_aplicada boolean;
  v_resultado jsonb;
  v_sql text;
  v_negativas integer := 0;
  v_inicio timestamptz := clock_timestamp();
begin
  -- El argumento nuevo cambia la identidad SQL. Nunca convivir con una sobrecarga anterior.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where ((n.nspname = 'private' and p.proname = 'facturacion_lista')
        or (n.nspname = 'crm' and p.proname = 'listar_operaciones_facturacion_fn'))
      and p.oid is distinct from to_regprocedure(n.nspname || '.' || p.proname ||
        '(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)')) then
    raise exception 'PREFLIGHT 3B: firma anterior o sobrecarga inesperada; revertir con su kit antes de instalar';
  end if;
  -- Cerrar también un estado parcial: o faltan las DOS piezas o existen las DOS selladas.
  v_aplicada := to_regprocedure('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)') is not null;
  if (v_aplicada = (to_regprocedure('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)') is not null)) is not true then
    raise exception 'PREFLIGHT 3B: instalación parcial; no se sobrescribe';
  end if;
  create temporary table f3b_funciones (
    firma text primary key, nueva text, definidor boolean, lenguaje text, acl text, dependencia boolean
  ) on commit drop;
-- INICIO HUELLAS
  insert into pg_temp.f3b_funciones values
    ('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', 'e8c3178b74ec5718e87b5b5fc697e1fd', false, 'plpgsql', '{postgres=X/postgres}', false),
    ('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '3b84fe0660b2257398edfd835828f3eb', true, 'sql', '{postgres=X/postgres,authenticated=X/postgres}', false);
-- FIN HUELLAS
  insert into pg_temp.f3b_funciones values
    ('private.facturacion_operaciones(timestamptz,timestamptz)', '5d63cb537b0b286ad47feb7f5b26d161', false, 'sql', '{postgres=X/postgres}', true),
    ('private.facturacion_operaciones_visibles(timestamptz,timestamptz)', '17c2ca27996adad88f685896915953e3', false, 'sql', '{postgres=X/postgres}', true),
    ('crm.facturacion_diaria_fn(date)', '3753d03552e26eb7e61117a3baab6f78', true, 'sql', '{postgres=X/postgres,authenticated=X/postgres}', true);
  for v_funcion in select * from pg_temp.f3b_funciones where dependencia or v_aplicada loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = v_funcion.nueva and v_catalogo.dueno = 'postgres'
        and v_catalogo.acl = v_funcion.acl and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = v_funcion.lenguaje
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception 'PREFLIGHT 3B: huella/contrato inesperado en %: %', v_funcion.firma, row_to_json(v_catalogo);
    end if;
  end loop;

  if not v_aplicada then
-- INICIO CUERPOS
  execute $def$
CREATE OR REPLACE FUNCTION private.facturacion_lista(p_desde date, p_hasta date, p_dias date[] DEFAULT NULL, p_analistas uuid[] DEFAULT NULL, p_sin_analista boolean DEFAULT false, p_equipo uuid DEFAULT NULL, p_sin_equipo boolean DEFAULT false, p_tipos text[] DEFAULT NULL, p_moneda text DEFAULT NULL, p_pagina integer DEFAULT 1, p_tamano integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_contratos_todos boolean;
  v_cooperativas_todas boolean;
  v_clientes uuid[] := '{}'::uuid[];
  v_vendedores uuid[] := '{}'::uuid[];
  v_resultado jsonb;
begin
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
  if not v_contratos_todos then
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
      coalesce(case when p.tipo = 'cooperativa' then
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
                       where not v_contratos_todos and ce.inversionista_id is not null) can on true
    left join crm.inversionistas i on i.id = can.id
    left join crm.leads l on l.id = ce.lead_id
  ), filas as (
    select d.n, jsonb_build_object(
      'n', d.n, 'fecha', d.dia, 'tipo', d.tipo, 'moneda', d.moneda, 'monto', d.monto,
      'anulado', d.anulado, 'analista_id', d.analista_id,
      'analista_nombre', coalesce(pa.nombre_completo, 'Sin analista'),
      'supervisor_id', d.supervisor_id, 'supervisor_nombre', coalesce(ps.nombre_completo, 'Sin supervisor'),
      'visible', d.visible, 'cliente_nombre', case when not d.visible then 'Cliente de otro equipo'
        when d.tipo = 'cooperativa' then d.nombre_cooperativa else d.nombre_cliente end
    ) || case when not d.visible then '{}'::jsonb else
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
$def$;
  execute $def$
CREATE OR REPLACE FUNCTION crm.listar_operaciones_facturacion_fn(p_desde date, p_hasta date, p_dias date[] DEFAULT NULL, p_analistas uuid[] DEFAULT NULL, p_sin_analista boolean DEFAULT false, p_equipo uuid DEFAULT NULL, p_sin_equipo boolean DEFAULT false, p_tipos text[] DEFAULT NULL, p_moneda text DEFAULT NULL, p_pagina integer DEFAULT 1, p_tamano integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.facturacion_lista(p_desde, p_hasta, p_dias, p_analistas, p_sin_analista, p_equipo, p_sin_equipo, p_tipos, p_moneda, p_pagina, p_tamano);
$function$
$def$;
-- FIN CUERPOS
  alter function private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) owner to postgres;
  alter function crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) owner to postgres;
  revoke all on function private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) from public, anon, authenticated, service_role;
  revoke all on function crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) from public, anon, service_role;
  grant execute on function crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) to authenticated;
  comment on function private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) is
    'Lista paginada de Facturación: una llamada a la fuente visible de la cifra; supervisor de entonces y cuenta viva incluso en meses sellados. Datos del cliente según relación de hoy; arreglos de visibilidad una vez, enriquecimiento solo de la página. DNI y datos bancarios nunca se proyectan. Sin registro de lecturas. Solo postgres ejecuta el núcleo.';
  comment on function crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer) is
    'Puerta de Facturación en dos capas: (1) operaciones e importes exclusivamente de private.facturacion_operaciones_visibles, la misma fuente de la cifra; sin autorización devuelve vacío; (2) datos del cliente según su relación actual: Gerencia ve todo; Directorio ve contratos y enmascara toda cooperativa. En cooperativas rige la relación de hoy del teléfono vivo de crm.cierres_externos_fn, más estricta que su reparto por analista_efectivo_cierre. Excepción explícita del contrato de respuesta: la fila de otro equipo conserva analista, supervisor, día, tipo, moneda, importe y anulado, ya mostrados por la cifra o que explican por qué cuenta. Ni un id de cliente, contrato, cierre o lead; tampoco número ni estado. DNI nunca. Mes sellado = cuenta viva. Sin auditoría de aperturas.';
  end if;

-- INICIO COMPARADOR
  execute $def$
create or replace function pg_temp.f3b_comparar(p_mes date, p_dias date[] default null, p_analistas uuid[] default null, p_sin_analista boolean default false,
  p_equipo uuid default null, p_sin_equipo boolean default false, p_tipos text[] default null,
  p_moneda text default null, p_tamano integer default 100) returns jsonb
language plpgsql set search_path = '' as $comparador$
declare
  v_pagina integer := 1;
  v_respuesta jsonb;
  v_filas jsonb := '[]';
  v_cifra jsonb;
  v_totales jsonb;
  v_total bigint;
  v_gerencia boolean := coalesce(private.rol_crm(auth.uid()) = 'gerencia', false);
  v_directorio boolean := coalesce(private.es_lector_global(), false) and not v_gerencia;
  v_esperadas jsonb;
  v_par record;
  v_clientes uuid[] := array(select c.cliente_id from private.cliente_ids_visibles_crm() c);
  v_comunes text[] := array['n','fecha','tipo','moneda','monto','anulado','analista_id','analista_nombre',
    'supervisor_id','supervisor_nombre','visible','cliente_nombre'];
  v_inicio timestamptz := clock_timestamp();
begin
  select coalesce(jsonb_agg(to_jsonb(f)), '[]') into v_cifra from crm.facturacion_diaria_fn(p_mes) f
  where (p_dias is null or f.dia = any(p_dias))
    and (p_analistas is null or f.analista_id = any(p_analistas))
    and (p_sin_analista is not true or f.analista_id is null)
    and (p_equipo is null or f.supervisor_id = p_equipo)
    and (p_sin_equipo is not true or f.supervisor_id is null)
    and (p_tipos is null or f.tipo = any(p_tipos)) and (p_moneda is null or f.moneda = p_moneda);
  -- Origen independiente del DTO: conservar la secuencia de operaciones y resolver la relación
  -- con EXISTS, como el teléfono vivo. No reutilizar banderas ni joins del núcleo de la lista.
  with esperadas as (
    select row_number() over(order by o.fecha, o.tipo, o.operacion_id) as n,
      (o.fecha at time zone 'America/Lima')::date as fecha,
      o.tipo, o.moneda, o.monto, o.anulado, o.analista_id, o.supervisor_id,
      o.contrato_id, o.cliente_id, c.numero_contrato, o.cierre_externo_id, ce.lead_id, ce.cooperativa,
      case when v_gerencia then true
        when o.tipo <> 'cooperativa' then v_directorio or coalesce(o.cliente_id = any(v_clientes), false)
        when v_directorio then false
        when ce.inversionista_id is not null then exists (
          select 1 from crm.inversionistas ip
          where ip.id = private.inversionista_canonica(ce.inversionista_id)
            and ip.responsable_relacion_id = any(array(select private.vendedor_ids_visibles(auth.uid()))))
        else coalesce(l.vendedor_id = any(array(select private.vendedor_ids_visibles(auth.uid()))), false)
      end as visible,
      -- Distingue el fallo de resolver un alias del fallo de abrir todas las cooperativas.
      exists (select 1 from crm.inversionistas ip where ip.id = ce.inversionista_id
        and ip.id <> private.inversionista_canonica(ce.inversionista_id)
        and ip.responsable_relacion_id = any(array(select private.vendedor_ids_visibles(auth.uid())))) as alias_propio
    from private.facturacion_operaciones_visibles(p_mes::timestamp at time zone 'America/Lima',
      (p_mes + interval '1 month')::timestamp at time zone 'America/Lima') o
    left join public.contratos c on c.id = o.contrato_id
    left join crm.cierres_externos ce on ce.id = o.cierre_externo_id
    left join crm.leads l on l.id = ce.lead_id
    where (p_dias is null or o.dia = any(p_dias))
      and (p_analistas is null or o.analista_id = any(p_analistas))
      and (p_sin_analista is not true or o.analista_id is null)
      and (p_equipo is null or o.supervisor_id = p_equipo)
      and (p_sin_equipo is not true or o.supervisor_id is null)
      and (p_tipos is null or o.tipo = any(p_tipos)) and (p_moneda is null or o.moneda = p_moneda)
  ) select coalesce(jsonb_agg(to_jsonb(e) order by e.n), '[]') into v_esperadas from esperadas e;
  loop
    v_respuesta := crm.listar_operaciones_facturacion_fn(p_mes, (p_mes + interval '1 month')::date - 1,
      p_dias, p_analistas, p_sin_analista, p_equipo, p_sin_equipo, p_tipos, p_moneda, v_pagina, p_tamano);
    if (jsonb_typeof(v_respuesta) = 'object'
        and v_respuesta ?& array['version','pagina','tamano','total','totales','filas']
        and v_respuesta - array['version','pagina','tamano','total','totales','filas'] = '{}'::jsonb) is not true then
      raise exception 'ORÁCULO 3B: claves raíz incorrectas' using errcode = 'P3B11';
    end if;
    if (v_respuesta->>'version' = '1' and (v_respuesta->>'pagina')::integer = v_pagina
        and (v_respuesta->>'tamano')::integer = p_tamano
        and jsonb_typeof(v_respuesta->'filas') = 'array'
        and jsonb_typeof(v_respuesta->'totales') = 'array'
        and (v_respuesta->>'total')::bigint >= 0) is not true then
      raise exception 'ORÁCULO 3B: formato o paginación inválidos' using errcode = 'P3B03';
    end if;
    if exists (select 1 from jsonb_array_elements(v_respuesta->'totales') t
      where (jsonb_typeof(t) = 'object' and t ?& array['moneda','operaciones','monto']
        and t - array['moneda','operaciones','monto'] = '{}'::jsonb) is not true) then
      raise exception 'ORÁCULO 3B: claves de totales incorrectas' using errcode = 'P3B05';
    end if;
    -- CADA respuesta entera: raíz, totales y filas. Nunca imprimir el documento.
    if exists (select 1 from pg_temp.f3b_documentos d
        where d.mes = p_mes and strpos(v_respuesta::text, d.documento) > 0) then
      raise exception 'ORÁCULO 3B: documento en la respuesta' using errcode = 'P3B02';
    end if;
    if v_pagina = 1 then
      v_total := (v_respuesta->>'total')::bigint;
      v_totales := v_respuesta->'totales';
      -- La cifra independiente acota el recorrido: un total corrupto no debe agotar el timeout.
      if (v_total = (select coalesce(sum(f.operaciones), 0)
          from jsonb_to_recordset(v_cifra) f(operaciones bigint))) is not true then
        raise exception 'ORÁCULO 3B: total de la lista distinto de la cifra' using errcode = case when p_dias is not null then 'P3B13' when p_sin_analista then 'P3B12' else 'P3B04' end;
      end if;
    end if;
    if ((v_respuesta->>'total')::bigint = v_total and v_respuesta->'totales' = v_totales
        and jsonb_array_length(v_respuesta->'filas') = least(p_tamano::bigint, greatest(0, v_total - (v_pagina::bigint - 1) * p_tamano))) is not true then
      raise exception 'ORÁCULO 3B: total, totales o longitud cambian entre páginas' using errcode = 'P3B03';
    end if;
    v_filas := v_filas || (v_respuesta->'filas');
    exit when v_pagina::bigint * p_tamano >= v_total;
    v_pagina := v_pagina + 1;
  end loop;
  if (jsonb_array_length(v_filas) = v_total and not exists (
    select 1 from jsonb_array_elements(v_filas) with ordinality f(fila, posicion)
    where ((fila->>'n')::bigint = posicion) is not true
  )) is not true then
    raise exception 'ORÁCULO 3B: n no es 1..total en orden, sin huecos ni repetidos' using errcode = 'P3B03';
  end if;
  -- Fila a fila por n: ni agregados iguales ni un duplicado del mismo importe prueban identidad.
  for v_par in
    select f.fila, e.fila as esperada
    from jsonb_array_elements(v_filas) with ordinality f(fila, n)
    full join jsonb_array_elements(v_esperadas) with ordinality e(fila, n) using(n)
    order by coalesce(f.n, e.n)
  loop
    if (v_par.fila is not null and v_par.esperada is not null
      and not exists (select 1 from unnest(array['n','fecha','tipo','moneda','monto','anulado','analista_id','supervisor_id']) k
        where v_par.fila->k is distinct from v_par.esperada->k)) is not true then
      raise exception 'ORÁCULO 3B: secuencia de operaciones incorrecta' using errcode = 'P3B10';
    end if;
    if v_par.fila->'visible' is distinct from v_par.esperada->'visible' then
      raise exception 'ORÁCULO 3B: visibilidad distinta de la relación esperada' using errcode =
        case when v_directorio and v_par.esperada->>'tipo' = 'cooperativa' then 'P3B09'
          when v_par.esperada->'visible' = 'true'::jsonb then 'P3B07'
          when v_par.esperada->>'tipo' <> 'cooperativa' then 'P3B01'
          when v_par.esperada->'alias_propio' = 'true'::jsonb then 'P3B08'
          else 'P3B06' end;
    end if;
    if v_par.esperada->'visible' = 'true'::jsonb and exists (
      select 1 from unnest(case when v_par.esperada->>'tipo' = 'cooperativa'
        then array['cierre_externo_id','lead_id','cooperativa']
        else array['contrato_id','cliente_id','numero_contrato'] end) k
      where v_par.fila->k is distinct from v_par.esperada->k
    ) then
      raise exception 'ORÁCULO 3B: identificadores distintos de la operación en n' using errcode = 'P3B10';
    end if;
  end loop;
  -- Compara multiconjuntos y NULL de analista/supervisor sin sentinelas ni nombres.
  if (not exists (
    with lista as (
      select f.fecha as dia, f.tipo, f.moneda, f.analista_id, f.supervisor_id,
        count(*)::bigint as operaciones, sum(f.monto) as capital
      from jsonb_to_recordset(v_filas) f(fecha date, tipo text, moneda text, analista_id uuid, supervisor_id uuid, monto numeric)
      group by f.fecha, f.tipo, f.moneda, f.analista_id, f.supervisor_id
    ), cifra as (
      select f.dia, f.tipo, f.moneda, f.analista_id, f.supervisor_id, f.operaciones, f.capital
      from jsonb_to_recordset(v_cifra) f(dia date, tipo text, moneda text, analista_id uuid, supervisor_id uuid, operaciones bigint, capital numeric)
    )
    (select * from lista except all select * from cifra)
    union all (select * from cifra except all select * from lista)
  )) is not true then
    raise exception 'ORÁCULO 3B: LA LISTA NO SUMA LA CIFRA' using errcode = 'P3B04';
  end if;
  if (not exists (
    with cifra as (
      select f.moneda, sum(f.operaciones) as operaciones, sum(f.capital) as monto
      from jsonb_to_recordset(v_cifra) f(moneda text, operaciones bigint, capital numeric) group by f.moneda
    ), totales as (
      select t.moneda, t.operaciones, t.monto from jsonb_to_recordset(v_totales) t(moneda text, operaciones numeric, monto numeric)
    )
    (select * from cifra except all select * from totales)
    union all (select * from totales except all select * from cifra)
  )) is not true then
    raise exception 'ORÁCULO 3B: totales no coinciden por moneda con la cifra' using errcode = 'P3B05';
  end if;
  if (not exists (
    select 1 from jsonb_array_elements(v_filas) f(fila)
    where case when fila->'visible' = 'false'::jsonb then
      -- EXACTAMENTE las claves permitidas, también se exige que no falte ninguna.
      (fila ?& v_comunes and fila - v_comunes = '{}'::jsonb
        and fila->>'cliente_nombre' = 'Cliente de otro equipo' and not v_gerencia) is not true
    when fila->'visible' = 'true'::jsonb then
      (fila ?& (v_comunes || array['estado'] || case when fila->>'tipo' = 'cooperativa'
          then array['cierre_externo_id','cooperativa','lead_id'] else array['contrato_id','numero_contrato','cliente_id'] end)
        and fila - (v_comunes || array['estado'] || case when fila->>'tipo' = 'cooperativa'
          then array['cierre_externo_id','cooperativa','lead_id'] else array['contrato_id','numero_contrato','cliente_id'] end) = '{}'::jsonb
        and (v_gerencia or v_directorio or fila->>'tipo' = 'cooperativa' or (fila->>'cliente_id')::uuid = any(v_clientes))) is not true
    else true end
  )) is not true then
    raise exception 'ORÁCULO 3B: capa de datos, claves o visibilidad de cliente incorrectas' using errcode = 'P3B01';
  end if;
  raise notice 'LISTA = CIFRA: uid %, mes %, días %, filtros %/%/%/%/%/%, % filas, % páginas de %, % ms',
    auth.uid(), p_mes, p_dias, p_analistas, p_sin_analista, p_equipo, p_sin_equipo, p_tipos, p_moneda, v_total, v_pagina, p_tamano,
    round(extract(epoch from clock_timestamp() - v_inicio) * 1000, 2);
  return jsonb_build_object('filas', v_total, 'enmascaradas',
    (select count(*) from jsonb_array_elements(v_filas) f where f->'visible' = 'false'::jsonb));
end $comparador$;
$def$;
-- FIN COMPARADOR

  create temporary table f3b_identidades (clase text, uid uuid) on commit drop;
  select e.perfil_id into v_uid from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if (v_uid is not null) is not true then raise exception 'ORÁCULO 3B: se necesita Gerencia activa'; end if;
  insert into pg_temp.f3b_identidades values ('gerencia', v_uid);
  for v_uid in select p.id from public.perfiles p left join crm.equipo e on e.perfil_id = p.id
    where p.activo is true and (p.rol = 'directorio' or e.rol_crm = 'directorio') order by p.id loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    if private.es_lector_global() is true then
      insert into pg_temp.f3b_identidades values ('directorio', v_uid);
      exit;
    end if;
  end loop;
  insert into pg_temp.f3b_identidades select 'supervisor', e.perfil_id from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'supervisor' order by e.perfil_id;
  select e.perfil_id into v_uid from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id limit 1;
  if (v_uid is not null) is not true then raise exception 'ORÁCULO 3B: se necesita vendedor activo'; end if;
  insert into pg_temp.f3b_identidades values ('vendedor', v_uid), ('sin sesión', null);
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);

  create temporary table f3b_operaciones on commit drop as
    select o.* from private.facturacion_operaciones('-infinity', 'infinity') o;
  create temporary table f3b_meses on commit drop as
    select distinct date_trunc('month', dia)::date as mes from pg_temp.f3b_operaciones where isfinite(dia)
    union select date_trunc('month', now() at time zone 'America/Lima')::date;
  if (exists(select 1 from pg_temp.f3b_operaciones where isfinite(dia))) is not true then
    raise exception 'ORÁCULO 3B: se necesitan operaciones; no se admite un PASS vacío';
  end if;
  create temporary table f3b_documentos on commit drop as
    select distinct date_trunc('month', o.dia)::date as mes, btrim(d.documento) as documento
    from pg_temp.f3b_operaciones o
    left join public.perfiles p on p.id = o.cliente_id
    left join crm.cierres_externos ce on ce.id = o.cierre_externo_id
    left join crm.leads l on l.id = coalesce(o.lead_id, ce.lead_id)
      or (o.tipo <> 'cooperativa' and l.perfil_id = o.cliente_id)
    left join crm.inversionistas ip on ip.perfil_id = o.cliente_id
    left join crm.inversionista_identificadores ii on ii.inversionista_id in (
      ce.inversionista_id, l.inversionista_id, ip.id,
      private.inversionista_canonica(ce.inversionista_id), private.inversionista_canonica(l.inversionista_id),
      private.inversionista_canonica(ip.id))
    cross join lateral unnest(array[p.dni, p.beneficiario_dni, p.beneficiario_dni_usd, ce.documento,
      l.dni, ii.documento_normalizado, ii.documento_original]) d(documento)
    where length(btrim(d.documento)) >= 6;
  create temporary table f3b_evidencia (clase text, uid uuid, mes date, filas bigint, enmascaradas bigint) on commit drop;
  for v_identidad in select * from pg_temp.f3b_identidades order by clase, uid loop
    perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
      jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
    for v_mes in select mes from pg_temp.f3b_meses order by mes loop
      v_resultado := pg_temp.f3b_comparar(v_mes);
      if v_identidad.clase in ('vendedor', 'sin sesión') and ((v_resultado->>'filas')::bigint = 0) is not true then
        raise exception 'ORÁCULO 3B: identidad no autorizada recibe operaciones' using errcode = 'P3B04';
      end if;
      insert into pg_temp.f3b_evidencia values (v_identidad.clase, v_identidad.uid, v_mes,
        (v_resultado->>'filas')::bigint, (v_resultado->>'enmascaradas')::bigint);
    end loop;
  end loop;

  -- Cada filtro contra la parte correspondiente de la cifra, en el mes con MÁS operaciones, por cada identidad.
  select date_trunc('month', dia)::date into v_mes from pg_temp.f3b_operaciones where isfinite(dia)
    group by 1 order by count(*) desc, 1 desc limit 1;
  -- Dos días distintos con operaciones; no ampliar a todo el intervalo entre ellos.
  -- El mismo conjunto se contrasta para TODAS las identidades, incluidas las no autorizadas (vacío).
  select array_agg(dia order by dia) into v_dias from (
    select min(dia) as dia from pg_temp.f3b_operaciones where dia >= v_mes and dia < v_mes + interval '1 month'
    union
    select max(dia) from pg_temp.f3b_operaciones where dia >= v_mes and dia < v_mes + interval '1 month'
  ) dias;
  if (cardinality(v_dias) between 2 and 3) is not true then
    raise exception 'ORÁCULO 3B: el mes con más operaciones necesita al menos dos días con operaciones';
  end if;
  for v_identidad in select * from pg_temp.f3b_identidades loop
    perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
      jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
    for v_filtro in select distinct analista_id from pg_temp.f3b_operaciones
      where dia >= v_mes and dia < v_mes + interval '1 month' and analista_id is not null loop
      perform pg_temp.f3b_comparar(v_mes, p_analistas => array[v_filtro.analista_id]);
    end loop;
    for v_filtro in select distinct supervisor_id from pg_temp.f3b_operaciones
      where dia >= v_mes and dia < v_mes + interval '1 month' and supervisor_id is not null loop
      perform pg_temp.f3b_comparar(v_mes, p_equipo => v_filtro.supervisor_id);
    end loop;
    perform pg_temp.f3b_comparar(v_mes, p_dias => v_dias);
    perform pg_temp.f3b_comparar(v_mes, p_sin_analista => true);
    perform pg_temp.f3b_comparar(v_mes, p_sin_equipo => true);
    for v_filtro in select unnest(array['contrato_nuevo','contrato_upgrade','contrato_renovacion','cooperativa']) as tipo loop
      perform pg_temp.f3b_comparar(v_mes, p_tipos => array[v_filtro.tipo]);
    end loop;
    perform pg_temp.f3b_comparar(v_mes, p_moneda => 'PEN');
    perform pg_temp.f3b_comparar(v_mes, p_moneda => 'USD');
  end loop;

  -- Solo 22023 es éxito: ni un error de permisos, sintaxis o tipos puede esconder una negativa rota.
  for v_sql in select unnest(array[
    $$null, '2026-10-31'$$, $$'2026-10-01', null$$, $$'2026-10-02', '2026-10-01'$$,
    $$'2026-10-01', '2026-11-01'$$, $$'-infinity', '2026-10-01'$$, $$'2026-10-01', 'infinity'$$,
    $$'2026-10-01', '2026-10-31', p_tamano => null$$,
    $$'2026-10-01', '2026-10-31', p_tamano => 0$$,
    $$'2026-10-01', '2026-10-31', p_tamano => 26$$,
    $$'2026-10-01', '2026-10-31', p_pagina => null$$,
    $$'2026-10-01', '2026-10-31', p_pagina => 0$$,
    $$'2026-10-01', '2026-10-31', p_pagina => -1$$,
    $$'2026-10-01', '2026-10-31', p_moneda => 'EUR'$$,
    $$'2026-10-01', '2026-10-31', p_moneda => ''$$,
    $$'2026-10-01', '2026-10-31', p_equipo => '00000000-0000-0000-0000-000000000001', p_sin_equipo => true$$,
    $$'2026-10-01', '2026-10-31', p_analistas => '{}'::uuid[]$$,
    $$'2026-10-01', '2026-10-31', p_analistas => array['00000000-0000-0000-0000-000000000001'::uuid], p_sin_analista => true$$,
    $$'2026-10-01', '2026-10-31', p_tipos => '{}'::text[]$$,
    $$'2026-10-01', '2026-10-31', p_dias => '{}'::date[]$$,
    $$'2026-10-01', '2026-10-31', p_dias => array['2026-10-02'::date, null]$$,
    $$'2026-10-01', '2026-10-31', p_dias => array['2026-10-02'::date, '2026-11-01'::date]$$
  ]) loop
    begin
      execute 'select crm.listar_operaciones_facturacion_fn(' || v_sql || ')';
      raise exception 'NEGATIVA 3B no rechazó parámetros: %', v_sql;
    exception when sqlstate '22023' then v_negativas := v_negativas + 1;
    end;
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  drop function pg_temp.f3b_comparar(date,date[],uuid[],boolean,uuid,boolean,text[],text,integer);
  create temporary table f3b_resumen on commit drop as select
    (select count(*) from pg_temp.f3b_meses) as meses,
    (select min(mes) from pg_temp.f3b_meses) as primero,
    (select max(mes) from pg_temp.f3b_meses) as ultimo,
    (select count(*) from pg_temp.f3b_identidades) as identidades,
    (select count(*) from pg_temp.f3b_identidades where clase = 'directorio') as directorios,
    (select count(*) from pg_temp.f3b_identidades where clase = 'supervisor') as supervisores,
    (select count(distinct uid) from pg_temp.f3b_evidencia where clase = 'supervisor' and filas > 0) as supervisores_con_filas,
    sum(filas) as filas, sum(enmascaradas) as enmascaradas, v_negativas as negativas,
    round(extract(epoch from clock_timestamp() - v_inicio) * 1000, 2) as ms
    from pg_temp.f3b_evidencia;
  raise notice 'ORÁCULO 3B PASS: %', (select row_to_json(r) from pg_temp.f3b_resumen r);
  -- Mostrar TODAS las huellas antes de rechazar los marcadores; nunca se desactiva la guarda.
  for v_funcion in select * from pg_temp.f3b_funciones loop
    raise notice 'HUELLA % = %', v_funcion.firma, md5(pg_get_functiondef(to_regprocedure(v_funcion.firma)));
  end loop;
  for v_funcion in select * from pg_temp.f3b_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = v_funcion.nueva and v_catalogo.dueno = 'postgres'
        and v_catalogo.acl = v_funcion.acl and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = v_funcion.lenguaje
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')
        and not has_function_privilege('anon', to_regprocedure(v_funcion.firma), 'EXECUTE')
        and not has_function_privilege('service_role', to_regprocedure(v_funcion.firma), 'EXECUTE')
        and has_function_privilege('authenticated', to_regprocedure(v_funcion.firma), 'EXECUTE') = v_funcion.definidor) is not true then
      raise exception 'POSTFLIGHT 3B: huella/contrato inesperado en %: %; esperada %; se deshace todo',
        v_funcion.firma, row_to_json(v_catalogo), v_funcion.nueva;
    end if;
  end loop;
  raise notice 'Facturación 3B %: lista = cifra y datos protegidos', case when v_aplicada then 'reverificada' else 'instalada' end;
end $migracion$;
-- FIN MIGRACION
do $resultado$
begin
  if ((select supervisores_con_filas > 0 from pg_temp.f3b_resumen)) is not true then
    raise exception 'ENSAYO 3B: ningún supervisor con filas; no acredita el recorte';
  end if;
  raise exception 'ENSAYO 3B PASS: evidencia %; huellas %; SE DESHACE TODO deliberadamente',
    (select row_to_json(r) from pg_temp.f3b_resumen r),
    (select jsonb_object_agg(firma, md5(pg_get_functiondef(to_regprocedure(firma)))) from pg_temp.f3b_funciones);
end $resultado$;
rollback;
