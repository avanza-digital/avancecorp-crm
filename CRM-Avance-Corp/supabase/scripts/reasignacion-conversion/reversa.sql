-- Retira solo la sincronización automática. Conserva todos los datos e historiales.
begin;
set local lock_timeout='5s';
drop trigger if exists trg_leads_zzzz_conversion_responsable on crm.leads;
drop function if exists private.trg_leads_sincronizar_conversion();
commit;
