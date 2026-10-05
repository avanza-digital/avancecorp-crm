-- B6c · la nota del veto (crm.actividades, metadata evento = no_contactar) queda reservada a sus puertas e inmutable, en el banco (UNA
-- transacción, impersonación con claims + set local role, ROLLBACK al final). Falla el proceso si hay un FAIL. Corre sobre un
-- banco LOCAL con B6c (20261004123611) aplicada y los actores de seed:demo (el banco del gate). Siembra leads transitorios
-- b6c00000-… y dos personas que se deshacen con el ROLLBACK.
-- Qué prueba: catálogo del sello (trigger, DEFINER, ACL, md5) y de levantar; la API (analista, Supervisión, Gerencia) NO
-- escribe la nota — marcar, levantar, sin acción, con tipo de contacto, con la bandera apagada — y la marca que B6b muestra
-- no cambia; sí escribe notas normales; las puertas REALES con sesión de usuario siguen escribiendo su nota (marcar, levantar
-- de Supervisión y de Gerencia, persona por enlace y puente con la bandera encendida, postventa vetar y levantar, marcar con
-- la bandera apagada) y B6b muestra la marca correcta tras cada una; ninguna deja la válvula encendida; sin usuario y
-- service_role sin sub siguen pudiendo (migraciones, backfills; exención aceptada); service_role CON sub no. r1 (auditor-rls r1):
-- variantes del evento ('No_Contactar', ' no_contactar ', tabulador) rechazadas; la nota del veto es INMUTABLE: UPDATE de
-- cualquier columna (detalle, creado_en, autor a NULL, metadata) y DELETE → 42501 salvo válvula o sin usuario.
-- Andamio dentro de la transacción (como b6b-vetados.sql): private.cartera_f5_exigir neutralizada (el banco del gate tiene
-- contratos sin identidad coherente y la postventa se negaría antes de vetar) y la bandera resolver_en_puertas encendida.
-- Mutantes: `node supabase/scripts/base-gestion/b6c-mutantes.mjs --puerto <puerto del banco local>` inyecta cada uno en la
-- línea @@MUTANTE@@ y exige que esta suite FALLE en su caso.
\set ON_ERROR_STOP on
-- Solo banco LOCAL (P3 del auditor-rls de B6b): el secreto JWT de la base tiene que ser el valor de desarrollo PÚBLICO del
-- Supabase CLI (se compara su md5; un proyecto alojado tiene el suyo) y la conexión no va por SSL.
do $solo_banco_local$
begin
  if (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646'
      and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid())) is not true then
    raise exception 'b6c-nota-veto: solo corre en un banco LOCAL de Docker (Supabase CLI); esta base no lo es';
  end if;
end $solo_banco_local$;
begin;
-- @@MUTANTE@@

-- ───────── Utilidades (todo en pg_temp: se va con el ROLLBACK) ─────────
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated, service_role; grant usage, select on sequence r_n_seq to authenticated, service_role;
create function pg_temp.sesion(p uuid, p_rol text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), true),
         set_config('request.jwt.claims', case when p is null and p_rol = 'authenticated' then ''
                                               else json_build_object('sub', p, 'role', p_rol)::text end, true);
$$;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$ insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
-- err: ejecuta y DEJA el efecto (puertas reales); prueba: ejecuta y lo DESHACE (subtransacción). Las dos anotan «paso» o
-- «<sqlstate> <mensaje>»: un rechazo no tumba la suite y el caso falla donde debe (un mutante cae en SU caso).
create function pg_temp.err(p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_caso, p_esperado, 'paso'); exception when others then perform pg_temp.caso(p_caso, p_esperado, sqlstate || ' ' || sqlerrm); end $$;
create function pg_temp.prueba(p_caso text, p_esperado text, p_sql text, p_valvula boolean default false) returns void language plpgsql as $$
declare v text;
begin
  begin
    if p_valvula then perform set_config('crm.op_privilegiada', 'on', true); end if;  -- como hacen las puertas (se deshace)
    execute p_sql;
    v := 'paso';
    raise exception using errcode = 'P0001', message = 'B6C_DESHACER';
  exception when others then
    if v is null then v := sqlstate || ' ' || sqlerrm; end if;
  end;
  perform pg_temp.caso(p_caso, p_esperado, v);
end $$;
-- El INSERT que haría la API (PostgREST: insert en crm.actividades).
create function pg_temp.nota(p_lead uuid, p_actor uuid, p_meta text, p_tipo text default 'nota') returns text language sql as $$
  select format('insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values (%L, %L, %L, %L::jsonb, %L)',
                p_lead, p_tipo, 'b6c nota', p_meta, p_actor) $$;
-- Una fila de la lista del actor (B6b): «no_contactar|en|motivo|por|rellamada_hoy».
create function pg_temp.fila(p_lead uuid, p_vet boolean) returns text language sql as $$
  select coalesce((select format('%s|%s|%s|%s|%s', t.no_contactar::text, coalesce(to_char(t.no_contactar_en at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), '-'),
                                 coalesce(t.no_contactar_motivo, '-'), coalesce(t.no_contactar_por, '-'), t.rellamada_hoy::text)
                     from crm.obtener_base_gestion(null, p_vet) t where t.lead_id = p_lead), 'sin fila') $$;
-- La fila sin la hora (para comparar con «*»).
create function pg_temp.fila_sin_hora(p_lead uuid, p_vet boolean) returns text language sql as $$
  select regexp_replace(pg_temp.fila(p_lead, p_vet), '^true\|[^|]+\|', 'true|*|') $$;
-- La última nota del veto de un lead: «accion|rol|autor|motivo».
create function pg_temp.ultima(p_lead uuid) returns text language sql as $$
  select coalesce((select format('%s|%s|%s|%s', a.metadata->>'accion', coalesce(a.metadata->>'rol', '-'), a.creado_por, coalesce(a.metadata->>'motivo', '-'))
                     from crm.actividades a where a.lead_id = p_lead and a.metadata->>'evento' = 'no_contactar'
                    order by a.creado_en desc, a.id desc limit 1), 'sin nota') $$;
create function pg_temp.notas_veto(p_lead uuid) returns text language sql as $$
  select count(*)::text from crm.actividades a where a.lead_id = p_lead and a.metadata->>'evento' = 'no_contactar' $$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ───────── Actores (seed:demo), leads transitorios y personas ─────────
create temp table f as select
  (select id from auth.users where email = 'vend1.crm@demo.avancecorp.pe') v1,
  (select id from auth.users where email = 'vend2.crm@demo.avancecorp.pe') v2,
  (select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe') s1,
  (select id from auth.users where email = 'gerencia.crm@demo.avancecorp.pe') g,
  'b6c00000-0000-4000-8000-0000000000a1'::uuid la,   -- V1: lo marca su analista, intentos de falsificar, lo levanta S1
  'b6c00000-0000-4000-8000-0000000000a2'::uuid lb,   -- V2 (equipo de S1): Supervisión intenta falsificar
  'b6c00000-0000-4000-8000-0000000000a3'::uuid lc,   -- V1: notas normales, sin usuario, service_role, UPDATE (todo se deshace)
  'b6c00000-0000-4000-8000-0000000000a4'::uuid lg,   -- V1: lo marca su analista y lo levanta Gerencia
  'b6c00000-0000-4000-8000-0000000000a5'::uuid lf,   -- V1: con la bandera APAGADA (veto solo del lead)
  'b6c00000-0000-4000-8000-0000000000b1'::uuid lp1,  -- persona P, enlace
  'b6c00000-0000-4000-8000-0000000000b2'::uuid lp2,  -- persona P, puente
  'b6c00000-0000-4000-8000-0000000000c1'::uuid lq1,  -- persona Q (postventa), enlace
  'b6c00000-0000-4000-8000-0000000000c2'::uuid lq2,  -- persona Q (postventa), puente
  'b6c00000-0000-4000-8000-0000000000f1'::uuid pp,
  'b6c00000-0000-4000-8000-0000000000f2'::uuid pq,
  '42501 La nota de No contactar solo la escriben sus puertas (marcar, levantar o postventa); no se cambia ni se borra'::text msg;
alter table f add column n_v1 text, add column n_s1 text, add column n_g text;
update f set n_v1 = (select nombre_completo from public.perfiles where id = f.v1), n_s1 = (select nombre_completo from public.perfiles where id = f.s1),
             n_g = (select nombre_completo from public.perfiles where id = f.g);
grant select on f to authenticated, service_role;
do $$ begin
  if (select v1 is null or v2 is null or s1 is null or g is null from f) then
    raise exception 'b6c-nota-veto: faltan actores de seed:demo en este banco (correr el gate o seed:demo antes)';
  end if;
  if exists (select 1 from crm.leads where id::text like 'b6c00000-%') then
    raise exception 'b6c-nota-veto: ya hay leads b6c00000-… en el banco';
  end if;
end $$;
select pg_temp.sesion(null);
create or replace function private.cartera_f5_exigir() returns void language plpgsql security definer set search_path = '' as $andamio$
begin return; end
$andamio$;
update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';  -- siembra con la bandera apagada
insert into crm.inversionistas (id) select unnest(array[f.pp, f.pq]) from f;
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'oficina', 'nuevo', x.v, 1000, 'PEN', x.v, true
  from f, lateral (values
    (f.la, 'B6C MARCADO', '966700101', f.v1), (f.lb, 'B6C EQUIPO S1', '966700102', f.v2), (f.lc, 'B6C NOTAS', '966700103', f.v1),
    (f.lg, 'B6C LEVANTA GERENCIA', '966700104', f.v1), (f.lf, 'B6C BANDERA APAGADA', '966700105', f.v1),
    (f.lp1, 'B6C P ENLACE', '966700106', f.v1), (f.lp2, 'B6C P PUENTE', '966700107', f.v1),
    (f.lq1, 'B6C Q ENLACE', '966700108', f.v1), (f.lq2, 'B6C Q PUENTE', '966700109', f.v1)) x(id, nombre, tel, v);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id::text like 'b6c00000-%';
select set_config('crm.op_privilegiada', 'on', true);
update crm.leads l set inversionista_id = x.p from f, lateral (values (f.lp1, f.pp), (f.lq1, f.pq)) x(lead, p) where l.id = x.lead;
select set_config('crm.op_privilegiada', 'off', true);
insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
select x.p, x.lead, 'historico' from f, lateral (values (f.pp, f.lp2), (f.pq, f.lq2)) x(p, lead);
update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';  -- como en producción (desde el 07/09)
select pg_temp.caso('banco: 9 leads transitorios descartados, 2 personas (enlace + puente), bandera encendida', '9|2|2|true',
  (select count(*) filter (where etapa = 'descartado') || '|' || count(inversionista_id) || '|' || (select count(*) from crm.inversionista_leads il, f where il.lead_id in (f.lp2, f.lq2))
          || '|' || (select activo::text from crm.multiempresa_flags where nombre = 'resolver_en_puertas')
     from crm.leads where id::text like 'b6c00000-%'));

-- ───────── Catálogo ─────────
select pg_temp.caso('C1 sello: trigger habilitado, BEFORE INSERT OR UPDATE OR DELETE (toda columna), por fila, sin WHEN', 'O|31|t|t|t',
  (select format('%s|%s|%s|%s|%s', t.tgenabled, t.tgtype, t.tgqual is null, t.tgattr = ''::int2vector, pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR DELETE OR UPDATE ON crm.actividades FOR EACH ROW EXECUTE FUNCTION private.trg_actividades_no_contactar_solo_puerta()')
     from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta'));
select pg_temp.caso('C2 sello: md5 ensayado, DEFINER de postgres, search_path vacío, ACL solo postgres', 'af83cbd67513122a325d2f159254bb3c|t|t|t|{postgres=X/postgres}',
  (select format('%s|%s|%s|%s|%s', md5(p.prosrc), p.prosecdef, p.proowner = 'postgres'::regrole, p.proconfig = array['search_path=""']::text[], p.proacl)
     from pg_proc p where p.oid = 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure));
select pg_temp.caso('C3 sello: anon, authenticated y service_role sin EXECUTE', 'false',
  (select bool_or(has_function_privilege(x, 'private.trg_actividades_no_contactar_solo_puerta()', 'EXECUTE'))::text from unnest(array['anon','authenticated','service_role']) x));
select pg_temp.caso('C4 levantar: md5 B6c (nota antes de apagar la válvula), DEFINER, ACL exacta, una sobrecarga', '663780d27e3c7aa8d086f9a376ab3c4b|t|{postgres=X/postgres,authenticated=X/postgres}|1',
  (select format('%s|%s|%s|%s', md5(p.prosrc), p.prosecdef, p.proacl, (select count(*) from pg_proc where proname = 'levantar_no_contactar' and pronamespace = 'crm'::regnamespace))
     from pg_proc p where p.oid = 'crm.levantar_no_contactar(uuid,text)'::regprocedure));
select pg_temp.caso('C5 marcar y postventa intactos', '6cd5678eed537dc880c5ce4447165d30|c67d516bcd37562a93af6a1a8b4629f7',
  (select md5(prosrc) from pg_proc where oid = 'crm.marcar_no_contactar(uuid,text)'::regprocedure) || '|' ||
  (select md5(prosrc) from pg_proc where oid = 'crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)'::regprocedure));
-- B10 (20261004223253) reemplaza el cuerpo (base_id, base_nombre y sin los dormidos sin repartir) y AÑADE una frase al final del
-- comentario: con B10 aplicada se exige su cuerpo y que el comentario, sin la frase de B10, siga siendo el de B6c.
select pg_temp.caso('C6 obtener_base_gestion: cuerpo de B6b (o el de B10 si está aplicada); comentario B6c con el residuo de la bandera y sin acreditar notas anteriores',
  case when to_regprocedure('crm.seguimiento_bases()') is null then '36af7e9cc4d6ec319b3d8004f3903473' else '26d887dc635824f383b0eb236c8226fb' end || '|67f83881ece789fee1a37e0799123c18|t|t|t',
  (select format('%s|%s|%s|%s|%s', md5(p.prosrc), md5(split_part(obj_description(p.oid, 'pg_proc'), ' B10 (04/10/2026', 1)), obj_description(p.oid, 'pg_proc') like '%no lee la bandera resolver_en_puertas%',
                 obj_description(p.oid, 'pg_proc') not like '%se cierra en B6c%', obj_description(p.oid, 'pg_proc') like '%No acredita las notas anteriores a B6c%')
     from pg_proc p where p.oid = 'crm.obtener_base_gestion(uuid,boolean)'::regprocedure));
select pg_temp.caso('C7 fuera del censo analítico (sello y levantar)', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c where c.objeto in ('private.trg_actividades_no_contactar_solo_puerta()', 'crm.levantar_no_contactar(uuid,text)')));
select pg_temp.caso('C9 comentario del sello: exención aceptada de service_role sin sub, no acredita lo anterior, inmutable', 'f1fd306fb7afc8d405a778e14779a90a|t|t|t',
  (select format('%s|%s|%s|%s', md5(d), d like '%clave de servicio SIN sub: exención aceptada%', d like '%No acredita las notas escritas antes de su instalación%', d like '%DELETE de una nota del veto%')
     from obj_description('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure, 'pg_proc') d));
-- B10 (20261004223253): el UPDATE de actividades del núcleo de intentos vive en private.base_gestion_intento_capital_core (el de
-- siempre queda de envoltorio): con B10 aplicada, ese es el nombre de la lista.
select pg_temp.caso('C10 solo cuatro funciones cambian actividades (ninguna borra) y ninguna toca notas del veto',
  replace('crm.deshacer_resultado_llamada(uuid),private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone),private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean),private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)',
          case when to_regprocedure('crm.seguimiento_bases()') is null then 'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'
               else 'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)' end),
  (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text collate "C") from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~* 'update\s+crm\.actividades|delete\s+from\s+crm\.actividades'));
select pg_temp.caso('C8 solo tres cuerpos construyen la nota del veto', 'crm.levantar_no_contactar(uuid,text),crm.marcar_no_contactar(uuid,text),crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)',
  (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~* '''evento''\s*,\s*''no_contactar''|"evento"\s*:\s*"no_contactar"'));

-- ───────── F: el analista marca DE VERDAD ─────────
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('F1 V1 marca LA por la puerta (marcar_no_contactar)', 'paso', format('select crm.marcar_no_contactar(%L, %L)', (select la from f), 'motivo real'));
select pg_temp.caso('F2 la nota real: marcar, autor V1, con su motivo', (select format('marcar|-|%s|motivo real', v1) from f), pg_temp.ultima((select la from f)));
select pg_temp.caso('F3 tras marcar, la válvula quedó apagada', 'off', coalesce(current_setting('crm.op_privilegiada', true), 'off'));
reset role;
create temp table e as select (select to_char(a.creado_en at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') from crm.actividades a, f where a.lead_id = f.la and a.metadata->>'evento' = 'no_contactar') la_en;
grant select on e to authenticated, service_role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('F4 Supervisión ve la marca real de LA (cuándo, motivo, quién)', (select format('true|%s|motivo real|%s|false', e.la_en, f.n_v1) from e, f), pg_temp.fila((select la from f), true));
reset role;

-- ───────── A: la API NO escribe la nota del veto (y la marca no cambia) ─────────
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('A1 V1 inserta por la API un «marcar» con motivo falso en su lead → 42501 del sello', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":"no_contactar","accion":"marcar","motivo":"motivo falso"}'));
select pg_temp.err('A2 V1 inserta por la API un «levantar» (ocultaría la marca) → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":"no_contactar","accion":"levantar","motivo":"levantar falso"}'));
select pg_temp.err('A3 V1 inserta evento no_contactar sin acción → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":"no_contactar"}'));
select pg_temp.err('A4 V1 inserta evento no_contactar con tipo de contacto (el sello va antes que el de gestión) → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":"no_contactar","accion":"marcar"}', 'llamada_realizada'));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.err('A5 Supervisión inserta un «marcar» en un lead de su equipo (V2) → 42501', (select msg from f),
  pg_temp.nota((select lb from f), (select s1 from f), '{"evento":"no_contactar","accion":"marcar","motivo":"sup falso"}'));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.err('A6 Gerencia inserta un «marcar» en LA → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select g from f), '{"evento":"no_contactar","accion":"marcar","motivo":"gerencia falso"}'));
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('A9 V1 inserta la variante «No_Contactar» → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":"No_Contactar","accion":"marcar","motivo":"variante"}'));
select pg_temp.err('A10 V1 inserta la variante « no_contactar » (espacios) → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":" no_contactar ","accion":"marcar","motivo":"variante"}'));
select pg_temp.err('A11 V1 inserta la variante con tabulador y salto, en mayúsculas → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":"\tNO_CONTACTAR\n","accion":"marcar","motivo":"variante"}'));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('A7 tras los intentos, Supervisión sigue viendo la marca REAL de LA', (select format('true|%s|motivo real|%s|false', e.la_en, f.n_v1) from e, f), pg_temp.fila((select la from f), true));
reset role;
select pg_temp.caso('A8 en LA hay UNA sola nota del veto (la real)', '1', pg_temp.notas_veto((select la from f)));

-- ───────── P: la API SÍ escribe notas normales (se deshacen) ─────────
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.prueba('P1 V1 inserta una nota normal (sin metadata) → entra', 'paso',
  format('insert into crm.actividades (lead_id, tipo, detalle, creado_por) values (%L, %L, %L, %L)', (select lc from f), 'nota', 'b6c nota normal', (select v1 from f)));
select pg_temp.prueba('P2 V1 inserta una nota con otro evento → entra', 'paso', pg_temp.nota((select lc from f), (select v1 from f), '{"evento":"nota_libre"}'));
select pg_temp.prueba('P3 V1 inserta accion/motivo SIN evento (B6b no la lee) → entra', 'paso', pg_temp.nota((select lc from f), (select v1 from f), '{"accion":"marcar","motivo":"sin evento"}'));
select pg_temp.prueba('P7 V1 inserta un evento PARECIDO pero distinto (no_contactar_x) → entra (el sello es estrecho)', 'paso', pg_temp.nota((select lc from f), (select v1 from f), '{"evento":"no_contactar_x"}'));
-- Una nota normal que se QUEDA en LA no cambia la marca.
select pg_temp.err('P4 V1 deja una nota normal en LA', 'paso',
  format('insert into crm.actividades (lead_id, tipo, detalle, creado_por) values (%L, %L, %L, %L)', (select la from f), 'nota', 'b6c nota normal en LA', (select v1 from f)));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.prueba('P5 Supervisión inserta una nota normal en un lead de su equipo → entra', 'paso',
  format('insert into crm.actividades (lead_id, tipo, detalle, creado_por) values (%L, %L, %L, %L)', (select lb from f), 'nota', 'b6c nota sup', (select s1 from f)));
select pg_temp.caso('P6 una nota normal no cambia la marca de LA', (select format('true|%s|motivo real|%s|false', e.la_en, f.n_v1) from e, f), pg_temp.fila((select la from f), true));
reset role;

-- ───────── S: sin usuario y service_role (se deshacen) ─────────
select pg_temp.sesion(null);
select pg_temp.prueba('S1 sin usuario (migración, backfill) inserta la nota del veto → entra', 'paso',
  pg_temp.nota((select lc from f), (select v1 from f), '{"evento":"no_contactar","accion":"marcar","motivo":"backfill"}'));
select pg_temp.sesion(null, 'service_role'); set local role service_role;
select pg_temp.prueba('S2 service_role SIN sub (clave de servicio) inserta la nota del veto → entra', 'paso',
  pg_temp.nota((select lc from f), (select v1 from f), '{"evento":"no_contactar","accion":"marcar","motivo":"servicio"}'));
reset role;
select pg_temp.sesion((select v1 from f), 'service_role'); set local role service_role;
select pg_temp.prueba('S3 service_role CON sub (identidad de usuario) inserta la nota del veto → 42501', (select msg from f),
  pg_temp.nota((select lc from f), (select v1 from f), '{"evento":"no_contactar","accion":"marcar","motivo":"servicio con sub"}'));
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.prueba('S4 con la válvula de las puertas (crm.op_privilegiada = on) la nota entra (así escriben las tres)', 'paso',
  pg_temp.nota((select lc from f), (select v1 from f), '{"evento":"no_contactar","accion":"marcar","motivo":"valvula"}'), true);
select pg_temp.caso('S5 la prueba con válvula no la dejó encendida', 'off', coalesce(current_setting('crm.op_privilegiada', true), 'off'));
reset role;

-- ───────── U: UPDATE de la metadata ─────────
-- Una nota del veto y una normal en LC, sin usuario y bajo la válvula (así la siembra sobrevive a los mutantes que quitan
-- una de las dos exenciones; se quedan hasta el ROLLBACK).
select pg_temp.sesion(null);
select set_config('crm.op_privilegiada', 'on', true);
insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por) values
  ('b6c00000-0000-4000-8000-0000000000d1', (select lc from f), 'nota', 'b6c veto sembrado', '{"evento":"no_contactar","accion":"marcar","motivo":"sembrado"}', (select v1 from f)),
  ('b6c00000-0000-4000-8000-0000000000d2', (select lc from f), 'nota', 'b6c normal sembrada', '{}', (select v1 from f)),
  ('b6c00000-0000-4000-8000-0000000000d3', (select lc from f), 'nota', 'b6c variante sembrada', '{"evento":" No_Contactar ","accion":"marcar"}', (select v1 from f));
select set_config('crm.op_privilegiada', 'off', true);
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.prueba('U1 la API no actualiza actividades (sin grant UPDATE)', '42501 permission denied for table actividades',
  'update crm.actividades set metadata = metadata where id = ''b6c00000-0000-4000-8000-0000000000d2''');
reset role;
select pg_temp.sesion((select v1 from f), 'service_role'); set local role service_role;
select pg_temp.prueba('U2 service_role con sub cambia el motivo de la nota del veto → 42501', (select msg from f),
  'update crm.actividades set metadata = metadata || ''{"motivo":"reescrito"}'' where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U3 service_role con sub convierte una nota normal en nota del veto → 42501', (select msg from f),
  'update crm.actividades set metadata = ''{"evento":"no_contactar","accion":"marcar"}'' where id = ''b6c00000-0000-4000-8000-0000000000d2''');
select pg_temp.prueba('U4 service_role con sub le quita el evento a la nota del veto → 42501', (select msg from f),
  'update crm.actividades set metadata = ''{"evento":"otro"}'' where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U5 service_role con sub cambia la metadata de una nota normal → entra', 'paso',
  'update crm.actividades set metadata = ''{"etiqueta":"x"}'' where id = ''b6c00000-0000-4000-8000-0000000000d2''');
-- r1 (auditor-rls r1, P3): inmutable — cualquier columna, también el autor a NULL (lo que haría el SET NULL al borrar el perfil), y DELETE.
select pg_temp.prueba('U8 service_role con sub cambia el detalle de la nota del veto (otra columna) → 42501', (select msg from f),
  'update crm.actividades set detalle = ''reescrito'' where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U9 service_role con sub cambia creado_en de la nota del veto → 42501', (select msg from f),
  'update crm.actividades set creado_en = creado_en - interval ''1 day'' where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U10 service_role con sub deja la nota del veto sin autor (creado_por NULL) → 42501', (select msg from f),
  'update crm.actividades set creado_por = null where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U11 service_role con sub borra la nota del veto → 42501', (select msg from f),
  'delete from crm.actividades where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U12 service_role con sub borra una nota normal → entra', 'paso',
  'delete from crm.actividades where id = ''b6c00000-0000-4000-8000-0000000000d2''');
select pg_temp.prueba('U13 service_role con sub le quita el evento a una nota del veto escrita con variante (« No_Contactar ») → 42501', (select msg from f),
  'update crm.actividades set metadata = ''{"evento":"otro"}'' where id = ''b6c00000-0000-4000-8000-0000000000d3''');
select pg_temp.prueba('U14 con la válvula de las puertas, service_role con sub borra la nota del veto → entra', 'paso',
  'delete from crm.actividades where id = ''b6c00000-0000-4000-8000-0000000000d1''', true);
reset role;
select pg_temp.sesion(null);
select pg_temp.prueba('U6 sin usuario cambia creado_en de la nota del veto (no toca la metadata) → entra', 'paso',
  'update crm.actividades set creado_en = creado_en - interval ''1 minute'' where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U7 sin usuario cambia la metadata de la nota del veto → entra', 'paso',
  'update crm.actividades set metadata = metadata || ''{"motivo":"corregido por migracion"}'' where id = ''b6c00000-0000-4000-8000-0000000000d1''');
select pg_temp.prueba('U15 sin usuario borra la nota del veto → entra', 'paso',
  'delete from crm.actividades where id = ''b6c00000-0000-4000-8000-0000000000d1''');

-- ───────── L: levantar DE VERDAD (Supervisión y Gerencia) ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.err('L1 Supervisión levanta LA por la puerta (levantar_no_contactar)', 'paso', format('select crm.levantar_no_contactar(%L, %L)', (select la from f), 'volvió a pedir información'));
select pg_temp.caso('L2 la nota de levantar: accion levantar, rol supervisor, autor S1, motivo', (select format('levantar|supervisor|%s|volvió a pedir información', s1) from f), pg_temp.ultima((select la from f)));
select pg_temp.caso('L3 tras levantar, la válvula quedó apagada', 'off', coalesce(current_setting('crm.op_privilegiada', true), 'off'));
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('L4 tras levantar (misma transacción), V1 sigue sin poder escribir la nota → 42501', (select msg from f),
  pg_temp.nota((select la from f), (select v1 from f), '{"evento":"no_contactar","accion":"marcar","motivo":"tras levantar"}'));
select pg_temp.caso('L5 LA vuelve a la base de V1 sin marca', 'false|-|-|-|false', pg_temp.fila((select la from f), false));
select pg_temp.err('L6 V1 marca LG por la puerta', 'paso', format('select crm.marcar_no_contactar(%L, %L)', (select lg from f), 'para Gerencia'));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.err('L7 Gerencia levanta LG por la puerta', 'paso', format('select crm.levantar_no_contactar(%L, %L)', (select lg from f), 'Gerencia lo levanta'));
select pg_temp.caso('L8 la nota de Gerencia: levantar, rol gerencia, autor G; LG ya no está vetado', (select format('levantar|gerencia|%s|Gerencia lo levanta|false', g) from f),
  pg_temp.ultima((select lg from f)) || '|' || (select no_contactar::text from crm.leads, f where id = f.lg));
reset role;

-- ───────── R: persona (bandera encendida): enlace y puente ─────────
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('R1 V1 marca LP1 (persona P por enlace)', 'paso', format('select crm.marcar_no_contactar(%L, %L)', (select lp1 from f), 'P marca desde el enlace'));
reset role;
select pg_temp.caso('R1b la persona y sus dos leads quedan vetados', 'true|true|true',
  (select (select no_contactar::text from crm.inversionistas, f where id = f.pp) || '|' || string_agg(l.no_contactar::text, '|' order by l.id) from crm.leads l, f where l.id in (f.lp1, f.lp2)));
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.err('R2 Supervisión levanta desde LP2 (puente)', 'paso', format('select crm.levantar_no_contactar(%L, %L)', (select lp2 from f), 'levanta desde el puente'));
select pg_temp.caso('R2b la nota de levantar quedó en LP2 y los dos leads ya no están vetados', (select format('levantar|supervisor|%s|levanta desde el puente|false|false', s1) from f),
  pg_temp.ultima((select lp2 from f)) || '|' || (select string_agg(l.no_contactar::text, '|' order by l.id) from crm.leads l, f where l.id in (f.lp1, f.lp2)));
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('R3 V1 re-veta desde LP2', 'paso', format('select crm.marcar_no_contactar(%L, %L)', (select lp2 from f), 're-veta desde el puente'));
select pg_temp.err('R4 V1 intenta un «levantar» falso en LP1 (más reciente) → 42501', (select msg from f),
  pg_temp.nota((select lp1 from f), (select v1 from f), '{"evento":"no_contactar","accion":"levantar","motivo":"falso"}'));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('R5 Supervisión ve en LP1 la marca vigente de la persona (la de LP2)', (select format('true|*|re-veta desde el puente|%s|false', f.n_v1) from f), pg_temp.fila_sin_hora((select lp1 from f), true));
reset role;

-- ───────── Q: postventa (Gerencia) vetar y levantar ─────────
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.err('Q1 Gerencia veta a la persona Q por postventa', 'paso', format('select crm.postventa_veto_fn(gen_random_uuid(), %L, true, %L)', (select pq from f), 'cliente pidió solo correo'));
select pg_temp.caso('Q2 la postventa escribió su nota «marcar» en los dos leads de Q; la válvula quedó apagada', '1|1|off',
  (select pg_temp.notas_veto(f.lq1) || '|' || pg_temp.notas_veto(f.lq2) from f) || '|' || coalesce(current_setting('crm.op_privilegiada', true), 'off'));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('Q3 Supervisión ve en LQ1 el motivo de la postventa y su autor', (select format('true|*|cliente pidió solo correo|%s|false', f.n_g) from f), pg_temp.fila_sin_hora((select lq1 from f), true));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.err('Q4 Gerencia levanta el veto de Q por postventa', 'paso', format('select crm.postventa_veto_fn(gen_random_uuid(), %L, false, %L)', (select pq from f), 'volvió a aceptar llamadas'));
select pg_temp.caso('Q5 la postventa escribió su «levantar» en los dos leads; ya no están vetados; válvula apagada', 'levantar|levantar|false|false|off',
  (select split_part(pg_temp.ultima(f.lq1), '|', 1) || '|' || split_part(pg_temp.ultima(f.lq2), '|', 1) || '|' ||
          (select string_agg(l.no_contactar::text, '|' order by l.id) from crm.leads l where l.id in (f.lq1, f.lq2)) from f) || '|' || coalesce(current_setting('crm.op_privilegiada', true), 'off'));
reset role;

-- ───────── O: con la bandera APAGADA ─────────
select pg_temp.sesion(null);
update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('O1 con la bandera apagada, V1 marca LF por la puerta (también bajo la válvula)', 'paso', format('select crm.marcar_no_contactar(%L, %L)', (select lf from f), 'bandera apagada'));
select pg_temp.err('O2 con la bandera apagada, V1 tampoco escribe la nota por la API → 42501', (select msg from f),
  pg_temp.nota((select lf from f), (select v1 from f), '{"evento":"no_contactar","accion":"levantar","motivo":"falso"}'));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('O3 Supervisión ve la marca de LF', (select format('true|*|bandera apagada|%s|false', f.n_v1) from f), pg_temp.fila_sin_hora((select lf from f), true));
reset role;

-- ───────── Resultado ─────────
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 220)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B6c: hay casos FAIL'; end if; end $$;
rollback;
