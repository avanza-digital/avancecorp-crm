-- Ventana temporal + límite en crm.actividades_del_ambito_fn
--
-- F0 del plan de escalabilidad (vault: «Plan de escalabilidad del CRM a data
-- gigante», 2026-08-08). Era la ÚNICA lectura del CRM sin techo: ni LIMIT ni
-- ventana, y gerencia (ámbito global por rol) se descargaba el timeline entero
-- de la empresa en cada arranque. Actividades es la tabla que más crece
-- (~10x leads).
--
-- Cambios sobre el as-built (20260808163618), scoping intacto:
--   1. Ventana: solo actividades con creado_en >= now() - 365 días.
--      Tope de SEGURIDAD, hoy invisible (el CRM arrancó 2026-07: no hay
--      actividad más vieja). La ventana OPERATIVA (90 días) es de F4, cuando
--      existan sus compensaciones (timeline por lead bajo demanda,
--      etapa_iniciada_en del servidor).
--   2. limit 10000 con orden determinista (creado_en desc, id asc): si la
--      ventana igual desbordara, sobreviven las MÁS RECIENTES — la señal
--      operativa (cola, cadencia, alertas) usa la última actividad por lead,
--      así que el recorte muerde primero lo inerte. El front compara el largo
--      de la respuesta contra 10000 y avisa a Sentry (alarma de topes, F0).
--
-- El ORDER BY es novedad deliberada: sin él, un LIMIT recortaría filas
-- arbitrarias. Los consumidores no dependían del orden (agrupan por lead).
--
-- Firma y tipo de retorno idénticos → create or replace válido, cero cambio
-- de contrato para el front (database.types.ts no cambia). Servidor primero
-- es seguro: quita filas que hoy no existen (ventana > edad del dato).
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
  where a.creado_en >= now() - interval '365 days'
    and exists (
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
    )
  order by a.creado_en desc, a.id asc
  limit 10000;
$function$;

comment on function crm.actividades_del_ambito_fn() is
  'Timeline de actividades del ámbito visible (RLS espejo en WHERE). Ventana de seguridad 365 días + limit 10000 (más recientes primero) desde 2026-08-08; la ventana operativa de 90 días llega en F4 del plan de escalabilidad.';

-- create or replace conserva el ACL, pero se reafirma por si esta migración
-- corre en un branch donde la función nace aquí.
revoke all on function crm.actividades_del_ambito_fn() from public, anon, service_role;
grant execute on function crm.actividades_del_ambito_fn() to authenticated;

-- Índice que sirve el ORDER BY + LIMIT de arriba (recorrido newest-first con
-- corte temprano). El existente idx_actividades_lead (lead_id, creado_en desc)
-- sirve el timeline POR LEAD, no este barrido global. Tabla hoy con 0 filas:
-- create index normal (sin concurrently) es instantáneo.
create index actividades_recientes_idx
  on crm.actividades (creado_en desc, id);

comment on index crm.actividades_recientes_idx is
  'Barrido global newest-first de actividades_del_ambito_fn (ventana + limit 10000).';

commit;
