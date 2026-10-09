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
