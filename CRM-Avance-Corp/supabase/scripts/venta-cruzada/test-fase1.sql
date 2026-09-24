-- Venta cruzada · Fase 1: prueba de las dos migraciones en el banco sintético.
-- Todo ocurre en UNA transacción que termina en ROLLBACK: no deja rastro.
-- NUNCA en producción (la guarda de abajo lo impide).
-- Uso (banco aislado de venta cruzada):
--   psql -h 127.0.0.1 -p 53322 -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     -f supabase/scripts/venta-cruzada/test-fase1.sql
-- El veredicto viaja como FILA: VENTA_CRUZADA_FASE1_OK.
begin;
set local statement_timeout = '60s';

do $guarda$ begin
  if (select count(*) from crm.leads) > 200 or (select count(*) from public.perfiles where rol = 'cliente') > 50 then
    raise exception 'Esta prueba solo corre en el banco sintético, nunca en producción';
  end if;
  if to_regclass('crm.busquedas_cliente_existente') is null then
    raise exception 'La Fase 1 no está aplicada en este banco';
  end if;
end $guarda$;

create function pg_temp.exigir(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FASE1: %', mensaje; end if; end $$;

-- Ejecuta p_sql y exige que falle con p_estado (y, si se da, con p_texto en el mensaje).
create function pg_temp.rechaza(p_sql text, p_estado text, p_texto text default null) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_estado and (p_texto is null or position(p_texto in sqlerrm) > 0) then return; end if;
    raise exception 'FASE1: esperado % (%), obtenido %: %', p_estado, coalesce(p_texto, '-'), sqlstate, sqlerrm;
  end;
  raise exception 'FASE1: debió rechazar con %: %', p_estado, left(p_sql, 160);
end $$;

-- SQL de una solicitud con los datos dados, listo para rechaza().
create function pg_temp.sol(p_id text, p_persona text, p_empresa uuid, p_creador text, p_puerta text,
  p_analista text, p_busqueda text, p_motivo text, p_lead text default null) returns text
language sql as $$
  select format($q$insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id,
    hash_payload, datos, creado_por, puerta, analista_cierre_id, busqueda_id, motivo_atribucion, lead_origen_id)
    values (%L, %L, %L, 'f1000000-0000-4000-8000-00000000000a', md5(%L)||md5(%L||'x'), %L::jsonb, %L, %L, %L, %L, %L, %L)$q$,
    p_id, p_persona, p_empresa, p_id, p_id,
    case when p_lead is null then '{}' else json_build_object('lead_id', p_lead)::text end,
    p_creador, p_puerta, p_analista, p_busqueda, p_motivo, p_lead);
$$;

-- ---------------------------------------------------------------------------
-- Mundo mínimo: A (responsable), B y C (otras carteras); personas c1, c2 y c3 (fusionada en c1).
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data)
select v.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v.correo, '', now(), now(), now(),
       '', '', '', '', '{"provider":"email"}', '{}'
  from (values ('f1000000-0000-4000-8000-00000000000a'::uuid, 'vc.fase1.a@avancecorp.test'),
               ('f1000000-0000-4000-8000-00000000000b'::uuid, 'vc.fase1.b@avancecorp.test'),
               ('f1000000-0000-4000-8000-00000000000c'::uuid, 'vc.fase1.c@avancecorp.test')) v(id, correo)
on conflict (id) do nothing;
insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password,
  titular_distinto, titular_distinto_usd)
values
  ('f1000000-0000-4000-8000-00000000000a','VC FASE1 ANALISTA A','analista',true,'DNI',false,false,false),
  ('f1000000-0000-4000-8000-00000000000b','VC FASE1 ANALISTA B','analista',true,'DNI',false,false,false),
  ('f1000000-0000-4000-8000-00000000000c','VC FASE1 ANALISTA C','analista',true,'DNI',false,false,false)
on conflict (id) do update set activo = true;
insert into crm.inversionistas (id, estado, responsable_relacion_id) values
  ('f1000000-0000-4000-8000-0000000000c1','activo','f1000000-0000-4000-8000-00000000000a'),
  ('f1000000-0000-4000-8000-0000000000c2','activo','f1000000-0000-4000-8000-00000000000a');
insert into crm.inversionistas (id, estado, inversionista_canonico_id, fusionado_en) values
  ('f1000000-0000-4000-8000-0000000000c3','fusionado','f1000000-0000-4000-8000-0000000000c1', now());

create temporary table t_ctx on commit drop as
select (select id from crm.empresas where clave = 'avance') as avance,
       (select id from crm.empresas where clave = 'qorilazo') as qorilazo;

-- ---------------------------------------------------------------------------
-- 1. Bitácora: formas válidas
-- ---------------------------------------------------------------------------
insert into crm.busquedas_cliente_existente (id, consultado_por, criterio, tipo_documento, valor_consultado, veredicto, inversionista_id, creado_en)
values
  -- d1: la llave buena de B sobre c1.
  ('f1000000-0000-4000-8000-0000000000d1','f1000000-0000-4000-8000-00000000000b','documento','DNI','48000001','encontrado','f1000000-0000-4000-8000-0000000000c1', now()),
  -- d2: la llave buena de A sobre c1.
  ('f1000000-0000-4000-8000-0000000000d2','f1000000-0000-4000-8000-00000000000a','documento','DNI','48000001','encontrado','f1000000-0000-4000-8000-0000000000c1', now()),
  -- d3: B, por teléfono, aunque «encontrado».
  ('f1000000-0000-4000-8000-0000000000d3','f1000000-0000-4000-8000-00000000000b','telefono',null,'+51987000001','encontrado','f1000000-0000-4000-8000-0000000000c1', now()),
  -- d4: B, no operable (nombra a la persona).
  ('f1000000-0000-4000-8000-0000000000d4','f1000000-0000-4000-8000-00000000000b','documento','DNI','48000001','no_operable','f1000000-0000-4000-8000-0000000000c1', now()),
  -- d5: B, de hace 3 horas.
  ('f1000000-0000-4000-8000-0000000000d5','f1000000-0000-4000-8000-00000000000b','documento','DNI','48000001','encontrado','f1000000-0000-4000-8000-0000000000c1', now() - interval '3 hours'),
  -- d6: B, sobre la otra persona c2.
  ('f1000000-0000-4000-8000-0000000000d6','f1000000-0000-4000-8000-00000000000b','documento','DNI','48000002','encontrado','f1000000-0000-4000-8000-0000000000c2', now()),
  -- d7: B, sobre la identidad fusionada c3 (canónica c1).
  ('f1000000-0000-4000-8000-0000000000d7','f1000000-0000-4000-8000-00000000000b','documento','DNI','48000003','encontrado','f1000000-0000-4000-8000-0000000000c3', now());
insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
values ('f1000000-0000-4000-8000-00000000000b','telefono','+51987000009','ambiguo');
insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto)
values ('f1000000-0000-4000-8000-00000000000b','documento','CE','001234567','no_operable');
select pg_temp.exigir((select count(*) from crm.busquedas_cliente_existente
  where consultado_por in ('f1000000-0000-4000-8000-00000000000a','f1000000-0000-4000-8000-00000000000b')) = 9,
  'las 9 búsquedas válidas se registran');

-- 2. Bitácora: formas inválidas
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','documento','48000001','no_encontrado')$q$, '23514', 'busqueda_cliente_documento_coherente');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','telefono','DNI','+51987000001','no_encontrado')$q$, '23514', 'busqueda_cliente_documento_coherente');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','lead','x','no_encontrado')$q$, '23514', 'busqueda_cliente_lead_coherente');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','documento','DNI','48000001','encontrado')$q$, '23514', 'busqueda_cliente_persona_coherente');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto, inversionista_id)
  values ('f1000000-0000-4000-8000-00000000000b','documento','DNI','48000001','ambiguo','f1000000-0000-4000-8000-0000000000c1')$q$, '23514', 'busqueda_cliente_persona_coherente');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','documento','RUC','20123456789','no_encontrado')$q$, '23514', 'busqueda_cliente_tipo_valido');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','telefono',repeat('9',65),'no_encontrado')$q$, '23514', 'busqueda_cliente_valor_acotado');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','telefono','','invalido')$q$, '23514', 'busqueda_cliente_valor_acotado');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','nombre','PEREZ','no_encontrado')$q$, '23514', 'busqueda_cliente_criterio_valido');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','telefono','+51987000001','quizas')$q$, '23514', 'busqueda_cliente_veredicto_valido');

-- 3. Bitácora inmutable: ni UPDATE, ni DELETE, ni TRUNCATE
select pg_temp.rechaza($q$update crm.busquedas_cliente_existente set veredicto = 'no_encontrado'
  where id = 'f1000000-0000-4000-8000-0000000000d1'$q$, 'P0409', 'no se modifica');
select pg_temp.rechaza($q$delete from crm.busquedas_cliente_existente
  where id = 'f1000000-0000-4000-8000-0000000000d1'$q$, 'P0409', 'no se modifica');
select pg_temp.rechaza('truncate crm.busquedas_cliente_existente cascade', 'P0409', 'no se modifica');

-- 4. Auditoría: la búsqueda deja rastro, pero el valor buscado va enmascarado
select pg_temp.exigir(exists (select 1 from public.audit_log a
  where a.tabla = 'crm.busquedas_cliente_existente' and a.operacion = 'INSERT'
    and a.fila_id = 'f1000000-0000-4000-8000-0000000000d1'
    and a.data_despues ->> 'valor_consultado' = '***'
    and a.data_despues ->> 'veredicto' = 'encontrado'), 'la auditoría registra la búsqueda con el valor enmascarado');
select pg_temp.exigir(not exists (select 1 from public.audit_log a
  where a.tabla = 'crm.busquedas_cliente_existente' and a.data_despues::text like '%48000001%'),
  'el documento buscado no aparece en claro en public.audit_log');

-- 5. Sin lectura ni escritura directa para los roles de la API
select set_config('request.jwt.claims', json_build_object('sub','f1000000-0000-4000-8000-00000000000b','role','authenticated')::text, true);
set local role authenticated;
select pg_temp.rechaza('select count(*) from crm.busquedas_cliente_existente', '42501');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','telefono','+51987000001','no_encontrado')$q$, '42501');
select pg_temp.rechaza($q$update crm.busquedas_cliente_existente set veredicto = 'no_encontrado'$q$, '42501');
select pg_temp.rechaza($q$delete from crm.busquedas_cliente_existente$q$, '42501');
reset role;
set local role anon;
select pg_temp.rechaza('select count(*) from crm.busquedas_cliente_existente', '42501');
reset role;
set local role service_role;
select pg_temp.rechaza('select count(*) from crm.busquedas_cliente_existente', '42501');
select pg_temp.rechaza($q$insert into crm.busquedas_cliente_existente (consultado_por, criterio, valor_consultado, veredicto)
  values ('f1000000-0000-4000-8000-00000000000b','telefono','+51987000001','no_encontrado')$q$, '42501');
reset role;

-- ---------------------------------------------------------------------------
-- 6. Solicitudes: la regla de hoy sigue igual
-- ---------------------------------------------------------------------------
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos, creado_por)
select 'f1000000-0000-4000-8000-0000000000e0','f1000000-0000-4000-8000-0000000000c1', avance,
       'f1000000-0000-4000-8000-00000000000a', md5('e0') || md5('e0x'), '{"empresa":"avance"}',
       'f1000000-0000-4000-8000-00000000000a' from t_ctx;
select pg_temp.exigir((select puerta = 'cartera' and analista_cierre_id is null and motivo_atribucion is null
  and busqueda_id is null from crm.inversion_solicitudes where id = 'f1000000-0000-4000-8000-0000000000e0'),
  'una solicitud de cartera nace con la regla de hoy');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000a', 'cartera', 'f1000000-0000-4000-8000-00000000000b', null, null),
  '23514', 'inversion_solicitud_atribucion_coherente');

-- 7. Venta cruzada: todo o nada
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d1', null), '23514', 'inversion_solicitud_atribucion_coherente');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d1', '   corto   '), '23514', 'inversion_solicitud_atribucion_coherente');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d1', E'\t\t\t\t\t\t\t\t\t\tabc\n\n\n\n'), '23514', 'inversion_solicitud_atribucion_coherente');
-- La venta es siempre de quien la registra.
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000c',
  'f1000000-0000-4000-8000-0000000000d1', 'El cliente llamó directamente a B para invertir'), '23514', 'inversion_solicitud_atribucion_coherente');
-- Nunca desde un lead.
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d1', 'El cliente llamó directamente a B para invertir',
  'f1000000-0000-4000-8000-0000000000ff'), '23514', 'inversion_solicitud_atribucion_coherente');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'otra', null, null, null), '23514', 'check constraint');

-- 8. La llave: búsqueda propia, por documento, «encontrado», misma persona y reciente
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d2', 'Usa la búsqueda que hizo A, no la suya'), '22023', 'búsqueda propia');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d3', 'Encontró al cliente solo por teléfono'), '22023', 'búsqueda propia');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d4', 'La búsqueda dijo que no admite inversiones'), '22023', 'búsqueda propia');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d5', 'La búsqueda es de hace tres horas'), '22023', 'búsqueda propia');
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000b', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000b',
  'f1000000-0000-4000-8000-0000000000d6', 'La búsqueda encontró a otra persona'), '22023', 'búsqueda propia');

-- 9. Alta válida (y por la identidad fusionada: la búsqueda de c3 abre c1)
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos,
  creado_por, puerta, analista_cierre_id, busqueda_id, motivo_atribucion)
select 'f1000000-0000-4000-8000-0000000000e1','f1000000-0000-4000-8000-0000000000c1', avance,
       'f1000000-0000-4000-8000-00000000000a', md5('e1') || md5('e1x'), '{"empresa":"avance"}',
       'f1000000-0000-4000-8000-00000000000b','cliente_existente','f1000000-0000-4000-8000-00000000000b',
       'f1000000-0000-4000-8000-0000000000d1','El cliente llamó directamente a B para invertir' from t_ctx;
select pg_temp.exigir((select responsable_esperado_id = 'f1000000-0000-4000-8000-00000000000a'
  and analista_cierre_id = 'f1000000-0000-4000-8000-00000000000b' and creado_por = 'f1000000-0000-4000-8000-00000000000b'
  from crm.inversion_solicitudes where id = 'f1000000-0000-4000-8000-0000000000e1'),
  'la venta cruzada guarda por separado responsable (A), analista (B) y quién la creó (B)');
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos,
  creado_por, puerta, analista_cierre_id, busqueda_id, motivo_atribucion)
select 'f1000000-0000-4000-8000-0000000000e2','f1000000-0000-4000-8000-0000000000c1', qorilazo,
       'f1000000-0000-4000-8000-00000000000a', md5('e2') || md5('e2x'), '{"empresa":"qorilazo"}',
       'f1000000-0000-4000-8000-00000000000b','cliente_existente','f1000000-0000-4000-8000-00000000000b',
       'f1000000-0000-4000-8000-0000000000d7','La búsqueda por la identidad fusionada vale para la canónica' from t_ctx;

-- 10. D6: una sola venta cruzada en preparación por persona y empresa
select pg_temp.rechaza(pg_temp.sol(gen_random_uuid()::text, 'f1000000-0000-4000-8000-0000000000c1', (select avance from t_ctx),
  'f1000000-0000-4000-8000-00000000000a', 'cliente_existente', 'f1000000-0000-4000-8000-00000000000a',
  'f1000000-0000-4000-8000-0000000000d2', 'Otro analista intenta la misma venta a la vez'), '23505', 'inversion_solicitud_cruzada_pendiente');
update crm.inversion_solicitudes set estado = 'cancelada' where id = 'f1000000-0000-4000-8000-0000000000e1';
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos,
  creado_por, puerta, analista_cierre_id, busqueda_id, motivo_atribucion)
select 'f1000000-0000-4000-8000-0000000000e3','f1000000-0000-4000-8000-0000000000c1', avance,
       'f1000000-0000-4000-8000-00000000000a', md5('e3') || md5('e3x'), '{"empresa":"avance"}',
       'f1000000-0000-4000-8000-00000000000a','cliente_existente','f1000000-0000-4000-8000-00000000000a',
       'f1000000-0000-4000-8000-0000000000d2','Segunda solicitud tras cancelar la primera' from t_ctx;

-- 11. La atribución (y la persona de una venta cruzada) no cambian después del alta
select pg_temp.rechaza($q$update crm.inversion_solicitudes set analista_cierre_id = 'f1000000-0000-4000-8000-00000000000b'
  where id = 'f1000000-0000-4000-8000-0000000000e3'$q$, '22023', 'La atribución de una solicitud es inmutable');
select pg_temp.rechaza($q$update crm.inversion_solicitudes set motivo_atribucion = 'Motivo cambiado después del alta'
  where id = 'f1000000-0000-4000-8000-0000000000e3'$q$, '22023', 'La atribución de una solicitud es inmutable');
select pg_temp.rechaza($q$update crm.inversion_solicitudes set busqueda_id = 'f1000000-0000-4000-8000-0000000000d1'
  where id = 'f1000000-0000-4000-8000-0000000000e3'$q$, '22023', 'La atribución de una solicitud es inmutable');
select pg_temp.rechaza($q$update crm.inversion_solicitudes set inversionista_id = 'f1000000-0000-4000-8000-0000000000c2'
  where id = 'f1000000-0000-4000-8000-0000000000e3'$q$, '22023', 'La atribución de una solicitud es inmutable');
select pg_temp.rechaza($q$update crm.inversion_solicitudes set puerta = 'cartera', analista_cierre_id = null,
  busqueda_id = null, motivo_atribucion = null where id = 'f1000000-0000-4000-8000-0000000000e3'$q$,
  '22023', 'La atribución de una solicitud es inmutable');
update crm.inversion_solicitudes set estado = 'cancelada', actualizado_en = statement_timestamp()
  where id = 'f1000000-0000-4000-8000-0000000000e3';

-- 12. El candado de origen que ya existía sigue vivo al lado de los nuevos
select pg_temp.rechaza($q$update crm.inversion_solicitudes set lead_origen_id = 'f1000000-0000-4000-8000-0000000000ff'
  where id = 'f1000000-0000-4000-8000-0000000000e0'$q$, '22023', 'El origen de una solicitud es inmutable');

-- 13. Auditoría de solicitudes: ve la atribución y enmascara datos y motivo
select pg_temp.exigir(exists (select 1 from public.audit_log a
  where a.tabla = 'crm.inversion_solicitudes' and a.fila_id = 'f1000000-0000-4000-8000-0000000000e1'
    and a.operacion = 'INSERT' and a.data_despues ->> 'datos' = '***'
    and a.data_despues ->> 'motivo_atribucion' = '***'
    and a.data_despues ->> 'analista_cierre_id' = 'f1000000-0000-4000-8000-00000000000b'
    and a.data_despues ->> 'puerta' = 'cliente_existente'), 'la auditoría registra la atribución y enmascara el motivo');
select pg_temp.exigir(not exists (select 1 from public.audit_log a
  where a.tabla = 'crm.inversion_solicitudes' and a.data_despues::text like '%llamó directamente%'),
  'el motivo no aparece en claro en public.audit_log');

select 'VENTA_CRUZADA_FASE1_OK' as veredicto;
rollback;
