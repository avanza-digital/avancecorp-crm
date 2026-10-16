create function pg_temp.leer(p_actor text,p_mes date) returns jsonb language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  return crm.cumplimiento_metas_fn(p_mes);
exception when insufficient_privilege then return '{"denegado":true}'::jsonb;
end $f$;
create temporary table lecturas(actor text,mes date,fase text,valor jsonb);
grant all on lecturas to authenticated;
create function pg_temp.fotografiar(p_fase text) returns void language plpgsql as $f$
declare a record; m date; begin
  for a in select clase from actores where clase<>'cliente' loop
    foreach m in array array[date '2026-09-01',date '2026-10-01',date '2026-11-01'] loop
      insert into lecturas values(a.clase,m,p_fase,pg_temp.leer(a.clase,m));
    end loop;
  end loop;
end $f$;

-- La foto sintética conserva la producción de octubre bajo noviembre.
-- Noviembre no tiene operaciones vivas: recalcularlo perdería estas ventas.
set local role authenticated;
select pg_temp.sesion('gerencia');
create temporary table foto_cerrada as select crm.cumplimiento_metas_fn('2026-10-01')->'fuera_ranking' as filas;
reset role;
select set_config('crm.op_privilegiada','on',true);
insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
select '2026-11-01',0.15,1,jsonb_build_object('fuera_ranking',filas) from foto_cerrada;
select set_config('crm.op_privilegiada','',true);
create temporary table contratos_antes as select id,analista_cierre_id,capital,moneda from public.contratos;
create temporary table cooperativas_antes as select * from crm.cierres_externos;
create temporary table acl_antes as select proacl,prosecdef,provolatile,proconfig
  from pg_proc where oid='crm.cumplimiento_metas_fn(date)'::regprocedure;
create temporary table sello_antes as select * from crm.periodos_cerrados;
set local role authenticated;
select pg_temp.fotografiar('antes');
reset role;

-- MIGRACION

set local role authenticated;
select pg_temp.fotografiar('despues');
do $prueba$ declare r record; esperado jsonb; id_propio text; begin
  perform pg_temp.exigir((select count(*) from lecturas)=54,'matriz completa: nueve actores, tres meses, antes y después');
  for r in select a.actor,a.mes,a.valor as antes,d.valor as despues
    from lecturas a join lecturas d using(actor,mes)
    where a.fase='antes' and d.fase='despues' loop
    if r.actor in ('gerencia','directorio','coordinador','vend1','vend2') or r.mes=date '2026-09-01' then
      perform pg_temp.exigir(r.antes=r.despues,'paridad JSON exacta: '||r.actor||' / '||r.mes);
    else
      select id::text into id_propio from actores where clase=r.actor;
      select coalesce(jsonb_agg(e.value order by e.ord),'[]'::jsonb) into esperado
      from lecturas l cross join lateral jsonb_array_elements(l.valor->'fuera_ranking')
        with ordinality e(value,ord)
      where l.actor='gerencia' and l.mes=r.mes and l.fase='antes'
        and e.value->>'persona_id'=id_propio and e.value->>'rol_crm'='supervisor';
      perform pg_temp.exigir(r.despues->'fuera_ranking'=esperado,'solo producción propia, sin equipo ajeno: '||r.actor||' / '||r.mes);
      perform pg_temp.exigir(r.antes-'fuera_ranking'=r.despues-'fuera_ranking','resto del contrato intacto: '||r.actor||' / '||r.mes);
      perform pg_temp.exigir(jsonb_array_length(r.despues->'fuera_ranking')=case when r.actor='sin_ventas' then 0 else 1 end,
        'atribución única o vacío sin ventas: '||r.actor||' / '||r.mes);
    end if;
  end loop;
  perform pg_temp.sesion('sup1');
  perform pg_temp.exigir((select sum((d->>'capital_real')::numeric)
    from jsonb_array_elements(crm.cumplimiento_metas_fn('2026-10-01')->'fuera_ranking') f
    cross join lateral jsonb_array_elements(f->'detalles') d where d->>'moneda'='PEN')=30000,
    'capital propio PEN conserva al autor comercial');
  perform pg_temp.exigir((select sum((d->>'capital_real')::numeric)
    from jsonb_array_elements(crm.cumplimiento_metas_fn('2026-11-01')->'fuera_ranking') f
    cross join lateral jsonb_array_elements(f->'detalles') d where d->>'moneda'='USD')=4000,
    'mes sellado conserva USD de la foto sin recalcular noviembre');
  perform pg_temp.exigir(pg_temp.leer('cliente','2026-10-01')='{"denegado":true}'::jsonb,'cliente sin rol CRM rechazado');
  perform pg_temp.exigir(pg_temp.leer('desconocido','2026-10-01')='{"denegado":true}'::jsonb,'sesión sin identidad rechazada');
  perform pg_temp.sesion('sup2');
  perform pg_temp.exigir((select sum((d->>'capital_real')::numeric)
    from jsonb_array_elements(crm.cumplimiento_metas_fn('2026-10-01')->'fuera_ranking') f
    cross join lateral jsonb_array_elements(f->'detalles') d where d->>'moneda'='PEN')=62000,
    'contrato y cooperativa propios suman una vez cada uno');
end $prueba$;
reset role;
savepoint perfil_activo;
select set_config('crm.op_privilegiada','on',true);
update public.perfiles set activo=false where id=(select id from actores where clase='sin_equipo');
set local role authenticated;
select pg_temp.exigir(pg_temp.leer('sin_equipo','2026-10-01')='{"denegado":true}'::jsonb,'perfil inactivo revoca la lectura propia');
rollback to savepoint perfil_activo;
savepoint cambio_rol;
-- Transición sintética como consola, con el par Portal/CRM coherente al final.
select pg_temp.sesion('desconocido');
select set_config('crm.op_privilegiada','on',true);
update public.perfiles set rol='analista' where id=(select id from actores where clase='sin_equipo');
update crm.equipo set rol_crm='vendedor',supervisor_id=(select id from actores where clase='sup1')
  where perfil_id=(select id from actores where clase='sin_equipo');
set local role authenticated;
select pg_temp.exigir(pg_temp.leer('sin_equipo','2026-10-01')->'fuera_ranking'='[]'::jsonb,
  'cambio a analista retira la capacidad de supervisión');
select pg_temp.exigir(pg_temp.leer('sin_equipo','2026-11-01')->'fuera_ranking'='[]'::jsonb,
  'cambio de rol tampoco hereda acceso a fotos de supervisión');
rollback to savepoint cambio_rol;
select set_config('crm.op_privilegiada','on',true);
update crm.equipo set activo=false where perfil_id=(select id from actores where clase='sin_ventas');
select set_config('crm.op_privilegiada','',true);
set local role authenticated;
select pg_temp.exigir(pg_temp.leer('sin_ventas','2026-10-01')='{"denegado":true}'::jsonb,'baja CRM revoca las ventas propias con el mismo actor');
reset role;
select pg_temp.exigir((select row(proacl,prosecdef,provolatile,proconfig) from acl_antes)=
  (select row(proacl,prosecdef,provolatile,proconfig) from pg_proc where oid='crm.cumplimiento_metas_fn(date)'::regprocedure),
  'ACL, security definer, estabilidad y search_path intactos');
select pg_temp.exigir(not exists((select * from sello_antes except select * from crm.periodos_cerrados)
  union all (select * from crm.periodos_cerrados except select * from sello_antes)),'ningún sello modificado');
select pg_temp.exigir(not exists((select * from contratos_antes except select id,analista_cierre_id,capital,moneda from public.contratos)
  union all (select id,analista_cierre_id,capital,moneda from public.contratos except select * from contratos_antes)),
  'ninguna venta duplicada, reasignada ni modificada');
select pg_temp.exigir(not exists((select * from cooperativas_antes except select * from crm.cierres_externos)
  union all (select * from crm.cierres_externos except select * from cooperativas_antes)),
  'cooperativas conservan atribución, monto e identidad');

-- REVERSA

set local role authenticated;
select pg_temp.exigir(pg_temp.leer('sup1','2026-10-01')=
  (select valor from lecturas where actor='sup1' and mes='2026-10-01' and fase='antes'),
  'reversa recupera exactamente el comportamiento anterior');
reset role;

-- REAPLICACION

set local role authenticated;
select pg_temp.exigir(pg_temp.leer('sup1','2026-10-01')=
  (select valor from lecturas where actor='sup1' and mes='2026-10-01' and fase='despues'),
  'reaplicación recupera exactamente las ventas propias');
reset role;
