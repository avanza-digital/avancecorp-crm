\set ON_ERROR_STOP on

-- Oráculo autocontenido de crm.tomar_lead_libre (F2 del plan «lead libre»).
-- Se ejecuta únicamente en un PostgreSQL vacío y desechable:
--   psql -v test_conn='dbname=... user=...' -f test-toma-lead-libre.sql
-- Construye la frontera mínima previa a P-048 (idéntica al oráculo de la
-- creación atómica), añade los CUERPOS VIGENTES DE PRODUCCIÓN de los triggers
-- de los que la toma depende (anclados por md5: si prod cambió, este oráculo
-- se detiene igual que la migración), aplica LAS MIGRACIONES REALES en cadena
-- (P-048 → F1 → F2, cada una pasando sus propias guardas) y verifica
-- veredictos, carencia, válvula, vetos y concurrencia con dblink.
-- Éxito = código 0 y el token TOMA_LEAD_LIBRE_TX_OK al final.

do $$
declare v_rol text;
begin
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_catalog.pg_roles where rolname = v_rol) then
      execute pg_catalog.format('create role %I nologin', v_rol);
    end if;
  end loop;
end;
$$;

create extension dblink;

create schema auth;
create schema crm;
create schema private;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table public.perfiles (
  id uuid primary key,
  nombre_completo text,
  rol text not null,
  activo boolean not null default true,
  telefono text,
  dni text,
  asesor_perfil_id uuid
);

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  supervisor_id uuid,
  activo boolean not null default true
);

create table crm.enfriamiento_politica (
  motivo text primary key,
  dias integer not null
);

insert into crm.enfriamiento_politica (motivo, dias) values
  ('sin_interes', 30),
  ('sin_fondos', 90),
  ('competencia', 180),
  ('no_responde', 15),
  ('datos_invalidos', 0),
  ('pide_credito', 0),
  ('otro', 20);

create table crm.leads (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  nombre_completo text not null,
  telefono text not null,
  correo text,
  dni text,
  genero text,
  fecha_nacimiento date,
  distrito text,
  origen text not null default 'otro',
  etapa text not null default 'nuevo',
  motivo_descarte text,
  monto_estimado numeric not null,
  moneda text not null default 'PEN',
  categoria_interes text,
  vendedor_id uuid,
  asignado_supervisor_id uuid,
  perfil_id uuid,
  contrato_id uuid,
  convertido_en timestamptz,
  nota text,
  no_contactar boolean not null default false,
  descartado_en timestamptz,
  descartado_por uuid,
  activo boolean not null default true,
  creado_por uuid,
  creado_en timestamptz not null default pg_catalog.now(),
  tenencia_desde timestamptz,
  ciclo_actual integer not null default 1,
  -- El sello del descarte la escribe en INSERT/UPDATE: el portero la exige.
  clasificacion_auto text,
  actualizado_en timestamptz not null default pg_catalog.now()
);

create unique index uq_leads_telefono_vivo on crm.leads (telefono)
  where activo = true and etapa not in ('convertido', 'descartado');
create unique index uq_leads_dni_vivo on crm.leads (dni)
  where dni is not null and activo = true and etapa not in ('convertido', 'descartado');

-- La traza y la última conversación viven aquí (F1 ya la consulta; la toma
-- escribe su nota §9). CHECK de tipos calcado del vigente.
create table crm.actividades (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  lead_id uuid not null references crm.leads(id),
  tipo text not null check (tipo in (
    'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
    'whatsapp_recibido', 'reunion_realizada', 'nota', 'cambio_etapa',
    'reasignacion', 'conversion'
  )),
  detalle text,
  metadata jsonb,
  creado_por uuid,
  creado_en timestamptz not null default pg_catalog.now()
);

create function private.normalizar_telefono(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p is null or pg_catalog.btrim(p) = '' then p
    when pg_catalog.length(pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')) = 9
      then '+51' || pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')
    when pg_catalog.regexp_replace(p, '[^0-9]', '', 'g') ~ '^51[0-9]{9}$'
      then '+' || pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')
    else '+' || pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')
  end;
$$;

create function private.rol_crm(p_perfil_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('vendedor', 'supervisor', 'gerencia', 'coordinador');
$$;

create function private.vendedor_ids_visibles(p_perfil_id uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol text := private.rol_crm(p_perfil_id);
begin
  if v_rol = 'gerencia' then
    return query select e.perfil_id from crm.equipo e;
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select e.perfil_id
        from crm.equipo e
        where e.perfil_id = p_perfil_id
        union
        select e.perfil_id
        from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select s.perfil_id from subarbol s;
  elsif v_rol = 'vendedor' then
    return next p_perfil_id;
  end if;
end;
$$;

create function private.es_destino_crm_activo(p_perfil_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = p_perfil_id
      and e.activo = true
      and p.activo = true
      and e.rol_crm = any (p_roles)
  );
$$;

-- F1 los necesita al crear sus tablas/policies: stubs honestos.
create function private.es_lector_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false;
$$;

create function private.log_audit_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  return coalesce(new, old);
end;
$$;

-- Impl de 2 argumentos previo a P-048 (P-048 lo reemplaza por el delegador).
create function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object('estado', 'error', 'detalle', 'telefono_invalido');
  end if;
  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$$;

grant usage on schema auth, crm to authenticated;
grant execute on function auth.uid() to authenticated;
grant select, insert, update on crm.leads to authenticated, service_role;

-- Actores: dos vendedores de subárboles distintos, supervisión y un inactivo.
insert into public.perfiles (id, nombre_completo, rol, activo) values
  ('10000000-0000-0000-0000-000000000001', 'VENDEDOR UNO', 'analista', true),
  ('10000000-0000-0000-0000-000000000002', 'SUPERVISOR UNO', 'supervisor', true),
  ('10000000-0000-0000-0000-000000000003', 'VENDEDOR DOS', 'analista', true),
  ('10000000-0000-0000-0000-000000000004', 'GERENCIA', 'gerencia', true),
  ('10000000-0000-0000-0000-000000000005', 'COORDINADOR', 'coordinador', true),
  ('10000000-0000-0000-0000-000000000006', 'VENDEDOR INACTIVO', 'analista', true),
  ('10000000-0000-0000-0000-000000000007', 'SUPERVISOR DOS', 'supervisor', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('10000000-0000-0000-0000-000000000001', 'vendedor', '10000000-0000-0000-0000-000000000002', true),
  ('10000000-0000-0000-0000-000000000002', 'supervisor', null, true),
  ('10000000-0000-0000-0000-000000000003', 'vendedor', '10000000-0000-0000-0000-000000000007', true),
  ('10000000-0000-0000-0000-000000000004', 'gerencia', null, true),
  ('10000000-0000-0000-0000-000000000005', 'coordinador', null, true),
  ('10000000-0000-0000-0000-000000000006', 'vendedor', '10000000-0000-0000-0000-000000000002', false),
  ('10000000-0000-0000-0000-000000000007', 'supervisor', null, true);

-- ── Cuerpos VIGENTES de producción (2026-08-17) de los triggers de los que la
-- toma depende. Copiados byte a byte de pg_proc; el DO de abajo los ancla por
-- md5 contra los hashes leídos de prod ese día — si esta copia envejece, el
-- oráculo se detiene en vez de validar contra un mundo inventado. ─────────────

create function private.trg_leads_guard_tenencia()
returns trigger
language plpgsql
security definer
set search_path = ''
as $guard$
declare
  v_rol_actor text;
  v_entra_terminal boolean;
begin
  if new.vendedor_id is not null and new.asignado_supervisor_id is not null then
    raise exception 'Un lead no puede tener analista y bandeja al mismo tiempo';
  end if;

  -- Solo un miembro plenamente activo puede recibir responsabilidad nueva.
  if new.vendedor_id is not null
     and (
       tg_op = 'INSERT'
       or new.vendedor_id is distinct from old.vendedor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.vendedor_id,
       array['vendedor', 'supervisor']::text[]
     ) then
    raise exception 'El analista destino no existe, no esta activo o no puede recibir leads';
  end if;

  -- Una bandeja pertenece exclusivamente a un supervisor plenamente activo.
  if new.asignado_supervisor_id is not null
     and (
       tg_op = 'INSERT'
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.asignado_supervisor_id,
       array['supervisor']::text[]
     ) then
    raise exception 'La bandeja destino no pertenece a un supervisor activo';
  end if;

  -- Un usuario CRM no gerencial no puede liberar un lead a la cola global.
  if new.vendedor_id is null
     and new.asignado_supervisor_id is null
     and (
       tg_op = 'INSERT'
       or old.vendedor_id is not null
       or old.asignado_supervisor_id is not null
     )
     and auth.uid() is not null then
    v_rol_actor := private.rol_crm(auth.uid());
    if v_rol_actor is distinct from 'gerencia' then
      raise exception 'Solo Gerencia puede dejar un lead en la cola global';
    end if;
  end if;

  if tg_op = 'INSERT' then
    new.creado_en := statement_timestamp();
    new.actualizado_en := new.creado_en;
    new.ciclo_actual := 1;
    return new;
  end if;

  new.ciclo_actual := old.ciclo_actual;

  if old.etapa = 'convertido' and new.etapa is distinct from old.etapa then
    raise exception 'Un lead convertido no se puede reabrir';
  end if;

  if old.etapa = 'descartado' and new.etapa is distinct from old.etapa then
    if new.etapa <> 'nuevo' then
      raise exception 'Un lead descartado solo se puede reabrir en etapa nuevo';
    end if;
    new.ciclo_actual := old.ciclo_actual + 1;
  end if;

  v_entra_terminal := old.etapa not in ('convertido', 'descartado')
    and new.etapa in ('convertido', 'descartado');

  if v_entra_terminal
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Asigna al responsable antes de cerrar el lead';
  end if;

  if v_entra_terminal and old.activo = false then
    raise exception 'Reactiva el lead antes de cerrarlo';
  end if;

  if v_entra_terminal and old.activo = true and new.activo = false then
    raise exception 'Cierra o desactiva el lead en operaciones separadas';
  end if;

  if old.etapa <> 'convertido' and new.etapa = 'convertido'
     and old.vendedor_id is null then
    raise exception 'Asigna un analista antes de convertir el lead';
  end if;

  if old.activo = true and new.activo = false
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Reasigna o desactiva el lead en operaciones separadas';
  end if;

  return new;
end;
$guard$;

create function private.trg_leads_bloquear_reasignacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $veto$
begin
  if new.vendedor_id is distinct from old.vendedor_id
     and private.rol_crm((select auth.uid())) = 'vendedor' then
    raise exception 'Un vendedor no puede reasignar leads';
  end if;
  return new;
end;
$veto$;

create function private.trg_leads_tenencia_desde()
returns trigger
language plpgsql
security definer
set search_path = ''
as $tenencia$
declare
  v_new_debe boolean;
  v_old_debe boolean;
begin
  v_new_debe := new.activo = true
    and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and new.vendedor_id is not null;

  if tg_op = 'INSERT' then
    new.tenencia_desde := case when v_new_debe then new.creado_en else null end;
    return new;
  end if;

  v_old_debe := old.activo = true
    and old.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and old.vendedor_id is not null;

  if not v_new_debe then
    new.tenencia_desde := null;
  elsif not v_old_debe then
    new.tenencia_desde := statement_timestamp();
  elsif new.vendedor_id is distinct from old.vendedor_id then
    new.tenencia_desde := statement_timestamp();
  elsif new.ciclo_actual is distinct from old.ciclo_actual then
    new.tenencia_desde := statement_timestamp();
  else
    new.tenencia_desde := old.tenencia_desde;
  end if;

  return new;
end;
$tenencia$;


-- El P4 relajado de leads_before_update consulta crm.cierres_externos aun
-- cuando su rama no aplica (el AND de SQL no garantiza cortocircuito): stub
-- mínimo para que el portero pueda respirar. Ningún caso F2 lo puebla.
create table crm.cierres_externos (
  lead_id uuid
);

-- Los tres porteros que la frontera original NO tenía y que el banco real sí
-- (la ausencia de leads_before_insert escondió que un descartado no puede
-- NACER: mordió en el ciclo del branch 2026-08-17). Cuerpos de prod al byte,
-- anclados por md5 como los demás.
create function private.leads_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $bins$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if not v_priv then
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada') then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$bins$;

create function private.leads_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $bupd$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Columnas inmutables: restaurar siempre desde OLD.
  new.id := old.id;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.actualizado_en := now();

  -- Conversión y enlace al portal: SOLO desde una RPC privilegiada
  -- (que fija crm.op_privilegiada='on'). Un cliente API no puede convertir
  -- ni enlazar perfil_id/contrato_id a mano.
  if not v_priv then
    if new.etapa = 'convertido' and old.etapa <> 'convertido' then
      raise exception 'La conversión a cliente solo se hace vía la operación de conversión';
    end if;
    new.perfil_id := old.perfil_id;
    new.contrato_id := old.contrato_id;
    new.convertido_en := old.convertido_en;

    -- ── SELLO DEL ORIGEN (migración D, 2026-08-11) ────────────────────────
    -- El origen se elige al ALTA y no se vuelve a mover. Lo que esto protege
    -- NO es un mes ya contado —el snapshot `lead_asignaciones.origen` ya era
    -- inmutable por `trg_lead_asignaciones_00_inmutables`— sino dos cosas del
    -- presente y del futuro:
    --   · el origen que copiará `private.trg_leads_asignaciones` al abrir el
    --     PRÓXIMO episodio de este lead (y ése sí sale del divisor del mes en
    --     curso si dice 'referido');
    --   · el bloque `referidos.dados_de_alta`, único número del payload que
    --     lee esta columna viva, agrupado por el mes de ALTA del lead.
    -- Se avisa con EXCEPCIÓN en vez de restaurar en silencio porque el store
    -- del front es optimista: un 200 mudo dejaría al usuario convencido de
    -- que corrigió.
    -- Va DENTRO de `if not v_priv`, a propósito: encima del gate el dato
    -- quedaría incorregible para siempre y el único remedio sería
    -- `disable trigger` en producción, que CLAUDE.md prohíbe.
    -- `is distinct from` (y no `<>`) hace que un UPDATE de payload completo que
    -- reenvía el MISMO valor no lance nada: es el caso de seed-demo.mjs y de
    -- test-rls.mjs, los dos únicos escritores que mandan `origen` en un UPDATE.
    if new.origen is distinct from old.origen then
      raise exception using
        errcode = 'P0409',
        message = 'El origen de un lead no se cambia despues del alta',
        detail  = pg_catalog.format(
          'lead %s: origen actual %L, intento %L',
          old.id, old.origen, new.origen),
        hint    = 'El origen se elige al crear el lead (crm.crear_lead_si_disponible). '
                  'La conversion mensual lee la FOTO del episodio, que ya es inmutable: '
                  'cambiar la ficha no mueve ningun mes ya contado, pero si moveria el '
                  'origen de los episodios FUTUROS de este lead y el bloque de referidos '
                  'dados de alta de su mes de creacion.';
    end if;
  end if;

  -- ── P4 RELAJADA (migración cierres externos, 2026-08-12) ────────────────
  -- Invariante de negocio en la transición (no como CHECK de tabla). Antes:
  -- «convertido ⇒ perfil_id no nulo». Ahora un convertido puede carecer de
  -- perfil SI Y SOLO SI tiene cierre externo (invirtió en una cooperativa y
  -- el portal no lo conoce). El EXISTS corre solo en la rama rara (convertido
  -- sin perfil) y lo sirve el UNIQUE de lead_id. Nótese que P2 sigue intacta:
  -- sin válvula no hay transición a convertido, con o sin cierre.
  if new.etapa = 'convertido' and new.perfil_id is null
     and not exists (
       select 1 from crm.cierres_externos ce where ce.lead_id = new.id
     ) then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$bupd$;

create function private.trg_leads_zz_sello_descarte()
returns trigger
language plpgsql
security definer
set search_path = ''
as $sello$
declare
  v_txt text;
begin
  if tg_op = 'INSERT' then
    -- El cliente API NO decide su propia clasificación ni su sello de cierre.
    -- translate() quita tildes sin depender de la extensión unaccent.
    v_txt := lower(translate(coalesce(new.nota, ''),
                             'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
    -- Prefijos con frontera de palabra a la izquierda: 'prestam*' (préstamo,
    -- préstamos, prestamista) y 'financiamient*'. Regla ESTRECHA a propósito
    -- (auditoría 2026-07-23): 'credit*' marcaba "¿son cooperativa de ahorro y
    -- CRÉDITO?" — la identidad de la propia empresa y la pregunta MÁS común de
    -- un buen cliente — y 'prestar' marcaba "prestar información". Con tasa
    -- base 0.5%, un falso positivo cuesta más que un falso negativo: lo que
    -- esta regla no atrape lo atrapa Rosa leyendo el comentario redactado.
    if v_txt ~ '\m(prestam|financiamient)' then
      new.clasificacion_auto := 'posible_credito';
    else
      new.clasificacion_auto := null;
    end if;
    new.descartado_en := null;
    new.descartado_por := null;
    return new;
  end if;

  -- El veredicto del código es un DATO DE MEDICIÓN: si un humano pudiera
  -- reescribirlo, la matriz de confusión (falsos positivos vs negativos)
  -- dejaría de ser calculable. Inmutable, como id/creado_por/creado_en.
  new.clasificacion_auto := old.clasificacion_auto;

  if new.etapa = 'descartado' and old.etapa is distinct from 'descartado' then
    new.descartado_en := statement_timestamp();
    new.descartado_por := auth.uid();
  elsif new.etapa is distinct from 'descartado' then
    -- Reapertura: el sello describe el cierre VIGENTE, no uno viejo. Dejarlo
    -- rancio corrompería en silencio cualquier informe de "descartes del mes".
    -- El histórico completo queda en public.audit_log y en crm.actividades.
    new.descartado_en := null;
    new.descartado_por := null;
  else
    new.descartado_en := old.descartado_en;
    new.descartado_por := old.descartado_por;
  end if;

  return new;
end;
$sello$;

do $$
declare
  v_md5 text;
begin
  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'leads_before_insert';
  if v_md5 is distinct from '23c0004c94d11494c3eba41357db7638' then
    raise exception 'stub de leads_before_insert NO es prod al byte (md5 %)', v_md5;
  end if;
  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'leads_before_update';
  if v_md5 is distinct from '006fbbaebced2218cff12a47aa1acb11' then
    raise exception 'stub de leads_before_update NO es prod al byte (md5 %)', v_md5;
  end if;
  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'trg_leads_zz_sello_descarte';
  if v_md5 is distinct from '02e578687d53f2fc828cde3077192365' then
    raise exception 'stub de trg_leads_zz_sello_descarte NO es prod al byte (md5 %)', v_md5;
  end if;
end;
$$;

create trigger trg_leads_before_insert
  before insert on crm.leads
  for each row execute function private.leads_before_insert();

create trigger trg_leads_before_update
  before update on crm.leads
  for each row execute function private.leads_before_update();

create trigger trg_leads_zz_sello_descarte
  before insert or update on crm.leads
  for each row execute function private.trg_leads_zz_sello_descarte();

-- Anclas: estos stubs deben ser PRODUCCIÓN al byte (md5 de pg_proc.prosrc
-- leídos de prod el 2026-08-17). Si difieren, el mundo es inventado: parar.
do $$
declare
  v_md5 text;
begin
  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'trg_leads_guard_tenencia';
  if v_md5 is distinct from '763323f5f4ecaa735ce78cbccabad894' then
    raise exception 'stub de trg_leads_guard_tenencia NO es prod al byte (md5 %)', v_md5;
  end if;

  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'trg_leads_bloquear_reasignacion';
  if v_md5 is distinct from '1ba780d9d3b7f4b846292237f0d78de9' then
    raise exception 'stub de trg_leads_bloquear_reasignacion NO es prod al byte (md5 %)', v_md5;
  end if;

  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'trg_leads_tenencia_desde';
  if v_md5 is distinct from 'c9e67e0bbe6dcad2486125b4600ead67' then
    raise exception 'stub de trg_leads_tenencia_desde NO es prod al byte (md5 %)', v_md5;
  end if;
end;
$$;

-- Los nombres de trigger replican prod: el 00 y el zzz fijan el ORDEN real.
create trigger trg_leads_00_guard_tenencia
  before insert or update on crm.leads
  for each row execute function private.trg_leads_guard_tenencia();

create trigger trg_leads_bloquear_reasignacion
  before update on crm.leads
  for each row execute function private.trg_leads_bloquear_reasignacion();

create trigger trg_leads_zzz_tenencia_desde
  before insert or update on crm.leads
  for each row execute function private.trg_leads_tenencia_desde();

-- ── Migraciones REALES, en cadena y con sus propias guardas ─────────────────
\ir ../migrations/20260804165440_crm_creacion_lead_atomica.sql

-- El wrapper con su cuerpo PRE-F1 vigente (nació en 20260803164348): la guarda
-- de F1 lo exige al byte (md5 a1de9063…).
create or replace function crm.verificar_disponibilidad_lead(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol text := private.rol_crm((select auth.uid()));
begin
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using
      errcode = '42501',
      message = 'Acceso CRM revocado';
  end if;

  return private.verificar_disponibilidad_lead_impl(p_telefono, p_dni);
end;
$$;

do $$
declare
  v_md5 text;
begin
  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'verificar_disponibilidad_lead';
  if v_md5 is distinct from 'a1de9063b2674341cec8f54743564072' then
    raise exception 'wrapper pre-F1 NO es prod al byte (md5 %)', v_md5;
  end if;
end;
$$;

\ir ../migrations/20260816221500_crm_lead_libre_f1_verificacion.sql
\ir ../migrations/20260817164745_crm_lead_libre_f2_tomar.sql

-- ── Semillas ────────────────────────────────────────────────────────────────
-- Como sistema (sin sesión): el importador legacy comparte esta vía.
do $$
begin
  execute 'alter table crm.leads disable trigger trg_leads_before_insert';
  execute 'alter table crm.leads disable trigger trg_leads_zz_sello_descarte';
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);

  -- Bolsa viva.
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa)
  values ('30000000-0000-0000-0000-000000000001', 'BOLSA UNO', '+51910000001', '40000001', 5000, 'nuevo');

  -- Descartado con enfriamiento VENCIDO (no_responde = 15 días; 20 atrás).
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa,
                         motivo_descarte, descartado_en, descartado_por, vendedor_id)
  values ('30000000-0000-0000-0000-000000000002', 'VENCIDO DOS', '+51910000002', '40000002', 6000,
          'descartado', 'no_responde',
          pg_catalog.now() - interval '20 days', '10000000-0000-0000-0000-000000000005', null);

  -- Descartado con enfriamiento VIGENTE (sin_fondos = 90 días; 10 atrás).
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa,
                         motivo_descarte, descartado_en, descartado_por)
  values ('30000000-0000-0000-0000-000000000003', 'VIGENTE TRES', '+51910000003', '40000003', 7000,
          'descartado', 'sin_fondos',
          pg_catalog.now() - interval '10 days', '10000000-0000-0000-0000-000000000005');

  -- Descarte de 0 días RECIÉN hecho (pide_credito, hace 1 hora): carencia.
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa,
                         motivo_descarte, descartado_en, descartado_por)
  values ('30000000-0000-0000-0000-000000000004', 'CARENCIA CUATRO', '+51910000004', '40000004', 8000,
          'descartado', 'pide_credito',
          pg_catalog.now() - interval '1 hour', '10000000-0000-0000-0000-000000000005');

  -- No contactar.
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa, no_contactar,
                         motivo_descarte, descartado_en)
  values ('30000000-0000-0000-0000-000000000005', 'VETADO CINCO', '+51910000005', '40000005', 9000,
          'descartado', true, 'otro', pg_catalog.now() - interval '60 days');

  -- Convertido sin perfil de portal (cierre externo): jamás reabrible.
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa, vendedor_id)
  values ('30000000-0000-0000-0000-000000000006', 'CONVERTIDO SEIS', '+51910000006', '40000006', 9500,
          'convertido', '10000000-0000-0000-0000-000000000003');

  -- Teléfono manda: descartado vencido por TELÉFONO cuyo DNI apunta a otra
  -- bolsa viva (comparten dni de CONSULTA, no de fila: la fila 7 tiene el
  -- dni 40000007 y la bolsa 8 el MISMO dni de búsqueda en su fila).
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa,
                         motivo_descarte, descartado_en)
  values ('30000000-0000-0000-0000-000000000007', 'MANDA TEL SIETE', '+51910000007', '40000007', 5500,
          'descartado', 'no_responde', pg_catalog.now() - interval '30 days');

  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa)
  values ('30000000-0000-0000-0000-000000000008', 'BOLSA OCHO', '+51910000008', '40000008', 5200, 'nuevo');

  -- La red del índice único: descartado vencido cuyo DNI ya vive en una bolsa.
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa,
                         motivo_descarte, descartado_en)
  values ('30000000-0000-0000-0000-000000000009', 'RED NUEVE', '+51910000009', '40000009', 5100,
          'descartado', 'no_responde', pg_catalog.now() - interval '30 days');
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa)
  values ('30000000-0000-0000-0000-00000000000a', 'RED DIEZ BOLSA', '+51910000010', '40000009', 5300, 'nuevo');

  -- Un cliente del portal para el veto ya_es_cliente.
  insert into public.perfiles (id, nombre_completo, rol, activo, telefono, dni, asesor_perfil_id)
  values ('20000000-0000-0000-0000-000000000001', 'CLIENTA REAL', 'cliente', true,
          '+51920000001', '48000001', '10000000-0000-0000-0000-000000000003');

  -- Conversaciones reales del vencido DOS (para ultima_conversacion_en).
  insert into crm.actividades (lead_id, tipo, creado_en)
  values ('30000000-0000-0000-0000-000000000002', 'llamada_realizada', pg_catalog.now() - interval '25 days'),
         ('30000000-0000-0000-0000-000000000002', 'whatsapp_enviado', pg_catalog.now() - interval '21 days');
  execute 'alter table crm.leads enable trigger trg_leads_before_insert';
  execute 'alter table crm.leads enable trigger trg_leads_zz_sello_descarte';
end;
$$;

-- ── TOMA-01: la bolsa se toma y la tenencia renace ──────────────────────────
do $$
declare
  v jsonb;
  v_lead crm.leads%rowtype;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v := crm.tomar_lead_libre('910000001');
  if v ->> 'estado' <> 'tomado_ok' or v ->> 'modo' <> 'bolsa' then
    raise exception 'FALLO TOMA-01: %', v;
  end if;
  select * into v_lead from crm.leads where id = '30000000-0000-0000-0000-000000000001';
  if v_lead.vendedor_id <> '10000000-0000-0000-0000-000000000001'
     or v_lead.tenencia_desde is null
     or v_lead.ciclo_actual <> 1 then
    raise exception 'FALLO TOMA-01: fila final incoherente (% % %)',
      v_lead.vendedor_id, v_lead.tenencia_desde, v_lead.ciclo_actual;
  end if;
  if not exists (
    select 1 from crm.actividades a
    where a.lead_id = v_lead.id and a.tipo = 'nota'
      and a.metadata ->> 'evento' = 'toma_directa'
      and a.metadata ->> 'modo' = 'bolsa'
      and a.creado_por = '10000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'FALLO TOMA-01: falta la nota §9 de la toma';
  end if;
  -- Auditor A1: también la toma EXITOSA deja asiento anti-pesca.
  if (select count(*) from crm.verificaciones_lead
      where verificado_por = '10000000-0000-0000-0000-000000000001'
        and telefono_consultado = '+51910000001'
        and veredicto = 'tomado_ok') <> 1 then
    raise exception 'FALLO TOMA-01: la toma exitosa no dejó asiento anti-pesca';
  end if;
  raise notice 'TOMA-01 OK (bolsa)';
end;
$$;

-- ── TOMA-02: el descartado vencido REVIVE (ciclo+1, tenencia renace) ────────
do $$
declare
  v jsonb;
  v_lead crm.leads%rowtype;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
  v := crm.tomar_lead_libre('910000002');
  if v ->> 'estado' <> 'tomado_ok' or v ->> 'modo' <> 'reutilizable'
     or (v ->> 'ciclo_actual')::int <> 2 or v ->> 'etapa' <> 'nuevo' then
    raise exception 'FALLO TOMA-02: %', v;
  end if;
  select * into v_lead from crm.leads where id = '30000000-0000-0000-0000-000000000002';
  if v_lead.vendedor_id <> '10000000-0000-0000-0000-000000000003'
     or v_lead.etapa <> 'nuevo'
     or v_lead.ciclo_actual <> 2
     or v_lead.motivo_descarte is not null
     or v_lead.tenencia_desde is null then
    raise exception 'FALLO TOMA-02: fila final incoherente';
  end if;
  if not exists (
    select 1 from crm.actividades a
    where a.lead_id = v_lead.id and a.tipo = 'nota'
      and a.metadata ->> 'modo' = 'reutilizable'
      and a.metadata ? 'quedo_libre_en'
      and (a.metadata ->> 'ultima_conversacion') is not null
  ) then
    raise exception 'FALLO TOMA-02: la nota §9 no lleva quedo_libre_en/ultima_conversacion';
  end if;
  raise notice 'TOMA-02 OK (reutilizable)';
end;
$$;

-- ── TOMA-03: enfriamiento vigente NO se toma ────────────────────────────────
do $$
declare v jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v := crm.tomar_lead_libre('910000003');
  if v ->> 'estado' <> 'enfriamiento' then
    raise exception 'FALLO TOMA-03: %', v;
  end if;
  if exists (select 1 from crm.leads where id = '30000000-0000-0000-0000-000000000003' and etapa <> 'descartado') then
    raise exception 'FALLO TOMA-03: la fila cambió';
  end if;
  -- Auditor A1: la toma FALLIDA (sondeo) también deja asiento — sin esto,
  -- quien pesque identidades usaría exactamente este endpoint sin log.
  if (select count(*) from crm.verificaciones_lead
      where telefono_consultado = '+51910000003'
        and veredicto = 'enfriamiento') < 1 then
    raise exception 'FALLO TOMA-03: la toma fallida no dejó asiento anti-pesca';
  end if;
  raise notice 'TOMA-03 OK (enfriamiento vigente)';
end;
$$;

-- ── TOMA-04: la carencia de 24 h de los motivos de 0 días ───────────────────
do $$
declare v jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  -- El wrapper dice 'libre' durante la ventana (el alta manual no cambia)…
  v := crm.verificar_disponibilidad_lead('910000004');
  if v ->> 'estado' <> 'libre' then
    raise exception 'FALLO TOMA-04a: el veredicto en carencia debía ser libre: %', v;
  end if;
  -- …y la TOMA se niega con ese mismo veredicto.
  v := crm.tomar_lead_libre('910000004');
  if v ->> 'estado' <> 'libre' then
    raise exception 'FALLO TOMA-04b: la toma en carencia debía rebotar en libre: %', v;
  end if;
  if exists (select 1 from crm.leads where id = '30000000-0000-0000-0000-000000000004' and etapa <> 'descartado') then
    raise exception 'FALLO TOMA-04: la carencia no protegió la fila';
  end if;
end;
$$;

-- Pasadas las 24 h el mismo descarte es reutilizable y se toma.
do $$
declare v jsonb;
begin
  execute 'alter table crm.leads disable trigger trg_leads_before_insert';
  execute 'alter table crm.leads disable trigger trg_leads_zz_sello_descarte';
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  update crm.leads set descartado_en = pg_catalog.now() - interval '25 hours'
  where id = '30000000-0000-0000-0000-000000000004';
  execute 'alter table crm.leads enable trigger trg_leads_before_insert';
  execute 'alter table crm.leads enable trigger trg_leads_zz_sello_descarte';

  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v := crm.verificar_disponibilidad_lead('910000004');
  if v ->> 'estado' <> 'reutilizable'
     or v ->> 'motivo_descarte' <> 'pide_credito'
     or (v ->> 'quedo_libre_en') is null
     or not (v ? 'descartado_por')
     or not (v ? 'ultima_conversacion_en') then
    raise exception 'FALLO TOMA-04c: forma del veredicto reutilizable: %', v;
  end if;
  v := crm.tomar_lead_libre('910000004');
  if v ->> 'estado' <> 'tomado_ok' or v ->> 'modo' <> 'reutilizable' then
    raise exception 'FALLO TOMA-04d: %', v;
  end if;
  raise notice 'TOMA-04 OK (carencia 24 h y toma posterior)';
end;
$$;

-- ── TOMA-05: supervisor y gerencia NO toman (su puerta es el reparto) ───────
do $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
  begin
    perform crm.tomar_lead_libre('910000008');
    raise exception 'FALLO TOMA-05: supervisor tomó';
  exception when sqlstate '42501' then null;
  end;
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
  begin
    perform crm.tomar_lead_libre('910000008');
    raise exception 'FALLO TOMA-05: gerencia tomó';
  exception when sqlstate '42501' then null;
  end;
  raise notice 'TOMA-05 OK (solo vendedores)';
end;
$$;

-- ── TOMA-06: vendedor con membresía inactiva → 42501 ────────────────────────
do $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000006', true);
  begin
    perform crm.tomar_lead_libre('910000008');
    raise exception 'FALLO TOMA-06: membresía inactiva tomó';
  exception when sqlstate '42501' then null;
  end;
  raise notice 'TOMA-06 OK (membresía inactiva)';
end;
$$;

-- ── TOMA-07: no_contactar y ya_es_cliente vetan la toma ─────────────────────
do $$
declare v jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v := crm.tomar_lead_libre('910000005');
  if v ->> 'estado' <> 'no_contactar' then
    raise exception 'FALLO TOMA-07a: %', v;
  end if;
  v := crm.tomar_lead_libre('920000001');
  if v ->> 'estado' <> 'ya_es_cliente' then
    raise exception 'FALLO TOMA-07b: %', v;
  end if;
  raise notice 'TOMA-07 OK (vetos de contacto)';
end;
$$;

-- ── TOMA-08: el teléfono manda sobre el DNI ─────────────────────────────────
do $$
declare
  v jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  -- El teléfono apunta al descartado vencido 7; el DNI tecleado apunta a la
  -- bolsa 8. Manda el teléfono: revive el 7 y la bolsa 8 queda intacta.
  v := crm.tomar_lead_libre('910000007', '40000008');
  if v ->> 'estado' <> 'tomado_ok'
     or v ->> 'lead_id' <> '30000000-0000-0000-0000-000000000007'
     or v ->> 'modo' <> 'reutilizable' then
    raise exception 'FALLO TOMA-08: %', v;
  end if;
  if exists (
    select 1 from crm.leads
    where id = '30000000-0000-0000-0000-000000000008'
      and (vendedor_id is not null or etapa <> 'nuevo')
  ) then
    raise exception 'FALLO TOMA-08: la bolsa del DNI fue tocada';
  end if;
  raise notice 'TOMA-08 OK (el teléfono manda)';
end;
$$;

-- ── TOMA-09: convertido jamás se reabre — su contacto es libre (alta nueva) ─
do $$
declare v jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v := crm.tomar_lead_libre('910000006');
  if v ->> 'estado' <> 'libre' then
    raise exception 'FALLO TOMA-09: %', v;
  end if;
  if exists (select 1 from crm.leads where id = '30000000-0000-0000-0000-000000000006' and etapa <> 'convertido') then
    raise exception 'FALLO TOMA-09: el convertido fue tocado';
  end if;
  raise notice 'TOMA-09 OK (convertido intocable)';
end;
$$;

-- ── TOMA-10: la red del índice único (revive chocando con un vivo) ──────────
do $$
declare v jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  -- El teléfono apunta al descartado 9, cuyo DNI de fila (40000009) ya vive
  -- en la bolsa 10: el revive choca con uq_leads_dni_vivo y responde verdad.
  v := crm.tomar_lead_libre('910000009');
  if v ->> 'estado' <> 'en_bolsa' then
    raise exception 'FALLO TOMA-10: la red debía responder en_bolsa: %', v;
  end if;
  if exists (select 1 from crm.leads where id = '30000000-0000-0000-0000-000000000009' and etapa <> 'descartado') then
    raise exception 'FALLO TOMA-10: el descartado quedó a medias';
  end if;
  raise notice 'TOMA-10 OK (unique_violation responde verdad)';
end;
$$;

-- ── TOMA-11: la válvula es ANGOSTA ──────────────────────────────────────────
do $$
begin
  -- Sin flag: un vendedor no puede autoasignarse ni con UPDATE directo.
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  begin
    update crm.leads set vendedor_id = '10000000-0000-0000-0000-000000000001'
    where id = '30000000-0000-0000-0000-000000000008';
    raise exception 'FALLO TOMA-11a: el veto de reasignación no saltó';
  exception when others then
    if sqlerrm !~ 'no puede reasignar' then
      raise exception 'FALLO TOMA-11a: excepción inesperada: %', sqlerrm;
    end if;
  end;

  -- Con flag encendido A MANO pero destino ajeno: sigue vetado.
  perform pg_catalog.set_config('crm.toma_directa', 'on', true);
  begin
    update crm.leads set vendedor_id = '10000000-0000-0000-0000-000000000003'
    where id = '30000000-0000-0000-0000-000000000008';
    raise exception 'FALLO TOMA-11b: la válvula dejó pasar un destino ajeno';
  exception when others then
    if sqlerrm !~ 'no puede reasignar' then
      raise exception 'FALLO TOMA-11b: excepción inesperada: %', sqlerrm;
    end if;
  end;
  perform pg_catalog.set_config('crm.toma_directa', 'off', true);
  raise notice 'TOMA-11 OK (válvula angosta)';
end;
$$;

-- ── Concurrencia real con dblink ────────────────────────────────────────────
-- Semillas frescas para las carreras.
do $$
begin
  execute 'alter table crm.leads disable trigger trg_leads_before_insert';
  execute 'alter table crm.leads disable trigger trg_leads_zz_sello_descarte';
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa)
  values ('31000000-0000-0000-0000-000000000001', 'CARRERA BOLSA', '+51930000001', '41000001', 5000, 'nuevo');
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa,
                         motivo_descarte, descartado_en)
  values ('31000000-0000-0000-0000-000000000002', 'CARRERA REVIVE', '+51930000002', '41000002', 5000,
          'descartado', 'no_responde', pg_catalog.now() - interval '30 days');
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa,
                         motivo_descarte, descartado_en)
  values ('31000000-0000-0000-0000-000000000003', 'CARRERA DESHACER', '+51930000003', '41000003', 5000,
          'descartado', 'no_responde', pg_catalog.now() - interval '30 days');
  execute 'alter table crm.leads enable trigger trg_leads_before_insert';
  execute 'alter table crm.leads enable trigger trg_leads_zz_sello_descarte';
end;
$$;

create table private.worker_test (pid integer primary key);

-- G1: dos vendedores por la MISMA bolsa — gana uno, el otro ve la verdad.
select dblink_connect('worker', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000001',
      false
    );
    select crm.tomar_lead_libre('930000001');
    -- El marcador se adquiere DESPUÉS de la toma: cuando el poll lo vea, la
    -- fila ya está bloqueada y actualizada SIN commitear — eso es la carrera.
    select pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('oraculo:toma:g1', 0)
    );
    select pg_catalog.pg_sleep(1);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'FALLO G1: worker nunca arrancó';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', false);
  v := crm.tomar_lead_libre('930000001');
  if v ->> 'estado' <> 'tomado' then
    raise exception 'FALLO G1: el perdedor debía ver tomado: %', v;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'FALLO G1: el perdedor no esperó el candado de fila';
  end if;
  if (select count(*) from crm.leads
      where telefono = '+51930000001' and vendedor_id is not null) <> 1 then
    raise exception 'FALLO G1: dueños distintos de 1';
  end if;
  if (select vendedor_id from crm.leads where telefono = '+51930000001')
     <> '10000000-0000-0000-0000-000000000001' then
    raise exception 'FALLO G1: ganó quien no era';
  end if;
  raise notice 'G1 OK (carrera de bolsa: gana uno, el otro ve la verdad)';
end;
$$;

select dblink_disconnect('worker');

-- G2: dos vendedores por el MISMO descartado vencido — un solo revive,
-- un solo incremento de ciclo.
truncate table private.worker_test;
select dblink_connect('worker_revive', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker_revive', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker_revive',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000001',
      false
    );
    select crm.tomar_lead_libre('930000002');
    select pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('oraculo:toma:g2', 0)
    );
    select pg_catalog.pg_sleep(1);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'FALLO G2: worker nunca arrancó';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
  v_lead crm.leads%rowtype;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', false);
  v := crm.tomar_lead_libre('930000002');
  if v ->> 'estado' <> 'tomado' then
    raise exception 'FALLO G2: el perdedor debía ver tomado: %', v;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'FALLO G2: el perdedor no esperó';
  end if;
  select * into v_lead from crm.leads where id = '31000000-0000-0000-0000-000000000002';
  if v_lead.etapa <> 'nuevo' or v_lead.ciclo_actual <> 2
     or v_lead.vendedor_id <> '10000000-0000-0000-0000-000000000001' then
    raise exception 'FALLO G2: revive incoherente (% ciclo %)', v_lead.etapa, v_lead.ciclo_actual;
  end if;
  raise notice 'G2 OK (carrera de revive: un solo ciclo+1)';
end;
$$;

select dblink_disconnect('worker_revive');

-- G3: el otro camino fila-primero (un UPDATE de etapa estilo «deshacer») NO se
-- abraza con la toma: la toma espera la fila y entra después, sin deadlock.
truncate table private.worker_test;
select dblink_connect('worker_fila', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker_fila', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker_fila',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000004',
      false
    );
    -- Fila primero (for update) y DESPUÉS las llaves advisory del trigger,
    -- exactamente como deshacer_descarte.
    select id from crm.leads where id = '31000000-0000-0000-0000-000000000003' for update;
    update crm.leads set etapa = 'nuevo', motivo_descarte = null
    where id = '31000000-0000-0000-0000-000000000003';
    select pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('oraculo:toma:g3', 0)
    );
    select pg_catalog.pg_sleep(1);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'FALLO G3: worker nunca arrancó';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
  v_lead crm.leads%rowtype;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);
  -- El «deshacer» del worker deja el lead VIVO en la bolsa; la toma espera la
  -- fila (sin abrazo mortal) y lo toma apenas se libera.
  v := crm.tomar_lead_libre('930000003');
  if v ->> 'estado' <> 'tomado_ok' or v ->> 'modo' <> 'bolsa' then
    raise exception 'FALLO G3: la toma tras el deshacer debía ganar la bolsa: %', v;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'FALLO G3: la toma no esperó la fila';
  end if;
  select * into v_lead from crm.leads where id = '31000000-0000-0000-0000-000000000003';
  if v_lead.vendedor_id <> '10000000-0000-0000-0000-000000000001' or v_lead.etapa <> 'nuevo' then
    raise exception 'FALLO G3: estado final incoherente';
  end if;
  raise notice 'G3 OK (fila-primero convive con la toma, sin deadlock)';
end;
$$;

select dblink_disconnect('worker_fila');

-- G4 (Codex R4): un «No contactar» marcado EN VUELO no se toma. El worker
-- (gerencia) marca no_contactar y retiene la fila sin commitear; la toma
-- espera la fila, EvalPlanQual re-evalúa el predicado sobre la versión nueva
-- y el lead queda fuera — el veredicto fresco dice la verdad.
do $$
begin
  execute 'alter table crm.leads disable trigger trg_leads_before_insert';
  execute 'alter table crm.leads disable trigger trg_leads_zz_sello_descarte';
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  insert into crm.leads (id, nombre_completo, telefono, dni, monto_estimado, etapa)
  values ('31000000-0000-0000-0000-000000000004', 'CARRERA NO CONTACTAR', '+51930000004', '41000004', 5000, 'nuevo');
  execute 'alter table crm.leads enable trigger trg_leads_before_insert';
  execute 'alter table crm.leads enable trigger trg_leads_zz_sello_descarte';
end;
$$;

truncate table private.worker_test;
select dblink_connect('worker_veto', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker_veto', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker_veto',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000004',
      false
    );
    update crm.leads set no_contactar = true
    where id = '31000000-0000-0000-0000-000000000004';
    select pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('oraculo:toma:g4', 0)
    );
    select pg_catalog.pg_sleep(1);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'FALLO G4: worker nunca arrancó';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
  v_lead crm.leads%rowtype;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);
  v := crm.tomar_lead_libre('930000004');
  if v ->> 'estado' <> 'no_contactar' then
    raise exception 'FALLO G4: un No contactar en vuelo fue tomado: %', v;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'FALLO G4: la toma no esperó la fila del veto';
  end if;
  select * into v_lead from crm.leads where id = '31000000-0000-0000-0000-000000000004';
  if v_lead.vendedor_id is not null or v_lead.no_contactar <> true then
    raise exception 'FALLO G4: estado final incoherente';
  end if;
  raise notice 'G4 OK (no_contactar en vuelo no se toma)';
end;
$$;

select dblink_disconnect('worker_veto');

do $$
begin
  raise notice 'TOMA_LEAD_LIBRE_TX_OK';
end;
$$;
