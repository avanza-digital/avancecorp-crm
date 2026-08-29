-- Gestión de cartera: autorización coherente y contratos de lectura seguros.
--
-- Invariantes de esta entrega:
--   1. Directorio Portal nunca hereda autoridad operativa: una membresía CRM
--      debe ser Directorio; el legado sin membresía conserva solo lectura.
--   2. La visibilidad de clientes del CRM tiene una única fuente server-side.
--   3. El detalle comercial no necesita SELECT crudo sobre public.perfiles y
--      redacta banca para quien solo tiene autoridad de lectura global.
--   4. Una tarea de cliente valida su asignación sin depender de la RLS de la
--      tabla compartida public.perfiles.
--   5. Los números automáticos de contrato se serializan por año.

begin;

set local lock_timeout = '10s';

-- Las RPC de administración de roles usan este mismo mutex. Tomarlo durante
-- toda la migración impide que una reasignación/democión concurrente observe
-- todavía a la falsa Gerencia de Directorio y deje la empresa sin Gerencia o
-- con subordinados colgados de un rol de solo lectura.
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
);

-- No sobreescribir silenciosamente contratos que hayan cambiado después de la
-- auditoría. Los hashes son de prosrc (no incluyen ACL ni formato del DDL).
do $preflight$
declare
  v_hash text;
  v_search_path text := pg_catalog.current_setting('search_path');
begin
  select pg_catalog.md5(p.prosrc) into v_hash
  from pg_catalog.pg_proc p
  where p.oid = 'private.rol_crm(uuid)'::pg_catalog.regprocedure;
  if v_hash is distinct from '2afc1b09b6cf71b10d791fbcae583d2d' then
    raise exception 'Preflight: private.rol_crm(uuid) cambió; revisar antes de reemplazar';
  end if;

  select pg_catalog.md5(p.prosrc) into v_hash
  from pg_catalog.pg_proc p
  where p.oid = 'private.validar_equipo_usuario_crm(uuid)'::pg_catalog.regprocedure;
  if v_hash is distinct from '11a2a2c600addc43aeea7f42a9272f7d' then
    raise exception 'Preflight: private.validar_equipo_usuario_crm(uuid) cambió; revisar antes de reemplazar';
  end if;

  select pg_catalog.md5(p.prosrc) into v_hash
  from pg_catalog.pg_proc p
  where p.oid = 'crm.clientes_basicos_fn()'::pg_catalog.regprocedure;
  -- Producción tiene la forma as-built de 12 columnas; el replay versionado
  -- llega legítimamente con la forma anterior de 10. Ambas son conocidas y se
  -- convergen abajo mediante DROP/CREATE atómico de vista + función.
  if v_hash not in (
    '1d6227ab54dcb34fd0e14508267e3177',
    'd13de445de157b410d1657b77e537f8e'
  ) then
    raise exception 'Preflight: crm.clientes_basicos_fn() cambió; revisar antes de reemplazar';
  end if;

  select pg_catalog.md5(p.prosrc) into v_hash
  from pg_catalog.pg_proc p
  where p.oid = 'private.es_lector_global()'::pg_catalog.regprocedure;
  if v_hash is distinct from 'd9e6238020882c2b2a7d0fb3b76305c1' then
    raise exception 'Preflight: private.es_lector_global() cambió; revisar antes de reemplazar';
  end if;

  select pg_catalog.md5(p.prosrc) into v_hash
  from pg_catalog.pg_proc p
  where p.oid = 'private.trg_tareas_before_insert()'::pg_catalog.regprocedure;
  if v_hash is distinct from '965965198be19bd688a84a86c2d028f2' then
    raise exception 'Preflight: private.trg_tareas_before_insert() cambió; revisar antes de reemplazar';
  end if;

  select pg_catalog.md5(p.prosrc) into v_hash
  from pg_catalog.pg_proc p
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::pg_catalog.regprocedure;
  if v_hash is distinct from 'f50b62e1a9839d2fb68363b8a53e7603' then
    raise exception 'Preflight: public.crear_contrato(jsonb,jsonb) cambió; revisar antes de reemplazar';
  end if;

  -- ALTER POLICY conserva comando, modalidad y roles. Fijar también el
  -- predicado previo evita reemplazar silenciosamente una autorización que
  -- haya derivado entre la captura auditada y el despliegue. pg_get_expr
  -- depende del search_path del ejecutor; vaciarlo vuelve estable la huella.
  perform pg_catalog.set_config('search_path', '', true);
  if not exists (
    select 1
    from pg_catalog.pg_policy p
    where p.polrelid = 'crm.tareas'::pg_catalog.regclass
      and p.polname = 'tareas_insert'
      and p.polcmd = 'a'
      and p.polpermissive is true
      and p.polroles = pg_catalog.array_append(
        array[]::oid[], 'authenticated'::pg_catalog.regrole::oid
      )
      -- El replay versionado llega sin la rama de cliente; la captura viva la
      -- incluye. Ambas formas son conocidas y convergen en el ALTER de abajo.
      and pg_catalog.md5(
        pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid)
      ) in (
        'af6492d0045c728d71860b720050161c',
        'fc2a3a37ca2167732efa3c211a57d8d1'
      )
  ) then
    raise exception 'Preflight: policy crm.tareas.tareas_insert cambió; revisar antes de reemplazar';
  end if;
  perform pg_catalog.set_config('search_path', v_search_path, true);

  if exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and (
        (p.rol = 'directorio' and e.rol_crm not in ('gerencia', 'directorio'))
        or (p.rol <> 'directorio' and e.rol_crm = 'directorio')
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'Preflight: existe una combinación Directorio Portal/CRM no normalizable automáticamente';
  end if;

  if exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and p.rol = 'directorio' and e.rol_crm = 'gerencia'
  ) and not exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and e.rol_crm = 'gerencia' and p.rol <> 'directorio'
  ) then
    raise exception using
      errcode = '23514',
      message = 'Preflight: falta una Gerencia operativa real; no se puede normalizar Directorio';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Identidad efectiva: fail-closed ante cualquier desalineación de Directorio.
-- ---------------------------------------------------------------------------

create or replace function private.rol_crm(p_perfil_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo is true and p.activo is true
    and e.rol_crm in (
      'vendedor','supervisor','gerencia','coordinador','directorio'
    )
    -- Directorio es una capacidad de lectura, no un alias operativo de
    -- Gerencia. Una pareja desalineada no recibe ningún rol efectivo.
    and (
      (p.rol = 'directorio' and e.rol_crm = 'directorio')
      or (p.rol is distinct from 'directorio' and e.rol_crm <> 'directorio')
    )
    -- Superadmin Portal gobierna roles CRM; solo una membresía de Gerencia le
    -- suma autoridad operativa. Cualquier otro rol queda fuera del gate global.
    and (p.rol is distinct from 'superadmin' or e.rol_crm = 'gerencia');
$function$;

create or replace function private.es_lector_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  with actor as materialized (
    select (select auth.uid()) as uid
  )
  select coalesce(private.rol_crm(a.uid) = 'directorio', false)
    or exists (
      select 1
      from public.perfiles p
      where p.id = a.uid
        and p.activo is true
        and p.rol = 'directorio'
        -- El fallback histórico solo aplica sin membresía. Una fila CRM
        -- inactiva o desalineada es revocación, nunca una segunda puerta.
        and not exists (
          select 1 from crm.equipo e where e.perfil_id = p.id
        )
    )
  from actor a;
$function$;

comment on function private.es_lector_global() is
  'Lector global fail-closed: Directorio Portal/CRM alineado y activo, o Directorio Portal sin ninguna membresía CRM. Una fila inactiva/desalineada revoca el fallback.';

revoke all on function private.rol_crm(uuid) from public, anon;
revoke all on function private.es_lector_global() from public, anon;
grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.es_lector_global() to authenticated;

create or replace function private.validar_equipo_usuario_crm(p_perfil_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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
    raise exception 'Una membresía CRM activa requiere perfil Portal activo';
  end if;

  if v_fila.activo
     and v_rol_portal = 'superadmin'
     and v_fila.rol_crm <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede tener una membresía CRM activa como Gerencia';
  end if;

  if v_fila.activo
     and v_rol_portal = 'directorio'
     and v_fila.rol_crm <> 'directorio' then
    raise exception 'Directorio Portal solo puede tener una membresía CRM activa como Directorio';
  end if;

  if v_fila.activo
     and v_fila.rol_crm = 'directorio'
     and v_rol_portal is distinct from 'directorio' then
    raise exception 'Directorio CRM requiere el rol Directorio en el Portal';
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

  if v_fila.rol_crm not in ('vendedor','supervisor') and exists (
    select 1 from public.perfiles p
    where p.rol = 'cliente' and p.activo is true
      and p.asesor_perfil_id = v_fila.perfil_id
  ) then
    raise exception 'El rol propuesto no puede conservar clientes asignados';
  end if;

  if v_fila.rol_crm not in ('vendedor','supervisor') and exists (
    select 1 from crm.tareas t
    where t.vendedor_id = v_fila.perfil_id
      and t.activo is true and t.estado = 'pendiente'
  ) then
    raise exception 'El rol propuesto no puede conservar tareas comerciales pendientes';
  end if;

  if v_fila.rol_crm <> 'supervisor' and exists (
    select 1 from crm.tareas t
    where t.asignado_supervisor_id = v_fila.perfil_id
      and t.activo is true and t.estado = 'pendiente'
  ) then
    raise exception 'El rol propuesto no puede conservar tareas de bandeja de supervisor';
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
    raise exception 'La membresía conserva dependencias activas; reasigna antes de desactivar';
  end if;
end;
$function$;

revoke all on function private.validar_equipo_usuario_crm(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.trg_perfiles_equipo_rol_invariante()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_rol_crm text;
begin
  -- Suspender siempre queda permitido: el corte P04 debe ser inmediato. La
  -- pareja se valida al cambiar el rol o al reactivar el perfil.
  if new.activo is not true then
    return new;
  end if;

  select e.rol_crm into v_rol_crm
  from crm.equipo e
  where e.perfil_id = new.id and e.activo is true;

  if not found then
    return new;
  end if;

  if new.rol = 'superadmin' and v_rol_crm <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede tener una membresía CRM activa como Gerencia';
  end if;
  if new.rol = 'directorio' and v_rol_crm <> 'directorio' then
    raise exception 'Directorio Portal solo puede tener una membresía CRM activa como Directorio';
  end if;
  if v_rol_crm = 'directorio' and new.rol is distinct from 'directorio' then
    raise exception 'Directorio CRM requiere el rol Directorio en el Portal';
  end if;
  return new;
end;
$function$;

revoke all on function private.trg_perfiles_equipo_rol_invariante()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_perfiles_superadmin_equipo_invariante on public.perfiles;
drop trigger if exists trg_perfiles_equipo_rol_invariante on public.perfiles;
create trigger trg_perfiles_equipo_rol_invariante
before update of rol, activo on public.perfiles
for each row
when (
  new.activo is true
  and (
    old.rol is distinct from new.rol
    or old.activo is distinct from new.activo
  )
)
execute function private.trg_perfiles_equipo_rol_invariante();

drop function if exists private.trg_perfiles_superadmin_equipo_invariante();

-- La clasificación histórica conocida era Directorio Portal + Gerencia CRM.
-- Antes de normalizarla, sus supervisores pasan a la única Gerencia operativa
-- real. Si el destino no es unívoco, se aborta: nunca se adivina una jefatura.
do $normalizar_directorio$
declare
  v_gerencias uuid[];
begin
  if exists (
    select 1
    from crm.equipo h
    where h.activo is true
      and h.supervisor_id in (
        select e.perfil_id
        from crm.equipo e
        join public.perfiles p on p.id = e.perfil_id
        where e.activo is true and p.activo is true
          and p.rol = 'directorio' and e.rol_crm = 'gerencia'
      )
  ) then
    select pg_catalog.array_agg(e.perfil_id order by e.perfil_id)
      into v_gerencias
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and e.rol_crm = 'gerencia' and p.rol <> 'directorio';

    if coalesce(pg_catalog.cardinality(v_gerencias), 0) <> 1 then
      raise exception using
        errcode = '23514',
        message = 'No existe una única Gerencia operativa para recibir los supervisores de Directorio';
    end if;

    update crm.equipo h
       set supervisor_id = v_gerencias[1]
     where h.activo is true
       and h.supervisor_id in (
         select e.perfil_id
         from crm.equipo e
         join public.perfiles p on p.id = e.perfil_id
         where e.activo is true and p.activo is true
           and p.rol = 'directorio' and e.rol_crm = 'gerencia'
       );
  end if;

  update crm.equipo e
     set rol_crm = 'directorio', supervisor_id = null
    from public.perfiles p
   where p.id = e.perfil_id
     and p.activo is true and e.activo is true
     and p.rol = 'directorio' and e.rol_crm = 'gerencia';

  if exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and (
        (p.rol = 'directorio' and e.rol_crm <> 'directorio')
        or (p.rol <> 'directorio' and e.rol_crm = 'directorio')
      )
  ) then
    raise exception 'La normalización de Directorio no cerró todas las desalineaciones'
      using errcode = '23514';
  end if;
end;
$normalizar_directorio$;

-- ---------------------------------------------------------------------------
-- 2. Fuente única del ámbito de clientes CRM y detalle con redacción por capacidad.
-- ---------------------------------------------------------------------------

create or replace function private.cliente_ids_visibles_crm()
returns table(cliente_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  with actor as materialized (
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() as lector,
      private.puede_acceder_crm() as acceso
  ), visibles as materialized (
    select private.vendedor_ids_visibles(a.uid) as perfil_id
    from actor a
  )
  select p.id
  from public.perfiles p
  cross join actor a
  where a.uid is not null
    and a.acceso
    and p.rol = 'cliente'
    and (
      a.lector
      or a.rol = 'gerencia'
      or p.asesor_perfil_id in (select v.perfil_id from visibles v)
      or (
        p.asesor_perfil_id is null
        and p.creado_por in (select v.perfil_id from visibles v)
      )
    );
$function$;

comment on function private.cliente_ids_visibles_crm() is
  'Fuente única del ámbito de clientes CRM: global para Gerencia/Directorio, árbol para Supervisor/Analista e incluye el fallback creado_por de clientes aún sin Analista.';

revoke all on function private.cliente_ids_visibles_crm()
  from public, anon, authenticated, service_role;

-- El historial versionado aún declara 10 columnas y producción tiene 12 por
-- una evolución as-built. PostgreSQL no permite cambiar OUT parameters con
-- CREATE OR REPLACE: se reconstruyen vista y función dentro de esta misma
-- transacción, sin ventana observable ni CASCADE.
drop view if exists crm.clientes_basicos;
drop function crm.clientes_basicos_fn();

create function crm.clientes_basicos_fn()
returns table (
  id uuid,
  nombres text,
  apellidos text,
  nombre_completo text,
  dni text,
  correo text,
  telefono text,
  asesor_perfil_id uuid,
  activo boolean,
  creado_en timestamptz,
  tipo_documento text,
  creado_por uuid
)
language sql
stable
security definer
set search_path = ''
as $function$
  select p.id, p.nombres, p.apellidos, p.nombre_completo, p.dni, p.correo,
         p.telefono, p.asesor_perfil_id, p.activo, p.creado_en,
         p.tipo_documento, p.creado_por
  from private.cliente_ids_visibles_crm() v
  join public.perfiles p on p.id = v.cliente_id;
$function$;

comment on function crm.clientes_basicos_fn() is
  'Cartera básica de 12 columnas scopeada exclusivamente por private.cliente_ids_visibles_crm; no expone banca.';

revoke all on function crm.clientes_basicos_fn() from public, anon;
grant execute on function crm.clientes_basicos_fn() to authenticated, service_role;

create view crm.clientes_basicos
with (security_invoker = true)
as select * from crm.clientes_basicos_fn();

comment on view crm.clientes_basicos is
  'Clientes del portal sin columnas bancarias, scopeados por private.cliente_ids_visibles_crm. Vista security_invoker sobre una función definer gateada.';

grant select on crm.clientes_basicos to authenticated, service_role;

create or replace function crm.cliente_detalle_fn(p_cliente_id uuid)
returns table (
  id uuid,
  nombre_completo text,
  nombres text,
  apellidos text,
  tipo_documento text,
  dni text,
  correo text,
  telefono text,
  domicilio text,
  asesor_perfil_id uuid,
  creado_por uuid,
  creado_en timestamptz,
  banca_visible boolean,
  cuentas_bancarias_visibles boolean,
  banco text,
  tipo_cuenta text,
  numero_cuenta text,
  cci text,
  titular_distinto boolean,
  beneficiario_nombre text,
  beneficiario_dni text,
  banco_usd text,
  tipo_cuenta_usd text,
  numero_cuenta_usd text,
  cci_usd text,
  titular_distinto_usd boolean,
  beneficiario_nombre_usd text,
  beneficiario_dni_usd text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol_crm text := private.rol_crm(v_uid);
  v_cliente public.perfiles%rowtype;
  v_acceso_crudo boolean;
  v_acceso_crm boolean;
  v_banca_visible boolean;
  v_cuentas_bancarias_visibles boolean;
begin
  if v_uid is null or p_cliente_id is null then
    return;
  end if;

  select p.* into v_cliente
  from public.perfiles p
  where p.id = p_cliente_id and p.rol = 'cliente';
  if not found then
    return;
  end if;

  -- Espejo exacto de las vías históricas de SELECT crudo sobre perfiles. Esta
  -- rama conserva su semántica; la rama CRM agrega Supervisor/Analista sin
  -- volver a exponer la tabla compartida.
  v_acceso_crudo :=
    v_cliente.id = v_uid
    or (select public.es_gestor_cartera())
    or (
      (select public.es_analista())
      and (
        v_cliente.asesor_perfil_id = v_uid
        or (
          v_cliente.asesor_perfil_id is null
          and v_cliente.creado_por = v_uid
        )
      )
    )
    or v_rol_crm = 'gerencia';

  select exists (
    select 1
    from private.cliente_ids_visibles_crm() v
    where v.cliente_id = v_cliente.id
  ) into v_acceso_crm;

  if not coalesce(v_acceso_crudo, false)
     and not coalesce(v_acceso_crm, false) then
    return;
  end if;

  -- Quien ya podía leer la fila cruda conserva sus campos. Para el nuevo
  -- ámbito CRM, las capacidades existentes deciden; Directorio queda con
  -- identidad/contacto mínimo global, sin domicilio ni banca.
  -- La lectura de las casillas históricas y la lectura del ledger no son la
  -- misma capacidad: el acceso crudo conserva banca embebida aun en un cliente
  -- inactivo, mientras cuentas_bancarias_cliente_fn exige cliente activo.
  -- Publicar ambos bits evita que el navegador infiera uno a partir del otro.
  v_cuentas_bancarias_visibles := coalesce(
    private.puede_gestionar_cuentas_cliente(v_cliente.id), false
  );
  v_banca_visible := coalesce(v_acceso_crudo, false)
    or v_cuentas_bancarias_visibles;

  return query select
    v_cliente.id,
    v_cliente.nombre_completo,
    v_cliente.nombres,
    v_cliente.apellidos,
    v_cliente.tipo_documento,
    v_cliente.dni,
    v_cliente.correo,
    v_cliente.telefono,
    case when private.es_lector_global() then null else v_cliente.domicilio end,
    v_cliente.asesor_perfil_id,
    v_cliente.creado_por,
    v_cliente.creado_en,
    v_banca_visible,
    v_cuentas_bancarias_visibles,
    case when v_banca_visible then v_cliente.banco else null end,
    case when v_banca_visible then v_cliente.tipo_cuenta else null end,
    case when v_banca_visible then v_cliente.numero_cuenta else null end,
    case when v_banca_visible then v_cliente.cci else null end,
    case when v_banca_visible then v_cliente.titular_distinto else false end,
    case when v_banca_visible then v_cliente.beneficiario_nombre else null end,
    case when v_banca_visible then v_cliente.beneficiario_dni else null end,
    case when v_banca_visible then v_cliente.banco_usd else null end,
    case when v_banca_visible then v_cliente.tipo_cuenta_usd else null end,
    case when v_banca_visible then v_cliente.numero_cuenta_usd else null end,
    case when v_banca_visible then v_cliente.cci_usd else null end,
    case when v_banca_visible then v_cliente.titular_distinto_usd else false end,
    case when v_banca_visible then v_cliente.beneficiario_nombre_usd else null end,
    case when v_banca_visible then v_cliente.beneficiario_dni_usd else null end;
end;
$function$;

comment on function crm.cliente_detalle_fn(uuid) is
  'Detalle comercial scopeado server-side. Supervisor ve su árbol; Directorio ve identidad/contacto mínimo global sin domicilio ni banca. banca_visible gobierna casillas embebidas y cuentas_bancarias_visibles refleja exactamente la capacidad de consultar el ledger.';

revoke all on function crm.cliente_detalle_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.cliente_detalle_fn(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Tareas de clientes: comprobar fila real sin heredar RLS de perfiles.
-- ---------------------------------------------------------------------------

-- Se reemite el cuerpo vivo auditado: deriva siempre los destinos técnicos
-- vendedor_id/asignado_supervisor_id desde
-- el cliente antes de que se evalúen los triggers y policies posteriores.
create or replace function private.trg_tareas_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_lead crm.leads%rowtype;
  v_cliente public.perfiles%rowtype;
  v_equipo crm.equipo%rowtype;
begin
  if new.lead_id is not null then
    -- El mismo row-lock serializa alta de tarea contra cierre/reasignación. Sin
    -- él, ambos commits podían dejar la tarea en el árbol anterior.
    select * into v_lead from crm.leads where id = new.lead_id for share;
    if not found then raise exception 'El lead de la tarea no existe'; end if;
    if v_lead.activo = false or v_lead.etapa in ('convertido','descartado') then
      raise exception 'El lead está cerrado: no admite tareas nuevas';
    end if;
    new.vendedor_id := v_lead.vendedor_id;
    new.asignado_supervisor_id := v_lead.asignado_supervisor_id;
  elsif new.perfil_id is not null then
    select * into v_cliente from public.perfiles p
    where p.id = new.perfil_id and p.rol = 'cliente'
    for share;
    if not found then raise exception 'El cliente de la tarea no existe'; end if;
    if not v_cliente.activo then
      raise exception 'El cliente está inactivo: no admite tareas comerciales nuevas';
    end if;
    if v_cliente.asesor_perfil_id is null then
      raise exception 'Asigna un Analista al cliente antes de agendar una gestión';
    end if;
    select * into v_equipo from crm.equipo e
    where e.perfil_id = v_cliente.asesor_perfil_id and e.activo
    for share;
    if not found or v_equipo.rol_crm not in ('vendedor','supervisor') then
      raise exception 'El Analista de la cartera no está activo en el CRM';
    end if;
    new.vendedor_id := v_cliente.asesor_perfil_id;
    new.asignado_supervisor_id := case
      when v_equipo.rol_crm = 'vendedor' then v_equipo.supervisor_id
      else null
    end;
  end if;

  if new.estado <> 'pendiente'
     and coalesce(current_setting('crm.op_tarea', true), 'off') <> 'on' then
    raise exception 'Una tarea nace pendiente; los cierres van por una RPC de agenda'
      using errcode = '22023';
  end if;
  if new.tipo = 'reunion' then
    new.modalidad_reunion := coalesce(new.modalidad_reunion, 'sin_clasificar');
  else
    new.modalidad_reunion := null;
    new.ubicacion_reunion := null;
    new.enlace_reunion := null;
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  if new.estado = 'pendiente' then
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  new.cancelada_por := case when new.estado = 'cancelada' then 'sistema' else null end;
  new.cancelada_por_id := null;
  return new;
end;
$function$;

revoke all on function private.trg_tareas_before_insert()
  from public, anon, authenticated, service_role;

create or replace function private.puede_gestionar_tarea_cliente(
  p_cliente_id uuid,
  p_vendedor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    private.rol_crm((select auth.uid())) in ('vendedor', 'supervisor', 'gerencia')
    and exists (
      select 1
      from public.perfiles p
      join private.cliente_ids_visibles_crm() v on v.cliente_id = p.id
      where p.id = p_cliente_id
        and p.rol = 'cliente'
        and p.activo is true
        and p.asesor_perfil_id = p_vendedor_id
    ),
    false
  );
$function$;

comment on function private.puede_gestionar_tarea_cliente(uuid, uuid) is
  'Valida cliente activo, Analista canónico y ámbito de la tarea bajo SECURITY DEFINER; evita consultar public.perfiles a través de su RLS.';

revoke all on function private.puede_gestionar_tarea_cliente(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.puede_gestionar_tarea_cliente(uuid, uuid)
  to authenticated, service_role;

-- La visibilidad descendente no es simétrica: un Analista ve solo su propio
-- id, pero el trigger debe poder escribir en la tarea el supervisor canónico
-- de su membresía. Encapsular la pareja evita abrir el árbol hacia arriba y
-- conserva la semántica previa de Supervisor/Gerencia.
create function private.puede_asignar_destino_tarea(
  p_vendedor_id uuid,
  p_supervisor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  with actor as materialized (
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol
  ), visibles as materialized (
    select private.vendedor_ids_visibles(a.uid) as perfil_id
    from actor a
  )
  select coalesce(
    case
      when a.rol in ('supervisor', 'gerencia') then
        (p_vendedor_id is null or p_vendedor_id in (
          select v.perfil_id from visibles v
        ))
        and (p_supervisor_id is null or p_supervisor_id in (
          select v.perfil_id from visibles v
        ))
      when a.rol = 'vendedor' then
        p_vendedor_id = a.uid
        and (
          p_supervisor_id is null
          or p_supervisor_id = (
            select e.supervisor_id
            from crm.equipo e
            where e.perfil_id = a.uid and e.activo is true
          )
        )
      else false
    end,
    false
  )
  from actor a;
$function$;

comment on function private.puede_asignar_destino_tarea(uuid, uuid) is
  'Autoriza los destinos técnicos canónicos de una tarea. El Analista solo usa su id y su supervisor directo; Supervisor/Gerencia conservan su ámbito visible.';

revoke all on function private.puede_asignar_destino_tarea(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.puede_asignar_destino_tarea(uuid, uuid)
  to authenticated, service_role;

alter policy tareas_insert on crm.tareas
with check (
  activo = true and creado_por = (select auth.uid())
  and private.puede_asignar_destino_tarea(
    vendedor_id, asignado_supervisor_id
  )
  and (lead_id is null or exists (
    select 1 from crm.leads l where l.id = lead_id
  ))
  and (
    perfil_id is null
    or private.puede_gestionar_tarea_cliente(perfil_id, vendedor_id)
  )
);

-- La tenencia de una tarea no es un campo editable por el navegador. El API
-- solo usa UPDATE directo para mover vencimiento y confirmación; los cierres,
-- reprogramaciones y reasignaciones pasan por RPCs/triggers SECURITY DEFINER.
-- Revocar el UPDATE de tabla evita que un Supervisor o Analista falsifique
-- vendedor_id/asignado_supervisor_id y haga visible una tarea a otra cartera.
revoke update on table crm.tareas from authenticated;
grant update (vence_en, confirmada_en) on table crm.tareas to authenticated;

-- Con privilegio por columna, el cliente autenticado no puede presentar un
-- destino alternativo en UPDATE. La policy conserva el gate de fila activa;
-- los cambios de tenencia legítimos siguen ocurriendo desde los triggers/RPCs
-- SECURITY DEFINER que sincronizan cliente y lead.
alter policy tareas_update on crm.tareas
with check (activo = true);

-- ---------------------------------------------------------------------------
-- 4. Numeración automática serializada por año.
-- ---------------------------------------------------------------------------

create or replace function private.siguiente_numero_contrato(p_anio integer)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_seq integer;
begin
  if p_anio is null or p_anio < 2000 or p_anio > 9999 then
    raise exception 'Año de contrato inválido' using errcode = '22023';
  end if;

  -- La pareja (namespace, año) permite concurrencia entre años y serializa
  -- solamente a quienes calculan el siguiente número del mismo año.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.contratos.numero_contrato'),
    p_anio
  );

  -- Solo el namespace automático AC-AAAA-(1..4 dígitos) participa del
  -- contador. Un número explícito malformado o con miles de dígitos jamás
  -- puede provocar overflow al convertir ni bloquear futuras altas.
  select coalesce(pg_catalog.max(
           pg_catalog.split_part(c.numero_contrato, '-', 3)::integer
         ), 0) + 1
    into v_seq
  from public.contratos c
  where c.numero_contrato ~ (
    '^AC-' || p_anio::text || '-[0-9]{1,4}$'
  );

  if v_seq > 9999 then
    raise exception 'Se agotó la numeración automática AC-% para el año %',
      p_anio, p_anio
      using errcode = '22003';
  end if;

  return 'AC-' || p_anio || '-' || pg_catalog.lpad(v_seq::text, 4, '0');
end;
$function$;

comment on function private.siguiente_numero_contrato(integer) is
  'Genera AC-AAAA-NNNN bajo advisory xact lock por año; evita colisiones max()+1 entre transacciones concurrentes.';

revoke all on function private.siguiente_numero_contrato(integer)
  from public, anon, authenticated, service_role;

create or replace function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_gestor_cartera boolean := (select public.es_gestor_cartera());
  v_rol_crm text := private.rol_crm(v_uid);
  v_es_gerencia_crm boolean := coalesce(v_rol_crm = 'gerencia', false);
  v_es_crm_catalogado boolean :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and nullif(current_setting('crm.producto_condicion_id', true), '') is not null;
  v_cliente_id uuid;
  v_numero text := nullif(btrim(p_contrato->>'numero_contrato'), '');
  v_categoria text := p_contrato->>'categoria';
  v_moneda text := upper(coalesce(nullif(p_contrato->>'moneda', ''), 'PEN'));
  v_capital numeric;
  v_anio integer := extract(year from now() at time zone 'America/Lima')::integer;
  v_contrato_id uuid;
  v_fecha_operacion date;
  v_periodo date;
  v_cuota jsonb;
  v_asesor_id uuid;
  v_asesor_rol text;
  v_operacion_id uuid;
  v_origen_id uuid;
  v_origen public.contratos%rowtype;
  v_capital_renovado numeric;
  v_capital_adicional numeric;
  v_primer_periodo date;
  v_upgrade_elegible boolean;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
    v_capital := (p_contrato->>'capital')::numeric;
  exception when invalid_text_representation then
    raise exception 'Cliente o capital inválido' using errcode = '22023';
  end;

  -- Vincula autorización y escritura a la misma versión de la cartera. Una
  -- reasignación concurrente espera este lock; si ganó antes, aquí ya se lee el
  -- nuevo Analista y el anterior queda fuera del gate.
  select p.asesor_perfil_id into v_asesor_id
  from public.perfiles p
  where p.id = v_cliente_id and p.rol = 'cliente'
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if not (
    v_es_analista or v_es_gestor_cartera or v_es_gerencia_crm or v_es_crm_catalogado
  ) or not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;
  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (Nuevo, Renovación o Upgrade)';
  end if;
  if v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;

  -- Las operaciones de cartera necesitan un dueño congelado. No se atribuye a
  -- quien digitó: se atribuye al Analista de perfiles.asesor_perfil_id.
  if v_categoria in ('renovacion', 'upgrade') then
    select e.rol_crm into v_asesor_rol
    from crm.equipo e
    where e.perfil_id = v_asesor_id and e.activo
    for share;
    if v_asesor_id is null
       or not found
       or v_asesor_rol not in ('vendedor', 'supervisor') then
      raise exception using
        errcode = '22023',
        message = 'Asigna un Analista activo al cliente antes de registrar la operación';
    end if;
  end if;

  if v_categoria = 'renovacion' then
    begin
      v_origen_id := (p_contrato->>'contrato_origen_id')::uuid;
      v_capital_renovado := (p_contrato->>'capital_renovado')::numeric;
      v_capital_adicional := coalesce((p_contrato->>'capital_adicional')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'Completa contrato anterior, capital renovado y adicional válidos'
        using errcode = '22023';
    end;

    select * into v_origen
    from public.contratos c
    where c.id = v_origen_id
    for update;
    if not found then
      raise exception 'El contrato a renovar no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from v_cliente_id then
      raise exception 'El contrato anterior pertenece a otro cliente' using errcode = '22023';
    end if;
    if v_origen.estado not in ('activo', 'vencido') or v_origen.renovado_a_id is not null then
      raise exception 'El contrato anterior ya fue cerrado o renovado' using errcode = 'P0409';
    end if;
    if v_origen.fecha_vencimiento > (now() at time zone 'America/Lima')::date then
      raise exception 'La renovación solo se registra cuando el contrato llega a su fecha fin'
        using errcode = '22023';
    end if;
    if v_origen.moneda is distinct from v_moneda then
      raise exception 'La renovación debe conservar la moneda del contrato anterior'
        using errcode = '22023';
    end if;
    if (p_contrato->>'fecha_inicio')::date < v_origen.fecha_vencimiento then
      raise exception 'El contrato nuevo no puede iniciar antes del vencimiento anterior'
        using errcode = '22023';
    end if;
    if v_capital_renovado <= 0 or v_capital_renovado > v_origen.capital then
      raise exception 'El capital renovado debe ser mayor a cero y no superar el contrato anterior'
        using errcode = '22023';
    end if;
    if v_capital_adicional < 0 then
      raise exception 'El capital adicional no puede ser negativo' using errcode = '22023';
    end if;
    if v_capital is distinct from (v_capital_renovado + v_capital_adicional) then
      raise exception 'El nuevo capital debe ser capital renovado + capital adicional'
        using errcode = '22023';
    end if;
  end if;

  if v_numero is null then
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, notas_internas,
    categoria, estado, creado_por
  ) values (
    v_cliente_id, v_numero, v_capital, v_moneda,
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria, 'activo', v_uid
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;

  if p_cronograma is null or jsonb_typeof(p_cronograma) <> 'array'
     or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacío';
  end if;
  for v_cuota in select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id, numero_cuota, fecha_programada, monto_programado, estado, tipo
    ) values (
      v_contrato_id, (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric, 'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;
  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(v_contrato_id, p_contrato->'titulares');
  end if;

  if v_categoria in ('renovacion', 'upgrade') then
    v_periodo := date_trunc('month', v_fecha_operacion)::date;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.operaciones_cartera'),
      pg_catalog.hashtext(v_cliente_id::text || '|' || v_periodo::text)
    );

    if v_categoria = 'upgrade' then
      select min(date_trunc('month', c.fecha_cierre_comercial)::date)
        into v_primer_periodo
      from public.contratos c
      where c.cliente_id = v_cliente_id;
      v_upgrade_elegible := v_periodo > v_primer_periodo;
    else
      v_upgrade_elegible := true;
    end if;

    insert into crm.operaciones_cartera (
      cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
      fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
      elegible_conversion, desglose_completo, fuente, creado_por
    ) values (
      v_cliente_id, v_asesor_id, v_categoria, v_origen_id, v_contrato_id,
      v_fecha_operacion, v_periodo, v_moneda,
      case when v_categoria = 'renovacion' then v_capital_renovado end,
      case when v_categoria = 'renovacion' then v_capital_adicional end,
      v_upgrade_elegible, true, 'flujo_cartera', v_uid
    ) returning id into v_operacion_id;
  end if;

  if v_categoria = 'renovacion' then
    update public.cronograma_pagos
       set estado = 'trasladado'
     where contrato_id = v_origen_id and estado in ('pendiente', 'vencido');
    update public.contratos
       set estado = 'renovado', renovado_a_id = v_contrato_id,
           cerrado_en = now(), cerrado_por = v_uid
     where id = v_origen_id;
  end if;

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero,
    'operacion_id', v_operacion_id,
    'conversion_elegible', case
      when v_categoria in ('renovacion', 'upgrade') then v_upgrade_elegible
    end
  );
end;
$function$;

revoke all on function public.crear_contrato(jsonb,jsonb) from public, anon;
grant execute on function public.crear_contrato(jsonb,jsonb) to authenticated, service_role;

comment on function public.crear_contrato(jsonb,jsonb) is
  'Alta atómica de contrato y cronograma; renovaciones/upgrades conservan su ledger. La numeración automática usa private.siguiente_numero_contrato y es segura ante concurrencia.';

-- ---------------------------------------------------------------------------
-- 5. Postflight estructural. Si una garantía queda a medias, revierte todo.
-- ---------------------------------------------------------------------------

do $postflight$
declare
  v_def text;
  v_check text;
begin
  if exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and (
        (p.rol = 'directorio' and e.rol_crm <> 'directorio')
        or (p.rol <> 'directorio' and e.rol_crm = 'directorio')
      )
  ) then
    raise exception 'Postflight: Directorio Portal/CRM sigue desalineado';
  end if;

  if exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
  ) and not exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and e.rol_crm = 'gerencia' and p.rol <> 'directorio'
  ) then
    raise exception 'Postflight: la organización quedó sin Gerencia operativa real';
  end if;

  if exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo is true and p.activo is true
      and e.rol_crm = 'directorio' and p.rol = 'directorio'
      and (
        exists (select 1 from crm.equipo h
                where h.supervisor_id = e.perfil_id and h.activo is true)
        or exists (select 1 from crm.leads l
                   where (l.vendedor_id = e.perfil_id
                       or l.asignado_supervisor_id = e.perfil_id)
                     and l.activo is true
                     and l.etapa not in ('convertido','descartado'))
        or exists (select 1 from crm.tareas t
                   where (t.vendedor_id = e.perfil_id
                       or t.asignado_supervisor_id = e.perfil_id)
                     and t.activo is true and t.estado = 'pendiente')
        or exists (select 1 from public.perfiles c
                   where c.rol = 'cliente' and c.activo is true
                     and c.asesor_perfil_id = e.perfil_id)
      )
  ) then
    raise exception 'Postflight: Directorio conserva responsabilidad operativa';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.perfiles'::pg_catalog.regclass
      and t.tgname = 'trg_perfiles_equipo_rol_invariante'
      and not t.tgisinternal
  ) then
    raise exception 'Postflight: falta el trigger de invariante Portal/CRM';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', 'crm.cliente_detalle_fn(uuid)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cliente_detalle_fn(uuid)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'service_role', 'crm.cliente_detalle_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'Postflight: ACL inesperada en crm.cliente_detalle_fn';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', 'crm.clientes_basicos_fn()', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.clientes_basicos_fn()', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'service_role', 'crm.clientes_basicos_fn()', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'service_role', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'authenticated', 'private.siguiente_numero_contrato(integer)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'service_role', 'private.siguiente_numero_contrato(integer)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'authenticated', 'private.validar_equipo_usuario_crm(uuid)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'service_role', 'private.validar_equipo_usuario_crm(uuid)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'authenticated', 'private.cliente_ids_visibles_crm()', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'service_role', 'private.cliente_ids_visibles_crm()', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'private.puede_gestionar_tarea_cliente(uuid,uuid)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'private.puede_gestionar_tarea_cliente(uuid,uuid)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'service_role', 'private.puede_gestionar_tarea_cliente(uuid,uuid)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'private.puede_asignar_destino_tarea(uuid,uuid)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'private.puede_asignar_destino_tarea(uuid,uuid)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'service_role', 'private.puede_asignar_destino_tarea(uuid,uuid)', 'EXECUTE'
     ) then
    raise exception 'Postflight: ACL inesperada en funciones de cartera';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    where p.oid = any(array[
      'private.rol_crm(uuid)'::pg_catalog.regprocedure::oid,
      'private.es_lector_global()'::pg_catalog.regprocedure::oid,
      'private.validar_equipo_usuario_crm(uuid)'::pg_catalog.regprocedure::oid,
      'private.trg_perfiles_equipo_rol_invariante()'::pg_catalog.regprocedure::oid,
      'private.cliente_ids_visibles_crm()'::pg_catalog.regprocedure::oid,
      'crm.clientes_basicos_fn()'::pg_catalog.regprocedure::oid,
      'crm.cliente_detalle_fn(uuid)'::pg_catalog.regprocedure::oid,
      'private.trg_tareas_before_insert()'::pg_catalog.regprocedure::oid,
      'private.puede_gestionar_tarea_cliente(uuid,uuid)'::pg_catalog.regprocedure::oid,
      'private.puede_asignar_destino_tarea(uuid,uuid)'::pg_catalog.regprocedure::oid,
      'private.siguiente_numero_contrato(integer)'::pg_catalog.regprocedure::oid,
      'public.crear_contrato(jsonb,jsonb)'::pg_catalog.regprocedure::oid
    ])
      and (
        r.rolname <> 'postgres'
        or p.prosecdef is not true
        or not (
          coalesce(p.proconfig, '{}'::text[])
          @> array['search_path=""']::text[]
        )
      )
  ) then
    raise exception 'Postflight: owner, SECURITY DEFINER o search_path inseguros';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    join pg_catalog.pg_roles r on r.oid = c.relowner
    where n.nspname = 'crm' and c.relname = 'clientes_basicos'
      and c.relkind = 'v'
      and r.rolname = 'postgres'
      and coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']
  ) or (
    select count(*)
    from information_schema.columns c
    where c.table_schema = 'crm' and c.table_name = 'clientes_basicos'
  ) <> 12 then
    raise exception 'Postflight: clientes_basicos no convergió a la vista invoker de 12 columnas';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'crm.clientes_basicos', 'SELECT'
     ) or not pg_catalog.has_table_privilege(
       'service_role', 'crm.clientes_basicos', 'SELECT'
     ) or pg_catalog.has_table_privilege(
       'anon', 'crm.clientes_basicos', 'SELECT'
  ) then
    raise exception 'Postflight: ACL inesperada en crm.clientes_basicos';
  end if;

  if pg_catalog.obj_description(
       'crm.clientes_basicos_fn()'::pg_catalog.regprocedure,
       'pg_proc'
     ) is null then
    raise exception 'Postflight: falta documentar crm.clientes_basicos_fn';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.es_lector_global()'::pg_catalog.regprocedure
  );
  if v_def not ilike '%private.rol_crm(a.uid)%'
     or v_def not ilike '%not exists%crm.equipo%' then
    raise exception 'Postflight: es_lector_global conserva una puerta Directorio desalineada';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'crm.cliente_detalle_fn(uuid)'::pg_catalog.regprocedure
  );
  if v_def not ilike '%cuentas_bancarias_visibles%'
     or v_def not ilike '%private.puede_gestionar_cuentas_cliente%'
     or v_def not ilike '%case when v_banca_visible%'
     or v_def not ilike '%case when private.es_lector_global() then null else v_cliente.domicilio end%' then
    raise exception 'Postflight: el detalle no separa las capacidades de domicilio, banca embebida y ledger';
  end if;

  select p.with_check into v_check
  from pg_catalog.pg_policies p
  where p.schemaname = 'crm' and p.tablename = 'tareas'
    and p.policyname = 'tareas_insert';
  if v_check not ilike '%private.puede_gestionar_tarea_cliente%'
     or v_check not ilike '%private.puede_asignar_destino_tarea%'
     or v_check ilike '%from perfiles%' then
    raise exception 'Postflight: tareas_insert sigue dependiendo de la RLS de perfiles';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.puede_asignar_destino_tarea(uuid,uuid)'::pg_catalog.regprocedure
  );
  if v_def not ilike '%p_vendedor_id = a.uid%'
     or v_def not ilike '%e.supervisor_id%'
     or v_def not ilike '%private.vendedor_ids_visibles(a.uid)%' then
    raise exception 'Postflight: la autorización de destinos de tarea perdió su semántica canónica';
  end if;

  if pg_catalog.has_table_privilege(
       'authenticated', 'crm.tareas', 'UPDATE'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', 'crm.tareas', 'vence_en', 'UPDATE'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', 'crm.tareas', 'confirmada_en', 'UPDATE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', 'crm.tareas', 'vendedor_id', 'UPDATE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', 'crm.tareas', 'asignado_supervisor_id', 'UPDATE'
     ) then
    raise exception 'Postflight: authenticated conserva UPDATE amplio o de tenencia sobre crm.tareas';
  end if;

  select pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid)
    into v_check
  from pg_catalog.pg_policy p
  where p.polrelid = 'crm.tareas'::pg_catalog.regclass
    and p.polname = 'tareas_update';
  if v_check not ilike '%activo = true%'
     or v_check ilike '%vendedor_ids_visibles%' then
    raise exception 'Postflight: tareas_update conserva un gate de destino incompatible con el UPDATE por columnas';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.trg_tareas_before_insert()'::pg_catalog.regprocedure
  );
  if v_def not ilike '%elsif new.perfil_id is not null%'
     or v_def not ilike '%new.vendedor_id := v_cliente.asesor_perfil_id%'
     or v_def not ilike '%v_equipo.supervisor_id%'
     or v_def not ilike '%crm.leads where id = new.lead_id for share%'
     or v_def not ilike '%p.rol = ''cliente''%for share%' then
    raise exception 'Postflight: el trigger de tareas no deriva y bloquea el destino canónico';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'public.crear_contrato(jsonb,jsonb)'::pg_catalog.regprocedure
  );
  if v_def not ilike '%private.siguiente_numero_contrato(v_anio)%'
     or v_def ilike '%max(nullif(regexp_replace(split_part(c.numero_contrato%'
     or v_def not ilike '%insert into crm.operaciones_cartera%'
     or v_def not ilike '%capital_renovado%'
     or v_def not ilike '%capital_adicional%'
     or v_def not ilike '%from public.perfiles p%for share%'
     or v_def not ilike '%from crm.equipo e%for share%'
     or v_def not ilike '%now() at time zone ''America/Lima''%' then
    raise exception 'Postflight: crear_contrato perdió semántica o conserva max()+1 sin lock';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.siguiente_numero_contrato(integer)'::pg_catalog.regprocedure
  );
  if v_def not ilike '%pg_advisory_xact_lock%'
     or v_def not ilike '%if v_seq > 9999%'
     or v_def not ilike '%errcode = ''22003''%'
     or v_def not ilike '%[0-9]{1,4}$%' then
    raise exception 'Postflight: la numeración no serializa o no falla al agotarse';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.cliente_ids_visibles_crm()'::pg_catalog.regprocedure
  );
  if v_def not ilike '%p.asesor_perfil_id is null%'
     or v_def not ilike '%p.creado_por in%'
     or v_def not ilike '%private.es_lector_global()%'
     or v_def not ilike '%private.vendedor_ids_visibles%' then
    raise exception 'Postflight: el ámbito común de clientes está incompleto';
  end if;
end;
$postflight$;

commit;
