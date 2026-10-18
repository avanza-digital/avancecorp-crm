-- Pruebas de 20261018032400 (recuperar las cinco ventas recargadas) en el BANCO Docker reemplazo-inv-db (esquema de
-- producción del 17/10/2026 con «Reemplazar inversión» aplicada, sin datos de producción). NO se corre sola: probar.sh
--   · le antepone la siembra y los ayudantes de la batería de la Fase 1 (../reemplazar-inversion/test-reemplazar-inversion.sql,
--     todo lo anterior a su bloque 0: configuración copiada de producción, plazo de septiembre al 22/10 00:00 Lima,
--     personas, leads d1..d5 con sus ventas);
--   · deja el texto de la migración en pg_temp.migracion_sql: el PREÁMBULO de su segunda transacción (candados y ajustes,
--     sin el «set transaction isolation level», que solo vale como primera sentencia) y el CUERPO desde «CASOS (inicio)»
--     hasta antes del commit final, con el bloque CASOS cambiado por la MISMA tabla temporal llenada con los casos que
--     se siembran aquí (pg_temp.casos_sembrados);
--   · pone la aplicación BASE de la migración (como postgres, el rol de `supabase db query --linked`) en la marca
--     «@@ MIGRACION @@» y cierra con ROLLBACK. Nada queda en el banco.
--
-- Los cinco casos se siembran con las puertas REALES y con la forma de producción:
--   1 A (como JULIO)        venta de octubre; «Eliminar contrato» (crm.contrato_eliminar_auditado) NO la anula; se vuelve a
--                           cargar «nuevo» al mismo cliente.
--   2 B (como NANCY)        igual, pero el original decía 01/10 (registro) y el recargado (inicio 30/09) nace en SEPTIEMBRE.
--   3 C (como MARIA AURORA) venta de octubre; «Eliminar inversión» (crm.eliminar_inversion_fn, Gerencia) la ANULA; recargado.
--   4 D (como VICTOR)       igual que C con otro analista; el recargado pasó por «upgrade» y Gerencia lo volvió a «nuevo».
--   5 E (como JOSE PEDRO)   venta de SEPTIEMBRE (30/09) borrada con «Eliminar contrato»; recargado con inicio 01/10 (y
--                           «upgrade» → «nuevo»).
-- A y B son REFERIDOS (como en producción). Controles: F, venta anulada por «Eliminar inversión», recargada y vuelta a enlazar
-- por la vía normal (NO está en los casos: debe seguir anulada); G, otro referido de a4 anterior a A que ya cuenta (el tope
-- de octubre, peso 1 y 15 %, reparte entre G y A: la SUMA de a4 sube una cuota y el aporte individual de A queda en 0).
-- Hecho del banco: con el lead enlazado, «Eliminar contrato» sin la válvula privilegiada falla (23503: el FK
-- leads_contrato_id_fkey, ON DELETE SET NULL, lo revierte private.leads_before_update; lo dice crm.eliminar_inversion_fn).
-- Por eso el borrado va con la válvula y el lead queda con contrato_id NULL: un contrato_id «colgante» no puede existir con
-- el FK validado. La variante V1 fuerza uno (sin triggers) para probar esa rama del preflight.

-- ── Ayudantes ──────────────────────────────────────────────────────────────────────────────────────────────────────────
create temporary table sembrados (clave text primary key, id uuid not null);
create function pg_temp.sembrado(p_clave text) returns uuid language sql stable as $$
  select s.id from pg_temp.sembrados s where s.clave = p_clave $$;

-- Cliente eN y lead fN convertido por p_analista el p_convertido (triggers apagados solo aquí, como la siembra de la Fase 1).
create function pg_temp.cliente_y_lead(p_n int, p_analista uuid, p_convertido timestamptz, p_origen text default 'landing') returns void language plpgsql as $f$
declare
  v_cliente uuid := ('e1000000-0000-4000-8000-00000000000' || p_n)::uuid;
  v_lead uuid := ('f1000000-0000-4000-8000-00000000000' || p_n)::uuid;
begin
  set local session_replication_role = replica;
  insert into auth.users (id) values (v_cliente);
  insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, dni, asesor_perfil_id, domicilio, correo)
    values (v_cliente, 'CLIENTE RECUPERAR ' || p_n || ' PRUEBA', 'cliente', true, 'DNI', '4300000' || p_n, p_analista,
      'Calle Recuperar ' || p_n, 'recuperar' || p_n || '@example.invalid');
  insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, convertido_en, vendedor_id, perfil_id, activo, monto_estimado)
    values (v_lead, 'LEAD RECUPERAR ' || p_n || ' PRUEBA', '+5199800000' || p_n, '4300000' || p_n, p_origen, 'convertido',
      p_convertido, p_analista, v_cliente, true, 1000);
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
      sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado,
      resultado_en, finalizado_en, finalizado_por, motivo_cierre)
    values (v_lead, 1, 1, p_analista, 'asignado', p_convertido - interval '5 days', 'PEN', p_origen,
      p_convertido - interval '5 days', gen_random_uuid(), p_convertido, p_convertido, 'convertido', p_convertido,
      p_convertido, p_analista, 'convertido');
  set local session_replication_role = origin;
end $f$;

-- «Eliminar contrato»: la Edge llama a crm.contrato_eliminar_auditado como service_role con el actor verificado (GER, admin del
-- portal). Con un lead convertido enlazado hace falta la válvula privilegiada (como en crm.eliminar_inversion_fn). NO anula.
create function pg_temp.eliminar_contrato(p_contrato uuid, p_valvula boolean default true) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  if p_valvula then perform set_config('crm.op_privilegiada', 'on', true); end if;
  set local role service_role;
  r := crm.contrato_eliminar_auditado(p_contrato, 'a0000000-0000-4000-8000-0000000000a2');
  reset role;
  perform set_config('crm.op_privilegiada', 'off', true);
  return r;
end $f$;

-- «Eliminar inversión» como Gerencia (GER es admin del portal y Gerencia del CRM): con una venta, la ANULA y la elimina.
create function pg_temp.eliminar_inversion(p_contrato uuid) returns jsonb language sql as $f$
  select pg_temp.api('a0000000-0000-4000-8000-0000000000a2',
    format('select crm.eliminar_inversion_fn(%L::uuid, %L)', p_contrato, 'Error de carga: se borra para volver a cargarla')) $f$;

-- «Corregir categoría» como Gerencia.
create function pg_temp.corregir_categoria(p_contrato uuid, p_categoria text, p_motivo text) returns jsonb language sql as $f$
  select pg_temp.api('a0000000-0000-4000-8000-0000000000a2',
    format('select crm.corregir_categoria_contrato_fn(%L::uuid, %L, %L)', p_contrato, p_categoria, p_motivo)) $f$;

-- Aplica la migración como postgres: preámbulo + cuerpo de pg_temp.migracion_sql. p_inyecciones = {ancla corta del cuerpo:
-- SQL que se ejecuta justo ANTES de esa ancla}: así una prueba altera algo «durante» la migración. Anclas semánticas (no
-- números de sección): 'create table crm.conversion_ventas_recuperadas' (ya tomada la foto de ANTES, nada cambiado todavía)
-- y 'do $postflight$' (todo hecho, falta el postflight). Si el ancla no aparece exactamente una vez: ERROR DE ENSAYO.
-- El SQL inyectado corre como postgres y con search_path vacío (el de la migración).
create function pg_temp.aplicar(p_inyecciones jsonb default '{}'::jsonb) returns void language plpgsql as $f$
declare
  v_cuerpo text := (select m.sql from pg_temp.migracion_sql m where m.parte = 'cuerpo');
  v_marca text;
begin
  for v_marca in select pg_catalog.jsonb_object_keys(p_inyecciones) loop
    if (pg_catalog.length(v_cuerpo) - pg_catalog.length(pg_catalog.replace(v_cuerpo, v_marca, ''))) / pg_catalog.length(v_marca) <> 1 then
      raise exception 'ENSAYO: la marca «%» no aparece exactamente una vez en el cuerpo de la migración', v_marca;
    end if;
    v_cuerpo := pg_catalog.replace(v_cuerpo, v_marca, (p_inyecciones ->> v_marca) || E'\n' || v_marca);
  end loop;
  -- Como `supabase db query --linked`: sin sesión de usuario (auth.uid() nulo). Las pruebas anteriores dejan las claims del
  -- JWT de Gerencia puestas (pg_temp.api no las limpia) y con ellas el trigger de atribución de crm.actividades rechazaría
  -- la nota de la migración (creado_por nulo ≠ auth.uid()).
  perform pg_temp.como(null);
  set local role postgres;
  execute (select m.sql from pg_temp.migracion_sql m where m.parte = 'preambulo') || v_cuerpo;
  reset role;
end $f$;

-- Un error que no es de negocio (SQL mal formado, objeto que no existe) es del ENSAYO, no una defensa: se re-lanza así para
-- que probar.sh no lo cuente como un mutante muerto.
create function pg_temp.es_error_de_ensayo(p_estado text, p_mensaje text) returns boolean language sql immutable as $$
  select p_mensaje like 'ENSAYO:%' or p_estado in ('42601', '42883', '42P01', '42703', '42704', '42P02') $$;

-- La migración tiene que RECHAZAR con p_estado y p_mensaje (dentro del texto). Lo que hizo se deshace.
create function pg_temp.rechaza_migracion(p_estado text, p_mensaje text, p_inyecciones jsonb default '{}'::jsonb) returns void
language plpgsql as $f$
begin
  begin
    perform pg_temp.aplicar(p_inyecciones);
  exception when others then
    reset role;
    if pg_temp.es_error_de_ensayo(sqlstate, sqlerrm) then
      raise exception 'ENSAYO: % «%»', sqlstate, sqlerrm;
    end if;
    if sqlstate = p_estado and position(p_mensaje in sqlerrm) > 0 then
      return;
    end if;
    raise exception 'FALLA: se esperaba % «%», llegó % «%»', p_estado, p_mensaje, sqlstate, sqlerrm;
  end;
  reset role;
  raise exception 'FALLA: la migración debió rechazar con % «%» y se aplicó', p_estado, p_mensaje;
end $f$;

-- La migración tiene que APLICARSE (si no, FALLA con el motivo).
create function pg_temp.aplicar_ok(p_etiqueta text, p_inyecciones jsonb default '{}'::jsonb) returns void language plpgsql as $f$
begin
  perform pg_temp.aplicar(p_inyecciones);
exception when others then
  reset role;
  if pg_temp.es_error_de_ensayo(sqlstate, sqlerrm) then
    raise exception 'ENSAYO: % «%»', sqlstate, sqlerrm;
  end if;
  raise exception 'FALLA: % — la migración debió aplicarse y falló con % «%»', p_etiqueta, sqlstate, sqlerrm;
end $f$;

-- Un rechazo: prepara el estado (SQL), aplica esperando el rechazo y lo deshace TODO con el centinela P7999.
create function pg_temp.caso_rechazo(p_etiqueta text, p_preparar text, p_estado text, p_mensaje text,
  p_inyecciones jsonb default '{}'::jsonb) returns void language plpgsql as $f$
begin
  begin
    if p_preparar is not null then execute p_preparar; end if;
    perform pg_temp.rechaza_migracion(p_estado, p_mensaje, p_inyecciones);
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS %', p_etiqueta;
end $f$;

-- Una aplicación que debe pasar: prepara, aplica, comprueba (SQL con pg_temp.exigir) y lo deshace TODO.
create function pg_temp.caso_aplica(p_etiqueta text, p_preparar text, p_inyecciones jsonb, p_comprobar text) returns void
language plpgsql as $f$
begin
  begin
    if p_preparar is not null then execute p_preparar; end if;
    perform pg_temp.aplicar_ok(p_etiqueta, p_inyecciones);
    reset search_path;
    if p_comprobar is not null then execute p_comprobar; end if;
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS %', p_etiqueta;
end $f$;

-- El informe «Altas nuevas» (crm.altas_nuevas_por_analista_fn) y el chip «CIERRE ANULADO» (crm.cierres_estado_fn), como
-- Gerencia (GER): las dos leen crm.cierres_avance_anulados directamente y la v2 de la migración las parcha por ancla.
create function pg_temp.altas_json() returns jsonb language sql as $$
  select pg_temp.api('a0000000-0000-4000-8000-0000000000a2',
    $q$ select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from crm.altas_nuevas_por_analista_fn(3) x $q$) $$;
create function pg_temp.altas_de(p_json jsonb, p_mes date, p_analista uuid) returns bigint language sql as $$
  select coalesce((select (e ->> 'altas')::bigint from jsonb_array_elements(p_json) e
                   where (e ->> 'mes')::date = p_mes and (e ->> 'analista_id')::uuid = p_analista), 0) $$;
create function pg_temp.estado_cierres(p_leads uuid[]) returns jsonb language sql as $$
  select pg_temp.api('a0000000-0000-4000-8000-0000000000a2', format('select crm.cierres_estado_fn(%L::uuid[])', p_leads)) $$;

-- La cifra OFICIAL (tope de referidos aplicado): private.conversion_episodios. pg_temp.cuenta_conversion (Fase 1) suma el
-- aporte BRUTO de private.conversion_cierres, antes del tope: un referido pesa 1 ahí y 0,15 (o lo que reparta el tope) aquí.
create function pg_temp.cuenta_oficial(p_periodo date) returns numeric language sql as $$
  select coalesce(sum(x.aporte_numerador), 0)
  from private.conversion_episodios(p_periodo::timestamp at time zone 'America/Lima', (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima',
                                    null, true, null, 1) x
  where x.tipo = 'cierre' and not x.anulado $$;

create function pg_temp.cierres_validos(p_lead uuid) returns bigint language sql as $$
  select count(*) from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
  where x.tipo = 'cierre' and x.lead_id = p_lead and not x.anulado and x.aporte_numerador > 0 $$;

-- ── S · Siembra de los cinco casos y del control, con las puertas reales ───────────────────────────────────────────────
-- Agosto sellado, como producción: no es un mes de estos casos y no debe estorbar.
set local session_replication_role = replica;
insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
  values ('2026-08-01', '2026-09-11 00:05-05', 'a0000000-0000-4000-8000-0000000000a2', false, 0.15, 0, '{}');
set local session_replication_role = origin;
-- A y B son REFERIDOS (como Julio César y Nancy en producción); G es otro referido de a4, anterior a A, que ya cuenta.
select pg_temp.cliente_y_lead(1, 'a0000000-0000-4000-8000-0000000000a4', '2026-10-05 15:00-05', 'referido');
select pg_temp.cliente_y_lead(2, 'a0000000-0000-4000-8000-0000000000a7', '2026-10-01 15:00-05', 'referido');
select pg_temp.cliente_y_lead(7, 'a0000000-0000-4000-8000-0000000000a4', '2026-10-03 15:00-05', 'referido');
select pg_temp.cliente_y_lead(3, 'a0000000-0000-4000-8000-0000000000a4', '2026-10-10 15:00-05');
select pg_temp.cliente_y_lead(4, 'a0000000-0000-4000-8000-0000000000a7', '2026-10-12 15:00-05');
select pg_temp.cliente_y_lead(5, 'a0000000-0000-4000-8000-0000000000a4', '2026-09-28 15:00-05');
select pg_temp.cliente_y_lead(6, 'a0000000-0000-4000-8000-0000000000a4', '2026-10-08 15:00-05');

do $s$
declare
  v uuid; r jsonb;
  a4 constant uuid := 'a0000000-0000-4000-8000-0000000000a4';
  a7 constant uuid := 'a0000000-0000-4000-8000-0000000000a7';
begin
  -- 1 A · venta de octubre, «Eliminar contrato», recargado «nuevo» con el mismo número.
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000001', '2026-01-930001', 5000, 'PEN', 15, date '2026-10-05', a4), pg_temp.cuenta(301));
  insert into pg_temp.sembrados values ('k1', v);
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000001', v);
  set constraints all immediate; set constraints all deferred;
  perform pg_temp.rechaza(format('select pg_temp.eliminar_contrato(%L::uuid, false)', v), '23503', 'leads_contrato_id_fkey');
  r := pg_temp.eliminar_contrato(v);
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000001', '2026-01-930001', 5000, 'PEN', 15, date '2026-10-05', a4), pg_temp.cuenta(302));
  insert into pg_temp.sembrados values ('r1', v);
  set constraints all immediate; set constraints all deferred;

  -- 2 B · el original se registró el 01/10 (fuente «registro»); el recargado empieza el 30/09 y nace en septiembre.
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000002', '2026-01-930002', 10000, 'PEN', 15, date '2026-10-01', a7), pg_temp.cuenta(303));
  insert into pg_temp.sembrados values ('k2', v);
  set local session_replication_role = replica;
  update public.contratos set creado_en = timestamptz '2026-10-01 10:00-05', fuente_cierre_comercial = 'registro' where id = v;
  set local session_replication_role = origin;
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000002', v);
  set constraints all immediate; set constraints all deferred;
  r := pg_temp.eliminar_contrato(v);
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000002', '2026-01-930003', 10000, 'PEN', 15, date '2026-09-30', a7), pg_temp.cuenta(304));
  insert into pg_temp.sembrados values ('r2', v);
  set constraints all immediate; set constraints all deferred;

  -- 3 C · «Eliminar inversión» anula la venta; recargado «nuevo».
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000003', '2026-01-930004', 3000, 'PEN', 15, date '2026-10-10', a4), pg_temp.cuenta(305));
  insert into pg_temp.sembrados values ('k3', v);
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000003', v);
  set constraints all immediate; set constraints all deferred;
  r := pg_temp.eliminar_inversion(v);
  perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean, 'S 3 C: «Eliminar inversión» anula la venta');
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000003', '2026-01-930004', 3000, 'PEN', 15, date '2026-10-16', a4), pg_temp.cuenta(306));
  insert into pg_temp.sembrados values ('r3', v);
  set constraints all immediate; set constraints all deferred;

  -- 4 D · igual que C con VEN2; el recargado pasa por «upgrade» y Gerencia lo vuelve a «nuevo» con «Corregir categoría».
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000004', '2026-01-930005', 4000, 'PEN', 15, date '2026-10-12', a7), pg_temp.cuenta(307));
  insert into pg_temp.sembrados values ('k4', v);
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000004', v);
  set constraints all immediate; set constraints all deferred;
  r := pg_temp.eliminar_inversion(v);
  perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean, 'S 4 D: «Eliminar inversión» anula la venta');
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000004', '2026-01-930005', 4000, 'PEN', 15, date '2026-10-15', a7), pg_temp.cuenta(308));
  insert into pg_temp.sembrados values ('r4', v);
  set constraints all immediate; set constraints all deferred;
  perform pg_temp.corregir_categoria(v, 'upgrade', 'Se cargó como upgrade (como en producción)');
  set constraints all immediate; set constraints all deferred;
  perform pg_temp.corregir_categoria(v, 'nuevo', 'Era una inversión nueva: Corregir categoría');
  set constraints all immediate; set constraints all deferred;

  -- 5 E · venta de SEPTIEMBRE (30/09) borrada con «Eliminar contrato»; recargado con inicio 01/10 y «upgrade» → «nuevo».
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000005', '2026-01-930006', 353000, 'PEN', 15, date '2026-09-30', a4), pg_temp.cuenta(309));
  insert into pg_temp.sembrados values ('k5', v);
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000005', v);
  set constraints all immediate; set constraints all deferred;
  r := pg_temp.eliminar_contrato(v);
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000005', '2026-01-930007', 353000, 'PEN', 15, date '2026-10-01', a4), pg_temp.cuenta(310));
  insert into pg_temp.sembrados values ('r5', v);
  set constraints all immediate; set constraints all deferred;
  perform pg_temp.corregir_categoria(v, 'upgrade', 'Se cargó como upgrade (como en producción)');
  set constraints all immediate; set constraints all deferred;
  perform pg_temp.corregir_categoria(v, 'nuevo', 'Era una inversión nueva: Corregir categoría');
  set constraints all immediate; set constraints all deferred;

  -- G · CONTROL referido de a4 (03/10, antes de A): venta normal que ya cuenta. Con el tope de octubre (peso 1, 15 %) hoy
  --     aporta 0,15; al recuperar A, el tope reparte 0,30 entre G y A en orden de fecha: G 0,30 y A 0 (la SUMA sube 0,15).
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000007', '2026-01-930009', 1500, 'PEN', 15, date '2026-10-03', a4), pg_temp.cuenta(313));
  insert into pg_temp.sembrados values ('g7', v);
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000007', v);
  set constraints all immediate; set constraints all deferred;

  -- F · CONTROL: anulada por «Eliminar inversión», recargada y vuelta a enlazar por la vía normal. No está en los casos.
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000006', '2026-01-930008', 2500, 'PEN', 15, date '2026-10-08', a4), pg_temp.cuenta(311));
  insert into pg_temp.sembrados values ('k6', v);
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000006', v);
  set constraints all immediate; set constraints all deferred;
  r := pg_temp.eliminar_inversion(v);
  perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean, 'S F: «Eliminar inversión» anula la venta');
  v := pg_temp.alta(pg_temp.contrato('e1000000-0000-4000-8000-000000000006', '2026-01-930008', 2500, 'PEN', 15, date '2026-10-08', a4), pg_temp.cuenta(312));
  insert into pg_temp.sembrados values ('r6', v);
  perform pg_temp.enlazar('f1000000-0000-4000-8000-000000000006', v);
  set constraints all immediate; set constraints all deferred;
end $s$;
set constraints all deferred;

-- Los casos, con las MISMAS columnas que pg_temp.recuperar_casos de la migración (probar.sh copia de aquí).
create temporary table casos_sembrados (
  caso text primary key, lead_id uuid not null, perfil_id uuid not null, acreditacion_id uuid not null, analista_id uuid not null,
  fuente_borrada uuid not null, recargado uuid not null, capital numeric not null, moneda text not null, periodo date not null,
  fecha_actual date not null, fecha_final date not null, anulacion_id uuid, copia_anulada_id uuid);
insert into pg_temp.casos_sembrados
select x.caso, x.lead_id, x.perfil_id, ca.id, x.analista, pg_temp.sembrado('k' || x.n), pg_temp.sembrado('r' || x.n),
  ct.capital, ct.moneda, x.periodo, x.fecha_actual, x.fecha_final,
  (select a.id from crm.cierres_avance_anulados a where a.lead_id = x.lead_id),
  (select ie.id from crm.inversiones_eliminadas ie where ie.lead_id = x.lead_id and ie.conversion_anulada)
from (select v.*, ('f1000000-0000-4000-8000-00000000000' || v.n)::uuid as lead_id,
        ('e1000000-0000-4000-8000-00000000000' || v.n)::uuid as perfil_id
      from (values
        (1, '1 A', 'a0000000-0000-4000-8000-0000000000a4'::uuid, date '2026-10-01', date '2026-10-05', date '2026-10-05'),
        (2, '2 B', 'a0000000-0000-4000-8000-0000000000a7'::uuid, date '2026-10-01', date '2026-09-30', date '2026-10-01'),
        (3, '3 C', 'a0000000-0000-4000-8000-0000000000a4'::uuid, date '2026-10-01', date '2026-10-16', date '2026-10-16'),
        (4, '4 D', 'a0000000-0000-4000-8000-0000000000a7'::uuid, date '2026-10-01', date '2026-10-15', date '2026-10-15'),
        (5, '5 E', 'a0000000-0000-4000-8000-0000000000a4'::uuid, date '2026-09-01', date '2026-10-01', date '2026-09-30')
      ) v(n, caso, analista, periodo, fecha_actual, fecha_final)) x
join crm.conversion_acreditaciones ca on ca.lead_id = x.lead_id
join public.contratos ct on ct.id = pg_temp.sembrado('r' || x.n);
grant select on pg_temp.casos_sembrados to postgres;

do $s1$
declare c record; v_acr crm.conversion_acreditaciones; v_ctr public.contratos; v_lead crm.leads;
begin
  perform pg_temp.exigir((select count(*) from pg_temp.casos_sembrados) = 5, 'S: cinco casos sembrados');
  for c in select * from pg_temp.casos_sembrados order by caso loop
    select * into v_lead from crm.leads l where l.id = c.lead_id;
    select * into v_acr from crm.conversion_acreditaciones ca where ca.lead_id = c.lead_id;
    select * into v_ctr from public.contratos ct where ct.id = c.recargado;
    perform pg_temp.exigir(v_lead.etapa = 'convertido' and v_lead.perfil_id = c.perfil_id and v_lead.contrato_id is null,
      format('S %s: lead convertido del cliente y sin contrato enlazado (el FK lo dejó en NULL al borrar)', c.caso));
    perform pg_temp.exigir(v_acr.fuente_tipo = 'contrato' and v_acr.fuente_id = c.fuente_borrada and v_acr.estado = 'acreditada'
      and v_acr.periodo_comercial = c.periodo and v_acr.analista_id = c.analista_id,
      format('S %s: la acreditación sigue apuntando al contrato BORRADO, acreditada en %s', c.caso, c.periodo));
    perform pg_temp.exigir(not exists (select 1 from public.contratos ct where ct.id = c.fuente_borrada)
      and exists (select 1 from crm.contratos_eliminados_auditoria a where a.contrato_id = c.fuente_borrada)
      and private.conversion_exclusion_fuente('contrato', c.fuente_borrada) = 'fuente_retirada',
      format('S %s: el original se borró con su auditoría y la métrica lo ve como fuente retirada', c.caso));
    perform pg_temp.exigir(v_ctr.cliente_id = c.perfil_id and v_ctr.categoria = 'nuevo' and v_ctr.estado = 'activo'
      and not coalesce(v_ctr.es_demo, false) and v_ctr.analista_cierre_id = c.analista_id
      and v_ctr.fecha_cierre_comercial = c.fecha_actual and v_ctr.fuente_cierre_comercial = 'fecha_inicio_inferida',
      format('S %s: el recargado es «nuevo», del mismo cliente y analista, con fecha %s (inferida del inicio)', c.caso, c.fecha_actual));
    perform pg_temp.exigir(not exists (select 1 from crm.conversion_acreditaciones o where o.fuente_tipo = 'contrato' and o.fuente_id = c.recargado),
      format('S %s: el recargado no es la venta de nadie', c.caso));
    perform pg_temp.exigir(private.cierre_anulado(c.lead_id) = (c.anulacion_id is not null)
      and (c.anulacion_id is null) = (c.copia_anulada_id is null),
      format('S %s: anulada solo si la borró «Eliminar inversión» (anulación y copia)', c.caso));
    -- EL DEFECTO: la venta no cuenta en la conversión (sin cierre válido en private.conversion_episodios).
    perform pg_temp.exigir(pg_temp.cierres_validos(c.lead_id) = 0, format('S %s: ANTES la venta NO cuenta (el defecto)', c.caso));
  end loop;
  perform pg_temp.exigir((select count(*) from crm.inversiones_eliminadas ie join pg_temp.casos_sembrados cs on cs.copia_anulada_id = ie.id
      where ie.lead_id = cs.lead_id and ie.conversion_anulada and ie.reemplazada_por is null and ie.fuente_tipo = 'contrato'
        and ie.fuente_id = cs.fuente_borrada) = 2, 'S: C y D con su copia de «Eliminar inversión» con la venta anulada');
  perform pg_temp.exigir((select count(*) from crm.correcciones_categoria_contrato x
      where x.contrato_id in (pg_temp.sembrado('r4'), pg_temp.sembrado('r5')) and x.categoria_anterior = 'upgrade'
        and x.categoria_nueva = 'nuevo') = 2, 'S: D y E pasaron de «upgrade» a «nuevo» con «Corregir categoría»');
  perform pg_temp.exigir((select a.snapshot #>> '{contrato,fuente_cierre_comercial}' = 'registro'
      and a.snapshot #>> '{contrato,fecha_cierre_comercial}' = '2026-10-01'
    from crm.contratos_eliminados_auditoria a where a.contrato_id = pg_temp.sembrado('k2')), 'S 2 B: el original decía 01/10 (registro)');
  perform pg_temp.exigir(private.cierre_anulado('f1000000-0000-4000-8000-000000000006')
    and (pg_temp.acr('f1000000-0000-4000-8000-000000000006')).fuente_id = pg_temp.sembrado('r6')
    and (pg_temp.acr('f1000000-0000-4000-8000-000000000006')).estado = 'acreditada'
    and exists (select 1 from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
                where x.tipo = 'cierre' and x.lead_id = 'f1000000-0000-4000-8000-000000000006' and x.anulado and x.aporte_numerador = 0),
    'S F: el control quedó acreditado al recargado pero ANULADO (su cierre sale anulado)');
  perform pg_temp.exigir((pg_temp.acr('f1000000-0000-4000-8000-000000000001')).origen = 'referido' and (pg_temp.acr('f1000000-0000-4000-8000-000000000002')).origen = 'referido'
      and (select x.aporte_numerador from private.conversion_episodios(timestamptz '2026-10-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
           where x.tipo = 'cierre' and x.lead_id = 'f1000000-0000-4000-8000-000000000007') = 0.15,
    'S: A y B son referidos (acreditación con origen referido) y el control G cuenta 0,15 (peso 1 recortado al tope del 15 %)');
  perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 5 and pg_temp.cuenta_conversion('2026-09-01') = 1
      and pg_temp.cuenta_oficial('2026-10-01') = 4.15 and pg_temp.cuenta_oficial('2026-09-01') = 1,
    format('S: la conversión está en octubre 5 bruto / 4,15 oficial (d1..d4 de la Fase 1 + G con el tope) y septiembre 1; ninguna de las cinco cuenta (oct %s / %s, sep %s)',
      pg_temp.cuenta_conversion('2026-10-01'), pg_temp.cuenta_oficial('2026-10-01'), pg_temp.cuenta_conversion('2026-09-01')));
  raise notice 'PASS S siembra: 5 casos con la forma de producción (acreditación al borrado, 2 anuladas, A y B referidos, B y E con fecha en otro mes) + controles F y G; ninguna cuenta';
end $s1$;

-- La migración exige el candado de SESIÓN de migraciones; la prueba lo toma como lo haría la migración.
select pg_catalog.pg_advisory_lock(pg_catalog.hashtext('crm_migracion_funciones'));

-- ── P · Rechazos del preflight (cada uno en una subtransacción que se deshace) ─────────────────────────────────────────
do $p1$
begin
  perform pg_temp.exigir(pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('crm_migracion_funciones')), 'P1: la sesión tenía el candado');
  perform pg_temp.rechaza_migracion('P0001', 'PREFLIGHT recuperar_ventas: esta sesión no tiene el candado de migraciones');
  perform pg_catalog.pg_advisory_lock(pg_catalog.hashtext('crm_migracion_funciones'));
  raise notice 'PASS P1 sin el candado de sesión de migraciones: rechazo';
end $p1$;

select pg_temp.caso_rechazo('P2 cambió una función que llama (costo de private.conversion_acreditar_fuente): rechazo',
  $prep$
    alter function private.conversion_acreditar_fuente(uuid, text, uuid, text) cost 101;
    do $x$ begin perform pg_temp.exigir(md5(pg_catalog.pg_get_functiondef('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure))
      <> '872930922a1d477e27b23243cbfe691a', 'P2: el costo cambia la huella'); end $x$;
  $prep$, 'P0001', 'PREFLIGHT recuperar_ventas: cambió una función que la corrección cambia o llama');

select pg_temp.caso_rechazo('P3 metadatos de una función que se cambia (otro dueño de private.cierre_anulado, misma huella): rechazo',
  $prep$
    alter function private.cierre_anulado(uuid) owner to supabase_admin;
    do $x$ begin perform pg_temp.exigir(md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure))
      = 'df71c2b1e3cd44b97c3ad84e00637266', 'P3: el dueño no cambia la huella'); end $x$;
  $prep$, 'P0001', 'PREFLIGHT recuperar_ventas: cambiaron los metadatos de una función que se cambia');

select pg_temp.caso_rechazo('P4a la tabla nueva ya existe: rechazo',
  'create table crm.conversion_ventas_recuperadas (id uuid)',
  'P0001', 'PREFLIGHT recuperar_ventas: los objetos nuevos ya existen');

select pg_temp.caso_rechazo('P4b la función nueva ya existe: rechazo',
  $prep$ create function private.proteger_venta_recuperada() returns trigger language plpgsql as $x$ begin return null; end $x$; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas: los objetos nuevos ya existen');

select pg_temp.caso_rechazo('P5a cuatro casos: rechazo',
  $prep$ delete from pg_temp.casos_sembrados where caso = '5 E' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas: se esperaban 5 casos');

select pg_temp.caso_rechazo('P5b seis casos: rechazo',
  $prep$ insert into pg_temp.casos_sembrados select '6 F', 'f1000000-0000-4000-8000-000000000006', 'e1000000-0000-4000-8000-000000000006',
    (pg_temp.acr('f1000000-0000-4000-8000-000000000006')).id, 'a0000000-0000-4000-8000-0000000000a4', pg_temp.sembrado('k6'),
    pg_temp.sembrado('r6'), 2500, 'PEN', date '2026-10-01', date '2026-10-08', date '2026-10-08', null, null $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas: se esperaban 5 casos');

select pg_temp.caso_rechazo('P6a octubre sellado (conversión): rechazo',
  $prep$ set local session_replication_role = replica;
    insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
      values ('2026-10-01', now(), 'a0000000-0000-4000-8000-0000000000a2', false, 1, 0, '{}');
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas: un mes de estas ventas ya está sellado o queda fuera de septiembre-octubre');

select pg_temp.caso_rechazo('P6b un mes POSTERIOR sellado (noviembre): rechazo',
  $prep$ set local session_replication_role = replica;
    insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
      values ('2026-11-01', now(), 'a0000000-0000-4000-8000-0000000000a2', false, 1, 0, '{}');
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas: un mes de estas ventas ya está sellado o queda fuera de septiembre-octubre');

select pg_temp.caso_rechazo('P6c septiembre sellado en CAPITAL: rechazo',
  $prep$ set local session_replication_role = replica;
    insert into crm.capital_mes_sellos (periodo, corte_id) values ('2026-09-01', gen_random_uuid());
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas: un mes de estas ventas ya está sellado o queda fuera de septiembre-octubre');

select pg_temp.caso_rechazo('P6d un caso con el mes antes de septiembre: rechazo',
  $prep$ update pg_temp.casos_sembrados set periodo = date '2026-08-01' where caso = '5 E' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas: un mes de estas ventas ya está sellado o queda fuera de septiembre-octubre');

select pg_temp.caso_rechazo('P7 plazo de carga de septiembre vencido: rechazo',
  $prep$ set local session_replication_role = replica;
    insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por, decidido_en)
      values ('2026-09-01', '2026-10-10', timestamptz '2026-10-11 00:00-05', 'banco: plazo vencido', 'a0000000-0000-4000-8000-0000000000a2', now());
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 5 E: venció el plazo de carga de 09/2026; no se hizo ningún cambio');

select pg_temp.caso_rechazo('P8 recargado en «upgrade»: rechazo con «Corregir categoría»',
  format('select pg_temp.corregir_categoria(%L::uuid, %L, %L)', pg_temp.sembrado('r1'), 'upgrade', 'Prueba: vuelve a upgrade'),
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: el contrato vivo es «upgrade»; antes hay que pasarlo a «nuevo» con «Corregir categoría»');

select pg_temp.caso_rechazo('P9 el contrato «borrado» existe: rechazo',
  format($prep$ set local session_replication_role = replica;
    insert into public.contratos select (jsonb_populate_record(null::public.contratos, to_jsonb(c)
      || jsonb_build_object('id', %L::uuid, 'numero_contrato', '2026-01-939001'))).* from public.contratos c where c.id = %L::uuid;
    set local session_replication_role = origin; $prep$, pg_temp.sembrado('k1'), pg_temp.sembrado('r1')),
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: el contrato borrado existe');

select pg_temp.caso_rechazo('P10a acreditación distinta de la medida (id): rechazo',
  $prep$ update pg_temp.casos_sembrados set acreditacion_id = gen_random_uuid() where caso = '3 C' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 3 C: la acreditación no está como se midió');

select pg_temp.caso_rechazo('P10b acreditación en otro estado: rechazo',
  $prep$ set local session_replication_role = replica;
    update crm.conversion_acreditaciones set estado = 'fuera_de_plazo' where lead_id = 'f1000000-0000-4000-8000-000000000002';
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 2 B: la acreditación no está como se midió');

select pg_temp.caso_rechazo('P10c acreditación de otro analista: rechazo',
  $prep$ update pg_temp.casos_sembrados set analista_id = 'a0000000-0000-4000-8000-0000000000a4' where caso = '4 D' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 4 D: la acreditación no está como se midió');

select pg_temp.caso_rechazo('P10d acreditación ya sellada (sellado_en, aunque no incluida): rechazo',
  $prep$ set local session_replication_role = replica;
    update crm.conversion_acreditaciones set sellado_en = now(), incluida_en_sello = false where lead_id = 'f1000000-0000-4000-8000-000000000002';
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 2 B: la acreditación no está como se midió');

select pg_temp.caso_rechazo('P10e acreditación en otro mes comercial que el del caso: rechazo',
  $prep$ update pg_temp.casos_sembrados set periodo = date '2026-09-01' where caso = '1 A' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: la acreditación no está como se midió');

select pg_temp.caso_rechazo('P11a anulación distinta (otra fila de anulación): rechazo',
  $prep$ update pg_temp.casos_sembrados set anulacion_id = gen_random_uuid() where caso = '4 D' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 4 D: la anulación no es exactamente la medida');

select pg_temp.caso_rechazo('P11b anulación distinta (otra copia): rechazo',
  $prep$ update pg_temp.casos_sembrados set copia_anulada_id = gen_random_uuid() where caso = '3 C' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 3 C: la anulación no es exactamente la medida');

select pg_temp.caso_rechazo('P11c una SEGUNDA copia anulada del mismo lead: rechazo',
  $prep$ set local session_replication_role = replica;
    insert into crm.inversiones_eliminadas select (jsonb_populate_record(null::crm.inversiones_eliminadas, to_jsonb(ie)
      || jsonb_build_object('id', gen_random_uuid(), 'valvula', gen_random_uuid(), 'fuente_id', gen_random_uuid()))).*
    from crm.inversiones_eliminadas ie where ie.id = (select c.copia_anulada_id from pg_temp.casos_sembrados c where c.caso = '3 C');
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 3 C: la anulación no es exactamente la medida');

select pg_temp.caso_rechazo('P11d venta anulada que los casos no declaran anulada: rechazo',
  $prep$ update pg_temp.casos_sembrados set anulacion_id = null, copia_anulada_id = null where caso = '3 C' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 3 C: la venta está anulada y no figura como anulada en los casos');

select pg_temp.caso_rechazo('P12a lead de otro perfil: rechazo',
  $prep$ update pg_temp.casos_sembrados set perfil_id = gen_random_uuid() where caso = '2 B' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 2 B: el lead no está como se midió');

select pg_temp.caso_rechazo('P12b lead enlazado a OTRO contrato: rechazo',
  format($prep$ set local session_replication_role = replica;
    update crm.leads set contrato_id = %L::uuid where id = 'f1000000-0000-4000-8000-000000000002';
    set local session_replication_role = origin; $prep$, pg_temp.sembrado('r1')),
  'P0001', 'PREFLIGHT recuperar_ventas 2 B: el lead no está como se midió');

select pg_temp.caso_rechazo('P13 contrato vivo con otra fecha comercial: rechazo',
  $prep$ update pg_temp.casos_sembrados set fecha_actual = fecha_actual + 1 where caso = '1 A' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: el contrato vivo no está como se midió');

select pg_temp.caso_rechazo('P13b contrato vivo con otro capital: rechazo',
  $prep$ update pg_temp.casos_sembrados set capital = capital + 1 where caso = '1 A' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: el contrato vivo no está como se midió');

select pg_temp.caso_rechazo('P13c contrato vivo en otra moneda: rechazo',
  $prep$ update pg_temp.casos_sembrados set moneda = 'USD' where caso = '1 A' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: el contrato vivo no está como se midió');

select pg_temp.caso_rechazo('P14 el contrato vivo ya es la venta de otro lead: rechazo',
  format($prep$ set local session_replication_role = replica;
    update crm.conversion_acreditaciones set fuente_id = %L::uuid where lead_id = 'd1000000-0000-4000-8000-000000000001';
    set local session_replication_role = origin; $prep$, pg_temp.sembrado('r1')),
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: el contrato vivo ya es la venta de otro lead');

select pg_temp.caso_rechazo('P15 fecha final fuera del mes esperado: rechazo',
  $prep$ update pg_temp.casos_sembrados set fecha_final = date '2026-09-30' where caso = '1 A' $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 1 A: la fecha final no cae en el mes esperado');

select pg_temp.caso_rechazo('P16 lead con ajuste de mes cerrado: rechazo',
  $prep$ set local session_replication_role = replica;
    insert into crm.ajustes_mes_cerrado (vendedor_id, periodo_origen, lead_id, motivo, creado_por, numerador, pendiente_numerador)
      values ('a0000000-0000-4000-8000-0000000000a4', '2026-08-01', 'f1000000-0000-4000-8000-000000000003', 'Ajuste de prueba',
        'a0000000-0000-4000-8000-0000000000a2', 1, 1);
    set local session_replication_role = origin; $prep$,
  'P0001', 'PREFLIGHT recuperar_ventas 3 C: el lead tiene un ajuste de mes cerrado; requiere revisión');

-- La red final de la migración (el INVARIANTE del paso 3d): si el escritor de acreditaciones dejara la venta en otro estado
-- (regla del plazo cambiada en private.conversion_decidir_plazo, que el preflight no mira), la migración aborta TODO.
select pg_temp.caso_rechazo('P17 la venta no queda acreditada (invariante del paso 3d): aborta todo',
  $prep$
    create or replace function private.conversion_decidir_plazo(p_fecha_comercial date, p_confirmado_en timestamp with time zone,
      p_vinculado_en timestamp with time zone, p_sellado_en timestamp with time zone)
    returns table(periodo_comercial date, plazo_hasta timestamp with time zone, acreditado_en timestamp with time zone, estado text)
    language plpgsql stable set search_path to '' as $f$
    begin
      periodo_comercial := pg_catalog.date_trunc('month', p_fecha_comercial::timestamp)::date;
      plazo_hasta := private.conversion_plazo_hasta(periodo_comercial);
      acreditado_en := greatest(p_confirmado_en, p_vinculado_en);
      estado := 'fuera_de_plazo';
      return next;
    end $f$;
  $prep$, 'P0409', 'RECUPERAR 1 A: la venta no quedó como se esperaba; no se hizo ningún cambio');

-- ── V · Aplicaciones que deben pasar (en una subtransacción que se deshace) ────────────────────────────────────────────
-- V1: un lead con contrato_id «colgante» igual al borrado (imposible con el FK validado; se fuerza sin triggers): el
-- preflight lo admite y la migración lo vuelve a enlazar al recargado.
select pg_temp.caso_aplica('V1 lead con contrato_id colgante al borrado: se aplica y queda enlazado al recargado',
  format($prep$ set local session_replication_role = replica;
    update crm.leads set contrato_id = %L::uuid where id = 'f1000000-0000-4000-8000-000000000001';
    set local session_replication_role = origin; $prep$, pg_temp.sembrado('k1')),
  '{}'::jsonb,
  $chk$ do $x$ begin
    perform pg_temp.exigir((select l.contrato_id from crm.leads l where l.id = 'f1000000-0000-4000-8000-000000000001') = pg_temp.sembrado('r1')
      and (pg_temp.acr('f1000000-0000-4000-8000-000000000001')).fuente_id = pg_temp.sembrado('r1'),
      'V1: el lead colgante quedó enlazado al recargado y la venta acreditada a él');
  end $x$; $chk$);

-- V2: un lead que ENTRA durante la migración (después del corte) no cambia la comparación del postflight: el corte es FIJO.
select pg_temp.caso_aplica('V2 un lead que entra durante la migración no rompe el postflight (corte fijo)',
  null,
  jsonb_build_object('create table crm.conversion_ventas_recuperadas', $iny$
    reset role;
    set local session_replication_role = replica;
    insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, activo, monto_estimado, creado_en)
      values ('f1000000-0000-4000-8000-000000000009', 'LEAD QUE ENTRA DURANTE LA MIGRACION', '+51998000009', '43000009', 'landing',
        'nuevo', 'a0000000-0000-4000-8000-0000000000a4', true, 1000, pg_catalog.clock_timestamp());
    set local session_replication_role = origin;
    set local role postgres;
  $iny$),
  $chk$ do $x$ begin
    perform pg_temp.exigir(exists (select 1 from crm.leads l where l.id = 'f1000000-0000-4000-8000-000000000009')
      and (select count(*) from crm.conversion_ventas_recuperadas) = 5, 'V2: entró el lead y se recuperaron las cinco');
  end $x$; $chk$);

-- ── I · El postflight detecta lo que cambie «durante» la migración (inyección en el cuerpo; todo se deshace) ───────────
select pg_temp.caso_rechazo('I1 otra venta cambia entre el antes y el después: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: cambiaron',
  jsonb_build_object('create table crm.conversion_ventas_recuperadas', $iny$
    select pg_temp.como('a0000000-0000-4000-8000-0000000000a2'::uuid);
    select crm.anular_cierre_avance('d1000000-0000-4000-8000-000000000004'::uuid, 'Anulación ajena durante la migración');
    select pg_temp.como(null);
  $iny$));

select pg_temp.caso_rechazo('I2 una venta recuperada no cuenta al final: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: una venta recuperada no cuenta exactamente una vez en la conversión',
  jsonb_build_object('do $postflight$', $iny$
    select pg_temp.como('a0000000-0000-4000-8000-0000000000a2'::uuid);
    select crm.anular_cierre_avance('f1000000-0000-4000-8000-000000000001'::uuid, 'Anulación de prueba durante la migración');
    select pg_temp.como(null);
  $iny$));

select pg_temp.caso_rechazo('I3 private.cierre_anulado no queda como se ensayó: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: una función cambiada no quedó como se ensayó',
  jsonb_build_object('do $postflight$', 'alter function private.cierre_anulado(uuid) cost 101;'));

select pg_temp.caso_rechazo('I4 cambian los metadatos de private.cierre_anulado: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: cambiaron dueño, seguridad, volatilidad, configuración o permisos de una función',
  jsonb_build_object('do $postflight$', 'reset role; alter function private.cierre_anulado(uuid) owner to supabase_admin; set local role postgres;'));

select pg_temp.caso_rechazo('I5a la tabla nueva con un privilegio para la API: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: la tabla nueva tiene RLS, es de postgres, sin políticas y sin privilegios para la API',
  jsonb_build_object('do $postflight$', 'grant select on crm.conversion_ventas_recuperadas to authenticated;'));

select pg_temp.caso_rechazo('I5b la tabla nueva sin RLS: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: la tabla nueva tiene RLS, es de postgres, sin políticas y sin privilegios para la API',
  jsonb_build_object('do $postflight$', 'alter table crm.conversion_ventas_recuperadas disable row level security;'));

select pg_temp.caso_rechazo('I5c la función del trigger nuevo con EXECUTE para la API: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: las funciones de los triggers nuevos son de postgres, INVOKER y sin EXECUTE para la API',
  jsonb_build_object('do $postflight$', 'grant execute on function private.validar_venta_recuperada() to authenticated;'));

-- I6a: una sexta fila BIEN armada (el control F, que no está en los casos) entra por el trigger y el postflight la detecta.
select pg_temp.caso_rechazo('I6a una sexta venta recuperada (bien armada): el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: se esperaban 5 ventas recuperadas',
  jsonb_build_object('do $postflight$', $iny$
    insert into crm.conversion_ventas_recuperadas (lead_id, acreditacion_id, fuente_borrada_id, contrato_vigente_id,
      cierre_avance_anulado_id, inversion_eliminada_id, fecha_comercial_antes, fecha_comercial_despues, motivo, autorizado_por, respaldo)
    select 'f1000000-0000-4000-8000-000000000006', (pg_temp.acr('f1000000-0000-4000-8000-000000000006'::uuid)).id,
      pg_temp.sembrado('k6'), pg_temp.sembrado('r6'), a.id, ie.id, date '2026-10-08', date '2026-10-08',
      'Fila ajena de prueba (el control F)', 'Prueba del banco', '{}'::jsonb
    from crm.cierres_avance_anulados a, crm.inversiones_eliminadas ie
    where a.lead_id = 'f1000000-0000-4000-8000-000000000006'
      and ie.lead_id = 'f1000000-0000-4000-8000-000000000006' and ie.conversion_anulada;
  $iny$));

-- I6b: una sexta fila MAL armada (acreditación que no es de ese lead) ni siquiera entra: el trigger de validación (v2) la
-- rechaza antes del postflight.
select pg_temp.caso_rechazo('I6b una sexta fila mal armada: el trigger de validación la rechaza antes del postflight',
  null, '23514', 'Venta recuperada: la acreditación no es de ese lead',
  jsonb_build_object('do $postflight$', $iny$
    insert into crm.conversion_ventas_recuperadas (lead_id, acreditacion_id, fuente_borrada_id, contrato_vigente_id,
      fecha_comercial_antes, fecha_comercial_despues, motivo, autorizado_por, respaldo)
    values ('d1000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
      date '2026-10-05', date '2026-10-05', 'Fila ajena de prueba', 'Prueba del banco', '{}'::jsonb);
  $iny$));

select pg_temp.caso_rechazo('I7 una función cambiada nombra una pieza cerrada de F7: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: una función cambiada nombra una pieza cerrada de F7',
  jsonb_build_object('do $postflight$', $iny$
    insert into private.f7_piezas_en_observacion (firma, huella_md5, acl_esperada, llamadores_permitidos, patron_censo, ola, estado,
      cerrada_en, ok_miguel)
    values ('crm.pieza_de_prueba()', 'x', 'x', '{}', 'conversion_ventas_recuperadas', 'banco', 'cerrada_permanente',
      date '2026-10-01', 'Pieza ficticia del banco de pruebas, no es real');
  $iny$));

select pg_temp.caso_rechazo('I8a la función nueva entra al censo de vigencia del analista: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: una función cambiada entró al censo de vigencia del analista',
  jsonb_build_object('do $postflight$', $iny$
    create or replace function private.proteger_venta_recuperada() returns trigger language plpgsql set search_path = '' as $v$
    begin
      if public.es_analista() then null; end if;
      raise exception 'Una venta recuperada no se modifica ni se borra: queda como historia' using errcode = 'P0409';
    end $v$;
  $iny$));

select pg_temp.caso_rechazo('I8b la función nueva entra al censo analítico: el postflight lo detecta',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: una función cambiada entró al censo analítico',
  jsonb_build_object('do $postflight$', $iny$
    create or replace function private.proteger_venta_recuperada() returns trigger language plpgsql set search_path = '' as $v$
    begin
      perform count(*) from crm.leads;
      raise exception 'Una venta recuperada no se modifica ni se borra: queda como historia' using errcode = 'P0409';
    end $v$;
  $iny$));

-- I9: solo la SUMA de referidos (el aporte individual de los referidos tocados queda fuera de la comparación): si el tope cambia
-- «durante» la migración, el reparto de a4 ya no sube exactamente una cuota y el postflight lo detecta.
select pg_temp.caso_rechazo('I9 el tope de referidos cambia durante la migración: la suma de referidos no sube una cuota',
  null, 'P0001', 'POSTFLIGHT recuperar_ventas: la suma de referidos de un analista no subió exactamente una cuota por venta recuperada',
  jsonb_build_object('do $postflight$', $iny$
    reset role;
    set local session_replication_role = replica;
    update crm.conversion_pesos set tope_referidos_pct = 30 where vigente_desde = date '2026-10-01';
    set local session_replication_role = origin;
    set local role postgres;
  $iny$));

-- ── Fotos de ANTES de la aplicación base ───────────────────────────────────────────────────────────────────────────────
create temporary table acreditaciones_antes as
  select ca.* from crm.conversion_acreditaciones ca where ca.lead_id in (select c.lead_id from pg_temp.casos_sembrados c);
create temporary table contratos_antes as
  select ct.id, ct.fecha_cierre_comercial, ct.fuente_cierre_comercial from public.contratos ct
  where ct.id in (select c.recargado from pg_temp.casos_sembrados c);
create temporary table totales_antes as
  select pg_temp.cuenta_conversion('2026-10-01') as oct, pg_temp.cuenta_conversion('2026-09-01') as sep,
    pg_temp.cuenta_oficial('2026-10-01') as oct_oficial, pg_temp.cuenta_oficial('2026-09-01') as sep_oficial,
    pg_temp.foto_capital('2026-10-01') as cap_oct, pg_temp.foto_capital('2026-09-01') as cap_sep;
create temporary table episodios_antes as
  select x.tipo, x.analista_id, x.lead_id, x.operacion_id, x.anulado, x.categoria, x.mes_origen, x.aporte_divisor, x.aporte_numerador
  from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x;
create temporary table altas_antes as select pg_temp.altas_json() as j;
do $m0$
declare v_estado jsonb := pg_temp.estado_cierres(array['f1000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000004',
  'f1000000-0000-4000-8000-000000000006']::uuid[]);
begin
  -- ANTES: el chip «CIERRE ANULADO» sale para C, D y F (los tres anulados por «Eliminar inversión»).
  perform pg_temp.exigir((select count(*) from jsonb_array_elements(v_estado) e where e ->> 'anulado_en' is not null and e ->> 'canal' = 'avance') = 3,
    'M: ANTES el chip «CIERRE ANULADO» sale para C, D y F');
  perform pg_temp.exigir(pg_catalog.current_setting('transaction_isolation') = 'read committed',
    'M: la transacción es READ COMMITTED (la migración lo fija y su escritor lo exige)');
  perform pg_temp.exigir(exists (select 1 from pg_catalog.pg_locks l where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid()
    and l.granted and l.objsubid = 1 and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint),
    'M: la sesión tiene el candado de migraciones');
end $m0$;

-- La aplicación BASE va como `supabase db query --linked`: sin sesión de usuario (auth.uid() nulo). Sin esto, las claims de
-- Gerencia que dejan las pruebas anteriores harían que el trigger de atribución de crm.actividades rechace la nota.
select pg_temp.como(null);
-- @@ MIGRACION @@
reset search_path;

-- ── D · Después de la aplicación base ──────────────────────────────────────────────────────────────────────────────────
do $d1$
declare c record; v_acr crm.conversion_acreditaciones; v_antes crm.conversion_acreditaciones; v_ctr public.contratos; v_ctr_antes record;
begin
  for c in select * from pg_temp.casos_sembrados order by caso loop
    select * into v_acr from crm.conversion_acreditaciones ca where ca.lead_id = c.lead_id;
    select * into v_antes from pg_temp.acreditaciones_antes a where a.lead_id = c.lead_id;
    perform pg_temp.exigir(v_acr.id = c.acreditacion_id and v_acr.fuente_tipo = 'contrato' and v_acr.fuente_id = c.recargado
      and v_acr.estado = 'acreditada' and v_acr.periodo_comercial = c.periodo and v_acr.fecha_comercial = c.fecha_final,
      format('D1 %s: la acreditación pasó al recargado, acreditada en %s con fecha %s', c.caso, c.periodo, c.fecha_final));
    perform pg_temp.exigir(v_acr.episodio_id = v_antes.episodio_id and v_acr.analista_id = v_antes.analista_id
      and v_acr.analista_id = c.analista_id and v_acr.inversionista_id is not distinct from v_antes.inversionista_id
      and v_acr.origen = v_antes.origen, format('D1 %s: es la MISMA venta (episodio, analista, persona y origen)', c.caso));
    perform pg_temp.exigir((select l.contrato_id from crm.leads l where l.id = c.lead_id) = c.recargado,
      format('D1 %s: el lead quedó enlazado al recargado', c.caso));
    perform pg_temp.exigir(not private.cierre_anulado(c.lead_id), format('D1 %s: la venta no está anulada', c.caso));
    perform pg_temp.exigir((select count(*) from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
        where x.tipo = 'cierre' and x.lead_id = c.lead_id and not x.anulado and (x.aporte_numerador > 0 or x.fue_referido)
          and x.fecha_numerador >= c.periodo::timestamp at time zone 'America/Lima'
          and x.fecha_numerador < (c.periodo + interval '1 month')::timestamp at time zone 'America/Lima') = 1,
      format('D1 %s: cuenta en la conversión de %s (un cierre sin anular; con aporte, salvo referido)', c.caso, c.periodo));
    select * into v_ctr from public.contratos ct where ct.id = c.recargado;
    select * into v_ctr_antes from pg_temp.contratos_antes x where x.id = c.recargado;
    perform pg_temp.exigir(v_ctr.categoria = 'nuevo' and v_ctr.estado = 'activo' and v_ctr.fecha_cierre_comercial = c.fecha_final,
      format('D1 %s: el recargado sigue «nuevo» y activo, con fecha comercial %s', c.caso, c.fecha_final));
    if c.fecha_actual is distinct from c.fecha_final then
      perform pg_temp.exigir(v_ctr.fuente_cierre_comercial = 'correccion_manual',
        format('D1 %s: la fecha comercial se corrigió con fuente correccion_manual', c.caso));
      perform pg_temp.exigir((select i.fecha_comercial from crm.inversiones i where i.contrato_id = c.recargado) = c.fecha_final,
        format('D1 %s: la inversión acompaña a su contrato (fecha %s)', c.caso, c.fecha_final));
    else
      perform pg_temp.exigir(v_ctr.fecha_cierre_comercial = v_ctr_antes.fecha_cierre_comercial
        and v_ctr.fuente_cierre_comercial = v_ctr_antes.fuente_cierre_comercial, format('D1 %s: la fecha comercial no se tocó', c.caso));
    end if;
  end loop;
  -- El capital de B se revalorizó con su fecha nueva (01/10, dentro de la política vigente desde el 01/10).
  perform pg_temp.exigir((select v.fecha_comercial from crm.capital_valoraciones v where v.fuente = 'contrato' and v.fuente_id = pg_temp.sembrado('r2')
      order by v.revision desc limit 1) = date '2026-10-01', 'D1 2 B: la valoración del capital tomó la fecha corregida');
  -- E vuelve al 30/09, ANTES de la política de valoración (vigente desde el 01/10): el materializador no la revalúa (su única
  -- revisión sigue siendo la histórica del alta, en PEN con tasa 1) y el capital del mes se mueve igual (lo mide D4).
  perform pg_temp.exigir((select count(*) from crm.capital_valoraciones v where v.fuente = 'contrato' and v.fuente_id = pg_temp.sembrado('r5')) = 1
      and (select v.motivo = 'historica' and v.moneda = 'PEN' and v.equivalente_pen = 353000 from crm.capital_valoraciones v
           where v.fuente = 'contrato' and v.fuente_id = pg_temp.sembrado('r5')),
    'D1 5 E: al volver a septiembre (antes de la política de valoración) conserva su única valoración histórica en PEN; el capital se mueve igual (D4)');
  -- REFERIDOS: el tope reparte 2 × 15 % = 0,30 entre G (03/10) y A (05/10) en orden de fecha: G 0,30 y A 0. La SUMA de a4 sube
  -- 0,15; la de a7 (solo B) sube 0,15. Es la regla vigente de la métrica, no un efecto de la migración.
  perform pg_temp.exigir((select x.aporte_numerador from private.conversion_episodios(timestamptz '2026-10-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
        where x.tipo = 'cierre' and x.lead_id = 'f1000000-0000-4000-8000-000000000007') = 0.30
      and (select x.aporte_numerador from private.conversion_episodios(timestamptz '2026-10-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
        where x.tipo = 'cierre' and x.lead_id = 'f1000000-0000-4000-8000-000000000001') = 0
      and (select x.aporte_numerador from private.conversion_episodios(timestamptz '2026-10-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
        where x.tipo = 'cierre' and x.lead_id = 'f1000000-0000-4000-8000-000000000002') = 0.15,
    'D1 referidos: el tope reparte 0,30 entre G (0,30) y A (0) y B suma 0,15: las SUMAS de a4 y a7 suben una cuota cada una');
  raise notice 'PASS D1 por caso: misma venta al recargado, en su mes, enlazada, sin anular, contando (referidos por la suma); B y E con fecha corregida';
end $d1$;

do $d2$
declare c record; v crm.conversion_ventas_recuperadas;
begin
  perform pg_temp.exigir((select count(*) from crm.conversion_ventas_recuperadas) = 5, 'D2: cinco ventas recuperadas');
  for c in select * from pg_temp.casos_sembrados order by caso loop
    select * into v from crm.conversion_ventas_recuperadas r where r.lead_id = c.lead_id;
    perform pg_temp.exigir(v.acreditacion_id = c.acreditacion_id and v.fuente_borrada_id = c.fuente_borrada
      and v.contrato_vigente_id = c.recargado and v.cierre_avance_anulado_id is not distinct from c.anulacion_id
      and v.inversion_eliminada_id is not distinct from c.copia_anulada_id
      and v.fecha_comercial_antes = c.fecha_actual and v.fecha_comercial_despues = c.fecha_final
      and v.respaldo ->> 'caso' = c.caso and v.respaldo #>> '{acreditacion_antes,fuente_id}' = c.fuente_borrada::text
      and v.respaldo #>> '{lead_antes,etapa}' = 'convertido' and v.respaldo #>> '{contrato_antes,categoria}' = 'nuevo'
      and v.transaccion = pg_catalog.pg_current_xact_id(), format('D2 %s: la fila guarda la venta, la rehabilitación y el respaldo', c.caso));
  end loop;
  perform pg_temp.rechaza('update crm.conversion_ventas_recuperadas set motivo = motivo', 'P0409', 'Una venta recuperada no se modifica ni se borra');
  perform pg_temp.rechaza('delete from crm.conversion_ventas_recuperadas', 'P0409', 'Una venta recuperada no se modifica ni se borra');
  perform pg_temp.rechaza('truncate crm.conversion_ventas_recuperadas', 'P0409', 'Una venta recuperada no se modifica ni se borra');
  perform pg_temp.exigir((select pc.relrowsecurity from pg_catalog.pg_class pc where pc.oid = 'crm.conversion_ventas_recuperadas'::regclass)
    and not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) r(rol)
      where pg_catalog.has_table_privilege(r.rol, 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger'))
    and not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) r(rol)
      where pg_catalog.has_function_privilege(r.rol, 'private.proteger_venta_recuperada()', 'execute')),
    'D2: la tabla tiene RLS y la API no la toca (ni a su trigger)');
  perform pg_temp.exigir((select count(*) from public.audit_log a where a.tabla = 'crm.conversion_ventas_recuperadas' and a.operacion = 'INSERT') = 5,
    'D2: las cinco filas quedaron en la bitácora (audit_log)');
  perform pg_temp.exigir(pg_catalog.obj_description('crm.conversion_ventas_recuperadas'::regclass, 'pg_class') is not null
    and not exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = 'crm.conversion_ventas_recuperadas'::regclass and a.attnum > 0
      and not a.attisdropped and pg_catalog.col_description(a.attrelid, a.attnum) is null)
    and pg_catalog.obj_description('private.proteger_venta_recuperada()'::regprocedure, 'pg_proc') is not null
    and pg_catalog.obj_description('private.cierre_anulado(uuid)'::regprocedure, 'pg_proc') like '%20261018032400%',
    'D2: COMMENT ON completo (tabla, columnas y funciones)');
  perform pg_temp.exigir(md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) = '878d19fffc19bc39649a5105bd51b082',
    'D2: private.cierre_anulado quedó con la huella ensayada');
  -- La anulación queda como HISTORIA: la fila de anulación y la copia siguen ahí.
  perform pg_temp.exigir((select count(*) from pg_temp.casos_sembrados cs
      join crm.cierres_avance_anulados a on a.id = cs.anulacion_id and a.lead_id = cs.lead_id
      join crm.inversiones_eliminadas ie on ie.id = cs.copia_anulada_id and ie.conversion_anulada) = 2,
    'D2: las anulaciones de C y D y sus copias siguen como historia');
  raise notice 'PASS D2 tabla nueva: 5 filas con respaldo, solo inserción (UPDATE, DELETE, TRUNCATE), RLS sin API, auditada, comentada, huella';
end $d2$;

do $d3$
begin
  perform pg_temp.exigir(private.cierre_anulado('f1000000-0000-4000-8000-000000000006')
    and exists (select 1 from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
                where x.tipo = 'cierre' and x.lead_id = 'f1000000-0000-4000-8000-000000000006' and x.anulado and x.aporte_numerador = 0),
    'D3 F: una venta anulada que NO está en los casos sigue anulada');
  -- Una anulación NUEVA de otro lead (d3 de la siembra) cuenta: la rehabilitación es por fila, no general.
  begin
    perform pg_temp.api('a0000000-0000-4000-8000-0000000000a2',
      format('select crm.anular_cierre_avance(%L::uuid, %L)', 'd1000000-0000-4000-8000-000000000003', 'Venta anulada después de la recuperación'));
    perform pg_temp.exigir(private.cierre_anulado('d1000000-0000-4000-8000-000000000003') and pg_temp.cuenta_conversion('2026-10-01') = 8,
      'D3: una anulación de Avance posterior, de otro lead, sigue contando (octubre 9 → 8 bruto)');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  -- Otra copia anulada del lead C (otra fila de «Eliminar inversión»): esa fila no está rehabilitada y cuenta.
  begin
    set local session_replication_role = replica;
    insert into crm.inversiones_eliminadas select (jsonb_populate_record(null::crm.inversiones_eliminadas, to_jsonb(ie)
      || jsonb_build_object('id', gen_random_uuid(), 'valvula', gen_random_uuid(), 'fuente_id', gen_random_uuid()))).*
    from crm.inversiones_eliminadas ie where ie.id = (select c.copia_anulada_id from pg_temp.casos_sembrados c where c.caso = '3 C');
    set local session_replication_role = origin;
    perform pg_temp.exigir(private.cierre_anulado('f1000000-0000-4000-8000-000000000003'),
      'D3 3 C: otra copia anulada (no rehabilitada) del mismo lead vuelve a anular la venta');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS D3 otras anulaciones siguen contando: el control F, una anulación nueva de otro lead y otra copia del mismo lead';
end $d3$;

do $d4$
declare v_antes record; v_oct jsonb := pg_temp.foto_capital('2026-10-01'); v_sep jsonb := pg_temp.foto_capital('2026-09-01'); v_dist bigint; v_quien text;
begin
  select * into v_antes from pg_temp.totales_antes;
  perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = v_antes.oct + 4 and pg_temp.cuenta_conversion('2026-09-01') = v_antes.sep + 1,
    format('D4 bruto: octubre %s → %s (+4: A, B, C, D) y septiembre %s → %s (+1: E)', v_antes.oct, pg_temp.cuenta_conversion('2026-10-01'),
      v_antes.sep, pg_temp.cuenta_conversion('2026-09-01')));
  perform pg_temp.exigir(pg_temp.cuenta_oficial('2026-10-01') = v_antes.oct_oficial + 2.30 and pg_temp.cuenta_oficial('2026-09-01') = v_antes.sep_oficial + 1,
    format('D4 oficial (con el tope): octubre %s → %s (+2,30: A 0,15 por la suma de a4, B 0,15, C 1, D 1) y septiembre %s → %s (+1: E)',
      v_antes.oct_oficial, pg_temp.cuenta_oficial('2026-10-01'), v_antes.sep_oficial, pg_temp.cuenta_oficial('2026-09-01')));
  perform pg_temp.exigir(coalesce((v_oct ->> 'PEN')::numeric, 0) = coalesce((v_antes.cap_oct ->> 'PEN')::numeric, 0) + 10000 - 353000
    and coalesce((v_sep ->> 'PEN')::numeric, 0) = coalesce((v_antes.cap_sep ->> 'PEN')::numeric, 0) - 10000 + 353000,
    format('D4: el capital de B (10 000) pasa de septiembre a octubre y el de E (353 000) de octubre a septiembre (oct %s → %s, sep %s → %s)',
      v_antes.cap_oct, v_oct, v_antes.cap_sep, v_sep));
  -- Independiente del postflight y SIN enmascarar nada: fuera de los cinco, lo ÚNICO que cambió es el aporte individual de G
  -- (0,15 → 0,30), porque el tope reparte 2 × 15 % entre G y A en orden de fecha. Ningún otro episodio se movió.
  with despues as (
    select x.tipo, x.analista_id, x.lead_id, x.operacion_id, x.anulado, x.categoria, x.mes_origen, x.aporte_divisor, x.aporte_numerador
    from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
  ), a as (select * from pg_temp.episodios_antes e where e.lead_id is null or e.lead_id not in (select c.lead_id from pg_temp.casos_sembrados c)),
  d as (select * from despues e where e.lead_id is null or e.lead_id not in (select c.lead_id from pg_temp.casos_sembrados c)),
  z as ((select 'antes' as foto, * from a except all select 'antes', * from d) union all (select 'despues', * from d except all select 'despues', * from a))
  select count(*), coalesce(string_agg(z.foto || ':' || z.lead_id::text || '=' || z.aporte_numerador::numeric(8,2)::text, ' ' order by z.foto), '') into v_dist, v_quien from z;
  perform pg_temp.exigir(v_dist = 2 and v_quien = 'antes:f1000000-0000-4000-8000-000000000007=0.15 despues:f1000000-0000-4000-8000-000000000007=0.30',
    format('D4: fuera de los cinco solo cambió el aporte de G por el tope, 0,15 → 0,30 (%s episodios distintos: %s)', v_dist, v_quien));
  raise notice 'PASS D4 totales: conversión octubre +4 bruto / +2,30 oficial y septiembre +1; capital de B y E mudado de mes; fuera de los cinco solo G por el tope';
end $d4$;

-- D6 · Las otras tres funciones parchadas (v2, hallazgo P1 del auditor-rls): el chip «CIERRE ANULADO», el informe «Altas
-- nuevas» y «Anular el cierre» / «Eliminar inversión» tratan la anulación rehabilitada como lo que es; el control F, no.
do $d6$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  a4 constant uuid := 'a0000000-0000-4000-8000-0000000000a4';
  a7 constant uuid := 'a0000000-0000-4000-8000-0000000000a7';
  v_estado jsonb := pg_temp.estado_cierres(array['f1000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000004',
    'f1000000-0000-4000-8000-000000000006']::uuid[]);
  v_antes jsonb := (select j from pg_temp.altas_antes);
  v_ahora jsonb := pg_temp.altas_json();
begin
  -- (a) crm.cierres_estado_fn: C y D ya no salen anulados (no viajan: son convertidos sanos); F sigue con su chip y su motivo.
  perform pg_temp.exigir(not exists (select 1 from jsonb_array_elements(v_estado) e
      where (e ->> 'lead_id')::uuid in ('f1000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000004')),
    'D6a: el chip «CIERRE ANULADO» ya no sale para C ni para D (rehabilitadas)');
  perform pg_temp.exigir((select e ->> 'anulado_en' is not null and e ->> 'motivo' is not null and e ->> 'canal' = 'avance'
      from jsonb_array_elements(v_estado) e where (e ->> 'lead_id')::uuid = 'f1000000-0000-4000-8000-000000000006'),
    'D6a: el chip «CIERRE ANULADO» sigue saliendo para el control F, con su motivo');
  -- (b) crm.altas_nuevas_por_analista_fn: los recargados de C (a4, oct) y D (a7, oct) entran; B (a7) pasa de sep a oct y
  --     E (a4) de oct a sep. Deltas: oct a4 = +1 (C) -1 (E) = 0; oct a7 = +1 (D) +1 (B) = +2; sep a4 = +1 (E); sep a7 = -1 (B).
  perform pg_temp.exigir(pg_temp.altas_de(v_ahora, date '2026-10-01', a7) = pg_temp.altas_de(v_antes, date '2026-10-01', a7) + 2
      and pg_temp.altas_de(v_ahora, date '2026-10-01', a4) = pg_temp.altas_de(v_antes, date '2026-10-01', a4)
      and pg_temp.altas_de(v_ahora, date '2026-09-01', a4) = pg_temp.altas_de(v_antes, date '2026-09-01', a4) + 1
      and pg_temp.altas_de(v_ahora, date '2026-09-01', a7) = pg_temp.altas_de(v_antes, date '2026-09-01', a7) - 1,
    format('D6b: «Altas nuevas» cuenta los recargados de C y D y mueve B y E de mes (antes %s, ahora %s)', v_antes, v_ahora));
  -- (c) «Anular el cierre» y «Eliminar inversión» sobre una venta rehabilitada: mensaje nuevo; sobre F: el de siempre.
  perform pg_temp.rechaza(format('select pg_temp.api(%L::uuid, %L)', a2,
      format('select crm.anular_cierre_avance(%L::uuid, %L)', 'f1000000-0000-4000-8000-000000000003', 'Prueba: volver a anular')),
    'P0409', 'Esta venta se anuló y después se recuperó: no se vuelve a anular');
  perform pg_temp.rechaza(format('select pg_temp.eliminar_inversion(%L::uuid)', pg_temp.sembrado('r4')),
    'P0409', 'Esta venta se anuló y después se recuperó: no se vuelve a anular');
  perform pg_temp.rechaza(format('select pg_temp.api(%L::uuid, %L)', a2,
      format('select crm.anular_cierre_avance(%L::uuid, %L)', 'f1000000-0000-4000-8000-000000000006', 'Prueba: volver a anular')),
    'P0409', 'Ese cierre ya estaba anulado');
  perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 9 and (select count(*) from crm.conversion_ventas_recuperadas) = 5
      and exists (select 1 from public.contratos c where c.id = pg_temp.sembrado('r4') and c.estado = 'activo'),
    'D6c: los rechazos no cambiaron nada (octubre 9 bruto, cinco filas, el recargado de D sigue activo)');
  raise notice 'PASS D6 funciones parchadas: chip sin C ni D (F sigue), «Altas nuevas» con C y D (B y E de mes), no se vuelve a anular';
end $d6$;

-- D7 · El trigger de validación de la tabla nueva: la acreditación, la anulación y la copia tienen que ser DE ESE lead y
-- de ese contrato (23514); una fila bien armada para F entra y des-anula a F (la rehabilitación es por fila).
do $d7$
declare
  f constant uuid := 'f1000000-0000-4000-8000-000000000006';
  d1 constant uuid := 'd1000000-0000-4000-8000-000000000001';
  v_anul uuid := (select a.id from crm.cierres_avance_anulados a where a.lead_id = 'f1000000-0000-4000-8000-000000000006');
  v_copia uuid := (select ie.id from crm.inversiones_eliminadas ie where ie.lead_id = 'f1000000-0000-4000-8000-000000000006' and ie.conversion_anulada);
  v_ins constant text := 'insert into crm.conversion_ventas_recuperadas (lead_id, acreditacion_id, fuente_borrada_id, contrato_vigente_id, '
    'cierre_avance_anulado_id, inversion_eliminada_id, fecha_comercial_antes, fecha_comercial_despues, motivo, autorizado_por, respaldo) '
    'values (%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, date ''2026-10-08'', date ''2026-10-08'', ''Fila de prueba del banco'', ''Prueba del banco'', ''{}''::jsonb)';
begin
  perform pg_temp.exigir(v_anul is not null and v_copia is not null and private.cierre_anulado(f), 'D7: F sigue anulado, con anulación y copia');
  perform pg_temp.rechaza(format(v_ins, d1, (pg_temp.acr(d1)).id, pg_temp.sembrado('k6'), pg_temp.sembrado('r6'), v_anul, v_copia),
    '23514', 'Venta recuperada: la anulación no es de ese lead');
  perform pg_temp.rechaza(format(v_ins, f, (pg_temp.acr(d1)).id, pg_temp.sembrado('k6'), pg_temp.sembrado('r6'), v_anul, v_copia),
    '23514', 'Venta recuperada: la acreditación no es de ese lead');
  perform pg_temp.rechaza(format(v_ins, f, (pg_temp.acr(f)).id, pg_temp.sembrado('k1'), pg_temp.sembrado('r6'), v_anul, v_copia),
    '23514', 'Venta recuperada: la copia anulada no es de ese lead y ese contrato');
  perform pg_temp.exigir(private.cierre_anulado(f) and (select count(*) from crm.conversion_ventas_recuperadas) = 5,
    'D7: ninguna fila mal armada entró y F sigue anulado');
  begin
    execute format(v_ins, f, (pg_temp.acr(f)).id, pg_temp.sembrado('k6'), pg_temp.sembrado('r6'), v_anul, v_copia);
    perform pg_temp.exigir(not private.cierre_anulado(f) and pg_temp.cierres_validos(f) = 1 and pg_temp.cuenta_conversion('2026-10-01') = 10,
      'D7: una fila bien armada para F entra, lo des-anula y su venta cuenta (octubre 9 → 10 bruto)');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  perform pg_temp.exigir(private.cierre_anulado(f) and pg_temp.cuenta_conversion('2026-10-01') = 9, 'D7: deshecho, F vuelve a estar anulado');
  raise notice 'PASS D7 trigger de validación: anulación, acreditación y copia ajenas se rechazan (23514); una fila correcta rehabilita';
end $d7$;

-- D8 · La nota en la línea de tiempo de cada lead recuperado.
do $d8$
begin
  perform pg_temp.exigir((select count(*) from pg_temp.casos_sembrados c
      join crm.actividades a on a.lead_id = c.lead_id and a.tipo = 'nota' and a.creado_por is null
        and a.metadata ->> 'accion' = 'recuperacion_venta' and a.metadata ->> 'migracion' = '20261018032400'
        and (a.metadata ->> 'contrato_id')::uuid = c.recargado and (a.metadata ->> 'contrato_borrado_id')::uuid = c.fuente_borrada
        and (a.metadata ->> 'rehabilita_anulacion')::boolean = (c.anulacion_id is not null)
        and a.detalle = case when c.anulacion_id is not null then 'Se recuperó la venta anulada al borrar el contrato'
                             else 'Se recuperó la venta perdida al borrar el contrato' end) = 5
    and (select count(*) from crm.actividades a where a.metadata ->> 'accion' = 'recuperacion_venta') = 5,
    'D8: cada lead recuperado tiene UNA nota con el contrato vivo, el borrado y si rehabilita una anulación');
  raise notice 'PASS D8 notas: una por lead recuperado, con su metadata';
end $d8$;

-- D9 · La REVERSA (reversa.sql, su segunda transacción, como postgres y sin sesión): las cuatro funciones vuelven a su huella
-- anterior; C y D vuelven a contar como anuladas (chip incluido); A, B y E siguen contando; las filas y las notas quedan.
do $d9$
declare
  v_estado jsonb;
begin
  begin
    perform pg_temp.como(null);
    set local role postgres;
    execute (select m.sql from pg_temp.migracion_sql m where m.parte = 'reversa');
    reset role;
    reset search_path;
    perform pg_temp.exigir((select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
        from pg_catalog.pg_proc p where p.oid in ('private.cierre_anulado(uuid)'::regprocedure, 'crm.cierres_estado_fn(uuid[])'::regprocedure,
          'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, 'crm.anular_cierre_avance(uuid,text)'::regprocedure))
      = 'crm.altas_nuevas_por_analista_fn(integer)=b421dfb1f3a317776d9e4e1b9e69dd76,crm.anular_cierre_avance(uuid,text)=03b673084dbbbbff7aef21c12e7f30b5,'
        'crm.cierres_estado_fn(uuid[])=f543c8090d2266f26cfbcd6649b783f4,private.cierre_anulado(uuid)=df71c2b1e3cd44b97c3ad84e00637266',
      'D9: las cuatro funciones volvieron a su huella anterior');
    perform pg_temp.exigir(private.cierre_anulado('f1000000-0000-4000-8000-000000000003') and private.cierre_anulado('f1000000-0000-4000-8000-000000000004')
        and not private.cierre_anulado('f1000000-0000-4000-8000-000000000001') and not private.cierre_anulado('f1000000-0000-4000-8000-000000000002')
        and not private.cierre_anulado('f1000000-0000-4000-8000-000000000005'),
      'D9: C y D vuelven a estar anuladas; A, B y E no');
    perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 7 and pg_temp.cuenta_conversion('2026-09-01') = 2
        and pg_temp.cuenta_oficial('2026-10-01') = 4.45,
      format('D9: octubre 9 → %s bruto / 6,45 → %s oficial (sin C ni D) y septiembre sigue en %s', pg_temp.cuenta_conversion('2026-10-01'),
        pg_temp.cuenta_oficial('2026-10-01'), pg_temp.cuenta_conversion('2026-09-01')));
    v_estado := pg_temp.estado_cierres(array['f1000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000004']::uuid[]);
    perform pg_temp.exigir((select count(*) from jsonb_array_elements(v_estado) e where e ->> 'anulado_en' is not null) = 2,
      'D9: el chip «CIERRE ANULADO» vuelve a salir para C y D');
    perform pg_temp.exigir((select count(*) from crm.conversion_ventas_recuperadas) = 5
        and (select count(*) from crm.actividades a where a.metadata ->> 'accion' = 'recuperacion_venta') = 5
        and pg_catalog.obj_description('crm.conversion_ventas_recuperadas'::regclass, 'pg_class') like '%REVERTIDA%',
      'D9: las filas y las notas quedan como historia; el comentario de la tabla dice REVERTIDA');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  perform pg_temp.exigir(not private.cierre_anulado('f1000000-0000-4000-8000-000000000003') and pg_temp.cuenta_conversion('2026-10-01') = 9,
    'D9: deshecha la reversa, C vuelve a contar (octubre 9 bruto)');
  raise notice 'PASS D9 reversa: cuatro huellas anteriores, C y D anuladas de nuevo (chip incluido), A, B y E siguen, filas y notas quedan';
end $d9$;

-- Una segunda aplicación (en otra transacción no existirían las tablas temporales de la primera) se rechaza: la primera
-- defensa que salta es la huella de private.cierre_anulado, que ya no es la del preflight.
drop table pg_temp.recuperar_casos, pg_temp.recuperar_corte, pg_temp.recuperar_episodios_antes, pg_temp.recuperar_funciones;
select pg_temp.caso_rechazo('D5 la migración no se aplica dos veces',
  null, 'P0001', 'PREFLIGHT recuperar_ventas: cambió una función que la corrección cambia o llama');

do $fin$
begin
  perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 9 and pg_temp.cuenta_conversion('2026-09-01') = 2
    and pg_temp.cuenta_oficial('2026-10-01') = 6.45 and pg_temp.cuenta_oficial('2026-09-01') = 2
    and (select count(*) from crm.conversion_ventas_recuperadas) = 5, 'fin: octubre 9 bruto / 6,45 oficial, septiembre 2 y cinco ventas recuperadas');
  raise notice 'PASS recuperar_ventas: 58 bloques (S, P1-P17 con variantes: 34, V1-V2, I1-I9 con variantes: 13, D1-D9); se revierte';
end $fin$;
