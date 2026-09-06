-- ============================================================================
-- REVERSA de F2.b [D-4] (20260906130000): suelta crm.importar_lead_fn y desregistra la versión. Repetible dos veces.
-- Antes de revertir, devolver el edge crm-importar-leads a la versión que INSERTA directo (fase 2 deshecha): con el edge de
-- fase 2 vivo y la puerta ausente, cada fila del lote responde «ERROR temporal» (PGRST202/42883 → se reintenta, no se
-- congela como rechazo) hasta que vuelva el edge o la puerta.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d4_importador_por_puerta'));
drop function if exists crm.importar_lead_fn(jsonb);
do $post$
begin
  if to_regprocedure('crm.importar_lead_fn(jsonb)') is not null then
    raise exception 'REVERSA D-4: la puerta sigue existiendo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906130000';
  raise notice 'REVERSA F2.b D-4 OK (versión 20260906130000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
