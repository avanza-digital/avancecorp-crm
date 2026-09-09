-- F5: cartera y ficha multiempresa. Candidata revisable; no encender producción.
-- Prerrequisito: revisión publicada F4 20260908211349 (no su candidata anterior).
-- Este archivo es generado por scripts/f5/generar-migracion.mjs.
do $pre$
begin
  if to_regprocedure('crm.confirmar_inversion_revisada_fn(uuid,integer)') is null
    or to_regprocedure('private.inversion_persona_contexto(uuid)') is null then
    raise exception 'Falta el prerrequisito publicado de F4';
  end if;
  if not exists(select 1 from crm.multiempresa_flags where nombre='ficha_360_neutral')
    or exists(select 1 from crm.multiempresa_flags where nombre='ficha_360_neutral' and activo) then
    raise exception 'Instalar F5 con su bandera existente apagada';
  end if;
end;
$pre$;

-- F5: lecturas neutrales. Este módulo se ensaya únicamente en el banco F5.
-- La candidata publicable se ensambla después de G5; ninguna bandera se enciende aquí.
create table if not exists crm.cartera_lecturas (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.perfiles(id),
  inversionista_id uuid references crm.inversionistas(id),
  tipo text not null check (tipo in ('lista','ficha','cuentas','documento')),
  creado_en timestamptz not null default statement_timestamp()
);
alter table crm.cartera_lecturas enable row level security;
revoke all on crm.cartera_lecturas from public, anon, authenticated, service_role;
create index if not exists cartera_lecturas_actor_fecha_idx
  on crm.cartera_lecturas(actor_id, creado_en desc);
create index if not exists cartera_lecturas_persona_fecha_idx
  on crm.cartera_lecturas(inversionista_id, creado_en desc);
drop trigger if exists trg_audit_cartera_lecturas on crm.cartera_lecturas;
create trigger trg_audit_cartera_lecturas after insert on crm.cartera_lecturas
  for each row execute function private.log_audit_crm();

-- Acceso continuado: un evento por actor/persona/categoría cada 60 segundos.
-- Refrescos de permisos y doble comprobación documental no multiplican el log.
-- El candado solo serializa este registro breve, después de autorizar la lectura.
create or replace function private.cartera_f5_registrar(p_tipo text,p_persona uuid default null)
returns void language plpgsql security definer set search_path=''
as $f$
declare v_actor uuid:=(select auth.uid());
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    concat_ws(':','f5-lectura',v_actor,p_tipo,p_persona),0));
  insert into crm.cartera_lecturas(actor_id,inversionista_id,tipo)
    select v_actor,p_persona,p_tipo where not exists (
      select 1 from crm.cartera_lecturas l where l.actor_id=v_actor and l.tipo=p_tipo
        and l.inversionista_id is not distinct from p_persona
        and l.creado_en>=statement_timestamp()-interval '60 seconds');
end;
$f$;

-- Una fila por FUENTE. Los vínculos aportan identidad, jamás otro capital.
-- Un enlace contradictorio produce identidad_coherente=false y bloquea F5.
create or replace function private.cartera_f5_fuentes()
returns table (
  fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text,
  perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text,
  estado text, fecha_comercial date, fecha_imputacion date, vence_en date,
  analista_origen_id uuid, es_inicial boolean, es_demo boolean,
  identidad_coherente boolean, creado_en timestamptz
)
language sql stable security definer set search_path=''
as $f$
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce(private.analista_atribuido_cadena(c.id),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$f$;

-- Una lectura no reclama identidades ni hace backfill. La cobertura es un gate.
create or replace function crm.cartera_inversionistas_estado_fn()
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
declare
  v_uid uuid:=(select auth.uid());
  v_rol text:=private.rol_crm(v_uid);
  v_lector boolean:=private.es_lector_global();
  v_f3 boolean; v_f5 boolean; v_cobertura boolean;
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia') or v_lector,false) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  select coalesce(bool_or(activo) filter(where nombre='resolver_en_puertas'),false),
         coalesce(bool_or(activo) filter(where nombre='ficha_360_neutral'),false)
    into v_f3,v_f5 from crm.multiempresa_flags;
  -- OFF no depende del censo ni escanea fuentes: deja disponible el recorrido publicado.
  if not v_f3 or not v_f5 then
    return jsonb_build_object('version',1,'habilitada',false,
      'escritura_habilitada',false,'motivo','La cartera multiempresa aún no está habilitada');
  end if;
  select not exists (
    select 1 from private.cartera_f5_fuentes() f
    left join crm.inversionistas i on i.id=f.inversionista_id
    where not coalesce(f.identidad_coherente,false) or i.id is null
      or i.inversionista_canonico_id is not null
  ) into v_cobertura;
  return jsonb_build_object('version',1,'habilitada',v_cobertura,
    'escritura_habilitada',v_cobertura and not v_lector
      and private.puede_gestionar_contratos_crm()
      and coalesce((select activo from crm.multiempresa_flags where nombre='inversiones_escritura'),false),
    'motivo',case when not v_cobertura then 'La cartera requiere conciliación antes de habilitarse' end);
end;
$f$;

create or replace function private.cartera_f5_exigir()
returns void language plpgsql security definer set search_path=''
as $f$
begin
  if not (crm.cartera_inversionistas_estado_fn()->>'habilitada')::boolean then
    raise exception 'La cartera multiempresa no está disponible; vuelve a cargar' using errcode='P0409';
  end if;
end;
$f$;

-- Autorizar ANTES de buscar, contar, agregar o paginar. Nunca usar el vendedor
-- histórico de una inversión como propietario de la relación actual.
create or replace function private.cartera_f5_personas_visibles()
returns table (
  inversionista_id uuid, nombre text, documento_tipo text, documento text,
  documento_verificado boolean, telefono text, correo text, estado text,
  no_contactar boolean, responsable_id uuid, responsable_nombre text,
  perfil_id uuid, perfil_ids uuid[], lead_ids uuid[], creado_en timestamptz
)
language sql stable security definer set search_path=''
as $f$
  with actor as materialized (
    select (select auth.uid()) uid,private.rol_crm((select auth.uid())) rol,
      private.es_lector_global() lector,
      array(select private.vendedor_ids_visibles((select auth.uid()))) visibles
  ), fuentes as materialized (select * from private.cartera_f5_fuentes()),
  autorizadas as materialized (
    select i.*,a.lector
    from crm.inversionistas i cross join actor a
    where a.uid is not null and i.inversionista_canonico_id is null
      and (a.rol in ('vendedor','supervisor','gerencia') or a.lector)
      and (a.rol='gerencia'
        or (not a.lector and i.responsable_relacion_id=any(a.visibles))
        or (a.rol='supervisor' and i.responsable_relacion_id is null and exists (
          select 1 from crm.leads l where l.activo and l.vendedor_id is null
            and l.asignado_supervisor_id=a.uid
            and private.inversionista_canonica(l.inversionista_id)=i.id))
        or (a.lector and exists (
          select 1 from crm.inversionistas h
          join private.cliente_ids_visibles_crm() v on v.cliente_id=h.perfil_id
          where private.inversionista_canonica(h.id)=i.id)))
      and (exists (select 1 from fuentes f where f.inversionista_id=i.id)
        or exists (select 1 from crm.inversionistas h
          join public.perfiles p on p.id=h.perfil_id and p.rol='cliente'
          where private.inversionista_canonica(h.id)=i.id))
  )
  select i.id,
    coalesce(nullif(btrim(p.nombre_completo),''),nullif(btrim(l.nombre_completo),''),
      nullif(btrim(ce.nombre_completo),''),'Identidad pendiente de completar'),
    case when i.lector then p.tipo_documento else d.tipo_documento end,
    case when i.lector then p.dni else d.documento_normalizado end,
    coalesce(d.verificado and (not i.lector or (d.tipo_documento=p.tipo_documento and d.documento_normalizado=p.dni)),false),
    coalesce(p.telefono,case when not i.lector then l.telefono end),
    coalesce(p.correo,case when not i.lector then l.correo end),
    i.estado,i.no_contactar or coalesce(l.no_contactar,false),
    i.responsable_relacion_id,r.nombre_completo,i.perfil_id,
    coalesce(enlaces.perfiles,'{}'::uuid[]),coalesce(enlaces.leads,'{}'::uuid[]),i.creado_en
  from autorizadas i
  left join public.perfiles r on r.id=i.responsable_relacion_id
  cross join lateral (
    select array(select distinct h.perfil_id from crm.inversionistas h
      join public.perfiles hp on hp.id=h.perfil_id and hp.rol='cliente'
      where private.inversionista_canonica(h.id)=i.id
        and (not i.lector or exists(select 1 from private.cliente_ids_visibles_crm() v where v.cliente_id=hp.id))) perfiles,
      array(select distinct x.id from (
        select l0.id from crm.leads l0 where private.inversionista_canonica(l0.inversionista_id)=i.id
        union select il.lead_id from crm.inversionista_leads il
          where private.inversionista_canonica(il.inversionista_id)=i.id
      ) x) leads
  ) enlaces
  left join lateral (
    select p0.* from public.perfiles p0 where p0.id=any(enlaces.perfiles)
      and (not i.lector or p0.rol='cliente')
    order by (p0.id=i.perfil_id) desc,p0.activo desc,p0.id limit 1
  ) p on true
  left join lateral (
    select l0.* from crm.leads l0 where l0.id=any(enlaces.leads)
      and (not i.lector)
    order by (l0.inversionista_id=i.id) desc,l0.actualizado_en desc,l0.id limit 1
  ) l on true
  left join lateral (
    select ce0.nombre_completo from crm.cierres_externos ce0
      join fuentes f on f.fuente_id=ce0.id and f.empresa<>'avance'
    where f.inversionista_id=i.id and not i.lector
    order by ce0.creado_en desc,ce0.id limit 1
  ) ce on true
  left join lateral (
    select d0.* from crm.inversionista_identificadores d0
    where d0.inversionista_id=i.id and d0.estado='vigente'
    order by d0.verificado desc,case d0.tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,d0.id
    limit 1
  ) d on true;
$f$;

create or replace function crm.cartera_inversionistas_fn(
  p_pagina integer default 1,p_tamano integer default 25,p_texto text default '',
  p_empresa text default null,p_responsable uuid default null,p_sin_responsable boolean default false
)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare v_resultado jsonb; v_texto text:=lower(btrim(coalesce(p_texto,'')));
  v_lector boolean:=private.es_lector_global();
begin
  perform private.cartera_f5_exigir();
  if p_pagina is null or p_pagina<1 or p_pagina>1000000
    or p_tamano is null or p_tamano not in (10,25,50)
    or length(v_texto)>120 or v_texto~'[[:cntrl:]]'
    or (p_empresa is not null and p_empresa not in ('avance','qorilazo','prodelco'))
    or p_sin_responsable is null or (p_sin_responsable and p_responsable is not null) then
    raise exception 'Filtros de cartera inválidos' using errcode='22023';
  end if;
  with personas as materialized (select * from private.cartera_f5_personas_visibles()),
  fuentes as materialized (
    select f.* from private.cartera_f5_fuentes() f
    join personas p on p.inversionista_id=f.inversionista_id
    where not v_lector or f.empresa='avance'
  ), filtradas as materialized (
    select p.* from personas p
    where (p_responsable is null or p.responsable_id=p_responsable)
      and (not p_sin_responsable or p.responsable_id is null)
      and (p_empresa is null or exists(select 1 from fuentes f where f.inversionista_id=p.inversionista_id and f.empresa=p_empresa))
      -- strpos interpreta % y _ literalmente: no son comodines de enumeración.
      and (v_texto='' or strpos(lower(concat_ws(' ',p.nombre,p.documento,p.telefono,p.correo)),v_texto)>0
        or exists(select 1 from fuentes f where f.inversionista_id=p.inversionista_id and strpos(f.empresa,v_texto)>0))
  ), pagina as materialized (
    select * from filtradas order by lower(nombre),inversionista_id
    limit p_tamano offset (p_pagina-1)*p_tamano
  ), totales as (
    select f.empresa,f.moneda,count(*) cantidad,
      sum(f.capital) filter(where not f.es_demo) capital_registrado,
      sum(f.capital) filter(where not f.es_demo and f.empresa='avance' and f.estado='activo'
        and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)) capital_activo
    from fuentes f join filtradas p using(inversionista_id)
    where p_empresa is null or f.empresa=p_empresa group by f.empresa,f.moneda
  )
  select jsonb_build_object('version',1,'pagina',p_pagina,'tamano',p_tamano,
    'total',(select count(*) from filtradas),
    'filas',coalesce((select jsonb_agg(
      (to_jsonb(p)-'perfil_ids'-'lead_ids'-'perfil_id')||jsonb_build_object('empresas',
        coalesce((select jsonb_agg(x.empresa order by x.empresa) from (
          select distinct f.empresa from fuentes f where f.inversionista_id=p.inversionista_id) x),'[]'))
      order by lower(p.nombre),p.inversionista_id) from pagina p),'[]'),
    'totales',coalesce((select jsonb_agg(jsonb_build_object('empresa',t.empresa,'moneda',t.moneda,
      'cantidad',t.cantidad,'capital_registrado',coalesce(t.capital_registrado,0),
      'capital_activo',case when t.empresa='avance' then coalesce(t.capital_activo,0) end)
      order by t.empresa,t.moneda) from totales t),'[]')) into v_resultado;
  perform private.cartera_f5_registrar('lista');
  return v_resultado;
end;
$f$;

create or replace function crm.inversionista_ficha_fn(p_inversionista uuid,
  p_pagina_inversiones integer default 1,p_pagina_historial integer default 1)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb;
begin
  perform private.cartera_f5_exigir();
  if p_pagina_inversiones is null or p_pagina_inversiones<1 or p_pagina_inversiones>1000000
    or p_pagina_historial is null or p_pagina_historial<1 or p_pagina_historial>1000000 then
    raise exception 'Página inválida' using errcode='22023';
  end if;
  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles() where inversionista_id=v_id;
  if not found then return null; end if;
  -- Contexto F4 es la autoridad operativa: revisa documento, responsable, veto,
  -- perfil y lead canónico. Su lock no se toma para una lectura de Directorio.
  if not v_lector and (crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada')::boolean then
    begin
      perform private.inversion_persona_contexto(v_id);
      v_operable:=true;
    exception when sqlstate 'P0409' or sqlstate 'P0429' then v_motivo:=sqlerrm;
      when lock_not_available or deadlock_detected then
        v_operable:=false;v_motivo:='Hay una actualización en curso. Revisa la ficha antes de registrar otra inversión';
      when insufficient_privilege then v_motivo:='Revisa la asignación antes de registrar otra inversión';
    end;
  else v_motivo:=case when v_lector then 'Acceso de solo lectura' else 'El registro de inversiones aún no está habilitado' end;
  end if;
  select coalesce(jsonb_agg(p.id order by p.id),'[]') into v_cuentas
  from public.perfiles p where p.id=any(v_p.perfil_ids) and not v_lector
    and private.puede_gestionar_cuentas_cliente(p.id);
  with fuentes as materialized (
    select * from private.cartera_f5_fuentes() f where f.inversionista_id=v_id
      and (not v_lector or f.empresa='avance')
  ), pagina as materialized (
    select * from fuentes order by empresa,moneda,creado_en desc,fuente_id
    limit 25 offset (p_pagina_inversiones-1)*25
  ), historial as materialized (
    select a.id,'lead'::text origen,a.tipo,a.detalle,a.creado_en
      from crm.actividades a where a.lead_id=any(v_p.lead_ids) and not v_lector
    union all
    -- Directorio ya lee actividades_cliente y tareas de clientes Avance por
    -- sus policies publicadas; se excluyen aquí los antecedentes de leads.
    select a.id,'cliente',a.tipo,a.detalle,a.creado_en
      from crm.actividades_cliente a where a.cliente_id=any(v_p.perfil_ids)
  ), tareas as materialized (
    select t.id,t.tipo,t.titulo,t.vence_en,t.estado
    from crm.tareas t where t.activo and (t.perfil_id=any(v_p.perfil_ids)
      or (not v_lector and t.lead_id=any(v_p.lead_ids)))
  )
  select jsonb_build_object('version',1,
    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      'contrato',case when f.empresa='avance' then (select jsonb_build_object(
        'fecha_inicio',c.fecha_inicio,'tasa_anual',c.tasa_anual,'modalidad',c.modalidad,
        'tipo_interes',c.tipo_interes,'categoria',c.categoria)
        from public.contratos c where c.id=f.fuente_id) end,
      'pdf',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then (
        select jsonb_build_object('estado',s->>'estado','reintentable',(s->>'reintentable')::boolean)
        from (select private.contrato_pdf_estado_base(f.fuente_id) s) x) end,
      'documentos',case when v_lector or (f.empresa='avance' and not private.puede_leer_contrato_pdf(f.fuente_id))
        then '[]'::jsonb when f.empresa='avance' then coalesce((
        select jsonb_agg(jsonb_build_object('id',d.id,'nombre',d.nombre,'tipo',d.tipo)
          order by d.creado_en desc,d.id) from public.documentos d where d.contrato_id=f.fuente_id),'[]')
        ||case when private.contrato_pdf_archivo_base(f.fuente_id) is not null then
          jsonb_build_array(jsonb_build_object('id',f.fuente_id,'nombre','Contrato vigente','tipo','contrato_pdf'))
          else '[]'::jsonb end
        else coalesce((select jsonb_build_array(jsonb_build_object('id',ce.comprobante_objeto_id,
          'nombre','Comprobante de depósito','tipo','comprobante')) from crm.cierres_externos ce
          where ce.id=f.fuente_id and ce.comprobante_objeto_id is not null),'[]') end,
      'cotitulares',case when f.empresa='avance' and not v_lector and private.puede_leer_contrato_pdf(f.fuente_id) then coalesce((
        select jsonb_agg(jsonb_build_object('orden',t.orden,'nombre',t.nombre_completo,
          'tipo_documento',t.tipo_documento,'documento',t.documento) order by t.orden,t.id)
        from public.contrato_titulares t where t.contrato_id=f.fuente_id),'[]') else '[]'::jsonb end,
      'proxima_cuota',case when f.empresa='avance' then (
        select jsonb_build_object('fecha',c.fecha_programada,'moneda',f.moneda,
          'monto',c.monto_programado,'estado',c.estado,'tipo',c.tipo)
        from public.cronograma_pagos c where c.contrato_id=f.fuente_id and c.estado='pendiente'
        order by c.fecha_programada,c.numero_cuota,c.id limit 1) end,
      'numero_transaccion',case when not v_lector and f.empresa<>'avance' then
        (select ce.numero_transaccion from crm.cierres_externos ce where ce.id=f.fuente_id) end)
      order by f.empresa,f.moneda,f.creado_en desc,f.fuente_id) from pagina f),'[]'),
    'inversiones_total',(select count(*) from fuentes),'pagina_inversiones',p_pagina_inversiones,
    'totales',coalesce((select jsonb_agg(x.d order by x.empresa,x.moneda) from (
      select f.empresa,f.moneda,jsonb_build_object('empresa',f.empresa,'moneda',f.moneda,'cantidad',count(*),
        'capital_registrado',coalesce(sum(f.capital) filter(where not f.es_demo),0),
        'capital_activo',case when f.empresa='avance' then coalesce(sum(f.capital)
          filter(where not f.es_demo and f.estado='activo'
            and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)),0) end) d
      from fuentes f group by f.empresa,f.moneda) x),'[]'),
    'historial',coalesce((select jsonb_agg(to_jsonb(h) order by h.creado_en desc,h.id) from (
      select * from historial order by creado_en desc,id limit 25 offset (p_pagina_historial-1)*25) h),'[]'),
    'historial_total',(select count(*) from historial),'pagina_historial',p_pagina_historial,
    'tareas',coalesce((select jsonb_agg(to_jsonb(t) order by t.vence_en,t.id) from (
      select * from tareas where estado='pendiente' order by vence_en,id limit 25) t),'[]'),
    'tareas_total',(select count(*) from tareas where estado='pendiente')) into v_resultado;
  perform private.cartera_f5_exigir();
  if not exists(select 1 from private.cartera_f5_personas_visibles() p where p.inversionista_id=v_id) then
    return null;
  end if;
  perform private.cartera_f5_registrar('ficha',v_id);
  return v_resultado;
end;
$f$;

-- Los IDs proceden de la ficha, pero se verifican otra vez en cada lectura.
create or replace function crm.inversionista_cuentas_fn(p_inversionista uuid,p_perfil uuid,p_moneda text)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare v_p record; v_r jsonb;
begin
  perform private.cartera_f5_exigir();
  if private.es_lector_global() then raise exception 'No autorizado' using errcode='42501'; end if;
  select * into v_p from private.cartera_f5_personas_visibles()
    where inversionista_id=private.inversionista_canonica(p_inversionista);
  if not found or not coalesce(p_perfil=any(v_p.perfil_ids),false)
    or not private.puede_gestionar_cuentas_cliente(p_perfil) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_moneda is null or p_moneda not in ('PEN','USD') then
    raise exception 'Moneda inválida' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(c)),'[]') into v_r
    from crm.cuentas_bancarias_cliente_fn(p_perfil,p_moneda) c;
  perform private.cartera_f5_registrar('cuentas',v_p.inversionista_id);
  return v_r;
end;
$f$;

create or replace function crm.inversionista_documento_fn(p_inversionista uuid,p_fuente uuid,p_documento uuid)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare v_id uuid;v_f record;v_r jsonb;v_pdf jsonb;
begin
  perform private.cartera_f5_exigir();
  if private.es_lector_global() then raise exception 'No autorizado' using errcode='42501'; end if;
  select p.inversionista_id into v_id from private.cartera_f5_personas_visibles() p
    where p.inversionista_id=private.inversionista_canonica(p_inversionista);
  if v_id is null then raise exception 'No autorizado' using errcode='42501'; end if;
  select * into v_f from private.cartera_f5_fuentes() f where f.fuente_id=p_fuente and f.inversionista_id=v_id;
  if not found then return null; end if;
  if v_f.empresa='avance' then
    -- El PDF incorpora banca: conservar además su capacidad documental vigente.
    if not private.puede_leer_contrato_pdf(p_fuente) then
      raise exception 'No autorizado' using errcode='42501';
    end if;
    if p_documento=p_fuente then
      v_pdf:=private.contrato_pdf_estado_base(p_fuente);
      if v_pdf->>'estado'='integridad_bloqueada' then
        raise exception 'El archivo contractual requiere revisión por integridad' using errcode='55000';
      end if;
      if v_pdf->>'estado'='sellado' then
        v_pdf:=private.contrato_pdf_archivo_base(p_fuente);
        v_r:=jsonb_build_object('bucket',v_pdf->>'storage_bucket','ruta',v_pdf->>'storage_path',
          'nombre',v_pdf->>'nombre_archivo','sha256',v_pdf->>'sha256','bytes',(v_pdf->>'bytes')::bigint);
      end if;
    else
      select jsonb_build_object('bucket','documentos','ruta',d.storage_path,'nombre',d.nombre)
        into v_r from public.documentos d where d.id=p_documento and d.contrato_id=p_fuente;
    end if;
  else
    select jsonb_build_object('bucket',o.bucket_id,'ruta',o.name,'nombre','Comprobante de depósito')
      into v_r from crm.cierres_externos ce join storage.objects o on o.id=ce.comprobante_objeto_id
      where ce.id=p_fuente and o.id=p_documento and o.bucket_id='f4-comprobantes';
  end if;
  if v_r is not null then
    perform private.cartera_f5_registrar('documento',v_id);
  end if;
  return v_r;
end;
$f$;

revoke all on function private.cartera_f5_fuentes() from public,anon,authenticated,service_role;
revoke all on function private.cartera_f5_registrar(text,uuid) from public,anon,authenticated,service_role;
revoke all on function private.cartera_f5_exigir() from public,anon,authenticated,service_role;
revoke all on function private.cartera_f5_personas_visibles() from public,anon,authenticated,service_role;
revoke all on function crm.cartera_inversionistas_estado_fn() from public,anon,authenticated,service_role;
revoke all on function crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function crm.inversionista_ficha_fn(uuid,integer,integer) from public,anon,authenticated,service_role;
revoke all on function crm.inversionista_cuentas_fn(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function crm.inversionista_documento_fn(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function crm.cartera_inversionistas_estado_fn() to authenticated;
grant execute on function crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean) to authenticated;
grant execute on function crm.inversionista_ficha_fn(uuid,integer,integer) to authenticated;
grant execute on function crm.inversionista_cuentas_fn(uuid,uuid,text) to authenticated;
grant execute on function crm.inversionista_documento_fn(uuid,uuid,uuid) to authenticated;

-- Sin grants de tabla ni permisos de escritura nuevos. La API solo ejecuta RPC.
do $post$
declare n integer;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where (ns.nspname='crm' and p.proname in ('cartera_inversionistas_estado_fn','cartera_inversionistas_fn',
    'inversionista_ficha_fn','inversionista_cuentas_fn','inversionista_documento_fn')
    or ns.nspname='private' and p.proname in ('cartera_f5_fuentes','cartera_f5_exigir','cartera_f5_personas_visibles','cartera_f5_registrar'))
    and p.prosecdef and p.proconfig=array['search_path=""'];
  if n<>9 or not (select relrowsecurity from pg_class where oid='crm.cartera_lecturas'::regclass)
    or has_table_privilege('authenticated','crm.cartera_lecturas','SELECT') then
    raise exception 'Postflight F5: revisar funciones, search_path, RLS y ACL';
  end if;
end;
$post$;
notify pgrst, 'reload schema';
