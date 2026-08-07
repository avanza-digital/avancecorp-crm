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
  ('71000000-0000-4000-8000-000000000007','authenticated','authenticated','metas-a@test.invalid',now(),'{}','{}',now(),now());

insert into public.perfiles(id,nombre_completo,correo,rol,activo) values
  ('71000000-0000-4000-8000-000000000001','Metas Gerencia','metas-g@test.invalid','superadmin',true),
  ('71000000-0000-4000-8000-000000000002','Metas Supervisor','metas-s@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-000000000003','Metas Vendedor','metas-v@test.invalid','comercial',true),
  ('71000000-0000-4000-8000-000000000004','Metas Directorio','metas-d@test.invalid','directorio',true),
  ('71000000-0000-4000-8000-000000000005','Metas Cliente','metas-c@test.invalid','cliente',true),
  ('71000000-0000-4000-8000-000000000006','Metas Superadmin','metas-sa@test.invalid','superadmin',true),
  ('71000000-0000-4000-8000-000000000007','Metas Admin','metas-a@test.invalid','admin',true);

-- Simula una fila residual/preexistente por debajo de los triggers defensivos:
-- aunque exista físicamente, el rol efectivo debe quedar enmascarado.
set local session_replication_role=replica;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values
  ('71000000-0000-4000-8000-000000000001','gerencia',null,true),
  ('71000000-0000-4000-8000-000000000002','supervisor',null,true),
  ('71000000-0000-4000-8000-000000000003','vendedor','71000000-0000-4000-8000-000000000002',true),
  ('71000000-0000-4000-8000-000000000006','vendedor','71000000-0000-4000-8000-000000000002',true);
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

-- Un contrato CRM creado/confirmado en el mes alimenta cumplimiento, sin sumar USD.
reset request.jwt.claim.sub;
insert into public.contratos(
  id,cliente_id,numero_contrato,capital,moneda,tasa_anual,modalidad,tipo_interes,
  categoria,estado,fecha_inicio,fecha_vencimiento,creado_por,creado_en
) values (
  '71000000-0000-4000-8000-000000000101',
  '71000000-0000-4000-8000-000000000005',
  'TEST-META-7101',25000,'PEN',10,'mensual','simple','nuevo','activo',
  date '2099-07-01',date '2100-07-01','71000000-0000-4000-8000-000000000003',
  timestamptz '2099-07-15 12:00:00-05'
);
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
  );
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $test$
declare v_c jsonb; v_vendedor jsonb; v_nuevo_pen jsonb;
begin
  v_c:=crm.cumplimiento_metas_fn(date '2099-07-01');
  select v.value,d.value into v_vendedor,v_nuevo_pen
  from jsonb_array_elements(v_c->'vendedores') v
  cross join lateral jsonb_array_elements(v.value->'detalles') d
  where v.value->>'vendedor_id'='71000000-0000-4000-8000-000000000003'
    and d.value->>'categoria'='nuevo' and d.value->>'moneda'='PEN';
  if (v_nuevo_pen->>'capital_real')::numeric<>25000
     or (v_nuevo_pen->>'contratos_real')::int<>1
     or (v_vendedor->>'convertidos')::int<>1
     or (v_vendedor->>'resueltos')::int<>2
     or (v_vendedor->>'conversion_real')::numeric<>50
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
     ) then
    raise exception 'M13 ACL legacy/nuevo incorrecta';
  end if;
  if not exists(select 1 from public.audit_log
    where tabla='crm.meta_periodos' and usuario_id='71000000-0000-4000-8000-000000000001') then
    raise exception 'M14 publicaciones sin auditoria';
  end if;
end;
$test$;

select 'METAS_VERSIONADAS_TX_OK' as resultado;
rollback;
