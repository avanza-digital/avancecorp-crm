-- Retira únicamente el índice agregado por 20260925170437: el índice original
-- ya cubre auth_claim_id con el mismo predicado. Sin cambio funcional ni de datos.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $guard$
declare a pg_catalog.pg_index%rowtype; b pg_catalog.pg_index%rowtype;
begin
 select * into a from pg_catalog.pg_index where indexrelid='crm.inversion_solicitudes_auth_idx'::regclass;
 select * into b from pg_catalog.pg_index where indexrelid='crm.inversion_solicitudes_auth_claim_idx'::regclass;
 if not a.indisvalid or not a.indisready or a.indisunique or b.indisunique
   or a.indrelid is distinct from b.indrelid
   or a.indkey is distinct from b.indkey
   or a.indclass is distinct from b.indclass
   or a.indcollation is distinct from b.indcollation
   or a.indoption is distinct from b.indoption
   or pg_catalog.pg_get_expr(a.indpred,a.indrelid) is distinct from pg_catalog.pg_get_expr(b.indpred,b.indrelid)
   or pg_catalog.pg_get_expr(a.indexprs,a.indrelid) is distinct from pg_catalog.pg_get_expr(b.indexprs,b.indrelid) then
  raise exception 'Los índices dejaron de ser equivalentes; conservar ambos y revisar';
 end if;
end $guard$;
drop index crm.inversion_solicitudes_auth_claim_idx;
commit;
