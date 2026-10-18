-- Coordinación: consulta global de Leads y Cartera, sin ampliar autoridad comercial.
-- Pedido de Miguel, 15/10/2026. No modifica datos ni los helpers de escritura.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));
create function private.es_coordinacion_consulta()
returns boolean language sql stable security definer set search_path=''
as $$ select coalesce(private.rol_crm((select auth.uid()))='coordinador',false); $$;
revoke all on function private.es_coordinacion_consulta() from public,anon,authenticated,service_role;
grant execute on function private.es_coordinacion_consulta() to authenticated;
comment on function private.es_coordinacion_consulta() is 'Consulta de Coordinación activa. No concede escrituras.';
create policy leads_coordinacion_consulta on crm.leads for select to authenticated
using (activo is true and (select private.es_coordinacion_consulta()));
create policy actividades_coordinacion_consulta on crm.actividades for select to authenticated
using ((select private.es_coordinacion_consulta()) and exists
  (select 1 from crm.leads l where l.id=lead_id and l.activo is true));
create policy tareas_coordinacion_consulta on crm.tareas for select to authenticated
using (activo is true and (select private.es_coordinacion_consulta()) and exists
  (select 1 from crm.leads l where l.id=lead_id and l.activo is true));

-- crm.cartera_filtrada_fn(integer, timestamp with time zone, uuid, text, uuid, boolean, text, date, date, text, text, boolean, text, text, text)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.cartera_filtrada_fn(integer, timestamp with time zone, uuid, text, uuid, boolean, text, date, date, text, text, boolean, text, text, text)'));
begin
  if v_def is null or md5(v_def) not in ('37e4e2a13b50c757ffc7a8fdcb3c37b0', '807a36a43ab5a4bda5794b9ef6edceb8') then
    raise exception 'Cambió crm.cartera_filtrada_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
$antes$, $despues$  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global() or private.es_coordinacion_consulta();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
$despues$);
  if md5(v_def) not in ('40dfde6d2e434c390cf00798493a069c', 'd1c85968cfe1ba0a9670fb837b216df0') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.equipo_visible_fn()
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.equipo_visible_fn()'));
begin
  if v_def is null or md5(v_def) not in ('200162f4519586a6c68d8ccf0cf591f7') then
    raise exception 'Cambió crm.equipo_visible_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$      or e.perfil_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or private.es_lector_global()
    );
$function$
$antes$, $despues$      or e.perfil_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or private.es_lector_global() or private.es_coordinacion_consulta()
    );
$function$
$despues$);
  if md5(v_def) not in ('58bd05540d2a3eb576a7b648978707e7') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.cartera_inversionistas_estado_fn()
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.cartera_inversionistas_estado_fn()'));
begin
  if v_def is null or md5(v_def) not in ('83575873409d51508753fa6405ffcc92') then
    raise exception 'Cambió crm.cartera_inversionistas_estado_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  v_escritura boolean;
begin
  if v_uid is null or not coalesce(
      v_rol in ('vendedor','supervisor','gerencia') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_f3:=private.resolver_en_puertas_bajo_candado();
  select private.rol_crm(v_uid),private.es_lector_global() into v_rol,v_lector;
  if not coalesce(v_rol in ('vendedor','supervisor','gerencia') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock_shared(hashtext('crm_flag_ficha_360_neutral'));
$antes$, $despues$  v_escritura boolean;
begin
  if v_uid is null or not coalesce(
      v_rol in ('vendedor','supervisor','gerencia','coordinador') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_f3:=private.resolver_en_puertas_bajo_candado();
  select private.rol_crm(v_uid),private.es_lector_global() into v_rol,v_lector;
  if not coalesce(v_rol in ('vendedor','supervisor','gerencia','coordinador') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock_shared(hashtext('crm_flag_ficha_360_neutral'));
$despues$);
  v_def := replace(v_def, $antes$      or i.inversionista_canonico_id is not null
  ) into v_cobertura;
  return jsonb_build_object('version',1,'habilitada',v_cobertura,
    'escritura_habilitada',v_cobertura and not v_lector
      and private.puede_gestionar_contratos_crm() and v_escritura,
    'motivo',case when not v_cobertura
      then 'La cartera requiere conciliación antes de habilitarse' end);
$antes$, $despues$      or i.inversionista_canonico_id is not null
  ) into v_cobertura;
  return jsonb_build_object('version',1,'habilitada',v_cobertura,
    'escritura_habilitada',v_cobertura and not v_lector and v_rol <> 'coordinador'
      and private.puede_gestionar_contratos_crm() and v_escritura,
    'motivo',case when not v_cobertura
      then 'La cartera requiere conciliación antes de habilitarse' end);
$despues$);
  if md5(v_def) not in ('d5f974d2805dda7578e31935a12eef30') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.cartera_f5_personas_visibles(uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.cartera_f5_personas_visibles(uuid)'));
begin
  if v_def is null or md5(v_def) not in ('bca76d60bd56905eff978357f539d300') then
    raise exception 'Cambió private.cartera_f5_personas_visibles; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$    where a.uid is not null and i.inversionista_canonico_id is null
      -- Recorta antes de los laterales de presentación; no elimina ninguna regla de acceso.
      and (p_inversionista is null or i.id=(select id from destino))
      and (a.rol in ('vendedor','supervisor','gerencia') or a.lector)
      and (a.rol='gerencia'
        or (not a.lector and i.responsable_relacion_id=any(a.visibles))
        or (a.rol='supervisor' and i.responsable_relacion_id is null
          and exists(select 1 from bandeja_supervisor b where b.canonica=i.id))
$antes$, $despues$    where a.uid is not null and i.inversionista_canonico_id is null
      -- Recorta antes de los laterales de presentación; no elimina ninguna regla de acceso.
      and (p_inversionista is null or i.id=(select id from destino))
      and (a.rol in ('vendedor','supervisor','gerencia','coordinador') or a.lector)
      and (a.rol in ('gerencia','coordinador')
        or (not a.lector and i.responsable_relacion_id=any(a.visibles))
        or (a.rol='supervisor' and i.responsable_relacion_id is null
          and exists(select 1 from bandeja_supervisor b where b.canonica=i.id))
$despues$);
  if md5(v_def) not in ('2a62e803b717e165ef91cbbf7f7d2845') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.inversionista_ficha_fn(uuid, integer, integer)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.inversionista_ficha_fn(uuid, integer, integer)'));
begin
  if v_def is null or md5(v_def) not in ('9d981c6ca6eb214a318678e85bd851d6') then
    raise exception 'Cambió crm.inversionista_ficha_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$AS $function$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb; v_postventa boolean:=false;
begin
  perform private.cartera_f5_exigir();
$antes$, $despues$AS $function$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_coordinacion boolean:=private.es_coordinacion_consulta();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb; v_postventa boolean:=false;
begin
  perform private.cartera_f5_exigir();
$despues$);
  v_def := replace(v_def, $antes$  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles(v_id) where inversionista_id=v_id;
  if not found then return null; end if;
  if not v_lector then
    begin
      v_postventa:=(crm.postventa_estado_fn()->>'habilitada')::boolean and private.postventa_visible(v_id);
    exception when serialization_failure or lock_not_available or sqlstate 'PT409' then v_postventa:=false;
$antes$, $despues$  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles(v_id) where inversionista_id=v_id;
  if not found then return null; end if;
  if not v_lector and not v_coordinacion then
    begin
      v_postventa:=(crm.postventa_estado_fn()->>'habilitada')::boolean and private.postventa_visible(v_id);
    exception when serialization_failure or lock_not_available or sqlstate 'PT409' then v_postventa:=false;
$despues$);
  v_def := replace(v_def, $antes$  end if;
  -- Contexto F4 es la autoridad operativa: revisa documento, responsable, veto,
  -- perfil y lead canónico. Su lock no se toma para una lectura de Directorio.
  if not v_lector and (crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada')::boolean then
    begin
      perform private.inversion_persona_contexto(v_id);
      v_operable:=true;
$antes$, $despues$  end if;
  -- Contexto F4 es la autoridad operativa: revisa documento, responsable, veto,
  -- perfil y lead canónico. Su lock no se toma para una lectura de Directorio.
  if not v_lector and not v_coordinacion and (crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada')::boolean then
    begin
      perform private.inversion_persona_contexto(v_id);
      v_operable:=true;
$despues$);
  v_def := replace(v_def, $antes$        v_operable:=false;v_motivo:='Hay una actualización en curso. Revisa la ficha antes de registrar otra inversión';
      when insufficient_privilege then v_motivo:='Revisa la asignación antes de registrar otra inversión';
    end;
  else v_motivo:=case when v_lector then 'Acceso de solo lectura' else 'El registro de inversiones aún no está habilitado' end;
  end if;
  select coalesce(jsonb_agg(p.id order by p.id),'[]') into v_cuentas
  from public.perfiles p where p.id=any(v_p.perfil_ids) and not v_lector
    and private.puede_gestionar_cuentas_cliente(p.id);
  with fuentes as materialized (
    select * from private.cartera_f5_fuentes_reales() f where f.inversionista_id=v_id
$antes$, $despues$        v_operable:=false;v_motivo:='Hay una actualización en curso. Revisa la ficha antes de registrar otra inversión';
      when insufficient_privilege then v_motivo:='Revisa la asignación antes de registrar otra inversión';
    end;
  else v_motivo:=case when v_lector or v_coordinacion then 'Acceso de consulta' else 'El registro de inversiones aún no está habilitado' end;
  end if;
  select coalesce(jsonb_agg(p.id order by p.id),'[]') into v_cuentas
  from public.perfiles p where p.id=any(v_p.perfil_ids) and not v_lector and not v_coordinacion
    and private.puede_gestionar_cuentas_cliente(p.id);
  with fuentes as materialized (
    select * from private.cartera_f5_fuentes_reales() f where f.inversionista_id=v_id
$despues$);
  v_def := replace(v_def, $antes$    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('postventa',v_postventa,'nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      -- Fase 6 de Facturación (10/10/2026): quién VENDIÓ (analista de cierre del contrato o vendedor de la
$antes$, $despues$    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('postventa',v_postventa,'nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and not v_coordinacion and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector and not v_coordinacion),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      -- Fase 6 de Facturación (10/10/2026): quién VENDIÓ (analista de cierre del contrato o vendedor de la
$despues$);
  v_def := replace(v_def, $antes$        'fecha_inicio',c.fecha_inicio,'tasa_anual',c.tasa_anual,'modalidad',c.modalidad,
        'tipo_interes',c.tipo_interes,'categoria',c.categoria)
        from public.contratos c where c.id=f.fuente_id) end,
      'pdf',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then (
        select jsonb_build_object('estado',s->>'estado','reintentable',(s->>'reintentable')::boolean)
        from (select private.contrato_pdf_estado_base(f.fuente_id) s) x) end,
      'documentos',case when v_lector or (f.empresa='avance' and not private.puede_leer_contrato_pdf(f.fuente_id))
        then '[]'::jsonb when f.empresa='avance' then coalesce((
        select jsonb_agg(jsonb_build_object('id',d.id,'nombre',d.nombre,'tipo',d.tipo)
          order by d.creado_en desc,d.id) from public.documentos d where d.contrato_id=f.fuente_id),'[]')
$antes$, $despues$        'fecha_inicio',c.fecha_inicio,'tasa_anual',c.tasa_anual,'modalidad',c.modalidad,
        'tipo_interes',c.tipo_interes,'categoria',c.categoria)
        from public.contratos c where c.id=f.fuente_id) end,
      'pdf',case when f.empresa='avance' and not v_lector and not v_coordinacion and private.puede_leer_contrato_pdf(f.fuente_id) then (
        select jsonb_build_object('estado',s->>'estado','reintentable',(s->>'reintentable')::boolean)
        from (select private.contrato_pdf_estado_base(f.fuente_id) s) x) end,
      'documentos',case when v_lector or v_coordinacion or (f.empresa='avance' and not private.puede_leer_contrato_pdf(f.fuente_id))
        then '[]'::jsonb when f.empresa='avance' then coalesce((
        select jsonb_agg(jsonb_build_object('id',d.id,'nombre',d.nombre,'tipo',d.tipo)
          order by d.creado_en desc,d.id) from public.documentos d where d.contrato_id=f.fuente_id),'[]')
$despues$);
  v_def := replace(v_def, $antes$        else coalesce((select jsonb_build_array(jsonb_build_object('id',ce.comprobante_objeto_id,
          'nombre','Comprobante de depósito','tipo','comprobante')) from crm.cierres_externos ce
          where ce.id=f.fuente_id and ce.comprobante_objeto_id is not null),'[]') end,
      'cotitulares',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then coalesce((
        select jsonb_agg(jsonb_build_object('orden',t.orden,'nombre',t.nombre_completo,
          'tipo_documento',t.tipo_documento,'documento',t.documento) order by t.orden,t.id)
        from public.contrato_titulares t where t.contrato_id=f.fuente_id),'[]') else '[]'::jsonb end,
$antes$, $despues$        else coalesce((select jsonb_build_array(jsonb_build_object('id',ce.comprobante_objeto_id,
          'nombre','Comprobante de depósito','tipo','comprobante')) from crm.cierres_externos ce
          where ce.id=f.fuente_id and ce.comprobante_objeto_id is not null),'[]') end,
      'cotitulares',case when f.empresa='avance' and not v_lector and not v_coordinacion and private.puede_leer_contrato_pdf(f.fuente_id) then coalesce((
        select jsonb_agg(jsonb_build_object('orden',t.orden,'nombre',t.nombre_completo,
          'tipo_documento',t.tipo_documento,'documento',t.documento) order by t.orden,t.id)
        from public.contrato_titulares t where t.contrato_id=f.fuente_id),'[]') else '[]'::jsonb end,
$despues$);
  if md5(v_def) not in ('be113f3c638e3fdf6e0ca9a45eb86a6d') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.inversionista_gestion_fn(uuid, uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.inversionista_gestion_fn(uuid, uuid)'));
begin
  if v_def is null or md5(v_def) not in ('b44e8b4bacf35d5f4571a6c106663228') then
    raise exception 'Cambió crm.inversionista_gestion_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  v_f record; v_c public.contratos%rowtype; v_ce crm.cierres_externos%rowtype;
  v_corregir boolean:=false; v_contrato jsonb; v_documento uuid;
begin
  perform private.cartera_f5_exigir();
  v_postventa:=private.postventa_modo();
  v_id:=private.inversionista_canonica(p_inversionista);
$antes$, $despues$  v_f record; v_c public.contratos%rowtype; v_ce crm.cierres_externos%rowtype;
  v_corregir boolean:=false; v_contrato jsonb; v_documento uuid;
begin
  if private.es_coordinacion_consulta() then
    raise exception 'Coordinación consulta la ficha y corrige la categoría desde su acción específica' using errcode='42501';
  end if;
  perform private.cartera_f5_exigir();
  v_postventa:=private.postventa_modo();
  v_id:=private.inversionista_canonica(p_inversionista);
$despues$);
  if md5(v_def) not in ('121c990d9af3ee22272a73a4c90e83f6') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.cartera_recepciones_fn(date, date)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.cartera_recepciones_fn(date, date)'));
begin
  if v_def is null or md5(v_def) not in ('26edd30fad832270ca637c80dd175e1a') then
    raise exception 'Cambió private.cartera_recepciones_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$     or p_hasta > (now() at time zone 'America/Lima')::date then
    raise exception 'Rango de fechas inválido' using errcode = '22023';
  end if;
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  return query
    select distinct on (l.id) l.id, a.asignado_en, a.aproximado
$antes$, $despues$     or p_hasta > (now() at time zone 'America/Lima')::date then
    raise exception 'Rango de fechas inválido' using errcode = '22023';
  end if;
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global() or private.es_coordinacion_consulta();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  return query
    select distinct on (l.id) l.id, a.asignado_en, a.aproximado
$despues$);
  if md5(v_def) not in ('61dd6b26d8d43ef835869f7c9a11c71a') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.cartera_potencial_fn()
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.cartera_potencial_fn()'));
begin
  if v_def is null or md5(v_def) not in ('73e993d618b203cdbe21e8127f7ea5b4') then
    raise exception 'Cambió private.cartera_potencial_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      );
end;
$antes$, $despues$      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol in ('gerencia','coordinador')
        or v_lector
      );
end;
$despues$);
  if md5(v_def) not in ('c475709205aed4422a44c852d1b28b81') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.inversionista_documento_fn(uuid, uuid, uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.inversionista_documento_fn(uuid, uuid, uuid)'));
begin
  if v_def is null or md5(v_def) not in ('18db225353031f1afc67a8263c281494') then
    raise exception 'Cambió crm.inversionista_documento_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$declare v_id uuid;v_f record;v_r jsonb;v_pdf jsonb;
begin
  perform private.cartera_f5_exigir();
  if private.es_lector_global() then raise exception 'No autorizado' using errcode='42501'; end if;
  select p.inversionista_id into v_id from private.cartera_f5_personas_visibles() p
    where p.inversionista_id=private.inversionista_canonica(p_inversionista);
  if v_id is null then raise exception 'No autorizado' using errcode='42501'; end if;
$antes$, $despues$declare v_id uuid;v_f record;v_r jsonb;v_pdf jsonb;
begin
  perform private.cartera_f5_exigir();
  if private.es_lector_global() or private.es_coordinacion_consulta() then raise exception 'No autorizado' using errcode='42501'; end if;
  select p.inversionista_id into v_id from private.cartera_f5_personas_visibles() p
    where p.inversionista_id=private.inversionista_canonica(p_inversionista);
  if v_id is null then raise exception 'No autorizado' using errcode='42501'; end if;
$despues$);
  if md5(v_def) not in ('57c57879cd49afaf9c33008762ae78a5') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.inversionista_cuentas_fn(uuid, uuid, text)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.inversionista_cuentas_fn(uuid, uuid, text)'));
begin
  if v_def is null or md5(v_def) not in ('bfd1f198a4e05440ea57f6344ac1c78b') then
    raise exception 'Cambió crm.inversionista_cuentas_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$declare v_p record; v_r jsonb;
begin
  perform private.cartera_f5_exigir();
  if private.es_lector_global() then raise exception 'No autorizado' using errcode='42501'; end if;
  select * into v_p from private.cartera_f5_personas_visibles()
    where inversionista_id=private.inversionista_canonica(p_inversionista);
  if not found or not coalesce(p_perfil=any(v_p.perfil_ids),false)
$antes$, $despues$declare v_p record; v_r jsonb;
begin
  perform private.cartera_f5_exigir();
  if private.es_lector_global() or private.es_coordinacion_consulta() then raise exception 'No autorizado' using errcode='42501'; end if;
  select * into v_p from private.cartera_f5_personas_visibles()
    where inversionista_id=private.inversionista_canonica(p_inversionista);
  if not found or not coalesce(p_perfil=any(v_p.perfil_ids),false)
$despues$);
  if md5(v_def) not in ('c3f792072dd3ae13385e3bbc19f5484b') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.cartera_pagina_fn(integer, timestamp with time zone, uuid, text, uuid, boolean, text)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.cartera_pagina_fn(integer, timestamp with time zone, uuid, text, uuid, boolean, text)'));
begin
  if v_def is null or md5(v_def) not in ('63bb448d0a2a0b01d17af6a767c26ddf') then
    raise exception 'Cambió crm.cartera_pagina_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$    -- que se ve lo sigue decidiendo `leads_select`.
    and (
      v_lector
      or v_rol = 'gerencia'
      or l.vendedor_id = any(v_visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
    )
$antes$, $despues$    -- que se ve lo sigue decidiendo `leads_select`.
    and (
      v_lector
      or v_rol in ('gerencia','coordinador')
      or l.vendedor_id = any(v_visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
    )
$despues$);
  if md5(v_def) not in ('bdac463a9878fb399f391502ff1e5812') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.cierres_estado_fn(uuid[])
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.cierres_estado_fn(uuid[])'));
begin
  if v_def is null or md5(v_def) not in ('5f6eca13b613aaa40b459ea56f7c8ac5') then
    raise exception 'Cambió crm.cierres_estado_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$        -- (`NULL = any(...)` da NULL, no TRUE, asi que la rama de arriba
        -- no se lo lleva por delante.)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
      -- Solo los leads con algo que decir. Un convertido de Avance sano no
$antes$, $despues$        -- (`NULL = any(...)` da NULL, no TRUE, asi que la rama de arriba
        -- no se lo lleva por delante.)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
        or v_rol in ('gerencia','coordinador')
        or v_lector
      )
      -- Solo los leads con algo que decir. Un convertido de Avance sano no
$despues$);
  if md5(v_def) not in ('f543c8090d2266f26cfbcd6649b783f4') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.potencial_lectura(uuid, uuid[], date, timestamp with time zone, date)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.potencial_lectura(uuid, uuid[], date, timestamp with time zone, date)'));
begin
  if v_def is null or md5(v_def) not in ('ce8386e7a73ce15189a8b571aaaef5bb') then
    raise exception 'Cambió private.potencial_lectura; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ) f;
$antes$, $despues$      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol in ('gerencia','coordinador')
        or v_lector
      )
  ) f;
$despues$);
  if md5(v_def) not in ('48e38561f84000cdfe790e88e014fb65') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- crm.documento_lead_fn(uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('crm.documento_lead_fn(uuid)'));
begin
  if v_def is null or md5(v_def) not in ('af908081a94f553267b07a3239414fd1') then
    raise exception 'Cambió crm.documento_lead_fn; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  select * into v_l from crm.leads l where l.id=p_lead_id and l.activo and (
    l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid()))) or
    (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid())))) or
    private.rol_crm((select auth.uid()))='gerencia' or private.es_lector_global());
  if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='P0002'; end if;
  select array_agg(distinct id) into v_personas from (
    select private.inversionista_canonica(v_l.inversionista_id) id
$antes$, $despues$  select * into v_l from crm.leads l where l.id=p_lead_id and l.activo and (
    l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid()))) or
    (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid())))) or
    private.rol_crm((select auth.uid())) in ('gerencia','coordinador') or private.es_lector_global());
  if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='P0002'; end if;
  select array_agg(distinct id) into v_personas from (
    select private.inversionista_canonica(v_l.inversionista_id) id
$despues$);
  if md5(v_def) not in ('91bef03263619310aef50a7f20f00acd') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.conversion_estado_lead_v1(uuid)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.conversion_estado_lead_v1(uuid)'));
begin
  if v_def is null or md5(v_def) not in ('ad887162316bcb1bf9094e20655d89f4') then
    raise exception 'Cambió private.conversion_estado_lead_v1; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  -- Mismo ámbito que leads_select: incluye estacionados del supervisor y
  -- lectores globales activos. ID inexistente y ajeno tienen idéntico error.
  select * into v_lead from crm.leads l where l.id=p_lead_id and l.activo
    and (private.rol_crm(v_uid)='gerencia' or private.es_lector_global()
      or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (l.vendedor_id is null and l.asignado_supervisor_id
        in (select private.vendedor_ids_visibles(v_uid))));
$antes$, $despues$  -- Mismo ámbito que leads_select: incluye estacionados del supervisor y
  -- lectores globales activos. ID inexistente y ajeno tienen idéntico error.
  select * into v_lead from crm.leads l where l.id=p_lead_id and l.activo
    and (private.rol_crm(v_uid) in ('gerencia','coordinador') or private.es_lector_global()
      or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (l.vendedor_id is null and l.asignado_supervisor_id
        in (select private.vendedor_ids_visibles(v_uid))));
$despues$);
  if md5(v_def) not in ('cd5eb069c20b53193aafe8d6912fb4cd') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

-- private.sla_operacion_autorizada(uuid[], boolean)
do $cambio$
declare v_def text := pg_get_functiondef(to_regprocedure('private.sla_operacion_autorizada(uuid[], boolean)'));
begin
  if v_def is null or md5(v_def) not in ('ea7ee548df90a8ce4f64d3349e37fb25') then
    raise exception 'Cambió private.sla_operacion_autorizada; revisar antes de aplicar' using errcode='P0409';
  end if;
  v_def := replace(v_def, $antes$  if p_incluir_operacion is null or array_position(p_lead_ids,null) is not null then
    raise exception 'Entrada SLA invalida' using errcode='22023';
  end if;
  v_global:=(v_rol='gerencia') or coalesce(v_global,false);
  v_visibles:=array(select x from private.vendedor_ids_visibles(v_uid) x order by x);
  if not p_incluir_operacion then
    select coalesce(jsonb_agg(h.base order by h.lead_id),'[]'::jsonb) into v_filas
$antes$, $despues$  if p_incluir_operacion is null or array_position(p_lead_ids,null) is not null then
    raise exception 'Entrada SLA invalida' using errcode='22023';
  end if;
  v_global:=(v_rol in ('gerencia','coordinador')) or coalesce(v_global,false);
  v_visibles:=array(select x from private.vendedor_ids_visibles(v_uid) x order by x);
  if not p_incluir_operacion then
    select coalesce(jsonb_agg(h.base order by h.lead_id),'[]'::jsonb) into v_filas
$despues$);
  if md5(v_def) not in ('26216085857a74fcbb010ef53e8d6e69') then
    raise exception 'No coincidieron todos los anclajes SQL de la migración' using errcode='P0409';
  end if;
  execute v_def;
end; $cambio$;

notify pgrst,'reload schema';
commit;
