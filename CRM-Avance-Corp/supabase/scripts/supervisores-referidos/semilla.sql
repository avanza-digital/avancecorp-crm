-- Banco exclusivo vacío, estructura productiva, datos sintéticos y ROLLBACK.
do $guardia$ begin
  if current_database() <> 'supervisores_referidos_20261016'
     or current_user <> 'postgres'
     or current_setting('session_replication_role') <> 'origin'
     or exists(select 1 from crm.equipo)
     or exists(select 1 from crm.leads)
     or exists(select 1 from public.contratos) then
    raise exception 'Solo se permite el banco local exclusivo y vacío';
  end if;
end $guardia$;

insert into crm.productos_inversion(codigo,es_legacy,permite_altas_legacy,estado,archivado_en)
values('HISTORICO-SIN-CATALOGO',true,true,'archivado',now());
insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
values(1,'2000-01-01','America/Lima','corrido',60,120);
insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
select id,'nuevo',120 from crm.sla_politicas;
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota)
values('2000-01-01',0.15,0.15,'Prueba sintética de referidos');
insert into crm.multiempresa_flags(nombre,activo)
values('resolver_en_puertas',true),('inversiones_escritura',true),('ficha_360_neutral',true),
  ('postventa_neutral',true),('potencial_lead',true),('metricas_multiempresa_sombra',false);
insert into crm.empresas(clave,nombre_legal,nombre_visible,activa,monedas,crea_contrato_avance,requiere_portal,exige_numero_transaccion,fuente_capital)
values('qorilazo','Cooperativa sintética','Cooperativa sintética',true,array['PEN'],false,false,true,'cierres_externos');
insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
values(1,'2000-01-01',15,28,1,'enforcement');

create temporary table actores(clase text primary key,id uuid not null default gen_random_uuid());
insert into actores(clase) values('gerencia'),('coordinador'),('directorio'),('sup1'),('sup2'),('sin_equipo'),('para_baja'),('para_cambio'),('vend1'),('vend2'),('cliente');
grant select on actores to authenticated;
insert into auth.users(id,email) select id,id::text||'@referidos.example.invalid' from actores;
insert into public.perfiles(id,nombre_completo,correo,rol,activo,tipo_documento,debe_cambiar_password,titular_distinto,titular_distinto_usd)
select id,'PRUEBA '||clase,id::text||'@referidos.example.invalid',
  case when clase='cliente' then 'cliente' when clase='directorio' then 'directorio'
    when clase in ('vend1','vend2') then 'analista' else 'comercial' end,
  true,'DNI',false,false,false from actores;
insert into crm.equipo(perfil_id,rol_crm,activo)
select id,case when clase in ('sup1','sup2','sin_equipo','para_baja','para_cambio') then 'supervisor' else clase end,true
from actores where clase in ('gerencia','directorio','coordinador','sup1','sup2','sin_equipo','para_baja','para_cambio');
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select a.id,'vendedor',s.id,true from actores a join actores s
  on s.clase=case a.clase when 'vend1' then 'sup1' when 'vend2' then 'sup2' end
where a.clase in ('vend1','vend2');

create function pg_temp.sesion(p_clase text) returns void language sql as $f$
  select set_config('request.jwt.claim.sub',coalesce((select id::text from actores where clase=p_clase),''),true);
  select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from actores where clase=p_clase),'role','authenticated')::text,true);
$f$;
create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $f$
begin
  if p_ok is not true then raise exception 'FAIL: %',p_mensaje; end if;
  raise notice 'PASS: %',p_mensaje;
end $f$;
create function pg_temp.rechaza(p_sql text,p_codigo text,p_mensaje text) returns void language plpgsql as $f$
declare codigo text;
begin
  begin execute p_sql; exception when others then get stacked diagnostics codigo=returned_sqlstate; end;
  perform pg_temp.exigir(codigo=p_codigo,p_mensaje||' ['||coalesce(codigo,'sin rechazo')||']');
end $f$;
create function pg_temp.alta(p_n integer,p_origen text default 'referido',p_destino uuid default null) returns jsonb language sql as $f$
  select crm.crear_lead_si_disponible(p_nombre_completo=>'REFERIDO SINTETICO',p_telefono=>(900000000+p_n)::text,
    p_origen=>p_origen,p_monto_estimado=>20000,p_moneda=>'PEN',p_id=>md5('referido-'||p_n)::uuid,
    p_dni=>(96000000+p_n)::text,p_vendedor_id=>p_destino);
$f$;
