-- ORÁCULO de «El teléfono alternativo de un CLIENTE no puede ser el número de un lead que ya existe» (bloque 2.13) — se ejecuta en
-- el LABORATORIO (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisión D-49 de Miguel, 09/10/2026; plan aprobado D-50; plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.13), sobre la del
-- bloque 2.8 (D-28, D-30, D-36; ronda 4): al PONER o CAMBIAR el teléfono ALTERNATIVO de un CLIENTE (la ficha queda `convertido`), con
-- sesión, si el número nuevo —en su FORMA CANÓNICA, la de `private.canonizar_contacto` (la que escribe el alta)— es el teléfono o el
-- alternativo de OTRO lead VIVO (activo, ni convertido ni descartado: el dominio del «tomado» de la disponibilidad), el CRM lo
-- RECHAZA con el MISMO `P0481` «Contacto no disponible» y el MISMO veredicto que la disponibilidad da hoy al teléfono principal de ese
-- lead (la pieza llama al verificador sellado): «tomado» con su asesor, «en_bolsa» si no tiene dueño o, si está vetado, el veto
-- «no_contactar» sin asesor; con las mismas claves, para que la pantalla lo muestre igual.
--   · Precedencia: lo que el disparador ya juzga hoy (rol, vetos propios, enfriamiento propio, verificador) y la regla del 2.8 (el
--     número de OTRO CLIENTE ⇒ «ya es cliente de X») van antes y mandan. Si solo cambia el alternativo y hay veredicto, primero el
--     rol (42501 a quien no puede registrar leads: nunca ve el veredicto), como en el 2.8.
--   · Entre varios leads vivos: el que lo tiene como TELÉFONO antes que el que lo tiene como alternativo; después, el id.
--   · Nunca contra la propia ficha; sin sesión (importador, escrituras internas), como hoy; bajo el candado por número de la ronda 4
--     del 2.8 (el disparador lo toma antes de juzgar: caso K1).
--   · NO CAMBIA: los leads que no son clientes, el alternativo libre, quitar el alternativo, el número de un lead RETIRADO (como el
--     teléfono principal hoy: la disponibilidad lo da por libre, caso N3m) o DESCARTADO (no es «tomado»: medido en N4m), lo que la
--     edición no toca (D-25: el cliente que YA comparte su alternativo con un lead vivo sigue editándose), el número de otro cliente
--     (lo juzga el 2.8, igual que hoy), el INSERT.
-- Hoy (sin la migración), el disparador `private.trg_leads_disponibilidad_atomica` solo compara el alternativo nuevo con los
-- teléfonos de los CLIENTES (la pieza del 2.8): el número de un lead vivo que no es cliente pasa ⇒ dos fichas con el mismo número.
--
-- RONDA 2 (09–10/10/2026; auditor de permisos r1, PASS con cinco P3; decisiones D-64, D-65 y D-67):
--   · P3-1: «es cliente» = la ficha ya era `convertido` o lo queda bajo la válvula privilegiada (la conversión real). T15/T15b, N7b/N7c
--     corren bajo `crm.op_privilegiada`; N14a/N14b miden la conversión ILEGAL sin válvula con el número de un lead vivo: la respuesta de
--     hoy (la guarda de la conversión, P0001) SIN veredicto en el detalle (no sirve para sondear de quién es un número).
--   · P3-3: el conjunto real de veredictos: T17 (lead vivo cuyo teléfono es el de un perfil ACTIVO del Portal ⇒ `ya_es_cliente` con el
--     asesor del perfil); la pieza solo mira leads vivos cuyo principal ve el verificador (N12 y N12b: un heredado no canónico no se
--     nombra ni hace nombrar a OTRO lead por su número normalizado).
--   · D-64 (solo leads vivos: N3/N4 se quedan), D-65 (H1/N13 se cuentan antes de publicar), D-67 (lo que revela el rechazo: aceptado).
--   · El juez de un rechazo exige que un error sin veredicto esperado NO traiga detalle.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (sin su `begin;`/`commit;`) dentro de
-- una única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y entonces TIENE que salir ROJO porque la
-- edición del alternativo de un cliente se ACEPTA (o, con un número no canónico, la rechaza otro error), nunca por un error de montaje.
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT, fijada en las DOS formas
-- (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de rol con `set role`: todo corre como `postgres`, así que la RLS y
-- los permisos por columna NO se ensayan aquí (sección C y ronda del banco). Actores reales del banco (`PASO08 …`), OBLIGATORIOS con
-- su rol exacto: sin ellos, `ENSAYO ABORTADO`.
--
-- Cómo nacen los clientes: los que se EDITAN, por la conversión REAL del formulario compartido (cooperativa, sin cuenta del Portal:
-- quedan con su cierre externo, el ancla sin la cual `private.leads_before_update` no deja editar un convertido —medido: la primera
-- corrida del ROJO con clientes sembrados recibió «Un lead convertido debe estar enlazado a un perfil de cliente» en cada edición—);
-- los OTROS clientes que solo se leen (T11, N8), sin persona: alta real y conversión SEMBRADA con los disparadores apagados (estado
-- heredado declarado, como en los oráculos del 2.7 y del 2.8). Los leads vivos, retirados y descartados nacen por la puerta real (el
-- retiro y el descarte, con la sesión de quien los hace). El duplicado heredado (N5, T12) nace también por la puerta real: hoy el alta
-- no compara el alternativo tecleado con los leads vivos.

set local statement_timeout = '600s';

-- Identidad de la sesión, en las DOS formas de los claims.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Acumulador del informe: un caso que pasa suma una línea «ok»; uno que falla, un fallo con su texto. Cuenta las comprobaciones.
create function pg_temp.reg(p_caso text, p_txt text) returns void language plpgsql as $f$
begin
  perform set_config('ensayo.casos', (coalesce(nullif(current_setting('ensayo.casos', true), ''), '0')::integer + 1)::text, true);
  if p_txt = '' then
    perform set_config('ensayo.oks', coalesce(current_setting('ensayo.oks', true), '') || 'ok ' || p_caso || E'\n', true);
  else
    perform set_config('ensayo.fallos',
      (coalesce(nullif(current_setting('ensayo.fallos', true), ''), '0')::integer + 1)::text, true);
    perform set_config('ensayo.informe', coalesce(current_setting('ensayo.informe', true), '') || p_txt, true);
  end if;
end;
$f$;

create function pg_temp.medida(p_txt text) returns void language sql as $$
  select set_config('ensayo.medidas', coalesce(current_setting('ensayo.medidas', true), '') || 'medida ' || p_txt || E'\n', true);
$$;

-- Contactos del ensayo: un bloque propio (+51 924 13xxxx / DNI 7533xxxx) que el montaje exige LIBRE (2.4: 92400/7524; 2.7:
-- 92407/7527; 2.8: 92408/7528; 2.9: 92409/7529).
create function pg_temp.tel(n integer) returns text language sql immutable as $$ select '92413' || lpad(n::text, 4, '0') $$;
create function pg_temp.teln(n integer) returns text language sql immutable as $$ select '+51' || pg_temp.tel(n) $$;
create function pg_temp.dni(n integer) returns text language sql immutable as $$ select '7533' || lpad(n::text, 4, '0') $$;

create temp table ens_actores (nombre text primary key, id uuid not null);

create function pg_temp.actor(p_nombre text) returns uuid language sql as $$
  select a.id from ens_actores a where a.nombre = p_nombre
$$;

-- Foto COMPLETA de una ficha (para «sigue intacta»).
create function pg_temp.ficha(p_id uuid) returns jsonb language sql as $$
  select to_jsonb(l) from crm.leads l where l.id = p_id
$$;

-- Huella de ESCRITURA (la del oráculo del 2.8): el contenido entero de crm.leads, crm.actividades y crm.lead_asignaciones (md5 de las
-- filas en orden de id) y el número de filas de tareas, personas, documentos y ciclos SLA.
create function pg_temp.huella_escritura() returns text language sql as $$
  select concat_ws(',',
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '')) from crm.leads l),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from crm.actividades a),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) from crm.lead_asignaciones e),
    (select count(*) from crm.tareas), (select count(*) from crm.inversionistas), (select count(*) from crm.inversionista_identificadores),
    (select count(*) from crm.lead_sla_ciclos))
$$;

-- Cuántas fichas llevan ese número (canónico) como teléfono o como alternativo: el «dos fichas con el mismo número» que mide el ROJO.
create function pg_temp.fichas_con(p_numero text) returns bigint language sql as $$
  select count(*) from crm.leads l where l.telefono = p_numero or l.telefono_alternativo = p_numero
$$;

-- 'SQLSTATE|mensaje|detalle' → sus partes (el detalle puede faltar).
create function pg_temp.error_de(p_res text, out estado text, out mensaje text, out detalle text) language sql immutable as $$
  select split_part(p_res, '|', 1), split_part(p_res, '|', 2),
         nullif(substr(p_res, length(split_part(p_res, '|', 1)) + length(split_part(p_res, '|', 2)) + 3), '')
$$;
create function pg_temp.a_jsonb(p text) returns jsonb language plpgsql immutable as $f$
begin
  return p::jsonb;
exception when others then
  return null;
end;
$f$;

-- ── Las puertas, como el actor ──────────────────────────────────────────────────────────────────────────────────────
-- Cada una devuelve 'ok|<respuesta>' o 'SQLSTATE|mensaje|detalle'. El bloque con EXCEPTION es una subtransacción: un rechazo
-- deshace TODO lo que la llamada había hecho.

-- Alta por la puerta real (con el alternativo).
create function pg_temp.alta(p_actor uuid, p_id uuid, p_nombre text, p_tel text, p_dni text, p_alt text default null)
returns text language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.crear_lead_si_disponible(
    p_nombre_completo => p_nombre, p_telefono => p_tel, p_origen => 'formulario', p_monto_estimado => 5000,
    p_moneda => 'PEN', p_id => p_id, p_dni => p_dni, p_telefono_alternativo => p_alt);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- La EDICIÓN desde la ficha: `crm.editar_lead_fn` (la única RPC de la app que manda `telefono_alternativo` de un lead existente).
create function pg_temp.editar(p_actor uuid, p_lead uuid, p_cambios jsonb) returns text language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.editar_lead_fn(p_lead, p_cambios);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- UPDATE directo (el PATCH de PostgREST: `authenticated` tiene UPDATE sobre crm.leads), con o sin sesión: un SET dinámico con SOLO las
-- columnas de p_set y, si se piden, las válvulas de transacción encendidas alrededor (p. ej. `crm.op_privilegiada`).
-- 'ok|<filas>' o 'SQLSTATE|mensaje|detalle'.
create function pg_temp.actualizar_v(p_actor uuid, p_lead uuid, p_set jsonb, p_valvulas text[]) returns text
language plpgsql as $f$
declare v_det text; v_n integer; v_sets text; v_v text;
begin
  select string_agg(format('%I = %L', k, p_set ->> k), ', ' order by k) into v_sets from jsonb_object_keys(p_set) k;
  perform pg_temp.sesion(p_actor);
  foreach v_v in array coalesce(p_valvulas, '{}'::text[]) loop
    perform set_config(v_v, 'on', true);
  end loop;
  execute format('update crm.leads set %s where id = $1', v_sets) using p_lead;
  get diagnostics v_n = row_count;
  foreach v_v in array coalesce(p_valvulas, '{}'::text[]) loop
    perform set_config(v_v, 'off', true);
  end loop;
  perform pg_temp.sesion(null);
  return 'ok|' || v_n::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  foreach v_v in array coalesce(p_valvulas, '{}'::text[]) loop
    perform set_config(v_v, 'off', true);
  end loop;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- INSERT en crm.leads CON SESIÓN que no es el alta (como en el 2.8): el mismo INSERT que hace el alta, sin su núcleo.
create function pg_temp.insertar(p_actor uuid, p_id uuid, p_nombre text, p_tel text, p_alt text)
returns text language plpgsql as $f$
declare v_det text;
begin
  perform pg_temp.sesion(p_actor);
  insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, origen, etapa, monto_estimado, moneda, vendedor_id,
                         asignado_supervisor_id, activo, creado_por, alta_manual)
  values (p_id, p_nombre, p_tel, p_alt, 'formulario', 'nuevo', 5000, 'PEN', p_actor, null, true, p_actor, true);
  perform pg_temp.sesion(null);
  return 'ok|' || p_id::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- Retirar como lo hace Gerencia/supervisión hoy: UPDATE activo=false por API, con su sesión. '1' si retiró una fila.
create function pg_temp.retirar(p_actor uuid, p_id uuid) returns text language plpgsql as $f$
declare v_n integer;
begin
  perform pg_temp.sesion(p_actor);
  update crm.leads set activo = false where id = p_id and activo;
  get diagnostics v_n = row_count;
  perform pg_temp.sesion(null);
  return v_n::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Descartar como la ficha hoy (`actualizarLead` con etapa y motivo), con la sesión de quien descarta. '1' si descartó.
create function pg_temp.descartar(p_actor uuid, p_id uuid, p_motivo text) returns text language plpgsql as $f$
declare v_n integer;
begin
  perform pg_temp.sesion(p_actor);
  update crm.leads set etapa = 'descartado', motivo_descarte = p_motivo where id = p_id;
  get diagnostics v_n = row_count;
  perform pg_temp.sesion(null);
  return v_n::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Una conversación REAL en un lead (para que el veredicto «tomado» lleve `ultima_conversacion_en`), con la sesión del dueño.
create function pg_temp.conversacion(p_actor uuid, p_id uuid) returns void language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  insert into crm.actividades (lead_id, tipo, detalle, creado_por) values (p_id, 'llamada_realizada', 'ENSAYO 2.13: conversación real', p_actor);
  perform pg_temp.sesion(null);
exception when others then
  perform pg_temp.sesion(null);
  raise exception 'ENSAYO ABORTADO: no se pudo registrar la conversación del lead % (% %)', p_id, sqlstate, sqlerrm;
end;
$f$;

-- ── Montaje de clientes y leads ─────────────────────────────────────────────────────────────────────────────────────

-- Un lead NUEVO por la puerta real, a nombre del actor (aborta si no nace), con su alternativo y, si se pide, un id fijo.
create function pg_temp.lead_nuevo(p_actor uuid, p_n integer, p_nombre text, p_alt text default null, p_id uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid := coalesce(p_id, gen_random_uuid()); v_res text;
begin
  v_res := pg_temp.alta(p_actor, v_id, p_nombre, pg_temp.tel(p_n), null, p_alt);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado'
     or (select l.telefono_alternativo from crm.leads l where l.id = v_id) is distinct from p_alt then
    raise exception 'ENSAYO ABORTADO: no se pudo crear por la puerta real el lead % (%)', p_n, v_res;
  end if;
  return v_id;
end;
$f$;

-- CONVERSIÓN SEMBRADA (sin persona, estado heredado) de un lead nacido por la puerta real, como en los oráculos del 2.4, 2.7 y 2.8.
create function pg_temp.convertir_sembrado(p_lead uuid, p_retirar boolean) returns void language plpgsql as $f$
declare v_ahora timestamptz := clock_timestamp(); v_cierra uuid;
begin
  v_cierra := (select coalesce(l.vendedor_id, l.asignado_supervisor_id, pg_temp.actor('GERENCIA')) from crm.leads l where l.id = p_lead);
  set local session_replication_role = replica;
  update crm.leads set etapa = 'convertido', convertido_en = v_ahora, activo = (activo and not p_retirar) where id = p_lead;
  update crm.lead_asignaciones set finalizado_en = v_ahora, finalizado_por = v_cierra, motivo_cierre = 'convertido',
         resultado = 'convertido', resultado_en = v_ahora where lead_id = p_lead and finalizado_en is null;
  update crm.lead_sla_etapas set finalizado_en = v_ahora, motivo_cierre = 'cierre_terminal' where lead_id = p_lead and finalizado_en is null;
  set local session_replication_role = origin;
  if (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = p_lead) is distinct from 'convertido|' || (not p_retirar)::text then
    raise exception 'ENSAYO ABORTADO: la conversión sembrada del lead % no quedó como se pidió', p_lead;
  end if;
end;
$f$;

-- OTRO CLIENTE SIN PERSONA (solo se LEE: es la otra parte de un caso, nunca la ficha que se edita): alta real a nombre de p_actor
-- (con el alternativo p_alt) y conversión sembrada. Un convertido así no se puede EDITAR (`private.leads_before_update` exige perfil
-- del Portal o cierre externo: medido en la primera corrida del ROJO); para el 2.8 basta como cliente («ya es cliente», sin persona).
create function pg_temp.cliente_sembrado(p_n integer, p_nombre text, p_actor uuid, p_alt text default null)
returns uuid language plpgsql as $f$
declare v_id uuid := pg_temp.lead_nuevo(p_actor, p_n, p_nombre, p_alt);
begin
  if (select l.inversionista_id from crm.leads l where l.id = v_id) is not null then
    raise exception 'ENSAYO ABORTADO: el lead del cliente % quedó enlazado a una persona', p_n;
  end if;
  perform pg_temp.convertir_sembrado(v_id, false);
  return v_id;
end;
$f$;

-- CLIENTE CON PERSONA por la conversión REAL (formulario compartido, cooperativa: sin cuenta del Portal; queda con su cierre externo,
-- el ancla que `private.leads_before_update` exige para EDITAR un convertido), como en el oráculo del 2.8. Con p_alt, el alta lleva ese
-- teléfono alternativo (hoy el alta no lo compara con los leads vivos: así nace también el duplicado heredado de N5 y T12).
create function pg_temp.convertir_real(p_n integer, p_nombre text, p_actor uuid, p_alt text default null) returns uuid language plpgsql as $f$
declare
  v_lead uuid := gen_random_uuid(); v_res text; v_r jsonb; v_per uuid; v_sol uuid := gen_random_uuid(); v_ruta text;
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
begin
  v_res := pg_temp.alta(p_actor, v_lead, p_nombre, pg_temp.tel(p_n), pg_temp.dni(p_n), p_alt);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear por la puerta real el lead del cliente % (%)', p_n, v_res;
  end if;
  begin
    perform pg_temp.sesion(p_actor);
    v_per := (crm.preparar_persona_lead_inversion_fn(v_lead, 'DNI', pg_temp.dni(p_n), p_nombre) ->> 'inversionista_id')::uuid;
    v_ruta := v_per || '/' || v_sol || '/comprobante.pdf';
    v_r := crm.preparar_inversion_fn(v_sol, jsonb_build_object('inversionista_id', v_per, 'lead_id', v_lead, 'empresa', 'prodelco',
             -- 22/10/2026 (C2-a ronda 2): 20261016195003 — una inversión nueva de cooperativa vence a plazo × 30 días (12 meses = 360 días), no a 12 meses de calendario.
             'monto', 5000, 'moneda', 'PEN', 'fecha_comercial', v_hoy, 'vence_en', v_hoy + 360,
             'plazo_meses', 12, 'tasa_anual', 15, 'numero_transaccion', 'ENS213-' || left(v_sol::text, 8),
             'referencia', 'ENSAYO 2.13 SINTETICA', 'evidencia', jsonb_build_object('ruta', v_ruta)));
    perform pg_temp.sesion(null);
    insert into storage.objects (bucket_id, name, metadata)
    values ('f4-comprobantes', v_ruta, '{"size":128,"mimetype":"application/pdf"}'::jsonb);
    perform pg_temp.sesion(p_actor);
    v_r := crm.confirmar_inversion_fn((v_r ->> 'solicitud_id')::uuid);
    perform pg_temp.sesion(null);
  exception when others then
    perform pg_temp.sesion(null);
    raise exception 'ENSAYO ABORTADO: la conversión real del cliente % falló (% %)', p_n, sqlstate, sqlerrm;
  end;
  if not coalesce((v_r ->> 'ok')::boolean, false)
     or (select l.etapa <> 'convertido' or not l.activo or l.inversionista_id is distinct from v_per from crm.leads l where l.id = v_lead)
     or (select l.telefono_alternativo from crm.leads l where l.id = v_lead) is distinct from p_alt then
    raise exception 'ENSAYO ABORTADO: el cliente % no quedó convertido, activo, enlazado a su persona y con el alternativo pedido (%)', p_n, v_r;
  end if;
  if not exists (select 1 from crm.cierres_externos ce where ce.lead_id = v_lead and ce.es_cierre_inicial) then
    raise exception 'ENSAYO ABORTADO: el cliente % no quedó con su cierre externo (no se podría editar)', p_n;
  end if;
  return v_lead;
end;
$f$;

-- El CLIENTE que se EDITA en cada caso: conversión real a nombre de p_actor (con el alternativo p_alt) y, si se pide, RETIRADO
-- después por Gerencia (como lo hace hoy: UPDATE activo=false por API).
create function pg_temp.cliente(p_n integer, p_nombre text, p_actor uuid, p_alt text default null, p_retirar boolean default false)
returns uuid language plpgsql as $f$
declare v_id uuid := pg_temp.convertir_real(p_n, p_nombre, p_actor, p_alt);
begin
  if p_retirar and pg_temp.retirar(pg_temp.actor('GERENCIA'), v_id) <> '1' then
    raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente %', p_n;
  end if;
  return v_id;
end;
$f$;

-- ── Jueces ──────────────────────────────────────────────────────────────────────────────────────────────────────────

-- El veredicto que da HOY la disponibilidad a un número como TELÉFONO PRINCIPAL (excluyendo la ficha que se edita): es el que la
-- regla tiene que repetir byte a byte. Aborta si no es el estado (y el asesor) que el caso declara.
create function pg_temp.veredicto_hoy(p_caso text, p_numero text, p_excluir uuid, p_estado text, p_vendedor text default null)
returns jsonb language plpgsql as $f$
declare v_v jsonb := private.verificar_disponibilidad_lead_impl(p_numero, null, p_excluir);
begin
  if v_v ->> 'estado' is distinct from p_estado or (p_vendedor is not null and v_v ->> 'vendedor' is distinct from p_vendedor) then
    raise exception 'ENSAYO ABORTADO: %: la disponibilidad de hoy para % no es % % (%): el caso no mediría la regla', p_caso, p_numero,
      p_estado, coalesce(p_vendedor, ''), v_v;
  end if;
  return v_v;
end;
$f$;

-- Lo que debe cumplir una escritura RECHAZADA: el error EXACTO (`p_esperado`: {"error": SQLSTATE, "detalle": <veredicto exacto>,
-- "mensaje": <texto que debe contener>}), la ficha que se escribía intacta byte a byte, el otro lead intacto, ninguna escritura (huella)
-- y las mismas fichas con el número. Si la escritura se ACEPTÓ, el fallo dice el defecto: dos fichas con el mismo número.
create function pg_temp.juzgar_rechazo(p_caso text, p_via text, p_res text, p_esperado jsonb, p_lead uuid, p_lead_antes jsonb,
                                       p_otro uuid, p_otro_antes jsonb, p_huella text, p_numero text, p_fichas bigint)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; e record;
begin
  if p_res like 'ok|%' then
    return format(E'FALLO %s: %s se ACEPTÓ (%s) → el cliente quedó con el número %s, que ya era de otro lead: %s fichas con ese número (había %s)\n',
      p_caso, p_via, substr(p_res, 4), coalesce(p_numero, '-'), pg_temp.fichas_con(p_numero), p_fichas);
  end if;
  e := pg_temp.error_de(p_res);
  if e.estado is distinct from p_esperado ->> 'error' then
    v_m := array_append(v_m, format('rechazó con otro error: %s (se esperaba %s)', p_res, p_esperado::text));
  else
    if p_esperado ? 'mensaje' and position(p_esperado ->> 'mensaje' in coalesce(e.mensaje, '')) = 0 then
      v_m := array_append(v_m, format('mensaje «%s», se esperaba que contuviera «%s»', e.mensaje, p_esperado ->> 'mensaje'));
    end if;
    if p_esperado ? 'detalle' and pg_temp.a_jsonb(e.detalle) is distinct from p_esperado -> 'detalle' then
      v_m := array_append(v_m, format('detalle %s, se esperaba EXACTAMENTE %s', coalesce(e.detalle, '(vacío)'), (p_esperado -> 'detalle')::text));
    end if;
    if not (p_esperado ? 'detalle') and e.detalle is not null then
      v_m := array_append(v_m, format('el %s trae detalle (%s): no debía llevar ningún veredicto', e.estado, e.detalle));
    end if;
  end if;
  if p_lead is not null and pg_temp.ficha(p_lead) is distinct from p_lead_antes then
    v_m := array_append(v_m, 'la ficha que se escribía cambió');
  end if;
  if p_otro is not null and pg_temp.ficha(p_otro) is distinct from p_otro_antes then
    v_m := array_append(v_m, 'el otro lead cambió');
  end if;
  if pg_temp.huella_escritura() is distinct from p_huella then
    v_m := array_append(v_m, format('se escribió algo (leads:md5, actividades:md5, episodios:md5, tareas, personas, documentos, ciclos: %s → %s)',
      p_huella, pg_temp.huella_escritura()));
  end if;
  if p_numero is not null and pg_temp.fichas_con(p_numero) <> p_fichas then
    v_m := array_append(v_m, format('%s fichas con el número %s (había %s)', pg_temp.fichas_con(p_numero), p_numero, p_fichas));
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- La EDICIÓN (ficha) que tiene que RECHAZARSE (la ficha y el otro lead se fotografían aquí, justo antes).
create function pg_temp.rechazo_edicion(p_caso text, p_actor uuid, p_lead uuid, p_cambios jsonb, p_esperado jsonb, p_otro uuid,
                                        p_numero text)
returns void language plpgsql as $f$
declare
  v_ficha jsonb := pg_temp.ficha(p_lead); v_otro jsonb := pg_temp.ficha(p_otro);
  v_huella text := pg_temp.huella_escritura(); v_fichas bigint := pg_temp.fichas_con(p_numero); v_res text;
begin
  v_res := pg_temp.editar(p_actor, p_lead, p_cambios);
  perform pg_temp.medida(format('%s · edición %s → %s', p_caso, p_cambios::text, v_res));
  perform pg_temp.reg(p_caso, pg_temp.juzgar_rechazo(p_caso, 'la edición', v_res, p_esperado, p_lead, v_ficha, p_otro, v_otro,
                                                     v_huella, p_numero, v_fichas));
end;
$f$;

-- El UPDATE directo (con o sin sesión, con o sin válvulas) que tiene que RECHAZARSE.
create function pg_temp.rechazo_update(p_caso text, p_actor uuid, p_lead uuid, p_set jsonb, p_valvulas text[], p_esperado jsonb,
                                       p_otro uuid, p_numero text)
returns void language plpgsql as $f$
declare
  v_ficha jsonb := pg_temp.ficha(p_lead); v_otro jsonb := pg_temp.ficha(p_otro);
  v_huella text := pg_temp.huella_escritura(); v_fichas bigint := pg_temp.fichas_con(p_numero); v_res text;
begin
  v_res := pg_temp.actualizar_v(p_actor, p_lead, p_set, p_valvulas);
  perform pg_temp.medida(format('%s · UPDATE %s (%s, válvulas %s) → %s', p_caso, p_set::text,
    case when p_actor is null then 'sin sesión' else 'con sesión' end, coalesce(nullif(array_to_string(p_valvulas, '+'), ''), '-'), v_res));
  perform pg_temp.reg(p_caso, pg_temp.juzgar_rechazo(p_caso, case when p_actor is null then 'el UPDATE sin sesión' else 'el UPDATE con sesión' end
                                                     || case when cardinality(p_valvulas) > 0 then ' bajo ' || array_to_string(p_valvulas, ' + ') else '' end,
                                                     v_res, p_esperado, p_lead, v_ficha, p_otro, v_otro, v_huella, p_numero, v_fichas));
end;
$f$;

-- Comprueba los valores esperados de una ficha después de una escritura aceptada.
create function pg_temp.campos(p_caso text, p_lead uuid, p_campos jsonb) returns text language plpgsql as $f$
declare v_k text; v_m text[] := '{}'; v_f jsonb := pg_temp.ficha(p_lead);
begin
  for v_k in select jsonb_object_keys(p_campos) loop
    if (v_f ->> v_k) is distinct from (p_campos ->> v_k) then
      v_m := array_append(v_m, format('%s = %s (se esperaba %s)', v_k, coalesce(v_f ->> v_k, 'null'), coalesce(p_campos ->> v_k, 'null')));
    end if;
  end loop;
  return case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: se guardó otra cosa: %s\n', p_caso, array_to_string(v_m, '; ')) end;
end;
$f$;

-- La EDICIÓN (ficha) que tiene que GUARDARSE como hoy: respuesta ok y cada valor esperado (ya normalizado).
create function pg_temp.ok_edicion(p_caso text, p_actor uuid, p_lead uuid, p_cambios jsonb, p_campos jsonb)
returns void language plpgsql as $f$
declare v_res text;
begin
  v_res := pg_temp.editar(p_actor, p_lead, p_cambios);
  perform pg_temp.medida(format('%s · edición %s → %s', p_caso, p_cambios::text, v_res));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la edición se RECHAZÓ (%s) y hoy se guarda: la regla bloquea una edición que no le toca\n', p_caso, v_res));
    return;
  end if;
  perform pg_temp.reg(p_caso, pg_temp.campos(p_caso, p_lead, p_campos));
end;
$f$;

-- El UPDATE directo que tiene que GUARDARSE como hoy: 'ok|1' y cada valor esperado.
create function pg_temp.ok_update(p_caso text, p_actor uuid, p_lead uuid, p_set jsonb, p_valvulas text[], p_campos jsonb)
returns void language plpgsql as $f$
declare v_res text;
begin
  v_res := pg_temp.actualizar_v(p_actor, p_lead, p_set, p_valvulas);
  perform pg_temp.medida(format('%s · UPDATE %s (%s, válvulas %s) → %s', p_caso, p_set::text, case when p_actor is null then 'sin sesión' else 'con sesión' end,
    coalesce(nullif(array_to_string(p_valvulas, '+'), ''), '-'), v_res));
  if v_res is distinct from 'ok|1' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: el UPDATE se RECHAZÓ (%s) y hoy se guarda\n', p_caso, v_res));
    return;
  end if;
  perform pg_temp.reg(p_caso, pg_temp.campos(p_caso, p_lead, p_campos));
end;
$f$;

-- Veredicto «ya es cliente» de un convertido SIN persona (formato del verificador, sin via: la decisión del 2.7, la pieza del 2.8).
create function pg_temp.sin_persona(p_asesor text) returns jsonb language sql immutable as $$
  select jsonb_build_object('estado', 'ya_es_cliente', 'asesor', p_asesor)
$$;

-- CLAVES DE CANDADO (las del oráculo del 2.8, ronda 4): las que pide UNA escritura, leídas en `pg_locks` dentro de un bloque que se
-- deshace. Son candados consultivos de transacción (`pg_advisory_xact_lock(hashtextextended('avancecrm:lead:' || <clave>, 0))`, en
-- `private.bloquear_contactos_lead`); en `pg_locks` la clave de 64 bits es `classid << 32 | objid`.
create function pg_temp.claves_tomadas() returns bigint[] language sql as $$
  select coalesce(array_agg(((l.classid::text::bigint) << 32) | (l.objid::text::bigint) order by 1), '{}')
  from pg_locks l
  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 1
$$;
create function pg_temp.clave(p_tipo text, p_valor text) returns bigint language sql stable as $$
  select hashtextextended('avancecrm:lead:' || p_tipo || ':'
                          || case when p_tipo = 'telefono' then private.normalizar_telefono(p_valor) else btrim(p_valor) end, 0)
$$;
create function pg_temp.nombre_clave(p_tipo text, p_valor text) returns text language sql stable as $$
  select p_tipo || ':' || case when p_tipo = 'telefono' then private.normalizar_telefono(p_valor) else btrim(p_valor) end
$$;
create function pg_temp.claves_de(p_actor uuid, p_sql text, out antes bigint[], out pedidas bigint[], out resultado text)
language plpgsql as $f$
begin
  begin
    antes := pg_temp.claves_tomadas();
    perform pg_temp.sesion(p_actor);
    execute p_sql;
    perform pg_temp.sesion(null);
    pedidas := array(select x from unnest(pg_temp.claves_tomadas()) x except select y from unnest(antes) y order by 1);
    resultado := 'ok';
    raise exception 'ENSAYO_CLAVES_DESHACER';
  exception when others then
    perform pg_temp.sesion(null);
    if sqlerrm <> 'ENSAYO_CLAVES_DESHACER' then
      resultado := sqlstate || '|' || sqlerrm;
    end if;
  end;
end;
$f$;
-- El juez: entre las claves de TELÉFONO y de DNI de los valores del caso (p_valores), la escritura tiene que pedir EXACTAMENTE
-- p_esperadas ('telefono:<número>'). Ninguna clave esperada puede estar tomada ANTES (si lo estuviera, el caso no la vería pedir).
create function pg_temp.juzgar_claves(p_caso text, p_actor uuid, p_sql text, p_esperadas text[], p_valores text[])
returns void language plpgsql as $f$
declare
  r record; v_esp bigint[]; v_uni bigint[]; v_ped bigint[]; v_falta text; v_sobra text; v_pedidas_txt text;
begin
  v_esp := array(select distinct pg_temp.clave(split_part(e, ':', 1), substr(e, length(split_part(e, ':', 1)) + 2))
                   from unnest(p_esperadas) e order by 1);
  v_uni := array(select distinct k from unnest(p_valores) v, lateral (values (pg_temp.clave('telefono', v)), (pg_temp.clave('dni', v))) t(k)
                  order by 1);
  r := pg_temp.claves_de(p_actor, p_sql);
  if r.resultado is distinct from 'ok' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la escritura del caso falló (%s): no se pudieron leer sus claves de candado\n', p_caso, r.resultado));
    return;
  end if;
  if r.antes && v_esp then
    raise exception 'ENSAYO ABORTADO: %: alguna clave esperada ya estaba tomada antes de la escritura (el caso no la vería pedir)', p_caso;
  end if;
  v_ped := array(select x from unnest(r.pedidas) x where x = any (v_uni) order by 1);
  select string_agg(n, ', ' order by n) into v_pedidas_txt
    from (select distinct pg_temp.nombre_clave(t.tipo, v) as n
            from unnest(p_valores) v cross join (values ('telefono'), ('dni')) t(tipo)
           where pg_temp.clave(t.tipo, v) = any (v_ped)) x;
  perform pg_temp.medida(format('%s · %s → pidió %s (y %s candado(s) consultivo(s) más, ajenos a los contactos del caso)', p_caso,
    regexp_replace(p_sql, '\s+', ' ', 'g'), coalesce('{' || v_pedidas_txt || '}', '{ninguno}'), cardinality(r.pedidas) - cardinality(v_ped)));
  select string_agg(e, ', ' order by e) into v_falta
    from unnest(p_esperadas) e
   where pg_temp.clave(split_part(e, ':', 1), substr(e, length(split_part(e, ':', 1)) + 2)) <> all (v_ped);
  select string_agg(n, ', ' order by n) into v_sobra
    from (select distinct pg_temp.nombre_clave(t.tipo, v) as n, pg_temp.clave(t.tipo, v) as k
            from unnest(p_valores) v cross join (values ('telefono'), ('dni')) t(tipo)) x
   where x.k = any (v_ped) and x.k <> all (v_esp);
  perform pg_temp.reg(p_caso, case when v_falta is null and v_sobra is null then ''
    else format(E'FALLO %s: el disparador no pide las claves de candado esperadas: pidió %s; faltan {%s}; sobran {%s}\n',
                p_caso, coalesce('{' || v_pedidas_txt || '}', '{ninguna clave de contacto}'), coalesce(v_falta, ''), coalesce(v_sobra, '')) end);
end;
$f$;

insert into ens_actores (nombre, id)
select n.nombre, p.id
from (values ('VEND1'), ('VEND2'), ('VEND3'), ('SUP1'), ('GERENCIA'), ('COORD'), ('INACTIVO'), ('ADMIN')) n(nombre)
join public.perfiles p on p.nombre_completo = 'PASO08 ' || n.nombre;

do $ensayo$
declare
  v_vend1 uuid; v_vend2 uuid; v_vend3 uuid; v_sup1 uuid; v_ger uuid; v_coord uuid; v_inactivo uuid; v_admin uuid;
  v_disp regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_pieza regprocedure := to_regprocedure('private.juicio_lead_vivo_por_numero(text,uuid)');
  v_pieza28 regprocedure := to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)');
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_c uuid; v_m uuid; v_m2 uuid; v_l uuid; v_r uuid; v_d uuid; v_esp jsonb; v_res text; v_n bigint; v_txt text; v_src text;
  v_cli1 uuid;
begin
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.casos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ── Actores reales del banco (OBLIGATORIOS: sin ellos un caso se saltaría en silencio) ──────────────────────────────
  v_vend1 := pg_temp.actor('VEND1'); v_vend2 := pg_temp.actor('VEND2'); v_vend3 := pg_temp.actor('VEND3');
  v_sup1 := pg_temp.actor('SUP1'); v_ger := pg_temp.actor('GERENCIA'); v_coord := pg_temp.actor('COORD');
  v_inactivo := pg_temp.actor('INACTIVO'); v_admin := pg_temp.actor('ADMIN');
  if v_vend1 is null or v_vend2 is null or v_vend3 is null or v_sup1 is null or v_ger is null or v_coord is null
     or v_inactivo is null or v_admin is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (vend1=%, vend2=%, vend3=%, sup1=%, gerencia=%, coord=%, inactivo=%, admin=%)',
      v_vend1, v_vend2, v_vend3, v_sup1, v_ger, v_coord, v_inactivo, v_admin;
  end if;
  if private.rol_crm(v_vend1) is distinct from 'vendedor' or private.rol_crm(v_vend2) is distinct from 'vendedor'
     or private.rol_crm(v_vend3) is distinct from 'vendedor' or private.rol_crm(v_sup1) is distinct from 'supervisor'
     or private.rol_crm(v_ger) is distinct from 'gerencia' or private.rol_crm(v_coord) is distinct from 'coordinador'
     or private.rol_crm(v_inactivo) is not null or private.rol_crm(v_admin) is not null then
    raise exception 'ENSAYO ABORTADO: un actor del banco no tiene el rol esperado (vend1/vend2/vend3 vendedor; sup1 supervisor; gerencia; coord coordinador; inactivo y admin sin rol CRM)';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'ENSAYO ABORTADO: la bandera resolver_en_puertas está apagada en este laboratorio (la conversión real la necesita)';
  end if;
  -- El perfil cliente del banco PASO08 CLI1 (activo, asesor VEND1): T17 le siembra el teléfono del caso, como 6a del 2.7.
  v_cli1 := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 CLI1' and p.rol = 'cliente' and p.activo and p.asesor_perfil_id = v_vend1);
  if v_cli1 is null then
    raise exception 'ENSAYO ABORTADO: falta el perfil cliente del banco PASO08 CLI1 (activo, con asesor VEND1)';
  end if;
  -- El bloque de contactos del ensayo tiene que estar libre (teléfono, alternativo, DNI, perfiles y documentos).
  if exists (select 1 from crm.leads l where l.telefono like '+5192413%' or l.telefono_alternativo like '%92413%'
                                             or l.telefono_alternativo_crudo like '%92413%' or l.dni like '7533%')
     or exists (select 1 from public.perfiles p where p.telefono like '%92413%' or p.dni like '7533%')
     or exists (select 1 from crm.inversionista_identificadores d where d.documento_normalizado like '7533%'
                                                                   or d.documento_normalizado like '%92413%') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene contactos del bloque +51 924 13xxxx / 7533xxxx';
  end if;
  -- El cubo de comprobantes de la conversión real (fixture del banco; si falta, vive y muere en esta transacción).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('f4-comprobantes', 'f4-comprobantes', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
  on conflict (id) do nothing;
  perform pg_temp.medida(format('T0 disparador de la edición: %s',
    (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update')));
  perform pg_temp.medida(format('T0 la pieza private.juicio_lead_vivo_por_numero: %s', case when v_pieza is null then 'AUSENTE' else 'presente' end));
  perform pg_temp.medida(format('T0 permisos de crm.leads: UPDATE de authenticated (tabla=%s) · INSERT de authenticated (tabla=%s, alguna columna=%s)',
    has_table_privilege('authenticated', 'crm.leads', 'UPDATE'), has_table_privilege('authenticated', 'crm.leads', 'INSERT'),
    has_any_column_privilege('authenticated', 'crm.leads', 'INSERT')));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- T. LA REGLA: el alternativo nuevo de un CLIENTE es el número de OTRO lead VIVO ⇒ P0481 con el veredicto de la disponibilidad
  --    de hoy para ese lead (byte a byte), nada guardado. Hoy se ACEPTA: dos fichas con el mismo número.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

  -- T1a. = el TELÉFONO de otro lead vivo (de VEND3, con una conversación real: el veredicto lleva `ultima_conversacion_en`).
  v_m := pg_temp.lead_nuevo(v_vend3, 101, 'LEAD VIVO T1A');
  perform pg_temp.conversacion(v_vend3, v_m);
  v_c := pg_temp.cliente(1, 'CLIENTE T1A', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T1a', pg_temp.teln(101), v_c, 'tomado', 'PASO08 VEND3');
  if v_esp -> 'ultima_conversacion_en' is null or jsonb_typeof(v_esp -> 'ultima_conversacion_en') <> 'string'
     or jsonb_typeof(v_esp -> 'tenencia_desde') <> 'string' then
    raise exception 'ENSAYO ABORTADO: T1a: el veredicto de hoy no lleva tenencia_desde ni ultima_conversacion_en (%)', v_esp;
  end if;
  perform pg_temp.rechazo_edicion('T1a-alternativo-de-cliente-es-el-telefono-de-un-lead-vivo (lo edita su dueño VEND1)', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(101)), jsonb_build_object('error', 'P0481', 'mensaje', 'Contacto no disponible', 'detalle', v_esp),
    v_m, pg_temp.teln(101));

  -- T1b. Lo mismo con el cliente de VEND2 editado por su supervisor (SUP1) y el lead vivo de VEND1.
  v_m := pg_temp.lead_nuevo(v_vend1, 102, 'LEAD VIVO T1B');
  v_c := pg_temp.cliente(2, 'CLIENTE T1B DE VEND2', v_vend2);
  v_esp := pg_temp.veredicto_hoy('T1b', pg_temp.teln(102), v_c, 'tomado', 'PASO08 VEND1');
  perform pg_temp.rechazo_edicion('T1b-lo-edita-el-supervisor-del-dueno-del-cliente', v_sup1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(102)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(102));

  -- T2. = el ALTERNATIVO de otro lead vivo (hoy la disponibilidad ni lo ve: «libre»). El veredicto es el de ese lead por su teléfono.
  v_m := pg_temp.lead_nuevo(v_vend3, 103, 'LEAD VIVO T2 CON ALTERNATIVO', pg_temp.teln(203));
  v_c := pg_temp.cliente(3, 'CLIENTE T2', v_vend1);
  perform pg_temp.veredicto_hoy('T2 (el alternativo del otro lead)', pg_temp.teln(203), v_c, 'libre');
  v_esp := pg_temp.veredicto_hoy('T2', pg_temp.teln(103), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_edicion('T2-alternativo-de-cliente-es-el-alternativo-de-un-lead-vivo', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(203)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(203));

  -- T3. = el teléfono de un lead vivo SIN dueño (en la bolsa) ⇒ el veredicto de hoy: {"estado":"en_bolsa"}.
  v_m := pg_temp.lead_nuevo(v_ger, 104, 'LEAD EN BOLSA T3');
  if (select l.vendedor_id is not null or l.asignado_supervisor_id is not null from crm.leads l where l.id = v_m) then
    raise exception 'ENSAYO ABORTADO: el lead T3 no quedó en la bolsa (sin dueño)';
  end if;
  v_c := pg_temp.cliente(4, 'CLIENTE T3', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T3', pg_temp.teln(104), v_c, 'en_bolsa');
  perform pg_temp.rechazo_edicion('T3-alternativo-de-cliente-es-el-telefono-de-un-lead-en-bolsa', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(104)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(104));

  -- T4. El cliente cambia a la vez su TELÉFONO (a uno libre) y su alternativo (al de un lead vivo): la rama del cambio de teléfono.
  v_m := pg_temp.lead_nuevo(v_vend3, 105, 'LEAD VIVO T4');
  v_c := pg_temp.cliente(5, 'CLIENTE T4', v_vend1);
  perform pg_temp.veredicto_hoy('T4 (su teléfono nuevo)', pg_temp.teln(305), v_c, 'libre');
  v_esp := pg_temp.veredicto_hoy('T4', pg_temp.teln(105), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_edicion('T4-cliente-cambia-telefono-libre-y-alternativo-de-un-lead-vivo', v_vend1, v_c,
    jsonb_build_object('telefono', pg_temp.tel(305), 'telefono_alternativo', pg_temp.teln(105)),
    jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(105));

  -- T5. FORMA CANÓNICA: el número del lead vivo escrito de otra forma (sin +51; con espacios alrededor). Hoy lo rechaza el CHECK de
  --     formato (23514); con la regla, el P0481 del lead vivo (se compara en la forma canónica de `private.canonizar_contacto`).
  v_m := pg_temp.lead_nuevo(v_vend3, 106, 'LEAD VIVO T5');
  v_c := pg_temp.cliente(6, 'CLIENTE T5', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T5', pg_temp.teln(106), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_edicion('T5a-alternativo-sin-prefijo-es-el-telefono-de-un-lead-vivo', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.tel(106)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(106));
  perform pg_temp.rechazo_edicion('T5b-alternativo-con-espacios-es-el-telefono-de-un-lead-vivo', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', '  ' || pg_temp.teln(106) || ' '), jsonb_build_object('error', 'P0481', 'detalle', v_esp),
    v_m, pg_temp.teln(106));

  -- T6. EL ROL PRIMERO: quien no puede registrar leads (Coordinación; un usuario sin rol CRM) recibe el 42501 de siempre y nunca ve el
  --     veredicto. Hoy se acepta.
  v_m := pg_temp.lead_nuevo(v_vend3, 107, 'LEAD VIVO T6');
  v_c := pg_temp.cliente(7, 'CLIENTE T6', v_vend1);
  perform pg_temp.veredicto_hoy('T6', pg_temp.teln(107), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_edicion('T6a-coordinacion-pone-al-cliente-el-numero-de-un-lead-vivo', v_coord, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(107)), jsonb_build_object('error', '42501', 'mensaje', 'Acceso CRM revocado'),
    v_m, pg_temp.teln(107));
  -- (T6b con su propio lead vivo y su propio cliente: en el ROJO, T6a deja el número en otro cliente y el 2.8 lo pararía por eso.)
  v_m := pg_temp.lead_nuevo(v_vend3, 116, 'LEAD VIVO T6B');
  v_c := pg_temp.cliente(14, 'CLIENTE T6B', v_vend1);
  perform pg_temp.veredicto_hoy('T6b', pg_temp.teln(116), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_edicion('T6b-usuario-sin-rol-crm-pone-al-cliente-el-numero-de-un-lead-vivo', v_inactivo, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(116)), jsonb_build_object('error', '42501', 'mensaje', 'Acceso CRM revocado'),
    v_m, pg_temp.teln(116));

  -- T7. Bajo la válvula privilegiada `crm.op_privilegiada` (con sesión) el alternativo se juzga igual (como en la ronda 3 del 2.8).
  v_m := pg_temp.lead_nuevo(v_vend3, 108, 'LEAD VIVO T7');
  v_c := pg_temp.cliente(8, 'CLIENTE T7', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T7', pg_temp.teln(108), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_update('T7-bajo-la-valvula-privilegiada', v_vend1, v_c, jsonb_build_object('telefono_alternativo', pg_temp.teln(108)),
    array['crm.op_privilegiada'], jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(108));

  -- T8. PRECEDENCIA entre leads vivos: el número es el TELÉFONO de uno (VEND3, id alto) y el ALTERNATIVO de otro (VEND2, id bajo) ⇒
  --     manda el que lo tiene como teléfono (el que perdería con un orden «solo por id» es el del alternativo).
  v_m := pg_temp.lead_nuevo(v_vend3, 109, 'LEAD VIVO T8 TELEFONO', null, 'f2130000-0000-4000-8000-000000000109'::uuid);
  v_m2 := pg_temp.lead_nuevo(v_vend2, 209, 'LEAD VIVO T8 ALTERNATIVO', pg_temp.teln(109), '02130000-0000-4000-8000-000000000209'::uuid);
  v_c := pg_temp.cliente(9, 'CLIENTE T8', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T8', pg_temp.teln(109), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_edicion('T8-precedencia-el-que-lo-tiene-como-telefono-antes-que-el-del-alternativo', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(109)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(109));

  -- T9. DESEMPATE entre dos leads vivos que lo tienen como ALTERNATIVO: el de id menor (VEND2), no el de id mayor (VEND3).
  v_m := pg_temp.lead_nuevo(v_vend2, 110, 'LEAD VIVO T9 ID MENOR', pg_temp.teln(210), '02130000-0000-4000-8000-000000000110'::uuid);
  v_m2 := pg_temp.lead_nuevo(v_vend3, 111, 'LEAD VIVO T9 ID MAYOR', pg_temp.teln(210), 'f2130000-0000-4000-8000-000000000111'::uuid);
  v_c := pg_temp.cliente(10, 'CLIENTE T9', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T9', pg_temp.teln(110), v_c, 'tomado', 'PASO08 VEND2');
  perform pg_temp.rechazo_edicion('T9-desempate-por-id-entre-dos-alternativos', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(210)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(210));

  -- T10. Un cliente RETIRADO (convertido, activo=false) también es cliente: la regla vale igual (Gerencia, UPDATE directo).
  v_m := pg_temp.lead_nuevo(v_vend3, 112, 'LEAD VIVO T10');
  v_c := pg_temp.cliente(11, 'CLIENTE T10 RETIRADO', v_vend1, null, true);
  v_esp := pg_temp.veredicto_hoy('T10', pg_temp.teln(112), v_c, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_update('T10-cliente-retirado', v_ger, v_c, jsonb_build_object('telefono_alternativo', pg_temp.teln(112)),
    '{}'::text[], jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(112));

  -- T11. El número es a la vez el ALTERNATIVO de otro CLIENTE (VEND2) y el TELÉFONO de un lead vivo (VEND3; duplicado heredado) ⇒
  --      manda la regla del 2.8 («ya es cliente» del otro cliente), como hoy.
  v_m := pg_temp.lead_nuevo(v_vend3, 113, 'LEAD VIVO T11');
  v_d := pg_temp.cliente_sembrado(213, 'OTRO CLIENTE T11', v_vend2, pg_temp.teln(113));
  v_c := pg_temp.cliente(12, 'CLIENTE T11', v_vend1);
  perform pg_temp.rechazo_edicion('T11-otro-cliente-manda-sobre-el-lead-vivo (la regla del 2.8, como hoy)', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(113)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND2')),
    v_d, pg_temp.teln(113));

  -- T12. El cliente que YA comparte su alternativo con un lead vivo (heredado) no puede CAMBIARLO al número de OTRO lead vivo.
  --      (Su estado heredado: N5, más abajo; aquí nace igual: el lead vivo primero, el cliente con ese alternativo después.)
  v_m := pg_temp.lead_nuevo(v_vend3, 114, 'LEAD VIVO T12 HEREDADO');
  v_m2 := pg_temp.lead_nuevo(v_vend2, 115, 'LEAD VIVO T12 OTRO');
  v_c := pg_temp.cliente(13, 'CLIENTE T12 CON DUPLICADO HEREDADO', v_vend1, pg_temp.teln(114));
  v_esp := pg_temp.veredicto_hoy('T12', pg_temp.teln(115), v_c, 'tomado', 'PASO08 VEND2');
  perform pg_temp.rechazo_edicion('T12-duplicado-heredado-no-cambia-a-otro-numero-tomado', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(115)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m2, pg_temp.teln(115));

  -- T13. El lead vivo está en la BANDEJA de un supervisor (sin analista: vendedor nulo, supervisor SUP1) ⇒ «tomado» a nombre del
  --      supervisor (el respaldo del verificador: el dueño es el vendedor o, sin él, el supervisor).
  v_m := pg_temp.lead_nuevo(v_sup1, 117, 'LEAD VIVO T13 EN BANDEJA');
  if (select l.vendedor_id is not null or l.asignado_supervisor_id is distinct from v_sup1 from crm.leads l where l.id = v_m) then
    raise exception 'ENSAYO ABORTADO: el lead T13 no quedó en la bandeja de SUP1 (sin analista)';
  end if;
  v_c := pg_temp.cliente(15, 'CLIENTE T13', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T13', pg_temp.teln(117), v_c, 'tomado', 'PASO08 SUP1');
  perform pg_temp.rechazo_edicion('T13-el-lead-vivo-esta-en-la-bandeja-de-un-supervisor', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(117)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(117));

  -- T14. El lead vivo está VETADO («No contactar»; sembrado con los disparadores apagados: el veto solo lo pone su puerta) ⇒ el veredicto
  --      de hoy para su teléfono es el veto, sin asesor: {"estado":"no_contactar"} (nunca «tomado» con el nombre de quien lo tiene).
  v_m := pg_temp.lead_nuevo(v_vend3, 118, 'LEAD VIVO T14 VETADO');
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_m;
  set local session_replication_role = origin;
  v_c := pg_temp.cliente(16, 'CLIENTE T14', v_vend1);
  v_esp := pg_temp.veredicto_hoy('T14', pg_temp.teln(118), v_c, 'no_contactar');
  perform pg_temp.rechazo_edicion('T14-el-lead-vivo-esta-vetado (el veto, sin asesor)', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(118)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(118));

  -- T15. LA PROPIA FICHA NO TAPA A OTRO LEAD (ronda 2: bajo la válvula privilegiada `crm.op_privilegiada`, como la conversión real; auditor
  --      P3-1): un lead vivo (VEND1, teléfono X) que en el MISMO UPDATE pasa a convertido y pone como alternativo su propio teléfono X, que
  --      es también el ALTERNATIVO de otro lead vivo (VEND3) ⇒ el P0481 de ese otro lead (la propia ficha no cuenta, el otro sí; si la
  --      propia ficha entrara en la búsqueda, la taparía: su teléfono es X y el veredicto saldría «libre»). Hoy, bajo la válvula: el P0001
  --      de la guarda del perfil del convertido (`private.leads_before_update`).
  v_l := pg_temp.lead_nuevo(v_vend1, 144, 'LEAD T15 QUE SE CONVIERTE');
  v_m := pg_temp.lead_nuevo(v_vend3, 145, 'LEAD VIVO T15 CON ESE ALTERNATIVO', pg_temp.teln(144));
  v_esp := pg_temp.veredicto_hoy('T15', pg_temp.teln(145), v_l, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_update('T15-la-propia-ficha-no-tapa-al-otro-lead-vivo (bajo la válvula)', v_vend1, v_l,
    jsonb_build_object('etapa', 'convertido', 'telefono_alternativo', pg_temp.teln(144)), array['crm.op_privilegiada'],
    jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(144));

  -- T15b. Lo mismo por la rama del TELÉFONO (ronda 2): el lead cambia además su teléfono a uno libre y pone X como alternativo ⇒ el P0481
  --       del otro lead.
  v_l := pg_temp.lead_nuevo(v_vend1, 154, 'LEAD T15B QUE SE CONVIERTE');
  v_m := pg_temp.lead_nuevo(v_vend3, 155, 'LEAD VIVO T15B CON ESE ALTERNATIVO', pg_temp.teln(154));
  perform pg_temp.veredicto_hoy('T15b (su teléfono nuevo)', pg_temp.teln(354), v_l, 'libre');
  v_esp := pg_temp.veredicto_hoy('T15b', pg_temp.teln(155), v_l, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_update('T15b-la-propia-ficha-no-tapa-al-otro-lead-vivo-rama-del-telefono (bajo la válvula)', v_vend1, v_l,
    jsonb_build_object('etapa', 'convertido', 'telefono', pg_temp.teln(354), 'telefono_alternativo', pg_temp.teln(154)), array['crm.op_privilegiada'],
    jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(154));

  -- T17. EL LEAD VIVO TIENE EL TELÉFONO DE UN PERFIL ACTIVO DEL PORTAL (ronda 2, auditor P3-3; estado heredado sembrado como en 6a del 2.7:
  --      el lead nace por la puerta real y DESPUÉS el perfil cliente del banco PASO08 CLI1 —asesor VEND1— recibe ese teléfono con los
  --      disparadores apagados) ⇒ el veredicto de hoy para ese número es el del Portal, que el verificador mira antes que el «tomado»:
  --      {"estado":"ya_es_cliente","asesor":"PASO08 VEND1"} (el asesor del perfil, no el dueño del lead ni quien edita), sin «via».
  v_m := pg_temp.lead_nuevo(v_vend3, 119, 'LEAD VIVO T17 CON EL TELEFONO DE UN PERFIL DEL PORTAL');
  set local session_replication_role = replica;
  update public.perfiles set telefono = pg_temp.tel(119) where id = v_cli1;
  set local session_replication_role = origin;
  v_c := pg_temp.cliente(18, 'CLIENTE T17 DE VEND2', v_vend2);
  v_esp := pg_temp.veredicto_hoy('T17', pg_temp.teln(119), v_c, 'ya_es_cliente');
  if v_esp is distinct from jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1') then
    raise exception 'ENSAYO ABORTADO: T17: el verificador no reconoce el perfil del Portal por el teléfono del lead vivo (%)', v_esp;
  end if;
  perform pg_temp.rechazo_edicion('T17-el-lead-vivo-tiene-el-telefono-de-un-perfil-activo-del-portal (ya_es_cliente con el asesor del perfil)', v_vend2, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(119)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(119));

  -- T16. UN RETIRADO NO TAPA A UN VIVO: el número es el TELÉFONO de un lead RETIRADO y el ALTERNATIVO de un lead VIVO (VEND2) ⇒ manda el
  --      vivo (un retirado no cuenta: ni se nombra ni oculta a otro; si entrara en la búsqueda, lo taparía con un «libre»).
  v_r := pg_temp.lead_nuevo(v_vend3, 146, 'LEAD RETIRADO T16');
  if pg_temp.retirar(v_ger, v_r) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar el lead T16'; end if;
  v_m := pg_temp.lead_nuevo(v_vend2, 147, 'LEAD VIVO T16 CON ESE ALTERNATIVO', pg_temp.teln(146));
  v_c := pg_temp.cliente(17, 'CLIENTE T16', v_vend1);
  perform pg_temp.veredicto_hoy('T16 (el teléfono del retirado)', pg_temp.teln(146), v_c, 'libre');
  v_esp := pg_temp.veredicto_hoy('T16', pg_temp.teln(147), v_c, 'tomado', 'PASO08 VEND2');
  perform pg_temp.rechazo_edicion('T16-un-retirado-no-tapa-al-lead-vivo', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(146)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_m, pg_temp.teln(146));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- N. LO QUE NO CAMBIA (la respuesta de hoy, exacta, con y sin la migración).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

  -- N1. El alternativo LIBRE se guarda.
  v_c := pg_temp.cliente(20, 'CLIENTE N1', v_vend1);
  perform pg_temp.ok_edicion('N1-alternativo-libre', v_vend1, v_c, jsonb_build_object('telefono_alternativo', pg_temp.teln(320)),
    jsonb_build_object('telefono_alternativo', pg_temp.teln(320), 'etapa', 'convertido'));

  -- N2. Un lead que NO es cliente pone como alternativo el teléfono (N2a) o el alternativo (N2b) de otro lead vivo: fuera de la regla.
  v_m := pg_temp.lead_nuevo(v_vend3, 122, 'LEAD VIVO N2A', pg_temp.teln(224));
  v_l := pg_temp.lead_nuevo(v_vend1, 121, 'LEAD N2A QUE NO ES CLIENTE');
  perform pg_temp.ok_edicion('N2a-lead-que-no-es-cliente-alternativo-telefono-de-lead-vivo', v_vend1, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(122)), jsonb_build_object('telefono_alternativo', pg_temp.teln(122)));
  v_l := pg_temp.lead_nuevo(v_vend1, 123, 'LEAD N2B QUE NO ES CLIENTE');
  perform pg_temp.ok_edicion('N2b-lead-que-no-es-cliente-alternativo-alternativo-de-lead-vivo', v_vend1, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(224)), jsonb_build_object('telefono_alternativo', pg_temp.teln(224)));
  -- N2c. El lead que no es cliente cambia a la vez su teléfono (libre) y su alternativo (el teléfono de un lead vivo): la rama del
  --      cambio de teléfono tampoco lo juzga.
  v_m := pg_temp.lead_nuevo(v_vend3, 141, 'LEAD VIVO N2C');
  v_l := pg_temp.lead_nuevo(v_vend1, 139, 'LEAD N2C QUE NO ES CLIENTE');
  perform pg_temp.veredicto_hoy('N2c (su teléfono nuevo)', pg_temp.teln(140), v_l, 'libre');
  perform pg_temp.ok_edicion('N2c-lead-que-no-es-cliente-cambia-telefono-y-alternativo-de-lead-vivo', v_vend1, v_l,
    jsonb_build_object('telefono', pg_temp.tel(140), 'telefono_alternativo', pg_temp.teln(141)),
    jsonb_build_object('telefono', pg_temp.teln(140), 'telefono_alternativo', pg_temp.teln(141)));

  -- N3. Un lead RETIRADO (activo=false, etapa nuevo; VEND3; con alternativo). Lo que hace HOY la disponibilidad del teléfono PRINCIPAL:
  --     la rama «tomado» del verificador exige activo=true ⇒ «libre» (N3m: el cliente se pone ese número como TELÉFONO y se guarda).
  --     La regla hace lo mismo con el alternativo: N3a (su teléfono) y N3b (su alternativo) se guardan.
  --     (N3m con su propio retirado: al guardarse, su número pasa a ser el de un cliente y el 2.8 pararía a N3a por eso.)
  v_r := pg_temp.lead_nuevo(v_vend3, 128, 'LEAD RETIRADO N3M');
  if pg_temp.retirar(v_ger, v_r) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar el lead N3m'; end if;
  v_c := pg_temp.cliente(21, 'CLIENTE N3M', v_vend1);
  perform pg_temp.medida(format('N3m la disponibilidad de hoy para el teléfono del retirado (excluido el cliente): %s',
    private.verificar_disponibilidad_lead_impl(pg_temp.teln(128), null, v_c)));
  perform pg_temp.veredicto_hoy('N3m', pg_temp.teln(128), v_c, 'libre');
  perform pg_temp.ok_edicion('N3m-hoy-el-telefono-principal-del-cliente-puede-ser-el-de-un-retirado', v_vend1, v_c,
    jsonb_build_object('telefono', pg_temp.tel(128)), jsonb_build_object('telefono', pg_temp.teln(128)));
  v_r := pg_temp.lead_nuevo(v_vend3, 125, 'LEAD RETIRADO N3', pg_temp.teln(225));
  if pg_temp.retirar(v_ger, v_r) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar el lead N3'; end if;
  v_c := pg_temp.cliente(22, 'CLIENTE N3A', v_vend1);
  perform pg_temp.ok_edicion('N3a-alternativo-de-cliente-es-el-telefono-de-un-retirado', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(125)), jsonb_build_object('telefono_alternativo', pg_temp.teln(125)));
  v_c := pg_temp.cliente(23, 'CLIENTE N3B', v_vend1);
  perform pg_temp.ok_edicion('N3b-alternativo-de-cliente-es-el-alternativo-de-un-retirado', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(225)), jsonb_build_object('telefono_alternativo', pg_temp.teln(225)));

  -- N4. Un lead DESCARTADO (activo, en enfriamiento por «competencia»: 180 días; VEND3). Medida N4m: hoy la disponibilidad del teléfono
  --     PRINCIPAL lo para con «enfriamiento» (no es «tomado»). El alternativo de un cliente no cambia: fuera del encargo (N4a).
  v_r := pg_temp.lead_nuevo(v_vend3, 126, 'LEAD DESCARTADO N4');
  if pg_temp.descartar(v_vend3, v_r, 'competencia') <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo descartar el lead N4'; end if;
  v_c := pg_temp.cliente(24, 'CLIENTE N4M', v_vend1);
  v_esp := pg_temp.veredicto_hoy('N4m', pg_temp.teln(126), v_c, 'enfriamiento');
  perform pg_temp.rechazo_edicion('N4m-hoy-el-telefono-principal-del-cliente-no-puede-ser-el-de-un-descartado-en-enfriamiento', v_vend1, v_c,
    jsonb_build_object('telefono', pg_temp.tel(126)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_r, pg_temp.teln(126));
  v_c := pg_temp.cliente(25, 'CLIENTE N4A', v_vend1);
  perform pg_temp.ok_edicion('N4a-alternativo-de-cliente-es-el-telefono-de-un-descartado (fuera del encargo)', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(126)), jsonb_build_object('telefono_alternativo', pg_temp.teln(126)));

  -- N5. D-25, el DUPLICADO HEREDADO: el cliente ya comparte su alternativo con el teléfono de un lead vivo (VEND3). Lo que la edición no
  --     toca no se juzga: N5a nombre y nota; N5b reenvía su mismo alternativo; N5c cambia su teléfono (libre) y reenvía el alternativo;
  --     N5d pasa su alternativo a uno libre.
  v_m := pg_temp.lead_nuevo(v_vend3, 127, 'LEAD VIVO N5 HEREDADO');
  v_c := pg_temp.cliente(27, 'CLIENTE N5 CON DUPLICADO HEREDADO', v_vend1, pg_temp.teln(127));
  if pg_temp.fichas_con(pg_temp.teln(127)) <> 2 then raise exception 'ENSAYO ABORTADO: N5 no parte del duplicado heredado'; end if;
  perform pg_temp.medida(format('H1 (fuera del encargo) el cliente N5 nació por el alta REAL con el alternativo %s (el teléfono de un lead vivo de VEND3) y se convirtió por la conversión REAL: %s fichas con ese número; la regla del 2.13 no lo ve (la conversión no pone ni cambia el alternativo)',
    pg_temp.teln(127), pg_temp.fichas_con(pg_temp.teln(127))));
  perform pg_temp.ok_edicion('N5a-duplicado-heredado-edita-nombre-y-nota', v_vend1, v_c,
    jsonb_build_object('nombre_completo', 'CLIENTE N5 RENOMBRADO', 'nota', 'n5a'),
    jsonb_build_object('nombre_completo', 'CLIENTE N5 RENOMBRADO', 'nota', 'n5a', 'telefono_alternativo', pg_temp.teln(127)));
  perform pg_temp.ok_edicion('N5b-duplicado-heredado-reenvia-su-mismo-alternativo', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(127), 'nota', 'n5b'),
    jsonb_build_object('telefono_alternativo', pg_temp.teln(127), 'nota', 'n5b'));
  perform pg_temp.veredicto_hoy('N5c (su teléfono nuevo)', pg_temp.teln(327), v_c, 'libre');
  perform pg_temp.ok_edicion('N5c-duplicado-heredado-cambia-su-telefono-y-reenvia-el-alternativo', v_vend1, v_c,
    jsonb_build_object('telefono', pg_temp.tel(327), 'telefono_alternativo', pg_temp.teln(127)),
    jsonb_build_object('telefono', pg_temp.teln(327), 'telefono_alternativo', pg_temp.teln(127)));
  perform pg_temp.ok_edicion('N5d-duplicado-heredado-pasa-su-alternativo-a-uno-libre', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(527)), jsonb_build_object('telefono_alternativo', pg_temp.teln(527)));

  -- N6. SIN SESIÓN (escritura interna), como hoy: se guarda.
  v_m := pg_temp.lead_nuevo(v_vend3, 129, 'LEAD VIVO N6');
  v_c := pg_temp.cliente(29, 'CLIENTE N6', v_vend1);
  perform pg_temp.ok_update('N6-sin-sesion', null, v_c, jsonb_build_object('telefono_alternativo', pg_temp.teln(129)), '{}'::text[],
    jsonb_build_object('telefono_alternativo', pg_temp.teln(129)));

  -- N7. LA PROPIA FICHA. N7a el cliente pone su propio teléfono como alternativo ⇒ se guarda. N7b (ronda 2: bajo la válvula privilegiada,
  --     como la conversión real) un lead vivo que en el MISMO UPDATE pasa a convertido y pone como alternativo su propio teléfono (su fila
  --     vieja es un lead vivo con ese número): nunca contra sí misma ⇒ la respuesta de hoy bajo la válvula (la guarda del perfil del
  --     convertido de `private.leads_before_update`, que corre DESPUÉS del disparador de disponibilidad: P0001 «Un lead convertido debe
  --     estar enlazado a un perfil de cliente»), no el P0481 de la regla.
  v_c := pg_temp.cliente(30, 'CLIENTE N7A', v_vend1);
  perform pg_temp.ok_edicion('N7a-cliente-pone-su-propio-telefono-como-alternativo', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(30)), jsonb_build_object('telefono_alternativo', pg_temp.teln(30)));
  v_l := pg_temp.lead_nuevo(v_vend1, 131, 'LEAD N7B QUE SE CONVIERTE');
  perform pg_temp.rechazo_update('N7b-convertir-y-poner-su-propio-telefono-en-el-mismo-update (bajo la válvula; la respuesta de hoy)', v_vend1, v_l,
    jsonb_build_object('etapa', 'convertido', 'telefono_alternativo', pg_temp.teln(131)), array['crm.op_privilegiada'],
    jsonb_build_object('error', 'P0001', 'mensaje', 'Un lead convertido debe estar enlazado a un perfil de cliente'), null, pg_temp.teln(131));
  --     N7c lo mismo cambiando además su teléfono (a uno libre): la rama del cambio de teléfono tampoco juzga contra la propia ficha.
  v_l := pg_temp.lead_nuevo(v_vend1, 142, 'LEAD N7C QUE SE CONVIERTE');
  perform pg_temp.rechazo_update('N7c-convertir-cambiar-telefono-y-poner-el-viejo-como-alternativo (bajo la válvula; la respuesta de hoy)', v_vend1, v_l,
    jsonb_build_object('etapa', 'convertido', 'telefono', pg_temp.teln(143), 'telefono_alternativo', pg_temp.teln(142)), array['crm.op_privilegiada'],
    jsonb_build_object('error', 'P0001', 'mensaje', 'Un lead convertido debe estar enlazado a un perfil de cliente'), null, pg_temp.teln(142));

  -- N14. CONVERSIÓN ILEGAL SIN VÁLVULA (ronda 2, auditor P3-1): un lead vivo propio que en el MISMO UPDATE pasa a convertido —SIN la
  --      válvula privilegiada: lo que haría un PATCH forjado— y pone como alternativo el teléfono de OTRO lead vivo (VEND3) ⇒ para la regla
  --      no es cliente: la respuesta de hoy (la guarda de la conversión de `private.leads_before_update`, P0001 «La conversión a cliente
  --      solo se hace vía la operación de conversión») SIN veredicto en el detalle: no sirve para sondear de quién es un número.
  --      a: rama del alternativo · b: rama del teléfono (cambia además su teléfono a uno libre).
  v_m := pg_temp.lead_nuevo(v_vend3, 156, 'LEAD VIVO N14');
  v_l := pg_temp.lead_nuevo(v_vend1, 157, 'LEAD N14A CONVERSION ILEGAL');
  perform pg_temp.veredicto_hoy('N14a', pg_temp.teln(156), v_l, 'tomado', 'PASO08 VEND3');
  perform pg_temp.rechazo_update('N14a-conversion-ilegal-sin-valvula-rama-del-alternativo (P0001 sin veredicto)', v_vend1, v_l,
    jsonb_build_object('etapa', 'convertido', 'telefono_alternativo', pg_temp.teln(156)), '{}'::text[],
    jsonb_build_object('error', 'P0001', 'mensaje', 'La conversión a cliente solo se hace vía la operación de conversión'), v_m, pg_temp.teln(156));
  v_l := pg_temp.lead_nuevo(v_vend1, 158, 'LEAD N14B CONVERSION ILEGAL');
  perform pg_temp.veredicto_hoy('N14b (su teléfono nuevo)', pg_temp.teln(358), v_l, 'libre');
  perform pg_temp.rechazo_update('N14b-conversion-ilegal-sin-valvula-rama-del-telefono (P0001 sin veredicto)', v_vend1, v_l,
    jsonb_build_object('etapa', 'convertido', 'telefono', pg_temp.teln(358), 'telefono_alternativo', pg_temp.teln(156)), '{}'::text[],
    jsonb_build_object('error', 'P0001', 'mensaje', 'La conversión a cliente solo se hace vía la operación de conversión'), v_m, pg_temp.teln(156));

  -- N8. El número de OTRO CLIENTE: lo juzga el 2.8, como hoy («ya es cliente» del otro cliente, VEND2).
  v_d := pg_temp.cliente_sembrado(33, 'OTRO CLIENTE N8', v_vend2);
  v_c := pg_temp.cliente(32, 'CLIENTE N8', v_vend1);
  perform pg_temp.rechazo_edicion('N8-alternativo-de-cliente-es-el-telefono-de-otro-cliente (el 2.8, como hoy)', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(33)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND2')),
    v_d, pg_temp.teln(33));

  -- N9. QUITAR el alternativo se guarda.
  v_c := pg_temp.cliente(34, 'CLIENTE N9', v_vend1, pg_temp.teln(434));
  perform pg_temp.ok_edicion('N9-quitar-el-alternativo', v_vend1, v_c, jsonb_build_object('telefono_alternativo', null),
    jsonb_build_object('telefono_alternativo', null));

  -- N10. EL INSERT no cambia: un lead nuevo (no es cliente) con sesión cuyo alternativo es el teléfono de un lead vivo entra como hoy.
  v_m := pg_temp.lead_nuevo(v_vend3, 136, 'LEAD VIVO N10');
  v_l := gen_random_uuid();
  v_res := pg_temp.insertar(v_vend1, v_l, 'INSERT CON SESION N10', pg_temp.teln(135), pg_temp.teln(136));
  perform pg_temp.medida(format('N10 · INSERT con sesión (teléfono %s, alternativo %s) → %s', pg_temp.teln(135), pg_temp.teln(136), v_res));
  perform pg_temp.reg('N10-insert-con-sesion-no-cambia', case when v_res = 'ok|' || v_l::text then pg_temp.campos('N10', v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(136), 'etapa', 'nuevo'))
    else format(E'FALLO N10: el INSERT con sesión se RECHAZÓ (%s) y hoy entra\n', v_res) end);

  -- N11. FORMA CANÓNICA, el otro lado: un número INTERNACIONAL de 9 dígitos (+924130199, válido para el CHECK) NO es el móvil peruano
  --      con los mismos dígitos (+51924130199, el teléfono de un lead vivo): en la forma de `private.canonizar_contacto` son distintos
  --      (la de `private.normalizar_telefono`, la del candado, los junta: una espera de más, nunca un rechazo de más) ⇒ se guarda.
  v_m := pg_temp.lead_nuevo(v_vend3, 199, 'LEAD VIVO N11 MOVIL PERUANO');
  v_c := pg_temp.cliente(36, 'CLIENTE N11', v_vend1);
  perform pg_temp.ok_edicion('N11-un-internacional-de-9-digitos-no-es-el-movil-peruano-con-esos-digitos', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', '+924130199'), jsonb_build_object('telefono_alternativo', '+924130199'));

  -- N13. MEDIDA (fuera del encargo, H-2): el cliente cambia su TELÉFONO principal al ALTERNATIVO de un lead vivo ⇒ se guarda, hoy y con
  --      la regla (la disponibilidad del principal solo mira los teléfonos principales de los otros leads; D-49 habla del alternativo).
  v_m := pg_temp.lead_nuevo(v_vend3, 153, 'LEAD VIVO N13 CON ALTERNATIVO', pg_temp.teln(253));
  v_c := pg_temp.cliente(38, 'CLIENTE N13', v_vend1);
  perform pg_temp.veredicto_hoy('N13 (el alternativo del lead vivo como teléfono)', pg_temp.teln(253), v_c, 'libre');
  perform pg_temp.ok_edicion('N13-MEDIDA-el-telefono-del-cliente-puede-ser-el-alternativo-de-un-lead-vivo (fuera del encargo)', v_vend1, v_c,
    jsonb_build_object('telefono', pg_temp.tel(253)), jsonb_build_object('telefono', pg_temp.teln(253)));

  -- N12. LÍMITE DECLARADO: un lead vivo HEREDADO con su teléfono principal fuera de la forma canónica (sembrado: el disparador de hoy ya
  --      no deja escribirlo) es invisible para la disponibilidad de hoy («libre» para su número); si el alternativo nuevo de un cliente es
  --      el alternativo de ese lead, la regla no tiene veredicto que repetir ⇒ se guarda, como hoy (contar estos leads antes de publicar).
  v_m := pg_temp.lead_nuevo(v_vend3, 151, 'LEAD VIVO N12 HEREDADO NO CANONICO');
  set local session_replication_role = replica;
  update crm.leads set telefono = pg_temp.tel(150), telefono_alternativo = pg_temp.teln(250) where id = v_m;
  set local session_replication_role = origin;
  v_c := pg_temp.cliente(37, 'CLIENTE N12', v_vend1);
  perform pg_temp.veredicto_hoy('N12', pg_temp.tel(150), v_c, 'libre');
  perform pg_temp.ok_edicion('N12-LIMITE-lead-vivo-heredado-con-telefono-no-canonico (la disponibilidad no lo ve)', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(250)), jsonb_build_object('telefono_alternativo', pg_temp.teln(250)));
  -- N12b. EL OTRO LADO DEL LÍMITE (ronda 2, auditor P3-3 [H], medido): un lead heredado L (principal no canónico '924130160', alternativo
  --       +51924130260) y OTRO lead vivo M (VEND2) cuyo principal canónico es +51924130160, el de L normalizado (conviven: el índice único
  --       compara el texto). El cliente pone +51924130260 ⇒ se guarda: L es invisible para la disponibilidad y M no tiene ese número; la
  --       pieza solo mira leads cuyo principal ve el verificador (sin ese filtro encontraría a L, preguntaría por su principal normalizado
  --       y respondería «tomado» de M: un veredicto sobre OTRO lead).
  v_r := pg_temp.lead_nuevo(v_vend3, 159, 'LEAD VIVO N12B HEREDADO NO CANONICO');
  set local session_replication_role = replica;
  update crm.leads set telefono = pg_temp.tel(160), telefono_alternativo = pg_temp.teln(260) where id = v_r;
  set local session_replication_role = origin;
  v_m := pg_temp.lead_nuevo(v_vend2, 160, 'LEAD VIVO N12B PRINCIPAL CANONICO');
  v_c := pg_temp.cliente(39, 'CLIENTE N12B', v_vend1);
  perform pg_temp.veredicto_hoy('N12b (el alternativo de L)', pg_temp.teln(260), v_c, 'libre');
  perform pg_temp.veredicto_hoy('N12b (el principal de L, que normalizado es el de M)', pg_temp.tel(160), v_c, 'tomado', 'PASO08 VEND2');
  perform pg_temp.ok_edicion('N12b-LIMITE-el-heredado-no-canonico-no-hace-nombrar-a-otro-lead', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(260)), jsonb_build_object('telefono_alternativo', pg_temp.teln(260)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- K. EL CANDADO POR NÚMERO (ronda 4 del 2.8): cambiar el alternativo de un cliente pide la clave `telefono:` + el número, la MISMA que
  --    pide quien pone ese número como teléfono; el disparador la toma antes de juzgar. El cliente nace con un teléfono auxiliar y recibe
  --    el suyo con los disparadores apagados (así ninguna de sus claves estaba tomada antes del caso).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente(42, 'CLIENTE K1', v_vend1);
  set local session_replication_role = replica;
  update crm.leads set telefono = pg_temp.teln(41) where id = v_c;
  set local session_replication_role = origin;
  perform pg_temp.juzgar_claves('K1-el-alternativo-nuevo-del-cliente-pide-la-clave-del-numero', v_vend1,
    format('select crm.editar_lead_fn(%L::uuid, %L::jsonb)', v_c, jsonb_build_object('telefono_alternativo', pg_temp.teln(441))),
    array['telefono:' || pg_temp.teln(41), 'telefono:' || pg_temp.teln(441)], array[pg_temp.teln(41), pg_temp.teln(441)]);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C. CATÁLOGO (con y sin la migración).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C1. La pieza (si existe): INVOKER de postgres, STABLE, search_path vacío y nada más, EXECUTE solo para postgres.
  perform pg_temp.reg('C1 la pieza private.juicio_lead_vivo_por_numero (si existe): INVOKER de postgres, STABLE, search_path vacío, EXECUTE solo postgres',
    case when v_pieza is null then ''
         when exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                        and p.provolatile = 's' and p.proconfig = array['search_path=""'])
              and (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
                     from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
                  = array['postgres:EXECUTE:false']
              and not has_function_privilege('anon', v_pieza, 'EXECUTE') and not has_function_privilege('authenticated', v_pieza, 'EXECUTE')
              and not has_function_privilege('service_role', v_pieza, 'EXECUTE') then ''
         else E'FALLO C1: la ficha de la pieza no es la esperada (INVOKER de postgres, STABLE, search_path vacío, EXECUTE solo postgres)\n' end);
  -- C2. El disparador: DEFINER de postgres, search_path vacío y lock_timeout 5s y nada más, EXECUTE solo para postgres.
  perform pg_temp.reg('C2 el disparador: DEFINER de postgres, proconfig exacto, EXECUTE solo postgres',
    case when exists (select 1 from pg_proc p where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                        and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
              and (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
                     from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
                  = array['postgres:EXECUTE:false']
              and not has_function_privilege('authenticated', v_disp, 'EXECUTE') then ''
         else E'FALLO C2: la ficha del disparador no es la esperada\n' end);
  -- C3. Los disparadores de tabla de disponibilidad, los del 2.8 (esta migración no los toca), habilitados.
  perform pg_temp.reg('C3 los disparadores de tabla de disponibilidad son los del 2.8 y están habilitados',
    case when (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
                where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update') = 'a585ac769d92cd1f2aba0c4cf49ca83a|O'
              and (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
                where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') = 'fd430e026c17ce4ca3ed0d74b48ba0e1|O' then ''
         else E'FALLO C3: los disparadores de tabla de disponibilidad no son los del 2.8 (definición o estado)\n' end);
  -- C4. Lo que esta migración no toca: la pieza del 2.8, el núcleo del alta y el verificador, con sus huellas.
  perform pg_temp.reg('C4 la pieza del 2.8, el núcleo del alta y el verificador intactos',
    case when (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza28)
                = '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f'
              -- 22/10/2026 (C3 ronda 2): orden definitivo 2.11 → 2.13: el núcleo del alta es el que deja el 2.11 (antes 2fe5fdac…/8d598eb4…, el del 2.8).
              and (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo)
                = '9f26e7f962d21170b2c35e113442d026/9c09cca28fd81fa29f16133b2b57c328'
              and (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure)
                = 'cece9dd168c9beea935af2e05895e32a' then ''
         else E'FALLO C4: cambió la pieza del 2.8, el núcleo del alta o el verificador\n' end);
  -- C5. El disparador llama a la pieza del 2.8 tres veces y a la del 2.13 dos veces si existe (ninguna si no).
  v_src := (select p.prosrc from pg_proc p where p.oid = v_disp);
  v_n := (length(v_src) - length(replace(v_src, 'private.juicio_lead_vivo_por_numero(', ''))) / length('private.juicio_lead_vivo_por_numero(');
  perform pg_temp.reg('C5 el disparador: tres llamadas a la pieza del 2.8; dos a la del 2.13 si existe (ninguna si no)',
    case when (length(v_src) - length(replace(v_src, 'private.juicio_cliente_convertido(', ''))) / length('private.juicio_cliente_convertido(') = 3
              and v_n = case when v_pieza is null then 0 else 2 end then ''
         else format(E'FALLO C5: llamadas a la pieza del 2.13 en el disparador: %s (pieza %s)\n', v_n, case when v_pieza is null then 'ausente' else 'presente' end) end);
  perform pg_temp.medida(format('C6 huellas: disparador md5(prosrc)=%s · md5(definición)=%s · comentario %s · pieza %s',
    (select md5(p.prosrc) from pg_proc p where p.oid = v_disp), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_disp),
    (select md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) from pg_proc p where p.oid = v_disp),
    coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza), 'ausente')));

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ───────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('Z', format(E'FALLO Z: algo de lo escrito no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
  end;

  -- ── Veredicto, y rollback SIEMPRE ───────────────────────────────────────────────────────────────────────────────
  raise exception E'ENSAYO %:\n%\n%\n%(rollback a propósito — nada queda escrito)',
    case when current_setting('ensayo.fallos')::integer = 0 then format('VERDE — 0 fallos (%s comprobaciones)', current_setting('ensayo.casos'))
         else format('ROJO — %s fallo(s) de %s comprobaciones', current_setting('ensayo.fallos'), current_setting('ensayo.casos')) end,
    current_setting('ensayo.informe'),
    current_setting('ensayo.medidas'),
    current_setting('ensayo.oks');
end;
$ensayo$;
