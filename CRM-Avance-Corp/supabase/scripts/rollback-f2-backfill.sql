-- Reversa de F2 (backfill). Deshace TODO lo que el backfill creo: nula los
-- enlaces, borra inversiones externas + titulares, el puente de leads, el ledger
-- de responsables, los identificadores y las identidades, y suelta el mapa y la
-- funcion. NO toca dinero (contratos/cierres/operaciones intactos).
-- Aborta si F3+ ya esta activo (banderas encendidas) o si hay identidades que no
-- vienen del backfill (creadas por otra via): en ese caso, revertir esa fase antes.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_backfill'));

do $g$
begin
  if to_regclass('crm.multiempresa_flags') is not null
     and exists (select 1 from crm.multiempresa_flags where activo) then
    raise exception 'REVERSA F2: hay banderas ENCENDIDAS (F3+ activo): revertir esa fase primero';
  end if;
  if to_regclass('crm.backfill_multiempresa_mapa') is null then
    raise exception 'REVERSA F2: no existe el mapa (F2 no aplicada o ya revertida)';
  end if;
  if exists (
    select 1 from crm.inversionistas i
    where not exists (select 1 from crm.backfill_multiempresa_mapa m where m.inversionista_id = i.id)
  ) then
    raise exception 'REVERSA F2: hay identidades que NO vienen del backfill (creadas por otra via): revertir esa fase antes';
  end if;
  -- Valvula: nula los enlaces protegidos (trigger de F1 y de inmutabilidad del cierre).
  perform pg_catalog.set_config('crm.op_privilegiada','on', true);
end
$g$;

update crm.leads            set inversionista_id = null where inversionista_id is not null;
update crm.cierres_externos set inversionista_id = null where inversionista_id is not null;

delete from crm.inversion_titulares;
delete from crm.inversiones;
delete from crm.inversionista_leads;
delete from crm.inversionista_responsables;
delete from crm.inversionista_fusiones;
delete from crm.inversionista_identificadores;
delete from crm.inversionistas;

drop function if exists private.backfill_multiempresa_ejecutar();
drop table if exists crm.backfill_multiempresa_mapa;

do $post$
begin
  if (select count(*) from crm.inversionistas) <> 0
     or (select count(*) from crm.inversionista_identificadores) <> 0
     or (select count(*) from crm.inversiones) <> 0
     or (select count(*) from crm.leads where inversionista_id is not null) <> 0
     or (select count(*) from crm.cierres_externos where inversionista_id is not null) <> 0
     or to_regclass('crm.backfill_multiempresa_mapa') is not null then
    raise exception 'REVERSA F2: quedo residuo del backfill';
  end if;
  raise notice 'REVERSA F2 OK: backfill retirado; identidad vacia, enlaces nulos, dinero intacto.';
end
$post$;
commit;
