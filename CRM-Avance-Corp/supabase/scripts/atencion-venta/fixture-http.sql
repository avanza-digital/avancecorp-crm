-- Solo banco propio 55483 con esquema vacío. Fixtures sintéticos; triggers activos.
\set ON_ERROR_STOP on
begin;
set local statement_timeout='90s';
do $$ begin
 if current_database()<>'atencion_http' or current_user<>'postgres' or exists(select 1 from public.perfiles) then raise exception 'Solo banco vacío propio'; end if;
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

commit;
