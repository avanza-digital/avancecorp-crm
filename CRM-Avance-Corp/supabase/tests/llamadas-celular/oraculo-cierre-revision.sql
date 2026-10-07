-- Regresiones de la duodécima, sobre el banco reducido: todo sintético y ROLLBACK.
begin;
do $oraculo$
declare
  a1 uuid := '00000000-0000-0000-0000-0000000000a1';
  a3 uuid := '00000000-0000-0000-0000-0000000000a3';
  b2 uuid := '00000000-0000-0000-0000-0000000000b2';
  b1 uuid := '00000000-0000-0000-0000-0000000000b1';
  g1 uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 uuid := '00000000-0000-0000-0000-0000000000c1';
  viejo uuid := gen_random_uuid();
  k text; r jsonb; x text; y text; e uuid; op uuid := gen_random_uuid();
begin
  perform set_config('request.jwt.claim.sub', g1::text, true);
  k := crm.asignar_celular('C1',a1)->>'credencial';
  perform set_config('request.jwt.claim.sub', a1::text, true);
  insert into crm.leads(id,nombre_completo,telefono,vendedor_id,etapa,motivo_descarte,descartado_en)
  values (viejo,'Descarte sintético','+51900000001',a3,'descartado','otro',now()-interval '40 days');
  if cardinality(private.llamada_celular_candidatos_dueno(a3,array['+51900000001'],now())) <> 0 then
    raise exception 'CIERRE: el descarte antiguo elude el lead abierto ajeno';
  end if;
  update crm.leads set telefono='+51900000999' where id=viejo;
  if not (viejo = any(private.llamada_celular_candidatos_dueno(a1,array['+51900000999'],now()))) then
    raise exception 'CIERRE: el reutilizable permitido desapareció';
  end if;
  if private.llamada_celular_visible(a3,viejo,a1) or private.llamada_celular_visible(b2,viejo,a1)
     or not private.llamada_celular_visible(g1,viejo,a1) then
    raise exception 'CIERRE: visibilidad del antiguo dueño o gerencia';
  end if;
  update crm.leads set vendedor_id=a1, etapa='nuevo', motivo_descarte=null where id=viejo;
  if not private.llamada_celular_visible(a1,viejo,a1) then raise exception 'CIERRE: no aparece a quien lo tomó'; end if;
  update crm.leads set no_contactar=true where id=viejo;
  if cardinality(private.llamada_celular_candidatos_dueno(a1,array['+51900000999'],now())) <> 0 then
    raise exception 'CIERRE: no contactar pasó';
  end if;
  update crm.leads set no_contactar=false,vetada_en_banco=true where id=viejo;
  if cardinality(private.llamada_celular_candidatos_dueno(a1,array['+51900000999'],now())) <> 0 then
    raise exception 'CIERRE: persona vetada pasó';
  end if;
  update crm.leads set vetada_en_banco=false where id=viejo;
  if not (viejo = any(private.llamada_celular_candidatos_dueno(a1,array['+51900000999'],now()))) then
    raise exception 'CIERRE: faltó control positivo antes del cliente';
  end if;
  update crm.leads set etapa='descartado',descartado_en=now()-interval '40 days',motivo_descarte='otro' where id=viejo;
  perform set_config('request.jwt.claim.sub', b1::text, true);
  if not private.llamada_celular_visible(b1,viejo,b1) then raise exception 'CIERRE: supervisor perdió su propia llamada tras descartar'; end if;
  perform set_config('request.jwt.claim.sub', a1::text, true);
  insert into public.perfiles(id,nombre_completo,rol,telefono) values(gen_random_uuid(),'Cliente sintético','cliente','900000999');
  if cardinality(private.llamada_celular_candidatos_dueno(a1,array['+51900000999'],now())) <> 0 then
    raise exception 'CIERRE: cliente pasó';
  end if;

  -- El veto no debe confundirse con número desconocido aunque la política permita guardarlos.
  update crm.llamadas_celular_politica set guardar_sin_identificar=true;
  x := 'C1-' || (floor(extract(epoch from now()))::bigint-200);
  r := crm.ingerir_llamada_celular_servicio(k,jsonb_build_object('v',1,'evento_origen_id',x,'numero','900000999','direccion','saliente'));
  if r->>'resultado' is distinct from 'aceptado' or exists(select 1 from crm.llamadas_celular_eventos where evento_origen_id=x) then
    raise exception 'CIERRE: cliente guardado por política sin identificar';
  end if;
  update crm.llamadas_celular_politica set guardar_sin_identificar=false;
  x := 'C1-' || (floor(extract(epoch from now()))::bigint-100);
  y := 'C1-' || (floor(extract(epoch from now()))::bigint-99);
  perform set_config('request.jwt.claim.sub', a1::text, true);
  r := crm.registrar_llamada_v5(op,c1,'no_contesto',p_evento_origen_id=>x,p_via=>'al_colgar');
  if r->'enlace'->>'estado' is distinct from 'pendiente' then raise exception 'CIERRE: no reservó X'; end if;
  perform crm.ingerir_llamada_celular_servicio(k,jsonb_build_object('v',1,'evento_origen_id',y,'numero','900000001','direccion','saliente'));
  select id into e from crm.llamadas_celular_eventos where evento_origen_id=y;
  if private.llamadas_celular_bandeja(a1,50,null,null)->'filas'->0->>'evento_origen_id' is distinct from y
     or private.llamada_celular_detalle(a1,e)->>'evento_origen_id' is distinct from y then
    raise exception 'CIERRE: lecturas sin id de origen';
  end if;
  r := crm.registrar_llamada_v5(op,c1,'no_contesto',p_evento_origen_id=>y,p_via=>'pestana');
  if r->'enlace'->>'estado' is distinct from 'enlazado'
     or exists(select 1 from private.llamadas_celular_intenciones where actividad_id=op) then
    raise exception 'CIERRE: enlazar Y dejó la intención X';
  end if;
  perform crm.ingerir_llamada_celular_servicio(k,jsonb_build_object('v',1,'evento_origen_id',x,'numero','900000001','direccion','saliente'));
  if (select count(*) from crm.llamadas_celular_enlaces where actividad_id=op) <> 1 then raise exception 'CIERRE: resultado duplicado'; end if;
  if private.llamadas_celular_resueltas_hoy(a1,50,now(),null,null)->'filas'->0->>'evento_origen_id' is distinct from y
     or private.actividades_con_llamada_celular(a1,array[op])->0->>'evento_origen_id' is distinct from y then
    raise exception 'CIERRE: resueltas o marca sin id';
  end if;
  raise notice 'ORACULO CIERRE REVISION OK';
end;
$oraculo$;
rollback;
