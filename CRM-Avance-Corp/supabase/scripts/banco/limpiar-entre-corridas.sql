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
-- Llamadas del celular: el gate deja asignaciones cerradas que apuntan a crm.equipo. En replica la FK no se
-- comprueba: sin esto quedarían huérfanas (las llamadas y las intenciones ya cayeron con crm.leads). CASCADE
-- arrastra recepciones y estado de private.
do $llamadas$ begin
  if to_regclass('crm.celulares_asignaciones') is not null then
    truncate crm.celulares_asignaciones cascade;
  end if;
end $llamadas$;
delete from crm.equipo;
set local session_replication_role = default;
commit;

-- Punto 4 de la adenda: la sonda de domicilio exige arrancar con la columna vacia.
update public.perfiles set domicilio = null where rol = 'cliente';
