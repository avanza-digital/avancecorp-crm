-- Venta cruzada · Fase 3: la venta queda a nombre de quien la cierra.
-- Recorrido completo por las funciones REALES de la solicitud (confirmar, corregir,
-- cancelar, consultar, comprobante, PDF), con la solicitud de venta cruzada creada
-- como la creará la puerta de la Fase 4 (fila con su llave). Una transacción que se
-- deshace. Solo en el banco sintético con mundo.sql sembrado.
-- Veredicto como FILA: VENTA_CRUZADA_FASE3_OK.
begin;
set local statement_timeout = '120s';

do $guarda$ begin
  if (select count(*) from crm.leads) > 200 or (select count(*) from public.perfiles where rol = 'cliente') > 50 then
    raise exception 'Esta prueba solo corre en el banco sintético';
  end if;
  if not exists (select 1 from pg_proc where proname = 'confirmar_inversion_revisada_fn'
                 and prosrc like '%v_s.analista_cierre_id%') then
    raise exception 'La Fase 3 no está aplicada en este banco';
  end if;
end $guarda$;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('f4-comprobantes','f4-comprobantes', false, 10485760, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do nothing;

create temporary table t3(clave text primary key, id uuid) on commit drop;
insert into t3 values
  ('G','c0000000-0000-4000-8000-000000000001'),('S1','c0000000-0000-4000-8000-000000000002'),
  ('S2','c0000000-0000-4000-8000-000000000003'),('A','c0000000-0000-4000-8000-000000000004'),
  ('A2','c0000000-0000-4000-8000-000000000005'),('B','c0000000-0000-4000-8000-000000000006'),
  ('C','c0000000-0000-4000-8000-000000000007'),('PX','c0000000-0000-4000-8000-000000000021');
insert into t3 select 'X', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000021';

create function pg_temp.id(p text) returns uuid language sql stable as $$ select id from t3 where clave = p $$;
create function pg_temp.como(p text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when p is null then '' else
    json_build_object('sub', pg_temp.id(p), 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.id(p)::text, ''), true);
end $$;
create function pg_temp.exigir(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FASE3: %', mensaje; end if; end $$;
create function pg_temp.rechaza(p_sql text, p_estado text, p_texto text default null) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate = p_estado and (p_texto is null or position(p_texto in sqlerrm) > 0) then return; end if;
    raise exception 'FASE3: esperado % (%), obtenido %: %', p_estado, coalesce(p_texto,'-'), sqlstate, sqlerrm;
  end;
  raise exception 'FASE3: debió rechazar con %: %', p_estado, left(p_sql, 160);
end $$;

-- Una búsqueda vigente de p_actor sobre X (la llave).
create function pg_temp.llave(p_actor text) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado, veredicto, inversionista_id)
  values (pg_temp.id(p_actor), 'documento', 'DNI', '70000021', 'encontrado', pg_temp.id('X')) returning id into v;
  return v;
end $$;

-- Una venta cruzada de p_actor sobre X, como la dejará la puerta de la Fase 4.
create function pg_temp.venta(p_clave text, p_actor text, p_datos jsonb) returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid(); d jsonb := p_datos || jsonb_build_object('inversionista_id', pg_temp.id('X'));
begin
  insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos,
    creado_por, puerta, analista_cierre_id, busqueda_id, motivo_atribucion)
  values (v, pg_temp.id('X'), (select id from crm.empresas where clave = d->>'empresa'),
    (select responsable_relacion_id from crm.inversionistas where id = pg_temp.id('X')), private.idem_hash(d), d,
    pg_temp.id(p_actor), 'cliente_existente', pg_temp.id(p_actor), pg_temp.llave(p_actor),
    'El cliente pidió invertir con este analista');
  insert into t3 values (p_clave, v);
  return v;
end $$;

create function pg_temp.coop(p_empresa text, p_numero text, p_solicitud uuid) returns jsonb language sql as $$
  select jsonb_build_object('empresa', p_empresa, 'monto', 3000, 'moneda', 'PEN',
    'fecha_comercial', (statement_timestamp() at time zone 'America/Lima')::date,
    'vence_en', ((statement_timestamp() at time zone 'America/Lima')::date + interval '12 months')::date,
    'numero_transaccion', p_numero, 'referencia', 'REF ' || p_numero,
    'evidencia', jsonb_build_object('ruta', pg_temp.id('X') || '/' || p_solicitud || '/comprobante.pdf'));
$$;

-- Datos legales mínimos del cliente para el PDF (los siembra el administrador local).
select pg_temp.como(null);
update public.perfiles set domicilio = 'AVENIDA SINTETICA 123 LIMA' where id = pg_temp.id('PX');

do $pruebas$
declare
  s1 uuid := gen_random_uuid(); d jsonb; r jsonb; r2 jsonb; ce crm.cierres_externos%rowtype;
  s2 uuid; s3 uuid := gen_random_uuid(); s4 uuid; s5 uuid; s6 uuid; c jsonb; cuotas jsonb; ruta text;
  contrato_b uuid; contrato_a uuid; inicio date := date_trunc('month', statement_timestamp() at time zone 'America/Lima')::date;
  cuotas_ant jsonb; c_ant jsonb; contrato_heredado uuid; s7 uuid; s8 uuid;
  tramos_antes bigint;
begin
  select count(*) into tramos_antes from crm.inversionista_responsables where inversionista_id = pg_temp.id('X');

  -- =====================================================================
  -- 1. Cooperativa: B vende a X, cliente de A
  -- =====================================================================
  insert into t3 values ('s1', s1);
  d := pg_temp.coop('qorilazo', 'VC-COOP-1', s1) || jsonb_build_object('inversionista_id', pg_temp.id('X'));
  insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos,
    creado_por, puerta, analista_cierre_id, busqueda_id, motivo_atribucion)
  values (s1, pg_temp.id('X'), (select id from crm.empresas where clave = 'qorilazo'), pg_temp.id('A'),
    private.idem_hash(d), d, pg_temp.id('B'), 'cliente_existente', pg_temp.id('B'), pg_temp.llave('B'),
    'El cliente pidió invertir con este analista');
  ruta := d#>>'{evidencia,ruta}';

  perform pg_temp.como('B');
  perform pg_temp.exigir(private.f4_comprobante_autorizado(ruta), 'B puede subir el comprobante de su venta');
  perform pg_temp.como('C');
  perform pg_temp.exigir(not private.f4_comprobante_autorizado(ruta), 'C no puede subir el comprobante de la venta de B');
  perform pg_temp.como('A');
  perform pg_temp.exigir(not private.f4_comprobante_autorizado(ruta), 'A, responsable, no sube el comprobante de la venta de B (Miguel, 24/09)');
  perform pg_temp.como(null);
  insert into storage.objects(bucket_id, name, metadata) values ('f4-comprobantes', ruta, '{"size":128,"mimetype":"application/pdf"}');
  perform pg_temp.como('B');  perform pg_temp.exigir(private.f4_comprobante_visible(ruta), 'B ve su comprobante');
  perform pg_temp.como('S2'); perform pg_temp.exigir(private.f4_comprobante_visible(ruta), 'S2 ve el comprobante de B');
  perform pg_temp.como('A');  perform pg_temp.exigir(private.f4_comprobante_visible(ruta), 'A, responsable, ve el comprobante');
  perform pg_temp.como('C');  perform pg_temp.exigir(not private.f4_comprobante_visible(ruta), 'C no ve el comprobante de B');

  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)', s1), '42501');
  perform pg_temp.rechaza(format('select crm.solicitud_inversion_fn(%L)', s1), '42501');
  perform pg_temp.como('B');
  r := crm.solicitud_inversion_fn(s1);
  perform pg_temp.exigir(r->>'puerta' = 'cliente_existente' and r->>'analista_cierre_id' = pg_temp.id('B')::text
    and r->>'responsable_esperado_id' = pg_temp.id('A')::text, 'la solicitud muestra puerta, analista B y responsable A');
  r := crm.confirmar_inversion_revisada_fn(s1, 0);
  r2 := crm.confirmar_inversion_revisada_fn(s1, 0);
  perform pg_temp.exigir(r->>'inversion_id' = r2->>'inversion_id' and (r2->>'reintento')::boolean, 'el reintento devuelve la misma inversión');
  perform pg_temp.exigir(r->>'analista_cierre_id' = pg_temp.id('B')::text and r->>'puerta' = 'cliente_existente', 'el resultado declara la atribución');
  select * into ce from crm.cierres_externos where id = (r#>>'{fuente,cierre_id}')::uuid;
  perform pg_temp.exigir(ce.vendedor_id = pg_temp.id('B') and ce.creado_por = pg_temp.id('B') and not ce.es_cierre_inicial,
    'el cierre es de B, lo registró B y no es inicial');
  perform pg_temp.exigir((select creado_por = pg_temp.id('B') and not es_primera_conversion from crm.inversiones
    where id = (r->>'inversion_id')::uuid), 'la inversión la registró B y no es conversión');
  perform pg_temp.exigir((select responsable_relacion_id = pg_temp.id('A') from crm.inversionistas where id = pg_temp.id('X')),
    'X sigue siendo de A');
  perform pg_temp.exigir((select asesor_perfil_id = pg_temp.id('A') from public.perfiles where id = pg_temp.id('PX')),
    'el perfil de X sigue asesorado por A');
  perform pg_temp.exigir((select count(*) from crm.inversionista_responsables where inversionista_id = pg_temp.id('X')) = tramos_antes,
    'no se abrió ningún tramo de responsable');
  perform pg_temp.exigir(crm.bienvenida_inversion_estado_fn(s1)->>'estado' = 'no_corresponde', 'sin bienvenida en venta cruzada');
  perform pg_temp.exigir(crm.cancelar_solicitud_inversion_fn(s1, 0)->>'estado' = 'confirmada', 'cancelar una confirmada devuelve su resultado');

  -- =====================================================================
  -- 2. Avance: B vende a X un contrato nuevo
  -- =====================================================================
  select jsonb_agg(jsonb_build_object('numero_cuota', n, 'fecha_programada', (inicio + (n || ' months')::interval)::date,
    'monto_programado', 18.75, 'tipo', 'cuota') order by n) into cuotas from generate_series(1, 12) n;
  cuotas := cuotas || jsonb_build_array(jsonb_build_object('numero_cuota', 13,
    'fecha_programada', (inicio + interval '12 months 7 days')::date, 'monto_programado', 1500, 'tipo', 'retorno'));
  c := jsonb_build_object('categoria', 'nuevo', 'capital', 1500, 'moneda', 'PEN', 'tasa_anual', 15, 'modalidad', 'mensual',
    'tipo_interes', 'simple', 'fecha_inicio', inicio, 'fecha_vencimiento', (inicio + interval '12 months')::date);
  d := jsonb_build_object('empresa', 'avance', 'contrato', c, 'cronograma', cuotas,
    'cuenta', jsonb_build_object('tipo', 'nueva', 'banco', 'BANCO SINTETICO', 'tipo_cuenta', 'ahorros',
      'numero_cuenta', 'VC-PEN-001', 'cci', '99999999999999999992', 'titular_distinto', false));
  perform pg_temp.como(null);
  s2 := pg_temp.venta('s2', 'B', d);
  perform pg_temp.como('B');
  r := crm.confirmar_inversion_revisada_fn(s2, 0);
  contrato_b := (r#>>'{fuente,id}')::uuid;
  perform pg_temp.exigir((select analista_cierre_id = pg_temp.id('B') and creado_por = pg_temp.id('B') and cliente_id = pg_temp.id('PX')
    and categoria = 'nuevo' from public.contratos where id = contrato_b), 'el contrato Avance es de B, lo creó B y es de X');
  perform pg_temp.exigir((select asesor_perfil_id = pg_temp.id('A') from public.perfiles where id = pg_temp.id('PX')),
    'el contrato de B no movió el asesor de X');
  perform pg_temp.exigir(r#>>'{fuente,pdf,estado}' is not null, 'la confirmación creó el trabajo del PDF');
  perform pg_temp.exigir(private.puede_leer_contrato_pdf(contrato_b), 'B lee el PDF de su contrato (D2)');
  perform pg_temp.como('S2'); perform pg_temp.exigir(private.puede_leer_contrato_pdf(contrato_b), 'S2 lee el PDF del contrato de B');
  perform pg_temp.como('A');  perform pg_temp.exigir(private.puede_leer_contrato_pdf(contrato_b), 'A, responsable, lee el PDF');
  perform pg_temp.como('C');  perform pg_temp.exigir(not private.puede_leer_contrato_pdf(contrato_b), 'C no lee el PDF del contrato de B');

  -- =====================================================================
  -- 2b. Auditoría P1: D2 abre la LECTURA, no el alta. Ni B ni su supervisor dan de alta
  --     un contrato Avance directo para X (aunque se pongan de analista), y B no hace el
  --     alta de Portal de un cliente ajeno.
  -- =====================================================================
  perform pg_temp.como('B');
  perform pg_temp.rechaza(format('select crm.crear_contrato_con_cuenta_pdf_v2(%L::jsonb,%L::jsonb,%L::jsonb)',
    c || jsonb_build_object('cliente_id', pg_temp.id('PX')), cuotas,
    (d->'cuenta') || '{"cci":"99999999999999999981","numero_cuenta":"VC-PEN-081"}'), '42501', 'fuera de tu cartera');
  perform pg_temp.rechaza(format('select crm.crear_contrato_con_cuenta_pdf_v2(%L::jsonb,%L::jsonb,%L::jsonb)',
    c || jsonb_build_object('cliente_id', pg_temp.id('PX'), 'analista_cierre_id', pg_temp.id('B')), cuotas,
    (d->'cuenta') || '{"cci":"99999999999999999982","numero_cuenta":"VC-PEN-082"}'), '42501', 'fuera de tu cartera');
  -- B también completa el acceso Avance (Miguel, 24/09): pasa la llave y la regla de
  -- operador, y solo lo frena que esta solicitud sea cooperativa y ya esté confirmada.
  perform pg_temp.rechaza(format('select crm.acceso_inversion_fn(%L,%L,%L::jsonb)', s1, 'reclamar', '{}'), 'P0409', 'no permite completar acceso Avance');
  perform pg_temp.como('A');
  perform pg_temp.rechaza(format('select crm.acceso_inversion_fn(%L,%L,%L::jsonb)', s1, 'reclamar', '{}'), '42501', 'la gestionan quien la registró');
  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.acceso_inversion_fn(%L,%L,%L::jsonb)', s1, 'reclamar', '{}'), '42501');
  perform pg_temp.como('B');
  perform pg_temp.como('S2');
  perform pg_temp.rechaza(format('select crm.crear_contrato_con_cuenta_pdf_v2(%L::jsonb,%L::jsonb,%L::jsonb)',
    c || jsonb_build_object('cliente_id', pg_temp.id('PX'), 'analista_cierre_id', pg_temp.id('B')), cuotas,
    (d->'cuenta') || '{"cci":"99999999999999999983","numero_cuenta":"VC-PEN-083"}'), '42501', 'fuera de tu cartera');
  -- Segunda auditoría (P1): un contrato de régimen documental «anterior» (fecha de inicio
  -- antes del 19/08) no crea PDF; la compuerta vive también en el alta.
  select jsonb_agg(jsonb_build_object('numero_cuota', n, 'fecha_programada', ('2026-08-10'::date + (n || ' months')::interval)::date,
    'monto_programado', 18.75, 'tipo', 'cuota') order by n) into cuotas_ant from generate_series(1, 12) n;
  cuotas_ant := cuotas_ant || jsonb_build_array(jsonb_build_object('numero_cuota', 13,
    'fecha_programada', ('2026-08-10'::date + interval '12 months 7 days')::date, 'monto_programado', 1500, 'tipo', 'retorno'));
  c_ant := c || jsonb_build_object('cliente_id', pg_temp.id('PX'), 'fecha_inicio', '2026-08-10',
    'fecha_vencimiento', ('2026-08-10'::date + interval '12 months')::date);
  perform pg_temp.rechaza(format('select crm.crear_contrato_con_cuenta_pdf_v2(%L::jsonb,%L::jsonb,%L::jsonb)', c_ant, cuotas_ant,
    (d->'cuenta') || '{"cci":"99999999999999999984","numero_cuenta":"VC-PEN-084"}'), '42501', 'fuera de tu cartera');
  perform pg_temp.como('B');
  perform pg_temp.rechaza(format('select crm.crear_contrato_con_cuenta_pdf_v2(%L::jsonb,%L::jsonb,%L::jsonb)', c_ant, cuotas_ant,
    (d->'cuenta') || '{"cci":"99999999999999999985","numero_cuenta":"VC-PEN-085"}'), '42501', 'fuera de tu cartera');
  perform pg_temp.exigir(not exists (select 1 from public.contratos where cliente_id = pg_temp.id('PX') and id <> contrato_b
    and creado_por in (pg_temp.id('B'), pg_temp.id('S2'))), 'no quedó ningún alta directa de B ni de S2 para X');
  perform pg_temp.exigir(not exists (select 1 from crm.cuentas_bancarias where cliente_id = pg_temp.id('PX')
    and cci in ('99999999999999999981','99999999999999999982','99999999999999999983','99999999999999999984','99999999999999999985')),
    'ningún alta rechazada dejó una cuenta del cliente');
  -- Y la Edge no genera el PDF de un contrato ajeno sin trabajo: B lo registra por la puerta
  -- heredada (Opción B, sin PDF) y la reserva que crearía su trabajo se niega; A sí puede.
  contrato_heredado := (public.crear_contrato(c || jsonb_build_object('cliente_id', pg_temp.id('PX')), cuotas)->>'id')::uuid;
  perform pg_temp.exigir(private.puede_leer_contrato_pdf(contrato_heredado), 'B lee el contrato que se atribuyó (D2)');
  perform pg_temp.como(null);
  perform pg_temp.rechaza(format('select crm.contrato_pdf_reservar(%L,%L)', contrato_heredado, pg_temp.id('B')), '42501', 'fuera de tu cartera');
  perform pg_temp.exigir(not exists (select 1 from private.contrato_pdf_jobs where contrato_id = contrato_heredado),
    'la reserva negada no dejó trabajo de PDF');
  -- A, de la cartera, sí pasa la compuerta (y se detiene después: la puerta heredada no
  -- dejó cuenta de pago contractual, que el PDF exige).
  perform pg_temp.rechaza(format('select crm.contrato_pdf_reservar(%L,%L)', contrato_heredado, pg_temp.id('A')), '23514', 'cuenta de pago contractual');
  -- La venta cruzada admite el alta del acceso Avance del cliente (Miguel, 24/09): con el
  -- perfil aún sin crear, los datos del alta y la cuenta vacía del primer paso validan.
  perform pg_temp.como(null);
  perform pg_temp.exigir(private.inversion_validar_datos(gen_random_uuid(),
    (d - 'cuenta') || jsonb_build_object('inversionista_id', pg_temp.id('X'), 'cuenta', '{}'::jsonb,
      'alta_portal', jsonb_build_object('correo', 'vc.x.nuevo@avancecorp.test', 'nombre_completo', 'VC CLIENTE X',
        'apellidos', 'X', 'nombres', 'VC CLIENTE', 'telefono', '987000021', 'domicilio', 'AVENIDA SINTETICA 123 LIMA')),
    jsonb_build_object('inversionista_id', pg_temp.id('X'), 'perfil_id', null, 'responsable_id', pg_temp.id('A'),
      'analista_cierre_id', pg_temp.id('B'), 'puerta', 'cliente_existente')) is not null,
    'la venta cruzada admite el alta del acceso Avance');
  -- D3: la cuenta de una venta cruzada es una registrada o una nueva, y la nueva no pisa
  -- una cuenta activa del cliente con el mismo CCI (la de la sección 2 ya es de X).
  perform pg_temp.rechaza(format('select private.inversion_validar_datos(%L,%L::jsonb,%L::jsonb)', gen_random_uuid(),
    d || jsonb_build_object('inversionista_id', pg_temp.id('X'), 'cuenta', (d->'cuenta') || '{"banco":"OTRO BANCO"}'),
    jsonb_build_object('inversionista_id', pg_temp.id('X'), 'perfil_id', pg_temp.id('PX'), 'responsable_id', pg_temp.id('A'),
      'analista_cierre_id', pg_temp.id('B'), 'puerta', 'cliente_existente')), 'P0409', 'ya está registrada');
  perform pg_temp.rechaza(format('select private.inversion_validar_datos(%L,%L::jsonb,%L::jsonb)', gen_random_uuid(),
    d || jsonb_build_object('inversionista_id', pg_temp.id('X'), 'cuenta', jsonb_build_object('tipo', 'perfil')),
    jsonb_build_object('inversionista_id', pg_temp.id('X'), 'perfil_id', pg_temp.id('PX'), 'responsable_id', pg_temp.id('A'),
      'analista_cierre_id', pg_temp.id('B'), 'puerta', 'cliente_existente')), '22023', 'cuenta registrada del cliente');

  -- =====================================================================
  -- 3. Mismo analista: A registra por su flujo de siempre y todo sigue igual
  -- =====================================================================
  perform pg_temp.como('A');
  d := jsonb_set(jsonb_set(d, '{cuenta,cci}', '"99999999999999999993"'), '{cuenta,numero_cuenta}', '"VC-PEN-002"')
       || jsonb_build_object('inversionista_id', pg_temp.id('X'));
  r := crm.preparar_inversion_fn(s3, d);
  perform pg_temp.exigir(r->>'puerta' is null and r->>'analista_cierre_id' is null, 'la solicitud de cartera no cambia de forma');
  r := crm.confirmar_inversion_revisada_fn(s3, 0);
  contrato_a := (r#>>'{fuente,id}')::uuid;
  perform pg_temp.exigir((select analista_cierre_id = pg_temp.id('A') and creado_por = pg_temp.id('A') from public.contratos
    where id = contrato_a), 'el flujo de A atribuye a A, como siempre');
  perform pg_temp.como('B');
  perform pg_temp.exigir(not private.puede_leer_contrato_pdf(contrato_a), 'B no lee el PDF de un contrato que no cerró');

  -- =====================================================================
  -- 4. La venta cruzada no admite renovación (D5)
  -- =====================================================================
  perform pg_temp.como(null);
  s4 := pg_temp.venta('s4', 'B', (d - 'inversionista_id') || jsonb_build_object('contrato', c || '{"categoria":"renovacion"}',
    'cuenta', (d->'cuenta') || '{"cci":"99999999999999999987","numero_cuenta":"VC-PEN-087"}'));
  perform pg_temp.como('B');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)', s4), '22023', 'la renovación es del responsable');
  perform pg_temp.rechaza(format('select crm.corregir_solicitud_inversion_fn(%L,%L,0,%L::jsonb,%L)', s4, gen_random_uuid(),
    (select datos from crm.inversion_solicitudes where id = s4), 'Corrige sin cambiar la categoría'), '22023', 'la renovación es del responsable');
  perform crm.cancelar_solicitud_inversion_fn(s4, 0);
  perform pg_temp.exigir((select estado = 'cancelada' from crm.inversion_solicitudes where id = s4), 'B cancela su propia solicitud');

  -- =====================================================================
  -- 5. Cambio de responsable a mitad (D7) y transferencia sin tocar el historial
  -- =====================================================================
  perform pg_temp.como(null);
  s5 := pg_temp.venta('s5', 'B', pg_temp.coop('prodelco', 'VC-COOP-2', gen_random_uuid()) - 'evidencia');
  update crm.inversion_solicitudes set datos = datos || jsonb_build_object('evidencia', jsonb_build_object('ruta',
    pg_temp.id('X') || '/' || s5 || '/comprobante.pdf')) where id = s5;
  update crm.inversion_solicitudes set hash_payload = private.idem_hash(datos) where id = s5;
  insert into storage.objects(bucket_id, name, metadata)
  values ('f4-comprobantes', pg_temp.id('X') || '/' || s5 || '/comprobante.pdf', '{"size":128,"mimetype":"application/pdf"}');
  -- B corrige su venta pendiente (D7: no se le exige nada del responsable).
  perform pg_temp.como('B');
  perform crm.corregir_solicitud_inversion_fn(s5, gen_random_uuid(), 0,
    (select datos from crm.inversion_solicitudes where id = s5) || '{"monto":3500}', 'Ajuste del monto acordado con el cliente');
  -- Gerencia transfiere X de A a A2 mientras la venta de B está pendiente.
  perform pg_temp.como('G');
  perform crm.reasignar_responsable_relacion_fn(pg_temp.id('X'), pg_temp.id('A2'), 'Reorganización de la cartera del equipo');
  perform pg_temp.como('A2');
  perform pg_temp.exigir(crm.solicitud_inversion_fn(s5)->>'estado' = 'preparada', 'A2, el nuevo responsable, ve la venta de B');
  perform pg_temp.rechaza(format('select crm.corregir_solicitud_inversion_fn(%L,%L,1,%L::jsonb,%L)', s5, gen_random_uuid(),
    (select datos from crm.inversion_solicitudes where id = s5), 'Intento del responsable'), '42501', 'la gestionan quien la registró');
  perform pg_temp.rechaza(format('select crm.cancelar_solicitud_inversion_fn(%L,1)', s5), '42501', 'la gestionan quien la registró');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,1)', s5), '42501', 'la gestionan quien la registró');
  perform pg_temp.rechaza(format('select crm.revisar_solicitud_inversion_fn(%L,%L,0,%L)', s5, pg_temp.id('A2'), 'Revisión del responsable'),
    '42501', 'la gestionan quien la registró');
  perform pg_temp.como('B');
  perform pg_temp.exigir((crm.solicitud_inversion_fn(s5)->>'requiere_revision_responsable')::boolean is false,
    'tras la transferencia, la venta cruzada no pide revisar el responsable (D7)');
  -- La excepción de D7 (acceso pendiente) la resuelve quien opera la venta: revisar acepta la llave.
  r := crm.revisar_solicitud_inversion_fn(s5, pg_temp.id('A2'), 0, 'El cliente pasó a la cartera de A2');
  perform pg_temp.exigir((select responsable_esperado_id = pg_temp.id('A2') from crm.inversion_solicitudes where id = s5),
    'B revisa su venta y acepta al nuevo responsable');
  -- C, ajeno a la venta y a X, no la consulta, corrige, cancela ni ve su bienvenida.
  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.cancelar_solicitud_inversion_fn(%L,1)', s5), '42501');
  perform pg_temp.rechaza(format('select crm.corregir_solicitud_inversion_fn(%L,%L,1,%L::jsonb,%L)', s5, gen_random_uuid(),
    (select datos from crm.inversion_solicitudes where id = s5), 'Intento de un analista ajeno'), '42501');
  perform pg_temp.rechaza(format('select crm.bienvenida_inversion_estado_fn(%L)', s5), '42501');
  perform pg_temp.como('B');
  r := crm.confirmar_inversion_revisada_fn(s5, 1);
  perform pg_temp.exigir((select vendedor_id = pg_temp.id('B') and monto = 3500 from crm.cierres_externos
    where id = (r#>>'{fuente,cierre_id}')::uuid), 'tras la transferencia, la venta sigue siendo de B');
  perform pg_temp.exigir((select responsable_relacion_id = pg_temp.id('A2') from crm.inversionistas where id = pg_temp.id('X')),
    'X ahora es de A2');
  perform pg_temp.exigir((select analista_cierre_id = pg_temp.id('B') from public.contratos where id = contrato_b)
    and (select analista_cierre_id = pg_temp.id('A') from public.contratos where id = contrato_a)
    and (select vendedor_id = pg_temp.id('B') from crm.cierres_externos where id = ce.id),
    'la transferencia no cambió ninguna inversión histórica');

  -- =====================================================================
  -- 5b. El supervisor de B confirma la venta cruzada de B: queda de B y la registra S2
  -- =====================================================================
  perform pg_temp.como(null);
  s7 := pg_temp.venta('s7', 'B', (d - 'inversionista_id') || jsonb_build_object('cuenta',
    (d->'cuenta') || '{"cci":"99999999999999999986","numero_cuenta":"VC-PEN-086"}'));
  perform pg_temp.como('S2');
  r := crm.confirmar_inversion_revisada_fn(s7, 0);
  perform pg_temp.exigir((select analista_cierre_id = pg_temp.id('B') and creado_por = pg_temp.id('S2') from public.contratos
    where id = (r#>>'{fuente,id}')::uuid) and r#>>'{fuente,pdf,estado}' is not null,
    'S2 confirma: el contrato es de B, lo registró S2 y tiene su trabajo de PDF');

  -- Gerencia cancela una venta cruzada abandonada (A ya no puede: D6 lo destraba así).
  perform pg_temp.como(null);
  s8 := pg_temp.venta('s8', 'B', pg_temp.coop('qorilazo', 'VC-COOP-8', gen_random_uuid()) - 'evidencia');
  update crm.inversion_solicitudes set datos = datos || jsonb_build_object('evidencia', jsonb_build_object('ruta',
    pg_temp.id('X') || '/' || s8 || '/comprobante.pdf')) where id = s8;
  update crm.inversion_solicitudes set hash_payload = private.idem_hash(datos) where id = s8;
  perform pg_temp.como('A2');
  perform pg_temp.rechaza(format('select crm.cancelar_solicitud_inversion_fn(%L,0)', s8), '42501', 'la gestionan quien la registró');
  perform pg_temp.como('G');
  perform pg_temp.exigir(crm.cancelar_solicitud_inversion_fn(s8, 0)->>'estado' = 'cancelada', 'Gerencia cancela la venta abandonada de B');

  -- =====================================================================
  -- 6. El analista tiene que seguir activo para cerrar
  -- =====================================================================
  perform pg_temp.como(null);
  s6 := pg_temp.venta('s6', 'C', (d - 'inversionista_id') || jsonb_build_object('cuenta',
    (d->'cuenta') || '{"cci":"99999999999999999994","numero_cuenta":"VC-PEN-003"}'));
end $pruebas$;

-- C deja el equipo con su venta pendiente (sentencia suelta: el banco no permite este
-- ajuste dentro de un bloque; solo para el caso, sin triggers).
set local session_replication_role = replica;
update crm.equipo set activo = false where perfil_id = pg_temp.id('C');
set local session_replication_role = origin;

do $pruebas_baja$
declare s6 uuid := pg_temp.id('s6');
begin
  perform pg_temp.como('S2');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)', s6), 'P0409', 'ya no está activo');
  perform pg_temp.como('C');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)', s6), '42501', 'No autorizado');
end $pruebas_baja$;

-- D2 solo mientras el cliente siga activo (auditoría P2).
do $d2_baja$ begin
  perform pg_temp.como(null);
  update public.perfiles set activo = false where id = pg_temp.id('PX');
  perform pg_temp.como('B');
  perform pg_temp.exigir(not private.puede_leer_contrato_pdf((select id from public.contratos
    where cliente_id = pg_temp.id('PX') and analista_cierre_id = pg_temp.id('B') limit 1)),
    'B ya no lee el PDF de un cliente dado de baja');
end $d2_baja$;

-- Como un commit: los controles diferidos pendientes (rentabilidad y operación de cartera
-- de public.contratos) se disparan aquí, antes de deshacer. Sin esto, una prueba que
-- termina en rollback nunca los ejerce.
set constraints all immediate;

select 'VENTA_CRUZADA_FASE3_OK' as veredicto;
rollback;
