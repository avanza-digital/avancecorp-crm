-- Banco sintético venta-cruzada; incluye RLS real (SET ROLE authenticated).
-- SET CONSTRAINTS drena la cola como COMMIT al terminar cada puerta,
-- conservando ROLLBACK para no dejar fixtures. No se desactiva el trigger.
begin;
set local statement_timeout='60s';
set local lock_timeout='3s';
do $$ begin
  if (select count(*) from crm.leads)>200 or not exists(select 1 from public.perfiles
    where id='c0000000-0000-4000-8000-000000000001' and nombre_completo='VC GERENCIA') then
    raise exception 'Solo banco sintético';
  end if;
end $$;
create temporary table resultados(nombre text primary key) on commit drop;
create temporary table caso(persona uuid, solicitud uuid, datos_antes jsonb) on commit drop;
grant all on resultados,caso to authenticated;
create function pg_temp.exigir(p_ok boolean,p_nombre text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL: %',p_nombre; end if;
  insert into resultados values(p_nombre);
  raise notice 'PASS: %',p_nombre;
end $$;
create function pg_temp.preparar(p_empresa text default 'prodelco',p_solicitud boolean default true)
returns void language plpgsql as $$
declare v_p uuid; v_s uuid:=gen_random_uuid(); v_d jsonb; v_f date:=(now() at time zone 'America/Lima')::date;
begin
  perform set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000004',true);
  v_p:=(crm.preparar_persona_lead_inversion_fn('c0000000-0000-4000-8000-000000000081',
    'DNI','48000081','PERSONA PRUEBA REASIGNADA')->>'inversionista_id')::uuid;
  if p_solicitud then
    v_d:=jsonb_build_object('inversionista_id',v_p,'lead_id','c0000000-0000-4000-8000-000000000081',
      'empresa',p_empresa,'monto',5000,'moneda','PEN','fecha_comercial',v_f,
      'vence_en',(v_f+interval '12 months')::date,'plazo_meses',12,'tasa_anual',18,
      'numero_transaccion','PRUEBA-REASIGNACION','referencia','PRUEBA SINTETICA',
      'evidencia',jsonb_build_object('ruta',v_p||'/'||v_s||'/comprobante.pdf'));
    if p_empresa='avance' then
      v_d:=jsonb_build_object('inversionista_id',v_p,'lead_id','c0000000-0000-4000-8000-000000000081',
        'empresa','avance','contrato',jsonb_build_object('moneda','PEN'),'cronograma','[]'::jsonb,'cuenta','{}'::jsonb,
        'alta_portal',jsonb_build_object('nombre_completo','PERSONA PRUEBA REASIGNADA','nombres','PERSONA','apellidos','PRUEBA REASIGNADA',
        'correo','reasignacion.prueba@example.test','telefono','999123456','domicilio','AVENIDA SINTETICA 123 LIMA'));
    end if;
    perform crm.preparar_inversion_fn(v_s,v_d);
  else v_s:=null;
  end if;
  insert into caso select v_p,v_s,(select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en' from crm.inversion_solicitudes s where id=v_s);
end $$;
create function pg_temp.alineado() returns boolean language sql as $$
select exists(select 1 from caso c join crm.inversionistas i on i.id=c.persona
  join crm.leads l on l.id='c0000000-0000-4000-8000-000000000081'
  left join crm.inversion_solicitudes s on s.id=c.solicitud
  where i.responsable_relacion_id=l.vendedor_id and (c.solicitud is null or s.responsable_esperado_id=l.vendedor_id))
$$;

savepoint caso_base;
select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado(),'Supervisor: lead, persona y borrador se reasignan juntos bajo RLS');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en'=c.datos_antes
  from caso c join crm.inversion_solicitudes s on s.id=c.solicitud),'Conserva datos, hash, creador, revisión de datos y estado del borrador');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select count(*)=1 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud
  where r.revision=1 and r.revisado_por='c0000000-0000-4000-8000-000000000002'),'Revisión atribuida al supervisor que reasignó');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select count(*)=1 from caso c join crm.inversionista_responsables r on r.inversionista_id=c.persona where r.hasta is null)
  and (select count(*)=1 from caso c join crm.inversionista_responsables r on r.inversionista_id=c.persona where r.hasta is not null),
  'Cierra el tramo anterior y abre uno solo');
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000005';
set local role authenticated;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(crm.preparar_persona_lead_inversion_fn('c0000000-0000-4000-8000-000000000081',
  'DNI','48000081','PERSONA PRUEBA REASIGNADA')->>'solicitud_id'=(select solicitud::text from caso),
  'Nuevo analista continúa la misma inversión');
reset role;
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select count(*)=1 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud),
  'Guardar la misma asignación no duplica revisión');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(not exists(select 1 from caso c join crm.inversiones i on i.inversionista_id=c.persona),
  'La reasignación no crea inversiones');
rollback to caso_base;

-- Las pruebas con rollback a savepoint imprimen sus PASS antes de deshacer.
select pg_temp.preparar('prodelco',false);
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000006' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado(),'Gerencia: sincroniza una persona preparada sin borrador entre equipos');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
  begin
    update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000006' where id='c0000000-0000-4000-8000-000000000081';
    raise exception 'Aceptó destino ajeno';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado() and (select count(*)=0 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud),
  'Supervisor: destino ajeno rechazado sin efectos secundarios');
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000004';
set local role authenticated;
do $$ begin
  begin
    update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
    raise exception 'Aceptó la reasignación del vendedor';
  exception when raise_exception then
    if sqlerrm<>'Un vendedor no puede reasignar leads' then raise; end if;
  end;
end $$;
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado(),'Vendedor conserva el veto a reasignar');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(not has_function_privilege('authenticated','private.trg_leads_sincronizar_conversion()','execute')
  and not has_function_privilege('anon','private.trg_leads_sincronizar_conversion()','execute')
  and not has_function_privilege('service_role','private.trg_leads_sincronizar_conversion()','execute'),
  'Helper privado sin ejecutores API');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
select crm.reasignar_responsable_relacion_fn((select persona from caso),'c0000000-0000-4000-8000-000000000006','Prueba de la puerta gerencial vigente');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado(),'La puerta gerencial vigente sincroniza también el borrador sin recursión');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select count(*)=1 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud),
  'La puerta gerencial deja una sola revisión');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
set local role authenticated;
update crm.leads set vendedor_id=null,asignado_supervisor_id='c0000000-0000-4000-8000-000000000002'
where id='c0000000-0000-4000-8000-000000000081';
reset role;
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
select crm.derivar_leads_equipo_fn(array['c0000000-0000-4000-8000-000000000081'::uuid],array['c0000000-0000-4000-8000-000000000005'::uuid])->>'total';
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select crm.revertir_derivacion_equipo_fn('c0000000-0000-4000-8000-000000000081')->>'devuelto_a_bandeja';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select vendedor_id is null from crm.leads where id='c0000000-0000-4000-8000-000000000081')
  and (select responsable_relacion_id='c0000000-0000-4000-8000-000000000005' from crm.inversionistas where id=(select persona from caso)),
  'Bandeja conserva el último responsable, sin inventar un analista');
set local role authenticated;
select crm.derivar_leads_equipo_fn(array['c0000000-0000-4000-8000-000000000081'::uuid],array['c0000000-0000-4000-8000-000000000004'::uuid])->>'total';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado(),'Derivar desde bandeja vuelve a sincronizar persona y borrador');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
set local role authenticated;
update crm.leads set vendedor_id=null,asignado_supervisor_id=null where id='c0000000-0000-4000-8000-000000000081';
reset role;
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000006';
set local role authenticated;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(crm.tomar_lead_libre('+51987800001','48000081')->>'estado'='tomado_ok','Toma directa conserva su puerta autorizada');
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado(),'Toma directa de un lead libre sincroniza la conversión');
rollback to caso_base;

-- Una conciliación pendiente no impide el traslado autorizado: no deja efectos
-- parciales en persona/borrador y mantiene el veto de invertir, con nota auditable.
select pg_temp.preparar();
update crm.inversion_solicitudes set auth_claim_id=gen_random_uuid(),auth_contexto=jsonb_build_object(
  'inversionista_id',inversionista_id,'documento_tipo','DNI','documento','48000081') where id=(select solicitud from caso);
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select vendedor_id='c0000000-0000-4000-8000-000000000005' from crm.leads where id='c0000000-0000-4000-8000-000000000081')
  and (select responsable_relacion_id='c0000000-0000-4000-8000-000000000004' from crm.inversionistas where id=(select persona from caso))
  and (select count(*)=1 from caso c join crm.inversionista_responsables r on r.inversionista_id=c.persona)
  and (select count(*)=0 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud)
  and exists(select 1 from crm.actividades where lead_id='c0000000-0000-4000-8000-000000000081'
    and metadata->>'evento'='reasignacion_conversion_requiere_revision'),
  'Saga inconsistente conserva la reasignación sin efectos parciales en la conversión y registra revisión pendiente');
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000005';
set local role authenticated;
do $$ begin
  begin
    perform crm.preparar_persona_lead_inversion_fn('c0000000-0000-4000-8000-000000000081','DNI','48000081','PERSONA PRUEBA REASIGNADA');
    raise exception 'La conciliación pendiente permitió invertir';
  exception when sqlstate 'P0409' then null;
  end;
end $$;
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(true,'La conciliación pendiente conserva el veto de invertir');
rollback to caso_base;

-- Proceso de acceso reclamado: la revisión existente conserva token y contexto.
select pg_temp.preparar('avance');
do $$ declare v_s uuid:=(select solicitud from caso); begin
  perform crm.acceso_inversion_fn(v_s,'reclamar',jsonb_build_object('token',repeat('a',48)));
  update caso set datos_antes=(select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en' from crm.inversion_solicitudes s where id=v_s);
end $$;
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado() and (select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en'=c.datos_antes
  from caso c join crm.inversion_solicitudes s on s.id=c.solicitud),'Acceso en curso: conserva claim, contexto y borrador');
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000005';
set local role authenticated;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(crm.acceso_inversion_fn((select solicitud from caso),'reclamar',jsonb_build_object('token',repeat('a',48)))->>'token'=repeat('a',48),
  'Nuevo analista puede reanudar el acceso pendiente');
reset role;
rollback to caso_base;

-- Perfil ya creado y enlazado, todavía sin inversión: usa la revisión oficial.
select pg_temp.preparar('avance');
do $$ declare v_s uuid:=(select solicitud from caso); v_r jsonb; v_p uuid:=gen_random_uuid(); v_token text:=repeat('a',48); begin
  v_r:=crm.acceso_inversion_fn(v_s,'reclamar',jsonb_build_object('token',v_token));
  insert into auth.users(id,aud,role,email,raw_app_meta_data)
    values(v_p,'authenticated','authenticated','reasignacion.prueba@example.test',jsonb_build_object('claim_id',v_r->>'claim_id'));
  v_r:=crm.acceso_inversion_fn(v_s,'registrar_auth',jsonb_build_object('token',v_token,'version',v_r->'version','auth_user_id',v_p));
  v_r:=crm.acceso_inversion_fn(v_s,'crear_perfil',jsonb_build_object('token',v_token,'version',v_r->'version'));
  v_r:=crm.acceso_inversion_fn(v_s,'enlazar',jsonb_build_object('token',v_token,'version',v_r->'version'));
  update caso set datos_antes=(select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en' from crm.inversion_solicitudes s where id=v_s);
end $$;
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado() and (select p.asesor_perfil_id=i.responsable_relacion_id from caso c
  join crm.inversionistas i on i.id=c.persona join public.perfiles p on p.id=i.perfil_id),
  'Perfil Avance pendiente se alinea mediante la revisión existente');
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en'=c.datos_antes
  from caso c join crm.inversion_solicitudes s on s.id=c.solicitud),
  'Perfil enlazado: no altera datos ni contexto histórico de acceso');
rollback to caso_base;

-- Inversión confirmada: ninguna atribución histórica se transfiere.
select pg_temp.preparar();
insert into storage.objects(bucket_id,name,metadata)
select 'f4-comprobantes',s.datos#>>'{evidencia,ruta}','{"size":128,"mimetype":"application/pdf"}'::jsonb
from caso c join crm.inversion_solicitudes s on s.id=c.solicitud;
select crm.confirmar_inversion_revisada_fn((select solicitud from caso),0)->>'estado';
update caso set datos_antes=(select to_jsonb(s) from crm.inversion_solicitudes s where id=caso.solicitud);
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
select crm.reasignar_responsable_relacion_fn((select persona from caso),'c0000000-0000-4000-8000-000000000006','Prueba de atribución histórica inmutable')->>'ok';
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select to_jsonb(s)=c.datos_antes from caso c join crm.inversion_solicitudes s on s.id=c.solicitud)
  and (select ce.vendedor_id='c0000000-0000-4000-8000-000000000004' from caso c join crm.inversiones i on i.inversionista_id=c.persona
    join crm.cierres_externos ce on ce.id=i.cierre_externo_id),'La inversión y el borrador confirmados conservan atribución e historia');
rollback to caso_base;

-- Lote mixto: un borrador válido y otro con acceso pendiente inconsistente.
select pg_temp.preparar();
create temporary table lote(persona uuid,solicitud uuid) on commit drop;
do $$ declare v_p uuid; v_s uuid:=gen_random_uuid(); v_f date:=(now() at time zone 'America/Lima')::date; begin
  v_p:=(crm.preparar_persona_lead_inversion_fn('c0000000-0000-4000-8000-000000000082',
    'DNI','48000082','SEGUNDA PERSONA PRUEBA')->>'inversionista_id')::uuid;
  perform crm.preparar_inversion_fn(v_s,jsonb_build_object('inversionista_id',v_p,
    'lead_id','c0000000-0000-4000-8000-000000000082','empresa','prodelco','monto',5000,'moneda','PEN',
    'fecha_comercial',v_f,'vence_en',(v_f+interval '12 months')::date,'plazo_meses',12,'tasa_anual',18,
    'numero_transaccion','LOTE-SINTETICO','referencia','PRUEBA SINTETICA',
    'evidencia',jsonb_build_object('ruta',v_p||'/'||v_s||'/comprobante.pdf')));
  insert into lote values(v_p,v_s);
  update crm.inversion_solicitudes set auth_claim_id=gen_random_uuid(),
    auth_contexto=jsonb_build_object('inversionista_id',v_p,'documento_tipo','DNI','documento','48000082') where id=v_s;
end $$;
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005'
where id in ('c0000000-0000-4000-8000-000000000081','c0000000-0000-4000-8000-000000000082');
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado()
  and (select count(*)=2 from crm.leads where id in ('c0000000-0000-4000-8000-000000000081','c0000000-0000-4000-8000-000000000082')
    and vendedor_id='c0000000-0000-4000-8000-000000000005')
  and (select responsable_relacion_id='c0000000-0000-4000-8000-000000000004' from crm.inversionistas where id=(select persona from lote))
  and exists(select 1 from crm.actividades where lead_id='c0000000-0000-4000-8000-000000000082'
    and metadata->>'evento'='reasignacion_conversion_requiere_revision'),
  'Lote mixto reasigna ambos leads, sincroniza el válido y conserva la conciliación del otro');
rollback to caso_base;

-- Baja real: incluye cartera mixta, personas previas y el nuevo borrador.
select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
set local role authenticated;
select crm.fijar_membresia_activa_fn('c0000000-0000-4000-8000-000000000004',false,
  'c0000000-0000-4000-8000-000000000005',
  (select actualizado_en from crm.equipo where perfil_id='c0000000-0000-4000-8000-000000000004'),gen_random_uuid())->>'activo_crm';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado() and
  not exists(select 1 from crm.equipo where perfil_id='c0000000-0000-4000-8000-000000000004' and activo)
  and (select count(*)=1 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud),
  'Offboarding real conserva traslado completo, borrador alineado y una revisión');
select pg_temp.exigir((select count(*)=2 from caso c join crm.inversionista_responsables r on r.inversionista_id=c.persona)
  and (select count(*)=1 from caso c join crm.inversionista_responsables r on r.inversionista_id=c.persona
    where r.hasta is null and r.motivo='offboarding' and r.responsable_id='c0000000-0000-4000-8000-000000000005')
  and not exists(select 1 from crm.actividades where lead_id='c0000000-0000-4000-8000-000000000081'
    and metadata->>'evento'='reasignacion_conversion_requiere_revision'),
  'Offboarding registra solo el tramo canónico, sin duplicados ni falsa alerta');
rollback to caso_base;

-- Un veto de inversión no puede bloquear la administración de cartera.
select pg_temp.preparar();
select crm.marcar_no_contactar('c0000000-0000-4000-8000-000000000081','Prueba de restricción vigente');
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select vendedor_id='c0000000-0000-4000-8000-000000000005' and no_contactar from crm.leads where id='c0000000-0000-4000-8000-000000000081')
  and (select responsable_relacion_id='c0000000-0000-4000-8000-000000000004' and no_contactar from crm.inversionistas where id=(select persona from caso))
  and exists(select 1 from crm.actividades where lead_id='c0000000-0000-4000-8000-000000000081'
    and metadata->>'evento'='reasignacion_conversion_requiere_revision'),
  'No insistir conserva la restricción y permite la reasignación administrativa auditada');
rollback to caso_base;

select pg_temp.preparar();
update crm.inversionista_identificadores set verificado=false where inversionista_id=(select persona from caso);
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select vendedor_id='c0000000-0000-4000-8000-000000000005' from crm.leads where id='c0000000-0000-4000-8000-000000000081')
  and (select count(*)=0 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud)
  and (select responsable_relacion_id='c0000000-0000-4000-8000-000000000004' from crm.inversionistas where id=(select persona from caso)),
  'Documento sin verificar no se autoaprueba ni bloquea la reasignación');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura';
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select vendedor_id='c0000000-0000-4000-8000-000000000005' from crm.leads where id='c0000000-0000-4000-8000-000000000081')
  and (select count(*)=0 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud),
  'Inversiones deshabilitadas conservan reasignación y no revisan el borrador');
-- Recuperación documentada: habilitada la operación, Gerencia usa las dos
-- puertas vigentes. La nota permanece como antecedente, nunca se borra.
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';
select crm.reasignar_responsable_relacion_fn((select persona from caso),
  'c0000000-0000-4000-8000-000000000005','Conciliación tras revisión de la reasignación')->>'ok';
select crm.revisar_solicitud_inversion_fn((select solicitud from caso),
  'c0000000-0000-4000-8000-000000000005',0,'Conciliación tras revisión de la reasignación')->>'estado';
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000005';
set local role authenticated;
select pg_temp.exigir(crm.preparar_persona_lead_inversion_fn('c0000000-0000-4000-8000-000000000081',
  'DNI','48000081','PERSONA PRUEBA REASIGNADA')->>'solicitud_id'=(select solicitud::text from caso),
  'Tras la conciliación canónica, el nuevo analista recupera el mismo borrador');
reset role;
select pg_temp.exigir(pg_temp.alineado(),'Recuperación de una alerta alinea persona, lead y solicitud sin borrar la historia');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000001';
update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select vendedor_id='c0000000-0000-4000-8000-000000000005' from crm.leads where id='c0000000-0000-4000-8000-000000000081')
  and (select responsable_relacion_id='c0000000-0000-4000-8000-000000000004' from crm.inversionistas where id=(select persona from caso)),
  'Resolver apagado conserva exactamente el comportamiento anterior');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='';
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir((select vendedor_id='c0000000-0000-4000-8000-000000000005' from crm.leads where id='c0000000-0000-4000-8000-000000000081')
  and (select responsable_relacion_id='c0000000-0000-4000-8000-000000000004' from crm.inversionistas where id=(select persona from caso))
  and exists(select 1 from crm.actividades where lead_id='c0000000-0000-4000-8000-000000000081'
    and metadata->>'evento'='reasignacion_conversion_requiere_revision' and creado_por is null),
  'Mantenimiento sin actor no imita Gerencia ni cambia responsable de persona');
rollback to caso_base;

select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000002' where id='c0000000-0000-4000-8000-000000000081';
reset role;
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
select pg_temp.exigir(pg_temp.alineado(),'Supervisor activo también es destino comercial permitido');
rollback to caso_base;

-- Dos movimientos antes del mismo COMMIT: solo cuenta el destino final.
select pg_temp.preparar();
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
set local role authenticated;
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000005' where id='c0000000-0000-4000-8000-000000000081';
update crm.leads set vendedor_id='c0000000-0000-4000-8000-000000000002' where id='c0000000-0000-4000-8000-000000000081';
set constraints crm.trg_leads_zzzz_conversion_responsable immediate;
set constraints crm.trg_leads_zzzz_conversion_responsable deferred;
reset role;
select pg_temp.exigir(pg_temp.alineado()
  and (select count(*)=2 from caso c join crm.inversionista_responsables r on r.inversionista_id=c.persona)
  and (select count(*)=1 from caso c join crm.inversion_solicitud_revisiones r on r.solicitud_id=c.solicitud)
  and not exists(select 1 from crm.actividades where lead_id='c0000000-0000-4000-8000-000000000081'
    and metadata->>'evento'='reasignacion_conversion_requiere_revision'),
  'Varios movimientos en la misma transacción sincronizan solo el destino final');
rollback to caso_base;

rollback;
select 'REASIGNACION_CONVERSION_SQL_OK' as resultado;
