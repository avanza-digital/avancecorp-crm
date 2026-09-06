-- ============================================================================
-- REVERSA de F2.b [D-15] (20260906150000): suelta crm.reabrir_lead_fn y desregistra la versión. Repetible dos veces.
-- Antes de revertir, publicar un front que vuelva al UPDATE directo (o el botón «Reabrir» responderá PGRST202 → «No se pudo
-- guardar el cambio» hasta que vuelva la puerta). Con la bandera encendida ese UPDATE directo lo cierra D-13.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d15_reabrir_lead_por_puerta'));
do $pre$
begin
  -- No se suelta a ciegas: solo la puerta que genera gen-d15.py (cuerpo 65b4b092…). Otro cuerpo = otra versión: revisar antes.
  if exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.reabrir_lead_fn(uuid)') and md5(p.prosrc) <> '65b4b0924da38eaa2c6b7dc42f44ee79')
     or exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.editar_lead_fn(uuid,jsonb)') and md5(p.prosrc) <> '55224774b94c1d429f1b0d52a185a303') then
    raise exception 'REVERSA D-15: alguna puerta viva no tiene el cuerpo de gen-d15.py (65b4b092… / 55224774…); no se suelta a ciegas';
  end if;
end
$pre$;
drop function if exists crm.reabrir_lead_fn(uuid);
drop function if exists crm.editar_lead_fn(uuid, jsonb);
do $post$
begin
  if to_regprocedure('crm.reabrir_lead_fn(uuid)') is not null or to_regprocedure('crm.editar_lead_fn(uuid,jsonb)') is not null then
    raise exception 'REVERSA D-15: alguna puerta sigue existiendo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906150000';
  raise notice 'REVERSA F2.b D-15 OK (versión 20260906150000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
