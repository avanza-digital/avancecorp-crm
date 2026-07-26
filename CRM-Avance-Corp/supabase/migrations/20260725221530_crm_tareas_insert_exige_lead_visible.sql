-- ============================================================================
-- CRM · `tareas_insert` deja de aceptar tareas sobre leads que el actor NO VE
--
-- HUECO PREVIO (descubierto por la auditoría del avance automático de etapa,
-- hallazgo C1; corregido aquí por orden de Miguel, 2026-07-25).
--
-- La policy `tareas_insert` valida la TENENCIA de la fila nueva
-- (`vendedor_id` / `asignado_supervisor_id`) pero NUNCA consulta `crm.leads`.
-- Y esos dos campos no los manda el cliente: los DERIVA del lead
-- `private.trg_tareas_before_insert`, que es SECURITY DEFINER y por tanto lee
-- `crm.leads` saltándose la RLS.
--
-- Para un lead de la COLA GLOBAL (`vendedor_id` y `asignado_supervisor_id`
-- ambos null — el estado normal entre el importador y el reparto de Rosa) los
-- valores derivados son ambos null, y el WITH CHECK pasa por la rama
-- `rol_crm in ('supervisor','gerencia') and vendedor_id is null`.
--
-- Resultado: CUALQUIER supervisor que conociera el UUID de un lead de esa cola
-- (lo tuvo antes en su bandeja, o gerencia lo devolvió) podía crear tareas
-- sobre un lead que `leads_select` no le deja ni VER — metiéndose trabajo ajeno
-- en su agenda y, desde el avance automático de etapa, arrastrando además una
-- escritura sobre `crm.leads`. En prod había 61 leads en esa cola.
--
-- EL ARREGLO: exigir que el lead sea VISIBLE para quien crea la tarea. El
-- `exists` corre bajo la RLS del llamador (no es SECURITY DEFINER), así que
-- `leads_select` es quien decide — misma técnica que ya usa `actividades_insert`
-- y por la que esa vía nunca tuvo el problema.
--
-- Alcance: es un ESTRECHAMIENTO puro. Nadie que pudiera crear una tarea
-- legítima deja de poder:
--   · vendedor sobre lead suyo            → visible (rama vendedor_ids_visibles)
--   · supervisor sobre lead de su equipo  → visible (misma rama)
--   · supervisor sobre su propia bandeja  → visible (rama vendedor_id is null)
--   · gerencia sobre cualquier lead       → visible (rama gerencia, sin filtro)
--   · tareas de CLIENTE (`lead_id` null)  → exentas por la primera condición
--   · `crm.cerrar_tarea` (SECURITY DEFINER) → no pasa por RLS
--   · seeds y edge functions (service_role) → no pasan por RLS
-- Lo único que deja de poder es lo que nunca debió: tareas sobre leads invisibles.
--
-- No toca objetos de `public`. Sin tablas, columnas ni grants nuevos.
-- ============================================================================

begin;

set local lock_timeout = '5s';

-- ALTER POLICY (no DROP+CREATE): conserva nombre, comando, roles y el USING,
-- y no deja a la tabla ni un instante sin la policy.
alter policy tareas_insert on crm.tareas
with check (
  activo = true
  and creado_por = (select auth.uid())
  and (select private.rol_crm((select auth.uid()))) is not null
  and (
    vendedor_id = (select auth.uid())
    or (
      (select private.rol_crm((select auth.uid()))) = any (array['supervisor', 'gerencia'])
      and (
        vendedor_id is null
        or vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
      )
    )
  )
  and (
    asignado_supervisor_id is null
    or asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid())))
  )
  -- ── LO NUEVO ───────────────────────────────────────────────────────────────
  -- `lead_id` no es ambiguo: `crm.leads` no tiene ninguna columna con ese
  -- nombre, así que resuelve a la fila de `crm.tareas` que se está insertando.
  -- El `exists` NO es SECURITY DEFINER → `leads_select` filtra por ámbito.
  and (
    lead_id is null
    or exists (select 1 from crm.leads l where l.id = lead_id)
  )
);

commit;
