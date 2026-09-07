-- ============================================================================
-- CRM · RENTABILIDAD SERVER-SIDE · R2 — OBSERVACIÓN: cada alta y cada corrección de tasa quedan en el ledger, sin bloquear
-- (plan del vault «Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06», fase R2; R1 = 20260906170000)
-- ============================================================================
--
-- QUÉ. R1 dejó el núcleo (private.resolver_tasa), la política v1 (15% · observación) y el ledger con la historia legacy.
-- R2 conecta el ledger a la REALIDAD sin tocar ninguna función viva: un TRIGGER DIFERIDO (constraint trigger, se dispara al
-- COMMIT) sobre public.contratos observa TODA alta (INSERT) y toda corrección de tasa (UPDATE OF tasa_anual), venga del CRM
-- (crm.crear_contrato_con_cuenta_pdf_v2), del portal admin (public.crear_contrato), de la corrección
-- (crm.actualizar_contrato_con_cuenta_pdf_v3 / public.actualizar_contrato) o de una llamada directa, y escribe UNA fila
-- `origen = observacion` con: la tasa que dice el núcleo (base + regla), la que quedó en el contrato (final = recibida),
-- `divergente`, y en `detalle` el capital, la moneda, el plazo, quién cerró y quién digitó (foto en el momento: si el
-- contrato luego se corrige o se elimina, la observación no cambia). NUNCA lanza: si el núcleo no puede resolver (cliente
-- inactivo, categoría nula, upgrade sin origen claro…) anota `regla = sin_regla` con el motivo, y si el propio INSERT en
-- el ledger falla, deja un WARNING y el alta sigue. En observación NO SE BLOQUEA NADA (eso es R4).
--
-- Por qué diferido al commit: public.crear_contrato inserta el contrato y DESPUÉS la fila de crm.operaciones_cartera
-- (que trae el contrato origen de una renovación) y cierra el origen (estado renovado, renovado_a_id); al commit ya está
-- todo. Precedente en la misma tabla: trg_contratos_operacion_cartera_commit (constraint trigger diferido).
--
-- El núcleo gana un argumento: private.resolver_tasa(cliente, categoría, origen, instante, p_contrato_nuevo_id). Un origen
-- que ya quedó «renovado» POR ESTE contrato sigue siendo su origen válido (al commit el origen ya está cerrado). La firma de
-- 4 argumentos de R1 se conserva como envoltorio (delega con null): mismo comportamiento para R1/R3. Sigue siendo UN núcleo.
--
-- Upgrade: hoy la puerta NO registra el contrato origen de un upgrade (operaciones_cartera lo lleva a null por CHECK). El
-- observador lo INFIERE solo cuando es inequívoco (el cliente tiene exactamente UN contrato activo anterior, sin contar demo)
-- y lo marca `origen_inferido = true`; si hay 0 o varios candidatos → `sin_regla` con motivo `upgrade_sin_contrato_activo_previo`
-- | `upgrade_origen_ambiguo`. Censo de prod al construir: 78 upgrades, 35 con origen único, 43 ambiguos → es justo el «caso no
-- definido» que R2 debe medir y que R3 resuelve (D2: el analista selecciona el origen).
--
-- TARJETA. crm.observacion_rentabilidad_fn(p_desde, p_hasta) → jsonb (solo Gerencia y Directorio): eventos y contratos,
-- divergentes/ceden/retienen/sin_regla, margen cedido y retenido en el PLAZO por moneda (capital × puntos/100 × plazo/365)
-- sobre la REVISIÓN EFECTIVA de cada contrato al corte (una corrección no suma dos veces) y solo de fotos completas, por
-- regla, por analista (quien cerró; si no, quien digitó), casos sin regla por motivo y últimos divergentes. Demo excluido por la
-- marca ACTUAL del contrato. Lee SOLO del ledger (una fuente); sondas separadas: consistencia_interna, cobertura_altas
-- (desde el hito crm.rentabilidad_hitos.observacion_activa_desde) y cobertura_correcciones (declarada desconocida).
--
-- v4 (06/09, tras auditor-rls y Codex): la observación se hace sobre el estado FINAL de la fila al commit y UNA por contrato
-- y transacción (detalle.xid); vigila también categoría, cliente, capital, moneda y fechas; en una corrección conserva la
-- resolución original del alta; el origen de un upgrade nunca se «infiere» como regla (queda sin_regla con el candidato en
-- detalle); lock_timeout 2 s en el observador; la condición de renovación usa IS NOT TRUE (un origen retirado ya no pasa).
-- v6 (Codex 2.ª ronda): marcador transaccional por contrato (un cambio neto vacío no es una corrección); la resolución
-- conservada exige mismo cliente y categoría y arrastra su política; el hito se fija tras montar el trigger y la tabla de hitos
-- sobrevive a la reversa; casts protegidos en la tarjeta; conciliación de importes sin redondear; cobertura por evento INSERT.
-- Riesgos ACEPTADOS y declarados: WHEN OTHERS no atrapa 57014 (statement_timeout de un cliente que además fuerce
-- SET CONSTRAINTS IMMEDIATE; nadie lo hace en el proyecto y PG17 apaga el temporizador antes del commit) ni assert_failure;
-- un contrato marcado demo y luego ELIMINADO vuelve a contarse por su foto (raro; la eliminación deja rastro propio).
-- v7 (Codex 3.ª ronda): `secuencia` monotónica en el ledger para ordenar revisiones; una corrección conserva también la
-- incertidumbre (sin_regla) de la resolución original; politica_version = la de la resolución conservada; casts de es_demo y
-- uuid estrictos. Límites aceptados además: lock_timeout es por adquisición (el observador hace 2–3: ledger + auditoría);
-- las altas ELIMINADAS salen de la comprobación de cobertura; si la categoría vuelve a la original tras un cambio, se recupera
-- la resolución del alta (la que se aplicó de verdad), aunque la política haya cambiado entre medias.
--
-- QUÉ TOCA DE `public`: SOLO un constraint trigger nuevo sobre public.contratos (trg_contratos_zz_observar_rentabilidad),
-- AFTER, diferido, que no modifica la fila ni puede abortar la transacción (todo bajo exception). Ninguna función viva cambia
-- (guardas + postflight de las 5 puertas de escritura). OK de Miguel: al aplicarla con `!` (registro de excepciones a
-- `public` en MIGRACIONES.md).
--
-- Ensayo: scripts/oraculo-rentabilidad-r2.sh (banco). Reversa: scripts/rollback-rentabilidad-r2.sql.
-- Registro: scripts/registrar-rentabilidad-r2.sql. Bloque «rentabilidad R2» en scripts/test-rls.mjs.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r2'));

create temp table _r2_puertas on commit drop as
select p.oid as fnoid, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as firma, md5(p.prosrc) as h
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'crm' and p.proname in ('crear_contrato_con_cuenta_pdf_v2', 'actualizar_contrato_con_cuenta_pdf_v3', 'crear_contrato_con_cuenta'))
   or (n.nspname = 'public' and p.proname in ('crear_contrato', 'actualizar_contrato'));

do $guard$
begin
  -- Textos conocidos: el vivo de producción del 06/09 y, para crm.crear_contrato_con_cuenta y public.crear_contrato, el que
  -- deja F2.b D-19 (20260906200000, ensayada en banco-f7 el mismo día; puede aterrizar antes o después que R2). R2 no toca
  -- ninguna de las cinco: solo exige que sean un texto conocido y que no cambien durante la migración (postflight).
  if (select count(*) from _r2_puertas) <> 5
     or (select h from _r2_puertas where firma like 'crm.crear_contrato_con_cuenta_pdf_v2(%') is distinct from '0fd6fa8d1d8f8106cb52662cb64193e0'
     or (select h from _r2_puertas where firma like 'crm.actualizar_contrato_con_cuenta_pdf_v3(%') is distinct from '85614480d6c8939e818342ef3fe63c65'
     or (select h from _r2_puertas where firma like 'crm.crear_contrato_con_cuenta(%') not in ('7f2b4976640553a50ab27cf25b30fb36', '0de7a130ae366cde54035e2c50f213e2')
     or (select h from _r2_puertas where firma like 'public.crear_contrato(%') not in ('061c40e345312ca5e515ddd5ee282e5c', '4bf2f691888bee4d3198cccba8acd396')
     or (select h from _r2_puertas where firma like 'public.actualizar_contrato(%') is distinct from 'db2e6d36d46c72250fd6f42022af80be' then
    raise exception 'RENTABILIDAD R2: alguna puerta de escritura de contratos no es un texto conocido (prod 06/09 o F2.b D-19)';
  end if;
  -- R1 aplicada y con su texto exacto (prod = banco).
  if to_regclass('crm.politica_rentabilidad') is null or to_regclass('crm.ledger_rentabilidad') is null or to_regclass('crm.solicitudes_tasa') is null then
    raise exception 'RENTABILIDAD R2: falta R1 (20260906170000)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.resolver_tasa(uuid,text,uuid,timestamptz)'::regprocedure) is distinct from 'f394b983e5554deb38a210329694aa70' then
    raise exception 'RENTABILIDAD R2: private.resolver_tasa(uuid,text,uuid,timestamptz) no es el texto de R1 (f394b983…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.politica_rentabilidad_vigente(timestamptz)'::regprocedure) is distinct from '8cc36ea7d3463f15a19b4209081450c9' then
    raise exception 'RENTABILIDAD R2: private.politica_rentabilidad_vigente no es el texto de R1 (8cc36ea7…)';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_operacion_cartera_commit' and t.tgenabled = 'O' and t.tgdeferrable and t.tginitdeferred) then
    raise exception 'RENTABILIDAD R2: falta el precedente trg_contratos_operacion_cartera_commit (constraint trigger diferido) en public.contratos';
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.contratos'::regclass and tgname = 'trg_contratos_zz_observar_rentabilidad')
     or to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)') is not null
     or to_regprocedure('crm.observacion_rentabilidad_fn(date,date)') is not null then
    raise exception 'RENTABILIDAD R2: ya está aplicada (existen sus objetos); no se reaplica';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906180000') then
    raise exception 'RENTABILIDAD R2: la versión 20260906180000 ya está registrada';
  end if;
end
$guard$;

-- ---------------------------------------------------------------------------
-- 1. EL NÚCLEO, con el argumento «este contrato nuevo»: la firma de R1 delega.
-- ---------------------------------------------------------------------------
create or replace function private.resolver_tasa(
  p_cliente_id uuid,
  p_categoria text,
  p_contrato_origen_id uuid,
  p_instante timestamptz,
  p_contrato_nuevo_id uuid
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_pol      crm.politica_rentabilidad;
  v_cli      record;
  v_origen   public.contratos%rowtype;
  v_previos  integer;
  v_activos  integer;
  v_base     numeric;
  v_regla    text;
begin
  if p_cliente_id is null then
    raise exception 'El cliente es obligatorio' using errcode = '22023';
  end if;
  if p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (nuevo, renovacion o upgrade)' using errcode = '22023';
  end if;
  v_pol := private.politica_rentabilidad_vigente(p_instante);
  if v_pol.id is null then
    raise exception 'No hay política de rentabilidad vigente' using errcode = 'P0002';
  end if;
  select p.id, p.activo, p.asesor_perfil_id into v_cli
  from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente';
  if v_cli.id is null then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  if v_cli.activo is not true then
    raise exception 'El cliente está inactivo' using errcode = 'P0409';
  end if;
  -- «Previos» = los contratos del cliente sin contar el que se está observando (al commit, el nuevo ya existe).
  select count(*), count(*) filter (where c.estado = 'activo')
    into v_previos, v_activos
  from public.contratos c
  where c.cliente_id = p_cliente_id and not c.es_demo and c.id is distinct from p_contrato_nuevo_id;

  if p_categoria = 'nuevo' then
    if p_contrato_origen_id is not null then
      raise exception 'Una primera inversión no lleva contrato origen' using errcode = '22023';
    end if;
    v_base := v_pol.tasa_base_nueva;
    v_regla := 'primera_inversion';
  else
    if p_contrato_origen_id is null then
      raise exception 'Selecciona el contrato que se % (contrato origen)', case when p_categoria = 'renovacion' then 'renueva' else 'amplía' end
        using errcode = '22023';
    end if;
    select * into v_origen from public.contratos c where c.id = p_contrato_origen_id;
    if v_origen.id is null then
      raise exception 'El contrato origen no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from p_cliente_id then
      raise exception 'El contrato origen pertenece a otro cliente' using errcode = 'P0409';
    end if;
    if p_categoria = 'renovacion' then
      -- Mismo criterio que public.crear_contrato: se renueva un contrato activo o vencido que aún no fue renovado…
      -- …salvo que ya haya quedado renovado POR ESTE contrato (observación al commit): sigue siendo su origen.
      -- IS NOT TRUE (no «NOT»): con renovado_a_id NULL la segunda alternativa es NULL y un «NOT NULL» dejaría pasar un
      -- origen retirado (Codex R2 #3). La segunda alternativa exige además estado 'renovado'.
      if (
           (v_origen.estado in ('activo', 'vencido') and v_origen.renovado_a_id is null)
        or (p_contrato_nuevo_id is not null and v_origen.estado = 'renovado' and v_origen.renovado_a_id = p_contrato_nuevo_id)
      ) is not true then
        raise exception 'El contrato origen ya fue cerrado o renovado (estado «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_renovacion';
    else
      -- D2: el upgrade amplía un contrato ACTIVO concreto que el analista selecciona.
      if v_origen.estado <> 'activo' or v_origen.renovado_a_id is not null then
        raise exception 'El upgrade solo amplía un contrato activo (este está «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_upgrade';
    end if;
    v_base := v_origen.tasa_anual;
  end if;

  return jsonb_build_object(
    'tasa_base', v_base,
    'regla', v_regla,
    'categoria', p_categoria,
    'cliente_id', p_cliente_id,
    'contrato_origen', case when v_origen.id is null then null else jsonb_build_object(
        'id', v_origen.id, 'numero_contrato', v_origen.numero_contrato, 'tasa_anual', v_origen.tasa_anual,
        'estado', v_origen.estado, 'moneda', v_origen.moneda, 'capital', v_origen.capital,
        'fecha_vencimiento', v_origen.fecha_vencimiento) end,
    'contratos_previos', v_previos,
    'contratos_activos', v_activos,
    'prioridad_bandeja', (p_categoria = 'nuevo' and v_previos > 0),
    'politica', jsonb_build_object('id', v_pol.id, 'version', v_pol.version, 'modo', v_pol.modo,
        'tasa_base_nueva', v_pol.tasa_base_nueva, 'tope_tecnico', v_pol.tope_tecnico,
        'vigencia_solicitud_dias', v_pol.vigencia_solicitud_dias),
    'resuelto_en', coalesce(p_instante, statement_timestamp())
  );
end;
$function$;
revoke all on function private.resolver_tasa(uuid, text, uuid, timestamptz, uuid) from public, anon, authenticated, service_role;
comment on function private.resolver_tasa(uuid, text, uuid, timestamptz, uuid) is
  'Rentabilidad R2: EL ÚNICO NÚCLEO de «qué tasa base corresponde y por qué» (cuerpo de R1 + p_contrato_nuevo_id: un origen ya renovado POR ESE contrato sigue siendo su origen válido; los «previos» excluyen al contrato observado). La firma de 4 argumentos delega aquí.';

create or replace function private.resolver_tasa(
  p_cliente_id uuid,
  p_categoria text,
  p_contrato_origen_id uuid,
  p_instante timestamptz default statement_timestamp()
)
returns jsonb
language sql stable security definer set search_path = ''
as $function$
  select private.resolver_tasa(p_cliente_id, p_categoria, p_contrato_origen_id, p_instante, null::uuid)
$function$;
revoke all on function private.resolver_tasa(uuid, text, uuid, timestamptz) from public, anon, authenticated, service_role;
comment on function private.resolver_tasa(uuid, text, uuid, timestamptz) is
  'Rentabilidad R1/R2: envoltorio de compatibilidad; delega en private.resolver_tasa(…, p_contrato_nuevo_id := null). Mismo comportamiento que en R1.';

-- ---------------------------------------------------------------------------
-- 1.a SECUENCIA en el ledger (Codex R2 #22): orden estricto de confirmación de las observaciones, independiente del reloj.
-- ---------------------------------------------------------------------------
alter table crm.ledger_rentabilidad add column if not exists secuencia bigint generated by default as identity;
comment on column crm.ledger_rentabilidad.secuencia is 'R2: orden monotónico de inserción (la observación diferida se inserta al commit): la revisión efectiva de un contrato es la de mayor secuencia.';
create index if not exists ledger_rentabilidad_secuencia_idx on crm.ledger_rentabilidad (contrato_id, secuencia desc);

-- ---------------------------------------------------------------------------
-- 1.b HITOS: el instante desde el que la observación es exigible (Codex R2 #10: una alta anterior a R2 no es un hueco).
-- ---------------------------------------------------------------------------
create table if not exists crm.rentabilidad_hitos (
  clave          text primary key check (clave ~ '^[a-z_]{3,60}$'),
  valor          jsonb not null check (jsonb_typeof(valor) = 'object'),
  registrado_en  timestamptz not null default statement_timestamp()
);
alter table crm.rentabilidad_hitos enable row level security;
comment on table crm.rentabilidad_hitos is 'Rentabilidad R2. Hitos del sistema de rentabilidad: observacion_activa_desde (desde cuándo toda alta debe tener su observación; se fija DESPUÉS de montar el observador, bajo su candado) y observacion_desactivada_en (lo escribe la reversa). La tabla SOBREVIVE a la reversa de R2 (rastro); solo la escriben migraciones y reversas.';
-- (Si la tabla sobrevive de una instalación anterior, se le quitan los triggers de aquella versión antes de montar los de esta.)
drop trigger if exists trg_rentabilidad_hitos_inmutable on crm.rentabilidad_hitos;
drop trigger if exists trg_rentabilidad_hitos_solo_migraciones on crm.rentabilidad_hitos;
create trigger trg_rentabilidad_hitos_solo_migraciones before delete on crm.rentabilidad_hitos
for each row execute function private.trg_ledger_rentabilidad_append_only();
drop trigger if exists trg_audit_rentabilidad_hitos on crm.rentabilidad_hitos;
create trigger trg_audit_rentabilidad_hitos after insert or update on crm.rentabilidad_hitos
for each row execute function private.log_audit_crm();
revoke all on table crm.rentabilidad_hitos from public, anon, authenticated, service_role;
grant select on table crm.rentabilidad_hitos to authenticated, service_role;
drop policy if exists rentabilidad_hitos_select on crm.rentabilidad_hitos;
create policy rentabilidad_hitos_select on crm.rentabilidad_hitos for select to authenticated
using ((select private.es_lector_global()) or (select private.rol_crm((select auth.uid()))) is not null);

-- ---------------------------------------------------------------------------
-- 2. EL OBSERVADOR: constraint trigger diferido sobre public.contratos. Nunca lanza.
-- ---------------------------------------------------------------------------
create or replace function private.trg_contratos_observar_rentabilidad()
returns trigger
language plpgsql security definer set search_path = '' set lock_timeout = '2s'
as $function$
declare
  v_c          public.contratos%rowtype;   -- el estado FINAL de la fila al commit (no la imagen del evento; Codex R2 #4)
  v_xid        text := pg_current_xact_id()::text;
  v_marca      text := 'crm.r2_obs_' || replace(new.id::text, '-', '');   -- GUC transaccional: «este contrato ya se procesó en esta tx»
  v_pol        crm.politica_rentabilidad;
  v_prev       record;
  v_prev_id    uuid;
  v_conservada boolean := false;
  v_pol_id     uuid;
  v_origen     uuid;
  v_candidatos integer := 0;
  v_cand_id    uuid;
  v_cand_num   text;
  v_cand_tasa  numeric;
  v_res        jsonb;
  v_base       numeric;
  v_regla      text;
  v_motivo     text;
  v_cambios    jsonb;
  v_detalle    jsonb;
begin
 -- TODO el cuerpo va bajo una excepción externa: el observador no puede abortar un alta ni una corrección. lock_timeout=2s
 -- convierte una espera de candado en 55P03 (atrapable). Lo único que WHEN OTHERS no atrapa es query_canceled (57014):
 -- en PostgreSQL 17 statement_timeout se desactiva antes del commit, y aquí no hay más esperas que las de candado.
 begin
  select * into v_c from public.contratos c where c.id = new.id;
  if v_c.id is null then
    return null;   -- borrado en la misma transacción: nada que observar
  end if;
  -- UNA observación por contrato y transacción: varios eventos (alta + correcciones en la misma tx) → una sola foto FINAL.
  -- El marcador es un GUC transaccional (se fija también cuando el cambio neto es vacío: 15→18→15 no es una corrección; Codex R2 #25).
  -- Límite declarado: si un cliente ejecutara SET CONSTRAINTS … IMMEDIATE a mitad de transacción, la foto sería la de ese
  -- momento (nadie lo hace en el proyecto; Codex R2 #19).
  if coalesce(current_setting(v_marca, true), '') = '1' then
    return null;
  end if;
  perform set_config(v_marca, '1', true);
  if tg_op = 'UPDATE' then
    -- Solo si cambió algo que determine la regla o el margen (Codex R2 #5), comparando la imagen previa con el estado final.
    v_cambios := jsonb_strip_nulls(jsonb_build_object(
      'tasa_anual',        case when old.tasa_anual        is distinct from v_c.tasa_anual        then jsonb_build_array(old.tasa_anual, v_c.tasa_anual) end,
      'categoria',         case when old.categoria         is distinct from v_c.categoria         then jsonb_build_array(old.categoria, v_c.categoria) end,
      'cliente_id',        case when old.cliente_id        is distinct from v_c.cliente_id        then jsonb_build_array(old.cliente_id, v_c.cliente_id) end,
      'capital',           case when old.capital           is distinct from v_c.capital           then jsonb_build_array(old.capital, v_c.capital) end,
      'moneda',            case when old.moneda            is distinct from v_c.moneda            then jsonb_build_array(old.moneda, v_c.moneda) end,
      'fecha_inicio',      case when old.fecha_inicio      is distinct from v_c.fecha_inicio      then jsonb_build_array(old.fecha_inicio, v_c.fecha_inicio) end,
      'fecha_vencimiento', case when old.fecha_vencimiento is distinct from v_c.fecha_vencimiento then jsonb_build_array(old.fecha_vencimiento, v_c.fecha_vencimiento) end));
    if v_cambios = '{}'::jsonb then
      return null;
    end if;
  end if;
  v_pol := private.politica_rentabilidad_vigente(statement_timestamp());
  if v_pol.id is null then
    return null;   -- sin política publicada no se observa (R1 garantiza la v1)
  end if;

  -- En una CORRECCIÓN que no cambia cliente ni categoría, la base de comparación es la RESOLUCIÓN ORIGINAL del alta
  -- (base, regla, origen), no una reevaluación con el estado de hoy (Codex R2 #8). Si cambió cliente o categoría, se resuelve de nuevo.
  v_pol_id := v_pol.id;
  if tg_op = 'UPDATE' and not (v_cambios ? 'categoria' or v_cambios ? 'cliente_id') then
    -- Solo se conserva una resolución del MISMO cliente y la MISMA categoría (Codex R2 #20), con la política que la produjo (#21).
    select l.tasa_base, l.regla, l.contrato_origen_id, l.politica_id, l.id, l.detalle ->> 'motivo' as motivo into v_prev
    from crm.ledger_rentabilidad l
    where l.contrato_id = v_c.id and l.origen = 'observacion'
      and l.categoria = v_c.categoria and l.cliente_id = v_c.cliente_id
    order by l.secuencia asc limit 1;
    if v_prev.regla is not null then
      -- Se conserva la resolución original… y también su INCERTIDUMBRE (Codex #8): un sin_regla no se «resuelve» al corregir.
      v_regla := v_prev.regla; v_origen := v_prev.contrato_origen_id; v_pol_id := v_prev.politica_id; v_prev_id := v_prev.id; v_conservada := true;
      if v_prev.regla = 'sin_regla' then
        v_base := v_c.tasa_anual; v_motivo := coalesce(v_prev.motivo, 'sin_motivo');
      else
        v_base := v_prev.tasa_base;
      end if;
    end if;
  end if;

  if not v_conservada then
    begin
      if v_c.categoria is null then
        v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'categoria_nula';
      elsif v_c.categoria = 'renovacion' then
        select o.contrato_origen_id into v_origen from crm.operaciones_cartera o where o.contrato_nuevo_id = v_c.id;
        if v_origen is null then
          v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'renovacion_sin_origen_registrado';
        else
          v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, v_origen, statement_timestamp(), v_c.id);
          v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla';
        end if;
      elsif v_c.categoria = 'upgrade' then
        -- D2 exige que el analista SELECCIONE el origen (R3). Hoy la puerta no lo registra: el observador solo apunta el
        -- candidato cuando es único —contrato activo del cliente que ya EXISTÍA antes y seguía vigente al inicio del
        -- nuevo— y lo deja como sin_regla (una inferencia es una hipótesis, no una regla; Codex R2 #7).
        select count(*), min(c.id::text)::uuid into v_candidatos, v_origen
        from public.contratos c
        where c.cliente_id = v_c.cliente_id and c.id <> v_c.id and c.estado = 'activo' and c.renovado_a_id is null
          and not c.es_demo and c.creado_en < v_c.creado_en and c.fecha_vencimiento >= v_c.fecha_inicio;
        if v_candidatos = 1 then
          select c.id, c.numero_contrato, c.tasa_anual into v_cand_id, v_cand_num, v_cand_tasa from public.contratos c where c.id = v_origen;
          v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'upgrade_origen_inferido';
        else
          v_origen := null; v_regla := 'sin_regla'; v_base := v_c.tasa_anual;
          v_motivo := case when v_candidatos = 0 then 'upgrade_sin_contrato_activo_previo' else 'upgrade_origen_ambiguo' end;
        end if;
        v_origen := null;   -- sin origen DEMOSTRADO no se anota como origen; el candidato va en detalle
      else
        v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, null, statement_timestamp(), v_c.id);
        v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla';
      end if;
    exception when others then
      -- El núcleo no pudo decidir (cliente inactivo, origen raro…): se anota, no se bloquea.
      v_regla := 'sin_regla'; v_base := v_c.tasa_anual;
      v_motivo := 'resolver:' || sqlstate || ':' || left(sqlerrm, 160);
      v_res := null; v_origen := null;
    end;
  end if;

  v_detalle := jsonb_strip_nulls(jsonb_build_object(
    'xid', v_xid, 'evento', tg_op,
    'capital', v_c.capital, 'moneda', v_c.moneda,
    'fecha_inicio', v_c.fecha_inicio, 'fecha_vencimiento', v_c.fecha_vencimiento,
    'plazo_dias', (v_c.fecha_vencimiento - v_c.fecha_inicio),
    'analista_cierre_id', v_c.analista_cierre_id, 'creado_por', v_c.creado_por,
    'es_demo', v_c.es_demo, 'estado', v_c.estado, 'operacion', tg_op,
    'tasa_anterior', case when tg_op = 'UPDATE' then old.tasa_anual end,
    'cambios', case when tg_op = 'UPDATE' then v_cambios end,
    'base_conservada', case when v_conservada then true end,
    'observacion_base_id', v_prev_id,
    'politica_vigente_al_observar', v_pol.version,
    'motivo', v_motivo,
    'candidato_origen', case when v_cand_id is null then null else jsonb_build_object('id', v_cand_id, 'numero_contrato', v_cand_num, 'tasa_anual', v_cand_tasa) end,
    'politica_version', (select pp.version from crm.politica_rentabilidad pp where pp.id = v_pol_id),
    'resolucion', case when v_res is null then null else v_res - 'politica' - 'cliente_id' - 'categoria' end
  ));
  begin
    insert into crm.ledger_rentabilidad (
      contrato_id, numero_contrato, cliente_id, categoria, contrato_origen_id, politica_id, solicitud_id,
      tasa_base, tasa_final, tasa_recibida, regla, origen, actor_id, detalle
    ) values (
      v_c.id, v_c.numero_contrato, v_c.cliente_id, v_c.categoria, v_origen, v_pol_id, null,
      v_base, v_c.tasa_anual, v_c.tasa_anual, v_regla, 'observacion', (select auth.uid()), v_detalle
    );
  exception when others then
    raise warning 'RENTABILIDAD R2: no se pudo observar el contrato % (% %)', v_c.id, sqlstate, sqlerrm;
  end;
  return null;
 exception when others then
  raise warning 'RENTABILIDAD R2: el observador falló y se ignora (% %) en el contrato %', sqlstate, sqlerrm, new.id;
  return null;
 end;
end;
$function$;
revoke all on function private.trg_contratos_observar_rentabilidad() from public, anon, authenticated, service_role;
comment on function private.trg_contratos_observar_rentabilidad() is
  'Rentabilidad R2: observador diferido de public.contratos (INSERT y UPDATE de tasa, categoría, cliente, capital, moneda o fechas). Al commit relee el estado FINAL de la fila y escribe UNA fila origen=observacion por contrato y transacción (detalle.xid) en crm.ledger_rentabilidad: base del núcleo vs la que quedó; en una corrección conserva la resolución original del alta (base_conservada); sin_regla con motivo cuando no decide (upgrade: solo candidato, nunca origen inferido); nunca aborta (lock_timeout 2 s → 55P03 atrapado; WARNING). No bloquea: eso es R4.';

create constraint trigger trg_contratos_zz_observar_rentabilidad
after insert or update of tasa_anual, categoria, cliente_id, capital, moneda, fecha_inicio, fecha_vencimiento on public.contratos
deferrable initially deferred
for each row execute function private.trg_contratos_observar_rentabilidad();
-- El hito de activación se fija AHORA, ya con el candado de CREATE TRIGGER sobre public.contratos (ningún alta concurrente
-- puede colarse entre el hito y el observador; Codex R2 #23) y con clock_timestamp (statement_timestamp es constante en todo
-- el archivo). Si R2 se reaplica tras una reversa, la cobertura exigible arranca en la NUEVA activación (limitación declarada).
insert into crm.rentabilidad_hitos (clave, valor, registrado_en)
values ('observacion_activa_desde', jsonb_build_object('en', clock_timestamp(), 'migracion', '20260906180000'), clock_timestamp())
on conflict (clave) do update set valor = excluded.valor, registrado_en = excluded.registrado_en;

-- ---------------------------------------------------------------------------
-- 3. LA TARJETA: lectura del ledger para Gerencia (una sola fuente, con sonda de coherencia).
-- ---------------------------------------------------------------------------
create or replace function crm.observacion_rentabilidad_fn(p_desde date default null, p_hasta date default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_uid   uuid := (select auth.uid());
  v_rol   text := private.rol_crm(v_uid);
  v_hoy   date := (now() at time zone 'America/Lima')::date;
  v_hasta date := coalesce(p_hasta, v_hoy);
  v_desde date := coalesce(p_desde, v_hasta - 29);
  v_ini   timestamptz;
  v_fin   timestamptz;
  v_act   timestamptz;
  v_pol   crm.politica_rentabilidad;
  v_payload jsonb;
begin
  if v_uid is null or not coalesce(v_rol = 'gerencia' or private.es_lector_global(), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if not isfinite(v_desde) or not isfinite(v_hasta) or v_desde > v_hasta or (v_hasta - v_desde) > 365 or v_hasta > v_hoy then
    raise exception 'Periodo inválido (desde <= hasta <= hoy, máximo 366 días)' using errcode = '22023';
  end if;
  v_ini := (v_desde::timestamp at time zone 'America/Lima');
  v_fin := ((v_hasta + 1)::timestamp at time zone 'America/Lima');
  v_pol := private.politica_rentabilidad_vigente(statement_timestamp());
  select (h.valor ->> 'en')::timestamptz into v_act from crm.rentabilidad_hitos h where h.clave = 'observacion_activa_desde';

  with eventos as materialized (
    -- Todas las observaciones del periodo (eventos), sin demo: la marca demo AUTORITATIVA es la del contrato hoy
    -- (public.marcar_contrato_demo la cambia después del alta; Codex R2 #6); si el contrato ya no existe, la foto.
    select l.id, l.secuencia, l.contrato_id, l.numero_contrato, l.cliente_id, l.categoria, l.regla, l.tasa_base, l.tasa_final,
           l.divergente, l.registrado_en, l.detalle, l.detalle ->> 'operacion' as operacion
    from crm.ledger_rentabilidad l
    left join public.contratos c on c.id = l.contrato_id
    where l.origen = 'observacion'
      -- cast protegido (Codex #12): un es_demo malformado en la foto no tumba la tarjeta
      and coalesce(c.es_demo, case when (l.detalle ->> 'es_demo') in ('true', 'false') then (l.detalle ->> 'es_demo')::boolean end, false) = false
      and l.registrado_en >= v_ini and l.registrado_en < v_fin
  ), efectivos as materialized (
    -- La REVISIÓN EFECTIVA de cada contrato al corte: su última observación del periodo (una corrección no suma dos veces;
    -- Codex R2 #9). registrado_en se fija al COMMIT (trigger diferido), así que ordena por confirmación; desempate por id.
    select distinct on (e.contrato_id) e.*
    from eventos e
    order by e.contrato_id, e.secuencia desc
  ), calc as materialized (
    -- Casts PROTEGIDOS (Codex R2 #12): un detalle malformado no tumba la tarjeta; se cuenta como no calculable.
    select e.*,
           (e.tasa_final - e.tasa_base) as puntos,
           case when (e.detalle ->> 'capital') ~ '^[0-9]+(\.[0-9]+)?$' then (e.detalle ->> 'capital')::numeric end as capital,
           case when (e.detalle ->> 'moneda') in ('PEN', 'USD') then e.detalle ->> 'moneda' end as moneda,
           case when (e.detalle ->> 'plazo_dias') ~ '^[1-9][0-9]*$' then (e.detalle ->> 'plazo_dias')::numeric end as plazo_dias,
           case when (e.detalle ->> 'analista_cierre_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.detalle ->> 'analista_cierre_id')::uuid
                when (e.detalle ->> 'creado_por') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.detalle ->> 'creado_por')::uuid end as analista_id,
           e.detalle ->> 'motivo' as motivo,
           coalesce(((e.detalle ->> 'capital') ~ '^[0-9]+(\.[0-9]+)?$') and ((e.detalle ->> 'moneda') in ('PEN', 'USD'))
                    and ((e.detalle ->> 'plazo_dias') ~ '^[1-9][0-9]*$'), false) as calculable
    from efectivos e
  ), calc2 as materialized (
    -- Importes SOLO cuando la foto es completa (Codex R2 #12): nada de 365 días por defecto ni ceros aparentes.
    select c.*,
           case when c.calculable and c.puntos > 0 then c.capital * c.puntos / 100 * c.plazo_dias / 365 end as cedido,
           case when c.calculable and c.puntos < 0 then c.capital * (-c.puntos) / 100 * c.plazo_dias / 365 end as retenido
    from calc c
  ), tot as (
    select (select count(*) from eventos)::int as eventos,
           (select count(*) filter (where operacion = 'UPDATE') from eventos)::int as correcciones,
           count(*)::int as contratos,
           count(*) filter (where divergente)::int as divergentes,
           count(*) filter (where puntos > 0)::int as ceden,
           count(*) filter (where puntos < 0)::int as retienen,
           count(*) filter (where regla = 'sin_regla')::int as sin_regla,
           count(*) filter (where calculable is not true)::int as importe_no_calculable,
           round(coalesce(avg(puntos) filter (where puntos > 0), 0), 2) as puntos_promedio_cedido,
           -- Sumas SIN redondear (la conciliación entre bloques compara estas; el redondeo es solo de presentación; Codex R2 #24)
           coalesce(sum(cedido) filter (where moneda = 'PEN'), 0) as cedido_pen,
           coalesce(sum(cedido) filter (where moneda = 'USD'), 0) as cedido_usd,
           coalesce(sum(retenido) filter (where moneda = 'PEN'), 0) as retenido_pen,
           coalesce(sum(retenido) filter (where moneda = 'USD'), 0) as retenido_usd
    from calc2
  ), por_regla as (
    select jsonb_agg(jsonb_build_object('regla', regla, 'contratos', n, 'observados', n, 'divergentes', d,
             'cedido_pen', round(cp, 2), 'cedido_usd', round(cu, 2), 'retenido_pen', round(rp, 2), 'retenido_usd', round(ru, 2)) order by n desc) as j,
           coalesce(sum(n), 0)::int as suma, coalesce(sum(cp), 0) as cp, coalesce(sum(cu), 0) as cu, coalesce(sum(rp), 0) as rp, coalesce(sum(ru), 0) as ru
    from (select regla, count(*)::int as n, count(*) filter (where divergente)::int as d,
                 coalesce(sum(cedido) filter (where moneda = 'PEN'), 0) as cp, coalesce(sum(cedido) filter (where moneda = 'USD'), 0) as cu,
                 coalesce(sum(retenido) filter (where moneda = 'PEN'), 0) as rp, coalesce(sum(retenido) filter (where moneda = 'USD'), 0) as ru
          from calc2 group by regla) x
  ), por_analista as (
    select jsonb_agg(jsonb_build_object(
             'analista_id', analista_id, 'analista_nombre', nombre, 'contratos', n, 'observados', n, 'divergentes', d,
             'puntos_promedio_cedido', pp, 'cedido_pen', round(cp, 2), 'cedido_usd', round(cu, 2), 'retenido_pen', round(rp, 2), 'retenido_usd', round(ru, 2)) order by cp desc, cu desc, n desc) as j,
           coalesce(sum(n), 0)::int as suma, coalesce(sum(cp), 0) as cp, coalesce(sum(cu), 0) as cu, coalesce(sum(rp), 0) as rp, coalesce(sum(ru), 0) as ru
    from (
      select c.analista_id, coalesce(p.nombre_completo, 'Sin analista') as nombre,
             count(*)::int as n, count(*) filter (where c.divergente)::int as d,
             round(coalesce(avg(c.puntos) filter (where c.puntos > 0), 0), 2) as pp,
             coalesce(sum(c.cedido) filter (where c.moneda = 'PEN'), 0) as cp, coalesce(sum(c.cedido) filter (where c.moneda = 'USD'), 0) as cu,
             coalesce(sum(c.retenido) filter (where c.moneda = 'PEN'), 0) as rp, coalesce(sum(c.retenido) filter (where c.moneda = 'USD'), 0) as ru
      from calc2 c left join public.perfiles p on p.id = c.analista_id
      group by c.analista_id, p.nombre_completo
    ) y
  ), sin_regla as (
    select jsonb_agg(jsonb_build_object('motivo', motivo, 'n', n) order by n desc) as j
    from (select coalesce(motivo, 'sin_motivo') as motivo, count(*)::int as n from calc2 where regla = 'sin_regla' group by 1) z
  ), ultimos as (
    select jsonb_agg(jsonb_build_object(
             'contrato_id', c.contrato_id, 'numero_contrato', c.numero_contrato, 'cliente_nombre', cl.nombre_completo,
             'analista_nombre', coalesce(an.nombre_completo, 'Sin analista'), 'categoria', c.categoria, 'regla', c.regla,
             'tasa_base', c.tasa_base, 'tasa_final', c.tasa_final, 'puntos', c.puntos, 'capital', c.capital, 'moneda', c.moneda,
             'cedido', round(c.cedido, 2), 'operacion', c.operacion, 'registrado_en', c.registrado_en) order by c.registrado_en desc) as j
    from (select * from calc2 where divergente order by secuencia desc limit 10) c
    left join public.perfiles cl on cl.id = c.cliente_id
    left join public.perfiles an on an.id = c.analista_id
  ), huecos as (
    -- Cobertura de ALTAS: desde la activación de R2 (hito), toda alta no demo del periodo debe tener observación.
    -- Las anteriores a la activación no son huecos (Codex R2 #10). La cobertura de CORRECCIONES no se puede medir aquí.
    select count(*)::int as altas_sin_observar
    from public.contratos c
    where not c.es_demo
      and v_act is not null
      and c.creado_en >= greatest(v_ini, v_act) and c.creado_en < v_fin
      -- La cobertura exige la observación del ALTA (evento INSERT); una corrección posterior no la sustituye (Codex R2 #11).
      and not exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = c.id and l.origen = 'observacion' and l.detalle ->> 'evento' = 'INSERT')
  )
  select jsonb_build_object(
    'version', 1,
    'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta),
    'cobertura', jsonb_build_object(
      'observacion_activa_desde', v_act,
      'cobertura_desde', case when v_act is null then null else greatest(v_ini, v_act) end,
      'periodo_sin_cobertura', (v_act is null or v_act > v_ini)),
    'politica', case when v_pol.id is null then null else jsonb_build_object('version', v_pol.version, 'modo', v_pol.modo, 'tasa_base_nueva', v_pol.tasa_base_nueva) end,
    'totales', jsonb_build_object(
      'eventos', t.eventos, 'contratos', t.contratos, 'observados', t.contratos,
      'divergentes', t.divergentes, 'ceden', t.ceden, 'retienen', t.retienen,
      'sin_regla', t.sin_regla, 'correcciones', t.correcciones, 'importe_no_calculable', t.importe_no_calculable,
      'puntos_promedio_cedido', t.puntos_promedio_cedido,
      'cedido', jsonb_build_object('PEN', round(t.cedido_pen, 2), 'USD', round(t.cedido_usd, 2)),
      'retenido', jsonb_build_object('PEN', round(t.retenido_pen, 2), 'USD', round(t.retenido_usd, 2))),
    'por_regla', coalesce(r.j, '[]'::jsonb),
    'por_analista', coalesce(a.j, '[]'::jsonb),
    'sin_regla', coalesce(s.j, '[]'::jsonb),
    'ultimos_divergentes', coalesce(u.j, '[]'::jsonb),
    -- Método declarado: interés simple sobre el plazo, sobre la REVISIÓN EFECTIVA de cada contrato al corte.
    'metodo', 'simple_sobre_plazo_revision_efectiva',
    'altas_sin_observar', h.altas_sin_observar,
    -- Sondas separadas (Codex R2 #11): consistencia interna (los bloques cuadran con el total, también en importes),
    -- cobertura de altas (ninguna alta desde la activación sin observar) y cobertura de correcciones (no medible aquí).
    'sondas', jsonb_build_object(
      'consistencia_interna', (t.contratos = r.suma and t.contratos = a.suma and t.divergentes = t.ceden + t.retienen
                               and abs(t.cedido_pen - r.cp) < 0.0001 and abs(t.cedido_pen - a.cp) < 0.0001 and abs(t.cedido_usd - r.cu) < 0.0001 and abs(t.cedido_usd - a.cu) < 0.0001
                               and abs(t.retenido_pen - r.rp) < 0.0001 and abs(t.retenido_pen - a.rp) < 0.0001 and abs(t.retenido_usd - r.ru) < 0.0001 and abs(t.retenido_usd - a.ru) < 0.0001),
      'cobertura_altas', (v_act is not null and h.altas_sin_observar = 0),
      'cobertura_correcciones', 'desconocida'),
    'coherente', (t.contratos = r.suma and t.contratos = a.suma and t.divergentes = t.ceden + t.retienen
                  and abs(t.cedido_pen - r.cp) < 0.0001 and abs(t.cedido_pen - a.cp) < 0.0001 and abs(t.cedido_usd - r.cu) < 0.0001 and abs(t.cedido_usd - a.cu) < 0.0001
                  and abs(t.retenido_pen - r.rp) < 0.0001 and abs(t.retenido_pen - a.rp) < 0.0001 and abs(t.retenido_usd - r.ru) < 0.0001 and abs(t.retenido_usd - a.ru) < 0.0001
                  and v_act is not null and h.altas_sin_observar = 0),
    'generado_en', statement_timestamp()
  ) into v_payload
  from tot t, por_regla r, por_analista a, sin_regla s, ultimos u, huecos h;
  return v_payload;
end;
$function$;
revoke all on function crm.observacion_rentabilidad_fn(date, date) from public, anon, service_role;
grant execute on function crm.observacion_rentabilidad_fn(date, date) to authenticated;
comment on function crm.observacion_rentabilidad_fn(date, date) is
  'Rentabilidad R2: la tarjeta de Gerencia (y Directorio): observaciones del ledger en el periodo (por defecto 30 días; máx 366; hasta <= hoy). Cuenta EVENTOS y CONTRATOS; los importes (margen cedido/retenido en el plazo por moneda, por regla y por analista) salen de la REVISIÓN EFECTIVA de cada contrato al corte y solo de fotos completas (`importe_no_calculable` cuenta el resto). Demo excluido por la marca actual del contrato. Sondas separadas (consistencia_interna, cobertura_altas desde el hito de activación, cobertura_correcciones desconocida) y `coherente`. 42501 para el resto.';

-- ---------------------------------------------------------------------------
-- 4. POSTFLIGHT
-- ---------------------------------------------------------------------------
do $post$
declare v_f text;
begin
  for v_f in select firma from _r2_puertas g
             where g.h is distinct from (select md5(p.prosrc) from pg_proc p where p.oid = g.fnoid) loop
    raise exception 'POSTFLIGHT R2: la puerta % cambió durante la migración', v_f;
  end loop;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_zz_observar_rentabilidad'
                 and t.tgenabled = 'O' and t.tgdeferrable and t.tginitdeferred and t.tgconstraint <> 0
                 and (t.tgtype & 2) = 0 and (t.tgtype & 4) > 0 and (t.tgtype & 16) > 0 and (t.tgtype & 8) = 0) then
    raise exception 'POSTFLIGHT R2: el observador no quedó como AFTER INSERT/UPDATE, constraint, diferido y habilitado';
  end if;
  if to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)') is null
     or to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz)') is null then
    raise exception 'POSTFLIGHT R2: falta alguna firma del núcleo';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_zz_observar_rentabilidad'
                 and array_length(t.tgattr::int2[], 1) = 7) then
    raise exception 'POSTFLIGHT R2: el observador no vigila las 7 columnas que determinan regla y margen';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'ledger_rentabilidad' and column_name = 'secuencia') then
    raise exception 'POSTFLIGHT R2: falta ledger_rentabilidad.secuencia';
  end if;
  if not exists (select 1 from crm.rentabilidad_hitos where clave = 'observacion_activa_desde' and (valor ->> 'migracion') = '20260906180000')
     or not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'crm' and c.relname = 'rentabilidad_hitos' and c.relrowsecurity)
     or has_table_privilege('authenticated', 'crm.rentabilidad_hitos', 'INSERT') or has_table_privilege('anon', 'crm.rentabilidad_hitos', 'SELECT') then
    raise exception 'POSTFLIGHT R2: el hito de activación no quedó (o su RLS/grants no son «solo SELECT para authenticated»)';
  end if;
  for v_f in select unnest(array['private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)', 'private.resolver_tasa(uuid,text,uuid,timestamptz)',
                                 'private.trg_contratos_observar_rentabilidad()']) loop
    if not exists (select 1 from pg_proc p where p.oid = v_f::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']) then
      raise exception 'POSTFLIGHT R2: % no es DEFINER de postgres con search_path vacío', v_f;
    end if;
    if has_function_privilege('authenticated', v_f, 'EXECUTE') or has_function_privilege('anon', v_f, 'EXECUTE')
       or has_function_privilege('service_role', v_f, 'EXECUTE')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f::regprocedure and a.grantee = 0) then
      raise exception 'POSTFLIGHT R2: % tiene EXECUTE para la API o PUBLIC', v_f;
    end if;
  end loop;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.observacion_rentabilidad_fn(date,date)'::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""'])
     or not has_function_privilege('authenticated', 'crm.observacion_rentabilidad_fn(date,date)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.observacion_rentabilidad_fn(date,date)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.observacion_rentabilidad_fn(date,date)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.observacion_rentabilidad_fn(date,date)'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT R2: crm.observacion_rentabilidad_fn no es DEFINER de postgres «solo authenticated»';
  end if;
  -- Sonda de comportamiento del envoltorio: la firma de R1 sigue delegando (con cliente nulo el núcleo lanza 22023, y SOLO eso).
  begin
    perform private.resolver_tasa(null::uuid, 'nuevo', null::uuid, statement_timestamp());
    raise exception 'POSTFLIGHT R2: el envoltorio de 4 argumentos no delegó (debía lanzar 22023 con cliente nulo)';
  exception when sqlstate '22023' then
    null;   -- la respuesta esperada del núcleo
  end;
  raise notice 'RENTABILIDAD R2 OK: observador diferido montado en public.contratos, núcleo con p_contrato_nuevo_id (envoltorio de R1 intacto en comportamiento), tarjeta crm.observacion_rentabilidad_fn; las 5 puertas de escritura intactas. No bloquea nada.';
end
$post$;
commit;
