-- El domicilio legal: UNA sola puerta, y con el liston a la altura del dato.
--
-- POR QUE. El 2026-08-19 se cerro el agujero de los caracteres INVISIBLES en la
-- ventana nueva de «+ Contrato», pero el mismo campo tiene otras TRES puertas, y
-- las tres seguian aceptandolo (comprobado EJECUTANDO las tres, no leyendo):
--   1. `crm.convertir_lead_con_domicilio`  — al convertir un lead en cliente
--   2. `_shared/domicilio.mjs`             — el alta automatica (edge)
--   3. `crm.actualizar_cliente_gerencia_con_domicilio` — la correccion de Gerencia
-- Cada una tenia su propia copia de la validacion: `length between 5 and 240` y
-- `[[:cntrl:]]`. Tres copias de una regla es tres reglas.
--
-- QUE HACE ESTA MIGRACION. Deja `crm.normalizar_domicilio_legal` como **fuente
-- unica** y hace que las otras dos funciones SQL la usen. La edge se alinea en
-- el mismo commit (`_shared/domicilio.mjs`), y el navegador tambien.
--
-- EL LISTON, DECIDIDO CON LOS DATOS REALES, no a ojo. Los 19 domicilios que hay
-- hoy en produccion:
--   · llevan numero: 19 de 19 (100 %)
--   · el mas corto: 28 caracteres
--   · el que menos palabras tiene: 5
-- Frente a lo que hoy PASA el filtro: `LIMA.` (5), `PENDIENTE` (9), `no tiene`
-- (8), `.....`. Por eso:
--   · exigir al menos un DIGITO no molesta a nadie —lo cumple el 100 %— y mata
--     de un golpe a todos los rellenos;
--   · el minimo sube de 5 a 15 caracteres, casi la mitad del mas corto real.
-- Ninguno de los 19 domicilios vivos queda por debajo del liston nuevo: subirlo
-- no rompe ninguna correccion posterior de Gerencia.
--
-- Y LA DIRECCION DE LA PROPIA AVANCE CORP se rechaza. No es hipotetico: el
-- 2026-08-19 se tecleo `Av. República de Panamá 3635` como domicilio de una
-- clienta, que es la direccion de la empresa en la cabecera del contrato. El PDF
-- habria dicho que ambas partes domicilian en el mismo sitio, y la clausula
-- decima cuarta manda ahi TODAS las notificaciones: la carta al cliente llegaria
-- a la oficina de quien se la manda.
--
-- No altera ningun objeto de `public`; reemplaza funciones de `crm` que ya
-- escriben `public.perfiles.domicilio`, como las que ya estaban vivas.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
begin
  if to_regprocedure('crm.normalizar_domicilio_legal(text)') is null then
    raise exception 'PREFLIGHT: falta crm.normalizar_domicilio_legal(text)';
  end if;
  if to_regprocedure('crm.convertir_lead(uuid, uuid)') is null then
    raise exception 'PREFLIGHT: falta crm.convertir_lead(uuid, uuid)';
  end if;
  if to_regprocedure('crm.actualizar_cliente_gerencia(uuid, jsonb)') is null then
    raise exception 'PREFLIGHT: falta crm.actualizar_cliente_gerencia(uuid, jsonb)';
  end if;
end;
$preflight$;

-- ── La fuente unica, con el liston nuevo ─────────────────────────────────────
create or replace function crm.normalizar_domicilio_legal(p_domicilio text)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  -- Espacios exoticos que SI ocupan sitio: se convierten en espacio normal.
  v_espacios constant text := U&'\00A0\2007\202F\3000\1680\2000\2001\2002\2003\2004\2005\2006\2008\2009\200A\205F';
  -- Invisibles de ancho CERO y controles de direccion: no se normalizan, se
  -- RECHAZAN. Escritos con escapes Unicode a proposito — pegarlos literales
  -- volveria este fichero ilegible y no auditable.
  v_invisibles constant text :=
    U&'[\00AD\180E\200B\200C\200D\200E\200F\2028\2029\202A\202B\202C\202D\202E\2060\2061\2062\2063\2064\FEFF]';
  v_min constant int := 15;
  v_max constant int := 240;
  v_out text;
  v_plano text;
begin
  v_out := coalesce(p_domicilio, '');
  v_out := translate(v_out, v_espacios, repeat(' ', length(v_espacios)));
  v_out := btrim(regexp_replace(v_out, '\s+', ' ', 'g'));

  if v_out = '' then
    raise exception 'Completa el domicilio legal del cliente.'
      using errcode = '22023';
  end if;
  if v_out ~ v_invisibles then
    raise exception 'El domicilio legal contiene caracteres invisibles que no se imprimirian en el contrato.'
      using errcode = '22023';
  end if;
  -- length() sobre text cuenta CARACTERES, igual que el Array.from() del
  -- navegador.
  if length(v_out) not between v_min and v_max or v_out ~ '[[:cntrl:]]' then
    raise exception
      'El domicilio legal debe tener entre % y % caracteres válidos; escribe la calle, el número y el distrito.',
      v_min, v_max
      using errcode = '22023';
  end if;

  -- Al menos un digito. Los 19 domicilios reales de produccion lo cumplen sin
  -- excepcion, y es lo que separa una direccion de un relleno: `LIMA.`,
  -- `PENDIENTE`, `no tiene`, `Su casa` caen todos aqui.
  if v_out !~ '[0-9]' then
    raise exception
      'El domicilio legal necesita el número de la calle, el lote o la manzana.'
      using errcode = '22023';
  end if;

  -- Un unico caracter repetido: `.....`, `xxxxxxxxxxxxxxxx`, `----------------`.
  if length(regexp_replace(v_out, '[^[:alnum:]]', '', 'g')) > 0
     and (select count(distinct c) from regexp_split_to_table(
            regexp_replace(lower(v_out), '[^[:alnum:]]', '', 'g'), '') as t(c)) = 1 then
    raise exception 'El domicilio legal no puede ser un solo carácter repetido.'
      using errcode = '22023';
  end if;

  -- La direccion de la PROPIA Avance Corp. Se compara en plano (sin tildes, sin
  -- mayusculas, sin puntuacion) para que no la salve un acento o un «N.°».
  v_plano := lower(translate(v_out,
    'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
  v_plano := regexp_replace(v_plano, '[^a-z0-9 ]', '', 'g');
  v_plano := regexp_replace(v_plano, '\s+', ' ', 'g');
  if v_plano like '%republica de panama%' and v_plano like '%3635%' then
    raise exception
      'Esa es la dirección de Avance Corp, no la del cliente: el contrato dejaría a las dos partes domiciliadas en el mismo sitio.'
      using errcode = '22023';
  end if;

  return v_out;
end;
$function$;

comment on function crm.normalizar_domicilio_legal(text) is
  'FUENTE UNICA de validacion del domicilio legal: normaliza espacios Unicode, rechaza invisibles de ancho cero, exige 15..240 caracteres y al menos un digito, y rechaza un solo caracter repetido y la direccion de la propia Avance Corp. La usan las TRES puertas SQL; el navegador y la edge la espejan.';

revoke all on function crm.normalizar_domicilio_legal(text)
  from public, anon, authenticated, service_role;

-- ── Puerta 1: convertir un lead en cliente ───────────────────────────────────
-- Tenia su propia copia de la regla (5..240 + cntrl). Ahora presta la fuente
-- unica, y de paso ESCRIBE el texto normalizado en vez del `btrim` a secas.
create or replace function crm.convertir_lead_con_domicilio(
  p_lead_id uuid,
  p_perfil_id uuid,
  p_domicilio text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_domicilio text;
  v_resultado jsonb;
  v_accion text := 'conservado';
begin
  -- Se valida ANTES de convertir: si falla, todavia no se ha escrito nada.
  v_domicilio := crm.normalizar_domicilio_legal(p_domicilio);

  v_resultado := crm.convertir_lead(p_lead_id, p_perfil_id);

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_perfil_id
     and rol = 'cliente'
     and domicilio is null;
  if found then v_accion := 'completado'; end if;

  return v_resultado || jsonb_build_object('domicilio_accion', v_accion);
end;
$function$;

comment on function crm.convertir_lead_con_domicilio(uuid, uuid, text) is
  'Convierte el lead y completa el domicilio SOLO si estaba vacio. Valida con crm.normalizar_domicilio_legal (fuente unica) ANTES de convertir: un domicilio invalido no deja el lead a medias.';

-- ── Puerta 3: la correccion de Gerencia ──────────────────────────────────────
-- Tercera copia de la misma regla, y la unica que puede SOBRESCRIBIR un
-- domicilio existente. Es justamente la que repara los errores de las otras dos:
-- con mas razon tiene que aplicar el mismo liston.
create or replace function crm.actualizar_cliente_gerencia_con_domicilio(
  p_cliente_id uuid,
  p_patch jsonb
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_domicilio text;
  v_actualizado boolean;
begin
  if private.rol_crm((select auth.uid())) is distinct from 'gerencia' then
    raise insufficient_privilege using
      message = 'Solo Gerencia puede corregir clientes fuera de cartera';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object'
     or not p_patch ? 'domicilio'
     or jsonb_typeof(p_patch->'domicilio') <> 'string' then
    raise exception 'El domicilio legal del cliente es obligatorio'
      using errcode = '22023';
  end if;

  v_domicilio := crm.normalizar_domicilio_legal(p_patch->>'domicilio');

  v_actualizado := crm.actualizar_cliente_gerencia(
    p_cliente_id,
    p_patch - 'domicilio'
  );
  if not v_actualizado then return false; end if;

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_cliente_id
     and rol = 'cliente';
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;

comment on function crm.actualizar_cliente_gerencia_con_domicilio(uuid, jsonb) is
  'Correccion de Gerencia: unica via que puede SOBRESCRIBIR un domicilio ya registrado. Valida con crm.normalizar_domicilio_legal (fuente unica).';

-- ── Postflight ───────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puertas text[] := array[
    'crm.convertir_lead_con_domicilio',
    'crm.actualizar_cliente_gerencia_con_domicilio',
    'crm.completar_domicilio_cliente'
  ];
  v_p text;
  v_src text;
  v_huerfanas text[] := '{}';
  v_bajo_liston int;
  v_medibles int;
begin
  -- 1. Las TRES puertas prestan la fuente unica. Si alguna vuelve a llevar su
  --    copia de la regla, esto lo dice por su nombre.
  foreach v_p in array v_puertas loop
    select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname || '.' || p.proname = v_p
    limit 1;
    if v_src is null then
      raise exception 'POSTFLIGHT 1: no existe %', v_p;
    end if;
    if strpos(v_src, 'crm.normalizar_domicilio_legal') = 0 then
      v_huerfanas := v_huerfanas || v_p;
    end if;
  end loop;
  if cardinality(v_huerfanas) > 0 then
    raise exception
      'POSTFLIGHT 1: estas puertas NO usan la fuente unica y validan por su cuenta: %',
      array_to_string(v_huerfanas, ', ');
  end if;
  raise notice 'POSTFLIGHT 1 OK: las 3 puertas del domicilio prestan la misma validacion.';

  -- 2. El liston nuevo no deja fuera a ningun domicilio YA registrado: si lo
  --    hiciera, Gerencia no podria volver a guardar la ficha de ese cliente.
  --
  --    ⚠️ Esta sonda tiene HAMBRE DE DATOS y lo DICE. En un branch recien
  --    sembrado no hay ni un domicilio escrito, asi que pasaria en verde sin
  --    haber medido nada — la «rama de aviso disfrazada de OK» que este
  --    proyecto prohibe. Si no hay nada que medir, se grita en vez de aprobar:
  --    el numero real hay que mirarlo en PRODUCCION antes de aplicar alli.
  --    (Medido el 2026-08-19 contra produccion: 22 domicilios, 0 por debajo de
  --    15 caracteres, 0 sin numero, el mas corto de 28.)
  select count(*) into v_medibles
  from public.perfiles
  where rol = 'cliente'
    and nullif(btrim(coalesce(domicilio, '')), '') is not null;

  if v_medibles = 0 then
    raise warning
      'POSTFLIGHT 2 NO SE EJERCITO: esta base no tiene ni un domicilio escrito. NO cuenta como aprobado — comprueba el liston contra PRODUCCION antes de aplicarlo alli.';
  else
    select count(*) into v_bajo_liston
    from public.perfiles
    where rol = 'cliente'
      and nullif(btrim(coalesce(domicilio, '')), '') is not null
      and (length(btrim(domicilio)) < 15 or btrim(domicilio) !~ '[0-9]');
    if v_bajo_liston > 0 then
      raise exception
        'POSTFLIGHT 2: % de % domicilios YA registrados quedan por debajo del liston nuevo; Gerencia no podria reguardarlos',
        v_bajo_liston, v_medibles;
    end if;
    raise notice 'POSTFLIGHT 2 OK: los % domicilios vivos pasan el liston.', v_medibles;
  end if;

  -- 3. Y el liston hace lo que dice: se EJECUTA la funcion contra la basura y
  --    contra una direccion real. Mirar el catalogo no prueba nada.
  declare
    v_basura text[] := array[
      'LIMA.', 'PENDIENTE', 'no tiene', 'Su casa', '....................',
      'Av. República de Panamá 3635'
    ];
    v_caso text;
    v_coladas text[] := '{}';
  begin
    foreach v_caso in array v_basura loop
      begin
        perform crm.normalizar_domicilio_legal(v_caso);
        v_coladas := v_coladas || v_caso;
      exception when sqlstate '22023' then
        null; -- correcto
      end;
    end loop;
    if cardinality(v_coladas) > 0 then
      raise exception 'POSTFLIGHT 3: se colaron por el liston: %',
        array_to_string(v_coladas, ' | ');
    end if;
    -- Y una direccion REAL de produccion tiene que pasar, o el arreglo seria
    -- peor que el problema: volveria a bloquear a los vendedores.
    if crm.normalizar_domicilio_legal('AV. MAESTRO PERUANO 225 URB. CARABAYLLO, COMAS, LIMA, LIMA')
       <> 'AV. MAESTRO PERUANO 225 URB. CARABAYLLO, COMAS, LIMA, LIMA' then
      raise exception 'POSTFLIGHT 3: una direccion real de produccion no pasa el liston';
    end if;
    raise notice 'POSTFLIGHT 3 OK: los 6 rellenos se rechazan y la direccion real pasa intacta.';
  end;
end;
$postflight$;

commit;
