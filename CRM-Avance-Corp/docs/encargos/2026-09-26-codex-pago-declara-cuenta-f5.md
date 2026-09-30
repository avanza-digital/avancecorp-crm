ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: Cuentas de Gloria · F5 — el registro de pagos declara a qué cuenta se depositó (LEVEL 3: pagos)

Tu trabajo es REFUTAR: busca fallos reales en el SQL (autorización, el ajuste de transacción
crm.cci_deposito, la resolución de la cuenta por CCI, la restricción a cuentas de pago del contrato,
carreras con F3/F4/versionado de cuentas, corrección de fechas, idempotencia) y en la pantalla
(importación por RPC, modal manual, textos, estados). Sin hallazgo sin evidencia. Única ronda.

## Decisiones de Miguel (dueño, NO son hallazgos)
- Solo se acepta como cuenta del depósito la cuenta de pago ACTUAL del contrato o una que lo haya
  sido antes (enlace crm.contrato_cuentas_pago o historial crm.contrato_cuenta_pago_cambios), en
  cualquiera de sus versiones (cliente+moneda+CCI). Otro CCI del cliente se rechaza (22023).
- El modal de pago manual muestra la cuenta de pago vigente del contrato y la declara al confirmar.
- Sin CCI (o vacío) se deduce por la fecha como hasta hoy. Los pagos anteriores conservan su
  constancia ('registro' o 'inferido').
- Un admin con la membresía CRM revocada (P04) marca pagos igual que con el UPDATE directo vigente:
  la RLS de public.cronograma_pagos (es_gestor_cartera) no aplica P04 y no se toca en esta fase
  (documentado en el test como AVISO).

## Contexto verificado (producción y banco Docker con el esquema de prod, PG 17.6)
- Hoy el portal registra pagos con `UPDATE public.cronograma_pagos … where id = … and estado =
  'pendiente'` bajo la policy `cronograma_admin_actualiza` (USING/WITH CHECK es_gestor_cartera()).
  El trigger 00 bloquea el contrato FOR UPDATE y el 10 exige enlace (FOR SHARE). El sello (F3) es un
  trigger AFTER de estado/fecha_pago_real.
- F3 sellaba por FECHA: si el mismo día del cambio A→B se importa un Excel exportado con A, el pago
  quedaba en B (caso «mismo día», aceptado en F3 como riesgo). F5 lo cierra declarando el CCI.
- `crm.cuentas_bancarias.cci` es not null con check `^[0-9]{20}$`; versiones: una sola activa por
  (cliente, moneda, CCI); corregir datos crea otra versión y deja la vieja inactiva pero enlazada.
- El Excel de Pagos ya trae la columna «CCI» de cada fila (la cuenta con la que se exportó).
- PostgREST: una RPC por transacción; `set_config(…, true)` es local a la transacción.

## Evidencia de ejecución (banco Docker)
```
1. aplicar F3 + F4 + arreglos + F5: OK
2. huella F5 (4 funciones, cuerpo+comentario): af5c176fb94a153098da7b10e3c6e9af
4. test F5: 12 comprobaciones OK (5 mutantes) · PAGO_DECLARA_CUENTA_OK
5. test F3, F4 y arreglos con F5 encima: CAMBIO_CUENTA_OK · RETIRO_CUENTA_OK · ARREGLOS_OK
6. registro ensayado (y revertido) · 7. la reversa se niega con sellos declarados (ensayado)
8-11. reversas F5 → arreglos → F4 → F3: OK · 12. catálogo idéntico al estado base (2052 líneas)
Portal: 160/160 tests. Navegador local con Supabase simulado (?cambio=1 = Gloria ya cambió K1 a B):
  · pago manual: el modal muestra «Se depositó en: Interbank …» (B) y la RPC recibe p_cci de B;
  · importación de un Excel exportado con A: la RPC recibe p_cci de A y el pago queda en A (declarado).
```
### Avisos del test F5
```
OK mismo día: el Excel viejo con el CCI de A deja el pago en A (declarado) aunque el contrato ya cobre en B; sin CCI se deduce por fecha; el pago anterior no cambia
OK reglas: CCI ajeno al contrato, CCI mal formado, monto nulo/cero, cuota inexistente y ya pagada no marcan ni sellan
OK versiones: el CCI resuelve la cuenta física (versión vigente) y acepta la cuenta actual y la histórica del contrato
OK fechas: corregir la fecha no toca lo declarado y recalcula lo deducido; anular y volver a pagar re-sella como declarado
AVISO documentado: el admin revocado (P04) marca pagos, igual que con el UPDATE directo vigente (la RLS de public.cronograma_pagos no aplica P04)
OK permisos: analista y cliente no marcan (RLS); operaciones y admin sí; el ajuste se limpia al salir
OK anon: 42501
OK lectura: pagadas por cuenta trae declaradas (A: 4, 3 declaradas · B: 3, 3 declaradas)
OK mutante 1 cazado (sin la declaración, el pago del mismo día iría a la cuenta nueva)
OK mutante 2 cazado (sin la restricción, un depósito a una cuenta ajena al contrato se sellaría)
OK mutante 3 cazado (sin limpiar, el CCI se quedaría en la transacción)
OK mutante 4 cazado (sin validar, un CCI dañado se registraría como si no hubiera CCI)
OK mutante 5 cazado (sin exigir pendiente, pisaría un pago ya registrado)
```

## Migración (texto íntegro) — CRM-Avance-Corp/supabase/migrations/20260927024423_crm_pago_declara_cuenta.sql
```sql
-- Cuentas de Gloria · F5: el registro de pagos declara a qué cuenta se depositó (26/09/2026).
--
-- Qué hace:
--   1. El sello por cuota (private.sellar_cuenta_cuota_pagada) admite una cuenta DECLARADA: si la
--      transacción trae el ajuste crm.cci_deposito, la cuota se sella en la cuenta del cliente con
--      ese CCI (cualquier versión: cliente+moneda+CCI), siempre que sea o haya sido cuenta de pago
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
  v_nuevo_pago boolean := tg_op = 'INSERT';
  v_origen_previo text;
begin
  if not v_nuevo_pago then
    v_nuevo_pago := old.estado is distinct from 'pagado';
  end if;
  -- Corrección de la fecha de una cuota ya pagada: solo se recalcula un sello deducido por la
  -- fecha ('registro'); lo declarado y lo inferido no dependen de ella.
  if not v_nuevo_pago then
    select q.origen into v_origen_previo from crm.cuotas_cuenta_pagada q where q.cuota_id = new.id;
    if v_origen_previo is distinct from 'registro' then
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
  update public.cronograma_pagos
     set estado = 'pagado', fecha_pago_real = p_fecha, monto_pagado = p_monto,
         registrado_por = (select auth.uid())
   where id = p_cuota_id and estado = 'pendiente'
  returning id into v_id;
  perform pg_catalog.set_config('crm.cci_deposito', '', true);
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

comment on function private.sellar_cuenta_cuota_pagada() is 'Trigger AFTER en public.cronograma_pagos: al pasar una cuota a pagado sella la cuenta DECLARADA (ajuste crm.cci_deposito: cuenta de pago del contrato, actual o histórica, con ese CCI) o, sin declaración, la vigente en la fecha del pago; corregir la fecha re-sella solo lo deducido. No cambia el registro del pago. SECURITY DEFINER porque quien registra el pago (gestor de cartera) no tiene grants sobre los registros crm.';
comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes, cuotas pagadas por cuenta (con las inferidas y las declaradas aparte) y cuenta_retirada (la cuenta física de pago ya no tiene versión vigente: hay que cambiarla). Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre enlace ni sellos. DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago y la marca cuenta_retirada. Solo admin.';
comment on function crm.registrar_pago_con_cuenta(uuid, date, numeric, text) is 'Marca una cuota PENDIENTE como pagada declarando el CCI de la cuenta a la que se depositó (20 dígitos; vacío = se deduce por la fecha); rechaza monto nulo o <= 0. INVOKER: el UPDATE corre con la RLS de quien registra (gestor de cartera). La usan la importación del Excel y el modal de pago manual. Devuelve la cuota o NULL si no estaba pendiente.';

-- ── 4. Postflight ──────────────────────────────────────────────────────────────────────────
do $postflight$
declare v_f record;
begin
  for v_f in
    select * from (values
      ('private.sellar_cuenta_cuota_pagada()', null),
      ('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', 'authenticated'),
      ('private.contratos_cuenta_pago_cliente_autorizado(uuid)', 'authenticated'),
      ('crm.contratos_cuenta_pago_cliente_fn(uuid)', 'authenticated')
    ) as f(firma, rol)
  loop
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
  if (select prosecdef from pg_catalog.pg_proc where oid = 'crm.registrar_pago_con_cuenta(uuid,date,numeric,text)'::regprocedure) then
    raise exception 'F5: la RPC de registro debe ser INVOKER';
  end if;
  if (select count(*) from pg_catalog.pg_trigger where tgrelid = 'public.cronograma_pagos'::regclass
      and tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert', 'trg_cronograma_pagos_20_sellar_cuenta_update')) <> 2 then
    raise exception 'F5: faltan los triggers del sello';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Test (texto íntegro) — CRM-Avance-Corp/supabase/scripts/cuentas-gloria/test-pago-declara-cuenta.sql
```sql
-- PRUEBA de 20260927024423_crm_pago_declara_cuenta (F5) — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra datos FICTICIOS en UNA transacción que termina en ROLLBACK.
-- Requiere aplicadas F3 (20260926204051), F4 (20260927012948), los arreglos (20260927020317) y F5.
--
-- Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-pago-declara-cuenta.sql
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

select to_regprocedure('private.exigir_cuenta_pago_cronograma()') is null as falta_exigir \gset
\if :falta_exigir
\ir ../../migrations/20260925194026_p0xx_pagos_solo_cuenta_contractual.sql
\endif

-- ── Siembra ficticia ─────────────────────────────────────────────────────────────────────────
-- 01 admin · 02 operaciones · 03 analista (asesor de C) · 05 cliente C · 07 admin revocado (P04).
insert into auth.users (id, email, aud, role) values
  ('e7b60000-0000-4000-8000-000000000001', 'f6.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000002', 'f6.oper@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000003', 'f6.analista@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000005', 'f6.cliente@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000007', 'f6.revocada@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, nombres, dni, correo, rol, activo, asesor_perfil_id) values
  ('e7b60000-0000-4000-8000-000000000001', 'F6 ADMIN PRUEBA', null, '77760001', 'f6.admin@prueba.invalid', 'admin', true, null),
  ('e7b60000-0000-4000-8000-000000000002', 'F6 OPERACIONES PRUEBA', null, '77760002', 'f6.oper@prueba.invalid', 'operaciones', true, null),
  ('e7b60000-0000-4000-8000-000000000003', 'F6 ANALISTA PRUEBA', null, '77760003', 'f6.analista@prueba.invalid', 'analista', true, null),
  ('e7b60000-0000-4000-8000-000000000005', 'PRUEBA CLIENTE EF', 'CLIENTE', '77760005', 'f6.cliente@prueba.invalid', 'cliente', true, 'e7b60000-0000-4000-8000-000000000003'),
  ('e7b60000-0000-4000-8000-000000000007', 'F6 ADMIN REVOCADA', null, '77760007', 'f6.revocada@prueba.invalid', 'admin', true, null);
insert into crm.equipo (perfil_id, rol_crm, activo) values ('e7b60000-0000-4000-8000-000000000007', 'gerencia', false);

-- Cuentas del cliente C (PEN): A (cuenta de pago de K1), B (vigente, será la nueva), Z (vigente pero
-- NUNCA de pago de K1: anomalía), Av (versión VIEJA de A, mismo CCI, retirada al corregir).
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, activa, origen, creado_en, desactivada_por, desactivada_en) values
  ('e7b6c000-0000-4000-8000-000000000001', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros', '19100000000001', '00219100000000000001', false, true, 'contrato', '2026-03-01', null, null),
  ('e7b6c000-0000-4000-8000-000000000002', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros', '89830000000002', '00389800000000000002', false, true, 'contrato', '2026-09-20', null, null),
  ('e7b6c000-0000-4000-8000-000000000003', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'Scotiabank', 'ahorros', '00070000000003', '00907000000000000003', false, true, 'contrato', '2026-01-03', null, null),
  ('e7b6c000-0000-4000-8000-000000000004', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'corriente', '19100000000001', '00219100000000000001', false, false, 'contrato', '2026-01-01', 'e7b60000-0000-4000-8000-000000000001', '2026-03-01 10:00-05');
alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial) values
  ('e7b6d000-0000-4000-8000-000000000001', 'F6-K1', 'e7b60000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo', '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01');
alter table public.contratos enable trigger user;
insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values
  ('e7b6d000-0000-4000-8000-000000000001', 'e7b6c000-0000-4000-8000-000000000001');
-- Cuotas: #1 pagada de antes (deducida), #2..#7 pendientes.
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado, fecha_pago_real) values
  ('e7b6e000-0000-4000-8000-000000000001', 'e7b6d000-0000-4000-8000-000000000001', 1, '2026-02-01', 100, 'pagado', '2026-02-01'),
  ('e7b6e000-0000-4000-8000-000000000002', 'e7b6d000-0000-4000-8000-000000000001', 2, '2026-10-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000003', 'e7b6d000-0000-4000-8000-000000000001', 3, '2026-11-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000004', 'e7b6d000-0000-4000-8000-000000000001', 4, '2026-12-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000005', 'e7b6d000-0000-4000-8000-000000000001', 5, '2027-01-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000006', 'e7b6d000-0000-4000-8000-000000000001', 6, '2027-02-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000007', 'e7b6d000-0000-4000-8000-000000000001', 7, '2027-03-01', 100, 'pendiente', null);
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  ('respaldos-cambio-cuenta', 'e7b60000-0000-4000-8000-000000000005/e7b6f000-0000-4000-8000-000000000001.pdf',
   'e7b60000-0000-4000-8000-000000000001', 'e7b60000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f601\""}');

-- ── Utilidades ───────────────────────────────────────────────────────────────────────────────
create function pg_temp.registrar(p_uid uuid, p_cuota uuid, p_fecha date, p_monto numeric, p_cci text) returns text
language plpgsql as $f$
declare r uuid; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.registrar_pago_con_cuenta(p_cuota, p_fecha, p_monto, p_cci);
    execute 'reset role';
    return 'OK:' || coalesce(r::text, 'null');
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR:' || e || ':' || m;
  end;
end;
$f$;
create function pg_temp.cambio(p_sol uuid, p_cta uuid, p_mot text) returns text
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b60000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.cambiar_cuenta_pago_contratos(p_sol, 'e7b60000-0000-4000-8000-000000000005', p_cta,
      array['e7b6d000-0000-4000-8000-000000000001'::uuid], p_mot,
      'e7b60000-0000-4000-8000-000000000005/e7b6f000-0000-4000-8000-000000000001.pdf');
    execute 'reset role';
    return 'OK:' || r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR:' || e || ':' || m;
  end;
end;
$f$;
create function pg_temp.espera(p_resultado text, p_prefijo text, p_caso text) returns void
language plpgsql as $f$
begin
  if p_resultado is null or p_resultado not like p_prefijo || '%' then
    raise exception 'FALLO [%]: esperaba «%…», vino «%»', p_caso, p_prefijo, p_resultado;
  end if;
end;
$f$;
create function pg_temp.sello(p_cuota uuid) returns text language sql as $f$
  select coalesce((select cuenta_bancaria_id::text || '|' || origen from crm.cuotas_cuenta_pagada where cuota_id = p_cuota), 'sin sello');
$f$;
create function pg_temp.estado(p_cuota uuid) returns text language sql as $f$
  select estado from public.cronograma_pagos where id = p_cuota;
$f$;
create function pg_temp.hoy() returns date language sql as $f$
  select (now() at time zone 'America/Lima')::date;
$f$;
create function pg_temp.mutar(p_firma text, p_de text, p_a text) returns void
language plpgsql as $f$
declare s text; t text;
begin
  s := pg_get_functiondef(p_firma::regprocedure);
  t := replace(s, p_de, p_a);
  if t = s then raise exception 'MUTANTE MAL ESCRITO: no se encontró el fragmento en %', p_firma; end if;
  execute t;
end;
$f$;

-- ── A. El caso del «mismo día» (criterio 1) y las reglas de la RPC ──────────────────────────
do $mismo_dia$
declare
  A constant text := 'e7b6c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b6c000-0000-4000-8000-000000000002';
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C2 constant uuid := 'e7b6e000-0000-4000-8000-000000000002';
  C3 constant uuid := 'e7b6e000-0000-4000-8000-000000000003';
  C4 constant uuid := 'e7b6e000-0000-4000-8000-000000000004';
begin
  -- #1 pagada antes de F5: sigue 'registro' en A (criterio 5).
  perform pg_temp.espera(pg_temp.sello('e7b6e000-0000-4000-8000-000000000001'), A || '|registro', 'pago anterior');
  -- El Excel se exportó con A y Operaciones depositó en A; ESE MISMO DÍA Gloria cambia K1 a B.
  perform pg_temp.espera(pg_temp.cambio('e7b6a000-0000-4000-8000-000000000001', B, 'El cliente pidió cobrar en Interbank'), 'OK:', 'cambio A→B');
  -- Importación posterior: la fila declara el CCI de A → queda en A como declarado, no en B.
  perform pg_temp.espera(pg_temp.registrar(OPER, C2, pg_temp.hoy(), 100, '00219100000000000001'), 'OK:' || C2::text, 'importación con CCI de A');
  perform pg_temp.espera(pg_temp.sello(C2), A || '|declarado', 'mismo día → A declarado');
  -- El formato del Excel no importa: espacios, guiones, apóstrofo de Excel.
  perform pg_temp.espera(pg_temp.registrar(OPER, C3, pg_temp.hoy(), 100, ' ''002-19100000000000001 '), 'OK:' || C3::text, 'CCI con formato');
  perform pg_temp.espera(pg_temp.sello(C3), A || '|declarado', 'CCI con formato → A');
  -- Sin CCI: se deduce por la fecha como hasta hoy (pago de hoy → B, la cuenta nueva).
  perform pg_temp.espera(pg_temp.registrar(OPER, C4, pg_temp.hoy(), 100, null), 'OK:' || C4::text, 'sin CCI');
  perform pg_temp.espera(pg_temp.sello(C4), B::text || '|registro', 'sin CCI → deducido');
  raise notice 'OK mismo día: el Excel viejo con el CCI de A deja el pago en A (declarado) aunque el contrato ya cobre en B; sin CCI se deduce por fecha; el pago anterior no cambia';
end;
$mismo_dia$;

do $reglas$
declare
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C5 constant uuid := 'e7b6e000-0000-4000-8000-000000000005';
  C2 constant uuid := 'e7b6e000-0000-4000-8000-000000000002';
begin
  -- Criterio 2: CCI de una cuenta del cliente que NUNCA fue de pago de este contrato → rechazo, sin marcar.
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, '00907000000000000003'), 'ERR:22023:El CCI del depósito no es de una cuenta de pago de este contrato', 'CCI ajeno al contrato');
  perform pg_temp.espera(pg_temp.estado(C5), 'pendiente', 'CCI ajeno no marca');
  perform pg_temp.espera(pg_temp.sello(C5), 'sin sello', 'CCI ajeno no sella');
  -- CCI mal formado, monto nulo o cero, cuota inexistente.
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, '123'), 'ERR:22023:El CCI del depósito no tiene 20 dígitos', 'CCI corto');
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, 'N/A'), 'ERR:22023:El CCI del depósito no tiene 20 dígitos', 'CCI sin dígitos');
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), null, null), 'ERR:22023:El monto pagado debe ser mayor que cero', 'monto nulo');
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 0, null), 'ERR:22023:El monto pagado debe ser mayor que cero', 'monto cero');
  perform pg_temp.espera(pg_temp.registrar(OPER, gen_random_uuid(), pg_temp.hoy(), 100, null), 'OK:null', 'cuota inexistente');
  -- Ya pagada: no se marca dos veces (NULL), y su sello no cambia.
  perform pg_temp.espera(pg_temp.registrar(OPER, C2, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:null', 'ya pagada');
  perform pg_temp.espera(pg_temp.sello(C2), 'e7b6c000-0000-4000-8000-000000000001|declarado', 'ya pagada conserva su sello');
  perform pg_temp.espera(pg_temp.estado(C5), 'pendiente', 'nada marcó C5');
  raise notice 'OK reglas: CCI ajeno al contrato, CCI mal formado, monto nulo/cero, cuota inexistente y ya pagada no marcan ni sellan';
end;
$reglas$;

-- ── B. Versión vieja de la cuenta de pago (mismo CCI) y cuenta histórica de F3 ──────────────
do $versiones$
declare
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C5 constant uuid := 'e7b6e000-0000-4000-8000-000000000005';
  C6 constant uuid := 'e7b6e000-0000-4000-8000-000000000006';
begin
  -- Av (versión vieja de A, mismo CCI) resuelve a la versión vigente A: misma cuenta física.
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, '00219100000000000001'), 'OK:' || C5::text, 'CCI de la cuenta física A');
  perform pg_temp.espera(pg_temp.sello(C5), 'e7b6c000-0000-4000-8000-000000000001|declarado', 'resuelve a la versión vigente');
  -- B es la cuenta de pago actual (tras el cambio): declarada, queda en B.
  perform pg_temp.espera(pg_temp.registrar(OPER, C6, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:' || C6::text, 'CCI de B');
  perform pg_temp.espera(pg_temp.sello(C6), 'e7b6c000-0000-4000-8000-000000000002|declarado', 'B declarado');
  raise notice 'OK versiones: el CCI resuelve la cuenta física (versión vigente) y acepta la cuenta actual y la histórica del contrato';
end;
$versiones$;

-- ── C. Corregir fecha no re-sella lo declarado; anular y volver a pagar re-sella (criterio 5) ──
do $fechas$
declare
  C2 constant uuid := 'e7b6e000-0000-4000-8000-000000000002';
  C4 constant uuid := 'e7b6e000-0000-4000-8000-000000000004';
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
begin
  update public.cronograma_pagos set fecha_pago_real = pg_temp.hoy() - 30 where id in (C2, C4);
  perform pg_temp.espera(pg_temp.sello(C2), 'e7b6c000-0000-4000-8000-000000000001|declarado', 'declarado no se recalcula');
  perform pg_temp.espera(pg_temp.sello(C4), 'e7b6c000-0000-4000-8000-000000000001|registro', 'deducido sí se recalcula (hace 30 días cobraba A)');
  -- Anular y volver a pagar con CCI: re-sella como declarado (una sola fila por cuota).
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = C4;
  perform pg_temp.espera(pg_temp.registrar(OPER, C4, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:' || C4::text, 'volver a pagar');
  perform pg_temp.espera(pg_temp.sello(C4), 'e7b6c000-0000-4000-8000-000000000002|declarado', 're-sellado como declarado');
  if (select count(*) from crm.cuotas_cuenta_pagada where cuota_id = C4) <> 1 then raise exception 'FALLO: dos sellos para una cuota'; end if;
  raise notice 'OK fechas: corregir la fecha no toca lo declarado y recalcula lo deducido; anular y volver a pagar re-sella como declarado';
end;
$fechas$;

-- ── D. Permisos (criterio 4): quién marca y quién no; el ajuste no se fija fuera de la RPC ──
do $permisos$
declare
  C7 constant uuid := 'e7b6e000-0000-4000-8000-000000000007';
  u uuid; v text;
begin
  foreach u in array array['e7b60000-0000-4000-8000-000000000003', 'e7b60000-0000-4000-8000-000000000005']::uuid[] loop
    perform pg_temp.espera(pg_temp.registrar(u, C7, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:null', 'no gestor ' || u);
    perform pg_temp.espera(pg_temp.estado(C7), 'pendiente', 'no gestor no marca ' || u);
  end loop;
  -- Un admin con la membresía CRM revocada: hoy la RLS de pagos (es_gestor_cartera) no aplica P04.
  -- Se documenta el comportamiento real: marca (igual que con el UPDATE directo de siempre).
  v := pg_temp.registrar('e7b60000-0000-4000-8000-000000000007', C7, pg_temp.hoy(), 100, '00389800000000000002');
  if v like 'OK:' || C7::text then
    raise notice 'AVISO documentado: el admin revocado (P04) marca pagos, igual que con el UPDATE directo vigente (la RLS de public.cronograma_pagos no aplica P04)';
    update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = C7;
  end if;
  -- El admin sí marca.
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000001', C7, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:' || C7::text, 'admin');
  -- El ajuste queda limpio tras la RPC.
  if coalesce(current_setting('crm.cci_deposito', true), '') <> '' then raise exception 'FALLO: el ajuste crm.cci_deposito no se limpió'; end if;
  raise notice 'OK permisos: analista y cliente no marcan (RLS); operaciones y admin sí; el ajuste se limpia al salir';
end;
$permisos$;
-- anon no ejecuta la RPC.
set local role anon;
do $anon$
begin
  begin
    perform crm.registrar_pago_con_cuenta(gen_random_uuid(), current_date, 100, null);
    raise exception 'FALLO: anon pudo llamar la RPC';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK anon: 42501';
end;
$anon$;
reset role;

-- ── E. Lectura: pagadas por cuenta distingue declaradas ──────────────────────────────────────
do $lectura$
declare r record;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b60000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into r from crm.contratos_cuenta_pago_cliente_fn('e7b60000-0000-4000-8000-000000000005') where numero_contrato = 'F6-K1';
  execute 'reset role';
  -- A: #1 registro + #2 #3 #5 declaradas = 4 (3 declaradas) · B: #4 #6 #7 declaradas = 3 (3 declaradas)
  if r.pagadas_por_cuenta <> jsonb_build_array(
       jsonb_build_object('cuenta_bancaria_id', 'e7b6c000-0000-4000-8000-000000000001', 'banco', 'BCP', 'numero_cuenta', '19100000000001', 'cuotas', 4, 'inferidas', 0, 'declaradas', 3),
       jsonb_build_object('cuenta_bancaria_id', 'e7b6c000-0000-4000-8000-000000000002', 'banco', 'Interbank', 'numero_cuenta', '89830000000002', 'cuotas', 3, 'inferidas', 0, 'declaradas', 3)) then
    raise exception 'FALLO: pagadas_por_cuenta no cuadra: %', r.pagadas_por_cuenta;
  end if;
  raise notice 'OK lectura: pagadas por cuenta trae declaradas (A: 4, 3 declaradas · B: 3, 3 declaradas)';
end;
$lectura$;

-- ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
-- M1: el sello ignora la declaración → el Excel viejo del «mismo día» quedaría en B.
savepoint m1;
select pg_temp.mutar('private.sellar_cuenta_cuota_pagada()', 'if v_nuevo_pago and v_cci is not null then', 'if false then');
do $m1$ begin
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = 'e7b6e000-0000-4000-8000-000000000002';
  perform pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000002', pg_temp.hoy(), 100, '00219100000000000001');
  if pg_temp.sello('e7b6e000-0000-4000-8000-000000000002') = 'e7b6c000-0000-4000-8000-000000000001|declarado' then raise exception 'MUTANTE 1 NO CAZADO'; end if;
  raise notice 'OK mutante 1 cazado (sin la declaración, el pago del mismo día iría a la cuenta nueva)';
end $m1$;
rollback to savepoint m1;

-- M2: el sello acepta cualquier cuenta del cliente → un depósito a Z (nunca de pago) se sellaría.
savepoint m2;
select pg_temp.mutar('private.sellar_cuenta_cuota_pagada()',
  'and ref.cliente_id = cb.cliente_id and ref.moneda = cb.moneda and ref.cci = cb.cci)',
  'and true) or true');
do $m2$ begin
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000007', pg_temp.hoy(), 100, '00907000000000000003'), 'OK:', 'MUTANTE 2 NO CAZADO');
  raise notice 'OK mutante 2 cazado (sin la restricción, un depósito a una cuenta ajena al contrato se sellaría)';
end $m2$;
rollback to savepoint m2;

-- M3: la RPC no limpia el ajuste → un UPDATE directo posterior en la misma transacción heredaría el CCI.
savepoint m3;
select pg_temp.mutar('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', $r$perform pg_catalog.set_config('crm.cci_deposito', '', true);
  return v_id;$r$, $r$return v_id;$r$);
do $m3$ begin
  perform pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000007', pg_temp.hoy(), 100, '00389800000000000002');
  if coalesce(current_setting('crm.cci_deposito', true), '') = '' then raise exception 'MUTANTE 3 NO CAZADO'; end if;
  raise notice 'OK mutante 3 cazado (sin limpiar, el CCI se quedaría en la transacción)';
end $m3$;
rollback to savepoint m3;

-- M4: la RPC sin validar el CCI → «N/A» pasaría en silencio como «sin CCI».
savepoint m4;
select pg_temp.mutar('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', $r$if pg_catalog.btrim(coalesce(p_cci, '')) <> '' and (v_cci is null or pg_catalog.length(v_cci) <> 20) then$r$, 'if false then');
do $m4$ begin
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000007', pg_temp.hoy(), 100, 'N/A'), 'OK:', 'MUTANTE 4 NO CAZADO');
  raise notice 'OK mutante 4 cazado (sin validar, un CCI dañado se registraría como si no hubiera CCI)';
end $m4$;
rollback to savepoint m4;

-- M5: la RPC marca cuotas ya pagadas → pisaría un pago registrado.
savepoint m5;
select pg_temp.mutar('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', $r$where id = p_cuota_id and estado = 'pendiente'$r$, $r$where id = p_cuota_id$r$);
do $m5$ begin
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000002', pg_temp.hoy(), 100, null), 'OK:e7b6e000', 'MUTANTE 5 NO CAZADO');
  raise notice 'OK mutante 5 cazado (sin exigir pendiente, pisaría un pago ya registrado)';
end $m5$;
rollback to savepoint m5;

select 'PAGO_DECLARA_CUENTA_OK' as veredicto;
rollback;
```

## Reversa — CRM-Avance-Corp/supabase/scripts/cuentas-gloria/reversa-pago-declara-cuenta.sql
```sql
-- REVERSA de 20260927024423_crm_pago_declara_cuenta (F5).
-- Repone byte a byte el sello y la lectura de F3 (con los arreglos 20260927020317) y la regla de
-- origen; retira la RPC. Se NIEGA si ya hay sellos 'declarado' (su constancia se perdería) o si las
-- piezas vivas no son las de F5 (huella af5c176fb94a153098da7b10e3c6e9af).
begin;
set local lock_timeout = '5s';
do $pre$
declare v_huella text;
begin
  if to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)') is null then
    raise exception 'REVERSA: la F5 no está aplicada';
  end if;
  lock table crm.cuotas_cuenta_pagada in access exclusive mode;
  if exists (select 1 from crm.cuotas_cuenta_pagada where origen = 'declarado') then
    raise exception 'REVERSA: ya hay pagos con cuenta declarada; revertir borraría su constancia';
  end if;
  select pg_catalog.md5(pg_catalog.string_agg(p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc)
           || '|' || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-'), E'\n'
           order by p.oid::regprocedure::text))
    into v_huella
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('private.sellar_cuenta_cuota_pagada()'),
                  to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)'),
                  to_regprocedure('private.contratos_cuenta_pago_cliente_autorizado(uuid)'),
                  to_regprocedure('crm.contratos_cuenta_pago_cliente_fn(uuid)'));
  if v_huella is distinct from 'af5c176fb94a153098da7b10e3c6e9af' then
    raise exception 'REVERSA: las piezas vivas no son las de la F5 (huella %); no se toca', v_huella;
  end if;
end $pre$;

drop function crm.registrar_pago_con_cuenta(uuid, date, numeric, text);
CREATE OR REPLACE FUNCTION private.sellar_cuenta_cuota_pagada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cuenta uuid;
  v_nuevo_pago boolean := tg_op = 'INSERT';
begin
  if not v_nuevo_pago then
    v_nuevo_pago := old.estado is distinct from 'pagado';
  end if;
  -- Corrección de la fecha de una cuota ya pagada: solo se recalcula un sello deducido por la
  -- fecha ('registro'); el inferido no depende de ella.
  if not v_nuevo_pago
     and exists (select 1 from crm.cuotas_cuenta_pagada q
                 where q.cuota_id = new.id and q.origen <> 'registro') then
    return null;
  end if;
  -- La cuenta vigente en la FECHA del pago: si después de esa fecha (día de Lima) hubo un cambio,
  -- la cuenta anterior del primero; si no, la cuenta contractual actual. Así, registrar tarde (o
  -- volver a registrar tras anular) un pago viejo no lo atribuye a la cuenta nueva. Un pago con
  -- fecha del mismo día del cambio va a la cuenta nueva: la fecha no dice la hora del depósito
  -- (la importación del Excel avisa esas filas).
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
  insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
  values (new.id, new.contrato_id, v_cuenta, case when v_nuevo_pago then 'registro' else 'inferido' end)
  on conflict (cuota_id) do update
    set contrato_id = excluded.contrato_id,
        cuenta_bancaria_id = excluded.cuenta_bancaria_id,
        origen = case when v_nuevo_pago then excluded.origen else crm.cuotas_cuenta_pagada.origen end,
        sellada_en = pg_catalog.now();
  return null;
end;
$function$;

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
                    'numero_cuenta', sb.numero_cuenta, 'cuotas', s.n, 'inferidas', s.inferidas)
                  order by s.n desc)
           from (select q.cuenta_bancaria_id, count(*) as n,
                        count(*) filter (where q.origen = 'inferido') as inferidas
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

comment on function private.sellar_cuenta_cuota_pagada() is 'Trigger AFTER en public.cronograma_pagos: al pasar una cuota a pagado sella la cuenta vigente en la fecha del pago; corregir la fecha re-sella lo deducido por fecha. No cambia el registro del pago. SECURITY DEFINER porque quien registra el pago (gestor de cartera) no tiene grants sobre los registros crm.';
comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes, cuotas pagadas por cuenta (con las inferidas aparte) y cuenta_retirada (la cuenta física de pago ya no tiene versión vigente: hay que cambiarla). Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre enlace ni sellos. DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago y la marca cuenta_retirada. Solo admin.';
alter table crm.cuotas_cuenta_pagada drop constraint cuotas_cuenta_pagada_origen_valido;
alter table crm.cuotas_cuenta_pagada add constraint cuotas_cuenta_pagada_origen_valido
  check (origen in ('registro', 'inferido'));
comment on column crm.cuotas_cuenta_pagada.origen is 'registro = deducida de la fecha del pago al registrarlo; inferido = backfill desde la cuenta contractual.';

do $chk$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc where oid = 'private.sellar_cuenta_cuota_pagada()'::regprocedure) <> 'bdc9ca16b94dbd2ec24e702e8d12651f'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = 'private.contratos_cuenta_pago_cliente_autorizado(uuid)'::regprocedure) <> 'd4d79c78d117d1458bd5aafa40cff89e'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = 'crm.contratos_cuenta_pago_cliente_fn(uuid)'::regprocedure) <> '4720e000300e7eda76f9a1f45ecd2c34'
     or to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)') is not null then
    raise exception 'REVERSA: las piezas repuestas no son las de F3 + arreglos';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;
```

## Portal — diff de pagos.js, cuentas-pago-core.js y pagos.html
```diff
diff --git a/admin/pagos.html b/admin/pagos.html
index c7ddffa..0bc868f 100644
--- a/admin/pagos.html
+++ b/admin/pagos.html
@@ -308,7 +308,7 @@
     </div>
   </div>
 
-  <script type="module" src="/js/admin/pagos.js?v=44"></script>
+  <script type="module" src="/js/admin/pagos.js?v=45"></script>
   <script type="module">
     import { initMobileMenu } from "/js/mobile-menu.js?v=12";
     initMobileMenu();
diff --git a/js/admin/cuentas-pago-core.js b/js/admin/cuentas-pago-core.js
index da4834b..72e18f6 100644
--- a/js/admin/cuentas-pago-core.js
+++ b/js/admin/cuentas-pago-core.js
@@ -137,24 +137,24 @@ export function cuentaPagoCompleta(cuenta) {
   )
 }
 
-/**
- * F3: ¿la cuenta de pago del contrato cambió después de exportar el Excel? Compara solo dígitos
- * (el formato de la celda no importa). Sin CCI de 20 dígitos en la fila (vacío o dañado, p. ej.
- * convertido en número) → no opina.
- */
-export function cuentaCambiadaDesdeExport(cuota) {
-  const exportado = String(cuota?.cci_excel ?? '').replace(/\D/g, '')
-  if (exportado.length !== 20) return false
-  const actual = cuentaParaCuota(cuota)
-  return !actual || String(actual.cci ?? '').replace(/\D/g, '') !== exportado
+// F5: el registro DECLARA a qué cuenta se depositó. En la importación va el CCI de la fila del
+// Excel; en el pago manual, el CCI de la cuenta de pago vigente del contrato (la que muestra el
+// modal). El servidor solo acepta cuentas de pago de ese contrato: otro CCI se rechaza.
+export function cciDeclaradoDeFila(cuota) {
+  const digitos = String(cuota?.cci_excel ?? '').replace(/\D/g, '')
+  return digitos.length === 20 ? digitos : null
+}
+
+// Traduce el rechazo del servidor a un motivo de fila de la importación (sin inventar).
+export function motivoRechazoRegistro(cliente, concepto, error) {
+  const quien = `${cliente} (${concepto})`
+  if (!error) return `${quien}: la cuota ya estaba pagada o no existe`
+  if (error.code === '22023' && error.message) return `${quien}: ${error.message}`
+  return `${quien}: ${error.message || 'error'}`
 }
 
-// El Excel se importa DESPUÉS de depositar: el registro no cambia y nunca se pide volver a pagar.
-// El servidor anota la cuenta vigente en la fecha del pago; un depósito a la cuenta anterior el
-// mismo día del cambio (o después, con un Excel viejo) quedaría anotado en la nueva: por eso se avisa.
-export function avisoPagosEnCuentaAnterior(clientes) {
-  const n = clientes.length
-  const distintos = [...new Set(clientes)]
-  const quienes = distintos.slice(0, 5).join(', ') + (distintos.length > 5 ? '…' : '')
-  return `${n} pago${n === 1 ? '' : 's'} del Excel ${n === 1 ? 'es de un contrato cuya' : 'son de contratos cuya'} cuenta de pago cambió después de exportarlo: ${quienes}. Se registra${n === 1 ? '' : 'n'} igual; no vuelvas a depositar. Si depositaste en la cuenta anterior el mismo día del cambio o después, avisa a administración.`
+// Texto de «Se depositó en:» del modal de pago manual.
+export function textoCuentaDeposito(cuenta) {
+  if (!cuenta) return 'Sin cuenta de pago — requiere conciliación'
+  return `${cuenta.banco} · ${cuenta.tipo_cuenta} · N°\u00A0${cuenta.numero_cuenta} · CCI\u00A0${cuenta.cci}`
 }
diff --git a/js/admin/pagos.js b/js/admin/pagos.js
index 4b77048..a0eed7e 100644
--- a/js/admin/pagos.js
+++ b/js/admin/pagos.js
@@ -29,9 +29,10 @@ import {
   asociarCuentasPagoPantalla,
   cuentaPagoCompleta,
   cuentaParaCuota,
-  cuentaCambiadaDesdeExport,
-  avisoPagosEnCuentaAnterior,
-} from './cuentas-pago-core.js?v=3'
+  cciDeclaradoDeFila,
+  motivoRechazoRegistro,
+  textoCuentaDeposito,
+} from './cuentas-pago-core.js?v=4'
 import { POR_PAGINA_POR_TRAMO, planPagina, etiquetaPagina } from './agenda-paginas-core.js?v=1'
 import {
   PAGE_SIZE_TABLA, parametrosTabla, mapearFilaResumen, totalDeRespuesta, paginaFueraDeRango, ultimaPagina,
@@ -55,6 +56,7 @@ let FILTRO_MONEDA     = ''
 const buscando = () => FILTRO_TEXTO.trim() !== ''
 let EXPANDIDO         = null        // contrato_id actualmente abierto (1 a la vez)
 let MODAL_CONTRATO_ID = null        // contrato del pago que se está editando en el modal
+let MODAL_CCI_DEPOSITO = null       // F5: CCI de la cuenta que muestra el modal; se declara al confirmar
 let MODAL_PROGRAMADO = 0            // monto programado de la cuota abierta (fuente fiable del aviso de pago parcial)
 let MODAL_MONEDA = 'PEN'           // moneda de la cuota abierta
 let ULTIMO_PAGO       = null        // datos del último pago registrado (para botón WhatsApp en el toast)
@@ -906,20 +908,6 @@ async function onArchivoImportSeleccionado(e) {
       aMarcar.push(...validadas)
     }
 
-    // CUENTA DE DEPÓSITO (F3): el registro no cambia; el servidor anota en cada cuota la cuenta
-    // vigente en la fecha del pago. Si la cuenta de pago del contrato cambió después de exportar
-    // el Excel, se avisa (el dinero ya salió: nunca se pide volver a depositar).
-    // Es solo un aviso: si la consulta falla, la importación sigue igual que siempre.
-    let enCuentaAnterior = []
-    if (aMarcar.length > 0) {
-      try {
-        const filasCuenta = await consultarCuentasContractuales([...new Set(aMarcar.map(x => x.contrato_id))])
-        enCuentaAnterior = asociarCuentasPagoContrato(aMarcar, filasCuenta).filter(cuentaCambiadaDesdeExport)
-      } catch (errCuenta) {
-        console.warn('[pagos] no se pudo comprobar si cambió la cuenta de pago:', errCuenta)
-      }
-    }
-
     document.getElementById('imp_loading').classList.add('hidden')
 
     if (aMarcar.length === 0 && rechazadas.length === 0) {
@@ -944,9 +932,6 @@ async function onArchivoImportSeleccionado(e) {
         <strong>${totalTxt}</strong>.
       </p>
     `
-    if (enCuentaAnterior.length > 0) {
-      html += `<div class="alert alert-warning" style="font-size:12px; margin-top: 10px;">⚠️ ${escapeHtml(avisoPagosEnCuentaAnterior(enCuentaAnterior.map(x => x.cliente)))}</div>`
-    }
     if (rechazadas.length > 0) {
       html += `
         <details class="alert alert-warning" style="font-size:12px; margin-top: 10px;">
@@ -978,26 +963,22 @@ async function aplicarImportacion() {
   try {
     const { data: { session } } = await supabase.auth.getSession()
     if (!session) throw new Error('Tu sesión expiró. Vuelve a iniciar sesión.')
-    const registradoPor = session.user.id
 
     // El archivo puede ser antiguo. Se consulta de nuevo antes de marcar;
     // el trigger del servidor repite la regla en la misma transacción del UPDATE.
     await verificarCuentasParaCuotas(IMPORT_PENDING)
 
-    // Updates en paralelo. Cada update incluye `.eq('estado', 'pendiente')` para
-    // evitar pisar pagos ya registrados manualmente entre el export y el import.
+    // F5: cada fila se registra por crm.registrar_pago_con_cuenta DECLARANDO el CCI de su columna
+    // «CCI» (la cuenta a la que de verdad se depositó). Misma RLS que el UPDATE directo; solo marca
+    // cuotas pendientes (no pisa pagos registrados a mano entre el export y el import). Un CCI que
+    // no es cuenta de pago de ese contrato lo rechaza el servidor y la fila queda como error.
     const resultados = await Promise.allSettled(IMPORT_PENDING.map(item =>
-      supabase
-        .from('cronograma_pagos')
-        .update({
-          estado: 'pagado',
-          fecha_pago_real: item.fecha_pago,
-          monto_pagado: item.monto_pagado,
-          registrado_por: registradoPor,
-        })
-        .eq('id', item.cuota_id)
-        .eq('estado', 'pendiente')
-        .select('id')
+      supabase.schema('crm').rpc('registrar_pago_con_cuenta', {
+        p_cuota_id: item.cuota_id,
+        p_fecha: item.fecha_pago,
+        p_monto: item.monto_pagado,
+        p_cci: cciDeclaradoDeFila(item),
+      })
     ))
 
     let aplicadas = 0
@@ -1006,12 +987,12 @@ async function aplicarImportacion() {
     resultados.forEach((r, i) => {
       const item = IMPORT_PENDING[i]
       if (r.status === 'rejected') {
-        errores.push(`${item.cliente} (${item.concepto}): ${r.reason?.message || 'error'}`)
+        errores.push(motivoRechazoRegistro(item.cliente, item.concepto, { message: r.reason?.message }))
       } else if (r.value.error) {
-        errores.push(`${item.cliente} (${item.concepto}): ${r.value.error.message}`)
-      } else if ((r.value.data?.length || 0) === 0) {
-        // 0 filas afectadas = la cuota ya estaba pagada o el id no existe
-        errores.push(`${item.cliente} (${item.concepto}): la cuota ya estaba pagada o no existe`)
+        errores.push(motivoRechazoRegistro(item.cliente, item.concepto, r.value.error))
+      } else if (!r.value.data) {
+        // NULL = no se marcó: la cuota ya estaba pagada o el id no existe
+        errores.push(motivoRechazoRegistro(item.cliente, item.concepto, null))
       } else {
         aplicadas++
         idsAplicadas.push(item.cuota_id)
@@ -1354,12 +1335,17 @@ function abrirModalPago(cuota, contrato) {
   const dd = String(hoyLocal.getDate()).padStart(2, '0')
   document.getElementById('p_fecha').value = `${yyyy}-${mm}-${dd}`
   document.getElementById('p_monto').value = Number(cuota.monto_programado).toFixed(2)
+  // F5: la cuenta a la que se depositó (la de pago vigente del contrato); al confirmar se declara.
+  let cuentaDeposito = null
+  try { cuentaDeposito = cuentaParaCuota(contrato) } catch { cuentaDeposito = null }
+  MODAL_CCI_DEPOSITO = cuentaDeposito?.cci || null
   document.getElementById('p_resumen').innerHTML = `
     <strong>${escapeHtml(contrato.cliente || '—')}</strong><br>
     Contrato <span class="font-mono">${escapeHtml(contrato.numero_contrato || '—')}</span> ·
     ${concepto} ·
     A pagar el ${formatearFecha(cuota.fecha_programada)}<br>
-    Monto a pagar: <strong>${formatearMoneda(cuota.monto_programado, moneda)}</strong>
+    Monto a pagar: <strong>${formatearMoneda(cuota.monto_programado, moneda)}</strong><br>
+    Se depositó en: <strong>${escapeHtml(textoCuentaDeposito(cuentaDeposito))}</strong>
   `
   document.getElementById('modalPagoError').classList.add('hidden')
   document.getElementById('modalPago').classList.remove('hidden')
@@ -1368,6 +1354,7 @@ function abrirModalPago(cuota, contrato) {
 function cerrarModalPago() {
   document.getElementById('modalPago').classList.add('hidden')
   MODAL_CONTRATO_ID = null
+  MODAL_CCI_DEPOSITO = null
   MODAL_PROGRAMADO = 0
   MODAL_MONEDA = 'PEN'
 }
@@ -1447,17 +1434,13 @@ async function confirmarPago(e) {
       return
     }
     await verificarCuentasParaCuotas([{ contrato_id: contratoId, moneda }])
-    const { data: filasPagadas, error } = await supabase
-      .from('cronograma_pagos')
-      .update({
-        estado: 'pagado',
-        fecha_pago_real: fecha,
-        monto_pagado: monto,
-        registrado_por: session.user.id
-      })
-      .eq('id', id)
-      .eq('estado', 'pendiente')   // anti-carrera: no pisar una cuota ya pagada en otra pestaña/admin
-      .select('id')
+    // F5: se declara la cuenta que mostró el modal. Solo marca si sigue pendiente (anti-carrera:
+    // no pisar una cuota ya pagada en otra pestaña/admin); el servidor rechaza un CCI ajeno.
+    const cciDeclarado = MODAL_CCI_DEPOSITO
+    const { data: cuotaMarcada, error } = await supabase.schema('crm').rpc('registrar_pago_con_cuenta', {
+      p_cuota_id: id, p_fecha: fecha, p_monto: monto, p_cci: cciDeclarado,
+    })
+    const filasPagadas = cuotaMarcada ? [{ id: cuotaMarcada }] : []
 
     if (error) {
       errEl.textContent = error.message
```

## Qué te pido
1. ¿Puede alguien que no sea gestor de cartera marcar cuotas o elegir la cuenta sellada? ¿Puede
   fijarse `crm.cci_deposito` fuera de la RPC? ¿Se filtra entre transacciones o subtransacciones?
2. ¿La resolución por cliente+moneda+CCI puede escoger una cuenta de otro cliente, o aceptar una
   cuenta que nunca fue de pago del contrato? ¿La restricción (enlace actual ∪ historial de F3) es
   correcta y completa (p. ej. versión vieja enlazada, cuenta retirada por F4, contrato sin enlace)?
3. ¿Qué pasa si el trigger lanza 22023 (CCI ajeno) DESPUÉS del set_config: queda el ajuste sucio en
   esa transacción para PostgREST? ¿Y si el UPDATE afecta 0 filas (ya pagada) con un CCI ajeno?
4. Corrección de fecha_pago_real tras un pago declarado; anular y volver a pagar; pagos 'registro' e
   'inferido' anteriores: ¿alguno cambia de constancia indebidamente?
5. Portal: ¿la importación puede registrar una fila sin el CCI que traía el Excel (p. ej. celda
   convertida en número → sin declaración → dedución por fecha, justo el caso que F5 quiere evitar)?
   ¿El modal manual puede declarar una cuenta distinta de la que muestra? ¿Textos engañosos?
6. ¿Riesgos residuales bien acotados? ¿Falta algún test o mutante crítico?
Termina con VERDICT (PASS/BLOCK).
