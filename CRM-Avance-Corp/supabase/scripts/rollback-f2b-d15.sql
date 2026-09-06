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
  -- No se suelta a ciegas: solo la puerta que genera gen-d15.py (cuerpo 704fecf9…). Otro cuerpo = otra versión: revisar antes.
  if exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.reabrir_lead_fn(uuid)') and md5(p.prosrc) <> '704fecf995c0300d2dc2ef064c6d6490') then
    raise exception 'REVERSA D-15: la puerta viva no tiene el cuerpo de gen-d15.py (704fecf9…); no se suelta a ciegas';
  end if;
end
$pre$;
drop function if exists crm.reabrir_lead_fn(uuid);
do $post$
begin
  if to_regprocedure('crm.reabrir_lead_fn(uuid)') is not null then
    raise exception 'REVERSA D-15: la puerta sigue existiendo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906150000';
  raise notice 'REVERSA F2.b D-15 OK (versión 20260906150000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
