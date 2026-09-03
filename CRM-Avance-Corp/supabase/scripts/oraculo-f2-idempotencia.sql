-- ORACULO F2 — SOLO en banco. Corre DESPUES de aplicar F2. Prueba IDEMPOTENCIA:
-- re-ejecutar el backfill NO crea nada nuevo (ni identidades, ni filas de mapa,
-- ni enlaces), y las invariantes siguen en pie. Hace ROLLBACK: no persiste.
begin;
do $ora$
declare
  n_inv_1 bigint; n_map_1 bigint; n_leads_1 bigint; n_cie_1 bigint; n_invers_1 bigint;
  n_inv_2 bigint; n_map_2 bigint; n_leads_2 bigint; n_cie_2 bigint; n_invers_2 bigint;
  v jsonb;
begin
  select count(*) into n_inv_1 from crm.inversionistas;
  select count(*) into n_map_1 from crm.backfill_multiempresa_mapa;
  select count(*) into n_leads_1 from crm.leads where inversionista_id is not null;
  select count(*) into n_cie_1 from crm.cierres_externos where inversionista_id is not null;
  select count(*) into n_invers_1 from crm.inversiones;

  -- Segunda pasada del backfill: debe ser inocua.
  v := private.backfill_multiempresa_ejecutar();

  select count(*) into n_inv_2 from crm.inversionistas;
  select count(*) into n_map_2 from crm.backfill_multiempresa_mapa;
  select count(*) into n_leads_2 from crm.leads where inversionista_id is not null;
  select count(*) into n_cie_2 from crm.cierres_externos where inversionista_id is not null;
  select count(*) into n_invers_2 from crm.inversiones;

  if n_inv_1<>n_inv_2 or n_map_1<>n_map_2 or n_leads_1<>n_leads_2 or n_cie_1<>n_cie_2 or n_invers_1<>n_invers_2 then
    raise exception 'ORACULO F2: la segunda pasada CAMBIO algo (inv %/%, mapa %/%, leads %/%, cierres %/%, inversiones %/%)',
      n_inv_1,n_inv_2, n_map_1,n_map_2, n_leads_1,n_leads_2, n_cie_1,n_cie_2, n_invers_1,n_invers_2;
  end if;

  -- Invariante de identidad: nadie con dos leads vivos ni dos canonicos.
  if exists (select inversionista_id from crm.leads where inversionista_id is not null group by inversionista_id having count(*)>1)
     or exists (select inversionista_id from crm.inversionista_leads where rol='canonico' group by inversionista_id having count(*)>1) then
    raise exception 'ORACULO F2: quedo una persona con mas de un lead vivo/canonico';
  end if;

  raise notice 'ORACULO F2 VERDE: backfill IDEMPOTENTE (2a pasada inocua: % identidades, % en mapa) e invariante de un-lead-por-persona en pie.', n_inv_2, n_map_2;
end
$ora$;
rollback;
