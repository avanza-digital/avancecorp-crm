-- Oráculo del filtro de ORIGEN en Leads (RPC crm.cartera_filtrada_fn, 10 args).
-- Banco desechable: fixtures deterministas, permisos reales y ROLLBACK total.
-- Prefijo f199… propio para no chocar con los fixtures del filtro del 13/09.
begin;
set local session_replication_role = replica;
insert into public.perfiles(id,nombre_completo,rol,activo)
select ('f1991000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'ORACULO ORIGEN '||n,case when n=7 then 'cliente' else 'comercial' end,true
from generate_series(1,8) n;
-- 1,2 supervisores · 3,4 analistas de 1 · 5 analista de 2 · 6 revocado · 8 gerencia.
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select ('f1991000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n in (1,2) then 'supervisor' when n=8 then 'gerencia' else 'vendedor' end,
  case when n in(3,4) then 'f1991000-0000-4000-8000-000000000001'::uuid
    when n in(5,6) then 'f1991000-0000-4000-8000-000000000002'::uuid end,n<>6
from generate_series(1,8) n where n<>7;
-- 40 leads: 1..30 del analista 3 (los 8 orígenes), 31..35 del analista 4,
-- 36..38 del analista 5 (otro equipo), 39 en bandeja del supervisor 1, 40 borrado.
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,
  moneda,vendedor_id,asignado_supervisor_id,creado_por,creado_en,actualizado_en,convertido_en,motivo_descarte,activo)
select ('f1992000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'ORIGEN LEAD '||lpad(n::text,3,'0'),'5199911'||lpad(n::text,4,'0'),
  case when n<=10 then 'landing' when n<=18 then 'formulario' when n<=22 then 'referido'
    when n<=25 then 'oficina' when n<=27 then 'otro' when n=28 then 'web'
    when n=29 then 'campania' when n=30 then 'whatsapp' else 'landing' end,
  case when n=7 then 'convertido' when n=6 then 'descartado'
    when n in (5,12) then 'contactado' else 'nuevo' end,
  1000,case when n=8 then 'USD' else 'PEN' end,
  case when n=39 or n=40 and false then null
    when n<=30 or n=40 then 'f1991000-0000-4000-8000-000000000003'::uuid
    when n<=35 then 'f1991000-0000-4000-8000-000000000004'::uuid
    when n<=38 then 'f1991000-0000-4000-8000-000000000005'::uuid end,
  case when n=39 then 'f1991000-0000-4000-8000-000000000001'::uuid end,
  'f1991000-0000-4000-8000-000000000003',now()-interval '100 days',
  -- Empates de sello con orígenes intercalados (1,2,3 landing y 11 formulario):
  -- el keyset desempata por id y el origen no puede romper eso.
  case when n in (1,2,3,11) then now()-interval '1 minute' else now()-(n||' minutes')::interval end,
  case when n=7 then now()-interval '10 days' end,
  case when n=6 then 'sin_interes' end,n<>40
from generate_series(1,40) n;
-- Recepción: 1..20 y 31..38 ayer; 21..30 hace tres días. Sin bandeja ni borrado.
insert into crm.lead_asignaciones(lead_id,ciclo_n,episodio_n,analista_id,
  motivo_apertura,asignado_en,sla_global_iniciado_en,sla_politica_asignacion_id,
  primera_gestion_limite_en,primer_contacto_limite_en,moneda,origen,
  finalizado_en,motivo_cierre,aproximado)
select l.id,1,1,l.vendedor_id,'asignado',t.sello,t.sello,
  'f1993000-0000-4000-8000-000000000001',t.sello+interval '1 hour',t.sello+interval '2 hours',
  l.moneda,'oraculo_origen',t.sello+interval '1 second','desactivado',false
from generate_series(1,38) n
join crm.leads l on l.id=('f1992000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
cross join lateral (select (((now() at time zone 'America/Lima')::date-1)::timestamp at time zone 'America/Lima')
  - case when n between 21 and 30 then interval '2 days' else interval '0 seconds' end
  + interval '12 hours' as sello) t;
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','f1991000-0000-4000-8000-000000000003',true);
do $test$
declare
  d date:=(now() at time zone 'America/Lima')::date-1;
  r jsonb; p jsonb; ids uuid[]:='{}'; fila jsonb; cursor_fecha timestamptz; cursor_id uuid;
  o record;
begin
  r:=crm.cartera_filtrada_fn();
  assert (r#>>'{resumen,totales,vivos}')::int=30,'Analista sin filtro: sus 30 leads vivos';
  assert r->'origen'='null'::jsonb,'Sin filtro el payload devuelve origen nulo';

  r:=crm.cartera_filtrada_fn(p_origen=>'landing');
  assert r->>'origen'='landing','El payload devuelve el origen filtrado';
  assert (r#>>'{resumen,totales,vivos}')::int=10,'Landing: 10 leads';
  assert jsonb_array_length(r->'items')=10,'Landing: 10 filas';
  assert not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'origen'<>'landing'),'Todas las filas son landing';
  assert (r#>>'{resumen,totales,abiertos}')::int=8 and (r#>>'{resumen,totales,convertidos}')::int=1
    and (r#>>'{resumen,totales,descartados}')::int=1,'Totales de la misma base filtrada';
  assert (r#>>'{resumen,totales,asignados_usd}')::int=1 and (r#>>'{resumen,totales,asignados_pen}')::int=7,'Monedas separadas';
  assert (r#>>'{resumen,capital,asignado,pen}')::numeric=7000 and (r#>>'{resumen,capital,asignado,usd}')::numeric=1000,'Capital solo de landing y solo en juego';
  assert (r#>>'{resumen,capital,ganado,pen}')::numeric=1000,'Ganado de landing';
  assert (select sum((e->>'n')::int) from jsonb_array_elements(r->'embudo') e)=10
    or (select sum((e->>'n')::int) from jsonb_array_elements(r#>'{resumen,embudo}') e)=10,'Embudo suma el total filtrado';
  assert (select (e->>'n')::int from jsonb_array_elements(r#>'{resumen,embudo}') e where e->>'etapa'='contactado')=1,'Embudo por etapa dentro del origen';

  -- Cada origen suma su parte y entre todos reconstruyen la cartera.
  for o in select * from (values ('landing',10),('formulario',8),('referido',4),('oficina',3),
      ('otro',2),('web',1),('campania',1),('whatsapp',1)) v(k,n) loop
    r:=crm.cartera_filtrada_fn(p_origen=>o.k);
    assert (r#>>'{resumen,totales,vivos}')::int=o.n,'Origen '||o.k||' esperaba '||o.n||' y dio '||(r#>>'{resumen,totales,vivos}');
    assert jsonb_array_length(r->'items')=o.n,'Filas de '||o.k;
  end loop;

  -- Combinado con etapa, búsqueda y recepción: la MISMA base para todo.
  r:=crm.cartera_filtrada_fn(p_origen=>'landing',p_etapa=>'contactado');
  assert (r#>>'{resumen,totales,vivos}')::int=1 and r#>>'{items,0,nombre_completo}'='ORIGEN LEAD 005','Origen + etapa';
  r:=crm.cartera_filtrada_fn(p_origen=>'landing',p_texto=>'ORIGEN LEAD 007');
  assert (r#>>'{resumen,totales,vivos}')::int=1 and r#>>'{items,0,etapa}'='convertido','Origen + búsqueda';
  r:=crm.cartera_filtrada_fn(p_origen=>'formulario',p_texto=>'ORIGEN LEAD 007');
  assert (r#>>'{resumen,totales,vivos}')::int=0 and r->'items'='[]'::jsonb
    and (r#>>'{resumen,capital,asignado,pen}')::numeric=0,'Vacío honesto: el lead existe pero no en ese origen';
  r:=crm.cartera_filtrada_fn(p_origen=>'landing',p_desde=>d,p_hasta=>d);
  assert (r#>>'{resumen,totales,vivos}')::int=10 and r->>'desde'=d::text and r->>'origen'='landing','Origen + recepción de ayer';
  r:=crm.cartera_filtrada_fn(p_origen=>'referido',p_desde=>d,p_hasta=>d);
  assert (r#>>'{resumen,totales,vivos}')::int=2,'Referidos recibidos ayer: 2 de 4';
  r:=crm.cartera_filtrada_fn(p_origen=>'referido',p_desde=>d-2,p_hasta=>d-2);
  assert (r#>>'{resumen,totales,vivos}')::int=2,'Referidos recibidos hace tres días: los otros 2';

  -- Paginación por cursor con el origen puesto: total estable, sin duplicados ni pérdidas.
  loop
    p:=crm.cartera_filtrada_fn(p_origen=>'landing',p_limite=>4,p_antes_de=>cursor_fecha,p_antes_id=>cursor_id);
    assert (p#>>'{resumen,totales,vivos}')::int=10,'Total estable entre páginas con origen';
    exit when jsonb_array_length(p->'items')=0;
    for fila in select value from jsonb_array_elements(p->'items') loop
      assert fila->>'origen'='landing','Ninguna página se sale del origen';
      assert not (fila->>'id')::uuid=any(ids),'Keyset sin duplicados';
      ids:=array_append(ids,(fila->>'id')::uuid);
      cursor_fecha:=(fila->>'actualizado_en')::timestamptz; cursor_id:=(fila->>'id')::uuid;
    end loop;
  end loop;
  assert cardinality(ids)=10,'Keyset sin pérdidas con origen';

  -- Valores fuera del dominio: rechazados, no «cero resultados» silenciosos.
  begin perform crm.cartera_filtrada_fn(p_origen=>'facebook'); raise exception 'Aceptó origen inexistente'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_origen=>''); raise exception 'Aceptó origen vacío'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_origen=>'LANDING'); raise exception 'Aceptó origen en mayúsculas'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_origen=>'landing',p_desde=>d); raise exception 'Aceptó rango incompleto'; exception when sqlstate '22023' then null; end;
end;
$test$;

select set_config('request.jwt.claim.sub','f1991000-0000-4000-8000-000000000001',true);
do $test$
declare r jsonb; v_bandeja int;
begin
  -- La bandeja (lead sin analista) se mide con el filtro vigente de pendientes:
  -- el origen tiene que componer con él y con el ámbito, no redefinirlos.
  r:=crm.cartera_filtrada_fn(p_origen=>'landing',p_sin_asignar=>true);
  v_bandeja:=(r#>>'{resumen,totales,vivos}')::int;
  assert v_bandeja in (0,1),'Pendientes de repartir con origen: a lo sumo la bandeja';
  r:=crm.cartera_filtrada_fn(p_origen=>'formulario',p_sin_asignar=>true);
  assert (r#>>'{resumen,totales,vivos}')::int=0,'La bandeja no tiene leads de formulario';
  r:=crm.cartera_filtrada_fn(p_origen=>'landing');
  assert (r#>>'{resumen,totales,vivos}')::int=15+v_bandeja,'Supervisor: landing de sus dos analistas más la bandeja que su ámbito le muestre';
  r:=crm.cartera_filtrada_fn(p_origen=>'landing',p_vendedor_id=>'f1991000-0000-4000-8000-000000000004');
  assert (r#>>'{resumen,totales,vivos}')::int=5,'Supervisor acota origen por analista';
  r:=crm.cartera_filtrada_fn(p_origen=>'landing',p_desde=>(now() at time zone 'America/Lima')::date-1,p_hasta=>(now() at time zone 'America/Lima')::date-1);
  assert (r#>>'{resumen,totales,vivos}')::int=15,'Supervisor: recepción de su equipo, sin bandeja';
  r:=crm.cartera_filtrada_fn(p_origen=>'landing',p_vendedor_id=>'f1991000-0000-4000-8000-000000000005');
  assert (r#>>'{resumen,totales,vivos}')::int=0,'No filtra hacia equipo ajeno';
end;
$test$;
select set_config('request.jwt.claim.sub','f1991000-0000-4000-8000-000000000005',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn(p_origen=>'landing');
  assert (r#>>'{resumen,totales,vivos}')::int=3,'Analista del otro equipo: solo lo suyo';
  r:=crm.cartera_filtrada_fn(p_origen=>'formulario');
  assert (r#>>'{resumen,totales,vivos}')::int=0,'Analista del otro equipo: nada de formulario';
end;
$test$;
select set_config('request.jwt.claim.sub','f1991000-0000-4000-8000-000000000008',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn(p_origen=>'landing');
  assert (r#>>'{resumen,totales,vivos}')::int>=19,'Gerencia: los landing de toda la empresa (incluye la bandeja)';
  assert exists(select 1 from jsonb_array_elements(r->'items') i where i->>'nombre_completo'='ORIGEN LEAD 039'),'Gerencia ve la bandeja';
end;
$test$;
select set_config('request.jwt.claim.sub','f1991000-0000-4000-8000-000000000006',true);
do $$ begin
  begin perform crm.cartera_filtrada_fn(p_origen=>'landing'); raise exception 'Aceptó miembro revocado'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f1991000-0000-4000-8000-000000000007',true);
do $$ begin
  begin perform crm.cartera_filtrada_fn(); raise exception 'Aceptó portal-only'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ declare f text:='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)'; begin
  assert to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)') is null,'La firma de 9 argumentos ya no existe';
  assert (select count(*) from pg_proc where proname='cartera_filtrada_fn' and pronamespace='crm'::regnamespace)=1,'Una sola firma para PostgREST';
  assert not has_function_privilege('anon',f,'EXECUTE'),'Anon denegado';
  assert not has_function_privilege('service_role',f,'EXECUTE'),'Service role denegado';
  assert has_function_privilege('authenticated',f,'EXECUTE'),'Authenticated permitido';
  assert not (select prosecdef from pg_proc where oid=to_regprocedure(f)),'RPC conserva RLS invoker';
end $$;
rollback;
select 'CARTERA_ORIGEN_OK';
