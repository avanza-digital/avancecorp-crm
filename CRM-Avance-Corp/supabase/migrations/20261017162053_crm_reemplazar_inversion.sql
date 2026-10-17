-- 20261017162053_crm_reemplazar_inversion.sql
--
-- «Reemplazar inversión» (Fase 1, solo servidor): Gerencia o un admin del portal cambia una inversión de Avance cargada con
-- error por la correcta EN UN SOLO PASO, y la venta del lead pasa a la nueva SIN ANULARSE. Pedido de Miguel (17/10/2026):
-- «si elimino inversión porque hubo un error, y luego la cargo de nuevo, me vuelve a sumar la conversión» — hoy NO: «Eliminar
-- inversión» (20261005200945, decisión D2) anula la venta antes de borrar y la anulación es por LEAD y de un solo sentido
-- (private.cierre_anulado mira crm.cierres_avance_anulados, UNIQUE por lead, y crm.inversiones_eliminadas.conversion_anulada).
-- El contrato que se carga después nunca vuelve a contar. Plan aprobado: vault «Reemplazar inversion - plan por fases
-- (2026-10-17)». Decisiones de Miguel (Fase 0): reemplazan Gerencia y admin (igual que «Eliminar inversión»); cambia todo
-- menos el cliente; mes sellado → no deja; si la fecha cae en otro mes, la venta se muda solo si ese mes sigue abierto;
-- mismo analista, fijo; la tasa aprobada se hereda; modo «quedarme con la otra» para una inversión cargada dos veces.
--
-- «ELIMINAR INVERSIÓN» NO CAMBIA: sigue anulando la venta (es para cuando de verdad no hubo venta). La anulación de Gerencia
-- sigue siendo la única puerta que QUITA una venta: el reemplazo no la quita, la cambia de fuente y comprueba que la
-- conversión quede igual (si no, no hace nada).
--
-- QUÉ HACE
--   1. crm.inversiones_eliminadas.reemplazada_por (uuid, sin llave foránea a propósito, como crm.ledger_rentabilidad: la
--      copia es inmutable y no debe impedir borrar después el contrato nuevo por su puerta). Nula en las eliminaciones de
--      siempre; en un reemplazo, el contrato que quedó. CHECK: un reemplazo nunca es una conversión anulada.
--   2. private.registrar_inversion_reemplazada_avance: la copia del original (molde de private.registrar_inversion_
--      eliminada_avance, que NO se toca): es_conversion como era, conversion_anulada = false, reemplazada_por, y en el
--      snapshot el bloque «reemplazo» (modo, contrato y número que quedan).
--   3. private.reemplazar_inversion_avance: el núcleo, UNA operación atómica:
--        a. private.eliminar_inversion_contexto (bloquea y clasifica el original con los candados y el orden de «Eliminar
--           inversión»: candado consultivo del contrato → contrato → inversión → leads → mes → acreditación);
--        b. rechaza lo que «Eliminar inversión» rechaza (private.inversion_motivo_no_eliminable: renovación, upgrade,
--           cambios de analista, ajustes de mes cerrado, solicitudes posteriores…), una venta ya anulada, una venta de
--           prueba, una venta acreditada a OTRA inversión, y todo mes sellado (conversión: crm.periodos_cerrados; capital:
--           crm.capital_mes_sellos) del original, de su acreditación o de la fecha nueva;
--        c. elimina el original con crm.contrato_eliminar_auditado (copia + PDF conservados), igual que «Eliminar
--           inversión», pero SIN crm.anular_cierre_avance;
--        d. modo «nueva»: da de alta la correcta con crm.crear_contrato_con_cuenta_pdf_v2 (la puerta de alta de siempre, con
--           su PDF, cuenta, cronograma y cotitulares), MISMO cliente, categoría nuevo y MISMO analista_cierre_id; y le deja la
--           fecha de cierre comercial que habría tenido si se hubiera registrado bien el día del original (así el mes de la
--           venta y del capital no se mueve solo por la fecha de hoy; si cambió la fecha de inicio, se recalcula con el día de
--           registro del original). Modo «existente»: la venta pasa a la otra inversión del mismo cliente (cargada dos
--           veces), sin alta;
--        e. vuelve a enlazar leads.contrato_id al contrato que queda (válvula crm.op_privilegiada, como las anulaciones) y
--           mueve la acreditación con el ÚNICO escritor, private.conversion_acreditar_fuente (que ya sabe cambiar de fuente y
--           de mes con los candados de crm.cerrar_periodo);
--        f. INVARIANTE: la acreditación tiene que quedar con el MISMO estado, episodio y analista; solo cambian la fuente y,
--           si cambió la fecha, el mes. Si no (p. ej. el plazo de carga del mes ya cerró → fuera_de_plazo), aborta TODO;
--        g. la copia del original (2.).
--   4. Puertas crm.reemplazar_inversion_fn(p_fuente_id, p_motivo, p_contrato, p_cronograma, p_cuenta) y
--      crm.reemplazar_inversion_por_existente_fn(p_fuente_id, p_conservar_id, p_motivo). DEFINER (justificación: el núcleo
--      borra con la puerta auditada de eliminación, que solo ejecutan postgres y service_role, y mueve la acreditación, que
--      no tiene escritura para la API). Actor y roles SIEMPRE con auth.uid() (private.eliminar_inversion_roles, la misma de
--      «Eliminar inversión»: bloquea perfil y membresía). Avance → admin/superadmin del portal (lo exige la eliminación
--      auditada); si es la venta de un lead → además Gerencia (igual que «Eliminar inversión»). Motivo 5..300. READ
--      COMMITTED. Idempotentes: si el original ya se reemplazó, devuelven el mismo resultado.
--   5. private.trg_contratos_observar_rentabilidad (candado de tasa, diferido): la tasa del original se HEREDA. Excepción
--      ÚNICA, solo en el INSERT del contrato que deja un reemplazo, reconocido por su copia privada en crm.inversiones_
--      eliminadas (misma transacción, reemplazada_por = el contrato) y la tasa del eliminado en su auditoría; la acepta si la
--      categoría es nuevo y quien registra es admin del portal. Solo salta la autorización nueva (enforcement) y el tope
--      técnico (observación); tasa positiva, dos decimales, el máximo de 50 y la regla siguen. El libro anota reemplazo_de.
--      Cuerpo de producción + 5 cambios por ancla; el postflight fija la huella resultante.
--
-- CAPAS: puerta (crm) → núcleo (private) → tablas. CENSO ANALÍTICO: sin count(; el postflight comprueba que nada nuevo entra.
-- negocio_id: como las demás tablas crm (un solo negocio), no lo lleva. NO toca objetos de public: borra y da de alta
-- contratos por sus puertas de siempre; la ÚNICA escritura directa es la fecha de cierre comercial del contrato que queda,
-- con la misma válvula que crm.corregir_fecha_cierre_comercial (crm.correccion_periodo_comercial), cuyo rastro queda en la
-- auditoría de public.contratos y el motivo en la copia. En un reemplazo, fuente 'registro'/'fecha_inicio_inferida'
-- significa «del registro de la VENTA original» (el día se hereda por la cadena de copias).
-- Aplicar en UN mensaje (`supabase db query --linked --file`).
-- REVERSA: supabase/scripts/reemplazar-inversion/reversa.sql (retira puertas y núcleo, devuelve el candado de tasa a su
-- huella de hoy; la columna se conserva si alguna copia la usa).
-- PRUEBAS: supabase/scripts/reemplazar-inversion/test-reemplazar-inversion.sql (banco Docker, ROLLBACK).

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT reemplazar_inversion: esta sesión no tiene el candado de migraciones';
  end if;
  -- Lo que se reemplaza: el candado de tasa, tal como está en producción el 17/10/2026.
  if md5(pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure))
       is distinct from '9a0c04118488b8ec0058a40d71cebcec' then
    raise exception 'PREFLIGHT reemplazar_inversion: cambió private.trg_contratos_observar_rentabilidad';
  end if;
  -- Lo que se llama sin tocar (huellas de producción del 17/10/2026).
  if (md5(pg_catalog.pg_get_functiondef('private.eliminar_inversion_contexto(uuid)'::regprocedure)) = '3d87226acfb1eda521dd9fef173fe256'
      and md5(pg_catalog.pg_get_functiondef('private.inversion_motivo_no_eliminable(text,uuid,uuid)'::regprocedure)) = '408fb7ce87130a81e052cbfa83e1b24b'
      and md5(pg_catalog.pg_get_functiondef('private.eliminar_inversion_roles(uuid)'::regprocedure)) = 'e9a2341105e4028565f81164d5e02c4c'
      and md5(pg_catalog.pg_get_functiondef('private.motivo_normalizado(text)'::regprocedure)) = '08602d4022e0731952cbf61c28efe9d7'
      and md5(pg_catalog.pg_get_functiondef('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure)) = 'c954f109757ccfa18692d0bff54f903c'
      and md5(pg_catalog.pg_get_functiondef('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure)) = 'd0b33d8fb1d27ef2da62105b7ccabd88'
      and md5(pg_catalog.pg_get_functiondef('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure)) = '872930922a1d477e27b23243cbfe691a'
      and md5(pg_catalog.pg_get_functiondef('private.conversion_acreditacion_evento_trg()'::regprocedure)) = 'cb9ad60e0e5956dff7feb212141fbf46'
      and md5(pg_catalog.pg_get_functiondef('private.leads_before_update()'::regprocedure)) = '4ae909f2d56ca650b5595b505e6aa51d'
      and md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) = 'df71c2b1e3cd44b97c3ad84e00637266'
      and md5(pg_catalog.pg_get_functiondef('private.definir_periodo_comercial_contrato()'::regprocedure)) = 'e46146ce46b1876d4d1b86a1912a669b'
      and md5(pg_catalog.pg_get_functiondef('private.materializar_capital_valoraciones_para(integer,text,uuid)'::regprocedure)) = '3ae629c22a85f7aaa4cb4923c1293bed'
      and md5(pg_catalog.pg_get_functiondef('private.log_audit_sin_secretos()'::regprocedure)) = 'ae7225bc9e86131813ac0328fff4c3ae'
      -- Lo que el alta llama por dentro (un cambio ahí cambiaría el alta del reemplazo sin tocar su puerta).
      and md5(pg_catalog.pg_get_functiondef('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure)) = '78e56b851e5fb1904c8ac9c46e095a34'
      and md5(pg_catalog.pg_get_functiondef('private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)'::regprocedure)) = '9a08e3b5ba288ab6614ef6e819337795'
      and md5(pg_catalog.pg_get_functiondef('private.inversiones_escritura_bajo_candado()'::regprocedure)) = '2122bbf3b22996f2e8373081a259db9b'
      and md5(pg_catalog.pg_get_functiondef('private.mes_sellado_de_venta(uuid)'::regprocedure)) = 'ba2cfaaa3337a05a6cd7c32cd6af8e8c'
      and md5(pg_catalog.pg_get_functiondef('private.conversion_plazo_hasta(date)'::regprocedure)) = '4ce984684a471d20aa779365c9b92452'
      and md5(pg_catalog.pg_get_functiondef('private.inversion_eliminacion_dependencias_conocidas()'::regprocedure)) = 'aed03021c2403d762f1b22d152aad585'
      and md5(pg_catalog.pg_get_functiondef('private.membresia_crm_revocada()'::regprocedure)) = '47f8ceb6455f4855562941a7057be02c') is not true then
    raise exception 'PREFLIGHT reemplazar_inversion: cambió una función que el reemplazo usa';
  end if;
  -- El candado de tasa con sus metadatos de hoy (el postflight exige los mismos).
  if not exists (select 1 from pg_catalog.pg_proc p where p.oid = 'private.trg_contratos_observar_rentabilidad()'::regprocedure
                 and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 'v'
                 and p.proconfig = array['search_path=""', 'lock_timeout=2s']
                 and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'PREFLIGHT reemplazar_inversion: cambiaron los metadatos del candado de tasa';
  end if;
  if private.inversion_eliminacion_dependencias_conocidas() is not true then
    raise exception 'PREFLIGHT reemplazar_inversion: las dependencias de las eliminaciones no son las conocidas';
  end if;
  if exists (select 1 from pg_catalog.pg_attribute a
             where a.attrelid = 'crm.inversiones_eliminadas'::regclass and a.attname = 'reemplazada_por' and not a.attisdropped)
     or to_regprocedure('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)') is not null
     or to_regprocedure('crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)') is not null
     or to_regprocedure('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)') is not null
     or to_regprocedure('private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)') is not null then
    raise exception 'PREFLIGHT reemplazar_inversion: los objetos nuevos ya existen';
  end if;
end
$preflight$;

-- ── 1 · La copia recuerda qué contrato quedó ──────────────────────────────────────────────────────────────────────────
alter table crm.inversiones_eliminadas add column reemplazada_por uuid;
alter table crm.inversiones_eliminadas add constraint inversiones_eliminadas_reemplazo_check
  check (reemplazada_por is null or (not conversion_anulada and reemplazada_por <> fuente_id));

-- ── 2 · Núcleo: la copia del original reemplazado ────────────────────────────────────────────────────────────────────
create function private.registrar_inversion_reemplazada_avance(p_ctx jsonb, p_contrato_auditoria uuid, p_actor uuid,
  p_rol text, p_motivo text, p_reemplazo uuid, p_modo text, p_detalle jsonb)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  v_fuente uuid := (p_ctx ->> 'fuente_id')::uuid;
  v_lead uuid := (p_ctx ->> 'lead_id')::uuid;
  v_es_conversion boolean := coalesce((p_ctx ->> 'es_conversion')::boolean, false);
  v_a crm.contratos_eliminados_auditoria%rowtype;
  v_numero_reemplazo text;
  v_id uuid;
begin
  if p_ctx ->> 'tipo' is distinct from 'contrato' or p_reemplazo is null or p_reemplazo = v_fuente
     or p_modo is null or p_modo not in ('nueva', 'existente') then
    raise exception 'Reemplazo no válido para una inversión de Avance' using errcode = '22023';
  end if;
  select * into v_a from crm.contratos_eliminados_auditoria a where a.id = p_contrato_auditoria and a.contrato_id = v_fuente;
  select c.numero_contrato into v_numero_reemplazo from public.contratos c where c.id = p_reemplazo;
  if v_a.id is null or v_numero_reemplazo is null or exists (select 1 from public.contratos c where c.id = v_fuente) then
    raise exception 'El reemplazo del contrato no se confirmó; requiere revisión' using errcode = '55000';
  end if;
  -- Una venta anulada no se «reemplaza»: se elimina con «Eliminar inversión». La puerta ya lo rechazó antes de borrar.
  if v_es_conversion and (v_lead is null or private.cierre_anulado(v_lead)) then
    raise exception 'Una venta anulada no se reemplaza' using errcode = 'P0409';
  end if;
  begin
  insert into crm.inversiones_eliminadas (fuente_tipo, fuente_id, inversion_id, empresa, inversionista_id, lead_id,
    es_conversion, conversion_anulada, anulacion, motivo, eliminado_por, rol_actor, contrato_auditoria_id, snapshot, archivos,
    reemplazada_por)
  values ('contrato', v_fuente, (p_ctx ->> 'inversion_id')::uuid, 'avance', (p_ctx ->> 'inversionista_id')::uuid,
    case when v_es_conversion then v_lead end, v_es_conversion, false, null, p_motivo, p_actor, p_rol, v_a.id,
    jsonb_build_object(
      'version', 1,
      'actor', jsonb_build_object('id', p_actor, 'rol', p_rol),
      'contrato_auditoria_id', v_a.id,
      'contrato', jsonb_build_object('id', v_fuente, 'numero_contrato', v_a.snapshot #>> '{contrato,numero_contrato}'),
      'inversion', v_a.snapshot -> 'inversion',
      -- p_detalle: la acreditación tal como estaba ANTES (re-acreditar reinicia sus relojes a la hora del reemplazo), el día
      -- de registro de la VENTA (el próximo reemplazo de ese contrato lo hereda) y la huella del pedido (idempotencia).
      'reemplazo', coalesce(p_detalle, '{}'::jsonb)
        || jsonb_build_object('modo', p_modo, 'contrato_id', p_reemplazo, 'numero_contrato', v_numero_reemplazo)),
    v_a.archivos, p_reemplazo)
  returning id into v_id;
  exception when check_violation or not_null_violation or foreign_key_violation or unique_violation then
    raise exception 'La copia de la inversión reemplazada no es válida; requiere revisión' using errcode = '55000';
  end;
  return v_id;
end
$function$;

-- ── 3 · Núcleo: el reemplazo, una operación atómica ───────────────────────────────────────────────────────────────────
create function private.reemplazar_inversion_avance(p_actor uuid, p_roles jsonb, p_fuente uuid, p_motivo text,
  p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb, p_conservar uuid)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_portal text := p_roles ->> 'portal';
  v_gerencia boolean := coalesce((p_roles ->> 'gerencia')::boolean, false);
  v_modo text := case when p_conservar is null then 'nueva' else 'existente' end;
  v_ctx jsonb;
  v_no text;
  v_previo crm.inversiones_eliminadas%rowtype;
  v_orig public.contratos%rowtype;
  v_cons public.contratos%rowtype;
  v_es_conversion boolean;
  v_lead uuid;
  v_acr crm.conversion_acreditaciones%rowtype;
  v_acr2 crm.conversion_acreditaciones%rowtype;
  v_mueve_venta boolean := false;
  v_leads uuid[];
  v_fi date;
  v_dia_registro date;
  v_fecha_cc date;
  v_fuente_cc text;
  v_periodos date[];
  v_p date;
  v_contrato jsonb;
  v_alta jsonb;
  v_nuevo uuid;
  v_nuevo_cc date;
  v_nuevo_fuente_cc text;
  v_priv_previa text;
  v_corr_previa text;
  v_res jsonb;
  v_aud uuid;
  v_rol text;
  v_mes_alta date;
  v_venta record;
  v_primera boolean;
  v_p_contrato uuid;
  v_lead_sin_enlace boolean := false;
  v_titulares jsonb;
  v_origen_conf crm.origenes_capital_confirmados%rowtype;
  -- Lo que se pidió (sin el motivo): un reintento con OTROS datos no recibe el resultado del primero como si fuera suyo.
  v_huella_pedido text := md5(coalesce(p_contrato::text, '') || '|' || coalesce(p_cronograma::text, '') || '|'
    || coalesce(p_cuenta::text, '') || '|' || coalesce(p_conservar::text, ''));
begin
  if p_fuente is null then
    raise exception 'Indica la inversión que se reemplaza' using errcode = '22023';
  end if;

  -- Candado GLOBAL del cierre de mes ANTES de cualquier fila (el orden de crm.cerrar_periodo, crm.corregir_fecha_cierre_
  -- comercial y crm.eliminar_lead_error_carga): mientras dura el reemplazo nadie sella, reabre ni cambia un plazo, y no hay
  -- abrazo mortal con el sello (que tras el mensual pide LOCK TABLE public.contratos IN SHARE).
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
  -- Los candados consultivos de LOS DOS contratos (el original y, en «quedarme con la otra», el que se conserva) en orden
  -- de uuid y ANTES del contexto: el mismo candado y la misma posición que usan la eliminación auditada y el contexto, así
  -- que un «Eliminar» del contrato conservado espera aquí en vez de cruzarse (Codex r1, P2).
  for v_p_contrato in select x from unnest(array[p_fuente, p_conservar]) x where x is not null order by x loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('contrato_eliminar_auditado:' || v_p_contrato::text, 0));
  end loop;
  if p_conservar is not null then
    -- La fila del contrato que se conserva y sus leads, ANTES de que el contexto tome el mes del original: quien toca ese
    -- contrato va fila → mes (p. ej. public.marcar_contrato_demo), así que pedirla después de un mes cruzaría (revisión de
    -- concurrencia, P3).
    select * into v_cons from public.contratos c where c.id = p_conservar for update;
    perform 1 from crm.leads l where l.contrato_id = p_conservar order by l.id for update;
  end if;

  -- a. Bloquear y clasificar el original (mismos candados y orden que «Eliminar inversión»).
  v_ctx := private.eliminar_inversion_contexto(p_fuente);
  if v_ctx is null then
    -- Idempotencia: el original ya se reemplazó (un reintento, o dos clics que se serializaron en el candado del contrato).
    -- Con los MISMOS permisos que el reemplazo (Codex r1, P2).
    select * into v_previo from crm.inversiones_eliminadas e where e.fuente_tipo = 'contrato' and e.fuente_id = p_fuente;
    if v_previo.id is not null and v_previo.reemplazada_por is not null then
      if v_portal is null then
        raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';
      end if;
      if v_previo.es_conversion and not v_gerencia then
        raise exception 'Esta inversión es la venta de un lead: solo gerencia puede reemplazarla' using errcode = '42501';
      end if;
      -- El origen de capital confirmado también exigió Gerencia en el reemplazo (Codex r2, P2): la copia lo recuerda.
      if coalesce((v_previo.snapshot #>> '{reemplazo,origen_confirmado}')::boolean, false) and not v_gerencia then
        raise exception 'Esta inversión tiene un origen de capital confirmado por Gerencia: solo gerencia puede reemplazarla'
          using errcode = '42501';
      end if;
      if v_previo.snapshot #>> '{reemplazo,huella_pedido}' is distinct from v_huella_pedido then
        raise exception 'Esta inversión ya se reemplazó por el contrato % con otros datos; no se hizo otro cambio',
          coalesce(v_previo.snapshot #>> '{reemplazo,numero_contrato}', v_previo.reemplazada_por::text)
          using errcode = 'P0409', hint = 'REEMPLAZO_YA_HECHO_CON_OTROS_DATOS';
      end if;
      return jsonb_build_object('ok', true, 'idempotente', true, 'fuente_id', p_fuente,
        'contrato_id', v_previo.reemplazada_por, 'auditoria_id', v_previo.id,
        'modo', v_previo.snapshot #>> '{reemplazo,modo}', 'numero_contrato', v_previo.snapshot #>> '{reemplazo,numero_contrato}');
    end if;
    raise exception 'La inversión no existe o ya fue eliminada' using errcode = 'P0002';
  end if;

  -- b. Lo que no se reemplaza.
  if v_ctx ->> 'tipo' is distinct from 'contrato' then
    raise exception 'Por ahora solo se reemplazan inversiones de Avance' using errcode = '0A000';
  end if;
  if v_portal is null then
    raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';
  end if;
  v_no := private.inversion_motivo_no_eliminable('contrato', p_fuente, (v_ctx ->> 'inversion_id')::uuid);
  if v_no is not null then
    raise exception '%', v_no using errcode = 'P0409';
  end if;
  v_es_conversion := coalesce((v_ctx ->> 'es_conversion')::boolean, false);
  v_lead := (v_ctx ->> 'lead_id')::uuid;
  if v_es_conversion then
    if coalesce((v_ctx ->> 'conversion_anulada')::boolean, false) then
      raise exception 'La venta de esta inversión ya fue anulada: el reemplazo es para conservar una venta vigente. Usa «Eliminar inversión»'
        using errcode = 'P0409';
    end if;
    if not v_gerencia then
      raise exception 'Esta inversión es la venta de un lead: solo gerencia puede reemplazarla' using errcode = '42501';
    end if;
    if v_lead is null then
      raise exception 'No se encuentra el lead de esta venta; requiere revisión' using errcode = 'P0409';
    end if;
  end if;
  select * into v_orig from public.contratos c where c.id = p_fuente;   -- ya bloqueado por el contexto
  if coalesce(v_orig.es_demo, false) then
    raise exception 'Es una venta de prueba: se elimina con «Eliminar inversión», no se reemplaza' using errcode = 'P0409';
  end if;
  if v_orig.categoria is distinct from 'nuevo' then
    raise exception 'Solo se reemplaza una inversión nueva (sin renovación ni upgrade)' using errcode = 'P0409';
  end if;
  if v_lead is not null then
    select * into v_acr from crm.conversion_acreditaciones ca where ca.lead_id = v_lead for update;
    if v_acr.id is not null and (v_acr.fuente_tipo, v_acr.fuente_id) is distinct from ('contrato'::text, p_fuente) then
      -- Mover el enlace del lead movería esta acreditación a la inversión nueva (el enlace explícito prevalece): no se adivina.
      raise exception 'La venta de este lead está acreditada a otra inversión; requiere revisión antes de reemplazar'
        using errcode = 'P0409';
    end if;
    v_mueve_venta := v_acr.id is not null;
  end if;
  v_leads := array(select l.id from crm.leads l where l.contrato_id = p_fuente order by l.id);   -- ya bloqueados
  -- El lead de la venta sin contrato enlazado (la acreditación decide: el contexto ya lo bloqueó) queda enlazado al que
  -- queda (Codex r1, P1). Si apunta a OTRO contrato, la venta y el enlace ya discrepan: mudar la venta dejaría el enlace en
  -- el otro y la próxima sincronización del lead podría llevársela allí. No se adivina: revisión (Codex r2).
  -- En «quedarme con la otra», el lead ya enlazado a la que se conserva está donde tiene que quedar (auditor-rls r2, P3).
  if v_lead is not null and not (v_lead = any (v_leads))
     and (p_conservar is null or (select l.contrato_id from crm.leads l where l.id = v_lead) is distinct from p_conservar) then
    if (select l.contrato_id from crm.leads l where l.id = v_lead) is not null then
      raise exception 'La venta de este lead está acreditada a esta inversión, pero el lead está enlazado a otra inversión; requiere revisión antes de reemplazar'
        using errcode = 'P0409';
    end if;
    v_leads := v_leads || v_lead;
    v_lead_sin_enlace := true;
  end if;

  -- Cuotas ya pagadas: el borrado se lleva el cronograma y el contrato que queda nace con todas sus cuotas pendientes (se
  -- pagarían dos veces). No se reemplaza (revisión de negocio, P1); pasar los pagos al cronograma nuevo es otra decisión.
  -- Bloqueado ANTES de mirar: un pago que esté escribiendo una cuota termina primero y se ve aquí, o espera al reemplazo y
  -- ya no encuentra la cuota (Codex r2; carrera-pago.sh). El contrato y su inversión ya están bloqueados (contexto); la
  -- eliminación auditada toma después las filas inversion_* y luego el cronograma, así que aquí el cronograma va ANTES de
  -- ellas: un escritor que tuviera una fila inversion_* y pidiera después una cuota del mismo contrato se cruzaría, y
  -- terminaría en abrazo mortal detectado (PT409 en la puerta), sin cambios a medias. No hay tal escritor conocido.
  perform 1 from public.cronograma_pagos cp where cp.contrato_id = p_fuente order by cp.id for update;
  if exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_fuente
             and (cp.estado in ('pagado', 'trasladado') or cp.monto_pagado is not null)) then
    raise exception 'Este contrato ya tiene cuotas pagadas: el reemplazo perdería esos pagos. No se hizo ningún cambio'
      using errcode = 'P0409';
  end if;
  -- El origen de capital que Gerencia confirmó para este contrato pasa al que queda; escribirlo exige Gerencia (su candado).
  select * into v_origen_conf from crm.origenes_capital_confirmados o
    where o.contrato_id = p_fuente and o.activo order by o.creado_en desc limit 1;
  if v_origen_conf.id is not null and not v_gerencia then
    raise exception 'Esta inversión tiene un origen de capital confirmado por Gerencia: solo gerencia puede reemplazarla'
      using errcode = '42501';
  end if;
  -- Los titulares del original, por si el pedido no los trae (no se pierden cotitulares en silencio).
  v_titulares := (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('tipo_documento', t.tipo_documento,
      'nombre_completo', t.nombre_completo, 'documento', t.documento) order by t.orden, t.id)
    from public.contrato_titulares t where t.contrato_id = p_fuente);
  -- El día de registro de la VENTA: si el original ya era el resultado de un reemplazo, el de la venta que reemplazó (la
  -- cadena lo guarda en la copia); si no, el de su propio registro (Codex r1, P1). Vale para los dos modos.
  v_dia_registro := coalesce(
    (select (ie.snapshot #>> '{reemplazo,dia_registro_venta}')::date from crm.inversiones_eliminadas ie
      where ie.reemplazada_por = p_fuente order by ie.es_conversion desc, ie.eliminado_en desc, ie.id desc limit 1),
    (v_orig.creado_en at time zone 'America/Lima')::date);

  -- La inversión que queda.
  if v_modo = 'nueva' then
    if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
      raise exception 'Faltan los datos del contrato correcto' using errcode = '22023';
    end if;
    if nullif(btrim(coalesce(p_contrato ->> 'cliente_id', '')), '') is distinct from v_orig.cliente_id::text
       and p_contrato ? 'cliente_id' then
      raise exception 'El reemplazo es para el mismo cliente; para otro cliente, elimina la inversión y regístrala de nuevo'
        using errcode = '22023';
    end if;
    if coalesce(nullif(btrim(coalesce(p_contrato ->> 'categoria', '')), ''), 'nuevo') <> 'nuevo' then
      raise exception 'El reemplazo registra una inversión nueva (categoría Nuevo)' using errcode = '22023';
    end if;
    if p_contrato ? 'analista_cierre_id'
       and nullif(btrim(coalesce(p_contrato ->> 'analista_cierre_id', '')), '') is distinct from v_orig.analista_cierre_id::text then
      raise exception 'El analista de la venta no cambia en un reemplazo' using errcode = '22023';
    end if;
    if nullif(btrim(coalesce(p_contrato ->> 'contrato_origen_id', '')), '') is not null or p_contrato ? 'fecha_cierre_comercial' then
      raise exception 'El reemplazo no lleva contrato de origen ni fecha de cierre comercial' using errcode = '22023';
    end if;
    begin
      v_fi := (p_contrato ->> 'fecha_inicio')::date;
    exception when others then
      raise exception 'La fecha de inicio del contrato correcto no es válida' using errcode = '22023';
    end;
    if v_fi is null or not pg_catalog.isfinite(v_fi) then
      raise exception 'La fecha de inicio del contrato correcto no es válida' using errcode = '22023';
    end if;
    -- El alta exige que el analista de la venta siga activo en el equipo comercial: se dice antes de borrar nada.
    if v_orig.analista_cierre_id is null or not exists (select 1 from crm.equipo e
        where e.perfil_id = v_orig.analista_cierre_id and e.activo and e.rol_crm in ('vendedor', 'supervisor', 'gerencia')) then
      raise exception 'El analista de esta venta ya no está activo en el equipo: el reemplazo no puede conservarlo. No se hizo ningún cambio'
        using errcode = 'P0409';
    end if;
    v_contrato := (p_contrato - 'fecha_cierre_comercial') || jsonb_build_object(
      'cliente_id', v_orig.cliente_id, 'categoria', 'nuevo', 'analista_cierre_id', v_orig.analista_cierre_id);
    if not (p_contrato ? 'titulares') and v_titulares is not null then
      v_contrato := v_contrato || jsonb_build_object('titulares', v_titulares);
    end if;
  else
    if p_conservar = p_fuente then
      raise exception 'Elige otra inversión para conservar' using errcode = '22023';
    end if;
    -- La fila y sus leads ya se bloquearon antes del contexto (candado consultivo → fila → leads).
    if v_cons.id is null then
      raise exception 'La inversión que se conserva no existe' using errcode = 'P0002';
    end if;
    if v_cons.cliente_id is distinct from v_orig.cliente_id then
      raise exception 'Las dos inversiones tienen que ser del mismo cliente' using errcode = '22023';
    end if;
    if v_cons.analista_cierre_id is distinct from v_orig.analista_cierre_id then
      raise exception 'La inversión que se conserva es de otro analista: el analista de la venta no cambia en un reemplazo'
        using errcode = '22023';
    end if;
    if v_cons.categoria is distinct from 'nuevo' or coalesce(v_cons.es_demo, false) or v_cons.estado is distinct from 'activo'
       or exists (select 1 from crm.operaciones_cartera o where o.contrato_origen_id = p_conservar or o.contrato_nuevo_id = p_conservar) then
      raise exception 'La inversión que se conserva tiene que ser una inversión nueva y activa, sin upgrade ni renovación'
        using errcode = 'P0409';
    end if;
    if private.contrato_en_eliminacion(p_conservar) then
      raise exception 'La inversión que se conserva está en proceso de eliminación' using errcode = '55000';
    end if;
    -- «Cargada dos veces»: la que se conserva tiene que ser IGUAL a la original. Si no, es otra inversión y conservar ahí la
    -- venta sería quitarle su dinero sin anularla (revisión de negocio, P1): para otros datos, el reemplazo con alta nueva.
    if (v_cons.capital, v_cons.moneda, v_cons.tasa_anual, v_cons.fecha_inicio, v_cons.fecha_vencimiento, v_cons.modalidad,
        v_cons.tipo_interes) is distinct from (v_orig.capital, v_orig.moneda, v_orig.tasa_anual, v_orig.fecha_inicio,
        v_orig.fecha_vencimiento, v_orig.modalidad, v_orig.tipo_interes) then
      raise exception 'La inversión que se conserva no es igual a la original (capital, moneda, tasa, fechas o modalidad): no es una carga doble. Usa el reemplazo con los datos correctos'
        using errcode = 'P0409';
    end if;
    -- Los mismos cotitulares (por documento): si no, conservarla dejaría el contrato vigente sin la cotitularidad que tenía
    -- la original (Codex r2, P2). Para cambiarlos, el reemplazo con los datos correctos o «Corregir».
    -- Ordenado por la EXPRESIÓN (dentro de un agregado, «order by 1» ordena por la constante 1: auditor-rls r2, P2).
    if (select coalesce(pg_catalog.array_agg(x.k order by x.k), '{}')
          from (select coalesce(t.tipo_documento, '') || ':' || coalesce(pg_catalog.upper(pg_catalog.btrim(t.documento)), '') as k
                from public.contrato_titulares t where t.contrato_id = p_conservar) x)
       is distinct from
       (select coalesce(pg_catalog.array_agg(x.k order by x.k), '{}')
          from (select coalesce(t.tipo_documento, '') || ':' || coalesce(pg_catalog.upper(pg_catalog.btrim(t.documento)), '') as k
                from public.contrato_titulares t where t.contrato_id = p_fuente) x) then
      raise exception 'La inversión que se conserva no tiene los mismos cotitulares que la original: no es una carga doble. Corrige los cotitulares o usa el reemplazo con los datos correctos'
        using errcode = 'P0409';
    end if;
    if exists (select 1 from crm.leads l where l.contrato_id = p_conservar and l.etapa = 'convertido' and l.id is distinct from v_lead)
       or exists (select 1 from crm.conversion_acreditaciones ca
                  where ca.fuente_tipo = 'contrato' and ca.fuente_id = p_conservar and ca.lead_id is distinct from v_lead) then
      raise exception 'La inversión que se conserva ya es la venta de otro lead' using errcode = 'P0409';
    end if;
    v_fi := v_cons.fecha_inicio;
  end if;
  -- La fecha de cierre comercial que habría tenido si se hubiera registrado bien EL DÍA DE LA VENTA
  -- (private.definir_periodo_comercial_contrato: least(fecha_inicio, día de registro)); en «quedarme con la otra» también:
  -- que la duplicada se cargara más tarde no muda la venta de mes (revisión de negocio, P1). Una fecha que Gerencia ya
  -- corrigió (correccion_manual) o una migrada se conserva tal cual.
  if v_orig.fuente_cierre_comercial in ('registro', 'fecha_inicio_inferida') then
    v_fecha_cc := least(v_fi, v_dia_registro);
    v_fuente_cc := case when v_fi < v_dia_registro then 'fecha_inicio_inferida' else 'registro' end;
  else
    v_fecha_cc := v_orig.fecha_cierre_comercial;
    v_fuente_cc := v_orig.fuente_cierre_comercial;
  end if;

  -- Meses: el del original, el de su acreditación, el de la fecha que queda y el que el alta calcula hoy (su trigger de
  -- periodo bloquea ese). Candados mensuales en orden, con las llaves de crm.cerrar_periodo (el global ya está tomado).
  if v_modo = 'nueva' then
    v_mes_alta := pg_catalog.date_trunc('month', least(v_fi, (now() at time zone 'America/Lima')::date)::timestamp)::date;
  end if;
  v_periodos := array(select distinct x from unnest(array[
      pg_catalog.date_trunc('month', v_orig.fecha_cierre_comercial::timestamp)::date,
      v_acr.periodo_comercial,
      pg_catalog.date_trunc('month', v_fecha_cc::timestamp)::date,
      v_mes_alta,
      pg_catalog.date_trunc('month', v_cons.fecha_cierre_comercial::timestamp)::date,
      -- El mes de la venta según el lead: el que mira private.mes_sellado_de_venta cuando NO hay acreditación (con
      -- acreditación manda su mes; sumarlo siempre rechazaría de más: revisión de negocio, P3).
      (select pg_catalog.date_trunc('month', (l.convertido_en at time zone 'America/Lima'))::date
         from crm.leads l where l.id = v_lead and v_acr.id is null),
      (select pg_catalog.date_trunc('month', (coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima'))::date
         from crm.lead_asignaciones la where la.lead_id = v_lead and la.resultado = 'convertido' and v_acr.id is null limit 1)]) x
    where x is not null order by x);
  -- El contexto ya tiene el mensual del original (después de las filas, como «Eliminar inversión»). Los DEMÁS meses se piden
  -- SIN esperar: pedirlos esperando después de tener uno puede cruzarse con un escritor que los pide en orden (Codex r1,
  -- P2). Si alguno está ocupado, nada se hizo todavía y se pide reintentar.
  foreach v_p in array v_periodos loop
    if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'), (v_p - date '2000-01-01')::integer) then
      raise exception 'Otra operación está usando el mes %; vuelve a intentar en unos segundos', pg_catalog.to_char(v_p, 'MM/YYYY')
        using errcode = 'PT409';
    end if;
  end loop;
  -- Un mes sellado no se reescribe, y tampoco uno que quedó POR DETRÁS del último sello (cerrar_periodo ya no lo sellaría:
  -- misma regla que crm.eliminar_lead_error_carga). El borrado auditado no lo comprueba: se rechaza aquí, ANTES de borrar.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= v_periodos[1])
     or exists (select 1 from crm.capital_mes_sellos s where s.periodo >= v_periodos[1]) then
    raise exception 'El mes de esta venta ya está cerrado: no se reemplaza' using errcode = 'P0409',
      hint = 'Un mes sellado no se reescribe.';
  end if;
  if v_lead is not null then
    -- El detector de las anulaciones (también cubre ventas anteriores a septiembre, cuyo mes sale del episodio).
    select * into v_venta from private.mes_sellado_de_venta(v_lead);
    if v_venta.p_desconocido or v_venta.p_sellado then
      raise exception 'El mes de esta venta ya está cerrado o no se puede determinar: no se reemplaza' using errcode = 'P0409';
    end if;
  end if;
  -- Re-acreditar reinicia el reloj de la venta a AHORA (private.conversion_acreditar_fuente): con el plazo de carga del mes
  -- vencido, la venta quedaría fuera de plazo. Se dice antes de borrar nada.
  if v_mueve_venta and v_acr.estado = 'acreditada'
     and pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(pg_catalog.date_trunc('month', v_fecha_cc::timestamp)::date) then
    raise exception 'Venció el plazo de carga de %: el reemplazo dejaría la venta fuera de plazo. No se hizo ningún cambio',
      pg_catalog.to_char(v_fecha_cc, 'MM/YYYY') using errcode = 'P0409';
  end if;

  -- La inversión del original es la primera conversión de la persona: el contrato que queda hereda la marca.
  select i.es_primera_conversion into v_primera from crm.inversiones i where i.id = (v_ctx ->> 'inversion_id')::uuid;

  -- c. Antes de borrar: el candado de tasa de lo que ESTA transacción ya escribió (la fuente misma, si es el resultado de un
  -- reemplazo anterior aún sin juzgar) corre AHORA. Borrada sin juzgar, su copia legitimaría la tasa del siguiente
  -- (A → B → C en una transacción: Codex r2, P1). Luego, diferido: el candado reconoce el alta que viene por su COPIA (que
  -- se escribe al final), así que tiene que juzgarla al commit aunque quien llama haya puesto las restricciones en
  -- IMMEDIATE. Diferirlo nunca lo debilita: corre igual, más tarde.
  set constraints public.trg_contratos_zz_observar_rentabilidad immediate;
  set constraints public.trg_contratos_zz_observar_rentabilidad deferred;

  -- Eliminar el original con copia y PDF conservados, SIN anular la venta.
  v_priv_previa := current_setting('crm.op_privilegiada', true);
  if cardinality(v_leads) > 0 then
    -- El SET NULL de leads.contrato_id lo revierte private.leads_before_update sin la válvula (ver crm.eliminar_inversion_fn).
    -- Encendida SOLO durante el borrado; se vuelve a encender solo para el re-enlace.
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  end if;
  v_res := crm.contrato_eliminar_auditado(p_fuente, p_actor);
  perform pg_catalog.set_config('crm.op_privilegiada', coalesce(nullif(v_priv_previa, ''), 'off'), true);

  -- d. La inversión que queda.
  if v_modo = 'nueva' then
    v_alta := crm.crear_contrato_con_cuenta_pdf_v2(v_contrato, p_cronograma, p_cuenta);
    begin
      v_nuevo := (v_alta ->> 'id')::uuid;
    exception when invalid_text_representation then
      v_nuevo := null;
    end;
    if v_nuevo is null or coalesce((v_alta ->> 'idempotente')::boolean, false) then
      raise exception 'El alta del contrato correcto no devolvió un contrato nuevo' using errcode = 'P0001';
    end if;
  else
    v_nuevo := p_conservar;
  end if;
  select c.fecha_cierre_comercial, c.fuente_cierre_comercial into v_nuevo_cc, v_nuevo_fuente_cc
    from public.contratos c where c.id = v_nuevo for update;
  if v_nuevo_cc is distinct from v_fecha_cc or v_nuevo_fuente_cc is distinct from v_fuente_cc then
    -- Misma válvula que crm.corregir_fecha_cierre_comercial; los meses implicados ya están bloqueados y sin sello.
    v_corr_previa := current_setting('crm.correccion_periodo_comercial', true);
    perform pg_catalog.set_config('crm.correccion_periodo_comercial', 'on', true);
    update public.contratos c set fecha_cierre_comercial = v_fecha_cc, fuente_cierre_comercial = v_fuente_cc where c.id = v_nuevo;
    perform pg_catalog.set_config('crm.correccion_periodo_comercial', coalesce(nullif(v_corr_previa, ''), 'off'), true);
    -- La inversión acompaña a su contrato (revisión de negocio, P3) y el capital se vuelve a valorar con la fecha buena.
    update crm.inversiones i set fecha_comercial = v_fecha_cc where i.contrato_id = v_nuevo and i.fecha_comercial is distinct from v_fecha_cc;
    perform private.materializar_capital_valoraciones_para(1, 'contrato', v_nuevo);
  end if;
  if v_origen_conf.id is not null and not exists (select 1 from crm.origenes_capital_confirmados o
      where o.contrato_id = v_nuevo and o.activo and o.origen = v_origen_conf.origen) then
    -- El origen confirmado pasa al contrato que queda (Gerencia, comprobado antes de borrar; revisión de negocio, P2).
    insert into crm.origenes_capital_confirmados (contrato_id, origen, motivo, confirmado_por)
      values (v_nuevo, v_origen_conf.origen, left('Reemplazo de inversión: ' || v_origen_conf.motivo, 500), p_actor);
  end if;
  if coalesce(v_primera, false) then
    update crm.inversiones i set es_primera_conversion = true where i.contrato_id = v_nuevo and not i.es_primera_conversion;
  end if;

  -- e. Volver a enlazar el lead y mover la acreditación con su único escritor.
  if v_mueve_venta then
    -- Primero la acreditación con su único escritor (motivo propio); el enlace de después entra por su rama idempotente.
    perform private.conversion_acreditar_fuente(v_lead, 'contrato', v_nuevo, 'Reemplazo de inversión: ' || left(p_motivo, 270));
  end if;
  if cardinality(v_leads) > 0 then
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
    update crm.leads l set contrato_id = v_nuevo where l.id = any (v_leads);
    perform pg_catalog.set_config('crm.op_privilegiada', coalesce(nullif(v_priv_previa, ''), 'off'), true);
    -- Sin la válvula, private.leads_before_update deja el enlace como estaba SIN error: se comprueba el resultado.
    if exists (select 1 from crm.leads l where l.id = any (v_leads) and l.contrato_id is distinct from v_nuevo) then
      raise exception 'No se pudo volver a enlazar el lead al contrato que queda; no se hizo ningún cambio' using errcode = '55000';
    end if;
  end if;
  if v_lead is not null and not v_mueve_venta
     and exists (select 1 from crm.conversion_acreditaciones ca where ca.lead_id = v_lead) then
    -- La venta no tenía acreditación: el reemplazo no la crea (la conversión no cambia) (Codex r1, P1).
    raise exception 'El reemplazo crearía una acreditación nueva para esta venta; requiere revisión. No se hizo ningún cambio'
      using errcode = 'P0409';
  end if;
  if v_mueve_venta then
    -- f. INVARIANTE: misma venta (estado, episodio, analista, persona, origen) y el mes de la fecha que queda; solo cambian
    -- la fuente y, si cambió la fecha, el mes.
    select * into v_acr2 from crm.conversion_acreditaciones ca where ca.lead_id = v_lead;
    if v_acr2.id is distinct from v_acr.id or v_acr2.fuente_tipo is distinct from 'contrato'
       or v_acr2.fuente_id is distinct from v_nuevo or v_acr2.estado is distinct from v_acr.estado
       or v_acr2.episodio_id is distinct from v_acr.episodio_id or v_acr2.analista_id is distinct from v_acr.analista_id
       or v_acr2.inversionista_id is distinct from v_acr.inversionista_id or v_acr2.origen is distinct from v_acr.origen
       or v_acr2.periodo_comercial is distinct from pg_catalog.date_trunc('month', v_fecha_cc::timestamp)::date then
      raise exception using errcode = 'P0409',
        message = case when v_acr2.estado = 'fuera_de_plazo' and v_acr.estado is distinct from 'fuera_de_plazo'
          then 'El plazo de carga de ' || pg_catalog.to_char(v_acr2.periodo_comercial, 'MM/YYYY')
               || ' ya cerró: el reemplazo no puede conservar la venta. No se hizo ningún cambio'
          else 'El reemplazo cambiaría la conversión de esta venta. No se hizo ningún cambio' end,
        detail = pg_catalog.jsonb_build_object(
          'antes', pg_catalog.jsonb_build_object('estado', v_acr.estado, 'periodo', v_acr.periodo_comercial),
          'despues', pg_catalog.jsonb_build_object('estado', v_acr2.estado, 'periodo', v_acr2.periodo_comercial))::text;
    end if;
  end if;

  -- g. La copia del original.
  v_rol := case when v_es_conversion or v_origen_conf.id is not null then 'gerencia' else v_portal end;
  v_aud := private.registrar_inversion_reemplazada_avance(v_ctx, (v_res ->> 'auditoria_id')::uuid, p_actor, v_rol, p_motivo,
    v_nuevo, v_modo, jsonb_build_object('acreditacion_antes', case when v_acr.id is not null then to_jsonb(v_acr) end,
      'dia_registro_venta', v_dia_registro, 'huella_pedido', v_huella_pedido,
      'origen_confirmado', v_origen_conf.id is not null));

  return coalesce(v_alta - 'idempotente', '{}'::jsonb) || jsonb_build_object(
    'ok', true,
    'modo', v_modo,
    'fuente_id', p_fuente,
    'contrato_id', v_nuevo,
    'numero_contrato', (select c.numero_contrato from public.contratos c where c.id = v_nuevo),
    'auditoria_id', v_aud,
    'conversion', case when v_mueve_venta then jsonb_build_object(
      'lead_id', v_lead, 'estado', v_acr2.estado, 'lead_enlazado', v_lead_sin_enlace,
      'periodo_antes', v_acr.periodo_comercial, 'periodo_despues', v_acr2.periodo_comercial) end);
end
$function$;

-- ── 4 · Puertas ────────────────────────────────────────────────────────────────────────────────────────────────────────
create function crm.reemplazar_inversion_fn(p_fuente_id uuid, p_motivo text, p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_motivo text := private.motivo_normalizado(p_motivo);
begin
  if v_uid is null then
    raise exception 'Inicia sesión para reemplazar inversiones' using errcode = '42501';
  end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'El reemplazo exige READ COMMITTED' using errcode = '0A000';
  end if;
  v_roles := private.eliminar_inversion_roles(v_uid);
  if v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  -- Hoy el reemplazo es solo de Avance y su borrado auditado exige admin del portal: sin él no se toma ningún candado
  -- (revisión de seguridad, P3). Una membresía del CRM revocada tampoco reemplaza, como en la corrección de tasa de admin.
  if v_roles ->> 'portal' is null then
    raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  if coalesce(length(v_motivo), 0) < 5 then
    raise exception 'Escribe el motivo del reemplazo (al menos 5 caracteres)' using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como máximo 300 caracteres' using errcode = '22023';
  end if;
  begin
    return private.reemplazar_inversion_avance(v_uid, v_roles, p_fuente_id, v_motivo, p_contrato, p_cronograma, p_cuenta, null);
  exception when deadlock_detected or lock_not_available then
    -- Otra operación (un cierre de mes, un alta del mismo cliente, una anulación) tenía lo que el reemplazo necesitaba. Nada
    -- quedó hecho: la transacción se revierte entera (revisión de concurrencia, P2).
    raise exception 'Hay un cierre de mes u otra operación sobre esta venta en curso; vuelve a intentar en unos segundos. No se hizo ningún cambio'
      using errcode = 'PT409';
  end;
end
$function$;

create function crm.reemplazar_inversion_por_existente_fn(p_fuente_id uuid, p_conservar_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_motivo text := private.motivo_normalizado(p_motivo);
begin
  if v_uid is null then
    raise exception 'Inicia sesión para reemplazar inversiones' using errcode = '42501';
  end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'El reemplazo exige READ COMMITTED' using errcode = '0A000';
  end if;
  v_roles := private.eliminar_inversion_roles(v_uid);
  if v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  -- Hoy el reemplazo es solo de Avance y su borrado auditado exige admin del portal: sin él no se toma ningún candado
  -- (revisión de seguridad, P3). Una membresía del CRM revocada tampoco reemplaza, como en la corrección de tasa de admin.
  if v_roles ->> 'portal' is null then
    raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  if coalesce(length(v_motivo), 0) < 5 then
    raise exception 'Escribe el motivo del reemplazo (al menos 5 caracteres)' using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como máximo 300 caracteres' using errcode = '22023';
  end if;
  if p_conservar_id is null then
    raise exception 'Elige la inversión que se conserva' using errcode = '22023';
  end if;
  begin
    return private.reemplazar_inversion_avance(v_uid, v_roles, p_fuente_id, v_motivo, null, null, null, p_conservar_id);
  exception when deadlock_detected or lock_not_available then
    -- Otra operación (un cierre de mes, un alta del mismo cliente, una anulación) tenía lo que el reemplazo necesitaba. Nada
    -- quedó hecho: la transacción se revierte entera (revisión de concurrencia, P2).
    raise exception 'Hay un cierre de mes u otra operación sobre esta venta en curso; vuelve a intentar en unos segundos. No se hizo ningún cambio'
      using errcode = 'PT409';
  end;
end
$function$;

-- ── 5 · Candado de tasa: la tasa del original se hereda en el alta de un reemplazo ────────────────────────────────────
-- Cuerpo de PRODUCCIÓN (huella del preflight) + 5 cambios por ancla, cada ancla presente UNA sola vez.
do $tasa$
declare
  v_def text := pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure);
  v_cambios text[][] := array[
    array['  v_admin_motivo text;
',
          '  v_admin_motivo text;
  v_reemplazo_tasa boolean := false;   -- 17/10/2026: alta que deja un reemplazo y conserva la tasa del original
  v_reemplazo_misma_huella boolean := false;   -- …y además con la misma intención (capital, moneda, plazo, modalidad)
'],
    array['  v_enforce := (v_modo = ''enforcement'');
',
          '  v_enforce := (v_modo = ''enforcement'');
  -- 17/10/2026 (Reemplazar inversión, 20261017162053): la tasa del original se HEREDA. Solo en el INSERT del contrato que
  -- deja un reemplazo, reconocido por su EVIDENCIA PRIVADA: la copia de crm.inversiones_eliminadas que lo nombra como
  -- reemplazada_por, escrita en ESTA transacción por private.reemplazar_inversion_avance (la API no tiene permisos sobre
  -- esa tabla), con la MISMA tasa que el contrato eliminado según su auditoría; categoría nuevo y un admin del portal
  -- registrando. Solo salta la autorización (enforcement, y solo para la MISMA intención) y el tope técnico (observación,
  -- con cualquier intención: igual que una corrección del contrato, que en observación conserva la tasa aunque cambien
  -- capital o plazo). Tasa positiva, dos decimales, el 50, sin_regla y la respuesta pendiente siguen igual.
  v_reemplazo_tasa := tg_op = ''INSERT'' and v_c.categoria = ''nuevo'' and coalesce(public.es_admin(), false)
    and exists (select 1 from crm.inversiones_eliminadas ie
                join crm.contratos_eliminados_auditoria a on a.id = ie.contrato_auditoria_id
                where ie.reemplazada_por = v_c.id and ie.transaccion = pg_catalog.pg_current_xact_id()
                  and ie.snapshot #>> ''{reemplazo,modo}'' = ''nueva''
                  and (a.snapshot #>> ''{contrato,tasa_anual}'')::numeric = v_c.tasa_anual);
  -- Bajo enforcement la herencia vale como una CORRECCIÓN del original: si la intención se movió (capital, moneda, fechas,
  -- modalidad, tipo de interés, condición de producto declarada), la tasa por encima de la base vuelve a pedir autorización.
  v_reemplazo_misma_huella := v_reemplazo_tasa
    and exists (select 1 from crm.inversiones_eliminadas ie
                join crm.contratos_eliminados_auditoria a on a.id = ie.contrato_auditoria_id
                where ie.reemplazada_por = v_c.id and ie.transaccion = pg_catalog.pg_current_xact_id()
                  and (a.snapshot #>> ''{contrato,capital}'')::numeric = v_c.capital
                  and a.snapshot #>> ''{contrato,moneda}'' = v_c.moneda
                  and (a.snapshot #>> ''{contrato,fecha_inicio}'')::date = v_c.fecha_inicio
                  and (a.snapshot #>> ''{contrato,fecha_vencimiento}'')::date = v_c.fecha_vencimiento
                  and a.snapshot #>> ''{contrato,modalidad}'' is not distinct from v_c.modalidad
                  and a.snapshot #>> ''{contrato,tipo_interes}'' is not distinct from v_c.tipo_interes
                  and private.rentabilidad_condicion_declarada((a.snapshot #>> ''{contrato,producto_condicion_id}'')::uuid)
                      is not distinct from private.rentabilidad_condicion_declarada(v_c.producto_condicion_id));
'],
    array['      elsif v_c.tasa_anual > v_base then
',
          '      elsif v_c.tasa_anual > v_base and v_reemplazo_misma_huella then
        null;   -- 17/10/2026: la tasa heredada del original, para la MISMA intención, no pide autorización nueva
      elsif v_c.tasa_anual > v_base then
'],
    array['    ''correccion_admin_directa'', case when v_admin_corr then true end,
',
          '    ''correccion_admin_directa'', case when v_admin_corr then true end,
    ''reemplazo_tasa_heredada'', case when v_reemplazo_tasa then true end,
    ''reemplazo_de'', case when v_reemplazo_tasa then (select pg_catalog.jsonb_build_object(''contrato_id'', ie.fuente_id,
        ''inversion_eliminada_id'', ie.id, ''numero_contrato'', ie.snapshot #>> ''{contrato,numero_contrato}'', ''tasa_heredada'', v_c.tasa_anual)
      from crm.inversiones_eliminadas ie where ie.reemplazada_por = v_c.id and ie.transaccion = pg_catalog.pg_current_xact_id() limit 1) end,
'],
    array['greatest(v_pol.tope_tecnico,case when v_c.categoria in (''renovacion'',''upgrade'') and v_regla in (''heredada_renovacion'',''heredada_upgrade'') then v_base else 0 end)',
          'greatest(v_pol.tope_tecnico,case when v_c.categoria in (''renovacion'',''upgrade'') and v_regla in (''heredada_renovacion'',''heredada_upgrade'') then v_base else 0 end,case when v_reemplazo_tasa then v_c.tasa_anual else 0 end)']
  ];
  i int;
begin
  for i in 1 .. array_length(v_cambios, 1) loop
    if (length(v_def) - length(replace(v_def, v_cambios[i][1], ''))) / length(v_cambios[i][1]) <> 1 then
      raise exception 'tasa: el ancla % no aparece exactamente una vez', i;
    end if;
    v_def := replace(v_def, v_cambios[i][1], v_cambios[i][2]);
  end loop;
  -- El DDL resultante es EXACTAMENTE el ensayado en el banco (misma huella que exige el postflight).
  if md5(v_def) is distinct from '1606e0a61a83f80a7873d7fafe7c4faa' then
    raise exception 'tasa: el cuerpo resultante no es el ensayado';
  end if;
  execute v_def;
end
$tasa$;

-- ── 6 · Permisos ───────────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function private.registrar_inversion_reemplazada_avance(jsonb, uuid, uuid, text, text, uuid, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.reemplazar_inversion_avance(uuid, jsonb, uuid, text, jsonb, jsonb, jsonb, uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.reemplazar_inversion_fn(uuid, text, jsonb, jsonb, jsonb) from public, anon, service_role;
grant execute on function crm.reemplazar_inversion_fn(uuid, text, jsonb, jsonb, jsonb) to authenticated;
revoke all on function crm.reemplazar_inversion_por_existente_fn(uuid, uuid, text) from public, anon, service_role;
grant execute on function crm.reemplazar_inversion_por_existente_fn(uuid, uuid, text) to authenticated;

-- ── 7 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on column crm.inversiones_eliminadas.reemplazada_por is
  'Reemplazo (17/10/2026): contrato que quedó en lugar de esta inversión (alta correcta o la otra inversión del mismo cliente '
  'cargada dos veces). Nula en una eliminación de siempre. La venta del lead pasó a ese contrato SIN anularse. Sin llave '
  'foránea a propósito: la copia es inmutable y no debe impedir eliminar después ese contrato por su puerta.';
comment on constraint inversiones_eliminadas_reemplazo_check on crm.inversiones_eliminadas is
  'Un reemplazo nunca es una conversión anulada ni se reemplaza por sí mismo.';
comment on function private.registrar_inversion_reemplazada_avance(jsonb, uuid, uuid, text, text, uuid, text, jsonb) is
  'Núcleo de «Reemplazar inversión»: copia inmutable del contrato de Avance reemplazado (molde de '
  'private.registrar_inversion_eliminada_avance): es_conversion como era, conversion_anulada = false y reemplazada_por. '
  'Exige que la eliminación auditada se haya confirmado y que el contrato que queda exista; 55000 si no.';
comment on function private.reemplazar_inversion_avance(uuid, jsonb, uuid, text, jsonb, jsonb, jsonb, uuid) is
  'Núcleo de «Reemplazar inversión» (Avance): en una sola transacción bloquea y clasifica el original (como «Eliminar '
  'inversión»), lo elimina con copia SIN anular la venta, da de alta el contrato correcto por la puerta de alta de siempre '
  '(o conserva la otra inversión del mismo cliente), vuelve a enlazar el lead, mueve la acreditación con su único escritor '
  'y aborta todo si la conversión no queda igual (mismo estado, episodio y analista). Rechaza: historia propia, venta '
  'anulada o de prueba, venta acreditada a otra inversión, mes sellado (conversión o capital) y otro cliente.';
comment on function crm.reemplazar_inversion_fn(uuid, text, jsonb, jsonb, jsonb) is
  'Puerta «Reemplazar inversión»: cambia una inversión de Avance cargada con error por la correcta (p_contrato, '
  'p_cronograma y p_cuenta como el alta de siempre; mismo cliente, categoría nuevo y mismo analista) y la venta del lead '
  'pasa a la nueva sin anularse. Admin del portal con membresía vigente; si es la venta de un lead, además Gerencia. Motivo '
  '5..300. Idempotente. Choques de candados → PT409 «vuelve a intentar». No se llama con service_role (sin EXECUTE).';
comment on function crm.reemplazar_inversion_por_existente_fn(uuid, uuid, text) is
  'Puerta «Reemplazar inversión» en modo «quedarme con la otra»: elimina la inversión de Avance cargada dos veces '
  '(p_fuente_id) y la venta del lead pasa a la otra inversión del mismo cliente (p_conservar_id) sin anularse. Mismos '
  'permisos y rechazos que crm.reemplazar_inversion_fn. Idempotente. No se llama con service_role (sin EXECUTE).';

-- ── 8 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
begin
  if md5(pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure))
       is distinct from '1606e0a61a83f80a7873d7fafe7c4faa' then
    raise exception 'POSTFLIGHT: el candado de tasa no quedó con la huella esperada';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p where p.oid = 'private.trg_contratos_observar_rentabilidad()'::regprocedure
                 and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 'v'
                 and p.proconfig = array['search_path=""', 'lock_timeout=2s']
                 and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'POSTFLIGHT: dueño, seguridad, configuración o permisos del candado de tasa';
  end if;
  -- Ninguna FK nueva hacia contratos, inversiones o la copia (romperían en silencio las eliminaciones de siempre).
  if private.inversion_eliminacion_dependencias_conocidas() is not true
     or (select pg_catalog.string_agg(t.tgname, ',' order by t.tgname) from pg_catalog.pg_trigger t
         where t.tgrelid = 'crm.inversiones_eliminadas'::regclass and not t.tgisinternal)
        is distinct from 'trg_audit_inversiones_eliminadas,trg_inversiones_eliminadas_inmutables,trg_inversiones_eliminadas_no_truncate' then
    raise exception 'POSTFLIGHT: dependencias de las eliminaciones o candados de la copia';
  end if;
  -- F7 por su cuenta (en producción el vigía puede estar ya en rojo por otra pieza y lanzar en el PRIMER fallo): ninguna
  -- función nueva ni el candado de tasa nombran una pieza cerrada. Misma normalización que private.assert_f7_piezas_cerradas.
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid in ('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure,
                             'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure,
                             'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure,
                             'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure,
                             'private.trg_contratos_observar_rentabilidad()'::regprocedure)
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT: una función nueva nombra una pieza cerrada de F7';
  end if;
  -- Vigencia del analista: nada nuevo entra a su censo (su tope solo baja).
  if exists (select 1 from private.puertas_analista_sin_vigencia() c
             where c.objeto in ('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)',
                                'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)',
                                'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)',
                                'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo de vigencia del analista';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
             where p.oid in ('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure,
                             'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure)
               and a.grantee <> p.proowner and a.grantee <> 'authenticated'::regrole)
     or exists (select 1 from pg_catalog.pg_proc p
                cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                where p.oid in ('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure,
                                'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure)
                  and a.grantee <> p.proowner)
     or not has_function_privilege('authenticated', 'crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)', 'execute') then
    raise exception 'POSTFLIGHT: permisos de las funciones nuevas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure,
                             'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure,
                             'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure,
                             'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure)
               and p.proowner <> 'postgres'::regrole) then
    raise exception 'POSTFLIGHT: dueño de las funciones nuevas';
  end if;
  if (select pg_catalog.bool_and(p.prosecdef and p.proconfig @> array['search_path=""']) from pg_catalog.pg_proc p
      where p.oid in ('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure,
                      'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure)) is not true
     or (select pg_catalog.bool_or(p.prosecdef) or not pg_catalog.bool_and(p.proconfig @> array['search_path=""'])
         from pg_catalog.pg_proc p
         where p.oid in ('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure,
                         'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure)) then
    raise exception 'POSTFLIGHT: puertas DEFINER y núcleo INVOKER, todos con search_path vacío';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in ('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)',
                                'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)',
                                'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)',
                                'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo analítico';
  end if;
  if has_table_privilege('authenticated', 'crm.inversiones_eliminadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_table_privilege('anon', 'crm.inversiones_eliminadas', 'select, insert, update, delete, truncate, references, trigger')
     or has_table_privilege('service_role', 'crm.inversiones_eliminadas', 'select, insert, update, delete, truncate, references, trigger') then
    raise exception 'POSTFLIGHT: permisos de crm.inversiones_eliminadas';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
