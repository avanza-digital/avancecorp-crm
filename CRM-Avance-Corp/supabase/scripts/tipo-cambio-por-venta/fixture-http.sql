-- Solo preparación sintética. Auth creó los usuarios con sus triggers reales.
set local session_replication_role=replica;
update public.perfiles set rol='cliente' where id=pg_temp.persona(5);
insert into public.perfiles(id,nombre_completo,rol)
select pg_temp.persona(n),'HTTP sintético '||n,case when n=8 then 'directorio' else 'analista' end
from unnest(array[8,9,11,12]) n;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo) values
  (pg_temp.persona(8),'directorio',null,true),(pg_temp.persona(9),'supervisor',null,false),
  (pg_temp.persona(11),'supervisor',null,true),(pg_temp.persona(12),'vendedor',pg_temp.persona(11),true);
-- El segundo analista pasa a otro equipo: ámbito que debe conservar HTTP.
update crm.equipo set supervisor_id=pg_temp.persona(11) where perfil_id=pg_temp.persona(3);
update public.perfiles set dni='48000002',telefono='999444002',correo='tc-http-2@example.test'
where id=pg_temp.persona(2);
set local session_replication_role=origin;
select set_config('request.jwt.claim.sub','',true);
create function pg_temp.tc_http(p_fecha date,p_tasa text) returns jsonb language sql as $$
  select jsonb_build_object('fecha_corte',p_fecha,'politica','sbs_punto_medio_7d_v1',
    'publicacion_confirmada',p_fecha,'fuente','BCRP · SBS PD04639PD/PD04640PD',
    'huella_respuestas',repeat('a',64),'pares',(select jsonb_agg(jsonb_build_object(
      'fecha',p_fecha-i,'compra',p_tasa,'venta',p_tasa)) from generate_series(0,6) i));
$$;
select private.consolidar_tc_venta(pg_temp.tc_http('2026-10-02','3.4'));
select private.consolidar_tc_venta(pg_temp.tc_http('2026-10-05','3.1'));
select private.consolidar_tc_venta(jsonb_build_object('fecha_corte','2026-09-30',
  'politica','sbs_punto_medio_hasta7_legado_v1','publicacion_confirmada','2026-10-01',
  'fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('b',64),
  'pares',jsonb_build_array(jsonb_build_object('fecha','2026-09-30','compra','3.5','venta','3.5'))));
select private.materializar_capital_valoraciones();
select private.publicar_corte_capital('2026-10-01');
update crm.capital_valoracion_politica set activa=true;
