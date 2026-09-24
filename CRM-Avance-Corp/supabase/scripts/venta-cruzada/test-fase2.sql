-- Venta cruzada · Fase 2: prueba de la rama nueva de los núcleos (_para con LLAVES).
-- La paridad de las funciones de siempre la prueba paridad-permisos.sql (foto antes y
-- después). Esta prueba cubre lo NUEVO: qué abre y qué NO abre una llave (solicitud
-- de venta cruzada o búsqueda vigente), siempre atada a la persona canónica.
-- Una transacción que se deshace. Solo en el banco sintético con mundo.sql sembrado.
-- Veredicto como FILA: VENTA_CRUZADA_FASE2_OK.
begin;

do $guarda$ begin
  if (select count(*) from crm.leads) > 200 or (select count(*) from public.perfiles where rol = 'cliente') > 50 then
    raise exception 'Esta prueba solo corre en el banco sintético';
  end if;
  if to_regprocedure('private.inversion_persona_autorizada_para(uuid,uuid,uuid)') is null then
    raise exception 'La Fase 2 no está aplicada en este banco';
  end if;
end $guarda$;

create temporary table t2(clave text primary key, id uuid) on commit drop;
insert into t2 values
  ('G','c0000000-0000-4000-8000-000000000001'),('S1','c0000000-0000-4000-8000-000000000002'),
  ('S2','c0000000-0000-4000-8000-000000000003'),('A','c0000000-0000-4000-8000-000000000004'),
  ('A2','c0000000-0000-4000-8000-000000000005'),('B','c0000000-0000-4000-8000-000000000006'),
  ('C','c0000000-0000-4000-8000-000000000007'),('D','c0000000-0000-4000-8000-000000000008'),
  ('DIR','c0000000-0000-4000-8000-000000000009'),('E','c0000000-0000-4000-8000-0000000000e5'),
  ('LEAD_T','c0000000-0000-4000-8000-000000000071');
insert into t2 select 'X', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000021';
insert into t2 select 'W', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000025';
insert into t2 select v.e, d.inversionista_id from (values ('Z','70000024'),('V','70000026'),('T','70000027'),('Y','70000029')) v(e, doc)
  join crm.inversionista_identificadores d on d.tipo_documento = 'DNI' and d.documento_normalizado = v.doc;

-- E: vendedor del equipo de S2 que ya dejó el equipo (para el caso del analista inactivo).
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data)
values ('c0000000-0000-4000-8000-0000000000e5','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'vc.e@avancecorp.test','',now(),now(),now(),'','','','','{"provider":"email"}','{}');
insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, dni, debe_cambiar_password, titular_distinto, titular_distinto_usd)
values ('c0000000-0000-4000-8000-0000000000e5','VC ANALISTA E','analista',true,'DNI','71000011',false,false,false);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values ('c0000000-0000-4000-8000-0000000000e5','vendedor','c0000000-0000-4000-8000-000000000003',true);

-- Búsquedas (la bitácora es inmutable: se fijan aquí con su hora).
do $$ declare v uuid; begin
  insert into crm.busquedas_cliente_existente (id, consultado_por, criterio, tipo_documento, valor_consultado, veredicto, inversionista_id, creado_en)
  select gen_random_uuid(), (select id from t2 where clave = x.actor), x.criterio,
         case when x.criterio = 'documento' then 'DNI' end, '70000000', 'encontrado',
         (select id from t2 where clave = x.persona), now() - x.hace
    from (values ('bB_X','B','X','documento','0 minutes'::interval), ('bB_V','B','V','documento','0 minutes'),
                 ('bB_Y','B','Y','documento','0 minutes'), ('bC_X','C','X','documento','0 minutes'),
                 ('bB_X_viejo','B','X','documento','3 hours'), ('bB_X_tel','B','X','telefono','0 minutes'),
                 ('bB_W','B','W','documento','0 minutes'), ('bB_Z','B','Z','documento','0 minutes'),
                 ('bB_T','B','T','documento','0 minutes'), ('bE_X','E','X','documento','0 minutes'))
         x(clave, actor, persona, criterio, hace);
end $$;
-- Recupera los ids por (actor, persona, criterio, antigüedad).
insert into t2
select v.clave, b.id from (values
    ('bB_X','B','X','documento',false), ('bB_V','B','V','documento',false), ('bB_Y','B','Y','documento',false),
    ('bC_X','C','X','documento',false), ('bB_X_viejo','B','X','documento',true), ('bB_X_tel','B','X','telefono',false),
    ('bB_W','B','W','documento',false), ('bB_Z','B','Z','documento',false), ('bB_T','B','T','documento',false),
    ('bE_X','E','X','documento',false)) v(clave, actor, persona, criterio, viejo)
  join crm.busquedas_cliente_existente b
    on b.consultado_por = (select id from t2 where clave = v.actor)
   and b.inversionista_id = (select id from t2 where clave = v.persona)
   and b.criterio = v.criterio
   and (b.creado_en < now() - interval '1 hour') = v.viejo;
do $$ begin
  if (select count(*) from t2 where clave like 'b%') <> 10 then raise exception 'FASE2: faltan búsquedas de prueba'; end if;
end $$;

-- Solicitudes: una venta cruzada de B y otra de E sobre X, y una de cartera de A sobre X.
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos,
  creado_por, puerta, analista_cierre_id, busqueda_id, motivo_atribucion)
select x.id, (select id from t2 where clave = 'X'), (select id from crm.empresas where clave = x.empresa),
       (select id from t2 where clave = 'A'), md5(x.id::text) || md5(x.id::text || 'x'), '{}'::jsonb,
       (select id from t2 where clave = x.actor), 'cliente_existente', (select id from t2 where clave = x.actor),
       (select id from t2 where clave = x.busq), 'El cliente pidió invertir con este analista'
  from (values ('c0000000-0000-4000-8000-0000000000f1'::uuid,'B','bB_X','avance'),
               ('c0000000-0000-4000-8000-0000000000f2'::uuid,'E','bE_X','qorilazo')) x(id, actor, busq, empresa);
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos, creado_por)
values ('c0000000-0000-4000-8000-0000000000f3', (select id from t2 where clave = 'X'),
        (select id from crm.empresas where clave = 'avance'), (select id from t2 where clave = 'A'),
        md5('f3') || md5('f3x'), '{}', (select id from t2 where clave = 'A'));
insert into t2 values ('sB_X','c0000000-0000-4000-8000-0000000000f1'), ('sE_X','c0000000-0000-4000-8000-0000000000f2'),
  ('sA_cartera','c0000000-0000-4000-8000-0000000000f3');
-- E deja el equipo después de registrar su solicitud.
set local session_replication_role = replica;
update crm.equipo set activo = false where perfil_id = 'c0000000-0000-4000-8000-0000000000e5';
set local session_replication_role = origin;

-- caso(actor, funcion, persona, lead, solicitud, busqueda) → 'OK <persona canónica>' o 'ERR <sqlstate> <mensaje>'
create function pg_temp.caso(p_actor text, p_funcion text, p_persona text, p_lead text, p_sol text, p_busq text)
returns text language plpgsql as $$
declare v_actor uuid := (select id from t2 where clave = p_actor);
  v_p uuid := (select id from t2 where clave = p_persona);
  v_l uuid := (select id from t2 where clave = p_lead);
  v_s uuid := (select id from t2 where clave = p_sol);
  v_b uuid := (select id from t2 where clave = p_busq);
  r jsonb;
begin
  perform set_config('request.jwt.claims', case when v_actor is null then '' else
    json_build_object('sub', v_actor, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(v_actor::text, ''), true);
  r := case p_funcion
    when 'autorizada' then private.inversion_persona_autorizada_para(v_p, v_s, v_b)
    when 'lectura' then private.inversion_persona_lectura_para(v_p, v_s, v_b)
    when 'contexto' then private.inversion_persona_contexto_para(v_p, v_l, v_s, v_b)
    when 'contexto_lectura' then private.inversion_contexto_lectura_para(v_p, v_l, v_s, v_b) end;
  return 'OK ' || (r ->> 'inversionista_id');
exception when others then
  return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp.espera(p_obtenido text, p_esperado text, p_caso text) returns void language plpgsql as $$
begin
  if p_obtenido is distinct from p_esperado and position(p_esperado in p_obtenido) <> 1 then
    raise exception 'FASE2 %: esperado «%», obtenido «%»', p_caso, p_esperado, p_obtenido;
  end if;
end $$;

do $pruebas$
declare x text := 'OK ' || (select id from t2 where clave = 'X'); f text;
  fuera text := 'ERR 42501 Persona no encontrada o fuera de tu ámbito';
  sin text := 'ERR 42501 No autorizado para registrar inversiones';
begin
  foreach f in array array['autorizada','lectura','contexto','contexto_lectura'] loop
    -- Sin llaves: la regla de siempre (B fuera, G dentro).
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, null, null), fuera, f || ': B sin llave');
    perform pg_temp.espera(pg_temp.caso('G', f, 'X', null, null, null), x, f || ': G sin llave');
    -- Búsqueda: solo la propia, vigente, por documento, de esta persona (o de su fusionada).
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, null, 'bB_X'), x, f || ': B con su búsqueda');
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, null, 'bB_V'), x, f || ': búsqueda de la fusionada V abre X');
    perform pg_temp.espera(pg_temp.caso('B', f, 'V', null, null, 'bB_X'), x, f || ': sobre V con búsqueda de X');
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, null, 'bB_Y'), fuera, f || ': búsqueda de otra persona');
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, null, 'bC_X'), fuera, f || ': búsqueda de C');
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, null, 'bB_X_viejo'), fuera, f || ': búsqueda vieja');
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, null, 'bB_X_tel'), fuera, f || ': búsqueda por teléfono');
    perform pg_temp.espera(pg_temp.caso('S2', f, 'X', null, null, 'bB_X'), fuera, f || ': S2 con la búsqueda de B');
    -- Solicitud: solo una venta cruzada de esta persona; la ve su analista y su cadena.
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, 'sB_X', null), x, f || ': B con su solicitud');
    perform pg_temp.espera(pg_temp.caso('S2', f, 'X', null, 'sB_X', null), x, f || ': S2 con la solicitud de B');
    perform pg_temp.espera(pg_temp.caso('C', f, 'X', null, 'sB_X', null), fuera, f || ': C con la solicitud de B');
    perform pg_temp.espera(pg_temp.caso('A2', f, 'X', null, 'sB_X', null), fuera, f || ': A2 con la solicitud de B');
    perform pg_temp.espera(pg_temp.caso('B', f, 'Y', null, 'sB_X', null), fuera, f || ': solicitud de X usada sobre Y');
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, 'sA_cartera', null), fuera, f || ': solicitud de cartera');
    perform pg_temp.espera(pg_temp.caso('B', f, 'X', null, 'sB_X', 'bB_X'), fuera, f || ': las dos llaves a la vez');
    -- Quien no opera inversiones sigue fuera, con cualquier llave.
    perform pg_temp.espera(pg_temp.caso('DIR', f, 'X', null, 'sB_X', null), sin, f || ': Directorio');
    perform pg_temp.espera(pg_temp.caso('D', f, 'X', null, 'sB_X', null), sin, f || ': D inactivo');
    perform pg_temp.espera(pg_temp.caso(null, f, 'X', null, 'sB_X', null), sin, f || ': sin sesión');
    -- Decisión documentada: el supervisor de un analista que dejó el equipo sigue
    -- pudiendo operar esa solicitud (p. ej. para cancelarla); confirmar exigirá un
    -- analista activo (Fase 3).
    perform pg_temp.espera(pg_temp.caso('S2', f, 'X', null, 'sE_X', null), x, f || ': S2 con la solicitud de E, inactivo');
    perform pg_temp.espera(pg_temp.caso('E', f, 'X', null, 'sE_X', null), sin, f || ': E ya no opera');
  end loop;

  foreach f in array array['contexto','contexto_lectura'] loop
    -- Las reglas del contexto siguen valiendo para la venta cruzada.
    perform pg_temp.espera(pg_temp.caso('B', f, 'W', null, null, 'bB_W'), 'ERR P0429 La persona no permite nuevas inversiones', f || ': W No insistir');
    perform pg_temp.espera(pg_temp.caso('B', f, 'Z', null, null, 'bB_Z'), 'ERR P0409 Asigna un responsable comercial activo', f || ': Z sin responsable');
    perform pg_temp.espera(pg_temp.caso('B', f, 'T', null, null, 'bB_T'), 'ERR P0409 Completa la conversión inicial', f || ': T con lead abierto (D4)');
    -- La venta cruzada nunca entra por el lead de otro.
    perform pg_temp.espera(pg_temp.caso('B', f, 'T', 'LEAD_T', null, 'bB_T'), 'ERR 42501 Lead no encontrado o fuera de tu ámbito', f || ': lead de A');
  end loop;
end $pruebas$;

select 'VENTA_CRUZADA_FASE2_OK' as veredicto;
rollback;
