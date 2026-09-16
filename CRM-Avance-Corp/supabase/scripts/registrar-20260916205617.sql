-- Registra 20260916205617 (crm_facturacion_diaria_supervisor) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/generar-registrador-facturacion-supervisor.mjs
-- leyendo la migracion del archivo: no editar a mano; regenerar. Orden de la
-- casa: PRIMERO aplicar la migracion con `db query --linked --file`, DESPUES
-- este registrador (el pin 1 se niega a registrar lo que no paso).
do $reg_fsup$
declare v_n int; v_cuerpo text; v_huella text;
begin
  v_cuerpo := $mig_fsup$-- crm_facturacion_diaria_supervisor — Facturación también para el SUPERVISOR:
-- ve el avance de SU equipo (Miguel, 16/09/2026: «quiero que el módulo de
-- facturación lo tengan los supervisores, para ver el avance de sus equipos»).
--
-- QUÉ CAMBIA
-- `crm.facturacion_diaria_fn(date)` conserva firma, columnas, orden, cuenta del
-- dinero y atribución (sigue leyendo `private.capital_episodios`, el mismo
-- núcleo de Conversiones, Ranking y Metas, y sigue rebobinando
-- `crm.usuario_eventos` para poner al supervisor DE ENTONCES). Lo ÚNICO que
-- cambia es la VERJA: además de Gerencia y del lector global (Directorio),
-- entra el SUPERVISOR — y entra con ÁMBITO, no con la empresa entera.
--
-- QUÉ ES «SU EQUIPO» AQUÍ, Y POR QUÉ NO ES EL ORGANIGRAMA DE HOY
-- La función ya acredita cada venta al supervisor de entonces (decisión de
-- Miguel del 10/09/2026). El ámbito del supervisor sigue ESA MISMA regla, no
-- otra: una fila es suya si
--   · su `supervisor_id` (el de entonces) es él o alguien de su subárbol de
--     hoy (`private.vendedor_ids_visibles`, el mismo helper con el que la RLS
--     le enseña leads, cartera y equipo), o
--   · la vendió él mismo (`analista_id = auth.uid()`): el supervisor también
--     vende desde el 16/09/2026 («Lead propio del supervisor», PR #2).
-- Consecuencias buscadas:
--   · un analista que SE FUE de su equipo a mitad de mes: lo que vendió bajo él
--     sigue en su pantalla; lo que vende después, no.
--   · un analista que LLEGÓ a mitad de mes: solo lo vendido desde que llegó.
--     Lo anterior es del otro supervisor, y por eso el NOMBRE del otro
--     supervisor no viaja a esta sesión — se conserva el criterio M-1 del
--     auditor-rls (04/09): nadie fuera de Gerencia lee por esta vía a qué
--     equipo pertenecía alguien de otro equipo. SALVO cuando la llegada no
--     dejó constancia de jerarquía anterior (`supervisor_anterior` NULL): ahí
--     rige la imputación al equipo de hoy de 20260910230000 y el supervisor
--     de hoy ve también lo anterior — es lo mismo que ve Gerencia, con el id
--     de él, no del otro.
--   · en sus ventas PROPIAS, la fila trae como supervisor a SU jefe de
--     entonces (el que la RPC pone para todos). Es su propio jefe, no «otro
--     equipo»: se acepta y se deja escrito (auditor-rls, 16/09).
-- Filtrar por el organigrama de hoy (`analista_id = any(visibles)`), que es lo
-- que hace `crm.metricas_capital_mes_fn`, habría roto las dos cosas a la vez:
-- le enseñaría al supervisor filas rotuladas con OTRO equipo y le quitaría al
-- otro las ventas que la regla de Miguel le acredita. Aquí el núcleo se llama
-- con `p_global = true` para el supervisor (como para Gerencia) y el recorte
-- se hace DESPUÉS de reconstruir al supervisor de entonces, que es el único
-- momento en que ese dato existe. Es un mes de filas ya agrupadas: barato.
--
-- Vendedor, coordinador, ajenos al CRM y sin sesión: VACÍO, exactamente como
-- antes (verja de visibilidad, no cierre; mismo criterio M-1). `anon` sigue sin
-- EXECUTE.
--
-- El resto del cuerpo es IDÉNTICO al de `20260910230000` (rebobinado,
-- imputación al equipo de hoy cuando no consta jerarquía, ATR-4: anular no
-- descuenta capital). Huella de la versión viva antes de esta migración:
-- f64e92e224fc64f3f0470f31e23aa56c (leída de producción el 16/09/2026); el
-- preflight la exige: una función viva NO se reteclea sobre otra versión.
--
-- Oráculos: `supabase/scripts/test-facturacion.sql` (casos 10-12: el ámbito
-- del supervisor, identidad por identidad, contra un cambio de equipo real) y
-- el bloque de facturación de `supabase/scripts/test-rls.mjs`.

begin;
set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- Preflight: la función viva es la que esta migración cree que es.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_huella text;
begin
  select md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = 'crm.facturacion_diaria_fn(date)'::regprocedure;
  if v_huella is distinct from 'f64e92e224fc64f3f0470f31e23aa56c' then
    raise exception 'facturacion_diaria_fn viva tiene huella %, se esperaba f64e92e224fc64f3f0470f31e23aa56c: otra version esta en produccion, NO se reemplaza a ciegas', v_huella;
  end if;
end
$preflight$;

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
$function$;

alter function crm.facturacion_diaria_fn(date) owner to postgres;
revoke all on function crm.facturacion_diaria_fn(date) from public;
grant execute on function crm.facturacion_diaria_fn(date) to authenticated;

comment on function crm.facturacion_diaria_fn(date) is
  'Facturación por día del mes comercial: día x tipo x moneda x analista x supervisor '
  'de entonces, con operaciones y capital. Solo lectura sobre private.capital_episodios '
  '(el mismo núcleo de Conversiones, Ranking y Metas). El supervisor se reconstruye '
  'rebobinando crm.usuario_eventos; validado 16/16 contra el sello de agosto de 2026. '
  'Anular NO descuenta capital (ATR-4). Verja: Gerencia y lector global ven todo; el '
  'SUPERVISOR solo las filas cuyo supervisor de entonces es él o su subárbol, más sus '
  'ventas propias (16/09/2026); cualquier otro rol recibe vacío.';

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
  v_gerencia uuid;
  v_vendedor uuid;
  v_mes date := date_trunc('month', (now() at time zone 'America/Lima'))::date;
  v_total bigint;
  v_mias bigint;
  v_esperadas bigint;
  v_fuera bigint;
  v_sups integer := 0;
  r record;
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
  -- no conserve EXECUTE. `proacl` NULL significa PRIVILEGIOS POR DEFECTO (que
  -- para una funcion incluyen EXECUTE a PUBLIC): se resuelve con `acldefault`.
  select count(*) into v_publico
  from pg_catalog.pg_proc p,
       lateral pg_catalog.aclexplode(
         coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) acl
  where p.oid = 'crm.facturacion_diaria_fn(date)'::regprocedure
    and acl.grantee = 0;
  if v_publico > 0 then
    raise exception 'facturacion_diaria_fn conserva % privilegios de PUBLIC', v_publico;
  end if;

  select count(*) into v_eventos
  from crm.usuario_eventos where accion = 'jerarquia_actualizada';
  raise notice 'facturacion_diaria_fn: % eventos de jerarquia visibles al DEFINER', v_eventos;

  -- ── ENSAYO CON LOS DATOS REALES, identidad por identidad ───────────────────
  -- Se cambia de identidad como lo hace PostgREST (claim `sub`) dentro de esta
  -- misma transaccion y se afirma la VERJA sobre el mes en curso:
  --   · cada SUPERVISOR activo recibe EXACTAMENTE las filas que Gerencia ve
  --     bajo su predicado (supervisor de entonces en su subarbol, o venta
  --     propia): ni una de mas (fuga) ni una de menos (agujero);
  --   · un VENDEDOR activo sigue recibiendo VACIO;
  --   · sin sesion, VACIO.
  -- Las identidades se eligen por su rol EFECTIVO (`private.rol_crm`, que
  -- devuelve NULL si el perfil del Portal esta suspendido o la pareja
  -- Portal/CRM esta desalineada), no por la fila cruda de crm.equipo: con una
  -- identidad a medias la sonda mediria otra cosa y abortaria culpando a la
  -- migracion (falso NO-GO; leccion de 20260902050000 y del auditor-rls, 16/09).
  select e.perfil_id into v_gerencia
  from crm.equipo e
  where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
  order by e.perfil_id limit 1;
  if v_gerencia is null then
    raise exception 'postflight: no hay gerencia con rol efectivo; no se puede ensayar la verja';
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_gerencia, 'role', 'authenticated')::text, true);
  create temp table zz_fact_gerencia on commit drop as
    select * from crm.facturacion_diaria_fn(v_mes);
  select count(*) into v_total from zz_fact_gerencia;
  if v_total = 0 then
    raise warning 'facturacion_diaria_fn: el mes en curso no tiene episodios; el ensayo de ambito pasa EN VACIO y no demuestra nada';
  end if;

  for r in
    select e.perfil_id from crm.equipo e
    where e.rol_crm = 'supervisor' and e.activo and private.rol_crm(e.perfil_id) = 'supervisor'
    order by e.perfil_id
  loop
    v_sups := v_sups + 1;
    perform set_config('request.jwt.claims',
      json_build_object('sub', r.perfil_id, 'role', 'authenticated')::text, true);
    create temp table zz_fact_sup on commit drop as
      select * from crm.facturacion_diaria_fn(v_mes);
    -- El subarbol se reconstruye aqui con su propia recursion (no con el helper,
    -- que se niega a enumerar equipos ajenos): dos implementaciones, un oraculo.
    with recursive sub as (
      select r.perfil_id
      union
      select e.perfil_id from crm.equipo e join sub s on e.supervisor_id = s.perfil_id
    )
    select
      (select count(*) from zz_fact_gerencia g
        where g.supervisor_id in (select perfil_id from sub) or g.analista_id = r.perfil_id),
      (select count(*) from zz_fact_sup),
      (select count(*) from zz_fact_sup s
        where not (s.supervisor_id in (select perfil_id from sub) or s.analista_id = r.perfil_id))
      into v_esperadas, v_mias, v_fuera;
    if v_fuera > 0 then
      raise exception 'postflight: el supervisor % recibio % filas AJENAS (fuga)', r.perfil_id, v_fuera;
    end if;
    if v_mias <> v_esperadas then
      raise exception 'postflight: el supervisor % recibio % filas y Gerencia ve % suyas (agujero o duplicado)',
        r.perfil_id, v_mias, v_esperadas;
    end if;
    raise notice 'facturacion_diaria_fn: supervisor % ve % de % filas del mes, todas suyas', r.perfil_id, v_mias, v_total;
    drop table zz_fact_sup;
  end loop;
  if v_sups = 0 then
    raise notice 'facturacion_diaria_fn: sin supervisores activos, el ensayo de ambito no aplica';
  end if;

  select e.perfil_id into v_vendedor
  from crm.equipo e
  where e.rol_crm = 'vendedor' and e.activo and private.rol_crm(e.perfil_id) = 'vendedor'
  order by e.perfil_id limit 1;
  if v_vendedor is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_vendedor, 'role', 'authenticated')::text, true);
    select count(*) into v_mias from crm.facturacion_diaria_fn(v_mes);
    if v_mias <> 0 then
      raise exception 'postflight: un vendedor recibio % filas; debia recibir VACIO', v_mias;
    end if;
  end if;

  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_mias from crm.facturacion_diaria_fn(v_mes);
  if v_mias <> 0 then
    raise exception 'postflight: sin sesion devolvio % filas', v_mias;
  end if;
  drop table zz_fact_gerencia;

  raise notice 'facturacion_diaria_fn: postflight OK (definer, dueño postgres, search_path sellado, sin PUBLIC; % supervisores ensayados sobre % filas de gerencia; vendedor y sin sesion en vacio)', v_sups, v_total;
end
$postflight$;

commit;
$mig_fsup$;

  -- 1) PIN: lo que la migracion hizo ES verdad — la funcion existe y su cuerpo
  --    YA NO es el de 20260910230000 (huella f64e92e2...). Si no, no se
  --    registra lo que no paso.
  if to_regprocedure('crm.facturacion_diaria_fn(date)') is null then
    raise exception 'registrar facturacion supervisor: crm.facturacion_diaria_fn(date) NO existe — aplicar la migracion antes de registrar';
  end if;
  select md5(p.prosrc) into v_huella from pg_proc p where p.oid = 'crm.facturacion_diaria_fn(date)'::regprocedure;
  if v_huella = 'f64e92e224fc64f3f0470f31e23aa56c' then
    raise exception 'registrar facturacion supervisor: la funcion viva sigue siendo la de 20260910230000 — aplicar la migracion antes de registrar';
  end if;

  -- 2) La version no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260916205617' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar facturacion supervisor: la version 20260916205617 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260916205617', 'crm_facturacion_diaria_supervisor', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260916205617' and name = 'crm_facturacion_diaria_supervisor'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar facturacion supervisor: la relectura no encontro la fila exacta';
  end if;
end $reg_fsup$;
