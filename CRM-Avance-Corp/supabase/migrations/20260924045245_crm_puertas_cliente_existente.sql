-- Venta cruzada · Fase 4: las puertas de la venta cruzada.
--
-- QUÉ HACE. Abre, para un vendedor o supervisor, el camino completo para registrar una
-- inversión NUEVA o un UPGRADE de un cliente de OTRA cartera sin crear un lead, sin
-- reabrir un descarte, sin otro perfil ni otra persona y sin tocar al responsable:
--   · crm.buscar_cliente_existente_fn: búsqueda EXACTA por documento, teléfono o lead
--     del propio ámbito. Deja rastro en crm.busquedas_cliente_existente (también las
--     fallidas), tope de 30 por hora y respuesta mínima. Solo la búsqueda por
--     documento con veredicto «encontrado» es la llave para preparar.
--   · crm.contexto_cliente_existente_fn: el contexto del formulario, con la misma
--     forma que crm.contexto_conversion_inversion_fn.
--   · crm.preparar_inversion_cliente_existente_fn: la puerta explícita. Exige la llave,
--     un motivo, que la persona sea cliente y que NO sea de tu cartera (esa va por su
--     ficha); congela analista = quien registra, la búsqueda y el motivo en la
--     solicitud. Todo lo demás lo hace el núcleo de siempre.
--   · crm.cuentas_cliente_existente_fn (D3): cuentas registradas del cliente,
--     enmascaradas (banco y 4 últimos dígitos); la lectura queda en cartera_lecturas.
--   · crm.datos_legales_cliente_existente_fn: los datos legales para el contrato.
--   · crm.contratos_upgrade_cliente_existente_fn (D5): los contratos Avance activos del
--     cliente que un upgrade puede ampliar.
-- Las lecturas con la solicitud como llave solo abren mientras está preparada (segunda
-- auditoría). Los motivos de «no operable» salen de un catálogo cerrado
-- (private.venta_cruzada_motivo).
-- Sin duplicar lógica: crm.preparar_inversion_fn y crm.datos_legales_contrato_fn pasan
-- a ser envoltorios de dos núcleos extraídos de sus cuerpos vivos
-- (private.inversion_preparar_nucleo y private.datos_legales_contrato_nucleo), que
-- las puertas nuevas comparten. D6 vive en el núcleo: una venta cruzada no convive con
-- otra inversión de la misma persona y empresa en preparación, en ningún sentido.
--
-- CONDUCTA. Cartera, conversión y renovación: idéntica salvo D6 (una preparación de
-- cartera se detiene si esa persona y empresa tienen una venta cruzada en
-- preparación). Datos legales de siempre: idénticos.
--
-- CUERPOS. Los dos núcleos y sus envoltorios se generan por programa desde los cuerpos
-- vivos de prod del 23/09 (anclados por md5), con cada sustitución exigida el número
-- exacto de veces. Las puertas nuevas se escriben a mano.
--
-- REQUIERE. Fases 1, 2 y 3 aplicadas. REVERSA: supabase/scripts/venta-cruzada/reversa-fase4.sql.
begin;
set local lock_timeout = '5s';

do $anclas$ declare a record; begin
  if to_regprocedure('crm.buscar_cliente_existente_fn(text,text,text,uuid)') is not null then
    raise exception 'La Fase 4 ya está aplicada';
  end if;
  if to_regprocedure('private.inversion_persona_autorizada_para(uuid,uuid,uuid)') is null
     or to_regprocedure('private.puede_crear_contrato_pdf_como(uuid,uuid)') is null
     or md5(pg_get_functiondef('private.inversion_solicitud_resultado(uuid,jsonb)'::regprocedure)) <> '2ce92b3e2327a1f7a585f0053cb59bc4' then
    raise exception 'Faltan las Fases 2 y 3 (20260924032042 y 20260924042729): aplícalas antes';
  end if;
  for a in select * from (values
    ('crm.preparar_inversion_fn(uuid,jsonb)','14fbc1f7153309e10d0c80bde1f4a1f7'),
    ('crm.datos_legales_contrato_fn(uuid)','7eab5cd09d1b90075e692cbd822d2d27')
  ) x(firma, huella) loop
    if to_regprocedure(a.firma) is null
       or md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'La base cambió: %. Revisa antes de instalar.', a.firma;
    end if;
  end loop;
end $anclas$;

-- Permisos y atributos de antes, para comprobar al final que no cambian.
create temporary table vc_fase4_antes on commit drop as
select p.oid, p.oid::regprocedure::text firma, p.proacl::text acl, p.proconfig, p.prosecdef, p.provolatile, pg_get_userbyid(p.proowner) dueno
  from pg_proc p where p.oid in ('crm.preparar_inversion_fn(uuid,jsonb)'::regprocedure, 'crm.datos_legales_contrato_fn(uuid)'::regprocedure);

-- ---------------------------------------------------------------------------
-- 1. Núcleos extraídos y sus envoltorios (generados desde los cuerpos vivos)
-- ---------------------------------------------------------------------------
CREATE FUNCTION private.inversion_preparar_nucleo(p_clave uuid, p_datos jsonb, p_puerta text, p_busqueda uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_persona uuid;
  v_lead uuid;
  v_ctx jsonb;
  v_e crm.empresas%rowtype;
  v_s crm.inversion_solicitudes%rowtype;
  v_monto numeric;
  v_fecha date;
  v_vence date;
  v_ruta text;
  v_hash text;
  v_llave_sol uuid;
begin
  if p_clave is null or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Falta la clave o el contenido de la inversión' using errcode='22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_datos) k where k not in (
    'inversionista_id','lead_id','empresa','monto','moneda','fecha_comercial','vence_en','numero_transaccion',
    'referencia','evidencia','producto_condicion_id','contrato','cronograma','cuenta','alta_portal','plazo_meses','tasa_anual'
  )) then
    raise exception 'La solicitud contiene campos no admitidos' using errcode='22023';
  end if;
  begin v_persona := (p_datos->>'inversionista_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Identificador de persona inválido' using errcode='22023';
  end;
  begin v_lead := (p_datos->>'lead_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Origen de inversión inválido' using errcode='22023';
  end;
  if p_puerta is null or p_puerta not in ('cartera','cliente_existente')
     or (p_puerta = 'cartera' and (p_busqueda is not null or p_motivo is not null))
     or (p_puerta = 'cliente_existente' and (p_busqueda is null or v_lead is not null)) then
    raise exception 'Puerta de preparación inválida' using errcode='22023';
  end if;
  -- Venta cruzada: un reintento se autoriza con su propia solicitud (la búsqueda pudo
  -- vencer); una solicitud nueva, con la búsqueda. En cartera no hay llaves.
  if p_puerta = 'cliente_existente' then
    select s.id into v_llave_sol from crm.inversion_solicitudes s where s.id=p_clave and s.puerta='cliente_existente';
  end if;
  v_ctx := private.inversion_persona_autorizada_para(v_persona,v_llave_sol,case when v_llave_sol is null then p_busqueda end);
  v_hash := private.idem_hash(p_datos);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('f4_solicitud:'||p_clave::text,0));
  select * into v_s from crm.inversion_solicitudes where id=p_clave for update;
  if found then
    if v_s.hash_payload<>v_hash or v_s.inversionista_id<>v_persona or v_s.puerta is distinct from p_puerta
       or v_s.busqueda_id is distinct from p_busqueda or v_s.motivo_atribucion is distinct from p_motivo
       or (p_puerta='cliente_existente' and v_s.analista_cierre_id is distinct from (select auth.uid())) then
      raise exception 'La misma clave llegó con datos distintos' using errcode='P0409';
    end if;
    if v_s.estado<>'confirmada' then
      v_ctx := private.inversion_persona_contexto_para(v_persona,v_lead,v_llave_sol,case when v_llave_sol is null then p_busqueda end);
    end if;
    return private.inversion_solicitud_resultado(v_s.id,v_ctx);
  end if;
  -- Venta cruzada nueva: bajo los candados de documento y persona que tomó la
  -- autorización (orden global: bandera, jerarquía, documento, persona), el documento
  -- buscado sigue siendo de esta persona. Una corrección o fusión posterior a la búsqueda
  -- la invalida (segunda auditoría, P3).
  if p_puerta='cliente_existente' and not exists (select 1 from crm.busquedas_cliente_existente b
       where b.id=p_busqueda
         and private.inversionista_por_documento(b.tipo_documento,b.valor_consultado)=private.inversionista_canonica(v_persona)) then
    raise exception 'El documento ya no corresponde a esta persona; vuelve a buscarla' using errcode='P0409';
  end if;
  v_ctx := private.inversion_persona_contexto_para(v_persona,v_lead,v_llave_sol,case when v_llave_sol is null then p_busqueda end);
  if v_lead is not null and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=v_lead and estado in ('preparada','confirmada')) then
    raise exception 'Este lead ya tiene una solicitud: retómala antes de crear otra' using errcode='P0409';
  end if;
  v_e.id:=private.inversion_validar_datos(p_clave,p_datos,v_ctx||case when p_puerta='cliente_existente'
    then jsonb_build_object('analista_cierre_id',(select auth.uid()),'puerta',p_puerta) else '{}'::jsonb end);
  -- D6: una venta cruzada no convive con otra inversión de la misma persona y empresa
  -- en preparación, en ninguno de los dos sentidos (evita registrar dos veces el mismo
  -- dinero). Corre bajo el candado de la persona que tomó la autorización.
  if exists (select 1 from crm.inversion_solicitudes s
             where s.estado='preparada' and s.empresa_id=v_e.id
               and (s.puerta='cliente_existente' or p_puerta='cliente_existente')
               and private.inversionista_canonica(s.inversionista_id)=private.inversionista_canonica(v_persona)) then
    raise exception 'Ya hay una inversión de este cliente en preparación en esta empresa: debe confirmarse o cancelarse antes' using errcode='P0409';
  end if;
  insert into crm.inversion_solicitudes(id,inversionista_id,empresa_id,responsable_esperado_id,hash_payload,datos,creado_por,lead_origen_id,
    puerta,analista_cierre_id,motivo_atribucion,busqueda_id)
  values(p_clave,v_persona,v_e.id,(v_ctx->>'responsable_id')::uuid,v_hash,p_datos,(select auth.uid()),v_lead,
    p_puerta,case when p_puerta='cliente_existente' then (select auth.uid()) end,p_motivo,p_busqueda);
  return private.inversion_solicitud_resultado(p_clave,v_ctx);
end;
$function$;

CREATE OR REPLACE FUNCTION crm.preparar_inversion_fn(p_clave uuid, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  -- Envoltorio: el flujo de Cartera y de conversión de siempre, sin llaves.
  return private.inversion_preparar_nucleo(p_clave, p_datos, 'cartera', null::uuid, null::text);
end;
$function$;

CREATE FUNCTION private.datos_legales_contrato_nucleo(p_cliente_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- La autorización la hace quien llama (P04 en crm.datos_legales_contrato_fn, la
  -- llave de venta cruzada en crm.datos_legales_cliente_existente_fn).
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

CREATE OR REPLACE FUNCTION crm.datos_legales_contrato_fn(p_cliente_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (select auth.uid()) is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;
  -- MISMO texto para «no existe» y «ajeno»: no da oraculo de existencia.
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;
  -- Envoltorio: los datos legales viven en el núcleo, compartido con la venta cruzada.
  return private.datos_legales_contrato_nucleo(p_cliente_id);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Puertas nuevas de la venta cruzada
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Qué es «cliente» para la venta cruzada (una sola definición)
-- ---------------------------------------------------------------------------
-- Una persona es cliente si ella, o alguien fusionado en ella, tiene perfil Avance o
-- alguna inversión registrada. La búsqueda y la preparación preguntan aquí.
create function private.inversionista_es_cliente(p_persona uuid)
returns boolean language sql stable set search_path = '' as $$
  with recursive arbol as (
    select i.id, i.perfil_id, 1 as n from crm.inversionistas i
     where i.id = private.inversionista_canonica(p_persona)
    union all
    select i.id, i.perfil_id, a.n + 1 from crm.inversionistas i
      join arbol a on i.inversionista_canonico_id = a.id
     where a.n < 16)
  select p_persona is not null and (
    exists (select 1 from arbol a where a.perfil_id is not null)
    or exists (select 1 from crm.inversiones iv where iv.inversionista_id in (select a.id from arbol a)))
$$;

-- ---------------------------------------------------------------------------
-- La ventana del tope de búsquedas (una sola definición)
-- ---------------------------------------------------------------------------
-- Búsquedas de un actor en la última hora que cuentan para el tope; las rechazadas por
-- el propio tope no cuentan (quedan en la bitácora, pero no alargan el castigo).
create function private.busquedas_cliente_ultima_hora(p_actor uuid)
returns bigint language sql stable set search_path = '' as $$
  select count(*) from crm.busquedas_cliente_existente b
   where b.consultado_por = p_actor and b.veredicto <> 'limite'
     and b.creado_en > statement_timestamp() - interval '1 hour'
$$;

-- ---------------------------------------------------------------------------
-- Por qué hoy no se puede invertir, en un catálogo cerrado
-- ---------------------------------------------------------------------------
-- Traduce el mensaje de la regla de contexto a un código y un texto fijos: lo que ve
-- quien busca no depende de cómo se redacte mañana un error del núcleo. «reservado»
-- dice si ese motivo impide mostrar nombre, responsable y empresas a quien no es de la
-- cartera (por ejemplo, No insistir o un perfil en revisión).
create function private.venta_cruzada_motivo(p_mensaje text)
returns jsonb language sql immutable set search_path = '' as $$
  select case
    when p_mensaje is null then null
    when p_mensaje like 'Asigna un responsable comercial activo%' then jsonb_build_object(
      'codigo', 'responsable_inactivo', 'reservado', false,
      'texto', 'El cliente no tiene un responsable activo: pide a Gerencia que se lo asigne.')
    when p_mensaje like 'Completa la conversión inicial%' or p_mensaje like 'Hay más de un lead canónico%' then jsonb_build_object(
      'codigo', 'conversion_pendiente', 'reservado', false,
      'texto', 'La persona tiene un lead abierto: su responsable debe completar la conversión inicial.')
    when p_mensaje like 'La persona no permite nuevas inversiones%' or p_mensaje like 'La persona tiene No insistir%' then jsonb_build_object(
      'codigo', 'no_admite', 'reservado', true,
      'texto', 'La persona no admite nuevas inversiones por ahora.')
    when p_mensaje like 'El perfil Avance requiere revisión%' or p_mensaje like 'El documento del perfil requiere conciliación%' then jsonb_build_object(
      'codigo', 'perfil_en_revision', 'reservado', true,
      'texto', 'El perfil del cliente necesita una revisión antes de invertir: consúltalo con Gerencia.')
    else jsonb_build_object('codigo', 'otro', 'reservado', true,
      'texto', 'Hoy no se puede registrar una inversión para esta persona.')
  end
$$;

-- ---------------------------------------------------------------------------
-- La llave de las lecturas de una venta cruzada (una sola definición)
-- ---------------------------------------------------------------------------
-- UNA llave: la búsqueda vigente de quien pregunta o la solicitud de venta cruzada, de esa
-- misma persona. Con p_solo_preparada, una solicitud confirmada o cancelada ya no abre
-- datos vivos del cliente (segunda auditoría, P2). 42501 igual para «no existe», «no es
-- tuya» y «ya se cerró»: no da oráculo. Devuelve la persona autorizada.
create function private.venta_cruzada_lectura(p_busqueda uuid, p_solicitud uuid, p_solo_preparada boolean)
returns jsonb language plpgsql set search_path = '' as $$
declare v_ctx jsonb;
begin
  if num_nonnulls(p_busqueda, p_solicitud) <> 1 then
    raise exception 'Falta la búsqueda o la solicitud de la venta cruzada' using errcode = '22023';
  end if;
  v_ctx := private.inversion_persona_lectura_para(coalesce(
    (select b.inversionista_id from crm.busquedas_cliente_existente b where b.id = p_busqueda),
    (select s.inversionista_id from crm.inversion_solicitudes s where s.id = p_solicitud)), p_solicitud, p_busqueda);
  if p_solo_preparada and p_solicitud is not null
     and (select s.estado from crm.inversion_solicitudes s where s.id = p_solicitud) is distinct from 'preparada' then
    raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode = '42501';
  end if;
  return v_ctx;
end $$;

-- ---------------------------------------------------------------------------
-- Búsqueda exacta de un cliente existente
-- ---------------------------------------------------------------------------
-- Exactamente un criterio: documento (tipo + número), teléfono o un lead del ámbito del
-- actor (el mismo del botón «Reabrir»). Cada búsqueda queda en la bitácora, también las
-- fallidas y las del tope (una fila de tope por minuto), porque la función devuelve el
-- veredicto en vez de fallar. Solo reconoce CLIENTES; una persona que aún no lo es se
-- informa como «no_encontrado». Devuelve lo mínimo: nombre (con iniciales si se buscó por
-- teléfono y la persona no es de tu cartera), documento enmascarado, nombre del
-- responsable y empresas; nada de eso si el motivo de «no operable» es reservado. La
-- «llave» para preparar solo la da una búsqueda por documento con veredicto «encontrado».
create function crm.buscar_cliente_existente_fn(p_tipo_documento text default null, p_documento text default null,
  p_telefono text default null, p_lead uuid default null)
returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_global boolean;
  v_criterio text; v_tipo text; v_valor text;
  v_lead crm.leads%rowtype;
  v_candidatos uuid[];
  v_persona uuid;
  v_veredicto text;
  v_b uuid;
  v_motivo text;
  v_catalogo jsonb;
  v_i crm.inversionistas%rowtype;
  v_mia boolean := false;
  v_ctx jsonb;
  v_nombre text; v_doc text; v_doc_tipo text; v_empresas jsonb;
begin
  -- Mismas compuertas que la lectura de una persona para invertir.
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para buscar clientes' using errcode = '42501';
  end if;
  if not private.inversiones_escritura_bajo_candado() then
    raise exception 'El registro multiempresa todavía no está habilitado' using errcode = 'P0409';
  end if;
  select coalesce(f.activo, false) into v_global from crm.multiempresa_flags f where f.nombre = 'inversiones_escritura';
  if not coalesce(v_global, false) then
    if not private.piloto_f8_actor_activo(v_uid) then
      raise exception 'El registro multiempresa está limitado al equipo piloto' using errcode = '42501';
    end if;
    perform private.cartera_f5_exigir();
  end if;
  v_rol := private.rol_crm(v_uid);
  if v_rol is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado para buscar clientes' using errcode = '42501';
  end if;
  if num_nonnulls(nullif(btrim(p_documento), ''), nullif(btrim(p_telefono), ''), p_lead) <> 1 then
    raise exception 'Busca por documento, por teléfono o desde un lead (uno solo)' using errcode = '22023';
  end if;

  if nullif(btrim(p_documento), '') is not null then
    v_criterio := 'documento';
    v_tipo := upper(btrim(coalesce(p_tipo_documento, '')));
    if v_tipo not in ('DNI','CE','PASAPORTE') then
      raise exception 'Elige el tipo de documento: DNI, CE o pasaporte' using errcode = '22023';
    end if;
    v_valor := upper(regexp_replace(p_documento, '[^A-Za-z0-9]', '', 'g'));
  elsif nullif(btrim(p_telefono), '') is not null then
    v_criterio := 'telefono';
    v_valor := private.normalizar_telefono(p_telefono);
  else
    v_criterio := 'lead';
    -- Mismo ámbito que el botón «Reabrir»: un lead ajeno o inexistente no se registra.
    select * into v_lead from crm.leads l
     where l.id = p_lead and l.activo
       and (v_rol = 'gerencia'
            or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
            or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))));
    if not found then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = '42501';
    end if;
    v_valor := p_lead::text;
  end if;
  v_valor := left(coalesce(nullif(v_valor, ''), '(vacío)'), 64);

  -- Tope por actor: 30 búsquedas por hora, bajo su candado para que no se cuele otra
  -- en paralelo.
  perform pg_advisory_xact_lock(hashtextextended('busquedas_cliente:' || v_uid::text, 0));
  if private.busquedas_cliente_ultima_hora(v_uid) >= 30 then
    v_veredicto := 'limite';
    -- Una sola fila de tope por minuto: insistir no infla la bitácora (segunda auditoría).
    select b.id into v_b from crm.busquedas_cliente_existente b
     where b.consultado_por = v_uid and b.veredicto = 'limite'
       and b.creado_en > statement_timestamp() - interval '1 minute'
     order by b.creado_en desc, b.id limit 1;
  end if;

  if v_veredicto is null then
    if v_criterio = 'documento' then
      if (v_tipo = 'DNI' and v_valor !~ '^[0-9]{8}$') or (v_tipo = 'CE' and v_valor !~ '^[0-9]{9,12}$')
         or (v_tipo = 'PASAPORTE' and v_valor !~ '^[A-Z0-9]{6,12}$') then
        v_veredicto := 'invalido';
      else
        v_persona := private.inversionista_por_documento(v_tipo, v_valor);
      end if;
    elsif v_criterio = 'telefono' then
      if v_valor !~ '^\+[0-9]{8,15}$' then
        v_veredicto := 'invalido';
      else
        -- Solo cuentan los CLIENTES que tienen ese teléfono; si son varios, no se nombra a nadie.
        select array_agg(distinct c.x) into v_candidatos from (
          select private.inversionista_canonica(i.id) x
            from public.perfiles p join crm.inversionistas i on i.perfil_id = p.id
           where p.rol = 'cliente' and private.normalizar_telefono(p.telefono) = v_valor
          union
          select private.inversionista_canonica(d.inversionista_id)
            from crm.inversionista_datos_contacto d where private.normalizar_telefono(d.telefono) = v_valor
          union
          select private.inversionista_canonica(l.inversionista_id)
            from crm.leads l where l.telefono = v_valor and l.inversionista_id is not null) c
         where c.x is not null and private.inversionista_es_cliente(c.x);
        if coalesce(cardinality(v_candidatos), 0) > 1 then
          v_veredicto := 'ambiguo';
        elsif cardinality(v_candidatos) = 1 then
          v_persona := v_candidatos[1];
        end if;
      end if;
    else
      -- Persona del lead, de su DNI y de su puente: si no coinciden, es un conflicto de
      -- identidad y no se nombra a nadie.
      select array_agg(distinct c.x) into v_candidatos from (
        select private.inversionista_canonica(v_lead.inversionista_id) x
        union select private.inversionista_por_documento('DNI', v_lead.dni) where v_lead.dni is not null
        union select private.inversionista_canonica(il.inversionista_id)
                from crm.inversionista_leads il where il.lead_id = v_lead.id) c
       where c.x is not null;
      if coalesce(cardinality(v_candidatos), 0) > 1 then
        v_veredicto := 'conflicto';
      elsif cardinality(v_candidatos) = 1 then
        v_persona := v_candidatos[1];
      end if;
    end if;
  end if;

  if v_veredicto is null and v_persona is not null and not private.inversionista_es_cliente(v_persona) then
    v_persona := null;
  end if;
  if v_veredicto is null and v_persona is null then
    v_veredicto := 'no_encontrado';
  end if;
  if v_persona is not null then
    select * into v_i from crm.inversionistas where id = v_persona;
    v_mia := coalesce(v_rol = 'gerencia' or v_i.responsable_relacion_id in (select private.vendedor_ids_visibles(v_uid)), false);
  end if;

  -- Encontrado: se registra y se pregunta a la regla del contexto si hoy admite una
  -- inversión (con la propia búsqueda como llave). Si no la admite, la fila se deshace
  -- y queda «no_operable» con su motivo.
  if v_veredicto is null then
    begin
      insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado,
        lead_id, veredicto, inversionista_id)
      values (v_uid, v_criterio, case when v_criterio = 'documento' then v_tipo end, v_valor,
        case when v_criterio = 'lead' then p_lead end, 'encontrado', v_persona)
      returning id into v_b;
      if v_criterio = 'documento' then
        v_ctx := private.inversion_contexto_lectura_para(v_persona, null, null, v_b);
      elsif v_mia then
        v_ctx := private.inversion_contexto_lectura_para(v_persona, null, null, null);
      end if;
      v_veredicto := 'encontrado';
    exception when sqlstate 'P0409' or sqlstate 'P0429' then
      get stacked diagnostics v_motivo = message_text;
      v_veredicto := 'no_operable';
      v_b := null;
    end;
  end if;
  if v_b is null then
    insert into crm.busquedas_cliente_existente (consultado_por, criterio, tipo_documento, valor_consultado,
      lead_id, veredicto, inversionista_id)
    values (v_uid, v_criterio, case when v_criterio = 'documento' then v_tipo end, v_valor,
      case when v_criterio = 'lead' then p_lead end, v_veredicto, case when v_veredicto = 'no_operable' then v_persona end)
    returning id into v_b;
  end if;

  if v_veredicto not in ('encontrado','no_operable') then
    return jsonb_build_object('estado', v_veredicto, 'busqueda_id', v_b, 'criterio', v_criterio);
  end if;
  v_catalogo := private.venta_cruzada_motivo(v_motivo);
  -- Un motivo reservado no muestra a la persona a quien no es de su cartera.
  if v_veredicto = 'no_operable' and not v_mia and (v_catalogo->>'reservado')::boolean then
    return jsonb_build_object('estado', v_veredicto, 'busqueda_id', v_b, 'criterio', v_criterio,
      'cliente', jsonb_build_object('es_mi_cartera', false),
      'acciones', jsonb_build_object('ver_ficha', false, 'nueva_inversion', false, 'requiere_documento', false,
        'motivo_codigo', v_catalogo->>'codigo', 'motivo_no_operable', v_catalogo->>'texto'));
  end if;

  v_nombre := coalesce(v_ctx->>'nombre',
    (select nullif(btrim(p.nombre_completo), '') from public.perfiles p where p.id = v_i.perfil_id),
    (select nullif(btrim(d.nombre_completo), '') from crm.inversionista_datos_contacto d where d.inversionista_id = v_persona),
    (select nullif(btrim(ce.nombre_completo), '') from crm.cierres_externos ce
      where ce.inversionista_id = v_persona order by ce.creado_en desc, ce.id desc limit 1));
  select d.tipo_documento, d.documento_normalizado into v_doc_tipo, v_doc
    from crm.inversionista_identificadores d
   where d.inversionista_id = v_persona and d.estado = 'vigente' and d.verificado
   order by case d.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end, d.id limit 1;
  select coalesce(jsonb_agg(distinct e.clave), '[]'::jsonb) into v_empresas
    from crm.inversiones iv join crm.empresas e on e.id = iv.empresa_id
   where private.inversionista_canonica(iv.inversionista_id) = v_persona;

  return jsonb_build_object(
    'estado', v_veredicto,
    'busqueda_id', v_b,
    'criterio', v_criterio,
    'cliente', jsonb_build_object(
      'inversionista_id', case when v_criterio = 'documento' or v_mia then v_persona end,
      'nombre', case when v_criterio <> 'telefono' or v_mia then v_nombre
        else (select string_agg(case when t.n = 1 then t.w else left(t.w, 1) || '.' end, ' ' order by t.n)
                from unnest(regexp_split_to_array(btrim(v_nombre), '\s+')) with ordinality t(w, n)) end,
      'documento_tipo', v_doc_tipo,
      'documento_enmascarado', case when v_doc is null then null
        else repeat('•', greatest(length(v_doc) - 3, 0)) || right(v_doc, 3) end,
      'responsable_nombre', (select p.nombre_completo from public.perfiles p where p.id = v_i.responsable_relacion_id),
      'empresas', v_empresas,
      'es_mi_cartera', v_mia),
    'acciones', jsonb_build_object(
      'ver_ficha', v_mia,
      'nueva_inversion', v_veredicto = 'encontrado' and v_criterio = 'documento' and not v_mia,
      'requiere_documento', v_veredicto = 'encontrado' and v_criterio <> 'documento' and not v_mia,
      'motivo_codigo', v_catalogo->>'codigo',
      'motivo_no_operable', v_catalogo->>'texto'));
end $$;

-- ---------------------------------------------------------------------------
-- Contexto del formulario de una venta cruzada (misma forma que la conversión)
-- ---------------------------------------------------------------------------
-- Con UNA llave: la búsqueda vigente (antes de preparar) o la solicitud (después). Misma
-- forma que crm.contexto_conversion_inversion_fn para que el formulario de siempre lo
-- consuma, sin correo ni teléfono del cliente: si falta el acceso Avance, quien vende se
-- los pide al cliente (tiene_acceso_avance lo avisa). Devuelve el perfil_id, que el
-- formulario necesita para la política de tasas (crm.resolver_tasa_fn y las solicitudes de
-- tasa ya lo aceptan de cualquier analista con un cliente activo). Una solicitud ya
-- confirmada o cancelada solo devuelve su estado, sin datos vivos del cliente.
create function crm.contexto_cliente_existente_fn(p_busqueda uuid default null, p_solicitud uuid default null)
returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_persona uuid; v_ctx jsonb; v_motivo text; v_catalogo jsonb; v_uid uuid := (select auth.uid()); v_estado text;
begin
  -- La llave se comprueba aquí: 42501 si no existe, no es de esta persona o no es tuya.
  v_ctx := private.venta_cruzada_lectura(p_busqueda, p_solicitud, false);
  v_persona := (v_ctx->>'inversionista_id')::uuid;
  v_estado := (select s.estado from crm.inversion_solicitudes s where s.id = p_solicitud);
  if p_solicitud is not null and v_estado is distinct from 'preparada' then
    return jsonb_build_object('solicitud_id', p_solicitud, 'documento_tipo', null,
      'persona', jsonb_build_object('inversionista_id', v_persona, 'perfil_id', null, 'tiene_acceso_avance', null,
        'nombre', null, 'correo', null, 'telefono', null, 'responsable_id', null, 'responsable_nombre', null),
      'capacidades', jsonb_build_object('nueva_inversion', false, 'motivo_codigo', 'solicitud_cerrada',
        'motivo_no_operable', case when v_estado = 'confirmada' then 'La inversión ya está confirmada.'
                                   else 'La solicitud está cancelada.' end));
  end if;
  v_ctx := v_ctx || jsonb_build_object('nombre', (select p.nombre_completo from public.perfiles p where p.id = (v_ctx->>'perfil_id')::uuid));
  begin
    v_ctx := private.inversion_contexto_lectura_para(v_persona, null, p_solicitud, p_busqueda);
  exception when sqlstate 'P0409' or sqlstate 'P0429' then
    get stacked diagnostics v_motivo = message_text;
  end;
  v_catalogo := private.venta_cruzada_motivo(v_motivo);
  return jsonb_build_object(
    'solicitud_id', coalesce(p_solicitud, (select s.id from crm.inversion_solicitudes s
        where s.puerta = 'cliente_existente' and s.estado = 'preparada' and s.analista_cierre_id = v_uid
          and private.inversionista_canonica(s.inversionista_id) = v_persona order by s.creado_en desc, s.id limit 1)),
    'documento_tipo', (select d.tipo_documento from crm.inversionista_identificadores d
      where d.inversionista_id = v_persona and d.estado = 'vigente' and d.verificado
      order by case d.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end, d.id limit 1),
    'persona', jsonb_build_object(
      'inversionista_id', v_ctx->>'inversionista_id', 'perfil_id', v_ctx->>'perfil_id',
      'tiene_acceso_avance', v_ctx->>'perfil_id' is not null,
      'nombre', v_ctx->>'nombre', 'correo', null, 'telefono', null,
      'responsable_id', v_ctx->>'responsable_id',
      'responsable_nombre', (select p.nombre_completo from public.perfiles p where p.id = (v_ctx->>'responsable_id')::uuid)),
    'capacidades', jsonb_build_object('nueva_inversion', v_motivo is null,
      'motivo_codigo', v_catalogo->>'codigo', 'motivo_no_operable', v_catalogo->>'texto'));
end $$;

-- ---------------------------------------------------------------------------
-- Preparar la venta cruzada
-- ---------------------------------------------------------------------------
-- Solo vendedor o supervisor (D1), con una búsqueda propia, vigente y por documento del
-- cliente, un motivo (10 a 500 caracteres, sin números de documento) y nunca desde un
-- lead. Manda a su ficha al cliente de la propia cartera (una sola vía por situación).
-- Todo lo demás es el núcleo de siempre: idempotencia, candados en el orden global
-- (bandera → jerarquía → documento → persona), revalidación del documento buscado bajo
-- esos candados, D6, validación y alta.
create function crm.preparar_inversion_cliente_existente_fn(p_clave uuid, p_busqueda uuid, p_datos jsonb, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_b crm.busquedas_cliente_existente%rowtype;
  v_persona uuid;
  v_motivo text := btrim(p_motivo, E' \t\r\n');
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor','supervisor') then
    raise exception 'Solo un vendedor o un supervisor registra la inversión de un cliente de otra cartera' using errcode = '42501';
  end if;
  if p_clave is null or p_busqueda is null or p_datos is null or jsonb_typeof(p_datos) <> 'object' then
    raise exception 'Falta la clave, la búsqueda o el contenido de la inversión' using errcode = '22023';
  end if;
  if p_datos ? 'lead_id' then
    raise exception 'La venta cruzada no convierte un lead' using errcode = '22023';
  end if;
  -- Reintento con la misma clave: el núcleo compara todo y autoriza con la solicitud.
  if exists (select 1 from crm.inversion_solicitudes s where s.id = p_clave) then
    return private.inversion_preparar_nucleo(p_clave, p_datos, 'cliente_existente', p_busqueda, v_motivo);
  end if;
  select * into v_b from crm.busquedas_cliente_existente b where b.id = p_busqueda;
  if not found or not private.busqueda_cliente_es_llave(p_busqueda, v_uid, v_b.inversionista_id) then
    raise exception 'Vuelve a buscar al cliente por su documento para registrar su inversión' using errcode = 'P0409';
  end if;
  v_persona := private.inversionista_canonica(v_b.inversionista_id);
  begin
    if private.inversionista_canonica((p_datos->>'inversionista_id')::uuid) is distinct from v_persona then
      raise exception 'La inversión no corresponde al cliente buscado' using errcode = '22023';
    end if;
  exception when invalid_text_representation then
    raise exception 'La inversión no corresponde al cliente buscado' using errcode = '22023';
  end;
  if (select i.responsable_relacion_id from crm.inversionistas i where i.id = v_persona)
     in (select private.vendedor_ids_visibles(v_uid)) then
    raise exception 'Este cliente es de tu cartera: registra la inversión desde su ficha' using errcode = 'P0409';
  end if;
  if not private.inversionista_es_cliente(v_persona) then
    raise exception 'La persona todavía no es cliente: su primera inversión nace de un lead' using errcode = 'P0409';
  end if;
  if v_motivo is null or char_length(v_motivo) not between 10 and 500 then
    raise exception 'Explica en 10 a 500 caracteres por qué registras la inversión de este cliente' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(v_motivo,
    (select array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = v_persona));
  return private.inversion_preparar_nucleo(p_clave, p_datos, 'cliente_existente', p_busqueda, v_motivo);
end $$;

-- ---------------------------------------------------------------------------
-- Cuentas bancarias del cliente, enmascaradas (D3)
-- ---------------------------------------------------------------------------
-- Con UNA llave (búsqueda vigente o solicitud en preparación). Solo cuentas registradas y
-- activas del perfil en esa moneda: banco, tipo y los 4 últimos dígitos. Para usar una,
-- la pantalla manda {tipo: 'existente', cuenta_id}; el escritor contractual de siempre
-- comprueba al confirmar que sea del cliente, de la moneda y esté activa. La lectura
-- queda en crm.cartera_lecturas como la de la ficha.
create function crm.cuentas_cliente_existente_fn(p_busqueda uuid default null, p_solicitud uuid default null,
  p_moneda text default 'PEN')
returns table(cuenta_id uuid, moneda text, banco text, tipo_cuenta text, numero_enmascarado text,
  cci_enmascarado text, titular_distinto boolean, creada_en timestamptz)
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_ctx jsonb;
begin
  if p_moneda is null or p_moneda not in ('PEN','USD') then
    raise exception 'Moneda bancaria inválida' using errcode = '22023';
  end if;
  v_ctx := private.venta_cruzada_lectura(p_busqueda, p_solicitud, true);
  perform private.cartera_f5_registrar('cuentas', (v_ctx->>'inversionista_id')::uuid);
  return query
    select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
           '••••' || right(cb.numero_cuenta, 4), '••••' || right(cb.cci, 4), cb.titular_distinto, cb.creado_en
      from crm.cuentas_bancarias cb
     where cb.cliente_id = (v_ctx->>'perfil_id')::uuid and cb.moneda = p_moneda and cb.activa
     order by cb.creado_en desc, cb.id;
end $$;

-- ---------------------------------------------------------------------------
-- Datos legales para el contrato de una venta cruzada
-- ---------------------------------------------------------------------------
-- Con UNA llave (búsqueda vigente o solicitud en preparación); mismo núcleo y misma forma
-- que crm.datos_legales_contrato_fn.
create function crm.datos_legales_cliente_existente_fn(p_busqueda uuid default null, p_solicitud uuid default null)
returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_ctx jsonb;
begin
  v_ctx := private.venta_cruzada_lectura(p_busqueda, p_solicitud, true);
  if v_ctx->>'perfil_id' is null then
    raise exception 'Completa primero el acceso Avance del cliente' using errcode = 'P0409';
  end if;
  return private.datos_legales_contrato_nucleo((v_ctx->>'perfil_id')::uuid);
end $$;

-- ---------------------------------------------------------------------------
-- Contratos que una venta cruzada puede ampliar con un UPGRADE (D5)
-- ---------------------------------------------------------------------------
-- Con UNA llave (búsqueda vigente o solicitud en preparación). Solo los contratos Avance
-- activos del cliente, con lo mínimo para elegir cuál se amplía (número, capital, moneda,
-- tasa y vencimiento): el upgrade es un contrato aparte que hereda la tasa del que
-- amplía. La lectura queda en crm.cartera_lecturas como la de la ficha.
create function crm.contratos_upgrade_cliente_existente_fn(p_busqueda uuid default null, p_solicitud uuid default null)
returns table(contrato_id uuid, numero_contrato text, capital numeric, moneda text, tasa_anual numeric, fecha_vencimiento date)
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_ctx jsonb;
begin
  v_ctx := private.venta_cruzada_lectura(p_busqueda, p_solicitud, true);
  perform private.cartera_f5_registrar('ficha', (v_ctx->>'inversionista_id')::uuid);
  return query
    select c.id, c.numero_contrato, c.capital, c.moneda, c.tasa_anual, c.fecha_vencimiento
      from public.contratos c
     where c.cliente_id = (v_ctx->>'perfil_id')::uuid and c.estado = 'activo' and c.es_demo is not true
     order by c.fecha_vencimiento, c.numero_contrato;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Permisos: los núcleos y la definición de «cliente» no son puertas
-- ---------------------------------------------------------------------------
revoke all on function private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text) from public, anon, authenticated, service_role;
revoke all on function private.datos_legales_contrato_nucleo(uuid) from public, anon, authenticated, service_role;
revoke all on function private.inversionista_es_cliente(uuid) from public, anon, authenticated, service_role;
revoke all on function private.busquedas_cliente_ultima_hora(uuid) from public, anon, authenticated, service_role;
revoke all on function private.venta_cruzada_motivo(text) from public, anon, authenticated, service_role;
revoke all on function private.venta_cruzada_lectura(uuid,uuid,boolean) from public, anon, authenticated, service_role;
revoke all on function crm.contratos_upgrade_cliente_existente_fn(uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function crm.buscar_cliente_existente_fn(text,text,text,uuid) from public, anon, authenticated, service_role;
revoke all on function crm.contexto_cliente_existente_fn(uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text) from public, anon, authenticated, service_role;
revoke all on function crm.cuentas_cliente_existente_fn(uuid,uuid,text) from public, anon, authenticated, service_role;
revoke all on function crm.datos_legales_cliente_existente_fn(uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function crm.buscar_cliente_existente_fn(text,text,text,uuid) to authenticated;
grant execute on function crm.contexto_cliente_existente_fn(uuid,uuid) to authenticated;
grant execute on function crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text) to authenticated;
grant execute on function crm.cuentas_cliente_existente_fn(uuid,uuid,text) to authenticated;
grant execute on function crm.datos_legales_cliente_existente_fn(uuid,uuid) to authenticated;
grant execute on function crm.contratos_upgrade_cliente_existente_fn(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Comentarios
-- ---------------------------------------------------------------------------
comment on function private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text) is
  'Núcleo de la preparación de una inversión (F4): idempotencia por clave, autorización, revalidación del documento buscado (venta cruzada), contexto, validación, D6 y alta de la solicitud. Puerta «cartera» (sin llaves: Cartera, conversión y renovación) o «cliente_existente» (venta cruzada: búsqueda como llave, analista = quien registra, motivo congelado).';
comment on function crm.preparar_inversion_fn(uuid,jsonb) is
  'Prepara una inversión desde Cartera, una conversión o una renovación: envoltorio del núcleo private.inversion_preparar_nucleo con la puerta «cartera».';
comment on function private.datos_legales_contrato_nucleo(uuid) is
  'Núcleo de los datos legales para el contrato: qué le falta al cliente y a quien registra. No autoriza: lo hace quien lo llama.';
comment on function private.inversionista_es_cliente(uuid) is
  'Venta cruzada: verdadero si la persona, o alguien fusionado en ella, tiene perfil Avance o alguna inversión. Única definición de «cliente» para buscar y preparar.';
comment on function private.busquedas_cliente_ultima_hora(uuid) is
  'Venta cruzada: búsquedas de un actor en la última hora que cuentan para el tope de crm.buscar_cliente_existente_fn (sin las rechazadas por el propio tope). Única definición de la ventana.';
comment on function private.venta_cruzada_motivo(text) is
  'Venta cruzada: traduce el motivo de «no operable» de la regla de contexto a un catálogo cerrado (código, texto fijo y si es reservado). Lo que ve quien busca no depende de la redacción de un error del núcleo.';
comment on function private.venta_cruzada_lectura(uuid,uuid,boolean) is
  'Venta cruzada: la llave de sus lecturas (búsqueda vigente de quien pregunta o solicitud de esa persona; con p_solo_preparada, solo si la solicitud sigue preparada). Devuelve la persona autorizada; 42501 sin oráculo.';
comment on function crm.contratos_upgrade_cliente_existente_fn(uuid,uuid) is
  'Venta cruzada (D5): contratos Avance activos del cliente que se pueden ampliar con un upgrade (número, capital, moneda, tasa y vencimiento), con UNA llave (búsqueda vigente o solicitud en preparación). La lectura queda en crm.cartera_lecturas.';
comment on function crm.buscar_cliente_existente_fn(text,text,text,uuid) is
  'Venta cruzada: búsqueda exacta de un CLIENTE por documento, teléfono o lead del propio ámbito. Registra cada intento en crm.busquedas_cliente_existente (tope 30 por hora) y devuelve lo mínimo; solo la búsqueda por documento con veredicto encontrado es la llave para preparar.';
comment on function crm.contexto_cliente_existente_fn(uuid,uuid) is
  'Venta cruzada: contexto del formulario con UNA llave (búsqueda vigente o solicitud). Misma forma que crm.contexto_conversion_inversion_fn, sin correo ni teléfono del cliente; una solicitud cerrada solo devuelve su estado.';
comment on function crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text) is
  'Venta cruzada: prepara la inversión NUEVA o UPGRADE de un cliente de otra cartera. Solo vendedor o supervisor, con su búsqueda por documento vigente y un motivo; el analista de cierre queda congelado en quien registra y el responsable no cambia.';
comment on function crm.cuentas_cliente_existente_fn(uuid,uuid,text) is
  'Venta cruzada (D3): cuentas registradas y activas del cliente en la moneda, enmascaradas (banco, tipo y 4 últimos dígitos), con UNA llave (búsqueda vigente o solicitud en preparación). La lectura queda en crm.cartera_lecturas.';
comment on function crm.datos_legales_cliente_existente_fn(uuid,uuid) is
  'Venta cruzada: datos legales para el contrato con UNA llave (búsqueda vigente o solicitud en preparación). Mismo núcleo y forma que crm.datos_legales_contrato_fn.';

-- ---------------------------------------------------------------------------
-- 5. Postflight
-- ---------------------------------------------------------------------------
do $post$ declare a record; begin
  if (select count(*) from vc_fase4_antes) <> 2 then
    raise exception 'POSTFLIGHT: faltan funciones en la foto de antes';
  end if;
  for a in select b.firma, b.acl, b.proconfig, b.prosecdef, b.provolatile, b.dueno,
                  p.proacl::text acl2, p.proconfig proconfig2, p.prosecdef prosecdef2, p.provolatile provolatile2,
                  pg_get_userbyid(p.proowner) dueno2
             from vc_fase4_antes b join pg_proc p on p.oid = b.oid loop
    if a.acl is distinct from a.acl2 or a.proconfig is distinct from a.proconfig2 or a.prosecdef <> a.prosecdef2
       or a.provolatile <> a.provolatile2 or a.dueno <> a.dueno2 then
      raise exception 'POSTFLIGHT: % cambió de permisos o atributos', a.firma;
    end if;
  end loop;
  for a in select * from (values
    ('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)', true, 'v', '{postgres=X/postgres}', '{"search_path=\"\"",lock_timeout=5s}'),
    ('private.datos_legales_contrato_nucleo(uuid)', true, 's', '{postgres=X/postgres}', '{"search_path=\"\""}'),
    ('private.inversionista_es_cliente(uuid)', false, 's', '{postgres=X/postgres}', '{"search_path=\"\""}'),
    ('private.busquedas_cliente_ultima_hora(uuid)', false, 's', '{postgres=X/postgres}', '{"search_path=\"\""}'),
    ('private.venta_cruzada_motivo(text)', false, 'i', '{postgres=X/postgres}', '{"search_path=\"\""}'),
    ('private.venta_cruzada_lectura(uuid,uuid,boolean)', false, 'v', '{postgres=X/postgres}', '{"search_path=\"\""}'),
    ('crm.contratos_upgrade_cliente_existente_fn(uuid,uuid)', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}', '{"search_path=\"\"",lock_timeout=5s}'),
    ('crm.buscar_cliente_existente_fn(text,text,text,uuid)', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}', '{"search_path=\"\"",lock_timeout=5s}'),
    ('crm.contexto_cliente_existente_fn(uuid,uuid)', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}', '{"search_path=\"\"",lock_timeout=5s}'),
    ('crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text)', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}', '{"search_path=\"\"",lock_timeout=5s}'),
    ('crm.cuentas_cliente_existente_fn(uuid,uuid,text)', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}', '{"search_path=\"\"",lock_timeout=5s}'),
    ('crm.datos_legales_cliente_existente_fn(uuid,uuid)', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}', '{"search_path=\"\"",lock_timeout=5s}')
  ) x(firma, definer, volatil, acl, config) loop
    if (select p.prosecdef <> a.definer or p.provolatile <> a.volatil::"char" or p.proacl::text is distinct from a.acl
              or p.proconfig::text is distinct from a.config or pg_get_userbyid(p.proowner) <> 'postgres'
          from pg_proc p where p.oid = to_regprocedure(a.firma)) is not false then
      raise exception 'POSTFLIGHT: % quedó con atributos o permisos distintos', a.firma;
    end if;
  end loop;
  -- Sin sesión, las puertas niegan con 42501 y los envoltorios siguen negando igual.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform crm.buscar_cliente_existente_fn('DNI', '12345678', null, null);
    raise exception 'POSTFLIGHT: la búsqueda respondió sin sesión';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.preparar_inversion_cliente_existente_fn(gen_random_uuid(), gen_random_uuid(), '{}'::jsonb, 'motivo de prueba');
    raise exception 'POSTFLIGHT: la preparación respondió sin sesión';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.datos_legales_contrato_fn(gen_random_uuid());
    raise exception 'POSTFLIGHT: los datos legales respondieron sin sesión';
  exception when insufficient_privilege then
    if sqlerrm <> 'Sesion no valida' then raise; end if;
  end;
  begin
    perform crm.preparar_inversion_fn(gen_random_uuid(), '{}'::jsonb);
    raise exception 'POSTFLIGHT: la preparación de siempre respondió sin sesión';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado para registrar inversiones' then raise; end if;
  end;
end $post$;

commit;
