-- ORÁCULO de «Reactivar una ficha retirada (o un contacto de la base) también reconoce al cliente» (bloque 2.11) — se ejecuta en
-- el LABORATORIO (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisiones D-42 y D-55 de Miguel, 09/10/2026; plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.11; la regla del cliente es
-- la del 2.7 y el 2.8: D-22, D-25, D-27, D-30): cuando el CRM va a REACTIVAR un lead, lo que ese lead CONSERVA —su teléfono, su
-- teléfono alternativo y su DNI— no puede ser de un cliente ya convertido (un lead en etapa `convertido`, activo o retirado), sin
-- contarlo a él. Si lo es, no se reactiva ni se escribe nada y se responde como el alta: «ya es cliente de X» (el veredicto del alta,
-- mismo formato y mismos datos; D-29). Dos puertas:
--   · A. EL ALTA que reactiva una ficha RETIRADA (regla del 2.4, `crm.crear_lead_si_disponible` → núcleo
--     `private.alta_reactivar_retirado`; también por la puerta del documento `crm.crear_lead_documento_fn`): el alta RESPONDE el
--     veredicto (como hoy cuando lo tecleado es de un cliente). Casos R2 (el alternativo conservado es el teléfono de un cliente) y R3b
--     (el teléfono conservado es de un cliente RETIRADO), medidos en la ronda 3 del 2.8, y los que pidió el auditor (R2 con el cliente
--     retirado; R2 alternativo contra alternativo).
--   · B. LA BASE PARA GESTIÓN que reactiva un contacto (D-55: `crm.reactivar_lead_base_v2`, hallazgo H-1 del 2.9; y por el mismo
--     núcleo `private.base_gestion_reactivar_capital_core`, la puerta sin capital `crm.reactivar_lead_base` y el intento «agendó
--     cita» de `crm.registrar_intento_base_v2`): estas puertas avisan con errores, así que el veredicto viaja en el MISMO `P0481`
--     «Contacto no disponible» con el que la edición y el INSERT ya responden esa regla (2.8), con el veredicto del alta en el
--     detalle.
--   · También en el REINTENTO del 2.4 (mismo p_id, tras un segundo retiro) de una ficha que CONSERVA el contacto de un cliente (A9;
--     D-61 de Miguel: «al reactivar», D-42 al pie de la letra). Con esto cambian los casos 8a y 11i del oráculo del 2.7, que fijaban lo
--     de antes: al integrar (grupo C) se actualizan sus esperados; aquí no se tocan.
--   · NO CAMBIA: las fichas y los contactos sin coincidencia; el reintento con el alternativo TECLEADO de un cliente (R1 del 2.8: lo
--     tecleado en un reintento sigue fuera de la regla 1b); lo que hoy ya se para (R3a: el cliente ACTIVO por lo conservado; un lead
--     vivo por lo conservado, «tomado»); el ámbito, el No contactar, el replay, los intentos que no reactivan y las demás puertas
--     (reabrir, tomar un lead libre: se MIDEN, sección H; van al bloque 2.16, D-62, que reutiliza la pieza).
-- Hoy (sin la migración) el núcleo del alta solo pasa lo conservado por `private.alta_reactivar_bloqueo_conservado` (el verificador,
-- que excluye a los convertidos, y los leads ACTIVOS: no mira el alternativo ni a los convertidos retirados) y la reactivación de la
-- base no mira nada ⇒ el lead vuelve activo con el contacto de un cliente: un SEGUNDO lead del cliente.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (sin su `begin;`/`commit;`) dentro de una
-- única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y entonces TIENE que salir ROJO porque la ficha o
-- el contacto se REACTIVAN con el contacto de un cliente (o porque la pieza nueva no existe), nunca por un error de montaje.
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT, fijada en las DOS formas
-- (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de rol con `set role` (llamar bajo `set role` a una función sin
-- EXECUTE tumba el Postgres de esta imagen): todo corre como `postgres`; las puertas son DEFINER y resuelven rol y ámbito con
-- `auth.uid()`. Actores reales del banco (`PASO08 …`), OBLIGATORIOS con su rol y su equipo exactos (VEND1 y VEND2 bajo SUP1, VEND3
-- bajo SUP2): sin ellos, `ENSAYO ABORTADO`.
--
-- Cómo nacen las cosas (como en los oráculos del 2.4, 2.7, 2.8 y 2.9): las fichas, por el ALTA REAL y retiradas como lo hace Gerencia
-- hoy; los clientes CON PERSONA, por la conversión REAL del formulario compartido; los clientes SIN PERSONA y los duplicados
-- heredados (una ficha que conserva el teléfono de un cliente, un cliente con el contacto de un lead que ya existía), sembrados con
-- los disparadores apagados (estado heredado declarado en cada caso); los contactos de base, por la carga real
-- (`crm.cargar_base_lote`); un descarte de cartera de hace 40 días, sembrado (como en el 2.9).
--
-- La REFERENCIA de cada caso es lo que responde HOY el alta (`crm.crear_lead_si_disponible`) cuando se teclea el contacto del cliente:
-- el veredicto del alta, con su formato y sus datos (D-29). El caso exige EXACTAMENTE ese veredicto.
--
-- RONDA 3 (10/10/2026; Codex r1): los rechazos de la base que van ANTES de la regla (B12 el ámbito, B13 el No contactar, B15 el estado)
-- exigen además el detalle del error VACÍO (un veredicto en el detalle filtraría el asesor a quien no ve el lead: mutante M18); B16 y los
-- casos que reactivan como hoy (B10, B11) comprueban la fila de la operación en crm.actividades (el intento con su resultado; la
-- reactivación), y los rechazos de la base (B1–B9) que esa fila NO quedó. El orden candado → juicio de la pieza lo prueba `espera.sh`
-- (modo «orden», mutante M17), no este oráculo.

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

-- Contactos del ensayo: un bloque propio (+51 924 11xxxx / 7531xxxx) que el montaje exige LIBRE (el del 2.4 es 92400/7524; el del
-- 2.7, 92407/7527; el del 2.8, 92408/7528; el del 2.9, 92409/7529).
create function pg_temp.tel(n integer) returns text language sql immutable as $$ select '92411' || lpad(n::text, 4, '0') $$;
create function pg_temp.teln(n integer) returns text language sql immutable as $$ select '+51' || pg_temp.tel(n) $$;
create function pg_temp.dni(n integer) returns text language sql immutable as $$ select '7531' || lpad(n::text, 4, '0') $$;

create temp table ens_actores (nombre text primary key, id uuid not null);

create function pg_temp.actor(p_nombre text) returns uuid language sql as $$
  select a.id from ens_actores a where a.nombre = p_nombre
$$;

-- Foto COMPLETA de una ficha (para «sigue intacta»).
create function pg_temp.ficha(p_id uuid) returns jsonb language sql as $$
  select to_jsonb(l) from crm.leads l where l.id = p_id
$$;

-- Huella de ESCRITURA (la del oráculo del 2.7 y del 2.8): el contenido entero de crm.leads, crm.actividades y crm.lead_asignaciones
-- (md5 de las filas en orden de id) y el número de filas de tareas, personas, documentos y ciclos SLA.
create function pg_temp.huella_escritura() returns text language sql as $$
  select concat_ws(',',
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '')) from crm.leads l),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from crm.actividades a),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) from crm.lead_asignaciones e),
    (select count(*) from crm.tareas), (select count(*) from crm.inversionistas), (select count(*) from crm.inversionista_identificadores),
    (select count(*) from crm.lead_sla_ciclos))
$$;

-- Cuántos OTROS leads ACTIVOS llevan alguno de los contactos del cliente (su teléfono, su alternativo —en cualquiera de los dos
-- campos y en el alternativo sin validar, normalizado— o su DNI): el «segundo lead del cliente» que mide el ROJO (la del 2.8).
create function pg_temp.otros_activos_del_cliente(p_cliente uuid) returns bigint language sql as $$
  select count(*)
  from crm.leads c
  join crm.leads l on l.id <> c.id and l.activo
  where c.id = p_cliente
    and (l.telefono = c.telefono or l.telefono = c.telefono_alternativo
         or l.telefono_alternativo = c.telefono or l.telefono_alternativo = c.telefono_alternativo
         or private.normalizar_telefono(l.telefono_alternativo_crudo) in (c.telefono, c.telefono_alternativo)
         or (c.dni is not null and l.dni = c.dni))
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

-- Alta por la puerta del DOCUMENTO (con DNI), como el actor.
create function pg_temp.alta_doc(p_actor uuid, p_id uuid, p_nombre text, p_tel text, p_dni text)
returns text language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.crear_lead_documento_fn(jsonb_build_object('id', p_id, 'nombre_completo', p_nombre, 'telefono', p_tel,
           'origen', 'formulario', 'monto_estimado', 5000, 'moneda', 'PEN'), 'DNI', p_dni);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
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

-- Una base de origen archivo, por la puerta real como el actor. Aborta si no nace.
create function pg_temp.base(p_actor uuid, p_nombre text, p_supervisor uuid default null) returns uuid language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  begin
    perform pg_temp.sesion(p_actor);
    v_r := crm.crear_base(gen_random_uuid(), p_nombre, 'archivo', p_supervisor, 'ensayo-2-11.csv');
    perform pg_temp.sesion(null);
  exception when others then
    get stacked diagnostics v_det = pg_exception_detail;
    perform pg_temp.sesion(null);
    raise exception 'ENSAYO ABORTADO: no se pudo crear la base % (% % %)', p_nombre, sqlstate, sqlerrm, coalesce(v_det, '');
  end;
  if (v_r ->> 'base_id') is null then
    raise exception 'ENSAYO ABORTADO: la base % no devolvió su id (%)', p_nombre, v_r;
  end if;
  return (v_r ->> 'base_id')::uuid;
end;
$f$;

-- Un lote de la carga de bases, como el actor.
create function pg_temp.cargar(p_actor uuid, p_base uuid, p_filas jsonb) returns text language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.cargar_base_lote(gen_random_uuid(), p_base, p_filas);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- Las puertas de la BASE PARA GESTIÓN que reactivan (o no), como el actor: `v2` (crm.reactivar_lead_base_v2, con capital), `v1`
-- (crm.reactivar_lead_base, sin capital), `cita` (crm.registrar_intento_base_v2 «agendó cita», que reactiva) y `no_contesto` (el
-- mismo intento con un resultado que NO reactiva).
create function pg_temp.por_la_base(p_via text, p_actor uuid, p_op uuid, p_lead uuid) returns text language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  if p_via not in ('v2', 'v1', 'cita', 'no_contesto') then
    raise exception 'ENSAYO ABORTADO: vía de la base desconocida %', p_via;
  end if;
  begin
    perform pg_temp.sesion(p_actor);
    if p_via = 'v2' then
      v_r := crm.reactivar_lead_base_v2(p_op, p_lead, 'ensayo del bloque 2.11', 5000, 'PEN');
    elsif p_via = 'v1' then
      v_r := crm.reactivar_lead_base(p_op, p_lead, 'ensayo del bloque 2.11');
    elsif p_via = 'cita' then
      v_r := crm.registrar_intento_base_v2(p_op, p_lead, 'agendo_reunion', 'ensayo del bloque 2.11', null, 5000, 'PEN');
    else
      v_r := crm.registrar_intento_base_v2(p_op, p_lead, 'no_contesto', 'ensayo del bloque 2.11', null, null, null);
    end if;
    perform pg_temp.sesion(null);
    return 'ok|' || v_r::text;
  exception when others then
    get stacked diagnostics v_det = pg_exception_detail;
    perform pg_temp.sesion(null);
    return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
  end;
end;
$f$;

-- ── Montaje de fichas, clientes y contactos ─────────────────────────────────────────────────────────────────────────

-- Un lead NUEVO por la puerta real, a nombre del actor, con su alternativo si se da (aborta si no nace).
create function pg_temp.lead_nuevo(p_actor uuid, p_n integer, p_nombre text, p_dni text default null, p_alt text default null)
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_res text;
begin
  v_res := pg_temp.alta(p_actor, v_id, p_nombre, pg_temp.tel(p_n), p_dni, p_alt);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear por la puerta real el lead % (%)', p_n, v_res;
  end if;
  if (select l.telefono_alternativo from crm.leads l where l.id = v_id) is distinct from p_alt then
    raise exception 'ENSAYO ABORTADO: el lead % no quedó con el alternativo pedido %', p_n, p_alt;
  end if;
  return v_id;
end;
$f$;

-- Una FICHA RETIRADA: alta real a nombre de p_actor (con su DNI y su alternativo, si se dan) y retirada por Gerencia. Exige que quede
-- retirada, sin convertir, sin veto, sin persona y con EXACTAMENTE el alternativo pedido.
create function pg_temp.ficha_retirada(p_actor uuid, p_n integer, p_nombre text, p_dni text, p_alt text) returns uuid
language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_res text;
begin
  v_res := pg_temp.alta(p_actor, v_id, p_nombre, pg_temp.tel(p_n), p_dni, p_alt);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear por la puerta real la ficha % (%)', p_n, v_res;
  end if;
  if pg_temp.retirar(pg_temp.actor('GERENCIA'), v_id) <> '1' then
    raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar la ficha %', p_n;
  end if;
  if (select l.activo or l.etapa = 'convertido' or l.no_contactar or l.inversionista_id is not null
             or l.telefono_alternativo is distinct from p_alt
        from crm.leads l where l.id = v_id) then
    raise exception 'ENSAYO ABORTADO: la ficha % no quedó retirada, sin convertir, sin veto, sin persona y con el alternativo %', p_n, p_alt;
  end if;
  return v_id;
end;
$f$;

-- DUPLICADO HEREDADO (estado declarado): la ficha pasa a conservar el TELÉFONO p_tel, con los disparadores apagados (como R3 del 2.8).
create function pg_temp.sembrar_telefono(p_lead uuid, p_tel text) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  update crm.leads set telefono = p_tel where id = p_lead;
  set local session_replication_role = origin;
  if (select l.telefono from crm.leads l where l.id = p_lead) is distinct from p_tel then
    raise exception 'ENSAYO ABORTADO: la ficha % no quedó con el teléfono %', p_lead, p_tel;
  end if;
end;
$f$;

-- CLIENTE CON PERSONA por la conversión REAL (formulario compartido, cooperativa: sin cuenta del Portal). Con p_alt, el alta lleva ese
-- teléfono alternativo. Devuelve el id del lead convertido (activo, enlazado a su persona). Como en el oráculo del 2.8 y del 2.9.
create function pg_temp.convertir_real(p_n integer, p_nombre text, p_actor uuid, p_alt text default null)
returns uuid language plpgsql as $f$
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
             'plazo_meses', 12, 'tasa_anual', 15, 'numero_transaccion', 'ENS211-' || left(v_sol::text, 8),
             'referencia', 'ENSAYO 2.11 SINTETICA', 'evidencia', jsonb_build_object('ruta', v_ruta)));
    perform pg_temp.sesion(null);
    -- El comprobante: objeto de Storage sintético, sin sesión (el mismo fixture que el banco sube por la API de Storage).
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
  if (select i.perfil_id from crm.inversionistas i where i.id = v_per) is not null
     or exists (select 1 from public.perfiles p where p.rol = 'cliente'
                  and private.normalizar_telefono(p.telefono) in (pg_temp.teln(p_n), p_alt)) then
    raise exception 'ENSAYO ABORTADO: el cliente % tiene cuenta del Portal (el caso exige que no la tenga)', p_n;
  end if;
  return v_lead;
end;
$f$;

-- CONVERSIÓN SEMBRADA (sin persona, estado heredado) de un lead nacido por la puerta real, como 3d/B1 del 2.4, 4a del 2.7, el 2.8 y el 2.9.
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

-- CLIENTE SIN PERSONA: alta real a nombre de p_actor con su DNI y el alternativo p_alt, y conversión sembrada (retirado si p_retirar).
create function pg_temp.cliente_sin_persona(p_n integer, p_nombre text, p_actor uuid, p_retirar boolean, p_alt text)
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_res text;
begin
  v_res := pg_temp.alta(p_actor, v_id, p_nombre, pg_temp.tel(p_n), pg_temp.dni(p_n), p_alt);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado'
     or (select l.inversionista_id from crm.leads l where l.id = v_id) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del cliente sin persona % (%)', p_n, v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_id, p_retirar);
  if (select l.telefono_alternativo from crm.leads l where l.id = v_id) is distinct from p_alt then
    raise exception 'ENSAYO ABORTADO: el cliente sin persona % no quedó con el alternativo pedido %', p_n, p_alt;
  end if;
  return v_id;
end;
$f$;

-- Un lead SEMBRADO sin disparadores (estado heredado: un cliente sin persona que llegó DESPUÉS con el contacto de una ficha o de un
-- contacto que ya existía), con su ciclo SLA como lo dejaría el alta (el del 2.8). p_etapa 'convertido' (convertido hace 5 días).
-- Dueño: p_vendedor (VEND1 si no se da). p_dni y p_alt: su DNI y su teléfono alternativo.
create function pg_temp.sembrado(p_n integer, p_nombre text, p_activo boolean, p_etapa text default 'contactado',
                                 p_dni text default null, p_vendedor uuid default null, p_alt text default null)
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_dueno uuid := coalesce(p_vendedor, pg_temp.actor('VEND1'));
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, dni, origen, etapa, convertido_en, monto_estimado, moneda,
                         vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual, ciclo_actual, creado_en, actualizado_en,
                         sla_global_iniciado_en)
  values (v_id, p_nombre, pg_temp.teln(p_n), p_alt, p_dni, 'formulario', p_etapa,
          case when p_etapa = 'convertido' then clock_timestamp() - interval '5 days' end,
          1000, 'PEN', v_dueno, null, p_activo, v_dueno, true, 1,
          now() - interval '30 days', now() - interval '10 days', now() - interval '30 days');
  insert into crm.lead_sla_ciclos (lead_id, ciclo_n, politica_id, iniciado_en, primera_gestion_limite_en, primer_contacto_limite_en)
  select v_id, 1, p.id, now() - interval '30 days',
         now() - interval '30 days' + p.primera_gestion_minutos * interval '1 minute',
         now() - interval '30 days' + p.primer_contacto_minutos * interval '1 minute'
  from crm.sla_politicas p
  where p.id = coalesce(private.sla_politica_vigente(now() - interval '30 days'), private.sla_politica_vigente(now()));
  set local session_replication_role = origin;
  if not exists (select 1 from crm.lead_sla_ciclos c where c.lead_id = v_id)
     or (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = v_id) is distinct from p_etapa || '|' || p_activo::text then
    raise exception 'ENSAYO ABORTADO: el lead sembrado % no quedó como se pidió (o sin ciclo SLA)', p_n;
  end if;
  return v_id;
end;
$f$;

-- DESCARTE SEMBRADO (estado heredado declarado) de un lead nacido por la puerta real: descartado sin interés hace 40 días (fuera del
-- enfriamiento), con los disparadores apagados; su episodio se cierra como «descartado» a la hora de la SENTENCIA del ensayo
-- (`statement_timestamp()`, la misma con la que lo abrió el alta dentro de este bloque): así el episodio que abra una reapertura en el
-- mismo bloque no se solapa con él (`lead_asignaciones_sin_solape`; con `clock_timestamp()`, como en el 2.9, chocaría, y con `now()`
-- quedaría antes de su apertura: medido en los dos primeros ROJO, `salidas/trabajo/rojo/rojo1|2`).
create function pg_temp.descartar_sembrado(p_lead uuid) returns void language plpgsql as $f$
declare v_hace40 timestamptz := clock_timestamp() - interval '40 days'; v_ahora timestamptz := statement_timestamp(); v_cierra uuid;
begin
  v_cierra := (select coalesce(l.vendedor_id, l.asignado_supervisor_id, pg_temp.actor('GERENCIA')) from crm.leads l where l.id = p_lead);
  set local session_replication_role = replica;
  update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes', descartado_en = v_hace40, descartado_por = v_cierra
   where id = p_lead;
  update crm.lead_asignaciones set finalizado_en = v_ahora, finalizado_por = v_cierra, motivo_cierre = 'descartado',
         resultado = 'descartado', resultado_en = v_ahora, motivo_descarte_cierre = 'sin_interes'
   where lead_id = p_lead and finalizado_en is null;
  update crm.lead_sla_etapas set finalizado_en = v_ahora, motivo_cierre = 'cierre_terminal' where lead_id = p_lead and finalizado_en is null;
  set local session_replication_role = origin;
  if (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = p_lead) is distinct from 'descartado|true' then
    raise exception 'ENSAYO ABORTADO: el descarte sembrado del lead % no quedó como se pidió', p_lead;
  end if;
end;
$f$;

-- Un CONTACTO DE BASE por la carga real (una fila con su teléfono y su DNI si se da): nace DORMIDO (descartado, motivo base_cargada,
-- activo). Aborta si no.
create function pg_temp.contacto(p_actor uuid, p_base uuid, p_n integer, p_dni text default null) returns uuid language plpgsql as $f$
declare v_res text; v_id uuid;
begin
  v_res := pg_temp.cargar(p_actor, p_base, jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('fila', 1,
             'nombre', 'CONTACTO ' || p_n, 'telefono', pg_temp.teln(p_n), 'dni', p_dni))));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb #>> '{filas,0,veredicto}') is distinct from 'cargada' then
    raise exception 'ENSAYO ABORTADO: el contacto de base % no se cargó (%)', p_n, v_res;
  end if;
  select l.id into v_id from crm.leads l where l.telefono = pg_temp.teln(p_n) and l.origen = 'base_cargada';
  if v_id is null
     or (select l.etapa || '|' || l.activo::text || '|' || coalesce(l.motivo_descarte, '-') || '|' || coalesce(l.dni, '-')
           from crm.leads l where l.id = v_id) is distinct from 'descartado|true|base_cargada|' || coalesce(p_dni, '-') then
    raise exception 'ENSAYO ABORTADO: el contacto de base % no nació dormido (descartado, activo, motivo base_cargada, con su DNI)', p_n;
  end if;
  return v_id;
end;
$f$;

-- LA REFERENCIA: lo que responde HOY el alta (VEND2, un id nuevo) cuando se teclea el contacto del cliente. Tiene que ser «ya es
-- cliente» (o «no contactar») y no escribir nada; si no, el caso no mediría la regla y el ensayo aborta. Se anota también lo que
-- responde la regla misma (la pieza del 2.8, llamada como postgres): el formato del alta es el suyo.
create function pg_temp.referencia(p_caso text, p_tel text, p_dni text default null) returns jsonb language plpgsql as $f$
declare v_h text := pg_temp.huella_escritura(); v_res text; v_r jsonb; v_pieza jsonb;
begin
  v_res := pg_temp.alta(pg_temp.actor('VEND2'), gen_random_uuid(), 'REFERENCIA ' || p_caso, p_tel, p_dni);
  v_r := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  if v_r is null or coalesce(v_r ->> 'estado', '') not in ('ya_es_cliente', 'no_contactar')
     or pg_temp.huella_escritura() is distinct from v_h then
    raise exception 'ENSAYO ABORTADO: %: la referencia (lo que responde HOY el alta al teclear el contacto del cliente) no es «ya es cliente» sin escribir nada (%)', p_caso, v_res;
  end if;
  v_pieza := private.juicio_cliente_convertido(private.normalizar_telefono(p_tel), null, p_dni, null);
  perform pg_temp.medida(format('%s · referencia: el alta con el contacto del cliente tecleado (%s%s) → %s%s', p_caso, p_tel,
    coalesce(', DNI ' || p_dni, ''), v_r, case when v_pieza is distinct from v_r then format(' (¡la regla sola dice %s!)', v_pieza) else ' (= la regla del cliente)' end));
  return v_r;
end;
$f$;

-- ── Jueces ──────────────────────────────────────────────────────────────────────────────────────────────────────────

-- A · Una reactivación por el ALTA que tiene que BLOQUEARSE: el alta (o la puerta del documento) con lo tecleado responde
-- EXACTAMENTE p_esperado, la ficha queda intacta byte a byte, nada se escribe (huella) y ningún lead ACTIVO más lleva los contactos
-- del cliente. Si la ficha se REACTIVA, el fallo dice el defecto.
create function pg_temp.bloqueo_alta(p_caso text, p_via text, p_actor uuid, p_pid uuid, p_tel text, p_dni text, p_ficha uuid,
                                     p_esperado jsonb, p_cliente uuid)
returns void language plpgsql as $f$
declare
  v_fa jsonb := pg_temp.ficha(p_ficha);
  v_h text := pg_temp.huella_escritura();
  v_n bigint := pg_temp.otros_activos_del_cliente(p_cliente);
  v_id uuid := coalesce(p_pid, gen_random_uuid());
  v_res text; v_r jsonb; v_m text[] := '{}';
begin
  v_res := case when p_via = 'doc' then pg_temp.alta_doc(p_actor, v_id, 'REINGRESO ' || split_part(p_caso, '-', 1), p_tel, p_dni)
                else pg_temp.alta(p_actor, v_id, 'REINGRESO ' || split_part(p_caso, '-', 1), p_tel, p_dni) end;
  perform pg_temp.medida(format('%s · %s (teléfono %s%s) → %s · la ficha queda %s · leads ACTIVOS con los contactos del cliente: %s (antes %s)',
    p_caso, case when p_via = 'doc' then 'alta por documento' else 'alta' end, p_tel, coalesce(', DNI ' || p_dni, ''), v_res,
    (select jsonb_build_object('activo', l.activo, 'etapa', l.etapa, 'telefono', l.telefono, 'alternativo', l.telefono_alternativo, 'dni', l.dni)
       from crm.leads l where l.id = p_ficha),
    pg_temp.otros_activos_del_cliente(p_cliente), v_n));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: el alta falló (%s) en vez de responder %s\n', p_caso, v_res, p_esperado));
    return;
  end if;
  v_r := substr(v_res, 4)::jsonb;
  if v_r ->> 'estado' = 'reutilizado' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la ficha RETIRADA se REACTIVÓ (%s) conservando el contacto de un cliente ya convertido → %s lead(s) ACTIVO(s) con los contactos del cliente (antes %s); se esperaba EXACTAMENTE %s\n',
      p_caso, v_r, pg_temp.otros_activos_del_cliente(p_cliente), v_n, p_esperado));
    return;
  end if;
  if v_r is distinct from p_esperado then
    v_m := array_append(v_m, format('respondió %s, se esperaba EXACTAMENTE %s', v_r, p_esperado));
  end if;
  if pg_temp.ficha(p_ficha) is distinct from v_fa then
    v_m := array_append(v_m, 'la ficha cambió');
  end if;
  if pg_temp.huella_escritura() is distinct from v_h then
    v_m := array_append(v_m, 'se escribió algo (huella de escritura distinta)');
  end if;
  if pg_temp.otros_activos_del_cliente(p_cliente) <> v_n then
    v_m := array_append(v_m, 'hay más leads ACTIVOS con los contactos del cliente');
  end if;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- A · Una reactivación por el ALTA que tiene que ENTRAR, como hoy: `reutilizado` con la ficha, que vuelve activa conservando su
-- alternativo (p_alt_conservado).
create function pg_temp.reactiva_alta(p_caso text, p_actor uuid, p_pid uuid, p_tel text, p_dni text, p_alt text, p_ficha uuid,
                                      p_alt_conservado text)
returns void language plpgsql as $f$
declare v_res text; v_r jsonb; v_m text[] := '{}';
begin
  v_res := pg_temp.alta(p_actor, coalesce(p_pid, gen_random_uuid()), 'REINGRESO ' || split_part(p_caso, '-', 1), p_tel, p_dni, p_alt);
  perform pg_temp.medida(format('%s · alta (teléfono %s%s%s) → %s', p_caso, p_tel, coalesce(', DNI ' || p_dni, ''),
    coalesce(', alternativo ' || p_alt, ''), v_res));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: el alta falló (%s) y hoy reactiva la ficha\n', p_caso, v_res));
    return;
  end if;
  v_r := substr(v_res, 4)::jsonb;
  if v_r ->> 'estado' is distinct from 'reutilizado' or (v_r ->> 'lead_id') is distinct from p_ficha::text then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la ficha NO se reactivó (%s) y hoy se reactiva: la regla bloquea una ficha que no conserva nada de un cliente\n', p_caso, v_r));
    return;
  end if;
  if (select not l.activo from crm.leads l where l.id = p_ficha) then
    v_m := array_append(v_m, 'la ficha no quedó activa');
  end if;
  if (select l.telefono_alternativo from crm.leads l where l.id = p_ficha) is distinct from p_alt_conservado then
    v_m := array_append(v_m, format('la ficha no conservó su alternativo %s', p_alt_conservado));
  end if;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- B · Una reactivación por la BASE que tiene que BLOQUEARSE: `P0481` «Contacto no disponible» con EXACTAMENTE p_esperado en el
-- detalle, el lead intacto byte a byte, nada escrito (huella) y ningún lead ACTIVO más con los contactos del cliente. Si la puerta
-- ACEPTA, el fallo dice el defecto.
create function pg_temp.bloqueo_base(p_caso text, p_via text, p_actor uuid, p_lead uuid, p_esperado jsonb, p_cliente uuid)
returns void language plpgsql as $f$
declare
  v_fa jsonb := pg_temp.ficha(p_lead);
  v_h text := pg_temp.huella_escritura();
  v_n bigint := pg_temp.otros_activos_del_cliente(p_cliente);
  v_op uuid := gen_random_uuid();
  v_res text; e record; v_m text[] := '{}';
begin
  v_res := pg_temp.por_la_base(p_via, p_actor, v_op, p_lead);
  perform pg_temp.medida(format('%s · %s → %s · el lead queda %s · leads ACTIVOS con los contactos del cliente: %s (antes %s)',
    p_caso, p_via, v_res,
    (select jsonb_build_object('activo', l.activo, 'etapa', l.etapa, 'telefono', l.telefono, 'alternativo', l.telefono_alternativo, 'dni', l.dni)
       from crm.leads l where l.id = p_lead),
    pg_temp.otros_activos_del_cliente(p_cliente), v_n));
  if v_res like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la reactivación por la base (%s) se ACEPTÓ (%s) → el lead volvió a la cartera (%s) con el contacto de un cliente ya convertido: %s lead(s) ACTIVO(s) con los contactos del cliente (antes %s); se esperaba P0481 «Contacto no disponible» con %s\n',
      p_caso, p_via, substr(v_res, 4), (select l.etapa from crm.leads l where l.id = p_lead), pg_temp.otros_activos_del_cliente(p_cliente), v_n, p_esperado));
    return;
  end if;
  e := pg_temp.error_de(v_res);
  if e.estado is distinct from 'P0481' or e.mensaje is distinct from 'Contacto no disponible'
     or pg_temp.a_jsonb(e.detalle) is distinct from p_esperado then
    v_m := array_append(v_m, format('rechazó con %s, se esperaba P0481 «Contacto no disponible» con EXACTAMENTE %s en el detalle', v_res, p_esperado));
  end if;
  if pg_temp.ficha(p_lead) is distinct from v_fa then
    v_m := array_append(v_m, 'el lead cambió');
  end if;
  if pg_temp.huella_escritura() is distinct from v_h then
    v_m := array_append(v_m, 'se escribió algo (huella de escritura distinta)');
  end if;
  if pg_temp.otros_activos_del_cliente(p_cliente) <> v_n then
    v_m := array_append(v_m, 'hay más leads ACTIVOS con los contactos del cliente');
  end if;
  -- Ronda 3 (Codex r1): la tabla de intentos y reactivaciones, directamente: la operación rechazada no dejó su fila en crm.actividades
  -- (ni el intento de «agendó cita» ni ninguna reactivación de este lead).
  if exists (select 1 from crm.actividades a
              where a.id = v_op or (a.lead_id = p_lead and a.metadata ->> 'evento' in ('intento_base', 'reactivacion_base'))) then
    v_m := array_append(v_m, 'quedó registrado un intento o una reactivación de este lead en crm.actividades');
  end if;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- B · Una puerta de la base que tiene que hacer LO DE HOY: `v2`/`v1`/`cita` reactivan (el lead vuelve a la cartera en
-- «contactado»); `no_contesto` registra el intento y el lead sigue en la base (descartado).
create function pg_temp.reactiva_base(p_caso text, p_via text, p_actor uuid, p_lead uuid) returns void language plpgsql as $f$
declare v_op uuid := gen_random_uuid(); v_res text; v_r jsonb; v_et text; v_fila text;
begin
  v_res := pg_temp.por_la_base(p_via, p_actor, v_op, p_lead);
  v_et := (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = p_lead);
  -- Ronda 3 (Codex r1): la fila de la operación en crm.actividades, directamente: el intento con su resultado o la reactivación.
  v_fila := (select a.metadata ->> 'evento' || ':' || coalesce(a.metadata ->> 'resultado', '-') from crm.actividades a
              where a.id = v_op and a.lead_id = p_lead);
  perform pg_temp.medida(format('%s · %s → %s · el lead queda %s · fila de la operación en crm.actividades: %s', p_caso, p_via, v_res, v_et,
    coalesce(v_fila, 'NINGUNA')));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la puerta %s rechazó (%s) y hoy %s\n', p_caso, p_via, v_res,
      case when p_via = 'no_contesto' then 'registra el intento' else 'reactiva el lead' end));
    return;
  end if;
  v_r := substr(v_res, 4)::jsonb;
  perform pg_temp.reg(p_caso, case
    when p_via = 'no_contesto' and v_et = 'descartado|true' and coalesce((v_r ->> 'reactivado')::boolean, true) = false
         and v_fila = 'intento_base:no_contesto' then ''
    when p_via in ('v2', 'v1') and v_et = 'contactado|true' and v_r ->> 'etapa' = 'contactado' and v_fila = 'reactivacion_base:-' then ''
    when p_via = 'cita' and v_et = 'contactado|true' and coalesce((v_r ->> 'reactivado')::boolean, false)
         and v_fila = 'intento_base:agendo_reunion' then ''
    else format(E'FALLO %s: la puerta %s respondió %s, el lead quedó %s y la fila de la operación en crm.actividades es %s (no es lo de hoy)\n',
                p_caso, p_via, v_r, v_et, coalesce(v_fila, 'NINGUNA')) end);
end;
$f$;

-- B · Una puerta de la base que tiene que rechazar COMO HOY, con el mismo error (código y texto) y SIN detalle (ronda 3, Codex r1: un
-- rechazo que va antes de la regla no puede llevar el veredicto —el asesor— en el detalle), sin tocar el lead ni escribir nada.
create function pg_temp.igual_base(p_caso text, p_via text, p_actor uuid, p_op uuid, p_lead uuid, p_estado text, p_mensaje text)
returns void language plpgsql as $f$
declare v_fa jsonb := pg_temp.ficha(p_lead); v_h text := pg_temp.huella_escritura(); v_res text; e record;
begin
  v_res := pg_temp.por_la_base(p_via, p_actor, p_op, p_lead);
  perform pg_temp.medida(format('%s · %s → %s', p_caso, p_via, v_res));
  e := pg_temp.error_de(v_res);
  perform pg_temp.reg(p_caso, case
    when v_res not like 'ok|%' and e.estado = p_estado and position(p_mensaje in e.mensaje) > 0 and e.detalle is null
         and pg_temp.ficha(p_lead) is not distinct from v_fa and pg_temp.huella_escritura() is not distinct from v_h then ''
    else format(E'FALLO %s: se esperaba %s «%s…» como hoy, SIN detalle (sin tocar el lead ni escribir nada) y llegó %s\n', p_caso, p_estado, p_mensaje, v_res) end);
end;
$f$;

-- K · Las CLAVES DE CANDADO que pide una llamada (la técnica del oráculo del 2.8, ronda 4). Son candados consultivos de transacción
-- (`pg_advisory_xact_lock(hashtextextended('avancecrm:lead:' || <clave>, 0))`, en `private.bloquear_contactos_lead`); en `pg_locks` la
-- clave de 64 bits es `classid << 32 | objid`. Se miran antes y después DENTRO de un bloque con EXCEPTION que se deshace al final.
create function pg_temp.claves_tomadas() returns bigint[] language sql as $$
  select coalesce(array_agg(((l.classid::text::bigint) << 32) | (l.objid::text::bigint) order by 1), '{}')
  from pg_locks l
  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 1
$$;
create function pg_temp.clave(p_tipo text, p_valor text) returns bigint language sql stable as $$
  select hashtextextended('avancecrm:lead:' || p_tipo || ':'
                          || case when p_tipo = 'telefono' then private.normalizar_telefono(p_valor) else btrim(p_valor) end, 0)
$$;
create function pg_temp.claves_de(p_sql text, out antes bigint[], out pedidas bigint[], out resultado text) language plpgsql as $f$
begin
  begin
    antes := pg_temp.claves_tomadas();
    execute p_sql;
    pedidas := array(select x from unnest(pg_temp.claves_tomadas()) x except select y from unnest(antes) y order by 1);
    resultado := 'ok';
    raise exception 'ENSAYO_CLAVES_DESHACER';
  exception when others then
    if sqlerrm <> 'ENSAYO_CLAVES_DESHACER' then
      resultado := sqlstate || '|' || sqlerrm;
    end if;
  end;
end;
$f$;

insert into ens_actores (nombre, id)
select n.nombre, p.id
from (values ('VEND1'), ('VEND2'), ('VEND3'), ('SUP1'), ('SUP2'), ('GERENCIA')) n(nombre)
join public.perfiles p on p.nombre_completo = 'PASO08 ' || n.nombre;

do $ensayo$
declare
  v_vend1 uuid; v_vend2 uuid; v_vend3 uuid; v_sup1 uuid; v_sup2 uuid; v_ger uuid;
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_nbase regprocedure := to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)');
  v_pieza regprocedure := to_regprocedure('private.juicio_cliente_conservado(uuid)');
  v_bs uuid; v_f uuid; v_c uuid; v_l uuid; v_pid uuid; v_op uuid;
  v_esp jsonb; v_r jsonb; v_res text; v_txt text; v_vis1 boolean; v_vis3 boolean; r record; v_esperadas bigint[]; v_ped bigint[];
begin
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.casos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ── Actores reales del banco (OBLIGATORIOS: sin ellos un caso se saltaría en silencio) ──────────────────────────────
  v_vend1 := pg_temp.actor('VEND1'); v_vend2 := pg_temp.actor('VEND2'); v_vend3 := pg_temp.actor('VEND3');
  v_sup1 := pg_temp.actor('SUP1'); v_sup2 := pg_temp.actor('SUP2'); v_ger := pg_temp.actor('GERENCIA');
  if v_vend1 is null or v_vend2 is null or v_vend3 is null or v_sup1 is null or v_sup2 is null or v_ger is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (vend1=%, vend2=%, vend3=%, sup1=%, sup2=%, gerencia=%)',
      v_vend1, v_vend2, v_vend3, v_sup1, v_sup2, v_ger;
  end if;
  perform pg_temp.sesion(v_sup1);
  v_vis1 := private.base_gestion_lead_visible(v_sup1, 'supervisor', v_vend1, null);
  v_vis3 := private.base_gestion_lead_visible(v_sup1, 'supervisor', v_vend3, null);
  perform pg_temp.sesion(null);
  if private.rol_crm(v_vend1) is distinct from 'vendedor' or private.rol_crm(v_vend2) is distinct from 'vendedor'
     or private.rol_crm(v_vend3) is distinct from 'vendedor' or private.rol_crm(v_sup1) is distinct from 'supervisor'
     or private.rol_crm(v_sup2) is distinct from 'supervisor' or private.rol_crm(v_ger) is distinct from 'gerencia'
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend1) is distinct from v_sup1
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend2) is distinct from v_sup1
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend3) is distinct from v_sup2
     or v_vis1 is not true or v_vis3 is not false then
    raise exception 'ENSAYO ABORTADO: un actor del banco no tiene el rol o el equipo esperado (vend1/vend2 bajo sup1 y visibles para él; vend3 bajo sup2 y fuera del ámbito de sup1; gerencia)';
  end if;
  -- El bloque de contactos del ensayo tiene que estar libre (teléfono, alternativo, DNI, perfiles y documentos).
  if exists (select 1 from crm.leads l where l.telefono like '+5192411%' or l.telefono_alternativo like '%92411%'
                                             or l.telefono_alternativo_crudo like '%92411%' or l.dni like '7531%')
     or exists (select 1 from public.perfiles p where p.telefono like '%92411%' or p.dni like '7531%')
     or exists (select 1 from crm.inversionista_identificadores d where d.documento_normalizado like '7531%'
                                                                   or d.documento_normalizado like '%92411%') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene contactos del bloque +51 924 11xxxx / 7531xxxx';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'ENSAYO ABORTADO: la identidad unificada (resolver_en_puertas) está apagada: el laboratorio no es el de producción';
  end if;
  -- El cubo de comprobantes de la conversión real (fixture del banco; si falta, vive y muere en esta transacción).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('f4-comprobantes', 'f4-comprobantes', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
  on conflict (id) do nothing;
  -- Medidas del punto de partida (no son casos).
  perform pg_temp.medida(format('T0 núcleo del alta md5(prosrc)=%s · md5(definición)=%s · núcleo de la base md5(prosrc)=%s · md5(definición)=%s · pieza nueva %s',
    (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo),
    (select md5(p.prosrc) from pg_proc p where p.oid = v_nbase), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nbase),
    coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza), 'AUSENTE')));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A. EL ALTA QUE REACTIVA UNA FICHA RETIRADA (regla del 2.4). La ficha nace por el alta real (VEND1) y la retira Gerencia; el
  --    cliente llega DESPUÉS con un contacto que la ficha conserva (sembrado: estado heredado). Reingresa VEND2 con lo que casa con
  --    la ficha. Debe responder EXACTAMENTE la referencia (el veredicto del alta) sin reactivar ni escribir nada.
  --    A1 R2 · A2 R2 con el cliente retirado (auditor) · A3 R2 alternativo contra alternativo (auditor) · A4 R3b · A5 R3b con persona ·
  --    A6 el DNI conservado · A14 por la puerta del documento · A9 un REINTENTO de una ficha que conserva el contacto de un cliente (D-61).
  --    Sin cambio: A7 R3a (lo para la regla de hoy) · A8 R1 (el reintento con el alternativo TECLEADO de un cliente) · A10 sin
  --    coincidencia · A11 el alternativo de un lead vivo que no es cliente · A12 un alternativo internacional que no es el móvil
  --    peruano de un cliente (comparación literal) · A13 lo conservado choca con un lead vivo: manda el «tomado» de hoy.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_f := pg_temp.ficha_retirada(v_vend1, 101, 'FICHA A1 RETIRADA CON ALTERNATIVO', pg_temp.dni(101), pg_temp.teln(100));
  v_c := pg_temp.sembrado(100, 'CLIENTE A1 CON EL ALTERNATIVO DE LA FICHA', true, 'convertido', null, v_vend3);
  v_esp := pg_temp.referencia('A1', pg_temp.tel(100));
  perform pg_temp.bloqueo_alta('A1-R2-el-alternativo-conservado-es-el-telefono-de-un-cliente-activo', 'alta', v_vend2, null,
    pg_temp.tel(101), pg_temp.dni(101), v_f, v_esp, v_c);

  v_f := pg_temp.ficha_retirada(v_vend1, 111, 'FICHA A2 RETIRADA CON ALTERNATIVO', pg_temp.dni(111), pg_temp.teln(110));
  v_c := pg_temp.sembrado(110, 'CLIENTE A2 RETIRADO CON EL ALTERNATIVO DE LA FICHA', false, 'convertido', null, v_vend3);
  v_esp := pg_temp.referencia('A2', pg_temp.tel(110));
  perform pg_temp.bloqueo_alta('A2-R2-el-alternativo-conservado-es-el-telefono-de-un-cliente-retirado', 'alta', v_vend2, null,
    pg_temp.tel(111), pg_temp.dni(111), v_f, v_esp, v_c);

  v_f := pg_temp.ficha_retirada(v_vend1, 121, 'FICHA A3 RETIRADA CON ALTERNATIVO', pg_temp.dni(121), pg_temp.teln(120));
  v_c := pg_temp.sembrado(122, 'CLIENTE A3 CON ESE ALTERNATIVO', true, 'convertido', null, v_vend3, pg_temp.teln(120));
  v_esp := pg_temp.referencia('A3', pg_temp.tel(122));
  perform pg_temp.bloqueo_alta('A3-R2-el-alternativo-conservado-es-el-alternativo-de-un-cliente', 'alta', v_vend2, null,
    pg_temp.tel(121), pg_temp.dni(121), v_f, v_esp, v_c);

  v_c := pg_temp.sembrado(130, 'CLIENTE A4 RETIRADO', false, 'convertido', null, v_vend3);
  v_esp := pg_temp.referencia('A4', pg_temp.tel(130));
  v_f := pg_temp.ficha_retirada(v_vend1, 131, 'FICHA A4 RETIRADA', pg_temp.dni(131), null);
  perform pg_temp.sembrar_telefono(v_f, pg_temp.teln(130));
  perform pg_temp.bloqueo_alta('A4-R3b-el-telefono-conservado-es-de-un-cliente-retirado (hallada por el DNI)', 'alta', v_vend2, null,
    pg_temp.tel(132), pg_temp.dni(131), v_f, v_esp, v_c);

  v_c := pg_temp.convertir_real(140, 'CLIENTE A5 CON PERSONA', v_vend1);
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente A5'; end if;
  v_esp := pg_temp.referencia('A5', pg_temp.tel(140));
  v_f := pg_temp.ficha_retirada(v_vend1, 141, 'FICHA A5 RETIRADA', pg_temp.dni(141), null);
  perform pg_temp.sembrar_telefono(v_f, pg_temp.teln(140));
  perform pg_temp.bloqueo_alta('A5-R3b-el-telefono-conservado-es-de-un-cliente-retirado-con-persona', 'alta', v_vend2, null,
    pg_temp.tel(142), pg_temp.dni(141), v_f, v_esp, v_c);

  v_f := pg_temp.ficha_retirada(v_vend1, 151, 'FICHA A6 RETIRADA CON EL DNI DE UN CLIENTE', pg_temp.dni(150), null);
  v_c := pg_temp.sembrado(152, 'CLIENTE A6 RETIRADO CON ESE DNI', false, 'convertido', pg_temp.dni(150), v_vend3);
  v_esp := pg_temp.referencia('A6', pg_temp.tel(153), pg_temp.dni(150));
  perform pg_temp.bloqueo_alta('A6-el-dni-conservado-es-de-un-cliente-retirado (tecleado solo el teléfono)', 'alta', v_vend2, null,
    pg_temp.tel(151), null, v_f, v_esp, v_c);

  v_f := pg_temp.ficha_retirada(v_vend1, 176, 'FICHA A14 RETIRADA CON ALTERNATIVO', pg_temp.dni(176), pg_temp.teln(175));
  v_c := pg_temp.sembrado(175, 'CLIENTE A14 CON EL ALTERNATIVO DE LA FICHA', true, 'convertido', null, v_vend3);
  v_esp := pg_temp.referencia('A14', pg_temp.tel(175));
  perform pg_temp.bloqueo_alta('A14-por-la-puerta-del-documento (DNI): el alternativo conservado es de un cliente', 'doc', v_vend2, null,
    pg_temp.tel(176), pg_temp.dni(176), v_f, v_esp, v_c);

  -- A9. Un REINTENTO del 2.4 (mismo p_id) sobre una ficha que se retiró otra vez y que CONSERVA el contacto de un cliente que llegó
  --     después: lo que se juzga es lo que ELLA conserva (D-61 de Miguel: «al reactivar», D-42 al pie de la letra), no lo tecleado (R1
  --     sigue igual: A8). Es lo que cambia los casos 8a y 11i del oráculo del 2.7 (al integrar se actualizan sus esperados). El mutante
  --     M9 (la regla solo en altas nuevas, lo que D-61 descartó) muere aquí.
  v_f := pg_temp.ficha_retirada(v_vend1, 181, 'FICHA A9 RETIRADA CON ALTERNATIVO', pg_temp.dni(181), pg_temp.teln(182));
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO A9', pg_temp.tel(181), pg_temp.dni(181));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id') is distinct from v_f::text then
    raise exception 'ENSAYO ABORTADO: A9: la primera reactivación no reactivó la ficha (%)', v_res;
  end if;
  if pg_temp.retirar(v_ger, v_f) <> '1' then raise exception 'ENSAYO ABORTADO: A9: no se pudo retirar otra vez la ficha'; end if;
  v_c := pg_temp.sembrado(182, 'CLIENTE A9 CON EL ALTERNATIVO DE LA FICHA', true, 'convertido', null, v_vend3);
  v_esp := pg_temp.referencia('A9', pg_temp.tel(182));
  perform pg_temp.bloqueo_alta('A9-reintento-de-una-ficha-que-conserva-el-contacto-de-un-cliente (D-61)', 'alta', v_vend2, v_pid,
    pg_temp.tel(181), pg_temp.dni(181), v_f, v_esp, v_c);

  -- A7. R3a (cliente ACTIVO por el teléfono conservado): HOY ya lo para la comprobación de lo conservado del 2.4 (3b, C-1), con su
  --     veredicto; no cambia.
  v_c := pg_temp.sembrado(160, 'CLIENTE A7 ACTIVO', true, 'convertido', null, v_vend3);
  v_f := pg_temp.ficha_retirada(v_vend1, 161, 'FICHA A7 RETIRADA', pg_temp.dni(161), null);
  perform pg_temp.sembrar_telefono(v_f, pg_temp.teln(160));
  perform pg_temp.bloqueo_alta('A7-R3a-el-telefono-conservado-es-de-un-cliente-activo (como hoy)', 'alta', v_vend2, null,
    pg_temp.tel(162), pg_temp.dni(161), v_f, '{"estado": "ya_es_cliente", "asesor": "PASO08 VEND3"}'::jsonb, v_c);

  -- A8. R1 del 2.8: el reintento con el alternativo TECLEADO de un cliente vuelve a reactivar LA MISMA ficha, que conserva su
  --     alternativo (que no es de nadie): como hoy.
  v_f := pg_temp.ficha_retirada(v_vend1, 171, 'FICHA A8 RETIRADA CON ALTERNATIVO', pg_temp.dni(171), pg_temp.teln(172));
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO A8', pg_temp.tel(171), pg_temp.dni(171), pg_temp.teln(173));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id') is distinct from v_f::text
     or (select l.telefono_alternativo from crm.leads l where l.id = v_f) is distinct from pg_temp.teln(172) then
    raise exception 'ENSAYO ABORTADO: A8: la primera reactivación no reactivó la ficha conservando su alternativo (%)', v_res;
  end if;
  v_c := pg_temp.sembrado(173, 'CLIENTE A8 CON EL ALTERNATIVO TECLEADO', false, 'convertido', null, v_vend3);
  if pg_temp.retirar(v_ger, v_f) <> '1' then raise exception 'ENSAYO ABORTADO: A8: no se pudo retirar otra vez la ficha'; end if;
  perform pg_temp.reactiva_alta('A8-R1-reintento-con-el-alternativo-tecleado-de-un-cliente (como hoy)', v_vend2, v_pid,
    pg_temp.tel(171), pg_temp.dni(171), pg_temp.teln(173), v_f, pg_temp.teln(172));

  v_f := pg_temp.ficha_retirada(v_vend1, 191, 'FICHA A10 RETIRADA SIN COINCIDENCIA', pg_temp.dni(191), pg_temp.teln(192));
  perform pg_temp.reactiva_alta('A10-sin-coincidencia (reactiva como hoy)', v_vend2, null, pg_temp.tel(191), pg_temp.dni(191), null,
    v_f, pg_temp.teln(192));

  v_l := pg_temp.lead_nuevo(v_vend3, 193, 'LEAD VIVO A11 QUE NO ES CLIENTE');
  v_f := pg_temp.ficha_retirada(v_vend1, 194, 'FICHA A11 RETIRADA', pg_temp.dni(194), pg_temp.teln(193));
  perform pg_temp.reactiva_alta('A11-el-alternativo-conservado-es-de-un-lead-vivo-que-no-es-cliente (reactiva como hoy)', v_vend2, null,
    pg_temp.tel(194), pg_temp.dni(194), null, v_f, pg_temp.teln(193));

  v_f := pg_temp.ficha_retirada(v_vend1, 196, 'FICHA A12 RETIRADA CON UN ALTERNATIVO INTERNACIONAL', pg_temp.dni(196), '+' || pg_temp.tel(195));
  v_c := pg_temp.sembrado(195, 'CLIENTE A12 CON EL MOVIL PERUANO DE ESOS DIGITOS', true, 'convertido', null, v_vend3);
  perform pg_temp.reactiva_alta('A12-un-alternativo-internacional-no-es-el-movil-peruano-de-un-cliente (reactiva como hoy)', v_vend2, null,
    pg_temp.tel(196), pg_temp.dni(196), null, v_f, '+' || pg_temp.tel(195));

  -- A13. Lo conservado choca con un lead VIVO (el teléfono) Y con un cliente (el alternativo): manda el veredicto de hoy («tomado»).
  v_l := pg_temp.lead_nuevo(v_vend1, 197, 'LEAD VIVO A13');
  v_f := pg_temp.ficha_retirada(v_vend1, 186, 'FICHA A13 RETIRADA', pg_temp.dni(186), pg_temp.teln(198));
  perform pg_temp.sembrar_telefono(v_f, pg_temp.teln(197));
  v_c := pg_temp.sembrado(198, 'CLIENTE A13 CON EL ALTERNATIVO DE LA FICHA', true, 'convertido', null, v_vend3);
  v_txt := pg_temp.ficha(v_f)::text;
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO A13', pg_temp.tel(187), pg_temp.dni(186));
  perform pg_temp.medida(format('A13-lo-conservado-choca-con-un-lead-vivo-y-con-un-cliente · alta (teléfono %s, DNI %s) → %s', pg_temp.tel(187), pg_temp.dni(186), v_res));
  v_r := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  perform pg_temp.reg('A13-lo-conservado-choca-con-un-lead-vivo-y-con-un-cliente: manda el «tomado» de hoy',
    case when v_r ->> 'estado' = 'tomado' and v_r ->> 'vendedor' = 'PASO08 VEND1' and pg_temp.ficha(v_f)::text = v_txt then ''
         else format(E'FALLO A13-lo-conservado-choca-con-un-lead-vivo-y-con-un-cliente: se esperaba «tomado» por PASO08 VEND1 (hoy) con la ficha intacta y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- B. LA BASE PARA GESTIÓN QUE REACTIVA UN CONTACTO (D-55; hallazgo H-1 del 2.9). El contacto se cargó cuando su teléfono era libre;
  --    el cliente llegó DESPUÉS con ese teléfono (o su DNI) entre sus contactos. Reactivar ⇒ P0481 «Contacto no disponible» con
  --    EXACTAMENTE la referencia en el detalle, sin tocar nada.
  --    B1 H-1: el alternativo de un cliente activo (v2) · B2 el principal de un cliente activo · B3 el principal de un cliente retirado
  --    · B4 el alternativo de un cliente retirado · B5 el alternativo de un cliente con persona · B6 el DNI de un cliente retirado ·
  --    B7 un lead DESCARTADO de la cartera (no de una base) cuyo alternativo es el teléfono de un cliente, lo reactiva su analista ·
  --    B8 la puerta sin capital (v1) · B9 el intento «agendó cita».
  --    Sin cambio: B10 sin coincidencia · B11 el alternativo de un lead vivo que no es cliente · B12 fuera del ámbito (P0002: nunca ve
  --    el veredicto) · B13 No contactar (P0429) · B14 el replay de una reactivación ya hecha · B15 un lead que ya no está en la base
  --    (22023) · B16 un intento que no reactiva («no contestó»).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_bs := pg_temp.base(v_sup1, 'BASE ENSAYO 2.11 SUP1');

  v_l := pg_temp.contacto(v_sup1, v_bs, 201);
  v_c := pg_temp.cliente_sin_persona(202, 'CLIENTE B1 CON EL TELEFONO DEL CONTACTO COMO ALTERNATIVO', v_vend1, false, pg_temp.teln(201));
  v_esp := pg_temp.referencia('B1', pg_temp.tel(202));
  perform pg_temp.bloqueo_base('B1-H1-el-telefono-del-contacto-es-el-alternativo-de-un-cliente-activo (v2)', 'v2', v_sup1, v_l, v_esp, v_c);

  v_l := pg_temp.contacto(v_sup1, v_bs, 211);
  v_c := pg_temp.sembrado(211, 'CLIENTE B2 CON EL TELEFONO DEL CONTACTO', true, 'convertido', pg_temp.dni(212), v_vend3);
  v_esp := pg_temp.referencia('B2', pg_temp.tel(213), pg_temp.dni(212));
  perform pg_temp.bloqueo_base('B2-el-telefono-del-contacto-es-el-principal-de-un-cliente-activo (v2)', 'v2', v_sup1, v_l, v_esp, v_c);

  v_l := pg_temp.contacto(v_sup1, v_bs, 221);
  v_c := pg_temp.sembrado(221, 'CLIENTE B3 RETIRADO CON EL TELEFONO DEL CONTACTO', false, 'convertido', pg_temp.dni(222), v_vend3);
  v_esp := pg_temp.referencia('B3', pg_temp.tel(223), pg_temp.dni(222));
  perform pg_temp.bloqueo_base('B3-el-telefono-del-contacto-es-el-principal-de-un-cliente-retirado (v2)', 'v2', v_sup1, v_l, v_esp, v_c);

  v_l := pg_temp.contacto(v_sup1, v_bs, 231);
  v_c := pg_temp.cliente_sin_persona(232, 'CLIENTE B4 RETIRADO CON EL TELEFONO DEL CONTACTO COMO ALTERNATIVO', v_vend1, true, pg_temp.teln(231));
  v_esp := pg_temp.referencia('B4', pg_temp.tel(232));
  perform pg_temp.bloqueo_base('B4-el-telefono-del-contacto-es-el-alternativo-de-un-cliente-retirado (v2)', 'v2', v_sup1, v_l, v_esp, v_c);

  v_l := pg_temp.contacto(v_sup1, v_bs, 241);
  v_c := pg_temp.convertir_real(242, 'CLIENTE B5 CON PERSONA', v_vend1, pg_temp.teln(241));
  v_esp := pg_temp.referencia('B5', pg_temp.tel(242));
  perform pg_temp.bloqueo_base('B5-el-telefono-del-contacto-es-el-alternativo-de-un-cliente-con-persona (v2)', 'v2', v_sup1, v_l, v_esp, v_c);

  v_l := pg_temp.contacto(v_sup1, v_bs, 251, pg_temp.dni(251));
  v_c := pg_temp.sembrado(252, 'CLIENTE B6 RETIRADO CON EL DNI DEL CONTACTO', false, 'convertido', pg_temp.dni(251), v_vend3);
  v_esp := pg_temp.referencia('B6', pg_temp.tel(252));
  perform pg_temp.bloqueo_base('B6-el-dni-del-contacto-es-de-un-cliente-retirado (v2)', 'v2', v_sup1, v_l, v_esp, v_c);

  v_l := pg_temp.lead_nuevo(v_vend1, 261, 'LEAD B7 DE LA CARTERA CON ALTERNATIVO', pg_temp.dni(261), pg_temp.teln(262));
  perform pg_temp.descartar_sembrado(v_l);
  v_c := pg_temp.sembrado(262, 'CLIENTE B7 CON EL ALTERNATIVO DEL LEAD', true, 'convertido', null, v_vend3);
  v_esp := pg_temp.referencia('B7', pg_temp.tel(262));
  perform pg_temp.bloqueo_base('B7-un-descartado-de-la-cartera-cuyo-alternativo-es-de-un-cliente (v2, su analista)', 'v2', v_vend1, v_l, v_esp, v_c);

  v_l := pg_temp.lead_nuevo(v_vend1, 271, 'LEAD B8 DE LA CARTERA CON ALTERNATIVO', pg_temp.dni(271), pg_temp.teln(272));
  perform pg_temp.descartar_sembrado(v_l);
  v_c := pg_temp.sembrado(272, 'CLIENTE B8 CON EL ALTERNATIVO DEL LEAD', true, 'convertido', null, v_vend3);
  v_esp := pg_temp.referencia('B8', pg_temp.tel(272));
  perform pg_temp.bloqueo_base('B8-la-puerta-sin-capital (v1): el alternativo del lead es de un cliente', 'v1', v_vend1, v_l, v_esp, v_c);

  v_l := pg_temp.contacto(v_sup1, v_bs, 281);
  v_c := pg_temp.cliente_sin_persona(282, 'CLIENTE B9 CON EL TELEFONO DEL CONTACTO COMO ALTERNATIVO', v_vend1, false, pg_temp.teln(281));
  v_esp := pg_temp.referencia('B9', pg_temp.tel(282));
  perform pg_temp.bloqueo_base('B9-el-intento-agendo-cita-reactiva: el telefono del contacto es el alternativo de un cliente', 'cita', v_sup1, v_l, v_esp, v_c);

  v_l := pg_temp.contacto(v_sup1, v_bs, 291);
  perform pg_temp.reactiva_base('B10-sin-coincidencia (v2, reactiva como hoy)', 'v2', v_sup1, v_l);

  v_l := pg_temp.contacto(v_sup1, v_bs, 293);
  perform pg_temp.lead_nuevo(v_vend3, 294, 'LEAD VIVO B11 QUE NO ES CLIENTE', null, pg_temp.teln(293));
  perform pg_temp.reactiva_base('B11-el-telefono-del-contacto-es-el-alternativo-de-un-lead-vivo-que-no-es-cliente (v2, reactiva como hoy)', 'v2', v_sup1, v_l);

  v_l := pg_temp.contacto(v_sup1, v_bs, 295);
  v_c := pg_temp.cliente_sin_persona(296, 'CLIENTE B12 CON EL TELEFONO DEL CONTACTO COMO ALTERNATIVO', v_vend1, false, pg_temp.teln(295));
  perform pg_temp.igual_base('B12-otro-equipo-no-ve-el-contacto (P0002 como hoy: nunca ve el veredicto)', 'v2', v_sup2, gen_random_uuid(), v_l,
    'P0002', 'Lead no encontrado o fuera de tu ambito');

  v_l := pg_temp.contacto(v_sup1, v_bs, 297);
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_l;
  set local session_replication_role = origin;
  v_c := pg_temp.cliente_sin_persona(298, 'CLIENTE B13 CON EL TELEFONO DEL CONTACTO COMO ALTERNATIVO', v_vend1, false, pg_temp.teln(297));
  perform pg_temp.igual_base('B13-no-contactar-manda (P0429 como hoy)', 'v2', v_sup1, gen_random_uuid(), v_l, 'P0429', 'No insistir');

  -- B14/B15. Un contacto reactivado ANTES de que el cliente llegara: el replay de esa misma operación devuelve lo de entonces, y otra
  --          operación sobre él dice lo de hoy (ya no está en la base).
  v_l := pg_temp.contacto(v_sup1, v_bs, 285);
  v_op := gen_random_uuid();
  v_res := pg_temp.por_la_base('v2', v_sup1, v_op, v_l);
  if v_res not like 'ok|%' then raise exception 'ENSAYO ABORTADO: B14: la primera reactivación falló (%)', v_res; end if;
  perform pg_temp.sembrado(286, 'CLIENTE B14 CON EL TELEFONO DEL CONTACTO COMO ALTERNATIVO', true, 'convertido', null, v_vend3, pg_temp.teln(285));
  v_txt := pg_temp.huella_escritura();
  v_res := pg_temp.por_la_base('v2', v_sup1, v_op, v_l);
  perform pg_temp.medida(format('B14-replay-de-una-reactivacion-ya-hecha · v2 (misma operación) → %s', v_res));
  perform pg_temp.reg('B14-replay-de-una-reactivacion-ya-hecha (como hoy)',
    case when v_res like 'ok|%' and coalesce((substr(v_res, 4)::jsonb ->> 'replay')::boolean, false)
              and pg_temp.huella_escritura() = v_txt then ''
         else format(E'FALLO B14-replay-de-una-reactivacion-ya-hecha: se esperaba el replay de la respuesta de entonces (replay=true, sin escribir) y llegó %s\n', v_res) end);
  perform pg_temp.igual_base('B15-un-lead-que-ya-no-esta-en-la-base (22023 como hoy)', 'v2', v_sup1, gen_random_uuid(), v_l,
    '22023', 'El lead ya no esta en la base');

  v_l := pg_temp.contacto(v_sup1, v_bs, 287);
  v_c := pg_temp.cliente_sin_persona(288, 'CLIENTE B16 CON EL TELEFONO DEL CONTACTO COMO ALTERNATIVO', v_vend1, false, pg_temp.teln(287));
  perform pg_temp.reactiva_base('B16-un-intento-que-no-reactiva (no contestó: como hoy)', 'no_contesto', v_sup1, v_l);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- U/K. LA PIEZA NUEVA (`private.juicio_cliente_conservado`, la regla que usan las dos puertas), por su contrato:
  --    U1 nunca juzga al lead contra sí mismo (un cliente retirado cuyos contactos nadie más tiene ⇒ NULL) · K1 toma los candados de
  --    contacto de lo que el lead conserva (su teléfono, su alternativo y su DNI) con la MISMA clave que el disparador.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado(301, 'CLIENTE U1 RETIRADO SIN NADIE MAS CON SUS CONTACTOS', false, 'convertido', pg_temp.dni(301), v_vend3, pg_temp.teln(302));
  if v_pieza is null then
    perform pg_temp.reg('U1', E'FALLO U1: la pieza private.juicio_cliente_conservado no existe (sin la migración)\n');
  else
    execute 'select private.juicio_cliente_conservado($1)' into v_r using v_c;
    perform pg_temp.medida(format('U1 · la pieza sobre un cliente retirado cuyos contactos nadie más tiene → %s', coalesce(v_r::text, 'NULL')));
    perform pg_temp.reg('U1-la-pieza-no-juzga-al-lead-contra-si-mismo',
      case when v_r is null then '' else format(E'FALLO U1-la-pieza-no-juzga-al-lead-contra-si-mismo: sobre un cliente cuyos contactos nadie más tiene respondió %s (se juzgó contra sí mismo)\n', v_r) end);
  end if;

  -- El lead de K1 nace por la puerta real con un número AUXILIAR (311: el alta y su disparador toman y retienen hasta el final de la
  -- transacción los candados de lo que escriben) y recibe los contactos del caso (313, 314, DNI 313) con los disparadores apagados
  -- (estado declarado, como `lead_para_claves` del 2.8): así ninguna de SUS claves estaba tomada antes de la llamada.
  v_l := pg_temp.lead_nuevo(v_vend1, 311, 'LEAD K1');
  set local session_replication_role = replica;
  update crm.leads set telefono = pg_temp.teln(313), telefono_alternativo = pg_temp.teln(314), dni = pg_temp.dni(313) where id = v_l;
  set local session_replication_role = origin;
  if v_pieza is null then
    perform pg_temp.reg('K1', E'FALLO K1: la pieza private.juicio_cliente_conservado no existe (sin la migración)\n');
  else
    v_esperadas := array(select x from unnest(array[pg_temp.clave('telefono', pg_temp.teln(313)), pg_temp.clave('telefono', pg_temp.teln(314)),
                                                    pg_temp.clave('dni', pg_temp.dni(313))]) x order by 1);
    r := pg_temp.claves_de(format('select private.juicio_cliente_conservado(%L::uuid)', v_l));
    if r.antes && v_esperadas then
      raise exception 'ENSAYO ABORTADO: K1: alguna clave esperada ya estaba tomada antes de la llamada';
    end if;
    v_ped := array(select x from unnest(r.pedidas) x where x = any (v_esperadas) order by 1);
    perform pg_temp.medida(format('K1 · la pieza sobre un lead con teléfono, alternativo y DNI → %s · pidió %s de las 3 claves esperadas (y %s candado(s) más)',
      r.resultado, cardinality(v_ped), coalesce(cardinality(r.pedidas), 0) - cardinality(v_ped)));
    perform pg_temp.reg('K1-la-pieza-toma-los-candados-de-contacto-de-lo-que-el-lead-conserva',
      case when r.resultado = 'ok' and v_ped = v_esperadas then ''
           else format(E'FALLO K1-la-pieza-toma-los-candados-de-contacto-de-lo-que-el-lead-conserva: resultado %s; pidió %s de las 3 claves (teléfono, alternativo y DNI)\n',
                       r.resultado, coalesce(cardinality(v_ped), 0)) end);
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- H. MEDIDAS (hallazgos, no casos): OTRAS puertas que devuelven a la cartera un lead que conserva el contacto de un cliente y que
  --    D-42/D-55 no nombran. HR «Reabrir» (crm.reabrir_lead_fn) un descartado de la cartera cuyo alternativo es el teléfono de un
  --    cliente · HT «Tomar un lead libre» (crm.tomar_lead_libre) un descartado de otro analista cuyo alternativo es el de un cliente.
  --    Igual con y sin la migración (no las toca).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l := pg_temp.lead_nuevo(v_vend1, 321, 'LEAD HR DESCARTADO CON ALTERNATIVO', pg_temp.dni(321), pg_temp.teln(322));
  perform pg_temp.descartar_sembrado(v_l);
  perform pg_temp.sembrado(322, 'CLIENTE HR CON EL ALTERNATIVO DEL LEAD', true, 'convertido', null, v_vend3);
  begin
    perform pg_temp.sesion(v_vend1);
    v_r := crm.reabrir_lead_fn(v_l);
    perform pg_temp.sesion(null);
    v_res := 'ok|' || v_r::text;
  exception when others then
    perform pg_temp.sesion(null);
    v_res := sqlstate || '|' || sqlerrm;
  end;
  perform pg_temp.medida(format('HR · «Reabrir» (VEND1, crm.reabrir_lead_fn) un descartado cuyo alternativo es el teléfono de un cliente → %s · el lead queda %s',
    regexp_replace(v_res, '"reabierto_en": "[^"]*"', '"reabierto_en": "<fecha>"'),
    (select jsonb_build_object('etapa', l.etapa, 'activo', l.activo) from crm.leads l where l.id = v_l)));
  v_l := pg_temp.lead_nuevo(v_vend1, 331, 'LEAD HT DESCARTADO CON ALTERNATIVO', null, pg_temp.teln(332));
  perform pg_temp.descartar_sembrado(v_l);
  perform pg_temp.sembrado(332, 'CLIENTE HT CON EL ALTERNATIVO DEL LEAD', true, 'convertido', null, v_vend3);
  begin
    perform pg_temp.sesion(v_vend2);
    v_r := crm.tomar_lead_libre(pg_temp.tel(331), null);
    perform pg_temp.sesion(null);
    v_res := 'ok|' || v_r::text;
  exception when others then
    perform pg_temp.sesion(null);
    v_res := sqlstate || '|' || sqlerrm;
  end;
  perform pg_temp.medida(format('HT · «Tomar un lead libre» (VEND2, crm.tomar_lead_libre) el descartado de VEND1 cuyo alternativo es el teléfono de un cliente → %s · el lead queda %s',
    v_res, (select jsonb_build_object('etapa', l.etapa, 'activo', l.activo, 'de_vend2', l.vendedor_id = v_vend2) from crm.leads l where l.id = v_l)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C. CATÁLOGO. C1 la pieza nueva: INVOKER de postgres, VOLÁTIL (toma candados), `search_path` vacío y nada más, EXECUTE solo para
  --    postgres, con comentario · C2 los dos núcleos la llaman EXACTAMENTE una vez y conservan su ficha (dueño, DEFINER, SET, ACL) ·
  --    C3 nadie más la usa · C4 lo que no se toca (la pieza del 2.8, lo conservado del 2.4, el alta, las puertas, la reapertura, el
  --    disparador, el verificador y los candados), con su definición de hoy.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if v_pieza is null then
    perform pg_temp.reg('C1', E'FALLO C1: la pieza private.juicio_cliente_conservado no existe (sin la migración)\n');
  elsif not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                      and p.provolatile = 'v' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE') or obj_description(v_pieza, 'pg_proc') is null then
    perform pg_temp.reg('C1', E'FALLO C1: private.juicio_cliente_conservado no es INVOKER de postgres, VOLÁTIL, con search_path vacío, EXECUTE solo para postgres y comentario\n');
  else
    perform pg_temp.reg('C1 private.juicio_cliente_conservado: ficha, ACL y comentario', '');
  end if;
  select string_agg(x.que, '; ') into v_txt
  from (
    select 'el núcleo del alta no la llama exactamente una vez' as que
     where (select (length(p.prosrc) - length(replace(p.prosrc, 'private.juicio_cliente_conservado(', ''))) / length('private.juicio_cliente_conservado(')
              from pg_proc p where p.oid = v_nucleo) is distinct from 1
    union all
    select 'el núcleo de la base no la llama exactamente una vez'
     where (select (length(p.prosrc) - length(replace(p.prosrc, 'private.juicio_cliente_conservado(', ''))) / length('private.juicio_cliente_conservado(')
              from pg_proc p where p.oid = v_nbase) is distinct from 1
    union all
    select 'la ficha del núcleo del alta cambió'
     where (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
                   || '|' || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
                                from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
              from pg_proc p where p.oid = v_nucleo) is distinct from 'postgres|true|v|{"search_path=\"\"",lock_timeout=5s}|postgres:EXECUTE:false'
    union all
    select 'la ficha del núcleo de la base cambió'
     where (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
                   || '|' || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
                                from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
              from pg_proc p where p.oid = v_nbase) is distinct from 'postgres|true|v|{"search_path=\"\""}|postgres:EXECUTE:false') x;
  perform pg_temp.reg('C2 los dos núcleos llaman a la pieza una vez y conservan su ficha',
    case when v_txt is null then '' else format(E'FALLO C2: %s\n', v_txt) end);
  if v_pieza is null then
    perform pg_temp.reg('C3', E'FALLO C3: la pieza private.juicio_cliente_conservado no existe (sin la migración)\n');
  else
    select string_agg(x.f, ', ' order by x.f) into v_txt
    from (select p.oid::regprocedure::text as f
            from pg_proc p
           where strpos(lower(p.prosrc), 'juicio_cliente_conservado') > 0
             and p.oid not in (v_pieza, v_nucleo, v_nbase)
          union all
          select pg_describe_object(d.classid, d.objid, d.objsubid)
            from pg_depend d
           where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_pieza) x;
    perform pg_temp.reg('C3 solo los dos núcleos usan la pieza',
      case when v_txt is null then '' else format(E'FALLO C3: otros usan la pieza: %s\n', v_txt) end);
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_txt
  from (values
    ('crm.crear_lead_documento_fn(jsonb,text,text)', 'f6dfdc2907a1c3069e4988bf038d04c1'),
    ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)', 'e06eca2333bb11869d00913a004c8261'),
    ('crm.reabrir_lead_fn(uuid)', '9cdac9e10f2efde549bbcbdf810b95d3'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'cf44c73e6326573dfbcb5defdb07fcf7'),
    ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'a8c982fb500bdc42b11032d4576ed953'),
    ('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)', '2c360e0e2536096713059a9dbbcd1ef8'),
    ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', '6f5971c0bf6f68285fadae5e30099ee2'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', '2186e7c4b4e3ac4bcf23636cb951d9ba'),
    ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', 'a4a0638e4ca2c8a89ad9909c522b4a92'),
    ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '83d99939149bbf445b5c77c33787f1cf'),
    ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', 'c9e90784de512cc4c8e694a0465bc80c'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882'),
    ('private.juicio_cliente_convertido(text,text,text,uuid)', 'a2b38faf42a875c7dffb7968b106e36f'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9'),
    ('private.trg_leads_disponibilidad_atomica()', '418b097675753ed9f81931a485b17c94'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a')) e(firma, definicion)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion;
  perform pg_temp.reg('C4 lo que no se toca, con su definición de hoy',
    case when v_txt is null then '' else format(E'FALLO C4: cambió algo que el 2.11 no toca: %s\n', v_txt) end);
  perform pg_temp.medida(format('C5 huellas al final: núcleo del alta md5(prosrc)=%s · md5(definición)=%s · núcleo de la base md5(prosrc)=%s · md5(definición)=%s · pieza nueva %s',
    (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo),
    (select md5(p.prosrc) from pg_proc p where p.oid = v_nbase), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nbase),
    coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza), 'AUSENTE')));

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ───────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('Z0', format(E'FALLO Z0: algo de lo escrito no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
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
