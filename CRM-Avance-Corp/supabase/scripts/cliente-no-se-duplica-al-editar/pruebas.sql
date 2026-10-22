-- ORÁCULO de «El cliente ya convertido tampoco se duplica al editar un lead ni por su teléfono alternativo» — se ejecuta en el
-- LABORATORIO (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisiones D-28 y D-30 de Miguel, 08/10/2026; plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.8), sobre la del bloque 2.7
-- (D-22, D-25, D-27): el teléfono, el teléfono ALTERNATIVO o el DNI de un cliente ya convertido (su lead está `convertido`, activo
-- o retirado) no pueden acabar en OTRO lead:
--   · EDICIÓN desde la ficha (`crm.editar_lead_fn`, y el DNI por su puerta `crm.fijar_dni_lead_fn`): poner a un lead el teléfono,
--     el alternativo o el DNI de un cliente ⇒ se rechaza con el MISMO `P0481` «Contacto no disponible» de hoy y el veredicto
--     «ya es cliente» (el de la regla del 2.7) en el detalle; no se guarda nada. Se juzga LO QUE LA EDICIÓN PONE (los valores que
--     cambian), no lo que el lead ya tenía: una edición que no toca teléfono, alternativo ni DNI —o que los deja como estaban—
--     sigue como hoy, también en los dos leads que YA comparten teléfono con un cliente (D-23/D-25: se dejan).
--   · INSERT con sesión en `crm.leads` (el directo, si alguna vez se concediera, o cualquier puerta que no sea el alta): la misma
--     regla, con todo lo tecleado.
--   · ALTA (`crm.crear_lead_si_disponible`, núcleo `private.alta_reactivar_retirado` del 2.4 + 2.7): la misma regla, ahora con el
--     alternativo.
--   · El ALTERNATIVO cuenta en las DOS direcciones (D-30): lo tecleado (principal o alternativo) contra los dos teléfonos de cada
--     cliente. Precedencia: el teléfono (principal antes que alternativo, lo tecleado principal primero) → el DNI; entre varios
--     convertidos, enlazado a persona → activo → más reciente (la del 2.7).
--   · NO CAMBIA: la carga de bases (su contacto dormido nace por su válvula), lo que corre sin sesión (el importador, cualquier
--     escritura sin usuario), el DNI que se escribe bajo la válvula `crm.op_privilegiada` (la conversión y la corrección de
--     documento: D-38; desde la ronda 3, bajo la válvula SÍ se juzgan el teléfono y el alternativo), los veredictos que el
--     disparador ya daba (veto, enfriamiento, lead vivo: van antes que la regla) y los roles (quien no puede, 42501; nunca ve el
--     veredicto). Lo que SÍ cambia de código, medido: el UPDATE directo del DNI hacia un cliente responde el P0481 de la regla
--     antes que el P0409 de la identidad (H-7); con la identidad encendida, la puerta del DNI decide a qué cliente se nombra
--     (medida E7l); un alternativo con espacios alrededor del teléfono de un cliente pasa del 23514 de formato al P0481 (E8l).
-- Hoy (sin la migración), la edición pasa solo por el disparador `private.trg_leads_disponibilidad_atomica`, que pregunta al
-- verificador sellado; el verificador excluye las fichas convertidas y no mira el alternativo, y el disparador ni siquiera se
-- dispara si solo cambia el alternativo ⇒ se acepta: un SEGUNDO lead del cliente. Lo mismo el INSERT con sesión y el alta con el
-- alternativo de un cliente.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (sin su `begin;`/`commit;`) dentro de
-- una única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y entonces TIENE que salir ROJO porque la
-- edición (o el INSERT, o el alta con el alternativo) deja un SEGUNDO lead del cliente, nunca por un error de montaje.
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT, fijada en las DOS formas
-- (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de rol con `set role` (llamar bajo `set role` a una función sin
-- EXECUTE tumba el Postgres del banco): todo corre como `postgres`, así que la RLS y los permisos por columna NO se ensayan aquí
-- (se leen del catálogo, sección C; la parte HTTP es de la ronda del banco). Actores reales del banco (`PASO08 …`), OBLIGATORIOS
-- con su rol exacto: sin ellos, `ENSAYO ABORTADO`.
--
-- Cómo nacen los clientes (como en el oráculo del 2.7):
--   · CON PERSONA: por la PUERTA REAL del formulario compartido (alta → persona → solicitud `prodelco`, cooperativa, sin cuenta del
--     Portal → comprobante sintético → confirmar). Con alternativo, el alta lleva `p_telefono_alternativo`.
--   · SIN PERSONA (convertidos heredados): alta real y conversión sembrada con los disparadores apagados.
--   · Duplicados heredados, convertidos con id o fecha fijos (desempates) y la persona vetada o fusionada: sembrados con los
--     disparadores apagados (estado heredado declarado en cada caso).
--
-- RONDA 3 (09/10/2026; revisiones del auditor de permisos y de Codex, `fase-2/bloque-2.8/revision/CONCILIACION.md`):
--   · F. El teléfono alternativo SIN VALIDAR (`telefono_alternativo_crudo`; solo lo escribe la importación, sin sesión): con sesión
--     —también bajo cualquier válvula— no se pone al nacer (INSERT) ni cambia a un valor no nulo (UPDATE, también cuando el SET solo
--     lo trae a él) ⇒ 42501 «El alternativo sin validar solo lo pone la importación». Conservar el heredado y borrarlo (NULL),
--     como hoy; sin sesión, como hoy.
--   · V. Bajo la válvula privilegiada se juzgan el teléfono y el alternativo; solo el DNI queda fuera (hasta D-38). La salida de la
--     corrección de documento (`crm.correccion_documento`) solo vale si cambia únicamente el DNI.
--   · E8. Los huecos: principal libre + alternativo de un cliente en el mismo UPDATE; desempate final por id (teléfono y DNI); el
--     propio lead excluido en la rama del alternativo; `crm.editar_lead_documento_fn` real (DNI, CE y pasaporte) y su atomicidad;
--     alternativos internacionales y fijos, formato inválido y con espacios (este, medido).
--   · A7/A8. El alta reconoce el fijo y el internacional de un cliente tecleados en otra forma (los canoniza antes de juzgar).
--   · R. El reintento del 2.4 con precondiciones que distinguen conservar de reescribir el alternativo, y MEDIDAS (sin arreglar:
--     D-25) de la reactivación de un retirado cuyo teléfono o alternativo CONSERVADO es de un cliente.
--
-- RONDA 4 (09/10/2026; Codex r2 y auditor de permisos r2, `fase-2/bloque-2.8/revision/CONCILIACION.md`):
--   · K. Las CLAVES DE CANDADO que pide el disparador (auditor P3-4): con la migración, el alternativo viejo y el nuevo (UPDATE) y el
--     alternativo (INSERT) entran en el candado de contacto con la MISMA clave que el teléfono principal para el mismo número
--     (`telefono:` + la forma de `private.normalizar_telefono`). Se leen en `pg_locks` dentro de una subtransacción que se deshace.
--     La espera real entre dos sesiones se ensaya aparte, con dos conexiones (`espera.sh`).
--   · E8g2 comprueba el enlace lead ↔ persona ↔ identificador PASAPORTE / E8G2X92408 (Codex R2-F2); E8l exige el P0481 del cliente con
--     la migración (sin ella, el 23514 de hoy); F2, F3a, F3b, F4 y F7u1–F7u4 usan cada uno su lead y afirman su estado inicial: en
--     ROJO cada uno es un cambio real a no nulo (o una conservación real), no un reenvío sobre lo que aceptó el caso anterior.

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

-- Contactos del ensayo: un bloque propio (+51 924 08xxxx / 7528xxxx) que el montaje exige LIBRE (el del 2.7 es 92407/7527; el
-- del 2.4, 92400/7524).
create function pg_temp.tel(n integer) returns text language sql immutable as $$ select '92408' || lpad(n::text, 4, '0') $$;
create function pg_temp.teln(n integer) returns text language sql immutable as $$ select '+51' || pg_temp.tel(n) $$;
create function pg_temp.dni(n integer) returns text language sql immutable as $$ select '7528' || lpad(n::text, 4, '0') $$;

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

-- Huella de ESCRITURA (la del oráculo del 2.7): el contenido entero de crm.leads, crm.actividades y crm.lead_asignaciones (md5
-- de las filas en orden de id) y el número de filas de tareas, personas, documentos y ciclos SLA.
create function pg_temp.huella_escritura() returns text language sql as $$
  select concat_ws(',',
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '')) from crm.leads l),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from crm.actividades a),
    (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) from crm.lead_asignaciones e),
    (select count(*) from crm.tareas), (select count(*) from crm.inversionistas), (select count(*) from crm.inversionista_identificadores),
    (select count(*) from crm.lead_sla_ciclos))
$$;

-- Cuántos OTROS leads llevan alguno de los contactos del cliente (su teléfono, su alternativo —en cualquiera de los dos campos y,
-- desde la ronda 3, también en el alternativo SIN VALIDAR, normalizado— o su DNI). Es el «segundo lead del cliente» que mide el ROJO.
create function pg_temp.otros_del_cliente(p_cliente uuid) returns bigint language sql as $$
  select count(*)
  from crm.leads c
  join crm.leads l on l.id <> c.id
  where c.id = p_cliente
    and (l.telefono = c.telefono or l.telefono = c.telefono_alternativo
         or l.telefono_alternativo = c.telefono or l.telefono_alternativo = c.telefono_alternativo
         or private.normalizar_telefono(l.telefono_alternativo_crudo) in (c.telefono, c.telefono_alternativo)
         or (c.dni is not null and l.dni = c.dni))
$$;

-- Lo mismo, contando solo los leads ACTIVOS (las medidas R2/R3: el retirado ya contaba antes de reactivarse).
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

-- Alta por la puerta real (con el alternativo, D-30).
create function pg_temp.alta(p_actor uuid, p_id uuid, p_nombre text, p_tel text, p_dni text, p_alt text default null,
                             p_vendedor uuid default null)
returns text language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.crear_lead_si_disponible(
    p_nombre_completo => p_nombre, p_telefono => p_tel, p_origen => 'formulario', p_monto_estimado => 5000,
    p_moneda => 'PEN', p_id => p_id, p_dni => p_dni, p_vendedor_id => p_vendedor, p_telefono_alternativo => p_alt);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- La EDICIÓN desde la ficha: `crm.editar_lead_fn` (con la identidad encendida, el DNI pasa antes por `crm.fijar_dni_lead_fn`).
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

-- INSERT en crm.leads CON SESIÓN que no es el alta (el «INSERT directo» de D-30 si se concediera; aquí corre como postgres con
-- los claims del actor, que es lo único que mira el disparador): el mismo INSERT que hace el alta, sin su núcleo. Con p_actor
-- nulo, sin sesión. Ronda 3: con el alternativo SIN VALIDAR (p_crudo) y, si se piden, las válvulas de transacción encendidas
-- alrededor del INSERT (p_valvulas: `crm.op_privilegiada`, `crm.correccion_documento`, `crm.dni_por_puerta`, `crm.op_bases_carga`).
create function pg_temp.insertar(p_actor uuid, p_id uuid, p_nombre text, p_tel text, p_alt text, p_dni text,
                                 p_crudo text default null, p_valvulas text[] default '{}')
returns text language plpgsql as $f$
declare v_det text; v_v text;
begin
  perform pg_temp.sesion(p_actor);
  foreach v_v in array coalesce(p_valvulas, '{}'::text[]) loop
    perform set_config(v_v, 'on', true);
  end loop;
  insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, telefono_alternativo_crudo, dni, origen, etapa,
                         monto_estimado, moneda, vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual)
  values (p_id, p_nombre, p_tel, p_alt, p_crudo, p_dni, 'formulario', 'nuevo', 5000, 'PEN', p_actor, null, true, p_actor, true);
  foreach v_v in array coalesce(p_valvulas, '{}'::text[]) loop
    perform set_config(v_v, 'off', true);
  end loop;
  perform pg_temp.sesion(null);
  return 'ok|' || p_id::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  foreach v_v in array coalesce(p_valvulas, '{}'::text[]) loop
    perform set_config(v_v, 'off', true);
  end loop;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- UPDATE directo (sin la ficha), con o sin sesión: un SET dinámico con SOLO las columnas que trae p_set (así un caso prueba también
-- la lista de columnas del disparador de tabla: ronda 3, Codex F1) y, si se piden, las válvulas de transacción encendidas
-- alrededor del UPDATE (p_valvulas: `crm.op_privilegiada`, `crm.correccion_documento`, `crm.dni_por_puerta`, `crm.op_bases_carga`),
-- como lo hacen las puertas que las usan. 'ok|<filas>' o 'SQLSTATE|mensaje|detalle'.
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
-- La forma de la ronda 1 (S2, S3, P1): sin válvulas o solo con la privilegiada.
create function pg_temp.actualizar(p_actor uuid, p_lead uuid, p_set jsonb, p_privilegiada boolean) returns text
language sql as $$
  select pg_temp.actualizar_v(p_actor, p_lead, p_set, case when p_privilegiada then array['crm.op_privilegiada'] else '{}'::text[] end)
$$;

-- La EDICIÓN CON DOCUMENTO de la ficha (`crm.editar_lead_documento_fn`, INVOKER): primero el documento por su puerta
-- (`crm.fijar_documento_lead_fn`: el DNI por `crm.fijar_dni_lead_fn`; CE o pasaporte, una persona enlazada bajo la válvula
-- privilegiada) y DESPUÉS el resto de la ficha por `crm.editar_lead_fn`, en la MISMA llamada: si el resto se rechaza, el documento
-- tampoco queda (ronda 3: la atomicidad que pidió Codex).
create function pg_temp.editar_doc(p_actor uuid, p_lead uuid, p_cambios jsonb, p_tipo text, p_documento text) returns text
language plpgsql as $f$
declare v_r jsonb; v_det text;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.editar_lead_documento_fn(p_lead, p_cambios, p_tipo, p_documento, null, null);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_det, '');
end;
$f$;

-- Un lead ENLAZADO a su persona (la forma que exige la salida de la corrección de documento): nace por la puerta real con su DNI y
-- se enlaza a la persona de ese DNI con los disparadores apagados (estado heredado declarado: así lo dejan la conversión y la toma).
create function pg_temp.lead_enlazado(p_actor uuid, p_n integer, p_nombre text) returns uuid language plpgsql as $f$
declare v_id uuid := pg_temp.lead_nuevo(p_actor, p_n, p_nombre, pg_temp.dni(p_n)); v_per uuid;
begin
  v_per := private.inversionista_resolver('DNI', pg_temp.dni(p_n), true, 'ensayo-bloque-2.8');
  if v_per is null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear la persona del lead enlazado %', p_n;
  end if;
  set local session_replication_role = replica;
  update crm.leads set inversionista_id = v_per where id = v_id;
  set local session_replication_role = origin;
  if (select l.inversionista_id from crm.leads l where l.id = v_id) is distinct from v_per then
    raise exception 'ENSAYO ABORTADO: el lead % no quedó enlazado a su persona', p_n;
  end if;
  return v_id;
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

-- Apagar o encender la identidad unificada DENTRO de esta transacción (como 5b/11c del 2.7).
create function pg_temp.bandera(p_activa boolean) returns void language plpgsql as $f$
begin
  perform pg_temp.sesion(pg_temp.actor('GERENCIA'));
  update crm.multiempresa_flags set activo = p_activa where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if private.resolver_en_puertas_bajo_candado() is distinct from p_activa then
    raise exception 'ENSAYO ABORTADO: no se pudo % la bandera resolver_en_puertas dentro del ensayo', case when p_activa then 'encender' else 'apagar' end;
  end if;
end;
$f$;

-- ── Montaje de clientes y leads ─────────────────────────────────────────────────────────────────────────────────────

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

-- CLIENTE CON PERSONA por la conversión REAL (formulario compartido, cooperativa: sin cuenta del Portal). Con p_alt, el alta
-- lleva ese teléfono alternativo. Devuelve el id del lead convertido (activo, enlazado a su persona).
create function pg_temp.convertir_real(p_n integer, p_nombre text, p_actor uuid default null, p_alt text default null)
returns uuid language plpgsql as $f$
declare
  v_actor uuid := coalesce(p_actor, pg_temp.actor('VEND1'));
  v_lead uuid := gen_random_uuid(); v_res text; v_r jsonb; v_per uuid; v_sol uuid := gen_random_uuid(); v_ruta text;
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
begin
  v_res := pg_temp.alta(v_actor, v_lead, p_nombre, pg_temp.tel(p_n), pg_temp.dni(p_n), p_alt);
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
             'plazo_meses', 12, 'tasa_anual', 15, 'numero_transaccion', 'ENS28-' || left(v_sol::text, 8),
             'referencia', 'ENSAYO 2.8 SINTETICA', 'evidencia', jsonb_build_object('ruta', v_ruta)));
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
     or (select l.etapa <> 'convertido' or not l.activo or l.inversionista_id is distinct from v_per from crm.leads l where l.id = v_lead)
     or (select l.telefono_alternativo from crm.leads l where l.id = v_lead) is distinct from p_alt then
    raise exception 'ENSAYO ABORTADO: el cliente % no quedó convertido, activo, enlazado a su persona y con el alternativo pedido (%)', p_n, v_r;
  end if;
  if (select i.perfil_id from crm.inversionistas i where i.id = v_per) is not null
     or exists (select 1 from public.perfiles p where p.rol = 'cliente' and private.normalizar_telefono(p.telefono) = pg_temp.teln(p_n)) then
    raise exception 'ENSAYO ABORTADO: el cliente % tiene cuenta del Portal (el caso exige que no la tenga)', p_n;
  end if;
  return v_lead;
end;
$f$;

-- CONVERSIÓN SEMBRADA (sin persona, estado heredado) de un lead nacido por la puerta real, como 3d/B1 del 2.4 y 4a del 2.7.
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

-- CLIENTE SIN PERSONA: alta real a nombre de p_actor (o en la cola global si p_actor es Gerencia y p_cola), con su DNI si p_con_dni
-- y el alternativo p_alt, y conversión sembrada (retirado si p_retirar). Exige que no quede enlazado a ninguna persona.
create function pg_temp.cliente_sin_persona(p_n integer, p_nombre text, p_actor uuid, p_retirar boolean,
                                            p_alt text default null, p_con_dni boolean default true)
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_res text;
begin
  v_res := pg_temp.alta(p_actor, v_id, p_nombre, pg_temp.tel(p_n), case when p_con_dni then pg_temp.dni(p_n) end, p_alt);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado'
     or (select l.inversionista_id from crm.leads l where l.id = v_id) is not null then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del cliente sin persona % (%)', p_n, v_res;
  end if;
  perform pg_temp.convertir_sembrado(v_id, p_retirar);
  return v_id;
end;
$f$;

-- Un lead SEMBRADO sin disparadores (estado heredado: duplicado del mismo teléfono, convertido sin persona con fecha o id fijos),
-- con su ciclo SLA como lo dejaría el alta. p_etapa 'contactado' | 'convertido' (sin persona, con p_convertido_en o hace 5 días; sin
-- fecha si p_convertido_en_nulo). Dueño: p_vendedor (VEND1 si no se da). p_alt: su teléfono alternativo.
create function pg_temp.sembrado(p_n integer, p_nombre text, p_activo boolean, p_etapa text default 'contactado',
                                 p_dni text default null, p_vendedor uuid default null, p_convertido_en timestamptz default null,
                                 p_id uuid default null, p_convertido_en_nulo boolean default false, p_alt text default null)
returns uuid language plpgsql as $f$
declare v_id uuid := coalesce(p_id, gen_random_uuid()); v_dueno uuid := coalesce(p_vendedor, pg_temp.actor('VEND1'));
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, dni, origen, etapa, convertido_en, monto_estimado, moneda,
                         vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual, ciclo_actual, creado_en, actualizado_en,
                         sla_global_iniciado_en)
  values (v_id, p_nombre, pg_temp.teln(p_n), p_alt, p_dni, 'formulario', p_etapa,
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

-- ── Jueces ──────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Lo que debe cumplir una escritura RECHAZADA: el error EXACTO (`p_esperado`: {"error": SQLSTATE, "detalle": <veredicto exacto>,
-- "mensaje": <texto que debe contener>}), el lead (si existía) intacto byte a byte, el cliente y su persona intactos, ninguna
-- escritura (huella) y ningún lead más con los contactos del cliente. Si la escritura se ACEPTÓ, el fallo dice el defecto: nació
-- un segundo lead del cliente. Devuelve '' o la línea FALLO.
create function pg_temp.juzgar_rechazo(p_caso text, p_via text, p_res text, p_esperado jsonb, p_lead uuid, p_lead_antes jsonb,
                                       p_cliente uuid, p_cliente_antes jsonb, p_persona uuid, p_persona_antes jsonb,
                                       p_huella text, p_otros bigint)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; e record; v_otros bigint := pg_temp.otros_del_cliente(p_cliente);
begin
  if p_res like 'ok|%' then
    return format(E'FALLO %s: %s se ACEPTÓ (%s) → nació un SEGUNDO lead del cliente: %s lead(s) más con su teléfono, su alternativo (también el sin validar) o su DNI (había %s)\n',
      p_caso, p_via, substr(p_res, 4), v_otros, p_otros);
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
  end if;
  if p_lead is not null and pg_temp.ficha(p_lead) is distinct from p_lead_antes then
    v_m := array_append(v_m, 'el lead que se escribía cambió (o nació)');
  end if;
  if pg_temp.ficha(p_cliente) is distinct from p_cliente_antes then
    v_m := array_append(v_m, 'la ficha del cliente cambió');
  end if;
  if p_persona is not null and pg_temp.persona(p_persona) is distinct from p_persona_antes then
    v_m := array_append(v_m, 'la persona del cliente cambió');
  end if;
  if pg_temp.huella_escritura() is distinct from p_huella then
    v_m := array_append(v_m, format('se escribió algo (leads:md5, actividades:md5, episodios:md5, tareas, personas, documentos, ciclos: %s → %s)',
      p_huella, pg_temp.huella_escritura()));
  end if;
  if v_otros <> p_otros then
    v_m := array_append(v_m, format('%s lead(s) más con los contactos del cliente (había %s)', v_otros, p_otros));
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- La EDICIÓN que tiene que RECHAZARSE (el lead y el cliente se fotografían aquí, justo antes).
create function pg_temp.rechazo_edicion(p_caso text, p_actor uuid, p_lead uuid, p_cambios jsonb, p_esperado jsonb, p_cliente uuid)
returns void language plpgsql as $f$
declare
  v_per uuid := (select l.inversionista_id from crm.leads l where l.id = p_cliente);
  v_ficha jsonb := pg_temp.ficha(p_lead); v_fc jsonb := pg_temp.ficha(p_cliente); v_pers jsonb := pg_temp.persona(v_per);
  v_huella text := pg_temp.huella_escritura(); v_otros bigint := pg_temp.otros_del_cliente(p_cliente); v_res text;
begin
  v_res := pg_temp.editar(p_actor, p_lead, p_cambios);
  perform pg_temp.medida(format('%s · edición %s → %s', p_caso, p_cambios::text, v_res));
  perform pg_temp.reg(p_caso, pg_temp.juzgar_rechazo(p_caso, 'la edición', v_res, p_esperado, p_lead, v_ficha, p_cliente, v_fc,
                                                     v_per, v_pers, v_huella, v_otros));
end;
$f$;

-- La EDICIÓN que tiene que GUARDARSE como hoy: respuesta ok y el lead con cada valor esperado (ya normalizado).
create function pg_temp.ok_edicion(p_caso text, p_actor uuid, p_lead uuid, p_cambios jsonb, p_campos jsonb)
returns void language plpgsql as $f$
declare v_res text; v_k text; v_m text[] := '{}'; v_f jsonb;
begin
  v_res := pg_temp.editar(p_actor, p_lead, p_cambios);
  perform pg_temp.medida(format('%s · edición %s → %s', p_caso, p_cambios::text, v_res));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la edición se RECHAZÓ (%s) y hoy se guarda: la regla bloquea una edición que no pone el contacto de ningún cliente\n', p_caso, v_res));
    return;
  end if;
  v_f := pg_temp.ficha(p_lead);
  for v_k in select jsonb_object_keys(p_campos) loop
    if (v_f ->> v_k) is distinct from (p_campos ->> v_k) then
      v_m := array_append(v_m, format('%s = %s (se esperaba %s)', v_k, coalesce(v_f ->> v_k, 'null'), coalesce(p_campos ->> v_k, 'null')));
    end if;
  end loop;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: se guardó otra cosa: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- El INSERT con sesión que tiene que RECHAZARSE (ronda 3: también con el alternativo sin validar y bajo válvulas).
create function pg_temp.rechazo_insert(p_caso text, p_actor uuid, p_tel text, p_alt text, p_dni text, p_esperado jsonb, p_cliente uuid,
                                       p_crudo text default null, p_valvulas text[] default '{}')
returns void language plpgsql as $f$
declare
  v_id uuid := gen_random_uuid(); v_per uuid := (select l.inversionista_id from crm.leads l where l.id = p_cliente);
  v_fc jsonb := pg_temp.ficha(p_cliente); v_pers jsonb := pg_temp.persona(v_per);
  v_huella text := pg_temp.huella_escritura(); v_otros bigint := pg_temp.otros_del_cliente(p_cliente); v_res text;
begin
  v_res := pg_temp.insertar(p_actor, v_id, 'INSERT CON SESION ' || p_caso, p_tel, p_alt, p_dni, p_crudo, p_valvulas);
  perform pg_temp.medida(format('%s · INSERT con sesión (teléfono %s, alternativo %s, sin validar %s, DNI %s, válvulas %s) → %s', p_caso, p_tel,
    coalesce(p_alt, '-'), coalesce(p_crudo, '-'), coalesce(p_dni, '-'), coalesce(nullif(array_to_string(p_valvulas, '+'), ''), '-'), v_res));
  perform pg_temp.reg(p_caso, pg_temp.juzgar_rechazo(p_caso, 'el INSERT con sesión' || case when cardinality(p_valvulas) > 0
                                                     then ' bajo ' || array_to_string(p_valvulas, ' + ') else '' end,
                                                     v_res, p_esperado, v_id, null, p_cliente, v_fc, v_per, v_pers, v_huella, v_otros));
end;
$f$;

-- El UPDATE directo que tiene que RECHAZARSE (con o sin válvulas): como la edición, sin la ficha.
create function pg_temp.rechazo_update(p_caso text, p_actor uuid, p_lead uuid, p_set jsonb, p_valvulas text[], p_esperado jsonb,
                                       p_cliente uuid)
returns void language plpgsql as $f$
declare
  v_per uuid := (select l.inversionista_id from crm.leads l where l.id = p_cliente);
  v_ficha jsonb := pg_temp.ficha(p_lead); v_fc jsonb := pg_temp.ficha(p_cliente); v_pers jsonb := pg_temp.persona(v_per);
  v_huella text := pg_temp.huella_escritura(); v_otros bigint := pg_temp.otros_del_cliente(p_cliente); v_res text;
begin
  v_res := pg_temp.actualizar_v(p_actor, p_lead, p_set, p_valvulas);
  perform pg_temp.medida(format('%s · UPDATE %s (válvulas %s) → %s', p_caso, p_set::text, coalesce(nullif(array_to_string(p_valvulas, '+'), ''), '-'), v_res));
  perform pg_temp.reg(p_caso, pg_temp.juzgar_rechazo(p_caso, case when p_actor is null then 'el UPDATE sin sesión' else 'el UPDATE con sesión' end
                                                     || case when cardinality(p_valvulas) > 0 then ' bajo ' || array_to_string(p_valvulas, ' + ') else '' end,
                                                     v_res, p_esperado, p_lead, v_ficha, p_cliente, v_fc, v_per, v_pers, v_huella, v_otros));
end;
$f$;

-- El UPDATE directo que tiene que GUARDARSE como hoy: 'ok|1' y cada valor esperado.
create function pg_temp.ok_update(p_caso text, p_actor uuid, p_lead uuid, p_set jsonb, p_valvulas text[], p_campos jsonb)
returns void language plpgsql as $f$
declare v_res text; v_k text; v_m text[] := '{}'; v_f jsonb;
begin
  v_res := pg_temp.actualizar_v(p_actor, p_lead, p_set, p_valvulas);
  perform pg_temp.medida(format('%s · UPDATE %s (%s, válvulas %s) → %s', p_caso, p_set::text, case when p_actor is null then 'sin sesión' else 'con sesión' end,
    coalesce(nullif(array_to_string(p_valvulas, '+'), ''), '-'), v_res));
  if v_res is distinct from 'ok|1' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: el UPDATE se RECHAZÓ (%s) y hoy se guarda\n', p_caso, v_res));
    return;
  end if;
  v_f := pg_temp.ficha(p_lead);
  for v_k in select jsonb_object_keys(p_campos) loop
    if (v_f ->> v_k) is distinct from (p_campos ->> v_k) then
      v_m := array_append(v_m, format('%s = %s (se esperaba %s)', v_k, coalesce(v_f ->> v_k, 'null'), coalesce(p_campos ->> v_k, 'null')));
    end if;
  end loop;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: se guardó otra cosa: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- La EDICIÓN CON DOCUMENTO que tiene que RECHAZARSE: el lead (con su documento) intacto, ninguna persona ni documento nuevos.
create function pg_temp.rechazo_doc(p_caso text, p_actor uuid, p_lead uuid, p_cambios jsonb, p_tipo text, p_documento text,
                                    p_esperado jsonb, p_cliente uuid)
returns void language plpgsql as $f$
declare
  v_per uuid := (select l.inversionista_id from crm.leads l where l.id = p_cliente);
  v_ficha jsonb := pg_temp.ficha(p_lead); v_fc jsonb := pg_temp.ficha(p_cliente); v_pers jsonb := pg_temp.persona(v_per);
  v_huella text := pg_temp.huella_escritura(); v_otros bigint := pg_temp.otros_del_cliente(p_cliente); v_res text;
begin
  v_res := pg_temp.editar_doc(p_actor, p_lead, p_cambios, p_tipo, p_documento);
  perform pg_temp.medida(format('%s · edición con documento (%s %s) y %s → %s', p_caso, p_tipo, p_documento, p_cambios::text, v_res));
  perform pg_temp.reg(p_caso, pg_temp.juzgar_rechazo(p_caso, 'la edición con documento', v_res, p_esperado, p_lead, v_ficha, p_cliente,
                                                     v_fc, v_per, v_pers, v_huella, v_otros));
end;
$f$;

-- La EDICIÓN CON DOCUMENTO que tiene que GUARDARSE: cada valor esperado y, con p_enlaza, el lead enlazado a la persona del documento.
create function pg_temp.ok_doc(p_caso text, p_actor uuid, p_lead uuid, p_cambios jsonb, p_tipo text, p_documento text, p_campos jsonb,
                               p_enlaza boolean, p_identificador boolean default false)
returns void language plpgsql as $f$
declare v_res text; v_k text; v_m text[] := '{}'; v_f jsonb; v_ident uuid;
begin
  v_res := pg_temp.editar_doc(p_actor, p_lead, p_cambios, p_tipo, p_documento);
  perform pg_temp.medida(format('%s · edición con documento (%s %s) y %s → %s', p_caso, p_tipo, p_documento, p_cambios::text, v_res));
  if v_res not like 'ok|%' then
    perform pg_temp.reg(p_caso, format(E'FALLO %s: la edición con documento se RECHAZÓ (%s) y hoy se guarda\n', p_caso, v_res));
    return;
  end if;
  v_f := pg_temp.ficha(p_lead);
  for v_k in select jsonb_object_keys(p_campos) loop
    if (v_f ->> v_k) is distinct from (p_campos ->> v_k) then
      v_m := array_append(v_m, format('%s = %s (se esperaba %s)', v_k, coalesce(v_f ->> v_k, 'null'), coalesce(p_campos ->> v_k, 'null')));
    end if;
  end loop;
  if p_enlaza and (v_f ->> 'inversionista_id') is null then
    v_m := array_append(v_m, 'el lead no quedó enlazado a la persona de su documento');
  end if;
  -- Ronda 4 (Codex R2-F2): no basta un enlace cualquiera; lead ↔ persona ↔ identificador: la persona del lead es la que TIENE ese
  -- documento (tipo y número normalizado), y la respuesta nombra esa persona y ese identificador.
  if p_identificador then
    select d.id into v_ident
      from crm.inversionista_identificadores d
     where d.tipo_documento = p_tipo and d.documento_normalizado = upper(btrim(p_documento))
       and d.inversionista_id = (v_f ->> 'inversionista_id')::uuid;
    if v_ident is null then
      v_m := array_append(v_m, format('el lead quedó enlazado a la persona %s, que NO tiene el documento %s %s (la persona de ese documento: %s)',
        coalesce(v_f ->> 'inversionista_id', 'ninguna'), p_tipo, p_documento,
        coalesce((select string_agg(d.inversionista_id::text, ', ') from crm.inversionista_identificadores d
                   where d.tipo_documento = p_tipo and d.documento_normalizado = upper(btrim(p_documento))), 'ninguna')));
    elsif (substr(v_res, 4)::jsonb ->> 'identificador_id') is distinct from v_ident::text
       or (substr(v_res, 4)::jsonb ->> 'inversionista_id') is distinct from (v_f ->> 'inversionista_id') then
      v_m := array_append(v_m, format('la respuesta no nombra esa persona y ese documento (%s)', substr(v_res, 4)));
    end if;
  end if;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: se guardó otra cosa: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- El ALTA que tiene que BLOQUEAR (respuesta, no error): la respuesta EXACTA, el cliente y su persona intactos, nada escrito y
-- ningún lead más con los contactos del cliente. Con estado=creado, el fallo dice el defecto.
create function pg_temp.bloqueo_alta(p_caso text, p_actor uuid, p_tel text, p_dni text, p_alt text, p_esperado jsonb, p_cliente uuid)
returns void language plpgsql as $f$
declare
  v_id uuid := gen_random_uuid(); v_per uuid := (select l.inversionista_id from crm.leads l where l.id = p_cliente);
  v_fc jsonb := pg_temp.ficha(p_cliente); v_pers jsonb := pg_temp.persona(v_per);
  v_huella text := pg_temp.huella_escritura(); v_otros bigint := pg_temp.otros_del_cliente(p_cliente);
  v_res text; v_r jsonb; v_m text[] := '{}';
begin
  v_res := pg_temp.alta(p_actor, v_id, 'ALTA ' || p_caso, p_tel, p_dni, p_alt);
  perform pg_temp.medida(format('%s · alta (teléfono %s, alternativo %s, DNI %s) → %s', p_caso, p_tel, coalesce(p_alt, '-'), coalesce(p_dni, '-'), v_res));
  if v_res not like 'ok|%' then
    v_m := array_append(v_m, format('el alta falló (%s) en vez de responder %s', v_res, p_esperado::text));
  else
    v_r := substr(v_res, 4)::jsonb;
    if v_r ->> 'estado' = 'creado' then
      perform pg_temp.reg(p_caso, format(E'FALLO %s: estado=creado, se esperaba %s → el alta creó un SEGUNDO lead del cliente: %s lead(s) más con su teléfono, su alternativo (también el sin validar) o su DNI (había %s)\n',
        p_caso, p_esperado::text, pg_temp.otros_del_cliente(p_cliente), v_otros));
      return;
    elsif v_r is distinct from p_esperado then
      v_m := array_append(v_m, format('respuesta %s, se esperaba EXACTAMENTE %s', v_r::text, p_esperado::text));
    end if;
  end if;
  if pg_temp.ficha(v_id) is not null then v_m := array_append(v_m, 'nació el lead del alta'); end if;
  if pg_temp.ficha(p_cliente) is distinct from v_fc then v_m := array_append(v_m, 'la ficha del cliente cambió'); end if;
  if v_per is not null and pg_temp.persona(v_per) is distinct from v_pers then v_m := array_append(v_m, 'la persona del cliente cambió'); end if;
  if pg_temp.huella_escritura() is distinct from v_huella then v_m := array_append(v_m, 'se escribió algo'); end if;
  if pg_temp.otros_del_cliente(p_cliente) <> v_otros then
    v_m := array_append(v_m, format('%s lead(s) más con los contactos del cliente (había %s)', pg_temp.otros_del_cliente(p_cliente), v_otros));
  end if;
  perform pg_temp.reg(p_caso, case when cardinality(v_m) = 0 then '' else format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; ')) end);
end;
$f$;

-- Veredicto «ya es cliente» de un convertido SIN persona (formato del verificador, sin via: la decisión del 2.7).
create function pg_temp.sin_persona(p_asesor text) returns jsonb language sql immutable as $$
  select jsonb_build_object('estado', 'ya_es_cliente', 'asesor', p_asesor)
$$;

-- El veredicto que da HOY el verificador con el teléfono Y el DNI del cliente con persona (el juicio de identidad): es el que la
-- regla tiene que repetir. Aborta si el cliente no es el estado del caso (ya_es_cliente, via identidad, asesor esperado).
create function pg_temp.juicio_de(p_n integer, p_asesor text) returns jsonb language plpgsql as $f$
declare v_j jsonb := private.verificar_disponibilidad_lead_impl(pg_temp.teln(p_n), pg_temp.dni(p_n));
begin
  if v_j ->> 'estado' is distinct from 'ya_es_cliente' or v_j ->> 'via' is distinct from 'identidad' or v_j ->> 'asesor' is distinct from p_asesor then
    raise exception 'ENSAYO ABORTADO: el cliente % no da el juicio de identidad esperado (%; asesor esperado %)', p_n, v_j, p_asesor;
  end if;
  return v_j;
end;
$f$;

-- Precondición de un caso de edición: hoy el disparador (el verificador sellado, excluyendo al propio lead) dice «libre» con lo que
-- el lead quedaría; si no, el caso no mediría la regla nueva y el ensayo aborta.
create function pg_temp.exigir_libre(p_caso text, p_tel text, p_dni text, p_lead uuid) returns void language plpgsql as $f$
declare v_v jsonb := private.verificar_disponibilidad_lead_impl(p_tel, p_dni, p_lead);
begin
  if v_v ->> 'estado' is distinct from 'libre' then
    raise exception 'ENSAYO ABORTADO: %: el verificador no dice «libre» (%): el caso no mediría la regla', p_caso, v_v;
  end if;
end;
$f$;

-- RONDA 4 (huecos de Codex r2): el estado inicial del alternativo sin validar de un lead, ANTES de su caso. Si no es el declarado, el
-- caso no mediría lo que dice (en ROJO, un reenvío sobre lo que aceptó otro caso) y el ensayo aborta.
create function pg_temp.exigir_cruda(p_caso text, p_lead uuid, p_valor text) returns void language plpgsql as $f$
begin
  if (select l.telefono_alternativo_crudo from crm.leads l where l.id = p_lead) is distinct from p_valor then
    raise exception 'ENSAYO ABORTADO: %: el lead no parte con el alternativo sin validar %', p_caso, coalesce('«' || p_valor || '»', 'NULL');
  end if;
end;
$f$;

-- RONDA 4 (auditor P3-4): las CLAVES DE CANDADO que pide UNA escritura. Son candados consultivos de transacción
-- (`pg_advisory_xact_lock(hashtextextended('avancecrm:lead:' || <clave>, 0))`, en `private.bloquear_contactos_lead`); en `pg_locks`
-- la clave de 64 bits es `classid << 32 | objid`. Se miran antes y después de la escritura DENTRO de un bloque con EXCEPTION que se
-- deshace al final: la escritura no queda y sus candados se sueltan (ensayado: salidas/ronda4/trabajo/ensayos/supuestos).
create function pg_temp.claves_tomadas() returns bigint[] language sql as $$
  select coalesce(array_agg(((l.classid::text::bigint) << 32) | (l.objid::text::bigint) order by 1), '{}')
  from pg_locks l
  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 1
$$;
-- La clave de un contacto como la calcula `private.bloquear_contactos_lead`: el teléfono, en la forma de `normalizar_telefono`.
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
-- p_esperadas ('telefono:<número>' / 'dni:<número>'); las demás claves consultivas (otros disparadores) se cuentan aparte. Ninguna
-- clave esperada puede estar tomada ANTES (si lo estuviera, el caso no la vería pedir y el ensayo aborta). Devuelve las pedidas.
create function pg_temp.juzgar_claves(p_caso text, p_actor uuid, p_sql text, p_esperadas text[], p_valores text[])
returns bigint[] language plpgsql as $f$
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
    return null;
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
    regexp_replace(p_sql, '\s+', ' ', 'g'),
    coalesce('{' || v_pedidas_txt || '}', '{ninguno}'), cardinality(r.pedidas) - cardinality(v_ped)));
  select string_agg(e, ', ' order by e) into v_falta
    from unnest(p_esperadas) e
   where pg_temp.clave(split_part(e, ':', 1), substr(e, length(split_part(e, ':', 1)) + 2)) <> all (v_ped);
  select string_agg(n, ', ' order by n) into v_sobra
    from (select distinct pg_temp.nombre_clave(t.tipo, v) as n, pg_temp.clave(t.tipo, v) as k
            from unnest(p_valores) v cross join (values ('telefono'), ('dni')) t(tipo)) x
   where x.k = any (v_ped) and x.k <> all (v_esp);
  perform pg_temp.reg(p_caso, case when v_falta is null and v_sobra is null then ''
    else format(E'FALLO %s: el disparador no pide las claves de candado esperadas (la del alternativo, con la clave del teléfono): pidió %s; faltan {%s}; sobran {%s}\n',
                p_caso, coalesce('{' || v_pedidas_txt || '}', '{ninguna clave de contacto: el disparador ni se disparó o no bloqueó}'),
                coalesce(v_falta, ''), coalesce(v_sobra, '')) end);
  return r.pedidas;
end;
$f$;
-- Un lead para K: nace por la PUERTA REAL (con su episodio y su ciclo SLA, que la edición exige) con un teléfono auxiliar y recibe
-- los contactos del caso con los disparadores apagados (estado declarado): así ninguna de SUS claves estaba tomada antes del caso.
create function pg_temp.lead_para_claves(p_n_puerta integer, p_nombre text, p_tel text, p_alt text, p_dni text) returns uuid
language plpgsql as $f$
declare v_id uuid := pg_temp.lead_nuevo(pg_temp.actor('VEND1'), p_n_puerta, p_nombre);
begin
  set local session_replication_role = replica;
  update crm.leads set telefono = p_tel, telefono_alternativo = p_alt, dni = p_dni where id = v_id;
  set local session_replication_role = origin;
  if (select l.telefono is distinct from p_tel or l.telefono_alternativo is distinct from p_alt or l.dni is distinct from p_dni
        from crm.leads l where l.id = v_id) then
    raise exception 'ENSAYO ABORTADO: el lead % de K no quedó con los contactos del caso', p_nombre;
  end if;
  return v_id;
end;
$f$;

insert into ens_actores (nombre, id)
select n.nombre, p.id
from (values ('VEND1'), ('VEND2'), ('VEND3'), ('SUP1'), ('GERENCIA'), ('COORD'), ('INACTIVO'), ('ADMIN')) n(nombre)
join public.perfiles p on p.nombre_completo = 'PASO08 ' || n.nombre;

do $ensayo$
declare
  v_vend1 uuid; v_vend2 uuid; v_vend3 uuid; v_sup1 uuid; v_ger uuid; v_coord uuid; v_inactivo uuid; v_admin uuid;
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_alta regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_disp regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_pieza regprocedure := to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)');
  v_c uuid; v_c2 uuid; v_l uuid; v_l2 uuid; v_l3 uuid; v_per uuid; v_otra uuid; v_pid uuid; v_base uuid;
  v_esp jsonb; v_r jsonb; v_res text; v_txt text; v_n bigint;
  v_le uuid; v_f1 uuid; v_li uuid; v_li2 uuid; v_i integer; v_ts timestamptz; v_esp8 jsonb; v_esp_cruda jsonb; v_ficha jsonb;
  v_huella text; v_c8 uuid;
  v_li3 uuid; v_li4 uuid; v_li5 uuid; v_f7 uuid; v_k2 bigint[]; v_k7 bigint[];
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
     or private.rol_crm(v_inactivo) is not null or private.rol_crm(v_admin) is not null
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend2) is distinct from v_sup1 then
    raise exception 'ENSAYO ABORTADO: un actor del banco no tiene el rol esperado (vend1/vend2/vend3 vendedor, vend2 bajo sup1; sup1 supervisor; gerencia; coord coordinador; inactivo y admin sin rol CRM)';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'ENSAYO ABORTADO: la bandera resolver_en_puertas está apagada en este laboratorio';
  end if;
  -- El bloque de contactos del ensayo tiene que estar libre (teléfono, alternativo, DNI, perfiles y documentos).
  if exists (select 1 from crm.leads l where l.telefono like '+5192408%' or l.telefono_alternativo like '%92408%'
                                             or l.telefono_alternativo_crudo like '%92408%' or l.dni like '7528%')
     or exists (select 1 from public.perfiles p where p.telefono like '%92408%' or p.dni like '7528%')
     or exists (select 1 from crm.inversionista_identificadores d where d.documento_normalizado like '7528%'
                                                                   or d.documento_normalizado like '%92408%') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene contactos del bloque +51 924 08xxxx / 7528xxxx';
  end if;
  -- El cubo de comprobantes de la conversión real (fixture del banco; si falta, vive y muere en esta transacción).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('f4-comprobantes', 'f4-comprobantes', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
  on conflict (id) do nothing;
  -- Medidas del punto de partida (no son casos).
  perform pg_temp.medida(format('I0 permisos de crm.leads: INSERT de authenticated (tabla=%s, alguna columna=%s) · INSERT de anon (tabla=%s, alguna columna=%s) · UPDATE de authenticated (tabla=%s)',
    has_table_privilege('authenticated', 'crm.leads', 'INSERT'), has_any_column_privilege('authenticated', 'crm.leads', 'INSERT'),
    has_table_privilege('anon', 'crm.leads', 'INSERT'), has_any_column_privilege('anon', 'crm.leads', 'INSERT'),
    has_table_privilege('authenticated', 'crm.leads', 'UPDATE')));
  perform pg_temp.medida(format('T0 disparador de la edición: %s',
    (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update')));
  perform pg_temp.medida(format('T0 la pieza común private.juicio_cliente_convertido: %s', case when v_pieza is null then 'AUSENTE' else 'presente' end));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E1. EDITAR EL TELÉFONO hacia el de un cliente ⇒ P0481 con el veredicto de la regla del 2.7 en el detalle; nada guardado.
  --     E1a con persona y activo (VEND2 edita su lead) · E1b con persona y retirado (SUP1 edita el de VEND2) · E1c sin persona,
  --     activo (Gerencia edita) · E1d sin persona, retirado · E1e sin persona y sin dueño («sin asesor asignado») · E1g persona
  --     VETADA con la bandera apagada (el verificador no la ve: la regla da `no_contactar`) · E1h persona FUSIONADA sin juicio
  --     (el respaldo de D-21).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(1, 'CLIENTE E1A ACTIVO');
  v_esp := pg_temp.juicio_de(1, 'PASO08 VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 101, 'LEAD E1A QUE SE EDITA');
  perform pg_temp.exigir_libre('E1a', pg_temp.teln(1), null, v_l);
  perform pg_temp.rechazo_edicion('E1a-telefono-de-cliente-activo-con-persona', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(1)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);

  v_c := pg_temp.convertir_real(2, 'CLIENTE E1B RETIRADO');
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente E1b'; end if;
  v_esp := pg_temp.juicio_de(2, 'PASO08 VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 102, 'LEAD E1B QUE SE EDITA');
  perform pg_temp.exigir_libre('E1b', pg_temp.teln(2), null, v_l);
  perform pg_temp.rechazo_edicion('E1b-telefono-de-cliente-retirado-con-persona (lo edita SUP1)', v_sup1, v_l,
    jsonb_build_object('telefono', pg_temp.tel(2)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);

  v_c := pg_temp.cliente_sin_persona(3, 'CLIENTE E1C SIN PERSONA', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 103, 'LEAD E1C QUE SE EDITA');
  perform pg_temp.exigir_libre('E1c', pg_temp.teln(3), null, v_l);
  perform pg_temp.rechazo_edicion('E1c-telefono-de-cliente-sin-persona-activo (lo edita Gerencia)', v_ger, v_l,
    jsonb_build_object('telefono', pg_temp.tel(3)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);

  v_c := pg_temp.cliente_sin_persona(4, 'CLIENTE E1D SIN PERSONA RETIRADO', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 104, 'LEAD E1D QUE SE EDITA');
  perform pg_temp.exigir_libre('E1d', pg_temp.teln(4), null, v_l);
  perform pg_temp.rechazo_edicion('E1d-telefono-de-cliente-sin-persona-retirado', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(4)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);

  v_c := pg_temp.cliente_sin_persona(5, 'CLIENTE E1E SIN DUENO', v_ger, false);
  if (select l.vendedor_id is not null or l.asignado_supervisor_id is not null from crm.leads l where l.id = v_c) then
    raise exception 'ENSAYO ABORTADO: el cliente E1e no quedó en la cola global (sin dueño)';
  end if;
  v_l := pg_temp.lead_nuevo(v_vend2, 105, 'LEAD E1E QUE SE EDITA');
  perform pg_temp.exigir_libre('E1e', pg_temp.teln(5), null, v_l);
  perform pg_temp.rechazo_edicion('E1e-telefono-de-cliente-sin-persona-sin-dueno', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(5)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('sin asesor asignado')), v_c);

  -- E1g. Persona VETADA (sembrada: la persona vetada y su lead sin veto) con la bandera APAGADA: el verificador no la ve.
  v_c := pg_temp.convertir_real(6, 'CLIENTE E1G PERSONA VETADA');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  set local session_replication_role = replica;
  update crm.inversionistas set no_contactar = true, no_contactar_en = clock_timestamp(), no_contactar_por = v_vend1 where id = v_per;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 106, 'LEAD E1G QUE SE EDITA');
  perform pg_temp.bandera(false);
  perform pg_temp.exigir_libre('E1g (bandera apagada)', pg_temp.teln(6), null, v_l);
  perform pg_temp.rechazo_edicion('E1g-persona-vetada-bandera-apagada (juicio de la persona)', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(6)), jsonb_build_object('error', 'P0481', 'detalle', jsonb_build_object('estado', 'no_contactar')), v_c);
  perform pg_temp.bandera(true);

  -- E1h. Persona FUSIONADA en otra sin leads (sembrado): el juicio de la canónica es nulo ⇒ el respaldo de D-21.
  v_c := pg_temp.convertir_real(7, 'CLIENTE E1H PERSONA FUSIONADA');
  v_per := (select l.inversionista_id from crm.leads l where l.id = v_c);
  v_otra := private.inversionista_resolver('DNI', pg_temp.dni(97), true, 'ensayo-bloque-2.8');
  if v_otra is null or v_otra = v_per then raise exception 'ENSAYO ABORTADO: no se pudo crear la persona canónica del caso E1h'; end if;
  set local session_replication_role = replica;
  update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = v_otra, fusionado_en = clock_timestamp() where id = v_per;
  set local session_replication_role = origin;
  v_l := pg_temp.lead_nuevo(v_vend2, 107, 'LEAD E1H QUE SE EDITA');
  if private.inversionista_canonica(v_per) is distinct from v_otra or private.juicio_persona(private.inversionista_canonica(v_per), v_l) is not null then
    raise exception 'ENSAYO ABORTADO: el caso E1h no es el estado buscado (canónica o juicio no nulo)';
  end if;
  perform pg_temp.exigir_libre('E1h', pg_temp.teln(7), null, v_l);
  perform pg_temp.rechazo_edicion('E1h-persona-fusionada-sin-juicio (respaldo de D-21)', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(7)),
    jsonb_build_object('error', 'P0481', 'detalle', jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad')), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E2. EDITAR EL DNI hacia el de un cliente.
  --     E2a con persona y la bandera ENCENDIDA: lo rechaza YA la puerta del DNI (`fijar_dni_lead_fn`, P0409 con el juicio): como hoy.
  --     E2b con persona y la bandera APAGADA (un solo UPDATE; el verificador no mira identidades) ⇒ P0481 con el juicio.
  --     E2c/E2d sin persona, activo/retirado (el verificador solo reconoce el DNI por las identidades) ⇒ P0481 a nombre del dueño.
  --     E2e el DNI de quien NO es cliente (un retirado no convertido) ⇒ se guarda como hoy.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(8, 'CLIENTE E2A');
  v_esp := pg_temp.juicio_de(8, 'PASO08 VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 108, 'LEAD E2A QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E2a-dni-de-cliente-con-persona-bandera-encendida (la puerta del DNI, como hoy)', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(8)),
    jsonb_build_object('error', 'P0409', 'mensaje', 'ya es cliente o ya tiene su lead', 'detalle', v_esp), v_c);

  v_c := pg_temp.convertir_real(9, 'CLIENTE E2B');
  v_esp := pg_temp.juicio_de(9, 'PASO08 VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 109, 'LEAD E2B QUE SE EDITA');
  perform pg_temp.bandera(false);
  perform pg_temp.exigir_libre('E2b (bandera apagada)', pg_temp.teln(109), pg_temp.dni(9), v_l);
  perform pg_temp.rechazo_edicion('E2b-dni-de-cliente-con-persona-bandera-apagada', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(9)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);
  perform pg_temp.bandera(true);

  v_c := pg_temp.cliente_sin_persona(10, 'CLIENTE E2C SIN PERSONA', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 110, 'LEAD E2C QUE SE EDITA');
  if private.inversionista_por_documento('DNI', pg_temp.dni(10)) is not null then
    raise exception 'ENSAYO ABORTADO: el DNI del cliente sin persona E2c resuelve a una persona';
  end if;
  perform pg_temp.exigir_libre('E2c', pg_temp.teln(110), pg_temp.dni(10), v_l);
  perform pg_temp.rechazo_edicion('E2c-dni-de-cliente-sin-persona-activo', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(10)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);

  v_c := pg_temp.cliente_sin_persona(11, 'CLIENTE E2D SIN PERSONA RETIRADO', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 111, 'LEAD E2D QUE SE EDITA');
  perform pg_temp.exigir_libre('E2d', pg_temp.teln(111), pg_temp.dni(11), v_l);
  perform pg_temp.rechazo_edicion('E2d-dni-de-cliente-sin-persona-retirado', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(11)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);

  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA E2E RETIRADA NO CLIENTE', pg_temp.tel(12), pg_temp.dni(12));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso E2e (%)', v_res;
  end if;
  v_l := pg_temp.lead_nuevo(v_vend2, 112, 'LEAD E2E QUE SE EDITA');
  perform pg_temp.ok_edicion('E2e-dni-de-quien-no-es-cliente (se guarda como hoy)', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(12)), jsonb_build_object('dni', pg_temp.dni(12)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E3. EDITAR EL ALTERNATIVO hacia el teléfono de un cliente (D-30: lo tecleado como alternativo contra el principal del cliente).
  --     Hoy el disparador ni siquiera se dispara si solo cambia el alternativo. E3a solo el alternativo · E3b el alternativo y el
  --     nombre · E3c/E3d quien no tiene rol CRM (INACTIVO, COORD) ⇒ 42501 «Acceso CRM revocado»: nunca ve el veredicto.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(13, 'CLIENTE E3A');
  v_esp := pg_temp.juicio_de(13, 'PASO08 VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 113, 'LEAD E3A QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E3a-alternativo-hacia-el-telefono-de-un-cliente', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(13)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);

  v_c := pg_temp.cliente_sin_persona(14, 'CLIENTE E3B SIN PERSONA', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 114, 'LEAD E3B QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E3b-alternativo-y-nombre-hacia-un-cliente-sin-persona', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(14), 'nombre_completo', 'LEAD E3B RENOMBRADO'),
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);

  v_c := pg_temp.convertir_real(15, 'CLIENTE E3C');
  v_l := pg_temp.lead_nuevo(v_vend2, 115, 'LEAD E3C QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E3c-alternativo-por-quien-no-tiene-rol (INACTIVO: 42501, sin veredicto)', v_inactivo, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(15)), jsonb_build_object('error', '42501', 'mensaje', 'Acceso CRM revocado'), v_c);
  v_l := pg_temp.lead_nuevo(v_vend2, 116, 'LEAD E3D QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E3d-alternativo-por-quien-no-tiene-rol (COORD: 42501, sin veredicto)', v_coord, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(15)), jsonb_build_object('error', '42501', 'mensaje', 'Acceso CRM revocado'), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E4. EDITAR EL TELÉFONO hacia el ALTERNATIVO de un cliente (lo tecleado como principal contra el alternativo del cliente).
  -- E5. EDITAR EL ALTERNATIVO hacia el ALTERNATIVO de un cliente.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(16, 'CLIENTE E4 CON ALTERNATIVO', null, pg_temp.teln(316));
  v_esp := pg_temp.juicio_de(16, 'PASO08 VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 117, 'LEAD E4 QUE SE EDITA');
  perform pg_temp.exigir_libre('E4', pg_temp.teln(316), null, v_l);
  perform pg_temp.rechazo_edicion('E4-telefono-hacia-el-alternativo-de-un-cliente', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(316)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);

  v_c := pg_temp.cliente_sin_persona(17, 'CLIENTE E5 SIN PERSONA CON ALTERNATIVO', v_vend1, false, pg_temp.teln(317));
  v_l := pg_temp.lead_nuevo(v_vend2, 118, 'LEAD E5 QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E5-alternativo-hacia-el-alternativo-de-un-cliente', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(317)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E6. NEGATIVOS de la edición: la respuesta de HOY, exacta.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E6a. Una edición ajena a los contactos (nombre, nota, correo, capital) ⇒ se guarda.
  v_l := pg_temp.lead_nuevo(v_vend2, 119, 'LEAD E6A');
  perform pg_temp.ok_edicion('E6a-edicion-ajena-a-los-contactos', v_vend2, v_l,
    jsonb_build_object('nombre_completo', 'LEAD E6A CORREGIDO', 'nota', 'nota e6a', 'correo', 'e6a@ensayo.invalid', 'monto_estimado', '7000'),
    jsonb_build_object('nombre_completo', 'LEAD E6A CORREGIDO', 'nota', 'nota e6a', 'correo', 'e6a@ensayo.invalid', 'monto_estimado', '7000'));
  -- E6b. El DUPLICADO HEREDADO (D-23/D-25: un lead vivo que YA comparte teléfono con un cliente, sembrado) sigue editándose:
  --      b1 nombre y nota · b2 reenvía su MISMO teléfono (como lo teclea la ficha, sin +51) con otro nombre · b3 cambia su DNI a
  --      uno que no es de un cliente (se juzga lo que la edición pone, no el teléfono que ya tenía) · b4 cambia su alternativo a uno
  --      libre · b5 cambia su teléfono a uno libre (deja de ser duplicado). El duplicado nace por la puerta real (con su episodio y
  --      su ciclo SLA, que la edición exige) y recibe el teléfono del cliente con los disparadores apagados: el estado heredado de D-23.
  v_c := pg_temp.convertir_real(19, 'CLIENTE E6B CON DUPLICADO HEREDADO');
  v_l2 := pg_temp.lead_nuevo(v_vend2, 219, 'DUPLICADO HEREDADO E6B');
  set local session_replication_role = replica;
  update crm.leads set telefono = pg_temp.teln(19) where id = v_l2;
  set local session_replication_role = origin;
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(19)) <> 2 then
    raise exception 'ENSAYO ABORTADO: el duplicado heredado E6b no comparte el teléfono del cliente';
  end if;
  perform pg_temp.ok_edicion('E6b1-duplicado-heredado-nombre-y-nota', v_vend2, v_l2,
    jsonb_build_object('nombre_completo', 'DUPLICADO E6B RENOMBRADO', 'nota', 'sigue editable'),
    jsonb_build_object('nombre_completo', 'DUPLICADO E6B RENOMBRADO', 'nota', 'sigue editable', 'telefono', pg_temp.teln(19)));
  perform pg_temp.ok_edicion('E6b2-duplicado-heredado-reenvia-su-mismo-telefono', v_vend2, v_l2,
    jsonb_build_object('telefono', pg_temp.tel(19), 'nombre_completo', 'DUPLICADO E6B OTRA VEZ'),
    jsonb_build_object('telefono', pg_temp.teln(19), 'nombre_completo', 'DUPLICADO E6B OTRA VEZ'));
  perform pg_temp.ok_edicion('E6b3-duplicado-heredado-cambia-su-dni-a-uno-libre', v_vend2, v_l2,
    jsonb_build_object('dni', pg_temp.dni(219)), jsonb_build_object('dni', pg_temp.dni(219), 'telefono', pg_temp.teln(19)));
  perform pg_temp.ok_edicion('E6b4-duplicado-heredado-cambia-su-alternativo-a-uno-libre', v_vend2, v_l2,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(319)), jsonb_build_object('telefono_alternativo', pg_temp.teln(319), 'telefono', pg_temp.teln(19)));
  perform pg_temp.ok_edicion('E6b5-duplicado-heredado-cambia-su-telefono-a-uno-libre', v_vend2, v_l2,
    jsonb_build_object('telefono', pg_temp.tel(419)), jsonb_build_object('telefono', pg_temp.teln(419)));
  -- E6c. El teléfono a uno LIBRE ⇒ se guarda.
  v_l := pg_temp.lead_nuevo(v_vend2, 120, 'LEAD E6C');
  perform pg_temp.ok_edicion('E6c-telefono-a-uno-libre', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(420)), jsonb_build_object('telefono', pg_temp.teln(420)));
  -- E6d. El teléfono de un lead VIVO de otro (no cliente) ⇒ el «tomado» de hoy, exacto.
  v_l3 := pg_temp.lead_nuevo(v_vend1, 121, 'LEAD E6D VIVO DE VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 122, 'LEAD E6D QUE SE EDITA');
  v_esp := private.verificar_disponibilidad_lead_impl(pg_temp.teln(121), null, v_l);
  if v_esp ->> 'estado' is distinct from 'tomado' then raise exception 'ENSAYO ABORTADO: E6d: el verificador no dice «tomado» (%)', v_esp; end if;
  perform pg_temp.rechazo_edicion('E6d-telefono-de-un-lead-vivo (el tomado de hoy)', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(121)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_l3);
  -- E6d2. El teléfono de un CLIENTE que además tiene un duplicado heredado VIVO ⇒ manda el «tomado» de hoy (el verificador va
  --       antes que la regla), no el «ya es cliente».
  v_c := pg_temp.convertir_real(23, 'CLIENTE E6D2');
  v_l2 := pg_temp.sembrado(23, 'DUPLICADO HEREDADO E6D2 VIVO', true, 'contactado', null, v_vend1);
  v_l := pg_temp.lead_nuevo(v_vend2, 123, 'LEAD E6D2 QUE SE EDITA');
  v_esp := private.verificar_disponibilidad_lead_impl(pg_temp.teln(23), null, v_l);
  if v_esp ->> 'estado' is distinct from 'tomado' then raise exception 'ENSAYO ABORTADO: E6d2: el verificador no dice «tomado» (%)', v_esp; end if;
  perform pg_temp.rechazo_edicion('E6d2-cliente-con-duplicado-vivo (manda el tomado de hoy)', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(23)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);
  -- E6e. Un lead VETADO (sembrado) que intenta tomar el teléfono de un cliente ⇒ el «no contactar» de hoy (el veto congela sus
  --      contactos), no el «ya es cliente».
  v_c := pg_temp.convertir_real(24, 'CLIENTE E6E');
  v_l := pg_temp.lead_nuevo(v_vend2, 124, 'LEAD E6E VETADO');
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_l;
  set local session_replication_role = origin;
  perform pg_temp.rechazo_edicion('E6e-lead-vetado-hacia-el-telefono-de-un-cliente (manda el veto de hoy)', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(24)), jsonb_build_object('error', 'P0481', 'detalle', jsonb_build_object('estado', 'no_contactar')), v_c);
  -- E6f. El propio CLIENTE (su lead convertido, con su alternativo) se edita: la regla no lo compara consigo mismo.
  --      f1 su nota · f2 intercambia su teléfono y su alternativo (cambió de número principal).
  v_c := pg_temp.convertir_real(25, 'CLIENTE E6F', null, pg_temp.teln(325));
  perform pg_temp.ok_edicion('E6f1-el-cliente-se-edita-a-si-mismo (nota)', v_vend1, v_c,
    jsonb_build_object('nota', 'nota del propio cliente'), jsonb_build_object('nota', 'nota del propio cliente'));
  perform pg_temp.exigir_libre('E6f2', pg_temp.teln(325), pg_temp.dni(25), v_c);
  perform pg_temp.ok_edicion('E6f2-el-cliente-intercambia-sus-dos-telefonos', v_vend1, v_c,
    jsonb_build_object('telefono', pg_temp.tel(325), 'telefono_alternativo', pg_temp.teln(25)),
    jsonb_build_object('telefono', pg_temp.teln(325), 'telefono_alternativo', pg_temp.teln(25)));
  -- E6g. Quitar el alternativo; E6h ponerlo a uno libre.
  v_l := pg_temp.lead_nuevo(v_vend2, 126, 'LEAD E6G CON ALTERNATIVO', null, pg_temp.teln(326));
  perform pg_temp.ok_edicion('E6g-quitar-el-alternativo', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', null), jsonb_build_object('telefono_alternativo', null));
  perform pg_temp.ok_edicion('E6h-alternativo-a-uno-libre', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(327)), jsonb_build_object('telefono_alternativo', pg_temp.teln(327)));
  -- E6i. Roles sin permiso que cambian el TELÉFONO hacia el de un cliente ⇒ el 42501 de hoy (antes de mirar nada).
  v_c := pg_temp.convertir_real(27, 'CLIENTE E6I');
  v_l := pg_temp.lead_nuevo(v_vend2, 127, 'LEAD E6I QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E6i1-inactivo-telefono-de-un-cliente (42501 de hoy)', v_inactivo, v_l,
    jsonb_build_object('telefono', pg_temp.tel(27)), jsonb_build_object('error', '42501', 'mensaje', 'Acceso CRM revocado'), v_c);
  perform pg_temp.rechazo_edicion('E6i2-coordinador-telefono-de-un-cliente (42501 de hoy)', v_coord, v_l,
    jsonb_build_object('telefono', pg_temp.tel(27)), jsonb_build_object('error', '42501', 'mensaje', 'Acceso CRM revocado'), v_c);
  perform pg_temp.rechazo_edicion('E6i3-admin-sin-rol-telefono-de-un-cliente (42501 de hoy)', v_admin, v_l,
    jsonb_build_object('telefono', pg_temp.tel(27)), jsonb_build_object('error', '42501', 'mensaje', 'Acceso CRM revocado'), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E7. PRECEDENCIA Y PRIORIDAD (en la edición). Entre teléfonos: lo tecleado como principal antes que el alternativo tecleado y,
  --     para cada uno, el principal del cliente antes que su alternativo (E7a–E7c; el que debe perder es además el más reciente,
  --     para que una prioridad «plana» también caiga). Entre varios convertidos del mismo contacto: enlazado → activo → más reciente
  --     (sin fecha detrás), por teléfono (E7d–E7g) y por DNI (E7h–E7k; ids fijos: el menor para el que debe perder). El teléfono
  --     manda sobre el DNI (E7l, bandera apagada: un solo UPDATE). Duplicados heredados sembrados.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.sembrado(171, 'CONVERTIDO E7A PRINCIPAL', true, 'convertido', null, v_vend3, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(172, 'CONVERTIDO E7A CON ESE ALTERNATIVO', true, 'convertido', null, v_vend1, clock_timestamp() - interval '1 day',
                           p_alt => pg_temp.teln(171));
  v_l := pg_temp.lead_nuevo(v_vend2, 128, 'LEAD E7A QUE SE EDITA');
  perform pg_temp.exigir_libre('E7a', pg_temp.teln(171), null, v_l);
  perform pg_temp.rechazo_edicion('E7a-el-principal-del-cliente-antes-que-su-alternativo', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(171)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);

  v_c := pg_temp.sembrado(173, 'CONVERTIDO E7B CON ALTERNATIVO', true, 'convertido', null, v_vend3, clock_timestamp() - interval '10 days',
                          p_alt => pg_temp.teln(373));
  v_c2 := pg_temp.sembrado(174, 'CONVERTIDO E7B PRINCIPAL', true, 'convertido', null, v_vend1, clock_timestamp() - interval '1 day');
  v_l := pg_temp.lead_nuevo(v_vend2, 129, 'LEAD E7B QUE SE EDITA');
  perform pg_temp.exigir_libre('E7b', pg_temp.teln(373), null, v_l);
  perform pg_temp.rechazo_edicion('E7b-lo-tecleado-como-principal-antes-que-el-alternativo-tecleado', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(373), 'telefono_alternativo', pg_temp.teln(174)),
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);

  v_c := pg_temp.sembrado(175, 'CONVERTIDO E7C PRINCIPAL', true, 'convertido', null, v_vend3, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(176, 'CONVERTIDO E7C CON ESE ALTERNATIVO', true, 'convertido', null, v_vend1, clock_timestamp() - interval '1 day',
                           p_alt => pg_temp.teln(175));
  v_l := pg_temp.lead_nuevo(v_vend2, 130, 'LEAD E7C QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E7c-el-alternativo-tecleado-contra-el-principal-antes-que-contra-el-alternativo', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(175)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);

  -- E7d. El ENLAZADO a persona gana aunque esté retirado y sea el más antiguo.
  v_c := pg_temp.convertir_real(77, 'CLIENTE E7D ENLAZADO');
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente E7d'; end if;
  v_esp := pg_temp.juicio_de(77, 'PASO08 VEND1');
  set local session_replication_role = replica;
  update crm.leads set convertido_en = clock_timestamp() - interval '30 days' where id = v_c;
  set local session_replication_role = origin;
  v_c2 := pg_temp.sembrado(77, 'CONVERTIDO E7D SIN PERSONA ACTIVO RECIENTE', true, 'convertido', null, v_vend3, clock_timestamp() - interval '1 day');
  v_l := pg_temp.lead_nuevo(v_vend2, 131, 'LEAD E7D QUE SE EDITA');
  perform pg_temp.exigir_libre('E7d', pg_temp.teln(77), null, v_l);
  perform pg_temp.rechazo_edicion('E7d-telefono-gana-el-enlazado-a-persona', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(77)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);
  -- E7e. Entre dos sin persona, el ACTIVO gana al retirado más reciente.
  v_c := pg_temp.sembrado(178, 'CONVERTIDO E7E ACTIVO', true, 'convertido', null, v_vend3, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(178, 'CONVERTIDO E7E RETIRADO RECIENTE', false, 'convertido', null, v_vend1, clock_timestamp() - interval '1 day');
  v_l := pg_temp.lead_nuevo(v_vend2, 132, 'LEAD E7E QUE SE EDITA');
  perform pg_temp.exigir_libre('E7e', pg_temp.teln(178), null, v_l);
  perform pg_temp.rechazo_edicion('E7e-telefono-gana-el-activo', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(178)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  -- E7f. Dos sin persona activos: el convertido MÁS RECIENTE gana (id menor para el que debe perder).
  v_c := pg_temp.sembrado(179, 'CONVERTIDO E7F RECIENTE', true, 'convertido', null, v_vend3, clock_timestamp() - interval '1 day',
                          p_id => 'ffffffff-0028-4000-8000-000000000706');
  v_c2 := pg_temp.sembrado(179, 'CONVERTIDO E7F ANTIGUO', true, 'convertido', null, v_vend1, clock_timestamp() - interval '10 days',
                           p_id => '00000000-0028-4000-8000-000000000706');
  v_l := pg_temp.lead_nuevo(v_vend2, 133, 'LEAD E7F QUE SE EDITA');
  perform pg_temp.exigir_libre('E7f', pg_temp.teln(179), null, v_l);
  perform pg_temp.rechazo_edicion('E7f-telefono-gana-el-mas-reciente', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(179)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  -- E7g. Un convertido SIN fecha frente a uno con fecha: gana el que la tiene (id menor para el sin fecha).
  v_c := pg_temp.sembrado(180, 'CONVERTIDO E7G CON FECHA', true, 'convertido', null, v_vend3, clock_timestamp() - interval '10 days',
                          p_id => 'ffffffff-0028-4000-8000-000000000707');
  v_c2 := pg_temp.sembrado(180, 'CONVERTIDO E7G SIN FECHA', true, 'convertido', null, v_vend1,
                           p_id => '00000000-0028-4000-8000-000000000707', p_convertido_en_nulo => true);
  v_l := pg_temp.lead_nuevo(v_vend2, 134, 'LEAD E7G QUE SE EDITA');
  perform pg_temp.exigir_libre('E7g', pg_temp.teln(180), null, v_l);
  perform pg_temp.rechazo_edicion('E7g-telefono-gana-el-que-tiene-fecha', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(180)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  -- E7h. DNI: entre dos sin persona, el ACTIVO gana al retirado más reciente.
  v_c := pg_temp.sembrado(181, 'CONVERTIDO E7H ACTIVO', true, 'convertido', pg_temp.dni(81), v_vend3, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(182, 'CONVERTIDO E7H RETIRADO RECIENTE', false, 'convertido', pg_temp.dni(81), v_vend1, clock_timestamp() - interval '1 day');
  v_l := pg_temp.lead_nuevo(v_vend2, 135, 'LEAD E7H QUE SE EDITA');
  perform pg_temp.exigir_libre('E7h', pg_temp.teln(135), pg_temp.dni(81), v_l);
  perform pg_temp.rechazo_edicion('E7h-dni-gana-el-activo', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(81)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  -- E7i. DNI: dos sin persona activos, el MÁS RECIENTE gana (id menor para el que debe perder).
  v_c := pg_temp.sembrado(183, 'CONVERTIDO E7I RECIENTE', true, 'convertido', pg_temp.dni(82), v_vend3, clock_timestamp() - interval '1 day',
                          p_id => 'ffffffff-0028-4000-8000-000000000709');
  v_c2 := pg_temp.sembrado(184, 'CONVERTIDO E7I ANTIGUO', true, 'convertido', pg_temp.dni(82), v_vend1, clock_timestamp() - interval '10 days',
                           p_id => '00000000-0028-4000-8000-000000000709');
  v_l := pg_temp.lead_nuevo(v_vend2, 136, 'LEAD E7I QUE SE EDITA');
  perform pg_temp.exigir_libre('E7i', pg_temp.teln(136), pg_temp.dni(82), v_l);
  perform pg_temp.rechazo_edicion('E7i-dni-gana-el-mas-reciente', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(82)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  -- E7j. DNI (bandera APAGADA: la puerta del DNI no juzga y el verificador no mira identidades): el ENLAZADO gana aunque esté
  --      retirado y sea el más antiguo.
  v_c := pg_temp.convertir_real(83, 'CLIENTE E7J ENLAZADO');
  if pg_temp.retirar(v_ger, v_c) <> '1' then raise exception 'ENSAYO ABORTADO: Gerencia no pudo retirar al cliente E7j'; end if;
  v_esp := pg_temp.juicio_de(83, 'PASO08 VEND1');
  set local session_replication_role = replica;
  update crm.leads set convertido_en = clock_timestamp() - interval '30 days' where id = v_c;
  set local session_replication_role = origin;
  v_c2 := pg_temp.sembrado(185, 'CONVERTIDO E7J SIN PERSONA ACTIVO RECIENTE', true, 'convertido', pg_temp.dni(83), v_vend3, clock_timestamp() - interval '1 day');
  v_l := pg_temp.lead_nuevo(v_vend2, 137, 'LEAD E7J QUE SE EDITA');
  perform pg_temp.bandera(false);
  perform pg_temp.exigir_libre('E7j (bandera apagada)', pg_temp.teln(137), pg_temp.dni(83), v_l);
  perform pg_temp.rechazo_edicion('E7j-dni-gana-el-enlazado-a-persona', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(83)), jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);
  perform pg_temp.bandera(true);
  -- E7k. DNI: un convertido SIN fecha frente a uno con fecha: gana el que la tiene (id menor para el sin fecha).
  v_c := pg_temp.sembrado(186, 'CONVERTIDO E7K CON FECHA', true, 'convertido', pg_temp.dni(84), v_vend3, clock_timestamp() - interval '10 days',
                          p_id => 'ffffffff-0028-4000-8000-000000000711');
  v_c2 := pg_temp.sembrado(187, 'CONVERTIDO E7K SIN FECHA', true, 'convertido', pg_temp.dni(84), v_vend1,
                           p_id => '00000000-0028-4000-8000-000000000711', p_convertido_en_nulo => true);
  v_l := pg_temp.lead_nuevo(v_vend2, 138, 'LEAD E7K QUE SE EDITA');
  perform pg_temp.exigir_libre('E7k', pg_temp.teln(138), pg_temp.dni(84), v_l);
  perform pg_temp.rechazo_edicion('E7k-dni-gana-el-que-tiene-fecha', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(84)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  -- E7l. El TELÉFONO manda sobre el DNI (bandera apagada: un solo UPDATE con los dos): teléfono de un cliente (VEND3) + DNI de
  --      otro (VEND1, más reciente) ⇒ responde por el del teléfono.
  v_c := pg_temp.sembrado(188, 'CONVERTIDO E7L POR TELEFONO', true, 'convertido', null, v_vend3, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(189, 'CONVERTIDO E7L POR DNI', true, 'convertido', pg_temp.dni(86), v_vend1, clock_timestamp() - interval '1 day');
  v_l := pg_temp.lead_nuevo(v_vend2, 139, 'LEAD E7L QUE SE EDITA');
  perform pg_temp.bandera(false);
  perform pg_temp.exigir_libre('E7l (bandera apagada)', pg_temp.teln(188), pg_temp.dni(86), v_l);
  perform pg_temp.rechazo_edicion('E7l-el-telefono-manda-sobre-el-dni', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(188), 'dni', pg_temp.dni(86)),
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  perform pg_temp.bandera(true);
  -- (Medida, no caso.) Lo mismo con la bandera ENCENDIDA: `crm.editar_lead_fn` pasa ANTES el DNI por su puerta (otro UPDATE), así
  -- que responde el cliente del DNI. Los dos bloquean; cuál se nombra lo decide el orden de la ficha, que este bloque no toca.
  v_c := pg_temp.sembrado(190, 'CONVERTIDO E7L-MEDIDA POR TELEFONO', true, 'convertido', null, v_vend3, clock_timestamp() - interval '10 days');
  v_c2 := pg_temp.sembrado(191, 'CONVERTIDO E7L-MEDIDA POR DNI', true, 'convertido', pg_temp.dni(87), v_vend1, clock_timestamp() - interval '1 day');
  v_l := pg_temp.lead_nuevo(v_vend2, 140, 'LEAD E7L CON BANDERA');
  v_res := pg_temp.editar(v_vend2, v_l, jsonb_build_object('telefono', pg_temp.tel(190), 'dni', pg_temp.dni(87)));
  perform pg_temp.medida(format('E7l (bandera ENCENDIDA; teléfono de un cliente de VEND3 + DNI de un cliente de VEND1): %s', v_res));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- E8. RONDA 3: LOS HUECOS DE LA EDICIÓN (auditor y Codex). E8a teléfono LIBRE + alternativo de un cliente en el MISMO UPDATE (la
  --     rama con cambio de identidad también mira el alternativo) · E8b/E8c desempate FINAL por id, por teléfono y por DNI (misma
  --     vinculación, actividad y fecha exacta; dueños distintos: gana el id menor) · E8d el propio lead, excluido en la rama del
  --     ALTERNATIVO (el cliente pone su principal como su alternativo: raro, pero la ficha no lo impide) · E8e–E8g2 la edición con
  --     documento real (`crm.editar_lead_documento_fn`): con DNI o con CE, si después se rechaza el teléfono o el alternativo, el
  --     documento TAMPOCO queda (ni persona ni documento nuevos); con DNI o pasaporte libres, se guarda como hoy · E8h/E8i el
  --     alternativo INTERNACIONAL y el FIJO de un cliente ⇒ P0481 · E8j internacional libre ⇒ se guarda · E8k formato inválido (el
  --     teléfono de un cliente sin +51) ⇒ el 23514 del CHECK de hoy · E8l con espacios alrededor del teléfono de un cliente: se
  --     rechaza sin escribir nada y QUÉ responde se mide (hoy el CHECK; con la regla, el P0481 del cliente).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c8 := pg_temp.convertir_real(540, 'CLIENTE E8 CON PERSONA');
  v_esp8 := pg_temp.juicio_de(540, 'PASO08 VEND1');
  v_l := pg_temp.lead_nuevo(v_vend2, 541, 'LEAD E8A QUE SE EDITA');
  perform pg_temp.exigir_libre('E8a', pg_temp.teln(641), null, v_l);
  perform pg_temp.rechazo_edicion('E8a-telefono-libre-y-alternativo-de-un-cliente-en-el-mismo-update', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(641), 'telefono_alternativo', pg_temp.teln(540)),
    jsonb_build_object('error', 'P0481', 'detalle', v_esp8), v_c8);

  v_ts := date_trunc('second', clock_timestamp()) - interval '3 days';
  v_c := pg_temp.sembrado(542, 'CONVERTIDO E8B ID MENOR', true, 'convertido', null, v_vend3, v_ts,
                          p_id => '00000000-0028-4000-8000-000000000801');
  v_c2 := pg_temp.sembrado(542, 'CONVERTIDO E8B ID MAYOR', true, 'convertido', null, v_vend1, v_ts,
                           p_id => 'ffffffff-0028-4000-8000-000000000801');
  v_l := pg_temp.lead_nuevo(v_vend2, 543, 'LEAD E8B QUE SE EDITA');
  perform pg_temp.exigir_libre('E8b', pg_temp.teln(542), null, v_l);
  perform pg_temp.rechazo_edicion('E8b-telefono-desempate-final-por-id', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(542)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);
  v_c := pg_temp.sembrado(544, 'CONVERTIDO E8C ID MENOR', true, 'convertido', pg_temp.dni(544), v_vend3, v_ts,
                          p_id => '00000000-0028-4000-8000-000000000802');
  v_c2 := pg_temp.sembrado(545, 'CONVERTIDO E8C ID MAYOR', true, 'convertido', pg_temp.dni(544), v_vend1, v_ts,
                           p_id => 'ffffffff-0028-4000-8000-000000000802');
  v_l := pg_temp.lead_nuevo(v_vend2, 546, 'LEAD E8C QUE SE EDITA');
  perform pg_temp.exigir_libre('E8c', pg_temp.teln(546), pg_temp.dni(544), v_l);
  perform pg_temp.rechazo_edicion('E8c-dni-desempate-final-por-id', v_vend2, v_l,
    jsonb_build_object('dni', pg_temp.dni(544)), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND3')), v_c);

  v_c := pg_temp.convertir_real(547, 'CLIENTE E8D');
  perform pg_temp.ok_edicion('E8d-el-cliente-pone-su-principal-como-su-alternativo (la rama del alternativo lo excluye; como hoy)', v_vend1, v_c,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(547)), jsonb_build_object('telefono_alternativo', pg_temp.teln(547)));

  v_l := pg_temp.lead_nuevo(v_vend2, 548, 'LEAD E8E QUE SE EDITA CON SU DNI');
  perform pg_temp.exigir_libre('E8e', pg_temp.teln(540), pg_temp.dni(548), v_l);
  perform pg_temp.rechazo_doc('E8e-documento-dni-y-telefono-de-un-cliente (el DNI tampoco queda)', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(540)), 'DNI', pg_temp.dni(548), jsonb_build_object('error', 'P0481', 'detalle', v_esp8), v_c8);
  v_l := pg_temp.lead_nuevo(v_vend2, 549, 'LEAD E8F QUE SE EDITA CON SU CE');
  perform pg_temp.rechazo_doc('E8f-documento-ce-y-alternativo-de-un-cliente (ni persona ni documento nuevos)', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(540)), 'CE', '75280054901', jsonb_build_object('error', 'P0481', 'detalle', v_esp8), v_c8);
  v_l := pg_temp.lead_nuevo(v_vend2, 550, 'LEAD E8G QUE SE EDITA CON SU DNI');
  perform pg_temp.ok_doc('E8g-documento-dni-y-telefono-libres (se guarda como hoy)', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.tel(650)), 'DNI', pg_temp.dni(550),
    jsonb_build_object('dni', pg_temp.dni(550), 'telefono', pg_temp.teln(650)), false);
  v_l := pg_temp.lead_nuevo(v_vend2, 551, 'LEAD E8G2 QUE SE EDITA CON SU PASAPORTE');
  perform pg_temp.ok_doc('E8g2-documento-pasaporte-y-alternativo-libres (se guarda y se enlaza, como hoy, a la persona de ESE pasaporte)', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(651)), 'PASAPORTE', 'E8G2X92408',
    jsonb_build_object('telefono_alternativo', pg_temp.teln(651), 'dni', null), true, true);

  v_c := pg_temp.cliente_sin_persona(552, 'CLIENTE E8H CON ALTERNATIVO INTERNACIONAL', v_vend1, false, '+19240805521');
  v_l := pg_temp.lead_nuevo(v_vend2, 553, 'LEAD E8H QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E8h-alternativo-internacional-de-un-cliente', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', '+19240805521'), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);
  v_c := pg_temp.cliente_sin_persona(554, 'CLIENTE E8I CON ALTERNATIVO FIJO', v_vend1, false, '+5119240855');
  v_l := pg_temp.lead_nuevo(v_vend2, 555, 'LEAD E8I QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E8i-alternativo-fijo-de-un-cliente', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', '+5119240855'), jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);
  v_l := pg_temp.lead_nuevo(v_vend2, 556, 'LEAD E8J QUE SE EDITA');
  perform pg_temp.ok_edicion('E8j-alternativo-internacional-libre (se guarda como hoy)', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', '+19240805599'), jsonb_build_object('telefono_alternativo', '+19240805599'));
  v_l := pg_temp.lead_nuevo(v_vend2, 557, 'LEAD E8K QUE SE EDITA');
  perform pg_temp.rechazo_edicion('E8k-alternativo-con-formato-invalido (el telefono de un cliente sin +51: el 23514 del CHECK, como hoy)', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.tel(540)),
    jsonb_build_object('error', '23514', 'mensaje', 'leads_telefono_alternativo_formato'), v_c8);
  v_l := pg_temp.lead_nuevo(v_vend2, 558, 'LEAD E8L QUE SE EDITA');
  v_ficha := pg_temp.ficha(v_l);
  v_huella := pg_temp.huella_escritura();
  v_res := pg_temp.editar(v_vend2, v_l, jsonb_build_object('telefono_alternativo', ' ' || pg_temp.teln(540) || ' '));
  perform pg_temp.medida(format('E8l · alternativo con espacios alrededor del teléfono de un cliente («%s») → %s', ' ' || pg_temp.teln(540) || ' ', v_res));
  -- Ronda 4 (Codex r2): con la migración se EXIGE el P0481 con el veredicto del cliente; sin ella, el 23514 de formato de hoy.
  perform pg_temp.reg('E8l-alternativo-con-espacios-de-un-cliente (sin escribir; con la migración, el P0481 del cliente; sin ella, el 23514 de hoy)',
    case when (case when v_pieza is not null
                    then v_res like 'P0481|%' and pg_temp.a_jsonb((pg_temp.error_de(v_res)).detalle) = v_esp8
                    else v_res like '23514|%' end)
              and pg_temp.ficha(v_l) is not distinct from v_ficha and pg_temp.huella_escritura() is not distinct from v_huella then ''
         else format(E'FALLO E8l-alternativo-con-espacios-de-un-cliente: se esperaba %s sin escribir nada y llegó %s\n',
                     case when v_pieza is not null then 'el P0481 con el veredicto del cliente (la migración está aplicada)'
                          else 'el 23514 de formato de hoy (sin la migración)' end, v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A. EL ALTA (núcleo del 2.4 + 2.7) con el ALTERNATIVO (D-30) ⇒ «ya es cliente» como RESPUESTA (no error), sin crear nada.
  --    A1 el alternativo tecleado es el teléfono de un cliente · A2 el teléfono tecleado es el alternativo de un cliente · A3 el
  --    alternativo tecleado es el alternativo de un cliente · A4 (negativo) alternativo libre ⇒ `creado` · A5 (el 2.7) solo el
  --    teléfono de un cliente ⇒ respuesta, no el P0481 del disparador · A6 el alternativo (un teléfono) manda sobre el DNI.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(40, 'CLIENTE A1');
  v_esp := pg_temp.juicio_de(40, 'PASO08 VEND1');
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(240), null) ->> 'estado' <> 'libre' then raise exception 'ENSAYO ABORTADO: A1 sin «libre»'; end if;
  perform pg_temp.bloqueo_alta('A1-alta-con-el-telefono-del-cliente-como-alternativo', v_vend2, pg_temp.tel(240), null, pg_temp.teln(40), v_esp, v_c);

  v_c := pg_temp.convertir_real(41, 'CLIENTE A2 CON ALTERNATIVO', null, pg_temp.teln(341));
  v_esp := pg_temp.juicio_de(41, 'PASO08 VEND1');
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(341), null) ->> 'estado' <> 'libre' then raise exception 'ENSAYO ABORTADO: A2 sin «libre»'; end if;
  perform pg_temp.bloqueo_alta('A2-alta-con-el-alternativo-del-cliente-como-telefono', v_vend2, pg_temp.tel(341), null, null, v_esp, v_c);

  v_c := pg_temp.cliente_sin_persona(42, 'CLIENTE A3 SIN PERSONA CON ALTERNATIVO', v_vend1, false, pg_temp.teln(342));
  perform pg_temp.bloqueo_alta('A3-alta-con-el-alternativo-del-cliente-como-alternativo', v_vend2, pg_temp.tel(242), null, pg_temp.teln(342),
    pg_temp.sin_persona('PASO08 VEND1'), v_c);

  v_l := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_l, 'ALTA A4 CON ALTERNATIVO LIBRE', pg_temp.tel(243), null, pg_temp.teln(343));
  perform pg_temp.medida(format('A4 · alta con alternativo libre → %s', v_res));
  perform pg_temp.reg('A4-alta-con-alternativo-libre (creado como hoy)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'creado'
              and (select l.telefono_alternativo from crm.leads l where l.id = v_l) is not distinct from pg_temp.teln(343) then ''
         else format(E'FALLO A4-alta-con-alternativo-libre: se esperaba «creado» con el alternativo %s y llegó %s\n', pg_temp.teln(343), v_res) end);

  v_c := pg_temp.cliente_sin_persona(44, 'CLIENTE A5 SIN PERSONA', v_vend1, false);
  perform pg_temp.bloqueo_alta('A5-alta-solo-por-telefono-de-un-cliente (el 2.7: respuesta, no error)', v_vend2, pg_temp.tel(44), null, null,
    pg_temp.sin_persona('PASO08 VEND1'), v_c);

  v_c := pg_temp.cliente_sin_persona(45, 'CLIENTE A6 POR TELEFONO', v_vend3, false);
  v_c2 := pg_temp.cliente_sin_persona(46, 'CLIENTE A6 POR DNI', v_vend1, false);
  perform pg_temp.bloqueo_alta('A6-el-alternativo-manda-sobre-el-dni', v_vend2, pg_temp.tel(246), pg_temp.dni(46), pg_temp.teln(45),
    pg_temp.sin_persona('PASO08 VEND3'), v_c);
  -- A7/A8 (ronda 3). El FIJO y el INTERNACIONAL de un cliente, tecleados como alternativo en OTRA forma (nacional con 0; con
  --       espacios): el alta los canoniza (`private.canonizar_contacto`) antes de juzgar ⇒ «ya es cliente».
  v_c := pg_temp.cliente_sin_persona(560, 'CLIENTE A7 CON ALTERNATIVO FIJO', v_vend1, false, '+5119240866');
  perform pg_temp.bloqueo_alta('A7-alta-con-el-fijo-de-un-cliente-tecleado-en-forma-nacional', v_vend2, pg_temp.tel(261), null, '019240866',
    pg_temp.sin_persona('PASO08 VEND1'), v_c);
  v_c := pg_temp.cliente_sin_persona(562, 'CLIENTE A8 CON ALTERNATIVO INTERNACIONAL', v_vend1, false, '+19240805621');
  perform pg_temp.bloqueo_alta('A8-alta-con-el-internacional-de-un-cliente-tecleado-con-espacios', v_vend2, pg_temp.tel(262), null, '+1 924 080 5621',
    pg_temp.sin_persona('PASO08 VEND1'), v_c);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- I. INSERT CON SESIÓN que no es el alta (D-30: «el INSERT directo, si sigue concedido, lo juzga la misma regla»). Los permisos
  --    de hoy están en la medida I0 (authenticated no tiene INSERT sobre crm.leads). Aquí se mide el disparador: un INSERT con la
  --    sesión de VEND2 y el contacto de un cliente ⇒ P0481 con el veredicto; I5 contacto libre ⇒ entra.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(50, 'CLIENTE I1');
  v_esp := pg_temp.juicio_de(50, 'PASO08 VEND1');
  perform pg_temp.rechazo_insert('I1-insert-con-sesion-con-el-telefono-de-un-cliente', v_vend2, pg_temp.teln(50), null, null,
    jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);
  v_c := pg_temp.convertir_real(51, 'CLIENTE I2');
  v_esp := pg_temp.juicio_de(51, 'PASO08 VEND1');
  perform pg_temp.rechazo_insert('I2-insert-con-sesion-con-el-telefono-del-cliente-como-alternativo', v_vend2, pg_temp.teln(251), pg_temp.teln(51), null,
    jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);
  v_c := pg_temp.convertir_real(52, 'CLIENTE I3 CON ALTERNATIVO', null, pg_temp.teln(352));
  v_esp := pg_temp.juicio_de(52, 'PASO08 VEND1');
  perform pg_temp.rechazo_insert('I3-insert-con-sesion-con-el-alternativo-del-cliente-como-telefono', v_vend2, pg_temp.teln(352), null, null,
    jsonb_build_object('error', 'P0481', 'detalle', v_esp), v_c);
  v_c := pg_temp.cliente_sin_persona(53, 'CLIENTE I4 SIN PERSONA', v_vend1, false);
  if private.verificar_disponibilidad_lead_impl(pg_temp.teln(253), pg_temp.dni(53)) ->> 'estado' <> 'libre' then raise exception 'ENSAYO ABORTADO: I4 sin «libre»'; end if;
  perform pg_temp.rechazo_insert('I4-insert-con-sesion-con-el-dni-de-un-cliente-sin-persona', v_vend2, pg_temp.teln(253), null, pg_temp.dni(53),
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);
  v_l := gen_random_uuid();
  v_res := pg_temp.insertar(v_vend2, v_l, 'INSERT CON SESION LIBRE', pg_temp.teln(254), null, null);
  perform pg_temp.reg('I5-insert-con-sesion-con-un-contacto-libre (entra como hoy)',
    case when v_res like 'ok|%' and pg_temp.ficha(v_l) is not null then ''
         else format(E'FALLO I5-insert-con-sesion-con-un-contacto-libre: se esperaba que entrara y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- B. LA CARGA DE BASES NO CAMBIA (D-30): su contacto nace DORMIDO por su válvula (`private.bases_carga_nace_dormido`) y con la
  --    sesión de quien carga; la regla no lo juzga. B1 una fila con el ALTERNATIVO de un cliente (la carga no lo mira: hoy se carga)
  --    ⇒ `cargada` · B2 una fila con el teléfono de un cliente ⇒ `ya_existia` (su envoltorio, como hoy).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(55, 'CLIENTE B CON ALTERNATIVO', null, pg_temp.teln(355));
  begin
    perform pg_temp.sesion(v_sup1);
    v_r := crm.crear_base(gen_random_uuid(), 'BASE ENSAYO 2.8', 'archivo', null, 'ensayo-2-8.csv');
    perform pg_temp.sesion(null);
  exception when others then
    perform pg_temp.sesion(null);
    raise exception 'ENSAYO ABORTADO: SUP1 no pudo crear la base del caso B (% %)', sqlstate, sqlerrm;
  end;
  v_base := (v_r ->> 'base_id')::uuid;
  v_res := pg_temp.cargar(v_sup1, v_base, jsonb_build_array(jsonb_build_object('fila', 1, 'nombre', 'CONTACTO B1 DE LA BASE', 'telefono', pg_temp.tel(355))));
  perform pg_temp.medida(format('B1 · lote con el alternativo de un cliente → %s', v_res));
  perform pg_temp.reg('B1-carga-de-bases-con-el-alternativo-de-un-cliente (cargada como hoy)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb #>> '{filas,0,veredicto}') = 'cargada' then ''
         else format(E'FALLO B1-carga-de-bases-con-el-alternativo-de-un-cliente: se esperaba la fila «cargada» (hoy) y llegó %s\n', v_res) end);
  v_res := pg_temp.cargar(v_sup1, v_base, jsonb_build_array(jsonb_build_object('fila', 1, 'nombre', 'CONTACTO B2 DE LA BASE', 'telefono', pg_temp.tel(55))));
  perform pg_temp.medida(format('B2 · lote con el teléfono de un cliente → %s', v_res));
  perform pg_temp.reg('B2-carga-de-bases-con-el-telefono-de-un-cliente (ya_existia como hoy)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb #>> '{filas,0,veredicto}') = 'ya_existia' then ''
         else format(E'FALLO B2-carga-de-bases-con-el-telefono-de-un-cliente: se esperaba la fila «ya_existia» (hoy) y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- S. SIN SESIÓN NO CAMBIA: S1 el importador (`crm.importar_lead_fn`, sin usuario: su contrato es NO consultar la disponibilidad
  --    comercial) con el teléfono de un cliente ⇒ `importado` · S2 un UPDATE sin sesión del teléfono · S3 del alternativo ⇒ entran.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.convertir_real(56, 'CLIENTE S1');
  perform pg_temp.sesion(null);
  begin
    v_r := crm.importar_lead_fn(jsonb_build_object('nombre_completo', 'IMPORTADO S1', 'telefono', pg_temp.tel(56), 'origen', 'landing',
                                                   'monto_estimado', '3000', 'moneda', 'PEN'));
    v_res := 'ok|' || v_r::text;
  exception when others then
    v_res := sqlstate || '|' || sqlerrm;
  end;
  perform pg_temp.medida(format('S1 · importador sin sesión con el teléfono de un cliente → %s', v_res));
  perform pg_temp.reg('S1-importador-sin-sesion-con-el-telefono-de-un-cliente (importado como hoy)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'resultado') = 'importado' then ''
         else format(E'FALLO S1-importador-sin-sesion-con-el-telefono-de-un-cliente: se esperaba «importado» (hoy) y llegó %s\n', v_res) end);
  v_c := pg_temp.convertir_real(57, 'CLIENTE S2');
  v_c2 := pg_temp.convertir_real(58, 'CLIENTE S3');
  v_l := pg_temp.lead_nuevo(v_vend2, 157, 'LEAD S2');
  v_res := pg_temp.actualizar(null, v_l, jsonb_build_object('telefono', pg_temp.teln(57)), false);
  perform pg_temp.reg('S2-update-sin-sesion-del-telefono-hacia-un-cliente (entra como hoy)',
    case when v_res = 'ok|1' and (select l.telefono from crm.leads l where l.id = v_l) = pg_temp.teln(57) then ''
         else format(E'FALLO S2-update-sin-sesion-del-telefono-hacia-un-cliente: se esperaba que entrara y llegó %s\n', v_res) end);
  v_res := pg_temp.actualizar(null, v_l, jsonb_build_object('telefono_alternativo', pg_temp.teln(58)), false);
  perform pg_temp.reg('S3-update-sin-sesion-del-alternativo-hacia-un-cliente (entra como hoy)',
    case when v_res = 'ok|1' and (select l.telefono_alternativo from crm.leads l where l.id = v_l) = pg_temp.teln(58) then ''
         else format(E'FALLO S3-update-sin-sesion-del-alternativo-hacia-un-cliente: se esperaba que entrara y llegó %s\n', v_res) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- P. BAJO LA VÁLVULA PRIVILEGIADA EL DNI NO SE JUZGA (otras puertas, D-30; hasta D-38): P1 un UPDATE del DNI con sesión bajo la
  --    válvula `crm.op_privilegiada` (como la conversión y la corrección de documento) hacia el DNI de un cliente ⇒ entra como hoy (el
  --    teléfono y el alternativo bajo la válvula sí se juzgan desde la ronda 3: sección V).
  --    P2 (medida) la preparación REAL de la conversión de un lead con el DNI de un cliente retirado sin persona.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(59, 'CLIENTE P1 SIN PERSONA', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 159, 'LEAD P1');
  perform pg_temp.exigir_libre('P1', pg_temp.teln(159), pg_temp.dni(59), v_l);
  v_res := pg_temp.actualizar(v_vend2, v_l, jsonb_build_object('dni', pg_temp.dni(59)), true);
  perform pg_temp.medida(format('P1 · UPDATE privilegiado del DNI hacia un cliente → %s', v_res));
  perform pg_temp.reg('P1-update-privilegiado-del-dni-hacia-un-cliente (entra como hoy)',
    case when v_res = 'ok|1' and (select l.dni from crm.leads l where l.id = v_l) = pg_temp.dni(59) then ''
         else format(E'FALLO P1-update-privilegiado-del-dni-hacia-un-cliente: se esperaba que entrara (hoy) y llegó %s\n', v_res) end);
  v_c := pg_temp.cliente_sin_persona(60, 'CLIENTE P2 SIN PERSONA RETIRADO', v_vend1, true);
  v_l := pg_temp.lead_nuevo(v_vend2, 160, 'LEAD P2');
  begin
    perform pg_temp.sesion(v_vend2);
    v_r := crm.preparar_persona_lead_inversion_fn(v_l, 'DNI', pg_temp.dni(60), 'LEAD P2');
    perform pg_temp.sesion(null);
    v_res := 'ok|' || v_r::text || ' · dni del lead=' || coalesce((select l.dni from crm.leads l where l.id = v_l), '-');
  exception when others then
    perform pg_temp.sesion(null);
    v_res := sqlstate || '|' || sqlerrm;
  end;
  perform pg_temp.medida(format('P2 · preparar la conversión de un lead con el DNI de un cliente retirado sin persona → %s', v_res));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- F. RONDA 3 (auditor F1, Codex F1): EL ALTERNATIVO SIN VALIDAR (`telefono_alternativo_crudo`). Solo lo escribe la importación, sin
  --    sesión; con sesión —también bajo cualquier válvula— no se pone ni cambia a un valor no nulo ⇒ 42501 «El alternativo sin validar
  --    solo lo pone la importación», sin escribir nada. Lo que se intenta poner es el teléfono de un cliente (el PATCH del auditor).
  --    F1 un UPDATE cuyo SET trae SOLO la cruda (prueba la lista de columnas) · F1b el PATCH del auditor (quita el alternativo y pone
  --    la cruda) · F2 de una cruda heredada a otra · F3a conservarla (el mismo valor en el SET) · F3b conservarla sin tocarla mientras
  --    la ficha cambia el teléfono · F4 borrarla · F4b cambiarla por un alternativo validado · F5 un INSERT con cruda · F6a/F6b sin
  --    sesión (UPDATE; el importador) ⇒ como hoy · F7u/F7i el UPDATE y el INSERT bajo CADA válvula · F8 (en V) con las dos válvulas
  --    de la corrección de documento.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_c := pg_temp.cliente_sin_persona(500, 'CLIENTE F SIN PERSONA', v_vend1, false);
  v_esp_cruda := jsonb_build_object('error', '42501', 'mensaje', 'El alternativo sin validar solo lo pone la importación');
  v_f1 := pg_temp.lead_nuevo(v_vend2, 501, 'LEAD F1');
  perform pg_temp.exigir_cruda('F1', v_f1, null);
  perform pg_temp.rechazo_update('F1-update-con-sesion-que-solo-pone-la-cruda (42501)', v_vend2, v_f1,
    jsonb_build_object('telefono_alternativo_crudo', pg_temp.teln(500)), '{}', v_esp_cruda, v_c);
  v_l := pg_temp.lead_nuevo(v_vend2, 502, 'LEAD F1B CON ALTERNATIVO', null, pg_temp.teln(602));
  perform pg_temp.exigir_cruda('F1b', v_l, null);
  perform pg_temp.rechazo_update('F1b-update-con-sesion-que-quita-el-alternativo-y-pone-la-cruda (el PATCH del auditor; 42501)', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', null, 'telefono_alternativo_crudo', pg_temp.teln(500)), '{}', v_esp_cruda, v_c);
  -- Cinco leads con una cruda HEREDADA (estado declarado: la puso la importación, sin sesión; aquí nacen por la puerta real y la cruda
  -- se siembra con los disparadores apagados, para no depender del importador, que se prueba aparte en F6b). Ronda 4 (Codex r2): CADA
  -- caso el suyo y su estado inicial afirmado: en ROJO lo que F2 acepta no contamina a F3a/F3b/F4 (antes F3a «conservaba» restaurando).
  v_li := pg_temp.lead_nuevo(v_vend2, 506, 'LEAD F2 CON ALTERNATIVO SIN VALIDAR HEREDADO');
  v_li2 := pg_temp.lead_nuevo(v_vend2, 508, 'LEAD F4B CON ALTERNATIVO SIN VALIDAR HEREDADO');
  v_li3 := pg_temp.lead_nuevo(v_vend2, 530, 'LEAD F3A CON ALTERNATIVO SIN VALIDAR HEREDADO');
  v_li4 := pg_temp.lead_nuevo(v_vend2, 531, 'LEAD F3B CON ALTERNATIVO SIN VALIDAR HEREDADO');
  v_li5 := pg_temp.lead_nuevo(v_vend2, 532, 'LEAD F4 CON ALTERNATIVO SIN VALIDAR HEREDADO');
  set local session_replication_role = replica;
  update crm.leads set telefono_alternativo_crudo = '01-445-7890 anexo 12' where id in (v_li, v_li3, v_li4, v_li5);
  update crm.leads set telefono_alternativo_crudo = '(01) 445 7891' where id = v_li2;
  set local session_replication_role = origin;
  if (select count(*) from crm.leads l where l.id in (v_li, v_li2, v_li3, v_li4, v_li5) and l.telefono_alternativo_crudo is not null) <> 5 then
    raise exception 'ENSAYO ABORTADO: los leads del caso F no quedaron con su alternativo sin validar heredado';
  end if;
  perform pg_temp.exigir_cruda('F2', v_li, '01-445-7890 anexo 12');
  perform pg_temp.rechazo_update('F2-update-con-sesion-de-una-cruda-heredada-a-otra (42501)', v_vend2, v_li,
    jsonb_build_object('telefono_alternativo_crudo', pg_temp.teln(500)), '{}', v_esp_cruda, v_c);
  perform pg_temp.exigir_cruda('F3a', v_li3, '01-445-7890 anexo 12');
  perform pg_temp.ok_update('F3a-conservar-la-cruda-heredada (el mismo valor en el SET; como hoy)', v_vend2, v_li3,
    jsonb_build_object('telefono_alternativo_crudo', '01-445-7890 anexo 12'), '{}',
    jsonb_build_object('telefono_alternativo_crudo', '01-445-7890 anexo 12'));
  perform pg_temp.exigir_cruda('F3b', v_li4, '01-445-7890 anexo 12');
  perform pg_temp.ok_edicion('F3b-conservar-la-cruda-heredada-sin-tocarla-mientras-cambia-el-telefono (como hoy)', v_vend2, v_li4,
    jsonb_build_object('telefono', pg_temp.tel(507)),
    jsonb_build_object('telefono', pg_temp.teln(507), 'telefono_alternativo_crudo', '01-445-7890 anexo 12'));
  perform pg_temp.exigir_cruda('F4', v_li5, '01-445-7890 anexo 12');
  perform pg_temp.ok_update('F4-borrar-la-cruda-heredada (como hoy)', v_vend2, v_li5,
    jsonb_build_object('telefono_alternativo_crudo', null), '{}', jsonb_build_object('telefono_alternativo_crudo', null));
  perform pg_temp.exigir_cruda('F4b', v_li2, '(01) 445 7891');
  perform pg_temp.ok_update('F4b-cambiar-la-cruda-por-un-alternativo-validado (como hoy)', v_vend2, v_li2,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(608), 'telefono_alternativo_crudo', null), '{}',
    jsonb_build_object('telefono_alternativo', pg_temp.teln(608), 'telefono_alternativo_crudo', null));
  perform pg_temp.rechazo_insert('F5-insert-con-sesion-con-la-cruda (42501)', v_vend2, pg_temp.teln(503), null, null, v_esp_cruda, v_c,
    pg_temp.teln(500));
  v_l := pg_temp.lead_nuevo(v_vend2, 504, 'LEAD F6A');
  perform pg_temp.ok_update('F6a-update-sin-sesion-de-la-cruda (como hoy)', null, v_l,
    jsonb_build_object('telefono_alternativo_crudo', pg_temp.teln(500)), '{}',
    jsonb_build_object('telefono_alternativo_crudo', pg_temp.teln(500)));
  begin
    perform pg_temp.sesion(null);
    v_r := crm.importar_lead_fn(jsonb_build_object('nombre_completo', 'IMPORTADO F6B', 'telefono', pg_temp.tel(505), 'origen', 'landing',
             'monto_estimado', '3000', 'moneda', 'PEN', 'telefono_alternativo_crudo', '+51 924 080 500'));
    v_res := 'ok|' || v_r::text;
  exception when others then
    v_res := sqlstate || '|' || sqlerrm;
  end;
  perform pg_temp.medida(format('F6b · importador sin sesión con la cruda «+51 924 080 500» → %s', v_res));
  perform pg_temp.reg('F6b-importador-sin-sesion-con-la-cruda (importado como hoy)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'resultado') = 'importado'
              and (select l.telefono_alternativo_crudo from crm.leads l
                    where l.id = nullif(substr(v_res, 4)::jsonb ->> 'lead_id', '')::uuid) = '+51 924 080 500' then ''
         else format(E'FALLO F6b-importador-sin-sesion-con-la-cruda: se esperaba «importado» con la cruda guardada (hoy) y llegó %s\n', v_res) end);
  v_i := 0;
  for v_txt in select x from jsonb_array_elements_text(
      '["crm.op_privilegiada", "crm.op_privilegiada+crm.correccion_documento", "crm.dni_por_puerta", "crm.op_bases_carga"]'::jsonb) x loop
    v_i := v_i + 1;
    -- Ronda 4 (Codex r2): cada F7u con su lead, sin cruda: en ROJO, un cambio real de NULL a no nulo (antes reenviaban la de F1).
    v_f7 := pg_temp.lead_nuevo(v_vend2, 514 + v_i, format('LEAD F7U%s', v_i));
    perform pg_temp.exigir_cruda(format('F7u%s', v_i), v_f7, null);
    perform pg_temp.rechazo_update(format('F7u%s-update-con-sesion-solo-de-la-cruda-bajo-%s (42501)', v_i, v_txt), v_vend2, v_f7,
      jsonb_build_object('telefono_alternativo_crudo', pg_temp.teln(500)), string_to_array(v_txt, '+'), v_esp_cruda, v_c);
    perform pg_temp.rechazo_insert(format('F7i%s-insert-con-sesion-con-la-cruda-bajo-%s (42501)', v_i, v_txt), v_vend2, pg_temp.teln(509 + v_i),
      null, null, v_esp_cruda, v_c, pg_temp.teln(500), string_to_array(v_txt, '+'));
  end loop;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- V. RONDA 3 (auditor F3, Codex F3): BAJO LA VÁLVULA PRIVILEGIADA SE JUZGAN EL TELÉFONO Y EL ALTERNATIVO; solo el DNI queda fuera
  --    (hasta D-38: P1). V1/V2 un UPDATE con sesión bajo `crm.op_privilegiada` que pone el teléfono / el alternativo de un cliente ⇒
  --    P0481. Con las DOS válvulas de la corrección de documento (`crm.op_privilegiada` + `crm.correccion_documento`), sobre un lead
  --    ENLAZADO a su persona (la forma de su salida anticipada): V5 el DNI y el alternativo de un cliente ⇒ P0481 · V6 el DNI y el
  --    teléfono de un cliente ⇒ P0481 · F8 el DNI y la cruda ⇒ 42501 · V4 SOLO el DNI ⇒ entra como hoy (la salida de la corrección).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- (Cada caso con su lead: en el ROJO lo que hoy se acepta no contamina al siguiente. Dos clientes: V1/V2 y V5/V6/F8.)
  v_c := pg_temp.cliente_sin_persona(520, 'CLIENTE V1 SIN PERSONA', v_vend1, false);
  v_l := pg_temp.lead_nuevo(v_vend2, 521, 'LEAD V1');
  perform pg_temp.exigir_libre('V1', pg_temp.teln(520), null, v_l);
  perform pg_temp.rechazo_update('V1-update-privilegiado-del-telefono-hacia-un-cliente', v_vend2, v_l,
    jsonb_build_object('telefono', pg_temp.teln(520)), array['crm.op_privilegiada'],
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);
  v_l := pg_temp.lead_nuevo(v_vend2, 528, 'LEAD V2');
  perform pg_temp.rechazo_update('V2-update-privilegiado-del-alternativo-hacia-un-cliente', v_vend2, v_l,
    jsonb_build_object('telefono_alternativo', pg_temp.teln(520)), array['crm.op_privilegiada'],
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);
  v_c := pg_temp.cliente_sin_persona(527, 'CLIENTE V5 SIN PERSONA', v_vend1, false);
  v_le := pg_temp.lead_enlazado(v_vend2, 523, 'LEAD V5 ENLAZADO A SU PERSONA');
  perform pg_temp.rechazo_update('V5-correccion-de-documento-dni-y-alternativo-de-un-cliente (las dos valvulas)', v_ger, v_le,
    jsonb_build_object('dni', pg_temp.dni(623), 'telefono_alternativo', pg_temp.teln(527)), array['crm.op_privilegiada', 'crm.correccion_documento'],
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);
  v_le := pg_temp.lead_enlazado(v_vend2, 524, 'LEAD V6 ENLAZADO A SU PERSONA');
  perform pg_temp.exigir_libre('V6', pg_temp.teln(527), pg_temp.dni(624), v_le);
  perform pg_temp.rechazo_update('V6-correccion-de-documento-dni-y-telefono-de-un-cliente (las dos valvulas)', v_ger, v_le,
    jsonb_build_object('dni', pg_temp.dni(624), 'telefono', pg_temp.teln(527)), array['crm.op_privilegiada', 'crm.correccion_documento'],
    jsonb_build_object('error', 'P0481', 'detalle', pg_temp.sin_persona('PASO08 VEND1')), v_c);
  v_le := pg_temp.lead_enlazado(v_vend2, 525, 'LEAD F8 ENLAZADO A SU PERSONA');
  perform pg_temp.rechazo_update('F8-correccion-de-documento-dni-y-cruda (las dos valvulas; 42501)', v_ger, v_le,
    jsonb_build_object('dni', pg_temp.dni(625), 'telefono_alternativo_crudo', pg_temp.teln(527)),
    array['crm.op_privilegiada', 'crm.correccion_documento'], v_esp_cruda, v_c);
  v_le := pg_temp.lead_enlazado(v_vend2, 526, 'LEAD V4 ENLAZADO A SU PERSONA');
  perform pg_temp.ok_update('V4-correccion-de-documento-solo-el-dni (las dos valvulas; entra como hoy)', v_ger, v_le,
    jsonb_build_object('dni', pg_temp.dni(626)), array['crm.op_privilegiada', 'crm.correccion_documento'],
    jsonb_build_object('dni', pg_temp.dni(626)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- R. EL REINTENTO DEL 2.4 NO CAMBIA aunque el alternativo tecleado sea ya el teléfono de un cliente (heredado, sembrado tras la
  --    primera reactivación). Ronda 3 (Codex, hueco 7): con precondiciones que distinguen CONSERVAR de REESCRIBIR el alternativo. La
  --    ficha nace con su alternativo W; la primera reactivación se teclea con otro, Z: R1a la ficha conserva W (no escribe el
  --    tecleado); tras un segundo retiro y un cliente nuevo con el teléfono Z, R1 el reintento con el mismo p_id vuelve a reactivar LA
  --    MISMA ficha, que sigue con W: ningún lead acaba con el teléfono del cliente.
  --    R2/R3 (MEDIDAS, sin arreglar: D-25 deja los heredados; auditor, hueco [H]): un alta NUEVA que reactiva un retirado cuyo
  --    alternativo (R2) o teléfono (R3) CONSERVADO es de un cliente; R3a con el cliente activo, R3b con el cliente retirado.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA R1 RETIRADA', pg_temp.tel(61), pg_temp.dni(61), pg_temp.teln(461));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1'
     or (select l.telefono_alternativo from crm.leads l where l.id = v_otra) is distinct from pg_temp.teln(461) then
    raise exception 'ENSAYO ABORTADO: no se pudo crear (con su alternativo W) y retirar la ficha del caso R1 (%)', v_res;
  end if;
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO R1', pg_temp.tel(61), pg_temp.dni(61), pg_temp.teln(361));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_otra then
    raise exception 'ENSAYO ABORTADO: la primera reactivación del caso R1 no reactivó la ficha (%)', v_res;
  end if;
  v_txt := (select l.telefono_alternativo from crm.leads l where l.id = v_otra);
  perform pg_temp.medida(format('R1a · tras la primera reactivación (tecleado el alternativo %s) la ficha tiene el alternativo %s (nació con %s)',
    pg_temp.teln(361), coalesce(v_txt, 'null'), pg_temp.teln(461)));
  perform pg_temp.reg('R1a-la-reactivacion-conserva-el-alternativo-de-la-ficha (no escribe el tecleado; como hoy)',
    case when v_txt is not distinct from pg_temp.teln(461) then ''
         else format(E'FALLO R1a-la-reactivacion-conserva-el-alternativo-de-la-ficha: la ficha quedó con el alternativo %s (nació con %s; se tecleó %s)\n',
                     coalesce(v_txt, 'null'), pg_temp.teln(461), pg_temp.teln(361)) end);
  v_c := pg_temp.sembrado(361, 'CLIENTE HEREDADO R1 CON EL ALTERNATIVO TECLEADO', false, 'convertido', null, v_vend3);
  if pg_temp.retirar(v_ger, v_otra) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha del caso R1'; end if;
  v_n := pg_temp.otros_del_cliente(v_c);
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO R1', pg_temp.tel(61), pg_temp.dni(61), pg_temp.teln(361));
  v_txt := (select l.telefono_alternativo from crm.leads l where l.id = v_otra);
  perform pg_temp.medida(format('R1 · reintento tras el segundo retiro → %s · alternativo de la ficha %s · leads con los contactos del cliente %s (antes %s)',
    v_res, coalesce(v_txt, 'null'), pg_temp.otros_del_cliente(v_c), v_n));
  perform pg_temp.reg('R1-reintento-del-2.4-con-un-alternativo-de-cliente (idéntico a hoy)',
    case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado'
              and (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid = v_otra and (select l.activo from crm.leads l where l.id = v_otra)
              and v_txt is not distinct from pg_temp.teln(461) and pg_temp.otros_del_cliente(v_c) = v_n then ''
         else format(E'FALLO R1-reintento-del-2.4-con-un-alternativo-de-cliente: se esperaba «reutilizado» con la ficha del primer rastro, que conserva su alternativo %s, y ningún lead más con los contactos del cliente; llegó %s (alternativo de la ficha %s; leads con los contactos del cliente %s, antes %s)\n',
                     pg_temp.teln(461), v_res, coalesce(v_txt, 'null'), pg_temp.otros_del_cliente(v_c), v_n) end);

  -- R2 (medida). El retirado conserva un ALTERNATIVO que es el teléfono de un cliente ACTIVO (el cliente llegó después).
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA R2 RETIRADA CON ALTERNATIVO', pg_temp.tel(581), pg_temp.dni(581), pg_temp.teln(580));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso R2 (%)', v_res;
  end if;
  v_c := pg_temp.sembrado(580, 'CLIENTE R2 CON EL ALTERNATIVO DE LA FICHA', true, 'convertido', null, v_vend3);
  v_n := pg_temp.otros_activos_del_cliente(v_c);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO R2', pg_temp.tel(581), pg_temp.dni(581));
  perform pg_temp.medida(format('R2 (D-25, sin arreglar) · alta nueva con el teléfono y el DNI de un retirado cuyo alternativo CONSERVADO es el teléfono de un cliente activo → %s · la ficha: activa=%s, alternativo=%s · leads ACTIVOS con los contactos del cliente: %s (antes %s)',
    v_res, (select l.activo::text from crm.leads l where l.id = v_otra),
    (select coalesce(l.telefono_alternativo, 'null') from crm.leads l where l.id = v_otra), pg_temp.otros_activos_del_cliente(v_c), v_n));

  -- R3 (medidas). Un retirado hallado por su DNI que conserva el TELÉFONO de un cliente (duplicado heredado, sembrado): R3a con el
  --    cliente activo, R3b con el cliente retirado. El alta teclea otro teléfono (libre) y ese DNI.
  v_c := pg_temp.sembrado(582, 'CLIENTE R3A ACTIVO', true, 'convertido', null, v_vend3);
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA R3A RETIRADA', pg_temp.tel(583), pg_temp.dni(583));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso R3a (%)', v_res;
  end if;
  set local session_replication_role = replica;
  update crm.leads set telefono = pg_temp.teln(582) where id = v_otra;
  set local session_replication_role = origin;
  v_n := pg_temp.otros_activos_del_cliente(v_c);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO R3A POR DNI', pg_temp.tel(584), pg_temp.dni(583));
  perform pg_temp.medida(format('R3a (D-25, sin arreglar) · alta nueva por el DNI de un retirado que conserva el teléfono de un cliente ACTIVO → %s · la ficha: activa=%s · leads ACTIVOS con los contactos del cliente: %s (antes %s)',
    v_res, (select l.activo::text from crm.leads l where l.id = v_otra), pg_temp.otros_activos_del_cliente(v_c), v_n));
  v_c := pg_temp.sembrado(585, 'CLIENTE R3B RETIRADO', false, 'convertido', null, v_vend3);
  v_otra := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_otra, 'FICHA R3B RETIRADA', pg_temp.tel(586), pg_temp.dni(586));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' or pg_temp.retirar(v_ger, v_otra) <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear y retirar la ficha del caso R3b (%)', v_res;
  end if;
  set local session_replication_role = replica;
  update crm.leads set telefono = pg_temp.teln(585) where id = v_otra;
  set local session_replication_role = origin;
  v_n := pg_temp.otros_activos_del_cliente(v_c);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO R3B POR DNI', pg_temp.tel(587), pg_temp.dni(586));
  perform pg_temp.medida(format('R3b (D-25, sin arreglar) · alta nueva por el DNI de un retirado que conserva el teléfono de un cliente RETIRADO → %s · la ficha: activa=%s, teléfono=%s · leads ACTIVOS con los contactos del cliente: %s (antes %s)',
    v_res, (select l.activo::text from crm.leads l where l.id = v_otra), (select l.telefono from crm.leads l where l.id = v_otra),
    pg_temp.otros_activos_del_cliente(v_c), v_n));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- K. RONDA 4 (auditor de permisos r2, P3-4): LAS CLAVES DE CANDADO QUE PIDE EL DISPARADOR. Con la migración, el alternativo VIEJO
  --    y el NUEVO (UPDATE) y el alternativo (INSERT) entran en el candado de contacto con la MISMA clave que el teléfono principal
  --    para el mismo número (`telefono:` + la forma de `private.normalizar_telefono`): la carrera del alternativo queda serializada (la
  --    espera real entre dos sesiones: `espera.sh`). Cada caso lee `pg_locks` antes y después de UNA escritura, en una subtransacción
  --    que se deshace; cada lead nace por la puerta real (con su episodio) con un número auxiliar y recibe los contactos del caso con
  --    los disparadores apagados: sus claves no estaban tomadas (si lo estuvieran, el ensayo aborta) y los números son nuevos. K1 solo el teléfono (el alternativo, que no cambia, también se bloquea) · K2 el alternativo de W a X ·
  --    K3 de nada a X · K4 de W a nada · K5 teléfono y alternativo a la vez · K6 un INSERT con alternativo · K7a/K7 la MISMA clave:
  --    la que pide X como teléfono es la que pidió X como alternativo en K2 · K8 un fijo · K9 un internacional · K10 un internacional
  --    de 9 dígitos (comparte clave con el móvil peruano «+51» + esos dígitos: una espera de más, conservadora; medido).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l := pg_temp.lead_para_claves(931, 'LEAD K1', pg_temp.teln(901), pg_temp.teln(902), pg_temp.dni(901));
  perform pg_temp.juzgar_claves('K1-update-solo-del-telefono (el alternativo, que no cambia, tambien se bloquea)', v_vend1,
    format('update crm.leads set telefono = %L where id = %L', pg_temp.teln(903), v_l),
    array['telefono:' || pg_temp.teln(901), 'telefono:' || pg_temp.teln(903), 'telefono:' || pg_temp.teln(902), 'dni:' || pg_temp.dni(901)],
    array[pg_temp.teln(901), pg_temp.teln(903), pg_temp.teln(902), pg_temp.dni(901)]);
  v_l := pg_temp.lead_para_claves(932, 'LEAD K2', pg_temp.teln(904), pg_temp.teln(905), pg_temp.dni(904));
  v_k2 := pg_temp.juzgar_claves('K2-update-del-alternativo-de-W-a-X (el viejo y el nuevo)', v_vend1,
    format('update crm.leads set telefono_alternativo = %L where id = %L', pg_temp.teln(906), v_l),
    array['telefono:' || pg_temp.teln(904), 'telefono:' || pg_temp.teln(905), 'telefono:' || pg_temp.teln(906), 'dni:' || pg_temp.dni(904)],
    array[pg_temp.teln(904), pg_temp.teln(905), pg_temp.teln(906), pg_temp.dni(904)]);
  v_l := pg_temp.lead_para_claves(933, 'LEAD K3', pg_temp.teln(907), null, pg_temp.dni(907));
  perform pg_temp.juzgar_claves('K3-update-del-alternativo-de-nada-a-X', v_vend1,
    format('update crm.leads set telefono_alternativo = %L where id = %L', pg_temp.teln(908), v_l),
    array['telefono:' || pg_temp.teln(907), 'telefono:' || pg_temp.teln(908), 'dni:' || pg_temp.dni(907)],
    array[pg_temp.teln(907), pg_temp.teln(908), pg_temp.dni(907)]);
  v_l := pg_temp.lead_para_claves(934, 'LEAD K4', pg_temp.teln(909), pg_temp.teln(910), pg_temp.dni(909));
  perform pg_temp.juzgar_claves('K4-update-que-quita-el-alternativo (el viejo se bloquea)', v_vend1,
    format('update crm.leads set telefono_alternativo = null where id = %L', v_l),
    array['telefono:' || pg_temp.teln(909), 'telefono:' || pg_temp.teln(910), 'dni:' || pg_temp.dni(909)],
    array[pg_temp.teln(909), pg_temp.teln(910), pg_temp.dni(909)]);
  v_l := pg_temp.lead_para_claves(935, 'LEAD K5', pg_temp.teln(911), pg_temp.teln(912), pg_temp.dni(911));
  perform pg_temp.juzgar_claves('K5-update-del-telefono-y-del-alternativo-a-la-vez', v_vend1,
    format('update crm.leads set telefono = %L, telefono_alternativo = %L where id = %L', pg_temp.teln(913), pg_temp.teln(914), v_l),
    array['telefono:' || pg_temp.teln(911), 'telefono:' || pg_temp.teln(913), 'telefono:' || pg_temp.teln(912), 'telefono:' || pg_temp.teln(914),
          'dni:' || pg_temp.dni(911)],
    array[pg_temp.teln(911), pg_temp.teln(913), pg_temp.teln(912), pg_temp.teln(914), pg_temp.dni(911)]);
  perform pg_temp.juzgar_claves('K6-insert-con-sesion-con-alternativo', v_vend2,
    format($i$insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, dni, origen, etapa, monto_estimado, moneda,
                                     vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual)
              values (gen_random_uuid(), 'LEAD K6', %L, %L, %L, 'formulario', 'nuevo', 5000, 'PEN', %L, null, true, %L, true)$i$,
           pg_temp.teln(915), pg_temp.teln(916), pg_temp.dni(915), v_vend2, v_vend2),
    array['telefono:' || pg_temp.teln(915), 'telefono:' || pg_temp.teln(916), 'dni:' || pg_temp.dni(915)],
    array[pg_temp.teln(915), pg_temp.teln(916), pg_temp.dni(915)]);
  v_l := pg_temp.lead_para_claves(937, 'LEAD K7', pg_temp.teln(917), null, pg_temp.dni(917));
  v_k7 := pg_temp.juzgar_claves('K7a-update-del-telefono-a-X (X: el alternativo de K2)', v_vend1,
    format('update crm.leads set telefono = %L where id = %L', pg_temp.teln(906), v_l),
    array['telefono:' || pg_temp.teln(917), 'telefono:' || pg_temp.teln(906), 'dni:' || pg_temp.dni(917)],
    array[pg_temp.teln(917), pg_temp.teln(906), pg_temp.dni(917)]);
  perform pg_temp.reg('K7-la-misma-clave-para-X-como-alternativo-y-como-telefono',
    case when pg_temp.clave('telefono', pg_temp.teln(906)) = any (coalesce(v_k2, '{}'::bigint[]))
              and pg_temp.clave('telefono', pg_temp.teln(906)) = any (coalesce(v_k7, '{}'::bigint[])) then ''
         else format(E'FALLO K7-la-misma-clave-para-X-como-alternativo-y-como-telefono: la clave de %s (%s) no la piden los dos: como alternativo (K2) %s · como teléfono (K7a) %s\n',
                     pg_temp.nombre_clave('telefono', pg_temp.teln(906)), pg_temp.clave('telefono', pg_temp.teln(906)),
                     case when pg_temp.clave('telefono', pg_temp.teln(906)) = any (coalesce(v_k2, '{}'::bigint[])) then 'sí' else 'NO' end,
                     case when pg_temp.clave('telefono', pg_temp.teln(906)) = any (coalesce(v_k7, '{}'::bigint[])) then 'sí' else 'NO' end) end);
  v_l := pg_temp.lead_para_claves(938, 'LEAD K8', pg_temp.teln(918), null, pg_temp.dni(918));
  perform pg_temp.juzgar_claves('K8-update-del-alternativo-a-un-fijo', v_vend1,
    format('update crm.leads set telefono_alternativo = %L where id = %L', '+5119240918', v_l),
    array['telefono:' || pg_temp.teln(918), 'telefono:+5119240918', 'dni:' || pg_temp.dni(918)],
    array[pg_temp.teln(918), '+5119240918', pg_temp.dni(918)]);
  v_l := pg_temp.lead_para_claves(939, 'LEAD K9', pg_temp.teln(919), null, pg_temp.dni(919));
  perform pg_temp.juzgar_claves('K9-update-del-alternativo-a-un-internacional', v_vend1,
    format('update crm.leads set telefono_alternativo = %L where id = %L', '+19240809190', v_l),
    array['telefono:' || pg_temp.teln(919), 'telefono:+19240809190', 'dni:' || pg_temp.dni(919)],
    array[pg_temp.teln(919), '+19240809190', pg_temp.dni(919)]);
  v_l := pg_temp.lead_para_claves(940, 'LEAD K10', pg_temp.teln(920), null, pg_temp.dni(920));
  perform pg_temp.juzgar_claves('K10-update-del-alternativo-a-un-internacional-de-9-digitos', v_vend1,
    format('update crm.leads set telefono_alternativo = %L where id = %L', '+924080921', v_l),
    array['telefono:' || pg_temp.teln(920), 'telefono:+924080921', 'dni:' || pg_temp.dni(920)],
    array[pg_temp.teln(920), '+924080921', pg_temp.dni(920)]);
  perform pg_temp.medida(format('K10 · el internacional de 9 dígitos +924080921 se bloquea como %s: %s la clave del móvil peruano %s (espera de más, conservadora; ningún veredicto cambia)',
    pg_temp.nombre_clave('telefono', '+924080921'),
    case when pg_temp.clave('telefono', '+924080921') = pg_temp.clave('telefono', pg_temp.teln(921)) then 'comparte' else 'NO comparte' end,
    pg_temp.teln(921)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C. CATÁLOGO: la ficha de la pieza común (si existe), del núcleo y del disparador; lo que no se toca, con su huella.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C1. La pieza: INVOKER de postgres, STABLE, search_path vacío y nada más, EXECUTE solo para postgres sin opción de concesión.
  if v_pieza is null then
    perform pg_temp.reg('C1 la pieza común (ausente: el laboratorio no tiene la migración)', '');
  elsif not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                      and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE') then
    perform pg_temp.reg('C1', E'FALLO C1: la pieza private.juicio_cliente_convertido no es INVOKER de postgres, STABLE, con search_path vacío y EXECUTE solo para postgres\n');
  else
    perform pg_temp.reg('C1 private.juicio_cliente_convertido: ficha y ACL', '');
  end if;
  -- C2. El núcleo: DEFINER de postgres, search_path vacío y lock_timeout, EXECUTE solo para postgres.
  if v_nucleo is null
     or not exists (select 1 from pg_proc p where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    perform pg_temp.reg('C2', E'FALLO C2: el núcleo no es DEFINER de postgres con search_path vacío y lock_timeout, con EXECUTE solo para postgres\n');
  else
    perform pg_temp.reg('C2 private.alta_reactivar_retirado: ficha y ACL', '');
  end if;
  -- C3. El disparador: DEFINER de postgres, search_path vacío y lock_timeout, EXECUTE solo para postgres.
  if not exists (select 1 from pg_proc p where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE') then
    perform pg_temp.reg('C3', E'FALLO C3: private.trg_leads_disponibilidad_atomica no es DEFINER de postgres con search_path vacío y lock_timeout, con EXECUTE solo para postgres\n');
  else
    perform pg_temp.reg('C3 private.trg_leads_disponibilidad_atomica: ficha y ACL', '');
  end if;
  -- C4. El alta intacta (cuerpo, ficha, ACL): el 2.8 no la toca.
  if (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_alta)
       is distinct from '30109c536ef0a73a85da1eb3465b8ed2|e06eca2333bb11869d00913a004c8261'
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_alta)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false'] then
    perform pg_temp.reg('C4', E'FALLO C4: crm.crear_lead_si_disponible cambió (cuerpo 30109c53…/e06eca23… o ACL)\n');
  else
    perform pg_temp.reg('C4 crm.crear_lead_si_disponible intacta', '');
  end if;
  -- C5. El verificador intacto: las huellas que fija la carga de bases (20261004184501:178-183).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from '683c16fdcb08377af860f1aa0a18f3a1'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    perform pg_temp.reg('C5', E'FALLO C5: el verificador private.verificar_disponibilidad_lead_impl cambió (la carga de bases dejaría de instalarse)\n');
  else
    perform pg_temp.reg('C5 verificador intacto (huella de la carga de bases)', '');
  end if;
  -- C6. Lo que NO se toca, con su huella: la ficha y su puerta del DNI, las otras puertas, la carga de bases, el importador y
  --     las piezas de las que depende la regla.
  select string_agg(e.firma, ', ' order by e.firma) into v_txt
  from (values
    ('crm.editar_lead_fn(uuid,jsonb)', 'f2c1b7665ae58bea071499e04d970290'),
    ('crm.fijar_dni_lead_fn(uuid,text)', '3b92916944a76fb7bcbc3bce603e4788'),
    ('crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text)', '8e495db5e2420e11c59f4b1d68d7b1fc'),
    ('crm.fijar_documento_lead_fn(uuid,text,text,uuid,text)', 'ec9f0206cf1fea25e1462435c7f609c0'),
    ('crm.crear_lead_documento_fn(jsonb,text,text)', '3ca9432b3d83061adfda6314633bdc3e'),
    ('crm.tomar_lead_libre(text,text)', 'f755d63f59dfc0e8959fefb83c7b9f9a'),
    ('crm.reabrir_lead_fn(uuid)', '65b4b0924da38eaa2c6b7dc42f44ee79'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'bf59d77929877e7a5eb46704d934363e'),
    ('crm.cargar_base_lote(uuid,uuid,jsonb)', 'fa281b7cc2ee056bec71a4dc58c3c703'),
    ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'b30f606a1fd63d5cfeae85c6b85e8339'),
    ('crm.importar_lead_fn(jsonb)', '5ba1ab45e6169c5926a01b623de49dc0'),
    ('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)', '4eebf912d4abc0b101e3c39688dc0c54'),
    ('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)', 'cbcb6c436c6b406121c9af79bb808dd1'),
    ('private.trg_leads_zz_enlaza_identidad()', '71807b0e2fa0b2cd8b2a5ca98dbf89a7'),
    ('private.juicio_persona(uuid,uuid)', '2570f6eab5ae8b076e6f759b43b9b659'),
    ('private.inversionista_canonica(uuid)', '6c7ff6001df2cb047967fa61b3ceb763'),
    ('private.bases_carga_nace_dormido(text,text,text,boolean)', 'c3d86ac0c12b8825265d3e6bbcf00476'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', 'a9ac3a87a7707e98c7cc8afbf9c663c3'),
    ('private.leads_de_personas(uuid[])', 'dbe4b65777e87c81d06abfe9a394d802'),
    ('private.persona_en_conversion(uuid,uuid)', 'ceb7cdd97c10c8489760332e727e0cba'),
    ('private.normalizar_telefono(text)', 'a65842f456827692e04f6542823f5da2'),
    ('private.canonizar_contacto(text)', '0628f8ff43ae7c4ab039653dca0bb712')) e(firma, cuerpo)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null or md5(p.prosrc) is distinct from e.cuerpo;
  perform pg_temp.reg('C6 huellas de lo que no se toca (ficha, puerta del DNI, otras puertas, carga, importador, piezas)',
    case when v_txt is null then '' else format(E'FALLO C6: cambió algo que no se toca: %s\n', v_txt) end);
  -- C7. Los dos disparadores de disponibilidad de crm.leads: el del INSERT intacto; el del UPDATE sigue siendo BEFORE UPDATE de la
  --     misma función, habilitado, con (al menos) las seis columnas de hoy; con la pieza (la migración aplicada), EXACTAMENTE esas
  --     seis más el alternativo y el alternativo sin validar (ronda 3).
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O'
     or not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'
                       and t.tgfoid = v_disp and t.tgenabled = 'O' and t.tgtype = 19
                       and (select array_agg(a.attname::text order by a.attname) from pg_attribute a
                             where a.attrelid = t.tgrelid and a.attnum = any (t.tgattr::int2[]))
                           @> array['activo', 'dni', 'etapa', 'motivo_descarte', 'no_contactar', 'telefono'])
     or (v_pieza is not null
         and (select array_agg(a.attname::text order by a.attname) from pg_trigger t
                join pg_attribute a on a.attrelid = t.tgrelid and a.attnum = any (t.tgattr::int2[])
               where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update')
             is distinct from array['activo', 'dni', 'etapa', 'motivo_descarte', 'no_contactar', 'telefono', 'telefono_alternativo',
                                    'telefono_alternativo_crudo']) then
    perform pg_temp.reg('C7', E'FALLO C7: los disparadores de disponibilidad de crm.leads no son los esperados (INSERT intacto; UPDATE de la misma función, habilitado, con sus seis columnas; con la migración, exactamente esas seis más el alternativo y el alternativo sin validar)\n');
  else
    perform pg_temp.reg('C7 disparadores de disponibilidad de crm.leads', '');
  end if;
  -- C8. El gate interno del núcleo (A-5 del 2.4): con un p_actor ajeno a la sesión ⇒ 42501.
  begin
    perform pg_temp.sesion(v_vend2);
    perform private.alta_reactivar_retirado(gen_random_uuid(), v_vend3, pg_temp.tel(1), null, v_vend3, null, '{"estado":"libre"}'::jsonb, '{}'::jsonb);
    perform pg_temp.sesion(null);
    v_res := 'ok';
  exception when others then
    perform pg_temp.sesion(null);
    v_res := sqlstate;
  end;
  perform pg_temp.reg('C8 el núcleo exige p_actor = auth.uid()',
    case when v_res = '42501' then '' else format(E'FALLO C8: con p_actor ajeno a la sesión se esperaba 42501 y llegó %s\n', v_res) end);
  perform pg_temp.medida(format('C9 huellas: núcleo md5(prosrc)=%s · md5(definición)=%s · disparador md5(prosrc)=%s · md5(definición)=%s · disparador UPDATE %s · pieza %s',
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), 'ausente'),
    coalesce((select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo), 'ausente'),
    (select md5(p.prosrc) from pg_proc p where p.oid = v_disp), (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_disp),
    (select md5(pg_get_triggerdef(t.oid)) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'),
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
