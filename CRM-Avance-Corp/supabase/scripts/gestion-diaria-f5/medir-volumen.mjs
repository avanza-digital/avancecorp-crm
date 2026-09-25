// Ensayo reproducible de volumen, dentro del banco sintético cerrado de F5.
// Incluye conciliación cruda; todas las inserciones terminan en ROLLBACK.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sql } from './banco.mjs';

assert.ok(process.argv.length === 2 || (process.argv.length === 3 && process.argv[2] === '--anio'), 'Sólo se admite --anio');
const diasHistoria = process.argv[2] === '--anio' ? 365 : 30;
const preparacion = readFileSync(new URL('./test-pulso-habitos.sql', import.meta.url), 'utf8')
  .split('create temporary table f5_fotos')[0];
const salida = sql(`${preparacion}
alter table crm.actividades disable trigger user;
insert into crm.actividades(lead_id,tipo,creado_por,creado_en,metadata)
select f.lead_1,case when n%10=1 then 'llamada_no_contestada' else 'llamada_realizada' end,
  (array[f.a,f.b,f.c])[1+(n%3)],
  ((f.dia-d)+time '09:00'+(n%540)*interval '1 minute') at time zone 'America/Lima',
  jsonb_build_object('resultado',case when n%10=0 then 'numero_errado' when n%10=1 then 'no_contesto' else 'interesado' end)
from f5_actores f cross join generate_series(0,${diasHistoria - 1}) d cross join generate_series(1,1000) n;
alter table crm.actividades enable trigger user;
analyze crm.actividades;
analyze crm.tareas;
create temporary table f5_tiempos(rpc text,iteracion integer,ms numeric,bytes integer);
grant all on f5_tiempos to authenticated;
select set_config('request.jwt.claim.sub',gerente::text,true) from f5_actores;
set local role authenticated;
do $medir$
declare v_fecha date; v_inicio timestamptz; v_foto jsonb; v_esperadas bigint; v_dias integer; v_i integer;
begin
  select dia into v_fecha from f5_actores;
  for v_i in 1..5 loop
    v_inicio:=clock_timestamp();
    v_foto:=crm.gestion_diaria_pulso_fn(v_fecha);
    insert into f5_tiempos values('pulso',v_i,1000*extract(epoch from clock_timestamp()-v_inicio),octet_length(v_foto::text));
    perform pg_temp.afirmar(v_foto#>>'{actual,llamadas}'='1009'
      and v_foto#>>'{actual,utiles}'='908' and v_foto#>>'{actual,contestadas}'='805',
      'volumen: conciliación manual del día 1009 / 908 / 805');
    foreach v_dias in array array[7,14,30] loop
      v_inicio:=clock_timestamp();
      v_foto:=crm.gestion_diaria_habitos_fn(v_fecha,v_dias);
      insert into f5_tiempos values('habitos_'||v_dias,v_i,1000*extract(epoch from clock_timestamp()-v_inicio),octet_length(v_foto::text));
      select count(*) into v_esperadas from crm.actividades a
      where a.tipo in ('llamada_realizada','llamada_no_contestada')
        and a.creado_en>=(v_fecha-v_dias+1)::timestamp at time zone 'America/Lima'
        and a.creado_en<(v_fecha+1)::timestamp at time zone 'America/Lima';
      perform pg_temp.afirmar((v_foto#>>'{operacion,llamadas}')::bigint=v_esperadas,
        'volumen: hábitos concilia contra registros originales');
    end loop;
  end loop;
end $medir$;
select jsonb_build_object('estado','PASS','llamadas_insertadas',${diasHistoria * 1000},'dias_historia',${diasHistoria},
  'analistas_activos',(select count(*) from private.gestion_diaria_pulso_roster()),
  'tareas_vencidas',1008,'muestras_por_rpc',5,
  'medidas',(select jsonb_agg(to_jsonb(x) order by x.rpc) from (
    select rpc,round(min(ms),2) minimo_ms,round(max(ms),2) maximo_ms,
      round((percentile_cont(0.5) within group(order by ms))::numeric,2) mediana_ms,
      round((percentile_cont(0.95) within group(order by ms))::numeric,2) p95_ms,
      max(bytes) respuesta_bytes
    from f5_tiempos group by rpc) x));
rollback;`);
const informe = JSON.parse(salida.split('\n').findLast((linea) => linea.startsWith('{')));
assert.equal(informe.estado, 'PASS');
assert.equal(informe.medidas.length, 4);
console.log(JSON.stringify(informe, null, 2));
