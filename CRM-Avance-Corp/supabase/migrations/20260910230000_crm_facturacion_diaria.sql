-- crm_facturacion_diaria — la lectura diaria de la pantalla Facturación.
--
-- QUÉ HACE
-- Devuelve, para UN mes comercial: día × tipo de capital × moneda × analista ×
-- supervisor, con el número de operaciones y el capital. Es SOLO LECTURA: no crea
-- ni altera ninguna tabla, no toca `public` (solo lo lee) y no inventa una
-- segunda cuenta del dinero.
--
-- POR QUÉ LEE `private.capital_episodios` Y NO `public.contratos`
-- Ese es el núcleo del que ya salen Conversiones, Ranking y Metas (vía
-- `private.metricas_conversiones_implementacion` y `crm.metricas_capital_mes_fn`).
-- Reimplementar la cuenta aquí crearía una tercera verdad sobre el mismo dinero,
-- que es justo lo que el proyecto lleva meses evitando. El núcleo ya resuelve el
-- día comercial de Lima, la atribución por cadena de upgrade (ATR-2), el descarte
-- de lo demo y el ámbito. Está SELLADO POR HUELLA en migraciones anteriores: se
-- lee, no se toca. Verificado antes de escribir esta migración: para setiembre de
-- 2026 el cuerpo devuelve S/ 2 786 004 en `contrato_nuevo`, idéntico al núcleo.
--
-- ANULAR NO QUITA CAPITAL (ATR-4, decisión de Miguel del 31/08)
-- «Solo la conversión, siempre»: anular es una sanción al analista en su tasa de
-- conversión, no un borrado del dinero que la empresa recibió. Por eso aquí NO
-- hay filtro de anulados — igual que en `crm.metricas_capital_mes_fn`, y a
-- diferencia de `crm.altas_nuevas_por_analista_fn`, que sí los excluye porque
-- cuenta altas y no dinero.
--
-- GERENCIA Y LECTOR GLOBAL
-- La PANTALLA es exclusiva de Gerencia (`VISTAS_GERENCIA` en app/src/lib/router.ts).
-- El gate SQL admite además al LECTOR GLOBAL (Directorio), igual que todas sus
-- hermanas: por definición lee toda la empresa, y negárselo aquí sería una
-- excepción sin motivo. Es decir, «solo Gerencia» describe el menú, no la RPC.
-- Por mínimo privilegio: un vendedor o un supervisor
-- que llame a la RPC directamente por PostgREST recibe VACÍO, no un 42501 — es una
-- verja de visibilidad, no un cierre (criterio del auditor-rls, hallazgo M-1 del
-- 04/09). Consecuencia buscada: nadie fuera de Gerencia puede leer por esta vía a
-- qué supervisor pertenecía alguien de otro equipo.
--
-- EL SUPERVISOR ES EL DE ENTONCES, NO EL DE HOY (decisión de Miguel, 10/09/2026)
-- Cuando un analista cambia de equipo, sus ventas anteriores se quedan con el
-- supervisor que las tenía. Se reconstruye rebobinando `crm.usuario_eventos`
-- (`jerarquia_actualizada`) desde el estado de hoy en `crm.equipo`.
--   VALIDADO: el rebobinado reproduce las 16 filas de la foto ya sellada de agosto
--   de 2026 (`crm.cierre_mes_vendedor`), 16 de 16, cero discrepancias.
--   PRECISIÓN: DÍA, NO HORA — y no puede ser de otro modo. `fecha_cierre_comercial`
--   es un `date`: una venta no tiene hora. Si un analista cambiara de equipo dos
--   veces el mismo día, TODAS las ventas de ese día se atribuyen al último
--   supervisor del día. No es una pérdida evitable: el dato de la hora no existe.
--   (Refutación de Codex, 10/09; aceptada explícitamente.)
--
--   ESTADO REAL DE PRODUCCIÓN (10/09/2026): los 5 eventos registrados son PRIMERAS
--   ASIGNACIONES, no cambios de equipo — los 5 tienen `supervisor_anterior = null`
--   (3 son altas nuevas; 2 son gente que ya vendía y recibió supervisor el 10/08,
--   cuando se estrenó la pantalla de jerarquía). Es decir: hoy NADIE ha cambiado
--   de equipo, y el rebobinado no mueve ni un sol. Existe para el día que ocurra.
--
--   QUÉ SIGNIFICA UN `supervisor_anterior` NULL, Y POR QUÉ SE RESUELVE CON EL
--   EQUIPO DE HOY. Un NULL ahí no dice «no tenía jefe»: dice que el CRM todavía no
--   guardaba jerarquía para esa persona. En un informe de dinero, «no consta» no
--   puede dejar S/ 1 863 000 sin dueño en una fila «Sin supervisor» — se resuelve
--   con el equipo de hoy, que es la única respuesta con sentido. Es una regla
--   DELIBERADA, no un descuido del `coalesce`: por eso el tramo se elige por
--   existencia y el NULL se colapsa después, a la vista.
--
--   LÍMITE CONOCIDO: el CRM registra jerarquía desde el 07/08/2026. De las 331
--   ventas nuevas del histórico, 232 son anteriores; 9 de ellas son de gente con
--   evento posterior y 223 de gente sin ningún evento. Para todas ellas el
--   supervisor mostrado es el de hoy. Es la mejor respuesta disponible, pero no es
--   demostrable: la auditoría de `crm.equipo` está vacía en producción (0 filas).
--
-- POR QUÉ DEVUELVE `tipo`
-- Para no necesitar otra migración el día que Gerencia quiera mirar también
-- upgrades o cooperativas. La pantalla decide qué tipos suma; hoy muestra
-- `contrato_nuevo`. Los `desglose_*` quedan fuera por `medida = 'stock'`: son el
-- reparto interno de una operación de cartera, no dinero nuevo del día.
-- OJO al nombre `operaciones`: para `cooperativa` cuenta cierres externos, no
-- contratos de `public.contratos`.

begin;
set local lock_timeout = '10s';

create or replace function crm.facturacion_diaria_fn(p_mes date default null)
returns table (
  dia date,
  tipo text,
  moneda text,
  analista_id uuid,
  analista_nombre text,
  supervisor_id uuid,
  supervisor_nombre text,
  operaciones bigint,
  capital numeric
)
language sql
stable
security definer
set search_path to ''
as $function$
  with ambito as materialized (
    -- Verja de Gerencia. `private.rol_crm` devuelve NULL para quien no es miembro
    -- del CRM: NULL = 'gerencia' es NULL, y el coalesce lo cierra en false.
    select coalesce(
      (select auth.uid()) is not null
      and (
        private.rol_crm((select auth.uid())) = 'gerencia'
        or private.es_lector_global()
      ), false) as ok
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
    -- entero para tirarlo después. Es output-neutral (el predicado interno del
    -- núcleo es el mismo que aplicaríamos fuera) y ahorra el trabajo.
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
  -- Ver la nota de la cabecera: en un informe de dinero «no consta» no deja el
  -- importe sin dueño.
  left join public.perfiles ps
    on ps.id = coalesce(t.supervisor_id, eq.supervisor_id)
  group by ep.dia, ep.tipo, ep.moneda, ep.analista_id, pf.nombre_completo,
           coalesce(t.supervisor_id, eq.supervisor_id), ps.nombre_completo
  -- PEN y USD no comparten escala: la moneda ordena ANTES que el importe, para no
  -- rankear US$ 10 000 por debajo de S/ 50 000.
  order by ep.dia, ep.moneda, sum(ep.monto) desc;
$function$;

alter function crm.facturacion_diaria_fn(date) owner to postgres;
revoke all on function crm.facturacion_diaria_fn(date) from public;
grant execute on function crm.facturacion_diaria_fn(date) to authenticated;

comment on function crm.facturacion_diaria_fn(date) is
  'Facturación por día del mes comercial: día x tipo x moneda x analista x supervisor '
  'de entonces, con operaciones y capital. Solo lectura sobre private.capital_episodios '
  '(el mismo núcleo de Conversiones, Ranking y Metas). El supervisor se reconstruye '
  'rebobinando crm.usuario_eventos; validado 16/16 contra el sello de agosto de 2026. '
  'Anular NO descuenta capital (ATR-4). Verja de Gerencia: cualquier otro rol recibe vacío.';

-- ---------------------------------------------------------------------------
-- Postflight. Lo que no se comprueba aquí se descubre en producción.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_prosecdef boolean;
  v_owner text;
  v_publico integer;
  v_search text;
  v_eventos bigint;
begin
  select p.prosecdef, pg_catalog.pg_get_userbyid(p.proowner),
         (select pg_catalog.array_to_string(p.proconfig, ','))
    into v_prosecdef, v_owner, v_search
  from pg_catalog.pg_proc p
  where p.oid = 'crm.facturacion_diaria_fn(date)'::regprocedure;

  if not v_prosecdef then
    raise exception 'facturacion_diaria_fn no quedo SECURITY DEFINER';
  end if;
  -- El DEFINER tiene que ser el dueño de crm.usuario_eventos: esa tabla tiene RLS
  -- ON y CERO policies, y solo se lee por ser su dueño. Con otro dueño, el CTE
  -- `eventos` devolveria 0 filas SIN ERROR y todo el rebobinado se degradaria en
  -- silencio al supervisor de hoy.
  if v_owner is distinct from 'postgres' then
    raise exception 'facturacion_diaria_fn es de % y debe ser de postgres', v_owner;
  end if;
  -- El search_path vacio se guarda ENTRECOMILLADO en proconfig (trampa repetida
  -- tres veces en este proyecto): se comprueba con las comillas.
  if v_search is distinct from 'search_path=""' then
    raise exception 'facturacion_diaria_fn tiene proconfig %, se esperaba search_path=""', v_search;
  end if;

  -- Revocar a anon no basta: lo que hay que comprobar es que PUBLIC (grantee 0)
  -- no conserve EXECUTE.
  select count(*) into v_publico
  from pg_catalog.pg_proc p,
       lateral pg_catalog.aclexplode(p.proacl) acl
  where p.oid = 'crm.facturacion_diaria_fn(date)'::regprocedure
    and acl.grantee = 0;
  if v_publico > 0 then
    raise exception 'facturacion_diaria_fn conserva % privilegios de PUBLIC', v_publico;
  end if;

  -- Anti-degradacion: si hay historia de jerarquia, el dueño de la funcion tiene
  -- que verla. Si esto falla, el rebobinado esta muerto aunque la funcion corra.
  select count(*) into v_eventos
  from crm.usuario_eventos where accion = 'jerarquia_actualizada';
  raise notice 'facturacion_diaria_fn: % eventos de jerarquia visibles al DEFINER', v_eventos;

  raise notice 'facturacion_diaria_fn: postflight OK (definer, dueño postgres, search_path sellado, sin PUBLIC)';
end
$postflight$;

commit;
