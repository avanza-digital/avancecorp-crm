-- 20261018053228_crm_reemplazar_inversion_cooperativa.sql
--
-- «Reemplazar inversión», Fase 4: COOPERATIVAS (Prodelco y Qorilazo, crm.cierres_externos). Misma idea que la Fase 1 de
-- Avance (20261017162053): una inversión de cooperativa cargada con error se cambia por la correcta EN UN SOLO PASO, la
-- original se elimina con una copia «reemplazada por» (crm.inversiones_eliminadas.reemplazada_por) y la venta del lead pasa a
-- la nueva SIN anularse. Plan: vault «Reemplazar inversion - plan por fases (2026-10-17)». Decisiones de Miguel (18/10/2026):
--   · Alcance: SOLO lo que «Corregir» (crm.inversionista_corregir_coopac_fn) no corrige: la cooperativa, la fecha comercial (el
--     mes de la venta) y el comprobante. Monto, moneda, plazo, tasa, número de operación, referencia y nota NO cambian aquí:
--     el reemplazo los copia tal cual de la original (para eso está «Corregir», que conserva la venta).
--   · Quién: Gerencia o admin del portal (los mismos que hoy eliminan una cooperativa).
--   · Comprobante: se reutiliza el de la original salvo que suban otro (p_cierre ->> 'comprobante_ruta').
--   · Rechazos: los de Avance (mes sellado, plazo de carga vencido, venta anulada, lead por revisar) más «ya tiene
--     movimientos» (private.inversion_motivo_no_eliminable: reinversión, retiro, ajustes de mes cerrado, eventos propios).
--     Sin «quedarme con la otra»: el número de operación es único y una carga doble exacta no existe.
--   · Solo la inversión INICIAL de la cooperativa (es_cierre_inicial): un aporte adicional nace de una reinversión y la
--     regla de «movimientos» ya lo rechaza; se corrige o se elimina.
--
-- QUÉ HACE
--   1. private.registrar_inversion_reemplazada_cooperativa: la copia de la original en crm.inversiones_eliminadas (es_conversion
--      según el contexto, conversion_anulada FALSE, reemplazada_por = la nueva) y el borrado de la original con la MISMA válvula
--      de un solo uso que «Eliminar inversión» (crm.inversion_eliminacion → private.inversion_eliminacion_autoriza), hijos antes
--      que padres. Es el espejo de private.eliminar_inversion_cooperativa sin exigir la anulación (eso es lo que se evita).
--   2. private.reemplazar_inversion_cooperativa: la operación atómica. Candado global del cierre de mes, contexto y candados de
--      «Eliminar inversión», validaciones (abajo), candados de los meses implicados SIN esperar, copia + borrado, alta de la
--      nueva fila de crm.cierres_externos con el id ya decidido (los mismos datos salvo cooperativa, fecha comercial y
--      comprobante; el vencimiento se recalcula con la misma convención de plazo), depósito reclamado, fila de crm.inversiones
--      (private.inversion_vincular_fuente, el mismo escritor del alta), cotitulares y evento «registro»; la acreditación de la
--      venta pasa a la nueva con su único escritor (private.conversion_acreditar_fuente) e INVARIANTE: misma acreditación,
--      estado, episodio, analista, persona y origen; el mes, el de la fecha que queda.
--   3. crm.reemplazar_inversion_cooperativa_fn (puerta, authenticated) y crm.reemplazar_inversion_cooperativa_vista_previa_fn
--      (solo lectura: en qué mes queda la venta y qué se negaría, para decirlo ANTES de confirmar).
--   4. El comprobante NUEVO: la pantalla lo sube ANTES de confirmar a f4-comprobantes en <persona>/reemplazo-<cierre>/<archivo>.
--      Hoy el bucket solo admite rutas de una solicitud preparada (private.f4_comprobante_autorizado) y solo deja ver las
--      rutas de una solicitud (private.f4_comprobante_visible): se parchan POR ANCLA (huella antes y después) para admitir esa
--      ruta a Gerencia o admin del portal sobre la inversión inicial vigente de ESA persona, y para que el comprobante que ya
--      respalda una inversión se vea con la misma visibilidad que la ficha. private.f4_comprobante_reemplazo_autorizado es la
--      regla nueva, aparte, para que el ancla sea una línea.
--
-- CAPAS: puerta en crm (valida, autoriza, delega) → núcleo en private (INVOKER, sin EXECUTE para la API) → tablas. Sin tablas
-- nuevas. No toca public (storage.objects no cambia: cambian dos funciones de private que sus políticas ya llamaban). CENSO
-- ANALÍTICO: sin count( sobre leads. REVERSA: supabase/scripts/reemplazar-inversion-cooperativa/reversa.sql (retira las cinco
-- funciones nuevas y devuelve los dos ayudantes del bucket a su huella; las copias con reemplazada_por quedan como historia).
-- PRUEBAS: probar.sh del kit.

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT reemplazar_cooperativa: esta sesión no tiene el candado de migraciones';
  end if;
  -- Lo que se llama, tal como se ensayó (huellas medidas en producción y en el banco el 18/10/2026).
  if (select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
      from pg_catalog.pg_proc p
      where p.oid in ('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure,
                      'private.conversion_coordinar_retiro_fuente(text,uuid)'::regprocedure,
                      'private.conversion_plazo_hasta(date)'::regprocedure,
                      'private.coopac_validar_condiciones_base(date,integer,numeric,text)'::regprocedure,
                      'private.eliminar_inversion_contexto(uuid)'::regprocedure,
                      'private.eliminar_inversion_cooperativa(jsonb,uuid,text,text,jsonb)'::regprocedure,
                      'private.eliminar_inversion_roles(uuid)'::regprocedure,
                      'private.inversion_eliminacion_autoriza(text,uuid,jsonb)'::regprocedure,
                      'private.inversion_eliminacion_dependencias_conocidas()'::regprocedure,
                      'private.inversion_motivo_no_eliminable(text,uuid,uuid)'::regprocedure,
                      'private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)'::regprocedure,
                      'private.inversionista_canonica(uuid)'::regprocedure,
                      'private.membresia_crm_revocada()'::regprocedure,
                      'private.mes_sellado_de_venta(uuid)'::regprocedure,
                      'private.motivo_normalizado(text)'::regprocedure))
     is distinct from 'private.conversion_acreditar_fuente(uuid,text,uuid,text)=872930922a1d477e27b23243cbfe691a,'
                      'private.conversion_coordinar_retiro_fuente(text,uuid)=6fd4bab73f10b9d179b9156afc2b50b0,'
                      'private.conversion_plazo_hasta(date)=4ce984684a471d20aa779365c9b92452,'
                      'private.coopac_validar_condiciones_base(date,integer,numeric,text)=b32f7418510ee1d529e867c89ef5533e,'
                      'private.eliminar_inversion_contexto(uuid)=3d87226acfb1eda521dd9fef173fe256,'
                      'private.eliminar_inversion_cooperativa(jsonb,uuid,text,text,jsonb)=88d0b29cb08c208f230f7019713da9d9,'
                      'private.eliminar_inversion_roles(uuid)=e9a2341105e4028565f81164d5e02c4c,'
                      'private.inversion_eliminacion_autoriza(text,uuid,jsonb)=155080f96d6efda6517d65d369a9b986,'
                      'private.inversion_eliminacion_dependencias_conocidas()=aed03021c2403d762f1b22d152aad585,'
                      'private.inversion_motivo_no_eliminable(text,uuid,uuid)=408fb7ce87130a81e052cbfa83e1b24b,'
                      'private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)=9a08e3b5ba288ab6614ef6e819337795,'
                      'private.inversionista_canonica(uuid)=34702897135078893b7d3a726b0c1816,'
                      'private.membresia_crm_revocada()=47f8ceb6455f4855562941a7057be02c,'
                      'private.mes_sellado_de_venta(uuid)=ba2cfaaa3337a05a6cd7c32cd6af8e8c,'
                      'private.motivo_normalizado(text)=08602d4022e0731952cbf61c28efe9d7' then
    raise exception 'PREFLIGHT reemplazar_cooperativa: cambió una función que el reemplazo llama';
  end if;
  -- La Fase 1 de Avance (la copia recuerda qué quedó) tiene que estar.
  if not exists (select 1 from pg_catalog.pg_attribute a
                 where a.attrelid = 'crm.inversiones_eliminadas'::regclass and a.attname = 'reemplazada_por' and not a.attisdropped)
     or not exists (select 1 from pg_catalog.pg_constraint c where c.conname = 'inversiones_eliminadas_reemplazo_check') then
    raise exception 'PREFLIGHT reemplazar_cooperativa: falta la Fase 1 (20261017162053: inversiones_eliminadas.reemplazada_por)';
  end if;
  -- Los dos ayudantes del bucket que se cambian, tal como están en producción (18/10/2026), con sus metadatos.
  if (select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
      from pg_catalog.pg_proc p
      where p.oid in ('private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure))
     is distinct from 'private.f4_comprobante_autorizado(text)=7cdb9ea79f143edf53f0663b2d37aeae,'
                      'private.f4_comprobante_visible(text)=45fb7ff24d69f7a685cdc45902aedf9e' then
    raise exception 'PREFLIGHT reemplazar_cooperativa: cambió un ayudante del bucket de comprobantes que esta migración parcha';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure)
               and (p.proowner <> 'postgres'::regrole or not p.prosecdef or not ('search_path=""' = any (p.proconfig))
                    or not has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                    or has_function_privilege('service_role', p.oid, 'execute'))) then
    raise exception 'PREFLIGHT reemplazar_cooperativa: cambiaron los metadatos de un ayudante del bucket de comprobantes';
  end if;
  if to_regprocedure('private.f4_comprobante_reemplazo_autorizado(text)') is not null
     or to_regprocedure('private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)') is not null
     or to_regprocedure('private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)') is not null
     or to_regprocedure('crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)') is not null
     or to_regprocedure('crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)') is not null then
    raise exception 'PREFLIGHT reemplazar_cooperativa: las funciones nuevas ya existen';
  end if;
  -- Lo que la nueva fila copia de la original: si la tabla cambia de forma, se revisa el alta antes de aplicar.
  if (select pg_catalog.string_agg(a.attname, ',' order by a.attnum) from pg_catalog.pg_attribute a
      where a.attrelid = 'crm.cierres_externos'::regclass and a.attnum > 0 and not a.attisdropped)
     is distinct from 'id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,numero_transaccion,'
                      'referencia_externa,vence_en,nota,vendedor_id,creado_por,creado_en,anulado_en,anulado_por,motivo_anulacion,'
                      'inversionista_id,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id,plazo_meses,'
                      'tasa_anual,base_plazo' then
    raise exception 'PREFLIGHT reemplazar_cooperativa: crm.cierres_externos cambió de forma; revisar qué copia el reemplazo';
  end if;
end
$preflight$;

-- ── 1 · Núcleo: la copia del original reemplazado y su borrado (espejo de private.eliminar_inversion_cooperativa) ──────
create function private.registrar_inversion_reemplazada_cooperativa(p_ctx jsonb, p_actor uuid, p_rol text, p_motivo text,
  p_nuevo uuid, p_detalle jsonb)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  v_cierre uuid := (p_ctx ->> 'fuente_id')::uuid;
  v_inv uuid := (p_ctx ->> 'inversion_id')::uuid;
  v_es_conversion boolean := coalesce((p_ctx ->> 'es_conversion')::boolean, false);
  v_ce crm.cierres_externos%rowtype;
  v_id uuid;
  v_valvula uuid;
  v_previa text := current_setting('crm.inversion_eliminacion', true);
  v_no text;
begin
  if p_ctx ->> 'tipo' is distinct from 'cierre_externo' or p_nuevo is null or p_nuevo = v_cierre
     or p_rol is null or p_rol not in ('gerencia', 'admin', 'superadmin') then
    raise exception 'Reemplazo no válido para una inversión de cooperativa' using errcode = '22023';
  end if;
  if not private.inversion_eliminacion_dependencias_conocidas() then
    raise exception 'La inversión tiene dependencias nuevas; requiere revisión antes de reemplazarla' using errcode = '55000';
  end if;
  -- Todo lo que se copia queda bloqueado antes de copiarlo: nada cambia entre la copia y el borrado.
  select * into strict v_ce from crm.cierres_externos where id = v_cierre for update;
  perform 1 from crm.inversiones where id = v_inv for update;
  perform 1 from crm.depositos_reclamados where cierre_id = v_cierre order by id for update;
  perform 1 from crm.inversion_eventos where inversion_id = v_inv order by id for update;
  perform 1 from crm.inversion_titulares where inversion_id = v_inv order by id for update;
  perform 1 from crm.inversion_solicitudes where inversion_id = v_inv order by id for update;
  v_no := private.inversion_motivo_no_eliminable('cierre_externo', v_cierre, v_inv);
  if v_no is not null then raise exception '%', v_no using errcode = 'P0409'; end if;
  if v_inv is not null and exists (select 1 from crm.inversiones i where i.id = v_inv and i.cierre_externo_id is distinct from v_cierre) then
    raise exception 'La inversión no corresponde a este cierre; requiere revisión' using errcode = 'P0409';
  end if;
  -- Una venta anulada no se «reemplaza»: se elimina con «Eliminar inversión». El núcleo ya lo rechazó antes de llegar aquí.
  if v_ce.anulado_en is not null or (v_es_conversion and coalesce((p_ctx ->> 'conversion_anulada')::boolean, false)) then
    raise exception 'Una venta anulada no se reemplaza' using errcode = 'P0409';
  end if;
  perform private.conversion_coordinar_retiro_fuente('cierre_externo', v_cierre);

  -- (auditor-rls r2 de «Eliminar inversión», P3) Un CHECK fallido traería la copia en el DETAIL: se relanza sin detalle.
  begin
  insert into crm.inversiones_eliminadas (fuente_tipo, fuente_id, inversion_id, empresa, inversionista_id, lead_id,
    es_conversion, conversion_anulada, anulacion, motivo, eliminado_por, rol_actor, snapshot, archivos, reemplazada_por)
  values ('cierre_externo', v_cierre, v_inv, v_ce.cooperativa,
    coalesce((p_ctx ->> 'inversionista_id')::uuid, v_ce.inversionista_id),
    case when v_es_conversion then v_ce.lead_id end,
    v_es_conversion, false, null, p_motivo, p_actor, p_rol,
    jsonb_build_object(
      'version', 1,
      'actor', jsonb_build_object('id', p_actor, 'rol', p_rol),
      'cierre', to_jsonb(v_ce),
      'inversion', (select to_jsonb(i) from crm.inversiones i where i.id = v_inv),
      'depositos', coalesce((select jsonb_agg(to_jsonb(d) order by d.id) from crm.depositos_reclamados d
                             where d.cierre_id = v_cierre), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(to_jsonb(e) order by e.id) from crm.inversion_eventos e
                           where e.inversion_id = v_inv), '[]'::jsonb),
      'titulares', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from crm.inversion_titulares t
                             where t.inversion_id = v_inv), '[]'::jsonb),
      'solicitudes', coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from crm.inversion_solicitudes s
                               where s.inversion_id = v_inv), '[]'::jsonb),
      'acreditaciones', coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from crm.conversion_acreditaciones a
                                  where a.fuente_tipo = 'cierre_externo' and a.fuente_id = v_cierre), '[]'::jsonb),
      -- p_detalle: la acreditación tal como estaba ANTES, los cambios pedidos y la huella del pedido (idempotencia).
      'reemplazo', coalesce(p_detalle, '{}'::jsonb) || jsonb_build_object('modo', 'nueva', 'cierre_id', p_nuevo)),
    case when v_ce.comprobante_objeto_id is null then '[]'::jsonb
      else jsonb_build_array(jsonb_build_object('tipo', 'comprobante', 'objeto_id', v_ce.comprobante_objeto_id)) end,
    p_nuevo)
  returning id, valvula into v_id, v_valvula;
  exception when check_violation or not_null_violation or foreign_key_violation or unique_violation then
    raise exception 'La copia de la inversión reemplazada no es válida; requiere revisión' using errcode = '55000';
  end;

  perform set_config('crm.inversion_eliminacion', v_valvula::text, true);
  -- Hijos antes que padres. La solicitud de alta se CONSERVA cancelada (como en «Eliminar inversión»: cierra replays).
  delete from crm.depositos_reclamados where cierre_id = v_cierre;
  delete from crm.inversion_eventos where inversion_id = v_inv;
  update crm.inversion_solicitudes set estado = 'cancelada', inversion_id = null, actualizado_en = statement_timestamp()
    where inversion_id = v_inv;
  delete from crm.inversion_titulares where inversion_id = v_inv;
  delete from crm.inversiones where id = v_inv;
  delete from crm.cierres_externos where id = v_cierre;
  perform set_config('crm.inversion_eliminacion', coalesce(v_previa, ''), true);
  if exists (select 1 from crm.cierres_externos ce where ce.id = v_cierre) then
    raise exception 'El reemplazo no pudo retirar la inversión original; no se hizo ningún cambio' using errcode = '55000';
  end if;
  return v_id;
exception when others then
  perform set_config('crm.inversion_eliminacion', coalesce(v_previa, ''), true);
  raise;
end $function$;

-- ── 2 · Núcleo: el reemplazo, una operación atómica ───────────────────────────────────────────────────────────────────
create function private.reemplazar_inversion_cooperativa(p_actor uuid, p_roles jsonb, p_fuente uuid, p_motivo text, p_cierre jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_portal text := p_roles ->> 'portal';
  v_gerencia boolean := coalesce((p_roles ->> 'gerencia')::boolean, false);
  v_rol text := case when v_gerencia then 'gerencia' else v_portal end;
  v_ctx jsonb;
  v_no text;
  v_previo crm.inversiones_eliminadas%rowtype;
  v_ce crm.cierres_externos%rowtype;
  v_e crm.empresas%rowtype;
  v_obj storage.objects%rowtype;
  v_es_conversion boolean;
  v_lead uuid;
  v_acr crm.conversion_acreditaciones%rowtype;
  v_acr2 crm.conversion_acreditaciones%rowtype;
  v_mueve_venta boolean := false;
  v_venta record;
  v_coop text;
  v_fecha date;
  v_ruta text;
  v_obj_id uuid;
  v_vence date;
  v_persona uuid;
  v_primera boolean;
  v_titulares jsonb;
  v_t record;
  v_periodos date[];
  v_p date;
  v_nuevo uuid := gen_random_uuid();
  v_inv uuid;
  v_aud uuid;
  v_hoy date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
  -- Lo que se pidió (sin el motivo): un reintento con OTROS datos no recibe el resultado del primero como si fuera suyo.
  v_huella_pedido text := md5(coalesce(p_cierre::text, ''));
begin
  if p_fuente is null then
    raise exception 'Indica la inversión que se reemplaza' using errcode = '22023';
  end if;
  if v_rol is null then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  if p_cierre is not null and jsonb_typeof(p_cierre) <> 'object' then
    raise exception 'Los datos del reemplazo no son válidos' using errcode = '22023';
  end if;
  p_cierre := coalesce(p_cierre, '{}'::jsonb);
  if exists (select 1 from jsonb_object_keys(p_cierre) k where k not in ('cooperativa', 'fecha_comercial', 'comprobante_ruta')) then
    raise exception 'En una cooperativa el reemplazo cambia solo la cooperativa, la fecha comercial y el comprobante; para el monto, el plazo o la tasa usa «Corregir»'
      using errcode = '22023';
  end if;

  -- Candado GLOBAL del cierre de mes ANTES de cualquier fila (el orden de crm.cerrar_periodo y de «Eliminar inversión»).
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

  -- a. Bloquear y clasificar el original (mismos candados y orden que «Eliminar inversión»).
  v_ctx := private.eliminar_inversion_contexto(p_fuente);
  if v_ctx is null then
    -- Idempotencia: el original ya se reemplazó (un reintento, o dos clics que se serializaron en el candado de la fila).
    select * into v_previo from crm.inversiones_eliminadas e where e.fuente_tipo = 'cierre_externo' and e.fuente_id = p_fuente;
    if v_previo.id is not null and v_previo.reemplazada_por is not null then
      if v_previo.snapshot #>> '{reemplazo,huella_pedido}' is distinct from v_huella_pedido then
        raise exception 'Esta inversión ya se reemplazó con otros datos; no se hizo otro cambio'
          using errcode = 'P0409', hint = 'REEMPLAZO_YA_HECHO_CON_OTROS_DATOS';
      end if;
      return jsonb_build_object('ok', true, 'idempotente', true, 'fuente_id', p_fuente, 'cierre_id', v_previo.reemplazada_por,
        'auditoria_id', v_previo.id, 'cooperativa', (select ce.cooperativa from crm.cierres_externos ce where ce.id = v_previo.reemplazada_por),
        'fecha_comercial', (select ce.fecha_comercial from crm.cierres_externos ce where ce.id = v_previo.reemplazada_por));
    end if;
    raise exception 'La inversión no existe o ya fue eliminada' using errcode = 'P0002';
  end if;

  -- b. Lo que no se reemplaza.
  if v_ctx ->> 'tipo' is distinct from 'cierre_externo' then
    raise exception 'Esta puerta reemplaza inversiones de cooperativa; una inversión de Avance se reemplaza con la puerta de Avance'
      using errcode = '0A000';
  end if;
  v_no := private.inversion_motivo_no_eliminable('cierre_externo', p_fuente, (v_ctx ->> 'inversion_id')::uuid);
  if v_no is not null then
    raise exception '%', v_no using errcode = 'P0409';
  end if;
  select * into v_ce from crm.cierres_externos ce where ce.id = p_fuente;   -- ya bloqueado por el contexto
  if v_ce.anulado_en is not null or coalesce((v_ctx ->> 'conversion_anulada')::boolean, false) then
    raise exception 'La venta de esta inversión ya fue anulada: el reemplazo es para conservar una venta vigente. Usa «Eliminar inversión»'
      using errcode = 'P0409';
  end if;
  if not v_ce.es_cierre_inicial then
    raise exception 'Solo se reemplaza la inversión inicial de la cooperativa (la venta del lead); un aporte adicional se corrige con «Corregir» o se elimina'
      using errcode = 'P0409';
  end if;
  v_es_conversion := coalesce((v_ctx ->> 'es_conversion')::boolean, false);
  v_lead := (v_ctx ->> 'lead_id')::uuid;
  if v_es_conversion and v_lead is null then
    raise exception 'No se encuentra el lead de esta venta; requiere revisión' using errcode = 'P0409';
  end if;
  if v_lead is not null then
    select * into v_acr from crm.conversion_acreditaciones ca where ca.lead_id = v_lead for update;
    if v_acr.id is not null and (v_acr.fuente_tipo, v_acr.fuente_id) is distinct from ('cierre_externo'::text, p_fuente) then
      raise exception 'La venta de este lead está acreditada a otra inversión; requiere revisión antes de reemplazar'
        using errcode = 'P0409';
    end if;
    v_mueve_venta := v_acr.id is not null;
  end if;

  -- Los datos que quedan: los de la original salvo cooperativa, fecha comercial y comprobante.
  v_coop := coalesce(nullif(btrim(p_cierre ->> 'cooperativa'), ''), v_ce.cooperativa);
  select * into v_e from crm.empresas e where e.clave = v_coop and e.fuente_capital = 'cierres_externos' and e.activa for share;
  if v_e.id is null then
    raise exception 'La cooperativa indicada no existe o no está disponible para nuevas inversiones' using errcode = '22023';
  end if;
  if not (v_ce.moneda = any (coalesce(v_e.monedas, '{}'::text[]))) then
    raise exception 'La cooperativa % no admite inversiones en %', v_e.nombre_visible, v_ce.moneda using errcode = 'P0409';
  end if;
  if p_cierre ? 'fecha_comercial' then
    begin
      v_fecha := (p_cierre ->> 'fecha_comercial')::date;
    exception when others then
      raise exception 'La fecha comercial no es válida' using errcode = '22023';
    end;
  else
    v_fecha := v_ce.fecha_comercial;
  end if;
  if v_fecha is null or not pg_catalog.isfinite(v_fecha) then
    raise exception 'Indica la fecha comercial de la venta' using errcode = '22023';
  end if;
  if v_fecha > v_hoy then
    raise exception 'La fecha comercial no puede ser futura' using errcode = '22023';
  end if;
  v_ruta := nullif(btrim(p_cierre ->> 'comprobante_ruta'), '');
  if v_ruta is not null then
    -- El comprobante nuevo: ya subido al bucket por la pantalla, en la carpeta de ESTA persona (como exige el alta).
    if v_ruta !~ ('^' || v_ce.inversionista_id::text || '/[A-Za-z0-9_/-]+\.(pdf|jpg|jpeg|png)$') then
      raise exception 'El comprobante tiene que estar en la carpeta de esta persona (PDF, JPG o PNG)' using errcode = '22023';
    end if;
    select * into v_obj from storage.objects o where o.bucket_id = 'f4-comprobantes' and o.name = v_ruta for key share;
    if v_obj.id is null or coalesce((v_obj.metadata ->> 'size')::bigint, 0) not between 1 and 10485760
       or coalesce(v_obj.metadata ->> 'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
      raise exception 'Sube el comprobante válido antes de confirmar el reemplazo' using errcode = 'P0409';
    end if;
    v_obj_id := v_obj.id;
  else
    v_obj_id := v_ce.comprobante_objeto_id;
  end if;
  if v_coop = v_ce.cooperativa and v_fecha is not distinct from v_ce.fecha_comercial and v_obj_id is not distinct from v_ce.comprobante_objeto_id then
    raise exception 'Nada que reemplazar: la cooperativa, la fecha comercial y el comprobante son los mismos. Para el monto, el plazo o la tasa usa «Corregir»'
      using errcode = '22023';
  end if;
  -- El vencimiento acompaña a la fecha comercial con la misma convención de plazo (es un CHECK de la tabla).
  if v_ce.plazo_meses is not null then
    v_vence := private.coopac_validar_condiciones_base(v_fecha, v_ce.plazo_meses, v_ce.tasa_anual, v_ce.base_plazo);
  else
    v_vence := v_ce.vence_en;
  end if;

  -- Meses: el de la original, el de su acreditación y el de la fecha que queda. Candados mensuales en orden, con las
  -- llaves de crm.cerrar_periodo (el global ya está tomado y el contexto ya tiene el mes de la original). Los DEMÁS se
  -- piden SIN esperar: si alguno está ocupado, nada se hizo todavía y se pide reintentar.
  v_periodos := array(select distinct x from unnest(array[
      pg_catalog.date_trunc('month', coalesce(v_ce.fecha_comercial, (v_ce.creado_en at time zone 'America/Lima')::date)::timestamp)::date,
      v_acr.periodo_comercial,
      pg_catalog.date_trunc('month', v_fecha::timestamp)::date]) x
    where x is not null order by x);
  foreach v_p in array v_periodos loop
    if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'), (v_p - date '2000-01-01')::integer) then
      raise exception 'Otra operación está usando el mes %; vuelve a intentar en unos segundos', pg_catalog.to_char(v_p, 'MM/YYYY')
        using errcode = 'PT409';
    end if;
  end loop;
  -- Un mes sellado no se reescribe, ni uno que quedó POR DETRÁS del último sello (misma regla que Avance).
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= v_periodos[1])
     or exists (select 1 from crm.capital_mes_sellos s where s.periodo >= v_periodos[1]) then
    raise exception 'El mes de esta venta ya está cerrado: no se reemplaza' using errcode = 'P0409',
      hint = 'Un mes sellado no se reescribe.';
  end if;
  if v_lead is not null then
    select * into v_venta from private.mes_sellado_de_venta(v_lead);
    if v_venta.p_desconocido or v_venta.p_sellado then
      raise exception 'El mes de esta venta ya está cerrado o no se puede determinar: no se reemplaza' using errcode = 'P0409';
    end if;
  end if;
  -- Re-acreditar reinicia el reloj de la venta a AHORA: con el plazo de carga del mes vencido quedaría fuera de plazo.
  if v_mueve_venta and v_acr.estado = 'acreditada'
     and pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(pg_catalog.date_trunc('month', v_fecha::timestamp)::date) then
    raise exception 'Venció el plazo de carga de %: el reemplazo dejaría la venta fuera de plazo. No se hizo ningún cambio',
      pg_catalog.to_char(v_fecha, 'MM/YYYY') using errcode = 'P0409';
  end if;

  -- Lo que la nueva hereda de la inversión: la persona canónica, la marca de primera conversión y los cotitulares.
  v_persona := private.inversionista_canonica(v_ce.inversionista_id);
  select i.es_primera_conversion into v_primera from crm.inversiones i where i.id = (v_ctx ->> 'inversion_id')::uuid;
  v_titulares := coalesce((select jsonb_agg(jsonb_build_object('inversionista_id', t.inversionista_id, 'rol', t.rol) order by t.id)
    from crm.inversion_titulares t where t.inversion_id = (v_ctx ->> 'inversion_id')::uuid and t.rol <> 'principal'), '[]'::jsonb);

  -- c. La copia de la original y su borrado, SIN anular la venta (la válvula de «Eliminar inversión», en esta transacción).
  v_aud := private.registrar_inversion_reemplazada_cooperativa(v_ctx, p_actor, v_rol, p_motivo, v_nuevo,
    jsonb_build_object('acreditacion_antes', case when v_acr.id is not null then to_jsonb(v_acr) end,
      'huella_pedido', v_huella_pedido,
      'cambios', jsonb_build_object('cooperativa', jsonb_build_object('antes', v_ce.cooperativa, 'despues', v_coop),
        'fecha_comercial', jsonb_build_object('antes', v_ce.fecha_comercial, 'despues', v_fecha),
        'comprobante_cambiado', v_obj_id is distinct from v_ce.comprobante_objeto_id)));

  -- d. La inversión que queda: la misma fila salvo cooperativa, fecha comercial, comprobante y vencimiento, con el id ya
  --    decidido (la copia lo recuerda). Su trigger de acreditación sincroniza la venta del lead al insertarla.
  begin
    insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
      numero_transaccion, referencia_externa, vence_en, nota, vendedor_id, creado_por, creado_en, inversionista_id,
      es_cierre_inicial, fecha_comercial, fecha_imputacion, comprobante_objeto_id, plazo_meses, tasa_anual, base_plazo)
    values (v_nuevo, v_ce.lead_id, v_coop, v_ce.monto, v_ce.moneda, v_ce.documento_tipo, v_ce.documento, v_ce.nombre_completo,
      v_ce.numero_transaccion, v_ce.referencia_externa, v_vence, v_ce.nota, v_ce.vendedor_id, p_actor, statement_timestamp(),
      v_ce.inversionista_id, true, v_fecha, v_fecha, v_obj_id, v_ce.plazo_meses, v_ce.tasa_anual, v_ce.base_plazo);
    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
    values (upper(btrim(v_ce.numero_transaccion)), v_nuevo, p_actor);
  exception when unique_violation then
    raise exception 'Ese número de operación del depósito ya está registrado en otra inversión; no se hizo ningún cambio' using errcode = 'P0409';
  when check_violation or not_null_violation or foreign_key_violation then
    -- Sin el DETAIL («Failing row contains…»): traería la fila con documento y nombre.
    raise exception 'La inversión nueva no es válida; requiere revisión. No se hizo ningún cambio' using errcode = '55000';
  end;
  v_inv := private.inversion_vincular_fuente(v_persona, null, v_nuevo, p_actor, coalesce(v_primera, true));
  for v_t in select (x ->> 'inversionista_id')::uuid as inversionista_id, x ->> 'rol' as rol from jsonb_array_elements(v_titulares) x loop
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol, creado_por)
    select v_inv, v_t.inversionista_id, v_t.rol, p_actor
    where not exists (select 1 from crm.inversion_titulares t where t.inversion_id = v_inv and t.inversionista_id = v_t.inversionista_id);
  end loop;
  insert into crm.inversion_eventos (inversion_id, tipo, motivo, creado_por)
  values (v_inv, 'registro', left('Reemplazo de inversión: ' || p_motivo, 300), p_actor);

  -- e. La venta pasa a la nueva con su único escritor. El trigger del alta (private.conversion_sincronizar_lead) ya la movió al
  --    insertar la fila si el lead tiene su asignación convertida desde septiembre; esta llamada es la red para cuando no la
  --    tiene (el motivo que queda en la acreditación es el del primero que la mueve; el del reemplazo está en la copia y en
  --    el evento «registro»).
  if v_mueve_venta then
    perform private.conversion_acreditar_fuente(v_lead, 'cierre_externo', v_nuevo, 'Reemplazo de inversión: ' || left(p_motivo, 270));
    -- f. INVARIANTE: misma venta (acreditación, estado, episodio, analista, persona, origen) y el mes de la fecha que queda.
    select * into v_acr2 from crm.conversion_acreditaciones ca where ca.lead_id = v_lead;
    if v_acr2.id is distinct from v_acr.id or v_acr2.fuente_tipo is distinct from 'cierre_externo'
       or v_acr2.fuente_id is distinct from v_nuevo or v_acr2.estado is distinct from v_acr.estado
       or v_acr2.episodio_id is distinct from v_acr.episodio_id or v_acr2.analista_id is distinct from v_acr.analista_id
       or v_acr2.inversionista_id is distinct from v_acr.inversionista_id or v_acr2.origen is distinct from v_acr.origen
       or v_acr2.periodo_comercial is distinct from pg_catalog.date_trunc('month', v_fecha::timestamp)::date then
      raise exception using errcode = 'P0409',
        message = case when v_acr2.estado = 'fuera_de_plazo' and v_acr.estado is distinct from 'fuera_de_plazo'
          then 'El plazo de carga de ' || pg_catalog.to_char(v_acr2.periodo_comercial, 'MM/YYYY')
               || ' ya cerró: el reemplazo no puede conservar la venta. No se hizo ningún cambio'
          else 'El reemplazo cambiaría la conversión de esta venta. No se hizo ningún cambio' end,
        detail = pg_catalog.jsonb_build_object(
          'antes', pg_catalog.jsonb_build_object('estado', v_acr.estado, 'periodo', v_acr.periodo_comercial),
          'despues', pg_catalog.jsonb_build_object('estado', v_acr2.estado, 'periodo', v_acr2.periodo_comercial))::text;
    end if;
  elsif v_lead is not null and exists (select 1 from crm.conversion_acreditaciones ca where ca.lead_id = v_lead) then
    -- La venta no tenía acreditación: el reemplazo no la crea (la conversión no cambia).
    raise exception 'El reemplazo crearía una acreditación nueva para esta venta; requiere revisión. No se hizo ningún cambio'
      using errcode = 'P0409';
  end if;

  return jsonb_build_object(
    'ok', true,
    'modo', 'nueva',
    'fuente_id', p_fuente,
    'cierre_id', v_nuevo,
    'inversion_id', v_inv,
    'auditoria_id', v_aud,
    'cooperativa', v_coop,
    'fecha_comercial', v_fecha,
    'vence_en', v_vence,
    'comprobante_cambiado', v_obj_id is distinct from v_ce.comprobante_objeto_id,
    'conversion', case when v_mueve_venta then jsonb_build_object(
      'lead_id', v_lead, 'estado', v_acr2.estado,
      'periodo_antes', v_acr.periodo_comercial, 'periodo_despues', v_acr2.periodo_comercial) end);
end
$function$;

-- ── 3 · Puertas ────────────────────────────────────────────────────────────────────────────────────────────────────────
create function crm.reemplazar_inversion_cooperativa_fn(p_fuente_id uuid, p_motivo text, p_cierre jsonb)
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
    return private.reemplazar_inversion_cooperativa(v_uid, v_roles, p_fuente_id, v_motivo, p_cierre);
  exception when deadlock_detected or lock_not_available then
    raise exception 'Hay un cierre de mes u otra operación sobre esta venta en curso; vuelve a intentar en unos segundos. No se hizo ningún cambio'
      using errcode = 'PT409';
  end;
end
$function$;

-- Solo lectura (VOLATILE a propósito: los roles toman FOR SHARE; se llama por POST). Dice, ANTES de confirmar, en qué mes
-- queda la venta con la fecha que se propone y qué se negaría; el reemplazo vuelve a decidirlo todo.
create function crm.reemplazar_inversion_cooperativa_vista_previa_fn(p_fuente_id uuid, p_fecha_comercial date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_ce crm.cierres_externos%rowtype;
  v_inv crm.inversiones%rowtype;
  v_acr crm.conversion_acreditaciones%rowtype;
  v_fecha date;
  v_mes date;
  v_mes_actual date;
  v_no text;
  v_lead uuid;
  v_hoy date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para reemplazar inversiones' using errcode = '42501';
  end if;
  begin
    v_roles := private.eliminar_inversion_roles(v_uid);
  exception when deadlock_detected or lock_not_available then
    raise exception 'Otra operación está usando estos datos; vuelve a intentar en unos segundos' using errcode = 'PT409';
  end;
  if v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  select * into v_ce from crm.cierres_externos ce where ce.id = p_fuente_id;
  if v_ce.id is null then
    raise exception 'La inversión no existe o ya fue eliminada' using errcode = 'P0002';
  end if;
  if p_fecha_comercial is not null and not pg_catalog.isfinite(p_fecha_comercial) then
    raise exception 'La fecha comercial no es válida' using errcode = '22023';
  end if;
  v_fecha := coalesce(p_fecha_comercial, v_ce.fecha_comercial, (v_ce.creado_en at time zone 'America/Lima')::date);
  v_mes := pg_catalog.date_trunc('month', v_fecha::timestamp)::date;
  v_mes_actual := pg_catalog.date_trunc('month', coalesce(v_ce.fecha_comercial, (v_ce.creado_en at time zone 'America/Lima')::date)::timestamp)::date;
  select * into v_inv from crm.inversiones i where i.cierre_externo_id = v_ce.id;
  v_no := private.inversion_motivo_no_eliminable('cierre_externo', v_ce.id, v_inv.id);
  -- La venta: la acreditación de la fuente si la hay; si no, el lead del cierre inicial.
  select * into v_acr from crm.conversion_acreditaciones ca where ca.fuente_tipo = 'cierre_externo' and ca.fuente_id = v_ce.id;
  v_lead := coalesce(v_acr.lead_id, case when v_ce.es_cierre_inicial then v_ce.lead_id end);
  return pg_catalog.jsonb_build_object(
    'fuente_id', v_ce.id,
    'cooperativa', v_ce.cooperativa,
    'es_inicial', v_ce.es_cierre_inicial,
    'anulada', v_ce.anulado_en is not null,
    'venta_de_lead', v_lead is not null,
    'comprobante', v_ce.comprobante_objeto_id is not null,
    'fecha_comercial_actual', v_ce.fecha_comercial,
    'mes_actual', v_mes_actual,
    'fecha_comercial_resultante', v_fecha,
    'mes_resultante', v_mes,
    'cambia_mes', v_mes is distinct from v_mes_actual,
    'fecha_futura', v_fecha > v_hoy,
    -- Lo que el reemplazo se negaría a hacer: la pantalla lo dice antes de llenar nada.
    'mes_sellado', exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= least(v_mes, v_mes_actual))
                   or exists (select 1 from crm.capital_mes_sellos s where s.periodo >= least(v_mes, v_mes_actual)),
    'plazo_vencido', v_acr.id is not null and v_acr.estado = 'acreditada'
                     and pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(v_mes),
    'no_reemplazable', case when v_ce.anulado_en is not null then 'La venta de esta inversión ya fue anulada: se elimina, no se reemplaza'
                            when not v_ce.es_cierre_inicial then 'Solo se reemplaza la inversión inicial de la cooperativa; un aporte adicional se corrige o se elimina'
                            else v_no end);
end
$function$;

-- ── 3b · El bucket de comprobantes admite el comprobante de un reemplazo ──────────────────────────────────────────────
-- La regla nueva, aparte (para que el ancla en el ayudante vivo sea una línea): <persona>/reemplazo-<cierre>/<archivo>.ext,
-- subido por Gerencia o admin del portal, para la inversión inicial VIGENTE de ESA persona. El reemplazo vuelve a comprobar
-- la ruta y el objeto al confirmar. Fail-closed: cualquier duda devuelve false.
create function private.f4_comprobante_reemplazo_autorizado(p_ruta text)
returns boolean
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_persona uuid;
  v_cierre uuid;
  v_roles jsonb;
begin
  if v_uid is null or p_ruta is null
     or p_ruta !~ '^[a-f0-9-]{36}/reemplazo-[a-f0-9-]{36}/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$' then
    return false;
  end if;
  begin
    v_persona := split_part(p_ruta, '/', 1)::uuid;
    v_cierre := substr(split_part(p_ruta, '/', 2), 11)::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  v_roles := private.eliminar_inversion_roles(v_uid);
  if (v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false)) or private.membresia_crm_revocada() then
    return false;
  end if;
  return exists (select 1 from crm.cierres_externos ce
                 where ce.id = v_cierre and ce.anulado_en is null and ce.es_cierre_inicial
                   and private.inversionista_canonica(ce.inversionista_id) = v_persona);
exception when insufficient_privilege or lock_not_available or sqlstate 'P0409' or sqlstate 'P0429' then
  return false;
end;
$function$;

-- Cuerpo vivo + un cambio por ancla (el ancla tiene que aparecer EXACTAMENTE una vez). CREATE OR REPLACE conserva dueño,
-- permisos, comentario y SECURITY; el postflight lo comprueba.
create function pg_temp.parchar(p_funcion regprocedure, p_cambios text[]) returns void language plpgsql as $$
declare
  v_def text := pg_catalog.pg_get_functiondef(p_funcion);
  i integer;
begin
  for i in 1 .. array_length(p_cambios, 1) loop
    if (length(v_def) - length(replace(v_def, p_cambios[i][1], ''))) / length(p_cambios[i][1]) <> 1 then
      raise exception 'PARCHE %: el ancla % no aparece exactamente una vez', p_funcion, i;
    end if;
    v_def := replace(v_def, p_cambios[i][1], p_cambios[i][2]);
  end loop;
  execute v_def;
end $$;

select pg_temp.parchar('private.f4_comprobante_autorizado(text)'::regprocedure, array[
  array['begin
  if p_ruta is null or p_ruta !~ ''^[a-f0-9-]{36}/[a-f0-9-]{36}/',
        'begin
  -- 18/10/2026 (Reemplazar inversión, cooperativas): <persona>/reemplazo-<cierre>/<archivo>, su propia regla.
  if p_ruta ~ ''^[a-f0-9-]{36}/reemplazo-'' then return private.f4_comprobante_reemplazo_autorizado(p_ruta); end if;
  if p_ruta is null or p_ruta !~ ''^[a-f0-9-]{36}/[a-f0-9-]{36}/']]);

-- La visibilidad: el cuerpo de producción (huella en el preflight) más la rama del comprobante que YA respalda una inversión
-- de cooperativa, con la misma visibilidad que la ficha del inversionista (gerencia, o el responsable de la relación visible).
create or replace function private.f4_comprobante_visible(p_ruta text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia') and (exists (
    select 1 from crm.inversion_solicitudes s join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    where s.datos#>>'{evidencia,ruta}'=p_ruta and (
      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (s.puerta='cliente_existente' and s.analista_cierre_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    )
  ) or exists (
    -- 18/10/2026 (Reemplazar inversión, cooperativas): la ruta de un reemplazo que ya respalda una inversión.
    select 1 from crm.cierres_externos ce
    join storage.objects o on o.id = ce.comprobante_objeto_id
    join crm.inversionistas i on i.id = private.inversionista_canonica(ce.inversionista_id)
    where p_ruta ~ '^[a-f0-9-]{36}/reemplazo-' and o.bucket_id = 'f4-comprobantes' and o.name = p_ruta and (
      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
    )
  )),false);
$function$;

-- ── 4 · Permisos ───────────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function private.registrar_inversion_reemplazada_cooperativa(jsonb, uuid, text, text, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.reemplazar_inversion_cooperativa(uuid, jsonb, uuid, text, jsonb)
  from public, anon, authenticated, service_role;
-- La regla del bucket la llama el ayudante vivo (DEFINER, EXECUTE a authenticated): la nueva, igual que él.
revoke all on function private.f4_comprobante_reemplazo_autorizado(text) from public, anon, service_role;
grant execute on function private.f4_comprobante_reemplazo_autorizado(text) to authenticated;
revoke all on function crm.reemplazar_inversion_cooperativa_fn(uuid, text, jsonb) from public, anon, service_role;
grant execute on function crm.reemplazar_inversion_cooperativa_fn(uuid, text, jsonb) to authenticated;
revoke all on function crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid, date) from public, anon, service_role;
grant execute on function crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid, date) to authenticated;

-- ── 5 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function private.registrar_inversion_reemplazada_cooperativa(jsonb, uuid, text, text, uuid, jsonb) is
  'Reemplazar inversión (cooperativas, 20261018053228): copia de la original en crm.inversiones_eliminadas (conversion_anulada '
  'false, reemplazada_por = la nueva) y borrado de la original con la válvula de «Eliminar inversión», SIN anular la venta. '
  'Espejo de private.eliminar_inversion_cooperativa. Solo la llama private.reemplazar_inversion_cooperativa.';
comment on function private.reemplazar_inversion_cooperativa(uuid, jsonb, uuid, text, jsonb) is
  'Reemplazar inversión (cooperativas, 20261018053228): la operación atómica. Cambia solo cooperativa, fecha comercial y '
  'comprobante; copia el resto de la original; la venta del lead pasa a la nueva con private.conversion_acreditar_fuente. '
  'Rechaza venta anulada, aporte adicional, movimientos, mes sellado y plazo vencido. Idempotente por la original.';
comment on function private.f4_comprobante_reemplazo_autorizado(text) is
  'Bucket f4-comprobantes (20261018053228): autoriza subir <persona>/reemplazo-<cierre>/<archivo> a Gerencia o admin del portal '
  'para la inversión inicial vigente de esa persona. La llama private.f4_comprobante_autorizado; el reemplazo lo revalida.';
comment on function private.f4_comprobante_autorizado(text) is
  'Bucket f4-comprobantes: la ruta de una solicitud preparada (alta) o, desde 20261018053228, la de un reemplazo de '
  'cooperativa (private.f4_comprobante_reemplazo_autorizado).';
comment on function private.f4_comprobante_visible(text) is
  'Bucket f4-comprobantes: visible la ruta de una solicitud del inversionista visible y, desde 20261018053228, la del '
  'comprobante que ya respalda una inversión de cooperativa, con la misma visibilidad que la ficha.';
comment on function crm.reemplazar_inversion_cooperativa_fn(uuid, text, jsonb) is
  'Puerta de «Reemplazar inversión» para cooperativas (Gerencia o admin del portal): p_cierre = {cooperativa?, '
  'fecha_comercial?, comprobante_ruta?}. Valida sesión, roles, membresía y motivo (5–300) y delega en el núcleo.';
comment on function crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid, date) is
  'Vista previa de «Reemplazar inversión» para cooperativas (solo lectura): mes actual y resultante de la venta con la fecha '
  'propuesta, y qué se negaría (anulada, aporte adicional, movimientos, mes sellado, plazo vencido). El reemplazo decide todo.';

-- ── 6 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
begin
  -- Los dos ayudantes del bucket quedaron EXACTAMENTE como se ensayó, con sus metadatos de siempre; la regla nueva, como ellos.
  if (select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
      from pg_catalog.pg_proc p
      where p.oid in ('private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure))
     is distinct from 'private.f4_comprobante_autorizado(text)=cdecad21e77c38d023ba156efd8faa74,'
                      'private.f4_comprobante_visible(text)=d5e74abf371a35c677d42da9abb2ff82' then
    raise exception 'POSTFLIGHT reemplazar_cooperativa: un ayudante del bucket no quedó como se ensayó';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure,
                             'private.f4_comprobante_reemplazo_autorizado(text)'::regprocedure)
               and (p.proowner <> 'postgres'::regrole or not p.prosecdef or not ('search_path=""' = any (p.proconfig))
                    or not has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                    or has_function_privilege('service_role', p.oid, 'execute')
                    or p.proacl is null or exists (select 1 from unnest(p.proacl) x where x::text like '=X/%'))) then
    raise exception 'POSTFLIGHT reemplazar_cooperativa: los ayudantes del bucket tienen que ser DEFINER de postgres, search_path vacío y EXECUTE solo authenticated';
  end if;
  -- Dueño postgres; el núcleo y la copia INVOKER y sin EXECUTE para la API; las puertas DEFINER con EXECUTE solo authenticated.
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)'::regprocedure,
                             'private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)'::regprocedure)
               and (p.proowner <> 'postgres'::regrole or p.prosecdef or p.proconfig is distinct from array['search_path=""']
                    or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                    or has_function_privilege('service_role', p.oid, 'execute')
                    -- Sin EXECUTE para PUBLIC (un ACL nulo lo concede a todos).
                    or p.proacl is null or exists (select 1 from unnest(p.proacl) x where x::text like '=X/%'))) then
    raise exception 'POSTFLIGHT reemplazar_cooperativa: el núcleo tiene que ser de postgres, INVOKER, search_path vacío y sin EXECUTE para la API';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)'::regprocedure,
                             'crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)'::regprocedure)
               and (p.proowner <> 'postgres'::regrole or not p.prosecdef
                    or not ('search_path=""' = any (p.proconfig)) or not ('lock_timeout=5s' = any (p.proconfig))
                    or not has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                    or has_function_privilege('service_role', p.oid, 'execute')
                    or p.proacl is null or exists (select 1 from unnest(p.proacl) x where x::text like '=X/%'))) then
    raise exception 'POSTFLIGHT reemplazar_cooperativa: las puertas tienen que ser DEFINER de postgres, search_path vacío, lock_timeout 5s y EXECUTE solo authenticated';
  end if;
  -- F7, vigencia del analista y censo analítico: ninguna función nueva entra.
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid in ('private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)'::regprocedure,
                             'private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)'::regprocedure,
                             'crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)'::regprocedure,
                             'crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)'::regprocedure,
                             'private.f4_comprobante_reemplazo_autorizado(text)'::regprocedure,
                             'private.f4_comprobante_autorizado(text)'::regprocedure,
                             'private.f4_comprobante_visible(text)'::regprocedure)
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT reemplazar_cooperativa: una función nueva nombra una pieza cerrada de F7';
  end if;
  if exists (select 1 from private.puertas_analista_sin_vigencia() c
             where c.objeto in ('private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)',
                                'private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)',
                                'crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)',
                                'crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)',
                                'private.f4_comprobante_reemplazo_autorizado(text)', 'private.f4_comprobante_autorizado(text)',
                                'private.f4_comprobante_visible(text)')) then
    raise exception 'POSTFLIGHT reemplazar_cooperativa: una función nueva entró al censo de vigencia del analista';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in ('private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)',
                                'private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)',
                                'crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)',
                                'crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)',
                                'private.f4_comprobante_reemplazo_autorizado(text)', 'private.f4_comprobante_autorizado(text)',
                                'private.f4_comprobante_visible(text)')) then
    raise exception 'POSTFLIGHT reemplazar_cooperativa: una función nueva entró al censo analítico';
  end if;
end
$postflight$;

commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
