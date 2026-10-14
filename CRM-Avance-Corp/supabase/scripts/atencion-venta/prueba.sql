-- Solo banco propio 55483 con esquema vacío. Fixtures sintéticos; triggers activos.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='90s';
do $$ begin
 if current_user<>'postgres' or exists(select 1 from public.perfiles) then raise exception 'Solo banco vacío propio'; end if;
end $$;
create function pg_temp.exigir(ok boolean,nombre text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',nombre; end if; raise notice 'PASS: %',nombre; end $$;
create function pg_temp.actor(id uuid) returns void language sql as $$
 select set_config('request.jwt.claim.sub',coalesce(id::text,''),true);
 select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true);
$$;
create temporary table caso as select
 md5('AV GERENCIA')::uuid g,md5('AV ADMIN PORTAL')::uuid admin,md5('AV OPERACIONES')::uuid op,
 md5('AV FIORELLA')::uuid a,md5('AV JORGE')::uuid b,md5('AV CLIENTE')::uuid cli,
 md5('AV PERSONA')::uuid persona,md5('AV 001595')::uuid venta;
grant select on caso to authenticated;
do $$ declare r record; begin
 for r in select * from (values
   ('AV GERENCIA','admin'),('AV ADMIN PORTAL','admin'),('AV OPERACIONES','operaciones'),
   ('AV FIORELLA','analista'),('AV JORGE','analista'),('AV CLIENTE','cliente')) x(nombre,rol) loop
   insert into auth.users(id,email) values(md5(r.nombre)::uuid,md5(r.nombre)||'@example.test');
   insert into public.perfiles(id,nombre_completo,correo,rol,activo,debe_cambiar_password,titular_distinto,titular_distinto_usd)
   values(md5(r.nombre)::uuid,r.nombre,md5(r.nombre)||'@example.test',r.rol,true,false,false,false);
 end loop;
end $$;
insert into crm.equipo(perfil_id,rol_crm,activo) select g,'gerencia',true from caso;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) select b,'supervisor',g,true from caso;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) select a,'vendedor',b,true from caso;
update public.perfiles set asesor_perfil_id=(select a from caso) where id=(select cli from caso);
insert into crm.inversionistas(id,perfil_id,responsable_relacion_id,creado_por) select persona,cli,a,g from caso;
insert into crm.inversionista_responsables(inversionista_id,responsable_id,motivo,por) select persona,a,'Fixture sintético',g from caso;
insert into crm.multiempresa_flags(nombre,activo) values('resolver_en_puertas',true);
insert into crm.productos_inversion(codigo,estado,es_legacy,permite_altas_legacy,archivado_en)
values('HISTORICO-SIN-CATALOGO','archivado',true,true,now());
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,tipo_interes,
 fecha_inicio,fecha_vencimiento,estado,categoria,creado_por,analista_cierre_id,es_demo)
select venta,'AV-001595',cli,150000,'PEN',15,'mensual','simple','2026-10-11','2027-10-11','activo','nuevo',b,a,false from caso;
-- Otras cuatro ventas de Fiorella: no deben moverse con la corrección de una.
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,tipo_interes,
 fecha_inicio,fecha_vencimiento,estado,categoria,creado_por,analista_cierre_id,es_demo)
select md5('AV-OTRA-'||n)::uuid,'AV-OTRA-'||n,cli,monto,moneda,15,'mensual','simple',fecha,fecha+365,'activo','nuevo',g,a,false
from caso cross join (values(1,9600,'PEN',date '2026-10-01'),(2,10000,'USD',date '2026-10-02'),
 (3,4690,'USD',date '2026-10-02'),(4,3000,'USD',date '2026-10-07')) x(n,monto,moneda,fecha);
insert into crm.tareas(id,perfil_id,vendedor_id,tipo,titulo,vence_en) select md5('AV TAREA')::uuid,cli,a,'llamada','Seguimiento sintético',now()+interval '1 day' from caso;
create temporary table capital_antes as select moneda,sum(monto) monto from private.facturacion_operaciones('2026-10-01','2026-11-01') group by moneda;
select pg_temp.actor(g) from caso;
create temporary table previo(d jsonb);grant all on previo to authenticated;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('atencion_persona',persona,b) from caso;
select crm.confirmar_cambio_responsabilidad_fn('atencion_persona',persona,b,'venta de Jorge',(select d->>'version' from previo)) from caso;
reset role;
select pg_temp.exigir((select responsable_relacion_id=b from crm.inversionistas i,caso where i.id=persona)
 and (select asesor_perfil_id=b from public.perfiles p,caso where p.id=cli),'Atención alinea persona y portal');
select pg_temp.exigir((select analista_cierre_id=a and creado_por=b and capital=150000 from public.contratos c,caso where c.id=venta),'Atención conserva dueño, creador y capital aunque el motivo diga venta de Jorge');
select pg_temp.exigir((select vendedor_id=b from crm.tareas t,caso where t.id=md5('AV TAREA')::uuid),'La tarea pendiente sigue al nuevo responsable');
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('venta',venta,b) from caso;
select crm.confirmar_cambio_responsabilidad_fn('venta',venta,b,'Corrección comercial',(select d->>'version' from previo)) from caso;
reset role;
select pg_temp.exigir((select analista_cierre_id=b and creado_por=b and capital=150000 from public.contratos c,caso where c.id=venta),'Corrección cambia solo vendedor; preserva capital y registrador');
select pg_temp.exigir((select count(*)=1 from crm.reasignaciones_analista),'Una sola fila de historial');
select pg_temp.exigir((select sum(capital)=9600 and sum(operaciones)=1 from crm.facturacion_diaria_fn('2026-10-01'),caso where analista_id=a and moneda='PEN')
 and (select sum(capital)=17690 and sum(operaciones)=3 from crm.facturacion_diaria_fn('2026-10-01'),caso where analista_id=a and moneda='USD'),
 'Facturación de Fiorella conserva las otras cuatro ventas: PEN 9600 y USD 17690');
select pg_temp.exigir(not exists((select moneda,sum(monto) from private.facturacion_operaciones('2026-10-01','2026-11-01') group by moneda)
 except select * from capital_antes),'Capital global por moneda idéntico tras corregir 150k');

set local role authenticated;
do $$ begin
 begin
 perform crm.confirmar_cambio_responsabilidad_fn('venta',(select venta from caso),(select b from caso),'Reintento',(select d->>'version' from previo));
 raise exception 'Aceptó versión consumida';
 exception when sqlstate 'PT409' then null; end;
end $$;
reset role;
select pg_temp.exigir((select count(*)=1 from crm.reasignaciones_analista),'Reintento rechazado sin duplicar historial');
select pg_temp.actor(admin) from caso;
set local role authenticated;
do $$ begin
 begin
 update public.perfiles set asesor_perfil_id=(select a from caso) where id=(select cli from caso);
 raise exception 'Aceptó UPDATE directo';
 exception when insufficient_privilege then null; end;
end $$;
delete from previo;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('atencion_cliente',cli,a) from caso;
select crm.confirmar_cambio_responsabilidad_fn('atencion_cliente',cli,a,'Cambio por administrador portal',(select d->>'version' from previo)) from caso;
reset role;
select pg_temp.exigir((select asesor_perfil_id=a from public.perfiles p,caso where p.id=cli)
 and (select responsable_relacion_id=a from crm.inversionistas i,caso where i.id=persona),'Admin portal sin CRM puede cambiar atención completa por núcleo');
-- La Gerencia con asiento de analista tampoco sufre una congelación silenciosa
-- de asesor_id legado. Un GUC falsificado nunca abre un UPDATE autenticado.
savepoint legado;
select pg_temp.actor(null);
update public.perfiles set rol='analista' where id=(select g from caso);
insert into public.asesores(id,nombre_completo,whatsapp) values(md5('AV LEGADO')::uuid,'AV LEGADO','999999999');
update public.perfiles set asesor_id=md5('AV LEGADO')::uuid where id=(select cli from caso);
select pg_temp.actor(g) from caso;
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('atencion_cliente',cli,b) from caso;
select crm.confirmar_cambio_responsabilidad_fn('atencion_cliente',cli,b,'Conciliar asesor antiguo',(select d->>'version' from previo))->>'ok' from caso;
reset role;
select pg_temp.exigir((select asesor_perfil_id=b and asesor_id is null from public.perfiles p,caso where p.id=cli),
 'Gerencia con asiento analista alinea perfil y limpia asesor legado');
select pg_temp.actor(admin) from caso;
set local role authenticated;
select set_config('crm.atencion_autorizada',(select cli::text from caso),true);
do $$ begin
 begin update public.perfiles set asesor_id=md5('AV LEGADO')::uuid where id=(select cli from caso);
 raise exception 'Aceptó cambiar asesor legado por fuera';exception when insufficient_privilege then null;end;
 begin update public.perfiles set asesor_perfil_id=(select a from caso) where id=(select cli from caso);
 raise exception 'Aceptó GUC como autorización';exception when insufficient_privilege then null;end;
end $$;
reset role;
select pg_temp.exigir(true,'GUC falsificado y cambio directo de asesor legado bloqueados');
rollback to legado;
-- Perfil antiguo sin persona: acción explícita y motivo auditado sin inventar identidad.
savepoint sin_persona;
select pg_temp.actor(null);
insert into auth.users(id,email) values(md5('AV SIN PERSONA')::uuid,'sinpersona@example.test');
insert into public.perfiles(id,nombre_completo,correo,rol,activo,debe_cambiar_password,titular_distinto,titular_distinto_usd)
values(md5('AV SIN PERSONA')::uuid,'AV SIN PERSONA','sinpersona@example.test','cliente',true,false,false,false);
select pg_temp.actor(admin) from caso;
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('atencion_cliente',md5('AV SIN PERSONA')::uuid,b) from caso;
select crm.confirmar_cambio_responsabilidad_fn('atencion_cliente',md5('AV SIN PERSONA')::uuid,b,'Atender perfil antiguo',(select d->>'version' from previo))->>'ok' from caso;
reset role;
select pg_temp.exigir((select asesor_perfil_id=b from public.perfiles p,caso where p.id=md5('AV SIN PERSONA')::uuid)
 and not exists(select 1 from crm.inversionistas where perfil_id=md5('AV SIN PERSONA')::uuid)
 and exists(select 1 from crm.actividades_cliente,caso where cliente_id=md5('AV SIN PERSONA')::uuid
   and creado_por=admin and detalle='Motivo del cambio de atención: Atender perfil antiguo'),
 'Perfil sin persona cambia atención con motivo y autor, sin crear identidad');
rollback to sin_persona;
select pg_temp.actor(op) from caso;
set local role authenticated;
do $$ begin
 begin
 perform crm.previsualizar_cambio_responsabilidad_fn('atencion_cliente',(select cli from caso),(select b from caso));
 raise exception 'Aceptó Operaciones para atención';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.exigir(not has_function_privilege('authenticated','private.ejecutar_cambio_responsabilidad(text,uuid,uuid,text,text,boolean)','execute')
 and not has_function_privilege('anon','crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid)','execute'),'Núcleo y puerta anónima cerrados');
-- Versión obsoleta, vendedor sin permiso, sin sesión y membresía revocada.
select pg_temp.actor(a) from caso;
set local role authenticated;
do $$ begin
 begin perform crm.previsualizar_cambio_responsabilidad_fn('venta',(select venta from caso),(select a from caso));
 raise exception 'Aceptó vendedor'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.actor(null);
set local role authenticated;
do $$ begin
 begin perform crm.previsualizar_cambio_responsabilidad_fn('venta',(select venta from caso),(select a from caso));
 raise exception 'Aceptó sin sesión'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.actor(g) from caso;
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('venta',venta,a) from caso;
reset role;
update public.contratos set capital=160000 where id=(select venta from caso);
set local role authenticated;
do $$ begin
 begin perform crm.confirmar_cambio_responsabilidad_fn('venta',(select venta from caso),(select a from caso),'Cambio con importe antiguo',(select d->>'version' from previo));
 raise exception 'Aceptó capital obsoleto'; exception when sqlstate 'PT409' then null; end;
end $$;
reset role;
select pg_temp.exigir((select count(*)=1 from crm.reasignaciones_analista),'Importe obsoleto no crea historial ni altera vendedor');
-- Puerta legado: misma forma de resultado y misma historia, núcleo único.
set local role authenticated;
select pg_temp.exigir(public.reasignar_analista_contrato((select venta from caso),(select a from caso),'Corrección mediante adaptador')->>'ok'='true','Adaptador público compatible');
reset role;
-- Falla de postcondición simulada por un trigger del ensayo: historial y UPDATE se revierten juntos.
create function pg_temp.desviar_venta() returns trigger language plpgsql as $$ begin new.analista_cierre_id:=old.analista_cierre_id;return new;end $$;
create trigger zzzz_ensayo_desviar before update of analista_cierre_id on public.contratos for each row execute function pg_temp.desviar_venta();
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('venta',venta,b) from caso;
do $$ begin
 begin perform crm.confirmar_cambio_responsabilidad_fn('venta',(select venta from caso),(select b from caso),'Debe revertir todo',(select d->>'version' from previo));
 raise exception 'No comprobó resultado'; exception when sqlstate 'P0409' then null;end;
end $$;
reset role;
drop trigger zzzz_ensayo_desviar on public.contratos;
select pg_temp.exigir((select count(*)=2 from crm.reasignaciones_analista)
 and (select analista_cierre_id=a from public.contratos c,caso where c.id=venta),'Postcondición fallida revierte vendedor e historial');
-- Inconsistencia legado: el tramo ya apunta al destino pero el perfil no.
update public.perfiles set asesor_perfil_id=(select b from caso) where id=(select cli from caso);
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('atencion_persona',persona,a) from caso;
select crm.confirmar_cambio_responsabilidad_fn('atencion_persona',persona,a,'Conciliar ficha desalineada',(select d->>'version' from previo))->>'ok' from caso;
reset role;
select pg_temp.exigir((select asesor_perfil_id=a from public.perfiles p,caso where p.id=cli),'Mismo tramo concilia el perfil; no devuelve sin_cambios incompleto');
-- Gerencia mantiene la excepción de cartera operativa, sin congelación silenciosa.
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('atencion_persona',persona,g) from caso;
select crm.confirmar_cambio_responsabilidad_fn('atencion_persona',persona,g,'Gerencia asume relación',(select d->>'version' from previo))->>'ok' from caso;
reset role;
select pg_temp.exigir((select responsable_relacion_id=g from crm.inversionistas i,caso where i.id=persona)
 and (select asesor_perfil_id=a from public.perfiles p,caso where p.id=cli),'Gerencia recibe relación y conserva asesor operativo explícitamente');
savepoint cadena;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,tipo_interes,
 fecha_inicio,fecha_vencimiento,estado,categoria,creado_por,analista_cierre_id,es_demo)
select md5(n)::uuid,n,cli,20000,'USD',15,'mensual','simple','2026-10-12','2027-10-12','activo',cat,g,analista,false
from caso cross join lateral (values('AV-UP','upgrade',a),('AV-REN','renovacion',b)) x(n,cat,analista);
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select cli,a,'upgrade',md5('AV-UP')::uuid,'2026-10-12','2026-10-01','USD',true,'flujo_cartera',g from caso;
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,contrato_origen_id,capital_renovado,capital_adicional,
 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select cli,b,'renovacion',md5('AV-REN')::uuid,md5('AV-UP')::uuid,19000,1000,'2026-10-12','2026-10-01','USD',true,'flujo_cartera',g from caso;
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('venta',md5('AV-UP')::uuid,b) from caso;
select pg_temp.exigir((select count(*)=2 from previo,jsonb_array_elements(d->'efectos') e where e->>'anterior' is distinct from e->>'previsto'),
 'Vista previa incluye upgrade y descendiente sin mezclar moneda');
do $$ begin
 begin perform public.reasignar_analista_contrato(md5('AV-UP')::uuid,(select b from caso),'Cadena requiere vista previa');
 raise exception 'Legado aceptó alcance ampliado';exception when sqlstate 'P0409' then null;end;
end $$;
select crm.confirmar_cambio_responsabilidad_fn('venta',md5('AV-UP')::uuid,b,'Corrección de upgrade y cadena',(select d->>'version' from previo))->>'ok' from caso;
reset role;
select pg_temp.exigir((select private.analista_efectivo_contrato(md5('AV-REN')::uuid,a)=b from caso)
 and (select vendedor_id=a from crm.operaciones_cartera o,caso where contrato_nuevo_id=md5('AV-UP')::uuid),'Cadena corregida sin reescribir autoría de operaciones_cartera');
select pg_temp.exigir(not exists(select 1 from private.capital_episodios('2026-10-01','2026-11-01',true,'{}') e,caso
 where contrato_id in (md5('AV-UP')::uuid,md5('AV-REN')::uuid) and analista_id is distinct from b),'Stock y desglose coinciden en el núcleo financiero');
rollback to cadena;
-- Renovación sin upgrade: se niega éxito engañoso si el desglose conservaría otro dueño.
savepoint desglose;
insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,contrato_origen_id,capital_renovado,capital_adicional,
 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
select cli,a,'renovacion',venta,venta,150000,0,'2026-10-11','2026-10-01','PEN',true,'flujo_cartera',g from caso;
set local role authenticated;
do $$ begin
 begin perform crm.previsualizar_cambio_responsabilidad_fn('venta',(select venta from caso),(select b from caso));
 raise exception 'Aceptó desglose contradictorio';exception when sqlstate 'P0409' then null;end;
end $$;
reset role;
select pg_temp.exigir(true,'Rechaza divergencia de desglose y resuelve ciclo sin colgarse');
rollback to desglose;

savepoint sellado;
insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
values('2026-10-01',0.5,1,'{}');
insert into crm.cierre_mes_vendedor(periodo,vendedor_id,nombre_completo,supervisor_id,supervisor_nombre,
 divisor,cierres_no_referidos,cierres_referidos,cierres_de_arrastre,numerador,estado,
 referidos_recibidos,referidos_dados_de_alta,conversion_objetivo,detalles)
select '2026-10-01',a,'FIORELLA SELLADA',b,'JORGE SELLADO',1,1,0,0,1,'cumplido',0,0,50,'[{"capital_pen":150000}]' from caso;
create temporary table foto_antes as select to_jsonb(c) foto from crm.cierre_mes_vendedor c;
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('venta',venta,b) from caso;
select crm.confirmar_cambio_responsabilidad_fn('venta',venta,b,'Corrección con foto sellada',(select d->>'version' from previo))->>'ok' from caso;
reset role;
select pg_temp.exigir((select to_jsonb(c)=f.foto from crm.cierre_mes_vendedor c cross join foto_antes f),
 'Corrección viva conserva íntegra la foto sellada del mismo mes');
rollback to sellado;

-- Cooperativas conservan el vendedor escrito; al darlo de baja, heredan del
-- responsable canónico y no de un campo del perfil elegido por la pantalla.
-- Solo montaje de un cierre histórico: no se ejecuta el alta comercial actual.
set local session_replication_role=replica;
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,vendedor_id,convertido_en,inversionista_id,creado_por,monto_estimado)
select md5('AV COOP LEAD')::uuid,'AV COOP','+51999817031','oficina','convertido',a,now(),persona,g,22000 from caso;
insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,
 numero_transaccion,vendedor_id,creado_por,inversionista_id,creado_en,fecha_comercial,fecha_imputacion,es_cierre_inicial,vence_en)
select md5('AV COOP')::uuid,md5('AV COOP LEAD')::uuid,'qorilazo',22000,'PEN','DNI','99817031','AV COOP',
 'AV-COOP',a,g,persona,now(),null,null,true,'2027-10-11' from caso;
set local session_replication_role=origin;
-- Herencia: fixture de baja histórica SOLO como mantenimiento del banco.
-- Los endpoints siguen ejecutándose con origin y RLS.
set local session_replication_role=replica;
update crm.equipo set activo=false where perfil_id=(select a from caso);
set local session_replication_role=origin;
delete from previo;
set local role authenticated;
insert into previo select crm.previsualizar_cambio_responsabilidad_fn('atencion_cliente',cli,b) from caso;
select pg_temp.exigir((select e->>'previsto'=(select b::text from caso) from previo,jsonb_array_elements(d->'efectos') e where e->>'id'=(select venta::text from caso)),'Vista previa muestra heredero de analista de baja');
select pg_temp.exigir((select e->>'tipo'='cooperativa' and e->>'previsto'=(select b::text from caso)
 from previo,jsonb_array_elements(d->'efectos') e where e->>'id'=md5('AV COOP')::uuid::text),
 'Vista previa incluye herencia de cooperativa');
select crm.confirmar_cambio_responsabilidad_fn('atencion_cliente',cli,b,'Traslado con herencia',(select d->>'version' from previo))->>'ok' from caso;
reset role;
select pg_temp.exigir((select private.analista_efectivo_contrato(venta,a)=b from caso),'Herencia efectiva coincide con vista previa');
select pg_temp.exigir((select private.analista_efectivo_cierre(md5('AV COOP')::uuid)=b from caso)
 and (select vendedor_id=a from crm.cierres_externos c,caso where c.id=md5('AV COOP')::uuid),
 'Cooperativa hereda del nuevo responsable sin cambiar vendedor registrado');
-- El rol service_role tampoco es un atajo para cambiar directamente el asesor.
set local role service_role;
do $$ begin
 begin update public.perfiles set asesor_perfil_id=md5('AV GERENCIA')::uuid where id=md5('AV CLIENTE')::uuid;
 raise exception 'Aceptó service_role directo'; exception when insufficient_privilege then null;end;
end $$;
reset role;
select pg_temp.exigir(true,'service_role directo bloqueado; las altas INSERT conservan su camino');

-- Revocación CRM manda incluso sobre admin del portal.
set local session_replication_role=replica;
update crm.equipo set activo=false where perfil_id=(select g from caso);
set local session_replication_role=origin;
select pg_temp.actor(g) from caso;
set local role authenticated;
do $$ begin
 begin perform crm.previsualizar_cambio_responsabilidad_fn('atencion_cliente',(select cli from caso),(select b from caso));
 raise exception 'Aceptó admin revocado'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.exigir(true,'Vendedor, sin sesión, Operaciones y admin revocado rechazados');

rollback;
