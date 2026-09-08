-- F4 multiempresa: SQL candidato. Construcción y pruebas aisladas; G4 aún no aprobado.
-- Fuentes: código vivo con huellas; módulos scripts/f4. No enciende ninguna bandera.
begin;
set local lock_timeout='5s';
set local check_function_bodies=true;
select pg_advisory_xact_lock(hashtext('crm_f4_multiempresa'));
do $guard$
begin
  if to_regclass('crm.inversion_solicitudes') is not null then raise exception 'F4 ya está instalada'; end if;
  if md5(pg_get_functiondef('crm.altas_nuevas_por_analista_fn(integer)'::regprocedure)) is distinct from '2cd38241a1331e1ac335658fc7f653f5' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.altas_nuevas_por_analista_fn(integer)';
  end if;
  if md5(pg_get_functiondef('crm.anular_cierre_avance(uuid, text)'::regprocedure)) is distinct from '9322f86beba6b40bb4a9c07186f0028f' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.anular_cierre_avance(uuid, text)';
  end if;
  if md5(pg_get_functiondef('crm.anular_cierre_externo(uuid, text)'::regprocedure)) is distinct from 'f77ef584632cc37afc06ab3864d41805' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.anular_cierre_externo(uuid, text)';
  end if;
  if md5(pg_get_functiondef('crm.cierres_estado_fn(uuid[])'::regprocedure)) is distinct from '1411c7395cf5579359d93565c42ce638' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.cierres_estado_fn(uuid[])';
  end if;
  if md5(pg_get_functiondef('crm.cierres_externos_fn(date)'::regprocedure)) is distinct from '337700989baed6b15f72349c021bb387' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.cierres_externos_fn(date)';
  end if;
  if md5(pg_get_functiondef('crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text)'::regprocedure)) is distinct from 'aeaead8aad9817e9790f6fc97448d25e' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text)';
  end if;
  if md5(pg_get_functiondef('crm.corregir_cierre_externo(uuid, numeric, text, text, text, text, date, text)'::regprocedure)) is distinct from '73cccb38b57506b065b0eb903838b4a0' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.corregir_cierre_externo(uuid, numeric, text, text, text, text, date, text)';
  end if;
  if md5(pg_get_functiondef('crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb)'::regprocedure)) is distinct from '79d9d316203ce217456a7d00f834c584' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb)';
  end if;
  if md5(pg_get_functiondef('crm.crear_contrato_con_cuenta_pdf_v2(jsonb, jsonb, jsonb)'::regprocedure)) is distinct from '9833ed526e733dc8af6ca78e5c85c7ca' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.crear_contrato_con_cuenta_pdf_v2(jsonb, jsonb, jsonb)';
  end if;
  if md5(pg_get_functiondef('crm.enlazar_lead_inversionista_fn(uuid, uuid, text)'::regprocedure)) is distinct from '50e64327a047171e2c4d37af7afdb9d5' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.enlazar_lead_inversionista_fn(uuid, uuid, text)';
  end if;
  if md5(pg_get_functiondef('private.capital_episodios(timestamp with time zone, timestamp with time zone, boolean, uuid[])'::regprocedure)) is distinct from 'b8f375fbb377582835f4cfe222240c5b' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','private.capital_episodios(timestamp with time zone, timestamp with time zone, boolean, uuid[])';
  end if;
  if md5(pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) is distinct from '3149031d7e90e13cacbb4b56480afbf1' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','private.cierre_anulado(uuid)';
  end if;
  if md5(pg_get_functiondef('private.leads_before_update()'::regprocedure)) is distinct from '213e284d9c50fde7f8cd136b4ecaa5d2' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','private.leads_before_update()';
  end if;
  if md5(pg_get_functiondef('private.metricas_conversiones_implementacion(date, date, text)'::regprocedure)) is distinct from 'be4e1c283a1f3042828cbb8c66332252' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','private.metricas_conversiones_implementacion(date, date, text)';
  end if;
  if md5(pg_get_functiondef('public.crear_contrato(jsonb, jsonb)'::regprocedure)) is distinct from '1cd2730dc75c966cfbd9ea8d95d4d1ed' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','public.crear_contrato(jsonb, jsonb)';
  end if;
  if md5(pg_get_functiondef('crm.contrato_eliminacion_preparar(uuid, uuid)'::regprocedure)) is distinct from '1b0617656c06eddade935d4c15b5bfd4' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','crm.contrato_eliminacion_preparar(uuid, uuid)';
  end if;
  if md5(pg_get_functiondef('public.proteger_campos_inmutables()'::regprocedure)) is distinct from '5e64e3fc95b367d262b4d7b39c687cde' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','public.proteger_campos_inmutables()';
  end if;
  if md5(pg_get_functiondef('private.backfill_multiempresa_ejecutar()'::regprocedure)) is distinct from '930acfc792eb4db91df599f26e283f12' then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar','private.backfill_multiempresa_ejecutar()';
  end if;

  -- Inventario mecánico completo ANTES del cambio de cardinalidad. Incluye
  -- consumidores sin adaptación y referencias en comentarios (conservador).
  if (select jsonb_agg(jsonb_build_object('firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
       'md5',md5(pg_get_functiondef(p.oid))) order by n.nspname,p.proname,oidvectortypes(p.proargtypes))
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('crm','private','public') and p.prokind='f' and p.prosrc ilike '%cierres_externos%')
      is distinct from '[{"md5":"2cd38241a1331e1ac335658fc7f653f5","firma":"crm.altas_nuevas_por_analista_fn(integer)"},{"md5":"9322f86beba6b40bb4a9c07186f0028f","firma":"crm.anular_cierre_avance(uuid, text)"},{"md5":"f77ef584632cc37afc06ab3864d41805","firma":"crm.anular_cierre_externo(uuid, text)"},{"md5":"1411c7395cf5579359d93565c42ce638","firma":"crm.cierres_estado_fn(uuid[])"},{"md5":"337700989baed6b15f72349c021bb387","firma":"crm.cierres_externos_fn(date)"},{"md5":"aeaead8aad9817e9790f6fc97448d25e","firma":"crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text)"},{"md5":"73cccb38b57506b065b0eb903838b4a0","firma":"crm.corregir_cierre_externo(uuid, numeric, text, text, text, text, date, text)"},{"md5":"49d73e13f8969161060e2ce2b669a85a","firma":"crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid)"},{"md5":"50e64327a047171e2c4d37af7afdb9d5","firma":"crm.enlazar_lead_inversionista_fn(uuid, uuid, text)"},{"md5":"814368bf22e2b9f2383bcce878a66fea","firma":"crm.fusion_previsualizar_fn(uuid, uuid)"},{"md5":"6919e7ce8960f7d985ac03ba033c347e","firma":"crm.fusionar_inversionistas_fn(uuid, uuid, text, text)"},{"md5":"930acfc792eb4db91df599f26e283f12","firma":"private.backfill_multiempresa_ejecutar()"},{"md5":"b8f375fbb377582835f4cfe222240c5b","firma":"private.capital_episodios(timestamp with time zone, timestamp with time zone, boolean, uuid[])"},{"md5":"3149031d7e90e13cacbb4b56480afbf1","firma":"private.cierre_anulado(uuid)"},{"md5":"9cc2996ce00e7b0ef73597b4a5800ee6","firma":"private.fusion_estado_jsonb(uuid, uuid)"},{"md5":"8f48cae159dee0ea157ba45e2a833e04","firma":"private.fusion_impacto(uuid, uuid)"},{"md5":"4873bebdf14f507e7f9200aa5b676b7f","firma":"private.inversiones_empresa_coherente()"},{"md5":"95d502fcae257bf2a439ec3e4aa6a2dc","firma":"private.inversionista_resolver(text, text, boolean, text)"},{"md5":"213e284d9c50fde7f8cd136b4ecaa5d2","firma":"private.leads_before_update()"},{"md5":"be4e1c283a1f3042828cbb8c66332252","firma":"private.metricas_conversiones_implementacion(date, date, text)"}]'::jsonb then
    raise exception 'F4: cambió el inventario de consumidores; recapturar y clasificar antes de aplicar';
  end if;
  if exists(select 1 from pg_views where schemaname in ('crm','private','public') and definition ilike '%cierres_externos%')
     or exists(select 1 from pg_policies where schemaname in ('crm','private','public') and
       (tablename='cierres_externos' or qual ilike '%cierres_externos%' or with_check ilike '%cierres_externos%')) then
    raise exception 'F4: hay una vista o política consumidora sin clasificar';
  end if;
end;
$guard$;
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

create or replace function private.inversion_vincular_fuente(
  p_persona uuid,p_contrato uuid,p_cierre uuid,p_por uuid,p_inicial boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_empresa uuid;
  v_fecha date;
  v_estado text;
  v_identidad uuid;
  v_i crm.inversiones%rowtype;
begin
  if ((p_contrato is not null)::integer+(p_cierre is not null)::integer)<>1 then
    raise exception 'La inversión requiere exactamente una fuente económica' using errcode='22023';
  end if;
  if p_cierre is not null then
    select e.id,coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
      case when ce.anulado_en is null then 'vigente' else 'anulada' end,
      private.inversionista_canonica(ce.inversionista_id)
    into v_empresa,v_fecha,v_estado,v_identidad
    from crm.cierres_externos ce join crm.empresas e on e.clave=ce.cooperativa
    where ce.id=p_cierre for share of ce;
  else
    select e.id,c.fecha_cierre_comercial,'vigente',private.inversionista_canonica(p.id)
    into v_empresa,v_fecha,v_estado,v_identidad
    from public.contratos c join crm.inversionistas p on p.perfil_id=c.cliente_id and p.estado<>'fusionado'
    cross join crm.empresas e where c.id=p_contrato and e.clave='avance' for share of c;
  end if;
  if v_empresa is null or v_identidad is distinct from p_persona then
    raise exception 'La fuente económica no corresponde a esta persona' using errcode='P0409';
  end if;
  -- También protege una vinculación histórica: si el borrado se preparó antes
  -- de obtener el candado contractual, no añadir una relación a esa fuente.
  if p_contrato is not null and private.contrato_en_eliminacion(p_contrato) then
    raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
  end if;
  select * into v_i from crm.inversiones
  where contrato_id=p_contrato or cierre_externo_id=p_cierre for update;
  if found then
    if v_i.inversionista_id<>p_persona or v_i.empresa_id<>v_empresa then
      raise exception 'La fuente ya está vinculada a otra persona o empresa' using errcode='P0409';
    end if;
  else
    insert into crm.inversiones(inversionista_id,empresa_id,contrato_id,cierre_externo_id,
      estado,fecha_comercial,es_primera_conversion,creado_por)
    values(p_persona,v_empresa,p_contrato,p_cierre,v_estado,v_fecha,p_inicial,p_por)
    returning * into v_i;
  end if;
  if exists (select 1 from crm.inversion_titulares it
             where it.inversion_id=v_i.id and it.rol='principal' and it.inversionista_id<>p_persona) then
    raise exception 'El titular principal requiere conciliación' using errcode='P0409';
  end if;
  insert into crm.inversion_titulares(inversion_id,inversionista_id,rol,creado_por)
  select v_i.id,p_persona,'principal',p_por where not exists (
    select 1 from crm.inversion_titulares it where it.inversion_id=v_i.id and it.rol='principal');
  return v_i.id;
end;
$$;
revoke all on function private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)
  from public,anon,authenticated,service_role;

create or replace function crm.confirmar_inversion_revisada_fn(p_solicitud uuid,p_revision_datos_esperada integer)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_uid uuid := (select auth.uid());
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_e crm.empresas%rowtype;
  v_obj storage.objects%rowtype;
  v_cierre uuid;
  v_contrato uuid;
  v_inversion uuid;
  v_fecha date;
  v_imputacion date;
  v_periodo date;
  v_ahora timestamptz := statement_timestamp();
  v_ajuste boolean := false;
  v_fuente jsonb;
  v_payload_contrato jsonb;
  v_condicion uuid;
  v_config_producto text := current_setting('crm.producto_condicion_id',true);
  v_responsable_inicial uuid;
  v_res jsonb;
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_origen := v_persona;
  v_ctx := private.inversion_persona_autorizada(v_persona);
  v_persona := (v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado='confirmada' then
    v_res:=v_s.resultado;
    select contrato_id into v_contrato from crm.inversiones where id=v_s.inversion_id;
    if v_contrato is not null then
      if private.contrato_en_eliminacion(v_contrato) then
        raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
      end if;
      v_res:=jsonb_set(v_res,'{fuente,pdf}',private.contrato_pdf_estado_base(v_contrato));
    end if;
    return v_res||jsonb_build_object('inversionista_id',v_persona,'reintento',true);
  end if;
  if v_s.estado<>'preparada' then raise exception 'La solicitud está cancelada' using errcode='P0409'; end if;
  if p_revision_datos_esperada is distinct from v_s.revision_datos then
    raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='40001';
  end if;
  v_ctx := private.inversion_persona_contexto(v_persona);
  if v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
  end if;
  select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
  if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
  if v_e.fuente_capital='cierres_externos' then
    if v_s.datos->>'moneda' is distinct from 'PEN' or not ('PEN'=any(v_e.monedas)) then
      raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
    end if;
    select * into v_obj from storage.objects
    where bucket_id='f4-comprobantes' and name=v_s.datos#>>'{evidencia,ruta}' for key share;
    if not found or coalesce((v_obj.metadata->>'size')::bigint,0) not between 1 and 10485760
       or coalesce(v_obj.metadata->>'mimetype','') not in ('application/pdf','image/jpeg','image/png') then
      raise exception 'Sube el comprobante válido antes de confirmar la inversión' using errcode='P0409';
    end if;
    v_fecha := (v_s.datos->>'fecha_comercial')::date;
    v_periodo := date_trunc('month',v_fecha)::date;
    -- Mismo candado que el sello mensual. El sello no puede aparecer entre la
    -- decisión y el alta. Un mes sellado recibe un hecho posterior trazable.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    v_ajuste := exists(select 1 from crm.periodos_cerrados where periodo=v_periodo);
    v_imputacion := case when v_ajuste then (v_ahora at time zone 'America/Lima')::date else v_fecha end;
    if v_ajuste then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
        (date_trunc('month',v_imputacion)::date-date '2000-01-01')::integer);
      if exists(select 1 from crm.periodos_cerrados where periodo=date_trunc('month',v_imputacion)::date) then
        raise exception 'El período de registro también está sellado; corresponde revisión de Gerencia' using errcode='P0409';
      end if;
    end if;
    begin
      insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
        nombre_completo,numero_transaccion,referencia_externa,vence_en,vendedor_id,creado_por,
        inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id)
      values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,'PEN',
        v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
        upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
        (v_s.datos->>'vence_en')::date,(v_ctx->>'responsable_id')::uuid,v_uid,v_persona,
        v_ahora,false,v_fecha,v_imputacion,v_obj.id) returning id into v_cierre;
      -- La reclamación histórica del depósito es global para ambas cooperativas.
      insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
      values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
    exception when unique_violation then
      raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
    end;
    v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
      'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste);
  elsif v_e.clave='avance' then
    if v_ctx->>'perfil_id' is null then
      raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
    end if;
    v_payload_contrato := v_s.datos->'contrato';
    select r.responsable_anterior_id into v_responsable_inicial
      from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
    v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
    if v_payload_contrato->>'cliente_id' is not null
       and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
    end if;
    if v_payload_contrato->>'analista_cierre_id' is not null
       and v_payload_contrato->>'analista_cierre_id' is distinct from v_responsable_inicial::text then
      raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
    end if;
    -- El contenido original conserva su huella. Una revisión explícita cambia
    -- el responsable con quien se confirma, sin reescribir las condiciones.
    v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
      'analista_cierre_id',v_ctx->>'responsable_id');
    -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
    -- documental y operaciones de cartera. Todo participa de esta transacción.
    -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
    -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
    -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
    -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
    perform pg_catalog.set_config('crm.producto_condicion_id',
      coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
    begin
      v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
        v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
        v_s.datos->'cronograma',v_s.datos->'cuenta');
    exception when others then
      perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
      raise;
    end;
    perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
    v_contrato := (v_fuente->>'id')::uuid;
    if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
    select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
    v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
  else
    raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
  end if;
  v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,false);
  if v_ajuste then
    insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
    values(v_inversion,v_periodo,v_imputacion,v_uid);
  end if;
  insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
  v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
    'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
    'revision_datos',v_s.revision_datos);
  update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
    resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
  return v_res;
end;
$$;
revoke all on function crm.confirmar_inversion_revisada_fn(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function crm.confirmar_inversion_revisada_fn(uuid,integer) to authenticated;

-- Compatibilidad: una pantalla antigua sólo confirma solicitudes sin corrección.
-- Una confirmada conserva su replay de lectura con cualquier revisión enviada.
create or replace function crm.confirmar_inversion_fn(p_solicitud uuid)
returns jsonb language sql security definer set search_path='' as $$
  select crm.confirmar_inversion_revisada_fn(p_solicitud,0);
$$;
revoke all on function crm.confirmar_inversion_fn(uuid) from public,anon,authenticated,service_role;
grant execute on function crm.confirmar_inversion_fn(uuid) to authenticated;


create or replace function private.f4_comprobante_visible(p_ruta text)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia') and exists (
    select 1 from crm.inversion_solicitudes s join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    where s.datos#>>'{evidencia,ruta}'=p_ruta and (
      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
    )
  ),false);
$$;
revoke all on function private.f4_comprobante_visible(text) from public,anon,authenticated,service_role;
grant execute on function private.f4_comprobante_visible(text) to authenticated;
create policy f4_comprobante_select on storage.objects for select to authenticated
  using(bucket_id='f4-comprobantes' and private.f4_comprobante_visible(name));
-- Las políticas RESTRICTIVE impiden que una política permisiva legacy de otro
-- bucket abra accidentalmente comprobantes F4 o permita sustituir sus bytes.
create policy f4_comprobante_insert_frontera on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'f4-comprobantes' or private.f4_comprobante_autorizado(name));
create policy f4_comprobante_select_frontera on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'f4-comprobantes' or private.f4_comprobante_visible(name));
create policy f4_comprobante_update_frontera on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'f4-comprobantes') with check(bucket_id<>'f4-comprobantes');
create policy f4_comprobante_delete_frontera on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'f4-comprobantes');

-- Adaptación acotada de private.backfill_multiempresa_ejecutar(); antes 930acfc792eb4db91df599f26e283f12
CREATE OR REPLACE FUNCTION private.backfill_multiempresa_ejecutar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record; v_inv uuid; v_valido boolean;
  v_old_priv text := pg_catalog.current_setting('crm.op_privilegiada', true);
  v_demo_cierre constant uuid := 'a112aead-184a-4979-9041-943978fadae4';
  v_a int:=0; v_b int:=0; v_c int:=0; v_e int:=0; v_resp int:=0; v_noc int:=0;
begin
  if to_regclass('crm.inversion_solicitudes') is not null then
    raise exception 'F2 global ya fue sustituida por el censo y los lotes históricos F4'
      using errcode='55000';
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada','on', true);

  -- ── Clase A / E: perfiles cliente ──
  for r in
    select p.id, p.tipo_documento as tipo, p.asesor_perfil_id,
           pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni,''),'[^A-Za-z0-9]','','g')) as dnorm
    from public.perfiles p where p.rol='cliente'
    order by p.id
  loop
    if r.dnorm = '' then
      perform private.f2_mapear('perfil', r.id, null, 'E', 'cliente sin documento', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_valido := coalesce(case r.tipo
      when 'DNI' then r.dnorm ~ '^[0-9]{8}$'
      when 'CE' then r.dnorm ~ '^[0-9]{9,12}$'
      when 'PASAPORTE' then r.dnorm ~ '^[A-Z0-9]{6,12}$' else false end, false);
    if not v_valido then
      perform private.f2_mapear('perfil', r.id, null, 'E', 'documento con formato invalido para '||r.tipo, 'revision');
      v_e := v_e+1; continue;
    end if;
    if exists (
      select 1 from public.perfiles p2
      where p2.id <> r.id
        and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p2.dni,''),'[^A-Za-z0-9]','','g')) = r.dnorm
    ) then
      perform private.f2_mapear('perfil', r.id, null, 'E', 'documento compartido con otro perfil (multirrol/colision)', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_inv := private.inversionista_resolver(r.tipo, r.dnorm, true, 'backfill-A');
    update crm.inversionistas set perfil_id = r.id
      where id = v_inv and perfil_id is null
        and not exists (select 1 from crm.inversionistas i2 where i2.perfil_id = r.id and i2.id <> v_inv);
    perform private.f2_mapear('perfil', r.id, v_inv, 'A', 'perfil cliente con documento valido y unico', 'alta');
    v_a := v_a+1;
    if r.asesor_perfil_id is not null
       and exists (select 1 from crm.equipo e where e.perfil_id=r.asesor_perfil_id and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id=v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, r.asesor_perfil_id, 'backfill: asesor del perfil cliente');
      update crm.inversionistas set responsable_relacion_id = r.asesor_perfil_id where id=v_inv and responsable_relacion_id is null;
      v_resp := v_resp+1;
    end if;
  end loop;

  -- ── Clase B / E: cierres coop (EXCLUYE el demo por id) ──
  for r in
    select ce.id, ce.documento_tipo as tipo, ce.cooperativa, ce.vendedor_id, ce.creado_por, ce.creado_en,
           pg_catalog.upper(pg_catalog.regexp_replace(ce.documento,'[^A-Za-z0-9]','','g')) as dnorm
    from crm.cierres_externos ce where ce.id <> v_demo_cierre
    order by ce.creado_en, ce.id
  loop
    v_valido := coalesce(case r.tipo
      when 'DNI' then r.dnorm ~ '^[0-9]{8}$'
      when 'CE' then r.dnorm ~ '^[0-9]{9,12}$'
      when 'PASAPORTE' then r.dnorm ~ '^[A-Z0-9]{6,12}$' else false end, false);
    if not v_valido then
      perform private.f2_mapear('cierre', r.id, null, 'E', 'documento de cierre invalido', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_inv := private.inversionista_resolver(r.tipo, r.dnorm, true, 'backfill-B');
    update crm.cierres_externos set inversionista_id = v_inv where id = r.id and inversionista_id is null;
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)
    select v_inv, e.id, r.id, 'vigente',
           least((r.creado_en at time zone 'America/Lima')::date, (pg_catalog.now() at time zone 'America/Lima')::date),
           true, r.creado_por
    from crm.empresas e
    where e.clave = r.cooperativa
      and not exists (select 1 from crm.inversiones inv where inv.cierre_externo_id = r.id);
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol)
    select inv.id, v_inv, 'principal' from crm.inversiones inv
    where inv.cierre_externo_id = r.id
      and not exists (select 1 from crm.inversion_titulares it where it.inversion_id=inv.id and it.rol='principal');
    perform private.f2_mapear('cierre', r.id, v_inv, 'B', 'cierre coop con documento valido; inversion externa inicial', 'alta');
    v_b := v_b+1;
    if r.vendedor_id is not null
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id=v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, r.vendedor_id, 'backfill: vendedor del cierre coop');
      update crm.inversionistas set responsable_relacion_id = r.vendedor_id where id=v_inv and responsable_relacion_id is null;
      v_resp := v_resp+1;
    end if;
  end loop;

  -- ── Clase C / E: leads convertidos ──
  for r in
    select l.id as lead_id, l.no_contactar,
           pg_catalog.upper(pg_catalog.regexp_replace(coalesce(l.dni,''),'[^A-Za-z0-9]','','g')) as ldni,
           (select i.id from crm.inversionistas i where i.perfil_id = l.perfil_id and i.estado <> 'fusionado' limit 1) as inv_perfil,
           (select ce.inversionista_id from crm.cierres_externos ce where ce.lead_id = l.id) as inv_cierre
    from crm.leads l where l.etapa='convertido'
    order by l.creado_en, l.id
  loop
    if r.inv_perfil is not null and r.inv_cierre is not null and r.inv_perfil <> r.inv_cierre then
      perform private.f2_mapear('lead', r.lead_id, null, 'E', 'convertido con perfil y cierre en identidades distintas', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_inv := coalesce(r.inv_perfil, r.inv_cierre);
    if v_inv is null then
      perform private.f2_mapear('lead', r.lead_id, null, 'E', 'lead convertido sin identidad inequivoca de perfil ni cierre', 'revision');
      v_e := v_e+1; continue;
    end if;
    if r.ldni <> '' and not exists (
      select 1 from crm.inversionista_identificadores d
      where d.inversionista_id = v_inv and d.documento_normalizado = r.ldni and d.estado='vigente'
    ) then
      perform private.f2_mapear('lead', r.lead_id, null, 'E', 'discrepancia documental del lead convertido', 'revision');
      v_e := v_e+1; continue;
    end if;
    if exists (select 1 from crm.leads l2 where l2.inversionista_id = v_inv) then
      insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
      select v_inv, r.lead_id, 'historico'
      where not exists (select 1 from crm.inversionista_leads il where il.lead_id = r.lead_id);
    else
      update crm.leads set inversionista_id = v_inv where id = r.lead_id and inversionista_id is null;
      insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
      select v_inv, r.lead_id, 'canonico'
      where not exists (select 1 from crm.inversionista_leads il where il.lead_id = r.lead_id);
    end if;
    perform private.f2_mapear('lead', r.lead_id, v_inv, 'C', 'lead convertido hereda identidad de perfil/cierre', 'alta');
    v_c := v_c+1;
    if r.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
      v_noc := v_noc+1;
    end if;
  end loop;

  perform pg_catalog.set_config('crm.op_privilegiada', coalesce(v_old_priv, 'off'), true);
  return jsonb_build_object('A',v_a,'B',v_b,'C',v_c,'E',v_e,'responsables',v_resp,'no_contactar',v_noc);
end
$function$;
-- Adaptación acotada de private.capital_episodios(timestamp with time zone, timestamp with time zone, boolean, uuid[]); antes b8f375fbb377582835f4cfe222240c5b
CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$

  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    -- ATR-2: la cadena de upgrade adopta tambien el CAPITAL (contrato 2026-08-30).
    coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id),
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) = any(p_visibles))

  union all

  select
    'cooperativa',
    -- ATR-4 (Miguel 31/08): la sancion de anular es SOLO de conversion. El
    -- capital de una coop anulada EXISTE y se queda: vuelve a 'stock'. UNICA
    -- excepcion DECLARADA: la fila DEMO de Miguel (qorilazo S/100.000, creada
    -- 19/08 y anulada 20/08 con motivo 'DEMO'; vault «Cierre Qorilazo S 100000
    -- es dato demo») — su lead es REAL y el filtro de demos no la caza, asi
    -- que se excluye por id, sellado por la huella de este cuerpo.
    case when ce.anulado_en is null then 'stock'
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 'nula'
         else 'stock' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 0::numeric
         else ce.monto end,
    'nuevo',
    date_trunc('month', coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date,
    coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en),
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= p_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));

$function$;
-- Adaptación acotada de private.cierre_anulado(uuid); antes 3149031d7e90e13cacbb4b56480afbf1
CREATE OR REPLACE FUNCTION private.cierre_anulado(p_lead_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id and ce.es_cierre_inicial
      and ce.anulado_en is not null
  ) or exists (
    select 1
    from crm.cierres_avance_anulados ca
    where ca.lead_id = p_lead_id
  )
$function$;
-- Adaptación acotada de private.leads_before_update(); antes 213e284d9c50fde7f8cd136b4ecaa5d2
CREATE OR REPLACE FUNCTION private.leads_before_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'crm', 'public'
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Columnas inmutables: restaurar siempre desde OLD.
  new.id := old.id;
  new.creado_por := old.creado_por;
  new.alta_manual := old.alta_manual;
  new.creado_en := old.creado_en;
  new.actualizado_en := now();

  -- Conversión y enlace al portal: SOLO desde una RPC privilegiada
  -- (que fija crm.op_privilegiada='on'). Un cliente API no puede convertir
  -- ni enlazar perfil_id/contrato_id a mano.
  if not v_priv then
    if new.etapa = 'convertido' and old.etapa <> 'convertido' then
      raise exception 'La conversión a cliente solo se hace vía la operación de conversión';
    end if;
    new.perfil_id := old.perfil_id;
    new.contrato_id := old.contrato_id;
    new.convertido_en := old.convertido_en;

    -- ── SELLO DEL ORIGEN (migración D, 2026-08-11) ────────────────────────
    -- El origen se elige al ALTA y no se vuelve a mover. Lo que esto protege
    -- NO es un mes ya contado —el snapshot `lead_asignaciones.origen` ya era
    -- inmutable por `trg_lead_asignaciones_00_inmutables`— sino dos cosas del
    -- presente y del futuro:
    --   · el origen que copiará `private.trg_leads_asignaciones` al abrir el
    --     PRÓXIMO episodio de este lead (y ése sí sale del divisor del mes en
    --     curso si dice 'referido');
    --   · el bloque `referidos.dados_de_alta`, único número del payload que
    --     lee esta columna viva, agrupado por el mes de ALTA del lead.
    -- Se avisa con EXCEPCIÓN en vez de restaurar en silencio porque el store
    -- del front es optimista: un 200 mudo dejaría al usuario convencido de
    -- que corrigió.
    -- Va DENTRO de `if not v_priv`, a propósito: encima del gate el dato
    -- quedaría incorregible para siempre y el único remedio sería
    -- `disable trigger` en producción, que CLAUDE.md prohíbe.
    -- `is distinct from` (y no `<>`) hace que un UPDATE de payload completo que
    -- reenvía el MISMO valor no lance nada: es el caso de seed-demo.mjs y de
    -- test-rls.mjs, los dos únicos escritores que mandan `origen` en un UPDATE.
    if new.origen is distinct from old.origen then
      raise exception using
        errcode = 'P0409',
        message = 'El origen de un lead no se cambia despues del alta',
        detail  = pg_catalog.format(
          'lead %s: origen actual %L, intento %L',
          old.id, old.origen, new.origen),
        hint    = 'El origen se elige al crear el lead (crm.crear_lead_si_disponible). '
                  'La conversion mensual lee la FOTO del episodio, que ya es inmutable: '
                  'cambiar la ficha no mueve ningun mes ya contado, pero si moveria el '
                  'origen de los episodios FUTUROS de este lead y el bloque de referidos '
                  'dados de alta de su mes de creacion.';
    end if;
  end if;

  -- ── P4 RELAJADA (migración cierres externos, 2026-08-12) ────────────────
  -- Invariante de negocio en la transición (no como CHECK de tabla). Antes:
  -- «convertido ⇒ perfil_id no nulo». Ahora un convertido puede carecer de
  -- perfil SI Y SOLO SI tiene cierre externo (invirtió en una cooperativa y
  -- el portal no lo conoce). El EXISTS corre solo en la rama rara (convertido
  -- sin perfil) y lo sirve el UNIQUE de lead_id. Nótese que P2 sigue intacta:
  -- sin válvula no hay transición a convertido, con o sin cierre.
  if new.etapa = 'convertido' and new.perfil_id is null
     and not exists (
       select 1 from crm.cierres_externos ce where ce.lead_id = new.id and ce.es_cierre_inicial
     ) then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$function$;
-- Adaptación acotada de crm.cierres_estado_fn(uuid[]); antes 1411c7395cf5579359d93565c42ce638
CREATE OR REPLACE FUNCTION crm.cierres_estado_fn(p_lead_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text;
  v_lector   boolean;
  v_visibles uuid[];
  v_payload  jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();

  -- Guardia de ADMISION, igual que cartera_pagina_fn: quien no es del CRM ni
  -- lector global no pregunta.
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- El gate RESTRICTIVO de `crm.leads` (`crm_actor_activo_gate`) se INVOCA en
  -- vez de copiarse: una llamada no se desincroniza. Sin esto, un actor
  -- revocado —que la RLS expulsa de la tabla— seguiria leyendo por aqui.
  if not coalesce(private.puede_acceder_crm(), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Tope alineado con `cartera_pagina_fn` (p_limite maximo 200): esta funcion
  -- sirve a una pagina en pantalla, no a un volcado.
  if p_lead_ids is not null and array_length(p_lead_ids, 1) > 200 then
    raise exception 'Parametro p_lead_ids invalido: maximo 200'
      using errcode = '22023';
  end if;
  if p_lead_ids is null or array_length(p_lead_ids, 1) is null then
    return '[]'::jsonb;
  end if;

  -- Se resuelve UNA vez (la policy lo evalua como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  select coalesce(jsonb_agg(f.fila order by f.lead_id), '[]'::jsonb)
    into v_payload
  from (
    select
      l.id as lead_id,
      jsonb_build_object(
        'lead_id', l.id,
        -- La foto del cierre manda sobre la etapa: si hay fila en
        -- cierres_externos, ese lead cerro en cooperativa, punto.
        'canal', case when ce.lead_id is not null then 'cooperativa' else 'avance' end,
        -- `coalesce` y no un case: los dos canales son excluyentes por
        -- construccion (crm.anular_cierre_avance rechaza un lead con cierre en
        -- cooperativa), asi que como mucho uno de los dos trae fecha.
        'anulado_en', coalesce(ce.anulado_en, ca.anulado_en),
        -- El motivo viaja: la regla de Miguel es que a quien se le quita el
        -- merito merece una razon escrita, no un numero que baja sin explicacion.
        'motivo', coalesce(ce.motivo_anulacion, ca.motivo)
      ) as fila
    from crm.leads l
    -- Los dos son UNIQUE por lead (`cierres_externos_un_cierre_por_lead` y el
    -- unique de `lead_id` en cierres_avance_anulados), asi que ningun join
    -- duplica la fila del lead.
    left join crm.cierres_externos ce on ce.lead_id = l.id and ce.es_cierre_inicial
    left join crm.cierres_avance_anulados ca on ca.lead_id = l.id
    where l.id = any(p_lead_ids)
      -- ── ESPEJO EXACTO de la policy `leads_select` (20260902040000) ─────────
      --   using: activo = true
      --          and ( vendedor_id in (vendedor_ids_visibles(uid))
      --                or (vendedor_id is null and asignado_supervisor_id in (...))
      --                or rol_crm(uid) = 'gerencia'
      --                or es_lector_global() )
      -- 🔴 El `or v_lector` va DENTRO del `activo`, igual que en la policy: el
      -- lector global ve todo lo VIVO y NADA de lo borrado. Hasta el 01/09 iba
      -- fuera —aqui y en la policy— y por eso el Directorio leia el estado de
      -- cierre de leads dados de baja.
      and l.activo = true
      and (
        l.vendedor_id = any(v_visibles)
        -- Lead en la bandeja de un supervisor: sin vendedor todavia.
        -- (`NULL = any(...)` da NULL, no TRUE, asi que la rama de arriba
        -- no se lo lleva por delante.)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
      -- Solo los leads con algo que decir. Un convertido de Avance sano no
      -- viaja: es el caso por defecto del front.
      and (ce.lead_id is not null or ca.lead_id is not null)
  ) f;

  return v_payload;
end;
$function$;
-- Adaptación acotada de crm.anular_cierre_avance(uuid, text); antes 9322f86beba6b40bb4a9c07186f0028f
CREATE OR REPLACE FUNCTION crm.anular_cierre_avance(p_lead_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_lead   crm.leads%rowtype;
  v_motivo text := btrim(p_motivo);
  v_contratos uuid[];
  v_ajuste uuid;
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia anula cierres'
      using errcode = '42501';
  end if;

  -- El motivo es obligatorio a proposito: esto le quita merito a una persona y
  -- esa persona merece una razon escrita, no un registro de auditoria mudo.
  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la anulacion'
      using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres'
      using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
  for update;
  if not found then
    raise exception 'Lead no encontrado';
  end if;

  if exists (select 1 from crm.cierres_externos ce where ce.lead_id = p_lead_id and ce.es_cierre_inicial) then
    raise exception 'Ese lead cerro en cooperativa: usa crm.anular_cierre_externo'
      using errcode = '22023';
  end if;

  if v_lead.etapa is distinct from 'convertido' then
    raise exception 'Ese lead no tiene ningun cierre que anular'
      using errcode = '22023';
  end if;

  if v_lead.convertido_en is null then
    raise exception 'Ese lead esta convertido pero sin fecha de conversion: no se puede saber que contratos trajo'
      using errcode = '22023';
  end if;

  if exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre ya estaba anulado';
  end if;

  -- Los contratos afectados se calculan ANTES de insertar la anulacion: despues,
  -- `contratos_afectados_por_anulacion` ya leeria la foto recien creada y daria
  -- lo mismo, pero el orden explicito evita depender de ese detalle.
  select coalesce(array_agg(x), '{}'::uuid[]) into v_contratos
  from private.contratos_afectados_por_anulacion(p_lead_id) x;

  insert into crm.cierres_avance_anulados (lead_id, motivo, anulado_por, acreditado_a)
  values (p_lead_id, v_motivo, v_uid,
          private.vendedor_acreditado_del_cierre(p_lead_id));

  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo hasta saldarla.
  v_ajuste := private.registrar_ajuste_si_mes_cerrado(p_lead_id, v_motivo, v_uid);

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'nota',
    'Gerencia anulo el cierre',
    jsonb_build_object(
      'accion', 'anulacion_cierre_avance',
      'motivo', v_motivo,
      'mes_cerrado', v_ajuste is not null,
      'anulado', jsonb_build_object(
        'vendedor_id', v_lead.vendedor_id,
        'contrato_id', v_lead.contrato_id)
    ),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'contratos_afectados', to_jsonb(v_contratos),
    'afecta_cuota', array_length(v_contratos, 1) is not null,
    -- CLAVES NUEVAS. `mes_cerrado` le dice a gerencia que ese mes ya se pago y
    -- que por eso el descuento va al mes vivo en vez de moverle el pasado.
    'mes_cerrado', v_ajuste is not null,
    'ajuste_id', v_ajuste);
end;
$function$;
-- Adaptación acotada de crm.enlazar_lead_inversionista_fn(uuid, uuid, text); antes 50e64327a047171e2c4d37af7afdb9d5
CREATE OR REPLACE FUNCTION crm.enlazar_lead_inversionista_fn(p_lead_id uuid, p_inversionista uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_lead0 crm.leads%rowtype; v_lead crm.leads%rowtype; v_cierre crm.cierres_externos%rowtype;
  v_perfil_inv uuid; v_perfil_dni text; v_perfil_tipo text; v_ahora timestamptz; v_veto boolean; v_n_tareas integer := 0;
  v_perfil_completado boolean := false; v_cierre_completado boolean := false; v_op_id uuid;
begin
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: enlaza a su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  select * into v_lead0 from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'El lead no existe' using errcode = 'P0002';
  end if;
  if v_lead0.inversionista_id is not null then
    raise exception 'El lead ya está enlazado a una persona' using errcode = 'P0409';
  end if;
  if v_lead0.dni is null then
    raise exception 'El lead no tiene DNI: solo el documento exacto enlaza (corrige el DNI del lead primero)' using errcode = 'P0409';
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_lead0.dni] || coalesce((select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista), '{}'));

  -- jerarquía + Gerencia revalidada -> documento del lead -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona (membresía revalidada)' using errcode = '42501';
  end if;
  perform private.identidad_bloquear_documento('DNI', v_lead0.dni);
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if not private.documento_es_de_identidad(p_inversionista, 'DNI', v_lead0.dni) then
    if private.inversionista_por_documento('DNI', v_lead0.dni) is not null then
      raise exception 'El DNI del lead pertenece a otra persona reconocida: fusiona o corrige primero' using errcode = 'P0409';
    end if;
    raise exception 'El DNI del lead no es un documento vigente y verificado de esta persona: corrige el documento primero' using errcode = 'P0409';
  end if;
  if exists (select 1 from private.leads_de_identidades(array[p_inversionista]) x where x <> p_lead_id) then
    raise exception 'La persona ya tiene su lead (enlace vivo o puente, activo o no): reconciliación de clase E hasta F5' using errcode = 'P0409';
  end if;
  -- unión de enlaces del lead [E3-10]: perfil (FOR SHARE, por DOCUMENTO) -> cierre (por DOCUMENTO) -> puente -> tareas -> lead -> reservas -> claim
  if v_lead0.perfil_id is not null then
    select p.dni, p.tipo_documento into v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_lead0.perfil_id for share;
    select i.id into v_perfil_inv from crm.inversionistas i where i.perfil_id = v_lead0.perfil_id and i.estado <> 'fusionado' limit 1;
    if v_perfil_inv is not null and v_perfil_inv <> p_inversionista then
      raise exception 'El perfil de cliente del lead pertenece a otra persona reconocida: reconciliación (fusión/corrección)' using errcode = 'P0409';
    end if;
    if v_perfil_inv is null then
      if v_inv.perfil_id is not null and v_inv.perfil_id <> v_lead0.perfil_id then
        raise exception 'La persona ya tiene otro perfil de cliente: reconciliación de clase E hasta F5 (dos perfiles)' using errcode = 'P0409';
      end if;
      if not private.documento_es_de_identidad(p_inversionista, v_perfil_tipo, v_perfil_dni) then
        raise exception 'El documento del perfil de cliente del lead no es de esta persona: corrige el documento primero' using errcode = 'P0409';
      end if;
    end if;
  end if;
  select * into v_cierre from crm.cierres_externos ce where ce.lead_id = p_lead_id and ce.es_cierre_inicial for update;
  if v_cierre.id is not null then
    if v_cierre.inversionista_id is not null and v_cierre.inversionista_id <> p_inversionista then
      raise exception 'El cierre del lead pertenece a otra persona reconocida: reconciliación' using errcode = 'P0409';
    end if;
    if v_cierre.inversionista_id is null and not private.documento_es_de_identidad(p_inversionista, v_cierre.documento_tipo, v_cierre.documento) then
      raise exception 'El documento del cierre del lead no es de esta persona: reconciliación documental primero' using errcode = 'P0409';
    end if;
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id and il.inversionista_id <> p_inversionista) then
    raise exception 'El puente del lead apunta a otra persona: reconciliación' using errcode = 'P0409';
  end if;
  perform 1 from crm.tareas t where t.estado = 'pendiente' and t.lead_id = p_lead_id order by t.id for update;
  perform private.bloquear_leads_nowait(array[p_lead_id]);
  select * into v_lead from crm.leads where id = p_lead_id;
  if v_lead.inversionista_id is not null or v_lead.perfil_id is distinct from v_lead0.perfil_id or v_lead.dni is distinct from v_lead0.dni then
    raise exception 'El lead cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
              and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))
              and (r.inversionista_id is null or r.inversionista_id <> p_inversionista)) then
    raise exception 'El lead tiene una reserva de conversión viva o sellada (de otra persona o sin persona): termina o deja caducar' using errcode = 'P0409';
  end if;
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de enlazar' using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  v_veto := v_inv.no_contactar or v_lead.no_contactar;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inversionista where id = p_lead_id;   -- el trigger zz escribe el puente canónico si no existe
  if v_lead0.perfil_id is not null and v_inv.perfil_id is null then
    update crm.inversionistas set perfil_id = v_lead0.perfil_id where id = p_inversionista;
    v_perfil_completado := true;
  end if;
  if v_cierre.id is not null and v_cierre.inversionista_id is null then
    update crm.cierres_externos set inversionista_id = p_inversionista where id = v_cierre.id;
    v_cierre_completado := true;
  end if;
  if v_veto and not v_inv.no_contactar then
    update crm.inversionistas set no_contactar = true, no_contactar_en = v_ahora, no_contactar_por = v_uid where id = p_inversionista;
  end if;
  if v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(p_lead_id);
    update crm.leads set no_contactar = true where id = p_lead_id;
  end if;
  insert into crm.inversionista_operaciones (tipo, inversionista_id, lead_id, motivo, detalle, por)
  values ('enlace', p_inversionista, p_lead_id, p_motivo,
          pg_catalog.jsonb_build_object('perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado,
                                        'veto', v_veto, 'tareas_canceladas', v_n_tareas, 'lead_activo', v_lead.activo), v_uid)
  returning id into v_op_id;
  if v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (p_lead_id, 'nota', 'Lead enlazado a una persona reconocida (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'enlace_identidad', 'operacion_id', v_op_id, 'inversionista_id', p_inversionista, 'veto', v_veto),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', p_inversionista, 'operacion_id', v_op_id,
    'perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado, 'veto', v_veto, 'tareas_canceladas', v_n_tareas);
end;
$function$;
-- Adaptación acotada de crm.altas_nuevas_por_analista_fn(integer); antes 2cd38241a1331e1ac335658fc7f653f5
CREATE OR REPLACE FUNCTION crm.altas_nuevas_por_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with gate as (
    -- fail-closed: sin rol CRM ni lector global, el reporte sale VACIO.
    select coalesce(
      (select auth.uid()) is not null
      and (
        private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia')
        or private.es_lector_global()
      ), false) as ok
  ),
  ambito as (
    select
      (coalesce(private.es_lector_global(), false)
       or private.rol_crm((select auth.uid())) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid()))) as ids
  ),
  anulados as (
    -- Contratos cuyo cierre fue anulado, por el mapeo CANONICO (no reinventado).
    -- Rama 2 (cierres_externos = cooperativa): las coop NO viven en public.contratos,
    -- asi que el mapeo devuelve contratos Avance solo si el MISMO lead ligo un 'nuevo'
    -- Avance al mismo acreditado; hoy 0 impacto (unica coop anulada -> 0 'nuevo').
    select x as contrato_id
    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
    union
    select x
    from crm.cierres_externos ce
    cross join lateral private.contratos_afectados_por_anulacion(ce.lead_id) x
    where ce.anulado_en is not null and ce.es_cierre_inicial
  ),
  base as (
    -- 🔴 fecha_cierre_comercial ES `date` (el dia comercial de Lima). NUNCA
    --    `at time zone` sobre un date: en un servidor UTC el dia 1 se cae al mes
    --    anterior (footgun del proyecto). Se bucketea y se acota en espacio de FECHA,
    --    igual que private.capital_episodios.
    select
      (date_trunc('month', c.fecha_cierre_comercial))::date as mes,
      coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as analista_id
    from public.contratos c
    where c.categoria = 'nuevo'
      and not c.es_demo
      and c.fecha_cierre_comercial is not null
      and not exists (select 1 from anulados an where an.contrato_id = c.id)
      and c.fecha_cierre_comercial >=
        (date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date
  )
  select
    b.mes,
    b.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    count(*)::bigint as altas
  from gate g
  cross join ambito a
  join base b on g.ok
  left join public.perfiles pf on pf.id = b.analista_id
  where a.es_global or b.analista_id = any(a.ids)
  group by b.mes, b.analista_id, coalesce(pf.nombre_completo, 'Sin analista')
  order by b.mes desc, altas desc;
$function$;
-- Adaptación acotada de crm.contrato_eliminacion_preparar(uuid, uuid); antes 1b0617656c06eddade935d4c15b5bfd4
CREATE OR REPLACE FUNCTION crm.contrato_eliminacion_preparar(p_contrato_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_poder jsonb;
  v_eliminacion private.contrato_eliminaciones%rowtype;
  v_objetos jsonb;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  v_poder := private.poder_eliminar_contrato_como(
    p_contrato_id, p_actor_id
  );
  if not coalesce((v_poder->>'admin')::boolean, false) then
    raise insufficient_privilege using
      message = 'Solo Admin o Superadmin puede eliminar contratos';
  end if;
  if coalesce((v_poder->>'tiene_pagos')::boolean, false)
     and not coalesce((v_poder->>'superadmin')::boolean, false) then
    raise insufficient_privilege using
      message = 'Este contrato tiene pagos; solo Superadmin puede eliminarlo';
  end if;

  -- La fila contractual ya está bloqueada y el actor ya fue autorizado.
  -- Rechazar ANTES de reservar el borrado o entregar rutas al borrador Storage.
  if exists(select 1 from crm.inversiones i where i.contrato_id=p_contrato_id) then
    raise exception 'El contrato forma parte del historial de inversiones; conserva el registro y utiliza la anulación comercial que corresponda'
      using errcode='55000';
  end if;

  select * into v_eliminacion
  from private.contrato_eliminaciones e
  where e.contrato_id = p_contrato_id
  for update;
  if found then
    return jsonb_build_object(
      'contrato_id', v_eliminacion.contrato_id,
      'token', v_eliminacion.token,
      'objetos', v_eliminacion.objetos
    );
  end if;

  if exists (
    select 1
    from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id
      and j.estado in ('procesando', 'subido_verificado')
      and j.lease_expira_en > statement_timestamp()
  ) then
    raise exception
      'El PDF se está generando; reintenta la eliminación en unos minutos'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from public.documentos d
    where d.contrato_id = p_contrato_id
      and (
        d.storage_path is null
        or d.storage_path <> btrim(d.storage_path)
        or length(d.storage_path) not between 5 and 1024
        or left(d.storage_path, length(p_contrato_id::text) + 1)
             <> p_contrato_id::text || '/'
        or strpos(d.storage_path, '..') > 0
        or strpos(d.storage_path, '//') > 0
        or strpos(d.storage_path, E'\\') > 0
        or d.storage_path ~ '[[:cntrl:]]'
      )
  ) then
    raise exception 'Un documento del contrato tiene una ruta Storage inválida'
      using errcode = '23514';
  end if;

  select coalesce(jsonb_agg(objeto order by objeto->>'bucket', objeto->>'path'), '[]'::jsonb)
  into v_objetos
  from (
    select distinct jsonb_build_object(
      'bucket', 'contratos-generados', 'path', x.storage_path
    ) as objeto
    from (
      select j.storage_path
      from private.contrato_pdf_jobs j
      where j.contrato_id = p_contrato_id
      union
      select p.storage_path
      from private.contrato_pdfs p
      where p.contrato_id = p_contrato_id
    ) x
    where x.storage_path is not null

    union

    select distinct jsonb_build_object(
      'bucket', 'documentos', 'path', d.storage_path
    ) as objeto
    from public.documentos d
    where d.contrato_id = p_contrato_id
      and d.storage_path is not null
      and btrim(d.storage_path) <> ''
  ) objetos;

  if jsonb_array_length(v_objetos) > 1000 then
    raise exception 'El contrato supera el límite seguro de archivos para borrar'
      using errcode = '54000';
  end if;

  insert into private.contrato_eliminaciones (
    contrato_id, solicitado_por, objetos
  ) values (
    p_contrato_id, p_actor_id, v_objetos
  ) returning * into v_eliminacion;

  return jsonb_build_object(
    'contrato_id', v_eliminacion.contrato_id,
    'token', v_eliminacion.token,
    'objetos', v_eliminacion.objetos
  );
end;
$function$;
-- Adaptación acotada de public.proteger_campos_inmutables(); antes 5e64e3fc95b367d262b4d7b39c687cde
CREATE OR REPLACE FUNCTION public.proteger_campos_inmutables()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_f4_alinea boolean := false;
BEGIN
  -- Excepción de una única columna desde la revisión F4 del servidor. Las
  -- escrituras directas mantienen todas las congelaciones originales.
  IF TG_TABLE_NAME='perfiles' AND current_user='postgres'
     AND nullif(current_setting('crm.f4_revision_solicitud',true),'') IS NOT NULL THEN
    v_f4_alinea:=private.f4_alineacion_perfil_permitida(OLD.id,NEW.asesor_perfil_id);
  END IF;
  NEW.id         := OLD.id;
  NEW.creado_en  := OLD.creado_en;
  NEW.creado_por := OLD.creado_por;

  -- Campos privilegiados / de asignacion: se congelan para el usuario que edita su PROPIA
  -- fila (cliente) y TAMBIEN para un ANALISTA que edita la fila de un cliente. Antes solo se
  -- congelaban en la auto-edicion (NEW.id=auth.uid()), por eso un analista podia togglear
  -- activo / debe_cambiar_password / blanquear asesor_perfil_id de su cliente via UPDATE forjado.
  -- admin/superadmin quedan EXCLUIDOS (siguen reasignando/activando). service_role
  -- (auth.uid() IS NULL, no es_analista) NO se ve afectado -> las edges de alta/baja siguen igual.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND ( NEW.id = auth.uid() OR public.es_analista() ) THEN
    NEW.activo           := OLD.activo;
    NEW.rol              := OLD.rol;
    NEW.asesor_id        := OLD.asesor_id;
    IF NOT v_f4_alinea THEN NEW.asesor_perfil_id := OLD.asesor_perfil_id; END IF;
    NEW.cargo            := OLD.cargo;
    -- El flag de cambio de clave solo lo baja el PROPIO usuario (primer login);
    -- un analista editando a un cliente NO puede tocarlo.
    IF NEW.id <> auth.uid() THEN
      NEW.debe_cambiar_password := OLD.debe_cambiar_password;
    END IF;
  END IF;

  -- Asiento «Operaciones» (2026-08-21): edita al cliente y lo activa o desactiva,
  -- pero NO lo mueve de analista. El `rol` se congela ademas por si acaso: la
  -- politica ya lo acota a 'cliente', esto es la segunda linea de defensa.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND public.es_operaciones()
     AND NEW.id <> auth.uid() THEN
    IF (NEW.asesor_perfil_id IS DISTINCT FROM OLD.asesor_perfil_id AND NOT v_f4_alinea)
       OR NEW.asesor_id IS DISTINCT FROM OLD.asesor_id THEN
      RAISE EXCEPTION 'El asiento Operaciones no puede reasignar el asesor de un cliente'
        USING ERRCODE = '42501';
    END IF;
    NEW.rol := OLD.rol;
  END IF;

  -- Ciclo de vida de contratos (2026-07-13): una vez cerrado un ciclo, el
  -- enlace de renovacion y los sellos de cierre quedan congelados para
  -- cualquier no-superadmin (correcciones = superadmin).
  IF TG_TABLE_NAME = 'contratos' AND NOT public.es_superadmin() THEN
    IF OLD.renovado_a_id IS NOT NULL THEN NEW.renovado_a_id := OLD.renovado_a_id; END IF;
    IF OLD.cerrado_en    IS NOT NULL THEN NEW.cerrado_en    := OLD.cerrado_en;    END IF;
    IF OLD.cerrado_por   IS NOT NULL THEN NEW.cerrado_por   := OLD.cerrado_por;   END IF;
  END IF;

  RETURN NEW;
END; $function$;
-- Adaptación acotada de crm.anular_cierre_externo(uuid, text); antes f77ef584632cc37afc06ab3864d41805
CREATE OR REPLACE FUNCTION crm.anular_cierre_externo(p_cierre_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_cierre crm.cierres_externos%rowtype;
  v_motivo text := btrim(p_motivo);
  v_ajuste uuid;
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia anula cierres externos'
      using errcode = '42501';
  end if;

  -- El motivo es obligatorio a propósito: esto le quita dinero a una persona y
  -- esa persona merece una razón escrita, no un registro de auditoría mudo.
  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la anulacion'
      using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres'
      using errcode = '22023';
  end if;

  select * into v_cierre
  from crm.cierres_externos
  where id = p_cierre_id
  for update;
  if not found then
    raise exception 'Cierre externo no encontrado';
  end if;
  if v_cierre.anulado_en is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre ya estaba anulado',
      detail  = pg_catalog.format('cierre %s, anulado el %s', v_cierre.id, v_cierre.anulado_en);
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.cierres_externos
     set anulado_en = now(),
         anulado_por = v_uid,
         motivo_anulacion = v_motivo
   where id = p_cierre_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo.
  if v_cierre.es_cierre_inicial then
    v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_cierre.lead_id, v_motivo, v_uid);
  end if;

  if v_cierre.lead_id is not null then
  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    v_cierre.lead_id,
    'nota',
    'Gerencia anulo el cierre externo',
    jsonb_build_object(
      'accion', 'anulacion_cierre_externo',
      'cierre_externo_id', p_cierre_id,
      'motivo', v_motivo,
      'mes_cerrado', v_ajuste is not null,
      'anulado', jsonb_build_object(
        'cooperativa', v_cierre.cooperativa,
        'monto', v_cierre.monto,
        'moneda', v_cierre.moneda,
        'numero_transaccion', v_cierre.numero_transaccion,
        'vendedor_id', v_cierre.vendedor_id)
    ),
    v_uid
  );
  end if;

  return jsonb_build_object(
    'ok', true,
    'cierre_id', p_cierre_id,
    'lead_id', v_cierre.lead_id,
    'mes_cerrado', v_ajuste is not null,
    'ajuste_id', v_ajuste);
end;
$function$;
-- Adaptación acotada de crm.corregir_cierre_externo(uuid, numeric, text, text, text, text, date, text); antes 73cccb38b57506b065b0eb903838b4a0
CREATE OR REPLACE FUNCTION crm.corregir_cierre_externo(p_cierre_id uuid, p_monto numeric, p_moneda text, p_cooperativa text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_cierre      crm.cierres_externos%rowtype;
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia corrige cierres externos'
      using errcode = '42501';
  end if;

  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;

  select * into v_cierre
  from crm.cierres_externos
  where id = p_cierre_id
  for update;
  if not found then
    raise exception 'Cierre externo no encontrado';
  end if;
  -- Un cierre anulado no se retoca: corregirlo daría a entender que vuelve a
  -- contar, y no vuelve. Si el monto anulado estaba mal, da igual: no paga.
  if v_cierre.anulado_en is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre esta anulado: ya no cuenta y no se corrige',
      detail  = pg_catalog.format('cierre %s, anulado el %s', v_cierre.id, v_cierre.anulado_en);
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  begin
    update crm.cierres_externos
       set monto = p_monto,
           moneda = p_moneda,
           cooperativa = p_cooperativa,
           numero_transaccion = v_transaccion,
           referencia_externa = v_referencia,
           vence_en = p_vence_en,
           nota = nullif(btrim(p_nota), '')
     where id = p_cierre_id;

    -- Si gerencia cambia el número, el NUEVO se reclama para siempre. El
    -- ANTERIOR no se libera: sigue en la memoria histórica, que es justo lo que
    -- impide que otro lead lo declare y el mismo depósito se cobre dos veces.
    if upper(v_transaccion) is distinct from upper(v_cierre.numero_transaccion) then
      insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
      values (upper(v_transaccion), p_cierre_id, v_uid);
    end if;
  exception when unique_violation then
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes (aunque su cierre se haya corregido despues): no se puede reusar.';
  end;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Rastro de negocio en la línea de tiempo del lead. Tipo 'nota' porque el
  -- CHECK de actividades no tiene 'correccion' y ampliarlo por esto no paga:
  -- el QUÉ cambió va en metadata (y el audit trigger guarda la fila entera).
  if v_cierre.lead_id is not null then
  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    v_cierre.lead_id,
    'nota',
    'Gerencia corrigio el cierre externo',
    jsonb_build_object(
      'accion', 'correccion_cierre_externo',
      'cierre_externo_id', p_cierre_id,
      'antes', jsonb_build_object(
        'monto', v_cierre.monto, 'moneda', v_cierre.moneda,
        'cooperativa', v_cierre.cooperativa,
        'numero_transaccion', v_cierre.numero_transaccion,
        'referencia_externa', v_cierre.referencia_externa,
        'vence_en', v_cierre.vence_en, 'nota', v_cierre.nota),
      'despues', jsonb_build_object(
        'monto', p_monto, 'moneda', p_moneda,
        'cooperativa', p_cooperativa,
        'numero_transaccion', v_transaccion,
        'referencia_externa', v_referencia,
        'vence_en', p_vence_en, 'nota', nullif(btrim(p_nota), ''))
    ),
    v_uid
  );
  end if;

  return jsonb_build_object('ok', true, 'cierre_id', p_cierre_id);
end;
$function$;
-- Adaptación acotada de crm.cierres_externos_fn(date); antes 337700989baed6b15f72349c021bb387
CREATE OR REPLACE FUNCTION crm.cierres_externos_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text;
  v_lector     boolean;
  v_global     boolean;
  v_filas      boolean;
  v_alcance    text;
  v_visibles   uuid[];
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini        timestamptz;
  v_fin        timestamptz;
  v_payload    jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_filas := coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false);
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'alcance', v_alcance,
    -- Filas para la sección «En cooperativas» de Mi cartera (todo el
    -- histórico del ámbito, más reciente primero). Tope de 200 con total al
    -- lado: sin tope sería la lista sin fin que F2 vino a matar; con tope
    -- mudo, el front sumaría filas truncadas y mentiría en los totales — por
    -- eso los mini-totales NO salen de las filas sino de `totales`.
    'cierres', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or case
          -- F3 conserva la tenencia del lead convertido como historia. El
          -- teléfono vivo de una persona reconocida sigue su relación actual.
          when ce.inversionista_id is not null then exists (
            select 1 from crm.inversionistas ip
            where ip.id=private.inversionista_canonica(ce.inversionista_id)
              and ip.responsable_relacion_id=any(v_visibles))
          else l.vendedor_id=any(v_visibles) end
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'fecha_comercial', coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
        'fecha_imputacion', coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
        'es_cierre_inicial', ce.es_cierre_inicial,
        -- Los anulados SÍ viajan en las filas (y NO en los totales): el asesor
        -- tiene que poder entender por qué le bajó el total, no encontrarse un
        -- hueco donde antes había un cierre.
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where v_global or ce0.vendedor_id = any(v_visibles)
        order by ce0.creado_en desc
        limit 200
      ) ce
      left join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where v_global or ce.vendedor_id = any(v_visibles)
    ),
    -- Las filas DEL MES pedido: es la vista de revisión de supervisor y gerencia
    -- («Ver cierres del mes»), donde el número de operación se contrasta. NO se
    -- filtra en el cliente sobre `cierres`, que viene tope 200 por antigüedad y
    -- podría no alcanzar el mes entero.
    'cierres_mes', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or case
          -- F3 conserva la tenencia del lead convertido como historia. El
          -- teléfono vivo de una persona reconocida sigue su relación actual.
          when ce.inversionista_id is not null then exists (
            select 1 from crm.inversionistas ip
            where ip.id=private.inversionista_canonica(ce.inversionista_id)
              and ip.responsable_relacion_id=any(v_visibles))
          else l.vendedor_id=any(v_visibles) end
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'fecha_comercial', coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
        'fecha_imputacion', coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
        'es_cierre_inicial', ce.es_cierre_inicial,
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where coalesce((ce0.fecha_imputacion::timestamp at time zone 'America/Lima'),ce0.creado_en) >= v_ini and coalesce((ce0.fecha_imputacion::timestamp at time zone 'America/Lima'),ce0.creado_en) < v_fin
          and (v_global or ce0.vendedor_id = any(v_visibles))
        order by ce0.creado_en desc
        limit 200
      ) ce
      left join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_mes_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= v_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < v_fin
        and (v_global or ce.vendedor_id = any(v_visibles))
    ),
    -- Mini-totales de Mi cartera: TODO el histórico del ámbito, por
    -- cooperativa y moneda (PEN/USD jamás sumados). Servidos aquí para que el
    -- front no haga aritmética sobre una lista que puede venir truncada.
    'totales', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cooperativa', t.cooperativa,
        'moneda', t.moneda,
        'capital', t.capital,
        'cierres', t.cierres
      ) order by t.cooperativa, t.moneda)
      from (
        select ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        where (v_global or ce.vendedor_id = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.cooperativa, ce.moneda
      ) t
    ), '[]'::jsonb),
    -- Desglose por empresa del MES pedido, por vendedor × cooperativa ×
    -- moneda, para supervisor y gerencia. La parte «Avance» del desglose la
    -- pone cumplimiento_metas_fn (capital_real ya INCLUYE los externos tras
    -- esta migración): Avance = capital_real − estos agregados, resta de dos
    -- números servidos — no una división en cliente.
    'por_empresa', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', x.vendedor_id,
        'vendedor_nombre', x.nombre,
        'cooperativa', x.cooperativa,
        'moneda', x.moneda,
        'capital', x.capital,
        'cierres', x.cierres
      ) order by x.nombre, x.cooperativa, x.moneda)
      from (
        select ce.vendedor_id, p.nombre_completo as nombre,
               ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        left join public.perfiles p on p.id = ce.vendedor_id
        where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= v_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < v_fin
          and (v_global or ce.vendedor_id = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.vendedor_id, p.nombre_completo, ce.cooperativa, ce.moneda
      ) x
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;
-- Adaptación acotada de private.metricas_conversiones_implementacion(date, date, text); antes be4e1c283a1f3042828cbb8c66332252
CREATE OR REPLACE FUNCTION private.metricas_conversiones_implementacion(p_desde date, p_hasta date, p_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_cosecha_fin timestamptz;
  v_ahora timestamptz := now();
  v_mes date;
  v_factor numeric;
  v_periodo date;
  v_payload jsonb;
  v_autorizado boolean;
begin
  select exists (
    select 1 from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo and e.rol_crm = 'gerencia'
  ) or private.es_lector_global() into v_autorizado;
  if v_uid is null or not coalesce(v_autorizado, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  -- La cosecha mira hasta HOY: un lead que entro en el rango puede haber
  -- cerrado despues, y esa maduracion es justamente lo que la lectura por
  -- cosecha responde («de ese lote, cuantos acabaron cerrando»).
  v_cosecha_fin := greatest(v_fin, v_ahora);

  -- Peso del referido del mes del `hasta` — la MISMA regla que usa el heroe
  -- de HOY para el mes del rango.
  v_mes := date_trunc('month', p_hasta)::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- El periodo identifica una ventana mensual; ya NO habilita/deshabilita
  -- cartera: el núcleo limita toda operación a su fecha efectiva en el rango.
  -- En rangos libres aplica el peso de cada mes dentro del propio núcleo.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  with vendedores_base as materialized (
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo and p.activo and e.rol_crm = 'vendedor'
  ),
  -- ── TABLA-BASE ──────────────────────────────────────────────────────────
  -- Flujo comercial del rango: llegadas únicas y aportes del núcleo.
  ep_flujo as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, true, null, v_factor
    ) e
  ),
  -- Cierres del ledger que sirven de numerador a la COSECHA: los de sus
  -- leads, ocurran cuando ocurran (hasta hoy). Sin anulados.
  ep_cosecha as materialized (
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null, true, null, v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
  ),
  cohorte_base as materialized (
    -- F1.3b: el capital del lead se mide por los caminos VIVOS y HASTA HOY
    -- (lectura de cosecha: «de ese lote, cuanto ha producido»): contratos del
    -- portal de su perfil + cierres en coops vigentes. Aqui muere la primera
    -- de las dos ultimas lecturas del enlace jamas poblado (leads.contrato_id).
    select l.id, l.origen, l.etapa, l.categoria_interes, l.creado_en,
      l.convertido_en, l.perfil_id, l.contrato_id, l.asignado_supervisor_id,
      l.creado_por, llegada.analista_id as vendedor_id,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           '-infinity'::timestamptz,
           'infinity'::timestamptz, true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           '-infinity'::timestamptz,
           'infinity'::timestamptz, true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_usd
    from ep_flujo llegada
    join crm.leads l on l.id = llegada.lead_id
    where llegada.tipo = 'recibido'
      -- Filtro de ORIGEN (pedido de Miguel 27/08): recorta el LOTE — cohorte,
      -- embudo, origenes, categorias, responsables y tendencia beben todos de
      -- aqui. 'sin_origen' selecciona los leads sin origen registrado. El
      -- nucleo y las sondas de paridad NO se filtran (miden el MES de la
      -- empresa y esta pantalla ya no los pinta): el payload declara el
      -- filtro en `origen_filtrado` para que nadie confunda las dos aguas.
      and (p_origen is null or coalesce(l.origen, 'sin_origen') = p_origen)
  ),
  -- N1: citas clasificadas por el núcleo, sobre el lote de llegadas. El
  -- instante disponible es vence_en (fecha prevista); no se inventa una fecha
  -- física de asistencia ni una identidad de persona distinta de lead_id.
  citas_reales_ep as materialized (
    select ce.*
    from private.citas_episodios(v_ini, v_ahora, v_ahora) ce
    where ce.realizada and ce.debio_ocurrir
  ),
  citas_reales_cohorte as materialized (
    select cb.id as lead_id,
      count(ce.tarea_id) filter (where ce.vence_en >= cb.creado_en)::int
        as citas_realizadas,
      count(ce.tarea_id) filter (where ce.vence_en < cb.creado_en)::int
        as citas_anteriores_al_alta
    from cohorte_base cb
    left join citas_reales_ep ce on ce.lead_id = cb.id
    group by cb.id
  ),
  senales as materialized (
    select cb.*,
      (cb.vendedor_id is not null or cb.asignado_supervisor_id is not null or exists (
        select 1 from crm.lead_asignaciones la where la.lead_id = cb.id
      )) as h_asignado,
      exists (
        select 1 from crm.actividades a
        where a.lead_id = cb.id and (
          a.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada')
          or (a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' in (
            'contactado','reunion_agendada','propuesta_enviada','convertido'
          ))
        )
      ) as h_contacto,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id and t.tipo = 'reunion'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'reunion_agendada'
      ) as h_reunion_agendada,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id
          and t.tipo = 'reunion' and t.estado = 'completada'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id and a.tipo = 'reunion_realizada'
      ) as h_reunion_realizada,
      exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'propuesta_enviada'
      ) or cb.etapa = 'propuesta_enviada' as h_propuesta,
      -- ANTES: (perfil_id is not null or etapa = 'convertido') / (contrato_id is not null)
      -- AHORA: el cierre del LEDGER, sin anulados. Un cierre anulado por
      -- gerencia deja de contar aqui igual que en el nucleo.
      (cb.id in (select ec.lead_id from ep_cosecha ec)) as h_cliente,
      (cb.id in (select ec.lead_id from ep_cosecha ec)) as h_contrato
    from cohorte_base cb
  ),
  cohorte as materialized (
    select s.*,
      (cr.citas_realizadas > 0) as cita_real,
      cr.citas_realizadas as citas_realizadas_reales,
      cr.citas_anteriores_al_alta,
      h_asignado as asignado,
      (h_contacto or h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as contactado,
      (h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_agendada,
      (h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_realizada,
      (h_propuesta or h_cliente or h_contrato) as propuesta,
      (h_cliente or h_contrato) as cliente,
      h_contrato as contrato
    from senales s
    join citas_reales_cohorte cr on cr.lead_id = s.id
  ),
  resumen as (
    select
      count(*)::int as leads,
      count(*) filter (where asignado)::int as asignados,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cita_real)::int as leads_con_cita_real,
      coalesce(sum(citas_realizadas_reales), 0)::int as citas_realizadas_reales,
      coalesce(sum(citas_anteriores_al_alta), 0)::int as citas_anteriores_al_alta,
      count(*) filter (where propuesta)::int as propuestas,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte
  ),
  -- ── NUCLEO (cifra principal) ────────────────────────────────────────────
  -- Se agrupa POR ANALISTA con la misma aritmetica del nucleo y luego se suma.
  -- OJO: el total NO tiene por que ser la suma de `responsables`: aqui entran
  -- TODOS los analistas con episodios (supervisores incluidos), mientras que
  -- `responsables` sale del roster de vendedores activos y ademas el wrapper
  -- publico elimina del array a quien no sea vendedor. La sonda
  -- `divisor_fuera_del_roster` mide exactamente ese hueco.
  nucleo_vendedor as (
    select e.analista_id,
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
    from ep_flujo e
    group by e.analista_id
  ),
  nucleo as (
    select
      coalesce(sum(nv.divisor), 0)::int as divisor,
      coalesce(sum(nv.referidos_recibidos), 0)::int as referidos_recibidos,
      coalesce(sum(nv.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(nv.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(nv.operaciones), 0)::int as operaciones,
      coalesce(sum(nv.numerador), 0)::numeric as numerador
    from nucleo_vendedor nv
  ),
  -- Sonda de paridad: cuando el rango es un mes exacto, este recomputo debe
  -- coincidir EXACTAMENTE con el nucleo. Si no, el front avisa.
  -- Sonda de paridad: compara TODOS los terminos (divisor, ambos tipos de
  -- cierre y el numerador entero — que es donde vive la cartera), y declara
  -- cuantas filas comparo: sin filas la paridad no prueba nada y se dice
  -- (`cuadra` = null), en vez de dar un cero tranquilizador y vacuo.
  comparacion as (
    select nv.analista_id as a_nuevo, cm.analista_id as a_nucleo,
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nucleo_vendedor nv
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, null, v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda_paridad as (
    select
      coalesce(sum(c.delta), 0) as desvio,
      count(*)::int as filas
    from comparacion c
  ),
  produccion as (
    select
      (select count(*)::int from crm.leads l
        where l.convertido_en >= v_ini and l.convertido_en < v_fin) as clientes,
      -- F1.3 (27/08): el enlace leads.contrato_id JAMAS se poblo (auditoria en
      -- prod: 0 enlaces historicos, S/ 0 eterno con capital real cerrado) y
      -- ningun flujo lo escribe. El camino VIVO es el perfil nacido del lead
      -- (leads.perfil_id = contratos.cliente_id) mas los cierres en
      -- cooperativas (crm.cierres_externos por lead, sin anulados). La columna
      -- contrato_id no se toca: en produccion no se borra nada.
      ((select count(*)::int from (select * from public.contratos where not es_demo) c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id))
       + (select count(*)::int from crm.cierres_externos ce
          where ce.anulado_en is null
            and (coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date between p_desde and p_hasta)) as contratos,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_usd,
      -- Sonda F1.3: convertidos del rango SIN rastro de capital (ni perfil ni
      -- cierre externo vigente). El hueco se declara; el front lo rotula.
      (select count(*)::int from crm.leads l
        where l.convertido_en >= v_ini and l.convertido_en < v_fin
          and l.perfil_id is null
          and not exists (select 1 from crm.cierres_externos ce
                          where ce.lead_id = l.id and ce.es_cierre_inicial and ce.anulado_en is null)) as sin_rastro
  ),
  origenes as (
    select coalesce(origen, 'sin_origen') as origen,
      count(*)::int as leads,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cita_real)::int as leads_con_cita_real,
      coalesce(sum(citas_realizadas_reales), 0)::int as citas_realizadas_reales,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados,
      coalesce(sum(capital_lead_pen), 0) as capital_pen,
      coalesce(sum(capital_lead_usd), 0) as capital_usd
    from cohorte group by coalesce(origen, 'sin_origen')
  ),
  categorias as (
    select coalesce(categoria_interes, 'sin_categoria') as categoria,
      count(*)::int as leads,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte group by coalesce(categoria_interes, 'sin_categoria')
  ),
  responsables_resumen as (
    select vb.vendedor_id,
      count(c.id)::int as leads,
      count(c.id) filter (where c.contactado)::int as contactados,
      count(c.id) filter (where c.reunion_realizada)::int as reuniones_realizadas,
      count(c.id) filter (where c.cita_real)::int as leads_con_cita_real,
      coalesce(sum(c.citas_realizadas_reales), 0)::int as citas_realizadas_reales,
      count(c.id) filter (where c.contrato)::int as contratos
    from vendedores_base vb
    left join cohorte c on c.vendedor_id = vb.vendedor_id
    group by vb.vendedor_id
  ),
  capital_responsables as (
    -- F1.3b: capital DEL RANGO por vendedor, por los caminos vivos — contratos
    -- del portal (fecha de cierre en el rango) de perfiles nacidos de SUS
    -- leads (el `in` dedupe si dos leads compartieran perfil) + sus cierres en
    -- coops del rango. Aqui muere la ULTIMA lectura del enlace jamas poblado.
    select vb.vendedor_id,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_usd
    from vendedores_base vb
  )
  select jsonb_build_object(
    'version', 1,
    'origen_filtrado', p_origen,
    'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1, 'zona', 'America/Lima'
    ),
    'nucleo', jsonb_build_object(
      'llegadas', (select count(*) from ep_flujo e where e.tipo = 'recibido'),
      'altas_manuales', (select count(*) from ep_flujo e
        where e.tipo = 'recibido' and not e.fue_referido and e.aporte_divisor = 0),
      'renovaciones', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'renovacion'),
      'upgrades', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'upgrade'),
      'aporte_cartera', (select coalesce(sum(e.aporte_numerador), 0) from ep_flujo e where e.tipo = 'operacion'),
      'base', 'llegada_unica',
      'atribucion', 'primer_analista',
      'peso_renovacion', v_factor,
      'incluye_cartera', true,
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      'divisor', n.divisor,
      'referidos_recibidos', n.referidos_recibidos,
      'cierres_no_referidos', n.cierres_no_referidos,
      'cierres_referidos', n.cierres_referidos,
      'operaciones_cartera', n.operaciones,
      'numerador', n.numerador,
      -- DOS decimales, como el nucleo real: este numero DEBE poder compararse
      -- byte a byte con el heroe de HOY, no redondearse distinto.
      'conversion_pct', case when n.divisor > 0
        then round(100.0 * n.numerador / n.divisor, 2) end,
      'referidos_cierran_pct', case when n.referidos_recibidos > 0
        then round(100.0 * n.cierres_referidos / n.referidos_recibidos, 1) end
    ),
    'cosecha', jsonb_build_object(
      'base', 'alta',
      'madura_hasta', v_cosecha_fin,
      'leads', r.leads,
      'cerraron', r.clientes,
      'conversion_pct', case when r.leads > 0
        then round(100.0 * r.clientes / r.leads, 1) end
    ),
    'citas_reales', jsonb_build_object(
      'version', 1,
      'unidad', 'lead_id',
      'base', 'llegadas_unicas',
      'fecha_cita', 'vence_en',
      'seguimiento_hasta', v_ahora,
      'origen_filtrado', p_origen,
      'atribucion', 'primer_analista',
      'leads_base', r.leads,
      'leads_con_cita_real', r.leads_con_cita_real,
      'citas_realizadas', r.citas_realizadas_reales,
      'citas_anteriores_al_alta', r.citas_anteriores_al_alta,
      'pct_llegadas_con_cita_real', case when r.leads > 0
        then round(100.0 * r.leads_con_cita_real / r.leads, 1) end
    ),
    'conversion_operaciones', jsonb_build_object(
      'version', 1,
      'lectura', 'viva',
      'completo', true,
      'desde', p_desde,
      'hasta', p_hasta,
      'zona', 'America/Lima',
      'origen_filtrado', null,
      'cantidad', (
        select count(*)::int from ep_flujo e where e.tipo = 'operacion'
      ),
      'aporte_total', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e where e.tipo = 'operacion'
      ),
      'detalle', coalesce((
        select jsonb_agg(jsonb_build_object(
          'operacion_id', e.operacion_id,
          'analista_id', e.analista_id,
          'categoria', e.categoria,
          'periodo', e.mes_origen,
          'fecha_numerador', e.fecha_numerador,
          'aporte_numerador', e.aporte_numerador
        ) order by e.fecha_numerador, e.operacion_id)
        from ep_flujo e
        where e.tipo = 'operacion' and e.operacion_id is not null
      ), '[]'::jsonb)
    ),
    'cierres_por_semana', jsonb_build_object(
      'version', 1,
      'desde', p_desde,
      'hasta', p_hasta,
      'base', 'fecha_numerador',
      'atribucion', 'autor_cierre',
      'agrupacion', 'bloques_7_dias_desde_inicio',
      'zona', 'America/Lima',
      'origen_filtrado', p_origen,
      'incluye_operaciones_cartera', false,
      'cierres', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      'aporte_cierres', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      -- El total global conserva cierres de bajas, supervisores o autor nulo,
      -- mientras responsables[] sólo enumera vendedores activos. El residual
      -- hace visible esa diferencia sin reasignar el cierre a otra persona.
      'cierres_fuera_del_roster', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
          and (e.analista_id is null or not exists (
            select 1 from vendedores_base vb
            where vb.vendedor_id = e.analista_id
          ))
      ),
      'aporte_cierres_fuera_del_roster', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
          and (e.analista_id is null or not exists (
            select 1 from vendedores_base vb
            where vb.vendedor_id = e.analista_id
          ))
      ),
      'semanas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'semana', semanal.semana,
          'desde', semanal.desde,
          'hasta', semanal.hasta,
          'cierres', semanal.cierres,
          'aporte_cierres', semanal.aporte_cierres,
          'cierres_fuera_del_roster', semanal.cierres_fuera_del_roster,
          'aporte_cierres_fuera_del_roster', semanal.aporte_cierres_fuera_del_roster
        ) order by semanal.semana)
        from (
          select gs.semana_indice + 1 as semana,
            p_desde + (gs.semana_indice * 7) as desde,
            least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
            count(distinct e.lead_id)::int as cierres,
            coalesce(sum(e.aporte_numerador), 0) as aporte_cierres,
            count(distinct e.lead_id) filter (
              where e.analista_id is null or not exists (
                select 1 from vendedores_base vb
                where vb.vendedor_id = e.analista_id
              )
            )::int as cierres_fuera_del_roster,
            coalesce(sum(e.aporte_numerador) filter (
              where e.analista_id is null or not exists (
                select 1 from vendedores_base vb
                where vb.vendedor_id = e.analista_id
              )
            ), 0) as aporte_cierres_fuera_del_roster
          from generate_series(
            0, ((p_hasta - p_desde) / 7)
          ) as gs(semana_indice)
          left join ep_flujo e
            on e.tipo = 'cierre' and not e.anulado
           and e.origen in ('landing', 'formulario', 'referido')
           and (p_origen is null or e.origen = p_origen)
           and (e.fecha_numerador at time zone 'America/Lima')::date
               between p_desde + (gs.semana_indice * 7)
                   and least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
          group by gs.semana_indice
        ) semanal
      ), '[]'::jsonb)
    ),
    'sondas', jsonb_build_object(
      'paridad_nucleo', sp.desvio,
      'paridad_filas', sp.filas,
      -- null = la sonda NO probo nada (rango sin mes, o sin una sola fila que
      -- comparar). Un true solo se afirma cuando hubo sustancia.
      'cuadra', case when sp.desvio is null or sp.filas = 0 then null
                     else sp.desvio = 0 end,
      'episodios_sin_origen', (
        select count(*)::int from ep_flujo e
        where e.tipo in ('recibido','cierre') and e.origen is null
      ),
      'cierres_anulados', (
        select count(*)::int from ep_flujo e
        where e.tipo = 'cierre' and e.anulado
      ),
      -- Cuanto divisor NO aparecera en `responsables`: episodios de analistas
      -- fuera del roster de vendedores activos (supervisores, bajas). Sin esto
      -- el desglose parece que no suma el total y nadie sabe por que.
      'divisor_fuera_del_roster', (
        select coalesce(sum(nv2.divisor), 0)::int
        from nucleo_vendedor nv2
        where nv2.analista_id is null
           or nv2.analista_id not in (select vb2.vendedor_id from vendedores_base vb2)
      ),
      -- Numerador que tampoco aparecera en `responsables`, por la misma razon
      -- que el divisor: analistas con cierres/cartera fuera del roster.
      'numerador_fuera_del_roster', (
        select coalesce(sum(
          nv3.numerador
        ), 0)
        from nucleo_vendedor nv3
        where nv3.analista_id is null
           or nv3.analista_id not in (select vb3.vendedor_id from vendedores_base vb3)
      ),
      -- Leads que la ficha da por convertidos pero SIN cierre elegible (o con
      -- el cierre anulado) en el ledger: el desacuerdo entre las dos verdades,
      -- medido en vez de tapado. Nombre explicito: «elegible», no «cierre».
      'cohorte_convertidos_sin_cierre_elegible', (
        select count(*)::int from cohorte c2
        where (c2.perfil_id is not null or c2.etapa = 'convertido')
          and c2.id not in (select ec2.lead_id from ep_cosecha ec2)
      ),
      -- El desacuerdo INVERSO: cierre elegible cuyo lead no figura convertido
      -- en su ficha. Sin esta, la sonda solo miraba en una direccion.
      'cierres_sin_ficha_convertida', (
        select count(*)::int from cohorte c3
        where c3.id in (select ec3.lead_id from ep_cosecha ec3)
          and c3.perfil_id is null and c3.etapa is distinct from 'convertido'
      ),
      -- Leads cuyo origen en la FICHA no coincide con el del ledger: mientras
      -- sea 0, rotular `peso_en_nucleo` sobre la fila de origen es seguro; si
      -- sube, la barra «Referido» de la ficha y la del nucleo hablan de
      -- poblaciones distintas (aviso de F3).
      'origen_ficha_distinto_del_ledger', (
        select count(*)::int
        from cohorte c4
        join (
          select e4.lead_id, bool_or(e4.fue_referido) as ref_ledger
          from ep_flujo e4 where e4.tipo = 'recibido' group by e4.lead_id
        ) l4 on l4.lead_id = c4.id
        where (c4.origen = 'referido') is distinct from l4.ref_ledger
      ),
      -- Operaciones de cartera contadas cuya fecha cae FUERA del rango pedido
      -- (solo puede pasar con fechas futuras dentro del mes en curso). NO se
      -- descuentan: el heroe de HOY las cuenta igual y la paridad manda; se
      -- DECLARAN para que F3 avise.
      'cartera_fuera_del_rango', (
        select count(*)::int from ep_flujo e
        where e.tipo = 'operacion'
          and (e.fecha_numerador at time zone 'America/Lima')::date not between p_desde and p_hasta
      ),
      -- F1.3b (hallazgo MEDIO-1 del auditor): un cliente puede volver como
      -- lead NUEVO de OTRO vendedor (los unicos de leads excluyen convertido y
      -- la edge reutiliza el perfil por DNI). Si pasa, su capital de portal
      -- cuenta ENTERO para ambos vendedores y el desglose suma mas que el
      -- total. Hoy es 0 (medido 27/08); esta sonda lo vigila para siempre y
      -- el front avisa si sube.
      'perfiles_con_leads_de_varios_vendedores', (
        select count(*)::int from (
          select l2.perfil_id
          from crm.leads l2
          where l2.perfil_id is not null and l2.vendedor_id is not null
          group by l2.perfil_id
          having count(distinct l2.vendedor_id) > 1
        ) dobles
      )
    ),
    'cohorte', jsonb_build_object(
      'leads', r.leads, 'asignados', r.asignados, 'contactados', r.contactados,
      'reuniones_agendadas', r.reuniones_agendadas,
      'reuniones_realizadas', r.reuniones_realizadas,
      'propuestas', r.propuestas, 'clientes', r.clientes,
      'contratos', r.contratos, 'descartados', r.descartados,
      'conversion_clientes_pct', case when r.leads > 0 then round(100.0 * r.clientes / r.leads, 1) end,
      'conversion_contratos_pct', case when r.leads > 0 then round(100.0 * r.contratos / r.leads, 1) end,
      'conversion_resueltos_pct', case when r.clientes + r.descartados > 0
        then round(100.0 * r.clientes / (r.clientes + r.descartados), 1) end
    ),
    'produccion', jsonb_build_object(
      'clientes', p.clientes, 'contratos', p.contratos,
      'capital_pen', p.capital_pen, 'capital_usd', p.capital_usd,
      'sin_rastro', p.sin_rastro
    ),
    'embudo', jsonb_build_array(
      jsonb_build_object('etapa','leads','cantidad',r.leads,'pct_anterior',case when r.leads > 0 then 100 else null end,'pct_total',case when r.leads > 0 then 100 else null end),
      jsonb_build_object('etapa','contactados','cantidad',r.contactados,'pct_anterior',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_agendadas','cantidad',r.reuniones_agendadas,'pct_anterior',case when r.contactados > 0 then round(100.0*r.reuniones_agendadas/r.contactados,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_agendadas/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_realizadas','cantidad',r.reuniones_realizadas,'pct_anterior',case when r.reuniones_agendadas > 0 then round(100.0*r.reuniones_realizadas/r.reuniones_agendadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_realizadas/r.leads,1) end),
      jsonb_build_object('etapa','propuestas','cantidad',r.propuestas,'pct_anterior',case when r.reuniones_realizadas > 0 then round(100.0*r.propuestas/r.reuniones_realizadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.propuestas/r.leads,1) end),
      jsonb_build_object('etapa','clientes','cantidad',r.clientes,'pct_anterior',case when r.propuestas > 0 then round(100.0*r.clientes/r.propuestas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.clientes/r.leads,1) end),
      jsonb_build_object('etapa','contratos','cantidad',r.contratos,'pct_anterior',case when r.clientes > 0 then round(100.0*r.contratos/r.clientes,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contratos/r.leads,1) end)
    ),
    'origenes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'origen', o.origen, 'leads', o.leads, 'contactados', o.contactados,
        'reuniones_agendadas', o.reuniones_agendadas,
        'reuniones_realizadas', o.reuniones_realizadas,
        'leads_con_cita_real', o.leads_con_cita_real,
        'citas_realizadas', o.citas_realizadas_reales,
        'clientes', o.clientes, 'contratos', o.contratos, 'descartados', o.descartados,
        'conversion_clientes_pct', case when o.leads > 0 then round(100.0*o.clientes/o.leads,1) end,
        'conversion_contratos_pct', case when o.leads > 0 then round(100.0*o.contratos/o.leads,1) end,
        'conversion_resueltos_pct', case when o.clientes+o.descartados > 0 then round(100.0*o.clientes/(o.clientes+o.descartados),1) end,
        -- D6: el referido NO pesa 1 en el nucleo. Viaja el peso para que la
        -- barra se pueda rotular sin recalcular nada (F3).
        'peso_en_nucleo', case when o.origen = 'referido' then v_factor else 1 end,
        'fuera_del_divisor_del_nucleo', o.origen = 'referido',
        'capital_pen', o.capital_pen, 'capital_usd', o.capital_usd
      ) order by o.contratos desc, o.clientes desc, o.leads desc, o.origen) from origenes o
    ), '[]'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoria', c.categoria, 'leads', c.leads, 'clientes', c.clientes,
        'contratos', c.contratos, 'descartados', c.descartados,
        'conversion_pct', case when c.leads > 0 then round(100.0*c.contratos/c.leads,1) end
      ) order by c.contratos desc, c.leads desc, c.categoria) from categorias c
    ), '[]'::jsonb),
    'responsables', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', rr.vendedor_id,
        'leads', rr.leads,
        'contactados', rr.contactados,
        'reuniones_realizadas', rr.reuniones_realizadas,
        'leads_con_cita_real', rr.leads_con_cita_real,
        'citas_realizadas', rr.citas_realizadas_reales,
        'clientes', rr.contratos,
        'conversion_pct', case when rr.leads > 0 then round(100.0*rr.contratos/rr.leads,1) end,
        -- Cifra principal por vendedor (nucleo): la MISMA que Ranking y Metas.
        'nucleo_divisor', coalesce(nv.divisor, 0),
        'nucleo_numerador', coalesce(
          nv.numerador, 0),
        'nucleo_conversion_pct', case when coalesce(nv.divisor, 0) > 0
          then round(100.0 * nv.numerador / nv.divisor, 2) end,
        'capital_pen', cr.capital_pen,
        'capital_usd', cr.capital_usd,
        'cierres_por_semana', coalesce((
          select jsonb_agg(jsonb_build_object(
            'semana', cierre_semanal.semana,
            'desde', cierre_semanal.desde,
            'hasta', cierre_semanal.hasta,
            'cierres', cierre_semanal.cierres,
            'aporte_cierres', cierre_semanal.aporte_cierres
          ) order by cierre_semanal.semana)
          from (
            select gs.semana_indice + 1 as semana,
              p_desde + (gs.semana_indice * 7) as desde,
              least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
              count(distinct e.lead_id)::int as cierres,
              coalesce(sum(e.aporte_numerador), 0) as aporte_cierres
            from generate_series(
              0, ((p_hasta - p_desde) / 7)
            ) as gs(semana_indice)
            left join ep_flujo e
              on e.tipo = 'cierre' and not e.anulado
             and e.origen in ('landing', 'formulario', 'referido')
             and e.analista_id = rr.vendedor_id
             and (p_origen is null or e.origen = p_origen)
             and (e.fecha_numerador at time zone 'America/Lima')::date
                 between p_desde + (gs.semana_indice * 7)
                     and least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
            group by gs.semana_indice
          ) cierre_semanal
        ), '[]'::jsonb),
        'tendencia_semanal', coalesce((
          select jsonb_agg(jsonb_build_object(
            'semana', semanal.semana,
            'desde', semanal.desde,
            'hasta', semanal.hasta,
            'leads', semanal.leads,
            'clientes', semanal.clientes,
            'conversion_pct', case when semanal.leads > 0
              then round(100.0*semanal.clientes/semanal.leads,1) end
          ) order by semanal.semana)
          from (
            select gs.semana_indice + 1 as semana,
              p_desde + (gs.semana_indice * 7) as desde,
              least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
              count(c.id)::int as leads,
              count(c.id) filter (where c.contrato)::int as clientes
            from generate_series(0, ((p_hasta - p_desde) / 7)) as gs(semana_indice)
            left join cohorte c on c.vendedor_id = rr.vendedor_id
              and (c.creado_en at time zone 'America/Lima')::date >= p_desde + (gs.semana_indice * 7)
              and (c.creado_en at time zone 'America/Lima')::date <= least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
            group by gs.semana_indice
          ) semanal
        ), '[]'::jsonb)
      ) order by rr.contratos desc, rr.leads desc, rr.vendedor_id)
      from responsables_resumen rr
      join capital_responsables cr on cr.vendedor_id = rr.vendedor_id
      left join nucleo_vendedor nv on nv.analista_id = rr.vendedor_id
    ), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join produccion p cross join nucleo n cross join sonda_paridad sp;

  return v_payload;
end;
$function$;
-- Adaptación acotada de crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text); antes aeaead8aad9817e9790f6fc97448d25e
CREATE OR REPLACE FUNCTION crm.convertir_lead_externo(p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text DEFAULT NULL::text, p_vence_en date DEFAULT NULL::date, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_lead        crm.leads%rowtype;
  v_documento   text := upper(btrim(p_documento));
  v_nombre      text := btrim(p_nombre);
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
  v_reserva     timestamptz;
  v_efectos     timestamptz;
  v_cierre_id   uuid;
  v_flag        boolean;
  v_escribe_inversion boolean;
  v_inv         uuid;
  v_lead_canon  uuid;
  v_clave       text;
  v_hash        text;
  v_prev        jsonb;
  v_res         jsonb;
begin
  -- La autoridad no se reinterpreta en esta puerta. El helper canónico
  -- resuelve identidad, vigencia y membresía CRM activa, incluido el caso NULL.
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);
  v_escribe_inversion := private.inversiones_escritura_bajo_candado();

  -- IDEMPOTENCIA (contrato §8.3, Codex #5): misma clave + mismo payload -> mismo
  -- resultado; misma clave con otro payload -> P0409. Se evalúa ANTES de validar
  -- para que un reintento idéntico ni siquiera toque el lead.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto.) El hash cubre
  -- TODO lo que se persiste (Codex), con el número de operación en MAYÚSCULAS como
  -- se compara y reclama.
  if v_flag then
    v_clave := 'conversion_coop:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object(
                 'lead', p_lead_id, 'coop', p_cooperativa, 'monto', p_monto, 'moneda', p_moneda,
                 'tipo', p_documento_tipo, 'doc', v_documento, 'trx', upper(v_transaccion),
                 'nombre', v_nombre, 'ref', v_referencia, 'vence', p_vence_en,
                 'nota', nullif(btrim(coalesce(p_nota,'')), '')));
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;

  -- Validaciones de entrada ANTES de tocar el lead: un payload inválido no
  -- debe dejar ni un lock tomado.
  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    -- numeric(14,2) redondearía en silencio; con dinero, mejor rechazar.
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  -- En cooperativas solo se invierte en soles. Se valida en vez de forzar: un
  -- bundle viejo que mande USD merece un rechazo claro, no que le cambiemos la
  -- moneda por debajo y le contemos el monto como si fueran soles.
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if p_documento_tipo is null
     or p_documento_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido: DNI, CE o PASAPORTE'
      using errcode = '22023';
  end if;
  -- Mismas reglas que src/lib/documento.ts y el CHECK de la tabla; el error
  -- aquí habla el idioma del formulario, no el del constraint.
  if (p_documento_tipo = 'DNI'       and v_documento !~ '^[0-9]{8}$')
     or (p_documento_tipo = 'CE'        and v_documento !~ '^[0-9]{9,12}$')
     or (p_documento_tipo = 'PASAPORTE' and v_documento !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo %', p_documento_tipo
      using errcode = '22023';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'El nombre completo es obligatorio'
      using errcode = '22023';
  end if;
  -- El número de operación es OBLIGATORIO (y único por cooperativa, ver el
  -- índice): es lo único que impide cobrar dos veces un mismo cierre real.
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  -- La fecha del cierre es HOY (automática): el vencimiento de una inversión
  -- recién cerrada solo puede ser futuro. En corregir_cierre_externo este
  -- check NO existe a propósito: una corrección tardía de otro campo debe
  -- poder reenviar un vencimiento que ya pasó.
  if p_vence_en is not null and p_vence_en <= (now() at time zone 'America/Lima')::date then
    raise exception 'El vencimiento de la inversion debe ser una fecha futura'
      using errcode = '22023';
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Resolver ANTES del lock del lead (orden identidad->lead, comparte orden con
  -- la fusión y mata el deadlock). El documento ya se validó arriba. Con bandera
  -- APAGADA nada de esto corre (comportamiento idéntico a hoy).
  if v_flag then
    v_inv := private.inversionista_resolver(p_documento_tipo, v_documento, true, 'conversion');
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b4): la PERSONA (no solo este lead) puede tener una conversión Avance en curso en OTRO
    -- lead: reserva viva o sellada con su inversionista_id. Lectura bajo el lock de la identidad
    -- (el sellado también lo toma desde b4): orden identidad -> lead -> reserva, sin cambios.
    if exists (select 1 from crm.conversion_reservas r
                where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                  and (r.efectos_iniciados_en is not null or r.expira_en > now())) then
      raise exception using
        errcode = 'P0409',
        message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
        hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
    end if;
  end if;

  -- Ámbito y lock: copiados VERBATIM de crm.convertir_lead para que los dos
  -- caminos de conversión signifiquen lo mismo.
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  -- Reintento tras éxito: el lead ya se convirtió y su cierre lleva ESTE número de
  -- operación -> mismo resultado, sin efectos (idempotente).
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock (Codex): la clave guardada manda; payload distinto → P0409.
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
    -- Sin clave guardada (p.ej. conversión previa a este lote): mismo número de
    -- operación en su cierre = mismo hecho.
    select ce.id into v_cierre_id
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id and ce.es_cierre_inicial
      and upper(ce.numero_transaccion) = upper(v_transaccion)
    limit 1;
    if v_cierre_id is not null then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'cierre_id', v_cierre_id,
                                             'cooperativa', p_cooperativa);
      perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
      return v_res || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- Un solo lead total (invariante #6, decisión Miguel 03/09): un 2.º lead de la
  -- misma persona no se convierte aquí; la nueva inversión sobre el cliente
  -- existente es F5. Mensaje de negocio en vez del choque con leads_inversionista_uidx.
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [Codex B2]: «un solo lead» cuenta también el PUENTE (históricos del backfill sin enlace vivo).
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento del cierre
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;

  -- LA CARRERA (ver sección 1-bis): si hay una conversión Avance en vuelo, sus
  -- efectos irreversibles —usuario de Auth, perfil, correo de bienvenida— ya
  -- pueden haber ocurrido, y cerrar aquí dejaría a un inversionista de
  -- cooperativa con cuenta de portal. Se rechaza SIN MIRAR QUIÉN reservó: lo que
  -- importa no es el actor, es que el correo quizá ya salió.
  -- Dos casos, y solo uno se cura esperando.
  --
  -- ⚠️ `for update` y NO una lectura suelta. En READ COMMITTED un SELECT normal
  -- ve la última versión CONFIRMADA: si la edge está sellando la reserva en ese
  -- mismo instante (su UPDATE aún sin confirmar), este cierre vería la versión
  -- vieja —caducada y sin efectos—, entraría, y acto seguido la edge crearía la
  -- cuenta de portal. Ventana de milisegundos, pero es EXACTAMENTE el fallo que
  -- toda esta tabla existe para impedir. Con el lock, este cierre espera al
  -- sellado y decide DESPUÉS, sobre el estado real.
  --
  -- El orden de bloqueo es el mismo en los dos caminos —primero `crm.leads`
  -- (arriba), luego `crm.conversion_reservas`— para que no puedan abrazarse.
  -- Sin `and (expira_en > now() …)` en el WHERE: primero se toma la fila, y la
  -- vigencia se juzga con lo que haya tras esperar.
  select r.expira_en, r.efectos_iniciados_en into v_reserva, v_efectos
  from crm.conversion_reservas r
  where r.lead_id = p_lead_id
  for update;
  if v_efectos is null and coalesce(v_reserva, '-infinity'::timestamptz) <= now() then
    -- Caducada y sin efectos: no manda.
    v_reserva := null;
  end if;
  if v_efectos is not null then
    -- Ya existe una cuenta de portal a nombre de esta persona. Este cierre NO
    -- puede entrar nunca: sería justo el inversionista de cooperativa con
    -- portal que toda esta función existe para impedir.
    raise exception using
      errcode = 'P0409',
      message = 'Esta persona ya tiene una cuenta de cliente de Avance en proceso',
      hint    = 'Se le creo (o se le esta creando) su acceso al portal. Termina esa conversion; este lead ya no se puede cerrar en una cooperativa.';
  end if;
  if v_reserva is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Hay una conversion a cliente de Avance en curso para este lead',
      hint    = pg_catalog.format(
        'Vuelve a intentarlo despues de las %s (hora de Lima). Si esa conversion no debia hacerse, avisa antes de cerrar en la cooperativa.',
        pg_catalog.to_char(v_reserva at time zone 'America/Lima', 'HH24:MI'));
  end if;

  -- La FOTO primero: así, cuando el UPDATE de etapa dispare el BEFORE trigger,
  -- la P4 relajada ya encuentra el cierre y deja pasar el convertido sin
  -- perfil. El UNIQUE(lead_id) es el cinturón contra un doble cierre que el
  -- gate de etapa no haya visto (el FOR UPDATE ya serializa el camino normal).
  begin
    insert into crm.cierres_externos (
      lead_id, cooperativa, monto, moneda,
      documento_tipo, documento, nombre_completo,
      numero_transaccion, referencia_externa, vence_en, nota,
      vendedor_id, creado_por, inversionista_id
    ) values (
      p_lead_id, p_cooperativa, p_monto, p_moneda,
      p_documento_tipo, v_documento, v_nombre,
      v_transaccion, v_referencia, p_vence_en, nullif(btrim(p_nota), ''),
      v_lead.vendedor_id, v_uid, v_inv
    )
    returning id into v_cierre_id;

    -- La reclamación es PARTE del mismo insert: si el número ya se declaró
    -- alguna vez —aunque su cierre se haya corregido después y el índice vivo
    -- lo haya soltado— este insert choca y el cierre entero se deshace.
    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
    values (upper(v_transaccion), v_cierre_id, v_uid);
  exception when unique_violation then
    -- El índice habla en idioma de constraint; el vendedor merece saber QUÉ
    -- pasó. El UNIQUE del lead ya lo cazó el gate de etapa más arriba, así que
    -- aquí el choque es el del depósito (vivo o histórico).
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes, aqui o en la otra cooperativa. Si lo escribiste mal, corrigelo; si es otro cierre, usa su propio numero de operacion.';
  end;

  -- El cierre del lead, IDÉNTICO al de convertir_lead salvo que perfil_id
  -- queda NULL (no hay portal). El AFTER trg_leads_asignaciones cierra el
  -- episodio con resultado='convertido' — por eso la conversión mensual cuenta
  -- este cierre sin tocar su fórmula.
  -- Inversión (colgada de la identidad) + titular principal (solo bandera).
  -- F2.b (b4) [Codex v2 #17]: los HECHOS de inversión son de F4: solo con `inversiones_escritura`.
  if v_flag and v_inv is not null and v_escribe_inversion then
    perform private.inversion_vincular_fuente(v_inv,null,v_cierre_id,v_uid,true);
  end if;

  -- El cierre del lead. inversionista_id viaja en el MISMO UPDATE bajo la válvula.
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         convertido_en = now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Reconocimiento de identidad (reemplaza al trigger 200000 para coop).
  if v_flag and v_inv is not null then
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);
    -- Responsable de relación = vendedor del cierre (si activo y sin tramo abierto).
    if v_lead.vendedor_id is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_lead.vendedor_id and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_lead.vendedor_id, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_lead.vendedor_id
        where id = v_inv and responsable_relacion_id is null;
    end if;
    -- no_contactar del lead se centraliza en la persona.
    if v_lead.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido en ' || case p_cooperativa
      when 'qorilazo' then 'COOPAC Qorilazo'
      else 'COOPAC Prodelco'
    end,
    jsonb_build_object(
      'cooperativa', p_cooperativa,
      'monto', p_monto,
      'moneda', p_moneda,
      'cierre_externo_id', v_cierre_id
    ),
    v_uid
  );

  v_res := jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'cierre_id', v_cierre_id,
    'cooperativa', p_cooperativa
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$;
-- Adaptación acotada de public.crear_contrato(jsonb, jsonb); antes 1cd2730dc75c966cfbd9ea8d95d4d1ed
CREATE OR REPLACE FUNCTION public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
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
  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF
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
$function$;
-- Adaptación acotada de crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb); antes 79d9d316203ce217456a7d00f834c584
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

    if length(v_banco) not between 1 and 100 then
      raise exception using errcode = '22023', message = 'Selecciona el banco de la cuenta';
    end if;
    if v_tipo_cuenta not in ('ahorros', 'corriente') then
      raise exception using errcode = '22023', message = 'Selecciona un tipo de cuenta valido';
    end if;
    if v_numero_cuenta !~ '^[A-Za-z0-9-]{1,30}$' then
      raise exception using errcode = '22023', message = 'El numero de cuenta solo puede contener letras, numeros y guiones';
    end if;
    if v_cci !~ '^[0-9]{20}$' then
      raise exception using errcode = '22023', message = 'El CCI debe tener exactamente 20 digitos';
    end if;
    if v_titular_distinto and (
      length(v_beneficiario_nombre) not between 1 and 200
      or v_beneficiario_dni !~ '^[0-9]{8,12}$'
    ) then
      raise exception using errcode = '22023', message = 'Completa correctamente los datos del beneficiario';
    end if;

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
-- Adaptación acotada de crm.crear_contrato_con_cuenta_pdf_v2(jsonb, jsonb, jsonb); antes 9833ed526e733dc8af6ca78e5c85c7ca
CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
  v_huella text;
  v_huella_previa text;
begin
  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    -- La huella de LO QUE SE PIDE (sin la clave): la misma clave solo vale para la
    -- misma solicitud. jsonb::text es canónico (claves ordenadas), así que dos
    -- envíos iguales dan la misma huella.
    v_huella := md5(
      (p_contrato - 'clave_idempotencia')::text || '|'
      || coalesce(p_cronograma::text, '') || '|'
      || coalesce(p_cuenta::text, '')
    );
    select a.respuesta, a.contrato_id, a.huella
      into v_resultado, v_contrato_id, v_huella_previa
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El replay pasa por la MISMA autorización que el alta (Codex 05/09): una
      -- membresía revocada o un contrato fuera de cartera no recuperan nada.
      if not (select private.puede_registrar_ventas()) then
        raise insufficient_privilege using
          message = 'Cliente no encontrado o fuera de tu cartera';
      end if;
      -- Lápida: el contrato de este intento fue eliminado después (FK SET NULL).
      -- Un reintento tardío NO recrea lo que Gerencia borró a propósito.
      if v_contrato_id is null then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end if;
      -- Misma fila que bloquea la puerta de eliminación: replay y borrado se
      -- serializan. Si el contrato desaparece mientras esperamos, es lápida.
      begin
        perform private.bloquear_fila_contrato_pdf(v_contrato_id);
      exception when sqlstate 'P0002' then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
        raise insufficient_privilege using
          message = 'Contrato no encontrado o fuera de tu cartera';
      end if;
      -- Misma clave pero OTROS datos (el analista editó el formulario tras un
      -- intento que SÍ creó el contrato): no se devuelve el viejo como si fuera
      -- el nuevo ni se crea otro. Se le dice la verdad, con el número.
      if v_huella_previa is distinct from v_huella then
        raise exception 'Este intento ya creó el contrato % con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
          coalesce(v_resultado->>'numero_contrato', v_contrato_id::text)
          using errcode = 'P0409',
                hint = 'ALTA_YA_CREADA_CON_OTROS_DATOS',
                detail = jsonb_build_object(
                  'contrato_id', v_contrato_id,
                  'numero_contrato', v_resultado->>'numero_contrato'
                )::text;
      end if;
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  if private.inversiones_escritura_bajo_candado() then
    perform private.inversion_cotitulares_vincular(
      (select id from crm.inversiones where contrato_id=v_contrato_id),'alta');
  end if;
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
end;
$function$;
create or replace function private.f4_sincronizar_cierre()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_inversion uuid;
begin
  update crm.inversiones i set empresa_id=e.id,
    estado=case when new.anulado_en is null then 'vigente' else 'anulada' end
  from crm.empresas e where i.cierre_externo_id=new.id and e.clave=new.cooperativa
  returning i.id into v_inversion;
  if v_inversion is not null and not new.es_cierre_inicial then
    insert into crm.inversion_eventos(inversion_id,tipo,motivo,creado_por)
    values(v_inversion,
      case when old.anulado_en is null and new.anulado_en is not null then 'anulacion' else 'correccion' end,
      case when old.anulado_en is null and new.anulado_en is not null then new.motivo_anulacion else 'Corrección de cierre externo' end,
      (select auth.uid()));
  end if;
  return new;
end;
$$;
revoke all on function private.f4_sincronizar_cierre() from public,anon,authenticated,service_role;
create trigger trg_cierres_f4_sincronizar after update of monto,moneda,cooperativa,
  numero_transaccion,referencia_externa,vence_en,nota,anulado_en on crm.cierres_externos
  for each row execute function private.f4_sincronizar_cierre();

-- Solo después de adaptar los lectores en la MISMA transacción puede dejar de
-- ser única la relación económica. La conversión inicial continúa siendo única.
alter table crm.cierres_externos drop constraint cierres_externos_un_cierre_por_lead;
create unique index cierres_externos_inicial_por_lead_uidx
  on crm.cierres_externos(lead_id) where es_cierre_inicial;
create index cierres_externos_lead_idx on crm.cierres_externos(lead_id);
create index cierres_externos_comprobante_idx on crm.cierres_externos(comprobante_objeto_id);
create index cierres_externos_fecha_imputacion_idx on crm.cierres_externos(fecha_imputacion)
  where fecha_imputacion is not null;

-- Las puertas Avance conservan su autoridad y cálculo. Estos observadores
-- completan el enlace relacional en la misma transacción de TODAS las altas.
create or replace function private.f4_contrato_reconocer()
returns trigger language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
begin
  if private.inversiones_escritura_bajo_candado() then
    perform private.asegurar_identidad_perfil(new.cliente_id,'contrato');
  end if;
  return new;
end;
$$;
revoke all on function private.f4_contrato_reconocer() from public,anon,authenticated,service_role;
create trigger trg_contratos_000_f4_reconocer before insert on public.contratos
  for each row execute function private.f4_contrato_reconocer();

create or replace function private.f4_contrato_vincular()
returns trigger language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_persona uuid;
begin
  if private.inversiones_escritura_bajo_candado() then
    select id into v_persona from crm.inversionistas
    where perfil_id=new.cliente_id and estado<>'fusionado';
    if v_persona is null then raise exception 'F4: falta la identidad del contrato' using errcode='P0409'; end if;
    perform private.inversion_vincular_fuente(v_persona,new.id,null,new.creado_por,false);
  end if;
  return new;
end;
$$;
revoke all on function private.f4_contrato_vincular() from public,anon,authenticated,service_role;
create trigger trg_contratos_f4_vincular after insert on public.contratos
  for each row execute function private.f4_contrato_vincular();

-- La inversión conserva su solicitud mientras Auth avanza en el servicio externo.
-- Reutiliza el claim global de F3, su marca de servidor, token, versión y lease.
-- Ningún paso recibe documento, asesor, claim ni perfil elegidos por el cliente.
create or replace function crm.acceso_inversion_fn(p_solicitud uuid,p_paso text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_datos jsonb;
  v_auth_ctx jsonb;
  v_hash_payload jsonb;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_r jsonb;
  v_p public.perfiles%rowtype;
  v_auth uuid;
  v_version integer;
  v_token text;
  v_otras uuid[];
begin
  if p_solicitud is null or p_paso is null or p_paso not in ('reclamar','registrar_auth','crear_perfil','enlazar')
     or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'Solicitud o paso de acceso Avance inválido' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_payload) k where
    k<>'token' and not (p_paso<>'reclamar' and k='version')
    and not (p_paso='registrar_auth' and k='auth_user_id')) then
    raise exception 'El paso de acceso contiene campos no admitidos' using errcode='22023';
  end if;
  v_token:=p_payload->>'token';
  if v_token is not null and v_token !~ '^[a-f0-9]{48}$' then
    raise exception 'Token de recuperación inválido' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_autorizada(v_persona);
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'confirmada' then
    v_ctx:=private.inversion_persona_contexto(v_persona);
  end if;
  if not exists(select 1 from crm.empresas e where e.id=v_s.empresa_id and e.clave='avance' and e.activa)
     or v_s.estado='cancelada' then
    raise exception 'Esta solicitud no permite completar acceso Avance' using errcode='P0409';
  end if;
  if v_s.estado='preparada' and v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; corresponde revisar esta solicitud antes de continuar' using errcode='P0409';
  end if;

  -- Un claim terminal conserva su clave de origen después de una fusión.
  -- Los contextos anteriores a esta ampliación usaban la persona de la solicitud.
  select * into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
    case when v_s.auth_claim_id is null then v_persona::text
      else coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text) end;
  if v_s.auth_claim_id is not null and
    (v_saga.clave is null or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text) then
    raise exception 'El proceso de acceso original requiere conciliación' using errcode='P0409';
  end if;
  -- Un enlace concluido se devuelve aunque se perdiera su respuesta. No reinicia
  -- Auth ni reescribe el perfil, su clave o su responsable.
  if v_ctx->>'perfil_id' is not null and
     (v_saga.clave is null or v_saga.resultado->>'estado'='enlazado') then
    if v_saga.clave is not null and v_saga.resultado->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El acceso y la identidad requieren conciliación' using errcode='P0409';
    end if;
    return jsonb_build_object('estado','enlazado','perfil_id',v_ctx->>'perfil_id',
      'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
  end if;
  if v_s.estado='confirmada' then
    raise exception 'El acceso de la inversión confirmada requiere conciliación' using errcode='P0409';
  end if;
  v_datos:=private.inversion_datos_portal(v_s.datos->'alta_portal');
  v_auth_ctx:=coalesce(v_s.auth_contexto,jsonb_build_object('documento_tipo',v_ctx->>'documento_tipo',
    'documento',v_ctx->>'documento','responsable_id',v_ctx->>'responsable_id','inversionista_id',v_persona));
  if v_auth_ctx->>'documento_tipo' is distinct from v_ctx->>'documento_tipo'
     or v_auth_ctx->>'documento' is distinct from v_ctx->>'documento' then
    raise exception 'El documento cambió durante el alta; corresponde revisar el acceso pendiente' using errcode='P0409';
  end if;
  -- Misma proyección que alta_cliente_identidad_fn; los bancos pertenecen a la
  -- cuenta contractual de esta inversión. El responsable inicial fija la huella.
  v_hash_payload:=jsonb_build_object('v',1,'inv',v_persona,'correo',v_datos->>'correo',
    'nombre',v_datos->>'nombre_completo','apellidos',coalesce(v_datos->>'apellidos',''),
    'nombres',coalesce(v_datos->>'nombres',''),'telefono',coalesce(v_datos->>'telefono',''),
    'domicilio',v_datos->'domicilio','bancarios','null'::jsonb,'asesor',v_auth_ctx->>'responsable_id');

  if p_paso='reclamar' then
    -- Una segunda solicitud no sustituye un alta pendiente de esta persona.
    -- Incluso "reclamado" puede tener Auth creado con respuesta perdida.
    if v_saga.clave is not null and v_saga.resultado->>'estado'<>'enlazado' then
      if exists(select 1 from crm.inversion_solicitudes s where s.id<>v_s.id
        and s.auth_claim_id=(v_saga.resultado->>'claim_id')::uuid) then
        raise exception 'Completa el acceso pendiente desde su solicitud original' using errcode='P0409';
      end if;
      if v_saga.hash_payload is distinct from private.idem_hash(v_hash_payload) then
        raise exception 'La persona tiene otro alta pendiente; recupera ese proceso con sus datos originales' using errcode='P0409';
      end if;
    end if;
    if v_saga.clave is null then
      select array_agg(p.id order by p.id) into v_otras from public.perfiles p
      where p.rol='cliente' and p.tipo_documento=v_ctx->>'documento_tipo'
        and upper(regexp_replace(coalesce(p.dni,''),'[^A-Za-z0-9]','','g'))=v_ctx->>'documento';
      if coalesce(cardinality(v_otras),0)>1 then
        raise exception 'Hay varios perfiles con ese documento; requiere conciliación' using errcode='P0409';
      elsif cardinality(v_otras)=1 then
        perform private.asegurar_identidad_perfil(v_otras[1],'f4_acceso_portal');
        v_ctx:=private.inversion_persona_contexto(v_persona);
        if v_ctx->>'perfil_id' is distinct from v_otras[1]::text then
          raise exception 'El perfil existente no pertenece a esta persona' using errcode='P0409';
        end if;
        return jsonb_build_object('estado','enlazado','perfil_id',v_otras[1],
          'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
      end if;
    end if;
    v_r:=private.saga_auth_reclamar(v_persona,'alta_cliente',v_hash_payload,null,v_token);
    if v_r->>'estado'='enlazado' and (v_ctx->>'perfil_id' is null
       or v_r->>'perfil_id' is distinct from v_ctx->>'perfil_id') then
      raise exception 'El perfil del acceso requiere conciliación con esta persona' using errcode='P0409';
    end if;
    if v_s.auth_claim_id is not null and v_s.auth_claim_id is distinct from (v_r->>'claim_id')::uuid then
      raise exception 'El proceso de acceso cambió; requiere revisión' using errcode='P0409';
    end if;
    update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,
      auth_contexto=v_auth_ctx,actualizado_en=statement_timestamp() where id=v_s.id;
    return v_r||jsonb_build_object('solicitud_id',v_s.id,'datos_portal',v_datos,
      'documento_tipo',v_auth_ctx->>'documento_tipo','documento',v_auth_ctx->>'documento');
  end if;

  if v_s.auth_claim_id is null or v_saga.clave is null
     or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text then
    raise exception 'Primero reclama el acceso desde esta solicitud' using errcode='P0409';
  end if;
  -- El perfil y el avance de estado se confirman juntos. Una versión antigua
  -- no puede dejar un perfil insertado ni enlazarlo por fuera de su claim.
  select * into v_saga from crm.multiempresa_idempotencia where clave=v_saga.clave for update;
  if v_token is null or v_saga.resultado->>'token_hash' is distinct from private.saga_token_hash(v_token) then
    raise exception 'Token de recuperación inválido' using errcode='42501';
  end if;
  begin v_version:=(p_payload->>'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Versión del acceso inválida' using errcode='22023';
  end;
  if v_version is null or v_saga.version is distinct from v_version then
    raise exception 'El acceso cambió; vuelve a reclamar con tu token' using errcode='40001';
  end if;
  if p_paso='registrar_auth' then
    begin v_auth:=(p_payload->>'auth_user_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Identificador de acceso inválido' using errcode='22023';
    end;
  else
    v_auth:=(v_saga.resultado->>'auth_user_id')::uuid;
  end if;
  if not exists(select 1 from auth.users u where u.id=v_auth
    and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
    and lower(u.email)=v_datos->>'correo') then
    raise exception 'El acceso no pertenece a esta solicitud o a su correo' using errcode='P0409';
  end if;
  if p_paso='registrar_auth' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'auth_creado',v_auth,null,v_version);
  end if;
  if v_saga.resultado->>'estado' not in ('auth_creado','perfil_creado') then
    raise exception 'El estado del acceso no permite este paso' using errcode='P0409';
  end if;
  select * into v_p from public.perfiles where id=v_auth for update;
  if not found and p_paso='crear_perfil' then
    insert into public.perfiles(id,rol,activo,nombre_completo,apellidos,nombres,tipo_documento,dni,
      correo,telefono,domicilio,asesor_perfil_id,creado_por,debe_cambiar_password)
    values(v_auth,'cliente',true,v_datos->>'nombre_completo',v_datos->>'apellidos',v_datos->>'nombres',
      v_auth_ctx->>'documento_tipo',v_auth_ctx->>'documento',v_datos->>'correo',v_datos->>'telefono',
      v_datos->>'domicilio',(v_ctx->>'responsable_id')::uuid,(select auth.uid()),true)
    returning * into v_p;
  end if;
  if v_p.id is null or v_p.rol<>'cliente' or v_p.activo is not true
     or v_p.tipo_documento is distinct from v_auth_ctx->>'documento_tipo'
     or v_p.dni is distinct from v_auth_ctx->>'documento'
     or lower(v_p.correo) is distinct from v_datos->>'correo'
     or v_p.asesor_perfil_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El perfil pendiente requiere conciliación con esta persona y su responsable' using errcode='P0409';
  end if;
  if p_paso='crear_perfil' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'perfil_creado',null,v_auth,v_version);
  end if;
  v_r:=private.asegurar_identidad_perfil(v_auth,'f4_acceso_portal');
  if private.inversionista_canonica((v_r->>'inversionista_id')::uuid) is distinct from v_persona then
    raise exception 'El perfil no corresponde a la persona de la inversión' using errcode='P0409';
  end if;
  return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'enlazado',null,v_auth,v_version)
    ||jsonb_build_object('solicitud_id',v_s.id);
end;
$$;
revoke all on function crm.acceso_inversion_fn(uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function crm.acceso_inversion_fn(uuid,text,jsonb) to authenticated;

-- Prueba acotada para el trigger de perfiles: solo permite alinear el asesor
-- con la persona durante la misma sentencia que registró una revisión F4.
-- Es INVOKER. El trigger la consulta únicamente desde el escritor postgres;
-- un UPDATE directo authenticated no puede abrir esta excepción con un GUC.
create or replace function private.f4_alineacion_perfil_permitida(p_perfil uuid,p_responsable uuid)
returns boolean language sql stable security invoker set search_path='' as $$
  select exists(
    select 1 from crm.inversion_solicitudes s
    join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    join crm.inversion_solicitud_revisiones r on r.solicitud_id=s.id
    where s.id=case when current_setting('crm.f4_revision_solicitud',true)
      ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
      then current_setting('crm.f4_revision_solicitud',true)::uuid else null end
      and s.estado='preparada' and s.responsable_esperado_id=p_responsable
      and i.estado='activo' and not i.no_contactar and i.responsable_relacion_id=p_responsable
      and r.revisado_por=(select auth.uid()) and r.transaccion=pg_current_xact_id()
      and r.responsable_nuevo_id=p_responsable
      and (i.perfil_id=p_perfil or (i.perfil_id is null and exists(
        select 1 from crm.multiempresa_idempotencia m join auth.users u
          on u.id=(m.resultado->>'auth_user_id')::uuid
        where m.clave='auth_persona:'||i.id::text
          and m.resultado->>'claim_id'=s.auth_claim_id::text
          and m.resultado->>'estado' in ('auth_creado','perfil_creado')
          and u.id=p_perfil and u.raw_app_meta_data->>'claim_id'=s.auth_claim_id::text
      )))
  );
$$;
revoke all on function private.f4_alineacion_perfil_permitida(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function crm.revisar_solicitud_inversion_fn(
  p_solicitud uuid,p_responsable_revisado uuid,p_revision_esperada integer,p_motivo text)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_revision crm.inversion_solicitud_revisiones%rowtype;
  v_num integer;
  v_motivo text:=btrim(p_motivo);
  v_perfil uuid;
  v_p public.perfiles%rowtype;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_config text:=current_setting('crm.f4_revision_solicitud',true);
begin
  if p_solicitud is null or p_responsable_revisado is null or p_revision_esperada is null or p_revision_esperada<0 then
    raise exception 'Falta la solicitud, el responsable revisado o su versión' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_contexto(v_persona);
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'preparada' then
    raise exception 'Solo se revisa el responsable de una solicitud pendiente; las inversiones confirmadas conservan su atribución' using errcode='P0409';
  end if;
  if p_responsable_revisado is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable actual ya no coincide con el que revisaste' using errcode='40001';
  end if;
  perform private.motivo_sin_documento(v_motivo,
    (select array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id=v_persona));
  select * into v_revision from crm.inversion_solicitud_revisiones r
    where r.solicitud_id=v_s.id order by r.revision desc limit 1;
  v_num:=coalesce(v_revision.revision,0);
  if p_revision_esperada<>v_num then
    if p_revision_esperada=v_num-1 and v_revision.responsable_nuevo_id=p_responsable_revisado
       and v_s.responsable_esperado_id=p_responsable_revisado and v_revision.motivo=v_motivo then
      return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',true);
    end if;
    raise exception 'La revisión cambió; vuelve a cargar la solicitud' using errcode='40001';
  end if;
  if v_s.responsable_esperado_id=p_responsable_revisado then
    return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('sin_cambios',true);
  end if;
  v_perfil:=(v_ctx->>'perfil_id')::uuid;
  if v_s.auth_claim_id is not null then
    select * into v_saga from crm.multiempresa_idempotencia m
      where m.clave='auth_persona:'||coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text)
        and m.resultado->>'claim_id'=v_s.auth_claim_id::text for update;
    if not found then raise exception 'El proceso de acceso requiere conciliación' using errcode='P0409'; end if;
    -- La corrección canónica solo se permite una vez enlazado el acceso. Su
    -- contexto original queda histórico y no impide revisar al nuevo equipo.
    if v_saga.resultado->>'estado'<>'enlazado' and not private.documento_es_de_identidad(
      v_persona,v_s.auth_contexto->>'documento_tipo',v_s.auth_contexto->>'documento') then
      raise exception 'El documento también cambió; revisa primero el acceso pendiente' using errcode='P0409';
    end if;
    if v_saga.resultado->>'auth_user_id' is not null then
      if not exists(select 1 from auth.users u where u.id=(v_saga.resultado->>'auth_user_id')::uuid
        and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
        raise exception 'El acceso pendiente no tiene la procedencia esperada' using errcode='P0409';
      end if;
      if v_perfil is not null and v_perfil is distinct from (v_saga.resultado->>'auth_user_id')::uuid then
        raise exception 'El perfil y el acceso pertenecen a procesos diferentes' using errcode='P0409';
      end if;
      select id into v_perfil from public.perfiles where id=(v_saga.resultado->>'auth_user_id')::uuid;
      if v_perfil is null and v_saga.resultado->>'estado' in ('perfil_creado','enlazado') then
        raise exception 'El perfil del proceso ya no existe; requiere revisión' using errcode='P0409';
      end if;
    end if;
  end if;
  if v_perfil is not null then
    -- La gestión de tareas puede tener ya una tarea/perfil. No esperar bajo el
    -- candado de persona: el intento se revierte entero y se puede repetir.
    begin
      perform 1 from crm.tareas t where t.perfil_id=v_perfil and t.estado='pendiente'
        order by t.id for update nowait;
      select * into v_p from public.perfiles where id=v_perfil for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando la ficha o sus tareas; vuelve a revisar' using errcode='40001';
    end;
    if not found or v_p.rol<>'cliente' or v_p.activo is not true
       or not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
      raise exception 'El perfil requiere conciliación con esta persona' using errcode='P0409';
    end if;
  end if;

  insert into crm.inversion_solicitud_revisiones(solicitud_id,revision,responsable_anterior_id,
    responsable_nuevo_id,motivo,revisado_por)
  values(v_s.id,v_num+1,v_s.responsable_esperado_id,p_responsable_revisado,v_motivo,(select auth.uid()));
  update crm.inversion_solicitudes set responsable_esperado_id=p_responsable_revisado,
    actualizado_en=statement_timestamp() where id=v_s.id;
  if v_perfil is not null and v_p.asesor_perfil_id is distinct from p_responsable_revisado then
    perform set_config('crm.f4_revision_solicitud',v_s.id::text,true);
    begin
      update public.perfiles set asesor_perfil_id=p_responsable_revisado where id=v_perfil;
      if (select asesor_perfil_id from public.perfiles where id=v_perfil) is distinct from p_responsable_revisado then
        raise exception 'El perfil no pudo alinearse con su responsable actual' using errcode='P0409';
      end if;
    exception when others then
      perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
      raise;
    end;
    perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
  end if;
  -- No cambia datos/hash/auth_contexto ni token/versión/lease de la saga.
  return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',false);
end;
$$;
revoke all on function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) to authenticated;

-- Continuación F4. Integrada en la candidata; sin ejecución productiva.
-- Previsualización administrativa: no crea identidades, no modifica fuentes ni
-- documentos, no asigna responsables. El escritor del lote se construye aparte.
create or replace function private.inversion_historica_estado(p_tipo text,p_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  v_c public.contratos%rowtype;
  v_ce crm.cierres_externos%rowtype;
  v_p public.perfiles%rowtype;
  v_l crm.leads%rowtype;
  v_i crm.inversionistas%rowtype;
  v_inv crm.inversiones%rowtype;
  v_tit crm.inversion_titulares%rowtype;
  v_empresa uuid;
  v_persona uuid;
  v_perfil uuid;
  v_documento uuid;
  v_indicios uuid[] := '{}';
  v_mapa jsonb;
  v_fuente jsonb;
  v_datos_identidad jsonb;
  v_estado text := 'pendiente';
  v_motivos text[] := '{}';
  v_demo boolean := false;
  v_estado_economico text;
  v_fecha date;
  v_inicial boolean;
  v_creado_por uuid;
  v_eliminacion boolean := false;
  v_n integer;
begin
  if p_tipo is null or p_tipo not in ('contrato','cierre') or p_id is null then
    raise exception 'Indica una fuente contractual o cooperativa concreta' using errcode='22023';
  end if;
  if p_tipo='contrato' then
    select * into v_c from public.contratos where id=p_id;
    if not found then
      return jsonb_build_object('tipo',p_tipo,'id',p_id,'estado','ausente');
    end if;
    v_fuente:=to_jsonb(v_c);
    v_demo:=v_c.es_demo;
    v_fecha:=v_c.fecha_cierre_comercial;
    v_estado_economico:='vigente'; -- El ciclo del contrato continúa en su fuente.
    v_inicial:=false;
    v_creado_por:=v_c.creado_por;
    v_eliminacion:=private.contrato_en_eliminacion(p_id);
    select id into v_empresa from crm.empresas where clave='avance';
    select * into v_p from public.perfiles where id=v_c.cliente_id;
    select id into v_perfil from crm.inversionistas
      where perfil_id=v_c.cliente_id and estado<>'fusionado';
    -- El documento se lee por el mismo reconocedor privado vigente de F3.
    v_documento:=private.inversionista_por_documento(v_p.tipo_documento,v_p.dni);
    v_indicios:=array[v_perfil,v_documento];
    if v_p.rol is distinct from 'cliente' then
      v_motivos:=array_append(v_motivos,'perfil_no_cliente');
    end if;
    if v_perfil is null then
      v_motivos:=array_append(v_motivos,'perfil_sin_vinculo_canonico');
    elsif not private.documento_es_de_identidad(v_perfil,v_p.tipo_documento,v_p.dni) then
      v_motivos:=array_append(v_motivos,'documento_perfil_no_conciliado');
    end if;
    select to_jsonb(m) into v_mapa from crm.backfill_multiempresa_mapa m
      where fuente='perfil' and fila_id=v_c.cliente_id;
    select * into v_inv from crm.inversiones where contrato_id=p_id;
  else
    select * into v_ce from crm.cierres_externos where id=p_id;
    if not found then
      return jsonb_build_object('tipo',p_tipo,'id',p_id,'estado','ausente');
    end if;
    v_fuente:=to_jsonb(v_ce);
    -- Exclusión duradera publicada por F2 para el antecedente demo de cooperativa.
    v_demo:=v_ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid;
    v_fecha:=coalesce(v_ce.fecha_comercial,(v_ce.creado_en at time zone 'America/Lima')::date);
    v_estado_economico:=case when v_ce.anulado_en is null then 'vigente' else 'anulada' end;
    v_inicial:=v_ce.es_cierre_inicial;
    v_creado_por:=v_ce.creado_por;
    select id into v_empresa from crm.empresas where clave=v_ce.cooperativa;
    select * into v_l from crm.leads where id=v_ce.lead_id;
    select to_jsonb(m) into v_mapa from crm.backfill_multiempresa_mapa m
      where fuente='cierre' and fila_id=p_id;
    v_indicios:=array[v_ce.inversionista_id,v_l.inversionista_id];
    -- Una fotografía documental antigua no deshace un vínculo autorizado.
    -- Si la fuente no tiene persona, el documento sí debe resolver de forma
    -- inequívoca y coincidir con los vínculos de lead/mapa que ya existan.
    if v_ce.inversionista_id is null then
      v_documento:=private.inversionista_por_documento(v_ce.documento_tipo,v_ce.documento);
      v_indicios:=array_append(v_indicios,v_documento);
      if v_documento is null then
        v_motivos:=array_append(v_motivos,'documento_sin_identidad_verificada');
      end if;
    end if;
    if v_l.perfil_id is not null then
      select id into v_perfil from crm.inversionistas
        where perfil_id=v_l.perfil_id and estado<>'fusionado';
      v_indicios:=array_append(v_indicios,v_perfil);
    end if;
    select * into v_inv from crm.inversiones where cierre_externo_id=p_id;
  end if;

  if v_mapa->>'inversionista_id' is not null and v_mapa->>'clase'<>'E' then
    v_indicios:=array_append(v_indicios,(v_mapa->>'inversionista_id')::uuid);
  end if;
  select coalesce(array_agg(distinct private.inversionista_canonica(x)
    order by private.inversionista_canonica(x)),'{}') into v_indicios
    from unnest(v_indicios) x where x is not null;
  if cardinality(v_indicios)<>1 then
    v_motivos:=array_append(v_motivos,case when cardinality(v_indicios)=0
      then 'sin_identidad_inequivoca' else 'identidades_en_conflicto' end);
  else
    v_persona:=v_indicios[1];
    select * into v_i from crm.inversionistas where id=v_persona;
    if v_i.id is null or v_i.estado='fusionado' then
      v_motivos:=array_append(v_motivos,'identidad_no_canonica');
    end if;
    if not exists (select 1 from crm.inversionista_identificadores d
      where d.inversionista_id=v_persona and d.estado='vigente' and d.verificado) then
      v_motivos:=array_append(v_motivos,'identidad_sin_documento_verificado');
    end if;
  end if;
  if v_empresa is null then v_motivos:=array_append(v_motivos,'empresa_desconocida'); end if;
  if v_eliminacion then v_motivos:=array_append(v_motivos,'contrato_en_eliminacion'); end if;

  select count(*) into v_n from crm.inversion_titulares
    where inversion_id=v_inv.id and rol='principal';
  if v_n=1 then
    select * into v_tit from crm.inversion_titulares
      where inversion_id=v_inv.id and rol='principal';
  end if;
  if v_inv.id is not null then
    if v_inv.inversionista_id is distinct from v_persona
       or v_inv.empresa_id is distinct from v_empresa
       or v_inv.estado is distinct from v_estado_economico
       or v_inv.fecha_comercial is distinct from v_fecha then
      v_motivos:=array_append(v_motivos,'inversion_no_conciliada');
    end if;
    if v_n>1 or (v_n=1 and v_tit.inversionista_id is distinct from v_persona) then
      v_motivos:=array_append(v_motivos,'titular_no_conciliado');
    end if;
    v_estado:=case when v_n=1 then 'resuelto' else 'titular_pendiente' end;
  end if;
  if cardinality(v_motivos)>0 then v_estado:='revision'; end if;
  if v_demo then v_estado:='excluido_demo'; end if;

  -- La huella detecta deriva de fuente, vínculos, mapa, identidad y documentos.
  -- El informe entrega solo referencias y huellas; no copia cifras ni documentos.
  select coalesce(jsonb_agg(jsonb_build_object('persona',to_jsonb(i),
    'documentos',(select coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]')
      from crm.inversionista_identificadores d where d.inversionista_id=i.id)) order by i.id),'[]')
    into v_datos_identidad from crm.inversionistas i where i.id=any(v_indicios);
  return jsonb_build_object('tipo',p_tipo,'id',p_id,'estado',v_estado,
    'motivos',v_motivos,'persona',v_persona,'empresa',v_empresa,
    'indicios',v_indicios,'inversion',v_inv.id,'titular',v_tit.id,
    'fuente_persona',case when p_tipo='cierre' then v_ce.inversionista_id else v_perfil end,
    'perfil',case when p_tipo='contrato' then v_c.cliente_id else v_l.perfil_id end,
    'lead',v_ce.lead_id,'fecha',v_fecha,'estado_economico',v_estado_economico,
    'inicial',v_inicial,'creado_por',v_creado_por,
    'huella',private.idem_hash(jsonb_build_object('fuente',v_fuente,'perfil',to_jsonb(v_p),
      'lead',to_jsonb(v_l),'identidades',v_datos_identidad,'mapa',v_mapa,
      'inversion',to_jsonb(v_inv),'titulares',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')
        from crm.inversion_titulares t where t.inversion_id=v_inv.id),'eliminacion',v_eliminacion)));
end;
$$;
revoke all on function private.inversion_historica_estado(text,uuid) from public,anon,authenticated,service_role;

-- Mantenimiento administrativo F4: aplicar exclusivamente un censo concreto.
-- Requiere 07-historicos.sql. Instalar no aplica ningún lote ni enciende banderas.
create table crm.inversion_backfill_lotes (
  id uuid primary key,
  hash_mapa text not null check (hash_mapa ~ '^[a-f0-9]{64}$'),
  mapa jsonb not null check (jsonb_typeof(mapa)='array'),
  resultado jsonb,
  operador name not null default session_user,
  creado_xid xid8 not null default pg_current_xact_id(),
  creado_en timestamptz not null default statement_timestamp(),
  finalizado_en timestamptz,
  check ((resultado is null)=(finalizado_en is null)),
  check (resultado is null or jsonb_typeof(resultado)='object')
);
comment on table crm.inversion_backfill_lotes is
  'Lotes acotados de vinculación histórica F4: mapa previo, huellas y resultado. No copia dinero ni documentos. Un lote completo es inmutable y no amplía permisos de usuario.';
alter table crm.inversion_backfill_lotes enable row level security;
revoke all on crm.inversion_backfill_lotes from public,anon,authenticated,service_role;
create trigger trg_audit_inversion_backfill_lotes after insert or update on crm.inversion_backfill_lotes
  for each row execute function private.log_audit_sin_secretos('mapa','resultado');

create or replace function private.f4_proteger_lote_historico()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if tg_when='AFTER' then
    if exists (select 1 from crm.inversion_backfill_lotes l where l.id=new.id and l.finalizado_en is null) then
      raise exception 'Un lote histórico no puede quedar incompleto' using errcode='23514';
    end if;
    return null;
  end if;
  if tg_op='DELETE' or old.finalizado_en is not null
     or old.creado_xid<>pg_current_xact_id() then
    raise exception 'El acta histórica se conserva íntegra' using errcode='P0409';
  end if;
  if (to_jsonb(new)-array['resultado','finalizado_en'])
       is distinct from (to_jsonb(old)-array['resultado','finalizado_en'])
     or new.finalizado_en is null or new.resultado is null then
    raise exception 'Solo puede concluirse el lote de esta transacción' using errcode='P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.f4_proteger_lote_historico() from public,anon,authenticated,service_role;
create trigger trg_inversion_backfill_inmutable before update or delete on crm.inversion_backfill_lotes
  for each row execute function private.f4_proteger_lote_historico();
create constraint trigger trg_inversion_backfill_completo after insert or update on crm.inversion_backfill_lotes
  deferrable initially deferred for each row execute function private.f4_proteger_lote_historico();

create or replace function private.inversion_historica_aplicar(p_lote uuid,p_mapa jsonb)
returns jsonb language plpgsql security invoker set search_path='' set lock_timeout='5s' as $$
declare
  v_mapa jsonb;
  v_hash text;
  v_previo crm.inversion_backfill_lotes%rowtype;
  v_r record;
  v_actual jsonb;
  v_final jsonb;
  v_inversion uuid;
  v_resultado jsonb;
  v_filas jsonb := '[]';
  v_n integer;
  v_personas uuid[];
  v_perfiles uuid[];
  v_leads uuid[];
  v_contratos uuid[];
  v_cierres uuid[];
  v_inversiones uuid[];
  v_old_priv text := current_setting('crm.op_privilegiada',true);
begin
  -- Mantenimiento por conexión administrativa, nunca una puerta HTTP ni una
  -- delegación implícita de service_role. INVOKER mantiene los privilegios reales.
  if session_user not in ('postgres','supabase_admin') or current_user<>'postgres' then
    raise exception 'La vinculación histórica exige una sesión administrativa' using errcode='42501';
  end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'El lote histórico exige READ COMMITTED' using errcode='0A000';
  end if;
  if p_lote is null or jsonb_typeof(p_mapa) is distinct from 'array' then
    raise exception 'Indica lote y previsualización completos' using errcode='22023';
  end if;
  if jsonb_array_length(p_mapa)<1 or jsonb_array_length(p_mapa)>100 then
    raise exception 'El lote admite entre una y cien fuentes concretas' using errcode='22023';
  end if;
  select jsonb_agg(value order by value->>'tipo',value->>'id'),
    count(distinct (value->>'tipo',value->>'id')) into v_mapa,v_n
    from jsonb_array_elements(p_mapa);
  if v_n<>jsonb_array_length(p_mapa) then
    raise exception 'Una fuente no se repite dentro del lote' using errcode='22023';
  end if;
  v_hash:=private.idem_hash(v_mapa);

  -- Ventana breve y explícita de mantenimiento. El orden coincide con el
  -- protocolo de banderas: identidad -> inversión. No se cambia ninguna bandera.
  -- El exclusivo de identidad drena sus escritores antes de fijar la foto; las
  -- correcciones financieras que no lo usan se arbitran con locks NOWAIT abajo.
  perform pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'La identidad debe estar encendida para vincular sus fuentes' using errcode='P0409';
  end if;
  if private.inversiones_escritura_bajo_candado() then
    raise exception 'Apaga el escritor de inversiones antes del lote histórico' using errcode='P0409';
  end if;
  select * into v_previo from crm.inversion_backfill_lotes where id=p_lote;
  if found then
    if v_previo.hash_mapa<>v_hash then
      raise exception 'El lote ya corresponde a otra previsualización' using errcode='P0409';
    end if;
    if v_previo.finalizado_en is null then
      raise exception 'Lote histórico incoherente: requiere revisión' using errcode='P0409';
    end if;
    return v_previo.resultado;
  end if;

  -- El mantenimiento F2 legado no participa en las banderas de identidad.
  -- Bloquear filas existentes no cubre un mapa todavía ausente: SHARE fija
  -- también ese conjunto frente a INSERT/UPDATE/DELETE hasta COMMIT. NOWAIT
  -- rechaza otra intervención administrativa sin crear un ciclo de espera.
  lock table crm.backfill_multiempresa_mapa in share mode nowait;

  -- Revalidar referencias antes de usarlas para bloquear; nunca confiar en los
  -- IDs de persona/empresa o en el estado que envíe el consumidor del censo.
  for v_r in select value from jsonb_array_elements(v_mapa) loop
    v_actual:=private.inversion_historica_estado(v_r.value->>'tipo',(v_r.value->>'id')::uuid);
    if v_actual is distinct from v_r.value then
      raise exception 'La previsualización histórica cambió; repite el censo' using errcode='40001';
    end if;
    if v_actual->>'estado' not in ('pendiente','titular_pendiente','resuelto') then
      raise exception 'El lote contiene una fuente que requiere revisión o está excluida' using errcode='P0409';
    end if;
  end loop;
  select array_agg(distinct (value->>'persona')::uuid),
    array_agg(distinct (value->>'perfil')::uuid),array_agg(distinct (value->>'lead')::uuid),
    array_agg((value->>'id')::uuid) filter(where value->>'tipo'='contrato'),
    array_agg((value->>'id')::uuid) filter(where value->>'tipo'='cierre'),
    array_agg(distinct (value->>'inversion')::uuid)
    into v_personas,v_perfiles,v_leads,v_contratos,v_cierres,v_inversiones
    from jsonb_array_elements(v_mapa);
  perform 1 from crm.inversionistas where id=any(v_personas) order by id for update nowait;
  perform 1 from public.perfiles where id=any(v_perfiles) order by id for share nowait;
  perform 1 from crm.cierres_externos where id=any(v_cierres) order by id for update nowait;
  perform 1 from public.contratos where id=any(v_contratos) order by id for update nowait;
  perform 1 from crm.inversiones where id=any(v_inversiones) order by id for update nowait;
  perform 1 from crm.inversion_titulares where inversion_id=any(v_inversiones) order by id for update nowait;
  perform 1 from crm.leads where id=any(v_leads) order by id for share nowait;
  for v_r in select value from jsonb_array_elements(v_mapa) loop
    if private.inversion_historica_estado(v_r.value->>'tipo',(v_r.value->>'id')::uuid)
       is distinct from v_r.value then
      raise exception 'La fuente histórica cambió mientras se bloqueaba; repite el censo' using errcode='40001';
    end if;
  end loop;

  -- Acta ANTES de enlazar. Si cualquier paso falla, PostgreSQL revierte acta y
  -- enlaces; la restricción diferida impide confirmar un acta inconclusa.
  insert into crm.inversion_backfill_lotes(id,hash_mapa,mapa) values(p_lote,v_hash,v_mapa);
  for v_r in select value from jsonb_array_elements(v_mapa) loop
    v_actual:=v_r.value;
    if v_actual->>'estado'<>'resuelto' then
      if v_actual->>'tipo'='cierre' and v_actual->>'fuente_persona' is null then
        perform set_config('crm.op_privilegiada','on',true);
        update crm.cierres_externos set inversionista_id=(v_actual->>'persona')::uuid
          where id=(v_actual->>'id')::uuid and inversionista_id is null;
        get diagnostics v_n=row_count;
        perform set_config('crm.op_privilegiada',coalesce(v_old_priv,'off'),true);
        if v_n<>1 then raise exception 'La fuente ya cambió de identidad' using errcode='40001'; end if;
      end if;
      v_inversion:=private.inversion_vincular_fuente((v_actual->>'persona')::uuid,
        case when v_actual->>'tipo'='contrato' then (v_actual->>'id')::uuid end,
        case when v_actual->>'tipo'='cierre' then (v_actual->>'id')::uuid end,
        (v_actual->>'creado_por')::uuid,(v_actual->>'inicial')::boolean);
    else
      v_inversion:=(v_actual->>'inversion')::uuid;
    end if;
    v_final:=private.inversion_historica_estado(v_actual->>'tipo',(v_actual->>'id')::uuid);
    if v_final->>'estado'<>'resuelto' or (v_final->>'inversion')::uuid<>v_inversion then
      raise exception 'La vinculación histórica no quedó conciliada' using errcode='P0409';
    end if;
    v_filas:=v_filas||jsonb_build_array(jsonb_build_object('tipo',v_actual->>'tipo','id',v_actual->>'id',
      'accion',case v_actual->>'estado' when 'resuelto' then 'sin_cambios'
        when 'titular_pendiente' then 'titular_completado' else 'vinculada' end,
      'inversion',v_inversion,'titular',v_final->>'titular','persona',v_final->>'persona',
      'huella_final',v_final->>'huella'));
  end loop;
  v_resultado:=jsonb_build_object('lote',p_lote,'fuentes',v_filas,'hash_mapa',v_hash);
  update crm.inversion_backfill_lotes set resultado=v_resultado,finalizado_en=clock_timestamp() where id=p_lote;
  perform set_config('crm.op_privilegiada',coalesce(v_old_priv,'off'),true);
  return v_resultado;
exception when others then
  perform set_config('crm.op_privilegiada',coalesce(v_old_priv,'off'),true);
  raise;
end;
$$;
revoke all on function private.inversion_historica_aplicar(uuid,jsonb) from public,anon,authenticated,service_role;

-- Prerrequisito de cotitularidad: el auxiliar no autentica ni autoriza.
-- Crear/actualizar contrato lo llaman como postgres después de sus controles.
-- Se conserva su cuerpo y la congelación documental; se cierra la llamada API.
do $cotitular_guard$
declare v_md5 text;
begin
  v_md5:=md5(pg_get_functiondef('public._sync_contrato_titulares(uuid,jsonb)'::regprocedure));
  if v_md5 is distinct from '833f09e11e2c1289739613074b07965b'
     or (select pg_get_userbyid(proowner) from pg_proc
       where oid='public._sync_contrato_titulares(uuid,jsonb)'::regprocedure) <> 'postgres' then
    raise exception 'Definición del auxiliar distinta de la base revisada (MD5 %); revisar cuerpo, atributos y versión PostgreSQL',v_md5;
  end if;
end;
$cotitular_guard$;
revoke all on function public._sync_contrato_titulares(uuid,jsonb)
  from public,anon,authenticated,service_role;

-- REVOKE no es prueba de su propio resultado: rechazar permisos efectivos o
-- grantees inesperados, incluso si el ejecutor recibió únicamente un WARNING.
do $cotitular_acl$
begin
  if exists (select 1 from pg_proc p,
      aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid='public._sync_contrato_titulares(uuid,jsonb)'::regprocedure
      and a.grantee<>p.proowner and a.privilege_type='EXECUTE')
    or exists (select 1 from unnest(array['anon','authenticated','service_role']) rol
      where has_function_privilege(rol,'public._sync_contrato_titulares(uuid,jsonb)','EXECUTE')) then
    raise exception 'El auxiliar de titulares conserva EXECUTE fuera de su propietario'
      using errcode='42501';
  end if;
end;
$cotitular_acl$;

-- Procedencia documental inmutable. No concede acceso Portal ni atribución comercial.
create table crm.inversion_cotitular_origenes (
  id uuid primary key default gen_random_uuid(),
  contrato_titular_id uuid not null unique references public.contrato_titulares(id) on delete restrict,
  inversion_id uuid not null references crm.inversiones(id),
  persona_origen_id uuid not null references crm.inversionistas(id),
  identificador_origen_id uuid not null references crm.inversionista_identificadores(id),
  fuente_snapshot jsonb not null,
  identificador_snapshot jsonb not null,
  hash_fuente text not null,
  vinculado_por uuid references public.perfiles(id),
  origen_registro text not null check(origen_registro in ('alta','conciliacion','administracion')),
  operador_sql text not null default session_user,
  vinculado_en timestamptz not null default statement_timestamp()
);
create index inversion_cotitular_origen_inversion_idx on crm.inversion_cotitular_origenes(inversion_id);
create index inversion_cotitular_origen_persona_idx on crm.inversion_cotitular_origenes(persona_origen_id);
create index inversion_cotitular_origen_identificador_idx on crm.inversion_cotitular_origenes(identificador_origen_id);
create index inversion_cotitular_origen_actor_idx on crm.inversion_cotitular_origenes(vinculado_por);
alter table crm.inversion_cotitular_origenes enable row level security;
revoke all on crm.inversion_cotitular_origenes from public,anon,authenticated,service_role;
create trigger trg_audit_cotitular_origen after insert on crm.inversion_cotitular_origenes
  for each row execute function private.log_audit_sin_secretos('fuente_snapshot','identificador_snapshot','hash_fuente');

create or replace function private.f4_proteger_origen_cotitular()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_schema='crm' then
    raise exception 'La procedencia del cotitular conserva su registro original' using errcode='P0409';
  end if;
  if tg_op='UPDATE' and to_jsonb(new)=to_jsonb(old) then return new; end if;
  if exists(select 1 from crm.inversion_cotitular_origenes where contrato_titular_id=old.id) then
    raise exception 'El titular documental tiene procedencia neutral; conserva el documento original' using errcode='55000';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.f4_proteger_origen_cotitular() from public,anon,authenticated,service_role;
create trigger trg_cotitular_origen_inmutable before update or delete on crm.inversion_cotitular_origenes
  for each row execute function private.f4_proteger_origen_cotitular();
create trigger trg_titular_procedencia_inmutable before update or delete on public.contrato_titulares
  for each row execute function private.f4_proteger_origen_cotitular();

-- Sólo consume identidades verificadas. Un documento histórico reutilizado por
-- otra persona queda en revisión: nunca se adivina quién firmó el contrato.
create or replace function private.inversion_cotitular_estado(p_titular uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  v_t public.contrato_titulares%rowtype;
  v_o crm.inversion_cotitular_origenes%rowtype;
  v_d crm.inversionista_identificadores%rowtype;
  v_i uuid; v_p uuid; v_norm text; v_base jsonb; v_duenos integer;
begin
  select * into v_t from public.contrato_titulares where id=p_titular;
  if not found then raise exception 'Titular no encontrado' using errcode='P0002'; end if;
  select id into v_i from crm.inversiones where contrato_id=v_t.contrato_id;
  v_base:=jsonb_build_object('titular_id',v_t.id,'orden',v_t.orden,'inversion_id',v_i);
  select * into v_o from crm.inversion_cotitular_origenes where contrato_titular_id=v_t.id;
  if found then
    v_p:=private.inversionista_canonica(v_o.persona_origen_id);
    if v_o.inversion_id is distinct from v_i or v_o.hash_fuente is distinct from private.idem_hash(to_jsonb(v_t))
      or not exists(select 1 from crm.inversion_titulares where inversion_id=v_i and inversionista_id=v_p) then
      return v_base||jsonb_build_object('estado','revision','motivo','procedencia_incoherente');
    end if;
    return v_base||jsonb_build_object('estado','vinculado','inversionista_id',v_p,
      'persona_origen_id',v_o.persona_origen_id,'origen_registro',v_o.origen_registro);
  end if;
  if v_i is null or not private.contrato_documental_congelado(v_t.contrato_id) then
    return v_base||jsonb_build_object('estado','pendiente','motivo','sin_inversion_o_snapshot');
  end if;
  v_norm:=upper(regexp_replace(coalesce(v_t.documento,''),'[^A-Za-z0-9]','','g'));
  select count(distinct private.inversionista_canonica(inversionista_id)) into v_duenos
    from crm.inversionista_identificadores where tipo_documento=v_t.tipo_documento and documento_normalizado=v_norm and verificado;
  if v_duenos>1 then
    return v_base||jsonb_build_object('estado','revision','motivo','documento_reutilizado');
  end if;
  select d.* into v_d from crm.inversionista_identificadores d join crm.inversionistas p on p.id=d.inversionista_id
    where d.tipo_documento=v_t.tipo_documento and d.documento_normalizado=v_norm and d.estado='vigente'
      and d.verificado and p.estado='activo' and private.inversionista_canonica(p.id)=p.id;
  if not found then
    return v_base||jsonb_build_object('estado','pendiente','motivo','identidad_verificada_pendiente');
  end if;
  return v_base||jsonb_build_object('estado','disponible','inversionista_id',v_d.inversionista_id,
    'identificador_id',v_d.id);
end;
$$;
revoke all on function private.inversion_cotitular_estado(uuid) from public,anon,authenticated,service_role;

create or replace function private.inversion_cotitulares_vincular(p_inversion uuid,p_origen_registro text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  v_i crm.inversiones%rowtype; v_t public.contrato_titulares%rowtype;
  v_d crm.inversionista_identificadores%rowtype; v_s jsonb; v_res jsonb:='[]'; v_p uuid;
begin
  if current_user<>'postgres' or p_origen_registro not in ('alta','conciliacion','administracion') then
    raise exception 'Operación interna' using errcode='42501';
  end if;
  select * into v_i from crm.inversiones where id=p_inversion for update nowait;
  if not found then raise exception 'Inversión no encontrada' using errcode='P0002'; end if;
  if v_i.contrato_id is null then return v_res; end if;
  perform 1 from public.contratos where id=v_i.contrato_id for share nowait;
  for v_t in select * from public.contrato_titulares where contrato_id=v_i.contrato_id order by orden,id loop
    begin
      perform 1 from public.contrato_titulares where id=v_t.id for update nowait;
      v_s:=private.inversion_cotitular_estado(v_t.id);
      if v_s->>'estado'='disponible' then
        -- Misma clave que F3; no esperar una corrección/fusión que necesita la
        -- persona principal ya bloqueada por el alta de esta inversión.
        if not pg_try_advisory_xact_lock(hashtext('inv_resolver:'||v_t.tipo_documento||':'||
          upper(regexp_replace(coalesce(v_t.documento,''),'[^A-Za-z0-9]','','g')))) then
          raise lock_not_available;
        end if;
        v_p:=(v_s->>'inversionista_id')::uuid;
        perform 1 from crm.inversionistas where id=v_p for update nowait;
        v_s:=private.inversion_cotitular_estado(v_t.id);
        if v_s->>'estado'='disponible' and (v_s->>'inversionista_id')::uuid=v_p then
          select * into strict v_d from crm.inversionista_identificadores where id=(v_s->>'identificador_id')::uuid;
          insert into crm.inversion_titulares(inversion_id,inversionista_id,rol,creado_por)
            values(v_i.id,v_p,'cotitular',(select auth.uid())) on conflict(inversion_id,inversionista_id) do nothing;
          insert into crm.inversion_cotitular_origenes(contrato_titular_id,inversion_id,persona_origen_id,
            identificador_origen_id,fuente_snapshot,identificador_snapshot,hash_fuente,vinculado_por,origen_registro)
            values(v_t.id,v_i.id,v_p,v_d.id,to_jsonb(v_t),to_jsonb(v_d),private.idem_hash(to_jsonb(v_t)),(select auth.uid()),p_origen_registro);
          v_s:=private.inversion_cotitular_estado(v_t.id);
        end if;
      end if;
    exception when lock_not_available or deadlock_detected then
      v_s:=jsonb_build_object('titular_id',v_t.id,'orden',v_t.orden,'inversion_id',v_i.id,
        'estado','pendiente','motivo','identidad_ocupada');
    end;
    -- El lector comercial no recibe identificadores privados ni huellas.
    v_res:=v_res||jsonb_build_array(v_s-'identificador_id');
  end loop;
  return v_res;
end;
$$;
revoke all on function private.inversion_cotitulares_vincular(uuid,text) from public,anon,authenticated,service_role;

create or replace function crm.inversion_cotitulares_fn(p_inversion uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_i crm.inversiones%rowtype; v_res jsonb;
begin
  select * into v_i from crm.inversiones where id=p_inversion;
  if not found then raise exception 'Inversión no encontrada' using errcode='P0002'; end if;
  perform private.inversion_persona_autorizada(v_i.inversionista_id);
  select coalesce(jsonb_agg(private.inversion_cotitular_estado(t.id)-'identificador_id' order by t.orden,t.id),'[]') into v_res
    from public.contrato_titulares t where t.contrato_id=v_i.contrato_id;
  return v_res;
end;
$$;
revoke all on function crm.inversion_cotitulares_fn(uuid) from public,anon,authenticated,service_role;
grant execute on function crm.inversion_cotitulares_fn(uuid) to authenticated;

create or replace function crm.conciliar_cotitulares_inversion_fn(p_inversion uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_p uuid;
begin
  select inversionista_id into v_p from crm.inversiones where id=p_inversion;
  if not found then raise exception 'Inversión no encontrada' using errcode='P0002'; end if;
  perform private.inversion_persona_autorizada(v_p);
  return private.inversion_cotitulares_vincular(p_inversion,'conciliacion');
end;
$$;
revoke all on function crm.conciliar_cotitulares_inversion_fn(uuid) from public,anon,authenticated,service_role;
grant execute on function crm.conciliar_cotitulares_inversion_fn(uuid) to authenticated;

create or replace function private.inversion_cotitulares_historicos(p_inversion uuid)
returns jsonb language plpgsql security invoker set search_path='' set lock_timeout='5s' as $$
begin
  if session_user not in ('postgres','supabase_admin') or current_user<>'postgres' then
    raise exception 'Operación administrativa SQL' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  perform pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  if exists(select 1 from crm.multiempresa_flags where nombre='inversiones_escritura' and activo) then
    raise exception 'La conciliación histórica requiere F4 apagada' using errcode='P0409';
  end if;
  return private.inversion_cotitulares_vincular(p_inversion,'administracion');
end;
$$;
revoke all on function private.inversion_cotitulares_historicos(uuid) from public,anon,authenticated,service_role;

-- Validador único compartido por preparación y corrección explícita.
create or replace function private.inversion_validar_datos(p_clave uuid,p_datos jsonb,p_contexto jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare
  v_persona uuid:=(p_datos->>'inversionista_id')::uuid;
  v_ctx jsonb:=p_contexto;
  v_e crm.empresas%rowtype;
  v_monto numeric; v_fecha date; v_vence date; v_ruta text;
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
  select * into v_e from crm.empresas where clave=p_datos->>'empresa' and activa for share;
  if not found or v_e.clave not in ('avance','qorilazo','prodelco') then
    raise exception 'Empresa no disponible para invertir' using errcode='22023';
  end if;
  if v_e.fuente_capital='cierres_externos' then
    begin
      v_monto := (p_datos->>'monto')::numeric;
      v_fecha := (p_datos->>'fecha_comercial')::date;
      v_vence := (p_datos->>'vence_en')::date;
    exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'Revisa el monto y las fechas de la inversión' using errcode='22023';
    end;
    if v_monto is null or v_monto in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
       or v_monto<=0 or v_monto>999999999999.99 or v_monto<>trunc(v_monto,2) then
      raise exception 'El monto debe ser positivo y tener como máximo dos decimales' using errcode='22023';
    end if;
    if p_datos->>'moneda' is distinct from 'PEN' or not ('PEN'=any(v_e.monedas)) then
      raise exception 'Esta cooperativa registra inversiones en soles' using errcode='22023';
    end if;
    if v_fecha is null or not isfinite(v_fecha) or v_fecha>(statement_timestamp() at time zone 'America/Lima')::date
       or v_vence is null or not isfinite(v_vence) or v_vence<=v_fecha then
      raise exception 'La fecha comercial no puede ser futura y el vencimiento debe ser posterior' using errcode='22023';
    end if;
    if length(btrim(coalesce(p_datos->>'numero_transaccion',''))) not between 1 and 64
       or length(btrim(coalesce(p_datos->>'referencia',''))) not between 1 and 64 then
      raise exception 'El depósito y la referencia son obligatorios, con un máximo de 64 caracteres' using errcode='22023';
    end if;
    v_ruta := p_datos#>>'{evidencia,ruta}';
    if v_ruta is null or v_ruta !~ ('^'||v_persona::text||'/'||p_clave::text||'/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$') then
      raise exception 'El comprobante debe pertenecer a esta persona y solicitud' using errcode='22023';
    end if;
  else
    if jsonb_typeof(p_datos->'contrato') is distinct from 'object'
       or jsonb_typeof(p_datos->'cronograma') is distinct from 'array'
       or jsonb_typeof(p_datos->'cuenta') is distinct from 'object' then
      raise exception 'Avance requiere contrato, cronograma y cuenta de pago' using errcode='22023';
    end if;
    if p_datos#>>'{contrato,moneda}' is null or not (p_datos#>>'{contrato,moneda}'=any(v_e.monedas)) then
      raise exception 'Moneda no admitida por Avance' using errcode='22023';
    end if;
    if p_datos#>>'{contrato,cliente_id}' is not null
       and p_datos#>>'{contrato,cliente_id}' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato debe pertenecer a esta persona' using errcode='P0409';
    end if;
    if v_ctx->>'perfil_id' is null or p_datos ? 'alta_portal' then
      perform private.inversion_datos_portal(p_datos->'alta_portal');
    end if;
    if p_datos#>>'{contrato,analista_cierre_id}' is not null
       and p_datos#>>'{contrato,analista_cierre_id}' is distinct from v_ctx->>'responsable_id' then
      raise exception 'El analista debe corresponder al responsable de la persona al preparar la inversión' using errcode='P0409';
    end if;
  end if;
  return v_e.id;
end;
$$;
revoke all on function private.inversion_validar_datos(uuid,jsonb,jsonb) from public,anon,authenticated,service_role;

create table crm.inversion_solicitud_correcciones (
  id uuid primary key,
  solicitud_id uuid not null references crm.inversion_solicitudes(id),
  revision_anterior integer not null check(revision_anterior>=0),
  revision integer not null check(revision=revision_anterior+1),
  hash_peticion text not null,
  hash_anterior text not null,
  hash_nuevo text not null,
  datos_anteriores jsonb not null,
  datos_nuevos jsonb not null,
  motivo text not null,
  corregido_por uuid not null references public.perfiles(id),
  corregido_en timestamptz not null default statement_timestamp(),
  unique(solicitud_id,revision)
);
create index inversion_correcciones_actor_idx on crm.inversion_solicitud_correcciones(corregido_por);
alter table crm.inversion_solicitud_correcciones enable row level security;
revoke all on crm.inversion_solicitud_correcciones from public,anon,authenticated,service_role;
create trigger trg_audit_inversion_correccion after insert on crm.inversion_solicitud_correcciones
  for each row execute function private.log_audit_sin_secretos('hash_peticion','hash_anterior','hash_nuevo','datos_anteriores','datos_nuevos','motivo');
create trigger trg_inversion_correcciones_inmutables before update or delete on crm.inversion_solicitud_correcciones
  for each row execute function private.f4_fuente_inmutable();

create or replace function crm.solicitud_inversion_fn(p_solicitud uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_persona uuid; v_ctx jsonb; v_datos jsonb;
begin
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_ctx:=private.inversion_persona_autorizada(v_persona);
  select datos into v_datos from crm.inversion_solicitudes where id=p_solicitud for share;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||jsonb_build_object('datos',v_datos);
end;
$$;
revoke all on function crm.solicitud_inversion_fn(uuid) from public,anon,authenticated,service_role;
grant execute on function crm.solicitud_inversion_fn(uuid) to authenticated;

create or replace function crm.corregir_solicitud_inversion_fn(
  p_solicitud uuid,p_clave uuid,p_revision_datos_esperada integer,p_datos jsonb,p_motivo text)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_persona uuid; v_ctx jsonb; v_validacion jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_r crm.inversion_solicitud_correcciones%rowtype;
  v_hash text; v_inicial uuid; v_empresa uuid;
begin
  if p_clave is null or p_revision_datos_esperada is null or p_revision_datos_esperada<0
    or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Indica clave, versión y contenido de la corrección' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  -- Siempre ámbito/membresía actuales, también al recuperar una corrección.
  v_ctx:=private.inversion_persona_autorizada(v_persona);
  perform private.motivo_sin_documento(p_motivo,(select array_agg(documento_normalizado)
    from crm.inversionista_identificadores where inversionista_id=private.inversionista_canonica(v_persona)));
  v_hash:=private.idem_hash(jsonb_build_object('solicitud',p_solicitud,'revision',p_revision_datos_esperada,
    'datos',p_datos,'motivo',btrim(p_motivo)));
  perform pg_advisory_xact_lock(hashtextextended('f4_correccion:'||p_clave::text,0));
  select * into v_r from crm.inversion_solicitud_correcciones where id=p_clave;
  if found then
    if v_r.hash_peticion is distinct from v_hash then
      raise exception 'La clave de corrección ya se usó con otros datos' using errcode='P0409';
    end if;
    return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
      jsonb_build_object('correccion_id',v_r.id,'revision_aplicada',v_r.revision,'reintento',true);
  end if;
  v_ctx:=private.inversion_persona_contexto(v_persona);
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if v_s.estado<>'preparada' then
    raise exception 'Sólo se corrigen solicitudes todavía preparadas' using errcode='P0409';
  end if;
  if v_s.revision_datos is distinct from p_revision_datos_esperada then
    raise exception 'Los datos cambiaron; vuelve a revisar la solicitud' using errcode='40001';
  end if;
  if v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'Revisa primero el cambio de responsable de esta solicitud' using errcode='P0409';
  end if;
  if p_datos->'inversionista_id' is distinct from v_s.datos->'inversionista_id'
    or p_datos->'empresa' is distinct from v_s.datos->'empresa'
    or p_datos#>'{contrato,cliente_id}' is distinct from v_s.datos#>'{contrato,cliente_id}'
    or p_datos#>'{contrato,analista_cierre_id}' is distinct from v_s.datos#>'{contrato,analista_cierre_id}' then
    raise exception 'La corrección conserva la persona, empresa y referencias originales del contrato' using errcode='22023';
  end if;
  if p_datos->'evidencia' is distinct from v_s.datos->'evidencia' then
    raise exception 'La corrección conserva la ruta del comprobante de esta solicitud' using errcode='22023';
  end if;
  if v_s.auth_claim_id is not null and p_datos->'alta_portal' is distinct from v_s.datos->'alta_portal' then
    raise exception 'El acceso Avance ya está reservado; conserva sus datos de alta' using errcode='P0409';
  end if;
  select responsable_anterior_id into v_inicial from crm.inversion_solicitud_revisiones
    where solicitud_id=p_solicitud order by revision limit 1;
  v_validacion:=v_ctx||jsonb_build_object('responsable_id',coalesce(v_inicial,v_s.responsable_esperado_id));
  v_empresa:=private.inversion_validar_datos(p_solicitud,p_datos,v_validacion);
  if v_empresa is distinct from v_s.empresa_id then
    raise exception 'La empresa cambió; revisa la solicitud' using errcode='40001';
  end if;
  if p_datos=v_s.datos then raise exception 'No hay datos distintos que corregir' using errcode='22023'; end if;
  insert into crm.inversion_solicitud_correcciones(id,solicitud_id,revision_anterior,revision,
    hash_peticion,hash_anterior,hash_nuevo,datos_anteriores,datos_nuevos,motivo,corregido_por)
    values(p_clave,p_solicitud,v_s.revision_datos,v_s.revision_datos+1,v_hash,
    private.idem_hash(v_s.datos),private.idem_hash(p_datos),v_s.datos,p_datos,btrim(p_motivo),(select auth.uid()));
  -- La huella original permanece: repetir preparar con su petición original
  -- recupera esta misma solicitud, nunca crea otra ni revierte una corrección.
  update crm.inversion_solicitudes set datos=p_datos,revision_datos=revision_datos+1,
    actualizado_en=statement_timestamp() where id=p_solicitud;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
    jsonb_build_object('correccion_id',p_clave,'revision_aplicada',v_s.revision_datos+1,'reintento',false);
end;
$$;
revoke all on function crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text) to authenticated;

alter function private.inversiones_escritura_bajo_candado() owner to postgres;
alter function private.inversion_persona_contexto(uuid) owner to postgres;
alter function private.inversion_persona_autorizada(uuid) owner to postgres;
alter function private.inversion_solicitud_resultado(uuid,jsonb) owner to postgres;
alter function crm.preparar_inversion_fn(uuid,jsonb) owner to postgres;
alter function private.f4_comprobante_autorizado(text) owner to postgres;
alter function private.f4_fuente_inmutable() owner to postgres;
alter function private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean) owner to postgres;
alter function crm.confirmar_inversion_fn(uuid) owner to postgres;
alter function private.f4_comprobante_visible(text) owner to postgres;
alter function private.f4_sincronizar_cierre() owner to postgres;
alter function private.f4_contrato_reconocer() owner to postgres;
alter function private.f4_contrato_vincular() owner to postgres;
alter function private.inversion_datos_portal(jsonb) owner to postgres;
alter function crm.acceso_inversion_fn(uuid,text,jsonb) owner to postgres;
alter function private.f4_alineacion_perfil_permitida(uuid,uuid) owner to postgres;
alter function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) owner to postgres;
alter function private.inversion_historica_estado(text,uuid) owner to postgres;
alter function private.inversion_historica_aplicar(uuid,jsonb) owner to postgres;
alter function private.f4_proteger_lote_historico() owner to postgres;
alter function private.inversion_validar_datos(uuid,jsonb,jsonb) owner to postgres;
alter function crm.solicitud_inversion_fn(uuid) owner to postgres;
alter function crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text) owner to postgres;
alter function crm.confirmar_inversion_revisada_fn(uuid,integer) owner to postgres;
alter function private.f4_proteger_origen_cotitular() owner to postgres;
alter function private.inversion_cotitular_estado(uuid) owner to postgres;
alter function private.inversion_cotitulares_vincular(uuid,text) owner to postgres;
alter function crm.inversion_cotitulares_fn(uuid) owner to postgres;
alter function crm.conciliar_cotitulares_inversion_fn(uuid) owner to postgres;
alter function private.inversion_cotitulares_historicos(uuid) owner to postgres;
alter table crm.inversion_solicitudes owner to postgres;
alter table crm.inversion_ajustes_mes_cerrado owner to postgres;
alter table crm.inversion_eventos owner to postgres;
alter table crm.inversion_solicitud_revisiones owner to postgres;
alter table crm.inversion_backfill_lotes owner to postgres;
alter table crm.inversion_cotitular_origenes owner to postgres;
alter table crm.inversion_solicitud_correcciones owner to postgres;
notify pgrst,'reload schema';
commit;
