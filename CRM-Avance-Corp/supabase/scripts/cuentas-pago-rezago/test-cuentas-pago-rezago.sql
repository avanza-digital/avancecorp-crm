-- PRUEBA de 20261001233019_crm_cuentas_pago_motivo_y_rezago — SOLO BANCO Docker propio.
-- ⚠️ Jamás contra producción. Requiere siembra.sql y que el banco no tenga nada más.
-- NO deja nada escrito: todo ocurre en UNA transacción que termina en ROLLBACK y, además, cada
-- intento de pago se deshace en su propio sub-bloque (por eso las pruebas no se estorban entre sí).
-- Las aserciones cortan en la primera que falla: «FALLO [Tn …]: esperaba «…», vino «…»».
--
--   docker exec -i -e PGPASSWORD=postgres <contenedor> psql -U supabase_admin -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -v modo=antes -qAt < test-cuentas-pago-rezago.sql
--
-- Se lanza como supabase_admin y lo primero que hace es «set session authorization postgres»: todo
-- corre como postgres (la «conexión directa» de producción: session_user = postgres, sin
-- superusuario). El superusuario solo hace falta para poder cambiar la sesión a «authenticator» en
-- los actores de la API: PostgREST entra SIEMPRE como authenticator y después hace SET ROLE, y el
-- bloqueo distingue la conexión directa de la API justo por session_user. Va sentencia a sentencia
-- (usa \if y \gset de psql: no va en un solo mensaje). Hay que decir el MODO; la prueba comprueba
-- primero que el banco está de verdad en ese estado:
--
--   modo=antes    La migración NO está aplicada (o ya se revirtió): no existe ninguna de las tres
--                 funciones nuevas y el bloqueo es el cuerpo anterior. Comprueba el mundo sembrado
--                 con una consulta propia (sin funciones nuevas), que el bloqueo de hoy rechaza a
--                 todos con el texto genérico y que los contratos ok se pagan. Es también la prueba
--                 de «todo volvió al estado ANTES» después de la reversa.
--   modo=despues  La migración está aplicada y la carga hecha. Se prueba en DOS estados:
--                 · «cargado»: el banco tal como quedó (T1 después, T4, T5, T6, T7, T8, T9);
--                 · «sembrado»: dentro de la transacción se borran los vínculos que creó la carga,
--                   para tener otra vez contratos una_cuenta con la regla NUEVA puesta (la migración
--                   instala y carga en la misma transacción: ese estado no existe confirmado). Ahí
--                   van T1 antes (con el diagnóstico de verdad), T2, T3, T7, T8 y T9.
--   modo=solo_codigo  Tras reversa-solo-codigo.sql: el bloqueo es el anterior y las tres funciones
--                 nuevas no existen, pero los vínculos de la carga SIGUEN (y se pueden pagar).
--
-- QUÉ CUBRE
--   T0  precondiciones: solo la siembra, sin restos, huellas del mundo, estado según el modo, y que la
--       prueba corre en READ COMMITTED (como entra producción, y lo exige la migración que inyecta un mutante)
--   T1  censo por caso = lo sembrado; tras la carga una_cuenta = 0, ok sube en los vinculados, el resto igual
--   T2  mensaje EXACTO (23514) de cada contrato bloqueado por UPDATE, INSERT y la RPC, como admin y operaciones
--   T3  quién ve el detalle: conexión directa y service_role sí; revocada, analista, cliente y anon NUNCA;
--       tampoco una sesión de la API (session_user = authenticator) que llegue SIN claims
--   T4  camino feliz intacto: los ok se pagan (también con la cuenta vinculada inactiva), toman el
--       candado FOR SHARE del vínculo y NO llaman al diagnóstico (se sustituye por uno que solo falla)
--   T5  la carga vinculó exactamente los una_cuenta a su única cuenta ACTIVA; rastro, bitácora; nada más cambió;
--       la cuota que REZAGO-04 ya tenía pagada sigue pagada y SIN sello (la carga no inventa hechos)
--   T6  los recién vinculados ya se pagan y el pago queda sellado; al pagar la siguiente cuota de
--       REZAGO-04 se sella esa, no la que ya estaba pagada
--   T7  puerta de lectura: filas, compuerta, límites y permisos (por catálogo)
--   T8  propiedad: para CADA contrato, «el bloqueo deja pagar» ⇔ caso = ok
--   T9  privacidad: ningún mensaje lleva número de cuenta, CCI, DNI, nombres ni identificadores
--   T10 catálogo: el bloqueo conserva DEFINER, search_path, dueño y ACL; los disparadores, intactos
--
-- QUÉ NO CUBRE (va en ciclo.sh: hace falta más de una sesión, o más de una transacción)
--   · el aislamiento: migración, reversas y vincular-rezago se niegan fuera de READ COMMITTED, y por qué
--     hace falta (una segunda cuenta registrada a mitad de la carga; un pago a mitad de la reversa);
--   · los pagos en vuelo frente a la carga, a reversa.sql y al ensayo (quién espera a quién);
--   · el ensayo de producción en sus tres veredictos (PASA / INCOMPLETO / FALLA).
--
-- TRAMPAS DE ESTE BANCO (ver supabase/scripts/potencial-lead/banco/LEEME.md)
--   · Llamar a una función SIN EXECUTE bajo «set role» tumba este Postgres: los permisos se leen del
--     catálogo y los ayudantes de abajo se NIEGAN a llamar (devuelven SIN_EXECUTE) si falta el permiso.
--   · auth.uid()/auth.role() de la imagen leen request.jwt.claim.sub / .role; los de producción
--     también request.jwt.claims: la sesión fija LAS DOS formas.
--   · Ningún ayudante toca tablas ni funciones temporales mientras la sesión o el rol están cambiados.
--
-- Si cambias siembra.sql, las huellas de «constantes» dejan de valer: T0 lo dice. Se recalculan con
--   set timezone = 'UTC';
--   select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from <tabla> x;
\set ON_ERROR_STOP 1
\if :{?modo}
\else
\set modo '(sin modo)'
\endif
select current_user as conectado \gset
set session authorization postgres;
begin;
set local lock_timeout = '5s';
set local timezone = 'UTC';
select set_config('rezago.modo', :'modo', true) as modo_fijado \gset
select set_config('rezago.estado', 'sembrado', true) as estado_fijado \gset
select set_config('rezago.conectado', :'conectado', true) as conectado_fijado \gset
do $modo$
begin
  if current_setting('rezago.modo') not in ('antes', 'despues', 'solo_codigo') then
    raise exception 'FALLO [uso]: falta el modo: psql -v modo=antes|despues|solo_codigo (vino «%»)', current_setting('rezago.modo');
  end if;
end;
$modo$;
select (:'modo' = 'despues') as es_despues, (:'modo' = 'solo_codigo') as es_solo_codigo \gset

-- ── Constantes ───────────────────────────────────────────────────────────────────────────────
create temp table constantes (k text primary key, v text not null) on commit drop;
insert into constantes values
  ('marca',                     'migracion:rezago-vinculos:20261001'),
  ('md5_bloqueo_anterior',      '5efb8619e4342763ae77df2ee0bb1f61'),
  ('generico',                  'Sin cuenta de pago — requiere conciliación'),
  ('huella_cuentas',            'e0d144c74afafd1a39a83b1b3ce87ecc'),
  ('huella_vinculos_sembrados', '58efd9f78ff5818b15410b022dca16c1'),
  ('huella_contratos',          'a7a31f97c61ab33f5c337f5fb8a8d36b'),
  ('huella_cuotas',             '727339960bd0447c711bf6ce93e8120b'),
  ('cuota_pagada_de_antes',     'c9ee0000-0000-4000-8000-000000000400'),
  ('sin_permiso',               'permission denied for table cronograma_pagos');
create function pg_temp.k(p_k text) returns text language sql stable as $f$
  select c.v from constantes c where c.k = p_k;
$f$;

-- ── Aserciones (una secuencia cuenta las hechas: no se deshace con los savepoints) ────────────
create temp sequence rezago_hechas;
create function pg_temp.igual(p_que text, p_esperado text, p_obtenido text) returns void language plpgsql as $f$
begin
  if p_obtenido is distinct from p_esperado then
    raise exception 'FALLO [%]: esperaba «%», vino «%»', p_que, coalesce(p_esperado, '(null)'), coalesce(p_obtenido, '(null)');
  end if;
  perform nextval('rezago_hechas');
end;
$f$;
create function pg_temp.cierto(p_que text, p_condicion boolean, p_detalle text default null) returns void language plpgsql as $f$
begin
  if p_condicion is not true then
    raise exception 'FALLO [%]%', p_que, coalesce(': ' || p_detalle, '');
  end if;
  perform nextval('rezago_hechas');
end;
$f$;
create function pg_temp.huella(p_tabla text, p_filtro text default 'true') returns text language plpgsql as $f$
declare v text;
begin
  execute format('select md5(coalesce(string_agg(md5(to_jsonb(x)::text), '','' order by x.id), '''')) from %s x where %s',
                 p_tabla, p_filtro) into v;
  return v;
end;
$f$;

-- ── Lo sembrado, tal como debe verlo la regla (los textos son los del contrato de la migración) ──
-- caso = el caso SEMBRADO (antes de la carga) · cuenta_carga = la cuenta que la carga debe vincular
-- · cuenta_sembrada = la cuenta del vínculo que ya trae la siembra · en_moneda/otra_moneda = cuentas
-- ACTIVAS del cliente en la moneda del contrato / en la otra · mensaje = null si se puede pagar.
create temp table esperado (
  k integer primary key, contrato_id uuid not null, numero text not null, cliente_id uuid not null,
  moneda text not null, es_demo boolean not null, caso text not null, cuenta_carga uuid, cuenta_sembrada uuid,
  en_moneda integer not null, otra_moneda integer not null, mensaje text
) on commit drop;
insert into esperado
select x.k, ('c9ed0000-0000-4000-8000-0000000000' || lpad(x.k::text, 2, '0'))::uuid, 'REZAGO-' || lpad(x.k::text, 2, '0'),
       ('c9e00000-0000-4000-8000-0000000000' || x.cliente)::uuid, x.moneda, x.es_demo, x.caso,
       ('c9ec0000-0000-4000-8000-0000000000' || x.carga)::uuid, ('c9ec0000-0000-4000-8000-0000000000' || x.sembrada)::uuid,
       x.en_moneda, x.otra_moneda, x.mensaje
from (values
  ( 1, '11', 'PEN', false, 'ok',                    null, '01', 1, 0, null),
  ( 2, '12', 'PEN', false, 'ok',                    null, '02', 1, 0, null),
  ( 3, '13', 'PEN', false, 'una_cuenta',            '04', null, 1, 1, 'Contrato REZAGO-03 sin cuenta de pago: el cliente ya tiene una cuenta en soles; falta vincularla a este contrato.'),
  ( 4, '14', 'USD', false, 'una_cuenta',            '07', null, 1, 1, 'Contrato REZAGO-04 sin cuenta de pago: el cliente ya tiene una cuenta en dólares; falta vincularla a este contrato.'),
  ( 5, '15', 'PEN', false, 'una_cuenta',            '09', null, 1, 0, 'Contrato REZAGO-05 sin cuenta de pago: el cliente ya tiene una cuenta en soles; falta vincularla a este contrato.'),
  ( 6, '15', 'PEN', false, 'una_cuenta',            '09', null, 1, 0, 'Contrato REZAGO-06 sin cuenta de pago: el cliente ya tiene una cuenta en soles; falta vincularla a este contrato.'),
  ( 7, '16', 'PEN', false, 'varias_cuentas',        null, null, 2, 0, 'Contrato REZAGO-07 sin cuenta de pago: el cliente tiene 2 cuentas en soles; confirma con él en cuál cobra este contrato.'),
  ( 8, '17', 'USD', false, 'varias_cuentas',        null, null, 3, 1, 'Contrato REZAGO-08 sin cuenta de pago: el cliente tiene 3 cuentas en dólares; confirma con él en cuál cobra este contrato.'),
  ( 9, '18', 'USD', false, 'otra_moneda',           null, null, 0, 1, 'Contrato REZAGO-09 sin cuenta de pago: el contrato es en dólares y el cliente solo tiene cuenta en soles; pídele una en dólares.'),
  (10, '19', 'PEN', false, 'otra_moneda',           null, null, 0, 2, 'Contrato REZAGO-10 sin cuenta de pago: el contrato es en soles y el cliente solo tiene cuenta en dólares; pídele una en soles.'),
  (11, '20', 'USD', false, 'sin_cuenta',            null, null, 0, 0, 'Contrato REZAGO-11 sin cuenta de pago: el cliente no tiene ninguna cuenta bancaria vigente; pídele una en dólares.'),
  (12, '21', 'PEN', false, 'sin_cuenta',            null, null, 0, 0, 'Contrato REZAGO-12 sin cuenta de pago: el cliente no tiene ninguna cuenta bancaria vigente; pídele una en soles.'),
  (13, '22', 'PEN', true,  'sin_cuenta',            null, null, 0, 0, 'Contrato REZAGO-13 sin cuenta de pago: el cliente no tiene ninguna cuenta bancaria vigente; pídele una en soles.'),
  (14, '23', 'PEN', false, 'cuenta_no_corresponde', null, '16', 1, 0, 'Contrato REZAGO-14: su cuenta de pago no es del cliente o de la moneda del contrato; no se paga hasta corregirla.'),
  (15, '24', 'PEN', false, 'cuenta_no_corresponde', null, '21', 0, 1, 'Contrato REZAGO-15: su cuenta de pago no es del cliente o de la moneda del contrato; no se paga hasta corregirla.')
) as x(k, cliente, moneda, es_demo, caso, carga, sembrada, en_moneda, otra_moneda, mensaje);

-- Lo esperado en el ESTADO en curso: «sembrado» (antes de la carga) o «cargado» (la carga ya vinculó).
create function pg_temp.esperado_ahora()
returns table (k integer, contrato_id uuid, numero text, cliente_id uuid, moneda text, es_demo boolean,
               caso text, cuenta_vinculada uuid, en_moneda integer, otra_moneda integer, mensaje text)
language sql stable as $f$
  select e.k, e.contrato_id, e.numero, e.cliente_id, e.moneda, e.es_demo,
         case when s.cargado and e.caso = 'una_cuenta' then 'ok' else e.caso end,
         case when s.cargado and e.caso = 'una_cuenta' then e.cuenta_carga else e.cuenta_sembrada end,
         e.en_moneda, e.otra_moneda,
         case when s.cargado and e.caso = 'una_cuenta' then null else e.mensaje end
  from esperado e cross join (select current_setting('rezago.estado') = 'cargado' as cargado) s;
$f$;
create function pg_temp.cuota(p_k integer, p_c integer) returns uuid language sql immutable as $f$
  select ('c9ee0000-0000-4000-8000-00000000' || lpad(p_k::text, 2, '0') || lpad(p_c::text, 2, '0'))::uuid;
$f$;

-- La regla, escrita aparte de la migración y sin funciones nuevas (segunda opinión del diagnóstico).
create function pg_temp.oraculo() returns table (contrato_id uuid, caso text, en_moneda integer, otra_moneda integer)
language sql stable as $f$
  select ct.id,
         case
           when l.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
           when l.id is not null then 'cuenta_no_corresponde'
           when a.en_moneda = 1 then 'una_cuenta'
           when a.en_moneda >= 2 then 'varias_cuentas'
           when a.otra_moneda >= 1 then 'otra_moneda'
           else 'sin_cuenta'
         end,
         a.en_moneda, a.otra_moneda
  from public.contratos ct
  left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  cross join lateral (
    select (count(*) filter (where x.moneda = ct.moneda))::integer as en_moneda,
           (count(*) filter (where x.moneda <> ct.moneda))::integer as otra_moneda
    from crm.cuentas_bancarias x
    where x.cliente_id = ct.cliente_id and x.activa
  ) a;
$f$;

-- ── Actores y sesión ─────────────────────────────────────────────────────────────────────────
-- sesion = con quién entra la conexión (session_user): «postgres» es la conexión directa; la API
-- entra SIEMPRE como «authenticator» y después hace SET ROLE a rol_db. con_claims = si llegan los
-- claims del JWT (rol, y uid si lo hay). «cliente» es C, el dueño de REZAGO-03. Los cuatro
-- «sinclaims_*» son sesiones de la API que llegan sin claims: nunca deben recibir el detalle.
create temp table actores (k text primary key, sesion text not null, rol_db text, uid uuid, con_claims boolean not null) on commit drop;
insert into actores values
  ('directa',            'postgres',      null,            null, false),
  ('servicio',           'authenticator', 'service_role',  null, true),
  ('admin',              'authenticator', 'authenticated', 'c9e00000-0000-4000-8000-000000000001', true),
  ('oper',               'authenticator', 'authenticated', 'c9e00000-0000-4000-8000-000000000002', true),
  ('revocada',           'authenticator', 'authenticated', 'c9e00000-0000-4000-8000-000000000003', true),
  ('analista',           'authenticator', 'authenticated', 'c9e00000-0000-4000-8000-000000000004', true),
  ('cliente',            'authenticator', 'authenticated', 'c9e00000-0000-4000-8000-000000000013', true),
  ('anon',               'authenticator', 'anon',          null, true),
  ('sinclaims_anon',     'authenticator', 'anon',          null, false),
  ('sinclaims_auth',     'authenticator', 'authenticated', null, false),
  ('sinclaims_servicio', 'authenticator', 'service_role',  null, false),
  ('sinclaims_sin_rol',  'authenticator', null,            null, false);

-- Fija (o limpia, con p_rol nulo) los claims en LAS DOS formas. No cambia de rol.
create function pg_temp.claims(p_rol text, p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(p_rol, ''), true);
  perform set_config('request.jwt.claims',
    case when p_rol is null then ''
         when p_uid is null then json_build_object('role', p_rol)::text
         else json_build_object('sub', p_uid, 'role', p_rol)::text end, true);
end;
$f$;

-- Lo que se vio en pantalla (mensajes de error del bloqueo y de la puerta): lo revisa T9.
create temp table vistos (origen text not null, texto text not null) on commit drop;

-- UN intento de pagar una cuota como un actor y por una vía. SIEMPRE se deshace. Devuelve:
--   'PAGADO:<cuenta sellada>:<origen del sello>' · 'SIN_EFECTO' (0 filas: lo cortó la RLS o la RPC
--   devolvió null) · 'ERR:<sqlstate>:<mensaje>' · 'SIN_EXECUTE' (no se llama: tumbaría el servidor).
--   vías: update (UPDATE directo de la cuota a pagado) · insert (INSERT de una cuota ya pagada) ·
--         rpc (crm.registrar_pago_con_cuenta).
create function pg_temp.intento(p_actor text, p_via text, p_contrato uuid, p_cuota uuid, p_cci text default null)
returns text language plpgsql as $f$
declare
  a record;
  v_hoy constant date := (now() at time zone 'America/Lima')::date;
  v_rpc constant text := 'crm.registrar_pago_con_cuenta(uuid,date,numeric,text)';
  v_n bigint;
  v_id uuid;
  r text; e text; m text;
begin
  select * into strict a from actores x where x.k = p_actor;
  if p_via = 'rpc' and not has_function_privilege(coalesce(a.rol_db, a.sesion), v_rpc, 'EXECUTE') then
    return 'SIN_EXECUTE';
  end if;
  perform pg_temp.claims(case when a.con_claims then a.rol_db end, a.uid);
  if a.sesion <> 'postgres' then
    execute format('set local session authorization %I', a.sesion);
  end if;
  if a.rol_db is not null then
    execute format('set local role %I', a.rol_db);
  end if;
  begin
    if p_via = 'update' then
      update public.cronograma_pagos
         set estado = 'pagado', fecha_pago_real = v_hoy, monto_pagado = 100, registrado_por = a.uid
       where id = p_cuota;
      get diagnostics v_n = row_count;
      v_id := p_cuota;
    elsif p_via = 'insert' then
      insert into public.cronograma_pagos
        (contrato_id, numero_cuota, fecha_programada, monto_programado, estado, monto_pagado, fecha_pago_real, registrado_por)
      values (p_contrato, 90, v_hoy, 100, 'pagado', 100, v_hoy, a.uid);
      get diagnostics v_n = row_count;
    elsif p_via = 'rpc' then
      v_id := crm.registrar_pago_con_cuenta(p_cuota, v_hoy, 100, p_cci);
      v_n := case when v_id is null then 0 else 1 end;
    else
      raise exception 'vía desconocida: %', p_via;
    end if;
    execute 'set local session authorization postgres';   -- vuelve a postgres (y suelta el rol)
    if p_via = 'insert' then
      select c.id into v_id from public.cronograma_pagos c where c.contrato_id = p_contrato and c.numero_cuota = 90;
    end if;
    if v_n = 0 then
      r := 'SIN_EFECTO';
    else
      r := 'PAGADO:' || coalesce((select q.cuenta_bancaria_id::text || ':' || q.origen
                                  from crm.cuotas_cuenta_pagada q where q.cuota_id = v_id), 'sin sello');
    end if;
    raise exception using errcode = 'P0001', message = 'REZAGO_DESHACER_INTENTO';
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    if not (e = 'P0001' and m = 'REZAGO_DESHACER_INTENTO') then
      r := 'ERR:' || e || ':' || m;
    end if;
  end;
  execute 'set local session authorization postgres';
  perform pg_temp.claims(null, null);
  return r;
end;
$f$;

-- Una llamada a la puerta de lectura (p_fn sin argumentos: 'crm.cuentas_pago_motivos_fn' o
-- 'private.cuentas_pago_motivos_autorizado') como un actor. Devuelve 'OK:<filas en jsonb ordenadas>',
-- 'ERR:<sqlstate>:<mensaje>', 'SIN_EXECUTE' o 'NO_EXISTE'. Solo lee.
create function pg_temp.puerta(p_actor text, p_fn text, p_ids uuid[]) returns text language plpgsql as $f$
declare
  a record;
  v_rol text;
  v_filas jsonb;
  r text; e text; m text;
begin
  select * into strict a from actores x where x.k = p_actor;
  v_rol := coalesce(a.rol_db, a.sesion);
  if to_regprocedure('crm.cuentas_pago_motivos_fn(uuid[])') is null
     or to_regprocedure('private.cuentas_pago_motivos_autorizado(uuid[])') is null then
    return 'NO_EXISTE';
  end if;
  -- La puerta INVOKER llama a la privada con los permisos de quien llama: hacen falta LAS DOS.
  if not has_function_privilege(v_rol, 'crm.cuentas_pago_motivos_fn(uuid[])', 'EXECUTE')
     or not has_function_privilege(v_rol, 'private.cuentas_pago_motivos_autorizado(uuid[])', 'EXECUTE') then
    return 'SIN_EXECUTE';
  end if;
  perform pg_temp.claims(case when a.con_claims then a.rol_db end, a.uid);
  if a.sesion <> 'postgres' then
    execute format('set local session authorization %I', a.sesion);
  end if;
  if a.rol_db is not null then
    execute format('set local role %I', a.rol_db);
  end if;
  begin
    execute format(
      'select coalesce(jsonb_agg(jsonb_build_object(''contrato_id'', t.contrato_id, ''caso'', t.caso, ''mensaje'', t.mensaje)
                                 order by t.contrato_id), ''[]''::jsonb) from %s($1) t', p_fn)
      into v_filas using p_ids;
    r := 'OK:' || v_filas::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    r := 'ERR:' || e || ':' || m;
  end;
  execute 'set local session authorization postgres';
  perform pg_temp.claims(null, null);
  return r;
end;
$f$;

-- Quién llega al bloqueo por cada vía y qué recibe en un contrato BLOQUEADO (medido contra el
-- bloqueo vivo el 01/10/2026). GEN = el texto genérico (23514) · DET = el motivo exacto (23514)
-- · SIN_EFECTO = la RLS no le deja tocar la cuota (no llega al bloqueo) · SIN_EXECUTE = no tiene la RPC
-- · SIN_PERMISO = ni siquiera tiene permisos sobre la tabla (authenticator sin SET ROLE).
-- Un INSERT llega SIEMPRE al bloqueo: el disparador BEFORE corre antes que la RLS.
-- El detalle se le dice a: la conexión directa (sin claims y session_user distinto de authenticator),
-- el rol de servicio (por su claim) y el gestor de cartera con la membresía CRM vigente.
create temp table matriz (actor text, via text, antes text not null, despues text not null, primary key (actor, via)) on commit drop;
insert into matriz values
  ('admin',    'update', 'GEN',         'DET'),        ('admin',    'insert', 'GEN', 'DET'), ('admin',    'rpc', 'GEN',         'DET'),
  ('oper',     'update', 'GEN',         'DET'),        ('oper',     'insert', 'GEN', 'DET'), ('oper',     'rpc', 'GEN',         'DET'),
  ('directa',  'update', 'GEN',         'DET'),        ('directa',  'insert', 'GEN', 'DET'), ('directa',  'rpc', 'GEN',         'DET'),
  ('servicio', 'update', 'GEN',         'DET'),        ('servicio', 'insert', 'GEN', 'DET'), ('servicio', 'rpc', 'SIN_EXECUTE', 'SIN_EXECUTE'),
  ('revocada', 'update', 'GEN',         'GEN'),        ('revocada', 'insert', 'GEN', 'GEN'), ('revocada', 'rpc', 'GEN',         'GEN'),
  ('analista', 'update', 'SIN_EFECTO',  'SIN_EFECTO'), ('analista', 'insert', 'GEN', 'GEN'), ('analista', 'rpc', 'SIN_EFECTO',  'SIN_EFECTO'),
  ('cliente',  'update', 'SIN_EFECTO',  'SIN_EFECTO'), ('cliente',  'insert', 'GEN', 'GEN'), ('cliente',  'rpc', 'SIN_EFECTO',  'SIN_EFECTO'),
  ('anon',     'update', 'SIN_EFECTO',  'SIN_EFECTO'), ('anon',     'insert', 'GEN', 'GEN'), ('anon',     'rpc', 'SIN_EXECUTE', 'SIN_EXECUTE'),
  -- La API sin claims (auth.role() nulo, pero session_user = authenticator): NUNCA el detalle.
  ('sinclaims_anon',     'update', 'SIN_EFECTO',  'SIN_EFECTO'),  ('sinclaims_anon',     'insert', 'GEN',         'GEN'),
  ('sinclaims_anon',     'rpc',    'SIN_EXECUTE', 'SIN_EXECUTE'),
  ('sinclaims_auth',     'update', 'SIN_EFECTO',  'SIN_EFECTO'),  ('sinclaims_auth',     'insert', 'GEN',         'GEN'),
  ('sinclaims_auth',     'rpc',    'SIN_EFECTO',  'SIN_EFECTO'),
  ('sinclaims_servicio', 'update', 'GEN',         'GEN'),         ('sinclaims_servicio', 'insert', 'GEN',         'GEN'),
  ('sinclaims_servicio', 'rpc',    'SIN_EXECUTE', 'SIN_EXECUTE'),
  ('sinclaims_sin_rol',  'update', 'SIN_PERMISO', 'SIN_PERMISO'), ('sinclaims_sin_rol',  'insert', 'SIN_PERMISO', 'SIN_PERMISO'),
  ('sinclaims_sin_rol',  'rpc',    'SIN_EXECUTE', 'SIN_EXECUTE');

-- ══ T0 · Precondiciones ═════════════════════════════════════════════════════════════════════
create function pg_temp.t0_precondiciones() returns text language plpgsql as $f$
declare
  v_modo constant text := current_setting('rezago.modo');
  v text;
  v_md5 text;
begin
  perform pg_temp.cierto('T0 la prueba se lanza como supabase_admin (superusuario): lo necesita para entrar como authenticator',
    (select r.rolsuper from pg_roles r where r.rolname = current_setting('rezago.conectado')), current_setting('rezago.conectado'));
  perform pg_temp.igual('T0 tras el «set session authorization», la sesión y el rol son postgres (la conexión directa)', 'postgres/postgres',
    session_user || '/' || current_user);
  perform pg_temp.igual('T0 la prueba corre en READ COMMITTED', 'read committed', current_setting('transaction_isolation'));
  select format('%s contratos (%s sembrados), %s cuotas (%s sembradas y pendientes, %s pagada de antes), %s sellos, %s cambios de cuenta, %s cuentas, %s filas de conciliación, %s PDF',
    (select count(*) from public.contratos),
    (select count(*) from public.contratos c join esperado e on e.contrato_id = c.id),
    (select count(*) from public.cronograma_pagos),
    (select count(*) from public.cronograma_pagos q where q.id::text like 'c9ee0000-%' and q.estado = 'pendiente'),
    (select count(*) from public.cronograma_pagos q where q.id::text = pg_temp.k('cuota_pagada_de_antes') and q.estado = 'pagado'),
    (select count(*) from crm.cuotas_cuenta_pagada),
    (select count(*) from crm.contrato_cuenta_pago_cambios),
    (select count(*) from crm.cuentas_bancarias),
    (select count(*) from private.conciliacion_cuentas_p0xx),
    (select count(*) from private.contrato_pdf_jobs) + (select count(*) from private.contrato_pdfs)) into v;
  perform pg_temp.igual('T0 el banco tiene SOLO la siembra y ningún resto (si falla: siembra.sql o la limpieza de ciclo.sh)',
    '15 contratos (15 sembrados), 46 cuotas (45 sembradas y pendientes, 1 pagada de antes), 0 sellos, 0 cambios de cuenta, 21 cuentas, 0 filas de conciliación, 0 PDF', v);
  perform pg_temp.igual('T0 huella de las cuentas sembradas (¿cambió siembra.sql?)', pg_temp.k('huella_cuentas'), pg_temp.huella('crm.cuentas_bancarias'));
  perform pg_temp.igual('T0 huella de los contratos sembrados', pg_temp.k('huella_contratos'), pg_temp.huella('public.contratos'));
  perform pg_temp.igual('T0 huella de las cuotas sembradas', pg_temp.k('huella_cuotas'), pg_temp.huella('public.cronograma_pagos'));
  perform pg_temp.igual('T0 huella de los 4 vínculos sembrados', pg_temp.k('huella_vinculos_sembrados'),
    pg_temp.huella('crm.contrato_cuentas_pago', $q$x.id::text like 'c9ef0000-%'$q$));

  -- Las tres funciones nuevas: por firma exacta / por nombre (por si queda una sobrecarga suelta).
  select ((to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null)::integer
        + (to_regprocedure('private.cuentas_pago_motivos_autorizado(uuid[])') is not null)::integer
        + (to_regprocedure('crm.cuentas_pago_motivos_fn(uuid[])') is not null)::integer)::text
         || '/' ||
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where (n.nspname, p.proname) in (('private', 'cuenta_pago_diagnostico'),
                                           ('private', 'cuentas_pago_motivos_autorizado'),
                                           ('crm', 'cuentas_pago_motivos_fn')))::text
    into v;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure;
  if v_modo = 'antes' then
    perform pg_temp.igual('T0 antes: no existe ninguna de las 3 funciones nuevas (por firma/por nombre)', '0/0', v);
    perform pg_temp.igual('T0 antes: el bloqueo es el cuerpo anterior (md5 de prosrc)', pg_temp.k('md5_bloqueo_anterior'), v_md5);
    perform pg_temp.igual('T0 antes: no hay más vínculos que los 4 sembrados', '4', (select count(*) from crm.contrato_cuentas_pago)::text);
    perform pg_temp.igual('T0 antes: ningún rastro VIGENTE de la carga', '0',
      (select count(*) from private.backfill_cuentas_p0xx b
       where b.marca_actor = pg_temp.k('marca') and b.revertida_en is null)::text);
  elsif v_modo = 'solo_codigo' then
    perform pg_temp.igual('T0 solo código: no existe ninguna de las 3 funciones nuevas (por firma/por nombre)', '0/0', v);
    perform pg_temp.igual('T0 solo código: el bloqueo es el cuerpo anterior (md5 de prosrc)', pg_temp.k('md5_bloqueo_anterior'), v_md5);
    perform pg_temp.igual('T0 solo código: siguen los vínculos de la carga (4 sembrados + 4) con su rastro vigente', '8/4',
      (select count(*) from crm.contrato_cuentas_pago)::text || '/' ||
      (select count(*) from private.backfill_cuentas_p0xx b
       where b.marca_actor = pg_temp.k('marca') and b.revertida_en is null)::text);
  else
    perform pg_temp.igual('T0 después: existen las 3 funciones nuevas y ninguna sobrecarga (por firma/por nombre)', '3/3', v);
    perform pg_temp.cierto('T0 después: el bloqueo ya no es el cuerpo anterior', v_md5 is distinct from pg_temp.k('md5_bloqueo_anterior'), v_md5);
  end if;
  return format('OK T0 (%s): solo la siembra, sin restos, huellas iguales y el banco en el estado que dice el modo', v_modo);
end;
$f$;

-- ══ T10 · Catálogo del bloqueo y de sus disparadores ═════════════════════════════════════════
create function pg_temp.t10_catalogo() returns text language plpgsql as $f$
declare
  v text;
begin
  select format('definer=%s config=%s dueño=%s acl=%s retorna=%s', p.prosecdef::text, coalesce(p.proconfig::text, '(sin config)'),
                p.proowner::regrole::text, coalesce(p.proacl::text, '(acl por defecto: PUBLIC ejecuta)'), p.prorettype::regtype::text)
    into v
  from pg_proc p where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure;
  perform pg_temp.igual('T10 el bloqueo conserva DEFINER, search_path vacío, dueño y ACL',
    'definer=true config={"search_path=\"\""} dueño=postgres acl={postgres=X/postgres} retorna=trigger', v);

  select string_agg(t.tgname || '|' || t.tgenabled::text || '|' || t.tgtype::text || '|' || n.nspname || '.' || p.proname,
                    ' · ' order by t.tgname) into v
  from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace n on n.oid = p.pronamespace
  where t.tgrelid = 'public.cronograma_pagos'::regclass and not t.tgisinternal;
  perform pg_temp.igual('T10 los 8 disparadores de public.cronograma_pagos: mismo nombre, habilitados, misma forma y función',
       'trg_audit_cronograma_pago|O|17|public.log_audit_change'
    || ' · trg_audit_cronograma_pago_alta_baja|O|13|public.log_audit_change'
    || ' · trg_cronograma_pagos_00_documental_congelado|O|31|private.proteger_cronograma_documental'
    || ' · trg_cronograma_pagos_10_exigir_cuenta_pago_insert|O|7|private.exigir_cuenta_pago_cronograma'
    || ' · trg_cronograma_pagos_10_exigir_cuenta_pago_update|O|19|private.exigir_cuenta_pago_cronograma'
    || ' · trg_cronograma_pagos_20_sellar_cuenta_insert|O|5|private.sellar_cuenta_cuota_pagada'
    || ' · trg_cronograma_pagos_20_sellar_cuenta_update|O|17|private.sellar_cuenta_cuota_pagada'
    || ' · trg_proteger_cuotas_contrato_cerrado|O|19|public.proteger_cuotas_contrato_cerrado', v);

  perform pg_temp.igual('T10 el disparador de INSERT del bloqueo no cambió',
    'CREATE TRIGGER trg_cronograma_pagos_10_exigir_cuenta_pago_insert BEFORE INSERT ON public.cronograma_pagos FOR EACH ROW WHEN ((new.estado = ''pagado''::text)) EXECUTE FUNCTION private.exigir_cuenta_pago_cronograma()',
    (select pg_get_triggerdef(t.oid) from pg_trigger t
     where t.tgrelid = 'public.cronograma_pagos'::regclass and t.tgname = 'trg_cronograma_pagos_10_exigir_cuenta_pago_insert'));
  perform pg_temp.igual('T10 el disparador de UPDATE del bloqueo no cambió',
    'CREATE TRIGGER trg_cronograma_pagos_10_exigir_cuenta_pago_update BEFORE UPDATE OF estado ON public.cronograma_pagos FOR EACH ROW WHEN (((old.estado IS DISTINCT FROM ''pagado''::text) AND (new.estado = ''pagado''::text))) EXECUTE FUNCTION private.exigir_cuenta_pago_cronograma()',
    (select pg_get_triggerdef(t.oid) from pg_trigger t
     where t.tgrelid = 'public.cronograma_pagos'::regclass and t.tgname = 'trg_cronograma_pagos_10_exigir_cuenta_pago_update'));

  select string_agg(t.tgname || '|' || t.tgenabled::text, ' · ' order by t.tgname) into v
  from pg_trigger t where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass and not t.tgisinternal;
  perform pg_temp.igual('T10 los 3 disparadores de crm.contrato_cuentas_pago siguen habilitados (coherencia, inmutable, bitácora)',
    'trg_audit_contrato_cuentas_pago|O · trg_contrato_cuenta_pago_00_inmutable|O · trg_contrato_cuenta_pago_coherente|O', v);
  return 'OK T10: el bloqueo conserva DEFINER, search_path, dueño y ACL; 8 + 3 disparadores intactos';
end;
$f$;

-- ══ T7 (catálogo) · Forma y permisos de las tres funciones nuevas, SIN llamarlas ═════════════
create function pg_temp.t7_catalogo() returns text language plpgsql as $f$
declare
  f record;
  v text;
begin
  for f in
    select * from (values
      ('private.cuenta_pago_diagnostico(uuid[])',
       'definer=false search_path_vacio=true dueño=postgres argumentos=p_contrato_ids uuid[] retorna=TABLE(contrato_id uuid, numero_contrato text, cliente_id uuid, moneda text, estado text, es_demo boolean, caso text, cuentas_en_moneda integer, cuentas_otra_moneda integer, mensaje text) ejecutan=postgres',
       'public=false anon=false authenticated=false service_role=false'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])',
       'definer=true search_path_vacio=true dueño=postgres argumentos=p_contrato_ids uuid[] retorna=TABLE(contrato_id uuid, caso text, mensaje text) ejecutan=authenticated,postgres',
       'public=false anon=false authenticated=true service_role=false'),
      ('crm.cuentas_pago_motivos_fn(uuid[])',
       'definer=false search_path_vacio=true dueño=postgres argumentos=p_contrato_ids uuid[] retorna=TABLE(contrato_id uuid, caso text, mensaje text) ejecutan=authenticated,postgres',
       'public=false anon=false authenticated=true service_role=false')
    ) as t(firma, ficha, permisos)
  loop
    select format('definer=%s search_path_vacio=%s dueño=%s argumentos=%s retorna=%s ejecutan=%s',
             p.prosecdef::text, coalesce(p.proconfig @> array['search_path=""'], false)::text, p.proowner::regrole::text,
             pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid),
             (select coalesce(string_agg(case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end, ','
                                         order by case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end), '(nadie)')
              from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x where x.privilege_type = 'EXECUTE'))
      into v
    from pg_proc p where p.oid = to_regprocedure(f.firma);
    perform pg_temp.igual(format('T7 catálogo de %s: INVOKER/DEFINER, search_path vacío, dueño, firma, columnas y quién ejecuta', f.firma), f.ficha, v);
    select format('public=%s anon=%s authenticated=%s service_role=%s',
             has_function_privilege('public', f.firma, 'EXECUTE')::text, has_function_privilege('anon', f.firma, 'EXECUTE')::text,
             has_function_privilege('authenticated', f.firma, 'EXECUTE')::text, has_function_privilege('service_role', f.firma, 'EXECUTE')::text)
      into v;
    perform pg_temp.igual(format('T7 EXECUTE efectivo sobre %s', f.firma), f.permisos, v);
  end loop;
  perform pg_temp.igual('T7 el diagnóstico es STABLE y su argumento tiene valor por defecto (null = todos)', 's/1',
    (select p.provolatile::text || '/' || p.pronargdefaults::text from pg_proc p
     where p.oid = to_regprocedure('private.cuenta_pago_diagnostico(uuid[])')));
  -- La prueba SÍ llama al diagnóstico (como postgres, su dueño): que no vaya a faltarle el permiso.
  perform pg_temp.cierto('T7 quien corre la prueba puede ejecutar el diagnóstico sin cambiar de rol',
    has_function_privilege(current_user, 'private.cuenta_pago_diagnostico(uuid[])', 'EXECUTE'), current_user::text);
  return 'OK T7 catálogo: diagnóstico solo para su dueño; las dos puertas solo para authenticated; search_path vacío en las tres';
end;
$f$;

-- ══ T1 · Censo ══════════════════════════════════════════════════════════════════════════════
create function pg_temp.t1_censo() returns text language plpgsql as $f$
declare
  v_modo constant text := current_setting('rezago.modo');
  v_estado constant text := current_setting('rezago.estado');
  v_censo constant text := case v_estado
    when 'sembrado' then 'cuenta_no_corresponde=2 ok=2 otra_moneda=2 sin_cuenta=3 una_cuenta=4 varias_cuentas=2'
    else                 'cuenta_no_corresponde=2 ok=6 otra_moneda=2 sin_cuenta=3 varias_cuentas=2' end;
  e record;
  d record;
  v text;
begin
  -- La consulta suelta (sin funciones nuevas) coincide, contrato por contrato, con lo esperado.
  for e in select * from pg_temp.esperado_ahora() x order by x.k loop
    select o.caso || '|' || o.en_moneda || '|' || o.otra_moneda into v from pg_temp.oraculo() o where o.contrato_id = e.contrato_id;
    perform pg_temp.igual(format('T1 %s en el estado %s, por la consulta suelta (caso|activas en la moneda|activas en la otra)', e.numero, v_estado),
      e.caso || '|' || e.en_moneda || '|' || e.otra_moneda, v);
  end loop;
  select string_agg(s.caso || '=' || s.n, ' ' order by s.caso) into v
  from (select o.caso, count(*) as n from pg_temp.oraculo() o group by o.caso) s;
  perform pg_temp.igual(format('T1 censo por caso en el estado %s, por la consulta suelta', v_estado), v_censo, v);
  if v_modo <> 'despues' then
    return format('OK T1 (%s): censo por la consulta suelta = %s', v_estado, v);
  end if;

  -- La regla instalada: una fila por contrato, con todas sus columnas.
  perform pg_temp.igual('T1 el diagnóstico sin argumentos devuelve una fila por contrato (filas/contratos distintos)', '15/15',
    (select count(*)::text || '/' || count(distinct d2.contrato_id)::text from private.cuenta_pago_diagnostico() d2));
  perform pg_temp.igual('T1 el diagnóstico con null devuelve lo mismo que sin argumentos', '15/15',
    (select count(*)::text || '/' || count(distinct d2.contrato_id)::text from private.cuenta_pago_diagnostico(null) d2));
  for e in select * from pg_temp.esperado_ahora() x order by x.k loop
    perform pg_temp.igual(format('T1 %s: el diagnóstico devuelve UNA fila al pedirlo solo', e.numero), '1',
      (select count(*)::text from private.cuenta_pago_diagnostico(array[e.contrato_id]) d2));
    select * into d from private.cuenta_pago_diagnostico(array[e.contrato_id]) d2;
    perform pg_temp.igual(format('T1 %s en el estado %s: contrato|cliente|moneda|estado|demo que devuelve el diagnóstico', e.numero, v_estado),
      e.numero || '|' || e.cliente_id || '|' || e.moneda || '|activo|' || e.es_demo::text,
      d.numero_contrato || '|' || d.cliente_id || '|' || d.moneda || '|' || d.estado || '|' || d.es_demo::text);
    perform pg_temp.igual(format('T1 %s en el estado %s: caso', e.numero, v_estado), e.caso, d.caso);
    perform pg_temp.igual(format('T1 %s en el estado %s: mensaje (null si se puede pagar)', e.numero, v_estado), e.mensaje, d.mensaje);
    -- El contrato de la migración define estos conteos para los casos sin vínculo; aquí se exigen
    -- para todos (cuentas ACTIVAS del cliente en la moneda del contrato / en la otra).
    perform pg_temp.igual(format('T1 %s en el estado %s: cuentas_en_moneda|cuentas_otra_moneda', e.numero, v_estado),
      e.en_moneda || '|' || e.otra_moneda, coalesce(d.cuentas_en_moneda::text, '(null)') || '|' || coalesce(d.cuentas_otra_moneda::text, '(null)'));
  end loop;
  select string_agg(s.caso || '=' || s.n, ' ' order by s.caso) into v
  from (select d2.caso, count(*) as n from private.cuenta_pago_diagnostico() d2 group by d2.caso) s;
  perform pg_temp.igual(format('T1 censo por caso en el estado %s, por el diagnóstico', v_estado), v_censo, v);
  -- Pedir unos contratos devuelve esos y solo esos; uno que no existe, ninguno.
  perform pg_temp.igual('T1 el diagnóstico de dos contratos devuelve esos dos', 'REZAGO-01,REZAGO-07',
    (select string_agg(d2.numero_contrato, ',' order by d2.numero_contrato)
     from private.cuenta_pago_diagnostico(array[(select contrato_id from esperado where k = 1), (select contrato_id from esperado where k = 7)]) d2));
  perform pg_temp.igual('T1 el diagnóstico de un contrato que no existe no devuelve filas', '0',
    (select count(*)::text from private.cuenta_pago_diagnostico(array['00000000-0000-4000-8000-00000000dead'::uuid]) d2));
  return format('OK T1 (%s): censo por el diagnóstico = %s; coincide con la consulta suelta en los 15 contratos', v_estado, v);
end;
$f$;

-- ══ T2 + T3 · Qué recibe cada actor, por cada vía, en CADA contrato bloqueado ═════════════════
create function pg_temp.t23_matriz() returns text language plpgsql as $f$
declare
  v_modo constant text := current_setting('rezago.modo');
  -- Con el bloqueo anterior (antes de la migración, o tras revertir solo el código) nadie recibe el detalle.
  v_bloqueo_anterior constant boolean := v_modo in ('antes', 'solo_codigo');
  v_generico constant text := 'ERR:23514:' || pg_temp.k('generico');
  v_sin_permiso constant text := 'ERR:42501:' || pg_temp.k('sin_permiso');
  e record;
  m record;
  r text;
  v_ficha text;
  v_espera text;
  v_intentos integer := 0;
  v_contratos integer := 0;
  v_detalles integer := 0;
begin
  for e in select * from pg_temp.esperado_ahora() x where x.caso <> 'ok' order by x.k loop
    v_contratos := v_contratos + 1;
    for m in select * from matriz x order by x.actor, x.via loop
      v_ficha := case when v_bloqueo_anterior then m.antes else m.despues end;
      v_espera := case v_ficha when 'GEN' then v_generico when 'DET' then 'ERR:23514:' || e.mensaje
                               when 'SIN_PERMISO' then v_sin_permiso else v_ficha end;
      r := pg_temp.intento(m.actor, m.via, e.contrato_id, pg_temp.cuota(e.k, 1));
      perform pg_temp.igual(format('%s %s (%s) como %s por %s', case when m.actor in ('admin', 'oper') then 'T2' else 'T3' end,
                                   e.numero, e.caso, m.actor, m.via), v_espera, r);
      if v_ficha = 'DET' then
        v_detalles := v_detalles + 1;
      else
        -- Regla general, valga lo que valga la fila de arriba: ni paga ni se entera del motivo.
        perform pg_temp.cierto(format('T3 %s: %s por %s NUNCA recibe el detalle ni paga', e.numero, m.actor, m.via),
          r not like 'PAGADO%' and position(e.numero in r) = 0 and position('cuenta de pago:' in r) = 0
          and position('su cuenta de pago' in r) = 0 and position(e.mensaje in r) = 0, r);
      end if;
      if r like 'ERR:%' then
        insert into vistos (origen, texto) values (format('bloqueo %s %s/%s', e.numero, m.actor, m.via), substr(r, 11));
      end if;
      v_intentos := v_intentos + 1;
    end loop;
  end loop;
  perform pg_temp.cierto('T2/T3 se probaron contratos bloqueados', v_contratos >= 9, v_contratos::text);
  return format('OK T2/T3 (%s): %s intentos sobre %s contratos bloqueados; %s recibieron el motivo exacto y el resto el genérico o nada',
                v_modo, v_intentos, v_contratos, v_detalles);
end;
$f$;

-- ══ T4 · Camino feliz ═══════════════════════════════════════════════════════════════════════
create function pg_temp.t4_camino_feliz() returns text language plpgsql as $f$
declare
  e record;
  m record;
  r text;
  x0 text;
  x1 text;
  v_pagos integer := 0;
begin
  perform pg_temp.cierto('T4 testigo: la cuenta vinculada de REZAGO-02 está INACTIVA (y aun así se debe poder pagar)',
    exists (select 1 from crm.contrato_cuentas_pago l join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
            where l.contrato_id = (select contrato_id from esperado where k = 2) and cb.activa is false));
  for e in select * from pg_temp.esperado_ahora() x where x.caso = 'ok' order by x.k loop
    for m in select * from (values ('admin', 'update'), ('admin', 'insert'), ('admin', 'rpc'), ('oper', 'update'), ('oper', 'rpc'),
                                   ('directa', 'update'), ('directa', 'rpc')) as t(actor, via) loop
      select l.xmax::text into x0 from crm.contrato_cuentas_pago l where l.contrato_id = e.contrato_id;
      r := pg_temp.intento(m.actor, m.via, e.contrato_id, pg_temp.cuota(e.k, 1));
      select l.xmax::text into x1 from crm.contrato_cuentas_pago l where l.contrato_id = e.contrato_id;
      perform pg_temp.igual(format('T4 %s se paga como %s por %s y queda sellado en su cuenta vinculada', e.numero, m.actor, m.via),
        'PAGADO:' || e.cuenta_vinculada || ':registro', r);
      -- El FOR SHARE de la consulta del bloqueo deja su marca en la fila del vínculo (xmax). Solo se
      -- puede medir en el vínculo: la fila del contrato la bloquea además el candado documental.
      perform pg_temp.cierto(format('T4 %s: el pago tomó el candado FOR SHARE del vínculo (%s por %s)', e.numero, m.actor, m.via),
        x1 is distinct from x0 and x1 <> '0', format('xmax %s → %s', x0, x1));
      v_pagos := v_pagos + 1;
    end loop;
  end loop;
  perform pg_temp.cierto('T4 se probaron contratos ok', v_pagos >= 14, v_pagos::text);
  return format('OK T4 (%s): %s pagos de contratos ok (incluida la cuenta vinculada inactiva), sellados y con el candado del vínculo',
                current_setting('rezago.estado'), v_pagos);
end;
$f$;

-- T4b: el diagnóstico se cambia por una versión que SOLO falla (misma firma y columnas, leídas del
-- catálogo). Se llama entre un savepoint y su rollback.
create function pg_temp.sabotear_diagnostico() returns text language plpgsql as $f$
declare
  v_oid constant oid := to_regprocedure('private.cuenta_pago_diagnostico(uuid[])');
begin
  execute format(
    $d$create or replace function private.cuenta_pago_diagnostico(%s) returns %s language plpgsql stable set search_path = '' as
       $sab$ begin raise exception using errcode = 'P0001', message = 'REZAGO_DIAGNOSTICO_SABOTEADO'; end; $sab$ $d$,
    pg_get_function_arguments(v_oid), pg_get_function_result(v_oid));
  return 'diagnóstico sustituido por una versión que solo hace raise (se repone con el rollback del savepoint)';
end;
$f$;
create function pg_temp.t4b_feliz_sin_diagnostico() returns text language plpgsql as $f$
declare
  e record;
  m record;
  r text;
  v text;
  v_pagos integer := 0;
  v_contra integer := 0;
begin
  begin
    perform count(*) from private.cuenta_pago_diagnostico();
    v := 'no falló';
  exception when others then
    v := sqlerrm;
  end;
  perform pg_temp.igual('T4b testigo: el diagnóstico saboteado falla al llamarlo', 'REZAGO_DIAGNOSTICO_SABOTEADO', v);
  for e in select * from pg_temp.esperado_ahora() x where x.caso = 'ok' order by x.k loop
    for m in select * from (values ('admin', 'update'), ('admin', 'insert'), ('oper', 'rpc'), ('directa', 'update')) as t(actor, via) loop
      r := pg_temp.intento(m.actor, m.via, e.contrato_id, pg_temp.cuota(e.k, 1));
      perform pg_temp.igual(format('T4b %s se paga como %s por %s aunque el diagnóstico solo falle (el camino feliz no lo llama)',
                                   e.numero, m.actor, m.via), 'PAGADO:' || e.cuenta_vinculada || ':registro', r);
      v_pagos := v_pagos + 1;
    end loop;
  end loop;
  -- Contraprueba: el sabotaje está vivo y el detalle SALE del diagnóstico. Sin él, quien sí podía
  -- recibir el motivo ya no lo recibe (y sigue sin pagar). Si esto falla, la prueba de arriba es vacía.
  for e in select * from pg_temp.esperado_ahora() x where x.caso <> 'ok' order by x.k loop
    for m in select * from (values ('admin', 'update'), ('directa', 'update')) as t(actor, via) loop
      r := pg_temp.intento(m.actor, m.via, e.contrato_id, pg_temp.cuota(e.k, 1));
      perform pg_temp.cierto(format('T4b contraprueba %s como %s: sin diagnóstico no hay detalle ni pago', e.numero, m.actor),
        r like 'ERR:%' and position(e.mensaje in r) = 0, r);
      v_contra := v_contra + 1;
    end loop;
  end loop;
  return format('OK T4b: con el diagnóstico saboteado, %s pagos de contratos ok pasan igual y %s rechazos pierden el detalle', v_pagos, v_contra);
end;
$f$;
create function pg_temp.t4b_diagnostico_repuesto() returns text language plpgsql as $f$
begin
  perform pg_temp.igual('T4b el diagnóstico de verdad volvió tras el rollback del savepoint', '15',
    (select count(*)::text from private.cuenta_pago_diagnostico()));
  return 'OK T4b: diagnóstico repuesto';
end;
$f$;

-- ══ T5 · La carga ═══════════════════════════════════════════════════════════════════════════
create function pg_temp.t5_carga() returns text language plpgsql as $f$
declare
  v_marca constant text := pg_temp.k('marca');
  e record;
  l record;
  a record;
  v text;
begin
  for e in select * from esperado x where x.caso = 'una_cuenta' order by x.k loop
    perform pg_temp.igual(format('T5 %s: tiene exactamente un vínculo', e.numero), '1',
      (select count(*)::text from crm.contrato_cuentas_pago x where x.contrato_id = e.contrato_id));
    select * into l from crm.contrato_cuentas_pago x where x.contrato_id = e.contrato_id;
    perform pg_temp.igual(format('T5 %s: vinculado a su única cuenta ACTIVA en la moneda', e.numero), e.cuenta_carga::text, l.cuenta_bancaria_id::text);
    perform pg_temp.cierto(format('T5 %s: la cuenta vinculada está activa y es del cliente y de la moneda del contrato', e.numero),
      exists (select 1 from crm.cuentas_bancarias cb
              where cb.id = l.cuenta_bancaria_id and cb.activa and cb.cliente_id = e.cliente_id and cb.moneda = e.moneda));
    perform pg_temp.cierto(format('T5 %s: creado_por es null', e.numero), l.creado_por is null, l.creado_por::text);
    perform pg_temp.igual(format('T5 %s: una fila de rastro vigente con la marca (tipo vinculo, su fila, su cliente y su contrato)', e.numero), '1',
      (select count(*)::text from private.backfill_cuentas_p0xx b
       where b.tipo = 'vinculo' and b.fila_id = l.id and b.cliente_id = e.cliente_id and b.contrato_id = e.contrato_id
         and b.marca_actor = v_marca and b.revertida_en is null));
    perform pg_temp.igual(format('T5 %s: ninguna otra fila de rastro para ese vínculo', e.numero), '1',
      (select count(*)::text from private.backfill_cuentas_p0xx b where b.fila_id = l.id));
    perform pg_temp.igual(format('T5 %s: una fila INSERT en public.audit_log para ese vínculo', e.numero), '1',
      (select count(*)::text from public.audit_log x
       where x.tabla = 'crm.contrato_cuentas_pago' and x.operacion = 'INSERT' and x.fila_id = l.id::text));
    select * into a from public.audit_log x
     where x.tabla = 'crm.contrato_cuentas_pago' and x.operacion = 'INSERT' and x.fila_id = l.id::text;
    perform pg_temp.igual(format('T5 %s: la bitácora guarda el vínculo tal como quedó (cuenta|creado_por)', e.numero),
      e.cuenta_carga::text || '|(null)',
      coalesce(a.data_despues ->> 'cuenta_bancaria_id', '(null)') || '|' || coalesce(a.data_despues ->> 'creado_por', '(null)'));
  end loop;

  -- Exactamente esos: ni un vínculo ni un rastro de más.
  perform pg_temp.igual('T5 vínculos en total (4 sembrados + 4 de la carga)', '8', (select count(*)::text from crm.contrato_cuentas_pago));
  select string_agg(ct.numero_contrato, ',' order by ct.numero_contrato) into v
  from private.backfill_cuentas_p0xx b join public.contratos ct on ct.id = b.contrato_id
  where b.marca_actor = v_marca and b.revertida_en is null;
  perform pg_temp.igual('T5 el rastro vigente de la carga son exactamente los una_cuenta sembrados', 'REZAGO-03,REZAGO-04,REZAGO-05,REZAGO-06', v);
  perform pg_temp.igual('T5 la carga no rastrea cuentas (no creó ni tocó ninguna)', '0',
    (select count(*)::text from private.backfill_cuentas_p0xx b where b.marca_actor = v_marca and b.tipo <> 'vinculo'));
  perform pg_temp.igual('T5 ningún vínculo fuera de los sembrados y de los que rastrea la carga', '0',
    (select count(*)::text from crm.contrato_cuentas_pago x
     where x.id::text not like 'c9ef0000-%'
       and not exists (select 1 from private.backfill_cuentas_p0xx b
                       where b.tipo = 'vinculo' and b.fila_id = x.id and b.marca_actor = v_marca and b.revertida_en is null)));
  perform pg_temp.igual('T5 ningún rastro REVERTIDO (de una vuelta anterior del ciclo) apunta a un vínculo vivo', '0',
    (select count(*)::text from private.backfill_cuentas_p0xx b
     where b.marca_actor = v_marca and b.revertida_en is not null
       and exists (select 1 from crm.contrato_cuentas_pago x where x.id = b.fila_id)));

  -- Lo demás no cambió.
  perform pg_temp.igual('T5 los 4 vínculos sembrados no cambiaron (huella de todas sus columnas)', pg_temp.k('huella_vinculos_sembrados'),
    pg_temp.huella('crm.contrato_cuentas_pago', $q$x.id::text like 'c9ef0000-%'$q$));
  perform pg_temp.igual('T5 ninguna cuenta bancaria cambió (huella de todas las columnas de todas las cuentas)', pg_temp.k('huella_cuentas'),
    pg_temp.huella('crm.cuentas_bancarias'));
  select string_agg(x.numero, ',' order by x.numero) into v
  from esperado x where not exists (select 1 from crm.contrato_cuentas_pago y where y.contrato_id = x.contrato_id);
  perform pg_temp.igual('T5 siguen SIN vínculo todos los que no tenían una sola cuenta posible (REZAGO-12 solo tiene una inactiva)',
    'REZAGO-07,REZAGO-08,REZAGO-09,REZAGO-10,REZAGO-11,REZAGO-12,REZAGO-13', v);
  -- La carga vincula, pero no inventa hechos: la cuota que REZAGO-04 ya tenía pagada sigue sin sello.
  perform pg_temp.igual('T5 la cuota que REZAGO-04 ya tenía pagada sigue pagada y SIN sello (la carga no sella lo de antes)', 'pagado/0',
    (select q.estado from public.cronograma_pagos q where q.id::text = pg_temp.k('cuota_pagada_de_antes')) || '/' ||
    (select count(*) from crm.cuotas_cuenta_pagada s where s.cuota_id::text = pg_temp.k('cuota_pagada_de_antes'))::text);
  perform pg_temp.igual('T5 ninguna cuenta INACTIVA quedó en un vínculo nuevo', '0',
    (select count(*)::text from crm.contrato_cuentas_pago x join crm.cuentas_bancarias cb on cb.id = x.cuenta_bancaria_id
     where not cb.activa and x.id::text not like 'c9ef0000-%'));
  return 'OK T5: la carga vinculó REZAGO-03/04/05/06 a su única cuenta activa (creado_por null, rastro y bitácora); nada más cambió';
end;
$f$;

-- ══ T6 · Los recién vinculados ya se pagan ══════════════════════════════════════════════════
create function pg_temp.t6_vinculados_pagan() returns text language plpgsql as $f$
declare
  e record;
  v_cci text;
  v_sellos text;
  v_n integer := 0;
begin
  for e in select * from esperado x where x.caso = 'una_cuenta' order by x.k loop
    select cb.cci into strict v_cci from crm.cuentas_bancarias cb where cb.id = e.cuenta_carga;
    perform pg_temp.igual(format('T6 %s: operaciones lo paga por la RPC y queda sellado en la cuenta vinculada', e.numero),
      'PAGADO:' || e.cuenta_carga || ':registro', pg_temp.intento('oper', 'rpc', e.contrato_id, pg_temp.cuota(e.k, 1)));
    perform pg_temp.igual(format('T6 %s: operaciones lo paga por la RPC declarando el CCI de esa cuenta', e.numero),
      'PAGADO:' || e.cuenta_carga || ':declarado', pg_temp.intento('oper', 'rpc', e.contrato_id, pg_temp.cuota(e.k, 2), v_cci));
    perform pg_temp.igual(format('T6 %s: admin lo paga por UPDATE directo', e.numero),
      'PAGADO:' || e.cuenta_carga || ':registro', pg_temp.intento('admin', 'update', e.contrato_id, pg_temp.cuota(e.k, 3)));
    perform pg_temp.igual(format('T6 %s: admin inserta una cuota ya pagada', e.numero),
      'PAGADO:' || e.cuenta_carga || ':registro', pg_temp.intento('admin', 'insert', e.contrato_id, pg_temp.cuota(e.k, 1)));
    v_n := v_n + 4;
  end loop;
  -- REZAGO-04: al pagar su siguiente cuota se sella ESA; la que ya estaba pagada sigue sin sello.
  begin
    update public.cronograma_pagos
       set estado = 'pagado', fecha_pago_real = (now() at time zone 'America/Lima')::date, monto_pagado = 100
     where id = pg_temp.cuota(4, 1);
    select coalesce(string_agg(q.cuota_id::text || '|' || q.cuenta_bancaria_id::text || '|' || q.origen, ' · ' order by q.cuota_id), '(ningún sello)')
      into v_sellos
    from crm.cuotas_cuenta_pagada q where q.contrato_id = (select x.contrato_id from esperado x where x.k = 4);
    raise exception using errcode = 'P0001', message = 'REZAGO_DESHACER_INTENTO';
  exception when others then
    if sqlerrm <> 'REZAGO_DESHACER_INTENTO' then
      v_sellos := 'ERR:' || sqlstate || ':' || sqlerrm;
    end if;
  end;
  perform pg_temp.igual('T6 REZAGO-04: tras pagar su siguiente cuota hay UN sello, el de esa cuota; la que ya estaba pagada sigue sin sello',
    pg_temp.cuota(4, 1)::text || '|' || (select x.cuenta_carga::text from esperado x where x.k = 4) || '|registro', v_sellos);
  return format('OK T6: los 4 contratos vinculados por la carga ya se pagan (%s pagos sellados en su cuenta); la cuota pagada de antes sigue sin sello', v_n);
end;
$f$;

-- ══ T7 · La puerta de lectura ═══════════════════════════════════════════════════════════════
create function pg_temp.t7_puerta() returns text language plpgsql as $f$
declare
  v_estado constant text := current_setting('rezago.estado');
  v_no_autorizado constant text := 'ERR:42501:No autorizado para consultar cuentas de pago';
  v_demasiados constant text := 'ERR:22023:Demasiados contratos en una sola consulta';
  v_todos uuid[];
  v_5000 uuid[];
  v_5001 uuid[];
  v_espera text;
  v_diag text;
  v_una text;
  f text;
  a text;
  r text;
begin
  select array_agg(x.contrato_id order by x.k) into v_todos from esperado x;
  v_5000 := v_todos || array(select gen_random_uuid() from generate_series(1, 5000 - cardinality(v_todos)));
  v_5001 := v_5000 || gen_random_uuid();
  perform pg_temp.igual('T7 tamaños de las listas de prueba', '5000/5001', cardinality(v_5000)::text || '/' || cardinality(v_5001)::text);

  select 'OK:' || coalesce(jsonb_agg(jsonb_build_object('contrato_id', x.contrato_id, 'caso', x.caso, 'mensaje', x.mensaje) order by x.contrato_id), '[]'::jsonb)::text
    into v_espera from pg_temp.esperado_ahora() x where x.caso <> 'ok';
  select 'OK:' || coalesce(jsonb_agg(jsonb_build_object('contrato_id', d.contrato_id, 'caso', d.caso, 'mensaje', d.mensaje) order by d.contrato_id), '[]'::jsonb)::text
    into v_diag from private.cuenta_pago_diagnostico(v_todos) d where d.caso <> 'ok';
  perform pg_temp.igual(format('T7 (%s) los no-ok del diagnóstico son los esperados, con su mensaje', v_estado), v_espera, v_diag);
  select 'OK:' || jsonb_build_array(jsonb_build_object('contrato_id', x.contrato_id, 'caso', x.caso, 'mensaje', x.mensaje))::text
    into v_una from pg_temp.esperado_ahora() x where x.k = 7;

  foreach f in array array['crm.cuentas_pago_motivos_fn', 'private.cuentas_pago_motivos_autorizado'] loop
    foreach a in array array['admin', 'oper'] loop
      r := pg_temp.puerta(a, f, v_todos);
      perform pg_temp.igual(format('T7 (%s) %s como %s: solo los contratos no-ok, con el mismo mensaje que el diagnóstico', v_estado, f, a), v_diag, r);
      insert into vistos (origen, texto)
      select format('puerta %s como %s', f, a), x ->> 'mensaje' from jsonb_array_elements(substr(r, 4)::jsonb) as t(x);
      perform pg_temp.igual(format('T7 %s como %s: lista vacía → sin filas', f, a), 'OK:[]', pg_temp.puerta(a, f, '{}'::uuid[]));
      perform pg_temp.igual(format('T7 %s como %s: null → sin filas', f, a), 'OK:[]', pg_temp.puerta(a, f, null));
      perform pg_temp.igual(format('T7 %s como %s: 5001 contratos → 22023', f, a), v_demasiados, pg_temp.puerta(a, f, v_5001));
      perform pg_temp.igual(format('T7 %s como %s: 5000 contratos (los 15 reales entre ellos) → las mismas filas', f, a), v_diag, pg_temp.puerta(a, f, v_5000));
      perform pg_temp.igual(format('T7 %s como %s: pide un ok (REZAGO-01) y un bloqueado (REZAGO-07) → solo el bloqueado', f, a), v_una,
        pg_temp.puerta(a, f, array[(select contrato_id from esperado where k = 1), (select contrato_id from esperado where k = 7)]));
      perform pg_temp.igual(format('T7 %s como %s: solo contratos ok → sin filas', f, a), 'OK:[]',
        pg_temp.puerta(a, f, array[(select contrato_id from esperado where k = 1), (select contrato_id from esperado where k = 2)]));
      perform pg_temp.igual(format('T7 %s como %s: un contrato que no existe → sin filas', f, a), 'OK:[]',
        pg_temp.puerta(a, f, array['00000000-0000-4000-8000-00000000dead'::uuid]));
    end loop;
    -- La compuerta va ANTES que todo lo demás (igual que crm.cuentas_pago_contratos_fn): quien no es
    -- gestor de cartera, o tiene la membresía CRM revocada, recibe 42501 pida lo que pida.
    foreach a in array array['analista', 'cliente', 'revocada', 'directa', 'sinclaims_auth'] loop
      perform pg_temp.igual(format('T7 %s como %s: 42501', f, a), v_no_autorizado, pg_temp.puerta(a, f, v_todos));
      perform pg_temp.igual(format('T7 %s como %s con lista vacía: 42501 (la compuerta va primero)', f, a), v_no_autorizado, pg_temp.puerta(a, f, '{}'::uuid[]));
      perform pg_temp.igual(format('T7 %s como %s con null: 42501', f, a), v_no_autorizado, pg_temp.puerta(a, f, null));
      perform pg_temp.igual(format('T7 %s como %s con 5001 contratos: 42501 (antes que el tope)', f, a), v_no_autorizado, pg_temp.puerta(a, f, v_5001));
    end loop;
    -- anon y service_role no tienen EXECUTE: el ayudante no llama (tumbaría el servidor) y lo dice.
    foreach a in array array['anon', 'servicio', 'sinclaims_anon', 'sinclaims_servicio', 'sinclaims_sin_rol'] loop
      perform pg_temp.igual(format('T7 %s como %s: sin EXECUTE (no se llama)', f, a), 'SIN_EXECUTE', pg_temp.puerta(a, f, v_todos));
    end loop;
  end loop;
  return format('OK T7 (%s): la puerta devuelve solo los no-ok con el mensaje del diagnóstico; compuerta, topes y permisos en regla', v_estado);
end;
$f$;

-- ══ T8 · Propiedad: el bloqueo deja pagar ⇔ caso = ok ═══════════════════════════════════════
create function pg_temp.t8_propiedad() returns text language plpgsql as $f$
declare
  v_modo constant text := current_setting('rezago.modo');
  e record;
  v_caso text;
  a text;
  r text;
  v_pagan integer := 0;
  v_no integer := 0;
begin
  for e in select * from esperado x order by x.k loop
    if v_modo = 'despues' then
      select d.caso into strict v_caso from private.cuenta_pago_diagnostico(array[e.contrato_id]) d;
    else
      select o.caso into strict v_caso from pg_temp.oraculo() o where o.contrato_id = e.contrato_id;
    end if;
    foreach a in array array['admin', 'directa'] loop
      r := pg_temp.intento(a, 'update', e.contrato_id, pg_temp.cuota(e.k, 1));
      perform pg_temp.igual(format('T8 %s (caso %s, %s): el bloqueo deja pagar ⇔ el caso es ok', e.numero, v_caso, a),
        (v_caso = 'ok')::text, (r like 'PAGADO:%')::text);
      perform pg_temp.cierto(format('T8 %s (%s): lo que no se paga lo detiene el bloqueo (23514), no otra regla', e.numero, a),
        r like 'PAGADO:%' or r like 'ERR:23514:%', r);
    end loop;
    if v_caso = 'ok' then v_pagan := v_pagan + 1; else v_no := v_no + 1; end if;
  end loop;
  return format('OK T8 (%s): en los 15 contratos, pagar ⇔ caso ok (%s se pagan, %s no)', current_setting('rezago.estado'), v_pagan, v_no);
end;
$f$;

-- ══ T9 · Privacidad ═════════════════════════════════════════════════════════════════════════
create function pg_temp.t9_privacidad() returns text language plpgsql as $f$
declare
  v_fugas integer;
  v_ejemplo text;
  v_textos integer;
  v_sensibles integer;
  v text;
begin
  create temp table t9_textos on commit drop as
    select 'diagnóstico de ' || d.numero_contrato as origen, d.mensaje as texto
    from private.cuenta_pago_diagnostico() d where d.mensaje is not null
    union all
    select x.origen, x.texto from vistos x;
  create temp table t9_sensibles on commit drop as
    select 'número de cuenta' as que, cb.numero_cuenta as valor from crm.cuentas_bancarias cb
    union all select 'CCI', cb.cci from crm.cuentas_bancarias cb
    union all select 'DNI de beneficiario', cb.beneficiario_dni from crm.cuentas_bancarias cb where cb.beneficiario_dni is not null
    union all select 'nombre de beneficiario', cb.beneficiario_nombre from crm.cuentas_bancarias cb where cb.beneficiario_nombre is not null
    union all select 'DNI', p.dni from public.perfiles p where p.dni is not null
    union all select 'nombre', p.nombre_completo from public.perfiles p
    union all select 'correo', p.correo from public.perfiles p where p.correo is not null;
  select count(*) into v_textos from t9_textos;
  select count(*) into v_sensibles from t9_sensibles;
  perform pg_temp.cierto('T9 hay mensajes y datos sensibles que cruzar (que la prueba no sea vacía)', v_textos >= 9 and v_sensibles >= 80,
    format('%s textos, %s datos', v_textos, v_sensibles));
  select count(*), min(t.origen || ' lleva un ' || s.que) into v_fugas, v_ejemplo
  from t9_textos t join t9_sensibles s on position(lower(s.valor) in lower(t.texto)) > 0;
  perform pg_temp.igual('T9 ningún mensaje lleva número de cuenta, CCI, DNI, nombre ni correo', '0', v_fugas::text || coalesce(' · ' || v_ejemplo, ''));
  select count(*), min(t.origen) into v_fugas, v_ejemplo
  from t9_textos t where t.texto ~* '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  perform pg_temp.igual('T9 ningún mensaje lleva identificadores internos (uuid)', '0', v_fugas::text || coalesce(' · ' || v_ejemplo, ''));
  select string_agg(distinct d.caso, ',' order by d.caso) into v
  from private.cuenta_pago_diagnostico() d
  where d.caso not in ('ok', 'una_cuenta', 'varias_cuentas', 'otra_moneda', 'sin_cuenta', 'cuenta_no_corresponde');
  perform pg_temp.igual('T9 el diagnóstico no devuelve ningún caso fuera de los seis', null, v);
  perform pg_temp.igual('T9 el mensaje es null si y solo si el caso es ok', '0',
    (select count(*)::text from private.cuenta_pago_diagnostico() d where (d.caso = 'ok') is distinct from (d.mensaje is null)));
  drop table t9_textos;
  drop table t9_sensibles;
  return format('OK T9 (%s): %s mensajes cruzados con %s datos sensibles sembrados, sin ninguna fuga', current_setting('rezago.estado'), v_textos, v_sensibles);
end;
$f$;

-- Borra, SOLO dentro de esta transacción, los vínculos que creó la carga (entre un savepoint y su rollback).
create function pg_temp.desvincular_la_carga() returns text language plpgsql as $f$
declare
  v_n integer;
begin
  delete from crm.contrato_cuentas_pago x
  using private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.fila_id = x.id and b.marca_actor = pg_temp.k('marca') and b.revertida_en is null;
  get diagnostics v_n = row_count;
  perform pg_temp.igual('estado sembrado: se retiraron en la transacción los 4 vínculos de la carga', '4', v_n::text);
  return 'los 4 vínculos de la carga, retirados dentro de la transacción: vuelve a haber contratos una_cuenta con la regla nueva';
end;
$f$;

-- ══ Ejecución ═══════════════════════════════════════════════════════════════════════════════
select pg_temp.t0_precondiciones();
select pg_temp.t10_catalogo();
\if :es_despues
select pg_temp.t7_catalogo();
\echo '── estado «cargado»: el banco tal como lo dejó la migración'
select set_config('rezago.estado', 'cargado', true) as estado_fijado \gset
select pg_temp.t1_censo();
select pg_temp.t5_carga();
select pg_temp.t4_camino_feliz();
select pg_temp.t6_vinculados_pagan();
savepoint sabotaje;
select pg_temp.sabotear_diagnostico();
select pg_temp.t4b_feliz_sin_diagnostico();
rollback to savepoint sabotaje;
select pg_temp.t4b_diagnostico_repuesto();
select pg_temp.t7_puerta();
select pg_temp.t8_propiedad();
select pg_temp.t9_privacidad();
\echo '── estado «sembrado» con la regla nueva: sin los vínculos de la carga (solo dentro de esta transacción)'
savepoint antes_de_la_carga;
select pg_temp.desvincular_la_carga();
select set_config('rezago.estado', 'sembrado', true) as estado_fijado \gset
select pg_temp.t1_censo();
select pg_temp.t23_matriz();
select pg_temp.t7_puerta();
select pg_temp.t8_propiedad();
select pg_temp.t9_privacidad();
rollback to savepoint antes_de_la_carga;
\elif :es_solo_codigo
\echo '── solo código: bloqueo anterior, sin las funciones nuevas, con los vínculos de la carga'
select set_config('rezago.estado', 'cargado', true) as estado_fijado \gset
select pg_temp.t1_censo();
select pg_temp.t5_carga();
select pg_temp.t4_camino_feliz();
select pg_temp.t6_vinculados_pagan();
select pg_temp.t23_matriz();
select pg_temp.t8_propiedad();
\else
select pg_temp.t1_censo();
select pg_temp.t23_matriz();
select pg_temp.t4_camino_feliz();
select pg_temp.t8_propiedad();
\endif
select 'REZAGO ' || current_setting('rezago.modo') || ' OK · ' || (select last_value from rezago_hechas) || ' comprobaciones, nada escrito' as veredicto;
rollback;
reset session authorization;
