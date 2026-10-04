-- B7 · Bases cargadas, esquema (20261004160034), en el banco (UNA transacción, impersonación con claims + set local role,
-- ROLLBACK al final). Falla el proceso si hay un FAIL. Corre sobre un banco LOCAL con B7 aplicada y los actores de seed:demo
-- (el banco del gate). Siembra leads b7000000-…, tres bases y sus recibos, que se deshacen con el ROLLBACK.
-- Qué prueba:
--   A catálogo (RLS, ACL, sello, CHECK, enfriamiento, censo);
--   B la API (anon, analista, Supervisión, Gerencia, Coordinación, service_role) NO lee ni escribe las tablas nuevas;
--   C el segundo candado: con un SELECT concedido DENTRO de la transacción, Supervisión ve sus bases y las de su subárbol,
--     Gerencia todas, el analista y Coordinación nada (filas y recibos siguen a su base);
--   D los recibos son inmutables (UPDATE, DELETE y TRUNCATE → P0409, también para el dueño) y únicos por actor e id;
--   E capital NULL solo con origen base_cargada Y etapa descartado (cualquier otro origen o etapa → 23514) y un capital no se
--     vacía; el contacto sin capital solo puede NACER descartado y, sin B8, queda sin descartado_en (E17–E19; con B8 nace con la
--     fecha y el alta ve «enfriamiento»: el pendiente lo resuelve 20261004184501). Sin B8 el alta lo
--     ve «libre»); con fecha de descarte, la política base_cargada (30 días) da «enfriamiento»;
--   V ninguna vía real saca del descarte a un lead sin capital (reactivar_lead_base, reabrir_lead_fn, tomar_lead_libre,
--     rescatar_descartes → 23514 del CHECK) y con el capital puesto pasan;
--   F/G motivo y origen base_cargada solo con la válvula crm.op_bases_carga (ni la API, ni sin usuario, ni el importador,
--     ni con crm.op_privilegiada); un dormido no se «despierta» cambiándole el motivo (r1); la puerta de alta no lo admite;
--   H un lead no está en dos bases vivas; I coherencia del reparto; J restricciones de la base; K auditoría; L regresión.
-- Mutantes: `node supabase/scripts/base-gestion/b7-mutantes.mjs --puerto <puerto del banco local>` inyecta cada uno en la
-- línea @@MUTANTE@@ y exige que esta suite FALLE en su caso.
\set ON_ERROR_STOP on
-- Solo banco LOCAL (como b6b-vetados.sql y b6c-nota-veto.sql): el secreto JWT de la base tiene que ser el valor de desarrollo
-- PÚBLICO del Supabase CLI (se compara su md5; un proyecto alojado tiene el suyo) y la conexión no va por SSL. La suite concede
-- SELECT de las tablas nuevas a authenticated dentro de su transacción (sección C) y siembra datos: nunca fuera del banco.
do $solo_banco_local$
begin
  if (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646'
      and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid())) is not true then
    raise exception 'b7-esquema: solo corre en un banco LOCAL de Docker (Supabase CLI); esta base no lo es';
  end if;
end $solo_banco_local$;
begin;
-- @@MUTANTE@@

-- ───────── Utilidades (todo en pg_temp: se va con el ROLLBACK) ─────────
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
create function pg_temp.sesion(p uuid, p_rol text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), true),
         set_config('request.jwt.claims', case when p is null and p_rol = 'authenticated' then ''
                                               else json_build_object('sub', p, 'role', p_rol)::text end, true);
$$;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
-- prueba: ejecuta p_sql (como p_rol con el usuario p_uid; sin rol = postgres sin usuario) y lo DESHACE (subtransacción).
-- Anota «paso» o «<sqlstate> <mensaje>». p_valvula enciende crm.op_bases_carga (la válvula de B8); p_priv, crm.op_privilegiada.
create function pg_temp.prueba(p_caso text, p_esperado text, p_sql text, p_rol text default null, p_uid uuid default null,
                               p_valvula boolean default false, p_priv boolean default false) returns void language plpgsql as $$
declare v text;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol = 'service_role' then 'service_role' else 'authenticated' end);
    if p_valvula then perform set_config('crm.op_bases_carga', 'on', true); end if;
    if p_priv then perform set_config('crm.op_privilegiada', 'on', true); end if;
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql;
    v := 'paso';
    raise exception using errcode = 'P0001', message = 'B7_DESHACER';
  exception when others then
    if v is null then v := sqlstate || ' ' || sqlerrm; end if;
  end;
  perform pg_temp.caso(p_caso, p_esperado, v);
end $$;
-- valor: devuelve el primer valor de p_sql (como p_rol/p_uid) o «ERROR <sqlstate> <mensaje>»; deshace todo.
create function pg_temp.valor(p_sql text, p_rol text default null, p_uid uuid default null, p_valvula boolean default false)
returns text language plpgsql as $$
declare v text; v_ok boolean := false;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol = 'service_role' then 'service_role' else 'authenticated' end);
    if p_valvula then perform set_config('crm.op_bases_carga', 'on', true); end if;
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql into v;
    v_ok := true;
    raise exception using errcode = 'P0001', message = 'B7_DESHACER';
  exception when others then
    if not v_ok then v := 'ERROR ' || sqlstate || ' ' || sqlerrm; end if;
  end;
  return coalesce(v, '(nulo)');
end $$;
-- detalle: «<sqlstate>|<detail>» del error de p_sql (como p_rol/p_uid), o «paso»; deshace todo.
create function pg_temp.detalle(p_sql text, p_rol text default null, p_uid uuid default null) returns text language plpgsql as $$
declare v text; v_det text;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol = 'service_role' then 'service_role' else 'authenticated' end);
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql;
    v := 'paso';
    raise exception using errcode = 'P0001', message = 'B7_DESHACER';
  exception when others then
    if v is null then get stacked diagnostics v_det = pg_exception_detail; v := sqlstate || '|' || coalesce(nullif(v_det, ''), '(sin detail)'); end if;
  end;
  return v;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- ───────── Actores (seed:demo) y precondiciones ─────────
create temp table f as select
  (select id from auth.users where email = 'vend1.crm@demo.avancecorp.pe') v1,
  (select id from auth.users where email = 'vend2.crm@demo.avancecorp.pe') v2,
  (select id from auth.users where email = 'vend3.crm@demo.avancecorp.pe') v3,
  (select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe') s1,
  (select id from auth.users where email = 'sup2.crm@demo.avancecorp.pe') s2,
  (select id from auth.users where email = 'sup-anidado.crm@demo.avancecorp.pe') sa,
  (select id from auth.users where email = 'gerencia.crm@demo.avancecorp.pe') g,
  (select id from auth.users where email = 'coordinador.crm@demo.avancecorp.pe') co,
  'b7000000-0000-4000-8000-0000000000a1'::uuid la,   -- V1, oficina, capital 1000, nuevo (la API lo edita)
  'b7000000-0000-4000-8000-0000000000a2'::uuid lb,   -- bandeja S1, base_cargada SIN capital, NACE descartado (lo único posible)
  'b7000000-0000-4000-8000-0000000000a3'::uuid lc,   -- bandeja S1, base_cargada CON capital 5000, descartado
  'b7000000-0000-4000-8000-0000000000a4'::uuid ld,   -- V1, oficina, descartado no_responde
  'b7000000-0000-4000-8000-0000000000a5'::uuid le,   -- V3 (equipo S2), oficina, descartado no_responde
  'b7000000-0000-4000-8000-0000000000a6'::uuid lt,   -- bandeja S1, base_cargada SIN capital, descartado (para «tomar lead libre»)
  'b7000000-0000-4000-8000-0000000000a7'::uuid lq,   -- base_cargada de V1 descartado con episodio cerrado (para el rescate)
  'b7000000-0000-4000-8000-0000000000b1'::uuid b1,   -- base de S1 (archivo)
  'b7000000-0000-4000-8000-0000000000b2'::uuid b2,   -- base de S2 (crm), mismo nombre en otra bandeja
  'b7000000-0000-4000-8000-0000000000b3'::uuid b3,   -- base del supervisor anidado bajo S1
  '966710002'::text tel_lb,
  '966710006'::text tel_lt,
  '42501 El origen base_cargada solo lo pone la carga de bases'::text m_origen,
  '42501 El motivo base_cargada solo lo pone la carga de bases'::text m_motivo,
  '42501 El motivo base_cargada de un contacto dormido solo lo cambia la carga de bases'::text m_despertar,
  '23514 El capital del lead no se puede vaciar'::text m_vaciar,
  '23514 new row for relation "leads" violates check constraint "leads_monto_estimado_valido"'::text m_check_monto,
  'P0409 Los recibos de las bases cargadas no se modifican ni se borran'::text m_recibo;
grant select on f to anon, authenticated, service_role;
do $$ begin
  if (select v1 is null or v2 is null or v3 is null or s1 is null or s2 is null or sa is null or g is null or co is null from f) then
    raise exception 'b7-esquema: faltan actores de seed:demo en este banco (correr el gate o seed:demo antes)';
  end if;
  if to_regclass('crm.bases_carga') is null or to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is null then
    raise exception 'b7-esquema: B7 (20261004160034) no está aplicada en este banco';
  end if;
  if exists (select 1 from crm.leads where id::text like 'b7000000-%') or exists (select 1 from crm.bases_carga) then
    raise exception 'b7-esquema: ya hay leads b7000000-… o bases en el banco';
  end if;
end $$;

-- ───────── Siembra (postgres sin usuario) ─────────
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'oficina', 'nuevo', x.v, 1000, 'PEN', x.v, true
  from f, lateral (values (f.la, 'B7 API', '966710001', f.v1), (f.ld, 'B7 DESCARTADO V1', '966710004', f.v1),
                          (f.le, 'B7 DESCARTADO V3', '966710005', f.v3)) x(id, nombre, tel, v);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id in ((select ld from f), (select le from f));
-- El contacto de base nace DESCARTADO en la bandeja del supervisor (con el CHECK de la etapa, sin capital no puede nacer
-- 'nuevo'), con las dos válvulas: crm.op_bases_carga (origen y motivo base_cargada) y crm.op_privilegiada (leads_before_insert
-- impide nacer en estado terminal sin ella). trg_leads_zz_sello_descarte le deja descartado_en = NULL (E17: pendiente de B8).
select set_config('crm.op_bases_carga', 'on', true);
select set_config('crm.op_privilegiada', 'on', true);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte, asignado_supervisor_id, vendedor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'base_cargada', 'descartado', 'base_cargada', f.s1, null, x.monto, 'PEN', f.s1, true
  from f, lateral (values (f.lb, 'B7 BASE SIN CAPITAL', f.tel_lb, null::numeric), (f.lc, 'B7 BASE CON CAPITAL', '966710003', 5000::numeric),
                          (f.lt, 'B7 BASE TOMAR', f.tel_lt, null::numeric)) x(id, nombre, tel, monto);
select set_config('crm.op_privilegiada', 'off', true);
-- lq: un base_cargada que llegó a un analista CON capital y él lo descartó (deja su episodio cerrado en lead_asignaciones,
-- que es lo que el rescate reparte); el capital se le quita después con el andamio de abajo (V7).
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select f.lq, 'B7 BASE RESCATE', '966710007', 'base_cargada', 'nuevo', f.v1, 1000, 'PEN', f.v1, true from f;
select set_config('crm.op_bases_carga', 'off', true);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = (select lq from f);
-- Andamio (solo en esta transacción, como cartera_f5_exigir en b6b/b6c): fechar el descarte de un lead sin pasar por
-- trg_leads_zz_sello_descarte, para simular un descarte viejo (el enfriamiento y «tomar lead libre» dependen de esa fecha).
create function pg_temp.fechar_descarte(p_lead uuid, p_dias integer) returns void language plpgsql as $$
begin
  alter table crm.leads disable trigger trg_leads_zz_sello_descarte;
  update crm.leads set descartado_en = now() - pg_catalog.make_interval(days => p_dias) where id = p_lead;
  alter table crm.leads enable trigger trg_leads_zz_sello_descarte;
end $$;
-- Andamio: quitar el capital a un lead de base descartado (lo que el sello prohíbe con razón), solo para construir V7.
create function pg_temp.vaciar_capital(p_lead uuid) returns void language plpgsql as $$
begin
  alter table crm.leads disable trigger trg_leads_000_base_cargada_solo_puerta;
  update crm.leads set monto_estimado = null where id = p_lead;
  alter table crm.leads enable trigger trg_leads_000_base_cargada_solo_puerta;
end $$;
select pg_temp.fechar_descarte((select lt from f), 10);
alter table f add column episodio_lq uuid;
update f set episodio_lq = (select la.id from crm.lead_asignaciones la where la.lead_id = f.lq and la.resultado = 'descartado' order by la.resultado_en desc limit 1);
do $$ begin if (select episodio_lq is null from f) then raise exception 'b7-esquema: lq no dejó episodio cerrado en lead_asignaciones'; end if; end $$;
insert into crm.bases_carga (id, nombre, origen, supervisor_id, creada_por, operacion_id, archivo_nombre, filas_recibidas, cargadas, invalidas)
select x.id, x.nombre, x.origen, x.sup, x.sup, gen_random_uuid(), x.archivo, x.filas, x.cargadas, x.invalidas
  from f, lateral (values (f.b1, 'Feria 2025', 'archivo', f.s1, 'feria-2025.xlsx', 3, 2, 1),
                          (f.b2, 'feria 2025', 'crm', f.s2, null, 1, 1, 0),
                          (f.b3, 'Anidada', 'crm', f.sa, null, 0, 0, 0)) x(id, nombre, origen, sup, archivo, filas, cargadas, invalidas);
insert into crm.base_carga_leads (base_id, lead_id, procedencia, agregado_por, analista_id, asignado_en, asignado_por)
select x.base, x.lead, x.proc, x.agrega, x.analista, case when x.analista is null then null else now() end, case when x.analista is null then null else x.agrega end
  from f, lateral (values (f.b1, f.lb, 'archivo', f.s1, null::uuid), (f.b1, f.lc, 'archivo', f.s1, null::uuid),
                          (f.b2, f.le, 'crm', f.s2, f.v3)) x(base, lead, proc, agrega, analista);
insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
select x.actor, x.op, x.base, x.tipo, md5(x.tipo), '{"ok": true}'::jsonb
  from f, lateral (values (f.s1, 'b7000000-0000-4000-8000-0000000000c1'::uuid, f.b1, 'crear'),
                          (f.s2, 'b7000000-0000-4000-8000-0000000000c2'::uuid, f.b2, 'armar'),
                          (f.sa, 'b7000000-0000-4000-8000-0000000000c3'::uuid, f.b3, 'crear')) x(actor, op, base, tipo);

-- ───────── A · Catálogo ─────────
select pg_temp.caso('A1 las 3 tablas: RLS activa, dueño postgres, ACL solo de postgres', 'true',
  (select (count(*) = 3)::text from pg_class c where c.oid in ('crm.bases_carga'::regclass, 'crm.base_carga_leads'::regclass, 'crm.base_carga_operaciones'::regclass)
     and c.relrowsecurity and c.relowner = 'postgres'::regrole and c.relacl is not null
     and not exists (select 1 from aclexplode(c.relacl) a where a.grantee <> 'postgres'::regrole)));
select pg_temp.caso('A2 sello en crm.leads: BEFORE INSERT OR UPDATE por fila, habilitado, sin WHEN ni columnas; INVOKER sin EXECUTE para la API', 'true',
  (select (count(*) = 1)::text from pg_trigger t join pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_base_cargada_solo_puerta' and t.tgenabled = 'O'
      and t.tgtype = 23 and t.tgqual is null and t.tgattr = ''::int2vector and not p.prosecdef
      and p.proconfig = array['search_path=""']::text[]
      and not has_function_privilege('anon', p.oid, 'EXECUTE') and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')));
select pg_temp.caso('A3 enfriamiento base_cargada = 30 días', '30', (select dias::text from crm.enfriamiento_politica where motivo = 'base_cargada'));
select pg_temp.caso('A4 CHECK del capital: vacío solo con base_cargada y descartado, la rama válida exige not null, validado', 'true',
  (select (pg_get_constraintdef(c.oid) like '%(monto_estimado IS NULL) AND (origen = ''base_cargada''::text) AND (etapa = ''descartado''::text)%(monto_estimado IS NOT NULL) AND (monto_estimado > (0)::numeric)%'
           and c.convalidated)::text from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_monto_estimado_valido'));
select pg_temp.caso('A5 monto_estimado ya no es NOT NULL', 'false',
  (select attnotnull::text from pg_attribute where attrelid = 'crm.leads'::regclass and attname = 'monto_estimado'));
select pg_temp.caso('A6 ninguna función nueva (ni leads_before_insert) entra al censo analítico', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c
    where c.objeto in ('private.trg_leads_base_cargada_solo_puerta()', 'private.bases_carga_operacion_inmutable()', 'private.leads_before_insert()')));

-- ───────── B · La API no lee ni escribe las tablas nuevas ─────────
do $b$
declare
  t text; a record; v_sql text; v_op text;
begin
  for t in select unnest(array['bases_carga', 'base_carga_leads', 'base_carga_operaciones']) loop
    for a in select * from (values ('anon', null::uuid, 'anon'), ('authenticated', (select v1 from f), 'analista'),
                                   ('authenticated', (select s1 from f), 'Supervisión'), ('authenticated', (select g from f), 'Gerencia'),
                                   ('authenticated', (select co from f), 'Coordinación'), ('service_role', null::uuid, 'service_role')) x(rol, uid, quien) loop
      foreach v_op in array array['select', 'insert', 'update', 'delete'] loop
        v_sql := case v_op
          when 'select' then format('select count(*) from crm.%I', t)
          when 'insert' then format('insert into crm.%I default values', t)
          -- Sin leer ninguna columna (ni WHERE): así solo cuenta el permiso de UPDATE (un `set id = id` exigiría también SELECT
          -- y escondería un UPDATE concedido: lo cazó el mutante «UPDATE de filas de base para service_role»).
          when 'update' then format('update crm.%I set creado_en = now()', t)
          else format('delete from crm.%I', t) end;
        perform pg_temp.prueba(format('B %s · %s %s → 42501', a.quien, v_op, t),
          case when a.rol = 'anon' then '42501 permission denied for schema crm' else format('42501 permission denied for table %s', t) end,
          v_sql, a.rol, a.uid);
      end loop;
    end loop;
  end loop;
end $b$;

-- ───────── C · Segundo candado: con SELECT concedido (solo dentro de esta transacción) ─────────
grant select on crm.bases_carga, crm.base_carga_leads, crm.base_carga_operaciones to authenticated;
create function pg_temp.bases_visibles() returns text language sql as $$
  select coalesce(string_agg(right(b.id::text, 2), ',' order by b.id), '') from crm.bases_carga b where b.id::text like 'b7000000-%' $$;
create function pg_temp.filas_visibles() returns text language sql as $$
  select coalesce(string_agg(right(l.lead_id::text, 2), ',' order by l.lead_id), '') from crm.base_carga_leads l $$;
create function pg_temp.recibos_visibles() returns text language sql as $$
  select coalesce(string_agg(right(o.operacion_id::text, 2), ',' order by o.operacion_id), '') from crm.base_carga_operaciones o $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
select pg_temp.caso('C1 Supervisión (S1) ve su base y la de su supervisor anidado', 'b1,b3', pg_temp.valor('select pg_temp.bases_visibles()', 'authenticated', (select s1 from f)));
select pg_temp.caso('C2 el supervisor anidado ve solo la suya', 'b3', pg_temp.valor('select pg_temp.bases_visibles()', 'authenticated', (select sa from f)));
select pg_temp.caso('C3 S2 ve solo la suya (no la de S1 con el mismo nombre)', 'b2', pg_temp.valor('select pg_temp.bases_visibles()', 'authenticated', (select s2 from f)));
select pg_temp.caso('C4 Gerencia ve todas', 'b1,b2,b3', pg_temp.valor('select pg_temp.bases_visibles()', 'authenticated', (select g from f)));
select pg_temp.caso('C5 el analista no ve ninguna base', '', pg_temp.valor('select pg_temp.bases_visibles()', 'authenticated', (select v1 from f)));
select pg_temp.caso('C6 Coordinación no ve ninguna base', '', pg_temp.valor('select pg_temp.bases_visibles()', 'authenticated', (select co from f)));
select pg_temp.caso('C7 filas de base: S1 ve las de su base', 'a2,a3', pg_temp.valor('select pg_temp.filas_visibles()', 'authenticated', (select s1 from f)));
select pg_temp.caso('C8 filas de base: S2 ve la suya', 'a5', pg_temp.valor('select pg_temp.filas_visibles()', 'authenticated', (select s2 from f)));
select pg_temp.caso('C9 filas de base: el analista al que se repartió (V3) no ve nada', '', pg_temp.valor('select pg_temp.filas_visibles()', 'authenticated', (select v3 from f)));
select pg_temp.caso('C10 filas de base: Gerencia ve todas', 'a2,a3,a5', pg_temp.valor('select pg_temp.filas_visibles()', 'authenticated', (select g from f)));
select pg_temp.caso('C11 recibos: S1 ve los de su base y de su anidado', 'c1,c3', pg_temp.valor('select pg_temp.recibos_visibles()', 'authenticated', (select s1 from f)));
select pg_temp.caso('C12 recibos: S2 solo el suyo', 'c2', pg_temp.valor('select pg_temp.recibos_visibles()', 'authenticated', (select s2 from f)));
select pg_temp.caso('C13 recibos: el analista nada', '', pg_temp.valor('select pg_temp.recibos_visibles()', 'authenticated', (select v1 from f)));
select pg_temp.caso('C14 recibos: Gerencia todos', 'c1,c2,c3', pg_temp.valor('select pg_temp.recibos_visibles()', 'authenticated', (select g from f)));
revoke select on crm.bases_carga, crm.base_carga_leads, crm.base_carga_operaciones from authenticated;

-- ───────── D · Recibos inmutables y únicos ─────────
select pg_temp.prueba('D1 UPDATE de un recibo (incluso el dueño de la tabla) → P0409', (select m_recibo from f), 'update crm.base_carga_operaciones set tipo = ''recoger''');
select pg_temp.prueba('D2 DELETE de un recibo → P0409', (select m_recibo from f), 'delete from crm.base_carga_operaciones');
select pg_temp.prueba('D3 TRUNCATE de los recibos → P0409', (select m_recibo from f), 'truncate crm.base_carga_operaciones');
select pg_temp.prueba('D4 mismo actor y mismo id de operación → 23505', '23505 duplicate key value violates unique constraint "base_carga_operaciones_actor_operacion_unica"',
  format('insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta) values (%L, %L, %L, %L, md5(''x''), ''{}'')',
         (select s1 from f), 'b7000000-0000-4000-8000-0000000000c1', (select b1 from f), 'cargar_lote'));
select pg_temp.prueba('D5 el mismo id de operación con OTRO actor sí entra', 'paso',
  format('insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta) values (%L, %L, %L, %L, md5(''x''), ''{}'')',
         (select g from f), 'b7000000-0000-4000-8000-0000000000c1', (select b1 from f), 'repartir'));
select pg_temp.prueba('D6 respuesta que no es un objeto → 23514', '23514 new row for relation "base_carga_operaciones" violates check constraint "base_carga_operaciones_respuesta_valida"',
  format('insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta) values (%L, gen_random_uuid(), %L, ''crear'', md5(''x''), ''[1]'')', (select s1 from f), (select b1 from f)));
select pg_temp.prueba('D7 respuesta de más de 64 KB → 23514', '23514 new row for relation "base_carga_operaciones" violates check constraint "base_carga_operaciones_respuesta_valida"',
  format('insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta) values (%L, gen_random_uuid(), %L, ''crear'', md5(''x''), jsonb_build_object(''x'', repeat(''a'', 70000)))', (select s1 from f), (select b1 from f)));
select pg_temp.prueba('D8 md5 del pedido inválido → 23514', '23514 new row for relation "base_carga_operaciones" violates check constraint "base_carga_operaciones_pedido_md5_valido"',
  format('insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta) values (%L, gen_random_uuid(), %L, ''crear'', upper(md5(''x'')), ''{}'')', (select s1 from f), (select b1 from f)));
select pg_temp.prueba('D9 tipo desconocido → 23514', '23514 new row for relation "base_carga_operaciones" violates check constraint "base_carga_operaciones_tipo_check"',
  format('insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta) values (%L, gen_random_uuid(), %L, ''borrar'', md5(''x''), ''{}'')', (select s1 from f), (select b1 from f)));

-- ───────── E · Capital vacío solo en un base_cargada DESCARTADO, y nunca se vacía ─────────
create function pg_temp.lead_sql(p_id text, p_origen text, p_monto text, p_tel text, p_etapa text default 'nuevo') returns text language sql as $$
  select format('insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo) values (%L, ''B7 E'', %L, %L, %L, %L, %L, %s, ''PEN'', %L, true)',
                p_id, p_tel, p_origen, p_etapa, case when p_etapa = 'descartado' then 'base_cargada' end, (select s1 from f), p_monto, (select s1 from f)) $$;
select pg_temp.prueba('E1 capital NULL con origen oficina (aunque haya válvula) → 23514', (select m_check_monto from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e1', 'oficina', 'null', '966710011'), p_valvula => true);
select pg_temp.prueba('E2 capital NULL con origen landing → 23514', (select m_check_monto from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e2', 'landing', 'null', '966710012'));
select pg_temp.prueba('E2b capital NULL en un descartado de otro origen (oficina, con las dos válvulas) → 23514', (select m_check_monto from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000ec', 'oficina', 'null', '966710009', 'descartado'), p_valvula => true, p_priv => true);
select pg_temp.prueba('E3 base_cargada sin capital que NACE descartado, con las dos válvulas → entra', 'paso',
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e3', 'base_cargada', 'null', '966710013', 'descartado'), p_valvula => true, p_priv => true);
select pg_temp.prueba('E3b base_cargada sin capital que nace NUEVO, ni con la válvula → 23514 (sin capital solo dentro de descartado)', (select m_check_monto from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000eb', 'base_cargada', 'null', '966710010'), p_valvula => true);
select pg_temp.prueba('E4 base_cargada sin capital, descartado, SIN la válvula de bases (con op_privilegiada) → 42501', (select m_origen from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e4', 'base_cargada', 'null', '966710014', 'descartado'), p_priv => true);
select pg_temp.prueba('E5 origen base_cargada CON capital y sin la válvula → 42501', (select m_origen from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e5', 'base_cargada', '5000', '966710015'));
select pg_temp.prueba('E6 base_cargada con capital 0 → 23514 (las tres condiciones siguen)', (select m_check_monto from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e6', 'base_cargada', '0', '966710016'), p_valvula => true);
select pg_temp.prueba('E7 base_cargada con 3 decimales → 23514', (select m_check_monto from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e7', 'base_cargada', '1000.005', '966710017'), p_valvula => true);
select pg_temp.prueba('E8 base_cargada por encima del máximo → 23514', (select m_check_monto from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000e8', 'base_cargada', '10000000000', '966710018'), p_valvula => true);
select pg_temp.prueba('E9 vaciar el capital de un lead de base (descartado: el CHECK lo dejaría) → 23514 del sello', (select m_vaciar from f),
  format('update crm.leads set monto_estimado = null where id = %L', (select lc from f)));
select pg_temp.prueba('E10 vaciar el capital ni con la válvula → 23514', (select m_vaciar from f),
  format('update crm.leads set monto_estimado = null where id = %L', (select lc from f)), p_valvula => true);
select pg_temp.prueba('E11 el analista vacía el capital de su lead por la API → 23514', (select m_vaciar from f),
  format('update crm.leads set monto_estimado = null where id = %L', (select la from f)), 'authenticated', (select v1 from f));
select pg_temp.caso('E11b ese 23514 lleva detail leads_monto_estimado_valido (el front muestra su mensaje de capital)', '23514|leads_monto_estimado_valido',
  pg_temp.detalle(format('update crm.leads set monto_estimado = null where id = %L', (select la from f)), 'authenticated', (select v1 from f)));
select pg_temp.prueba('E12 sacar del descarte un lead de base SIN capital (UPDATE directo) → 23514 del CHECK', (select m_check_monto from f),
  format('update crm.leads set etapa = ''nuevo'', motivo_descarte = null where id = %L', (select lb from f)));
select pg_temp.prueba('E12b … ni con la válvula de bases → 23514', (select m_check_monto from f),
  format('update crm.leads set etapa = ''nuevo'', motivo_descarte = null where id = %L', (select lb from f)), p_valvula => true);
select pg_temp.prueba('E13 sacarlo del descarte completando el capital en el mismo cambio → entra', 'paso',
  format('update crm.leads set etapa = ''nuevo'', motivo_descarte = null, monto_estimado = 2000 where id = %L', (select lb from f)));
select pg_temp.prueba('E14 tocar otra columna del lead sin capital mientras sigue descartado → entra', 'paso',
  format('update crm.leads set nota = ''B7 nota'' where id = %L', (select lb from f)));
-- E17–E19: el pendiente (a) lo resuelve B8 (20261004184501): con B8 aplicada el dormido nace CON descartado_en (disparador
-- trg_leads_zz_sello_descarte_base_cargada) y el alta y «tomar lead libre» ven «enfriamiento». Sin B8, lo de B7.
select pg_temp.caso('E17 el contacto que nace descartado: sin B8 queda SIN descartado_en (sello del descarte); con B8 nace con la fecha',
  case when (to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)') is not null) then 'descartado|base_cargada|true|true' else 'descartado|base_cargada|true|false' end,
  (select format('%s|%s|%s|%s', etapa, motivo_descarte, (monto_estimado is null)::text, (descartado_en is not null)::text)
     from crm.leads where id = (select lb from f)));
select pg_temp.caso('E18 el alta de ese teléfono: sin B8 ve «libre» (duplicaría); con B8, «enfriamiento» (base_cargada 30 días)',
  case when (to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)') is not null) then 'enfriamiento' else 'libre' end,
  (select private.verificar_disponibilidad_lead_impl((select tel_lb from f), null, null)->>'estado'));
select pg_temp.caso('E19 «tomar lead libre»: sin B8 no lo ve («libre»); con B8, «enfriamiento»; el lead sigue en la bandeja de S1',
  case when (to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)') is not null) then 'enfriamiento|descartado|true' else 'libre|descartado|true' end,
  pg_temp.valor(format('select crm.tomar_lead_libre(%L, null)->>''estado''', (select tel_lb from f)), 'authenticated', (select v1 from f))
  || (select format('|%s|%s', etapa, (vendedor_id is null and asignado_supervisor_id = (select s1 from f))::text) from crm.leads where id = (select lb from f)));
select pg_temp.caso('E20 con fecha de descarte (hace 10 días), la política base_cargada (30 días) da «enfriamiento» hasta descartado_en + 30', 'enfriamiento|base_cargada|true',
  (select format('%s|%s|%s', v->>'estado', v->>'motivo_descarte', ((v->>'disponible_desde')::timestamptz = l.descartado_en + interval '30 days')::text)
     from crm.leads l, lateral (select private.verificar_disponibilidad_lead_impl((select tel_lt from f), null, null) v) x where l.id = (select lt from f)));
select pg_temp.caso('E21 … y «tomar lead libre» del analista no lo toma (enfriamiento)', 'enfriamiento',
  pg_temp.valor(format('select crm.tomar_lead_libre(%L, null)->>''estado''', (select tel_lt from f)), 'authenticated', (select v1 from f)));

-- ───────── V · Ninguna vía saca del descarte a un lead SIN capital (23514 del CHECK); con el capital puesto, pasan ─────────
-- Puertas REALES con sesión de usuario: reactivar_lead_base (S1, su bandeja), reabrir_lead_fn (S1), tomar_lead_libre (V1,
-- descarte vencido) y rescatar_descartes (S1, episodio cerrado de V1 → V2). Cada caso se deshace.
create function pg_temp.como(p_uid uuid) returns text language sql as $$
  select format('select pg_temp.sesion(%L); set local role authenticated; ', p_uid) $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
select pg_temp.prueba('V1 reactivar_lead_base (Supervisión, su bandeja) de un lead de base sin capital → 23514', (select m_check_monto from f),
  pg_temp.como((select s1 from f)) || format('select crm.reactivar_lead_base(gen_random_uuid(), %L, ''B7 V1'')', (select lb from f)));
select pg_temp.prueba('V2 … con el capital puesto antes, reactivar_lead_base pasa', 'paso',
  format('update crm.leads set monto_estimado = 2000 where id = %L; ', (select lb from f)) || pg_temp.como((select s1 from f))
  || format('select crm.reactivar_lead_base(gen_random_uuid(), %L, ''B7 V2'')', (select lb from f)));
select pg_temp.prueba('V3 reabrir_lead_fn («Reabrir» de la ficha) de un lead de base sin capital → 23514', (select m_check_monto from f),
  pg_temp.como((select s1 from f)) || format('select crm.reabrir_lead_fn(%L)', (select lb from f)));
select pg_temp.prueba('V4 … con el capital puesto, reabrir_lead_fn pasa', 'paso',
  format('update crm.leads set monto_estimado = 2000 where id = %L; ', (select lb from f)) || pg_temp.como((select s1 from f))
  || format('select crm.reabrir_lead_fn(%L)', (select lb from f)));
select pg_temp.prueba('V5 tomar_lead_libre (analista) de un lead de base sin capital con el descarte vencido → 23514', (select m_check_monto from f),
  format('select pg_temp.fechar_descarte(%L, 40); ', (select lt from f)) || pg_temp.como((select v1 from f))
  || format('select crm.tomar_lead_libre(%L, null)', (select tel_lt from f)));
select pg_temp.prueba('V6 … con el capital puesto, tomar_lead_libre lo toma (reutilizable)', 'paso',
  format('select pg_temp.fechar_descarte(%L, 40); update crm.leads set monto_estimado = 2000 where id = %L; ', (select lt from f), (select lt from f))
  || pg_temp.como((select v1 from f))
  -- En dos sentencias: dentro de UNA, la subconsulta no ve lo que escribió la función (misma instantánea).
  || format('select crm.tomar_lead_libre(%L, null); do $t$ begin if not exists (select 1 from crm.leads where id = %L and etapa = ''nuevo'' and vendedor_id = %L and monto_estimado = 2000) then raise exception ''no lo tomó''; end if; end $t$',
            (select tel_lt from f), (select lt from f), (select v1 from f)));
select pg_temp.prueba('V7 rescatar_descartes (Supervisión) de un descarte de base sin capital → 23514', (select m_check_monto from f),
  format('select pg_temp.vaciar_capital(%L); ', (select lq from f)) || pg_temp.como((select s1 from f))
  || format('select crm.rescatar_descartes(array[%L]::uuid[], array[%L]::uuid[], true)', (select episodio_lq from f), (select v2 from f)));
select pg_temp.prueba('V8 … con el capital puesto, rescatar_descartes pasa', 'paso',
  pg_temp.como((select s1 from f))
  || format('select crm.rescatar_descartes(array[%L]::uuid[], array[%L]::uuid[], true); do $t$ begin if not exists (select 1 from crm.leads where id = %L and etapa = ''nuevo'' and vendedor_id = %L) then raise exception ''no lo rescató''; end if; end $t$',
            (select episodio_lq from f), (select v2 from f), (select lq from f), (select v2 from f)));

-- ───────── F · Motivo base_cargada solo con la válvula ─────────
select pg_temp.prueba('F1 el analista descarta su lead con motivo base_cargada por la API → 42501', (select m_motivo from f),
  format('update crm.leads set etapa = ''descartado'', motivo_descarte = ''base_cargada'' where id = %L', (select la from f)), 'authenticated', (select v1 from f));
select pg_temp.prueba('F2 el analista descarta su lead con no_responde por la API → entra', 'paso',
  format('update crm.leads set etapa = ''descartado'', motivo_descarte = ''no_responde'' where id = %L', (select la from f)), 'authenticated', (select v1 from f));
select pg_temp.prueba('F3 Supervisión cambia el motivo de un descartado de su equipo a base_cargada → 42501', (select m_motivo from f),
  format('update crm.leads set motivo_descarte = ''base_cargada'' where id = %L', (select ld from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('F4 sin usuario y sin válvula (migración, job, importador) → 42501: sin exención', (select m_motivo from f),
  format('update crm.leads set motivo_descarte = ''base_cargada'' where id = %L', (select ld from f)));
select pg_temp.prueba('F5 con la válvula el CHECK acepta el motivo base_cargada', 'paso',
  format('update crm.leads set motivo_descarte = ''base_cargada'' where id = %L', (select ld from f)), p_valvula => true);
select pg_temp.prueba('F6 un lead que YA tiene motivo base_cargada se sigue editando sin válvula', 'paso',
  format('update crm.leads set nota = ''B7 F6'' where id = %L', (select lc from f)));
select pg_temp.prueba('F8 Supervisión «despierta» un dormido de su bandeja cambiándole el motivo a datos_invalidos → 42501', (select m_despertar from f),
  format('update crm.leads set motivo_descarte = ''datos_invalidos'' where id = %L', (select lb from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('F9 … tampoco sin usuario (migración, job)', (select m_despertar from f),
  format('update crm.leads set motivo_descarte = ''no_responde'' where id = %L', (select lb from f)));
select pg_temp.prueba('F10 … ni con capital (el dormido con capital tampoco se despierta por el motivo)', (select m_despertar from f),
  format('update crm.leads set motivo_descarte = ''datos_invalidos'' where id = %L', (select lc from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('F11 con la válvula de bases sí se cambia el motivo', 'paso',
  format('update crm.leads set motivo_descarte = ''no_responde'' where id = %L', (select lc from f)), p_valvula => true);
select pg_temp.prueba('F7 nacer con motivo base_cargada sin válvula → 42501', (select m_motivo from f),
  format('insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte, vendedor_id, monto_estimado, moneda, creado_por, activo) values (''b7000000-0000-4000-8000-0000000000f7'', ''B7 F7'', ''966710027'', ''oficina'', ''nuevo'', ''base_cargada'', %L, 1000, ''PEN'', %L, true)', (select v1 from f), (select v1 from f)));

-- ───────── G · Origen base_cargada solo con la válvula ─────────
select pg_temp.prueba('G1 pasar a origen base_cargada con crm.op_privilegiada (que sí deja cambiar el origen) → 42501', (select m_origen from f),
  format('update crm.leads set origen = ''base_cargada'' where id = %L', (select la from f)), p_priv => true);
select pg_temp.prueba('G2 service_role (sin usuario) inserta un lead base_cargada → 42501', (select m_origen from f),
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000f1', 'base_cargada', '1000', '966710021'), 'service_role');
select pg_temp.prueba('G3 el importador (service_role) con origen base_cargada y sin capital → 42501', (select m_origen from f),
  'select crm.importar_lead_fn(''{"nombre_completo":"B7 IMPORT","telefono":"966710022","origen":"base_cargada","moneda":"PEN"}''::jsonb)', 'service_role');
select pg_temp.prueba('G4 la puerta de alta (crear_lead_si_disponible) no admite base_cargada → 22023 (su lista propia no cambia)', '22023 Origen invalido',
  'select crm.crear_lead_si_disponible(''B7 ALTA'', ''966710023'', ''base_cargada'', 1000, ''PEN'')', 'authenticated', (select v1 from f));
select pg_temp.prueba('G5 la lista del alta sigue sin «otro» (no se crean nuevos Otro)', '22023 Selecciona un canal concreto: Landing, Formulario, Referido o Walking',
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000f2', 'otro', '1000', '966710024'), p_valvula => true);

-- ───────── H · Un lead en UNA sola base viva ─────────
select pg_temp.prueba('H1 el mismo lead en otra base viva → 23505', '23505 duplicate key value violates unique constraint "base_carga_leads_lead_vivo_unico"',
  format('insert into crm.base_carga_leads (base_id, lead_id, procedencia, agregado_por) values (%L, %L, ''crm'', %L)', (select b2 from f), (select lb from f), (select s2 from f)));
select pg_temp.prueba('H2 retirado de su base, puede entrar a otra', 'paso',
  format('update crm.base_carga_leads set activo = false where lead_id = %L; insert into crm.base_carga_leads (base_id, lead_id, procedencia, agregado_por) values (%L, %L, ''crm'', %L)',
         (select lb from f), (select b2 from f), (select lb from f), (select s2 from f)));
select pg_temp.prueba('H3 el mismo lead dos veces en la misma base (aunque una fila esté retirada) → 23505', '23505 duplicate key value violates unique constraint "base_carga_leads_base_lead_unico"',
  format('update crm.base_carga_leads set activo = false where lead_id = %L; insert into crm.base_carga_leads (base_id, lead_id, procedencia, agregado_por) values (%L, %L, ''archivo'', %L)',
         (select lc from f), (select b1 from f), (select lc from f), (select s1 from f)));

-- ───────── I · Coherencia del reparto ─────────
select pg_temp.prueba('I1 analista sin cuándo ni quién → 23514', '23514 new row for relation "base_carga_leads" violates check constraint "base_carga_leads_asignacion_coherente"',
  format('update crm.base_carga_leads set analista_id = %L where lead_id = %L', (select v1 from f), (select lb from f)));
select pg_temp.prueba('I2 analista con cuándo pero sin quién → 23514', '23514 new row for relation "base_carga_leads" violates check constraint "base_carga_leads_asignacion_coherente"',
  format('update crm.base_carga_leads set analista_id = %L, asignado_en = now() where lead_id = %L', (select v1 from f), (select lb from f)));
select pg_temp.prueba('I3 quién sin analista → 23514', '23514 new row for relation "base_carga_leads" violates check constraint "base_carga_leads_asignacion_coherente"',
  format('update crm.base_carga_leads set asignado_por = %L where lead_id = %L', (select s1 from f), (select lb from f)));
select pg_temp.prueba('I4 los tres juntos (repartir) → entra', 'paso',
  format('update crm.base_carga_leads set analista_id = %L, asignado_en = now(), asignado_por = %L where lead_id = %L', (select v1 from f), (select s1 from f), (select lb from f)));
select pg_temp.prueba('I5 los tres a NULL (recoger) → entra', 'paso',
  format('update crm.base_carga_leads set analista_id = null, asignado_en = null, asignado_por = null where lead_id = %L', (select le from f)));
select pg_temp.prueba('I6 procedencia desconocida → 23514', '23514 new row for relation "base_carga_leads" violates check constraint "base_carga_leads_procedencia_check"',
  format('update crm.base_carga_leads set procedencia = ''excel'' where lead_id = %L', (select lb from f)));

-- ───────── J · Restricciones de la base ─────────
create function pg_temp.base_sql(p_nombre text, p_origen text, p_archivo text, p_sup uuid, p_totales text default '0, 0, 0, 0, 0, 0') returns text language sql as $$
  select format('insert into crm.bases_carga (nombre, origen, supervisor_id, creada_por, operacion_id, archivo_nombre, filas_recibidas, cargadas, ya_existian, no_contactar, invalidas, repetidas) values (%L, %L, %L, %L, gen_random_uuid(), %L, %s)',
                p_nombre, p_origen, p_sup, p_sup, p_archivo, p_totales) $$;
select pg_temp.prueba('J1 nombre vacío → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_nombre_valido"', pg_temp.base_sql('', 'crm', null, (select s1 from f)));
select pg_temp.prueba('J2 nombre con espacios al borde → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_nombre_valido"', pg_temp.base_sql(' Feria', 'crm', null, (select s1 from f)));
select pg_temp.prueba('J3 nombre de 81 caracteres → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_nombre_valido"', pg_temp.base_sql(repeat('x', 81), 'crm', null, (select s1 from f)));
select pg_temp.prueba('J4 nombre de 80 caracteres → entra', 'paso', pg_temp.base_sql(repeat('x', 80), 'crm', null, (select s1 from f)));
select pg_temp.prueba('J5 mismo nombre (otras mayúsculas) en la misma bandeja viva → 23505', '23505 duplicate key value violates unique constraint "bases_carga_nombre_vivo_unico"', pg_temp.base_sql('FERIA 2025', 'crm', null, (select s1 from f)));
select pg_temp.prueba('J6 retirada la base, el nombre se puede reutilizar', 'paso',
  format('update crm.bases_carga set activo = false where id = %L; ', (select b1 from f)) || pg_temp.base_sql('Feria 2025', 'crm', null, (select s1 from f)));
select pg_temp.prueba('J7 origen archivo sin nombre de archivo → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_archivo_coherente"', pg_temp.base_sql('J7', 'archivo', null, (select s1 from f)));
select pg_temp.prueba('J8 origen crm con nombre de archivo → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_archivo_coherente"', pg_temp.base_sql('J8', 'crm', 'x.csv', (select s1 from f)));
select pg_temp.prueba('J9 origen desconocido → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_origen_check"', pg_temp.base_sql('J9', 'excel', null, (select s1 from f)));
select pg_temp.prueba('J9b nombre de archivo de 256 caracteres → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_archivo_nombre_valido"', pg_temp.base_sql('J9b', 'archivo', repeat('a', 256), (select s1 from f)));
select pg_temp.prueba('J10 un total negativo → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_totales_no_negativos"', pg_temp.base_sql('J10', 'crm', null, (select s1 from f), '1, 2, 0, 0, 0, -1'));
select pg_temp.prueba('J11 los totales suman más que lo recibido → 23514', '23514 new row for relation "bases_carga" violates check constraint "bases_carga_totales_cuadran"', pg_temp.base_sql('J11', 'crm', null, (select s1 from f), '5, 2, 1, 1, 1, 1'));
select pg_temp.prueba('J12 los totales suman justo lo recibido → entra', 'paso', pg_temp.base_sql('J12', 'archivo', 'j12.xlsx', (select s1 from f), '6, 2, 1, 1, 1, 1'));
select pg_temp.prueba('J13 el mismo id de operación para otra base → 23505', '23505 duplicate key value violates unique constraint "bases_carga_operacion_unica"',
  format('insert into crm.bases_carga (nombre, origen, supervisor_id, creada_por, operacion_id) select ''J13'', ''crm'', supervisor_id, creada_por, operacion_id from crm.bases_carga where id = %L', (select b2 from f)));
select pg_temp.prueba('J14 sin supervisor dueño → 23502', '23502 null value in column "supervisor_id" of relation "bases_carga" violates not-null constraint', pg_temp.base_sql('J14', 'crm', null, null));

-- ───────── K · Auditoría ─────────
select pg_temp.caso('K1 la siembra dejó rastro en audit_log (3 bases, 3 filas, 3 recibos)', '3|3|3',
  (select format('%s|%s|%s', count(*) filter (where tabla = 'crm.bases_carga'), count(*) filter (where tabla = 'crm.base_carga_leads'),
                 count(*) filter (where tabla = 'crm.base_carga_operaciones'))
     from public.audit_log where operacion = 'INSERT' and ts >= now() and tabla in ('crm.bases_carga', 'crm.base_carga_leads', 'crm.base_carga_operaciones')));
select pg_temp.caso('K2 las 3 tablas fuera de la lista de tablas sin rastro', '0',
  (select count(*)::text from private.tablas_sin_rastro() t where t::text in ('crm.bases_carga', 'crm.base_carga_leads', 'crm.base_carga_operaciones')));

-- ───────── L · Regresión de lo de siempre ─────────
select pg_temp.prueba('L1 el analista cambia el capital de su lead a un valor válido', 'paso',
  format('update crm.leads set monto_estimado = 2500 where id = %L', (select la from f)), 'authenticated', (select v1 from f));
select pg_temp.prueba('L2 un lead nuevo de origen oficina con capital sigue naciendo', 'paso',
  pg_temp.lead_sql('b7000000-0000-4000-8000-0000000000f3', 'oficina', '1000', '966710025'));
select pg_temp.prueba('L3 la puerta de alta crea un lead normal', 'paso',
  'select crm.crear_lead_si_disponible(''B7 ALTA NORMAL'', ''966710026'', ''oficina'', 1000, ''PEN'')', 'authenticated', (select v1 from f));

-- ───────── Resultado ─────────
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 220)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B7: hay casos FAIL'; end if; end $$;
rollback;
