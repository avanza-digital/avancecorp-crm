-- Reconciliación as-built: crm.actividades_del_ambito_fn
--
-- F0 del plan de escalabilidad (vault: «Plan de escalabilidad del CRM a data
-- gigante», 2026-08-08). Esta función vive en producción desde el ciclo de
-- automatismos comerciales pero NUNCA quedó versionada en el repo (drift
-- documentado en MIGRACIONES.md). Regla del proyecto: prohibido modificar una
-- función no versionada — esta migración la reproduce EXACTA (definición
-- extraída con pg_get_functiondef el 2026-08-08; ACL real:
-- {postgres=X/postgres,authenticated=X/postgres}) para que la migración
-- siguiente (ventana + límite) parta de una base fiel.
--
-- ⚠️ As-built fiel, NO canónica: conserva su search_path legacy
-- ('private','public','crm') y la ausencia de guardia 42501 (el scoping vive
-- en el WHERE). La modernización, si toca, será en F1/F4 — no aquí. En prod
-- este CREATE OR REPLACE es un no-op byte a byte; en un branch nuevo la crea.
--
-- No toca tablas, policies, grants de tablas ni objetos de `public`.

begin;

set local lock_timeout = '10s';

create or replace function crm.actividades_del_ambito_fn()
 returns table(id uuid, lead_id uuid, tipo text, detalle text, autor_nombre text, creado_en timestamp with time zone)
 language sql
 stable security definer
 set search_path to 'private', 'public', 'crm'
as $function$
  select a.id, a.lead_id, a.tipo, a.detalle,
         coalesce(p.nombre_completo, '—') as autor_nombre, a.creado_en
  from crm.actividades a
  left join public.perfiles p on p.id = a.creado_por
  where exists (
    select 1 from crm.leads l
    where l.id = a.lead_id
      and (
        (l.activo = true and (
          l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
          or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))
          or (select private.rol_crm((select auth.uid()))) = 'gerencia'
        ))
        or (select private.es_lector_global())
      )
  );
$function$;

comment on function crm.actividades_del_ambito_fn() is
  'Timeline de actividades del ámbito visible (RLS espejo en WHERE). As-built reconciliada 2026-08-08; sin ventana ni límite hasta la migración siguiente.';

-- Reproduce el ACL real de producción (idempotente allí).
revoke all on function crm.actividades_del_ambito_fn() from public, anon, service_role;
grant execute on function crm.actividades_del_ambito_fn() to authenticated;

commit;
