-- REGISTRO en supabase_migrations.schema_migrations de F2.b E4. `db query --linked --file` NO registra: correr DESPUÉS de aplicar. Idempotente.
begin;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260905140000', 'crm_f2b_e4_contrato_reconoce_persona_y_candado_documento', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b E4 — LAS DOS PIEZAS DE `public` (OK de Miguel 05/09) [D-1]
-- ============================================================================
--
-- ⚠️ Excepción documentada: esta migración del CRM TOCA `public` (regla del subproyecto) con OK explícito de Miguel
-- (05/09/2026, RETOMAR-60 §4): (1) public.crear_contrato transformada desde el texto vivo (guarda md5 de prod);
-- (2) trigger nuevo en public.perfiles. TODO detrás de la bandera resolver_en_puertas: apagada = byte a byte / inerte.
--
-- QUE:
--   * public.crear_contrato: con la bandera ENCENDIDA y el cliente activo, reconoce a la persona
--     (private.asegurar_identidad_perfil) ANTES de su FOR SHARE: jerarquía -> documento -> identidad -> perfil.
--     Sin documento válido o con documento de otra persona reconocida -> P0409 (fail-closed). OFF: idéntica.
--   * trg_perfiles_zz_documento_protegido (BEFORE UPDATE OF dni, tipo_documento): con la bandera encendida, el
--     documento de un perfil ENLAZADO a una identidad no fusionada solo cambia bajo crm.correccion_documento=on
--     (la fija crm.corregir_documento_inversionista_fn, b5). Mismo documento con otro formato: pasa. OFF: inerte.
--   * Colaboradores y registros del Portal: FUERA de la identidad (decisión de Miguel): nada que construir.
-- Reversa: scripts/rollback-f2b-e4.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_e4_public_contrato_y_candado'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.asegurar_identidad_perfil(uuid,text)') is null
     or to_regprocedure('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)') is null then
    raise exception 'F2.b E4: falta b3 (20260905100000) o b5 (20260905120000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b E4: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='crear_contrato' and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb';
  if v_h is null then
    raise exception 'F2.b E4: falta public.crear_contrato(jsonb,jsonb)';
  end if;
  if v_h is distinct from 'a538aa6f60791a4b215bbe615b347a1e' and v_h is distinct from '49401604f728e1f6ae817f2df076a750' then
    raise exception 'F2.b E4: public.crear_contrato no es ni el texto vivo de producción ni el de E4 (%)', v_h;
  end if;
end
$guard$;

-- ============================================================================
-- 1. public.crear_contrato reconoce a la persona (rama ON; OFF byte a byte)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_gestor_cartera boolean := (select public.es_gestor_cartera());
  v_rol_crm text := private.rol_crm(v_uid);
  v_es_gerencia_crm boolean := coalesce(v_rol_crm = 'gerencia', false);
  v_es_crm_catalogado boolean :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and nullif(current_setting('crm.producto_condicion_id', true), '') is not null;
  v_cliente_id uuid;
  v_numero text := nullif(btrim(p_contrato->>'numero_contrato'), '');
  v_categoria text := p_contrato->>'categoria';
  v_moneda text := upper(coalesce(nullif(p_contrato->>'moneda', ''), 'PEN'));
  v_capital numeric;
  v_anio integer := extract(year from now() at time zone 'America/Lima')::integer;
  v_contrato_id uuid;
  v_fecha_operacion date;
  v_periodo date;
  v_cuota jsonb;
  v_asesor_id uuid;
  v_asesor_rol text;
  v_operacion_id uuid;
  v_origen_id uuid;
  v_origen public.contratos%rowtype;
  v_capital_renovado numeric;
  v_capital_adicional numeric;
  v_primer_periodo date;
  v_upgrade_elegible boolean;
  v_analista_cierre uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
    v_capital := (p_contrato->>'capital')::numeric;
  exception when invalid_text_representation then
    raise exception 'Cliente o capital inválido' using errcode = '22023';
  end;

  -- Vincula autorización y escritura a la misma versión de la cartera. Una
  -- reasignación concurrente espera este lock; si ganó antes, aquí ya se lee el
  -- nuevo Analista y el anterior queda fuera del gate.
  -- F2.b (E4) [D-1, OK de Miguel 05/09]: con la identidad unificada ENCENDIDA, crear un contrato RECONOCE
  -- a la persona ANTES del FOR SHARE de abajo (jerarquía -> documento -> identidad -> perfil, reentrante).
  -- Solo si el cliente existe activo (así un id inexistente sigue muriendo en el 42501 de siempre).
  -- Sin documento válido o con documento de otra persona reconocida -> P0409 (contrato §4.3, fail-closed).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and exists (select 1 from public.perfiles p where p.id = v_cliente_id and p.rol = 'cliente' and p.activo) then
    perform private.asegurar_identidad_perfil(v_cliente_id, 'contrato');
  end if;
  select p.asesor_perfil_id into v_asesor_id
  from public.perfiles p
  where p.id = v_cliente_id and p.rol = 'cliente' and p.activo
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;
  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (Nuevo, Renovación o Upgrade)';
  end if;
  if v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;

  -- EL ANALISTA QUE CIERRA (decision 2 del plan P-055). Es de quien VENDIO, no
  -- de quien tecleo: `creado_por` se conserva aparte y no se pisa.
  begin
    v_analista_cierre := nullif(btrim(coalesce(p_contrato->>'analista_cierre_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception 'El analista que cierra no es valido' using errcode = '22023';
  end;

  if v_analista_cierre is not null then
    -- Elegido a mano: tiene que poder tener ventas. SOLO ACTIVOS (decision de
    -- Miguel, 29/08): una venta NUEVA es de alguien que esta trabajando; la
    -- venta vieja de alguien que se fue entra por la reasignacion de gerencia
    -- (que si acepta inactivos, con motivo y rastro). Y los roles OFF-ROSTER
    -- (coordinador, directorio) no son organigrama comercial por diseno.
    if not exists (
      select 1 from crm.equipo e where e.perfil_id = v_analista_cierre
        and e.activo
        and e.rol_crm in ('vendedor','supervisor','gerencia')
    ) then
      raise exception 'El analista que cierra tiene que estar activo en el equipo comercial'
        using errcode = '22023';
    end if;
  else
    -- No vino. «Si no corresponde a nadie, lo pone a su nombre» (decision 2):
    -- eso solo tiene sentido si quien registra PUEDE tener ventas. Si no puede
    -- -una administrativa, por ejemplo-, tiene que elegir a quien corresponde.
    if not exists (select 1 from crm.equipo e where e.perfil_id = v_uid and e.activo) then
      raise exception 'Elige el analista de la venta'
        using errcode = '22023',
              hint = 'Quien registra no forma parte del equipo comercial, asi que la venta no puede quedar a su nombre.';
    end if;
    v_analista_cierre := v_uid;
  end if;

  -- Las operaciones de cartera necesitan un dueño congelado. No se atribuye a
  -- quien digitó: se atribuye al Analista de perfiles.asesor_perfil_id.
  if v_categoria in ('renovacion', 'upgrade') then
    select e.rol_crm into v_asesor_rol
    from crm.equipo e
    where e.perfil_id = v_asesor_id and e.activo
    for share;
    if v_asesor_id is null
       or not found
       or v_asesor_rol not in ('vendedor', 'supervisor') then
      raise exception using
        errcode = '22023',
        message = 'Asigna un Analista activo al cliente antes de registrar la operación';
    end if;
  end if;

  if v_categoria = 'renovacion' then
    begin
      v_origen_id := (p_contrato->>'contrato_origen_id')::uuid;
      v_capital_renovado := (p_contrato->>'capital_renovado')::numeric;
      v_capital_adicional := coalesce((p_contrato->>'capital_adicional')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'Completa contrato anterior, capital renovado y adicional válidos'
        using errcode = '22023';
    end;

    select * into v_origen
    from public.contratos c
    where c.id = v_origen_id
    for update;
    if not found then
      raise exception 'El contrato a renovar no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from v_cliente_id then
      raise exception 'El contrato anterior pertenece a otro cliente' using errcode = '22023';
    end if;
    if v_origen.estado not in ('activo', 'vencido') or v_origen.renovado_a_id is not null then
      raise exception 'El contrato anterior ya fue cerrado o renovado' using errcode = 'P0409';
    end if;
    if v_origen.fecha_vencimiento > (now() at time zone 'America/Lima')::date then
      raise exception 'La renovación solo se registra cuando el contrato llega a su fecha fin'
        using errcode = '22023';
    end if;
    if v_origen.moneda is distinct from v_moneda then
      raise exception 'La renovación debe conservar la moneda del contrato anterior'
        using errcode = '22023';
    end if;
    if (p_contrato->>'fecha_inicio')::date < v_origen.fecha_vencimiento then
      raise exception 'El contrato nuevo no puede iniciar antes del vencimiento anterior'
        using errcode = '22023';
    end if;
    if v_capital_renovado <= 0 or v_capital_renovado > v_origen.capital then
      raise exception 'El capital renovado debe ser mayor a cero y no superar el contrato anterior'
        using errcode = '22023';
    end if;
    if v_capital_adicional < 0 then
      raise exception 'El capital adicional no puede ser negativo' using errcode = '22023';
    end if;
    if v_capital is distinct from (v_capital_renovado + v_capital_adicional) then
      raise exception 'El nuevo capital debe ser capital renovado + capital adicional'
        using errcode = '22023';
    end if;
  end if;

  if v_numero is null then
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, notas_internas,
    categoria, estado, creado_por, analista_cierre_id
  ) values (
    v_cliente_id, v_numero, v_capital, v_moneda,
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria, 'activo', v_uid, v_analista_cierre
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;

  if p_cronograma is null or jsonb_typeof(p_cronograma) <> 'array'
     or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacío';
  end if;
  for v_cuota in select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id, numero_cuota, fecha_programada, monto_programado, estado, tipo
    ) values (
      v_contrato_id, (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric, 'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;
  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(v_contrato_id, p_contrato->'titulares');
  end if;

  if v_categoria in ('renovacion', 'upgrade') then
    v_periodo := date_trunc('month', v_fecha_operacion)::date;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.operaciones_cartera'),
      pg_catalog.hashtext(v_cliente_id::text || '|' || v_periodo::text)
    );

    if v_categoria = 'upgrade' then
      select min(date_trunc('month', c.fecha_cierre_comercial)::date)
        into v_primer_periodo
      from public.contratos c
      where c.cliente_id = v_cliente_id;
      v_upgrade_elegible := v_periodo > v_primer_periodo;
    else
      v_upgrade_elegible := true;
    end if;

    insert into crm.operaciones_cartera (
      cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
      fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
      elegible_conversion, desglose_completo, fuente, creado_por
    ) values (
      v_cliente_id, v_asesor_id, v_categoria, v_origen_id, v_contrato_id,
      v_fecha_operacion, v_periodo, v_moneda,
      case when v_categoria = 'renovacion' then v_capital_renovado end,
      case when v_categoria = 'renovacion' then v_capital_adicional end,
      v_upgrade_elegible, true, 'flujo_cartera', v_uid
    ) returning id into v_operacion_id;
  end if;

  if v_categoria = 'renovacion' then
    update public.cronograma_pagos
       set estado = 'trasladado'
     where contrato_id = v_origen_id and estado in ('pendiente', 'vencido');
    update public.contratos
       set estado = 'renovado', renovado_a_id = v_contrato_id,
           cerrado_en = now(), cerrado_por = v_uid
     where id = v_origen_id;
  end if;

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero,
    'operacion_id', v_operacion_id,
    'conversion_elegible', case
      when v_categoria in ('renovacion', 'upgrade') then v_upgrade_elegible
    end
  );
end;
$function$
;

-- ============================================================================
-- 2. Candado del documento en el Portal: el DNI/tipo de un cliente RECONOCIDO solo cambia por la corrección de Gerencia
-- ============================================================================
create or replace function private.trg_perfiles_documento_protegido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(old.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_new text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(new.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_told text := coalesce(nullif(pg_catalog.btrim(old.tipo_documento), ''), 'DNI');
  v_tnew text := coalesce(nullif(pg_catalog.btrim(new.tipo_documento), ''), 'DNI');
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  -- La corrección de Gerencia (crm.corregir_documento_inversionista_fn, b5) fija esta GUC alrededor de sus hechos.
  if coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false) then
    return new;
  end if;
  if v_old = v_new and v_told = v_tnew then
    return new;   -- mismo documento con otro formato: no es un cambio
  end if;
  if exists (select 1 from crm.inversionistas i where i.perfil_id = new.id and i.estado <> 'fusionado') then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige desde el CRM (corrección de documento de Gerencia)'
      using errcode = 'P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.trg_perfiles_documento_protegido() from public, anon, authenticated, service_role;
drop trigger if exists trg_perfiles_zz_documento_protegido on public.perfiles;
create trigger trg_perfiles_zz_documento_protegido
  before update of dni, tipo_documento on public.perfiles
  for each row execute function private.trg_perfiles_documento_protegido();
comment on trigger trg_perfiles_zz_documento_protegido on public.perfiles is
  'F2.b E4 (OK Miguel 05/09): con resolver_en_puertas encendida, el documento de un perfil enlazado a una identidad solo cambia bajo crm.correccion_documento=on (corrección de Gerencia). Apagada: inerte.';

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='crear_contrato' and pg_get_function_identity_arguments(p.oid)='p_contrato jsonb, p_cronograma jsonb') is distinct from '49401604f728e1f6ae817f2df076a750' then
    raise exception 'POSTFLIGHT E4: public.crear_contrato no quedó byte a byte como la genera gen-e4.py';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid='public.perfiles'::regclass and tgname='trg_perfiles_zz_documento_protegido' and not tgisinternal) then
    raise exception 'POSTFLIGHT E4: falta el trigger del candado';
  end if;
  if has_function_privilege('anon', 'private.trg_perfiles_documento_protegido()', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.trg_perfiles_documento_protegido()', 'EXECUTE')
     or has_function_privilege('service_role', 'private.trg_perfiles_documento_protegido()', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'private.trg_perfiles_documento_protegido()'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT E4: grants indebidos en la función del trigger';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT E4: la bandera quedó encendida';
  end if;
  raise notice 'F2.b E4 OK: crear_contrato reconoce a la persona (ON) y el documento del Portal queda bajo candado (ON). Bandera APAGADA.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
commit;
