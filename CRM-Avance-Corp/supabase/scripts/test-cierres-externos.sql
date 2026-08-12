-- ============================================================================
-- Oráculo transaccional de los CIERRES EXTERNOS (COOPAC Qorilazo / Prodelco)
-- Migración: 20260812000259_crm_cierres_externos.sql
-- ============================================================================
-- Cómo se corre (sobre el branch de Supabase, DESPUÉS de aplicar la migración
-- y de `npm run seed:demo` — el seed va ANTES que las migraciones en el ciclo
-- del branch; este oráculo va después de todo):
--
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/scripts/test-cierres-externos.sql
--
-- ⚠️ LA CONEXIÓN TIENE QUE SER EL DUEÑO de `crm.equipo`, `crm.leads`,
-- `crm.lead_asignaciones` y `crm.cierres_externos` (en este proyecto,
-- `postgres`). El fichero duerme triggers con `alter table ... disable trigger
-- user` en DOS sitios (equipo para la jerarquía; lead_asignaciones para
-- retro-fechar el episodio de sacrificio que da cobertura histórica al ledger
-- — sin él, `conversion_mensual_fn` marca el mes como no medible y el oráculo
-- probaría un payload que producción no emite). NO se usa
-- `session_replication_role` (el postgres de Supabase no puede ponerlo).
--
-- Éxito = una sola fila con el token CIERRES_EXTERNOS_OK. Cualquier aserción
-- fallida lanza `raise exception` con su código CEXT-xx, el valor ESPERADO y
-- el OBTENIDO. Todo revierte: el fichero termina en `rollback`.
--
-- QUÉ PRUEBA (y qué no puede probar el postflight de la migración):
--   · el postflight corre SIN sesión: jamás ejercita la RPC con un rol real.
--     Aquí cada gate se prueba con identidad verdadera (request.jwt.claim.sub)
--     y rol `authenticated`, que es como llega la Data API.
--   · la ARITMÉTICA completa: el cierre externo cuenta en la conversión del
--     mes (no referido ×1, referido ×0,150) y suma a la cuota
--     (cumplimiento_metas_fn) SIN tocar la fórmula de ninguna de las dos.
--   · el ledger se escribe por su CAMINO REAL: ni una fila de
--     `crm.lead_asignaciones` se inserta a mano; los episodios nacen del alta
--     y mueren por el AFTER trigger cuando la RPC convierte.
-- ============================================================================

begin;

set local search_path = public;

-- ---------------------------------------------------------------------------
-- 0. Helpers pg_temp
-- ---------------------------------------------------------------------------
create table pg_temp.cext_casos (codigo text primary key);
-- La fase RPC corre con `set local role authenticated`, y las funciones
-- pg_temp que registran casos escriben en esta tabla temporal: sin el grant,
-- el primer cext_caso() bajo ese rol muere con permission denied.
grant select, insert on pg_temp.cext_casos to authenticated;

create function pg_temp.cext_caso(p_codigo text) returns void
  language plpgsql volatile as
$$
begin
  insert into pg_temp.cext_casos (codigo) values (p_codigo)
  on conflict (codigo) do nothing;
end;
$$;

create function pg_temp.cext_casos_esperados() returns text[]
  language sql immutable as
$$ select array[
  'CEXT-00a', 'CEXT-00b', 'CEXT-00c',
  'CEXT-01', 'CEXT-02', 'CEXT-03', 'CEXT-04', 'CEXT-05', 'CEXT-06',
  'CEXT-07', 'CEXT-08', 'CEXT-09', 'CEXT-10', 'CEXT-11', 'CEXT-12',
  'CEXT-13', 'CEXT-14', 'CEXT-15', 'CEXT-16', 'CEXT-17', 'CEXT-18', 'CEXT-99'
]::text[] $$;

create function pg_temp.cext_uid(p_n integer) returns uuid
  language sql immutable as
$$ select ('41000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;

create function pg_temp.cext_tel(p_n integer) returns text
  language sql immutable as
$$ select '9' || lpad((41000000 + p_n)::text, 8, '0') $$;

create function pg_temp.cext_mes() returns date
  language sql stable as
$$ select date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date $$;

-- Día 16 de hace DOS meses, 00:00 Lima: el instante al que se retro-fecha el
-- episodio de SACRIFICIO para que el suelo del ledger sea anterior al mes y el
-- payload salga `medible` (Lima es UTC-5 fijo, sin ambigüedad).
create function pg_temp.cext_instante_suelo() returns timestamptz
  language sql stable as
$$ select (date_trunc('month', pg_catalog.now() at time zone 'America/Lima')
           - interval '2 months' + interval '15 days') at time zone 'America/Lima' $$;

-- Identidades: el sub del JWT simulado (transacción-local, como llega por la
-- Data API). '' = sin sesión (auth.uid() → NULL).
create function pg_temp.cext_como(p_n integer) returns void
  language sql volatile as
$$ select pg_catalog.set_config('request.jwt.claim.sub', pg_temp.cext_uid(p_n)::text, true) $$;

create function pg_temp.cext_sin_sesion() returns void
  language sql volatile as
$$ select pg_catalog.set_config('request.jwt.claim.sub', '', true) $$;

create function pg_temp.cext_num(p_codigo text, p_campo text,
                                 p_esperado numeric, p_obtenido numeric)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.cext_caso(p_codigo);
  if p_esperado is distinct from p_obtenido then
    raise exception '% · %: ESPERADO % · OBTENIDO %',
      p_codigo, p_campo,
      coalesce(p_esperado::text, '<null>'), coalesce(p_obtenido::text, '<null>');
  end if;
end;
$$;

create function pg_temp.cext_txt(p_codigo text, p_campo text,
                                 p_esperado text, p_obtenido text)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.cext_caso(p_codigo);
  if p_esperado is distinct from p_obtenido then
    raise exception '% · %: ESPERADO % · OBTENIDO %',
      p_codigo, p_campo,
      coalesce(p_esperado, '<null>'), coalesce(p_obtenido, '<null>');
  end if;
end;
$$;

-- Intento que DEBE fallar. Ejecuta en subtransacción (todo se desanda, incluso
-- si aceptara), compara SQLSTATE y, si se pide, el mensaje. Un rechazo sin
-- control positivo al lado no distingue «la base defiende la regla» de «esa
-- fila no entraba ni bien formada»: cada grupo de rechazos tiene su ACEPTADO.
create function pg_temp.cext_falla(p_codigo text, p_campo text, p_sql text,
                                   p_sqlstate text, p_msg_like text default null)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.cext_caso(p_codigo);
  begin
    execute p_sql;
    raise exception 'CEXT_ACEPTADO';
  exception
    when others then
      if sqlerrm = 'CEXT_ACEPTADO' then
        raise exception '% · %: ESPERADO rechazo (sqlstate %) · OBTENIDO ACEPTADO',
          p_codigo, p_campo, p_sqlstate;
      end if;
      if sqlstate is distinct from p_sqlstate then
        raise exception '% · %: ESPERADO sqlstate % · OBTENIDO % (mensaje: %)',
          p_codigo, p_campo, p_sqlstate, sqlstate, sqlerrm;
      end if;
      if p_msg_like is not null and sqlerrm not like p_msg_like then
        raise exception '% · %: ESPERADO mensaje como %L · OBTENIDO %',
          p_codigo, p_campo, p_msg_like, sqlerrm;
      end if;
  end;
end;
$$;

-- Fila de un vendedor en conversion_mensual_fn (array `responsables`).
create function pg_temp.cext_fila_conv(p_codigo text, p_payload jsonb, p_vendedor uuid)
returns jsonb language plpgsql volatile as
$$
declare
  v_fila jsonb;
begin
  perform pg_temp.cext_caso(p_codigo);
  select el.value into v_fila
  from jsonb_array_elements(p_payload -> 'responsables') el
  where (el.value ->> 'vendedor_id')::uuid = p_vendedor;
  if v_fila is null then
    raise exception '% · responsables: ESPERADO una fila para % · OBTENIDO ninguna (el array trae %)',
      p_codigo, p_vendedor, jsonb_array_length(p_payload -> 'responsables');
  end if;
  return v_fila;
end;
$$;

-- Fila de un vendedor en cumplimiento_metas_fn (array `vendedores`).
create function pg_temp.cext_fila_meta(p_codigo text, p_payload jsonb, p_vendedor uuid)
returns jsonb language plpgsql volatile as
$$
declare
  v_fila jsonb;
begin
  perform pg_temp.cext_caso(p_codigo);
  select el.value into v_fila
  from jsonb_array_elements(p_payload -> 'vendedores') el
  where (el.value ->> 'vendedor_id')::uuid = p_vendedor;
  if v_fila is null then
    raise exception '% · vendedores: ESPERADO una fila para % · OBTENIDO ninguna (el array trae %)',
      p_codigo, p_vendedor, jsonb_array_length(p_payload -> 'vendedores');
  end if;
  return v_fila;
end;
$$;

-- Detalle categoria×moneda dentro de una fila de cumplimiento.
create function pg_temp.cext_detalle(p_fila jsonb, p_cat text, p_mon text)
returns jsonb language sql volatile as
$$
  select el.value
  from jsonb_array_elements(p_fila -> 'detalles') el
  where el.value ->> 'categoria' = p_cat and el.value ->> 'moneda' = p_mon
$$;

-- Elemento cooperativa×moneda de `totales` de cierres_externos_fn.
create function pg_temp.cext_total(p_payload jsonb, p_coop text, p_mon text)
returns jsonb language sql volatile as
$$
  select el.value
  from jsonb_array_elements(p_payload -> 'totales') el
  where el.value ->> 'cooperativa' = p_coop and el.value ->> 'moneda' = p_mon
$$;

-- Elemento vendedor×cooperativa×moneda de `por_empresa`.
create function pg_temp.cext_empresa(p_payload jsonb, p_vendedor uuid, p_coop text, p_mon text)
returns jsonb language sql volatile as
$$
  select el.value
  from jsonb_array_elements(p_payload -> 'por_empresa') el
  where (el.value ->> 'vendedor_id')::uuid = p_vendedor
    and el.value ->> 'cooperativa' = p_coop and el.value ->> 'moneda' = p_mon
$$;

-- ---------------------------------------------------------------------------
-- CEXT-00a · PRECONDICIÓN: esta conexión es dueña de las tablas del fixture
-- ---------------------------------------------------------------------------
do $test$
declare
  v_sin_dueno text;
begin
  perform pg_temp.cext_caso('CEXT-00a');
  select string_agg(c.relname, ', ' order by c.relname)
    into v_sin_dueno
  from pg_catalog.pg_class c
  where c.oid in ('crm.equipo'::regclass, 'crm.leads'::regclass,
                  'crm.lead_asignaciones'::regclass, 'crm.cierres_externos'::regclass)
    and not pg_catalog.pg_has_role(current_user, c.relowner, 'USAGE');
  if v_sin_dueno is not null then
    raise exception 'CEXT-00a · duenno de las tablas del fixture: ESPERADO % duenno · OBTENIDO sin dominio sobre: %',
      current_user, v_sin_dueno;
  end if;
end;
$test$;

-- ---------------------------------------------------------------------------
-- CEXT-00b · PRECONDICIÓN: los triggers empiezan en su sitio
-- ---------------------------------------------------------------------------
-- (No se mira crm.equipo: el ciclo del gate suspende
-- trg_equipo_validar_usuarios_jerarquia durante seed+corrida.)
do $test$
declare
  v_apagados text;
begin
  perform pg_temp.cext_caso('CEXT-00b');
  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ' order by t.tgname)
    into v_apagados
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.leads'::regclass, 'crm.lead_asignaciones'::regclass,
                      'crm.cierres_externos'::regclass)
    and not t.tgisinternal
    and t.tgenabled = 'D';
  if v_apagados is not null then
    raise exception 'CEXT-00b · triggers deshabilitados ANTES de sembrar: ESPERADO ninguno · OBTENIDO %', v_apagados;
  end if;
end;
$test$;

-- ---------------------------------------------------------------------------
-- 1. Personas
-- ---------------------------------------------------------------------------
--  1 SUP1        supervisor del equipo bajo prueba
--  2 A           vendedor de SUP1 — el protagonista (3 cierres externos)
--  3 B           vendedor de SUP1 — su lead lo convierte SUP1; gerencia corrige
--  4 GERENCIA    equipo gerencia (perfil directorio, como en producción)
--  5 COORD       coordinador — denegado en todas las RPC nuevas
--  6 SUP2        supervisor AJENO
--  7 C           vendedor de SUP2 — cierre con pasaporte, ANULADO en CEXT-16
--  8 LECTOR      directorio PURO (sin fila en equipo): agregados sí, filas no
--  9 SACRIFICIO  vendedor de SUP2; su episodio retro-fechado da cobertura
--                histórica al ledger (sin él, el mes sale no-medible)
insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
select
  pg_temp.cext_uid(n), 'authenticated', 'authenticated',
  'cext-' || n || '@test.invalid', now(), '{}', '{}', now(), now()
from generate_series(1, 9) n;

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  (pg_temp.cext_uid(1), 'ORACULO CEXT SUP1',       'cext-1@test.invalid', 'comercial',  true),
  (pg_temp.cext_uid(2), 'ORACULO CEXT A',          'cext-2@test.invalid', 'comercial',  true),
  (pg_temp.cext_uid(3), 'ORACULO CEXT B',          'cext-3@test.invalid', 'comercial',  true),
  (pg_temp.cext_uid(4), 'ORACULO CEXT GERENCIA',   'cext-4@test.invalid', 'directorio', true),
  (pg_temp.cext_uid(5), 'ORACULO CEXT COORD',      'cext-5@test.invalid', 'comercial',  true),
  (pg_temp.cext_uid(6), 'ORACULO CEXT SUP2',       'cext-6@test.invalid', 'comercial',  true),
  (pg_temp.cext_uid(7), 'ORACULO CEXT C',          'cext-7@test.invalid', 'comercial',  true),
  (pg_temp.cext_uid(8), 'ORACULO CEXT LECTOR',     'cext-8@test.invalid', 'directorio', true),
  (pg_temp.cext_uid(9), 'ORACULO CEXT SACRIFICIO', 'cext-9@test.invalid', 'comercial',  true);

alter table crm.equipo disable trigger user;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  (pg_temp.cext_uid(1), 'supervisor',  null,                 true),
  (pg_temp.cext_uid(2), 'vendedor',    pg_temp.cext_uid(1),  true),
  (pg_temp.cext_uid(3), 'vendedor',    pg_temp.cext_uid(1),  true),
  (pg_temp.cext_uid(4), 'gerencia',    null,                 true),
  (pg_temp.cext_uid(5), 'coordinador', null,                 true),
  (pg_temp.cext_uid(6), 'supervisor',  null,                 true),
  (pg_temp.cext_uid(7), 'vendedor',    pg_temp.cext_uid(6),  true),
  (pg_temp.cext_uid(9), 'vendedor',    pg_temp.cext_uid(6),  true);
alter table crm.equipo enable trigger user;

-- ---------------------------------------------------------------------------
-- 2. El snapshot de metas del mes (la cuota valida contra ESTA foto)
-- ---------------------------------------------------------------------------
-- Directo como dueño: publicar por la RPC arrastraría el roster real del
-- branch; aquí el snapshot ES el fixture. Todos los detalles son nuevo/PEN
-- porque en cooperativas solo se invierte en soles (2026-08-12) y la meta
-- operativa vive normalizada ahí.
-- La costura de «se ve pero no cuenta» ya no la da la moneda: la da la
-- ANULACIÓN (CEXT-16), que es el caso que de verdad importa vigilar.
insert into crm.meta_periodos (id, periodo, revision, publicada_por)
values (pg_temp.cext_uid(900), pg_temp.cext_mes(), 1, pg_temp.cext_uid(4));

insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo)
values
  (pg_temp.cext_uid(901), pg_temp.cext_uid(900), pg_temp.cext_uid(2), pg_temp.cext_uid(1), 50),
  (pg_temp.cext_uid(902), pg_temp.cext_uid(900), pg_temp.cext_uid(3), pg_temp.cext_uid(1), 50),
  (pg_temp.cext_uid(903), pg_temp.cext_uid(900), pg_temp.cext_uid(7), pg_temp.cext_uid(6), 50);

insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo)
values
  (pg_temp.cext_uid(901), 'nuevo', 'PEN', 50000, 5),
  (pg_temp.cext_uid(902), 'nuevo', 'PEN', 20000, 2),
  (pg_temp.cext_uid(903), 'nuevo', 'PEN', 10000, 1);

-- ---------------------------------------------------------------------------
-- 3. Leads. Cada alta con vendedor abre su episodio por el trigger REAL.
-- ---------------------------------------------------------------------------
select pg_temp.cext_como(4);  -- gerencia da las altas

insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, asignado_supervisor_id, creado_por
)
values
  -- L1101: no referido de A → qorilazo PEN 10.000 (CEXT-01)
  (pg_temp.cext_uid(1101), 'ORACULO CEXT 1101 QORILAZO', pg_temp.cext_tel(1101), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(2), null, pg_temp.cext_uid(4)),
  -- L1102: REFERIDO de A → prodelco PEN 2.000; pesa 0,150 (CEXT-03)
  (pg_temp.cext_uid(1102), 'ORACULO CEXT 1102 REFERIDO', pg_temp.cext_tel(1102), 'referido', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(2), null, pg_temp.cext_uid(4)),
  -- L1103: no referido de A; recibe las validaciones y al final → qorilazo PEN 1.500
  (pg_temp.cext_uid(1103), 'ORACULO CEXT 1103 VALIDA',   pg_temp.cext_tel(1103), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(2), null, pg_temp.cext_uid(4)),
  -- L1104: de B; lo convierte SUP1 → prodelco PEN 7.000; gerencia corrige (CEXT-05/13)
  (pg_temp.cext_uid(1104), 'ORACULO CEXT 1104 DE B',     pg_temp.cext_tel(1104), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(3), null, pg_temp.cext_uid(4)),
  -- L1105: de C (equipo ajeno) → prodelco PEN 3.000 con pasaporte (CEXT-04/09),
  -- y en CEXT-16 gerencia lo ANULA: es la costura de «se ve pero no cuenta».
  (pg_temp.cext_uid(1105), 'ORACULO CEXT 1105 DE C',     pg_temp.cext_tel(1105), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(7), null, pg_temp.cext_uid(4)),
  -- L1106: cola global, sin analista: no se puede convertir (CEXT-07)
  (pg_temp.cext_uid(1106), 'ORACULO CEXT 1106 COLA',     pg_temp.cext_tel(1106), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', null, null, pg_temp.cext_uid(4)),
  -- L1107: de A; se DESCARTA antes (divisor sí, convertir no) (CEXT-08)
  (pg_temp.cext_uid(1107), 'ORACULO CEXT 1107 DESCARTE', pg_temp.cext_tel(1107), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(2), null, pg_temp.cext_uid(4)),
  -- L1108: de SACRIFICIO; su episodio se retro-fecha para dar cobertura al ledger
  (pg_temp.cext_uid(1108), 'ORACULO CEXT 1108 SUELO',    pg_temp.cext_tel(1108), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(9), null, pg_temp.cext_uid(4)),
  -- L1109: de SACRIFICIO; GERENCIA lo convierte con éxito (caso positivo del
  -- alcance global que faltaba en la matriz — hallazgo M1 del auditor)
  (pg_temp.cext_uid(1109), 'ORACULO CEXT 1109 GLOBAL',   pg_temp.cext_tel(1109), 'landing',  'nuevo', 1000, 'PEN', 'nuevo', pg_temp.cext_uid(9), null, pg_temp.cext_uid(4));

-- Cobertura histórica: el suelo del ledger tiene que ser ANTERIOR al arranque
-- del mes o conversion_mensual_fn declara el mes no-medible (y con razón). El
-- reloj no se puede mover por la vía normal (el guard lo pisa con
-- statement_timestamp), así que se duerme el guard SOLO para esta corrección,
-- igual que hace test-conversion-mensual.
-- Se mueven también las TRES columnas del SLA porque sus CHECK las amarran a
-- `asignado_en` (lead_asignaciones_sla_global_orden_valido y compañía, 20260718152741)
-- — mismo idioma que la sección 3 de test-conversion-mensual.
alter table crm.lead_asignaciones disable trigger user;
update crm.lead_asignaciones
   set asignado_en               = pg_temp.cext_instante_suelo(),
       sla_global_iniciado_en    = pg_temp.cext_instante_suelo(),
       primera_gestion_limite_en = pg_temp.cext_instante_suelo() + interval '1 hour',
       primer_contacto_limite_en = pg_temp.cext_instante_suelo() + interval '2 hours'
 where lead_id = pg_temp.cext_uid(1108);
alter table crm.lead_asignaciones enable trigger user;

-- L1107 se descarta por el camino normal (UPDATE de etapa; el AFTER cierra el
-- episodio como descartado). Entra al divisor de A y NO al numerador.
update crm.leads
   set etapa = 'descartado', motivo_descarte = 'sin_interes'
 where id = pg_temp.cext_uid(1107);

-- ---------------------------------------------------------------------------
-- CEXT-00c · La siembra quedó como se declaró
-- ---------------------------------------------------------------------------
do $test$
declare
  v_n bigint;
begin
  select count(*) into v_n from crm.lead_asignaciones la
  where la.lead_id in (select pg_temp.cext_uid(n) from generate_series(1101, 1109) n);
  perform pg_temp.cext_num('CEXT-00c', 'episodios del fixture (8 altas con dueno)', 8, v_n);

  select count(*) into v_n from crm.lead_asignaciones la
  where la.lead_id = pg_temp.cext_uid(1107) and la.resultado = 'descartado';
  perform pg_temp.cext_num('CEXT-00c', 'descarte de L1107 cerrado en el ledger', 1, v_n);

  select count(*) into v_n from crm.lead_asignaciones la
  where not la.aproximado
    and la.asignado_en < pg_temp.cext_mes()::timestamp at time zone 'America/Lima';
  perform pg_temp.cext_num('CEXT-00c', 'episodios ANTES del mes (cobertura del suelo)', 1, v_n);
end;
$test$;

-- ---------------------------------------------------------------------------
-- 4. Fase RPC — rol y identidad reales
-- ---------------------------------------------------------------------------
set local role authenticated;

-- ── CEXT-01 · A convierte L1101 a Qorilazo: la foto, el lead y el ledger ────
select pg_temp.cext_como(2);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-01');
  v_res := crm.convertir_lead_externo(
    pg_temp.cext_uid(1101), 'qorilazo', 10000.00, 'PEN',
    'DNI', '41000001', 'Cliente Qorilazo Uno',
    'OP-QOR-1101', 'QOR-2026-001',
    (pg_temp.cext_mes() + interval '13 months')::date, 'primera inversion');
  perform pg_temp.cext_txt('CEXT-01', 'respuesta ok', 'true', v_res ->> 'ok');
  perform pg_temp.cext_txt('CEXT-01', 'respuesta cooperativa', 'qorilazo', v_res ->> 'cooperativa');
end;
$test$;

reset role;
do $test$
declare
  v_cierre crm.cierres_externos%rowtype;
  v_lead   crm.leads%rowtype;
  v_ep     crm.lead_asignaciones%rowtype;
  v_n      bigint;
begin
  select * into v_cierre from crm.cierres_externos where lead_id = pg_temp.cext_uid(1101);
  if not found then
    raise exception 'CEXT-01 · cierre: ESPERADO una fila en crm.cierres_externos · OBTENIDO ninguna';
  end if;
  perform pg_temp.cext_txt('CEXT-01', 'foto cooperativa', 'qorilazo', v_cierre.cooperativa);
  perform pg_temp.cext_num('CEXT-01', 'foto monto', 10000.00, v_cierre.monto);
  perform pg_temp.cext_txt('CEXT-01', 'foto moneda', 'PEN', v_cierre.moneda);
  perform pg_temp.cext_txt('CEXT-01', 'foto documento', '41000001', v_cierre.documento);
  perform pg_temp.cext_txt('CEXT-01', 'foto vendedor (quien cobra)', pg_temp.cext_uid(2)::text, v_cierre.vendedor_id::text);
  perform pg_temp.cext_txt('CEXT-01', 'foto creado_por', pg_temp.cext_uid(2)::text, v_cierre.creado_por::text);
  perform pg_temp.cext_txt('CEXT-01', 'foto referencia', 'QOR-2026-001', v_cierre.referencia_externa);

  select * into v_lead from crm.leads where id = pg_temp.cext_uid(1101);
  perform pg_temp.cext_txt('CEXT-01', 'lead etapa', 'convertido', v_lead.etapa);
  perform pg_temp.cext_txt('CEXT-01', 'lead perfil_id (sin portal)', '<null>', coalesce(v_lead.perfil_id::text, '<null>'));
  if v_lead.convertido_en is null then
    raise exception 'CEXT-01 · lead convertido_en: ESPERADO no nulo · OBTENIDO null';
  end if;

  -- El episodio se cerró por el CAMINO REAL, idéntico a un cierre Avance.
  select * into v_ep from crm.lead_asignaciones
  where lead_id = pg_temp.cext_uid(1101) and resultado = 'convertido';
  if not found then
    raise exception 'CEXT-01 · ledger: ESPERADO episodio cerrado convertido · OBTENIDO ninguno';
  end if;
  perform pg_temp.cext_txt('CEXT-01', 'ledger motivo_cierre', 'convertido', v_ep.motivo_cierre);
  perform pg_temp.cext_txt('CEXT-01', 'ledger analista', pg_temp.cext_uid(2)::text, v_ep.analista_id::text);
  perform pg_temp.cext_txt('CEXT-01', 'ledger finalizado_por', pg_temp.cext_uid(2)::text, v_ep.finalizado_por::text);
  -- Ficha y ledger fechan el cierre con relojes distintos: convertido_en =
  -- now() (transaction_timestamp) y resultado_en = statement_timestamp()
  -- (20260717212639:636). En producción cada RPC es su propia transacción y
  -- los dos coinciden; en la ÚNICA transacción de este oráculo divergen por
  -- diseño, así que aquí se asevera lo que la métrica necesita: ambos existen
  -- y caen en el MISMO mes de Lima.
  perform pg_temp.cext_txt('CEXT-01', 'ficha y ledger en el mismo mes de Lima',
    date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date::text,
    date_trunc('month', v_ep.resultado_en at time zone 'America/Lima')::date::text);
  perform pg_temp.cext_txt('CEXT-01', 'ledger origen (foto no referido)', 'landing', v_ep.origen);

  select count(*) into v_n from crm.actividades a
  where a.lead_id = pg_temp.cext_uid(1101) and a.tipo = 'conversion'
    and a.metadata ->> 'cooperativa' = 'qorilazo'
    and (a.metadata ->> 'cierre_externo_id')::uuid = v_cierre.id;
  perform pg_temp.cext_num('CEXT-01', 'actividad de conversion con metadata', 1, v_n);
end;
$test$;
set local role authenticated;

-- ── CEXT-02 · doble cierre: el lead ya está cerrado ─────────────────────────
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-02', 'reconvertir L1101 (ya convertido)',
  format('select crm.convertir_lead_externo(%L, %L, 500.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1101), 'prodelco', 'PEN', 'DNI', '41000001', 'X', 'CEXT-RECHAZO-01'),
  'P0001', '%ya esta cerrado%');

-- ── CEXT-03 · el REFERIDO cerrado en coop existe y pesará 0,150 ─────────────
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-03');
  v_res := crm.convertir_lead_externo(
    pg_temp.cext_uid(1102), 'prodelco', 2000.00, 'PEN',
    'DNI', '41000002', 'Cliente Referido Prodelco', 'OP-PRO-1102');
  perform pg_temp.cext_txt('CEXT-03', 'respuesta ok', 'true', v_res ->> 'ok');
end;
$test$;

-- ── CEXT-04 · fuera de ámbito: ni A ni SUP1 tocan el lead de C ──────────────
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-04', 'A sobre lead de C',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1105), 'qorilazo', 'PEN', 'DNI', '41000005', 'X', 'CEXT-RECHAZO-02'),
  'P0001', '%fuera de tu ambito%');
select pg_temp.cext_como(1);
select pg_temp.cext_falla('CEXT-04', 'SUP1 sobre lead de C (equipo ajeno)',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1105), 'qorilazo', 'PEN', 'DNI', '41000005', 'X', 'CEXT-RECHAZO-03'),
  'P0001', '%fuera de tu ambito%');
-- La fuga intra-equipo canónica: A sobre el lead de B (MISMO supervisor).
-- vendedor_ids_visibles(A) = {A}: compañero no es cartera propia.
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-04', 'A sobre lead de B (mismo equipo)',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1104), 'qorilazo', 'PEN', 'DNI', '41000004', 'X', 'CEXT-RECHAZO-04'),
  'P0001', '%fuera de tu ambito%');
-- COORD denegado en el gate de rol, aunque el lead exista.
select pg_temp.cext_como(5);
select pg_temp.cext_falla('CEXT-04', 'coordinador denegado (42501)',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-05'),
  '42501');
select pg_temp.cext_sin_sesion();
select pg_temp.cext_falla('CEXT-04', 'sin sesion denegado (42501)',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-06'),
  '42501');
-- rol_crm NULL (directorio puro): el gate debe dar 42501, no dejarlo llegar al
-- ámbito. Con el `not in` heredado de convertir_lead, NULL not in (...) es NULL
-- y el gate no dispara — la trampa que el gate RLS cazó en vivo (2026-08-12).
select pg_temp.cext_como(8);
select pg_temp.cext_falla('CEXT-04', 'rol_crm NULL (directorio) denegado (42501)',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-07'),
  '42501');

-- ── CEXT-05 · SUP1 convierte el lead de B: la comisión es de B ──────────────
select pg_temp.cext_como(1);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-05');
  v_res := crm.convertir_lead_externo(
    pg_temp.cext_uid(1104), 'prodelco', 7000.00, 'PEN',
    'CE', '001234567', 'Cliente CE Prodelco', 'OP-PRO-1104');
  perform pg_temp.cext_txt('CEXT-05', 'respuesta ok', 'true', v_res ->> 'ok');
end;
$test$;

-- ...y GERENCIA convierte con éxito el lead de un vendedor cualquiera (el caso
-- positivo del alcance global): la comisión sigue siendo del analista.
select pg_temp.cext_como(4);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-05');
  v_res := crm.convertir_lead_externo(
    pg_temp.cext_uid(1109), 'prodelco', 100.00, 'PEN',
    'DNI', '41000009', 'Cliente Global Prodelco', 'OP-PRO-1109');
  perform pg_temp.cext_txt('CEXT-05', 'gerencia convierte (alcance global)', 'true', v_res ->> 'ok');
end;
$test$;

reset role;
do $test$
declare
  v_cierre crm.cierres_externos%rowtype;
begin
  select * into v_cierre from crm.cierres_externos where lead_id = pg_temp.cext_uid(1104);
  perform pg_temp.cext_txt('CEXT-05', 'quien cobra = B (analista del lead)',
    pg_temp.cext_uid(3)::text, v_cierre.vendedor_id::text);
  perform pg_temp.cext_txt('CEXT-05', 'quien registro = SUP1',
    pg_temp.cext_uid(1)::text, v_cierre.creado_por::text);
  perform pg_temp.cext_txt('CEXT-05', 'documento CE valido', '001234567', v_cierre.documento);

  select * into v_cierre from crm.cierres_externos where lead_id = pg_temp.cext_uid(1109);
  perform pg_temp.cext_txt('CEXT-05', 'cierre de gerencia: cobra el analista (9)',
    pg_temp.cext_uid(9)::text, v_cierre.vendedor_id::text);
  perform pg_temp.cext_txt('CEXT-05', 'cierre de gerencia: registro gerencia',
    pg_temp.cext_uid(4)::text, v_cierre.creado_por::text);
end;
$test$;
set local role authenticated;

-- ── CEXT-06 · validaciones 22023 (y el ACEPTADO de control llega en CEXT-09) ─
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-06', 'monto cero',
  format('select crm.convertir_lead_externo(%L, %L, 0, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-08'),
  '22023');
select pg_temp.cext_falla('CEXT-06', 'monto con 3 decimales',
  format('select crm.convertir_lead_externo(%L, %L, 100.123, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-09'),
  '22023');
select pg_temp.cext_falla('CEXT-06', 'cooperativa desconocida',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'coopac_x', 'PEN', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-10'),
  '22023');
select pg_temp.cext_falla('CEXT-06', 'moneda EUR',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'EUR', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-11'),
  '22023');
-- DOLARES: en cooperativas solo se invierte en soles (regla de negocio de
-- Miguel, 2026-08-12). No es un valor «raro» como EUR: es el que un vendedor
-- podria intentar de buena fe, y por eso tiene su propio caso.
select pg_temp.cext_falla('CEXT-06', 'moneda USD (en coops solo soles)',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'USD', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-11b'),
  '22023', '%solo se registran inversiones en soles%');
-- Y el NUMERO DE OPERACION es obligatorio: sin el, el cierre no se puede
-- contrastar contra nada y el fraude sale gratis.
-- NaN: Postgres admite el numeric NaN y lo considera MAYOR que cualquier
-- numero, asi que `NaN > 0` es TRUE y `NaN <> round(NaN,2)` es FALSE. Sin la
-- guarda explicita se colaba por las dos validaciones, pasaba el CHECK de la
-- tabla y convertia en NaN la SUMA de la cuota de todo el equipo. Verificado en
-- PG17 antes de escribir la guarda.
select pg_temp.cext_falla('CEXT-06', 'monto NaN (envenenaba la cuota entera)',
  format('select crm.convertir_lead_externo(%L, %L, ''NaN''::numeric, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', 'X', 'CEXT-RECHAZO-NAN'),
  '22023', '%mayor que cero%');
select pg_temp.cext_falla('CEXT-06', 'sin numero de operacion',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', 'X', '   '),
  '22023', '%numero de operacion del deposito es obligatorio%');
select pg_temp.cext_falla('CEXT-06', 'tipo de documento RUC',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'RUC', '41000003', 'X', 'CEXT-RECHAZO-12'),
  '22023');
select pg_temp.cext_falla('CEXT-06', 'DNI de 7 digitos',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '4100003', 'X', 'CEXT-RECHAZO-13'),
  '22023');
select pg_temp.cext_falla('CEXT-06', 'pasaporte de 4 caracteres',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'PASAPORTE', 'AB12', 'X', 'CEXT-RECHAZO-14'),
  '22023');
select pg_temp.cext_falla('CEXT-06', 'nombre en blanco',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1103), 'qorilazo', 'PEN', 'DNI', '41000003', '   ', 'CEXT-RECHAZO-15'),
  '22023');

-- ── CEXT-07 · un lead sin analista no se convierte (ni gerencia puede) ──────
select pg_temp.cext_como(4);
select pg_temp.cext_falla('CEXT-07', 'cola global sin analista',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1106), 'qorilazo', 'PEN', 'DNI', '41000006', 'X', 'CEXT-RECHAZO-16'),
  '22023', '%Asigna el lead%');

-- ── CEXT-08 · un descartado está cerrado: no se convierte ───────────────────
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-08', 'descartado L1107',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1107), 'qorilazo', 'PEN', 'DNI', '41000007', 'X', 'CEXT-RECHAZO-17'),
  'P0001', '%ya esta cerrado%');

-- ── CEXT-09 · C cierra con pasaporte: normalización de la foto ─────────────
select pg_temp.cext_como(7);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-09');
  -- pasaporte en minúsculas y con aire; nombre con aire: la RPC normaliza.
  v_res := crm.convertir_lead_externo(
    pg_temp.cext_uid(1105), 'prodelco', 3000.00, 'PEN',
    'PASAPORTE', '  ab1234x  ', '  Zoila Prueba  ', '  op-pro-1105  ');
  perform pg_temp.cext_txt('CEXT-09', 'respuesta ok', 'true', v_res ->> 'ok');
end;
$test$;

-- ...y A cierra el tercero suyo (el control ACEPTADO de las validaciones de CEXT-06).
select pg_temp.cext_como(2);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-09');
  v_res := crm.convertir_lead_externo(
    pg_temp.cext_uid(1103), 'qorilazo', 1500.00, 'PEN',
    'DNI', '41000003', 'Cliente Qorilazo Dos', 'OP-QOR-1103');
  perform pg_temp.cext_txt('CEXT-09', 'L1103 convertido tras las validaciones', 'true', v_res ->> 'ok');
end;
$test$;

reset role;
do $test$
declare
  v_cierre crm.cierres_externos%rowtype;
begin
  select * into v_cierre from crm.cierres_externos where lead_id = pg_temp.cext_uid(1105);
  perform pg_temp.cext_txt('CEXT-09', 'pasaporte normalizado a mayusculas', 'AB1234X', v_cierre.documento);
  perform pg_temp.cext_txt('CEXT-09', 'nombre sin aire', 'Zoila Prueba', v_cierre.nombre_completo);
  perform pg_temp.cext_txt('CEXT-09', 'moneda PEN (en coops no hay dolares)', 'PEN', v_cierre.moneda);
  -- El numero de operacion se guarda NORMALIZADO, igual que el pasaporte: es
  -- lo que hace que « op-pro-1105 » y «OP-PRO-1105» sean el mismo deposito.
  perform pg_temp.cext_txt('CEXT-09', 'numero de operacion sin aire', 'op-pro-1105', v_cierre.numero_transaccion);
end;
$test$;

-- ── CEXT-10 · el teléfono del convertido queda LIBRE: la persona renace ─────
-- (uq_leads_telefono_vivo solo vigila leads vivos no cerrados: si esa misma
-- persona luego quiere invertir en Avance, se le crea un lead nuevo.)
select pg_temp.cext_como(4);
do $test$
declare
  v_nuevo uuid;
begin
  perform pg_temp.cext_caso('CEXT-10');
  insert into crm.leads (
    nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
    categoria_interes, vendedor_id, asignado_supervisor_id, creado_por
  ) values (
    'ORACULO CEXT RENACIDO', pg_temp.cext_tel(1101), 'landing', 'nuevo', 1000, 'PEN',
    'nuevo', null, null, pg_temp.cext_uid(4)
  )
  returning id into v_nuevo;
  if v_nuevo is null then
    raise exception 'CEXT-10 · renacer: ESPERADO alta aceptada con el telefono del convertido · OBTENIDO nada';
  end if;
  -- En cola global: sin episodio, sin tocar el divisor de nadie.
  if exists (select 1 from crm.lead_asignaciones la where la.lead_id = v_nuevo) then
    raise exception 'CEXT-10 · renacer: el lead en cola global NO debe abrir episodio';
  end if;
end;
$test$;
set local role authenticated;

-- ── CEXT-11 · la conversión del mes cuenta los cierres externos SOLA ────────
-- A: divisor 3 (L1101, L1103, L1107 descartado; el referido L1102 NO entra),
--    numerador 1 + 1 + 0,150 = 2,150 → 71,67 %.
-- B: divisor 1, numerador 1 → 100 %.
select pg_temp.cext_como(1);
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.cext_mes());

  f := pg_temp.cext_fila_conv('CEXT-11', v_pay, pg_temp.cext_uid(2));
  perform pg_temp.cext_num('CEXT-11', 'divisor de A', 3, (f ->> 'divisor')::numeric);
  perform pg_temp.cext_num('CEXT-11', 'cierres no referidos de A', 2, (f ->> 'cierres_no_referidos')::numeric);
  perform pg_temp.cext_num('CEXT-11', 'cierres referidos de A', 1, (f ->> 'cierres_referidos')::numeric);
  perform pg_temp.cext_num('CEXT-11', 'numerador de A (2 + 0,150)', 2.150, (f ->> 'numerador')::numeric);
  perform pg_temp.cext_num('CEXT-11', 'conversion_pct de A', 71.67, (f ->> 'conversion_pct')::numeric);
  perform pg_temp.cext_txt('CEXT-11', 'estado de A', 'medible', f ->> 'estado');

  f := pg_temp.cext_fila_conv('CEXT-11', v_pay, pg_temp.cext_uid(3));
  perform pg_temp.cext_num('CEXT-11', 'divisor de B', 1, (f ->> 'divisor')::numeric);
  perform pg_temp.cext_num('CEXT-11', 'numerador de B', 1, (f ->> 'numerador')::numeric);
  perform pg_temp.cext_num('CEXT-11', 'conversion_pct de B', 100.00, (f ->> 'conversion_pct')::numeric);
end;
$test$;

-- ── CEXT-12 · la CUOTA suma los cierres externos (antes de la corrección) ───
do $test$
declare
  v_pay jsonb;
  f jsonb;
  d jsonb;
begin
  v_pay := crm.cumplimiento_metas_fn(pg_temp.cext_mes());

  f := pg_temp.cext_fila_meta('CEXT-12', v_pay, pg_temp.cext_uid(2));
  d := pg_temp.cext_detalle(f, 'nuevo', 'PEN');
  perform pg_temp.cext_num('CEXT-12', 'capital_real de A (10000+2000+1500)', 13500, (d ->> 'capital_real')::numeric);
  perform pg_temp.cext_num('CEXT-12', 'contratos_real de A (3 cierres)', 3, (d ->> 'contratos_real')::numeric);
  perform pg_temp.cext_num('CEXT-12', 'capital_cumplimiento_pct de A (13500/50000)', 27.00, (d ->> 'capital_cumplimiento_pct')::numeric);
  -- La conversión histórica del payload de metas también los ve (convertido_en).
  perform pg_temp.cext_num('CEXT-12', 'convertidos de A', 3, (f ->> 'convertidos')::numeric);
  perform pg_temp.cext_num('CEXT-12', 'resueltos de A (3 conv + 1 descarte)', 4, (f ->> 'resueltos')::numeric);

  f := pg_temp.cext_fila_meta('CEXT-12', v_pay, pg_temp.cext_uid(3));
  d := pg_temp.cext_detalle(f, 'nuevo', 'PEN');
  perform pg_temp.cext_num('CEXT-12', 'capital_real de B (7000 aun sin corregir)', 7000, (d ->> 'capital_real')::numeric);
  perform pg_temp.cext_num('CEXT-12', 'contratos_real de B', 1, (d ->> 'contratos_real')::numeric);
end;
$test$;

-- ── CEXT-13 · la corrección es de gerencia y la cuota la refleja ────────────
-- El id del cierre se captura como dueño y viaja en un GUC transaccional: un
-- subquery a crm.cierres_externos dentro del intento correría como
-- `authenticated` y moriría con 42501 ANTES de llegar al gate de la RPC — el
-- rechazo saldría verde por la razón equivocada.
reset role;
select set_config('cext.cierre_1104', ce.id::text, true)
from crm.cierres_externos ce where ce.lead_id = pg_temp.cext_uid(1104);
set local role authenticated;

select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-13', 'vendedor no corrige (42501)',
  format('select crm.corregir_cierre_externo(%L::uuid, 9000.00, %L, %L, %L, %L, null, null)',
    current_setting('cext.cierre_1104'), 'PEN', 'qorilazo', 'OP-PRO-1104', 'QOR-2026-77'),
  '42501');
select pg_temp.cext_como(1);
select pg_temp.cext_falla('CEXT-13', 'supervisor no corrige (42501)',
  format('select crm.corregir_cierre_externo(%L::uuid, 9000.00, %L, %L, %L, %L, null, null)',
    current_setting('cext.cierre_1104'), 'PEN', 'qorilazo', 'OP-PRO-1104', 'QOR-2026-77'),
  '42501');
select pg_temp.cext_como(8);
select pg_temp.cext_falla('CEXT-13', 'lector global no corrige (42501)',
  format('select crm.corregir_cierre_externo(%L::uuid, 9000.00, %L, %L, %L, %L, null, null)',
    current_setting('cext.cierre_1104'), 'PEN', 'qorilazo', 'OP-PRO-1104', 'QOR-2026-77'),
  '42501');
select pg_temp.cext_como(4);
select pg_temp.cext_falla('CEXT-13', 'gerencia con monto de 3 decimales (22023)',
  format('select crm.corregir_cierre_externo(%L::uuid, 9000.123, %L, %L, %L, %L, null, null)',
    current_setting('cext.cierre_1104'), 'PEN', 'qorilazo', 'OP-PRO-1104', 'QOR-2026-77'),
  '22023');
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-13');
  -- Gerencia corrige TAMBIEN el numero de operacion: es la unica que puede, y
  -- es lo que se hace cuando el vendedor lo tipeo mal.
  v_res := crm.corregir_cierre_externo(
    current_setting('cext.cierre_1104')::uuid,
    9000.00, 'PEN', 'qorilazo', 'OP-PRO-1104-BIS', 'QOR-2026-77',
    null, 'monto real del certificado');
  perform pg_temp.cext_txt('CEXT-13', 'correccion ok', 'true', v_res ->> 'ok');
end;
$test$;

reset role;
do $test$
declare
  v_cierre crm.cierres_externos%rowtype;
  v_n bigint;
begin
  select * into v_cierre from crm.cierres_externos where lead_id = pg_temp.cext_uid(1104);
  perform pg_temp.cext_num('CEXT-13', 'monto corregido', 9000.00, v_cierre.monto);
  perform pg_temp.cext_txt('CEXT-13', 'cooperativa corregida', 'qorilazo', v_cierre.cooperativa);
  perform pg_temp.cext_txt('CEXT-13', 'referencia corregida', 'QOR-2026-77', v_cierre.referencia_externa);
  -- La identidad NO se movió: quien cobra sigue siendo B y el documento el CE.
  perform pg_temp.cext_txt('CEXT-13', 'identidad intacta: vendedor', pg_temp.cext_uid(3)::text, v_cierre.vendedor_id::text);
  perform pg_temp.cext_txt('CEXT-13', 'identidad intacta: documento', '001234567', v_cierre.documento);

  select count(*) into v_n from crm.actividades a
  where a.lead_id = pg_temp.cext_uid(1104) and a.tipo = 'nota'
    and a.metadata ->> 'accion' = 'correccion_cierre_externo'
    and (a.metadata -> 'antes' ->> 'monto')::numeric = 7000.00
    and (a.metadata -> 'despues' ->> 'monto')::numeric = 9000.00;
  perform pg_temp.cext_num('CEXT-13', 'actividad de correccion con antes/despues', 1, v_n);
end;
$test$;
set local role authenticated;

-- La cuota de B ahora dice 9000, y la de C dice 3000: los dos cierres cuentan.
-- El de C se anulará en CEXT-16 y ese 3000 volverá a cero — por eso aquí se
-- afirma el ANTES: sin control positivo, la anulación no probaría nada.
select pg_temp.cext_como(4);
do $test$
declare
  v_pay jsonb;
  f jsonb;
  d jsonb;
begin
  v_pay := crm.cumplimiento_metas_fn(pg_temp.cext_mes());

  f := pg_temp.cext_fila_meta('CEXT-13', v_pay, pg_temp.cext_uid(3));
  d := pg_temp.cext_detalle(f, 'nuevo', 'PEN');
  perform pg_temp.cext_num('CEXT-13', 'capital_real de B tras la correccion', 9000, (d ->> 'capital_real')::numeric);

  -- C cerro 3.000 en soles y SI tiene meta: su cierre cuenta. Es el control
  -- positivo que da sentido al CEXT-16 de abajo, donde ese mismo cierre se
  -- anula y este numero vuelve a cero.
  f := pg_temp.cext_fila_meta('CEXT-13', v_pay, pg_temp.cext_uid(7));
  d := pg_temp.cext_detalle(f, 'nuevo', 'PEN');
  perform pg_temp.cext_num('CEXT-13', 'capital_real de C ANTES de anular', 3000, (d ->> 'capital_real')::numeric);
  perform pg_temp.cext_num('CEXT-13', 'contratos_real de C ANTES de anular', 1, (d ->> 'contratos_real')::numeric);
end;
$test$;

-- ── CEXT-14 · cierres_externos_fn: ámbitos, totales y desglose ──────────────
-- A (propio): sus 3 cierres y nada del resto.
select pg_temp.cext_como(2);
do $test$
declare
  v_pay jsonb;
  t jsonb;
begin
  v_pay := crm.cierres_externos_fn(pg_temp.cext_mes());
  perform pg_temp.cext_txt('CEXT-14', 'alcance de A', 'propio', v_pay ->> 'alcance');
  perform pg_temp.cext_num('CEXT-14', 'cierres_total de A', 3, (v_pay ->> 'cierres_total')::numeric);
  perform pg_temp.cext_num('CEXT-14', 'filas visibles de A', 3, jsonb_array_length(v_pay -> 'cierres'));

  t := pg_temp.cext_total(v_pay, 'qorilazo', 'PEN');
  perform pg_temp.cext_num('CEXT-14', 'total qorilazo PEN de A (10000+1500)', 11500, (t ->> 'capital')::numeric);
  perform pg_temp.cext_num('CEXT-14', 'cierres qorilazo PEN de A', 2, (t ->> 'cierres')::numeric);
  t := pg_temp.cext_total(v_pay, 'prodelco', 'PEN');
  perform pg_temp.cext_num('CEXT-14', 'total prodelco PEN de A', 2000, (t ->> 'capital')::numeric);

  -- El teléfono viene del lead (la mini-ficha lo necesita y A puede verlo).
  -- Por SUFIJO: el alta lo normaliza con prefijo +51.
  if not exists (
    select 1 from jsonb_array_elements(v_pay -> 'cierres') el
    where el.value ->> 'telefono' like '%' || pg_temp.cext_tel(1101)
  ) then
    raise exception 'CEXT-14 · filas de A: ESPERADO el telefono del lead en la fila · OBTENIDO ninguno';
  end if;
end;
$test$;

-- SUP1 (equipo): los 3 de A + el corregido de B; nada de C.
select pg_temp.cext_como(1);
do $test$
declare
  v_pay jsonb;
  t jsonb;
  e jsonb;
begin
  v_pay := crm.cierres_externos_fn(pg_temp.cext_mes());
  perform pg_temp.cext_txt('CEXT-14', 'alcance de SUP1', 'equipo', v_pay ->> 'alcance');
  perform pg_temp.cext_num('CEXT-14', 'cierres_total de SUP1', 4, (v_pay ->> 'cierres_total')::numeric);
  -- El bloque DEL MES respeta el mismo ambito: 4 del equipo, y NINGUNO de C.
  perform pg_temp.cext_num('CEXT-14', 'cierres_mes de SUP1', 4, jsonb_array_length(v_pay -> 'cierres_mes'));
  if exists (select 1 from jsonb_array_elements(v_pay -> 'cierres_mes') c
             where c ->> 'vendedor_id' = pg_temp.cext_uid(7)::text) then
    raise exception 'CEXT-14 · SUP1 ve en cierres_mes un cierre de C (equipo ajeno)';
  end if;

  t := pg_temp.cext_total(v_pay, 'qorilazo', 'PEN');
  perform pg_temp.cext_num('CEXT-14', 'total qorilazo PEN del equipo (11500+9000)', 20500, (t ->> 'capital')::numeric);
  -- Prodelco de SUP1 = SOLO el referido de A (L1102, 2.000). El cierre de C
  -- (3.000, prodelco) es de otro equipo y NO puede sumar aquí: si se colara, el
  -- número diría 5.000. La exclusión se afirma con el TOTAL exacto y no con un
  -- «no hay nada», que en este fixture ya no probaría el ámbito.
  perform pg_temp.cext_num('CEXT-14', 'total prodelco PEN del equipo (solo el referido de A)',
    2000, (pg_temp.cext_total(v_pay, 'prodelco', 'PEN') ->> 'capital')::numeric);

  -- El desglose del mes por vendedor: B con 9000 en qorilazo.
  e := pg_temp.cext_empresa(v_pay, pg_temp.cext_uid(3), 'qorilazo', 'PEN');
  perform pg_temp.cext_num('CEXT-14', 'por_empresa B qorilazo PEN', 9000, (e ->> 'capital')::numeric);
  perform pg_temp.cext_num('CEXT-14', 'por_empresa B cierres', 1, (e ->> 'cierres')::numeric);
end;
$test$;

-- Gerencia (global): los 6 (A×3 + B + C + el global de la 1109).
select pg_temp.cext_como(4);
do $test$
declare
  v_pay jsonb;
  e jsonb;
begin
  v_pay := crm.cierres_externos_fn(pg_temp.cext_mes());
  perform pg_temp.cext_txt('CEXT-14', 'alcance de gerencia', 'global', v_pay ->> 'alcance');
  perform pg_temp.cext_num('CEXT-14', 'cierres_total global', 6, (v_pay ->> 'cierres_total')::numeric);
  e := pg_temp.cext_empresa(v_pay, pg_temp.cext_uid(7), 'prodelco', 'PEN');
  perform pg_temp.cext_num('CEXT-14', 'por_empresa C prodelco PEN', 3000, (e ->> 'capital')::numeric);
end;
$test$;

-- LECTOR puro (directorio sin equipo): agregados sí, filas NO (PII).
select pg_temp.cext_como(8);
do $test$
declare
  v_pay jsonb;
begin
  v_pay := crm.cierres_externos_fn(pg_temp.cext_mes());
  perform pg_temp.cext_txt('CEXT-14', 'alcance del lector global', 'global', v_pay ->> 'alcance');
  perform pg_temp.cext_num('CEXT-14', 'filas del lector global (PII vedada)', 0, jsonb_array_length(v_pay -> 'cierres'));
  -- El bloque DEL MES es igual de sensible que el historico y nacio sin una
  -- sola asercion: si manana alguien lo copia «como el de arriba» y se come el
  -- gate, el lector global empieza a recibir documento y telefono de todos los
  -- cierres del mes y el ciclo entero sigue en verde.
  perform pg_temp.cext_num('CEXT-14', 'filas DEL MES del lector global (PII vedada)', 0, jsonb_array_length(v_pay -> 'cierres_mes'));
  perform pg_temp.cext_num('CEXT-14', 'cierres_mes_total del lector global', 6, (v_pay ->> 'cierres_mes_total')::numeric);
  perform pg_temp.cext_num('CEXT-14', 'cierres_total del lector global', 6, (v_pay ->> 'cierres_total')::numeric);
  perform pg_temp.cext_num('CEXT-14', 'totales visibles para el lector',
    20500, (pg_temp.cext_total(v_pay, 'qorilazo', 'PEN') ->> 'capital')::numeric);
end;
$test$;

-- Denegados y períodos inválidos.
select pg_temp.cext_como(5);
select pg_temp.cext_falla('CEXT-14', 'coordinador denegado (42501)',
  format('select crm.cierres_externos_fn(%L::date)', pg_temp.cext_mes()), '42501');
select pg_temp.cext_sin_sesion();
select pg_temp.cext_falla('CEXT-14', 'sin sesion denegado (42501)',
  format('select crm.cierres_externos_fn(%L::date)', pg_temp.cext_mes()), '42501');
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-14', 'periodo no es primer dia (22023)',
  format('select crm.cierres_externos_fn(%L::date)', pg_temp.cext_mes() + 1), '22023');
select pg_temp.cext_falla('CEXT-14', 'periodo futuro (22023)',
  format('select crm.cierres_externos_fn((%L::date + interval ''1 month'')::date)', pg_temp.cext_mes()), '22023');

-- ── CEXT-15 · la Data API no toca la tabla: deny-by-default absoluto ────────
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-15', 'select directo como authenticated',
  'select count(*) from crm.cierres_externos', '42501');
select pg_temp.cext_falla('CEXT-15', 'insert directo como authenticated',
  format('insert into crm.cierres_externos (lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion, vendedor_id, creado_por) values (%L, %L, 1.00, %L, %L, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1106), 'qorilazo', 'PEN', 'DNI', '41000006', 'X', 'OP-DIRECTO',
    pg_temp.cext_uid(2), pg_temp.cext_uid(2)),
  '42501');
select pg_temp.cext_falla('CEXT-15', 'update directo como authenticated',
  'update crm.cierres_externos set monto = 1.00', '42501');
select pg_temp.cext_falla('CEXT-15', 'delete directo como authenticated',
  'delete from crm.cierres_externos', '42501');


-- ---------------------------------------------------------------------------
-- CEXT-16 · LA ANULACIÓN: el cierre se ve, pero deja de contar
-- ---------------------------------------------------------------------------
-- El freno de emergencia de gerencia contra un cierre falso o mal digitado. Lo
-- que se prueba es lo que Miguel pidió (2026-08-12): que un cierre anulado no
-- cuente NI en dinero NI en conversión. El control positivo lo dejó CEXT-13
-- (capital de C = 3000) y CEXT-11 (su conversión); aquí se anula y los dos
-- números caen — sin control positivo previo, esto no probaría nada.
--
-- El id viaja por GUC transaccional, igual que en CEXT-13: un subquery a
-- crm.cierres_externos dentro del intento correría como `authenticated` y
-- moriría con 42501 antes de llegar al gate de rol.
reset role;
select set_config('cext.cierre_1105', ce.id::text, true)
from crm.cierres_externos ce where ce.lead_id = pg_temp.cext_uid(1105);
set local role authenticated;

-- Quién NO puede anular: ni el vendedor que cobró, ni su supervisor, ni el
-- lector global. Anular mueve dinero de una persona: es de gerencia.
select pg_temp.cext_como(7);
select pg_temp.cext_falla('CEXT-16', 'el vendedor no anula su propio cierre (42501)',
  format('select crm.anular_cierre_externo(%L::uuid, %L)',
    current_setting('cext.cierre_1105'), 'me arrepenti'),
  '42501');
select pg_temp.cext_como(6);
select pg_temp.cext_falla('CEXT-16', 'el supervisor no anula (42501)',
  format('select crm.anular_cierre_externo(%L::uuid, %L)',
    current_setting('cext.cierre_1105'), 'no me cuadra'),
  '42501');
select pg_temp.cext_como(8);
select pg_temp.cext_falla('CEXT-16', 'el lector global no anula (42501)',
  format('select crm.anular_cierre_externo(%L::uuid, %L)',
    current_setting('cext.cierre_1105'), 'curioseando'),
  '42501');
-- Y gerencia tampoco anula SIN MOTIVO: esto le quita dinero a alguien y esa
-- persona merece una razón escrita.
select pg_temp.cext_como(4);
select pg_temp.cext_falla('CEXT-16', 'gerencia sin motivo (22023)',
  format('select crm.anular_cierre_externo(%L::uuid, %L)',
    current_setting('cext.cierre_1105'), '   '),
  '22023', '%motivo de la anulacion%');

do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-16');
  v_res := crm.anular_cierre_externo(
    current_setting('cext.cierre_1105')::uuid,
    'El deposito no existe en el estado de cuenta');
  perform pg_temp.cext_txt('CEXT-16', 'anulacion ok', 'true', v_res ->> 'ok');
end;
$test$;

-- De UNA SOLA DIRECCIÓN, y un anulado tampoco se corrige (corregirlo daría a
-- entender que vuelve a contar, y no vuelve).
select pg_temp.cext_falla('CEXT-16', 'no se anula dos veces (P0409)',
  format('select crm.anular_cierre_externo(%L::uuid, %L)',
    current_setting('cext.cierre_1105'), 'otra vez'),
  'P0409', '%ya estaba anulado%');
select pg_temp.cext_falla('CEXT-16', 'un anulado no se corrige (P0409)',
  format('select crm.corregir_cierre_externo(%L::uuid, 1.00, %L, %L, %L, null, null, null)',
    current_setting('cext.cierre_1105'), 'PEN', 'prodelco', 'OP-NUEVA'),
  'P0409', '%esta anulado%');

-- La foto: autoría, motivo y el rastro en la línea de tiempo del lead.
reset role;
do $test$
declare
  v_cierre crm.cierres_externos%rowtype;
  v_n bigint;
begin
  select * into v_cierre from crm.cierres_externos where lead_id = pg_temp.cext_uid(1105);
  if v_cierre.anulado_en is null then
    raise exception 'CEXT-16 · anulado_en: ESPERADO una fecha · OBTENIDO NULL';
  end if;
  perform pg_temp.cext_txt('CEXT-16', 'anulado_por es gerencia',
    pg_temp.cext_uid(4)::text, v_cierre.anulado_por::text);
  perform pg_temp.cext_txt('CEXT-16', 'motivo guardado',
    'El deposito no existe en el estado de cuenta', v_cierre.motivo_anulacion);
  -- El lead NO se reabre: un convertido es terminal por diseño.
  perform pg_temp.cext_txt('CEXT-16', 'el lead sigue convertido', 'convertido',
    (select l.etapa from crm.leads l where l.id = pg_temp.cext_uid(1105)));
  select count(*) into v_n
  from crm.actividades a
  where a.lead_id = pg_temp.cext_uid(1105)
    and a.tipo = 'nota'
    and a.metadata ->> 'accion' = 'anulacion_cierre_externo';
  perform pg_temp.cext_num('CEXT-16', 'actividad de anulacion', 1, v_n);
end;
$test$;
set local role authenticated;

-- Y AHORA los dos números. La cuota de C vuelve a cero…
select pg_temp.cext_como(4);
do $test$
declare
  v_pay jsonb;
  f jsonb;
  d jsonb;
begin
  perform pg_temp.cext_caso('CEXT-16');
  v_pay := crm.cumplimiento_metas_fn(pg_temp.cext_mes());
  f := pg_temp.cext_fila_meta('CEXT-16', v_pay, pg_temp.cext_uid(7));
  d := pg_temp.cext_detalle(f, 'nuevo', 'PEN');
  perform pg_temp.cext_num('CEXT-16', 'capital_real de C tras anular', 0, (d ->> 'capital_real')::numeric);
  perform pg_temp.cext_num('CEXT-16', 'contratos_real de C tras anular', 0, (d ->> 'contratos_real')::numeric);

  -- Y LA CONVERSIÓN DE ESTE MISMO PAYLOAD. Es el número que pintan el resumen
  -- de gerencia, inteligencia comercial y las alertas — y venía de una CTE
  -- distinta (`conversiones`, que mira `leads.etapa`), así que tras anular
  -- seguía diciendo «1 convertido, 100 %» mientras conversion_mensual_fn ya
  -- decía 0 %. Dos números para el mismo concepto, los dos en pantalla. El
  -- divisor (`resueltos`) NO se mueve: el lead se trabajó igual.
  perform pg_temp.cext_num('CEXT-16', 'convertidos de C en la CUOTA tras anular', 0, (f ->> 'convertidos')::numeric);
  perform pg_temp.cext_num('CEXT-16', 'resueltos de C (el divisor no se mueve)', 1, (f ->> 'resueltos')::numeric);
  perform pg_temp.cext_num('CEXT-16', 'conversion_real de C en la CUOTA tras anular', 0, (f ->> 'conversion_real')::numeric);
end;
$test$;

-- …y su CONVERSIÓN también, sin que el divisor se mueva: el lead se trabajó y
-- le sigue contando (misma regla que un descartado). Lo que se le quita es el
-- premio, no el trabajo.
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  perform pg_temp.cext_caso('CEXT-16');
  v_pay := crm.conversion_mensual_fn(pg_temp.cext_mes());
  f := pg_temp.cext_fila_conv('CEXT-16', v_pay, pg_temp.cext_uid(7));
  perform pg_temp.cext_num('CEXT-16', 'divisor de C NO se mueve al anular', 1, (f ->> 'divisor')::numeric);
  perform pg_temp.cext_num('CEXT-16', 'cierres de C tras anular', 0, (f ->> 'cierres_no_referidos')::numeric);
  perform pg_temp.cext_num('CEXT-16', 'numerador de C tras anular', 0, (f ->> 'numerador')::numeric);
  perform pg_temp.cext_num('CEXT-16', 'conversion_pct de C tras anular', 0.00, (f ->> 'conversion_pct')::numeric);
end;
$test$;

-- En la lectura: la fila SIGUE ahí (marcada) pero sale de los totales y del
-- desglose. Que desapareciera sería peor: el asesor vería bajar su número sin
-- ninguna explicación.
do $test$
declare
  v_pay jsonb;
  v_fila jsonb;
begin
  perform pg_temp.cext_caso('CEXT-16');
  v_pay := crm.cierres_externos_fn(pg_temp.cext_mes());
  select c into v_fila
  from jsonb_array_elements(v_pay -> 'cierres') c
  where c ->> 'lead_id' = pg_temp.cext_uid(1105)::text;
  if v_fila is null then
    raise exception 'CEXT-16 · el cierre anulado DESAPARECIO de las filas: el asesor veria bajar su total sin explicacion';
  end if;
  if v_fila ->> 'anulado_en' is null then
    raise exception 'CEXT-16 · la fila viaja SIN la marca de anulado: en pantalla pareceria viva';
  end if;
  perform pg_temp.cext_txt('CEXT-16', 'motivo visible en la fila',
    'El deposito no existe en el estado de cuenta', v_fila ->> 'motivo_anulacion');
  -- Fuera de los agregados de DINERO.
  if pg_temp.cext_empresa(v_pay, pg_temp.cext_uid(7), 'prodelco', 'PEN') is not null then
    raise exception 'CEXT-16 · el cierre anulado SIGUE en por_empresa: los agregados son dinero y un anulado no lo es';
  end if;
  -- Prodelco vivo = L1102 (2.000) + L1109 (100). El 1104 se fue a qorilazo en
  -- la corrección de CEXT-13 y el 1105 (3.000) acaba de anularse.
  perform pg_temp.cext_num('CEXT-16', 'total prodelco PEN sin el anulado',
    2100, (pg_temp.cext_total(v_pay, 'prodelco', 'PEN') ->> 'capital')::numeric);
end;
$test$;

-- ---------------------------------------------------------------------------
-- CEXT-17 · el MISMO depósito no se cobra dos veces
-- ---------------------------------------------------------------------------
-- El fraude que Codex encontró: un cierre real reingresado paga doble. El
-- índice único `(cooperativa, upper(btrim(numero_transaccion)))` lo cierra.
-- Aquí se ataca por la ruta de CORRECCIÓN (gerencia intenta ponerle a un cierre
-- el depósito de otro de la MISMA cooperativa); la ruta de conversión sobre un
-- lead distinto la cubre el veredicto (8) del postflight de la migración, que
-- fabrica el segundo lead sin tocar los conteos de este fixture.
select pg_temp.cext_como(4);
select pg_temp.cext_falla('CEXT-17', 'mismo deposito, misma cooperativa (P0409)',
  format('select crm.corregir_cierre_externo(%L::uuid, 9000.00, %L, %L, %L, null, null, null)',
    current_setting('cext.cierre_1104'), 'PEN', 'qorilazo', 'OP-QOR-1103'),
  'P0409', '%ya esta registrado%');
-- Y la normalización: cambia la caja y sobran espacios, sigue siendo el mismo.
select pg_temp.cext_falla('CEXT-17', 'mismo deposito con otra caja y espacios (P0409)',
  format('select crm.corregir_cierre_externo(%L::uuid, 9000.00, %L, %L, %L, null, null, null)',
    current_setting('cext.cierre_1104'), 'PEN', 'qorilazo', '  op-qor-1103  '),
  'P0409', '%ya esta registrado%');
-- Y EN LA OTRA COOPERATIVA TAMPOCO. Éste es el agujero que Codex encontró en
-- la primera corrección: el índice era único POR COOPERATIVA, y la cooperativa
-- la elige el mismo vendedor cuya declaración se está deduplicando. Bastaba
-- declarar el voucher una vez en Qorilazo y otra en Prodelco para cobrarlo dos
-- veces. Un namespace que controla el sospechoso no es un namespace.
select pg_temp.cext_falla('CEXT-17', 'mismo deposito movido a la OTRA cooperativa (P0409)',
  format('select crm.corregir_cierre_externo(%L::uuid, 9000.00, %L, %L, %L, null, null, null)',
    current_setting('cext.cierre_1104'), 'PEN', 'prodelco', 'OP-QOR-1103'),
  'P0409', '%ya esta registrado%');
-- El precio asumido: una colisión legítima entre bancos también se rechaza. Es
-- barato al lado de cobrar dos veces, y gerencia corrige o anula.
-- Se deja el cierre como estaba: un oráculo no deja rastros que no declara.
do $test$
begin
  perform pg_temp.cext_caso('CEXT-17');
  perform crm.corregir_cierre_externo(
    current_setting('cext.cierre_1104')::uuid,
    9000.00, 'PEN', 'qorilazo', 'OP-PRO-1104-BIS', 'QOR-2026-77',
    null, 'monto real del certificado');
end;
$test$;

-- LA MEMORIA HISTÓRICA. El índice vivo solo vigila los números que están
-- puestos AHORA: al corregir «OP-PRO-1104» a «OP-PRO-1104-BIS», el primero
-- salía del índice y quedaba libre para que otro lead lo declarara y cobrara el
-- mismo depósito dos veces. `crm.depositos_reclamados` no olvida.
-- Se ataca desde el cierre de L1101, que está VIVO: si se usara uno anulado, el
-- veto de «un anulado no se corrige» saltaría antes y el caso no probaría nada.
reset role;
select set_config('cext.cierre_1101', ce.id::text, true)
from crm.cierres_externos ce where ce.lead_id = pg_temp.cext_uid(1101);
set local role authenticated;
select pg_temp.cext_como(4);
select pg_temp.cext_falla('CEXT-17', 'un numero YA CORREGIDO no se puede reusar en otro cierre',
  format('select crm.corregir_cierre_externo(%L::uuid, 10000.00, %L, %L, %L, null, null, null)',
    current_setting('cext.cierre_1101'), 'PEN', 'qorilazo', 'OP-PRO-1104'),
  'P0409', '%ya esta registrado%');
-- Y esa memoria es de verdad append-only: ni el dueño de la base la limpia.
reset role;
do $test$
declare v_ok boolean := false;
begin
  perform pg_temp.cext_caso('CEXT-17');
  begin
    delete from crm.depositos_reclamados;
  exception when sqlstate 'P0409' then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'CEXT-17 · la memoria de depositos SE PUDO BORRAR: si se limpia, el mismo deposito se cobra dos veces';
  end if;
  begin
    v_ok := false;
    update crm.depositos_reclamados set numero_norm = 'OTRO';
  exception when sqlstate 'P0409' then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'CEXT-17 · la memoria de depositos SE PUDO EDITAR';
  end if;
end;
$test$;
set local role authenticated;
select pg_temp.cext_como(4);

-- ---------------------------------------------------------------------------
-- CEXT-18 · LA CARRERA: la reserva que evita el usuario de portal huérfano
-- ---------------------------------------------------------------------------
-- La conversión Avance no es transaccional: crea el usuario, el perfil y MANDA
-- EL CORREO antes de cerrar el lead. Si en esa ventana se confirma un cierre en
-- cooperativa, el inversionista de la coop acaba con cuenta de portal — y un
-- correo no se retira. La reserva durable es lo que lo impide.
--
-- Todo este caso usa L1108 (de SACRIFICIO) y NO lo convierte: solo reserva e
-- intenta. El fixture queda intacto.

-- La dirección que salva el correo: si el cierre en coop ya ganó, la reserva
-- falla y la edge se entera ANTES de crear nada.
select pg_temp.cext_como(2);
select pg_temp.cext_falla('CEXT-18', 'no se reserva un lead ya convertido',
  format('select crm.reservar_conversion_lead(%L)', pg_temp.cext_uid(1101)),
  'P0001', '%ya esta cerrado%');
select pg_temp.cext_falla('CEXT-18', 'no se reserva un lead fuera de ambito',
  format('select crm.reservar_conversion_lead(%L)', pg_temp.cext_uid(1108)),
  'P0001', '%fuera de tu ambito%');
select pg_temp.cext_como(5);
select pg_temp.cext_falla('CEXT-18', 'coordinador no reserva (42501)',
  format('select crm.reservar_conversion_lead(%L)', pg_temp.cext_uid(1108)),
  '42501');
select pg_temp.cext_sin_sesion();
select pg_temp.cext_falla('CEXT-18', 'sin sesion no reserva (42501)',
  format('select crm.reservar_conversion_lead(%L)', pg_temp.cext_uid(1108)),
  '42501');

-- SACRIFICIO reserva su lead (es lo que hace la edge antes de crear el usuario).
select pg_temp.cext_como(9);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-18');
  v_res := crm.reservar_conversion_lead(pg_temp.cext_uid(1108));
  perform pg_temp.cext_txt('CEXT-18', 'reserva ok', 'true', v_res ->> 'ok');
  -- Idempotente para el MISMO actor: un reintento de la edge renueva, no choca.
  v_res := crm.reservar_conversion_lead(pg_temp.cext_uid(1108));
  perform pg_temp.cext_txt('CEXT-18', 'el mismo actor renueva su reserva', 'true', v_res ->> 'ok');
end;
$test$;

-- Otro actor con ámbito (su supervisor) choca mientras la reserva viva.
select pg_temp.cext_como(6);
select pg_temp.cext_falla('CEXT-18', 'otro actor no pisa una reserva viva (P0409)',
  format('select crm.reservar_conversion_lead(%L)', pg_temp.cext_uid(1108)),
  'P0409', '%esta convirtiendo este lead%');

-- Y EL PUNTO DE TODO: con la reserva viva, el cierre en cooperativa se rechaza
-- —incluso al MISMO que reservó—, porque lo que importa no es quién la tomó
-- sino que el correo de bienvenida quizá ya salió.
select pg_temp.cext_como(9);
select pg_temp.cext_falla('CEXT-18', 'la reserva viva bloquea el cierre en coop (P0409)',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1108), 'qorilazo', 'PEN', 'DNI', '41000008', 'X', 'OP-CARRERA'),
  'P0409', '%conversion a cliente de Avance en curso%');

-- Caducada la reserva SIN efectos, el camino se abre solo (una edge caída antes
-- de tocar nada no deja el lead incerrable para siempre). Se caduca como dueño:
-- la tabla es deny-by-default.
reset role;
update crm.conversion_reservas set expira_en = now() - interval '1 minute'
where lead_id = pg_temp.cext_uid(1108);
set local role authenticated;
-- ⚠️ Se comprueba con OTRO actor (SUP2), no con el que reservó. Con el mismo
-- actor esta prueba era VACUA: él puede renovar hasta una reserva viva, así que
-- habría salido verde aunque la caducidad estuviera rota. Lo cazó Codex.
select pg_temp.cext_como(6);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-18');
  v_res := crm.reservar_conversion_lead(pg_temp.cext_uid(1108));
  perform pg_temp.cext_txt('CEXT-18', 'caducada la reserva, OTRO actor puede tomarla', 'true', v_res ->> 'ok');
end;
$test$;

-- ── EL PUNTO DE NO RETORNO ─────────────────────────────────────────────────
-- Cuando la edge ya creó el usuario de Auth, la reserva DEJA DE CADUCAR. Es el
-- agujero que la primera versión no cerraba: bastaba que la edge muriera tras
-- mandar el correo para que, cinco minutos después, el cierre en cooperativa
-- entrara igual y quedara un inversionista de coop con acceso al portal.
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-18');
  v_res := crm.marcar_efectos_conversion(pg_temp.cext_uid(1108));
  perform pg_temp.cext_txt('CEXT-18', 'la edge sella el punto de no retorno', 'true', v_res ->> 'ok');
end;
$test$;
-- Se fuerza la caducidad: da igual, ya no manda.
reset role;
update crm.conversion_reservas set expira_en = now() - interval '1 hour'
where lead_id = pg_temp.cext_uid(1108);
set local role authenticated;
select pg_temp.cext_como(9);
select pg_temp.cext_falla('CEXT-18', 'con efectos iniciados, el cierre en coop NO entra ni con la reserva caducada',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1108), 'qorilazo', 'PEN', 'DNI', '41000008', 'X', 'OP-NO-RETORNO'),
  'P0409', '%cuenta de cliente de Avance en proceso%');
-- Y tampoco se puede «reiniciar» esa reserva para saltarse el candado.
select pg_temp.cext_falla('CEXT-18', 'una reserva con efectos no se reinicia',
  format('select crm.reservar_conversion_lead(%L)', pg_temp.cext_uid(1108)),
  'P0409', '%conversion a cliente de Avance empezada%');
-- Sellar la reserva de OTRO sería regalar un bloqueo permanente sobre su lead.
select pg_temp.cext_como(1);
select pg_temp.cext_falla('CEXT-18', 'no se sella la reserva de otro actor',
  format('select crm.marcar_efectos_conversion(%L)', pg_temp.cext_uid(1108)),
  'P0409', '%ya no esta viva%');

-- EL REINTENTO. Si la conversión Avance falla en el último paso, la pantalla
-- dice «reintenta» — y ese reintento tiene que poder entrar. Su DUEÑO retoma su
-- propia reserva aunque ya esté sellada y caducada; cualquier OTRO, no. Sin
-- esto, un fallo de red en la última llamada dejaba el lead trabado para
-- siempre y la instrucción de la pantalla era mentira.
-- ⚠️ El dueño de la reserva a estas alturas es SUP2 (la tomó cuando caducó la
-- de SACRIFICIO) y es quien la selló: el reintento le toca a ÉL.
select pg_temp.cext_como(6);
do $test$
declare
  v_res jsonb;
begin
  perform pg_temp.cext_caso('CEXT-18');
  v_res := crm.reservar_conversion_lead(pg_temp.cext_uid(1108));
  perform pg_temp.cext_txt('CEXT-18', 'su DUENO puede reintentar una conversion sellada', 'true', v_res ->> 'ok');
end;
$test$;
-- Pero el sello NO se borra al retomar: el cierre en coop sigue vetado, que es
-- la garantía que de verdad importa.
select pg_temp.cext_como(9);
select pg_temp.cext_falla('CEXT-18', 'reintentar NO reabre el cierre en cooperativa',
  format('select crm.convertir_lead_externo(%L, %L, 100.00, %L, %L, %L, %L, %L)',
    pg_temp.cext_uid(1108), 'qorilazo', 'PEN', 'DNI', '41000008', 'X', 'OP-TRAS-REINTENTO'),
  'P0409', '%cuenta de cliente de Avance en proceso%');
select pg_temp.cext_como(9);
select pg_temp.cext_falla('CEXT-18', 'y OTRO actor sigue sin poder retomarla',
  format('select crm.reservar_conversion_lead(%L)', pg_temp.cext_uid(1108)),
  'P0409', '%empezada por otra persona%');
-- Y la tabla de reservas también es deny-by-default absoluto.
select pg_temp.cext_falla('CEXT-18', 'select directo a conversion_reservas (42501)',
  'select count(*) from crm.conversion_reservas', '42501');
select pg_temp.cext_falla('CEXT-18', 'insert directo a conversion_reservas (42501)',
  format('insert into crm.conversion_reservas (lead_id, reservado_por, expira_en) values (%L, %L, now())',
    pg_temp.cext_uid(1106), pg_temp.cext_uid(2)),
  '42501');

-- ---------------------------------------------------------------------------
-- CEXT-99 · Foto final: los triggers quedaron como estaban
-- ---------------------------------------------------------------------------
reset role;
do $test$
declare
  v_apagados text;
  v_faltan text;
begin
  -- ⚠️ crm.equipo queda FUERA del escaneo a propósito (mismo criterio que
  -- CONV-00b/99): el ciclo del gate suspende trg_equipo_validar_usuarios_
  -- jerarquia durante seed+corrida, y mirarla aquí haría fallar el oráculo en
  -- el único entorno donde se corre. El disable/enable de la sección 1 es
  -- transaccional y el rollback final lo deshace igual.
  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ' order by t.tgname)
    into v_apagados
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.leads'::regclass, 'crm.lead_asignaciones'::regclass,
                      'crm.cierres_externos'::regclass)
    and not t.tgisinternal
    and t.tgenabled = 'D';
  if v_apagados is not null then
    raise exception 'CEXT-99 · triggers deshabilitados AL FINAL: ESPERADO ninguno · OBTENIDO %', v_apagados;
  end if;
  perform pg_temp.cext_caso('CEXT-99');

  -- Y todos los casos anunciados corrieron: un oráculo que se salta secciones
  -- en silencio no es un oráculo.
  select string_agg(c.codigo, ', ' order by c.codigo)
    into v_faltan
  from unnest(pg_temp.cext_casos_esperados()) c(codigo)
  where not exists (select 1 from pg_temp.cext_casos r where r.codigo = c.codigo);
  if v_faltan is not null then
    raise exception 'CEXT-99 · casos que NO corrieron: %', v_faltan;
  end if;
end;
$test$;

rollback;

select 'CIERRES_EXTERNOS_OK' as resultado;
