-- B8 · Bases cargadas: cargar un archivo y armar bases desde el CRM (20261004184501), en el banco. UNA transacción con
-- impersonación (claims + set local role), statement_timeout de authenticated (8 s) y ROLLBACK al final. Falla el proceso si
-- hay un FAIL. Corre sobre un banco LOCAL con B7 y B8 aplicadas y los actores de seed:demo. Siembra leads b8000000-… y
-- teléfonos 96678xxxx, que se deshacen con el ROLLBACK. Mundo de PRODUCCIÓN: la bandera de identidad resolver_en_puertas
-- ENCENDIDA (sección Z: apagada).
-- Qué prueba:
--   A catálogo (EXECUTE solo authenticated en las puertas, núcleo cerrado, disparador nuevo, sello del descarte intacto, censo)
--     y la definición única de «nace dormido»;
--   B crear_base: roles (analista, coordinación, anon, service_role → 42501), supervisor solo para sí, Gerencia elige
--     supervisor activo (E11), nombre, origen, archivo, idempotencia (replay idéntico; mismo id con otro pedido → 22023);
--   C cargar_base_lote: ámbito (P0002), forma del lote, base retirada / de CRM / supervisor inactivo, tope por lote y de 5000;
--   D veredictos de un lote: cargada, invalida (cada motivo), repetida en el archivo (teléfono y DNI), ya_existia (con dueño
--     visible y ajeno, en bolsa, retirado, descartado < 24 h, convertido, enfriamiento, reutilizable, cliente por teléfono y
--     por DNI, persona con lead por identidad), no_contactar (lead y persona vetada); lead_id solo si el actor lo ve; sin datos
--     personales en la respuesta ni en el recibo;
--   E el contacto nace dormido (descartado, motivo y origen base_cargada, bandeja del supervisor, sin analista, descartado_en
--     = la carga, descartado_por = el actor, sin ciclo SLA ni episodio ni tenencia), la válvula queda apagada, no cuenta en
--     métricas de SLA, «Descartes del mes» ni llegadas; enlazado a su persona si existe;
--   F el alta, «tomar lead libre» y el alta por DNI posteriores NO duplican (enfriamiento → reutilizable);
--   G repetida en la base (segundo lote) e idempotencia del lote;
--   H armar_base_crm: roles, cada motivo de exclusión, el lead no se toca, idempotencia, sin elegibles no crea base, topes;
--   L regresión (alta normal con su ciclo SLA; nadie más nace terminal; reactivar un dormido con capital abre el ciclo 2);
--   Z con la bandera de identidad apagada (el mundo del banco), un lote carga y el alta posterior no duplica.
-- Mutantes: `node supabase/scripts/base-gestion/b8-mutantes.mjs --puerto <puerto>` inyecta cada uno en @@MUTANTE@@.
-- Concurrencia (dos sesiones): supabase/scripts/base-gestion/b8-concurrencia.sh (aparte: una transacción no la prueba).
\set ON_ERROR_STOP on
do $solo_banco_local$
begin
  if (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646'
      and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid())) is not true then
    raise exception 'b8-cargar: solo corre en un banco LOCAL de Docker (Supabase CLI); esta base no lo es';
  end if;
end $solo_banco_local$;
begin;
set local statement_timeout = '8s';
-- @@MUTANTE@@

-- ───────── Utilidades (pg_temp: se van con el ROLLBACK) ─────────
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
create function pg_temp.sesion(p uuid, p_rol text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), true),
         set_config('request.jwt.claims', case when p is null and p_rol = 'authenticated' then ''
                                               else json_build_object('sub', p, 'role', p_rol)::text end, true);
$$;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
-- prueba: ejecuta p_sql como p_rol/p_uid y lo DESHACE; anota «paso» o «<sqlstate> <mensaje>».
create function pg_temp.prueba(p_caso text, p_esperado text, p_sql text, p_rol text default null, p_uid uuid default null,
                               p_valvula boolean default false) returns void language plpgsql as $$
declare v text;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol = 'service_role' then 'service_role' else 'authenticated' end);
    if p_valvula then perform set_config('crm.op_bases_carga', 'on', true); end if;
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql;
    v := 'paso';
    raise exception using errcode = 'P0001', message = 'B8_DESHACER';
  exception when others then
    if v is null then v := sqlstate || ' ' || sqlerrm; end if;
  end;
  perform pg_temp.caso(p_caso, p_esperado, v);
end $$;
-- valor: primer valor de p_sql (como p_rol/p_uid) o «ERROR <sqlstate> <mensaje>»; deshace todo.
create function pg_temp.valor(p_sql text, p_rol text default null, p_uid uuid default null) returns text language plpgsql as $$
declare v text; v_ok boolean := false;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol = 'service_role' then 'service_role' else 'authenticated' end);
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql into v;
    v_ok := true;
    raise exception using errcode = 'P0001', message = 'B8_DESHACER';
  exception when others then
    if not v_ok then v := 'ERROR ' || sqlstate || ' ' || sqlerrm; end if;
  end;
  return coalesce(v, '(nulo)');
end $$;
-- ejecutar: corre p_sql como authenticated con el usuario p_uid y CONSERVA su efecto (dentro de la transacción de la suite).
-- Si p_sql falla, devuelve {"error": "<sqlstate> <mensaje>"} (deshace lo suyo) y la suite sigue: los casos que dependen de
-- ese resultado caen con su nombre (un mutante no aborta la suite sin decir dónde).
create function pg_temp.ejecutar(p_sql text, p_uid uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  begin
    perform pg_temp.sesion(p_uid);
    execute 'set local role authenticated';
    execute p_sql into v;
    execute 'reset role';
  exception when others then
    v := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  perform pg_temp.sesion(null);
  return v;
end $$;
-- detalle: «<sqlstate>|<detail>» del error de p_sql, o «paso»; deshace todo.
create function pg_temp.detalle(p_sql text, p_rol text default null, p_uid uuid default null) returns text language plpgsql as $$
declare v text; v_det text;
begin
  begin
    perform pg_temp.sesion(p_uid);
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql;
    v := 'paso';
    raise exception using errcode = 'P0001', message = 'B8_DESHACER';
  exception when others then
    if v is null then get stacked diagnostics v_det = pg_exception_detail; v := sqlstate || '|' || coalesce(nullif(v_det, ''), '(sin detail)'); end if;
  end;
  return v;
end $$;
-- a_jsonb: el texto como jsonb, o {"error": texto} si no lo es (un «ERROR …» de valor() hace caer el caso, no la suite).
create function pg_temp.a_jsonb(p text) returns jsonb language plpgsql as $$
begin
  return p::jsonb;
exception when others then
  return jsonb_build_object('error', p);
end $$;
-- lista: el jsonb si es una lista; si no (un error), la lista vacía.
create function pg_temp.lista(p jsonb) returns jsonb language sql as $$
  select case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end $$;
-- veredictos: «fila:veredicto[/motivo][+id]» de una respuesta de cargar_base_lote, en orden de fila.
create function pg_temp.veredictos(p jsonb) returns text language sql as $$
  select string_agg((x->>'fila') || ':' || (x->>'veredicto') || coalesce('/' || (x->>'motivo'), '') || case when x ? 'lead_id' then '+id' else '' end,
                    ',' order by (x->>'fila')::int)
    from jsonb_array_elements(p->'filas') x $$;
-- Andamio (solo en esta transacción): fechar el descarte de un lead sin pasar por el sello del descarte.
create function pg_temp.fechar_descarte(p_lead uuid, p_dias integer) returns void language plpgsql as $$
begin
  alter table crm.leads disable trigger trg_leads_zz_sello_descarte;
  update crm.leads set descartado_en = now() - make_interval(days => p_dias) where id = p_lead;
  alter table crm.leads enable trigger trg_leads_zz_sello_descarte;
end $$;
create function pg_temp.huella_sello() returns text language sql set search_path = '' as $$
  select md5(pg_get_functiondef('private.trg_leads_zz_sello_descarte()'::regprocedure)) $$;
create function pg_temp.dormido_con_valvula() returns text language plpgsql as $$
begin
  perform set_config('crm.op_bases_carga', 'on', true);
  return concat_ws('|', private.bases_carga_nace_dormido('base_cargada', 'descartado', 'base_cargada', true)::text,
                        private.bases_carga_nace_dormido('oficina', 'descartado', 'base_cargada', true)::text,
                        private.bases_carga_nace_dormido('base_cargada', 'nuevo', 'base_cargada', true)::text,
                        private.bases_carga_nace_dormido('base_cargada', 'descartado', 'no_responde', true)::text,
                        private.bases_carga_nace_dormido('base_cargada', 'descartado', 'base_cargada', false)::text,
                        private.bases_carga_nace_dormido('base_cargada', 'descartado', 'base_cargada', null)::text);
end $$;
-- alta_tras_vencer: vence el enfriamiento del lead (andamio, como postgres) y prueba el alta de su teléfono como p_uid.
create function pg_temp.alta_tras_vencer(p_lead uuid, p_tel text, p_uid uuid) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.fechar_descarte(p_lead, 40);
  perform pg_temp.sesion(p_uid);
  execute 'set local role authenticated';
  v := crm.crear_lead_si_disponible('Otro', p_tel, 'oficina', 1000, 'PEN')->>'estado';
  execute 'reset role';
  return v || '|' || (select count(*) from crm.leads where telefono = private.normalizar_telefono(p_tel));
end $$;
-- nace_nuevo_con_valvula: un base_cargada NUEVO (con capital) bajo la válvula, sin usuario: ¿ciclo SLA? ¿fecha de descarte?
-- Lleva motivo_descarte base_cargada a propósito: así solo la ETAPA lo separa de «nace dormido» (aísla esa condición).
create function pg_temp.alta_normal(p_uid uuid) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.sesion(p_uid);
  execute 'set local role authenticated';
  v := crm.crear_lead_si_disponible('B8 Normal', '966780301', 'oficina', 1000, 'PEN')->>'estado';
  execute 'reset role';
  return v || '|' || (select count(*) from crm.lead_sla_ciclos c join crm.leads l on l.id = c.lead_id where l.telefono = '+51966780301')
           || '|' || (select count(*) from crm.lead_sla_etapas e join crm.leads l on l.id = e.lead_id where l.telefono = '+51966780301' and e.finalizado_en is null);
end $$;
create function pg_temp.reactivar(p_lead uuid, p_uid uuid) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.sesion(p_uid);
  execute 'set local role authenticated';
  v := crm.reactivar_lead_base(gen_random_uuid(), p_lead)->>'etapa';
  execute 'reset role';
  return v || '|' || (select ciclo_actual from crm.leads where id = p_lead)
           || '|' || (select string_agg(ciclo_n::text, ',' order by ciclo_n) from crm.lead_sla_ciclos where lead_id = p_lead);
end $$;
-- metricas_con_carga: métricas de SLA de Gerencia de hoy ANTES y DESPUÉS de cargar un lote nuevo (misma transacción).
create function pg_temp.metricas_con_carga(p_g uuid, p_s1 uuid, p_base uuid) returns text language plpgsql as $$
declare m1 jsonb; m2 jsonb; v jsonb;
begin
  perform pg_temp.sesion(p_g); execute 'set local role authenticated';
  m1 := crm.metricas_sla_fn((now() at time zone 'America/Lima')::date, (now() at time zone 'America/Lima')::date);  -- día de Lima: con current_date (UTC) falla de 19:00 a 24:00 Lima
  execute 'reset role';
  perform pg_temp.sesion(p_s1); execute 'set local role authenticated';
  v := crm.cargar_base_lote(gen_random_uuid(), p_base, '[{"fila":1,"nombre":"M uno","telefono":"966780501"},{"fila":2,"nombre":"M dos","telefono":"966780502"}]'::jsonb);
  execute 'reset role';
  perform pg_temp.sesion(p_g); execute 'set local role authenticated';
  m2 := crm.metricas_sla_fn((now() at time zone 'America/Lima')::date, (now() at time zone 'America/Lima')::date);  -- día de Lima: con current_date (UTC) falla de 19:00 a 24:00 Lima
  execute 'reset role';
  return (v->'lote'->>'cargadas') || '|' || (m1 = m2)::text;
end $$;
-- lote_tras: prepara el mundo como postgres (p_preparar), carga un lote como p_uid y devuelve sus veredictos (valor() lo deshace).
create function pg_temp.lote_tras(p_preparar text, p_uid uuid, p_base uuid, p_filas text) returns text language plpgsql as $$
declare v jsonb;
begin
  execute p_preparar;
  perform pg_temp.sesion(p_uid);
  execute 'set local role authenticated';
  v := crm.cargar_base_lote(gen_random_uuid(), p_base, p_filas::jsonb);
  execute 'reset role';
  return pg_temp.veredictos(v);
end $$;
-- lote_con_falla: simula la CARRERA del INSERT (un disparador de prueba rechaza el teléfono 966780601 con p_codigo y un detail
-- con datos de otro equipo) y carga ese teléfono y otro libre como p_uid. Devuelve «veredictos|¿la respuesta filtra el detail?».
create function pg_temp.lote_con_falla(p_codigo text, p_uid uuid, p_base uuid) returns text language plpgsql as $$
declare v jsonb;
begin
  execute format('create function private.b8_prueba_falla() returns trigger language plpgsql as %s', quote_literal(format(
    'begin if new.telefono = %L then raise exception using errcode = %L, message = %L, detail = %L; end if; return new; end',
    '+51966780601', p_codigo, 'Contacto no disponible', '{"vendedor": "ANALISTA AJENO SECRETO", "lead_id": "00000000-0000-4000-8000-00000000dead"}')));
  create trigger zz_b8_prueba_falla before insert on crm.leads for each row execute function private.b8_prueba_falla();
  perform pg_temp.sesion(p_uid);
  execute 'set local role authenticated';
  v := crm.cargar_base_lote(gen_random_uuid(), p_base, '[{"fila": 1, "nombre": "T uno", "telefono": "966780601"}, {"fila": 2, "nombre": "T dos", "telefono": "966780602"}]'::jsonb);
  execute 'reset role';
  return pg_temp.veredictos(v) || '|' || (v::text ~ 'SECRETO|00000000-0000-4000-8000-00000000dead')::text;
end $$;
-- lote_falla_n (r2): una tanda de p_n filas nuevas (teléfonos 96681nnnn) donde un disparador de prueba rechaza la fila
-- p_falla con p_codigo. Devuelve «cargadas|ya_existia|leads con esos teléfonos|pertenencias|resultado», o el error (y los
-- residuos) si la carga aborta; avisa la duración.
create function pg_temp.lote_falla_n(p_codigo text, p_uid uuid, p_base uuid, p_n integer, p_falla integer) returns text language plpgsql as $$
declare v jsonb; t0 timestamptz; r text := 'ok'; v_det text;
begin
  create temp sequence if not exists intentos_falla;
  perform setval('intentos_falla', 1, false);
  -- La secuencia NO se deshace con la subtransacción: cuenta cuántas veces se intentó insertar la fila que falla.
  execute format('create function private.b8_prueba_falla_n() returns trigger language plpgsql as %s', quote_literal(format(
    'begin if new.telefono = %L then perform nextval(''pg_temp.intentos_falla''); raise exception using errcode = %L, message = %L, detail = %L; end if; return new; end',
    '+5196681' || lpad(p_falla::text, 4, '0'), p_codigo, 'Rechazo de prueba', '{"vendedor": "ANALISTA AJENO SECRETO"}')));
  create trigger zz_b8_prueba_falla_n before insert on crm.leads for each row execute function private.b8_prueba_falla_n();
  t0 := clock_timestamp();
  begin
    perform pg_temp.sesion(p_uid);
    execute 'set local role authenticated';
    v := crm.cargar_base_lote(gen_random_uuid(), p_base,
           (select jsonb_agg(jsonb_build_object('fila', i, 'nombre', 'N ' || i, 'telefono', '96681' || lpad(i::text, 4, '0')) order by i) from generate_series(1, p_n) i));
    execute 'reset role';
  exception when others then
    get stacked diagnostics v_det = pg_exception_detail;
    r := sqlstate || ' ' || sqlerrm || coalesce(' DETAIL ' || nullif(v_det, ''), '');
  end;
  raise notice 'B8 lote_falla_n(%, %, fila %): % ms', p_codigo, p_n, p_falla, round(extract(epoch from clock_timestamp() - t0) * 1000);
  return coalesce((v->'lote'->>'cargadas') || '|' || (v->'lote'->>'ya_existian'), '-|-')
      || '|intentos ' || (select case when is_called then last_value else 0 end from pg_temp.intentos_falla)
      || '|' || (select count(*) from crm.leads where telefono like '+5196681%')
      || '|' || (select count(*) from crm.base_carga_leads bl join crm.leads l on l.id = bl.lead_id where l.telefono like '+5196681%')
      || '|' || r || '|' || coalesce((v::text ~ 'SECRETO')::text, 'false');
end $$;
-- respaldo_p0429_fuera (r2, caja blanca): el respaldo fila a fila juzga un P0429 con la MISMA regla del ámbito. Bajo los candados
-- de contacto un lead que coincida no puede aparecer entre el veredicto y el INSERT; para ver la rama, el ayudante del ámbito se
-- instrumenta (solo en esta transacción): dice «dentro» en el veredicto y «fuera» en el respaldo para el teléfono 966780611.
create function pg_temp.respaldo_p0429_fuera(p_uid uuid, p_base uuid) returns text language plpgsql as $$
declare v jsonb;
begin
  create temp table if not exists contador_fuera (n integer);
  delete from contador_fuera; insert into contador_fuera values (0);
  create or replace function private.bases_carga_fuera_de_ambito(p_actor uuid, p_rol text, p_telefono text, p_dni text)
  returns boolean language plpgsql set search_path = '' as $f$
  begin
    if p_telefono = '+51966780611' then
      update pg_temp.contador_fuera set n = n + 1;
      return (select c.n from pg_temp.contador_fuera c) > 1;
    end if;
    return false;
  end $f$;
  create function private.b8_prueba_veto() returns trigger language plpgsql as $f$
  begin
    if new.telefono = '+51966780611' then
      raise exception using errcode = 'P0429', message = 'veto de prueba', detail = '{"estado": "no_contactar"}';
    end if;
    return new;
  end $f$;
  create trigger zz_b8_prueba_veto before insert on crm.leads for each row execute function private.b8_prueba_veto();
  perform pg_temp.sesion(p_uid);
  execute 'set local role authenticated';
  v := crm.cargar_base_lote(gen_random_uuid(), p_base, '[{"fila": 1, "nombre": "V uno", "telefono": "966780611"}, {"fila": 2, "nombre": "V dos", "telefono": "966780612"}]'::jsonb);
  execute 'reset role';
  return pg_temp.veredictos(v);
end $$;
create function pg_temp.nace_nuevo_con_valvula(p_sup uuid) returns text language plpgsql as $$
begin
  perform set_config('crm.op_bases_carga', 'on', true);
  insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte, monto_estimado, moneda, asignado_supervisor_id, creado_por)
  values ('b8000000-0000-4000-8000-0000000000aa', 'X', '966780306', 'base_cargada', 'nuevo', 'base_cargada', 1000, 'PEN', p_sup, p_sup);
  perform set_config('crm.op_bases_carga', 'off', true);
  return (select count(*) from crm.lead_sla_ciclos where lead_id = 'b8000000-0000-4000-8000-0000000000aa') || '|'
      || (select (descartado_en is not null)::text from crm.leads where id = 'b8000000-0000-4000-8000-0000000000aa');
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
  -- Leads sembrados para los veredictos (teléfonos 96678xxxx).
  'b8000000-0000-4000-8000-000000000001'::uuid l_v1,      -- vivo de V1 (equipo de S1): con_dueno, visible para S1
  'b8000000-0000-4000-8000-000000000002'::uuid l_v3,      -- vivo de V3 (equipo de S2): con_dueno, NO visible para S1
  'b8000000-0000-4000-8000-000000000003'::uuid l_bolsa,   -- vivo sin dueño (cola global): en_bolsa
  'b8000000-0000-4000-8000-000000000004'::uuid l_ret,     -- retirado (activo = false): el verificador dice «libre»
  'b8000000-0000-4000-8000-000000000005'::uuid l_d24,     -- descartado datos_invalidos hace 2 h (0 días): «libre» 24 h
  'b8000000-0000-4000-8000-000000000006'::uuid l_conv,    -- convertido: el verificador dice «libre»
  'b8000000-0000-4000-8000-000000000007'::uuid l_enf,     -- descartado sin_interes reciente: enfriamiento
  'b8000000-0000-4000-8000-000000000008'::uuid l_reu,     -- descartado sin_interes hace 40 días: reutilizable
  'b8000000-0000-4000-8000-000000000009'::uuid l_noc,     -- vivo marcado No contactar (DNI 47800009)
  'b8000000-0000-4000-8000-00000000000a'::uuid l_dni,     -- vivo de V1 con DNI 47800010 (otro teléfono en el archivo)
  'b8000000-0000-4000-8000-00000000000b'::uuid l_noc3,    -- vivo de V3 (otro equipo) marcado No contactar
  'b8000000-0000-4000-8000-00000000000c'::uuid l_desc3,   -- descartado de V3 (otro equipo), DNI 47800012
  'b8000000-0000-4000-8000-00000000000d'::uuid l_v1b,     -- vivo de V1 (su teléfono + el DNI de l_desc3 en una fila)
  '4a29ae67-6d5b-456d-a942-beebfbf01b5a'::uuid p_vet,     -- persona sin lead (DNI 78427011): se veta en la siembra
  '0c1b22e4-815a-447a-bdb5-fafbd43af391'::uuid p_libre,   -- persona sin lead ni perfil (DNI 78258291): el contacto se enlaza
  '42501 Solo Supervisión y Gerencia cargan y arman bases'::text m_rol,
  'P0002 Base no encontrada o fuera de tu ámbito'::text m_ambito;
grant select on f to anon, authenticated, service_role;
do $$ begin
  if (select v1 is null or v2 is null or v3 is null or s1 is null or s2 is null or sa is null or g is null or co is null from f) then
    raise exception 'b8-cargar: faltan actores de seed:demo en este banco (correr el gate o seed:demo antes)';
  end if;
  if to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is null or to_regclass('crm.bases_carga') is null then
    raise exception 'b8-cargar: B7 y B8 (20261004184501) no están aplicadas en este banco';
  end if;
  if exists (select 1 from crm.leads where id::text like 'b8000000-%' or telefono like '+5196678%') or exists (select 1 from crm.bases_carga) then
    raise exception 'b8-cargar: ya hay leads b8000000-…/96678xxxx o bases en el banco';
  end if;
  if not exists (select 1 from crm.inversionista_identificadores where inversionista_id = (select p_vet from f) and documento_normalizado = '78427011' and verificado and estado = 'vigente')
     or not exists (select 1 from crm.inversionista_identificadores where inversionista_id = (select p_libre from f) and documento_normalizado = '78258291' and verificado and estado = 'vigente')
     or not exists (select 1 from public.perfiles where rol = 'cliente' and activo and telefono = '999888777')
     or not exists (select 1 from public.perfiles where rol = 'cliente' and activo and dni = '74447002')
     or not exists (select 1 from crm.leads where dni = '99887761') then
    raise exception 'b8-cargar: faltan los datos de identidad de seed:demo que usa la suite';
  end if;
end $$;

-- Mundo de producción: la identidad unificada ENCENDIDA (la sección Z la apaga).
update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';

-- ───────── Siembra (postgres sin usuario) ─────────
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, x.dni, 'oficina', 'nuevo', x.v, 1000, 'PEN', coalesce(x.v, (select g from f)), true
  from f, lateral (values (f.l_v1, 'B8 VIVO V1', '966780001', null::text, f.v1), (f.l_v3, 'B8 VIVO V3', '966780002', null, f.v3),
                          (f.l_bolsa, 'B8 BOLSA', '966780003', null, null::uuid), (f.l_ret, 'B8 RETIRADO', '966780004', null, f.v1),
                          (f.l_d24, 'B8 DESC 24H', '966780005', null, f.v1),
                          (f.l_enf, 'B8 ENFRIAMIENTO', '966780007', null, f.v1), (f.l_reu, 'B8 REUTILIZABLE', '966780008', null, f.v1),
                          (f.l_noc, 'B8 NO CONTACTAR', '966780009', '47800009', f.v1), (f.l_dni, 'B8 CON DNI', '966780010', '47800010', f.v1),
                          (f.l_noc3, 'B8 NO CONTACTAR V3', '966780011', null, f.v3), (f.l_desc3, 'B8 DESCARTADO V3', '966780012', '47800012', f.v3),
                          (f.l_v1b, 'B8 VIVO V1 B', '966780013', null, f.v1)) x(id, nombre, tel, dni, v);
update crm.leads set activo = false where id = (select l_ret from f);
update crm.leads set etapa = 'descartado', motivo_descarte = 'datos_invalidos' where id = (select l_d24 from f);
update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where id in ((select l_enf from f), (select l_reu from f), (select l_desc3 from f));
select pg_temp.fechar_descarte((select l_d24 from f), 0);
select pg_temp.fechar_descarte((select l_enf from f), 3);
select pg_temp.fechar_descarte((select l_reu from f), 40);
-- convertido: nace convertido bajo crm.op_privilegiada (sin usuario), como los históricos (convertir por UPDATE exige su inversión)
select set_config('crm.op_privilegiada', 'on', true);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo, convertido_en)
select f.l_conv, 'B8 CONVERTIDO', '966780006', 'oficina', 'convertido', f.v1, 1000, 'PEN', f.v1, true, now() from f;
update crm.leads set no_contactar = true where id in ((select l_noc from f), (select l_noc3 from f));
select set_config('crm.op_privilegiada', 'off', true);
update crm.inversionistas set no_contactar = true, no_contactar_en = now(), no_contactar_por = (select s1 from f) where id = (select p_vet from f);
do $$ begin
  if (select string_agg(etapa || '/' || activo::text || '/' || no_contactar::text, ',' order by id) from crm.leads where id::text like 'b8000000-%')
     is distinct from 'nuevo/true/false,nuevo/true/false,nuevo/true/false,nuevo/false/false,descartado/true/false,convertido/true/false,descartado/true/false,descartado/true/false,nuevo/true/true,nuevo/true/false,nuevo/true/true,descartado/true/false,nuevo/true/false' then
    raise exception 'b8-cargar: la siembra no quedó como se esperaba: %', (select string_agg(etapa || '/' || activo::text || '/' || no_contactar::text, ',' order by id) from crm.leads where id::text like 'b8000000-%');
  end if;
end $$;

-- ───────── A · Catálogo y definición única de «nace dormido» ─────────
select pg_temp.caso('A1 las 3 puertas: DEFINER de postgres, search_path vacío, EXECUTE solo authenticated (ni anon, ni service_role, ni PUBLIC)', '3',
  (select count(*)::text from pg_proc p where p.oid in ('crm.crear_base(uuid,text,text,uuid,text)'::regprocedure, 'crm.cargar_base_lote(uuid,uuid,jsonb)'::regprocedure, 'crm.armar_base_crm(uuid,text,uuid,uuid[])'::regprocedure)
     and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']
     and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
     and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)));
select pg_temp.caso('A2 el núcleo (17 funciones bases_carga_* de B8 y la del disparador) sin EXECUTE para la API', '0',
  (select count(*)::text from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) x(rol)
    where p.pronamespace = 'private'::regnamespace and (p.proname like 'bases\_carga\_%' or p.proname = 'trg_leads_sello_descarte_base_cargada')
      and has_function_privilege(x.rol, p.oid, 'EXECUTE')));
select pg_temp.caso('A3 disparador de la fecha: BEFORE INSERT por fila con WHEN origen base_cargada, habilitado', 'true',
  (select (count(*) = 1)::text from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_descarte_base_cargada'
     and t.tgenabled = 'O' and t.tgtype = 7 and t.tgqual is not null));
select pg_temp.caso('A4 el sello del descarte conserva la huella que sella assert_gestion_diaria_resultado', '150d7ae56bb2094733f7620a1362c29e',
  pg_temp.valor('select pg_temp.huella_sello()'));
select pg_temp.caso('A5 ninguna función de B8 entra al censo analítico', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c where c.objeto ~ 'bases_carga|cargar_base_lote|armar_base_crm|crear_base|sello_descarte_base_cargada'));
select pg_temp.caso('A6 assert_gestion_diaria_resultado pasa con B8', 'OK',
  left(pg_temp.valor('select private.assert_gestion_diaria_resultado()'), 2));
select pg_temp.caso('A7 «nace dormido» sin la válvula → false', 'false',
  (select private.bases_carga_nace_dormido('base_cargada', 'descartado', 'base_cargada', true)::text));
select pg_temp.caso('A8 «nace dormido» con la válvula: sí solo con origen, etapa y motivo base_cargada/descartado y activo', 'true|false|false|false|false|false',
  pg_temp.valor('select pg_temp.dormido_con_valvula()'));
select pg_temp.caso('A9 topes: 5000 por base, 2000 al armar; el de lote entre 1 y 1000', '5000|2000|true',
  (select format('%s|%s|%s', k.max_filas_base, k.max_leads_armar, (k.max_filas_lote between 1 and 1000)::text) from private.bases_carga_constantes() k));

-- ───────── B · crear_base ─────────
select pg_temp.prueba('B1 anon → 42501 (sin EXECUTE)', '42501 permission denied for schema crm',
  'select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', null, ''x.csv'')', 'anon');
select pg_temp.prueba('B2 service_role → 42501 (sin EXECUTE)', '42501 permission denied for function crear_base',
  'select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', null, ''x.csv'')', 'service_role');
select pg_temp.prueba('B3 el analista → 42501', (select m_rol from f),
  'select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', null, ''x.csv'')', 'authenticated', (select v1 from f));
select pg_temp.prueba('B4 Coordinación → 42501', (select m_rol from f),
  'select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', null, ''x.csv'')', 'authenticated', (select co from f));
select pg_temp.prueba('B5 un supervisor no crea la base de OTRO supervisor → 42501', '42501 Un supervisor solo crea bases para su propia bandeja',
  format('select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', %L, ''x.csv'')', (select s2 from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('B6 Gerencia sin supervisor → 22023', '22023 Gerencia debe elegir el supervisor dueño de la base',
  'select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', null, ''x.csv'')', 'authenticated', (select g from f));
select pg_temp.prueba('B7 Gerencia con un analista como supervisor → 22023', '22023 El supervisor elegido no existe, no está activo o no es supervisor',
  format('select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', %L, ''x.csv'')', (select v1 from f)), 'authenticated', (select g from f));
select pg_temp.prueba('B8 nombre vacío → 22023', '22023 El nombre de la base debe tener entre 1 y 80 caracteres',
  'select crm.crear_base(gen_random_uuid(), ''   '', ''archivo'', null, ''x.csv'')', 'authenticated', (select s1 from f));
select pg_temp.prueba('B9 nombre de 81 caracteres → 22023', '22023 El nombre de la base debe tener entre 1 y 80 caracteres',
  format('select crm.crear_base(gen_random_uuid(), %L, ''archivo'', null, ''x.csv'')', repeat('n', 81)), 'authenticated', (select s1 from f));
select pg_temp.prueba('B10 origen crm por esta puerta → 22023', '22023 Por esta puerta se crea una base de origen archivo; la que se arma desde el CRM la crea armar_base_crm',
  'select crm.crear_base(gen_random_uuid(), ''X'', ''crm'', null, null)', 'authenticated', (select s1 from f));
select pg_temp.prueba('B11 sin nombre de archivo → 22023', '22023 El nombre del archivo es obligatorio (1 a 255 caracteres)',
  'select crm.crear_base(gen_random_uuid(), ''X'', ''archivo'', null, ''  '')', 'authenticated', (select s1 from f));
select pg_temp.prueba('B12 sin id de operación → 22023', '22023 El identificador de la operación es obligatorio',
  'select crm.crear_base(null, ''X'', ''archivo'', null, ''x.csv'')', 'authenticated', (select s1 from f));
-- Las bases de la suite (se conservan dentro de la transacción).
alter table f add column bs1 jsonb, add column bs1b jsonb, add column bs2g jsonb, add column bsa jsonb;
update f set bs1 = pg_temp.ejecutar('select crm.crear_base(''b8000000-0000-4000-8000-0000000000c1'', ''  Feria 2025  '', ''archivo'', null, ''feria.xlsx'')', f.s1);
update f set bs2g = pg_temp.ejecutar(format('select crm.crear_base(''b8000000-0000-4000-8000-0000000000c2'', ''Feria 2025'', ''archivo'', %L, ''feria-s2.csv'')', f.s2), f.g);
update f set bsa = pg_temp.ejecutar('select crm.crear_base(''b8000000-0000-4000-8000-0000000000c3'', ''Anidada'', ''archivo'', null, ''anidada.csv'')', f.sa);
select pg_temp.caso('B13 Supervisión crea su base: dueño él, origen archivo, nombre sin espacios al borde, creada por él', 'true',
  (select (b.supervisor_id = f.s1 and b.creada_por = f.s1 and b.origen = 'archivo' and b.nombre = 'Feria 2025' and b.archivo_nombre = 'feria.xlsx'
           and b.activo and b.filas_recibidas = 0 and (f.bs1->>'supervisor_id')::uuid = f.s1 and f.bs1->>'origen' = 'archivo' and (f.bs1->>'ok')::boolean)::text
     from f join crm.bases_carga b on b.id = (f.bs1->>'base_id')::uuid));
select pg_temp.caso('B14 Gerencia crea la base de S2 (E11): dueño S2, creada por Gerencia; el mismo nombre en otra bandeja vale', 'true',
  (select (b.supervisor_id = f.s2 and b.creada_por = f.g)::text from f join crm.bases_carga b on b.id = (f.bs2g->>'base_id')::uuid));
select pg_temp.prueba('B15 el mismo nombre (otras mayúsculas) en la misma bandeja viva → 23505', '23505 Ya hay una base viva con ese nombre en la bandeja de ese supervisor',
  'select crm.crear_base(gen_random_uuid(), ''FERIA 2025'', ''archivo'', null, ''y.csv'')', 'authenticated', (select s1 from f));
select pg_temp.caso('B16 replay (mismo id, mismo pedido) → la MISMA respuesta y ninguna base nueva', 'true|1',
  (select format('%s|%s', (pg_temp.ejecutar('select crm.crear_base(''b8000000-0000-4000-8000-0000000000c1'', ''Feria 2025'', ''archivo'', null, ''feria.xlsx'')', f.s1) = f.bs1)::text,
                 (select count(*) from crm.bases_carga where operacion_id = 'b8000000-0000-4000-8000-0000000000c1'))
     from f));
select pg_temp.prueba('B17 mismo id de operación con otro pedido → 22023', '22023 Este identificador de operación ya se usó con un pedido distinto',
  'select crm.crear_base(''b8000000-0000-4000-8000-0000000000c1'', ''Otra'', ''archivo'', null, ''feria.xlsx'')', 'authenticated', (select s1 from f));
select pg_temp.prueba('B18 el id de operación de una base de OTRO actor → 23505 (único por base)', '23505 Este identificador de operación ya se usó para otra base',
  'select crm.crear_base(''b8000000-0000-4000-8000-0000000000c1'', ''De S2'', ''archivo'', null, ''s2.csv'')', 'authenticated', (select s2 from f));
select pg_temp.caso('B19 recibo crear: actor, tipo, md5 y la respuesta exacta', 'true',
  (select (o.tipo = 'crear' and o.actor = f.s1 and o.respuesta = f.bs1 and o.base_id = (f.bs1->>'base_id')::uuid and o.pedido_md5 ~ '^[0-9a-f]{32}$')::text
     from f join crm.base_carga_operaciones o on o.operacion_id = 'b8000000-0000-4000-8000-0000000000c1' and o.actor = f.s1));

-- ───────── C · cargar_base_lote: ámbito, forma y topes ─────────
create function pg_temp.lote(p_op text, p_base uuid, p_filas text) returns text language sql as $$
  select format('select crm.cargar_base_lote(%L, %L, %L::jsonb)', p_op, p_base, p_filas) $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
select pg_temp.prueba('C1 el analista → 42501', (select m_rol from f),
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select v1 from f));
select pg_temp.prueba('C2 S2 en la base de S1 → P0002', (select m_ambito from f),
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s2 from f));
select pg_temp.prueba('C3 el supervisor anidado (bajo S1) en la base de S1 → P0002', (select m_ambito from f),
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select sa from f));
select pg_temp.prueba('C4 una base que no existe → P0002', (select m_ambito from f),
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', gen_random_uuid(), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C5 S1 carga en la base de su supervisor anidado (subárbol) → entra', 'paso',
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bsa->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C6 Gerencia carga en la base de S1 → entra', 'paso',
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select g from f));
select pg_temp.prueba('C7 filas que no son una lista → 22023', '22023 Las filas llegan como una lista JSON',
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '{"fila":1}'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C8 lista vacía → 22023', (select format('22023 Un lote trae entre 1 y %s filas (este trae 0)', max_filas_lote) from private.bases_carga_constantes()),
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C9 un lote por encima del tope → 22023',
  (select format('22023 Un lote trae entre 1 y %s filas (este trae %s)', max_filas_lote, max_filas_lote + 1) from private.bases_carga_constantes()),
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f),
               (select jsonb_agg(jsonb_build_object('fila', i, 'nombre', 'X', 'telefono', '9667' || lpad(i::text, 5, '0')))::text
                  from generate_series(1, (select max_filas_lote + 1 from private.bases_carga_constantes())) i)), 'authenticated', (select s1 from f));
select pg_temp.prueba('C10 una fila sin número de fila → 22023', '22023 Cada fila es un objeto con su número de fila (entero positivo); la posición 2 no lo es',
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"},{"nombre":"Y","telefono":"966780098"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C11 número de fila repetido → 22023', '22023 El número de fila 1 se repite en el lote',
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"},{"fila":1,"nombre":"Y","telefono":"966780098"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C12 base retirada → 22023', '22023 La base está retirada: no admite más filas',
  format('reset role; update crm.bases_carga set activo = false where id = %L; set local role authenticated; ', (select (bsa->>'base_id')::uuid from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bsa->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C13 base de origen crm → 22023', '22023 Solo una base de origen archivo recibe filas de un archivo',
  format('reset role; update crm.bases_carga set origen = ''crm'', archivo_nombre = null where id = %L; set local role authenticated; ', (select (bsa->>'base_id')::uuid from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bsa->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C14 el dueño de la base ya no es un supervisor activo → 22023', '22023 El supervisor dueño de la base ya no está activo: no se le pueden cargar contactos',
  format('reset role; update crm.bases_carga set supervisor_id = %L where id = %L; set local role authenticated; ', (select v1 from f), (select (bs2g->>'base_id')::uuid from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs2g->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select g from f));
select pg_temp.prueba('C15 la base con 4999 filas recibe un lote de 2 → 22023 (E5: 5000)', '22023 Una base recibe hasta 5000 filas: ya tiene 4999 y este lote trae 2',
  format('reset role; update crm.bases_carga set filas_recibidas = 4999 where id = %L; set local role authenticated; ', (select (bs1->>'base_id')::uuid from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"},{"fila":2,"nombre":"Y","telefono":"966780098"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('C16 … y un lote de 1 llega justo a 5000 → entra', 'paso',
  format('reset role; update crm.bases_carga set filas_recibidas = 4999 where id = %L; set local role authenticated; ', (select (bs1->>'base_id')::uuid from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s1 from f));

-- ───────── D · Veredictos de un lote (S1 en su base) ─────────
alter table f add column lote1 jsonb, add column req1 text;
update f set req1 = ($j$[
  {"fila": 2, "nombre": "  Ana Base Uno ", "telefono": "966 780 101", "dni": "47800101", "distrito": " Lince ", "comentario": "llamar de tarde", "capital": "1500.50", "moneda": "usd"},
  {"fila": 3, "nombre": "Beto Sin Capital", "telefono": "+51 966-780-102"},
  {"fila": 4, "nombre": "   ", "telefono": "966780103"},
  {"fila": 5, "nombre": "Tel Malo", "telefono": "12345"},
  {"fila": 6, "nombre": "Fijo", "telefono": "014457890"},
  {"fila": 7, "nombre": "Dni Malo", "telefono": "966780107", "dni": "4780010"},
  {"fila": 8, "nombre": "Capital Cero", "telefono": "966780108", "capital": 0},
  {"fila": 9, "nombre": "Capital 3 decimales", "telefono": "966780109", "capital": "1.234"},
  {"fila": 10, "nombre": "Capital texto", "telefono": "966780110", "capital": "mil"},
  {"fila": 11, "nombre": "Moneda", "telefono": "966780111", "moneda": "EUR"},
  {"fila": 12, "nombre": "Repite telefono", "telefono": "51966780101"},
  {"fila": 13, "nombre": "Repite DNI", "telefono": "966780113", "dni": "47800101"},
  {"fila": 14, "nombre": "Ya de V1", "telefono": "966780001"},
  {"fila": 15, "nombre": "Ya de V3", "telefono": "966780002"},
  {"fila": 16, "nombre": "En bolsa", "telefono": "966780003"},
  {"fila": 17, "nombre": "Retirado", "telefono": "966780004"},
  {"fila": 18, "nombre": "Descartado 24h", "telefono": "966780005"},
  {"fila": 19, "nombre": "Convertido", "telefono": "966780006"},
  {"fila": 20, "nombre": "Enfriamiento", "telefono": "966780007"},
  {"fila": 21, "nombre": "Reutilizable", "telefono": "966780008"},
  {"fila": 22, "nombre": "Cliente por telefono", "telefono": "999888777"},
  {"fila": 23, "nombre": "No contactar por DNI", "telefono": "966780123", "dni": "47800009"},
  {"fila": 24, "nombre": "Persona vetada", "telefono": "966780124", "dni": "78427011"},
  {"fila": 25, "nombre": "Persona con lead", "telefono": "966780125", "dni": "99887761"},
  {"fila": 26, "nombre": "Lead vivo por DNI", "telefono": "966780126", "dni": "47800010"},
  {"fila": 27, "nombre": "Cliente por DNI", "telefono": "966780127", "dni": "74447002"},
  {"fila": 28, "nombre": "Persona sin lead", "telefono": "966780128", "dni": "78258291", "capital": 2000},
  {"fila": 32, "nombre": "No contactar de otro equipo", "telefono": "966780011"},
  {"fila": 33, "nombre": "Descartado de otro equipo", "telefono": "966780012"},
  {"fila": 34, "nombre": "Mezcla: lead de V1 por teléfono, de V3 por DNI", "telefono": "966780013", "dni": "47800012"}
]$j$::jsonb || jsonb_build_array(jsonb_build_object('fila', 29, 'nombre', repeat('n', 201), 'telefono', '966780129'),
                                  jsonb_build_object('fila', 30, 'nombre', 'Distrito largo', 'telefono', '966780130', 'distrito', repeat('d', 121)),
                                  jsonb_build_object('fila', 31, 'nombre', 'Comentario largo', 'telefono', '966780131', 'comentario', repeat('c', 1001))))::text;
update f set lote1 = pg_temp.ejecutar(pg_temp.lote('b8000000-0000-4000-8000-0000000000d2', (f.bs1->>'base_id')::uuid, f.req1), f.s1);
do $$ begin
  if (select lote1 is null from f) then raise exception 'b8-cargar: el lote principal no devolvió nada'; end if;
end $$;
select pg_temp.caso('D1 veredicto de cada fila (motivo y lead_id solo en el ámbito de S1; lead_id solo de leads activos)',
  '2:cargada,3:cargada,4:invalida/nombre_vacio,5:invalida/telefono_invalido,6:invalida/telefono_invalido,7:invalida/dni_invalido,'
  || '8:invalida/capital_invalido,9:invalida/capital_invalido,10:invalida/capital_invalido,11:invalida/moneda_invalida,'
  || '12:repetida/en_archivo,13:repetida/en_archivo,14:ya_existia/con_dueno+id,15:ya_existia,16:ya_existia,'
  || '17:ya_existia/retirado,18:ya_existia/descartado+id,19:ya_existia/convertido+id,20:ya_existia/descartado+id,'
  || '21:ya_existia/descartado+id,22:ya_existia/cliente,23:no_contactar/no_insistir+id,24:no_contactar/no_insistir,'
  || '25:ya_existia/cliente,26:ya_existia/con_dueno+id,27:ya_existia/cliente,28:cargada,29:invalida/nombre_largo,'
  || '30:invalida/distrito_largo,31:invalida/comentario_largo,32:ya_existia,33:ya_existia,34:ya_existia',
  (select pg_temp.veredictos(lote1) from f));
select pg_temp.caso('D2 conteos del lote', '{"filas": 33, "cargadas": 3, "invalidas": 11, "repetidas": 2, "ya_existian": 15, "no_contactar": 2}',
  (select (lote1->'lote')::text from f));
select pg_temp.caso('D3 los lead_id que salen son los de los leads sembrados (14 → V1, 23 → No contactar, 26 → el del DNI)', 'true',
  (select ((select (x->>'lead_id')::uuid from jsonb_array_elements(lote1->'filas') x where x->>'fila' = '14') = f.l_v1
           and (select (x->>'lead_id')::uuid from jsonb_array_elements(lote1->'filas') x where x->>'fila' = '23') = f.l_noc
           and (select (x->>'lead_id')::uuid from jsonb_array_elements(lote1->'filas') x where x->>'fila' = '26') = f.l_dni)::text from f));
select pg_temp.caso('D4 totales de la base = conteos del lote', '{"cargadas": 3, "invalidas": 11, "repetidas": 2, "ya_existian": 15, "no_contactar": 2, "filas_recibidas": 33}',
  (select (lote1->'base')::text from f));
select pg_temp.caso('D5 la respuesta no lleva nombres, teléfonos ni DNI', 'true',
  (select (lote1::text !~ 'Ana Base|Beto|96678|47800|78427011|99887761|74447002|999888777|Lince|tarde|otro equipo|Mezcla')::text from f));
select pg_temp.caso('D6 recibo cargar_lote = respuesta exacta, cabe en 64 KB', 'true',
  (select (o.tipo = 'cargar_lote' and o.respuesta = f.lote1 and o.base_id = (f.bs1->>'base_id')::uuid and octet_length(o.respuesta::text) <= 65536)::text
     from f join crm.base_carga_operaciones o on o.operacion_id = 'b8000000-0000-4000-8000-0000000000d2' and o.actor = f.s1));

-- ───────── E · El contacto nace dormido ─────────
create temp view cargados as
  select l.* from crm.leads l join crm.base_carga_leads bl on bl.lead_id = l.id
   where bl.base_id = (select (bs1->>'base_id')::uuid from f) and bl.procedencia = 'archivo';
select pg_temp.caso('E1 tres contactos en la base, todos dormidos: base_cargada/descartado/base_cargada, bandeja de S1, sin analista, activos, alta_manual false, creados por S1, ciclo 1', '3|3',
  (select format('%s|%s', count(*), count(*) filter (where l.origen = 'base_cargada' and l.etapa = 'descartado' and l.motivo_descarte = 'base_cargada'
       and l.asignado_supervisor_id = f.s1 and l.vendedor_id is null and l.activo and not l.alta_manual and l.creado_por = f.s1 and l.ciclo_actual = 1
       and not l.no_contactar and l.tenencia_desde is null and l.perfil_id is null and l.contrato_id is null))
     from cargados l, f));
select pg_temp.caso('E2 descartado_en = momento de la carga (= creado_en) y descartado_por = S1', '3',
  (select count(*)::text from cargados l, f where l.descartado_en = l.creado_en and l.descartado_en >= now() - interval '1 minute' and l.descartado_por = f.s1));
select pg_temp.caso('E3 los datos de la fila 2: nombre y distrito sin espacios al borde, teléfono normalizado, DNI, nota, capital 1500.50 USD', 'Ana Base Uno|+51966780101|47800101|Lince|llamar de tarde|1500.50|USD',
  (select concat_ws('|', nombre_completo, telefono, dni, distrito, nota, monto_estimado, moneda) from cargados where telefono = '+51966780101'));
select pg_temp.caso('E4 la fila 3 sin capital → monto NULL (E8), moneda PEN, teléfono normalizado', '+51966780102|true|PEN',
  (select concat_ws('|', telefono, (monto_estimado is null)::text, moneda) from cargados where nombre_completo = 'Beto Sin Capital'));
select pg_temp.caso('E5 ningún ciclo ni episodio de SLA, ninguna asignación en el ledger', '0|0|0',
  (select format('%s|%s|%s', (select count(*) from crm.lead_sla_ciclos c where c.lead_id in (select id from cargados)),
                             (select count(*) from crm.lead_sla_etapas e where e.lead_id in (select id from cargados)),
                             (select count(*) from crm.lead_asignaciones a where a.lead_id in (select id from cargados)))));
select pg_temp.caso('E6 pertenencia: procedencia archivo, agregada por S1, sin repartir, viva', '3',
  (select count(*)::text from crm.base_carga_leads bl, f where bl.base_id = (f.bs1->>'base_id')::uuid and bl.procedencia = 'archivo'
     and bl.agregado_por = f.s1 and bl.analista_id is null and bl.asignado_en is null and bl.asignado_por is null and bl.activo));
select pg_temp.caso('E7 la válvula queda APAGADA al salir de la puerta', 'off',
  (select coalesce(current_setting('crm.op_bases_carga', true), '(sin valor)')));
select pg_temp.caso('E8 bitácora: una fila INSERT por contacto, con el DNI enmascarado', '3|true',
  (select format('%s|%s', count(*), bool_and(coalesce(a.data_despues->>'dni', '') !~ '47800101')::text) from public.audit_log a
    where a.tabla = 'crm.leads' and a.operacion = 'INSERT' and a.fila_id::text in (select id::text from cargados)));
select pg_temp.caso('E9 la fila 28 quedó ENLAZADA a su persona (DNI de una persona sin lead) con su puente canónico', 'true|true',
  (select format('%s|%s', (l.inversionista_id = f.p_libre)::text,
                 exists (select 1 from crm.inversionista_leads il where il.lead_id = l.id and il.inversionista_id = f.p_libre and il.rol = 'canonico')::text)
     from cargados l, f where l.dni = '78258291'));
select pg_temp.caso('E10 «Descartes del mes» (rescate) de S1 y de Gerencia NO los muestra (salen del ledger)', '0|0',
  (select format('%s|%s',
     pg_temp.valor(format('select count(*) from crm.rescate_descartes_mes(current_date) d where d.lead_id in (%s)', (select string_agg(quote_literal(id), ',') from cargados)), 'authenticated', (select s1 from f)),
     pg_temp.valor(format('select count(*) from crm.rescate_descartes_mes(current_date) d where d.lead_id in (%s)', (select string_agg(quote_literal(id), ',') from cargados)), 'authenticated', (select g from f)))));
select pg_temp.caso('E11 métricas de SLA de Gerencia (crm.metricas_sla_fn de hoy): idénticas antes y después de cargar 2 contactos', '2|true',
  pg_temp.valor(format('select pg_temp.metricas_con_carga(%L, %L, %L)', (select g from f), (select s1 from f), (select (bs1->>'base_id')::uuid from f))));
select pg_temp.caso('E12 llegadas (conversion_episodios del mes): ninguno de los contactos cargados', '0',
  (select count(*)::text from private.conversion_episodios(date_trunc('month', now()), date_trunc('month', now()) + interval '1 month', null, true, '{}'::uuid[], 1) e
    where e.lead_id in (select id from cargados)));
-- Andamio: el banco no trae la fila de control del SLA que producción sí tiene (como supabase/scripts/g4/test-g4b.sql).
alter table crm.sla_operacion_control disable trigger user;
insert into crm.sla_operacion_control (id, modo, revision, cambiado_en, cambiado_por)
select true, 'observacion', 0, now(), f.g from f where not exists (select 1 from crm.sla_operacion_control);
alter table crm.sla_operacion_control enable trigger user;
select pg_temp.caso('E13 el estado SLA (estado_sla_leads_v2_fn) se lee igual para un descartado normal y para un dormido (sin ciclo 1)', 'ok|ok',
  (select string_agg(case when v like 'ERROR%' then v else 'ok' end, '|' order by o)
     from (select 1 as o, pg_temp.valor(format('select jsonb_array_length(crm.estado_sla_leads_v2_fn(array[%L]::uuid[])->''filas'')', (select l_enf from f)), 'authenticated', (select s1 from f)) v
           union all
           select 2, pg_temp.valor(format('select jsonb_array_length(crm.estado_sla_leads_v2_fn(array[%L]::uuid[])->''filas'')', (select id from cargados where telefono = '+51966780102')), 'authenticated', (select s1 from f))) x));
-- B10 (20261004223253) lo decidió: los dormidos SIN REPARTIR ya no salen en la Gestión de la base (viven en la pestaña «Bases»).
select pg_temp.caso('E14 los dormidos salen en la Gestión de la base de su supervisor (obtener_base_gestion); con B10, ya no',
  case when to_regprocedure('crm.seguimiento_bases()') is null then '3' else '0' end,
  pg_temp.valor(format('select count(*) from crm.obtener_base_gestion() b where b.lead_id in (%s)', (select string_agg(quote_literal(id), ',') from cargados)), 'authenticated', (select s1 from f)));
select pg_temp.caso('E15 … con 0 días desde el descarte y sin «en gestión» (B6)', '0|true',
  case when to_regprocedure('crm.seguimiento_bases()') is null then
  (select format('%s|%s', min(x.dias), bool_and(private.base_gestion_en_gestion_hasta(x.lead_id) is null)::text)
     from (select (b->>'dias_desde_descarte')::int as dias, (b->>'lead_id')::uuid as lead_id
             from jsonb_array_elements(pg_temp.lista(pg_temp.a_jsonb(pg_temp.valor(format('select jsonb_agg(to_jsonb(b)) from crm.obtener_base_gestion() b where b.lead_id in (%s)',
                                                            (select string_agg(quote_literal(id), ',') from cargados)), 'authenticated', (select s1 from f))))) b) x)
  -- Con B10 no están en la lista: los mismos días (como los calcula la lista) desde el lead.
  else (select format('%s|%s', min(((now() at time zone 'America/Lima')::date - (l.descartado_en at time zone 'America/Lima')::date)::integer),
                      bool_and(private.base_gestion_en_gestion_hasta(l.id) is null)::text)
          from crm.leads l where l.id in (select id from cargados)) end);

select pg_temp.prueba('E16 Gerencia (API) pone el enfriamiento base_cargada en 0 días → 23514 (el alta vería «libre» 24 h)',
  '23514 new row for relation "enfriamiento_politica" violates check constraint "enfriamiento_politica_base_cargada_dias_positivos"',
  'update crm.enfriamiento_politica set dias = 0 where motivo = ''base_cargada''', 'authenticated', (select g from f));
select pg_temp.prueba('E17 … a 15 días sí puede', 'paso',
  'update crm.enfriamiento_politica set dias = 15 where motivo = ''base_cargada''', 'authenticated', (select g from f));

-- ───────── F · Las altas posteriores NO duplican ─────────
select pg_temp.caso('F1 alta manual del teléfono de la fila 3 (V1) → «enfriamiento» (base_cargada, 30 días), sin lead nuevo', 'enfriamiento|base_cargada|1',
  (select concat_ws('|', v->>'estado', v->>'motivo_descarte', (select count(*) from crm.leads where telefono = '+51966780102'))
     from (select pg_temp.a_jsonb(pg_temp.valor('select crm.crear_lead_si_disponible(''Otro Beto'', ''966780102'', ''oficina'', 1000, ''PEN'')', 'authenticated', (select v1 from f))) v) x));
select pg_temp.caso('F2 alta manual con el DNI de la fila 2 y otro teléfono → «enfriamiento»', 'enfriamiento',
  (select v->>'estado' from (select pg_temp.a_jsonb(pg_temp.valor('select crm.crear_lead_si_disponible(''Otra Ana'', ''966780199'', ''oficina'', 1000, ''PEN'', null, null, ''47800101'')', 'authenticated', (select v1 from f))) v) x));
select pg_temp.caso('F3 «tomar lead libre» (V1) del teléfono de la fila 3 → «enfriamiento»; el contacto sigue en la bandeja de S1', 'enfriamiento|true',
  pg_temp.valor('select crm.tomar_lead_libre(''966780102'', null)->>''estado''', 'authenticated', (select v1 from f))
  || '|' || (select (vendedor_id is null and asignado_supervisor_id = (select s1 from f))::text from crm.leads where telefono = '+51966780102'));
alter table f add column beto uuid;
update f set beto = (select id from cargados where telefono = '+51966780102');
select pg_temp.caso('F4 vencido el enfriamiento (40 días), el alta de V1 ve «reutilizable» y tampoco crea otro', 'reutilizable|1',
  pg_temp.valor(format('select pg_temp.alta_tras_vencer(%L, ''966780102'', %L)', (select beto from f), (select v1 from f))));
select pg_temp.prueba('F5 un INSERT directo (con la sesión de S1, sin la válvula) del teléfono de un dormido → P0481 enfriamiento', 'P0481 Contacto no disponible',
  'insert into crm.leads (nombre_completo, telefono, origen, etapa, monto_estimado, moneda, asignado_supervisor_id, creado_por) select ''Directo'', ''966780102'', ''oficina'', ''nuevo'', 1000, ''PEN'', s1, s1 from f',
  null, (select s1 from f));

-- ───────── G · Repetida en la base e idempotencia del lote ─────────
alter table f add column lote2 jsonb;
update f set lote2 = pg_temp.ejecutar(pg_temp.lote('b8000000-0000-4000-8000-0000000000d3', (f.bs1->>'base_id')::uuid,
  '[{"fila": 40, "nombre": "Otra vez Ana", "telefono": "966780101"}, {"fila": 41, "nombre": "Otra vez por DNI", "telefono": "966780141", "dni": "47800101"}, {"fila": 42, "nombre": "Nueva", "telefono": "966780142"}]'), f.s1);
select pg_temp.caso('G1 segundo lote: lo ya cargado en ESTA base → repetida/en_base (con su lead_id); lo nuevo, cargada', '40:repetida/en_base+id,41:repetida/en_base+id,42:cargada',
  (select pg_temp.veredictos(lote2) from f));
select pg_temp.caso('G2 los totales de la base suman los dos lotes', '36|4|4',
  (select format('%s|%s|%s', filas_recibidas, cargadas, repetidas) from crm.bases_carga where id = (select (bs1->>'base_id')::uuid from f)));
select pg_temp.caso('G3 replay del lote 1 (mismo id y mismas filas) → la MISMA respuesta; nada cambia', 'true|36|4|4',
  (select format('%s|%s', (pg_temp.ejecutar(pg_temp.lote('b8000000-0000-4000-8000-0000000000d2', (f.bs1->>'base_id')::uuid, f.req1), f.s1) = f.lote1)::text,
                 (select format('%s|%s|%s', b.filas_recibidas, b.cargadas, (select count(*) from crm.base_carga_leads bl where bl.base_id = b.id)) from crm.bases_carga b where b.id = (f.bs1->>'base_id')::uuid))
     from f));
select pg_temp.prueba('RP1 (r2) el lead que el recibo nombra (fila 14) se retira → el replay del lote 1 se rechaza (P0002)',
  'P0002 La respuesta guardada nombra leads que ya no están a tu alcance; repite la operación con otro identificador',
  format('reset role; update crm.leads set activo = false where id = %L; set local role authenticated; ', (select l_v1 from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d2', (select (bs1->>'base_id')::uuid from f), (select req1 from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('RP2 (r2) el lead de la fila 26 pasa al equipo de S2 → el replay del lote 1 se rechaza (P0002)',
  'P0002 La respuesta guardada nombra leads que ya no están a tu alcance; repite la operación con otro identificador',
  format('reset role; update crm.leads set vendedor_id = %L where id = %L; set local role authenticated; ', (select v3 from f), (select l_dni from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d2', (select (bs1->>'base_id')::uuid from f), (select req1 from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('G4 mismo id del lote 1 con otras filas → 22023', '22023 Este identificador de operación ya se usó con un pedido distinto',
  pg_temp.lote('b8000000-0000-4000-8000-0000000000d2', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s1 from f));
select pg_temp.prueba('G5 el id de la operación crear usado para un lote → 22023', '22023 Este identificador de operación ya se usó con un pedido distinto',
  pg_temp.lote('b8000000-0000-4000-8000-0000000000c1', (select (bs1->>'base_id')::uuid from f), '[{"fila":1,"nombre":"X","telefono":"966780099"}]'), 'authenticated', (select s1 from f));

select pg_temp.caso('G6 un lead de la base que pasó a otro equipo (bandeja de S2) → repetida/en_base SIN su id', '50:repetida/en_base',
  pg_temp.valor(format('select pg_temp.lote_tras(%L, %L, %L, %L)',
    'update crm.leads set asignado_supervisor_id = ' || quote_literal((select s2 from f)) || ' where telefono = ''+51966780101''',
    (select s1 from f), (select (bs1->>'base_id')::uuid from f), '[{"fila": 50, "nombre": "X", "telefono": "966780101"}]')));
select pg_temp.caso('G7 un lead que SALIÓ de la base (pertenencia retirada) no cuenta como repetida: se evalúa (enfriamiento, en su ámbito)', '51:ya_existia/descartado+id',
  pg_temp.valor(format('select pg_temp.lote_tras(%L, %L, %L, %L)',
    'update crm.base_carga_leads set activo = false where lead_id = (select id from crm.leads where telefono = ''+51966780142'')',
    (select s1 from f), (select (bs1->>'base_id')::uuid from f), '[{"fila": 51, "nombre": "X", "telefono": "966780142"}]')));

-- ───────── R · El replay exige ámbito vigente sobre la base ─────────
alter table f add column lotesa jsonb;
update f set lotesa = pg_temp.ejecutar(pg_temp.lote('b8000000-0000-4000-8000-0000000000d5', (f.bsa->>'base_id')::uuid, '[{"fila": 1, "nombre": "SA uno", "telefono": "966780701"}]'), f.s1);
select pg_temp.caso('R1 S1 carga en la base de su supervisor anidado y el replay devuelve lo mismo', '1:cargada|true',
  (select pg_temp.veredictos(lotesa) || '|' || (pg_temp.ejecutar(pg_temp.lote('b8000000-0000-4000-8000-0000000000d5', (f.bsa->>'base_id')::uuid, '[{"fila": 1, "nombre": "SA uno", "telefono": "966780701"}]'), f.s1) = f.lotesa)::text from f));
select pg_temp.prueba('R2 el supervisor anidado pasa al equipo de S2: el replay de S1 ya no devuelve el recibo → P0002', 'P0002 Base no encontrada o fuera de tu ámbito',
  format('reset role; update crm.equipo set supervisor_id = %L where perfil_id = %L; set local role authenticated; ', (select s2 from f), (select sa from f))
  || pg_temp.lote('b8000000-0000-4000-8000-0000000000d5', (select (bsa->>'base_id')::uuid from f), '[{"fila": 1, "nombre": "SA uno", "telefono": "966780701"}]'),
  'authenticated', (select s1 from f));

-- ───────── T · Una carrera en el INSERT no saca datos de otro equipo ─────────
select pg_temp.caso('T1 el INSERT choca con un P0481 (detail con un analista ajeno): esa fila → ya_existia sin motivo; la otra carga; sin el detail', '1:ya_existia,2:cargada|false',
  pg_temp.valor(format('select pg_temp.lote_con_falla(''P0481'', %L, %L)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));
select pg_temp.caso('T2 un P0429 (veto) → no_contactar sin motivo; la otra carga; sin el detail', '1:no_contactar,2:cargada|false',
  pg_temp.valor(format('select pg_temp.lote_con_falla(''P0429'', %L, %L)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));
select pg_temp.caso('T3 otra excepción del INSERT aborta el lote con un mensaje sin datos (fila y código)', 'ERROR P0001 No se pudo cargar la fila 1 (P0001)',
  pg_temp.valor(format('select pg_temp.lote_con_falla(''P0001'', %L, %L)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));
select pg_temp.caso('T4 … y sin detail (ni el analista ajeno ni el id)', 'P0001|(sin detail)',
  pg_temp.detalle(format('select pg_temp.lote_con_falla(''P0001'', %L, %L)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));

select pg_temp.caso('T5 (r2) un lote lleno (100) y la 100 choca (P0481): respaldo fila a fila (2 intentos) → 99 cargadas + 1 ya_existia; sin residuos ni el detail', '99|1|intentos 2|99|99|ok|false',
  pg_temp.valor(format('select pg_temp.lote_falla_n(''P0481'', %L, %L, 100, 100)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));
select pg_temp.caso('T6 (r2) la fila 100 da un error TRANSITORIO (40001): el lote aborta entero (1 intento, sin respaldo), mismo código, sin detail ni residuos', '-|-|intentos 1|0|0|40001 La carga se interrumpió (40001); reintenta|false',
  pg_temp.valor(format('select pg_temp.lote_falla_n(''40001'', %L, %L, 100, 100)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));
select pg_temp.caso('T6b (r2) … y con 55P03 (espera agotada), igual', '-|-|intentos 1|0|0|55P03 La carga se interrumpió (55P03); reintenta|false',
  pg_temp.valor(format('select pg_temp.lote_falla_n(''55P03'', %L, %L, 3, 2)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));
select pg_temp.caso('T7 (r2) el respaldo juzga un P0429 con la regla del ámbito: con un lead fuera del ámbito → ya_existia sin motivo', '1:ya_existia,2:cargada',
  pg_temp.valor(format('select pg_temp.respaldo_p0429_fuera(%L, %L)', (select s1 from f), (select (bs1->>'base_id')::uuid from f))));

-- ───────── H · armar_base_crm ─────────
-- Descartados del equipo de S1 (V1) y uno de S2 (V3), sembrados sin usuario.
alter table f add column h jsonb;
update f set h = jsonb_build_object('ok1', gen_random_uuid(), 'ok2', gen_random_uuid(), 'noc', gen_random_uuid(), 'dinv', gen_random_uuid(),
  'desc', gen_random_uuid(), 'gest', gen_random_uuid(), 'vivo', gen_random_uuid(), 'inact', gen_random_uuid(), 'otra', gen_random_uuid(), 'v3', gen_random_uuid());
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select (f.h->>x.k)::uuid, 'B8 ARMAR ' || x.k, x.tel, 'oficina', 'nuevo', case when x.k = 'v3' then f.v3 else f.v1 end, 1000, 'PEN', f.v1, true
  from f, lateral (values ('ok1', '966780201'), ('ok2', '966780202'), ('noc', '966780203'), ('dinv', '966780204'), ('desc', '966780205'),
                          ('gest', '966780206'), ('vivo', '966780207'), ('inact', '966780208'), ('otra', '966780209'), ('v3', '966780210')) x(k, tel);
update crm.leads set etapa = 'descartado', motivo_descarte = case when id = (select (h->>'dinv')::uuid from f) then 'datos_invalidos' else 'no_responde' end
 where id in (select (value #>> '{}')::uuid from f, jsonb_each(f.h) where key <> 'vivo');
select set_config('crm.op_privilegiada', 'on', true);
update crm.leads set no_contactar = true where id = (select (h->>'noc')::uuid from f);
select set_config('crm.op_privilegiada', 'off', true);
update crm.leads set activo = false where id = (select (h->>'inact')::uuid from f);
select set_config('crm.op_base_gestion', 'on', true);
update crm.leads set enfriado_hasta = current_date + 10 where id = (select (h->>'desc')::uuid from f);
select set_config('crm.op_base_gestion', 'off', true);
-- «gest»: su analista registra un intento por la puerta real (seguimiento activo B6: ≤ 7 días).
select pg_temp.ejecutar(format('select to_jsonb(crm.registrar_intento_base(gen_random_uuid(), %L, ''no_contesto'', ''B8 intento''))', (f.h->>'gest')::uuid), f.v1) from f;
-- «otra» ya está en otra base viva (la de S2 de la sección B).
insert into crm.base_carga_leads (base_id, lead_id, procedencia, agregado_por)
select (f.bs2g->>'base_id')::uuid, (f.h->>'otra')::uuid, 'crm', f.g from f;
create temp table antes_armar as select l.id, md5(row(l.*)::text) as huella from crm.leads l, f where l.id in (select (value #>> '{}')::uuid from jsonb_each(f.h));
create function pg_temp.armar(p_op text, p_nombre text, p_sup uuid, p_ids uuid[]) returns text language sql as $$
  select format('select crm.armar_base_crm(%L, %L, %L, %L::uuid[])', p_op, p_nombre, p_sup, p_ids) $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
alter table f add column ids uuid[];
update f set ids = array[(h->>'ok1')::uuid, (h->>'noc')::uuid, (h->>'dinv')::uuid, (h->>'desc')::uuid, (h->>'gest')::uuid, (h->>'vivo')::uuid,
                         (h->>'inact')::uuid, (h->>'otra')::uuid, (h->>'v3')::uuid, 'b8000000-0000-4000-8000-0000000000ff'::uuid, (h->>'ok2')::uuid, (h->>'ok1')::uuid];
select pg_temp.prueba('H1 el analista → 42501', (select m_rol from f), pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate', null, (select ids from f)), 'authenticated', (select v1 from f));
select pg_temp.prueba('H2 Gerencia sin supervisor → 22023', '22023 Gerencia debe elegir el supervisor dueño de la base',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate', null, (select ids from f)), 'authenticated', (select g from f));
select pg_temp.prueba('H3 S1 para la bandeja de S2 → 42501', '42501 Un supervisor solo crea bases para su propia bandeja',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate', (select s2 from f), (select ids from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('H4 lista vacía → 22023', '22023 Una base armada desde el CRM lleva entre 1 y 2000 leads (llegaron 0)',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate', null, '{}'), 'authenticated', (select s1 from f));
select pg_temp.prueba('H5 2001 leads → 22023', '22023 Una base armada desde el CRM lleva entre 1 y 2000 leads (llegaron 2001)',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate', null, (select array_agg(gen_random_uuid()) from generate_series(1, 2001))), 'authenticated', (select s1 from f));
select pg_temp.prueba('H6 un id vacío en la lista → 22023', '22023 La lista de leads no admite vacíos',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate', null, array[(select (h->>'ok1')::uuid from f), null]), 'authenticated', (select s1 from f));
select pg_temp.prueba('H6b un arreglo que empieza en la posición 0 → 22023', '22023 La lista de leads debe ser un arreglo simple que empiece en la posición 1',
  format('select crm.armar_base_crm(%L, %L, null, %L::uuid[])', 'b8000000-0000-4000-8000-0000000000e9', 'Indices',
         (select '[0:1]={' || (h->>'ok1') || ',' || (h->>'ok2') || '}' from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('H6c un arreglo de dos dimensiones → 22023', '22023 La lista de leads debe ser un arreglo simple que empiece en la posición 1',
  format('select crm.armar_base_crm(%L, %L, null, %L::uuid[])', 'b8000000-0000-4000-8000-0000000000e9', 'Indices',
         (select '{{' || (h->>'ok1') || '},{' || (h->>'ok2') || '}}' from f)), 'authenticated', (select s1 from f));
alter table f add column arm1 jsonb;
update f set arm1 = pg_temp.ejecutar(pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate S1', null, f.ids), f.s1);
select pg_temp.caso('H7 incluidos y excluidos con su motivo (por posición en la lista)', 'true|12|2|10',
  (select format('%s|%s|%s|%s', ((arm1->'excluidos_por_motivo') = '{"inactivo": [7], "repetido": [12], "en_gestion": [5], "en_descanso": [4], "en_otra_base": [8], "no_contactar": [2], "no_encontrado": [9, 10], "no_descartado": [6], "datos_invalidos": [3]}'::jsonb)::text,
                 arm1->>'recibidos', arm1->>'incluidos', arm1->>'excluidos') from f));
select pg_temp.caso('H8 excluidos_detalle trae el lead_id de cada posición', 'true',
  (select (jsonb_array_length(arm1->'excluidos_detalle') = 10
           and (select bool_and((x->>'lead_id')::uuid = f.ids[(x->>'posicion')::int]) from jsonb_array_elements(f.arm1->'excluidos_detalle') x))::text from f));
select pg_temp.caso('H9 la base: origen crm, sin archivo, de S1; pertenencia procedencia crm de ok1 y ok2; totales', 'crm|true|true|ok1,ok2|12|2|1|1',
  (select format('%s|%s|%s|%s|%s|%s|%s|%s', b.origen, (b.archivo_nombre is null)::text, (b.supervisor_id = f.s1 and b.creada_por = f.s1)::text,
                 (select string_agg(k.key, ',' order by k.key) from crm.base_carga_leads bl join jsonb_each_text(f.h) k on k.value::uuid = bl.lead_id
                   where bl.base_id = b.id and bl.procedencia = 'crm' and bl.agregado_por = f.s1 and bl.analista_id is null),
                 b.filas_recibidas, b.cargadas, b.no_contactar, b.repetidas)
     from f join crm.bases_carga b on b.id = (f.arm1->>'base_id')::uuid));
select pg_temp.caso('H10 armar NO toca los leads (E13: misma fila exacta antes y después)', '0',
  (select count(*)::text from antes_armar a join crm.leads l on l.id = a.id where md5(row(l.*)::text) <> a.huella));
select pg_temp.caso('H11 replay → la MISMA respuesta (sin otra base)', 'true|1',
  (select format('%s|%s', (pg_temp.ejecutar(pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate S1', null, f.ids), f.s1) = f.arm1)::text,
                 (select count(*) from crm.bases_carga where nombre = 'Rescate S1')) from f));
select pg_temp.prueba('RP3 (r2) un lead INCLUIDO en el armado se retira → el replay se rechaza (P0002)',
  'P0002 La respuesta guardada nombra leads que ya no están a tu alcance; repite la operación con otro identificador',
  format('reset role; update crm.leads set activo = false where id = %L; set local role authenticated; ', (select (h->>'ok1')::uuid from f))
  || pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate S1', null, (select ids from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('RP5 (r2) un EXCLUIDO por su estado (no_contactar) pasa al equipo de S2 → el replay se rechaza (P0002)',
  'P0002 La respuesta guardada nombra leads que ya no están a tu alcance; repite la operación con otro identificador',
  format('reset role; update crm.leads set vendedor_id = %L where id = %L; set local role authenticated; ', (select v3 from f), (select (h->>'noc')::uuid from f))
  || pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate S1', null, (select ids from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('RP4 (r2) un EXCLUIDO por inactivo sigue inactivo y a su alcance → el replay pasa', 'paso',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate S1', null, (select ids from f)), 'authenticated', (select s1 from f));
select pg_temp.prueba('H12 mismo id con otra lista → 22023', '22023 Este identificador de operación ya se usó con un pedido distinto',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e1', 'Rescate S1', null, (select ids[1:3] from f)), 'authenticated', (select s1 from f));
select pg_temp.caso('H13 otra base solo con ok1 (ya en una base viva) → 22023 sin elegibles, detail en_otra_base, y no se crea base', '22023|{"excluidos_por_motivo": {"en_otra_base": [1]}}|0',
  (select pg_temp.detalle(pg_temp.armar('b8000000-0000-4000-8000-0000000000e2', 'Otra', null, array[(h->>'ok1')::uuid]), 'authenticated', s1) from f)
  || '|' || (select count(*) from crm.bases_carga where nombre = 'Otra'));
select pg_temp.prueba('H14 nombre repetido en la bandeja viva → 23505', '23505 Ya hay una base viva con ese nombre en la bandeja de ese supervisor',
  pg_temp.armar('b8000000-0000-4000-8000-0000000000e3', 'rescate s1', null, array[(select (h->>'ok2')::uuid from f)]), 'authenticated', (select s1 from f));
select pg_temp.caso('H14b Gerencia arma para S1 con un descartado de V3 (fuera del subárbol de S1) → no_encontrado, sin base', '22023|{"excluidos_por_motivo": {"no_encontrado": [1]}}',
  (select pg_temp.detalle(pg_temp.armar('b8000000-0000-4000-8000-0000000000e5', 'Gerencia para S1', s1, array[(h->>'v3')::uuid]), 'authenticated', g) from f));
-- Un descartado de la BANDEJA de S1 (sin analista): dentro del ámbito del dueño.
alter table f add column band uuid;
update f set band = gen_random_uuid();
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, asignado_supervisor_id, vendedor_id, monto_estimado, moneda, creado_por, activo)
select f.band, 'B8 ARMAR BANDEJA', '966780211', 'oficina', 'nuevo', f.s1, null, 1000, 'PEN', f.s1, true from f;
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = (select band from f);
select pg_temp.caso('H14c S1 arma con un descartado de su bandeja (sin analista) → incluido', '1|{}',
  (select v->>'incluidos' || '|' || (v->'excluidos_por_motivo')::text
     from (select pg_temp.a_jsonb(pg_temp.valor(pg_temp.armar('b8000000-0000-4000-8000-0000000000e6', 'Bandeja S1', null, array[(select band from f)]), 'authenticated', (select s1 from f))) v) x));
alter table f add column arm2 jsonb;
update f set arm2 = pg_temp.ejecutar(pg_temp.armar('b8000000-0000-4000-8000-0000000000e4', 'Rescate de S2', f.s2, array[(f.h->>'v3')::uuid, (f.h->>'ok2')::uuid]), f.g);
select pg_temp.caso('H15 Gerencia arma para S2: el descartado de V3 entra; ok2 (de V1, fuera del subárbol de S2) → no_encontrado', '1|{"no_encontrado": [2]}|true',
  (select format('%s|%s|%s', arm2->>'incluidos', arm2->'excluidos_por_motivo',
                 exists (select 1 from crm.base_carga_leads bl where bl.base_id = (arm2->>'base_id')::uuid and bl.lead_id = (h->>'v3')::uuid)::text) from f));
select pg_temp.caso('H16 recibo armar compacto (posiciones) y < 64 KB', 'armar|true',
  (select format('%s|%s', o.tipo, (o.respuesta ? 'excluidos_por_motivo' and not o.respuesta ? 'excluidos_detalle' and octet_length(o.respuesta::text) <= 65536)::text)
     from f join crm.base_carga_operaciones o on o.operacion_id = 'b8000000-0000-4000-8000-0000000000e1' and o.actor = f.s1));

-- ───────── L · Regresión ─────────
select pg_temp.caso('L1 el alta normal sigue naciendo con su ciclo SLA (1) y su etapa abierta (1)', 'creado|1|1',
  pg_temp.valor(format('select pg_temp.alta_normal(%L)', (select v1 from f))));
select pg_temp.prueba('L2 sin la válvula, un alta con usuario no nace descartada → 22023', '22023 Un lead debe nacer activo y en etapa operativa',
  'insert into crm.leads (nombre_completo, telefono, origen, etapa, motivo_descarte, monto_estimado, moneda, asignado_supervisor_id, creado_por) select ''X'', ''966780302'', ''oficina'', ''descartado'', ''no_responde'', 1000, ''PEN'', s1, s1 from f',
  null, (select s1 from f));
select pg_temp.prueba('L3 con la válvula, otro origen descartado (motivo base_cargada) no nace (sin usuario) → terminal', 'P0001 Un lead nuevo no puede nacer en estado terminal',
  'insert into crm.leads (nombre_completo, telefono, origen, etapa, motivo_descarte, monto_estimado, moneda, asignado_supervisor_id, creado_por) select ''X'', ''966780303'', ''oficina'', ''descartado'', ''base_cargada'', 1000, ''PEN'', s1, s1 from f',
  null, null, p_valvula => true);
select pg_temp.prueba('L4 con la válvula y usuario, base_cargada descartado con OTRO motivo no nace → 22023', '22023 Un lead debe nacer activo y en etapa operativa',
  'insert into crm.leads (nombre_completo, telefono, origen, etapa, motivo_descarte, monto_estimado, moneda, asignado_supervisor_id, creado_por) select ''X'', ''966780304'', ''base_cargada'', ''descartado'', ''no_responde'', 1000, ''PEN'', s1, s1 from f',
  null, (select s1 from f), p_valvula => true);
select pg_temp.prueba('L5 con la válvula, un dormido INACTIVO no nace (sin usuario) → terminal', 'P0001 Un lead nuevo no puede nacer en estado terminal',
  'insert into crm.leads (nombre_completo, telefono, origen, etapa, motivo_descarte, monto_estimado, moneda, asignado_supervisor_id, creado_por, activo) select ''X'', ''966780305'', ''base_cargada'', ''descartado'', ''base_cargada'', null, ''PEN'', s1, s1, false from f',
  null, null, p_valvula => true);
select pg_temp.caso('L6 con la válvula, un base_cargada que nace NUEVO (con capital y motivo base_cargada) abre su ciclo SLA y no recibe fecha de descarte', '1|false',
  pg_temp.valor(format('select pg_temp.nace_nuevo_con_valvula(%L)', (select s1 from f))));
alter table f add column nueva uuid, add column ana uuid;
update f set nueva = (select id from cargados where nombre_completo = 'Nueva'), ana = (select id from cargados where telefono = '+51966780101');
-- B10 (20261004223253): la puerta pide el capital antes de reabrir → 22023 (el CHECK sigue de candado debajo).
select pg_temp.caso('L7 reactivar un dormido SIN capital (S1) → 23514 del CHECK (con B10: 22023, pide el capital)',
  case when to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is null then 'ERROR 23514 new row for relation "leads" violates check constraint "leads_monto_estimado_valido"'
       else 'ERROR 22023 Indica el capital estimado para reactivar' end,
  pg_temp.valor(format('select pg_temp.reactivar(%L, %L)', (select nueva from f), (select s1 from f))));
select pg_temp.caso('L8 reactivar un dormido CON capital (S1) → contactado, ciclo 2 con su fila SLA (y sin la del ciclo 1)', 'contactado|2|2',
  pg_temp.valor(format('select pg_temp.reactivar(%L, %L)', (select ana from f), (select s1 from f))));

-- ───────── Z · Con la identidad APAGADA (el mundo del banco) ─────────
update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';
alter table f add column loteZ jsonb;
update f set loteZ = pg_temp.ejecutar(pg_temp.lote('b8000000-0000-4000-8000-0000000000d9', (f.bs1->>'base_id')::uuid,
  '[{"fila": 1, "nombre": "Z Uno", "telefono": "966780401", "dni": "47800401"}, {"fila": 2, "nombre": "Z Persona con lead", "telefono": "966780402", "dni": "99887761"}, {"fila": 3, "nombre": "Z vetada", "telefono": "966780403", "dni": "78427011"}]'), f.s1);
select pg_temp.caso('Z1 bandera apagada: carga; el DNI de un lead retirado → retirado (envoltorio, sin id: está retirado); la persona vetada sin lead, sin identidad, carga', '1:cargada,2:ya_existia/retirado,3:cargada',
  (select pg_temp.veredictos(loteZ) from f));
select pg_temp.caso('Z2 … y el alta posterior del mismo teléfono ve «enfriamiento»', 'enfriamiento',
  (select v->>'estado' from (select pg_temp.a_jsonb(pg_temp.valor('select crm.crear_lead_si_disponible(''Z Otro'', ''966780401'', ''oficina'', 1000, ''PEN'')', 'authenticated', (select v1 from f))) v) x));

-- ───────── Resultado ─────────
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 300)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B8: hay casos FAIL'; end if; end $$;
rollback;
