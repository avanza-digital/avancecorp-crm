-- Reversa preparada. Requiere revisión/autorización; sin cambios de datos ni modo.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $preflight$
begin

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)')) is distinct from 'c8e51fc0bcebf9d5f9c7c85fce76134f' then raise exception 'La candidata cambió: revisar reversa de private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)'; end if;

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('private.enlazar_tasa_lead(uuid,uuid)')) is distinct from 'aa2cea0d964bad5a50ae68344f830a53' then raise exception 'La candidata cambió: revisar reversa de private.enlazar_tasa_lead(uuid,uuid)'; end if;

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('crm.solicitar_tasa_fn(jsonb)')) is distinct from 'cfcb0a610a8ce658cddc145ce1b8e6d5' then raise exception 'La candidata cambió: revisar reversa de crm.solicitar_tasa_fn(jsonb)'; end if;

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('private.rentabilidad_exigir_respuesta(uuid,text,uuid)')) is distinct from '146e0794373cc15e4bd110e850139d83' then raise exception 'La candidata cambió: revisar reversa de private.rentabilidad_exigir_respuesta(uuid,text,uuid)'; end if;

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('private.trg_contratos_observar_rentabilidad()')) is distinct from '58664972f2caf80b2d4557d541467340' then raise exception 'La candidata cambió: revisar reversa de private.trg_contratos_observar_rentabilidad()'; end if;

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid)')) is distinct from 'f6655428825fda40e8c7ba7a12cdddde' then raise exception 'La candidata cambió: revisar reversa de private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid)'; end if;

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('crm.resolver_tasa_lead_fn(uuid,text,uuid)')) is distinct from '0e550e7c422217246dad7c481f1f3d16' then raise exception 'La candidata cambió: revisar reversa de crm.resolver_tasa_lead_fn(uuid,text,uuid)'; end if;

if (select md5(pg_get_functiondef(oid)) from pg_proc where oid=to_regprocedure('crm.politica_rentabilidad_fn()')) is distinct from '9756dc2300ef1f76094d8265008d9e86' then raise exception 'La candidata cambió: revisar reversa de crm.politica_rentabilidad_fn()'; end if;

end;
$preflight$;

CREATE OR REPLACE FUNCTION private.validar_tasa_conversion_lead(p_lead uuid, p_cliente uuid, p_i jsonb, p_solo_pendientes boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_cliente uuid := coalesce(p_cliente,private.cliente_tasa_lead(p_lead));
 v_categoria text := coalesce(p_i->>'categoria','nuevo');
 v_origen uuid := (p_i->>'contrato_origen_id')::uuid;
 v_base numeric; v_tasa numeric; v_ahora timestamptz := clock_timestamp(); v_huella text; v_huella_lead text;
begin
 -- El caller conserva los locks de identidad/lead; operación viene después.
 perform private.rentabilidad_bloquear_operacion(v_cliente,v_categoria,v_origen);
 if exists(select 1 from crm.solicitudes_tasa s where
     (s.lead_id=p_lead or (v_cliente is not null and s.cliente_id=v_cliente and s.categoria=v_categoria
       and s.contrato_origen_id is not distinct from v_origen))
     and s.estado='pendiente' and s.vence_en>v_ahora) then
   raise exception 'La solicitud de tasa está pendiente de Gerencia. Espera su respuesta antes de convertir, incluso a la tasa base.' using errcode='P0411';
 end if;
 if exists(select 1 from crm.solicitudes_tasa s join crm.leads l on l.id=s.lead_id
   where s.lead_id=p_lead and s.documento_lead is not null
     and s.estado in ('pendiente','aprobada','aprobada_con_tope','aceptada_por_analista') and s.vence_en>v_ahora
     and (s.documento_lead is distinct from l.dni or (p_cliente is not null and s.documento_lead is distinct from (select p.dni from public.perfiles p where p.id=p_cliente)))) then
   raise exception 'El documento cambió después de solicitar la tasa. La aprobación no corresponde a esta persona.' using errcode='P0409';
 end if;
 if p_solo_pendientes then return; end if;
 if p_i is null or p_i='null'::jsonb then
   if exists(select 1 from crm.solicitudes_tasa s where s.lead_id=p_lead
     and s.estado in ('aprobada','aprobada_con_tope','aceptada_por_analista') and s.vence_en>v_ahora) then
     raise exception 'Confirma las condiciones de inversión desde la ficha del lead antes de convertir.' using errcode='P0410';
   end if;
   return; -- Cliente anterior sin propuesta: la base se controla igualmente al contratar.
 end if;
 if jsonb_typeof(p_i)<>'object' or (p_i->>'capital')::numeric is null
   or (p_i->>'capital')::numeric not between 100 and 100000000
   or coalesce(p_i->>'moneda','') not in ('PEN','USD')
   or coalesce(p_i->>'modalidad','') not in ('mensual','trimestral','semestral','anual')
   or coalesce(p_i->>'tipo_interes','') not in ('simple','compuesto')
   or (p_i->>'fecha_inicio')::date is null or (p_i->>'fecha_vencimiento')::date is null
   or (p_i->>'fecha_vencimiento')::date <= (p_i->>'fecha_inicio')::date then
   raise exception 'Completa las condiciones de inversión antes de convertir.' using errcode='22023';
 end if;
 v_base := (private.resolver_tasa(v_cliente,v_categoria,v_origen,v_ahora,null)->>'tasa_base')::numeric;
 v_tasa := (p_i->>'tasa_anual')::numeric;
 if v_tasa is null or v_tasa<private.rentabilidad_minimo_alta(v_categoria,v_base) or v_tasa>50 or v_tasa<>round(v_tasa,2) then
   raise exception 'La tasa no está dentro del rango permitido.' using errcode='P0410';
 end if;
 if v_tasa<=v_base then return; end if;
 -- Una reserva ya sellada conserva la validación del punto de no retorno.
 -- La vigencia ACTUAL sigue siendo obligatoria al crear el contrato (R4).
 select coalesce(r.efectos_iniciados_en,v_ahora) into v_ahora from crm.conversion_reservas r where r.lead_id=p_lead;
 v_ahora:=coalesce(v_ahora,clock_timestamp());
 v_huella:=private.huella_intencion_tasa(coalesce(v_cliente,p_lead),p_i);
 v_huella_lead:=private.huella_intencion_tasa(p_lead,p_i);
 if not exists(select 1 from crm.solicitudes_tasa s where
   ((s.lead_id=p_lead and s.huella in (v_huella,v_huella_lead)) or (s.cliente_id=v_cliente and s.huella=v_huella))
   and s.estado in ('aprobada','aceptada_por_analista') and s.vence_en>=v_ahora
   and s.tasa_maxima_autorizada>=v_tasa) then
   raise exception 'La tasa requiere una aprobación vigente para estas mismas condiciones. Si hubo un tope, acéptalo primero.' using errcode='P0410';
 end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.enlazar_tasa_lead(p_lead uuid, p_cliente uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s crm.solicitudes_tasa; v_huella text; v_previo text:=coalesce(current_setting('crm.solicitud_tasa_por_puerta',true),'off');
begin
 for v_s in select * from crm.solicitudes_tasa where lead_id=p_lead and cliente_id is distinct from p_cliente order by id for update loop
   if v_s.cliente_id is not null then raise exception 'La solicitud pertenece a otro cliente' using errcode='P0409'; end if;
   perform private.rentabilidad_bloquear_operacion(p_cliente,v_s.categoria,v_s.contrato_origen_id);
   v_huella:=private.huella_solicitud_tasa(p_cliente,v_s.categoria,v_s.contrato_origen_id,v_s.producto_condicion_id,
     v_s.capital,v_s.moneda,v_s.modalidad,v_s.tipo_interes,v_s.fecha_inicio,v_s.fecha_vencimiento);
   if v_s.estado in ('pendiente','aprobada','aprobada_con_tope','aceptada_por_analista') and exists(
     select 1 from crm.solicitudes_tasa s where s.id<>v_s.id and s.huella=v_huella
       and s.estado in ('pendiente','aprobada','aprobada_con_tope','aceptada_por_analista')) then
     raise exception 'Ya existe otra solicitud para esta inversión del cliente. Gerencia debe resolver la coincidencia antes de convertir.' using errcode='P0409';
   end if;
   perform set_config('crm.solicitud_tasa_por_puerta','on',true);
   update crm.solicitudes_tasa set cliente_id=p_cliente,huella_preconversion=coalesce(huella_preconversion,huella),huella=v_huella where id=v_s.id;
 end loop;
 perform set_config('crm.solicitud_tasa_por_puerta',v_previo,true);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.solicitar_tasa_fn(p_solicitud jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_lead uuid; v_cliente uuid; v_cat text; v_origen uuid; v_pc uuid; v_ctr uuid;
  v_capital numeric; v_moneda text; v_mod text; v_ti text; v_fi date; v_fv date;
  v_tasa numeric; v_motivo text;
  v_res jsonb; v_base numeric; v_tope numeric; v_dias integer; v_pol_id uuid;
  v_huella text; v_viva record; v_fila crm.solicitudes_tasa;
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
begin
  -- La AUTORIDAD se pregunta antes de mirar el JSON (auditor n2): un no autorizado muere en el 42501 uniforme sin
  -- distinguir «formato inválido»; el cliente (activo, rol cliente) se comprueba justo después de leerlo.
  if v_uid is null or not private.puede_registrar_ventas() then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if p_solicitud is null or jsonb_typeof(p_solicitud) <> 'object' then
    raise exception 'Faltan los datos de la solicitud' using errcode = '22023';
  end if;
  begin
    v_lead := (p_solicitud ->> 'lead_id')::uuid;
    v_cliente := (p_solicitud ->> 'cliente_id')::uuid;
    v_cat     := p_solicitud ->> 'categoria';
    v_origen  := (p_solicitud ->> 'contrato_origen_id')::uuid;
    v_pc      := (p_solicitud ->> 'producto_condicion_id')::uuid;
    v_capital := (p_solicitud ->> 'capital')::numeric;
    v_moneda  := p_solicitud ->> 'moneda';
    v_mod     := p_solicitud ->> 'modalidad';
    v_ti      := p_solicitud ->> 'tipo_interes';
    v_fi      := (p_solicitud ->> 'fecha_inicio')::date;
    v_fv      := (p_solicitud ->> 'fecha_vencimiento')::date;
    v_tasa    := round((p_solicitud ->> 'tasa_solicitada')::numeric, 2);   -- misma escala que contratos.tasa_anual (auditor m5)
    v_motivo  := btrim(p_solicitud ->> 'motivo');
    -- R4: contexto de CORRECCIÓN. El contrato que se está corrigiendo se pasa al núcleo como p_contrato_nuevo_id, para
    -- que un origen «ya renovado POR ESE contrato» siga siendo su origen válido. Sin esto no se puede ni PEDIR
    -- autorización para corregir la tasa de una renovación: el núcleo la rechaza por origen cerrado (Codex R4 #3).
    v_ctr     := (p_solicitud ->> 'contrato_id')::uuid;
  exception when others then
    raise exception 'Datos de la solicitud inválidos' using errcode = '22023';
  end;
  if v_lead is not null then
    perform private.exigir_operar_tasa_lead(v_lead);
    if v_cliente is not null and v_cliente is distinct from private.cliente_tasa_lead(v_lead) then
      raise exception 'El cliente no corresponde a este lead' using errcode='42501';
    end if;
    v_cliente := private.cliente_tasa_lead(v_lead);
    if v_ctr is not null then raise exception 'Una corrección se solicita desde el contrato' using errcode='22023'; end if;
  elsif not private.puede_operar_tasa_cliente(v_cliente) then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if v_capital is null or v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000' using errcode = '22023';
  end if;
  if v_moneda is null or v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;
  if v_mod is null or v_mod not in ('mensual', 'trimestral', 'semestral', 'anual')
     or v_ti is null or v_ti not in ('simple', 'compuesto') then
    raise exception 'Modalidad o tipo de interés inválidos' using errcode = '22023';
  end if;
  if v_fi is null or v_fv is null or v_fv <= v_fi then
    raise exception 'El plazo del contrato es inválido' using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 500 then
    raise exception 'Escribe el motivo comercial (entre 5 y 500 caracteres)' using errcode = '22023';
  end if;
  if v_tasa is null or v_tasa <= 0 then
    raise exception 'La tasa solicitada es inválida' using errcode = '22023';
  end if;

  perform private.vencer_solicitudes_tasa();
  -- EL NÚCLEO decide la base y la regla; esta puerta no calcula tasa.
  v_res := private.resolver_tasa(v_cliente, v_cat, v_origen, statement_timestamp(), v_ctr);
  v_base := (v_res ->> 'tasa_base')::numeric;
  v_tope := (v_res #>> '{politica,tope_tecnico}')::numeric;
  v_dias := (v_res #>> '{politica,vigencia_solicitud_dias}')::integer;
  v_pol_id := (v_res #>> '{politica,id}')::uuid;
  if v_tasa <= v_base then
    raise exception 'La excepción debe ser superior a la tasa base de % %%', rtrim(rtrim(to_char(v_base, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;
  if v_tasa > v_tope then
    raise exception 'La tasa solicitada supera el tope técnico de % %%', rtrim(rtrim(to_char(v_tope, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;

  perform private.rentabilidad_bloquear_operacion(v_cliente, v_cat, v_origen);
  perform private.exigir_sin_conversion_tasa(v_lead,v_cliente);
  if v_lead is not null and exists(select 1 from crm.solicitudes_tasa s join crm.leads l2 on l2.id=s.lead_id
    join crm.leads l on l.id=v_lead where s.lead_id<>v_lead
      and ((l.dni is not null and l.dni=l2.dni)
        or (l.inversionista_id is not null and private.inversionista_canonica(l.inversionista_id)=private.inversionista_canonica(l2.inversionista_id)))
      and s.estado in ('pendiente','aprobada','aprobada_con_tope','aceptada_por_analista') and s.vence_en>clock_timestamp()) then
    raise exception 'Esta persona tiene una solicitud en otro lead. Revisa la coincidencia con Gerencia antes de enviar otra.' using errcode='P0409';
  end if;
  if v_lead is not null and exists(select 1 from crm.solicitudes_tasa s
    where (s.lead_id=v_lead or (v_cliente is not null and s.cliente_id=v_cliente and s.categoria=v_cat
      and s.contrato_origen_id is not distinct from v_origen))
      and s.estado='pendiente' and s.vence_en>clock_timestamp()) then
    raise exception 'La solicitud de tasa está pendiente de Gerencia. Espera su respuesta.' using errcode='P0411';
  end if;
  v_huella := private.huella_solicitud_tasa(coalesce(v_cliente,v_lead), v_cat, v_origen, v_pc, v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv);
  perform pg_advisory_xact_lock(hashtext('crm.solicitudes_tasa'), hashtext(v_huella));
  select s.id, s.estado, s.solicitada_por into v_viva from crm.solicitudes_tasa s
   where s.huella = v_huella
     and s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
   limit 1;
  if v_viva.id is not null then
    raise exception 'Ya hay una solicitud viva para este contrato (estado «%»)', v_viva.estado
      using errcode = 'P0409',
            detail = jsonb_build_object('solicitud_id', v_viva.id, 'estado', v_viva.estado, 'solicitada_por', v_viva.solicitada_por,
                                        'propia', v_viva.solicitada_por = v_uid)::text;
  end if;

  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  insert into crm.solicitudes_tasa (
    politica_id, lead_id, documento_lead, cliente_id, categoria, contrato_origen_id, contrato_origen_numero, producto_condicion_id,
    capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, huella,
    tasa_base, regla_base, contratos_previos, prioridad_bandeja, tasa_solicitada, motivo,
    estado, solicitada_por, solicitada_en, vence_en
  ) values (
    v_pol_id, v_lead, (select dni from crm.leads where id=v_lead), v_cliente, v_cat, v_origen, v_res #>> '{contrato_origen,numero_contrato}', v_pc,
    v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv, v_huella,
    v_base, v_res ->> 'regla', (v_res ->> 'contratos_previos')::integer, (v_res ->> 'prioridad_bandeja')::boolean, v_tasa, v_motivo,
    'pendiente', v_uid, statement_timestamp(), statement_timestamp() + make_interval(days => v_dias)
  ) returning * into v_fila;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return to_jsonb(v_fila) || jsonb_build_object('ok', true, 'resolucion', v_res);
end;
$function$
;

CREATE OR REPLACE FUNCTION private.rentabilidad_exigir_respuesta(p_cliente uuid, p_categoria text, p_origen uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform private.rentabilidad_bloquear_operacion(p_cliente, p_categoria, p_origen);
  if exists (
    select 1 from crm.solicitudes_tasa s
    where s.cliente_id = p_cliente and s.categoria = p_categoria
      and s.contrato_origen_id is not distinct from p_origen
      and s.estado = 'pendiente' and s.vence_en > pg_catalog.clock_timestamp()
  ) then
    raise exception 'La solicitud de tasa está pendiente de Gerencia. Espera su respuesta antes de crear el contrato, incluso a la tasa base.'
      using errcode = 'P0411';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.trg_contratos_observar_rentabilidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
declare
  v_c          public.contratos%rowtype;   -- el estado FINAL de la fila al commit (no la imagen del evento; Codex R2 #4)
  v_xid        text := pg_current_xact_id()::text;
  v_marca      text := 'crm.r2_obs_' || replace(new.id::text, '-', '');   -- GUC transaccional: «este contrato ya se procesó en esta tx»
  v_pol        crm.politica_rentabilidad;
  v_prev       record;
  v_prev_id    uuid;
  v_conservada boolean := false;
  v_pol_id     uuid;
  v_origen     uuid;
  v_candidatos integer := 0;
  v_cand_id    uuid;
  v_cand_num   text;
  v_cand_tasa  numeric;
  v_res        jsonb;
  v_base       numeric;
  v_regla      text;
  v_motivo     text;
  v_cambios    jsonb;
  v_detalle    jsonb;
  -- R4 (el candado)
  v_modo       text;               -- modo de la política vigente (null = no se pudo leer)
  v_enforce    boolean := false;
  v_anotar     boolean := true;    -- ¿toca escribir la fila del libro en esta transacción?
  v_en_juego   boolean := false;   -- ¿esta transacción fija o altera la tasa (o la intención que la amparaba)?
  v_huella_mov boolean := false;   -- ¿cambió alguna dimensión de la huella autorizada?
  v_rechazo    text;               -- motivo del rechazo (se lanza FUERA del manejador)
  v_origen_dec uuid;               -- origen DECLARADO por la puerta (upgrade, D2)
  v_cond       uuid;               -- condición DECLARADA (null cuando es el snapshot legacy del puente)
  v_aut        jsonb;
  v_solicitud  uuid;
begin
 -- TODO el cuerpo va bajo una excepción externa: el observador no puede abortar un alta ni una corrección. lock_timeout=2s
 -- convierte una espera de candado en 55P03 (atrapable). Lo único que WHEN OTHERS no atrapa es query_canceled (57014):
 -- en PostgreSQL 17 statement_timeout se desactiva antes del commit, y aquí no hay más esperas que las de candado.
 begin
  select * into v_c from public.contratos c where c.id = new.id;
  if v_c.id is null then
    return null;   -- borrado en la misma transacción: nada que observar
  end if;
  -- UNA fila de libro por contrato y transacción: varios eventos (alta + correcciones en la misma tx) → una sola foto
  -- FINAL. El marcador es un GUC transaccional (se fija también cuando el cambio neto es vacío: 15→18→15 no es una
  -- corrección; Codex R2 #25). OJO (Codex R4 #4): el marcador decide solo si se ESCRIBE en el libro; NO exime de
  -- validar. Con SET CONSTRAINTS ALL IMMEDIATE a mitad de transacción el trigger vuelve a dispararse, y antes se
  -- saltaba la comprobación: un alta válida servía de pasaporte a una corrección no autorizada.
  v_anotar := coalesce(current_setting(v_marca, true), '') <> '1';
  perform set_config(v_marca, '1', true);
  if tg_op = 'UPDATE' then
    -- Solo si cambió algo que determine la regla o el margen (Codex R2 #5), comparando la imagen previa con el estado final.
    v_cambios := jsonb_strip_nulls(jsonb_build_object(
      'tasa_anual',        case when old.tasa_anual        is distinct from v_c.tasa_anual        then jsonb_build_array(old.tasa_anual, v_c.tasa_anual) end,
      'categoria',         case when old.categoria         is distinct from v_c.categoria         then jsonb_build_array(old.categoria, v_c.categoria) end,
      'cliente_id',        case when old.cliente_id        is distinct from v_c.cliente_id        then jsonb_build_array(old.cliente_id, v_c.cliente_id) end,
      'capital',           case when old.capital           is distinct from v_c.capital           then jsonb_build_array(old.capital, v_c.capital) end,
      'moneda',            case when old.moneda            is distinct from v_c.moneda            then jsonb_build_array(old.moneda, v_c.moneda) end,
      'fecha_inicio',      case when old.fecha_inicio      is distinct from v_c.fecha_inicio      then jsonb_build_array(old.fecha_inicio, v_c.fecha_inicio) end,
      'fecha_vencimiento', case when old.fecha_vencimiento is distinct from v_c.fecha_vencimiento then jsonb_build_array(old.fecha_vencimiento, v_c.fecha_vencimiento) end,
      -- R4 (Codex #1): la huella de una autorización también lleva modalidad, tipo de interés y producto. Si no se
      -- comparan, una autorización para 20 000 a 12 meses ampara luego 100 000 a 24: bastaba corregir el capital.
      'modalidad',         case when old.modalidad             is distinct from v_c.modalidad             then jsonb_build_array(old.modalidad, v_c.modalidad) end,
      'tipo_interes',      case when old.tipo_interes          is distinct from v_c.tipo_interes          then jsonb_build_array(old.tipo_interes, v_c.tipo_interes) end,
      -- Se compara la condición DECLARADA, no el id crudo: el puente legacy sintetiza un snapshot NUEVO en cada
      -- cambio de términos, y eso no mueve la huella (declarada = null en las dos orillas). Cambiar de producto de
      -- catálogo sí la mueve.
      'producto_condicion_id', case when private.rentabilidad_condicion_declarada(old.producto_condicion_id)
                                      is distinct from private.rentabilidad_condicion_declarada(v_c.producto_condicion_id)
                                    then jsonb_build_array(old.producto_condicion_id, v_c.producto_condicion_id) end,
      -- R4 (Codex #6): pasar un contrato de prueba a real es un cambio de rentabilidad como cualquier otro.
      'es_demo',           case when old.es_demo               is distinct from v_c.es_demo               then jsonb_build_array(old.es_demo, v_c.es_demo) end));
    if v_cambios = '{}'::jsonb then
      return null;
    end if;
  end if;
  v_pol := private.politica_rentabilidad_vigente(statement_timestamp());
  if v_pol.id is null then
    return null;   -- sin política publicada no se observa (R1 garantiza la v1)
  end if;
  -- R4: el interruptor. En «observacion» este trigger hace EXACTAMENTE lo de R2 (mide, no bloquea).
  v_modo := v_pol.modo;
  v_enforce := (v_modo = 'enforcement');

  -- En una CORRECCIÓN que no cambia cliente ni categoría, la base de comparación es la RESOLUCIÓN ORIGINAL del alta
  -- (base, regla, origen), no una reevaluación con el estado de hoy (Codex R2 #8). Si cambió cliente o categoría, se resuelve de nuevo.
  v_pol_id := v_pol.id;
  if tg_op = 'UPDATE' and not (v_cambios ? 'categoria' or v_cambios ? 'cliente_id') then
    -- Solo se conserva una resolución del MISMO cliente y la MISMA categoría (Codex R2 #20), con la política que la produjo (#21).
    select l.tasa_base, l.regla, l.contrato_origen_id, l.politica_id, l.id, l.detalle ->> 'motivo' as motivo into v_prev
    from crm.ledger_rentabilidad l
    where l.contrato_id = v_c.id and l.origen in ('observacion', 'enforcement')
      and l.categoria = v_c.categoria and l.cliente_id = v_c.cliente_id
    order by l.secuencia asc limit 1;
    if v_prev.regla is not null then
      -- Se conserva la resolución original… y también su INCERTIDUMBRE (Codex #8): un sin_regla no se «resuelve» al corregir.
      v_regla := v_prev.regla; v_origen := v_prev.contrato_origen_id; v_pol_id := v_prev.politica_id; v_prev_id := v_prev.id; v_conservada := true;
      if v_prev.regla = 'sin_regla' then
        v_base := v_c.tasa_anual; v_motivo := coalesce(v_prev.motivo, 'sin_motivo');
      else
        v_base := v_prev.tasa_base;
      end if;
    end if;
  end if;

  -- El origen declarado se lee UNA sola vez: la lectura consume la declaración, para que un segundo contrato de la
  -- misma transacción no herede la del primero (Codex R4 #5).
  if v_c.categoria = 'upgrade' then
    v_origen_dec := private.rentabilidad_origen_declarado(v_c);
  end if;
  if not v_conservada then
    begin
      if v_c.categoria is null then
        v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'categoria_nula';
      elsif v_c.categoria = 'renovacion' then
        select o.contrato_origen_id into v_origen from crm.operaciones_cartera o where o.contrato_nuevo_id = v_c.id;
        if v_origen is null then
          v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'renovacion_sin_origen_registrado';
        else
          v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, v_origen, statement_timestamp(), v_c.id);
          v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla';
        end if;
      elsif v_c.categoria = 'upgrade' and v_origen_dec is not null then
        -- D2: el upgrade DECLARA el contrato que amplía. R4: la puerta del CRM lo publica y aquí SÍ es una regla
        -- (heredada_upgrade), no una hipótesis.
        v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, v_origen_dec, statement_timestamp(), v_c.id);
        v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla'; v_origen := v_origen_dec;
      elsif v_c.categoria = 'upgrade' then
        -- Sin declaración (portal, RPC antigua, alta anterior a R3) se mantiene lo de R2: solo se apunta el candidato
        -- único —contrato activo del cliente que ya EXISTÍA antes y seguía vigente al inicio del nuevo— como
        -- hipótesis, y queda sin_regla (una inferencia no es una regla; Codex R2 #7). Bajo enforcement se rechaza.
        select count(*), min(c.id::text)::uuid into v_candidatos, v_origen
        from public.contratos c
        where c.cliente_id = v_c.cliente_id and c.id <> v_c.id and c.estado = 'activo' and c.renovado_a_id is null
          and not c.es_demo and c.creado_en < v_c.creado_en and c.fecha_vencimiento >= v_c.fecha_inicio;
        if v_candidatos = 1 then
          select c.id, c.numero_contrato, c.tasa_anual into v_cand_id, v_cand_num, v_cand_tasa from public.contratos c where c.id = v_origen;
          v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'upgrade_origen_inferido';
        else
          v_origen := null; v_regla := 'sin_regla'; v_base := v_c.tasa_anual;
          v_motivo := case when v_candidatos = 0 then 'upgrade_sin_contrato_activo_previo' else 'upgrade_origen_ambiguo' end;
        end if;
        v_origen := null;   -- sin origen DEMOSTRADO no se anota como origen; el candidato va en detalle
      else
        v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, null, statement_timestamp(), v_c.id);
        v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla';
      end if;
    exception when others then
      -- El núcleo no pudo decidir (cliente inactivo, origen raro…): se anota, no se bloquea.
      v_regla := 'sin_regla'; v_base := v_c.tasa_anual;
      v_motivo := 'resolver:' || sqlstate || ':' || left(sqlerrm, 160);
      v_res := null; v_origen := null;
    end;
  end if;

  -- ── R4 · EL CANDADO ──────────────────────────────────────────────────────────────────────────────────────────
  -- Solo con la política en enforcement, y nunca sobre datos de prueba. La tasa se juzga cuando ESTA transacción la
  -- fija (alta), la cambia (corrección) o mueve la INTENCIÓN que amparaba una tasa excepcional: conservar una tasa
  -- por encima de la base exige conservar el contrato que Gerencia autorizó (Codex R4 #1).
  if v_enforce and v_c.es_demo is not true then
    v_huella_mov := (tg_op = 'UPDATE') and (v_cambios ?| array['capital', 'moneda', 'fecha_inicio', 'fecha_vencimiento',
                     'modalidad', 'tipo_interes', 'producto_condicion_id', 'categoria', 'cliente_id']);
    v_en_juego := (tg_op = 'INSERT')
      or (v_cambios ? 'tasa_anual')
      -- Pasar de prueba a real es un alta a efectos de la política.
      or (v_cambios ? 'es_demo')
      -- Tasa por encima de la base + intención movida = la autorización ya no ampara esto.
      or (v_huella_mov and v_base is not null and v_c.tasa_anual is distinct from v_base);
    if v_en_juego then
      if v_regla = 'sin_regla' then
        -- Sin regla no hay base con la que comparar: bajo enforcement no pasa, y se dice qué falta.
        v_rechazo := case coalesce(v_motivo, '')
          when 'categoria_nula' then 'El contrato debe declarar su categoría (nuevo, renovación o upgrade).'
          when 'renovacion_sin_origen_registrado' then 'La renovación debe declarar el contrato que renueva.'
          when 'upgrade_origen_inferido' then 'El upgrade debe declarar el contrato que amplía: regístralo desde el CRM.'
          when 'upgrade_origen_ambiguo' then 'El upgrade debe declarar el contrato que amplía: regístralo desde el CRM.'
          when 'upgrade_sin_contrato_activo_previo' then 'Un upgrade amplía un contrato activo del cliente y no se encontró ninguno.'
          else 'No se pudo determinar qué tasa corresponde a este contrato (' || coalesce(v_motivo, 'sin motivo') || '). La tasa la decide la política.'
        end;
      elsif v_c.tasa_anual < v_base and not (
        v_c.categoria='nuevo'
        and v_c.tasa_anual >= private.rentabilidad_minimo_alta(v_c.categoria,v_base)
        and (tg_op='INSERT' or (tg_op='UPDATE'
          and old.categoria='nuevo' and old.es_demo is not true
          and old.cliente_id is not distinct from v_c.cliente_id
          and old.tasa_anual is not distinct from v_c.tasa_anual))
      ) then
        -- D4 revisada: el alta nueva admite una tasa menor. Una corrección solo
        -- conserva esa tasa; no concede permiso para rebajar contratos emitidos.
        v_rechazo := 'La tasa de este contrato la fija la política: ' || private.rentabilidad_tasa_txt(v_base)
          || '%, y no puede quedar por debajo. Corrige la tasa antes de guardar.';
      elsif v_c.tasa_anual > v_base then
        -- Por encima de la base: solo pasa con una autorización VIVA de Gerencia para esta MISMA intención (huella),
        -- que se consume aquí, en esta transacción y de un solo uso.
        v_cond := private.rentabilidad_condicion_declarada(v_c.producto_condicion_id);
        v_aut := private.rentabilidad_consumir_autorizacion(v_c, v_base, v_origen, v_cond, statement_timestamp());
        if v_aut is null then
          v_rechazo := 'La tasa de este contrato la fija la política: ' || private.rentabilidad_tasa_txt(v_base)
            || '%. Para cerrar a ' || private.rentabilidad_tasa_txt(v_c.tasa_anual)
            || '% hace falta una autorización vigente de Gerencia para estos mismos datos (cliente, capital, plazo, modalidad y origen).';
        else
          v_solicitud := (v_aut ->> 'solicitud_id')::uuid;
        end if;
      end if;
    end if;
  end if;

  v_detalle := jsonb_strip_nulls(jsonb_build_object(
    'xid', v_xid, 'evento', tg_op,
    'capital', v_c.capital, 'moneda', v_c.moneda,
    'fecha_inicio', v_c.fecha_inicio, 'fecha_vencimiento', v_c.fecha_vencimiento,
    'plazo_dias', (v_c.fecha_vencimiento - v_c.fecha_inicio),
    'analista_cierre_id', v_c.analista_cierre_id, 'creado_por', v_c.creado_por,
    'es_demo', v_c.es_demo, 'estado', v_c.estado, 'operacion', tg_op,
    'tasa_anterior', case when tg_op = 'UPDATE' then old.tasa_anual end,
    'tasa_inferior_sin_excepcion', case when v_c.categoria='nuevo' and v_c.tasa_anual<v_base then true end,
    'cambios', case when tg_op = 'UPDATE' then v_cambios end,
    'base_conservada', case when v_conservada then true end,
    'observacion_base_id', v_prev_id,
    'politica_vigente_al_observar', v_pol.version,
    'motivo', v_motivo,
    'candidato_origen', case when v_cand_id is null then null else jsonb_build_object('id', v_cand_id, 'numero_contrato', v_cand_num, 'tasa_anual', v_cand_tasa) end,
    'politica_version', (select pp.version from crm.politica_rentabilidad pp where pp.id = v_pol_id),
    'modo', v_modo,
    'tasa_en_juego', case when v_enforce then v_en_juego end,
    'huella_movida', case when v_enforce and tg_op = 'UPDATE' then v_huella_mov end,
    'autorizacion', v_aut,
    'origen_declarado', v_origen_dec,
    'resolucion', case when v_res is null then null else v_res - 'politica' - 'cliente_id' - 'categoria' end
  ));
  -- Si el candado rechaza no se anota nada (la transacción se aborta unas líneas más abajo); y solo se escribe UNA
  -- fila por contrato y transacción. OJO: no se puede «return» aquí — un return sale de la función y el rechazo, que
  -- vive fuera del manejador, nunca se lanzaría.
  if v_rechazo is null and v_anotar then
  begin
    insert into crm.ledger_rentabilidad (
      contrato_id, numero_contrato, cliente_id, categoria, contrato_origen_id, politica_id, solicitud_id,
      tasa_base, tasa_final, tasa_recibida, regla, origen, actor_id, detalle
    ) values (
      v_c.id, v_c.numero_contrato, v_c.cliente_id, v_c.categoria, v_origen, v_pol_id, v_solicitud,
      v_base, v_c.tasa_anual, v_c.tasa_anual, v_regla,
      case when v_enforce then 'enforcement' else 'observacion' end, (select auth.uid()), v_detalle
    );
  exception when others then
    if v_enforce then
      -- Bajo enforcement no puede pasar un contrato SIN su fila en el libro: el candado también falla cerrado aquí.
      v_rechazo := 'No se pudo registrar la tasa de este contrato en el libro de rentabilidad (' || sqlstate || '). Reintenta.';
    else
      raise warning 'RENTABILIDAD R2: no se pudo observar el contrato % (% %)', v_c.id, sqlstate, sqlerrm;
    end if;
  end;
  end if;
 exception when others then
  if v_enforce then
    -- Bajo enforcement el candado FALLA CERRADO: si no pudo verificar la tasa, el contrato no pasa. La vuelta atrás
    -- es publicar la política en «observacion» (sin migración).
    v_rechazo := 'No se pudo verificar la tasa contra la política de rentabilidad (' || sqlstate || '). Reintenta; si persiste, avisa a Gerencia.';
  else
    -- Límite DECLARADO y deliberado (frente a Codex R4 #7): si el fallo impidió incluso LEER el modo, v_enforce sigue
    -- en false y el contrato pasa. Fallar cerrado ahí convertiría un problema al leer una tabla de una fila en una
    -- parada de TODAS las altas mientras el candado está apagado, que es justo lo que estas fases prometen no hacer.
    -- El contrato queda sin fila en el libro, así que la tarjeta de Gerencia lo cuenta como hueco de cobertura.
    raise warning 'RENTABILIDAD R2: el observador falló y se ignora (% %) en el contrato %', sqlstate, sqlerrm, new.id;
  end if;
 end;

 -- Fuera del manejador de observación: ni los errores ni P0411 se ignoran.
 -- R4 ya resolvió el origen y consumió su GUC una sola vez; no volver a leerlo.
 if tg_op = 'INSERT' and v_c.id is not null and v_c.es_demo is not true then
   perform private.rentabilidad_exigir_respuesta(v_c.cliente_id, v_c.categoria, coalesce(v_origen, v_origen_dec));
 end if;
 -- El rechazo vive AQUÍ, fuera del manejador: dentro, el propio WHEN OTHERS se lo tragaría.
 if v_rechazo is not null then
   raise exception '%', v_rechazo using errcode = 'P0410';
 end if;
 return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.resolver_tasa(p_cliente_id uuid, p_categoria text, p_contrato_origen_id uuid, p_instante timestamp with time zone, p_contrato_nuevo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pol      crm.politica_rentabilidad;
  v_cli      record;
  v_origen   public.contratos%rowtype;
  v_previos  integer;
  v_activos  integer;
  v_base     numeric;
  v_regla    text;
begin
  -- Sin perfil aún: únicamente una intención nueva sin origen; misma política central.
  if p_cliente_id is null and (p_categoria is distinct from 'nuevo' or p_contrato_origen_id is not null) then
    raise exception 'Una renovación o ampliación requiere su cliente y contrato origen' using errcode='22023';
  end if;
  if p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (nuevo, renovacion o upgrade)' using errcode = '22023';
  end if;
  v_pol := private.politica_rentabilidad_vigente(p_instante);
  if v_pol.id is null then
    raise exception 'No hay política de rentabilidad vigente' using errcode = 'P0002';
  end if;
  select p.id, p.activo, p.asesor_perfil_id into v_cli
  from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente';
  if p_cliente_id is not null and v_cli.id is null then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  if p_cliente_id is not null and v_cli.activo is not true then
    raise exception 'El cliente está inactivo' using errcode = 'P0409';
  end if;
  -- «Previos» = los contratos del cliente sin contar el que se está observando (al commit, el nuevo ya existe).
  select count(*), count(*) filter (where c.estado = 'activo')
    into v_previos, v_activos
  from public.contratos c
  where c.cliente_id = p_cliente_id and not c.es_demo and c.id is distinct from p_contrato_nuevo_id;

  if p_categoria = 'nuevo' then
    if p_contrato_origen_id is not null then
      raise exception 'Una primera inversión no lleva contrato origen' using errcode = '22023';
    end if;
    v_base := v_pol.tasa_base_nueva;
    v_regla := 'primera_inversion';
  else
    if p_contrato_origen_id is null then
      raise exception 'Selecciona el contrato que se % (contrato origen)', case when p_categoria = 'renovacion' then 'renueva' else 'amplía' end
        using errcode = '22023';
    end if;
    select * into v_origen from public.contratos c where c.id = p_contrato_origen_id;
    if v_origen.id is null then
      raise exception 'El contrato origen no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from p_cliente_id then
      raise exception 'El contrato origen pertenece a otro cliente' using errcode = 'P0409';
    end if;
    if p_categoria = 'renovacion' then
      -- Mismo criterio que public.crear_contrato: se renueva un contrato activo o vencido que aún no fue renovado…
      -- …salvo que ya haya quedado renovado POR ESTE contrato (observación al commit): sigue siendo su origen.
      -- IS NOT TRUE (no «NOT»): con renovado_a_id NULL la segunda alternativa es NULL y un «NOT NULL» dejaría pasar un
      -- origen retirado (Codex R2 #3). La segunda alternativa exige además estado 'renovado'.
      if (
           (v_origen.estado in ('activo', 'vencido') and v_origen.renovado_a_id is null)
        or (p_contrato_nuevo_id is not null and v_origen.estado = 'renovado' and v_origen.renovado_a_id = p_contrato_nuevo_id)
      ) is not true then
        raise exception 'El contrato origen ya fue cerrado o renovado (estado «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_renovacion';
    else
      -- D2: el upgrade amplía un contrato ACTIVO concreto que el analista selecciona.
      if v_origen.estado <> 'activo' or v_origen.renovado_a_id is not null then
        raise exception 'El upgrade solo amplía un contrato activo (este está «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_upgrade';
    end if;
    v_base := v_origen.tasa_anual;
  end if;

  return jsonb_build_object(
    'tasa_base', v_base,
    'tasa_minima_sin_autorizacion', private.rentabilidad_minimo_alta(p_categoria, v_base),
    'regla', v_regla,
    'categoria', p_categoria,
    'cliente_id', p_cliente_id,
    'contrato_origen', case when v_origen.id is null then null else jsonb_build_object(
        'id', v_origen.id, 'numero_contrato', v_origen.numero_contrato, 'tasa_anual', v_origen.tasa_anual,
        'estado', v_origen.estado, 'moneda', v_origen.moneda, 'capital', v_origen.capital,
        'fecha_vencimiento', v_origen.fecha_vencimiento) end,
    'contratos_previos', v_previos,
    'contratos_activos', v_activos,
    'prioridad_bandeja', (p_categoria = 'nuevo' and v_previos > 0),
    'politica', jsonb_build_object('id', v_pol.id, 'version', v_pol.version, 'modo', v_pol.modo,
        'tasa_base_nueva', v_pol.tasa_base_nueva, 'tope_tecnico', v_pol.tope_tecnico,
        'vigencia_solicitud_dias', v_pol.vigencia_solicitud_dias),
    'resuelto_en', coalesce(p_instante, statement_timestamp())
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.resolver_tasa_lead_fn(p_lead_id uuid, p_categoria text DEFAULT 'nuevo'::text, p_contrato_origen_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cliente uuid; v_bloqueo text;
begin
 if not private.puede_ver_tasa_lead(p_lead_id) then
   raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
 end if;
 v_cliente:=private.cliente_tasa_lead(p_lead_id);
 if exists(select 1 from crm.solicitudes_tasa s where
   (s.lead_id=p_lead_id or (v_cliente is not null and s.cliente_id=v_cliente and s.categoria=p_categoria
     and s.contrato_origen_id is not distinct from p_contrato_origen_id))
   and s.estado='pendiente' and s.vence_en>statement_timestamp()) then
   v_bloqueo:='La solicitud de tasa está pendiente de Gerencia. Espera su respuesta antes de convertir, incluso a la tasa base.';
 end if;
 return private.resolver_tasa(v_cliente,p_categoria,p_contrato_origen_id,statement_timestamp(),null)
   || jsonb_build_object('lead_id',p_lead_id,'bloqueo_conversion',v_bloqueo);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.politica_rentabilidad_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_vig crm.politica_rentabilidad;
  v_max integer;
  v_hist jsonb;
begin
  if v_uid is null or not (private.rol_crm(v_uid) is not null or private.es_lector_global()) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_vig := private.politica_rentabilidad_vigente(statement_timestamp());
  select max(p.version) into v_max from crm.politica_rentabilidad p;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'version', p.version, 'vigente_desde', p.vigente_desde, 'tasa_base_nueva', p.tasa_base_nueva,
    'regla_renovacion', p.regla_renovacion, 'regla_upgrade', p.regla_upgrade, 'tope_tecnico', p.tope_tecnico,
    'vigencia_solicitud_dias', p.vigencia_solicitud_dias, 'modo', p.modo, 'nota', p.nota,
    'publicada_por', p.publicada_por, 'publicada_por_nombre', pe.nombre_completo, 'publicada_en', p.publicada_en,
    'es_vigente', (p.id = v_vig.id)
  ) order by p.version desc), '[]'::jsonb)
  into v_hist
  from crm.politica_rentabilidad p left join public.perfiles pe on pe.id = p.publicada_por;
  return jsonb_build_object(
    'version', 1,
    'vigente', case when v_vig.id is null then null else jsonb_build_object(
      'id', v_vig.id, 'version', v_vig.version, 'vigente_desde', v_vig.vigente_desde, 'tasa_base_nueva', v_vig.tasa_base_nueva,
      'regla_renovacion', v_vig.regla_renovacion, 'regla_upgrade', v_vig.regla_upgrade, 'tope_tecnico', v_vig.tope_tecnico,
      'vigencia_solicitud_dias', v_vig.vigencia_solicitud_dias, 'modo', v_vig.modo, 'nota', v_vig.nota, 'publicada_en', v_vig.publicada_en) end,
    'expected_version', v_max,
    'historial', v_hist,
    'observacion_activa_desde', (select h.valor ->> 'en' from crm.rentabilidad_hitos h where h.clave = 'observacion_activa_desde'),
    'puede_publicar', coalesce(private.rol_crm(v_uid) = 'gerencia', false),
    'generado_en', statement_timestamp()
  );
end;
$function$
;

notify pgrst, 'reload schema';
commit;
