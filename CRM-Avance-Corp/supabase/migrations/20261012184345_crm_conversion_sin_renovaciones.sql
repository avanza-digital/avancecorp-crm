-- Miguel, 12/10/2026: las renovaciones NO suman conversión de analistas.
-- Rige desde octubre (abierto). Julio/septiembre y las fotos selladas conservan
-- su regla. Solo cambia el peso: operaciones, capital, atribución y el límite
-- de una primera operación elegible por cliente/mes permanecen iguales.
-- Todas las puertas leen private.peso_renovacion_conversion; no hay otra fórmula.
-- Ensayar en banco/rama antes de merge. Nunca aplicar directamente a producción.
-- Reversa: supabase/scripts/conversion-sin-renovaciones/reversa.sql, solo sin meses afectados sellados.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local search_path = '';

-- Impide cambiar pesos o sellar octubre entre el preflight y el cambio.
-- READ COMMITTED: el preflight toma su instantánea DESPUÉS de obtener los locks.
-- Mismo candado global de cerrar_periodo, ANTES de sus lecturas de pesos.
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table crm.conversion_pesos in access exclusive mode;
lock table crm.periodos_cerrados in share row exclusive mode;

do $preflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_attrdef d
      on d.adrelid=a.attrelid and d.adnum=a.attnum
    where a.attrelid='crm.conversion_pesos'::regclass and a.attname='peso_renovacion'
      and a.attnotnull and pg_catalog.pg_get_expr(d.adbin,d.adrelid)='0.15'
  ) then
    raise exception 'SIN RENOVACIONES: cambió el default o la nulabilidad del peso; revisar antes de aplicar'
      using errcode='P0409';
  end if;
  if exists (select 1 from crm.periodos_cerrados where periodo >= date '2026-10-01') then
    raise exception 'SIN RENOVACIONES: octubre o un mes posterior ya está sellado; no se reescribe el histórico'
      using errcode = 'P0409';
  end if;
  if (select count(*) from crm.conversion_pesos) <> 2
     or not exists (select 1 from crm.conversion_pesos
       where vigente_desde = date '2026-07-01' and peso_referido = 0.15
         and peso_renovacion = 0.15 and tope_referidos_pct is null)
     or not exists (select 1 from crm.conversion_pesos
       where vigente_desde = date '2026-10-01' and peso_referido = 1
         and peso_renovacion = 0.15 and tope_referidos_pct = 15 and nota is not null) then
    raise exception 'SIN RENOVACIONES: los pesos cambiaron desde el ensayo; revisar antes de aplicar'
      using errcode = 'P0409';
  end if;
  if private.peso_renovacion_conversion(date '2026-09-01') <> 0.15
     or private.peso_renovacion_conversion(date '2026-10-01') <> 0.15 then
    raise exception 'SIN RENOVACIONES: el lector del peso no coincide con la configuración'
      using errcode = 'P0409';
  end if;
end;
$preflight$;

-- Ya existe una versión para octubre por el tope de referidos. Se corrige SOLO
-- su peso de renovación, después de comprobar que ningún mes afectado se selló.
-- El trigger de auditoría existente conserva el antes y el después.
update crm.conversion_pesos
   set peso_renovacion = 0,
       nota = nota || E'\nMiguel 2026-10-12: desde octubre de 2026 las renovaciones aportan 0 a la conversión de analistas. Sustituye la mención anterior de renovación 0,15. Se conservan los meses anteriores, los registros e importes de cartera, el peso y tope del referido y la primera operación elegible por cliente/mes.'
 where vigente_desde = date '2026-10-01';

alter table crm.conversion_pesos alter column peso_renovacion set default 0;
alter table crm.conversion_pesos
  add constraint conversion_renovacion_cero_desde_octubre
  check (vigente_desde < date '2026-10-01' or peso_renovacion = 0);
comment on constraint conversion_renovacion_cero_desde_octubre on crm.conversion_pesos is
  'Miguel 12/10/2026: renovación no suma conversión desde octubre 2026. No puede reactivarse por omisión ni explícitamente; reactivarla exige otra migración. El histórico anterior conserva sus pesos.';

do $postflight$
begin
  if private.peso_renovacion_conversion(date '2026-09-01') is distinct from 0.15
     or private.peso_renovacion_conversion(date '2026-10-01') is distinct from 0
     or private.peso_renovacion_conversion(date '2027-01-01') is distinct from 0
     or private.peso_referido_conversion(date '2026-10-01') is distinct from 1
     or private.tope_referidos_conversion(date '2026-10-01') is distinct from 15 then
    raise exception 'SIN RENOVACIONES: postflight de pesos y tope no coincide';
  end if;
end;
$postflight$;
commit;
