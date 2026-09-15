import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {sql,ajustes} from './banco-local.mjs';

const migracion=readFileSync(new URL('../../migrations/20260915170237_crm_ficha_lectura_individual.sql',import.meta.url),'utf8')
  .replace(/^begin;\s*/m,'').replace(/^commit;\s*$/m,'');
const a=JSON.parse(sql(`select jsonb_build_object(
  'gerencia',(select perfil_id from crm.equipo where activo and rol_crm='gerencia' order by perfil_id limit 1),
  'analista',(select perfil_id from crm.equipo where activo and rol_crm='vendedor' order by perfil_id limit 1),
  'ajeno',(select perfil_id from crm.equipo where activo and rol_crm='vendedor' order by perfil_id offset 1 limit 1));`));
const persona="md5('ficha-volumen-persona-2')::uuid";
const fixtures=`
-- Solo en esta copia sintética; las escrituras y ajustes terminan en ROLLBACK.
set local session_replication_role='replica';
insert into auth.users(id,aud,role,email)
 select md5('ficha-volumen-perfil-'||n)::uuid,'authenticated','authenticated','ficha-volumen-'||n||'@example.invalid'
 from generate_series(1,460) n;
insert into public.perfiles(id,nombre_completo,correo,dni,asesor_perfil_id)
 select md5('ficha-volumen-perfil-'||n)::uuid,'PERSONA SINTETICA '||n,'ficha-volumen-'||n||'@example.invalid',
 (78000000+n)::text,case when n<=14 then '${a.analista}'::uuid else '${a.ajeno}'::uuid end
 from generate_series(1,460) n;
insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
 select md5('ficha-volumen-persona-'||n)::uuid,md5('ficha-volumen-perfil-'||n)::uuid,
 case when n<=14 then '${a.analista}'::uuid else '${a.ajeno}'::uuid end from generate_series(1,460) n;
insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,inversionista_id)
 select md5('ficha-volumen-lead-'||n)::uuid,'PERSONA SINTETICA '||n,'+51986'||lpad(n::text,6,'0'),1000,
 case when n<=14 then '${a.analista}'::uuid else '${a.ajeno}'::uuid end,
 case when n<=460 then md5('ficha-volumen-persona-'||n)::uuid end from generate_series(1,1732) n;
insert into public.contratos
 select (jsonb_populate_record(null::public.contratos,to_jsonb(t)||jsonb_build_object(
 'id',md5('ficha-volumen-contrato-'||n)::uuid,'numero_contrato','FICHA-VOLUMEN-'||n,
 'cliente_id',md5('ficha-volumen-perfil-'||(1+(n-1)%460))::uuid,
 'analista_cierre_id',case when 1+(n-1)%460<=14 then '${a.analista}'::uuid else '${a.ajeno}'::uuid end,
 'es_demo',false,'categoria','nuevo','capital',10000,'tasa_anual',12,
 'fecha_inicio',current_date,'fecha_vencimiento',current_date+365,'fecha_cierre_comercial',current_date))).*
 from (select * from public.contratos where estado='activo' and not es_demo order by id limit 1) t
 cross join generate_series(1,538) n;
insert into public.cronograma_pagos(id,contrato_id,numero_cuota,fecha_programada,monto_programado,estado,tipo)
 select md5('ficha-volumen-cuota-'||n||'-'||q)::uuid,md5('ficha-volumen-contrato-'||n)::uuid,q,
 (current_date+make_interval(months=>q))::date,100,'pendiente','cuota'
 from generate_series(1,538) n cross join generate_series(1,12) q;
set local session_replication_role='origin';
analyze public.perfiles; analyze public.contratos; analyze public.cronograma_pagos;
analyze crm.inversionistas; analyze crm.leads;
update crm.multiempresa_flags set activo=true
 where nombre in ('resolver_en_puertas','ficha_360_neutral','inversiones_escritura','postventa_neutral');
`;
function mediciones(fase) {
 return `do $medir$
 declare a record; t0 timestamptz; t1 timestamptz; dato jsonb; n integer; visible integer;
 begin
 for a in select * from (values('gerencia','${a.gerencia}'::uuid),('analista','${a.analista}'::uuid)) x(rol,uid) loop
  perform set_config('request.jwt.claim.sub',a.uid::text,true);
  for n in 0..4 loop
   t0:=clock_timestamp();
   select coalesce(jsonb_agg(to_jsonb(p) order by p.inversionista_id),'[]') into dato
    from private.cartera_f5_personas_visibles() p;
   t1:=clock_timestamp();
   insert into prueba_mediciones values('${fase}',a.rol,'nucleo_listado',n,extract(epoch from t1-t0)*1000,md5(dato::text));
   visible:=jsonb_array_length(dato);
   t0:=clock_timestamp();
   set local role authenticated;
   dato:=crm.inversionista_ficha_fn(${persona});
   reset role;
   t1:=clock_timestamp();
   if dato#>'{persona}' is null or (dato->>'inversiones_total')::int<>2 then raise exception 'Ficha de volumen incompleta'; end if;
   insert into prueba_mediciones values('${fase}',a.rol,'ficha_completa',n,extract(epoch from t1-t0)*1000,md5(dato::text));
  end loop;
  insert into prueba_visibles values('${fase}',a.rol,visible);
 end loop;
 end; $medir$;`;
}
const salida=sql(`begin;${ajustes}${fixtures}
create temporary table prueba_mediciones(fase text,rol text,operacion text,muestra int,ms numeric,huella text);
create temporary table prueba_visibles(fase text,rol text,total int);
${mediciones('antes')}
${migracion}
${mediciones('despues')}
do $paridad$ begin
 if exists(select 1 from prueba_mediciones group by rol,operacion having count(distinct huella)<>1) then
  raise exception 'Cambió una ficha o listado al optimizar'; end if;
end; $paridad$;
select jsonb_build_object('resultado','PASS','fecha',clock_timestamp(),'base',current_database(),
 'volumen',jsonb_build_object('personas',(select count(*) from crm.inversionistas),'perfiles',(select count(*) from public.perfiles),
  'leads',(select count(*) from crm.leads),'fuentes',(select jsonb_agg(x) from (select empresa,count(*) total from private.cartera_f5_fuentes_reales() group by empresa) x),
  'cuotas',(select count(*) from public.cronograma_pagos)),
 'visibles',(select jsonb_agg(x) from prueba_visibles x),
 'medidas',(select jsonb_agg(x) from prueba_mediciones x),
 'estadisticas',(select jsonb_agg(x) from (select fase,rol,operacion,count(*) muestras,
  percentile_cont(0.5) within group(order by ms)::numeric(12,3) mediana_ms,
  min(ms)::numeric(12,3) minimo_ms,max(ms)::numeric(12,3) maximo_ms
  from prueba_mediciones where muestra>0 group by fase,rol,operacion order by rol,operacion,fase) x));
rollback;`);
const r=JSON.parse(salida);
assert.equal(r.resultado,'PASS');
const evidencias=new URL('./evidencias/',import.meta.url);mkdirSync(evidencias,{recursive:true});
writeFileSync(new URL('volumen-local.json',evidencias),JSON.stringify(r,null,2)+'\n');
console.log(JSON.stringify({...r,medidas:undefined}));
