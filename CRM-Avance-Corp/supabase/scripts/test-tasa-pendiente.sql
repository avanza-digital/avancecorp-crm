-- Banco AISLADO con R4 instalada y siembra-banco-f3.sql -v run=910908.
-- No usar producción. Todo el ensayo se revierte al terminar.
\set ON_ERROR_STOP on
begin;
set local timezone = 'America/Lima';
set local plpgsql.check_asserts = on;
insert into auth.users(id) values ('f3000000-0000-0000-0000-000000000004') on conflict do nothing;
insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni)
values ('f3000000-0000-0000-0000-000000000004','QA SEGUNDO ANALISTA','comercial','DNI','70000094') on conflict do nothing;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo,creado_por)
values ('f3000000-0000-0000-0000-000000000004','vendedor','f3000000-0000-0000-0000-000000000003',true,'f3000000-0000-0000-0000-000000000002') on conflict do nothing;
update crm.multiempresa_flags set activo = false where nombre in ('resolver_en_puertas', 'inversiones_escritura');
insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
select 1,statement_timestamp()-interval '1 day',15,50,7,'enforcement'
where not exists(select 1 from crm.politica_rentabilidad);

create function pg_temp.actor(p_id text) returns void language sql as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub',p_id,'role','authenticated')::text, true);
$$;
create function pg_temp.alta(p_tasa numeric, p_capital numeric default 20000) returns jsonb language plpgsql as $$
declare v_resultado jsonb;
begin
  v_resultado := crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','f3a00000-0000-0000-0000-910908000001','numero_contrato','QA-TASA-'||gen_random_uuid()::text,
      'capital',p_capital,'moneda','PEN','tasa_anual',p_tasa,'modalidad','mensual','tipo_interes','simple','categoria','nuevo',
      'fecha_inicio','2026-03-11','fecha_vencimiento','2027-03-11','notas_internas','Prueba aislada de espera de Gerencia'),
    jsonb_build_array(jsonb_build_object('numero_cuota',1,'fecha_programada','2026-04-11','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','2027-03-11','monto_programado',p_capital,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','QA'||substr(gen_random_uuid()::text,1,8),
      'cci','004'||lpad(abs(hashtext(gen_random_uuid()::text)::bigint)::text,17,'0'),
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null));
  set constraints all immediate;
  return v_resultado;
end;
$$;
create function pg_temp.solicitar() returns uuid language plpgsql as $$
declare v_res jsonb;
begin
  v_res := crm.solicitar_tasa_fn(jsonb_build_object('cliente_id','f3a00000-0000-0000-0000-910908000001',
    'categoria','nuevo','contrato_origen_id',null,'capital',20000,'moneda','PEN','modalidad','mensual','tipo_interes','simple',
    'fecha_inicio','2026-03-11','fecha_vencimiento','2027-03-11','tasa_solicitada',17,'motivo','Cliente referido para prueba aislada'));
  return (v_res->>'id')::uuid;
end;
$$;

do $prueba$
declare
  v_s uuid;
  v_alta jsonb;
  v_antes bigint;
  v_modo text;
begin
  perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
  v_alta := pg_temp.alta(15);
  assert exists(select 1 from public.contratos where id=(v_alta->>'id')::uuid), 'alta sin petición';
  raise notice 'PASS: sin solicitud crea a la base';
  v_s := pg_temp.solicitar();
  select count(*) into v_antes from public.contratos;
  -- Observación se ensaya sin bloqueos en rentabilidad-modo/test-modo.sql.
  foreach v_modo in array array['enforcement'] loop
    perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
    -- Fixture vigente dentro de esta sentencia, incluso después de otros tests.
    insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
    select max(version)+1,statement_timestamp()-interval '1 microsecond',15,50,7,v_modo
    from crm.politica_rentabilidad;
    assert (select modo from private.politica_rentabilidad_vigente(statement_timestamp()))=v_modo;
    perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
    begin
      perform pg_temp.alta(15);
      raise exception 'FAIL: permitió crear a la base con solicitud pendiente';
    exception when sqlstate 'P0411' then null; end;
    begin
      perform pg_temp.alta(15,30000);
      raise exception 'FAIL: cambiar capital eludió la petición';
    exception when sqlstate 'P0411' then null; end;
    perform pg_temp.actor('f3000000-0000-0000-0000-000000000003');
    begin
      perform pg_temp.alta(15);
      raise exception 'FAIL: otro actor eludió la petición';
    exception when sqlstate 'P0411' then null; end;
    assert (select count(*) from public.contratos)=v_antes, 'un rechazo dejó contratos parciales';
    raise notice 'PASS: % bloquea base, cambio de capital y otro actor; cero altas parciales', v_modo;
  end loop;
  -- La regla no se extiende a otros clientes/categorías/orígenes.
  perform private.rentabilidad_exigir_respuesta('f3a00000-0000-0000-0000-910908000099','nuevo',null);
  perform private.rentabilidad_exigir_respuesta('f3a00000-0000-0000-0000-910908000001','renovacion',null);
  perform private.rentabilidad_exigir_respuesta('f3a00000-0000-0000-0000-910908000001','nuevo','f3a00000-0000-0000-0000-910908000099');
  raise notice 'PASS: conserva el ámbito cliente/categoría/origen';

  perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
  perform crm.resolver_solicitud_tasa_fn(v_s,'rechazar',null,'Prueba de rechazo');
  perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
  perform pg_temp.alta(15);
  raise notice 'PASS: tras rechazo crea a la base';
  v_s := pg_temp.solicitar();
  perform pg_temp.actor('f3000000-0000-0000-0000-000000000002');
  perform crm.resolver_solicitud_tasa_fn(v_s,'aprobar',null,null);
  perform pg_temp.actor('f3000000-0000-0000-0000-000000000001');
  v_alta := pg_temp.alta(17);
  assert (select estado='consumida' and contrato_id=(v_alta->>'id')::uuid from crm.solicitudes_tasa where id=v_s), 'no consumió la aprobación';
  raise notice 'PASS: aprobación permite la tasa y consume la autorización';
  begin
    perform pg_temp.alta(17);
    raise exception 'FAIL: reutilizó la autorización consumida';
  exception when sqlstate 'P0410' then null; end;
  raise notice 'PASS: no reutiliza una autorización';
  v_s := pg_temp.solicitar();
  perform set_config('crm.solicitud_tasa_por_puerta','on',true);
  update crm.solicitudes_tasa set solicitada_en=clock_timestamp()-interval '8 days',
    vence_en=clock_timestamp()-interval '1 second' where id=v_s;
  perform set_config('crm.solicitud_tasa_por_puerta','off',true);
  perform pg_temp.alta(15);
  raise notice 'PASS: una solicitud caducada no bloquea a la base';
  assert not has_function_privilege('authenticated','private.rentabilidad_exigir_respuesta(uuid,text,uuid)','EXECUTE');
  assert not has_function_privilege('anon','private.rentabilidad_exigir_respuesta(uuid,text,uuid)','EXECUTE');
  assert not has_function_privilege('service_role','private.rentabilidad_bloquear_operacion(uuid,text,uuid)','EXECUTE');
  raise notice 'PASS: helpers internos cerrados a la API';
end;
$prueba$;
-- Sesión real de API: A pide; B no puede ver su fila por RLS, pero el candado
-- SECURITY DEFINER del contrato sí la conoce y la espera se impone a ambos.
set local role authenticated;
select pg_temp.actor('f3000000-0000-0000-0000-000000000001');
select pg_temp.solicitar();
select pg_temp.actor('f3000000-0000-0000-0000-000000000004');
do $rls$
begin
  assert current_user='authenticated';
  assert not exists(select 1 from crm.solicitudes_tasa where estado='pendiente'
    and cliente_id='f3a00000-0000-0000-0000-910908000001');
  begin
    perform pg_temp.alta(15);
    raise exception 'FAIL: la API eludió la solicitud ajena';
  exception when sqlstate 'P0411' then null; end;
  raise notice 'PASS: authenticated no ve la solicitud ajena, pero tampoco puede crear';
end;
$rls$;
rollback;
