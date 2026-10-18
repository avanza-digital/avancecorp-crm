-- Altas y cierres por las puertas reales, con datos sintéticos y triggers activos.
set local role authenticated;
select set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000001',true);
create temporary table _alta_manual_f3 as select crm.crear_lead_si_disponible(
  'ALTA MANUAL F3','985002001','formulario_3',1000,'PEN') as recibo;
reset role;
select set_config('request.jwt.claim.sub','',true);

select pg_temp.exigir((select count(*)=1 and bool_and(alta_manual and origen='formulario_3')
  from crm.leads where telefono='+51985002001'),'alta manual nativa por RPC, con procedencia manual');
select pg_temp.exigir((select campania_origen is null from crm.leads where telefono='+51985002001'),
  'alta manual F3 usa el origen nativo sin atribuirle una campaña de importación');

select crm.importar_lead_fn(jsonb_build_object('nombre_completo','ALTA AUTOMATICA F3',
 'telefono','985002002','origen','formulario_3','monto_estimado',1000,'moneda','PEN',
 'vendedor_id','f6000000-0000-0000-0000-000000000001'));
create temporary table _llegadas_f3 as
select e.* from private.conversion_episodios(now()-interval '1 day',now()+interval '1 day',null,true,null,1) e
join crm.leads l on l.id=e.lead_id where l.telefono in ('+51985002001','+51985002002') and e.tipo='recibido';
select pg_temp.exigir((select count(*)=2 and sum(aporte_divisor)=1 from _llegadas_f3),
 'manual no suma divisor, automático suma una sola llegada');

-- Mismo cambio operativo que los demás orígenes: no mueve la atribución inicial.
select set_config('crm.op_privilegiada','on',true);
update crm.leads set vendedor_id='f6000000-0000-0000-0000-000000000004'
where telefono in ('+51985002001','+51985002002');
select set_config('crm.op_privilegiada','off',true);
select pg_temp.exigir((select count(*)=2 and bool_and(e.analista_id='f6000000-0000-0000-0000-000000000001'::uuid)
 and sum(e.aporte_divisor)=1 from private.conversion_episodios(now()-interval '1 day',now()+interval '1 day',null,true,null,1) e
 join crm.leads l on l.id=e.lead_id where l.telefono in ('+51985002001','+51985002002') and e.tipo='recibido'),
 'reasignar no altera la primera atribución ni duplica llegadas');

-- Puertas reales de inversión; solo el objeto de Storage es una fixture de metadatos.
update crm.conversion_politica set activada_en=now(),manifiesto_huella='fixture-f3',resultado='{}' where unica;
update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura');
insert into crm.empresas(clave,nombre_legal,nombre_visible,activa,monedas,
 crea_contrato_avance,requiere_portal,exige_numero_transaccion,fuente_capital)
values('qorilazo','Cooperativa sintética','Cooperativa sintética',true,array['PEN'],false,false,true,'cierres_externos');
set local role supabase_admin;
-- El esquema mínimo del banco no copia ACL de Storage. En producción postgres
-- tiene ALL WITH GRANT OPTION en ambas tablas (consulta de ACL del 15/10/2026).
-- Se reproduce ese permiso solo dentro de esta transacción, luego ROLLBACK.
grant all on storage.buckets,storage.objects to postgres with grant option;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do nothing;
set local role postgres;
do $convertir$
declare l record; persona uuid; solicitud uuid; datos jsonb; r jsonb; repetido jsonb;
 fecha date := (statement_timestamp() at time zone 'America/Lima')::date;
begin
 for l in select id,nombre_completo,vendedor_id,row_number() over(order by telefono) numero
   from crm.leads where telefono in ('+51985002001','+51985002002','+51985000004') loop
   perform set_config('request.jwt.claim.sub',l.vendedor_id::text,true);
   execute 'set local role authenticated';
   persona := (crm.preparar_persona_lead_inversion_fn(l.id,'DNI','4950020'||l.numero,l.nombre_completo)->>'inversionista_id')::uuid;
   solicitud := gen_random_uuid();
   datos := jsonb_build_object('inversionista_id',persona,'lead_id',l.id,'empresa','qorilazo',
     'monto',5000,'moneda','PEN','fecha_comercial',fecha,'vence_en',(fecha+interval '12 months')::date,
     'plazo_meses',12,'tasa_anual',18,'numero_transaccion','F3-LOCAL-'||solicitud,'referencia','CERTIFICADO FICTICIO',
     'evidencia',jsonb_build_object('ruta',persona||'/'||solicitud||'/comprobante.pdf'));
   perform crm.preparar_inversion_fn(solicitud,datos);
   execute 'set local role supabase_admin';
   insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',datos#>>'{evidencia,ruta}',
     '{"size":128,"mimetype":"application/pdf"}'::jsonb);
   execute 'set local role authenticated';
   r := crm.confirmar_inversion_revisada_fn(solicitud,0);
   repetido := crm.confirmar_inversion_revisada_fn(solicitud,0);
   execute 'reset role';
   perform pg_temp.exigir(r->>'inversion_id'=repetido->>'inversion_id',
     'cierre F3 por el formulario compartido no duplica la inversión al reintentar');
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
end $convertir$;
select pg_temp.exigir((select count(*)=3 and sum(e.aporte_numerador)=3
 and bool_and(e.origen='formulario_3' and not e.anulado)
 from private.conversion_episodios(now()-interval '1 day',now()+interval '1 day',null,true,null,1) e
 join crm.leads l on l.id=e.lead_id where l.telefono in ('+51985002001','+51985002002','+51985000004') and e.tipo='cierre'),
 'cierres F3 nativos y legado aportan uno por la acreditación real');
select pg_temp.exigir((select cierres_formulario_3=3 and cierres_otros=0
 from private.conversion_divisor_empresa_totales((now() at time zone 'America/Lima')::date,
 (now() at time zone 'America/Lima')::date)), 'agregado separa cierres F3 de otros sin perder aportes');
set local role authenticated;
select set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000006',true);
select pg_temp.exigir((crm.conversion_divisor_coordinacion_fn(
 p_desde=>(now() at time zone 'America/Lima')::date,p_hasta=>(now() at time zone 'America/Lima')::date)
 #>>'{empresa,cierres,formulario_3}')::int=3, 'RPC pública de Coordinación refleja cierres F3');
reset role;
select set_config('request.jwt.claim.sub','',true);

-- La pantalla de Gerencia usa esta puerta genérica con filtro exacto.
set local role authenticated;
select set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000002',true);
do $$ declare r jsonb; begin
  r:=crm.metricas_conversiones_fn((now() at time zone 'America/Lima')::date,
    (now() at time zone 'America/Lima')::date,'formulario_3');
  perform pg_temp.exigir(r->>'origen_filtrado'='formulario_3'
    and (r#>>'{cierres_por_semana,cierres}')::int=3
    and not exists(select 1 from jsonb_array_elements(r->'origenes') f where f->>'origen'<>'formulario_3'),
    'métrica de Gerencia admite y aplica el filtro F3');
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
