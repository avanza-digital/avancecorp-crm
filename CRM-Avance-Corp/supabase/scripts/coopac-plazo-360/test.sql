\set ON_ERROR_STOP on
-- Ejecutar exclusivamente en los bancos declarados, con esquema copiado de local.
-- Fixtures directas con réplica SOLO para probar conservación y CHECKs.
-- No acredita la conversión ni la corrección autenticada completa.
do $$ begin
  if current_database() not in ('coopac_360_20261016','coopac_360_replay_20261016') then raise exception 'Banco incorrecto'; end if;
end $$;
set session_replication_role=replica;
select exists(select 1 from information_schema.columns where table_schema='crm'
  and table_name='cierres_externos' and column_name='base_plazo') as ya_instalada \gset
\if :ya_instalada
\echo Conservando las fixtures históricas ya preparadas.
\else
insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,
  nombre_completo,numero_transaccion,vendedor_id,creado_por,fecha_comercial,fecha_imputacion,
  plazo_meses,tasa_anual,vence_en)
values('00000000-0000-4000-8000-000000000001',gen_random_uuid(),'qorilazo',1000,'PEN','DNI','49990001',
  'ENSAYO SINTETICO','ENSAYO-360-ANTIGUO',gen_random_uuid(),gen_random_uuid(),'2026-01-31','2026-01-31',12,12,'2027-01-31'),
('00000000-0000-4000-8000-000000000002',gen_random_uuid(),'prodelco',2000,'USD','DNI','49990002',
  'ENSAYO HISTORICO','ENSAYO-360-HISTORICO',gen_random_uuid(),gen_random_uuid(),null,null,null,null,'2027-03-10')
on conflict(id) do nothing;
\endif
create temporary table foto_cierres as
select id,to_jsonb(c)-'base_plazo' as datos from crm.cierres_externos c
where id in ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002');
create temporary table foto_funciones as
select p.oid,p.proname,p.proacl,p.proowner,md5(pg_get_functiondef(p.oid)) as huella
from pg_proc p where p.pronamespace in ('crm'::regnamespace,'private'::regnamespace) and p.prokind='f';
\if :ya_instalada
\echo Migración ya ensayada en este banco; se comprueban las condiciones.
\else
\ir ../../migrations/20261016195003_crm_coopac_plazo_360_dias.sql
\endif
create function pg_temp.exigir(ok boolean,mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'COOPAC360: %',mensaje; end if; end $$;
select pg_temp.exigir(not exists(select 1 from foto_cierres f join crm.cierres_externos c using(id)
  where to_jsonb(c)-'base_plazo'<>f.datos or c.base_plazo<>'calendario'),'históricos alterados');
select pg_temp.exigir(not exists(select 1 from foto_funciones f join pg_proc p using(oid)
  where f.proacl is distinct from p.proacl or f.proowner<>p.proowner),'ACL o propietario alterados');
select pg_temp.exigir(not exists(select 1 from foto_funciones f join pg_proc p using(oid)
  where f.proname not in ('coopac_validar_condiciones','inversionista_corregir_coopac_fn')
    and f.huella<>md5(pg_get_functiondef(p.oid))),'funciones ajenas alteradas');
select pg_temp.exigir(not has_function_privilege('anon','private.coopac_validar_condiciones_base(date,integer,numeric,text)','EXECUTE')
  and not has_function_privilege('authenticated','private.coopac_validar_condiciones_base(date,integer,numeric,text)','EXECUTE'),
  'helper interno expuesto');
select pg_temp.exigir((select relrowsecurity from pg_class where oid='crm.cierres_externos'::regclass)
  and not has_table_privilege('authenticated','crm.cierres_externos','INSERT'),'acceso directo a cierres');
do $casos$
declare c record; n integer:=0;
begin
  for c in select * from (values
    ('2026-01-31'::date,1,'2026-03-02'::date),
    ('2024-01-31'::date,1,'2024-03-01'::date),
    ('2024-02-29'::date,12,'2025-02-23'::date),
    ('2026-08-31'::date,6,'2027-02-27'::date),
    ('2026-09-14'::date,12,'2027-09-09'::date),
    ('2026-10-16'::date,12,'2027-10-11'::date),
    ('2026-10-16'::date,24,'2028-10-05'::date)
  ) x(inicio,plazo,fin) loop
    perform pg_temp.exigir(private.coopac_validar_condiciones(c.inicio,c.plazo,12)=c.fin,'fecha calculada');
    perform pg_temp.exigir(private.coopac_validar_condiciones(c.inicio,c.plazo,12)-c.inicio=c.plazo*30,'días exactos');
    n:=n+1;
  end loop;
  perform pg_temp.exigir(private.coopac_validar_condiciones_base('2026-01-31',12,12,'calendario')='2027-01-31','corrección histórica');
  perform pg_temp.exigir(private.coopac_validar_condiciones_base('2026-01-31',1,12,'calendario')='2026-02-28','fin de mes histórico');
  raise notice 'PASS: % fechas y diferencias exactas; 2 cálculos históricos',n;
end $casos$;
do $invalidos$
declare s text; n integer:=0;
begin
  foreach s in array array[
    $$select private.coopac_validar_condiciones(null,12,12)$$,
    $$select private.coopac_validar_condiciones('infinity',12,12)$$,
    $$select private.coopac_validar_condiciones('2026-01-01',0,12)$$,
    $$select private.coopac_validar_condiciones('2026-01-01',1201,12)$$,
    $$select private.coopac_validar_condiciones('2026-01-01',12,null)$$,
    $$select private.coopac_validar_condiciones('2026-01-01',12,'NaN')$$,
    $$select private.coopac_validar_condiciones('2026-01-01',12,'Infinity')$$,
    $$select private.coopac_validar_condiciones('2026-01-01',12,0)$$,
    $$select private.coopac_validar_condiciones('2026-01-01',12,12.345)$$,
    $$select private.coopac_validar_condiciones_base('2026-01-01',12,12,null)$$
  ] loop
    begin
      execute s;
      raise exception 'Se aceptó una condición inválida';
    exception when sqlstate '22023' then n:=n+1;
    end;
  end loop;
  raise notice 'PASS: % entradas inválidas rechazadas',n;
end $invalidos$;
do $tabla$
declare empresa text; v_cierre uuid; n integer:=0; antiguo date;
begin
  foreach empresa in array array['qorilazo','prodelco'] loop
    insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,
      numero_transaccion,vendedor_id,creado_por,fecha_comercial,fecha_imputacion,plazo_meses,tasa_anual,vence_en)
    values(gen_random_uuid(),empresa,1500,'PEN','DNI','49990003','ENSAYO NUEVO',empresa||'-360',
      gen_random_uuid(),gen_random_uuid(),'2026-01-31','2026-01-31',12,12,'2027-01-26') returning crm.cierres_externos.id into v_cierre;
    perform pg_temp.exigir((select base_plazo='dias_360' from crm.cierres_externos c where c.id=v_cierre),'DEFAULT nuevo');
    begin
      update crm.cierres_externos set vence_en='2027-01-31' where crm.cierres_externos.id=v_cierre;
      raise exception 'Se aceptó vencimiento calendario en contrato nuevo';
    exception when check_violation then n:=n+1;
    end;
    begin
      update crm.cierres_externos set base_plazo='otra' where crm.cierres_externos.id=v_cierre;
      raise exception 'Se aceptó convención desconocida';
    exception when check_violation then n:=n+1;
    end;
  end loop;
  update crm.cierres_externos c set nota='Corrección de nota' where c.id='00000000-0000-4000-8000-000000000001';
  select c.vence_en into antiguo from crm.cierres_externos c where c.id='00000000-0000-4000-8000-000000000001';
  perform pg_temp.exigir(antiguo='2027-01-31','nota cambia vencimiento antiguo');
  raise notice 'PASS: ambas cooperativas; % restricciones; corrección de nota conserva fecha',n;
end $tabla$;
set session_replication_role=origin;
select 'COOPAC_360_SQL_PASS' as resultado;
