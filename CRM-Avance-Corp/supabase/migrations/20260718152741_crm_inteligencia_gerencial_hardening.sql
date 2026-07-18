-- Inteligencia Gerencial V2: SLA global inmutable, RPC con puente de minimo
-- privilegio y contrato monetario explicito.
--
-- Rollout compatible:
--   1. Esta migracion conserva la RPC JSON V1 para el frontend anterior.
--   2. Agrega metricas_distribucion_leads_v2_fn para el frontend nuevo.
--   3. Un rollback de frontend vuelve a V1 sin revertir historia ni columnas.

begin;

set local lock_timeout = '10s';

-- El reloj principal vive en el ciclo del lead. Una reasignacion abre otro
-- episodio operativo, pero no cambia este instante.
alter table crm.leads
  add column sla_global_iniciado_en timestamptz,
  add column sla_global_aproximado boolean not null default false;

with reaperturas as (
  select
    a.lead_id,
    (row_number() over (
      partition by a.lead_id
      order by a.creado_en, a.id
    ) + 1)::integer as ciclo_n,
    a.creado_en
  from crm.actividades a
  where a.tipo = 'cambio_etapa'
    and a.metadata ->> 'etapa_anterior' = 'descartado'
    and a.metadata ->> 'etapa_nueva' = 'nuevo'
)
update crm.leads l
set
  sla_global_iniciado_en = case
    when l.ciclo_actual = 1 then l.creado_en
    else coalesce(
      (
        select r.creado_en
        from reaperturas r
        where r.lead_id = l.id
          and r.ciclo_n = l.ciclo_actual
          and r.creado_en <= coalesce((
            select min(la.asignado_en)
            from crm.lead_asignaciones la
            where la.lead_id = l.id
              and la.ciclo_n = l.ciclo_actual
          ), 'infinity'::timestamptz)
      ),
      (
        select min(la.asignado_en)
        from crm.lead_asignaciones la
        where la.lead_id = l.id
          and la.ciclo_n = l.ciclo_actual
      ),
      l.creado_en
    )
  end,
  sla_global_aproximado = l.ciclo_actual > 1 and not exists (
    select 1
    from reaperturas r
    where r.lead_id = l.id
      and r.ciclo_n = l.ciclo_actual
      and r.creado_en <= coalesce((
        select min(la.asignado_en)
        from crm.lead_asignaciones la
        where la.lead_id = l.id
          and la.ciclo_n = l.ciclo_actual
      ), 'infinity'::timestamptz)
  );

alter table crm.leads
  alter column sla_global_iniciado_en set default statement_timestamp(),
  alter column sla_global_iniciado_en set not null;

comment on column crm.leads.sla_global_iniciado_en is
  'Inicio inmutable del SLA principal para el ciclo actual; no cambia al asignar, transferir o parquear.';
comment on column crm.leads.sla_global_aproximado is
  'True solo cuando el inicio del ciclo historico no pudo reconstruirse desde un evento estructurado.';

-- Cada fotografia del ledger conserva el mismo inicio global de su ciclo. Esto
-- permite reconstruir el SLA aunque el lead se transfiera o cierre despues.
alter table crm.lead_asignaciones
  add column sla_global_iniciado_en timestamptz,
  add column sla_global_aproximado boolean;

with reaperturas as (
  select
    a.lead_id,
    (row_number() over (
      partition by a.lead_id
      order by a.creado_en, a.id
    ) + 1)::integer as ciclo_n,
    a.creado_en
  from crm.actividades a
  where a.tipo = 'cambio_etapa'
    and a.metadata ->> 'etapa_anterior' = 'descartado'
    and a.metadata ->> 'etapa_nueva' = 'nuevo'
),
primeras_asignaciones as (
  select lead_id, ciclo_n, min(asignado_en) as primera_asignacion_en
  from crm.lead_asignaciones
  group by lead_id, ciclo_n
)
update crm.lead_asignaciones la
set
  sla_global_iniciado_en = case
    when la.ciclo_n = 1 then l.creado_en
    when r.creado_en is not null and r.creado_en <= pa.primera_asignacion_en
      then r.creado_en
    else pa.primera_asignacion_en
  end,
  sla_global_aproximado = case
    when la.ciclo_n = 1 then false
    else r.creado_en is null or r.creado_en > pa.primera_asignacion_en
  end
from crm.leads l
join primeras_asignaciones pa on pa.lead_id = l.id
left join reaperturas r
  on r.lead_id = pa.lead_id
 and r.ciclo_n = pa.ciclo_n
where l.id = la.lead_id
  and pa.ciclo_n = la.ciclo_n;

alter table crm.lead_asignaciones
  add constraint lead_asignaciones_sla_global_orden_valido
    check (sla_global_iniciado_en <= asignado_en) not valid;

alter table crm.lead_asignaciones
  validate constraint lead_asignaciones_sla_global_orden_valido;

alter table crm.lead_asignaciones
  alter column sla_global_iniciado_en set not null,
  alter column sla_global_aproximado set not null,
  alter column sla_global_aproximado set default false;

create index lead_asignaciones_sla_global_cohorte_idx
  on crm.lead_asignaciones (sla_global_iniciado_en, lead_id, ciclo_n);

comment on column crm.lead_asignaciones.sla_global_iniciado_en is
  'Inicio del SLA global del ciclo, compartido por todos sus episodios de asignacion.';

-- El cliente no gobierna el reloj global. El trigger 00 de tenencia fija
-- creado_en/ciclo_actual primero; el nombre 01 garantiza que este corre despues.
create or replace function private.trg_leads_sla_global()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  if tg_op = 'INSERT' then
    if new.creado_en is null then
      raise exception 'No existe timestamp de ingreso para iniciar el SLA global';
    end if;
    new.sla_global_iniciado_en := new.creado_en;
    new.sla_global_aproximado := false;
    return new;
  end if;

  if new.ciclo_actual is distinct from old.ciclo_actual then
    if new.ciclo_actual <> old.ciclo_actual + 1 then
      raise exception 'Transicion de ciclo invalida para el SLA global';
    end if;
    new.sla_global_iniciado_en := statement_timestamp();
    new.sla_global_aproximado := false;
  else
    new.sla_global_iniciado_en := old.sla_global_iniciado_en;
    new.sla_global_aproximado := old.sla_global_aproximado;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_leads_01_sla_global on crm.leads;
create trigger trg_leads_01_sla_global
before insert or update on crm.leads
for each row
execute function private.trg_leads_sla_global();

-- Completa la fotografia antes del guard inmutable ya existente. El trigger
-- del ledger sigue siendo el unico escritor autorizado.
create or replace function private.trg_lead_asignaciones_completar_sla_global()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_inicio timestamptz;
  v_aproximado boolean;
  v_ciclo integer;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  select
    l.sla_global_iniciado_en,
    l.sla_global_aproximado,
    l.ciclo_actual
  into v_inicio, v_aproximado, v_ciclo
  from crm.leads l
  where l.id = new.lead_id;

  if not found or v_inicio is null then
    raise exception 'El lead no tiene un inicio de SLA global valido';
  end if;
  if new.ciclo_n is distinct from v_ciclo then
    raise exception 'El episodio no pertenece al ciclo actual del lead';
  end if;
  if v_inicio > new.asignado_en then
    raise exception 'El SLA global no puede iniciar despues de la asignacion';
  end if;

  new.sla_global_iniciado_en := v_inicio;
  new.sla_global_aproximado := v_aproximado;
  return new;
end;
$function$;

create trigger trg_lead_asignaciones_00_fill_sla_global
before insert or update on crm.lead_asignaciones
for each row
execute function private.trg_lead_asignaciones_completar_sla_global();

create or replace function private.trg_lead_asignaciones_sla_global_inmutable()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  if tg_op = 'UPDATE'
     and (
       old.sla_global_iniciado_en is distinct from new.sla_global_iniciado_en
       or old.sla_global_aproximado is distinct from new.sla_global_aproximado
     ) then
    raise exception 'El inicio del SLA global de un episodio es inmutable';
  end if;
  return new;
end;
$function$;

create trigger trg_lead_asignaciones_00_sla_global_inmutable
before update on crm.lead_asignaciones
for each row
execute function private.trg_lead_asignaciones_sla_global_inmutable();

revoke all on function private.trg_leads_sla_global()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_lead_asignaciones_completar_sla_global()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_lead_asignaciones_sla_global_inmutable()
  from public, anon, authenticated, service_role;

-- SLA principal por ciclo. Cuenta la espera desde el ingreso/reapertura aunque
-- el lead este sin asignar, parqueado o pase por varios analistas. No descuenta
-- pausas: actualmente ningun estado puede maquillar el reloj global.
create or replace function private.metricas_sla_global_core(
  p_desde date,
  p_hasta date,
  p_ahora timestamptz
)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
with
parametros as (
  select
    (p_desde::timestamp at time zone 'America/Lima') as inicio,
    ((p_hasta + 1)::timestamp at time zone 'America/Lima') as fin,
    p_ahora as ahora
),
ciclos_ledger as (
  select
    la.lead_id,
    la.ciclo_n,
    min(la.sla_global_iniciado_en) as sla_iniciado_en,
    bool_or(la.sla_global_aproximado) as aproximado,
    case
      when l.ciclo_actual = la.ciclo_n
       and l.activo = true
       and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
        then null
      else coalesce(
        max(la.resultado_en) filter (where la.resultado is not null),
        max(la.finalizado_en)
      )
    end as ciclo_finalizado_en,
    greatest(count(*) - 1, 0)::integer as reasignaciones
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  group by
    la.lead_id,
    la.ciclo_n,
    l.ciclo_actual,
    l.activo,
    l.etapa
),
ciclos_sin_episodio as (
  select
    l.id as lead_id,
    l.ciclo_actual as ciclo_n,
    l.sla_global_iniciado_en as sla_iniciado_en,
    l.sla_global_aproximado as aproximado,
    null::timestamptz as ciclo_finalizado_en,
    0::integer as reasignaciones
  from crm.leads l
  where l.activo = true
    and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and not exists (
      select 1
      from crm.lead_asignaciones la
      where la.lead_id = l.id
        and la.ciclo_n = l.ciclo_actual
    )
),
ciclos as (
  select * from ciclos_ledger
  union all
  select * from ciclos_sin_episodio
),
contactos as (
  select
    c.lead_id,
    c.ciclo_n,
    c.sla_iniciado_en,
    c.aproximado,
    c.ciclo_finalizado_en,
    c.reasignaciones,
    min(a.creado_en) as primera_gestion_en
  from ciclos c
  cross join parametros p
  left join crm.actividades a
    on a.lead_id = c.lead_id
   and a.tipo in (
     'llamada_realizada',
     'llamada_no_contestada',
     'whatsapp_enviado',
     'whatsapp_recibido',
     'reunion_realizada'
   )
   and a.creado_en >= c.sla_iniciado_en
   and (c.ciclo_finalizado_en is null or a.creado_en < c.ciclo_finalizado_en)
   and a.creado_en <= p.ahora
  group by
    c.lead_id,
    c.ciclo_n,
    c.sla_iniciado_en,
    c.aproximado,
    c.ciclo_finalizado_en,
    c.reasignaciones
),
medidas as (
  select
    c.*,
    case
      when c.primera_gestion_en is not null
        then extract(epoch from (c.primera_gestion_en - c.sla_iniciado_en)) / 60.0
      else null
    end as primera_gestion_minutos,
    (
      c.primera_gestion_en is not null
      or coalesce(c.ciclo_finalizado_en, p.ahora)
        >= c.sla_iniciado_en + interval '24 hours'
    ) as sla_evaluable,
    (
      c.primera_gestion_en is not null
      and c.primera_gestion_en <= c.sla_iniciado_en + interval '24 hours'
    ) as sla_en_24h
  from contactos c
  cross join parametros p
),
cohorte as (
  select m.*
  from medidas m
  cross join parametros p
  where m.sla_iniciado_en >= p.inicio
    and m.sla_iniciado_en < p.fin
)
select jsonb_build_object(
  'cohorte_ciclos', (select count(*) from cohorte),
  'cohorte_leads_unicos', (select count(distinct lead_id) from cohorte),
  'contactos', (select count(*) from cohorte where primera_gestion_en is not null),
  'sla_evaluables', (select count(*) from cohorte where sla_evaluable),
  'sla_en_24h', (select count(*) from cohorte where sla_en_24h),
  'primer_contacto_mediana_minutos', (
    select round((percentile_cont(0.5) within group (
      order by primera_gestion_minutos
    ))::numeric, 1)
    from cohorte
    where primera_gestion_minutos is not null
  ),
  'sin_contacto_vencidos_actuales', (
    select count(*)
    from medidas m
    cross join parametros p
    where m.ciclo_finalizado_en is null
      and m.primera_gestion_en is null
      and p.ahora >= m.sla_iniciado_en + interval '24 hours'
  ),
  'reasignaciones_cohorte', coalesce((select sum(reasignaciones) from cohorte), 0),
  'ciclos_aproximados_cohorte', (select count(*) from cohorte where aproximado)
);
$function$;

-- Adapta la fotografia V1 sin duplicar sus calculos de rangos, moneda,
-- capacidad, conversion o colas. Solo cambia la semantica explicita de SLA.
create or replace function private.metricas_distribucion_leads_v2_core(
  p_desde date,
  p_hasta date,
  p_ahora timestamptz
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_sla jsonb;
  v_analistas jsonb;
begin
  v_base := private.metricas_distribucion_leads_core(p_desde, p_hasta, p_ahora);
  v_sla := private.metricas_sla_global_core(p_desde, p_hasta, p_ahora);

  v_base := jsonb_set(v_base, '{version}', '2'::jsonb);
  v_base := jsonb_set(
    v_base,
    '{cohorte}',
    (v_base->'cohorte') || jsonb_build_object(
      'criterio_sla_global', 'ciclo_sla_global_iniciado_en',
      'politica_pausas', 'SIN_DESCUENTO'
    )
  );
  v_base := jsonb_set(
    v_base,
    '{alcances}',
    ((v_base->'alcances') - 'operacion_sla') || jsonb_build_object(
      'montos', 'SEPARADOS_SIN_CONVERSION',
      'sla_principal', 'GLOBAL_POR_CICLO',
      'sla_operativo', 'POR_EPISODIO_DE_ASIGNACION'
    )
  );
  v_base := jsonb_set(
    v_base,
    '{resumen}',
    ((v_base->'resumen') - 'sla_evaluables' - 'sla_en_24h') || jsonb_build_object(
      'sla_global_ciclos_cohorte', v_sla->'cohorte_ciclos',
      'sla_global_leads_unicos_cohorte', v_sla->'cohorte_leads_unicos',
      'sla_global_contactos', v_sla->'contactos',
      'sla_global_evaluables', v_sla->'sla_evaluables',
      'sla_global_en_24h', v_sla->'sla_en_24h',
      'primer_contacto_global_mediana_minutos', v_sla->'primer_contacto_mediana_minutos',
      'sla_global_sin_contacto_vencidos_actuales', v_sla->'sin_contacto_vencidos_actuales',
      'reasignaciones_cohorte', v_sla->'reasignaciones_cohorte'
    )
  );

  select coalesce(jsonb_agg(
    jsonb_set(
      elemento,
      '{operacion}',
      ((elemento->'operacion')
        - 'contactos'
        - 'sla_evaluables'
        - 'sla_en_24h'
        - 'primer_contacto_mediana_minutos')
      || jsonb_build_object(
        'contactos_asignacion', elemento#>'{operacion,contactos}',
        'sla_asignacion_evaluables', elemento#>'{operacion,sla_evaluables}',
        'sla_asignacion_en_24h', elemento#>'{operacion,sla_en_24h}',
        'primer_contacto_asignacion_mediana_minutos',
          elemento#>'{operacion,primer_contacto_mediana_minutos}'
      )
    ) order by orden
  ), '[]'::jsonb)
  into v_analistas
  from jsonb_array_elements(v_base->'analistas') with ordinality as filas(elemento, orden);

  v_base := jsonb_set(v_base, '{analistas}', v_analistas);
  v_base := jsonb_set(
    v_base,
    '{calidad}',
    (v_base->'calidad') || jsonb_build_object(
      'ciclos_sla_global_aproximados_cohorte', v_sla->'ciclos_aproximados_cohorte'
    )
  );

  return v_base;
end;
$function$;

-- Puente sin login, sin acceso a tablas y sin BYPASSRLS. Es propietario de las
-- RPC expuestas, pero solo puede ejecutar un unico entrypoint private que vuelve
-- a validar identidad/rol antes de leer datos con el propietario privilegiado.
do $role$
declare
  v_role record;
begin
  if not exists (select 1 from pg_roles where rolname = 'crm_metricas_bridge') then
    execute 'create role crm_metricas_bridge nologin noinherit';
  end if;

  select oid, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
    into strict v_role
  from pg_roles
  where rolname = 'crm_metricas_bridge';

  if v_role.rolsuper
     or v_role.rolcreatedb
     or v_role.rolcreaterole
     or v_role.rolreplication
     or v_role.rolbypassrls
     or exists (select 1 from pg_auth_members where member = v_role.oid) then
    raise exception 'crm_metricas_bridge ya existe con privilegios incompatibles; requiere saneamiento por un administrador de base de datos'
      using errcode = '42501';
  end if;

  -- Supabase ejecuta migraciones con CREATEROLE, no con SUPERUSER. Por eso los
  -- atributos reservados se verifican arriba y aqui solo se fuerzan los que ese
  -- rol de migracion puede modificar de forma portable.
  execute 'alter role crm_metricas_bridge nologin noinherit';
end;
$role$;

grant usage on schema private to crm_metricas_bridge;

create or replace function private.metricas_distribucion_leads_autorizada(
  p_desde date,
  p_hasta date,
  p_version smallint
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
begin
  if v_actor is null or not (
    exists (
      select 1
      from crm.equipo e
      join public.perfiles p on p.id = e.perfil_id
      where e.perfil_id = v_actor
        and e.rol_crm = 'gerencia'
        and e.activo = true
        and p.activo = true
    )
    or private.es_lector_global()
  ) then
    raise exception 'Solo Gerencia o un lector global puede consultar estas metricas'
      using errcode = '42501';
  end if;

  if p_desde is null
     or p_hasta is null
     or p_desde > p_hasta
     or p_hasta > v_hoy
     or (p_hasta - p_desde) > 365 then
    raise exception 'Periodo invalido: usa fechas hasta hoy y un maximo de 366 dias'
      using errcode = '22023';
  end if;

  if p_version = 1 then
    return private.metricas_distribucion_leads_core(p_desde, p_hasta, v_ahora);
  elsif p_version = 2 then
    return private.metricas_distribucion_leads_v2_core(p_desde, p_hasta, v_ahora);
  end if;

  raise exception 'Version de metricas no soportada' using errcode = '22023';
end;
$function$;

revoke all on function private.metricas_sla_global_core(date, date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function private.metricas_distribucion_leads_v2_core(date, date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function private.metricas_distribucion_leads_autorizada(date, date, smallint)
  from public, anon, authenticated, service_role;
grant execute on function private.metricas_distribucion_leads_autorizada(date, date, smallint)
  to crm_metricas_bridge;

-- V1 permanece para rollback del frontend, pero deja de ser propiedad de un rol
-- con acceso directo a los datos.
create or replace function crm.metricas_distribucion_leads_fn(
  p_desde date,
  p_hasta date
)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select private.metricas_distribucion_leads_autorizada(p_desde, p_hasta, 1::smallint);
$function$;

create or replace function crm.metricas_distribucion_leads_v2_fn(
  p_desde date,
  p_hasta date
)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select private.metricas_distribucion_leads_autorizada(p_desde, p_hasta, 2::smallint);
$function$;

grant usage, create on schema crm to crm_metricas_bridge;
do $membership$
begin
  -- Evita GRANT ... TO CURRENT_USER: la imagen local de Supabase/Postgres 17.6
  -- tiene un fallo del motor con esa forma sintactica. El identificador real se
  -- escapa y produce la operacion equivalente sin depender del nombre del rol.
  execute format('grant crm_metricas_bridge to %I', current_user);
end;
$membership$;
alter function crm.metricas_distribucion_leads_fn(date, date)
  owner to crm_metricas_bridge;
alter function crm.metricas_distribucion_leads_v2_fn(date, date)
  owner to crm_metricas_bridge;
revoke create on schema crm from crm_metricas_bridge;

revoke all on function crm.metricas_distribucion_leads_fn(date, date)
  from public, anon, authenticated, service_role;
revoke all on function crm.metricas_distribucion_leads_v2_fn(date, date)
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_distribucion_leads_fn(date, date)
  to authenticated;
grant execute on function crm.metricas_distribucion_leads_v2_fn(date, date)
  to authenticated;

comment on function crm.metricas_distribucion_leads_fn(date, date) is
  'JSON V1 conservado para rollback; puente sin login y autorizacion private fail-closed.';
comment on function crm.metricas_distribucion_leads_v2_fn(date, date) is
  'JSON V2: SLA global por ciclo sin reinicio, SLA operativo por asignacion y montos separados por moneda.';

do $membership$
begin
  execute format('revoke crm_metricas_bridge from %I', current_user);
end;
$membership$;

commit;
