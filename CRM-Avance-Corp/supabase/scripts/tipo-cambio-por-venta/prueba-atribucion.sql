begin;
set local statement_timeout='90s';
do $$ begin if current_database()<>'tc_venta' then raise exception 'Solo banco tc_venta'; end if; end $$;
create function pg_temp.comprobar(p_ok boolean,p_mensaje text) returns void language plpgsql as $$ begin
  if p_ok is distinct from true then raise exception 'FAIL: %',p_mensaje; end if;
  raise notice 'PASS: %',p_mensaje;
end $$;
create function pg_temp.persona(n integer) returns uuid language sql immutable as $$
  select ('f1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.contrato(n integer) returns uuid language sql immutable as $$
  select ('f2000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
set local session_replication_role=replica;
insert into public.perfiles(id,nombre_completo,rol)
select pg_temp.persona(i),'Persona sintética '||i,'analista' from generate_series(1,5) i;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id)
values(pg_temp.persona(1),'supervisor',null),(pg_temp.persona(2),'vendedor',pg_temp.persona(1)),
  (pg_temp.persona(3),'vendedor',pg_temp.persona(1)),(pg_temp.persona(4),'coordinador',null);
insert into crm.meta_periodos(id,periodo,revision,publicada_por)
values(pg_temp.persona(10),'2026-10-01',1,pg_temp.persona(4));
insert into crm.metas_vendedor(meta_periodo_id,vendedor_id,supervisor_id,conversion_objetivo)
values(pg_temp.persona(10),pg_temp.persona(2),pg_temp.persona(1),10);
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por)
select pg_temp.contrato(n),'ATR-TC-'||n,pg_temp.persona(5),n*1000,moneda,'mensual',
  date '2026-09-02',date '2027-10-02',categoria,pg_temp.persona(99),fecha,
  case when analista is not null then pg_temp.persona(analista) end,pg_temp.persona(autor)
from (values(1,'PEN','nuevo',date '2026-10-02',2,4),
  (2,'USD','renovacion',date '2026-10-02',3,2),
  (3,'PEN','nuevo',date '2026-10-02',null::int,4),
  (4,'PEN','upgrade',date '2026-10-02',null,2),
  (5,'PEN','nuevo',date '2026-10-02',null,2),
  (6,'PEN','nuevo',date '2026-10-02',null,2),
  (7,'USD','nuevo',date '2026-09-02',2,2),
  (8,'PEN','nuevo',date '2026-10-02',2,2)) f(n,moneda,categoria,fecha,analista,autor);
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,vendedor_id,perfil_id,contrato_id,convertido_en)
select pg_temp.persona(20+n),'Lead sintético '||n,'+51900000'||lpad(n::text,3,'0'),
  'landing','convertido',1000,pg_temp.persona(vendedor),pg_temp.persona(5),pg_temp.contrato(contrato),
  '2026-10-03 10:00 America/Lima'::timestamptz
from(values(1,1,3),(2,5,2),(3,5,3),(4,6,3)) f(n,contrato,vendedor);
insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,
  numero_transaccion,vendedor_id,creado_por,creado_en,fecha_comercial,fecha_imputacion,anulado_en,anulado_por,motivo_anulacion)
values(pg_temp.persona(31),pg_temp.persona(41),'prodelco',9000,'USD','DNI','00000000','Cooperativa sintética',
  'ATR-TC-COOP-1',pg_temp.persona(3),pg_temp.persona(4),'2026-10-04 10:00 America/Lima','2026-10-02','2026-10-03',null,null,null),
 (pg_temp.persona(32),pg_temp.persona(42),'prodelco',10000,'USD','DNI','00000000','Cooperativa anulada sintética',
  'ATR-TC-COOP-2',pg_temp.persona(3),pg_temp.persona(4),'2026-10-04 10:00 America/Lima','2026-09-30','2026-10-02',
  '2026-10-05 10:00 America/Lima',pg_temp.persona(4),'Anulación sintética de conversión');
set local session_replication_role=origin;

create temp table atribucion_antes as select * from private.produccion_mes_por_vendedor(
  '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima',pg_temp.persona(10));
select pg_temp.comprobar((select count(*)>=3 from atribucion_antes),'el agregado de comparación no está vacío');

-- @MIGRACION_OPERACIONES@

select pg_temp.comprobar(not exists(
  (select * from atribucion_antes except all select * from private.produccion_mes_por_vendedor(
    '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima',pg_temp.persona(10)))
  union all
  (select * from private.produccion_mes_por_vendedor(
    '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima',pg_temp.persona(10)) except all select * from atribucion_antes)),
  'agregado completo idéntico antes/después con atribuciones explícitas, legado y cooperativas');
create temp table operaciones as select * from private.produccion_operaciones(
  '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima',pg_temp.persona(10));
select pg_temp.comprobar((select vendedor_id=pg_temp.persona(2) from operaciones where fuente_id=pg_temp.contrato(1)),
  'el analista explícito prevalece sobre un lead y autor diferentes');
select pg_temp.comprobar((select vendedor_id=pg_temp.persona(3) from operaciones where fuente_id=pg_temp.contrato(2)),
  'el dueño explícito fuera de metas conserva su producción, sin caer al autor');
select pg_temp.comprobar(not exists(select 1 from operaciones where fuente_id=pg_temp.contrato(3)),
  'el autor que no es vendedor no recibe capital por fallback');
select pg_temp.comprobar((select vendedor_id=pg_temp.persona(2) from operaciones where fuente_id=pg_temp.contrato(4)),
  'el autor vendedor conserva el fallback cuando no hay atribución explícita');
select pg_temp.comprobar(not exists(select 1 from operaciones where fuente_id=pg_temp.contrato(5)),
  'dos leads con vendedores distintos no producen atribución inventada');
select pg_temp.comprobar((select vendedor_id=pg_temp.persona(3) from operaciones where fuente_id=pg_temp.contrato(6)),
  'un lead con dueño explícito fuera de metas no cae al autor');
select pg_temp.comprobar((select fecha_comercial='2026-10-02' and fecha_imputacion='2026-10-03'
  from operaciones where fuente_id=pg_temp.persona(31)),
  'cooperativa expone fecha de venta y fecha de imputación separadas');
select pg_temp.comprobar((select fecha_comercial='2026-09-30' and fecha_imputacion='2026-10-02' and capital=10000
  from operaciones where fuente_id=pg_temp.persona(32)),
  'una cooperativa de septiembre imputada en octubre conserva su capital aun anulada');
select pg_temp.comprobar(not exists(select 1 from operaciones where fuente_id=pg_temp.contrato(7)),
  'el contrato de septiembre queda fuera de octubre');
select pg_temp.comprobar((select count(*)=count(distinct(fuente,fuente_id)) from private.capital_fuentes_tc()),
  'identidad stock única para valoración y proyección de capital');
select pg_temp.comprobar((select count(*)=1 from operaciones where fuente_id=pg_temp.contrato(8)),
  'fecha legal de inicio distinta no cambia la fecha comercial de producción');
select pg_temp.comprobar(not has_function_privilege('authenticated','private.produccion_operaciones(timestamptz,timestamptz,uuid)','EXECUTE'),
  'la proyección global de operaciones no se expone a usuarios');
select pg_temp.comprobar(not exists(
  select 1 from private.capital_fuentes_tc() s
  left join public.contratos c on s.fuente='contrato' and c.id=s.fuente_id
  left join crm.cierres_externos ce on s.fuente='cierre_externo' and ce.id=s.fuente_id
  where (s.moneda,s.monto,s.fecha_comercial,s.fecha_imputacion) is distinct from
    (case when s.fuente='contrato' then c.moneda else ce.moneda end,
     case when s.fuente='contrato' then c.capital else ce.monto end,
     case when s.fuente='contrato' then c.fecha_cierre_comercial else ce.fecha_comercial end,
     case when s.fuente='contrato' then c.fecha_cierre_comercial
       else coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date) end)),
  'stock canónico coincide con la relectura bloqueada incluso en renovación, upgrade y cooperativa septiembre imputada en octubre');
select pg_temp.comprobar((select count(*)=2 and bool_and(pg_catalog.format_type(atttypid,atttypmod)~'^numeric\([0-9]+,2\)$')
  from pg_attribute where (attrelid='public.contratos'::regclass and attname='capital')
    or (attrelid='crm.cierres_externos'::regclass and attname='monto')),
  'las dos fuentes monetarias ya almacenan dos decimales: la valoración no recibe una escala mayor');
rollback;
