-- REEXPRESIÓN DE AGOSTO 2026 — reversa: dejar la foto EXACTAMENTE como el 10/09.
-- Solo si algo salió mal. Retira el sello/foto actuales de agosto (si los hay),
-- vuelve a insertar las 17 filas del respaldo y reactiva el ciclo diario.
-- Se ejecuta con: npx supabase db query --linked --file <este archivo>
begin;
set local lock_timeout = '10s';
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), (date '2026-08-01' - date '2000-01-01')::integer);

do $pre$
begin
  if to_regclass('private.respaldo_cierre_agosto_2026') is null
     or (select count(*) from private.respaldo_cierre_agosto_2026) <> 17 then
    raise exception 'PREFLIGHT: no existe el respaldo completo de agosto; no se puede restaurar';
  end if;
end $pre$;

alter table crm.cierre_mes_vendedor disable trigger trg_cierre_mes_vendedor_00_append_only;
alter table crm.periodos_cerrados   disable trigger trg_periodos_cerrados_00_append_only;

delete from crm.cierre_mes_vendedor where periodo = date '2026-08-01';
delete from crm.periodos_cerrados   where periodo = date '2026-08-01';

insert into crm.periodos_cerrados
  select (jsonb_populate_record(null::crm.periodos_cerrados, r.fila)).*
  from private.respaldo_cierre_agosto_2026 r where r.tabla = 'periodos_cerrados';
insert into crm.cierre_mes_vendedor
  select (jsonb_populate_record(null::crm.cierre_mes_vendedor, r.fila)).*
  from private.respaldo_cierre_agosto_2026 r where r.tabla = 'cierre_mes_vendedor';

alter table crm.cierre_mes_vendedor enable trigger trg_cierre_mes_vendedor_00_append_only;
alter table crm.periodos_cerrados   enable trigger trg_periodos_cerrados_00_append_only;

select cron.alter_job(job_id := 3, active := true);

do $post$
begin
  if (select count(*) from crm.periodos_cerrados where periodo = date '2026-08-01') <> 1
     or (select count(*) from crm.cierre_mes_vendedor where periodo = date '2026-08-01') <> 16 then
    raise exception 'POSTFLIGHT: la restauración no dejó 1 sello + 16 vendedores';
  end if;
  -- Igualdad fila a fila contra el respaldo.
  if exists (
    select 1 from private.respaldo_cierre_agosto_2026 r
    where r.tabla = 'cierre_mes_vendedor'
      and not exists (select 1 from crm.cierre_mes_vendedor f where to_jsonb(f) = r.fila)
  ) or exists (
    select 1 from private.respaldo_cierre_agosto_2026 r
    where r.tabla = 'periodos_cerrados'
      and not exists (select 1 from crm.periodos_cerrados pc where to_jsonb(pc) = r.fila)
  ) then
    raise exception 'POSTFLIGHT: alguna fila restaurada no es idéntica al respaldo';
  end if;
  raise notice 'AGOSTO 2026 RESTAURADO tal como estaba el 10/09. Ciclo diario reactivado.';
end $post$;
commit;
