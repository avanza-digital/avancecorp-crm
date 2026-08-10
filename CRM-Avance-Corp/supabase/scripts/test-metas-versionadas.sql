\set ON_ERROR_STOP on

-- Oraculo transaccional de metas versionadas.
-- Exito: METAS_VERSIONADAS_TX_OK. Todo queda en rollback.

begin;

insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
  ('71000000-0000-4000-8000-000000000001','authenticated','authenticated','metas-g@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-000000000002','authenticated','authenticated','metas-s@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-000000000003','authenticated','authenticated','metas-v@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-000000000004','authenticated','authenticated','metas-d@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-000000000005','authenticated','authenticated','metas-c@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-000000000006','authenticated','authenticated','metas-sa@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-000000000007','authenticated','authenticated','metas-a@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-000000000008','authenticated','authenticated','metas-v2@test.invalid',now(),'{}','{}',now(),now());

insert into public.perfiles(id,nombre_completo,correo,rol,activo) values
  ('71000000-0000-4000-8000-000000000001','Metas Gerencia','metas-g@test.invalid','superadmin',true),
  ('71000000-0000-4000-8000-000000000002','Metas Supervisor','metas-s@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-000000000003','Metas Vendedor','metas-v@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-000000000004','Metas Directorio','metas-d@test.invalid','directorio',true),
  ('71000000-0000-4000-8000-000000000005','Metas Cliente','metas-c@test.invalid','cliente',true),
  ('71000000-0000-4000-8000-000000000006','Metas Superadmin','metas-sa@test.invalid','superadmin',true),
  ('71000000-0000-4000-8000-000000000007','Metas Admin','metas-a@test.invalid','admin',true),
  ('71000000-0000-4000-8000-000000000008','Metas Vendedor Dos','metas-v2@test.invalid','comercial',true);

-- Simula una fila residual/preexistente por debajo de los triggers defensivos:
-- aunque exista físicamente, el rol efectivo debe quedar enmascarado.
set local session_replication_role=replica;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values
  ('71000000-0000-4000-8000-000000000001','gerencia',null,true),
  ('71000000-0000-4000-8000-000000000002','supervisor',null,true),
  ('71000000-0000-4000-8000-000000000003','vendedor','71000000-0000-4000-8000-000000000002',true),
  ('71000000-0000-4000-8000-000000000006','vendedor','71000000-0000-4000-8000-000000000002',true),
  ('71000000-0000-4000-8000-000000000008','vendedor','71000000-0000-4000-8000-000000000002',true);
set local session_replication_role=origin;

select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
set local role authenticated;

do $test$
declare
  v_periodo constant date:=date '2099-07-01';
  v_payload jsonb;
  v_resultado crm.meta_periodos;
  v_config jsonb;
  v_total_vendedores integer;
begin
  -- La base de rama puede conservar otros vendedores activos. El oraculo
  -- publica el roster real completo, pero comprueba en detalle su vendedor.
  select count(*)::integer,jsonb_object_agg(
    e.perfil_id::text,jsonb_build_object(
      'conversion_objetivo',25,
      'detalles',jsonb_build_array(
        jsonb_build_object('categoria','nuevo','moneda','PEN','capital_objetivo',100000,'contratos_objetivo',2),
        jsonb_build_object('categoria','nuevo','moneda','USD','capital_objetivo',10000,'contratos_objetivo',1),
        jsonb_build_object('categoria','renovacion','moneda','PEN','capital_objetivo',50000,'contratos_objetivo',1),
        jsonb_build_object('categoria','renovacion','moneda','USD','capital_objetivo',5000,'contratos_objetivo',1),
        jsonb_build_object('categoria','upgrade','moneda','PEN','capital_objetivo',30000,'contratos_objetivo',1),
        jsonb_build_object('categoria','upgrade','moneda','USD','capital_objetivo',3000,'contratos_objetivo',1)
      )
    )
  ) into v_total_vendedores,v_payload
  from crm.equipo e
  join public.perfiles p on p.id=e.perfil_id and p.activo
  where private.rol_crm(e.perfil_id)='vendedor';

  select * into v_resultado
  from crm.publicar_metas_vendedores(v_periodo,0,v_payload);
  if v_resultado.revision<>1 then raise exception 'M01 revision inicial incorrecta'; end if;
  if (select count(*) from crm.metas_vendedor where meta_periodo_id=v_resultado.id)<>v_total_vendedores
     or (select count(*) from crm.metas_vendedor_detalle d join crm.metas_vendedor m
          on m.id=d.meta_vendedor_id where m.meta_periodo_id=v_resultado.id)<>6*v_total_vendedores then
    raise exception 'M02 la publicacion no dejo roster x 6 dimensiones';
  end if;
  if (select sum(capital_objetivo) from crm.metas_vendedor_detalle d
      join crm.metas_vendedor m on m.id=d.meta_vendedor_id
      where m.meta_periodo_id=v_resultado.id
        and m.vendedor_id='71000000-0000-4000-8000-000000000003' and d.moneda='PEN')<>180000
     or (select sum(capital_objetivo) from crm.metas_vendedor_detalle d
      join crm.metas_vendedor m on m.id=d.meta_vendedor_id
      where m.meta_periodo_id=v_resultado.id
        and m.vendedor_id='71000000-0000-4000-8000-000000000003' and d.moneda='USD')<>18000 then
    raise exception 'M03 PEN/USD no quedaron en acumuladores separados';
  end if;

  v_config:=crm.configuracion_metas_fn(v_periodo);
  if (v_config->>'version')::int<>1 or (v_config->>'revision')::int<>1
     or lower(v_config->>'publicada_por_nombre')<>'metas gerencia'
     or v_config->>'publicada_por'<>'71000000-0000-4000-8000-000000000001'
     or not exists(select 1 from jsonb_array_elements(v_config->'vendedores') x
       where x.value->>'vendedor_id'='71000000-0000-4000-8000-000000000003'
         and jsonb_array_length(x.value->'detalles')=6)
     or exists(select 1 from jsonb_array_elements(v_config->'vendedores') x
       where x.value->>'vendedor_id'='71000000-0000-4000-8000-000000000006')
     or (v_config->>'puede_editar')::boolean is distinct from true then
    raise exception 'M04 configuracion_metas_fn fuera de contrato';
  end if;

  -- CAS: una revision obsoleta no escribe una tercera historia.
  begin
    perform * from crm.publicar_metas_vendedores(v_periodo,0,v_payload);
    raise exception 'M05 acepto expected_revision obsoleta';
  exception when serialization_failure then null;
  end;

  perform * from crm.publicar_metas_vendedores(v_periodo,1,v_payload);
  if (select count(*) from crm.meta_periodos where periodo=v_periodo)<>2 then
    raise exception 'M06 no preservo las dos revisiones';
  end if;

end;
$test$;
reset role;

-- Un sujeto deja el roster vivo al perder rol efectivo, pero las revisiones ya
-- publicadas siguen siendo historia consultable y no se reescriben.
set local session_replication_role=replica;
update public.perfiles
set rol='superadmin'
where id='71000000-0000-4000-8000-000000000003';
set local session_replication_role=origin;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $test$
declare v_config jsonb; v_cumplimiento jsonb;
begin
  v_config:=crm.configuracion_metas_fn(date '2099-07-01');
  v_cumplimiento:=crm.cumplimiento_metas_fn(date '2099-07-01');
  if exists(select 1 from jsonb_array_elements(v_config->'vendedores') x
       where x.value->>'vendedor_id'='71000000-0000-4000-8000-000000000003')
     or not exists(select 1 from jsonb_array_elements(v_cumplimiento->'vendedores') x
       where x.value->>'vendedor_id'='71000000-0000-4000-8000-000000000003') then
    raise exception 'M06b roster vivo oculto o historia publicada perdida';
  end if;
end;
$test$;
reset role;
set local session_replication_role=replica;
update public.perfiles
set rol='comercial'
where id='71000000-0000-4000-8000-000000000003';
set local session_replication_role=origin;

-- El ACL bloquea UPDATE al navegador; como owner se prueba además el candado
-- físico que protege la historia ante scripts privilegiados equivocados.
do $test$
begin
  begin
    update crm.meta_periodos set revision=99
    where periodo=date '2099-07-01' and revision=1;
    raise exception 'M07 permitio reescribir historia';
  exception when object_not_in_prerequisite_state then null;
  end;
end;
$test$;

-- Vendedor: solo su meta, nunca publica.
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $test$
declare v_periodo constant date:=date '2099-07-01';
begin
  if (select count(*) from crm.metas_vendedor m join crm.meta_periodos p
      on p.id=m.meta_periodo_id where p.periodo=v_periodo)<>2 then
    raise exception 'M08 vendedor no ve sus dos revisiones';
  end if;
  begin
    perform * from crm.publicar_metas_vendedores(v_periodo,2,'{}');
    raise exception 'M09 vendedor publico metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Directorio: lectura atomica global y sin escritura.
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000004',true);
set local role authenticated;
do $test$
declare v_c jsonb; v_m jsonb;
begin
  v_c:=crm.configuracion_metas_fn(date '2099-07-01');
  v_m:=crm.cumplimiento_metas_fn(date '2099-07-01');
  if (v_c->>'puede_editar')::boolean is distinct from false
     or lower(v_c->>'publicada_por_nombre')<>'metas gerencia'
     or not exists(
       select 1 from jsonb_array_elements(v_m->'vendedores') vendedor
       where vendedor.value->>'vendedor_id'='71000000-0000-4000-8000-000000000003'
     ) then
    raise exception 'M10 Directorio no obtuvo lectura de solo lectura';
  end if;
  begin
    perform * from crm.publicar_metas_vendedores(
      date '2099-07-01',2,'{}'
    );
    raise exception 'M11 Directorio publico metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Superadmin Portal sin Gerencia administra roles, pero no hereda la operacion
-- comercial ni la lectura global de Directorio.
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000006',true);
set local role authenticated;
do $test$
begin
  if private.rol_crm('71000000-0000-4000-8000-000000000006') is not null
     or (select count(*) from crm.meta_periodos)<>0
     or (select count(*) from crm.metas_vendedor)<>0
     or (select count(*) from crm.metas_vendedor_detalle)<>0 then
    raise exception 'M11b Superadmin puro leyo tablas de metas';
  end if;
  begin
    perform crm.configuracion_metas_fn(date '2099-07-01');
    raise exception 'M11c Superadmin puro obtuvo configuracion de metas';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.cumplimiento_metas_fn(date '2099-07-01');
    raise exception 'M11d Superadmin puro obtuvo cumplimiento de metas';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from crm.publicar_metas_vendedores(date '2099-07-01',2,'{}');
    raise exception 'M11e Superadmin puro publico metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Admin Portal tampoco recibe acceso CRM por su rol del Portal.
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000007',true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.meta_periodos)<>0
     or (select count(*) from crm.metas_vendedor)<>0
     or (select count(*) from crm.metas_vendedor_detalle)<>0 then
    raise exception 'M11f Admin Portal leyo tablas de metas';
  end if;
  begin
    perform crm.configuracion_metas_fn(date '2099-07-01');
    raise exception 'M11g Admin Portal obtuvo configuracion de metas';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.cumplimiento_metas_fn(date '2099-07-01');
    raise exception 'M11h Admin Portal obtuvo cumplimiento de metas';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from crm.publicar_metas_vendedores(date '2099-07-01',2,'{}');
    raise exception 'M11i Admin Portal publico metas';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Oráculo de atribución: enlace explícito autoritativo, contrato libre por
-- autor-snapshot y conflictos fail-closed. Todos los casos comparten cliente
-- a propósito para demostrar que cambiar su asesor actual no mueve históricos.
reset request.jwt.claim.sub;
insert into public.contratos(
  id,cliente_id,numero_contrato,capital,moneda,tasa_anual,modalidad,tipo_interes,
  categoria,estado,fecha_inicio,fecha_vencimiento,creado_por,creado_en
) values
  -- Lead A + autor A: atribución explícita normal.
  ('71000000-0000-4000-8000-000000000101','71000000-0000-4000-8000-000000000005',
   'TEST-META-7101',25000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-15 12:00:00-05'),
  -- Sin lead + autor A en snapshot: fallback válido.
  ('71000000-0000-4000-8000-000000000102','71000000-0000-4000-8000-000000000005',
   'TEST-META-7102',4000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-16 12:00:00-05'),
  -- Sin lead + autor supervisor fuera del snapshot: excluido.
  ('71000000-0000-4000-8000-000000000103','71000000-0000-4000-8000-000000000005',
   'TEST-META-7103',8000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000002',
   timestamptz '2099-07-17 12:00:00-05'),
  -- Lead supervisor inelegible + autor A válido: no hace fallback.
  ('71000000-0000-4000-8000-000000000104','71000000-0000-4000-8000-000000000005',
   'TEST-META-7104',16000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-18 12:00:00-05'),
  -- Leads de A y B: conflicto explícito, excluido.
  ('71000000-0000-4000-8000-000000000105','71000000-0000-4000-8000-000000000005',
   'TEST-META-7105',32000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-19 12:00:00-05'),
  -- Lead B + autor A: manda B.
  ('71000000-0000-4000-8000-000000000106','71000000-0000-4000-8000-000000000005',
   'TEST-META-7106',64000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-20 12:00:00-05'),
  -- Solo lead con vendedor nulo: autor A conserva fallback.
  ('71000000-0000-4000-8000-000000000107','71000000-0000-4000-8000-000000000005',
   'TEST-META-7107',128000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-21 12:00:00-05'),
  -- Dos leads del mismo B: una sola atribución/contrato.
  ('71000000-0000-4000-8000-000000000108','71000000-0000-4000-8000-000000000005',
   'TEST-META-7108',256000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-22 12:00:00-05'),
  -- Límite inferior Lima incluido.
  ('71000000-0000-4000-8000-000000000109','71000000-0000-4000-8000-000000000005',
   'TEST-META-7109',512000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-07-01 00:00:00-05'),
  -- Límite superior Lima excluido.
  ('71000000-0000-4000-8000-000000000110','71000000-0000-4000-8000-000000000005',
   'TEST-META-7110',1024000,'PEN',10,'mensual','simple','nuevo','activo',
   date '2099-08-01',date '2100-08-01','71000000-0000-4000-8000-000000000003',
   timestamptz '2099-08-01 00:00:00-05');
select set_config('crm.op_privilegiada','on',true);
insert into crm.leads(
  id,nombre_completo,telefono,origen,etapa,monto_estimado,moneda,categoria_interes,
  vendedor_id,perfil_id,contrato_id,convertido_en,creado_por
) values (
  '71000000-0000-4000-8000-000000000201','Lead Meta Confirmada','51999007101',
  'otro','convertido',25000,'PEN','nuevo','71000000-0000-4000-8000-000000000003',
  '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000101',
  now(),'71000000-0000-4000-8000-000000000003'
);
select set_config('crm.op_privilegiada','off',true);

-- Cohorte de conversión deliberadamente independiente de contratos: un lead
-- convertido sin contrato suma a conversión, nunca a capital/contratos. Se
-- inyectan los sellos históricos con triggers suspendidos porque los triggers
-- vivos sellan statement_timestamp(), mientras este oráculo usa julio de 2099
-- para quedar aislado de cualquier fixture preexistente.
set local session_replication_role = replica;
insert into crm.leads(
  id,nombre_completo,telefono,origen,etapa,motivo_descarte,monto_estimado,moneda,
  categoria_interes,vendedor_id,perfil_id,contrato_id,convertido_en,descartado_en,
  creado_por,creado_en
) values
  (
    '71000000-0000-4000-8000-000000000202','Lead Meta Convertida Sin Contrato',
    '51999007102','otro','convertido',null,30000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000003',
    '71000000-0000-4000-8000-000000000005',null,
    timestamptz '2099-07-20 12:00:00-05',null,
    '71000000-0000-4000-8000-000000000003',
    timestamptz '2099-07-10 12:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000203','Lead Meta Descartada',
    '51999007103','otro','descartado','sin_interes',10000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000003',null,null,null,
    timestamptz '2099-07-21 12:00:00-05',
    '71000000-0000-4000-8000-000000000003',
    timestamptz '2099-07-11 12:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000204','Lead Explícito Supervisor',
    '51999007104','otro','nuevo',null,16000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000002',
    '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000104',
    null,null,'71000000-0000-4000-8000-000000000002',
    timestamptz '2099-07-18 12:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000205','Lead Conflicto A',
    '51999007105','otro','nuevo',null,32000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000003',
    '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000105',
    null,null,'71000000-0000-4000-8000-000000000003',
    timestamptz '2099-07-19 12:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000206','Lead Conflicto B',
    '51999007106','otro','nuevo',null,32000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000008',
    '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000105',
    null,null,'71000000-0000-4000-8000-000000000008',
    timestamptz '2099-07-19 13:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000207','Lead B Autor A',
    '51999007107','otro','nuevo',null,64000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000008',
    '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000106',
    null,null,'71000000-0000-4000-8000-000000000008',
    timestamptz '2099-07-20 12:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000208','Lead Sin Vendedor',
    '51999007108','otro','nuevo',null,128000,'PEN','nuevo',null,
    '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000107',
    null,null,'71000000-0000-4000-8000-000000000003',
    timestamptz '2099-07-21 12:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000209','Lead Duplicado B Uno',
    '51999007109','otro','nuevo',null,256000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000008',
    '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000108',
    null,null,'71000000-0000-4000-8000-000000000008',
    timestamptz '2099-07-22 12:00:00-05'
  ),
  (
    '71000000-0000-4000-8000-000000000210','Lead Duplicado B Dos',
    '51999007110','otro','nuevo',null,256000,'PEN','nuevo',
    '71000000-0000-4000-8000-000000000008',
    '71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000108',
    null,null,'71000000-0000-4000-8000-000000000008',
    timestamptz '2099-07-22 13:00:00-05'
  );

-- Dos mutaciones vivas que NO deben alterar el snapshot de atribución.
update public.perfiles
set asesor_perfil_id='71000000-0000-4000-8000-000000000002'
where id='71000000-0000-4000-8000-000000000005';
update crm.equipo set activo=false
where perfil_id='71000000-0000-4000-8000-000000000003';
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $test$
declare
  v_c jsonb;
  v_vendedor_a jsonb;
  v_nuevo_pen_a jsonb;
  v_vendedor_b jsonb;
  v_nuevo_pen_b jsonb;
  v_total_contratos integer;
  v_total_capital numeric;
begin
  v_c:=crm.cumplimiento_metas_fn(date '2099-07-01');
  select v.value,d.value into v_vendedor_a,v_nuevo_pen_a
  from jsonb_array_elements(v_c->'vendedores') v
  cross join lateral jsonb_array_elements(v.value->'detalles') d
  where v.value->>'vendedor_id'='71000000-0000-4000-8000-000000000003'
    and d.value->>'categoria'='nuevo' and d.value->>'moneda'='PEN';

  select v.value,d.value into v_vendedor_b,v_nuevo_pen_b
  from jsonb_array_elements(v_c->'vendedores') v
  cross join lateral jsonb_array_elements(v.value->'detalles') d
  where v.value->>'vendedor_id'='71000000-0000-4000-8000-000000000008'
    and d.value->>'categoria'='nuevo' and d.value->>'moneda'='PEN';

  select
    coalesce(sum((d.value->>'contratos_real')::integer),0),
    coalesce(sum((d.value->>'capital_real')::numeric),0)
    into v_total_contratos,v_total_capital
  from jsonb_array_elements(v_c->'vendedores') v
  cross join lateral jsonb_array_elements(v.value->'detalles') d;

  if (v_nuevo_pen_a->>'capital_real')::numeric<>669000
     or (v_nuevo_pen_a->>'contratos_real')::int<>4
     or (v_nuevo_pen_b->>'capital_real')::numeric<>320000
     or (v_nuevo_pen_b->>'contratos_real')::int<>2
     or v_total_capital<>989000
     or v_total_contratos<>6
     or private.rol_crm('71000000-0000-4000-8000-000000000003') is not null
     or (v_vendedor_a->>'convertidos')::int<>1
     or (v_vendedor_a->>'resueltos')::int<>2
     or (v_vendedor_a->>'conversion_real')::numeric<>50
     or v_c ? 'fuente_reales'
     or v_c->'fuentes_reales'<>jsonb_build_object(
       'capital_y_contratos','contratos_confirmados',
       'conversion','leads_resueltos'
     ) then
    raise exception 'M12 fuentes o cumplimiento real fuera de contrato';
  end if;
end;
$test$;
reset role;

do $test$
begin
  if has_function_privilege('anon','crm.publicar_metas_vendedores(date,integer,jsonb)','execute')
     or has_function_privilege('anon','crm.cumplimiento_metas_fn(date)','execute')
     or has_function_privilege('service_role','crm.cumplimiento_metas_fn(date)','execute')
     or not has_function_privilege('authenticated','crm.cumplimiento_metas_fn(date)','execute')
     or has_table_privilege('authenticated','crm.meta_periodos','insert,update,delete')
     or has_table_privilege('authenticated','crm.objetivos_legacy_archivo','select')
     or to_regclass('crm.objetivos') is not null
     or to_regclass('crm.objetivos_vendedores') is not null
     or to_regclass('crm.objetivos_legacy_archivo') is null
     or to_regclass('crm.objetivos_vendedores_legacy_archivo') is null
     or to_regprocedure('crm.fijar_objetivos(date,jsonb)') is not null
     or to_regprocedure('crm.fijar_objetivos_vendedores(date,jsonb)') is not null
     or exists (
       select 1
       from pg_policies
       where schemaname = 'crm'
         and tablename in (
           'objetivos_legacy_archivo',
           'objetivos_vendedores_legacy_archivo'
         )
     )
     or coalesce((
       select pg_get_indexdef(c.oid)
       from pg_class c
       join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relname='idx_contratos_creado_en'
     ),'') not like 'CREATE INDEX idx_contratos_creado_en ON public.contratos USING btree (creado_en)%'
     then
    raise exception 'M13 ACL legacy/nuevo incorrecta';
  end if;
  if not exists(select 1 from public.audit_log
    where tabla='crm.meta_periodos' and usuario_id='71000000-0000-4000-8000-000000000001') then
    raise exception 'M14 publicaciones sin auditoria';
  end if;
end;
$test$;

-- ============================================================================
-- M15..M18 — Un vendedor sin supervisor no puede secuestrar el mes entero.
--
-- El bug real (2026-08-10): el editor ofrecia las metas del roster (vendedores
-- CON supervisor) y el publicador las exigia de TODOS los vendedores, ademas de
-- abortar con 23514 si a alguno le faltaba. Con una sola analista huerfana,
-- publicar metas era imposible y `crm.meta_periodos` llevaba 0 filas.
-- Aqui se fija el contrato nuevo: se publica el roster, al excluido se le
-- nombra, y colarlo en el payload sigue siendo un error.
-- ============================================================================

-- Los TRES caminos por los que un vendedor cae fuera del roster. Se prueban
-- juntos porque el arreglo de cada uno esta en un sitio distinto y una sola
-- etiqueta para los tres manda a Gerencia a buscar el problema equivocado.
insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
  ('71000000-0000-4000-8000-000000000009','authenticated','authenticated',
   'metas-huerfano@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-00000000000a','authenticated','authenticated',
   'metas-sup-baja@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-00000000000b','authenticated','authenticated',
   'metas-v-supbaja@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-00000000000c','authenticated','authenticated',
   'metas-coord@test.invalid',now(),'{}','{}',now(),now()),
  ('71000000-0000-4000-8000-00000000000d','authenticated','authenticated',
   'metas-v-coord@test.invalid',now(),'{}','{}',now(),now());

insert into public.perfiles(id,nombre_completo,correo,rol,activo) values
  ('71000000-0000-4000-8000-000000000009','Metas Vendedor Sin Jefe',
   'metas-huerfano@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-00000000000a','Metas Supervisor De Baja',
   'metas-sup-baja@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-00000000000b','Metas Vendedor Con Jefe De Baja',
   'metas-v-supbaja@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-00000000000c','Metas Coordinador',
   'metas-coord@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-00000000000d','Metas Vendedor Bajo Coordinador',
   'metas-v-coord@test.invalid','comercial',true);

set local session_replication_role=replica;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values
  ('71000000-0000-4000-8000-000000000009','vendedor',null,true),
  ('71000000-0000-4000-8000-00000000000a','supervisor',null,false),
  ('71000000-0000-4000-8000-00000000000b','vendedor','71000000-0000-4000-8000-00000000000a',true),
  ('71000000-0000-4000-8000-00000000000c','coordinador',null,true),
  ('71000000-0000-4000-8000-00000000000d','vendedor','71000000-0000-4000-8000-00000000000c',true);
set local session_replication_role=origin;

select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $test$
declare
  v_c jsonb;
  v_payload jsonb;
  v_periodo date := date '2099-09-01';
  v_revision integer;
begin
  v_c := crm.configuracion_metas_fn(v_periodo);

  -- M15: el huerfano queda FUERA del roster editable y DENTRO de la lista de
  -- excluidos, con nombre. Callarlo dejaria a alguien sin meta en silencio.
  -- Ninguno de los tres entra al roster editable...
  if exists (
       select 1 from jsonb_array_elements(v_c->'vendedores') v
       where v.value->>'vendedor_id' in (
         '71000000-0000-4000-8000-000000000009',
         '71000000-0000-4000-8000-00000000000b',
         '71000000-0000-4000-8000-00000000000d')
     ) then
    raise exception 'M15 un vendedor sin supervisor valido entro al roster editable';
  end if;

  -- ...y cada uno sale nombrado CON SU MOTIVO, que es lo que decide donde se
  -- arregla: asignar supervisor, reactivar al que esta de baja, o corregir un
  -- rol. Una sola etiqueta para los tres seria un predicado usado como proxy
  -- de tres preguntas distintas.
  if jsonb_array_length(v_c->'sin_supervisor')<>3
     or not exists (
       select 1 from jsonb_array_elements(v_c->'sin_supervisor') s
       where s.value->>'vendedor_id'='71000000-0000-4000-8000-000000000009'
         -- En MAYUSCULAS: public.perfiles normaliza el nombre al insertarlo.
         and s.value->>'nombre'='METAS VENDEDOR SIN JEFE'
         and s.value->>'motivo'='sin_supervisor')
     or not exists (
       select 1 from jsonb_array_elements(v_c->'sin_supervisor') s
       where s.value->>'vendedor_id'='71000000-0000-4000-8000-00000000000b'
         and s.value->>'motivo'='supervisor_inactivo')
     or not exists (
       select 1 from jsonb_array_elements(v_c->'sin_supervisor') s
       where s.value->>'vendedor_id'='71000000-0000-4000-8000-00000000000d'
         and s.value->>'motivo'='supervisor_no_es_supervisor') then
    raise exception 'M15 los excluidos no se nombran o no distinguen el motivo';
  end if;

  -- M16: con el huerfano vivo, publicar el roster DEBE funcionar. Este es el
  -- caso exacto que estaba roto en produccion.
  select jsonb_object_agg(v.value->>'vendedor_id', jsonb_build_object(
           'conversion_objetivo',0,'detalles',v.value->'detalles'))
    into v_payload
  from jsonb_array_elements(v_c->'vendedores') v;

  select mp.revision into v_revision
  from crm.publicar_metas_vendedores(v_periodo,0,v_payload) mp;

  if v_revision is distinct from 1 then
    raise exception 'M16 el roster no se pudo publicar con un vendedor huerfano vivo';
  end if;
  if exists (
       select 1 from crm.metas_vendedor mv
       join crm.meta_periodos mp on mp.id=mv.meta_periodo_id
       where mp.periodo=v_periodo
         and mv.vendedor_id='71000000-0000-4000-8000-000000000009'
     ) then
    raise exception 'M16b se creo meta para un vendedor sin supervisor';
  end if;

  -- M17: colar al excluido en el payload sigue siendo un error de contrato.
  begin
    perform * from crm.publicar_metas_vendedores(v_periodo,1,
      v_payload || jsonb_build_object('71000000-0000-4000-8000-000000000009',
        jsonb_build_object('conversion_objetivo',0,
          'detalles',(v_payload->(select v.value->>'vendedor_id'
                                  from jsonb_array_elements(v_c->'vendedores') v
                                  limit 1))->'detalles')));
    raise exception 'M17 se acepto una meta para alguien fuera del roster';
  exception when sqlstate '22023' then null;
  end;
end;
$test$;
reset role;

-- M18: a un supervisor no le corresponde enumerar analistas fuera de su
-- subarbol; la lista de excluidos es cosa de quien gobierna el roster entero.
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $test$
declare
  v_c jsonb;
begin
  v_c := crm.configuracion_metas_fn(date '2099-09-01');
  if jsonb_array_length(v_c->'sin_supervisor')<>0
     or (v_c->>'puede_editar')::boolean then
    raise exception 'M18 el supervisor enumero excluidos o pudo editar';
  end if;
end;
$test$;
reset role;

select 'METAS_VERSIONADAS_TX_OK' as resultado;
rollback;
