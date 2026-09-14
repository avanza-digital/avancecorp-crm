-- Sólo banco desechable con seed-demo. Todas las guardas permanecen activas.
-- El lote completo debe enviarse en una sesión. No deja datos de prueba.
begin;
set local statement_timeout='180s';
do $$ begin
  if exists(select 1 from auth.users where email not like '%@pruebas.example' and email not like '%@demo.avancecorp.pe') then
    raise exception 'Sólo banco de pruebas';
  end if;
end $$;
create temporary table citas_avance_ids as
select n,gen_random_uuid() lead_id,gen_random_uuid() tarea_id,gen_random_uuid() cliente_id,gen_random_uuid() contrato_id,
  (select id from public.perfiles where correo='vend1.crm@demo.avancecorp.pe') analista,
  (select id from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe') gerencia
from generate_series(1,4) n;
do $$ begin assert (select bool_and(analista is not null and gerencia is not null) from citas_avance_ids),'Falta semilla demo'; end $$;
select set_config('request.jwt.claim.sub','',true);
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,moneda,vendedor_id,creado_por,alta_manual)
select lead_id,'CITAS AVANCE SINTETICO '||n,'+51962'||lpad(n::text,6,'0'),'referido',20000,'PEN',analista,analista,n=2 from citas_avance_ids;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por,modalidad_reunion,ubicacion_reunion)
select tarea_id,lead_id,'reunion','CITAS AVANCE SINTETICO',
  case when n=4 then date_trunc('month',now())+interval '1 month 1 day'
       when n=3 then date_trunc('month',now())-interval '1 day' else now()-interval '1 hour' end,
  analista,'presencial','Oficina de prueba' from citas_avance_ids where n<>2;
select set_config('request.jwt.claim.sub',(select analista::text from citas_avance_ids limit 1),true);
do $$declare r record; begin
  for r in select * from citas_avance_ids where n in(1,3) loop
    perform crm.cerrar_reunion(r.tarea_id,'completada','interesado',null,'Entrevista sintética');
  end loop;
end $$;
select set_config('request.jwt.claim.sub','',true);
insert into auth.users(id,email) select cliente_id,'citas-'||cliente_id::text||'@pruebas.example' from citas_avance_ids where n=1;
insert into public.perfiles(id,correo,nombre_completo,rol,activo,dni,asesor_perfil_id)
select cliente_id,'citas-'||cliente_id::text||'@pruebas.example','CLIENTE CITAS SINTETICO','cliente',true,'93876251',analista from citas_avance_ids where n=1
on conflict(id) do update set rol=excluded.rol,nombre_completo=excluded.nombre_completo,activo=excluded.activo,dni=excluded.dni,asesor_perfil_id=excluded.asesor_perfil_id;
-- Clona sólo un contrato ficticio del seed. El importe USD difiere del lead PEN.
insert into public.contratos
select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
  'id',m.contrato_id,'cliente_id',m.cliente_id,'numero_contrato','CITAS-'||m.contrato_id::text,
  'capital',12000,'moneda','USD','fecha_inicio',current_date,'fecha_vencimiento',current_date+365,
  'producto_condicion_id',private.crear_snapshot_producto_legacy(m.contrato_id,c.categoria,'USD',c.modalidad,c.tipo_interes,12000,c.tasa_anual,current_date,current_date+365),
  'fecha_cierre_comercial',null,'analista_cierre_id',m.analista,'creado_en',now(),
  'estado','activo','es_demo',false))).*
from citas_avance_ids m cross join lateral(select * from public.contratos where analista_cierre_id is not null limit 1)c where m.n=1;
select set_config('request.jwt.claim.sub',(select gerencia::text from citas_avance_ids limit 1),true);
do $$declare r record; begin
  select * into r from citas_avance_ids where n=1;
  perform crm.convertir_lead(r.lead_id,r.cliente_id);
end $$;
select set_config('request.jwt.claim.sub',(select gerencia::text from citas_avance_ids limit 1),true);
create temporary table citas_avance_resultado as
select crm.citas_gerencia_consulta_fn(date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month -1 day')::date) r;
do $$declare r jsonb; c jsonb; k jsonb; v_caso record; v_identidad text; v_inversionista uuid; begin
  select t.r into r from citas_avance_resultado t;
  assert r->'gestion'->>'version'='2','Contrato mensual V2';
  assert r->'gestion'->>'citas_por_lead'='1.25','Meta interna correcta';
  assert r->'gestion'->'control'->'configuracion'->>'excluir_manuales_base'='false','Manuales incluidos';
  assert (select count(*) from jsonb_array_elements(r->'gestion'->'asignaciones') a join citas_avance_ids m on m.lead_id=(a->>'lead_id')::uuid)=4,'Todos los asignados, con o sin cita';
  assert (select count(*) from jsonb_array_elements(r->'citas') a join citas_avance_ids m on m.tarea_id=(a->>'id')::uuid)=3,'Cita creada para otro mes y entrevista prevista antes';
  select * into v_caso from citas_avance_ids where n=1;
  select a into c from jsonb_array_elements(r->'gestion'->'conversiones') a where a->>'lead_id'=v_caso.lead_id::text;
  assert c->>'perfil_id'=v_caso.cliente_id::text and c->>'analista_id'=v_caso.analista::text,'Conversión y atribución del núcleo';
  assert c->>'contrato_id' is null,'La prueba reproduce el flujo real sin contrato en el lead';
  select a into k from jsonb_array_elements(r->'gestion'->'capital') a where a->>'contrato_id'=v_caso.contrato_id::text;
  assert k is not null and (k->>'monto')::numeric=12000 and k->>'moneda'='USD','Capital real separado de monto estimado PEN';
  assert k->>'perfil_id'=v_caso.cliente_id::text,'Importe del mismo cliente';
  assert (select count(*) from jsonb_array_elements(r->'gestion'->'poblacion') p join citas_avance_ids i on i.lead_id=(p->>'lead_id')::uuid where p->>'analista_origen_id'=i.analista::text)=4,'Origen acreditado en ledger';
  select p->>'identidad_persona' into v_identidad from jsonb_array_elements(r->'gestion'->'poblacion') p where p->>'lead_id'=v_caso.lead_id::text;
  if (select activo from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    select inversionista_id into v_inversionista from crm.leads where id=v_caso.lead_id;
    assert v_inversionista is not null,'La conversión nativa con F3 enlaza la identidad';
    assert v_identidad='persona:'||private.inversionista_canonica(v_inversionista)::text,'Identidad canónica de la conversión con F3';
  else
    assert v_identidad='perfil:'||v_caso.cliente_id::text,'Identidad del perfil en el modo anterior sin F3';
  end if;
  assert not exists(select 1 from jsonb_array_elements(r->'gestion'->'poblacion') p where p->>'identidad_persona' is null),'Identidad presente también sin conversión';
end $$;
-- Puertas y anulación: ningún rol distinto de Gerencia recibe la población.
do $$declare p record; begin
  for p in select id from public.perfiles where correo like '%@demo.avancecorp.pe' and id<>(select gerencia from citas_avance_ids limit 1) loop
    perform set_config('request.jwt.claim.sub',p.id::text,true);
    begin
      perform crm.citas_gerencia_consulta_fn(date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month -1 day')::date);
      raise exception 'Acceso indebido';
    exception when insufficient_privilege then null; end;
  end loop;
end $$;
select set_config('request.jwt.claim.sub',(select gerencia::text from citas_avance_ids limit 1),true);
select crm.anular_cierre_avance(lead_id,'Anulación sintética de prueba de Citas') from citas_avance_ids where n=1;
do $$declare r jsonb; begin
  r:=crm.citas_gerencia_consulta_fn(date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month -1 day')::date);
  assert not exists(select 1 from jsonb_array_elements(r->'gestion'->'conversiones') a join citas_avance_ids m on m.n=1 and m.lead_id=(a->>'lead_id')::uuid),'Anulación excluye conversión';
  assert not exists(select 1 from jsonb_array_elements(r->'gestion'->'capital') a join citas_avance_ids m on m.n=1 and m.contrato_id=(a->>'contrato_id')::uuid),'Anulación excluye ticket';
end $$;
select private.assert_analitica_leads_citas();
select jsonb_build_object('estado','PASS','casos',array['manuales','base sin citas','registro vs fecha prevista','entrevista anterior','conversion nativa','capital real USD','atribucion','roles','anulacion','censo']) evidencia;
rollback;
