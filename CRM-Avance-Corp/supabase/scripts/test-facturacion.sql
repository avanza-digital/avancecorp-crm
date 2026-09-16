-- Oráculo de ATRIBUCIÓN de crm.facturacion_diaria_fn.
--
-- Existe porque ni la matriz de RLS ni la paridad de totales pueden cazar una
-- atribución equivocada: el capital total del mes es idéntico se le acredite a
-- un supervisor o a otro. Y porque los 5 eventos de jerarquía que hay en
-- producción son PRIMERAS ASIGNACIONES, así que nadie ha ejercitado nunca el
-- rebobinado con un cambio de equipo de verdad (hallazgo R6 del auditor-rls,
-- confirmado por Codex el 10/09/2026).
--
-- Siembra un cambio de equipo real sobre datos del banco, comprueba la
-- atribución antes y después, y DESHACE TODO.
--
-- Desde el 16/09/2026 (migración 20260916205617) prueba también el ÁMBITO DEL
-- SUPERVISOR: ve las filas cuyo supervisor de entonces es él (o su subárbol) y
-- sus ventas propias, y NADA más (casos 10 a 12). Y la verja del caso 8 deja de
-- ser «ve o no ve» para el supervisor: es «ve exactamente lo suyo».
--
-- ⚠ AVISO DE CANDADO: baja y sube el trigger de la fecha de cierre, y
-- `ALTER TABLE ... DISABLE/ENABLE TRIGGER` toma un SHARE ROW EXCLUSIVE sobre
-- `public.contratos` que NO se libera al volver a habilitarlo: dura hasta el
-- rollback. Mientras corre, otra sesión que escriba contratos en el mismo banco
-- espera. Es de segundos, pero no lo lances a la vez que un ciclo largo ajeno.
-- (Refutación de Codex, 10/09.)
--
-- Uso:
--   psql "$BANCO" -v ON_ERROR_STOP=1 -f supabase/scripts/test-facturacion.sql
-- Termina siempre en rollback: no deja rastro ni en el banco compartido.

\set ON_ERROR_STOP on
begin;

do $oraculo$
declare
  v_analista  uuid;
  v_sup_viejo uuid;
  v_sup_nuevo uuid;
  v_gerencia  uuid;
  v_mes       date := date_trunc('month', (now() at time zone 'America/Lima'))::date;
  v_antes     date := v_mes + 4;   -- día 5: ANTES del cambio
  v_cambio    date := v_mes + 9;   -- día 10: el cambio
  v_despues   date := v_mes + 19;  -- día 20: DESPUÉS del cambio
  v_id        bigint;
  v_res       uuid;
  v_filas     bigint;
  v_c1        uuid;
  v_c2        uuid;
  v_malas     bigint;
  v_ops       bigint;
  v_cap       numeric;
  v_ops_real  bigint;
  v_cap_real  numeric;
  v_tocadas   integer;
begin
  -- ── Fixture ───────────────────────────────────────────────────────────────
  select e.perfil_id into v_gerencia
  from crm.equipo e where e.rol_crm = 'gerencia' and e.activo limit 1;
  if v_gerencia is null then
    raise exception 'ORACULO: el banco no tiene gerencia activa; no se puede probar';
  end if;

  select perfil_id into v_sup_viejo from crm.equipo where rol_crm = 'supervisor' order by perfil_id limit 1;
  select perfil_id into v_sup_nuevo from crm.equipo where rol_crm = 'supervisor' order by perfil_id desc limit 1;
  if v_sup_viejo is null or v_sup_viejo = v_sup_nuevo then
    raise exception 'ORACULO: hacen falta DOS supervisores distintos en el banco';
  end if;

  -- Un analista con al menos dos ventas nuevas este mes.
  select coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) into v_analista
  from public.contratos c
  where c.categoria = 'nuevo' and not c.es_demo
    and c.fecha_cierre_comercial >= v_mes
    and c.fecha_cierre_comercial < (v_mes + interval '1 month')
  group by 1 having count(*) >= 2 order by count(*) desc limit 1;
  if v_analista is null then
    raise exception 'ORACULO: ningun analista tiene 2+ ventas este mes en el banco';
  end if;

  -- Sus ventas se reparten a los dos lados del cambio. La fecha de cierre está
  -- protegida por un trigger (solo se corrige por su RPC auditada): se baja ese
  -- candado POR SU NOMBRE, nunca con DISABLE TRIGGER USER, y solo dentro de esta
  -- transacción que se deshace.
  alter table public.contratos disable trigger trg_definir_periodo_comercial_contrato;
  -- Se eligen DOS contratos por su id ANTES de tocar nada. Con el filtro por
  -- fecha que había antes, dos contratos ya fechados el día 5 hacían que el
  -- segundo update no encontrara ninguno y el montaje mintiera. (Codex, 10/09.)
  select c2.id into v_c1 from public.contratos c2
  where coalesce(private.analista_atribuido_cadena(c2.id), c2.analista_cierre_id) = v_analista
    and c2.categoria = 'nuevo' and not c2.es_demo
    and c2.fecha_cierre_comercial >= v_mes
    and c2.fecha_cierre_comercial < (v_mes + interval '1 month')
  order by c2.id limit 1;
  select c2.id into v_c2 from public.contratos c2
  where coalesce(private.analista_atribuido_cadena(c2.id), c2.analista_cierre_id) = v_analista
    and c2.categoria = 'nuevo' and not c2.es_demo
    and c2.fecha_cierre_comercial >= v_mes
    and c2.fecha_cierre_comercial < (v_mes + interval '1 month')
    and c2.id <> v_c1
  order by c2.id limit 1;
  if v_c1 is null or v_c2 is null then
    raise exception 'ORACULO: no hay dos contratos distintos del analista este mes';
  end if;

  update public.contratos set fecha_cierre_comercial = v_antes where id = v_c1;
  get diagnostics v_tocadas = row_count;
  if v_tocadas <> 1 then raise exception 'ORACULO: el primer update toco % filas', v_tocadas; end if;
  update public.contratos set fecha_cierre_comercial = v_despues where id = v_c2;
  get diagnostics v_tocadas = row_count;
  if v_tocadas <> 1 then raise exception 'ORACULO: el segundo update toco % filas', v_tocadas; end if;

  alter table public.contratos enable trigger trg_definir_periodo_comercial_contrato;

  -- Hoy pertenece al supervisor NUEVO, y consta el cambio a mitad de mes.
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
  values (v_analista, 'vendedor', v_sup_nuevo, true)
  on conflict (perfil_id) do update set supervisor_id = excluded.supervisor_id;

  delete from crm.usuario_eventos
  where objetivo_id = v_analista and accion = 'jerarquia_actualizada';
  insert into crm.usuario_eventos (actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)
  values (v_gerencia, v_analista, 'jerarquia_actualizada',
          jsonb_build_object('supervisor_anterior', v_sup_viejo, 'supervisor_nuevo', v_sup_nuevo),
          gen_random_uuid(),
          (v_cambio::timestamp at time zone 'America/Lima'))
  returning id into v_id;

  -- La sesión pasa a ser Gerencia (si no, el gate cierra y no hay nada que ver).
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_gerencia, 'role', 'authenticated')::text, true);

  -- ── CASO 1 — la venta ANTERIOR al cambio se queda con el supervisor VIEJO ──
  -- Se miran TODAS las filas del día, no la primera: un LIMIT 1 aceptaría una
  -- fila buena y dejaría pasar otra mal atribuida. Y se contrastan operaciones y
  -- capital contra los propios contratos, que es lo único que caza un join que
  -- DUPLIQUE importes sin cambiar el número de filas. (Codex, 10/09.)
  select count(*), count(*) filter (where f.supervisor_id is distinct from v_sup_viejo),
         coalesce(sum(f.operaciones), 0), coalesce(sum(f.capital), 0)
    into v_filas, v_malas, v_ops, v_cap
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_antes and f.tipo = 'contrato_nuevo';
  -- La expectativa se calcula sobre TODAS las ventas del analista ESE DÍA, no
  -- sobre el contrato que movió el fixture. Compararla contra un solo contrato
  -- fue un fallo real de este oráculo: en un banco donde ese día ya tenía otras
  -- 66 ventas, acusó una duplicación que no existía (rama banco-f7, 10/09).
  select count(*), coalesce(sum(c.capital), 0) into v_ops_real, v_cap_real
  from public.contratos c
  where coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = v_analista
    and c.categoria = 'nuevo' and not c.es_demo
    and c.fecha_cierre_comercial = v_antes;
  if v_filas = 0 or v_malas > 0 then
    raise exception 'ORACULO 1 FALLA: % filas del %, % mal atribuidas (se esperaba el VIEJO %)',
      v_filas, v_antes, v_malas, v_sup_viejo;
  end if;
  if v_ops is distinct from v_ops_real or v_cap is distinct from v_cap_real then
    raise exception 'ORACULO 1 FALLA: importes duplicados — la funcion dice %/% y los contratos %/%',
      v_ops, v_cap, v_ops_real, v_cap_real;
  end if;
  raise notice 'ORACULO 1 OK: la venta anterior al cambio se queda con el supervisor de entonces';

  -- ── CASO 2 — la venta POSTERIOR va con el supervisor NUEVO ────────────────
  select count(*), count(*) filter (where f.supervisor_id is distinct from v_sup_nuevo)
    into v_filas, v_malas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_despues and f.tipo = 'contrato_nuevo';
  if v_filas = 0 or v_malas > 0 then
    raise exception 'ORACULO 2 FALLA: % filas del %, % mal atribuidas (se esperaba el NUEVO %)',
      v_filas, v_despues, v_malas, v_sup_nuevo;
  end if;
  raise notice 'ORACULO 2 OK: la venta posterior al cambio va con el supervisor nuevo';

  -- ── CASO 3 — EL MUTANTE. Si se borra la historia, la venta vieja cae al
  --    equipo de HOY. Es exactamente el fallo que un test de totales no ve:
  --    el capital del mes no cambia, solo cambia de dueño.
  delete from crm.usuario_eventos where id = v_id;
  select f.supervisor_id into v_res
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_antes and f.tipo = 'contrato_nuevo' limit 1;
  if v_res is distinct from v_sup_nuevo then
    raise exception 'ORACULO 3 FALLA: sin historia deberia caer al equipo de hoy (%) y dio %',
      v_sup_nuevo, coalesce(v_res::text, 'NADIE');
  end if;
  raise notice 'ORACULO 3 OK: sin historia manda el equipo de hoy — y el caso 1 demuestra que CON historia no';

  -- ── CASO 4 — DOS CAMBIOS EL MISMO DÍA: manda el último del día ────────────
  --    OJO al montaje: el equipo de HOY pasa a ser el VIEJO a propósito. Si no,
  --    afirmar «gana el último del día» (= el nuevo) sería indistinguible de
  --    «no encontró tramo y se cayó al equipo de hoy», y el caso pasaría con el
  --    rebobinado roto. Ahora las dos hipótesis dan respuestas distintas.
  update crm.equipo set supervisor_id = v_sup_viejo where perfil_id = v_analista;
  insert into crm.usuario_eventos (actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)
  values (v_gerencia, v_analista, 'jerarquia_actualizada',
          jsonb_build_object('supervisor_anterior', null, 'supervisor_nuevo', v_sup_viejo),
          gen_random_uuid(), (v_antes::timestamp at time zone 'America/Lima') + interval '9 hours'),
         (v_gerencia, v_analista, 'jerarquia_actualizada',
          jsonb_build_object('supervisor_anterior', v_sup_viejo, 'supervisor_nuevo', v_sup_nuevo),
          gen_random_uuid(), (v_antes::timestamp at time zone 'America/Lima') + interval '17 hours');
  -- La moneda va FIJADA: forma parte del group by, así que dos monedas darían
  -- dos filas legítimas y el conteo acusaría una duplicación que no existe.
  select count(*), count(*) filter (where f.supervisor_id is distinct from v_sup_nuevo)
    into v_filas, v_malas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_antes and f.tipo = 'contrato_nuevo'
    and f.moneda = (select c.moneda from public.contratos c where c.id = v_c1);
  if v_filas <> 1 then
    raise exception 'ORACULO 4 FALLA: dos cambios el mismo dia dieron % filas para una moneda', v_filas;
  end if;
  if v_malas > 0 then
    raise exception 'ORACULO 4 FALLA: con dos cambios el mismo dia debia mandar el ULTIMO (%)', v_sup_nuevo;
  end if;
  raise notice 'ORACULO 4 OK: dos cambios el mismo dia no duplican fila y manda el ultimo (y NO el equipo de hoy)';

  -- ── CASO 6 — precondiciones: el oráculo no puede afirmar sobre la nada ────
  --    Si el fixture no hubiera colocado ventas a los dos lados del cambio, los
  --    casos 1 y 2 mirarían filas inexistentes. Fallarían (NULL is distinct from
  --    un uuid es cierto), pero conviene decirlo con su propio nombre.
  select count(*) into v_filas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia in (v_antes, v_despues) and f.tipo = 'contrato_nuevo';
  if v_filas <> 2 then
    raise exception 'ORACULO 6 FALLA: el fixture no dejo una venta a cada lado del cambio (% filas)', v_filas;
  end if;
  raise notice 'ORACULO 6 OK: el fixture si puso una venta a cada lado — los casos 1 y 2 miraban algo real';

  -- ── CASO 7 — EL TRAMO DE EN MEDIO. Es el que pidió Codex: una venta situada
  --    ENTRE dos cambios de días distintos, cuyo supervisor de entonces NO es el
  --    equipo de hoy. Sin él, una implementación que solo mirase «antes del
  --    primer evento» y cayera al equipo actual para todo lo demás pasaría.
  delete from crm.usuario_eventos where objetivo_id = v_analista and accion = 'jerarquia_actualizada';
  update crm.equipo set supervisor_id = v_sup_nuevo where perfil_id = v_analista;
  insert into crm.usuario_eventos (actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)
  values (v_gerencia, v_analista, 'jerarquia_actualizada',
          jsonb_build_object('supervisor_anterior', v_sup_nuevo, 'supervisor_nuevo', v_sup_viejo),
          gen_random_uuid(), ((v_mes + 2)::timestamp at time zone 'America/Lima')),
         (v_gerencia, v_analista, 'jerarquia_actualizada',
          jsonb_build_object('supervisor_anterior', v_sup_viejo, 'supervisor_nuevo', v_sup_nuevo),
          gen_random_uuid(), ((v_mes + 14)::timestamp at time zone 'America/Lima'));
  select count(*), count(*) filter (where f.supervisor_id is distinct from v_sup_viejo)
    into v_filas, v_malas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_antes and f.tipo = 'contrato_nuevo';
  if v_filas = 0 or v_malas > 0 then
    raise exception 'ORACULO 7 FALLA: la venta del % cae ENTRE dos cambios y debia ser del VIEJO %; % de % filas dicen otra cosa',
      v_antes, v_sup_viejo, v_malas, v_filas;
  end if;
  -- Y la del día 20, después del segundo cambio, vuelve al nuevo.
  select count(*) filter (where f.supervisor_id is distinct from v_sup_nuevo) into v_malas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_despues and f.tipo = 'contrato_nuevo';
  if v_malas > 0 then
    raise exception 'ORACULO 7 FALLA: tras el segundo cambio la venta del % debia ser del NUEVO %', v_despues, v_sup_nuevo;
  end if;
  raise notice 'ORACULO 7 OK: el tramo de EN MEDIO se atribuye al supervisor de entonces, que no es el de hoy';

  -- ── CASO 10 — EL ÁMBITO DEL SUPERVISOR SIGUE LA REGLA DE «ENTONCES» ───────
  --    Con la historia del caso 7 (día 5 bajo el VIEJO, día 20 bajo el NUEVO, y
  --    el analista HOY en el equipo del nuevo): el supervisor VIEJO ve la venta
  --    del día 5 y NO la del 20; el NUEVO ve la del 20 y NO la del 5. Si el
  --    recorte fuera por organigrama de hoy, el viejo no vería nada y el nuevo
  --    lo vería todo: las dos hipótesis dan respuestas distintas.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_sup_viejo, 'role', 'authenticated')::text, true);
  select count(*) filter (where f.dia = v_antes), count(*) filter (where f.dia = v_despues)
    into v_ops, v_filas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.tipo = 'contrato_nuevo';
  if v_ops = 0 or v_filas > 0 then
    raise exception 'ORACULO 10 FALLA: el supervisor VIEJO ve % filas del dia % (debia >0) y % del % (debia 0)',
      v_ops, v_antes, v_filas, v_despues;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_sup_nuevo, 'role', 'authenticated')::text, true);
  select count(*) filter (where f.dia = v_antes), count(*) filter (where f.dia = v_despues)
    into v_ops, v_filas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.tipo = 'contrato_nuevo';
  if v_ops > 0 or v_filas = 0 then
    raise exception 'ORACULO 10 FALLA: el supervisor NUEVO ve % filas del dia % (debia 0) y % del % (debia >0)',
      v_ops, v_antes, v_filas, v_despues;
  end if;
  raise notice 'ORACULO 10 OK: cada supervisor ve las ventas hechas BAJO EL, no las del organigrama de hoy';

  -- ── CASO 11 — NI UNA FILA AJENA, y el nombre del otro no viaja ────────────
  --    Todo lo que recibe el supervisor nuevo lleva como supervisor a alguien de
  --    su subárbol (o lo vendió él). En particular, la venta del día 5 —que HOY
  --    es de un analista suyo— no le llega rotulada con el nombre del viejo.
  select count(*) into v_malas
  from crm.facturacion_diaria_fn(v_mes) f
  where not (
    f.supervisor_id in (
      with recursive sub as (
        select v_sup_nuevo as perfil_id
        union
        select e.perfil_id from crm.equipo e join sub s on e.supervisor_id = s.perfil_id
      ) select perfil_id from sub)
    or f.analista_id = v_sup_nuevo);
  if v_malas > 0 then
    raise exception 'ORACULO 11 FALLA: el supervisor nuevo recibio % filas ajenas', v_malas;
  end if;
  select count(*) into v_malas
  from crm.facturacion_diaria_fn(v_mes) f where f.supervisor_id = v_sup_viejo;
  if v_malas > 0 then
    raise exception 'ORACULO 11 FALLA: el supervisor nuevo ve % filas rotuladas con el VIEJO', v_malas;
  end if;
  raise notice 'ORACULO 11 OK: el supervisor no recibe filas ajenas ni el nombre del otro equipo';

  -- ── CASO 12 — EL MUTANTE del ámbito: si el recorte se cayera al organigrama
  --    de hoy, la venta del día 5 aparecería para el NUEVO. Se comprueba la
  --    dirección contraria también: mover al analista al equipo del VIEJO hoy
  --    no le regala al viejo la venta del día 20, que fue bajo el nuevo.
  update crm.equipo set supervisor_id = v_sup_viejo where perfil_id = v_analista;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_sup_viejo, 'role', 'authenticated')::text, true);
  select count(*) into v_malas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_despues and f.tipo = 'contrato_nuevo';
  if v_malas > 0 then
    raise exception 'ORACULO 12 FALLA: con el analista HOY en su equipo, el viejo ve % filas del dia %, hechas bajo el nuevo',
      v_malas, v_despues;
  end if;
  update crm.equipo set supervisor_id = v_sup_nuevo where perfil_id = v_analista;
  raise notice 'ORACULO 12 OK: el organigrama de hoy no cambia lo que cada supervisor ve';

  -- ── CASO 5 — el gate: sin sesión, ni una fila ─────────────────────────────
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_filas from crm.facturacion_diaria_fn(v_mes);
  if v_filas <> 0 then
    raise exception 'ORACULO 5 FALLA: sin sesion devolvio % filas', v_filas;
  end if;
  raise notice 'ORACULO 5 OK: sin sesion, cero filas';

  -- ── CASO 8 — LA VERJA, IDENTIDAD POR IDENTIDAD. Se cambia de identidad como
  --    lo hace PostgREST (claim `sub` del JWT) y se recorre TODO el equipo del
  --    banco. La intención se escribe como afirmación —la ven Gerencia y el
  --    Directorio enteras, cada supervisor exactamente lo suyo, nadie más— en
  --    vez de copiar la condición de la función, que sería tautológico.
  declare
    r          record;
    v_ident    bigint := 0;
    v_mal      bigint := 0;
    v_esperado bigint;
  begin
    -- La foto de Gerencia, para medir a cada supervisor contra ella.
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_gerencia, 'role', 'authenticated')::text, true);
    create temp table zz_verja_gerencia on commit drop as
      select * from crm.facturacion_diaria_fn(v_mes);

    for r in
      select e.perfil_id, e.rol_crm, (e.rol_crm in ('gerencia','directorio')) as deberia_ver
      from crm.equipo e where e.activo order by e.rol_crm, e.perfil_id
    loop
      perform set_config('request.jwt.claims',
        json_build_object('sub', r.perfil_id, 'role', 'authenticated')::text, true);
      select count(*) into v_filas from crm.facturacion_diaria_fn(v_mes);
      v_ident := v_ident + 1;
      if r.rol_crm = 'supervisor' then
        -- Desde el 16/09/2026 el supervisor VE, pero exactamente lo suyo: las
        -- filas de Gerencia cuyo supervisor de entonces cae en su subarbol, o
        -- que vendio el. Ni una mas, ni una menos.
        with recursive sub as (
          select r.perfil_id
          union
          select e.perfil_id from crm.equipo e join sub s on e.supervisor_id = s.perfil_id
        )
        select count(*) into v_esperado from zz_verja_gerencia g
        where g.supervisor_id in (select perfil_id from sub) or g.analista_id = r.perfil_id;
        if v_filas <> v_esperado then
          v_mal := v_mal + 1;
          raise warning 'VERJA MAL: el supervisor % vio % filas y le tocaban %', r.perfil_id, v_filas, v_esperado;
        end if;
      elsif (v_filas > 0) <> r.deberia_ver then
        v_mal := v_mal + 1;
        raise warning 'VERJA MAL: el rol % vio % filas (deberia_ver=%)', r.rol_crm, v_filas, r.deberia_ver;
      end if;
    end loop;
    drop table zz_verja_gerencia;

    -- Un uuid que no es nadie tampoco entra.
    perform set_config('request.jwt.claims',
      json_build_object('sub', '00000000-0000-4000-8000-000000000000', 'role', 'authenticated')::text, true);
    select count(*) into v_filas from crm.facturacion_diaria_fn(v_mes);
    v_ident := v_ident + 1;
    if v_filas <> 0 then
      v_mal := v_mal + 1; raise warning 'VERJA MAL: un desconocido vio % filas', v_filas;
    end if;

    if v_mal > 0 then raise exception 'ORACULO 8 FALLA: la verja se equivoca en % de % identidades', v_mal, v_ident; end if;
    raise notice 'ORACULO 8 OK: la verja acierta en las % identidades del banco', v_ident;
  end;

  -- ── CASO 9 — privilegios efectivos de los roles de PostgREST ──────────────
  if has_function_privilege('anon', 'crm.facturacion_diaria_fn(date)', 'execute') then
    raise exception 'ORACULO 9 FALLA: anon puede EJECUTAR la funcion';
  end if;
  if not has_function_privilege('authenticated', 'crm.facturacion_diaria_fn(date)', 'execute') then
    raise exception 'ORACULO 9 FALLA: authenticated NO puede ejecutar la funcion';
  end if;
  raise notice 'ORACULO 9 OK: anon no ejecuta, authenticated si';

  raise notice '── LOS 12 ORACULOS DE FACTURACION PASAN ──';
end
$oraculo$;

rollback;
