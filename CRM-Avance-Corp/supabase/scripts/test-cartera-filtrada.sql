-- Banco desechable: fixtures deterministas, permisos reales y ROLLBACK total.
begin;
set local session_replication_role = replica;
insert into public.perfiles(id,nombre_completo,rol,activo)
select ('f1981000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'ORACULO FILTRO '||n,case when n=7 then 'cliente' else 'comercial' end,true
from generate_series(1,7) n;
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select ('f1981000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n in (1,2) then 'supervisor' else 'vendedor' end,
  case when n in(3,4) then 'f1981000-0000-4000-8000-000000000001'::uuid
    when n in(5,6) then 'f1981000-0000-4000-8000-000000000002'::uuid end,n<>6
from generate_series(1,6) n;
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,
  moneda,vendedor_id,asignado_supervisor_id,creado_por,creado_en,actualizado_en,convertido_en,motivo_descarte,activo)
select ('f1982000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'FILTRO LEAD '||lpad(n::text,3,'0'),'5199811'||lpad(n::text,4,'0'),'otro',
  case when n=71 then 'convertido' when n=72 then 'descartado'
    when n<=60 and n%2=0 then 'contactado' else 'nuevo' end,
  1000,case when n=70 then 'USD' else 'PEN' end,
  case when n=67 then null when n between 61 and 65 then 'f1981000-0000-4000-8000-000000000004'::uuid
    when n=66 then 'f1981000-0000-4000-8000-000000000005'::uuid
    else 'f1981000-0000-4000-8000-000000000003'::uuid end,
  case when n=67 then 'f1981000-0000-4000-8000-000000000001'::uuid end,
  'f1981000-0000-4000-8000-000000000003',now()-interval '100 days',
  now(),case when n=71 then now()-interval '60 days' end,
  case when n=72 then 'sin_interes' end,n<>73
from generate_series(1,74) n;
insert into crm.lead_asignaciones(lead_id,ciclo_n,episodio_n,analista_id,
  motivo_apertura,asignado_en,sla_global_iniciado_en,sla_politica_asignacion_id,
  primera_gestion_limite_en,primer_contacto_limite_en,moneda,origen,
  finalizado_en,motivo_cierre,aproximado)
select l.id,1,1,l.vendedor_id,'asignado',t.sello,t.sello,
  'f1983000-0000-4000-8000-000000000001',t.sello+interval '1 hour',t.sello+interval '2 hours',
  l.moneda,'oraculo_filtro',t.sello+interval '1 second','desactivado',n=74
from generate_series(1,74) n
join crm.leads l on l.id=('f1982000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
cross join lateral (select (((now() at time zone 'America/Lima')::date-1)::timestamp at time zone 'America/Lima')
  + case when n=68 then -interval '1 microsecond' when n=69 then interval '1 day'
    when n=70 then interval '1 day'-interval '1 microsecond'
    when n=71 then -interval '90 days' else interval '0 seconds' end as sello) t
where n<>67;
-- Dos episodios del mismo lead dentro del rango: una sola fila y un solo total.
insert into crm.lead_asignaciones(lead_id,ciclo_n,episodio_n,analista_id,motivo_apertura,
  asignado_en,sla_global_iniciado_en,sla_politica_asignacion_id,primera_gestion_limite_en,
  primer_contacto_limite_en,moneda,origen)
select lead_id,1,2,analista_id,'reasignado',asignado_en+interval '2 seconds',
  asignado_en,sla_politica_asignacion_id,primera_gestion_limite_en,primer_contacto_limite_en,moneda,origen
from crm.lead_asignaciones where lead_id='f1982000-0000-4000-8000-000000000074';
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','f1981000-0000-4000-8000-000000000003',true);
do $test$
declare
  d date:=(now() at time zone 'America/Lima')::date-1;
  r jsonb; p jsonb; ids uuid[]:='{}'; fila jsonb; cursor_fecha timestamptz; cursor_id uuid;
begin
  r:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_limite=>51);
  assert (r#>>'{resumen,totales,vivos}')::int=63,'Analista: 60 + último microsegundo + descartado + deduplicado';
  assert jsonb_array_length(r->'items')=51,'El total no debe limitarse a la página';
  assert (r#>>'{resumen,capital,asignado,usd}')::numeric=1000,'USD separado';
  assert (r#>>'{resumen,capital,asignado,pen}')::numeric=61000,'Capital excluye descartado';
  p:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_texto=>'FILTRO LEAD 074');
  assert (p#>>'{items,0,recepcion_aproximada}')::boolean=false,'La aproximación pertenece a la fecha elegida';
  loop
    p:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_limite=>17,p_antes_de=>cursor_fecha,p_antes_id=>cursor_id);
    assert (p#>>'{resumen,totales,vivos}')::int=63,'Total estable entre páginas';
    exit when jsonb_array_length(p->'items')=0;
    for fila in select value from jsonb_array_elements(p->'items') loop
      assert not (fila->>'id')::uuid=any(ids),'Keyset sin duplicados';
      ids:=array_append(ids,(fila->>'id')::uuid);
      cursor_fecha:=(fila->>'actualizado_en')::timestamptz; cursor_id:=(fila->>'id')::uuid;
    end loop;
  end loop;
  assert cardinality(ids)=63,'Keyset sin pérdidas con sellos empatados';
  r:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_etapa=>'contactado');
  assert (r#>>'{resumen,totales,vivos}')::int=30 and jsonb_array_length(r->'items')=30,'Etapas conectadas';
  r:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_texto=>'FILTRO LEAD 059');
  assert (r#>>'{resumen,totales,vivos}')::int=1,'Búsqueda alcanza otra página';
  r:=crm.cartera_filtrada_fn(p_desde=>d-100,p_hasta=>d,p_etapa=>'convertido');
  assert (r#>>'{resumen,totales,vivos}')::int=1,'Convertido antiguo recibido en rango';
  r:=crm.cartera_filtrada_fn(p_etapa=>'convertido');
  assert (r#>>'{resumen,totales,vivos}')::int=0,'Sin fecha mantiene ventana operativa';
  r:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_vendedor_id=>'f1981000-0000-4000-8000-000000000005');
  assert (r#>>'{resumen,totales,vivos}')::int=0,'No filtra hacia equipo ajeno';
  r:=crm.cartera_filtrada_fn(p_desde=>d-20,p_hasta=>d-20);
  assert (r#>>'{resumen,totales,vivos}')::int=0 and r->'items'='[]'::jsonb,'Vacío honesto';
  begin perform crm.cartera_filtrada_fn(p_desde=>d); raise exception 'Aceptó rango incompleto'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_desde=>d+2,p_hasta=>d+2); raise exception 'Aceptó futuro'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_sin_asignar=>true); raise exception 'Aceptó pendientes con recepción'; exception when sqlstate '22023' then null; end;
end;
$test$;
select set_config('request.jwt.claim.sub','f1981000-0000-4000-8000-000000000001',true);
do $test$
declare d date:=(now() at time zone 'America/Lima')::date-1; r jsonb;
begin
  r:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d);
  assert (r#>>'{resumen,totales,vivos}')::int=68,'Supervisor: sus dos analistas, sin bandeja ni otro equipo';
  r:=crm.cartera_filtrada_fn(p_desde=>d,p_hasta=>d,p_vendedor_id=>'f1981000-0000-4000-8000-000000000004');
  assert (r#>>'{resumen,totales,vivos}')::int=5,'Supervisor puede acotar por analista';
end;
$test$;
select set_config('request.jwt.claim.sub','f1981000-0000-4000-8000-000000000006',true);
do $$ begin
  begin perform crm.cartera_filtrada_fn(); raise exception 'Aceptó miembro revocado'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f1981000-0000-4000-8000-000000000007',true);
do $$ begin
  begin perform crm.cartera_filtrada_fn(); raise exception 'Aceptó portal-only'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert not has_function_privilege('anon','crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)','EXECUTE'),'Anon denegado';
  assert not has_function_privilege('service_role','crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)','EXECUTE'),'Service role denegado';
  assert not (select prosecdef from pg_proc where oid='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)'::regprocedure),'RPC conserva RLS invoker';
end $$;
rollback;
select 'CARTERA_FILTRADA_RLS_OK';
