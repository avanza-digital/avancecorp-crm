-- ============================================================================
-- F0-hardening: cierre de los 3 hallazgos NUEVOS de los advisors (2026-07-11)
--
-- 1. [ERROR security_definer_view] crm.clientes_basicos era vista de owner.
--    Se pasa al patrón ya aceptado del proyecto (como existe_cliente_por_dni y
--    las RPCs del portal): función SECURITY DEFINER con gate interno + vista
--    security_invoker encima, así el cliente sigue usando .from('clientes_basicos').
-- 2. [WARN function_search_path_mutable] private.normalizar_telefono sin
--    search_path fijo (solo usa funciones de pg_catalog → se fija vacío).
-- 3. [INFO unindexed_foreign_keys] índices para los FK creado_por de las 3
--    tablas crm (regla del portal: toda columna FK con índice).
-- ============================================================================

-- 1) clientes_basicos: función definer gateada + vista invoker
create or replace function crm.clientes_basicos_fn()
returns table (
  id uuid, nombres text, apellidos text, nombre_completo text, dni text,
  correo text, telefono text, asesor_perfil_id uuid, activo boolean,
  creado_en timestamptz
)
language sql stable security definer
set search_path = private, public
as $$
  select p.id, p.nombres, p.apellidos, p.nombre_completo, p.dni, p.correo,
         p.telefono, p.asesor_perfil_id, p.activo, p.creado_en
  from public.perfiles p
  where p.rol = 'cliente'
    and ((select private.rol_crm((select auth.uid()))) is not null
         or (select private.es_lector_global()));
$$;

revoke all on function crm.clientes_basicos_fn() from public, anon;
grant execute on function crm.clientes_basicos_fn() to authenticated;

drop view crm.clientes_basicos;
create view crm.clientes_basicos with (security_invoker = true) as
  select * from crm.clientes_basicos_fn();

comment on view crm.clientes_basicos is
  'Clientes del portal SIN columnas bancarias. Vista invoker sobre crm.clientes_basicos_fn() (SECURITY DEFINER con gate: staff CRM activo o lector global; cualquier otro authenticated obtiene 0 filas).';

grant select on crm.clientes_basicos to authenticated;

-- 2) search_path fijo en el normalizador (solo pg_catalog)
alter function private.normalizar_telefono(text) set search_path = '';

-- 3) índices de FK creado_por
create index if not exists idx_equipo_creado_por      on crm.equipo (creado_por);
create index if not exists idx_leads_creado_por       on crm.leads (creado_por);
create index if not exists idx_actividades_creado_por on crm.actividades (creado_por);
