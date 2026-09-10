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
-- atribución antes y después, y DESHACE TODO. Uso:
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
  update public.contratos c set fecha_cierre_comercial = v_antes
  where c.id in (
    select c2.id from public.contratos c2
    where coalesce(private.analista_atribuido_cadena(c2.id), c2.analista_cierre_id) = v_analista
      and c2.categoria = 'nuevo' and not c2.es_demo
      and c2.fecha_cierre_comercial >= v_mes
      and c2.fecha_cierre_comercial < (v_mes + interval '1 month')
    order by c2.id limit 1);
  update public.contratos c set fecha_cierre_comercial = v_despues
  where c.id in (
    select c2.id from public.contratos c2
    where coalesce(private.analista_atribuido_cadena(c2.id), c2.analista_cierre_id) = v_analista
      and c2.categoria = 'nuevo' and not c2.es_demo
      and c2.fecha_cierre_comercial >= v_mes
      and c2.fecha_cierre_comercial < (v_mes + interval '1 month')
      and c2.fecha_cierre_comercial <> v_antes
    order by c2.id limit 1);

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
  select f.supervisor_id into v_res
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_antes and f.tipo = 'contrato_nuevo' limit 1;
  if v_res is distinct from v_sup_viejo then
    raise exception 'ORACULO 1 FALLA: la venta del % se acredito a % y debia ser al supervisor VIEJO %',
      v_antes, coalesce(v_res::text, 'NADIE'), v_sup_viejo;
  end if;
  raise notice 'ORACULO 1 OK: la venta anterior al cambio se queda con el supervisor de entonces';

  -- ── CASO 2 — la venta POSTERIOR va con el supervisor NUEVO ────────────────
  select f.supervisor_id into v_res
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_despues and f.tipo = 'contrato_nuevo' limit 1;
  if v_res is distinct from v_sup_nuevo then
    raise exception 'ORACULO 2 FALLA: la venta del % se acredito a % y debia ser al supervisor NUEVO %',
      v_despues, coalesce(v_res::text, 'NADIE'), v_sup_nuevo;
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
  insert into crm.usuario_eventos (actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)
  values (v_gerencia, v_analista, 'jerarquia_actualizada',
          jsonb_build_object('supervisor_anterior', v_sup_viejo, 'supervisor_nuevo', v_sup_viejo),
          gen_random_uuid(), (v_antes::timestamp at time zone 'America/Lima') + interval '9 hours'),
         (v_gerencia, v_analista, 'jerarquia_actualizada',
          jsonb_build_object('supervisor_anterior', v_sup_viejo, 'supervisor_nuevo', v_sup_nuevo),
          gen_random_uuid(), (v_antes::timestamp at time zone 'America/Lima') + interval '17 hours');
  select count(*) into v_filas
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_antes and f.tipo = 'contrato_nuevo';
  if v_filas <> 1 then
    raise exception 'ORACULO 4 FALLA: dos cambios el mismo dia DUPLICARON la fila (% filas)', v_filas;
  end if;
  select f.supervisor_id into v_res
  from crm.facturacion_diaria_fn(v_mes) f
  where f.analista_id = v_analista and f.dia = v_antes and f.tipo = 'contrato_nuevo' limit 1;
  if v_res is distinct from v_sup_nuevo then
    raise exception 'ORACULO 4 FALLA: con dos cambios el mismo dia debia mandar el ULTIMO (%) y dio %',
      v_sup_nuevo, coalesce(v_res::text, 'NADIE');
  end if;
  raise notice 'ORACULO 4 OK: dos cambios el mismo dia no duplican fila y manda el ultimo';

  -- ── CASO 5 — el gate: sin sesión, ni una fila ─────────────────────────────
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_filas from crm.facturacion_diaria_fn(v_mes);
  if v_filas <> 0 then
    raise exception 'ORACULO 5 FALLA: sin sesion devolvio % filas', v_filas;
  end if;
  raise notice 'ORACULO 5 OK: sin sesion, cero filas';

  raise notice '── LOS 5 ORACULOS DE ATRIBUCION PASAN ──';
end
$oraculo$;

rollback;
