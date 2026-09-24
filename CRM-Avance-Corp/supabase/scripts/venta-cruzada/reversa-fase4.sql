-- Venta cruzada · reversa de la Fase 4 (20260924045245_crm_puertas_cliente_existente).
-- Retira las seis puertas y sus seis piezas privadas, y devuelve
-- crm.preparar_inversion_fn y crm.datos_legales_contrato_fn AL BYTE (cuerpos vivos de
-- prod del 23/09). Las búsquedas y las ventas cruzadas ya registradas se conservan: la
-- Fase 3 las sigue operando (consultar, corregir, cancelar, confirmar).
-- Falla cerrada si alguna de las catorce funciones ya no es la de la Fase 4 (se perdería
-- un cambio) o si otra función depende de lo que se retira.
-- El veredicto viaja como FILA al final.
begin;
set local lock_timeout = '5s';

do $pre$ declare a record; begin
  if to_regprocedure('crm.buscar_cliente_existente_fn(text,text,text,uuid)') is null then
    raise exception 'REVERSA: la Fase 4 no está aplicada';
  end if;
  for a in select * from (values
    ('crm.buscar_cliente_existente_fn(text,text,text,uuid)','43b317c13c40471a3e3eec2fbbe0fb8a'),
    ('crm.contexto_cliente_existente_fn(uuid,uuid)','8cd36f9311dd59327fa749f4568861cb'),
    ('crm.contratos_upgrade_cliente_existente_fn(uuid,uuid)','52b0849050326644e431b99b6731a29b'),
    ('crm.cuentas_cliente_existente_fn(uuid,uuid,text)','1a0bdfc6e946bf82b100aae98313259f'),
    ('crm.datos_legales_cliente_existente_fn(uuid,uuid)','fdf1abc5b71d3511d196890addd03c43'),
    ('crm.datos_legales_contrato_fn(uuid)','c3cd14bc7b95bcb2f21e966114802363'),
    ('crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text)','327cf5e944998d5a2177f87f69af66bd'),
    ('crm.preparar_inversion_fn(uuid,jsonb)','5fefbc143578a735a8648f686f71bf9a'),
    ('private.busquedas_cliente_ultima_hora(uuid)','d85af6591a9e64909e569c02dee05325'),
    ('private.datos_legales_contrato_nucleo(uuid)','8405bc624737f01bf2e4731813c957ba'),
    ('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)','c34bc06eafdb62f128476a8bffbfa642'),
    ('private.inversionista_es_cliente(uuid)','335c0b4cea632d845eccda54d2cb963e'),
    ('private.venta_cruzada_lectura(uuid,uuid,boolean)','87439c218f479b31573d88a527a48163'),
    ('private.venta_cruzada_motivo(text)','e33eba9c8686cd3f17a573b48bf23569')
  ) x(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'REVERSA: % ya no es la de la Fase 4; revisa ese cambio antes de retirar nada', a.firma;
    end if;
  end loop;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('crm','private','public')
               and (p.prosrc like '%inversion_preparar_nucleo%' or p.prosrc like '%datos_legales_contrato_nucleo%'
                    or p.prosrc like '%inversionista_es_cliente%' or p.prosrc like '%cliente_existente_fn%'
                    or p.prosrc like '%busquedas_cliente_ultima_hora%' or p.prosrc like '%venta_cruzada_motivo%'
                    or p.prosrc like '%venta_cruzada_lectura%' or p.prosrc like '%contratos_upgrade_cliente_existente%')
               and p.oid not in (select to_regprocedure(f) from unnest(array[
                 'crm.buscar_cliente_existente_fn(text,text,text,uuid)',
                 'crm.contexto_cliente_existente_fn(uuid,uuid)',
                 'crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text)',
                 'crm.cuentas_cliente_existente_fn(uuid,uuid,text)',
                 'crm.datos_legales_cliente_existente_fn(uuid,uuid)',
                 'private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)',
                 'crm.contratos_upgrade_cliente_existente_fn(uuid,uuid)',
                 'private.datos_legales_contrato_nucleo(uuid)',
                 'private.inversionista_es_cliente(uuid)',
                 'private.busquedas_cliente_ultima_hora(uuid)',
                 'private.venta_cruzada_motivo(text)',
                 'private.venta_cruzada_lectura(uuid,uuid,boolean)',
                 'crm.preparar_inversion_fn(uuid,jsonb)',
                 'crm.datos_legales_contrato_fn(uuid)']) f)) then
    raise exception 'REVERSA: hay funciones que dependen de la Fase 4; retíralas antes';
  end if;
end $pre$;

-- Cuerpos de antes, tal como los devolvía pg_get_functiondef en producción el 23/09.
CREATE OR REPLACE FUNCTION crm.preparar_inversion_fn(p_clave uuid, p_datos jsonb)
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
  v_ctx := private.inversion_persona_autorizada(v_persona);
  v_hash := private.idem_hash(p_datos);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('f4_solicitud:'||p_clave::text,0));
  select * into v_s from crm.inversion_solicitudes where id=p_clave for update;
  if found then
    if v_s.hash_payload<>v_hash or v_s.inversionista_id<>v_persona then
      raise exception 'La misma clave llegó con datos distintos' using errcode='P0409';
    end if;
    if v_s.estado<>'confirmada' then
      v_ctx := private.inversion_persona_contexto(v_persona,v_lead);
    end if;
    return private.inversion_solicitud_resultado(v_s.id,v_ctx);
  end if;
  v_ctx := private.inversion_persona_contexto(v_persona,v_lead);
  if v_lead is not null and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=v_lead and estado in ('preparada','confirmada')) then
    raise exception 'Este lead ya tiene una solicitud: retómala antes de crear otra' using errcode='P0409';
  end if;
  v_e.id:=private.inversion_validar_datos(p_clave,p_datos,v_ctx);
  insert into crm.inversion_solicitudes(id,inversionista_id,empresa_id,responsable_esperado_id,hash_payload,datos,creado_por,lead_origen_id)
  values(p_clave,v_persona,v_e.id,(v_ctx->>'responsable_id')::uuid,v_hash,p_datos,(select auth.uid()),v_lead);
  return private.inversion_solicitud_resultado(p_clave,v_ctx);
end;
$function$;

CREATE OR REPLACE FUNCTION crm.datos_legales_contrato_fn(p_cliente_id uuid)
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

comment on function crm.preparar_inversion_fn(uuid,jsonb) is null;

drop function crm.buscar_cliente_existente_fn(text,text,text,uuid);
drop function crm.contexto_cliente_existente_fn(uuid,uuid);
drop function crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text);
drop function crm.cuentas_cliente_existente_fn(uuid,uuid,text);
drop function crm.datos_legales_cliente_existente_fn(uuid,uuid);
drop function private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text);
drop function crm.contratos_upgrade_cliente_existente_fn(uuid,uuid);
drop function private.datos_legales_contrato_nucleo(uuid);
drop function private.inversionista_es_cliente(uuid);
drop function private.busquedas_cliente_ultima_hora(uuid);
drop function private.venta_cruzada_motivo(text);
drop function private.venta_cruzada_lectura(uuid,uuid,boolean);

do $post$ begin
  if md5(pg_get_functiondef('crm.preparar_inversion_fn(uuid,jsonb)'::regprocedure)) <> '14fbc1f7153309e10d0c80bde1f4a1f7'
     or md5(pg_get_functiondef('crm.datos_legales_contrato_fn(uuid)'::regprocedure)) <> '7eab5cd09d1b90075e692cbd822d2d27' then
    raise exception 'REVERSA: los envoltorios no volvieron al byte a su cuerpo de antes';
  end if;
  if (select proacl::text from pg_proc where oid = 'crm.preparar_inversion_fn(uuid,jsonb)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'crm.datos_legales_contrato_fn(uuid)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'REVERSA: los permisos de los envoltorios cambiaron';
  end if;
  if to_regprocedure('crm.buscar_cliente_existente_fn(text,text,text,uuid)') is not null
     or to_regprocedure('crm.contexto_cliente_existente_fn(uuid,uuid)') is not null
     or to_regprocedure('crm.preparar_inversion_cliente_existente_fn(uuid,uuid,jsonb,text)') is not null
     or to_regprocedure('crm.cuentas_cliente_existente_fn(uuid,uuid,text)') is not null
     or to_regprocedure('crm.datos_legales_cliente_existente_fn(uuid,uuid)') is not null
     or to_regprocedure('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)') is not null
     or to_regprocedure('crm.contratos_upgrade_cliente_existente_fn(uuid,uuid)') is not null
     or to_regprocedure('private.datos_legales_contrato_nucleo(uuid)') is not null
     or to_regprocedure('private.inversionista_es_cliente(uuid)') is not null
     or to_regprocedure('private.busquedas_cliente_ultima_hora(uuid)') is not null
     or to_regprocedure('private.venta_cruzada_motivo(text)') is not null
     or to_regprocedure('private.venta_cruzada_lectura(uuid,uuid,boolean)') is not null then
    raise exception 'REVERSA: quedaron restos de la Fase 4';
  end if;
end $post$;

commit;
select 'REVERSA_FASE4_OK' as veredicto;
