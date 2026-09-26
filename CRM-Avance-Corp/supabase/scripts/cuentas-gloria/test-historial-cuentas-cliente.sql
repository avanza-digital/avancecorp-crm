-- PRUEBA del historial de cuentas (20260926193424_crm_historial_cuentas_cliente) — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra usuarios y cuentas FICTICIOS. Todo va en UNA transacción
-- que termina en ROLLBACK: no deja nada escrito.
--
-- Uso (banco local de Docker, con la migración ya aplicada):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-historial-cuentas-cliente.sql
--
-- Casos: admin y operaciones ven el historial; el analista de la cartera también; un analista
-- ajeno, el propio cliente y anon reciben 42501; solo salen cuentas retiradas y del cliente
-- pedido; orden por fecha de retiro; nombre de quién retiró (o NULL si no hay). N°, CCI y DNI
-- del beneficiario llegan COMPLETOS solo al admin; a Operaciones y al analista, tapados.
-- Mutantes: sin permisos, sin el filtro de retiradas y sin el tapado → los tres cazados.
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

-- ── Siembra ficticia (auth.uid() es NULL aquí: los candados de perfiles no actúan) ─────────
insert into auth.users (id, email, aud, role) values
  ('e7a10000-0000-4000-8000-000000000001', 'hist.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7a10000-0000-4000-8000-000000000002', 'hist.oper@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7a10000-0000-4000-8000-000000000003', 'hist.analista.a@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7a10000-0000-4000-8000-000000000004', 'hist.analista.b@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7a10000-0000-4000-8000-000000000005', 'hist.cliente.c@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7a10000-0000-4000-8000-000000000006', 'hist.cliente.d@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, dni, correo, rol, activo, asesor_perfil_id) values
  ('e7a10000-0000-4000-8000-000000000001', 'HIST ADMIN PRUEBA', '77700001', 'hist.admin@prueba.invalid', 'admin', true, null),
  ('e7a10000-0000-4000-8000-000000000002', 'HIST OPERACIONES PRUEBA', '77700002', 'hist.oper@prueba.invalid', 'operaciones', true, null),
  ('e7a10000-0000-4000-8000-000000000003', 'HIST ANALISTA A PRUEBA', '77700003', 'hist.analista.a@prueba.invalid', 'analista', true, null),
  ('e7a10000-0000-4000-8000-000000000004', 'HIST ANALISTA B PRUEBA', '77700004', 'hist.analista.b@prueba.invalid', 'analista', true, null),
  ('e7a10000-0000-4000-8000-000000000005', 'HIST CLIENTE C PRUEBA', '77700005', 'hist.cliente.c@prueba.invalid', 'cliente', true, 'e7a10000-0000-4000-8000-000000000003'),
  ('e7a10000-0000-4000-8000-000000000006', 'HIST CLIENTE D PRUEBA', '77700006', 'hist.cliente.d@prueba.invalid', 'cliente', true, 'e7a10000-0000-4000-8000-000000000003');

-- Cliente C: 1 vigente + 2 retiradas (una con autor, otra sin). Cliente D: 1 retirada.
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto,
   beneficiario_nombre, beneficiario_dni, activa, origen, creado_por, creado_en) values
  ('e7a1c000-0000-4000-8000-000000000001', 'e7a10000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros',
   '19100000000011', '00219100000000000011', false, null, null, true, 'contrato', null, '2026-09-20 10:00+00'),
  ('e7a1c000-0000-4000-8000-000000000002', 'e7a10000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros',
   '89830000000012', '00389800000000000012', true, 'ANA PRUEBA ROJAS', '40404040', true, 'contrato', null, '2026-09-01 10:00+00'),
  ('e7a1c000-0000-4000-8000-000000000003', 'e7a10000-0000-4000-8000-000000000005', 'USD', 'BBVA', 'corriente',
   '01100000000013', '01110000000000000013', false, null, null, true, 'perfil', null, '2026-08-01 10:00+00'),
  ('e7a1c000-0000-4000-8000-000000000004', 'e7a10000-0000-4000-8000-000000000006', 'PEN', 'BCP', 'ahorros',
   '1234', '00219100000000000014', false, null, null, true, 'contrato', null, '2026-08-15 10:00+00');
update crm.cuentas_bancarias set activa = false,
  desactivada_por = 'e7a10000-0000-4000-8000-000000000001', desactivada_en = '2026-09-25 15:00+00'
 where id = 'e7a1c000-0000-4000-8000-000000000002';
update crm.cuentas_bancarias set activa = false, desactivada_por = null, desactivada_en = '2026-08-10 15:00+00'
 where id = 'e7a1c000-0000-4000-8000-000000000003';
update crm.cuentas_bancarias set activa = false,
  desactivada_por = 'e7a10000-0000-4000-8000-000000000001', desactivada_en = '2026-09-24 15:00+00'
 where id = 'e7a1c000-0000-4000-8000-000000000004';

-- Utilidad de la prueba: cuántas filas de un cliente ve un usuario, o -1 si recibe el 42501
-- DEL GATE (mismo mensaje en todos los rechazos: sin oráculo de existencia). Un 42501 por
-- falta de GRANT tiene otro mensaje y hace fallar la prueba.
create function pg_temp.filas_de(p_uid uuid,
  p_cliente uuid default 'e7a10000-0000-4000-8000-000000000005') returns integer
language plpgsql as $f$
declare n integer; v_msg text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    select count(*) into n from crm.historial_cuentas_cliente_fn(p_cliente);
  exception when insufficient_privilege then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'Cliente no encontrado o fuera de tu cartera' then
      raise exception 'FALLO: 42501 con mensaje inesperado: %', v_msg;
    end if;
    n := -1;
  end;
  execute 'reset role';
  return n;
end;
$f$;

-- Utilidad: cómo ve un usuario N° / CCI / DNI de la cuenta retirada Interbank del cliente C.
create function pg_temp.datos_de(p_uid uuid) returns text
language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select h.numero_cuenta || '|' || h.cci || '|' || coalesce(h.beneficiario_dni, '-') into v
  from crm.historial_cuentas_cliente_fn('e7a10000-0000-4000-8000-000000000005') h
  where h.banco = 'Interbank';
  execute 'reset role';
  return v;
end;
$f$;

-- ── Casos ─────────────────────────────────────────────────────────────────────────────────
do $casos$
declare
  v_filas record;
  v_orden text;
begin
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000001') <> 2 then
    raise exception 'FALLO: admin debía ver 2 cuentas retiradas del cliente C';
  end if;
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000002') <> 2 then
    raise exception 'FALLO: operaciones (gestor de cartera) debía ver 2';
  end if;
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000003') <> 2 then
    raise exception 'FALLO: el analista de la cartera debía ver 2';
  end if;
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000004') <> -1 then
    raise exception 'FALLO: un analista AJENO debía recibir 42501';
  end if;
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000005') <> -1 then
    raise exception 'FALLO: el propio cliente debía recibir 42501';
  end if;
  raise notice 'OK permisos: admin 2 · operaciones 2 · analista de cartera 2 · analista ajeno 42501 · cliente 42501';

  -- Sin oráculo: inexistente, perfil que no es cliente, cliente inactivo y NULL → el mismo 42501.
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000003', 'e7a10000-0000-4000-8000-0000000000ff') <> -1
     or pg_temp.filas_de('e7a10000-0000-4000-8000-000000000003', 'e7a10000-0000-4000-8000-000000000004') <> -1
     or pg_temp.filas_de('e7a10000-0000-4000-8000-000000000003', null) <> -1 then
    raise exception 'FALLO: inexistente, no-cliente o NULL debían dar el mismo 42501';
  end if;
  -- Sin identidad: los candados de perfiles solo actúan con un usuario conectado.
  perform set_config('request.jwt.claims', '', true);
  update public.perfiles set activo = false where id = 'e7a10000-0000-4000-8000-000000000006';
  if (select activo from public.perfiles where id = 'e7a10000-0000-4000-8000-000000000006') then
    raise exception 'PRUEBA: no se pudo desactivar el cliente ficticio D';
  end if;
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000001', 'e7a10000-0000-4000-8000-000000000006') <> -1 then
    raise exception 'FALLO: un cliente inactivo debía dar 42501 incluso al admin';
  end if;
  perform set_config('request.jwt.claims', '', true);
  update public.perfiles set activo = true where id = 'e7a10000-0000-4000-8000-000000000006';
  raise notice 'OK sin oráculo: inexistente, no-cliente, inactivo y NULL → mismo 42501';

  -- Contenido y orden (como postgres, con la identidad del admin).
  perform set_config('request.jwt.claims',
    json_build_object('sub', 'e7a10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  select string_agg(h.banco || '/' || coalesce(h.desactivada_por_nombre, 'NULL'), ' > '
                    order by h.desactivada_en desc)
    into v_orden
  from crm.historial_cuentas_cliente_fn('e7a10000-0000-4000-8000-000000000005') h;
  if v_orden is distinct from 'Interbank/HIST ADMIN PRUEBA > BBVA/NULL' then
    raise exception 'FALLO: contenido u orden inesperado: %', v_orden;
  end if;
  select * into v_filas
  from crm.historial_cuentas_cliente_fn('e7a10000-0000-4000-8000-000000000005') h
  where h.banco = 'Interbank';
  if v_filas.numero_cuenta <> '89830000000012' or v_filas.cci <> '00389800000000000012'
     or v_filas.beneficiario_nombre <> 'ANA PRUEBA ROJAS' or v_filas.desactivada_en is null then
    raise exception 'FALLO: faltan datos de la cuenta retirada';
  end if;
  raise notice 'OK contenido: solo retiradas del cliente C, más reciente primero, con autor o NULL';

  if pg_temp.datos_de('e7a10000-0000-4000-8000-000000000001')
     is distinct from '89830000000012|00389800000000000012|40404040' then
    raise exception 'FALLO: el admin debía recibir N°, CCI y DNI completos';
  end if;
  if pg_temp.datos_de('e7a10000-0000-4000-8000-000000000002') is distinct from '••••0012|••••0012|-'
     or pg_temp.datos_de('e7a10000-0000-4000-8000-000000000003') is distinct from '••••0012|••••0012|-' then
    raise exception 'FALLO: Operaciones y el analista debían recibir N° y CCI tapados y sin DNI del beneficiario';
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', 'e7a10000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
  if exists (select 1 from crm.historial_cuentas_cliente_fn('e7a10000-0000-4000-8000-000000000005') h
             where h.beneficiario_nombre is not null) then
    raise exception 'FALLO: el nombre del beneficiario no debía llegar a quien no es admin';
  end if;
  -- Un N° corto (4 caracteres, cliente D) no sale entero: como mucho la mitad.
  perform set_config('request.jwt.claims',
    json_build_object('sub', 'e7a10000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
  if (select h.numero_cuenta from crm.historial_cuentas_cliente_fn('e7a10000-0000-4000-8000-000000000006') h)
     is distinct from '••••34' then
    raise exception 'FALLO: un N° corto debía salir como ••••34 para Operaciones';
  end if;
  raise notice 'OK tapado en servidor: admin completo · Operaciones y analista ••••+4 y sin beneficiario · N° corto ••••34';
end;
$casos$;

-- anon: sin EXECUTE.
set local role anon;
do $anon$
begin
  perform crm.historial_cuentas_cliente_fn('e7a10000-0000-4000-8000-000000000005');
  raise exception 'FALLO: anon pudo ejecutar el historial';
exception when insufficient_privilege then
  raise notice 'OK anon: 42501';
end;
$anon$;
reset role;

-- Cliente sin retiradas → 0 filas (se vacía el historial de C dentro de un savepoint).
savepoint sin_retiradas;
delete from crm.cuentas_bancarias
 where cliente_id = 'e7a10000-0000-4000-8000-000000000005' and activa is false;
do $vacio$
begin
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000001') <> 0 then
    raise exception 'FALLO: sin retiradas debía devolver 0 filas';
  end if;
  raise notice 'OK sin retiradas: 0 filas';
end;
$vacio$;
rollback to savepoint sin_retiradas;

-- ── Mutante 1: sin comprobación de permisos → el analista ajeno ya no recibe 42501 ─────────
savepoint mutante_permisos;
create or replace function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language plpgsql stable security definer set search_path to ''
as $m$
begin
  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta, cb.numero_cuenta, cb.cci, cb.titular_distinto,
         cb.beneficiario_nombre, cb.beneficiario_dni, cb.origen, cb.creado_en, cb.desactivada_en,
         pr.nombre_completo
  from crm.cuentas_bancarias cb left join public.perfiles pr on pr.id = cb.desactivada_por
  where cb.cliente_id = p_cliente_id and cb.activa is false;
end;
$m$;
do $m1$
begin
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000004') = -1 then
    raise exception 'MUTANTE 1 NO CAZADO: la prueba no distingue la falta de permisos';
  end if;
  raise notice 'OK mutante 1 cazado (sin permisos, el analista ajeno vería el historial)';
end;
$m1$;
rollback to savepoint mutante_permisos;

-- ── Mutante 2: sin el filtro de retiradas → el admin vería también la vigente (3) ─────────
savepoint mutante_filtro;
create or replace function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language plpgsql stable security definer set search_path to ''
as $m$
begin
  if not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501', message = 'x';
  end if;
  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta, cb.numero_cuenta, cb.cci, cb.titular_distinto,
         cb.beneficiario_nombre, cb.beneficiario_dni, cb.origen, cb.creado_en, cb.desactivada_en,
         pr.nombre_completo
  from crm.cuentas_bancarias cb left join public.perfiles pr on pr.id = cb.desactivada_por
  where cb.cliente_id = p_cliente_id;
end;
$m$;
do $m2$
begin
  if pg_temp.filas_de('e7a10000-0000-4000-8000-000000000001') = 2 then
    raise exception 'MUTANTE 2 NO CAZADO: la prueba no distingue vigentes de retiradas';
  end if;
  raise notice 'OK mutante 2 cazado (sin filtro, el admin vería también la vigente)';
end;
$m2$;
rollback to savepoint mutante_filtro;

-- ── Mutante 3: sin el tapado → Operaciones recibiría el N° completo ──────────────────────────
savepoint mutante_tapado;
create or replace function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language plpgsql stable security definer set search_path to ''
as $m$
begin
  if not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501', message = 'x';
  end if;
  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta, cb.numero_cuenta, cb.cci, cb.titular_distinto,
         cb.beneficiario_nombre, cb.beneficiario_dni, cb.origen, cb.creado_en, cb.desactivada_en,
         pr.nombre_completo
  from crm.cuentas_bancarias cb left join public.perfiles pr on pr.id = cb.desactivada_por
  where cb.cliente_id = p_cliente_id and cb.activa is false;
end;
$m$;
do $m3$
begin
  if pg_temp.datos_de('e7a10000-0000-4000-8000-000000000002') = '••••0012|••••0012|-' then
    raise exception 'MUTANTE 3 NO CAZADO: la prueba no distingue el tapado en servidor';
  end if;
  raise notice 'OK mutante 3 cazado (sin tapado, Operaciones recibiría los números completos)';
end;
$m3$;
rollback to savepoint mutante_tapado;

select 'HISTORIAL_OK' as veredicto;
rollback;
