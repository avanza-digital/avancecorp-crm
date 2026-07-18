-- Distribucion de leads por capital · paso 4B (contrato de escritura).
--
-- Requisito de rollout: el frontend que exige capital/moneda debe estar listo
-- antes de llevar esta migracion a produccion. En branch se valida primero.
-- Frontera: solo crm.leads; no modifica public ni el portal de clientes.

begin;

-- Congela el conjunto entre el guard y el cambio de contrato. Si hay una
-- escritura larga en curso, falla pronto y puede reintentarse sin dejar drift.
set local lock_timeout = '10s';
lock table crm.leads in access exclusive mode;

do $guard$
declare
  v_invalidos bigint;
begin
  select count(*)
    into v_invalidos
  from crm.leads
  where monto_estimado is null
     or monto_estimado <= 0
     or monto_estimado > 9999999999.99
     or monto_estimado <> trunc(monto_estimado, 2);

  if v_invalidos > 0 then
    raise exception
      'No se puede exigir capital estimado: existen % leads fuera del contrato',
      v_invalidos
      using errcode = '23514';
  end if;
end;
$guard$;

alter table crm.leads
  drop constraint leads_monto_estimado_check;

-- Quitar el typmod evita que PostgreSQL redondee ANTES del CHECK:
-- numeric(12,2) convertiria 5000.999 silenciosamente en 5001.00. El CHECK
-- equivalente conserva el mismo rango y rechaza la precision excedida.
alter table crm.leads
  alter column monto_estimado type numeric
  using monto_estimado::numeric;

alter table crm.leads
  add constraint leads_monto_estimado_valido
    check (
      monto_estimado > 0
      and monto_estimado <= 9999999999.99
      and monto_estimado = trunc(monto_estimado, 2)
    ) not valid;

alter table crm.leads
  validate constraint leads_monto_estimado_valido;

alter table crm.leads
  alter column monto_estimado set not null;

comment on column crm.leads.monto_estimado is
  'Capital que el lead estima invertir. Obligatorio, mayor que 0, maximo 9999999999.99 y hasta 2 decimales; clasificado siempre junto con moneda.';

commit;
