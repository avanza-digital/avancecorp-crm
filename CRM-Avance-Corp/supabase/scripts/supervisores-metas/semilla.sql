-- Solo banco local exclusivo y vacío. Datos ficticios; triggers y RLS encendidos.
do $guardia$ begin
  if current_database() <> 'supervisores_metas_20261016'
     or current_user <> 'postgres'
     or current_setting('session_replication_role') <> 'origin'
     or exists (select 1 from crm.equipo)
     or exists (select 1 from public.contratos) then
    raise exception 'La prueba requiere su banco sintético exclusivo y vacío';
  end if;
end $guardia$;

insert into crm.productos_inversion(codigo,es_legacy,permite_altas_legacy,estado,archivado_en)
values('HISTORICO-SIN-CATALOGO',true,true,'archivado',now());
insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
values(1,'2000-01-01','America/Lima','corrido',60,120);
insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
select id,'nuevo',120 from crm.sla_politicas;
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota)
values('2000-01-01',0.15,0.15,'Prueba sintética de supervisores');

create temporary table actores(clase text primary key, id uuid not null default gen_random_uuid());
insert into actores(clase) values
  ('gerencia'),('directorio'),('coordinador'),('sup1'),('sup2'),('sin_equipo'),('sin_ventas'),('vend1'),('vend2'),('cliente');
grant select on actores to authenticated;

select set_config('crm.op_privilegiada','on',true);
insert into auth.users(id,email) select id,id::text||'@supervisores.test' from actores;
insert into public.perfiles(id,nombre_completo,correo,rol,activo,tipo_documento,
  debe_cambiar_password,titular_distinto,titular_distinto_usd)
select id,'PRUEBA '||clase,id::text||'@supervisores.test',
  case when clase='cliente' then 'cliente' when clase='directorio' then 'directorio'
    when clase in ('vend1','vend2') then 'analista' else 'comercial' end,
  true,'DNI',false,false,false from actores;
insert into crm.equipo(perfil_id,rol_crm,activo)
select id,case when clase in ('sup1','sup2','sin_equipo','sin_ventas') then 'supervisor' else clase end,true
from actores where clase in ('gerencia','directorio','coordinador','sup1','sup2','sin_equipo','sin_ventas');
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select a.id,'vendedor',s.id,true from actores a join actores s
  on s.clase=case a.clase when 'vend1' then 'sup1' when 'vend2' then 'sup2' end
where a.clase in ('vend1','vend2');

-- El autor de la carga es Gerencia; el dueño comercial de cada venta es distinto.
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,
  modalidad,tipo_interes,fecha_inicio,fecha_vencimiento,estado,categoria,creado_por,analista_cierre_id,es_demo)
select gen_random_uuid(),'SUP-TEST-'||gen_random_uuid(),c.id,v.monto,v.moneda,15,
  'mensual','simple',mes+4,(mes+4+interval '12 months')::date,'activo','nuevo',g.id,a.id,false
from (values ('vend1',10000::numeric,'PEN'),('vend2',20000,'PEN'),('sup1',30000,'PEN'),
  ('sup1',4000,'USD'),('sup2',50000,'PEN'),('sin_equipo',60000,'PEN')) v(clase,monto,moneda)
join actores a on a.clase=v.clase
cross join (values (date '2026-09-01'),(date '2026-10-01')) m(mes)
cross join actores c cross join actores g where c.clase='cliente' and g.clase='gerencia';
create temporary table leads_coop(mes date, id uuid default gen_random_uuid());
insert into leads_coop(mes) values('2026-09-01'),('2026-10-01');
insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,creado_por,monto_estimado,categoria_interes)
select l.id,'PRUEBA COOPERATIVA','9000000'||lpad(extract(month from l.mes)::text,2,'0'),'referido',a.id,g.id,12000,'nuevo'
from leads_coop l cross join actores a cross join actores g
where a.clase='sup2' and g.clase='gerencia';
insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
  nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en,
  fecha_comercial,fecha_imputacion)
select l.id,'qorilazo',12000,'PEN','DNI','00000001','CLIENTE SINTETICO',
  'SUP-TEST-'||gen_random_uuid(),a.id,g.id,
  (mes+5)::timestamp at time zone 'America/Lima',mes+5,mes+5
from actores a cross join actores g cross join leads_coop l
where a.clase='sup2' and g.clase='gerencia';
select set_config('crm.op_privilegiada','',true);

create function pg_temp.sesion(p_clase text) returns void language sql as $f$
  select set_config('request.jwt.claim.sub',coalesce((select id::text from actores where clase=p_clase),''),true);
  select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from actores where clase=p_clase),'role','authenticated')::text,true);
$f$;
create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $f$
begin
  if p_ok is not true then raise exception 'FAIL: %',p_mensaje; end if;
  raise notice 'PASS: %',p_mensaje;
end $f$;

set local role authenticated;
select pg_temp.sesion('gerencia');
do $metas$ declare mes date; payload jsonb; begin
  select jsonb_object_agg(a.id::text,jsonb_build_object('conversion_objetivo',15,'detalles',d.valor))
  into payload from actores a cross join lateral (
    select jsonb_agg(jsonb_build_object('categoria',categoria,'moneda',moneda,
      'capital_objetivo',case when categoria='nuevo' and moneda='PEN' then 1000 else 0 end,
      'contratos_objetivo',0)) as valor
    from (values('nuevo'),('renovacion'),('upgrade')) c(categoria)
      cross join (values('PEN'),('USD')) m(moneda)
  ) d where a.clase in ('vend1','vend2');
  foreach mes in array array[date '2026-09-01',date '2026-10-01'] loop
    perform crm.publicar_metas_vendedores(mes,0,payload);
  end loop;
end $metas$;
reset role;
