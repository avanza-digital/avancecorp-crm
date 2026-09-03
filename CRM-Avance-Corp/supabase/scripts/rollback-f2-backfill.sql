-- Reversa de F2 (backfill). Deshace TODO lo que el backfill creo, sin tocar
-- dinero (contratos/cierres/operaciones intactos). Aborta si F3+ activo o si hay
-- identidades AJENAS al backfill (por procedencia: su identificador no es 'backfill-%').
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
  -- Procedencia: toda identidad debe venir del backfill. Si alguna tiene un
  -- identificador con fuente distinta de 'backfill-%' (creada por otra via/fase),
  -- NO se revierte a ciegas.
  if exists (
    select 1 from crm.inversionista_identificadores d
    where d.fuente is null or d.fuente not like 'backfill-%'
  ) then
    raise exception 'REVERSA F2: hay identidades que NO vienen del backfill (fuente distinta): revertir esa fase antes';
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

-- El mapa referencia inversionistas por FK: soltarlo ANTES de borrar identidades.
drop table if exists crm.backfill_multiempresa_mapa;

delete from crm.inversionistas;

drop function if exists private.backfill_multiempresa_ejecutar();
drop function if exists private.f2_mapear(text,uuid,uuid,text,text,text);

do $post$
begin
  if (select count(*) from crm.inversionistas) <> 0
     or (select count(*) from crm.inversionista_identificadores) <> 0
     or (select count(*) from crm.inversiones) <> 0
     or (select count(*) from crm.inversion_titulares) <> 0
     or (select count(*) from crm.inversionista_leads) <> 0
     or (select count(*) from crm.inversionista_responsables) <> 0
     or (select count(*) from crm.leads where inversionista_id is not null) <> 0
     or (select count(*) from crm.cierres_externos where inversionista_id is not null) <> 0
     or to_regclass('crm.backfill_multiempresa_mapa') is not null
     or to_regprocedure('private.backfill_multiempresa_ejecutar()') is not null then
    raise exception 'REVERSA F2: quedo residuo del backfill';
  end if;
  raise notice 'REVERSA F2 OK: backfill retirado; identidad vacia, enlaces nulos, dinero intacto.';
end
$post$;
commit;
