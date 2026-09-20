-- REEXPRESIÓN DE AGOSTO 2026 — paso 1: reabrir el mes.
-- Pedido por Miguel el 17/09/2026: hay contratos de agosto sin cargar y el sello
-- del 10/09 los rechaza. Es SOLO por agosto (desde septiembre se carga a tiempo).
-- Qué hace, en una transacción: guarda la foto en private.respaldo_cierre_agosto_2026,
-- retira el sello y la foto, y PAUSA el ciclo diario para que nadie vuelva a sellar
-- hasta que los analistas terminen. Reversa: 03-restaurar.sql · cierre: 02-resellar.sql.
-- Ensayado en producción el 17/09 dentro de un DO revertido: respaldo 17 filas,
-- sello 0, foto 0, ciclo en pausa, agosto sin bloqueo.
-- Se ejecuta con: npx supabase db query --linked --file <este archivo>
begin;
set local lock_timeout = '10s';

-- Mismos candados que usan el sello y el trigger de altas de contratos.
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), (date '2026-08-01' - date '2000-01-01')::integer);

do $pre$
begin
  if (select count(*) from crm.periodos_cerrados) <> 1
     or not exists (select 1 from crm.periodos_cerrados where periodo = date '2026-08-01') then
    raise exception 'PREFLIGHT: agosto 2026 no es el único mes sellado; revisar antes de reabrir';
  end if;
  if (select count(*) from crm.cierre_mes_vendedor where periodo = date '2026-08-01') <> 16 then
    raise exception 'PREFLIGHT: la foto de agosto no tiene 16 filas (medido el 17/09)';
  end if;
  if (select count(*) from crm.ajustes_mes_cerrado) <> 0
     or (select count(*) from crm.inversion_ajustes_mes_cerrado) <> 0 then
    raise exception 'PREFLIGHT: hay ajustes derivados de un mes sellado; no reabrir sin plan';
  end if;
  -- Re-ejecutable: si el respaldo ya existe (agosto se reabrió y se reselló antes de
  -- cargar, 17/09 15:55→15:56), se conserva la foto ORIGINAL del 10/09 y no se pisa.
  if to_regclass('private.respaldo_cierre_agosto_2026') is not null
     and (select count(*) from private.respaldo_cierre_agosto_2026) <> 17 then
    raise exception 'PREFLIGHT: existe un respaldo incompleto (<> 17 filas); revisar antes de reabrir';
  end if;
  if not exists (select 1 from cron.job where jobid = 3 and jobname = 'crm-cierre-mes-diario' and active) then
    raise exception 'PREFLIGHT: el ciclo diario no es el job 3 activo; revisar';
  end if;
end $pre$;

-- 1. Copia íntegra de lo que se va a retirar (también hay copia local en
--    releases/respaldo-cierre-agosto-2026-09-17.json).
do $respaldo$
begin
  if to_regclass('private.respaldo_cierre_agosto_2026') is not null then
    raise notice 'Respaldo ya existente (foto del 10/09): se conserva tal cual.';
    return;
  end if;
  create table private.respaldo_cierre_agosto_2026 as
    select 'periodos_cerrados'::text as tabla, to_jsonb(pc) as fila, now() as guardado_en
      from crm.periodos_cerrados pc where pc.periodo = date '2026-08-01'
    union all
    select 'cierre_mes_vendedor', to_jsonb(f), now()
      from crm.cierre_mes_vendedor f where f.periodo = date '2026-08-01';
  revoke all on private.respaldo_cierre_agosto_2026 from public, anon, authenticated;
  comment on table private.respaldo_cierre_agosto_2026 is
    'Foto del cierre de agosto 2026 tal como estaba antes de reabrirlo el 17/09/2026 para cargar contratos atrasados. Se restaura con 03-restaurar.sql.';
end $respaldo$;

-- 2. El candado «un mes cerrado no se edita ni se borra» se levanta SOLO aquí,
--    dentro de la transacción, para esta reexpresión autorizada. Los triggers de
--    auditoría siguen activos: cada fila retirada queda en el audit_log.
alter table crm.cierre_mes_vendedor disable trigger trg_cierre_mes_vendedor_00_append_only;
alter table crm.periodos_cerrados   disable trigger trg_periodos_cerrados_00_append_only;

delete from crm.cierre_mes_vendedor where periodo = date '2026-08-01';
delete from crm.periodos_cerrados   where periodo = date '2026-08-01';

alter table crm.cierre_mes_vendedor enable trigger trg_cierre_mes_vendedor_00_append_only;
alter table crm.periodos_cerrados   enable trigger trg_periodos_cerrados_00_append_only;

-- 3. Nadie vuelve a sellar agosto hasta que los analistas terminen de cargar.
select cron.alter_job(job_id := 3, active := false);

do $post$
begin
  if exists (select 1 from crm.periodos_cerrados where periodo = date '2026-08-01')
     or exists (select 1 from crm.cierre_mes_vendedor where periodo = date '2026-08-01') then
    raise exception 'POSTFLIGHT: agosto sigue sellado';
  end if;
  if (select count(*) from private.respaldo_cierre_agosto_2026) <> 17 then
    raise exception 'POSTFLIGHT: el respaldo no tiene 17 filas (1 sello + 16 vendedores)';
  end if;
  if (select active from cron.job where jobid = 3) then
    raise exception 'POSTFLIGHT: el ciclo diario sigue activo';
  end if;
  if exists (
    select 1 from pg_trigger
    where tgname in ('trg_cierre_mes_vendedor_00_append_only', 'trg_periodos_cerrados_00_append_only')
      and tgenabled = 'D'
  ) then
    raise exception 'POSTFLIGHT: un candado append-only quedó apagado';
  end if;
  raise notice 'AGOSTO 2026 REABIERTO: ya se pueden cargar contratos con fecha de agosto. Ciclo diario en pausa.';
end $post$;
commit;
