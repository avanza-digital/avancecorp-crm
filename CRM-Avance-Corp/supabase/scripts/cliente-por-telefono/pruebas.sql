-- ORÁCULO de «El cliente ya convertido también se reconoce por teléfono» — se ejecuta en el LABORATORIO (banco Docker local),
-- NUNCA contra producción, y no escribe nada.
--
-- La regla (decisiones D-22 y D-25 de Miguel, 08/10/2026; hallazgo H-28, caso L9f-tel del banco; plan AVANCE-BACKEND-0710-P3,
-- fase 2, bloque 2.7): si alguien registra como lead nuevo a una persona que YA ES CLIENTE —su lead está CONVERTIDO, activo o
-- retirado— escribiendo SOLO el teléfono (o el teléfono con OTRO DNI), `crm.crear_lead_si_disponible` responde «ya es cliente»
-- y no crea (ni reactiva) nada. Enlazado a una persona ⇒ el mismo juicio de identidad que da el DNI (`ya_es_cliente` con su
-- asesor, o `no_contactar` si la persona está vetada); sin persona ⇒ `ya_es_cliente` a nombre del dueño de esa ficha. El
-- convertido gana a cualquier retirado no convertido que también case por teléfono o DNI. El camino del REINTENTO del 2.4 no
-- cambia. RONDA 2 (D-27 de Miguel, 08/10/2026): lo mismo con el DNI tecleado cuando es el `dni` de un lead convertido (activo o
-- retirado, con o sin persona) y ningún convertido casa por el teléfono; precedencia: teléfono → DNI → candidato retirado del
-- 2.4 (sección 11). RONDA 3 (revisión de Codex): la prioridad entre VARIOS convertidos del mismo teléfono o del mismo DNI con
-- asesores distintos —primero el enlazado a persona, luego el activo, luego el convertido más reciente— (sección 12), y la huella de
-- escritura por contenido. RONDA 4 (revisión 2 del auditor): desempates deterministas en la sección 12 —ids fijos en 12c/12f y un
-- convertido sin fecha frente a uno con fecha en 12g/12h—. Un lead activo vivo, la cuenta del Portal, el teléfono con el DNI del
-- cliente, «no contactar» y los roles siguen como hoy. Hoy (sin la migración) el verificador dice «libre» (solo el documento
-- vincula; su paso de lead vivo excluye
-- `etapa = 'convertido'`), la rama del 2.4 excluye convertidos y el alta INSERTA un SEGUNDO lead del cliente.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (a la que quita su
-- `begin;`/`commit;`) dentro de una única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y
-- entonces TIENE que salir ROJO porque el alta crea un SEGUNDO lead del cliente (caso 1), no por un error de montaje.
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT (las puertas son `security definer` y
-- deciden por `auth.uid()`), fijada en las DOS formas (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de rol con
-- `set role`: llamar bajo `set role` a una función sin EXECUTE tumba el Postgres del banco; los permisos se leen del catálogo
-- (sección 10). Actores reales del banco (`PASO08 …`), OBLIGATORIOS con su rol exacto: sin ellos, `ENSAYO ABORTADO`.
--
-- Cómo nacen los clientes (los convertidos):
--   · CON PERSONA: por la PUERTA REAL del formulario compartido, como el banco (L9f) y `conversion-inversion/test-conversion.sql`:
--     alta del lead por `crm.crear_lead_si_disponible` (VEND1) → `crm.preparar_persona_lead_inversion_fn` (persona + DNI) →
--     `crm.preparar_inversion_fn` (empresa `prodelco`: cooperativa, SIN cuenta del Portal) → comprobante (objeto de Storage
--     sintético, sin sesión: el mismo fixture que usa el banco) → `crm.confirmar_inversion_fn`. La ficha queda `convertido`,
--     activa, enlazada a su persona, con el responsable de relación que fija la conversión y su episodio cerrado.
--     Retirarla es el UPDATE `activo = false` con la sesión de Gerencia (así se retira hoy: por API, sin pantalla).
--   · SIN PERSONA (estado heredado: convertidos anteriores a la identidad unificada): alta por la puerta real y conversión
--     sembrada con los disparadores apagados, como los casos 3d/B1/R3-1a del oráculo del 2.4.
--   · Los DUPLICADOS heredados del mismo teléfono (un retirado no convertido o un lead activo que comparte teléfono con un
--     cliente: D-23/D-25, «se dejan como están») se siembran con los disparadores apagados, como `retirado_sintetico` del 2.4:
--     con la regla instalada la puerta real ya no permite montarlos.
--   · El veto de la PERSONA sin veto en su lead (5b) y la cuenta del Portal con el teléfono del cliente (6a: el perfil
--     `PASO08 CLI1` recibe ese teléfono) se siembran con los disparadores apagados (estado heredado declarado).

set local statement_timeout = '300s';

-- Identidad de la sesión, en las DOS formas de los claims.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Acumulador del informe: un caso que pasa suma una línea «ok»; uno que falla, un fallo con su texto.
create function pg_temp.reg(p_caso text, p_txt text) returns void language plpgsql as $f$
begin
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

-- Contactos del ensayo: un bloque propio (+51 924 07xxxx / 7527xxxx) que el montaje exige LIBRE (el del 2.4 es 92400/7524).
create function pg_temp.tel(n integer) returns text language sql immutable as $$ select '92407' || lpad(n::text, 4, '0') $$;
create function pg_temp.teln(n integer) returns text language sql immutable as $$ select '+51' || pg_temp.tel(n) $$;
create function pg_temp.dni(n integer) returns text language sql immutable as $$ select '7527' || lpad(n::text, 4, '0') $$;

create temp table ens_actores (nombre text primary key, id uuid not null);

create function pg_temp.actor(p_nombre text) returns uuid language sql as $$
  select a.id from ens_actores a where a.nombre = p_nombre
$$;

-- Fotos COMPLETAS de una ficha y de una persona (para «sigue intacta»).
create function pg_temp.ficha(p_id uuid) returns jsonb language sql as $$
  select to_jsonb(l) from crm.leads l where l.id = p_id
$$;
create function pg_temp.persona(p_id uuid) returns jsonb language sql as $$
  select to_jsonb(i) from crm.inversionistas i where i.id = p_id
$$;

-- Huella de ESCRITURA: cualquier lead, actividad, episodio, tarea, persona, documento o ciclo SLA nuevo la cambia; y, desde la ronda 3
-- (Codex), cualquier CAMBIO en una fila existente de crm.leads, crm.actividades o crm.lead_asignaciones: compara su contenido entero
-- (md5 de las filas, en orden de id), no solo cuántas hay. Cubre todas las filas de esas tablas (las de los actores del ensayo y las
-- demás del laboratorio: es barato, son tablas pequeñas aquí). Las demás tablas, por número de filas.
create function pg_temp.huella_escritura() returns text language sql as $$
  select concat_ws(',',
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '')) from crm.leads l),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from crm.actividades a),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) from crm.lead_asignaciones e),
    (select count(*) from crm.tareas), (select count(*) from crm.inversionistas), (select count(*) from crm.inversionista_identificadores),
    (select count(*) from crm.lead_sla_ciclos))
$$;

-- Alta por la puerta real, como el actor. 'ok|<respuesta>' o 'SQLSTATE|mensaje'. El bloque con EXCEPTION es una
-- subtransacción: un rechazo deshace TODO lo que la llamada había hecho.
create function pg_temp.alta(p_actor uuid, p_id uuid, p_nombre text, p_tel text, p_dni text,
                             p_etapa text default 'nuevo', p_vendedor uuid default null, p_nota text default null,
                             p_correo text default null, p_monto numeric default 5000)
returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.crear_lead_si_disponible(
    p_nombre_completo => p_nombre, p_telefono => p_tel, p_origen => 'formulario', p_monto_estimado => p_monto,
    p_moneda => 'PEN', p_id => p_id, p_correo => p_correo, p_dni => p_dni, p_etapa => p_etapa,
    p_vendedor_id => p_vendedor, p_nota => p_nota);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Alta por la puerta del documento (CE/pasaporte/DNI), como el actor.
create function pg_temp.alta_doc(p_actor uuid, p_datos jsonb, p_tipo text, p_documento text)
returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.crear_lead_documento_fn(p_datos, p_tipo, p_documento);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- El núcleo llamado DIRECTAMENTE (el banco corre como postgres, su único ejecutor) con una sesión y un p_actor dados y un
-- veredicto bloqueante: mide que el gate interno del 2.4 (A-5) sigue en pie. 'ok|<respuesta o null>' o 'SQLSTATE|mensaje'.
create function pg_temp.nucleo_directo(p_sesion uuid, p_actor uuid, p_tel text) returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_sesion);
  v_r := private.alta_reactivar_retirado(gen_random_uuid(), p_actor, p_tel, null, p_actor, null,
                                         '{"estado":"tomado"}'::jsonb, '{}'::jsonb);
  perform pg_temp.sesion(null);
  return 'ok|' || coalesce(v_r::text, 'null');
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
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

-- CLIENTE CON PERSONA por la conversión REAL (formulario compartido, cooperativa: sin cuenta del Portal). Aborta el ensayo si
-- algo del montaje falla. Devuelve el id del lead convertido (activo, enlazado a su persona).
create function pg_temp.convertir_real(p_n integer, p_nombre text, p_actor uuid default null) returns uuid language plpgsql as $f$
declare
  v_actor uuid := coalesce(p_actor, pg_temp.actor('VEND1'));
  v_lead uuid := gen_random_uuid(); v_res text; v_r jsonb; v_per uuid; v_sol uuid := gen_random_uuid(); v_ruta text;
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
begin
  v_res := pg_temp.alta(v_actor, v_lead, p_nombre, pg_temp.tel(p_n), pg_temp.dni(p_n));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear por la puerta real el lead del cliente % (%)', p_n, v_res;
  end if;
  begin
    perform pg_temp.sesion(v_actor);
    v_per := (crm.preparar_persona_lead_inversion_fn(v_lead, 'DNI', pg_temp.dni(p_n), p_nombre) ->> 'inversionista_id')::uuid;
    v_ruta := v_per || '/' || v_sol || '/comprobante.pdf';
    v_r := crm.preparar_inversion_fn(v_sol, jsonb_build_object('inversionista_id', v_per, 'lead_id', v_lead, 'empresa', 'prodelco',
             -- 22/10/2026 (C2-a ronda 2): 20261016195003 — una inversión nueva de cooperativa vence a plazo × 30 días (12 meses = 360 días), no a 12 meses de calendario.
             'monto', 5000, 'moneda', 'PEN', 'fecha_comercial', v_hoy, 'vence_en', v_hoy + 360,
             'plazo_meses', 12, 'tasa_anual', 15, 'numero_transaccion', 'ENS27-' || left(v_sol::text, 8),
             'referencia', 'ENSAYO 2.7 SINTETICA', 'evidencia', jsonb_build_object('ruta', v_ruta)));
    perform pg_temp.sesion(null);
    -- El comprobante: objeto de Storage sintético, sin sesión (el mismo fixture que el banco sube por la API de Storage).
    insert into storage.objects (bucket_id, name, metadata)
    values ('f4-comprobantes', v_ruta, '{"size":128,"mimetype":"application/pdf"}'::jsonb);
    perform pg_temp.sesion(v_actor);
    v_r := crm.confirmar_inversion_fn((v_r ->> 'solicitud_id')::uuid);
    perform pg_temp.sesion(null);
  exception when others then
    perform pg_temp.sesion(null);
    raise exception 'ENSAYO ABORTADO: la conversión real del cliente % falló (% %)', p_n, sqlstate, sqlerrm;
  end;
  if not coalesce((v_r ->> 'ok')::boolean, false)
     or (select l.etapa <> 'convertido' or not l.activo or l.inversionista_id is distinct from v_per from crm.leads l where l.id = v_lead) then
    raise exception 'ENSAYO ABORTADO: el cliente % no quedó convertido, activo y enlazado a su persona (%)', p_n, v_r;
  end if;
  -- Sin cuenta del Portal (es lo que H-28 deja expuesto): ni perfil enlazado ni perfil cliente con ese teléfono.
  if (select i.perfil_id from crm.inversionistas i where i.id = v_per) is not null
     or exists (select 1 from public.perfiles p where p.rol = 'cliente' and private.normalizar_telefono(p.telefono) = pg_temp.teln(p_n)) then
    raise exception 'ENSAYO ABORTADO: el cliente % tiene cuenta del Portal (el caso exige que no la tenga)', p_n;
  end if;
  return v_lead;
end;
$f$;

-- CONVERSIÓN SEMBRADA (sin persona, estado heredado) de un lead nacido por la puerta real, como 3d/B1/R3-1a del 2.4: etapa
-- `convertido` con su sello, el episodio del ledger y la etapa SLA cerrados; con p_retirar, además activo=false.
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

-- Un lead SEMBRADO sin disparadores (duplicado heredado del mismo teléfono, D-23/D-25), con su ciclo SLA como lo dejaría el
-- alta. p_activo=false ⇒ retirado. p_etapa 'contactado' | 'descartado' (con p_motivo y descarte de hace una hora) |
-- 'convertido' (sin persona, con su sello: p_convertido_en, o hace 5 días). Dueño: p_vendedor (VEND1 si no se da).
-- Ronda 4 (desempates): p_id fija el id del lead (si no se da, uno aleatorio) y p_convertido_en_nulo siembra un convertido SIN
-- fecha de conversión (duplicado heredado sin sello).
create function pg_temp.sembrado(p_n integer, p_nombre text, p_activo boolean, p_etapa text default 'contactado',
                                 p_dni text default null, p_motivo text default null, p_vendedor uuid default null,
                                 p_convertido_en timestamptz default null, p_id uuid default null,
                                 p_convertido_en_nulo boolean default false)
returns uuid language plpgsql as $f$
declare v_id uuid := coalesce(p_id, gen_random_uuid()); v_dueno uuid := coalesce(p_vendedor, pg_temp.actor('VEND1'));
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, motivo_descarte, descartado_en, descartado_por,
                         convertido_en, monto_estimado, moneda, vendedor_id, asignado_supervisor_id, activo, creado_por,
                         alta_manual, ciclo_actual, creado_en, actualizado_en, sla_global_iniciado_en)
  values (v_id, p_nombre, pg_temp.teln(p_n), p_dni, 'formulario', p_etapa,
          case when p_etapa = 'descartado' then p_motivo end,
          case when p_etapa = 'descartado' then clock_timestamp() - interval '1 hour' end,
          case when p_etapa = 'descartado' then v_dueno end,
          case when p_etapa = 'convertido' and not p_convertido_en_nulo then coalesce(p_convertido_en, clock_timestamp() - interval '5 days') end,
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
     or (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = v_id) is distinct from p_etapa || '|' || p_activo::text
     or (p_convertido_en_nulo and (select l.convertido_en from crm.leads l where l.id = v_id) is not null) then
    raise exception 'ENSAYO ABORTADO: el lead sembrado % no quedó como se pidió (o sin ciclo SLA)', p_n;
  end if;
  return v_id;
end;
$f$;

-- Lo que debe cumplir un alta que BLOQUEA (o un veredicto que no cambia): respuesta EXACTA (`p_esperado`, igualdad jsonb), la
-- ficha del cliente y su persona intactas byte a byte, ninguna escritura (huella), los mismos leads con ese teléfono que antes
-- y, si se da, otra ficha (el retirado o el duplicado) intacta. Devuelve '' o la línea FALLO.
create function pg_temp.exigir_bloqueo(p_caso text, p_res text, p_esperado jsonb, p_cliente uuid, p_ficha_antes jsonb,
                                       p_persona uuid, p_persona_antes jsonb, p_huella_antes text, p_teln text,
                                       p_n_tel_antes bigint, p_otra uuid default null, p_otra_antes jsonb default null)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; v_r jsonb; v_n bigint;
begin
  v_n := (select count(*) from crm.leads l where l.telefono = p_teln);
  if p_esperado ? 'error' then
    if p_res like 'ok|%' then
      v_m := v_m || format('debía rechazar con %s y devolvió %s', p_esperado ->> 'error', substr(p_res, 4));
    elsif split_part(p_res, '|', 1) <> p_esperado ->> 'error'
          or (p_esperado ? 'mensaje' and position(p_esperado ->> 'mensaje' in p_res) = 0) then
      v_m := v_m || format('rechazó con otro error: %s (se esperaba %s)', p_res, p_esperado::text);
    end if;
  elsif p_res not like 'ok|%' then
    v_m := v_m || format('el alta falló (%s) en vez de responder %s', p_res, p_esperado::text);
  else
    v_r := substr(p_res, 4)::jsonb;
    if v_r ->> 'estado' = 'creado' then
      return format(E'FALLO %s: estado=creado, se esperaba %s → el alta creó un SEGUNDO lead del cliente: %s lead(s) con el teléfono %s (había %s)\n',
        p_caso, p_esperado::text, v_n, p_teln, p_n_tel_antes);
    elsif v_r ->> 'estado' = 'reutilizado' then
      v_m := v_m || format('estado=reutilizado (reactivó la ficha %s), se esperaba %s', v_r ->> 'lead_id', p_esperado::text);
    elsif v_r is distinct from p_esperado then
      v_m := v_m || format('respuesta %s, se esperaba EXACTAMENTE %s', v_r::text, p_esperado::text);
    end if;
  end if;
  if pg_temp.ficha(p_cliente) is distinct from p_ficha_antes then
    v_m := v_m || format('la ficha del cliente cambió (etapa|activo|dueño %s → %s)',
      (p_ficha_antes ->> 'etapa') || '|' || (p_ficha_antes ->> 'activo') || '|' || coalesce(p_ficha_antes ->> 'vendedor_id', '-'),
      (pg_temp.ficha(p_cliente) ->> 'etapa') || '|' || (pg_temp.ficha(p_cliente) ->> 'activo') || '|' || coalesce(pg_temp.ficha(p_cliente) ->> 'vendedor_id', '-'));
  end if;
  if p_persona is not null and pg_temp.persona(p_persona) is distinct from p_persona_antes then
    v_m := array_append(v_m, 'la persona del cliente cambió');
  end if;
  if p_otra is not null and pg_temp.ficha(p_otra) is distinct from p_otra_antes then
    v_m := v_m || format('la otra ficha del mismo contacto cambió (etapa|activo %s → %s)',
      (p_otra_antes ->> 'etapa') || '|' || (p_otra_antes ->> 'activo'),
      (pg_temp.ficha(p_otra) ->> 'etapa') || '|' || (pg_temp.ficha(p_otra) ->> 'activo'));
  end if;
  if v_n <> p_n_tel_antes then
    v_m := v_m || format('%s lead(s) con el teléfono %s (había %s)', v_n, p_teln, p_n_tel_antes);
  end if;
  if pg_temp.huella_escritura() is distinct from p_huella_antes then
    v_m := v_m || format('se escribió algo (leads:md5, actividades:md5, episodios:md5, tareas, personas, documentos, ciclos: %s → %s)',
      p_huella_antes, pg_temp.huella_escritura());
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

insert into ens_actores (nombre, id)
select n.nombre, p.id
from (values ('VEND1'), ('VEND2'), ('VEND3'), ('SUP1'), ('GERENCIA'), ('COORD'), ('INACTIVO'), ('ADMIN'), ('CLI1')) n(nombre)
join public.perfiles p on p.nombre_completo = 'PASO08 ' || n.nombre;

do $ensayo$
declare
  v_vend1 uuid; v_vend2 uuid; v_vend3 uuid; v_sup1 uuid; v_ger uuid; v_coord uuid; v_inactivo uuid; v_admin uuid; v_cli1 uuid;
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_alta regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_c uuid; v_per uuid; v_otra uuid; v_pid uuid; v_res text; v_txt text; v_esperado jsonb; v_ficha jsonb; v_pers jsonb;
  v_otra_antes jsonb; v_huella text; v_n bigint; v_verif text; v_r jsonb; v_cnt integer; v_l record;
  -- Ronda 2 (D-27).
  v_c2 uuid; v_per2 uuid; v_pid2 uuid; v_ficha2 jsonb; v_pers2 jsonb;
begin
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ── Actores reales del banco (OBLIGATORIOS: sin ellos un caso se saltaría en silencio) ──────────────────────────────
  v_vend1 := pg_temp.actor('VEND1'); v_vend2 := pg_temp.actor('VEND2'); v_vend3 := pg_temp.actor('VEND3');
  v_sup1 := pg_temp.actor('SUP1'); v_ger := pg_temp.actor('GERENCIA'); v_coord := pg_temp.actor('COORD');
  v_inactivo := pg_temp.actor('INACTIVO'); v_admin := pg_temp.actor('ADMIN'); v_cli1 := pg_temp.actor('CLI1');
  if v_vend1 is null or v_vend2 is null or v_vend3 is null or v_sup1 is null or v_ger is null or v_coord is null
     or v_inactivo is null or v_admin is null or v_cli1 is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (vend1=%, vend2=%, vend3=%, sup1=%, gerencia=%, coord=%, inactivo=%, admin=%, cli1=%)',
      v_vend1, v_vend2, v_vend3, v_sup1, v_ger, v_coord, v_inactivo, v_admin, v_cli1;
  end if;
  if private.rol_crm(v_vend1) is distinct from 'vendedor' or private.rol_crm(v_vend2) is distinct from 'vendedor'
     or private.rol_crm(v_vend3) is distinct from 'vendedor' or private.rol_crm(v_sup1) is distinct from 'supervisor'
     or private.rol_crm(v_ger) is distinct from 'gerencia' or private.rol_crm(v_coord) is distinct from 'coordinador'
     or private.rol_crm(v_inactivo) is not null or private.rol_crm(v_admin) is not null
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend2) is distinct from v_sup1
     or (select p.rol || '|' || p.activo::text || '|' || coalesce(p.asesor_perfil_id::text, '-') from public.perfiles p where p.id = v_cli1)
        is distinct from 'cliente|true|' || v_vend1::text then
    raise exception 'ENSAYO ABORTADO: un actor del banco no tiene el rol esperado (vend1/vend2/vend3 vendedor, vend2 bajo sup1; sup1 supervisor; gerencia; coord coordinador; inactivo y admin sin rol CRM; CLI1 perfil cliente activo con asesor VEND1)';
  end if;
  -- La identidad unificada tiene que estar encendida (el juicio de identidad y la conversión real la usan).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'ENSAYO ABORTADO: la bandera resolver_en_puertas está apagada en este laboratorio';
  end if;
  -- El bloque de contactos del ensayo tiene que estar libre.
  if exists (select 1 from crm.leads l where l.telefono like '+5192407%' or l.dni like '7527%')
     or exists (select 1 from public.perfiles p where p.telefono like '%92407%' or p.dni like '7527%')
     or exists (select 1 from crm.inversionista_identificadores d where d.documento_normalizado like '7527%') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene contactos del bloque +51 924 07xxxx / 7527xxxx';
  end if;
  -- El cubo de comprobantes de la conversión real (fixture del banco; si falta, vive y muere en esta transacción).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('f4-comprobantes', 'f4-comprobantes', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
  on conflict (id) do nothing;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 1. Convertido ACTIVO enlazado a persona, sin cuenta del Portal (conversión real de VEND1); otro vendedor (VEND2) lo
  --    registra SOLO por teléfono ⇒ `ya_es_cliente` con el MISMO juicio que da el DNI (asesor = responsable de relación),
  --    un solo lead con ese teléfono, ficha y persona intactas, nada escrito. Es la sonda del Director sobre H-28.
  --    1b/1c: SUP1 (parquea) y Gerencia (elige a VEND3) ⇒ igual. 1d: su PROPIO dueño (VEND1) ⇒ igual, sin escribir nada.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(1, 'CLIENTE UNO ACTIVO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_verif := private.verificar_disponibilidad_lead_impl(pg_temp.teln(1), null) ->> 'estado';
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(1), pg_temp.dni(1));
  perform pg_temp.medida(format('1 (verificador sobre el cliente 1: solo teléfono=%s · teléfono+DNI=%s)', v_verif, v_esperado::text));
  if v_verif <> 'libre' or v_esperado ->> 'estado' <> 'ya_es_cliente' or v_esperado ->> 'via' is distinct from 'identidad'
     or v_esperado ->> 'asesor' is distinct from 'PASO08 VEND1' then
    raise exception 'ENSAYO ABORTADO: el cliente 1 no es el estado de H-28 (solo teléfono=%, con DNI=%): el caso no mediría lo que dice', v_verif, v_esperado;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(1));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO UNO SOLO TELEFONO', pg_temp.tel(1), null);
  perform pg_temp.reg('1-activo-solo-telefono (VEND2; el mismo juicio que con el DNI)',
    pg_temp.exigir_bloqueo('1-activo-solo-telefono', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(1), v_n));
  perform pg_temp.medida(format('1 (alta de VEND2 solo por teléfono sobre el cliente activo): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- 1b. SUP1 (parquea en su bandeja), otro cliente.
  v_c := pg_temp.convertir_real(24, 'CLIENTE VEINTICUATRO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(24), pg_temp.dni(24));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(24));
  v_res := pg_temp.alta(v_sup1, gen_random_uuid(), 'REINGRESO VEINTICUATRO POR SUP1', pg_temp.tel(24), null);
  perform pg_temp.reg('1b-supervisor-solo-telefono',
    pg_temp.exigir_bloqueo('1b-supervisor-solo-telefono', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(24), v_n));
  -- 1c. Gerencia elige a VEND3 como destino, otro cliente.
  v_c := pg_temp.convertir_real(25, 'CLIENTE VEINTICINCO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(25), pg_temp.dni(25));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(25));
  v_res := pg_temp.alta(v_ger, gen_random_uuid(), 'REINGRESO VEINTICINCO POR GERENCIA', pg_temp.tel(25), null, 'nuevo', v_vend3);
  perform pg_temp.reg('1c-gerencia-con-destino-solo-telefono',
    pg_temp.exigir_bloqueo('1c-gerencia-con-destino-solo-telefono', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(25), v_n));
  -- 1d. Su PROPIO dueño (VEND1) lo vuelve a registrar por teléfono: tampoco nace nada (y la regla no escribe nada aunque el
  --     actor pudiera escribir en esa ficha).
  v_c := pg_temp.convertir_real(23, 'CLIENTE VEINTITRES');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(23), pg_temp.dni(23));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(23));
  v_res := pg_temp.alta(v_vend1, gen_random_uuid(), 'REINGRESO VEINTITRES POR SU DUENO', pg_temp.tel(23), null);
  perform pg_temp.reg('1d-su-propio-dueno-solo-telefono',
    pg_temp.exigir_bloqueo('1d-su-propio-dueno-solo-telefono', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(23), v_n));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 2. Convertido RETIRADO enlazado a persona (conversión real; Gerencia lo retira por API), solo por teléfono ⇒ igual que 1;
  --    la ficha sigue `convertido|false` (no se reactiva: D-15). Es el caso L9f-tel del banco.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(2, 'CLIENTE DOS RETIRADO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente 2'; end if;
  v_verif := private.verificar_disponibilidad_lead_impl(pg_temp.teln(2), null) ->> 'estado';
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(2), pg_temp.dni(2));
  perform pg_temp.medida(format('2 (verificador sobre el cliente 2 retirado: solo teléfono=%s · teléfono+DNI=%s)', v_verif, v_esperado::text));
  if v_verif <> 'libre' or v_esperado ->> 'estado' <> 'ya_es_cliente' then
    raise exception 'ENSAYO ABORTADO: el cliente 2 retirado no es el estado de L9f-tel (solo teléfono=%, con DNI=%)', v_verif, v_esperado;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(2));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO DOS SOLO TELEFONO', pg_temp.tel(2), null);
  perform pg_temp.reg('2-retirado-solo-telefono (L9f-tel)',
    pg_temp.exigir_bloqueo('2-retirado-solo-telefono', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(2), v_n));
  perform pg_temp.medida(format('2 (alta de VEND2 solo por teléfono sobre el cliente retirado): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3. Teléfono del cliente con OTRO DNI ⇒ `ya_es_cliente` (D-25: el teléfono manda) con el juicio de SU persona; ningún lead
  --    con el DNI tecleado, un solo lead con el teléfono.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(3, 'CLIENTE TRES');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_verif := private.verificar_disponibilidad_lead_impl(pg_temp.teln(3), pg_temp.dni(93)) ->> 'estado';
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(3), pg_temp.dni(3));
  if v_verif <> 'libre' or v_esperado ->> 'estado' <> 'ya_es_cliente' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» con el teléfono del cliente 3 y otro DNI (%): el caso no mediría D-25', v_verif;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(3));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'OTRA PERSONA CON EL TELEFONO TRES', pg_temp.tel(3), pg_temp.dni(93));
  v_txt := pg_temp.exigir_bloqueo('3-otro-dni', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(3), v_n);
  if exists (select 1 from crm.leads l where l.dni = pg_temp.dni(93)) then
    v_txt := v_txt || E'FALLO 3-otro-dni: nació un lead con el DNI tecleado\n';
  end if;
  perform pg_temp.reg('3-otro-dni (D-25: bloquea igual)', v_txt);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 4. Convertido SIN persona (estado heredado: alta por la puerta real + conversión sembrada, como 3d del 2.4) ⇒
  --    `ya_es_cliente` a nombre del dueño de esa ficha, en el formato del verificador SIN `via` (decisión del ensayo: como el
  --    `ya_es_cliente` que el núcleo del 2.4 ya sintetiza para un convertido sin persona —R3-1, pieza B1—; `via = identidad`
  --    significa «reconocido por su documento» en el contrato de la app).
  --    4a activo, solo teléfono · 4b activo, teléfono + su DNI · 4c RETIRADO, teléfono + su DNI (el escenario exacto del 3d del
  --    oráculo del 2.4, que hoy CREA un segundo lead: D-22 lo cambia) · 4d sin dueño (cola global) ⇒ «sin asesor asignado» ·
  --    4e (con persona, pero fusionada y sin juicio) ⇒ el respaldo de D-21.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_c, 'CONVERTIDO CUATRO SIN PERSONA', pg_temp.tel(4), pg_temp.dni(4));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 4 sin persona (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c, false);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(4), pg_temp.dni(4)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» sobre el convertido sin persona 4';
  end if;
  v_esperado := jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1');
  v_ficha := pg_temp.ficha(v_c); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(4));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO CUATRO SOLO TELEFONO', pg_temp.tel(4), null);
  perform pg_temp.reg('4a-sin-persona-solo-telefono',
    pg_temp.exigir_bloqueo('4a-sin-persona-solo-telefono', v_res, v_esperado, v_c, v_ficha, null, null, v_huella, pg_temp.teln(4), v_n));
  -- 4b. Activo y sin persona, teléfono + su DNI (otro cliente, para que el ROJO de 4a no lo contamine).
  v_c := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_c, 'CONVERTIDO VEINTISEIS SIN PERSONA', pg_temp.tel(26), pg_temp.dni(26));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 4b sin persona (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c, false);
  v_ficha := pg_temp.ficha(v_c); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(26));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO VEINTISEIS CON SU DNI', pg_temp.tel(26), pg_temp.dni(26));
  perform pg_temp.reg('4b-sin-persona-telefono-y-dni',
    pg_temp.exigir_bloqueo('4b-sin-persona-telefono-y-dni', v_res, v_esperado, v_c, v_ficha, null, null, v_huella, pg_temp.teln(26), v_n));
  -- 4c. Retirado y sin persona, teléfono + su DNI (3d del 2.4).
  v_c := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_c, 'CONVERTIDO CINCO SIN PERSONA RETIRADO', pg_temp.tel(5), pg_temp.dni(5));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 4c (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c, true);
  v_ficha := pg_temp.ficha(v_c); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(5));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO CINCO CON SU DNI', pg_temp.tel(5), pg_temp.dni(5));
  perform pg_temp.reg('4c-sin-persona-retirado-telefono-y-dni (el 3d del 2.4)',
    pg_temp.exigir_bloqueo('4c-sin-persona-retirado-telefono-y-dni', v_res, v_esperado, v_c, v_ficha, null, null, v_huella, pg_temp.teln(5), v_n));
  -- 4d. Sin persona y sin dueño (Gerencia lo dejó en la cola global) ⇒ «sin asesor asignado».
  v_c := gen_random_uuid();
  v_res := pg_temp.alta(v_ger, v_c, 'CONVERTIDO SEIS SIN DUENO', pg_temp.tel(6), null);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado'
     or (select l.vendedor_id is not null or l.asignado_supervisor_id is not null or l.inversionista_id is not null from crm.leads l where l.id = v_c) then
    raise exception 'ENSAYO ABORTADO: no se pudo crear en la cola global el lead del caso 4d (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c, false);
  v_ficha := pg_temp.ficha(v_c); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(6));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO SEIS SOLO TELEFONO', pg_temp.tel(6), null);
  perform pg_temp.reg('4d-sin-persona-sin-dueno',
    pg_temp.exigir_bloqueo('4d-sin-persona-sin-dueno', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(6), v_n));

  -- 4e. Respaldo de D-21: el cliente está enlazado a una persona FUSIONADA en otra (estado heredado sembrado: la ficha sigue
  --     apuntando a la persona fusionada) y la canónica no tiene leads, ni conversión en curso, ni cuenta del Portal: el juicio
  --     de la canónica no dice nada (nulo) y la regla responde el mismo respaldo que ya usa el núcleo (`ya_es_cliente`,
  --     `sin asesor asignado`, `via = identidad`), nunca nulo (nulo dejaría llegar al INSERT).
  v_c := pg_temp.convertir_real(27, 'CLIENTE VEINTISIETE PERSONA FUSIONADA');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_otra := private.inversionista_resolver('DNI', pg_temp.dni(97), true, 'ensayo-bloque-2.7');
  if v_otra is null or v_otra = v_per then
    raise exception 'ENSAYO ABORTADO: no se pudo crear la persona canónica del caso 4e';
  end if;
  set local session_replication_role = replica;
  update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = v_otra, fusionado_en = clock_timestamp() where id = v_per;
  set local session_replication_role = origin;
  if private.inversionista_canonica(v_per) is distinct from v_otra
     or private.juicio_persona(private.inversionista_canonica(v_per), null) is not null
     or private.verificar_disponibilidad_lead_impl(pg_temp.teln(27), null) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el caso 4e no es el estado buscado (canónica %, juicio %, verificador %)', private.inversionista_canonica(v_per),
      private.juicio_persona(private.inversionista_canonica(v_per), null), private.verificar_disponibilidad_lead_impl(pg_temp.teln(27), null);
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(27));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO VEINTISIETE SOLO TELEFONO', pg_temp.tel(27), null);
  perform pg_temp.reg('4e-persona-fusionada-sin-juicio-respaldo-de-D-21',
    pg_temp.exigir_bloqueo('4e-persona-fusionada-sin-juicio-respaldo', v_res,
                           jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'),
                           v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(27), v_n));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 5. Persona VETADA.
  --    5a (bandera encendida): su dueño la marca «No contactar» por su puerta (`crm.marcar_no_contactar`, que veta a la
  --        persona y a sus leads) ⇒ `no_contactar`: lo da YA el verificador, antes del núcleo (medido).
  --    5b (bandera APAGADA dentro del rollback): la persona vetada y su lead SIN veto (estado heredado sembrado) ⇒ el
  --        verificador no la ve («libre») y la regla tiene que dar el juicio de la persona: `no_contactar`.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(7, 'CLIENTE SIETE VETADO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  begin
    perform pg_temp.sesion(v_vend1);
    perform crm.marcar_no_contactar(v_c, null);
    perform pg_temp.sesion(null);
  exception when others then
    raise exception 'ENSAYO ABORTADO: no se pudo marcar No contactar al cliente 7 (% %)', sqlstate, sqlerrm;
  end;
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(7), null);
  perform pg_temp.medida(format('5a (persona vetada por su puerta, bandera encendida; verificador solo teléfono): %s', v_esperado::text));
  if v_esperado ->> 'estado' <> 'no_contactar' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «no_contactar» sobre el cliente 7 vetado (%)', v_esperado;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(7));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO SIETE SOLO TELEFONO', pg_temp.tel(7), null);
  perform pg_temp.reg('5a-persona-vetada-bandera-encendida (lo da el verificador)',
    pg_temp.exigir_bloqueo('5a-persona-vetada-bandera-encendida', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(7), v_n));
  -- 5b. Bandera APAGADA (se apaga y se vuelve a encender dentro de esta transacción, como AR2-1 del 2.4).
  v_c := pg_temp.convertir_real(8, 'CLIENTE OCHO PERSONA VETADA');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  set local session_replication_role = replica;
  update crm.inversionistas set no_contactar = true, no_contactar_en = clock_timestamp(), no_contactar_por = v_vend1 where id = v_per;
  set local session_replication_role = origin;
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if private.resolver_en_puertas_bajo_candado() then
    raise exception 'ENSAYO ABORTADO: no se pudo apagar la bandera resolver_en_puertas dentro del ensayo (caso 5b)';
  end if;
  v_verif := private.verificar_disponibilidad_lead_impl(pg_temp.teln(8), null) ->> 'estado';
  perform pg_temp.medida(format('5b (bandera APAGADA, persona vetada y su lead sin veto; verificador solo teléfono): %s', v_verif));
  if v_verif <> 'libre' or (select l.no_contactar from crm.leads l where l.id = v_c) then
    raise exception 'ENSAYO ABORTADO: con la bandera apagada el verificador no dice «libre» sobre el cliente 8 (%): el caso no mediría el juicio de la regla', v_verif;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(8));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO OCHO SOLO TELEFONO', pg_temp.tel(8), null);
  perform pg_temp.reg('5b-persona-vetada-bandera-apagada (juicio de la persona)',
    pg_temp.exigir_bloqueo('5b-persona-vetada-bandera-apagada', v_res, jsonb_build_object('estado', 'no_contactar'),
                           v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(8), v_n));
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'ENSAYO ABORTADO: no se pudo volver a encender la bandera resolver_en_puertas (caso 5b)';
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 6. NEGATIVOS que no cambian (la respuesta EXACTA de hoy, nada escrito).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 6a. Cliente CON cuenta del Portal: el cliente 9 lo convirtió VEND2 (responsable VEND2) y el perfil cliente CLI1 (asesor
  --     VEND1) tiene ese teléfono (sembrado). El verificador ya responde `ya_es_cliente` por el Portal (asesor VEND1, sin `via`):
  --     esa respuesta, exacta (la regla no puede adelantarse con otro asesor).
  v_c := pg_temp.convertir_real(9, 'CLIENTE NUEVE CON PORTAL', v_vend2);
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  set local session_replication_role = replica;
  update public.perfiles set telefono = pg_temp.tel(9) where id = v_cli1;
  set local session_replication_role = origin;
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(9), null);
  perform pg_temp.medida(format('6a (cliente con cuenta del Portal; verificador solo teléfono): %s', v_esperado::text));
  if v_esperado is distinct from jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1') then
    raise exception 'ENSAYO ABORTADO: el verificador no reconoce al cliente 9 por su cuenta del Portal (%)', v_esperado;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(9));
  v_res := pg_temp.alta(v_vend3, gen_random_uuid(), 'REINGRESO NUEVE SOLO TELEFONO', pg_temp.tel(9), null);
  perform pg_temp.reg('6a-cuenta-del-portal (veredicto de hoy)',
    pg_temp.exigir_bloqueo('6a-cuenta-del-portal', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(9), v_n));
  -- 6b. Teléfono Y DNI del cliente: el camino de identidad de hoy (el verificador, `via = identidad`).
  v_c := pg_temp.convertir_real(10, 'CLIENTE DIEZ');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(10), pg_temp.dni(10));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(10));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO DIEZ CON SU DNI', pg_temp.tel(10), pg_temp.dni(10));
  perform pg_temp.reg('6b-telefono-y-dni-del-cliente (camino de identidad de hoy)',
    pg_temp.exigir_bloqueo('6b-telefono-y-dni-del-cliente', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(10), v_n));
  -- 6c. Retirado NO convertido ⇒ se sigue reactivando (2.4 intacto): misma ficha, dueño VEND2, un solo lead con ese teléfono.
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA ONCE RETIRADA', pg_temp.tel(11), pg_temp.dni(11));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso 6c (%)', v_res;
  end if;
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO ONCE', pg_temp.tel(11), pg_temp.dni(11));
  v_txt := '';
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_otra then
    v_txt := format(E'FALLO 6c-retirado-no-convertido-se-reactiva: se esperaba «reutilizado» con la ficha retirada y llegó %s\n', v_res);
  elsif (select l.activo::text || '|' || l.vendedor_id::text from crm.leads l where l.id = v_otra) is distinct from 'true|' || v_vend2::text
        or (select count(*) from crm.leads l where l.telefono = pg_temp.teln(11)) <> 1
        or not exists (select 1 from crm.actividades a where a.id = v_pid and a.lead_id = v_otra and a.metadata ->> 'evento' = 'reactivacion_alta') then
    v_txt := E'FALLO 6c-retirado-no-convertido-se-reactiva: la ficha no quedó activa a nombre de VEND2 con su rastro, o hay más de un lead con ese teléfono\n';
  end if;
  perform pg_temp.reg('6c-retirado-no-convertido-se-reactiva (2.4 intacto)', v_txt);
  -- 6d. Teléfono nuevo ⇒ `creado`.
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'PERSONA NUEVA DOCE', pg_temp.tel(12), null);
  perform pg_temp.reg('6d-telefono-nuevo-creado',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'creado' and (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid = v_pid
              and (select count(*) from crm.leads l where l.telefono = pg_temp.teln(12)) = 1 then ''
         else format(E'FALLO 6d-telefono-nuevo-creado: se esperaba «creado» con el id del alta y llegó %s\n', v_res) end);
  -- 6e. Un lead ACTIVO VIVO comparte el teléfono con un cliente (duplicado heredado de D-23/D-25, sembrado) ⇒ el veredicto de
  --     hoy, exacto (`tomado` nombrando a VEND1); el cliente y el duplicado intactos.
  v_c := pg_temp.convertir_real(13, 'CLIENTE TRECE');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_otra := pg_temp.sembrado(13, 'DUPLICADO ACTIVO TRECE', true, 'contactado');
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(13), null);
  if v_esperado ->> 'estado' <> 'tomado' or v_esperado ->> 'vendedor' is distinct from 'PASO08 VEND1' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «tomado» (VEND1) sobre el duplicado activo del cliente 13 (%)', v_esperado;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(13));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO TRECE SOLO TELEFONO', pg_temp.tel(13), null);
  perform pg_temp.reg('6e-lead-activo-vivo-tomado (veredicto de hoy)',
    pg_temp.exigir_bloqueo('6e-lead-activo-vivo-tomado', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(13), v_n,
                           v_otra, v_otra_antes));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 7. PRECEDENCIA: el convertido gana a cualquier retirado no convertido que case por teléfono o DNI (y no se reactiva).
  --    Con el cliente RETIRADO la rama del 2.4 REACTIVARÍA al otro retirado (hoy: `reutilizado`, el cliente recibe un lead
  --    activo nuevo); con el cliente ACTIVO, el paso 3a del 2.4 devuelve nulo y el alta INSERTA (hoy: `creado`).
  --    7a el mismo teléfono, cliente retirado · 7a2 el mismo teléfono, cliente activo · 7b el retirado casa solo por el DNI
  --    tecleado (cliente retirado) · 7c el retirado está DESCARTADO con la espera vigente (el verificador dice «enfriamiento»;
  --    D-15 lo reactivaría; cliente retirado) · 7d (decisión del ensayo) un DESCARTADO ACTIVO con la espera vigente comparte
  --    el teléfono con un cliente activo: «enfriamiento» pasa a `ya_es_cliente` (los dos bloquean; manda D-22).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(14, 'CLIENTE CATORCE RETIRADO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente 14'; end if;
  v_otra := pg_temp.sembrado(14, 'RETIRADO CATORCE MISMO TELEFONO', false, 'contactado');
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(14), pg_temp.dni(14));
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(14), null) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» sobre el teléfono 14 (cliente + retirado)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(14));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO CATORCE SOLO TELEFONO', pg_temp.tel(14), null);
  perform pg_temp.reg('7a-precedencia-por-telefono',
    pg_temp.exigir_bloqueo('7a-precedencia-por-telefono', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(14), v_n,
                           v_otra, v_otra_antes));
  -- 7a2. El mismo teléfono con el cliente ACTIVO (hoy el alta inserta otro lead; con la regla, el cliente gana).
  v_c := pg_temp.convertir_real(16, 'CLIENTE DIECISEIS ACTIVO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_otra := pg_temp.sembrado(16, 'RETIRADO DIECISEIS MISMO TELEFONO', false, 'contactado');
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(16), pg_temp.dni(16));
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(16), null) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» sobre el teléfono 16 (cliente activo + retirado)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(16));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO DIECISEIS SOLO TELEFONO', pg_temp.tel(16), null);
  perform pg_temp.reg('7a2-precedencia-por-telefono-cliente-activo',
    pg_temp.exigir_bloqueo('7a2-precedencia-por-telefono-cliente-activo', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella,
                           pg_temp.teln(16), v_n, v_otra, v_otra_antes));
  -- 7b. El retirado casa solo por el DNI tecleado (su teléfono es otro); el cliente está retirado.
  v_c := pg_temp.convertir_real(15, 'CLIENTE QUINCE RETIRADO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente 15'; end if;
  v_otra := pg_temp.sembrado(95, 'RETIRADO NOVENTA Y CINCO', false, 'contactado', pg_temp.dni(95));
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(15), pg_temp.dni(15));
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(15), pg_temp.dni(95)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» sobre el teléfono 15 con el DNI del retirado';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(15));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO QUINCE CON EL DNI DEL RETIRADO', pg_temp.tel(15), pg_temp.dni(95));
  perform pg_temp.reg('7b-precedencia-por-dni',
    pg_temp.exigir_bloqueo('7b-precedencia-por-dni', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(15), v_n,
                           v_otra, v_otra_antes));
  -- 7c. El retirado del mismo teléfono está DESCARTADO con la espera vigente (`sin_fondos`, 90 días): el verificador dice
  --     «enfriamiento» y la rama del 2.4 (D-15) lo reactivaría (el cliente está retirado); el cliente gana.
  v_c := pg_temp.convertir_real(17, 'CLIENTE DIECISIETE RETIRADO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente 17'; end if;
  v_otra := pg_temp.sembrado(17, 'RETIRADO DESCARTADO DIECISIETE', false, 'descartado', null, 'sin_fondos');
  v_verif := private.verificar_disponibilidad_lead_impl(pg_temp.teln(17), null) ->> 'estado';
  perform pg_temp.medida(format('7c (cliente + retirado descartado con espera vigente; verificador solo teléfono): %s', v_verif));
  if v_verif <> 'enfriamiento' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «enfriamiento» sobre el teléfono 17 (%)', v_verif;
  end if;
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(17), pg_temp.dni(17));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(17));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO DIECISIETE SOLO TELEFONO', pg_temp.tel(17), null);
  perform pg_temp.reg('7c-precedencia-sobre-el-retirado-en-enfriamiento',
    pg_temp.exigir_bloqueo('7c-precedencia-sobre-el-retirado-en-enfriamiento', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella,
                           pg_temp.teln(17), v_n, v_otra, v_otra_antes));
  -- 7d. (decisión del ensayo) Un DESCARTADO ACTIVO con la espera vigente comparte el teléfono con el cliente (duplicado
  --     heredado, sembrado): hoy «enfriamiento»; con la regla, `ya_es_cliente` (el juicio de la persona). Nada escrito.
  v_c := pg_temp.convertir_real(18, 'CLIENTE DIECIOCHO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_otra := pg_temp.sembrado(18, 'DESCARTADO ACTIVO DIECIOCHO', true, 'descartado', null, 'sin_fondos');
  v_verif := private.verificar_disponibilidad_lead_impl(pg_temp.teln(18), null) ->> 'estado';
  perform pg_temp.medida(format('7d (cliente + descartado ACTIVO con espera vigente; verificador solo teléfono): %s', v_verif));
  if v_verif <> 'enfriamiento' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «enfriamiento» sobre el teléfono 18 (%)', v_verif;
  end if;
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(18), pg_temp.dni(18));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(18));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO DIECIOCHO SOLO TELEFONO', pg_temp.tel(18), null);
  perform pg_temp.reg('7d-el-cliente-gana-al-enfriamiento-de-un-descartado-activo (decisión del ensayo)',
    pg_temp.exigir_bloqueo('7d-el-cliente-gana-al-enfriamiento-de-un-descartado-activo', v_res, v_esperado, v_c, v_ficha, v_per, v_pers,
                           v_huella, pg_temp.teln(18), v_n, v_otra, v_otra_antes));
  perform pg_temp.medida(format('7d (alta solo por teléfono): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 8. REINTENTO del 2.4 con el mismo p_id ⇒ idéntico a hoy, aunque el teléfono sea ya también de un cliente convertido
  --    (duplicado heredado, sembrado SIN persona después de la primera reactivación).
  --    8a: (i) la ficha sigue activa ⇒ `reutilizado` con la misma ficha; (ii) Gerencia la retira otra vez ⇒ el reintento la
  --        reactiva de nuevo (`reutilizado`, misma ficha, segundo rastro con alta_id = p_id) y el cliente queda intacto.
  --    8b: el cliente heredado está ACTIVO ⇒ el reintento tras el segundo retiro sigue en 22023 «el alta original ya no se
  --        puede repetir» (R4-1 del 2.4), no en `ya_es_cliente`.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA DIECINUEVE RETIRADA', pg_temp.tel(19), pg_temp.dni(19));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso 8a (%)', v_res;
  end if;
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO DIECINUEVE', pg_temp.tel(19), pg_temp.dni(19));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'reutilizado' then
    raise exception 'ENSAYO ABORTADO: la primera reactivación del caso 8a no ocurrió (%): el 2.4 no está en este laboratorio', v_res;
  end if;
  v_c := pg_temp.sembrado(19, 'CLIENTE HEREDADO DIECINUEVE', false, 'convertido', null, null, v_vend3);
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO DIECINUEVE', pg_temp.tel(19), pg_temp.dni(19));
  v_txt := '';
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_otra then
    v_txt := format(E'FALLO 8a-reintento-con-la-ficha-activa: se esperaba «reutilizado» con la misma ficha (lo de hoy) y llegó %s\n', v_res);
  elsif pg_temp.ficha(v_c) is distinct from v_ficha or pg_temp.ficha(v_otra) is distinct from v_otra_antes or pg_temp.huella_escritura() is distinct from v_huella then
    v_txt := E'FALLO 8a-reintento-con-la-ficha-activa: el reintento escribió algo\n';
  end if;
  perform pg_temp.reg('8a-reintento-con-la-ficha-activa (idéntico a hoy)', v_txt);
  if pg_temp.retirar(v_ger, v_otra) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha del caso 8a'; end if;
  v_ficha := pg_temp.ficha(v_c);
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO DIECINUEVE', pg_temp.tel(19), pg_temp.dni(19));
  v_txt := '';
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_otra then
    v_txt := format(E'FALLO 8a-reintento-tras-segundo-retiro: se esperaba «reutilizado» con la ficha del primer rastro (lo de hoy, R2-1 del 2.4) y llegó %s\n', v_res);
  elsif not (select l.activo from crm.leads l where l.id = v_otra)
        or not exists (select 1 from crm.actividades a where a.lead_id = v_otra and a.id <> v_pid
                         and a.metadata ->> 'evento' = 'reactivacion_alta' and (a.metadata ->> 'alta_id')::uuid = v_pid)
        or pg_temp.ficha(v_c) is distinct from v_ficha then
    v_txt := E'FALLO 8a-reintento-tras-segundo-retiro: la ficha no volvió activa con su segundo rastro, o el cliente heredado cambió\n';
  end if;
  perform pg_temp.reg('8a-reintento-tras-segundo-retiro (idéntico a hoy)', v_txt);
  perform pg_temp.medida(format('8a (reintento tras el segundo retiro, cliente heredado del mismo teléfono): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- 8b. El cliente heredado está ACTIVO.
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA VEINTE RETIRADA', pg_temp.tel(20), pg_temp.dni(20));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso 8b (%)', v_res;
  end if;
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO VEINTE', pg_temp.tel(20), pg_temp.dni(20));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'reutilizado' then
    raise exception 'ENSAYO ABORTADO: la primera reactivación del caso 8b no ocurrió (%)', v_res;
  end if;
  v_c := pg_temp.sembrado(20, 'CLIENTE HEREDADO VEINTE ACTIVO', true, 'convertido', null, null, v_vend3);
  if pg_temp.retirar(v_ger, v_otra) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha del caso 8b'; end if;
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(20));
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO VEINTE', pg_temp.tel(20), pg_temp.dni(20));
  perform pg_temp.reg('8b-reintento-con-cliente-activo-sigue-en-22023 (idéntico a hoy)',
    pg_temp.exigir_bloqueo('8b-reintento-con-cliente-activo-sigue-en-22023', v_res,
                           jsonb_build_object('error', '22023', 'mensaje', 'El alta original ya no se puede repetir'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(20), v_n, v_otra, v_otra_antes));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 9. Roles sin permiso siguen en 42501 (antes de mirar nada) y la ficha del cliente no se toca; la puerta del documento
  --    (CE) con el teléfono de un cliente también responde «ya es cliente» y no fija documento ni crea identidad.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(21, 'CLIENTE VEINTIUNO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(21));
  v_res := pg_temp.alta(v_coord, gen_random_uuid(), 'INTENTO COORD', pg_temp.tel(21), null);
  perform pg_temp.reg('9-coordinador-42501', pg_temp.exigir_bloqueo('9-coordinador-42501', v_res, jsonb_build_object('error', '42501'),
                                                                     v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(21), v_n));
  v_res := pg_temp.alta(v_inactivo, gen_random_uuid(), 'INTENTO INACTIVO', pg_temp.tel(21), null);
  perform pg_temp.reg('9-inactivo-42501', pg_temp.exigir_bloqueo('9-inactivo-42501', v_res, jsonb_build_object('error', '42501'),
                                                                  v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(21), v_n));
  v_res := pg_temp.alta(v_admin, gen_random_uuid(), 'INTENTO ADMIN SIN CRM', pg_temp.tel(21), null);
  perform pg_temp.reg('9-admin-sin-crm-42501', pg_temp.exigir_bloqueo('9-admin-sin-crm-42501', v_res, jsonb_build_object('error', '42501'),
                                                                       v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(21), v_n));
  -- 9e. Puerta del documento con CE y el teléfono de un cliente.
  v_c := pg_temp.convertir_real(22, 'CLIENTE VEINTIDOS');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(22), pg_temp.dni(22));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(22));
  v_res := pg_temp.alta_doc(v_vend2, jsonb_build_object('id', gen_random_uuid(), 'nombre_completo', 'OTRA PERSONA CON CE',
             'telefono', pg_temp.tel(22), 'origen', 'formulario', 'monto_estimado', 5000, 'moneda', 'PEN'), 'CE', '001234567');
  perform pg_temp.reg('9e-documento-ce-con-el-telefono-de-un-cliente',
    pg_temp.exigir_bloqueo('9e-documento-ce', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(22), v_n));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 11. D-27 (ronda 2): el DNI de un cliente YA CONVERTIDO también lo reconoce, aunque el teléfono tecleado sea otro (nuevo).
  --     11a sin persona, activo · 11b sin persona, retirado · 11c/11d con persona, activo/retirado, con la bandera APAGADA (el
  --     verificador no consulta identidades: la regla da el juicio de la persona) · 11e con persona y bandera encendida: lo
  --     bloquea YA el verificador por la identidad (medido; no cambia) · 11f el DNI de quien NO es cliente sigue su camino de hoy
  --     (retirado no convertido ⇒ se reactiva; persona sin lead ⇒ `creado` enlazado; lead activo ⇒ `tomado`) · 11g el teléfono
  --     manda sobre el DNI · 11h el DNI manda sobre el candidato retirado del 2.4 · 11i el reintento del 2.4 no cambia aunque el
  --     DNI sea de un cliente convertido.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 11a. Sin persona, activo (alta real + conversión sembrada); VEND2 teclea su DNI con un teléfono nuevo.
  v_c := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_c, 'CONVERTIDO TREINTA SIN PERSONA', pg_temp.tel(30), pg_temp.dni(30));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 11a (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c, false);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(31), pg_temp.dni(30)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» con el DNI del convertido sin persona 30 y un teléfono nuevo';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO TREINTA CON SU DNI Y OTRO TELEFONO', pg_temp.tel(31), pg_temp.dni(30));
  v_txt := pg_temp.exigir_bloqueo('11a-dni-sin-persona-activo', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1'),
                                  v_c, v_ficha, null, null, v_huella, pg_temp.teln(31), 0);
  if (select count(*) from crm.leads l where l.dni = pg_temp.dni(30)) <> 1 then
    v_txt := v_txt || format(E'FALLO 11a-dni-sin-persona-activo: %s leads con el DNI del cliente (debe ser 1)\n', (select count(*) from crm.leads l where l.dni = pg_temp.dni(30)));
  end if;
  perform pg_temp.reg('11a-dni-sin-persona-activo (D-27)', v_txt);
  -- 11b. Sin persona, retirado.
  v_c := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_c, 'CONVERTIDO TREINTA Y DOS SIN PERSONA RETIRADO', pg_temp.tel(32), pg_temp.dni(32));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 11b (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c, true);
  v_ficha := pg_temp.ficha(v_c); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO TREINTA Y DOS CON SU DNI Y OTRO TELEFONO', pg_temp.tel(33), pg_temp.dni(32));
  v_txt := pg_temp.exigir_bloqueo('11b-dni-sin-persona-retirado', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1'),
                                  v_c, v_ficha, null, null, v_huella, pg_temp.teln(33), 0);
  if (select count(*) from crm.leads l where l.dni = pg_temp.dni(32)) <> 1 then
    v_txt := v_txt || format(E'FALLO 11b-dni-sin-persona-retirado: %s leads con el DNI del cliente (debe ser 1)\n', (select count(*) from crm.leads l where l.dni = pg_temp.dni(32)));
  end if;
  perform pg_temp.reg('11b-dni-sin-persona-retirado (D-27)', v_txt);
  -- 11c/11d. Con persona (conversión real), activo y retirado, con la bandera APAGADA dentro del rollback: el verificador no mira
  --     identidades y dice «libre»; la regla del DNI da el juicio de la persona (el mismo que con la bandera encendida).
  v_c := pg_temp.convertir_real(34, 'CLIENTE TREINTA Y CUATRO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_c2 := pg_temp.convertir_real(36, 'CLIENTE TREINTA Y SEIS RETIRADO');
  v_per2 := (select l.inversionista_id from crm.leads l where l.id = v_c2);
  if pg_temp.retirar(v_ger, v_c2) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente 36'; end if;
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(35), pg_temp.dni(34));
  if v_esperado ->> 'estado' <> 'ya_es_cliente' or v_esperado ->> 'via' is distinct from 'identidad'
     or private.verificar_disponibilidad_lead_impl(pg_temp.teln(37), pg_temp.dni(36)) is distinct from v_esperado then
    raise exception 'ENSAYO ABORTADO: con la bandera encendida el verificador no da el juicio de identidad de los clientes 34/36 por su DNI (%)', v_esperado;
  end if;
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if private.resolver_en_puertas_bajo_candado() then
    raise exception 'ENSAYO ABORTADO: no se pudo apagar la bandera resolver_en_puertas dentro del ensayo (casos 11c/11d)';
  end if;
  v_verif := private.verificar_disponibilidad_lead_impl(pg_temp.teln(35), pg_temp.dni(34)) ->> 'estado';
  perform pg_temp.medida(format('11c (bandera APAGADA; verificador con el DNI del cliente 34 y un teléfono nuevo): %s', v_verif));
  if v_verif <> 'libre' or private.verificar_disponibilidad_lead_impl(pg_temp.teln(37), pg_temp.dni(36)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: con la bandera apagada el verificador no dice «libre» con el DNI de los clientes 34/36 (%): el caso no mediría la regla', v_verif;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO TREINTA Y CUATRO CON SU DNI', pg_temp.tel(35), pg_temp.dni(34));
  perform pg_temp.reg('11c-dni-con-persona-activo-bandera-apagada (D-27; juicio de la persona)',
    pg_temp.exigir_bloqueo('11c-dni-con-persona-activo', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(35), 0));
  v_ficha2 := pg_temp.ficha(v_c2); v_pers2 := pg_temp.persona(v_per2); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO TREINTA Y SEIS CON SU DNI', pg_temp.tel(37), pg_temp.dni(36));
  perform pg_temp.reg('11d-dni-con-persona-retirado-bandera-apagada (D-27; juicio de la persona)',
    pg_temp.exigir_bloqueo('11d-dni-con-persona-retirado', v_res, v_esperado, v_c2, v_ficha2, v_per2, v_pers2, v_huella, pg_temp.teln(37), 0));
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'ENSAYO ABORTADO: no se pudo volver a encender la bandera resolver_en_puertas (casos 11c/11d)';
  end if;
  -- 11e. Con persona y la bandera encendida: el DNI lo bloquea YA el verificador (camino de identidad de hoy), exacto.
  v_c := pg_temp.convertir_real(38, 'CLIENTE TREINTA Y OCHO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(39), pg_temp.dni(38));
  perform pg_temp.medida(format('11e (bandera encendida; verificador con el DNI del cliente 38 y un teléfono nuevo): %s', v_esperado::text));
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO TREINTA Y OCHO CON SU DNI', pg_temp.tel(39), pg_temp.dni(38));
  perform pg_temp.reg('11e-dni-con-persona-bandera-encendida (lo da el verificador)',
    pg_temp.exigir_bloqueo('11e-dni-con-persona-bandera-encendida', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(39), 0));
  -- 11f. El DNI de quien NO es cliente sigue su camino de hoy.
  --  (i) el DNI de un RETIRADO no convertido, con otro teléfono ⇒ el 2.4 reactiva esa ficha (`reutilizado`, dueño VEND2).
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA CUARENTA RETIRADA', pg_temp.tel(40), pg_temp.dni(40));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso 11f-i (%)', v_res;
  end if;
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO CUARENTA POR SU DNI', pg_temp.tel(41), pg_temp.dni(40));
  perform pg_temp.reg('11f-i-dni-de-un-retirado-no-convertido-se-reactiva (2.4 intacto)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado' and (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid = v_otra
              and (select l.activo::text || '|' || l.vendedor_id::text from crm.leads l where l.id = v_otra) = 'true|' || v_vend2::text
              and (select count(*) from crm.leads l where l.dni = pg_temp.dni(40)) = 1 and not exists (select 1 from crm.leads l where l.telefono = pg_temp.teln(41)) then ''
         else format(E'FALLO 11f-i-dni-de-un-retirado-no-convertido: se esperaba «reutilizado» con la ficha retirada (dueño VEND2, un solo lead con ese DNI) y llegó %s\n', v_res) end);
  --  (ii) el DNI de una PERSONA sin lead ⇒ `creado` y el lead nace enlazado a ella.
  v_per := private.inversionista_resolver('DNI', pg_temp.dni(42), true, 'ensayo-bloque-2.7');
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'PERSONA CUARENTA Y DOS SIN LEAD', pg_temp.tel(42), pg_temp.dni(42));
  perform pg_temp.reg('11f-ii-dni-de-una-persona-sin-lead-creado',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'creado' and (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid = v_pid
              and (select l.inversionista_id from crm.leads l where l.id = v_pid) is not distinct from v_per then ''
         else format(E'FALLO 11f-ii-dni-de-una-persona-sin-lead: se esperaba «creado» y enlazado a su persona y llegó %s\n', v_res) end);
  --  (iii) el DNI de un lead ACTIVO no convertido, con otro teléfono ⇒ el veredicto de hoy (`tomado` nombrando a VEND1), exacto.
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'LEAD ACTIVO CUARENTA Y TRES', pg_temp.tel(43), pg_temp.dni(43));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead activo del caso 11f-iii (%)', v_res;
  end if;
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(44), pg_temp.dni(43));
  if v_esperado ->> 'estado' <> 'tomado' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «tomado» con el DNI del lead activo 43 (%)', v_esperado;
  end if;
  v_ficha := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'OTRO CON EL DNI CUARENTA Y TRES', pg_temp.tel(44), pg_temp.dni(43));
  perform pg_temp.reg('11f-iii-dni-de-un-lead-activo-tomado (veredicto de hoy)',
    pg_temp.exigir_bloqueo('11f-iii-dni-de-un-lead-activo', v_res, v_esperado, v_otra, v_ficha, null, null, v_huella, pg_temp.teln(44), 0));
  -- 11g. El TELÉFONO manda sobre el DNI: el teléfono es del cliente 45 (con persona, de VEND1) y el DNI tecleado es de otro
  --     convertido SIN persona (de VEND3) ⇒ el juicio de la persona del teléfono, no el dueño del DNI.
  v_c := pg_temp.convertir_real(45, 'CLIENTE CUARENTA Y CINCO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_c2 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend3, v_c2, 'CONVERTIDO CUARENTA Y SEIS SIN PERSONA', pg_temp.tel(46), pg_temp.dni(46));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or (select l.inversionista_id from crm.leads l where l.id = v_c2) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 11g (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c2, false);
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(45), pg_temp.dni(45));
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(45), pg_temp.dni(46)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» con el teléfono 45 y el DNI 46';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(45));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'TELEFONO CUARENTA Y CINCO CON EL DNI CUARENTA Y SEIS', pg_temp.tel(45), pg_temp.dni(46));
  perform pg_temp.reg('11g-el-telefono-manda-sobre-el-dni',
    pg_temp.exigir_bloqueo('11g-el-telefono-manda-sobre-el-dni', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(45), v_n,
                           v_c2, v_otra_antes));
  -- 11h. El DNI manda sobre el candidato retirado del 2.4: el teléfono es de un RETIRADO no convertido y el DNI de un cliente
  --     convertido sin persona y RETIRADO (con el cliente retirado la rama del 2.4 reactivaría al otro: hoy `reutilizado`) ⇒
  --     `ya_es_cliente` (el dueño del cliente); el retirado no se reactiva.
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA CUARENTA Y SIETE RETIRADA', pg_temp.tel(47), null);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso 11h (%)', v_res;
  end if;
  v_c := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_c, 'CONVERTIDO CUARENTA Y OCHO SIN PERSONA RETIRADO', pg_temp.tel(48), pg_temp.dni(48));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 11h (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_c, true);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(47), pg_temp.dni(48)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» con el teléfono del retirado 47 y el DNI del cliente 48';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_otra); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(47));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'TELEFONO CUARENTA Y SIETE CON EL DNI CUARENTA Y OCHO', pg_temp.tel(47), pg_temp.dni(48));
  perform pg_temp.reg('11h-el-dni-manda-sobre-el-candidato-retirado',
    pg_temp.exigir_bloqueo('11h-el-dni-manda-sobre-el-candidato-retirado', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(47), v_n, v_otra, v_otra_antes));
  -- 11i. El REINTENTO del 2.4 no cambia aunque el DNI tecleado sea también el de un cliente convertido (heredado, sembrado sin
  --     persona con OTRO teléfono después de la primera reactivación): tras el segundo retiro, `reutilizado` con la misma ficha.
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA CUARENTA Y NUEVE RETIRADA', pg_temp.tel(49), pg_temp.dni(49));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso 11i (%)', v_res;
  end if;
  v_pid2 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid2, 'REINGRESO CUARENTA Y NUEVE', pg_temp.tel(49), pg_temp.dni(49));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'reutilizado' then
    raise exception 'ENSAYO ABORTADO: la primera reactivación del caso 11i no ocurrió (%)', v_res;
  end if;
  v_c := pg_temp.sembrado(50, 'CLIENTE HEREDADO CINCUENTA CON EL DNI CUARENTA Y NUEVE', false, 'convertido', pg_temp.dni(49), null, v_vend3);
  if pg_temp.retirar(v_ger, v_otra) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha del caso 11i'; end if;
  v_ficha := pg_temp.ficha(v_c);
  v_res := pg_temp.alta(v_vend2, v_pid2, 'REINGRESO CUARENTA Y NUEVE', pg_temp.tel(49), pg_temp.dni(49));
  v_txt := '';
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_otra then
    v_txt := format(E'FALLO 11i-reintento-con-el-dni-de-un-cliente: se esperaba «reutilizado» con la ficha del primer rastro (lo de hoy) y llegó %s\n', v_res);
  elsif not (select l.activo from crm.leads l where l.id = v_otra) or pg_temp.ficha(v_c) is distinct from v_ficha then
    v_txt := E'FALLO 11i-reintento-con-el-dni-de-un-cliente: la ficha no volvió activa o el cliente heredado cambió\n';
  end if;
  perform pg_temp.reg('11i-reintento-con-el-dni-de-un-cliente (idéntico a hoy)', v_txt);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 12. Ronda 3 (Codex P2): PRIORIDAD entre varios convertidos que casan (duplicados heredados, sembrados; los enlazados nacen por
  --     la conversión real), con asesores distintos: primero el ENLAZADO a persona, luego el ACTIVO, luego el convertido MÁS RECIENTE.
  --     Cada caso aísla un criterio (el que pierde gana en los criterios siguientes), por teléfono (12a–12c) y por DNI (12d–12f).
  --     Ronda 4 (revisión 2 del auditor): DESEMPATES deterministas. 12c/12f siembran con ids FIJOS, el menor para el que debe
  --     perder: si la fecha dejara de decidir, desempataría `l.id` y el caso caería siempre (con ids aleatorios, solo a veces).
  --     12g/12h enfrentan un convertido SIN fecha a uno con fecha (`convertido_en desc nulls last`: gana el que la tiene), también
  --     con el id menor para el que debe perder. Ids: `ffffffff-0027-…` el que debe ganar, `00000000-0027-…` el que debe perder; el
  --     último grupo nombra el caso (1203 = 12c, 1206 = 12f, 1207 = 12g, 1208 = 12h).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 12a. Teléfono: el ENLAZADO gana aunque esté retirado y su conversión sea más antigua; el otro (sin persona, activo, reciente, de
  --      VEND3) pierde.
  v_c := pg_temp.convertir_real(60, 'CLIENTE SESENTA ENLAZADO RETIRADO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente 60'; end if;
  set local session_replication_role = replica;
  update crm.leads set convertido_en = clock_timestamp() - interval '30 days' where id = v_c;
  set local session_replication_role = origin;
  v_c2 := pg_temp.sembrado(60, 'CONVERTIDO SESENTA SIN PERSONA ACTIVO RECIENTE', true, 'convertido', null, null, v_vend3, clock_timestamp() - interval '1 day');
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(60), pg_temp.dni(60));
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(60), null) ->> 'estado' <> 'libre' or v_esperado ->> 'asesor' is distinct from 'PASO08 VEND1' then
    raise exception 'ENSAYO ABORTADO: el caso 12a no es el estado buscado (verificador solo teléfono %, juicio %)',
      private.verificar_disponibilidad_lead_impl(pg_temp.teln(60), null), v_esperado;
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(60));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO SESENTA SOLO TELEFONO', pg_temp.tel(60), null);
  perform pg_temp.reg('12a-telefono-gana-el-enlazado',
    pg_temp.exigir_bloqueo('12a-telefono-gana-el-enlazado', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(60), v_n,
                           v_c2, v_otra_antes));
  -- 12b. Teléfono, dos SIN persona: el ACTIVO (VEND1, más antiguo) gana al retirado (VEND3, más reciente).
  v_c := pg_temp.sembrado(61, 'CONVERTIDO SESENTA Y UNO ACTIVO ANTIGUO', true, 'convertido', null, null, v_vend1, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(61, 'CONVERTIDO SESENTA Y UNO RETIRADO RECIENTE', false, 'convertido', null, null, v_vend3, clock_timestamp() - interval '1 day');
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(61));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO SESENTA Y UNO SOLO TELEFONO', pg_temp.tel(61), null);
  perform pg_temp.reg('12b-telefono-gana-el-activo',
    pg_temp.exigir_bloqueo('12b-telefono-gana-el-activo', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(61), v_n, v_c2, v_otra_antes));
  -- 12c. Teléfono, dos SIN persona y ACTIVOS: el convertido MÁS RECIENTE (VEND3) gana al más antiguo (VEND1). Ids fijos (ronda 4):
  --      el menor para el más antiguo, el que debe perder.
  v_c := pg_temp.sembrado(62, 'CONVERTIDO SESENTA Y DOS ACTIVO RECIENTE', true, 'convertido', null, null, v_vend3, clock_timestamp() - interval '1 day',
                          p_id => 'ffffffff-0027-4000-8000-000000001203');
  v_c2 := pg_temp.sembrado(62, 'CONVERTIDO SESENTA Y DOS ACTIVO ANTIGUO', true, 'convertido', null, null, v_vend1, clock_timestamp() - interval '10 days',
                           p_id => '00000000-0027-4000-8000-000000001203');
  if not v_c2 < v_c then
    raise exception 'ENSAYO ABORTADO: los ids fijos del caso 12c no favorecen al que debe perder (el desempate por id dejaría de ser determinista)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(62));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO SESENTA Y DOS SOLO TELEFONO', pg_temp.tel(62), null);
  perform pg_temp.reg('12c-telefono-gana-el-mas-reciente',
    pg_temp.exigir_bloqueo('12c-telefono-gana-el-mas-reciente', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND3'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(62), v_n, v_c2, v_otra_antes));
  -- 12d. DNI (con un teléfono nuevo), bandera APAGADA para que el verificador no se adelante con la identidad: el ENLAZADO (retirado,
  --      antiguo, VEND1) gana al sin persona (activo, reciente, VEND3) que comparte su DNI.
  v_c := pg_temp.convertir_real(63, 'CLIENTE SESENTA Y TRES ENLAZADO RETIRADO');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente 63'; end if;
  set local session_replication_role = replica;
  update crm.leads set convertido_en = clock_timestamp() - interval '30 days' where id = v_c;
  set local session_replication_role = origin;
  v_c2 := pg_temp.sembrado(64, 'CONVERTIDO SESENTA Y CUATRO SIN PERSONA CON EL DNI SESENTA Y TRES', true, 'convertido', pg_temp.dni(63), null, v_vend3,
                           clock_timestamp() - interval '1 day');
  v_esperado := private.verificar_disponibilidad_lead_impl(pg_temp.teln(65), pg_temp.dni(63));
  if v_esperado ->> 'estado' <> 'ya_es_cliente' or v_esperado ->> 'asesor' is distinct from 'PASO08 VEND1' then
    raise exception 'ENSAYO ABORTADO: con la bandera encendida el verificador no da el juicio de la persona 63 por su DNI (%)', v_esperado;
  end if;
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if private.resolver_en_puertas_bajo_candado() or private.verificar_disponibilidad_lead_impl(pg_temp.teln(65), pg_temp.dni(63)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: con la bandera apagada el verificador no dice «libre» con el DNI 63 (caso 12d)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_pers := pg_temp.persona(v_per); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'OTRO TELEFONO CON EL DNI SESENTA Y TRES', pg_temp.tel(65), pg_temp.dni(63));
  perform pg_temp.reg('12d-dni-gana-el-enlazado',
    pg_temp.exigir_bloqueo('12d-dni-gana-el-enlazado', v_res, v_esperado, v_c, v_ficha, v_per, v_pers, v_huella, pg_temp.teln(65), 0,
                           v_c2, v_otra_antes));
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'ENSAYO ABORTADO: no se pudo volver a encender la bandera resolver_en_puertas (caso 12d)';
  end if;
  -- 12e. DNI, dos SIN persona: el ACTIVO (VEND1, antiguo) gana al retirado (VEND3, reciente).
  v_c := pg_temp.sembrado(66, 'CONVERTIDO SESENTA Y SEIS ACTIVO ANTIGUO', true, 'convertido', pg_temp.dni(66), null, v_vend1, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(67, 'CONVERTIDO SESENTA Y SIETE RETIRADO RECIENTE CON EL DNI SESENTA Y SEIS', false, 'convertido', pg_temp.dni(66), null, v_vend3,
                           clock_timestamp() - interval '1 day');
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(68), pg_temp.dni(66)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» con el DNI 66 y un teléfono nuevo (caso 12e)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'OTRO TELEFONO CON EL DNI SESENTA Y SEIS', pg_temp.tel(68), pg_temp.dni(66));
  perform pg_temp.reg('12e-dni-gana-el-activo',
    pg_temp.exigir_bloqueo('12e-dni-gana-el-activo', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND1'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(68), 0, v_c2, v_otra_antes));
  -- 12f. DNI, dos SIN persona y ACTIVOS: el convertido MÁS RECIENTE (VEND3) gana al más antiguo (VEND1). Ids fijos (ronda 4): el
  --      menor para el más antiguo, el que debe perder.
  v_c := pg_temp.sembrado(69, 'CONVERTIDO SESENTA Y NUEVE ACTIVO RECIENTE', true, 'convertido', pg_temp.dni(69), null, v_vend3, clock_timestamp() - interval '1 day',
                          p_id => 'ffffffff-0027-4000-8000-000000001206');
  v_c2 := pg_temp.sembrado(70, 'CONVERTIDO SETENTA ACTIVO ANTIGUO CON EL DNI SESENTA Y NUEVE', true, 'convertido', pg_temp.dni(69), null, v_vend1,
                           clock_timestamp() - interval '10 days', p_id => '00000000-0027-4000-8000-000000001206');
  if not v_c2 < v_c then
    raise exception 'ENSAYO ABORTADO: los ids fijos del caso 12f no favorecen al que debe perder (el desempate por id dejaría de ser determinista)';
  end if;
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(71), pg_temp.dni(69)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» con el DNI 69 y un teléfono nuevo (caso 12f)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'OTRO TELEFONO CON EL DNI SESENTA Y NUEVE', pg_temp.tel(71), pg_temp.dni(69));
  perform pg_temp.reg('12f-dni-gana-el-mas-reciente',
    pg_temp.exigir_bloqueo('12f-dni-gana-el-mas-reciente', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND3'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(71), 0, v_c2, v_otra_antes));
  -- 12g. Ronda 4. Teléfono, dos SIN persona y ACTIVOS, uno SIN fecha de conversión (duplicado heredado sin sello): gana el que
  --      TIENE fecha (VEND3; `convertido_en desc nulls last`). Ids fijos: el menor para el sin fecha (VEND1), el que debe perder;
  --      así, con `nulls first` o sin el criterio de la fecha, el caso cae siempre.
  v_c := pg_temp.sembrado(72, 'CONVERTIDO SETENTA Y DOS ACTIVO CON FECHA', true, 'convertido', null, null, v_vend3,
                          clock_timestamp() - interval '10 days', p_id => 'ffffffff-0027-4000-8000-000000001207');
  v_c2 := pg_temp.sembrado(72, 'CONVERTIDO SETENTA Y DOS ACTIVO SIN FECHA', true, 'convertido', null, null, v_vend1,
                           p_id => '00000000-0027-4000-8000-000000001207', p_convertido_en_nulo => true);
  if not v_c2 < v_c or (select l.convertido_en from crm.leads l where l.id = v_c2) is not null
     or private.verificar_disponibilidad_lead_impl(pg_temp.teln(72), null) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el caso 12g no es el estado buscado (ids fijos, convertido sin fecha o verificador «libre»)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_n := (select count(*) from crm.leads l where l.telefono = pg_temp.teln(72));
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO SETENTA Y DOS SOLO TELEFONO', pg_temp.tel(72), null);
  perform pg_temp.reg('12g-telefono-gana-el-que-tiene-fecha',
    pg_temp.exigir_bloqueo('12g-telefono-gana-el-que-tiene-fecha', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND3'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(72), v_n, v_c2, v_otra_antes));
  -- 12h. Ronda 4. DNI (con un teléfono nuevo), dos SIN persona y ACTIVOS, uno SIN fecha: gana el que TIENE fecha (VEND3). Ids
  --      fijos: el menor para el sin fecha (VEND1), el que debe perder.
  v_c := pg_temp.sembrado(73, 'CONVERTIDO SETENTA Y TRES ACTIVO CON FECHA', true, 'convertido', pg_temp.dni(73), null, v_vend3,
                          clock_timestamp() - interval '10 days', p_id => 'ffffffff-0027-4000-8000-000000001208');
  v_c2 := pg_temp.sembrado(74, 'CONVERTIDO SETENTA Y CUATRO ACTIVO SIN FECHA CON EL DNI SETENTA Y TRES', true, 'convertido', pg_temp.dni(73), null,
                           v_vend1, p_id => '00000000-0027-4000-8000-000000001208', p_convertido_en_nulo => true);
  if not v_c2 < v_c or (select l.convertido_en from crm.leads l where l.id = v_c2) is not null
     or private.verificar_disponibilidad_lead_impl(pg_temp.teln(75), pg_temp.dni(73)) ->> 'estado' <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el caso 12h no es el estado buscado (ids fijos, convertido sin fecha o verificador «libre» con el DNI 73)';
  end if;
  v_ficha := pg_temp.ficha(v_c); v_otra_antes := pg_temp.ficha(v_c2); v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'OTRO TELEFONO CON EL DNI SETENTA Y TRES', pg_temp.tel(75), pg_temp.dni(73));
  perform pg_temp.reg('12h-dni-gana-el-que-tiene-fecha',
    pg_temp.exigir_bloqueo('12h-dni-gana-el-que-tiene-fecha', v_res, jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND3'),
                           v_c, v_ficha, null, null, v_huella, pg_temp.teln(75), 0, v_c2, v_otra_antes));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- Medida (no caso): el estado REAL del banco, si está — los convertidos que dejó la corrida (conversión real), con un
  -- teléfono que no comparte ningún otro lead: lo que responde hoy un alta solo por teléfono (la sonda del Director, H-28).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_cnt := 0;
  for v_l in
    select l.id, l.telefono, l.activo, l.inversionista_id is not null as con_persona
    from crm.leads l
    where l.etapa = 'convertido' and l.telefono ~ '^\+519[0-9]{8}$' and l.telefono not like '+5192407%'
      and (select count(*) from crm.leads l2 where l2.telefono = l.telefono) = 1
      and not exists (select 1 from public.perfiles p where p.rol = 'cliente' and private.normalizar_telefono(p.telefono) = l.telefono)
    order by l.creado_en, l.id
    limit 2
  loop
    v_cnt := v_cnt + 1;
    v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'MEDIDA BANCO REINGRESO', substr(v_l.telefono, 4), null);
    perform pg_temp.medida(format('banco (convertido real %s, activo=%s, con persona=%s; alta de VEND2 solo por teléfono): %s; leads con ese teléfono=%s',
      left(v_l.id::text, 8), v_l.activo, v_l.con_persona, case when v_res like 'ok|%' then substr(v_res, 4) else v_res end,
      (select count(*) from crm.leads l where l.telefono = v_l.telefono)));
  end loop;
  if v_cnt = 0 then
    perform pg_temp.medida('banco: no hay convertidos reales con teléfono propio en este laboratorio');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 10. Catálogo: lo que la migración conserva, lo que no puede tocar y la ficha del núcleo.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 10a. El alta no cambia (ni cuerpo, ni ficha, ni ACL): la regla vive solo en el núcleo.
  if (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_alta)
       is distinct from '30109c536ef0a73a85da1eb3465b8ed2|e06eca2333bb11869d00913a004c8261'
     or not exists (select 1 from pg_proc p where p.oid = v_alta and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_alta)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']
     or has_function_privilege('anon', v_alta, 'EXECUTE') or has_function_privilege('service_role', v_alta, 'EXECUTE') then
    perform pg_temp.reg('10a', E'FALLO 10a: crm.crear_lead_si_disponible cambió (cuerpo 30109c53…/e06eca23…, dueño, DEFINER, search_path vacío, lock_timeout o ACL)\n');
  else
    perform pg_temp.reg('10a crm.crear_lead_si_disponible intacta (cuerpo, ficha y ACL)', '');
  end if;
  -- 10b. El núcleo: DEFINER de postgres, search_path vacío y lock_timeout, EXECUTE solo para postgres.
  if v_nucleo is null then
    perform pg_temp.reg('10b', E'FALLO 10b: el núcleo private.alta_reactivar_retirado no existe\n');
  elsif not exists (select 1 from pg_proc p where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    perform pg_temp.reg('10b', E'FALLO 10b: el núcleo no es DEFINER de postgres con search_path vacío y lock_timeout, con EXECUTE solo para postgres\n');
  else
    perform pg_temp.reg('10b private.alta_reactivar_retirado: ficha y ACL', '');
  end if;
  -- 10c. El verificador no se toca: huella del cuerpo y la compuesta que fija la carga de bases (20261004184501:178-183).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from '683c16fdcb08377af860f1aa0a18f3a1'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from '48c51531ebc8db1a41f5a816241920da'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    perform pg_temp.reg('10c', E'FALLO 10c: el verificador private.verificar_disponibilidad_lead_impl cambió (la carga de bases dejaría de instalarse)\n');
  else
    perform pg_temp.reg('10c verificador intacto (huella de la carga de bases)', '');
  end if;
  -- 10d. Lo que NO se toca, con su huella: puertas de alta y toma, la pieza del 2.4 y el juicio de identidad que usa la regla.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.tomar_lead_libre(text,text)')) is distinct from 'f755d63f59dfc0e8959fefb83c7b9f9a'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reabrir_lead_fn(uuid)')) is distinct from '65b4b0924da38eaa2c6b7dc42f44ee79'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)')) is distinct from 'bf59d77929877e7a5eb46704d934363e'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_lead_documento_fn(jsonb,text,text)')) is distinct from '3ca9432b3d83061adfda6314633bdc3e'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)')) is distinct from 'a9ac3a87a7707e98c7cc8afbf9c663c3'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_persona(uuid,uuid)')) is distinct from '2570f6eab5ae8b076e6f759b43b9b659'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.inversionista_canonica(uuid)')) is distinct from '6c7ff6001df2cb047967fa61b3ceb763'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.leads_de_personas(uuid[])')) is distinct from 'dbe4b65777e87c81d06abfe9a394d802'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.persona_en_conversion(uuid,uuid)')) is distinct from 'ceb7cdd97c10c8489760332e727e0cba' then
    perform pg_temp.reg('10d', E'FALLO 10d: cambió algo que no se toca (tomar_lead_libre, reabrir_lead_fn, reactivar_lead_base, crear_lead_documento_fn, la pieza alta_reactivar_bloqueo_conservado, juicio_persona, inversionista_canonica, leads_de_personas o persona_en_conversion)\n');
  else
    perform pg_temp.reg('10d huellas de lo que no se toca', '');
  end if;
  -- 10f. El gate interno del núcleo (A-5 del 2.4) sigue: actor ajeno a la sesión ⇒ 42501; el propio con veredicto bloqueante ⇒ null.
  if v_nucleo is null then
    perform pg_temp.reg('10f', E'FALLO 10f: el núcleo private.alta_reactivar_retirado no existe\n');
  else
    v_res := pg_temp.nucleo_directo(v_vend2, v_vend3, pg_temp.tel(1));
    v_txt := case when v_res like '42501|%' then '' else format('con p_actor ajeno a la sesión se esperaba 42501 y llegó %s; ', v_res) end;
    v_res := pg_temp.nucleo_directo(v_vend2, v_vend2, pg_temp.tel(1));
    if v_res <> 'ok|null' then v_txt := v_txt || format('con el propio actor y veredicto «tomado» se esperaba null y llegó %s; ', v_res); end if;
    perform pg_temp.reg('10f el núcleo exige p_actor = auth.uid()', case when v_txt = '' then '' else format(E'FALLO 10f: %s\n', v_txt) end);
  end if;
  perform pg_temp.medida(format('10e: núcleo md5(prosrc) = %s · md5(definición) = %s · alta md5(prosrc) = %s · md5(definición) = %s',
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), 'ausente'),
    coalesce((select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo), 'ausente'),
    (select md5(p.prosrc) from pg_proc p where p.oid = v_alta),
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_alta)));

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ───────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('11', format(E'FALLO 11: algo de lo escrito no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
  end;

  -- ── Veredicto, y rollback SIEMPRE ───────────────────────────────────────────────────────────────────────────────
  raise exception E'ENSAYO %:\n%\n%\n%(rollback a propósito — nada queda escrito)',
    case when current_setting('ensayo.fallos')::integer = 0 then 'VERDE — 0 fallos'
         else format('ROJO — %s fallo(s)', current_setting('ensayo.fallos')) end,
    current_setting('ensayo.informe'),
    current_setting('ensayo.medidas'),
    current_setting('ensayo.oks');
end;
$ensayo$;
