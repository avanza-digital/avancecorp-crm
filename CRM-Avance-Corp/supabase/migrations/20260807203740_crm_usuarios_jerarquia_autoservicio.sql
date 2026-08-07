-- Usuarios y jerarquia autoservicio del CRM.
--
-- Frontera de autoridad (deliberadamente asimetrica):
--   * Gerencia CRM ACTIVA crea/edita candidatos, recupera accesos, organiza la
--     jerarquia y activa/desactiva la membresia CRM.
--   * Superadmin del Portal ACTIVO solo ve la proyeccion minima necesaria y
--     asigna/cambia rol_crm. No edita datos, estado ni jerarquia, salvo que la
--     misma identidad tambien tenga rol CRM gerencia activo.
--   * Directorio ACTIVO audita una proyeccion seudonimizada, sin PII ni
--     jerarquia. No recibe ninguna capacidad de escritura.
--   * Ninguna RPC cambia public.perfiles.rol ni public.perfiles.activo.
--   * crm.equipo sigue sin INSERT/UPDATE/DELETE directo para authenticated.
--
-- Un alta de Gerencia nace como public.perfiles.rol='comercial', sin fila en
-- crm.equipo (estado pendiente_rol). La primera asignacion de rol, hecha por
-- Superadmin, crea una membresia INACTIVA. Gerencia decide su jerarquia y la
-- activa despues: asignar rol nunca concede por si solo acceso al CRM.

begin;

set local lock_timeout = '10s';

do $$
begin
  if to_regclass('public.perfiles') is null
     or to_regclass('auth.users') is null
     or to_regclass('crm.equipo') is null
     or to_regclass('crm.leads') is null
     or to_regclass('crm.tareas') is null then
    raise exception 'Faltan tablas requeridas por Usuarios/Jerarquia CRM';
  end if;

  if to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.puede_acceder_crm()') is null
     or to_regprocedure('crm.mi_acceso_fn()') is null then
    raise exception 'Faltan helpers P04 de acceso CRM';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'public.perfiles'::regclass
      and a.attname in (
        'correo', 'dni', 'tipo_documento', 'telefono', 'whatsapp', 'cargo',
        'creado_por', 'creado_en', 'actualizado_en', 'debe_cambiar_password'
      )
    group by a.attrelid having count(*) = 10
  ) then
    raise exception 'public.perfiles no tiene el contrato requerido';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'crm.equipo'::regclass
      and a.attname in ('creado_por', 'creado_en', 'actualizado_en')
    group by a.attrelid having count(*) = 3
  ) then
    raise exception 'crm.equipo no tiene columnas de autoria/version';
  end if;
end;
$$;

-- Directorio es un rol CRM de solo lectura. Historicamente entraba solo como
-- fallback Portal sin fila en equipo; se admite tambien la membresia explicita
-- sin convertirla en rol operativo ni darle descendientes/responsabilidades.
-- El nombre es parte del contrato desde 20260721120000; fallar si diverge evita
-- borrar accidentalmente otro CHECK futuro que tambien mencione rol_crm.
alter table crm.equipo drop constraint equipo_rol_crm_check;

alter table crm.equipo
  add constraint equipo_rol_crm_check check (rol_crm in (
    'vendedor','supervisor','gerencia','coordinador','directorio'
  ));

create or replace function private.rol_crm(p_perfil_id uuid)
returns text
language sql stable security definer
set search_path = ''
as $$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo is true and p.activo is true
    and e.rol_crm in (
      'vendedor','supervisor','gerencia','coordinador','directorio'
    )
    -- Superadmin Portal gobierna roles CRM; solo una membresia de Gerencia le
    -- suma autoridad operativa. Cualquier otro rol queda fuera del gate global.
    and (p.rol is distinct from 'superadmin' or e.rol_crm = 'gerencia');
$$;

create or replace function private.es_lector_global()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    left join crm.equipo e on e.perfil_id = p.id
    where p.id = (select auth.uid())
      and p.activo is true
      and (
        (e.perfil_id is not null
          and e.activo is true
          and e.rol_crm = 'directorio'
          and p.rol is distinct from 'superadmin')
        or (e.perfil_id is null and p.rol = 'directorio')
      )
  );
$$;

comment on function private.es_lector_global() is
  'Lector global: solo Directorio CRM explicito activo o Directorio Portal sin membresia. Admin/Superadmin Portal no heredan lectura operativa.';

revoke all on function private.rol_crm(uuid) from public, anon;
revoke all on function private.es_lector_global() from public, anon;
grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.es_lector_global() to authenticated;

-- Destinos y actores comparten exactamente el mismo concepto de rol efectivo.
-- Sin esta redefinicion, el helper heredado de P04 leeria crm.equipo directo y
-- un Superadmin + Vendedor/Supervisor podria seguir recibiendo responsabilidad.
create or replace function private.es_destino_crm_activo(
  p_perfil_id uuid,
  p_roles text[]
)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    private.rol_crm(p_perfil_id) = any (p_roles),
    false
  );
$$;

comment on function private.es_destino_crm_activo(uuid, text[]) is
  'Destino CRM activo resuelto por el rol efectivo canonico; Superadmin Portal solo puede ser destino operativo cuando tambien es Gerencia.';

revoke all on function private.es_destino_crm_activo(uuid, text[])
  from public, anon, authenticated, service_role;

-- Roster operativo: solo identidades con rol efectivo. Los perfiles pendientes,
-- inactivos o Superadmin no-Gerencia permanecen administrables en Usuarios,
-- pero no aparecen como vendedores/supervisores/operadores del CRM.
create or replace function crm.equipo_visible_fn()
returns table (
  perfil_id uuid,
  nombre_completo text,
  rol_crm text,
  supervisor_id uuid,
  activo boolean
)
language sql stable security definer
set search_path = ''
as $$
  select e.perfil_id, p.nombre_completo, e.rol_crm, e.supervisor_id, e.activo
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where private.puede_acceder_crm()
    and private.rol_crm(e.perfil_id) is not null
    and (
      (e.perfil_id = (select auth.uid()) and e.activo is true)
      or e.perfil_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or private.es_lector_global()
    );
$$;

comment on function crm.equipo_visible_fn() is
  'Roster operativo vivo: conserva el alcance P04 y excluye toda identidad sin rol CRM efectivo. El histórico/inactivo se administra por Usuarios.';

revoke all on function crm.equipo_visible_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.equipo_visible_fn() to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Capacidades vivas: jamas se confia en metadata del JWT
-- ---------------------------------------------------------------------------

create or replace function private.es_superadmin_portal_activo()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    left join crm.equipo e on e.perfil_id = p.id
    where p.id = (select auth.uid())
      and p.activo is true
      and p.rol = 'superadmin'
      and (
        e.perfil_id is null
        or (
          e.activo is true
          and e.rol_crm in (
            'vendedor','supervisor','gerencia','coordinador','directorio'
          )
        )
      )
  );
$$;

create or replace function private.es_gerencia_crm_activa()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    private.rol_crm((select auth.uid())) = 'gerencia',
    false
  );
$$;

-- Mantener la comprobacion positiva permite redactar Directorio en Usuarios sin
-- confundirla con la autoridad independiente de Superadmin para gobernar roles.
create or replace function private.es_directorio_crm_activo()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(private.puede_acceder_crm(), false)
     and exists (
       select 1
       from public.perfiles p
       left join crm.equipo e on e.perfil_id = p.id
       where p.id = (select auth.uid())
         and p.activo is true
         and (
           (e.perfil_id is not null
             and e.activo is true
             and e.rol_crm = 'directorio')
           or (e.perfil_id is null and p.rol = 'directorio')
         )
     );
$$;

create or replace function private.puede_listar_usuarios_crm()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(private.es_gerencia_crm_activa(), false)
      or coalesce(private.es_superadmin_portal_activo(), false)
      or coalesce(private.es_directorio_crm_activo(), false);
$$;

revoke all on function private.es_superadmin_portal_activo()
  from public, anon, authenticated, service_role;
revoke all on function private.es_gerencia_crm_activa()
  from public, anon, authenticated, service_role;
revoke all on function private.es_directorio_crm_activo()
  from public, anon, authenticated, service_role;
revoke all on function private.puede_listar_usuarios_crm()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1.b Cola de reparto: adaptar las RPC historicas al rol CRM efectivo
-- ---------------------------------------------------------------------------
--
-- C1/C1b/C1c validaban al actor leyendo crm.equipo directamente. Esa lectura
-- es correcta para los roles CRM ordinarios, pero permitiria que un perfil
-- Portal Superadmin + Coordinador operase la cola aunque private.rol_crm() ya
-- hubiese retirado su rol efectivo. Las implementaciones historicas se guardan
-- en private sin EXECUTE externo y las RPC publicas anteponen el gate canonico.

create or replace function private.puede_operar_reparto_crm()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    private.rol_crm((select auth.uid())) in ('coordinador','gerencia'),
    false
  );
$$;

revoke all on function private.puede_operar_reparto_crm()
  from public, anon, authenticated, service_role;

alter function crm.leads_por_repartir() set schema private;
alter function private.leads_por_repartir()
  rename to leads_por_repartir_implementacion;
revoke all on function private.leads_por_repartir_implementacion()
  from public, anon, authenticated, service_role;

create function crm.leads_por_repartir()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text,
  creado_en timestamptz, clasificacion_auto text, comentario text
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.puede_operar_reparto_crm() then
    raise insufficient_privilege using message = 'Solo Coordinacion o Gerencia puede ver la cola de reparto';
  end if;
  return query select * from private.leads_por_repartir_implementacion();
end;
$$;

alter function crm.supervisores_para_reparto() set schema private;
alter function private.supervisores_para_reparto()
  rename to supervisores_para_reparto_implementacion;
revoke all on function private.supervisores_para_reparto_implementacion()
  from public, anon, authenticated, service_role;

create function crm.supervisores_para_reparto()
returns table (
  perfil_id uuid, nombre text, activo boolean, bandeja_pendiente integer
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.puede_operar_reparto_crm() then
    raise insufficient_privilege using message = 'Solo Coordinacion o Gerencia puede ver los supervisores de reparto';
  end if;
  return query
  select s.*
  from private.supervisores_para_reparto_implementacion() s
  where private.es_destino_crm_activo(s.perfil_id, array['supervisor']);
end;
$$;

alter function crm.repartir_lead(uuid, uuid) set schema private;
alter function private.repartir_lead(uuid, uuid)
  rename to repartir_lead_implementacion;
revoke all on function private.repartir_lead_implementacion(uuid, uuid)
  from public, anon, authenticated, service_role;

create function crm.repartir_lead(p_lead uuid, p_supervisor uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.puede_operar_reparto_crm() then
    raise insufficient_privilege using message = 'Solo Coordinacion o Gerencia puede repartir leads';
  end if;
  if not private.es_destino_crm_activo(p_supervisor, array['supervisor']) then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;
  return private.repartir_lead_implementacion(p_lead, p_supervisor);
end;
$$;

alter function crm.descartar_lead(uuid, text, text) set schema private;
alter function private.descartar_lead(uuid, text, text)
  rename to descartar_lead_implementacion;
revoke all on function private.descartar_lead_implementacion(uuid, text, text)
  from public, anon, authenticated, service_role;

create function crm.descartar_lead(
  p_lead uuid,
  p_motivo text,
  p_nota text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.puede_operar_reparto_crm() then
    raise insufficient_privilege using message = 'Solo Coordinacion o Gerencia puede descartar leads de la cola';
  end if;
  return private.descartar_lead_implementacion(p_lead, p_motivo, p_nota);
end;
$$;

alter function crm.deshacer_descarte(uuid) set schema private;
alter function private.deshacer_descarte(uuid)
  rename to deshacer_descarte_implementacion;
revoke all on function private.deshacer_descarte_implementacion(uuid)
  from public, anon, authenticated, service_role;

create function crm.deshacer_descarte(p_lead uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.puede_operar_reparto_crm() then
    raise insufficient_privilege using message = 'Solo Coordinacion o Gerencia puede deshacer descartes';
  end if;
  return private.deshacer_descarte_implementacion(p_lead);
end;
$$;

alter function crm.leads_descartados() set schema private;
alter function private.leads_descartados()
  rename to leads_descartados_implementacion;
revoke all on function private.leads_descartados_implementacion()
  from public, anon, authenticated, service_role;

create function crm.leads_descartados()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text, creado_en timestamptz,
  clasificacion_auto text, comentario text, nota_descarte text,
  motivo_descarte text, descartado_en timestamptz,
  descartado_por_nombre text, es_mio boolean, puede_deshacer boolean
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.puede_operar_reparto_crm() then
    raise insufficient_privilege using message = 'Solo Coordinacion o Gerencia puede ver los descartes de la cola';
  end if;
  return query select * from private.leads_descartados_implementacion();
end;
$$;

revoke all on function crm.leads_por_repartir()
  from public, anon, authenticated, service_role;
revoke all on function crm.supervisores_para_reparto()
  from public, anon, authenticated, service_role;
revoke all on function crm.repartir_lead(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.descartar_lead(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function crm.deshacer_descarte(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.leads_descartados()
  from public, anon, authenticated, service_role;
grant execute on function crm.leads_por_repartir() to authenticated;
grant execute on function crm.supervisores_para_reparto() to authenticated;
grant execute on function crm.repartir_lead(uuid, uuid) to authenticated;
grant execute on function crm.descartar_lead(uuid, text, text) to authenticated;
grant execute on function crm.deshacer_descarte(uuid) to authenticated;
grant execute on function crm.leads_descartados() to authenticated;

comment on function private.puede_operar_reparto_crm() is
  'Gate canonico de C1: Coordinacion ordinaria o Gerencia efectiva. Superadmin Portal solo suma operacion si tambien es Gerencia.';
comment on function crm.leads_por_repartir() is
  'Frontera C1 endurecida: conserva la proyeccion historica y exige rol CRM efectivo Coordinacion o Gerencia.';
comment on function crm.supervisores_para_reparto() is
  'Frontera C1 endurecida: conserva destinos/carga y exige rol CRM efectivo Coordinacion o Gerencia.';
comment on function crm.repartir_lead(uuid, uuid) is
  'Frontera C1 endurecida para reparto atomico; Superadmin Portal sin Gerencia queda fuera.';
comment on function crm.descartar_lead(uuid, text, text) is
  'Frontera C1b endurecida para descarte de cola; Superadmin Portal sin Gerencia queda fuera.';
comment on function crm.deshacer_descarte(uuid) is
  'Frontera C1b endurecida para deshacer descarte; Superadmin Portal sin Gerencia queda fuera.';
comment on function crm.leads_descartados() is
  'Frontera C1c endurecida para lectura de descartes; Superadmin Portal sin Gerencia queda fuera.';

-- El feed ICS se consume con service_role y un token, fuera de la RLS del
-- navegador. Conserva la implementación viva, pero el token solo autoriza si
-- su dueño mantiene un rol CRM efectivo bajo la misma política canónica.
alter function crm.agenda_ics_feed_fn(uuid, timestamptz) set schema private;
alter function private.agenda_ics_feed_fn(uuid, timestamptz)
  rename to agenda_ics_feed_implementacion;
revoke all on function private.agenda_ics_feed_implementacion(uuid, timestamptz)
  from public, anon, authenticated, service_role;

create function crm.agenda_ics_feed_fn(p_token uuid, p_desde timestamptz)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_perfil_id uuid;
begin
  select a.perfil_id into v_perfil_id
  from crm.agenda_ics a
  where a.token = p_token;

  if not found or private.rol_crm(v_perfil_id) is null then
    return pg_catalog.jsonb_build_object(
      'autorizado', false,
      'tareas', '[]'::jsonb
    );
  end if;

  return private.agenda_ics_feed_implementacion(p_token, p_desde);
end;
$$;

revoke all on function crm.agenda_ics_feed_fn(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function crm.agenda_ics_feed_fn(uuid, timestamptz)
  to service_role;

comment on function crm.agenda_ics_feed_fn(uuid, timestamptz) is
  'Feed ICS por token con rol CRM efectivo: inactividad y Superadmin no-Gerencia fallan cerrados aunque el token exista.';

create or replace function crm.mi_acceso_fn()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_nombre text;
  v_rol_portal text;
  v_perfil_activo boolean;
  v_tiene_equipo boolean;
  v_rol_crm text;
  v_equipo_activo boolean;
  v_es_gerencia boolean := false;
  v_es_superadmin boolean := false;
  v_es_directorio boolean := false;
begin
  if v_actor is null then
    raise insufficient_privilege using message = 'Sesion CRM requerida';
  end if;

  select p.nombre_completo, p.rol, p.activo,
         e.perfil_id is not null, e.rol_crm, e.activo
    into v_nombre, v_rol_portal, v_perfil_activo,
         v_tiene_equipo, v_rol_crm, v_equipo_activo
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where p.id = v_actor;

  if not found then
    return pg_catalog.jsonb_build_object(
      'estado', 'no_enrolado', 'perfil_id', v_actor,
      'puede_listar_usuarios', false,
      'puede_administrar_usuarios', false,
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', false
    );
  end if;

  if v_perfil_activo is not true
     or (v_tiene_equipo and (
       v_equipo_activo is not true
       or v_rol_crm not in ('vendedor','supervisor','gerencia','coordinador','directorio')
     )) then
    return pg_catalog.jsonb_build_object(
      'estado', 'revocado', 'perfil_id', v_actor,
      'puede_listar_usuarios', false,
      'puede_administrar_usuarios', false,
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', false
    );
  end if;

  v_es_gerencia := private.es_gerencia_crm_activa();
  v_es_superadmin := private.es_superadmin_portal_activo();
  v_es_directorio := private.es_directorio_crm_activo();

  if v_es_superadmin and not v_es_gerencia then
    return pg_catalog.jsonb_build_object(
      'estado', 'administrador_roles', 'perfil_id', v_actor,
      'rol_portal', v_rol_portal,
      'nombre_completo', v_nombre,
      'puede_listar_usuarios', true,
      'puede_administrar_usuarios', false,
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', true
    );
  end if;

  if v_tiene_equipo then
    return pg_catalog.jsonb_build_object(
      'estado', 'miembro', 'perfil_id', v_actor,
      'rol_crm', v_rol_crm, 'rol_portal', v_rol_portal,
      'nombre_completo', v_nombre,
      'puede_listar_usuarios',
        v_es_gerencia or v_es_superadmin or v_es_directorio,
      'puede_administrar_usuarios', v_es_gerencia,
      'puede_organizar_jerarquia', v_es_gerencia,
      'puede_administrar_roles', v_es_superadmin
    );
  end if;

  if v_rol_portal = 'directorio' then
    return pg_catalog.jsonb_build_object(
      'estado', 'global', 'perfil_id', v_actor,
      'rol_crm', 'directorio', 'rol_portal', v_rol_portal,
      'nombre_completo', v_nombre,
      'puede_listar_usuarios', v_es_superadmin or v_es_directorio,
      'puede_administrar_usuarios', false,
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', v_es_superadmin
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'estado', 'no_enrolado', 'perfil_id', v_actor,
    'puede_listar_usuarios', false,
    'puede_administrar_usuarios', false,
    'puede_organizar_jerarquia', false,
    'puede_administrar_roles', false
  );
end;
$$;

comment on function crm.mi_acceso_fn() is
  'Acceso P04 y capacidades vivas: Gerencia opera/administra; Superadmin sin Gerencia obtiene estado administrador_roles sin rol CRM; Directorio audita.';

revoke all on function crm.mi_acceso_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.mi_acceso_fn() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Auditoria semantica append-only, sin credenciales ni PII
-- ---------------------------------------------------------------------------

create table crm.usuario_eventos (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  objetivo_id uuid,
  accion text not null constraint usuario_eventos_accion_valida check (accion in (
    'candidato_creado', 'perfil_actualizado', 'rol_asignado', 'rol_cambiado',
    'jerarquia_actualizada', 'membresia_activada',
    'membresia_desactivada', 'recuperacion_solicitada'
  )),
  detalle jsonb not null default '{}'::jsonb
    constraint usuario_eventos_detalle_objeto check (
      pg_catalog.jsonb_typeof(detalle) = 'object'
      and pg_catalog.octet_length(detalle::text) <= 4096
    ),
  idempotencia uuid not null,
  creado_en timestamptz not null default pg_catalog.clock_timestamp(),
  constraint usuario_eventos_idempotencia_unica
    unique (actor_id, accion, idempotencia)
);

comment on table crm.usuario_eventos is
  'Auditoria de usuarios CRM. Append-only y cerrada al Data API; nunca contiene email, documento, password, token ni secreto.';

create index usuario_eventos_objetivo_fecha_idx
  on crm.usuario_eventos (objetivo_id, creado_en desc);

alter table crm.usuario_eventos enable row level security;
revoke all privileges on table crm.usuario_eventos
  from public, anon, authenticated, service_role;
revoke all privileges on sequence crm.usuario_eventos_id_seq
  from public, anon, authenticated, service_role;

create or replace function private.registrar_evento_usuario(
  p_accion text, p_objetivo_id uuid, p_detalle jsonb, p_idempotencia uuid
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_detalle jsonb := coalesce(p_detalle, '{}'::jsonb);
begin
  if (select auth.uid()) is null or p_idempotencia is null then
    raise insufficient_privilege using message = 'Actor e idempotencia requeridos';
  end if;

  if pg_catalog.jsonb_typeof(v_detalle) <> 'object'
     or pg_catalog.octet_length(v_detalle::text) > 4096
     or lower(v_detalle::text) ~ '(password|contrase|token|secret|clave)' then
    raise exception 'Detalle de auditoria no permitido';
  end if;

  insert into crm.usuario_eventos (
    actor_id, objetivo_id, accion, detalle, idempotencia
  ) values (
    (select auth.uid()), p_objetivo_id, p_accion, v_detalle, p_idempotencia
  )
  on conflict (actor_id, accion, idempotencia) do nothing;
end;
$$;

revoke all on function private.registrar_evento_usuario(text, uuid, jsonb, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Invariantes estructurales de jerarquia y dependencias
-- ---------------------------------------------------------------------------

create or replace function private.validar_supervisor_usuario_crm(
  p_perfil_id uuid,
  p_rol_crm text,
  p_supervisor_id uuid
)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_rol_supervisor text;
  v_supervisor_activo boolean;
  v_perfil_supervisor_activo boolean;
  v_membresia_activa boolean;
begin
  if p_rol_crm not in ('vendedor','supervisor','gerencia','coordinador','directorio') then
    raise exception 'Rol CRM no permitido';
  end if;

  select e.activo into v_membresia_activa
  from crm.equipo e
  where e.perfil_id = p_perfil_id;

  if p_supervisor_id is null then
    if p_rol_crm = 'vendedor' and v_membresia_activa is true then
      raise exception 'Un vendedor CRM activo requiere un Supervisor activo';
    end if;
    return;
  end if;

  if p_supervisor_id = p_perfil_id then
    raise exception 'Un usuario no puede supervisarse a si mismo';
  end if;

  if p_rol_crm in ('gerencia','coordinador','directorio') then
    raise exception 'Gerencia, Coordinacion y Directorio no admiten supervisor';
  end if;

  select e.rol_crm, e.activo, p.activo
    into v_rol_supervisor, v_supervisor_activo, v_perfil_supervisor_activo
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_supervisor_id;

  if not found
     or v_supervisor_activo is not true
     or v_perfil_supervisor_activo is not true
     or (p_rol_crm = 'vendedor' and v_rol_supervisor <> 'supervisor')
     or (p_rol_crm = 'supervisor' and v_rol_supervisor not in ('supervisor','gerencia')) then
    raise exception 'El supervisor destino no existe, no esta activo o no tiene rol compatible';
  end if;

  if exists (
    with recursive ancestros as (
      select e.perfil_id, e.supervisor_id
      from crm.equipo e
      where e.perfil_id = p_supervisor_id
      union
      select e.perfil_id, e.supervisor_id
      from crm.equipo e
      join ancestros a on e.perfil_id = a.supervisor_id
    )
    select 1 from ancestros where perfil_id = p_perfil_id
  ) then
    raise exception 'La jerarquia propuesta forma un ciclo';
  end if;
end;
$$;

create or replace function private.validar_equipo_usuario_crm(p_perfil_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_fila crm.equipo%rowtype;
  v_perfil_activo boolean;
  v_rol_portal text;
begin
  select e.* into v_fila
  from crm.equipo e
  where e.perfil_id = p_perfil_id;

  if not found then
    return;
  end if;

  perform private.validar_supervisor_usuario_crm(
    v_fila.perfil_id, v_fila.rol_crm, v_fila.supervisor_id
  );

  select p.activo, p.rol into v_perfil_activo, v_rol_portal
  from public.perfiles p where p.id = v_fila.perfil_id;

  if v_fila.activo and v_perfil_activo is not true then
    raise exception 'Una membresia CRM activa requiere perfil Portal activo';
  end if;

  if v_fila.activo
     and v_rol_portal = 'superadmin'
     and v_fila.rol_crm <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede tener una membresia CRM activa como Gerencia';
  end if;

  if v_fila.rol_crm not in ('supervisor','gerencia') and exists (
    select 1 from crm.equipo h
    where h.supervisor_id = v_fila.perfil_id and h.activo is true
  ) then
    raise exception 'El rol propuesto no puede conservar subordinados activos';
  end if;

  if v_fila.rol_crm not in ('vendedor','supervisor') and exists (
    select 1 from crm.leads l
    where l.vendedor_id = v_fila.perfil_id
      and l.activo is true and l.etapa not in ('convertido','descartado')
  ) then
    raise exception 'El rol propuesto no puede conservar leads asignados';
  end if;

  if v_fila.rol_crm <> 'supervisor' and exists (
    select 1 from crm.leads l
    where l.asignado_supervisor_id = v_fila.perfil_id
      and l.activo is true and l.etapa not in ('convertido','descartado')
  ) then
    raise exception 'El rol propuesto no puede conservar una bandeja de supervisor';
  end if;

  if v_fila.activo is not true and (
    exists (
      select 1 from crm.equipo h
      where h.supervisor_id = v_fila.perfil_id and h.activo is true
    )
    or exists (
      select 1 from crm.leads l
      where (l.vendedor_id = v_fila.perfil_id
          or l.asignado_supervisor_id = v_fila.perfil_id)
        and l.activo is true and l.etapa not in ('convertido','descartado')
    )
    or exists (
      select 1 from crm.tareas t
      where (t.vendedor_id = v_fila.perfil_id
          or t.asignado_supervisor_id = v_fila.perfil_id)
        and t.activo is true and t.estado = 'pendiente'
    )
    or exists (
      select 1 from public.perfiles p
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = v_fila.perfil_id
    )
  ) then
    raise exception 'La membresia conserva dependencias activas; reasigna antes de desactivar';
  end if;
end;
$$;

create or replace function private.trg_validar_equipo_usuario_crm()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  perform private.validar_equipo_usuario_crm(new.perfil_id);
  return new;
end;
$$;

create or replace function private.trg_perfiles_superadmin_equipo_invariante()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  -- Suspender (NEW.activo=false) siempre queda permitido: P04 exige corte
  -- inmediato. Solo se bloquea crear o reactivar la combinacion operativa.
  if new.activo is true
     and new.rol = 'superadmin'
     and exists (
       select 1 from crm.equipo e
       where e.perfil_id = new.id
         and e.activo is true
         and e.rol_crm <> 'gerencia'
     ) then
    raise exception 'Superadmin Portal solo puede tener una membresia CRM activa como Gerencia';
  end if;
  return new;
end;
$$;

revoke all on function private.validar_supervisor_usuario_crm(uuid, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.validar_equipo_usuario_crm(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.trg_validar_equipo_usuario_crm()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_perfiles_superadmin_equipo_invariante()
  from public, anon, authenticated, service_role;

-- La migracion no normaliza silenciosamente responsabilidades preexistentes.
-- Si aparece una combinacion invalida se detiene para exigir un handoff
-- explicito antes del deploy; ocultarla o apagarla aqui perderia contexto.
do $$
begin
  if exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true
      and p.activo is true
      and p.rol = 'superadmin'
      and e.rol_crm <> 'gerencia'
  ) then
    raise exception 'Hay Superadmin Portal con membresia CRM activa no-Gerencia; reasigna y desactiva antes de aplicar la migracion'
      using errcode = '23514';
  end if;
end;
$$;

drop trigger if exists trg_equipo_validar_usuarios_jerarquia on crm.equipo;
create trigger trg_equipo_validar_usuarios_jerarquia
after insert or update of rol_crm, supervisor_id, activo on crm.equipo
for each row execute function private.trg_validar_equipo_usuario_crm();

drop trigger if exists trg_perfiles_superadmin_equipo_invariante
  on public.perfiles;
create trigger trg_perfiles_superadmin_equipo_invariante
before update of rol, activo on public.perfiles
for each row
when (
  new.activo is true
  and new.rol = 'superadmin'
  and (
    old.rol is distinct from new.rol
    or old.activo is distinct from new.activo
  )
)
execute function private.trg_perfiles_superadmin_equipo_invariante();

-- ---------------------------------------------------------------------------
-- 4. Proyeccion por autoridad. Directorio recibe seudonimo, sin PII/jerarquia.
-- ---------------------------------------------------------------------------

create or replace function crm.usuarios_administrables_fn(
  p_busqueda text default null,
  p_limite integer default 50,
  p_desde integer default 0
)
returns table (
  perfil_id uuid,
  nombre_completo text,
  tipo_documento text,
  documento text,
  correo text,
  telefono text,
  whatsapp text,
  cargo text,
  tipo_cuenta text,
  estado text,
  rol_crm text,
  supervisor_id uuid,
  activo_crm boolean,
  activo_portal boolean,
  version_perfil timestamptz,
  version_equipo timestamptz,
  total bigint
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_es_gerencia boolean := private.es_gerencia_crm_activa();
  v_es_superadmin boolean := private.es_superadmin_portal_activo();
  v_es_directorio boolean := private.es_directorio_crm_activo();
  v_solo_directorio boolean;
  v_q text := nullif(lower(pg_catalog.btrim(p_busqueda)), '');
begin
  if not private.puede_listar_usuarios_crm() then
    raise insufficient_privilege using message = 'No autorizado para listar usuarios CRM';
  end if;

  if p_limite not between 1 and 100 or p_desde not between 0 and 100000 then
    raise exception 'Paginacion invalida';
  end if;

  -- Si una misma identidad tambien es Gerencia o Superadmin conserva la
  -- proyeccion necesaria para esa autoridad. El modo seudonimizado aplica al
  -- Directorio puro y no puede convertirse en un oraculo de PII por busqueda.
  v_solo_directorio := v_es_directorio
    and not v_es_gerencia
    and not v_es_superadmin;

  return query
  select
    p.id,
    case when v_solo_directorio then
      'Usuario CRM · '
        || upper(pg_catalog.right(pg_catalog.replace(p.id::text, '-', ''), 8))
    else p.nombre_completo end,
    case when v_es_gerencia then p.tipo_documento end,
    case when v_es_gerencia then p.dni end,
    case when v_es_gerencia then p.correo end,
    case when v_es_gerencia then p.telefono end,
    case when v_es_gerencia then p.whatsapp end,
    case when v_es_gerencia then p.cargo end,
    case when p.rol = 'comercial' then 'solo_crm' else 'compartida_portal' end,
    case
      when p.activo is not true then 'suspendido_portal'
      when e.perfil_id is null then 'pendiente_rol'
      when e.activo is not true then 'inactivo_crm'
      else 'activo'
    end,
    e.rol_crm,
    case when v_es_gerencia then e.supervisor_id end,
    e.activo,
    p.activo,
    case when v_es_gerencia then p.actualizado_en end,
    case when not v_solo_directorio then e.actualizado_en end,
    count(*) over ()
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where (e.perfil_id is not null or p.rol = 'comercial')
    and (
      v_q is null
      or (
        not v_solo_directorio
        and lower(coalesce(p.nombre_completo, '')) like '%' || v_q || '%'
      )
      or (
        v_es_gerencia and (
          lower(coalesce(p.correo, '')) like '%' || v_q || '%'
          or lower(coalesce(p.dni, '')) like '%' || v_q || '%'
        )
      )
      or (
        v_solo_directorio and (
          lower(
            'Usuario CRM · '
              || upper(pg_catalog.right(
                pg_catalog.replace(p.id::text, '-', ''), 8
              ))
          ) like '%' || v_q || '%'
          or lower(coalesce(e.rol_crm, 'sin rol')) like '%' || v_q || '%'
          or lower(case
            when p.activo is not true then 'suspendido portal'
            when e.perfil_id is null then 'pendiente rol'
            when e.activo is not true then 'inactivo crm'
            else 'activo'
          end) like '%' || v_q || '%'
        )
      )
    )
  order by case when v_solo_directorio
    then p.id::text
    else lower(coalesce(p.nombre_completo, ''))
  end, p.id
  limit p_limite offset p_desde;
end;
$$;

comment on function crm.usuarios_administrables_fn(text, integer, integer) is
  'Roster CRM por autoridad: Gerencia obtiene datos operativos; Superadmin identidad minima para roles; Directorio seudonimos/rol/estado sin PII, jerarquia ni versiones.';

revoke all on function crm.usuarios_administrables_fn(text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.usuarios_administrables_fn(text, integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Alta pendiente y edicion segura de datos: solo Gerencia
-- ---------------------------------------------------------------------------

create or replace function private.validar_datos_usuario_crm(
  p_nombre_completo text,
  p_tipo_documento text,
  p_documento text,
  p_telefono text,
  p_whatsapp text,
  p_cargo text
)
returns void
language plpgsql immutable security invoker
set search_path = ''
as $$
declare
  v_tipo text := upper(pg_catalog.btrim(coalesce(p_tipo_documento, '')));
  v_documento text := upper(pg_catalog.btrim(coalesce(p_documento, '')));
begin
  if length(pg_catalog.btrim(coalesce(p_nombre_completo, ''))) not between 2 and 160 then
    raise exception 'Nombre completo invalido';
  end if;

  if v_tipo = 'DNI' and v_documento !~ '^[0-9]{8}$' then
    raise exception 'DNI invalido';
  elsif v_tipo = 'CE' and v_documento !~ '^[0-9]{9,12}$' then
    raise exception 'CE invalido';
  elsif v_tipo = 'PASAPORTE' and v_documento !~ '^[A-Z0-9]{6,12}$' then
    raise exception 'Pasaporte invalido';
  elsif v_tipo not in ('DNI','CE','PASAPORTE') then
    raise exception 'Tipo de documento invalido';
  end if;

  if p_telefono is not null
     and length(pg_catalog.btrim(p_telefono)) not between 7 and 30 then
    raise exception 'Telefono invalido';
  end if;
  if p_whatsapp is not null
     and length(pg_catalog.btrim(p_whatsapp)) not between 7 and 30 then
    raise exception 'WhatsApp invalido';
  end if;
  if p_cargo is not null
     and length(pg_catalog.btrim(p_cargo)) not between 1 and 120 then
    raise exception 'Cargo invalido';
  end if;
end;
$$;

revoke all on function private.validar_datos_usuario_crm(text, text, text, text, text, text)
  from public, anon, authenticated, service_role;

create or replace function crm.buscar_candidato_por_correo_fn(p_correo text)
returns uuid
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_correo text := lower(pg_catalog.btrim(coalesce(p_correo, '')));
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede preparar altas CRM';
  end if;

  if v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Correo invalido';
  end if;

  select p.id into v_id
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where lower(p.correo) = v_correo
    and (p.rol = 'comercial' or e.perfil_id is not null)
  limit 1;

  return v_id;
end;
$$;

revoke all on function crm.buscar_candidato_por_correo_fn(text)
  from public, anon, authenticated, service_role;
grant execute on function crm.buscar_candidato_por_correo_fn(text)
  to authenticated;

create or replace function crm.registrar_candidato_usuario_fn(
  p_perfil_id uuid,
  p_correo text,
  p_nombre_completo text,
  p_tipo_documento text,
  p_documento text,
  p_telefono text,
  p_whatsapp text,
  p_cargo text,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_correo text := lower(pg_catalog.btrim(coalesce(p_correo, '')));
  v_tipo text := upper(pg_catalog.btrim(coalesce(p_tipo_documento, '')));
  v_documento text := upper(pg_catalog.btrim(coalesce(p_documento, '')));
  v_auth_correo text;
  v_existente record;
  v_evento_objetivo uuid;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede crear usuarios CRM';
  end if;
  if p_perfil_id is null or p_idempotencia is null then
    raise exception 'perfil_id e idempotencia son requeridos';
  end if;
  if v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or length(v_correo) > 254 then
    raise exception 'Correo invalido';
  end if;

  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion = 'candidato_creado'
    and ue.idempotencia = p_idempotencia;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', v_evento_objetivo, 'estado', 'pendiente_rol',
      'idempotente', true
    );
  end if;

  perform private.validar_datos_usuario_crm(
    p_nombre_completo, v_tipo, v_documento,
    nullif(pg_catalog.btrim(p_telefono), ''),
    nullif(pg_catalog.btrim(p_whatsapp), ''),
    nullif(pg_catalog.btrim(p_cargo), '')
  );

  select lower(u.email) into v_auth_correo
  from auth.users u where u.id = p_perfil_id;
  if not found or v_auth_correo is distinct from v_correo then
    raise exception 'La identidad Auth no coincide con el candidato';
  end if;

  select p.id, p.correo, p.rol, e.perfil_id is not null as tiene_equipo
    into v_existente
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where p.id = p_perfil_id
  for update of p;

  if found then
    if lower(v_existente.correo) is distinct from v_correo
       or (v_existente.rol <> 'comercial' and not v_existente.tiene_equipo) then
      raise exception 'La identidad Auth ya pertenece a otro perfil Portal';
    end if;
  else
    insert into public.perfiles (
      id, nombre_completo, tipo_documento, dni, correo,
      telefono, whatsapp, cargo, rol, activo, debe_cambiar_password,
      creado_por, creado_en, actualizado_en
    ) values (
      p_perfil_id,
      pg_catalog.btrim(p_nombre_completo),
      v_tipo,
      v_documento,
      v_correo,
      nullif(pg_catalog.btrim(p_telefono), ''),
      nullif(pg_catalog.btrim(p_whatsapp), ''),
      nullif(pg_catalog.btrim(p_cargo), ''),
      'comercial', true, false,
      v_actor, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
    );
  end if;

  perform private.registrar_evento_usuario(
    'candidato_creado', p_perfil_id,
    pg_catalog.jsonb_build_object('estado', 'pendiente_rol'),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'estado', 'pendiente_rol',
    'idempotente', false
  );
end;
$$;

comment on function crm.registrar_candidato_usuario_fn(uuid, text, text, text, text, text, text, text, uuid) is
  'Finaliza un alta Auth ya creada por la Edge: perfil comercial pendiente, sin rol ni membresia CRM. Solo Gerencia.';

revoke all on function crm.registrar_candidato_usuario_fn(uuid, text, text, text, text, text, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.registrar_candidato_usuario_fn(uuid, text, text, text, text, text, text, text, uuid)
  to authenticated;

create or replace function crm.actualizar_usuario_administrable_fn(
  p_perfil_id uuid,
  p_nombre_completo text,
  p_tipo_documento text,
  p_documento text,
  p_telefono text,
  p_whatsapp text,
  p_cargo text,
  p_version_perfil timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_tipo text := upper(pg_catalog.btrim(coalesce(p_tipo_documento, '')));
  v_documento text := upper(pg_catalog.btrim(coalesce(p_documento, '')));
  v_fila public.perfiles%rowtype;
  v_nueva_version timestamptz := pg_catalog.clock_timestamp();
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede editar usuarios CRM';
  end if;
  if p_idempotencia is null or p_version_perfil is null then
    raise exception 'Idempotencia y version de perfil requeridas';
  end if;

  perform private.validar_datos_usuario_crm(
    p_nombre_completo, v_tipo, v_documento,
    nullif(pg_catalog.btrim(p_telefono), ''),
    nullif(pg_catalog.btrim(p_whatsapp), ''),
    nullif(pg_catalog.btrim(p_cargo), '')
  );

  select p.* into v_fila
  from public.perfiles p
  where p.id = p_perfil_id
    and (
      p.rol = 'comercial'
      or exists (select 1 from crm.equipo e where e.perfil_id = p.id)
    )
  for update;

  if not found then
    raise exception 'Usuario CRM no encontrado';
  end if;
  if exists (
    select 1 from crm.usuario_eventos ue
    where ue.actor_id = v_actor
      and ue.accion = 'perfil_actualizado'
      and ue.idempotencia = p_idempotencia
      and ue.objetivo_id = p_perfil_id
  ) then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'version_perfil', v_fila.actualizado_en,
      'idempotente', true
    );
  elsif exists (
    select 1 from crm.usuario_eventos ue
    where ue.actor_id = v_actor
      and ue.accion = 'perfil_actualizado'
      and ue.idempotencia = p_idempotencia
  ) then
    raise exception 'La idempotencia ya fue usada para otro usuario';
  end if;
  if v_fila.actualizado_en is distinct from p_version_perfil then
    raise exception using errcode = '40001', message = 'El usuario fue modificado por otra sesion';
  end if;

  update public.perfiles p
  set nombre_completo = pg_catalog.btrim(p_nombre_completo),
      tipo_documento = v_tipo,
      dni = v_documento,
      telefono = nullif(pg_catalog.btrim(p_telefono), ''),
      whatsapp = nullif(pg_catalog.btrim(p_whatsapp), ''),
      cargo = nullif(pg_catalog.btrim(p_cargo), ''),
      actualizado_en = v_nueva_version
  where p.id = p_perfil_id;

  select p.actualizado_en into v_nueva_version
  from public.perfiles p where p.id = p_perfil_id;

  perform private.registrar_evento_usuario(
    'perfil_actualizado', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'campos', pg_catalog.jsonb_build_array(
        'nombre_completo','tipo_documento','documento','telefono','whatsapp','cargo'
      )
    ),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'version_perfil', v_nueva_version,
    'idempotente', false
  );
end;
$$;

revoke all on function crm.actualizar_usuario_administrable_fn(uuid, text, text, text, text, text, text, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_usuario_administrable_fn(uuid, text, text, text, text, text, text, timestamptz, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Rol CRM: potestad unica de Superadmin, sin tocar estado ni jerarquia
-- ---------------------------------------------------------------------------

create or replace function crm.asignar_rol_usuario_fn(
  p_perfil_id uuid,
  p_rol_crm text,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_perfil_rol text;
  v_perfil_activo boolean;
  v_tiene_equipo boolean := false;
  v_rol_anterior text;
  v_supervisor uuid;
  v_activo boolean;
  v_version timestamptz;
  v_accion text;
  v_evento_objetivo uuid;
begin
  if not private.es_superadmin_portal_activo() then
    raise insufficient_privilege using message = 'Solo Superadmin puede asignar roles CRM';
  end if;
  if p_rol_crm not in ('vendedor','supervisor','gerencia','coordinador','directorio') then
    raise exception 'Rol CRM no permitido';
  end if;
  if p_idempotencia is null then
    raise exception 'Idempotencia requerida';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select p.rol, p.activo into v_perfil_rol, v_perfil_activo
  from public.perfiles p where p.id = p_perfil_id
  for update;
  if not found or v_perfil_activo is not true then
    raise exception 'El perfil no existe o esta suspendido en Portal';
  end if;
  if v_perfil_rol = 'superadmin' and p_rol_crm <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede recibir el rol CRM Gerencia';
  end if;

  select true, e.rol_crm, e.supervisor_id, e.activo, e.actualizado_en
    into v_tiene_equipo, v_rol_anterior, v_supervisor, v_activo, v_version
  from crm.equipo e where e.perfil_id = p_perfil_id
  for update;
  v_tiene_equipo := found;

  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion in ('rol_asignado','rol_cambiado')
    and ue.idempotencia = p_idempotencia
  limit 1;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    if not v_tiene_equipo then
      raise exception 'La operacion idempotente perdio su membresia';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'rol_crm', v_rol_anterior,
      'activo_crm', v_activo, 'version_equipo', v_version,
      'idempotente', true
    );
  end if;

  if not v_tiene_equipo then
    if v_perfil_rol <> 'comercial' then
      raise exception 'Solo un candidato CRM pendiente puede recibir su primer rol';
    end if;
    if p_version_equipo is not null then
      raise exception using errcode = '40001', message = 'La membresia cambio antes de asignar el rol';
    end if;

    insert into crm.equipo (
      perfil_id, rol_crm, supervisor_id, activo,
      creado_por, creado_en, actualizado_en
    ) values (
      p_perfil_id, p_rol_crm, null, false,
      v_actor, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
    );
    v_accion := 'rol_asignado';
  else
    if p_version_equipo is null or v_version is distinct from p_version_equipo then
      raise exception using errcode = '40001', message = 'La membresia fue modificada por otra sesion';
    end if;
    if v_rol_anterior = p_rol_crm then
      return pg_catalog.jsonb_build_object(
        'perfil_id', p_perfil_id, 'rol_crm', v_rol_anterior,
        'activo_crm', v_activo, 'version_equipo', v_version,
        'idempotente', true
      );
    end if;

    if v_rol_anterior = 'gerencia' and v_activo is true
       and not exists (
         select 1 from crm.equipo e
         join public.perfiles p on p.id = e.perfil_id and p.activo is true
         where e.perfil_id <> p_perfil_id
           and e.rol_crm = 'gerencia' and e.activo is true
       ) then
      raise exception 'No se puede retirar el rol a la ultima Gerencia activa';
    end if;

    -- El Superadmin no recibe supervisor ni activo: conserva ambos valores.
    -- El trigger estructural bloquea el cambio si Gerencia aun no resolvio una
    -- jerarquia o responsabilidad incompatible con el rol nuevo.
    update crm.equipo e
    set rol_crm = p_rol_crm
    where e.perfil_id = p_perfil_id;
    v_accion := 'rol_cambiado';
  end if;

  select e.activo, e.actualizado_en into v_activo, v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  perform private.registrar_evento_usuario(
    v_accion, p_perfil_id,
    pg_catalog.jsonb_build_object(
      'rol_anterior', v_rol_anterior,
      'rol_nuevo', p_rol_crm
    ),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'rol_crm', p_rol_crm,
    'activo_crm', v_activo, 'version_equipo', v_version,
    'idempotente', false
  );
end;
$$;

comment on function crm.asignar_rol_usuario_fn(uuid, text, timestamptz, uuid) is
  'Unica escritura de rol_crm para la app. Solo Superadmin Portal. No acepta ni cambia supervisor/activo; el alta nace inactiva.';

revoke all on function crm.asignar_rol_usuario_fn(uuid, text, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.asignar_rol_usuario_fn(uuid, text, timestamptz, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Jerarquia e impacto: solo Gerencia
-- ---------------------------------------------------------------------------

create or replace function crm.actualizar_jerarquia_usuario_fn(
  p_perfil_id uuid,
  p_supervisor_id uuid,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_supervisor_anterior uuid;
  v_version timestamptz;
  v_evento_objetivo uuid;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede organizar la jerarquia CRM';
  end if;
  if p_version_equipo is null or p_idempotencia is null then
    raise exception 'Version e idempotencia requeridas';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select e.rol_crm, e.supervisor_id, e.actualizado_en
    into v_rol, v_supervisor_anterior, v_version
  from crm.equipo e where e.perfil_id = p_perfil_id
  for update;
  if not found then
    raise exception 'Membresia CRM no encontrada';
  end if;
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion = 'jerarquia_actualizada'
    and ue.idempotencia = p_idempotencia;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'supervisor_id', v_supervisor_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;
  if v_version is distinct from p_version_equipo then
    raise exception using errcode = '40001', message = 'La jerarquia fue modificada por otra sesion';
  end if;

  perform private.validar_supervisor_usuario_crm(
    p_perfil_id, v_rol, p_supervisor_id
  );

  if v_supervisor_anterior is not distinct from p_supervisor_id then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'supervisor_id', p_supervisor_id,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;

  update crm.equipo e
  set supervisor_id = p_supervisor_id
  where e.perfil_id = p_perfil_id;

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  perform private.registrar_evento_usuario(
    'jerarquia_actualizada', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'supervisor_anterior', v_supervisor_anterior,
      'supervisor_nuevo', p_supervisor_id
    ),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'supervisor_id', p_supervisor_id,
    'version_equipo', v_version, 'idempotente', false
  );
end;
$$;

revoke all on function crm.actualizar_jerarquia_usuario_fn(uuid, uuid, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_jerarquia_usuario_fn(uuid, uuid, timestamptz, uuid)
  to authenticated;

create or replace function crm.impacto_desactivacion_usuario_fn(p_perfil_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_subordinados integer;
  v_leads integer;
  v_bandeja integer;
  v_tareas integer;
  v_clientes integer;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede evaluar una baja CRM';
  end if;
  if not exists (select 1 from crm.equipo e where e.perfil_id = p_perfil_id) then
    raise exception 'Membresia CRM no encontrada';
  end if;

  select count(*)::integer into v_subordinados
  from crm.equipo e
  where e.supervisor_id = p_perfil_id and e.activo is true;

  select count(*)::integer into v_leads
  from crm.leads l
  where l.vendedor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_bandeja
  from crm.leads l
  where l.asignado_supervisor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_tareas
  from crm.tareas t
  where (t.vendedor_id = p_perfil_id
      or t.asignado_supervisor_id = p_perfil_id)
    and t.activo is true and t.estado = 'pendiente';

  select count(*)::integer into v_clientes
  from public.perfiles p
  where p.rol = 'cliente' and p.activo is true
    and p.asesor_perfil_id = p_perfil_id;

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id,
    'subordinados_activos', v_subordinados,
    'leads_abiertos', v_leads,
    'leads_en_bandeja', v_bandeja,
    'tareas_pendientes', v_tareas,
    'clientes_activos', v_clientes,
    'requiere_reemplazo',
      v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes > 0
  );
end;
$$;

revoke all on function crm.impacto_desactivacion_usuario_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.impacto_desactivacion_usuario_fn(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Activacion/offboarding CRM con handoff atomico: solo Gerencia
-- ---------------------------------------------------------------------------

create or replace function crm.fijar_membresia_activa_fn(
  p_perfil_id uuid,
  p_activo boolean,
  p_reemplazo_id uuid,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_activo_anterior boolean;
  v_version timestamptz;
  v_perfil_activo boolean;
  v_rol_portal text;
  v_rol_reemplazo text;
  v_reemplazo_activo boolean;
  v_reemplazo_portal_activo boolean;
  v_impacto jsonb;
  v_requiere_reemplazo boolean;
  v_evento_objetivo uuid;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede activar o desactivar membresias CRM';
  end if;
  if p_activo is null or p_version_equipo is null or p_idempotencia is null then
    raise exception 'Estado, version e idempotencia requeridos';
  end if;
  if p_activo is false and p_perfil_id = v_actor then
    raise exception 'Gerencia no puede desactivar su propia membresia';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select e.rol_crm, e.activo, e.actualizado_en, p.activo, p.rol
    into v_rol, v_activo_anterior, v_version, v_perfil_activo, v_rol_portal
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
  for update of e;
  if not found then
    raise exception 'Membresia CRM no encontrada';
  end if;
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion in ('membresia_activada','membresia_desactivada')
    and ue.idempotencia = p_idempotencia
  limit 1;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;
  if v_version is distinct from p_version_equipo then
    raise exception using errcode = '40001', message = 'La membresia fue modificada por otra sesion';
  end if;

  if p_activo and v_rol_portal = 'superadmin' and v_rol <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede activarse en CRM como Gerencia';
  end if;

  if v_activo_anterior is not distinct from p_activo then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;

  if p_activo then
    if v_perfil_activo is not true then
      raise exception 'El perfil esta suspendido en Portal; Gerencia no puede reactivarlo';
    end if;

    update crm.equipo e set activo = true
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_activada', p_perfil_id,
      pg_catalog.jsonb_build_object('estado_nuevo', 'activo'),
      p_idempotencia
    );
  else
    v_impacto := crm.impacto_desactivacion_usuario_fn(p_perfil_id);
    v_requiere_reemplazo := (v_impacto->>'requiere_reemplazo')::boolean;

    if v_requiere_reemplazo and p_reemplazo_id is null then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;

    if p_reemplazo_id is not null then
      if p_reemplazo_id = p_perfil_id then
        raise exception 'El reemplazo debe ser otro usuario';
      end if;

      select e.rol_crm, e.activo, p.activo
        into v_rol_reemplazo, v_reemplazo_activo, v_reemplazo_portal_activo
      from crm.equipo e
      join public.perfiles p on p.id = e.perfil_id
      where e.perfil_id = p_reemplazo_id
      for update of e;

      if not found
         or v_reemplazo_activo is not true
         or v_reemplazo_portal_activo is not true
         or v_rol_reemplazo is distinct from v_rol then
        raise exception 'El reemplazo no existe, no esta activo o no tiene el mismo rol CRM';
      end if;

      if exists (
        with recursive descendientes as (
          select e.perfil_id
          from crm.equipo e
          where e.supervisor_id = p_perfil_id
          union
          select e.perfil_id
          from crm.equipo e
          join descendientes d on e.supervisor_id = d.perfil_id
        )
        select 1 from descendientes where perfil_id = p_reemplazo_id
      ) then
        raise exception 'El reemplazo no puede pertenecer al subarbol del usuario saliente';
      end if;

      update crm.equipo e
      set supervisor_id = p_reemplazo_id
      where e.supervisor_id = p_perfil_id and e.activo is true;

      update crm.leads l
      set vendedor_id = p_reemplazo_id
      where l.vendedor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      update crm.leads l
      set asignado_supervisor_id = p_reemplazo_id
      where l.asignado_supervisor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      -- Los triggers de leads sincronizan la agenda normal. Este barrido cubre
      -- ademas tareas independientes y cualquier residuo historico pendiente.
      update crm.tareas t
      set vendedor_id = p_reemplazo_id
      where t.vendedor_id = p_perfil_id
        and t.activo is true and t.estado = 'pendiente';

      update crm.tareas t
      set asignado_supervisor_id = p_reemplazo_id
      where t.asignado_supervisor_id = p_perfil_id
        and t.activo is true and t.estado = 'pendiente';

      update public.perfiles p
      set asesor_perfil_id = p_reemplazo_id,
          actualizado_en = pg_catalog.clock_timestamp()
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = p_perfil_id;
    end if;

    update crm.equipo e set activo = false
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_desactivada', p_perfil_id,
      pg_catalog.jsonb_build_object(
        'reemplazo_id', p_reemplazo_id,
        'subordinados_transferidos', (v_impacto->>'subordinados_activos')::integer,
        'leads_transferidos',
          (v_impacto->>'leads_abiertos')::integer
          + (v_impacto->>'leads_en_bandeja')::integer,
        'tareas_transferidas', (v_impacto->>'tareas_pendientes')::integer,
        'clientes_transferidos', (v_impacto->>'clientes_activos')::integer
      ),
      p_idempotencia
    );
  end if;

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'activo_crm', p_activo,
    'version_equipo', v_version, 'idempotente', false
  );
end;
$$;

comment on function crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamptz, uuid) is
  'Solo Gerencia. Cambia crm.equipo.activo; nunca public.perfiles.activo. La baja transfiere todas las dependencias declaradas o aborta completa.';

revoke all on function crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.fijar_membresia_activa_fn(uuid, boolean, uuid, timestamptz, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Recuperacion: Gerencia autoriza el objetivo; la Edge envia el correo
-- ---------------------------------------------------------------------------

create or replace function crm.preparar_recuperacion_usuario_fn(
  p_perfil_id uuid,
  p_idempotencia uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_correo text;
  v_evento_objetivo uuid;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede iniciar recuperacion de accesos CRM';
  end if;
  if p_idempotencia is null then
    raise exception 'Idempotencia requerida';
  end if;

  select p.correo into v_correo
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where p.id = p_perfil_id
    and p.activo is true
    and p.correo is not null
    and (p.rol = 'comercial' or e.perfil_id is not null)
  for update of p;
  if not found then
    raise exception 'Usuario CRM no encontrado o suspendido en Portal';
  end if;

  -- Un retry con la misma clave es seguro y no consume la cuota de envio.
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
    where ue.actor_id = v_actor
      and ue.accion = 'recuperacion_solicitada'
      and ue.idempotencia = p_idempotencia;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'correo', lower(v_correo),
      'idempotente', true
    );
  end if;

  if exists (
    select 1 from crm.usuario_eventos ue
    where ue.objetivo_id = p_perfil_id
      and ue.accion = 'recuperacion_solicitada'
      and ue.creado_en > pg_catalog.clock_timestamp() - interval '60 seconds'
  ) or (
    select count(*)
    from crm.usuario_eventos ue
    where ue.objetivo_id = p_perfil_id
      and ue.accion = 'recuperacion_solicitada'
      and ue.creado_en > pg_catalog.clock_timestamp() - interval '1 hour'
  ) >= 5 then
    raise exception using errcode = 'P0001', message = 'Demasiadas solicitudes de recuperacion; espera antes de reintentar';
  end if;

  perform private.registrar_evento_usuario(
    'recuperacion_solicitada', p_perfil_id,
    pg_catalog.jsonb_build_object('canal', 'correo'),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'correo', lower(v_correo),
    'idempotente', false
  );
end;
$$;

revoke all on function crm.preparar_recuperacion_usuario_fn(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.preparar_recuperacion_usuario_fn(uuid, uuid)
  to authenticated;

-- Defensa repetida tras crear las RPC: el navegador conserva solo SELECT de
-- roster. Todas las mutaciones pasan por las funciones anteriores.
revoke insert, update, delete, truncate, references, trigger
  on table crm.equipo from public, anon, authenticated;

commit;
