-- F4: módulos de construcción. Se ensamblan en una sola migración con guardas.
-- No ejecutar por separado en producción.

alter table crm.cierres_externos
  add column es_cierre_inicial boolean not null default true,
  add column fecha_comercial date,
  add column fecha_imputacion date,
  add column comprobante_objeto_id uuid references storage.objects(id);

comment on column crm.cierres_externos.es_cierre_inicial is
  'Distingue la conversión inicial del lead de una inversión posterior. No determina elegibilidad de renovaciones/upgrades.';
comment on column crm.cierres_externos.fecha_comercial is
  'Fecha propia de la inversión F4. NULL conserva exactamente la fecha histórica de creado_en.';
comment on column crm.cierres_externos.fecha_imputacion is
  'Fecha usada por Capital. Igual a fecha_comercial en mes abierto; día de registro para un ajuste de mes ya sellado. creado_en conserva el instante de registro.';

alter table crm.cierres_externos
  alter column lead_id drop not null,
  add constraint cierres_iniciales_requieren_lead check (not es_cierre_inicial or lead_id is not null),
  add constraint cierres_f4_datos_completos check (
    es_cierre_inicial or (
      inversionista_id is not null and fecha_comercial is not null
      and fecha_imputacion is not null and comprobante_objeto_id is not null
      and referencia_externa is not null
    )
  ),
  add constraint cierres_f4_fechas_validas check (
    (fecha_comercial is null and fecha_imputacion is null) or (
      fecha_comercial is not null and fecha_imputacion is not null
      and isfinite(fecha_comercial) and isfinite(fecha_imputacion)
      and fecha_comercial <= fecha_imputacion
      and fecha_imputacion <= (creado_en at time zone 'America/Lima')::date
    )
  );

create table crm.inversion_solicitudes (
  id uuid primary key,
  inversionista_id uuid not null references crm.inversionistas(id),
  empresa_id uuid not null references crm.empresas(id),
  responsable_esperado_id uuid not null references public.perfiles(id),
  auth_claim_id uuid,
  auth_contexto jsonb,
  hash_payload text not null check (hash_payload ~ '^[a-f0-9]{64}$'),
  datos jsonb not null check (jsonb_typeof(datos) = 'object'),
  revision_datos integer not null default 0 check(revision_datos>=0),
  estado text not null default 'preparada' check (estado in ('preparada','confirmada','cancelada')),
  inversion_id uuid unique references crm.inversiones(id),
  resultado jsonb,
  creado_por uuid not null references public.perfiles(id),
  confirmado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default statement_timestamp(),
  actualizado_en timestamptz not null default statement_timestamp(),
  constraint inversion_solicitud_confirmada check (
    (estado = 'confirmada') = (inversion_id is not null and resultado is not null and confirmado_por is not null)
  ),
  constraint inversion_solicitud_auth_contexto check (
    (auth_claim_id is null and auth_contexto is null) or
    (auth_claim_id is not null and auth_contexto is not null and jsonb_typeof(auth_contexto)='object')
  )
);
create index inversion_solicitudes_auth_idx on crm.inversion_solicitudes(auth_claim_id) where auth_claim_id is not null;
create index inversion_solicitudes_persona_idx on crm.inversion_solicitudes(inversionista_id,estado);
create index inversion_solicitudes_empresa_idx on crm.inversion_solicitudes(empresa_id);
create index inversion_solicitudes_responsable_idx on crm.inversion_solicitudes(responsable_esperado_id);
create index inversion_solicitudes_creador_idx on crm.inversion_solicitudes(creado_por);
create index inversion_solicitudes_confirmador_idx on crm.inversion_solicitudes(confirmado_por);

create table crm.inversion_solicitud_revisiones (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references crm.inversion_solicitudes(id),
  revision integer not null check (revision>0),
  responsable_anterior_id uuid not null references public.perfiles(id),
  responsable_nuevo_id uuid not null references public.perfiles(id),
  motivo text not null,
  revisado_por uuid not null references public.perfiles(id),
  transaccion xid8 not null default pg_current_xact_id(),
  revisado_en timestamptz not null default statement_timestamp(),
  unique(solicitud_id,revision),
  check(responsable_anterior_id<>responsable_nuevo_id)
);
create index inversion_revision_anterior_idx on crm.inversion_solicitud_revisiones(responsable_anterior_id);
create index inversion_revision_nuevo_idx on crm.inversion_solicitud_revisiones(responsable_nuevo_id);
create index inversion_revision_actor_idx on crm.inversion_solicitud_revisiones(revisado_por);
alter table crm.inversion_solicitud_revisiones enable row level security;
revoke all on crm.inversion_solicitud_revisiones from public,anon,authenticated,service_role;
create trigger trg_audit_inversion_revision after insert on crm.inversion_solicitud_revisiones
  for each row execute function private.log_audit_sin_secretos('motivo');

create table crm.inversion_ajustes_mes_cerrado (
  inversion_id uuid primary key references crm.inversiones(id),
  periodo_origen date not null references crm.periodos_cerrados(periodo),
  fecha_imputacion date not null,
  creado_por uuid not null references public.perfiles(id),
  creado_en timestamptz not null default statement_timestamp(),
  check (periodo_origen = date_trunc('month',periodo_origen)::date),
  check (fecha_imputacion > periodo_origen)
);
create index inversion_ajustes_periodo_idx on crm.inversion_ajustes_mes_cerrado(periodo_origen);
create index inversion_ajustes_creador_idx on crm.inversion_ajustes_mes_cerrado(creado_por);
comment on table crm.inversion_ajustes_mes_cerrado is
  'Rastro append-only de inversiones registradas después del sello de su mes. No copia monto, moneda, comisión ni conversión: remite a la inversión y a su fuente.';

create table crm.inversion_eventos (
  id uuid primary key default gen_random_uuid(),
  inversion_id uuid not null references crm.inversiones(id),
  tipo text not null check (tipo in ('registro','correccion','anulacion')),
  motivo text,
  creado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default statement_timestamp()
);
create index inversion_eventos_inversion_idx on crm.inversion_eventos(inversion_id,creado_en);
create index inversion_eventos_creador_idx on crm.inversion_eventos(creado_por);

alter table crm.inversion_solicitudes enable row level security;
alter table crm.inversion_ajustes_mes_cerrado enable row level security;
alter table crm.inversion_eventos enable row level security;
revoke all on crm.inversion_solicitudes, crm.inversion_ajustes_mes_cerrado, crm.inversion_eventos from public,anon,authenticated,service_role;
create trigger trg_audit_inversion_solicitudes after insert or update or delete on crm.inversion_solicitudes
  for each row execute function private.log_audit_sin_secretos('datos','auth_contexto');
create trigger trg_audit_inversion_ajustes after insert on crm.inversion_ajustes_mes_cerrado
  for each row execute function private.log_audit_crm();
create trigger trg_audit_inversion_eventos after insert on crm.inversion_eventos
  for each row execute function private.log_audit_sin_secretos('motivo');

create or replace function private.inversiones_escritura_bajo_candado()
returns boolean language plpgsql security definer set search_path='' as $$
begin
  -- Orden común: bandera identidad -> bandera inversión -> jerarquía -> documentos -> persona.
  if not private.resolver_en_puertas_bajo_candado() then return false; end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_inversiones_escritura'));
  return coalesce((select activo from crm.multiempresa_flags where nombre='inversiones_escritura'),false);
end;
$$;
revoke all on function private.inversiones_escritura_bajo_candado() from public,anon,authenticated,service_role;

-- Autoriza y bloquea la identidad vigente. Una lectura de una inversión ya
-- confirmada conserva el ámbito actual, aunque después se haya vetado operar.
create or replace function private.inversion_persona_autorizada(p_persona uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_i crm.inversionistas%rowtype;
  v_docs text[];
  v_docs_actuales text[];
  v_persona uuid;
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  if not private.inversiones_escritura_bajo_candado() then
    raise exception 'El registro multiempresa todavía no está habilitado' using errcode='P0409';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_rol := private.rol_crm(v_uid);
  if v_rol is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  -- La solicitud conserva la identidad con que nació. La autorización y los
  -- nuevos hechos pertenecen a su canónica vigente, también tras otra fusión.
  v_persona := private.inversionista_canonica(p_persona);
  v_docs := private.identidad_bloquear_documentos_de(array[v_persona]);
  select * into v_i from crm.inversionistas where id=v_persona for update;
  if not found or not coalesce((
    v_rol='gerencia' or v_i.responsable_relacion_id in (select private.vendedor_ids_visibles(v_uid))
  ),false) then
    raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode='42501';
  end if;
  if private.inversionista_canonica(p_persona) is distinct from v_persona then
    raise exception 'La identidad cambió mientras se esperaba; vuelve a cargar la persona' using errcode='40001';
  end if;
  select coalesce(array_agg(k order by k),'{}') into v_docs_actuales
  from (select distinct tipo_documento||':'||documento_normalizado as k
        from crm.inversionista_identificadores where inversionista_id=v_persona and estado='vigente') d;
  if v_docs is distinct from v_docs_actuales then
    raise exception 'El documento cambió durante la operación; vuelve a cargar la persona' using errcode='40001';
  end if;
  return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
    'responsable_id',v_i.responsable_relacion_id);
end;
$$;
revoke all on function private.inversion_persona_autorizada(uuid) from public,anon,authenticated,service_role;

-- Las altas nuevas y los pasos todavía pendientes mantienen todas las puertas
-- comerciales. La autorización anterior no basta para escribir una inversión.
create or replace function private.inversion_persona_contexto(p_persona uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_i crm.inversionistas%rowtype;
  v_p public.perfiles%rowtype;
  v_l crm.leads%rowtype;
  v_doc crm.inversionista_identificadores%rowtype;
  v_leads uuid[];
  v_nombre text;
  v_persona uuid;
begin
  v_persona := (private.inversion_persona_autorizada(p_persona)->>'inversionista_id')::uuid;
  select * into v_i from crm.inversionistas where id=v_persona for update;
  if v_i.estado <> 'activo' or v_i.no_contactar then
    raise exception 'La persona no permite nuevas inversiones: revisa su estado o No insistir' using errcode='P0429';
  end if;
  if v_i.responsable_relacion_id is null or not exists (
    select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.perfil_id=v_i.responsable_relacion_id and e.activo and p.activo
      and e.rol_crm in ('vendedor','supervisor')
  ) then
    raise exception 'Asigna un responsable comercial activo antes de registrar la inversión' using errcode='P0409';
  end if;
  select * into v_doc from crm.inversionista_identificadores
  where inversionista_id=v_persona and estado='vigente' and verificado
  order by case tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,id limit 1;
  if not found then
    raise exception 'La inversión requiere un documento verificado' using errcode='P0409';
  end if;
  if v_i.perfil_id is not null then
    select * into v_p from public.perfiles where id=v_i.perfil_id for share;
    if not found or v_p.activo is not true or v_p.rol <> 'cliente' then
      raise exception 'El perfil Avance requiere revisión antes de operar' using errcode='P0409';
    end if;
    if not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
      raise exception 'El documento del perfil requiere conciliación con la persona' using errcode='P0409';
    end if;
  end if;
  select array_agg(distinct id order by id) into v_leads from (
    select l.id from crm.leads l where l.inversionista_id=v_persona
    union select il.lead_id from crm.inversionista_leads il
      where il.inversionista_id=v_persona and il.rol='canonico'
  ) l;
  if coalesce(cardinality(v_leads),0)>1 then
    raise exception 'Hay más de un lead canónico; corresponde conciliación de identidad' using errcode='P0409';
  end if;
  if cardinality(v_leads)=1 then
    -- NOWAIT mantiene el orden de la corrección/fusión y evita esperar una reasignación que ya tomó el lead.
    select * into v_l from crm.leads where id=v_leads[1] for share nowait;
    if v_l.no_contactar then
      raise exception 'La persona tiene No insistir en su lead' using errcode='P0429';
    end if;
    if v_l.etapa <> 'convertido' then
      raise exception 'Completa la conversión inicial antes de registrar otra inversión' using errcode='P0409';
    end if;
  end if;
  v_nombre := coalesce(nullif(btrim(v_p.nombre_completo),''),nullif(btrim(v_l.nombre_completo),''),
    (select ce.nombre_completo from crm.cierres_externos ce where ce.inversionista_id=v_persona order by ce.creado_en desc,ce.id desc limit 1));
  if v_nombre is null then
    raise exception 'La persona necesita un antecedente con su nombre completo' using errcode='P0409';
  end if;
  return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
    'responsable_id',v_i.responsable_relacion_id,'lead_id',v_l.id,
    'documento_tipo',v_doc.tipo_documento,'documento',v_doc.documento_normalizado,'nombre',v_nombre);
end;
$$;
revoke all on function private.inversion_persona_contexto(uuid) from public,anon,authenticated,service_role;

create or replace function private.inversion_solicitud_resultado(p_id uuid,p_contexto jsonb)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('solicitud_id',s.id,'estado',s.estado,'inversion_id',s.inversion_id,
    'inversionista_id',p_contexto->>'inversionista_id','inversionista_origen_id',s.inversionista_id,
    'identidad_fusionada',s.inversionista_id::text is distinct from p_contexto->>'inversionista_id',
    'responsable_esperado_id',s.responsable_esperado_id,'responsable_actual_id',p_contexto->>'responsable_id',
    'requiere_revision_responsable',s.estado='preparada' and s.responsable_esperado_id::text is distinct from p_contexto->>'responsable_id',
    'revision_datos',s.revision_datos,'hash_datos',private.idem_hash(s.datos),
    'revision_responsable',coalesce((select max(r.revision) from crm.inversion_solicitud_revisiones r where r.solicitud_id=s.id),0),
    'resultado',case when s.resultado is not null then s.resultado||jsonb_build_object('inversionista_id',p_contexto->>'inversionista_id') end,
    'necesita_portal',e.requiere_portal and p_contexto->>'perfil_id' is null,
    'comprobante_bucket',case when e.fuente_capital='cierres_externos' then 'f4-comprobantes' else null end,
    'comprobante_ruta',s.datos#>>'{evidencia,ruta}')
  from crm.inversion_solicitudes s join crm.empresas e on e.id=s.empresa_id where s.id=p_id;
$$;
revoke all on function private.inversion_solicitud_resultado(uuid,jsonb) from public,anon,authenticated,service_role;

create or replace function private.inversion_datos_portal(p_datos jsonb)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare v_correo text; v_nombre text; v_domicilio text;
begin
  if jsonb_typeof(p_datos) is distinct from 'object' then
    raise exception 'Completa los datos para el acceso Avance de esta persona' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_datos) k where k not in
    ('correo','nombre_completo','apellidos','nombres','telefono','domicilio'))
    or exists(select 1 from jsonb_each(p_datos) d where jsonb_typeof(d.value) not in ('string','null')) then
    raise exception 'El alta Avance contiene campos no admitidos; documento y responsable los determina el servidor' using errcode='22023';
  end if;
  v_correo:=lower(btrim(p_datos->>'correo'));
  v_nombre:=upper(btrim(p_datos->>'nombre_completo'));
  if v_correo is null or length(v_correo)>254 or v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or v_nombre is null or length(v_nombre) not between 2 and 240 or v_nombre ~ '[[:cntrl:]]' then
    raise exception 'Completa el nombre legal y un correo válido para el acceso Avance' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_each_text(p_datos) d where d.key in ('apellidos','nombres','telefono')
    and (length(d.value)>240 or d.value ~ '[[:cntrl:]]')) then
    raise exception 'Revisa los nombres y el teléfono del cliente' using errcode='22023';
  end if;
  v_domicilio:=crm.normalizar_domicilio_legal(p_datos->>'domicilio');
  return jsonb_build_object('correo',v_correo,'nombre_completo',v_nombre,
    'apellidos',nullif(upper(btrim(p_datos->>'apellidos')),''),
    'nombres',nullif(upper(btrim(p_datos->>'nombres')),''),
    'telefono',nullif(btrim(p_datos->>'telefono'),''),'domicilio',v_domicilio);
end;
$$;
revoke all on function private.inversion_datos_portal(jsonb) from public,anon,authenticated,service_role;

create or replace function crm.preparar_inversion_fn(p_clave uuid,p_datos jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_persona uuid;
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
    'inversionista_id','empresa','monto','moneda','fecha_comercial','vence_en','numero_transaccion',
    'referencia','evidencia','producto_condicion_id','contrato','cronograma','cuenta','alta_portal'
  )) then
    raise exception 'La solicitud contiene campos no admitidos' using errcode='22023';
  end if;
  begin v_persona := (p_datos->>'inversionista_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Identificador de persona inválido' using errcode='22023';
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
      v_ctx := private.inversion_persona_contexto(v_persona);
    end if;
    return private.inversion_solicitud_resultado(v_s.id,v_ctx);
  end if;
  v_ctx := private.inversion_persona_contexto(v_persona);
  v_e.id:=private.inversion_validar_datos(p_clave,p_datos,v_ctx);
  insert into crm.inversion_solicitudes(id,inversionista_id,empresa_id,responsable_esperado_id,hash_payload,datos,creado_por)
  values(p_clave,v_persona,v_e.id,(v_ctx->>'responsable_id')::uuid,v_hash,p_datos,(select auth.uid()));
  return private.inversion_solicitud_resultado(p_clave,v_ctx);
end;
$$;
revoke all on function crm.preparar_inversion_fn(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function crm.preparar_inversion_fn(uuid,jsonb) to authenticated;

create or replace function private.f4_comprobante_autorizado(p_ruta text)
returns boolean language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_persona uuid; v_solicitud uuid; v_ctx jsonb; v_s crm.inversion_solicitudes%rowtype;
begin
  if p_ruta is null or p_ruta !~ '^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$' then return false; end if;
  begin v_persona:=split_part(p_ruta,'/',1)::uuid; v_solicitud:=split_part(p_ruta,'/',2)::uuid;
  exception when invalid_text_representation then return false; end;
  v_ctx:=private.inversion_persona_contexto(v_persona);
  select * into v_s from crm.inversion_solicitudes where id=v_solicitud for share;
  return found and v_s.inversionista_id=v_persona and v_s.estado='preparada'
    and v_s.responsable_esperado_id=(v_ctx->>'responsable_id')::uuid
    and v_s.datos#>>'{evidencia,ruta}'=p_ruta;
exception when insufficient_privilege then return false;
end;
$$;
revoke all on function private.f4_comprobante_autorizado(text) from public,anon,authenticated,service_role;
grant execute on function private.f4_comprobante_autorizado(text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf','image/jpeg','image/png']);
create policy f4_comprobante_insert on storage.objects for insert to authenticated
  with check(bucket_id='f4-comprobantes' and private.f4_comprobante_autorizado(name));
-- No UPDATE ni DELETE: el comprobante confirmado conserva sus bytes y su referencia.

create or replace function private.f4_fuente_inmutable()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name in ('inversion_ajustes_mes_cerrado','inversion_eventos','inversion_solicitud_revisiones','inversion_solicitud_correcciones') then
    raise exception 'El historial de una inversión no se modifica ni se elimina' using errcode='P0409';
  end if;
  if new.es_cierre_inicial is distinct from old.es_cierre_inicial
     or new.fecha_comercial is distinct from old.fecha_comercial
     or new.fecha_imputacion is distinct from old.fecha_imputacion
     or new.comprobante_objeto_id is distinct from old.comprobante_objeto_id then
    raise exception 'La clase, las fechas y el comprobante del cierre conservan su registro original' using errcode='P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.f4_fuente_inmutable() from public,anon,authenticated,service_role;
create trigger trg_cierres_f4_inmutables before update on crm.cierres_externos
  for each row execute function private.f4_fuente_inmutable();
create trigger trg_inversion_ajustes_inmutables before update or delete on crm.inversion_ajustes_mes_cerrado
  for each row execute function private.f4_fuente_inmutable();
create trigger trg_inversion_eventos_inmutables before update or delete on crm.inversion_eventos
  for each row execute function private.f4_fuente_inmutable();
create trigger trg_inversion_revisiones_inmutables before update or delete on crm.inversion_solicitud_revisiones
  for each row execute function private.f4_fuente_inmutable();
