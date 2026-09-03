-- ORACULO F2 IDEMPOTENCIA — SOLO en banco. Corre DESPUES de aplicar F2. Prueba
-- que re-ejecutar el backfill es REALMENTE inocuo: ni cuenta, ni actualizado_en,
-- ni filas de auditoria del mapa cambian. Hace ROLLBACK (no persiste).
begin;
do $ora$
declare
  n_inv_1 bigint; n_map_1 bigint; n_leads_1 bigint; n_cie_1 bigint; n_invers_1 bigint;
  n_inv_2 bigint; n_map_2 bigint; n_leads_2 bigint; n_cie_2 bigint; n_invers_2 bigint;
  t_act_1 timestamptz; t_act_2 timestamptz; n_aud_1 bigint; n_aud_2 bigint; v jsonb;
begin
  select count(*), max(actualizado_en) into n_map_1, t_act_1 from crm.backfill_multiempresa_mapa;
  select count(*) into n_inv_1 from crm.inversionistas;
  select count(*) into n_leads_1 from crm.leads where inversionista_id is not null;
  select count(*) into n_cie_1 from crm.cierres_externos where inversionista_id is not null;
  select count(*) into n_invers_1 from crm.inversiones;
  select count(*) into n_aud_1 from public.audit_log where tabla='crm.backfill_multiempresa_mapa';

  v := private.backfill_multiempresa_ejecutar();   -- segunda pasada

  select count(*), max(actualizado_en) into n_map_2, t_act_2 from crm.backfill_multiempresa_mapa;
  select count(*) into n_inv_2 from crm.inversionistas;
  select count(*) into n_leads_2 from crm.leads where inversionista_id is not null;
  select count(*) into n_cie_2 from crm.cierres_externos where inversionista_id is not null;
  select count(*) into n_invers_2 from crm.inversiones;
  select count(*) into n_aud_2 from public.audit_log where tabla='crm.backfill_multiempresa_mapa';

  if n_inv_1<>n_inv_2 or n_map_1<>n_map_2 or n_leads_1<>n_leads_2 or n_cie_1<>n_cie_2 or n_invers_1<>n_invers_2 then
    raise exception 'ORACULO F2: la 2a pasada cambio conteos (inv %/%, mapa %/%, leads %/%, cierres %/%, inversiones %/%)',
      n_inv_1,n_inv_2, n_map_1,n_map_2, n_leads_1,n_leads_2, n_cie_1,n_cie_2, n_invers_1,n_invers_2;
  end if;
  if t_act_1 is distinct from t_act_2 or n_aud_1 <> n_aud_2 then
    raise exception 'ORACULO F2: la 2a pasada MOVIO el mapa (actualizado_en % -> %, auditoria % -> %) — no es inocua', t_act_1, t_act_2, n_aud_1, n_aud_2;
  end if;
  if exists (select inversionista_id from crm.leads where inversionista_id is not null group by inversionista_id having count(*)>1)
     or exists (select inversionista_id from crm.inversionista_leads where rol='canonico' group by inversionista_id having count(*)>1) then
    raise exception 'ORACULO F2: quedo una persona con mas de un lead vivo/canonico';
  end if;

  raise notice 'ORACULO F2 VERDE: backfill IDEMPOTENTE de verdad (2a pasada sin cambios de conteo, actualizado_en ni auditoria; % identidades).', n_inv_2;
end
$ora$;
rollback;
