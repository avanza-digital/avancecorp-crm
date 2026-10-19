-- Regresión del PR #331: fixtures sintéticos y ROLLBACK, solo banco local.
begin;
set local statement_timeout='60s';
create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $$
begin if p_ok is not true then raise exception 'REVISION PR: %',p_mensaje;end if;end $$;
do $$
declare v_modo text; v_id uuid; v_actividad uuid; v_r jsonb; v_rev integer;
  v_ciclo_row crm.lead_sla_ciclos%rowtype;
  v_analista uuid:='b0000000-0000-4000-8000-000000000002';
  v_gerente uuid:='bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
  v_i integer:=0;
begin
  foreach v_modo in array array['observacion','apagado','exigir'] loop
    v_i:=v_i+1; v_id:=gen_random_uuid();
    select revision into v_rev from crm.recorrido_control where id;
    perform set_config('request.jwt.claim.sub',v_gerente::text,true);
    perform crm.recorrido_configurar_fn(v_modo,'Regresion de gestion sin ciclo en copia local',v_rev);
    perform set_config('request.jwt.claim.sub','',true);
    insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,monto_estimado,creado_por)
      values(v_id,'BANCO SIN CICLO '||v_modo,'98765000'||v_i,'landing',v_analista,1000,v_analista);
    update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id=v_id;
    select * into strict v_ciclo_row from crm.lead_sla_ciclos where lead_id=v_id and ciclo_n=1;
    -- Simular SOLO el dato heredado/inconsistente; restablecer todos los triggers
    -- antes de llamar la puerta real. No cambiar funciones ni permisos del ensayo.
    perform set_config('session_replication_role','replica',true);
    delete from crm.lead_sla_ciclos where lead_id=v_id;
    perform set_config('session_replication_role','origin',true);
    perform set_config('request.jwt.claim.sub',v_analista::text,true);
    v_r:=crm.registrar_intento_base_v2(gen_random_uuid(),v_id,'no_contesto','Intento legitimo sin fabricar ciclo',null,null,null);
    perform pg_temp.exigir((v_r->>'ok')::boolean,'intento real en '||v_modo);
    select a.id into strict v_actividad from crm.actividades a where a.lead_id=v_id and a.tipo='llamada_no_contestada';
    perform pg_temp.exigir((select ciclo_n is null and estado_ciclo='sin_ciclo' and registrado_en is not null
      from crm.actividad_ciclo_contexto where actividad_id=v_actividad),'sello sin acreditar ciclo en '||v_modo);
    perform pg_temp.exigir(not exists(select 1 from crm.lead_sla_ciclos where lead_id=v_id),'no fabricar ciclo en '||v_modo);
    select resultado into v_r from private.recorrido_evaluar(array[v_id]);
    perform pg_temp.exigir(v_r->>'estado'='ambiguo' and not (v_r->>'habilita_conversion')::boolean
      and not (v_r#>>'{pasos,gestionado}')::boolean,'no atribuir actividad a ciclo inexistente');
    -- Una reparación externa posterior tampoco debe adjudicar retroactivamente
    -- este intento al ciclo. Restaurar únicamente la fila sintética original.
    perform set_config('session_replication_role','replica',true);
    insert into crm.lead_sla_ciclos select (v_ciclo_row).*;
    perform set_config('session_replication_role','origin',true);
    select resultado into v_r from private.recorrido_evaluar(array[v_id]);
    perform pg_temp.exigir(not (v_r#>>'{pasos,gestionado}')::boolean
      and (select ciclo_n is null from crm.actividad_ciclo_contexto where actividad_id=v_actividad),
      'un ciclo restaurado no se apropia del intento sin ciclo');
    raise notice 'PASS: gestion real sin ciclo en %, sello no acreditado y sin backfill',v_modo;
  end loop;
end $$;
-- Una sentencia posterior a activar, como la siguiente petición de la API.
do $$
declare v_id uuid; v_analista uuid:='b0000000-0000-4000-8000-000000000002';
begin
  perform set_config('request.jwt.claim.sub','',true);
  -- Un lead nuevo sin ciclo sigue bloqueado al convertir con exigencia activa.
  v_id:=gen_random_uuid();
  -- El guard fija creado_en con statement_timestamp de esta nueva sentencia.
  insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,monto_estimado,creado_por,creado_en)
    values(v_id,'BANCO NUEVO SIN CICLO','987650009','landing',v_analista,1000,v_analista,clock_timestamp());
  perform set_config('session_replication_role','replica',true);
  delete from crm.lead_sla_ciclos where lead_id=v_id;
  perform set_config('session_replication_role','origin',true);
  insert into crm.actividades(lead_id,tipo,detalle) values(v_id,'llamada_no_contestada','Intento conservado');
  perform set_config('request.jwt.claim.sub',v_analista::text,true);
  begin
    perform crm.preparar_persona_lead_inversion_fn(v_id,'DNI','98765009','BANCO NUEVO SIN CICLO');
    raise exception 'La conversion debio rechazar por falta de hechos';
  exception when sqlstate 'P0409' then
    perform pg_temp.exigir(position('Antes de convertir' in sqlerrm)>0,'rechazo correcto');
  end;
  raise notice 'PASS: conservar gestion sin ciclo no habilita primera conversion nueva';
end $$;
rollback;
