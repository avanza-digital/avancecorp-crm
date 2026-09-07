-- Sólo después de revertir SLA. Devuelve la gobernanza previa (incluidos sus cuatro gates rojos conocidos).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
DO $guard$ begin
if md5(pg_get_functiondef('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)'::regprocedure)) <> '49d73e13f8969161060e2ce2b669a85a' then raise exception 'Deriva posterior; rollback no autorizado'; end if;
if md5(pg_get_functiondef('crm.fusion_previsualizar_fn(uuid,uuid)'::regprocedure)) <> '814368bf22e2b9f2383bcce878a66fea' then raise exception 'Deriva posterior; rollback no autorizado'; end if;
if md5(pg_get_functiondef('private.bloquear_leads_nowait(uuid[])'::regprocedure)) <> '52ae633ace06f02c129de3612a021680' then raise exception 'Deriva posterior; rollback no autorizado'; end if;
if md5(pg_get_functiondef('private.fusion_bloqueos(uuid,uuid)'::regprocedure)) <> '0d12b3e7b02c7de953f93f132acb8d94' then raise exception 'Deriva posterior; rollback no autorizado'; end if;
if md5(pg_get_functiondef('crear_contrato(jsonb,jsonb)'::regprocedure)) <> '1cd2730dc75c966cfbd9ea8d95d4d1ed' then raise exception 'Deriva posterior; rollback no autorizado'; end if;
if md5(pg_get_functiondef('private.identidad_documentos_vigentes_cantidad(uuid,text)'::regprocedure)) <> '801485a9b42f3605eb87ebe6d30a5fa0' then raise exception 'Deriva posterior; rollback no autorizado'; end if;
if md5(pg_get_functiondef('private.fusion_impacto(uuid,uuid)'::regprocedure)) <> '8f48cae159dee0ea157ba45e2a833e04' then raise exception 'Deriva posterior; rollback no autorizado'; end if;
end; $guard$;
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
  -- [auditor A1] la AUTORIDAD se pregunta antes de reconocer: un no autorizado sigue muriendo en el 42501 uniforme
  -- de abajo (sin aprender nada del documento), con ON igual que con OFF.
  if private.resolver_en_puertas_bajo_candado()
     and (select private.puede_registrar_ventas())
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
CREATE OR REPLACE FUNCTION private.fusion_bloqueos(p_perdedora uuid, p_canonica uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_b text[] := '{}'; v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_n integer;
begin
  if p_perdedora is null or p_canonica is null then
    return array['Faltan las dos identidades'];
  end if;
  if p_perdedora = p_canonica then
    return array['La perdedora y la canónica son la misma identidad'];
  end if;
  select * into v_p from crm.inversionistas where id = p_perdedora;
  if not found then return array['La identidad perdedora no existe']; end if;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if not found then return array['La identidad canónica no existe']; end if;
  if v_p.estado = 'fusionado' then
    v_b := pg_catalog.array_append(v_b, ('La perdedora ya está fusionada: usa su canónica ' || private.inversionista_canonica(v_p.id)::text)::text);
  elsif v_p.estado <> 'activo' then
    v_b := pg_catalog.array_append(v_b, ('La perdedora no está activa (' || v_p.estado || '): revisión de Gerencia')::text);
  end if;
  if v_c.estado = 'fusionado' then
    v_b := pg_catalog.array_append(v_b, ('La canónica ya está fusionada: usa su canónica ' || private.inversionista_canonica(v_c.id)::text)::text);
  elsif v_c.estado <> 'activo' then
    v_b := pg_catalog.array_append(v_b, ('La canónica no está activa (' || v_c.estado || '): revisión de Gerencia')::text);
  end if;
  select count(*) into v_n from private.leads_de_identidades(array[p_perdedora, p_canonica]);
  if v_n > 1 then
    v_b := pg_catalog.array_append(v_b, 'Las dos identidades tienen lead (enlace vivo o puente): reconciliación de clase E hasta F5 (dos leads)'::text);
  end if;
  select count(distinct pf) into v_n from (
    select v_p.perfil_id as pf union select v_c.perfil_id
    union select l.perfil_id from crm.leads l where l.id in (select private.leads_de_identidades(array[p_perdedora, p_canonica]))) s
  where pf is not null;
  if v_n > 1 then
    v_b := pg_catalog.array_append(v_b, 'Hay más de un perfil de cliente entre las dos identidades y su lead: reconciliación de clase E hasta F5 (dos perfiles)'::text);
  end if;
  -- [Codex B1] el perfil del lead aún no reconocido debe llevar un documento de P o de C
  if exists (select 1 from crm.leads l join public.perfiles pp on pp.id = l.perfil_id
              where l.id in (select private.leads_de_identidades(array[p_perdedora, p_canonica]))
                and not exists (select 1 from crm.inversionistas i where i.perfil_id = pp.id and i.estado <> 'fusionado')
                and not (private.documento_es_de_identidad(p_perdedora, pp.tipo_documento, pp.dni)
                         or private.documento_es_de_identidad(p_canonica, pp.tipo_documento, pp.dni))) then
    v_b := pg_catalog.array_append(v_b, 'El perfil de cliente del lead no está reconocido y su documento no es de estas personas: reconciliación documental primero'::text);
  end if;
  if exists (select 1 from crm.multiempresa_idempotencia m
              where m.clave in ('auth_persona:' || p_perdedora::text, 'auth_persona:' || p_canonica::text)
                and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    v_b := pg_catalog.array_append(v_b, 'Hay un alta o conversión en curso (claim de Auth no terminal): termina o deja caducar'::text);
  end if;
  if exists (select 1 from crm.conversion_reservas r
              left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id in (p_perdedora, p_canonica)
                     or r.lead_id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])))
                and (r.expira_en > pg_catalog.now()
                     or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    v_b := pg_catalog.array_append(v_b, 'Hay una reserva de conversión viva o sellada sin convertir (por persona o por lead): termina o deja caducar'::text);
  end if;
  return v_b;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.bloquear_leads_nowait(p_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n integer;
begin
  begin
    select count(*) into v_n from (select l.id from crm.leads l where l.id = any(p_ids) order by l.id for update nowait) s;
  exception when lock_not_available then
    raise exception 'El lead está en uso por otra operación; vuelve a intentarlo' using errcode = '40001';
  end;
  return v_n;
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.fusion_previsualizar_fn(p_perdedora uuid, p_canonica uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_lead crm.leads%rowtype;
  v_bloq text[]; v_adv text[] := '{}'; v_foto jsonb;
  v_tp crm.inversionista_responsables%rowtype; v_tc crm.inversionista_responsables%rowtype;
begin
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia previsualiza una fusión' using errcode = '42501';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  select * into v_p from crm.inversionistas where id = p_perdedora;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if v_p.id is null or v_c.id is null or p_perdedora = p_canonica then
    return pg_catalog.jsonb_build_object('viable', false, 'bloqueos', pg_catalog.to_jsonb(v_bloq),
      'advertencias', '[]'::jsonb, 'hash', null, 'foto', null, 'impacto', null);
  end if;
  if exists (select 1 from crm.inversionista_identificadores a
             join crm.inversionista_identificadores b on b.tipo_documento = a.tipo_documento and b.documento_normalizado <> a.documento_normalizado
             where a.inversionista_id = p_perdedora and b.inversionista_id = p_canonica and a.estado = 'vigente' and b.estado = 'vigente') then
    v_adv := pg_catalog.array_append(v_adv, 'Las dos tienen un documento vigente del mismo tipo: una está mal; corrige el documento después de fusionar (indicando cuál sale)'::text);
  end if;
  if v_p.no_contactar <> v_c.no_contactar
     or exists (select 1 from crm.leads l where l.id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) and l.no_contactar <> (v_p.no_contactar or v_c.no_contactar)) then
    v_adv := pg_catalog.array_append(v_adv, 'Vetos distintos: el resultado es «No contactar» en la persona y el lead, y se cancelan las tareas pendientes del lead'::text);
  end if;
  select * into v_tp from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tc from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tp.responsable_id is not null and v_tc.responsable_id is not null and v_tp.responsable_id <> v_tc.responsable_id then
    v_adv := pg_catalog.array_append(v_adv, 'Responsables de relación distintos: gana el de la canónica; se cierra el tramo de la perdedora'::text);
  elsif v_tp.responsable_id is not null and v_tc.responsable_id is null then
    v_adv := pg_catalog.array_append(v_adv, 'La canónica hereda el responsable de relación de la perdedora'::text);
  end if;
  if exists (select 1 from crm.inversiones where inversionista_id = p_perdedora)
     or exists (select 1 from crm.inversion_titulares where inversionista_id = p_perdedora)
     or exists (select 1 from crm.cierres_externos where inversionista_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora tiene inversiones, titularidades o cierres: se reapuntan a la canónica; el dinero y sus fotos no se tocan'::text);
  end if;
  if exists (select 1 from crm.inversionistas where inversionista_canonico_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora es canónica de otras identidades fusionadas: se aplanan a la nueva canónica'::text);
  end if;
  select * into v_lead from crm.leads where id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) order by id limit 1;
  if v_lead.id is not null and not v_lead.activo then
    v_adv := pg_catalog.array_append(v_adv, 'El lead está inactivo: no se deja nota de actividad (el libro de fusiones es el rastro)'::text);
  end if;
  v_adv := pg_catalog.array_append(v_adv, 'La conversión mensual sigue siendo por lead/cliente hasta Contrato-F3: la fusión no altera cifras ni meses sellados'::text);
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  return pg_catalog.jsonb_build_object(
    'viable', pg_catalog.cardinality(v_bloq) = 0,
    'bloqueos', pg_catalog.to_jsonb(v_bloq),
    'advertencias', pg_catalog.to_jsonb(v_adv),
    'hash', private.idem_hash(v_foto),
    'foto', v_foto,
    'impacto', pg_catalog.jsonb_build_object(
      'leads', (select count(*) from private.leads_de_identidades(array[p_perdedora])),
      'puente', (select count(*) from crm.inversionista_leads where inversionista_id = p_perdedora),
      'tareas_pendientes', (select count(*) from crm.tareas t where t.estado = 'pendiente' and t.lead_id in (select private.leads_de_identidades(array[p_perdedora, p_canonica]))),
      'identificadores', (select count(*) from crm.inversionista_identificadores where inversionista_id = p_perdedora and estado = 'vigente'),
      'tramos', (select count(*) from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null),
      'cierres', (select count(*) from crm.cierres_externos where inversionista_id = p_perdedora),
      'inversiones', (select count(*) from crm.inversiones where inversionista_id = p_perdedora),
      'titulares', (select count(*) from crm.inversion_titulares where inversionista_id = p_perdedora),
      'reservas', (select count(*) from crm.conversion_reservas where inversionista_id = p_perdedora),
      'predecesoras', (select count(*) from crm.inversionistas where inversionista_canonico_id = p_perdedora)));
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.corregir_documento_inversionista_fn(p_inversionista uuid, p_tipo text, p_documento text, p_motivo text, p_identificador_anterior uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_tipo text; v_norm text;
  v_inv crm.inversionistas%rowtype; v_old_id uuid; v_old_tipo text; v_old_norm text; v_n integer; v_otro uuid; v_ahora timestamptz;
  v_perfil_id uuid; v_perfil_dni text; v_perfil_tipo text; v_lead crm.leads%rowtype; v_new_id uuid; v_op_id uuid;
  v_perfil_res text; v_lead_res text; v_k text; v_docs text[]; v_reusa boolean := false;
begin
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  v_tipo := pg_catalog.upper(pg_catalog.btrim(coalesce(p_tipo, '')));
  v_norm := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido' using errcode = '22023';
  end if;
  if (v_tipo = 'DNI' and v_norm !~ '^[0-9]{8}$')
     or (v_tipo = 'CE' and v_norm !~ '^[0-9]{9,12}$')
     or (v_tipo = 'PASAPORTE' and v_norm !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: corrige en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  -- El identificador que sale, leído SIN lock (solo para calcular los advisories); se revalida bajo la identidad [E3-5].
  -- La unicidad «único de su tipo» solo se exige cuando NO se indica cuál sale [E3-15].
  if p_identificador_anterior is not null then
    select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
    from crm.inversionista_identificadores d
    where d.id = p_identificador_anterior and d.inversionista_id = p_inversionista and d.estado = 'vigente';
    if v_old_id is null then
      raise exception 'El identificador anterior no es un documento vigente de esta persona' using errcode = 'P0409';
    end if;
  else
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n > 1 then
      raise exception 'La persona tiene varios documentos vigentes de tipo %: indica cuál sustituir (p_identificador_anterior)', v_tipo using errcode = '22023';
    elsif v_n = 1 then
      select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
      from crm.inversionista_identificadores d
      where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    end if;
  end if;
  if v_old_tipo = v_tipo and v_old_norm = v_norm then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_norm, v_old_norm] || coalesce((select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista), '{}'));

  -- jerarquía [E3-2] + Gerencia revalidada -> advisories de viejo y nuevo, ordenados -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona (membresía revalidada)' using errcode = '42501';
  end if;
  select pg_catalog.array_agg(k order by k) into v_docs
  from (select distinct k from unnest(array[v_tipo || ':' || v_norm, v_old_tipo || ':' || v_old_norm]) k where k is not null) s;
  foreach v_k in array v_docs loop
    perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
  end loop;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se corregía (estado %); vuelve a intentarlo', v_inv.estado using errcode = '40001';
  end if;
  if v_old_id is not null then
    if not exists (select 1 from crm.inversionista_identificadores d where d.id = v_old_id and d.inversionista_id = p_inversionista
                     and d.estado = 'vigente' and d.tipo_documento = v_old_tipo and d.documento_normalizado = v_old_norm) then
      raise exception 'El documento de la persona cambió mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  if p_identificador_anterior is null then
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n <> (case when v_old_id is null then 0 else 1 end) then
      raise exception 'Los documentos de la persona cambiaron mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  -- el nuevo, ¿ya es vigente de alguien?
  select d.inversionista_id, d.id into v_otro, v_new_id from crm.inversionista_identificadores d
  where d.tipo_documento = v_tipo and d.documento_normalizado = v_norm and d.estado = 'vigente';
  if v_otro is not null and v_otro <> p_inversionista then
    raise exception 'El documento pertenece a otra persona reconocida: fusiona las identidades en vez de corregir' using errcode = 'P0409';
  end if;
  if v_otro = p_inversionista then
    if v_old_id is null then
      return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
    end if;
    v_reusa := true;   -- [E3-15] el destino ya es un vigente propio (p. ej. tras una fusión): sale el anterior y se reutiliza
  else
    v_new_id := null;
  end if;
  -- alta/conversión en curso [E3-7]: claim y reservas (por persona O por lead) bajo lock
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- perfil enlazado FOR UPDATE (escribe) -> cierres -> tareas -> lead (NOWAIT) -> reservas -> contactos -> terceros
  if v_inv.perfil_id is not null then
    select p.id, p.dni, p.tipo_documento into v_perfil_id, v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_inv.perfil_id for update;
  end if;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id = p_inversionista or ce.lead_id in (select private.leads_de_identidades(array[p_inversionista]))
   order by ce.id for update;
  perform 1 from crm.tareas t where t.estado = 'pendiente'
     and t.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by t.id for update;
  perform private.bloquear_leads_nowait(coalesce((select pg_catalog.array_agg(x) from private.leads_de_identidades(array[p_inversionista]) x), '{}'));
  select * into v_lead from crm.leads l where l.inversionista_id = p_inversionista order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by r.lead_id for update;
  if exists (select 1 from crm.conversion_reservas r left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])))
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    raise exception 'Hay una reserva de conversión viva o sellada sin convertir (por persona o por lead): termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- contactos (último recurso del orden) ANTES de mirar a terceros [E3-6]: el trigger los retoma reentrante
  if v_lead.id is not null then
    perform private.bloquear_contactos_lead(array[v_lead.telefono], array[v_lead.dni, case when v_tipo = 'DNI' then v_norm end]);
  else
    perform private.bloquear_contactos_lead(array[]::text[], array[case when v_tipo = 'DNI' then v_norm end]);
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  if exists (select 1 from public.perfiles pp
              where pp.rol = 'cliente'
                and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(pp.dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
                and coalesce(nullif(pg_catalog.btrim(pp.tipo_documento), ''), 'DNI') = v_tipo
                and pp.id is distinct from v_inv.perfil_id) then
    raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id
                                  and l.activo = true and l.etapa not in ('convertido', 'descartado')) then
    raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id and l.inversionista_id is not null
                                  and l.inversionista_id <> p_inversionista) then
    raise exception 'Otro lead enlazado a otra persona lleva ese DNI: fusiona o corrige ese lead primero' using errcode = 'P0409';
  end if;
  -- [auditor M2] lo que la excepción del trigger deja de comprobar: OTRO lead con ese DNI vetado o en enfriamiento congela el
  -- documento (el veto de la PROPIA persona no cuenta: corregir su documento es justamente lo que Gerencia está haciendo).
  if v_tipo = 'DNI' and exists (
       select 1 from crm.leads l
       left join crm.enfriamiento_politica ep on ep.motivo = l.motivo_descarte
       where l.dni = v_norm and l.id is distinct from v_lead.id
         and (l.inversionista_id is null or l.inversionista_id <> p_inversionista)
         and (l.no_contactar
              or (l.etapa = 'descartado' and l.descartado_en is not null and coalesce(ep.dias, 0) > 0
                  and l.descartado_en + pg_catalog.make_interval(days => ep.dias) > pg_catalog.now()))) then
    raise exception 'Ese DNI está congelado por un veto o un enfriamiento vigente en otro lead: revisión de Gerencia' using errcode = 'P0409';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  perform pg_catalog.set_config('crm.correccion_documento', 'on', true);   -- [auditor M1] la excepción del trigger la exige
  if v_old_id is not null then
    update crm.inversionista_identificadores set estado = 'historico', vigente_hasta = v_ahora where id = v_old_id;
  end if;
  if not v_reusa then
    insert into crm.inversionista_identificadores
      (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
    values (p_inversionista, v_tipo, v_norm, p_documento, 'vigente', true, 'correccion', v_ahora, v_uid)
    returning id into v_new_id;
  else
    -- [Codex B3] el destino reutilizado queda VERIFICADO con la misma política de la corrección
    update crm.inversionista_identificadores set verificado = true, fuente = coalesce(fuente, 'correccion') where id = v_new_id and verificado = false;
  end if;
  v_perfil_res := case when v_inv.perfil_id is null then 'ninguno' else 'sin_cambio' end;
  if v_perfil_id is not null and v_old_id is not null
     and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(v_perfil_dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_old_norm
     and coalesce(nullif(pg_catalog.btrim(v_perfil_tipo), ''), 'DNI') = v_old_tipo then
    begin
      update public.perfiles set dni = v_norm, tipo_documento = v_tipo where id = v_perfil_id;
    exception when unique_violation then
      raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
    end;
    v_perfil_res := 'actualizado';
  end if;
  v_lead_res := case when v_lead.id is null then 'sin_lead' else 'sin_cambio' end;
  if v_lead.id is not null and v_old_id is not null and v_old_tipo = 'DNI' and v_lead.dni = v_old_norm then
    if v_tipo = 'DNI' then
      begin
        update crm.leads set dni = v_norm where id = v_lead.id;
      exception when unique_violation then
        raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
      end;
      v_lead_res := 'dni';
    else
      update crm.leads set dni = null where id = v_lead.id;
      v_lead_res := 'nulo';
    end if;
  end if;
  insert into crm.inversionista_operaciones
    (tipo, inversionista_id, lead_id, identificador_anterior_id, identificador_nuevo_id, motivo, detalle, por)
  values ('correccion', p_inversionista, v_lead.id, v_old_id, v_new_id, p_motivo,
          pg_catalog.jsonb_build_object('tipo_documento', v_tipo, 'perfil', v_perfil_res, 'lead', v_lead_res, 'reutilizado', v_reusa), v_uid)
  returning id into v_op_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Documento corregido por Gerencia (' || v_tipo || ')',
            pg_catalog.jsonb_build_object('evento', 'correccion_documento', 'operacion_id', v_op_id,
                                          'inversionista_id', p_inversionista, 'lead', v_lead_res),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.correccion_documento', 'off', true);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'corregido', 'inversionista_id', p_inversionista,
    'operacion_id', v_op_id, 'identificador_nuevo_id', v_new_id, 'identificador_anterior_id', v_old_id,
    'reutilizado', v_reusa, 'perfil', v_perfil_res, 'lead', v_lead_res);
end;
$function$
;
drop function private.identidad_documentos_vigentes_cantidad(uuid,text),private.fusion_impacto(uuid,uuid);
DROP TRIGGER trg_audit_ledger_rentabilidad ON crm.ledger_rentabilidad;
CREATE TRIGGER trg_audit_ledger_rentabilidad AFTER INSERT ON crm.ledger_rentabilidad FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm();
DROP TRIGGER trg_audit_politica_rentabilidad ON crm.politica_rentabilidad;
CREATE TRIGGER trg_audit_politica_rentabilidad AFTER INSERT ON crm.politica_rentabilidad FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm();
DROP TRIGGER trg_audit_rentabilidad_hitos ON crm.rentabilidad_hitos;
CREATE TRIGGER trg_audit_rentabilidad_hitos AFTER INSERT OR UPDATE ON crm.rentabilidad_hitos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm();
DROP TRIGGER trg_audit_solicitudes_tasa ON crm.solicitudes_tasa;
CREATE TRIGGER trg_audit_solicitudes_tasa AFTER INSERT OR UPDATE ON crm.solicitudes_tasa FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm();
insert into private.analista_vigencia_exenciones select * from jsonb_populate_record(null::private.analista_vigencia_exenciones,'{"tipo": "funcion", "razon": "P-055 F5.c: gatea por private.puede_registrar_ventas(), que exige NO estar revocado (la misma garantia que P04 daba via membresia). Sigue nombrando es_analista() en el DECLARE (linea muerta), por eso permanece en el censo y exenta; huella re-fijada al cuerpo de F5.c.", "huella": "1ddba6aba83fee25f9225a6bec1608f1", "objeto": "public.crear_contrato(jsonb,jsonb)", "declarado_en": "2026-08-30T04:02:39.070674+00:00"}'::jsonb);
ALTER TABLE private.f7_piezas_en_observacion DISABLE TRIGGER trg_f7_obs_00_solo_crece;
UPDATE private.f7_piezas_en_observacion SET huella_md5='5c92f416c4e34fd4ed864c8be19502eb',nota='organo interno del alta pdf_v2 - JAMAS se derriba' WHERE firma='crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)';
ALTER TABLE private.f7_piezas_en_observacion ENABLE TRIGGER trg_f7_obs_00_solo_crece;
UPDATE private.analitica_leads_citas_exenciones SET huella='ce96112648f15d1f8213913b8c736ba1',razon='Operativa de derivacion: cuenta para validar el lote que se deriva y dejar rastro; no es una pregunta de metricas.' WHERE objeto='crm.derivar_leads_equipo_fn(uuid[],uuid[])';
UPDATE private.analitica_leads_citas_exenciones SET huella='f0f1fdde36810504fb7e8ff2d0942dd3',razon='Previa de offboarding: cuenta que dejaria huerfano una desactivacion (leads, tareas) como inventario del momento; no es metrica historica.' WHERE objeto='crm.impacto_desactivacion_usuario_fn(uuid)';
UPDATE private.analitica_leads_citas_exenciones SET huella='2ed68bc3b32208af5b1c8d0261ada01c',razon='Operativa de rescate: valida el lote de descartados que se rescata; sus counts son de consistencia, no metricas.' WHERE objeto='crm.rescatar_descartes(uuid[],uuid[],boolean)';
UPDATE private.analitica_leads_citas_exenciones SET huella='45c1ff5cd533ee1138ec46cfa5f24877',razon='Resumen operativo del reparto: cuenta lo por repartir AHORA; inventario del momento.' WHERE objeto='crm.resumen_reparto_fn()';
UPDATE private.analitica_leads_citas_exenciones SET huella='985a176dbe618ea28d47c9147cc17e69',razon='El MOTOR DEL SELLO: su conversion viene de conversion_mensual_por_vendedor, que bebe del nucleo (transitividad verificada el 30/08); sus counts propios son cobertura del ledger (suelo, mes parcial), no otra conversion.' WHERE objeto='crm.cerrar_periodo(date)';
UPDATE private.analitica_leads_citas_exenciones SET huella='6ce60dcdab28267cbfc6bdc42227588b',razon='Nucleo por TRANSITIVIDAD (llama a conversion_mensual_por_vendedor): sirve el mes sellado desde las tablas del cierre y, con el mes ABIERTO, calcula en vivo por el mismo puente; sus counts propios son cobertura y altas del periodo.' WHERE objeto='crm.conversion_mensual_sin_cartera_fn(date)';
UPDATE private.analitica_lc_sello SET sello=private.huella_exenciones_analitica_lc(),sellado_en=now() WHERE id;
commit;
