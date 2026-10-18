\set ON_ERROR_STOP on
begin;
\ir fixtures.sql
\ir cartera-anterior.sql
-- Mismo envoltorio vivo, cambiando únicamente la consulta a su versión previa.
do $$ begin
  execute replace(replace(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure),
    'FUNCTION crm.resumen_cartera_fn()', 'FUNCTION pg_temp.resumen_anterior()'),
    'crm.cartera_filtrada_fn(', 'pg_temp.cartera_anterior(');
end $$;
create temporary table comprobaciones(nombre text);
grant select,insert on comprobaciones to authenticated,anon;
create function pg_temp.exigir(v boolean,nombre text) returns void language plpgsql as $$
begin
  if v is distinct from true then raise exception 'FAIL: %',nombre; end if;
  insert into comprobaciones values(nombre);
end;
$$;

select pg_temp.exigir((select count(*)=1 from pg_proc where pronamespace='crm'::regnamespace and proname='cartera_filtrada_fn'),'firma integrada inequívoca');
select pg_temp.exigir((select count(*)=1 from pg_proc where pronamespace='crm'::regnamespace and proname='cartera_pagina_fn'),'firma anterior inequívoca');
select pg_temp.exigir(has_column_privilege('authenticated','crm.leads','campania_origen','SELECT')
  and not has_column_privilege('authenticated','crm.leads','campania_origen','UPDATE')
  and not has_column_privilege('authenticated','crm.leads','campania_origen','INSERT'),'campaña solo de lectura humana');
select pg_temp.exigir(not has_function_privilege('anon','crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text)','EXECUTE'),'anon sin ejecutar cartera');
select pg_temp.exigir(not has_function_privilege('anon','crm.cartera_pagina_fn(integer,timestamptz,uuid,text,uuid,boolean,text)','EXECUTE'),'anon sin ejecutar lector anterior');
select pg_temp.exigir((select count(*)=2 from pg_proc where pronamespace='crm'::regnamespace
  and proname in ('cartera_filtrada_fn','cartera_pagina_fn') and length(obj_description(oid,'pg_proc'))>30),'documentación de ambas funciones conservada');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $cartera$
declare a jsonb; b jsonb; anterior jsonb; actual jsonb; c jsonb; ultima jsonb; valor text; hoy date := (now() at time zone 'America/Lima')::date;
begin
  anterior := pg_temp.cartera_anterior(p_limite=>200,p_texto=>'F3 FASE2');
  actual := crm.cartera_filtrada_fn(p_limite=>200,p_texto=>'F3 FASE2');
  perform pg_temp.exigir(actual->'resumen'=anterior->'resumen','sin filtro conserva todas las cifras previas');
  perform pg_temp.exigir((select jsonb_agg(x-'campania_origen' order by ord) from jsonb_array_elements(actual->'items') with ordinality as z(x,ord))=anterior->'items','sin filtro conserva todas las filas previas y su orden');
  perform pg_temp.exigir(actual->'campania_origen'='null'::jsonb,'eco nulo al no filtrar');
  perform pg_temp.exigir((actual#>>'{resumen,totales,vivos}')::int=135,'ámbito propio completo');
  perform pg_temp.exigir((select count(*)=60 from jsonb_array_elements(actual->'items') x where x->'campania_origen'='null'::jsonb),'históricos conservan campaña nula');

  a := crm.cartera_filtrada_fn(p_limite=>51,p_texto=>'F3 FASE2',p_campania_origen=>'Formulario 3');
  perform pg_temp.exigir(a->>'campania_origen'='Formulario 3','eco confirma campaña solicitada');
  perform pg_temp.exigir(jsonb_array_length(a->'items')=51,'primera página trae 50 más centinela');
  perform pg_temp.exigir((a#>>'{resumen,totales,vivos}')::int=70,'total cuenta más allá de la primera página');
  perform pg_temp.exigir((a#>>'{resumen,capital,asignado,pen}')::numeric=35000 and (a#>>'{resumen,capital,asignado,usd}')::numeric=35000,'capital por moneda del conjunto completo');
  perform pg_temp.exigir((select sum((x->>'n')::int)=70 from jsonb_array_elements(a#>'{resumen,embudo}') x),'embudo concuerda con total filtrado');
  perform pg_temp.exigir((select bool_and(x->>'campania_origen'='Formulario 3' and x->>'origen'='formulario') from jsonb_array_elements(a->'items') x),'filas conservan campaña y canal separados');
  ultima := a->'items'->49;
  b := crm.cartera_filtrada_fn(p_limite=>51,p_texto=>'F3 FASE2',p_campania_origen=>'Formulario 3',
    p_antes_de=>(ultima->>'actualizado_en')::timestamptz,p_antes_id=>(ultima->>'id')::uuid);
  perform pg_temp.exigir(jsonb_array_length(b->'items')=20,'segunda página completa los 70');
  perform pg_temp.exigir(b->'resumen'=a->'resumen','página siguiente conserva cifras completas');
  perform pg_temp.exigir((select count(distinct x->>'id')=70 from (
    select x from jsonb_array_elements(a->'items') with ordinality z(x,ord) where ord<=50
    union all select x from jsonb_array_elements(b->'items') x) z),'cursor con empate no repite ni pierde leads');
  perform pg_temp.exigir(crm.cartera_filtrada_fn(p_limite=>51,p_texto=>'F3 FASE2',p_campania_origen=>'Formulario 3')=a,'recarga devuelve el mismo conjunto y cifras');
  perform pg_temp.exigir((select campania_origen='Formulario 3' from crm.leads where id=(ultima->>'id')::uuid),'ficha por id coincide con la lista');
  perform pg_temp.exigir((select count(*)=70 from crm.cartera_pagina_fn(p_limite=>200,p_texto=>'F3 FASE2') where campania_origen='Formulario 3'),'lector antiguo también transporta campaña');
  perform pg_temp.exigir(crm.resumen_cartera_fn()=pg_temp.resumen_anterior(),'envoltorio conserva toda su respuesta anterior');
  c := crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2',p_origen=>'landing');
  perform pg_temp.exigir(jsonb_array_length(c->'items')=0 and (c#>>'{resumen,totales,vivos}')::int=0,'campaña y canal se combinan sin inventar resultados');
  c := crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2 061',p_origen=>'formulario',p_etapa=>'nuevo',p_procedencia=>'sistema');
  perform pg_temp.exigir((c#>>'{resumen,totales,vivos}')::int=1,'campaña combina búsqueda etapa canal y procedencia');
  c := crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2',p_desde=>hoy,p_hasta=>hoy);
  perform pg_temp.exigir((c#>>'{resumen,totales,vivos}')::int=70,'campaña combina recepción por fecha');
  c := crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2',p_vendedor_id=>'f3000000-0000-0000-0000-000000000004');
  perform pg_temp.exigir((c#>>'{resumen,totales,vivos}')::int=0,'filtro de vendedor ajeno no amplía ámbito');
  c := crm.cartera_filtrada_fn(p_campania_origen=>'Campaña anterior',p_texto=>'F3 FASE2');
  perform pg_temp.exigir((c#>>'{resumen,totales,vivos}')::int=5,'campañas anteriores no se reclasifican como Formulario 3');
  foreach valor in array array['', ' formulario 3', 'formulario 3', repeat('x',81), 'x'||chr(133)] loop
    begin
      perform crm.cartera_filtrada_fn(p_campania_origen=>valor);
      raise exception 'Filtro inválido admitido';
    exception when invalid_parameter_value then perform pg_temp.exigir(true,'campaña inválida rechazada'); end;
  end loop;
  begin
    update crm.leads set campania_origen='Otra' where id=(ultima->>'id')::uuid;
    raise exception 'Campaña editable';
  exception when insufficient_privilege then perform pg_temp.exigir(true,'edición de campaña bloqueada'); end;
  update crm.leads set nota='Edición permitida de un lead con campaña' where id=(ultima->>'id')::uuid;
  perform pg_temp.exigir((select nota='Edición permitida de un lead con campaña' and campania_origen='Formulario 3'
    from crm.leads where id=(ultima->>'id')::uuid),'editar un campo permitido conserva la campaña');
end;
$cartera$;

select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select pg_temp.exigir((crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2')#>>'{resumen,totales,vivos}')::int=70,'supervisor conserva su equipo');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.exigir((crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2')#>>'{resumen,totales,vivos}')::int=79,'gerencia conserva ámbito global');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000008","role":"authenticated"}',true);
select pg_temp.exigir((crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2')#>>'{resumen,totales,vivos}')::int=79,'Directorio conserva lectura global');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select pg_temp.exigir((crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2')#>>'{resumen,totales,vivos}')::int=9,'otro analista solo ve su cartera');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000006","role":"authenticated"}',true);
select pg_temp.exigir((crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3',p_texto=>'F3 FASE2')#>>'{resumen,totales,vivos}')::int=0,'coordinación no obtiene filas ni conteos ajenos');
select set_config('request.jwt.claims','{"sub":"f3000000-0000-0000-0000-000000000007","role":"authenticated"}',true);
do $$ begin
  begin
    perform crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3');
    raise exception 'Miembro inactivo admitido';
  exception when insufficient_privilege then perform pg_temp.exigir(true,'miembro inactivo rechazado'); end;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
  begin
    perform crm.cartera_filtrada_fn(p_campania_origen=>'Formulario 3');
    raise exception 'Sesión anónima admitida';
  exception when insufficient_privilege then perform pg_temp.exigir(true,'sesión sin usuario rechazada'); end;
end $$;
reset role;
select count(*) as comprobaciones from comprobaciones;
rollback;
select 'PASS: cartera, paginación y permisos; fixtures revertidas' as resultado;
