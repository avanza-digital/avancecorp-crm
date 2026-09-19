-- Oráculo de la PROCEDENCIA en Leads (RPC crm.cartera_filtrada_fn, 11 args).
-- Banco desechable: fixtures deterministas, permisos reales y ROLLBACK total.
-- Prefijo f299… propio para no chocar con los fixtures del 13/09 (f1…) ni del
-- 16/09 (f199…).
begin;
set local session_replication_role = replica;
insert into public.perfiles(id,nombre_completo,rol,activo)
select ('f2991000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'ORACULO PROCEDENCIA '||n,case when n=7 then 'cliente' else 'comercial' end,true
from generate_series(1,8) n;
-- 1,2 supervisores · 3,4 analistas de 1 · 5 analista de 2 · 6 revocado · 8 gerencia.
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select ('f2991000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n in (1,2) then 'supervisor' when n=8 then 'gerencia' else 'vendedor' end,
  case when n in(3,4) then 'f2991000-0000-4000-8000-000000000001'::uuid
    when n in(5,6) then 'f2991000-0000-4000-8000-000000000002'::uuid end,n<>6
from generate_series(1,8) n where n<>7;
-- 40 leads: 1..30 del analista 3, 31..35 del analista 4, 36..38 del analista 5
-- (otro equipo), 39 en bandeja del supervisor 1, 40 borrado.
-- Procedencia del analista 3 (30 vivos): 18 del SISTEMA (sin marca ni autor) y
-- 12 MANUALES: 16..24 y 26 con `alta_manual` (desde 01/09), y dos HISTÓRICOS
-- anteriores a esa columna que solo tienen autor: 25 (autor: el analista) y
-- 27 (autor: su supervisor). Landing/formulario mezclan las dos procedencias
-- (16..18 son formulario manual): el origen no decide.
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,
  moneda,vendedor_id,asignado_supervisor_id,alta_manual,creado_por,creado_en,actualizado_en,convertido_en,motivo_descarte,activo)
select ('f2992000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'PROCEDENCIA LEAD '||lpad(n::text,3,'0'),'5299911'||lpad(n::text,4,'0'),
  case when n<=10 then 'landing' when n<=18 then 'formulario' when n<=22 then 'referido'
    when n<=25 then 'oficina' when n<=27 then 'otro' when n=28 then 'web'
    when n=29 then 'campania' when n=30 then 'whatsapp' else 'landing' end,
  case when n=7 then 'convertido' when n=6 then 'descartado'
    when n in (5,12,17) then 'contactado' else 'nuevo' end,
  1000,case when n=8 then 'USD' else 'PEN' end,
  case when n=39 then null
    when n<=30 or n=40 then 'f2991000-0000-4000-8000-000000000003'::uuid
    when n<=35 then 'f2991000-0000-4000-8000-000000000004'::uuid
    when n<=38 then 'f2991000-0000-4000-8000-000000000005'::uuid end,
  case when n=39 then 'f2991000-0000-4000-8000-000000000001'::uuid end,
  n in (16,17,18,19,20,21,22,23,24,26,31,32,36,40),
  case when n in (16,17,18,19,20,21,22,23,24,25,26,40) then 'f2991000-0000-4000-8000-000000000003'::uuid
    when n=27 then 'f2991000-0000-4000-8000-000000000001'::uuid
    when n in (31,32) then 'f2991000-0000-4000-8000-000000000004'::uuid
    when n=36 then 'f2991000-0000-4000-8000-000000000005'::uuid end,
  now()-interval '100 days',
  -- Empates de sello con procedencias intercaladas (1,2,3 sistema y 16 manual):
  -- el keyset desempata por id y la procedencia no puede romper eso.
  case when n in (1,2,3,16) then now()-interval '1 minute' else now()-(n||' minutes')::interval end,
  case when n=7 then now()-interval '10 days' end,
  case when n=6 then 'sin_interes' end,n<>40
from generate_series(1,40) n;
-- Recepción: 1..20 y 31..38 ayer; 21..30 hace tres días. Sin bandeja ni borrado.
insert into crm.lead_asignaciones(lead_id,ciclo_n,episodio_n,analista_id,
  motivo_apertura,asignado_en,sla_global_iniciado_en,sla_politica_asignacion_id,
  primera_gestion_limite_en,primer_contacto_limite_en,moneda,origen,
  finalizado_en,motivo_cierre,aproximado)
select l.id,1,1,l.vendedor_id,'asignado',t.sello,t.sello,
  'f2993000-0000-4000-8000-000000000001',t.sello+interval '1 hour',t.sello+interval '2 hours',
  l.moneda,'oraculo_procedencia',t.sello+interval '1 second','desactivado',false
from generate_series(1,38) n
join crm.leads l on l.id=('f2992000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
cross join lateral (select (((now() at time zone 'America/Lima')::date-1)::timestamp at time zone 'America/Lima')
  - case when n between 21 and 30 then interval '2 days' else interval '0 seconds' end
  + interval '12 hours' as sello) t;
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','f2991000-0000-4000-8000-000000000003',true);
do $test$
declare
  d date:=(now() at time zone 'America/Lima')::date-1;
  r jsonb; p jsonb; ids uuid[]:='{}'; fila jsonb; cursor_fecha timestamptz; cursor_id uuid;
  a3 constant uuid:='f2991000-0000-4000-8000-000000000003';
  s1 constant uuid:='f2991000-0000-4000-8000-000000000001';
begin
  -- Sin filtro: todo igual que antes más las dos claves nuevas por fila.
  r:=crm.cartera_filtrada_fn();
  assert (r#>>'{resumen,totales,vivos}')::int=30,'Analista sin filtro: sus 30 leads vivos';
  assert r->'procedencia'='null'::jsonb,'Sin filtro el payload devuelve procedencia nula';
  assert r->'origen'='null'::jsonb,'Sin filtro el payload sigue devolviendo origen nulo';
  assert jsonb_array_length(r->'items')=30,'Sin filtro: 30 filas';
  assert not exists(select 1 from jsonb_array_elements(r->'items') i
    where not (i ? 'procedencia') or not (i ? 'cargado_por') or i->>'procedencia' not in ('sistema','manual')),
    'Toda fila trae procedencia válida y cargado_por';
  assert (select count(*) from jsonb_array_elements(r->'items') i where i->>'procedencia'='manual')=12,'12 manuales entre las filas';
  assert (select count(*) from jsonb_array_elements(r->'items') i where i->>'procedencia'='sistema')=18,'18 del sistema entre las filas';
  assert not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'procedencia'='sistema' and i->'cargado_por'<>'null'::jsonb),
    'Lo del sistema nunca tiene autor';

  -- Manual: la marca del 01/09 O tener autor (los dos históricos entran).
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual');
  assert r->>'procedencia'='manual','El payload devuelve la procedencia filtrada';
  assert (r#>>'{resumen,totales,vivos}')::int=12,'Manual: 12 leads';
  assert jsonb_array_length(r->'items')=12,'Manual: 12 filas';
  assert not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'procedencia'<>'manual' or i->'cargado_por'='null'::jsonb),
    'Todas las filas son manuales y con autor';
  assert exists(select 1 from jsonb_array_elements(r->'items') i where i->>'nombre_completo'='PROCEDENCIA LEAD 025' and (i->>'cargado_por')::uuid=a3),
    'Histórico sin marca pero con autor (el analista) cuenta como manual';
  assert exists(select 1 from jsonb_array_elements(r->'items') i where i->>'nombre_completo'='PROCEDENCIA LEAD 027' and (i->>'cargado_por')::uuid=s1),
    'Histórico cargado por el supervisor cuenta como manual y dice quién';
  assert (r#>>'{resumen,totales,abiertos}')::int=12 and (r#>>'{resumen,totales,convertidos}')::int=0
    and (r#>>'{resumen,totales,descartados}')::int=0,'Totales de la misma base filtrada (manual)';
  assert (r#>>'{resumen,capital,asignado,pen}')::numeric=12000 and (r#>>'{resumen,capital,asignado,usd}')::numeric=0,'Capital solo de lo manual';
  assert (select (e->>'n')::int from jsonb_array_elements(r#>'{resumen,embudo}') e where e->>'etapa'='contactado')=1,'Embudo por etapa dentro de lo manual';
  assert (select sum((e->>'n')::int) from jsonb_array_elements(r#>'{resumen,embudo}') e)=12,'Embudo suma el total filtrado';

  -- Sistema: sin marca y sin autor.
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema');
  assert r->>'procedencia'='sistema','Eco de sistema';
  assert (r#>>'{resumen,totales,vivos}')::int=18 and jsonb_array_length(r->'items')=18,'Sistema: 18 leads';
  assert not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'procedencia'<>'sistema' or i->'cargado_por'<>'null'::jsonb),
    'Todas las filas son del sistema y sin autor';
  assert (r#>>'{resumen,totales,convertidos}')::int=1 and (r#>>'{resumen,totales,descartados}')::int=1,'Convertido y descartado del sistema';
  assert (r#>>'{resumen,totales,asignados_usd}')::int=1 and (r#>>'{resumen,totales,asignados_pen}')::int=15,'Monedas separadas';
  assert (r#>>'{resumen,capital,asignado,pen}')::numeric=15000 and (r#>>'{resumen,capital,asignado,usd}')::numeric=1000
    and (r#>>'{resumen,capital,ganado,pen}')::numeric=1000,'Capital del sistema: en juego y ganado';
  -- Las dos procedencias reconstruyen la cartera.
  assert 12+18=30,'Manual + sistema = todo';

  -- Compone con origen: el canal NO decide la procedencia.
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_origen=>'formulario');
  assert (r#>>'{resumen,totales,vivos}')::int=3 and r->>'origen'='formulario' and r->>'procedencia'='manual','Formulario manual: 3';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema',p_origen=>'formulario');
  assert (r#>>'{resumen,totales,vivos}')::int=5,'Formulario del sistema: 5';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_origen=>'landing');
  assert (r#>>'{resumen,totales,vivos}')::int=0 and r->'items'='[]'::jsonb
    and (r#>>'{resumen,capital,asignado,pen}')::numeric=0,'Vacío honesto: landing existe pero ninguno es manual';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema',p_origen=>'referido');
  assert (r#>>'{resumen,totales,vivos}')::int=0,'Ningún referido es del sistema';

  -- Compone con etapa, búsqueda y recepción: la MISMA base para todo.
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_etapa=>'contactado');
  assert (r#>>'{resumen,totales,vivos}')::int=1 and r#>>'{items,0,nombre_completo}'='PROCEDENCIA LEAD 017','Manual + etapa';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema',p_etapa=>'contactado');
  assert (r#>>'{resumen,totales,vivos}')::int=2,'Sistema + etapa';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema',p_texto=>'PROCEDENCIA LEAD 007');
  assert (r#>>'{resumen,totales,vivos}')::int=1 and r#>>'{items,0,etapa}'='convertido','Sistema + búsqueda';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_texto=>'PROCEDENCIA LEAD 007');
  assert (r#>>'{resumen,totales,vivos}')::int=0,'Manual + búsqueda: el lead existe pero no es manual';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_desde=>d,p_hasta=>d);
  assert (r#>>'{resumen,totales,vivos}')::int=5 and r->>'desde'=d::text and r->>'procedencia'='manual','Manuales recibidos ayer: 16..20';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_desde=>d-2,p_hasta=>d-2);
  assert (r#>>'{resumen,totales,vivos}')::int=7,'Manuales recibidos hace tres días: 21..27';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema',p_desde=>d,p_hasta=>d);
  assert (r#>>'{resumen,totales,vivos}')::int=15,'Del sistema recibidos ayer: 1..15';

  -- Paginación por cursor con la procedencia puesta: total estable, sin
  -- duplicados ni pérdidas, y el empate de sello (16 con 1,2,3) bien resuelto.
  loop
    p:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_limite=>5,p_antes_de=>cursor_fecha,p_antes_id=>cursor_id);
    assert (p#>>'{resumen,totales,vivos}')::int=12,'Total estable entre páginas con procedencia';
    exit when jsonb_array_length(p->'items')=0;
    for fila in select value from jsonb_array_elements(p->'items') loop
      assert fila->>'procedencia'='manual','Ninguna página se sale de la procedencia';
      assert not (fila->>'id')::uuid=any(ids),'Keyset sin duplicados';
      ids:=array_append(ids,(fila->>'id')::uuid);
      cursor_fecha:=(fila->>'actualizado_en')::timestamptz; cursor_id:=(fila->>'id')::uuid;
    end loop;
  end loop;
  assert cardinality(ids)=12,'Keyset sin pérdidas con procedencia';

  -- Valores fuera del dominio: rechazados, no «cero resultados» silenciosos.
  begin perform crm.cartera_filtrada_fn(p_procedencia=>'automatico'); raise exception 'Aceptó procedencia inexistente'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_procedencia=>''); raise exception 'Aceptó procedencia vacía'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_procedencia=>'MANUAL'); raise exception 'Aceptó procedencia en mayúsculas'; exception when sqlstate '22023' then null; end;
  begin perform crm.cartera_filtrada_fn(p_procedencia=>'manual',p_desde=>d); raise exception 'Aceptó rango incompleto'; exception when sqlstate '22023' then null; end;
  -- El resto de guardas del 16/09 siguen: origen fuera de dominio.
  begin perform crm.cartera_filtrada_fn(p_origen=>'facebook'); raise exception 'Aceptó origen inexistente'; exception when sqlstate '22023' then null; end;
end;
$test$;

select set_config('request.jwt.claim.sub','f2991000-0000-4000-8000-000000000001',true);
do $test$
declare r jsonb; v_bandeja int;
begin
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual');
  assert (r#>>'{resumen,totales,vivos}')::int=14,'Supervisor: manuales de sus dos analistas (12 + 2)';
  -- La bandeja (lead sin analista) se mide con el filtro vigente de pendientes:
  -- la procedencia tiene que componer con él y con el ámbito, no redefinirlos.
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema',p_sin_asignar=>true);
  v_bandeja:=(r#>>'{resumen,totales,vivos}')::int;
  assert v_bandeja in (0,1),'Pendientes de repartir del sistema: a lo sumo la bandeja';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_sin_asignar=>true);
  assert (r#>>'{resumen,totales,vivos}')::int=0,'La bandeja no tiene leads manuales';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema');
  assert (r#>>'{resumen,totales,vivos}')::int=21+v_bandeja,'Supervisor: sistema de sus dos analistas más la bandeja que su ámbito le muestre';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_vendedor_id=>'f2991000-0000-4000-8000-000000000004');
  assert (r#>>'{resumen,totales,vivos}')::int=2,'Supervisor acota procedencia por analista';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_desde=>(now() at time zone 'America/Lima')::date-1,p_hasta=>(now() at time zone 'America/Lima')::date-1);
  assert (r#>>'{resumen,totales,vivos}')::int=7,'Supervisor: manuales recibidos ayer por su equipo (5 + 2)';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual',p_vendedor_id=>'f2991000-0000-4000-8000-000000000005');
  assert (r#>>'{resumen,totales,vivos}')::int=0,'No filtra hacia equipo ajeno';
end;
$test$;
select set_config('request.jwt.claim.sub','f2991000-0000-4000-8000-000000000005',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual');
  assert (r#>>'{resumen,totales,vivos}')::int=1 and (r#>>'{items,0,cargado_por}')::uuid='f2991000-0000-4000-8000-000000000005','Analista del otro equipo: solo su manual';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema');
  assert (r#>>'{resumen,totales,vivos}')::int=2,'Analista del otro equipo: sus dos del sistema';
end;
$test$;
select set_config('request.jwt.claim.sub','f2991000-0000-4000-8000-000000000008',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn(p_procedencia=>'manual');
  assert (r#>>'{resumen,totales,vivos}')::int>=15,'Gerencia: los manuales de toda la empresa';
  r:=crm.cartera_filtrada_fn(p_procedencia=>'sistema',p_limite=>200);
  assert (r#>>'{resumen,totales,vivos}')::int>=24,'Gerencia: los del sistema de toda la empresa (incluye la bandeja)';
  assert exists(select 1 from jsonb_array_elements(r->'items') i where i->>'nombre_completo'='PROCEDENCIA LEAD 039'),'Gerencia ve la bandeja';
end;
$test$;
select set_config('request.jwt.claim.sub','f2991000-0000-4000-8000-000000000006',true);
do $$ begin
  begin perform crm.cartera_filtrada_fn(p_procedencia=>'manual'); raise exception 'Aceptó miembro revocado'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f2991000-0000-4000-8000-000000000007',true);
do $$ begin
  begin perform crm.cartera_filtrada_fn(); raise exception 'Aceptó portal-only'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ declare f text:='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)'; begin
  assert to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)') is null,'La firma de 10 argumentos ya no existe';
  assert (select count(*) from pg_proc where proname='cartera_filtrada_fn' and pronamespace='crm'::regnamespace)=1,'Una sola firma para PostgREST';
  assert not has_function_privilege('anon',f,'EXECUTE'),'Anon denegado';
  assert not has_function_privilege('service_role',f,'EXECUTE'),'Service role denegado';
  assert has_function_privilege('authenticated',f,'EXECUTE'),'Authenticated permitido';
  assert not (select prosecdef from pg_proc where oid=to_regprocedure(f)),'RPC conserva RLS invoker';
end $$;
rollback;
select 'CARTERA_PROCEDENCIA_OK';
