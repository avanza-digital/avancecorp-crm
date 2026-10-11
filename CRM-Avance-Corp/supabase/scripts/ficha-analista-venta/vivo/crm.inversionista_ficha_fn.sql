CREATE OR REPLACE FUNCTION crm.inversionista_ficha_fn(p_inversionista uuid, p_pagina_inversiones integer DEFAULT 1, p_pagina_historial integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p record; v_id uuid; v_resultado jsonb; v_lector boolean:=private.es_lector_global();
  v_operable boolean:=false; v_motivo text; v_cuentas jsonb; v_postventa boolean:=false;
begin
  perform private.cartera_f5_exigir();
  if p_pagina_inversiones is null or p_pagina_inversiones<1 or p_pagina_inversiones>1000000
    or p_pagina_historial is null or p_pagina_historial<1 or p_pagina_historial>1000000 then
    raise exception 'Página inválida' using errcode='22023';
  end if;
  v_id:=private.inversionista_canonica(p_inversionista);
  select * into v_p from private.cartera_f5_personas_visibles(v_id) where inversionista_id=v_id;
  if not found then return null; end if;
  if not v_lector then
    begin
      v_postventa:=(crm.postventa_estado_fn()->>'habilitada')::boolean and private.postventa_visible(v_id);
    exception when serialization_failure or lock_not_available or sqlstate 'PT409' then v_postventa:=false;
    end;
  end if;
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
    select * from private.cartera_f5_fuentes_reales() f where f.inversionista_id=v_id
      and (not v_lector or f.empresa='avance')
  ), pagina as materialized (
    select * from fuentes order by empresa,moneda,creado_en desc,fuente_id
    limit 25 offset (p_pagina_inversiones-1)*25
  ), historial as materialized (
    select a.id,'lead'::text origen,a.tipo,a.detalle,a.creado_en,null::text empresa
      from crm.actividades a where a.lead_id=any(v_p.lead_ids) and not v_lector
        and not (v_postventa and exists(select 1 from crm.inversionista_gestiones g
          where g.id::text=a.metadata->>'postventa_gestion_id'
            and private.inversionista_canonica(g.inversionista_id)=v_id))
    union all
    -- Directorio ya lee actividades_cliente y tareas de clientes Avance por
    -- sus policies publicadas; se excluyen aquí los antecedentes de leads.
    select a.id,'cliente',a.tipo,a.detalle,a.creado_en,'avance'::text empresa
      from crm.actividades_cliente a where a.cliente_id=any(v_p.perfil_ids)
    union all
    select g.id,'postventa',g.tipo,g.detalle,g.creado_en,g.empresa
      from crm.inversionista_gestiones g where v_postventa
        and private.inversionista_canonica(g.inversionista_id)=v_id
  ), tareas as materialized (
    select t.id,t.tipo,t.titulo,t.vence_en,t.estado,t.inversionista_id,t.postventa_revision
    from crm.tareas t where t.activo and (t.perfil_id=any(v_p.perfil_ids)
      or (not v_lector and t.lead_id=any(v_p.lead_ids))
      or (v_postventa and private.inversionista_canonica(t.inversionista_id)=v_id))
  )
  select jsonb_build_object('version',1,
    'persona',to_jsonb(v_p)-'perfil_ids'-'lead_ids',
    'identidad_fusionada',p_inversionista is distinct from v_id,
    'capacidades',jsonb_build_object('postventa',v_postventa,'nueva_inversion',v_operable,
      'motivo_no_operable',v_motivo,'contactar',not v_lector and v_p.estado='activo' and not v_p.no_contactar,
      'cuentas_perfil_ids',v_cuentas,'documentos',not v_lector),
    'inversiones',coalesce((select jsonb_agg(to_jsonb(f)-'identidad_coherente'||jsonb_build_object(
      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),
      'condiciones_coopac',case when f.empresa<>'avance' then (select
        jsonb_build_object('plazo_meses',ce.plazo_meses,'tasa_anual',ce.tasa_anual)
        from crm.cierres_externos ce where ce.id=f.fuente_id
          and ce.plazo_meses is not null and ce.tasa_anual is not null) end,
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
    'continuidad',jsonb_build_object('proximo_vencimiento',(
      select coalesce(max(f.vence_en) filter(where f.vence_en<=(now() at time zone 'America/Lima')::date),
        min(f.vence_en) filter(where f.vence_en>(now() at time zone 'America/Lima')::date))
      from fuentes f where f.estado in ('activo','vigente','vencido') and isfinite(f.vence_en))),
    'inversiones_total',(select count(*) from fuentes),'pagina_inversiones',p_pagina_inversiones,
    'totales',coalesce((select jsonb_agg(x.d order by x.empresa,x.moneda) from (
      select f.empresa,f.moneda,jsonb_build_object('empresa',f.empresa,'moneda',f.moneda,'cantidad',count(*),
        'capital_registrado',coalesce(sum(f.capital) filter(where not f.es_demo),0),
        'capital_activo',case when f.empresa='avance' then coalesce(sum(f.capital)
          filter(where not f.es_demo and f.estado='activo'
            and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)),0) end) d
      from fuentes f group by f.empresa,f.moneda) x),'[]'),
    'historial',coalesce((select jsonb_agg(to_jsonb(h) order by h.creado_en desc,h.id,h.origen) from (
      select * from historial order by creado_en desc,id,origen limit 25 offset (p_pagina_historial-1)*25) h),'[]'),
    'historial_total',(select count(*) from historial),'pagina_historial',p_pagina_historial,
    'tareas',coalesce((select jsonb_agg(to_jsonb(t) order by t.vence_en,t.id) from (
      select * from tareas where estado='pendiente' order by vence_en,id limit 25) t),'[]'),
    'tareas_total',(select count(*) from tareas where estado='pendiente')) into v_resultado;
  perform private.cartera_f5_exigir();
  if not exists(select 1 from private.cartera_f5_personas_visibles(v_id) p where p.inversionista_id=v_id) then
    return null;
  end if;
  perform private.cartera_f5_registrar('ficha',v_id);
  return v_resultado;
end;
$function$
