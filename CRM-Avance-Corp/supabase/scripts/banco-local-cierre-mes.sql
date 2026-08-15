-- ---------------------------------------------------------------------------
-- Banco local para el CIERRE DE MES: calcos del catalogo de produccion
-- ---------------------------------------------------------------------------
-- Monta en un Postgres LOCAL la FORMA de los objetos que tocan las migraciones
-- del cierre de mes, para poder aplicarlas y EJECUTAR el oraculo
-- (`test-cierre-mes.sql`) sin gastar un branch de Supabase.
--
-- No es un fixture de datos: los datos los siembra el oraculo. Esto es el
-- esqueleto — tablas con su forma y funciones con su MISMA FIRMA que produccion.
--
-- USO:
--   createdb cierre_mes_test
--   psql -v ON_ERROR_STOP=1 -d cierre_mes_test -f supabase/scripts/banco-local-cierre-mes.sql
--   # aplicar las migraciones 20260815* SIN sus bloques `do $preflight$`
--   # (anclan md5 de funciones de PRODUCCION y aqui no aplican)
--   psql -v ON_ERROR_STOP=1 -d cierre_mes_test -f supabase/scripts/test-cierre-mes.sql
--
-- ⚠️ Un calco que no respeta la forma real no prueba nada: las tres correcciones
-- que este fichero lleva dentro salieron de que el oraculo daba por buenas cosas
-- que no lo eran. Ver los comentarios marcados con ⚠️.
-- ---------------------------------------------------------------------------
create schema if not exists crm;
create schema if not exists private;
create schema if not exists auth;

do $$ begin
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;

-- Identidad conmutable: cada bloque del oraculo se pone en la piel de quien toca.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.uid', true), '')::uuid $$;

-- ── public ──────────────────────────────────────────────────────────────────
create table if not exists public.perfiles (
  id uuid primary key default gen_random_uuid(),
  nombre_completo text,
  rol text,
  activo boolean default true,
  asesor_perfil_id uuid,
  creado_por uuid,
  creado_en timestamptz default now()
);
create table if not exists public.contratos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid,
  capital numeric,
  moneda text,
  categoria text,
  estado text,
  creado_por uuid,
  creado_en timestamptz default now()
);

-- ── crm ─────────────────────────────────────────────────────────────────────
create table if not exists crm.leads (
  id uuid primary key default gen_random_uuid(),
  nombre_completo text,
  etapa text,
  origen text,
  vendedor_id uuid,
  asignado_supervisor_id uuid,
  perfil_id uuid,
  contrato_id uuid,
  convertido_en timestamptz,
  creado_por uuid,
  creado_en timestamptz default now()
);
create table if not exists crm.lead_asignaciones (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid,
  analista_id uuid,
  resultado text,
  resultado_en timestamptz,
  finalizado_en timestamptz,
  asignado_en timestamptz,
  aproximado boolean default false,
  origen text
);
create table if not exists crm.meta_periodos (
  id uuid primary key default gen_random_uuid(),
  periodo date,
  revision integer,
  publicada_en timestamptz
);
create table if not exists crm.metas_vendedor (
  id uuid primary key default gen_random_uuid(),
  meta_periodo_id uuid,
  vendedor_id uuid,
  supervisor_id uuid,
  conversion_objetivo numeric
);
create table if not exists crm.metas_vendedor_detalle (
  id uuid primary key default gen_random_uuid(),
  meta_vendedor_id uuid,
  categoria text,
  moneda text,
  capital_objetivo numeric,
  contratos_objetivo integer
);
create table if not exists crm.cierres_externos (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid,
  vendedor_id uuid,
  cooperativa text,
  monto numeric,
  moneda text,
  numero_transaccion text,
  anulado_en timestamptz,
  anulado_por uuid,
  motivo_anulacion text,
  creado_en timestamptz default now()
);
create table if not exists crm.cierres_avance_anulados (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid unique,
  acreditado_a uuid,
  motivo text,
  anulado_por uuid,
  anulado_en timestamptz default now()
);
create table if not exists crm.actividades (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid,
  tipo text,
  detalle text,
  metadata jsonb,
  creado_por uuid,
  creado_en timestamptz default now()
);
create table if not exists crm.conversion_pesos (
  vigente_desde date primary key,
  peso_referido numeric,
  nota text,
  creado_en timestamptz default now()
);

-- ── private: calcos con la MISMA firma que producción ────────────────────────
create or replace function private.log_audit_crm() returns trigger language plpgsql as $$
begin return coalesce(new, old); end $$;

-- ⚠️ Devolver siempre 'gerencia' hacia inutil la mitad de las pruebas de gate:
-- un vendedor podia cerrar meses y nadie se enteraba. El calco tiene que
-- distinguir a las personas, como el original.
-- ⚠️ Y tiene que conocer a los CINCO roles, no a tres. Con solo gerencia,
-- supervisor y vendedor, los gates de coordinador y directorio no se pueden
-- probar en ningun sitio — y el directorio es el rol raro del proyecto: un
-- lector global que NO es gerencia. Un calco que no tiene un rol no lo prueba,
-- y no probarlo se parece mucho a que este bien.
create or replace function private.rol_crm(p_perfil_id uuid) returns text
language sql stable as $$
  select case p_perfil_id
    when '11111111-1111-4111-8111-111111111111'::uuid then 'gerencia'
    when '22222222-2222-4222-8222-222222222222'::uuid then 'supervisor'
    when '33333333-3333-4333-8333-333333333333'::uuid then 'vendedor'
    when '88888888-8888-4888-8888-888888888888'::uuid then 'coordinador'
    when '99999999-9999-4999-8999-999999999999'::uuid then 'directorio'
  end $$;

-- En produccion el lector global es EXACTAMENTE el rol `directorio`
-- (`private.es_lector_global`, verificado contra el catalogo el 15/08). El calco
-- que devolvia `false` siempre dejaba esa rama sin ejecutar nunca.
create or replace function private.es_lector_global() returns boolean
  language sql stable as $$
    select (select auth.uid()) = '99999999-9999-4999-8999-999999999999'::uuid $$;

create or replace function private.vendedor_ids_visibles(p_perfil_id uuid) returns setof uuid
language sql stable as $$
  select case private.rol_crm(p_perfil_id)
    when 'vendedor' then p_perfil_id
    when 'supervisor' then '33333333-3333-4333-8333-333333333333'::uuid end
  where private.rol_crm(p_perfil_id) in ('vendedor','supervisor') $$;

create or replace function private.roster_metas_vendedores()
  returns table(vendedor_id uuid, supervisor_id uuid)
  language sql stable as $$ select mv.vendedor_id, mv.supervisor_id from crm.metas_vendedor mv $$;

create or replace function private.vendedores_sin_supervisor()
  returns table(vendedor_id uuid, nombre text, motivo text)
  language sql stable as $$ select null::uuid, null::text, null::text where false $$;

create or replace function private.peso_referido_conversion(p_mes date) returns numeric
  language sql stable as $$ select coalesce((select cp.peso_referido from crm.conversion_pesos cp
    where cp.vigente_desde <= p_mes order by cp.vigente_desde desc limit 1), 0.15) $$;

create or replace function private.etiqueta_mes_es(p_mes date) returns text
  language sql immutable as $$ select to_char(p_mes, 'TMMonth') $$;

create or replace function private.filtrar_desglose_sujetos_crm(
  p_payload jsonb, p_clave text, p_clave_id text, p_roles text[]) returns jsonb
  language sql immutable as $$ select p_payload $$;

create or replace function private.vendedor_acreditado_del_cierre(p_lead_id uuid) returns uuid
  language sql stable as $$ select l.vendedor_id from crm.leads l where l.id = p_lead_id $$;

create or replace function private.contratos_afectados_por_anulacion(p_lead_id uuid) returns setof uuid
  language sql stable as $$
    select c.id from crm.leads l join public.contratos c on c.cliente_id = l.perfil_id
    where l.id = p_lead_id and l.convertido_en is not null and c.creado_en >= l.convertido_en
  $$;

-- ⚠️ El divisor fecha por `asignado_en` y el numerador por `resultado_en`, cada
-- uno con su ventana. El primer calco ignoraba la ventana del numerador y un
-- cierre de junio contaba tambien en julio: la prueba del arrastre daba por
-- saldada una deuda que nadie habia pagado. Un calco que no respeta la FORMA
-- real no prueba nada.
create or replace function private.conversion_mensual_por_vendedor(
  p_ini timestamptz, p_fin timestamptz, p_global boolean, p_visibles uuid[], p_factor numeric)
  returns table(analista_id uuid, divisor integer, divisor_aproximado integer,
    divisor_por_motivo jsonb, cierres_no_referidos integer, cierres_referidos integer,
    cierres_de_arrastre integer, numerador numeric, conversion_pct numeric,
    procedencia jsonb, referidos_recibidos integer, referidos_aporta_pct numeric)
  language sql stable as $$
    select la.analista_id,
      count(*) filter (where la.asignado_en >= p_ini and la.asignado_en < p_fin)::int,
      0::int, '{}'::jsonb,
      count(*) filter (where la.resultado='convertido' and la.origen is distinct from 'referido'
                         and la.resultado_en >= p_ini and la.resultado_en < p_fin)::int,
      count(*) filter (where la.resultado='convertido' and la.origen='referido'
                         and la.resultado_en >= p_ini and la.resultado_en < p_fin)::int,
      0::int,
      (count(*) filter (where la.resultado='convertido' and la.origen is distinct from 'referido'
                          and la.resultado_en >= p_ini and la.resultado_en < p_fin)
       + p_factor * count(*) filter (where la.resultado='convertido' and la.origen='referido'
                          and la.resultado_en >= p_ini and la.resultado_en < p_fin))::numeric,
      null::numeric, '[]'::jsonb, 0::int, null::numeric
    from crm.lead_asignaciones la
    group by la.analista_id
  $$;

-- ── pg_cron ─────────────────────────────────────────────────────────────────
-- Calco del reloj. La migracion del candado programa el ciclo diario con
-- `cron.schedule` y despues COMPRUEBA en `cron.job` que quedo puesto; sin este
-- calco esa rama entera se saltaria en silencio y el banco daria verde sobre un
-- «el mes se cierra solo» que nadie habria ejecutado.
--
-- Forma tomada de produccion el 2026-08-15 (`information_schema.columns`), y
-- semantica de UPSERT POR NOMBRE, que es la que hace idempotente reaplicar la
-- migracion.
create schema if not exists cron;
create table if not exists cron.job (
  jobid    bigserial primary key,
  schedule text not null,
  command  text not null,
  nodename text not null default 'localhost',
  nodeport integer not null default 5432,
  database text not null default current_database(),
  username text not null default current_user,
  active   boolean not null default true,
  jobname  text
);
create unique index if not exists cron_job_jobname_username_key
  on cron.job (jobname, username);

create or replace function cron.schedule(p_job_name text, p_schedule text, p_command text)
returns bigint language plpgsql as $$
declare v_id bigint;
begin
  insert into cron.job (jobname, schedule, command)
  values (p_job_name, p_schedule, p_command)
  on conflict (jobname, username) do update
    set schedule = excluded.schedule, command = excluded.command, active = true
  returning jobid into v_id;
  return v_id;
end;
$$;
