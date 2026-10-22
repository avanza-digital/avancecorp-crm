-- ORÁCULO de «La carga de bases también mira el teléfono alternativo de los clientes» (bloque 2.9) — se ejecuta en el LABORATORIO
-- (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisión D-37 de Miguel, 09/10/2026; alcance, 09/10 ~12:00: SOLO el alternativo de los leads CONVERTIDOS; plan
-- AVANCE-BACKEND-0810-F2, fase 2, bloque 2.9), sobre la carga de bases B8 (20261004184501): una fila de una base cuyo teléfono es el
-- TELÉFONO ALTERNATIVO de un cliente ya convertido (su lead está `convertido`, activo o retirado) NO entra como contacto dormido:
-- sale `ya_existia`, EXACTAMENTE como hoy con su teléfono PRINCIPAL (mismo motivo, mismo id, la misma regla del ámbito y el mismo
-- orden de relevancia del envoltorio de identidad de la carga).
--   · NO CAMBIA: el alternativo de un lead que NO es cliente (D-37), las filas libres, el teléfono principal y el DNI, los veredictos
--     del verificador (van antes y mandan), el importador y lo que no es carga de bases.
-- Hoy (sin la migración) el envoltorio `private.bases_carga_contacto_existente` solo compara el teléfono principal y el DNI de los
-- leads, y el verificador de la casa no mira el alternativo ⇒ la fila con el alternativo de un cliente se carga (nace un contacto
-- dormido con ese teléfono; medido en el 2.8, caso B1).
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (sin su `begin;`/`commit;`) dentro de
-- una única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y entonces TIENE que salir ROJO porque la fila
-- con el alternativo de un cliente entra (o, en R1, porque el motivo no es el del cliente), nunca por un error de montaje.
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT, fijada en las DOS formas
-- (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de rol con `set role` (llamar bajo `set role` a una función sin
-- EXECUTE tumba el Postgres de esta imagen): todo corre como `postgres`; la puerta `crm.cargar_base_lote` es DEFINER y resuelve el rol
-- y el ámbito con `auth.uid()`. Actores reales del banco (`PASO08 …`), OBLIGATORIOS con su rol y su equipo exactos (VEND1 bajo SUP1,
-- VEND3 bajo SUP2): sin ellos, `ENSAYO ABORTADO`.
--
-- Cómo nacen los clientes (como en los oráculos del 2.7 y del 2.8): CON PERSONA por la PUERTA REAL del formulario compartido (alta con
-- su alternativo → persona → solicitud `prodelco`, cooperativa, sin cuenta del Portal → comprobante sintético → confirmar); SIN
-- PERSONA, alta real con su alternativo y conversión sembrada con los disparadores apagados (estado heredado declarado). Retirar: como
-- lo hace Gerencia hoy. Lo que la puerta real ya no deja montar (un lead descartado con alternativo) se siembra y se declara.
--
-- RONDA 2 (09/10/2026; auditor de permisos r1 y Codex r1, `fase-2/bloque-2.9/revision/CONCILIACION.md`): D2 el DNI de un cliente
-- retirado sin persona con un teléfono libre (el resultado de B8, que no cambia) · E1 el EMPATE de categoría entre dos clientes con
-- fechas distintas (gana el más reciente: la promesa «mismo motivo y mismo id que el principal» vale cuando no hay otra coincidencia
-- que cambie la selección) · F3/F3b el ÁMBITO MIXTO (un lead propio vivo o en No contactar + el alternativo de un cliente de otro
-- equipo ⇒ solo `ya_existia`: manda la respuesta opaca; con los contadores del lote y del acumulado de la base) · F4 el cliente
-- RETIRADO de otro equipo · C2 con el verificador de 3 argumentos y la cadena del ámbito · C3 los consumidores del envoltorio, de la
-- regla del ámbito y del núcleo · C5 el candado de contacto del 2.8 r4 del que depende el orden frente a quien pone ese número como
-- alternativo de un cliente.

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

-- Contactos del ensayo: un bloque propio (+51 924 09xxxx / 7529xxxx) que el montaje exige LIBRE (el del 2.4 es 92400/7524; el del
-- 2.7, 92407/7527; el del 2.8, 92408/7528).
create function pg_temp.tel(n integer) returns text language sql immutable as $$ select '92409' || lpad(n::text, 4, '0') $$;
create function pg_temp.teln(n integer) returns text language sql immutable as $$ select '+51' || pg_temp.tel(n) $$;
create function pg_temp.dni(n integer) returns text language sql immutable as $$ select '7529' || lpad(n::text, 4, '0') $$;

create temp table ens_actores (nombre text primary key, id uuid not null);

create function pg_temp.actor(p_nombre text) returns uuid language sql as $$
  select a.id from ens_actores a where a.nombre = p_nombre
$$;

-- Foto COMPLETA de una ficha (para «sigue intacta»).
create function pg_temp.ficha(p_id uuid) returns jsonb language sql as $$
  select to_jsonb(l) from crm.leads l where l.id = p_id
$$;

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

-- Un lote de la carga de bases, como el actor (supervisión o Gerencia).
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

-- Una base de origen archivo, por la puerta real como el actor (Gerencia elige el supervisor dueño, E11). Aborta si no nace.
create function pg_temp.base(p_actor uuid, p_nombre text, p_supervisor uuid default null) returns uuid language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  begin
    perform pg_temp.sesion(p_actor);
    v_r := crm.crear_base(gen_random_uuid(), p_nombre, 'archivo', p_supervisor, 'ensayo-2-9.csv');
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

-- ── Montaje de clientes y leads ─────────────────────────────────────────────────────────────────────────────────────

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

-- CLIENTE CON PERSONA por la conversión REAL (formulario compartido, cooperativa: sin cuenta del Portal). Con p_alt, el alta lleva
-- ese teléfono alternativo. Devuelve el id del lead convertido (activo, enlazado a su persona). Como en el oráculo del 2.8.
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
             'plazo_meses', 12, 'tasa_anual', 15, 'numero_transaccion', 'ENS29-' || left(v_sol::text, 8),
             'referencia', 'ENSAYO 2.9 SINTETICA', 'evidencia', jsonb_build_object('ruta', v_ruta)));
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

-- CONVERSIÓN SEMBRADA (sin persona, estado heredado) de un lead nacido por la puerta real, como 3d/B1 del 2.4, 4a del 2.7 y el 2.8.
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
-- Exige que no quede enlazado a ninguna persona y que conserve el alternativo pedido.
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
    raise exception 'ENSAYO ABORTADO: el cliente sin persona % no quedó con el alternativo pedido % (quedó %)', p_n, p_alt,
      (select l.telefono_alternativo from crm.leads l where l.id = v_id);
  end if;
  return v_id;
end;
$f$;

-- DESCARTE SEMBRADO (estado heredado declarado) de un lead nacido por la puerta real: descartado sin interés hace 40 días (fuera del
-- enfriamiento), con los disparadores apagados; su episodio se cierra ahora como «descartado» (las reglas de lead_asignaciones).
create function pg_temp.descartar_sembrado(p_lead uuid) returns void language plpgsql as $f$
declare v_hace40 timestamptz := clock_timestamp() - interval '40 days'; v_ahora timestamptz := clock_timestamp(); v_cierra uuid;
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

-- NO CONTACTAR SEMBRADO (estado heredado declarado): el lead marcado No contactar, con los disparadores apagados (ronda 2, F3b).
create function pg_temp.no_contactar_sembrado(p_lead uuid) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = p_lead;
  set local session_replication_role = origin;
  if (select l.no_contactar from crm.leads l where l.id = p_lead) is not true then
    raise exception 'ENSAYO ABORTADO: el lead % no quedó marcado No contactar', p_lead;
  end if;
end;
$f$;

-- ── Precondiciones y jueces ─────────────────────────────────────────────────────────────────────────────────────────

-- El cliente del caso: un lead CONVERTIDO (activo o retirado, según p_activo) con EXACTAMENTE ese alternativo.
create function pg_temp.exigir_cliente(p_caso text, p_cliente uuid, p_alt text, p_activo boolean) returns void language plpgsql as $f$
begin
  if (select l.etapa = 'convertido' and l.telefono_alternativo = p_alt and l.activo = p_activo from crm.leads l where l.id = p_cliente)
     is not true then
    raise exception 'ENSAYO ABORTADO: %: el cliente no es un convertido % con el alternativo %', p_caso,
      case when p_activo then 'activo' else 'retirado' end, p_alt;
  end if;
end;
$f$;

-- Hoy la fila se CARGARÍA: el verificador dice «libre» con su teléfono (normalizado) y su DNI, y ningún lead tiene ese teléfono como
-- principal ni ese DNI (el envoltorio de hoy no lo vería). Si no, el caso no mediría la regla nueva y el ensayo aborta.
create function pg_temp.exigir_carga_hoy(p_caso text, p_tel text, p_dni text) returns void language plpgsql as $f$
declare v_t text := private.normalizar_telefono(p_tel); v_v jsonb;
begin
  v_v := private.verificar_disponibilidad_lead_impl(v_t, p_dni);
  if v_v ->> 'estado' is distinct from 'libre' then
    raise exception 'ENSAYO ABORTADO: %: el verificador no dice «libre» con % (%): el caso no mediría la regla', p_caso, v_t, v_v;
  end if;
  if exists (select 1 from crm.leads l where l.telefono = v_t or (p_dni is not null and l.dni = p_dni)) then
    raise exception 'ENSAYO ABORTADO: %: ya hay un lead con el teléfono principal % o el DNI de la fila (el envoltorio de hoy ya lo vería)', p_caso, v_t;
  end if;
end;
$f$;

-- El veredicto esperado de una fila que NO entra (sin su número de fila): `ya_existia` con su motivo y su lead_id si los lleva.
create function pg_temp.esp(p_motivo text, p_lead uuid) returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object('veredicto', 'ya_existia', 'motivo', p_motivo, 'lead_id', p_lead))
$$;

-- Una fila que NO debe entrar: la carga responde con EXACTAMENTE p_esperado, el lote cuenta 1 ya_existia y 0 cargadas, no nace ningún
-- lead con ese teléfono, la base no gana pertenencias, el cliente queda intacto y la respuesta no lleva su nombre, sus teléfonos ni su
-- DNI (la respuesta de la carga no lleva datos personales: prueba B8 del gate). Si la fila ENTRA, el fallo dice el defecto.
create function pg_temp.no_entra(p_caso text, p_actor uuid, p_base uuid, p_tel text, p_dni text, p_esperado jsonb, p_cliente uuid)
returns void language plpgsql as $f$
declare
  v_t text := private.normalizar_telefono(p_tel);
  v_antes bigint := (select count(*) from crm.leads l where l.telefono = v_t);
  v_perten bigint := (select count(*) from crm.base_carga_leads bl where bl.base_id = p_base);
  v_fc jsonb := pg_temp.ficha(p_cliente);
  v_res text; v_r jsonb; v_f jsonb; v_m text[] := '{}'; v_despues bigint; v_dato text;
begin
  v_res := pg_temp.cargar(p_actor, p_base, jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
             'fila', 1, 'nombre', 'CONTACTO ' || split_part(p_caso, ' ', 1), 'telefono', p_tel, 'dni', p_dni))));
  perform pg_temp.medida(format('%s · fila (teléfono «%s»%s) → %s', p_caso, p_tel, coalesce(', DNI ' || p_dni, ''), v_res));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la carga falló (%s) en vez de responder %s\n', p_caso, v_res, p_esperado));
    return;
  end if;
  v_r := substr(v_res, 4)::jsonb;
  v_f := v_r #> '{filas,0}';
  v_despues := (select count(*) from crm.leads l where l.telefono = v_t);
  if v_f ->> 'veredicto' = 'cargada' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la fila ENTRÓ como contacto dormido (cargada) → nació un lead con el teléfono %s, que es de un cliente ya convertido: %s lead(s) con ese teléfono (había %s); se esperaba %s\n',
      p_caso, v_t, v_despues, v_antes, p_esperado));
    return;
  end if;
  if (v_f - 'fila') is distinct from p_esperado then
    v_m := array_append(v_m, format('la fila respondió %s, se esperaba EXACTAMENTE %s', v_f - 'fila', p_esperado));
  end if;
  if (v_r #>> '{lote,ya_existian}') is distinct from '1' or (v_r #>> '{lote,cargadas}') is distinct from '0' then
    v_m := array_append(v_m, format('conteos del lote %s (se esperaba 1 ya_existia y 0 cargadas)', v_r -> 'lote'));
  end if;
  if v_despues <> v_antes then
    v_m := array_append(v_m, format('nació un lead con el teléfono %s (%s; había %s)', v_t, v_despues, v_antes));
  end if;
  if (select count(*) from crm.base_carga_leads bl where bl.base_id = p_base) <> v_perten then
    v_m := array_append(v_m, 'la base ganó una pertenencia');
  end if;
  if pg_temp.ficha(p_cliente) is distinct from v_fc then
    v_m := array_append(v_m, 'la ficha del cliente cambió');
  end if;
  for v_dato in
    select x from unnest(array[(v_fc ->> 'nombre_completo'), (v_fc ->> 'telefono'), (v_fc ->> 'telefono_alternativo'),
                               right(v_fc ->> 'telefono', 9), right(v_fc ->> 'telefono_alternativo', 9), (v_fc ->> 'dni')]) x
     where x is not null
  loop
    if position(v_dato in v_res) > 0 then
      v_m := array_append(v_m, format('la respuesta lleva un dato personal del cliente («%s»)', v_dato));
    end if;
  end loop;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- Lo mismo con una BASE NUEVA de SUP1 para el caso (ronda 2): además de la fila exacta, los contadores del lote y del ACUMULADO de la
-- base (la respuesta y la fila de `crm.bases_carga`) tienen que ser EXACTAMENTE p_lote (la base nace con este lote). Mide el traslado
-- entre contadores (`no_contactar` → `ya_existian`) del ámbito mixto.
create function pg_temp.no_entra_base_nueva(p_caso text, p_actor uuid, p_tel text, p_esperado jsonb, p_cliente uuid, p_lote jsonb)
returns void language plpgsql as $f$
declare
  v_t text := private.normalizar_telefono(p_tel);
  v_base uuid := pg_temp.base(p_actor, 'BASE ENSAYO 2.9 ' || split_part(p_caso, '-', 1));
  v_antes bigint := (select count(*) from crm.leads l where l.telefono = v_t);
  v_fc jsonb := pg_temp.ficha(p_cliente);
  v_res text; v_r jsonb; v_f jsonb; v_m text[] := '{}'; v_base_esp jsonb; v_fila_base jsonb;
begin
  v_res := pg_temp.cargar(p_actor, v_base, jsonb_build_array(jsonb_build_object('fila', 1, 'nombre', 'CONTACTO ' || split_part(p_caso, ' ', 1),
                                                                                'telefono', p_tel)));
  perform pg_temp.medida(format('%s · fila (teléfono «%s», base nueva) → %s', p_caso, p_tel, v_res));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la carga falló (%s) en vez de responder %s\n', p_caso, v_res, p_esperado));
    return;
  end if;
  v_r := substr(v_res, 4)::jsonb;
  v_f := v_r #> '{filas,0}';
  if v_f ->> 'veredicto' = 'cargada' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la fila ENTRÓ como contacto dormido (cargada) → nació un lead con el teléfono %s, que es de un cliente ya convertido; se esperaba %s\n',
      p_caso, v_t, p_esperado));
    return;
  end if;
  if (v_f - 'fila') is distinct from p_esperado then
    v_m := array_append(v_m, format('la fila respondió %s, se esperaba EXACTAMENTE %s', v_f - 'fila', p_esperado));
  end if;
  if (v_r -> 'lote') is distinct from p_lote then
    v_m := array_append(v_m, format('el lote contó %s, se esperaba EXACTAMENTE %s', v_r -> 'lote', p_lote));
  end if;
  v_base_esp := jsonb_build_object('filas_recibidas', p_lote -> 'filas', 'cargadas', p_lote -> 'cargadas', 'ya_existian', p_lote -> 'ya_existian',
                                   'no_contactar', p_lote -> 'no_contactar', 'invalidas', p_lote -> 'invalidas', 'repetidas', p_lote -> 'repetidas');
  if (v_r -> 'base') is distinct from v_base_esp then
    v_m := array_append(v_m, format('el acumulado de la base en la respuesta es %s, se esperaba EXACTAMENTE %s', v_r -> 'base', v_base_esp));
  end if;
  select jsonb_build_object('filas_recibidas', b.filas_recibidas, 'cargadas', b.cargadas, 'ya_existian', b.ya_existian,
                            'no_contactar', b.no_contactar, 'invalidas', b.invalidas, 'repetidas', b.repetidas)
    into v_fila_base from crm.bases_carga b where b.id = v_base;
  if v_fila_base is distinct from v_base_esp then
    v_m := array_append(v_m, format('la fila de la base en crm.bases_carga guarda %s, se esperaba %s', v_fila_base, v_base_esp));
  end if;
  if (select count(*) from crm.leads l where l.telefono = v_t) <> v_antes then
    v_m := array_append(v_m, format('nació un lead con el teléfono %s', v_t));
  end if;
  if pg_temp.ficha(p_cliente) is distinct from v_fc then
    v_m := array_append(v_m, 'la ficha del cliente cambió');
  end if;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- Una fila que SÍ debe entrar, como hoy: `cargada` (sin motivo ni id) y nace su contacto DORMIDO (descartado, motivo y origen
-- base_cargada, activo, en la bandeja del supervisor de la base, sin analista) como miembro de la base.
create function pg_temp.entra(p_caso text, p_actor uuid, p_base uuid, p_tel text, p_dni text default null)
returns void language plpgsql as $f$
declare
  v_t text := private.normalizar_telefono(p_tel);
  v_sup uuid := (select b.supervisor_id from crm.bases_carga b where b.id = p_base);
  v_res text; v_f jsonb;
begin
  v_res := pg_temp.cargar(p_actor, p_base, jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
             'fila', 1, 'nombre', 'CONTACTO ' || split_part(p_caso, ' ', 1), 'telefono', p_tel, 'dni', p_dni))));
  perform pg_temp.medida(format('%s · fila (teléfono «%s»%s) → %s', p_caso, p_tel, coalesce(', DNI ' || p_dni, ''), v_res));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la carga falló (%s) y hoy la fila se carga\n', p_caso, v_res));
    return;
  end if;
  v_f := substr(v_res, 4)::jsonb #> '{filas,0}';
  if (v_f - 'fila') is distinct from '{"veredicto": "cargada"}'::jsonb then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la fila NO entró (%s) y hoy se carga: la regla bloquea un teléfono que no es de ningún cliente\n', p_caso, v_f));
    return;
  end if;
  perform pg_temp.reg(p_caso, case when exists (
      select 1 from crm.leads l join crm.base_carga_leads bl on bl.lead_id = l.id and bl.base_id = p_base and bl.activo
       where l.telefono = v_t and l.origen = 'base_cargada' and l.etapa = 'descartado' and l.motivo_descarte = 'base_cargada'
         and l.activo and l.vendedor_id is null and l.asignado_supervisor_id = v_sup)
    then '' else format(E'FALLO %s: respondió «cargada» pero no nació el contacto dormido de la base con %s\n', p_caso, v_t) end);
end;
$f$;

insert into ens_actores (nombre, id)
select n.nombre, p.id
from (values ('VEND1'), ('VEND2'), ('VEND3'), ('SUP1'), ('SUP2'), ('GERENCIA')) n(nombre)
join public.perfiles p on p.nombre_completo = 'PASO08 ' || n.nombre;

do $ensayo$
declare
  v_vend1 uuid; v_vend2 uuid; v_vend3 uuid; v_sup1 uuid; v_sup2 uuid; v_ger uuid;
  v_env regprocedure := to_regprocedure('private.bases_carga_contacto_existente(text,text)');
  v_bs uuid; v_bg uuid;
  v_c uuid; v_l uuid; v_res text; v_r jsonb; v_txt text; v_r2 text; v_vis1 boolean; v_vis3 boolean;
  v_a uuid := '00000000-0029-4000-8000-0000000000a1'; v_b uuid := 'ffffffff-0029-4000-8000-0000000000b1';
  v_nucleo regprocedure := to_regprocedure('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)');
  v_ambito regprocedure := to_regprocedure('private.bases_carga_fuera_de_ambito(uuid,text,text,text)');
  v_puerta regprocedure := to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)');
  v_disp regprocedure := to_regprocedure('private.trg_leads_disponibilidad_atomica()');
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
  -- El ámbito de SUP1 (espejo de leads_select, `private.base_gestion_lead_visible`), con SU sesión: VEND1 dentro, VEND3 fuera.
  perform pg_temp.sesion(v_sup1);
  v_vis1 := private.base_gestion_lead_visible(v_sup1, 'supervisor', v_vend1, null);
  v_vis3 := private.base_gestion_lead_visible(v_sup1, 'supervisor', v_vend3, null);
  perform pg_temp.sesion(null);
  if private.rol_crm(v_vend1) is distinct from 'vendedor' or private.rol_crm(v_vend2) is distinct from 'vendedor'
     or private.rol_crm(v_vend3) is distinct from 'vendedor' or private.rol_crm(v_sup1) is distinct from 'supervisor'
     or private.rol_crm(v_sup2) is distinct from 'supervisor' or private.rol_crm(v_ger) is distinct from 'gerencia'
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend1) is distinct from v_sup1
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend3) is distinct from v_sup2
     or v_vis1 is not true or v_vis3 is not false then
    raise exception 'ENSAYO ABORTADO: un actor del banco no tiene el rol o el equipo esperado (vend1/vend2/vend3 vendedores; vend1 bajo sup1 y visible para él; vend3 bajo sup2 y fuera del ámbito de sup1; sup1 y sup2 supervisores; gerencia)';
  end if;
  -- El bloque de contactos del ensayo tiene que estar libre (teléfono, alternativo, DNI, perfiles y documentos).
  if exists (select 1 from crm.leads l where l.telefono like '+5192409%' or l.telefono_alternativo like '%92409%'
                                             or l.telefono_alternativo_crudo like '%92409%' or l.dni like '7529%')
     or exists (select 1 from public.perfiles p where p.telefono like '%92409%' or p.dni like '7529%')
     or exists (select 1 from crm.inversionista_identificadores d where d.documento_normalizado like '7529%'
                                                                   or d.documento_normalizado like '%92409%') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene contactos del bloque +51 924 09xxxx / 7529xxxx';
  end if;
  -- El cubo de comprobantes de la conversión real (fixture del banco; si falta, vive y muere en esta transacción).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('f4-comprobantes', 'f4-comprobantes', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
  on conflict (id) do nothing;
  -- Medidas del punto de partida (no son casos).
  perform pg_temp.medida(format('T0 envoltorio %s: md5(prosrc)=%s · md5(definición)=%s · md5(comentario)=%s · ¿mira el alternativo? %s',
    coalesce(v_env::text, 'AUSENTE'), (select md5(p.prosrc) from pg_proc p where p.oid = v_env),
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_env),
    (select md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) from pg_proc p where p.oid = v_env),
    case when position('telefono_alternativo' in (select p.prosrc from pg_proc p where p.oid = v_env)) > 0 then 'sí' else 'no' end));
  perform pg_temp.medida(format('T0 bandera resolver_en_puertas=%s',
    coalesce((select f.activo::text from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), 'ausente')));

  -- Las bases del ensayo: una de SUP1 (la carga él) y otra de SUP1 que carga Gerencia (E11: Gerencia elige el supervisor dueño).
  v_bs := pg_temp.base(v_sup1, 'BASE ENSAYO 2.9 SUP1');
  v_bg := pg_temp.base(v_ger, 'BASE ENSAYO 2.9 GERENCIA', v_sup1);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A. EL ALTERNATIVO DE UN CLIENTE ⇒ `ya_existia`, EXACTAMENTE COMO SU TELÉFONO PRINCIPAL HOY (Ap: el principal, que ya se detecta;
  --    A: el alternativo, que hoy se carga). A1 con persona y activo · A2 con persona y RETIRADO (motivo `retirado`, sin id: como su
  --    principal) · A3 sin persona y activo · A4 sin persona y retirado · A5 la carga Gerencia (ve a todos).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(1, 'CLIENTE A1 CON PERSONA', v_vend1, pg_temp.teln(301));
  perform pg_temp.exigir_cliente('A1', v_c, pg_temp.teln(301), true);
  perform pg_temp.no_entra('A1p-telefono-principal-de-un-cliente-activo-con-persona (como hoy)', v_sup1, v_bs, pg_temp.teln(1), null,
    pg_temp.esp('convertido', v_c), v_c);
  perform pg_temp.exigir_carga_hoy('A1', pg_temp.teln(301), null);
  perform pg_temp.no_entra('A1-alternativo-de-un-cliente-activo-con-persona', v_sup1, v_bs, pg_temp.teln(301), null,
    pg_temp.esp('convertido', v_c), v_c);

  v_c := pg_temp.convertir_real(2, 'CLIENTE A2 CON PERSONA RETIRADO', v_vend1, pg_temp.teln(302));
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente A2'; end if;
  perform pg_temp.exigir_cliente('A2', v_c, pg_temp.teln(302), false);
  perform pg_temp.no_entra('A2p-telefono-principal-de-un-cliente-retirado-con-persona (como hoy)', v_sup1, v_bs, pg_temp.teln(2), null,
    pg_temp.esp('retirado', null), v_c);
  perform pg_temp.exigir_carga_hoy('A2', pg_temp.teln(302), null);
  perform pg_temp.no_entra('A2-alternativo-de-un-cliente-retirado-con-persona (motivo retirado, como su principal)', v_sup1, v_bs,
    pg_temp.teln(302), null, pg_temp.esp('retirado', null), v_c);

  v_c := pg_temp.cliente_sin_persona(3, 'CLIENTE A3 SIN PERSONA', v_vend1, false, pg_temp.teln(303));
  perform pg_temp.exigir_cliente('A3', v_c, pg_temp.teln(303), true);
  perform pg_temp.no_entra('A3p-telefono-principal-de-un-cliente-activo-sin-persona (como hoy)', v_sup1, v_bs, pg_temp.teln(3), null,
    pg_temp.esp('convertido', v_c), v_c);
  perform pg_temp.exigir_carga_hoy('A3', pg_temp.teln(303), null);
  perform pg_temp.no_entra('A3-alternativo-de-un-cliente-activo-sin-persona', v_sup1, v_bs, pg_temp.teln(303), null,
    pg_temp.esp('convertido', v_c), v_c);

  v_c := pg_temp.cliente_sin_persona(4, 'CLIENTE A4 SIN PERSONA RETIRADO', v_vend1, true, pg_temp.teln(304));
  perform pg_temp.exigir_cliente('A4', v_c, pg_temp.teln(304), false);
  perform pg_temp.no_entra('A4p-telefono-principal-de-un-cliente-retirado-sin-persona (como hoy)', v_sup1, v_bs, pg_temp.teln(4), null,
    pg_temp.esp('retirado', null), v_c);
  perform pg_temp.exigir_carga_hoy('A4', pg_temp.teln(304), null);
  perform pg_temp.no_entra('A4-alternativo-de-un-cliente-retirado-sin-persona (motivo retirado, como su principal)', v_sup1, v_bs,
    pg_temp.teln(304), null, pg_temp.esp('retirado', null), v_c);

  v_c := pg_temp.convertir_real(5, 'CLIENTE A5 CON PERSONA', v_vend1, pg_temp.teln(305));
  perform pg_temp.exigir_cliente('A5', v_c, pg_temp.teln(305), true);
  perform pg_temp.no_entra('A5p-telefono-principal-de-un-cliente-lo-carga-gerencia (como hoy)', v_ger, v_bg, pg_temp.teln(5), null,
    pg_temp.esp('convertido', v_c), v_c);
  perform pg_temp.exigir_carga_hoy('A5', pg_temp.teln(305), null);
  perform pg_temp.no_entra('A5-alternativo-de-un-cliente-lo-carga-gerencia', v_ger, v_bg, pg_temp.teln(305), null,
    pg_temp.esp('convertido', v_c), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- F. LA REGLA DEL ÁMBITO, LA MISMA: F1 SUP1 carga el alternativo de un cliente de VEND3 (equipo de SUP2, fuera de su ámbito) ⇒ solo
  --    `ya_existia`, sin motivo ni id (como su principal, F1p) · F2 Gerencia carga el de otro cliente de VEND3 ⇒ motivo e id.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(6, 'CLIENTE F1 DE OTRO EQUIPO', v_vend3, pg_temp.teln(306));
  perform pg_temp.exigir_cliente('F1', v_c, pg_temp.teln(306), true);
  perform pg_temp.no_entra('F1p-telefono-principal-de-un-cliente-de-otro-equipo (sin motivo ni id, como hoy)', v_sup1, v_bs, pg_temp.teln(6),
    null, pg_temp.esp(null, null), v_c);
  perform pg_temp.exigir_carga_hoy('F1', pg_temp.teln(306), null);
  perform pg_temp.no_entra('F1-alternativo-de-un-cliente-de-otro-equipo (sin motivo ni id)', v_sup1, v_bs, pg_temp.teln(306), null,
    pg_temp.esp(null, null), v_c);
  v_c := pg_temp.convertir_real(7, 'CLIENTE F2 DE OTRO EQUIPO', v_vend3, pg_temp.teln(307));
  perform pg_temp.exigir_cliente('F2', v_c, pg_temp.teln(307), true);
  perform pg_temp.exigir_carga_hoy('F2', pg_temp.teln(307), null);
  perform pg_temp.no_entra('F2-alternativo-de-un-cliente-de-otro-equipo-lo-carga-gerencia', v_ger, v_bg, pg_temp.teln(307), null,
    pg_temp.esp('convertido', v_c), v_c);

  -- F3/F3b (ronda 2; auditor P3-3, Codex): el ÁMBITO MIXTO. El teléfono de la fila es el principal de un lead PROPIO (de VEND1, en
  -- el ámbito de SUP1) y el alternativo de un cliente de OTRO equipo (VEND3) ⇒ con el 2.9 manda la respuesta OPACA de la regla del
  -- ámbito de B8 r1 (cualquier coincidencia fuera del ámbito oculta todo): solo `ya_existia`, sin motivo ni id, y cuenta en
  -- `ya_existian` del lote y del acumulado de la base. Hoy: F3 `con_dueno` con el id del lead propio; F3b `no_contactar` (motivo
  -- `no_insistir`, con su id), que contaba en `no_contactar`. Decisión del Director (conciliación r1), ratificada por Codex. Cada uno en
  -- una base NUEVA de SUP1, para medir también su acumulado.
  v_l := pg_temp.lead_nuevo(v_vend1, 91, 'LEAD F3 PROPIO VIVO');
  v_c := pg_temp.convertir_real(92, 'CLIENTE F3 DE OTRO EQUIPO', v_vend3, pg_temp.teln(91));
  perform pg_temp.exigir_cliente('F3', v_c, pg_temp.teln(91), true);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(91), null) ->> 'estado' is distinct from 'tomado' then
    raise exception 'ENSAYO ABORTADO: F3: el verificador no dice «tomado» con el teléfono del lead propio';
  end if;
  perform pg_temp.no_entra_base_nueva('F3-principal-propio-vivo-y-alternativo-de-un-cliente-de-otro-equipo (manda la respuesta opaca)', v_sup1,
    pg_temp.teln(91), pg_temp.esp(null, null), v_c,
    '{"filas": 1, "cargadas": 0, "invalidas": 0, "repetidas": 0, "ya_existian": 1, "no_contactar": 0}'::jsonb);
  v_l := pg_temp.lead_nuevo(v_vend1, 93, 'LEAD F3B PROPIO NO CONTACTAR');
  perform pg_temp.no_contactar_sembrado(v_l);
  v_c := pg_temp.convertir_real(94, 'CLIENTE F3B DE OTRO EQUIPO', v_vend3, pg_temp.teln(93));
  perform pg_temp.exigir_cliente('F3b', v_c, pg_temp.teln(93), true);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(93), null) ->> 'estado' is distinct from 'no_contactar' then
    raise exception 'ENSAYO ABORTADO: F3b: el verificador no dice «no_contactar» con el teléfono del lead propio vetado';
  end if;
  perform pg_temp.no_entra_base_nueva('F3b-principal-propio-no-contactar-y-alternativo-de-un-cliente-de-otro-equipo (manda la respuesta opaca: cuenta en ya_existian)',
    v_sup1, pg_temp.teln(93), pg_temp.esp(null, null), v_c,
    '{"filas": 1, "cargadas": 0, "invalidas": 0, "repetidas": 0, "ya_existian": 1, "no_contactar": 0}'::jsonb);
  -- F4 (ronda 2, conciliación r1): el cliente RETIRADO de otro equipo ⇒ solo `ya_existia`, como su principal (F4p).
  v_c := pg_temp.convertir_real(96, 'CLIENTE F4 DE OTRO EQUIPO RETIRADO', v_vend3, pg_temp.teln(396));
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente F4'; end if;
  perform pg_temp.exigir_cliente('F4', v_c, pg_temp.teln(396), false);
  perform pg_temp.no_entra('F4p-telefono-principal-de-un-cliente-retirado-de-otro-equipo (sin motivo ni id, como hoy)', v_sup1, v_bs,
    pg_temp.teln(96), null, pg_temp.esp(null, null), v_c);
  perform pg_temp.exigir_carga_hoy('F4', pg_temp.teln(396), null);
  perform pg_temp.no_entra('F4-alternativo-de-un-cliente-retirado-de-otro-equipo (sin motivo ni id)', v_sup1, v_bs, pg_temp.teln(396), null,
    pg_temp.esp(null, null), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- N. NO CAMBIA (D-37): el alternativo de un lead que NO es cliente sigue sin mirarse ⇒ `cargada`, como hoy. N1 lead vivo · N2 lead
  --    descartado (sembrado) · N3 lead retirado · N4 un teléfono libre · N5 el alternativo INTERNACIONAL de 9 dígitos de un cliente
  --    (+924090315) no es el móvil peruano +51 924 090 315 de la fila: comparación literal de formas canónicas, como el 2.8.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l := pg_temp.lead_nuevo(v_vend1, 11, 'LEAD N1 VIVO CON ALTERNATIVO', null, pg_temp.teln(311));
  perform pg_temp.exigir_carga_hoy('N1', pg_temp.teln(311), null);
  perform pg_temp.entra('N1-alternativo-de-un-lead-vivo-que-no-es-cliente (se carga como hoy)', v_sup1, v_bs, pg_temp.teln(311));
  v_l := pg_temp.lead_nuevo(v_vend1, 12, 'LEAD N2 DESCARTADO CON ALTERNATIVO', null, pg_temp.teln(312));
  perform pg_temp.descartar_sembrado(v_l);
  perform pg_temp.exigir_carga_hoy('N2', pg_temp.teln(312), null);
  perform pg_temp.entra('N2-alternativo-de-un-lead-descartado-que-no-es-cliente (se carga como hoy)', v_sup1, v_bs, pg_temp.teln(312));
  v_l := pg_temp.lead_nuevo(v_vend1, 13, 'LEAD N3 RETIRADO CON ALTERNATIVO', null, pg_temp.teln(313));
  if pg_temp.retirar(v_ger, v_l) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar el lead N3'; end if;
  perform pg_temp.exigir_carga_hoy('N3', pg_temp.teln(313), null);
  perform pg_temp.entra('N3-alternativo-de-un-lead-retirado-que-no-es-cliente (se carga como hoy)', v_sup1, v_bs, pg_temp.teln(313));
  perform pg_temp.exigir_carga_hoy('N4', pg_temp.teln(314), null);
  perform pg_temp.entra('N4-telefono-libre (se carga como hoy)', v_sup1, v_bs, pg_temp.teln(314));
  v_c := pg_temp.cliente_sin_persona(15, 'CLIENTE N5 CON ALTERNATIVO INTERNACIONAL', v_vend1, false, '+' || pg_temp.tel(315));
  perform pg_temp.exigir_cliente('N5', v_c, '+' || pg_temp.tel(315), true);
  perform pg_temp.exigir_carga_hoy('N5', pg_temp.teln(315), null);
  perform pg_temp.entra('N5-movil-peruano-con-los-mismos-digitos-que-el-alternativo-internacional-de-un-cliente (otro número: se carga como hoy)',
    v_sup1, v_bs, pg_temp.teln(315));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- R. EL MISMO ORDEN DE RELEVANCIA Y EL VERIFICADOR MANDA: R1 el teléfono de la fila es el PRINCIPAL de una ficha RETIRADA (no
  --    cliente) y el ALTERNATIVO de un cliente ACTIVO ⇒ manda el cliente activo (convertido antes que retirado): motivo `convertido` y
  --    su id (hoy, `retirado`) · R2 el principal de un lead VIVO y el alternativo de un cliente ⇒ el verificador dice «tomado» y manda:
  --    `con_dueno` con el id del lead vivo (como hoy).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l := pg_temp.lead_nuevo(v_vend1, 21, 'LEAD R1 QUE SE RETIRA');
  if pg_temp.retirar(v_ger, v_l) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar el lead R1'; end if;
  v_c := pg_temp.cliente_sin_persona(22, 'CLIENTE R1 CON EL TELEFONO DEL RETIRADO', v_vend1, false, pg_temp.teln(21));
  perform pg_temp.exigir_cliente('R1', v_c, pg_temp.teln(21), true);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(21), null) ->> 'estado' is distinct from 'libre' then
    raise exception 'ENSAYO ABORTADO: R1: el verificador no dice «libre» con el teléfono de la ficha retirada';
  end if;
  perform pg_temp.no_entra('R1-principal-de-un-retirado-y-alternativo-de-un-cliente-activo (manda el cliente: convertido)', v_sup1, v_bs,
    pg_temp.teln(21), null, pg_temp.esp('convertido', v_c), v_c);
  v_l := pg_temp.lead_nuevo(v_vend1, 23, 'LEAD R2 VIVO');
  v_c := pg_temp.cliente_sin_persona(24, 'CLIENTE R2 CON EL TELEFONO DEL VIVO', v_vend1, false, pg_temp.teln(23));
  perform pg_temp.exigir_cliente('R2', v_c, pg_temp.teln(23), true);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(23), null) ->> 'estado' is distinct from 'tomado' then
    raise exception 'ENSAYO ABORTADO: R2: el verificador no dice «tomado» con el teléfono del lead vivo';
  end if;
  perform pg_temp.no_entra('R2-principal-de-un-lead-vivo-y-alternativo-de-un-cliente (manda el verificador: con_dueno, como hoy)', v_sup1, v_bs,
    pg_temp.teln(23), null, pg_temp.esp('con_dueno', v_l), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E. EL GANADOR ENTRE VARIAS COINCIDENCIAS (ronda 2, Codex P3-3). E1 EMPATE de categoría con fechas distintas: el teléfono de la
  --    fila es el PRINCIPAL de un cliente A y el ALTERNATIVO de otro cliente B, los dos convertidos activos (misma categoría). El
  --    envoltorio ordena por categoría, después por `creado_en` (el más reciente primero) y por id: gana B (creado después) aunque su id
  --    sea MAYOR ⇒ el id cambia respecto de hoy (hoy el conjunto solo tiene a A). La promesa «mismo motivo y mismo id que el principal»
  --    vale cuando no hay otra coincidencia que cambie la selección. Sembrado declarado: ids fijos, `creado_en` de A hace 10 días y
  --    de B hace 1 día (dentro del ensayo todas las altas comparten el `statement_timestamp()` del bloque).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_res := pg_temp.alta(v_vend1, v_b, 'CLIENTE E1 B CON EL ALTERNATIVO', pg_temp.tel(82), pg_temp.dni(82), pg_temp.teln(81));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: E1: no nació el lead de B por la puerta real (%)', v_res;
  end if;
  v_res := pg_temp.alta(v_vend1, v_a, 'CLIENTE E1 A CON EL PRINCIPAL', pg_temp.tel(81), pg_temp.dni(81));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: E1: no nació el lead de A por la puerta real (%)', v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_a, false);
  perform pg_temp.convertir_sembrado(v_b, false);
  set local session_replication_role = replica;
  update crm.leads set creado_en = now() - interval '10 days' where id = v_a;
  update crm.leads set creado_en = now() - interval '1 day' where id = v_b;
  set local session_replication_role = origin;
  perform pg_temp.exigir_cliente('E1 (B)', v_b, pg_temp.teln(81), true);
  if (select l.etapa || '|' || l.activo::text || '|' || l.telefono from crm.leads l where l.id = v_a) is distinct from 'convertido|true|' || pg_temp.teln(81)
     or (select l.creado_en < (select b.creado_en from crm.leads b where b.id = v_b) from crm.leads l where l.id = v_a) is not true
     or private.verificar_disponibilidad_lead_impl(pg_temp.teln(81), null) ->> 'estado' is distinct from 'libre' then
    raise exception 'ENSAYO ABORTADO: E1: A no es un convertido activo con ese principal, no es más antiguo que B o el verificador no dice «libre»';
  end if;
  perform pg_temp.no_entra('E1-empate-de-categoria-gana-el-cliente-mas-reciente (principal de A, alternativo de B: B)', v_sup1, v_bs,
    pg_temp.teln(81), null, pg_temp.esp('convertido', v_b), v_b);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- Z. LA MISMA NORMALIZACIÓN: la fila trae el alternativo del cliente en otra forma y la carga lo normaliza antes de comparar ⇒
  --    `ya_existia`. Z1 con espacios · Z2 con +51 y guiones · Z3 con 51 delante · Z4 los nueve dígitos (lo habitual en un archivo).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(31, 'CLIENTE Z1', v_vend1, false, pg_temp.teln(331));
  perform pg_temp.exigir_carga_hoy('Z1', pg_temp.teln(331), null);
  perform pg_temp.no_entra('Z1-alternativo-de-un-cliente-con-espacios', v_sup1, v_bs,
    substr(pg_temp.tel(331), 1, 3) || ' ' || substr(pg_temp.tel(331), 4, 3) || ' ' || substr(pg_temp.tel(331), 7, 3), null,
    pg_temp.esp('convertido', v_c), v_c);
  v_c := pg_temp.cliente_sin_persona(32, 'CLIENTE Z2', v_vend1, false, pg_temp.teln(332));
  perform pg_temp.exigir_carga_hoy('Z2', pg_temp.teln(332), null);
  perform pg_temp.no_entra('Z2-alternativo-de-un-cliente-con-prefijo-y-guiones', v_sup1, v_bs,
    '+51 ' || substr(pg_temp.tel(332), 1, 3) || '-' || substr(pg_temp.tel(332), 4, 3) || '-' || substr(pg_temp.tel(332), 7, 3), null,
    pg_temp.esp('convertido', v_c), v_c);
  v_c := pg_temp.cliente_sin_persona(33, 'CLIENTE Z3', v_vend1, false, pg_temp.teln(333));
  perform pg_temp.exigir_carga_hoy('Z3', pg_temp.teln(333), null);
  perform pg_temp.no_entra('Z3-alternativo-de-un-cliente-con-51-delante', v_sup1, v_bs, '51' || pg_temp.tel(333), null,
    pg_temp.esp('convertido', v_c), v_c);
  v_c := pg_temp.cliente_sin_persona(34, 'CLIENTE Z4', v_vend1, false, pg_temp.teln(334));
  perform pg_temp.exigir_carga_hoy('Z4', pg_temp.teln(334), null);
  perform pg_temp.no_entra('Z4-alternativo-de-un-cliente-en-nueve-digitos', v_sup1, v_bs, pg_temp.tel(334), null,
    pg_temp.esp('convertido', v_c), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- D. CON DNI: D1 la fila trae el alternativo de un cliente y un DNI libre ⇒ `ya_existia` (el teléfono basta).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(41, 'CLIENTE D1', v_vend1, false, pg_temp.teln(341));
  perform pg_temp.exigir_carga_hoy('D1', pg_temp.teln(341), pg_temp.dni(941));
  perform pg_temp.no_entra('D1-alternativo-de-un-cliente-con-un-dni-libre', v_sup1, v_bs, pg_temp.teln(341), pg_temp.dni(941),
    pg_temp.esp('convertido', v_c), v_c);
  -- D2 (ronda 2, Codex P3-2): un teléfono LIBRE con el DNI de un cliente RETIRADO SIN PERSONA ⇒ el resultado de B8, que no cambia
  -- (`ya_existia`, `retirado`, sin id: la ficha está retirada). Antes, el verificador dice «libre» (no reconoce el DNI de un cliente
  -- sin persona) y nadie tiene ese teléfono: lo decide la coincidencia por DNI del envoltorio.
  v_c := pg_temp.cliente_sin_persona(42, 'CLIENTE D2 SIN PERSONA RETIRADO', v_vend1, true, null);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(342), pg_temp.dni(42)) ->> 'estado' is distinct from 'libre'
     or exists (select 1 from crm.leads l where l.telefono = pg_temp.teln(342))
     or (select l.dni || '|' || l.etapa || '|' || l.activo::text || '|' || (l.inversionista_id is null)::text from crm.leads l where l.id = v_c)
        is distinct from pg_temp.dni(42) || '|convertido|false|true' then
    raise exception 'ENSAYO ABORTADO: D2: el verificador no dice «libre», el teléfono ya existe o el cliente no es un retirado sin persona con ese DNI';
  end if;
  perform pg_temp.no_entra('D2-telefono-libre-y-dni-de-un-cliente-retirado-sin-persona (el resultado de B8, como hoy)', v_sup1, v_bs,
    pg_temp.teln(342), pg_temp.dni(42), pg_temp.esp('retirado', null), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- L. UN LOTE MIXTO (la tanda del INSERT): L1 fila 1 libre · fila 2 el alternativo de un cliente · fila 3 el alternativo de un lead
  --    que no es cliente ⇒ cargada · ya_existia (convertido, con su id) · cargada; el lote cuenta 2 y 1; nacen los dos dormidos y
  --    ninguno con el alternativo del cliente.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(51, 'CLIENTE L1', v_vend1, false, pg_temp.teln(351));
  v_l := pg_temp.lead_nuevo(v_vend1, 52, 'LEAD L1 VIVO CON ALTERNATIVO', null, pg_temp.teln(352));
  perform pg_temp.exigir_carga_hoy('L1 (2)', pg_temp.teln(351), null);
  perform pg_temp.exigir_carga_hoy('L1 (3)', pg_temp.teln(352), null);
  perform pg_temp.exigir_carga_hoy('L1 (1)', pg_temp.teln(353), null);
  v_res := pg_temp.cargar(v_sup1, v_bs, jsonb_build_array(
    jsonb_build_object('fila', 1, 'nombre', 'CONTACTO L1 LIBRE', 'telefono', pg_temp.teln(353)),
    jsonb_build_object('fila', 2, 'nombre', 'CONTACTO L1 DEL CLIENTE', 'telefono', pg_temp.teln(351)),
    jsonb_build_object('fila', 3, 'nombre', 'CONTACTO L1 DEL NO CLIENTE', 'telefono', pg_temp.teln(352))));
  perform pg_temp.medida(format('L1 · lote mixto → %s', v_res));
  v_txt := '';
  if v_res not like 'ok|%' then
    v_txt := format('la carga falló (%s)', v_res);
  else
    v_r := substr(v_res, 4)::jsonb;
    if (select jsonb_agg(x - 'fila' order by (x ->> 'fila')::int) from jsonb_array_elements(v_r -> 'filas') x)
       is distinct from jsonb_build_array('{"veredicto": "cargada"}'::jsonb, pg_temp.esp('convertido', v_c), '{"veredicto": "cargada"}'::jsonb) then
      v_txt := format('las filas respondieron %s, se esperaba [cargada, %s, cargada]', v_r -> 'filas', pg_temp.esp('convertido', v_c));
      if (v_r #>> '{filas,1,veredicto}') = 'cargada' then
        v_txt := v_txt || ' → la fila 2 ENTRÓ como contacto dormido con el alternativo de un cliente ya convertido';
      end if;
    elsif (v_r #>> '{lote,cargadas}') is distinct from '2' or (v_r #>> '{lote,ya_existian}') is distinct from '1' then
      v_txt := format('conteos del lote %s (se esperaban 2 cargadas y 1 ya_existia)', v_r -> 'lote');
    elsif (select count(*) from crm.leads l where l.telefono in (pg_temp.teln(352), pg_temp.teln(353)) and l.origen = 'base_cargada') <> 2
       or exists (select 1 from crm.leads l where l.telefono = pg_temp.teln(351)) then
      v_txt := 'no nacieron exactamente los dos contactos dormidos esperados (o nació uno con el alternativo del cliente)';
    end if;
  end if;
  perform pg_temp.reg('L1-lote-mixto (libre, alternativo de un cliente, alternativo de un no cliente)',
    case when v_txt = '' then '' else format(E'FALLO L1-lote-mixto: %s\n', v_txt) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- S. LO QUE NO ES CARGA DE BASES NO CAMBIA: S1 el importador (`crm.importar_lead_fn`, sin sesión: su contrato es NO consultar la
  --    disponibilidad comercial, H-3 del 2.8) con el alternativo de un cliente ⇒ `importado`, como hoy.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(61, 'CLIENTE S1', v_vend1, false, pg_temp.teln(361));
  perform pg_temp.sesion(null);
  begin
    v_r := crm.importar_lead_fn(jsonb_build_object('nombre_completo', 'IMPORTADO S1', 'telefono', pg_temp.tel(361), 'origen', 'landing',
                                                   'monto_estimado', '3000', 'moneda', 'PEN'));
    v_res := 'ok|' || v_r::text;
  exception when others then
    v_res := sqlstate || '|' || sqlerrm;
  end;
  perform pg_temp.medida(format('S1 · importador sin sesión con el alternativo de un cliente → %s', v_res));
  perform pg_temp.reg('S1-importador-sin-sesion-con-el-alternativo-de-un-cliente (importado como hoy)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'resultado') = 'importado' then ''
         else format(E'FALLO S1-importador-sin-sesion-con-el-alternativo-de-un-cliente: se esperaba «importado» (hoy) y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- H. MEDIDA (hallazgo, no arreglo: otra puerta, que D-37 no cubre). H1 un contacto de base que se cargó cuando su teléfono era
  --    libre y que DESPUÉS resulta ser el alternativo de un cliente (el alternativo se le puso al cliente más tarde: la dirección de
  --    D-49, bloque 2.13) se REACTIVA por la puerta de la base para gestión (`crm.reactivar_lead_base_v2`, con capital) ⇒ ¿vuelve
  --    activo con el teléfono del cliente? (hipótesis H-2 del 2.8). Lo mismo con y sin la migración: el 2.9 no toca la reactivación.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_res := pg_temp.cargar(v_sup1, v_bs, jsonb_build_array(jsonb_build_object('fila', 1, 'nombre', 'CONTACTO H1 CARGADO ANTES',
                                                                             'telefono', pg_temp.teln(371))));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb #>> '{filas,0,veredicto}') is distinct from 'cargada' then
    raise exception 'ENSAYO ABORTADO: H1: el contacto libre no se cargó (%)', v_res;
  end if;
  v_l := (select l.id from crm.leads l where l.telefono = pg_temp.teln(371));
  v_c := pg_temp.cliente_sin_persona(72, 'CLIENTE H1 CON ALTERNATIVO PUESTO DESPUES', v_vend1, false, pg_temp.teln(371));
  begin
    perform pg_temp.sesion(v_sup1);
    v_r := crm.reactivar_lead_base_v2(gen_random_uuid(), v_l, 'medida del bloque 2.9', 5000, 'PEN');
    perform pg_temp.sesion(null);
    v_res := 'ok|' || v_r::text;
  exception when others then
    perform pg_temp.sesion(null);
    v_res := sqlstate || '|' || sqlerrm;
  end;
  perform pg_temp.medida(format('H1 · reactivar (SUP1, crm.reactivar_lead_base_v2) un contacto de base cuyo teléfono resultó ser el alternativo de un cliente → %s · el contacto queda %s',
    v_res, (select jsonb_build_object('etapa', l.etapa, 'activo', l.activo, 'es_el_alternativo_del_cliente',
                                      l.telefono = (select c.telefono_alternativo from crm.leads c where c.id = v_c))
              from crm.leads l where l.id = v_l)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C. CATÁLOGO. C1 el envoltorio sigue siendo INVOKER de postgres, STABLE, con `search_path` vacío y nada más, EXECUTE solo para
  --    postgres · C2 sus dos llamadores, la puerta y lo que decide su efecto, intactos (definición, dueño, ACL; ronda 2: también el
  --    verificador de 3 argumentos, al que delega el de 2, la cadena del ámbito —`vendedor_ids_visibles`, `es_lector_global`,
  --    `rol_crm`— y la función del candado de contacto) · C3 los CONSUMIDORES (ronda 2): del envoltorio solo el núcleo y la regla del
  --    ámbito; de la regla del ámbito solo el núcleo; del núcleo solo la puerta (referencias LITERALES en los cuerpos, sin distinguir
  --    mayúsculas; dependencias registradas en pg_depend; cron.job visible; el SQL dinámico no se ve) · C4 el CHECK del formato del
  --    alternativo (la premisa de la comparación literal), intacto · C5 (ronda 2) el candado de contacto del 2.8 r4: el disparador de
  --    disponibilidad lo toma con el alternativo viejo y nuevo (UPDATE) y con el alternativo (INSERT), y sus dos disparadores de tabla
  --    están habilitados (el de la edición, con el alternativo en su lista).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if not exists (select 1 from pg_proc p where p.oid = v_env and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_env)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_env, 'EXECUTE') or has_function_privilege('authenticated', v_env, 'EXECUTE')
     or has_function_privilege('service_role', v_env, 'EXECUTE') then
    perform pg_temp.reg('C1', E'FALLO C1: private.bases_carga_contacto_existente no es INVOKER de postgres, STABLE, con search_path vacío y EXECUTE solo para postgres\n');
  else
    perform pg_temp.reg('C1 private.bases_carga_contacto_existente: ficha y ACL', '');
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_txt
  from (values
    ('crm.cargar_base_lote(uuid,uuid,jsonb)', 'b03d2e9d4500ca54fb8aec014786653a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'e5f25344437c0c54b289d4ae294b5e39', 'postgres:EXECUTE:false'),
    ('private.bases_carga_fuera_de_ambito(uuid,text,text,text)', '7341099506af3a2f2af3eeb9ec0862e4', 'postgres:EXECUTE:false'),
    ('private.bases_carga_lead_ref(uuid,text,uuid)', 'db760dd5ae42b06a886b9420fa927be8', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.es_lector_global()', 'c8be602f84348a0125617995802db618', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  perform pg_temp.reg('C2 llamadores, puerta y dependencias intactos (definición, dueño, ACL)',
    case when v_txt is null then '' else format(E'FALLO C2: cambió algo que el 2.9 no toca: %s\n', v_txt) end);
  select string_agg(x.f, ', ' order by x.f) into v_txt
  from (select p.oid::regprocedure::text || ' → ' || o.nombre as f
          from (values ('bases_carga_contacto_existente', array[v_env::oid, v_nucleo::oid, v_ambito::oid]),
                       ('bases_carga_fuera_de_ambito', array[v_ambito::oid, v_nucleo::oid]),
                       ('bases_carga_cargar_lote_core', array[v_nucleo::oid, v_puerta::oid])) o(nombre, permitidos)
          join pg_proc p on strpos(lower(coalesce(p.prosrc, '')), o.nombre) > 0
         where p.oid <> all (o.permitidos)
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid) || ' → ' || d.refobjid::regprocedure::text
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_env, v_ambito, v_nucleo)) x;
  if to_regclass('cron.job') is not null then
    execute $cron$select string_agg('cron.job ' || j.jobid::text, ', ' order by j.jobid) from cron.job j
                   where strpos(lower(coalesce(j.command, '')), 'bases_carga_contacto_existente') > 0
                      or strpos(lower(coalesce(j.command, '')), 'bases_carga_fuera_de_ambito') > 0
                      or strpos(lower(coalesce(j.command, '')), 'bases_carga_cargar_lote_core') > 0$cron$ into v_r2;
    v_txt := nullif(concat_ws(', ', v_txt, v_r2), '');
  end if;
  perform pg_temp.reg('C3 consumidores: del envoltorio, el núcleo y el ámbito; del ámbito, el núcleo; del núcleo, la puerta',
    case when v_txt is null then '' else format(E'FALLO C3: otros consumen el envoltorio, el ámbito o el núcleo (el cambio los alcanzaría): %s\n', v_txt) end);
  perform pg_temp.reg('C4 el CHECK leads_telefono_alternativo_formato, intacto y validado',
    case when (select md5(pg_get_constraintdef(c.oid)) || '|' || c.convalidated::text from pg_constraint c
                where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_telefono_alternativo_formato')
              = '4ce894b3dc052735877c5e1ae07b3219|true' then ''
         else E'FALLO C4: el CHECK leads_telefono_alternativo_formato cambió (la comparación literal dejaría de valer)\n' end);
  -- C5 (ronda 2; Codex P2-1, auditor P3-2): el candado de contacto del 2.8 r4 del que depende el ORDEN entre una carga y quien pone ese
  --    número como alternativo de un cliente (o convierte un lead que lo tiene): la función del candado (en C2), el disparador que la
  --    llama con el alternativo (UPDATE: viejo y nuevo; INSERT) y sus dos disparadores de tabla habilitados. No prueba concurrencia.
  perform pg_temp.reg('C5 el candado de contacto del 2.8 r4: el disparador con el alternativo y sus disparadores de tabla habilitados',
    case when (select p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and (length(p.prosrc) - length(replace(p.prosrc, E'    perform private.bloquear_contactos_lead(\n      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],\n      array[old.dni, new.dni]\n    );\n', '')))
                          / length(E'    perform private.bloquear_contactos_lead(\n      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],\n      array[old.dni, new.dni]\n    );\n') = 1
                      and (length(p.prosrc) - length(replace(p.prosrc, E'  perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);\n', '')))
                          / length(E'  perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);\n') = 1
                 from pg_proc p where p.oid = v_disp) is true
              and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert'
                            and t.tgfoid = v_disp and t.tgenabled = 'O' and t.tgtype = 7)
              and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'
                            and t.tgfoid = v_disp and t.tgenabled = 'O' and t.tgtype = 19
                            and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = t.tgrelid and a.attnum = any (t.tgattr::int2[]))
                                @> array['activo', 'dni', 'etapa', 'telefono', 'telefono_alternativo'])
         then '' else E'FALLO C5: falta el candado de contacto del 2.8 r4 (el disparador sin el alternativo en su candado, o un disparador de tabla deshabilitado o sin el alternativo)\n' end);
  perform pg_temp.medida(format('C6 huellas al final: envoltorio md5(prosrc)=%s · md5(definición)=%s · md5(comentario)=%s',
    (select md5(p.prosrc) from pg_proc p where p.oid = v_env), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_env),
    (select md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) from pg_proc p where p.oid = v_env)));

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
