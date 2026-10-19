-- Banco local sintético. El alcance se prueba con leads/borradores anteriores
-- a la activación, cierres normales, roles reales y rollback de todas las filas.
begin;
set local statement_timeout='90s';
set local lock_timeout='3s';
create function pg_temp.exigir(p_ok boolean,p_texto text) returns void language plpgsql as $$
begin if p_ok is not true then raise exception 'TODOS PENDIENTES: %',p_texto;end if;end $$;
create function pg_temp.rechaza(p_sql text,p_codigo text,p_texto text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlstate=p_codigo and position(p_texto in sqlerrm)>0 then return;end if;
    raise exception 'Esperado % / %, obtenido % / %',p_codigo,p_texto,sqlstate,sqlerrm;
  end;
  raise exception 'La operacion debio rechazarse: %',p_sql;
end $$;
create temporary table casos_todos(nombre text primary key,id uuid default gen_random_uuid(),
  documento text,solicitud uuid default gen_random_uuid(),persona uuid,datos jsonb,tarea uuid,actividad uuid);
grant select,update on casos_todos to authenticated;
insert into casos_todos(nombre,documento) values
 ('borrador_antiguo','98648001'),('sin_persona_antiguo','98648002'),('valido_antes','98648003');
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
 select id,'BANCO TODOS '||nombre,'98648'||lpad(row_number() over(order by nombre)::text,4,'0'),'oficina',1000,
 'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002' from casos_todos;
insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing;
select set_config('banco.vence_todos',private.coopac_validar_condiciones((clock_timestamp() at time zone 'America/Lima')::date,12,12)::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare c record;r jsonb;f date:=(clock_timestamp() at time zone 'America/Lima')::date;
begin
  select * into c from casos_todos where nombre='borrador_antiguo';
  r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO BORRADOR ANTERIOR');
  c.persona:=(r->>'inversionista_id')::uuid;
  c.datos:=jsonb_build_object('inversionista_id',c.persona,'lead_id',c.id,'empresa','qorilazo','monto',1000,'moneda','PEN',
    'fecha_comercial',f,'vence_en',current_setting('banco.vence_todos')::date,'plazo_meses',12,'tasa_anual',12,
    'numero_transaccion','TODOS-'||c.solicitud,'referencia','BORRADOR PREVIO',
    'evidencia',jsonb_build_object('ruta',c.persona||'/'||c.solicitud||'/comprobante.pdf'));
  perform crm.preparar_inversion_fn(c.solicitud,c.datos);
  update casos_todos set persona=c.persona,datos=c.datos where id=c.id;
  select * into c from casos_todos where nombre='valido_antes';
  r:=crm.recorrido_atender_oficina_fn(gen_random_uuid(),c.id,'interesado','Hechos registrados antes de activar',null,1000,'PEN');
  update casos_todos set tarea=(r->>'tarea_id')::uuid,actividad=(r->>'actividad_id')::uuid where id=c.id;
end $$;
reset role;
insert into storage.objects(bucket_id,name,metadata)
 select 'f4-comprobantes',datos#>>'{evidencia,ruta}','{"size":12,"mimetype":"application/pdf"}'::jsonb
 from casos_todos where nombre='borrador_antiguo';
set local role authenticated;
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
reset role;
select set_config('banco.revision_todos',(select revision::text from crm.recorrido_control where id),true);
set local role authenticated;
select crm.recorrido_configurar_fn('exigir','Exigencia de todas las primeras conversiones pendientes',current_setting('banco.revision_todos')::integer);
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.exigir((select bool_and((r->>'exigible')::boolean and
 (r->>'ciclo_inicio')::timestamptz<(respuesta->>'cohorte_desde')::timestamptz)
 from (select crm.recorrido_leads_fn(array(select id from casos_todos)) respuesta) q,
 jsonb_array_elements(respuesta->'filas') r),'los tres ciclos anteriores están incluidos en la exigencia');
select pg_temp.exigir((crm.recorrido_leads_fn(array[(select id from casos_todos where nombre='valido_antes')])#>>'{filas,0,habilita_conversion}')::boolean,
 'la entrevista anterior a activar es válida si su evidencia del ciclo ya existe');
select pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO ANTIGUO SIN HECHOS'')',id,documento),
 'P0409','Antes de convertir') from casos_todos where nombre='sin_persona_antiguo';
select pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',solicitud),'P0409','Antes de convertir')
 from casos_todos where nombre='borrador_antiguo';
do $$
declare c record;r jsonb;
begin
  select * into c from casos_todos where nombre='borrador_antiguo';
  r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'NO CAMBIAR AL RETOMAR');
  perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'retoma conserva la solicitud anterior');
  r:=crm.preparar_inversion_fn(c.solicitud,c.datos);
  perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'mismo borrador sigue recuperable');
end $$;
reset role;
select pg_temp.exigir((select s.estado='preparada' and s.inversion_id is null and s.datos=c.datos and s.recorrido_confirmado is null
 from crm.inversion_solicitudes s join casos_todos c on c.solicitud=s.id where c.nombre='borrador_antiguo'),
 'rechazo de la primera conversión anterior conserva capital, comprobante y estado');
-- El writer interno tampoco evita la comprobación por usar la tabla directamente.
select set_config('request.jwt.claim.sub','',true);
select pg_temp.rechaza(format('update crm.inversion_solicitudes set estado=''confirmada'' where id=%L',solicitud),
 'P0409','Antes de convertir') from casos_todos where nombre='borrador_antiguo';
do $$begin raise notice 'PASS: antiguos y borrador anterior bloqueados por RPC y tabla; sin pérdida del borrador';end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare c record;r jsonb;confirmado jsonb;
begin
  select * into c from casos_todos where nombre='borrador_antiguo';
  r:=crm.recorrido_atender_oficina_fn(gen_random_uuid(),c.id,'interesado','Atención real del banco después del rechazo',null,1000,'PEN');
  update casos_todos set tarea=(r->>'tarea_id')::uuid,actividad=(r->>'actividad_id')::uuid where id=c.id;
  confirmado:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
  r:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
  perform pg_temp.exigir((r->>'reintento')::boolean and r->>'inversion_id'=confirmado->>'inversion_id',
    'completar los hechos permite confirmar y el reintento no duplica');
end $$;
reset role;
select pg_temp.exigir((select (s.recorrido_confirmado->>'exigible')::boolean
 and s.recorrido_confirmado->>'alcance'='primeras_conversiones_pendientes'
 and s.recorrido_confirmado->>'asistencia_id'=c.actividad::text
 and s.recorrido_confirmado->>'entrevista_tarea_id'=c.tarea::text
 from crm.inversion_solicitudes s join casos_todos c on c.solicitud=s.id where c.nombre='borrador_antiguo'),
 'snapshot registra la misma cita y el alcance para el lead anterior');
-- El caso de ciclo corrupto requiere superuser y se acredita en el banco local.
rollback;

-- Inicio programado: la fecha regula CUÁNDO se exige, no QUÉ leads se incluyen.
begin;
set local statement_timeout='20s';
create temporary table casos_fecha(id uuid default gen_random_uuid(),documento text);
grant select on casos_fecha to authenticated;
insert into casos_fecha(documento) values('98648010');
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
 select id,'BANCO FECHA FUTURA','986489999','oficina',1000,
 'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002' from casos_fecha;
select set_config('banco.revision_todos',(select revision::text from crm.recorrido_control where id),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
select crm.recorrido_configurar_fn('exigir','Inicio programado de la exigencia para todos',current_setting('banco.revision_todos')::integer,
 clock_timestamp()+interval '2 seconds');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$begin
  if (crm.recorrido_leads_fn(array(select id from casos_fecha))#>>'{filas,0,exigible}')::boolean is distinct from false then
    raise exception 'La guía no debe exigir antes de la fecha programada';end if;
end $$;
reset role;
do $$declare r jsonb;begin
 select private.recorrido_exigir(id,'prueba_fecha_antes') into r from casos_fecha;
 if (r->>'exigible')::boolean is distinct from false then raise exception 'El servidor exige antes de lo programado';end if;
end $$;
select pg_sleep(2.1);
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$declare c record;begin
  if (crm.recorrido_leads_fn(array(select id from casos_fecha))#>>'{filas,0,exigible}')::boolean is distinct from true then
    raise exception 'La guía debe exigir al alcanzar la fecha incluso al antiguo';end if;
  select * into c from casos_fecha;
  begin
    perform crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO FECHA FUTURA');
  exception when sqlstate 'P0409' then
    if position('Antes de convertir' in sqlerrm)>0 then
      raise notice 'PASS: inicio futuro coherente en guía y servidor; antiguo incluido al llegar la fecha';return;
    end if;
    raise;
  end;
  raise exception 'La fecha de creación no debe eximir al lead al iniciar el bloqueo';
end $$;
rollback;
