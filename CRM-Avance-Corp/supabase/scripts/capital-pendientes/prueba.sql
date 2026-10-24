-- Exclusivamente en una rama vacía verificada por el runner. Todo termina en rollback.
begin;
set local client_min_messages='notice';
set local statement_timeout='90s';
set local lock_timeout='5s';
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.perfiles)
    or exists(select 1 from public.contratos) or exists(select 1 from crm.cierres_externos)
    or exists(select 1 from crm.meta_periodos) or exists(select 1 from crm.capital_cortes_valorados) then
    raise exception 'El banco debe estar vacío; no se borran datos para preparar esta prueba';
  end if;
end $$;
create function pg_temp.comprobar(ok boolean,mensaje text) returns void language plpgsql as $$ begin
  if ok is distinct from true then raise exception 'FAIL: %',mensaje; end if;
  raise notice 'PASS: %',mensaje;
end $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
  select ('f3000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
set local session_replication_role=replica;
insert into auth.users(id,aud,role,email)
select pg_temp.id(n),'authenticated','authenticated','capital-pendientes-'||n||'@example.test'
from generate_series(1,7) n;
insert into public.perfiles(id,nombre_completo,rol)
select pg_temp.id(n),'Persona sintética '||n,case n when 3 then 'admin' when 4 then 'cliente' else 'analista' end
from generate_series(1,7) n;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id)
values(pg_temp.id(1),'supervisor',null),(pg_temp.id(2),'vendedor',pg_temp.id(1)),
  (pg_temp.id(3),'gerencia',null),(pg_temp.id(5),'supervisor',null),(pg_temp.id(6),'vendedor',pg_temp.id(5)),
  (pg_temp.id(7),'vendedor',pg_temp.id(5));
insert into crm.productos_inversion(id,codigo) values(pg_temp.id(100),'CAPITAL-PENDIENTES');
insert into crm.producto_versiones(id,producto_id,numero_version,nombre,vigente_desde,estado,publicada_en)
values(pg_temp.id(101),pg_temp.id(100),1,'Producto sintético','2026-01-01','publicada',now());
insert into crm.producto_condiciones(id,version_id,orden,categoria,moneda,plazo_meses,modalidad,tipo_interes,
  capital_minimo,capital_maximo,tasa_referencia,tasa_minima,tasa_maxima)
values(pg_temp.id(102),pg_temp.id(101),1,'nuevo','PEN',12,'mensual','simple',100,100000000,15,1,50),
  (pg_temp.id(103),pg_temp.id(101),2,'nuevo','USD',12,'mensual','simple',100,100000000,15,1,50);
insert into crm.meta_periodos(id,periodo,revision,publicada_por)
values(pg_temp.id(104),'2026-10-01',1,pg_temp.id(3));
insert into crm.metas_vendedor(id,meta_periodo_id,vendedor_id,supervisor_id,conversion_objetivo)
values(pg_temp.id(105),pg_temp.id(104),pg_temp.id(2),pg_temp.id(1),10),
  (pg_temp.id(106),pg_temp.id(104),pg_temp.id(6),pg_temp.id(5),10);
insert into crm.metas_vendedor_detalle(meta_vendedor_id,categoria,moneda,capital_objetivo,contratos_objetivo)
select m.id,d.categoria,d.moneda,case when d.categoria='nuevo' and d.moneda='PEN' then 100000 else 0 end,0
from crm.metas_vendedor m cross join(values('nuevo','PEN'),('nuevo','USD'),('renovacion','PEN'),
  ('renovacion','USD'),('upgrade','PEN'),('upgrade','USD')) d(categoria,moneda);
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,tope_referidos_pct,nota)
values('2026-10-01',1,0,15,'Banco sintético de capital') on conflict(vigente_desde) do nothing;
insert into crm.capital_valoracion_politica default values on conflict(id) do nothing;
update crm.capital_valoracion_politica set activa=true where id;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por,creado_en)
values(pg_temp.id(201),'PENDIENTES-PEN-10',pg_temp.id(4),1000,'PEN','mensual','2026-10-23','2027-10-23',
  'nuevo',pg_temp.id(102),'2026-10-23',pg_temp.id(2),pg_temp.id(3),'2026-10-23 10:00 America/Lima');
set local session_replication_role=origin;
create temp table cortes(etapa text primary key,id uuid,revision integer);
grant select on cortes to authenticated;
select crm.reconciliar_capital_valoraciones_fn(200);
insert into cortes select 'inicial',id,revision from crm.capital_cortes_valorados
  where periodo='2026-10-01' order by revision desc limit 1;
select pg_temp.comprobar((select jsonb_array_length(c.produccion)=1 from crm.capital_cortes_valorados c
  join cortes t on t.id=c.id where t.etapa='inicial'),'precondición: el PEN de las 10 ya tenía una foto publicada');

set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por,creado_en)
values(pg_temp.id(202),'PENDIENTES-USD-11',pg_temp.id(4),20000,'USD','mensual','2026-10-23','2027-10-23',
  'nuevo',pg_temp.id(103),'2026-10-23',pg_temp.id(2),pg_temp.id(3),'2026-10-23 11:00 America/Lima'),
  (pg_temp.id(203),'PENDIENTES-PEN-12',pg_temp.id(4),5000,'PEN','mensual','2026-10-23','2027-10-23',
  'nuevo',pg_temp.id(102),'2026-10-23',pg_temp.id(2),pg_temp.id(3),'2026-10-23 12:00 America/Lima');
set local session_replication_role=origin;
select crm.reconciliar_capital_valoraciones_fn(200);
insert into cortes select 'pendiente',id,revision from crm.capital_cortes_valorados
  where periodo='2026-10-01' order by revision desc limit 1;
select pg_temp.comprobar((select c.corte=least(date '2026-10-31',(statement_timestamp() at time zone 'America/Lima')::date)
  and jsonb_array_length(c.base)=2 and jsonb_array_length(c.produccion)=2 and jsonb_array_length(c.facturacion)=2
  and c.revision=(select revision+1 from cortes where etapa='inicial')
  and (select sum((p->>'equivalente_pen')::numeric) from jsonb_array_elements(c.produccion) p)=6000
  and (select array_agg((p->>'fuente_id')::uuid order by p->>'fuente_id') from jsonb_array_elements(c.produccion) p)
    =array[pg_temp.id(201),pg_temp.id(203)]
  and not exists(select 1 from jsonb_array_elements(c.base) p where p->>'valoracion_id' is null
    or p->>'identidad_persona' is null)
  from crm.capital_cortes_valorados c join cortes t on t.id=c.id where t.etapa='pendiente'),
  'TEST 1: corte hasta hoy con ambos PEN (6000), sin USD en base, producción ni facturación');

select set_config('request.jwt.claim.sub',pg_temp.id(2)::text,true);
set local role authenticated;
do $$ declare r jsonb; d jsonb; begin
  r:=crm.cumplimiento_metas_v2_fn('2026-10-01');
  perform pg_temp.comprobar((r#>>'{capital_valoracion,personas,0,capital_valorado,equivalente_pen}')::numeric=6000
    and (r#>>'{capital_valoracion,personas,0,capital_valorado,contratos}')::int=2,
    'metas del analista cuentan solo las dos ventas valoradas');
  d:=crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2));
  perform pg_temp.comprobar(d->'cobertura'->'pendientes'='{"cantidad":1,"pen":0,"usd":20000}'::jsonb
    and d#>'{cobertura,ventas_pendientes,0}'=jsonb_build_object('fuente','contrato','fuente_id',pg_temp.id(202),
      'fecha_comercial','2026-10-23','fecha_imputacion','2026-10-23','moneda','USD','monto',20000,'motivo','cotizacion_pendiente')
    and (d->>'total_pen')::numeric=6000 and jsonb_array_length(d->'operaciones')=2,
    'ventas del analista: USD pendiente con fuente, monto original y fechas; total PEN independiente');
  perform pg_temp.comprobar(d-'cobertura'=crm.capital_operaciones_valoradas_fn('2026-10-01',pg_temp.id(2)),
    'la nueva puerta conserva íntegro el detalle y la autorización v1');
end $$;
select jsonb_build_object('capital_fixture','pendiente','payload',crm.cumplimiento_metas_v2_fn('2026-10-01'));
select jsonb_build_object('capital_fixture','detalle-pendiente','payload',crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2)));
reset role;

-- El total del detalle incluye todas las páginas y usa el mismo corte y día de la malla.
create function pg_temp.comprobar_facturacion(total_esperado numeric) returns void language plpgsql as $$
declare m jsonb; l jsonb; t_malla numeric; t_lista numeric;
begin
  m:=crm.facturacion_diaria_v2_fn('2026-10-01');
  l:=crm.listar_operaciones_facturacion_v3_fn('2026-10-23','2026-10-23',p_pagina=>2,p_tamano=>25,
    p_cortes=>jsonb_build_object('2026-10-01',m->>'corte_id'));
  select sum((f->>'capital_equivalente_pen')::numeric) into t_malla
    from jsonb_array_elements(m->'filas') f where f->>'dia'='2026-10-23';
  select sum((f->>'equivalente_pen')::numeric) into t_lista from jsonb_array_elements(l->'totales_por_mes') f;
  perform pg_temp.comprobar(t_malla=total_esperado and t_lista=t_malla
    and jsonb_array_length(l->'filas')=0,'TEST 5: total de lista independiente de página y cuadro diario concilian '||total_esperado||' PEN');
end $$;
select set_config('request.jwt.claim.sub',pg_temp.id(1)::text,true);
set local role authenticated;
select pg_temp.comprobar_facturacion(6000);
select jsonb_build_object('capital_fixture','facturacion-pendiente','payload',crm.facturacion_diaria_v2_fn('2026-10-01'));
select jsonb_build_object('capital_fixture','lista-pendiente','payload',crm.listar_operaciones_facturacion_v3_fn(
  '2026-10-01','2026-10-31',p_cortes=>jsonb_build_object('2026-10-01',crm.facturacion_diaria_v2_fn('2026-10-01')->>'corte_id')));
reset role;
select set_config('request.jwt.claim.sub','',true);
select crm.reconciliar_capital_valoraciones_fn(200);
select pg_temp.comprobar((select count(*)=2 from crm.capital_cortes_valorados where periodo='2026-10-01')
  and private.publicar_corte_capital('2026-10-01')=(select id from cortes where etapa='pendiente'),
  'TEST 4: con pendiente, repetir sin cambios conserva id, revisión y número de fotos');

-- La fecha del cierre se simula solo dentro del savepoint del banco.
savepoint sello_pendiente;
do $$ declare def text; begin
  select pg_get_functiondef('crm.cerrar_periodo(date)'::regprocedure) into def;
  def:=replace(def,'pg_catalog.now()','now()');
  execute replace(def,'now()',E'timestamptz ''2026-11-12 12:00 America/Lima''');
  select pg_get_functiondef('private.publicar_corte_capital(date)'::regprocedure) into def;
  execute replace(def,E'(statement_timestamp() at time zone ''America/Lima'')::date',E'date ''2026-11-12''');
end $$;
select private.publicar_corte_capital('2026-10-01');
select pg_temp.comprobar((select corte=date '2026-10-31' and jsonb_array_length(produccion)=2
  from crm.capital_cortes_valorados where periodo='2026-10-01' order by revision desc limit 1),
  'precondición del cierre: corte al último día del mes con USD aún pendiente');
select set_config('request.jwt.claim.sub',pg_temp.id(3)::text,true);
set local role authenticated;
do $$ begin
  begin
    perform crm.cerrar_periodo('2026-10-01');
    raise exception 'FAIL: selló un mes con USD pendiente';
  exception when sqlstate 'PT409' then
    if sqlerrm not like 'Cierre pendiente: reconciliar % valoraciones de capital%' then raise; end if;
    raise notice 'PASS: TEST 3: cierre real rechazado por valoración pendiente';
  end;
end $$;
reset role;
select pg_temp.comprobar(not exists(select 1 from crm.periodos_cerrados where periodo='2026-10-01')
  and not exists(select 1 from crm.capital_mes_sellos where periodo='2026-10-01'),
  'el rechazo conserva abierto el mes y no crea sello de capital');
rollback to savepoint sello_pendiente;

-- Un pendiente ajeno no aparece en la cobertura específica del analista ni en su equipo.
savepoint permisos;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por,creado_en)
values(pg_temp.id(204),'PENDIENTE-AJENO',pg_temp.id(4),7000,'USD','mensual','2026-10-23','2027-10-23',
  'nuevo',pg_temp.id(103),'2026-10-23',pg_temp.id(6),pg_temp.id(3),'2026-10-23 13:00 America/Lima');
set local session_replication_role=origin;
select set_config('request.jwt.claim.sub',pg_temp.id(2)::text,true);
set local role authenticated;
select pg_temp.comprobar((crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2))#>>'{cobertura,pendientes,usd}')::numeric=20000,
  'RLS: el detalle propio no incluye los 7000 USD ajenos');
do $$ begin
  begin perform crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(6));
    raise exception 'FAIL: el vendedor leyó otro equipo';
  exception when insufficient_privilege then raise notice 'PASS: RLS vendedor ajeno rechazado'; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',pg_temp.id(1)::text,true);
set local role authenticated;
select pg_temp.comprobar((crm.facturacion_diaria_v2_fn('2026-10-01')#>>'{cobertura,pendientes,usd}')::numeric=20000,
  'RLS: Facturación limita también los pendientes al equipo autorizado');
do $$ begin
  begin perform crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(6));
    raise exception 'FAIL: el supervisor leyó otro equipo';
  exception when insufficient_privilege then raise notice 'PASS: RLS supervisor ajeno rechazado'; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',pg_temp.id(3)::text,true);
set local role authenticated;
select pg_temp.comprobar((crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2))#>>'{cobertura,pendientes,usd}')::numeric=20000
  and (crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(6))#>>'{cobertura,pendientes,usd}')::numeric=7000,
  'RLS: gerencia consulta cada analista sin mezclar sus pendientes');
reset role;
rollback to savepoint permisos;

savepoint sin_meta;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por,creado_en)
values(pg_temp.id(205),'PENDIENTE-SIN-META',pg_temp.id(4),9000,'USD','mensual','2026-10-23','2027-10-23',
  'nuevo',pg_temp.id(103),'2026-10-23',pg_temp.id(7),pg_temp.id(3),'2026-10-23 14:00 America/Lima');
set local session_replication_role=origin;
select crm.reconciliar_capital_valoraciones_fn(200);
select set_config('request.jwt.claim.sub',pg_temp.id(7)::text,true);
set local role authenticated;
select pg_temp.comprobar((crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{capital_valoracion,cobertura,pendientes,usd}')::numeric=9000
  and jsonb_array_length(crm.cumplimiento_metas_v2_fn('2026-10-01')#>'{capital_valoracion,personas}')=0,
  'sin meta ni producción valorada, el propio analista conserva su aviso de USD pendiente');
do $$ begin
  begin
    perform crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(7));
    raise exception 'FAIL: se amplió la autorización del detalle fuera de personas';
  exception when insufficient_privilege then
    raise notice 'PASS: sin meta ni capital valorado, el detalle conserva la autorización v1; el aviso está en cumplimiento';
  end;
end $$;
reset role;
rollback to savepoint sin_meta;

select private.consolidar_tc_venta(jsonb_build_object('fecha_corte','2026-10-23','politica','sbs_punto_medio_7d_v1',
  'publicacion_confirmada','2026-10-23','fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('a',64),
  'pares',(select jsonb_agg(jsonb_build_object('fecha',date '2026-10-23'-n,'compra','3.4','venta','3.4') order by n desc)
    from generate_series(0,6) n)));
select crm.reconciliar_capital_valoraciones_fn(200);
insert into cortes select 'valorado',id,revision from crm.capital_cortes_valorados
  where periodo='2026-10-01' order by revision desc limit 1;
select pg_temp.comprobar((select c.revision=(select revision+1 from cortes where etapa='pendiente')
  and jsonb_array_length(c.base)=3 and jsonb_array_length(c.produccion)=3 and jsonb_array_length(c.facturacion)=3
  and (select sum((p->>'equivalente_pen')::numeric) from jsonb_array_elements(c.produccion) p)=74000
  and (select (p->>'equivalente_pen')::numeric=68000 and (p->>'tasa')::numeric=3.4
    from jsonb_array_elements(c.produccion) p where (p->>'fuente_id')::uuid=pg_temp.id(202))
  from crm.capital_cortes_valorados c join cortes t on t.id=c.id where t.etapa='valorado'),
  'TEST 2: al llegar TC, revisión nueva con tres ventas, USD a 68000 y total 74000 PEN');
select set_config('request.jwt.claim.sub',pg_temp.id(2)::text,true);
set local role authenticated;
select pg_temp.comprobar((crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2))#>'{cobertura,ventas_pendientes}')='[]'::jsonb
  and (crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{capital_valoracion,cobertura,pendientes,cantidad}')::int=0,
  'TEST 2: ventas del analista y metas quedan sin pendientes');
select pg_temp.comprobar((crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2),
    (select id from cortes where etapa='pendiente'))#>>'{cobertura,por_incorporar,cantidad}')::int=1
  and (crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2),
    (select id from cortes where etapa='pendiente'))#>>'{cobertura,pendientes,cantidad}')::int=0,
  'consultar el corte anterior tras TC distingue una venta ya valorada por incorporar de un pendiente');
select jsonb_build_object('capital_fixture','activo','payload',crm.cumplimiento_metas_v2_fn('2026-10-01'));
select jsonb_build_object('capital_fixture','detalle-activo','payload',crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2)));
reset role;
select set_config('request.jwt.claim.sub',pg_temp.id(1)::text,true);
set local role authenticated;
select pg_temp.comprobar_facturacion(74000);
reset role;
select set_config('request.jwt.claim.sub','',true);
select crm.reconciliar_capital_valoraciones_fn(200);
select pg_temp.comprobar((select count(*)=3 from crm.capital_cortes_valorados where periodo='2026-10-01')
  and private.publicar_corte_capital('2026-10-01')=(select id from cortes where etapa='valorado'),
  'TEST 4: sin pendientes, repetir sin cambios tampoco publica revisión');
select pg_temp.comprobar(not has_function_privilege('anon','crm.capital_operaciones_valoradas_v2_fn(date,uuid,uuid)','EXECUTE')
  and not has_function_privilege('service_role','crm.capital_operaciones_valoradas_v2_fn(date,uuid,uuid)','EXECUTE')
  and not has_function_privilege('authenticated','private.publicar_corte_capital(date)','EXECUTE')
  and not has_table_privilege('authenticated','crm.capital_cortes_valorados','SELECT'),
  'RLS: puerta autenticada mínima; publicador y foto global siguen privados');

savepoint sello_completo;
do $$ declare def text; begin
  select pg_get_functiondef('crm.cerrar_periodo(date)'::regprocedure) into def;
  def:=replace(def,'pg_catalog.now()','now()');
  execute replace(def,'now()',E'timestamptz ''2026-11-12 12:00 America/Lima''');
  select pg_get_functiondef('private.publicar_corte_capital(date)'::regprocedure) into def;
  execute replace(def,E'(statement_timestamp() at time zone ''America/Lima'')::date',E'date ''2026-11-12''');
end $$;
select set_config('request.jwt.claim.sub',pg_temp.id(3)::text,true);
set local role authenticated;
select crm.cerrar_periodo('2026-10-01');
select pg_temp.comprobar((crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2))#>>'{cobertura,estado}')='completo'
  and (crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2))#>'{cobertura,ventas_pendientes}')='[]'::jsonb
  and (crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2))->>'total_pen')::numeric=74000,
  'mes sellado con cobertura completa: detalle conserva 74000 PEN y ningún pendiente');
select pg_temp.comprobar((crm.capital_operaciones_valoradas_v2_fn('2026-10-01',pg_temp.id(2))->'cobertura')-'generado_en'
  =crm.cumplimiento_metas_v2_fn('2026-10-01')#>'{capital_valoracion,cobertura}',
  'la cobertura sellada coincide con metas salvo generado_en, metadata opcional del contrato');
reset role;
select pg_temp.comprobar(private.publicar_corte_capital('2026-10-01')=
  (select corte_id from crm.capital_mes_sellos where periodo='2026-10-01'),
  'el publicador sigue devolviendo el mismo sello inmutable');
rollback to savepoint sello_completo;
rollback;
