-- 20261004160034_crm_bases_cargadas_esquema.sql
--
-- Bases cargadas · B7 (solo esquema). Pedido de Miguel (03/10/2026) y decisiones E1–E14 (03–04/10/2026) en
-- `BASE PARA GESTION/BASES-CARGADAS.md`: el supervisor carga bases antiguas (archivo o armadas desde el CRM), las reparte a
-- sus analistas y sigue si se trabajan. Esta migración NO trae puertas (cargar, armar, repartir, recoger, seguimiento: B8–B10):
-- solo las tablas, los valores nuevos y sus candados.
--
-- QUÉ HACE
--   1. Tres tablas nuevas (esquema crm, RLS ON, sin grants para la API, sin DELETE, auditadas con private.log_audit_crm):
--      · crm.bases_carga — la base: nombre (1–80, único por supervisor entre las vivas, sin distinguir mayúsculas), origen
--        archivo|crm, supervisor dueño (su bandeja; E11: gerencia elige el supervisor), quién la creó, id de operación único,
--        nombre del archivo (solo si origen = archivo) y los totales del informe. SIN capital por defecto (E8: si el Excel no
--        trae capital, no existe).
--      · crm.base_carga_leads — qué lead está en qué base, de dónde vino (archivo|crm) y a quién se repartió (analista,
--        cuándo, quién: los tres NULL a la vez = sin repartir). Un lead una sola vez por base, y en UNA sola base viva.
--      · crm.base_carga_operaciones — recibos INMUTABLES de cada operación (crear, cargar_lote, armar, repartir, recoger):
--        actor, id de operación (único por actor: idempotencia de B8–B10), base, md5 del pedido y respuesta sin datos
--        personales. UPDATE, DELETE y TRUNCATE se rechazan (P0409).
--   2. crm.leads, SIN columnas nuevas (los grants por columna no cambian):
--      · 'base_cargada' en el CHECK del origen (leads_origen_check) y en la lista de private.leads_before_insert (E7).
--      · 'base_cargada' en el CHECK del motivo de descarte (leads_motivo_descarte_check) y en el de la política de
--        enfriamiento (enfriamiento_politica_motivo_check), con su fila: 30 días (ver ENFRIAMIENTO).
--      · Capital vacío SOLO en un contacto de base cargada DORMIDO (E8): monto_estimado deja de ser NOT NULL y
--        leads_monto_estimado_valido (mismo nombre: el front lo traduce por nombre, app/src/data/crm-api.ts:2055-2059 →
--        «El capital estimado es obligatorio y debe ser mayor que 0») pasa a
--          (monto_estimado is null and origen = 'base_cargada' and etapa = 'descartado')
--          or (monto_estimado is not null and <las tres condiciones de 20260717222018>)
--        La etapa va EN el CHECK (ajuste del coordinador, 04/10, regla «toda vía va en el lead»): toda vía que saque al lead
--        del descarte sin capital —reactivar_lead_base, reabrir_lead_fn («Reabrir»), tomar_lead_libre, rescatar_descartes,
--        una edición— falla con 23514 en su propio UPDATE (medido en el banco con las cuatro puertas reales; con el capital
--        puesto pasan). El `monto_estimado is not null` explícito de la segunda rama NO es adorno: sin él, con el NOT NULL
--        quitado, un NULL deja esa rama en NULL y un CHECK con NULL PASA — cualquier origen y cualquier etapa (medido: el
--        mutante con la fórmula sin esa guarda cae en la suite).
--   3. Sello nuevo `trg_leads_000_base_cargada_solo_puerta` (BEFORE INSERT OR UPDATE ON crm.leads, por fila, sin WHEN) con
--      private.trg_leads_base_cargada_solo_puerta(): lo reservado de los valores nuevos vive en UNA sola definición.
--      Sin la válvula de transacción `crm.op_bases_carga = on` (hoy no la enciende nadie; la encenderá el núcleo de B8):
--        · un lead que nace o pasa a tener origen base_cargada → 42501;
--        · un lead que nace o pasa a tener motivo_descarte base_cargada → 42501;
--        · cambiar el motivo base_cargada de un lead que SIGUE descartado → 42501 (auditor-rls r1, P3: «despertar» un dormido
--          a datos_invalidos le daría 0 días de enfriamiento → «libre» 24 h → duplicado, contra E2).
--      Y SIEMPRE (con o sin válvula): un capital que existe no se vacía → 23514 con detail leads_monto_estimado_valido (el
--      front muestra «El capital estimado es obligatorio…»; el capital vacío solo nace con el lead; el CHECK solo no lo
--      impide en un base_cargada descartado). Salir del descarte sin capital NO es del sello: lo rechaza el
--      CHECK (una sola definición de cada regla, para que cada mutante caiga en su caso).
--      Sin exención para sesiones sin usuario: el importador (crm.importar_lead_fn) corre sin usuario y valida el origen
--      solo por la tabla (20260906210000:233-262); con la exención, la hoja del puente podría crear leads base_cargada sin
--      capital. POR QUÉ un sello además del CHECK: authenticated tiene UPDATE de tabla en crm.leads y la API descarta por
--      PATCH (supabase/scripts/test-rls.mjs:16010) — sin el sello cualquiera pondría motivo base_cargada —; y
--      crm.editar_lead_fn manda `monto_estimado = NULL` si la ficha lo pide (20260906150000:216 + SET dinámico), lo que el
--      CHECK permitiría en un contacto de base descartado. Regla de «toda vía» → en el lead (vault: «Una regla de toda vía
--      va en el lead»). Hoy no cambia nada observable: ningún lead puede tener todavía origen o motivo base_cargada ni
--      capital NULL.
--
-- ENFRIAMIENTO (crm.enfriamiento_politica, que leen private.verificar_disponibilidad_lead_impl, crm.tomar_lead_libre,
--   private.trg_leads_disponibilidad_atomica y crm.corregir_documento_inversionista_fn; NO la lee la base para gestión, que
--   usa enfriado_hasta de B4): 'base_cargada' = 30 días. Así el contacto de base dormido se comporta como un descartado
--   ELEGIBLE para la base (los de E12: sin_interes 30, no_responde 15, otro 20…) y no como datos_invalidos/pide_credito
--   (0 días), que E12 excluye: con 0 días el veredicto del alta sería «libre» durante 24 h (20260906200000:3514-3733,
--   rama de carencia) y el alta manual crearía un DUPLICADO (contra E2). Con 30: durante 30 días desde su descarte nadie
--   da de alta ese teléfono ni lo toma con «tomar lead libre» (veredicto «enfriamiento»; la base es del supervisor); después
--   es «reutilizable», como cualquier descartado vencido (E14: las otras vías no se bloquean; si no tiene capital, el CHECK
--   rechaza su reapertura). Gerencia puede cambiar los días (policy enfriamiento_update): 0 reabriría la ventana de 24 h.
--   ⚠️ PENDIENTE PARA B8/B10 (no se resuelve aquí): con el CHECK de la etapa, un contacto SIN capital solo puede existir
--   descartado, también al nacer (los CHECK no se difieren: no puede nacer 'nuevo' y descartarse después). Nace con
--   crm.op_bases_carga Y crm.op_privilegiada (private.leads_before_insert impide nacer en estado terminal sin ella) y
--   trg_leads_zz_sello_descarte (sellado por huella) le pone descartado_en = NULL al INSERTAR. Sin descartado_en:
--   (a) verificar_disponibilidad_lead_impl salta su rama de descartados → el alta de ese teléfono ve «libre» y el alta
--   manual crearía un DUPLICADO (contra E2), y tomar_lead_libre no lo encuentra: esta fila de enfriamiento no le aplica a
--   un contacto así; (b) obtener_base_gestion no tiene «días desde el descarte» y lo ordena al final. B8 debe resolverlo
--   (envoltorio de identidad «existe cualquier lead con ese teléfono o DNI», hallazgo del F0, y/o fecha de descarte).
--   Medido en el banco (suite b7-esquema.sql, casos E17–E19).
--
-- LECTURA (segundo candado; las tablas NO tienen grants: por las 4 capas la pantalla no lee tablas y las puertas DEFINER de
--   B8–B10 serán el único acceso): una policy SELECT por tabla para authenticated.
--   · crm.bases_carga: Supervisión ve las bases cuyo supervisor dueño está en su subárbol (las suyas y las de su equipo);
--     Gerencia ve todas (private.vendedor_ids_visibles le devuelve todo crm.equipo); el analista y cualquier otro rol, NADA.
--   · crm.base_carga_leads y crm.base_carga_operaciones: exists sobre crm.bases_carga (la RLS del que consulta decide).
--   Analista = NADA, decidido con evidencia: F6 le muestra la base dentro de su Base para gestión por
--   crm.obtener_base_gestion (DEFINER, B10, con su propio ámbito); nada de su pantalla lee estas tablas. Sin consumidor, el
--   segundo candado se queda en lo mínimo (si algún día lo necesita, se abre con una migración y su prueba).
-- SIN negocio_id: ninguna tabla del CRM lo tiene (convención del CRM; deuda reconocida en el CLAUDE.md raíz). Nombres de
--   tiempo en español (creado_en, actualizado_en), como 20260930213647.
-- CANDADOS (r1: Codex P2 y auditor-rls P3). Orden: candado de migración de la casa (crm_migracion_funciones) → foto del
--   censo (solo catálogo) → candados de tabla en orden fijo crm.leads (ACCESS EXCLUSIVE) → public.perfiles (SHARE ROW
--   EXCLUSIVE) → crm.enfriamiento_politica (ACCESS EXCLUSIVE), y DESPUÉS el preflight, el DDL y el postflight, hasta el
--   commit. ACCESS EXCLUSIVE porque cambiar un CHECK y quitar un NOT NULL lo exigen (validar los CHECK en otra transacción
--   bajaría a SHARE UPDATE EXCLUSIVE solo esa pasada, que medida dura ~2 ms: no justifica partir la migración). Mientras se
--   retiene, NADIE lee ni escribe crm.leads (ni las pantallas): esperan. public.perfiles solo por las FK nuevas (crearlas
--   toma SHARE ROW EXCLUSIVE: frena escrituras del portal, no lecturas; precedentes 20260930213647 y 20260922184459).
--   lock_timeout 5 s solo limita la ESPERA para obtenerlos (si no, aborta sin cambiar nada), no cuánto se retienen.
--   MEDIDO en el banco (04/10, 3083 leads, 961 descartados, una sesión que lee y otra que escribe crm.leads cada 50 ms):
--   retención (del primer LOCK TABLE al COMMIT) 115–250 ms en 5 aplicaciones; la lectura concurrente esperó como máximo
--   228 ms y la escritura 121 ms (una sentencia de cada sonda, sin errores). La validación de los tres CHECK sobre 3083 filas:
--   ~2 ms; lo que pesa es el censo del postflight (75–170 ms, una sola llamada; con tres llamadas y la foto bajo candado la r0
--   retenía 369 ms). La reversa retiene 90–144 ms (esperas 57–94 ms lectura, 65–71 ms escritura). La rama medirá con datos
--   reales. Aplicar en horario bajo. Sin DML de prueba: el postflight es SOLO de catálogo (lección de B6c: nada de DML con el
--   candado puesto). La única escritura de datos es la fila de configuración del enfriamiento.
-- CENSO: ninguna función nueva nombra crm.leads ni «reunion» con agregados; el postflight exige el censo analítico igual a
--   la foto previa. crm.cartera_filtrada_fn no se toca (huella en el censo).
-- QUÉ NO CAMBIA: columnas, grants y policies de crm.leads; descartar_lead_implementacion (su lista NO lleva base_cargada: el
--   motivo es del sistema, nadie lo elige); crear_lead_si_disponible (su lista propia no lleva base_cargada); lectores de
--   monto_estimado (inventario en el informe de B7: riesgos ante NULL, para B8–B11).
-- PRECONDICIÓN: B6c aplicada (20261004123611) — el preflight fija las definiciones vivas que reemplaza.
-- REVERSA: supabase/scripts/base-gestion/reversa-b7.sql (se niega si hay filas en las tablas nuevas, o leads con origen o
--   motivo base_cargada o capital NULL).
begin;
set transaction isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- Exclusión con otro despliegue que use el mismo candado de la casa (20260902200000:39): el preflight lee cuerpos y CHECK
-- y el DDL los reemplaza; entre medias no se cuela otro. La reversa toma el mismo.
select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));

-- Foto del censo analítico ANTES de los candados de tabla: solo lee el catálogo (~0,1 s medido) y así no alarga el ACCESS
-- EXCLUSIVE de crm.leads (Codex r1, P2). Bajo el candado de migración; si otra cosa cambiara funciones entre la foto y el
-- postflight, el postflight lo vería y abortaría (falla cerrada). El postflight exige que no cambie.
create temp table _b7_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- Candados en orden fijo ANTES del preflight (auditor-rls r1, P3: el preflight lee crm.enfriamiento_politica y crm.leads;
-- leído bajo candado, lo comprobado no cambia hasta el commit). Ver CANDADOS en la cabecera.
lock table crm.leads in access exclusive mode;
lock table public.perfiles in share row exclusive mode;
lock table crm.enfriamiento_politica in access exclusive mode;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if (
    -- Nada de B7 existe todavía.
    to_regclass('crm.bases_carga') is null
    and to_regclass('crm.base_carga_leads') is null
    and to_regclass('crm.base_carga_operaciones') is null
    and to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is null
    and to_regprocedure('private.bases_carga_operacion_inmutable()') is null
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass
                     and t.tgname = 'trg_leads_000_base_cargada_solo_puerta')
    and not exists (select 1 from crm.enfriamiento_politica ep where ep.motivo = 'base_cargada')
    -- Los CHECK que se reemplazan, EXACTOS y validados (definición medida en el banco a paridad con producción, 04/10).
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((origen = ANY (ARRAY[''referido''::text, ''landing''::text, ''formulario''::text, ''oficina''::text, ''otro''::text, ''web''::text, ''campania''::text, ''whatsapp''::text])))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_origen_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((motivo_descarte = ANY (ARRAY[''sin_interes''::text, ''sin_fondos''::text, ''competencia''::text, ''no_responde''::text, ''datos_invalidos''::text, ''pide_credito''::text, ''otro''::text])))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_motivo_descarte_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK (((monto_estimado > (0)::numeric) AND (monto_estimado <= 9999999999.99) AND (monto_estimado = trunc(monto_estimado, 2))))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_monto_estimado_valido')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((motivo = ANY (ARRAY[''sin_interes''::text, ''sin_fondos''::text, ''competencia''::text, ''no_responde''::text, ''datos_invalidos''::text, ''pide_credito''::text, ''otro''::text])))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass and c.conname = 'enfriamiento_politica_motivo_check')
    -- monto_estimado: numeric sin typmod, NOT NULL, con el comentario de hoy (se reescribe).
    and (select a.attnotnull and a.atttypid = 'numeric'::regtype and a.atttypmod = -1
                and md5(coalesce(col_description(a.attrelid, a.attnum), '')) = '46535ad03f2be4cca8b4ccc7b3e3388c'
           from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname = 'monto_estimado' and not a.attisdropped)
    -- private.leads_before_insert: la definición viva de 20260928192822 (cuerpo, DEFINER, volatilidad, search_path y dueño:
    -- huella independiente del search_path de la sesión), su ACL y sin comentario; y es la del trigger de alta.
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                    || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text) = '61451ff1ec7002a3c73670ac50f7b81a'
                and md5(p.prosrc) = '5d8df9e9f913604b1d72d0e4b0598cb2'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and obj_description(p.oid, 'pg_proc') is null
           from pg_proc p where p.oid = to_regprocedure('private.leads_before_insert()'))
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_before_insert'
                 and t.tgfoid = to_regprocedure('private.leads_before_insert()') and t.tgenabled = 'O')
    -- Ayudantes de las policies y de los disparadores, con la identidad ensayada.
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                    || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text) = '16960a2a21cc5c372431c2dd67acafe4'
           from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                    || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text) = '45ae492c03234b80336c0b8f5c8ac09b'
           from pg_proc p where p.oid = to_regprocedure('private.vendedor_ids_visibles(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                    || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text) = 'd35e819cffec4d1d17d1b0f21b97b3d7'
           from pg_proc p where p.oid = to_regprocedure('private.log_audit_crm()'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                    || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text) = '170bce0f3e1f9aed3ca24be87ad9d3b4'
           from pg_proc p where p.oid = to_regprocedure('private.set_actualizado_en_crm()'))
    -- Nadie enciende ni usa todavía la válvula nueva (ni por configuración de rol o de base: abriría el sello a todos).
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'op_bases_carga')
    and not exists (select 1 from pg_db_role_setting s cross join lateral unnest(s.setconfig) c(x)
                     where c.x ilike 'crm.op_bases_carga=%')
  ) is not true then
    raise exception 'PREFLIGHT B7: ya aplicada o a medias, un CHECK o leads_before_insert no son los medidos, un ayudante cambio, o la valvula crm.op_bases_carga ya existe';
  end if;
end;
$preflight$;

-- ── 1 · Tablas y restricciones ─────────────────────────────────────────────────────────────────────────────────────────
create table crm.bases_carga (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  origen text not null,
  supervisor_id uuid not null references public.perfiles(id),
  creada_por uuid not null references public.perfiles(id),
  operacion_id uuid not null,
  archivo_nombre text,
  filas_recibidas integer not null default 0,
  cargadas integer not null default 0,
  ya_existian integer not null default 0,
  no_contactar integer not null default 0,
  invalidas integer not null default 0,
  repetidas integer not null default 0,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint bases_carga_operacion_unica unique (operacion_id),
  constraint bases_carga_nombre_valido check (nombre = pg_catalog.btrim(nombre) and pg_catalog.char_length(nombre) between 1 and 80),
  constraint bases_carga_origen_check check (origen in ('archivo', 'crm')),
  -- Reglas separadas a propósito (cada CHECK con su mutante): el origen decide si hay archivo; el nombre, su largo.
  constraint bases_carga_archivo_coherente check ((origen = 'archivo') = (archivo_nombre is not null)),
  constraint bases_carga_archivo_nombre_valido check (archivo_nombre is null or pg_catalog.char_length(archivo_nombre) between 1 and 255),
  constraint bases_carga_totales_no_negativos check (
    filas_recibidas >= 0 and cargadas >= 0 and ya_existian >= 0 and no_contactar >= 0 and invalidas >= 0 and repetidas >= 0),
  constraint bases_carga_totales_cuadran check (
    cargadas::bigint + ya_existian::bigint + no_contactar::bigint + invalidas::bigint + repetidas::bigint <= filas_recibidas::bigint),
  constraint bases_carga_fechas_finitas check (isfinite(creado_en) and isfinite(actualizado_en))
);
alter table crm.bases_carga enable row level security;

create table crm.base_carga_leads (
  id uuid primary key default gen_random_uuid(),
  base_id uuid not null references crm.bases_carga(id),
  lead_id uuid not null references crm.leads(id),
  procedencia text not null,
  analista_id uuid references public.perfiles(id),
  asignado_en timestamptz,
  asignado_por uuid references public.perfiles(id),
  agregado_por uuid not null references public.perfiles(id),
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint base_carga_leads_base_lead_unico unique (base_id, lead_id),
  constraint base_carga_leads_procedencia_check check (procedencia in ('archivo', 'crm')),
  constraint base_carga_leads_asignacion_coherente check (
    (analista_id is null) = (asignado_en is null) and (analista_id is null) = (asignado_por is null)),
  constraint base_carga_leads_fechas_finitas check (
    isfinite(creado_en) and isfinite(actualizado_en) and (asignado_en is null or isfinite(asignado_en)))
);
alter table crm.base_carga_leads enable row level security;

create table crm.base_carga_operaciones (
  id uuid primary key default gen_random_uuid(),
  actor uuid not null references public.perfiles(id),
  operacion_id uuid not null,
  base_id uuid not null references crm.bases_carga(id),
  tipo text not null,
  pedido_md5 text not null,
  respuesta jsonb not null,
  creado_en timestamptz not null default now(),
  constraint base_carga_operaciones_actor_operacion_unica unique (actor, operacion_id),
  constraint base_carga_operaciones_tipo_check check (tipo in ('crear', 'cargar_lote', 'armar', 'repartir', 'recoger')),
  constraint base_carga_operaciones_pedido_md5_valido check (pedido_md5 ~ '^[0-9a-f]{32}$'),
  constraint base_carga_operaciones_respuesta_valida check (
    pg_catalog.jsonb_typeof(respuesta) = 'object' and pg_catalog.octet_length(respuesta::text) <= 65536),
  constraint base_carga_operaciones_creado_en_finito check (isfinite(creado_en))
);
alter table crm.base_carga_operaciones enable row level security;

-- Índices: unicidades de negocio y todas las FK con un índice que las encabeza (advisor de rendimiento).
create unique index bases_carga_nombre_vivo_unico on crm.bases_carga (supervisor_id, pg_catalog.lower(nombre)) where activo;
create index bases_carga_supervisor_idx on crm.bases_carga (supervisor_id);
create index bases_carga_creada_por_idx on crm.bases_carga (creada_por);
create unique index base_carga_leads_lead_vivo_unico on crm.base_carga_leads (lead_id) where activo;
create index base_carga_leads_lead_idx on crm.base_carga_leads (lead_id);
create index base_carga_leads_analista_idx on crm.base_carga_leads (analista_id, base_id);
create index base_carga_leads_asignado_por_idx on crm.base_carga_leads (asignado_por);
create index base_carga_leads_agregado_por_idx on crm.base_carga_leads (agregado_por);
create index base_carga_operaciones_base_idx on crm.base_carga_operaciones (base_id, creado_en);

-- ── 2 · RLS: segundo candado de lectura (sin grants) ───────────────────────────────────────────────────────────────────
create policy bases_carga_select on crm.bases_carga
  for select to authenticated
  using ((select private.rol_crm((select auth.uid()))) in ('supervisor', 'gerencia')
         and supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))));

create policy base_carga_leads_select on crm.base_carga_leads
  for select to authenticated
  using (exists (select 1 from crm.bases_carga b where b.id = base_carga_leads.base_id));

create policy base_carga_operaciones_select on crm.base_carga_operaciones
  for select to authenticated
  using (exists (select 1 from crm.bases_carga b where b.id = base_carga_operaciones.base_id));

-- ── 3 · Núcleo: disparadores ───────────────────────────────────────────────────────────────────────────────────────────
create function private.bases_carga_operacion_inmutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  raise exception 'Los recibos de las bases cargadas no se modifican ni se borran' using errcode = 'P0409';
end;
$function$;

create function private.trg_leads_base_cargada_solo_puerta()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_valvula boolean := coalesce(pg_catalog.current_setting('crm.op_bases_carga', true), 'off') = 'on';
begin
  -- B7 · Bases cargadas: lo reservado del origen y el motivo base_cargada y del capital vacío vive en UNA definición.
  -- Sin exención para sesiones sin usuario: el importador corre sin usuario y valida el origen solo por la tabla.
  if new.origen = 'base_cargada' and not v_valvula then
    if tg_op = 'INSERT' then
      raise exception 'El origen base_cargada solo lo pone la carga de bases' using errcode = '42501';
    elsif old.origen is distinct from 'base_cargada' then
      raise exception 'El origen base_cargada solo lo pone la carga de bases' using errcode = '42501';
    end if;
  end if;
  if new.motivo_descarte = 'base_cargada' and not v_valvula then
    if tg_op = 'INSERT' then
      raise exception 'El motivo base_cargada solo lo pone la carga de bases' using errcode = '42501';
    elsif old.motivo_descarte is distinct from 'base_cargada' then
      raise exception 'El motivo base_cargada solo lo pone la carga de bases' using errcode = '42501';
    end if;
  end if;
  -- auditor-rls r1 (P3): un dormido no se «despierta» cambiándole el motivo mientras sigue descartado (p. ej. a
  -- datos_invalidos, 0 días de enfriamiento → «libre» 24 h → duplicado, contra E2). Sale del motivo base_cargada solo
  -- saliendo del descarte (reactivar, con capital) o con la válvula.
  if tg_op = 'UPDATE' and not v_valvula and old.motivo_descarte = 'base_cargada'
     and new.etapa = 'descartado' and new.motivo_descarte is distinct from 'base_cargada' then
    raise exception 'El motivo base_cargada de un contacto dormido solo lo cambia la carga de bases' using errcode = '42501';
  end if;
  -- El capital vacío solo nace con el lead (E8): uno que existe no se vacía, ni con la válvula. (Salir del descarte sin
  -- capital lo rechaza el CHECK leads_monto_estimado_valido: no se repite aquí.) El detail lleva el nombre del CHECK para
  -- que el front muestre su mensaje de capital (app/src/data/crm-api.ts:2033 y 2055-2059; auditor-rls r1, P3).
  if tg_op = 'UPDATE' and new.monto_estimado is null then
    if old.monto_estimado is not null then
      raise exception 'El capital del lead no se puede vaciar'
        using errcode = '23514', detail = 'leads_monto_estimado_valido';
    end if;
  end if;
  return new;
end;
$function$;

-- private.leads_before_insert: el texto vivo de 20260928192822 con UN cambio: 'base_cargada' en la lista de orígenes (la
-- reserva a la carga de bases la hace private.trg_leads_base_cargada_solo_puerta). Firma, DEFINER, search_path, dueño y ACL
-- iguales (el postflight lo comprueba).
create or replace function private.leads_before_insert()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'crm', 'public'
as $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.
  -- B7: base_cargada solo con la valvula de la carga de bases (trg_leads_000_base_cargada_solo_puerta).
  if new.origen is null or new.origen not in ('referido','landing','formulario','oficina','web','campania','whatsapp','base_cargada') then
    raise exception using errcode = '22023', message = 'Selecciona un canal concreto: Landing, Formulario, Referido o Walking';
  end if;
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
$function$;

create trigger trg_bases_carga_touch before update on crm.bases_carga
  for each row execute function private.set_actualizado_en_crm();
create trigger trg_audit_bases_carga after insert or update or delete on crm.bases_carga
  for each row execute function private.log_audit_crm();
create trigger trg_base_carga_leads_touch before update on crm.base_carga_leads
  for each row execute function private.set_actualizado_en_crm();
create trigger trg_audit_base_carga_leads after insert or update or delete on crm.base_carga_leads
  for each row execute function private.log_audit_crm();
create trigger base_carga_operaciones_inmutable before update or delete on crm.base_carga_operaciones
  for each row execute function private.bases_carga_operacion_inmutable();
create trigger base_carga_operaciones_no_truncate before truncate on crm.base_carga_operaciones
  for each statement execute function private.bases_carga_operacion_inmutable();
create trigger trg_audit_base_carga_operaciones after insert or update or delete on crm.base_carga_operaciones
  for each row execute function private.log_audit_crm();
create trigger trg_leads_000_base_cargada_solo_puerta before insert or update on crm.leads
  for each row execute function private.trg_leads_base_cargada_solo_puerta();

-- ── 4 · crm.leads y la política de enfriamiento (un solo ALTER por tabla: una sola pasada de validación) ────────────────
alter table crm.leads
  drop constraint leads_origen_check,
  add constraint leads_origen_check check ((origen = any (array['referido'::text, 'landing'::text, 'formulario'::text, 'oficina'::text, 'otro'::text, 'web'::text, 'campania'::text, 'whatsapp'::text, 'base_cargada'::text]))),
  drop constraint leads_motivo_descarte_check,
  add constraint leads_motivo_descarte_check check ((motivo_descarte = any (array['sin_interes'::text, 'sin_fondos'::text, 'competencia'::text, 'no_responde'::text, 'datos_invalidos'::text, 'pide_credito'::text, 'otro'::text, 'base_cargada'::text]))),
  drop constraint leads_monto_estimado_valido,
  add constraint leads_monto_estimado_valido check (
    (monto_estimado is null and origen = 'base_cargada'::text and etapa = 'descartado'::text)
    or (monto_estimado is not null and monto_estimado > (0)::numeric and monto_estimado <= 9999999999.99
        and monto_estimado = trunc(monto_estimado, 2))),
  alter column monto_estimado drop not null;

alter table crm.enfriamiento_politica
  drop constraint enfriamiento_politica_motivo_check,
  add constraint enfriamiento_politica_motivo_check check ((motivo = any (array['sin_interes'::text, 'sin_fondos'::text, 'competencia'::text, 'no_responde'::text, 'datos_invalidos'::text, 'pide_credito'::text, 'otro'::text, 'base_cargada'::text])));

-- Fila de configuración (no es DML de prueba): 30 días, ver ENFRIAMIENTO en la cabecera.
insert into crm.enfriamiento_politica (motivo, dias) values ('base_cargada', 30);

-- ── 5 · Dueños y permisos (sin grants para la API) ─────────────────────────────────────────────────────────────────────
alter table crm.bases_carga owner to postgres;
alter table crm.base_carga_leads owner to postgres;
alter table crm.base_carga_operaciones owner to postgres;
alter function private.bases_carga_operacion_inmutable() owner to postgres;
alter function private.trg_leads_base_cargada_solo_puerta() owner to postgres;

revoke all on crm.bases_carga, crm.base_carga_leads, crm.base_carga_operaciones from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_operacion_inmutable() from public, anon, authenticated, service_role;
revoke all on function private.trg_leads_base_cargada_solo_puerta() from public, anon, authenticated, service_role;
-- private.leads_before_insert conserva su ACL ({postgres=X/postgres}): CREATE OR REPLACE no la cambia.

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on table crm.bases_carga is
'Bases cargadas (B7, 04/10/2026): una base antigua que un supervisor carga desde un archivo o arma con leads del CRM, para repartirla a sus analistas y seguir si se trabaja. Sin grants para la API: solo las puertas DEFINER de B8–B10 la escriben y la leen. Sin DELETE (soft-delete con activo).';
comment on column crm.bases_carga.id is 'Identificador de la base.';
comment on column crm.bases_carga.nombre is 'Nombre visible de la base (p. ej. «Feria 2025»): 1 a 80 caracteres, sin espacios al borde; único por supervisor entre las bases vivas, sin distinguir mayúsculas.';
comment on column crm.bases_carga.origen is 'De dónde salió: archivo (Excel/CSV subido) o crm (armada con descartados elegibles del CRM, E12).';
comment on column crm.bases_carga.supervisor_id is 'Supervisor dueño de la base: sus contactos quedan en su bandeja y él la reparte a su equipo (E4). Si la carga Gerencia, elige este supervisor (E11).';
comment on column crm.bases_carga.creada_por is 'Perfil que creó la base (el supervisor o alguien de Gerencia).';
comment on column crm.bases_carga.operacion_id is 'Id de la operación que creó la base (idempotencia: un doble clic no crea dos). Único.';
comment on column crm.bases_carga.archivo_nombre is 'Nombre del archivo subido (1 a 255 caracteres); obligatorio con origen archivo y vacío con origen crm.';
comment on column crm.bases_carga.filas_recibidas is 'Informe: filas recibidas del archivo (o candidatos evaluados al armar). Entero ≥ 0.';
comment on column crm.bases_carga.cargadas is 'Informe: filas que quedaron como lead de la base. Entero ≥ 0.';
comment on column crm.bases_carga.ya_existian is 'Informe: filas saltadas porque el contacto ya existía (mismo teléfono o DNI: de otro analista o ya cliente, E2). Entero ≥ 0.';
comment on column crm.bases_carga.no_contactar is 'Informe: filas saltadas porque la persona tiene «No contactar» (E2). Entero ≥ 0.';
comment on column crm.bases_carga.invalidas is 'Informe: filas sin nombre o sin teléfono válido (E5). Entero ≥ 0.';
comment on column crm.bases_carga.repetidas is 'Informe: filas repetidas dentro del mismo archivo. Entero ≥ 0. La suma de cargadas, ya_existian, no_contactar, invalidas y repetidas no pasa de filas_recibidas.';
comment on column crm.bases_carga.activo is 'Soft-delete: false = base retirada. Al retirarla, su puerta debe retirar también sus filas de crm.base_carga_leads (el lead queda libre para otra base).';
comment on column crm.bases_carga.creado_en is 'Cuándo se creó la base.';
comment on column crm.bases_carga.actualizado_en is 'Último cambio de la fila (totales, retiro).';

comment on table crm.base_carga_leads is
'Bases cargadas (B7): qué lead está en qué base y a quién se repartió. Un lead una sola vez por base y en UNA sola base viva a la vez (índice único parcial sobre lead_id con activo). Sin grants para la API; sin DELETE (soft-delete con activo).';
comment on column crm.base_carga_leads.id is 'Identificador de la fila.';
comment on column crm.base_carga_leads.base_id is 'Base a la que pertenece el lead.';
comment on column crm.base_carga_leads.lead_id is 'Lead de la base. Solo puede estar en una base viva a la vez.';
comment on column crm.base_carga_leads.procedencia is 'Cómo entró a la base: archivo (contacto nuevo creado desde el archivo, origen base_cargada) o crm (lead que ya existía, armado desde el CRM).';
comment on column crm.base_carga_leads.analista_id is 'Analista al que se repartió; NULL = sin repartir. Va junto con asignado_en y asignado_por (los tres NULL o los tres con valor).';
comment on column crm.base_carga_leads.asignado_en is 'Cuándo se repartió al analista; NULL = sin repartir.';
comment on column crm.base_carga_leads.asignado_por is 'Quién repartió (supervisor o Gerencia); NULL = sin repartir.';
comment on column crm.base_carga_leads.agregado_por is 'Perfil que agregó el lead a la base (quien cargó o armó).';
comment on column crm.base_carga_leads.activo is 'Soft-delete: false = el lead salió de la base (y puede entrar a otra).';
comment on column crm.base_carga_leads.creado_en is 'Cuándo entró el lead a la base.';
comment on column crm.base_carga_leads.actualizado_en is 'Último cambio de la fila (reparto, recogida, retiro).';

comment on table crm.base_carga_operaciones is
'Bases cargadas (B7): recibos INMUTABLES de cada operación de las puertas (crear, cargar_lote, armar, repartir, recoger), para la idempotencia (único por actor e id de operación) y el rastro (el cambio de analista de un descartado no escribe en lead_asignaciones). Solo INSERT; UPDATE, DELETE y TRUNCATE se rechazan. Sin grants para la API.';
comment on column crm.base_carga_operaciones.id is 'Identificador del recibo.';
comment on column crm.base_carga_operaciones.actor is 'Perfil que hizo la operación.';
comment on column crm.base_carga_operaciones.operacion_id is 'Id de operación que manda la pantalla; con el actor, único: repetirlo devuelve el mismo recibo.';
comment on column crm.base_carga_operaciones.base_id is 'Base sobre la que se operó.';
comment on column crm.base_carga_operaciones.tipo is 'Operación: crear, cargar_lote, armar, repartir o recoger.';
comment on column crm.base_carga_operaciones.pedido_md5 is 'md5 (32 hexadecimales en minúscula) del pedido normalizado: el mismo id con otro pedido se rechaza.';
comment on column crm.base_carga_operaciones.respuesta is 'Respuesta devuelta (objeto JSON de hasta 64 KB) SIN datos personales: conteos, ids y motivos; nunca nombres, teléfonos ni DNI.';
comment on column crm.base_carga_operaciones.creado_en is 'Momento de la operación.';

comment on policy bases_carga_select on crm.bases_carga is
'Segundo candado (no hay grants): Supervisión ve las bases cuyo supervisor dueño está en su subárbol (las suyas y las de su equipo); Gerencia ve todas; el analista y cualquier otro rol, nada (lee su base por la puerta DEFINER de B10).';
comment on policy base_carga_leads_select on crm.base_carga_leads is
'Segundo candado (no hay grants): ve las filas quien ve la base (exists sobre crm.bases_carga, cuya RLS decide).';
comment on policy base_carga_operaciones_select on crm.base_carga_operaciones is
'Segundo candado (no hay grants): ve los recibos quien ve la base (exists sobre crm.bases_carga, cuya RLS decide).';

comment on function private.bases_carga_operacion_inmutable() is
'Disparador que vuelve inmutable crm.base_carga_operaciones (UPDATE, DELETE y TRUNCATE → P0409). Sin EXECUTE para la API.';
comment on function private.trg_leads_base_cargada_solo_puerta() is
'Bases cargadas (B7, 04/10/2026): sello de crm.leads para los valores nuevos. Sin la válvula de transacción crm.op_bases_carga = on (la encenderá solo el núcleo de la carga de bases, B8): nacer o pasar a origen base_cargada → 42501; nacer o pasar a motivo_descarte base_cargada → 42501; cambiar el motivo base_cargada de un lead que sigue descartado → 42501 (no se «despierta» un dormido por el motivo). Siempre (también con la válvula): un capital que existe no se vacía → 23514 (detail leads_monto_estimado_valido, para el mensaje del front). Que un lead sin capital no salga del descarte lo impone el CHECK leads_monto_estimado_valido (E8), no este sello. Sin exención para sesiones sin usuario (el importador corre sin usuario). INVOKER, search_path vacío, sin EXECUTE para la API.';
comment on function private.leads_before_insert() is
'Alta de un lead (BEFORE INSERT): exige un canal concreto (sin nuevos Otro; base_cargada solo con la válvula de la carga de bases, B7 04/10/2026, la reserva vive en private.trg_leads_base_cargada_solo_puerta) y, sin crm.op_privilegiada, impide nacer en estado terminal y enlazar perfil, contrato o conversión. DEFINER, search_path crm, public.';
comment on trigger trg_leads_000_base_cargada_solo_puerta on crm.leads is
'Bases cargadas (B7): origen y motivo base_cargada solo con la válvula crm.op_bases_carga (entrar y, mientras siga descartado, salir del motivo); un capital que existe no se vacía. Ver private.trg_leads_base_cargada_solo_puerta.';
comment on trigger base_carga_operaciones_inmutable on crm.base_carga_operaciones is
'Los recibos de las bases cargadas no se cambian ni se borran (P0409).';
comment on trigger base_carga_operaciones_no_truncate on crm.base_carga_operaciones is
'Los recibos de las bases cargadas no se vacían con TRUNCATE (P0409).';

comment on column crm.leads.monto_estimado is
'Capital que el lead estima invertir: mayor que 0, máximo 9999999999.99 y hasta 2 decimales; clasificado siempre junto con moneda. Obligatorio, salvo en un contacto de base cargada DORMIDO (origen base_cargada y etapa descartado, B7 04/10/2026, E8): si su archivo no traía capital nace sin él y no sale del descarte sin capital por ninguna vía (CHECK leads_monto_estimado_valido; se pide al reactivar). Un capital que existe no se vacía (trg_leads_000_base_cargada_solo_puerta).';
comment on constraint leads_origen_check on crm.leads is
'Canales del lead. base_cargada (B7): contacto creado desde el archivo de una base cargada; solo lo pone la carga de bases (trg_leads_000_base_cargada_solo_puerta).';
comment on constraint leads_motivo_descarte_check on crm.leads is
'Motivos de descarte. base_cargada (B7): contacto de base cargada que nace «dormido» en la bandeja del supervisor (E7); solo lo pone la carga de bases (trg_leads_000_base_cargada_solo_puerta), nadie lo elige al descartar.';
comment on constraint leads_monto_estimado_valido on crm.leads is
'Capital válido (mayor que 0, máximo 9999999999.99, hasta 2 decimales) o vacío SOLO en un contacto de base cargada dormido: origen base_cargada y etapa descartado (B7, E8). Toda vía que lo saque del descarte sin capital falla aquí con 23514. La rama válida exige monto_estimado is not null: sin ella un NULL pasaría el CHECK en cualquier origen y etapa.';
comment on constraint enfriamiento_politica_motivo_check on crm.enfriamiento_politica is
'Motivos con política de enfriamiento: los mismos de leads_motivo_descarte_check (base_cargada desde B7, 30 días).';

-- ── 7 · Postflight (SOLO catálogo) ─────────────────────────────────────────────────────────────────────────────────────
-- El censo después, UNA sola llamada (era la parte más cara del tiempo con candados: tres llamadas, ~0,2 s).
create temp table _b7_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
do $postflight$
declare
  v_tablas regclass[] := array['crm.bases_carga'::regclass, 'crm.base_carga_leads'::regclass, 'crm.base_carga_operaciones'::regclass];
  v_policies text;
  v_disparadores text;
  v_indices text;
begin
  -- Tablas: dueño postgres, RLS activa, ACL solo de postgres y cero permisos efectivos para la API (herencia incluida).
  if (
    (select count(*) from pg_class c
      where c.oid = any (v_tablas) and c.relowner = 'postgres'::regrole and c.relrowsecurity and c.relacl is not null) = 3
    and not exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = any (v_tablas) and a.grantee <> 'postgres'::regrole)
    and not exists (
      select 1
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol),
           unnest(v_tablas) t(tabla),
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) x(priv)
      where has_table_privilege(r.rol, t.tabla::oid, x.priv))
    -- Comentario en cada tabla y en cada columna.
    and not exists (select 1 from unnest(v_tablas) t(tabla) where obj_description(t.tabla, 'pg_class') is null)
    and not exists (select 1 from pg_attribute a where a.attrelid = any (v_tablas) and a.attnum > 0 and not a.attisdropped
                     and col_description(a.attrelid, a.attnum) is null)
  ) is not true then
    raise exception 'POSTFLIGHT B7: dueño, RLS, ACL, permisos efectivos o comentarios de las tablas nuevas no son los previstos';
  end if;

  -- Policies exactas: una SELECT por tabla, para authenticated, sin WITH CHECK.
  select string_agg(pp.tablename || '|' || pp.policyname || '|' || pp.cmd || '|' || pp.permissive || '|' || pp.roles::text || '|'
                    || regexp_replace(coalesce(pp.qual, ''), '\s+', ' ', 'g') || '|' || coalesce(pp.with_check, ''),
                    ' ## ' order by pp.tablename)
    into v_policies
  from pg_policies pp
  where pp.schemaname = 'crm' and pp.tablename in ('bases_carga', 'base_carga_leads', 'base_carga_operaciones');
  if (v_policies =
        'base_carga_leads|base_carga_leads_select|SELECT|PERMISSIVE|{authenticated}|(EXISTS ( SELECT 1 FROM crm.bases_carga b WHERE (b.id = base_carga_leads.base_id)))|'
     || ' ## base_carga_operaciones|base_carga_operaciones_select|SELECT|PERMISSIVE|{authenticated}|(EXISTS ( SELECT 1 FROM crm.bases_carga b WHERE (b.id = base_carga_operaciones.base_id)))|'
     || ' ## bases_carga|bases_carga_select|SELECT|PERMISSIVE|{authenticated}|((( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = ANY (ARRAY[''supervisor''::text, ''gerencia''::text])) AND (supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)))|'
  ) is not true then
    raise exception 'POSTFLIGHT B7: policies inesperadas: %', coalesce(v_policies, '(ninguna)');
  end if;

  -- Disparadores exactos de las tablas nuevas y el sello de crm.leads, todos habilitados ('O').
  select string_agg(pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']', ' ## ' order by t.tgname)
    into v_disparadores
  from pg_trigger t
  where not t.tgisinternal
    and (t.tgrelid = any (v_tablas)
         or (t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_base_cargada_solo_puerta'));
  if (v_disparadores =
        'CREATE TRIGGER base_carga_operaciones_inmutable BEFORE DELETE OR UPDATE ON crm.base_carga_operaciones FOR EACH ROW EXECUTE FUNCTION private.bases_carga_operacion_inmutable() [O]'
     || ' ## CREATE TRIGGER base_carga_operaciones_no_truncate BEFORE TRUNCATE ON crm.base_carga_operaciones FOR EACH STATEMENT EXECUTE FUNCTION private.bases_carga_operacion_inmutable() [O]'
     || ' ## CREATE TRIGGER trg_audit_base_carga_leads AFTER INSERT OR DELETE OR UPDATE ON crm.base_carga_leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_audit_base_carga_operaciones AFTER INSERT OR DELETE OR UPDATE ON crm.base_carga_operaciones FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_audit_bases_carga AFTER INSERT OR DELETE OR UPDATE ON crm.bases_carga FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_base_carga_leads_touch BEFORE UPDATE ON crm.base_carga_leads FOR EACH ROW EXECUTE FUNCTION private.set_actualizado_en_crm() [O]'
     || ' ## CREATE TRIGGER trg_bases_carga_touch BEFORE UPDATE ON crm.bases_carga FOR EACH ROW EXECUTE FUNCTION private.set_actualizado_en_crm() [O]'
     || ' ## CREATE TRIGGER trg_leads_000_base_cargada_solo_puerta BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_base_cargada_solo_puerta() [O]'
  ) is not true then
    raise exception 'POSTFLIGHT B7: disparadores inesperados: %', coalesce(v_disparadores, '(ninguno)');
  end if;

  -- Índices exactos de las tablas nuevas (unicidades de negocio incluidas).
  select string_agg(pg_get_indexdef(i.indexrelid), ' ## ' order by pg_get_indexdef(i.indexrelid))
    into v_indices
  from pg_index i where i.indrelid = any (v_tablas);
  if (select count(*) from pg_index i where i.indrelid = any (v_tablas)) <> 15
     or v_indices not like '%CREATE UNIQUE INDEX bases_carga_nombre_vivo_unico ON crm.bases_carga USING btree (supervisor_id, lower(nombre)) WHERE activo%'
     or v_indices not like '%CREATE UNIQUE INDEX base_carga_leads_lead_vivo_unico ON crm.base_carga_leads USING btree (lead_id) WHERE activo%'
     or v_indices not like '%CREATE UNIQUE INDEX base_carga_leads_base_lead_unico ON crm.base_carga_leads USING btree (base_id, lead_id)%'
     or v_indices not like '%CREATE UNIQUE INDEX base_carga_operaciones_actor_operacion_unica ON crm.base_carga_operaciones USING btree (actor, operacion_id)%'
     or v_indices not like '%CREATE UNIQUE INDEX bases_carga_operacion_unica ON crm.bases_carga USING btree (operacion_id)%'
     or v_indices is null then
    raise exception 'POSTFLIGHT B7: indices inesperados: %', coalesce(v_indices, '(ninguno)');
  end if;

  -- crm.leads: los tres CHECK nuevos EXACTOS y validados, monto_estimado sin NOT NULL; enfriamiento con su CHECK y su fila.
  if (
    (select pg_get_constraintdef(c.oid) = 'CHECK ((origen = ANY (ARRAY[''referido''::text, ''landing''::text, ''formulario''::text, ''oficina''::text, ''otro''::text, ''web''::text, ''campania''::text, ''whatsapp''::text, ''base_cargada''::text])))'
            and c.convalidated and obj_description(c.oid, 'pg_constraint') is not null
       from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_origen_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((motivo_descarte = ANY (ARRAY[''sin_interes''::text, ''sin_fondos''::text, ''competencia''::text, ''no_responde''::text, ''datos_invalidos''::text, ''pide_credito''::text, ''otro''::text, ''base_cargada''::text])))'
            and c.convalidated and obj_description(c.oid, 'pg_constraint') is not null
       from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_motivo_descarte_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((((monto_estimado IS NULL) AND (origen = ''base_cargada''::text) AND (etapa = ''descartado''::text)) OR ((monto_estimado IS NOT NULL) AND (monto_estimado > (0)::numeric) AND (monto_estimado <= 9999999999.99) AND (monto_estimado = trunc(monto_estimado, 2)))))'
            and c.convalidated and obj_description(c.oid, 'pg_constraint') is not null
       from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_monto_estimado_valido')
    and (select count(*) = 1 from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname like 'leads\_monto%')
    and (select not a.attnotnull and a.atttypid = 'numeric'::regtype and a.atttypmod = -1
                and col_description(a.attrelid, a.attnum) like 'Capital que el lead estima invertir%B7%'
           from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname = 'monto_estimado')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((motivo = ANY (ARRAY[''sin_interes''::text, ''sin_fondos''::text, ''competencia''::text, ''no_responde''::text, ''datos_invalidos''::text, ''pide_credito''::text, ''otro''::text, ''base_cargada''::text])))'
            and c.convalidated
       from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass and c.conname = 'enfriamiento_politica_motivo_check')
    and (select ep.dias = 30 and ep.actualizado_por is null from crm.enfriamiento_politica ep where ep.motivo = 'base_cargada')
    and (select count(*) from crm.enfriamiento_politica) = 8
  ) is not true then
    raise exception 'POSTFLIGHT B7: los CHECK de crm.leads, el NOT NULL de monto_estimado o la politica de enfriamiento no quedaron como se ensayaron';
  end if;

  -- Funciones: el sello y el inmutable con el cuerpo ensayado, INVOKER, dueño postgres, search_path vacío, ACL solo postgres
  -- y comentario; leads_before_insert con el cuerpo ensayado y la MISMA identidad (DEFINER, search_path crm, public, dueño,
  -- ACL). Ninguna entra al censo, y el censo es el de la foto.
  if (
    (select md5(p.prosrc) = '2e095d8962828551f29b0a1458a2a585'
            and not p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole and p.prorettype = 'trigger'::regtype
            and p.proconfig = array['search_path=""']::text[] and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
            and obj_description(p.oid, 'pg_proc') like 'Bases cargadas (B7%'
       from pg_proc p where p.oid = to_regprocedure('private.trg_leads_base_cargada_solo_puerta()'))
    and (select md5(p.prosrc) = '7a71be95d06e6b5abff6f4c155f18865'
            and not p.prosecdef and p.proowner = 'postgres'::regrole and p.prorettype = 'trigger'::regtype
            and p.proconfig = array['search_path=""']::text[] and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
            and obj_description(p.oid, 'pg_proc') is not null
       from pg_proc p where p.oid = to_regprocedure('private.bases_carga_operacion_inmutable()'))
    and (select md5(p.prosrc) = 'de4823aebce64646271689a5d78db18b'
            and p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole
            and p.proconfig = array['search_path=crm, public']::text[] and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
            and obj_description(p.oid, 'pg_proc') like 'Alta de un lead%B7%'
       from pg_proc p where p.oid = to_regprocedure('private.leads_before_insert()'))
    and (select count(*) = 1 from pg_trigger t
          where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_base_cargada_solo_puerta'
            and t.tgfoid = to_regprocedure('private.trg_leads_base_cargada_solo_puerta()')
            and t.tgenabled = 'O' and t.tgtype = 23 and t.tgqual is null and t.tgattr = ''::int2vector
            and obj_description(t.oid, 'pg_trigger') like 'Bases cargadas (B7)%')
    and not exists (select 1 from pg_temp._b7_censo_despues c
                     where c.objeto in (to_regprocedure('private.trg_leads_base_cargada_solo_puerta()')::text,
                                        to_regprocedure('private.bases_carga_operacion_inmutable()')::text,
                                        to_regprocedure('private.leads_before_insert()')::text))
    and not exists (select 1 from pg_temp._b7_censo_despues c where c.objeto not in (select a.objeto from pg_temp._b7_censo_antes a))
    and (select count(*) from pg_temp._b7_censo_antes) = (select count(*) from pg_temp._b7_censo_despues)
  ) is not true then
    raise exception 'POSTFLIGHT B7: el sello, el inmutable, leads_before_insert, el trigger del sello o el censo no quedaron como se ensayaron';
  end if;

  -- Aviso honesto: aquí solo se acredita el CATÁLOGO (sin DML con los candados puestos). El comportamiento se prueba después
  -- con supabase/scripts/base-gestion/b7-esquema.sql (banco local) o b7-comprobar-tras-aplicar.sql (rama/producción).
  raise notice 'B7 CATALOGO OK: 3 tablas (RLS, sin grants API, policies, indices, comentarios), recibos inmutables, sello en crm.leads, CHECK de origen/motivo/capital validados, enfriamiento base_cargada 30, censo igual. COMPORTAMIENTO NO PROBADO en esta migracion.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
