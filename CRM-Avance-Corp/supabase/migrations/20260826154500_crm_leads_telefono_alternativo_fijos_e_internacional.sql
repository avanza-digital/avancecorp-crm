-- ---------------------------------------------------------------------------
-- El segundo numero del lead: fijos peruanos y numeros del mundo
-- ---------------------------------------------------------------------------
-- DECISIONES DE MIGUEL (2026-08-26):
--   · «necesito que los leads vengan con sus dos numeros si o si»
--   · «debe reconocer formatos de numero a nivel mundial»
--
-- Hasta hoy `telefono_alternativo` solo aceptaba celular peruano
-- (`+519########`), asi que el puente tiraba en el origen todo lo demas: el fijo
-- de la oficina y el celular del peruano que ahorra desde el extranjero. Los dos
-- son canales de contacto reales y el negocio los quiere.
--
-- EL FORMATO NUEVO, en dos tramos:
--   celular peruano   +51 9XXXXXXXX      (9 + ocho digitos)
--   fijo peruano      +51 XXXXXXXX       (ocho digitos nacionales, empieza 1..8)
--   resto del mundo   +CC...             (E.164: 8 a 15 digitos, primero 1..9)
--
-- El fijo peruano tiene SIEMPRE ocho digitos nacionales, se reparta como se
-- reparta entre zona y abonado: Lima es 1 + siete (1 445 7890) y las provincias
-- dos + seis (84 234567, Cusco). Escribirlo como «siete para Lima, seis para
-- provincias» deja fuera a medio pais.
--
-- ⚠️ EL `(?!51)` NO ES ADORNO. Sin el, el tramo internacional se traga cualquier
-- cosa que empiece por 51 y con largo plausible: `+51123456789` entraria como
-- «numero internacional valido» y nadie podria llamarlo jamas. Todo lo que dice
-- ser peruano se juzga con la vara peruana o no entra. Postgres soporta
-- lookahead en su sintaxis ARE; el postflight lo comprueba EJECUTANDOLO, porque
-- una asercion sobre el motor de regex que no se ejecuta no vale nada.
--
-- QUE NO CAMBIA. `telefono` —la identidad: dedup, reparto, conversion— no tiene
-- CHECK en esta tabla y no se le pone uno aqui: quien decide que entra es la
-- capa de aplicacion (telefonos.ts en el conector, validacion.ts en el front,
-- el puente en la hoja), y el trigger `private.trg_leads_normalizar_telefono` ya
-- canoniza a `+digitos`. Esta migracion toca UN campo informativo.
--
-- El CHECK se recrea con VALIDATE porque el formato nuevo es un SUPERCONJUNTO
-- del viejo: toda fila que pasaba sigue pasando.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_def text;
begin
  select pg_catalog.pg_get_constraintdef(oid) into v_def
    from pg_catalog.pg_constraint
   where conrelid = 'crm.leads'::regclass
     and conname = 'leads_telefono_alternativo_formato';
  if v_def is null then
    raise exception 'Falta el CHECK leads_telefono_alternativo_formato: aplicar antes 20260824154218.';
  end if;
  -- Que se este relajando el CHECK que se leyo, y no otro que alguien cambio
  -- por el camino.
  if position('^\+519[0-9]{8}$' in v_def) = 0 then
    raise exception 'El CHECK leads_telefono_alternativo_formato ya no es el que esta migracion viene a relajar: %', v_def;
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El formato nuevo
-- ---------------------------------------------------------------------------
alter table crm.leads
  drop constraint leads_telefono_alternativo_formato;

alter table crm.leads
  add constraint leads_telefono_alternativo_formato
  check (
    telefono_alternativo is null
    or telefono_alternativo ~ '^\+(51(9[0-9]{8}|[1-8][0-9]{7})|(?!51)[1-9][0-9]{7,14})$'
  ) not valid;

alter table crm.leads
  validate constraint leads_telefono_alternativo_formato;

comment on column crm.leads.telefono_alternativo is
  'Segundo canal de contacto del lead, si es distinto del principal: celular peruano (+519########), fijo peruano (+51 + ocho digitos nacionales) o numero internacional en E.164. Es informativo: telefono sigue siendo la identidad usada por el dedup, el reparto y la conversion.';

-- ---------------------------------------------------------------------------
-- 2. Postflight — EJECUTANDO el CHECK, no leyendolo
-- ---------------------------------------------------------------------------
-- Un CHECK se lee bien y rechaza mal: la unica prueba honesta es meterle filas.
--
-- Pero NO se le meten a `crm.leads`. Insertar ahi dispara los triggers de
-- auditoria y de negocio, y borrar despues exige bajar los siete candados
-- nombrados que protegen la tabla en produccion — una limpieza delicada para
-- probar un formato de texto. Se usa una tabla TEMPORAL creada con
-- `including constraints`: hereda el CHECK REAL recien instalado (es el mismo
-- objeto, copiado del catalogo, no una reescritura del regex), no hereda ni un
-- trigger, y desaparece al cerrar la sesion.
do $postflight$
declare
  v_probe record;
begin
  create temp table postflight_alt
    (like crm.leads including constraints including defaults)
    on commit drop;

  for v_probe in
    select * from (values
      -- Peru: lo de siempre y lo que se gana
      ('+51987654321',   true),   -- celular de siempre
      ('+5114457890',    true),   -- fijo de Lima  (1 + siete)
      ('+5184234567',    true),   -- fijo de Cusco (84 + seis)
      ('+5144123456',    true),   -- fijo de Trujillo
      -- El mundo
      ('+14155552671',   true),   -- EE. UU.
      ('+34612345678',   true),   -- España
      ('+819012345678',  true),   -- Japón
      ('+56987654321',   true),   -- Chile
      ('+39066982',      true),   -- ocho digitos: el minimo de E.164
      ('+123456789012345', true), -- quince digitos: el maximo de E.164
      -- Lo que NO puede entrar
      ('+51123456789',   false),  -- dice ser Peru y no tiene forma peruana
      ('+511234567',     false),  -- idem, mas corto
      ('+51044123456',   false),  -- fijo con el 0 de larga distancia: no canonico
      ('+5191234567',    false),  -- celular peruano corto
      ('+1234567890123456', false), -- dieciseis digitos: pasado de E.164
      ('+0123456789',    false),  -- codigo de pais que empieza en 0
      ('+3906698',       false),  -- siete digitos: por debajo de E.164
      ('987654321',      false),  -- sin `+`: en la columna se guarda canonico
      ('+51 987654321',  false),  -- con espacio
      ('+51987654321x',  false)   -- con cola: el ancla $ tiene que morder
    ) as t(valor, debe_entrar)
  loop
    begin
      insert into postflight_alt (nombre_completo, telefono, telefono_alternativo,
                                  origen, etapa, monto_estimado, moneda)
      values ('probe', '+51900000001', v_probe.valor, 'otro', 'nuevo', 1, 'PEN');
      if not v_probe.debe_entrar then
        raise exception 'postflight: el CHECK acepto un formato invalido: %', v_probe.valor;
      end if;
    exception
      when check_violation then
        if v_probe.debe_entrar then
          raise exception 'postflight: el CHECK rechazo un formato que debe entrar: %', v_probe.valor;
        end if;
    end;
  end loop;

  -- Que el null siga siendo legal: la inmensa mayoria de leads no trae segundo.
  insert into postflight_alt (nombre_completo, telefono, telefono_alternativo,
                              origen, etapa, monto_estimado, moneda)
  values ('probe', '+51900000002', null, 'otro', 'nuevo', 1, 'PEN');

  -- Y que la copia temporal se llevara DE VERDAD el CHECK. Sin esto, si
  -- `including constraints` no lo copiara, todos los casos de arriba entrarian
  -- y el postflight cantaria verde sin haber probado nada.
  if not exists (
    select 1 from pg_catalog.pg_constraint
     where conrelid = 'postflight_alt'::regclass
       and pg_catalog.pg_get_constraintdef(oid) like '%telefono_alternativo%'
  ) then
    raise exception 'postflight: la tabla de prueba no heredo el CHECK — la prueba no probo nada';
  end if;
end;
$postflight$;

commit;
