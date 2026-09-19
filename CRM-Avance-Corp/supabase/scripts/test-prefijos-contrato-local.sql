-- Auditoría de numeración física. SOLO banco sintético aislado, nunca producción.
-- Requiere la copia prefijos_auditoria_20260919_v2 y los actores ficticios F4.
-- El reporte de auditoría documenta las funciones vigentes reproducidas en ella.
\set ON_ERROR_STOP on
begin;
set local timezone='America/Lima';
do $$
declare
  vendedor uuid := 'ed3bf307-f569-4a31-8eb8-d31b79166f5d';
  gerente uuid := '0ea17e82-00da-4691-90c0-78bd702f86fa';
  ajeno uuid := '0ad9b9e4-59cd-413a-903b-1b23dd516fa7';
  cliente uuid := '656834d4-b6ba-4274-b41d-5116fc8203a3';
  persona uuid := '521c1f3c-c90b-4141-a251-301a3f74a589';
  base jsonb; c jsonb; c2024 jsonb; r jsonb; repetido jsonb; cuotas jsonb;
  cuenta jsonb := '{"tipo":"nueva","banco":"BANCO FICTICIO","tipo_cuenta":"ahorros","numero_cuenta":"AUDITORIA-001","cci":"99999999999999999991","titular_distinto":false}';
  serie text; numero text; v_id uuid; id2024 uuid; id2026 uuid;
  cronograma_antes jsonb; inversion_antes jsonb; cuenta_antes jsonb;
  solicitud uuid; datos jsonb; preparado jsonb; confirmado jsonb; copia jsonb;
begin
  assert current_database()='prefijos_auditoria_20260919_v2', 'Solo base desechable de auditoría';
  assert exists(select 1 from public.perfiles p where p.id=vendedor and nombre_completo='PRUEBA F4 VENDEDOR'), 'Solo actores sintéticos';
  select jsonb_agg(jsonb_build_object('numero_cuota',n,'fecha_programada',
    (date '2026-09-01'+n*interval '1 month')::date,'monto_programado',12.50,'tipo','cuota') order by n)
    into cuotas from generate_series(1,12) n;
  cuotas:=cuotas||jsonb_build_array(jsonb_build_object('numero_cuota',13,'fecha_programada','2027-09-08','monto_programado',1000,'tipo','retorno'));
  base:=jsonb_build_object('cliente_id',cliente,'analista_cierre_id',vendedor,
    'capital',1000,'moneda','PEN','categoria','nuevo','tasa_anual',15,'tipo_interes','simple',
    'modalidad','mensual','fecha_inicio','2026-09-01','fecha_vencimiento','2027-09-01');
  perform set_config('request.jwt.claim.sub',vendedor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',vendedor,'role','authenticated')::text,true);

  foreach serie in array array['2024-01-','2025-01-','2026-01-'] loop
    numero:=serie||'999901';
    c:=base||jsonb_build_object('numero_contrato',numero,'clave_idempotencia',gen_random_uuid());
    set local role authenticated;
    r:=crm.crear_contrato_con_cuenta_pdf_v2(c,cuotas,cuenta);
    reset role;
    v_id:=(r->>'id')::uuid;
    assert exists(select 1 from public.contratos where contratos.id=v_id and numero_contrato=numero and cliente_id=cliente);
    assert (select count(*) from public.cronograma_pagos where contrato_id=v_id)=13;
    assert exists(select 1 from private.contrato_pdf_jobs where contrato_id=v_id
      and snapshot#>>'{contrato,numero}'=numero and nombre_archivo='Contrato-'||numero||'.pdf'
      and storage_path like v_id::text||'/%');
    if serie='2024-01-' then id2024:=v_id; c2024:=c; end if;
    if serie='2026-01-' then id2026:=v_id; end if;
    raise notice 'PASS alta %, 13 cuotas, snapshot, archivo PDF y relación por UUID',numero;
  end loop;

  set local role authenticated;
  repetido:=crm.crear_contrato_con_cuenta_pdf_v2(c,cuotas,cuenta);
  assert repetido->>'id'=r->>'id' and (repetido->>'idempotente')::boolean;
  raise notice 'PASS reintento idéntico devuelve el mismo contrato';
  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(c||'{"numero_contrato":"2025-01-999903"}',cuotas,cuenta);
    raise exception using errcode='P7777',message='No rechazó cambiar el prefijo con la misma clave';
  exception when sqlstate 'P0409' then
    raise notice 'PASS la misma clave con otro prefijo no duplica el alta';
  end;
  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(c||jsonb_build_object('clave_idempotencia',gen_random_uuid()),cuotas,cuenta);
    raise exception using errcode='P7777',message='No rechazó el número completo duplicado';
  exception when raise_exception or unique_violation then
    assert sqlstate='23505' or sqlerrm like '%ya existe%';
    raise notice 'PASS número completo repetido rechazado';
  end;
  r:=crm.actualizar_contrato_con_cuenta_pdf_v3(id2024,c2024-'clave_idempotencia',cuotas);
  reset role;
  assert (select numero_contrato from public.contratos where contratos.id=id2024)='2024-01-999901';
  assert exists(select 1 from private.contrato_pdf_jobs where contrato_id=id2024 and revision=2
    and snapshot#>>'{contrato,numero}'='2024-01-999901');
  raise notice 'PASS corrección del analista conserva 2024 y reserva revisión PDF 2';

  select jsonb_agg(to_jsonb(p) order by p.id) into cronograma_antes from public.cronograma_pagos p where contrato_id=id2024;
  select jsonb_agg(jsonb_build_object('id',i.id,'persona',i.inversionista_id,'contrato',i.contrato_id) order by i.id) into inversion_antes from crm.inversiones i where contrato_id=id2024;
  select to_jsonb(p) into cuenta_antes from crm.contrato_cuentas_pago p where contrato_id=id2024;
  perform set_config('request.jwt.claim.sub',gerente::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',gerente,'role','authenticated')::text,true);
  set local role authenticated;
  r:=crm.actualizar_numero_contrato_pdf_v3(id2024,'2025-01-999904',null,'nuevo');
  reset role;
  assert (select numero_contrato from public.contratos where contratos.id=id2024)='2025-01-999904';
  assert cronograma_antes=(select jsonb_agg(to_jsonb(p) order by p.id) from public.cronograma_pagos p where contrato_id=id2024);
  assert inversion_antes is not distinct from (select jsonb_agg(jsonb_build_object('id',i.id,'persona',i.inversionista_id,'contrato',i.contrato_id) order by i.id) from crm.inversiones i where contrato_id=id2024);
  assert cuenta_antes is not distinct from (select to_jsonb(p) from crm.contrato_cuentas_pago p where contrato_id=id2024);
  assert exists(select 1 from private.contrato_pdf_jobs where contrato_id=id2024 and revision=3
    and snapshot#>>'{contrato,numero}'='2025-01-999904' and nombre_archivo='Contrato-2025-01-999904.pdf');
  raise notice 'PASS corrección de gestor mantiene cuotas, cuenta e inversión y actualiza snapshot/archivo';

  set local role authenticated;
  begin
    perform crm.actualizar_numero_contrato_pdf_v3(id2024,'2026-01-999901',null,'nuevo');
    raise exception using errcode='P7777',message='No rechazó duplicado al corregir';
  exception when raise_exception or unique_violation then
    assert sqlstate='23505' or sqlerrm like '%ya existe%';
    raise notice 'PASS duplicado al corregir rechazado';
  end;
  reset role;
  perform set_config('request.jwt.claim.sub',ajeno::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ajeno,'role','authenticated')::text,true);
  set local role authenticated;
  begin
    perform crm.actualizar_contrato_con_cuenta_pdf_v3(id2026,c-'clave_idempotencia',cuotas);
    raise exception using errcode='P7777',message='Otro analista corrigió un contrato ajeno';
  exception when insufficient_privilege then raise notice 'PASS analista ajeno rechazado'; end;
  reset role;
  -- Usa un contrato ficticio antiguo: creado_en es inmutable incluso en el banco.
  select k.id into v_id from public.contratos k where k.creado_por=vendedor
    and k.creado_en<=now()-interval '5 hours' and k.estado='activo' limit 1;
  assert v_id is not null, 'El banco debe contener un contrato sintético antiguo';
  perform set_config('request.jwt.claim.sub',vendedor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',vendedor,'role','authenticated')::text,true);
  set local role authenticated;
  begin
    perform crm.actualizar_contrato_con_cuenta_pdf_v3(v_id,c-'clave_idempotencia',cuotas);
    raise exception using errcode='P7777',message='Se omitió la ventana de cinco horas';
  exception when insufficient_privilege then
    assert sqlerrm like '%5 horas%';
    raise notice 'PASS ventana de corrección de cinco horas conservada';
  end;
  reset role;

  solicitud:=gen_random_uuid();
  datos:=jsonb_build_object('inversionista_id',persona,'empresa','avance',
    'contrato',base||'{"numero_contrato":"2025-01-999905"}', 'cronograma',cuotas,'cuenta',cuenta);
  set local role authenticated;
  preparado:=crm.preparar_inversion_fn(solicitud,datos);
  assert (preparado->>'revision_datos')::integer=0;
  copia:=jsonb_set(datos,'{contrato,numero_contrato}','"2024-01-999905"');
  preparado:=crm.corregir_solicitud_inversion_fn(solicitud,gen_random_uuid(),0,copia,'Corregir la serie del contrato físico');
  assert (preparado->>'revision_datos')::integer=1;
  begin
    perform crm.confirmar_inversion_revisada_fn(solicitud,0);
    raise exception using errcode='P7777',message='Confirmó revisión desactualizada';
  exception when sqlstate 'PT409' then raise notice 'PASS revisión desactualizada rechazada'; end;
  confirmado:=crm.confirmar_inversion_revisada_fn(solicitud,1);
  repetido:=crm.confirmar_inversion_revisada_fn(solicitud,1);
  assert repetido->>'inversion_id'=confirmado->>'inversion_id';
  assert repetido#>>'{fuente,id}'=confirmado#>>'{fuente,id}';
  reset role;
  v_id:=(confirmado#>>'{fuente,id}')::uuid;
  assert exists(select 1 from public.contratos where contratos.id=v_id and numero_contrato='2024-01-999905');
  assert exists(select 1 from crm.inversiones where contrato_id=v_id and inversionista_id=persona);
  assert exists(select 1 from private.contrato_pdf_jobs where contrato_id=v_id and snapshot#>>'{contrato,numero}'='2024-01-999905');
  raise notice 'PASS preparar 2025, corregir a 2024, confirmar y reintentar conserva un contrato y una inversión';

  solicitud:=gen_random_uuid();
  datos:=jsonb_set(datos,'{contrato,numero_contrato}','"2026-01-999901"');
  set local role authenticated;
  perform crm.preparar_inversion_fn(solicitud,datos);
  begin
    perform crm.confirmar_inversion_revisada_fn(solicitud,0);
    raise exception using errcode='P7777',message='Inversión confirmó número duplicado';
  exception when raise_exception or unique_violation then
    assert sqlstate='23505' or sqlerrm like '%ya existe%';
  end;
  copia:=jsonb_set(datos,'{contrato,numero_contrato}','"2025-01-999906"');
  perform crm.corregir_solicitud_inversion_fn(solicitud,gen_random_uuid(),0,copia,'Corregir número duplicado del contrato físico');
  confirmado:=crm.confirmar_inversion_revisada_fn(solicitud,1);
  reset role;
  assert exists(select 1 from public.contratos where contratos.id=(confirmado#>>'{fuente,id}')::uuid and numero_contrato='2025-01-999906');
  raise notice 'PASS confirmación duplicada se recupera corrigiendo la misma solicitud';
  set constraints all immediate;
end $$;
rollback;
