-- ============================================================================
-- C1-ter — La vista de DESCARTADOS del coordinador (pedido de Miguel 2026-07-24)
--
-- Qué habilita: hoy, cuando Rosa descarta, el lead desaparece de su pantalla
-- para siempre — el "Deshacer" solo vive en un toast de 15 segundos, pero
-- crm.deshacer_descarte da 24 HORAS. Esta RPC alimenta la pestaña "Descartados":
-- Rosa revisa lo que cerró (motivo, comentario, cuándo, quién) y deshace los
-- SUYOS dentro de la ventana. De paso es la primera lectura real de la matriz
-- del clasificador: cuántos 'pide_credito' está cerrando la segunda malla.
--
-- ALCANCE deliberado: SOLO descartes de la COLA GLOBAL cerrados por
-- coordinador/gerencia — el espejo exacto de crm.descartar_lead. DOS filtros,
-- no uno (auditoría c1c):
--   (1) tenencia ACTUAL nula (vendedor_id y asignado_supervisor_id null) — un
--       descarte de cartera del vendedor tiene dueño y queda fuera;
--   (2) el AUTOR del descarte pasa el mismo gate (rol coordinador|gerencia).
--   Sin (2), un lead que un vendedor descartó y que gerencia LUEGO liberó a la
--   cola global (el guard permite reasignar un lead ya terminal) reaparecería
--   aquí con el nombre del vendedor — rompiendo la promesa de que
--   descartado_por_nombre es siempre staff de la cola.
--
-- Ventana y tope: últimos 30 días, LIMIT 200, descartado_en DESC. La vista es
-- OPERATIVA (revisar/deshacer lo reciente), no un archivo histórico — el
-- histórico completo vive en public.audit_log y crm.actividades. Los
-- descartados ANTIGUOS sin sello (anteriores a c1b; no se inventó backfill)
-- quedan fuera solos por `descartado_en is not null`.
--
-- PII y separación comentario/nota: misma premisa que la cola (sin
-- teléfono/correo/DNI; private.redactar_pii es la fuente única). c1b APPENDEA la
-- nota que Rosa escribe al cerrar AL FINAL del comentario del cliente
-- (' · DESCARTE: <nota>'). Se DEVUELVEN SEPARADOS: si se redactara y truncara el
-- texto pegado, un comentario de cliente largo empujaría la razón del cierre
-- fuera del corte de 400 — y con ámbito ∅ no hay otra forma de recuperarla
-- (auditoría c1c). Así `comentario` (del cliente) y `nota_descarte` (de Rosa)
-- se truncan por separado y ninguno se come al otro.
--
-- `puede_deshacer` es un HINT de UI (pinta el botón): el servidor RE-VALIDA
-- todo en crm.deshacer_descarte (propio + 24 h + sin dueño + carrera). Mentirle
-- al hint solo compra un P0002 con mensaje humano.
--
-- `creado_en` viaja (como en la cola): al deshacer, el lead vuelve a 'nuevo' y
-- el FIFO lo manda al FRENTE de la cola por su fecha de INGRESO — Rosa necesita
-- saber qué tan viejo es antes de reabrirlo.
--
-- Frontera: solo LECTURA sobre crm.leads + JOIN de lectura a public.perfiles
-- (no altera ningún objeto de public). Cero tablas, cero policies, cero
-- triggers nuevos. Plan: vault "Distribución de leads y base fría" — C1-ter.
-- ============================================================================

begin;
set local lock_timeout = '10s';

create or replace function crm.leads_descartados()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text, creado_en timestamptz,
  clasificacion_auto text, comentario text, nota_descarte text,
  motivo_descarte text, descartado_en timestamptz,
  descartado_por_nombre text, es_mio boolean, puede_deshacer boolean
)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
begin
  -- Gate idéntico al de la cola: coordinador|gerencia activos con perfil activo.
  if v_actor is null or not exists (
    select 1 from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador','gerencia')
      and actor_equipo.activo = true and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver los leads descartados de la cola'
      using errcode = '42501';
  end if;

  return query
  select l.id, l.nombre_completo, l.distrito, l.origen,
         l.categoria_interes, l.monto_estimado, l.moneda, l.creado_en,
         l.clasificacion_auto,
         -- Comentario DEL CLIENTE (la parte anterior al marcador ' · DESCARTE: '
         -- que appendea c1b; si TODA la nota es la de Rosa, comentario = null),
         -- REDACTADO y trunco a 400 por separado de la nota del cierre.
         nullif(left(private.redactar_pii(
           case
             when sp.pos > 0 then left(l.nota, sp.pos - 1)
             when l.nota like 'DESCARTE: %' then ''
             else coalesce(l.nota, '')
           end), 400), ''),
         -- Nota que Rosa escribió al cerrar (la parte tras el marcador), también
         -- redactada y trunca aparte: el truncado del comentario nunca la borra.
         nullif(left(private.redactar_pii(
           case
             when sp.pos > 0 then substring(l.nota from sp.pos + length(' · DESCARTE: '))
             when l.nota like 'DESCARTE: %' then substring(l.nota from length('DESCARTE: ') + 1)
             else ''
           end), 400), ''),
         l.motivo_descarte,
         l.descartado_en,
         p.nombre_completo,   -- el filtro exige AUTOR con rol de staff → nunca null aquí
         (l.descartado_por is not distinct from v_actor),
         (l.descartado_por is not distinct from v_actor
            and l.descartado_en > statement_timestamp() - interval '24 hours')
  from crm.leads l
  join public.perfiles p on p.id = l.descartado_por
  cross join lateral (
    select position(' · DESCARTE: ' in coalesce(l.nota, '')) as pos
  ) sp
  where l.activo = true
    and l.etapa = 'descartado'
    and l.vendedor_id is null
    and l.asignado_supervisor_id is null                 -- (1) SOLO cola global
    and l.descartado_en is not null                      -- con sello (post-c1b)
    and l.descartado_en > statement_timestamp() - interval '30 days'
    and exists (                                         -- (2) AUTOR = staff de la cola
      select 1 from crm.equipo e
      where e.perfil_id = l.descartado_por
        and e.rol_crm in ('coordinador','gerencia')
    )
  order by l.descartado_en desc
  limit 200;
end;
$$;

comment on function crm.leads_descartados() is
  'Descartes recientes de la COLA GLOBAL cerrados por coordinador/gerencia (30 días, tope 200, más nuevos primero) para la pestaña Descartados del coordinador. Sin PII de contacto: comentario del cliente y nota del cierre REDACTADOS y truncados a 400 POR SEPARADO (el truncado de uno no se come al otro). Excluye descartes con dueño (cartera de vendedor) y descartes cuyo autor no sea staff de la cola. puede_deshacer es hint de UI (propio + 24 h); crm.deshacer_descarte re-valida todo. Solo coordinador/gerencia activos; 42501 si no.';

-- WARN authenticated_security_definer_function_executable: clase ACEPTADA y
-- documentada (todas las RPC del CRM viven así).
revoke all on function crm.leads_descartados() from public, anon;
grant execute on function crm.leads_descartados() to authenticated;

commit;
