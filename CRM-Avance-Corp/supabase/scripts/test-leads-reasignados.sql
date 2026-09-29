-- Oráculo de Leads reasignados. Solo en banco aislado con la migración instalada.
-- Los fixtures viven dentro de la transacción y se revierten íntegros.
begin;
set local session_replication_role=replica;

insert into public.perfiles(id,nombre_completo,rol,activo)
select ('f2aa1000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'REASIGNADOS ACTOR '||n,'comercial',true
from generate_series(1,5) n;
-- 1 supervisor, 2 analista A, 3 analista B, 4 gerencia, 5 analista ajeno.
insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
select ('f2aa1000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n=1 then 'supervisor' when n=4 then 'gerencia' else 'vendedor' end,
  case when n in (2,3) then 'f2aa1000-0000-4000-8000-000000000001'::uuid end,
  true
from generate_series(1,5) n;

-- 1 primera entrega directa, 2 primera entrega desde cola, 3 A->B,
-- 4 A->cola->B, 5 A->cola->A, 6 A->B->A, 7 manual A->B,
-- 8 aparcado tras A, 9 reasignado en otro equipo, 10 baja lógica.
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,
  moneda,vendedor_id,asignado_supervisor_id,creado_por,alta_manual,creado_en,actualizado_en,activo)
select ('f2aa2000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'REASIGNADO LEAD '||lpad(n::text,2,'0'), '5199922'||lpad(n::text,4,'0'),
  case when n=7 then 'referido' else 'landing' end,
  case when n=4 then 'contactado' else 'nuevo' end,
  1000,'PEN',
  case when n in (1,2,5,6,10) then 'f2aa1000-0000-4000-8000-000000000002'::uuid
    when n in (3,4,7) then 'f2aa1000-0000-4000-8000-000000000003'::uuid
    when n=9 then 'f2aa1000-0000-4000-8000-000000000005'::uuid end,
  case when n=8 then 'f2aa1000-0000-4000-8000-000000000001'::uuid end,
  case when n=7 then 'f2aa1000-0000-4000-8000-000000000002'::uuid end,
  n=7, now()-interval '1 day', now()-n*interval '1 minute', n<>10
from generate_series(1,10) n;

insert into crm.actividades(lead_id,tipo,metadata,creado_en)
select ('f2aa2000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'reasignacion',
  jsonb_build_object('vendedor_anterior',
    case when n=2 then null
      when n=6 then 'f2aa1000-0000-4000-8000-000000000003'
      else 'f2aa1000-0000-4000-8000-000000000002' end,
    'vendedor_nuevo',case when n in (4,5,8) then null
      when n=9 then 'f2aa1000-0000-4000-8000-000000000005'
      else 'f2aa1000-0000-4000-8000-000000000003' end),
  now()-interval '30 minutes'
from (values(2),(3),(4),(5),(6),(7),(8),(9),(10)) v(n);
insert into crm.actividades(lead_id,tipo,metadata,creado_en)
values
  ('f2aa2000-0000-4000-8000-000000000004','reasignacion',
    '{"vendedor_anterior":null,"vendedor_nuevo":"f2aa1000-0000-4000-8000-000000000003"}'::jsonb,
    now()-interval '29 minutes'),
  ('f2aa2000-0000-4000-8000-000000000005','reasignacion',
    '{"vendedor_anterior":null,"vendedor_nuevo":"f2aa1000-0000-4000-8000-000000000002"}'::jsonb,
    now()-interval '29 minutes');

-- Contrato REAL del trigger (sin eventos fabricados): la primera entrega
-- emite anterior NULL, A->A no emite, A->B sí; pasar por bandeja no borra
-- la trayectoria. Este bloque se revierte antes del oráculo de cifras.
savepoint trigger_oracle;
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,
  moneda,vendedor_id,asignado_supervisor_id,creado_en,actualizado_en,activo)
values ('f2aa2000-0000-4000-8000-000000000011','REASIGNADO TRIGGER REAL',
  '51999220011','landing','nuevo',1000,'PEN',null,
  'f2aa1000-0000-4000-8000-000000000001',now(),now(),true);
set local session_replication_role=origin;
update crm.leads set vendedor_id='f2aa1000-0000-4000-8000-000000000002',
  asignado_supervisor_id=null where id='f2aa2000-0000-4000-8000-000000000011';
do $test$
begin
  assert (select count(*) from crm.actividades where lead_id='f2aa2000-0000-4000-8000-000000000011'
    and tipo='reasignacion' and metadata->>'vendedor_anterior' is not null)=0,
    'primera entrega no tiene analista anterior';
end;
$test$;
update crm.leads set vendedor_id='f2aa1000-0000-4000-8000-000000000002'
  where id='f2aa2000-0000-4000-8000-000000000011';
do $test$
begin
  assert (select count(*) from crm.actividades where lead_id='f2aa2000-0000-4000-8000-000000000011'
    and tipo='reasignacion')=1,'A->A no crea evento';
end;
$test$;
update crm.leads set vendedor_id='f2aa1000-0000-4000-8000-000000000003'
  where id='f2aa2000-0000-4000-8000-000000000011';
do $test$
begin
  assert (select count(*) from crm.actividades where lead_id='f2aa2000-0000-4000-8000-000000000011'
    and tipo='reasignacion' and metadata->>'vendedor_anterior'='f2aa1000-0000-4000-8000-000000000002')=1,
    'A->B conserva analista anterior';
end;
$test$;
update crm.leads set vendedor_id=null,
  asignado_supervisor_id='f2aa1000-0000-4000-8000-000000000001'
  where id='f2aa2000-0000-4000-8000-000000000011';
update crm.leads set asignado_supervisor_id=null
  where id='f2aa2000-0000-4000-8000-000000000011';
do $test$
begin
  assert (select metadata->>'vendedor_anterior' from crm.actividades
    where lead_id='f2aa2000-0000-4000-8000-000000000011'
      and metadata->>'movimiento'='sale_bandeja' limit 1) is null,
    'solo cambiar la bandeja no inventa analista anterior';
end;
$test$;
update crm.leads set vendedor_id='f2aa1000-0000-4000-8000-000000000003'
  where id='f2aa2000-0000-4000-8000-000000000011';
do $test$
begin
  assert (select count(*) from crm.actividades where lead_id='f2aa2000-0000-4000-8000-000000000011'
    and tipo='reasignacion' and metadata->>'vendedor_anterior' is not null)=2,
    'reparto desde bandeja conserva la historia B anterior';
end;
$test$;
rollback to savepoint trigger_oracle;
set local session_replication_role=origin;
set local role authenticated;

select set_config('request.jwt.claim.sub','f2aa1000-0000-4000-8000-000000000004',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn();
  assert r->'reasignados'='false'::jsonb,'sin filtro: eco false';
  assert (r#>>'{resumen,totales,vivos}')::int=9,'gerencia: nueve leads activos';
  assert (r#>>'{resumen,totales,reasignados}')::int=6,'gerencia: seis reasignados';
  assert (r#>'{items,0}') ? 'reasignado','cada fila declara el indicador';
  assert (crm.resumen_cartera_fn()#>>'{totales,vivos}')::int=9,
    'el consumidor de cartera sigue resolviendo la firma ampliada';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true);
  assert r->'reasignados'='true'::jsonb,'filtro: eco true';
  assert (r#>>'{resumen,totales,vivos}')::int=6,'gerencia: seis filtrados';
  assert (r#>>'{resumen,totales,reasignados}')::int=6,'contador y base filtrada coinciden';
  assert jsonb_array_length(r->'items')=6,'las seis filas llegan en primera pagina';
  assert not exists(select 1 from jsonb_array_elements(r->'items') i
    where i->'reasignado'<>'true'::jsonb),'ninguna fila ajena en el filtro';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true,p_procedencia=>'manual');
  assert (r#>>'{resumen,totales,vivos}')::int=1
    and r#>>'{items,0,nombre_completo}'='REASIGNADO LEAD 07',
    'reasignado compone con alta manual, sin sustituirla';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true,p_etapa=>'contactado');
  assert (r#>>'{resumen,totales,vivos}')::int=1
    and r#>>'{items,0,nombre_completo}'='REASIGNADO LEAD 04',
    'etapa y reasignado recortan el mismo total';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true,
    p_vendedor_id=>'f2aa1000-0000-4000-8000-000000000003');
  assert (r#>>'{resumen,totales,vivos}')::int=3,
    'analista y reasignado componen sin mezclar ambitos';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true,p_texto=>'LEAD 05');
  assert (r#>>'{resumen,totales,vivos}')::int=1,
    'busqueda y reasignado usan la misma base';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true,p_limite=>2);
  assert (r#>>'{resumen,totales,vivos}')::int=6 and jsonb_array_length(r->'items')=2,
    'primera pagina conserva el total';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true,p_limite=>2,
    p_antes_de=>(r#>>'{items,1,actualizado_en}')::timestamptz,
    p_antes_id=>(r#>>'{items,1,id}')::uuid);
  assert (r#>>'{resumen,totales,vivos}')::int=6 and jsonb_array_length(r->'items')=2,
    'cursor no recorta la cifra global';
end;
$test$;

select set_config('request.jwt.claim.sub','f2aa1000-0000-4000-8000-000000000002',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn();
  assert (r#>>'{resumen,totales,vivos}')::int=4,'A solo ve su cartera';
  assert (r#>>'{resumen,totales,reasignados}')::int=2,
    'A: primera entrega no cuenta; retorno tras la bandeja si';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true);
  assert (r#>>'{resumen,totales,vivos}')::int=2,
    'A ve al que regreso tras B y al que regreso de la bandeja';
end;
$test$;

select set_config('request.jwt.claim.sub','f2aa1000-0000-4000-8000-000000000003',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn();
  assert (r#>>'{resumen,totales,vivos}')::int=3,'B solo ve su cartera';
  assert (r#>>'{resumen,totales,reasignados}')::int=3,'B: directo, via cola y manual';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true);
  assert (r#>>'{resumen,totales,vivos}')::int=3,'filtro no pierde ninguno de B';
end;
$test$;
do $test$
begin
  begin
    insert into crm.actividades(lead_id,tipo,metadata,creado_por)
    values ('f2aa2000-0000-4000-8000-000000000003','reasignacion',
      '{"vendedor_anterior":"f2aa1000-0000-4000-8000-000000000002"}'::jsonb,
      'f2aa1000-0000-4000-8000-000000000003');
    raise exception 'un analista pudo falsificar la marca';
  exception when insufficient_privilege then null;
  end;
  begin
    update crm.actividades set metadata='{"vendedor_anterior":null}'::jsonb
    where lead_id='f2aa2000-0000-4000-8000-000000000003' and tipo='reasignacion';
    raise exception 'un analista pudo alterar el evento que sostiene la marca';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from crm.actividades
    where lead_id='f2aa2000-0000-4000-8000-000000000003' and tipo='reasignacion';
    raise exception 'un analista pudo borrar el evento que sostiene la marca';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

select set_config('request.jwt.claim.sub','f2aa1000-0000-4000-8000-000000000001',true);
do $test$
declare r jsonb;
begin
  r:=crm.cartera_filtrada_fn(p_reasignados=>true);
  assert (r#>>'{resumen,totales,vivos}')::int=5,'supervisor ve cinco y no el otro equipo';
  assert not exists(select 1 from jsonb_array_elements(r->'items') i
    where i->>'nombre_completo'='REASIGNADO LEAD 09'),'sin filtración entre equipos';
  r:=crm.cartera_filtrada_fn(p_reasignados=>true,p_sin_asignar=>true);
  assert (r#>>'{resumen,totales,vivos}')::int=0,'aparcado no aparece como reasignado';
end;
$test$;

set local role anon;
do $test$
begin
  begin
    perform crm.cartera_filtrada_fn(p_reasignados=>true);
    raise exception 'anon obtuvo la cartera';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

rollback;
