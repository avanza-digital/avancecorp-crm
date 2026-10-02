-- PRUEBA de 20261002005004_crm_asignar_cuenta_pago — SOLO BANCO Docker propio.
-- ⚠️ Jamás contra producción. Requiere la siembra común (../cuentas-pago-rezago/siembra.sql), la
-- siembra extra (siembra-extra.sql) y la migración APLICADA. Funciona con y sin la otra migración
-- de la tanda (20261001233019): lo detecta sola y T10 solo corre si está.
-- NO deja nada escrito: todo ocurre en UNA transacción que termina en ROLLBACK y, además, cada
-- tramo se deshace entero al terminar (todos arrancan del mismo mundo sembrado y no se estorban).
--
--   docker exec -i -e PGPASSWORD=postgres <contenedor> psql -U supabase_admin -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -qAt < test-asignar-cuenta-pago.sql
--
-- Se lanza como supabase_admin (superusuario) y enseguida pasa a ser postgres (la «conexión directa»
-- de producción). El superusuario hace falta para dos cosas: entrar como «authenticator» en los
-- actores de la API (PostgREST entra SIEMPRE así y después hace SET ROLE) y montar el doble de
-- storage.objects de T8. Va sentencia a sentencia.
--
-- CÓMO SE LEE LA SALIDA
--   Una línea por tramo: «T4 PASS · 214 comprobaciones · …» o «T4 FAIL · 37 comprobaciones ·
--   FALLO [T4 …]: esperaba «…», vino «…»». Un tramo que falla se corta en su primera aserción rota,
--   pero LOS DEMÁS SIGUEN (por eso un mutante dice qué tramos lo cazan). La última línea es el
--   veredicto: «ASIGNAR OK · …» o «ASIGNAR FALLO · …» (y entonces psql sale con error).
--
-- QUÉ CUBRE
--   T0   precondiciones: superusuario, migración aplicada, puerta abierta y el mundo sembrado sin restos (corta todo)
--   T1   quién: admin y superadmin asignan; operaciones, analista, cliente, comercial, directorio, admin
--        revocado (P04), superadmin revocado, admin desactivado, sesión sin sub, sin claims, uid que no
--        existe y la conexión directa → 42501 y NADA escrito; permisos de puerta y núcleo por catálogo;
--        el núcleo llamado directo aplica la misma compuerta
--   T2   efecto: vínculo, constancia completa (motivo recortado), bitácora de los dos, retorno sin datos
--        sensibles y NINGUNA otra tabla cambia
--   T3   después se paga: antes 23514; después, pagado y sellado (declarando el CCI y sin declararlo);
--        la cuota que ya estaba pagada NO se sella y los sellos previos quedan intactos
--   T4   rechazos, cada uno con su mensaje EXACTO y sin escribir nada; un 23505 ajeno NO se disfraza de «ya tiene cuenta»
--   T5   idempotencia por solicitud
--   T6   elegir entre varias; una_cuenta; otra_moneda y sin_cuenta hasta registrar una; y la propiedad:
--        asignar pasa ⇔ la cuenta es vigente, del mismo cliente y de la misma moneda
--   T7   la constancia: no se modifica, ni se borra, ni se vacía; RLS, sin permisos de API, sin FK, comentarios, bitácora
--   T8   convivencia con F3 (cambiar cuenta de pago) y F4 (retirar cuenta)
--   T10  con la otra migración: diagnóstico y puerta de motivos antes y después de asignar
--   TC   catálogo de las tres funciones, verificado aparte del postflight
--   (T9, concurrencia con dos sesiones reales, va en prueba-concurrencia.sh; ahí va también la guarda de
--    aislamiento del núcleo —REPEATABLE READ y SERIALIZABLE dan 0A000—, que esta prueba no puede ver
--    porque toda ella corre en UNA transacción READ COMMITTED)
--
-- TRAMPAS DE ESTE BANCO (ver supabase/scripts/potencial-lead/banco/LEEME.md)
--   · Llamar a una función SIN EXECUTE bajo «set role» tumba este Postgres: los permisos se leen del
--     catálogo y pg_temp.como() se NIEGA a llamar (devuelve SIN_EXECUTE) si falta el permiso.
--   · auth.uid()/auth.role() de la imagen leen request.jwt.claim.sub / .role; los de producción
--     también request.jwt.claims: la sesión fija LAS DOS formas.
--   · La imagen no trae storage.objects y F3/F4 lo declaran (%rowtype): sin esa tabla ni siquiera
--     compilan. T8 monta un DOBLE mínimo dentro de esta transacción (se va con el ROLLBACK).
--   · Ningún ayudante toca tablas ni funciones temporales mientras la sesión o el rol están cambiados.
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';
set local timezone = 'UTC';

-- ── Entrada (como superusuario): quién lanza y el doble de storage.objects ─────────────────────
do $entrada$
begin
  perform set_config('asignar.conectado', session_user::text, true);
  if not (select r.rolsuper from pg_catalog.pg_roles r where r.rolname = session_user) then
    raise exception 'FALLO [uso]: la prueba se lanza como supabase_admin (superusuario); vino %', session_user;
  end if;
  if to_regclass('storage.objects') is null then
    execute 'create table storage.objects (
               id uuid primary key default gen_random_uuid(), bucket_id text, name text,
               owner uuid, owner_id text, metadata jsonb, created_at timestamptz default now())';
    perform set_config('asignar.storage', 'doble', true);
  else
    perform set_config('asignar.storage', 'real', true);
  end if;
  execute 'grant select on storage.objects to postgres';
end;
$entrada$;
-- Respaldos ficticios para F3 (el «correo del cliente»), subidos por la admin 01: dos en la carpeta
-- del cliente F (REZAGO-07) y uno en la del cliente M (REZAGO-14).
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  ('respaldos-cambio-cuenta', 'c9e00000-0000-4000-8000-000000000016/a519f000-0000-4000-8000-000000000001.pdf',
   'c9e00000-0000-4000-8000-000000000001', 'c9e00000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"a519-01\""}'),
  ('respaldos-cambio-cuenta', 'c9e00000-0000-4000-8000-000000000016/a519f000-0000-4000-8000-000000000002.pdf',
   'c9e00000-0000-4000-8000-000000000001', 'c9e00000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"a519-02\""}'),
  ('respaldos-cambio-cuenta', 'c9e00000-0000-4000-8000-000000000023/a519f000-0000-4000-8000-000000000003.pdf',
   'c9e00000-0000-4000-8000-000000000001', 'c9e00000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"a519-03\""}');
set local session authorization postgres;

-- «MUTANTE» (ciclo.sh sustituye esta línea por la alteración que quiere probar; aquí no hay nada)

-- ── Constantes ───────────────────────────────────────────────────────────────────────────────
create temp table constantes (k text primary key, v text not null) on commit drop;
insert into constantes values
  ('puerta',         'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'),
  ('nucleo',         'private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'),
  ('candado',        'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'),
  ('md5_puerta',     '46e03517fc68ffd79fed6892d1128c2b'),
  ('md5_nucleo',     '3642871283e7306a179ea3795bad1389'),
  ('md5_candado',    '49bb93b9429aa7b0c168cc8ceb43acfc'),
  ('marca_carga',    'migracion:rezago-vinculos:20261001'),
  ('no_admin',       'ERR:42501:Solo administración puede asignar la cuenta de pago'),
  ('faltan',         'ERR:22023:Faltan datos de la asignación'),
  ('motivo',         'ERR:22023:Escribe el motivo de la asignación (5 a 500 caracteres)'),
  ('usada',          'ERR:22023:Esta solicitud ya se usó con otros datos'),
  ('no_cuenta',      'ERR:22023:La cuenta elegida no existe'),
  ('no_contrato',    'ERR:22023:El contrato no existe'),
  ('no_vigente',     'ERR:22023:La cuenta elegida ya no está vigente'),
  ('ajena',          'ERR:22023:La cuenta elegida no es del cliente del contrato %s'),
  ('moneda',         'ERR:22023:El contrato %s es en %s y la cuenta elegida en %s'),
  ('cerrado',        'ERR:22023:El contrato %s está cerrado (%s)'),
  ('ya_tiene',       'ERR:22023:El contrato %s ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»'),
  ('no_modifica',    'ERR:22023:El registro de asignaciones de cuenta de pago no se modifica ni se vacía'),
  ('no_borra',       'ERR:22023:Los registros de cuentas de pago no se borran'),
  ('motivo_bueno',   'Operaciones confirmó con el cliente en cuál cobra');
create function pg_temp.k(p_k text) returns text language sql stable as $f$
  select c.v from constantes c where c.k = p_k;
$f$;
-- Identificadores del mundo sembrado: c = contrato REZAGO-n · cta = su cuenta c9ec…n ·
-- cuota(k, c) · xc = contrato ASIGNAR-n · xcta = cuenta a519c…n · xcuota(k, c) · sol(n) = solicitud n.
create function pg_temp.c(p_n integer) returns uuid language sql immutable as $f$
  select ('c9ed0000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid;
$f$;
create function pg_temp.cta(p_n integer) returns uuid language sql immutable as $f$
  select ('c9ec0000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid;
$f$;
create function pg_temp.cuota(p_k integer, p_c integer) returns uuid language sql immutable as $f$
  select ('c9ee0000-0000-4000-8000-00000000' || lpad(p_k::text, 2, '0') || lpad(p_c::text, 2, '0'))::uuid;
$f$;
create function pg_temp.xc(p_n integer) returns uuid language sql immutable as $f$
  select ('a519d000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid;
$f$;
create function pg_temp.xcta(p_n integer) returns uuid language sql immutable as $f$
  select ('a519c000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid;
$f$;
create function pg_temp.xcuota(p_k integer, p_c integer) returns uuid language sql immutable as $f$
  select ('a519e000-0000-4000-8000-00000000' || lpad(p_k::text, 2, '0') || lpad(p_c::text, 2, '0'))::uuid;
$f$;
create function pg_temp.sol(p_n integer) returns uuid language sql immutable as $f$
  select ('a519a000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
$f$;

-- ── Aserciones (una secuencia cuenta las hechas: no se deshace con los sub-bloques) ────────────
create temp sequence asignar_hechas;
select nextval('asignar_hechas') > 0 as secuencia_lista;
create function pg_temp.igual(p_que text, p_esperado text, p_obtenido text) returns void language plpgsql as $f$
begin
  if p_obtenido is distinct from p_esperado then
    raise exception 'FALLO [%]: esperaba «%», vino «%»', p_que, coalesce(p_esperado, '(null)'), coalesce(p_obtenido, '(null)');
  end if;
  perform nextval('asignar_hechas');
end;
$f$;
create function pg_temp.cierto(p_que text, p_condicion boolean, p_detalle text default null) returns void language plpgsql as $f$
begin
  if p_condicion is not true then
    raise exception 'FALLO [%]%', p_que, coalesce(': ' || p_detalle, '');
  end if;
  perform nextval('asignar_hechas');
end;
$f$;

-- ── Fotos del mundo ──────────────────────────────────────────────────────────────────────────
-- Cuántas filas tiene CADA tabla de crm, public y private (-1 = no legible).
create function pg_temp.conteos() returns jsonb language plpgsql as $f$
declare
  t record;
  n bigint;
  j jsonb := '{}';
begin
  for t in
    select s.nspname, c.relname
    from pg_catalog.pg_class c join pg_catalog.pg_namespace s on s.oid = c.relnamespace
    where s.nspname in ('crm', 'public', 'private') and c.relkind in ('r', 'p')
    order by 1, 2
  loop
    begin
      execute format('select count(*) from %I.%I', t.nspname, t.relname) into n;
    exception when insufficient_privilege then
      n := -1;
    end;
    j := j || jsonb_build_object(t.nspname || '.' || t.relname, n);
  end loop;
  return j;
end;
$f$;
-- Lo que cambió entre dos conteos: «tabla:+n» ordenado, o «(nada)».
create function pg_temp.diferencia(p_antes jsonb, p_despues jsonb) returns text language sql as $f$
  select coalesce(string_agg(d.key || ':' || case when d.n > 0 then '+' else '' end || d.n, ' ' order by d.key), '(nada)')
  from (select coalesce(a.key, b.key) as key, coalesce(b.value::bigint, 0) - coalesce(a.value::bigint, 0) as n
        from jsonb_each_text(p_antes) a full join jsonb_each_text(p_despues) b on b.key = a.key) d
  where d.n <> 0;
$f$;
-- La huella del CONTENIDO (todas las columnas de todas las filas) de las tablas que la asignación
-- lee o podría tocar, más cuántas filas tiene la bitácora.
create function pg_temp.huella_mundo() returns text language plpgsql as $f$
declare
  t text;
  v text;
  r text := '';
begin
  foreach t in array array['crm.contrato_cuentas_pago', 'crm.contrato_cuenta_pago_asignaciones', 'crm.cuentas_bancarias',
                           'public.contratos', 'public.cronograma_pagos', 'crm.cuotas_cuenta_pagada',
                           'crm.contrato_cuenta_pago_cambios', 'crm.cuentas_bancarias_retiros', 'public.perfiles'] loop
    execute format('select count(*) || '':'' || md5(coalesce(string_agg(md5(to_jsonb(x)::text), '','' order by x.id), '''')) from %s x', t) into v;
    r := r || t || '=' || v || ' ';
  end loop;
  return r || 'bitacora=' || (select count(*) from public.audit_log);
end;
$f$;

-- ── Actores y sesión ─────────────────────────────────────────────────────────────────────────
-- rol_db = el rol al que PostgREST hace SET ROLE (null = conexión directa como postgres, sin API).
-- con_claims = si llegan los claims del JWT. uid = el sub.
create temp table actores (k text primary key, rol_db text, uid uuid, con_claims boolean not null, que text not null) on commit drop;
insert into actores values
  ('admin',          'authenticated', 'c9e00000-0000-4000-8000-000000000001', true,  'admin activo'),
  ('super',          'authenticated', 'a5190000-0000-4000-8000-000000000031', true,  'superadmin activo'),
  ('admin_equipo',   'authenticated', 'a5190000-0000-4000-8000-000000000034', true,  'admin con membresía CRM vigente'),
  ('oper',           'authenticated', 'c9e00000-0000-4000-8000-000000000002', true,  'operaciones'),
  ('analista',       'authenticated', 'c9e00000-0000-4000-8000-000000000004', true,  'analista'),
  ('cliente',        'authenticated', 'c9e00000-0000-4000-8000-000000000013', true,  'cliente'),
  ('cliente_p',      'authenticated', 'a5190000-0000-4000-8000-000000000041', true,  'cliente dueño del contrato'),
  ('comercial',      'authenticated', 'a5190000-0000-4000-8000-000000000036', true,  'comercial'),
  ('directorio',     'authenticated', 'a5190000-0000-4000-8000-000000000037', true,  'directorio'),
  ('revocada',       'authenticated', 'c9e00000-0000-4000-8000-000000000003', true,  'admin con la membresía CRM revocada'),
  ('super_revocada', 'authenticated', 'a5190000-0000-4000-8000-000000000033', true,  'superadmin con la membresía CRM revocada'),
  ('admin_inactivo', 'authenticated', 'a5190000-0000-4000-8000-000000000032', true,  'admin desactivado'),
  ('fantasma',       'authenticated', 'a5190000-0000-4000-8000-0000000000ee', true,  'uid que no existe en perfiles'),
  ('sin_sub',        'authenticated', null,                                   true,  'sesión authenticated sin sub'),
  ('sin_claims',     'authenticated', null,                                   false, 'sesión authenticated sin claims'),
  ('directa',        null,            null,                                   false, 'conexión directa (postgres, sin identidad)');

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

-- EL ÚNICO sitio donde se cambia de sesión: ejecuta p_sql (un SELECT que devuelve un texto) como
-- el actor. p_funciones = las funciones que esa llamada necesita ejecutar: si el rol no tiene
-- EXECUTE sobre alguna NO se llama (tumbaría el servidor). Devuelve 'OK:<texto>',
-- 'ERR:<sqlstate>:<mensaje>', 'SIN_EXECUTE:<firma>' o 'NO_EXISTE:<firma>'. Lo que la llamada escriba
-- se QUEDA (dentro del tramo); si falla, no escribe nada.
create function pg_temp.como(p_actor text, p_funciones text[], p_sql text) returns text language plpgsql as $f$
declare
  a record;
  f text;
  r text; e text; m text;
begin
  select * into strict a from actores x where x.k = p_actor;
  foreach f in array p_funciones loop
    if to_regprocedure(f) is null then
      return 'NO_EXISTE:' || f;
    end if;
    if not has_function_privilege(coalesce(a.rol_db, 'postgres'), f, 'EXECUTE') then
      return 'SIN_EXECUTE:' || f;
    end if;
  end loop;
  perform pg_temp.claims(case when a.con_claims then a.rol_db end, a.uid);
  if a.rol_db is not null then
    execute 'set local session authorization authenticator';
    execute format('set local role %I', a.rol_db);
  end if;
  begin
    execute p_sql into r;
    r := 'OK:' || coalesce(r, '(null)');
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    r := 'ERR:' || e || ':' || m;
  end;
  execute 'set local session authorization postgres';
  perform pg_temp.claims(null, null);
  return r;
end;
$f$;

-- Privacidad: lo que devuelve la asignación (el JSON o el mensaje de error) no lleva ningún dato
-- sensible de NINGUNA cuenta ni persona del banco, ni más identificador que la propia solicitud.
create function pg_temp.sin_fugas(p_texto text, p_sol uuid) returns void language plpgsql as $f$
declare
  v text;
begin
  select min(s.que) into v
  from (select 'número de cuenta' as que, cb.numero_cuenta as valor from crm.cuentas_bancarias cb
        union all select 'CCI', cb.cci from crm.cuentas_bancarias cb
        union all select 'DNI de beneficiario', cb.beneficiario_dni from crm.cuentas_bancarias cb where cb.beneficiario_dni is not null
        union all select 'nombre de beneficiario', cb.beneficiario_nombre from crm.cuentas_bancarias cb where cb.beneficiario_nombre is not null
        union all select 'documento', p.dni from public.perfiles p where p.dni is not null
        union all select 'nombre de persona', p.nombre_completo from public.perfiles p
        union all select 'correo', p.correo from public.perfiles p where p.correo is not null) s
  where position(lower(s.valor) in lower(p_texto)) > 0;
  if v is not null then
    raise exception 'FALLO [privacidad]: la respuesta lleva un %: «%»', v, p_texto;
  end if;
  if exists (select 1 from regexp_matches(p_texto, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'gi') as x(u)
             where lower(x.u[1]) is distinct from lower(p_sol::text)) then
    raise exception 'FALLO [privacidad]: la respuesta lleva un identificador interno: «%»', p_texto;
  end if;
  perform nextval('asignar_hechas');
end;
$f$;

-- La asignación como un actor, por la puerta (lo normal) o llamando al núcleo directo.
create function pg_temp.asignar(p_actor text, p_sol uuid, p_contrato uuid, p_cuenta uuid, p_motivo text,
                                p_via text default 'puerta') returns text language plpgsql as $f$
declare
  r text;
begin
  r := pg_temp.como(p_actor,
         case p_via when 'puerta' then array[pg_temp.k('puerta'), pg_temp.k('nucleo')] else array[pg_temp.k('nucleo')] end,
         format('select (%s(%L::uuid, %L::uuid, %L::uuid, %L::text))::text',
                case p_via when 'puerta' then 'crm.asignar_cuenta_pago_contrato' else 'private.asignar_cuenta_pago_contrato_autorizado' end,
                p_sol, p_contrato, p_cuenta, p_motivo));
  perform pg_temp.sin_fugas(r, p_sol);
  return r;
end;
$f$;
-- Lo mismo, pero SIEMPRE se deshace. Si pasó, añade lo que quedó guardado: « cuenta=<id> motivo=«…»».
create function pg_temp.ensayo(p_actor text, p_contrato uuid, p_cuenta uuid, p_motivo text) returns text language plpgsql as $f$
declare
  v_sol constant uuid := gen_random_uuid();
  r text;
  v_guardado text;
begin
  begin
    r := pg_temp.asignar(p_actor, v_sol, p_contrato, p_cuenta, p_motivo);
    if r like 'OK:%' then
      select ' cuenta=' || l.cuenta_bancaria_id || ' motivo=«' || a.motivo || '»' into v_guardado
      from crm.contrato_cuenta_pago_asignaciones a join crm.contrato_cuentas_pago l on l.id = a.vinculo_id
      where a.solicitud_id = v_sol;
    end if;
    raise exception using errcode = 'P0001', message = 'ASIGNAR_DESHACER';
  exception when others then
    if sqlerrm <> 'ASIGNAR_DESHACER' then raise; end if;
  end;
  return case when r like 'OK:%' then 'OK' || coalesce(v_guardado, ' (sin constancia)') else r end;
end;
$f$;
create function pg_temp.vinculo(p_contrato uuid) returns text language sql as $f$
  select coalesce((select l.cuenta_bancaria_id::text || '|' || coalesce(l.creado_por::text, '(null)')
                   from crm.contrato_cuentas_pago l where l.contrato_id = p_contrato), 'sin vínculo');
$f$;

-- Registrar el pago de una cuota por la RPC, como un gestor. El pago se QUEDA (dentro del tramo).
-- 'PAGADO:<cuenta sellada>:<origen>' · 'PAGADO:sin sello' · 'SIN_EFECTO' (la RPC devolvió null) · 'ERR:…'
create function pg_temp.pagar(p_actor text, p_cuota uuid, p_cci text default null) returns text language plpgsql as $f$
declare
  r text;
begin
  r := pg_temp.como(p_actor, array['crm.registrar_pago_con_cuenta(uuid,date,numeric,text)'],
         format('select (crm.registrar_pago_con_cuenta(%L::uuid, %L::date, 100, %L::text))::text',
                p_cuota, (now() at time zone 'America/Lima')::date, p_cci));
  if r = 'OK:(null)' then
    return 'SIN_EFECTO';
  elsif r like 'OK:%' then
    return 'PAGADO:' || coalesce((select q.cuenta_bancaria_id::text || ':' || q.origen
                                  from crm.cuotas_cuenta_pagada q where q.cuota_id = p_cuota), 'sin sello');
  end if;
  return r;
end;
$f$;
-- F3: cambiar la cuenta de pago · F4: retirar una cuenta · registrar una cuenta · puerta de motivos.
create function pg_temp.cambiar(p_actor text, p_sol uuid, p_cliente uuid, p_cuenta uuid, p_ids uuid[], p_motivo text, p_ruta text)
returns text language sql as $f$
  select pg_temp.como(p_actor, array['crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)',
                                     'private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)'],
    format('select (crm.cambiar_cuenta_pago_contratos(%L::uuid, %L::uuid, %L::uuid, %L::uuid[], %L::text, %L::text))::text',
           p_sol, p_cliente, p_cuenta, p_ids, p_motivo, p_ruta));
$f$;
create function pg_temp.retirar(p_actor text, p_sol uuid, p_cliente uuid, p_cuenta uuid, p_motivo text) returns text language sql as $f$
  select pg_temp.como(p_actor, array['crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)',
                                     'private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)'],
    format('select (crm.retirar_cuenta_cliente(%L::uuid, %L::uuid, %L::uuid, %L::text, null))::text', p_sol, p_cliente, p_cuenta, p_motivo));
$f$;
create function pg_temp.registrar_cuenta(p_actor text, p_cliente uuid, p_cuenta jsonb) returns text language sql as $f$
  select pg_temp.como(p_actor, array['crm.registrar_cuenta_cliente(uuid,jsonb)', 'private.registrar_cuenta_cliente_autorizado(uuid,jsonb)'],
    format('select (crm.registrar_cuenta_cliente(%L::uuid, %L::jsonb))::text', p_cliente, p_cuenta));
$f$;
create function pg_temp.motivos(p_actor text, p_ids uuid[]) returns text language plpgsql as $f$
declare
  r text;
begin
  r := pg_temp.como(p_actor, array['crm.cuentas_pago_motivos_fn(uuid[])', 'private.cuentas_pago_motivos_autorizado(uuid[])'],
         format('select coalesce(jsonb_agg(jsonb_build_object(''contrato'', t.contrato_id, ''caso'', t.caso)), ''[]''::jsonb)::text
                 from crm.cuentas_pago_motivos_fn(%L::uuid[]) t', p_ids));
  if r not like 'OK:%' then
    return r;
  end if;
  return 'OK:' || coalesce((select string_agg(ct.numero_contrato || '=' || (x ->> 'caso'), ',' order by ct.numero_contrato)
                            from jsonb_array_elements(substr(r, 4)::jsonb) as t(x)
                            join public.contratos ct on ct.id = (x ->> 'contrato')::uuid), '(ninguno)');
end;
$f$;

-- Si la carga de la otra migración ya vinculó los cuatro «una_cuenta» (REZAGO-03…06), los desvincula
-- SOLO dentro del tramo en curso, para probar con el mundo tal como se sembró. Devuelve cuántos.
create function pg_temp.mundo_sembrado() returns integer language plpgsql as $f$
declare
  v_n integer;
begin
  delete from crm.contrato_cuentas_pago x
  using private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.fila_id = x.id and b.marca_actor = pg_temp.k('marca_carga') and b.revertida_en is null;
  get diagnostics v_n = row_count;
  if v_n not in (0, 4) then
    raise exception 'FALLO [mundo]: la carga de la otra migración tenía % vínculos vivos; se esperaban 0 o 4', v_n;
  end if;
  return v_n;
end;
$f$;
create function pg_temp.otra_aplicada() returns boolean language sql stable as $f$
  select to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null
     and to_regprocedure('crm.cuentas_pago_motivos_fn(uuid[])') is not null;
$f$;

-- ── El corredor de tramos ────────────────────────────────────────────────────────────────────
-- Corre un tramo y lo DESHACE entero, pase o falle; anota el resultado y sigue con el siguiente.
create temp table resultados (orden serial primary key, tramo text not null, estado text not null,
                              comprobaciones bigint not null, detalle text) on commit drop;
create function pg_temp.correr(p_tramo text, p_fn text) returns text language plpgsql as $f$
declare
  v_antes constant bigint := (select s.last_value from asignar_hechas s);
  v_estado text := 'PASS';
  v_detalle text;
  v_n bigint;
begin
  begin
    execute format('select %s()', p_fn) into v_detalle;
    raise exception using errcode = 'P0001', message = 'ASIGNAR_DESHACER_TRAMO';
  exception when others then
    if sqlerrm <> 'ASIGNAR_DESHACER_TRAMO' then
      v_estado := 'FAIL';
      v_detalle := sqlerrm;
    end if;
  end;
  if session_user <> 'postgres' or current_user <> 'postgres' then
    raise exception 'FALLO [%]: el tramo dejó la sesión cambiada (%/%)', p_tramo, session_user, current_user;
  end if;
  v_n := (select s.last_value from asignar_hechas s) - v_antes;
  insert into resultados (tramo, estado, comprobaciones, detalle) values (p_tramo, v_estado, v_n, v_detalle);
  return format('%s %s · %s comprobaciones · %s', p_tramo, v_estado, v_n, v_detalle);
end;
$f$;

-- ══ T0 · Precondiciones (si falla, se corta todo) ═══════════════════════════════════════════
create function pg_temp.t0_precondiciones() returns text language plpgsql as $f$
declare
  v text;
  v_carga integer;
begin
  perform pg_temp.igual('T0 tras el «set session authorization», la sesión y el rol son postgres', 'postgres/postgres',
    session_user || '/' || current_user);
  perform pg_temp.igual('T0 la migración está aplicada: existen la tabla, la puerta, el núcleo y el candado', 'true/true/true/true',
    (to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null)::text || '/' ||
    (to_regprocedure(pg_temp.k('puerta')) is not null)::text || '/' ||
    (to_regprocedure(pg_temp.k('nucleo')) is not null)::text || '/' ||
    (to_regprocedure(pg_temp.k('candado')) is not null)::text);
  select count(*) into v_carga
  from crm.contrato_cuentas_pago x join private.backfill_cuentas_p0xx b on b.fila_id = x.id
  where b.tipo = 'vinculo' and b.marca_actor = pg_temp.k('marca_carga') and b.revertida_en is null;
  perform pg_temp.cierto('T0 la carga de la otra migración tiene 0 o 4 vínculos vivos', v_carga in (0, 4), v_carga::text);
  select format('%s contratos (%s REZAGO, %s ASIGNAR), %s cuentas (%s inactivas), %s vínculos sembrados, %s de la carga, %s de más, %s constancias, %s sellos, %s cambios, %s retiros, %s cuotas pagadas',
    (select count(*) from public.contratos),
    (select count(*) from public.contratos where id::text like 'c9ed0000-%'),
    (select count(*) from public.contratos where id::text like 'a519d000-%'),
    (select count(*) from crm.cuentas_bancarias),
    (select count(*) from crm.cuentas_bancarias where not activa),
    (select count(*) from crm.contrato_cuentas_pago where id::text like 'c9ef0000-%'),
    v_carga,
    (select count(*) from crm.contrato_cuentas_pago) - 4 - v_carga,
    (select count(*) from crm.contrato_cuenta_pago_asignaciones),
    (select count(*) from crm.cuotas_cuenta_pagada),
    (select count(*) from crm.contrato_cuenta_pago_cambios),
    (select count(*) from crm.cuentas_bancarias_retiros),
    (select count(*) from public.cronograma_pagos where estado = 'pagado')) into v;
  perform pg_temp.igual('T0 el banco tiene SOLO las dos siembras y ningún resto (si falla: ciclo.sh limpia)',
    format('28 contratos (15 REZAGO, 13 ASIGNAR), 28 cuentas (4 inactivas), 4 vínculos sembrados, %s de la carga, 0 de más, 0 constancias, 0 sellos, 0 cambios, 0 retiros, 1 cuotas pagadas', v_carga), v);
  perform pg_temp.igual('T0 la puerta está abierta: authenticated ejecuta la puerta y el núcleo (tras una reversa con asignaciones no)', 'true/true',
    has_function_privilege('authenticated', pg_temp.k('puerta'), 'EXECUTE')::text || '/' ||
    has_function_privilege('authenticated', pg_temp.k('nucleo'), 'EXECUTE')::text);
  return format('la migración está aplicada, la puerta abierta y el mundo sembrado sin restos; la otra migración %s; storage.objects %s',
    case when pg_temp.otra_aplicada() then format('SÍ está aplicada (su carga tiene %s vínculos vivos)', v_carga) else 'NO está aplicada' end,
    case current_setting('asignar.storage') when 'doble' then 'es un DOBLE de esta transacción (la imagen no lo trae)' else 'es el real' end);
end;
$f$;

-- ══ T1 · Quién ══════════════════════════════════════════════════════════════════════════════
create function pg_temp.t1_quien() returns text language plpgsql as $f$
declare
  K1 constant uuid := pg_temp.xc(1);
  A1 constant uuid := pg_temp.xcta(1);
  MOT constant text := pg_temp.k('motivo_bueno');
  v_huella constant text := pg_temp.huella_mundo();
  v_conteos constant jsonb := pg_temp.conteos();
  a record;
  f text;
  r text;
  v text;
  v_negados integer := 0;
begin
  -- Permisos por catálogo (nunca llamando: sin EXECUTE, este Postgres se cae).
  foreach f in array array[pg_temp.k('puerta'), pg_temp.k('nucleo')] loop
    perform pg_temp.igual(format('T1 EXECUTE efectivo sobre %s (public/anon/authenticated/service_role)', f),
      'public=false anon=false authenticated=true service_role=false',
      format('public=%s anon=%s authenticated=%s service_role=%s',
        has_function_privilege('public', f, 'EXECUTE')::text, has_function_privilege('anon', f, 'EXECUTE')::text,
        has_function_privilege('authenticated', f, 'EXECUTE')::text, has_function_privilege('service_role', f, 'EXECUTE')::text));
    perform pg_temp.igual(format('T1 quién tiene EXECUTE en la ACL de %s (exacto)', f), 'authenticated,postgres',
      (select coalesce(string_agg(case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end, ','
                                  order by case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end), '(nadie)')
       from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
       where p.oid = to_regprocedure(f) and x.privilege_type = 'EXECUTE'));
  end loop;
  -- El núcleo vive en private y solo lo nombra la puerta: ninguna otra función de un esquema que la
  -- API pueda exponer (crm, public) lo llama, y no hay sobrecargas.
  perform pg_temp.igual('T1 las únicas funciones de crm, public y private que nombran al núcleo', 'crm.asignar_cuenta_pago_contrato',
    (select string_agg(s.nspname || '.' || p.proname, ',' order by s.nspname, p.proname)
     from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname in ('crm', 'public', 'private') and p.prosrc like '%asignar_cuenta_pago_contrato_autorizado%'));
  perform pg_temp.igual('T1 funciones con el nombre de la puerta o del núcleo, en cualquier esquema (sin sobrecargas ni copias)',
    'crm.asignar_cuenta_pago_contrato,private.asignar_cuenta_pago_contrato_autorizado',
    (select string_agg(s.nspname || '.' || p.proname, ',' order by s.nspname, p.proname)
     from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where p.proname in ('asignar_cuenta_pago_contrato', 'asignar_cuenta_pago_contrato_autorizado')));
  -- Si el banco lleva la configuración de PostgREST, private no está entre los esquemas expuestos.
  select string_agg(c.cfg, ' · ') into v
  from pg_db_role_setting s cross join lateral unnest(s.setconfig) as c(cfg)
  where s.setrole = 'authenticator'::regrole and c.cfg like 'pgrst.db_schemas=%';
  perform pg_temp.cierto('T1 si el banco declara los esquemas de la API, private no está entre ellos',
    v is null or v !~ '(=|,|\s)private(,|\s|$)', v);

  -- Los que NO pueden: 42501 pidan lo que pidan (con datos buenos, con todo nulo y llamando al núcleo).
  for a in select * from actores x where x.k not in ('admin', 'super', 'admin_equipo') order by x.k loop
    perform pg_temp.igual(format('T1 %s (%s) por la puerta con datos válidos', a.k, a.que), pg_temp.k('no_admin'),
      pg_temp.asignar(a.k, gen_random_uuid(), K1, A1, MOT));
    perform pg_temp.igual(format('T1 %s por la puerta con todo nulo (la compuerta va antes que la validación)', a.k), pg_temp.k('no_admin'),
      pg_temp.asignar(a.k, null, null, null, null));
    perform pg_temp.igual(format('T1 %s llamando al núcleo directo', a.k), pg_temp.k('no_admin'),
      pg_temp.asignar(a.k, gen_random_uuid(), K1, A1, MOT, 'nucleo'));
    perform pg_temp.igual(format('T1 %s sobre un contrato que ya tiene cuenta: tampoco se entera', a.k), pg_temp.k('no_admin'),
      pg_temp.asignar(a.k, gen_random_uuid(), pg_temp.c(1), pg_temp.cta(1), MOT));
    v_negados := v_negados + 1;
  end loop;
  perform pg_temp.cierto('T1 se probaron los 13 actores sin permiso', v_negados = 13, v_negados::text);
  perform pg_temp.igual('T1 ningún intento sin permiso escribió nada (huella de todas las tablas tocables y de la bitácora)', v_huella, pg_temp.huella_mundo());
  perform pg_temp.igual('T1 ningún intento sin permiso cambió el número de filas de ninguna tabla', '(nada)', pg_temp.diferencia(v_conteos, pg_temp.conteos()));

  -- Los que SÍ pueden: admin, superadmin y admin con membresía CRM vigente.
  r := pg_temp.asignar('admin', pg_temp.sol(101), K1, A1, MOT);
  perform pg_temp.cierto('T1 admin asigna', r like 'OK:%' and (substr(r, 4)::jsonb ->> 'ya_aplicada') = 'false', r);
  perform pg_temp.igual('T1 el vínculo de admin queda a su nombre', A1 || '|c9e00000-0000-4000-8000-000000000001', pg_temp.vinculo(K1));
  r := pg_temp.asignar('super', pg_temp.sol(102), pg_temp.c(7), pg_temp.cta(10), MOT);
  perform pg_temp.cierto('T1 superadmin asigna', r like 'OK:%' and (substr(r, 4)::jsonb ->> 'ya_aplicada') = 'false', r);
  perform pg_temp.igual('T1 el vínculo de superadmin queda a su nombre', pg_temp.cta(10) || '|a5190000-0000-4000-8000-000000000031', pg_temp.vinculo(pg_temp.c(7)));
  r := pg_temp.asignar('admin_equipo', pg_temp.sol(103), pg_temp.c(8), pg_temp.cta(12), MOT);
  perform pg_temp.cierto('T1 admin con membresía CRM vigente asigna (estar en el equipo no es estar revocado)',
    r like 'OK:%' and (substr(r, 4)::jsonb ->> 'ya_aplicada') = 'false', r);
  -- El núcleo llamado directo por un admin hace lo mismo: la compuerta está DENTRO del núcleo.
  r := pg_temp.asignar('admin', pg_temp.sol(104), pg_temp.xc(2), A1, MOT, 'nucleo');
  perform pg_temp.cierto('T1 el núcleo llamado directo por admin asigna (misma compuerta, mismo efecto)', r like 'OK:%', r);
  perform pg_temp.igual('T1 las cuatro asignaciones dejaron cuatro constancias, cada una con su autor',
    'a5190000-0000-4000-8000-000000000031,a5190000-0000-4000-8000-000000000034,c9e00000-0000-4000-8000-000000000001,c9e00000-0000-4000-8000-000000000001',
    (select string_agg(x.asignado_por::text, ',' order by x.asignado_por::text) from crm.contrato_cuenta_pago_asignaciones x));
  return format('admin, superadmin y admin con equipo vigente asignan; %s actores sin permiso reciben 42501 por puerta y núcleo sin escribir nada; anon, public y service_role sin EXECUTE; %s',
    v_negados, case when v is null then 'el banco no lleva la configuración de PostgREST (pgrst.db_schemas)' else 'pgrst.db_schemas sin private' end);
end;
$f$;

-- ══ T2 · Efecto ═════════════════════════════════════════════════════════════════════════════
create function pg_temp.t2_efecto() returns text language plpgsql as $f$
declare
  K1 constant uuid := pg_temp.xc(1);
  A2 constant uuid := pg_temp.xcta(2);
  SUPER constant uuid := 'a5190000-0000-4000-8000-000000000031';
  S constant uuid := pg_temp.sol(201);
  -- Bordes con espacio, tabulador, salto de línea, espacio duro, espacio «em» e ideográfico.
  MOT constant text := E' \t\n' || chr(160) || 'El cliente confirmó por teléfono su cuenta de   Interbank' || chr(8195) || chr(12288) || E' \n';
  MOT_LIMPIO constant text := 'El cliente confirmó por teléfono su cuenta de   Interbank';
  v_conteos constant jsonb := pg_temp.conteos();
  v_cuentas text; v_contratos text; v_cuotas text; v_perfiles text;
  r text;
  j jsonb;
  l record;
  a record;
  b record;
  n record;
  v_cta uuid;
  v_esperado jsonb;
  v_llamada text;
begin
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from crm.cuentas_bancarias x$q$ into v_cuentas;
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.contratos x$q$ into v_contratos;
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.cronograma_pagos x$q$ into v_cuotas;
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.perfiles x$q$ into v_perfiles;

  r := pg_temp.asignar('super', S, K1, A2, MOT);
  perform pg_temp.cierto('T2 la asignación pasa', r like 'OK:%', r);
  j := substr(r, 4)::jsonb;
  perform pg_temp.igual('T2 el retorno, entero (sin número de cuenta completo, CCI ni documento)',
    jsonb_build_object('solicitud_id', S, 'ya_aplicada', false, 'numero_contrato', 'ASIGNAR-01', 'banco', 'Interbank', 'moneda', 'PEN', 'ultimos', '0002')::text, j::text);
  perform pg_temp.igual('T2 las claves del retorno son exactamente seis', 'banco,moneda,numero_contrato,solicitud_id,ultimos,ya_aplicada',
    (select string_agg(x, ',' order by x) from jsonb_object_keys(j) as t(x)));
  perform pg_temp.igual('T2 «ultimos» son los 4 últimos caracteres del número de la cuenta elegida, y el número tiene más de 4',
    (select right(cb.numero_cuenta, 4) || '/true' from crm.cuentas_bancarias cb where cb.id = A2),
    (j ->> 'ultimos') || '/' || (select (length(cb.numero_cuenta) > 4)::text from crm.cuentas_bancarias cb where cb.id = A2));

  -- El vínculo.
  perform pg_temp.igual('T2 el contrato tiene exactamente un vínculo', '1',
    (select count(*)::text from crm.contrato_cuentas_pago x where x.contrato_id = K1));
  select * into strict l from crm.contrato_cuentas_pago x where x.contrato_id = K1;
  perform pg_temp.igual('T2 el vínculo apunta a la cuenta elegida y queda a nombre de quien asigna (cuenta|creado_por)', A2 || '|' || SUPER,
    l.cuenta_bancaria_id || '|' || coalesce(l.creado_por::text, '(null)'));
  perform pg_temp.cierto('T2 el vínculo lleva la hora de la transacción', l.creado_en = now(), l.creado_en::text);

  -- La constancia, campo por campo.
  perform pg_temp.igual('T2 hay exactamente una constancia', '1', (select count(*)::text from crm.contrato_cuenta_pago_asignaciones));
  select * into strict a from crm.contrato_cuenta_pago_asignaciones x where x.solicitud_id = S;
  perform pg_temp.igual('T2 constancia: solicitud|contrato|cliente|cuenta|vínculo|quién',
    S || '|' || K1 || '|a5190000-0000-4000-8000-000000000041|' || A2 || '|' || l.id || '|' || SUPER,
    a.solicitud_id || '|' || a.contrato_id || '|' || a.cliente_id || '|' || a.cuenta_bancaria_id || '|' || a.vinculo_id || '|' || a.asignado_por);
  perform pg_temp.igual('T2 constancia: el motivo se guarda recortado por los bordes y con sus espacios interiores intactos', MOT_LIMPIO, a.motivo);
  perform pg_temp.cierto('T2 constancia: lleva la hora de la transacción', a.asignado_en = now(), a.asignado_en::text);
  perform pg_temp.cierto('T2 constancia: tiene su propio id', a.id is not null and a.id <> l.id);

  -- La bitácora: una fila del vínculo y otra de la constancia, las dos con su autor.
  perform pg_temp.igual('T2 bitácora: exactamente un INSERT del vínculo', '1',
    (select count(*)::text from public.audit_log x where x.tabla = 'crm.contrato_cuentas_pago' and x.fila_id = l.id::text));
  select * into strict b from public.audit_log x where x.tabla = 'crm.contrato_cuentas_pago' and x.fila_id = l.id::text;
  perform pg_temp.igual('T2 bitácora del vínculo: operación|autor|cuenta|creado_por|sin «antes»', 'INSERT|' || SUPER || '|' || A2 || '|' || SUPER || '|true',
    b.operacion || '|' || coalesce(b.usuario_id::text, '(null)') || '|' || (b.data_despues ->> 'cuenta_bancaria_id') || '|' ||
    coalesce(b.data_despues ->> 'creado_por', '(null)') || '|' || (b.data_antes is null)::text);
  perform pg_temp.igual('T2 bitácora: exactamente un INSERT de la constancia', '1',
    (select count(*)::text from public.audit_log x where x.tabla = 'crm.contrato_cuenta_pago_asignaciones' and x.fila_id = a.id::text));
  select * into strict b from public.audit_log x where x.tabla = 'crm.contrato_cuenta_pago_asignaciones' and x.fila_id = a.id::text;
  perform pg_temp.igual('T2 bitácora de la constancia: operación|autor|motivo|vínculo', 'INSERT|' || SUPER || '|' || MOT_LIMPIO || '|' || l.id,
    b.operacion || '|' || coalesce(b.usuario_id::text, '(null)') || '|' || (b.data_despues ->> 'motivo') || '|' || (b.data_despues ->> 'vinculo_id'));
  perform pg_temp.igual('T2 bitácora de la constancia: guarda la fila entera', to_jsonb(a)::text, b.data_despues::text);

  -- Y nada más: ni avisos al cliente, ni sellos, ni cambios, ni otras tablas.
  perform pg_temp.igual('T2 las ÚNICAS tablas de crm, public y private que cambian de tamaño',
    'crm.contrato_cuenta_pago_asignaciones:+1 crm.contrato_cuentas_pago:+1 public.audit_log:+2', pg_temp.diferencia(v_conteos, pg_temp.conteos()));
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from crm.cuentas_bancarias x$q$ into r;
  perform pg_temp.igual('T2 ninguna cuenta bancaria cambió (huella de todas sus columnas)', v_cuentas, r);
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.contratos x$q$ into r;
  perform pg_temp.igual('T2 ningún contrato cambió', v_contratos, r);
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.cronograma_pagos x$q$ into r;
  perform pg_temp.igual('T2 ninguna cuota cambió', v_cuotas, r);
  execute $q$select md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.perfiles x$q$ into r;
  perform pg_temp.igual('T2 ningún perfil cambió', v_perfiles, r);
  -- «ultimos» solo sale de un número de 8 o más caracteres; con uno más corto viene null: NUNCA el número
  -- entero (la regla de las cuentas admite números de 1 a 30 caracteres). Igual en la repetición. Cada
  -- cuenta se registra por la puerta real y se asigna a un contrato distinto (todo se deshace). La
  -- respuesta se compara ENTERA con lo esperado.
  begin
    for n in select * from (values ('4321', '00251900000000004321', 2), ('7654321', '00251900000007654321', 6),
                                   ('87654321', '00251900000087654321', 7)) as t(numero, cci, contrato) loop
      r := pg_temp.registrar_cuenta('admin', 'a5190000-0000-4000-8000-000000000041',
             jsonb_build_object('moneda', 'PEN', 'banco', 'BCP', 'tipo_cuenta', 'ahorros', 'numero_cuenta', n.numero, 'cci', n.cci));
      perform pg_temp.cierto(format('T2 se registra una cuenta de número «%s» (%s caracteres)', n.numero, length(n.numero)), r like 'OK:%' and r <> 'OK:(null)', r);
      v_cta := substr(r, 4)::uuid;
      v_esperado := jsonb_build_object('solicitud_id', pg_temp.sol(210 + n.contrato), 'ya_aplicada', false,
                      'numero_contrato', 'ASIGNAR-0' || n.contrato, 'banco', 'BCP', 'moneda', 'PEN',
                      'ultimos', case when length(n.numero) >= 8 then right(n.numero, 4) end);
      v_llamada := format('select (crm.asignar_cuenta_pago_contrato(%L::uuid, %L::uuid, %L::uuid, %L))::text',
                          pg_temp.sol(210 + n.contrato), pg_temp.xc(n.contrato), v_cta, pg_temp.k('motivo_bueno'));
      perform pg_temp.igual(format('T2 número de %s caracteres: «ultimos» es %s', length(n.numero),
                                   case when length(n.numero) >= 8 then 'los 4 últimos' else 'null (nunca el número entero)' end),
        'OK:' || v_esperado::text, pg_temp.como('admin', array[pg_temp.k('puerta'), pg_temp.k('nucleo')], v_llamada));
      perform pg_temp.igual(format('T2 número de %s caracteres: la repetición devuelve lo mismo, con ya_aplicada', length(n.numero)),
        'OK:' || (v_esperado || jsonb_build_object('ya_aplicada', true))::text,
        pg_temp.como('admin', array[pg_temp.k('puerta'), pg_temp.k('nucleo')], v_llamada));
    end loop;
    raise exception using errcode = 'P0001', message = 'ASIGNAR_DESHACER';
  exception when others then
    if sqlerrm <> 'ASIGNAR_DESHACER' then raise; end if;
  end;
  return 'vínculo con la cuenta elegida y creado_por = quien asigna; constancia completa con el motivo recortado; una fila de bitácora del vínculo y otra de la constancia, con su autor; retorno de seis claves sin datos sensibles; «ultimos» son los 4 últimos solo si el número tiene 8 o más caracteres (con 4 y con 7 viene null, también en la repetición); ninguna otra tabla cambió';
end;
$f$;

-- ══ T3 · Después se paga ════════════════════════════════════════════════════════════════════
create function pg_temp.t3_despues_se_paga() returns text language plpgsql as $f$
declare
  K4 constant uuid := pg_temp.c(4);          -- REZAGO-04, USD, cliente D, con la cuota 0 ya pagada y sin sello
  A7 constant uuid := pg_temp.cta(7);        -- la única USD activa de D
  K2X constant uuid := pg_temp.xc(2);        -- ASIGNAR-02, VENCIDO
  A1X constant uuid := pg_temp.xcta(1);
  PAGADA_ANTES constant uuid := 'c9ee0000-0000-4000-8000-000000000400';
  MOT constant text := pg_temp.k('motivo_bueno');
  v_cci text;
  v_cci_otra text;
  v_desvinculados integer;
  v_previos uuid[];
  v_sellos text;
  a text;
  r text;
begin
  v_desvinculados := pg_temp.mundo_sembrado();
  select cb.cci into strict v_cci from crm.cuentas_bancarias cb where cb.id = A7;
  select cb.cci into strict v_cci_otra from crm.cuentas_bancarias cb where cb.id = pg_temp.cta(8);   -- la PEN de D
  perform pg_temp.igual('T3 testigo: REZAGO-04 no tiene vínculo y su cuota 0 está pagada sin sello', 'sin vínculo/pagado/0',
    pg_temp.vinculo(K4) || '/' || (select q.estado from public.cronograma_pagos q where q.id = PAGADA_ANTES) || '/' ||
    (select count(*) from crm.cuotas_cuenta_pagada s where s.cuota_id = PAGADA_ANTES));

  -- Antes de asignar: el bloqueo de pagos rechaza (23514), declare o no el CCI, sea quien sea el gestor.
  foreach a in array array['oper', 'admin'] loop
    r := pg_temp.pagar(a, pg_temp.cuota(4, 1));
    perform pg_temp.cierto(format('T3 antes de asignar, %s no puede pagar (23514)', a), r like 'ERR:23514:%', r);
    r := pg_temp.pagar(a, pg_temp.cuota(4, 1), v_cci);
    perform pg_temp.cierto(format('T3 antes de asignar, %s tampoco declarando el CCI (23514)', a), r like 'ERR:23514:%', r);
  end loop;
  perform pg_temp.igual('T3 los intentos rechazados no dejaron la cuota pagada ni sellos', 'pendiente/0',
    (select q.estado from public.cronograma_pagos q where q.id = pg_temp.cuota(4, 1)) || '/' || (select count(*) from crm.cuotas_cuenta_pagada));

  -- Sellos PREVIOS a la asignación, que no deben moverse: el de un pago de otro contrato (REZAGO-01,
  -- que ya tenía cuenta) y uno de este mismo contrato puesto a mano (inferido, en la otra cuenta del cliente).
  perform pg_temp.igual('T3 preparación: un pago de otro contrato deja su sello', 'PAGADO:' || pg_temp.cta(1) || ':registro', pg_temp.pagar('oper', pg_temp.cuota(1, 1)));
  insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen, sellada_en)
  values (gen_random_uuid(), K4, pg_temp.cta(8), 'inferido', timestamptz '2026-05-05 12:00+00');
  select array_agg(s.id order by s.id), count(*) || ':' || md5(string_agg(md5(to_jsonb(s)::text), ',' order by s.id))
    into v_previos, v_sellos from crm.cuotas_cuenta_pagada s;
  perform pg_temp.igual('T3 preparación: hay dos sellos previos (uno de otro contrato y uno de este)', '2', cardinality(v_previos)::text);

  r := pg_temp.asignar('admin', pg_temp.sol(301), K4, A7, MOT);
  perform pg_temp.cierto('T3 admin asigna a REZAGO-04 su cuenta en dólares', r like 'OK:%', r);
  perform pg_temp.igual('T3 asignar NO sella la cuota que el contrato ya tenía pagada', 'pagado/0',
    (select q.estado from public.cronograma_pagos q where q.id = PAGADA_ANTES) || '/' ||
    (select count(*) from crm.cuotas_cuenta_pagada s where s.cuota_id = PAGADA_ANTES));
  perform pg_temp.igual('T3 asignar no crea ni toca ningún sello: los sellos previos siguen idénticos (todas sus columnas)', v_sellos,
    (select count(*) || ':' || md5(string_agg(md5(to_jsonb(s)::text), ',' order by s.id)) from crm.cuotas_cuenta_pagada s));

  -- Después: se paga y queda sellado en la cuenta asignada.
  perform pg_temp.igual('T3 operaciones paga la cuota 1 DECLARANDO el CCI de la cuenta asignada', 'PAGADO:' || A7 || ':declarado',
    pg_temp.pagar('oper', pg_temp.cuota(4, 1), v_cci));
  perform pg_temp.igual('T3 la cuota 1 quedó pagada, a nombre de operaciones', 'pagado|c9e00000-0000-4000-8000-000000000002|100.00',
    (select q.estado || '|' || q.registrado_por || '|' || q.monto_pagado from public.cronograma_pagos q where q.id = pg_temp.cuota(4, 1)));
  perform pg_temp.igual('T3 operaciones paga la cuota 2 SIN declarar la cuenta', 'PAGADO:' || A7 || ':registro',
    pg_temp.pagar('oper', pg_temp.cuota(4, 2)));
  r := pg_temp.pagar('admin', pg_temp.cuota(4, 3), v_cci_otra);
  perform pg_temp.igual('T3 declarar el CCI de OTRA cuenta del cliente (la que no se asignó) se rechaza',
    'ERR:22023:El CCI del depósito no es de una cuenta de pago de este contrato', r);
  perform pg_temp.igual('T3 admin paga la cuota 3 declarando el CCI bueno', 'PAGADO:' || A7 || ':declarado', pg_temp.pagar('admin', pg_temp.cuota(4, 3), v_cci));
  perform pg_temp.igual('T3 los tres pagos posteriores crean tres sellos NUEVOS, los tres en la cuenta asignada; la cuota 0 sigue sin sello',
    '3/3/0',
    (select count(*) from crm.cuotas_cuenta_pagada s where s.contrato_id = K4 and s.id <> all (v_previos)) || '/' ||
    (select count(*) from crm.cuotas_cuenta_pagada s where s.contrato_id = K4 and s.id <> all (v_previos) and s.cuenta_bancaria_id = A7) || '/' ||
    (select count(*) from crm.cuotas_cuenta_pagada s where s.cuota_id = PAGADA_ANTES));
  perform pg_temp.igual('T3 tras los pagos, los sellos previos siguen idénticos (ni re-sellados ni movidos a la cuenta asignada)', v_sellos,
    (select count(*) || ':' || md5(string_agg(md5(to_jsonb(s)::text), ',' order by s.id)) from crm.cuotas_cuenta_pagada s where s.id = any (v_previos)));

  -- Un contrato VENCIDO es un contrato abierto: se asigna y se paga igual.
  r := pg_temp.pagar('oper', pg_temp.xcuota(2, 1));
  perform pg_temp.cierto('T3 antes de asignar, la cuota del contrato vencido no se paga (23514)', r like 'ERR:23514:%', r);
  r := pg_temp.asignar('super', pg_temp.sol(302), K2X, A1X, MOT);
  perform pg_temp.cierto('T3 superadmin asigna a un contrato VENCIDO', r like 'OK:%', r);
  perform pg_temp.igual('T3 la cuota del contrato vencido se paga y queda sellada', 'PAGADO:' || A1X || ':registro', pg_temp.pagar('oper', pg_temp.xcuota(2, 1)));
  return format('antes de asignar el pago cae con 23514 (operaciones y admin, con y sin CCI); después se paga y se sella en la cuenta asignada (declarado y registro); el CCI de otra cuenta del cliente se rechaza; la cuota que ya estaba pagada sigue sin sello; los sellos previos (de otro contrato y de este) quedan intactos al asignar y al pagar después; un contrato vencido también se asigna y se paga%s',
    case when v_desvinculados > 0 then format(' · (se retiraron en el tramo los %s vínculos de la carga de la otra migración)', v_desvinculados) else '' end);
end;
$f$;

-- Monta, SOLO dentro de un sub-bloque que se deshace, un disparador de prueba BEFORE INSERT sobre el
-- vínculo que lanza una violación de unicidad y devuelve lo que recibe quien asigna. Clases:
--   real_bitacora un 23505 DE VERDAD de otra tabla (dos filas con el mismo id en public.audit_log)
--   otro_esquema un 23505 que dice venir de public.contrato_cuentas_pago (mismo nombre, otro esquema)
--   otra_tabla   un 23505 que dice venir de crm.otra_tabla
--   sin_origen   un 23505 sin esquema ni tabla
--   pk_del_vinculo  un 23505 DE VERDAD del propio vínculo, pero de su clave primaria (el disparador le pone
--                   al vínculo nuevo el id de uno que ya existe): no es «el contrato ya tiene cuenta»
--   sin_restriccion un 23505 que dice venir de crm.contrato_cuentas_pago, sin nombre de restricción
--   otra_restriccion un 23505 de crm.contrato_cuentas_pago con otra restricción
--   esquema_ajeno_misma_restriccion  un 23505 de public.contrato_cuentas_pago con el MISMO nombre de restricción
--   tabla_ajena_misma_restriccion    un 23505 de crm.otra_tabla con el MISMO nombre de restricción
--   el_vinculo   un 23505 de crm.contrato_cuentas_pago y de su restricción contrato_cuentas_pago_contrato_id_key
--                (el testigo: ese SÍ se traduce)
create function pg_temp.unicidad_ajena(p_clase text, p_contrato uuid, p_cuenta uuid) returns text language plpgsql as $f$
declare
  r text;
begin
  begin
    execute format($d$create function private.zz_prueba_unicidad_ajena() returns trigger language plpgsql set search_path to '' as $t$
      begin
        %s
        return new;
      end;
      $t$ $d$,
      case p_clase
        when 'real_bitacora' then $x$insert into public.audit_log (id, tabla, operacion) values
          ('a519b000-0000-4000-8000-000000000001', 'prueba', 'INSERT'), ('a519b000-0000-4000-8000-000000000001', 'prueba', 'INSERT');$x$
        when 'otro_esquema' then $x$raise exception using errcode = '23505', message = 'duplicado ajeno de prueba', schema = 'public', table = 'contrato_cuentas_pago';$x$
        when 'otra_tabla'   then $x$raise exception using errcode = '23505', message = 'duplicado ajeno de prueba', schema = 'crm', table = 'otra_tabla';$x$
        when 'sin_origen'   then $x$raise exception using errcode = '23505', message = 'duplicado ajeno de prueba';$x$
        when 'pk_del_vinculo' then $x$new.id := (select l.id from crm.contrato_cuentas_pago l order by l.id limit 1);$x$
        when 'sin_restriccion' then $x$raise exception using errcode = '23505', message = 'duplicado ajeno de prueba', schema = 'crm', table = 'contrato_cuentas_pago';$x$
        when 'otra_restriccion' then $x$raise exception using errcode = '23505', message = 'duplicado ajeno de prueba', schema = 'crm', table = 'contrato_cuentas_pago', constraint = 'contrato_cuentas_pago_otra_key';$x$
        when 'esquema_ajeno_misma_restriccion' then $x$raise exception using errcode = '23505', message = 'duplicado ajeno de prueba', schema = 'public', table = 'contrato_cuentas_pago', constraint = 'contrato_cuentas_pago_contrato_id_key';$x$
        when 'tabla_ajena_misma_restriccion' then $x$raise exception using errcode = '23505', message = 'duplicado ajeno de prueba', schema = 'crm', table = 'otra_tabla', constraint = 'contrato_cuentas_pago_contrato_id_key';$x$
        when 'el_vinculo'   then $x$raise exception using errcode = '23505', message = 'duplicado de prueba', schema = 'crm', table = 'contrato_cuentas_pago', constraint = 'contrato_cuentas_pago_contrato_id_key';$x$
      end);
    execute 'create trigger zz_prueba_unicidad_ajena before insert on crm.contrato_cuentas_pago
             for each row execute function private.zz_prueba_unicidad_ajena()';
    r := pg_temp.asignar('admin', gen_random_uuid(), p_contrato, p_cuenta, pg_temp.k('motivo_bueno'));
    raise exception using errcode = 'P0001', message = 'ASIGNAR_DESHACER';
  exception when others then
    if sqlerrm <> 'ASIGNAR_DESHACER' then raise; end if;
  end;
  return r;
end;
$f$;

-- ══ T4 · Rechazos ═══════════════════════════════════════════════════════════════════════════
create function pg_temp.t4_rechazos() returns text language plpgsql as $f$
declare
  K1 constant uuid := pg_temp.xc(1);
  A1 constant uuid := pg_temp.xcta(1);
  MOT constant text := pg_temp.k('motivo_bueno');
  -- Los «espacios» que el motivo no cuenta: los de [[:space:]] y los Unicode que la migración lista.
  v_blancos constant integer[] := array[32, 9, 10, 11, 12, 13, 160, 5760]
    || array(select generate_series(8192, 8203)) || array[8232, 8233, 8239, 8287, 12288, 65279];
  -- Invisibles que la lista NO trae (se miden y se informan; no son parte del contrato).
  v_fuera constant integer[] := array[133, 173, 6158, 8204, 8205, 8288];
  v_huella text;
  v_conteos jsonb;
  v_pasan text := '';
  v_n integer := 0;
  n integer;
  b text;
  r text;
begin
  -- Un contrato «recién asignado», para el rechazo de «ya tiene cuenta» (lo único que este tramo escribe).
  r := pg_temp.asignar('admin', pg_temp.sol(401), pg_temp.xc(5), pg_temp.xcta(3), MOT);
  perform pg_temp.cierto('T4 preparación: ASIGNAR-05 (USD) recibe su cuenta', r like 'OK:%', r);
  v_huella := pg_temp.huella_mundo();
  v_conteos := pg_temp.conteos();

  -- La cuenta.
  perform pg_temp.igual('T4 cuenta de otro cliente (REZAGO-07 con una cuenta de H)', format(pg_temp.k('ajena'), 'REZAGO-07'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(7), pg_temp.cta(16), MOT));
  perform pg_temp.igual('T4 cuenta de otro cliente (ASIGNAR-01 con la cuenta de Q)', format(pg_temp.k('ajena'), 'ASIGNAR-01'),
    pg_temp.asignar('admin', gen_random_uuid(), K1, pg_temp.xcta(11), MOT));
  perform pg_temp.igual('T4 cuenta en otra moneda (REZAGO-08 es USD y la cuenta PEN)', format(pg_temp.k('moneda'), 'REZAGO-08', 'USD', 'PEN'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(8), pg_temp.cta(15), MOT));
  perform pg_temp.igual('T4 cuenta en otra moneda (REZAGO-10 es PEN y la cuenta USD)', format(pg_temp.k('moneda'), 'REZAGO-10', 'PEN', 'USD'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(10), pg_temp.cta(17), MOT));
  perform pg_temp.igual('T4 cuenta en otra moneda (ASIGNAR-01 es PEN y la cuenta USD)', format(pg_temp.k('moneda'), 'ASIGNAR-01', 'PEN', 'USD'),
    pg_temp.asignar('super', gen_random_uuid(), K1, pg_temp.xcta(3), MOT));
  perform pg_temp.igual('T4 cuenta inactiva (REZAGO-12 con la única cuenta del cliente, retirada)', pg_temp.k('no_vigente'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(12), pg_temp.cta(19), MOT));
  perform pg_temp.igual('T4 cuenta inactiva (ASIGNAR-01 con la cuenta retirada de P)', pg_temp.k('no_vigente'),
    pg_temp.asignar('admin', gen_random_uuid(), K1, pg_temp.xcta(4), MOT));
  perform pg_temp.igual('T4 cuenta inexistente', pg_temp.k('no_cuenta'),
    pg_temp.asignar('admin', gen_random_uuid(), K1, 'a519c000-0000-4000-8000-0000000000ff', MOT));
  perform pg_temp.igual('T4 el id de un CONTRATO en el lugar de la cuenta: tampoco existe', pg_temp.k('no_cuenta'),
    pg_temp.asignar('admin', gen_random_uuid(), K1, K1, MOT));

  -- El contrato.
  perform pg_temp.igual('T4 contrato inexistente', pg_temp.k('no_contrato'),
    pg_temp.asignar('admin', gen_random_uuid(), 'a519d000-0000-4000-8000-0000000000ff', A1, MOT));
  perform pg_temp.igual('T4 cuenta y contrato inexistentes: avisa primero de la cuenta', pg_temp.k('no_cuenta'),
    pg_temp.asignar('admin', gen_random_uuid(), 'a519d000-0000-4000-8000-0000000000ff', 'a519c000-0000-4000-8000-0000000000ff', MOT));
  perform pg_temp.igual('T4 contrato con cuenta (REZAGO-01, ok) y la misma cuenta', format(pg_temp.k('ya_tiene'), 'REZAGO-01'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(1), pg_temp.cta(1), MOT));
  perform pg_temp.igual('T4 contrato con cuenta (REZAGO-02, cuya cuenta vinculada está inactiva) y OTRA cuenta vigente del cliente',
    format(pg_temp.k('ya_tiene'), 'REZAGO-02'), pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(2), pg_temp.cta(3), MOT));
  perform pg_temp.igual('T4 contrato con un vínculo que no corresponde (REZAGO-14) y la cuenta propia del cliente: no se «arregla» por aquí',
    format(pg_temp.k('ya_tiene'), 'REZAGO-14'), pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(14), pg_temp.cta(20), MOT));
  perform pg_temp.igual('T4 contrato recién asignado (ASIGNAR-05) con otra solicitud y otra cuenta', format(pg_temp.k('ya_tiene'), 'ASIGNAR-05'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.xc(5), pg_temp.xcta(5), MOT));
  perform pg_temp.igual('T4 contrato recién asignado con otra solicitud y la MISMA cuenta', format(pg_temp.k('ya_tiene'), 'ASIGNAR-05'),
    pg_temp.asignar('super', gen_random_uuid(), pg_temp.xc(5), pg_temp.xcta(3), MOT));
  perform pg_temp.igual('T4 contrato cerrado (renovado)', format(pg_temp.k('cerrado'), 'ASIGNAR-03', 'renovado'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.xc(3), A1, MOT));
  perform pg_temp.igual('T4 contrato cerrado (retirado)', format(pg_temp.k('cerrado'), 'ASIGNAR-04', 'retirado'),
    pg_temp.asignar('super', gen_random_uuid(), pg_temp.xc(4), A1, MOT));

  -- Parámetros nulos, uno por uno.
  perform pg_temp.igual('T4 solicitud nula', pg_temp.k('faltan'), pg_temp.asignar('admin', null, K1, A1, MOT));
  perform pg_temp.igual('T4 contrato nulo', pg_temp.k('faltan'), pg_temp.asignar('admin', gen_random_uuid(), null, A1, MOT));
  perform pg_temp.igual('T4 cuenta nula', pg_temp.k('faltan'), pg_temp.asignar('admin', gen_random_uuid(), K1, null, MOT));
  perform pg_temp.igual('T4 todo nulo', pg_temp.k('faltan'), pg_temp.asignar('admin', null, null, null, null));
  perform pg_temp.igual('T4 motivo nulo', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, null));

  -- El motivo.
  perform pg_temp.igual('T4 motivo vacío', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, ''));
  perform pg_temp.igual('T4 motivo de 4 visibles', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, 'abcd'));
  perform pg_temp.igual('T4 motivo de 4 visibles separados por espacios', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, 'a b  c d'));
  perform pg_temp.igual('T4 motivo solo de espacios', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, '          '));
  perform pg_temp.igual('T4 motivo solo de tabuladores y saltos', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, E'\t\t\n\r\t\n\t'));
  perform pg_temp.igual('T4 motivo de 501 caracteres', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, repeat('x', 501)));
  perform pg_temp.igual('T4 motivo de 501 caracteres con espacios dentro', pg_temp.k('motivo'), pg_temp.asignar('admin', gen_random_uuid(), K1, A1, repeat('xxxx ', 100) || 'y'));
  foreach n in array v_blancos loop
    b := chr(n);
    perform pg_temp.igual(format('T4 motivo solo de U+%s (seis seguidos)', to_hex(n)), pg_temp.k('motivo'),
      pg_temp.asignar('admin', gen_random_uuid(), K1, A1, repeat(b, 6)));
    perform pg_temp.igual(format('T4 4 visibles rodeados de U+%s', to_hex(n)), pg_temp.k('motivo'),
      pg_temp.asignar('admin', gen_random_uuid(), K1, A1, b || b || 'abcd' || b));
    perform pg_temp.igual(format('T4 4 visibles con U+%s en medio (los de dentro tampoco cuentan)', to_hex(n)), pg_temp.k('motivo'),
      pg_temp.asignar('admin', gen_random_uuid(), K1, A1, 'ab' || b || b || 'cd'));
    v_n := v_n + 1;
  end loop;
  perform pg_temp.cierto('T4 se probaron los 26 espacios (6 ASCII y 20 Unicode)', v_n = 26, v_n::text);

  perform pg_temp.igual('T4 ningún rechazo escribió nada (huella de todas las tablas tocables y de la bitácora)', v_huella, pg_temp.huella_mundo());
  perform pg_temp.igual('T4 ningún rechazo cambió el número de filas de ninguna tabla', '(nada)', pg_temp.diferencia(v_conteos, pg_temp.conteos()));

  -- Una violación de unicidad AJENA (no la del vínculo por contrato) sube tal cual: no se disfraza de
  -- «ya tiene cuenta de pago». Se provoca con un disparador de prueba sobre el vínculo (se va con el tramo).
  foreach b in array array['real_bitacora', 'otro_esquema', 'otra_tabla', 'sin_origen', 'pk_del_vinculo', 'sin_restriccion', 'otra_restriccion',
                           'esquema_ajeno_misma_restriccion', 'tabla_ajena_misma_restriccion'] loop
    r := pg_temp.unicidad_ajena(b, K1, A1);
    perform pg_temp.cierto(format('T4 un 23505 ajeno (%s) sube como 23505', b), r like 'ERR:23505:%', r);
    perform pg_temp.cierto(format('T4 un 23505 ajeno (%s) NO sale como «ya tiene cuenta de pago»', b), r not like '%ya tiene cuenta de pago%', r);
  end loop;
  perform pg_temp.igual('T4 la colisión de la CLAVE PRIMARIA del vínculo sube cruda, con el nombre de su restricción',
    'ERR:23505:duplicate key value violates unique constraint "contrato_cuentas_pago_pkey"', pg_temp.unicidad_ajena('pk_del_vinculo', K1, A1));
  perform pg_temp.igual('T4 testigo: la violación de la unicidad POR CONTRATO del vínculo SÍ se traduce (el filtro es por restricción, no un «todo sube»)',
    format(pg_temp.k('ya_tiene'), 'ASIGNAR-01'), pg_temp.unicidad_ajena('el_vinculo', K1, A1));
  perform pg_temp.igual('T4 las violaciones de unicidad provocadas no escribieron nada', v_huella, pg_temp.huella_mundo());

  -- Los bordes que SÍ pasan (cada uno se deshace): el recorte no rechaza lo válido.
  perform pg_temp.igual('T4 pasa: 5 visibles justos', 'OK cuenta=' || A1 || ' motivo=«abcde»', pg_temp.ensayo('admin', K1, A1, 'abcde'));
  perform pg_temp.igual('T4 pasa: 5 visibles con espacios dentro (se guardan tal cual)', 'OK cuenta=' || A1 || ' motivo=«a b c d e»', pg_temp.ensayo('admin', K1, A1, 'a b c d e'));
  perform pg_temp.igual('T4 pasa: 5 letras con tilde y eñe (cuenta caracteres, no bytes)', 'OK cuenta=' || A1 || ' motivo=«ñandú»', pg_temp.ensayo('admin', K1, A1, 'ñandú'));
  perform pg_temp.igual('T4 pasa: 500 caracteres justos', 'OK cuenta=' || A1 || ' motivo=«' || repeat('x', 500) || '»', pg_temp.ensayo('admin', K1, A1, repeat('x', 500)));
  perform pg_temp.igual('T4 pasa: 500 caracteres con espacios en los bordes (se recorta ANTES de medir)', 'OK cuenta=' || A1 || ' motivo=«' || repeat('x', 500) || '»',
    pg_temp.ensayo('admin', K1, A1, E' \t' || repeat('x', 500) || chr(160) || ' '));
  foreach n in array v_blancos loop
    b := chr(n);
    perform pg_temp.igual(format('T4 pasa: 5 visibles rodeados de U+%s → se guarda sin los bordes', to_hex(n)), 'OK cuenta=' || A1 || ' motivo=«abcde»',
      pg_temp.ensayo('admin', K1, A1, b || 'abcde' || b || b));
    perform pg_temp.igual(format('T4 pasa: U+%s en medio se conserva', to_hex(n)), 'OK cuenta=' || A1 || ' motivo=«abc' || b || 'de»',
      pg_temp.ensayo('admin', K1, A1, 'abc' || b || 'de'));
  end loop;
  perform pg_temp.igual('T4 los bordes que pasan se deshicieron: el mundo sigue igual', v_huella, pg_temp.huella_mundo());

  -- Medición (no es parte del contrato): invisibles que la lista no trae y que cuentan como «visibles».
  foreach n in array v_fuera loop
    if pg_temp.ensayo('admin', K1, A1, repeat(chr(n), 5)) like 'OK%' then
      v_pasan := v_pasan || ' U+' || upper(to_hex(n));
    end if;
  end loop;
  return format('cada rechazo con su mensaje exacto y sin escribir nada: cuenta ajena, otra moneda, inactiva, inexistente; contrato inexistente, con cuenta (ok, incoherente y recién asignado), cerrado (renovado y retirado); nulos uno a uno; motivo vacío, corto, en blanco, de 501 y los 26 espacios; un 23505 ajeno (otra tabla, otro esquema —aun con el mismo nombre de restricción—, la clave primaria del vínculo u otra restricción) sube tal cual · MEDIDO, fuera del contrato: cinco caracteres invisibles que la lista no trae pasan como motivo válido →%s',
    case when v_pasan = '' then ' ninguno' else v_pasan end);
end;
$f$;

-- ══ T5 · Idempotencia ═══════════════════════════════════════════════════════════════════════
create function pg_temp.t5_idempotencia() returns text language plpgsql as $f$
declare
  K1 constant uuid := pg_temp.xc(1);
  K2 constant uuid := pg_temp.xc(2);
  A1 constant uuid := pg_temp.xcta(1);
  A2 constant uuid := pg_temp.xcta(2);
  S1 constant uuid := pg_temp.sol(501);
  MOT constant text := pg_temp.k('motivo_bueno');
  -- La repetición devuelve LAS MISMAS claves que la primera vez, con ya_aplicada = true.
  v_repetida constant text := 'OK:' || jsonb_build_object('solicitud_id', S1, 'ya_aplicada', true, 'numero_contrato', 'ASIGNAR-01',
                                                          'banco', 'BCP', 'moneda', 'PEN', 'ultimos', '0001')::text;
  v_primera text;
  v_huella text;
  v_conteos jsonb;
  r text;
begin
  r := pg_temp.asignar('admin', S1, K1, A1, MOT);
  perform pg_temp.cierto('T5 la primera vez se aplica', r like 'OK:%' and (substr(r, 4)::jsonb ->> 'ya_aplicada') = 'false', r);
  v_primera := (substr(r, 4)::jsonb || jsonb_build_object('ya_aplicada', true))::text;
  v_huella := pg_temp.huella_mundo();
  v_conteos := pg_temp.conteos();

  perform pg_temp.igual('T5 misma solicitud, mismos datos (doble clic): ya_aplicada', v_repetida, pg_temp.asignar('admin', S1, K1, A1, MOT));
  perform pg_temp.igual('T5 la repetición devuelve EXACTAMENTE lo mismo que la primera vez, salvo ya_aplicada', 'OK:' || v_primera, pg_temp.asignar('admin', S1, K1, A1, MOT));
  perform pg_temp.igual('T5 misma solicitud y el motivo con espacios en los bordes: es el mismo motivo', v_repetida,
    pg_temp.asignar('admin', S1, K1, A1, E'  \t' || MOT || chr(160) || ' '));
  perform pg_temp.igual('T5 misma solicitud y mismos datos enviados por OTRA administradora: ya_aplicada (el autor no es parte de los datos)', v_repetida,
    pg_temp.asignar('super', S1, K1, A1, MOT));
  perform pg_temp.igual('T5 misma solicitud repetida por quien NO es administración: 42501 (la compuerta va antes)', pg_temp.k('no_admin'),
    pg_temp.asignar('oper', S1, K1, A1, MOT));
  perform pg_temp.igual('T5 misma solicitud con OTRA cuenta', pg_temp.k('usada'), pg_temp.asignar('admin', S1, K1, A2, MOT));
  perform pg_temp.igual('T5 misma solicitud con OTRO contrato', pg_temp.k('usada'), pg_temp.asignar('admin', S1, K2, A1, MOT));
  perform pg_temp.igual('T5 misma solicitud con OTRO motivo', pg_temp.k('usada'), pg_temp.asignar('admin', S1, K1, A1, MOT || ' (corregido)'));
  perform pg_temp.igual('T5 misma solicitud con el motivo en otras mayúsculas', pg_temp.k('usada'), pg_temp.asignar('admin', S1, K1, A1, upper(MOT)));
  perform pg_temp.igual('T5 misma solicitud con una cuenta que no existe: «otros datos», no «no existe»', pg_temp.k('usada'),
    pg_temp.asignar('admin', S1, K1, 'a519c000-0000-4000-8000-0000000000ff', MOT));
  perform pg_temp.igual('T5 OTRA solicitud para el mismo contrato y los mismos datos', format(pg_temp.k('ya_tiene'), 'ASIGNAR-01'),
    pg_temp.asignar('admin', pg_temp.sol(502), K1, A1, MOT));
  perform pg_temp.igual('T5 OTRA solicitud para el mismo contrato y otra cuenta', format(pg_temp.k('ya_tiene'), 'ASIGNAR-01'),
    pg_temp.asignar('admin', pg_temp.sol(503), K1, A2, MOT));
  perform pg_temp.igual('T5 repeticiones y rechazos: cero filas nuevas y nada cambiado', v_huella, pg_temp.huella_mundo());
  perform pg_temp.igual('T5 repeticiones y rechazos: ninguna tabla cambió de tamaño', '(nada)', pg_temp.diferencia(v_conteos, pg_temp.conteos()));

  -- La repetición sigue respondiendo «ya aplicada» aunque el mundo cambie después (se mira ANTES que la cuenta y el contrato).
  update crm.cuentas_bancarias set activa = false, desactivada_por = 'c9e00000-0000-4000-8000-000000000001', desactivada_en = now() where id = A1;
  perform pg_temp.igual('T5 repetida después de que la cuenta dejara de estar vigente: sigue siendo ya_aplicada', v_repetida, pg_temp.asignar('admin', S1, K1, A1, MOT));

  -- La misma cuenta sirve para otro contrato del cliente, con su propia solicitud.
  r := pg_temp.asignar('admin', pg_temp.sol(504), K2, A2, MOT);
  perform pg_temp.cierto('T5 otra solicitud, otro contrato: se aplica', r like 'OK:%' and (substr(r, 4)::jsonb ->> 'ya_aplicada') = 'false', r);
  perform pg_temp.igual('T5 al final hay dos constancias y dos vínculos nuevos, uno por solicitud aplicada', '2/2',
    (select count(*) from crm.contrato_cuenta_pago_asignaciones) || '/' ||
    (select count(*) from crm.contrato_cuentas_pago x where x.contrato_id in (K1, K2)));
  return 'misma solicitud y mismos datos → ya_aplicada sin escribir (también con el motivo sin recortar, con otra administradora y con la cuenta ya inactiva); con otra cuenta, otro contrato u otro motivo → 22023; otra solicitud para el mismo contrato → «ya tiene cuenta de pago»; quien no es administración recibe 42501 aunque repita una solicitud aplicada';
end;
$f$;

-- ══ T6 · Elegir entre varias, y la propiedad ════════════════════════════════════════════════
create function pg_temp.t6_elegir() returns text language plpgsql as $f$
declare
  MOT constant text := pg_temp.k('motivo_bueno');
  v_desvinculados integer;
  v_nueva uuid;
  v_ensayos integer := 0;
  v_pasan integer := 0;
  k record;
  c record;
  r text;
  v_espera boolean;
begin
  v_desvinculados := pg_temp.mundo_sembrado();

  -- La propiedad, sobre TODOS los contratos sin vínculo y TODAS las cuentas del banco (cada ensayo se
  -- deshace): asignar pasa ⇔ el contrato está abierto y la cuenta es vigente, del mismo cliente y moneda.
  for k in
    select ct.id, ct.numero_contrato, ct.cliente_id, ct.moneda, ct.estado
    from public.contratos ct
    where not exists (select 1 from crm.contrato_cuentas_pago l where l.contrato_id = ct.id)
    order by ct.numero_contrato
  loop
    for c in select cb.id, cb.cliente_id, cb.moneda, cb.activa from crm.cuentas_bancarias cb order by cb.id loop
      v_espera := k.estado in ('activo', 'vencido') and c.activa and c.cliente_id = k.cliente_id and c.moneda = k.moneda;
      r := pg_temp.ensayo('admin', k.id, c.id, MOT);
      perform pg_temp.igual(format('T6 propiedad: %s (%s, %s) con la cuenta %s (%s, activa=%s, %s cliente)', k.numero_contrato, k.estado, k.moneda,
                                   c.id, c.moneda, c.activa, case when c.cliente_id = k.cliente_id then 'mismo' else 'otro' end),
        v_espera::text, (r like 'OK cuenta=' || c.id || ' %')::text);
      perform pg_temp.cierto(format('T6 propiedad: lo que no pasa es un rechazo de regla (22023), no otro error (%s con %s)', k.numero_contrato, c.id),
        r like 'OK %' or r like 'ERR:22023:%', r);
      v_ensayos := v_ensayos + 1;
      if v_espera then v_pasan := v_pasan + 1; end if;
    end loop;
  end loop;
  perform pg_temp.cierto('T6 la propiedad se probó sobre un mundo con contenido (≥ 600 ensayos, ≥ 30 válidos)', v_ensayos >= 600 and v_pasan >= 30,
    format('%s ensayos, %s válidos', v_ensayos, v_pasan));
  perform pg_temp.igual('T6 los ensayos de la propiedad no dejaron ninguna constancia', '0', (select count(*)::text from crm.contrato_cuenta_pago_asignaciones));

  -- varias_cuentas: se asigna la SEGUNDA (la que está a nombre de un tercero) y es la que queda.
  r := pg_temp.asignar('admin', pg_temp.sol(601), pg_temp.c(7), pg_temp.cta(11), MOT);
  perform pg_temp.cierto('T6 REZAGO-07 (dos cuentas en soles): se asigna la segunda', r like 'OK:%' and (substr(r, 4)::jsonb ->> 'banco') = 'Scotiabank', r);
  perform pg_temp.igual('T6 REZAGO-07 cobra en la segunda cuenta', pg_temp.cta(11) || '|c9e00000-0000-4000-8000-000000000001', pg_temp.vinculo(pg_temp.c(7)));
  perform pg_temp.igual('T6 REZAGO-07 se paga y se sella en la segunda cuenta', 'PAGADO:' || pg_temp.cta(11) || ':registro', pg_temp.pagar('oper', pg_temp.cuota(7, 1)));
  r := pg_temp.asignar('super', pg_temp.sol(602), pg_temp.c(8), pg_temp.cta(14), MOT);
  perform pg_temp.cierto('T6 REZAGO-08 (tres cuentas en dólares): se asigna la tercera', r like 'OK:%' and (substr(r, 4)::jsonb ->> 'banco') = 'BBVA', r);
  perform pg_temp.igual('T6 REZAGO-08 cobra en la tercera cuenta', pg_temp.cta(14)::text, split_part(pg_temp.vinculo(pg_temp.c(8)), '|', 1));

  -- una_cuenta: su única cuenta.
  r := pg_temp.asignar('admin', pg_temp.sol(603), pg_temp.c(3), pg_temp.cta(4), MOT);
  perform pg_temp.cierto('T6 REZAGO-03 (una cuenta en soles): se asigna su única cuenta', r like 'OK:%', r);
  r := pg_temp.asignar('admin', pg_temp.sol(604), pg_temp.c(5), pg_temp.cta(9), MOT);
  perform pg_temp.cierto('T6 REZAGO-05 (una cuenta para dos contratos): se asigna', r like 'OK:%', r);
  r := pg_temp.asignar('admin', pg_temp.sol(605), pg_temp.c(6), pg_temp.cta(9), MOT);
  perform pg_temp.cierto('T6 REZAGO-06 (el otro contrato del mismo cliente): se asigna la MISMA cuenta', r like 'OK:%', r);
  perform pg_temp.igual('T6 REZAGO-03 se paga', 'PAGADO:' || pg_temp.cta(4) || ':registro', pg_temp.pagar('oper', pg_temp.cuota(3, 1)));

  -- otra_moneda: REZAGO-09 es en dólares y H solo tiene una cuenta en soles. Se registra una y entonces sí.
  perform pg_temp.igual('T6 REZAGO-09 (otra_moneda): la única cuenta del cliente no vale', format(pg_temp.k('moneda'), 'REZAGO-09', 'USD', 'PEN'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(9), pg_temp.cta(16), MOT));
  r := pg_temp.registrar_cuenta('oper', 'c9e00000-0000-4000-8000-000000000018',
         '{"moneda": "USD", "banco": "BCP", "tipo_cuenta": "ahorros", "numero_cuenta": "19151900000091", "cci": "00251900000000000091"}');
  perform pg_temp.cierto('T6 operaciones registra una cuenta en dólares para H (por la puerta real)', r like 'OK:%' and r <> 'OK:(null)', r);
  v_nueva := substr(r, 4)::uuid;
  r := pg_temp.asignar('admin', pg_temp.sol(606), pg_temp.c(9), v_nueva, MOT);
  perform pg_temp.cierto('T6 REZAGO-09: con la cuenta recién registrada se asigna', r like 'OK:%' and (substr(r, 4)::jsonb ->> 'moneda') = 'USD', r);
  perform pg_temp.igual('T6 REZAGO-09 se paga y se sella en la cuenta nueva', 'PAGADO:' || v_nueva || ':registro', pg_temp.pagar('oper', pg_temp.cuota(9, 1)));

  -- sin_cuenta: REZAGO-11 (J no tiene ninguna) y REZAGO-12 (K solo tiene una retirada).
  perform pg_temp.igual('T6 REZAGO-11 (sin_cuenta): el cliente no tiene ninguna cuenta', '0',
    (select count(*)::text from crm.cuentas_bancarias cb where cb.cliente_id = 'c9e00000-0000-4000-8000-000000000020'));
  r := pg_temp.registrar_cuenta('admin', 'c9e00000-0000-4000-8000-000000000020',
         '{"moneda": "USD", "banco": "Interbank", "tipo_cuenta": "ahorros", "numero_cuenta": "89851900000092", "cci": "00351900000000000092"}');
  perform pg_temp.cierto('T6 admin registra una cuenta en dólares para J', r like 'OK:%' and r <> 'OK:(null)', r);
  v_nueva := substr(r, 4)::uuid;
  r := pg_temp.asignar('admin', pg_temp.sol(607), pg_temp.c(11), v_nueva, MOT);
  perform pg_temp.cierto('T6 REZAGO-11: con la cuenta recién registrada se asigna', r like 'OK:%', r);
  perform pg_temp.igual('T6 REZAGO-11 se paga', 'PAGADO:' || v_nueva || ':registro', pg_temp.pagar('oper', pg_temp.cuota(11, 1)));
  perform pg_temp.igual('T6 REZAGO-12 (sin_cuenta): su única cuenta está retirada', pg_temp.k('no_vigente'),
    pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(12), pg_temp.cta(19), MOT));
  r := pg_temp.registrar_cuenta('oper', 'c9e00000-0000-4000-8000-000000000021',
         '{"moneda": "PEN", "banco": "BBVA", "tipo_cuenta": "ahorros", "numero_cuenta": "01151900000093", "cci": "01151900000000000093"}');
  perform pg_temp.cierto('T6 operaciones registra una cuenta en soles para K', r like 'OK:%' and r <> 'OK:(null)', r);
  v_nueva := substr(r, 4)::uuid;
  r := pg_temp.asignar('super', pg_temp.sol(608), pg_temp.c(12), v_nueva, MOT);
  perform pg_temp.cierto('T6 REZAGO-12: con la cuenta recién registrada se asigna', r like 'OK:%', r);
  return format('propiedad sobre %s ensayos (contratos sin vínculo × todas las cuentas): pasan exactamente los %s con cuenta vigente del mismo cliente y moneda en contrato abierto; se asigna la segunda de dos y la tercera de tres; la única de un una_cuenta (y la misma a dos contratos); en otra_moneda y sin_cuenta no hay nada válido hasta registrar la cuenta por su puerta%s',
    v_ensayos, v_pasan, case when v_desvinculados > 0 then format(' · (se retiraron en el tramo los %s vínculos de la carga de la otra migración)', v_desvinculados) else '' end);
end;
$f$;

-- ══ T7 · La constancia ══════════════════════════════════════════════════════════════════════
-- Una escritura directa sobre la constancia, como el dueño de la conexión que se diga. Siempre se deshace.
create function pg_temp.sobre_constancia(p_sesion text, p_sql text) returns text language plpgsql as $f$
declare
  r text; e text; m text; n bigint;
begin
  begin
    execute format('set local session authorization %I', p_sesion);
    execute p_sql;
    get diagnostics n = row_count;
    r := 'PASÓ (' || n || ' filas)';
    raise exception using errcode = 'P0001', message = 'ASIGNAR_DESHACER';
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    if m <> 'ASIGNAR_DESHACER' then
      r := 'ERR:' || e || ':' || m;
    end if;
  end;
  return r;
end;
$f$;
create function pg_temp.t7_constancia() returns text language plpgsql as $f$
declare
  v_tabla constant text := 'crm.contrato_cuenta_pago_asignaciones';
  K1 constant uuid := pg_temp.xc(1);
  A1 constant uuid := pg_temp.xcta(1);
  SOL constant uuid := pg_temp.sol(701);
  v_super constant text := current_setting('asignar.conectado');
  v_bitacora bigint;
  v_fila text;
  v_quien text;
  r text;
begin
  r := pg_temp.asignar('admin', SOL, K1, A1, pg_temp.k('motivo_bueno'));
  perform pg_temp.cierto('T7 preparación: una asignación', r like 'OK:%', r);
  select to_jsonb(x)::text into strict v_fila from crm.contrato_cuenta_pago_asignaciones x where x.solicitud_id = SOL;
  select count(*) into v_bitacora from public.audit_log;

  -- No se modifica ni se borra: ni postgres (el dueño) ni el superusuario.
  foreach v_quien in array array['postgres', v_super] loop
    perform pg_temp.igual(format('T7 UPDATE del motivo como %s', v_quien), pg_temp.k('no_modifica'),
      pg_temp.sobre_constancia(v_quien, $q$update crm.contrato_cuenta_pago_asignaciones set motivo = 'Motivo reescrito a mano'$q$));
    perform pg_temp.igual(format('T7 UPDATE de la cuenta como %s', v_quien), pg_temp.k('no_modifica'),
      pg_temp.sobre_constancia(v_quien, format($q$update crm.contrato_cuenta_pago_asignaciones set cuenta_bancaria_id = %L$q$, pg_temp.xcta(2))));
    perform pg_temp.igual(format('T7 UPDATE que no cambia nada como %s (el candado no mira qué cambia)', v_quien), pg_temp.k('no_modifica'),
      pg_temp.sobre_constancia(v_quien, $q$update crm.contrato_cuenta_pago_asignaciones set motivo = motivo$q$));
    perform pg_temp.igual(format('T7 DELETE como %s', v_quien), pg_temp.k('no_borra'),
      pg_temp.sobre_constancia(v_quien, $q$delete from crm.contrato_cuenta_pago_asignaciones$q$));
    perform pg_temp.igual(format('T7 TRUNCATE como %s', v_quien), pg_temp.k('no_modifica'),
      pg_temp.sobre_constancia(v_quien, $q$truncate crm.contrato_cuenta_pago_asignaciones$q$));
    perform pg_temp.igual(format('T7 TRUNCATE … CASCADE como %s', v_quien), pg_temp.k('no_modifica'),
      pg_temp.sobre_constancia(v_quien, $q$truncate table crm.contrato_cuenta_pago_asignaciones restart identity cascade$q$));
  end loop;
  perform pg_temp.igual('T7 tras los intentos la constancia está intacta', v_fila,
    (select to_jsonb(x)::text from crm.contrato_cuenta_pago_asignaciones x where x.solicitud_id = SOL));
  perform pg_temp.igual('T7 los intentos rechazados no escribieron en la bitácora', v_bitacora::text, (select count(*)::text from public.audit_log));

  -- RLS y permisos: nadie de la API toca la tabla.
  perform pg_temp.igual('T7 RLS activa y ninguna política (todo negado)', 'true/0',
    (select c.relrowsecurity::text from pg_class c where c.oid = v_tabla::regclass) || '/' ||
    (select count(*) from pg_policy p where p.polrelid = v_tabla::regclass));
  perform pg_temp.igual('T7 la ACL de la tabla es solo la de su dueño', '{postgres=arwdDxtm/postgres}|postgres',
    (select coalesce(c.relacl::text, '(acl por defecto)') || '|' || c.relowner::regrole::text from pg_class c where c.oid = v_tabla::regclass));
  foreach v_quien in array array['anon', 'authenticated', 'service_role', 'public', 'authenticator'] loop
    perform pg_temp.igual(format('T7 %s no tiene NINGÚN privilegio sobre la tabla ni sobre sus columnas', v_quien), 'false/false',
      has_table_privilege(v_quien, v_tabla, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')::text || '/' ||
      has_any_column_privilege(v_quien, v_tabla, 'SELECT, INSERT, UPDATE, REFERENCES')::text);
  end loop;
  perform pg_temp.igual('T7 ninguna columna tiene permisos propios', '0',
    (select count(*)::text from pg_attribute a where a.attrelid = v_tabla::regclass and a.attacl is not null));
  perform pg_temp.igual('T7 una administradora, por la API, no puede leer la constancia',
    'ERR:42501:permission denied for table contrato_cuenta_pago_asignaciones',
    pg_temp.como('admin', '{}', 'select count(*)::text from crm.contrato_cuenta_pago_asignaciones'));
  perform pg_temp.igual('T7 ni escribirla a mano',
    'ERR:42501:permission denied for table contrato_cuenta_pago_asignaciones',
    pg_temp.como('admin', '{}', format($q$insert into crm.contrato_cuenta_pago_asignaciones (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)
      values (gen_random_uuid(), %L, gen_random_uuid(), %L, gen_random_uuid(), 'Motivo metido a mano', gen_random_uuid()) returning id::text$q$, K1, A1)));

  -- Sin claves foráneas, ni entrantes ni salientes.
  perform pg_temp.igual('T7 ninguna clave foránea entra ni sale de la constancia', '0',
    (select count(*)::text from pg_constraint c where c.contype = 'f' and (c.conrelid = v_tabla::regclass or c.confrelid = v_tabla::regclass)));
  -- Forma de la tabla.
  perform pg_temp.igual('T7 columnas: nombre, tipo, obligatoria y valor por defecto',
    'id uuid NOT NULL gen_random_uuid() · solicitud_id uuid NOT NULL - · contrato_id uuid NOT NULL - · cliente_id uuid NOT NULL - · cuenta_bancaria_id uuid NOT NULL - · vinculo_id uuid NOT NULL - · motivo text NOT NULL - · asignado_por uuid NOT NULL - · asignado_en timestamp with time zone NOT NULL now()',
    (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL ' else ' NULL ' end ||
                       coalesce(pg_get_expr(d.adbin, d.adrelid), '-'), ' · ' order by a.attnum)
     from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = v_tabla::regclass and a.attnum > 0 and not a.attisdropped));
  perform pg_temp.igual('T7 restricciones: clave, solicitud única y motivo válido', 'contrato_cuenta_pago_asignaciones_motivo_valido:c,contrato_cuenta_pago_asignaciones_pkey:p,contrato_cuenta_pago_asignaciones_solicitud_uq:u',
    (select string_agg(c.conname || ':' || c.contype::text, ',' order by c.conname) from pg_constraint c where c.conrelid = v_tabla::regclass));
  perform pg_temp.igual('T7 índices: solo la clave primaria y el único de la solicitud (la tabla no crea índices propios)', 'contrato_cuenta_pago_asignaciones_pkey,contrato_cuenta_pago_asignaciones_solicitud_uq',
    (select string_agg(c.relname, ',' order by c.relname) from pg_index i join pg_class c on c.oid = i.indexrelid where i.indrelid = v_tabla::regclass));
  -- Los cuatro disparadores, enteros y habilitados.
  perform pg_temp.igual('T7 disparadores (definición|habilitado)',
       'CREATE TRIGGER trg_audit_contrato_cuenta_pago_asignaciones AFTER INSERT OR DELETE OR UPDATE ON crm.contrato_cuenta_pago_asignaciones FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()|O'
    || ' · CREATE TRIGGER trg_contrato_cuenta_pago_asignaciones_00_inmutable BEFORE UPDATE ON crm.contrato_cuenta_pago_asignaciones FOR EACH ROW EXECUTE FUNCTION private.trg_contrato_cuenta_pago_asignaciones_inmutable()|O'
    || ' · CREATE TRIGGER trg_contrato_cuenta_pago_asignaciones_00_no_borrar BEFORE DELETE ON crm.contrato_cuenta_pago_asignaciones FOR EACH ROW EXECUTE FUNCTION private.trg_registro_cuenta_pago_no_borrar()|O'
    || ' · CREATE TRIGGER trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar BEFORE TRUNCATE ON crm.contrato_cuenta_pago_asignaciones FOR EACH STATEMENT EXECUTE FUNCTION private.trg_contrato_cuenta_pago_asignaciones_inmutable()|O',
    (select string_agg(pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text, ' · ' order by t.tgname)
     from pg_trigger t where t.tgrelid = v_tabla::regclass and not t.tgisinternal));
  perform pg_temp.igual('T7 el vigía de bitácora (private.tablas_sin_rastro) NO señala la tabla nueva', '0',
    (select count(*)::text from private.tablas_sin_rastro() x where x.tabla = v_tabla));
  -- Comentarios.
  perform pg_temp.cierto('T7 la tabla tiene comentario', obj_description(v_tabla::regclass, 'pg_class') is not null);
  perform pg_temp.igual('T7 las nueve columnas tienen comentario', '9/9',
    (select count(*) || '/' || count(col_description(a.attrelid, a.attnum))
     from pg_attribute a where a.attrelid = v_tabla::regclass and a.attnum > 0 and not a.attisdropped));

  -- La tabla se defiende sola de una escritura directa del dueño (por si alguien se salta el núcleo).
  perform pg_temp.igual('T7 una solicitud repetida no entra (única)', 'ERR:23505:duplicate key value violates unique constraint "contrato_cuenta_pago_asignaciones_solicitud_uq"',
    pg_temp.sobre_constancia('postgres', format($q$insert into crm.contrato_cuenta_pago_asignaciones (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)
      values (%L, gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'Motivo bien escrito', gen_random_uuid())$q$, SOL)));
  foreach v_quien in array array[' con borde', 'abcd', repeat('x', 501), chr(160) || 'con borde duro', E'   \t  '] loop
    r := pg_temp.sobre_constancia('postgres', format($q$insert into crm.contrato_cuenta_pago_asignaciones (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)
      values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), %L, gen_random_uuid())$q$, v_quien));
    perform pg_temp.cierto(format('T7 un motivo inválido no entra ni escrito a mano («%s»)', left(v_quien, 20)),
      r like 'ERR:23514:%contrato_cuenta_pago_asignaciones_motivo_valido%', r);
  end loop;
  r := pg_temp.sobre_constancia('postgres', $q$insert into crm.contrato_cuenta_pago_asignaciones (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)
      values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'Motivo bien escrito', null)$q$);
  perform pg_temp.cierto('T7 una constancia sin autor no entra', r like 'ERR:23502:%', r);

  return 'UPDATE, DELETE y TRUNCATE fallan como postgres y como superusuario; RLS sin políticas; anon, authenticated, service_role, public y authenticator sin ningún privilegio; sin claves foráneas; cuatro disparadores habilitados; sin índices propios; el vigía de bitácora no la señala; comentario en la tabla y en las nueve columnas; la solicitud es única y el motivo inválido no entra ni a mano';
end;
$f$;

-- ══ T8 · Convivencia con F3 (cambiar cuenta de pago) y F4 (retirar cuenta) ══════════════════
create function pg_temp.t8_convivencia() returns text language plpgsql as $f$
declare
  K7 constant uuid := pg_temp.c(7);                       -- REZAGO-07, cliente F, dos cuentas en soles
  CLI_F constant uuid := 'c9e00000-0000-4000-8000-000000000016';
  C10 constant uuid := pg_temp.cta(10);
  C11 constant uuid := pg_temp.cta(11);
  R1 constant text := 'c9e00000-0000-4000-8000-000000000016/a519f000-0000-4000-8000-000000000001.pdf';
  R2 constant text := 'c9e00000-0000-4000-8000-000000000016/a519f000-0000-4000-8000-000000000002.pdf';
  RM constant text := 'c9e00000-0000-4000-8000-000000000023/a519f000-0000-4000-8000-000000000003.pdf';
  MOT constant text := pg_temp.k('motivo_bueno');
  v_constancia text;
  v_vinculo uuid;
  r text;
begin
  -- F3 ANTES de asignar: el contrato no tiene cuenta y F3 lo rechaza.
  perform pg_temp.igual('T8 F3 antes de asignar: «no tiene cuenta de pago»', 'ERR:22023:El contrato REZAGO-07 no tiene cuenta de pago; requiere conciliación',
    pg_temp.cambiar('admin', pg_temp.sol(801), CLI_F, C11, array[K7], MOT, R1));
  -- F4 ANTES de asignar: la cuenta no cobra ningún contrato y se puede retirar; retirada, ya no se asigna.
  begin
    r := pg_temp.retirar('admin', pg_temp.sol(802), CLI_F, C10, MOT);
    perform pg_temp.cierto('T8 F4 antes de asignar: la cuenta se retira (testigo de que el rechazo de después es por la asignación)',
      r like 'OK:%' and (substr(r, 4)::jsonb ->> 'ya_aplicada') = 'false', r);
    perform pg_temp.igual('T8 una cuenta retirada por F4 ya no se puede asignar', pg_temp.k('no_vigente'),
      pg_temp.asignar('admin', gen_random_uuid(), K7, C10, MOT));
    raise exception using errcode = 'P0001', message = 'ASIGNAR_DESHACER';
  exception when others then
    if sqlerrm <> 'ASIGNAR_DESHACER' then raise; end if;
  end;

  r := pg_temp.asignar('admin', pg_temp.sol(803), K7, C10, MOT);
  perform pg_temp.cierto('T8 se asigna la primera cuenta a REZAGO-07', r like 'OK:%', r);
  select to_jsonb(x)::text, x.vinculo_id into strict v_constancia, v_vinculo
  from crm.contrato_cuenta_pago_asignaciones x where x.solicitud_id = pg_temp.sol(803);

  -- F4 DESPUÉS de asignar: la cuenta ya cobra un contrato abierto y no se retira.
  perform pg_temp.igual('T8 F4 después de asignar: el retiro de la cuenta recién asignada se rechaza',
    'ERR:22023:La cuenta todavía cobra el contrato REZAGO-07. Primero cambia su cuenta de pago',
    pg_temp.retirar('admin', pg_temp.sol(804), CLI_F, C10, MOT));
  perform pg_temp.igual('T8 la cuenta sigue vigente tras el retiro rechazado', 'true',
    (select cb.activa::text from crm.cuentas_bancarias cb where cb.id = C10));

  -- F3 DESPUÉS de asignar: el contrato ya es uno CON cuenta.
  perform pg_temp.igual('T8 F3 después de asignar, hacia la misma cuenta: «ya cobra en esa cuenta» (ve el vínculo)',
    'ERR:22023:El contrato REZAGO-07 ya cobra en esa cuenta', pg_temp.cambiar('admin', pg_temp.sol(805), CLI_F, C10, array[K7], MOT, R1));
  r := pg_temp.cambiar('admin', pg_temp.sol(801), CLI_F, C11, array[K7], MOT, R1);
  perform pg_temp.cierto('T8 F3 después de asignar, hacia la otra cuenta: el cambio se completa (la misma llamada que antes se rechazaba)',
    r like 'OK:%' and (substr(r, 4)::jsonb ->> 'ya_aplicada') = 'false' and (substr(r, 4)::jsonb ->> 'contratos') = '1', r);
  perform pg_temp.igual('T8 tras el cambio, el vínculo es la MISMA fila, apunta a la cuenta nueva y conserva a quien asignó',
    v_vinculo || '|' || C11 || '|c9e00000-0000-4000-8000-000000000001',
    (select l.id || '|' || l.cuenta_bancaria_id || '|' || l.creado_por from crm.contrato_cuentas_pago l where l.contrato_id = K7));
  perform pg_temp.igual('T8 el historial de F3 guarda como cuenta ANTERIOR la que se asignó', C10 || '→' || C11,
    (select x.cuenta_anterior_id || '→' || x.cuenta_nueva_id from crm.contrato_cuenta_pago_cambios x where x.contrato_id = K7));
  perform pg_temp.igual('T8 la constancia de la asignación no cambió con el cambio de F3 (sigue diciendo la cuenta original)', v_constancia,
    (select to_jsonb(x)::text from crm.contrato_cuenta_pago_asignaciones x where x.solicitud_id = pg_temp.sol(803)));
  perform pg_temp.igual('T8 tras el cambio, asignar otra vez se rechaza: sigue teniendo cuenta', format(pg_temp.k('ya_tiene'), 'REZAGO-07'),
    pg_temp.asignar('admin', gen_random_uuid(), K7, C10, MOT));
  perform pg_temp.igual('T8 la solicitud de la asignación, repetida tras el cambio, sigue siendo ya_aplicada y describe la cuenta que SE ASIGNÓ (la de la constancia)',
    'OK:' || jsonb_build_object('solicitud_id', pg_temp.sol(803), 'ya_aplicada', true, 'numero_contrato', 'REZAGO-07', 'banco', 'BCP', 'moneda', 'PEN', 'ultimos', '0010')::text,
    pg_temp.asignar('admin', pg_temp.sol(803), K7, C10, MOT));
  -- Y entonces F4 sí deja retirar la cuenta que se asignó primero: ya no cobra ningún contrato.
  r := pg_temp.retirar('admin', pg_temp.sol(806), CLI_F, C10, MOT);
  perform pg_temp.cierto('T8 F4 tras el cambio: la cuenta que se asignó primero ya se puede retirar', r like 'OK:%', r);
  perform pg_temp.igual('T8 el pago posterior al cambio se sella en la cuenta nueva', 'PAGADO:' || C11 || ':registro', pg_temp.pagar('oper', pg_temp.cuota(7, 1)));

  -- Lo que dice el mensaje «para cambiarla usa «Cambiar cuenta de pago»»: F3 corrige un vínculo incoherente.
  r := pg_temp.cambiar('admin', pg_temp.sol(807), 'c9e00000-0000-4000-8000-000000000023', pg_temp.cta(20), array[pg_temp.c(14)], MOT, RM);
  perform pg_temp.cierto('T8 F3 sí corrige el vínculo incoherente de REZAGO-14 (el camino que indica el mensaje de «ya tiene cuenta»)', r like 'OK:%', r);
  return format('con storage.objects %s: F3 pasa de «no tiene cuenta de pago» a «ya cobra en esa cuenta» y completa un cambio REAL hacia la otra cuenta (misma fila de vínculo, historial con la asignada como anterior, constancia intacta); F4 retira la cuenta antes de asignarla, se niega mientras cobra el contrato y vuelve a dejar tras el cambio; F3 corrige un vínculo incoherente',
    case current_setting('asignar.storage') when 'doble' then 'DOBLE (tabla mínima creada en esta transacción: la imagen no trae Storage)' else 'real' end);
end;
$f$;

-- ══ T10 · Con la otra migración (20261001233019) ════════════════════════════════════════════
create function pg_temp.diagnostico(p_contrato uuid) returns text language plpgsql as $f$
declare
  v text;
begin
  execute 'select d.caso || ''|'' || coalesce(d.mensaje, ''(sin mensaje)'') from private.cuenta_pago_diagnostico(array[$1]) d' into v using p_contrato;
  return coalesce(v, '(sin fila)');
end;
$f$;
create function pg_temp.t10_con_la_otra() returns text language plpgsql as $f$
declare
  MOT constant text := pg_temp.k('motivo_bueno');
  K7 constant uuid := pg_temp.c(7);
  K9 constant uuid := pg_temp.c(9);
  K11 constant uuid := pg_temp.c(11);
  K1X constant uuid := pg_temp.xc(1);
  v_carga integer;
  v_ok_antes integer;
  v_ok_despues integer;
  v_nueva uuid;
  v_todos uuid[];
  v_cerrado text;
  n integer;
  r text;
begin
  if not pg_temp.otra_aplicada() then
    return 'NO APLICA: la otra migración (20261001233019) no está aplicada en el banco; este tramo solo corre con las dos';
  end if;
  select array_agg(ct.id order by ct.numero_contrato) into v_todos from public.contratos ct;
  execute 'select count(*) from private.cuenta_pago_diagnostico() d where d.caso = ''ok''' into v_ok_antes;

  -- Los contratos que vinculó la carga de la otra migración ya tienen cuenta: no se asignan.
  select count(*) into v_carga
  from crm.contrato_cuentas_pago x join private.backfill_cuentas_p0xx b on b.fila_id = x.id
  where b.tipo = 'vinculo' and b.marca_actor = pg_temp.k('marca_carga') and b.revertida_en is null;
  if v_carga = 4 then
    foreach n in array array[3, 4, 5, 6] loop
      perform pg_temp.igual(format('T10 REZAGO-%s lo vinculó la carga (creado_por nulo) y el diagnóstico lo da por ok', lpad(n::text, 2, '0')),
        'ok|(sin mensaje)/(null)', pg_temp.diagnostico(pg_temp.c(n)) || '/' || split_part(pg_temp.vinculo(pg_temp.c(n)), '|', 2));
      perform pg_temp.igual(format('T10 REZAGO-%s: asignar lo rechaza, ya tiene cuenta', lpad(n::text, 2, '0')),
        format(pg_temp.k('ya_tiene'), 'REZAGO-' || lpad(n::text, 2, '0')),
        pg_temp.asignar('admin', gen_random_uuid(), pg_temp.c(n), (select l.cuenta_bancaria_id from crm.contrato_cuentas_pago l where l.contrato_id = pg_temp.c(n)), MOT));
    end loop;
  end if;

  -- varias_cuentas (REZAGO-07): antes, el diagnóstico, la puerta de motivos y el bloqueo dicen por qué; después, ok.
  perform pg_temp.igual('T10 REZAGO-07 antes: diagnóstico',
    'varias_cuentas|Contrato REZAGO-07 sin cuenta de pago: el cliente tiene 2 cuentas en soles; confirma con él en cuál cobra este contrato.', pg_temp.diagnostico(K7));
  perform pg_temp.igual('T10 REZAGO-07 antes: la puerta de motivos (operaciones) lo devuelve, y no devuelve el que está ok', 'OK:REZAGO-07=varias_cuentas',
    pg_temp.motivos('oper', array[K7, pg_temp.c(1)]));
  perform pg_temp.igual('T10 REZAGO-07 antes: al intentar pagar, el bloqueo le dice el motivo al gestor',
    'ERR:23514:Contrato REZAGO-07 sin cuenta de pago: el cliente tiene 2 cuentas en soles; confirma con él en cuál cobra este contrato.',
    pg_temp.pagar('oper', pg_temp.cuota(7, 1)));
  r := pg_temp.asignar('admin', pg_temp.sol(1001), K7, pg_temp.cta(11), MOT);
  perform pg_temp.cierto('T10 REZAGO-07: se asigna', r like 'OK:%', r);
  perform pg_temp.igual('T10 REZAGO-07 después: el diagnóstico da ok y sin mensaje', 'ok|(sin mensaje)', pg_temp.diagnostico(K7));
  perform pg_temp.igual('T10 REZAGO-07 después: la puerta de motivos ya no lo trae', 'OK:(ninguno)', pg_temp.motivos('oper', array[K7, pg_temp.c(1)]));
  perform pg_temp.igual('T10 REZAGO-07 después: se paga', 'PAGADO:' || pg_temp.cta(11) || ':registro', pg_temp.pagar('oper', pg_temp.cuota(7, 1)));

  -- Un contrato de la siembra extra (tres cuentas en soles).
  perform pg_temp.igual('T10 ASIGNAR-01 antes: diagnóstico',
    'varias_cuentas|Contrato ASIGNAR-01 sin cuenta de pago: el cliente tiene 3 cuentas en soles; confirma con él en cuál cobra este contrato.', pg_temp.diagnostico(K1X));
  r := pg_temp.asignar('super', pg_temp.sol(1002), K1X, pg_temp.xcta(2), MOT);
  perform pg_temp.cierto('T10 ASIGNAR-01: se asigna', r like 'OK:%', r);
  perform pg_temp.igual('T10 ASIGNAR-01 después: ok', 'ok|(sin mensaje)', pg_temp.diagnostico(K1X));

  -- otra_moneda (REZAGO-09): al registrar la cuenta pasa a una_cuenta y, al asignarla, a ok.
  perform pg_temp.igual('T10 REZAGO-09 antes: diagnóstico',
    'otra_moneda|Contrato REZAGO-09 sin cuenta de pago: el contrato es en dólares y el cliente solo tiene cuenta en soles; pídele una en dólares.', pg_temp.diagnostico(K9));
  r := pg_temp.registrar_cuenta('oper', 'c9e00000-0000-4000-8000-000000000018',
         '{"moneda": "USD", "banco": "BCP", "tipo_cuenta": "ahorros", "numero_cuenta": "19151900000094", "cci": "00251900000000000094"}');
  perform pg_temp.cierto('T10 REZAGO-09: operaciones registra la cuenta en dólares', r like 'OK:%' and r <> 'OK:(null)', r);
  v_nueva := substr(r, 4)::uuid;
  perform pg_temp.igual('T10 REZAGO-09 con la cuenta registrada: el diagnóstico pasa a una_cuenta',
    'una_cuenta|Contrato REZAGO-09 sin cuenta de pago: el cliente ya tiene una cuenta en dólares; falta vincularla a este contrato.', pg_temp.diagnostico(K9));
  r := pg_temp.asignar('admin', pg_temp.sol(1003), K9, v_nueva, MOT);
  perform pg_temp.cierto('T10 REZAGO-09: se asigna la cuenta registrada (sin esperar a la carga)', r like 'OK:%', r);
  perform pg_temp.igual('T10 REZAGO-09 después: ok', 'ok|(sin mensaje)', pg_temp.diagnostico(K9));

  -- sin_cuenta (REZAGO-11).
  perform pg_temp.igual('T10 REZAGO-11 antes: diagnóstico',
    'sin_cuenta|Contrato REZAGO-11 sin cuenta de pago: el cliente no tiene ninguna cuenta bancaria vigente; pídele una en dólares.', pg_temp.diagnostico(K11));
  r := pg_temp.registrar_cuenta('admin', 'c9e00000-0000-4000-8000-000000000020',
         '{"moneda": "USD", "banco": "Interbank", "tipo_cuenta": "ahorros", "numero_cuenta": "89851900000095", "cci": "00351900000000000095"}');
  perform pg_temp.cierto('T10 REZAGO-11: admin registra la cuenta', r like 'OK:%' and r <> 'OK:(null)', r);
  r := pg_temp.asignar('admin', pg_temp.sol(1004), K11, substr(r, 4)::uuid, MOT);
  perform pg_temp.cierto('T10 REZAGO-11: se asigna', r like 'OK:%', r);
  perform pg_temp.igual('T10 REZAGO-11 después: ok', 'ok|(sin mensaje)', pg_temp.diagnostico(K11));

  -- En conjunto: los ok suben exactamente en los cuatro asignados; la puerta de motivos no trae ninguno de ellos.
  execute 'select count(*) from private.cuenta_pago_diagnostico() d where d.caso = ''ok''' into v_ok_despues;
  perform pg_temp.igual('T10 los contratos ok suben exactamente en los cuatro asignados', (v_ok_antes + 4)::text, v_ok_despues::text);
  r := pg_temp.motivos('admin', v_todos);
  perform pg_temp.cierto('T10 la puerta de motivos, pedida con TODOS los contratos, no trae ninguno de los cuatro asignados',
    r like 'OK:%' and r !~ '(REZAGO-07|ASIGNAR-01|REZAGO-09|REZAGO-11)=', r);
  -- El diagnóstico y el bloqueo dicen lo mismo de todos los contratos, también de los asignados.
  execute $q$select count(*) from private.cuenta_pago_diagnostico() d
            where (d.caso = 'ok') is distinct from exists (
              select 1 from crm.contrato_cuentas_pago cp
              join public.contratos ct on ct.id = cp.contrato_id
              join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
              where cp.contrato_id = d.contrato_id and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda)$q$ into n;
  perform pg_temp.igual('T10 en ningún contrato el diagnóstico y la condición del bloqueo dicen cosas distintas', '0', n::text);
  -- MEDIDO, sin exigir nada (el diagnóstico es de la otra migración): un contrato CERRADO sin cuenta de pago.
  -- El diagnóstico no mira el estado del contrato; «Asignar» solo admite contratos abiertos.
  v_cerrado := format('contrato cerrado ASIGNAR-03 (renovado): el diagnóstico dice «%s» y asignar responde «%s»',
    pg_temp.diagnostico(pg_temp.xc(3)), pg_temp.asignar('admin', gen_random_uuid(), pg_temp.xc(3), pg_temp.xcta(1), MOT));
  return format('con las dos migraciones (la carga de la otra tiene %s vínculos vivos): antes de asignar el diagnóstico da el caso sin vínculo, la puerta de motivos lo devuelve y el bloqueo se lo dice al gestor; después da ok, la puerta ya no lo trae y se paga; los vinculados por la carga se rechazan con «ya tiene cuenta de pago»; los ok suben de %s a %s · MEDIDO %s',
    v_carga, v_ok_antes, v_ok_despues, v_cerrado);
end;
$f$;

-- ══ TC · Catálogo de las tres funciones (lo que mira el postflight, comprobado aparte) ═══════
create function pg_temp.tc_catalogo() returns text language plpgsql as $f$
declare
  f record;
  v text;
begin
  for f in
    select * from (values
      (pg_temp.k('candado'), 'definer=true lenguaje=plpgsql volatilidad=v config={"search_path=\"\""} dueño=postgres argumentos= retorna=trigger ejecutan=postgres',
       pg_temp.k('md5_candado'), 'public=false anon=false authenticated=false service_role=false'),
      (pg_temp.k('nucleo'),  'definer=true lenguaje=plpgsql volatilidad=v config={"search_path=\"\""} dueño=postgres argumentos=p_solicitud_id uuid, p_contrato_id uuid, p_cuenta_id uuid, p_motivo text retorna=jsonb ejecutan=authenticated,postgres',
       pg_temp.k('md5_nucleo'), 'public=false anon=false authenticated=true service_role=false'),
      (pg_temp.k('puerta'),  'definer=false lenguaje=sql volatilidad=v config={"search_path=\"\""} dueño=postgres argumentos=p_solicitud_id uuid, p_contrato_id uuid, p_cuenta_id uuid, p_motivo text retorna=jsonb ejecutan=authenticated,postgres',
       pg_temp.k('md5_puerta'), 'public=false anon=false authenticated=true service_role=false')
    ) as t(firma, ficha, huella, permisos)
  loop
    select format('definer=%s lenguaje=%s volatilidad=%s config=%s dueño=%s argumentos=%s retorna=%s ejecutan=%s',
             p.prosecdef::text, l.lanname, p.provolatile::text, coalesce(p.proconfig::text, '(sin config)'), p.proowner::regrole::text,
             pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid),
             (select coalesce(string_agg(case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end, ','
                                         order by case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end), '(nadie)')
              from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x where x.privilege_type = 'EXECUTE'))
      into v
    from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = to_regprocedure(f.firma);
    perform pg_temp.igual(format('TC %s: DEFINER/INVOKER, lenguaje, volatilidad, search_path vacío (y nada más), dueño, firma, retorno y quién ejecuta', f.firma), f.ficha, v);
    perform pg_temp.igual(format('TC %s: huella del cuerpo (md5 de prosrc)', f.firma), f.huella,
      (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(f.firma)));
    perform pg_temp.cierto(format('TC %s: la ACL está escrita (no es la de por defecto, que deja ejecutar a PUBLIC)', f.firma),
      (select p.proacl is not null from pg_proc p where p.oid = to_regprocedure(f.firma)));
    perform pg_temp.igual(format('TC %s: EXECUTE efectivo', f.firma), f.permisos,
      format('public=%s anon=%s authenticated=%s service_role=%s',
        has_function_privilege('public', f.firma, 'EXECUTE')::text, has_function_privilege('anon', f.firma, 'EXECUTE')::text,
        has_function_privilege('authenticated', f.firma, 'EXECUTE')::text, has_function_privilege('service_role', f.firma, 'EXECUTE')::text));
    perform pg_temp.cierto(format('TC %s: tiene comentario', f.firma), obj_description(to_regprocedure(f.firma), 'pg_proc') is not null);
  end loop;
  perform pg_temp.igual('TC la puerta INVOKER necesita que authenticated entre a crm y a private', 'true/true',
    has_schema_privilege('authenticated', 'crm', 'USAGE')::text || '/' || has_schema_privilege('authenticated', 'private', 'USAGE')::text);
  perform pg_temp.cierto('TC el dueño de las funciones (postgres) se salta la RLS: el núcleo lee contratos, cuentas y vínculos',
    (select r.rolbypassrls from pg_roles r where r.rolname = 'postgres'));
  -- Las piezas ajenas de las que depende, por identidad (las del preflight).
  perform pg_temp.igual('TC la compuerta y los dos candados ajenos siguen siendo los que la migración comprobó',
    '810dce30e37d1da9d913ef48ab6a4aa1/7e946a5af78a827c18ee5b218896f24c/e95919db53c44ff1fe6632c346f27a06',
    (select md5(p.prosrc) from pg_proc p where p.oid = 'private.admin_banca_vigente(uuid)'::regprocedure) || '/' ||
    (select md5(p.prosrc) from pg_proc p where p.oid = 'private.trg_contrato_cuenta_pago_coherente()'::regprocedure) || '/' ||
    (select md5(p.prosrc) from pg_proc p where p.oid = 'private.trg_registro_cuenta_pago_no_borrar()'::regprocedure));
  perform pg_temp.igual('TC los tres disparadores del vínculo siguen habilitados (coherencia, inmutable, bitácora)',
    'trg_audit_contrato_cuentas_pago|O · trg_contrato_cuenta_pago_00_inmutable|O · trg_contrato_cuenta_pago_coherente|O',
    (select string_agg(t.tgname || '|' || t.tgenabled::text, ' · ' order by t.tgname)
     from pg_trigger t where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass and not t.tgisinternal));
  perform pg_temp.igual('TC el vínculo sigue siendo único por contrato', '1',
    (select count(*)::text from pg_index i
     where i.indrelid = 'crm.contrato_cuentas_pago'::regclass and i.indisunique and i.indpred is null and i.indnatts = 1
       and i.indkey[0] = (select a.attnum from pg_attribute a where a.attrelid = 'crm.contrato_cuentas_pago'::regclass and a.attname = 'contrato_id')));
  return 'candado, núcleo y puerta con su huella, DEFINER/DEFINER/INVOKER, search_path vacío, dueño postgres, ACL exacta (núcleo y puerta: solo authenticated; candado: nadie) y comentario; las piezas ajenas, intactas';
end;
$f$;

-- ══ Ejecución ═══════════════════════════════════════════════════════════════════════════════
select 'T0 · ' || pg_temp.t0_precondiciones();
select pg_temp.correr('T1',  'pg_temp.t1_quien');
select pg_temp.correr('T2',  'pg_temp.t2_efecto');
select pg_temp.correr('T3',  'pg_temp.t3_despues_se_paga');
select pg_temp.correr('T4',  'pg_temp.t4_rechazos');
select pg_temp.correr('T5',  'pg_temp.t5_idempotencia');
select pg_temp.correr('T6',  'pg_temp.t6_elegir');
select pg_temp.correr('T7',  'pg_temp.t7_constancia');
select pg_temp.correr('T8',  'pg_temp.t8_convivencia');
select pg_temp.correr('T10', 'pg_temp.t10_con_la_otra');
select pg_temp.correr('TC',  'pg_temp.tc_catalogo');
-- Veredicto. Con algún tramo en FAIL la última sentencia falla a propósito (psql sale con error).
select case when count(*) filter (where r.estado = 'FAIL') = 0
            then format('ASIGNAR OK · %s tramos · %s comprobaciones · nada escrito', count(*), (select s.last_value - 1 from asignar_hechas s))
            else format('ASIGNAR FALLO · %s de %s tramos: %s · %s comprobaciones hechas', count(*) filter (where r.estado = 'FAIL'), count(*),
                        string_agg(r.tramo, ' ' order by r.orden) filter (where r.estado = 'FAIL'), (select s.last_value - 1 from asignar_hechas s))
       end as veredicto
from resultados r;
do $veredicto$
begin
  if exists (select 1 from resultados r where r.estado = 'FAIL') then
    raise exception 'ASIGNAR FALLO: %', (select string_agg(r.tramo || ' → ' || r.detalle, ' ;; ' order by r.orden) from resultados r where r.estado = 'FAIL');
  end if;
end;
$veredicto$;
rollback;
