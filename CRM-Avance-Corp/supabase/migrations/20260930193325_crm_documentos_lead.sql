-- Documentos del lead: la identidad canónica conserva DNI/CE/PASAPORTE.
-- crm.leads.dni sigue siendo exclusivamente DNI para mantener las puertas legadas.
-- No modifica tablas, policies ni objetos de public. Ensayar antes de publicar.
-- Reversa: retirar el frontend nuevo y eliminar estas cuatro RPC y el validador.
begin;

-- Fuentes contrastadas con producción el 30/09/2026. Si otra tarea cambia una
-- puerta de identidad, volver a ensayar antes de instalar este envoltorio.
do $$ declare r record; begin
  for r in select * from (values
    ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)','54fc34f7357d4d5688f210df6c521045'),
    ('crm.editar_lead_fn(uuid,jsonb)','f2c1b7665ae58bea071499e04d970290'),
    ('crm.fijar_dni_lead_fn(uuid,text)','3b92916944a76fb7bcbc3bce603e4788'),
    ('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)','cbcb6c436c6b406121c9af79bb808dd1'),
    ('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)','d1c9358dff1d7565cf01bb546151619f'),
    ('private.inversionista_resolver(text,text,boolean,text)','c3827954ad2e86783284f239440b7074'),
    ('private.identidad_bloquear_documentos_de(uuid[])','9bd7251cf7482137b6e6f4d5b40facda'),
    ('private.juicio_persona(uuid,uuid)','2570f6eab5ae8b076e6f759b43b9b659'),
    ('private.leads_de_identidades(uuid[])','47f780bca25df39eda0ad16f2cbdaf56'),
    ('private.resolver_en_puertas_bajo_candado()','3d0fb83b13c9950461184de7c678ba64')
  ) fuentes(firma,huella) loop
    if (select md5(prosrc) from pg_proc where oid=to_regprocedure(r.firma)) is distinct from r.huella then
      raise exception 'La fuente % cambió; revisar y ensayar documentos antes de aplicar',r.firma;
    end if;
  end loop;
end $$;

create or replace function private.validar_documento_lead(p_tipo text, p_numero text)
returns text language plpgsql immutable set search_path='' as $$
declare v_numero text := nullif(upper(btrim(p_numero)), '');
begin
  if p_tipo is null or p_tipo not in ('DNI','CE','PASAPORTE') then
    raise exception 'Selecciona DNI, Carné de Extranjería o Pasaporte' using errcode='22023';
  end if;
  if v_numero is not null and not (
    (p_tipo='DNI' and v_numero ~ '^[0-9]{8}$') or
    (p_tipo='CE' and v_numero ~ '^[0-9]{9,12}$') or
    (p_tipo='PASAPORTE' and v_numero ~ '^[A-Z0-9]{6,12}$')) then
    raise exception 'Documento inválido para el tipo seleccionado' using errcode='22023';
  end if;
  return v_numero;
end $$;
revoke all on function private.validar_documento_lead(text,text) from public,anon,authenticated,service_role;
comment on function private.validar_documento_lead(text,text) is 'Valida tipo y número completos; conserva ceros iniciales y nunca recorta ni elimina letras.';

create or replace function crm.documento_lead_fn(p_lead_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_l crm.leads%rowtype; v_d crm.inversionista_identificadores%rowtype; v_persona uuid; v_personas uuid[];
begin
  if (select auth.uid()) is null or not coalesce(private.puede_acceder_crm(),false) then
    raise exception 'Acceso CRM revocado' using errcode='42501';
  end if;
  -- Mismo ámbito y gate restrictivo que leads_select; no consulta documentos ajenos.
  select * into v_l from crm.leads l where l.id=p_lead_id and l.activo and (
    l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid()))) or
    (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid())))) or
    private.rol_crm((select auth.uid()))='gerencia' or private.es_lector_global());
  if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='P0002'; end if;
  select array_agg(distinct id) into v_personas from (
    select private.inversionista_canonica(v_l.inversionista_id) id
    union select private.inversionista_canonica(il.inversionista_id)
      from crm.inversionista_leads il where il.lead_id=p_lead_id
  ) personas where id is not null;
  if cardinality(v_personas)>1 then
    raise exception 'El lead tiene varias identidades; requiere conciliación administrativa' using errcode='P0409';
  end if;
  v_persona := v_personas[1];
  select * into v_d from crm.inversionista_identificadores d
    where d.inversionista_id=v_persona and d.estado='vigente' and d.verificado
    order by case d.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,d.id limit 1;
  return jsonb_build_object('lead_id',p_lead_id,'inversionista_id',v_persona,
    'identificador_id',v_d.id,'tipo',coalesce(v_d.tipo_documento,'DNI'),
    'numero',coalesce(v_d.documento_normalizado,v_l.dni),
    'puede_corregir',coalesce(public.es_admin(),false));
end $$;
revoke all on function crm.documento_lead_fn(uuid) from public,anon,service_role;
grant execute on function crm.documento_lead_fn(uuid) to authenticated;
comment on function crm.documento_lead_fn(uuid) is 'PII: documento canónico de un lead visible, con fallback al DNI legado. Mismo ámbito que leads_select; sin acceso directo a identificadores.';

create or replace function crm.fijar_documento_lead_fn(p_lead_id uuid,p_tipo text,p_documento text,
  p_identificador_anterior uuid default null,p_motivo text default null)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_uid uuid := (select auth.uid()); v_rol text := private.rol_crm((select auth.uid()));
  v_pre crm.leads%rowtype; v_l crm.leads%rowtype; v_i crm.inversionistas%rowtype;
  v_numero text; v_persona uuid; v_documento jsonb; v_juicio jsonb; v_k record; v_operacion jsonb;
  v_priv text := coalesce(current_setting('crm.op_privilegiada',true),'off');
  v_correccion text := coalesce(current_setting('crm.correccion_documento',true),'off');
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor','supervisor','gerencia')
    or not coalesce(private.puede_acceder_crm(),false) then
    raise exception 'Acceso CRM revocado' using errcode='42501';
  end if;
  select * into v_pre from crm.leads l where l.id=p_lead_id and l.activo and (
    v_rol='gerencia' or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid)) or
    (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))));
  if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='P0002'; end if;
  if v_pre.etapa in ('convertido','descartado') then
    raise exception 'El lead está cerrado; su documento se corrige desde la ficha del cliente' using errcode='P0409';
  end if;
  v_numero := private.validar_documento_lead(p_tipo,p_documento);
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'La identidad unificada no está habilitada' using errcode='P0409';
  end if;
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_documento := crm.documento_lead_fn(p_lead_id);
  if v_documento->>'inversionista_id' is not null then
    if p_identificador_anterior is not null and p_identificador_anterior::text is distinct from v_documento->>'identificador_id' then
      raise exception 'El documento cambió en otra sesión; vuelve a cargar la ficha' using errcode='P0409';
    end if;
    if p_tipo=v_documento->>'tipo' and v_numero is not distinct from v_documento->>'numero' then
      perform private.identidad_bloquear_documentos_de(array[(v_documento->>'inversionista_id')::uuid]);
      perform 1 from crm.inversionistas where id=(v_documento->>'inversionista_id')::uuid for share;
      select * into v_l from crm.leads where id=p_lead_id for update nowait;
      if private.rol_crm(v_uid) is distinct from v_rol or v_l.etapa in ('convertido','descartado')
        or crm.documento_lead_fn(p_lead_id) is distinct from v_documento then
        raise exception 'El documento o el lead cambió; vuelve a cargar la ficha' using errcode='P0409';
      end if;
      return v_documento;
    end if;
    if not coalesce(public.es_admin(),false) then
      raise exception 'Solo Administración puede corregir el documento de una identidad ya vinculada' using errcode='42501';
    end if;
    if v_numero is null or p_identificador_anterior is null then
      raise exception 'La corrección requiere el documento anterior y un número válido' using errcode='22023';
    end if;
    v_operacion := crm.corregir_documento_inversionista_fn((v_documento->>'inversionista_id')::uuid,
      p_tipo,v_numero,p_motivo,p_identificador_anterior);
    perform set_config('crm.op_privilegiada',v_priv,true);
    perform set_config('crm.correccion_documento',v_correccion,true);
    -- La puerta histórica corrige el primer lead directo de la persona.
    -- La operación auditada debe corresponder al lead solicitado. La persona
    -- puede tener varios leads; un éxito en otro lead se revierte por completo.
    if (select lead_id from crm.inversionista_operaciones
        where id=(v_operacion->>'operacion_id')::uuid) is distinct from p_lead_id then
      raise exception 'La corrección requiere conciliar los leads de esta persona; no se guardó ningún cambio' using errcode='P0409';
    end if;
    -- No confirmar una corrección si el lead objetivo conserva un DNI anterior.
    select * into v_l from crm.leads where id=p_lead_id;
    if private.inversionista_canonica(v_l.inversionista_id) is distinct from (v_documento->>'inversionista_id')::uuid
      or (v_l.dni is not null and (p_tipo<>'DNI' or v_l.dni is distinct from v_numero)) then
      raise exception 'La corrección requiere conciliar los leads de esta persona; no se guardó ningún cambio' using errcode='P0409';
    end if;
    v_documento := crm.documento_lead_fn(p_lead_id);
    if v_documento->>'tipo' is distinct from p_tipo or v_documento->>'numero' is distinct from v_numero then
      raise exception 'La persona tiene varios documentos; requiere conciliación administrativa. No se guardó ningún cambio' using errcode='P0409';
    end if;
    return v_documento;
  end if;
  if p_identificador_anterior is not null then
    raise exception 'La identidad cambió; vuelve a cargar la ficha' using errcode='P0409';
  end if;
  if p_tipo<>'DNI' and v_numero is null and v_pre.dni is not null then
    raise exception 'Introduce el número completo del documento seleccionado' using errcode='22023';
  end if;
  -- Los DNI sin identidad conservan la puerta DEFINER con auth.uid(), rol,
  -- ámbito y candados explícitos existentes; no depende de RLS del invocador.
  if p_tipo='DNI' or v_numero is null then
    perform crm.fijar_dni_lead_fn(p_lead_id,v_numero);
    return crm.documento_lead_fn(p_lead_id);
  end if;
  -- Documento anterior y nuevo, orden global; luego persona y al final lead.
  for v_k in select t,n from (values ('DNI',v_pre.dni),(p_tipo,v_numero)) d(t,n)
    where n is not null order by t||':'||n loop
    perform private.identidad_bloquear_documento(v_k.t,v_k.n);
  end loop;
  v_persona := private.inversionista_resolver(p_tipo,v_numero,true,'documento_lead');
  select * into v_i from crm.inversionistas where id=v_persona for update;
  select * into v_l from crm.leads where id=p_lead_id for update nowait;
  if not found or not v_l.activo or private.rol_crm(v_uid) is distinct from v_rol or
    not coalesce((v_rol='gerencia' or v_l.vendedor_id in (select private.vendedor_ids_visibles(v_uid)) or
      (v_l.vendedor_id is null and v_l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))),false) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='P0002';
  end if;
  if v_l.dni is distinct from v_pre.dni or v_l.inversionista_id is distinct from v_pre.inversionista_id
    or exists(select 1 from crm.inversionista_leads where lead_id=p_lead_id) then
    raise exception 'La identidad cambió; vuelve a cargar la ficha' using errcode='P0409';
  end if;
  if v_l.etapa in ('convertido','descartado') then
    raise exception 'El lead está cerrado' using errcode='P0409';
  end if;
  if v_l.no_contactar or v_i.no_contactar or v_i.estado<>'activo' then
    raise exception 'El contacto no permite nuevas gestiones' using errcode='P0429';
  end if;
  v_juicio := private.juicio_persona(v_persona,p_lead_id);
  if v_juicio is not null or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead_id) then
    raise exception 'La persona de ese documento ya es cliente o tiene otro lead' using errcode='P0409';
  end if;
  if exists(select 1 from crm.conversion_reservas r where r.lead_id=p_lead_id
      and (r.expira_en>now() or r.efectos_iniciados_en is not null)) or
    exists(select 1 from crm.inversion_solicitudes s where s.lead_origen_id=p_lead_id and s.estado in ('preparada','confirmada')) then
    raise exception 'El lead tiene una conversión en curso; revisa su identidad antes de editar' using errcode='P0409';
  end if;
  perform set_config('crm.op_privilegiada','on',true);
  update crm.leads set dni=null,inversionista_id=v_persona where id=p_lead_id;
  perform set_config('crm.op_privilegiada',v_priv,true);
  return crm.documento_lead_fn(p_lead_id);
end $$;
revoke all on function crm.fijar_documento_lead_fn(uuid,text,text,uuid,text) from public,anon,service_role;
grant execute on function crm.fijar_documento_lead_fn(uuid,text,text,uuid,text) to authenticated;
comment on function crm.fijar_documento_lead_fn(uuid,text,text,uuid,text) is 'Documento de un lead en ámbito. CE/pasaporte enlazan identidad canónica; cambiar una identidad reconocida exige la corrección administrativa auditada existente.';

create or replace function crm.editar_lead_documento_fn(p_lead_id uuid,p_cambios jsonb,p_tipo text,p_documento text,
  p_identificador_anterior uuid default null,p_motivo text default null)
returns jsonb language plpgsql security invoker set search_path='' set lock_timeout='5s' as $$
begin
  if p_cambios is null or jsonb_typeof(p_cambios)<>'object' or p_cambios ? 'dni' then
    raise exception 'Los datos del documento deben enviarse juntos, con su tipo' using errcode='22023';
  end if;
  perform crm.fijar_documento_lead_fn(p_lead_id,p_tipo,p_documento,p_identificador_anterior,p_motivo);
  if p_cambios<>'{}'::jsonb then
    perform crm.editar_lead_fn(p_lead_id,p_cambios);
  end if;
  return crm.documento_lead_fn(p_lead_id);
end $$;
revoke all on function crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text) from public,anon,service_role;
grant execute on function crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text) to authenticated;
comment on function crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text) is 'Edición atómica de documento y ficha. SECURITY INVOKER conserva RLS y grants por columna de editar_lead_fn; cualquier fallo revierte toda la operación.';

create or replace function crm.crear_lead_documento_fn(p_datos jsonb,p_tipo text,p_documento text)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_uid uuid := (select auth.uid()); v_rol text := private.rol_crm((select auth.uid()));
  v_id uuid; v_numero text; v_persona uuid; v_resultado jsonb; v_pre crm.leads%rowtype; v_doc jsonb; v_k text;
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor','supervisor','gerencia')
    or not coalesce(private.puede_acceder_crm(),false) then
    raise exception 'Acceso CRM revocado' using errcode='42501';
  end if;
  if p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Datos de alta inválidos' using errcode='22023';
  end if;
  for v_k in select jsonb_object_keys(p_datos) loop
    if not v_k=any(array['id','nombre_completo','telefono','telefono_alternativo','correo','genero',
      'fecha_nacimiento','distrito','origen','etapa','monto_estimado','moneda','categoria_interes','vendedor_id','nota']) then
      raise exception 'Campo no permitido en el alta: %',v_k using errcode='22023';
    end if;
  end loop;
  v_numero := private.validar_documento_lead(p_tipo,p_documento);
  v_id := coalesce((p_datos->>'id')::uuid,gen_random_uuid());
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'La identidad unificada no está habilitada' using errcode='P0409';
  end if;
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  perform pg_advisory_xact_lock(hashtextextended('avancecrm:lead:id:'||v_id::text,0));
  select * into v_pre from crm.leads where id=v_id;
  if found then
    if v_pre.creado_por is distinct from v_uid then
      raise exception 'El identificador de esta alta ya fue usado con datos distintos' using errcode='22023';
    end if;
    v_doc := crm.documento_lead_fn(v_id);
    if (v_numero is not null and p_tipo is distinct from v_doc->>'tipo') or
      v_numero is distinct from v_doc->>'numero' then
      raise exception 'El identificador de esta alta ya fue usado con otro documento' using errcode='22023';
    end if;
  end if;
  -- Antes de contactos/fila se bloquea la identidad existente, SIN crearla.
  -- Una identidad nueva solo nace tras confirmar que el alta está disponible.
    if p_tipo<>'DNI' and v_numero is not null then
      perform private.identidad_bloquear_documento(p_tipo,v_numero);
      v_persona := private.inversionista_por_documento(p_tipo,v_numero);
      perform 1 from crm.inversionistas where id=v_persona for update;
    end if;
    -- Esta puerta es DEFINER y autoriza por auth.uid(): rol, autoasignación,
    -- destino visible y etapas no terminales; conserva sus propios candados.
    v_resultado := crm.crear_lead_si_disponible(
      p_nombre_completo=>p_datos->>'nombre_completo',p_telefono=>p_datos->>'telefono',
      p_origen=>p_datos->>'origen',p_monto_estimado=>(p_datos->>'monto_estimado')::numeric,
      p_moneda=>p_datos->>'moneda',p_id=>v_id,p_correo=>p_datos->>'correo',
      p_dni=>case when p_tipo='DNI' then v_numero else null end,
      p_genero=>p_datos->>'genero',p_fecha_nacimiento=>(p_datos->>'fecha_nacimiento')::date,
      p_distrito=>p_datos->>'distrito',p_etapa=>coalesce(p_datos->>'etapa','nuevo'),
      p_categoria_interes=>p_datos->>'categoria_interes',p_vendedor_id=>(p_datos->>'vendedor_id')::uuid,
      p_nota=>p_datos->>'nota',p_telefono_alternativo=>p_datos->>'telefono_alternativo');
    if v_resultado->>'estado' is distinct from 'creado' then
      return v_resultado;
    end if;
    if p_tipo<>'DNI' and v_numero is not null then
      perform crm.fijar_documento_lead_fn(v_id,p_tipo,v_numero);
    end if;

  return v_resultado;
end $$;
revoke all on function crm.crear_lead_documento_fn(jsonb,text,text) from public,anon,service_role;
grant execute on function crm.crear_lead_documento_fn(jsonb,text,text) to authenticated;
comment on function crm.crear_lead_documento_fn(jsonb,text,text) is 'Alta atómica e idempotente con documento tipado. Reutiliza validación/destinos de crear_lead_si_disponible y enlaza CE/pasaporte sin alterar el DNI legado.';
notify pgrst,'reload schema';
commit;
