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
