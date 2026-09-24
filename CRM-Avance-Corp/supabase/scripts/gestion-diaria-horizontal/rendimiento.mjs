import { readFileSync } from 'node:fs';
import { sql } from './banco.mjs';
const fixture=readFileSync(new URL('test-pendientes.sql',import.meta.url),'utf8').split('create temporary table h3_paginas')[0];
const salida=sql(`${fixture}
create function pg_temp.medir(analista uuid) returns jsonb language plpgsql as $$
declare inicio timestamptz; tiempos numeric[]:='{}'; p jsonb; i int; begin
  for i in 1..5 loop
    inicio:=clock_timestamp(); p:=crm.gestion_diaria_pendientes_fn(analista,false,25);
    tiempos:=array_append(tiempos,round(extract(epoch from clock_timestamp()-inicio)*1000,3));
    if p#>>'{resumen,tareas_pendientes}'<>'1008' then raise exception 'Fixture incompleto'; end if;
  end loop;
  return jsonb_build_object('tareas',1008,'limite',25,'milisegundos',tiempos,'rol','authenticated');
end $$;
select set_config('request.jwt.claim.sub',supervisor::text,true) from h3_actores;
set local role authenticated;
select 'H3_MEDIDA:'||pg_temp.medir(vendedor)::text from h3_actores;
reset role; rollback;`);
console.log(salida.split('\n').find(l=>l.startsWith('H3_MEDIDA:')));
