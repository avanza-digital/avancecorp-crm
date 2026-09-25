-- P-0XX / S2: escritura bancaria versionada desde CRM y portal.
-- La copia en public.perfiles queda como legado de solo lectura.
begin;
set local lock_timeout = '10s';

do $origen$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'crm.cuentas_bancarias'::pg_catalog.regclass
      and c.conname = 'cuentas_bancarias_origen_valido'
      and pg_catalog.strpos(pg_catalog.pg_get_constraintdef(c.oid), 'portal') > 0
  ) then
    alter table crm.cuentas_bancarias
      drop constraint if exists cuentas_bancarias_origen_valido;
    alter table crm.cuentas_bancarias
      add constraint cuentas_bancarias_origen_valido
      check (origen in ('perfil', 'contrato', 'portal'));
  end if;
end;
$origen$;

-- Hecho sin autorizacion: conserva la version antigua para contratos ya
-- vinculados. El wrapper toma antes el mismo advisory lock que el alta CRM.
create or replace function private.registrar_cuenta_cliente_hecho(
  p_cliente_id uuid, p_moneda text, p_normalizada jsonb, p_actor uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actual crm.cuentas_bancarias%rowtype;
  v_id uuid;
  v_cci text := p_normalizada->>'cci';
begin
  select cb.* into v_actual
  from crm.cuentas_bancarias cb
  where cb.cliente_id = p_cliente_id and cb.moneda = p_moneda
    and cb.cci = v_cci and cb.activa is true
  for update;

  if found
     and pg_catalog.lower(v_actual.banco) = pg_catalog.lower(p_normalizada->>'banco')
     and v_actual.tipo_cuenta = p_normalizada->>'tipo_cuenta'
     and v_actual.numero_cuenta = p_normalizada->>'numero_cuenta'
     and v_actual.titular_distinto = (p_normalizada->>'titular_distinto')::boolean
     and v_actual.beneficiario_nombre is not distinct from p_normalizada->>'beneficiario_nombre'
     and v_actual.beneficiario_dni is not distinct from p_normalizada->>'beneficiario_dni' then
    return v_actual.id;
  end if;

  if found then
    update crm.cuentas_bancarias
       set activa = false,
           desactivada_por = p_actor,
           desactivada_en = pg_catalog.clock_timestamp()
     where id = v_actual.id;
  end if;

  insert into crm.cuentas_bancarias
    (cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
     titular_distinto, beneficiario_nombre, beneficiario_dni,
     activa, origen, creado_por, creado_en)
  values
    (p_cliente_id, p_moneda, p_normalizada->>'banco',
     p_normalizada->>'tipo_cuenta', p_normalizada->>'numero_cuenta', v_cci,
     (p_normalizada->>'titular_distinto')::boolean,
     p_normalizada->>'beneficiario_nombre', p_normalizada->>'beneficiario_dni',
     true, 'portal', p_actor, pg_catalog.clock_timestamp())
  returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function private.registrar_cuenta_cliente_hecho(uuid,text,jsonb,uuid)
  from public, anon, authenticated;

-- Wrapper de autorizacion. El UPDATE historico de perfiles limita la
-- correccion del analista a cinco horas; se conserva ese alcance al migrar.
create or replace function private.registrar_cuenta_cliente_autorizado(
  p_cliente_id uuid, p_cuenta jsonb)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_cliente public.perfiles%rowtype;
  v_moneda text;
  v_normalizada jsonb;
  v_cci text;
begin
  if p_cliente_id is null
     or not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  select p.* into v_cliente
  from public.perfiles p
  where p.id = p_cliente_id and p.rol = 'cliente' and p.activo is true
  for share;
  if not found then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if not (select public.es_gestor_cartera())
     and private.rol_crm(v_actor) is distinct from 'gerencia'
     and not (
       (select private.es_analista_vigente())
       and v_cliente.creado_en > pg_catalog.now() - interval '5 hours'
       and (v_cliente.creado_por = v_actor
            or v_cliente.asesor_perfil_id = v_actor)
     ) then
    raise exception using errcode = '42501',
      message = 'La correccion bancaria requiere Gerencia o un cliente en tu plazo de correccion';
  end if;

  if p_cuenta is null or pg_catalog.jsonb_typeof(p_cuenta) <> 'object' then
    raise exception using errcode = '22023', message = 'Datos bancarios invalidos';
  end if;
  v_moneda := pg_catalog.upper(pg_catalog.btrim(coalesce(p_cuenta->>'moneda', '')));
  if v_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda bancaria invalida';
  end if;
  v_normalizada := private.validar_cuenta_bancaria(p_cuenta);
  v_cci := v_normalizada->>'cci';

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_cliente_id::text || '|' || v_moneda || '|' || v_cci, 0));
  if not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  return private.registrar_cuenta_cliente_hecho(
    p_cliente_id, v_moneda, v_normalizada, v_actor);
end;
$function$;
revoke all on function private.registrar_cuenta_cliente_autorizado(uuid,jsonb)
  from public, anon, authenticated;

-- Wrapper de pantalla compartido por CRM y miavance.com.
create or replace function crm.registrar_cuenta_cliente(
  p_cliente_id uuid, p_cuenta jsonb)
returns uuid
language sql
security definer
set search_path to ''
as $function$
  select private.registrar_cuenta_cliente_autorizado(p_cliente_id, p_cuenta);
$function$;
revoke all on function crm.registrar_cuenta_cliente(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function crm.registrar_cuenta_cliente(uuid,jsonb)
  to authenticated;

-- Alta de perfil y cuentas en UNA transaccion. Solo las Edge Functions con
-- service_role usan esta puerta, tras comprobar el JWT del operador. Los datos
-- del actor se conservan en creado_por y en la auditoria del ledger.
create or replace function private.crear_perfil_cliente_con_cuentas_hecho(
  p_perfil jsonb, p_cuentas jsonb, p_actor_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid := (p_perfil->>'id')::uuid;
  v_existente public.perfiles%rowtype;
  v_ya_existia boolean := false;
  v_cuenta jsonb;
  v_normalizada jsonb;
  v_moneda text;
  v_cci text;
begin
  select p.* into v_existente
  -- Compatible con FOR SHARE de crear_contrato y registrar_cuenta: ambas
  -- rutas toman luego el advisory de cuenta. FOR UPDATE aqui invertia el
  -- orden de espera durante una reanudacion del alta.
  from public.perfiles p where p.id = v_id for share;
  v_ya_existia := found;
  if v_ya_existia then
    if v_existente.rol is distinct from 'cliente'
       or pg_catalog.lower(v_existente.correo) is distinct from
          pg_catalog.lower(p_perfil->>'correo')
       or v_existente.tipo_documento is distinct from p_perfil->>'tipo_documento'
       or v_existente.dni is distinct from p_perfil->>'dni' then
      raise exception using errcode = '23505',
        message = 'El perfil existente no coincide con el alta';
    end if;
  else
    insert into public.perfiles (
      id, nombre_completo, apellidos, nombres, tipo_documento, dni,
      telefono, domicilio, correo, rol, activo, creado_por,
      debe_cambiar_password, asesor_perfil_id)
    values (
      v_id, p_perfil->>'nombre_completo', p_perfil->>'apellidos',
      p_perfil->>'nombres', p_perfil->>'tipo_documento', p_perfil->>'dni',
      p_perfil->>'telefono', p_perfil->>'domicilio', p_perfil->>'correo',
      'cliente', true, p_actor_id,
      coalesce((p_perfil->>'debe_cambiar_password')::boolean, false),
      (p_perfil->>'asesor_perfil_id')::uuid);
  end if;

  -- PEN antes que USD en todas las reanudaciones, independientemente del orden
  -- del JSON. La cuenta se examina despues de su advisory, no antes.
  for v_cuenta in
    select x.value from pg_catalog.jsonb_array_elements(p_cuentas) x
    order by pg_catalog.upper(pg_catalog.btrim(x.value->>'moneda'))
  loop
    v_moneda := pg_catalog.upper(pg_catalog.btrim(v_cuenta->>'moneda'));
    v_normalizada := private.validar_cuenta_bancaria(v_cuenta);
    v_cci := v_normalizada->>'cci';
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_id::text || '|' || v_moneda || '|' || v_cci, 0));
    -- Reanudar exige la cuenta original activa y unica. Si fue desactivada,
    -- no se resucita una instruccion de pago historica por un retry tardio.
    if v_ya_existia then
      if (select pg_catalog.count(*) from crm.cuentas_bancarias cb
          where cb.cliente_id = v_id and cb.moneda = v_moneda and cb.activa) <> 1
         or not exists (
           select 1 from crm.cuentas_bancarias cb
           where cb.cliente_id = v_id and cb.moneda = v_moneda and cb.activa
             and cb.cci = v_cci
             and pg_catalog.lower(cb.banco) = pg_catalog.lower(v_normalizada->>'banco')
             and cb.tipo_cuenta = v_normalizada->>'tipo_cuenta'
             and cb.numero_cuenta = v_normalizada->>'numero_cuenta'
             and cb.titular_distinto = (v_normalizada->>'titular_distinto')::boolean
             and cb.beneficiario_nombre is not distinct from v_normalizada->>'beneficiario_nombre'
             and cb.beneficiario_dni is not distinct from v_normalizada->>'beneficiario_dni'
         ) then
        raise exception using errcode = 'P0409',
          message = 'La cuenta del alta cambio; requiere conciliacion';
      end if;
      continue;
    end if;
    perform private.registrar_cuenta_cliente_hecho(
      v_id, v_moneda, v_normalizada, p_actor_id);
  end loop;
  return v_id;
end;
$function$;
revoke all on function private.crear_perfil_cliente_con_cuentas_hecho(jsonb,jsonb,uuid)
  from public, anon, authenticated, service_role;

create or replace function private.crear_perfil_cliente_con_cuentas_autorizado(
  p_perfil jsonb, p_cuentas jsonb, p_actor_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
  v_cuenta jsonb;
  v_moneda text;
  v_monedas text[] := '{}';
begin
  if (select auth.role()) is distinct from 'service_role'
     or p_actor_id is null
     or not exists (
       select 1 from public.perfiles p
       where p.id = p_actor_id and p.activo is true
         and not exists (
           select 1 from crm.equipo e
           where e.perfil_id = p_actor_id and e.activo is false)
         and (p.rol in ('admin', 'superadmin', 'analista', 'operaciones')
              or private.rol_crm(p_actor_id) in ('vendedor','supervisor','gerencia'))) then
    raise exception using errcode = '42501', message = 'Operador no autorizado';
  end if;
  if p_perfil is null or pg_catalog.jsonb_typeof(p_perfil) <> 'object'
     or p_cuentas is null or pg_catalog.jsonb_typeof(p_cuentas) <> 'array'
     or pg_catalog.jsonb_array_length(p_cuentas) not between 1 and 2
     or p_perfil - array[
       'id','nombre_completo','apellidos','nombres','tipo_documento','dni',
       'telefono','domicilio','correo','debe_cambiar_password',
       'asesor_perfil_id']::text[] <> '{}'::jsonb then
    raise exception using errcode = '22023', message = 'Datos de alta invalidos';
  end if;
  begin
    v_id := (p_perfil->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Cliente invalido';
  end;
  if v_id is null or pg_catalog.btrim(coalesce(p_perfil->>'nombre_completo', '')) = ''
     or pg_catalog.btrim(coalesce(p_perfil->>'correo', '')) = ''
     or coalesce(p_perfil->>'tipo_documento', '') not in ('DNI','CE','PASAPORTE')
     or not exists (
       select 1 from auth.users u
       where u.id = v_id
         and pg_catalog.lower(u.email) = pg_catalog.lower(p_perfil->>'correo')) then
    raise exception using errcode = '22023', message = 'Identidad de alta invalida';
  end if;
  for v_cuenta in select x.value from pg_catalog.jsonb_array_elements(p_cuentas) x
  loop
    if pg_catalog.jsonb_typeof(v_cuenta) <> 'object' then
      raise exception using errcode = '22023', message = 'Cuenta bancaria invalida';
    end if;
    v_moneda := pg_catalog.upper(pg_catalog.btrim(coalesce(v_cuenta->>'moneda', '')));
    if v_moneda not in ('PEN','USD') or v_moneda = any(v_monedas) then
      raise exception using errcode = '22023', message = 'Moneda bancaria repetida o invalida';
    end if;
    v_monedas := pg_catalog.array_append(v_monedas, v_moneda);
    perform private.validar_cuenta_bancaria(v_cuenta);
  end loop;
  return private.crear_perfil_cliente_con_cuentas_hecho(
    p_perfil, p_cuentas, p_actor_id);
end;
$function$;
revoke all on function private.crear_perfil_cliente_con_cuentas_autorizado(jsonb,jsonb,uuid)
  from public, anon, authenticated, service_role;

create or replace function crm.crear_perfil_cliente_con_cuentas(
  p_perfil jsonb, p_cuentas jsonb, p_actor_id uuid)
returns uuid
language sql
security definer
set search_path to ''
as $function$
  select private.crear_perfil_cliente_con_cuentas_autorizado(
    p_perfil, p_cuentas, p_actor_id);
$function$;
revoke all on function crm.crear_perfil_cliente_con_cuentas(jsonb,jsonb,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.crear_perfil_cliente_con_cuentas(jsonb,jsonb,uuid)
  to service_role;

-- El trigger nuevo corre antes de trg_perfiles_cuentas_no_vaciar por nombre.
-- No se elimina ese trigger legado. Cualquier valor bancario nuevo de cliente
-- se rechaza, incluidos INSERT de clientes y UPDATE directos con service_role.
create or replace function private.trg_perfiles_banca_solo_lectura()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_claves text[] := array[
    'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
    'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
    'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
    'titular_distinto_usd', 'beneficiario_nombre_usd', 'beneficiario_dni_usd'];
  v_tiene_banca boolean;
begin
  if tg_op = 'INSERT' then
    if new.rol = 'cliente' then
      select exists (
        select 1 from pg_catalog.jsonb_each(pg_catalog.to_jsonb(new)) as x(k,v)
        where k = any(v_claves)
          and v <> 'null'::jsonb
          and (k not in ('titular_distinto','titular_distinto_usd')
               or v <> 'false'::jsonb)
      ) into v_tiene_banca;
      if v_tiene_banca then
        raise exception using errcode = '22023',
          message = 'Los datos bancarios del cliente se registran en cuentas_bancarias';
      end if;
    end if;
    return new;
  end if;

  if old.rol = 'cliente' or new.rol = 'cliente' then
    if exists (
      select 1 from pg_catalog.unnest(v_claves) as x(k)
      where pg_catalog.to_jsonb(old)->k is distinct from pg_catalog.to_jsonb(new)->k
    ) then
      raise exception using errcode = '22023',
        message = 'Las columnas bancarias de perfiles son de solo lectura';
    end if;
    if old.rol is distinct from 'cliente' and new.rol = 'cliente' then
      select exists (
        select 1 from pg_catalog.jsonb_each(pg_catalog.to_jsonb(new)) as x(k,v)
        where k = any(v_claves)
          and v <> 'null'::jsonb
          and (k not in ('titular_distinto','titular_distinto_usd')
               or v <> 'false'::jsonb)
      ) into v_tiene_banca;
      if v_tiene_banca then
        raise exception using errcode = '22023',
          message = 'Los datos bancarios del cliente se registran en cuentas_bancarias';
      end if;
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_perfiles_banca_solo_lectura()
  from public, anon, authenticated;
drop trigger if exists trg_perfiles_banca_solo_lectura on public.perfiles;
create trigger trg_perfiles_banca_solo_lectura
before insert or update of
  banco, tipo_cuenta, numero_cuenta, cci,
  titular_distinto, beneficiario_nombre, beneficiario_dni,
  banco_usd, tipo_cuenta_usd, numero_cuenta_usd, cci_usd,
  titular_distinto_usd, beneficiario_nombre_usd, beneficiario_dni_usd, rol
on public.perfiles
for each row execute function private.trg_perfiles_banca_solo_lectura();

-- La comparacion de la fotografia del modo perfil permanece antes de la
-- validacion compartida. Las ACL de esta funcion interna no cambian.
-- F7 mantiene esta puerta cerrada por huella. Antes de recrearla, se exige
-- exactamente el cuerpo vivo de produccion (o este mismo cuerpo en un replay).
-- La rama recuperada conserva la huella declarada original 0de7... aunque el
-- cuerpo vivo ya era el de produccion 802c...; ambos estados se reconocen,
-- pero nunca se acepta un cuerpo vivo distinto ni un ACL abierto.
do $f7_pre$
declare
  v_firma constant text := 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)';
  v_cuerpo text;
  v_definicion text;
  v_acl text;
  v_dueno text;
  v_fila private.f7_piezas_en_observacion%rowtype;
begin
  select pg_catalog.md5(p.prosrc),
         pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)),
         p.proacl::text, pg_catalog.pg_get_userbyid(p.proowner)
    into v_cuerpo, v_definicion, v_acl, v_dueno
  from pg_catalog.pg_proc p
  where p.oid = v_firma::pg_catalog.regprocedure;
  select * into v_fila from private.f7_piezas_en_observacion f
    where f.firma = v_firma;
  if v_cuerpo is null or not found
     or (v_cuerpo, v_definicion) not in (
       ('802c0318fd3ec5636e174b4f98b3c965', 'e52e632b340992c18d09e8aad18ed67e'),
       ('22ec068ff5d27312c5eb0749600292fd', '4799e4c15faaddafae4afc4852944680'))
     or v_acl is distinct from '{postgres=X/postgres}'
     or v_dueno is distinct from 'postgres'
     or v_fila.estado is distinct from 'cerrada_permanente'
     or v_fila.ola is distinct from 'F7.1'
     or v_fila.acl_esperada is distinct from v_acl
     or v_fila.huella_md5 not in (
       '0de7a130ae366cde54035e2c50f213e2',
       '802c0318fd3ec5636e174b4f98b3c965',
       '22ec068ff5d27312c5eb0749600292fd') then
    raise exception 'P-0XX S2: la puerta F7 de contratos no coincide con la base auditada';
  end if;
end;
$f7_pre$;

CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid                  uuid := (select auth.uid());
  v_cliente_id           uuid;
  v_moneda               text;
  v_tipo_seleccion       text;
  v_cuenta_id            uuid;
  v_cuenta_activa        crm.cuentas_bancarias%rowtype;
  v_banco                text;
  v_tipo_cuenta          text;
  v_numero_cuenta        text;
  v_cci                  text;
  v_titular_distinto     boolean := false;
  v_beneficiario_nombre  text;
  v_beneficiario_dni     text;
  v_cuenta_esperada      jsonb;
  v_cuenta_normalizada   jsonb;
  v_origen               text;
  v_resultado            jsonb;
  v_contrato_id          uuid;
begin
  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception using errcode = '22023', message = 'Faltan los datos del contrato';
  end if;
  if p_cuenta is null or jsonb_typeof(p_cuenta) <> 'object' then
    raise exception using errcode = '22023', message = 'Selecciona la cuenta para el pago de intereses';
  end if;

  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Cliente invalido';
  end;
  v_moneda := upper(btrim(coalesce(p_contrato->>'moneda', '')));
  if v_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda del contrato invalida';
  end if;
  if not (select private.puede_registrar_ventas()) then
    raise exception using errcode = '42501', message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  -- F2.b (E4) [Codex B-2]: la prepuerta de reconocimiento (jerarquía -> documento -> identidad -> perfil) va ANTES
  -- de los locks de cuenta/perfil de este wrapper, con el mismo orden que public.crear_contrato (reentrante allí).
  -- Después del 42501 de arriba: la precedencia para un no autorizado no cambia.
  if private.resolver_en_puertas_bajo_candado()
     and exists (select 1 from public.perfiles p where p.id = v_cliente_id and p.rol = 'cliente' and p.activo) then
    perform private.asegurar_identidad_perfil(v_cliente_id, 'contrato');
  end if;
  v_tipo_seleccion := lower(btrim(coalesce(p_cuenta->>'tipo', '')));

  if v_tipo_seleccion = 'existente' then
    begin
      v_cuenta_id := (p_cuenta->>'cuenta_id')::uuid;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'Cuenta bancaria invalida';
    end;

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.id = v_cuenta_id
      and cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.activa = true
    for share;
    if not found then
      raise exception using
        errcode = '22023',
        message = 'La cuenta bancaria no esta disponible para este cliente y moneda';
    end if;

  elsif v_tipo_seleccion in ('perfil', 'nueva') then
    if v_tipo_seleccion = 'perfil' then
      select
        btrim(case when v_moneda = 'USD' then p.banco_usd else p.banco end),
        lower(btrim(case when v_moneda = 'USD' then p.tipo_cuenta_usd else p.tipo_cuenta end)),
        upper(btrim(case when v_moneda = 'USD' then p.numero_cuenta_usd else p.numero_cuenta end)),
        btrim(case when v_moneda = 'USD' then p.cci_usd else p.cci end),
        case when v_moneda = 'USD' then p.titular_distinto_usd else p.titular_distinto end,
        case when v_moneda = 'USD' then p.beneficiario_nombre_usd else p.beneficiario_nombre end,
        case when v_moneda = 'USD' then p.beneficiario_dni_usd else p.beneficiario_dni end
      into v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
           v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni
      from public.perfiles p
      where p.id = v_cliente_id
      -- La fotografia del perfil debe seguir siendo cierta hasta que termine
      -- el alta. Sin este lock, un UPDATE concurrente podia confirmar despues
      -- del SELECT y antes de crear el vinculo contractual.
      for share;
      v_origen := 'perfil';
    else
      v_banco := btrim(coalesce(p_cuenta->>'banco', ''));
      v_tipo_cuenta := lower(btrim(coalesce(p_cuenta->>'tipo_cuenta', '')));
      v_numero_cuenta := upper(btrim(coalesce(p_cuenta->>'numero_cuenta', '')));
      v_cci := btrim(coalesce(p_cuenta->>'cci', ''));
      begin
        v_titular_distinto := coalesce((p_cuenta->>'titular_distinto')::boolean, false);
      exception when invalid_text_representation then
        raise exception using errcode = '22023', message = 'Indicador de beneficiario invalido';
      end;
      v_beneficiario_nombre := p_cuenta->>'beneficiario_nombre';
      v_beneficiario_dni := p_cuenta->>'beneficiario_dni';
      v_origen := 'contrato';
    end if;

    v_banco := btrim(coalesce(v_banco, ''));
    v_tipo_cuenta := lower(btrim(coalesce(v_tipo_cuenta, '')));
    v_numero_cuenta := upper(btrim(coalesce(v_numero_cuenta, '')));
    v_cci := btrim(coalesce(v_cci, ''));
    if v_titular_distinto then
      v_beneficiario_nombre := upper(regexp_replace(btrim(coalesce(v_beneficiario_nombre, '')), '\s+', ' ', 'g'));
      v_beneficiario_dni := btrim(coalesce(v_beneficiario_dni, ''));
    else
      v_beneficiario_nombre := null;
      v_beneficiario_dni := null;
    end if;

    if v_tipo_seleccion = 'perfil' then
      v_cuenta_esperada := jsonb_build_object(
        'banco', v_banco,
        'tipo_cuenta', v_tipo_cuenta,
        'numero_cuenta', v_numero_cuenta,
        'cci', v_cci,
        'titular_distinto', v_titular_distinto,
        'beneficiario_nombre', v_beneficiario_nombre,
        'beneficiario_dni', v_beneficiario_dni
      );
      if jsonb_typeof(p_cuenta->'cuenta_esperada') is distinct from 'object'
         or (p_cuenta->'cuenta_esperada') is distinct from v_cuenta_esperada then
        raise exception using
          errcode = 'P0001',
          message = 'La cuenta actual del cliente cambio. Recarga las cuentas y vuelve a seleccionarla';
      end if;
    end if;

    v_cuenta_normalizada := private.validar_cuenta_bancaria(
      pg_catalog.jsonb_build_object(
        'banco', v_banco, 'tipo_cuenta', v_tipo_cuenta,
        'numero_cuenta', v_numero_cuenta, 'cci', v_cci,
        'titular_distinto', coalesce(v_titular_distinto, false),
        'beneficiario_nombre', v_beneficiario_nombre,
        'beneficiario_dni', v_beneficiario_dni));
    v_banco := v_cuenta_normalizada->>'banco';
    v_tipo_cuenta := v_cuenta_normalizada->>'tipo_cuenta';
    v_numero_cuenta := v_cuenta_normalizada->>'numero_cuenta';
    v_cci := v_cuenta_normalizada->>'cci';
    v_titular_distinto := (v_cuenta_normalizada->>'titular_distinto')::boolean;
    v_beneficiario_nombre := v_cuenta_normalizada->>'beneficiario_nombre';
    v_beneficiario_dni := v_cuenta_normalizada->>'beneficiario_dni';

    -- Serializa dos altas simultaneas del mismo CCI sin bloquear otras cuentas.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_cliente_id::text || '|' || v_moneda || '|' || v_cci, 0)
    );

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.cci = v_cci
      and cb.activa = true
    for update;

    if found
       and lower(v_cuenta_activa.banco) = lower(v_banco)
       and v_cuenta_activa.tipo_cuenta = v_tipo_cuenta
       and v_cuenta_activa.numero_cuenta = v_numero_cuenta
       and v_cuenta_activa.titular_distinto = v_titular_distinto
       and v_cuenta_activa.beneficiario_nombre is not distinct from v_beneficiario_nombre
       and v_cuenta_activa.beneficiario_dni is not distinct from v_beneficiario_dni then
      v_cuenta_id := v_cuenta_activa.id;
    else
      if found then
        update crm.cuentas_bancarias
           set activa = false,
               desactivada_por = v_uid,
               desactivada_en = now()
         where id = v_cuenta_activa.id;
      end if;

      insert into crm.cuentas_bancarias (
        cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
        titular_distinto, beneficiario_nombre, beneficiario_dni,
        activa, origen, creado_por
      ) values (
        v_cliente_id, v_moneda, v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
        v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni,
        true, v_origen, v_uid
      )
      returning id into v_cuenta_id;
    end if;
  else
    raise exception using
      errcode = '22023',
      message = 'Selecciona una cuenta existente o registra una cuenta nueva';
  end if;

  -- public.crear_contrato mantiene su validacion de rol/cartera, numeracion,
  -- contrato, cronograma y co-titulares. La llamada anidada participa de ESTA
  -- transaccion: si el enlace bancario falla, todo (incluida una cuenta nueva)
  -- se revierte.
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador valido';
  end;
  if v_contrato_id is null then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador';
  end if;

  insert into crm.contrato_cuentas_pago (
    contrato_id, cuenta_bancaria_id, creado_por
  ) values (
    v_contrato_id, v_cuenta_id, v_uid
  );

  return v_resultado || jsonb_build_object('cuenta_bancaria_id', v_cuenta_id);
end;
$function$;

-- Actualizar el retrato F7 en la misma transaccion que el cuerpo. La tabla
-- impide reescrituras ordinarias: el candado nombrado se baja solo aqui y se
-- reactiva antes de confirmar. El replay no agrega una segunda nota.
alter table private.f7_piezas_en_observacion
  disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set huella_md5 = '22ec068ff5d27312c5eb0749600292fd',
       nota = coalesce(nota, '') || E'\nP-0XX S2: huella re-declarada el '
              || pg_catalog.to_char((pg_catalog.now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || ' tras extraer private.validar_cuenta_bancaria; firma, ACL y caller PDF intactos.'
 where firma = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'
   and huella_md5 in (
     '0de7a130ae366cde54035e2c50f213e2',
     '802c0318fd3ec5636e174b4f98b3c965');
alter table private.f7_piezas_en_observacion
  enable trigger trg_f7_obs_00_solo_crece;
do $f7_post$
declare
  v_resultado text;
  v_mordio boolean := false;
  v_mensaje text;
begin
  if (select f.huella_md5 from private.f7_piezas_en_observacion f
      where f.firma = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)')
       is distinct from '22ec068ff5d27312c5eb0749600292fd'
     or (
       select count(*) from pg_catalog.pg_trigger t
       where t.tgrelid = 'private.f7_piezas_en_observacion'::pg_catalog.regclass
         and t.tgname in (
           'trg_f7_obs_00_solo_crece',
           'trg_f7_obs_01_no_borrar',
           'trg_f7_obs_02_no_truncar')
         and t.tgenabled = 'O') <> 3 then
    raise exception 'P-0XX S2: la huella F7 o sus candados no quedaron activos';
  end if;
  select private.assert_f7_piezas_cerradas() into v_resultado;
  if v_resultado is null or v_resultado not like 'OK:%' then
    raise exception 'P-0XX S2: la vigilancia F7 no quedo en verde';
  end if;
  begin
    update private.f7_piezas_en_observacion
       set acl_esperada = acl_esperada || ' '
     where firma = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)';
  exception when insufficient_privilege then
    get stacked diagnostics v_mensaje = message_text;
    v_mordio := v_mensaje like '%no se reescribe%';
  end;
  if not v_mordio then
    raise exception 'P-0XX S2: el candado F7 no rechazo una reescritura';
  end if;
end;
$f7_post$;

-- Gerencia conserva identidad/contacto y rechaza con error claro el banco.
-- El UPDATE deja de asignar las 14 columnas, incluso con patch sin banca.
CREATE OR REPLACE FUNCTION crm.actualizar_cliente_gerencia(p_cliente_id uuid, p_patch jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cliente public.perfiles%rowtype;
begin
  if private.rol_crm((select auth.uid())) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede corregir clientes fuera de cartera'
      using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Los datos del cliente son invalidos'
      using errcode = '22023';
  end if;
  if p_patch ?| array[
    'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
    'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
    'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
    'titular_distinto_usd', 'beneficiario_nombre_usd',
    'beneficiario_dni_usd'] then
    raise exception 'Los datos bancarios se guardan con registrar_cuenta_cliente'
      using errcode = '22023';
  end if;
  if (
    p_patch - array[
      'nombre_completo', 'nombres', 'apellidos', 'tipo_documento',
      'dni', 'telefono',
      'actualizado_en'
    ]::text[]
  ) <> '{}'::jsonb then
    raise exception 'El formulario intento modificar campos no permitidos'
      using errcode = '22023';
  end if;

  select *
    into v_cliente
  from public.perfiles
  where id = p_cliente_id
    and rol = 'cliente'
  for update;
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  -- F2.b (b3): el documento de un cliente ENLAZADO a una identidad solo cambia por la
  -- corrección de documento de Gerencia (b5), que realinea identificador, perfil y lead.
  if (p_patch ? 'dni' or p_patch ? 'tipo_documento')
     and private.resolver_en_puertas_bajo_candado()
     and exists (select 1 from crm.inversionistas i where i.perfil_id = p_cliente_id and i.estado <> 'fusionado')
     and ((p_patch ? 'dni' and p_patch->>'dni' is distinct from v_cliente.dni)
          or (p_patch ? 'tipo_documento' and p_patch->>'tipo_documento' is distinct from v_cliente.tipo_documento)) then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige por la corrección de documento (Gerencia)'
      using errcode = 'P0409';
  end if;

  update public.perfiles
     set nombre_completo = case
           when p_patch ? 'nombre_completo'
             then p_patch->>'nombre_completo'
           else nombre_completo
         end,
         nombres = case
           when p_patch ? 'nombres' then p_patch->>'nombres'
           else nombres
         end,
         apellidos = case
           when p_patch ? 'apellidos' then p_patch->>'apellidos'
           else apellidos
         end,
         tipo_documento = case
           when p_patch ? 'tipo_documento'
             then p_patch->>'tipo_documento'
           else tipo_documento
         end,
         dni = case
           when p_patch ? 'dni' then p_patch->>'dni'
           else dni
         end,
         telefono = case
           when p_patch ? 'telefono' then p_patch->>'telefono'
           else telefono
         end,
         actualizado_en = now()
   where id = p_cliente_id;

  return true;
end;
$function$;

commit;
