-- ---------------------------------------------------------------------------------------------------------------------
-- Pruebas por escenario de 20261015000852_crm_plazo_carga_mes (plazo de carga por mes y reapertura del último mes).
-- ---------------------------------------------------------------------------------------------------------------------
-- Base IGUAL A PRODUCCIÓN (banco Docker con el volcado de esquema de producción) y la migración YA aplicada. Siembra un
-- mundo SINTÉTICO (sin personas reales) con la forma de producción del 14/10: el mes de hace dos meses sellado, el mes
-- anterior abierto con metas, el mes en curso. Cada bloque monta su variación y la deshace al terminar (subtransacción
-- que termina en `DESHACER`); el archivo entero termina en ROLLBACK: no deja nada.
--
--   psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -f supabase/scripts/plazo-carga-mes/prueba.sql
--
-- Verde = última línea «PRUEBA PLAZO CARGA OK: N casos». Un fallo de aserción dice «PRUEBA FALLA [bloque] caso: …».
-- Lo usa mutantes.py (cada mutante tiene que hacer caer una aserción, no un error cualquiera).
-- Bloques: B1 plazo base · B2 ampliar (ventana, ciclo antes/después, sello sobre filas ya decididas) · B3 acortar ·
-- B4 validaciones 22023 · B5 gate 42501 por rol · B6 reevaluación · B7 reapertura completa · B8 cada negativa de la
-- reapertura · B9 candados sin autorización y la autorización acotada a su mes y su transacción · B10 historia
-- inmutable y permisos · B11 solo un mes con metas admite plazo y reapertura, nombres en blanco (Codex r1/r2) · B12
-- con un mes ampliado, los meses siguientes esperan (Codex r2). La carrera del sello con una ampliación (Codex r1, P1)
-- necesita dos sesiones: dos-sesiones.py, T7/T8.
-- ⚠️ RELOJ: el «después del plazo» de B2 solo se puede ejercitar desde el día 11 del mes (antes, el plazo base del mes
-- anterior todavía no venció y ninguna decisión puede ser anterior a la base); lo dice con un NOTICE y no lo cuenta.
-- ⚠️ Sin `set role` contra funciones: en esta imagen, llamar a una función SIN permiso de EXECUTE tumba el backend
-- (memoria postgres-cae-por-permiso-de-funcion). Los permisos de las funciones se comprueban por catálogo; los de las
-- tablas, con `set role` (eso sí da un error normal).
-- ---------------------------------------------------------------------------------------------------------------------
\set ON_ERROR_STOP on

begin;
set local timezone = 'UTC';
set local lock_timeout = '10s';

-- ── Ayudantes ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- La identidad, por los claims del JWT (las dos formas que lee auth.uid()). NULL = sin sesión (el reloj, la consola).
create function pg_temp.como(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true),
         set_config('request.jwt.claims',
           case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
$$;

create table pg_temp.casos (n serial primary key, bloque text not null, caso text not null);

-- Aserción: si no se cumple, «PRUEBA FALLA»; si se cumple, devuelve el nombre del caso (se acumula en el bloque y se
-- registra al final, fuera de la subtransacción que se deshace).
create function pg_temp.exigir(p_condicion boolean, p_bloque text, p_caso text, p_detalle text default '')
returns text language plpgsql as $$
begin
  if p_condicion is not true then
    raise exception 'PRUEBA FALLA [%] %: %', p_bloque, p_caso, coalesce(p_detalle, '(sin detalle)');
  end if;
  return p_caso;
end $$;

-- Ejecuta y devuelve «SQLSTATE mensaje» o 'SIN ERROR' (lo que hizo, si falló, se deshace solo).
create function pg_temp.error_de(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'SIN ERROR';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

-- Ejecuta lo que DEBE salir bien y devuelve su jsonb; si falla, es una aserción caída (no un error cualquiera).
create function pg_temp.resultado(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute p_sql into v;
  return v;
exception when others then
  raise exception 'PRUEBA FALLA [llamada] % → % %', p_sql, sqlstate, sqlerrm;
end $$;

create table pg_temp.ids (nombre text primary key, id uuid not null unique);
insert into pg_temp.ids values
  ('G',   'ca7e1500-0000-4000-8000-0000000000a1'),  -- gerencia
  ('G2',  'ca7e1500-0000-4000-8000-0000000000a2'),  -- otra gerencia
  ('GI',  'ca7e1500-0000-4000-8000-0000000000a3'),  -- gerencia dada de baja (equipo inactivo)
  ('SA',  'ca7e1500-0000-4000-8000-0000000000a4'),  -- superadmin del Portal sin membresía CRM
  ('ADM', 'ca7e1500-0000-4000-8000-0000000000a5'),  -- admin del Portal sin membresía CRM
  ('S',   'ca7e1500-0000-4000-8000-0000000000b1'),  -- supervisor
  ('V',   'ca7e1500-0000-4000-8000-0000000000b2'),  -- analista con meta
  ('V2',  'ca7e1500-0000-4000-8000-0000000000b3'),  -- analista sin meta
  ('CO',  'ca7e1500-0000-4000-8000-0000000000b4'),  -- coordinador
  ('DI',  'ca7e1500-0000-4000-8000-0000000000b5'),  -- directorio
  ('CLI', 'ca7e1500-0000-4000-8000-0000000000c1');  -- cliente del Portal
create function pg_temp.id(p text) returns uuid language sql stable as $$ select id from pg_temp.ids where nombre = p $$;

-- Las fechas de la prueba salen del reloj de la transacción, en Lima (como el servidor).
create table pg_temp.f as
select (now() at time zone 'America/Lima')::date as hoy,
       date_trunc('month', now() at time zone 'America/Lima')::date as m0,
       (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date as m1,
       (date_trunc('month', now() at time zone 'America/Lima') - interval '2 month')::date as m2,
       (date_trunc('month', now() at time zone 'America/Lima') - interval '3 month')::date as m3;

-- Sello SINTÉTICO de un mes (sin pasar por crm.cerrar_periodo): sello + foto de V, con los disparadores apagados SOLO
-- para sembrar, como los ensayos de la casa. Lo que se MIDE corre siempre con los disparadores encendidos.
create function pg_temp.sellar(p_periodo date, p_con_foto boolean, p_ajuste numeric default 0) returns void
language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into crm.periodos_cerrados (periodo, cerrado_en, automatico, ponderacion_referido, meta_revision, cobertura)
  values (p_periodo, (p_periodo + interval '1 month 10 days 9 hours 20 minutes')::timestamp at time zone 'America/Lima',
          true, 0.15, 1, '{}'::jsonb);
  if p_con_foto then
    insert into crm.cierre_mes_vendedor (periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor,
      cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador, estado, referidos_recibidos,
      referidos_dados_de_alta, conversion_objetivo, ajuste_numerador)
    values (p_periodo, pg_temp.id('V'), 'ANALISTA PRUEBA PLAZO', pg_temp.id('S'), 'SUPERVISOR PRUEBA PLAZO', 10, 1, 0, 0, 1,
            'sellado', 0, 0, 10, p_ajuste);
  end if;
  set local session_replication_role = origin;
end $$;

-- Un lead convertido con su episodio (forma real de crm.lead_asignaciones) y su persona. Devuelve el episodio.
create function pg_temp.lead_convertido(p_lead uuid, p_vendedor uuid, p_persona uuid, p_cuando timestamptz) returns uuid
language plpgsql as $$
declare v_ep uuid;
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, etapa, origen, vendedor_id, inversionista_id, convertido_en,
                         monto_estimado, creado_en)
  values (p_lead, 'LEAD SINTETICO PLAZO', '+5196' || lpad((abs(hashtext(p_lead::text)) % 10000000)::text, 7, '0'),
          'convertido', 'formulario', p_vendedor, p_persona, p_cuando, 1000, p_cuando - interval '5 days');
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda,
      origen, sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en,
      resultado, resultado_en, finalizado_en, finalizado_por, motivo_cierre)
  values (p_lead, 1, 1, p_vendedor, 'asignado', p_cuando - interval '5 days', 'PEN', 'formulario',
          p_cuando - interval '5 days', gen_random_uuid(), p_cuando - interval '5 days', p_cuando - interval '5 days',
          'convertido', p_cuando, p_cuando, p_vendedor, 'convertido')
  returning id into v_ep;
  set local session_replication_role = origin;
  return v_ep;
end $$;

create function pg_temp.persona(p_id uuid, p_canonica uuid default null) returns void language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into crm.inversionistas (id, estado, inversionista_canonico_id, fusionado_en)
  values (p_id, case when p_canonica is null then 'activo' else 'fusionado' end, p_canonica,
          case when p_canonica is null then null else now() - interval '1 day' end);
  set local session_replication_role = origin;
end $$;

-- Un cierre en cooperativa con la forma real (F4: los no iniciales llevan persona, fechas, comprobante y referencia).
-- El comprobante es un objeto de Storage (llave foránea): se siembra su fila, porque una fila insertada en la misma
-- transacción vuelve a comprobar sus llaves al actualizarse (en producción el objeto ya existe).
create function pg_temp.cierre(p_id uuid, p_lead uuid, p_vendedor uuid, p_persona uuid, p_fecha date, p_imputacion date,
                               p_inicial boolean, p_monto numeric) returns void language plpgsql as $$
declare v_obj uuid := case when p_inicial then null else gen_random_uuid() end;
begin
  set local session_replication_role = replica;
  if v_obj is not null then
    insert into storage.objects (id, bucket_id, name) values (v_obj, 'comprobantes-prueba-plazo', 'plazo/' || p_id::text);
  end if;
  insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
      numero_transaccion, vendedor_id, creado_por, inversionista_id, es_cierre_inicial, fecha_comercial, fecha_imputacion,
      comprobante_objeto_id, referencia_externa)
  values (p_id, p_lead, 'qorilazo', p_monto, 'PEN', 'DNI', '7' || lpad((abs(hashtext(p_id::text)) % 10000000)::text, 7, '0'),
          'CLIENTE SINTETICO PLAZO', 'OP-PLAZO-' || replace(p_id::text, '-', ''), p_vendedor, p_vendedor, p_persona,
          p_inicial, p_fecha, p_imputacion, v_obj, case when p_inicial then null else 'REF-' || left(p_id::text, 8) end);
  set local session_replication_role = origin;
end $$;

-- Una inversión (fuente = cierre o contrato) y, si se pide, su rastro de registro tardío.
create function pg_temp.inversion(p_id uuid, p_persona uuid, p_cierre uuid, p_contrato uuid, p_fecha date) returns void
language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into crm.inversiones (id, inversionista_id, empresa_id, contrato_id, cierre_externo_id, estado, fecha_comercial)
  values (p_id, p_persona, gen_random_uuid(), p_contrato, p_cierre, 'vigente', p_fecha);
  set local session_replication_role = origin;
end $$;

create function pg_temp.rastro(p_inversion uuid, p_periodo date, p_imputacion date) returns void language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into crm.inversion_ajustes_mes_cerrado (inversion_id, periodo_origen, fecha_imputacion, creado_por)
  values (p_inversion, p_periodo, p_imputacion, pg_temp.id('G'));
  set local session_replication_role = origin;
end $$;

-- Una acreditación de conversión con la forma real (acreditado_en = el mayor de confirmado y vinculado; plazo = base).
create function pg_temp.acreditacion(p_lead uuid, p_episodio uuid, p_persona uuid, p_fuente_tipo text, p_fuente uuid,
    p_fecha date, p_acreditado timestamptz, p_estado text, p_sellado timestamptz default null,
    p_incluida boolean default null, p_ajuste numeric default null) returns uuid language sql as $$
  insert into crm.conversion_acreditaciones (lead_id, episodio_id, inversionista_id, analista_id, origen, fuente_tipo,
      fuente_id, fecha_comercial, confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado,
      sellado_en, incluida_en_sello, ajuste_anulacion_en_sello, motivo)
  values (p_lead, p_episodio, p_persona, pg_temp.id('V'), 'formulario', p_fuente_tipo, p_fuente, p_fecha, p_acreditado,
          p_acreditado, p_acreditado, date_trunc('month', p_fecha::timestamp)::date,
          private.conversion_plazo_base(date_trunc('month', p_fecha::timestamp)::date), p_estado, p_sellado, p_incluida,
          p_ajuste, 'Siembra de la prueba del plazo de carga')
  returning id;
$$;

-- La forma exacta del payload de la lectura (el front la valida con strictObject).
create function pg_temp.claves(p jsonb) returns text language sql immutable as $$
  select string_agg(k, ',' order by k) from jsonb_object_keys(p) k
$$;

-- ── Siembra común (el mundo de producción del 14/10, sintético) ──────────────────────────────────────────────────────
do $siembra$
declare
  v_mp1 uuid := gen_random_uuid(); v_mp2 uuid := gen_random_uuid();
  v_mv1 uuid := gen_random_uuid(); v_mv2 uuid := gen_random_uuid();
  f record;
begin
  select * into f from pg_temp.f;
  if exists (select 1 from crm.periodos_cerrados) or exists (select 1 from crm.meta_periodos)
     or exists (select 1 from crm.plazos_carga_mes) or exists (select 1 from crm.reaperturas_mes) then
    raise exception 'PRUEBA ABORTADA: el banco ya tiene sellos, metas, plazos o reaperturas; correrla en un banco sin datos';
  end if;
  if exists (select 1 from public.perfiles p where p.id in (select id from pg_temp.ids)) then
    raise exception 'PRUEBA ABORTADA: ya existen perfiles con los ids fijos de la prueba';
  end if;
  if f.m1 < date '2026-09-01' then
    raise exception 'PRUEBA ABORTADA: el mes anterior tiene que ser de la política de conversión (desde septiembre 2026)';
  end if;

  -- Personas: perfiles con los disparadores y llaves apagados (perfiles.id cuelga de auth.users).
  set local session_replication_role = replica;
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (pg_temp.id('G'), 'GERENCIA PRUEBA PLAZO', 'comercial', true),
    (pg_temp.id('G2'), 'GERENCIA DOS PRUEBA PLAZO', 'comercial', true),
    (pg_temp.id('GI'), 'GERENCIA DE BAJA PRUEBA PLAZO', 'comercial', true),
    (pg_temp.id('SA'), 'SUPERADMIN PRUEBA PLAZO', 'superadmin', true),
    (pg_temp.id('ADM'), 'ADMIN PRUEBA PLAZO', 'admin', true),
    (pg_temp.id('S'), 'SUPERVISOR PRUEBA PLAZO', 'comercial', true),
    (pg_temp.id('V'), 'ANALISTA PRUEBA PLAZO', 'comercial', true),
    (pg_temp.id('V2'), 'ANALISTA SIN META PRUEBA PLAZO', 'comercial', true),
    (pg_temp.id('CO'), 'COORDINACION PRUEBA PLAZO', 'comercial', true),
    (pg_temp.id('DI'), 'DIRECTORIO PRUEBA PLAZO', 'directorio', true),
    (pg_temp.id('CLI'), 'CLIENTE PRUEBA PLAZO', 'cliente', true);
  set local session_replication_role = origin;

  -- El equipo del CRM con sus disparadores encendidos (alta de consola, sin sesión).
  perform pg_temp.como(null);
  insert into crm.equipo (perfil_id, rol_crm, activo) values
    (pg_temp.id('G'), 'gerencia', true), (pg_temp.id('G2'), 'gerencia', true), (pg_temp.id('S'), 'supervisor', true),
    (pg_temp.id('CO'), 'coordinador', true), (pg_temp.id('DI'), 'directorio', true), (pg_temp.id('GI'), 'gerencia', true);
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
    (pg_temp.id('V'), 'vendedor', pg_temp.id('S'), true), (pg_temp.id('V2'), 'vendedor', pg_temp.id('S'), true);
  update crm.equipo set activo = false where perfil_id = pg_temp.id('GI');
  if private.rol_crm(pg_temp.id('G')) is distinct from 'gerencia' or private.rol_crm(pg_temp.id('G2')) is distinct from 'gerencia'
     or private.rol_crm(pg_temp.id('GI')) is not null or private.rol_crm(pg_temp.id('SA')) is not null
     or private.rol_crm(pg_temp.id('ADM')) is not null or private.rol_crm(pg_temp.id('S')) is distinct from 'supervisor'
     or private.rol_crm(pg_temp.id('V')) is distinct from 'vendedor' or private.rol_crm(pg_temp.id('CO')) is distinct from 'coordinador'
     or private.rol_crm(pg_temp.id('DI')) is distinct from 'directorio' or private.rol_crm(pg_temp.id('CLI')) is not null then
    raise exception 'PRUEBA ABORTADA: la siembra no dio los roles CRM esperados';
  end if;

  insert into crm.conversion_pesos (vigente_desde, peso_referido, nota) values (date '2025-01-01', 0.150, 'prueba plazo');
  insert into crm.conversion_politica (unica, vigente_desde, activada_en, manifiesto_huella, resultado)
  values (true, date '2026-09-01', now() - interval '45 days', 'prueba-plazo', '{}'::jsonb);
  insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por) values
    (v_mp2, f.m2, 1, now(), pg_temp.id('G')), (v_mp1, f.m1, 1, now(), pg_temp.id('G'));
  insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo) values
    (v_mv2, v_mp2, pg_temp.id('V'), pg_temp.id('S'), 10), (v_mv1, v_mp1, pg_temp.id('V'), pg_temp.id('S'), 10);
  insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo) values
    (v_mv2, 'nuevo', 'PEN', 100000, 5), (v_mv1, 'nuevo', 'PEN', 100000, 5);
  -- Hace dos meses, sellado (como agosto en producción); el mes anterior queda pendiente.
  perform pg_temp.sellar(f.m2, true);
  if private.cierre_mes_pendiente(f.m0) is distinct from f.m1 then
    raise exception 'PRUEBA ABORTADA: el mes pendiente no es el anterior';
  end if;
end
$siembra$;

-- ── B1 · El plazo base: nada cambia sin decisión ─────────────────────────────────────────────────────────────────────
do $b1$
declare
  c text[] := '{}'; b text := 'B1 plazo base'; f record; v_base timestamptz; v_r jsonb; v_e text; m jsonb;
begin
  select * into f from pg_temp.f;
  begin
    v_base := (f.m1::timestamp + interval '1 month 10 days') at time zone 'America/Lima';
    c := c || pg_temp.exigir(private.conversion_plazo_base(f.m1) = v_base, b, 'la base es el día 11 del mes siguiente, 00:00 de Lima');
    c := c || pg_temp.exigir(private.conversion_plazo_hasta(f.m1) = v_base, b, 'sin decisión, el plazo vigente es la base');
    c := c || pg_temp.exigir(private.cierre_mes_ventana_desde(f.m1) = v_base, b, 'sin decisión, la ventana del sello es la base');
    v_e := pg_temp.error_de(format('select private.conversion_plazo_hasta(%L::date)', f.m1 + 1));
    c := c || pg_temp.exigir(v_e = '22023 El periodo debe ser el primer dia de un mes finito', b, 'periodo que no es primer día → 22023', v_e);
    v_e := pg_temp.error_de('select private.conversion_plazo_base(''infinity''::date)');
    c := c || pg_temp.exigir(v_e = '22023 El periodo debe ser el primer dia de un mes finito', b, 'periodo infinito → 22023', v_e);
    v_e := private.reapertura_impedimento(f.m1);
    c := c || pg_temp.exigir(v_e = private.etiqueta_mes_es(f.m1) || ' ' || to_char(f.m1, 'YYYY') || ' no está cerrado: no hay nada que reabrir',
                             b, 'un mes abierto no se «reabre»', v_e);
    select d.estado into v_e from private.conversion_decidir_plazo(f.m1 + 5, v_base - interval '1 minute', v_base - interval '1 minute', null) d;
    c := c || pg_temp.exigir(v_e = 'acreditada', b, 'antes de la base se acredita', v_e);
    select d.estado into v_e from private.conversion_decidir_plazo(f.m1 + 5, v_base, v_base, null) d;
    c := c || pg_temp.exigir(v_e = 'fuera_de_plazo', b, 'en la base (extremo excluido) queda fuera de plazo', v_e);

    perform pg_temp.como(pg_temp.id('G'));
    v_r := pg_temp.resultado('select crm.cierre_mes_estado_fn()');
    c := c || pg_temp.exigir(v_r #>> '{pendiente,mes}' = to_char(f.m1, 'YYYY-MM')
                             and (v_r #>> '{pendiente,cierra_el}')::date = (v_base at time zone 'America/Lima')::date,
                             b, 'el aviso de cierre muestra la base', v_r::text);
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    c := c || pg_temp.exigir(pg_temp.claves(v_r) = 'generado_en,hoy,meses,version,zona' and v_r ->> 'version' = '1'
                             and v_r ->> 'zona' = 'America/Lima' and (v_r ->> 'hoy')::date = f.hoy,
                             b, 'lectura: cabecera exacta', v_r::text);
    c := c || pg_temp.exigir(jsonb_array_length(v_r -> 'meses') = 2 and v_r #>> '{meses,0,mes}' = to_char(f.m1, 'YYYY-MM')
                             and v_r #>> '{meses,1,mes}' = to_char(f.m0, 'YYYY-MM'),
                             b, 'lectura: mes pendiente/anterior y mes en curso, en orden', v_r::text);
    m := v_r -> 'meses' -> 0;
    c := c || pg_temp.exigir(pg_temp.claves(m) = 'ampliado,decision,mes,mes_nombre,motivo_no_reabrible,plazo_base_ultimo_dia,plazo_ultimo_dia,reabrible,sellado,ultima_reapertura',
                             b, 'lectura: claves exactas por mes', m::text);
    c := c || pg_temp.exigir(m ->> 'sellado' = 'false' and (m ->> 'plazo_base_ultimo_dia')::date = f.m0 + 9
                             and (m ->> 'plazo_ultimo_dia')::date = f.m0 + 9 and m ->> 'ampliado' = 'false'
                             and jsonb_typeof(m -> 'decision') = 'null' and m ->> 'reabrible' = 'false'
                             and jsonb_typeof(m -> 'motivo_no_reabrible') = 'null' and jsonb_typeof(m -> 'ultima_reapertura') = 'null'
                             and m ->> 'mes_nombre' = private.etiqueta_mes_es(f.m1) || ' ' || to_char(f.m1, 'YYYY'),
                             b, 'lectura: mes abierto sin decisión (último día incluido = el 10)', m::text);
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b1$;

-- ── B2 · Ampliar: el plazo y la ventana cambian; el ciclo no sella antes y sí después ───────────────────────────────
do $b2$
declare
  c text[] := '{}'; b text := 'B2 ampliar'; f record; v_base timestamptz; v_nuevo timestamptz; v_r jsonb; v_e text;
  v_ep uuid; v_ok uuid; v_fp uuid; m jsonb; v_dec record; v_sello timestamptz;
  l1 uuid := 'ca7e1502-0000-4000-8000-000000000001'; l2 uuid := 'ca7e1502-0000-4000-8000-000000000002';
  p1 uuid := 'ca7e1502-0000-4000-8000-0000000000e1'; p2 uuid := 'ca7e1502-0000-4000-8000-0000000000e2';
  ce1 uuid := 'ca7e1502-0000-4000-8000-0000000000f1'; ce2 uuid := 'ca7e1502-0000-4000-8000-0000000000f2';
begin
  select * into f from pg_temp.f;
  begin
    v_base := (f.m1::timestamp + interval '1 month 10 days') at time zone 'America/Lima';
    v_nuevo := (f.hoy + 7)::timestamp at time zone 'America/Lima';
    -- Dos conversiones del mes anterior: una acreditada a tiempo y una que llegó fuera de plazo.
    perform pg_temp.persona(p1); perform pg_temp.persona(p2);
    v_ep := pg_temp.lead_convertido(l1, pg_temp.id('V'), p1, f.m1::timestamp at time zone 'America/Lima' + interval '10 days');
    perform pg_temp.cierre(ce1, l1, pg_temp.id('V'), p1, f.m1 + 10, f.m1 + 10, true, 5000);
    v_ok := pg_temp.acreditacion(l1, v_ep, p1, 'cierre_externo', ce1, f.m1 + 10, v_base - interval '3 days', 'acreditada');
    v_ep := pg_temp.lead_convertido(l2, pg_temp.id('V'), p2, f.m1::timestamp at time zone 'America/Lima' + interval '12 days');
    perform pg_temp.cierre(ce2, l2, pg_temp.id('V'), p2, f.m1 + 12, f.m1 + 12, true, 7000);
    v_fp := pg_temp.acreditacion(l2, v_ep, p2, 'cierre_externo', ce2, f.m1 + 12, now() - interval '2 hours', 'fuera_de_plazo');

    perform pg_temp.como(pg_temp.id('G'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 6,
                                    E'  Analistas cargan tarde\t'));
    c := c || pg_temp.exigir(pg_temp.claves(v_r) = 'acreditaciones_reevaluadas,conflictos_identidad,mes,ok,plazo_hasta,reabierto,reapertura_id,ultimo_dia,ventas_devueltas',
                             b, 'respuesta: claves exactas', v_r::text);
    c := c || pg_temp.exigir(v_r ->> 'ok' = 'true' and v_r ->> 'mes' = to_char(f.m1, 'YYYY-MM')
                             and (v_r ->> 'ultimo_dia')::date = f.hoy + 6 and (v_r ->> 'plazo_hasta')::timestamptz = v_nuevo
                             and v_r ->> 'reabierto' = 'false' and jsonb_typeof(v_r -> 'reapertura_id') = 'null'
                             and v_r -> 'ventas_devueltas' = '[]'::jsonb,
                             b, 'respuesta: plazo = 00:00 de Lima del día siguiente al último día', v_r::text);
    c := c || pg_temp.exigir((v_r ->> 'acreditaciones_reevaluadas')::int = 1 and (v_r ->> 'conflictos_identidad')::int = 0,
                             b, 'respuesta: una reevaluada, sin conflictos', v_r::text);
    select * into v_dec from crm.plazos_carga_mes where periodo = f.m1;
    c := c || pg_temp.exigir(v_dec.motivo = 'Analistas cargan tarde' and v_dec.decidido_por = pg_temp.id('G')
                             and v_dec.reapertura_id is null and v_dec.ultimo_dia = f.hoy + 6 and v_dec.plazo_hasta = v_nuevo,
                             b, 'decisión guardada con el motivo normalizado y el actor de la sesión', to_jsonb(v_dec)::text);
    c := c || pg_temp.exigir(exists (select 1 from public.audit_log a where a.tabla = 'crm.plazos_carga_mes'
                                      and a.operacion = 'INSERT' and a.fila_id::uuid = v_dec.id and a.usuario_id = pg_temp.id('G')),
                             b, 'la decisión queda en la auditoría con su autor');
    c := c || pg_temp.exigir(private.conversion_plazo_hasta(f.m1) = v_nuevo and private.cierre_mes_ventana_desde(f.m1) = v_nuevo
                             and private.conversion_plazo_base(f.m1) = v_base,
                             b, 'el plazo vigente y la ventana son los nuevos; la base no cambia');
    select d.estado into v_e from private.conversion_decidir_plazo(f.m1 + 5, now(), now(), null) d;
    c := c || pg_temp.exigir(v_e = 'acreditada', b, 'una conversión que llega ahora se acredita', v_e);
    c := c || pg_temp.exigir((select estado = 'acreditada' and plazo_hasta = v_nuevo from crm.conversion_acreditaciones where id = v_fp)
                             and (select estado = 'acreditada' and plazo_hasta = v_base from crm.conversion_acreditaciones where id = v_ok),
                             b, 'la que estaba fuera de plazo pasa a acreditada con el plazo nuevo; la otra no se toca');
    v_r := pg_temp.resultado('select crm.cierre_mes_estado_fn()');
    c := c || pg_temp.exigir((v_r #>> '{pendiente,cierra_el}')::date = f.hoy + 7 and v_r #>> '{pendiente,estado}' = 'en_ventana',
                             b, 'el aviso de cierre refleja el plazo nuevo sin cambiar su forma', v_r::text);
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    m := v_r -> 'meses' -> 0;
    c := c || pg_temp.exigir((m ->> 'plazo_ultimo_dia')::date = f.hoy + 6 and m ->> 'ampliado' = 'true'
                             and (m #>> '{decision,ultimo_dia}')::date = f.hoy + 6
                             and m #>> '{decision,motivo}' = 'Analistas cargan tarde'
                             and m #>> '{decision,decidido_por}' = 'GERENCIA PRUEBA PLAZO'
                             and pg_temp.claves(m -> 'decision') = 'decidido_en,decidido_por,motivo,ultimo_dia',
                             b, 'la lectura muestra la decisión, quién y por qué', m::text);

    -- El reloj no sella antes del plazo; Gerencia a mano tampoco.
    perform pg_temp.como(null);
    v_r := pg_temp.resultado('select crm.ciclo_cierre_mes()');
    c := c || pg_temp.exigir((v_r ->> 'ok')::boolean and (v_r ->> 'cerrados')::int = 0
                             and not exists (select 1 from crm.periodos_cerrados where periodo = f.m1),
                             b, 'el ciclo NO sella antes del plazo ampliado', v_r::text);
    perform pg_temp.como(pg_temp.id('G'));
    v_e := pg_temp.error_de(format('select crm.cerrar_periodo(%L::date)', f.m1));
    c := c || pg_temp.exigir(v_e like '22023 El mes % no se puede cerrar antes del %', b,
                             'Gerencia tampoco lo sella a mano antes del plazo', v_e);

    -- Después del plazo, sí: se mueve el reloj con una decisión directa (como postgres) ya vencida y ≥ base.
    if f.hoy >= f.m0 + 10 then
      insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por)
      values (f.m1, f.hoy - 1, f.hoy::timestamp at time zone 'America/Lima', 'Reloj movido por la prueba', pg_temp.id('G2'));
      c := c || pg_temp.exigir(private.conversion_plazo_hasta(f.m1) = f.hoy::timestamp at time zone 'America/Lima', b,
                               'vale la última decisión');
      perform pg_temp.como(null);
      v_r := pg_temp.resultado('select crm.ciclo_cierre_mes()');
      c := c || pg_temp.exigir((v_r ->> 'ok')::boolean and (v_r ->> 'cerrados')::int = 1
                               and v_r #>> '{detalle,0,periodo}' = to_char(f.m1, 'YYYY-MM'),
                               b, 'vencido el plazo, el ciclo sí sella el mes', v_r::text);
      select pc.cerrado_en into v_sello from crm.periodos_cerrados pc where pc.periodo = f.m1;
      -- El trigger del sello marca filas YA decididas con plazos distintos (la base y el ampliado): el CHECK nuevo lo deja.
      c := c || pg_temp.exigir((select bool_and(ca.sellado_en = v_sello) from crm.conversion_acreditaciones ca
                                 where ca.periodo_comercial = f.m1)
                               and (select plazo_hasta from crm.conversion_acreditaciones where id = v_ok) = v_base
                               and (select plazo_hasta from crm.conversion_acreditaciones where id = v_fp) = v_nuevo,
                               b, 'el sello marca las acreditaciones y cada una conserva el plazo con que se decidió');
    else
      raise notice 'B2: hoy es día % del mes: «después del plazo» no se puede ejercitar antes del día 11 (NO EJECUTADO)',
        extract(day from f.hoy);
    end if;
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b2$;

-- ── B3 · Acortar: vale la última decisión ────────────────────────────────────────────────────────────────────────────
do $b3$
declare c text[] := '{}'; b text := 'B3 acortar'; f record; v_r jsonb; v_base0 timestamptz;
begin
  select * into f from pg_temp.f;
  begin
    perform pg_temp.como(pg_temp.id('G'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 10, 'Primera decisión de prueba'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 3, 'Segunda decisión: acortar'));
    c := c || pg_temp.exigir(private.conversion_plazo_hasta(f.m1) = (f.hoy + 4)::timestamp at time zone 'America/Lima'
                             and (select count(*) from crm.plazos_carga_mes where periodo = f.m1) = 2,
                             b, 'acortar: el plazo vigente es el de la última decisión, y las dos quedan');
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    c := c || pg_temp.exigir((v_r #>> '{meses,0,decision,ultimo_dia}')::date = f.hoy + 3
                             and v_r #>> '{meses,0,decision,motivo}' = 'Segunda decisión: acortar',
                             b, 'la lectura muestra la última decisión', v_r::text);
    -- Mes en curso: fijarlo exactamente en su base (día 10 del mes siguiente) se admite y no cuenta como ampliado. Solo
    -- un mes con metas publicadas admite plazo (revisión Codex r2): se publican las del mes en curso.
    insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por)
    values (gen_random_uuid(), f.m0, 1, now(), pg_temp.id('G'));
    v_base0 := (f.m0::timestamp + interval '1 month 10 days') at time zone 'America/Lima';
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m0,
                                    (v_base0 at time zone 'America/Lima')::date - 1, 'El mes en curso en su base'));
    c := c || pg_temp.exigir((v_r ->> 'plazo_hasta')::timestamptz = v_base0, b, 'el mes en curso admite su base exacta', v_r::text);
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    c := c || pg_temp.exigir(v_r #>> '{meses,1,mes}' = to_char(f.m0, 'YYYY-MM') and v_r #>> '{meses,1,ampliado}' = 'false'
                             and jsonb_typeof(v_r #> '{meses,1,decision}') = 'object',
                             b, 'en su base: decisión visible, no ampliado', v_r::text);
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b3$;

-- ── B4 · Validaciones (22023, sin escribir nada) ─────────────────────────────────────────────────────────────────────
do $b4$
declare
  c text[] := '{}'; b text := 'B4 validaciones'; f record; v_e text; r record; v_r jsonb;
begin
  select * into f from pg_temp.f;
  begin
    -- Hace tres meses, SIN sellar y con metas (estado heredado: metas publicadas hacia atrás antes de que el candado de
    -- metas lo impidiera; con los disparadores apagados solo para sembrar). Sin metas, la regla de metas (Codex r2) lo
    -- cortaría antes y no se probaría la negativa «por detrás del último cierre».
    set local session_replication_role = replica;
    insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por)
    values (gen_random_uuid(), f.m3, 1, now(), pg_temp.id('G'));
    set local session_replication_role = origin;
    perform pg_temp.como(pg_temp.id('G'));
    for r in
      select * from (values
        (format('%L::date, %L::date, %L', f.m1 + 1, f.hoy + 5, 'motivo válido'), '22023 Elige un mes válido (el primer día del mes)', 'mes que no es primer día'),
        (format('null::date, %L::date, %L', f.hoy + 5, 'motivo válido'), '22023 Elige un mes válido (el primer día del mes)', 'mes nulo'),
        (format('''infinity''::date, %L::date, %L', f.hoy + 5, 'motivo válido'), '22023 Elige un mes válido (el primer día del mes)', 'mes infinito'),
        (format('%L::date, %L::date, %L', (f.m0 + interval '1 month')::date, f.hoy + 60, 'motivo válido'), '22023 No se fija el plazo de un mes que todavía no empieza', 'mes futuro'),
        (format('%L::date, null::date, %L', f.m1, 'motivo válido'), '22023 Indica el último día en que se puede cargar', 'último día nulo'),
        (format('%L::date, ''infinity''::date, %L', f.m1, 'motivo válido'), '22023 Indica el último día en que se puede cargar', 'último día infinito'),
        (format('%L::date, %L::date, %L', f.m1, f.hoy - 1, 'motivo válido'), '22023 El último día de carga no puede ser anterior a hoy', 'último día en el pasado'),
        (format('%L::date, %L::date, %L', f.m0, f.hoy, 'motivo válido'), '22023 El plazo de % no puede terminar antes del %', 'antes de la base del mes'),
        (format('%L::date, %L::date, %L', f.m3, f.hoy + 5, 'motivo válido'), '22023 % quedó por detrás del último mes cerrado (%): ya no admite plazo de carga', 'mes sin sellar por detrás del último cierre'),
        (format('%L::date, %L::date, %L', f.m1, f.hoy + 5, 'abcd'), '22023 El motivo debe tener entre 5 y 300 caracteres', 'motivo de 4'),
        (format('%L::date, %L::date, %L', f.m1, f.hoy + 5, E'  \t ab \n  '), '22023 El motivo debe tener entre 5 y 300 caracteres', 'motivo corto rodeado de blancos'),
        (format('%L::date, %L::date, null', f.m1, f.hoy + 5), '22023 El motivo debe tener entre 5 y 300 caracteres', 'motivo nulo'),
        (format('%L::date, %L::date, %L', f.m1, f.hoy + 5, repeat('x', 301)), '22023 El motivo debe tener entre 5 y 300 caracteres', 'motivo de 301')
      ) t(args, esperado, caso)
    loop
      v_e := pg_temp.error_de('select crm.fijar_plazo_carga_mes(' || r.args || ')');
      c := c || pg_temp.exigir(v_e like r.esperado || '%', b, r.caso, v_e);
    end loop;
    c := c || pg_temp.exigir(not exists (select 1 from crm.plazos_carga_mes) and not exists (select 1 from crm.reaperturas_mes),
                             b, 'ninguna validación escribe');
    -- Los bordes que SÍ valen: hoy, motivo de 5 y de 300.
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy, 'cinco'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy, repeat('y', 300)));
    c := c || pg_temp.exigir((select count(*) from crm.plazos_carga_mes) = 2
                             and private.conversion_plazo_hasta(f.m1) = (f.hoy + 1)::timestamp at time zone 'America/Lima',
                             b, 'hoy como último día y motivos de 5 y 300 caracteres se admiten');
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b4$;

-- ── B5 · Gate: solo Gerencia (42501 para todos los demás, sin escribir) ──────────────────────────────────────────────
do $b5$
declare c text[] := '{}'; b text := 'B5 gate por rol'; f record; v_e text; v_a text; v_r jsonb;
begin
  select * into f from pg_temp.f;
  begin
    foreach v_a in array array['sin sesión', 'V', 'V2', 'S', 'CO', 'DI', 'GI', 'SA', 'ADM', 'CLI'] loop
      perform pg_temp.como(case when v_a = 'sin sesión' then null else pg_temp.id(v_a) end);
      v_e := pg_temp.error_de(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 5, 'Intento sin permiso'));
      c := c || pg_temp.exigir(v_e = '42501 Solo Gerencia decide el plazo de carga de un mes', b, 'fijar plazo: ' || v_a || ' → 42501', v_e);
      v_e := pg_temp.error_de('select crm.plazos_carga_mes_fn()');
      c := c || pg_temp.exigir(v_e = '42501 Solo Gerencia ve y decide los plazos de carga', b, 'leer plazos: ' || v_a || ' → 42501', v_e);
    end loop;
    c := c || pg_temp.exigir(not exists (select 1 from crm.plazos_carga_mes), b, 'nadie sin permiso escribió');
    perform pg_temp.como(pg_temp.id('G2'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 5, 'La otra Gerencia también decide'));
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    c := c || pg_temp.exigir(v_r #>> '{meses,0,decision,decidido_por}' = 'GERENCIA DOS PRUEBA PLAZO', b,
                             'cualquier Gerencia activa decide y queda su nombre', v_r::text);
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b5$;

-- ── B6 · Reevaluación al fijar el plazo ──────────────────────────────────────────────────────────────────────────────
do $b6$
declare
  c text[] := '{}'; b text := 'B6 reevaluación'; f record; v_r jsonb; v_nuevo timestamptz; v_base timestamptz;
  v_ep uuid; v_antes jsonb; v_lejos timestamptz;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; a6 uuid; a7 uuid; a8 uuid; a9 uuid; a10 uuid; a11 uuid; a12 uuid; a13 uuid;
  -- leads, personas y fuentes
  l uuid[] := array(select ('ca7e1506-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid from generate_series(1, 13) i);
  p uuid[] := array(select ('ca7e1506-0000-4000-8000-0000000001' || lpad(i::text, 2, '0'))::uuid from generate_series(1, 14) i);
  ce uuid[] := array(select ('ca7e1506-0000-4000-8000-0000000002' || lpad(i::text, 2, '0'))::uuid from generate_series(1, 13) i);
  v_contrato_demo uuid := 'ca7e1506-0000-4000-8000-000000000301';
begin
  select * into f from pg_temp.f;
  begin
    v_base := (f.m1::timestamp + interval '1 month 10 days') at time zone 'America/Lima';
    v_nuevo := (f.hoy + 6)::timestamp at time zone 'America/Lima';
    v_lejos := now() + interval '60 days';
    -- Personas: p[2] y p[3] son la MISMA identidad (p[2] fusionada en p[3]); p[11] y p[12] también (p[11] → p[12]).
    perform pg_temp.persona(p[1]); perform pg_temp.persona(p[3]); perform pg_temp.persona(p[2], p[3]);
    perform pg_temp.persona(p[4]); perform pg_temp.persona(p[5]); perform pg_temp.persona(p[6]); perform pg_temp.persona(p[7]);
    perform pg_temp.persona(p[8]); perform pg_temp.persona(p[9]); perform pg_temp.persona(p[10]);
    perform pg_temp.persona(p[12]); perform pg_temp.persona(p[11], p[12]);
    perform pg_temp.persona(p[13], p[3]);   -- p[13] es la misma identidad que p[3] (A3, acreditada)
    -- A1 fuera de plazo, cooperativa inicial (elegible) → acreditada.
    v_ep := pg_temp.lead_convertido(l[1], pg_temp.id('V'), p[1], now() - interval '3 days');
    perform pg_temp.cierre(ce[1], l[1], pg_temp.id('V'), p[1], f.m1 + 20, f.m1 + 20, true, 1000);
    a1 := pg_temp.acreditacion(l[1], v_ep, p[1], 'cierre_externo', ce[1], f.m1 + 20, now() - interval '3 days', 'fuera_de_plazo');
    -- A2 fuera de plazo, pero su identidad (p[2] → p[3]) ya tiene otra captación acreditada (A3, otro lead) → conflicto.
    v_ep := pg_temp.lead_convertido(l[2], pg_temp.id('V'), p[2], now() - interval '2 days');
    perform pg_temp.cierre(ce[2], l[2], pg_temp.id('V'), p[2], f.m1 + 21, f.m1 + 21, true, 1000);
    a2 := pg_temp.acreditacion(l[2], v_ep, p[2], 'cierre_externo', ce[2], f.m1 + 21, now() - interval '2 days', 'fuera_de_plazo');
    v_ep := pg_temp.lead_convertido(l[3], pg_temp.id('V'), p[3], f.m1::timestamp at time zone 'America/Lima' + interval '5 days');
    perform pg_temp.cierre(ce[3], l[3], pg_temp.id('V'), p[3], f.m1 + 5, f.m1 + 5, true, 1000);
    a3 := pg_temp.acreditacion(l[3], v_ep, p[3], 'cierre_externo', ce[3], f.m1 + 5, v_base - interval '20 days', 'acreditada');
    -- A4 fuera de plazo, contrato DEMO → fuente_demo (la exclusión del escritor).
    v_ep := pg_temp.lead_convertido(l[4], pg_temp.id('V'), p[4], now() - interval '3 days');
    set local session_replication_role = replica;
    insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, categoria, estado, creado_por, creado_en,
        modalidad, fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial, es_demo)
    values (v_contrato_demo, 'PLAZO-DEMO-0001', pg_temp.id('CLI'), 10000, 'PEN', 'nuevo', 'activo', pg_temp.id('V'),
            now() - interval '3 days', 'mensual', f.m1 + 22, f.m1 + 387, gen_random_uuid(), f.m1 + 22, true);
    set local session_replication_role = origin;
    a4 := pg_temp.acreditacion(l[4], v_ep, p[4], 'contrato', v_contrato_demo, f.m1 + 22, now() - interval '3 days', 'fuera_de_plazo');
    -- A5 fuera de plazo, cooperativa NO inicial (operación de cartera) → operacion_cartera.
    v_ep := pg_temp.lead_convertido(l[5], pg_temp.id('V'), p[5], now() - interval '3 days');
    perform pg_temp.cierre(ce[5], null, pg_temp.id('V'), p[5], f.m1 + 23, f.m1 + 23, false, 1000);
    a5 := pg_temp.acreditacion(l[5], v_ep, p[5], 'cierre_externo', ce[5], f.m1 + 23, now() - interval '3 days', 'fuera_de_plazo');
    -- A6 «mes_sellado» (se decidió después de un sello que ya no está) → acreditada.
    v_ep := pg_temp.lead_convertido(l[6], pg_temp.id('V'), p[6], now() - interval '3 days');
    perform pg_temp.cierre(ce[6], l[6], pg_temp.id('V'), p[6], f.m1 + 24, f.m1 + 24, true, 1000);
    a6 := pg_temp.acreditacion(l[6], v_ep, p[6], 'cierre_externo', ce[6], f.m1 + 24, now() - interval '3 days', 'mes_sellado');
    -- A7 ya acreditada → no se toca.
    v_ep := pg_temp.lead_convertido(l[7], pg_temp.id('V'), p[7], f.m1::timestamp at time zone 'America/Lima' + interval '6 days');
    perform pg_temp.cierre(ce[7], l[7], pg_temp.id('V'), p[7], f.m1 + 6, f.m1 + 6, true, 1000);
    a7 := pg_temp.acreditacion(l[7], v_ep, p[7], 'cierre_externo', ce[7], f.m1 + 6, v_base - interval '15 days', 'acreditada');
    -- A8 fuera de plazo y acreditada DESPUÉS del plazo nuevo → se queda (solo se reevalúa lo anterior al plazo).
    v_ep := pg_temp.lead_convertido(l[8], pg_temp.id('V'), p[8], now() - interval '3 days');
    perform pg_temp.cierre(ce[8], l[8], pg_temp.id('V'), p[8], f.m1 + 25, f.m1 + 25, true, 1000);
    a8 := pg_temp.acreditacion(l[8], v_ep, p[8], 'cierre_externo', ce[8], f.m1 + 25, v_lejos, 'fuera_de_plazo');
    -- A9 fuera de plazo con la fuente retirada (no existe) → se queda: el retiro lo coordina su propia regla.
    v_ep := pg_temp.lead_convertido(l[9], pg_temp.id('V'), p[9], now() - interval '3 days');
    a9 := pg_temp.acreditacion(l[9], v_ep, p[9], 'cierre_externo', ce[9], f.m1 + 26, now() - interval '3 days', 'fuera_de_plazo');
    -- A10 fuera de plazo de OTRO mes (hace dos meses) → no se toca.
    v_ep := pg_temp.lead_convertido(l[10], pg_temp.id('V'), p[10], now() - interval '3 days');
    perform pg_temp.cierre(ce[10], l[10], pg_temp.id('V'), p[10], f.m2 + 20, f.m2 + 20, true, 1000);
    a10 := pg_temp.acreditacion(l[10], v_ep, p[10], 'cierre_externo', ce[10], f.m2 + 20, now() - interval '3 days', 'fuera_de_plazo');
    -- A11 y A12: la MISMA identidad, las dos fuera de plazo: la primera en llegar se acredita, la otra choca.
    v_ep := pg_temp.lead_convertido(l[11], pg_temp.id('V'), p[11], now() - interval '4 days');
    perform pg_temp.cierre(ce[11], l[11], pg_temp.id('V'), p[11], f.m1 + 27, f.m1 + 27, true, 1000);
    a11 := pg_temp.acreditacion(l[11], v_ep, p[11], 'cierre_externo', ce[11], f.m1 + 27, now() - interval '4 days', 'fuera_de_plazo');
    v_ep := pg_temp.lead_convertido(l[12], pg_temp.id('V'), p[12], now() - interval '1 day');
    perform pg_temp.cierre(ce[12], l[12], pg_temp.id('V'), p[12], f.m1 + 28, f.m1 + 28, true, 1000);
    a12 := pg_temp.acreditacion(l[12], v_ep, p[12], 'cierre_externo', ce[12], f.m1 + 28, now() - interval '1 day', 'fuera_de_plazo');
    -- A13 fuera de plazo, fuente de CARTERA (cooperativa no inicial) y su identidad (p[13] → p[3]) ya tiene otra captación
    -- acreditada (A3): la regla de identidad va ANTES de decidir el estado, como en el escritor → conflicto, intacta
    -- (revisión Codex r1, P3; antes pasaba a operacion_cartera sin contar el conflicto).
    v_ep := pg_temp.lead_convertido(l[13], pg_temp.id('V'), p[13], now() - interval '3 days');
    perform pg_temp.cierre(ce[13], null, pg_temp.id('V'), p[13], f.m1 + 19, f.m1 + 19, false, 1000);
    a13 := pg_temp.acreditacion(l[13], v_ep, p[13], 'cierre_externo', ce[13], f.m1 + 19, now() - interval '3 days', 'fuera_de_plazo');

    select jsonb_object_agg(ca.id, to_jsonb(ca)) into v_antes from crm.conversion_acreditaciones ca;
    perform pg_temp.como(pg_temp.id('G'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 5, 'Reevaluar conversiones de prueba'));
    c := c || pg_temp.exigir((v_r ->> 'acreditaciones_reevaluadas')::int = 5 and (v_r ->> 'conflictos_identidad')::int = 3,
                             b, 'cinco reevaluadas (A1, A4, A5, A6, A11) y tres conflictos de identidad (A2, A12, A13)', v_r::text);
    c := c || pg_temp.exigir((select estado = 'acreditada' and plazo_hasta = v_nuevo from crm.conversion_acreditaciones where id = a1),
                             b, 'fuera de plazo con fuente elegible → acreditada con el plazo nuevo');
    c := c || pg_temp.exigir((select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a2) = v_antes -> a2::text,
                             b, 'conflicto de identidad (fusionada): se queda exactamente como estaba');
    c := c || pg_temp.exigir((select estado = 'fuente_demo' and plazo_hasta = v_nuevo from crm.conversion_acreditaciones where id = a4),
                             b, 'fuente demo → fuente_demo (exclusión del escritor), no acreditada');
    c := c || pg_temp.exigir((select estado = 'operacion_cartera' from crm.conversion_acreditaciones where id = a5),
                             b, 'operación de cartera → operacion_cartera, no acreditada');
    c := c || pg_temp.exigir((select estado = 'acreditada' from crm.conversion_acreditaciones where id = a6),
                             b, 'mes_sellado con el mes abierto → acreditada');
    c := c || pg_temp.exigir((select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a3) = v_antes -> a3::text
                             and (select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a7) = v_antes -> a7::text,
                             b, 'las ya acreditadas no se tocan');
    c := c || pg_temp.exigir((select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a8) = v_antes -> a8::text,
                             b, 'la que se acreditó después del plazo nuevo sigue fuera de plazo');
    c := c || pg_temp.exigir((select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a9) = v_antes -> a9::text,
                             b, 'fuente retirada: no se reevalúa');
    c := c || pg_temp.exigir((select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a10) = v_antes -> a10::text,
                             b, 'otro mes: no se toca');
    c := c || pg_temp.exigir((select estado from crm.conversion_acreditaciones where id = a11) = 'acreditada'
                             and (select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a12) = v_antes -> a12::text,
                             b, 'misma identidad dos veces: la primera en llegar se acredita, la segunda choca y se queda');
    c := c || pg_temp.exigir((select to_jsonb(ca) from crm.conversion_acreditaciones ca where ca.id = a13) = v_antes -> a13::text,
                             b, 'fuente de cartera con la identidad ya acreditada: conflicto, se queda como estaba (Codex P3)');
    -- Volver a fijar no duplica nada: solo quedan los conflictos (y siguen contándose).
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 5, 'Reevaluar otra vez'));
    c := c || pg_temp.exigir((v_r ->> 'acreditaciones_reevaluadas')::int = 0 and (v_r ->> 'conflictos_identidad')::int = 3,
                             b, 'reevaluar dos veces es idempotente', v_r::text);
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b6$;

-- ── B7 · Reapertura completa del mes anterior sellado ────────────────────────────────────────────────────────────────
do $b7$
declare
  c text[] := '{}'; b text := 'B7 reapertura'; f record; v_r jsonb; v_e text; v_ep uuid; v_sello jsonb; v_foto jsonb;
  v_acred jsonb; v_rastro jsonb; v_cierre jsonb; v_reap record; v_dec record; v_base timestamptz;
  r1 uuid; r2 uuid; r3 uuid;
  l uuid[] := array(select ('ca7e1507-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid from generate_series(1, 3) i);
  p uuid[] := array(select ('ca7e1507-0000-4000-8000-0000000001' || lpad(i::text, 2, '0'))::uuid from generate_series(1, 4) i);
  ce uuid[] := array(select ('ca7e1507-0000-4000-8000-0000000002' || lpad(i::text, 2, '0'))::uuid from generate_series(1, 4) i);
  v_inv uuid := 'ca7e1507-0000-4000-8000-000000000301';
  v_sello_en timestamptz;
begin
  select * into f from pg_temp.f;
  begin
    v_base := (f.m1::timestamp + interval '1 month 10 days') at time zone 'America/Lima';
    -- El mes anterior SELLADO como septiembre el 11/10: sello, foto, acreditaciones marcadas y una venta en cooperativa
    -- registrada tarde (imputada al mes en curso, con su rastro) de un analista con meta.
    perform pg_temp.sellar(f.m1, true);
    select pc.cerrado_en into v_sello_en from crm.periodos_cerrados pc where pc.periodo = f.m1;
    perform pg_temp.persona(p[1]); perform pg_temp.persona(p[2]); perform pg_temp.persona(p[3]); perform pg_temp.persona(p[4]);
    v_ep := pg_temp.lead_convertido(l[1], pg_temp.id('V'), p[1], f.m1::timestamp at time zone 'America/Lima' + interval '3 days');
    perform pg_temp.cierre(ce[1], l[1], pg_temp.id('V'), p[1], f.m1 + 3, f.m1 + 3, true, 3000);
    r1 := pg_temp.acreditacion(l[1], v_ep, p[1], 'cierre_externo', ce[1], f.m1 + 3, v_base - interval '25 days', 'acreditada', v_sello_en, true, 1);
    v_ep := pg_temp.lead_convertido(l[2], pg_temp.id('V'), p[2], f.m1::timestamp at time zone 'America/Lima' + interval '4 days');
    perform pg_temp.cierre(ce[2], l[2], pg_temp.id('V'), p[2], f.m1 + 4, f.m1 + 4, true, 4000);
    r2 := pg_temp.acreditacion(l[2], v_ep, p[2], 'cierre_externo', ce[2], f.m1 + 4, v_base - interval '24 days', 'acreditada', v_sello_en, false, 0);
    v_ep := pg_temp.lead_convertido(l[3], pg_temp.id('V'), p[3], now() - interval '1 day');
    perform pg_temp.cierre(ce[3], l[3], pg_temp.id('V'), p[3], f.m1 + 25, f.m1 + 25, true, 2500);
    r3 := pg_temp.acreditacion(l[3], v_ep, p[3], 'cierre_externo', ce[3], f.m1 + 25, now() - interval '1 day', 'mes_sellado');
    perform pg_temp.cierre(ce[4], null, pg_temp.id('V'), p[4], f.m1 + 14, f.hoy, false, 20000);
    perform pg_temp.inversion(v_inv, p[4], ce[4], null, f.m1 + 14);
    perform pg_temp.rastro(v_inv, f.m1, f.hoy);
    select to_jsonb(pc) into v_sello from crm.periodos_cerrados pc where pc.periodo = f.m1;
    select jsonb_agg(to_jsonb(x) order by x.vendedor_id) into v_foto from crm.cierre_mes_vendedor x where x.periodo = f.m1;
    select jsonb_agg(to_jsonb(x) order by x.id) into v_acred from crm.conversion_acreditaciones x where x.periodo_comercial = f.m1;
    select jsonb_agg(to_jsonb(x)) into v_rastro from crm.inversion_ajustes_mes_cerrado x where x.periodo_origen = f.m1;
    select jsonb_agg(to_jsonb(x) - 'documento' - 'documento_tipo' - 'nombre_completo') into v_cierre
      from crm.cierres_externos x where x.id = ce[4];

    perform pg_temp.como(pg_temp.id('G'));
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    c := c || pg_temp.exigir(v_r #>> '{meses,0,mes}' = to_char(f.m1, 'YYYY-MM') and v_r #>> '{meses,0,sellado}' = 'true'
                             and v_r #>> '{meses,0,reabrible}' = 'true' and jsonb_typeof(v_r #> '{meses,0,motivo_no_reabrible}') = 'null',
                             b, 'la lectura ofrece reabrir el mes anterior sellado', v_r::text);
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 5,
                                    'Reapertura de prueba del banco'));
    select * into v_reap from crm.reaperturas_mes where periodo = f.m1;
    select * into v_dec from crm.plazos_carga_mes where periodo = f.m1;
    c := c || pg_temp.exigir(v_r ->> 'reabierto' = 'true' and (v_r ->> 'reapertura_id')::uuid = v_reap.id
                             and (v_r ->> 'plazo_hasta')::timestamptz = (f.hoy + 6)::timestamp at time zone 'America/Lima',
                             b, 'la respuesta dice que se reabrió y con qué plazo', v_r::text);
    c := c || pg_temp.exigir(jsonb_array_length(v_r -> 'ventas_devueltas') = 1
                             and pg_temp.claves(v_r -> 'ventas_devueltas' -> 0) = 'cooperativa,fecha_comercial,imputada_antes_a,moneda,monto'
                             and v_r #>> '{ventas_devueltas,0,cooperativa}' = 'qorilazo'
                             and (v_r #>> '{ventas_devueltas,0,monto}')::numeric = 20000
                             and v_r #>> '{ventas_devueltas,0,moneda}' = 'PEN'
                             and (v_r #>> '{ventas_devueltas,0,fecha_comercial}')::date = f.m1 + 14
                             and (v_r #>> '{ventas_devueltas,0,imputada_antes_a}')::date = f.hoy,
                             b, 'la respuesta lista la venta devuelta con su forma exacta', v_r::text);
    c := c || pg_temp.exigir((v_r ->> 'acreditaciones_reevaluadas')::int = 1 and (v_r ->> 'conflictos_identidad')::int = 0,
                             b, 'tras reabrir, la decidida después del sello se reevalúa', v_r::text);
    -- Efecto (idéntico a 01-reabrir.sql).
    c := c || pg_temp.exigir(not exists (select 1 from crm.periodos_cerrados where periodo = f.m1)
                             and not exists (select 1 from crm.cierre_mes_vendedor where periodo = f.m1),
                             b, 'sello y foto retirados');
    c := c || pg_temp.exigir(not exists (select 1 from crm.inversion_ajustes_mes_cerrado where periodo_origen = f.m1)
                             and (select fecha_imputacion from crm.cierres_externos where id = ce[4]) = f.m1 + 14,
                             b, 'rastro tardío retirado y la venta vuelve a su mes comercial');
    c := c || pg_temp.exigir((select count(*) filter (where sellado_en is not null or incluida_en_sello is not null
                                                       or ajuste_anulacion_en_sello is not null)
                                from crm.conversion_acreditaciones where periodo_comercial = f.m1) = 0,
                             b, 'las acreditaciones del mes quedan sin marcas de sello');
    c := c || pg_temp.exigir((select estado from crm.conversion_acreditaciones where id = r3) = 'acreditada'
                             and (select estado from crm.conversion_acreditaciones where id = r1) = 'acreditada',
                             b, 'estados correctos tras reabrir y reevaluar');
    -- La reapertura queda registrada con su respaldo completo (estado ANTES).
    c := c || pg_temp.exigir(v_reap.motivo = 'Reapertura de prueba del banco' and v_reap.decidido_por = pg_temp.id('G')
                             and v_reap.transaccion = pg_current_xact_id() and v_reap.reabierto_en = now(),
                             b, 'reapertura: quién, por qué y en qué transacción (id e instante)', to_jsonb(v_reap)::text);
    c := c || pg_temp.exigir(v_reap.respaldo -> 'sello' = v_sello and v_reap.respaldo -> 'foto' = v_foto
                             and v_reap.respaldo -> 'acreditaciones' = v_acred and v_reap.respaldo -> 'rastros_tardios' = v_rastro
                             and v_reap.respaldo -> 'cierres_externos' = v_cierre,
                             b, 'respaldo: sello, foto, acreditaciones, rastros y cierres (sin datos del cliente) como estaban');
    c := c || pg_temp.exigir(strpos(v_reap.respaldo::text, '"documento"') = 0 and strpos(v_reap.respaldo::text, '"nombre_completo": "CLIENTE') = 0,
                             b, 'el respaldo no guarda documento ni nombre del cliente');
    c := c || pg_temp.exigir((v_reap.resumen ->> 'foto_retirada')::int = 1 and (v_reap.resumen ->> 'acreditaciones_respaldadas')::int = 3
                             and (v_reap.resumen ->> 'acreditaciones_liberadas')::int = 2
                             and (v_reap.resumen ->> 'acreditaciones_que_estaban_incluidas')::int = 1
                             and (v_reap.resumen ->> 'rastros_retirados')::int = 1
                             and (v_reap.resumen #>> '{ventas_devueltas,0,analista_id}')::uuid = pg_temp.id('V'),
                             b, 'resumen de la reapertura', v_reap.resumen::text);
    c := c || pg_temp.exigir(v_dec.reapertura_id = v_reap.id and v_dec.motivo = v_reap.motivo,
                             b, 'la decisión de plazo enlaza su reapertura');
    -- Auditoría: la copia NO duplica el respaldo (datos personales) en public.audit_log.
    c := c || pg_temp.exigir((select a.data_despues -> 'respaldo' -> 'rastros_tardios' from public.audit_log a
                               where a.tabla = 'crm.reaperturas_mes' and a.operacion = 'INSERT' and a.fila_id::uuid = v_reap.id
                                 and a.usuario_id = pg_temp.id('G')) = v_rastro
                             and exists (select 1 from public.audit_log a where a.tabla = 'crm.periodos_cerrados'
                                          and a.operacion = 'DELETE' and a.usuario_id = pg_temp.id('G'))
                             and (select count(*) from public.audit_log a where a.tabla = 'crm.cierre_mes_vendedor'
                                   and a.operacion = 'DELETE' and a.usuario_id = pg_temp.id('G')) = 1,
                             b, 'auditoría: la reapertura con su respaldo (también el rastro retirado); sello y foto con su autor');
    -- El aviso de cierre y la lectura ven el mes abierto con el plazo nuevo.
    v_r := pg_temp.resultado('select crm.cierre_mes_estado_fn()');
    c := c || pg_temp.exigir(v_r #>> '{pendiente,mes}' = to_char(f.m1, 'YYYY-MM') and (v_r #>> '{pendiente,cierra_el}')::date = f.hoy + 6
                             and v_r #>> '{ultimo_cerrado,mes}' = to_char(f.m2, 'YYYY-MM'),
                             b, 'el aviso de cierre ve el mes reabierto, con su nueva fecha de sello', v_r::text);
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    c := c || pg_temp.exigir(v_r #>> '{meses,0,sellado}' = 'false' and v_r #>> '{meses,0,ultima_reapertura,decidido_por}' = 'GERENCIA PRUEBA PLAZO'
                             and (v_r #>> '{meses,0,ultima_reapertura,reabierto_en}')::timestamptz = v_reap.reabierto_en
                             and pg_temp.claves(v_r #> '{meses,0,ultima_reapertura}') = 'decidido_por,reabierto_en',
                             b, 'la lectura muestra la última reapertura', v_r::text);
    -- El reloj no lo vuelve a sellar antes del plazo nuevo.
    perform pg_temp.como(null);
    v_r := pg_temp.resultado('select crm.ciclo_cierre_mes()');
    c := c || pg_temp.exigir((v_r ->> 'cerrados')::int = 0 and not exists (select 1 from crm.periodos_cerrados where periodo = f.m1),
                             b, 'con el plazo nuevo en el futuro, el ciclo no lo vuelve a sellar', v_r::text);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b7$;

-- ── B8 · Cada negativa de la reapertura: P0409 con su motivo, sin escribir nada ──────────────────────────────────────
-- Cada variación monta el mes anterior sellado (como B7), le añade UNA causa y comprueba el mensaje, que la lectura
-- dice lo mismo (una sola regla) y que no se escribió nada.
create function pg_temp.negativa(p_variacion text, p_periodo date, p_esperado text) returns text language plpgsql as $$
declare
  f record; v_e text; v_r jsonb; v_m jsonb; v_salida text;
  l uuid := 'ca7e1508-0000-4000-8000-000000000001'; p uuid := 'ca7e1508-0000-4000-8000-000000000101';
  ce uuid := 'ca7e1508-0000-4000-8000-000000000201'; inv uuid := 'ca7e1508-0000-4000-8000-000000000301';
  v_ep uuid; v_contrato uuid := 'ca7e1508-0000-4000-8000-000000000401';
begin
  select * into f from pg_temp.f;
  begin
    perform pg_temp.persona(p);
    if p_variacion = 'no es el último' then
      perform pg_temp.sellar(f.m1, true); perform pg_temp.sellar(f.m0, true);
    elsif p_variacion = 'no es el mes anterior' then
      null;  -- hace dos meses es el último sellado, pero no el anterior
    elsif p_variacion = 'sin foto' then
      perform pg_temp.sellar(f.m1, false);
    elsif p_variacion = 'deuda nacida' then
      perform pg_temp.sellar(f.m1, true);
      v_ep := pg_temp.lead_convertido(l, pg_temp.id('V'), p, f.m1::timestamp at time zone 'America/Lima' + interval '3 days');
      set local session_replication_role = replica;
      insert into crm.ajustes_mes_cerrado (vendedor_id, periodo_origen, lead_id, motivo, creado_por, numerador, pendiente_numerador)
      values (pg_temp.id('V'), f.m1, l, 'Anulación después del sello', pg_temp.id('G'), 1, 1);
      set local session_replication_role = origin;
    elsif p_variacion = 'deuda absorbida' then
      perform pg_temp.sellar(f.m1, true, 1);
    elsif p_variacion = 'rastro de contrato' then
      perform pg_temp.sellar(f.m1, true);
      set local session_replication_role = replica;
      insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, categoria, estado, creado_por, creado_en,
          modalidad, fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial)
      values (v_contrato, 'PLAZO-TARDIO-0001', pg_temp.id('CLI'), 10000, 'PEN', 'nuevo', 'activo', pg_temp.id('V'), now(),
              'mensual', f.m1 + 14, f.m1 + 379, gen_random_uuid(), f.m1 + 14);
      set local session_replication_role = origin;
      perform pg_temp.inversion(inv, p, null, v_contrato, f.m1 + 14);
      perform pg_temp.rastro(inv, f.m1, f.hoy);
    elsif p_variacion = 'rastro incoherente' then
      perform pg_temp.sellar(f.m1, true);
      perform pg_temp.cierre(ce, null, pg_temp.id('V'), p, f.m1 + 14, f.hoy, false, 20000);
      perform pg_temp.inversion(inv, p, ce, null, f.m1 + 14);
      perform pg_temp.rastro(inv, f.m1, f.hoy - 1);   -- el rastro no coincide con la imputación del cierre
    elsif p_variacion = 'rastro dentro del mes' then
      perform pg_temp.sellar(f.m1, true);
      perform pg_temp.cierre(ce, null, pg_temp.id('V'), p, f.m1 + 14, f.m1 + 20, false, 20000);
      perform pg_temp.inversion(inv, p, ce, null, f.m1 + 14);
      perform pg_temp.rastro(inv, f.m1, f.m1 + 20);   -- coherente con el cierre, pero imputada dentro del propio mes
    elsif p_variacion = 'rastro de otro mes' then
      perform pg_temp.sellar(f.m1, true);
      perform pg_temp.cierre(ce, null, pg_temp.id('V'), p, f.m2 + 14, f.hoy, false, 20000);
      perform pg_temp.inversion(inv, p, ce, null, f.m2 + 14);
      perform pg_temp.rastro(inv, f.m1, f.hoy);       -- el rastro dice el mes anterior; la venta es de hace dos meses
    elsif p_variacion = 'analista sin meta' then
      perform pg_temp.sellar(f.m1, true);
      perform pg_temp.cierre(ce, null, pg_temp.id('V2'), p, f.m1 + 14, f.hoy, false, 20000);
      perform pg_temp.inversion(inv, p, ce, null, f.m1 + 14);
      perform pg_temp.rastro(inv, f.m1, f.hoy);
    elsif p_variacion = 'cooperativa sin rastro' then
      perform pg_temp.sellar(f.m1, true);
      perform pg_temp.cierre(ce, null, pg_temp.id('V'), p, f.m1 + 14, f.hoy, false, 20000);
    else
      raise exception 'variación desconocida %', p_variacion;
    end if;

    perform pg_temp.como(pg_temp.id('G'));
    v_e := pg_temp.error_de(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', p_periodo, f.hoy + 5,
                                   'Intento de reabrir de la prueba'));
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    select m into v_m from jsonb_array_elements(v_r -> 'meses') m where m ->> 'mes' = to_char(p_periodo, 'YYYY-MM');
    perform pg_temp.como(null);
    if v_e not like p_esperado then
      raise exception 'PRUEBA FALLA [B8 negativas] %: se esperaba «%», salió «%»', p_variacion, p_esperado, v_e;
    end if;
    if v_m is not null and (v_m ->> 'reabrible' is distinct from 'false' or 'P0409 ' || (v_m ->> 'motivo_no_reabrible') <> v_e) then
      raise exception 'PRUEBA FALLA [B8 negativas] %: la lectura no dice lo mismo que la puerta (% / %)', p_variacion, v_m, v_e;
    end if;
    if exists (select 1 from crm.reaperturas_mes) or exists (select 1 from crm.plazos_carga_mes)
       or not exists (select 1 from crm.periodos_cerrados where periodo = p_periodo) then
      raise exception 'PRUEBA FALLA [B8 negativas] %: la negativa escribió algo o retiró el sello', p_variacion;
    end if;
    v_salida := p_variacion;
    raise exception using errcode = 'P9999', message = v_salida;
  exception when sqlstate 'P9999' then
    return sqlerrm;
  end;
end $$;

do $b8$
declare c text[] := '{}'; b text := 'B8 negativas'; f record; r record;
begin
  select * into f from pg_temp.f;
  for r in select * from (values
      ('no es el último', f.m1, 'P0409 Solo se reabre el último mes cerrado, y % ya está cerrado'),
      ('no es el mes anterior', f.m2, 'P0409 Solo se reabre el mes anterior al mes en curso (%)'),
      ('sin foto', f.m1, 'P0409 El cierre de % no tiene foto de analistas%'),
      ('deuda nacida', f.m1, 'P0409 Hay deudas nacidas de %'),
      ('deuda absorbida', f.m1, 'P0409 El cierre de % ya descontó deudas de meses anteriores%'),
      ('rastro de contrato', f.m1, 'P0409 Hay una venta de % registrada después del cierre que no es una venta en cooperativa%'),
      ('rastro incoherente', f.m1, 'P0409 Hay una venta de % registrada después del cierre que no es una venta en cooperativa%'),
      ('rastro dentro del mes', f.m1, 'P0409 Hay una venta de % registrada después del cierre que no es una venta en cooperativa%'),
      ('rastro de otro mes', f.m1, 'P0409 Hay una venta de % registrada después del cierre que no es una venta en cooperativa%'),
      ('analista sin meta', f.m1, 'P0409 El analista de una venta en cooperativa de % no tiene meta en ese mes%'),
      ('cooperativa sin rastro', f.m1, 'P0409 Hay ventas en cooperativa de % imputadas a otro mes sin rastro%')
    ) t(variacion, periodo, esperado)
  loop
    c := c || ('reapertura negada: ' || pg_temp.negativa(r.variacion, r.periodo, r.esperado));
  end loop;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b8$;

-- ── B9 · Candados: sin autorización rebotan; la autorización no se filtra a otro mes, a otra venta ni a otra transacción ─
-- Un UPDATE de un cierre externo pasa por DOS candados: trg_cierres_externos_00_inmutables (la válvula) y
-- trg_cierres_f4_inmutables (clase, fechas y comprobante). Sin la válvula de corrección, rebota en el primero (v_cierre);
-- con ella abierta (crm.op_privilegiada, la de crm.corregir_cierre_externo) se mide el segundo (v_f4).
do $b9$
declare
  c text[] := '{}'; b text := 'B9 candados'; f record; v_e text; v_r record;
  p uuid := 'ca7e1509-0000-4000-8000-000000000101'; ce1 uuid := 'ca7e1509-0000-4000-8000-000000000201';
  ce2 uuid := 'ca7e1509-0000-4000-8000-000000000202'; inv1 uuid := 'ca7e1509-0000-4000-8000-000000000301';
  inv2 uuid := 'ca7e1509-0000-4000-8000-000000000302'; p2 uuid := 'ca7e1509-0000-4000-8000-000000000102';
  ce3 uuid := 'ca7e1509-0000-4000-8000-000000000203'; p3 uuid := 'ca7e1509-0000-4000-8000-000000000103';
  v_respaldo jsonb; v_ok boolean; v_e2 text;
  v_sello text := 'P0409 Un mes cerrado no se edita ni se borra';
  v_historial text := 'P0409 El historial de una inversión no se modifica ni se elimina';
  v_cierre text := 'P0409 Un cierre externo solo se corrige via crm.corregir_cierre_externo';
  v_f4 text := 'P0409 La clase, las fechas y el comprobante del cierre conservan su registro original';
begin
  select * into f from pg_temp.f;
  begin
    -- El mes anterior sellado, con una venta tardía (ce1, con rastro) y otra del mismo mes que la reapertura NO respalda
    -- (ce3, sin rastro); y hace dos meses (sellado en la siembra) con otra venta tardía (ce2).
    perform pg_temp.sellar(f.m1, true);
    perform pg_temp.persona(p); perform pg_temp.persona(p2); perform pg_temp.persona(p3);
    perform pg_temp.cierre(ce1, null, pg_temp.id('V'), p, f.m1 + 14, f.hoy, false, 20000);
    perform pg_temp.inversion(inv1, p, ce1, null, f.m1 + 14);
    perform pg_temp.rastro(inv1, f.m1, f.hoy);
    perform pg_temp.cierre(ce2, null, pg_temp.id('V'), p2, f.m2 + 14, f.hoy, false, 15000);
    perform pg_temp.inversion(inv2, p2, ce2, null, f.m2 + 14);
    perform pg_temp.rastro(inv2, f.m2, f.hoy);
    perform pg_temp.cierre(ce3, null, pg_temp.id('V'), p3, f.m1 + 16, f.hoy, false, 8000);
    v_respaldo := jsonb_build_object('sello', '{}'::jsonb, 'foto', '[]'::jsonb, 'acreditaciones', '[]'::jsonb,
                                     'rastros_tardios', '[]'::jsonb, 'cierres_externos', jsonb_build_array(jsonb_build_object('id', ce1)));

    -- 1) Sin reapertura: todo rebota.
    c := c || pg_temp.exigir(private.reapertura_autoriza(f.m1) = false and private.reapertura_autoriza(f.m1, ce1) = false,
                             b, 'sin reapertura no hay autorización');
    v_e := pg_temp.error_de(format('delete from crm.cierre_mes_vendedor where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'sin autorización: borrar la foto rebota', v_e);
    v_e := pg_temp.error_de(format('delete from crm.periodos_cerrados where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'sin autorización: borrar el sello rebota', v_e);
    v_e := pg_temp.error_de(format('update crm.periodos_cerrados set automatico = automatico where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'sin autorización: editar el sello rebota', v_e);
    v_e := pg_temp.error_de(format('delete from crm.inversion_ajustes_mes_cerrado where inversion_id = %L', inv1));
    c := c || pg_temp.exigir(v_e = v_historial, b, 'sin autorización: borrar el rastro tardío rebota', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_cierre, b, 'sin autorización: devolver la venta a su mes rebota', v_e);
    perform set_config('crm.op_privilegiada', 'on', true);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce1));
    perform set_config('crm.op_privilegiada', 'off', true);
    c := c || pg_temp.exigir(v_e = v_f4, b, 'sin autorización y con la válvula de corrección: la imputación no se mueve', v_e);

    -- 2) Reaperturas que NO son de esta transacción (sembradas con el trigger de la llave apagado, que es la única forma
    --    de escribir otra llave): de otra transacción, y una vieja con el MISMO id de transacción (tras restaurar un
    --    volcado en otro cluster) pero otro instante. Ninguna autoriza.
    set local session_replication_role = replica;
    insert into crm.reaperturas_mes (periodo, motivo, decidido_por, transaccion, reabierto_en, respaldo, resumen)
    values (f.m1, 'Reapertura de otra transacción', pg_temp.id('G'), '1'::xid8, now() - interval '1 day', v_respaldo, '{}'::jsonb);
    set local session_replication_role = origin;
    c := c || pg_temp.exigir(private.reapertura_autoriza(f.m1) = false and private.reapertura_autoriza(f.m1, ce1) = false,
                             b, 'otra transacción: no autoriza');
    v_e := pg_temp.error_de(format('delete from crm.cierre_mes_vendedor where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'otra transacción: borrar la foto rebota', v_e);
    v_e := pg_temp.error_de(format('delete from crm.periodos_cerrados where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'otra transacción: borrar el sello rebota', v_e);
    v_e := pg_temp.error_de(format('delete from crm.inversion_ajustes_mes_cerrado where inversion_id = %L', inv1));
    c := c || pg_temp.exigir(v_e = v_historial, b, 'otra transacción: borrar el rastro rebota', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_cierre, b, 'otra transacción: devolver la venta rebota', v_e);
    perform set_config('crm.op_privilegiada', 'on', true);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce1));
    perform set_config('crm.op_privilegiada', 'off', true);
    c := c || pg_temp.exigir(v_e = v_f4, b, 'otra transacción y con la válvula de corrección: la imputación no se mueve', v_e);
    set local session_replication_role = replica;
    insert into crm.reaperturas_mes (periodo, motivo, decidido_por, transaccion, reabierto_en, respaldo, resumen)
    values (f.m1, 'Reapertura vieja con el mismo id de transacción', pg_temp.id('G'), pg_current_xact_id(),
            now() - interval '1 day', v_respaldo, '{}'::jsonb);
    set local session_replication_role = origin;
    c := c || pg_temp.exigir(private.reapertura_autoriza(f.m1) = false and private.reapertura_autoriza(f.m1, ce1) = false,
                             b, 'mismo id de transacción pero otro instante: no autoriza');
    v_e := pg_temp.error_de(format('delete from crm.periodos_cerrados where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'mismo id de transacción pero otro instante: borrar el sello rebota', v_e);
    -- Revisión Codex r1 (P3): con esa reapertura vieja del MISMO id de transacción todavía ahí (volcado restaurado en otro
    -- cluster), la de ESTA transacción se puede registrar: la llave única es la pareja (transaccion, reabierto_en). Y si
    -- la subtransacción que la registró se deshace, la fila desaparece y deja de autorizar.
    v_ok := null; v_e2 := null;
    begin
      insert into crm.reaperturas_mes (periodo, motivo, decidido_por, respaldo, resumen)
      values (f.m1, 'Reapertura en una subtransacción que se deshace', pg_temp.id('G'), v_respaldo, '{}'::jsonb);
      v_ok := private.reapertura_autoriza(f.m1) and private.reapertura_autoriza(f.m1, ce1);
      raise exception using errcode = 'P9998', message = 'deshacer la subtransacción';
    exception
      when sqlstate 'P9998' then null;
      when others then v_e2 := sqlstate || ' ' || sqlerrm;
    end;
    c := c || pg_temp.exigir(v_e2 is null, b,
                             'una reapertura vieja con el mismo id de transacción no impide registrar la de esta transacción (Codex P3)', v_e2);
    c := c || pg_temp.exigir(v_ok is true, b, 'dentro de la subtransacción que la registró, la reapertura autoriza');
    c := c || pg_temp.exigir(private.reapertura_autoriza(f.m1) = false and private.reapertura_autoriza(f.m1, ce1) = false
                             and not exists (select 1 from crm.reaperturas_mes where motivo = 'Reapertura en una subtransacción que se deshace'),
                             b, 'deshecha la subtransacción que la registró, la reapertura desaparece y deja de autorizar (Codex P3)');
    set local session_replication_role = replica;
    delete from crm.reaperturas_mes where transaccion = pg_current_xact_id();   -- deja sitio a la de esta transacción
    -- Y otra transacción que empezó en el MISMO instante (otro id): tampoco.
    insert into crm.reaperturas_mes (periodo, motivo, decidido_por, transaccion, reabierto_en, respaldo, resumen)
    values (f.m1, 'Reapertura de otra transacción del mismo instante', pg_temp.id('G'), '2'::xid8, now(), v_respaldo, '{}'::jsonb);
    set local session_replication_role = origin;
    c := c || pg_temp.exigir(private.reapertura_autoriza(f.m1) = false and private.reapertura_autoriza(f.m1, ce1) = false,
                             b, 'otra transacción del mismo instante: no autoriza');
    v_e := pg_temp.error_de(format('delete from crm.periodos_cerrados where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'otra transacción del mismo instante: borrar el sello rebota', v_e);

    -- 3) Reapertura del mes anterior en ESTA transacción. La llave la fija el trigger: aunque se pida otra, queda la de
    --    esta transacción y su instante.
    insert into crm.reaperturas_mes (periodo, motivo, decidido_por, transaccion, reabierto_en, respaldo, resumen)
    values (f.m1, 'Reapertura de esta transacción', pg_temp.id('G'), '5'::xid8, timestamptz '2000-01-01', v_respaldo, '{}'::jsonb);
    select r.transaccion, r.reabierto_en into v_r from crm.reaperturas_mes r where r.motivo = 'Reapertura de esta transacción';
    c := c || pg_temp.exigir(v_r.transaccion = pg_current_xact_id() and v_r.reabierto_en = now(),
                             b, 'la llave no la elige quien inserta: es esta transacción y su instante', to_jsonb(v_r)::text);
    c := c || pg_temp.exigir(private.reapertura_autoriza(f.m1) = true and private.reapertura_autoriza(f.m2) = false
                             and private.reapertura_autoriza(f.m1, ce1) = true and private.reapertura_autoriza(f.m1, ce3) = false,
                             b, 'esta transacción: autoriza su mes y su venta respaldada, nada más');
    -- Alcance documentado (revisión Codex r1, P3): la transacción SUPERIOR entera, también dentro de sus subtransacciones.
    v_ok := null;
    begin
      v_ok := private.reapertura_autoriza(f.m1) and private.reapertura_autoriza(f.m1, ce1);
      raise exception using errcode = 'P9998', message = 'deshacer la subtransacción';
    exception when sqlstate 'P9998' then null;
    end;
    c := c || pg_temp.exigir(v_ok is true, b, 'la autorización alcanza las subtransacciones de su transacción superior (Codex P3)');
    -- Otro mes: todo sigue rebotando.
    v_e := pg_temp.error_de(format('delete from crm.periodos_cerrados where periodo = %L', f.m2));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'otro mes: borrar su sello rebota', v_e);
    v_e := pg_temp.error_de(format('delete from crm.cierre_mes_vendedor where periodo = %L', f.m2));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'otro mes: borrar su foto rebota', v_e);
    v_e := pg_temp.error_de(format('delete from crm.inversion_ajustes_mes_cerrado where inversion_id = %L', inv2));
    c := c || pg_temp.exigir(v_e = v_historial, b, 'otro mes: borrar su rastro rebota', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce2));
    c := c || pg_temp.exigir(v_e = v_cierre, b, 'otro mes: devolver su venta rebota', v_e);
    perform set_config('crm.op_privilegiada', 'on', true);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce2));
    perform set_config('crm.op_privilegiada', 'off', true);
    c := c || pg_temp.exigir(v_e = v_f4, b, 'otro mes y con la válvula de corrección: la imputación no se mueve', v_e);
    -- Su mes, pero lo que la reapertura no hace: editar sello/rastro, borrar el cierre.
    v_e := pg_temp.error_de(format('update crm.periodos_cerrados set automatico = automatico where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = v_sello, b, 'su mes: EDITAR el sello sigue prohibido (solo se retira)', v_e);
    v_e := pg_temp.error_de(format('update crm.inversion_ajustes_mes_cerrado set fecha_imputacion = fecha_imputacion where inversion_id = %L', inv1));
    c := c || pg_temp.exigir(v_e = v_historial, b, 'su mes: EDITAR el rastro sigue prohibido', v_e);
    v_e := pg_temp.error_de(format('delete from crm.cierres_externos where id = %L', ce1));
    c := c || pg_temp.exigir(v_e like 'P0409 Un cierre externo no se elimina%', b, 'su mes: BORRAR el cierre sigue prohibido', v_e);
    -- Su mes, la válvula de la reapertura: solo la imputación, solo a la fecha comercial, nada más de la fila, y solo de una
    -- venta respaldada (revisión auditor-rls, P2).
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial, monto = monto + 1 where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_cierre, b, 'su mes: cambiar el monto a la vez rebota', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial, nota = ''otra nota'' where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_cierre, b, 'su mes: cambiar la nota a la vez rebota', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = %L where id = %L', f.m1 + 20, ce1));
    c := c || pg_temp.exigir(v_e = v_cierre, b, 'su mes: llevar la imputación a otra fecha rebota', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce3));
    c := c || pg_temp.exigir(v_e = v_cierre, b, 'su mes: una venta que la reapertura no respaldó no se mueve', v_e);
    -- Con la válvula de corrección abierta, el candado de la imputación decide solo (mismas cuatro reglas).
    perform set_config('crm.op_privilegiada', 'on', true);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = %L where id = %L', f.m1 + 20, ce1));
    c := c || pg_temp.exigir(v_e = v_f4, b, 'candado de la imputación: solo a la fecha comercial', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial, comprobante_objeto_id = gen_random_uuid() where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_f4, b, 'candado de la imputación: no cambia el comprobante a la vez', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial, es_cierre_inicial = true where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_f4, b, 'candado de la imputación: no cambia la clase a la vez', v_e);
    -- (en un UPDATE, «fecha_imputacion = fecha_comercial» toma la fecha comercial ANTERIOR)
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_comercial = %L, fecha_imputacion = fecha_comercial where id = %L', f.m1 + 15, ce1));
    c := c || pg_temp.exigir(v_e = v_f4, b, 'candado de la imputación: no cambia la fecha comercial', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce3));
    c := c || pg_temp.exigir(v_e = v_f4, b, 'candado de la imputación: solo una venta respaldada', v_e);
    -- Revisión Codex r1 (P2): con la válvula abierta, la rama de la reapertura tampoco deja cambiar otra columna a la vez.
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial, monto = monto + 1 where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_f4, b, 'con la válvula de corrección: devolver la venta y cambiar el monto a la vez rebota (Codex P2)', v_e);
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial, nota = ''otra nota'' where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = v_f4, b, 'con la válvula de corrección: devolver la venta y cambiar la nota a la vez rebota (Codex P2)', v_e);
    -- … y solo la imputación sí pasa (en una subtransacción que se deshace: el flujo de abajo la devuelve sin la válvula).
    v_e2 := null; v_ok := null;
    begin
      update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = ce1;
      v_ok := (select fecha_imputacion from crm.cierres_externos where id = ce1) = f.m1 + 14;
      raise exception using errcode = 'P9998', message = 'deshacer la subtransacción';
    exception
      when sqlstate 'P9998' then null;
      when others then v_e2 := sqlstate || ' ' || sqlerrm;
    end;
    c := c || pg_temp.exigir(v_e2 is null and v_ok is true, b,
                             'con la válvula de corrección: devolver SOLO la imputación de la venta respaldada pasa', v_e2);
    perform set_config('crm.op_privilegiada', 'off', true);
    -- Y lo que sí autoriza, solo en su mes: devolver la venta respaldada, retirar rastro, foto y sello.
    v_e := pg_temp.error_de(format('update crm.cierres_externos set fecha_imputacion = fecha_comercial where id = %L', ce1));
    c := c || pg_temp.exigir(v_e = 'SIN ERROR' and (select fecha_imputacion from crm.cierres_externos where id = ce1) = f.m1 + 14,
                             b, 'su mes: devolver la venta respaldada a su fecha comercial pasa', v_e);
    v_e := pg_temp.error_de(format('delete from crm.inversion_ajustes_mes_cerrado where inversion_id = %L', inv1));
    c := c || pg_temp.exigir(v_e = 'SIN ERROR', b, 'su mes: retirar el rastro pasa', v_e);
    v_e := pg_temp.error_de(format('delete from crm.cierre_mes_vendedor where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = 'SIN ERROR', b, 'su mes: retirar la foto pasa', v_e);
    v_e := pg_temp.error_de(format('delete from crm.periodos_cerrados where periodo = %L', f.m1));
    c := c || pg_temp.exigir(v_e = 'SIN ERROR', b, 'su mes: retirar el sello pasa', v_e);
    c := c || pg_temp.exigir(exists (select 1 from crm.periodos_cerrados where periodo = f.m2)
                             and exists (select 1 from crm.inversion_ajustes_mes_cerrado where inversion_id = inv2)
                             and (select fecha_imputacion from crm.cierres_externos where id = ce2) = f.hoy
                             and (select fecha_imputacion from crm.cierres_externos where id = ce3) = f.hoy,
                             b, 'el otro mes y la venta no respaldada siguen intactos');
    -- El mismo candado vigila los eventos de inversión: las ramas nuevas (anidadas por tabla) no los alcanzan, ni
    -- siquiera dentro de la transacción de la reapertura.
    set local session_replication_role = replica;
    insert into crm.inversion_eventos (inversion_id, tipo, motivo, creado_por) values (inv1, 'registro', 'Evento sintético', pg_temp.id('G'));
    set local session_replication_role = origin;
    v_e := pg_temp.error_de(format('update crm.inversion_eventos set motivo = ''otro'' where inversion_id = %L', inv1));
    c := c || pg_temp.exigir(v_e = v_historial, b, 'eventos de inversión: editar sigue prohibido', v_e);
    v_e := pg_temp.error_de(format('delete from crm.inversion_eventos where inversion_id = %L', inv1));
    c := c || pg_temp.exigir(v_e = v_historial, b, 'eventos de inversión: borrar sigue prohibido', v_e);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b9$;

-- ── B10 · Historia inmutable y permisos ──────────────────────────────────────────────────────────────────────────────
do $b10$
declare c text[] := '{}'; b text := 'B10 historia y permisos'; f record; v_e text; v_r jsonb;
begin
  select * into f from pg_temp.f;
  begin
    perform pg_temp.como(pg_temp.id('G'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 5, 'Decisión que no se borra'));
    perform pg_temp.como(null);
    insert into crm.reaperturas_mes (periodo, motivo, decidido_por, respaldo, resumen)
    values (f.m1, 'Reapertura que no se borra', pg_temp.id('G'),
            '{"sello":{},"foto":[],"acreditaciones":[],"rastros_tardios":[],"cierres_externos":[]}'::jsonb, '{}'::jsonb);
    foreach v_e in array array[
        'update crm.plazos_carga_mes set motivo = ''otro motivo'' ', 'delete from crm.plazos_carga_mes',
        'truncate crm.plazos_carga_mes cascade', 'update crm.reaperturas_mes set motivo = ''otro motivo'' ',
        'delete from crm.reaperturas_mes', 'truncate crm.reaperturas_mes cascade'] loop
      c := c || pg_temp.exigir(pg_temp.error_de(v_e) like 'P0409 Las decisiones de plazo de carga y las reaperturas de mes no se editan ni se borran%',
                               b, 'historia inmutable: ' || v_e, pg_temp.error_de(v_e));
    end loop;
    -- Las tablas no tienen grants ni políticas: los tres roles de la API rebotan (error normal de tabla).
    foreach v_e in array array['anon', 'authenticated', 'service_role'] loop
      c := c || pg_temp.exigir(not has_table_privilege(v_e, 'crm.plazos_carga_mes', 'select,insert,update,delete')
                               and not has_table_privilege(v_e, 'crm.reaperturas_mes', 'select,insert,update,delete'),
                               b, 'sin privilegios de tabla: ' || v_e);
    end loop;
    execute 'set local role authenticated';
    v_e := pg_temp.error_de('select 1 from crm.plazos_carga_mes');
    execute 'reset role';
    c := c || pg_temp.exigir(v_e like '42501 permission denied for table plazos_carga_mes%', b, 'authenticated no lee las decisiones', v_e);
    -- Funciones: núcleo solo postgres (sin la entrada de PUBLIC); puertas solo authenticated.
    c := c || pg_temp.exigir(not exists (
        select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid in ('private.conversion_plazo_base(date)'::regprocedure, 'private.reapertura_autoriza(date,uuid)'::regprocedure,
                         'private.reapertura_impedimento(date)'::regprocedure, 'private.conversion_reevaluar_plazo(date)'::regprocedure,
                         'private.reabrir_mes(date,text,uuid)'::regprocedure, 'private.conversion_plazo_hasta(date)'::regprocedure,
                         'private.fijar_plazo_carga(date,date,text,uuid)'::regprocedure,
                         'private.plazos_carga_mes_lectura()'::regprocedure, 'private.trg_reaperturas_mes_llave()'::regprocedure)
           and a.grantee <> 'postgres'::regrole), b, 'el núcleo solo lo ejecuta postgres (ni PUBLIC)');
    c := c || pg_temp.exigir((select array_agg(a.grantee::regrole::text order by a.grantee::regrole::text)
                                from pg_proc p cross join lateral aclexplode(p.proacl) a
                               where p.oid = 'crm.fijar_plazo_carga_mes(date,date,text)'::regprocedure) = array['authenticated', 'postgres']
                             and (select array_agg(a.grantee::regrole::text order by a.grantee::regrole::text)
                                from pg_proc p cross join lateral aclexplode(p.proacl) a
                               where p.oid = 'crm.plazos_carga_mes_fn()'::regprocedure) = array['authenticated', 'postgres'],
                             b, 'las puertas: authenticated y postgres, nadie más (ni anon ni service_role ni PUBLIC)');
    c := c || pg_temp.exigir((select pg_get_constraintdef(c2.oid) from pg_constraint c2
                               where c2.conrelid = 'crm.reaperturas_mes'::regclass and c2.conname = 'reaperturas_mes_transaccion_key')
                             = 'UNIQUE (transaccion, reabierto_en)'
                             and not exists (select 1 from pg_constraint c2 where c2.conrelid = 'crm.reaperturas_mes'::regclass
                                              and c2.contype = 'u' and pg_get_constraintdef(c2.oid) = 'UNIQUE (transaccion)'),
                             b, 'la llave única de la reapertura es la pareja (transaccion, reabierto_en) (Codex P3)');
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b10$;

-- ── B11 · Revisión Codex r1/r2: solo un mes con metas admite plazo y reapertura; nombres en blanco ──────────────────
-- Codex r2 (P2): el ciclo solo sella meses con metas (private.cierre_mes_pendiente). Un mes SIN metas con plazo quedaría
-- saltado al sellarse el siguiente y luego sin sello ni decisión modificable: por eso no admite plazo (22023) ni se
-- reabre (la lectura lo dice con el motivo de private.reapertura_impedimento). Y un nombre en blanco nunca sale vacío.
do $b11$
declare
  c text[] := '{}'; b text := 'B11 metas y nombres'; f record; v_r jsonb; m jsonb; v_m4 date; v_e text;
  v_base0 timestamptz; v_sin_metas_m0 text; v_sin_metas_m1 text; v_reab_m1 text;
begin
  select * into f from pg_temp.f;
  begin
    v_m4 := (f.m3 - interval '1 month')::date;
    v_base0 := (f.m0::timestamp + interval '1 month 10 days') at time zone 'America/Lima';
    v_sin_metas_m0 := private.etiqueta_mes_es(f.m0) || ' ' || to_char(f.m0, 'YYYY')
                      || ' no tiene metas publicadas: no tiene cierre ni plazo de carga';
    v_sin_metas_m1 := private.etiqueta_mes_es(f.m1) || ' ' || to_char(f.m1, 'YYYY')
                      || ' no tiene metas publicadas: no tiene cierre ni plazo de carga';
    v_reab_m1 := private.etiqueta_mes_es(f.m1) || ' ' || to_char(f.m1, 'YYYY')
                 || ' no tiene metas publicadas: el ciclo no lo volvería a cerrar';
    -- 1) El mes en curso SIN metas (la siembra no las publica): fijar su plazo → 22023, sin escribir; la lectura sigue bien.
    perform pg_temp.como(pg_temp.id('G'));
    v_e := pg_temp.error_de(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m0,
                                   (v_base0 at time zone 'America/Lima')::date - 1, 'Mes sin metas con plazo'));
    c := c || pg_temp.exigir(v_e = '22023 ' || v_sin_metas_m0, b, 'un mes sin metas no admite plazo (22023, Codex r2)', v_e);
    c := c || pg_temp.exigir(not exists (select 1 from crm.plazos_carga_mes) and not exists (select 1 from crm.reaperturas_mes),
                             b, 'la negativa por falta de metas no escribe');
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    select x into m from jsonb_array_elements(v_r -> 'meses') x where x ->> 'mes' = to_char(f.m0, 'YYYY-MM');
    c := c || pg_temp.exigir(m is not null and jsonb_typeof(m -> 'decision') = 'null' and m ->> 'ampliado' = 'false',
                             b, 'la lectura sigue respondiendo y muestra el mes en curso sin decisión', v_r::text);
    -- 2) Decide una Gerencia con el nombre en blanco (el front exige texto no vacío).
    set local session_replication_role = replica;
    update public.perfiles set nombre_completo = '   ' where id = pg_temp.id('G2');
    set local session_replication_role = origin;
    perform pg_temp.como(pg_temp.id('G2'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 4,
                                    'Decide una Gerencia sin nombre'));
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    select x into m from jsonb_array_elements(v_r -> 'meses') x where x ->> 'mes' = to_char(f.m1, 'YYYY-MM');
    c := c || pg_temp.exigir(m #>> '{decision,decidido_por}' = '(sin nombre · ' || left(pg_temp.id('G2')::text, 8) || ')',
                             b, 'un nombre en blanco sale como «(sin nombre · …)», nunca vacío', coalesce(m::text, 'null'));
    -- 3) El mes anterior SELLADO y SIN metas (retiradas con los disparadores apagados, solo para sembrar): la puerta no lo
    --    reabre (22023 de la regla de metas, antes de mirar el sello), el núcleo de la reapertura tampoco (P0409 con el
    --    motivo) y la lectura dice lo mismo que el núcleo: reabrible = false con ese motivo. Nada se escribe.
    set local session_replication_role = replica;
    delete from crm.metas_vendedor_detalle d using crm.metas_vendedor mv, crm.meta_periodos mp
     where d.meta_vendedor_id = mv.id and mv.meta_periodo_id = mp.id and mp.periodo = f.m1;
    delete from crm.metas_vendedor mv using crm.meta_periodos mp where mv.meta_periodo_id = mp.id and mp.periodo = f.m1;
    delete from crm.meta_periodos where periodo = f.m1;
    set local session_replication_role = origin;
    perform pg_temp.sellar(f.m1, true);
    perform pg_temp.como(pg_temp.id('G'));
    v_e := pg_temp.error_de(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m1, f.hoy + 5,
                                   'Reabrir un mes sin metas'));
    c := c || pg_temp.exigir(v_e = '22023 ' || v_sin_metas_m1, b, 'la puerta no reabre un mes sellado sin metas (22023)', v_e);
    v_e := pg_temp.error_de(format('select private.reabrir_mes(%L::date, %L, %L::uuid)', f.m1, 'Reabrir un mes sin metas',
                                   pg_temp.id('G')));
    c := c || pg_temp.exigir(v_e = 'P0409 ' || v_reab_m1, b, 'el núcleo de la reapertura tampoco (P0409 con el motivo, Codex r2)', v_e);
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    select x into m from jsonb_array_elements(v_r -> 'meses') x where x ->> 'mes' = to_char(f.m1, 'YYYY-MM');
    c := c || pg_temp.exigir(m ->> 'sellado' = 'true' and m ->> 'reabrible' = 'false' and m ->> 'motivo_no_reabrible' = v_reab_m1,
                             b, 'la lectura: sellado, no reabrible, con el motivo de la falta de metas', coalesce(m::text, 'null'));
    c := c || pg_temp.exigir(not exists (select 1 from crm.reaperturas_mes)
                             and (select count(*) from crm.plazos_carga_mes) = 1
                             and exists (select 1 from crm.periodos_cerrados where periodo = f.m1)
                             and exists (select 1 from crm.cierre_mes_vendedor where periodo = f.m1),
                             b, 'las negativas no reabren ni escriben (queda solo la decisión del paso 2)');
    -- 4) Un mes por DETRÁS del último sellado no aparece aunque tenga una decisión (ya no admite otra).
    set local session_replication_role = replica;
    insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por)
    values (v_m4, f.hoy + 4, (f.hoy + 5)::timestamp at time zone 'America/Lima', 'Decisión de un mes ya superado', pg_temp.id('G'));
    set local session_replication_role = origin;
    v_r := pg_temp.resultado('select crm.plazos_carga_mes_fn()');
    c := c || pg_temp.exigir(not exists (select 1 from jsonb_array_elements(v_r -> 'meses') x where x ->> 'mes' = to_char(v_m4, 'YYYY-MM')),
                             b, 'un mes por detrás del último sellado no aparece aunque tenga decisión', v_r::text);
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b11$;

-- ── B12 · Revisión Codex r2: con un mes ampliado, los meses siguientes esperan ─────────────────────────────────────
-- Hace tres meses (M, con metas) ampliado a una fecha futura; hace dos meses (M+1, con metas) con su ventana abierta hace
-- un mes. El ciclo sale en M (todavía en plazo) y no sella M+1; Gerencia tampoco puede sellar M+1 a mano («Falta cerrar»).
-- Para montarlo se retira (con los disparadores apagados, solo para sembrar) el sello de hace dos meses, se publican
-- metas de hace tres y se sella el de hace cuatro.
do $b12$
declare c text[] := '{}'; b text := 'B12 los meses siguientes esperan'; f record; v_r jsonb; v_e text; v_m4 date;
begin
  select * into f from pg_temp.f;
  begin
    v_m4 := (f.m3 - interval '1 month')::date;
    set local session_replication_role = replica;
    delete from crm.cierre_mes_vendedor where periodo = f.m2;
    delete from crm.periodos_cerrados where periodo = f.m2;
    insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por)
    values (gen_random_uuid(), f.m3, 1, now(), pg_temp.id('G'));
    set local session_replication_role = origin;
    perform pg_temp.sellar(v_m4, true);
    perform pg_temp.como(pg_temp.id('G'));
    v_r := pg_temp.resultado(format('select crm.fijar_plazo_carga_mes(%L::date, %L::date, %L)', f.m3, f.hoy + 5,
                                    'Ampliar un mes viejo de prueba'));
    c := c || pg_temp.exigir(v_r ->> 'ok' = 'true'
                             and private.cierre_mes_ventana_desde(f.m3) = (f.hoy + 6)::timestamp at time zone 'America/Lima'
                             and private.cierre_mes_ventana_desde(f.m2) <= now(),
                             b, 'M ampliado al futuro y M+1 con su ventana ya abierta', v_r::text);
    perform pg_temp.como(null);
    v_r := pg_temp.resultado('select crm.ciclo_cierre_mes()');
    c := c || pg_temp.exigir((v_r ->> 'ok')::boolean and (v_r ->> 'cerrados')::int = 0
                             and not exists (select 1 from crm.periodos_cerrados where periodo in (f.m3, f.m2, f.m1)),
                             b, 'el ciclo sale en M (todavía en plazo) y no sella M+1 ni los siguientes', v_r::text);
    perform pg_temp.como(pg_temp.id('G'));
    v_e := pg_temp.error_de(format('select crm.cerrar_periodo(%L::date)', f.m2));
    c := c || pg_temp.exigir(v_e like '22023 Falta cerrar ' || f.m3::text || ' antes que ' || f.m2::text || '%',
                             b, 'Gerencia tampoco sella M+1 a mano: «Falta cerrar» M', v_e);
    v_e := pg_temp.error_de(format('select crm.cerrar_periodo(%L::date)', f.m3));
    c := c || pg_temp.exigir(v_e like '22023 El mes ' || to_char(f.m3, 'YYYY-MM') || ' no se puede cerrar antes del %',
                             b, 'ni sella M antes de su plazo ampliado', v_e);
    perform pg_temp.como(null);
    raise exception using errcode = 'P9999', message = 'DESHACER';
  exception when sqlstate 'P9999' then null;
  end;
  insert into pg_temp.casos (bloque, caso) select b, unnest(c);
end
$b12$;

-- ── Veredicto ────────────────────────────────────────────────────────────────────────────────────────────────────────
select bloque, count(*) as casos from pg_temp.casos group by bloque order by min(n);
select 'PRUEBA PLAZO CARGA OK: ' || count(*) || ' casos' as veredicto from pg_temp.casos;
rollback;
