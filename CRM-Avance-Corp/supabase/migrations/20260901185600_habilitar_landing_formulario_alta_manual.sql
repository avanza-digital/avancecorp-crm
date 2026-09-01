-- LANDING y FORMULARIO vuelven a ser orígenes declarables en el alta manual.
-- Decisión de Miguel (2026-09-01): reemplaza solo esa mitad de D8; Referido
-- sigue reservado al vendedor y a su propia asignación.
--
-- Regla de conversión confirmada el mismo día: el alta manual cuenta para
-- cartera, cierres, numerador y todas las demás métricas que correspondan; la
-- ÚNICA excepción es el divisor mensual del analista. El puente automático
-- conserva su aporte normal al divisor, aunque use el mismo origen.
--
-- No nace una función nueva ni cambia ninguna firma. Se obtiene la definición
-- viva de cada función existente y se aplican sustituciones fail-closed. Así se
-- preservan todas las guardias incorporadas después de D8 (segundo teléfono,
-- disponibilidad, ámbito, revocación bajo lock e idempotencia) sin mantener
-- otra copia de ellas.

begin;

set local lock_timeout = '10s';

-- `creado_por` no sirve como procedencia durable: su FK es ON DELETE SET NULL.
-- Este sello, en cambio, queda inmutable y distingue de forma explícita la RPC
-- manual del INSERT service_role del puente (que toma el DEFAULT false).
alter table crm.leads
  add column alta_manual boolean not null default false;

comment on column crm.leads.alta_manual is
  'Procedencia inmutable del alta: true solo cuando el lead nació mediante crm.crear_lead_si_disponible; false para el puente automático y registros históricos. Junto con origen landing/formulario excluye únicamente el divisor mensual, no el numerador ni otras métricas.';

do $sellar_procedencia$
declare
  v_firma constant pg_catalog.regprocedure :=
    'private.leads_before_update()'::pg_catalog.regprocedure;
  v_definicion text := pg_catalog.pg_get_functiondef(v_firma::pg_catalog.oid);
  v_anterior constant text :=
    E'  new.creado_por := old.creado_por;\n  new.creado_en := old.creado_en;';
  v_nuevo constant text :=
    E'  new.creado_por := old.creado_por;\n  new.alta_manual := old.alta_manual;\n  new.creado_en := old.creado_en;';
begin
  if pg_catalog.strpos(v_definicion, v_nuevo) > 0 then
    raise exception 'preflight: alta_manual ya estaba sellada en leads_before_update';
  end if;
  if (
    (pg_catalog.length(v_definicion) - pg_catalog.length(pg_catalog.replace(v_definicion, v_anterior, '')))
    / pg_catalog.length(v_anterior)
  ) <> 1 then
    raise exception 'preflight: el ancla de inmutabilidad de leads_before_update debe aparecer exactamente una vez';
  end if;
  if pg_catalog.strpos(pg_catalog.lower(v_definicion), 'security definer') = 0 then
    raise exception 'preflight: leads_before_update perdió SECURITY DEFINER';
  end if;

  execute pg_catalog.replace(v_definicion, v_anterior, v_nuevo);
end;
$sellar_procedencia$;

-- El núcleo único de conversión cambia solo en la pierna RECIBIDO. El cierre
-- queda intacto: por eso una conversión manual sigue sumando 1 al numerador.
do $conversion$
declare
  v_firma constant pg_catalog.regprocedure :=
    'private.conversion_episodios(timestamp with time zone, timestamp with time zone, date, boolean, uuid[], numeric)'::pg_catalog.regprocedure;
  v_definicion text := pg_catalog.pg_get_functiondef(v_firma::pg_catalog.oid);
  v_caso_anterior constant text :=
    'case when r.fue_referido then 0 else 1 end,';
  v_caso_nuevo constant text :=
    'case when r.fue_referido or r.alta_manual_fuera_divisor then 0 else 1 end,';
  v_fuente_anterior constant text :=
    E'    bool_or(la.aproximado) as aproximado,\n    min(la.asignado_en) as primera_asignacion\n  from crm.lead_asignaciones la\n  where la.asignado_en >= p_ini and la.asignado_en < p_fin';
  v_fuente_nueva constant text :=
    E'    bool_or(la.aproximado) as aproximado,\n    bool_or(l.alta_manual and la.origen in (''landing'', ''formulario'')) as alta_manual_fuera_divisor,\n    min(la.asignado_en) as primera_asignacion\n  from crm.lead_asignaciones la\n  join crm.leads l on l.id = la.lead_id\n  where la.asignado_en >= p_ini and la.asignado_en < p_fin';
begin
  if pg_catalog.strpos(v_definicion, v_caso_nuevo) > 0
     or pg_catalog.strpos(v_definicion, v_fuente_nueva) > 0 then
    raise exception 'preflight: conversion_episodios ya contiene la exclusión del alta manual';
  end if;
  if (
    (pg_catalog.length(v_definicion) - pg_catalog.length(pg_catalog.replace(v_definicion, v_caso_anterior, '')))
    / pg_catalog.length(v_caso_anterior)
  ) <> 1
     or (
       (pg_catalog.length(v_definicion) - pg_catalog.length(pg_catalog.replace(v_definicion, v_fuente_anterior, '')))
       / pg_catalog.length(v_fuente_anterior)
     ) <> 1 then
    raise exception 'preflight: cada ancla de la pierna RECIBIDO debe aparecer exactamente una vez';
  end if;
  if pg_catalog.strpos(pg_catalog.lower(v_definicion), 'security definer') = 0
     or pg_catalog.strpos(v_definicion, $needle$SET search_path TO ''$needle$) = 0 then
    raise exception 'preflight: conversion_episodios perdió sus guardias SECURITY DEFINER/search_path';
  end if;

  v_definicion := pg_catalog.replace(v_definicion, v_caso_anterior, v_caso_nuevo);
  v_definicion := pg_catalog.replace(v_definicion, v_fuente_anterior, v_fuente_nueva);
  execute v_definicion;
end;
$conversion$;

do $migration$
declare
  v_firma constant pg_catalog.regprocedure :=
    'crm.crear_lead_si_disponible(text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text)'::pg_catalog.regprocedure;
  v_definicion text;
  v_regla_anterior constant text :=
    'if p_origen not in (''referido'', ''oficina'', ''otro'') then';
  v_regla_nueva constant text :=
    'if p_origen not in (''referido'', ''landing'', ''formulario'', ''oficina'', ''otro'') then';
  v_columnas_anteriores constant text :=
    E'    activo,\n    creado_por\n  ) values (';
  v_columnas_nuevas constant text :=
    E'    activo,\n    creado_por,\n    alta_manual\n  ) values (';
  v_valores_anteriores constant text :=
    E'    true,\n    v_actor\n  );';
  v_valores_nuevos constant text :=
    E'    true,\n    v_actor,\n    true\n  );';
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname = 'crear_lead_si_disponible'
  ) <> 1 then
    raise exception 'preflight: crear_lead_si_disponible debe existir una sola vez';
  end if;

  select pg_catalog.pg_get_functiondef(v_firma::pg_catalog.oid)
    into v_definicion;

  if pg_catalog.strpos(v_definicion, v_regla_nueva) > 0 then
    raise exception 'preflight: LANDING y FORMULARIO ya estaban habilitados en el alta manual';
  end if;
  if (
    (pg_catalog.length(v_definicion) - pg_catalog.length(pg_catalog.replace(v_definicion, v_regla_anterior, '')))
    / pg_catalog.length(v_regla_anterior)
  ) <> 1 then
    raise exception 'preflight: la regla D8 esperada debe aparecer exactamente una vez';
  end if;
  if (
    (pg_catalog.length(v_definicion) - pg_catalog.length(pg_catalog.replace(v_definicion, v_columnas_anteriores, '')))
    / pg_catalog.length(v_columnas_anteriores)
  ) <> 1
     or (
       (pg_catalog.length(v_definicion) - pg_catalog.length(pg_catalog.replace(v_definicion, v_valores_anteriores, '')))
       / pg_catalog.length(v_valores_anteriores)
     ) <> 1 then
    raise exception 'preflight: las anclas del INSERT vivo deben aparecer exactamente una vez';
  end if;
  if pg_catalog.strpos(pg_catalog.lower(v_definicion), 'security definer') = 0
     or pg_catalog.strpos(v_definicion, $needle$SET search_path TO ''$needle$) = 0 then
    raise exception 'preflight: la RPC perdió sus guardias SECURITY DEFINER/search_path';
  end if;

  v_definicion := pg_catalog.replace(v_definicion, v_regla_anterior, v_regla_nueva);
  v_definicion := pg_catalog.replace(v_definicion, v_columnas_anteriores, v_columnas_nuevas);
  v_definicion := pg_catalog.replace(v_definicion, v_valores_anteriores, v_valores_nuevos);
  execute v_definicion;
end;
$migration$;

comment on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) is
  'Alta atomica manual de lead con verificacion de disponibilidad e idempotencia. Origenes manuales activos: referido, landing, formulario, oficina y otro. Referido sigue reservado al vendedor a su propio nombre. LANDING/FORMULARIO manuales cuentan en todo salvo el divisor mensual; el puente automatico conserva el divisor. El telefono principal identifica y el alternativo es solo canal de contacto.';

-- CREATE OR REPLACE conserva ACL, pero las volvemos a declarar para que el
-- contrato de exposición de esta SECURITY DEFINER quede verificable aquí.
revoke all on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) from public, anon, service_role;
grant execute on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) to authenticated;

do $postflight$
declare
  v_firma constant pg_catalog.regprocedure :=
    'crm.crear_lead_si_disponible(text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text)'::pg_catalog.regprocedure;
  v_definicion text := pg_catalog.pg_get_functiondef(v_firma::pg_catalog.oid);
  v_update text := pg_catalog.pg_get_functiondef(
    'private.leads_before_update()'::pg_catalog.regprocedure::pg_catalog.oid
  );
  v_conversion text := pg_catalog.pg_get_functiondef(
    'private.conversion_episodios(timestamp with time zone, timestamp with time zone, date, boolean, uuid[], numeric)'::pg_catalog.regprocedure::pg_catalog.oid
  );
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname = 'crear_lead_si_disponible'
  ) <> 1 then
    raise exception 'postflight: apareció una sobrecarga de crear_lead_si_disponible';
  end if;

  if pg_catalog.strpos(
    v_definicion,
    'if p_origen not in (''referido'', ''landing'', ''formulario'', ''oficina'', ''otro'') then'
  ) = 0 then
    raise exception 'postflight: la lista blanca manual no quedó actualizada';
  end if;
  if pg_catalog.strpos(
    v_definicion,
    'if p_origen not in (''referido'', ''oficina'', ''otro'') then'
  ) > 0 then
    raise exception 'postflight: la restricción manual anterior sigue presente';
  end if;
  if pg_catalog.strpos(v_definicion, E'    creado_por,\n    alta_manual\n  ) values (') = 0
     or pg_catalog.strpos(v_definicion, E'    v_actor,\n    true\n  );') = 0 then
    raise exception 'postflight: la RPC no sella alta_manual=true';
  end if;
  if pg_catalog.strpos(v_update, E'  new.alta_manual := old.alta_manual;') = 0 then
    raise exception 'postflight: alta_manual no quedó inmutable';
  end if;
  if pg_catalog.strpos(
    v_conversion,
    'case when r.fue_referido or r.alta_manual_fuera_divisor then 0 else 1 end,'
  ) = 0
     or pg_catalog.strpos(
       v_conversion,
       'bool_or(l.alta_manual and la.origen in (''landing'', ''formulario'')) as alta_manual_fuera_divisor'
     ) = 0 then
    raise exception 'postflight: el divisor no distingue el alta manual del puente';
  end if;
  -- La pierna CIERRE debe permanecer sin referencia al sello: así conserva el
  -- numerador y todo lo que deriva de él.
  if pg_catalog.strpos(
    v_conversion,
    E'case when c.anulado then 0\n       when c.fue_referido then p_factor\n       else 1 end'
  ) = 0 then
    raise exception 'postflight: la pierna CIERRE cambió y podría afectar el numerador';
  end if;
  if pg_catalog.has_function_privilege('public', v_firma::pg_catalog.oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', v_firma::pg_catalog.oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', v_firma::pg_catalog.oid, 'EXECUTE') then
    raise exception 'postflight: un rol no autorizado conserva EXECUTE';
  end if;
  if not pg_catalog.has_function_privilege('authenticated', v_firma::pg_catalog.oid, 'EXECUTE') then
    raise exception 'postflight: authenticated perdió EXECUTE';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_attribute a
    where a.attrelid = 'crm.leads'::pg_catalog.regclass
      and a.attname = 'alta_manual'
      and a.atttypid = 'boolean'::pg_catalog.regtype
      and a.attnotnull
      and not a.attisdropped
  ) then
    raise exception 'postflight: falta crm.leads.alta_manual boolean NOT NULL';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_attrdef d
      on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = 'crm.leads'::pg_catalog.regclass
      and a.attname = 'alta_manual'
      and pg_catalog.lower(pg_catalog.pg_get_expr(d.adbin, d.adrelid))
          in ('false', 'false::boolean')
  ) then
    raise exception 'postflight: alta_manual perdió DEFAULT false; el puente quedaría mal clasificado';
  end if;
end;
$postflight$;

commit;
