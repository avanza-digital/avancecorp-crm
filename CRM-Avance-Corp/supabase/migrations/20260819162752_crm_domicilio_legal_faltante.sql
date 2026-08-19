-- Domicilio legal faltante: desbloquea el 2.o contrato de un cliente antiguo.
--
-- EL SINTOMA (Miguel, 2026-08-19): «los vendedores no pueden registrar otro
-- contrato a clientes antiguos».
--
-- LA CAUSA, medida en produccion. `crm.crear_contrato_con_cuenta_pdf_v2` reserva
-- el PDF en la MISMA transaccion del alta, y `private.contrato_pdf_snapshot_v2_base`
-- exige los datos que van escritos en el documento: del cliente
-- nombre_completo, tipo_documento, dni, DOMICILIO y correo; del analista
-- nombre_completo, dni, telefono y correo. Si falta uno, el raise revierte el
-- contrato ENTERO. Reproducido en produccion sin escribir nada (bloque DO que
-- termina en raise) sobre el contrato d2625108-3081-46e5-a016-6bdc7b19a984.
--
-- Censo del 2026-08-19 sobre los 319 clientes con contrato: 313 sin domicilio
-- (98%) y CERO sin cualquiera de los otros cuatro campos. El domicilio es el
-- unico culpable, y esta medido campo por campo, no por muestreo.
--
-- Y el vendedor no veia ni siquiera ese mensaje: `aErrorApi` no reconocia el
-- 23514 y lo convertia en «No se pudo guardar el cambio.» (corregido en el
-- front por este mismo cambio). Por eso nadie pudo diagnosticarlo.
--
-- POR QUE NO PODIAN ARREGLARLO ELLOS. `perfiles_analista_update` exige
-- `creado_en > now() - '05:00:00'`: la ventana de «Corregir» dura 5 h desde que
-- el vendedor creo al cliente. Un cliente de hace meses cae fuera, asi que el
-- vendedor no podia emitir NI escribir el dato. `perfiles_analista_select` no
-- tiene ventana: podia LEER el hueco sin poder cerrarlo.
--
-- QUE ABRE (decisiones de Miguel, 2026-08-19): (1) el VENDEDOR rellena el
-- domicilio de sus clientes sin depender de nadie; (2) SOLO se rellena el
-- vacio — un domicilio ya registrado no se pisa nunca desde aqui.
--
-- EL GATE ES PRESTADO, NO COPIADO: `private.puede_gestionar_cuentas_cliente()`,
-- el mismo con el que `crm.crear_contrato_con_cuenta` decide quien gestiona la
-- banca contractual del cliente. Inventar un segundo concepto de «cartera» es
-- la via por la que este proyecto ya se hizo dano. Es condicion NECESARIA para
-- emitir pero no suficiente (`public.crear_contrato` exige ademas rol), asi que
-- el conjunto que podra escribir el domicilio es un SUPERCONJUNTO del que
-- emite: no se afirma equivalencia. Medido ejecutando el predicado real: de los
-- 313 afectados, 312 los resuelve su propio asesor y 1 (sin asesor asignado)
-- necesita a Gerencia. Inalcanzables: 0.
--
-- AUDITORIA ADVERSARIA (2026-08-19, 4 lentes: Codex + auditor-rls + carreras +
-- consecuencias legales). Lo aplicado aqui:
--   · el permiso se REEVALUA despues del lock (autorizacion caducada);
--   · no se devuelve el domicilio ajeno (era lectura de PII para el supervisor,
--     que por RLS no puede leer esa columna);
--   · `for no key update` en vez de `for update`: misma exclusion mutua sin
--     frenar inserts de tablas hijas con FK a ese perfil;
--   · `get diagnostics` sobre el UPDATE: responder 'completado' habiendo tocado
--     0 filas seria mentir al vendedor y dejarlo bloqueado creyendo que guardo;
--   · se rechazan los caracteres INVISIBLES (ancho cero, guion suave, controles
--     bidi). Comprobado contra el CHECK vivo de produccion: seis U+200B lo
--     pasan hoy, se imprimirian como NADA en el contrato y —al no ser vacios
--     para btrim— cerrarian el hueco PARA SIEMPRE (el trigger
--     `perfiles_domicilio_legal_no_borrar` impide volver a NULL y esta funcion
--     nunca pisa lo existente);
--   · el postflight comprobaba `search_path=` cuando el catalogo guarda
--     `search_path=""`: la sonda era SIEMPRE falsa y habria hecho rollback de
--     la migracion entera, en todas sus ejecuciones;
--   · `create or replace` + sondas de datos fuera: la version anterior exigia
--     que el defecto siguiera vivo, asi que no se podia reaplicar en un branch
--     ya saneado. Las sondas de COMPORTAMIENTO (que ejecutan las funciones, en
--     vez de mirar el catalogo) viven en
--     `supabase/scripts/test-domicilio-legal.sql`.
--
-- No altera NINGUN objeto de `public`: crea funciones en `crm` que ESCRIBEN una
-- columna de `public.perfiles`, igual que la RPC de Gerencia ya viva. Lo que si
-- cambia es QUIEN escribe esa columna saltandose la RLS del portal (antes solo
-- Gerencia; ahora toda la cartera CRM): queda anotado en el registro de
-- excepciones de MIGRACIONES.md aunque no haya DDL, porque ese registro es el
-- indice donde se busca «quien le escribe a mis tablas».

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- ── Preflight: plpgsql NO resuelve referencias al crear ──────────────────────
-- Sin esto, un renombrado de las dependencias crearia ambas funciones y solo
-- fallaria en runtime, con el vendedor delante.
do $preflight$
begin
  if to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null then
    raise exception 'PREFLIGHT: falta private.puede_gestionar_cuentas_cliente(uuid)';
  end if;
  if to_regprocedure('private.contrato_pdf_snapshot_v2_base(uuid)') is null then
    raise exception 'PREFLIGHT: falta private.contrato_pdf_snapshot_v2_base(uuid)';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'perfiles'
      and column_name = 'domicilio'
  ) then
    raise exception 'PREFLIGHT: falta public.perfiles.domicilio';
  end if;
end;
$preflight$;

-- ── Normalizador compartido del domicilio legal ──────────────────────────────
-- Fuente UNICA del servidor, espejo de `validarDomicilioLegal` del navegador.
-- Devuelve el texto normalizado o levanta el error es-PE correspondiente.
--
-- Por que normalizar y no solo validar: `btrim` de Postgres solo quita U+0020,
-- mientras que `.trim()` de JavaScript quita todo el espacio Unicode. Sin
-- normalizar, «  Lima » lo rechaza el navegador (4 caracteres) y
-- lo acepta el servidor (7): dos varas para el mismo dato.
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
  -- RECHAZAN. Se escriben con escapes Unicode a proposito — pegarlos literales
  -- volveria ilegible (y no auditable) este fichero.
  v_invisibles constant text :=
    U&'[\00AD\180E\200B\200C\200D\200E\200F\2028\2029\202A\202B\202C\202D\202E\2060\2061\2062\2063\2064\FEFF]';
  v_out text;
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
  -- navegador. Limites identicos a crm.actualizar_cliente_gerencia_con_domicilio
  -- y al CHECK vivo perfiles_domicilio_legal_valido.
  if length(v_out) not between 5 and 240 or v_out ~ '[[:cntrl:]]' then
    raise exception
      'El domicilio legal debe tener entre 5 y 240 caracteres válidos'
      using errcode = '22023';
  end if;
  return v_out;
end;
$function$;

comment on function crm.normalizar_domicilio_legal(text) is
  'Normaliza (espacios Unicode a espacio simple, colapsa, recorta) y valida el domicilio legal: 5..240 caracteres, sin controles y sin invisibles de ancho cero. Fuente unica del servidor; espejo de validarDomicilioLegal del navegador.';

revoke all on function crm.normalizar_domicilio_legal(text)
  from public, anon, authenticated, service_role;

-- ── Lectura: que dato legal falta para poder emitir ──────────────────────────
-- Devuelve NOMBRES de campo, nunca valores: no es una via para leer PII.
--
-- El «analista» que valida el snapshot es `contratos.creado_por`, y
-- `public.crear_contrato` lo escribe siempre como auth.uid(): por eso aqui se
-- mira el perfil de QUIEN LLAMA. Eso la hace correcta para el ALTA (su unico
-- consumidor) y solo para el alta — para regenerar el PDF de un contrato creado
-- por otra persona, el perfil que importa es el de aquella. Anotado como deuda
-- en el ledger; el nombre no promete otra cosa.
create or replace function crm.datos_legales_contrato_fn(p_cliente_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_cliente public.perfiles%rowtype;
  v_analista public.perfiles%rowtype;
  -- Los append van con ::text explicito: `text[] || 'literal'` es AMBIGUO en
  -- Postgres (intenta castear el literal a text[]) y revienta en RUNTIME con
  -- «malformed array literal», no al crear la funcion. Compilaba y fallaba con
  -- el vendedor delante; lo caza el oraculo de comportamiento, no el catalogo.
  v_faltan_cliente text[] := '{}';
  v_faltan_analista text[] := '{}';
begin
  if v_uid is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;

  -- MISMO texto para «no existe» y «ajeno»: no da oraculo de existencia.
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  select * into v_cliente
  from public.perfiles p
  where p.id = p_cliente_id
    and p.rol = 'cliente';
  if not found then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  select * into v_analista
  from public.perfiles p
  where p.id = v_uid;
  if not found then
    raise exception 'Tu perfil no esta disponible' using errcode = 'P0002';
  end if;

  if nullif(btrim(coalesce(v_cliente.nombre_completo, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'nombre_completo'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.tipo_documento, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'tipo_documento'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.dni, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'documento'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.domicilio, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'domicilio'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.correo, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'correo'::text;
  end if;

  if nullif(btrim(coalesce(v_analista.nombre_completo, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'nombre_completo'::text;
  end if;
  if nullif(btrim(coalesce(v_analista.dni, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'documento'::text;
  end if;
  if nullif(btrim(coalesce(v_analista.telefono, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'telefono'::text;
  end if;
  if nullif(btrim(coalesce(v_analista.correo, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'correo'::text;
  end if;

  return jsonb_build_object(
    'version', 1,
    'cliente_id', p_cliente_id,
    -- El unico que el vendedor puede resolver por su cuenta. Los demas huecos
    -- se informan para que el front diga a quien acudir, no para que los edite.
    'falta_domicilio', ('domicilio' = any (v_faltan_cliente)),
    'faltan_cliente', to_jsonb(v_faltan_cliente),
    'faltan_analista', to_jsonb(v_faltan_analista)
  );
end;
$function$;

comment on function crm.datos_legales_contrato_fn(uuid) is
  'Que dato legal falta para poder EMITIR el contrato de este cliente: nombres de campo del cliente y del propio analista que llama, nunca valores. Espejo de private.contrato_pdf_snapshot_v2_base. Alcance: private.puede_gestionar_cuentas_cliente.';

revoke all on function crm.datos_legales_contrato_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.datos_legales_contrato_fn(uuid) to authenticated;

-- ── Escritura: rellenar el domicilio VACIO ───────────────────────────────────
create or replace function crm.completar_domicilio_cliente(
  p_cliente_id uuid,
  p_domicilio text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_domicilio text;
  v_actual text;
  v_filas int;
begin
  if v_uid is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;

  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  v_domicilio := crm.normalizar_domicilio_legal(p_domicilio);

  -- Techo a la espera del lock: mas vale un error claro que una pantalla
  -- colgada mientras otra transaccion larga retiene la fila.
  perform set_config('lock_timeout', '3s', true);

  -- `for no key update` y no `for update`: da la misma exclusion mutua entre
  -- dos escrituras concurrentes del domicilio y sigue conflictuando con el
  -- `for share` del alta de contrato, pero NO bloquea los inserts de tablas
  -- hijas con FK a este perfil (contratos, cuentas, leads).
  select nullif(btrim(coalesce(p.domicilio, '')), '')
  into v_actual
  from public.perfiles p
  where p.id = p_cliente_id
    and p.rol = 'cliente'
  for no key update;
  if not found then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  -- El permiso se comprueba OTRA VEZ, ya con la fila bloqueada: entre la
  -- primera comprobacion y el lock pudo esperarse a otra transaccion (una
  -- reasignacion de cartera, una baja) y la autorizacion de arriba estaria
  -- caducada. Mismo patron que private.crear_job_contrato_pdf_base.
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  -- NO se devuelve el domicilio que ya estaba: el alcance incluye al supervisor
  -- del arbol, que por RLS no puede leer public.perfiles.domicilio
  -- (perfiles_analista_select exige asesor_perfil_id = auth.uid()). Devolverlo
  -- convertiria una funcion de ESCRITURA en una via de lectura de PII.
  if v_actual is not null then
    return jsonb_build_object('version', 1, 'accion', 'conservado');
  end if;

  update public.perfiles
  set domicilio = v_domicilio
  where id = p_cliente_id
    and rol = 'cliente';

  -- Sin esto, un UPDATE que toque 0 filas (RLS forzada, trigger, la fila
  -- cambiada bajo los pies) devolveria 'completado' y el vendedor veria
  -- «Domicilio legal registrado» sobre algo que no se guardo: seguiria
  -- bloqueado, y convencido de lo contrario.
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception 'El domicilio legal no se pudo registrar (% filas afectadas)', v_filas
      using errcode = 'P0001';
  end if;

  -- Tampoco se devuelve en 'completado': es EXACTAMENTE el texto que envio
  -- quien llama, y devolverlo solo abriria la puerta a usar esta funcion como
  -- lectura disfrazada.
  return jsonb_build_object('version', 1, 'accion', 'completado');
end;
$function$;

comment on function crm.completar_domicilio_cliente(uuid, text) is
  'Rellena public.perfiles.domicilio SOLO si esta vacio (nunca lo pisa; devuelve completado|conservado, sin el valor). Normaliza y valida via crm.normalizar_domicilio_legal. Alcance: private.puede_gestionar_cuentas_cliente, reevaluado tras el lock.';

revoke all on function crm.completar_domicilio_cliente(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function crm.completar_domicilio_cliente(uuid, text) to authenticated;

-- ── Postflight ESTRUCTURAL (re-ejecutable) ───────────────────────────────────
-- Las sondas de comportamiento —las que EJECUTAN las funciones contra datos—
-- viven en supabase/scripts/test-domicilio-legal.sql, no aqui: una sonda que
-- exija «que el defecto siga existiendo» convierte la migracion en irrepetible
-- y se auto-invalida el dia en que el arreglo funciona.
do $postflight$
declare
  v_fuente text;
  v_bloque text;
  v_campo text;
  v_faltan text[] := '{}';
begin
  -- 1. El espejo sigue siendo espejo. Se mira SOLO el bloque de validacion del
  --    snapshot (desde el `if nullif(btrim(` hasta su `raise`), no la funcion
  --    entera: buscar el identificador en todo el cuerpo daba verde aunque
  --    alguien sacara el campo del `if` y lo dejara en el jsonb de salida.
  -- Sin `strict`: si la funcion no existe o esta sobrecargada, el error nativo
  -- («query returned no rows») no dice cual es el problema ni cual es la sonda.
  select pg_get_functiondef(p.oid) into v_fuente
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'contrato_pdf_snapshot_v2_base'
  limit 1;
  if v_fuente is null then
    raise exception
      'POSTFLIGHT 1: no existe private.contrato_pdf_snapshot_v2_base; el espejo no se puede comprobar';
  end if;

  v_bloque := substring(
    v_fuente
    from 'if nullif\(btrim.*?Faltan datos legales obligatorios'
  );
  if v_bloque is null then
    raise exception
      'POSTFLIGHT 1: no se encontro el bloque de validacion legal del snapshot; el espejo ya no se puede comprobar';
  end if;

  foreach v_campo in array array[
    'v_cliente.nombre_completo', 'v_cliente.tipo_documento', 'v_cliente.dni',
    'v_cliente.domicilio', 'v_cliente.correo',
    'v_analista.nombre_completo', 'v_analista.dni',
    'v_analista.telefono', 'v_analista.correo'
  ] loop
    if strpos(v_bloque, v_campo) = 0 then
      v_faltan := v_faltan || v_campo;
    end if;
  end loop;
  if cardinality(v_faltan) > 0 then
    raise exception
      'POSTFLIGHT 1: el snapshot ya no exige %; datos_legales_contrato_fn quedo desalineada',
      array_to_string(v_faltan, ', ');
  end if;

  -- Y al reves: si el snapshot exige MAS campos de perfil de los que espejamos,
  -- el vendedor volveria a chocar contra un muro sin nombre. Se cuenta.
  if (select count(*) from regexp_matches(v_bloque, 'v_(cliente|analista)\.', 'g')) <> 9 then
    raise exception
      'POSTFLIGHT 1: el snapshot exige % campos de perfil y el espejo cubre 9',
      (select count(*) from regexp_matches(v_bloque, 'v_(cliente|analista)\.', 'g'));
  end if;
  raise notice 'POSTFLIGHT 1 OK: los 9 campos legales del snapshot estan espejados (bloque de validacion, no el cuerpo entero).';

  -- 2. Las tres funciones nacen con search_path fijado y los grants exactos.
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname in (
        'datos_legales_contrato_fn', 'completar_domicilio_cliente',
        'normalizar_domicilio_legal'
      )
      -- `set search_path to ''` deja en proconfig el literal `search_path=""`
      -- CON comillas. La forma ingenua ('search_path=' = any(...)) es SIEMPRE
      -- falsa, asi que la sonda levantaba excepcion en toda ejecucion y hacia
      -- rollback de la migracion entera. Verificado en PG16 y PG17 por la
      -- auditoria adversaria del 2026-08-19; el resto del repo ya usa esta
      -- forma en 8 sitios.
      and (p.proconfig is null or not (p.proconfig @> array['search_path=""']))
  ) then
    raise exception 'POSTFLIGHT 2: alguna funcion nueva no fijo search_path';
  end if;

  -- Los dos lados del grant, no solo uno: que anon/service_role NO puedan y que
  -- authenticated SI pueda. Un grant mal escrito deja la pantalla muerta y la
  -- version anterior de esta sonda no lo habria cazado.
  --
  -- Los roles se comprueban antes: has_function_privilege() sobre un rol
  -- inexistente lanza `role "X" does not exist` y abortaria el arnes local con
  -- un error que no describe nada.
  if to_regrole('anon') is null
     or to_regrole('authenticated') is null
     or to_regrole('service_role') is null then
    raise notice 'POSTFLIGHT 2: faltan los roles de Supabase (base pelada); se omite la comprobacion de grants.';
  elsif has_function_privilege('anon', 'crm.datos_legales_contrato_fn(uuid)', 'execute')
     or has_function_privilege('anon', 'crm.completar_domicilio_cliente(uuid, text)', 'execute')
     or has_function_privilege('anon', 'crm.normalizar_domicilio_legal(text)', 'execute')
     or has_function_privilege('service_role', 'crm.datos_legales_contrato_fn(uuid)', 'execute')
     or has_function_privilege('service_role', 'crm.completar_domicilio_cliente(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'crm.normalizar_domicilio_legal(text)', 'execute') then
    raise exception 'POSTFLIGHT 2: alguna funcion nueva conserva execute para un rol que no debe';
  end if;
  if not has_function_privilege('authenticated', 'crm.datos_legales_contrato_fn(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'crm.completar_domicilio_cliente(uuid, text)', 'execute') then
    raise exception 'POSTFLIGHT 2: authenticated NO puede ejecutar las RPC; la pantalla naceria muerta';
  end if;
  if not (
    select bool_and(p.prosecdef)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname in ('datos_legales_contrato_fn', 'completar_domicilio_cliente')
  ) then
    raise exception 'POSTFLIGHT 2: alguna RPC no quedo como SECURITY DEFINER';
  end if;
  raise notice 'POSTFLIGHT 2 OK: search_path fijado, SECURITY DEFINER donde toca y grants minimos en los dos sentidos.';

  -- 3. La autoria de la escritura NO es una premisa: se ancla. Es la primera
  --    vez que esta columna se abre a decenas de personas, y el unico rastro de
  --    quien la escribio es el trigger de auditoria del portal.
  --    Los casts van por to_regclass/to_regprocedure: el cast directo revienta
  --    con `undefined_function` ANTES de llegar al raise con nombre, y la sonda
  --    nunca llega a decir lo que queria decir.
  if to_regprocedure('public.log_audit_change()') is null
     or not exists (
    select 1 from pg_trigger t
    where t.tgrelid = to_regclass('public.perfiles')
      and not t.tgisinternal
      and t.tgfoid = to_regprocedure('public.log_audit_change()')
  ) then
    raise exception
      'POSTFLIGHT 3: public.perfiles no tiene el trigger de auditoria; la escritura del domicilio quedaria sin autor';
  end if;
  raise notice 'POSTFLIGHT 3 OK: la escritura del domicilio queda auditada con su autor.';
end;
$postflight$;

commit;
