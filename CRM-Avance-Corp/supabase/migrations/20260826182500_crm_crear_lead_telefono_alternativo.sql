-- ---------------------------------------------------------------------------
-- El alta manual de un lead admite su SEGUNDO numero
-- ---------------------------------------------------------------------------
-- OPCION A, elegida por Miguel (2026-08-26): el primer numero IDENTIFICA al
-- lead y por eso sigue siendo celular peruano; el segundo es solo una forma de
-- contactarlo y admite lo que sea — otro celular, un fijo peruano o un numero
-- de cualquier pais.
--
-- POR QUE EL PRINCIPAL NO SE TOCA. `private.normalizar_telefono` es la pieza con
-- la que TODO el CRM decide que dos leads son el mismo: dedup, reparto y
-- conversion cuelgan de ella. Ensancharla movería esa huella hacia atras, sobre
-- 544 leads vivos. La opcion B queda escrita en el vault para cuando haya un
-- caso real que la justifique, no por si acaso.
--
-- QUE CAMBIA. Un parametro nuevo, `p_telefono_alternativo`, al final y con
-- DEFAULT NULL (asi ninguna llamada existente se rompe). Se canoniza con
-- `private.canonizar_contacto` — la MISMA regla del conector, del front y del
-- puente, en vez de un regex reescrito aqui dentro, que es como los espejos
-- empiezan a divergir.
--
-- Es `drop` + `create` y no `create or replace`: añadir un parametro crea una
-- SOBRECARGA, no un reemplazo, y dos funciones con el mismo nombre harian
-- ambigua cada llamada. Por eso el grant se vuelve a poner explicitamente.
--
-- ASIMETRIA CONSCIENTE, dicha para que nadie la descubra por accidente: por la
-- via automatica (hoja → conector) un lead SI puede entrar con un fijo de
-- identidad, porque alli la alternativa era perder el lead entero. Tecleando a
-- mano se exige celular. Un cliente de oficina que solo deje un fijo no se
-- podra registrar; se decidio asumirlo (Miguel, 2026-08-26).
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if to_regprocedure('private.canonizar_contacto(text)') is null then
    raise exception 'Falta private.canonizar_contacto: aplicar antes 20260826182000.';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'crm.leads'::regclass
       and attname = 'telefono_alternativo' and not attisdropped
  ) then
    raise exception 'Falta crm.leads.telefono_alternativo: aplicar antes 20260824154218.';
  end if;
  -- Ancla del cuerpo VIVO: si alguien toco la funcion por otro lado, este `drop`
  -- se llevaria ese cambio por delante en silencio.
  if (select md5(prosrc) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'crear_lead_si_disponible')
     is distinct from '3c06a68dd2c9a1a7ead67cf5019c1aa8' then
    raise exception 'crm.crear_lead_si_disponible cambio desde que se escribio esta migracion: contrastar el cuerpo vivo antes de reemplazarlo.';
  end if;
end;
$preflight$;

drop function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text
);

create function crm.crear_lead_si_disponible(
  p_nombre_completo text,
  p_telefono text,
  p_origen text,
  p_monto_estimado numeric,
  p_moneda text,
  p_id uuid default null,
  p_correo text default null,
  p_dni text default null,
  p_genero text default null,
  p_fecha_nacimiento date default null,
  p_distrito text default null,
  p_etapa text default 'nuevo',
  p_categoria_interes text default null,
  p_vendedor_id uuid default null,
  p_nota text default null,
  p_telefono_alternativo text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_rol_actual text;
  v_id uuid := coalesce(p_id, pg_catalog.gen_random_uuid());
  v_nombre text := nullif(pg_catalog.btrim(p_nombre_completo), '');
  v_telefono text := private.normalizar_telefono(p_telefono);
  v_alt_bruto text := nullif(pg_catalog.btrim(p_telefono_alternativo), '');
  v_alt text;
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_correo text := nullif(pg_catalog.btrim(p_correo), '');
  v_genero text := nullif(pg_catalog.btrim(p_genero), '');
  v_distrito text := nullif(pg_catalog.btrim(p_distrito), '');
  v_categoria text := nullif(pg_catalog.btrim(p_categoria_interes), '');
  v_nota text := nullif(pg_catalog.btrim(p_nota), '');
  v_vendedor uuid := p_vendedor_id;
  v_supervisor uuid;
  v_disponibilidad jsonb;
  v_existente crm.leads%rowtype;
  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_nombre is null then
    raise exception using errcode = '22023', message = 'El nombre es obligatorio';
  end if;
  if v_telefono is null or v_telefono !~ '^\+519[0-9]{8}$' then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  -- EL SEGUNDO NUMERO (opcion A). Admite celular, fijo peruano o cualquier pais,
  -- via la MISMA regla que el conector y el front. No participa del dedup: la
  -- identidad del lead sigue siendo `telefono`.
  if v_alt_bruto is not null then
    select c.e164 into v_alt from private.canonizar_contacto(v_alt_bruto) c;
    if v_alt is null then
      raise exception using
        errcode = '22023',
        message = 'Segundo telefono invalido: celular peruano, fijo peruano (014457890) o internacional con +codigo de pais';
    end if;
    -- Si repite al principal no aporta un canal nuevo: se guarda vacio en vez de
    -- enseñar el mismo numero dos veces en la ficha.
    if v_alt = v_telefono then
      v_alt := null;
    end if;
  end if;

  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  if p_origen not in ('referido', 'landing', 'formulario', 'oficina', 'otro', 'web', 'campania', 'whatsapp') then
    raise exception using errcode = '22023', message = 'Origen invalido';
  end if;

  -- D8 (2026-08-11) · «landing y formulario se carga solo»: los canales
  -- automáticos (y los heredados) SOLO entran por el puente. Un alta manual que
  -- los declare está suplantando a la fuente — y con T10 vivo (el referido
  -- fuera del divisor), el origen mueve el porcentaje de alguien.
  if p_origen not in ('referido', 'oficina', 'otro') then
    raise exception using
      errcode = '42501',
      message = 'Ese origen entra solo por el puente: el alta manual admite referido, oficina u otro';
  end if;

  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
  -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
  -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
  if p_origen = 'referido' and v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
  end if;

  if p_etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead no puede nacer en etapa terminal';
  end if;
  if p_monto_estimado is null
     or p_monto_estimado <= 0
     or p_monto_estimado > 9999999999.99
     or p_monto_estimado <> pg_catalog.trunc(p_monto_estimado, 2) then
    raise exception using errcode = '22023', message = 'Capital estimado invalido';
  end if;
  if p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda invalida';
  end if;
  if v_genero is not null and v_genero not in ('F', 'M') then
    raise exception using errcode = '22023', message = 'Genero invalido';
  end if;
  if v_categoria is not null and v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception using errcode = '22023', message = 'Categoria de interes invalida';
  end if;
  if p_fecha_nacimiento is not null
     and (
       p_fecha_nacimiento < date '1900-01-01'
       or p_fecha_nacimiento > (v_hoy_lima - interval '18 years')::date
     ) then
    raise exception using errcode = '22023', message = 'El lead debe tener al menos 18 anos';
  end if;

  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
  -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
  -- destino operativo activo o dejar el lead en la cola global.
  if v_rol = 'vendedor' then
    if v_vendedor is not null and v_vendedor is distinct from v_actor then
      raise exception using errcode = '42501', message = 'Solo puedes crear leads asignados a ti mismo';
    end if;
    v_vendedor := v_actor;
    v_supervisor := null;
  elsif v_vendedor is null and v_rol = 'supervisor' then
    v_supervisor := v_actor;
  else
    v_supervisor := null;
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  -- La identidad optimista funciona también como llave idempotente: si el
  -- commit llegó pero la respuesta de red se perdió, repetir el MISMO payload
  -- antes de una mutación posterior confirma el alta anterior en vez de
  -- pintarla como un contacto ajeno.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('avancecrm:lead:id:' || v_id::text, 0)
  );
  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);

  -- Un administrador puede desactivar la membresia mientras esta sesion
  -- espera un contacto. El permiso se vuelve a consultar DESPUES de todos
  -- los locks para que una sesion revocada no alcance a insertar al despertar.
  v_rol_actual := private.rol_crm(v_actor);
  if v_rol_actual is distinct from v_rol
     or v_rol_actual not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  select l.* into v_existente
  from crm.leads l
  where l.id = v_id;

  if found then
    if v_existente.creado_por is not distinct from v_actor
       and v_existente.nombre_completo is not distinct from v_nombre
       and v_existente.telefono is not distinct from v_telefono
       -- El segundo numero entra en la comparacion idempotente: sin esto, un
       -- reintento que SOLO cambia el alternativo se confirmaria como «ya
       -- creado» y el dato nuevo se perderia sin decir nada.
       and v_existente.telefono_alternativo is not distinct from v_alt
       and v_existente.correo is not distinct from v_correo
       and v_existente.dni is not distinct from v_dni
       and v_existente.genero is not distinct from v_genero
       and v_existente.fecha_nacimiento is not distinct from p_fecha_nacimiento
       and v_existente.distrito is not distinct from v_distrito
       and v_existente.origen is not distinct from p_origen
       and v_existente.etapa is not distinct from p_etapa
       and v_existente.monto_estimado is not distinct from p_monto_estimado
       and v_existente.moneda is not distinct from p_moneda
       and v_existente.categoria_interes is not distinct from v_categoria
       and v_existente.vendedor_id is not distinct from v_vendedor
       and v_existente.asignado_supervisor_id is not distinct from v_supervisor
       and v_existente.nota is not distinct from v_nota
       and v_existente.activo = true then
      return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
    end if;

    raise exception using
      errcode = '22023',
      message = 'El identificador de esta alta ya fue usado con datos distintos';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    return v_disponibilidad;
  end if;

  insert into crm.leads (
    id,
    nombre_completo,
    telefono,
    telefono_alternativo,
    correo,
    dni,
    genero,
    fecha_nacimiento,
    distrito,
    origen,
    etapa,
    monto_estimado,
    moneda,
    categoria_interes,
    vendedor_id,
    asignado_supervisor_id,
    nota,
    activo,
    creado_por
  ) values (
    v_id,
    v_nombre,
    v_telefono,
    v_alt,
    v_correo,
    v_dni,
    v_genero,
    p_fecha_nacimiento,
    v_distrito,
    p_origen,
    p_etapa,
    p_monto_estimado,
    p_moneda,
    v_categoria,
    v_vendedor,
    v_supervisor,
    v_nota,
    true,
    v_actor
  );

  return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
end;
$function$;

comment on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) is
  'Alta atomica de lead: verifica disponibilidad y crea en la misma transaccion, con llave idempotente por p_id. El telefono PRINCIPAL sigue siendo celular peruano (es la identidad: dedup, reparto y conversion cuelgan de el). Desde 20260826182500 admite p_telefono_alternativo, que acepta celular, fijo peruano o internacional via private.canonizar_contacto y no participa del dedup.';

revoke all on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) from public, anon, service_role;
grant execute on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) to authenticated;

do $postflight$
declare
  v_oid oid := 'crm.crear_lead_si_disponible(text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text)'::regprocedure;
  v_def text := pg_get_functiondef(v_oid);
begin
  -- Que NO haya quedado una SOBRECARGA: dos funciones con este nombre harian
  -- ambigua cada llamada del front y el alta fallaria con un error ilegible.
  if (select count(*) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'crear_lead_si_disponible') <> 1 then
    raise exception 'postflight: quedo mas de una crear_lead_si_disponible (sobrecarga ambigua)';
  end if;
  -- Que el segundo numero se canonice con la REGLA COMPARTIDA y no con un regex
  -- reescrito aqui dentro, que es como los espejos divergen.
  if position('private.canonizar_contacto' in v_def) = 0 then
    raise exception 'postflight: el segundo numero no usa la regla compartida';
  end if;
  -- Que se INSERTE de verdad: declararlo y olvidarlo en el insert es el fallo
  -- exacto que ya mordio en esta familia.
  if position('telefono_alternativo,' in v_def) = 0 or position('v_alt,' in v_def) = 0 then
    raise exception 'postflight: el segundo numero no viaja al insert';
  end if;
  -- Que entre en la comparacion idempotente.
  if position('v_existente.telefono_alternativo is not distinct from v_alt' in v_def) = 0 then
    raise exception 'postflight: el segundo numero queda fuera de la llave idempotente';
  end if;
  -- Que el PRINCIPAL siga siendo celular peruano: la opcion A depende de esto.
  if position('v_telefono !~ ''^\+519[0-9]{8}$''' in v_def) = 0 then
    raise exception 'postflight: el telefono principal dejo de exigir celular peruano';
  end if;
  -- Que sigan las guardias de ambito y admision.
  if position('vendedor_ids_visibles' in v_def) = 0
     or position('bloquear_contactos_lead' in v_def) = 0
     or position('verificar_disponibilidad_lead_impl' in v_def) = 0
     or position('Acceso CRM revocado' in v_def) = 0 then
    raise exception 'postflight: el alta perdio una guardia';
  end if;
  if not (select prosecdef from pg_catalog.pg_proc where oid = v_oid) then
    raise exception 'postflight: el alta dejo de ser SECURITY DEFINER';
  end if;
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'postflight: authenticated perdio el execute';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'postflight: el drop+create abrio el alta a un rol que no la tenia';
  end if;
end;
$postflight$;

commit;
