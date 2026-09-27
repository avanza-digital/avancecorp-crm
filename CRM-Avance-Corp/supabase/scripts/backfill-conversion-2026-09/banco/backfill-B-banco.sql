-- GENERADO por banco/generar-B-banco.py desde backfill-B-setiembre-2026.sql. NO EDITAR A MANO.
-- Backfill único · tipo B · setiembre 2026
-- 11 contratos «nuevo» que en realidad son inversión adicional de un cliente existente.
-- Se registra su operación de cartera 'upgrade' con el MISMO molde que public.crear_contrato
-- y el precedente Morales (op 36b643a1-5f99-4d80-87a9-cb4c8cf8cb11). No toca contratos,
-- no crea objetos de esquema, no apaga triggers, no usa válvulas de sesión.
-- ⛔ NO EJECUTAR sin OK explícito de Miguel sobre ESTE texto.
-- Reversa: la tabla es append-only (trg_operaciones_cartera_00_append_only); no hay DELETE
-- legítimo. Un error se corrige con otra decisión de Gerencia, no borrando.
-- Revisión Codex 23/09 aplicada: filas bloqueadas antes de validar, condiciones repetidas en el
-- INSERT, comprobación contrato a contrato y la única no elegible identificada (001408).
-- Revisión Codex nº 2: el predicado COMPLETO del candidato se repite en el INSERT y en la comprobación final.

do $b$
declare
  v_admin constant uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'; -- ADMINISTRADOR AVANCE CORP
  v_ids constant uuid[] := array[
    'e0000000-0000-4000-8000-00000000000d', -- BANCO-B1-SEP (cliente con contrato de julio → elegible)
    'e0000000-0000-4000-8000-00000000000f'  -- BANCO-B2-2 (mismo mes que su 1.er contrato → no elegible)
  ]::uuid[];
  v_no_elegible constant uuid := 'e0000000-0000-4000-8000-00000000000f'; -- BANCO-B2-2
  v_c record;
  v_n int;
begin
  perform pg_catalog.set_config('lock_timeout', '5s', true);

  -- 0. Setiembre abierto, bajo el mismo candado que el sello mensual.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
    (date '2026-09-01' - date '2000-01-01')::integer);
  if exists (select 1 from crm.periodos_cerrados where periodo = date '2026-09-01') then
    raise exception 'Setiembre 2026 está sellado: el backfill se detiene';
  end if;

  -- 1. Las filas de los 11 contratos quedan bloqueadas ANTES de validarlas: nadie puede
  --    cambiarlas hasta el final de esta transacción.
  perform 1 from public.contratos c where c.id = any(v_ids) order by c.id for share;

  -- 2. Cada contrato sigue siendo exactamente el candidato revisado.
  select count(*) into v_n
  from public.contratos c
  where c.id = any(v_ids)
    and c.categoria = 'nuevo' and c.estado = 'activo' and not c.es_demo
    and c.fecha_cierre_comercial between date '2026-09-01' and date '2026-09-30'
    and c.analista_cierre_id is not null
    and not private.contrato_en_eliminacion(c.id)
    -- Sin lead propio. Los leads del backfill tipo A NO cuentan: el cliente de 001408 tiene su
    -- 1.er contrato (001397) en el tipo A, y tras correr A ya tiene ese lead (ensayado en el
    -- banco el 23/09: sin esta excepción, B se detenía con «hay 10»).
    and not exists (select 1 from crm.leads l
                    where (l.perfil_id = c.cliente_id or l.contrato_id = c.id)
                      and not coalesce(l.alta_manual and l.creado_por = v_admin
                               and l.nota like 'Backfill 2026-09 · contrato %', false))
    and exists (select 1 from public.contratos c2
                where c2.cliente_id = c.cliente_id and c2.id <> c.id and not c2.es_demo
                  and (c2.fecha_cierre_comercial < c.fecha_cierre_comercial
                       or (c2.fecha_cierre_comercial = c.fecha_cierre_comercial and c2.creado_en < c.creado_en)));
  if v_n <> 2 then
    raise exception 'Se esperaban 2 contratos candidatos tipo B y hay %: revisar antes de seguir', v_n;
  end if;

  -- 3. Mismo candado por cliente|período que public.crear_contrato.
  for v_c in select distinct c.cliente_id from public.contratos c where c.id = any(v_ids) order by 1 loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.operaciones_cartera'),
      pg_catalog.hashtext(v_c.cliente_id::text || '|' || date '2026-09-01'::text));
  end loop;

  -- 4. Inserción idempotente (contrato_nuevo_id es UNIQUE). Elegibilidad = regla de
  --    public.crear_contrato: el período del upgrade debe ser POSTERIOR al del primer contrato.
  --    Se repite el predicado COMPLETO del candidato: solo entra lo que sigue cumpliéndolo.
  insert into crm.operaciones_cartera (
    cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
    fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
    elegible_conversion, desglose_completo, fuente, creado_por)
  select c.cliente_id, c.analista_cierre_id, 'upgrade', null, c.id,
    c.fecha_cierre_comercial, date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, null, null,
    date_trunc('month', c.fecha_cierre_comercial)::date >
      (select min(date_trunc('month', c2.fecha_cierre_comercial)::date)
         from public.contratos c2 where c2.cliente_id = c.cliente_id),
    true, 'flujo_cartera', v_admin
  from public.contratos c
  where c.id = any(v_ids)
    and c.categoria = 'nuevo' and c.estado = 'activo' and not c.es_demo
    and c.fecha_cierre_comercial between date '2026-09-01' and date '2026-09-30'
    and c.analista_cierre_id is not null
    and not private.contrato_en_eliminacion(c.id)
    and not exists (select 1 from crm.leads l
                    where (l.perfil_id = c.cliente_id or l.contrato_id = c.id)
                      and not coalesce(l.alta_manual and l.creado_por = v_admin
                               and l.nota like 'Backfill 2026-09 · contrato %', false))
    and exists (select 1 from public.contratos c2
                where c2.cliente_id = c.cliente_id and c2.id <> c.id and not c2.es_demo
                  and (c2.fecha_cierre_comercial < c.fecha_cierre_comercial
                       or (c2.fecha_cierre_comercial = c.fecha_cierre_comercial and c2.creado_en < c.creado_en)))
    and not exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = c.id);

  -- 5. Comprobación CONTRATO A CONTRATO dentro de la misma transacción (si no cuadra, no queda
  --    nada): cada uno sigue siendo candidato y tiene exactamente una operación, la esperada
  --    —también si ya existía.
  select count(*) into v_n
  from public.contratos c
  where c.id = any(v_ids)
    and c.categoria = 'nuevo' and c.estado = 'activo' and not c.es_demo
    and c.fecha_cierre_comercial between date '2026-09-01' and date '2026-09-30'
    and c.analista_cierre_id is not null
    and not private.contrato_en_eliminacion(c.id)
    and not exists (select 1 from crm.leads l
                    where (l.perfil_id = c.cliente_id or l.contrato_id = c.id)
                      and not coalesce(l.alta_manual and l.creado_por = v_admin
                               and l.nota like 'Backfill 2026-09 · contrato %', false))
    and exists (select 1 from public.contratos c2
                where c2.cliente_id = c.cliente_id and c2.id <> c.id and not c2.es_demo
                  and (c2.fecha_cierre_comercial < c.fecha_cierre_comercial
                       or (c2.fecha_cierre_comercial = c.fecha_cierre_comercial and c2.creado_en < c.creado_en)))
    and (select count(*) from crm.operaciones_cartera o where o.contrato_nuevo_id = c.id) = 1
    and exists (select 1 from crm.operaciones_cartera o
                where o.contrato_nuevo_id = c.id and o.tipo = 'upgrade'
                  and o.cliente_id = c.cliente_id and o.vendedor_id = c.analista_cierre_id
                  and o.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
                  and o.fecha_operacion = c.fecha_cierre_comercial and o.moneda = c.moneda
                  and o.elegible_conversion = (date_trunc('month', c.fecha_cierre_comercial)::date >
                        (select min(date_trunc('month', c2.fecha_cierre_comercial)::date)
                           from public.contratos c2 where c2.cliente_id = c.cliente_id)));
  if v_n <> 2 then
    raise exception 'Solo % de 2 contratos tienen su operación con la forma esperada', v_n;
  end if;

  -- 6. Exactamente una no elegible, y es la de 001408.
  if (select count(*) from crm.operaciones_cartera o
       where o.contrato_nuevo_id = any(v_ids) and not o.elegible_conversion) <> 1
     or not exists (select 1 from crm.operaciones_cartera o
                     where o.contrato_nuevo_id = v_no_elegible and not o.elegible_conversion) then
    raise exception 'La única operación no elegible tenía que ser la de BANCO-B2-2';
  end if;

  raise notice 'Backfill B OK: 2 operaciones upgrade, 1 elegible';
end;
$b$;
