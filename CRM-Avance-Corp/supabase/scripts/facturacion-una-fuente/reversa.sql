-- Reversa 3A: restaura el cuerpo vivo al byte, conserva su comentario y ACL.
-- ORDEN: esta reversa va ANTES que la de la fase 2 (20261009223000), que fija la huella vieja de la puerta; y DESPUÉS de
-- la de cualquier consumidor de las piezas (la 3B): si alguno existe, se niega.
-- Solo acepta la instalación completa conocida o la reversa ya completa. Sin CASCADE.
begin;
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
-- INICIO TRANSACCION
do $reversa$
declare
  v_funcion record;
  v_catalogo record;
  v_revertida boolean;
begin
  -- Puede ejecutarse tras el ensayo en la MISMA transacción.
  drop table if exists pg_temp.f3a_funciones;
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
  insert into pg_temp.f3a_funciones values
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])',
     '2ed07da302e9a1b881a4962724234dd7', '2ed07da302e9a1b881a4962724234dd7', true, '{postgres=X/postgres}');
  select md5(pg_get_functiondef(p.oid)) = f.anterior into v_revertida
  from pg_temp.f3a_funciones f join pg_proc p on p.oid = to_regprocedure(f.firma)
  where f.firma = 'crm.facturacion_diaria_fn(date)';
  for v_funcion in select * from pg_temp.f3a_funciones loop
    if v_funcion.anterior is null and v_revertida is true then
      if (to_regprocedure(v_funcion.firma) is null) is not true then
        raise exception 'REVERSA PREFLIGHT: queda % con la puerta viva; estado mixto', v_funcion.firma;
      end if;
      continue;
    end if;
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = case when v_revertida then v_funcion.anterior else v_funcion.nueva end
        and v_catalogo.dueno = 'postgres' and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = 'sql'
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception 'REVERSA PREFLIGHT: huella/contrato inesperado en %: %', v_funcion.firma, row_to_json(v_catalogo);
    end if;
  end loop;
  if v_revertida is true then
    drop table pg_temp.f3a_funciones;
    raise notice 'REVERSA 3A ya completa: cuerpo vivo, ACL y ausencia de piezas comprobados';
    return;
  end if;
  -- Las funciones SQL con cuerpo en texto no registran dependencias: un DROP sin CASCADE no ve a sus llamadores.
  if (exists (select 1 from pg_proc p
      where p.prosrc ~* 'private\.facturacion_operaciones(_visibles)?\s*\('
        and p.oid not in (select x from unnest(array[
              to_regprocedure('crm.facturacion_diaria_fn(date)'),
              to_regprocedure('private.facturacion_operaciones_visibles(timestamptz,timestamptz)'),
              to_regprocedure('private.facturacion_operaciones(timestamptz,timestamptz)')]::oid[]) x
            where x is not null))) is true then
    raise exception 'REVERSA PREFLIGHT: otra función usa las piezas de la 3A (¿la puerta de la 3B?); revierte primero esa';
  end if;
-- INICIO CUERPOS GENERADOS
  execute $def$
CREATE OR REPLACE FUNCTION crm.facturacion_diaria_fn(p_mes date DEFAULT NULL::date)
 RETURNS TABLE(dia date, tipo text, moneda text, analista_id uuid, analista_nombre text, supervisor_id uuid, supervisor_nombre text, operaciones bigint, capital numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
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
  ),
  mes as (
    -- Se normaliza en vez de rechazar: una fecha a mitad de mes solo puede querer
    -- decir ese mes. Y sin argumento vale el mes EN CURSO de Lima — un NULL que
    -- devolviera vacío en silencio sería indistinguible de «no se vendió nada».
    select coalesce(
      date_trunc('month', p_mes),
      date_trunc('month', (now() at time zone 'America/Lima'))
    )::date as ini
  ),
  episodios as (
    -- El ámbito va HACIA DENTRO del núcleo: sin autorización no se escanea el mes
    -- entero para tirarlo después. El supervisor entra GLOBAL aquí a propósito:
    -- su recorte es por el supervisor DE ENTONCES, que solo existe tras el
    -- rebobinado de abajo (ver cabecera).
    select
      (e.fecha at time zone 'America/Lima')::date as dia,
      e.tipo,
      e.moneda,
      e.analista_id,
      e.monto
    from ambito a
    cross join mes m
    cross join lateral private.capital_episodios(
      (m.ini::timestamp at time zone 'America/Lima'),
      (((m.ini + interval '1 month')::date)::timestamp at time zone 'America/Lima'),
      a.ok, '{}'::uuid[]
    ) e
    where a.ok
      and e.medida = 'stock'
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
    ep.dia,
    ep.tipo,
    ep.moneda,
    ep.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    coalesce(t.supervisor_id, eq.supervisor_id) as supervisor_id,
    coalesce(ps.nombre_completo, 'Sin supervisor') as supervisor_nombre,
    count(*)::bigint as operaciones,
    sum(ep.monto) as capital
  from episodios ep
  cross join ambito a
  -- Los tramos de un analista son disjuntos y cubren toda la línea temporal, así
  -- que este join casa como mucho una fila. `crm.equipo.perfil_id` es PK.
  left join tramos t
    on t.analista_id = ep.analista_id
   and ep.dia >= t.desde
   and ep.dia <  t.hasta
  left join crm.equipo eq on eq.perfil_id = ep.analista_id
  left join public.perfiles pf on pf.id = ep.analista_id
  -- LOS DOS CAMINOS AL EQUIPO DE HOY, y son deliberados: no hay tramo (nunca se
  -- registró un cambio) o el tramo dice NULL («no constaba jerarquía entonces»).
  -- Ver la nota de la cabecera de 20260910230000: en un informe de dinero «no
  -- consta» no deja el importe sin dueño.
  left join public.perfiles ps
    on ps.id = coalesce(t.supervisor_id, eq.supervisor_id)
  -- EL RECORTE DEL SUPERVISOR (ver cabecera): el supervisor de entonces es él o
  -- alguien de su subárbol, o la venta es suya. Gerencia y el lector global
  -- pasan enteros. Un `= any('{}')` es false y un supervisor NULL da NULL: para
  -- quien no es supervisor solo queda `es_global`, que para él es false — y de
  -- todos modos `episodios` ya salió vacío por `a.ok`.
  where a.es_global
     or coalesce(t.supervisor_id, eq.supervisor_id) = any(a.subarbol)
     or ep.analista_id = a.uid
  group by ep.dia, ep.tipo, ep.moneda, ep.analista_id, pf.nombre_completo,
           coalesce(t.supervisor_id, eq.supervisor_id), ps.nombre_completo
  -- PEN y USD no comparten escala: la moneda ordena ANTES que el importe, para no
  -- rankear US$ 10 000 por debajo de S/ 50 000.
  order by ep.dia, ep.moneda, sum(ep.monto) desc;
$function$
$def$;

-- FIN CUERPOS GENERADOS
  alter function crm.facturacion_diaria_fn(date) owner to postgres;
  revoke execute on function crm.facturacion_diaria_fn(date) from public, anon, service_role;
  grant execute on function crm.facturacion_diaria_fn(date) to authenticated;
  drop function private.facturacion_operaciones_visibles(timestamptz,timestamptz);
  drop function private.facturacion_operaciones(timestamptz,timestamptz);
  for v_funcion in select * from pg_temp.f3a_funciones loop
    if v_funcion.anterior is null then
      if (to_regprocedure(v_funcion.firma) is null) is not true then
        raise exception 'REVERSA POSTFLIGHT: no desapareció %', v_funcion.firma;
      end if;
      continue;
    end if;
    if ((select md5(pg_get_functiondef(p.oid)) = v_funcion.anterior
        and pg_get_userbyid(p.proowner) = 'postgres' and p.proacl::text = v_funcion.acl
        and p.prosecdef = v_funcion.definidor and p.provolatile = 's' and l.lanname = 'sql'
        and cardinality(p.proconfig) = 1 and p.proconfig[1] in ('search_path=', 'search_path=""')
      from pg_proc p join pg_language l on l.oid = p.prolang
      where p.oid = to_regprocedure(v_funcion.firma))) is not true then
      raise exception 'REVERSA POSTFLIGHT: no se restauró exactamente %', v_funcion.firma;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  drop table pg_temp.f3a_funciones;
  raise notice 'REVERSA 3A PASS: huella viva y ACL exactas; dos piezas eliminadas';
end $reversa$;
-- FIN TRANSACCION
commit;
