-- ORÁCULO de «Convertir a un cliente antiguo sin ficha de persona usa su misma ficha» (bloque 2.10) — se ejecuta en el LABORATORIO
-- (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisión D-38 de Miguel, 09/10/2026; plan aprobado en D-45; plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.10; la regla
-- del cliente y lo que revela «ya es cliente de X» son las del 2.7 y el 2.8: D-22, D-25, D-27, D-29): al PREPARAR LA CONVERSIÓN de un
-- lead (`crm.preparar_persona_lead_inversion_fn`) con el DNI de un CLIENTE ANTIGUO SIN FICHA DE PERSONA (un lead `convertido` sin
-- persona ni puente, distinto del que se convierte):
--   · si ese cliente antiguo está RETIRADO ⇒ se enlaza a la persona de la conversión (misma ficha: puente `historico` sin tomar el
--     puntero, con su rastro en el libro de operaciones), la conversión sigue —preparar, solicitud, comprobante, confirmar— y el
--     cliente pasa al asesor que convierte (responsable de la persona);
--   · si sigue ACTIVO a nombre de OTRO asesor ⇒ «ya es cliente de X» (el veredicto del alta, mismo formato y datos: D-29) con el
--     `P0481` «Contacto no disponible» de la regla del cliente, y no convierte ni escribe nada;
--   · si sigue activo a nombre del MISMO asesor ⇒ se absorbe (nota en el lead antiguo y su RETIRO, D-81: la casa no admite dos leads
--     vivos de una persona; sus tareas pendientes las cancela la casa como `sistema`), se enlaza como histórico y convierte; si la
--     casa no deja retirarlo (sin perfil del Portal ni cierre inicial), P0409 «El cliente antiguo no se puede retirar; requiere
--     conciliación de Gerencia» y nada escrito (límite P3-2.i).
--   · D-83: al absorber, el CIERRE EXTERNO INICIAL del antiguo se completa con la persona (como la puerta de enlace de Gerencia) si
--     seguía sin persona y su documento es de ella; el asesor de origen del cierre no cambia; Cartera (`crm.inversionista_ficha_fn`)
--     lo cuenta entre las inversiones de la persona. Si el cierre ya es de OTRA persona (D-84) o su documento no es de la persona que
--     se convierte —otro DNI, un CE— (D-85), la conversión se DETIENE con el P0409 de la casa («… requiere conciliación de Gerencia») y
--     nada se escribe (ni puente, ni retiro, ni nota, ni cierre, ni tareas): lo mismo que la puerta de enlace de Gerencia (medido en la
--     ronda 3); si ya es de esta persona, se absorbe sin tocarlo y el detalle lo dice. Un cierre sin documento no existe (U4).
--   · D-86/D-87 (ronda 4): ANTES del cierre, el PERFIL DEL PORTAL del antiguo, en el orden de la puerta de enlace de Gerencia: de OTRA
--     persona, la ficha ya con OTRO perfil, o con otro documento ⇒ P0409 «… requiere conciliación de Gerencia», nada escrito; de nadie
--     y con documento de la persona ⇒ se enlaza a la ficha después del UPDATE (D-87), salvo si la cuenta está DESACTIVADA (D-89: el
--     predicado del núcleo que responde «El perfil Avance requiere revisión antes de operar») ⇒ no se enlaza, la conversión sigue y el
--     detalle lo dice; los conflictos de D-86 detienen también con la cuenta desactivada; si está activo con el mismo DNI, el verificador lo trata como
--     cliente (P0481, límite ii, como hoy); ya de la persona ⇒ el verificador detiene con «ya es cliente» vía identidad (como hoy). Los
--     perfiles se CREAN dentro de la transacción del ensayo (auth.users solo con id + public.perfiles, disparadores apagados).
--   · D-90 (ronda 6): solo un antiguo RETIRADO cuenta como historia de la persona; un antiguo ya unido por puente histórico y ACTIVO
--     sigue siendo «otro lead» (P0409 de conciliación, como hoy: A1s). Los dos núcleos lo mantienen (contrato de la pieza: U7, U8).
--   · D-91 (ronda 7): en la PUERTA, la historia solo exime si la puso ESTA conversión (el reintento de la misma preparación: la operación
--     de enlace del antiguo lleva lead_conversion = el lead que se convierte; A13). Un antiguo RETIRADO ya unido por puente histórico
--     ANTES de esta preparación ⇒ el P0409 «Esta persona ya tiene otra identidad o lead; requiere conciliación» de hoy, con su texto
--     EXACTO, sin P0481 y nada escrito (A1r; con otro antiguo del mismo DNI por absorber, A1r2; con la operación de enlace de OTRA
--     conversión, A1r3); en la ronda 6 el verificador sellado lo paraba con P0481 «ya es cliente» vía identidad. La conversión de OTRO
--     lead de una persona ya absorbida ⇒ conciliación, como hoy (A1t).
--   · D-91 (ronda 8): SOLO cuando esta preparación ESCRIBE el DNI del lead —el único caso en que corre el verificador sellado—. El UPDATE de
--     la puerta (l. 93-94 de su definición viva, b40dded8…) cambia el DNI solo si el documento es un DNI que el lead aún no lleva, y el
--     disparador de disponibilidad llama al verificador solo si cambia el teléfono o el DNI (l. 42-43 y 70 de su función, 418b0976…).
--     Si el lead YA lleva ese DNI (el estado del backfill de identidad y de la carga: el lead vivo canónico, A1u, o el lead con el DNI y
--     sin puntero, A1u2) o el documento es un CE (A1v), el verificador no corre y manda D-90: el retirado ya unido por puente histórico
--     de antes cuenta como historia, la conversión SIGUE y la confirmación entra (en la ronda 7 D-91 la detenía con el P0409 de
--     conciliación: ROJO-PRIMERO). A1r, A1r2 y A1r3 (el lead SIN DNI: la conversión lo escribe) siguen deteniéndose; A1t y A1tb (otro lead
--     de una persona ya absorbida, sin y con el DNI ya escrito) siguen en conciliación, como hoy.
--   · D-94 (ronda 9): el «No insistir» de un antiguo que la conversión CUENTA COMO HISTORIA (D-90: un retirado ya unido por puente histórico) o que
--     ABSORBE (D-38: un candidato de la pieza de absorción) detiene SIEMPRE la conversión con la respuesta exacta que hoy da el verificador
--     sellado en A15/A20 —P0481, «Contacto no disponible», detalle {"estado": "no_contactar"}— y nada se escribe, aunque el verificador no corra
--     (el lead ya lleva el DNI, A1w y A1wc; el documento es un CE, A1wv). Va en la puerta DESPUÉS de la conciliación (los antiguos que no son
--     historia siguen yendo al P0409 de hoy; con el lead SIN DNI manda el P0409 de D-91, A1wb) y ANTES del UPDATE del lead. Antes de la ronda 9
--     el lead con el DNI ya escrito o el CE se convertían (y el candidato se absorbía) pasando por encima del veto (ROJO-PRIMERO).
--   · Quién convierte (P3-6): el supervisor con un antiguo activo de OTRO analista de su equipo y Gerencia con un antiguo activo de
--     otro asesor reciben el veredicto «ya es cliente de X» (no absorben); un antiguo ACTIVO con No insistir del mismo asesor: el veto
--     manda (P0481 no_contactar) y nada se escribe; varios retirados más uno activo del mismo asesor: todos absorbidos, un solo retiro.
--   · H-3 (deuda documentada): tras absorber, el alta con el TELÉFONO del antiguo sigue nombrando al dueño viejo.
--   · D-92 (deuda, con H-3): un bloque corto posterior al grupo C ajustará el verificador para que los antiguos RETIRADOS ya unidos
--     conviertan sin trámite (A1r, A1r2 y A1r3 dejarán de detenerse) y resolverá H-3.
--   · NO CAMBIA: los leads sin coincidencia (persona nueva); los clientes CON ficha, activos o retirados, también en sus dos
--     estados heredados (puntero sin puente, puente canónico sin puntero) (P0409 «requiere conciliación», como hoy); un lead vivo NO
--     convertido con ese DNI (P0409, como hoy); CE y pasaporte; todo lo que hoy ya rechaza y va antes (No insistir del lead, «ya está
--     cerrado»…).
--   · C (catálogo): la puerta llama a la pieza de absorción EXACTAMENTE una vez, DESPUÉS de tomar la fila del lead FOR UPDATE NOWAIT y
--     ANTES de la conciliación, y a la pieza de historia TRES veces (las dos comprobaciones de conciliación y la de D-94, después de ellas);
--     los dos núcleos del
--     contexto de la persona, una vez cada uno; las piezas con su ficha (INVOKER, dueño postgres, EXECUTE solo postgres); nadie más
--     usa las piezas; lo que no se toca, con su definición de hoy. U (contratos): la pieza de historia y la de absorción.
-- Hoy (sin la migración) el cliente antiguo retirado no aparece por ningún camino (`private.leads_de_personas` solo trae enlaces y
-- «sueltos VIVOS») ⇒ nace una persona nueva y el cliente queda con dos registros (P2 del 2.8); el activo es un «suelto vivo» ⇒ P0409
-- «requiere conciliación» para el mismo asesor y para otro.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de las migraciones del 2.11 y del 2.16 (el orden de
-- instalación; el laboratorio no las tiene) y de la migración real de este bloque (sin sus `begin;`/`commit;`) dentro de una única
-- transacción que termina en `rollback`. Con `--sin-migracion` pega solo las de delante y el oráculo, y entonces TIENE que salir ROJO
-- por el defecto (persona nueva o conciliación), nunca por un error de montaje.
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT, fijada en las DOS formas
-- (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de rol con `set role` (tumba el Postgres de esta imagen): todo corre
-- como `postgres`; la puerta es DEFINER y resuelve rol y ámbito con `auth.uid()`. Actores reales del banco (`PASO08 …`), OBLIGATORIOS
-- con su rol y su equipo exactos (VEND1 y VEND2 bajo SUP1, VEND3 bajo SUP2, GERENCIA, BAJA): sin ellos, `ENSAYO ABORTADO`.
--
-- Cómo nacen las cosas (como en los oráculos del 2.7, 2.8, 2.11 y 2.16): los leads, por el ALTA REAL (a nombre del analista); los
-- clientes SIN PERSONA (convertidos heredados), alta real y conversión SEMBRADA con los disparadores apagados (estado heredado
-- declarado: activo o retirado); los clientes CON PERSONA, por la conversión REAL del formulario compartido (cooperativa, sin cuenta del
-- Portal); los estados que la puerta real ya no deja montar (un convertido en una bandeja, de un asesor de baja, con No insistir, un
-- puente histórico ajeno), sembrados con los disparadores apagados y declarados.
--
-- La REFERENCIA de cada veredicto es lo que responde HOY el alta (`crm.crear_lead_si_disponible`) cuando se teclea el DNI del cliente
-- antiguo: el veredicto del alta, con su formato y sus datos (D-29). El caso exige EXACTAMENTE ese veredicto.

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

-- Contactos del ensayo: un bloque propio (+51 924 09xxxx / 7529xxxx) que el montaje exige LIBRE (el del 2.8 es 92408/7528; el del
-- 2.11, 92410; el del 2.16, 92416/7536).
create function pg_temp.tel(n integer) returns text language sql immutable as $$ select '92409' || lpad(n::text, 4, '0') $$;
create function pg_temp.teln(n integer) returns text language sql immutable as $$ select '+51' || pg_temp.tel(n) $$;
create function pg_temp.dni(n integer) returns text language sql immutable as $$ select '7529' || lpad(n::text, 4, '0') $$;

create temp table ens_actores (nombre text primary key, id uuid not null);
create temp table ens_fotos (id uuid primary key, foto jsonb not null);
-- Ronda 6 (Codex r1): la VERSIÓN física de cada lead fotografiado (xmin/ctid: un UPDATE crea otra versión aunque no cambie nada) y cuántos
-- UPDATE suyos auditó la casa en esta transacción (public.audit_log, ts = now(): las filas de ESTA transacción; la auditoría omite los
-- UPDATE que solo cambian actualizado_en).
create temp table ens_fisico (id uuid primary key, version text not null, auditorias bigint not null);

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
create function pg_temp.version_fisica(p_id uuid) returns text language sql as $$
  select l.xmin::text || '/' || l.ctid::text from crm.leads l where l.id = p_id
$$;
create function pg_temp.auditorias_update(p_id uuid) returns bigint language sql as $$
  select count(*) from public.audit_log a where a.ts = now() and a.tabla = 'crm.leads' and a.operacion = 'UPDATE' and a.fila_id = p_id::text
$$;
create function pg_temp.fotografiar(p_ids uuid[]) returns void language sql as $$
  insert into ens_fotos (id, foto)
  select x, pg_temp.ficha(x) from unnest(p_ids) x
  union all
  select ce.id, to_jsonb(ce) from crm.cierres_externos ce where ce.lead_id = any(p_ids) and ce.es_cierre_inicial
  on conflict (id) do update set foto = excluded.foto;
  insert into ens_fisico (id, version, auditorias)
  select x, pg_temp.version_fisica(x), pg_temp.auditorias_update(x) from unnest(p_ids) x where pg_temp.version_fisica(x) is not null
  on conflict (id) do update set version = excluded.version, auditorias = excluded.auditorias;
$$;

-- Huella de ESCRITURA (la del oráculo del 2.8, más el puente y el libro de operaciones): el contenido entero de crm.leads,
-- crm.actividades, crm.lead_asignaciones, crm.inversionista_leads y crm.inversionista_operaciones (md5 de las filas en orden de id) y
-- el número de filas de tareas, personas, documentos, responsables, solicitudes y ciclos SLA.
create function pg_temp.huella_escritura() returns text language sql as $$
  select concat_ws(',',
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '')) from crm.leads l),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from crm.actividades a),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) from crm.lead_asignaciones e),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(il)::text, '|' order by il.id), '')) from crm.inversionista_leads il),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(o)::text, '|' order by o.id), '')) from crm.inversionista_operaciones o),
    (select count(*) from crm.tareas), (select count(*) from crm.inversionistas), (select count(*) from crm.inversionista_identificadores),
    (select count(*) from crm.inversionista_responsables), (select count(*) from crm.inversion_solicitudes), (select count(*) from crm.lead_sla_ciclos),
    (select count(*) from public.audit_log a where a.ts = now()))
$$;

-- Cuántas PERSONAS tienen vigente y verificado ese DNI (la «persona duplicada» que mide el ROJO: con el defecto nace una nueva).
create function pg_temp.personas_con_dni(p_dni text) returns bigint language sql as $$
  select count(distinct d.inversionista_id) from crm.inversionista_identificadores d
  where d.tipo_documento = 'DNI' and d.documento_normalizado = p_dni and d.estado = 'vigente' and d.verificado
$$;

create function pg_temp.error_de(p_res text, out estado text, out mensaje text, out detalle text) language sql immutable as $$
  select split_part(p_res, '|', 1), split_part(p_res, '|', 2), nullif(substr(p_res, length(split_part(p_res, '|', 1)) + length(split_part(p_res, '|', 2)) + 3), '')
$$;
create function pg_temp.a_jsonb(p text) returns jsonb language plpgsql immutable as $f$
begin
  return p::jsonb;
exception when others then
  return null;
end;
$f$;

-- ── Puertas reales ─────────────────────────────────────────────────────────────────────────────────────────────────

-- El ALTA real (crm.crear_lead_si_disponible), como el actor. Devuelve 'ok|<json>' o 'SQLSTATE|mensaje|detalle'.
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

-- La PREPARACIÓN DE LA CONVERSIÓN real (la puerta bajo juicio), como el actor. 'ok|<json>' o 'SQLSTATE|mensaje|detalle'.
create function pg_temp.preparar(p_actor uuid, p_lead uuid, p_tipo text, p_doc text, p_nombre text) returns text language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.preparar_persona_lead_inversion_fn(p_lead, p_tipo, p_doc, p_nombre);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- El RESTO de la conversión real tras preparar (formulario compartido, cooperativa prodelco, sin cuenta del Portal): el contexto que lee
-- la pantalla, la solicitud, el comprobante sintético (el mismo fixture que el banco sube por la API de Storage) y la confirmación.
-- Devuelve '' si todo cuadra o el texto del fallo. El lead queda convertido, enlazado a su persona, con su inversión inicial.
create function pg_temp.flujo_completo(p_caso text, p_actor uuid, p_lead uuid, p_persona uuid, p_nombre text) returns text language plpgsql as $f$
declare
  v_ctx jsonb; v_r jsonb; v_sol uuid := gen_random_uuid(); v_ruta text; v_m text[] := '{}';
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
begin
  begin
    perform pg_temp.sesion(p_actor);
    v_ctx := crm.contexto_conversion_inversion_fn(p_lead, p_persona);
    if coalesce((v_ctx #>> '{capacidades,nueva_inversion}')::boolean, false) is not true then
      v_m := array_append(v_m, format('la pantalla no podría seguir: capacidades %s', v_ctx -> 'capacidades'));
    end if;
    v_ruta := p_persona || '/' || v_sol || '/comprobante.pdf';
    v_r := crm.preparar_inversion_fn(v_sol, jsonb_build_object('inversionista_id', p_persona, 'lead_id', p_lead, 'empresa', 'prodelco',
             -- 22/10/2026 (C2-a ronda 2): 20261016195003 — una inversión nueva de cooperativa vence a plazo × 30 días (12 meses = 360 días), no a 12 meses de calendario.
             'monto', 5000, 'moneda', 'PEN', 'fecha_comercial', v_hoy, 'vence_en', v_hoy + 360,
             'plazo_meses', 12, 'tasa_anual', 15, 'numero_transaccion', 'ENS210-' || left(v_sol::text, 8),
             'referencia', 'ENSAYO 2.10 SINTETICA', 'evidencia', jsonb_build_object('ruta', v_ruta)));
    if v_r ->> 'estado' is distinct from 'preparada' then
      v_m := array_append(v_m, format('la solicitud no quedó preparada: %s', v_r));
    end if;
    perform pg_temp.sesion(null);
    insert into storage.objects (bucket_id, name, metadata)
    values ('f4-comprobantes', v_ruta, '{"size":128,"mimetype":"application/pdf"}'::jsonb);
    perform pg_temp.sesion(p_actor);
    v_r := crm.confirmar_inversion_fn(v_sol);
    perform pg_temp.sesion(null);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      v_m := array_append(v_m, format('la confirmación no respondió ok: %s', v_r));
    end if;
  exception when others then
    perform pg_temp.sesion(null);
    return format(E'FALLO %s: la conversión no pudo seguir tras preparar (%s %s)\n', p_caso, sqlstate, sqlerrm);
  end;
  if (select l.etapa <> 'convertido' or not l.activo or l.inversionista_id is distinct from p_persona from crm.leads l where l.id = p_lead) then
    v_m := array_append(v_m, 'el lead no quedó convertido, activo y enlazado a su persona');
  end if;
  if not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead and il.inversionista_id = p_persona and il.rol = 'canonico') then
    v_m := array_append(v_m, 'el lead convertido no quedó como puente canónico de la persona');
  end if;
  if (select count(*) from crm.inversiones i where i.inversionista_id = p_persona) <> 1
     or not exists (select 1 from crm.inversiones i where i.inversionista_id = p_persona and i.es_primera_conversion) then
    v_m := array_append(v_m, 'la persona no quedó con EXACTAMENTE una inversión inicial');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- ── Montaje de clientes y leads ─────────────────────────────────────────────────────────────────────────────────────

-- Un PERFIL DEL PORTAL de cliente CREADO dentro de la transacción del ensayo (rollback: nunca sale de ella): auth.users solo con su id y
-- public.perfiles con su documento, su teléfono en el bloque del ensayo (+51 924 09 07xx) y activo o no, con los disparadores apagados
-- (estado declarado; el banco no tiene perfiles con documentos del bloque). Lo usan los casos D-86/D-87.
create function pg_temp.perfil_cliente(p_n integer, p_tipo text, p_doc text, p_activo boolean) returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid();
begin
  set local session_replication_role = replica;
  insert into auth.users (id) values (v_id);
  insert into public.perfiles (id, nombre_completo, dni, tipo_documento, telefono, rol, activo)
  values (v_id, 'ENS210 PERFIL ' || p_n, p_doc, p_tipo, '+51' || pg_temp.tel(700 + p_n), 'cliente', p_activo);
  set local session_replication_role = origin;
  return v_id;
end;
$f$;

-- El lead p_lead con la cuenta del Portal p_perfil (estado heredado declarado, disparadores apagados).
create function pg_temp.con_perfil(p_lead uuid, p_perfil uuid) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  update crm.leads set perfil_id = p_perfil where id = p_lead;
  set local session_replication_role = origin;
end;
$f$;

-- Un lead NUEVO por la puerta real, a nombre del actor (aborta si no nace).
create function pg_temp.lead_nuevo(p_actor uuid, p_n integer, p_nombre text, p_dni text default null, p_alt text default null)
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_res text;
begin
  v_res := pg_temp.alta(p_actor, v_id, p_nombre, pg_temp.tel(p_n), p_dni, p_alt);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear por la puerta real el lead % (%)', p_n, v_res;
  end if;
  return v_id;
end;
$f$;

-- CONVERSIÓN SEMBRADA (sin persona, estado heredado) de un lead nacido por la puerta real, como 3d/B1 del 2.4, 4a del 2.7 y P2 del 2.8,
-- con su CIERRE EXTERNO inicial (p_cierre, por defecto): el estado real de un cliente de cooperativa cuya identidad no se resolvió (la
-- casa exige a todo convertido sin perfil del Portal un cierre inicial: `private.leads_before_update`, P4 relajada). Sin cierre
-- (p_cierre = false) es el estado «imposible de editar» que declara ese disparador (solo para medirlo).
create function pg_temp.convertir_sembrado(p_lead uuid, p_retirar boolean, p_cierre boolean default true) returns void language plpgsql as $f$
declare v_ahora timestamptz := clock_timestamp(); v_cierra uuid; v_l crm.leads%rowtype;
begin
  select * into v_l from crm.leads where id = p_lead;
  v_cierra := coalesce(v_l.vendedor_id, v_l.asignado_supervisor_id, pg_temp.actor('GERENCIA'));
  set local session_replication_role = replica;
  update crm.leads set etapa = 'convertido', convertido_en = v_ahora, activo = (activo and not p_retirar) where id = p_lead;
  if p_cierre then
    insert into crm.cierres_externos (lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion,
                                      vendedor_id, creado_por, creado_en, es_cierre_inicial)
    values (p_lead, 'prodelco', 1000, 'PEN', 'DNI', coalesce(v_l.dni, '00000000'), v_l.nombre_completo, 'ENS210-CIERRE-' || left(p_lead::text, 8),
            v_cierra, v_cierra, v_ahora, true);
  end if;
  update crm.lead_asignaciones set finalizado_en = v_ahora, finalizado_por = v_cierra, motivo_cierre = 'convertido',
         resultado = 'convertido', resultado_en = v_ahora where lead_id = p_lead and finalizado_en is null;
  update crm.lead_sla_etapas set finalizado_en = v_ahora, motivo_cierre = 'cierre_terminal' where lead_id = p_lead and finalizado_en is null;
  set local session_replication_role = origin;
  if (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = p_lead) is distinct from 'convertido|' || (not p_retirar)::text then
    raise exception 'ENSAYO ABORTADO: la conversión sembrada del lead % no quedó como se pidió', p_lead;
  end if;
end;
$f$;

-- CLIENTE SIN PERSONA: alta real a nombre de p_actor con su DNI y conversión sembrada (retirado si p_retirar). Exige que no quede
-- enlazado a ninguna persona ni tenga puente.
create function pg_temp.cliente_sin_persona(p_n integer, p_nombre text, p_actor uuid, p_retirar boolean, p_cierre boolean default true) returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_res text;
begin
  v_res := pg_temp.alta(p_actor, v_id, p_nombre, pg_temp.tel(p_n), pg_temp.dni(p_n));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado'
     or (select l.inversionista_id from crm.leads l where l.id = v_id) is not null
     or exists (select 1 from crm.inversionista_leads il where il.lead_id = v_id) then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del cliente sin persona % (%)', p_n, v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_id, p_retirar, p_cierre);
  return v_id;
end;
$f$;

-- Un CONVERTIDO SEMBRADO sin disparadores (estado heredado declarado): en una bandeja (sin vendedor, con supervisor), de un asesor de
-- baja, con No insistir, o con fecha de conversión fija (desempates). Con su ciclo SLA como lo dejaría el alta.
create function pg_temp.sembrado_convertido(p_n integer, p_nombre text, p_activo boolean, p_vendedor uuid, p_supervisor uuid default null,
                                            p_no_contactar boolean default false, p_convertido_en timestamptz default null)
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_creador uuid := coalesce(p_vendedor, p_supervisor, pg_temp.actor('GERENCIA'));
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, convertido_en, monto_estimado, moneda,
                         vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual, ciclo_actual, creado_en, actualizado_en,
                         sla_global_iniciado_en, no_contactar)
  values (v_id, p_nombre, pg_temp.teln(p_n), pg_temp.dni(p_n), 'formulario', 'convertido',
          coalesce(p_convertido_en, clock_timestamp() - interval '5 days'),
          1000, 'PEN', p_vendedor, p_supervisor, p_activo, v_creador, true, 1,
          now() - interval '30 days', now() - interval '10 days', now() - interval '30 days', p_no_contactar);
  insert into crm.lead_sla_ciclos (lead_id, ciclo_n, politica_id, iniciado_en, primera_gestion_limite_en, primer_contacto_limite_en)
  select v_id, 1, p.id, now() - interval '30 days',
         now() - interval '30 days' + p.primera_gestion_minutos * interval '1 minute',
         now() - interval '30 days' + p.primer_contacto_minutos * interval '1 minute'
  from crm.sla_politicas p
  where p.id = coalesce(private.sla_politica_vigente(now() - interval '30 days'), private.sla_politica_vigente(now()));
  insert into crm.cierres_externos (lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion,
                                    vendedor_id, creado_por, creado_en, es_cierre_inicial)
  values (v_id, 'prodelco', 1000, 'PEN', 'DNI', pg_temp.dni(p_n), p_nombre, 'ENS210-CIERRE-' || left(v_id::text, 8), v_creador, v_creador,
          coalesce(p_convertido_en, clock_timestamp() - interval '5 days'), true);
  set local session_replication_role = origin;
  if not exists (select 1 from crm.lead_sla_ciclos c where c.lead_id = v_id)
     or (select l.etapa || '|' || l.activo::text || '|' || l.no_contactar::text from crm.leads l where l.id = v_id)
        is distinct from 'convertido|' || p_activo::text || '|' || p_no_contactar::text then
    raise exception 'ENSAYO ABORTADO: el convertido sembrado % no quedó como se pidió (o sin ciclo SLA)', p_n;
  end if;
  return v_id;
end;
$f$;

-- CLIENTE CON PERSONA por la conversión REAL (alta real + preparar + solicitud + comprobante + confirmar). Devuelve el id del lead
-- convertido (activo, enlazado a su persona).
create function pg_temp.convertir_real(p_n integer, p_nombre text, p_actor uuid) returns uuid language plpgsql as $f$
declare v_lead uuid; v_res text; v_per uuid; v_txt text;
begin
  v_lead := pg_temp.lead_nuevo(p_actor, p_n, p_nombre, pg_temp.dni(p_n));
  v_res := pg_temp.preparar(p_actor, v_lead, 'DNI', pg_temp.dni(p_n), p_nombre);
  if v_res not like 'ok|%' then
    raise exception 'ENSAYO ABORTADO: la preparación de la conversión real del cliente % falló (%)', p_n, v_res;
  end if;
  v_per := (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid;
  v_txt := pg_temp.flujo_completo('montaje-' || p_n, p_actor, v_lead, v_per, p_nombre);
  if v_txt <> '' then
    raise exception 'ENSAYO ABORTADO: la conversión real del cliente % no se completó (%)', p_n, v_txt;
  end if;
  return v_lead;
end;
$f$;

-- RETIRAR sembrado (estado heredado): activo = false con los disparadores apagados.
create function pg_temp.retirar_sembrado(p_lead uuid) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  update crm.leads set activo = false where id = p_lead;
  set local session_replication_role = origin;
  if (select l.activo from crm.leads l where l.id = p_lead) then
    raise exception 'ENSAYO ABORTADO: el lead % no quedó retirado', p_lead;
  end if;
end;
$f$;

-- La REFERENCIA de un veredicto: lo que responde HOY el alta cuando se teclea el DNI del cliente antiguo (con otro teléfono). Aborta
-- si no es «ya es cliente» o si escribe algo.
create function pg_temp.referencia_alta(p_actor uuid, p_n_tel integer, p_dni text) returns jsonb language plpgsql as $f$
declare v_h text := pg_temp.huella_escritura(); v_res text; v_r jsonb;
begin
  v_res := pg_temp.alta(p_actor, gen_random_uuid(), 'REFERENCIA ' || p_dni, pg_temp.tel(p_n_tel), p_dni);
  if v_res not like 'ok|%' then
    raise exception 'ENSAYO ABORTADO: el alta de referencia con el DNI % falló (%)', p_dni, v_res;
  end if;
  v_r := substr(v_res, 4)::jsonb;
  if v_r ->> 'estado' is distinct from 'ya_es_cliente' then
    raise exception 'ENSAYO ABORTADO: el alta de referencia con el DNI % no dice «ya es cliente» (%)', p_dni, v_r;
  end if;
  if pg_temp.huella_escritura() is distinct from v_h then
    raise exception 'ENSAYO ABORTADO: el alta de referencia con el DNI % escribió algo', p_dni;
  end if;
  return v_r;
end;
$f$;

-- ── Jueces ──────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Lo que debe cumplir una preparación que ABSORBE (misma ficha): respondió ok con la persona P; el lead que se convierte apunta a P y
-- lleva el DNI; cada antiguo: puente historico a P (creado_por = el actor), sin puntero, sigue convertido con su dueño de antes y
-- queda RETIRADO (si estaba activo, se retira: nada más cambia en su ficha), una operación «enlace» en el libro (por = actor; detalle
-- con la vía, el rol, el lead de la conversión, si estaba activo y se retiró, y los dos asesores) y una nota «enlace_identidad» SOLO si
-- estaba activo; la persona con el responsable que convierte y su tramo; UNA sola persona con ese DNI; la pieza de historia lo
-- reconoce. D-83: su CIERRE EXTERNO INICIAL (fotografiado) queda con la persona si estaba sin persona y su documento es de ella —y
-- entonces Cartera lo atribuye a la persona y la operación dice cierre_completado—; si ya era de esta persona, no cambia y la
-- operación dice cierre_no_completado con el motivo «el cierre ya es de esta persona»; nada más del cierre cambia (tampoco el asesor
-- de origen). Un cierre de OTRA persona (D-84) o con otro documento (D-85) absorbido es un FALLO: ahí la conversión se detiene.
-- Devuelve '' o la línea FALLO.
create function pg_temp.juzgar_absorcion(p_caso text, p_res text, p_lead uuid, p_dni text, p_antiguos uuid[], p_actor uuid, p_vendedor uuid)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; v_r jsonb; v_per uuid; v_a uuid; v_op record; v_antes jsonb; v_hist boolean; v_ce crm.cierres_externos%rowtype; v_ce_antes jsonb;
begin
  if p_res not like 'ok|%' then
    return format(E'FALLO %s: la preparación se RECHAZÓ (%s): el cliente antiguo no se absorbió en la misma ficha\n', p_caso, p_res);
  end if;
  v_r := substr(p_res, 4)::jsonb;
  v_per := (v_r ->> 'inversionista_id')::uuid;
  if v_per is null or v_r ->> 'lead_id' is distinct from p_lead::text then
    return format(E'FALLO %s: la respuesta no trae la persona y el lead (%s)\n', p_caso, v_r);
  end if;
  if (select l.inversionista_id is distinct from v_per or l.dni is distinct from p_dni from crm.leads l where l.id = p_lead) then
    v_m := array_append(v_m, 'el lead que se convierte no quedó apuntando a la persona con el DNI');
  end if;
  foreach v_a in array p_antiguos loop
    v_antes := (select f.foto from ens_fotos f where f.id = v_a);
    if not exists (select 1 from crm.inversionista_leads il where il.lead_id = v_a and il.inversionista_id = v_per and il.rol = 'historico' and il.creado_por = p_actor) then
      v_m := array_append(v_m, format('el antiguo %s no quedó con puente historico a la persona (creado_por = quien convierte)', left(v_a::text, 8)));
    end if;
    if (select count(*) from crm.inversionista_leads il where il.lead_id = v_a) <> 1 then
      v_m := array_append(v_m, format('el antiguo %s tiene %s puentes (debe ser 1)', left(v_a::text, 8), (select count(*) from crm.inversionista_leads il where il.lead_id = v_a)));
    end if;
    -- Retirar es lo que hace la casa al retirar (activo = false y, por su disparador de tenencia, tenencia_desde a NULL); nada más cambia.
    if (select to_jsonb(l) - 'activo' - 'actualizado_en' - 'tenencia_desde' from crm.leads l where l.id = v_a) is distinct from v_antes - 'activo' - 'actualizado_en' - 'tenencia_desde' then
      v_m := array_append(v_m, format('la ficha del antiguo %s cambió en algo más que su retiro (puntero, dueño, etapa o algo más): antes %s, ahora %s', left(v_a::text, 8),
        v_antes - 'actualizado_en', (select to_jsonb(l) - 'actualizado_en' from crm.leads l where l.id = v_a)));
    end if;
    if (v_antes ->> 'activo')::boolean then
      if (select l.activo or l.tenencia_desde is not null from crm.leads l where l.id = v_a) then
        v_m := array_append(v_m, format('el antiguo ACTIVO %s no quedó retirado como lo retira la casa (activo = false y sin tenencia): un solo lead vivo por persona', left(v_a::text, 8)));
      end if;
    elsif (select to_jsonb(l) -> 'tenencia_desde' from crm.leads l where l.id = v_a) is distinct from v_antes -> 'tenencia_desde'
          or (select l.activo from crm.leads l where l.id = v_a) then
      v_m := array_append(v_m, format('el antiguo RETIRADO %s cambió de estado o de tenencia (no se tocó: nada debía cambiar)', left(v_a::text, 8)));
    end if;
    -- Ronda 6 (Codex r1): los UPDATE FÍSICOS de su fila. Retirado ⇒ ninguno (su fila sigue en la misma versión); activo ⇒ exactamente
    -- uno auditado (su retiro).
    if (v_antes ->> 'activo')::boolean then
      if pg_temp.auditorias_update(v_a) - coalesce((select f.auditorias from ens_fisico f where f.id = v_a), -100) <> 1 then
        v_m := array_append(v_m, format('el antiguo ACTIVO %s recibió %s UPDATE auditados en la preparación (se esperaba 1: su retiro)', left(v_a::text, 8),
          pg_temp.auditorias_update(v_a) - coalesce((select f.auditorias from ens_fisico f where f.id = v_a), -100)));
      end if;
    elsif pg_temp.version_fisica(v_a) is distinct from (select f.version from ens_fisico f where f.id = v_a) then
      v_m := array_append(v_m, format('el antiguo RETIRADO %s recibió un UPDATE físico (su fila no debía tocarse)', left(v_a::text, 8)));
    end if;
    select o.* into v_op from crm.inversionista_operaciones o where o.lead_id = v_a and o.inversionista_id = v_per and o.tipo = 'enlace';
    if v_op.id is null then
      v_m := array_append(v_m, format('el antiguo %s no tiene su operación «enlace» en el libro', left(v_a::text, 8)));
    else
      if v_op.por is distinct from p_actor or v_op.motivo not like 'Conversión%' or v_op.motivo like '%' || p_dni || '%'
         or v_op.detalle ->> 'via' is distinct from 'preparar_conversion_inversion' or v_op.detalle ->> 'rol' is distinct from 'historico'
         or v_op.detalle ->> 'lead_conversion' is distinct from p_lead::text
         or (v_op.detalle ->> 'lead_antiguo_activo')::boolean is distinct from (v_antes ->> 'activo')::boolean
         or (v_op.detalle ->> 'retirado_al_absorber')::boolean is distinct from (v_antes ->> 'activo')::boolean
         or v_op.detalle ->> 'vendedor_antiguo' is distinct from (v_antes ->> 'vendedor_id')
         or v_op.detalle ->> 'vendedor_conversion' is distinct from p_vendedor::text then
        v_m := array_append(v_m, format('la operación del antiguo %s no lleva el rastro esperado (por, motivo sin documento, vía, rol, lead de la conversión, activo y retiro, asesores): %s', left(v_a::text, 8), to_jsonb(v_op)));
      end if;
      if (v_antes ->> 'activo')::boolean then
        if not exists (select 1 from crm.actividades a where a.lead_id = v_a and a.tipo = 'nota' and a.creado_por = p_actor
                        and a.metadata ->> 'evento' = 'enlace_identidad' and a.metadata ->> 'operacion_id' = v_op.id::text) then
          v_m := array_append(v_m, format('el antiguo ACTIVO %s no recibió la nota «enlace_identidad» de quien convierte', left(v_a::text, 8)));
        end if;
      elsif exists (select 1 from crm.actividades a where a.lead_id = v_a and a.metadata ->> 'evento' = 'enlace_identidad') then
        v_m := array_append(v_m, format('el antiguo RETIRADO %s recibió una nota (no debe)', left(v_a::text, 8)));
      end if;
    end if;
    -- D-83: el cierre externo inicial del antiguo.
    v_ce := null;
    select ce.* into v_ce from crm.cierres_externos ce where ce.lead_id = v_a and ce.es_cierre_inicial;
    if v_ce.id is not null then
      v_ce_antes := (select f.foto from ens_fotos f where f.id = v_ce.id);
      if v_ce_antes is null then
        v_m := array_append(v_m, format('el cierre del antiguo %s no se fotografió (error del ensayo)', left(v_a::text, 8)));
      else
        if to_jsonb(v_ce) - 'inversionista_id' is distinct from v_ce_antes - 'inversionista_id' then
          v_m := array_append(v_m, format('el cierre del antiguo %s cambió en algo más que su persona (asesor de origen u otra columna): antes %s, ahora %s', left(v_a::text, 8), v_ce_antes, to_jsonb(v_ce)));
        end if;
        if (v_ce_antes ->> 'inversionista_id') is null and not private.documento_es_de_identidad(v_per, v_ce.documento_tipo, v_ce.documento) then
          v_m := array_append(v_m, format('el cierre del antiguo %s lleva otro documento y se absorbió igual: la conversión debía detenerse (D-85)', left(v_a::text, 8)));
        elsif (v_ce_antes ->> 'inversionista_id') is null then
          if v_ce.inversionista_id is distinct from v_per then
            v_m := array_append(v_m, format('el cierre inicial del antiguo %s no se completó con la persona (D-83)', left(v_a::text, 8)));
          end if;
          if v_op.id is not null and (v_op.detalle ->> 'cierre_completado' is distinct from v_ce.id::text or v_op.detalle ->> 'cierre_no_completado' is not null) then
            v_m := array_append(v_m, format('la operación del antiguo %s no dice cierre_completado = su cierre (D-83): %s', left(v_a::text, 8), v_op.detalle));
          end if;
          if not exists (select 1 from private.cartera_f5_fuentes() f where f.fuente_id = v_ce.id and f.inversionista_id = v_per and f.lead_id = v_a and f.es_inicial and f.capital = v_ce.monto) then
            v_m := array_append(v_m, format('Cartera no atribuye el cierre inicial del antiguo %s a la persona (D-83)', left(v_a::text, 8)));
          end if;
        elsif (v_ce_antes ->> 'inversionista_id')::uuid = v_per then
          -- El cierre YA era de esta persona: no se toca y el detalle lo dice (el único caso que se absorbe sin completar).
          if v_ce.inversionista_id is distinct from v_per then
            v_m := array_append(v_m, format('el cierre del antiguo %s, que ya era de la persona, cambió de persona', left(v_a::text, 8)));
          end if;
          if v_op.id is not null and (v_op.detalle ->> 'cierre_no_completado' is distinct from v_ce.id::text
                                      or v_op.detalle ->> 'cierre_motivo' is distinct from 'el cierre ya es de esta persona' or v_op.detalle ->> 'cierre_completado' is not null) then
            v_m := array_append(v_m, format('la operación del antiguo %s no dice que el cierre ya era de esta persona (cierre_no_completado, cierre_motivo): %s', left(v_a::text, 8), v_op.detalle));
          end if;
        else
          v_m := array_append(v_m, format('el cierre del antiguo %s era de OTRA persona y se absorbió igual: la conversión debía detenerse (D-84)', left(v_a::text, 8)));
        end if;
      end if;
    elsif v_op.id is not null and (v_op.detalle ->> 'cierre_completado' is not null or v_op.detalle ->> 'cierre_no_completado' is not null) then
      v_m := array_append(v_m, format('la operación del antiguo %s habla de un cierre que no existe', left(v_a::text, 8)));
    end if;
    if v_op.id is not null and (v_antes ->> 'perfil_id') is null
       and (v_op.detalle ->> 'perfil_completado' is not null or v_op.detalle ->> 'perfil_no_enlazado' is not null or v_op.detalle ->> 'perfil_motivo' is not null) then
      v_m := array_append(v_m, format('la operación del antiguo %s habla de un perfil del Portal que no tiene', left(v_a::text, 8)));
    end if;
    if to_regprocedure('private.lead_historia_de_persona(uuid,uuid)') is not null then
      execute 'select private.lead_historia_de_persona($1, $2)' into v_hist using v_a, v_per;
      if v_hist is not true then
        v_m := array_append(v_m, format('la pieza de historia no reconoce al antiguo %s como historia de la persona', left(v_a::text, 8)));
      end if;
    else
      v_m := array_append(v_m, 'no existe la pieza private.lead_historia_de_persona');
    end if;
  end loop;
  if (select i.responsable_relacion_id from crm.inversionistas i where i.id = v_per) is distinct from p_vendedor
     or not exists (select 1 from crm.inversionista_responsables r where r.inversionista_id = v_per and r.responsable_id = p_vendedor and r.hasta is null) then
    v_m := array_append(v_m, 'la persona no quedó con el asesor que convierte como responsable (con su tramo abierto)');
  end if;
  if pg_temp.personas_con_dni(p_dni) <> 1 then
    v_m := array_append(v_m, format('hay %s personas con ese DNI (debe ser 1)', pg_temp.personas_con_dni(p_dni)));
  end if;
  if (select count(*) from crm.inversionista_leads il where il.inversionista_id = v_per and il.rol = 'historico') <> cardinality(p_antiguos)
     or (select count(*) from crm.inversionista_operaciones o where o.inversionista_id = v_per and o.tipo = 'enlace') <> cardinality(p_antiguos) then
    v_m := array_append(v_m, 'la persona tiene más (o menos) puentes históricos u operaciones de enlace que antiguos absorbidos');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- D-83 visto desde Cartera: `crm.inversionista_ficha_fn`, leída como el actor, cuenta el cierre inicial de cada antiguo absorbido entre
-- las inversiones de la persona (total, cantidad y capital registrado por empresa/moneda, y cada lead con su inversión inicial).
create function pg_temp.juzgar_ficha(p_caso text, p_actor uuid, p_persona uuid, p_total integer, p_empresa text, p_moneda text, p_cantidad integer, p_capital numeric, p_leads uuid[])
returns text language plpgsql as $f$
declare v_f jsonb; v_m text[] := '{}'; v_t jsonb; v_a uuid;
begin
  begin
    perform pg_temp.sesion(p_actor);
    v_f := crm.inversionista_ficha_fn(p_persona, 1, 1);
    perform pg_temp.sesion(null);
  exception when others then
    perform pg_temp.sesion(null);
    return format(E'FALLO %s: la ficha de Cartera no se pudo leer como el actor (%s %s)\n', p_caso, sqlstate, sqlerrm);
  end;
  if (v_f ->> 'inversiones_total')::integer is distinct from p_total then
    v_m := array_append(v_m, format('inversiones_total %s (se esperaban %s)', v_f ->> 'inversiones_total', p_total));
  end if;
  select t into v_t from jsonb_array_elements(coalesce(v_f -> 'totales', '[]'::jsonb)) t where t ->> 'empresa' = p_empresa and t ->> 'moneda' = p_moneda;
  if v_t is null or (v_t ->> 'cantidad')::integer is distinct from p_cantidad or (v_t ->> 'capital_registrado')::numeric is distinct from p_capital then
    v_m := array_append(v_m, format('totales %s/%s = %s (se esperaban cantidad %s y capital registrado %s)', p_empresa, p_moneda, coalesce(v_t::text, '(ninguno)'), p_cantidad, p_capital));
  end if;
  foreach v_a in array p_leads loop
    if not exists (select 1 from jsonb_array_elements(coalesce(v_f -> 'inversiones', '[]'::jsonb)) i where i ->> 'lead_id' = v_a::text and (i ->> 'es_inicial')::boolean) then
      v_m := array_append(v_m, format('la inversión inicial del lead %s no está en la ficha', left(v_a::text, 8)));
    end if;
  end loop;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- Lo que debe cumplir una conversión DETENIDA con el P0409 de la casa (D-84, D-85): ese error y ese mensaje; NADA escrito (la huella de
-- escritura igual: leads, actividades, episodios, puentes, libro y los recuentos); las fichas de los leads dados y sus cierres
-- iniciales (fotografiados) EXACTAMENTE como antes; ninguna persona con ese DNI; y, si se da, la tarea pendiente sigue pendiente.
create function pg_temp.juzgar_detenida(p_caso text, p_res text, p_mensaje text, p_huella text, p_leads uuid[], p_dni text, p_tarea uuid default null,
                                        p_personas integer default 0)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; e record; v_a uuid;
begin
  if p_res like 'ok|%' then
    return format(E'FALLO %s: la preparación se ACEPTÓ (%s): la conversión debía detenerse con P0409 «%s»\n', p_caso, substr(p_res, 4), p_mensaje);
  end if;
  e := pg_temp.error_de(p_res);
  if e.estado is distinct from 'P0409' or position(p_mensaje in coalesce(e.mensaje, '')) = 0 then
    v_m := array_append(v_m, format('rechazó con otro error: %s (se esperaba P0409 «%s»)', p_res, p_mensaje));
  end if;
  if pg_temp.huella_escritura() is distinct from p_huella then
    v_m := array_append(v_m, 'se escribió algo (leads, actividades, episodios, puentes, libro o recuentos)');
  end if;
  foreach v_a in array p_leads loop
    if pg_temp.ficha(v_a) is distinct from (select f.foto from ens_fotos f where f.id = v_a) then
      v_m := array_append(v_m, format('la ficha %s cambió', left(v_a::text, 8)));
    end if;
    if exists (select 1 from crm.cierres_externos ce where ce.lead_id = v_a and ce.es_cierre_inicial
                and to_jsonb(ce) is distinct from (select f.foto from ens_fotos f where f.id = ce.id)) then
      v_m := array_append(v_m, format('el cierre inicial del lead %s cambió', left(v_a::text, 8)));
    end if;
  end loop;
  if pg_temp.personas_con_dni(p_dni) <> p_personas then
    v_m := array_append(v_m, format('hay %s persona(s) con ese DNI (se esperaban %s)', pg_temp.personas_con_dni(p_dni), p_personas));
  end if;
  if p_tarea is not null and not exists (select 1 from crm.tareas t where t.id = p_tarea and t.estado = 'pendiente' and t.cancelada_por is null) then
    v_m := array_append(v_m, format('la tarea pendiente del antiguo ya no está pendiente (%s)', (select to_jsonb(t) - 'id' from crm.tareas t where t.id = p_tarea)));
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- Lo que debe cumplir una preparación detenida por D-91 (ronda 7): el P0409 de conciliación de HOY con su texto EXACTO —el del cuerpo
-- vivo de la puerta, línea 74 de su definición (b40dded8…): «Esta persona ya tiene otra identidad o lead; requiere conciliación»—, por
-- tanto sin P0481; nada escrito (la huella); las fichas y los cierres iniciales fotografiados intactos; UNA persona con ese DNI (la de
-- antes). Devuelve '' o la línea FALLO.
create function pg_temp.juzgar_d91(p_caso text, p_res text, p_huella text, p_leads uuid[], p_dni text) returns text language plpgsql as $f$
declare v_txt text; e record;
begin
  v_txt := pg_temp.juzgar_detenida(p_caso, p_res, 'Esta persona ya tiene otra identidad o lead; requiere conciliación', p_huella, p_leads, p_dni, null, 1);
  e := pg_temp.error_de(p_res);
  if v_txt = '' and e.mensaje is distinct from 'Esta persona ya tiene otra identidad o lead; requiere conciliación' then
    v_txt := format(E'FALLO %s: el mensaje no es EXACTAMENTE el de hoy: %s\n', p_caso, p_res);
  end if;
  return v_txt;
end;
$f$;

-- Lo que debe cumplir una preparación que SIGUE aunque la persona tenga un convertido RETIRADO ya unido por puente histórico de ANTES
-- (ronda 8: el lead ya lleva el DNI, o el documento es un CE, así que el UPDATE de la puerta no cambia el DNI y el verificador no corre; manda
-- D-90, la historia cuenta): ok con la persona de antes y el lead, el lead con su DNI de antes (o sin él, con un CE) y apuntando a la persona,
-- UNA persona con ese documento, el antiguo INTACTO (ficha, versión física, su único puente histórico, ninguna operación en el libro ni
-- nota: no hay nada que absorber) y el responsable de la persona = el asesor que convierte. Devuelve '' o la línea FALLO.
create function pg_temp.juzgar_dni_ya_escrito(p_caso text, p_res text, p_lead uuid, p_persona uuid, p_tipo text, p_doc text, p_dni_lead text,
                                              p_antiguo uuid, p_vendedor uuid) returns text language plpgsql as $f$
declare v_m text[] := '{}'; v_r jsonb; v_n bigint;
begin
  if p_res not like 'ok|%' then
    return format(E'FALLO %s: la preparación se RECHAZÓ (%s): el verificador no corre y el retirado ya unido cuenta como historia (D-90), así que la conversión debía seguir\n', p_caso, p_res);
  end if;
  v_r := substr(p_res, 4)::jsonb;
  if (v_r ->> 'inversionista_id')::uuid is distinct from p_persona or v_r ->> 'lead_id' is distinct from p_lead::text then
    v_m := array_append(v_m, format('la respuesta no trae la persona de antes y el lead (%s)', v_r));
  end if;
  -- Ronda 9 (Codex r2): la fila TIENE QUE EXISTIR (con `if (select …)` una fila ausente daba NULL y no fallaba).
  if not exists (select 1 from crm.leads l where l.id = p_lead and l.dni is not distinct from p_dni_lead and l.inversionista_id is not distinct from p_persona
                                                and p_persona is not null) then
    v_m := array_append(v_m, 'el lead no quedó con su DNI de antes y apuntando a la persona');
  end if;
  select count(distinct d.inversionista_id) into v_n from crm.inversionista_identificadores d
   where d.tipo_documento = p_tipo and d.documento_normalizado = p_doc and d.estado = 'vigente' and d.verificado;
  if v_n <> 1 then
    v_m := array_append(v_m, format('hay %s personas con ese documento (debe ser 1)', v_n));
  end if;
  if pg_temp.ficha(p_antiguo) is distinct from (select f.foto from ens_fotos f where f.id = p_antiguo) then
    v_m := array_append(v_m, 'la ficha del antiguo cambió (no debía tocarse)');
  end if;
  if pg_temp.version_fisica(p_antiguo) is distinct from (select f.version from ens_fisico f where f.id = p_antiguo) then
    v_m := array_append(v_m, 'el antiguo recibió un UPDATE físico (su fila no debía tocarse)');
  end if;
  if (select count(*) from crm.inversionista_leads il where il.lead_id = p_antiguo) <> 1
     or not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_antiguo and il.inversionista_id = p_persona and il.rol = 'historico') then
    v_m := array_append(v_m, 'el antiguo no conserva su único puente histórico a la persona');
  end if;
  if (select count(*) from crm.inversionista_leads il where il.inversionista_id = p_persona and il.rol = 'historico') <> 1 then
    v_m := array_append(v_m, 'la persona tiene más de un puente histórico (se absorbió algo que no debía)');
  end if;
  if exists (select 1 from crm.inversionista_operaciones o where o.inversionista_id = p_persona)
     or exists (select 1 from crm.actividades a where a.lead_id = p_antiguo and a.metadata ->> 'evento' = 'enlace_identidad') then
    v_m := array_append(v_m, 'quedó rastro de una absorción (operación del libro o nota) y no había nada que absorber');
  end if;
  if (select i.responsable_relacion_id from crm.inversionistas i where i.id = p_persona) is distinct from p_vendedor then
    v_m := array_append(v_m, 'la persona no quedó con quien convierte como responsable');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- Lo que debe cumplir una conversión DETENIDA por el «No insistir» de un antiguo (D-94, ronda 9): EXACTAMENTE la respuesta que da hoy el verificador sellado
-- en A15/A20 —P0481, mensaje «Contacto no disponible», detalle {"estado": "no_contactar"} (como texto y como jsonb)—; NADA escrito (la huella: leads,
-- actividades, episodios, puentes, libro y recuentos); la ficha, la versión física y el cierre inicial fotografiados de los leads dados (el que se convierte y
-- los antiguos: el antiguo NO se absorbe ni se retira de nuevo) EXACTAMENTE como antes; y p_personas persona(s) con ese documento (las de antes: 1 si la persona
-- ya existía; 0 si la creó la preparación y el rechazo la deshizo). Devuelve '' o la línea FALLO.
create function pg_temp.juzgar_no_insistir(p_caso text, p_res text, p_huella text, p_leads uuid[], p_tipo text, p_doc text, p_personas integer)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; e record; v_a uuid; v_n bigint;
begin
  if p_res like 'ok|%' then
    return format(E'FALLO %s: la preparación se ACEPTÓ (%s): el «No insistir» del antiguo debía detener la conversión con P0481 «Contacto no disponible» {"estado": "no_contactar"}\n', p_caso, substr(p_res, 4));
  end if;
  e := pg_temp.error_de(p_res);
  if e.estado is distinct from 'P0481' or e.mensaje is distinct from 'Contacto no disponible' then
    v_m := array_append(v_m, format('rechazó con otro error: %s (se esperaba P0481 «Contacto no disponible» con {"estado": "no_contactar"})', p_res));
  elsif e.detalle is distinct from '{"estado": "no_contactar"}' or pg_temp.a_jsonb(e.detalle) is distinct from jsonb_build_object('estado', 'no_contactar') then
    v_m := array_append(v_m, format('detalle %s, se esperaba EXACTAMENTE {"estado": "no_contactar"}', coalesce(e.detalle, '(vacío)')));
  end if;
  if pg_temp.huella_escritura() is distinct from p_huella then
    v_m := array_append(v_m, 'se escribió algo (leads, actividades, episodios, puentes, libro o recuentos)');
  end if;
  foreach v_a in array p_leads loop
    if pg_temp.ficha(v_a) is distinct from (select f.foto from ens_fotos f where f.id = v_a) then
      v_m := array_append(v_m, format('la ficha %s cambió', left(v_a::text, 8)));
    end if;
    if pg_temp.version_fisica(v_a) is distinct from (select f.version from ens_fisico f where f.id = v_a) then
      v_m := array_append(v_m, format('el lead %s recibió un UPDATE físico', left(v_a::text, 8)));
    end if;
    if exists (select 1 from crm.cierres_externos ce where ce.lead_id = v_a and ce.es_cierre_inicial
                and to_jsonb(ce) is distinct from (select f.foto from ens_fotos f where f.id = ce.id)) then
      v_m := array_append(v_m, format('el cierre inicial del lead %s cambió (se completó con la persona)', left(v_a::text, 8)));
    end if;
  end loop;
  select count(distinct d.inversionista_id) into v_n from crm.inversionista_identificadores d
   where d.tipo_documento = p_tipo and d.documento_normalizado = p_doc and d.estado = 'vigente' and d.verificado;
  if v_n <> p_personas then
    v_m := array_append(v_m, format('hay %s persona(s) con ese documento (se esperaban %s)', v_n, p_personas));
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- Lo que debe cumplir una preparación RECHAZADA con el veredicto «ya es cliente de X»: el error EXACTO (P0481, «Contacto no disponible»,
-- detalle = el veredicto del alta, byte a byte como jsonb), el lead que se convierte y los antiguos intactos, NINGUNA persona con ese
-- DNI (la que creó el resolver se deshizo con el rechazo) y ninguna escritura. Devuelve '' o la línea FALLO.
create function pg_temp.juzgar_veredicto(p_caso text, p_res text, p_esperado jsonb, p_lead uuid, p_dni text, p_antiguos uuid[], p_huella text)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; e record; v_a uuid;
begin
  if p_res like 'ok|%' then
    return format(E'FALLO %s: la preparación se ACEPTÓ (%s) en vez de responder «ya es cliente de X» (%s): un cliente activo de otro asesor se convirtió en otro lead\n',
      p_caso, substr(p_res, 4), p_esperado::text);
  end if;
  e := pg_temp.error_de(p_res);
  if e.estado is distinct from 'P0481' or e.mensaje is distinct from 'Contacto no disponible' then
    v_m := array_append(v_m, format('rechazó con otro error: %s (se esperaba P0481 «Contacto no disponible» con el veredicto %s)', p_res, p_esperado::text));
  elsif pg_temp.a_jsonb(e.detalle) is distinct from p_esperado then
    v_m := array_append(v_m, format('detalle %s, se esperaba EXACTAMENTE el veredicto del alta %s', coalesce(e.detalle, '(vacío)'), p_esperado::text));
  end if;
  foreach v_a in array p_antiguos || p_lead loop
    if pg_temp.ficha(v_a) is distinct from (select f.foto from ens_fotos f where f.id = v_a) then
      v_m := array_append(v_m, format('la ficha %s cambió', left(v_a::text, 8)));
    end if;
  end loop;
  if pg_temp.personas_con_dni(p_dni) <> 0 then
    v_m := array_append(v_m, format('quedó %s persona(s) con ese DNI (la persona del resolver no se deshizo)', pg_temp.personas_con_dni(p_dni)));
  end if;
  if pg_temp.huella_escritura() is distinct from p_huella then
    v_m := array_append(v_m, 'se escribió algo');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- Lo que debe cumplir una preparación que sigue en CONCILIACIÓN como hoy (P0409 «Esta persona ya tiene otra identidad o lead»): ese
-- error, nada escrito, ningún puente nuevo. Devuelve '' o la línea FALLO.
create function pg_temp.juzgar_conciliacion(p_caso text, p_res text, p_huella text, p_mensaje text default 'Esta persona ya tiene otra identidad o lead')
returns text language plpgsql as $f$
declare v_m text[] := '{}'; e record;
begin
  if p_res like 'ok|%' then
    return format(E'FALLO %s: la preparación se ACEPTÓ (%s) y hoy se detiene con P0409 «%s»\n', p_caso, substr(p_res, 4), p_mensaje);
  end if;
  e := pg_temp.error_de(p_res);
  if e.estado is distinct from 'P0409' or position(p_mensaje in coalesce(e.mensaje, '')) = 0 then
    v_m := array_append(v_m, format('rechazó con otro error: %s (se esperaba P0409 «%s», como hoy)', p_res, p_mensaje));
  end if;
  if pg_temp.huella_escritura() is distinct from p_huella then
    v_m := array_append(v_m, 'se escribió algo');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- Lo que debe cumplir una preparación sin coincidencia (como hoy): ok, persona NUEVA con ese DNI, sin puentes históricos ni operaciones.
create function pg_temp.juzgar_sin_cambio(p_caso text, p_res text, p_lead uuid, p_dni text) returns text language plpgsql as $f$
declare v_m text[] := '{}'; v_per uuid;
begin
  if p_res not like 'ok|%' then
    return format(E'FALLO %s: la preparación se rechazó (%s) y hoy entra\n', p_caso, p_res);
  end if;
  v_per := (substr(p_res, 4)::jsonb ->> 'inversionista_id')::uuid;
  if (select l.inversionista_id from crm.leads l where l.id = p_lead) is distinct from v_per then
    v_m := array_append(v_m, 'el lead no quedó apuntando a la persona');
  end if;
  if pg_temp.personas_con_dni(p_dni) <> 1 then
    v_m := array_append(v_m, format('hay %s personas con ese DNI', pg_temp.personas_con_dni(p_dni)));
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.inversionista_id = v_per and il.rol = 'historico')
     or exists (select 1 from crm.inversionista_operaciones o where o.inversionista_id = v_per) then
    v_m := array_append(v_m, 'la persona recibió puentes históricos u operaciones sin haber cliente antiguo');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- La POSICIÓN de la última aparición de un texto en un cuerpo (para «la llamada va después de tomar la fila»).
create function pg_temp.ultima(p_src text, p_txt text) returns integer language sql immutable as $$
  select coalesce(length(p_src) - length(split_part(reverse(p_src), reverse(p_txt), 1)) - length(p_txt) + 1, 0)
  where strpos(p_src, p_txt) > 0
$$;

-- La ficha de una función: dueño postgres, DEFINER o INVOKER, volatilidad, su SET exacto, su ACL efectiva, sin anon ni service_role.
create function pg_temp.ficha_ok(p_firma regprocedure, p_definer boolean, p_vol "char", p_config text[], p_acl text) returns boolean language sql as $$
  select exists (select 1 from pg_proc p where p.oid = p_firma and p.proowner = 'postgres'::regrole::oid and p.prosecdef = p_definer
                   and p.provolatile = p_vol and p.proconfig = p_config)
     and (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
            from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = p_firma) = p_acl
     and not has_function_privilege('anon', p_firma, 'EXECUTE') and not has_function_privilege('service_role', p_firma, 'EXECUTE')
$$;

insert into ens_actores (nombre, id)
select n.nombre, p.id
from (values ('VEND1'), ('VEND2'), ('VEND3'), ('SUP1'), ('SUP2'), ('GERENCIA'), ('BAJA')) n(nombre)
join public.perfiles p on p.nombre_completo = 'PASO08 ' || n.nombre;

do $ensayo$
declare
  v_vend1 uuid; v_vend2 uuid; v_vend3 uuid; v_sup1 uuid; v_sup2 uuid; v_ger uuid; v_baja uuid;
  v_puerta regprocedure := 'crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'::regprocedure;
  v_escritura regprocedure := 'private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure;
  v_lectura regprocedure := 'private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'::regprocedure;
  v_absorber regprocedure := to_regprocedure('private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)');
  v_enlazar regprocedure := to_regprocedure('private.conversion_enlazar_cliente_antiguo(uuid,jsonb,uuid)');
  v_historia regprocedure := to_regprocedure('private.lead_historia_de_persona(uuid,uuid)');
  v_c uuid; v_c2 uuid; v_c3 uuid; v_l uuid; v_per uuid; v_p9 uuid; v_q uuid; v_tarea uuid; v_x uuid; v_y uuid; v_c4 uuid; v_q2 uuid; v_u9 uuid; v_u9p uuid;
  v_res text; v_res2 text; v_txt text; v_h text; v_esp jsonb; v_r jsonb; e record; v_b boolean; v_src text; v_m text[];
begin
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.casos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ── Actores reales del banco (OBLIGATORIOS: sin ellos un caso se saltaría en silencio) ──────────────────────────────
  v_vend1 := pg_temp.actor('VEND1'); v_vend2 := pg_temp.actor('VEND2'); v_vend3 := pg_temp.actor('VEND3');
  v_sup1 := pg_temp.actor('SUP1'); v_sup2 := pg_temp.actor('SUP2'); v_ger := pg_temp.actor('GERENCIA'); v_baja := pg_temp.actor('BAJA');
  if v_vend1 is null or v_vend2 is null or v_vend3 is null or v_sup1 is null or v_sup2 is null or v_ger is null or v_baja is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (vend1=%, vend2=%, vend3=%, sup1=%, sup2=%, gerencia=%, baja=%)',
      v_vend1, v_vend2, v_vend3, v_sup1, v_sup2, v_ger, v_baja;
  end if;
  if private.rol_crm(v_vend1) is distinct from 'vendedor' or private.rol_crm(v_vend2) is distinct from 'vendedor'
     or private.rol_crm(v_vend3) is distinct from 'vendedor' or private.rol_crm(v_sup1) is distinct from 'supervisor'
     or private.rol_crm(v_sup2) is distinct from 'supervisor' or private.rol_crm(v_ger) is distinct from 'gerencia'
     or (select eq.supervisor_id from crm.equipo eq where eq.perfil_id = v_vend2) is distinct from v_sup1
     or (select eq.supervisor_id from crm.equipo eq where eq.perfil_id = v_vend1) is distinct from v_sup1
     or (select eq.supervisor_id from crm.equipo eq where eq.perfil_id = v_vend3) is distinct from v_sup2
     or (select p.activo from public.perfiles p where p.id = v_baja) is not false then
    raise exception 'ENSAYO ABORTADO: un actor del banco no tiene el rol o el equipo esperado (vend1/vend2 bajo sup1, vend3 bajo sup2; gerencia; BAJA con el perfil inactivo)';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'inversiones_escritura'), false) then
    raise exception 'ENSAYO ABORTADO: las banderas resolver_en_puertas e inversiones_escritura tienen que estar encendidas (como en producción)';
  end if;
  -- El bloque de contactos del ensayo tiene que estar libre (teléfono, alternativo, DNI, perfiles y documentos).
  if exists (select 1 from crm.leads l where l.telefono like '+5192409%' or l.telefono_alternativo like '%92409%'
                                             or l.telefono_alternativo_crudo like '%92409%' or l.dni like '7529%')
     or exists (select 1 from public.perfiles p where p.telefono like '%92409%' or p.dni like '7529%')
     or exists (select 1 from crm.inversionista_identificadores d where d.documento_normalizado like '7529%') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene contactos del bloque +51 924 09xxxx / 7529xxxx';
  end if;
  -- El cubo de comprobantes de la conversión real (fixture del banco; si falta, vive y muere en esta transacción).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('f4-comprobantes', 'f4-comprobantes', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
  on conflict (id) do nothing;
  perform pg_temp.medida(format('T0 piezas: absorción %s · enlace %s · historia %s · puerta md5(prosrc)=%s', coalesce(v_absorber::text, 'AUSENTE'), coalesce(v_enlazar::text, 'AUSENTE'), coalesce(v_historia::text, 'AUSENTE'),
    (select md5(p.prosrc) from pg_proc p where p.oid = v_puerta)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1. CLIENTE ANTIGUO RETIRADO DE OTRO ASESOR (el P2 del 2.8): VEND1 registró y convirtió (sin persona) al cliente 1 y la ficha
  --     está retirada; VEND2 convierte otro lead con ese DNI ⇒ misma ficha (puente historico, rastro), el cliente pasa a VEND2 y la
  --     conversión se completa de verdad.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(1, 'ENS210 CLIENTE A1 RETIRADO', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 101, 'ENS210 LEAD A1');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(1), 'ENS210 LEAD A1');
  perform pg_temp.medida(format('A1 · preparar con el DNI de un cliente antiguo RETIRADO de otro asesor (P2 del 2.8) → %s · personas con ese DNI: %s · puente del antiguo: %s',
    v_res, pg_temp.personas_con_dni(pg_temp.dni(1)), coalesce((select il.rol from crm.inversionista_leads il where il.lead_id = v_c), 'ninguno')));
  v_txt := pg_temp.juzgar_absorcion('A1-retirado-de-otro-asesor-misma-ficha', v_res, v_l, pg_temp.dni(1), array[v_c], v_vend2, v_vend2);
  perform pg_temp.reg('A1-retirado-de-otro-asesor-misma-ficha', v_txt);
  if v_txt = '' then
    v_per := (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid;
    perform pg_temp.reg('A1b-la-conversion-sigue-hasta-confirmar', pg_temp.flujo_completo('A1b-la-conversion-sigue-hasta-confirmar', v_vend2, v_l, v_per, 'ENS210 LEAD A1'));
    -- Tras confirmar: el antiguo sigue como historia, el nuevo es el canónico; la pieza de historia distingue los dos.
    if v_historia is not null then
      execute 'select private.lead_historia_de_persona($1, $2) and not private.lead_historia_de_persona($3, $2) and not private.lead_historia_de_persona($1, gen_random_uuid())'
        into v_b using v_c, v_per, v_l;
      perform pg_temp.reg('U1-contrato-de-la-pieza-de-historia',
        case when v_b then '' else E'FALLO U1-contrato-de-la-pieza-de-historia: la pieza no dice sí al antiguo (historico, convertido, sin puntero) y no al canónico ni a otra persona\n' end);
    else
      perform pg_temp.reg('U1-contrato-de-la-pieza-de-historia', E'FALLO U1-contrato-de-la-pieza-de-historia: no existe private.lead_historia_de_persona\n');
    end if;
    -- A1c (D-83): la ficha de Cartera de la persona, leída como VEND2, cuenta el cierre inicial del antiguo (1000 PEN prodelco) y la
    --     inversión nueva (5000 PEN prodelco): 2 inversiones, prodelco/PEN cantidad 2 y capital registrado 6000.
    perform pg_temp.reg('A1c-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-y-la-inversion-nueva (D-83)',
      pg_temp.juzgar_ficha('A1c-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-y-la-inversion-nueva (D-83)', v_vend2, v_per, 2, 'prodelco', 'PEN', 2, 6000, array[v_c, v_l]));
    -- A24 (H-3, deuda documentada): tras absorber, el ALTA por VEND3 con el TELÉFONO del antiguo sigue nombrando al dueño VIEJO
    --     (VEND1): la regla del cliente del alta (private.juicio_cliente_convertido, fijada por el 2.9/2.11/2.16) juzga por el lead
    --     convertido que encuentra, no por la persona. Se mide también con el DNI (que resuelve por la persona). Se asienta «como hoy».
    v_res2 := pg_temp.alta(v_vend3, gen_random_uuid(), 'ENS210 ALTA A24 TELEFONO', pg_temp.tel(1), null);
    v_txt := pg_temp.alta(v_vend3, gen_random_uuid(), 'ENS210 ALTA A24 DNI', pg_temp.tel(133), pg_temp.dni(1));
    perform pg_temp.medida(format('A24 (H-3) · tras absorber y confirmar, el alta por VEND3 con el TELÉFONO del antiguo → %s · con el DNI del antiguo → %s', v_res2, v_txt));
    perform pg_temp.reg('A24-tras-absorber-el-alta-con-el-telefono-del-antiguo-nombra-al-dueno-viejo (H-3, deuda, como hoy)',
      case when v_res2 like 'ok|%' and (substr(v_res2, 4)::jsonb ->> 'estado') = 'ya_es_cliente' and (substr(v_res2, 4)::jsonb ->> 'asesor') = 'PASO08 VEND1' then ''
           else format(E'FALLO A24-tras-absorber-el-alta-con-el-telefono-del-antiguo-nombra-al-dueno-viejo (H-3, deuda, como hoy): se esperaba «ya es cliente de PASO08 VEND1» (el dueño viejo) y llegó %s\n', v_res2) end);
  else
    perform pg_temp.reg('A1b-la-conversion-sigue-hasta-confirmar', E'FALLO A1b-la-conversion-sigue-hasta-confirmar: no se midió (A1 falló)\n');
    perform pg_temp.reg('U1-contrato-de-la-pieza-de-historia', E'FALLO U1-contrato-de-la-pieza-de-historia: no se midió (A1 falló)\n');
    perform pg_temp.reg('A1c-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-y-la-inversion-nueva (D-83)', E'FALLO A1c-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-y-la-inversion-nueva (D-83): no se midió (A1 falló)\n');
    perform pg_temp.reg('A24-tras-absorber-el-alta-con-el-telefono-del-antiguo-nombra-al-dueno-viejo (H-3, deuda, como hoy)', E'FALLO A24-tras-absorber-el-alta-con-el-telefono-del-antiguo-nombra-al-dueno-viejo (H-3, deuda, como hoy): no se midió (A1 falló)\n');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A2. CLIENTE ANTIGUO RETIRADO DEL MISMO ASESOR (VEND2) ⇒ misma ficha y la conversión sigue.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(2, 'ENS210 CLIENTE A2 RETIRADO MISMO', v_vend2, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 102, 'ENS210 LEAD A2');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(2), 'ENS210 LEAD A2');
  v_txt := pg_temp.juzgar_absorcion('A2-retirado-del-mismo-asesor-misma-ficha', v_res, v_l, pg_temp.dni(2), array[v_c], v_vend2, v_vend2);
  perform pg_temp.reg('A2-retirado-del-mismo-asesor-misma-ficha', v_txt);
  if v_txt = '' then
    perform pg_temp.reg('A2b-la-conversion-sigue-hasta-confirmar', pg_temp.flujo_completo('A2b-la-conversion-sigue-hasta-confirmar', v_vend2, v_l, (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid, 'ENS210 LEAD A2'));
  else
    perform pg_temp.reg('A2b-la-conversion-sigue-hasta-confirmar', E'FALLO A2b-la-conversion-sigue-hasta-confirmar: no se midió (A2 falló)\n');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A4. CLIENTE ANTIGUO ACTIVO DEL MISMO ASESOR (VEND2) ⇒ misma ficha (la nota en el lead antiguo y su retiro) y la conversión sigue.
  --     Hoy: P0409 «requiere conciliación» (medida).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(4, 'ENS210 CLIENTE A4 ACTIVO MISMO', v_vend2, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 104, 'ENS210 LEAD A4');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(4), 'ENS210 LEAD A4');
  perform pg_temp.medida(format('A4 · preparar con el DNI de un cliente antiguo ACTIVO del mismo asesor → %s · el antiguo después: %s', v_res,
    (select 'etapa=' || l.etapa || ' activo=' || l.activo::text || ' vendedor=' || coalesce(l.vendedor_id::text, '-') || ' puente=' || coalesce((select il.rol from crm.inversionista_leads il where il.lead_id = l.id), 'ninguno') from crm.leads l where l.id = v_c)));
  v_txt := pg_temp.juzgar_absorcion('A4-activo-del-mismo-asesor-misma-ficha-con-nota-y-retiro', v_res, v_l, pg_temp.dni(4), array[v_c], v_vend2, v_vend2);
  perform pg_temp.reg('A4-activo-del-mismo-asesor-misma-ficha-con-nota-y-retiro', v_txt);
  if v_txt = '' then
    v_per := (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid;
    perform pg_temp.reg('A4b-la-conversion-sigue-hasta-confirmar', pg_temp.flujo_completo('A4b-la-conversion-sigue-hasta-confirmar', v_vend2, v_l, v_per, 'ENS210 LEAD A4'));
    perform pg_temp.reg('A4d-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-retirado-y-la-inversion-nueva (D-83)',
      pg_temp.juzgar_ficha('A4d-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-retirado-y-la-inversion-nueva (D-83)', v_vend2, v_per, 2, 'prodelco', 'PEN', 2, 6000, array[v_c, v_l]));
  else
    perform pg_temp.reg('A4b-la-conversion-sigue-hasta-confirmar', E'FALLO A4b-la-conversion-sigue-hasta-confirmar: no se midió (A4 falló)\n');
    perform pg_temp.reg('A4d-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-retirado-y-la-inversion-nueva (D-83)', E'FALLO A4d-la-ficha-de-cartera-cuenta-el-cierre-del-antiguo-retirado-y-la-inversion-nueva (D-83): no se midió (A4 falló)\n');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A4c. LÍMITE (P3-2.i): el antiguo activo del mismo asesor SIN perfil del Portal NI cierre externo —el estado que la casa declara
  --      imposible de editar (`private.leads_before_update`, P4 relajada; en producción un convertido tiene perfil o cierre)— no se
  --      puede retirar: la conversión falla con el P0409 de la casa («El cliente antiguo no se puede retirar; requiere conciliación de
  --      Gerencia», y en el detalle SOLO el código del error original, P0001 —el texto queda en el registro del servidor: P3-2 del
  --      auditor r2—) y nada se escribe (hoy: P0409 «requiere conciliación»).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(23, 'ENS210 CLIENTE A4C ACTIVO SIN CIERRE', v_vend2, false, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 123, 'ENS210 LEAD A4C');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(23), 'ENS210 LEAD A4C');
  perform pg_temp.medida(format('A4c · antiguo activo del mismo asesor sin perfil ni cierre (estado imposible de editar) → %s', v_res));
  e := pg_temp.error_de(v_res);
  perform pg_temp.reg('A4c-antiguo-activo-sin-perfil-ni-cierre-no-se-puede-retirar (limite P0409 de la casa, nada escrito)',
    case when e.estado = 'P0409' and position('El cliente antiguo no se puede retirar; requiere conciliación de Gerencia' in coalesce(e.mensaje, '')) > 0
              and e.detalle is not distinct from 'P0001'
              and pg_temp.huella_escritura() = v_h and pg_temp.personas_con_dni(pg_temp.dni(23)) = 0 then ''
         else format(E'FALLO A4c-antiguo-activo-sin-perfil-ni-cierre-no-se-puede-retirar (limite P0409 de la casa, nada escrito): se esperaba P0409 «El cliente antiguo no se puede retirar; requiere conciliación de Gerencia» con SOLO el código P0001 en el detalle, sin escribir, y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A4e. EL ANTIGUO ACTIVO DEL MISMO ASESOR TENÍA UNA TAREA PENDIENTE (P3-4): al retirarlo, la casa (`private.trg_leads_sync_tareas`)
  --      la cancela como `sistema` (cancelada_por = 'sistema', sin cancelada_por_id). Se mide y se aserta: es efecto de la casa, no de
  --      esta regla.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(28, 'ENS210 CLIENTE A4E ACTIVO CON TAREA', v_vend2, false);
  set local session_replication_role = replica;
  insert into crm.tareas (lead_id, vendedor_id, asignado_supervisor_id, tipo, titulo, vence_en, estado, creado_por)
  select l.id, l.vendedor_id, l.asignado_supervisor_id, 'llamada', 'ENS210 tarea pendiente A4E', clock_timestamp() + interval '2 days', 'pendiente', l.vendedor_id
  from crm.leads l where l.id = v_c returning id into v_tarea;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 128, 'ENS210 LEAD A4E');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(28), 'ENS210 LEAD A4E');
  perform pg_temp.medida(format('A4e · antiguo activo del mismo asesor con una tarea pendiente → %s · la tarea después: %s', v_res,
    (select 'estado=' || t.estado || ' cancelada_por=' || coalesce(t.cancelada_por, '-') || ' cancelada_por_id=' || coalesce(t.cancelada_por_id::text, '-') from crm.tareas t where t.id = v_tarea)));
  v_txt := pg_temp.juzgar_absorcion('A4e-antiguo-activo-con-tarea-pendiente-la-casa-la-cancela-como-sistema', v_res, v_l, pg_temp.dni(28), array[v_c], v_vend2, v_vend2);
  if v_txt = '' and not exists (select 1 from crm.tareas t where t.id = v_tarea and t.estado = 'cancelada' and t.cancelada_por = 'sistema' and t.cancelada_por_id is null) then
    v_txt := format(E'FALLO A4e-antiguo-activo-con-tarea-pendiente-la-casa-la-cancela-como-sistema: la tarea pendiente del antiguo retirado no quedó cancelada por sistema (%s)\n',
      (select to_jsonb(t) from crm.tareas t where t.id = v_tarea));
  end if;
  perform pg_temp.reg('A4e-antiguo-activo-con-tarea-pendiente-la-casa-la-cancela-como-sistema', v_txt);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1d/A1e/A1g/A1f. EL CIERRE INICIAL DEL ANTIGUO (D-83, D-84, D-85; como la puerta de enlace de Gerencia, medida en la ronda 3).
  --          A1d el cierre YA es de OTRA persona (sembrado y declarado) ⇒ D-84: P0409 «El cierre del cliente antiguo pertenece a otra
  --          persona; requiere conciliación de Gerencia» y nada escrito · A1e (más abajo) el cierre lleva un CE y A1g otro DNI ⇒ D-85:
  --          P0409 «El cierre del cliente antiguo lleva otro documento; requiere conciliación de Gerencia» y nada escrito · A1f el
  --          cierre YA es de la persona ⇒ se absorbe sin tocarlo y el detalle lo dice.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(26, 'ENS210 CLIENTE A1D CIERRE AJENO', v_vend1, true);
  insert into crm.inversionistas (estado) values ('activo') returning id into v_q;
  set local session_replication_role = replica;
  update crm.cierres_externos set inversionista_id = v_q where lead_id = v_c and es_cierre_inicial;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 126, 'ENS210 LEAD A1D');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(26), 'ENS210 LEAD A1D');
  perform pg_temp.medida(format('A1d · antiguo retirado cuyo cierre inicial ya es de OTRA persona → %s', v_res));
  perform pg_temp.reg('A1d-el-cierre-del-antiguo-es-de-otra-persona-p0409-nada-escrito (D-84)',
    pg_temp.juzgar_detenida('A1d-el-cierre-del-antiguo-es-de-otra-persona-p0409-nada-escrito (D-84)', v_res,
      'El cierre del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(26)));

  -- (A23 va aquí, antes de A1e y de A20–A22: lee la ficha de Cartera, y esos casos dejan cierres sin persona que la deshabilitan.)
  v_c := pg_temp.cliente_sin_persona(32, 'ENS210 CLIENTE A23 RETIRADO VEND1', v_vend1, true);
  v_c2 := pg_temp.sembrado_convertido(32, 'ENS210 CLIENTE A23 RETIRADO VEND3', false, v_vend3);
  v_c3 := pg_temp.sembrado_convertido(32, 'ENS210 CLIENTE A23 ACTIVO VEND2', true, v_vend2);
  v_l := pg_temp.lead_nuevo(v_vend2, 132, 'ENS210 LEAD A23');
  perform pg_temp.fotografiar(array[v_c, v_c2, v_c3]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(32), 'ENS210 LEAD A23');
  perform pg_temp.medida(format('A23 · dos retirados (VEND1, VEND3) y un activo del mismo asesor (VEND2) → %s · retirados ahora: %s · notas: %s · cierres con la persona: %s', v_res,
    (select count(*) from crm.leads l where l.id in (v_c, v_c2, v_c3) and not l.activo),
    (select count(*) from crm.actividades a where a.lead_id in (v_c, v_c2, v_c3) and a.metadata ->> 'evento' = 'enlace_identidad'),
    (select count(*) from crm.cierres_externos ce where ce.lead_id in (v_c, v_c2, v_c3) and ce.inversionista_id is not null)));
  v_txt := pg_temp.juzgar_absorcion('A23-dos-retirados-y-un-activo-del-mismo-asesor-los-tres-absorbidos-un-solo-retiro', v_res, v_l, pg_temp.dni(32), array[v_c, v_c2, v_c3], v_vend2, v_vend2);
  if v_txt = '' and ((select count(*) from crm.actividades a where a.lead_id in (v_c, v_c2, v_c3) and a.metadata ->> 'evento' = 'enlace_identidad') <> 1
                     or (select count(*) from crm.inversionista_operaciones o where o.lead_id in (v_c, v_c2, v_c3) and (o.detalle ->> 'retirado_al_absorber')::boolean) <> 1) then
    v_txt := E'FALLO A23-dos-retirados-y-un-activo-del-mismo-asesor-los-tres-absorbidos-un-solo-retiro: debía haber UN solo retiro (una nota y una sola operación con retirado_al_absorber)\n';
  end if;
  perform pg_temp.reg('A23-dos-retirados-y-un-activo-del-mismo-asesor-los-tres-absorbidos-un-solo-retiro', v_txt);
  if v_txt = '' then
    perform pg_temp.reg('A23b-la-ficha-de-cartera-cuenta-los-tres-cierres-absorbidos (D-83)',
      pg_temp.juzgar_ficha('A23b-la-ficha-de-cartera-cuenta-los-tres-cierres-absorbidos (D-83)', v_vend2, (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid, 3, 'prodelco', 'PEN', 3, 3000, array[v_c, v_c2, v_c3]));
  else
    perform pg_temp.reg('A23b-la-ficha-de-cartera-cuenta-los-tres-cierres-absorbidos (D-83)', E'FALLO A23b-la-ficha-de-cartera-cuenta-los-tres-cierres-absorbidos (D-83): no se midió (A23 falló)\n');
  end if;

  -- A1e (D-85; reescrito en la ronda 3). El antiguo es ACTIVO del mismo asesor (VEND2), con una tarea pendiente, y su cierre lleva un CE:
  --     la conversión se DETIENE y NADA cambia —ni el lead que se convierte, ni el antiguo (sigue activo: sin retiro, sin nota, sin
  --     puente), ni su cierre, ni su tarea, ni el libro—; ninguna persona con ese DNI. (Ronda 2: se absorbía sin completar el cierre.)
  v_c := pg_temp.cliente_sin_persona(27, 'ENS210 CLIENTE A1E CIERRE CON CE', v_vend2, false);
  set local session_replication_role = replica;
  update crm.cierres_externos set documento_tipo = 'CE', documento = '000529027' where lead_id = v_c and es_cierre_inicial;
  insert into crm.tareas (lead_id, vendedor_id, asignado_supervisor_id, tipo, titulo, vence_en, estado, creado_por)
  select l.id, l.vendedor_id, l.asignado_supervisor_id, 'llamada', 'ENS210 tarea pendiente A1E', clock_timestamp() + interval '2 days', 'pendiente', l.vendedor_id
  from crm.leads l where l.id = v_c returning id into v_tarea;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 127, 'ENS210 LEAD A1E');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(27), 'ENS210 LEAD A1E');
  perform pg_temp.medida(format('A1e · antiguo ACTIVO del mismo asesor, con una tarea pendiente, cuyo cierre lleva otro documento (CE) → %s · después: antiguo activo=%s, cierre con persona=%s, tarea=%s, puentes del antiguo=%s, notas=%s', v_res,
    (select l.activo from crm.leads l where l.id = v_c),
    (select ce.inversionista_id is not null from crm.cierres_externos ce where ce.lead_id = v_c and ce.es_cierre_inicial),
    (select t.estado from crm.tareas t where t.id = v_tarea),
    (select count(*) from crm.inversionista_leads il where il.lead_id = v_c),
    (select count(*) from crm.actividades a where a.lead_id = v_c and a.metadata ->> 'evento' = 'enlace_identidad')));
  perform pg_temp.reg('A1e-el-cierre-con-otro-documento-detiene-la-conversion-nada-escrito (D-85)',
    pg_temp.juzgar_detenida('A1e-el-cierre-con-otro-documento-detiene-la-conversion-nada-escrito (D-85)', v_res,
      'El cierre del cliente antiguo lleva otro documento; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(27), v_tarea));

  -- A1g (D-85). El antiguo RETIRADO de otro asesor (VEND1) y su cierre lleva OTRO DNI ⇒ la conversión se detiene igual (la puerta de
  --     enlace de Gerencia no distingue un CE de otro DNI: medido en la ronda 3) y nada se escribe.
  v_c := pg_temp.cliente_sin_persona(34, 'ENS210 CLIENTE A1G CIERRE CON OTRO DNI', v_vend1, true);
  set local session_replication_role = replica;
  update crm.cierres_externos set documento = pg_temp.dni(35) where lead_id = v_c and es_cierre_inicial;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 134, 'ENS210 LEAD A1G');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(34), 'ENS210 LEAD A1G');
  perform pg_temp.medida(format('A1g · antiguo retirado de otro asesor cuyo cierre lleva OTRO DNI → %s', v_res));
  perform pg_temp.reg('A1g-el-cierre-con-otro-dni-detiene-la-conversion-nada-escrito (D-85)',
    pg_temp.juzgar_detenida('A1g-el-cierre-con-otro-dni-detiene-la-conversion-nada-escrito (D-85)', v_res,
      'El cierre del cliente antiguo lleva otro documento; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(34)));

  -- A1f. El cierre del antiguo YA es de la persona del DNI (estado sembrado y declarado: la persona existe, sin leads, y el cierre ya la
  --     nombra) ⇒ se absorbe sin tocar el cierre (como la puerta de enlace de Gerencia) y la operación lo dice: cierre_no_completado =
  --     su id, cierre_motivo «el cierre ya es de esta persona». Es el ÚNICO caso que se absorbe sin completar el cierre.
  v_c := pg_temp.cliente_sin_persona(36, 'ENS210 CLIENTE A1F CIERRE YA DE LA PERSONA', v_vend1, true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(36), true, 'ensayo-bloque-2.10');
  set local session_replication_role = replica;
  update crm.cierres_externos set inversionista_id = v_q where lead_id = v_c and es_cierre_inicial;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 136, 'ENS210 LEAD A1F');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(36), 'ENS210 LEAD A1F');
  perform pg_temp.medida(format('A1f · antiguo retirado cuyo cierre YA es de la persona → %s · detalle de la operación: %s', v_res,
    coalesce((select (o.detalle - 'lead_conversion' - 'vendedor_antiguo' - 'vendedor_conversion' - 'cierre_no_completado')::text from crm.inversionista_operaciones o where o.lead_id = v_c), 'ninguna')));
  v_txt := pg_temp.juzgar_absorcion('A1f-el-cierre-que-ya-es-de-la-persona-se-absorbe-sin-tocarlo', v_res, v_l, pg_temp.dni(36), array[v_c], v_vend2, v_vend2);
  if v_txt = '' and (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid is distinct from v_q then
    v_txt := E'FALLO A1f-el-cierre-que-ya-es-de-la-persona-se-absorbe-sin-tocarlo: la conversión no usó la persona que ya tenía el cierre\n';
  end if;
  perform pg_temp.reg('A1f-el-cierre-que-ya-es-de-la-persona-se-absorbe-sin-tocarlo', v_txt);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1i–A1p. EL PERFIL DEL PORTAL DEL ANTIGUO (D-86/D-87; ronda 4), ANTES del cierre, como la puerta de enlace de Gerencia (medida en la
  --          ronda 4: perfil → cierre; misma respuesta para «otro DNI» y «sin documento»). Perfiles creados en la transacción del ensayo.
  --          A1i de OTRA persona ⇒ P0409 · A1j la ficha YA tiene otro perfil ⇒ P0409 · A1k otro DNI ⇒ P0409 · A1p sin documento ⇒ el mismo
  --          P0409 (A1j, A1k y A1p con la cuenta DESACTIVADA, y A1q de OTRA persona y desactivada: D-86 detiene igual) · A1l propio ACTIVO
  --          (un CE de la persona) ⇒ se enlaza a la ficha y la conversión sigue hasta confirmar · A1m propio DESACTIVADO ⇒ NO se enlaza
  --          (D-89), la conversión sigue hasta confirmar y el detalle lo dice ·
  --          A1n propio ACTIVO con el mismo DNI ⇒ el verificador lo trata como cliente (P0481, límite ii, como hoy) · A1o el perfil YA es
  --          de la persona ⇒ el verificador detiene con «ya es cliente» vía identidad (como hoy).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(38, 'ENS210 CLIENTE A1I PERFIL DE OTRA', v_vend1, true);
  v_x := pg_temp.perfil_cliente(38, 'DNI', pg_temp.dni(88), true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(88), true, 'ensayo-bloque-2.10');
  update crm.inversionistas set perfil_id = v_x where id = v_q;
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 138, 'ENS210 LEAD A1I');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(38), 'ENS210 LEAD A1I');
  perform pg_temp.medida(format('A1i · antiguo retirado cuyo perfil del Portal es de OTRA persona → %s', v_res));
  perform pg_temp.reg('A1i-el-perfil-del-antiguo-es-de-otra-persona-p0409-nada-escrito (D-86)',
    pg_temp.juzgar_detenida('A1i-el-perfil-del-antiguo-es-de-otra-persona-p0409-nada-escrito (D-86)', v_res,
      'El perfil del Portal del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(38)));

  v_c := pg_temp.cliente_sin_persona(39, 'ENS210 CLIENTE A1J FICHA CON OTRO PERFIL', v_vend1, true);
  v_x := pg_temp.perfil_cliente(39, 'DNI', pg_temp.dni(39), false);
  v_y := pg_temp.perfil_cliente(89, 'DNI', pg_temp.dni(91), false);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(39), true, 'ensayo-bloque-2.10');
  update crm.inversionistas set perfil_id = v_y where id = v_q;
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 139, 'ENS210 LEAD A1J');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(39), 'ENS210 LEAD A1J');
  perform pg_temp.medida(format('A1j · la ficha de la persona YA tiene otro perfil y el antiguo trae otro → %s', v_res));
  perform pg_temp.reg('A1j-la-ficha-ya-tiene-otra-cuenta-del-portal-p0409-nada-escrito (D-86)',
    pg_temp.juzgar_detenida('A1j-la-ficha-ya-tiene-otra-cuenta-del-portal-p0409-nada-escrito (D-86)', v_res,
      'La ficha ya tiene otra cuenta del Portal; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(39), null, 1));

  v_c := pg_temp.cliente_sin_persona(40, 'ENS210 CLIENTE A1K PERFIL OTRO DNI', v_vend1, true);
  v_x := pg_temp.perfil_cliente(40, 'DNI', pg_temp.dni(90), false);
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 140, 'ENS210 LEAD A1K');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(40), 'ENS210 LEAD A1K');
  perform pg_temp.medida(format('A1k · el perfil del antiguo lleva OTRO DNI → %s', v_res));
  perform pg_temp.reg('A1k-el-perfil-con-otro-dni-p0409-nada-escrito (D-86)',
    pg_temp.juzgar_detenida('A1k-el-perfil-con-otro-dni-p0409-nada-escrito (D-86)', v_res,
      'El perfil del Portal del cliente antiguo lleva otro documento; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(40)));

  v_c := pg_temp.cliente_sin_persona(41, 'ENS210 CLIENTE A1P PERFIL SIN DOCUMENTO', v_vend1, true);
  v_x := pg_temp.perfil_cliente(41, 'DNI', null, false);
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 141, 'ENS210 LEAD A1P');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(41), 'ENS210 LEAD A1P');
  perform pg_temp.medida(format('A1p · el perfil del antiguo NO tiene documento → %s', v_res));
  perform pg_temp.reg('A1p-el-perfil-sin-documento-p0409-nada-escrito (D-86, como Gerencia)',
    pg_temp.juzgar_detenida('A1p-el-perfil-sin-documento-p0409-nada-escrito (D-86, como Gerencia)', v_res,
      'El perfil del Portal del cliente antiguo lleva otro documento; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(41)));

  -- A1l (D-87): la persona del DNI ya existe (sin leads ni responsable) y tiene también un CE verificado (sembrado y declarado); el perfil
  --     del antiguo es ACTIVO y lleva ese CE (su documento es de la persona, pero no es el DNI del lead: el verificador no lo trata como
  --     cliente). ⇒ se absorbe, el perfil se enlaza a la ficha DESPUÉS del UPDATE, el detalle lo dice y la conversión sigue hasta confirmar.
  v_c := pg_temp.cliente_sin_persona(42, 'ENS210 CLIENTE A1L PERFIL PROPIO ACTIVO', v_vend1, true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(42), true, 'ensayo-bloque-2.10');
  set local session_replication_role = replica;
  insert into crm.inversionista_identificadores (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente)
  values (v_q, 'CE', '000529042', '000529042', 'vigente', true, 'ensayo-bloque-2.10');
  set local session_replication_role = origin;
  v_x := pg_temp.perfil_cliente(42, 'CE', '000529042', true);
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 142, 'ENS210 LEAD A1L');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(42), 'ENS210 LEAD A1L');
  perform pg_temp.medida(format('A1l · perfil propio ACTIVO (un CE de la persona) → %s · la ficha después: perfil %s · detalle: %s', v_res,
    coalesce((select case when i.perfil_id = v_x then 'el del antiguo' else i.perfil_id::text end from crm.inversionistas i where i.id = v_q), 'ninguno'),
    coalesce((select (o.detalle - 'lead_conversion' - 'vendedor_antiguo' - 'vendedor_conversion' - 'cierre_completado' - 'perfil_completado')::text
                     || ' perfil_completado=' || coalesce(case when o.detalle ->> 'perfil_completado' = v_x::text then 'el del antiguo' else o.detalle ->> 'perfil_completado' end, 'null')
              from crm.inversionista_operaciones o where o.lead_id = v_c), 'ninguno')));
  v_txt := pg_temp.juzgar_absorcion('A1l-el-perfil-propio-activo-se-enlaza-a-la-ficha-y-la-conversion-sigue (D-87)', v_res, v_l, pg_temp.dni(42), array[v_c], v_vend2, v_vend2);
  if v_txt = '' and ((substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid is distinct from v_q
                     or (select i.perfil_id from crm.inversionistas i where i.id = v_q) is distinct from v_x
                     or (select o.detalle ->> 'perfil_completado' from crm.inversionista_operaciones o where o.lead_id = v_c) is distinct from v_x::text) then
    v_txt := E'FALLO A1l-el-perfil-propio-activo-se-enlaza-a-la-ficha-y-la-conversion-sigue (D-87): el perfil no quedó en la ficha de la persona o la operación no lo dice (perfil_completado)\n';
  end if;
  perform pg_temp.reg('A1l-el-perfil-propio-activo-se-enlaza-a-la-ficha-y-la-conversion-sigue (D-87)', v_txt);
  if v_txt = '' then
    perform pg_temp.reg('A1lb-la-conversion-con-el-perfil-enlazado-sigue-hasta-confirmar (D-87)',
      pg_temp.flujo_completo('A1lb-la-conversion-con-el-perfil-enlazado-sigue-hasta-confirmar (D-87)', v_vend2, v_l, v_q, 'ENS210 LEAD A1L'));
  else
    perform pg_temp.reg('A1lb-la-conversion-con-el-perfil-enlazado-sigue-hasta-confirmar (D-87)', E'FALLO A1lb-la-conversion-con-el-perfil-enlazado-sigue-hasta-confirmar (D-87): no se midió (A1l falló)\n');
  end if;

  -- A1m (D-89; reescrito en la ronda 5): el perfil propio está DESACTIVADO (activo = false) ⇒ NO se enlaza a la ficha: la absorción y la
  --     conversión siguen, `perfil_id` de la persona sigue NULL, la operación dice perfil_no_enlazado (su id) y perfil_motivo «cuenta del
  --     Portal desactivada», y A1mb la confirmación entra. (Ronda 4: se enlazaba y el núcleo detenía la preparación: ROJO.)
  v_c := pg_temp.cliente_sin_persona(43, 'ENS210 CLIENTE A1M PERFIL PROPIO DESACTIVADO', v_vend1, true);
  v_x := pg_temp.perfil_cliente(43, 'DNI', pg_temp.dni(43), false);
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 143, 'ENS210 LEAD A1M');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(43), 'ENS210 LEAD A1M');
  v_per := case when v_res like 'ok|%' then (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid end;
  perform pg_temp.medida(format('A1m · perfil propio DESACTIVADO → %s · la ficha después: perfil %s · detalle: %s', v_res,
    coalesce((select i.perfil_id::text from crm.inversionistas i where i.id = v_per), 'ninguno'),
    coalesce((select jsonb_build_object('perfil_no_enlazado', case when o.detalle ->> 'perfil_no_enlazado' = v_x::text then 'el del antiguo' else o.detalle ->> 'perfil_no_enlazado' end,
                                        'perfil_motivo', o.detalle ->> 'perfil_motivo', 'perfil_completado', o.detalle ->> 'perfil_completado')::text
              from crm.inversionista_operaciones o where o.lead_id = v_c), 'ninguno')));
  v_txt := pg_temp.juzgar_absorcion('A1m-el-perfil-propio-desactivado-no-se-enlaza-y-la-conversion-sigue (D-89)', v_res, v_l, pg_temp.dni(43), array[v_c], v_vend2, v_vend2);
  if v_txt = '' and ((select i.perfil_id from crm.inversionistas i where i.id = v_per) is not null
                     or (select o.detalle ->> 'perfil_no_enlazado' from crm.inversionista_operaciones o where o.lead_id = v_c) is distinct from v_x::text
                     or (select o.detalle ->> 'perfil_motivo' from crm.inversionista_operaciones o where o.lead_id = v_c) is distinct from 'cuenta del Portal desactivada'
                     or (select o.detalle ->> 'perfil_completado' from crm.inversionista_operaciones o where o.lead_id = v_c) is not null) then
    v_txt := E'FALLO A1m-el-perfil-propio-desactivado-no-se-enlaza-y-la-conversion-sigue (D-89): la cuenta desactivada se enlazó a la ficha o la operación no dice perfil_no_enlazado con su motivo\n';
  end if;
  perform pg_temp.reg('A1m-el-perfil-propio-desactivado-no-se-enlaza-y-la-conversion-sigue (D-89)', v_txt);
  if v_txt = '' then
    perform pg_temp.reg('A1mb-la-conversion-sin-la-cuenta-desactivada-sigue-hasta-confirmar (D-89)',
      pg_temp.flujo_completo('A1mb-la-conversion-sin-la-cuenta-desactivada-sigue-hasta-confirmar (D-89)', v_vend2, v_l, v_per, 'ENS210 LEAD A1M'));
  else
    perform pg_temp.reg('A1mb-la-conversion-sin-la-cuenta-desactivada-sigue-hasta-confirmar (D-89)', E'FALLO A1mb-la-conversion-sin-la-cuenta-desactivada-sigue-hasta-confirmar (D-89): no se midió (A1m falló)\n');
  end if;

  -- A1q (D-86 con la cuenta DESACTIVADA): el perfil del antiguo es de OTRA persona y además está desactivado ⇒ D-86 se mira ANTES que D-89:
  --     P0409 «El perfil del Portal del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia», nada escrito.
  v_c := pg_temp.cliente_sin_persona(50, 'ENS210 CLIENTE A1Q PERFIL DE OTRA DESACTIVADO', v_vend1, true);
  v_x := pg_temp.perfil_cliente(50, 'DNI', pg_temp.dni(92), false);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(92), true, 'ensayo-bloque-2.10');
  update crm.inversionistas set perfil_id = v_x where id = v_q;
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 150, 'ENS210 LEAD A1Q');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(50), 'ENS210 LEAD A1Q');
  perform pg_temp.medida(format('A1q · el perfil del antiguo es de OTRA persona y está desactivado → %s', v_res));
  perform pg_temp.reg('A1q-el-perfil-de-otra-persona-desactivado-sigue-deteniendo (D-86 antes que D-89)',
    pg_temp.juzgar_detenida('A1q-el-perfil-de-otra-persona-desactivado-sigue-deteniendo (D-86 antes que D-89)', v_res,
      'El perfil del Portal del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia', v_h, array[v_c, v_l], pg_temp.dni(50)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1h2/A1h3 (test gap de Codex r1): VARIOS ANTIGUOS y el SEGUNDO (por id) se detiene por otra razón que D-85 ⇒ P0409 y NADA queda
  --     del primero. A1h2: dos retirados de VEND1; el segundo trae un perfil del Portal de OTRA persona (D-86). A1h3: dos ACTIVOS del
  --     mismo asesor; el segundo no tiene cierre ni perfil: el retiro es imposible (P3-2.i).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado_convertido(51, 'ENS210 CLIENTE A1H2 RETIRADO UNO', false, v_vend1);
  v_c2 := pg_temp.sembrado_convertido(51, 'ENS210 CLIENTE A1H2 RETIRADO DOS', false, v_vend1);
  if v_c > v_c2 then
    v_c3 := v_c; v_c := v_c2; v_c2 := v_c3;
  end if;
  v_x := pg_temp.perfil_cliente(51, 'DNI', pg_temp.dni(93), false);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(93), true, 'ensayo-bloque-2.10');
  update crm.inversionistas set perfil_id = v_x where id = v_q;
  perform pg_temp.con_perfil(v_c2, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 151, 'ENS210 LEAD A1H2');
  perform pg_temp.fotografiar(array[v_c, v_c2, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(51), 'ENS210 LEAD A1H2');
  perform pg_temp.medida(format('A1h2 · dos retirados; el segundo (por id) con un perfil de OTRA persona → %s', v_res));
  perform pg_temp.reg('A1h2-varios-antiguos-el-segundo-se-detiene-por-d86-y-no-queda-nada-del-primero',
    pg_temp.juzgar_detenida('A1h2-varios-antiguos-el-segundo-se-detiene-por-d86-y-no-queda-nada-del-primero', v_res,
      'El perfil del Portal del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia', v_h, array[v_c, v_c2, v_l], pg_temp.dni(51)));

  v_c := pg_temp.sembrado_convertido(52, 'ENS210 CLIENTE A1H3 ACTIVO UNO', true, v_vend2);
  v_c2 := pg_temp.sembrado_convertido(52, 'ENS210 CLIENTE A1H3 ACTIVO DOS', true, v_vend2);
  if v_c > v_c2 then
    v_c3 := v_c; v_c := v_c2; v_c2 := v_c3;
  end if;
  set local session_replication_role = replica;
  delete from crm.cierres_externos where lead_id = v_c2 and es_cierre_inicial;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 152, 'ENS210 LEAD A1H3');
  perform pg_temp.fotografiar(array[v_c, v_c2, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(52), 'ENS210 LEAD A1H3');
  perform pg_temp.medida(format('A1h3 · dos activos del mismo asesor; el segundo (por id) sin cierre ni perfil → %s', v_res));
  perform pg_temp.reg('A1h3-varios-antiguos-el-segundo-no-se-puede-retirar-y-no-queda-nada-del-primero',
    pg_temp.juzgar_detenida('A1h3-varios-antiguos-el-segundo-no-se-puede-retirar-y-no-queda-nada-del-primero', v_res,
      'El cliente antiguo no se puede retirar; requiere conciliación de Gerencia', v_h, array[v_c, v_c2, v_l], pg_temp.dni(52)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1r/A1r2/A1r3/A1s/U7 (D-90, D-91; P2-1 de Codex r1). Un convertido sin puntero con PUENTE HISTÓRICO PREEXISTENTE a la MISMA persona
  --     (estado de Gerencia o de la carga de septiembre; sembrado y declarado). No es candidato a absorción (ya tiene puente). En los tres
  --     casos de D-91 el lead que se convierte nace por el alta SIN DNI: la conversión lo ESCRIBE y por eso correría el verificador
  --     (ronda 8: D-91 solo en ese caso; con el DNI ya escrito o con un CE la conversión sigue: A1u, A1u2, A1v, abajo).
  --     A1r RETIRADO ⇒ D-91 (ronda 7): en la puerta la historia solo exime si la puso ESTA conversión; ese puente es de ANTES ⇒ el P0409
  --          de conciliación de hoy con su texto EXACTO, sin P0481, nada escrito (en la ronda 6 la historia lo dejaba pasar y el
  --          verificador sellado, al escribir el DNI, paraba con P0481 «ya es cliente» vía identidad: ROJO). D-92 lo hará convertir.
  --     A1r2 lo mismo, con OTRO antiguo sin ficha del mismo DNI por absorber ⇒ igual y nada escrito, tampoco la absorción del otro: la
  --          operación de enlace del otro (lead_conversion = este lead) no exime al de antes (la exención va por lead).
  --     A1r3 lo mismo, pero el puente de antes lleva la operación de enlace de OTRA conversión (sembrada y declarada: lead_conversion = un
  --          lead que ya no cuenta como lead de la persona; en la casa ese lead sigue contando —A1t—: el caso aísla «la puso ESTA conversión»).
  --     A1s ACTIVO ⇒ como hoy: P0409 «Esta persona ya tiene otra identidad o lead; requiere conciliación», nada escrito (en la ronda 5 la
  --          historia lo eximía y paraba el verificador con P0481: ROJO).
  --     U7 el contrato de la pieza: historia(A1r) = sí, historia(A1s) = no (los núcleos mantienen D-90).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c4 := pg_temp.cliente_sin_persona(53, 'ENS210 CLIENTE A1R RETIRADO YA UNIDO', v_vend1, true);
  v_q2 := private.inversionista_resolver('DNI', pg_temp.dni(53), true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q2, v_c4, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 153, 'ENS210 LEAD A1R');
  perform pg_temp.fotografiar(array[v_c4, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(53), 'ENS210 LEAD A1R');
  perform pg_temp.medida(format('A1r · convertido RETIRADO ya unido por puente histórico ANTES de esta preparación → %s', v_res));
  perform pg_temp.reg('A1r-retirado-ya-unido-antes-de-esta-preparacion-requiere-conciliacion (D-91)',
    pg_temp.juzgar_d91('A1r-retirado-ya-unido-antes-de-esta-preparacion-requiere-conciliacion (D-91)', v_res, v_h, array[v_c4, v_l], pg_temp.dni(53)));

  v_c := pg_temp.cliente_sin_persona(58, 'ENS210 CLIENTE A1R2 RETIRADO YA UNIDO', v_vend1, true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(58), true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_c2 := pg_temp.sembrado_convertido(58, 'ENS210 CLIENTE A1R2 OTRO ANTIGUO SIN FICHA', false, v_vend1);
  v_l := pg_temp.lead_nuevo(v_vend2, 158, 'ENS210 LEAD A1R2');
  perform pg_temp.fotografiar(array[v_c, v_c2, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(58), 'ENS210 LEAD A1R2');
  perform pg_temp.medida(format('A1r2 · el retirado ya unido ANTES y otro antiguo sin ficha del mismo DNI por absorber → %s', v_res));
  perform pg_temp.reg('A1r2-retirado-ya-unido-antes-y-otro-por-absorber-requiere-conciliacion-sin-escribir (D-91)',
    pg_temp.juzgar_d91('A1r2-retirado-ya-unido-antes-y-otro-por-absorber-requiere-conciliacion-sin-escribir (D-91)', v_res, v_h, array[v_c, v_c2, v_l], pg_temp.dni(58)));

  v_c := pg_temp.cliente_sin_persona(59, 'ENS210 CLIENTE A1R3 RETIRADO YA UNIDO POR OTRA CONVERSION', v_vend1, true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(59), true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_y := pg_temp.lead_nuevo(v_vend1, 160, 'ENS210 LEAD A1R3 DE LA OTRA CONVERSION');
  insert into crm.inversionista_operaciones (tipo, inversionista_id, lead_id, motivo, detalle, por)
  values ('enlace', v_q, v_c, 'Conversión: cliente antiguo sin ficha de persona, enlazado a la misma ficha (D-38)',
          jsonb_build_object('via', 'preparar_conversion_inversion', 'rol', 'historico', 'lead_conversion', v_y,
                             'lead_antiguo_activo', false, 'retirado_al_absorber', false), v_vend1);
  v_l := pg_temp.lead_nuevo(v_vend2, 159, 'ENS210 LEAD A1R3');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(59), 'ENS210 LEAD A1R3');
  perform pg_temp.medida(format('A1r3 · el retirado ya unido ANTES con la operación de enlace de OTRA conversión → %s', v_res));
  perform pg_temp.reg('A1r3-la-operacion-de-otra-conversion-no-exime-requiere-conciliacion (D-91)',
    pg_temp.juzgar_d91('A1r3-la-operacion-de-otra-conversion-no-exime-requiere-conciliacion (D-91)', v_res, v_h, array[v_c, v_l], pg_temp.dni(59)));

  v_c := pg_temp.cliente_sin_persona(54, 'ENS210 CLIENTE A1S ACTIVO YA UNIDO', v_vend1, false);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(54), true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 154, 'ENS210 LEAD A1S');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(54), 'ENS210 LEAD A1S');
  perform pg_temp.medida(format('A1s · convertido ACTIVO ya unido por puente histórico a la misma persona → %s', v_res));
  perform pg_temp.reg('A1s-activo-ya-unido-por-puente-sigue-siendo-otro-lead-como-hoy (D-90)',
    pg_temp.juzgar_conciliacion('A1s-activo-ya-unido-por-puente-sigue-siendo-otro-lead-como-hoy (D-90)', v_res, v_h));

  if v_historia is not null then
    execute 'select private.lead_historia_de_persona($1, $2) and not private.lead_historia_de_persona($3, $4)' into v_b using v_c4, v_q2, v_c, v_q;
    perform pg_temp.reg('U7-la-historia-solo-de-los-retirados (D-90)',
      case when v_b then '' else E'FALLO U7-la-historia-solo-de-los-retirados (D-90): la pieza no dice sí al retirado ya unido y no al activo ya unido\n' end);
  else
    perform pg_temp.reg('U7-la-historia-solo-de-los-retirados (D-90)', E'FALLO U7-la-historia-solo-de-los-retirados (D-90): no existe private.lead_historia_de_persona\n');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1u/A1u2/A1v (ronda 8: D-91 SOLO cuando esta preparación ESCRIBE el DNI del lead). El UPDATE de la puerta (l. 93-94 de su definición
  --     viva) cambia el DNI solo si el documento es un DNI que el lead aún no lleva, y solo entonces el disparador de disponibilidad llama al
  --     verificador sellado (l. 42-43 y 70 de su función). Con el DNI ya escrito, o con un CE (que no se escribe en crm.leads.dni), el
  --     verificador no corre y manda D-90: el retirado ya unido por puente histórico ANTES cuenta como historia y la conversión SIGUE (en
  --     la ronda 7 D-91 la detenía con el P0409 de conciliación). Estados sembrados y declarados (disparadores apagados), como A1r:
  --     A1u  el estado del backfill de identidad y de la carga: el lead vivo lleva el DNI, apunta a la persona y es su puente canónico, y la
  --          persona tiene además un convertido RETIRADO sin puntero con puente histórico de antes ⇒ ok con la MISMA persona, el antiguo
  --          intacto (nada que absorber), el lead con su DNI y su puntero, quien convierte como responsable; A1ub: la conversión SIGUE hasta
  --          confirmar (la pantalla puede operar —nueva_inversion— y la confirmación entra).
  --     A1u2 lo mismo, pero el lead lleva el DNI y aún no apunta a la persona (ni puente): la condición es el DNI, no el puntero.
  --     A1v  el documento es un CE (el UPDATE no escribe DNI): la persona del CE tiene el retirado con puente histórico de antes ⇒ ok y la
  --          conversión sigue hasta confirmar.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(60, 'ENS210 CLIENTE A1U RETIRADO YA UNIDO', v_vend1, true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(60), true, 'ensayo-bloque-2.10');
  v_l := pg_temp.lead_nuevo(v_vend2, 162, 'ENS210 LEAD A1U VIVO CANONICO');
  set local session_replication_role = replica;
  update crm.leads set dni = pg_temp.dni(60), inversionista_id = v_q where id = v_l;
  set local session_replication_role = origin;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_l, 'canonico');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(60), 'ENS210 LEAD A1U VIVO CANONICO');
  perform pg_temp.medida(format('A1u · el lead vivo YA lleva el DNI (y es el canónico de la persona) y la persona tiene un convertido RETIRADO ya unido por puente histórico de antes → %s', v_res));
  if v_res like 'ok|%' then
    begin
      perform pg_temp.sesion(v_vend2);
      v_r := crm.contexto_conversion_inversion_fn(v_l, v_q);
      perform pg_temp.sesion(null);
      perform pg_temp.medida(format('A1u · la pantalla (núcleo de lectura) → capacidades.nueva_inversion=%s', v_r #>> '{capacidades,nueva_inversion}'));
    exception when others then
      perform pg_temp.sesion(null);
      perform pg_temp.medida(format('A1u · la pantalla (núcleo de lectura) → %s %s', sqlstate, sqlerrm));
    end;
  end if;
  v_txt := pg_temp.juzgar_dni_ya_escrito('A1u-el-lead-ya-lleva-el-dni-el-retirado-ya-unido-cuenta-como-historia-la-conversion-sigue (D-90, D-91 solo si escribe el DNI)',
             v_res, v_l, v_q, 'DNI', pg_temp.dni(60), pg_temp.dni(60), v_c, v_vend2);
  perform pg_temp.reg('A1u-el-lead-ya-lleva-el-dni-el-retirado-ya-unido-cuenta-como-historia-la-conversion-sigue (D-90, D-91 solo si escribe el DNI)', v_txt);
  if v_txt = '' then
    perform pg_temp.reg('A1ub-con-el-dni-ya-escrito-la-conversion-sigue-hasta-confirmar (D-90)',
      pg_temp.flujo_completo('A1ub-con-el-dni-ya-escrito-la-conversion-sigue-hasta-confirmar (D-90)', v_vend2, v_l, v_q, 'ENS210 LEAD A1U VIVO CANONICO'));
  else
    perform pg_temp.reg('A1ub-con-el-dni-ya-escrito-la-conversion-sigue-hasta-confirmar (D-90)', E'FALLO A1ub-con-el-dni-ya-escrito-la-conversion-sigue-hasta-confirmar (D-90): no se midió (A1u falló)\n');
  end if;

  v_c := pg_temp.cliente_sin_persona(62, 'ENS210 CLIENTE A1U2 RETIRADO YA UNIDO', v_vend1, true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(62), true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 164, 'ENS210 LEAD A1U2 CON DNI SIN PUNTERO');
  set local session_replication_role = replica;
  update crm.leads set dni = pg_temp.dni(62) where id = v_l;
  set local session_replication_role = origin;
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(62), 'ENS210 LEAD A1U2 CON DNI SIN PUNTERO');
  perform pg_temp.medida(format('A1u2 · el lead vivo lleva el DNI y aún no apunta a la persona (sin puntero ni puente) → %s', v_res));
  v_txt := pg_temp.juzgar_dni_ya_escrito('A1u2-el-lead-con-el-dni-y-sin-puntero-tambien-sigue (D-90, D-91 solo si escribe el DNI)',
             v_res, v_l, v_q, 'DNI', pg_temp.dni(62), pg_temp.dni(62), v_c, v_vend2);
  if v_txt = '' then
    v_txt := pg_temp.flujo_completo('A1u2-el-lead-con-el-dni-y-sin-puntero-tambien-sigue (D-90, D-91 solo si escribe el DNI)', v_vend2, v_l, v_q, 'ENS210 LEAD A1U2 CON DNI SIN PUNTERO');
  end if;
  perform pg_temp.reg('A1u2-el-lead-con-el-dni-y-sin-puntero-tambien-sigue (D-90, D-91 solo si escribe el DNI)', v_txt);

  v_c := pg_temp.cliente_sin_persona(63, 'ENS210 CLIENTE A1V RETIRADO UNIDO A UN CE', v_vend1, true);
  v_q := private.inversionista_resolver('CE', '000529063', true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 165, 'ENS210 LEAD A1V CE');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'CE', '000529063', 'ENS210 LEAD A1V CE');
  perform pg_temp.medida(format('A1v · el documento es un CE (el UPDATE no escribe DNI) y la persona del CE tiene un retirado ya unido por puente histórico de antes → %s', v_res));
  v_txt := pg_temp.juzgar_dni_ya_escrito('A1v-con-un-ce-el-verificador-no-corre-y-la-conversion-sigue (D-90, D-91 solo si escribe el DNI)',
             v_res, v_l, v_q, 'CE', '000529063', null, v_c, v_vend2);
  if v_txt = '' then
    v_txt := pg_temp.flujo_completo('A1v-con-un-ce-el-verificador-no-corre-y-la-conversion-sigue (D-90, D-91 solo si escribe el DNI)', v_vend2, v_l, v_q, 'ENS210 LEAD A1V CE');
  end if;
  perform pg_temp.reg('A1v-con-un-ce-el-verificador-no-corre-y-la-conversion-sigue (D-90, D-91 solo si escribe el DNI)', v_txt);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1w/A1wb/A1wc/A1wv (ronda 9: D-94; P2-1 de Codex r2, medido por el Director). El «No insistir» de un antiguo de la persona detiene SIEMPRE la
  --     conversión con la respuesta que hoy da el verificador sellado en A15/A20 —P0481 «Contacto no disponible», {"estado": "no_contactar"}—, aunque
  --     el verificador no corra. Estados sembrados y declarados (disparadores apagados), como A1u/A1v:
  --     A1w  (M1) el lead YA lleva el DNI y la persona tiene un RETIRADO con puente histórico de antes y No insistir ⇒ historia (D-90) con veto ⇒
  --          P0481 no_contactar; nada escrito (la huella igual; el antiguo intacto; la persona de antes, UNA). En la ronda 8 convertía.
  --     A1wc (M2) el lead YA lleva el DNI y hay un RETIRADO sin puente (candidato a absorción) con No insistir ⇒ P0481 no_contactar; el antiguo NO se
  --          absorbe (ni cierre completado, ni puente, ni operación) y la persona que creó el resolver se deshace (cero). En la ronda 8 lo absorbía.
  --     A1wv (M4) el documento es un CE: la persona del CE tiene el retirado ya unido con No insistir ⇒ lo mismo que A1w. En la ronda 8 convertía.
  --     A1wb (M1b, control) el lead nace SIN DNI (la conversión lo escribe), mismo retirado ya unido con No insistir ⇒ sigue el P0409 de conciliación de
  --          D-91, con su texto exacto, sin P0481 (la comprobación de D-94 va DESPUÉS de la conciliación).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(64, 'ENS210 CLIENTE A1W RETIRADO YA UNIDO NO INSISTIR', v_vend1, true);
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_c;
  set local session_replication_role = origin;
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(64), true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 167, 'ENS210 LEAD A1W CON DNI');
  set local session_replication_role = replica;
  update crm.leads set dni = pg_temp.dni(64) where id = v_l;
  set local session_replication_role = origin;
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(64), 'ENS210 LEAD A1W CON DNI');
  perform pg_temp.medida(format('A1w · el lead YA lleva el DNI y la persona tiene un RETIRADO ya unido por puente histórico de antes con No insistir → %s', left(v_res, 200)));
  perform pg_temp.reg('A1w-el-lead-ya-lleva-el-dni-el-retirado-ya-unido-tiene-no-insistir-p0481-no-contactar-nada-escrito (D-94)',
    pg_temp.juzgar_no_insistir('A1w-el-lead-ya-lleva-el-dni-el-retirado-ya-unido-tiene-no-insistir-p0481-no-contactar-nada-escrito (D-94)', v_res, v_h, array[v_c, v_l], 'DNI', pg_temp.dni(64), 1));

  v_c := pg_temp.cliente_sin_persona(65, 'ENS210 CLIENTE A1WB RETIRADO YA UNIDO NO INSISTIR', v_vend1, true);
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_c;
  set local session_replication_role = origin;
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(65), true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 168, 'ENS210 LEAD A1WB SIN DNI');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(65), 'ENS210 LEAD A1WB SIN DNI');
  perform pg_temp.medida(format('A1wb · el lead SIN DNI y el mismo retirado ya unido con No insistir → %s', left(v_res, 200)));
  perform pg_temp.reg('A1wb-el-lead-sin-dni-sigue-el-p0409-de-conciliacion-de-d91 (control: D-94 va despues de la conciliacion)',
    pg_temp.juzgar_d91('A1wb-el-lead-sin-dni-sigue-el-p0409-de-conciliacion-de-d91 (control: D-94 va despues de la conciliacion)', v_res, v_h, array[v_c, v_l], pg_temp.dni(65)));

  v_c := pg_temp.cliente_sin_persona(66, 'ENS210 CLIENTE A1WC RETIRADO POR ABSORBER NO INSISTIR', v_vend1, true);
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_c;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 169, 'ENS210 LEAD A1WC CON DNI');
  set local session_replication_role = replica;
  update crm.leads set dni = pg_temp.dni(66) where id = v_l;
  set local session_replication_role = origin;
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(66), 'ENS210 LEAD A1WC CON DNI');
  perform pg_temp.medida(format('A1wc · el lead YA lleva el DNI y hay un RETIRADO sin puente (por absorber) con No insistir → %s · puente del antiguo: %s · operaciones de enlace: %s',
    left(v_res, 200), coalesce((select il.rol from crm.inversionista_leads il where il.lead_id = v_c), 'ninguno'),
    (select count(*) from crm.inversionista_operaciones o where o.tipo = 'enlace' and o.lead_id = v_c)));
  perform pg_temp.reg('A1wc-el-lead-ya-lleva-el-dni-el-retirado-por-absorber-tiene-no-insistir-p0481-no-contactar-sin-absorber (D-94)',
    pg_temp.juzgar_no_insistir('A1wc-el-lead-ya-lleva-el-dni-el-retirado-por-absorber-tiene-no-insistir-p0481-no-contactar-sin-absorber (D-94)', v_res, v_h, array[v_c, v_l], 'DNI', pg_temp.dni(66), 0));

  v_c := pg_temp.cliente_sin_persona(67, 'ENS210 CLIENTE A1WV RETIRADO UNIDO A UN CE NO INSISTIR', v_vend1, true);
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_c;
  set local session_replication_role = origin;
  v_q := private.inversionista_resolver('CE', '000529067', true, 'ensayo-bloque-2.10');
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_q, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 170, 'ENS210 LEAD A1WV CE');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'CE', '000529067', 'ENS210 LEAD A1WV CE');
  perform pg_temp.medida(format('A1wv · el documento es un CE y la persona del CE tiene un retirado ya unido por puente histórico de antes con No insistir → %s', left(v_res, 200)));
  perform pg_temp.reg('A1wv-con-un-ce-el-retirado-ya-unido-tiene-no-insistir-p0481-no-contactar-nada-escrito (D-94)',
    pg_temp.juzgar_no_insistir('A1wv-con-un-ce-el-retirado-ya-unido-tiene-no-insistir-p0481-no-contactar-nada-escrito (D-94)', v_res, v_h, array[v_c, v_l], 'CE', '000529067', 1));

  -- U9 (Codex r2, juez): `juzgar_dni_ya_escrito` no puede aprobar un lead que NO existe (antes comprobaba con `if (select …)`: una fila ausente daba
  --     NULL y no añadía fallo). Se le da una respuesta «ok» de un lead y una persona inexistentes: tiene que señalar el lead.
  v_u9 := gen_random_uuid(); v_u9p := gen_random_uuid();
  v_txt := pg_temp.juzgar_dni_ya_escrito('U9-sonda', 'ok|' || jsonb_build_object('inversionista_id', v_u9p, 'lead_id', v_u9)::text, v_u9, v_u9p, 'DNI', '00000000', '00000000', gen_random_uuid(), v_vend2);
  perform pg_temp.reg('U9-el-juez-del-dni-ya-escrito-no-aprueba-un-lead-ausente (Codex r2)',
    case when position('el lead no quedó con su DNI de antes y apuntando a la persona' in v_txt) > 0 then ''
         else format(E'FALLO U9-el-juez-del-dni-ya-escrito-no-aprueba-un-lead-ausente (Codex r2): el juez no señaló la fila ausente del lead (devolvió «%s»)\n', v_txt) end);

  -- A1n (límite ii, como hoy): el perfil propio está ACTIVO y lleva el MISMO DNI ⇒ el verificador, al escribir el DNI en el lead que se
  --     convierte, lo trata como cliente del Portal: P0481 con «ya es cliente de <asesor del perfil>» (sin asesor: «sin asesor asignado»).
  v_c := pg_temp.cliente_sin_persona(44, 'ENS210 CLIENTE A1N PERFIL PROPIO ACTIVO MISMO DNI', v_vend1, true);
  v_x := pg_temp.perfil_cliente(44, 'DNI', pg_temp.dni(44), true);
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 144, 'ENS210 LEAD A1N');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(44), 'ENS210 LEAD A1N');
  perform pg_temp.medida(format('A1n · perfil propio ACTIVO con el mismo DNI (límite ii) → %s', v_res));
  perform pg_temp.reg('A1n-el-perfil-propio-activo-con-el-mismo-dni-el-verificador-lo-trata-como-cliente (limite ii, como hoy)',
    pg_temp.juzgar_veredicto('A1n-el-perfil-propio-activo-con-el-mismo-dni-el-verificador-lo-trata-como-cliente (limite ii, como hoy)', v_res,
      jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado'), v_l, pg_temp.dni(44), array[v_c], v_h));

  -- A1o (como hoy): el perfil YA es de la persona del DNI (que existe, sin leads) ⇒ la pieza no lo toca, pero el verificador trata a una
  --     persona con perfil enlazado como cliente: P0481 vía identidad (el asesor es el responsable que la puerta le acaba de poner).
  v_c := pg_temp.cliente_sin_persona(45, 'ENS210 CLIENTE A1O PERFIL YA DE LA PERSONA', v_vend1, true);
  v_x := pg_temp.perfil_cliente(45, 'DNI', pg_temp.dni(45), false);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(45), true, 'ensayo-bloque-2.10');
  update crm.inversionistas set perfil_id = v_x where id = v_q;
  perform pg_temp.con_perfil(v_c, v_x);
  v_l := pg_temp.lead_nuevo(v_vend2, 145, 'ENS210 LEAD A1O');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(45), 'ENS210 LEAD A1O');
  perform pg_temp.medida(format('A1o · el perfil del antiguo YA es de la persona → %s', v_res));
  e := pg_temp.error_de(v_res);
  perform pg_temp.reg('A1o-el-perfil-ya-de-la-persona-el-verificador-la-trata-como-cliente (como hoy)',
    case when e.estado = 'P0481' and pg_temp.a_jsonb(e.detalle) = jsonb_build_object('via', 'identidad', 'estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND2')
              and pg_temp.huella_escritura() = v_h and pg_temp.personas_con_dni(pg_temp.dni(45)) = 1
              and pg_temp.ficha(v_c) = (select f.foto from ens_fotos f where f.id = v_c) then ''
         else format(E'FALLO A1o-el-perfil-ya-de-la-persona-el-verificador-la-trata-como-cliente (como hoy): se esperaba P0481 con {"via":"identidad","asesor":"PASO08 VEND2","estado":"ya_es_cliente"} sin escribir y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1h (test gap del auditor r2). VARIOS ANTIGUOS con el DNI: dos ACTIVOS del mismo asesor; la pieza los trata por id, así que al de id
  --     menor (con una tarea pendiente) se le hace todo —cierre completado, libro, nota, retiro, tarea cancelada— y el de id mayor, cuyo
  --     cierre lleva un CE, DETIENE la conversión (D-85) ⇒ P0409 y NADA queda: los dos siguen activos, el cierre del primero sigue sin
  --     persona, su tarea sigue pendiente, sin libro, nota ni puente, sin persona nueva.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado_convertido(46, 'ENS210 CLIENTE A1H ACTIVO UNO', true, v_vend2);
  v_c2 := pg_temp.sembrado_convertido(46, 'ENS210 CLIENTE A1H ACTIVO DOS', true, v_vend2);
  if v_c > v_c2 then
    v_c3 := v_c; v_c := v_c2; v_c2 := v_c3;
  end if;
  set local session_replication_role = replica;
  update crm.cierres_externos set documento_tipo = 'CE', documento = '000529046' where lead_id = v_c2 and es_cierre_inicial;
  insert into crm.tareas (lead_id, vendedor_id, asignado_supervisor_id, tipo, titulo, vence_en, estado, creado_por)
  select l.id, l.vendedor_id, l.asignado_supervisor_id, 'llamada', 'ENS210 tarea pendiente A1H', clock_timestamp() + interval '2 days', 'pendiente', l.vendedor_id
  from crm.leads l where l.id = v_c returning id into v_tarea;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 146, 'ENS210 LEAD A1H');
  perform pg_temp.fotografiar(array[v_c, v_c2, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(46), 'ENS210 LEAD A1H');
  perform pg_temp.medida(format('A1h · dos antiguos activos del mismo asesor; el segundo (por id) con el cierre en CE → %s', v_res));
  perform pg_temp.reg('A1h-varios-antiguos-el-segundo-se-detiene-y-no-queda-nada-del-primero',
    pg_temp.juzgar_detenida('A1h-varios-antiguos-el-segundo-se-detiene-y-no-queda-nada-del-primero', v_res,
      'El cierre del cliente antiguo lleva otro documento; requiere conciliación de Gerencia', v_h, array[v_c, v_c2, v_l], pg_temp.dni(46), v_tarea));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A1fb (A1f-b del auditor r2). El estado que deja el BACKFILL: la persona del DNI existe con responsable = el vendedor del cierre (VEND1,
  --     con su tramo abierto) y el cierre del antiguo ya es suyo; convierte OTRO asesor (VEND2) ⇒ el P0409 de responsable de la puerta
  --     («El responsable de la persona y el analista del lead deben coincidir antes de invertir»), que va después de la absorción y la
  --     deshace: nada escrito.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(47, 'ENS210 CLIENTE A1FB BACKFILL', v_vend1, true);
  v_q := private.inversionista_resolver('DNI', pg_temp.dni(47), true, 'ensayo-bloque-2.10');
  set local session_replication_role = replica;
  update crm.inversionistas set responsable_relacion_id = v_vend1 where id = v_q;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo, por) values (v_q, v_vend1, 'backfill_multiempresa', v_vend1);
  update crm.cierres_externos set inversionista_id = v_q where lead_id = v_c and es_cierre_inicial;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 147, 'ENS210 LEAD A1FB');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(47), 'ENS210 LEAD A1FB');
  perform pg_temp.medida(format('A1fb · persona del backfill con responsable VEND1; convierte VEND2 → %s', v_res));
  perform pg_temp.reg('A1fb-la-persona-del-backfill-tiene-otro-responsable-p0409-nada-escrito',
    pg_temp.juzgar_detenida('A1fb-la-persona-del-backfill-tiene-otro-responsable-p0409-nada-escrito', v_res,
      'El responsable de la persona y el analista del lead deben coincidir antes de invertir', v_h, array[v_c, v_l], pg_temp.dni(47), null, 1));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A20–A23. FRONTERAS (P3-6). A20 el antiguo ACTIVO del MISMO asesor tiene «No insistir» ⇒ el veto manda: el verificador que corre al
  --          escribir el DNI responde P0481 {"estado": "no_contactar"} y el rechazo deshace la absorción y el retiro; nada escrito ·
  --          A21 el SUPERVISOR (SUP1) convierte el lead de VEND2 con un antiguo ACTIVO de VEND1 (otro analista de SU equipo) ⇒ «ya es
  --          cliente de PASO08 VEND1» (la referencia del alta por SUP1), no absorbe · A22 GERENCIA convierte el lead de VEND2 con un
  --          antiguo ACTIVO de VEND1 ⇒ el veredicto, no absorbe · A23 dos retirados (VEND1, VEND3) y uno ACTIVO del mismo asesor (VEND2)
  --          ⇒ los tres absorbidos, UN solo retiro (una nota), y Cartera cuenta los tres cierres.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado_convertido(29, 'ENS210 CLIENTE A20 ACTIVO VETADO MISMO', true, v_vend2, null, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 129, 'ENS210 LEAD A20');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(29), 'ENS210 LEAD A20');
  perform pg_temp.medida(format('A20 · antiguo ACTIVO del mismo asesor con No insistir → %s', v_res));
  perform pg_temp.reg('A20-antiguo-activo-del-mismo-asesor-con-no-insistir-el-veto-manda-nada-escrito',
    pg_temp.juzgar_veredicto('A20-antiguo-activo-del-mismo-asesor-con-no-insistir-el-veto-manda-nada-escrito', v_res, jsonb_build_object('estado', 'no_contactar'), v_l, pg_temp.dni(29), array[v_c], v_h));

  v_c := pg_temp.cliente_sin_persona(30, 'ENS210 CLIENTE A21 ACTIVO VEND1', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 130, 'ENS210 LEAD A21');
  v_esp := pg_temp.referencia_alta(v_sup1, 930, pg_temp.dni(30));
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_sup1, v_l, 'DNI', pg_temp.dni(30), 'ENS210 LEAD A21');
  perform pg_temp.medida(format('A21 · SUP1 convierte el lead de VEND2 con un antiguo activo de VEND1 (su equipo) → %s (referencia del alta por SUP1: %s)', v_res, v_esp));
  v_txt := pg_temp.juzgar_veredicto('A21-el-supervisor-con-un-antiguo-activo-de-otro-analista-de-su-equipo-ya-es-cliente-de-ese-analista', v_res, v_esp, v_l, pg_temp.dni(30), array[v_c], v_h);
  if v_txt = '' and v_esp ->> 'asesor' is distinct from 'PASO08 VEND1' then
    v_txt := format(E'FALLO A21-el-supervisor-con-un-antiguo-activo-de-otro-analista-de-su-equipo-ya-es-cliente-de-ese-analista: el veredicto no nombra a VEND1 (%s)\n', v_esp);
  end if;
  perform pg_temp.reg('A21-el-supervisor-con-un-antiguo-activo-de-otro-analista-de-su-equipo-ya-es-cliente-de-ese-analista', v_txt);

  v_c := pg_temp.cliente_sin_persona(31, 'ENS210 CLIENTE A22 ACTIVO VEND1', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 131, 'ENS210 LEAD A22');
  v_esp := pg_temp.referencia_alta(v_ger, 931, pg_temp.dni(31));
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_ger, v_l, 'DNI', pg_temp.dni(31), 'ENS210 LEAD A22');
  perform pg_temp.medida(format('A22 · Gerencia convierte el lead de VEND2 con un antiguo activo de VEND1 → %s (referencia del alta por Gerencia: %s)', v_res, v_esp));
  perform pg_temp.reg('A22-gerencia-con-un-antiguo-activo-de-otro-asesor-recibe-el-veredicto-no-absorbe',
    pg_temp.juzgar_veredicto('A22-gerencia-con-un-antiguo-activo-de-otro-asesor-recibe-el-veredicto-no-absorbe', v_res, v_esp, v_l, pg_temp.dni(31), array[v_c], v_h));


  -- (A3 va aquí, detrás de los casos que leen la ficha de Cartera: su antiguo deja un cierre SIN persona y Cartera se deshabilita
  --  para todos en cuanto existe uno —cobertura de crm.cartera_inversionistas_estado_fn—; medido en la ronda 2.)
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A3. CLIENTE ANTIGUO ACTIVO DE OTRO ASESOR (VEND1): VEND2 convierte otro lead con ese DNI ⇒ «ya es cliente de VEND1» (la referencia
  --     del alta) con P0481, nada escrito, ninguna persona creada. Hoy: P0409 «requiere conciliación» (medida).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(3, 'ENS210 CLIENTE A3 ACTIVO OTRO', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 103, 'ENS210 LEAD A3');
  v_esp := pg_temp.referencia_alta(v_vend2, 903, pg_temp.dni(3));
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(3), 'ENS210 LEAD A3');
  perform pg_temp.medida(format('A3 · preparar con el DNI de un cliente antiguo ACTIVO de otro asesor → %s (referencia del alta: %s)', v_res, v_esp));
  e := pg_temp.error_de(v_res);
  perform pg_temp.medida(format('P · lo que recibe la pantalla en A3: code=%s · message=%s · details=%s', e.estado, e.mensaje, coalesce(e.detalle, '(vacío)')));
  perform pg_temp.reg('A3-activo-de-otro-asesor-ya-es-cliente', pg_temp.juzgar_veredicto('A3-activo-de-otro-asesor-ya-es-cliente', v_res, v_esp, v_l, pg_temp.dni(3), array[v_c], v_h));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- B. NO CAMBIA. B1 sin coincidencia (persona nueva, sin puentes) · B2 cliente CON ficha activo de otro asesor (conversión real:
  --    P0409 conciliación) · B3 cliente CON ficha retirado (P0409) · B4 un lead VIVO no convertido de otro asesor con ese DNI (P0409)
  --    · B5 un convertido sin persona retirado con un PUENTE HISTÓRICO a OTRA persona (no es candidato: persona nueva, como hoy) ·
  --    B6 CE (sin absorción) · B7 un puente histórico sobre un lead NO convertido de la persona (sigue siendo «otro lead»: P0409).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l := pg_temp.lead_nuevo(v_vend2, 105, 'ENS210 LEAD B1');
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(5), 'ENS210 LEAD B1');
  perform pg_temp.reg('B1-sin-coincidencia-persona-nueva (como hoy)', pg_temp.juzgar_sin_cambio('B1-sin-coincidencia-persona-nueva (como hoy)', v_res, v_l, pg_temp.dni(5)));

  v_c := pg_temp.convertir_real(6, 'ENS210 CLIENTE B2 CON FICHA', v_vend1);
  v_l := pg_temp.lead_nuevo(v_vend2, 106, 'ENS210 LEAD B2');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(6), 'ENS210 LEAD B2');
  perform pg_temp.medida(format('B2 · preparar con el DNI de un cliente CON ficha activo de otro asesor → %s', v_res));
  perform pg_temp.reg('B2-cliente-con-ficha-activo-sigue-en-conciliacion (como hoy)', pg_temp.juzgar_conciliacion('B2-cliente-con-ficha-activo-sigue-en-conciliacion (como hoy)', v_res, v_h));

  -- B2b/B2c: dos estados HEREDADOS de «cliente con ficha» que la puerta real ya no produce (sembrados y declarados, como el lead enlazado
  --          del oráculo del 2.8): B2b un convertido con PUNTERO a su persona pero SIN puente · B2c un convertido con puente CANÓNICO
  --          pero SIN puntero. Ninguno es candidato (tienen ficha) y ninguno es «historia»: siguen en conciliación, como hoy.
  v_per := private.inversionista_resolver('DNI', pg_temp.dni(24), true, 'ensayo-bloque-2.10');
  v_c := pg_temp.lead_nuevo(v_vend1, 24, 'ENS210 CLIENTE B2B PUNTERO SIN PUENTE');
  set local session_replication_role = replica;
  update crm.leads set inversionista_id = v_per, dni = pg_temp.dni(24) where id = v_c;
  set local session_replication_role = origin;
  perform pg_temp.convertir_sembrado(v_c, false);
  if (select l.inversionista_id from crm.leads l where l.id = v_c) is distinct from v_per or exists (select 1 from crm.inversionista_leads il where il.lead_id = v_c) then
    raise exception 'ENSAYO ABORTADO: el convertido B2b no quedó con puntero y sin puente';
  end if;
  v_l := pg_temp.lead_nuevo(v_vend2, 124, 'ENS210 LEAD B2B');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(24), 'ENS210 LEAD B2B');
  perform pg_temp.medida(format('B2b · preparar con el DNI de un convertido activo con puntero y sin puente → %s', v_res));
  perform pg_temp.reg('B2b-convertido-con-puntero-sin-puente-sigue-en-conciliacion (como hoy)', pg_temp.juzgar_conciliacion('B2b-convertido-con-puntero-sin-puente-sigue-en-conciliacion (como hoy)', v_res, v_h));

  v_per := private.inversionista_resolver('DNI', pg_temp.dni(25), true, 'ensayo-bloque-2.10');
  v_c := pg_temp.lead_nuevo(v_vend1, 25, 'ENS210 CLIENTE B2C PUENTE CANONICO SIN PUNTERO');
  set local session_replication_role = replica;
  update crm.leads set dni = pg_temp.dni(25) where id = v_c;
  set local session_replication_role = origin;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_per, v_c, 'canonico');
  perform pg_temp.convertir_sembrado(v_c, false);
  if (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: el convertido B2c no quedó sin puntero';
  end if;
  v_l := pg_temp.lead_nuevo(v_vend2, 125, 'ENS210 LEAD B2C');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(25), 'ENS210 LEAD B2C');
  perform pg_temp.medida(format('B2c · preparar con el DNI de un convertido activo con puente canónico y sin puntero → %s', v_res));
  perform pg_temp.reg('B2c-convertido-con-puente-canonico-sin-puntero-sigue-en-conciliacion (como hoy)', pg_temp.juzgar_conciliacion('B2c-convertido-con-puente-canonico-sin-puntero-sigue-en-conciliacion (como hoy)', v_res, v_h));

  -- B2d (D-90, ronda 6): lo mismo que B2c pero RETIRADO ⇒ sigue en conciliación como hoy (un puente CANÓNICO no es historia aunque el lead
  --     esté retirado): con D-90 los activos ya no son historia, así que es este caso, y no B2c, el que prueba que la pieza exige el rol
  --     histórico (mutante M17).
  v_per := private.inversionista_resolver('DNI', pg_temp.dni(55), true, 'ensayo-bloque-2.10');
  v_c := pg_temp.lead_nuevo(v_vend1, 55, 'ENS210 CLIENTE B2D PUENTE CANONICO SIN PUNTERO RETIRADO');
  set local session_replication_role = replica;
  update crm.leads set dni = pg_temp.dni(55) where id = v_c;
  set local session_replication_role = origin;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_per, v_c, 'canonico');
  perform pg_temp.convertir_sembrado(v_c, true);
  if (select l.inversionista_id from crm.leads l where l.id = v_c) is not null then
    raise exception 'ENSAYO ABORTADO: el convertido B2d no quedó sin puntero';
  end if;
  v_l := pg_temp.lead_nuevo(v_vend2, 155, 'ENS210 LEAD B2D');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(55), 'ENS210 LEAD B2D');
  perform pg_temp.medida(format('B2d · preparar con el DNI de un convertido RETIRADO con puente canónico y sin puntero → %s', v_res));
  perform pg_temp.reg('B2d-convertido-retirado-con-puente-canonico-sigue-en-conciliacion (como hoy)', pg_temp.juzgar_conciliacion('B2d-convertido-retirado-con-puente-canonico-sigue-en-conciliacion (como hoy)', v_res, v_h));

  v_c := pg_temp.convertir_real(7, 'ENS210 CLIENTE B3 CON FICHA RETIRADO', v_vend1);
  perform pg_temp.retirar_sembrado(v_c);
  v_l := pg_temp.lead_nuevo(v_vend2, 107, 'ENS210 LEAD B3');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(7), 'ENS210 LEAD B3');
  perform pg_temp.medida(format('B3 · preparar con el DNI de un cliente CON ficha RETIRADO → %s', v_res));
  perform pg_temp.reg('B3-cliente-con-ficha-retirado-sigue-en-conciliacion (como hoy)', pg_temp.juzgar_conciliacion('B3-cliente-con-ficha-retirado-sigue-en-conciliacion (como hoy)', v_res, v_h));

  v_c := pg_temp.lead_nuevo(v_vend1, 8, 'ENS210 LEAD VIVO B4', pg_temp.dni(8));
  v_l := pg_temp.lead_nuevo(v_vend2, 108, 'ENS210 LEAD B4');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(8), 'ENS210 LEAD B4');
  perform pg_temp.reg('B4-lead-vivo-no-convertido-con-ese-dni-sigue-en-conciliacion (como hoy)', pg_temp.juzgar_conciliacion('B4-lead-vivo-no-convertido-con-ese-dni-sigue-en-conciliacion (como hoy)', v_res, v_h));

  v_c := pg_temp.cliente_sin_persona(9, 'ENS210 CLIENTE B5 CON PUENTE AJENO', v_vend1, true);
  insert into crm.inversionistas (estado) values ('activo') returning id into v_p9;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_p9, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 109, 'ENS210 LEAD B5');
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(9), 'ENS210 LEAD B5');
  perform pg_temp.medida(format('B5 · preparar con el DNI de un convertido sin persona pero con puente histórico a OTRA persona → %s', v_res));
  v_txt := pg_temp.juzgar_sin_cambio('B5-convertido-con-puente-ajeno-no-es-candidato (como hoy)', v_res, v_l, pg_temp.dni(9));
  if v_txt = '' and (select count(*) from crm.inversionista_leads il where il.lead_id = v_c) <> 1 then
    v_txt := E'FALLO B5-convertido-con-puente-ajeno-no-es-candidato (como hoy): el convertido con puente ajeno recibió otro puente\n';
  end if;
  perform pg_temp.reg('B5-convertido-con-puente-ajeno-no-es-candidato (como hoy)', v_txt);

  v_l := pg_temp.lead_nuevo(v_vend2, 110, 'ENS210 LEAD B6');
  v_res := pg_temp.preparar(v_vend2, v_l, 'CE', '000529010', 'ENS210 LEAD B6');
  perform pg_temp.reg('B6-carnet-de-extranjeria-sin-absorcion (como hoy)',
    case when v_res like 'ok|%' and not exists (select 1 from crm.inversionista_leads il where il.inversionista_id = (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid and il.rol = 'historico')
         then '' else format(E'FALLO B6-carnet-de-extranjeria-sin-absorcion (como hoy): se esperaba ok sin puentes y llegó %s\n', v_res) end);

  -- B7: la persona P (DNI 11) tiene un lead NO convertido con puente histórico (estado sembrado): para la conversión de otro lead con ese
  --     DNI sigue siendo «otro lead» (la pieza de historia solo reconoce convertidos sin puntero).
  v_per := private.inversionista_resolver('DNI', pg_temp.dni(11), true, 'ensayo-bloque-2.10');
  v_c := pg_temp.lead_nuevo(v_vend1, 11, 'ENS210 LEAD B7 CONTACTADO');
  set local session_replication_role = replica;
  update crm.leads set inversionista_id = null where id = v_c;
  set local session_replication_role = origin;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_per, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 111, 'ENS210 LEAD B7');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(11), 'ENS210 LEAD B7');
  perform pg_temp.reg('B7-puente-historico-de-un-lead-no-convertido-sigue-siendo-otro-lead (como hoy)', pg_temp.juzgar_conciliacion('B7-puente-historico-de-un-lead-no-convertido-sigue-siendo-otro-lead (como hoy)', v_res, v_h));

  -- B7b (D-90, ronda 6): lo mismo que B7 pero el lead NO convertido está RETIRADO ⇒ sigue siendo «otro lead» (la historia exige etapa
  --     convertido): es el caso que prueba esa condición con D-90 (mutante M18).
  v_per := private.inversionista_resolver('DNI', pg_temp.dni(56), true, 'ensayo-bloque-2.10');
  v_c := pg_temp.lead_nuevo(v_vend1, 56, 'ENS210 LEAD B7B RETIRADO');
  set local session_replication_role = replica;
  update crm.leads set inversionista_id = null, activo = false where id = v_c;
  set local session_replication_role = origin;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values (v_per, v_c, 'historico');
  v_l := pg_temp.lead_nuevo(v_vend2, 156, 'ENS210 LEAD B7B');
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(56), 'ENS210 LEAD B7B');
  perform pg_temp.medida(format('B7b · un lead NO convertido y RETIRADO con puente histórico a la persona → %s', v_res));
  perform pg_temp.reg('B7b-puente-historico-de-un-lead-no-convertido-retirado-sigue-siendo-otro-lead (como hoy)', pg_temp.juzgar_conciliacion('B7b-puente-historico-de-un-lead-no-convertido-retirado-sigue-siendo-otro-lead (como hoy)', v_res, v_h));
  -- U8 (ronda 7): el contrato de la pieza para B7b. Desde D-91 la PUERTA detiene B7b también por su puente histórico de antes, así que la
  --     etapa «convertido» de la pieza ya solo la prueba su contrato (la usan los núcleos: D-90): un lead NO convertido y retirado con
  --     puente histórico NO es historia (mutante M18).
  if v_historia is not null then
    execute 'select private.lead_historia_de_persona($1, $2)' into v_b using v_c, v_per;
    perform pg_temp.reg('U8-la-historia-exige-la-etapa-convertido (D-90)',
      case when v_b is false then '' else E'FALLO U8-la-historia-exige-la-etapa-convertido (D-90): la pieza dice sí a un lead NO convertido (retirado, con puente histórico)\n' end);
  else
    perform pg_temp.reg('U8-la-historia-exige-la-etapa-convertido (D-90)', E'FALLO U8-la-historia-exige-la-etapa-convertido (D-90): no existe private.lead_historia_de_persona\n');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A9. VARIOS CANDIDATOS. A9 un retirado de VEND1 y un ACTIVO de VEND3 ⇒ el activo de otro manda: «ya es cliente de VEND3» (nada se
  --     absorbe) · A9b dos activos, el del MISMO asesor más reciente y otro de VEND3 más antiguo ⇒ «ya es cliente de VEND3» · A10 dos
  --     retirados (VEND1 y VEND3) ⇒ los dos absorbidos.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado_convertido(12, 'ENS210 CLIENTE A9 RETIRADO VEND1', false, v_vend1, null, false, clock_timestamp() - interval '2 days');
  v_c2 := pg_temp.sembrado_convertido(12, 'ENS210 CLIENTE A9 ACTIVO VEND3', true, v_vend3, null, false, clock_timestamp() - interval '9 days');
  v_l := pg_temp.lead_nuevo(v_vend2, 112, 'ENS210 LEAD A9');
  v_esp := pg_temp.referencia_alta(v_vend2, 912, pg_temp.dni(12));
  perform pg_temp.fotografiar(array[v_c, v_c2, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(12), 'ENS210 LEAD A9');
  perform pg_temp.medida(format('A9 · dos candidatos (retirado VEND1, activo VEND3) → %s (referencia %s)', v_res, v_esp));
  perform pg_temp.reg('A9-un-retirado-y-un-activo-de-otro-manda-el-activo', pg_temp.juzgar_veredicto('A9-un-retirado-y-un-activo-de-otro-manda-el-activo', v_res, v_esp, v_l, pg_temp.dni(12), array[v_c, v_c2], v_h));

  v_c := pg_temp.sembrado_convertido(13, 'ENS210 CLIENTE A9B ACTIVO VEND2', true, v_vend2, null, false, clock_timestamp() - interval '2 days');
  v_c2 := pg_temp.sembrado_convertido(13, 'ENS210 CLIENTE A9B ACTIVO VEND3', true, v_vend3, null, false, clock_timestamp() - interval '9 days');
  v_l := pg_temp.lead_nuevo(v_vend2, 113, 'ENS210 LEAD A9B');
  v_esp := jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'PASO08 VEND3');
  perform pg_temp.fotografiar(array[v_c, v_c2, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(13), 'ENS210 LEAD A9B');
  perform pg_temp.medida(format('A9b · dos activos (VEND2 más reciente, VEND3 más antiguo) → %s', v_res));
  perform pg_temp.reg('A9b-dos-activos-el-de-otro-asesor-manda-aunque-sea-mas-antiguo', pg_temp.juzgar_veredicto('A9b-dos-activos-el-de-otro-asesor-manda-aunque-sea-mas-antiguo', v_res, v_esp, v_l, pg_temp.dni(13), array[v_c, v_c2], v_h));

  v_c := pg_temp.cliente_sin_persona(14, 'ENS210 CLIENTE A10 RETIRADO VEND1', v_vend1, true);
  v_c2 := pg_temp.sembrado_convertido(14, 'ENS210 CLIENTE A10 RETIRADO VEND3', false, v_vend3);
  v_l := pg_temp.lead_nuevo(v_vend2, 114, 'ENS210 LEAD A10');
  perform pg_temp.fotografiar(array[v_c, v_c2]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(14), 'ENS210 LEAD A10');
  perform pg_temp.reg('A10-dos-retirados-los-dos-absorbidos', pg_temp.juzgar_absorcion('A10-dos-retirados-los-dos-absorbidos', v_res, v_l, pg_temp.dni(14), array[v_c, v_c2], v_vend2, v_vend2));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A11/A12. QUIÉN CONVIERTE. A11 el SUPERVISOR (SUP1) convierte el lead de VEND2 con un antiguo ACTIVO de VEND2 ⇒ mismo asesor
  --          (el analista del lead), absorbido con la nota (de SUP1), responsable VEND2, y la conversión sigue · A12 GERENCIA convierte
  --          el lead de VEND2 con un antiguo retirado de VEND1 ⇒ absorbido, responsable VEND2.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(15, 'ENS210 CLIENTE A11 ACTIVO VEND2', v_vend2, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 115, 'ENS210 LEAD A11');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_sup1, v_l, 'DNI', pg_temp.dni(15), 'ENS210 LEAD A11');
  perform pg_temp.medida(format('A11 · el supervisor convierte el lead de su analista con un antiguo activo del mismo analista → %s', v_res));
  v_txt := pg_temp.juzgar_absorcion('A11-el-supervisor-convierte-mismo-analista-absorbe', v_res, v_l, pg_temp.dni(15), array[v_c], v_sup1, v_vend2);
  perform pg_temp.reg('A11-el-supervisor-convierte-mismo-analista-absorbe', v_txt);
  if v_txt = '' then
    perform pg_temp.reg('A11b-la-conversion-del-supervisor-sigue-hasta-confirmar', pg_temp.flujo_completo('A11b-la-conversion-del-supervisor-sigue-hasta-confirmar', v_sup1, v_l, (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid, 'ENS210 LEAD A11'));
  else
    perform pg_temp.reg('A11b-la-conversion-del-supervisor-sigue-hasta-confirmar', E'FALLO A11b-la-conversion-del-supervisor-sigue-hasta-confirmar: no se midió (A11 falló)\n');
  end if;

  v_c := pg_temp.cliente_sin_persona(16, 'ENS210 CLIENTE A12 RETIRADO VEND1', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 116, 'ENS210 LEAD A12');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_ger, v_l, 'DNI', pg_temp.dni(16), 'ENS210 LEAD A12');
  perform pg_temp.reg('A12-gerencia-convierte-absorbe-responsable-el-analista', pg_temp.juzgar_absorcion('A12-gerencia-convierte-absorbe-responsable-el-analista', v_res, v_l, pg_temp.dni(16), array[v_c], v_ger, v_vend2));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A13. REINTENTO: preparar dos veces (la respuesta se perdió) ⇒ la misma persona, UN puente, UNA operación.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(17, 'ENS210 CLIENTE A13 RETIRADO', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 117, 'ENS210 LEAD A13');
  perform pg_temp.fotografiar(array[v_c]);
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(17), 'ENS210 LEAD A13');
  perform pg_temp.medida(format('A13 · entre la 1.ª y la 2.ª: el antiguo con puente %s a la persona; su operación de enlace lleva lead_conversion = este lead: %s; el lead YA lleva el DNI: %s (ronda 8: D-91 solo se evalúa si la preparación ESCRIBE el DNI, así que el reintento no llega a esa comprobación; la exención por esa operación se conserva y la inspecciona C1d)',
    coalesce((select il.rol from crm.inversionista_leads il where il.lead_id = v_c), 'ninguno'),
    exists (select 1 from crm.inversionista_operaciones o where o.lead_id = v_c and o.tipo = 'enlace' and o.detalle ->> 'lead_conversion' = v_l::text),
    (select l.dni is not distinct from pg_temp.dni(17) from crm.leads l where l.id = v_l)));
  v_res2 := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(17), 'ENS210 LEAD A13');
  perform pg_temp.medida(format('A13 · reintento: 1.ª %s · 2.ª %s', v_res, v_res2));
  v_txt := pg_temp.juzgar_absorcion('A13-el-reintento-no-duplica-puente-ni-operacion', v_res2, v_l, pg_temp.dni(17), array[v_c], v_vend2, v_vend2);
  if v_txt = '' and (v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'inversionista_id') is distinct from (substr(v_res2, 4)::jsonb ->> 'inversionista_id')) then
    v_txt := E'FALLO A13-el-reintento-no-duplica-puente-ni-operacion: el reintento devolvió otra persona\n';
  end if;
  perform pg_temp.reg('A13-el-reintento-no-duplica-puente-ni-operacion', v_txt);

  -- A1t (D-91, ronda 7): OTRO lead de una persona cuyos antiguos ya absorbió el 2.10 ⇒ conciliación, como hoy. VEND2 convierte L1 con el
  --     DNI de un retirado sin ficha (lo absorbe: puente histórico con la operación de enlace de L1) y después prepara OTRO lead suyo, L2,
  --     con ese DNI ⇒ el P0409 de conciliación de hoy, nada escrito: L1 (con puntero) es otro lead, y el puente del antiguo lo puso la
  --     conversión de L1, no la de L2 (para D-91 es «de antes»).
  v_c := pg_temp.cliente_sin_persona(57, 'ENS210 CLIENTE A1T RETIRADO', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 157, 'ENS210 LEAD A1T PRIMERO');
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(57), 'ENS210 LEAD A1T PRIMERO');
  v_per := case when v_res like 'ok|%' then (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid end;
  if v_per is null
     or not exists (select 1 from crm.inversionista_leads il where il.lead_id = v_c and il.inversionista_id = v_per and il.rol = 'historico')
     or not exists (select 1 from crm.inversionista_operaciones o where o.lead_id = v_c and o.tipo = 'enlace' and o.detalle ->> 'lead_conversion' = v_l::text) then
    perform pg_temp.reg('A1t-otro-lead-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy)',
      format(E'FALLO A1t-otro-lead-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy): no se midió (la 1.ª conversión no absorbió al antiguo: %s)\n', v_res));
  else
    v_y := pg_temp.lead_nuevo(v_vend2, 161, 'ENS210 LEAD A1T SEGUNDO');
    perform pg_temp.fotografiar(array[v_c, v_l, v_y]);
    v_h := pg_temp.huella_escritura();
    v_res2 := pg_temp.preparar(v_vend2, v_y, 'DNI', pg_temp.dni(57), 'ENS210 LEAD A1T SEGUNDO');
    perform pg_temp.medida(format('A1t · OTRO lead de la persona cuyo antiguo absorbió la conversión de L1 → %s', v_res2));
    perform pg_temp.reg('A1t-otro-lead-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy)',
      pg_temp.juzgar_d91('A1t-otro-lead-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy)', v_res2, v_h, array[v_c, v_l, v_y], pg_temp.dni(57)));
  end if;

  -- A1tb (ronda 8): lo mismo que A1t pero el otro lead YA lleva el DNI (el UPDATE de la puerta no lo cambia ⇒ la comprobación de D-91 no se
  --      evalúa). L1 convierte (real) y absorbe a un retirado sin ficha, y CONFIRMA (queda convertido: ya no ocupa el índice único
  --      `uq_leads_dni_vivo`, que prohíbe dos leads operativos con el mismo DNI; con L1 sin confirmar el estado no se puede sembrar: medido);
  --      L2, otro lead vivo de vend2, lleva ya ese DNI (sembrado y declarado, disparadores apagados) ⇒ el P0409 de conciliación de hoy, nada
  --      escrito: L1 (canónico, con puntero) es otro lead de la persona y lo decide la conciliación de siempre, no D-91. Medido en ROJO, en
  --      la ronda 6 y en la ronda 7: P0409 en las tres (es un control: no cambia con la ronda 8).
  v_c := pg_temp.cliente_sin_persona(61, 'ENS210 CLIENTE A1TB RETIRADO', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 163, 'ENS210 LEAD A1TB PRIMERO');
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(61), 'ENS210 LEAD A1TB PRIMERO');
  v_per := case when v_res like 'ok|%' then (substr(v_res, 4)::jsonb ->> 'inversionista_id')::uuid end;
  v_txt := case when v_per is null then format('la 1.ª conversión no se preparó: %s', v_res)
                else pg_temp.flujo_completo('A1tb-montaje', v_vend2, v_l, v_per, 'ENS210 LEAD A1TB PRIMERO') end;
  if v_per is null or v_txt <> ''
     or not exists (select 1 from crm.inversionista_leads il where il.lead_id = v_c and il.inversionista_id = v_per and il.rol = 'historico')
     or not exists (select 1 from crm.inversionista_operaciones o where o.lead_id = v_c and o.tipo = 'enlace' and o.detalle ->> 'lead_conversion' = v_l::text) then
    perform pg_temp.reg('A1tb-otro-lead-que-ya-lleva-el-dni-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy)',
      format(E'FALLO A1tb-otro-lead-que-ya-lleva-el-dni-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy): no se midió (la 1.ª conversión no absorbió y confirmó: %s)\n', coalesce(nullif(v_txt, ''), v_res)));
  else
    v_y := pg_temp.lead_nuevo(v_vend2, 166, 'ENS210 LEAD A1TB SEGUNDO');
    set local session_replication_role = replica;
    update crm.leads set dni = pg_temp.dni(61) where id = v_y;
    set local session_replication_role = origin;
    perform pg_temp.fotografiar(array[v_c, v_l, v_y]);
    v_h := pg_temp.huella_escritura();
    v_res2 := pg_temp.preparar(v_vend2, v_y, 'DNI', pg_temp.dni(61), 'ENS210 LEAD A1TB SEGUNDO');
    perform pg_temp.medida(format('A1tb · OTRO lead de la persona cuyo antiguo absorbió y confirmó L1, y que YA lleva el DNI → %s', v_res2));
    perform pg_temp.reg('A1tb-otro-lead-que-ya-lleva-el-dni-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy)',
      pg_temp.juzgar_d91('A1tb-otro-lead-que-ya-lleva-el-dni-de-una-persona-ya-absorbida-requiere-conciliacion (D-91, como hoy)', v_res2, v_h, array[v_c, v_l, v_y], pg_temp.dni(61)));
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A15. EL CLIENTE ANTIGUO RETIRADO TENÍA «No insistir» ⇒ COMO HOY: el verificador que corre al escribir el DNI en el lead que se
  --      convierte lo rechaza (P0481 con {"estado": "no_contactar"}) y el rechazo deshace la absorción (medido en ROJO: hoy ya responde
  --      así). Nada se escribe: ni puente, ni operación, ni persona. El veto manda (no hace falta decisión nueva).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado_convertido(18, 'ENS210 CLIENTE A15 RETIRADO VETADO', false, v_vend1, null, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 118, 'ENS210 LEAD A15');
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(18), 'ENS210 LEAD A15');
  perform pg_temp.medida(format('A15 · antiguo retirado con No insistir → %s', v_res));
  perform pg_temp.reg('A15-antiguo-retirado-con-no-insistir-el-veto-manda (como hoy)',
    pg_temp.juzgar_veredicto('A15-antiguo-retirado-con-no-insistir-el-veto-manda (como hoy)', v_res, jsonb_build_object('estado', 'no_contactar'), v_l, pg_temp.dni(18), array[v_c], v_h));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A16/A17. EL NOMBRE DEL VEREDICTO ES EL DEL ALTA: A16 el antiguo activo es de un asesor de BAJA ⇒ «ya es cliente de PASO08 BAJA» ·
  --          A17 el antiguo activo está en una BANDEJA (sin vendedor, con supervisor SUP2) ⇒ «ya es cliente de PASO08 SUP2».
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado_convertido(19, 'ENS210 CLIENTE A16 ACTIVO BAJA', true, v_baja);
  v_l := pg_temp.lead_nuevo(v_vend2, 119, 'ENS210 LEAD A16');
  v_esp := pg_temp.referencia_alta(v_vend2, 919, pg_temp.dni(19));
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(19), 'ENS210 LEAD A16');
  perform pg_temp.reg('A16-activo-de-un-asesor-de-baja-nombra-al-de-baja-como-el-alta', pg_temp.juzgar_veredicto('A16-activo-de-un-asesor-de-baja-nombra-al-de-baja-como-el-alta', v_res, v_esp, v_l, pg_temp.dni(19), array[v_c], v_h));

  v_c := pg_temp.sembrado_convertido(20, 'ENS210 CLIENTE A17 ACTIVO BANDEJA', true, null, v_sup2);
  v_l := pg_temp.lead_nuevo(v_vend2, 120, 'ENS210 LEAD A17');
  v_esp := pg_temp.referencia_alta(v_vend2, 920, pg_temp.dni(20));
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(20), 'ENS210 LEAD A17');
  perform pg_temp.medida(format('A17 · antiguo activo en la bandeja de SUP2 → %s (referencia %s)', v_res, v_esp));
  perform pg_temp.reg('A17-activo-en-una-bandeja-nombra-al-supervisor-como-el-alta', pg_temp.juzgar_veredicto('A17-activo-en-una-bandeja-nombra-al-supervisor-como-el-alta', v_res, v_esp, v_l, pg_temp.dni(20), array[v_c], v_h));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A18/A19. LO QUE HOY YA RECHAZA VA ANTES: A18 el lead que se convierte tiene «No insistir» y hay un antiguo activo de otro ⇒ P0429
  --          «El lead tiene No insistir» (no el veredicto) · A19 el lead que se convierte está DESCARTADO ⇒ P0409 «ya está cerrado».
  --          Nada se escribe en ninguno.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(21, 'ENS210 CLIENTE A18 ACTIVO OTRO', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 121, 'ENS210 LEAD A18 VETADO');
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_l;
  set local session_replication_role = origin;
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(21), 'ENS210 LEAD A18 VETADO');
  e := pg_temp.error_de(v_res);
  perform pg_temp.reg('A18-el-no-insistir-del-lead-que-se-convierte-manda-sobre-el-veredicto',
    case when e.estado = 'P0429' and position('No insistir' in coalesce(e.mensaje, '')) > 0 and pg_temp.huella_escritura() = v_h
              and pg_temp.ficha(v_c) = (select f.foto from ens_fotos f where f.id = v_c) then ''
         else format(E'FALLO A18-el-no-insistir-del-lead-que-se-convierte-manda-sobre-el-veredicto: se esperaba P0429 «El lead tiene No insistir» sin escribir y llegó %s\n', v_res) end);

  v_c := pg_temp.cliente_sin_persona(22, 'ENS210 CLIENTE A19 ACTIVO OTRO', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 122, 'ENS210 LEAD A19 DESCARTADO');
  set local session_replication_role = replica;
  update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes', descartado_en = clock_timestamp(), descartado_por = v_vend2 where id = v_l;
  set local session_replication_role = origin;
  perform pg_temp.fotografiar(array[v_c, v_l]);
  v_h := pg_temp.huella_escritura();
  v_res := pg_temp.preparar(v_vend2, v_l, 'DNI', pg_temp.dni(22), 'ENS210 LEAD A19 DESCARTADO');
  e := pg_temp.error_de(v_res);
  perform pg_temp.reg('A19-el-lead-cerrado-manda-sobre-el-veredicto',
    case when e.estado = 'P0409' and position('ya está cerrado' in coalesce(e.mensaje, '')) > 0 and pg_temp.huella_escritura() = v_h then ''
         else format(E'FALLO A19-el-lead-cerrado-manda-sobre-el-veredicto: se esperaba P0409 «El lead ya está cerrado» sin escribir y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- U2. CONTRATO DE LA PIEZA DE ABSORCIÓN: sin candidatos devuelve NULL (y no escribe); con un argumento nulo, NULL.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if v_absorber is not null then
    v_h := pg_temp.huella_escritura();
    execute 'select private.conversion_absorber_cliente_antiguo($1, $2, $3, $4, $4) is null and private.conversion_absorber_cliente_antiguo($1, $2, null, $4, $4) is null'
      into v_b using v_l, v_p9, pg_temp.dni(99), v_vend2;
    perform pg_temp.reg('U2-contrato-de-la-pieza-de-absorcion-sin-candidatos-null',
      case when v_b and pg_temp.huella_escritura() = v_h then '' else E'FALLO U2-contrato-de-la-pieza-de-absorcion-sin-candidatos-null: la pieza no devuelve NULL sin candidatos (o escribió)\n' end);
  else
    perform pg_temp.reg('U2-contrato-de-la-pieza-de-absorcion-sin-candidatos-null', E'FALLO U2-contrato-de-la-pieza-de-absorcion-sin-candidatos-null: no existe private.conversion_absorber_cliente_antiguo\n');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- U3. CONTRATO DE LA CASA (lo que sostiene «el asesor de origen del cierre no cambia», D-83): bajo la válvula privilegiada, un UPDATE
  --     del vendedor_id de un cierre externo lo restaura `private.trg_cierres_externos_inmutables` (fijado por el preflight); sin la
  --     válvula, lo rechaza. Se mide sobre el cierre del antiguo de A19 (de VEND1, sin persona).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_m := '{}';
  select ce.id into v_q from crm.cierres_externos ce where ce.lead_id = v_c and ce.es_cierre_inicial;
  if v_q is null then
    v_m := array_append(v_m, 'no hay cierre sobre el que medir');
  else
    begin
      perform set_config('crm.op_privilegiada', 'on', true);
      update crm.cierres_externos set vendedor_id = v_vend3 where id = v_q;
      perform set_config('crm.op_privilegiada', 'off', true);
      if (select ce.vendedor_id from crm.cierres_externos ce where ce.id = v_q) is distinct from v_vend1 then
        v_m := array_append(v_m, 'bajo la válvula, el asesor de origen del cierre cambió (el disparador de inmutables no lo restauró)');
      end if;
    exception when others then
      perform set_config('crm.op_privilegiada', 'off', true);
      v_m := array_append(v_m, format('bajo la válvula, el UPDATE falló (%s %s)', sqlstate, sqlerrm));
    end;
    begin
      update crm.cierres_externos set vendedor_id = v_vend3 where id = v_q;
      v_m := array_append(v_m, 'sin la válvula, el UPDATE del asesor de origen entró');
    exception when others then
      if sqlstate <> 'P0409' then
        v_m := array_append(v_m, format('sin la válvula, el UPDATE falló con otro error (%s %s)', sqlstate, sqlerrm));
      end if;
    end;
  end if;
  perform pg_temp.reg('U3-contrato-de-la-casa-el-asesor-de-origen-del-cierre-es-inmutable (como hoy)',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO U3-contrato-de-la-casa-el-asesor-de-origen-del-cierre-es-inmutable (como hoy): %s\n', array_to_string(v_m, '; ')) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- U4. CONTRATO DE LA CASA (por qué D-85 no distingue «sin documento», como no lo distingue la puerta de enlace de Gerencia): un cierre
  --     externo SIN documento no existe —`documento` y `documento_tipo` son NOT NULL y el documento tiene formato (CHECK)—, ni con los
  --     disparadores apagados.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_m := '{}';
  v_c := pg_temp.cliente_sin_persona(37, 'ENS210 CLIENTE U4 SIN CIERRE', v_vend1, true, false);
  for i in 1..3 loop
    begin
      set local session_replication_role = replica;
      insert into crm.cierres_externos (lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion,
                                        vendedor_id, creado_por, creado_en, es_cierre_inicial)
      values (v_c, 'prodelco', 1000, 'PEN', case when i = 3 then null else 'DNI' end, case when i = 1 then null when i = 2 then '' else pg_temp.dni(37) end,
              'ENS210 CLIENTE U4 SIN CIERRE', 'ENS210-U4-' || i, v_vend1, v_vend1, clock_timestamp(), true);
      set local session_replication_role = origin;
      v_m := array_append(v_m, format('el cierre %s se guardó', case i when 1 then 'con documento NULL' when 2 then 'con documento vacío' else 'sin tipo de documento' end));
    exception when others then
      set local session_replication_role = origin;
      if sqlstate not in ('23502', '23514') then
        v_m := array_append(v_m, format('el cierre %s falló con otro error (%s %s)', i, sqlstate, sqlerrm));
      end if;
    end;
  end loop;
  perform pg_temp.reg('U4-contrato-de-la-casa-un-cierre-sin-documento-no-existe (como hoy)',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO U4-contrato-de-la-casa-un-cierre-sin-documento-no-existe (como hoy): %s\n', array_to_string(v_m, '; ')) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- U5. CONTRATO DE LA PIEZA DE ABSORCIÓN: repone la válvula `crm.op_privilegiada` como la encontró (test gap del auditor r2: la puerta
  --     la vuelve a poner tras su UPDATE y taparía el olvido). Se llama a la pieza a pelo, con la válvula en off y en on, sobre un antiguo
  --     que absorbe; todo dentro de un bloque que se deshace al final.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_m := '{}';
  begin
    v_c := pg_temp.cliente_sin_persona(48, 'ENS210 CLIENTE U5 VALVULA', v_vend1, true);
    v_q := private.inversionista_resolver('DNI', pg_temp.dni(48), true, 'ensayo-bloque-2.10');
    if v_absorber is null then
      v_m := array_append(v_m, 'no existe la pieza de absorción');
    else
      perform set_config('crm.op_privilegiada', 'off', true);
      execute 'select private.conversion_absorber_cliente_antiguo($1, $2, $3, $4, $4)' into v_r using gen_random_uuid(), v_q, pg_temp.dni(48), v_vend2;
      if v_r is null or not (v_r ? 'candidatos') then
        v_m := array_append(v_m, format('la pieza no absorbió (%s): no se midió la válvula', v_r));
      end if;
      if current_setting('crm.op_privilegiada', true) is distinct from 'off' then
        v_m := array_append(v_m, format('con la válvula en off antes, quedó en %s', current_setting('crm.op_privilegiada', true)));
      end if;
      perform set_config('crm.op_privilegiada', 'on', true);
      execute 'select private.conversion_absorber_cliente_antiguo($1, $2, $3, $4, $4)' into v_r using gen_random_uuid(), v_q, pg_temp.dni(48), v_vend2;
      if current_setting('crm.op_privilegiada', true) is distinct from 'on' then
        v_m := array_append(v_m, format('con la válvula en on antes, quedó en %s', current_setting('crm.op_privilegiada', true)));
      end if;
    end if;
    raise exception 'U5_DESHACER';
  exception when others then
    if sqlerrm <> 'U5_DESHACER' then
      v_m := array_append(v_m, format('error inesperado (%s %s)', sqlstate, sqlerrm));
    end if;
  end;
  perform pg_temp.reg('U5-la-pieza-de-absorcion-repone-la-valvula-como-la-encontro',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO U5-la-pieza-de-absorcion-repone-la-valvula-como-la-encontro: %s\n', array_to_string(v_m, '; ')) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- U6. CONTRATO DE LA PIEZA DE ENLACE (D-87): si al enlazar el perfil a la ficha otra persona ya lo tiene (una carrera: el índice único
  --     inversionistas_perfil_uidx da 23505), responde el 40001 de la casa «La cuenta del Portal del cliente antiguo cambió mientras se
  --     enlazaba; vuelve a intentarlo». Se llama a la pieza a pelo dentro de un bloque que se deshace al final.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_m := '{}';
  begin
    v_c := pg_temp.cliente_sin_persona(49, 'ENS210 CLIENTE U6 PERFIL EN CARRERA', v_vend1, true);
    v_q := private.inversionista_resolver('DNI', pg_temp.dni(49), true, 'ensayo-bloque-2.10');
    v_x := pg_temp.perfil_cliente(49, 'DNI', pg_temp.dni(49), false);
    insert into crm.inversionistas (estado, perfil_id) values ('activo', v_x);
    if v_enlazar is null then
      v_m := array_append(v_m, 'no existe la pieza de enlace');
    else
      begin
        execute 'select private.conversion_enlazar_cliente_antiguo($1, $2, $3)'
          using v_q, jsonb_build_array(jsonb_build_object('id', v_c, 'activo', false, 'vendedor_id', v_vend1, 'perfil_a_enlazar', v_x)), v_vend2;
        v_m := array_append(v_m, 'la pieza siguió sin error aunque otra persona ya tenía el perfil (no respondió el 40001 de la casa)');
      exception when others then
        if sqlstate <> '40001' or position('La cuenta del Portal del cliente antiguo cambió mientras se enlazaba' in sqlerrm) = 0 then
          v_m := array_append(v_m, format('respondió %s «%s» (se esperaba el 40001 de la casa)', sqlstate, sqlerrm));
        end if;
      end;
    end if;
    raise exception 'U6_DESHACER';
  exception when others then
    if sqlerrm <> 'U6_DESHACER' then
      v_m := array_append(v_m, format('error inesperado (%s %s)', sqlstate, sqlerrm));
    end if;
  end;
  perform pg_temp.reg('U6-la-carrera-por-el-perfil-da-el-40001-de-la-casa (D-87)',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO U6-la-carrera-por-el-perfil-da-el-40001-de-la-casa (D-87): %s\n', array_to_string(v_m, '; ')) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C. CATÁLOGO. C1 la puerta llama a la pieza de absorción EXACTAMENTE una vez, DESPUÉS de tomar la fila del lead (el último
  --    `for update nowait`) y ANTES de la conciliación, con las dos comprobaciones de conciliación pasando por la pieza de historia, y
  --    conserva su ficha con el comentario del 2.10 · C1b la pieza de absorción toma los candidatos FOR UPDATE NOWAIT, con su ficha ·
  --    C2 los dos núcleos llaman a la pieza de historia una vez, con su ficha y su comentario · C3 nadie más usa las piezas · C4 lo que
  --    no se toca, con su definición de hoy.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_m := '{}';
  select p.prosrc into v_src from pg_proc p where p.oid = v_puerta;
  if (length(v_src) - length(replace(v_src, 'private.conversion_absorber_cliente_antiguo(', ''))) / length('private.conversion_absorber_cliente_antiguo(') <> 1 then
    v_m := array_append(v_m, 'no llama a la pieza de absorción exactamente una vez');
  else
    if strpos(v_src, 'private.conversion_absorber_cliente_antiguo(') < pg_temp.ultima(v_src, 'for update nowait') then
      v_m := array_append(v_m, 'llama a la pieza ANTES de tomar la fila del lead FOR UPDATE NOWAIT');
    end if;
    if strpos(v_src, 'private.conversion_absorber_cliente_antiguo(') > strpos(v_src, 'Esta persona ya tiene otra identidad o lead') then
      v_m := array_append(v_m, 'llama a la pieza DESPUÉS de la conciliación');
    end if;
    if strpos(v_src, 'private.conversion_absorber_cliente_antiguo(') < strpos(v_src, 'Asigna el lead a un analista activo') then
      v_m := array_append(v_m, 'llama a la pieza ANTES de lo que hoy decide (analista activo)');
    end if;
  end if;
  if (length(v_src) - length(replace(v_src, 'private.lead_historia_de_persona(', ''))) / length('private.lead_historia_de_persona(') <> 3 then
    v_m := array_append(v_m, 'las dos comprobaciones de conciliación y la de D-94 no pasan por la pieza de historia (debe aparecer tres veces)');
  end if;
  if (length(v_src) - length(replace(v_src, 'private.conversion_enlazar_cliente_antiguo(', ''))) / length('private.conversion_enlazar_cliente_antiguo(') <> 1 then
    v_m := array_append(v_m, 'no llama a la pieza de enlace exactamente una vez');
  elsif strpos(v_src, 'private.conversion_enlazar_cliente_antiguo(') < strpos(v_src, 'update crm.leads set inversionista_id=v_persona') then
    v_m := array_append(v_m, 'llama a la pieza de enlace ANTES del UPDATE que escribe la persona y el DNI (el verificador contaría el puente)');
  end if;
  if not pg_temp.ficha_ok(v_puerta, true, 'v', array['search_path=""', 'lock_timeout=5s'], 'authenticated:EXECUTE:false,postgres:EXECUTE:false') then
    v_m := array_append(v_m, 'su ficha no es la de hoy (dueño postgres, security definer, volátil, su SET, su ACL)');
  end if;
  if strpos(coalesce(obj_description(v_puerta, 'pg_proc'), ''), 'Bloque 2.10') = 0 then
    v_m := array_append(v_m, 'su comentario no dice lo que hace el 2.10');
  end if;
  perform pg_temp.reg('C1-la-puerta-llama-a-las-piezas-en-su-sitio-con-su-ficha',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO C1-la-puerta-llama-a-las-piezas-en-su-sitio-con-su-ficha: crm.preparar_persona_lead_inversion_fn %s\n', array_to_string(v_m, '; ')) end);

  -- C1d (ronda 8): la comprobación de D-91 de la puerta lleva (1) la condición «solo si esta preparación escribe el DNI» y (2) la exención de
  --      los puentes de ESTA conversión, cada una exactamente una vez, después de la pieza de absorción y antes del P0409 de conciliación.
  --      La condición la prueban A1u/A1u2/A1v (comportamiento). La exención NO tiene prueba de comportamiento: solo se evalúa si la
  --      preparación escribe el DNI y ya existe un puente de ESTA conversión, y el reintento (A13) ya lleva el DNI y no llega ahí; por eso
  --      se inspecciona el cuerpo (como C1b con NOWAIT) y el mutante M44 muere aquí.
  v_m := '{}';
  select p.prosrc into v_src from pg_proc p where p.oid = v_puerta;
  if (length(v_src) - length(replace(v_src, 'p_tipo_documento=''DNI'' and v_l.dni is distinct from v_doc', ''))) / length('p_tipo_documento=''DNI'' and v_l.dni is distinct from v_doc') <> 1 then
    v_m := array_append(v_m, 'la comprobación de D-91 no lleva exactamente una vez la condición «p_tipo_documento=''DNI'' and v_l.dni is distinct from v_doc» (solo cuando la preparación escribe el DNI)');
  end if;
  if (length(v_src) - length(replace(v_src, 'o.detalle->>''lead_conversion''=p_lead::text', ''))) / length('o.detalle->>''lead_conversion''=p_lead::text') <> 1 then
    v_m := array_append(v_m, 'la comprobación de D-91 no exime exactamente una vez los puentes de esta conversión (o.detalle->>''lead_conversion''=p_lead::text)');
  end if;
  if strpos(v_src, 'p_tipo_documento=''DNI'' and v_l.dni is distinct from v_doc') < strpos(v_src, 'private.conversion_absorber_cliente_antiguo(')
     or strpos(v_src, 'o.detalle->>''lead_conversion''=p_lead::text') < strpos(v_src, 'p_tipo_documento=''DNI'' and v_l.dni is distinct from v_doc')
     or strpos(v_src, 'o.detalle->>''lead_conversion''=p_lead::text') > strpos(v_src, 'Esta persona ya tiene otra identidad o lead; requiere conciliación') then
    v_m := array_append(v_m, 'la condición del DNI y la exención no están en su sitio (después de la pieza de absorción, la condición antes de la exención, las dos antes del P0409 de conciliación)');
  end if;
  perform pg_temp.reg('C1d-la-comprobacion-de-d91-lleva-la-condicion-del-dni-y-la-exencion-de-esta-conversion',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO C1d-la-comprobacion-de-d91-lleva-la-condicion-del-dni-y-la-exencion-de-esta-conversion: crm.preparar_persona_lead_inversion_fn %s\n', array_to_string(v_m, '; ')) end);

  -- C1e (ronda 9): la comprobación de D-94 de la puerta (el «No insistir» de un antiguo) está UNA vez, cubre las dos mitades (los leads de la persona que
  --      cuentan como historia —la pieza de historia— y los candidatos de la pieza de absorción) y da EXACTAMENTE la respuesta del verificador (P0481, «Contacto
  --      no disponible», {"estado": "no_contactar"}); va DESPUÉS del P0409 de conciliación y ANTES del UPDATE que escribe la persona y el DNI. El
  --      comportamiento lo prueban A1w/A1wc/A1wv/A1wb; esto fija el sitio y la forma (como C1d).
  v_m := '{}';
  select p.prosrc into v_src from pg_proc p where p.oid = v_puerta;
  if (length(v_src) - length(replace(v_src, 'lx.no_contactar', ''))) / length('lx.no_contactar') <> 1
     or (length(v_src) - length(replace(v_src, 'lc.no_contactar', ''))) / length('lc.no_contactar') <> 1 then
    v_m := array_append(v_m, 'la comprobación de D-94 no mira exactamente una vez los leads de la persona que cuentan como historia (lx.no_contactar) y exactamente una vez los candidatos de la absorción (lc.no_contactar)');
  end if;
  if (length(v_src) - length(replace(v_src, 'jsonb_build_object(''estado'',''no_contactar'')::text', ''))) / length('jsonb_build_object(''estado'',''no_contactar'')::text') <> 1 then
    v_m := array_append(v_m, 'la comprobación de D-94 no responde exactamente una vez con {"estado": "no_contactar"}');
  end if;
  if strpos(v_src, 'lx.no_contactar') = 0
     or strpos(v_src, 'lx.no_contactar') < pg_temp.ultima(v_src, 'Esta persona ya tiene otra identidad o lead; requiere conciliación')
     or strpos(v_src, 'lx.no_contactar') > strpos(v_src, 'update crm.leads set inversionista_id=v_persona')
     or strpos(v_src, 'lc.no_contactar') < strpos(v_src, 'lx.no_contactar')
     or strpos(v_src, 'lc.no_contactar') > strpos(v_src, 'update crm.leads set inversionista_id=v_persona') then
    v_m := array_append(v_m, 'la comprobación de D-94 no está en su sitio (después del P0409 de conciliación y antes del UPDATE que escribe la persona y el DNI)');
  end if;
  if strpos(v_src, 'errcode=''P0481'', detail=jsonb_build_object(''estado'',''no_contactar'')::text') = 0 then
    v_m := array_append(v_m, 'la comprobación de D-94 no lanza el P0481 «Contacto no disponible» con el detalle del verificador');
  end if;
  perform pg_temp.reg('C1e-la-comprobacion-de-d94-esta-en-su-sitio-y-responde-como-el-verificador',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO C1e-la-comprobacion-de-d94-esta-en-su-sitio-y-responde-como-el-verificador: crm.preparar_persona_lead_inversion_fn %s\n', array_to_string(v_m, '; ')) end);

  v_m := '{}';
  if v_absorber is null then
    v_m := array_append(v_m, 'no existe');
  else
    select p.prosrc into v_src from pg_proc p where p.oid = v_absorber;
    if (length(v_src) - length(replace(v_src, 'for update of l nowait', ''))) / length('for update of l nowait') <> 1 then
      v_m := array_append(v_m, 'no toma los candidatos FOR UPDATE OF l NOWAIT exactamente una vez');
    end if;
    if strpos(v_src, 'lock_not_available') = 0 or strpos(v_src, '40001') = 0 then
      v_m := array_append(v_m, 'no traduce lock_not_available al 40001 de la casa');
    end if;
    if not pg_temp.ficha_ok(v_absorber, false, 'v', array['search_path=""'], 'postgres:EXECUTE:false') then
      v_m := array_append(v_m, 'su ficha no es la esperada (INVOKER, volátil, search_path vacío, dueño postgres, EXECUTE solo postgres)');
    end if;
    if strpos(coalesce(obj_description(v_absorber, 'pg_proc'), ''), 'Bloque 2.10') = 0 then
      v_m := array_append(v_m, 'su comentario no dice lo que hace');
    end if;
  end if;
  perform pg_temp.reg('C1b-la-pieza-de-absorcion-toma-los-candidatos-nowait-con-su-ficha',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO C1b-la-pieza-de-absorcion-toma-los-candidatos-nowait-con-su-ficha: private.conversion_absorber_cliente_antiguo %s\n', array_to_string(v_m, '; ')) end);
  v_m := '{}';
  if v_enlazar is null then
    v_m := array_append(v_m, 'no existe');
  else
    select p.prosrc into v_src from pg_proc p where p.oid = v_enlazar;
    if strpos(v_src, '''historico''') = 0 or strpos(v_src, 'insert into crm.inversionista_leads') = 0 then
      v_m := array_append(v_m, 'no pone el puente historico');
    end if;
    if not pg_temp.ficha_ok(v_enlazar, false, 'v', array['search_path=""'], 'postgres:EXECUTE:false') then
      v_m := array_append(v_m, 'su ficha no es la esperada (INVOKER, volátil, search_path vacío, dueño postgres, EXECUTE solo postgres)');
    end if;
    if strpos(coalesce(obj_description(v_enlazar, 'pg_proc'), ''), 'Bloque 2.10') = 0 then
      v_m := array_append(v_m, 'su comentario no dice lo que hace');
    end if;
  end if;
  perform pg_temp.reg('C1c-la-pieza-de-enlace-pone-el-puente-historico-con-su-ficha',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO C1c-la-pieza-de-enlace-pone-el-puente-historico-con-su-ficha: private.conversion_enlazar_cliente_antiguo %s\n', array_to_string(v_m, '; ')) end);

  v_m := '{}';
  if v_historia is null then
    v_m := array_append(v_m, 'no existe la pieza de historia');
  elsif not pg_temp.ficha_ok(v_historia, false, 's', array['search_path=""'], 'postgres:EXECUTE:false') then
    v_m := array_append(v_m, 'la ficha de la pieza de historia no es la esperada (INVOKER, estable, search_path vacío, dueño postgres, EXECUTE solo postgres)');
  end if;
  select p.prosrc into v_src from pg_proc p where p.oid = v_escritura;
  if (length(v_src) - length(replace(v_src, 'private.lead_historia_de_persona(', ''))) / length('private.lead_historia_de_persona(') <> 1 then
    v_m := array_append(v_m, 'inversion_persona_contexto_para no pasa su conciliación por la pieza de historia exactamente una vez');
  end if;
  select p.prosrc into v_src from pg_proc p where p.oid = v_lectura;
  if (length(v_src) - length(replace(v_src, 'private.lead_historia_de_persona(', ''))) / length('private.lead_historia_de_persona(') <> 1 then
    v_m := array_append(v_m, 'inversion_contexto_lectura_para no pasa su conciliación por la pieza de historia exactamente una vez');
  end if;
  if not pg_temp.ficha_ok(v_escritura, true, 'v', array['search_path=""', 'lock_timeout=5s'], 'postgres:EXECUTE:false')
     or not pg_temp.ficha_ok(v_lectura, true, 'v', array['search_path=""', 'lock_timeout=5s'], 'postgres:EXECUTE:false') then
    v_m := array_append(v_m, 'la ficha de un núcleo no es la de hoy');
  end if;
  if strpos(coalesce(obj_description(v_escritura, 'pg_proc'), ''), 'Bloque 2.10') = 0 or strpos(coalesce(obj_description(v_lectura, 'pg_proc'), ''), 'Bloque 2.10') = 0 then
    v_m := array_append(v_m, 'el comentario de un núcleo no dice lo que hace el 2.10');
  end if;
  perform pg_temp.reg('C2-los-dos-nucleos-del-contexto-usan-la-pieza-de-historia-con-su-ficha',
    case when cardinality(v_m) = 0 then '' else format(E'FALLO C2-los-dos-nucleos-del-contexto-usan-la-pieza-de-historia-con-su-ficha: %s\n', array_to_string(v_m, '; ')) end);

  select string_agg(x.f, ', ' order by x.f) into v_txt
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where (strpos(lower(p.prosrc), 'conversion_absorber_cliente_antiguo') > 0 or strpos(lower(p.prosrc), 'conversion_enlazar_cliente_antiguo') > 0
                or strpos(lower(p.prosrc), 'lead_historia_de_persona') > 0)
           and p.pronamespace <> pg_my_temp_schema()  -- los ayudantes de este oráculo las nombran
           and p.oid not in (coalesce(v_absorber, 0), coalesce(v_enlazar, 0), coalesce(v_historia, 0), v_puerta, v_escritura, v_lectura)
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (coalesce(v_absorber, 0), coalesce(v_enlazar, 0), coalesce(v_historia, 0))) x;
  perform pg_temp.reg('C3-solo-la-puerta-y-los-dos-nucleos-usan-las-piezas',
    case when v_txt is null and v_absorber is not null and v_enlazar is not null and v_historia is not null then ''
         when v_absorber is null or v_enlazar is null or v_historia is null then E'FALLO C3-solo-la-puerta-y-los-dos-nucleos-usan-las-piezas: faltan las piezas\n'
         else format(E'FALLO C3-solo-la-puerta-y-los-dos-nucleos-usan-las-piezas: otros usan las piezas: %s\n', v_txt) end);

  select string_agg(ex.firma, ', ' order by ex.firma) into v_txt
  from (values
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)', '33af606a814c74de5de8a080430bb299'),
    ('crm.contexto_conversion_inversion_fn(uuid,uuid)', 'a616232e3ada628404fc6a1a8356eb13'),
    ('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', '1159aa8443c117c8c9384a2bcf17ae2b'),
    ('private.identidad_bloquear_documento(text,text)', '9c08b500af7bc11aeba5e0e7d3a63330'),
    ('private.inversion_contexto_lectura(uuid,uuid)', '7ae71408f49ecd1eb2a05ed746746dde'),
    ('private.inversion_persona_contexto(uuid,uuid)', 'a7ce8164838edc6b64cdc3f933c5a276'),
    ('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)', 'c34bc06eafdb62f128476a8bffbfa642'),
    ('private.inversionista_resolver(text,text,boolean,text)', '95d502fcae257bf2a439ec3e4aa6a2dc'),
    ('private.juicio_cliente_convertido(text,text,text,uuid)', 'a2b38faf42a875c7dffb7968b106e36f'),
    ('private.leads_de_identidades(uuid[])', '2421b2b78b02b8e93fd01598e2f54128'),
    ('private.leads_de_personas(uuid[])', '6eded477639796c1053f0190f6decc18'),
    ('private.leads_protege_inversionista_id()', '6151f6d4da6c80fc62ad7f131ea398a4'),
    ('private.trg_gestion_lead_serializada()', '7af0e66b8a4849566e43b514245e1b86'),
    ('private.trg_leads_zz_enlaza_identidad()', '6ea5abfcc7bc7113f62f175df4e65879'),
    ('private.trg_leads_zz_puente_identidad()', 'e96f21d1c58623f6c2a84e7c04683a5c')) ex(firma, definicion)
  left join pg_proc p on p.oid = to_regprocedure(ex.firma)
  where p.oid is null or md5(pg_get_functiondef(p.oid)) is distinct from ex.definicion;
  perform pg_temp.reg('C4-lo-que-no-se-toca-con-su-definicion-de-hoy',
    case when v_txt is null then '' else format(E'FALLO C4-lo-que-no-se-toca-con-su-definicion-de-hoy: cambió algo que el 2.10 no toca: %s\n', v_txt) end);
  perform pg_temp.medida(format('C5 huellas al final: puerta md5(prosrc)=%s · md5(definición)=%s · escritura %s · %s · lectura %s · %s · absorción %s · enlace %s · historia %s',
    (select md5(p.prosrc) from pg_proc p where p.oid = v_puerta), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta),
    (select md5(p.prosrc) from pg_proc p where p.oid = v_escritura), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_escritura),
    (select md5(p.prosrc) from pg_proc p where p.oid = v_lectura), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_lectura),
    coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_absorber), 'ausente'),
    coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_enlazar), 'ausente'),
    coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_historia), 'ausente')));

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
