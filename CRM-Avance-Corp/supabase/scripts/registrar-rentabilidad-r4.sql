-- REGISTRO en supabase_migrations.schema_migrations de RENTABILIDAD R4 (20260907093000).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si CUALQUIER
-- pieza del candado no lleva exactamente el cuerpo de esta versión (los cuatro helpers incluidos: certificar por
-- existencia dejaría pasar una instalación alterada), si el trigger no vigila las 11 columnas de la huella, o si la
-- versión ya está registrada con otro contenido. md5 del archivo 32f6e3ef1107ad6c6aaf13596c7eb487.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r4'));
do $chk$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_contratos_observar_rentabilidad()')) is distinct from '0e73d5d01bf7aa3c1e39368a1cb20cd3'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)')) is distinct from 'a363ad7e514c8eef3257acd7a1a54d44'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.solicitar_tasa_fn(jsonb)')) is distinct from '0e2b20efbc05c5facd8769bc5ae88164'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from 'ec070a86678c3a952ed15b3fc7d7cafd'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.observacion_rentabilidad_fn(date,date)')) is distinct from '014c621343975e35202e0587e35f443a' then
    raise exception 'REGISTRO R4: alguna pieza no lleva el cuerpo de esta versión (observador 0e73d5d0…, puerta a363ad7e…, solicitar 0e2b20ef…, publicar ec070a86…, tarjeta 014c6213…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.rentabilidad_tasa_txt(numeric)')) is distinct from '66684670065a5544e3142087a4fa3a4c' then
    raise exception 'REGISTRO R4: private.rentabilidad_tasa_txt(numeric) no lleva el cuerpo de esta versión (66684670…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.rentabilidad_condicion_declarada(uuid)')) is distinct from '2cf100dd0fbf1b0f078a156611137028' then
    raise exception 'REGISTRO R4: private.rentabilidad_condicion_declarada(uuid) no lleva el cuerpo de esta versión (2cf100dd…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.rentabilidad_origen_declarado(public.contratos)')) is distinct from '1c6c299a611ef933d39e9279e17ae1c9' then
    raise exception 'REGISTRO R4: private.rentabilidad_origen_declarado(public.contratos) no lleva el cuerpo de esta versión (1c6c299a…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)')) is distinct from '920c105bb3f116f41bd50e2a8223b4f8' then
    raise exception 'REGISTRO R4: private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz) no lleva el cuerpo de esta versión (920c105b…)';
  end if;
  if not exists (
    select 1 from pg_trigger t
    where t.tgname = 'trg_contratos_zz_observar_rentabilidad' and t.tgrelid = 'public.contratos'::regclass
      and t.tgdeferrable and t.tginitdeferred and t.tgenabled = 'O'
      and t.tgfoid = to_regprocedure('private.trg_contratos_observar_rentabilidad()')
      and (select count(*) from unnest(t.tgattr::int2[]) a) = 11) then
    raise exception 'REGISTRO R4: el trigger del candado no está diferido, habilitado y vigilando las 11 columnas';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260907093000' and coalesce(md5(statements[1]), '') <> '32f6e3ef1107ad6c6aaf13596c7eb487') then
    raise exception 'REGISTRO R4: la versión 20260907093000 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260907093000', 'crm_rentabilidad_r4_enforcement_candado_servidor', array[$m$-- ===================================================================
-- CRM · RENTABILIDAD SERVER-SIDE · R4 — EL CANDADO DEL SERVIDOR (enforcement)
-- ===================================================================
-- Cierra el plan «la tasa la decide la política» (vault: Plan Rentabilidad server-side, 2026-09-06, D1–D6).
-- R1 puso el núcleo, las solicitudes y el libro; R2 observó cada alta sin bloquear; R3 dejó al analista y a Gerencia
-- trabajar la tasa desde el CRM. Nada impedía que una llamada directa a la RPC, el portal o una pantalla vieja
-- pusieran la tasa que quisieran. Eso termina aquí.
--
-- CÓMO. El candado NO reescribe las cinco puertas de escritura: vive donde ya vive el observador de R2, en el trigger
-- diferido de public.contratos, así que cubre TODA vía (CRM, portal, RPC antigua, SQL directo) con un solo texto — la
-- regla de una sola fuente en el servidor. Al commit ese trigger ya sabe qué tasa corresponde (núcleo
-- private.resolver_tasa) y qué tasa quedó; R4 añade la decisión:
--   · política en «observacion»  → EXACTAMENTE lo de R2: mide, anota y jamás aborta un alta.
--   · política en «enforcement»  → rechaza (P0410) cuando la tasa que quedó no es la resuelta y no hay una
--     autorización VIVA de Gerencia para la MISMA huella (cliente, categoría, origen, producto declarado, capital,
--     moneda, modalidad, tipo de interés, fechas), que se consume de un solo uso en esa misma transacción.
-- El interruptor es la política: crm.publicar_politica_rentabilidad_fn ya admite modo=enforcement (R1 lo rechazaba
-- con 0A000). La vuelta atrás es publicar otra versión en «observacion»: NO hace falta migración ni reversa.
--
-- QUÉ TRAE
--   1. private.rentabilidad_tasa_txt / private.rentabilidad_condicion_declarada — la tasa en texto para los mensajes,
--      y la condición de producto que el formulario PUDO declarar (NULL en un contrato legacy, cuyo snapshot lo
--      sintetiza el puente al insertar y lo recrea al cambiar términos; el id real en un producto de catálogo).
--   2. private.rentabilidad_origen_declarado — de qué contrato hereda la tasa: renovación desde
--      crm.operaciones_cartera (como R2) y upgrade desde el GUC transaccional crm.rentabilidad_origen_upgrade que
--      publica la puerta del CRM (D2), de UN SOLO USO y sin autorreferencia ni mezcla de datos de prueba.
--   3. private.rentabilidad_consumir_autorizacion — busca y consume la autorización que ampara la tasa.
--   4. private.trg_contratos_observar_rentabilidad — observador + candado.
--   5. crm.crear_contrato_con_cuenta_pdf_v2 — ÚNICO cambio en una puerta: el set_config del origen del upgrade (mismo
--      patrón que clave_idempotencia; la cadena de abajo recibe lo que recibía). Su texto es el MISMO en producción y
--      en el banco, así que esta migración no cuela cambios de nadie. public.crear_contrato NO se toca a propósito:
--      su texto difiere entre banco y producción (D-19 y el cambio del 07/09 de otra sesión).
--   6. crm.solicitar_tasa_fn — admite `contrato_id` (contexto de CORRECCIÓN) para que el núcleo acepte un origen «ya
--      renovado POR ese contrato». Sin esto no se podía ni PEDIR autorización para corregir la tasa de una renovación.
--   7. crm.publicar_politica_rentabilidad_fn — admite enforcement. Es el interruptor.
--   8. crm.observacion_rentabilidad_fn — la tarjeta de Gerencia cuenta también las filas origen=enforcement (si no,
--      encender el candado la dejaría en cero justo en las horas en que hay que vigilarla).
--   9. El trigger se RECREA para vigilar además modalidad, tipo de interés, producto y la marca de prueba.
--  10. Hito crm.rentabilidad_hitos('enforcement_construido_desde').
--
-- LO QUE NO HACE. No enciende nada: la política sigue en «observacion» al terminar (el postflight lo exige).
-- Encenderlo es de Gerencia, desde Configuración → Política de rentabilidad (48 h de observación antes de darlo por
-- bueno). Y NO revalida los contratos que ya existen: el candado juzga lo que se escribe desde que se enciende.
--
-- LÍMITES DECLARADOS (revisión adversarial de Codex sobre R4, 07/09):
--   · Si el fallo impide incluso LEER el modo de la política, el contrato pasa (fallar cerrado ahí convertiría un
--     problema al leer una tabla de una fila en una parada de todas las altas con el candado apagado). El contrato
--     queda sin fila en el libro, así que la tarjeta de Gerencia lo cuenta como hueco de cobertura.
--   · Los rechazos no dejan rastro en la base (la transacción se deshace): se cuentan por la telemetría de errores del
--     front (código TASA_FUERA_DE_POLITICA) y por el log de Postgres, no por el libro.
--   · Publicar el modo no es una frontera instantánea: una transacción en vuelo que ya leyó «observacion» puede
--     confirmar después. Con el trigger al commit la ventana es de milisegundos.
--   · Una futura suscripción lógica escribiría sin disparar este trigger; habría que decidir el candado en el destino.
--
-- APLICAR: npx supabase db query --linked --file <este archivo>   (no registra: correr después
--          scripts/registrar-rentabilidad-r4.sql). REVERSA: scripts/rollback-rentabilidad-r4.sql.
-- OJO: mientras R4 esté aplicada, rollback-rentabilidad-r2.sql se NIEGA (el observador ya no lleva el cuerpo de R2).
--      La cadena correcta es reversa de R4 y después la de R2.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r4'));

do $pre$
begin
  if to_regprocedure('private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)') is not null then
    raise exception 'RENTABILIDAD R4: ya está aplicada (existe private.rentabilidad_consumir_autorizacion)';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260907093000') then
    raise exception 'RENTABILIDAD R4: la versión 20260907093000 ya está registrada';
  end if;
  if to_regclass('crm.politica_rentabilidad') is null or to_regclass('crm.solicitudes_tasa') is null
     or to_regclass('crm.ledger_rentabilidad') is null or to_regprocedure('crm.solicitudes_tasa_fn(text[],integer,boolean,uuid)') is null then
    raise exception 'RENTABILIDAD R4: faltan objetos de R1 o R3 (aplica 20260906170000, 20260906180000 y 20260906220000 antes)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)')) is distinct from 'a3f043fb2b4c76ecbb59e5e3e98e3ba0' then
    raise exception 'RENTABILIDAD R4: el núcleo private.resolver_tasa(5 args) no es el de R2 (a3f043fb…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_contratos_observar_rentabilidad()')) is distinct from '8cd6c5bb1e9a51e4b20d2a6e90bedeb0' then
    raise exception 'RENTABILIDAD R4: el observador no lleva el cuerpo de R2 (8cd6c5bb…): hay otra versión encima';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.solicitar_tasa_fn(jsonb)')) is distinct from '1db7a86959289e9168147595bd6a1a3f' then
    raise exception 'RENTABILIDAD R4: crm.solicitar_tasa_fn no lleva el cuerpo de R1 (1db7a869…)';
  end if;
  -- La tarjeta puede llevar el cuerpo de R2 o el de R4: la reversa de R4 la deja A PROPÓSITO contando las dos orillas
  -- (las filas origen=enforcement del libro son reales), así que reaplicar R4 sobre eso es legítimo.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.observacion_rentabilidad_fn(date,date)'))
       not in ('b059dd6dc80681970dd44ce2946a9572', '014c621343975e35202e0587e35f443a') then
    raise exception 'RENTABILIDAD R4: la tarjeta crm.observacion_rentabilidad_fn no lleva el cuerpo de R2 ni el de R4 (b059dd6d… / 014c6213…)';
  end if;
  -- El hotfix del conflicto de versión va ANTES (si no, publicar enforcement colgaría 125 s en PostgREST).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from '5519377757c09621da1671fb60b9f49f' then
    raise exception 'RENTABILIDAD R4: falta el hotfix 20260906233000 en crm.publicar_politica_rentabilidad_fn (55193777…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)')) is distinct from '0fd6fa8d1d8f8106cb52662cb64193e0' then
    raise exception 'RENTABILIDAD R4: crm.crear_contrato_con_cuenta_pdf_v2 no lleva el texto esperado (0fd6fa8d…): revisa si otra sesión la cambió';
  end if;
  if (select p.modo from private.politica_rentabilidad_vigente(statement_timestamp()) p) is distinct from 'observacion' then
    raise exception 'RENTABILIDAD R4: la política vigente no está en observacion; R4 no debe aplicarse con el candado ya encendido';
  end if;
  if to_regprocedure('private.huella_solicitud_tasa(uuid,text,uuid,uuid,numeric,text,text,text,date,date)') is null then
    raise exception 'RENTABILIDAD R4: falta private.huella_solicitud_tasa (R1)';
  end if;
  if to_regclass('crm.producto_condiciones') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'producto_condiciones' and column_name = 'es_legacy') then
    raise exception 'RENTABILIDAD R4: falta crm.producto_condiciones.es_legacy (catálogo)';
  end if;
end
$pre$;

-- ---------------------------------------------------------------------------
-- 1. Utilidades del candado
-- ---------------------------------------------------------------------------
-- La tasa como la escribe una persona: 15, 16.5, 18.25 (sin el punto suelto que deja FM).
create or replace function private.rentabilidad_tasa_txt(p_tasa numeric)
returns text
language sql immutable set search_path = ''
as $function$
  select rtrim(rtrim(trim(to_char(p_tasa, 'FM999990.99')), '0'), '.')
$function$;
revoke all on function private.rentabilidad_tasa_txt(numeric) from public, anon, authenticated, service_role;
comment on function private.rentabilidad_tasa_txt(numeric) is
  'Rentabilidad R4: la tasa en texto para los mensajes del candado (15, 16.5), sin ceros ni punto sobrantes.';

-- La condición de producto DECLARADA de un contrato, para la huella de una autorización. El puente legacy sintetiza un
-- snapshot en el momento de insertar —y otro distinto cada vez que cambian los términos—, así que ese id NO lo puede
-- conocer el formulario cuando pide la autorización: para la huella, un contrato legacy declara NULL. Un producto de
-- catálogo sí se declara con su id, y ahí la coincidencia es estricta (Codex R4 #2: admitir NULL para todo dejaría que
-- una solicitud sin producto amparara un producto comercial concreto).
create or replace function private.rentabilidad_condicion_declarada(p_condicion uuid)
returns uuid
language sql stable security definer set search_path = ''
as $function$
  select case
           when p_condicion is null then null
           when exists (select 1 from crm.producto_condiciones pc where pc.id = p_condicion and pc.es_legacy) then null
           else p_condicion
         end
$function$;
revoke all on function private.rentabilidad_condicion_declarada(uuid) from public, anon, authenticated, service_role;
comment on function private.rentabilidad_condicion_declarada(uuid) is
  'Rentabilidad R4: la condición de producto que el formulario PUDO declarar al pedir la autorización — NULL si es un snapshot legacy del puente (el puente lo sintetiza al insertar y lo RECREA en cada cambio de términos, así que nadie puede predecirlo), y el id real si es un producto de catálogo. Se usa en las dos orillas de la huella y para comparar si la condición DECLARADA cambió: un re-snapshot legacy no cambia nada (null → null), pero cambiar de producto de catálogo sí.';

-- ---------------------------------------------------------------------------
-- 2. El ORIGEN DECLARADO (D2): de qué contrato hereda la tasa este contrato
-- ---------------------------------------------------------------------------
-- Renovación: lo registra la puerta en crm.operaciones_cartera (así lo lee R2 desde el primer día).
-- Upgrade: hasta R3 nadie lo registraba y el observador solo podía APUNTAR un candidato. Ahora la puerta del CRM
-- publica el origen que eligió el analista en un GUC TRANSACCIONAL «cliente_id|contrato_origen_id».
-- La lectura es de UN SOLO USO (consume el GUC): si una transacción creara dos upgrades, el segundo no puede heredar
-- la declaración del primero — se queda sin origen y bajo enforcement se rechaza (Codex R4 #5).
-- Se rechaza además el origen que sea el propio contrato (autorreferencia) y el que no comparta la marca de prueba
-- (un contrato de ensayo no puede prestar su tasa a uno real; Codex R4 #6).
create or replace function private.rentabilidad_origen_declarado(p_contrato public.contratos)
returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_guc text := nullif(btrim(coalesce(current_setting('crm.rentabilidad_origen_upgrade', true), '')), '');
  v_id  uuid;
  v_ok  boolean;
begin
  if p_contrato.categoria = 'renovacion' then
    select o.contrato_origen_id into v_id
    from crm.operaciones_cartera o
    where o.contrato_nuevo_id = p_contrato.id and o.tipo = 'renovacion';
    return v_id;
  end if;
  if p_contrato.categoria <> 'upgrade' or v_guc is null then
    return null;
  end if;
  perform set_config('crm.rentabilidad_origen_upgrade', '', true);   -- un solo uso
  if split_part(v_guc, '|', 1) is distinct from p_contrato.cliente_id::text then
    return null;   -- declarado para otro cliente
  end if;
  begin
    v_id := split_part(v_guc, '|', 2)::uuid;
  exception when others then
    return null;
  end;
  if v_id = p_contrato.id then
    return null;   -- un contrato no se amplía a sí mismo
  end if;
  select (c.es_demo is not distinct from p_contrato.es_demo) into v_ok
  from public.contratos c where c.id = v_id;
  if v_ok is not true then
    return null;   -- no existe, o mezcla ensayo con real
  end if;
  return v_id;
end;
$function$;
revoke all on function private.rentabilidad_origen_declarado(public.contratos) from public, anon, authenticated, service_role;
comment on function private.rentabilidad_origen_declarado(public.contratos) is
  'Rentabilidad R4 (D2): el contrato del que este hereda la tasa, DECLARADO por la puerta — renovación: crm.operaciones_cartera; upgrade: GUC transaccional crm.rentabilidad_origen_upgrade («cliente_id|contrato_origen_id»), de UN SOLO USO (se limpia al leerlo, para que un segundo upgrade de la misma transacción no herede la declaración del primero). Descarta otro cliente, la autorreferencia y mezclar un contrato de prueba con uno real. El resto de la validación (existe, activo, no renovado) es del único núcleo, private.resolver_tasa.';

-- ---------------------------------------------------------------------------
-- 3. CONSUMIR una autorización de Gerencia (un solo uso, misma huella, en esta transacción)
-- ---------------------------------------------------------------------------
-- Devuelve la autorización consumida, o NULL si no hay ninguna que ampare esta tasa. Exige:
--   · misma HUELLA que la intención autorizada (private.huella_solicitud_tasa: cliente, categoría, origen, producto
--     declarado, capital, moneda, modalidad, tipo de interés y las dos fechas). Si el contrato cambió, no aplica;
--   · viva: aprobada o aceptada_por_analista (un tope sin aceptar NO habilita nada) y sin vencer;
--   · base <= tasa <= tope autorizado, midiendo la base RESUELTA AHORA. No se exige que la base sea idéntica a la que
--     tenía la solicitud (Codex R4 #3): si la política subió la base entre la autorización y el alta, el suelo nuevo
--     manda (D4) y el techo autorizado sigue siendo el de Gerencia; si el suelo pasa a superar el techo, no pasa.
-- El «for update» serializa dos altas concurrentes: la segunda relee la fila ya consumida, no la encuentra y su
-- contrato se rechaza. Doble consumo imposible.
create or replace function private.rentabilidad_consumir_autorizacion(
  p_contrato public.contratos, p_base numeric, p_origen uuid, p_condicion uuid, p_ahora timestamptz
)
returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_huella text;
  v_s      crm.solicitudes_tasa;
  v_previo text;
  v_n      integer;
begin
  if p_contrato.id is null or p_base is null or p_contrato.tasa_anual is null then
    return null;
  end if;
  v_huella := private.huella_solicitud_tasa(p_contrato.cliente_id, p_contrato.categoria, p_origen, p_condicion,
    p_contrato.capital, p_contrato.moneda, p_contrato.modalidad, p_contrato.tipo_interes,
    p_contrato.fecha_inicio, p_contrato.fecha_vencimiento);

  select s.* into v_s
  from crm.solicitudes_tasa s
  where s.huella = v_huella
    and s.cliente_id = p_contrato.cliente_id
    and s.estado in ('aprobada', 'aceptada_por_analista')
    and s.vence_en >= p_ahora
    and s.tasa_maxima_autorizada >= p_contrato.tasa_anual
    and p_contrato.tasa_anual >= p_base
  order by s.resuelta_en desc nulls last, s.solicitada_en desc
  limit 1
  for update;
  if v_s.id is null then
    return null;
  end if;

  -- El sello lo escribe la puerta: crm.solicitudes_tasa solo se deja tocar con este GUC (trigger de R1).
  v_previo := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  update crm.solicitudes_tasa s
     set estado = 'consumida', consumida_en = p_ahora, contrato_id = p_contrato.id, actualizado_en = p_ahora
   where s.id = v_s.id and s.estado in ('aprobada', 'aceptada_por_analista');
  get diagnostics v_n = row_count;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  if v_n = 0 then
    return null;   -- alguien la consumió entre el select y el update: este contrato no pasa
  end if;
  return jsonb_build_object(
    'solicitud_id', v_s.id,
    'huella', v_s.huella,
    'tasa_base_solicitud', v_s.tasa_base,
    'tasa_base_ahora', p_base,
    'tasa_solicitada', v_s.tasa_solicitada,
    'tasa_maxima_autorizada', v_s.tasa_maxima_autorizada,
    'solicitada_por', v_s.solicitada_por,
    'resuelta_por', v_s.resuelta_por,
    'consumida_en', p_ahora);
end;
$function$;
revoke all on function private.rentabilidad_consumir_autorizacion(public.contratos, numeric, uuid, uuid, timestamptz) from public, anon, authenticated, service_role;
comment on function private.rentabilidad_consumir_autorizacion(public.contratos, numeric, uuid, uuid, timestamptz) is
  'Rentabilidad R4: busca y CONSUME (estado consumida, un solo uso) la autorización viva de Gerencia que ampara la tasa de este contrato — misma huella (con la condición DECLARADA: NULL para legacy, el id real para catálogo), estado aprobada o aceptada_por_analista, sin vencer, y base_resuelta_ahora <= tasa <= tope autorizado (D4). NULL si no hay ninguna. El «for update» hace imposible el doble consumo: la segunda transacción no la encuentra y su contrato se rechaza.';

-- ---------------------------------------------------------------------------
-- 4. EL OBSERVADOR pasa a ser OBSERVADOR + CANDADO (mismo trigger diferido de R2)
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
  -- R4 (el candado)
  v_modo       text;               -- modo de la política vigente (null = no se pudo leer)
  v_enforce    boolean := false;
  v_anotar     boolean := true;    -- ¿toca escribir la fila del libro en esta transacción?
  v_en_juego   boolean := false;   -- ¿esta transacción fija o altera la tasa (o la intención que la amparaba)?
  v_huella_mov boolean := false;   -- ¿cambió alguna dimensión de la huella autorizada?
  v_rechazo    text;               -- motivo del rechazo (se lanza FUERA del manejador)
  v_origen_dec uuid;               -- origen DECLARADO por la puerta (upgrade, D2)
  v_cond       uuid;               -- condición DECLARADA (null cuando es el snapshot legacy del puente)
  v_aut        jsonb;
  v_solicitud  uuid;
begin
 -- TODO el cuerpo va bajo una excepción externa: el observador no puede abortar un alta ni una corrección. lock_timeout=2s
 -- convierte una espera de candado en 55P03 (atrapable). Lo único que WHEN OTHERS no atrapa es query_canceled (57014):
 -- en PostgreSQL 17 statement_timeout se desactiva antes del commit, y aquí no hay más esperas que las de candado.
 begin
  select * into v_c from public.contratos c where c.id = new.id;
  if v_c.id is null then
    return null;   -- borrado en la misma transacción: nada que observar
  end if;
  -- UNA fila de libro por contrato y transacción: varios eventos (alta + correcciones en la misma tx) → una sola foto
  -- FINAL. El marcador es un GUC transaccional (se fija también cuando el cambio neto es vacío: 15→18→15 no es una
  -- corrección; Codex R2 #25). OJO (Codex R4 #4): el marcador decide solo si se ESCRIBE en el libro; NO exime de
  -- validar. Con SET CONSTRAINTS ALL IMMEDIATE a mitad de transacción el trigger vuelve a dispararse, y antes se
  -- saltaba la comprobación: un alta válida servía de pasaporte a una corrección no autorizada.
  v_anotar := coalesce(current_setting(v_marca, true), '') <> '1';
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
      'fecha_vencimiento', case when old.fecha_vencimiento is distinct from v_c.fecha_vencimiento then jsonb_build_array(old.fecha_vencimiento, v_c.fecha_vencimiento) end,
      -- R4 (Codex #1): la huella de una autorización también lleva modalidad, tipo de interés y producto. Si no se
      -- comparan, una autorización para 20 000 a 12 meses ampara luego 100 000 a 24: bastaba corregir el capital.
      'modalidad',         case when old.modalidad             is distinct from v_c.modalidad             then jsonb_build_array(old.modalidad, v_c.modalidad) end,
      'tipo_interes',      case when old.tipo_interes          is distinct from v_c.tipo_interes          then jsonb_build_array(old.tipo_interes, v_c.tipo_interes) end,
      -- Se compara la condición DECLARADA, no el id crudo: el puente legacy sintetiza un snapshot NUEVO en cada
      -- cambio de términos, y eso no mueve la huella (declarada = null en las dos orillas). Cambiar de producto de
      -- catálogo sí la mueve.
      'producto_condicion_id', case when private.rentabilidad_condicion_declarada(old.producto_condicion_id)
                                      is distinct from private.rentabilidad_condicion_declarada(v_c.producto_condicion_id)
                                    then jsonb_build_array(old.producto_condicion_id, v_c.producto_condicion_id) end,
      -- R4 (Codex #6): pasar un contrato de prueba a real es un cambio de rentabilidad como cualquier otro.
      'es_demo',           case when old.es_demo               is distinct from v_c.es_demo               then jsonb_build_array(old.es_demo, v_c.es_demo) end));
    if v_cambios = '{}'::jsonb then
      return null;
    end if;
  end if;
  v_pol := private.politica_rentabilidad_vigente(statement_timestamp());
  if v_pol.id is null then
    return null;   -- sin política publicada no se observa (R1 garantiza la v1)
  end if;
  -- R4: el interruptor. En «observacion» este trigger hace EXACTAMENTE lo de R2 (mide, no bloquea).
  v_modo := v_pol.modo;
  v_enforce := (v_modo = 'enforcement');

  -- En una CORRECCIÓN que no cambia cliente ni categoría, la base de comparación es la RESOLUCIÓN ORIGINAL del alta
  -- (base, regla, origen), no una reevaluación con el estado de hoy (Codex R2 #8). Si cambió cliente o categoría, se resuelve de nuevo.
  v_pol_id := v_pol.id;
  if tg_op = 'UPDATE' and not (v_cambios ? 'categoria' or v_cambios ? 'cliente_id') then
    -- Solo se conserva una resolución del MISMO cliente y la MISMA categoría (Codex R2 #20), con la política que la produjo (#21).
    select l.tasa_base, l.regla, l.contrato_origen_id, l.politica_id, l.id, l.detalle ->> 'motivo' as motivo into v_prev
    from crm.ledger_rentabilidad l
    where l.contrato_id = v_c.id and l.origen in ('observacion', 'enforcement')
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

  -- El origen declarado se lee UNA sola vez: la lectura consume la declaración, para que un segundo contrato de la
  -- misma transacción no herede la del primero (Codex R4 #5).
  if v_c.categoria = 'upgrade' then
    v_origen_dec := private.rentabilidad_origen_declarado(v_c);
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
      elsif v_c.categoria = 'upgrade' and v_origen_dec is not null then
        -- D2: el upgrade DECLARA el contrato que amplía. R4: la puerta del CRM lo publica y aquí SÍ es una regla
        -- (heredada_upgrade), no una hipótesis.
        v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, v_origen_dec, statement_timestamp(), v_c.id);
        v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla'; v_origen := v_origen_dec;
      elsif v_c.categoria = 'upgrade' then
        -- Sin declaración (portal, RPC antigua, alta anterior a R3) se mantiene lo de R2: solo se apunta el candidato
        -- único —contrato activo del cliente que ya EXISTÍA antes y seguía vigente al inicio del nuevo— como
        -- hipótesis, y queda sin_regla (una inferencia no es una regla; Codex R2 #7). Bajo enforcement se rechaza.
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

  -- ── R4 · EL CANDADO ──────────────────────────────────────────────────────────────────────────────────────────
  -- Solo con la política en enforcement, y nunca sobre datos de prueba. La tasa se juzga cuando ESTA transacción la
  -- fija (alta), la cambia (corrección) o mueve la INTENCIÓN que amparaba una tasa excepcional: conservar una tasa
  -- por encima de la base exige conservar el contrato que Gerencia autorizó (Codex R4 #1).
  if v_enforce and v_c.es_demo is not true then
    v_huella_mov := (tg_op = 'UPDATE') and (v_cambios ?| array['capital', 'moneda', 'fecha_inicio', 'fecha_vencimiento',
                     'modalidad', 'tipo_interes', 'producto_condicion_id', 'categoria', 'cliente_id']);
    v_en_juego := (tg_op = 'INSERT')
      or (v_cambios ? 'tasa_anual')
      -- Pasar de prueba a real es un alta a efectos de la política.
      or (v_cambios ? 'es_demo')
      -- Tasa por encima de la base + intención movida = la autorización ya no ampara esto.
      or (v_huella_mov and v_base is not null and v_c.tasa_anual is distinct from v_base);
    if v_en_juego then
      if v_regla = 'sin_regla' then
        -- Sin regla no hay base con la que comparar: bajo enforcement no pasa, y se dice qué falta.
        v_rechazo := case coalesce(v_motivo, '')
          when 'categoria_nula' then 'El contrato debe declarar su categoría (nuevo, renovación o upgrade).'
          when 'renovacion_sin_origen_registrado' then 'La renovación debe declarar el contrato que renueva.'
          when 'upgrade_origen_inferido' then 'El upgrade debe declarar el contrato que amplía: regístralo desde el CRM.'
          when 'upgrade_origen_ambiguo' then 'El upgrade debe declarar el contrato que amplía: regístralo desde el CRM.'
          when 'upgrade_sin_contrato_activo_previo' then 'Un upgrade amplía un contrato activo del cliente y no se encontró ninguno.'
          else 'No se pudo determinar qué tasa corresponde a este contrato (' || coalesce(v_motivo, 'sin motivo') || '). La tasa la decide la política.'
        end;
      elsif v_c.tasa_anual < v_base then
        -- D4: por debajo de la base no se autoriza nada, así que tampoco se ofrece pedir permiso (Codex R4 #12).
        v_rechazo := 'La tasa de este contrato la fija la política: ' || private.rentabilidad_tasa_txt(v_base)
          || '%, y no puede quedar por debajo. Corrige la tasa antes de guardar.';
      elsif v_c.tasa_anual > v_base then
        -- Por encima de la base: solo pasa con una autorización VIVA de Gerencia para esta MISMA intención (huella),
        -- que se consume aquí, en esta transacción y de un solo uso.
        v_cond := private.rentabilidad_condicion_declarada(v_c.producto_condicion_id);
        v_aut := private.rentabilidad_consumir_autorizacion(v_c, v_base, v_origen, v_cond, statement_timestamp());
        if v_aut is null then
          v_rechazo := 'La tasa de este contrato la fija la política: ' || private.rentabilidad_tasa_txt(v_base)
            || '%. Para cerrar a ' || private.rentabilidad_tasa_txt(v_c.tasa_anual)
            || '% hace falta una autorización vigente de Gerencia para estos mismos datos (cliente, capital, plazo, modalidad y origen).';
        else
          v_solicitud := (v_aut ->> 'solicitud_id')::uuid;
        end if;
      end if;
    end if;
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
    'modo', v_modo,
    'tasa_en_juego', case when v_enforce then v_en_juego end,
    'huella_movida', case when v_enforce and tg_op = 'UPDATE' then v_huella_mov end,
    'autorizacion', v_aut,
    'origen_declarado', v_origen_dec,
    'resolucion', case when v_res is null then null else v_res - 'politica' - 'cliente_id' - 'categoria' end
  ));
  -- Si el candado rechaza no se anota nada (la transacción se aborta unas líneas más abajo); y solo se escribe UNA
  -- fila por contrato y transacción. OJO: no se puede «return» aquí — un return sale de la función y el rechazo, que
  -- vive fuera del manejador, nunca se lanzaría.
  if v_rechazo is null and v_anotar then
  begin
    insert into crm.ledger_rentabilidad (
      contrato_id, numero_contrato, cliente_id, categoria, contrato_origen_id, politica_id, solicitud_id,
      tasa_base, tasa_final, tasa_recibida, regla, origen, actor_id, detalle
    ) values (
      v_c.id, v_c.numero_contrato, v_c.cliente_id, v_c.categoria, v_origen, v_pol_id, v_solicitud,
      v_base, v_c.tasa_anual, v_c.tasa_anual, v_regla,
      case when v_enforce then 'enforcement' else 'observacion' end, (select auth.uid()), v_detalle
    );
  exception when others then
    if v_enforce then
      -- Bajo enforcement no puede pasar un contrato SIN su fila en el libro: el candado también falla cerrado aquí.
      v_rechazo := 'No se pudo registrar la tasa de este contrato en el libro de rentabilidad (' || sqlstate || '). Reintenta.';
    else
      raise warning 'RENTABILIDAD R2: no se pudo observar el contrato % (% %)', v_c.id, sqlstate, sqlerrm;
    end if;
  end;
  end if;
 exception when others then
  if v_enforce then
    -- Bajo enforcement el candado FALLA CERRADO: si no pudo verificar la tasa, el contrato no pasa. La vuelta atrás
    -- es publicar la política en «observacion» (sin migración).
    v_rechazo := 'No se pudo verificar la tasa contra la política de rentabilidad (' || sqlstate || '). Reintenta; si persiste, avisa a Gerencia.';
  else
    -- Límite DECLARADO y deliberado (frente a Codex R4 #7): si el fallo impidió incluso LEER el modo, v_enforce sigue
    -- en false y el contrato pasa. Fallar cerrado ahí convertiría un problema al leer una tabla de una fila en una
    -- parada de TODAS las altas mientras el candado está apagado, que es justo lo que estas fases prometen no hacer.
    -- El contrato queda sin fila en el libro, así que la tarjeta de Gerencia lo cuenta como hueco de cobertura.
    raise warning 'RENTABILIDAD R2: el observador falló y se ignora (% %) en el contrato %', sqlstate, sqlerrm, new.id;
  end if;
 end;
 -- El rechazo vive AQUÍ, fuera del manejador: dentro, el propio WHEN OTHERS se lo tragaría.
 if v_rechazo is not null then
   raise exception '%', v_rechazo using errcode = 'P0410';
 end if;
 return null;
end;
$function$;
revoke all on function private.trg_contratos_observar_rentabilidad() from public, anon, authenticated, service_role;
comment on function private.trg_contratos_observar_rentabilidad() is
  'Rentabilidad R2+R4: observador Y CANDADO diferido de public.contratos. Al commit relee el estado FINAL de la fila y escribe UNA fila por contrato y transacción en crm.ledger_rentabilidad (base del núcleo vs la que quedó; en una corrección conserva la resolución del alta; el upgrade resuelve de verdad cuando la puerta DECLARA su origen —GUC de un solo uso, D2— y si no, solo apunta el candidato como sin_regla). Con la política en «observacion» mide y NUNCA aborta (idéntico a R2). Con «enforcement» RECHAZA (P0410) el alta o la corrección que fije una tasa distinta a la resuelta sin una autorización viva de Gerencia para la misma huella, que consume de un solo uso; también cuando la tasa estaba por encima de la base y se MUEVE la intención que la amparaba (capital, plazo, modalidad, producto…), cuando un contrato de prueba pasa a real, y cuando no hay regla. Nunca por debajo de la base (D4). Los datos de prueba no se tocan. Falla CERRADO. Volver a observacion es publicar la política, sin migración.';

-- ---------------------------------------------------------------------------
-- 5. La PUERTA del alta del CRM declara el origen del upgrade (D2). Único cambio: un set_config.
-- ---------------------------------------------------------------------------
create or replace function crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
  v_huella text;
  v_huella_previa text;
  -- Rentabilidad R4 (D2): el contrato que amplía un UPGRADE. Viaja dentro de p_contrato igual que
  -- clave_idempotencia (es del transporte, no del contrato) y NO se le quita: la cadena de abajo solo lo lee en la
  -- rama de renovación, así que recibe exactamente lo que recibía.
  v_origen_upgrade text := nullif(btrim(coalesce(p_contrato->>'contrato_origen_id', '')), '');
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- El origen declarado se publica en un GUC TRANSACCIONAL para que el candado del servidor
  -- (private.trg_contratos_observar_rentabilidad, al commit) sepa de qué contrato hereda la tasa este upgrade. Va con
  -- el cliente delante para que no pueda aplicarse al contrato de otro, y se REESCRIBE en cada alta (también vacío)
  -- para que un alta posterior de la misma transacción no herede la declaración de la anterior.
  perform set_config(
    'crm.rentabilidad_origen_upgrade',
    case when p_contrato->>'categoria' = 'upgrade' and v_origen_upgrade is not null
         then coalesce(p_contrato->>'cliente_id', '') || '|' || v_origen_upgrade else '' end,
    true);

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    -- La huella de LO QUE SE PIDE (sin la clave): la misma clave solo vale para la
    -- misma solicitud. jsonb::text es canónico (claves ordenadas), así que dos
    -- envíos iguales dan la misma huella.
    v_huella := md5(
      (p_contrato - 'clave_idempotencia')::text || '|'
      || coalesce(p_cronograma::text, '') || '|'
      || coalesce(p_cuenta::text, '')
    );
    select a.respuesta, a.contrato_id, a.huella
      into v_resultado, v_contrato_id, v_huella_previa
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El replay pasa por la MISMA autorización que el alta (Codex 05/09): una
      -- membresía revocada o un contrato fuera de cartera no recuperan nada.
      if not (select private.puede_registrar_ventas()) then
        raise insufficient_privilege using
          message = 'Cliente no encontrado o fuera de tu cartera';
      end if;
      -- Lápida: el contrato de este intento fue eliminado después (FK SET NULL).
      -- Un reintento tardío NO recrea lo que Gerencia borró a propósito.
      if v_contrato_id is null then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end if;
      -- Misma fila que bloquea la puerta de eliminación: replay y borrado se
      -- serializan. Si el contrato desaparece mientras esperamos, es lápida.
      begin
        perform private.bloquear_fila_contrato_pdf(v_contrato_id);
      exception when sqlstate 'P0002' then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
        raise insufficient_privilege using
          message = 'Contrato no encontrado o fuera de tu cartera';
      end if;
      -- Misma clave pero OTROS datos (el analista editó el formulario tras un
      -- intento que SÍ creó el contrato): no se devuelve el viejo como si fuera
      -- el nuevo ni se crea otro. Se le dice la verdad, con el número.
      if v_huella_previa is distinct from v_huella then
        raise exception 'Este intento ya creó el contrato % con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
          coalesce(v_resultado->>'numero_contrato', v_contrato_id::text)
          using errcode = 'P0409',
                hint = 'ALTA_YA_CREADA_CON_OTROS_DATOS',
                detail = jsonb_build_object(
                  'contrato_id', v_contrato_id,
                  'numero_contrato', v_resultado->>'numero_contrato'
                )::text;
      end if;
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
end;
$function$;


-- ---------------------------------------------------------------------------
-- 6. PEDIR autorización desde una CORRECCIÓN (contrato_id → el núcleo acepta el origen ya renovado por él)
-- ---------------------------------------------------------------------------
create or replace function crm.solicitar_tasa_fn(p_solicitud jsonb)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_cliente uuid; v_cat text; v_origen uuid; v_pc uuid; v_ctr uuid;
  v_capital numeric; v_moneda text; v_mod text; v_ti text; v_fi date; v_fv date;
  v_tasa numeric; v_motivo text;
  v_res jsonb; v_base numeric; v_tope numeric; v_dias integer; v_pol_id uuid;
  v_huella text; v_viva record; v_fila crm.solicitudes_tasa;
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
begin
  -- La AUTORIDAD se pregunta antes de mirar el JSON (auditor n2): un no autorizado muere en el 42501 uniforme sin
  -- distinguir «formato inválido»; el cliente (activo, rol cliente) se comprueba justo después de leerlo.
  if v_uid is null or not private.puede_registrar_ventas() then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if p_solicitud is null or jsonb_typeof(p_solicitud) <> 'object' then
    raise exception 'Faltan los datos de la solicitud' using errcode = '22023';
  end if;
  begin
    v_cliente := (p_solicitud ->> 'cliente_id')::uuid;
    v_cat     := p_solicitud ->> 'categoria';
    v_origen  := (p_solicitud ->> 'contrato_origen_id')::uuid;
    v_pc      := (p_solicitud ->> 'producto_condicion_id')::uuid;
    v_capital := (p_solicitud ->> 'capital')::numeric;
    v_moneda  := p_solicitud ->> 'moneda';
    v_mod     := p_solicitud ->> 'modalidad';
    v_ti      := p_solicitud ->> 'tipo_interes';
    v_fi      := (p_solicitud ->> 'fecha_inicio')::date;
    v_fv      := (p_solicitud ->> 'fecha_vencimiento')::date;
    v_tasa    := round((p_solicitud ->> 'tasa_solicitada')::numeric, 2);   -- misma escala que contratos.tasa_anual (auditor m5)
    v_motivo  := btrim(p_solicitud ->> 'motivo');
    -- R4: contexto de CORRECCIÓN. El contrato que se está corrigiendo se pasa al núcleo como p_contrato_nuevo_id, para
    -- que un origen «ya renovado POR ESE contrato» siga siendo su origen válido. Sin esto no se puede ni PEDIR
    -- autorización para corregir la tasa de una renovación: el núcleo la rechaza por origen cerrado (Codex R4 #3).
    v_ctr     := (p_solicitud ->> 'contrato_id')::uuid;
  exception when others then
    raise exception 'Datos de la solicitud inválidos' using errcode = '22023';
  end;
  if not private.puede_operar_tasa_cliente(v_cliente) then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if v_capital is null or v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000' using errcode = '22023';
  end if;
  if v_moneda is null or v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;
  if v_mod is null or v_mod not in ('mensual', 'trimestral', 'semestral', 'anual')
     or v_ti is null or v_ti not in ('simple', 'compuesto') then
    raise exception 'Modalidad o tipo de interés inválidos' using errcode = '22023';
  end if;
  if v_fi is null or v_fv is null or v_fv <= v_fi then
    raise exception 'El plazo del contrato es inválido' using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 500 then
    raise exception 'Escribe el motivo comercial (entre 5 y 500 caracteres)' using errcode = '22023';
  end if;
  if v_tasa is null or v_tasa <= 0 then
    raise exception 'La tasa solicitada es inválida' using errcode = '22023';
  end if;

  perform private.vencer_solicitudes_tasa();
  -- EL NÚCLEO decide la base y la regla; esta puerta no calcula tasa.
  v_res := private.resolver_tasa(v_cliente, v_cat, v_origen, statement_timestamp(), v_ctr);
  v_base := (v_res ->> 'tasa_base')::numeric;
  v_tope := (v_res #>> '{politica,tope_tecnico}')::numeric;
  v_dias := (v_res #>> '{politica,vigencia_solicitud_dias}')::integer;
  v_pol_id := (v_res #>> '{politica,id}')::uuid;
  if v_tasa <= v_base then
    raise exception 'La excepción debe ser superior a la tasa base de % %%', rtrim(rtrim(to_char(v_base, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;
  if v_tasa > v_tope then
    raise exception 'La tasa solicitada supera el tope técnico de % %%', rtrim(rtrim(to_char(v_tope, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;

  v_huella := private.huella_solicitud_tasa(v_cliente, v_cat, v_origen, v_pc, v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv);
  perform pg_advisory_xact_lock(hashtext('crm.solicitudes_tasa'), hashtext(v_huella));
  select s.id, s.estado, s.solicitada_por into v_viva from crm.solicitudes_tasa s
   where s.huella = v_huella
     and s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
   limit 1;
  if v_viva.id is not null then
    raise exception 'Ya hay una solicitud viva para este contrato (estado «%»)', v_viva.estado
      using errcode = 'P0409',
            detail = jsonb_build_object('solicitud_id', v_viva.id, 'estado', v_viva.estado, 'solicitada_por', v_viva.solicitada_por,
                                        'propia', v_viva.solicitada_por = v_uid)::text;
  end if;

  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  insert into crm.solicitudes_tasa (
    politica_id, cliente_id, categoria, contrato_origen_id, contrato_origen_numero, producto_condicion_id,
    capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, huella,
    tasa_base, regla_base, contratos_previos, prioridad_bandeja, tasa_solicitada, motivo,
    estado, solicitada_por, solicitada_en, vence_en
  ) values (
    v_pol_id, v_cliente, v_cat, v_origen, v_res #>> '{contrato_origen,numero_contrato}', v_pc,
    v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv, v_huella,
    v_base, v_res ->> 'regla', (v_res ->> 'contratos_previos')::integer, (v_res ->> 'prioridad_bandeja')::boolean, v_tasa, v_motivo,
    'pendiente', v_uid, statement_timestamp(), statement_timestamp() + make_interval(days => v_dias)
  ) returning * into v_fila;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return to_jsonb(v_fila) || jsonb_build_object('ok', true, 'resolucion', v_res);
end;
$function$;
revoke all on function crm.solicitar_tasa_fn(jsonb) from public, anon, service_role;
grant execute on function crm.solicitar_tasa_fn(jsonb) to authenticated;
comment on function crm.solicitar_tasa_fn(jsonb) is
  'Rentabilidad R1: el analista pide una tasa SUPERIOR a la base para un contrato en intención {cliente_id, categoria, contrato_origen_id?, producto_condicion_id?, capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, tasa_solicitada, motivo}. Autoridad del alta + cliente en ámbito (42501); base y regla del núcleo; base < tasa <= tope técnico (22023); una viva por huella (P0409). Devuelve la solicitud + resolucion. R4: admite contrato_id (corrección) para que el núcleo acepte un origen ya renovado POR ese contrato.';

-- ---------------------------------------------------------------------------
-- 7. EL INTERRUPTOR: publicar la política admite modo=enforcement
-- ---------------------------------------------------------------------------
create or replace function crm.publicar_politica_rentabilidad_fn(p_expected_version integer, p_config jsonb)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_actual integer; v_anterior uuid; v_ultimo timestamptz;
  v_tasa numeric; v_tope numeric; v_dias numeric; v_modo text; v_nota text;
  v_fila crm.politica_rentabilidad;
  v_desde timestamptz := clock_timestamp();
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa publica la política de rentabilidad' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'expected_version inválido' using errcode = '22023';
  end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object'
     or not (p_config ?& array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo'])
     or (p_config - array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo', 'nota']) <> '{}'::jsonb
     or jsonb_typeof(p_config -> 'tasa_base_nueva') is distinct from 'number'
     or jsonb_typeof(p_config -> 'tope_tecnico') is distinct from 'number'
     or jsonb_typeof(p_config -> 'vigencia_solicitud_dias') is distinct from 'number'
     or jsonb_typeof(p_config -> 'modo') is distinct from 'string'
     or (p_config ? 'nota' and jsonb_typeof(p_config -> 'nota') not in ('string', 'null')) then
    raise exception 'Formato de política inválido' using errcode = '22023';
  end if;
  v_tasa := (p_config ->> 'tasa_base_nueva')::numeric;
  v_tope := (p_config ->> 'tope_tecnico')::numeric;
  v_dias := (p_config ->> 'vigencia_solicitud_dias')::numeric;
  v_modo := p_config ->> 'modo';
  v_nota := nullif(btrim(p_config ->> 'nota'), '');
  if v_tasa <= 0 or v_tasa > 50 or v_tope <= 0 or v_tope > 50 or v_tope < v_tasa
     or trunc(v_dias) <> v_dias or v_dias < 1 or v_dias > 30 then
    raise exception 'Política fuera de rango (tasa 0-50, tope >= tasa y <= 50, vigencia 1-30 días)' using errcode = '22023';
  end if;
  if v_modo not in ('observacion', 'enforcement') then
    raise exception 'Modo inválido: observacion o enforcement' using errcode = '22023';
  end if;
  -- R4: enforcement YA está construido (private.trg_contratos_observar_rentabilidad lo lee al commit de cada alta y
  -- corrección). Publicarlo es EL INTERRUPTOR: desde esa versión, una tasa distinta a la resuelta sin autorización
  -- viva de Gerencia se rechaza (P0410). Volver a «observacion» es publicar otra versión: no hace falta migración.
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'La nota no puede superar 500 caracteres' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('crm.politica_rentabilidad'), 1);
  select p.id, p.version, p.vigente_desde into v_anterior, v_actual, v_ultimo
  from crm.politica_rentabilidad p order by p.version desc limit 1;
  if p_expected_version <> v_actual then
    raise exception 'Conflicto de versión: esperada %, vigente %', p_expected_version, v_actual using errcode = 'P0409';
  end if;
  if v_desde <= v_ultimo then
    v_desde := v_ultimo + interval '1 millisecond';
  end if;
  insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico,
                                         vigencia_solicitud_dias, modo, nota, publicada_por)
  values (v_actual + 1, v_anterior, v_desde, v_tasa, v_tope, v_dias::integer, v_modo, v_nota, v_uid)
  returning * into v_fila;
  return to_jsonb(v_fila) || jsonb_build_object('ok', true);
end;
$function$;
comment on function crm.publicar_politica_rentabilidad_fn(integer, jsonb) is
  'Rentabilidad R1: Gerencia publica una revisión {tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota?} con control optimista por versión (P0409). R4: admite el modo enforcement (el interruptor del candado); volver a observacion es publicar otra versión.';

-- ---------------------------------------------------------------------------
-- 8. LA TARJETA de Gerencia cuenta también lo que pasa con el candado encendido
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
    -- R4: con el candado encendido las filas nuevas llevan origen='enforcement'. La tarjeta tiene que ver LAS DOS o se
    -- quedaría ciega justo en las 48 h en que Gerencia mira si el candado hace daño.
    where l.origen in ('observacion', 'enforcement')
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
      and not exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = c.id and l.origen in ('observacion', 'enforcement') and l.detalle ->> 'evento' = 'INSERT')
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
  'Rentabilidad R2 (+R4): la tarjeta de Gerencia (y Directorio): observaciones del ledger en el periodo (por defecto 30 días; máx 366; hasta <= hoy). Cuenta EVENTOS y CONTRATOS; los importes (margen cedido/retenido en el plazo por moneda, por regla y por analista) salen de la REVISIÓN EFECTIVA de cada contrato al corte y solo de fotos completas (`importe_no_calculable` cuenta el resto). Demo excluido por la marca actual del contrato. Sondas separadas (consistencia_interna, cobertura_altas desde el hito de activación, cobertura_correcciones desconocida) y `coherente`. 42501 para el resto. R4: cuenta también las filas origen=enforcement, para que la tarjeta no se quede ciega al encender el candado.';

-- ---------------------------------------------------------------------------
-- 9. El TRIGGER se recrea: vigila además modalidad, tipo de interés, producto y la marca de prueba
-- ---------------------------------------------------------------------------
-- Son dimensiones de la huella autorizada (y la marca de prueba decide si el candado mira o no): sin vigilarlas, una
-- autorización para 20 000 a 12 meses amparaba después 100 000 a 24, o un contrato de ensayo con tasa a mano pasaba a
-- real sin pasar por el candado (Codex R4 #1 y #6). Mismo nombre, mismo momento (diferido al commit), misma función.
drop trigger if exists trg_contratos_zz_observar_rentabilidad on public.contratos;
create constraint trigger trg_contratos_zz_observar_rentabilidad
after insert or update of tasa_anual, categoria, cliente_id, capital, moneda, fecha_inicio, fecha_vencimiento,
                          modalidad, tipo_interes, producto_condicion_id, es_demo on public.contratos
deferrable initially deferred
for each row execute function private.trg_contratos_observar_rentabilidad();

-- ---------------------------------------------------------------------------
-- 10. HITO: desde cuándo EXISTE el candado (no cuándo se encendió)
-- ---------------------------------------------------------------------------
insert into crm.rentabilidad_hitos (clave, valor, registrado_en)
values ('enforcement_construido_desde',
        jsonb_build_object('en', clock_timestamp(), 'migracion', '20260907093000',
                           'nota', 'El candado existe y lee la política; se enciende publicando modo=enforcement.'),
        clock_timestamp())
on conflict (clave) do update set valor = excluded.valor, registrado_en = excluded.registrado_en;

do $post$
declare
  v_f text;
  -- rentabilidad_tasa_txt es inmutable y no lee tablas: no necesita ser DEFINER, solo privada.
  v_definer text[] := array['private.rentabilidad_condicion_declarada(uuid)',
                            'private.rentabilidad_origen_declarado(public.contratos)',
                            'private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)'];
  v_esperado text[] := array['private.rentabilidad_tasa_txt(numeric)'] || v_definer;
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_contratos_observar_rentabilidad()')) is distinct from '0e73d5d01bf7aa3c1e39368a1cb20cd3' then
    raise exception 'POSTFLIGHT R4: el observador+candado no quedó con el cuerpo esperado (0e73d5d0…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)')) is distinct from 'a363ad7e514c8eef3257acd7a1a54d44' then
    raise exception 'POSTFLIGHT R4: la puerta del alta no quedó con el cuerpo esperado (a363ad7e…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.solicitar_tasa_fn(jsonb)')) is distinct from '0e2b20efbc05c5facd8769bc5ae88164' then
    raise exception 'POSTFLIGHT R4: crm.solicitar_tasa_fn no quedó con el cuerpo esperado (0e2b20ef…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from 'ec070a86678c3a952ed15b3fc7d7cafd' then
    raise exception 'POSTFLIGHT R4: publicar_politica_rentabilidad_fn no quedó con el cuerpo esperado (ec070a86…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.observacion_rentabilidad_fn(date,date)')) is distinct from '014c621343975e35202e0587e35f443a' then
    raise exception 'POSTFLIGHT R4: la tarjeta de Gerencia no quedó con el cuerpo esperado (014c6213…)';
  end if;
  -- Los helpers son PRIVADOS: DEFINER de postgres, search_path vacío y sin EXECUTE para nadie de la API.
  foreach v_f in array v_esperado loop
    if to_regprocedure(v_f) is null then
      raise exception 'POSTFLIGHT R4: falta %', v_f;
    end if;
    if v_f = any(v_definer) and not exists (select 1 from pg_proc p where p.oid = v_f::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole
                     and exists (select 1 from unnest(p.proconfig) c where c in ('search_path=', 'search_path=""'))) then
      raise exception 'POSTFLIGHT R4: % no es DEFINER de postgres con search_path vacío', v_f;
    end if;
    if not v_f = any(v_definer) and not exists (select 1 from pg_proc p where p.oid = v_f::regprocedure and p.proowner = 'postgres'::regrole
                     and exists (select 1 from unnest(p.proconfig) c where c in ('search_path=', 'search_path=""'))) then
      raise exception 'POSTFLIGHT R4: % no es de postgres con search_path vacío', v_f;
    end if;
    if has_function_privilege('authenticated', v_f, 'EXECUTE') or has_function_privilege('anon', v_f, 'EXECUTE')
       or has_function_privilege('service_role', v_f, 'EXECUTE')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f::regprocedure and a.grantee = 0) then
      raise exception 'POSTFLIGHT R4: % no debería ser ejecutable desde la API', v_f;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE') then
    raise exception 'POSTFLIGHT R4: los grants de la puerta del alta cambiaron';
  end if;
  for v_f in select unnest(array['crm.solicitar_tasa_fn(jsonb)', 'crm.publicar_politica_rentabilidad_fn(integer,jsonb)', 'crm.observacion_rentabilidad_fn(date,date)']) loop
    if not has_function_privilege('authenticated', v_f, 'EXECUTE') or has_function_privilege('anon', v_f, 'EXECUTE')
       or has_function_privilege('service_role', v_f, 'EXECUTE') then
      raise exception 'POSTFLIGHT R4: los grants de % cambiaron', v_f;
    end if;
  end loop;
  -- El trigger: diferido, habilitado, apuntando a NUESTRA función y vigilando las 11 columnas.
  if not exists (
    select 1 from pg_trigger t
    where t.tgname = 'trg_contratos_zz_observar_rentabilidad' and t.tgrelid = 'public.contratos'::regclass
      and t.tgdeferrable and t.tginitdeferred and t.tgenabled = 'O'
      and t.tgfoid = to_regprocedure('private.trg_contratos_observar_rentabilidad()')
      and (select count(*) from unnest(t.tgattr::int2[]) a) = 11
      and (select array_agg(att.attname::text order by att.attname::text) from unnest(t.tgattr::int2[]) a
             join pg_attribute att on att.attrelid = t.tgrelid and att.attnum = a)
          = array['capital','categoria','cliente_id','es_demo','fecha_inicio','fecha_vencimiento','modalidad','moneda','producto_condicion_id','tasa_anual','tipo_interes']::text[]) then
    raise exception 'POSTFLIGHT R4: el trigger del candado no quedó diferido, habilitado y vigilando las 11 columnas de la huella';
  end if;
  if (select p.modo from private.politica_rentabilidad_vigente(statement_timestamp()) p) is distinct from 'observacion' then
    raise exception 'POSTFLIGHT R4: la política quedó fuera de observacion; R4 no debe encender el candado';
  end if;
  raise notice 'RENTABILIDAD R4 OK: candado construido (observador+enforcement, 4 helpers privados, la puerta del alta declara el origen del upgrade, la solicitud admite contexto de corrección, publicar admite enforcement, la tarjeta ve las dos orillas y el trigger vigila las 11 columnas de la huella). La política sigue en OBSERVACION: no bloquea nada todavía.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260907093000' and md5(statements[1]) = '32f6e3ef1107ad6c6aaf13596c7eb487') then
    raise exception 'REGISTRO R4: la versión no quedó registrada con el contenido esperado';
  end if;
  raise notice 'REGISTRO RENTABILIDAD R4 OK (20260907093000, md5 32f6e3ef…)';
end
$post$;
commit;
