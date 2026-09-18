-- ============================================================================
-- Oráculo de PRODELCO EN DÓLARES (migración 20260917235656).
-- ============================================================================
-- Cómo se corre (sobre una copia local a paridad con producción, DESPUÉS de
-- aplicar la migración):
--
--   psql "$URL" -v ON_ERROR_STOP=1 -f supabase/scripts/prodelco-usd/test-prodelco-usd.sql
--
-- Éxito = una sola fila con el token PRODELCO_USD_OK. Cualquier aserción
-- fallida lanza `raise exception` con su código PUSD-xx, lo ESPERADO y lo
-- OBTENIDO. Todo revierte: el fichero termina en `rollback`.
--
-- QUÉ PRUEBA, y por qué cada caso está aquí:
--   PUSD-01  Prodelco ACEPTA un cierre en USD y la fila queda en USD (no en
--            soles «por debajo»): es la petición de Miguel del 17/09/2026.
--   PUSD-02  Qorilazo SIGUE rechazando USD. La apertura es de UNA cooperativa;
--            si se hubiera abierto a las dos, este caso lo delata.
--   PUSD-03  Ninguna de las dos acepta una moneda fuera del dominio (EUR) ni
--            una moneda nula. Ensanchar no es abrir del todo.
--   PUSD-04  EL CATÁLOGO MANDA: con la fila de Prodelco devuelta a {PEN} —sin
--            desplegar una línea de código— el cierre en USD vuelve a
--            rechazarse. Es la prueba de que la reversa barata existe.
--   PUSD-05  FAIL-CLOSED: si la cooperativa no tiene fila en el catálogo, el
--            cierre se RECHAZA. Sin la guarda explícita del null, `= any(null)`
--            daría NULL y el candado se abriría solo.
--   PUSD-06  La corrección de gerencia respeta el mismo catálogo: puede llevar
--            un cierre de Prodelco a USD, y no puede hacerlo en Qorilazo.
--   PUSD-07  PEN sigue funcionando en las dos (no hay regresión).
--   PUSD-08  EL DINERO NO SE MEZCLA: tras el cierre en USD, la lectura y el
--            núcleo de capital reportan los dólares en SU moneda, y el total
--            en soles no se mueve ni un céntimo.
--   PUSD-09  La validación de la solicitud F4 (inversión adicional) usa el
--            mismo catálogo: Prodelco/USD pasa, Qorilazo/USD no.
--   PUSD-10  La RUTA F4 COMPLETA (preparar → confirmar) deja la fila en USD.
--            Es el caso decisivo del insert: antes de esta migración esa
--            sentencia escribía 'PEN' a mano, así que una inversión adicional
--            en dólares habría quedado registrada como soles.
--   PUSD-11  LA MONEDA ES INMUTABLE al corregir una solicitud F4. Un bundle
--            anterior manda `moneda:'PEN'` fijo: al corregir cualquier otro
--            campo de una solicitud en dólares la habría reescrito como soles,
--            con el mismo importe y sin avisar. Corregir OTRO campo
--            conservando la moneda sigue funcionando.
--   PUSD-12  Si la cooperativa RETIRA la moneda entre preparar y confirmar, la
--            confirmación se niega y no deja nada escrito.
--   PUSD-13  Gerencia NO cambia la moneda de un cierre imputado a un mes
--            SELLADO (movería capital entre columnas de una foto ya tomada);
--            corregir otros campos de ese mismo cierre sigue permitido.
-- ============================================================================
begin;
set local statement_timeout = '120s';

create function pg_temp.pusd_casos_esperados() returns text[]
language sql immutable as
$$ select array['PUSD-01','PUSD-02','PUSD-03','PUSD-04','PUSD-05','PUSD-06','PUSD-07','PUSD-08','PUSD-09','PUSD-10','PUSD-11','PUSD-12','PUSD-13'] $$;

create temporary table pusd_vistos (codigo text primary key) on commit drop;
create function pg_temp.pusd_caso(p_codigo text) returns void
language sql volatile as
$$ insert into pusd_vistos (codigo) values (p_codigo) on conflict do nothing $$;

create function pg_temp.pusd_como(p_perfil uuid) returns void
language sql volatile as
$$ select pg_catalog.set_config('request.jwt.claim.sub', p_perfil::text, true) $$;

/** Ejecuta y EXIGE que sea aceptado; devuelve lo que respondió, como texto.
 *  Texto y no jsonb a propósito: aquí se llaman funciones que devuelven jsonb
 *  (los escritores) y otras que devuelven uuid (el validador F4). */
create function pg_temp.pusd_ok(p_codigo text, p_campo text, p_sql text)
returns text language plpgsql volatile as
$$
declare v_out text;
begin
  perform pg_temp.pusd_caso(p_codigo);
  begin
    execute p_sql into v_out;
  exception when others then
    -- El SQL va en el mensaje: sin él, un fallo de la propia siembra parece un
    -- fallo de la regla que se está midiendo.
    raise exception '% · %: ESPERADO aceptado · OBTENIDO rechazo % (%) · SQL: %',
      p_codigo, p_campo, sqlstate, sqlerrm, p_sql;
  end;
  return v_out;
end;
$$;

/** Ejecuta y EXIGE rechazo con sqlstate (y opcionalmente mensaje) concretos. */
create function pg_temp.pusd_falla(p_codigo text, p_campo text, p_sql text,
                                   p_sqlstate text, p_msg_like text default null)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.pusd_caso(p_codigo);
  begin
    execute p_sql;
    raise exception 'PUSD_ACEPTADO';
  exception
    when others then
      if sqlerrm = 'PUSD_ACEPTADO' then
        raise exception '% · %: ESPERADO rechazo (sqlstate %) · OBTENIDO ACEPTADO',
          p_codigo, p_campo, p_sqlstate;
      end if;
      if sqlstate is distinct from p_sqlstate then
        raise exception '% · %: ESPERADO sqlstate % · OBTENIDO % (mensaje: %)',
          p_codigo, p_campo, p_sqlstate, sqlstate, sqlerrm;
      end if;
      if p_msg_like is not null and sqlerrm not like p_msg_like then
        raise exception '% · %: ESPERADO mensaje como %L · OBTENIDO %',
          p_codigo, p_campo, p_msg_like, sqlerrm;
      end if;
  end;
end;
$$;

create function pg_temp.pusd_igual(p_codigo text, p_campo text, p_esperado anyelement, p_obtenido anyelement)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.pusd_caso(p_codigo);
  if p_esperado is distinct from p_obtenido then
    raise exception '% · %: ESPERADO % · OBTENIDO %', p_codigo, p_campo, p_esperado, p_obtenido;
  end if;
end;
$$;

-- ── El mundo de la prueba: leads libres de ESTA copia, con su analista ───────
-- No se inventa un mundo nuevo: se toman leads reales, cada uno con el
-- vendedor que ya tiene, y se actúa CON ESA identidad (como en producción).
-- El analista tiene que estar VIGENTE: un lead cuyo analista fue dado de baja
-- se rechaza con 42501 por una regla anterior a esta migración, y meterlo aquí
-- mediría esa otra regla en vez de la moneda.
create temporary table pusd_leads on commit drop as
select row_number() over (order by l.id) as n, l.id, l.vendedor_id, l.nombre_completo
from crm.leads l
where l.activo and l.etapa not in ('convertido','descartado')
  and l.vendedor_id is not null
  and private.rol_crm(l.vendedor_id) is not null
  and exists (select 1 from crm.equipo e where e.perfil_id = l.vendedor_id and e.activo)
order by l.id
limit 8;

do $seguro$
begin
  if (select count(*) from pusd_leads) < 7 then
    raise exception 'PUSD-00: la copia necesita 7 leads libres con analista vigente; tiene %',
      (select count(*) from pusd_leads);
  end if;
  -- El punto de partida es el de producción DESPUÉS de la migración.
  if (select jsonb_object_agg(clave, monedas order by clave) from crm.empresas)
     is distinct from '{"avance":["PEN","USD"],"prodelco":["PEN","USD"],"qorilazo":["PEN"]}'::jsonb then
    raise exception 'PUSD-00: el catálogo no es el de después de la migración (¿la aplicaste?)';
  end if;
end;
$seguro$;

create function pg_temp.pusd_lead(p_n integer) returns uuid
language sql stable as $$ select id from pusd_leads where n = p_n $$;
create function pg_temp.pusd_vendedor(p_n integer) returns uuid
language sql stable as $$ select vendedor_id from pusd_leads where n = p_n $$;

/** Llamada completa a convertir_lead_externo, con la identidad del analista. */
create function pg_temp.pusd_cerrar(p_n integer, p_coop text, p_monto numeric,
                                    p_moneda text, p_dep text) returns text
language sql stable as
$$
  select pg_catalog.format(
    'select pg_temp.pusd_como(%L::uuid), crm.convertir_lead_externo(%L::uuid, %s, %s, %s, %L, %L, %L, %L)',
    pg_temp.pusd_vendedor(p_n), pg_temp.pusd_lead(p_n),
    case when p_coop is null then 'null' else pg_catalog.quote_literal(p_coop) end,
    p_monto::text,
    case when p_moneda is null then 'null' else pg_catalog.quote_literal(p_moneda) end,
    'DNI', pg_catalog.lpad((40000000 + p_n)::text, 8, '0'),
    'ORACULO PUSD ' || p_n, p_dep)
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-01 · Prodelco ACEPTA dólares, y la fila queda en dólares
-- ════════════════════════════════════════════════════════════════════════════
select pg_temp.pusd_ok('PUSD-01', 'cierre Prodelco en USD',
  pg_temp.pusd_cerrar(1, 'prodelco', 5000.00, 'USD', 'PUSD-USD-001'));

select pg_temp.pusd_igual('PUSD-01', 'moneda guardada', 'USD',
  (select moneda from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'));
select pg_temp.pusd_igual('PUSD-01', 'monto guardado', 5000.00,
  (select monto from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'));
select pg_temp.pusd_igual('PUSD-01', 'cooperativa guardada', 'prodelco',
  (select cooperativa from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'));
-- El lead quedó convertido igual que en un cierre en soles.
select pg_temp.pusd_igual('PUSD-01', 'etapa del lead', 'convertido',
  (select etapa from crm.leads where id = pg_temp.pusd_lead(1)));

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-02 · Qorilazo SIGUE en soles
-- ════════════════════════════════════════════════════════════════════════════
select pg_temp.pusd_falla('PUSD-02', 'Qorilazo en USD',
  pg_temp.pusd_cerrar(2, 'qorilazo', 5000.00, 'USD', 'PUSD-USD-002'),
  '22023', '%no registra inversiones en USD%');

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-03 · Ensanchar no es abrir del todo
-- ════════════════════════════════════════════════════════════════════════════
select pg_temp.pusd_falla('PUSD-03', 'Prodelco en EUR',
  pg_temp.pusd_cerrar(2, 'prodelco', 100.00, 'EUR', 'PUSD-EUR-001'),
  '22023', '%no registra inversiones en EUR%');
select pg_temp.pusd_falla('PUSD-03', 'Qorilazo en EUR',
  pg_temp.pusd_cerrar(2, 'qorilazo', 100.00, 'EUR', 'PUSD-EUR-002'),
  '22023', '%no registra inversiones en EUR%');
-- La moneda nula no se interpreta como «la de siempre»: se rechaza y se dice.
select pg_temp.pusd_falla('PUSD-03', 'moneda nula',
  pg_temp.pusd_cerrar(2, 'prodelco', 100.00, null, 'PUSD-NULL-001'),
  '22023', '%no registra inversiones en la moneda enviada%');

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-04 · El catálogo manda: cerrar la puerta NO necesita desplegar código
-- ════════════════════════════════════════════════════════════════════════════
savepoint pusd_catalogo;
update crm.empresas set monedas = array['PEN'] where clave = 'prodelco';
select pg_temp.pusd_falla('PUSD-04', 'Prodelco en USD con el catálogo cerrado',
  pg_temp.pusd_cerrar(3, 'prodelco', 5000.00, 'USD', 'PUSD-USD-003'),
  '22023', '%no registra inversiones en USD%');
-- Y con el catálogo abierto otra vez, la misma llamada pasa: lo único que
-- cambió entre el rechazo y la aceptación es UNA FILA.
rollback to savepoint pusd_catalogo;
select pg_temp.pusd_ok('PUSD-04', 'la misma llamada con el catálogo abierto',
  pg_temp.pusd_cerrar(3, 'prodelco', 5000.00, 'USD', 'PUSD-USD-003'));

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-05 · Sin fila en el catálogo se CIERRA, no se abre
-- ════════════════════════════════════════════════════════════════════════════
savepoint pusd_sin_fila;
update crm.empresas set clave = 'prodelco_fuera_del_catalogo' where clave = 'prodelco';
select pg_temp.pusd_falla('PUSD-05', 'Prodelco sin fila en el catálogo (USD)',
  pg_temp.pusd_cerrar(4, 'prodelco', 5000.00, 'USD', 'PUSD-USD-004'),
  '22023', '%no esta registrada%');
-- Ni siquiera en soles: sin catálogo no se sabe qué admite, y no se adivina.
select pg_temp.pusd_falla('PUSD-05', 'Prodelco sin fila en el catálogo (PEN)',
  pg_temp.pusd_cerrar(4, 'prodelco', 5000.00, 'PEN', 'PUSD-PEN-004'),
  '22023', '%no esta registrada%');
rollback to savepoint pusd_sin_fila;
-- El registro del caso vive en una tabla temporal y el `rollback to savepoint`
-- se lo lleva también: se vuelve a anotar para que el cierre no lo eche en
-- falta. (A PUSD-04 no le hace falta: tiene aserciones después del rollback.)
select pg_temp.pusd_caso('PUSD-05');

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-06 · La corrección de gerencia usa el MISMO catálogo
-- ════════════════════════════════════════════════════════════════════════════
-- Un cierre de Qorilazo en soles, para corregirlo después.
select pg_temp.pusd_ok('PUSD-06', 'cierre Qorilazo en PEN (base de la corrección)',
  pg_temp.pusd_cerrar(5, 'qorilazo', 3000.00, 'PEN', 'PUSD-PEN-005'));

create temporary table pusd_gerencia on commit drop as
select e.perfil_id from crm.equipo e
where e.activo and private.rol_crm(e.perfil_id) = 'gerencia' limit 1;

do $g$ begin
  if not exists (select 1 from pusd_gerencia) then
    raise exception 'PUSD-06: la copia no tiene gerencia activa';
  end if;
end $g$;

-- Gerencia lleva el cierre de Prodelco (PUSD-01) de USD a USD con otro monto:
-- la moneda admitida se conserva.
select pg_temp.pusd_ok('PUSD-06', 'gerencia corrige un cierre Prodelco a USD',
  pg_catalog.format(
    'select pg_temp.pusd_como(%L::uuid), crm.corregir_cierre_externo(%L::uuid, 7500.00, %L, %L, %L, null, null, null)',
    (select perfil_id from pusd_gerencia),
    (select id from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'),
    'USD', 'prodelco', 'PUSD-USD-001'));
select pg_temp.pusd_igual('PUSD-06', 'moneda tras corregir', 'USD',
  (select moneda from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'));
select pg_temp.pusd_igual('PUSD-06', 'monto tras corregir', 7500.00,
  (select monto from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'));

-- Y NO puede dejar en dólares un cierre de Qorilazo.
select pg_temp.pusd_falla('PUSD-06', 'gerencia NO corrige un Qorilazo a USD',
  pg_catalog.format(
    'select pg_temp.pusd_como(%L::uuid), crm.corregir_cierre_externo(%L::uuid, 3000.00, %L, %L, %L, null, null, null)',
    (select perfil_id from pusd_gerencia),
    (select id from crm.cierres_externos where numero_transaccion = 'PUSD-PEN-005'),
    'USD', 'qorilazo', 'PUSD-PEN-005'),
  '22023', '%no registra inversiones en USD%');
select pg_temp.pusd_igual('PUSD-06', 'el Qorilazo sigue en soles', 'PEN',
  (select moneda from crm.cierres_externos where numero_transaccion = 'PUSD-PEN-005'));

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-07 · Sin regresión: los soles siguen entrando en las dos
-- ════════════════════════════════════════════════════════════════════════════
select pg_temp.pusd_ok('PUSD-07', 'cierre Prodelco en PEN',
  pg_temp.pusd_cerrar(6, 'prodelco', 12000.00, 'PEN', 'PUSD-PEN-006'));
select pg_temp.pusd_igual('PUSD-07', 'moneda del cierre Prodelco PEN', 'PEN',
  (select moneda from crm.cierres_externos where numero_transaccion = 'PUSD-PEN-006'));
select pg_temp.pusd_ok('PUSD-07', 'cierre Qorilazo en PEN',
  pg_temp.pusd_cerrar(7, 'qorilazo', 9000.00, 'PEN', 'PUSD-PEN-007'));

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-08 · El dinero NO se mezcla: los dólares van a su columna
-- ════════════════════════════════════════════════════════════════════════════
-- Los dólares sembrados aquí: 7500 (PUSD-01 corregido) + 5000 (PUSD-04).
select pg_temp.pusd_igual('PUSD-08', 'capital vivo en USD de Prodelco', 12500.00,
  (select coalesce(sum(monto), 0) from crm.cierres_externos
   where cooperativa = 'prodelco' and moneda = 'USD' and anulado_en is null));
-- Y el núcleo ÚNICO de capital los reporta como USD, no como soles. Es la
-- pieza que decide: si aquí los dólares salieran como PEN, el cierre en USD
-- envenenaría la cuota y el ranking de todo el equipo.
create temporary table pusd_episodio on commit drop as
select e.moneda, e.monto
from private.capital_episodios(
       (statement_timestamp() - interval '2 days'),
       (statement_timestamp() + interval '2 days'), true, null) e
where e.cierre_externo_id = (select id from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001');

select pg_temp.pusd_igual('PUSD-08', 'capital_episodios: el episodio existe', 1,
  (select count(*)::integer from pusd_episodio));
select pg_temp.pusd_igual('PUSD-08', 'capital_episodios: moneda del cierre corregido', 'USD',
  (select moneda from pusd_episodio));
select pg_temp.pusd_igual('PUSD-08', 'capital_episodios: monto en USD', 7500.00,
  (select monto from pusd_episodio));
-- El total en SOLES de Prodelco no incluye ni un céntimo de los dólares.
select pg_temp.pusd_igual('PUSD-08', 'los soles de Prodelco no crecieron con los USD', 12000.00,
  (select coalesce(sum(monto), 0) from crm.cierres_externos
   where cooperativa = 'prodelco' and moneda = 'PEN' and anulado_en is null
     and numero_transaccion like 'PUSD-%'));

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-09 · La solicitud F4 (inversión adicional) usa el mismo catálogo
-- ════════════════════════════════════════════════════════════════════════════
create temporary table pusd_f4 on commit drop as
select gen_random_uuid() as clave,
       (select inversionista_id from crm.cierres_externos
        where numero_transaccion = 'PUSD-USD-001') as persona;

create function pg_temp.pusd_datos_f4(p_empresa text, p_moneda text) returns text
language sql stable as
$$
  select pg_catalog.format(
    'select private.inversion_validar_datos(%L::uuid, %L::jsonb, %L::jsonb)',
    (select clave from pusd_f4),
    jsonb_build_object(
      'inversionista_id', (select persona from pusd_f4),
      'empresa', p_empresa,
      'monto', 4000,
      'moneda', p_moneda,
      'fecha_comercial', (statement_timestamp() at time zone 'America/Lima')::date,
      'vence_en', ((statement_timestamp() at time zone 'America/Lima')::date + 365),
      'numero_transaccion', 'PUSD-F4-001',
      'referencia', 'PUSD-F4-REF',
      'evidencia', jsonb_build_object('ruta',
        (select persona from pusd_f4)::text || '/' || (select clave from pusd_f4)::text || '/comprobante.pdf')
    )::text,
    jsonb_build_object('responsable_id', pg_temp.pusd_vendedor(1))::text)
$$;

do $f4$ begin
  if (select persona from pusd_f4) is null then
    raise exception 'PUSD-09: el cierre en USD no dejó inversionista; revisar F4';
  end if;
end $f4$;

select pg_temp.pusd_ok('PUSD-09', 'solicitud F4 Prodelco en USD',
  pg_temp.pusd_datos_f4('prodelco', 'USD'));
select pg_temp.pusd_falla('PUSD-09', 'solicitud F4 Qorilazo en USD',
  pg_temp.pusd_datos_f4('qorilazo', 'USD'),
  '22023', '%no registra inversiones en USD%');
select pg_temp.pusd_ok('PUSD-09', 'solicitud F4 Qorilazo en PEN (sin regresión)',
  pg_temp.pusd_datos_f4('qorilazo', 'PEN'));

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-10 · La ruta F4 completa (preparar → confirmar) escribe la moneda real
-- ════════════════════════════════════════════════════════════════════════════
-- Hace falta el bucket de comprobantes y el objeto que la confirmación exige.
-- En una copia local se siembran; en producción ya existen.
insert into storage.buckets (id, name) values ('f4-comprobantes','f4-comprobantes')
on conflict (id) do nothing;

create temporary table pusd_f4_full on commit drop as
select (select perfil_id from pusd_gerencia) as actor,
       (select persona from pusd_f4) as persona,
       gen_random_uuid() as clave;

-- `p_clave` viaja porque el servidor valida la ruta del comprobante contra
-- <persona>/<clave>/...: si no es la misma clave que se pasa a
-- preparar_inversion_fn, la solicitud se rechaza por el comprobante y el caso
-- mediría esa otra regla en vez de la moneda.
create function pg_temp.pusd_datos_full(p_empresa text, p_moneda text, p_dep text, p_clave uuid) returns jsonb
language sql stable as
$$
  select jsonb_build_object(
    'inversionista_id', (select persona from pusd_f4_full),
    'empresa', p_empresa,
    'monto', 4321.00,
    'moneda', p_moneda,
    'fecha_comercial', (statement_timestamp() at time zone 'America/Lima')::date,
    'vence_en', ((statement_timestamp() at time zone 'America/Lima')::date + 365),
    'plazo_meses', 12,
    'tasa_anual', 9.50,
    'numero_transaccion', p_dep,
    'referencia', p_dep || '-REF',
    'evidencia', jsonb_build_object('ruta',
      (select persona from pusd_f4_full)::text || '/' || p_clave::text || '/comprobante.pdf'))
$$;

-- Gerencia prepara y confirma una inversión adicional de Prodelco en dólares.
select pg_temp.pusd_como((select actor from pusd_f4_full));

create temporary table pusd_solicitud on commit drop as
select crm.preparar_inversion_fn((select clave from pusd_f4_full),
         pg_temp.pusd_datos_full('prodelco','USD','PUSD-F4-FULL',(select clave from pusd_f4_full))) as s;

select pg_temp.pusd_igual('PUSD-10', 'la solicitud queda preparada', 'preparada',
  (select s->>'estado' from pusd_solicitud));

-- El comprobante que la confirmación exige, en la ruta que devolvió el
-- servidor (la fija ÉL con el id de la solicitud, no el cliente).
insert into storage.objects (bucket_id, name, metadata)
select 'f4-comprobantes', s->>'comprobante_ruta',
       jsonb_build_object('size', 2048, 'mimetype', 'application/pdf')
from pusd_solicitud;

select pg_temp.pusd_ok('PUSD-10', 'confirmar la inversión F4 en USD',
  pg_catalog.format('select crm.confirmar_inversion_revisada_fn(%L::uuid, %s)',
    (select s->>'solicitud_id' from pusd_solicitud),
    (select s->>'revision_datos' from pusd_solicitud)));

-- LA aserción que justifica este caso: la fila nació en USD.
select pg_temp.pusd_igual('PUSD-10', 'moneda de la fila F4', 'USD',
  (select moneda from crm.cierres_externos where numero_transaccion = 'PUSD-F4-FULL'));
select pg_temp.pusd_igual('PUSD-10', 'monto de la fila F4', 4321.00,
  (select monto from crm.cierres_externos where numero_transaccion = 'PUSD-F4-FULL'));
select pg_temp.pusd_igual('PUSD-10', 'cooperativa de la fila F4', 'prodelco',
  (select cooperativa from crm.cierres_externos where numero_transaccion = 'PUSD-F4-FULL'));

-- Y la misma ruta, con Qorilazo en dólares, se niega desde la preparación.
-- La clave nueva se reutiliza en los datos para que la ruta case y el rechazo
-- sea por la MONEDA, no por el comprobante.
create temporary table pusd_clave_qori on commit drop as select gen_random_uuid() as clave;
select pg_temp.pusd_falla('PUSD-10', 'preparar F4 Qorilazo en USD',
  pg_catalog.format('select crm.preparar_inversion_fn(%L::uuid, %L::jsonb)',
    (select clave from pusd_clave_qori),
    pg_temp.pusd_datos_full('qorilazo','USD','PUSD-F4-QORI',(select clave from pusd_clave_qori))::text),
  '22023', '%no registra inversiones en USD%');

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-11 · La moneda es inmutable al corregir una solicitud F4
-- ════════════════════════════════════════════════════════════════════════════
-- Se prepara una solicitud de Prodelco en dólares y se intenta corregir su
-- referencia mandando `moneda:'PEN'`, que es exactamente lo que manda un bundle
-- anterior. Debe rechazarse; si no, el importe se re-denominaría en silencio.
create temporary table pusd_clave_inmut on commit drop as select gen_random_uuid() as clave;
create temporary table pusd_sol_usd on commit drop as
select crm.preparar_inversion_fn((select clave from pusd_clave_inmut),
         pg_temp.pusd_datos_full('prodelco','USD','PUSD-F4-INMUT',
           (select clave from pusd_clave_inmut))) as s;

select pg_temp.pusd_igual('PUSD-11', 'la solicitud en USD queda preparada', 'preparada',
  (select s->>'estado' from pusd_sol_usd));
select pg_temp.pusd_igual('PUSD-11', 'y guardada en USD', 'USD',
  (select datos->>'moneda' from crm.inversion_solicitudes
   where id = (select (s->>'solicitud_id')::uuid from pusd_sol_usd)));

/** Los datos guardados de la solicitud, con las claves que se le cambien. */
create function pg_temp.pusd_datos_sol(p_cambios jsonb) returns text
language sql stable as
$$
  select pg_catalog.format('select crm.corregir_solicitud_inversion_fn(%L::uuid,%L::uuid,%s,%L::jsonb,%L)',
    (select (s->>'solicitud_id')::uuid from pusd_sol_usd),
    gen_random_uuid(),
    (select s->>'revision_datos' from pusd_sol_usd),
    ((select datos from crm.inversion_solicitudes
      where id=(select (s->>'solicitud_id')::uuid from pusd_sol_usd)) || p_cambios)::text,
    'Motivo sintetico del oraculo PUSD-11')
$$;

select pg_temp.pusd_falla('PUSD-11', 'corregir la referencia mandando moneda PEN (bundle anterior)',
  pg_temp.pusd_datos_sol(jsonb_build_object('moneda','PEN','referencia','PUSD-F4-INMUT-REF2')),
  '22023', '%conserva la persona, empresa, moneda%');
select pg_temp.pusd_igual('PUSD-11', 'la solicitud sigue en USD tras el rechazo', 'USD',
  (select datos->>'moneda' from crm.inversion_solicitudes
   where id = (select (s->>'solicitud_id')::uuid from pusd_sol_usd)));

-- Y corregir OTRO campo conservando la moneda sí funciona: la guarda acota la
-- moneda, no la corrección.
select pg_temp.pusd_ok('PUSD-11', 'corregir la referencia conservando USD',
  pg_temp.pusd_datos_sol(jsonb_build_object('referencia','PUSD-F4-INMUT-REF3')));
select pg_temp.pusd_igual('PUSD-11', 'la referencia se corrigió', 'PUSD-F4-INMUT-REF3',
  (select datos->>'referencia' from crm.inversion_solicitudes
   where id = (select (s->>'solicitud_id')::uuid from pusd_sol_usd)));

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-12 · Retirar la moneda entre preparar y confirmar niega la confirmación
-- ════════════════════════════════════════════════════════════════════════════
savepoint pusd_retirada;
update crm.empresas set monedas = array['PEN'] where clave = 'prodelco';
insert into storage.objects (bucket_id, name, metadata)
select 'f4-comprobantes', s->>'comprobante_ruta',
       jsonb_build_object('size', 2048, 'mimetype', 'application/pdf')
from pusd_sol_usd
on conflict do nothing;
select pg_temp.pusd_falla('PUSD-12', 'confirmar con la moneda ya retirada del catálogo',
  pg_catalog.format('select crm.confirmar_inversion_revisada_fn(%L::uuid, %s)',
    (select s->>'solicitud_id' from pusd_sol_usd),
    (select revision_datos from crm.inversion_solicitudes
     where id=(select (s->>'solicitud_id')::uuid from pusd_sol_usd))),
  'P0409', '%ya no está admitida por la cooperativa%');
-- Y no dejó nada escrito.
select pg_temp.pusd_igual('PUSD-12', 'ningún cierre nació de esa confirmación', 0,
  (select count(*)::integer from crm.cierres_externos where numero_transaccion = 'PUSD-F4-INMUT'));
rollback to savepoint pusd_retirada;
select pg_temp.pusd_caso('PUSD-12');

-- ════════════════════════════════════════════════════════════════════════════
-- PUSD-13 · La moneda de un cierre imputado a un mes SELLADO no se cambia
-- ════════════════════════════════════════════════════════════════════════════
savepoint pusd_sello;
-- Se sella el mes al que está imputado el cierre de PUSD-01 (hoy, en Lima).
-- El sello se siembra a mano con las columnas que la tabla exige; lo que este
-- caso mide es la reacción del escritor al sello, no cómo se sella (para eso
-- está el oráculo del cierre de mes).
insert into crm.periodos_cerrados (periodo, automatico, ponderacion_referido, meta_revision, cobertura)
select date_trunc('month', coalesce(ce.fecha_imputacion, ce.fecha_comercial,
         (ce.creado_en at time zone 'America/Lima')::date))::date,
       true, 1.0, 1, '{"oraculo":"PUSD-13"}'::jsonb
from crm.cierres_externos ce where ce.numero_transaccion = 'PUSD-USD-001'
on conflict (periodo) do nothing;

select pg_temp.pusd_falla('PUSD-13', 'gerencia cambia la moneda en un mes sellado',
  pg_catalog.format(
    'select pg_temp.pusd_como(%L::uuid), crm.corregir_cierre_externo(%L::uuid, 7500.00, %L, %L, %L, null, null, null)',
    (select perfil_id from pusd_gerencia),
    (select id from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'),
    'PEN', 'prodelco', 'PUSD-USD-001'),
  'P0409', '%mes ya esta sellado%');
select pg_temp.pusd_igual('PUSD-13', 'el cierre sigue en USD', 'USD',
  (select moneda from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'));

-- Corregir OTROS campos del MISMO cierre en el MISMO mes sellado sigue
-- permitido: la guarda acota la moneda, no la corrección (conducta anterior).
select pg_temp.pusd_ok('PUSD-13', 'corregir la nota del mismo cierre en el mes sellado',
  pg_catalog.format(
    'select pg_temp.pusd_como(%L::uuid), crm.corregir_cierre_externo(%L::uuid, 7500.00, %L, %L, %L, null, null, %L)',
    (select perfil_id from pusd_gerencia),
    (select id from crm.cierres_externos where numero_transaccion = 'PUSD-USD-001'),
    'USD', 'prodelco', 'PUSD-USD-001', 'Nota sintetica del oraculo PUSD-13'));
rollback to savepoint pusd_sello;
select pg_temp.pusd_caso('PUSD-13');

-- ── Todos los casos se ejecutaron ───────────────────────────────────────────
do $cierre$
declare v_faltan text[];
begin
  select array_agg(c order by c) into v_faltan
  from unnest(pg_temp.pusd_casos_esperados()) c
  where c not in (select codigo from pusd_vistos);
  if v_faltan is not null then
    raise exception 'PUSD: no se ejecutaron los casos %', v_faltan;
  end if;
end;
$cierre$;

select 'PRODELCO_USD_OK' as resultado, count(*) as casos from pusd_vistos;
rollback;
