-- ============================================================================
-- P-055 · MULTIEMPRESA F1 — Expandir el esquema (identidad, empresas, inversiones)
-- ============================================================================
--
-- QUE, en una linea: crea el ESQUELETO relacional de "una persona, varias
-- inversiones, varias empresas" — TODO aditivo, nullable y APAGADO. No cambia
-- ni una lectura ni una escritura de produccion: ninguna puerta viva llama aun
-- a nada de esto (eso es F3). No toca public.* salvo FKs de lectura a perfiles
-- (patron de la casa). No crea Auth, ni Portal, ni segunda calculadora de Capital.
--
-- POR QUE. Hoy la "persona" se escribe por cuatro caminos que no se conocen
-- entre si (alta/toma de lead, conversion Avance, conversion cooperativa, alta
-- de colaborador) y un lead solo admite UNA inversion externa (UNIQUE(lead_id)).
-- F1 pone el ancla de identidad y el registro relacional de inversiones para que
-- F2 (backfill) y F3 (puertas canonicas) tengan donde enganchar sin duplicar.
--
-- QUE TRAE (todo en el esquema crm; helpers en private):
--   1. crm.empresas                      — catalogo ampliable (avance/qorilazo/prodelco)
--   2. crm.inversionistas                — ancla estable de la persona
--   3. crm.inversionista_identificadores — DNI/CE/PASAPORTE, vigente/historico
--   4. crm.inversionista_leads           — puente lead canonico + historicos
--   5. crm.inversionista_responsables    — ledger de responsable de relacion
--   6. crm.inversionista_fusiones        — libro append-only de fusiones
--   7. crm.inversiones                   — REGISTRO RELACIONAL (no fuente de dinero)
--   8. crm.inversion_titulares           — titular principal + cotitulares
--   9. crm.multiempresa_idempotencia     — clave+tipo+version+hash+resultado
--  10. crm.multiempresa_flags            — banderas de rollout, TODAS apagadas
--   + enlaces nullable: crm.leads.inversionista_id, crm.cierres_externos.inversionista_id
--   + primitiva private.inversionista_resolver(tipo, documento) SIN EXECUTE a la API
--   + candados de coherencia (fuente<->empresa, titular principal, fusiones
--     append-only sin ciclos) y proteccion de crm.leads.inversionista_id ante
--     escritura directa por la Data API (revision de Codex).
--
-- SEGURIDAD (contrato §14): RLS activa en todas; CERO grants a la Data API
-- (anon/authenticated/service_role) — el acceso sera por RPC definer en fases
-- siguientes; el documento NO viaja en claro a logs: la tabla de identificadores
-- usa el auditor ENMASCARADO (private.log_audit_sin_secretos), el resto usa
-- private.log_audit_crm; ambos escriben en public.audit_log.
--
-- REVERSA: scripts/rollback-f1-multiempresa.sql (drop en orden inverso). Como
-- todo es aditivo y apagado, revertir no toca ningun dato vivo.
--
-- GATE G1: esquema reconstruible, reversible y seguro. El gate de comportamiento
-- (dos altas simultaneas del mismo documento -> UNA identidad; capital identico;
-- cero fusiones ambiguas) se prueba con el oraculo de concurrencia del resolver.

begin;

set local lock_timeout = '5s';

-- Exclusion con cualquier otro despliegue en curso sobre estas piezas.
select pg_advisory_xact_lock(hashtext('crm_f1_multiempresa'));

-- ── 0. Guardas de dependencias ───────────────────────────────────────────────
do $guard$
begin
  if to_regclass('public.perfiles') is null
     or to_regclass('crm.leads') is null
     or to_regclass('crm.cierres_externos') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.log_audit_crm()') is null
     or to_regprocedure('private.log_audit_sin_secretos()') is null
     or to_regprocedure('private.set_actualizado_en_crm()') is null
     or to_regprocedure('private.es_gerencia_crm_activa()') is null then
    raise exception 'F1: faltan dependencias de base (perfiles/leads/cierres/helpers/auditores)';
  end if;
  -- Idempotencia del propio despliegue: si ya existe el ancla, no re-crear.
  if to_regclass('crm.inversionistas') is not null then
    raise exception 'F1: crm.inversionistas ya existe — esta migracion ya se aplico';
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.empresas — catalogo ampliable de empresas de inversion
-- ============================================================================
create table crm.empresas (
  id uuid primary key default gen_random_uuid(),
  -- Clave estable de negocio (contrato §10: "las claves son estables").
  clave text not null unique
    check (clave collate "C" ~ '^[a-z][a-z0-9_]{1,30}$'),
  nombre_legal   text not null check (length(btrim(nombre_legal))  between 2 and 200),
  nombre_visible text not null check (length(btrim(nombre_visible)) between 2 and 120),
  activa boolean not null default true,
  -- Monedas permitidas (decision F0: cooperativas solo PEN; Avance PEN+USD).
  monedas text[] not null default array['PEN']
    check (cardinality(monedas) between 1 and 5
           and monedas <@ array['PEN','USD']
           and array_ndims(monedas) = 1),
  -- Reglas de la empresa (decisiones F0), como banderas explicitas.
  crea_contrato_avance boolean not null default false, -- solo Avance
  requiere_portal      boolean not null default false, -- solo Avance
  exige_numero_transaccion boolean not null default false, -- cooperativas
  -- Fuente economica que consume Capital para esta empresa:
  --   'contratos'        -> public.contratos (Avance)
  --   'cierres_externos' -> crm.cierres_externos (cooperativas)
  fuente_capital text not null
    check (fuente_capital in ('contratos','cierres_externos')),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  actualizado_en timestamptz not null default now() check (isfinite(actualizado_en)),
  creado_por uuid references public.perfiles(id),
  -- Coherencia estructural (no re-litiga decisiones): solo una empresa cuya
  -- fuente es 'contratos' (Avance) puede crear contrato o exigir Portal.
  constraint empresas_contrato_implica_fuente check (not crea_contrato_avance or fuente_capital = 'contratos'),
  constraint empresas_portal_implica_fuente   check (not requiere_portal      or fuente_capital = 'contratos')
);

comment on table crm.empresas is
  'F1 multiempresa: catalogo ampliable de empresas de inversion. Claves estables (avance/qorilazo/prodelco); una cuarta empresa se agrega con una fila, no con codigo. monedas/reglas por empresa reflejan las decisiones de F0 (cooperativas solo PEN, solo Avance crea contrato y Portal). fuente_capital dice de que tabla lee Capital para esta empresa; NO nace una segunda calculadora. Sin grants a la Data API.';
comment on column crm.empresas.fuente_capital is
  'De donde lee Capital esta empresa: contratos (Avance) o cierres_externos (cooperativas). Dimension para el nucleo, no una suma nueva.';

-- Semilla: las TRES empresas aprobadas. Idempotente por la unique de clave.
insert into crm.empresas (clave, nombre_legal, nombre_visible, activa, monedas,
                          crea_contrato_avance, requiere_portal, exige_numero_transaccion, fuente_capital)
values
  ('avance',   'Avance Corp',      'Avance Corp',      true, array['PEN','USD'], true,  true,  false, 'contratos'),
  ('qorilazo', 'COOPAC Qorilazo',  'COOPAC Qorilazo',  true, array['PEN'],       false, false, true,  'cierres_externos'),
  ('prodelco', 'COOPAC Prodelco',  'COOPAC Prodelco',  true, array['PEN'],       false, false, true,  'cierres_externos');

-- ============================================================================
-- 2. crm.inversionistas — el ancla estable de la persona
-- ============================================================================
-- NO es un duplicado del perfil ni del lead: no guarda nombre/telefono/correo
-- como cuarta copia maestra (contrato §4.1). El contacto se PROYECTA desde
-- fuentes vigentes en la ficha (F5), con procedencia.
create table crm.inversionistas (
  id uuid primary key default gen_random_uuid(),
  estado text not null default 'activo'
    check (estado in ('activo','fusionado','bloqueado')),
  -- Enlace OPCIONAL y UNICO al perfil Portal/Auth (Avance). El vinculo vive
  -- AQUI, no se agrega columna al Portal (contrato §3).
  perfil_id uuid references public.perfiles(id),
  -- Responsable de relacion vigente: opcional en backfill, obligatorio para
  -- operar comercialmente (se valida en las puertas de F3, no aqui).
  responsable_relacion_id uuid references public.perfiles(id),
  -- no_contactar global de la persona, con su auditoria de activacion.
  no_contactar boolean not null default false,
  no_contactar_en  timestamptz check (no_contactar_en is null or isfinite(no_contactar_en)),
  no_contactar_por uuid references public.perfiles(id),
  -- Fusion: la perdedora apunta a la canonica y se marca; NUNCA se borra.
  inversionista_canonico_id uuid references crm.inversionistas(id),
  fusionado_en timestamptz check (fusionado_en is null or isfinite(fusionado_en)),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  actualizado_en timestamptz not null default now() check (isfinite(actualizado_en)),
  creado_por uuid references public.perfiles(id),
  -- Coherencia de la maquina de estados de fusion.
  constraint inversionistas_fusion_coherente check (
    (estado = 'fusionado') = (inversionista_canonico_id is not null and fusionado_en is not null)
  ),
  -- Una identidad no puede ser su propia canonica.
  constraint inversionistas_no_autofusion check (inversionista_canonico_id is distinct from id),
  -- no_contactar activado deja rastro de cuando.
  constraint inversionistas_nocontactar_auditado check (
    (no_contactar = false) or (no_contactar_en is not null)
  )
);

comment on table crm.inversionistas is
  'F1 multiempresa: ancla estable de la persona (una fila por persona confirmada). NO duplica nombre/telefono/correo (el contacto se proyecta desde fuentes vigentes en la Ficha 360). perfil_id enlaza opcional y unicamente al Portal Avance SIN tocar public. Fusion append-only: la perdedora apunta a canonica y se marca fusionado, jamas se borra. RLS activa, sin grants a la Data API: acceso solo por RPC definer (F3+).';

-- perfil_id unico entre identidades no fusionadas (una identidad activa por perfil).
create unique index inversionistas_perfil_uidx
  on crm.inversionistas (perfil_id)
  where perfil_id is not null and estado <> 'fusionado';

create index inversionistas_responsable_idx on crm.inversionistas (responsable_relacion_id);
create index inversionistas_canonico_idx     on crm.inversionistas (inversionista_canonico_id);
create index inversionistas_estado_idx       on crm.inversionistas (estado);

-- ============================================================================
-- 3. crm.inversionista_identificadores — documentos fuertes
-- ============================================================================
create table crm.inversionista_identificadores (
  id uuid primary key default gen_random_uuid(),
  inversionista_id uuid not null references crm.inversionistas(id),
  tipo_documento text not null check (tipo_documento in ('DNI','CE','PASAPORTE')),
  -- Normalizado = mayusculas y solo alfanumerico (lo calcula el resolver).
  documento_normalizado text not null,
  -- El documento tal como se recibio (para mostrar), opcional.
  documento_original text,
  estado text not null default 'vigente' check (estado in ('vigente','historico')),
  verificado boolean not null default false,
  fuente text,  -- origen de la verificacion (portal, cierre, backfill, gerencia...)
  vigente_desde timestamptz not null default now() check (isfinite(vigente_desde)),
  vigente_hasta timestamptz check (vigente_hasta is null or isfinite(vigente_hasta)),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  creado_por uuid references public.perfiles(id),
  -- Formato del documento POR TIPO, alineado con crm.cierres_externos
  -- (20260812000259): DNI 8 digitos, CE 9-12 digitos, PASAPORTE 6-12 alfanum.
  -- Asi una identidad fuerte siempre puede representarse por un cierre valido.
  constraint identificador_documento_por_tipo check (
    (tipo_documento = 'DNI'       and documento_normalizado collate "C" ~ '^[0-9]{8}$')
    or (tipo_documento = 'CE'        and documento_normalizado collate "C" ~ '^[0-9]{9,12}$')
    or (tipo_documento = 'PASAPORTE' and documento_normalizado collate "C" ~ '^[A-Z0-9]{6,12}$')
  )
);

comment on table crm.inversionista_identificadores is
  'F1 multiempresa: documentos de la persona (DNI/CE/PASAPORTE). Solo un identificador VIGENTE, verificado y no fusionado resuelve identidad automaticamente. Corregir un documento marca el anterior como historico (no reescribe hechos). Telefono/correo/nombre NO son identificadores fuertes y NUNCA fusionan. El documento no viaja a logs genericos.';

-- UNICIDAD que arbitra las carreras del resolver (contrato §4.2): un documento
-- vigente pertenece a una sola persona. Los historicos no compiten.
create unique index inversionista_identificadores_vigente_uidx
  on crm.inversionista_identificadores (tipo_documento, documento_normalizado)
  where estado = 'vigente';

create index inversionista_identificadores_inv_idx
  on crm.inversionista_identificadores (inversionista_id);

-- ============================================================================
-- 4. Puente de leads, ledger de responsabilidad y libro de fusiones
-- ============================================================================
-- Puente: conserva el lead CANONICO y TODOS los historicos de la persona
-- (decision del handoff). El enlace vivo y rapido vive ademas en
-- crm.leads.inversionista_id (seccion 6); este puente es el historial.
create table crm.inversionista_leads (
  id uuid primary key default gen_random_uuid(),
  inversionista_id uuid not null references crm.inversionistas(id),
  lead_id uuid not null references crm.leads(id),
  rol text not null default 'canonico' check (rol in ('canonico','historico')),
  desde timestamptz not null default now() check (isfinite(desde)),
  hasta timestamptz check (hasta is null or isfinite(hasta)),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  creado_por uuid references public.perfiles(id)
);
comment on table crm.inversionista_leads is
  'F1 multiempresa: puente persona<->lead. Conserva el lead CANONICO (rol=canonico, uno por persona) y todos los leads historicos. La reinversion NUNCA crea otro lead: reutiliza el canonico. El enlace vivo esta ademas en crm.leads.inversionista_id.';
-- Un lead pertenece a una sola persona.
create unique index inversionista_leads_lead_uidx on crm.inversionista_leads (lead_id);
-- Un solo lead canonico por persona.
create unique index inversionista_leads_canonico_uidx
  on crm.inversionista_leads (inversionista_id) where rol = 'canonico';
create index inversionista_leads_inv_idx on crm.inversionista_leads (inversionista_id);

-- Ledger de responsable de relacion: un solo responsable ABIERTO por persona.
create table crm.inversionista_responsables (
  id uuid primary key default gen_random_uuid(),
  inversionista_id uuid not null references crm.inversionistas(id),
  responsable_id uuid not null references public.perfiles(id),
  desde timestamptz not null default now() check (isfinite(desde)),
  hasta timestamptz check (hasta is null or isfinite(hasta)),
  motivo text,
  por uuid references public.perfiles(id),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  constraint inv_responsables_rango check (hasta is null or hasta >= desde)
);
comment on table crm.inversionista_responsables is
  'F1 multiempresa: historial de responsable de relacion. Cambiar el responsable NO mueve atribuciones historicas de venta. Un solo tramo abierto (hasta is null) por persona.';
create unique index inv_responsables_abierto_uidx
  on crm.inversionista_responsables (inversionista_id) where hasta is null;
create index inv_responsables_inv_idx on crm.inversionista_responsables (inversionista_id);
create index inv_responsables_resp_idx on crm.inversionista_responsables (responsable_id);

-- Libro append-only de fusiones (contrato §4.4): exclusivo de Gerencia (F3),
-- con motivo, impacto y sin borrar la perdedora.
create table crm.inversionista_fusiones (
  id uuid primary key default gen_random_uuid(),
  canonico_id  uuid not null references crm.inversionistas(id),
  fusionado_id uuid not null references crm.inversionistas(id),
  motivo text not null check (length(btrim(motivo)) between 3 and 500),
  impacto jsonb,
  por uuid references public.perfiles(id),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  constraint inv_fusiones_distintas check (canonico_id <> fusionado_id)
);
comment on table crm.inversionista_fusiones is
  'F1 multiempresa: libro append-only de fusiones de identidad. Gana la canonica; la perdedora se marca fusionado (nunca se borra) y solo se reorientan enlaces operativos vivos. Nunca reescribe un mes sellado.';
create index inv_fusiones_canonico_idx  on crm.inversionista_fusiones (canonico_id);
create index inv_fusiones_fusionado_idx on crm.inversionista_fusiones (fusionado_id);

-- ============================================================================
-- 5. crm.inversiones — REGISTRO RELACIONAL (nunca una segunda fuente de dinero)
-- ============================================================================
-- Cada inversion referencia SU fuente economica (un contrato Avance O un cierre
-- de cooperativa), su empresa y su titular principal. El DINERO se sigue leyendo
-- de la fuente (contratos/cierres_externos) por private.capital_episodios: aqui
-- NO se guarda monto/moneda como verdad. Es el hilo que une persona<->empresa<->fuente.
create table crm.inversiones (
  id uuid primary key default gen_random_uuid(),
  inversionista_id uuid not null references crm.inversionistas(id),
  empresa_id uuid not null references crm.empresas(id),
  -- Fuente economica: EXACTAMENTE una (una fuente por inversion, decision F0).
  contrato_id uuid references public.contratos(id) on delete restrict,
  cierre_externo_id uuid references crm.cierres_externos(id) on delete restrict,
  estado text not null default 'vigente' check (estado in ('vigente','anulada')),
  -- Fecha comercial PROPIA de la inversion (decision 9, confirmada 02/09):
  -- anterior o igual al registro, NUNCA futura; en mes sellado entra como
  -- ajuste posterior. "Nunca futura" se valida en la PUERTA de escritura (F4):
  -- un CHECK de tabla no puede comparar contra el reloj (no es inmutable).
  fecha_comercial date,
  es_primera_conversion boolean not null default false,
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  actualizado_en timestamptz not null default now() check (isfinite(actualizado_en)),
  creado_por uuid references public.perfiles(id),
  -- Exactamente UNA fuente economica.
  constraint inversiones_una_fuente check (
    (contrato_id is not null)::int + (cierre_externo_id is not null)::int = 1
  )
);
comment on table crm.inversiones is
  'F1 multiempresa: registro RELACIONAL de inversiones (NO fuente de dinero). Une persona<->empresa<->fuente economica (un contrato Avance O un cierre de cooperativa, exactamente una). El monto/moneda se leen de la fuente por private.capital_episodios; aqui no se copian. fecha_comercial es propia (decision 9); "nunca futura" lo valida la puerta de escritura de F4. APAGADO en F1: ninguna puerta escribe aqui todavia.';
comment on column crm.inversiones.fecha_comercial is
  'Fecha comercial propia de la inversion (decision 9): <= registro, nunca futura; en mes sellado -> ajuste posterior. Validacion de "no futura" en la puerta de escritura (F4), no en CHECK.';
-- Una fuente economica pertenece a lo sumo a UNA inversion (sin doble conteo).
create unique index inversiones_contrato_uidx on crm.inversiones (contrato_id) where contrato_id is not null;
create unique index inversiones_cierre_uidx   on crm.inversiones (cierre_externo_id) where cierre_externo_id is not null;
create index inversiones_inv_idx     on crm.inversiones (inversionista_id);
create index inversiones_empresa_idx on crm.inversiones (empresa_id);
create index inversiones_estado_idx  on crm.inversiones (estado);

-- Titularidad: un principal, N cotitulares. Cotitular NO duplica Capital (regla
-- de lectura del nucleo, F3); aqui solo se modela la relacion.
create table crm.inversion_titulares (
  id uuid primary key default gen_random_uuid(),
  inversion_id uuid not null references crm.inversiones(id),
  inversionista_id uuid not null references crm.inversionistas(id),
  rol text not null default 'principal' check (rol in ('principal','cotitular')),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  creado_por uuid references public.perfiles(id)
);
comment on table crm.inversion_titulares is
  'F1 multiempresa: titular principal (uno) y cotitulares (N) de una inversion. Ser cotitular NO concede Auth/Portal/banca ni duplica Capital (eso se respeta en la lectura del nucleo). Modelo relacional apagado en F1.';
create unique index inversion_titulares_principal_uidx
  on crm.inversion_titulares (inversion_id) where rol = 'principal';
create unique index inversion_titulares_par_uidx
  on crm.inversion_titulares (inversion_id, inversionista_id);
create index inversion_titulares_inv_idx on crm.inversion_titulares (inversionista_id);

-- ============================================================================
-- 6. Idempotencia (saga) y banderas de rollout (apagadas)
-- ============================================================================
-- Idempotencia con hash (handoff #20/#21): misma clave + mismo hash devuelve el
-- resultado guardado; misma clave + hash distinto = conflicto auditado. La
-- comparacion la hara la puerta (F3/F4); F1 solo pone el almacen.
create table crm.multiempresa_idempotencia (
  clave text primary key check (length(clave) between 8 and 200),
  tipo text not null check (length(tipo) between 2 and 80),
  version integer not null default 1 check (version >= 1),
  hash_payload text not null check (hash_payload collate "C" ~ '^[a-f0-9]{64}$'),
  resultado jsonb,
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  creado_por uuid references public.perfiles(id)
);
comment on table crm.multiempresa_idempotencia is
  'F1 multiempresa: almacen de idempotencia de las puertas (clave, tipo, version, hash SHA-256 del payload canonico, resultado). Misma clave+hash devuelve resultado; misma clave+hash distinto = conflicto. Usado por F3/F4; apagado en F1.';

-- Banderas: TODAS apagadas. F1 no enciende ningun comportamiento nuevo.
create table crm.multiempresa_flags (
  nombre text primary key check (nombre collate "C" ~ '^[a-z][a-z0-9_]{2,60}$'),
  activo boolean not null default false,
  descripcion text,
  actualizado_en timestamptz not null default now() check (isfinite(actualizado_en)),
  actualizado_por uuid references public.perfiles(id)
);
comment on table crm.multiempresa_flags is
  'F1 multiempresa: banderas de rollout. TODAS apagadas en F1. Encienden comportamiento en F3+ (resolver en puertas, escritura de inversiones, Ficha 360). Solo Gerencia/servidor las mueve; sin grants a la Data API.';
insert into crm.multiempresa_flags (nombre, activo, descripcion) values
  ('resolver_en_puertas',   false, 'F3: las puertas de alta/conversion resuelven identidad via private.inversionista_resolver'),
  ('inversiones_escritura', false, 'F4: se registran filas en crm.inversiones/inversion_titulares'),
  ('ficha_360_neutral',     false, 'F5: la Ficha 360 y Mi cartera pasan a la identidad neutral');

-- ============================================================================
-- 7. Enlaces nullable en tablas vivas (aditivo, sin reescritura)
-- ============================================================================
alter table crm.leads            add column inversionista_id uuid references crm.inversionistas(id);
alter table crm.cierres_externos add column inversionista_id uuid references crm.inversionistas(id);
comment on column crm.leads.inversionista_id is
  'F1 multiempresa: enlace vivo lead->persona (nullable en captacion; obligatorio al convertir en F3). UNICO cuando no es null: impide un segundo lead de la misma persona. El historial completo vive en crm.inversionista_leads.';
comment on column crm.cierres_externos.inversionista_id is
  'F1 multiempresa: enlace cierre->persona (obligatorio al cierre en F3). El cierre deja de depender de lead.perfil_id para identificar a la persona.';
-- Restriccion clave del contrato §3: un solo lead por persona (vacia hoy: todo NULL).
create unique index leads_inversionista_uidx
  on crm.leads (inversionista_id) where inversionista_id is not null;
create index cierres_externos_inversionista_idx
  on crm.cierres_externos (inversionista_id);

-- ============================================================================
-- 8. private.inversionista_resolver — primitiva unica de identidad (§8.1)
-- ============================================================================
-- Normaliza, valida, busca el identificador vigente y crea idempotente si no
-- existe. La creacion del MISMO documento se serializa con un advisory lock; el
-- indice unico parcial es el respaldo (backstop) si dos transacciones se cruzan.
-- SIN EXECUTE para la Data API: solo la usan puertas definer (F3) o el backfill.
create function private.inversionista_resolver(
  p_tipo text,
  p_documento text,
  p_verificado boolean default false,
  p_fuente text default 'resolver'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_norm text;
  v_id uuid;
begin
  if p_tipo is null or p_tipo not in ('DNI','CE','PASAPORTE') then
    raise exception using errcode = '22023', message = 'Tipo de documento invalido';
  end if;
  v_norm := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento,''), '[^A-Za-z0-9]', '', 'g'));
  -- Validacion POR TIPO alineada con crm.cierres_externos (20260812000259).
  if (p_tipo = 'DNI'       and v_norm !~ '^[0-9]{8}$')
     or (p_tipo = 'CE'        and v_norm !~ '^[0-9]{9,12}$')
     or (p_tipo = 'PASAPORTE' and v_norm !~ '^[A-Z0-9]{6,12}$') then
    raise exception using errcode = '22023', message = 'Documento invalido para el tipo';
  end if;

  -- Serializa la creacion del MISMO documento (otros documentos no contienden).
  -- Asume READ COMMITTED (el default de las puertas F3): bajo REPEATABLE READ un
  -- reintento tras el lock podria no ver al ganador (snapshot fijado antes).
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('inv_resolver:' || p_tipo || ':' || v_norm));

  -- Solo resuelve un identificador VIGENTE, VERIFICADO y de identidad NO fusionada
  -- (contrato §4.2): nunca devuelve una identidad perdedora.
  select i.inversionista_id into v_id
  from crm.inversionista_identificadores i
  join crm.inversionistas inv on inv.id = i.inversionista_id
  where i.tipo_documento = p_tipo
    and i.documento_normalizado = v_norm
    and i.estado = 'vigente'
    and i.verificado = true
    and inv.estado <> 'fusionado'
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  -- No crea identidad OPERATIVA sin documento verificado (contrato §4.3).
  if p_verificado is not true then
    raise exception using errcode = '22023',
      message = 'No se crea identidad con documento sin verificar';
  end if;
  insert into crm.inversionistas (estado) values ('activo') returning id into v_id;
  insert into crm.inversionista_identificadores
    (inversionista_id, tipo_documento, documento_normalizado, documento_original,
     estado, verificado, fuente)
  values (v_id, p_tipo, v_norm, p_documento, 'vigente', true, coalesce(p_fuente, 'resolver'));
  return v_id;

exception when unique_violation then
  -- El indice unico arbitro la carrera: releer la identidad ganadora.
  -- (Los inserts de esta subtransaccion se deshacen solos al entrar aqui.)
  select i.inversionista_id into v_id
  from crm.inversionista_identificadores i
  where i.tipo_documento = p_tipo
    and i.documento_normalizado = v_norm
    and i.estado = 'vigente'
  limit 1;
  if v_id is null then
    -- No reelevar la unique_violation nativa: su DETAIL lleva el documento en
    -- claro (Key (tipo_documento, documento_normalizado)=(...)). Mensaje higienizado.
    raise exception using errcode = '23505',
      message = 'No se pudo resolver la identidad (documento en conflicto)';
  end if;
  return v_id;
end
$fn$;

comment on function private.inversionista_resolver(text,text,boolean,text) is
  'F1 multiempresa (§8.1): primitiva unica de resolucion de identidad. Normaliza y valida el documento, devuelve la identidad del identificador vigente o la crea idempotente (advisory lock + indice unico como respaldo). NUNCA fusiona por datos debiles. SIN EXECUTE para anon/authenticated/service_role.';

revoke all on function private.inversionista_resolver(text,text,boolean,text) from public;
revoke all on function private.inversionista_resolver(text,text,boolean,text) from anon, authenticated, service_role;

-- ============================================================================
-- 8.5. Candados de coherencia y proteccion (hallazgos de la revision de Codex)
-- ============================================================================
-- #4: crm.leads.inversionista_id NO puede escribirlo un cliente de la Data API
-- (authenticated tiene UPDATE de tabla; un revoke por columna no neutraliza un
-- grant de tabla). Un trigger lo protege igual que las guardas vivas protegen
-- perfil_id/contrato_id: nulo al alta y restaurado en update, salvo operacion
-- privilegiada (crm.op_privilegiada='on', que solo fijan las RPC definer).
-- cierres_externos NO lo necesita: no tiene escritura por la Data API.
create function private.leads_protege_inversionista_id() returns trigger
language plpgsql security definer set search_path = '' as $p4$
declare v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if not v_priv then
    if tg_op = 'INSERT' then
      new.inversionista_id := null;
    else
      new.inversionista_id := old.inversionista_id;
    end if;
  end if;
  return new;
end $p4$;
revoke all on function private.leads_protege_inversionista_id() from public, anon, authenticated, service_role;
create trigger trg_leads_protege_inversionista_id
  before insert or update on crm.leads
  for each row execute function private.leads_protege_inversionista_id();

-- #5: la fuente economica de una inversion debe corresponder a su empresa (una
-- empresa 'contratos' lleva contrato; una 'cierres_externos' lleva un cierre
-- cuya cooperativa == la clave de la empresa). El XOR solo garantiza UNA fuente.
create function private.inversiones_empresa_coherente() returns trigger
language plpgsql security definer set search_path = '' as $p5$
declare v_fuente text; v_clave text; v_coop text;
begin
  select e.fuente_capital, e.clave into v_fuente, v_clave from crm.empresas e where e.id = new.empresa_id;
  if v_fuente is null then
    raise exception 'inversiones: empresa % inexistente', new.empresa_id using errcode = '23503';
  end if;
  if new.contrato_id is not null then
    if v_fuente <> 'contratos' then
      raise exception 'inversiones: contrato en empresa cuya fuente es % (se esperaba contratos)', v_fuente using errcode = '23514';
    end if;
  else
    if v_fuente <> 'cierres_externos' then
      raise exception 'inversiones: cierre en empresa cuya fuente es % (se esperaba cierres_externos)', v_fuente using errcode = '23514';
    end if;
    select ce.cooperativa into v_coop from crm.cierres_externos ce where ce.id = new.cierre_externo_id;
    if v_coop is distinct from v_clave then
      raise exception 'inversiones: el cierre (coop %) no corresponde a la empresa %', v_coop, v_clave using errcode = '23514';
    end if;
  end if;
  return new;
end $p5$;
revoke all on function private.inversiones_empresa_coherente() from public, anon, authenticated, service_role;
create trigger trg_inversiones_empresa_coherente
  before insert or update on crm.inversiones
  for each row execute function private.inversiones_empresa_coherente();

-- #6: el titular 'principal' debe ser el mismo inversionista que la inversion
-- declara como principal (evita principal=B con inversiones.inversionista_id=A).
-- La cardinalidad "existe exactamente uno" la garantiza la puerta de F4 (crea
-- inversion + principal en una transaccion); aqui se sella la coherencia.
create function private.inversion_titular_coherente() returns trigger
language plpgsql security definer set search_path = '' as $p6$
declare v_principal uuid;
begin
  if new.rol = 'principal' then
    select i.inversionista_id into v_principal from crm.inversiones i where i.id = new.inversion_id;
    if new.inversionista_id is distinct from v_principal then
      raise exception 'inversion_titulares: el principal debe ser el inversionista de la inversion (% <> %)',
        new.inversionista_id, v_principal using errcode = '23514';
    end if;
  end if;
  return new;
end $p6$;
revoke all on function private.inversion_titular_coherente() from public, anon, authenticated, service_role;
create trigger trg_inversion_titular_coherente
  before insert or update on crm.inversion_titulares
  for each row execute function private.inversion_titular_coherente();

-- #7: el ancla de fusion y el libro se blindan.
--   (a) un perdedor se fusiona UNA sola vez;
create unique index inv_fusiones_fusionado_uidx on crm.inversionista_fusiones (fusionado_id);
--   (b) la canonica destino debe estar ACTIVA (no fusionada): impide cadenas y
--       ciclos (A->B->A), porque no se fusiona hacia una perdedora;
create function private.inversionista_fusion_destino_activo() returns trigger
language plpgsql security definer set search_path = '' as $p7a$
declare v_estado text;
begin
  if new.estado = 'fusionado' and new.inversionista_canonico_id is not null then
    select estado into v_estado from crm.inversionistas where id = new.inversionista_canonico_id;
    if v_estado is null then
      raise exception 'fusion: la identidad canonica % no existe', new.inversionista_canonico_id using errcode = '23503';
    end if;
    if v_estado = 'fusionado' then
      raise exception 'fusion: no se fusiona hacia una identidad ya fusionada (cadena/ciclo)' using errcode = '23514';
    end if;
  end if;
  return new;
end $p7a$;
revoke all on function private.inversionista_fusion_destino_activo() from public, anon, authenticated, service_role;
create trigger trg_inversionistas_fusion_destino
  before insert or update on crm.inversionistas
  for each row execute function private.inversionista_fusion_destino_activo();
--   (c) el libro de fusiones es APPEND-ONLY (el comentario lo prometia; ahora un
--       trigger lo cumple, ademas de no tener grants de la Data API).
create function private.inversionista_fusiones_append_only() returns trigger
language plpgsql security definer set search_path = '' as $p7b$
begin
  raise exception 'crm.inversionista_fusiones es append-only: % no permitido', tg_op using errcode = '0A000';
end $p7b$;
revoke all on function private.inversionista_fusiones_append_only() from public, anon, authenticated, service_role;
create trigger trg_inversionista_fusiones_append_only
  before update or delete on crm.inversionista_fusiones
  for each row execute function private.inversionista_fusiones_append_only();

-- ============================================================================
-- 9. RLS, permisos y auditoria (contrato §14: RLS activa, CERO grants a la API)
-- ============================================================================
-- Patron para las 10 tablas nuevas:
--   * RLS ON;
--   * SELECT solo para Gerencia (defensa en profundidad — ademas no hay grant);
--   * sin policy de INSERT/UPDATE/DELETE: la escritura sera por funciones
--     definer (owner postgres) que pasan por encima de RLS de forma controlada;
--   * revoke all de public/anon/authenticated/service_role (cero Data API);
--   * auditoria private.log_audit_crm en insert/update/delete;
--   * touch de actualizado_en donde exista la columna.
do $rls$
declare
  t text;
  con_actualizado text[] := array['empresas','inversionistas','inversiones','multiempresa_flags'];
  tablas text[] := array[
    'empresas','inversionistas','inversionista_identificadores','inversionista_leads',
    'inversionista_responsables','inversionista_fusiones','inversiones','inversion_titulares',
    'multiempresa_idempotencia','multiempresa_flags'];
begin
  foreach t in array tablas loop
    -- RLS activa (SIN force: postgres tiene bypassrls y ninguna de las 38 tablas
    -- crm usa force; el cierre real a la API son los revokes de abajo).
    execute format('alter table crm.%I enable row level security', t);
    execute format('revoke all on crm.%I from public, anon, authenticated, service_role', t);
    execute format(
      'create policy %I on crm.%I for select to authenticated using (private.es_gerencia_crm_activa())',
      t||'_select_gerencia', t);
    if t = 'inversionista_identificadores' then
      -- PII (documento): auditor ENMASCARADO — el documento nunca en claro en audit_log.
      execute format(
        $q$create trigger %I after insert or update or delete on crm.%I for each row execute function private.log_audit_sin_secretos('documento_normalizado','documento_original')$q$,
        'trg_audit_'||t, t);
    else
      execute format(
        'create trigger %I after insert or update or delete on crm.%I for each row execute function private.log_audit_crm()',
        'trg_audit_'||t, t);
    end if;
  end loop;
  foreach t in array con_actualizado loop
    execute format(
      'create trigger %I before update on crm.%I for each row execute function private.set_actualizado_en_crm()',
      'trg_'||t||'_touch', t);
  end loop;
end
$rls$;

-- ============================================================================
-- 10. Postflight — G1: contar lo que quedo, no lo que se quiso (house rule)
-- ============================================================================
do $post$
declare
  v_n int; v_falta text; v_rol text;
  v_tablas text[] := array[
    'empresas','inversionistas','inversionista_identificadores','inversionista_leads',
    'inversionista_responsables','inversionista_fusiones','inversiones','inversion_titulares',
    'multiempresa_idempotencia','multiempresa_flags'];
  t text;
begin
  -- 10.1 Las 10 tablas existen.
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='crm' and c.relkind='r' and c.relname = any(v_tablas);
  if v_n <> 10 then raise exception 'POSTFLIGHT: se esperaban 10 tablas nuevas, hay %', v_n; end if;

  -- 10.2 RLS activa en las 10.
  select string_agg(c.relname, ', ') into v_falta
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='crm' and c.relname = any(v_tablas) and not c.relrowsecurity;
  if v_falta is not null then raise exception 'POSTFLIGHT: RLS no activa en %', v_falta; end if;

  -- 10.3 CERO grants a la Data API en las 10 (anon/authenticated/service_role).
  foreach t in array v_tablas loop
    foreach v_rol in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(v_rol, 'crm.'||t, 'SELECT')
         or has_table_privilege(v_rol, 'crm.'||t, 'INSERT')
         or has_table_privilege(v_rol, 'crm.'||t, 'UPDATE')
         or has_table_privilege(v_rol, 'crm.'||t, 'DELETE') then
        raise exception 'POSTFLIGHT: % tiene privilegio directo sobre crm.% (debe ser CERO)', v_rol, t;
      end if;
    end loop;
  end loop;

  -- 10.4 Auditoria en las 10.
  select string_agg(t2, ', ') into v_falta from (
    select unnest(v_tablas) t2
    except
    select c.relname from pg_trigger tg join pg_class c on c.oid=tg.tgrelid join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='crm' and tg.tgname = 'trg_audit_'||c.relname
  ) s;
  if v_falta is not null then raise exception 'POSTFLIGHT: falta auditoria en %', v_falta; end if;

  -- 10.5 El resolver NO tiene EXECUTE para la API.
  foreach v_rol in array array['anon','authenticated','service_role'] loop
    if has_function_privilege(v_rol, 'private.inversionista_resolver(text,text,boolean,text)', 'EXECUTE') then
      raise exception 'POSTFLIGHT: % puede EJECUTAR el resolver (debe ser CERO)', v_rol;
    end if;
  end loop;

  -- 10.6 Semillas: 3 empresas, 3 flags TODAS apagadas.
  if (select count(*) from crm.empresas) <> 3 then raise exception 'POSTFLIGHT: se esperaban 3 empresas'; end if;
  if (select count(*) from crm.multiempresa_flags where activo) <> 0 then
    raise exception 'POSTFLIGHT: hay flags ENCENDIDAS (F1 debe dejarlas todas apagadas)';
  end if;

  -- 10.7 Enlaces nullable creados y VACIOS (aditivo, sin backfill en F1).
  if not exists (select 1 from information_schema.columns where table_schema='crm' and table_name='leads' and column_name='inversionista_id')
     or not exists (select 1 from information_schema.columns where table_schema='crm' and table_name='cierres_externos' and column_name='inversionista_id') then
    raise exception 'POSTFLIGHT: faltan los enlaces inversionista_id en leads/cierres_externos';
  end if;
  if (select count(*) from crm.leads where inversionista_id is not null) <> 0
     or (select count(*) from crm.cierres_externos where inversionista_id is not null) <> 0 then
    raise exception 'POSTFLIGHT: F1 no hace backfill — los enlaces deben estar VACIOS';
  end if;

  -- 10.8 El nucleo de Capital sigue EXISTIENDO con su firma exacta (F1 no toca
  -- dinero). No se ancla al md5(prosrc): es fragil (cualquier byte lo mueve, y
  -- regla de la casa: md5 no acredita una recreacion) y acoplaria F1 a una
  -- funcion que no toca. La firma ::regprocedure ya pina los 4 tipos de argumento.
  if to_regprocedure('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])') is null then
    raise exception 'POSTFLIGHT: desaparecio private.capital_episodios — F1 no debe tocar el nucleo';
  end if;

  -- 10.9 Candados de la revision de Codex presentes.
  if to_regprocedure('private.leads_protege_inversionista_id()') is null
     or not exists (select 1 from pg_trigger where tgname='trg_leads_protege_inversionista_id' and not tgisinternal)
     or to_regprocedure('private.inversiones_empresa_coherente()') is null
     or to_regprocedure('private.inversion_titular_coherente()') is null
     or to_regprocedure('private.inversionista_fusion_destino_activo()') is null
     or to_regprocedure('private.inversionista_fusiones_append_only()') is null
     or not exists (select 1 from pg_indexes where schemaname='crm' and indexname='inv_fusiones_fusionado_uidx') then
    raise exception 'POSTFLIGHT: faltan candados de coherencia/proteccion de F1';
  end if;

  raise notice 'F1 OK: 10 tablas con RLS activa y auditoria, 0 grants API, resolver privado, 3 empresas, flags apagadas, enlaces vacios, candados de coherencia, nucleo intacto.';
end
$post$;

commit;
