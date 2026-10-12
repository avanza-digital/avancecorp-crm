-- Solo base Docker dedicada, vacía, con la candidata instalada. Todos los datos sintéticos hacen rollback.
\set ON_ERROR_STOP on
begin;
set local statement_timeout = '120s';
set local jit = off;
set local max_parallel_workers_per_gather = 0;
do $$ begin
  if current_database() <> 'conversion_cierres_20261012' or current_user <> 'postgres'
    or exists(select 1 from crm.leads) or exists(select 1 from public.perfiles) then
    raise exception 'Solo banco sintético vacío conversion_cierres_20261012';
  end if;
end $$;

-- Construye ESTADOS de lectura, no prueba los comandos de venta/offboarding.
-- Se suspenden los triggers de negocio SOLO durante fixtures; FK y CHECK siguen activos.
alter table public.perfiles disable trigger user;
alter table crm.equipo disable trigger user;
alter table public.contratos disable trigger user;
alter table crm.productos_inversion disable trigger user;
alter table crm.producto_versiones disable trigger user;
alter table crm.producto_condiciones disable trigger user;
alter table crm.leads disable trigger user;
alter table crm.lead_asignaciones disable trigger user;
alter table crm.conversion_acreditaciones disable trigger user;
alter table crm.operaciones_cartera disable trigger user;
alter table crm.periodos_cerrados disable trigger user;

create function pg_temp.uid(n integer) returns uuid language sql immutable as
  $$ select ('a0000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
insert into auth.users(id,email) select pg_temp.uid(n), 'actor'||n||'@cierres.test' from generate_series(1,13) n;
insert into public.perfiles(id,nombre_completo,correo,rol,activo,tipo_documento,
  debe_cambiar_password,titular_distinto,titular_distinto_usd)
select pg_temp.uid(n), 'ACTOR SINTETICO '||n, 'actor'||n||'@cierres.test',
  case when n in (2,10,11) then 'admin' when n=6 then 'directorio' when n>=12 then 'cliente' else 'comercial' end,
  n not in (9,11),'DNI',false,false,false from generate_series(1,13) n;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select pg_temp.uid(n), case when n in (1,8,9) then 'coordinador' when n in (2,10,11) then 'gerencia'
  when n=3 then 'supervisor' when n=6 then 'directorio' else 'vendedor' end,
  case when n in (4,5) then pg_temp.uid(3) end, n not in (8,10)
from generate_series(1,11) n where n<>7;
insert into crm.sla_politicas(id,version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
values(pg_temp.uid(90),1,'2000-01-01','America/Lima','corrido',60,120);
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,tope_referidos_pct)
values('2000-01-01',1,0.15,5);
insert into crm.conversion_politica(unica,activada_en,manifiesto_huella,resultado)
values(true,now(),'fixture','{}');

insert into crm.productos_inversion(id,codigo) values(pg_temp.uid(91),'CIERRES-TEST');
insert into crm.producto_versiones(id,producto_id,numero_version,nombre,vigente_desde)
values(pg_temp.uid(92),pg_temp.uid(91),1,'PRODUCTO SINTETICO','2026-01-01');
insert into crm.producto_condiciones(id,version_id,orden,categoria,moneda,plazo_meses,modalidad,tipo_interes,
 capital_minimo,capital_maximo,tasa_referencia,tasa_minima,tasa_maxima)
values(pg_temp.uid(93),pg_temp.uid(92),1,'nuevo','PEN',12,'mensual','simple',100,100000,15,10,20);
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,
  modalidad,tipo_interes,fecha_inicio,fecha_vencimiento,estado,categoria,creado_por,analista_cierre_id,es_demo,producto_condicion_id,fecha_cierre_comercial)
select pg_temp.uid(200+n), 'CIERRE-TEST-'||n,pg_temp.uid(case when n=29 then 13 else 12 end),1000,'PEN',15,
 'mensual','simple','2026-10-01','2027-10-01','activo',case when n>=27 then 'upgrade' else 'nuevo' end,
 pg_temp.uid(2),pg_temp.uid(case when n=26 then 5 else 4 end),n=8,pg_temp.uid(93),'2026-10-01'
from generate_series(1,29) n where n<>9;
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,vendedor_id,alta_manual,monto_estimado,creado_en)
select pg_temp.uid(100+n), 'CIERRE SINTETICO '||n,'+5199988'||lpad(n::text,4,'0'),
 case when n in (1,7) then 'referido' when n in (2,3) then 'formulario' when n=5 then 'oficina'
 when n=6 then 'base_cargada' else 'landing' end,
 'convertido',pg_temp.uid(case when n=26 then 5 else 4 end),n in (1,3,4,7),1000,'2026-10-01 05:00Z'
from generate_series(1,26) n;
insert into crm.lead_asignaciones(id,lead_id,ciclo_n,episodio_n,analista_id,motivo_apertura,
 asignado_en,moneda,origen,finalizado_en,motivo_cierre,resultado,resultado_en,
 sla_global_iniciado_en,sla_politica_asignacion_id,primera_gestion_limite_en,primer_contacto_limite_en)
select pg_temp.uid(300+n),l.id,1,1,l.vendedor_id,'asignado','2026-10-01 05:00Z','PEN',l.origen,
 '2026-10-07 05:00Z','convertido','convertido','2026-10-07 05:00Z',
 '2026-10-01 05:00Z',pg_temp.uid(90),'2026-10-01 06:00Z','2026-10-01 07:00Z'
from generate_series(1,26) n join crm.leads l on l.id=pg_temp.uid(100+n);
insert into crm.conversion_acreditaciones(lead_id,episodio_id,analista_id,origen,fuente_tipo,fuente_id,
 fecha_comercial,confirmado_en,vinculado_en,acreditado_en,periodo_comercial,plazo_hasta,estado,motivo)
select l.id,pg_temp.uid(300+n),l.vendedor_id,l.origen,'contrato',pg_temp.uid(200+n),
 case when n=1 then date '2026-10-01' else date '2026-10-07' end,
 '2026-10-07 05:00Z','2026-10-07 05:00Z','2026-10-07 05:00Z','2026-10-01',private.conversion_plazo_hasta('2026-10-01'),
 case when n=10 then 'fuera_de_plazo' else 'acreditada' end,'Fixture lectura'
from generate_series(1,26) n join crm.leads l on l.id=pg_temp.uid(100+n);
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,fecha_operacion,periodo,
 moneda,elegible_conversion,fuente,creado_por)
select pg_temp.uid(case when n=29 then 13 else 12 end),pg_temp.uid(4),'upgrade',pg_temp.uid(200+n),
 date '2026-10-01'+(n-27),'2026-10-01','PEN',true,'flujo_cartera',pg_temp.uid(2)
from generate_series(27,29) n;
insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
values('2026-09-01',0.15,1,'{}');

alter table public.perfiles enable trigger user;
alter table crm.equipo enable trigger user;
alter table public.contratos enable trigger user;
alter table crm.productos_inversion enable trigger user;
alter table crm.producto_versiones enable trigger user;
alter table crm.producto_condiciones enable trigger user;
alter table crm.leads enable trigger user;
alter table crm.lead_asignaciones enable trigger user;
alter table crm.conversion_acreditaciones enable trigger user;
alter table crm.operaciones_cartera enable trigger user;
alter table crm.periodos_cerrados enable trigger user;

create function pg_temp.sesion(n integer) returns void language sql as $$
 select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.uid(n),'role','authenticated')::text,true);
 select set_config('request.jwt.claim.sub',pg_temp.uid(n)::text,true);
$$;
create function pg_temp.exigir(ok boolean,mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',mensaje; end if; end $$;
create function pg_temp.denegado(n integer) returns void language plpgsql as $$
begin
 perform pg_temp.sesion(n);
 begin
   perform crm.conversion_cierres_coordinacion_fn(null,'2099-01-01');
   raise exception 'Rol % admitido',n;
 exception when insufficient_privilege then null; end;
end $$;

-- Propiedades y ACL reales; no se invocan funciones privadas con un rol sin EXECUTE.
select pg_temp.exigir(not exists(select 1 from pg_trigger where tgrelid in
 ('crm.leads'::regclass,'crm.equipo'::regclass,'public.perfiles'::regclass,'crm.conversion_acreditaciones'::regclass)
 and tgenabled='D'),'triggers encendidos antes de consultar');
select pg_temp.exigir((select bool_and(prosecdef and provolatile='s' and proconfig @> array['search_path=""'])
 from pg_proc where oid in ('private.conversion_cierres_coordinacion(uuid,date,date,integer)'::regprocedure,
 'crm.conversion_cierres_coordinacion_fn(uuid,date,date,date,integer)'::regprocedure)),'search_path y definer');
select pg_temp.exigir(not exists(select 1 from unnest(array['anon','authenticated','service_role','public']) r
 where has_function_privilege(r,'private.conversion_cierres_coordinacion(uuid,date,date,integer)','execute')),'núcleo privado');
select pg_temp.exigir(not exists(select 1 from unnest(array['anon','service_role','public']) r
 where has_function_privilege(r,'crm.conversion_cierres_coordinacion_fn(uuid,date,date,date,integer)','execute')),'ACL puerta');

create temporary table esperado as select count(*)::integer total, sum(aporte_numerador) aporte
from private.conversion_episodios('2026-10-01 05:00Z','2026-11-01 05:00Z','2026-10-01',true,null,1)
where analista_id=pg_temp.uid(4) and tipo in ('cierre','operacion') and not anulado;
select pg_temp.exigir((select total from esperado) = (
 select cierres_formulario+cierres_landing+cierres_base_cargada+cierres_referido+cierres_oficina+cierres_otros+upgrade+renovacion
 from private.conversion_divisor_empresa('2026-10-01','2026-10-31') where analista_id=pg_temp.uid(4)
),'paridad contra el agregado que alimenta la pantalla');
grant select on esperado to authenticated;
set local role authenticated;
select pg_temp.denegado(n) from generate_series(3,11) n;
select pg_temp.sesion(1);
do $$ declare a jsonb; b jsonb; filas jsonb; p jsonb; n integer; begin
 a:=crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),'2026-10-01');
 b:=crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),'2026-10-01',p_pagina=>1);
 filas:=(a->'filas')||(b->'filas');
 perform pg_temp.exigir((a->>'total')::integer=(select total from pg_temp.esperado),'paridad total canónico');
 perform pg_temp.exigir((select sum((f->>'aporte')::numeric) from jsonb_array_elements(filas) f)=(select aporte from pg_temp.esperado),'paridad aportes');
 perform pg_temp.exigir(jsonb_array_length(a->'filas')=20 and jsonb_array_length(b->'filas')=4,'paginación 20 + 4');
 perform pg_temp.exigir((select count(*)=3 from jsonb_array_elements(filas) f where f->>'registro'='manual' and (f->>'aporte')::numeric=1),'manual referido formulario y landing');
 perform pg_temp.exigir((select count(*)=1 from jsonb_array_elements(filas) f where f->>'origen'='referido' and (f->>'aporte')::numeric=0),'referido excede tope visible');
 perform pg_temp.exigir((select count(*)=2 from jsonb_array_elements(filas) f where f->>'registro'='cartera'),'deduplicación cartera');
 perform pg_temp.exigir(not exists(select 1 from jsonb_array_elements(filas) f where f->>'nombre' in ('CIERRE SINTETICO 8','CIERRE SINTETICO 9','CIERRE SINTETICO 10','CIERRE SINTETICO 26')),'excluye demo retirada fuera plazo y otro analista');
 perform pg_temp.exigir(not exists(select 1 from jsonb_array_elements(filas) f, jsonb_object_keys(f) k
   where k not in ('nombre','origen','fecha','registro','aporte')),'proyección mínima sin contactos ni identificadores');
 perform pg_temp.exigir((crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),'2026-10-01',p_pagina=>99)->>'pagina')::integer=1,'clamp');
 perform pg_temp.exigir((crm.conversion_cierres_coordinacion_fn(pg_temp.uid(99),'2026-10-01')->>'total')::integer=0,'vacío');
 perform pg_temp.exigir(crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),'2026-09-01')->>'disponible'='false','mes sellado');
 perform pg_temp.exigir(crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),p_desde=>'2026-09-01',p_hasta=>'2026-09-30')->>'disponible'='false','mes exacto por rango sellado');
 p:=crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),p_desde=>'2026-09-30',p_hasta=>'2026-10-01');
 perform pg_temp.exigir(p->>'disponible'='true' and (p->>'total')::integer=2,'rango vivo que toca sellado: referido y primera operación');
 perform pg_temp.exigir((select count(*)=1 from jsonb_array_elements(p->'filas') f where f->>'nombre'='CIERRE SINTETICO 1' and f->>'fecha'='2026-10-01' and (f->>'aporte')::numeric=1),'Lima y tope sobre mes completo antes del recorte');
 perform pg_temp.sesion(2);
 perform pg_temp.exigir(a=crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),'2026-10-01'),'gerencia misma respuesta');
 raise notice 'PASS: roles, bajas CRM/Portal, paridad, manuales, exclusiones, cartera, proyección mínima, paginación, vacío y sellados';
end $$;
do $$ declare consulta text; begin
 for consulta in select unnest(array[
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),''2099-01-01'')',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),''2026-10-02'')',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),''2026-10-01'',p_pagina=>-1)',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),''2026-10-01'',p_pagina=>50001)',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),''2026-10-01'',p_desde=>''2026-10-01'',p_hasta=>''2026-10-02'')',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),p_desde=>''2026-10-01'')',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),p_desde=>''2026-10-02'',p_hasta=>''2026-10-01'')',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),p_desde=>''2024-10-01'',p_hasta=>''2026-10-01'')',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),p_desde=>''2026-10-01'',p_hasta=>''2099-01-01'')',
  'select crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),''-infinity'')'
 ]) loop
   begin execute consulta; raise exception 'Aceptó entrada inválida: %',consulta;
   exception when invalid_parameter_value then null; end;
 end loop;
 raise notice 'PASS: diez entradas inválidas';
end $$;
set local role anon;
do $$ begin
 begin perform crm.conversion_cierres_coordinacion_fn(pg_temp.uid(4),'2026-10-01');
 raise exception 'Anon admitido'; exception when insufficient_privilege then null; end;
end $$;
rollback;
