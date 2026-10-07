-- Solo la copia sintética local upgrade_tasa_20261007. Todo el ensayo se deshace.
begin;
set local statement_timeout='120s';
set local plpgsql.check_asserts=on;
set local timezone='America/Lima';
create temporary table contexto(clave text primary key,id uuid,datos jsonb);
grant all on contexto to authenticated;
insert into contexto(clave,id) values
  ('actor',(select perfil_id from crm.equipo where private.rol_crm(perfil_id)='vendedor' order by perfil_id limit 1)),
  ('gerente',(select perfil_id from crm.equipo where private.rol_crm(perfil_id)='gerencia' order by perfil_id limit 1)),
  ('cliente',gen_random_uuid());
insert into auth.users(id) select id from contexto where clave='cliente';
insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,asesor_perfil_id,domicilio,correo)
  select id,'QA UPGRADE TASA','cliente','DNI','49710701',(select id from contexto where clave='actor'),
    'Calle sintética 123','qa-upgrade-tasa@example.invalid' from contexto where clave='cliente';

create function pg_temp.actor(p_clave text default 'actor') returns void language plpgsql as $$
declare id_actor uuid;
begin
  select id into strict id_actor from contexto where clave=p_clave;
  perform set_config('request.jwt.claim.sub',id_actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',id_actor,'role','authenticated')::text,true);
end $$;
create function pg_temp.modo(p_modo text) returns void language plpgsql as $$
begin
  perform pg_temp.actor('gerente');
  perform crm.publicar_politica_rentabilidad_fn((select max(version) from crm.politica_rentabilidad),
    jsonb_build_object('tasa_base_nueva',18,'tope_tecnico',25,'vigencia_solicitud_dias',7,'modo',p_modo,'nota','Ensayo sintético upgrade tasa'));
  perform pg_temp.actor();
end $$;
create function pg_temp.intencion(p_tasa numeric,p_categoria text default 'upgrade',p_origen uuid default null) returns jsonb language sql as $$
  select jsonb_build_object('cliente_id',(select id from contexto where clave='cliente'),
    'categoria',p_categoria,'contrato_origen_id',p_origen,'capital',10000,'moneda','PEN',
    'modalidad','mensual','tipo_interes','simple','fecha_inicio',current_date,
    'fecha_vencimiento',(current_date+interval '12 months')::date,'tasa_anual',p_tasa);
$$;
create function pg_temp.alta(p_tasa numeric,p_categoria text default 'upgrade',p_origen uuid default null) returns uuid language plpgsql as $$
declare r jsonb; cuotas jsonb;
begin
  select jsonb_agg(c order by n) into cuotas from (
    select n,jsonb_build_object('numero_cuota',n,'fecha_programada',(current_date+make_interval(months=>n))::date,
      'monto_programado',round(10000*p_tasa/100/12,2),'tipo','cuota') c from generate_series(1,12) n
    union all select 13,jsonb_build_object('numero_cuota',13,'fecha_programada',(current_date+interval '12 months')::date,
      'monto_programado',10000,'tipo','retorno')) q;
  set constraints all deferred;
  r:=crm.crear_contrato_con_cuenta_pdf_v2(pg_temp.intencion(p_tasa,p_categoria,p_origen)||
    jsonb_build_object('numero_contrato','QA-UPT-'||gen_random_uuid()),cuotas,
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros',
      'numero_cuenta','QA'||substr(gen_random_uuid()::text,1,8),
      'cci','004'||lpad(abs(hashtext(gen_random_uuid()::text)::bigint)::text,17,'0'),'titular_distinto',false));
  set constraints all immediate;
  return (r->>'id')::uuid;
end $$;
create function pg_temp.rechaza(p_sql text,p_codigo text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate=p_codigo then return; end if;
    raise exception 'Esperado %, recibido %: %',p_codigo,sqlstate,sqlerrm;
  end;
  raise exception 'Se esperaba rechazo %: %',p_codigo,p_sql;
end $$;

select pg_temp.modo('enforcement');
set local role authenticated;
select pg_temp.actor();
insert into contexto(clave,id) values('origen',pg_temp.alta(18,'nuevo'));
reset role;
update contexto set datos=(select to_jsonb(c) from public.contratos c where c.id=contexto.id) where clave='origen';
set local role authenticated;
do $tasas$
declare origen uuid:=(select id from contexto where clave='origen'); r jsonb; n numeric; id_nuevo uuid;
begin
  r:=crm.resolver_tasa_fn((select id from contexto where clave='cliente'),'upgrade',origen);
  assert (r->>'tasa_base')::numeric=18 and (r->>'tasa_minima_sin_autorizacion')::numeric=18
    and (r->>'tasa_minima_upgrade_sin_autorizacion')::numeric=0.01,'referencia, compatibilidad y mínimo del upgrade';
  r:=crm.resolver_tasa_fn((select id from contexto where clave='cliente'),'renovacion',origen);
  assert (r->>'tasa_minima_sin_autorizacion')::numeric=18,'no extender a renovación';
  foreach n in array array[0.01,16,18]::numeric[] loop
    id_nuevo:=pg_temp.alta(n,'upgrade',origen);
    assert id_nuevo is not null,'el alta no devolvió contrato';
    insert into contexto values('upgrade_'||n,id_nuevo,jsonb_build_object('tasa',n));
  end loop;
  perform pg_temp.rechaza(format('select pg_temp.alta(20,%L,%L)','upgrade',origen),'P0410');
  perform pg_temp.rechaza('select pg_temp.alta(16,''upgrade'',null)','P0410');
  raise notice 'PASS: referencia 18; upgrades 0.01, 16 y 18; renovación conserva piso; 20 sin aprobación y origen ausente rechazados';
end $tasas$;
reset role;
do $auditoria$
begin
  assert (select count(*)=3 from contexto x join public.contratos c on c.id=x.id where x.clave like 'upgrade_%'
    and c.categoria='upgrade' and c.tasa_anual=(x.datos->>'tasa')::numeric),'tasa elegida alterada';
  assert (select count(*)=3 from crm.ledger_rentabilidad l join contexto c on c.id=l.contrato_id where c.clave like 'upgrade_%'
    and l.regla='heredada_upgrade' and l.tasa_base=18 and l.solicitud_id is null and l.contrato_origen_id=(select id from contexto where clave='origen')),'auditoría del origen';
  assert (select count(*)=2 from crm.ledger_rentabilidad l join contexto c on c.id=l.contrato_id where c.clave like 'upgrade_%'
    and l.detalle->>'tasa_inferior_sin_excepcion'='true'),'auditoría de tasas inferiores';
  assert (select to_jsonb(c)=x.datos from contexto x join public.contratos c on c.id=x.id where x.clave='origen'),'contrato anterior modificado';
  raise notice 'PASS: trazabilidad sin solicitud artificial y contrato anterior intacto';
end $auditoria$;

-- Solicitud real vinculada al aporte; bajar la tasa no evade una pendiente.
set local role authenticated;
select pg_temp.actor();
insert into contexto(clave,id)
  select 'solicitud',(crm.solicitar_tasa_fn(pg_temp.intencion(20,'upgrade',(select id from contexto where clave='origen'))||
    jsonb_build_object('tasa_solicitada',20,'motivo','Nuevo aporte sintético a mayor tasa'))->>'id')::uuid;
select pg_temp.rechaza(format('select pg_temp.alta(16,%L,%L)','upgrade',(select id from contexto where clave='origen')),'P0411');
select pg_temp.rechaza(format('select crm.resolver_solicitud_tasa_fn(%L,''aprobar'')',(select id from contexto where clave='solicitud')),'42501');
reset role;
select pg_temp.modo('observacion');
set local role authenticated;
select pg_temp.actor();
do $libre$
declare n numeric; origen uuid:=(select id from contexto where clave='origen');
begin
  foreach n in array array[16,22,25]::numeric[] loop
    perform pg_temp.alta(n,'upgrade',origen);
  end loop;
  perform pg_temp.rechaza(format('select pg_temp.alta(25.01,%L,%L)','upgrade',origen),'P0410');
  perform pg_temp.rechaza(format('select crm.solicitar_tasa_fn(%L)',
    pg_temp.intencion(22,'upgrade',origen)||jsonb_build_object('tasa_solicitada',22,'motivo','Solicitud innecesaria')),'P0410');
  raise notice 'PASS: desactivado permite 16,22,25 con pendiente; conserva límite y evita solicitar';
end $libre$;
reset role;
do $sin_consumo$ begin
  assert (select estado='pendiente' and contrato_id is null from crm.solicitudes_tasa where id=(select id from contexto where clave='solicitud')),'observación alteró la solicitud';
end $sin_consumo$;
select pg_temp.modo('enforcement');
set local role authenticated;
select pg_temp.actor();
select pg_temp.rechaza(format('select pg_temp.alta(16,%L,%L)','upgrade',(select id from contexto where clave='origen')),'P0411');
select pg_temp.actor('gerente');
select crm.resolver_solicitud_tasa_fn((select id from contexto where clave='solicitud'),'aprobar');
select pg_temp.actor();
insert into contexto(clave,id) select 'autorizado',pg_temp.alta(20,'upgrade',(select id from contexto where clave='origen'));
select pg_temp.rechaza(format('select pg_temp.alta(20,%L,%L)','upgrade',(select id from contexto where clave='origen')),'P0410');
reset role;
do $aprobacion$ begin
  assert (select estado='consumida' and contrato_id=(select id from contexto where clave='autorizado') from crm.solicitudes_tasa
    where id=(select id from contexto where clave='solicitud')),'aprobación no consumida por el upgrade';
  assert (select to_jsonb(c)=x.datos from contexto x join public.contratos c on c.id=x.id where x.clave='origen'),'contrato origen alterado';
  raise notice 'PASS: reactivación recupera pendiente y solo Gerencia permite un único consumo para el upgrade';
end $aprobacion$;

-- Aislar la regla de corrección con un contrato sin PDF, sin desactivar triggers.
select pg_temp.actor();
set constraints all deferred;
do $sin_pdf$
declare c public.contratos; id_nuevo uuid;
begin
  select * into c from public.contratos where id=(select id from contexto where clave='origen');
  insert into public.contratos(cliente_id,numero_contrato,capital,moneda,tasa_anual,modalidad,tipo_interes,fecha_inicio,fecha_vencimiento,categoria,creado_por)
    values(c.cliente_id,'QA-UPT-SIN-PDF',10000,'PEN',16,'mensual','simple',c.fecha_inicio,c.fecha_vencimiento,'upgrade',auth.uid()) returning id into id_nuevo;
  perform set_config('crm.rentabilidad_origen_upgrade',c.cliente_id::text||'|'||c.id::text,true);
  insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_origen_id,contrato_nuevo_id,
    fecha_operacion,periodo,moneda,capital_renovado,capital_adicional,elegible_conversion,desglose_completo,fuente,creado_por)
    select cliente_id,vendedor_id,tipo,contrato_origen_id,id_nuevo,fecha_operacion,periodo,moneda,
      capital_renovado,capital_adicional,elegible_conversion,desglose_completo,fuente,creado_por
    from crm.operaciones_cartera where contrato_nuevo_id=(select id from contexto where clave='upgrade_16');
  set constraints all immediate;
  insert into contexto(clave,id) values('sin_pdf',id_nuevo);
  perform pg_temp.rechaza(format('update public.contratos set tasa_anual=15 where id=%L',id_nuevo),'P0410');
  update public.contratos set capital=11000 where id=id_nuevo;
  assert (select tasa_anual=16 from public.contratos where id=id_nuevo),'corrección cambió tasa pactada';
  raise notice 'PASS: corregir capital conserva 16 y rechaza rebajar la tasa del contrato emitido';
end $sin_pdf$;
rollback;
