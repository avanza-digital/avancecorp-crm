-- Solo antes de la primera corrección. Después, corregir por la puerta auditada.
begin;
do $$ begin
  if exists(select 1 from crm.correcciones_categoria_contrato) then
    raise exception 'Hay correcciones auditadas: preparar una migración compensatoria; no borrar el historial';
  end if;
end; $$;
-- private.trg_contratos_producto_snapshot()
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.trg_contratos_producto_snapshot()'));
begin
  if v_def is null or md5(v_def) not in ('c5973e7aaf319548ec39ce78e17b4470') then
    raise exception 'Cambió private.trg_contratos_producto_snapshot; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  v_old_es_legacy boolean;
  v_terminos_legacy_coinciden boolean;
  v_terminos_cambiaron boolean := false;
  v_clasificacion_corregida boolean := false;
begin
  if v_solicitada_text is not null then
    begin
$antes$, $despues$  v_old_es_legacy boolean;
  v_terminos_legacy_coinciden boolean;
  v_terminos_cambiaron boolean := false;
begin
  if v_solicitada_text is not null then
    begin
$despues$);
  v_def := replace(v_def, $antes$  end if;

  if tg_op = 'UPDATE' then
    -- La categoría comercial puede corregirse sin cambiar el producto contratado.
    -- El trigger de categoría exige además la autorización de ESTA transacción.
    v_clasificacion_corregida := coalesce((select x.categoria_nueva=new.categoria from crm.correcciones_categoria_contrato x
      where x.contrato_id=new.id order by x.creado_en desc,x.id desc limit 1),false);
    v_terminos_cambiaron :=
      (new.categoria is distinct from old.categoria and not v_clasificacion_corregida)
      or new.moneda is distinct from old.moneda
      or new.modalidad is distinct from old.modalidad
      or new.tipo_interes is distinct from old.tipo_interes
$antes$, $despues$  end if;

  if tg_op = 'UPDATE' then
    v_terminos_cambiaron :=
      new.categoria is distinct from old.categoria
      or new.moneda is distinct from old.moneda
      or new.modalidad is distinct from old.modalidad
      or new.tipo_interes is distinct from old.tipo_interes
$despues$);
  v_def := replace(v_def, $antes$    end if;
  end if;

  if (new.categoria is distinct from v_categoria and not v_clasificacion_corregida)
     or new.moneda is distinct from v_moneda
     or new.modalidad is distinct from v_modalidad
     or new.tipo_interes is distinct from v_tipo_interes
$antes$, $despues$    end if;
  end if;

  if new.categoria is distinct from v_categoria
     or new.moneda is distinct from v_moneda
     or new.modalidad is distinct from v_modalidad
     or new.tipo_interes is distinct from v_tipo_interes
$despues$);
  if md5(v_def) not in ('c4c222984db5bf6232edae70b0ee19f1') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.ranking_cartera_desglose(date, uuid, jsonb)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.ranking_cartera_desglose(date, uuid, jsonb)'));
begin
  if v_def is null or md5(v_def) not in ('0bac249b4061ce1f2827dec405a4235d') then
    raise exception 'Cambió private.ranking_cartera_desglose; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$    left join public.contratos c on c.id = f.operacion_id
    -- contrato_nuevo_id es UNIQUE: jamás multiplica el capital. No usamos la
    -- elegibilidad de conversión para excluir stock confirmado del Ranking.
    left join private.operaciones_cartera_clasificadas() o on o.contrato_nuevo_id = c.id
      and o.cliente_id = c.cliente_id and o.moneda = f.moneda
      and o.fecha_operacion = c.fecha_cierre_comercial
    where f.vendedor_id = p_vendedor_id and f.origen = 'cartera'
$antes$, $despues$    left join public.contratos c on c.id = f.operacion_id
    -- contrato_nuevo_id es UNIQUE: jamás multiplica el capital. No usamos la
    -- elegibilidad de conversión para excluir stock confirmado del Ranking.
    left join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
      and o.cliente_id = c.cliente_id and o.moneda = f.moneda
      and o.fecha_operacion = c.fecha_cierre_comercial
    where f.vendedor_id = p_vendedor_id and f.origen = 'cartera'
$despues$);
  if md5(v_def) not in ('ed569a0ae4c21e0da484c6f989f6ecc8') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.ranking_capital_origen_filas(timestamp with time zone, timestamp with time zone, uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.ranking_capital_origen_filas(timestamp with time zone, timestamp with time zone, uuid)'));
begin
  if v_def is null or md5(v_def) not in ('e835dffe112f42df8a26bff65b600669') then
    raise exception 'Cambió private.ranking_capital_origen_filas; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$        when cliente.cantidad > 0 then
          case when cliente.origenes_distintos = 1 then cliente.origen_unico else 'sin_origen' end
        when exists (
          select 1 from private.operaciones_cartera_clasificadas() o
          where o.contrato_nuevo_id = c.id
            and o.cliente_id = c.cliente_id
            and o.moneda = c.moneda
$antes$, $despues$        when cliente.cantidad > 0 then
          case when cliente.origenes_distintos = 1 then cliente.origen_unico else 'sin_origen' end
        when exists (
          select 1 from crm.operaciones_cartera o
          where o.contrato_nuevo_id = c.id
            and o.cliente_id = c.cliente_id
            and o.moneda = c.moneda
$despues$);
  if md5(v_def) not in ('2f7e30d1a375e5db70b2d1803ad43f2e') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.capital_episodios(timestamp with time zone, timestamp with time zone, boolean, uuid[])
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.capital_episodios(timestamp with time zone, timestamp with time zone, boolean, uuid[])'));
begin
  if v_def is null or md5(v_def) not in ('9a2384749cc50e0f8c550cd439de6ff2') then
    raise exception 'Cambió private.capital_episodios; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$    ),
    o.moneda,
    parte.monto,
    case when exists(select 1 from crm.correcciones_categoria_contrato x where x.contrato_id=c.id) then c.categoria else o.tipo end,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
$antes$, $despues$    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
$despues$);
  if md5(v_def) not in ('2ed07da302e9a1b881a4962724234dd7') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.metricas_cartera_por_vendedor(date)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.metricas_cartera_por_vendedor(date)'));
begin
  if v_def is null or md5(v_def) not in ('1099cc8b6ccf684c978c77b5f15c0968') then
    raise exception 'Cambió private.metricas_cartera_por_vendedor; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$ SET search_path TO ''
AS $function$
  with ops as materialized (
    -- Los conteos siguen la clasificación corregida; el dinero sale del núcleo.
    -- Una corrección sin desglose financiero queda marcada como incompleta.
    select o.*
    from private.operaciones_cartera_clasificadas() o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
$antes$, $despues$ SET search_path TO ''
AS $function$
  with ops as materialized (
    -- Los CONTEOS de operaciones siguen siendo del registro de operaciones
    -- (contar filas no es sumar capital); el DINERO sale del nucleo.
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
$despues$);
  if md5(v_def) not in ('6b7e7a8b868082cd0c81e18ca7c21479') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.conversion_cierres_coordinacion(uuid, date, date, integer)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.conversion_cierres_coordinacion(uuid, date, date, integer)'));
begin
  if v_def is null or md5(v_def) not in ('4e433dc05b04a5734595483870dda191') then
    raise exception 'Cambió private.conversion_cierres_coordinacion; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$      ) as fila
    from pagina e
    left join crm.leads l on l.id = e.lead_id
    left join private.operaciones_cartera_clasificadas() o on o.id = e.operacion_id
    left join public.perfiles p on p.id = o.cliente_id
  )
  select pg_catalog.jsonb_build_object('version', 1, 'analista_id', p_analista,
$antes$, $despues$      ) as fila
    from pagina e
    left join crm.leads l on l.id = e.lead_id
    left join crm.operaciones_cartera o on o.id = e.operacion_id
    left join public.perfiles p on p.id = o.cliente_id
  )
  select pg_catalog.jsonb_build_object('version', 1, 'analista_id', p_analista,
$despues$);
  if md5(v_def) not in ('46d9dd87b4d4d251a3b7695b0c927c21') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.conversion_episodios(timestamp with time zone, timestamp with time zone, date, boolean, uuid[], numeric)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.conversion_episodios(timestamp with time zone, timestamp with time zone, date, boolean, uuid[], numeric)'));
begin
  if v_def is null or md5(v_def) not in ('7e98a168466fd0dac92f181756257066', '98d3aa487aa7315301d08820bf55cce8') then
    raise exception 'Cambió private.conversion_episodios; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$
-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Desde octubre, el adicional de renovación cuenta como upgrade.
-- Una corrección manual explícita prevalece sobre la derivación por adicional.
-- Solo cambia la categoría del aporte: el registro y el capital no se alteran.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
$antes$, $despues$
-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Desde octubre, el adicional de renovación cuenta como upgrade.
-- Solo cambia la categoría del aporte: el registro y el capital no se alteran.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
$despues$);
  v_def := replace(v_def, $antes$    when o.categoria_conversion = 'upgrade' then 1 else 0 end
from (
  select o0.*,
    case when not o0.categoria_corregida and o0.tipo = 'renovacion'
      and o0.periodo >= date '2026-10-01'
      and o0.capital_adicional > 0
      then 'upgrade' else o0.tipo end as categoria_conversion,
$antes$, $despues$    when o.categoria_conversion = 'upgrade' then 1 else 0 end
from (
  select o0.*,
    case when o0.tipo = 'renovacion'
      and o0.periodo >= date '2026-10-01'
      and o0.capital_adicional > 0
      then 'upgrade' else o0.tipo end as categoria_conversion,
$despues$);
  v_def := replace(v_def, $antes$    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from private.operaciones_cartera_clasificadas() o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
$antes$, $despues$    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
$despues$);
  if md5(v_def) not in ('1e374f6b0d63d631272c675f66ed205a', 'be063cee167bd6864b2fa20f0b151aeb') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.conversion_cierres(timestamp with time zone, timestamp with time zone, date, boolean, uuid[], numeric, uuid[])
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.conversion_cierres(timestamp with time zone, timestamp with time zone, date, boolean, uuid[], numeric, uuid[])'));
begin
  if v_def is null or md5(v_def) not in ('11fcedd5fd2a9c0e8fe452082f7548bb') then
    raise exception 'Cambió private.conversion_cierres; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$from crm.lead_asignaciones la
join crm.leads l on l.id = la.lead_id
where la.resultado = 'convertido'
  -- La corrección también excluye captaciones antiguas de un mes todavía abierto.
  and not exists(select 1 from crm.correcciones_categoria_contrato x
    join public.contratos c on c.id=x.contrato_id
    where c.id=l.contrato_id and c.categoria<>'nuevo')
  -- La política previa conserva agosto y todos los meses anteriores.
  and (not exists(select 1 from crm.conversion_politica where activada_en is not null)
    or coalesce(la.resultado_en, la.finalizado_en) < '2026-09-01 00:00:00 America/Lima'::timestamptz)
$antes$, $despues$from crm.lead_asignaciones la
join crm.leads l on l.id = la.lead_id
where la.resultado = 'convertido'
  -- La política previa conserva agosto y todos los meses anteriores.
  and (not exists(select 1 from crm.conversion_politica where activada_en is not null)
    or coalesce(la.resultado_en, la.finalizado_en) < '2026-09-01 00:00:00 America/Lima'::timestamptz)
$despues$);
  if md5(v_def) not in ('df8e81953333c5bb07b536bb306571c2') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.conversion_acreditar_fuente(uuid, text, uuid, text)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.conversion_acreditar_fuente(uuid, text, uuid, text)'));
begin
  if v_def is null or md5(v_def) not in ('872930922a1d477e27b23243cbfe691a') then
    raise exception 'Cambió private.conversion_acreditar_fuente; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$    select c.fecha_cierre_comercial as fecha,c.creado_en as confirmado,
      c.cliente_id=v_lead.perfil_id as pertenece,
      coalesce(c.es_demo,false) as demo,
      c.categoria<>'nuevo' or (exists(select 1 from crm.operaciones_cartera o
        where o.contrato_nuevo_id=c.id) and not exists(select 1 from crm.correcciones_categoria_contrato x where x.contrato_id=c.id)) as cartera
    into v_fuente from public.contratos c where c.id=p_fuente_id;
  else
    select coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date) as fecha,
$antes$, $despues$    select c.fecha_cierre_comercial as fecha,c.creado_en as confirmado,
      c.cliente_id=v_lead.perfil_id as pertenece,
      coalesce(c.es_demo,false) as demo,
      c.categoria<>'nuevo' or exists(select 1 from crm.operaciones_cartera o
        where o.contrato_nuevo_id=c.id) as cartera
    into v_fuente from public.contratos c where c.id=p_fuente_id;
  else
    select coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date) as fecha,
$despues$);
  if md5(v_def) not in ('581462c4ecbdab349c18655f4850e010') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.conversion_exclusion_fuente(text, uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.conversion_exclusion_fuente(text, uuid)'));
begin
  if v_def is null or md5(v_def) not in ('ba11b6f937e4abd9aef9cf29dd21e333') then
    raise exception 'Cambió private.conversion_exclusion_fuente; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  select case p_tipo
    when 'contrato' then coalesce((select case
      when coalesce(c.es_demo,false) then 'fuente_demo'
      when c.categoria<>'nuevo' or (exists(select 1 from crm.operaciones_cartera o
        where o.contrato_nuevo_id=c.id) and not exists(select 1 from crm.correcciones_categoria_contrato x where x.contrato_id=c.id)) then 'operacion_cartera'
      else 'elegible' end from public.contratos c where c.id=p_id),'fuente_retirada')
    when 'cierre_externo' then coalesce((select case when ce.es_cierre_inicial
      then 'elegible' else 'operacion_cartera' end from crm.cierres_externos ce where ce.id=p_id),'fuente_retirada')
$antes$, $despues$  select case p_tipo
    when 'contrato' then coalesce((select case
      when coalesce(c.es_demo,false) then 'fuente_demo'
      when c.categoria<>'nuevo' or exists(select 1 from crm.operaciones_cartera o
        where o.contrato_nuevo_id=c.id) then 'operacion_cartera'
      else 'elegible' end from public.contratos c where c.id=p_id),'fuente_retirada')
    when 'cierre_externo' then coalesce((select case when ce.es_cierre_inicial
      then 'elegible' else 'operacion_cartera' end from crm.cierres_externos ce where ce.id=p_id),'fuente_retirada')
$despues$);
  if md5(v_def) not in ('a4572363b00484774768c9d3d314a6fd') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.trg_contrato_categoria_por_operacion()
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.trg_contrato_categoria_por_operacion()'));
begin
  if v_def is null or md5(v_def) not in ('c6248807290897e45c088ec1489f55a5') then
    raise exception 'Cambió private.trg_contrato_categoria_por_operacion; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$    raise exception 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED'
      using errcode = '25001',
            hint = 'La API ya trabaja en READ COMMITTED. En SQL: BEGIN ISOLATION LEVEL READ COMMITTED.';
  end if;
  -- Excepción estrecha: una corrección autorizada, auditada en esta transacción.
  if exists(select 1 from crm.correcciones_categoria_contrato x
    where x.contrato_id=new.id and x.actor_id=(select auth.uid())
      and x.transaccion=txid_current()
      and x.categoria_anterior is not distinct from old.categoria and x.categoria_nueva=new.categoria) then
    return new;
  end if;
  select o.tipo into v_tipo from crm.operaciones_cartera o where o.contrato_nuevo_id = new.id;
  v_con_operacion := found;
$antes$, $despues$    raise exception 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED'
      using errcode = '25001',
            hint = 'La API ya trabaja en READ COMMITTED. En SQL: BEGIN ISOLATION LEVEL READ COMMITTED.';
  end if;
  select o.tipo into v_tipo from crm.operaciones_cartera o where o.contrato_nuevo_id = new.id;
  v_con_operacion := found;
$despues$);
  if md5(v_def) not in ('28abb55cb3fe7ecaa08480814f870262') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.fijar_categoria_contrato(uuid, text, text, text, uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.fijar_categoria_contrato(uuid, text, text, text, uuid)'));
begin
  if v_def is null or md5(v_def) not in ('7983afed5e279504019c13489896e9e0') then
    raise exception 'Cambió private.fijar_categoria_contrato; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  if p_contrato_id is null
     or p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade')
     or v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300
     or p_via is null or p_via not in ('puerta', 'operacion_de_cartera', 'correccion_manual') then
    raise exception 'Datos inválidos para fijar la categoría del contrato' using errcode = '22023';
  end if;

  if p_via='correccion_manual' then
    if p_usuario_id is distinct from (select auth.uid()) then
      raise exception 'El actor de la corrección no coincide con la sesión' using errcode='42501';
    end if;
    perform private.exigir_correccion_categoria();
  end if;

  -- Candados en el orden del sello mensual: primero el del mes (el día comercial se lee SIN bloquear la fila), después la
$antes$, $despues$  if p_contrato_id is null
     or p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade')
     or v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300
     or p_via is null or p_via not in ('puerta', 'operacion_de_cartera') then
    raise exception 'Datos inválidos para fijar la categoría del contrato' using errcode = '22023';
  end if;

  -- Candados en el orden del sello mensual: primero el del mes (el día comercial se lee SIN bloquear la fila), después la
$despues$);
  v_def := replace(v_def, $antes$  select o.id, o.tipo into v_operacion_id, v_operacion_tipo
    from crm.operaciones_cartera o
   where o.contrato_nuevo_id = p_contrato_id;
  if p_via<>'correccion_manual' and v_operacion_id is not null then
    if p_categoria is distinct from v_operacion_tipo then
      raise exception 'La categoría la decide la operación de cartera'
        using errcode = '23514',
              detail = format('El contrato tiene una operación de cartera de tipo %s.', v_operacion_tipo);
    end if;
  elsif p_via<>'correccion_manual' and p_categoria <> 'nuevo' then
    raise exception 'Un contrato sin operación de cartera solo puede quedar como nuevo'
      using errcode = '23514',
            hint = 'Una renovación o un upgrade se registran por el flujo de cartera, que crea su operación.';
  end if;

  if p_via='correccion_manual' then
    if v_operacion_id is null and exists(select 1 from crm.operaciones_cartera where id=p_contrato_id) then
      raise exception 'La inversión requiere conciliación de identificadores' using errcode='P0409';
    end if;
    -- El trigger solo admite este permiso dentro de la misma transacción y actor.
    insert into crm.correcciones_categoria_contrato(contrato_id,actor_id,categoria_anterior,categoria_nueva,motivo)
      values(p_contrato_id,p_usuario_id,v_contrato.categoria,p_categoria,v_motivo);
  end if;

  -- Durante el UPDATE: sin contrato de origen declarado (si el observador de rentabilidad corre en ese momento, lo
$antes$, $despues$  select o.id, o.tipo into v_operacion_id, v_operacion_tipo
    from crm.operaciones_cartera o
   where o.contrato_nuevo_id = p_contrato_id;
  if v_operacion_id is not null then
    if p_categoria is distinct from v_operacion_tipo then
      raise exception 'La categoría la decide la operación de cartera'
        using errcode = '23514',
              detail = format('El contrato tiene una operación de cartera de tipo %s.', v_operacion_tipo);
    end if;
  elsif p_categoria <> 'nuevo' then
    raise exception 'Un contrato sin operación de cartera solo puede quedar como nuevo'
      using errcode = '23514',
            hint = 'Una renovación o un upgrade se registran por el flujo de cartera, que crea su operación.';
  end if;

  -- Durante el UPDATE: sin contrato de origen declarado (si el observador de rentabilidad corre en ese momento, lo
$despues$);
  v_def := replace(v_def, $antes$  perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_guc_previo, true);
  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', v_origen_previo, true);

  if p_via='correccion_manual' then
    perform private.sincronizar_conversion_categoria(p_contrato_id,p_categoria,v_motivo);
  end if;

  -- trg_audit_contratos ya guardó la fila completa (antes y después). Esta fila hermana guarda el motivo.
  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
$antes$, $despues$  perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_guc_previo, true);
  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', v_origen_previo, true);

  -- trg_audit_contratos ya guardó la fila completa (antes y después). Esta fila hermana guarda el motivo.
  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
$despues$);
  if md5(v_def) not in ('718e7e0f9c9112f3996d9fe0fbf85415') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.corregir_categoria_contrato_fn(uuid, text, text)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.corregir_categoria_contrato_fn(uuid, text, text)'));
begin
  if v_def is null or md5(v_def) not in ('b560705b4cfb9fd701dbc7e021d0e797') then
    raise exception 'Cambió crm.corregir_categoria_contrato_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_categoria text := nullif(btrim(p_categoria), '');
  v_motivo text := nullif(btrim(p_motivo), '');
begin
  perform private.exigir_correccion_categoria();
  if p_contrato_id is null then
    raise exception 'El contrato es obligatorio' using errcode = '22023';
  end if;
$antes$, $despues$AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_categoria text := nullif(btrim(p_categoria), '');
  v_motivo text := nullif(btrim(p_motivo), '');
begin
  if v_uid is null or v_rol is distinct from 'gerencia'
     or (select private.membresia_crm_revocada()) is not false then
    raise exception 'Solo Gerencia puede corregir la categoría de un contrato' using errcode = '42501';
  end if;
  if p_contrato_id is null then
    raise exception 'El contrato es obligatorio' using errcode = '22023';
  end if;
$despues$);
  v_def := replace(v_def, $antes$  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300 then
    raise exception 'El motivo debe tener entre 5 y 300 caracteres' using errcode = '22023';
  end if;
  return private.fijar_categoria_contrato(p_contrato_id, v_categoria, v_motivo, 'correccion_manual', v_uid);
end;
$function$
$antes$, $despues$  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300 then
    raise exception 'El motivo debe tener entre 5 y 300 caracteres' using errcode = '22023';
  end if;
  return private.fijar_categoria_contrato(p_contrato_id, v_categoria, v_motivo, 'puerta', v_uid);
end;
$function$
$despues$);
  if md5(v_def) not in ('1d55b75d685737215ed0771d1db1b539') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

drop function private.sincronizar_conversion_categoria(uuid,text,text);
drop function private.operaciones_cartera_clasificadas();
drop function private.exigir_correccion_categoria();
drop table crm.correcciones_categoria_contrato;
drop function private.trg_correccion_categoria_inmutable();
notify pgrst,'reload schema';
commit;
