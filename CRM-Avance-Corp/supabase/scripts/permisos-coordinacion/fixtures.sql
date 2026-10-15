-- Datos exclusivamente sintéticos. El llamante abre la transacción y termina en ROLLBACK.
do $$ begin
  if current_database() not like 'permisos_coordinacion_%' then
    raise exception 'Este ensayo solo admite el banco aislado de permisos';
  end if;
  if exists(select 1 from public.contratos) or exists(select 1 from crm.equipo) then
    raise exception 'El ensayo requiere un banco vacío, sin datos de usuarios';
  end if;
end; $$;
create function pg_temp.uid(n integer) returns uuid language sql immutable as $$
  select ('cc150000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.sesion(n integer) returns void language sql as $$
  select set_config('request.jwt.claim.sub',pg_temp.uid(n)::text,true);
  select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.uid(n),'role','authenticated')::text,true);
$$;

-- Solo la siembra de identidades omite sus triggers; todos vuelven a estar activos antes del ensayo.
set local session_replication_role=replica;
insert into auth.users(id,email) select pg_temp.uid(n),'prueba'||n||'@coordinacion.invalid'
from generate_series(1,20) n;
insert into public.perfiles(id,nombre_completo,correo,rol,activo,dni,tipo_documento,asesor_perfil_id)
select pg_temp.uid(n),'PRUEBA COORDINACION '||n,'prueba'||n||'@coordinacion.invalid',
  case when n=3 then 'admin' when n=7 then 'superadmin' when n=6 then 'directorio'
    when n>=10 then 'cliente' else 'comercial' end,
  n<>9,(48001000+n)::text,'DNI',case when n>=10 then pg_temp.uid(4) end
from generate_series(1,20) n;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select pg_temp.uid(n),case n when 1 then 'coordinador' when 2 then 'gerencia'
  when 4 then 'vendedor' when 5 then 'supervisor' when 6 then 'directorio' else 'coordinador' end,
  case when n=4 then pg_temp.uid(5) end,n<>8
from unnest(array[1,2,4,5,6,8,9]) n;
insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
select pg_temp.uid(100+n),pg_temp.uid(n),pg_temp.uid(4)
from generate_series(10,20) n;
insert into crm.productos_inversion(codigo,es_legacy,permite_altas_legacy,estado,archivado_en)
values('HISTORICO-SIN-CATALOGO',true,true,'archivado',now());
insert into crm.multiempresa_flags(nombre,activo) values
  ('resolver_en_puertas',false),('ficha_360_neutral',false),('inversiones_escritura',false)
on conflict(nombre) do update set activo=false;
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota)
values('2026-10-01',0.15,0,'Reglas sintéticas de octubre');
insert into crm.conversion_politica(activada_en,manifiesto_huella,resultado)
values('2026-09-01',repeat('a',64),'{}') on conflict(unica) do nothing;
insert into crm.sla_politicas(id,version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
values(pg_temp.uid(50),1,'-infinity','America/Lima','corrido',1440,1440);
insert into crm.sla_operacion_control(id) values(true) on conflict(id) do nothing;
set local session_replication_role=origin;

-- Contratos reales dentro del banco: snapshot, auditoría y triggers de negocio activos.
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,
  fecha_inicio,fecha_vencimiento,categoria,analista_cierre_id,creado_por,creado_en)
select pg_temp.uid(1000+n),'PRUEBA-ANTERIOR-'||n,pg_temp.uid(n),1000,'PEN',15,'mensual',
  '2026-09-01','2027-09-01','nuevo',pg_temp.uid(4),pg_temp.uid(4),'2026-09-01 12:00:00-05'
from generate_series(10,19) n;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,
  fecha_inicio,fecha_vencimiento,categoria,analista_cierre_id,creado_por,creado_en)
select pg_temp.uid(2000+n),'PRUEBA-ACTUAL-'||n,pg_temp.uid(n),2000,'PEN',15,'mensual',
  '2026-10-05','2027-10-05','nuevo',pg_temp.uid(4),pg_temp.uid(4),'2026-10-05 12:00:00-05'
from generate_series(10,20) n;
insert into crm.operaciones_cartera(id,cliente_id,vendedor_id,tipo,contrato_origen_id,contrato_nuevo_id,
  fecha_operacion,periodo,moneda,capital_renovado,capital_adicional,elegible_conversion,desglose_completo,fuente,creado_por,creado_en)
select pg_temp.uid(3000+n),pg_temp.uid(n),pg_temp.uid(4),case when n in (11,14) then 'upgrade' else 'renovacion' end,
  case when n not in (11,14) then pg_temp.uid(1000+n) end,pg_temp.uid(2000+n),'2026-10-05','2026-10-01','PEN',
  case when n not in (11,14) then 1500 end,case when n not in (11,14) then 500 end,
  true,true,'flujo_cartera',pg_temp.uid(4),'2026-10-05 12:00:00-05'
from unnest(array[11,12,14,15]) n;
set constraints all immediate;
set constraints all deferred;

-- Estado comercial sintético, con relojes y entidades verificables.
set local session_replication_role=replica;
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,perfil_id,inversionista_id,contrato_id,vendedor_id,
  creado_en,convertido_en,tenencia_desde,monto_estimado)
select pg_temp.uid(4000+n),'LEAD PRUEBA '||n,'9840010'||lpad(n::text,2,'0'),'landing','convertido',
  pg_temp.uid(n),pg_temp.uid(100+n),pg_temp.uid(2000+n),pg_temp.uid(4),
  '2026-10-01 10:00:00-05','2026-10-05 12:00:00-05','2026-10-01 10:00:00-05',2000
from generate_series(10,20) n;
insert into crm.lead_asignaciones(id,lead_id,ciclo_n,episodio_n,analista_id,motivo_apertura,asignado_en,moneda,origen,
  finalizado_en,motivo_cierre,resultado,resultado_en,sla_global_iniciado_en,sla_politica_asignacion_id,
  primera_gestion_limite_en,primer_contacto_limite_en)
select pg_temp.uid(5000+n),pg_temp.uid(4000+n),1,1,pg_temp.uid(4),'asignado','2026-10-01 10:00:00-05','PEN','landing',
  '2026-10-05 12:00:00-05','convertido','convertido','2026-10-05 12:00:00-05','2026-10-01 10:00:00-05',pg_temp.uid(50),
  '2026-10-02 10:00:00-05','2026-10-02 10:00:00-05'
from generate_series(10,20) n;
insert into crm.conversion_acreditaciones(lead_id,episodio_id,inversionista_id,analista_id,origen,fuente_tipo,fuente_id,
  fecha_comercial,confirmado_en,vinculado_en,acreditado_en,periodo_comercial,plazo_hasta,estado,motivo)
select pg_temp.uid(4000+n),pg_temp.uid(5000+n),pg_temp.uid(100+n),pg_temp.uid(4),'landing','contrato',pg_temp.uid(2000+n),
  '2026-10-05','2026-10-05 12:00:00-05','2026-10-05 12:00:00-05','2026-10-05 12:00:00-05','2026-10-01',
  private.conversion_plazo_hasta('2026-10-01'),case when n in (11,12,14,15) then 'operacion_cartera' else 'acreditada' end,
  'Captación sintética original'
from generate_series(10,20) n;
insert into crm.actividades(lead_id,tipo,creado_por) values(pg_temp.uid(4010),'nota',pg_temp.uid(4));
insert into crm.tareas(lead_id,titulo,tipo,vence_en,vendedor_id)
values(pg_temp.uid(4010),'Seguimiento sintético','llamada','2026-10-15',pg_temp.uid(4));
update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','ficha_360_neutral');
set local session_replication_role=origin;
