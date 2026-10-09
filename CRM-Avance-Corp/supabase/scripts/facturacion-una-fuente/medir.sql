-- SOLO Miguel con !, después del banco. MISMA transacción, siempre deshecha por RAISE.
-- ! supabase db query --linked --file supabase/scripts/facturacion-una-fuente/medir.sql
-- Mediana de 7 muestras por mes y etapa, tras una llamada de calentamiento.
-- El umbral se aplica POR MES: mediana después <= mediana antes * 1.20.
begin;
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
create temporary table f3a_tiempos (etapa text, mes date, muestra integer, ms numeric) on commit drop;
create temporary table f3a_medicion_actor (uid uuid not null) on commit drop;
do $precondicion$
begin
  if ((select md5(pg_get_functiondef(to_regprocedure('crm.facturacion_diaria_fn(date)'))))
      = '4b11e1da336f2f296c81f064ce30e35b') is not true then
    raise exception 'MEDICIÓN: exige la puerta VIVA antes de migrar; no medir nuevo contra nuevo';
  end if;
  insert into pg_temp.f3a_medicion_actor select e.perfil_id from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if ((select count(*) = 1 from pg_temp.f3a_medicion_actor)) is not true then
    raise exception 'MEDICIÓN: falta Gerencia activa';
  end if;
end $precondicion$;
create function pg_temp.f3a_medir(p_etapa text) returns void language plpgsql as $medir$
declare
  v_uid uuid := (select uid from pg_temp.f3a_medicion_actor);
  v_mes date;
  v_i integer;
  v_inicio timestamptz;
  v_filas bigint;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  foreach v_mes in array array[date '2026-10-01', date '2026-09-01'] loop
    for v_i in 0..7 loop
      v_inicio := clock_timestamp();
      select count(*) into v_filas from crm.facturacion_diaria_fn(v_mes);
      if (v_filas > 0) is not true then
        raise exception 'MEDICIÓN: % está vacío; la línea base no es representativa', v_mes;
      end if;
      if v_i > 0 then
        insert into pg_temp.f3a_tiempos values (p_etapa, v_mes, v_i,
          extract(epoch from clock_timestamp() - v_inicio) * 1000);
      end if;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $medir$;
select pg_temp.f3a_medir('antes');
-- INICIO MIGRACION
do $migracion$
declare
  v_funcion record;
  v_catalogo record;
  v_identidad record;
  v_mes date;
  v_primero date;
  v_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_uid uuid;
  v_aplicada boolean;
  v_inicio timestamptz := clock_timestamp();
  v_etapa text := 'PREFLIGHT';
begin
  -- PRECONDICIÓN: la fase 2. Su registrador y su reversa fijan la huella VIEJA de esta puerta, así que tras la 3A las
  -- reversas van en orden inverso: primero la de la 3A.
  if ((select md5(pg_get_functiondef(p.oid)) from pg_proc p
       where p.oid = to_regprocedure('private.trg_equipo_evento_jerarquia()'))
      = '93906f654ba2e4c358ecfe6da1c95f77') is not true then
    raise exception 'PREFLIGHT: falta la fase 2 (20261009223000) aplicada; la 3A va después';
  end if;
  create temporary table f3a_funciones (
    firma text primary key, anterior text, nueva text not null,
    definidor boolean not null, acl text not null
  ) on commit drop;
-- INICIO HUELLAS
  insert into pg_temp.f3a_funciones values
    ('crm.facturacion_diaria_fn(date)', '4b11e1da336f2f296c81f064ce30e35b', '3753d03552e26eb7e61117a3baab6f78', true, '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.facturacion_operaciones(timestamptz,timestamptz)', null, '5d63cb537b0b286ad47feb7f5b26d161', false, '{postgres=X/postgres}'),
    ('private.facturacion_operaciones_visibles(timestamptz,timestamptz)', null, '17c2ca27996adad88f685896915953e3', false, '{postgres=X/postgres}');
-- FIN HUELLAS
  -- La dependencia viva también queda sellada por huella, dueño y permisos.
  insert into pg_temp.f3a_funciones values
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])',
     '2ed07da302e9a1b881a4962724234dd7', '2ed07da302e9a1b881a4962724234dd7', true, '{postgres=X/postgres}');
  select md5(pg_get_functiondef(p.oid)) = f.nueva into v_aplicada
  from pg_temp.f3a_funciones f join pg_proc p on p.oid = to_regprocedure(f.firma)
  where f.firma = 'crm.facturacion_diaria_fn(date)';
  for v_funcion in select * from pg_temp.f3a_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if v_funcion.anterior is null and v_aplicada is not true then
      if (to_regprocedure(v_funcion.firma) is null) is not true then
        raise exception 'PREFLIGHT: ya existe % sin la puerta migrada; no se sobrescribe', v_funcion.firma;
      end if;
      continue;
    end if;
    if (v_catalogo.huella = case when v_aplicada then v_funcion.nueva else v_funcion.anterior end
        and v_catalogo.dueno = 'postgres' and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = 'sql'
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception 'PREFLIGHT: huella/contrato inesperado en %: %', v_funcion.firma, row_to_json(v_catalogo);
    end if;
  end loop;
  if v_aplicada is true then
    perform set_config('request.jwt.claims', '{}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    drop table pg_temp.f3a_funciones;
    raise notice 'Facturación 3A ya aplicada: cuatro huellas y contratos verificados';
    return;
  end if;

  create temporary table f3a_identidades (
    identidad integer generated always as identity primary key, clase text not null, uid uuid
  ) on commit drop;
  select e.perfil_id into v_uid from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if (v_uid is not null) is not true then
    raise exception 'ORÁCULO: se necesita una Gerencia activa';
  end if;
  insert into pg_temp.f3a_identidades(clase, uid) values ('gerencia', v_uid);
  -- Directorio se comprueba con su capacidad real, incluido el fallback Portal.
  for v_uid in select p.id from public.perfiles p
    left join crm.equipo e on e.perfil_id = p.id
    where p.activo is true and (p.rol = 'directorio' or e.rol_crm = 'directorio')
    order by p.id
  loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    if private.es_lector_global() is true then
      insert into pg_temp.f3a_identidades(clase, uid) values ('directorio', v_uid);
      exit;
    end if;
  end loop;
  insert into pg_temp.f3a_identidades(clase, uid)
    select 'supervisor', e.perfil_id from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'supervisor' order by e.perfil_id;
  select e.perfil_id into v_uid from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id limit 1;
  if (v_uid is not null) is not true then
    raise exception 'ORÁCULO: se necesita un vendedor activo';
  end if;
  insert into pg_temp.f3a_identidades(clase, uid) values ('vendedor', v_uid), ('sin sesión', null);
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- Solo los meses CON operaciones, más el mes en curso. Un mes vacío da vacío antes y después, y una fecha mal
  -- tecleada (año 0202) no convierte el oráculo en miles de llamadas. Cubre también meses futuros con datos.
  create temporary table f3a_meses on commit drop as
    select distinct date_trunc('month', (e.fecha at time zone 'America/Lima'))::date as mes
    from private.capital_episodios('-infinity', 'infinity', true, '{}'::uuid[]) e
    where e.medida = 'stock' and isfinite(e.fecha);
  select min(mes) into v_primero from pg_temp.f3a_meses;
  if (v_primero is not null and isfinite(v_primero)) is not true then
    raise exception 'ORÁCULO: no hay meses finitos con operaciones';
  end if;
  insert into pg_temp.f3a_meses
    select v_actual where not exists (select 1 from pg_temp.f3a_meses where mes = v_actual);
  create temporary table f3a_antes (
    identidad integer, mes date, dia date, tipo text, moneda text,
    analista_id uuid, analista_nombre text, supervisor_id uuid, supervisor_nombre text,
    operaciones bigint, capital numeric
  ) on commit drop;
  create temporary table f3a_despues (like pg_temp.f3a_antes) on commit drop;
  for v_identidad in select * from pg_temp.f3a_identidades order by identidad loop
    perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
      jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
    for v_mes in select mes from pg_temp.f3a_meses order by mes loop
      insert into pg_temp.f3a_antes select v_identidad.identidad, v_mes, f.*
      from crm.facturacion_diaria_fn(v_mes) f;
    end loop;
  end loop;
  if (not exists (select 1 from pg_temp.f3a_antes f join pg_temp.f3a_identidades i using (identidad)
      where i.clase in ('vendedor', 'sin sesión'))) is not true then
    raise exception 'ORÁCULO: vendedor o sin sesión ya recibían filas antes del cambio';
  end if;

-- INICIO CUERPOS GENERADOS
  execute $def$
CREATE OR REPLACE FUNCTION private.facturacion_operaciones(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
  with episodios as (
    select (e.fecha at time zone 'America/Lima')::date as dia, e.*
    from private.capital_episodios(p_desde, p_hasta, true, '{}'::uuid[]) e
    where e.medida = 'stock'
  ),
  eventos as (
    select
      ue.objetivo_id as analista_id,
      (ue.creado_en at time zone 'America/Lima')::date as dia_cambio,
      (ue.detalle->>'supervisor_anterior')::uuid as antes,
      (ue.detalle->>'supervisor_nuevo')::uuid as despues,
      -- `ue.id` desempata: sin él, dos eventos en el mismo instante numerarían
      -- de forma no determinista y los tramos podrían solaparse.
      row_number() over (partition by ue.objetivo_id order by ue.creado_en, ue.id) as n
    from crm.usuario_eventos ue
    where ue.accion = 'jerarquia_actualizada'
  ),
  tramos as (
    -- Antes del primer cambio registrado.
    select e.analista_id, '-infinity'::date as desde, e.dia_cambio as hasta, e.antes as supervisor_id
    from eventos e
    where e.n = 1
    union all
    -- Entre un cambio y el siguiente (o hasta hoy, si fue el último). El día del
    -- cambio cuenta ya para el supervisor NUEVO; con dos cambios el mismo día, el
    -- tramo intermedio queda vacío y manda el último.
    select e.analista_id, e.dia_cambio, coalesce(sig.dia_cambio, 'infinity'::date), e.despues
    from eventos e
    left join eventos sig
      on sig.analista_id = e.analista_id and sig.n = e.n + 1
  )
  select
    coalesce(ep.contrato_id, ep.cierre_externo_id) as operacion_id,
    ep.dia, ep.fecha, ep.tipo, ep.moneda, ep.monto, ep.analista_id,
  -- LOS DOS CAMINOS AL EQUIPO DE HOY, y son deliberados: no hay tramo (nunca se
  -- registró un cambio) o el tramo dice NULL («no constaba jerarquía entonces»).
  -- Ver la nota de la cabecera de 20260910230000: en un informe de dinero «no
  -- consta» no deja el importe sin dueño.
    coalesce(t.supervisor_id, eq.supervisor_id) as supervisor_id,
    ep.contrato_id, ep.cierre_externo_id, ep.cliente_id, ep.lead_id,
    ep.registrado_por, ep.categoria, ep.estado, ep.anulado, ep.fecha_vencimiento
  from episodios ep
  -- Los tramos de un analista son disjuntos y cubren toda la línea temporal, así
  -- que este join casa como mucho una fila. `crm.equipo.perfil_id` es PK.
  left join tramos t
    on t.analista_id = ep.analista_id
   and ep.dia >= t.desde
   and ep.dia <  t.hasta
  left join crm.equipo eq on eq.perfil_id = ep.analista_id;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION private.facturacion_operaciones_visibles(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
  with quien as materialized (
    -- Una sola vez: quién pregunta y con qué rol. `private.rol_crm` devuelve
    -- NULL para quien no es miembro del CRM.
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() as lector
  ),
  ambito as materialized (
    -- La verja, en tres columnas. NULL = 'gerencia' es NULL, y el coalesce lo
    -- cierra en false. `ok` abre el núcleo; `es_global` y `subarbol` recortan.
    select
      q.uid,
      coalesce(q.uid is not null and (q.rol = 'gerencia' or q.lector), false) as es_global,
      coalesce(q.uid is not null and (q.rol in ('gerencia', 'supervisor') or q.lector), false) as ok,
      -- El subárbol de HOY del supervisor (él incluido). Para cualquier otro
      -- rol queda VACÍO a propósito: así el predicado final no puede abrirse
      -- por accidente para nadie más.
      case when coalesce(q.uid is not null and q.rol = 'supervisor', false)
           then array(select private.vendedor_ids_visibles(q.uid))
           else '{}'::uuid[] end as subarbol
    from quien q
  )
  select ep.*
  from (select * from ambito a where a.ok) a
  -- La dependencia de a.ok mantiene el lateral detrás de la verja incluso si
  -- el planificador reordena joins: con cero actores autorizados no se llama.
  cross join lateral private.facturacion_operaciones(
    case when a.ok then p_desde end, p_hasta
  ) ep
  -- EL RECORTE DEL SUPERVISOR (ver cabecera): el supervisor de entonces es él o
  -- alguien de su subárbol, o la venta es suya. Gerencia y el lector global
  -- pasan enteros. Un `= any('{}')` es false y un supervisor NULL da NULL: para
  -- quien no es supervisor solo queda `es_global`, que para él es false — y de
  -- todos modos `episodios` ya salió vacío por `a.ok`.
  where a.es_global
     or ep.supervisor_id = any(a.subarbol)
     or ep.analista_id = a.uid;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION crm.facturacion_diaria_fn(p_mes date DEFAULT NULL::date)
 RETURNS TABLE(dia date, tipo text, moneda text, analista_id uuid, analista_nombre text, supervisor_id uuid, supervisor_nombre text, operaciones bigint, capital numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with
  mes as (
    -- Se normaliza en vez de rechazar: una fecha a mitad de mes solo puede querer
    -- decir ese mes. Y sin argumento vale el mes EN CURSO de Lima — un NULL que
    -- devolviera vacío en silencio sería indistinguible de «no se vendió nada».
    select coalesce(
      date_trunc('month', p_mes),
      date_trunc('month', (now() at time zone 'America/Lima'))
    )::date as ini
  )
  select
    ep.dia,
    ep.tipo,
    ep.moneda,
    ep.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    ep.supervisor_id as supervisor_id,
    coalesce(ps.nombre_completo, 'Sin supervisor') as supervisor_nombre,
    count(*)::bigint as operaciones,
    sum(ep.monto) as capital
  from mes m
  cross join lateral private.facturacion_operaciones_visibles(
    (m.ini::timestamp at time zone 'America/Lima'),
    (((m.ini + interval '1 month')::date)::timestamp at time zone 'America/Lima')
  ) ep
  left join public.perfiles pf on pf.id = ep.analista_id
  left join public.perfiles ps on ps.id = ep.supervisor_id
  group by ep.dia, ep.tipo, ep.moneda, ep.analista_id, pf.nombre_completo,
           ep.supervisor_id, ps.nombre_completo
  -- PEN y USD no comparten escala: la moneda ordena ANTES que el importe, para no
  -- rankear US$ 10 000 por debajo de S/ 50 000.
  order by ep.dia, ep.moneda, sum(ep.monto) desc;
$function$
$def$;

-- FIN CUERPOS GENERADOS
  alter function private.facturacion_operaciones(timestamptz,timestamptz) owner to postgres;
  alter function private.facturacion_operaciones_visibles(timestamptz,timestamptz) owner to postgres;
  alter function crm.facturacion_diaria_fn(date) owner to postgres;
  revoke execute on function private.facturacion_operaciones(timestamptz,timestamptz),
    private.facturacion_operaciones_visibles(timestamptz,timestamptz) from public, anon, authenticated, service_role;
  revoke execute on function crm.facturacion_diaria_fn(date) from public, anon, service_role;
  grant execute on function crm.facturacion_diaria_fn(date) to authenticated;
  comment on function private.facturacion_operaciones(timestamptz,timestamptz) is
    'SIN VERJA: devuelve TODAS las operaciones de stock de la empresa (capital vivo, también en meses sellados), una fila por operación, con día de Lima y supervisor de entonces (caída al de hoy: 20260910230000). Su ÚNICO llamador es private.facturacion_operaciones_visibles; ninguna puerta la llama directo (el gate censa sus llamadores). Única fuente de la cifra y de la lista de Facturación. Sin EXECUTE para la API.';
  comment on function private.facturacion_operaciones_visibles(timestamptz,timestamptz) is
    'Única fuente VISIBLE de la cifra y de la lista de Facturación: la verja y el recorte del supervisor (supervisor de entonces en su subárbol de hoy, o ventas propias; ver 20260916205617) viven aquí. Sin autorización no llama al núcleo. Devuelve ids crudos (cliente, lead, registrado_por): la puerta de la lista DEBE aplicar la capa de datos (cliente de otro equipo sin nombre ni N.º, DNI nunca). Sus llamadores son una lista cerrada que censa el gate. Sin EXECUTE para la API.';

  for v_identidad in select * from pg_temp.f3a_identidades order by identidad loop
    perform set_config('request.jwt.claims', case when v_identidad.uid is null then '{}' else
      jsonb_build_object('sub', v_identidad.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(v_identidad.uid::text, ''), true);
    for v_mes in select mes from pg_temp.f3a_meses order by mes loop
      insert into pg_temp.f3a_despues select v_identidad.identidad, v_mes, f.*
      from crm.facturacion_diaria_fn(v_mes) f;
    end loop;
  end loop;
  if (not exists (
    (select * from pg_temp.f3a_antes except all select * from pg_temp.f3a_despues)
    union all
    (select * from pg_temp.f3a_despues except all select * from pg_temp.f3a_antes)
  )) is not true then
    raise exception 'ORÁCULO: cambió la salida completa (incluidos nombres o multiplicidad); se deshace todo';
  end if;
  -- Materializar UNA llamada por mes permite comprobar tanto las claves como el agregado.
  create temporary table f3a_operaciones on commit drop as
    select null::date as mes, o.* from private.facturacion_operaciones(null, null) o with no data;
  for v_mes in select mes from pg_temp.f3a_meses order by mes loop
    insert into pg_temp.f3a_operaciones select v_mes, o.*
    from private.facturacion_operaciones(
      v_mes::timestamp at time zone 'America/Lima',
      ((v_mes + interval '1 month')::date)::timestamp at time zone 'America/Lima'
    ) o;
  end loop;
  if (not exists (select 1 from pg_temp.f3a_operaciones
      group by operacion_id having operacion_id is null or count(*) > 1)) is not true then
    raise exception 'ORÁCULO: operacion_id nulo o repetido (incluidos solapamientos entre meses)';
  end if;
  create temporary table f3a_agregado on commit drop as
    select mes, dia, tipo, moneda, analista_id, supervisor_id,
      count(*)::bigint as operaciones, sum(monto) as capital
    from pg_temp.f3a_operaciones group by mes, dia, tipo, moneda, analista_id, supervisor_id;
  create temporary table f3a_gerencia on commit drop as
    select f.mes, f.dia, f.tipo, f.moneda, f.analista_id, f.supervisor_id, f.operaciones, f.capital
    from pg_temp.f3a_despues f join pg_temp.f3a_identidades i using (identidad) where i.clase = 'gerencia';
  if (not exists (
    (select * from pg_temp.f3a_agregado except all select * from pg_temp.f3a_gerencia)
    union all
    (select * from pg_temp.f3a_gerencia except all select * from pg_temp.f3a_agregado)
  )) is not true then
    raise exception 'ORÁCULO: el agregado directo del núcleo no coincide con Gerencia';
  end if;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'ORÁCULO PASS: % meses (% a %), % identidades (% Directorio), % filas antes / % después, % operaciones únicas; % ms',
    (select count(*) from pg_temp.f3a_meses), (select min(mes) from pg_temp.f3a_meses),
    (select max(mes) from pg_temp.f3a_meses),
    (select count(*) from pg_temp.f3a_identidades),
    (select count(*) from pg_temp.f3a_identidades where clase = 'directorio'),
    (select count(*) from pg_temp.f3a_antes), (select count(*) from pg_temp.f3a_despues),
    (select count(*) from pg_temp.f3a_operaciones),
    round(extract(epoch from clock_timestamp() - v_inicio) * 1000, 2);
  v_etapa := 'POSTFLIGHT';
  -- Imprimir todas antes de rechazar los marcadores; medir no desactiva el candado.
  for v_funcion in select * from pg_temp.f3a_funciones loop
    raise notice 'HUELLA % = %', v_funcion.firma, md5(pg_get_functiondef(to_regprocedure(v_funcion.firma)));
  end loop;
  for v_funcion in select * from pg_temp.f3a_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = v_funcion.nueva
        and v_catalogo.dueno = 'postgres' and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = 'sql'
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception '%: huella/contrato inesperado en %: %; esperada %; se deshace todo',
        v_etapa, v_funcion.firma, row_to_json(v_catalogo), v_funcion.nueva;
    end if;
  end loop;
  raise notice 'Facturación 3A aplicada: cifra intacta y fuente única preparada para 3B';
end $migracion$;
-- FIN MIGRACION
select pg_temp.f3a_medir('después');
do $resultado$
declare
  v_mes record;
  v_falla boolean := false;
  v_resumen text := '';
begin
  for v_mes in
    with medianas as (
      select mes, etapa, percentile_cont(0.5) within group (order by ms)::numeric as mediana,
        min(ms) as minimo, count(*) as muestras
      from pg_temp.f3a_tiempos group by mes, etapa
    )
    select a.mes, a.mediana as antes, d.mediana as despues, a.minimo as min_antes, d.minimo as min_despues,
      a.muestras = 7 and d.muestras = 7 and a.mediana > 0 and d.mediana <= a.mediana * 1.20 as pasa
    from medianas a join medianas d on a.mes = d.mes and d.etapa = 'después' where a.etapa = 'antes'
  loop
    raise notice 'MEDICIÓN %: mediana % → % ms; mínimo % → % ms; límite % ms: %',
      v_mes.mes, round(v_mes.antes, 2), round(v_mes.despues, 2), round(v_mes.min_antes, 2),
      round(v_mes.min_despues, 2), round(v_mes.antes * 1.20, 2), case when v_mes.pasa then 'PASS' else 'FAIL' end;
    v_resumen := v_resumen || format(' · %s: %s → %s ms (límite %s) %s', to_char(v_mes.mes, 'YYYY-MM'),
      round(v_mes.antes, 2), round(v_mes.despues, 2), round(v_mes.antes * 1.20, 2),
      case when v_mes.pasa then 'PASS' else 'FAIL' end);
    if v_mes.pasa is not true then v_falla := true; end if;
  end loop;
  if ((select count(*) = 28 from pg_temp.f3a_tiempos)) is not true then v_falla := true; end if;
  if v_falla is true then
    raise exception 'MEDICIÓN FAIL: supera línea base +20%% o faltan muestras%; SE DESHACE TODO', v_resumen;
  end if;
  raise exception 'MEDICIÓN PASS: septiembre y octubre dentro de línea base +20%%%; SE DESHACE TODO deliberadamente', v_resumen;
end $resultado$;
