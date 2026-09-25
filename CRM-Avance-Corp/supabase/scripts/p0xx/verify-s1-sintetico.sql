-- Solo rama con seed-s1-clientes.sql + seed-s1-contratos.sql y S1 aplicado.
-- Prueba de integridad y permisos; no modifica datos.
begin;

do $verificar$
begin
  if (select count(*) from private.backfill_cuentas_p0xx
      where tipo = 'cuenta' and revertida_en is null) <> 3
     or (select count(*) from private.backfill_cuentas_p0xx
      where tipo = 'vinculo' and revertida_en is null) <> 2 then
    raise exception 'S1: conteos de backfill inesperados';
  end if;
  if (select count(*) from crm.contrato_cuentas_pago cp
      join public.contratos ct on ct.id = cp.contrato_id
      join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
      where ct.cliente_id <> cb.cliente_id or ct.moneda <> cb.moneda) <> 0 then
    raise exception 'S1: vinculo incoherente';
  end if;
  if (select count(*) from public.contratos ct
      where ct.estado = 'activo' and not exists (
        select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = ct.id)) <> 3 then
    raise exception 'S1: contratos sin vinculo inesperados';
  end if;
  if (select count(*) from private.conciliacion_cuentas_p0xx
      where clase = 'contrato' and motivo in
        ('cuentas_ambiguas', 'perfil_conflictivo', 'sin_cuenta')) <> 3 then
    raise exception 'S1: reporte de conciliacion incompleto';
  end if;
  if (select count(*) from private.conciliacion_cuentas_p0xx
      where clase = 'perfil' and motivo = 'varias_activas'
        and cliente_id = 'c0000000-0000-4000-8000-000000000006') <> 1
     or (select count(*) from crm.cuentas_bancarias
      where cliente_id = 'c0000000-0000-4000-8000-000000000006'
        and moneda = 'PEN' and activa) <> 2 then
    raise exception 'S1: CCI distintos no conservaron ambas cuentas';
  end if;
  if (select count(*) from private.conciliacion_cuentas_p0xx
      where clase = 'perfil' and motivo = 'mismo_cci_datos_distintos'
        and cliente_id = 'c0000000-0000-4000-8000-000000000007') <> 1
     or (select count(*) from crm.cuentas_bancarias
      where cliente_id = 'c0000000-0000-4000-8000-000000000007'
        and moneda = 'PEN' and activa) <> 1 then
    raise exception 'S1: conflicto de mismo CCI no fue aislado';
  end if;
  if (select count(*) from crm.cuentas_bancarias cb
      join public.perfiles p on p.id = cb.cliente_id
      where p.id = 'c0000000-0000-4000-8000-000000000001'
        and cb.activa and cb.origen = 'perfil'
        and ((cb.moneda = 'PEN' and cb.banco = p.banco
              and cb.numero_cuenta = p.numero_cuenta and cb.cci = p.cci)
          or (cb.moneda = 'USD' and cb.banco = p.banco_usd
              and cb.numero_cuenta = p.numero_cuenta_usd
              and cb.cci = p.cci_usd))) <> 2 then
    raise exception 'S1: perfil valido sin equivalente';
  end if;
  if pg_catalog.has_table_privilege('authenticated',
      'crm.cuentas_bancarias', 'SELECT')
     or pg_catalog.has_function_privilege('authenticated',
       'private.cuentas_cliente_vigentes(uuid)', 'EXECUTE') then
    raise exception 'S1: acceso directo bancario habilitado';
  end if;
  if exists (
    select 1 from public.audit_log a
    where a.tabla in ('perfiles', 'crm.cuentas_bancarias')
      and coalesce(
        a.data_antes->>'numero_cuenta', a.data_despues->>'numero_cuenta',
        a.data_antes->>'numero_cuenta_usd',
        a.data_despues->>'numero_cuenta_usd',
        a.data_antes->>'cci', a.data_despues->>'cci',
        a.data_antes->>'cci_usd', a.data_despues->>'cci_usd',
        a.data_antes->>'beneficiario_dni',
        a.data_despues->>'beneficiario_dni',
        a.data_antes->>'beneficiario_dni_usd',
        a.data_despues->>'beneficiario_dni_usd') is not null
  ) then
    raise exception 'S1: auditoria nueva contiene datos bancarios';
  end if;
end;
$verificar$;

set local role authenticated;
set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000002';
do $verificar$
declare
  v_detalle record;
begin
  select * into v_detalle
  from crm.cliente_detalle_fn('c0000000-0000-4000-8000-000000000005');
  if not found or not v_detalle.banca_visible
     or v_detalle.banco <> 'BCP' or v_detalle.banco_usd <> 'BCP'
     or pg_catalog.right(v_detalle.numero_cuenta, 4) <> '6087'
     or pg_catalog.right(v_detalle.numero_cuenta_usd, 4) <> '9168' then
    raise exception 'S1: ficha del testigo no refleja las cuentas CRM';
  end if;
  if (select count(*) from crm.cuentas_bancarias_cliente_fn(
      'c0000000-0000-4000-8000-000000000005', 'PEN')) <> 1 then
    raise exception 'S1: wrapper bancario no devuelve la cuenta vigente';
  end if;
end;
$verificar$;

set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000004';
do $verificar$
begin
  begin
    perform * from crm.cuentas_bancarias_cliente_fn(
      'c0000000-0000-4000-8000-000000000005', 'PEN');
    raise exception 'S1: vendedor fuera de cartera accedio a cuentas';
  exception when insufficient_privilege then
    null;
  end;
  if exists (
    select 1 from crm.cliente_detalle_fn(
      'c0000000-0000-4000-8000-000000000005')
    where banca_visible or cuentas_bancarias_visibles
       or numero_cuenta is not null or cci is not null
       or numero_cuenta_usd is not null or cci_usd is not null
  ) then
    raise exception 'S1: ficha expone banca fuera de cartera';
  end if;
end;
$verificar$;

rollback;
