-- REGISTRO en supabase_migrations.schema_migrations de 20260927024423_crm_pago_declara_cuenta (F5).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar. Se niega si las piezas vivas no son
-- las ensayadas (huella de las 4 funciones: cuerpo y comentario) o si la regla de origen no es la nueva.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_pago_declara_cuenta'));
do $chk$
declare v_huella text;
begin
  select pg_catalog.md5(pg_catalog.string_agg(p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc)
           || '|' || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-'), E'\n'
           order by p.oid::regprocedure::text))
    into v_huella
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('private.sellar_cuenta_cuota_pagada()'),
                  to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)'),
                  to_regprocedure('private.contratos_cuenta_pago_cliente_autorizado(uuid)'),
                  to_regprocedure('crm.contratos_cuenta_pago_cliente_fn(uuid)'));
  if v_huella is distinct from '5fe996aff266f293464c24e59764269b'
     or (select pg_catalog.pg_get_constraintdef(oid) from pg_catalog.pg_constraint
         where conrelid = 'crm.cuotas_cuenta_pagada'::regclass and conname = 'cuotas_cuenta_pagada_origen_valido') not like '%declarado%' then
    raise exception 'REGISTRO: las piezas vivas no son las ensayadas (huella %); aplica primero 20260927024423', v_huella;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260927024423' and coalesce(name, '') <> 'crm_pago_declara_cuenta') then
    raise exception 'REGISTRO: la versión 20260927024423 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260927024423', 'crm_pago_declara_cuenta', array[$registro$-- Cuentas de Gloria · F5: el registro de pagos declara a qué cuenta se depositó (26/09/2026).
--
-- Qué hace:
--   1. El sello por cuota (private.sellar_cuenta_cuota_pagada) admite una cuenta DECLARADA: si la
--      transacción trae el ajuste crm.cci_deposito, la cuota se sella en la cuenta del cliente con
--      ese CCI (cualquier versión: cliente+moneda+CCI) —solo si la declaración la armó la RPC en esa
--      misma transacción (testigo)—, siempre que sea o haya sido cuenta de pago
--      de ESE contrato (enlace actual o historial de F3); otro CCI se rechaza (22023). origen =
--      'declarado'. Sin ajuste, deduce por la fecha como hasta hoy ('registro'). Corregir la fecha
--      solo re-sella lo deducido.
--   2. crm.registrar_pago_con_cuenta (INVOKER): marca una cuota pendiente como pagada declarando el
--      CCI del depósito. Misma RLS que el UPDATE directo. La usan la importación del Excel y el modal
--      de pago manual del portal.
--   3. crm.contratos_cuenta_pago_cliente_fn: «pagadas_por_cuenta» suma 'declaradas'.
--
-- Decisiones de Miguel (26/09): solo cuentas de pago del contrato (actual o histórica); el pago
-- manual muestra la cuenta y la declara al confirmar. Cierra el caso del «mismo día» aceptado en F3.
--
-- Toca public solo por lectura y por el UPDATE de la RPC, que corre con la RLS de quien registra
-- (no crea ni cambia triggers, policies ni tablas de public). Reversión:
-- ../scripts/cuentas-gloria/reversa-pago-declara-cuenta.sql (repone el sello y la lectura byte a
-- byte; se niega si ya hay sellos 'declarado', porque su constancia se perdería).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc where oid = to_regprocedure('private.sellar_cuenta_cuota_pagada()'))
       is distinct from 'bdc9ca16b94dbd2ec24e702e8d12651f'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = to_regprocedure('private.contratos_cuenta_pago_cliente_autorizado(uuid)'))
       is distinct from 'd4d79c78d117d1458bd5aafa40cff89e'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = to_regprocedure('crm.contratos_cuenta_pago_cliente_fn(uuid)'))
       is distinct from '4720e000300e7eda76f9a1f45ecd2c34' then
    raise exception 'F5: las piezas vivas (F3 + arreglos 20260927020317) no son las esperadas; no se toca';
  end if;
  if (select pg_catalog.pg_get_constraintdef(oid) from pg_catalog.pg_constraint
      where conrelid = 'crm.cuotas_cuenta_pagada'::regclass and conname = 'cuotas_cuenta_pagada_origen_valido')
     is distinct from 'CHECK ((origen = ANY (ARRAY[''registro''::text, ''inferido''::text])))' then
    raise exception 'F5: la regla de origen del sello no es la esperada; no se toca';
  end if;
  if to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)') is not null then
    raise exception 'F5: crm.registrar_pago_con_cuenta ya existe; no se sobrescribe';
  end if;
  if to_regclass('crm.contrato_cuenta_pago_cambios') is null or to_regclass('crm.contrato_cuentas_pago') is null then
    raise exception 'F5: faltan dependencias de F3';
  end if;
  -- El sello (DEFINER) lee public.contratos como su dueño: quien aplica debe ver todas las filas.
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'F5: el dueño de las funciones debe tener bypassrls';
  end if;
end;
$precondicion$;

-- ── 1. Origen 'declarado' y sello con cuenta declarada ─────────────────────────────────────
alter table crm.cuotas_cuenta_pagada drop constraint cuotas_cuenta_pagada_origen_valido;
alter table crm.cuotas_cuenta_pagada add constraint cuotas_cuenta_pagada_origen_valido
  check (origen in ('registro', 'declarado', 'inferido'));
comment on column crm.cuotas_cuenta_pagada.origen is 'declarado = quien registró dijo a qué cuenta depositó (CCI del Excel o cuenta del modal); registro = deducida de la fecha del pago al registrarlo; inferido = backfill desde la cuenta contractual.';

create or replace function private.sellar_cuenta_cuota_pagada()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_cuenta uuid;
  v_cci text := nullif(pg_catalog.current_setting('crm.cci_deposito', true), '');
  v_testigo text := nullif(pg_catalog.current_setting('crm.cci_deposito_testigo', true), '');
  v_nuevo_pago boolean := tg_op = 'INSERT';
  v_origen_previo text;
begin
  -- Procedencia: la declaración solo vale si la armó crm.registrar_pago_con_cuenta en ESTA
  -- transacción (testigo = md5 del txid + CCI). Un CCI fijado a mano sin la RPC se ignora.
  if v_cci is not null and v_testigo is distinct from pg_catalog.md5(pg_catalog.txid_current()::text || '|' || v_cci) then
    raise exception using errcode = '22023',
      message = 'La cuenta del depósito solo se declara por crm.registrar_pago_con_cuenta';
  end if;
  if not v_nuevo_pago then
    v_nuevo_pago := old.estado is distinct from 'pagado';
  end if;
  -- Corrección de la fecha de una cuota ya pagada: solo se recalcula un sello deducido por la
  -- fecha ('registro'); lo declarado y lo inferido no dependen de ella.
  if not v_nuevo_pago then
    select q.origen into v_origen_previo from crm.cuotas_cuenta_pagada q where q.cuota_id = new.id;
    -- Sin sello previo (cuota pagada antes de tener cuenta de pago): se sella como 'inferido'.
    if v_origen_previo is not null and v_origen_previo <> 'registro' then
      return null;
    end if;
  end if;

  if v_nuevo_pago and v_cci is not null then
    -- Quien registra DECLARÓ a qué cuenta depositó (el CCI del Excel o la cuenta que mostró el
    -- modal): esa es la constancia. Solo vale una cuenta que sea o haya sido cuenta de pago de
    -- ESTE contrato (enlace actual o historial de cambios), en cualquiera de sus versiones
    -- (mismo cliente, moneda y CCI). Otro CCI del cliente se rechaza: un depósito fuera de la
    -- instrucción de pago es una anomalía, no una constancia.
    select cb.id into v_cuenta
    from crm.cuentas_bancarias cb
    join public.contratos ct on ct.id = new.contrato_id
    where cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda
      and pg_catalog.regexp_replace(cb.cci, '\D', '', 'g') = v_cci
      and exists (
        select 1 from crm.cuentas_bancarias ref
        where ref.id in (
          select l.cuenta_bancaria_id from crm.contrato_cuentas_pago l where l.contrato_id = new.contrato_id
          union
          select c.cuenta_anterior_id from crm.contrato_cuenta_pago_cambios c where c.contrato_id = new.contrato_id
          union
          select c.cuenta_nueva_id from crm.contrato_cuenta_pago_cambios c where c.contrato_id = new.contrato_id)
          and ref.cliente_id = cb.cliente_id and ref.moneda = cb.moneda and ref.cci = cb.cci)
    order by cb.activa desc, cb.creado_en desc
    limit 1;
    if v_cuenta is null then
      raise exception using errcode = '22023',
        message = 'El CCI del depósito no es de una cuenta de pago de este contrato';
    end if;
  else
    -- Sin declaración: la cuenta vigente en la FECHA del pago (si después de esa fecha, día de
    -- Lima, hubo un cambio, la cuenta anterior del primero; si no, la contractual actual).
    if new.fecha_pago_real is not null then
      select c.cuenta_anterior_id into v_cuenta
      from crm.contrato_cuenta_pago_cambios c
      where c.contrato_id = new.contrato_id
        and (c.cambiado_en at time zone 'America/Lima')::date > new.fecha_pago_real
      order by c.cambiado_en asc, c.id asc
      limit 1;
    end if;
    if v_cuenta is null then
      select l.cuenta_bancaria_id into v_cuenta
      from crm.contrato_cuentas_pago l
      where l.contrato_id = new.contrato_id;
    end if;
    -- Sin cuenta: el trigger BEFORE de exigencia ya rechazó el pago; nada que sellar.
    if v_cuenta is null then
      return null;
    end if;
  end if;

  insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
  values (new.id, new.contrato_id, v_cuenta,
          case when not v_nuevo_pago then 'inferido' when v_cci is not null then 'declarado' else 'registro' end)
  on conflict (cuota_id) do update
    set contrato_id = excluded.contrato_id,
        cuenta_bancaria_id = excluded.cuenta_bancaria_id,
        origen = case when v_nuevo_pago then excluded.origen else crm.cuotas_cuenta_pagada.origen end,
        sellada_en = pg_catalog.now();
  return null;
end;
$function$;

-- ── 2. Registrar un pago declarando la cuenta del depósito ─────────────────────────────────
-- INVOKER: el UPDATE corre con la RLS de quien registra (cronograma_admin_actualiza =
-- es_gestor_cartera), exactamente la misma puerta que el UPDATE directo que hace hoy el portal.
-- El CCI viaja al sello solo dentro de esta transacción y se limpia al terminar (también si el
-- UPDATE falla: el ajuste es local a la transacción y se descarta con ella).
create function crm.registrar_pago_con_cuenta(
  p_cuota_id uuid, p_fecha date, p_monto numeric, p_cci text)
returns uuid
language plpgsql
volatile security invoker
set search_path to ''
as $function$
declare
  v_id uuid;
  v_cci text := nullif(pg_catalog.regexp_replace(coalesce(p_cci, ''), '\D', '', 'g'), '');
begin
  if p_cuota_id is null or p_fecha is null then
    raise exception using errcode = '22023', message = 'Faltan la cuota o la fecha del pago';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception using errcode = '22023', message = 'El monto pagado debe ser mayor que cero';
  end if;
  if pg_catalog.btrim(coalesce(p_cci, '')) <> '' and (v_cci is null or pg_catalog.length(v_cci) <> 20) then
    raise exception using errcode = '22023', message = 'El CCI del depósito no tiene 20 dígitos';
  end if;
  perform pg_catalog.set_config('crm.cci_deposito', coalesce(v_cci, ''), true);
  perform pg_catalog.set_config('crm.cci_deposito_testigo',
    case when v_cci is null then '' else pg_catalog.md5(pg_catalog.txid_current()::text || '|' || v_cci) end, true);
  update public.cronograma_pagos
     set estado = 'pagado', fecha_pago_real = p_fecha, monto_pagado = p_monto,
         registrado_por = (select auth.uid())
   where id = p_cuota_id and estado = 'pendiente'
  returning id into v_id;
  perform pg_catalog.set_config('crm.cci_deposito', '', true);
  perform pg_catalog.set_config('crm.cci_deposito_testigo', '', true);
  return v_id;
end;
$function$;
revoke all on function crm.registrar_pago_con_cuenta(uuid, date, numeric, text) from public, anon, authenticated, service_role;
grant execute on function crm.registrar_pago_con_cuenta(uuid, date, numeric, text) to authenticated;

-- ── 3. Lectura: pagadas por cuenta distingue las declaradas ────────────────────────────────
drop function crm.contratos_cuenta_pago_cliente_fn(uuid);
drop function private.contratos_cuenta_pago_cliente_autorizado(uuid);
CREATE OR REPLACE FUNCTION private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id uuid)
 RETURNS TABLE(contrato_id uuid, numero_contrato text, moneda text, estado text, cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text, cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb, cuenta_retirada boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not coalesce(private.admin_banca_vigente((select auth.uid())), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede ver las cuentas de pago';
  end if;
  return query
  select ct.id, ct.numero_contrato, ct.moneda, ct.estado,
         l.cuenta_bancaria_id, cb.banco, cb.tipo_cuenta, cb.numero_cuenta, cb.cci,
         (select count(*) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         (select min(cp.fecha_programada) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'cuenta_bancaria_id', s.cuenta_bancaria_id, 'banco', sb.banco,
                    'numero_cuenta', sb.numero_cuenta, 'cuotas', s.n, 'inferidas', s.inferidas, 'declaradas', s.declaradas)
                  order by s.n desc)
           from (select q.cuenta_bancaria_id, count(*) as n,
                        count(*) filter (where q.origen = 'inferido') as inferidas,
                        count(*) filter (where q.origen = 'declarado') as declaradas
                 from crm.cuotas_cuenta_pagada q
                 join public.cronograma_pagos cp on cp.id = q.cuota_id and cp.estado = 'pagado'
                 where q.contrato_id = ct.id
                 group by q.cuenta_bancaria_id) s
           join crm.cuentas_bancarias sb on sb.id = s.cuenta_bancaria_id), '[]'::jsonb),
         -- La cuenta de pago ya no existe como cuenta vigente: ninguna versión con ese CCI está activa
         -- (p. ej., un contrato que volvió a abrirse al borrar su renovación después de retirar la
         -- cuenta). Una cuenta corregida (versión vieja + versión vigente con el mismo CCI) no cuenta.
         (cb.id is not null and not exists (
            select 1 from crm.cuentas_bancarias v
            where v.cliente_id = cb.cliente_id and v.moneda = cb.moneda
              and v.cci = cb.cci and v.activa is true))
  from public.contratos ct
  left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  where ct.cliente_id = p_cliente_id
    and ct.estado in ('activo', 'vencido')
  order by ct.moneda, ct.numero_contrato;
end;
$function$;
revoke all on function private.contratos_cuenta_pago_cliente_autorizado(uuid) from public, anon, authenticated, service_role;
grant execute on function private.contratos_cuenta_pago_cliente_autorizado(uuid) to authenticated;

CREATE OR REPLACE FUNCTION crm.contratos_cuenta_pago_cliente_fn(p_cliente_id uuid)
 RETURNS TABLE(contrato_id uuid, numero_contrato text, moneda text, estado text, cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text, cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb, cuenta_retirada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select * from private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.contratos_cuenta_pago_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.contratos_cuenta_pago_cliente_fn(uuid) to authenticated;

comment on function private.sellar_cuenta_cuota_pagada() is 'Trigger AFTER en public.cronograma_pagos: al pasar una cuota a pagado sella la cuenta DECLARADA (ajuste crm.cci_deposito armado por crm.registrar_pago_con_cuenta en la misma transacción, con testigo: cuenta de pago del contrato, actual o histórica, con ese CCI) o, sin declaración, la vigente en la fecha del pago; corregir la fecha re-sella solo lo deducido. No cambia el registro del pago. SECURITY DEFINER porque quien registra el pago (gestor de cartera) no tiene grants sobre los registros crm.';
comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes, cuotas pagadas por cuenta (con las inferidas y las declaradas aparte) y cuenta_retirada (la cuenta física de pago ya no tiene versión vigente: hay que cambiarla). Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre enlace ni sellos. DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago y la marca cuenta_retirada. Solo admin.';
comment on function crm.registrar_pago_con_cuenta(uuid, date, numeric, text) is 'Marca una cuota PENDIENTE como pagada declarando el CCI de la cuenta a la que se depositó (20 dígitos; vacío = se deduce por la fecha); rechaza monto nulo o <= 0. INVOKER: el UPDATE corre con la RLS de quien registra (gestor de cartera). La usan la importación del Excel y el modal de pago manual. Devuelve la cuota o NULL si no estaba pendiente.';

-- ── 4. Postflight ──────────────────────────────────────────────────────────────────────────
do $postflight$
declare v_f record;
begin
  for v_f in
    select * from (values
      ('private.sellar_cuenta_cuota_pagada()', null, true, 'v'),
      ('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', 'authenticated', false, 'v'),
      ('private.contratos_cuenta_pago_cliente_autorizado(uuid)', 'authenticated', true, 's'),
      ('crm.contratos_cuenta_pago_cliente_fn(uuid)', 'authenticated', false, 's')
    ) as f(firma, rol, definer, volatilidad)
  loop
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.prosecdef = v_f.definer and p.provolatile = v_f.volatilidad) then
      raise exception 'F5: DEFINER/INVOKER o volatilidad inesperados en %', v_f.firma;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE'))
      or not exists (select 1 from pg_catalog.pg_proc p
                     where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'F5: EXECUTE o search_path inesperados en %', v_f.firma;
    end if;
  end loop;
  if (select pg_catalog.pg_get_constraintdef(oid) from pg_catalog.pg_constraint
      where conrelid = 'crm.cuotas_cuenta_pagada'::regclass and conname = 'cuotas_cuenta_pagada_origen_valido')
     is distinct from 'CHECK ((origen = ANY (ARRAY[''registro''::text, ''declarado''::text, ''inferido''::text])))' then
    raise exception 'F5: la regla de origen no quedó como se esperaba';
  end if;
  if (select count(*) from pg_catalog.pg_trigger where tgrelid = 'public.cronograma_pagos'::regclass
      and tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert', 'trg_cronograma_pagos_20_sellar_cuenta_update')) <> 2 then
    raise exception 'F5: faltan los triggers del sello';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$registro$])
on conflict (version) do nothing;
select version, name from supabase_migrations.schema_migrations where version = '20260927024423';
commit;
