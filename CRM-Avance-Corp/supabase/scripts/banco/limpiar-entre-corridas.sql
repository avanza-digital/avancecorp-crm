-- Limpieza entre corridas del gate, punto 3 de supabase/scripts/LEEME-seed.md.
-- El seed NO es re-ejecutable a medias: sin esto, la segunda corrida se atasca.
-- Solo banco local.
begin;
set local session_replication_role = replica;  -- el ledger es append-only
truncate crm.actividades, crm.tareas, crm.lead_asignaciones, crm.leads cascade;
-- Bases cargadas (B7/B8): el gate deja bases y recibos (sin DELETE por diseño; los recibos rechazan TRUNCATE salvo en replica).
do $bases$ begin
  if to_regclass('crm.bases_carga') is not null then
    truncate crm.base_carga_operaciones, crm.base_carga_leads, crm.bases_carga;
  end if;
end $bases$;
delete from crm.equipo;
set local session_replication_role = default;
commit;

-- Punto 4 de la adenda: la sonda de domicilio exige arrancar con la columna vacia.
update public.perfiles set domicilio = null where rol = 'cliente';
