-- Reversión de 20261019213516_crm_citas_clientes_proyeccion.sql (ensayada en el
-- banco Docker el 19/10/2026). Retira la puerta y el núcleo del lector de reuniones
-- con clientes de la Proyección. No toca tablas, datos, policies ni ningún otro
-- lector. Antes de correrla, el front no debe llamar a
-- crm.citas_clientes_proyeccion_fn (si lo hace, esa llamada pasará a PGRST202).
-- Un solo mensaje:
--   supabase db query --linked --file supabase/scripts/revertir-20261019213516-citas-clientes-proyeccion.sql
-- y, si la migración ya estaba registrada:
--   supabase migration repair --status reverted 20261019213516 --linked
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello,
  private.analista_vigencia_exenciones in share mode;

create temporary table cc_proy_rev_censo_antes on commit drop as
  select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
  from private.contadores_crudos_leads_citas() c
  union all
  select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
  from private.puertas_analista_sin_vigencia() v;

do $preflight$
begin
  if pg_catalog.to_regprocedure('private.citas_clientes_proyeccion(date,date)') is null
     or pg_catalog.to_regprocedure('crm.citas_clientes_proyeccion_fn(date,date)') is null then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: falta alguna de las dos funciones; nada coherente que revertir';
  end if;
  -- Nada más en la base puede depender del lector (pg_depend sólo ve vistas y
  -- defaults; las llamadas desde otras funciones se buscan en el cuerpo).
  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and p.oid not in ('private.citas_clientes_proyeccion(date,date)'::regprocedure,
                        'crm.citas_clientes_proyeccion_fn(date,date)'::regprocedure)
      and pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'citas_clientes_proyeccion') > 0
  ) then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: otra función de la base llama al lector; retirarla primero';
  end if;
end;
$preflight$;

drop function crm.citas_clientes_proyeccion_fn(date,date);
drop function private.citas_clientes_proyeccion(date,date);

do $postflight$
begin
  if pg_catalog.to_regprocedure('private.citas_clientes_proyeccion(date,date)') is not null
     or pg_catalog.to_regprocedure('crm.citas_clientes_proyeccion_fn(date,date)') is not null then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: alguna función sigue existiendo';
  end if;
end;
$postflight$;

-- Los dos censos quedan EXACTAMENTE como estaban.
do $censo$
begin
  create temporary table cc_proy_rev_censo_despues on commit drop as
    select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
    from private.contadores_crudos_leads_citas() c
    union all
    select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
    from private.puertas_analista_sin_vigencia() v;
  if exists ((select * from cc_proy_rev_censo_antes except all select * from cc_proy_rev_censo_despues)
             union all
             (select * from cc_proy_rev_censo_despues except all select * from cc_proy_rev_censo_antes)) then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: cambió un censo (analítico o de vigencia)';
  end if;
end;
$censo$;

notify pgrst, 'reload schema';
commit;
