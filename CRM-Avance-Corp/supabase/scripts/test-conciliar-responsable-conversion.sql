-- Regresión del incidente 2026-09-29. Solo banco sintético venta-cruzada.
-- No confirma inversiones; toda la prueba termina en ROLLBACK.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $prueba$
declare
  v_lead uuid := 'c0000000-0000-4000-8000-000000000081';
  v_gerencia uuid := 'c0000000-0000-4000-8000-000000000001';
  v_anterior uuid := 'c0000000-0000-4000-8000-000000000004';
  v_nuevo uuid := 'c0000000-0000-4000-8000-000000000005';
  v_persona uuid; v_solicitud uuid := gen_random_uuid();
  v_datos jsonb; v_antes jsonb; v_despues jsonb; v_resultado jsonb;
  v_fecha date := (now() at time zone 'America/Lima')::date;
begin
  if (select count(*) from crm.leads)>200 or not exists(
    select 1 from public.perfiles where id=v_gerencia and nombre_completo='VC GERENCIA') then
    raise exception 'Solo se permite en el banco sintético venta-cruzada';
  end if;
  perform set_config('request.jwt.claim.sub',v_anterior::text,true);
  v_persona := (crm.preparar_persona_lead_inversion_fn(v_lead,'DNI','48000081','PERSONA PRUEBA REASIGNADA')->>'inversionista_id')::uuid;
  v_datos := jsonb_build_object('inversionista_id',v_persona,'lead_id',v_lead,
    'empresa','prodelco','monto',5000,'moneda','USD','fecha_comercial',v_fecha,
    'vence_en',(v_fecha+interval '12 months')::date,'plazo_meses',12,'tasa_anual',18,
    'numero_transaccion','PRUEBA-REASIGNACION','referencia','PRUEBA SINTETICA',
    'evidencia',jsonb_build_object('ruta',v_persona||'/'||v_solicitud||'/comprobante.pdf'));
  perform crm.preparar_inversion_fn(v_solicitud,v_datos);
  select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en' into v_antes
    from crm.inversion_solicitudes s where id=v_solicitud;
  perform set_config('request.jwt.claim.sub',v_gerencia::text,true);
  update crm.leads set vendedor_id=v_nuevo where id=v_lead;
  -- Reproducir exactamente el bloqueo y no aceptar otro error.
  begin
    perform crm.preparar_persona_lead_inversion_fn(v_lead,'DNI','48000081','PERSONA PRUEBA REASIGNADA');
    raise exception 'Falta el bloqueo esperado';
  exception when sqlstate 'P0409' then
    if sqlerrm<>'El responsable de la persona y el analista del lead deben coincidir antes de invertir' then raise; end if;
  end;
  raise notice 'PASS: reproduce el bloqueo tras reasignar el lead';
  -- El analista no puede utilizar la puerta reservada a gerencia.
  perform set_config('request.jwt.claim.sub',v_nuevo::text,true);
  begin
    perform crm.reasignar_responsable_relacion_fn(v_persona,v_nuevo,'Prueba de conciliación autorizada');
    raise exception 'El analista obtuvo permiso de Gerencia';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: conserva el permiso exclusivo de Gerencia';
  perform set_config('request.jwt.claim.sub',v_gerencia::text,true);
  perform crm.reasignar_responsable_relacion_fn(v_persona,v_nuevo,'Prueba de conciliación autorizada');
  perform crm.revisar_solicitud_inversion_fn(v_solicitud,v_nuevo,0,'Prueba de conciliación autorizada');
  if (select responsable_relacion_id from crm.inversionistas where id=v_persona) is distinct from v_nuevo
    or (select responsable_esperado_id from crm.inversion_solicitudes where id=v_solicitud) is distinct from v_nuevo
    or (select vendedor_id from crm.leads where id=v_lead) is distinct from v_nuevo then
    raise exception 'No se alinearon las tres asignaciones';
  end if;
  raise notice 'PASS: lead, persona y solicitud coinciden';
  if (select count(*) from crm.inversionista_responsables where inversionista_id=v_persona and hasta is null)<>1
    or not exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona and responsable_id=v_anterior and hasta is not null)
    or not exists(select 1 from crm.inversion_solicitud_revisiones where solicitud_id=v_solicitud and revision=1 and responsable_anterior_id=v_anterior and responsable_nuevo_id=v_nuevo) then
    raise exception 'Falta el historial coherente de la reparación';
  end if;
  raise notice 'PASS: conserva el tramo anterior y registra la revisión';
  select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en' into v_despues
    from crm.inversion_solicitudes s where id=v_solicitud;
  if v_antes is distinct from v_despues or exists(select 1 from crm.inversiones where inversionista_id=v_persona)
    or (select etapa from crm.leads where id=v_lead) <> 'nuevo' then
    raise exception 'La reparación alteró el borrador o creó efectos económicos';
  end if;
  raise notice 'PASS: datos, hash, autoría y estado intactos; cero inversiones';
  perform set_config('request.jwt.claim.sub',v_nuevo::text,true);
  v_resultado:=crm.preparar_persona_lead_inversion_fn(v_lead,'DNI','48000081','PERSONA PRUEBA REASIGNADA');
  if v_resultado->>'solicitud_id' is distinct from v_solicitud::text then
    raise exception 'El nuevo analista no recupera el mismo borrador';
  end if;
  perform crm.solicitud_inversion_fn(v_solicitud);
  raise notice 'PASS: el nuevo analista abre y recupera la solicitud existente';
  perform set_config('request.jwt.claim.sub',v_gerencia::text,true);
  perform crm.reasignar_responsable_relacion_fn(v_persona,v_nuevo,'Prueba de conciliación autorizada');
  perform crm.revisar_solicitud_inversion_fn(v_solicitud,v_nuevo,0,'Prueba de conciliación autorizada');
  if (select count(*) from crm.inversion_solicitud_revisiones where solicitud_id=v_solicitud)<>1
    or (select count(*) from crm.inversionista_responsables where inversionista_id=v_persona)<>2 then
    raise exception 'El reintento duplicó el historial';
  end if;
  raise notice 'PASS: reintento idempotente';
end $prueba$;
rollback;
