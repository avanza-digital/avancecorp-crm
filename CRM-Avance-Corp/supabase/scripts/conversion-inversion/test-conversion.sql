-- Casos económicos completos, con rollback. Sólo se ejecuta en la copia sintética.
begin;
set local statement_timeout='120s';
-- El template alterna políticas en pruebas previas. Este oráculo exige el
-- modo estricto: la aprobación debe consumirse en el escritor contractual.
insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
  select coalesce(max(version),0)+1,statement_timestamp()-interval '1 second',15,50,7,'enforcement'
  from crm.politica_rentabilidad;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf','image/jpeg','image/png'])
  on conflict(id) do nothing;
create temporary table ci_leads on commit drop as
select row_number() over(order by l.id) n,l.id,l.vendedor_id,l.etapa
from crm.leads l where l.activo and l.etapa not in ('convertido','descartado')
  and not l.no_contactar and l.inversionista_id is null and l.dni is null
  and private.rol_crm(l.vendedor_id) is not null order by l.id limit 6;
create function pg_temp.exigir(ok boolean,mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'CONVERSION: %',mensaje; end if; end $$;
create function pg_temp.rechaza(p_sql text,p_estado text,p_mensaje text default null) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate=p_estado and (p_mensaje is null or position(p_mensaje in sqlerrm)>0) then return; end if;
    raise exception 'Esperado %, obtenido % (%)',p_estado,sqlstate,sqlerrm;
  end;
  raise exception 'Debió rechazar con %',p_estado;
end $$;
do $$
declare
  l record; inicial jsonb; r jsonb; d jsonb; confirmado jsonb; repetido jsonb;
  persona uuid; solicitud uuid:=gen_random_uuid(); adicional uuid:=gen_random_uuid();
  fecha date:=(statement_timestamp() at time zone 'America/Lima')::date;
  fuente crm.cierres_externos%rowtype;
begin
  perform pg_temp.exigir((select count(*) from ci_leads)=6,'faltan fixtures sintéticos');
  select * into l from ci_leads where n=1;
  perform set_config('request.jwt.claim.sub',l.vendedor_id::text,true);
  inicial:=crm.preparar_persona_lead_inversion_fn(l.id,'DNI','48000001','PERSONA PRUEBA UNIFICADA');
  persona:=(inicial->>'inversionista_id')::uuid;
  perform pg_temp.exigir((select etapa=l.etapa and perfil_id is null and convertido_en is null from crm.leads where id=l.id),'preparar identidad convirtió el lead');
  perform pg_temp.exigir(not exists(select 1 from crm.inversiones where inversionista_id=persona),'preparar identidad creó una inversión');
  perform pg_temp.exigir((crm.preparar_persona_lead_inversion_fn(l.id,'DNI','48000001','PERSONA PRUEBA UNIFICADA')->>'inversionista_id')::uuid=persona,'reintento duplicó identidad');
  perform pg_temp.rechaza(format('select private.inversion_persona_contexto(%L::uuid)',persona),'P0409');
  perform pg_temp.exigir(crm.contexto_conversion_inversion_fn(l.id,persona)#>>'{persona,responsable_id}'=l.vendedor_id::text,'contexto pierde al analista');
  d:=jsonb_build_object('inversionista_id',persona,'lead_id',l.id,'empresa','prodelco','monto',5000,'moneda','USD',
    'fecha_comercial',fecha,'vence_en',(fecha+interval '12 months')::date,'plazo_meses',12,'tasa_anual',18,
    'numero_transaccion','CI-USD-INICIAL','referencia','CERTIFICADO CI',
    'evidencia',jsonb_build_object('ruta',persona||'/'||solicitud||'/comprobante.pdf'));
  r:=crm.preparar_inversion_fn(solicitud,d);
  perform pg_temp.exigir(r->>'estado'='preparada','solicitud no preparada');
  perform pg_temp.exigir((select etapa=l.etapa from crm.leads where id=l.id),'cerrar el formulario después de preparar no conserva el lead');
  perform pg_temp.exigir(crm.preparar_inversion_fn(solicitud,d)->>'solicitud_id'=solicitud::text,'preparar no es idempotente');
  perform pg_temp.exigir(crm.preparar_persona_lead_inversion_fn(l.id,'DNI','48000001','PERSONA PRUEBA UNIFICADA')->>'solicitud_id'=solicitud::text,'reabrir no recupera la solicitud');
  perform pg_temp.rechaza(format('select crm.preparar_inversion_fn(%L::uuid,%L::jsonb)',gen_random_uuid(),d),'P0409');
  perform pg_temp.rechaza(format('select crm.corregir_solicitud_inversion_fn(%L,%L,0,%L,%L)',solicitud,gen_random_uuid(),d-'lead_id','Corregir las condiciones financieras'),'22023');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',solicitud),'P0409');
  perform pg_temp.exigir((select etapa=l.etapa from crm.leads where id=l.id),'confirmación sin comprobante convirtió el lead');
  perform pg_temp.exigir(not exists(select 1 from crm.inversiones where inversionista_id=persona),'fallo creó inversión');
  insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',d#>>'{evidencia,ruta}',
    '{"size":128,"mimetype":"application/pdf"}'::jsonb);
  confirmado:=crm.confirmar_inversion_revisada_fn(solicitud,0);
  repetido:=crm.confirmar_inversion_revisada_fn(solicitud,0);
  perform pg_temp.exigir(confirmado->>'inversion_id'=repetido->>'inversion_id','respuesta perdida duplicó inversión');
  perform pg_temp.exigir((select count(*)=1 from crm.inversiones where inversionista_id=persona),'más de una inversión inicial');
  perform pg_temp.exigir((select etapa='convertido' and convertido_en is not null and perfil_id is null from crm.leads where id=l.id),'el lead no se convirtió con la inversión cooperativa');
  select * into fuente from crm.cierres_externos where id=(confirmado#>>'{fuente,cierre_id}')::uuid;
  perform pg_temp.exigir(fuente.es_cierre_inicial and fuente.moneda='USD' and fuente.monto=5000 and fuente.fecha_comercial=fecha
    and fuente.vendedor_id=l.vendedor_id and fuente.comprobante_objeto_id is not null,'la fuente no conserva fecha, moneda, comprobante o analista');
  perform pg_temp.exigir((select es_primera_conversion from crm.inversiones where id=(confirmado->>'inversion_id')::uuid),'inversión sin marca inicial');
  perform pg_temp.exigir((select count(*)=1 from crm.inversion_titulares where inversion_id=(confirmado->>'inversion_id')::uuid and inversionista_id=persona and rol='principal'),'titular incorrecto');
  perform pg_temp.exigir(exists(select 1 from crm.lead_asignaciones where lead_id=l.id and resultado='convertido'),'episodio comercial no registra conversión');
  -- La siguiente inversión pasa por EXACTAMENTE las mismas dos puertas.
  d:=(d-'lead_id')||jsonb_build_object('numero_transaccion','CI-USD-ADICIONAL',
    'evidencia',jsonb_build_object('ruta',persona||'/'||adicional||'/comprobante.pdf'));
  perform crm.preparar_inversion_fn(adicional,d);
  insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',d#>>'{evidencia,ruta}','{"size":128,"mimetype":"application/pdf"}'::jsonb);
  r:=crm.confirmar_inversion_revisada_fn(adicional,0);
  perform pg_temp.exigir((select not es_primera_conversion from crm.inversiones where id=(r->>'inversion_id')::uuid),'adicional se contó como conversión');
  perform pg_temp.exigir((select count(*)=2 from crm.inversiones where inversionista_id=persona),'paridad inicial/adicional');
  raise notice 'PASS: conversión cooperativa, cancelación sin efectos económicos, corrección inmutable, comprobante, reintentos, atribución, episodio y registro adicional';
end $$;
do $$
declare
  l record; persona uuid; solicitud uuid:=gen_random_uuid(); perfil uuid:=gen_random_uuid();
  token text:=repeat('a',48); r jsonb; d jsonb; c jsonb; cuotas jsonb; confirmado jsonb;
  inicio date:=date_trunc('month',statement_timestamp() at time zone 'America/Lima')::date;
  antes bigint; tasa uuid; gerente uuid; vencimiento_aprobacion timestamptz;
begin
  select * into l from ci_leads where n=2;
  -- La comprobación del fixture detectó DNI/teléfono vacíos en el firmante.
  -- La siembra la hace el administrador local, fuera de una sesión comercial.
  perform set_config('request.jwt.claim.sub','',true);
  update public.perfiles set telefono=coalesce(nullif(telefono,''),'999555222'),
    dni=coalesce(nullif(dni,''),'48100002') where id=l.vendedor_id;
  perform set_config('request.jwt.claim.sub',l.vendedor_id::text,true);
  persona:=(crm.preparar_persona_lead_inversion_fn(l.id,'DNI','48000002','PERSONA PRUEBA AVANCE')->>'inversionista_id')::uuid;
  d:=jsonb_build_object('inversionista_id',persona,'lead_id',l.id,'empresa','avance',
    'contrato',jsonb_build_object('moneda','PEN'),'cronograma','[]'::jsonb,'cuenta','{}'::jsonb,
    'alta_portal',jsonb_build_object('correo','conversion.sintetica@example.test','nombre_completo','PERSONA PRUEBA AVANCE',
      'nombres','PERSONA','apellidos','PRUEBA AVANCE','telefono','999123456','domicilio','AVENIDA SINTETICA 123 LIMA'));
  r:=crm.preparar_inversion_fn(solicitud,d);
  perform pg_temp.exigir((r->>'necesita_portal')::boolean,'Avance no pide acceso');
  r:=crm.acceso_inversion_fn(solicitud,'reclamar',jsonb_build_object('token',token));
  perform pg_temp.exigir(r->>'token'=token,'el primer reclamo sustituyó el token guardado antes del envío');
  perform pg_temp.rechaza(format('select crm.acceso_inversion_fn(%L,%L,%L::jsonb)',solicitud,'reclamar',
    jsonb_build_object('token',repeat('b',48))),'P0409');
  -- Simula perder la primera respuesta: el token local sigue recuperando el claim.
  r:=crm.acceso_inversion_fn(solicitud,'reclamar',jsonb_build_object('token',token));
  perform pg_temp.exigir(r->>'token'=token and (r->>'reanudar')::boolean,'no recupera el primer reclamo');
  insert into auth.users(id,aud,role,email,raw_app_meta_data)
    values(perfil,'authenticated','authenticated','conversion.sintetica@example.test',jsonb_build_object('claim_id',r->>'claim_id'));
  r:=crm.acceso_inversion_fn(solicitud,'registrar_auth',jsonb_build_object('token',token,'version',r->'version','auth_user_id',perfil));
  r:=crm.acceso_inversion_fn(solicitud,'crear_perfil',jsonb_build_object('token',token,'version',r->'version'));
  r:=crm.acceso_inversion_fn(solicitud,'enlazar',jsonb_build_object('token',token,'version',r->'version'));
  perform pg_temp.exigir(r->>'perfil_id'=perfil::text,'la saga no enlazó el perfil');
  perform pg_temp.exigir((select etapa=l.etapa and perfil_id is null and convertido_en is null from crm.leads where id=l.id),'Auth/perfil convirtió anticipadamente el lead');
  perform pg_temp.exigir(not exists(select 1 from crm.inversiones where inversionista_id=persona),'Auth/perfil creó una inversión');
  perform pg_temp.exigir(crm.acceso_inversion_fn(solicitud,'reclamar',jsonb_build_object('token',token))->>'perfil_id'=perfil::text,'acceso no idempotente');
  perform pg_temp.rechaza(format('select crm.convertir_lead(%L,%L)',l.id,perfil),'P0409');
  perform pg_temp.exigir((select count(*)=1 from public.perfiles where id=perfil),'perfil duplicado');
  select jsonb_agg(jsonb_build_object('numero_cuota',n,'fecha_programada',(inicio+(n||' months')::interval)::date,
    'monto_programado',18.75,'tipo','cuota') order by n) into cuotas from generate_series(1,12) n;
  cuotas:=cuotas||jsonb_build_array(jsonb_build_object('numero_cuota',13,'fecha_programada',(inicio+interval '12 months 7 days')::date,
    'monto_programado',1500,'tipo','retorno'));
  c:=jsonb_build_object('categoria','nuevo','capital',1500,'moneda','PEN','tasa_anual',15,'modalidad','mensual',
    'tipo_interes','simple','fecha_inicio',inicio,'fecha_vencimiento',(inicio+interval '12 months')::date);
  d:=d||jsonb_build_object('contrato',c,'cronograma',cuotas,
    'cuenta',jsonb_build_object('tipo','nueva','banco','BANCO SINTETICO','tipo_cuenta','ahorros',
      'numero_cuenta','CI-PEN-001','cci','99999999999999999991','titular_distinto',false));
  -- Un error después de entrar al escritor contractual debe revertir TODO.
  d:=jsonb_set(d,'{contrato,titulares}','[{"nombre_completo":"COTITULAR INVALIDO","tipo_documento":"DNI","documento":"123"}]'::jsonb);
  perform crm.corregir_solicitud_inversion_fn(solicitud,gen_random_uuid(),0,d,'Completar condiciones de la inversión');
  select count(*) into antes from public.contratos;
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,1)',solicitud),'P0001','Documento invalido para el co-titular');
  perform pg_temp.exigir((select count(*)=antes from public.contratos),'fallo dejó contrato parcial');
  perform pg_temp.exigir((select etapa=l.etapa from crm.leads where id=l.id),'fallo contractual convirtió lead');
  d:=d#-'{contrato,titulares}';
  perform crm.corregir_solicitud_inversion_fn(solicitud,gen_random_uuid(),1,d,'Corregir los datos del cotitular');
  tasa:=(crm.solicitar_tasa_fn(c||jsonb_build_object('lead_id',l.id,'tasa_anual',18,'tasa_solicitada',18,
    'motivo','Validar condiciones de la primera inversión sintética'))->>'id')::uuid;
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,2)',solicitud),'P0411');
  perform pg_temp.exigir((select etapa=l.etapa from crm.leads where id=l.id),'una tasa pendiente convirtió el lead');
  select perfil_id into gerente from crm.equipo where activo and rol_crm='gerencia' limit 1;
  perform set_config('request.jwt.claim.sub',gerente::text,true);
  perform crm.resolver_solicitud_tasa_fn(tasa,'aprobar_hasta',17,'Tope del ensayo sintético');
  perform set_config('request.jwt.claim.sub',l.vendedor_id::text,true);
  d:=jsonb_set(d,'{contrato,tasa_anual}','17'::jsonb);
  -- Cronograma de las mismas condiciones a la tasa autorizada.
  d:=jsonb_set(d,'{cronograma}',(select jsonb_agg(case when x->>'tipo'='cuota'
    then jsonb_set(x,'{monto_programado}','21.25'::jsonb) else x end order by ord)
    from jsonb_array_elements(d->'cronograma') with ordinality a(x,ord)));
  perform crm.corregir_solicitud_inversion_fn(solicitud,gen_random_uuid(),2,d,'Aplicar el tope a las mismas condiciones');
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,3)',solicitud),'P0410');
  perform crm.responder_tope_tasa_fn(tasa,true);
  -- Una aprobación vencida y un cambio de capital no autorizan el cierre.
  select vence_en into vencimiento_aprobacion from crm.solicitudes_tasa where id=tasa;
  -- Sólo el reloj del fixture; la confirmación conserva la sesión comercial.
  perform set_config('crm.solicitud_tasa_por_puerta','on',true);
  update crm.solicitudes_tasa set solicitada_en=clock_timestamp()-interval '2 minutes',
    vence_en=clock_timestamp()-interval '1 minute' where id=tasa;
  perform set_config('crm.solicitud_tasa_por_puerta','off',true);
  perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,3)',solicitud),'P0410');
  perform set_config('crm.solicitud_tasa_por_puerta','on',true);
  update crm.solicitudes_tasa set vence_en=vencimiento_aprobacion where id=tasa;
  perform set_config('crm.solicitud_tasa_por_puerta','off',true);
  perform pg_temp.rechaza(format('select private.validar_tasa_conversion_lead(%L,%L,%L::jsonb)',l.id,perfil,
    (d->'contrato')||'{"capital":1600}'::jsonb),'P0410');
  confirmado:=crm.confirmar_inversion_revisada_fn(solicitud,3);
  set constraints all immediate;
  perform pg_temp.exigir((select estado='consumida' and contrato_id=(confirmado#>>'{fuente,id}')::uuid
    from crm.solicitudes_tasa where id=tasa),'la aprobación no se consumió en el contrato confirmado');
  perform pg_temp.exigir((select etapa='convertido' and perfil_id=perfil and contrato_id=(confirmado#>>'{fuente,id}')::uuid
    from crm.leads where id=l.id),'contrato y conversión no quedaron vinculados');
  perform pg_temp.exigir((select count(*)=13 from public.cronograma_pagos where contrato_id=(confirmado#>>'{fuente,id}')::uuid),'cronograma incompleto');
  perform pg_temp.exigir(exists(select 1 from crm.contrato_cuentas_pago where contrato_id=(confirmado#>>'{fuente,id}')::uuid),'falta cuenta de pago');
  perform pg_temp.exigir((select analista_cierre_id=l.vendedor_id from public.contratos where id=(confirmado#>>'{fuente,id}')::uuid),'atribución Avance incorrecta');
  perform pg_temp.exigir(crm.confirmar_inversion_revisada_fn(solicitud,3)->>'inversion_id'=confirmado->>'inversion_id','reintento Avance duplicó inversión');
  perform pg_temp.exigir((select count(*)=1 from crm.inversiones where inversionista_id=persona),'Avance creó más de una inversión');
  perform pg_temp.exigir((select es_primera_conversion from crm.inversiones where id=(confirmado->>'inversion_id')::uuid),'Avance perdió marca inicial');
  raise notice 'PASS: Avance prepara/Auth/perfil sin convertir; corrección, rollback contractual, contrato/cuenta/cronograma, atribución y reintento único';
end $$;
rollback;
