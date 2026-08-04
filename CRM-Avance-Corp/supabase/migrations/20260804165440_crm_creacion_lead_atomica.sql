-- Creacion atomica de leads (cierre del TOCTOU de P-048).
--
-- La consulta preventiva del formulario sigue siendo util para UX, pero ya no
-- decide el alta. Esta RPC toma candados transaccionales deterministas por
-- telefono/DNI, vuelve a ejecutar P-047 y solo entonces inserta. Un trigger
-- comparte los mismos candados para que clientes web anteriores y escritores
-- internos no corran en paralelo sobre el mismo contacto.
--
-- Frontera consciente: no se altera ningun objeto de `public`. El alta de un
-- cliente del portal, o un cambio de su identidad, que ocurra exactamente en
-- paralelo sigue en esa frontera y se revisara al universalizar portal/CRM.

begin;

set local lock_timeout = '10s';

-- Ordenar TODAS las llaves antes de tomarlas evita ciclos teléfono↔DNI entre
-- dos altas simultaneas. Una colision del hash solo serializa de mas; nunca
-- permite dos escrituras. Los locks se liberan solos al COMMIT/ROLLBACK.
create or replace function private.bloquear_contactos_lead(
  p_telefonos text[],
  p_dnis text[]
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_clave text;
begin
  for v_clave in
    select claves.clave
    from (
      select distinct 'telefono:' || private.normalizar_telefono(t.valor) as clave
      from pg_catalog.unnest(coalesce(p_telefonos, array[]::text[])) as t(valor)
      where nullif(pg_catalog.btrim(coalesce(t.valor, '')), '') is not null

      union

      select distinct 'dni:' || pg_catalog.btrim(d.valor) as clave
      from pg_catalog.unnest(coalesce(p_dnis, array[]::text[])) as d(valor)
      where nullif(pg_catalog.btrim(coalesce(d.valor, '')), '') is not null
    ) as claves
    where claves.clave is not null
    order by claves.clave
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('avancecrm:lead:' || v_clave, 0)
    );
  end loop;
end;
$$;

comment on function private.bloquear_contactos_lead(text[], text[]) is
  'Candados advisory xact, ordenados por teléfono/DNI, para serializar mutaciones de un mismo contacto.';

revoke all on function private.bloquear_contactos_lead(text[], text[])
  from public, anon, authenticated, service_role;

-- Un solo cuerpo P-047, con exclusión opcional para validar una edición sin
-- que el propio lead se detecte como `tomado`. La firma histórica de dos
-- argumentos queda como wrapper y conserva exactamente el contrato público.
create or replace function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text,
  p_excluir_lead_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  if exists (
    select 1
    from crm.leads l
    where l.id is distinct from p_excluir_lead_id
      and l.no_contactar = true
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  ) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;

  select per.id, asesor.nombre_completo as asesor_nombre
  into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  select
    l.tenencia_desde,
    l.vendedor_id,
    l.asignado_supervisor_id,
    coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
  into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.id is distinct from p_excluir_lead_id
    and l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
    end if;
    return pg_catalog.jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde
    );
  end if;

  select
    l.motivo_descarte,
    l.descartado_en,
    pd.nombre_completo as descartado_por_nombre
  into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.id is distinct from p_excluir_lead_id
    and l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias
    into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return pg_catalog.jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;
  end if;

  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$$;

comment on function private.verificar_disponibilidad_lead_impl(text, text, uuid) is
  'Cuerpo canónico P-047 con exclusión opcional del lead que se está editando.';

revoke all on function private.verificar_disponibilidad_lead_impl(text, text, uuid)
  from public, anon, authenticated, service_role;

create or replace function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.verificar_disponibilidad_lead_impl(
    p_telefono,
    p_dni,
    null::uuid
  );
$$;

comment on function private.verificar_disponibilidad_lead_impl(text, text) is
  'Wrapper P-047 histórico; delega al único cuerpo canónico sin excluir lead.';

revoke all on function private.verificar_disponibilidad_lead_impl(text, text)
  from public, anon, authenticated, service_role;

-- Segunda malla. En INSERT normaliza y bloquea para TODOS los escritores. Para
-- una sesion humana CRM tambien ejecuta el veredicto P-047 dentro del mismo
-- statement; service_role conserva el importador especializado y sus reglas.
-- En UPDATE toma las llaves vieja+nueva para coordinar descartes/No contactar.
-- Una sesión humana no puede mudar la identidad de una fila que porta un veto
-- propio vigente; para el resto aplica P-047 excluyendo la fila editada, de
-- modo que corregir un dato no se confunda con duplicarse a sí misma.
create or replace function private.trg_leads_disponibilidad_atomica()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_disponibilidad jsonb;
  v_cambio_identidad boolean;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_descartado_por text;
begin
  if tg_op = 'UPDATE' then
    if new.telefono is distinct from old.telefono then
      new.telefono := private.normalizar_telefono(new.telefono);
      if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'Telefono invalido';
      end if;
    end if;

    if new.dni is distinct from old.dni then
      new.dni := nullif(pg_catalog.btrim(new.dni), '');
      if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'DNI invalido';
      end if;
    end if;

    v_cambio_identidad := new.telefono is distinct from old.telefono
      or new.dni is distinct from old.dni;

    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono],
      array[old.dni, new.dni]
    );

    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;

    v_rol := private.rol_crm(v_actor);
    if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
      raise exception using errcode = '42501', message = 'Acceso CRM revocado';
    end if;

    -- Excluir OLD al validar el destino es correcto para un lead operativo,
    -- pero no debe permitir «mover» un No contactar o un enfriamiento y dejar
    -- libre la identidad anterior. Ambos vetos propios congelan teléfono y DNI
    -- mientras sigan vigentes; levantarlos es una operación separada y auditable.
    if old.no_contactar = true then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = pg_catalog.jsonb_build_object('estado', 'no_contactar')::text;
    end if;

    if old.etapa = 'descartado'
       and old.descartado_en is not null
       and old.motivo_descarte is not null then
      select
        ep.dias,
        old.descartado_en + pg_catalog.make_interval(days => ep.dias),
        p.nombre_completo
      into v_dias, v_disponible_desde, v_descartado_por
      from crm.enfriamiento_politica ep
      left join public.perfiles p on p.id = old.descartado_por
      where ep.motivo = old.motivo_descarte;

      if coalesce(v_dias, 0) > 0
         and v_disponible_desde > pg_catalog.now() then
        raise exception using
          errcode = 'P0481',
          message = 'Contacto no disponible',
          detail = pg_catalog.jsonb_build_object(
            'estado', 'enfriamiento',
            'motivo_descarte', old.motivo_descarte,
            'disponible_desde', v_disponible_desde,
            'descartado_por', v_descartado_por
          )::text;
      end if;
    end if;

    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    return new;
  end if;

  new.telefono := private.normalizar_telefono(new.telefono);
  new.dni := nullif(pg_catalog.btrim(new.dni), '');

  if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'Telefono invalido';
  end if;
  if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'DNI invalido';
  end if;

  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);

  -- Un escritor interno sin sesion humana se serializa, pero conserva su
  -- contrato especializado (por ejemplo crm-importar-leads con service_role).
  if v_actor is null then
    return new;
  end if;

  v_rol := private.rol_crm(v_actor);
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La compatibilidad temporal es solo para el alta que ya hacía el bundle
  -- anterior. No abre una vía para fabricar leads terminales o inactivos.
  if new.activo is distinct from true
     or new.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead debe nacer activo y en etapa operativa';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  return new;
end;
$$;

comment on function private.trg_leads_disponibilidad_atomica() is
  'Serializa contactos, preserva vetos propios y aplica P-047 a INSERT humanos y cambios de identidad.';

revoke all on function private.trg_leads_disponibilidad_atomica()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_00_disponibilidad_insert on crm.leads;
create trigger trg_leads_00_disponibilidad_insert
before insert on crm.leads
for each row execute function private.trg_leads_disponibilidad_atomica();

drop trigger if exists trg_leads_00_disponibilidad_update on crm.leads;
create trigger trg_leads_00_disponibilidad_update
before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte on crm.leads
for each row execute function private.trg_leads_disponibilidad_atomica();

-- API de alta. Es SECURITY DEFINER porque necesita leer estados globales que
-- RLS oculta; por eso replica de forma explícita el gate y el alcance de
-- leads_insert, deriva creado_por y nunca acepta flags legales/terminales.
create or replace function crm.crear_lead_si_disponible(
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
  p_nota text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_rol_actual text;
  v_id uuid := coalesce(p_id, pg_catalog.gen_random_uuid());
  v_nombre text := nullif(pg_catalog.btrim(p_nombre_completo), '');
  v_telefono text := private.normalizar_telefono(p_telefono);
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
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  if p_origen not in ('referido', 'landing', 'formulario', 'oficina', 'otro', 'web', 'campania', 'whatsapp') then
    raise exception using errcode = '22023', message = 'Origen invalido';
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
$$;

comment on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text
) is
  'Alta P-048 atomica: serializa telefono/DNI, revalida no contactar/cliente/vivo/enfriamiento y crea el lead en la misma transaccion.';

revoke all on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text
) from public, anon, service_role;

grant execute on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text
) to authenticated;

-- Despliegue sin corte: `authenticated` conserva por ahora el INSERT directo
-- que usa el bundle anterior, pero el trigger de arriba lo somete al mismo
-- veredicto y a los mismos locks. Tras verificar adopción de la RPC, una
-- migración separada retirará grants de tabla/columna y la policy leads_insert.

commit;
