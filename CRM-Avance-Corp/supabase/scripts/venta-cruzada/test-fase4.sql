-- Venta cruzada · Fase 4: las puertas de la venta cruzada, de punta a punta.
-- Búsqueda exacta (documento, teléfono normalizado, lead), rastro y tope; contexto,
-- cuentas enmascaradas y datos legales con UNA llave; preparación con motivo,
-- idempotencia y D6; confirmación atribuida a quien vende sin tocar al responsable; un
-- cliente con varias inversiones; transferencia de Gerencia; permisos del catálogo.
-- Todo por las funciones REALES. Una transacción que se deshace. Solo en el banco
-- sintético con mundo.sql sembrado. Veredicto como FILA: VENTA_CRUZADA_FASE4_OK.
-- La concurrencia (dos sesiones) va aparte: concurrencia-fase4.sh.
begin;
set local statement_timeout = '180s';

do $guarda$ begin
  if (select count(*) from crm.leads) > 200 or (select count(*) from public.perfiles where rol = 'cliente') > 50 then
    raise exception 'Esta prueba solo corre en el banco sintético';
  end if;
  if to_regprocedure('crm.buscar_cliente_existente_fn(text,text,text,uuid)') is null then
    raise exception 'La Fase 4 no está aplicada en este banco';
  end if;
end $guarda$;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('f4-comprobantes','f4-comprobantes', false, 10485760, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do nothing;

create temporary table t4(clave text primary key, id uuid) on commit drop;
insert into t4 values
  ('G','c0000000-0000-4000-8000-000000000001'),('S1','c0000000-0000-4000-8000-000000000002'),
  ('S2','c0000000-0000-4000-8000-000000000003'),('A','c0000000-0000-4000-8000-000000000004'),
  ('A2','c0000000-0000-4000-8000-000000000005'),('B','c0000000-0000-4000-8000-000000000006'),
  ('C','c0000000-0000-4000-8000-000000000007'),('DIR','c0000000-0000-4000-8000-000000000009'),
  ('CO','c0000000-0000-4000-8000-00000000000a'),('PX','c0000000-0000-4000-8000-000000000021'),
  ('PK','c0000000-0000-4000-8000-000000000031'),('PH','c0000000-0000-4000-8000-000000000032'),
  ('LB','c0000000-0000-4000-8000-000000000091'),('LK','c0000000-0000-4000-8000-000000000092'),
  ('LH','c0000000-0000-4000-8000-000000000093');
insert into t4 select 'X', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000021';

create function pg_temp.id(p text) returns uuid language sql stable as $$ select id from t4 where clave = p $$;
create function pg_temp.como(p text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when p is null then '' else
    json_build_object('sub', pg_temp.id(p), 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.id(p)::text, ''), true);
end $$;
create function pg_temp.exigir(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FASE4: %', mensaje; end if; end $$;
create function pg_temp.rechaza(p_sql text, p_estado text, p_texto text default null) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate = p_estado and (p_texto is null or position(p_texto in sqlerrm) > 0) then return; end if;
    raise exception 'FASE4: esperado % (%), obtenido %: %', p_estado, coalesce(p_texto,'-'), sqlstate, sqlerrm;
  end;
  raise exception 'FASE4: debió rechazar con %: %', p_estado, left(p_sql, 160);
end $$;
-- Búsqueda por documento de p_actor; guarda su id con la clave p_clave.
create function pg_temp.buscar(p_clave text, p_actor text, p_dni text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.como(p_actor);
  r := crm.buscar_cliente_existente_fn('DNI', p_dni, null, null);
  insert into t4 values (p_clave, (r->>'busqueda_id')::uuid) on conflict (clave) do update set id = excluded.id;
  return r;
end $$;
create function pg_temp.coop(p_empresa text, p_numero text, p_persona uuid, p_solicitud uuid) returns jsonb language sql as $$
  select jsonb_build_object('inversionista_id', p_persona, 'empresa', p_empresa, 'monto', 3000, 'moneda', 'PEN',
    'fecha_comercial', (statement_timestamp() at time zone 'America/Lima')::date,
    'vence_en', ((statement_timestamp() at time zone 'America/Lima')::date + interval '12 months')::date,
    'numero_transaccion', p_numero, 'referencia', 'REF ' || p_numero,
    'evidencia', jsonb_build_object('ruta', p_persona || '/' || p_solicitud || '/comprobante.pdf'));
$$;
create function pg_temp.avance(p_persona uuid, p_cuenta jsonb, p_categoria text default 'nuevo') returns jsonb language plpgsql as $$
declare inicio date := date_trunc('month', statement_timestamp() at time zone 'America/Lima')::date; cuotas jsonb;
begin
  select jsonb_agg(jsonb_build_object('numero_cuota', n, 'fecha_programada', (inicio + (n || ' months')::interval)::date,
    'monto_programado', 18.75, 'tipo', 'cuota') order by n) into cuotas from generate_series(1, 12) n;
  cuotas := cuotas || jsonb_build_array(jsonb_build_object('numero_cuota', 13,
    'fecha_programada', (inicio + interval '12 months 7 days')::date, 'monto_programado', 1500, 'tipo', 'retorno'));
  return jsonb_build_object('inversionista_id', p_persona, 'empresa', 'avance',
    'contrato', jsonb_build_object('categoria', p_categoria, 'capital', 1500, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple', 'fecha_inicio', inicio,
      'fecha_vencimiento', (inicio + interval '12 months')::date),
    'cronograma', cuotas, 'cuenta', p_cuenta);
end $$;

-- ===========================================================================
-- Accesorios de esta prueba (se deshacen con ella)
--   K: cliente con perfil y lead canónico CONVERTIDO de A (el caso normal en prod).
--   H: cliente con perfil y lead canónico ABIERTO de A (D4). Comparte teléfono con K.
--   LB: lead DESCARTADO de B con el DNI de X (la tarjeta «ya es cliente»).
-- ===========================================================================
select pg_temp.como(null);
do $accesorios$
declare e record;
begin
  for e in select * from (values
    ('c0000000-0000-4000-8000-000000000031','vc.k','VC CLIENTE KAPA LOPEZ','70000031'),
    ('c0000000-0000-4000-8000-000000000032','vc.h','VC CLIENTE HACHE','70000032')
  ) t(id, correo, nombre, dni) loop
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data)
    values (e.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      e.correo || '@avancecorp.test', '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}');
    insert into public.perfiles (id, nombre_completo, correo, rol, activo, tipo_documento, dni, asesor_perfil_id,
      debe_cambiar_password, titular_distinto, titular_distinto_usd, telefono, domicilio)
    values (e.id::uuid, e.nombre, e.correo || '@avancecorp.test', 'cliente', true, 'DNI', e.dni, pg_temp.id('A'),
      false, false, false, '987000031', 'AVENIDA SINTETICA 456 LIMA');
    perform private.asegurar_identidad_perfil(e.id::uuid, 'vc_prueba');
  end loop;
  insert into t4 select 'K', id from crm.inversionistas where perfil_id = pg_temp.id('PK');
  insert into t4 select 'H', id from crm.inversionistas where perfil_id = pg_temp.id('PH');
  update public.perfiles set domicilio = 'AVENIDA SINTETICA 123 LIMA' where id = pg_temp.id('PX');
  -- Una cuenta registrada de X para la venta Avance (D3).
  insert into crm.cuentas_bancarias (cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, activa, origen, creado_por)
  values (pg_temp.id('PX'), 'PEN', 'BANCO SINTETICO', 'ahorros', 'VC-PEN-4321', '99999999999999998765', false, true, 'contrato', pg_temp.id('A'));
end $accesorios$;
-- Los leads se siembran tal como quedan en prod tras convertir o descartar, sin sus
-- puertas (sentencias sueltas: el banco no permite este ajuste dentro de un bloque).
set local session_replication_role = replica;
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, moneda, origen, etapa, vendedor_id, dni, inversionista_id)
values (pg_temp.id('LK'), 'VC CLIENTE KAPA LOPEZ', '+51987000031', 3000, 'PEN', 'formulario', 'convertido', pg_temp.id('A'), '70000031', pg_temp.id('K')),
       (pg_temp.id('LH'), 'VC CLIENTE HACHE', '+51987000032', 3000, 'PEN', 'formulario', 'contactado', pg_temp.id('A'), '70000032', pg_temp.id('H'));
insert into crm.inversionista_leads (inversionista_id, lead_id, rol, creado_por)
values (pg_temp.id('K'), pg_temp.id('LK'), 'canonico', pg_temp.id('G')), (pg_temp.id('H'), pg_temp.id('LH'), 'canonico', pg_temp.id('G'));
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, moneda, origen, etapa, motivo_descarte, vendedor_id, dni)
values (pg_temp.id('LB'), 'VC PERSONA DESCARTADA', '+51987000099', 2000, 'PEN', 'formulario', 'descartado', 'sin_interes', pg_temp.id('B'), '70000021');
set local session_replication_role = origin;

do $pruebas$
declare
  r jsonb; r2 jsonb; d jsonb; s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid();
  s4 uuid := gen_random_uuid(); s5 uuid := gen_random_uuid(); cuenta uuid; contrato uuid; inv_antes bigint;
  s8 uuid := gen_random_uuid(); s9 uuid := gen_random_uuid(); s10 uuid := gen_random_uuid();
  perfiles_antes bigint; personas_antes bigint; leads_antes bigint; tramos_antes bigint; n bigint;
begin
  select count(*) into perfiles_antes from public.perfiles;
  select count(*) into personas_antes from crm.inversionistas;
  select count(*) into leads_antes from crm.leads;
  select count(*) into tramos_antes from crm.inversionista_responsables where inversionista_id = pg_temp.id('X');
  select id into cuenta from crm.cuentas_bancarias where cliente_id = pg_temp.id('PX') and cci = '99999999999999998765';

  -- =====================================================================
  -- 1. Búsqueda por documento: otro analista (B) encuentra a X, cliente de A
  -- =====================================================================
  r := pg_temp.buscar('bB', 'B', '70000021');
  perform pg_temp.exigir(r->>'estado' = 'encontrado' and r->>'criterio' = 'documento', 'B encuentra a X por DNI');
  perform pg_temp.exigir(r#>>'{cliente,inversionista_id}' = pg_temp.id('X')::text
    and r#>>'{cliente,nombre}' = 'VC CLIENTE X' and r#>>'{cliente,responsable_nombre}' = 'VC ANALISTA A'
    and r#>>'{cliente,documento_enmascarado}' = '•••••021' and not (r#>>'{cliente,es_mi_cartera}')::boolean,
    'la respuesta trae a X, su responsable y el documento enmascarado');
  perform pg_temp.exigir((r#>>'{acciones,nueva_inversion}')::boolean and not (r#>>'{acciones,ver_ficha}')::boolean,
    'B puede registrar una inversión nueva, no ver la ficha');
  perform pg_temp.exigir(not (r ? 'correo') and not (r->'cliente' ? 'telefono') and not (r->'cliente' ? 'correo'),
    'la búsqueda no devuelve correo ni teléfono');
  perform pg_temp.exigir((select consultado_por = pg_temp.id('B') and criterio = 'documento' and tipo_documento = 'DNI'
    and valor_consultado = '70000021' and veredicto = 'encontrado' and inversionista_id = pg_temp.id('X')
    from crm.busquedas_cliente_existente where id = pg_temp.id('bB')), 'la búsqueda queda en la bitácora');
  -- Documento con separadores: se normaliza.
  r := pg_temp.buscar('bB2', 'B', ' 7000-0021 ');
  perform pg_temp.exigir(r->>'estado' = 'encontrado' and r#>>'{cliente,inversionista_id}' = pg_temp.id('X')::text,
    'el documento se normaliza antes de buscar');

  -- =====================================================================
  -- 2. Mismo analista, su supervisor y Gerencia: X es de su cartera → ficha
  -- =====================================================================
  r := pg_temp.buscar('bA', 'A', '70000021');
  perform pg_temp.exigir((r#>>'{cliente,es_mi_cartera}')::boolean and (r#>>'{acciones,ver_ficha}')::boolean
    and not (r#>>'{acciones,nueva_inversion}')::boolean, 'para A, X es de su cartera: ver ficha');
  r := pg_temp.buscar('bS1', 'S1', '70000021');
  perform pg_temp.exigir((r#>>'{cliente,es_mi_cartera}')::boolean, 'para S1 (supervisor de A), X es de su cartera');
  r := pg_temp.buscar('bG', 'G', '70000021');
  perform pg_temp.exigir((r#>>'{cliente,es_mi_cartera}')::boolean and not (r#>>'{acciones,nueva_inversion}')::boolean,
    'Gerencia ve la ficha y no hace venta cruzada');
  perform pg_temp.como('A');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', gen_random_uuid(),
    pg_temp.id('bA'), pg_temp.avance(pg_temp.id('X'), jsonb_build_object('tipo','existente','cuenta_id',cuenta)),
    'El cliente pidió invertir de nuevo'), 'P0409', 'es de tu cartera');
  perform pg_temp.como('G');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', gen_random_uuid(),
    pg_temp.id('bG'), pg_temp.avance(pg_temp.id('X'), jsonb_build_object('tipo','existente','cuenta_id',cuenta)),
    'El cliente pidió invertir de nuevo'), '42501');
  perform pg_temp.como('DIR');
  perform pg_temp.rechaza($q$select crm.buscar_cliente_existente_fn('DNI','70000021',null,null)$q$, '42501');
  perform pg_temp.como('CO');
  perform pg_temp.rechaza($q$select crm.buscar_cliente_existente_fn('DNI','70000021',null,null)$q$, '42501');
  perform pg_temp.como(null);
  perform pg_temp.rechaza($q$select crm.buscar_cliente_existente_fn('DNI','70000021',null,null)$q$, '42501');

  -- =====================================================================
  -- 3. Teléfono normalizado: encuentra, pero con iniciales y sin llave
  -- =====================================================================
  perform pg_temp.como('B');
  for d in select jsonb_build_object('t', t) from unnest(array['987 000 021', '+51 987-000-021', '51987000021', '(987)000021']) t loop
    r := crm.buscar_cliente_existente_fn(null, null, d->>'t', null);
    perform pg_temp.exigir(r->>'estado' = 'encontrado' and r->>'criterio' = 'telefono'
      and r#>>'{cliente,nombre}' = 'VC C. X.' and r#>>'{cliente,inversionista_id}' is null
      and (r#>>'{acciones,requiere_documento}')::boolean and not (r#>>'{acciones,nueva_inversion}')::boolean,
      format('el teléfono %s encuentra a X con iniciales y pide el documento', d->>'t'));
    perform pg_temp.exigir((select valor_consultado = '+51987000021' from crm.busquedas_cliente_existente
      where id = (r->>'busqueda_id')::uuid), 'el teléfono queda normalizado en la bitácora');
    perform pg_temp.exigir(not private.busqueda_cliente_es_llave((r->>'busqueda_id')::uuid, pg_temp.id('B'), pg_temp.id('X')),
      'una búsqueda por teléfono no es llave');
  end loop;
  r := crm.buscar_cliente_existente_fn(null, null, '987000031', null);
  perform pg_temp.exigir(r->>'estado' = 'ambiguo' and not (r ? 'cliente'), 'dos clientes con el mismo teléfono: ambiguo, sin nombres');
  r := crm.buscar_cliente_existente_fn(null, null, '987800001', null);
  perform pg_temp.exigir(r->>'estado' = 'no_encontrado', 'el teléfono de un lead que no es cliente: no encontrado');
  r := crm.buscar_cliente_existente_fn(null, null, 'abc', null);
  perform pg_temp.exigir(r->>'estado' = 'invalido', 'teléfono ilegible: inválido');
  r := crm.buscar_cliente_existente_fn('DNI', '123', null, null);
  perform pg_temp.exigir(r->>'estado' = 'invalido', 'DNI de 3 dígitos: inválido');
  perform pg_temp.rechaza($q$select crm.buscar_cliente_existente_fn('DNI','70000021','987000021',null)$q$, '22023', 'uno solo');
  perform pg_temp.rechaza($q$select crm.buscar_cliente_existente_fn(null,null,null,null)$q$, '22023', 'uno solo');
  perform pg_temp.rechaza($q$select crm.buscar_cliente_existente_fn('RUC','70000021',null,null)$q$, '22023', 'tipo de documento');

  -- =====================================================================
  -- 4. Desde un lead: el descartado de B con el DNI de X («ya es cliente»)
  -- =====================================================================
  r := crm.buscar_cliente_existente_fn(null, null, null, pg_temp.id('LB'));
  perform pg_temp.exigir(r->>'estado' = 'encontrado' and r->>'criterio' = 'lead' and r#>>'{cliente,nombre}' = 'VC CLIENTE X'
    and r#>>'{cliente,responsable_nombre}' = 'VC ANALISTA A' and r#>>'{cliente,inversionista_id}' is null
    and (r#>>'{acciones,requiere_documento}')::boolean, 'el lead descartado de B es X: nombre y responsable, y pide el documento');
  perform pg_temp.exigir((select etapa = 'descartado' and vendedor_id = pg_temp.id('B') and inversionista_id is null
    from crm.leads where id = pg_temp.id('LB')), 'buscar no reabre ni toca el lead');
  perform pg_temp.rechaza(format('select crm.buscar_cliente_existente_fn(null,null,null,%L)', pg_temp.id('LK')), '42501', 'fuera de tu ámbito');
  r := crm.buscar_cliente_existente_fn(null, null, null, 'c0000000-0000-4000-8000-000000000084');
  perform pg_temp.exigir(r->>'estado' = 'no_encontrado', 'un lead propio sin persona: no encontrado');

  -- =====================================================================
  -- 5. Quién NO es operable hoy, y quién no es cliente
  -- =====================================================================
  r := crm.buscar_cliente_existente_fn('DNI', '70000023', null, null);
  perform pg_temp.exigir(r->>'estado' = 'no_operable' and r#>>'{acciones,motivo_codigo}' = 'responsable_inactivo'
    and r#>>'{acciones,motivo_no_operable}' = 'El cliente no tiene un responsable activo: pide a Gerencia que se lo asigne.'
    and r#>>'{cliente,nombre}' = 'VC CLIENTE R' and not (r#>>'{acciones,nueva_inversion}')::boolean,
    'R (responsable inactivo): no operable, con el motivo del catálogo y su nombre para gestionarlo');
  r := crm.buscar_cliente_existente_fn('DNI', '70000025', null, null);
  perform pg_temp.exigir(r->>'estado' = 'no_operable' and r#>>'{acciones,motivo_codigo}' = 'no_admite'
    and r->'cliente' = '{"es_mi_cartera": false}'::jsonb, 'W (No insistir): no operable y sin datos de la persona');
  r := crm.buscar_cliente_existente_fn('DNI', '70000022', null, null);
  perform pg_temp.exigir(r->>'estado' = 'no_operable' and r#>>'{acciones,motivo_codigo}' = 'perfil_en_revision'
    and r->'cliente' = '{"es_mi_cartera": false}'::jsonb, 'Q (perfil inactivo): no operable y sin datos de la persona');
  r := pg_temp.buscar('bBH', 'B', '70000032');
  perform pg_temp.exigir(r->>'estado' = 'no_operable' and r#>>'{acciones,motivo_codigo}' = 'conversion_pendiente'
    and r#>>'{cliente,responsable_nombre}' = 'VC ANALISTA A', 'H (lead canónico abierto): no operable (D4), con su responsable');
  perform pg_temp.como('A');
  r := crm.buscar_cliente_existente_fn('DNI', '70000025', null, null);
  perform pg_temp.exigir(r->>'estado' = 'no_operable' and r#>>'{cliente,nombre}' = 'VC CLIENTE W',
    'a su propio responsable, W se le muestra entera');
  perform pg_temp.como('B');
  perform pg_temp.exigir((select veredicto = 'no_operable' and inversionista_id = pg_temp.id('H') from crm.busquedas_cliente_existente
    where id = pg_temp.id('bBH')), 'el no operable queda en la bitácora con la persona');
  perform pg_temp.exigir(not private.busqueda_cliente_es_llave(pg_temp.id('bBH'), pg_temp.id('B'), pg_temp.id('H')), 'no operable no es llave');
  foreach d in array array['"70000024"','"70000027"','"70000028"','"70000029"']::jsonb[] loop
    r := crm.buscar_cliente_existente_fn('DNI', d #>> '{}', null, null);
    perform pg_temp.exigir(r->>'estado' = 'no_encontrado' and not (r ? 'cliente'),
      format('%s no es cliente (o su documento no está verificado): no encontrado', d #>> '{}'));
  end loop;

  -- =====================================================================
  -- 6. Contexto, cuentas enmascaradas (D3) y datos legales con la llave de B
  -- =====================================================================
  perform pg_temp.como('B');
  r := crm.contexto_cliente_existente_fn(pg_temp.id('bB'), null);
  perform pg_temp.exigir(r#>>'{persona,inversionista_id}' = pg_temp.id('X')::text and r#>>'{persona,perfil_id}' = pg_temp.id('PX')::text
    and (r#>>'{persona,tiene_acceso_avance}')::boolean
    and r#>>'{persona,nombre}' = 'VC CLIENTE X' and r#>>'{persona,responsable_id}' = pg_temp.id('A')::text
    and r#>'{persona,correo}' = 'null'::jsonb and r#>'{persona,telefono}' = 'null'::jsonb
    and (r#>>'{capacidades,nueva_inversion}')::boolean and r->>'documento_tipo' = 'DNI' and r->>'solicitud_id' is null,
    'el contexto trae a X sin correo ni teléfono y habilita la inversión');
  select count(*) into n from crm.cuentas_cliente_existente_fn(pg_temp.id('bB'), null, 'PEN') c
   where c.cuenta_id = cuenta and c.numero_enmascarado = '••••4321' and c.cci_enmascarado = '••••8765' and c.banco = 'BANCO SINTETICO';
  perform pg_temp.exigir(n = 1, 'B ve la cuenta de X enmascarada');
  perform pg_temp.exigir(exists (select 1 from crm.cartera_lecturas where actor_id = pg_temp.id('B') and tipo = 'cuentas'
    and inversionista_id = pg_temp.id('X')), 'la lectura de cuentas queda registrada');
  r := crm.datos_legales_cliente_existente_fn(pg_temp.id('bB'), null);
  perform pg_temp.exigir(r->>'cliente_id' = pg_temp.id('PX')::text and not (r->>'falta_domicilio')::boolean, 'B lee los datos legales de X');
  perform pg_temp.rechaza(format('select crm.datos_legales_contrato_fn(%L)', pg_temp.id('PX')), '42501', 'fuera de tu cartera');
  perform pg_temp.como('A');
  r2 := crm.datos_legales_contrato_fn(pg_temp.id('PX'));
  perform pg_temp.exigir(r2->>'cliente_id' = pg_temp.id('PX')::text and r2->'faltan_cliente' = r->'faltan_cliente'
    and r2->'faltan_analista' is not null,
    'la puerta de siempre (A) devuelve lo mismo del cliente');
  -- Una llave ajena, o de otra persona, no abre nada.
  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.contexto_cliente_existente_fn(%L,null)', pg_temp.id('bB')), '42501');
  perform pg_temp.rechaza(format('select * from crm.cuentas_cliente_existente_fn(%L,null,%L)', pg_temp.id('bB'), 'PEN'), '42501');
  perform pg_temp.rechaza(format('select crm.datos_legales_cliente_existente_fn(%L,null)', pg_temp.id('bB')), '42501');
  perform pg_temp.rechaza(format('select crm.contexto_cliente_existente_fn(%L,null)', gen_random_uuid()), '42501');
  perform pg_temp.rechaza(format('select crm.contexto_cliente_existente_fn(%L,%L)', pg_temp.id('bB'), gen_random_uuid()), '22023');

  -- =====================================================================
  -- 7. Preparar: llave, motivo y datos, validados en el servidor
  -- =====================================================================
  perform pg_temp.como('B');
  d := pg_temp.avance(pg_temp.id('X'), jsonb_build_object('tipo','existente','cuenta_id',cuenta));
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'), d, 'corto'),
    '22023', '10 a 500');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'), d,
    'El cliente 70000021 pidió invertir conmigo'), '22023', 'número de documento');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bA'), d,
    'El cliente pidió invertir conmigo'), 'P0409', 'Vuelve a buscar');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bBH'), d,
    'El cliente pidió invertir conmigo'), 'P0409', 'Vuelve a buscar');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'),
    d || jsonb_build_object('inversionista_id', pg_temp.id('K')), 'El cliente pidió invertir conmigo'), '22023', 'no corresponde al cliente buscado');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'),
    d || jsonb_build_object('lead_id', pg_temp.id('LB')), 'El cliente pidió invertir conmigo'), '22023', 'no convierte un lead');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'),
    pg_temp.avance(pg_temp.id('X'), jsonb_build_object('tipo','existente','cuenta_id',cuenta), 'renovacion'),
    'El cliente pidió invertir conmigo'), '22023', 'la renovación es del responsable');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'),
    d || jsonb_build_object('contrato', (d->'contrato') || jsonb_build_object('analista_cierre_id', pg_temp.id('A'))),
    'El cliente pidió invertir conmigo'), 'P0409', 'El analista debe corresponder');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'),
    pg_temp.avance(pg_temp.id('X'), jsonb_build_object('tipo','perfil')), 'El cliente pidió invertir conmigo'), '22023', 'cuenta registrada del cliente');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'),
    pg_temp.avance(pg_temp.id('X'), jsonb_build_object('tipo','nueva','banco','OTRO BANCO','tipo_cuenta','ahorros',
      'numero_cuenta','VC-PEN-9999','cci','99999999999999998765','titular_distinto',false)),
    'El cliente pidió invertir conmigo'), 'P0409', 'ya está registrada');
  perform pg_temp.exigir(not exists (select 1 from crm.inversion_solicitudes where id = s1), 'ningún rechazo dejó solicitud');

  -- =====================================================================
  -- 8. B prepara la venta cruzada de X (Avance, cuenta registrada)
  -- =====================================================================
  r := crm.preparar_inversion_cliente_existente_fn(s1, pg_temp.id('bB'), d, '  El cliente pidió invertir conmigo en la feria  ');
  perform pg_temp.exigir(r->>'puerta' = 'cliente_existente' and r->>'analista_cierre_id' = pg_temp.id('B')::text
    and r->>'estado' = 'preparada', 'la solicitud declara puerta y analista B');
  perform pg_temp.exigir((select puerta = 'cliente_existente' and analista_cierre_id = pg_temp.id('B') and creado_por = pg_temp.id('B')
    and busqueda_id = pg_temp.id('bB') and motivo_atribucion = 'El cliente pidió invertir conmigo en la feria'
    and responsable_esperado_id = pg_temp.id('A') and lead_origen_id is null
    from crm.inversion_solicitudes where id = s1), 'la fila congela analista, quien registra, llave y motivo, y conserva al responsable');
  -- Reintento con la misma clave: la misma solicitud; con otros datos: rechazo.
  r2 := crm.preparar_inversion_cliente_existente_fn(s1, pg_temp.id('bB'), d, 'El cliente pidió invertir conmigo en la feria');
  perform pg_temp.exigir(r2->>'solicitud_id' = r->>'solicitud_id' and r2->>'hash_datos' = r->>'hash_datos', 'el reintento devuelve la misma solicitud');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'),
    d || jsonb_build_object('contrato', (d->'contrato') || '{"capital":1600}'), 'El cliente pidió invertir conmigo en la feria'), 'P0409', 'datos distintos');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bB'), d,
    'Otro motivo distinto del primero'), 'P0409', 'datos distintos');
  -- C no reutiliza la clave de B.
  perform pg_temp.buscar('bC', 'C', '70000021');
  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s1, pg_temp.id('bC'), d,
    'El cliente pidió invertir conmigo en la feria'), '42501');

  -- D6: una venta cruzada pendiente por persona y empresa, en ningún sentido.
  perform pg_temp.como('B');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s2, pg_temp.id('bB'), d,
    'El cliente quiere una segunda inversión'), 'P0409', 'en preparación');
  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s2, pg_temp.id('bC'), d,
    'El cliente quiere invertir con C'), 'P0409', 'en preparación');
  perform pg_temp.como('A');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_fn(%L,%L::jsonb)', s2,
    pg_temp.avance(pg_temp.id('X'), (d->'cuenta'))), 'P0409', 'en preparación');
  -- Otra empresa sí (D6 es por empresa): A prepara Qorilazo por su cartera...
  r := crm.preparar_inversion_fn(s3, pg_temp.coop('qorilazo', 'VC-A-Q1', pg_temp.id('X'), s3));
  perform pg_temp.exigir(r->>'puerta' is null, 'A prepara Qorilazo por su cartera, como siempre');
  -- ... y entonces B no puede preparar Qorilazo para X (D6 en el otro sentido).
  perform pg_temp.como('B');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s4, pg_temp.id('bB'),
    pg_temp.coop('qorilazo', 'VC-B-Q1', pg_temp.id('X'), s4), 'El cliente quiere invertir en Qorilazo'), 'P0409', 'en preparación');
  perform pg_temp.como('A');
  perform crm.cancelar_solicitud_inversion_fn(s3, 0);

  -- =====================================================================
  -- 9. Confirmar: la venta es de B; el responsable, el perfil y la identidad no cambian
  -- =====================================================================
  perform pg_temp.como('B');
  r := crm.confirmar_inversion_revisada_fn(s1, 0);
  contrato := (r#>>'{fuente,id}')::uuid;
  perform pg_temp.exigir((select analista_cierre_id = pg_temp.id('B') and creado_por = pg_temp.id('B') and cliente_id = pg_temp.id('PX')
    from public.contratos where id = contrato), 'el contrato es de B, lo registró B y es de X');
  perform pg_temp.exigir((select cuenta_bancaria_id = cuenta from crm.contrato_cuentas_pago where contrato_id = contrato),
    'el contrato paga en la cuenta registrada que B eligió enmascarada');
  perform pg_temp.exigir((select responsable_relacion_id = pg_temp.id('A') from crm.inversionistas where id = pg_temp.id('X'))
    and (select asesor_perfil_id = pg_temp.id('A') from public.perfiles where id = pg_temp.id('PX'))
    and (select count(*) from crm.inversionista_responsables where inversionista_id = pg_temp.id('X')) = tramos_antes,
    'X sigue siendo de A (responsable, asesor y tramos intactos)');
  perform pg_temp.exigir((select count(*) from public.perfiles) = perfiles_antes and (select count(*) from crm.inversionistas) = personas_antes
    and (select count(*) from crm.leads) = leads_antes, 'ningún perfil, persona ni lead nuevo');
  perform pg_temp.exigir((select etapa = 'descartado' from crm.leads where id = pg_temp.id('LB')), 'el lead descartado sigue descartado');
  perform pg_temp.exigir(private.puede_leer_contrato_pdf(contrato), 'B lee el PDF de su venta (D2)');

  -- La llave «solicitud» solo abre lecturas vivas mientras está preparada.
  r := crm.contexto_cliente_existente_fn(null, s1);
  perform pg_temp.exigir(r#>>'{capacidades,motivo_codigo}' = 'solicitud_cerrada' and r#>'{persona,nombre}' = 'null'::jsonb
    and r#>'{persona,responsable_id}' = 'null'::jsonb and not (r#>>'{capacidades,nueva_inversion}')::boolean,
    'con la solicitud confirmada, el contexto solo dice su estado');
  perform pg_temp.rechaza(format('select * from crm.cuentas_cliente_existente_fn(null,%L,%L)', s1, 'PEN'), '42501');
  perform pg_temp.rechaza(format('select crm.datos_legales_cliente_existente_fn(null,%L)', s1), '42501');
  perform pg_temp.rechaza(format('select * from crm.contratos_upgrade_cliente_existente_fn(null,%L)', s1), '42501');

  -- =====================================================================
  -- 10. Un cliente con varias inversiones: B vende otra en Qorilazo
  -- =====================================================================
  r := pg_temp.buscar('bB3', 'B', '70000021');
  perform pg_temp.exigir(r#>'{cliente,empresas}' ? 'avance' and (r#>>'{acciones,nueva_inversion}')::boolean,
    'tras la primera venta, X aparece con Avance y B puede venderle otra');
  perform pg_temp.como(null);
  insert into storage.objects(bucket_id, name, metadata)
  values ('f4-comprobantes', pg_temp.id('X') || '/' || s5 || '/comprobante.pdf', '{"size":128,"mimetype":"application/pdf"}');
  perform pg_temp.como('B');
  r := crm.preparar_inversion_cliente_existente_fn(s5, pg_temp.id('bB3'), pg_temp.coop('qorilazo', 'VC-B-Q2', pg_temp.id('X'), s5),
    'Segunda inversión que el cliente pidió cerrar con B');
  r := crm.confirmar_inversion_revisada_fn(s5, 0);
  perform pg_temp.exigir((select vendedor_id = pg_temp.id('B') from crm.cierres_externos where id = (r#>>'{fuente,cierre_id}')::uuid),
    'el cierre cooperativo también es de B');
  -- D6 también frena la reinversión de A mientras B tiene otra venta cruzada de X en
  -- Qorilazo en preparación (la reinversión pasa por el mismo núcleo).
  perform crm.preparar_inversion_cliente_existente_fn(s8, pg_temp.id('bB3'), pg_temp.coop('qorilazo', 'VC-B-Q3', pg_temp.id('X'), s8),
    'Tercera inversión que el cliente pidió cerrar con B');
  perform pg_temp.como('A');
  perform pg_temp.rechaza(format('select crm.preparar_reinversion_fn(%L,%L,%L::jsonb)', s9, r#>>'{fuente,cierre_id}',
    pg_temp.coop('qorilazo', 'VC-A-R1', pg_temp.id('X'), s9)), 'P0409', 'en preparación');
  perform pg_temp.como('B');
  perform crm.cancelar_solicitud_inversion_fn(s8, 0);

  -- Upgrade (D5): B elige, con su llave, qué contrato Avance de X amplía.
  select count(*) into n from crm.contratos_upgrade_cliente_existente_fn(pg_temp.id('bB3'), null) u
   where u.contrato_id = contrato and u.numero_contrato is not null and u.tasa_anual = 15;
  perform pg_temp.exigir(n = 1, 'B ve el contrato activo de X que puede ampliar');
  perform pg_temp.exigir(exists (select 1 from crm.cartera_lecturas where actor_id = pg_temp.id('B') and tipo = 'ficha'
    and inversionista_id = pg_temp.id('X')), 'la lectura para el upgrade queda registrada');
  d := pg_temp.avance(pg_temp.id('X'), jsonb_build_object('tipo','existente','cuenta_id',cuenta), 'upgrade');
  d := jsonb_set(d, '{contrato,contrato_origen_id}', to_jsonb(contrato::text));
  perform crm.preparar_inversion_cliente_existente_fn(s10, pg_temp.id('bB3'), d, 'El cliente amplía su contrato con B');
  r := crm.confirmar_inversion_revisada_fn(s10, 0);
  perform pg_temp.exigir((select categoria = 'upgrade' and analista_cierre_id = pg_temp.id('B') and creado_por = pg_temp.id('B')
    from public.contratos where id = (r#>>'{fuente,id}')::uuid), 'el upgrade es un contrato aparte de B');
  perform pg_temp.exigir((select vendedor_id = pg_temp.id('A') from crm.operaciones_cartera
    where contrato_nuevo_id = (r#>>'{fuente,id}')::uuid and tipo = 'upgrade'),
    'la operación de cartera del upgrade queda a nombre del asesor (A): decisión pendiente de Miguel');

  select count(*) into inv_antes from crm.inversiones iv where private.inversionista_canonica(iv.inversionista_id) = pg_temp.id('X');
  perform pg_temp.exigir(inv_antes >= 3, 'X tiene varias inversiones y una sola identidad');

  -- =====================================================================
  -- 11. Gerencia transfiere X de A a A2: nada histórico cambia
  -- =====================================================================
  perform pg_temp.como('G');
  perform crm.reasignar_responsable_relacion_fn(pg_temp.id('X'), pg_temp.id('A2'), 'Reorganización de la cartera del equipo');
  perform pg_temp.exigir((select analista_cierre_id = pg_temp.id('B') from public.contratos where id = contrato)
    and (select count(*) from crm.inversiones iv where private.inversionista_canonica(iv.inversionista_id) = pg_temp.id('X')) = inv_antes,
    'la transferencia no cambió la atribución ni las inversiones de X');
  r := pg_temp.buscar('bB4', 'B', '70000021');
  perform pg_temp.exigir(r#>>'{cliente,responsable_nombre}' = 'VC ANALISTA A DOS', 'la búsqueda ya muestra al nuevo responsable');

  -- =====================================================================
  -- 12. K, cliente con lead canónico CONVERTIDO: la venta cruzada funciona
  -- =====================================================================
  r := pg_temp.buscar('bBK', 'B', '70000031');
  perform pg_temp.exigir(r->>'estado' = 'encontrado' and (r#>>'{acciones,nueva_inversion}')::boolean,
    'K (lead convertido) admite venta cruzada');
  perform pg_temp.como(null);
  s2 := gen_random_uuid();
  insert into storage.objects(bucket_id, name, metadata)
  values ('f4-comprobantes', pg_temp.id('K') || '/' || s2 || '/comprobante.pdf', '{"size":128,"mimetype":"application/pdf"}');
  perform pg_temp.como('B');
  perform crm.preparar_inversion_cliente_existente_fn(s2, pg_temp.id('bBK'), pg_temp.coop('prodelco', 'VC-B-K1', pg_temp.id('K'), s2),
    'El cliente K pidió invertir en Prodelco');
  r := crm.confirmar_inversion_revisada_fn(s2, 0);
  perform pg_temp.exigir((select vendedor_id = pg_temp.id('B') and not es_cierre_inicial from crm.cierres_externos
    where id = (r#>>'{fuente,cierre_id}')::uuid), 'la venta a K es de B y no es conversión');
  perform pg_temp.exigir((select etapa = 'convertido' and vendedor_id = pg_temp.id('A') from crm.leads where id = pg_temp.id('LK')),
    'el lead de K sigue convertido y de A');
end $pruebas$;

-- La llave vence a las 2 horas, pero el reintento de una solicitud ya creada se autoriza
-- con la propia solicitud. (La bitácora es inmutable: solo aquí se envejece una fila,
-- con sentencias sueltas y sin triggers.)
set local session_replication_role = replica;
update crm.busquedas_cliente_existente set creado_en = creado_en - interval '3 hours'
 where id in (pg_temp.id('bBK'), pg_temp.id('bC'));
set local session_replication_role = origin;

do $vencida$
declare s uuid := (select id from crm.inversion_solicitudes where busqueda_id = pg_temp.id('bBK'));
begin
  perform pg_temp.como('B');
  perform pg_temp.exigir((crm.preparar_inversion_cliente_existente_fn(s, pg_temp.id('bBK'),
    (select datos from crm.inversion_solicitudes where id = s), 'El cliente K pidió invertir en Prodelco')->>'solicitud_id') = s::text,
    'el reintento con la búsqueda vencida devuelve su solicitud');
  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', gen_random_uuid(),
    pg_temp.id('bC'), pg_temp.coop('prodelco', 'VC-C-X1', pg_temp.id('X'), gen_random_uuid()), 'El cliente pidió invertir con C'),
    'P0409', 'Vuelve a buscar');
  perform pg_temp.rechaza(format('select crm.contexto_cliente_existente_fn(%L,null)', pg_temp.id('bC')), '42501');
end $vencida$;

-- Si el documento buscado deja de ser de la persona (corrección de identidad), la
-- búsqueda ya no sirve aunque siga vigente.
do $doc_busqueda$ begin perform pg_temp.buscar('bBK2', 'B', '70000031'); end $doc_busqueda$;
set local session_replication_role = replica;
update crm.inversionista_identificadores set estado = 'historico', vigente_hasta = now()
 where inversionista_id = pg_temp.id('K') and documento_normalizado = '70000031';
insert into crm.inversionista_identificadores (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente)
values (pg_temp.id('K'), 'DNI', '70000131', '70000131', 'vigente', true, 'vc_prueba');
-- El perfil acompaña la corrección: así solo la revalidación del documento buscado lo frena.
update public.perfiles set dni = '70000131' where id = pg_temp.id('PK');
set local session_replication_role = origin;
do $doc_cambio$ declare s uuid := gen_random_uuid(); begin
  perform pg_temp.como('B');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_cliente_existente_fn(%L,%L,%L::jsonb,%L)', s, pg_temp.id('bBK2'),
    pg_temp.coop('qorilazo', 'VC-B-K2', pg_temp.id('K'), s), 'El cliente K pidió invertir en Qorilazo'), 'P0409', 'ya no corresponde');
end $doc_cambio$;

-- La bitácora es inmutable y sus filas no se borran.
do $inmutable$ begin
  perform pg_temp.como(null);
  perform pg_temp.rechaza(format('update crm.busquedas_cliente_existente set veredicto = %L where id = %L', 'invalido', pg_temp.id('bB')), 'P0409');
  perform pg_temp.rechaza(format('delete from crm.busquedas_cliente_existente where id = %L', pg_temp.id('bB')), 'P0409');
end $inmutable$;

-- Tope: 30 búsquedas por hora por actor (C llena su cupo).
do $tope$
declare r jsonb; r2 jsonb; n bigint;
begin
  perform pg_temp.como(null);
  select count(*) into n from crm.busquedas_cliente_existente
   where consultado_por = pg_temp.id('C') and veredicto <> 'limite' and creado_en > statement_timestamp() - interval '1 hour';
  insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto)
  select pg_temp.id('C'), 'documento', 'DNI', '7000' || lpad(g::text, 4, '0'), 'no_encontrado' from generate_series(1, 30 - n) g;
  perform pg_temp.como('C');
  r := crm.buscar_cliente_existente_fn('DNI', '70000021', null, null);
  perform pg_temp.exigir(r->>'estado' = 'limite' and not (r ? 'cliente'), 'al llegar a 30 en una hora: límite, sin datos');
  r2 := crm.buscar_cliente_existente_fn('DNI', '70000021', null, null);
  perform pg_temp.exigir(r2->>'estado' = 'limite' and r2->>'busqueda_id' = r->>'busqueda_id', 'sigue en el límite, con la misma fila');
  perform pg_temp.exigir((select count(*) from crm.busquedas_cliente_existente where consultado_por = pg_temp.id('C') and veredicto = 'limite') = 1,
    'los intentos sobre el tope dejan una sola fila por minuto');
  -- B: 29 búsquedas que cuentan y 3 rechazadas por el tope. Los rechazos no alargan el
  -- castigo, así que todavía puede buscar (y el tope de C no lo afecta).
  perform pg_temp.como(null);
  n := private.busquedas_cliente_ultima_hora(pg_temp.id('B'));
  perform pg_temp.exigir(n < 29, 'B todavía está por debajo del tope antes de llenarlo');
  insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto)
  select pg_temp.id('B'), 'documento', 'DNI', '7100' || lpad(g::text, 4, '0'), 'no_encontrado' from generate_series(1, 29 - n) g;
  insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto)
  select pg_temp.id('B'), 'documento', 'DNI', '70000021', 'limite' from generate_series(1, 3) g;
  perform pg_temp.como('B');
  perform pg_temp.exigir(crm.buscar_cliente_existente_fn('DNI', '70000021', null, null)->>'estado' = 'encontrado',
    'con 29 que cuentan y 3 rechazos del tope, B todavía busca');
  perform pg_temp.exigir(crm.buscar_cliente_existente_fn('DNI', '70000021', null, null)->>'estado' = 'limite',
    'la búsqueda número 30 de B agota su cupo');
end $tope$;

-- Permisos del catálogo: la bitácora y los núcleos no son puertas.
do $catalogo$ declare f text; begin
  perform pg_temp.exigir((select relrowsecurity from pg_class where oid = 'crm.busquedas_cliente_existente'::regclass)
    and not exists (select 1 from pg_policies where schemaname = 'crm' and tablename = 'busquedas_cliente_existente'),
    'la bitácora tiene RLS y ninguna policy');
  foreach f in array array['anon','authenticated','service_role'] loop
    perform pg_temp.exigir(not has_table_privilege(f, 'crm.busquedas_cliente_existente', 'select,insert,update,delete'),
      format('%s no toca la bitácora', f));
    perform pg_temp.exigir(not has_function_privilege(f, 'private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)', 'execute')
      and not has_function_privilege(f, 'private.datos_legales_contrato_nucleo(uuid)', 'execute')
      and not has_function_privilege(f, 'private.inversionista_es_cliente(uuid)', 'execute'),
      format('%s no ejecuta los núcleos', f));
  end loop;
  foreach f in array array['crm.buscar_cliente_existente_fn(text,text,text,uuid)','crm.contexto_cliente_existente_fn(uuid,uuid)',
    'crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text)','crm.cuentas_cliente_existente_fn(uuid,uuid,text)',
    'crm.datos_legales_cliente_existente_fn(uuid,uuid)'] loop
    perform pg_temp.exigir(has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute')
      and not has_function_privilege('service_role', f, 'execute'), format('%s: solo authenticated', f));
  end loop;
end $catalogo$;

-- Como un commit: los controles diferidos pendientes (rentabilidad y operación de cartera
-- de public.contratos) se disparan aquí, antes de deshacer. Sin esto, una prueba que
-- termina en rollback nunca los ejerce.
set constraints all immediate;

select 'VENTA_CRUZADA_FASE4_OK' as veredicto;
rollback;
