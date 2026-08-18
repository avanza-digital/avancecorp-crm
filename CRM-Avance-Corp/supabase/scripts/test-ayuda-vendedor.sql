\set ON_ERROR_STOP on

-- Oráculo transaccional del Centro de ayuda del vendedor.
-- Éxito = AYUDA_VENDEDOR_TX_OK; no deja usuarios ni telemetría de prueba.
begin;

-- Catálogo, índices y extensiones.
do $test$
declare
  v_total integer;
begin
  select count(*) into v_total from private.ayuda_intenciones where estado = 'publicado';
  if v_total <> 17 then raise exception 'A01: se esperaban 17 guías, hay %', v_total; end if;

  select count(*) into v_total from private.ayuda_expresiones;
  if v_total <> 112 then raise exception 'A02: se esperaban 112 expresiones, hay %', v_total; end if;

  select count(*) into v_total from private.ayuda_reglas_aclaracion where activa;
  if v_total <> 3 then raise exception 'A03: se esperaban 3 reglas, hay %', v_total; end if;

  if not exists (
    select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'unaccent' and n.nspname = 'extensions'
  ) or not exists (
    select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'pg_trgm' and n.nspname = 'extensions'
  ) then
    raise exception 'A04: unaccent/pg_trgm no están en extensions';
  end if;

  if (
    select count(*)
    from pg_indexes
    where schemaname = 'private'
      and indexname in (
        'ayuda_expresiones_texto_normalizado_key',
        'ayuda_expresiones_vector_idx',
        'ayuda_expresiones_trgm_idx',
        'ayuda_expresiones_intencion_idx',
        'ayuda_consultas_intencion_idx',
        'ayuda_consultas_retencion_idx'
      )
  ) <> 6 then
    raise exception 'A05: faltan índices exacto/FTS/trigram/FK/retención';
  end if;

  if exists (
    select 1
    from private.ayuda_intenciones i
    where not (
      i.contenido ?& array['id','titulo','resumen','duracion','pasos','accion','fuente']
      and jsonb_typeof(i.contenido -> 'pasos') = 'array'
      and jsonb_array_length(i.contenido -> 'pasos') between 1 and 8
    )
  ) then
    raise exception 'A06: una guía no cumple el contenido mínimo';
  end if;
end;
$test$;

-- Las versiones publicadas son inmutables.
do $test$
begin
  begin
    update private.ayuda_intenciones
    set pregunta = pregunta || ' alterada'
    where clave = 'registrar-lead' and estado = 'publicado';
    raise exception 'A07: se pudo modificar una guía publicada';
  exception when check_violation then
    null;
  end;
end;
$test$;

-- Actor CRM válido y usuario autenticado ajeno al CRM.
set local session_replication_role = replica;
insert into public.perfiles(id, nombre_completo, correo, rol, activo) values
  ('8a100000-0000-4000-8000-000000000001', 'ORACULO AYUDA VENDEDOR', 'ayuda-v@test.invalid', 'comercial', true),
  ('8a100000-0000-4000-8000-000000000002', 'ORACULO AYUDA AJENO', 'ayuda-a@test.invalid', 'cliente', true);
insert into crm.equipo(perfil_id, rol_crm, supervisor_id, activo) values
  ('8a100000-0000-4000-8000-000000000001', 'vendedor', null, true);
set local session_replication_role = origin;

-- Un registro vencido debe desaparecer en la siguiente consulta.
insert into private.ayuda_consultas (
  usuario_id, vista, consulta_redactada, longitud, resultado, motivo,
  creado_en, retener_hasta
) values (
  '8a100000-0000-4000-8000-000000000001', 'hoy', 'registro vencido', 15,
  'sin_resultado', 'oraculo_retencion', now() - interval '91 days', now() - interval '1 day'
);

select set_config('request.jwt.claim.sub', '8a100000-0000-4000-8000-000000000001', true);
set local role authenticated;

-- Las 17 preguntas canónicas resuelven exactamente la intención publicada.
do $test$
declare
  v_consulta text;
  v_esperada text;
  v jsonb;
begin
  for v_consulta, v_esperada in
    select * from (values
      ('¿Cómo elimino una acción que ya no voy a realizar?', 'anular-tarea-pendiente'),
      ('¿Cómo registro y empiezo a trabajar un lead?', 'registrar-lead'),
      ('¿Cómo llamo o escribo por WhatsApp y dejo registrada la gestión?', 'contactar-registrar-gestion'),
      ('¿Cómo corrijo o completo los datos de un lead?', 'editar-datos-lead'),
      ('¿Cómo agendo una llamada, WhatsApp o reunión?', 'agendar-siguiente-accion'),
      ('¿Cómo reprogramo una reunión?', 'reprogramar-reunion'),
      ('¿Cómo confirmo una reunión o envío un recordatorio?', 'confirmar-recordar-reunion'),
      ('¿Cómo marco que ya hice una llamada, tarea o reunión?', 'cerrar-tarea-resultado'),
      ('¿Cuándo marco No asistió?', 'marcar-no-asistio'),
      ('¿Puedo borrar una gestión que ya registré?', 'corregir-actividad-registrada'),
      ('¿Cómo cambio un lead de etapa en el proceso?', 'mover-etapa-lead'),
      ('¿Cómo descarto un lead que ya no continuará?', 'descartar-lead'),
      ('¿Cómo convierto un lead en cliente después del cierre?', 'convertir-lead-cliente'),
      ('¿Dónde busco a una persona: en Leads o en Mi cartera?', 'buscar-lead-cliente'),
      ('¿Qué hago si el CRM dice que el celular ya existe o está ocupado?', 'contacto-ya-existe'),
      ('¿Cómo creo el contrato de un cliente?', 'crear-contrato'),
      ('¿Qué hago si falló el PDF del contrato?', 'reintentar-pdf')
    ) as casos(consulta, esperada)
  loop
    v := crm.consultar_ayuda_vendedor(v_consulta, 'hoy');
    if v ->> 'tipo' <> 'respuesta'
       or v #>> '{respuesta,id}' <> v_esperada
       or (v ->> 'version')::integer <> 1 then
      raise exception 'A08: % resolvió %, esperado %', v_consulta, v, v_esperada;
    end if;
    if v ?| array['puntuacion','segunda_puntuacion','motivo'] then
      raise exception 'A09: el contrato filtró observabilidad interna: %', v;
    end if;
  end loop;
end;
$test$;

-- Cada una de las expresiones publicadas debe seguir resolviendo su propia
-- intención, aunque no sea una de las preguntas visibles del inicio.
reset role;
do $test$
declare
  v_expresion record;
  v jsonb;
begin
  for v_expresion in
    select e.texto, i.clave
    from private.ayuda_expresiones e
    join private.ayuda_intenciones i on i.id = e.intencion_id
    where i.estado = 'publicado'
    order by i.clave, e.id
  loop
    v := crm.consultar_ayuda_vendedor(v_expresion.texto, 'hoy');
    if v ->> 'tipo' <> 'respuesta'
       or v #>> '{respuesta,id}' <> v_expresion.clave then
      raise exception 'A08b: expresión % resolvió %, esperado %',
        v_expresion.texto, v, v_expresion.clave;
    end if;
  end loop;
end;
$test$;
set local role authenticated;

-- Lenguaje cotidiano, tildes y errores tipográficos conservando el objeto.
do $test$
declare
  v_consulta text;
  v_esperada text;
  v jsonb;
begin
  for v_consulta, v_esperada in
    select * from (values
      ('como elimino una accion', 'anular-tarea-pendiente'),
      ('CÓMO ELIMINO UNA ACCIÓN', 'anular-tarea-pendiente'),
      ('quiero sacar un pendiente', 'anular-tarea-pendiente'),
      ('como elimino una actividad', 'corregir-actividad-registrada'),
      ('como elimno una accion pendiente', 'anular-tarea-pendiente'),
      ('quiero reprogramr una reunion', 'reprogramar-reunion'),
      ('quiero actualizr el correo', 'editar-datos-lead'),
      ('quiero reintentarr el pdf', 'reintentar-pdf'),
      ('como marco que ya llame', 'contactar-registrar-gestion'),
      ('me dejo plantado', 'marcar-no-asistio'),
      ('el numero ya esta registrado', 'contacto-ya-existe'),
      ('ya cerre la venta', 'convertir-lead-cliente'),
      ('quiero actualizar el correo', 'editar-datos-lead'),
      ('como lo paso a contactado', 'mover-etapa-lead'),
      ('quiero hacer el contrato', 'crear-contrato')
    ) as casos(consulta, esperada)
  loop
    v := crm.consultar_ayuda_vendedor(v_consulta, 'agenda');
    if v ->> 'tipo' <> 'respuesta' or v #>> '{respuesta,id}' <> v_esperada then
      raise exception 'A10: % resolvió %, esperado %', v_consulta, v, v_esperada;
    end if;
  end loop;
end;
$test$;

-- Las ambigüedades nunca se fuerzan como respuesta.
do $test$
declare
  v_consulta text;
  v jsonb;
begin
  foreach v_consulta in array array[
    'quiero eliminar algo',
    'necesito cambiar algo',
    'como marco que ya lo hice'
  ]
  loop
    v := crm.consultar_ayuda_vendedor(v_consulta, 'hoy');
    if v ->> 'tipo' <> 'aclaracion'
       or jsonb_array_length(v #> '{aclaracion,opciones}') not between 2 and 3 then
      raise exception 'A11: la ambigüedad % no pidió aclaración: %', v_consulta, v;
    end if;
  end loop;
end;
$test$;

-- Conflictos críticos y temas ajenos: se admite aclarar o no responder, jamás
-- recomendar una operación concreta.
do $test$
declare
  v_consulta text;
  v jsonb;
begin
  foreach v_consulta in array array[
    'como registro una cobranza bancaria',
    'quiero comprar una agenda para mi oficina',
    'como cancelo el contrato',
    'como genero el contrto',
    'quiero borrar el cliente',
    'quiero borrar el historial de pagos',
    'donde genero una factura',
    'como cambio mi contraseña',
    'cual es el tipo de cambio del dolar',
    'como elimino una acción judicial'
  ]
  loop
    v := crm.consultar_ayuda_vendedor(v_consulta, 'agenda');
    if v ->> 'tipo' = 'respuesta' then
      raise exception 'A12: recomendación incorrecta para %: %', v_consulta, v;
    end if;
  end loop;
end;
$test$;

-- La pantalla no convierte una consulta desconocida en respuesta.
do $test$
declare
  v_agenda jsonb := crm.consultar_ayuda_vendedor('necesito ayuda con una transferencia bancaria', 'agenda');
  v_cartera jsonb := crm.consultar_ayuda_vendedor('necesito ayuda con una transferencia bancaria', 'cartera');
  v_inicio jsonb := crm.ayuda_vendedor_inicio('agenda');
begin
  if v_agenda ->> 'tipo' <> 'sin_resultado'
     or v_cartera ->> 'tipo' <> 'sin_resultado' then
    raise exception 'A13: la vista forzó una respuesta: agenda %, cartera %', v_agenda, v_cartera;
  end if;
  if (v_inicio ->> 'version')::integer <> 1
     or jsonb_array_length(v_inicio -> 'preguntas') <> 6
     or not (v_inicio -> 'preguntas') ? '¿Cómo reprogramo una reunión?' then
    raise exception 'A14: inicio contextual inválido: %', v_inicio;
  end if;
end;
$test$;

-- Genera telemetría con nombre, teléfono, DNI y correo para revisar redacción.
select crm.consultar_ayuda_vendedor(
  'Juan Perez pregunta como elimino una accion 987654321 DNI 12345678 juan.perez@example.com',
  'agenda'
);

-- La tabla privada no es legible directamente por authenticated.
do $test$
begin
  begin
    perform count(*) from private.ayuda_intenciones;
    raise exception 'A15: authenticated pudo leer la tabla privada';
  exception when insufficient_privilege then
    null;
  end;
end;
$test$;

reset role;

-- PII, retención y privilegios desde el dueño de la migración.
do $test$
declare
  v_redactada text;
  v_fn regprocedure;
begin
  select consulta_redactada
  into v_redactada
  from private.ayuda_consultas
  where usuario_id = '8a100000-0000-4000-8000-000000000001'
  order by id desc
  limit 1;

  if v_redactada ~* '(juan|perez|987654321|12345678|example|@)'
     or position('[numero]' in v_redactada) = 0
     or position('[correo]' in v_redactada) = 0 then
    raise exception 'A16: PII sin redactar: %', v_redactada;
  end if;

  if exists (
    select 1 from private.ayuda_consultas where motivo = 'oraculo_retencion'
  ) then
    raise exception 'A17: la retención no eliminó telemetría vencida';
  end if;

  foreach v_fn in array array[
    'crm.ayuda_vendedor_inicio(text)'::regprocedure,
    'crm.consultar_ayuda_vendedor(text,text)'::regprocedure
  ]
  loop
    if not has_function_privilege('authenticated', v_fn, 'execute')
       or has_function_privilege('anon', v_fn, 'execute')
       or has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'A18: ACL pública incorrecta en %', v_fn;
    end if;
    if not exists (
      select 1 from pg_proc p
      where p.oid = v_fn
        and p.prosecdef
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'A19: falta security definer/search_path vacío en %', v_fn;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'private.ayuda_intenciones', 'select')
     or has_table_privilege('authenticated', 'private.ayuda_consultas', 'select') then
    raise exception 'A20: authenticated tiene privilegio directo en tablas privadas';
  end if;
end;
$test$;

-- Un autenticado sin rol CRM recibe 42501.
select set_config('request.jwt.claim.sub', '8a100000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.consultar_ayuda_vendedor('como creo un lead', 'hoy');
    raise exception 'A21: usuario ajeno al CRM pudo consultar';
  exception when insufficient_privilege then
    null;
  end;
end;
$test$;
reset role;

-- Sin JWT también recibe 42501.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.ayuda_vendedor_inicio('hoy');
    raise exception 'A22: sesión sin identidad pudo consultar';
  exception when insufficient_privilege then
    null;
  end;
end;
$test$;
reset role;

-- Certificación visible de los índices de recuperación (se ejecutan de verdad).
set local enable_seqscan = off;
explain (analyze, buffers, costs off)
select e.id
from private.ayuda_expresiones e
where e.vector_busqueda @@ websearch_to_tsquery('spanish'::regconfig, 'reprogramar reunion');

explain (analyze, buffers, costs off)
select e.id
from private.ayuda_expresiones e
where e.texto_normalizado operator(extensions.%) 'quiero reprogramr una reunion';

rollback;
\echo AYUDA_VENDEDOR_TX_OK
